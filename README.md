# XNDV ~ xen/dev:latest

XNDV is a sandboxed, GPU-accelerated, terminal-first development environment. A ready-to-run box of overpowered dotfiles, like a living Awesome List of development tools, all wired into the same AI control plane.

Unify agentic tools through a local AI gateway for greater visibility, multi-provider resilience, OAuth-friendly logins, and optional local LLMs.

Run it as a:

- **GPU-accelerated terminal** with clipboard integration ← recommended
- **TTY-only terminal** for headless servers
- **Full desktop environment** in a window (x11docker)
- **Docker-in-Docker environment** for nested containers (sysbox)

> Developed on and for Linux. Other platforms untested.

## Quickstart

```sh
git clone https://github.com/xendarboh/xndv.git ~/src/xndv
cd ~/src/xndv
cp .env-example .env                 # edit to enable optional tools
cp -a conf.local-example conf.local  # local overrides (see Customization)
make build                           # headless server? use `make build-tty-sys` instead
./bin.host/xndv
# optionally add ~/src/xndv/bin.host to your PATH for direct access to the launcher
```

`make build` produces the X11 images for a desktop host; `make build-tty-sys` produces the
smaller TTY-only images (no X11, no x11docker needed) for headless servers. See [Build](#build).

## Philosophy

- Open Source!
- Latest greatest terminal tools, LTS versions, vi-bindings
- Unified theming via [tinty](https://github.com/tinted-theming/tinty) with native Neovim colorscheme sync
- Reproducible environment from [Ubuntu](https://hub.docker.com/_/ubuntu) base
- Security via sandboxing with analog control over isolation vs. functionality

## Host Dependencies

| Dependency                                                                                  | Required For              | Notes                                                                                                                                               |
| :------------------------------------------------------------------------------------------ | :------------------------ | :-------------------------------------------------------------------------------------------------------------------------------------------------- |
| docker or podman                                                                            | Core                      | Container runtime                                                                                                                                   |
| docker compose                                                                              | Building                  | Build orchestration                                                                                                                                 |
| make                                                                                        | Building                  | Recommended; or run [Makefile](Makefile) commands manually                                                                                          |
| [x11docker](https://github.com/mviereck/x11docker#installation)                             | `max`, `min`, `sys` (x11) | Desktop/GUI runner only; not needed for `tty` mode or headless (`sys` on a server). Install with `make install-x11docker`                           |
| NVIDIA driver runfile (optional)                                                            | GPU in `min`, `sys`       | `make fetch-nvidia-driver` caches the host-matching installer for x11docker's fallback GPU                                                          |
| [sysbox](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/install-package.md) | `sys` mode                | Recommended for Docker-in-Docker                                                                                                                    |
| rofi / dmenu / fzf                                                                          | Launcher                  | Any one; detected in order                                                                                                                          |
| `pactl` (`pulseaudio-utils`) or PipeWire ≥ 1.4                                              | Audio (optional)          | Host sound server + client tool x11docker probes; see [Audio](#audio)                                                                               |
| [Nerd Font](https://github.com/ryanoasis/nerd-fonts#font-installation)                      | `tty` mode                | Container provides fonts for GUI modes                                                                                                              |
| [Docker Model Runner](https://docs.docker.com/ai/model-runner/)                             | Local AI (optional)       | GPU-accelerated inference via [nvidia-container-toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html), etc |

## Run

### Launcher

The `bin.host/xndv` launcher provides an interactive menu (via `rofi`, `dmenu`, or `fzf`) for selecting modes, naming containers, and toggling volume mounts.

| Mode  | Description                                                       | X11 |   GPU    | Use Case                           |
| ----- | ----------------------------------------------------------------- | :-: | :------: | ---------------------------------- |
| `max` | Most host integration, direct GPU                                 | Yes |  Direct  | Daily development                  |
| `min` | Minimal host integration, fallback GPU                            | Yes | Fallback | Sandboxed agents, untrusted code   |
| `sys` | Docker-in-Docker via [sysbox](https://github.com/nestybox/sysbox) | Yes | Fallback | Stronger isolation, run containers |
| `tty` | TTY-only, no X11                                                  | No  |    No    | Headless servers, SSH sessions     |

All modes are containerized and sandboxed; the difference is capability and host integration.

**Runner**: A mode is launched under one of two runners — `x11` (x11docker + kitty window) or `tty` (headless `docker run -d`, re-enter via the menu). The launcher offers only the runners your host supports (x11docker installed vs. not) and only modes whose image is built. On a server without x11docker, `sys` and `tty` run headless automatically; where x11docker is installed, modes that support both (e.g. `sys`) show a runner choice (`sys·x11`, `sys·tty`).

**Selector**: The launcher probes for an available selector. Override with `xndv -s <selector>`.

```sh
# interactive launcher: create or enter a container
xndv

# enter directly; maps host $PWD and remains in shell after the command exits
xndv enter xndv-sys -- lazygit

# omit the name with XNDV_CONTAINER or exactly one running container
XNDV_CONTAINER=xndv-sys xndv enter -- lazygit
xndv enter -- lazygit

# override the mapped working directory
xndv enter xndv-sys -C /container/path -- lazygit

# pass agent identity through herdr
HERDR_AGENT=claude xndv enter xndv-sys -- claude "/do-stuff"

# quote compound (fish shell) commands
xndv enter xndv-sys -- 'git status; lazygit'
```

### No Launcher

Run directly without the interactive menu, for example:

```sh
# GPU-accelerated terminal with clipboard
x11docker --gpu --clipboard --network --user=RETAIN -- --tmpfs=/tmp:exec -- xen/dev

# Full desktop in a window
x11docker --desktop --gpu --clipboard --network -- xen/dev

# TTY-only (no x11docker needed)
docker run -it --rm --network=host xen/dev
```

### Docker-in-Docker (Sysbox)

The `sys` mode uses [sysbox](https://github.com/nestybox/sysbox) for secure, rootless Docker-in-Docker without `--privileged`.

**Headless servers**: `sys` runs without x11docker. Build with `make build-tty-sys` (stacks `xen/sys` on the TTY `xen/dev`, no X11 layer) and the launcher runs it via plain `docker run -d` — create the instance, then re-enter it from the launcher menu (`docker exec`). x11docker is not required.

**Tradeoffs**: No direct GPU (uses `--gpu` fallback under x11), bridged networking (no `--network=host`).

**Persistence**: Inner Docker data stored at `~/.local/share/xndv/xndv/sysbox/docker`.

### Audio

Off by default. Sound is provided by the host's sound server — the container only ever runs clients — and x11docker does the wiring, so audio applies to the `x11` runner (`max`, `min`, `sys·x11`), not to headless `tty`.

```sh
# in .env
ENABLE_AUDIO=1

make build            # adds sound clients to the xen/x11 image
./bin.host/xndv       # launcher adds the sound option to x11docker
./test/audio.sh       # from inside the container: verify and play a sound
./test/microphone.sh  # record five seconds, then play the recording back
```

`AUDIO_MODE` names an [x11docker](https://github.com/mviereck/x11docker) sound option, written without its leading dashes. The default `auto` probes the host and picks the first that fits:

| `AUDIO_MODE`        | What it shares                                       | `auto` selects it when                                        |
| :------------------ | :--------------------------------------------------- | :------------------------------------------------------------ |
| `pipewire`          | Sandboxed PipeWire socket minted by `pw-container`   | Host runs PipeWire ≥ 1.4                                      |
| `pulseaudio=host`   | The host's existing PulseAudio/pipewire-pulse socket | Host runs `pipewire-pulse`, which cannot mint a second socket |
| `pulseaudio=socket` | A dedicated socket minted via `pactl`                | Host runs classic PulseAudio                                  |
| `pulseaudio=tcp`    | A PulseAudio TCP port                                | `sys` mode — sysbox cannot reach the host user's runtime dir  |
| `alsa[=CARD]`       | `/dev/snd` directly, bypassing the host sound server | Nothing else is available                                     |

Override with any of the above, e.g. `AUDIO_MODE=alsa=PCH` (card names from `aplay -l`).

**Caveats**:

- Every mode lets container applications capture audio output and microphone input — this is a deliberate loosening of isolation, which is why it is opt-in.
- `alsa` bypasses the host sound server, so host and container will fight over the device. Prefer a `pulseaudio` or `pipewire` mode whenever a sound server is running.
- Ubuntu 24.04 ships PipeWire 1.0, which has no `pw-container`; `--pipewire` needs 25.04 or newer. `pulseaudio=host` is the equivalent there.
- x11docker falls back to no sound rather than failing the launch. Run with `--verbose` (already set for `max`/`min`/`sys`) to see which option it settled on.
- `pulseaudio=host` and `pipewire` bind their socket under `/tmp`, where these modes also mount `--tmpfs=/tmp:exec`. Docker orders the tmpfs first so the socket lands inside it; if a silent container turns out to be missing `/tmp/*.socket.host`, use `AUDIO_MODE=pulseaudio=tcp`.

## Tools

> `{alias}` — invoke via shell alias (like `oc` for OpenCode).

### Powered By

- [x11docker](https://github.com/mviereck/x11docker): Secure GUI containers
- [Sysbox](https://github.com/nestybox/sysbox): Rootless system containers, enabling Docker-in-Docker
- [Xen](https://github.com/xendarboh): Elven Tech Wizard

### Editor & Plugins

- [Neovim](https://github.com/neovim/neovim): Vim-fork focused on extensibility and usability
  - [LazyVim](https://github.com/LazyVim/LazyVim): Neovim config for the lazy _(INSTALL_NVIM_LAZYVIM)_
    - [avante.nvim](https://github.com/yetone/avante.nvim): Use your Neovim like using Cursor AI IDE!
    - [better-escape.nvim](https://github.com/max397574/better-escape.nvim): Escape from insert mode without delay
    - [gruvbox.nvim](https://github.com/ellisonleao/gruvbox.nvim): Gruvbox colorscheme
    - [herdr-splits.nvim](https://github.com/lmilojevicc/herdr-splits.nvim): Seamless navigation and resizing between Neovim and herdr
    - [markdown-preview.nvim](https://github.com/iamcco/markdown-preview.nvim): Markdown preview plugin
    - [noir.nvim](https://github.com/noir-lang/noir-nvim): Syntax highlighting and LSP for Noir
    - [nx.nvim](https://github.com/Equilibris/nx.nvim): NX console features for Neovim
    - [tinted-nvim](https://github.com/tinted-theming/tinted-nvim): Tinty colorscheme sync with native fallback
    - [tokyonight.nvim](https://github.com/folke/tokyonight.nvim): Tokyo Night colorscheme
    - [tuicr.nvim](https://github.com/xendarboh/tuicr.nvim): Neovim integration for tuicr
    - [wakatime.nvim](https://github.com/wakatime/vim-wakatime): Automatic time tracking

### AI/Agentic Coding

- [aider](https://github.com/Aider-AI/aider): AI pair programming in your terminal _(INSTALL_AIDER)_
  - [aider.nvim](https://github.com/joshuavial/aider.nvim): Neovim integration for aider
- [claude-code](https://github.com/anthropics/claude-code): Agentic coding tool in your terminal _(INSTALL_CLAUDECODE)_
  - [GSD](https://github.com/gsd-build/get-shit-done): Meta-prompting and spec-driven development system
- [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI): OAuth adapter for login-based LLM providers
  - [CLIProxyAPI Quota Inspector](https://github.com/AllenReder/CLIProxyAPI-Quota-Inspector): Terminal tool for monitoring CPA quota usage
- [Codex](https://github.com/openai/codex): Lightweight coding agent that runs in your terminal _(INSTALL_CODEX)_
- [Docker Model Runner](https://docs.docker.com/ai/model-runner/) (DMR): Run LLMs locally via Docker
- [herdr](https://github.com/ogulcancelik/herdr): Agent multiplexer that lives in your terminal
  - [herdr-git-status](https://github.com/ezcorp-org/herdr-git-status): Shows each space's git working-tree status in the sidebar
  - [herdr-splits.nvim](https://github.com/lmilojevicc/herdr-splits.nvim): Seamless navigation and resizing between Neovim and herdr
  - [herdr-spreader](https://github.com/yuk1ty/herdr-spreader): Reproduce herdr workspace layouts from declarative YAML files
- [LiteLLM](https://github.com/BerriAI/litellm): Unified LLM proxy — 100+ providers, one endpoint, cost tracking, caching
- [llmfit](https://github.com/AlexsJones/llmfit): Score and rank LLMs by hardware fit (RAM, CPU, GPU)
- [Oh My Pi](https://github.com/can1357/oh-my-pi): Batteries-included terminal coding agent with LSP, debugger, and subagents _(INSTALL_OMP)_
  - [worked-for](conf/.omp/agent/extensions/worked-for.ts): xndv extension showing elapsed agent work time
- [Open WebUI](https://github.com/open-webui/open-webui): Chat UI for local LLMs
- [OpenCode](https://github.com/anomalyco/opencode): Open source coding agent _(INSTALL_OPENCODE)_ `{oc}`
  - [GSD](https://github.com/gsd-build/get-shit-done): Meta-prompting and spec-driven development system
  - [opentmux](https://github.com/AnganSamadder/opentmux): Smart tmux integration for real-time agent panes
  - [opencode-notifier](https://github.com/mohak34/opencode-notifier): Desktop notifications for OpenCode
  - [opencode-wakatime](https://github.com/angristan/opencode-wakatime): OpenCode usage time tracking
  - [opencode.nvim](https://github.com/nickjvandyke/opencode.nvim): Neovim integration for opencode
- [OpenPackage](https://github.com/enulus/openpackage): Universal package manager for AI coding agent skills/rules/commands
- [repomix](https://github.com/yamadashy/repomix): Pack repository into AI-friendly file
- [rtk](https://github.com/rtk-ai/rtk): Token-optimized CLI proxy (60-90% token savings on dev operations)
- [tuicr](https://github.com/agavra/tuicr): Human-in-the-loop code review TUI for AI-generated changes

### Shell & Terminal

- [ack](https://github.com/beyondgrep/ack3): Grep-like tool for searching code
- [bat](https://github.com/sharkdp/bat): A cat(1) clone with syntax highlighting
- [btop](https://github.com/aristocratos/btop): Resource monitor with GPU support
- [exa](https://github.com/ogham/exa): Modern replacement for 'ls'
- [fd](https://github.com/sharkdp/fd): Simple, fast alternative to 'find'
- [fish-shell](https://github.com/fish-shell/fish-shell): User-friendly command line shell
  - [fish-exa](https://github.com/gazorby/fish-exa): exa aliases for fish
  - [fish-nx](https://github.com/jukben/fish-nx): Fish completions for Nx
  - [fisher](https://github.com/jorgebucaran/fisher): Plugin manager for Fish
  - [nix-env.fish](https://github.com/lilyball/nix-env.fish): Nix environment for fish _(INSTALL_NIX)_
  - Shortcuts: see [Shell Shortcuts](#shell-shortcuts)
- [fzf](https://github.com/junegunn/fzf): Command-line fuzzy finder
- [htop](https://github.com/htop-dev/htop): Interactive process viewer
- [mani](https://github.com/alajmo/mani): CLI tool to help you manage multiple repositories
- [jq](https://github.com/stedolan/jq): Command-line JSON processor
- [ripgrep](https://github.com/BurntSushi/ripgrep): Fast regex search respecting gitignore
- [silversearcher-ag](https://github.com/ggreer/the_silver_searcher): Code search faster than ack
- [ShellCheck](https://github.com/koalaman/shellcheck): Shell script static analysis tool
- [spacer](https://github.com/samwho/spacer): Insert spacers in command output
- [starship](https://github.com/starship/starship): Minimal, fast, customizable prompt
- [stow](https://github.com/aspiers/stow): Symlink farm manager
- [tinty](https://github.com/tinted-theming/tinty): Unified colorscheme manager for 70+ apps
- [tmux](https://github.com/tmux/tmux): Terminal multiplexer
  - [tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect): Persist environment across restarts
  - [tmux-window-name](https://github.com/ofirgall/tmux-window-name): Smart window naming
  - [tpm](https://github.com/tmux-plugins/tpm): Tmux Plugin Manager
- [tree](https://github.com/Old-Man-Programmer/tree): Directory tree viewer
- [zoxide](https://github.com/ajeetdsouza/zoxide): Smarter cd command

### Git & Version Control

- [delta](https://github.com/dandavison/delta): Syntax-highlighting pager for git, diff, grep, and blame output
- [gh](https://github.com/cli/cli): GitHub's official CLI
- [git](https://github.com/git/git): Latest stable version
  - [git-absorb](https://github.com/tummychow/git-absorb): Automatic fixup commits
  - [git-crypt](https://github.com/xendarboh/git-crypt): Transparent file encryption \[fork\]
  - [git-filter-repo](https://github.com/newren/git-filter-repo): Rewrite git history fast
    - gfr-bfg-ish: BFG Repo Cleaner reimplementation
    - gfr-clean-ignore: Remove gitignored files from history
    - gfr-insert-beginning: Insert a file at history start
    - gfr-lint-history: Lint all non-binary files across history
    - gfr-signed-off-by: Add Signed-off-by tags to commit range
  - [git-lfs](https://github.com/git-lfs/git-lfs): Large file versioning
- [lazygit](https://github.com/jesseduffield/lazygit): Terminal UI for git `{lz}`

### Languages & Runtimes

- [Bun](https://github.com/oven-sh/bun): Fast JS runtime, bundler, test runner, package manager
- [Deno](https://github.com/denoland/deno): Modern JavaScript/TypeScript runtime
- [Go](https://github.com/golang/go): The Go programming language
- [LLVM](https://github.com/llvm/llvm-project): Clang toolchain _(INSTALL_LLVM)_
- [Nix](https://github.com/NixOS/nix): Purely functional package manager _(INSTALL_NIX)_
- [Node.js](https://github.com/nodejs/node): JavaScript runtime
  - [fnm](https://github.com/Schniz/fnm): Fast Node.js version manager
  - [npm-check-updates](https://github.com/raineorshine/npm-check-updates): Find newer package versions
  - [npm-check](https://github.com/dylang/npm-check): Check for outdated dependencies
  - [pnpm](https://github.com/pnpm/pnpm): Fast, disk space efficient package manager
  - [yarn](https://github.com/yarnpkg/yarn): Dependency management
- [Python](https://www.python.org): Programming language
  - [uv](https://github.com/astral-sh/uv): Extremely fast Python package and project manager
- [Ruby](https://github.com/ruby/ruby): Dynamic programming language
  - [rake](https://github.com/ruby/rake): Ruby build automation tool
- [Rust](https://github.com/rust-lang/rust): Reliable and efficient software
  - [cargo-edit](https://github.com/killercup/cargo-edit): Manage cargo dependencies from CLI
  - [rust-analyzer](https://github.com/rust-lang/rust-analyzer): Rust compiler front-end for IDEs
  - [rustup](https://github.com/rust-lang/rustup): Rust toolchain installer

### ZK & Blockchain

- [circom](https://github.com/iden3/circom): zkSnark circuit compiler _(INSTALL_CIRCOM)_
- [Noir](https://github.com/noir-lang/noir): DSL for zero knowledge proofs _(INSTALL_NOIR)_
  - [barretenberg](https://github.com/AztecProtocol/aztec-packages): ZK prover backend
- [Solidity](https://github.com/ethereum/solidity): Smart contract language

### DevOps _(INSTALL_DEVOPS)_

- [Ansible](https://github.com/ansible/ansible): IT automation
- [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-welcome.html): AWS interaction
- [OpenTofu](https://github.com/opentofu/opentofu): Open source Terraform alternative
- [Packer](https://github.com/hashicorp/packer): Machine image builder
- [terraform-local](https://github.com/localstack/terraform-local): Deploy to LocalStack
- [Terraform](https://github.com/hashicorp/terraform): Infrastructure as code

### Utilities

- [CMake](https://gitlab.kitware.com/cmake/cmake): Cross-platform build system generator
- [cpanminus](https://github.com/miyagawa/cpanminus): CPAN module installer
- [cypress](https://github.com/cypress-io/cypress): Browser testing deps _(INSTALL_CYPRESS_DEPS)_
- [dprint](https://github.com/dprint/dprint): Pluggable and configurable code formatting platform
- [fastmod](https://github.com/facebookincubator/fastmod): Large-scale codebase refactors
- [grip](https://github.com/joeyespo/grip): GitHub Markdown preview server _(INSTALL_GRIP)_
- [ImageMagick](https://github.com/ImageMagick/ImageMagick): Image manipulation
- [kpcli](http://kpcli.sourceforge.net/): KeePass CLI
- [ncdu](https://code.blicky.net/yorhel/ncdu): NCurses Disk Usage
- [ninja-build](https://github.com/ninja-build/ninja): Fast build system
- [platformio-core](https://github.com/platformio/platformio-core): Embedded development _(INSTALL_PLATFORMIO)_
- [prettier](https://github.com/prettier/prettier): Opinionated code formatter
- [protobuf](https://github.com/protocolbuffers/protobuf): Protocol Buffers _(INSTALL_PB)_
  - [buf](https://github.com/bufbuild/buf): Modern protobuf workflow
- [ranger](https://github.com/ranger/ranger): VIM-inspired file manager
- [sqlite](https://github.com/sqlite/sqlite): SQL database engine
- [tauri-cli](https://github.com/tauri-apps/tauri): Build desktop apps _(INSTALL_TAURI)_
- [Tomb](https://github.com/dyne/Tomb): Crypto Undertaker _(INSTALL_TOMB)_
- [tree-sitter-cli](https://github.com/tree-sitter/tree-sitter/tree/master/crates/cli): Parser generator for syntax trees
- [watchexec](https://github.com/watchexec/watchexec): Execute on file changes
- [websocat](https://github.com/vi/websocat): WebSocket CLI client

### X11 Desktop

- [Brave browser](https://github.com/brave/brave-browser) _(INSTALL_BROWSER_BRAVE)_
- [Chromium](https://github.com/chromium/chromium) _(INSTALL_BROWSER_CHROMIUM)_
- [kitty](https://github.com/kovidgoyal/kitty): GPU-accelerated terminal
- [Nerd Fonts](https://github.com/ryanoasis/nerd-fonts): Developer fonts with icons
  - [Hack](https://github.com/ryanoasis/nerd-fonts/tree/master/patched-fonts/Hack): Typeface for code
- [xclip](https://github.com/astrand/xclip): X11 clipboard CLI
- [Xfce](https://gitlab.xfce.org/xfce): Lightweight desktop environment
  - [xfce4-notifyd](https://docs.xfce.org/apps/notifyd/start): Desktop notification daemon
  - [xfce4-taskmanager](https://docs.xfce.org/apps/xfce4-taskmanager/start): Process/task manager
  - [xfce4-terminal](https://docs.xfce.org/apps/terminal/start): Terminal emulator

### Sysbox Runtime

- [docker](https://github.com/docker/cli): The Docker CLI
  - [docker-compose](https://github.com/docker/compose): Orchestrate multi-container Docker apps

### Built-in Scripts

Scripts in [bin/](bin/) are available inside the container:

- [x-ai](bin/x-ai): Query a local LLM (via Docker Model Runner) directly from the terminal
- [x-aztec-ai-tools](bin/x-aztec-ai-tools): Setup a project with [Aztec/Noir AI Tooling](https://docs.aztec.network/developers/ai_tooling) (MCP servers, skills, platform configs)
- [x-git-commit](bin/x-git-commit): AI-generated conventional git commit messages
  - auto-selects local LLM (DMR) when available, falls back to opencode
  - opens editor (neovim) with N alternatives for final selection
  - invoke from lazygit with `CTRL+a`
- [x-herdr-clear](bin/x-herdr-clear): Clear the current herdr pane's agent authority
- [x-herdr-exec](bin/x-herdr-exec): Run a command while reporting its state to the herdr pane
- [x-herdr-spreader-apply](bin/x-herdr-spreader-apply): Apply every `herdr-spreader.yaml` found beneath the current directory
  - `--dry-run` lists the files without applying them

Scripts in [bin.host/](bin.host/) run on the host (outside the container):

- [xndv](bin.host/xndv): Interactive menu and direct entry for managing the xndv environment
  - `launch`: Select mode, name container, toggle mounts, attach to running instances
  - `clean`: Disk monitor and selective cleanup for host-persistent directories
  - `enter`: Enter a running instance, optionally run a command, then remain in Fish

### Runtime Scripts

Optional tools installed on-demand via [setup.d/](setup.d/):

- [Aztec Toolchain](https://github.com/AztecProtocol/aztec-packages): Privacy-first L2
- [WhisperX](https://github.com/m-bain/whisperX): Speech recognition with timestamps

## Shell Shortcuts

Fish abbreviations and functions from [config.fish](conf/.config/fish/config.fish), available in every container shell:

| Shortcut    | Runs                                                               |
| :---------- | :----------------------------------------------------------------- |
| `s`         | `git status`                                                       |
| `d`         | `git diff`                                                         |
| `b`         | `git branch -av`                                                   |
| `gb`        | `git branch`                                                       |
| `gg`        | `git grep`                                                         |
| `gl`        | `git log --show-signature`                                         |
| `gln`       | `git log --oneline \| nl`                                          |
| `ga`        | `git absorb --base HEAD~N`; `N` = commits ahead of upstream        |
| `gr [N]`    | `git rebase -i --autosquash HEAD~N`; `N` defaults to commits ahead |
| `gra [N]`   | `gr` + `--exec` amend each commit with `--reset-author`            |
| `see [DUR]` | files changed within `DUR` (default `1m`) via `fd`, noise-filtered |
| `vimgit X`  | open every file with git status code `X` in nvim, e.g. `vimgit M`  |
| `mkcd DIR`  | `mkdir -p DIR` then `cd` into it                                   |
| `dc`        | `docker compose`                                                   |
| `fm`        | `fastmod --hidden`                                                 |
| `grip`      | `grip --theme=dark`                                                |
| `hc`        | `x-herdr-clear`                                                    |
| `hs`        | `x-herdr-spreader-apply`                                           |
| `hx`        | `x-herdr-exec`                                                     |
| `kt-clip`   | `kitty +kitten clipboard`                                          |
| `kt-diff`   | `kitty +kitten diff`                                               |
| `kt-icat`   | `kitty +kitten icat`                                               |
| `lz`        | `lazygit`                                                          |
| `oc`        | `opencode`                                                         |
| `tc`        | `tinty cycle` through configured themes                            |
| `v`         | `nvim`                                                             |
| `vd`        | `nvim -d` (diff mode)                                              |
| `vr`        | `nvim -R` (read-only)                                              |
| `x`         | `cd $XNDV_DIR` then open nvim there                                |

Two commands are also transparently wrapped: `nx` repaints the prompt afterward, and `tuicr` adds
`--no-update-check --stdout` and copies its output to the clipboard. Where installed,
`brave-browser` and `chromium-browser` gain `--no-sandbox`.

## Build

### Configure

Edit `.env` to set versions and enable optional tools (copy from `.env-example`).

### Build Images

```sh
make build          # X11 images: xen/x11 → xen/dev → xen/sys
make build-tty      # TTY-only image (smaller, no X11)
make build-tty-sys  # TTY-only + sysbox layer, for headless `sys` mode
make help           # all available targets
```

### Rebuild & Maintain

```sh
make retag          # tag current images :prev first, to keep a rollback
make rebuild        # rebuild X11 images with --no-cache, pulling a fresh base
make rebuild-tty    # same for TTY-only (also: make rebuild-tty-sys)
make refresh        # pull peripheral images (models, gateway) and reinstall the DMR runner
```

## Tests

Verify terminal and environment capabilities with scripts in [test/](test/):

```sh
./test/truecolor.sh          # terminal color support
./test/tput.sh               # 256-color tput table
./test/glyphs.sh             # nerd font rendering
./test/test-fonts.sh         # full nerd font codepoint sweep
./test/kitty-debug-fonts.sh  # log kitty's font fallback chain
./test/italics.sh            # italic text
./test/gpg.sh                # GPG volume mapping
./test/audio.sh              # sound wiring and playback (requires ENABLE_AUDIO=1)
./test/microphone.sh         # microphone recording and playback (requires ENABLE_AUDIO=1)
./test/herdr-notification.sh # herdr notification (title, body, sound)
./test/ai-gateway.sh         # LLM gateway routes; run from the host with the gateway up
```

## Customization

### Dotfiles

- `conf/` — Git-tracked user configuration, stowed to the user's home directory during the image build
- `conf.local/` — Private/local user configuration, gitignored and stowed to the user's home directory at runtime
- `conf.system/` — Git-tracked system configuration, stowed to the root filesystem (`/`) during the image build

The build-time Stow links target files under the xndv source tree. When the host source tree is mounted at
`~/src`, edits to existing files in `conf/` and `conf.system/` are visible in the container without rebuilding
the image. For example, `conf.system/etc/codex/config.toml` is available as `/etc/codex/config.toml`.

Runtime-only and private files belong in `conf.local/` (for example, `conf.local/.aws/` → `~/.aws/`):

```sh
cp -a conf.local-example conf.local
```

Notable files in `conf.local/`, for example:

| File                     | Purpose                                             |
| :----------------------- | :-------------------------------------------------- |
| `xndv/bash.sh`           | Custom env vars (`GH_TOKEN`, `FLEEK_API_KEY`, etc.) |
| `xndv/directory_map.txt` | Path mappings for tmux/kitty CWD preservation       |
| `.wakatime.cfg`          | Wakatime/Wakapi config                              |
| `.aws/`                  | AWS credentials                                     |

### herdr

The image installs the latest stable herdr with some herdr plugins. Run the same installer directly on a
host when the herdr server lives outside xndv:

```sh
make install-herdr       # or: ./build/install.d/herdr.sh
```

On a host this installs herdr (a static binary — no toolchain) and links the plugin binaries already built
in the `xen/dev` image, extracted via a throwaway container to minimize host dependencies. Re-run after rebuilding the image to
pick up newer plugins.

Configuration remains Stow-managed. When launched from a host herdr pane, `bin.host/xndv` mounts the host
herdr directory at `~/.config/herdr-host` inside the container and forwards its socket, pane, client, and
herdr-splits environment. Use herdr's foreground-process hint when xndv wraps an agent, for example:

```sh
HERDR_AGENT=codex ./bin.host/xndv enter xndv-sys -- codex '$worker-prime $msg wC'
```

Remote clients should use the server's plugin-action keybindings:

```sh
herdr --remote <host> --remote-keybindings server
```

### Git Config

Include xndv's git config conditionally:

```gitconfig
# ~/.config/git/config
[includeIf "gitdir:/home/xndv"]
  path = ~/src/xndv/conf/gitconfig
```

### Themes

Colorschemes are managed by [tinty](https://github.com/tinted-theming/tinty), providing unified theming across apps.

Set `OPTIONS_THEME` in `.env` for the image build-time default.

Neovim listens for theme changes and applies the corresponding native plugin (tokyonight, gruvbox) when available.

**Change theme at runtime:**

```sh
tinty cycle                          # cycle through preferred schemes
tinty apply base24-tokyo-night-dark  # or any scheme from `tinty list`
```

## Local AI Models

Run local AI model(s) with [Docker Model Runner](https://docs.docker.com/ai/model-runner/) and interact via [Open WebUI](https://github.com/open-webui/open-webui), [OpenCode](https://github.com/anomalyco/opencode), or `bin/x-ai`. Optional, independent of the main xndv build.

### Quick Start

```sh
# Edit MODELS_* vars in .env (see .env-example) to configure the model
make models-up
```

Access Open Webui at <http://localhost:12444>

Model downloads on first start. See `docker model list` and use `docker model` for management.

For more models, check out the published [Docker Hub AI models](https://hub.docker.com/u/ai) or [Hugging Face Transformers](https://huggingface.co/models?filter=transformers&sort=trending) (compatible with Docker Model Runner). Pull any model with `docker model pull` and set `MODELS_PRIMARY` to your chosen image.

### Configuration

| Variable            | Description                                |
| :------------------ | :----------------------------------------- |
| `MODELS_PRIMARY`    | Model (any `docker model pull` compatible) |
| `MODELS_WEBUI_PORT` | Open WebUI port                            |

### Management

```sh
make models-up      # Start docker containers (detached)
make models-down    # Stop
make models-logs    # Follow logs
make models-status  # Show containers

make models-thinking-enable   # turn on model reasoning (also: models-thinking-disable)
```

## LLM Gateway

Route LLM traffic through a local [LiteLLM](https://github.com/BerriAI/litellm) proxy for unified observability, cost tracking, and response caching across AI clients and model providers. This is an optional, independent component of the main environment.

### Quick Start

```sh
cp conf.local-example/xndv/litellm.yaml conf.local/xndv/
# Edit conf.local/xndv/litellm.yaml for your setup
make gateway-up          # on docker host
# set ENABLE_GATEWAY=1 in .env, then restart shell in container
```

Access LiteLLM UI at <http://localhost:4000>

By default, gateway services bind to `127.0.0.1` only, which works for `max`/`tty` modes but not `sys`/`min`. Override `GATEWAY_BIND_HOST` in `.env` if you intentionally want LAN or wider access.

### Configuration

| Variable                  | Description                                                       |
| :------------------------ | :---------------------------------------------------------------- |
| `ENABLE_GATEWAY`          | Set to `1` to activate gateway routing in the container           |
| `GATEWAY_BIND_HOST`       | Host interface for published gateway ports (default: `127.0.0.1`) |
| `GATEWAY_MASTER_KEY`      | LiteLLM master key (used as default client auth)                  |
| `GATEWAY_PROXY_PORT`      | LiteLLM proxy port (default: `4000`)                              |
| `GATEWAY_OAUTH_PORT`      | CLIProxyAPI OAuth port (default: `8317`)                          |
| `GATEWAY_API_KEY_*`       | Provider API keys passed to LiteLLM                               |
| `GATEWAY_CLIENT_BASE_URL` | Override gateway URL (default: `http://${XNDV_HOSTNAME}:PORT`)    |
| `GATEWAY_CLIENT_API_KEY`  | Override client auth key (default: `GATEWAY_MASTER_KEY`)          |

`XNDV_HOSTNAME` is injected by the launcher at runtime so containers can reach host-exposed services across modes. It defaults to `localhost` in host-networked modes and `host.docker.internal` in isolated modes such as `sys` and `min`.

Set `GATEWAY_BIND_HOST=0.0.0.0` to listen on all interfaces, or set it to a specific LAN IP to expose the gateway only on that trusted network interface.

### OAuth Providers

Route login-based providers through the gateway via [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI):

```sh
cp conf.local-example/xndv/cliproxyapi.yaml conf.local/xndv/
make gateway-up
make gateway-login                         # see list of supported providers
make gateway-login PROVIDER=someprovider   # one-time per account: follow the URL to authorize
```

Supports any provider available in CLIProxyAPI. Run once per account. Re-run if a token is revoked or to add accounts for load balancing.

After logging in, uncomment the corresponding entries in `conf.local/xndv/litellm.yaml` and restart the gateway. Each model can have multiple deployments across providers and accounts — the gateway tries them in priority order, falling back to the next if one is rate-limited or down.

### Management

```sh
make gateway-up      # Start gateway (detached)
make gateway-down    # Stop
make gateway-logs    # Follow logs
make gateway-status  # Show containers
make gateway-login PROVIDER=<provider>  # OAuth login
make gateway-quota                      # Check quota for connected OAuth providers
```
