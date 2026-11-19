---
name: xndv-tool
description: Add a tool to the xndv Docker image following the house patterns, or remove one completely. Covers the Dockerfile, build flags, README and fish completions.
metadata:
  usage: |
    /xndv-tool add <tool name | tool URL> [--opt-in]
    /xndv-tool rm <tool name>
---

# xndv-tool

`add` installs a tool the way the house already does. `rm` is its exact inverse: it walks the
same surfaces and leaves no trace. Read the neighbouring blocks in the source, and let the
source win.

## Surfaces

1. **Dockerfile** — `Dockerfile` (`xen/dev`) by default. `Dockerfile.x11` only for a clearly
   desktop tool, `Dockerfile.sys` only for a clearly sysbox tool. If unclear, ask.
   - **Root or user:** apt packages and `/usr/local/bin` binaries go above `USER ${_USER}`.
     User-level installers (`uv tool`, `cargo binstall`, `go install`, `bun add -g`, `~/.local/bin`)
     go below it. Place the install after whatever it needs (`gh-latest`, go, rust, bun, node).
   - **Join an existing list** when one fits (the main `apt install`, `cargo binstall`,
     `go install`, `bun add -g`), alphabetically. Otherwise add a commented `RUN` next to its kin.
   - **Use the cache, always when possible:** `--mount=type=cache` with the house ids:
     `apt-archives` + `apt-lists`, `dl` (root) or `dlu` (user, `uid=${_USER_ID}`) for
     `wget -qN -P` downloads, `uv-cache`, `cargo-registry` + `cargo-target`, `cpanm-cache`.
   - **Latest by default:** `gh-latest <owner/repo> [prefix]` resolves GitHub releases.
2. **`INSTALL_X`** (only with `--opt-in`) — `ARG INSTALL_X=0` and an
   `if [ "${INSTALL_X}" = "1" ]; then … ; fi` block in the Dockerfile, `- INSTALL_X` in the build
   service's `args` in `docker-compose.yml`, `INSTALL_X=0` in `.env-example`, and `_(INSTALL_X)_`
   on the README entry. Keep every list alphabetical.
3. **`VERSION_X`** (sparingly) — only when latest is impossible or not discernible by script, or
   when latest would break dependencies. `ARG VERSION_X` directly above its use, `- VERSION_X` in
   the compose `args`, and the value under `# versions` in `.env-example`. Say why in a dated
   `# NOTE:` comment.
4. **README** — `## Tools` is an awesome-list, grouped into sections (Editor & Plugins,
   AI/Agentic Coding, Shell & Terminal, …). Insert into the right section in
   **case-insensitive alphabetical order** (`Bun`, `Deno`, `Go`):
   ```markdown
   - [ToolName](https://github.com/org/repo): Brief description
   - [Nix](https://github.com/NixOS/nix): Purely functional package manager _(INSTALL_NIX)_
   - [fish-shell](https://github.com/fish-shell/fish-shell): User-friendly command line shell
     - [fisher](https://github.com/jorgebucaran/fisher): Plugin manager for Fish
   ```
   Opt-in tools carry the `_(INSTALL_X)_` suffix; sub-tools (plugins, extensions) indent under
   their parent. Example: `htop` goes in Utilities, between `ImageMagick` and `kpcli`.
5. **Fish completions** — if the tool prints its own, add `_complete <cmd> <args>` to the
   `status is-interactive` block of `conf/.config/fish/config.fish`, alphabetically.
   `_complete` skips missing tools, caches the output and regenerates it when the binary
   changes. Install into `/usr/share/fish/vendor_completions.d/` at build time only when the
   completions come from a separate generator (as with git-cliff).
6. **Theme and config** — if the tool has a tinted template or ships config:
   `conf/.config/tinted-theming/tinty/config.toml` and/or `conf/.config/<tool>/` (add it to the
   stow step's `mkdir -p` list if the directory must not become a symlink).

## add

1. Resolve the tool: a name → its upstream repo; a URL → its install docs. Prefer the installer
   the house already uses for that ecosystem.
2. Walk the surfaces. Without `--opt-in`, if the tool adds significantly to image size or build
   time, **suggest** `--opt-in` and say why. Don't apply it unasked.

## rm

Search the whole repo for the tool (`rg -i <tool>`), then undo every surface: list entries,
`RUN` blocks, `ARG`s, compose args, `.env-example` lines, the README entry, the completion line
and config. Leave anything that shares a block with it intact. Report any remaining reference you
didn't remove, such as another tool that depends on it.

## Finish

Agents must not run `make` (`AGENTS.md`), so the build is the operator's check. End with the
surfaces you changed and the check to run: set `INSTALL_X=1` in `.env` if opted in, then
`make build`, then `<tool> --version` in a new container (and a tab-completion if added).
