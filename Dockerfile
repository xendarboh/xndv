# syntax=docker/dockerfile:1

ARG IMAGE_BASE=
FROM ${IMAGE_BASE}

# configuration
ARG _LOCALE=en_US.UTF-8
ARG _USER=xndv
ARG _USER_GROUPS=audio,dialout,video
ARG _USER_ID=1000

# persist _USER for use in inheriting images
ENV XNDV_USER=${_USER}

# xndv source directory volume mount point when running container
# used for configuration files as symlinks
ENV XNDV_DIR=/home/${_USER}/src/xndv

# use the "noninteractive" debconf frontend
ENV DEBIAN_FRONTEND=noninteractive

# Cache downloaded .deb files to speed up repeated builds
RUN rm -f /etc/apt/apt.conf.d/docker-clean \
  && echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

# use bash for RUN commands
SHELL ["/bin/bash", "--login", "-e", "-o", "pipefail", "-c"]

# install things
RUN \
  --mount=type=cache,id=apt-archives,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,id=apt-lists,target=/var/lib/apt,sharing=locked \
  apt update \
  # install some apt related things first
  && apt install --no-install-recommends -y -q \
    apt-transport-https \
    ca-certificates \
    software-properties-common \
  && apt install --no-install-recommends -y -q \
    ack-grep \
    automake \
    bash-completion \
    btop \
    build-essential \
    curl \
    dos2unix \
    gpg-agent \
    htop \
    jq \
    less \
    libtool \
    locales \
    lsof \
    man-db \
    ncdu \
    netcat-openbsd \
    ninja-build \
    openssh-client \
    pinentry-curses \
    pkg-config \
    psmisc \
    python3-libtmux \
    python3-pygments \
    python3-venv \
    rake \
    ranger \
    rsync \
    silversearcher-ag \
    sqlite3 \
    sshfs \
    stow \
    sudo \
    tmux \
    tree \
    tzdata \
    units \
    unzip \
    wget \
    xsel \
    zip \
    # https://github.com/mapbox/node-sqlite3/issues/1443
    python-is-python3 \
    # for kpcli:
    libreadline-dev \
    xclip \
    zlib1g-dev \
  && true

# set locale
RUN locale-gen ${_LOCALE} \
  && update-locale LANG=${_LOCALE} LC_ALL=${_LOCALE}

# install latest fish
ARG VERSION_FISH
RUN \
  --mount=type=cache,id=apt-archives,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,id=apt-lists,target=/var/lib/apt,sharing=locked \
  apt-add-repository ppa:fish-shell/${VERSION_FISH} \
  && apt update \
  && apt install --no-install-recommends -y -q \
    fish

# install latest git
RUN \
  --mount=type=cache,id=apt-archives,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,id=apt-lists,target=/var/lib/apt,sharing=locked \
  apt-add-repository ppa:git-core/ppa \
  && apt update \
  && apt install --no-install-recommends -y -q \
    git \
    git-lfs

# create user, grant sudo access
# NOTE: _USER_GROUPS are voided by x11docker without --user=RETAIN option
RUN \
  # remove ubuntu (1000:1000) user/group if it exists to replace it
  (userdel -r ubuntu) || true && (groupdel ubuntu) || true \
  && groupadd -g ${_USER_ID} ${_USER} \
  && useradd -m \
    -s /bin/bash \
    -u ${_USER_ID} \
    -g ${_USER_ID} \
    -G ${_USER_GROUPS} \
    ${_USER} \
  && echo "${_USER}:${_USER}" | chpasswd \
  && echo "${_USER} ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/${_USER} \
  && chmod 0440 /etc/sudoers.d/${_USER}

# fix: "cannot find name for group ID 110"
RUN groupadd -g 110 render

# build helper: gh-latest <owner/repo> [prefix]
# Fetches the latest GitHub release version via web redirect (no REST API, not rate-limited).
# Default output: bare version "X.Y.Z". Pass a prefix (e.g. "v") to prepend it.
RUN <<'EOF'
cat > /usr/local/bin/gh-latest << 'SCRIPT'
#!/bin/bash
set -euo pipefail
v=$(curl -Ls -o /dev/null -w '%{url_effective}' "https://github.com/${1}/releases/latest" | sed 's|.*/tag/v\?||')
[ -n "$v" ] || { echo "gh-latest: failed to resolve ${1}" >&2; exit 1; }
echo "${2:-}${v}"
SCRIPT
chmod +x /usr/local/bin/gh-latest
EOF

# install git-crypt
RUN \
  --mount=type=cache,id=apt-archives,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,id=apt-lists,target=/var/lib/apt,sharing=locked \
  # install deps
  apt update \
  && apt install --no-install-recommends -y -q \
    libssl-dev \
  # clone our patched fork
  && git clone \
    --depth 1 \
    https://github.com/xendarboh/git-crypt.git \
    /tmp/git-crypt \
  && cd /tmp/git-crypt \
  # make, install, then cleanup
  && make  \
  && make \
    PREFIX=/usr/local \
    install \
  && rm -rf /tmp/git-crypt

# install latest git-filter-repo
# Note: 2023-06-12 make from git clone failed
RUN \
  --mount=type=cache,id=dl,target=/dl,sharing=locked \
  export V=$(gh-latest newren/git-filter-repo) \
  && export F="git-filter-repo-${V}" \
  && wget -qN -P /dl "https://github.com/newren/git-filter-repo/releases/download/v${V}/${F}.tar.xz" \
  && tar -xf /dl/${F}.tar.xz -C /tmp \
  && cd /tmp/${F} \
  && make \
    bindir=/usr/local/bin \
    prefix=/usr \
    pythondir=$(python -c "import site; print(site.getsitepackages()[-1])") \
    install \
  && gzip $(git --man-path)/man1/git-filter-repo.1 \
  # install contrib tools
  && cd contrib/filter-repo-demos \
  && for x in \
      bfg-ish \
      clean-ignore \
      insert-beginning \
      lint-history \
      signed-off-by \
    ; do \
      install -Dm0755 $x /usr/local/bin/gfr-$x; \
    done \
  && rm -rf /tmp/git-filter-repo-*

# install latest github cli
RUN \
  --mount=type=cache,id=apt-archives,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,id=apt-lists,target=/var/lib/apt,sharing=locked \
  --mount=type=cache,id=dl,target=/dl,sharing=locked \
  export V=$(gh-latest cli/cli) \
  && export F="gh_${V}_linux_amd64.deb" \
  && wget -qN -P /dl "https://github.com/cli/cli/releases/download/v${V}/${F}" \
  && apt update \
  && (dpkg -i /dl/${F} || true) \
  && apt install --no-install-recommends -y -q -f

# install latest shellcheck
RUN \
  --mount=type=cache,id=dl,target=/dl,sharing=locked \
  export V=$(gh-latest koalaman/shellcheck v) \
  && export F="shellcheck-${V}.linux.x86_64.tar.xz" \
  && wget -qN -P /dl "https://github.com/koalaman/shellcheck/releases/download/${V}/${F}" \
  && tar -xJf /dl/${F} -C /tmp \
  && install -m755 /tmp/shellcheck-${V}/shellcheck /usr/local/bin/shellcheck \
  && rm -rf /tmp/shellcheck-${V}

# install latest clang tools
# https://apt.llvm.org/
ARG INSTALL_LLVM=0
ARG VERSION_LLVM
RUN \
  --mount=type=cache,id=apt-archives,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,id=apt-lists,target=/var/lib/apt,sharing=locked \
  --mount=type=cache,id=dl,target=/dl,sharing=locked \
  if [ "${INSTALL_LLVM}" = "1" ]; then \
    wget -qN -P /dl/llvm https://apt.llvm.org/llvm.sh \
    && chmod +x /dl/llvm/llvm.sh \
    && /dl/llvm/llvm.sh ${VERSION_LLVM} all \
    && for x in $(ls /usr/bin/clang*${VERSION_LLVM}); do \
        ln -sv $x $(echo $x | sed "s/-${VERSION_LLVM}//"); \
      done \
  ; fi

# install latest cmake from Kitware APT repository
# https://apt.kitware.com/
RUN \
  --mount=type=cache,id=apt-archives,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,id=apt-lists,target=/var/lib/apt,sharing=locked \
  --mount=type=cache,id=dl,target=/dl,sharing=locked \
  wget -qN -P /dl/kitware https://apt.kitware.com/kitware-archive.sh \
  && bash /dl/kitware/kitware-archive.sh \
  && apt update \
  && apt install --no-install-recommends -y -q \
    cmake

# install solidity compiler
RUN \
  --mount=type=cache,id=apt-archives,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,id=apt-lists,target=/var/lib/apt,sharing=locked \
  apt-add-repository ppa:ethereum/ethereum \
  && apt update \
  && apt install --no-install-recommends -y -q \
    solc

# install cypress system deps
# https://docs.cypress.io/guides/getting-started/installing-cypress#UbuntuDebian
ARG INSTALL_CYPRESS_DEPS=0
RUN \
  --mount=type=cache,id=apt-archives,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,id=apt-lists,target=/var/lib/apt,sharing=locked \
  if [ "${INSTALL_CYPRESS_DEPS}" = "1" ]; then \
    apt update \
    && apt install --no-install-recommends -y -q \
      libasound2 \
      libgbm-dev \
      libgconf-2-4 \
      libgtk-3-0 \
      libgtk2.0-0 \
      libnotify-dev \
      libnss3 \
      libxss1 \
      libxtst6 \
      xauth \
      xvfb \
  ; fi

# install tomb
ARG INSTALL_TOMB=0
ARG VERSION_TOMB
RUN \
  --mount=type=cache,id=apt-archives,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,id=apt-lists,target=/var/lib/apt,sharing=locked \
  if [ "${INSTALL_TOMB}" = "1" ]; then \
    apt update \
      && apt install --no-install-recommends -y -q \
        cryptsetup \
        gettext \
        pinentry-curses \
        zsh \
    && git clone \
      --branch ${VERSION_TOMB} \
      --depth 1 \
      https://github.com/dyne/Tomb.git \
      /usr/local/src/tomb \
    && cd /usr/local/src/tomb \
    && make install \
    && rm -rf /usr/local/src/tomb \
  ; fi

# install node
ARG VERSION_NODE
RUN \
  --mount=type=cache,id=dl,target=/dl,sharing=locked \
  if [ "${VERSION_NODE}" = "LATEST" ]; then \
    export V=$(curl -Ls https://nodejs.org/dist/index.json \
      | grep '"lts":false' | head -n1 | cut -d',' -f1 | cut -d'"' -f4) \
  ; elif [ "${VERSION_NODE}" = "LTS" ]; then \
    export V=$(curl -Ls https://nodejs.org/dist/index.json \
      | grep -v '"lts":false' | grep lts | head -n1 | cut -d',' -f1 | cut -d'"' -f4) \
  ; else \
    export V=${VERSION_NODE} \
  ; fi \
  && export F="node-${V}-linux-x64.tar.xz" \
  && wget -qN -P /dl https://nodejs.org/dist/${V}/${F} \
  && tar -xf /dl/${F} \
    --directory /usr/local \
    --exclude='CHANGELOG.md' \
    --exclude='LICENSE' \
    --exclude='README.md' \
    --strip-components 1 \
  && chown -R 0:0 /usr/local

# install yarn and pnpm
RUN npm install --global corepack

# stop corepack from prompting
ENV COREPACK_ENABLE_DOWNLOAD_PROMPT=0

# install node things
RUN npm install --global \
    neovim \
    npm-check \
    npm-check-updates \
    opkg \
    prettier \
    prettier-plugin-solidity \
    typescript

# install latest deno
RUN \
  --mount=type=cache,id=dl,target=/dl,sharing=locked \
  wget -qN -P /dl/deno https://deno.land/install.sh \
  && DENO_INSTALL=/usr/local sh /dl/deno/install.sh

ARG INSTALL_NEOVIM_FROM_SRC=0
ARG INSTALL_NEOVIM_FROM_PPA_STABLE=0
ARG INSTALL_NEOVIM_FROM_PPA_UNSTABLE=0
ARG VERSION_NEOVIM_FROM_SRC=stable
RUN \
  --mount=type=cache,id=apt-archives,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,id=apt-lists,target=/var/lib/apt,sharing=locked \
  if [ "${INSTALL_NEOVIM_FROM_SRC}" = "1" ]; then \
    # install neovim tag'd release from source
    # reference: https://github.com/neovim/neovim/wiki/Building-Neovim
    apt update \
      && apt install --no-install-recommends -y -q \
        cmake \
        curl \
        g++ \
        gettext \
        libtool-bin \
        ninja-build \
        pkg-config \
        unzip \
      && git clone \
        --branch ${VERSION_NEOVIM_FROM_SRC} \
        --depth 1 \
        https://github.com/neovim/neovim.git \
        /usr/local/src/neovim \
      && cd /usr/local/src/neovim \
      && make \
        CMAKE_BUILD_TYPE=Release \
        CMAKE_INSTALL_PREFIX=/usr \
      && make install \
      && rm -rf /usr/local/src/neovim \
  ; elif [ "${INSTALL_NEOVIM_FROM_PPA_STABLE}" = "1" ]; then \
    # install neovim (stable) from ppa
    # reference: https://github.com/neovim/neovim/wiki/Installing-Neovim#ubuntu
    add-apt-repository ppa:neovim-ppa/stable \
      && apt update \
      && apt install --no-install-recommends -y -q \
        neovim \
  ; elif [ "${INSTALL_NEOVIM_FROM_PPA_UNSTABLE}" = "1" ]; then \
    # install neovim (unstable) from ppa
    add-apt-repository ppa:neovim-ppa/unstable \
      && apt update \
      && apt install --no-install-recommends -y -q \
        neovim \
  ; else \
    # install neovim from apt
    apt update \
      && apt install --no-install-recommends -y -q \
        neovim \
  ; fi

# use neovim for editor alternatives
# reference: https://github.com/neovim/neovim/wiki/Installing-Neovim#install-from-source
RUN update-alternatives --install /usr/bin/vi vi /usr/bin/nvim 60 \
  && update-alternatives --config vi \
  && update-alternatives --install /usr/bin/vim vim /usr/bin/nvim 60 \
  && update-alternatives --config vim \
  && update-alternatives --install /usr/bin/editor editor /usr/bin/nvim 60 \
  && update-alternatives --config editor

########################################################################
# switch to user
########################################################################
ENV HOME=/home/${_USER} USER=${_USER} LC_ALL=${_LOCALE} LANG=${_LOCALE}
ENV PATH=/home/${_USER}/bin:/home/${_USER}/.local/bin:/home/${_USER}/.go/bin:/home/${_USER}/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ENV SHELL=/bin/bash
ENV XDG_CONFIG_HOME=/home/${_USER}/.config
SHELL ["/bin/bash", "--login", "-c"]
USER ${_USER}
WORKDIR /home/${_USER}

# install uv (python package manager)
ENV UV_LINK_MODE=copy
ENV UV_TOOL_DIR=${HOME}/.uv/tools
RUN \
  --mount=type=cache,id=dlu,target=/dlu,sharing=locked,uid=${_USER_ID} \
  wget -qN -P /dlu/uv https://astral.sh/uv/install.sh \
  && sh /dlu/uv/install.sh

RUN \
  --mount=type=cache,id=uv-cache,target=${HOME}/.cache/uv,uid=${_USER_ID} \
  # install python support for neovim
  uv tool install --upgrade pynvim \
  # install grip (GitHub Markdown preview server)
  && uv tool install --upgrade "git+https://github.com/joeyespo/grip.git"

# install aider AI coding assistant
# https://aider.chat
ARG INSTALL_AIDER=0
RUN \
  --mount=type=cache,id=uv-cache,target=${HOME}/.cache/uv,uid=${_USER_ID} \
  if [ "${INSTALL_AIDER}" = "1" ]; then \
    uv tool install --upgrade aider-chat \
  ; fi

# install PlatformIO (stable version)
# http://docs.platformio.org/en/latest/installation.html#python-package-manager
ARG INSTALL_PLATFORMIO=0
RUN \
  --mount=type=cache,id=uv-cache,target=${HOME}/.cache/uv,uid=${_USER_ID} \
  if [ "${INSTALL_PLATFORMIO}" = "1" ]; then \
    uv tool install --upgrade platformio \
  ; fi

# install latest go
# Note: 2023-08: go_installer fails with:
#   Downloading Go from 400 Bad Request failed with HTTP status %!s(MISSING)
#   https://github.com/golang/tools/tree/master/cmd/getgo#usage
RUN \
  --mount=type=cache,id=dlu,target=/dlu,sharing=locked,uid=${_USER_ID} \
  export JSON=$(curl -Ls 'https://go.dev/dl/?mode=json' \
    | jq -r '.[0].files[] | select(.os == "linux" and .arch == "amd64")') \
  && export F=$(echo "$JSON" | jq -r '.filename') \
  && export C=$(echo "$JSON" | jq -r '.sha256') \
  && wget -qN -P /dlu "https://go.dev/dl/${F}" \
  && echo "${C}  /dlu/${F}" | sha256sum --check \
  && tar -xzf /dlu/${F} \
  && mv go ~/.go

# install go things
RUN echo \
  && go install github.com/alajmo/mani@latest \
  && go install github.com/jesseduffield/lazygit@latest \
  && go clean --cache

# install rust
RUN \
  --mount=type=cache,id=dlu,target=/dlu,sharing=locked,uid=${_USER_ID} \
  wget -qN -P /dlu/rustup https://sh.rustup.rs \
  && sh /dlu/rustup/index.html -y

# install rust things
ENV CARGO_HOME=/home/${_USER}/.cargo
ENV CARGO_TARGET_DIR=${CARGO_HOME}/target
RUN \
  --mount=type=cache,id=apt-archives,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,id=apt-lists,target=/var/lib/apt,sharing=locked \
  --mount=type=cache,id=cargo-registry,target=${CARGO_HOME}/registry,uid=${_USER_ID} \
  --mount=type=cache,id=cargo-target,target=$CARGO_TARGET_DIR,uid=${_USER_ID} \
  --mount=type=cache,id=dlu,target=/dlu,sharing=locked,uid=${_USER_ID} \
  # ensure clang is available (otherwise provided by INSTALL_LLVM)
  if ! command -v clang >/dev/null 2>&1; then \
    sudo apt install --no-install-recommends -y -q \
      clang \
      libclang-dev \
  ; fi \
  && wget -qN -P /dlu/cargo-binstall https://raw.githubusercontent.com/cargo-bins/cargo-binstall/main/install-from-binstall-release.sh \
  && bash /dlu/cargo-binstall/install-from-binstall-release.sh \
  && cargo binstall \
    --continue-on-failure \
    --disable-telemetry \
    --locked \
    bat \
    cargo-edit \
    dprint \
    exa \
    fastmod \
    fd-find \
    fnm \
    git-absorb \
    git-delta \
    llmfit \
    ripgrep \
    spacer \
    starship \
    tree-sitter-cli \
    tuicr \
    watchexec-cli \
    websocat \
    zoxide \
  && cargo install --git https://github.com/rtk-ai/rtk \
  && rustup component add \
    rust-analyzer

# install latest bun and make it available in PATH
RUN \
  --mount=type=cache,id=dlu,target=/dlu,sharing=locked,uid=${_USER_ID} \
  wget -qN -P /dlu/bun https://bun.sh/install \
  && bash /dlu/bun/install
ENV PATH="/home/${_USER}/.bun/bin:${PATH}"

# install bun things
RUN bun add -g \
    repomix

# install latest circom release
# https://docs.circom.io/getting-started/installation/#installing-dependencies
ARG INSTALL_CIRCOM=0
RUN \
  if [ "${INSTALL_CIRCOM}" = "1" ]; then \
    git clone \
      --branch $(gh-latest iden3/circom v) \
      --depth 1 \
      https://github.com/iden3/circom.git \
      /tmp/circom \
    && cd /tmp/circom \
    && cargo build --release \
    && cargo install --path circom \
    && rm -rf /tmp/circom \
  ; fi

# install noir
# https://noir-lang.org/docs/getting_started_manually
# NOTE: 2026-07: noirup without -v fails with gzip/tar error, remove explicit version once upstream issue ressolved
ARG INSTALL_NOIR=0
ARG VERSION_NOIR=1.0.0-beta.22
ENV NARGO_HOME=/home/${_USER}/.nargo
RUN \
  --mount=type=cache,id=dlu,target=/dlu,sharing=locked,uid=${_USER_ID} \
  if [ "${INSTALL_NOIR}" = "1" ]; then \
    wget -qN -P /dlu/noirup https://raw.githubusercontent.com/noir-lang/noirup/refs/heads/main/install \
    && bash /dlu/noirup/install \
    && ${NARGO_HOME}/bin/noirup -v ${VERSION_NOIR} \
    # NOTE: bb installed this way works on ubuntu 24, but not 22 (cuz glibc)
    && wget -qN -P /dlu/bbup https://raw.githubusercontent.com/AztecProtocol/aztec-packages/refs/heads/next/barretenberg/bbup/install \
    && bash /dlu/bbup/install \
    && PATH="${NARGO_HOME}/bin:$PATH" SHELL=/bin/bash ~/.bb/bbup \
  ; fi

# install Protocol Buffers
ARG INSTALL_PB=0
RUN \
  --mount=type=cache,id=dlu,target=/dlu,sharing=locked,uid=${_USER_ID} \
  if [ "${INSTALL_PB}" = "1" ]; then \
    export V=$(gh-latest protocolbuffers/protobuf) \
    && export F="protoc-${V}-linux-x86_64.zip" \
    && wget -qN -P /dlu "https://github.com/protocolbuffers/protobuf/releases/download/v${V}/${F}" \
    && unzip /dlu/${F} \
      -x readme.txt \
      -d ~/.local \
    && go install github.com/bufbuild/buf/cmd/buf@latest \
    && go clean --cache \
  ; fi

# install cpanminus for installing perl modules
# running cpanm gives suggestion to install local::lib, so do that
RUN \
  --mount=type=cache,id=dlu,target=/dlu,sharing=locked,uid=${_USER_ID} \
  --mount=type=cache,id=cpanm-cache,target=${HOME}/.cpanm,uid=${_USER_ID} \
  mkdir bin \
  && wget -qN -P /dlu/cpanm https://cpanmin.us/ \
  && install -m755 /dlu/cpanm/index.html bin/cpanm \
  && bin/cpanm --quiet --local-lib=perl5 local::lib \
  && perl -I perl5/lib/perl5/ -Mlocal::lib >> .bashrc

# install neovim perl provider dependencies (according to :checkhealth)
RUN \
  --mount=type=cache,id=cpanm-cache,target=${HOME}/.cpanm,uid=${_USER_ID} \
  cpanm --quiet --notest \
    Neovim::Ext \
    App::cpanminus

# install latest kpcli and dependencies
ARG VERSION_KPCLI
RUN \
  --mount=type=cache,id=dlu,target=/dlu,sharing=locked,uid=${_USER_ID} \
  --mount=type=cache,id=cpanm-cache,target=${HOME}/.cpanm,uid=${_USER_ID} \
  wget -qN -P /dlu https://downloads.sourceforge.net/project/kpcli/kpcli-${VERSION_KPCLI}.pl \
  && install -m755 /dlu/kpcli-${VERSION_KPCLI}.pl bin/kpcli \
  && cpanm --quiet --notest \
    Authen::OATH \
    Capture::Tiny \
    Clipboard \
    Clone \
    Convert::Base32 \
    Crypt::Argon2 \
    Crypt::Rijndael \
    Data::Password \
    Data::Password::zxcvbn \
    File::KDBX \
    File::KeePass \
    Math::Random::ISAAC \
    Sort::Naturally \
    Sub::Install \
    Term::ReadKey \
    Term::ReadLine::Gnu \
    Term::ShellUI

# install latest fzf release
RUN git clone \
    --depth 1 \
    --branch $(gh-latest junegunn/fzf v) \
    https://github.com/junegunn/fzf.git \
    ~/.fzf \
  && ~/.fzf/install \
    --all \
    --no-zsh

# install claude code
ARG INSTALL_CLAUDECODE=0
ENV CLAUDE_CONFIG_DIR /home/${_USER}/.local/share/claude
RUN \
  --mount=type=cache,id=dlu,target=/dlu,sharing=locked,uid=${_USER_ID} \
  if [ "${INSTALL_CLAUDECODE}" = "1" ]; then \
    wget -qN -P /dlu/claude-code https://claude.ai/install.sh \
    && bash /dlu/claude-code/install.sh \
    # 2026-03: claude is dir-dumb, hack it into shape
    && mv ${CLAUDE_CONFIG_DIR}/versions/* ~/.local/bin/claude \
    # install extras
    && npx get-shit-done-cc --claude --global \
  ; fi

# install opencode
ARG INSTALL_OPENCODE=0
RUN \
  if [ "${INSTALL_OPENCODE}" = "1" ]; then \
    curl -fsSL https://opencode.ai/install | bash \
    && export PATH=/home/${_USER}/.opencode/bin:${PATH} \
    && sudo npm i -g opencode-wakatime && opencode-wakatime --install \
    && sudo npm i -g opentmux \
    && npx get-shit-done-cc --opencode --global \
    && rtk init -g --opencode \
  ; fi

# install codex
ARG INSTALL_CODEX=0
ENV CODEX_HOME=/home/${_USER}/.local/share/codex
RUN \
  --mount=type=cache,id=apt-archives,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,id=apt-lists,target=/var/lib/apt,sharing=locked \
  if [ "${INSTALL_CODEX}" = "1" ]; then \
    sudo npm install -g @openai/codex \
  ; fi

# install oh-my-pi
ARG INSTALL_OMP=0
RUN \
  if [ "${INSTALL_OMP}" = "1" ]; then \
    bun install -g @oh-my-pi/pi-coding-agent \
  ; fi

# install herdr
RUN \
  --mount=type=cache,id=dlu,target=/dlu,sharing=locked,uid=${_USER_ID} \
  curl -fsSL https://herdr.dev/install.sh -o /dlu/herdr-install.sh \
  && sh /dlu/herdr-install.sh

# install extra bash things
RUN mkdir ~/.bash

# install extra fish things
SHELL ["/bin/fish", "--login", "-c"]
RUN \
  --mount=type=cache,id=dlu,target=/dlu,sharing=locked,uid=${_USER_ID} \
  wget -qN -P /dlu/fisher https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish \
  && source /dlu/fisher/fisher.fish \
  && fisher install \
    gazorby/fish-exa \
    jukben/fish-nx \
    jorgebucaran/fisher
SHELL ["/bin/bash", "--login", "-c"]

# install nix; single-user mode
# https://nixos.wiki/wiki/Nix_Installation_Guide
ARG INSTALL_NIX=0
RUN \
  --mount=type=cache,id=dlu,target=/dlu,sharing=locked,uid=${_USER_ID} \
  if [ "${INSTALL_NIX}" = "1" ]; then \
    sudo install -d -m755 -o $(id -u) -g $(id -g) /nix \
    && wget -qN -P /dlu/nix https://nixos.org/nix/install \
    && sh /dlu/nix/install \
    && /bin/fish --login -c 'fisher install lilyball/nix-env.fish' \
  ; fi

ARG INSTALL_DEVOPS=0
RUN \
  --mount=type=cache,id=apt-archives,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,id=apt-lists,target=/var/lib/apt,sharing=locked \
  --mount=type=cache,id=dlu,target=/dlu,sharing=locked,uid=${_USER_ID} \
  --mount=type=cache,id=uv-cache,target=${HOME}/.cache/uv,uid=${_USER_ID} \
  if [ "${INSTALL_DEVOPS}" = "1" ]; then \
    uv tool install --upgrade ansible-core \
    && wget -qN -P /dlu https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip \
    && unzip -q /dlu/awscli-exe-linux-x86_64.zip -d /tmp \
    && sudo /tmp/aws/install \
    && rm -rf /tmp/aws \
    # https://opentofu.org/docs/intro/install/deb/#installing-using-the-installer
    && wget -qN -P /dlu/opentofu https://get.opentofu.org/install-opentofu.sh \
    && chmod +x /dlu/opentofu/install-opentofu.sh && /dlu/opentofu/install-opentofu.sh --install-method deb \
    && wget -qN -P /dlu/hashicorp https://apt.releases.hashicorp.com/gpg \
    && sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg < /dlu/hashicorp/gpg \
    && echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
      | sudo tee /etc/apt/sources.list.d/hashicorp.list \
    && sudo apt update \
    && sudo apt install --no-install-recommends -y -q \
      packer \
      terraform \
    && uv tool install --upgrade terraform-local \
  ; fi

# https://v2.tauri.app/start/prerequisites/#linux
ARG INSTALL_TAURI=0
RUN \
  --mount=type=cache,id=apt-archives,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,id=apt-lists,target=/var/lib/apt,sharing=locked \
  if [ "${INSTALL_TAURI}" = "1" ]; then \
    sudo apt update \
    && sudo apt install --no-install-recommends -y -q \
      build-essential \
      curl \
      file \
      libayatana-appindicator3-dev \
      librsvg2-dev \
      libssl-dev \
      libwebkit2gtk-4.1-dev \
      libxdo-dev \
      wget \
    && cargo binstall \
      --continue-on-failure \
      --disable-telemetry \
      --locked \
      tauri-cli \
  ; fi

# copy configuration files so that links to them work during docker build
RUN mkdir -p ${XNDV_DIR}
COPY --chown=${_USER}:${_USER} . ${XNDV_DIR}

# link configuration files so that a mounted volume may override at container execution time
RUN \
  # stash original files before replacing with symlinks to our custom config files
  files_to_stash=( \
    /home/${_USER}/.config/opencode/opencode.json \
  ) \
  && for file in "${files_to_stash[@]}"; do \
    test -f "$file" || continue; \
    mkdir -p ~/.xndv/stash/$(dirname "$file") && mv "$file" ~/.xndv/stash/$(dirname "$file")/; \
  done \
  # create dirs so stow symlinks files and not dirs
  && mkdir -p \
    /home/${_USER}/.config/btop \
    /home/${_USER}/.config/herdr \
    /home/${_USER}/.config/kitty \
    /home/${_USER}/.config/lazygit \
    /home/${_USER}/.config/opencode \
    /home/${_USER}/.omp/agent \
  # stow the conf files!
  && stow \
    --dir=${XNDV_DIR} \
    --target=/home/${_USER}/ \
    --ignore=gitconfig \
    --verbose \
    conf

# source bash configuration
RUN /bin/echo -e "\ntest -f ~/.bash_xndv && . ~/.bash_xndv\n" >> .bashrc

# install tinty, sync schemes/templates, and apply a theme
# tinty expects a ~/.config/ file, so run this after stow
ARG OPTIONS_THEME
RUN \
  cargo binstall \
    --continue-on-failure \
    --disable-telemetry \
    --locked \
    tinty \
  && tinty sync \
  # symlink our custom schemes, as they only work in tinty data-dir
  && export D="tinted-theming/tinty/custom-schemes" && ln -sfn /home/${_USER}/.config/${D} ~/.local/share/${D} \
  # apply configured theme system wide
  && tinty apply ${OPTIONS_THEME} \
  # relocate tinty data-dir as ~/.local/share/ is commonly volume-mapped for persistence
  && mv ~/.local/share/tinted-theming/tinty ~/.tinty

# set nvim distribution
ARG OPTIONS_NVIM_APPNAME
ENV NVIM_APPNAME=${OPTIONS_NVIM_APPNAME}

########################################################################
# temporarily switch back to root user
########################################################################
USER root

# stow system configuration into the root filesystem
RUN stow \
  --dir=${XNDV_DIR} \
  --target=/ \
  --verbose \
  conf.system

# /home/${_USER} --> /etc/skel
# symlink xndv user's home to /etc/skel to support x11docker user home
RUN mv /etc/skel /etc/skel.bak \
  && mkdir /etc/skel \
  && (ln -sv /home/${_USER}/{.,}* /etc/skel/ || true)

# record xndv release
RUN echo \
    "VERSION=$(date +'%Y%m%d%H%M%S')" \
    > /etc/xndv-release

# record cache state
RUN \
  --mount=type=cache,id=apt-archives,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,id=apt-lists,target=/var/lib/apt,sharing=locked \
  --mount=type=cache,id=dl,target=/dl,sharing=locked \
  --mount=type=cache,id=dlu,target=/dlu,sharing=locked,uid=${_USER_ID} \
  du -hs /dl /dlu /var/cache/apt/archives /var/lib/apt/lists | sort -h > /etc/xndv-cache-stats

# unminimize to install docs
ARG INSTALL_DOCS=0
RUN \
  --mount=type=cache,id=apt-archives,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,id=apt-lists,target=/var/lib/apt,sharing=locked \
  if [ "${INSTALL_DOCS}" = "1" ]; then \
    yes | unminimize \
  ; fi

########################################################################
# switch to user
########################################################################
USER ${_USER}

CMD ["/bin/bash", "-c", "command -v start &>/dev/null && start || /bin/bash -l"]
