#!/usr/bin/env bash
# Install herdr and its plugins. The mode follows the environment:
#
#   container — install herdr, build plugins from source, then prune the build
#               intermediates. XNDV_DIR is an image ENV set only inside xndv, and
#               the Dockerfile's RUN resolves this script through that same var,
#               so it can never be absent there.
#   host      — install herdr, then link plugin binaries prebuilt in the xndv
#               image. No rust toolchain on the host.
#
# To force host mode from inside a container (sysbox docker-in-docker), unset the
# marker for the call: XNDV_DIR= ./build/install.d/herdr.sh
#
# herdr itself is a static binary the upstream installer downloads, so neither
# mode needs a compiler for herdr — only the plugins ever did.
set -euo pipefail

[[ -n "${XNDV_DIR:-}" ]] && MODE=container || MODE=host

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
XNDV_IMAGE="${XNDV_IMAGE:-xen/dev}"
BUNDLE_DIR="${HOME}/.local/share/xndv/xndv/herdr-plugins"
PLUGIN_SRC="${HOME}/.config/herdr/plugins/github"

PLUGINS=(
  ezcorp-org/herdr-git-status
  lmilojevicc/herdr-splits.nvim
  yuk1ty/herdr-spreader
)

say() { echo "[herdr] $*"; }

install_herdr() {
  curl -fsSL https://herdr.dev/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
}

link_config() {
  # ensure custom config when this script is run on host
  # this is redundant for xndv, which gets the config via stow
  mkdir -p ~/.config/herdr
  ln -sfv "${REPO_DIR}/conf/.config/herdr/config.toml" ~/.config/herdr/config.toml
}

#---------------------------------------------------------------------------
# CONTAINER
#---------------------------------------------------------------------------

# Plugin manifests invoke ./target/release/<bin> relative to the plugin root, so
# the binary must live in the checkout — but the ~119M of intermediates around it
# must not reach the layer. Pruning here (not in a later RUN) is what makes the
# image actually smaller; a subsequent RUN would only mask the bytes.
prune_plugins() {
  local dir keep
  for dir in "$PLUGIN_SRC"/*/; do
    [[ -d "${dir}target/release" ]] || continue
    keep=$(mktemp -d)
    find "${dir}target/release" -maxdepth 1 -type f -executable -exec cp -p {} "$keep/" \;
    rm -rf "${dir}target"
    mkdir -p "${dir}target/release"
    cp -a "$keep"/. "${dir}target/release/"
    rm -rf "$keep"
    say "pruned $(basename "$dir") -> $(du -sh "$dir" | cut -f1)"
  done
}

install_container() {
  install_herdr

  # keep plugin build artifacts in their checkouts
  unset CARGO_TARGET_DIR

  local p
  for p in "${PLUGINS[@]}"; do
    herdr plugin install "$p" --yes
  done

  prune_plugins

  # herdr-spreader also ships a CLI. Symlink the plugin's own binary rather than
  # `cargo install`-ing the crate a second time: that built the same commit into
  # a separate target dir (~77M of intermediates baked into the layer, since that
  # RUN had no cache mount) and let the CLI drift from the pinned plugin action.
  local spreader
  spreader=$(echo "$PLUGIN_SRC"/herdr-spreader-*/target/release/herdr-spreader)
  if [[ -x "$spreader" ]]; then
    mkdir -p ~/.local/bin
    ln -sfv "$spreader" ~/.local/bin/herdr-spreader
  else
    say "WARNING: herdr-spreader binary not found; CLI unavailable" >&2
  fi

  link_config
}

#---------------------------------------------------------------------------
# HOST
#---------------------------------------------------------------------------

# The plugin binaries link libc/libgcc and nothing else, so they run on any host
# at or above the glibc they were built against and fail to start below it.
# Catch that here rather than as a silent plugin failure later.
check_abi() {
  local bundle_glibc host_glibc
  bundle_glibc=$(awk '/GLIBC|GNU libc/ {print $NF}' "$BUNDLE_DIR/BUNDLE.txt" 2>/dev/null || true)
  host_glibc=$(ldd --version | head -1 | awk '{print $NF}')

  [[ -n "$bundle_glibc" ]] || return 0
  [[ "$(printf '%s\n%s\n' "$bundle_glibc" "$host_glibc" | sort -V | head -1)" == "$bundle_glibc" ]] && return 0

  cat >&2 <<EOF
[herdr] ABI mismatch: plugins were built against glibc ${bundle_glibc},
        this host has ${host_glibc}. The plugin binaries will not start.
        Rebuild the image's plugins against x86_64-unknown-linux-musl, or
        install herdr without plugins on this host.
EOF
  exit 1
}

install_host() {
  command -v docker >/dev/null || {
    say "docker required to extract the plugin bundle from ${XNDV_IMAGE}" >&2
    exit 1
  }
  docker image inspect "$XNDV_IMAGE" &>/dev/null || {
    say "image ${XNDV_IMAGE} not found — build it first (make build-tty)" >&2
    exit 1
  }

  install_herdr

  say "extracting plugin bundle from ${XNDV_IMAGE}"
  rm -rf "$BUNDLE_DIR"
  mkdir -p "$BUNDLE_DIR"
  # --rm so nothing is left behind on a disk-constrained host; XNDV_DIR is an
  # image ENV, and the explicit path avoids sourcing any shell rc onto stdout
  docker run --rm "$XNDV_IMAGE" sh -c 'exec "$XNDV_DIR/bin/x-herdr-bundle"' |
    tar -C "$BUNDLE_DIR" -xzf -

  check_abi

  local dir
  for dir in "$BUNDLE_DIR"/*/; do
    [[ -f "${dir}herdr-plugin.toml" ]] || continue
    herdr plugin link "$dir" --enabled >/dev/null
    say "linked $(basename "$dir")"
  done

  link_config

  say "done — $(du -sh "$BUNDLE_DIR" | cut -f1) in ${BUNDLE_DIR}"
  say "restart herdr (or: herdr update --handoff) to fire plugin startup hooks"
}

"install_${MODE}"

# vim ft=bash
