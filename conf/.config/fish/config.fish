if status is-interactive
    # Commands to run in interactive sessions can go here
end

# tool-generated completions: cached per binary, regenerated when it changes, autoloaded by fish on <Tab>
set -g _complete_dir (set -q XDG_CACHE_HOME; and echo $XDG_CACHE_HOME; or echo ~/.cache)/xndv/fish-completions
set -p fish_complete_path $_complete_dir

# usage: _complete <cmd> <args to make cmd print fish completions...>
function _complete
    set -l cmd $argv[1]
    set -l file $_complete_dir/$cmd.fish
    set -l bin (command -s $cmd); or begin
        rm -f $file # tool gone: drop its stale completions
        return 0
    end
    # fresh = same binary path (header line) and binary not changed since generation (ctime)
    if test -f $file; and read -l header <$file; and test "$header" = "# xndv: $bin"
        test (stat -L -c %Z $bin) -le (path mtime $file); and return 0
    end
    mkdir -p $_complete_dir
    set -l tmp (mktemp $file.XXXXXX)
    echo "# xndv: $bin" >$tmp
    if $bin $argv[2..] >>$tmp 2>/dev/null; and test (count <$tmp) -gt 1
        mv -f $tmp $file; and echo "[xndv] generated fish completions: $cmd" >&2
    else
        rm -f $tmp
        echo "[xndv] ERROR: failed to generate fish completions: $cmd" >&2
        return 1
    end
end

if status is-interactive
    _complete bat --completion fish
    _complete buf completion fish
    _complete fnm completions --shell fish
    _complete gh completion -s fish
    _complete git-absorb --gen-completions fish
    _complete herdr completion fish
    _complete mani completion fish
    _complete nargo generate-completion-script fish
    _complete omp completions fish
    _complete tinty generate-completion fish
    _complete uv generate-shell-completion fish
    _complete woodpecker-cli completion fish
    _complete wrangler complete fish
end

fnm env | source
starship init fish | source
zoxide init fish | source

# gpg needs this
export GPG_TTY=(tty)

# forgit requires SHELL=/bin/fish
set SHELL /bin/fish

# kitty manual shell integration
# https://sw.kovidgoyal.net/kitty/shell-integration/#manual-shell-integration
if set -q KITTY_INSTALLATION_DIR
    set --global KITTY_SHELL_INTEGRATION enabled
    source "$KITTY_INSTALLATION_DIR/shell-integration/fish/vendor_conf.d/kitty-shell-integration.fish"
    set --prepend fish_complete_path "$KITTY_INSTALLATION_DIR/shell-integration/fish/vendor_completions.d"
end

# add all emacs-mode bindings to vi-mode
# https://fishshell.com/docs/current/interactive.html#vi-mode-commands
function fish_user_key_bindings
    # Execute this once per mode that emacs bindings should be used in
    fish_default_key_bindings -M insert

    # Then execute the vi-bindings so they take precedence when there's a conflict.
    # Without --no-erase fish_vi_key_bindings will default to
    # resetting all bindings.
    # The argument specifies the initial mode (insert, "default" or visual).
    fish_vi_key_bindings --no-erase insert
end

set -g fish_key_bindings fish_vi_key_bindings

function fish_greeting
    # silence the greeting
end

# Default history to oldest-first; preserve native subcommands.
functions -c history __history_original
function history
    switch "$argv[1]"
        case delete clear clear-session merge save append
            __history_original $argv
        case '*'
            __history_original --reverse $argv
    end
end

function dirmap
    set F "$XNDV_DIR/conf.local/xndv/directory_map.txt"
    test -f "$F" || return
    for line in (cat "$F")
        set from (echo "$line" | cut -d':' -f1)
        set to (echo "$line" | cut -d':' -f2)

        set match (string match --regex ^$from $PWD)
        if test ! -z "$match"
            set XNDV_DIRMAP_MSG "[xndv] directory map: $from --> $to"
            set XNDV_DIRMAP_PWD (echo "$PWD" | sed -e "s|^$from|$to|")
            echo $XNDV_DIRMAP_MSG && cd $XNDV_DIRMAP_PWD
        end
    end
end
dirmap

# 20250724: fix pesky issue where all nx commands b0rk the terminal prompt
function nx
    command nx $argv
    commandline -f repaint
    commandline -f execute
end

# 20260313: fix tuicr broken clipboard copy
function tuicr
    command tuicr --no-update-check --stdout $argv | tee /dev/tty | xclip -selection clipboard
end

function on_variable_pwd --on-variable PWD
    # update tmux-window-name upon directory change (iff running tmux)
    test ! -z "$TMUX_PLUGIN_MANAGER_PATH" \
        && $TMUX_PLUGIN_MANAGER_PATH/tmux-window-name/scripts/rename_session_windows.py &>/dev/null
end

# https://github.com/gazorby/fish-exa#-configuration
set -Ux EXA_STANDARD_OPTIONS \
    --group \
    --group-directories-first \
    --header \
    --icons \
    --long \
    --time-style=long-iso
set -Ux EXA_LL_OPTIONS --sort changed
set -Ux EXA_LT_OPTIONS --ignore-glob '.git|node_modules' --tree --level

function ga
    set -l n (git rev-list --count @{upstream}..HEAD 2>/dev/null)
    test -z "$n" -o "$n" = 0 && echo "[xndv] ERROR: no commits ahead of upstream" >&2 && return 1
    git absorb --base HEAD~$n $argv
end

function gr
    set -l n $argv[1]
    set -l opts $argv[2..-1]
    if test -z "$n"
        set n (git rev-list --count @{upstream}..HEAD 2>/dev/null)
        test -z "$n" -o "$n" = 0 && echo "[xndv] ERROR: no commits ahead of upstream" >&2 && return 1
    end
    git rebase -i --autosquash HEAD~$n $opts
end

function gra
    gr "$argv[1]" --exec 'git commit --amend --reset-author --no-edit' $argv[2..-1]
end

function see
    set -l changed_within $argv[1]
    test -n "$changed_within"; or set changed_within 1m
    fd . --changed-within "$changed_within" --type f --hidden \
        | grep -v Brave \
        | grep -v chromium \
        | grep -v mesa \
        | sort
end

# edit files of specified git status, for example "vimgit M" to open all modified files
function vimgit
    set -l code $argv[1]
    test -z "$code" && echo "[xndv] usage: vimgit <status-code> [nvim-args...]" >&2 && return 1
    set -l files (git status --porcelain | grep "$code " | awk '{print $2}')
    test (count $files) -eq 0 && echo "[xndv] ERROR: no files with git status '$code'" >&2 && return 1
    nvim $argv[2..-1] $files
end

function mkcd
    mkdir -p "$argv[1]" && cd "$argv[1]"
end

abbr b 'git branch -av'
abbr d 'git diff'
abbr s 'git status'
abbr gb 'git branch'
abbr gg 'git grep'
abbr gl 'git log --show-signature'
abbr gln 'git log --oneline | nl'
abbr dc 'docker compose'
abbr grip 'grip --theme=dark'
abbr fm 'fastmod --hidden'
abbr hr 'herdr --remote-keybindings server --remote'
abbr hs x-herdr-spreader-apply
abbr lz lazygit
abbr oc opencode
abbr tc 'tinty cycle'
abbr v nvim
abbr vd 'nvim -d'
abbr vr 'nvim -R'
abbr xm 'xndv mount'
abbr x 'cd $XNDV_DIR; and nvim'

# INSTALL_BROWSER_BRAVE
command -v brave-browser >/dev/null && abbr brave-browser 'brave-browser --no-sandbox'

# INSTALL_BROWSER_CHROMIUM
command -v chromium >/dev/null && abbr chromium 'chromium --no-sandbox'

abbr kt-clip 'kitty +kitten clipboard'
abbr kt-diff 'kitty +kitten diff'
abbr kt-icat 'kitty +kitten icat'

# vim:sw=4:ts=4:et:
