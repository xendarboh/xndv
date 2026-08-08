#!/usr/bin/env bash
set -euo pipefail

curl -fsSL https://herdr.dev/install.sh | sh

export PATH="$HOME/.local/bin:$PATH"

# keep plugin build artifacts in their checkouts
unset CARGO_TARGET_DIR

herdr plugin install ezcorp-org/herdr-git-status --yes
herdr plugin install lmilojevicc/herdr-splits.nvim --yes
herdr plugin install yuk1ty/herdr-spreader --yes

# ensure custom config when this script is run on host
# this is redundant for xndv, which gets the config via stow
ln -sfv ~/src/xndv/conf/.config/herdr/config.toml ~/.config/herdr/config.toml
