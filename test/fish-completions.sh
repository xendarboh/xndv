#!/bin/bash
#
# Verify the cached fish completions in config.fish. `_complete <cmd> <args>`
# writes a tool's generated completions to a cache dir on fish_complete_path,
# once per binary: it regenerates when the binary changes (ctime) or when a
# different binary answers to the name, and drops the file when the tool is gone.
# Runs the real function against a fake tool under a throwaway XDG_CACHE_HOME.
# Asserts and exits non-zero on failure. Starts no xndv container.
# Usage: ./test/fish-completions.sh

config=$(readlink -f "$(dirname "$0")")/../conf/.config/fish/config.fish

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Only the completion-cache block: from its dir setup to the end of _complete.
block="$tmp/block.fish"
awk '/^set -g _complete_dir/ { on = 1 } on { print } on && /^end$/ { exit }' "$config" >"$block"

export XDG_CACHE_HOME="$tmp/cache"
export COUNT="$tmp/count"
cache="$XDG_CACHE_HOME/xndv/fish-completions"
file="$cache/fake-tool.fish"

# A generator that records each run; MODE=fail or MODE=empty breaks it.
make_tool() {
  mkdir -p "$1"
  cat >"$1/$2" <<'EOF'
#!/bin/bash
echo run >>"$COUNT"
case "$MODE" in fail) exit 1 ;; empty) exit 0 ;; esac
echo "complete -c fake-tool -l foo"
EOF
  chmod +x "$1/$2"
}
make_tool "$tmp/bin1" fake-tool
make_tool "$tmp/bin2" fake-tool
make_tool "$tmp/bin1" fake-bad

pass=0
fail=0
check() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo "ok   $label"
    pass=$((pass + 1))
  else
    echo "FAIL $label"
    echo "       expected: $expected"
    echo "       actual:   $actual"
    fail=$((fail + 1))
  fi
}

# _complete <cmd> under the given PATH prefix; prints "<rc>|<output>"
run() {
  local path="$1" cmd="$2" out rc
  out=$(PATH="$path:$PATH" fish --no-config -c "source $block; _complete $cmd gen" 2>&1)
  rc=$?
  echo "$rc|$out"
}
runs() { [[ -f "$COUNT" ]] && wc -l <"$COUNT" || echo 0; }

echo "=== first run generates ==="
check "logged" "0|[xndv] generated fish completions: fake-tool" "$(run "$tmp/bin1" fake-tool)"
check "file written" "complete -c fake-tool -l foo" "$(tail -n1 "$file")"
check "header names the binary" "# xndv: $tmp/bin1/fake-tool" "$(head -n1 "$file")"
check "generator ran once" "1" "$(runs)"

echo "=== unchanged binary is served from cache ==="
check "silent" "0|" "$(run "$tmp/bin1" fake-tool)"
check "generator not rerun" "1" "$(runs)"

echo "=== changed binary regenerates ==="
sleep 1.1 # ctime and mtime compare in whole seconds
chmod u+x "$tmp/bin1/fake-tool"
check "logged" "0|[xndv] generated fish completions: fake-tool" "$(run "$tmp/bin1" fake-tool)"
check "generator rerun" "2" "$(runs)"

echo "=== different binary on PATH regenerates ==="
check "logged" "0|[xndv] generated fish completions: fake-tool" "$(run "$tmp/bin2:$tmp/bin1" fake-tool)"
check "header names the new binary" "# xndv: $tmp/bin2/fake-tool" "$(head -n1 "$file")"

echo "=== completions autoload from the cache dir ==="
check "complete -C finds --foo" "--foo" \
  "$(PATH="$tmp/bin2:$PATH" fish --no-config -c "source $block; complete -C 'fake-tool --'" | cut -f1)"

echo "=== failing generators cache nothing ==="
for mode in fail empty; do
  out=$(MODE=$mode run "$tmp/bin1" fake-bad)
  check "$mode: errors" "1|[xndv] ERROR: failed to generate fish completions: fake-bad" "$out"
  check "$mode: no file or temp left" "" "$(ls "$cache" | grep fake-bad)"
done

echo "=== removed tool drops its file ==="
check "silent" "0|" "$(run "$tmp/none" fake-tool)"
check "file deleted" "gone" "$([[ -e "$file" ]] && echo present || echo gone)"

echo
echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]

# vim: ft=sh
