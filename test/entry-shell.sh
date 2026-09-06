#!/usr/bin/env bash
#
# Verify the Bash-to-Fish transition at the PID-namespace boundary used by
# `xndv enter`. The production rc file is mounted into throwaway containers:
# command-running Bash must preserve its command status without probing PPID 0,
# fresh interactive Bash must enter Fish without that probe, and Bash launched
# by Fish must remain Bash. No xndv container is started.
# Usage: ./test/entry-shell.sh
#        XNDV_TEST_IMAGE=<bash-and-procps-image> ./test/entry-shell.sh

set -uo pipefail

root=$(readlink -f "$(dirname "$0")/..")
bashrc="$root/conf/.bash_xndv"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir -p \
  "$tmp/bin" \
  "$tmp/home/.config/git" \
  "$tmp/home/.local/share/tinted-theming/tinty" \
  "$tmp/home/.aztec" \
  "$tmp/home/.omp/agent/extensions" \
  "$tmp/home/.local/share/nvim/spell" \
  "$tmp/home/.local/share/omp/agent/extensions" \
  "$tmp/parent" \
  "$tmp/xndv/conf.local/.config/opencode"
touch \
  "$tmp/home/.config/git/config" \
  "$tmp/home/.omp/agent/config.yml" \
  "$tmp/home/.omp/agent/extensions/fixture.ts" \
  "$tmp/xndv/.env"

cat >"$tmp/bin/stub" <<'EOF'
#!/bin/sh
if [ "${0##*/}" = fish ]; then
  printf 'fish-stub\n'
fi
EOF
chmod +x "$tmp/bin/stub"
for command in fish fnm git stow tty zoxide; do
  ln -s stub "$tmp/bin/$command"
done
ln -s /bin/bash "$tmp/parent/fish"

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

check_contains() {
  local label="$1" needle="$2" output="$3"
  check "$label" yes "$([[ "$output" == *"$needle"* ]] && echo yes || echo no)"
}

check_absent() {
  local label="$1" needle="$2" output="$3"
  check "$label" yes "$([[ "$output" != *"$needle"* ]] && echo yes || echo no)"
}

container_args() {
  local -n out="$1"
  local mode="$2" image="$3" entrypoint="${4:-/bin/bash}"
  # shellcheck disable=SC2034 # nameref output is read by the caller
  out=(
    docker run --rm
    --user "$(id -u):$(id -g)"
    --env "HOME=/tmp/fixture/home"
    --env "PATH=/tmp/fixture/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    --env "XNDV_DIR=/tmp/fixture/xndv"
    --env "XNDV_MODE=$mode"
    --env PROMPT_COMMAND
    --volume "$tmp:/tmp/fixture"
    --volume "$bashrc:/opt/xndv/.bash_xndv:ro"
    --entrypoint "$entrypoint"
    "$image"
  )
}

dev_image="${XNDV_TEST_IMAGE:-xen/dev}"
sys_image="${XNDV_TEST_SYS_IMAGE:-${XNDV_TEST_IMAGE:-xen/sys}}"

echo "=== command-running entry Bash never inspects an invisible parent ==="
for mode_image in "max:$dev_image" "min:$dev_image" "sys:$sys_image" "tty:$dev_image"; do
  mode=${mode_image%%:*}
  image=${mode_image#*:}

  if ! docker image inspect "$image" >/dev/null 2>&1; then
    echo "FAIL $mode image is unavailable: $image"
    fail=$((fail + 1))
    continue
  fi

  args=()
  container_args args "$mode" "$image"
  output=$("${args[@]}" --rcfile /opt/xndv/.bash_xndv -ic \
    'printf "entry-command-ran\n"; exit 23' 2>&1)
  status=$?

  check "$mode preserves command status" 23 "$status"
  check_contains "$mode runs the command" entry-command-ran "$output"
  check_absent "$mode passes no invalid PID to ps" "process ID out of range" "$output"
  check_absent "$mode leaves Fish to the entry command" fish-stub "$output"
done

echo ""
echo "=== interactive entry with PPID 0 enters Fish without probing it ==="
args=()
container_args args max "$dev_image"
output=$("${args[@]}" --rcfile /opt/xndv/.bash_xndv -i 2>&1)
status=$?
check "interactive entry succeeds" 0 "$status"
check_contains "interactive entry reaches Fish" fish-stub "$output"
check_absent "interactive entry passes no invalid PID to ps" "process ID out of range" "$output"

echo ""
echo "=== interactive Bash launched by Fish remains Bash ==="
args=()
container_args args sys "$sys_image" "/tmp/fixture/parent/fish"
output=$(PROMPT_COMMAND='printf "fish-parent-kept-bash\n"; exit' \
  "${args[@]}" -c '/bin/bash --rcfile /opt/xndv/.bash_xndv -i; :' 2>&1)
status=$?
check "Fish child Bash succeeds" 0 "$status"
check_contains "Fish child remains Bash" fish-parent-kept-bash "$output"
check_absent "Fish child does not re-enter Fish" fish-stub "$output"
check_absent "Fish child uses a valid parent lookup" "process ID out of range" "$output"

echo ""
echo "$pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
