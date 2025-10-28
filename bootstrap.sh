#!/usr/bin/env bash
set -Eeuo pipefail

################################################################################
# Debian Desktop Dev Bootstrap (Fish, Flatpak apps, PPD, GNOME tweaks)
# Idempotent: safe to re-run. Adapt sections as you like.
################################################################################

# === REQUIRED: your dotfiles repo ===
DOTFILES_REPO="https://github.com/LinusAndersson02/dotfiles.git"
DOTFILES_DIR="${HOME}/.dotfiles"
DOTFILES_STOW_DIR="${DOTFILES_DIR}"

# === OPTIONS you can tweak ===
SET_FISH_DEFAULT="true"
GNOME_WORKSPACES="5"
GNOME_FONT_SIZE="12"  # used for UI + monospace
DOCKER_DESKTOP="true" # set "false" to skip Docker Desktop
DOCKER_DESKTOP_DEB_URL="${DOCKER_DESKTOP_DEB_URL:-https://desktop.docker.com/linux/main/amd64/docker-desktop-amd64.deb}"

# Logging helpers
STEP=0
log() {
  STEP=$((STEP + 1))
  printf "\n\033[1;34m[%02d] %s\033[0m\n" "$STEP" "$*"
}
ok() { printf "\033[1;32m[ OK ]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
die() {
  printf "\033[1;31m[FAIL]\033[0m %s\n" "$*\n"
  exit 1
}
trap 'die "Error on line $LINENO. See output above."' ERR

# ------------------------------------------------------------------------------
# 01) Sanity
# ------------------------------------------------------------------------------
log "Sanity checks"
if [[ $(id -u) -eq 0 ]]; then die "Run as a regular user (not root)."; fi
if ! command -v sudo >/dev/null 2>&1; then
  echo "Installing sudo..."
  su -c "apt-get update && apt-get install -y sudo"
  su -c "usermod -aG sudo $(whoami)"
  die "Re-login so sudo group takes effect, then re-run."
fi
if [[ -z "${DOTFILES_REPO}" ]]; then die "Set DOTFILES_REPO at top of script."; fi
export DEBIAN_FRONTEND=noninteractive
ok "Environment looks good"

# ------------------------------------------------------------------------------
# 02) APT baseline (CLI toolchain + fish + Flatpak + fonts + thermals)
# ------------------------------------------------------------------------------
log "APT baseline + CLI toolchain (fish, starship, zoxide, Flatpak, etc.)"
sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get install -y \
  build-essential cmake pkg-config \
  git curl wget ca-certificates gnupg lsb-release \
  unzip zip tar xz-utils jq \
  python3 python3-pip python3-venv pipx \
  gcc g++ gdb valgrind \
  clang clang-format clang-tidy libc++-dev libc++abi-dev \
  stow tmux fish \
  ripgrep fzf fd-find tree htop luarocks \
  bat xclip \
  ufw thermald \
  power-profiles-daemon \
  flatpak \
  fonts-jetbrains-mono \
  alacritty \
  starship zoxide
ok "Base packages installed"

# ------------------------------------------------------------------------------
# 03) Remove or disable packages that conflict with our plan
#     (TLP conflicts with power-profiles-daemon)
# ------------------------------------------------------------------------------
log "Removing/disabling conflicting power tools (TLP) and enabling PPD"
sudo apt-get purge -y tlp tlp-rdw || true
sudo systemctl disable tlp --now 2>/dev/null || true
sudo systemctl enable --now thermald || true
sudo systemctl enable --now power-profiles-daemon || true
# default to balanced profile if available
if command -v powerprofilesctl >/dev/null 2>&1; then powerprofilesctl set balanced || true; fi
ok "Power-profiles-daemon is active (TLP removed)."

# ------------------------------------------------------------------------------
# 04) PATH shims + fd/bat Debian aliasing
# ------------------------------------------------------------------------------
log "Ensuring ~/.local/bin is on PATH + fd/bat shims"
mkdir -p "${HOME}/.local/bin"
grep -q 'HOME/.local/bin' "${HOME}/.profile" 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >>"${HOME}/.profile"
command -v fd >/dev/null 2>&1 || { command -v fdfind >/dev/null 2>&1 && ln -sf "$(command -v fdfind)" "${HOME}/.local/bin/fd"; }
command -v bat >/dev/null 2>&1 || { command -v batcat >/dev/null 2>&1 && ln -sf "$(command -v batcat)" "${HOME}/.local/bin/bat"; }
ok "PATH + shims configured"

# ------------------------------------------------------------------------------
# 05) UFW firewall (deny in / allow out) + optional SSH
# ------------------------------------------------------------------------------
log "Configuring UFW firewall"
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp || true # comment if you never SSH into the laptop
sudo ufw --force enable
ok "UFW enabled"

# ------------------------------------------------------------------------------
# 06) Docker Engine (official repo) + Buildx + Compose plugin
# ------------------------------------------------------------------------------
log "Installing Docker Engine (official repo)"
sudo apt-get remove -y docker docker-engine docker.io containerd runc docker-doc podman-docker || true
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(
  . /etc/os-release && echo "$VERSION_CODENAME"
) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
if ! groups | grep -qw docker; then
  sudo usermod -aG docker "$USER" || true
  warn "Added you to 'docker'. Run: newgrp docker   (or log out/in) to pick it up."
fi
ok "Docker Engine installed"

# ------------------------------------------------------------------------------
# 07) (Optional) Docker Desktop for Linux (no Flatpak; install .deb)
# ------------------------------------------------------------------------------
if [[ "${DOCKER_DESKTOP}" == "true" ]]; then
  log "Installing Docker Desktop for Linux (.deb)"
  mkdir -p /tmp/bootstrap-dd && dd_dir=/tmp/bootstrap-dd
  dd_pkg="${dd_dir}/docker-desktop-amd64.deb"
  curl -fL "${DOCKER_DESKTOP_DEB_URL}" -o "${dd_pkg}"
  sudo apt-get update -y
  sudo apt-get install -y "${dd_pkg}" || true # apt warns about unsandboxed download; per docs, safe to ignore
  systemctl --user enable docker-desktop || true
  ok "Docker Desktop installed (start from apps menu or: systemctl --user start docker-desktop)"
fi

# ------------------------------------------------------------------------------
# 08) Rust toolchain (rustup) + rust-analyzer
# ------------------------------------------------------------------------------
log "Installing Rust toolchain"
if ! command -v rustup >/dev/null 2>&1; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  echo 'source "$HOME/.cargo/env"' >>"${HOME}/.profile"
  # shellcheck disable=SC1090
  source "${HOME}/.cargo/env"
fi
rustup default stable
rustup component add rust-analyzer || true
ok "Rust ready"

# ------------------------------------------------------------------------------
# 09) Node.js via fnm (install latest LTS, set default, enable corepack)
# ------------------------------------------------------------------------------
log "Installing Node via fnm (LTS) + enabling corepack"
if ! command -v fnm >/dev/null 2>&1; then
  curl -fsSL https://fnm.vercel.app/install | bash -s -- --install-dir "$HOME/.local/share/fnm" --skip-shell
  echo 'export PATH="$HOME/.local/share/fnm:$PATH"' >>"$HOME/.profile"
  echo 'eval "$(fnm env --use-on-cd --shell bash)"' >>"$HOME/.profile"
fi
export PATH="$HOME/.local/share/fnm:$PATH"
eval "$(fnm env --use-on-cd --shell bash)"
LTS_VER="$(fnm list-remote --lts --latest | tr -d ' *')"
if [[ -z "$LTS_VER" ]]; then
  warn "Could not resolve latest LTS; installing --lts and selecting newest installed."
  fnm install --lts
  LTS_VER="$(fnm list | awk '/^v[0-9]/{v=$1} END{print v}')"
fi
fnm install "$LTS_VER"
fnm use "$LTS_VER"
fnm default "$LTS_VER"
command -v corepack >/dev/null 2>&1 && corepack enable || true
ok "Node $LTS_VER installed and set as default"

# ------------------------------------------------------------------------------
# 10) Neovim (incremental to latest tag, only rebuild when needed)
# ------------------------------------------------------------------------------
log "Neovim: incremental update to latest stable tag (skip if current)"
sudo apt-get install -y ninja-build gettext cmake unzip curl build-essential ccache
export CCACHE_DIR="${HOME}/.cache/ccache"
mkdir -p "$CCACHE_DIR"
export CC="ccache gcc" CXX="ccache g++"
NVIM_SRC="${HOME}/.local/src/neovim"
mkdir -p "${NVIM_SRC%/*}"
if [[ -d "${NVIM_SRC}/.git" ]]; then
  git -C "${NVIM_SRC}" fetch --tags --force origin
else
  git clone --depth 1 https://github.com/neovim/neovim "${NVIM_SRC}"
  git -C "${NVIM_SRC}" fetch --tags --force origin
fi
LATEST_TAG="$(git -C "${NVIM_SRC}" describe --tags "$(git -C "${NVIM_SRC}" rev-list --tags --max-count=1)")"
LATEST_VER="${LATEST_TAG#v}"
INSTALLED_VER="$(nvim --version 2>/dev/null | sed -n '1s/^NVIM v//p' || true)"
if [[ -n "${INSTALLED_VER}" && "${INSTALLED_VER}" == "${LATEST_VER}" ]]; then
  ok "Neovim ${INSTALLED_VER} already installed — skipping rebuild"
else
  echo "Updating Neovim to ${LATEST_TAG} (was: ${INSTALLED_VER:-none})..."
  git -C "${NVIM_SRC}" checkout -f "${LATEST_TAG}"
  make -C "${NVIM_SRC}" CMAKE_BUILD_TYPE=RelWithDebInfo -j"$(nproc)"
  sudo make -C "${NVIM_SRC}" install
  ok "Neovim updated to ${LATEST_VER}"
fi

# ------------------------------------------------------------------------------
# 11) Flatpak + Flathub + Apps (Discord, Spotify)  [Wireshark via APT for capture]
# ------------------------------------------------------------------------------
log "Flatpak: add Flathub remote and install apps"
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || true
flatpak update -y || true
flatpak install -y flathub com.discordapp.Discord com.spotify.Client
ok "Installed Flatpak apps: Discord, Spotify"
# Wireshark note: Flathub build cannot capture; install native for capture support.
sudo apt-get install -y wireshark
sudo usermod -aG wireshark "$USER" || true
sudo dpkg-reconfigure wireshark-common >/dev/null 2>&1 || true
sudo setcap cap_net_raw,cap_net_admin=eip /usr/bin/dumpcap || true
ok "Wireshark (native) installed with capture permissions"

# ------------------------------------------------------------------------------
# 12) Dotfiles: clone/pull + stow packages (adopt conflicts)
# ------------------------------------------------------------------------------
log "Cloning/pulling dotfiles and stowing packages"
if [[ -d "${DOTFILES_DIR}/.git" ]]; then
  git -C "${DOTFILES_DIR}" pull --ff-only
else
  git clone "${DOTFILES_REPO}" "${DOTFILES_DIR}"
fi
pushd "${DOTFILES_STOW_DIR}" >/dev/null
for pkg in */; do
  [[ "$pkg" == ".git/" ]] && continue
  echo "[stow] installing package: ${pkg%/}"
  if stow -vvt "${HOME}" "$pkg"; then
    continue
  fi
  warn "Conflicts while stowing ${pkg%/} — adopting existing files"
  stow -vvt "${HOME}" --adopt "$pkg"
done
popd >/dev/null
ok "Dotfiles stowed"

# ------------------------------------------------------------------------------
# 13) fish shell setup (default shell + conf.d for starship/zoxide/fnm)
# ------------------------------------------------------------------------------
log "Setting fish as default shell and wiring prompt/tools"
if [[ "${SET_FISH_DEFAULT}" == "true" ]] && command -v fish >/dev/null 2>&1; then
  [[ "${SHELL}" == "$(command -v fish)" ]] || chsh -s "$(command -v fish)" || warn "Could not change login shell automatically."
fi
mkdir -p "${HOME}/.config/fish/conf.d"
# starship prompt (fish)
grep -q "starship init fish" "${HOME}/.config/fish/conf.d/starship.fish" 2>/dev/null ||
  echo 'starship init fish | source' >>"${HOME}/.config/fish/conf.d/starship.fish"
# zoxide (fish)
grep -q "zoxide init fish" "${HOME}/.config/fish/conf.d/zoxide.fish" 2>/dev/null ||
  echo 'zoxide init fish | source' >>"${HOME}/.config/fish/conf.d/zoxide.fish"
# fnm (fish) — ensure Node versions available in fish shells too
grep -q "fnm env --use-on-cd --shell fish" "${HOME}/.config/fish/conf.d/fnm.fish" 2>/dev/null ||
  echo 'fnm env --use-on-cd --shell fish | source' >>"${HOME}/.config/fish/conf.d/fnm.fish"
ok "fish configured (starship, zoxide, fnm)"

# ------------------------------------------------------------------------------
# 14) GNOME settings: natural scrolling, workspaces, fonts
# ------------------------------------------------------------------------------
log "Applying GNOME settings (natural scroll, workspaces, fonts)"
if command -v gsettings >/dev/null 2>&1; then
  # Natural scrolling for mouse & touchpad
  gsettings set org.gnome.desktop.peripherals.mouse natural-scroll true || true
  gsettings set org.gnome.desktop.peripherals.touchpad natural-scroll true || true
  # Fixed number of workspaces
  gsettings set org.gnome.mutter dynamic-workspaces false || true
  gsettings set org.gnome.desktop.wm.preferences num-workspaces "${GNOME_WORKSPACES}" || true
  # Fonts (UI + monospace) to JetBrains Mono
  gsettings set org.gnome.desktop.interface font-name "JetBrains Mono ${GNOME_FONT_SIZE}" || true
  gsettings set org.gnome.desktop.interface document-font-name "JetBrains Mono ${GNOME_FONT_SIZE}" || true
  gsettings set org.gnome.desktop.interface monospace-font-name "JetBrains Mono ${GNOME_FONT_SIZE}" || true
  ok "GNOME settings applied"
else
  warn "gsettings not found — skipping GNOME tweaks"
fi

# ------------------------------------------------------------------------------
# 15) Default terminal to Alacritty (alternatives + GNOME)
# ------------------------------------------------------------------------------
log "Setting Alacritty as system default terminal"
if command -v alacritty >/dev/null 2>&1; then
  if command -v update-alternatives >/dev/null 2>&1; then
    if update-alternatives --list x-terminal-emulator >/dev/null 2>&1; then
      sudo update-alternatives --set x-terminal-emulator "$(command -v alacritty)" || true
    else
      sudo update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator "$(command -v alacritty)" 50
      sudo update-alternatives --set x-terminal-emulator "$(command -v alacritty)" || true
    fi
  fi
  if command -v gsettings >/dev/null 2>&1 && gsettings writable org.gnome.desktop.default-applications.terminal exec >/dev/null 2>&1; then
    gsettings set org.gnome.desktop.default-applications.terminal exec 'alacritty'
    gsettings set org.gnome.desktop.default-applications.terminal exec-arg ''
  fi
fi
ok "Alacritty set (where applicable)"

# ------------------------------------------------------------------------------
# 16) Cleanup
# ------------------------------------------------------------------------------
log "Final cleanup"
sudo apt-get autoremove -y
ok "All done"

printf "\n\033[1;32m✅ Bootstrap complete!\033[0m\n"
echo "• If added to 'docker' or 'wireshark' groups, run: newgrp docker && newgrp wireshark  (or log out/in)."
echo "• Open a new terminal (fish) so PATH & prompt changes take effect."
