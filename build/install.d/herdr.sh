#!/usr/bin/env bash
set -euo pipefail

curl -fsSL https://herdr.dev/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
herdr plugin install lmilojevicc/herdr-splits.nvim --yes
