# ----- Minimal Zsh config (Antidote + Starship + zoxide) -----

# PATH (tweak as you like)
export PATH="$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH"

# --- Antidote (zsh plugin manager) ---
# Prefer Debian package path if present, else fallback to ~/.antidote
if [[ -f /usr/share/zsh-antidote/antidote.zsh ]]; then
  source /usr/share/zsh-antidote/antidote.zsh
elif [[ -f "${ZDOTDIR:-$HOME}/.antidote/antidote.zsh" ]]; then
  source "${ZDOTDIR:-$HOME}/.antidote/antidote.zsh"
fi

# User completions BEFORE compinit (optional)
fpath=(~/.zfunc $fpath)

# Build & load plugin bundle from ~/.zsh_plugins.txt
typeset -f antidote >/dev/null && antidote load

# Completions
autoload -Uz compinit && compinit

# --- Prompt (Starship) ---
command -v starship >/dev/null && eval "$(starship init zsh)"

# --- Smarter cd (zoxide) ---
# Keep this AFTER compinit per docs
command -v zoxide  >/dev/null && eval "$(zoxide init zsh)"

