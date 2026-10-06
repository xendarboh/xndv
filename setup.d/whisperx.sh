#!/bin/bash -ex

sudo apt update
sudo apt install --no-install-recommends -y -q \
  ffmpeg \
  libsndfile1

uv tool install --upgrade \
  git+https://github.com/m-bain/whisperx.git

# Find executables, exclude generic python/pip, and link
SRC="${UV_TOOL_DIR:-$HOME/.local/share/uv/tools}/whisperx/bin"
DEST="$HOME/.local/bin"
fd . "$SRC" -t x -d 1 -E python* -E pip* -x ln -sf {} "$DEST/"
