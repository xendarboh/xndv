#!/usr/bin/env bash
set -euo pipefail

curl -fsSL https://herdr.dev/install.sh | sh

export PATH="$HOME/.local/bin:$PATH"

herdr plugin install lmilojevicc/herdr-splits.nvim --yes

# ensure custom config when this script is run on host
# this is redundant for xndv, which gets the config via stow
ln -sfv ~/src/xndv/conf/.config/herdr/config.toml ~/.config/herdr/config.toml
