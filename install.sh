#!/bin/bash
set -euo pipefail

# The script should be run by a normal user; if not root, re-run under sudo,
# but preserve the invoking user's USER and HOME env variables.
if [ "$EUID" -ne 0 ]; then
  ORIGINAL_USER="${SUDO_USER:-$USER}"
  ORIGINAL_HOME="${HOME:-/home/$ORIGINAL_USER}"
  echo "Re-execing under sudo (keeping USER=$ORIGINAL_USER HOME=$ORIGINAL_HOME)..."
  exec sudo --preserve-env=USER,HOME -- \
       env USER="$ORIGINAL_USER" HOME="$ORIGINAL_HOME" SUDO_USER="$ORIGINAL_USER" \
       bash "$0" "$@"
fi

download_and_install_binary(){
    binary_name=$1
    binary_path="/usr/bin/$binary_name"
    url=$2
    wget "$url" -O $binary_path && chmod +x $binary_path
}

backup_path="$HOME/.old/$(date -Is)"
echo "Creating backup at $backup_path"
mkdir -p $backup_path
if [ -f $HOME/.zshrc ]; then
    cp $HOME/.zshrc $backup_path/.zshrc
fi
if [ -f $HOME/.vimrc ]; then
    cp $HOME/.vimrc $backup_path/.vimrc
fi
if [ -f $HOME/.p10k.zsh ]; then
    cp $HOME/.p10k.zsh $backup_path/.p10k.zsh
fi
if [ -f $HOME/.vim/plugged/gruvbox/colors/gruvbox.vim ]; then
    cp $HOME/.vim/plugged/gruvbox/colors/gruvbox.vim $backup_path/gruvbox.vim
fi
if [ ! -f $HOME/.workprofile.zshrc ]; then
    touch $HOME/.workprofile.zshrc
fi

echo "Installing basic tools"
apt-get update -y
apt-get upgrade -y
apt-get install -y curl wget jq eza vim-gtk3 xkcdpass python3-pip pipx
if ! which -s yq; then
    download_and_install_binary yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
fi

echo "Installing zsh and oh-my-zsh"
if [ ! -d $HOME/.oh-my-zsh ]; then
    apt install -y zsh
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi
echo "Setting zsh as default shell"
chsh -s "$(command -v zsh)" "$USER"

echo "Installing oh-my-zsh plugins"
# If powerlevel10k oh-my-zsh theme file doesnt exists
if [ ! -d $HOME/.oh-my-zsh/custom/themes/powerlevel10k ]; then
    echo "  Installing powerlevel10k zsh theme"
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git $HOME/.oh-my-zsh/custom/themes/powerlevel10k
fi
echo "  Installing FZF"
apt-get install fzf -y
echo "  Installing autojump"
apt-get install autojump -y
if [ ! -d $HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting ]; then
    echo "  Installing syntax highlighting"
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git $HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
fi
if [ ! -d $HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions ]; then
    echo "  Installing auto suggestions"
    git clone https://github.com/zsh-users/zsh-autosuggestions $HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions
fi
if [ ! -d $HOME/.oh-my-zsh/custom/plugins/terragrunt ]; then
    echo "  Installing terragrunt"
    git clone https://github.com/hanjunlee/terragrunt-oh-my-zsh-plugin $HOME/.oh-my-zsh/custom/plugins/terragrunt
fi
if [ ! -d $HOME/.oh-my-zsh/custom/plugins/kustomize ]; then
    echo "  Installing kustomize"
    git clone https://github.com/ralgozino/oh-my-kustomize $HOME/.oh-my-zsh/custom/plugins/kustomize
fi

echo "Overwriting zsh and vim config files"
\cp dot_files/p10k.zsh $HOME/.p10k.zsh
\cp dot_files/zshrc $HOME/.zshrc
\cp dot_files/vimrc $HOME/.vimrc

echo "Installing vim plugins"
if [ ! -f $HOME/.vim/.plugins_installed ]; then
    vim +'PlugInstall --sync' +qa
    echo "  Overwriting vim gruvbox theme"
    \cp dot_files/gruvbox.vim $HOME/.vim/plugged/gruvbox/colors/gruvbox.vim
    echo "  Installing YouCompleteMe Prerequisites"
    echo "    Installing cmake, vim and python"
    apt-get install -y build-essential cmake vim-nox python3-dev
    echo "    Installing mono-complete, go, node, java and npm"
    apt-get install -y mono-complete golang nodejs default-jdk npm
    echo "  Installing YouCompleteMe"
    cd $HOME/.vim/plugged/YouCompleteMe
    git submodule update --init --recursive
    python3 install.py --all --force-sudo
    echo "  Installing RipGrep"
    apt-get install -y ripgrep
    # Create file that indicates that plugins were installed
    touch $HOME/.vim/.plugins_installed
fi

echo "Installing Git Delta"
echo -n '
[core]
    pager = delta

[interactive]
    diffFilter = delta --color-only

[delta]
    navigate = true # use n and N to move between diff sections
    dark = true
    line-numbers = true

[merge]
    conflictstyle = diff3

[diff]
    colorMoved = default
' >> $HOME/.gitconfig
wget https://github.com/dandavison/delta/releases/download/0.17.0/git-delta_0.17.0_amd64.deb -O /tmp/git-delta
dpkg -i /tmp/git-delta

if ! ls /usr/local/share/fonts | grep -qi nerdfont; then
    echo "Installing NerdFont"
    wget https://github.com/ryanoasis/nerd-fonts/releases/download/v3.3.0/SourceCodePro.zip -O /tmp/nerdfont.zip
    unzip /tmp/nerdfont.zip -d /usr/local/share/fonts
    fc-cache -fv
fi

if ! which -s kubectl; then
    echo "Installing Kubectl"
    download_and_install_binary kubectl https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl
fi

if ! which -s kustomize; then
    echo "Installing Kustomize"
    curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
    mv kustomize /usr/bin/kustomize
fi

if ! which -s helm; then
    echo "Installing Helm"
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

if ! which -s terraform; then
    echo "Installing Terraform"
    wget -O - https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list
    apt update && apt install terraform
fi

if ! which -s llm; then
    echo "Installing LLM"
    pipx install llm
    pipx install files-to-prompt
    $HOME/.local/bin/llm install llm-cmd
    $HOME/.local/bin/llm install llm-cmd-comp
    $HOME/.local/bin/llm install llm-jq
    $HOME/.local/bin/llm install llm-fragments-github
fi

if ! which -s docker; then
    # Add Docker's official GPG key:
    apt-get update
    apt-get install ca-certificates curl
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    # Add the repository to Apt sources:
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update
    # Install docker packages
    apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    # Create group to run as non-sudo
    groupadd --force docker
    usermod -aG docker $USER
    newgrp docker
fi
