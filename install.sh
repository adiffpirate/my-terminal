#!/bin/bash
set -xeuo pipefail

# Must be run as a normal user with sudo privileges, NOT as root.
if [ "$EUID" -eq 0 ]; then
    echo "Do not run this script as root. Run it as your normal user (sudo will be used where needed)." >&2
    exit 1
fi

# -------------------------------------------------------------------
# Helper to download a binary to /usr/bin
# -------------------------------------------------------------------
download_and_install_binary() {
    local binary_name="$1"
    local binary_path="/usr/bin/$binary_name"
    local url="$2"

    sudo wget "$url" -O "$binary_path"
    sudo chmod +x "$binary_path"
}

# -------------------------------------------------------------------
# Backup existing configs (optional, but safe)
# -------------------------------------------------------------------
backup_path="$HOME/.old/$(date -Is)"
echo "Creating backup at $backup_path"
mkdir -p "$backup_path"

for file in .zshrc .vimrc .p10k.zsh; do
    if [ -f "$HOME/$file" ]; then
        cp "$HOME/$file" "$backup_path/$file"
    fi
done
if [ -f "$HOME/.vim/plugged/gruvbox/colors/gruvbox.vim" ]; then
    cp "$HOME/.vim/plugged/gruvbox/colors/gruvbox.vim" "$backup_path/gruvbox.vim"
fi

# Create an empty work profile file if missing
touch "$HOME/.workprofile.zshrc"

# -------------------------------------------------------------------
# Basic tools
# -------------------------------------------------------------------
echo "Installing basic tools"
sudo apt-get update -y
sudo apt-get install -y htop curl wget jq eza vim-gtk3 xkcdpass python3-pip pipx

if ! command -v yq &>/dev/null; then
    download_and_install_binary yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
fi

# -------------------------------------------------------------------
# zsh & oh‑my‑zsh
# -------------------------------------------------------------------
echo "Installing zsh and oh-my-zsh"
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    sudo apt-get install -y zsh
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi
echo "Setting zsh as default shell"
chsh -s "$(command -v zsh)" "$USER"

# -------------------------------------------------------------------
# oh‑my‑zsh plugins
# -------------------------------------------------------------------
echo "Installing oh-my-zsh plugins"

if [ ! -d "$HOME/.oh-my-zsh/custom/themes/powerlevel10k" ]; then
    echo "  Installing powerlevel10k theme"
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
fi

echo "  Installing FZF"
sudo apt-get install -y fzf
echo "  Installing autojump"
sudo apt-get install -y autojump

plugins=(
    "zsh-syntax-highlighting:https://github.com/zsh-users/zsh-syntax-highlighting.git"
    "zsh-autosuggestions:https://github.com/zsh-users/zsh-autosuggestions"
    "terragrunt:https://github.com/hanjunlee/terragrunt-oh-my-zsh-plugin"
    "kustomize:https://github.com/ralgozino/oh-my-kustomize"
)

for entry in "${plugins[@]}"; do
    plugin_name="${entry%%:*}"
    plugin_url="${entry#*:}"          # <--- changed from ## to #
    if [ ! -d "$HOME/.oh-my-zsh/custom/plugins/$plugin_name" ]; then
        echo "  Installing $plugin_name"
        git clone "$plugin_url" "$HOME/.oh-my-zsh/custom/plugins/$plugin_name"
    fi
done

# -------------------------------------------------------------------
# Copy your personal dotfiles
# -------------------------------------------------------------------
echo "Overwriting zsh and vim config files"
if [ -f "dot_files/p10k.zsh" ]; then
    \cp "dot_files/p10k.zsh" "$HOME/.p10k.zsh"
fi
if [ -f "dot_files/zshrc" ]; then
    \cp "dot_files/zshrc" "$HOME/.zshrc"
fi
if [ -f "dot_files/vimrc" ]; then
    \cp "dot_files/vimrc" "$HOME/.vimrc"
fi

# -------------------------------------------------------------------
# Vim plugins (idempotent via marker file)
# -------------------------------------------------------------------
echo "Installing vim plugins"
if [ ! -f "$HOME/.vim/.plugins_installed" ]; then
    vim +'PlugInstall --sync' +qa
    echo "  Overwriting vim gruvbox theme"
    if [ -f "dot_files/gruvbox.vim" ]; then
        \cp "dot_files/gruvbox.vim" "$HOME/.vim/plugged/gruvbox/colors/gruvbox.vim"
    fi
    echo "  Installing YouCompleteMe prerequisites"
    sudo apt-get install -y build-essential cmake vim-nox python3-dev
    sudo apt-get install -y mono-complete golang nodejs default-jdk npm
    echo "  Installing YouCompleteMe"
    cd "$HOME/.vim/plugged/YouCompleteMe"
    git submodule update --init --recursive
    python3 install.py --all --force-sudo
    echo "  Installing RipGrep"
    sudo apt-get install -y ripgrep
    touch "$HOME/.vim/.plugins_installed"
fi

# -------------------------------------------------------------------
# Git Delta (fully idempotent via git config)
# -------------------------------------------------------------------
echo "Configuring Git Delta"
sudo apt-get install -y git  # ensure git is available
wget -q https://github.com/dandavison/delta/releases/download/0.17.0/git-delta_0.17.0_amd64.deb -O /tmp/git-delta.deb
sudo dpkg -i /tmp/git-delta.deb 2>/dev/null || sudo apt-get -f install -y   # fix dependencies if any

git config --global user.name adiffpirate
git config --global user.email adiffpirate@gmail.com
git config --global credential.username adiffpirate
git config --global core.pager delta
git config --global interactive.diffFilter 'delta --color-only'
git config --global delta.navigate true
git config --global delta.dark true
git config --global delta.line-numbers true
git config --global diff.colorMoved default

# -------------------------------------------------------------------
# NerdFont (check via fc-list, idempotent)
# -------------------------------------------------------------------
if ! fc-list | grep -qi 'nerd'; then
    echo "Installing NerdFont"
    wget -q https://github.com/ryanoasis/nerd-fonts/releases/download/v3.3.0/SourceCodePro.zip -O /tmp/nerdfont.zip
    sudo unzip -o /tmp/nerdfont.zip -d /usr/local/share/fonts/
    sudo fc-cache -fv
fi

# -------------------------------------------------------------------
# Kubernetes tools
# -------------------------------------------------------------------
if ! command -v kubectl &>/dev/null; then
    echo "Installing Kubectl"
    KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
    download_and_install_binary kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
fi

if ! command -v kustomize &>/dev/null; then
    echo "Installing Kustomize"
    curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
    sudo mv kustomize /usr/bin/kustomize
fi

if ! command -v helm &>/dev/null; then
    echo "Installing Helm"
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# -------------------------------------------------------------------
# Terraform
# -------------------------------------------------------------------
if ! command -v terraform &>/dev/null; then
    echo "Installing Terraform"
    wget -qO- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y terraform
fi

# -------------------------------------------------------------------
# LLM tools (pipx)
# -------------------------------------------------------------------
if ! command -v llm &>/dev/null; then
    echo "Installing LLM and plugins"
    pipx install llm
    pipx install files-to-prompt
    pipx install mdrender
    pipx install token-count
    "$HOME/.local/bin/llm" install llm-cmd
    "$HOME/.local/bin/llm" install llm-cmd-comp
    "$HOME/.local/bin/llm" install llm-jq
    "$HOME/.local/bin/llm" install llm-fragments-github
fi

# -------------------------------------------------------------------
# Docker (optional group membership, no newgrp)
# -------------------------------------------------------------------
if ! command -v docker &>/dev/null; then
    echo "Installing Docker"
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo groupadd --force docker
    sudo usermod -aG docker "$USER"
    echo "Docker installed. Please log out and back in (or restart) to use Docker without sudo."
fi

echo "Setup complete!"
