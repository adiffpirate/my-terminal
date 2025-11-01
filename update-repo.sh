#!/usr/bin/env bash
# Copy local config files into the repository's dot_files directory.
# This script preserves the structure of the repository and reports
# any failures during the copy process.

set -euo pipefail

# Path to the dot_files directory relative to this script
DOT_DIR="$PWD/dot_files"

# Ensure the destination directory exists
mkdir -p "$DOT_DIR"

# Mapping of source files to destination names
declare -A FILES=(
  ["$HOME/.zshrc"]="zshrc"
  ["$HOME/.vimrc"]="vimrc"
  ["$HOME/.p10k.zsh"]="p10k.zsh"
  ["$HOME/.vim/plugged/gruvbox/colors/gruvbox.vim"]="gruvbox.vim"
)

# Function to copy a file and report status
copy_file() {
  local src="$1"
  local dst="$2"

  echo "Copying $src to $dst ..."
  if cp -f "$src" "$dst"; then
    echo "✓ Copied."
  else
    echo "✗ Failed to copy $src" >&2
  fi
}

# Iterate over the defined files and perform the copy
for src in "${!FILES[@]}"; do
  dst="$DOT_DIR/${FILES[$src]}"
  copy_file "$src" "$dst"
done
