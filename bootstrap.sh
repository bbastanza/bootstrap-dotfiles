#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
# Colors
# ─────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

banner() {
    echo -e "\n${BLUE}${BOLD}══════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}  $1${NC}"
    echo -e "${BLUE}${BOLD}══════════════════════════════════════════${NC}\n"
}

info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }

# ─────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────
command_exists() {
    command -v "$1" &>/dev/null
}

run_as_user() {
    if [[ "$EUID" -eq 0 ]]; then
        sudo -u "$TARGET_USER" bash -c "$1"
    else
        bash -c "$1"
    fi
}

# ─────────────────────────────────────────────
# Root check
# ─────────────────────────────────────────────
if [[ "$EUID" -ne 0 ]]; then
    error "Run as root or with sudo."
    exit 1
fi

# ─────────────────────────────────────────────
# Target user
# ─────────────────────────────────────────────
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)

info "Target user: ${BOLD}$TARGET_USER${NC} (home: $TARGET_HOME)"

# ─────────────────────────────────────────────
# Package manager detection
# ─────────────────────────────────────────────
if command_exists apt; then
    PKG_MANAGER="apt"
elif command_exists dnf; then
    PKG_MANAGER="dnf"
else
    error "Neither apt nor dnf found. Unsupported distro."
    exit 1
fi

info "Package manager: ${BOLD}$PKG_MANAGER${NC}"

# ─────────────────────────────────────────────
# Git credentials (env vars or args or prompt)
# Usage: GIT_USER=x GIT_EMAIL=y sudo -E bash bootstrap.sh
#   or:  sudo bash bootstrap.sh <username> <email>
# ─────────────────────────────────────────────
banner "Configuration"

GIT_USERNAME="${1:-${GIT_USER:-}}"
GIT_EMAIL="${2:-${GIT_EMAIL_ADDR:-}}"
VPS_NAME="${3:-${VPS_NAME:-}}"

# Pull from existing gitconfig if available
if [[ -z "$GIT_USERNAME" ]] && [[ -f "$TARGET_HOME/.gitconfig" ]]; then
    GIT_USERNAME=$(run_as_user "git config --global user.name" 2>/dev/null || true)
fi
if [[ -z "$GIT_EMAIL" ]] && [[ -f "$TARGET_HOME/.gitconfig" ]]; then
    GIT_EMAIL=$(run_as_user "git config --global user.email" 2>/dev/null || true)
fi

if [[ -z "$GIT_USERNAME" || -z "$GIT_EMAIL" || -z "$VPS_NAME" ]]; then
    # Read from /dev/tty so it works even when piped
    [[ -z "$GIT_USERNAME" ]] && read -rp "$(echo -e "${CYAN}GitHub username: ${NC}")" GIT_USERNAME < /dev/tty
    [[ -z "$GIT_EMAIL" ]] && read -rp "$(echo -e "${CYAN}GitHub email: ${NC}")" GIT_EMAIL < /dev/tty
    [[ -z "$VPS_NAME" ]] && read -rp "$(echo -e "${CYAN}VPS name (shown in prompt): ${NC}")" VPS_NAME < /dev/tty
fi

if [[ -z "$GIT_USERNAME" || -z "$GIT_EMAIL" || -z "$VPS_NAME" ]]; then
    error "Username, email, and VPS name are required."
    error "Pass as args: sudo bash bootstrap.sh <username> <email> <vps-name>"
    error "Or env vars:  GIT_USER=x GIT_EMAIL=y VPS_NAME=z sudo -E bash bootstrap.sh"
    exit 1
fi

info "Git user: $GIT_USERNAME <$GIT_EMAIL>"
info "VPS name: $VPS_NAME"

# ─────────────────────────────────────────────
# 1. System Update & Core Packages
# ─────────────────────────────────────────────
banner "1. System Update & Core Packages"

CORE_PACKAGES="curl wget git unzip tar jq htop tmux ranger zsh"

if [[ "$PKG_MANAGER" == "apt" ]]; then
    info "Updating apt..."
    apt update -y
    apt upgrade -y
    info "Installing core packages..."
    # shellcheck disable=SC2086
    apt install -y $CORE_PACKAGES
elif [[ "$PKG_MANAGER" == "dnf" ]]; then
    info "Updating dnf..."
    dnf upgrade -y --refresh
    info "Installing core packages..."
    # shellcheck disable=SC2086
    dnf install -y $CORE_PACKAGES util-linux-user
fi

# neofetch with fastfetch fallback
if ! command_exists neofetch && ! command_exists fastfetch; then
    info "Trying neofetch..."
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        apt install -y neofetch 2>/dev/null || apt install -y fastfetch 2>/dev/null || warn "neofetch/fastfetch unavailable"
    elif [[ "$PKG_MANAGER" == "dnf" ]]; then
        dnf install -y neofetch 2>/dev/null || dnf install -y fastfetch 2>/dev/null || warn "neofetch/fastfetch unavailable"
    fi
else
    success "neofetch/fastfetch already present"
fi

success "Core packages done"

# ─────────────────────────────────────────────
# 2. Dev Tools
# ─────────────────────────────────────────────
banner "2. Dev Tools"

if [[ "$PKG_MANAGER" == "apt" ]]; then
    apt install -y build-essential
elif [[ "$PKG_MANAGER" == "dnf" ]]; then
    dnf group install -y development-tools
fi

success "Dev tools done"

# ─────────────────────────────────────────────
# 3. Zsh + Oh-My-Zsh
# ─────────────────────────────────────────────
banner "3. Zsh + Oh-My-Zsh"

if [[ ! -d "$TARGET_HOME/.oh-my-zsh" ]]; then
    info "Installing oh-my-zsh..."
    run_as_user 'RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended'
    success "oh-my-zsh installed"
else
    success "oh-my-zsh already installed"
fi

AUTOSUGG_DIR="$TARGET_HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
if [[ ! -d "$AUTOSUGG_DIR" ]]; then
    info "Cloning zsh-autosuggestions..."
    run_as_user "git clone https://github.com/zsh-users/zsh-autosuggestions $AUTOSUGG_DIR"
    success "zsh-autosuggestions cloned"
else
    success "zsh-autosuggestions already present"
fi

# ─────────────────────────────────────────────
# 4. Neovim
# ─────────────────────────────────────────────
banner "4. Neovim"

if ! command_exists nvim; then
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        info "Adding neovim PPA..."
        add-apt-repository -y ppa:neovim-ppa/unstable
        apt update -y
        apt install -y neovim
    elif [[ "$PKG_MANAGER" == "dnf" ]]; then
        dnf install -y neovim
    fi
    success "Neovim installed"
else
    success "Neovim already installed: $(nvim --version | head -1)"
fi

# Dotfiles (nvim + broot configs)
DOTFILES_DIR="$TARGET_HOME/.dotfiles"
if [[ ! -d "$DOTFILES_DIR" ]]; then
    info "Cloning dotfiles..."
    mkdir -p "$TARGET_HOME/.config"
    chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.config"
    run_as_user "git clone https://github.com/bbastanza/bootstrap-dotfiles.git '$DOTFILES_DIR'"
    success "Dotfiles cloned"
else
    info "Updating dotfiles..."
    run_as_user "cd '$DOTFILES_DIR' && git pull"
    success "Dotfiles updated"
fi

# Symlink nvim config
NVIM_CFG="$TARGET_HOME/.config/nvim"
if [[ ! -L "$NVIM_CFG" ]]; then
    rm -rf "$NVIM_CFG"
    run_as_user "ln -s '$DOTFILES_DIR/nvim' '$NVIM_CFG'"
    success "Neovim config linked"
else
    success "Neovim config already linked"
fi

# Symlink broot config
BROOT_CFG="$TARGET_HOME/.config/broot"
if [[ ! -L "$BROOT_CFG" ]]; then
    rm -rf "$BROOT_CFG"
    run_as_user "ln -s '$DOTFILES_DIR/broot' '$BROOT_CFG'"
    success "Broot config linked"
else
    success "Broot config already linked"
fi

# ─────────────────────────────────────────────
# 5. Modern CLI Tools
# ─────────────────────────────────────────────
banner "5. Modern CLI Tools"

# eza
if ! command_exists eza; then
    info "Installing eza..."
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        mkdir -p /etc/apt/keyrings
        wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc \
            | gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
        echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" \
            > /etc/apt/sources.list.d/gierens.list
        chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
        apt update -y
        apt install -y eza
    elif [[ "$PKG_MANAGER" == "dnf" ]]; then
        dnf install -y eza
    fi
    success "eza installed"
else
    success "eza already installed"
fi

# bat
if ! command_exists bat; then
    info "Installing bat..."
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        apt install -y bat
    elif [[ "$PKG_MANAGER" == "dnf" ]]; then
        dnf install -y bat
    fi
    # Ubuntu installs bat as 'batcat' — symlink to 'bat'
    if command_exists batcat && ! command_exists bat; then
        ln -sf "$(which batcat)" /usr/local/bin/bat
    fi
    success "bat installed"
else
    success "bat already installed"
fi

# ripgrep
if ! command_exists rg; then
    info "Installing ripgrep..."
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        apt install -y ripgrep
    elif [[ "$PKG_MANAGER" == "dnf" ]]; then
        dnf install -y ripgrep
    fi
    success "ripgrep installed"
else
    success "ripgrep already installed"
fi

# broot
if ! command_exists broot; then
    info "Downloading broot..."
    wget -qO /usr/local/bin/broot https://dystroy.org/broot/download/x86_64-linux/broot
    chmod +x /usr/local/bin/broot
    info "Running broot --install as $TARGET_USER..."
    run_as_user "broot --install"
    success "broot installed"
else
    success "broot already installed"
fi

# ─────────────────────────────────────────────
# 6. Starship Prompt
# ─────────────────────────────────────────────
banner "6. Starship Prompt"

if ! command_exists starship; then
    info "Installing starship..."
    curl -fsSL https://starship.rs/install.sh | sh -s -- -y
    success "Starship installed"
else
    success "Starship already installed"
fi

info "Writing starship config..."
mkdir -p "$TARGET_HOME/.config"
cat > "$TARGET_HOME/.config/starship.toml" <<EOF
format = """
_${VPS_NAME}_ \$all"""

[character]
success_symbol = "[>](bold green)"
error_symbol = "[>](bold red)"
EOF
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.config/starship.toml"
success "Starship config written (VPS: $VPS_NAME)"

# ─────────────────────────────────────────────
# 7. Git + GitHub CLI
# ─────────────────────────────────────────────
banner "7. Git + GitHub CLI"

if ! command_exists gh; then
    info "Installing gh CLI..."
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
            | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
        chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
            > /etc/apt/sources.list.d/github-cli.list
        apt update -y
        apt install -y gh
    elif [[ "$PKG_MANAGER" == "dnf" ]]; then
        dnf install -y gh
    fi
    success "gh CLI installed"
else
    success "gh CLI already installed"
fi

info "Writing ~/.gitconfig..."
cat > "$TARGET_HOME/.gitconfig" <<EOF
[user]
    name = $GIT_USERNAME
    email = $GIT_EMAIL

[init]
    defaultBranch = main

[credential]
    helper = !/usr/bin/gh auth git-credential

[credential "https://github.com"]
    helper = !/usr/bin/gh auth git-credential

[credential "https://gist.github.com"]
    helper = !/usr/bin/gh auth git-credential

[core]
    editor = nvim

[pull]
    rebase = false
EOF
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.gitconfig"
success "~/.gitconfig written"

# ─────────────────────────────────────────────
# 8. SSH Key + GitHub Auth
# ─────────────────────────────────────────────
banner "8. SSH Key for GitHub"

SSH_KEY="$TARGET_HOME/.ssh/id_ed25519"
mkdir -p "$TARGET_HOME/.ssh"
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.ssh"
chmod 700 "$TARGET_HOME/.ssh"

if [[ ! -f "$SSH_KEY" ]]; then
    info "Generating ed25519 SSH key..."
    run_as_user "ssh-keygen -t ed25519 -C '$GIT_EMAIL' -f '$SSH_KEY' -N ''"
    success "SSH key generated: $SSH_KEY"
else
    success "SSH key already exists: $SSH_KEY"
fi

if run_as_user "gh auth status &>/dev/null"; then
    success "gh already authenticated"
else
    echo -e "\n${YELLOW}${BOLD}ACTION REQUIRED:${NC} Please complete GitHub authentication below."
    echo -e "${CYAN}Select the following when prompted:${NC}"
    echo -e "  ${BOLD}1.${NC} GitHub.com"
    echo -e "  ${BOLD}2.${NC} HTTPS"
    echo -e "  ${BOLD}3.${NC} Login with a web browser (or paste a token)"
    echo -e "${CYAN}Required scopes:${NC} ${BOLD}repo${NC}, ${BOLD}admin:public_key${NC}\n"
    run_as_user "gh auth login --scopes repo,admin:public_key" < /dev/tty
fi

info "Adding SSH key to GitHub..."
run_as_user "gh ssh-key add '${SSH_KEY}.pub' --title '$(hostname)'" 2>/dev/null \
    && success "SSH key added to GitHub" \
    || success "SSH key already on GitHub"

# ─────────────────────────────────────────────
# 9. NVM + Node
# ─────────────────────────────────────────────
banner "9. NVM + Node.js"

NVM_DIR="$TARGET_HOME/.nvm"

if [[ ! -d "$NVM_DIR" ]]; then
    info "Installing nvm v0.40.1..."
    run_as_user "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash"
    success "nvm installed"
else
    success "nvm already installed"
fi

info "Installing latest LTS Node..."
run_as_user "source '$NVM_DIR/nvm.sh' && nvm install --lts && nvm alias default 'lts/*'"
success "Node LTS installed"

# ─────────────────────────────────────────────
# 10. pnpm
# ─────────────────────────────────────────────
banner "10. pnpm"

if ! run_as_user "command -v pnpm &>/dev/null"; then
    info "Installing pnpm..."
    run_as_user "curl -fsSL https://get.pnpm.io/install.sh | sh -"
    success "pnpm installed"
else
    success "pnpm already installed"
fi

# ─────────────────────────────────────────────
# 11. .NET SDK
# ─────────────────────────────────────────────
banner "11. .NET SDK 9.0"

if ! command_exists dotnet; then
    info "Installing .NET SDK 9.0..."
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        # Detect distro for Microsoft repo
        . /etc/os-release
        DISTRO_ID="${ID}"
        DISTRO_VER="${VERSION_ID}"
        wget -qO /tmp/packages-microsoft-prod.deb \
            "https://packages.microsoft.com/config/${DISTRO_ID}/${DISTRO_VER}/packages-microsoft-prod.deb"
        dpkg -i /tmp/packages-microsoft-prod.deb
        rm /tmp/packages-microsoft-prod.deb
        apt update -y
        apt install -y dotnet-sdk-9.0
    elif [[ "$PKG_MANAGER" == "dnf" ]]; then
        if ! dnf install -y dotnet-sdk-9.0 2>/dev/null; then
            warn "Falling back to Microsoft repo for .NET..."
            . /etc/os-release
            rpm --import https://packages.microsoft.com/keys/microsoft.asc
            cat > /etc/yum.repos.d/microsoft-prod.repo <<EOF
[packages-microsoft-com-prod]
name=packages-microsoft-com-prod
baseurl=https://packages.microsoft.com/rhel/$(rpm -E '%{rhel}')/prod/
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
            dnf install -y dotnet-sdk-9.0
        fi
    fi
    success ".NET SDK installed"
else
    success ".NET SDK already installed: $(dotnet --version)"
fi

# ─────────────────────────────────────────────
# 12. Docker
# ─────────────────────────────────────────────
banner "12. Docker CE"

if ! command_exists docker; then
    info "Installing Docker CE..."
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        apt install -y ca-certificates gnupg lsb-release
        install -m 0755 -d /etc/apt/keyrings
        . /etc/os-release
        curl -fsSL "https://download.docker.com/linux/${ID}/gpg" \
            | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
        echo \
            "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/${ID} $(lsb_release -cs) stable" \
            > /etc/apt/sources.list.d/docker.list
        apt update -y
        apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    elif [[ "$PKG_MANAGER" == "dnf" ]]; then
        dnf install -y dnf-plugins-core
        dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo
        dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi
    success "Docker installed"
else
    success "Docker already installed: $(docker --version)"
fi

info "Enabling Docker service..."
systemctl enable --now docker

if ! groups "$TARGET_USER" | grep -q docker; then
    usermod -aG docker "$TARGET_USER"
    success "$TARGET_USER added to docker group"
else
    success "$TARGET_USER already in docker group"
fi

# ─────────────────────────────────────────────
# 13. Nginx + Certbot
# ─────────────────────────────────────────────
banner "13. Nginx + Certbot"

if [[ "$PKG_MANAGER" == "apt" ]]; then
    apt install -y nginx certbot python3-certbot-nginx
elif [[ "$PKG_MANAGER" == "dnf" ]]; then
    dnf install -y nginx certbot python3-certbot-nginx
fi

systemctl enable nginx
success "Nginx enabled (not started)"

# ─────────────────────────────────────────────
# 14. Security (Firewall + fail2ban)
# ─────────────────────────────────────────────
banner "14. Security"

# Firewall
if [[ "$PKG_MANAGER" == "apt" ]]; then
    info "Configuring ufw..."
    apt install -y ufw
    ufw allow ssh
    ufw allow http
    ufw allow https
    ufw --force enable
    success "ufw enabled"
elif [[ "$PKG_MANAGER" == "dnf" ]]; then
    info "Configuring firewalld..."
    systemctl enable --now firewalld
    firewall-cmd --permanent --add-service=ssh
    firewall-cmd --permanent --add-service=http
    firewall-cmd --permanent --add-service=https
    firewall-cmd --reload
    success "firewalld configured"
fi

# fail2ban
if [[ "$PKG_MANAGER" == "apt" ]]; then
    apt install -y fail2ban
elif [[ "$PKG_MANAGER" == "dnf" ]]; then
    dnf install -y fail2ban
fi

cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled  = true
port     = ssh
logpath  = %(sshd_log)s
backend  = %(sshd_backend)s
EOF

systemctl enable --now fail2ban
success "fail2ban configured and enabled"

# ─────────────────────────────────────────────
# 15. Write ~/.zshrc
# ─────────────────────────────────────────────
banner "15. Writing ~/.zshrc"

cat > "$TARGET_HOME/.zshrc" <<'ZSHRC'
# Path
export PATH=$HOME/.local/bin:$HOME/bin:$HOME/.cargo/bin:$PATH

# Oh-My-Zsh
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git zsh-autosuggestions sudo history)
source $ZSH/oh-my-zsh.sh

# History
HISTFILE=~/.histfile
HISTSIZE=10000
SAVEHIST=10000
setopt autocd extendedglob

# Completion
zstyle :compinstall filename "$HOME/.zshrc"
autoload -Uz compinit
compinit

# --- Git Aliases ---
alias push="git push"
alias all="git add -A"
alias force="git push --force"
alias stat="git status"
alias diff="git diff"
alias sdiff="git diff --staged"
alias commit="git commit -m"
alias branch="git branch | bat -p"
alias fpull="git checkout main && git fetch && git pull"
alias amend="git add -A && git commit --amend --no-edit"
alias up="sudo dnf update -y && sudo dnf upgrade -y"
alias pull="git pull"

# --- Utility Aliases ---
alias ls="eza -l"
alias la="eza -la"
alias svim="sudo -e"

# --- Directory Aliases ---
alias cc="cd ~/.config/"

# --- NVM ---
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# --- Starship ---
eval "$(starship init zsh)"

# --- pnpm ---
export PNPM_HOME="$HOME/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac

# --- Broot ---
[ -f "$HOME/.config/broot/launcher/bash/br" ] && source "$HOME/.config/broot/launcher/bash/br"

# --- Keybindings ---
bindkey -e
bindkey '^L' autosuggest-accept
bindkey '\e[76;5u' clear-screen

# neofetch or fastfetch
if command -v neofetch &>/dev/null; then
  neofetch
elif command -v fastfetch &>/dev/null; then
  fastfetch
fi
ZSHRC

chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.zshrc"
success "~/.zshrc written"

# ─────────────────────────────────────────────
# 16. Set Default Shell
# ─────────────────────────────────────────────
banner "16. Set Default Shell to Zsh"

ZSH_PATH=$(which zsh)
CURRENT_SHELL=$(getent passwd "$TARGET_USER" | cut -d: -f7)

# Ensure zsh is in /etc/shells
if ! grep -qx "$ZSH_PATH" /etc/shells; then
    info "Adding $ZSH_PATH to /etc/shells..."
    echo "$ZSH_PATH" >> /etc/shells
fi

if [[ "$CURRENT_SHELL" != "$ZSH_PATH" ]]; then
    chsh -s "$ZSH_PATH" "$TARGET_USER"
    success "Default shell set to $ZSH_PATH for $TARGET_USER"
else
    success "Default shell already zsh"
fi

# ─────────────────────────────────────────────
# 17. Final Summary
# ─────────────────────────────────────────────
banner "17. Setup Complete"

echo -e "${GREEN}${BOLD}Installed / Configured:${NC}"
echo -e "  ${CYAN}System${NC}       — updated, core packages, dev tools"
echo -e "  ${CYAN}Shell${NC}        — zsh, oh-my-zsh, zsh-autosuggestions, starship"
echo -e "  ${CYAN}Editor${NC}       — neovim + config"
echo -e "  ${CYAN}Dotfiles${NC}     — nvim, broot (symlinked from ~/.dotfiles)"
echo -e "  ${CYAN}CLI Tools${NC}    — eza, bat, ripgrep, broot"
echo -e "  ${CYAN}Git / GitHub${NC} — git, gh CLI, gitconfig, SSH key"
echo -e "  ${CYAN}Node${NC}         — nvm v0.40.1, Node LTS, pnpm"
echo -e "  ${CYAN}.NET${NC}         — dotnet-sdk-9.0"
echo -e "  ${CYAN}Docker${NC}       — docker CE, compose plugin"
echo -e "  ${CYAN}Web${NC}          — nginx (enabled), certbot"
echo -e "  ${CYAN}Security${NC}     — firewall, fail2ban (sshd jail)"
echo -e "  ${CYAN}Dotfiles${NC}     — ~/.zshrc, ~/.gitconfig"

echo -e "\n${YELLOW}${BOLD}Next steps:${NC}"
echo -e "  1. ${BOLD}Log out and back in${NC} — required for shell change and docker group to take effect"
echo -e "  2. Verify with: ${CYAN}docker run hello-world${NC}"
echo -e "  3. Start nginx when ready: ${CYAN}sudo systemctl start nginx${NC}"
echo -e "  4. Configure certbot: ${CYAN}sudo certbot --nginx${NC}"
