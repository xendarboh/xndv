#!/usr/bin/env bash
#
# Verify the HERDR_AGENT boundary for `xndv enter`. Herdr observes the host
# foreground wrapper, so command identity belongs in the host docker process
# environment—not in docker's container environment or the container-local path.
# Asserts and exits non-zero on failure. Starts no xndv container.
# Usage: ./test/enter-agent.sh

set -uo pipefail

root=$(readlink -f "$(dirname "$0")/..")
launcher="$root/bin.host/xndv"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

cat >"$tmp/bin/docker" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
ps)
  printf 'xndv-probe\n'
  ;;
inspect)
  exit 0
  ;;
exec)
  printf '%s\n' "${HERDR_AGENT-unset}" >"$XNDV_CAPTURE_DIR/host-agent"
  printf '%s\0' "$@" >"$XNDV_CAPTURE_DIR/docker-argv"
  printf 'docker stdout sentinel\n'
  printf 'docker stderr sentinel\n' >&2
  exit 37
  ;;
*)
  printf 'unexpected docker command: %s\n' "${1:-<none>}" >&2
  exit 99
  ;;
esac
EOF
chmod +x "$tmp/bin/docker"

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

array_repr() {
  (($#)) || return
  printf '<%q>' "$@"
}

read_docker_command() {
  local command_index=-1 i
  mapfile -d '' -t docker_args <"$tmp/docker-argv"
  for i in "${!docker_args[@]}"; do
    [[ "${docker_args[$i]}" == xndv ]] && command_index=$i
  done
  if ((command_index < 0)); then
    docker_command=()
    return 1
  fi
  docker_command=("${docker_args[@]:command_index + 1}")
}

run_host() {
  local initial_agent="$1"
  shift
  : >"$tmp/stdout"
  : >"$tmp/stderr"
  rm -f "$tmp/host-agent" "$tmp/docker-argv"

  if [[ "$initial_agent" == unset ]]; then
    # shellcheck disable=SC2016 # variables expand in the nested Bash
    env -u HERDR_AGENT \
      PATH="$tmp/bin:$PATH" \
      XNDV_CAPTURE_DIR="$tmp" \
      bash -c 'source "$1"; in_container() { return 1; }; shift; enter_existing "$@"' \
      xndv "$launcher" xndv-probe -C /work "$@" >"$tmp/stdout" 2>"$tmp/stderr"
  else
    # shellcheck disable=SC2016 # variables expand in the nested Bash
    env HERDR_AGENT="$initial_agent" \
      PATH="$tmp/bin:$PATH" \
      XNDV_CAPTURE_DIR="$tmp" \
      bash -c 'source "$1"; in_container() { return 1; }; shift; enter_existing "$@"' \
      xndv "$launcher" xndv-probe -C /work "$@" >"$tmp/stdout" 2>"$tmp/stderr"
  fi
  host_status=$?
  read_docker_command
}

echo "=== host command identity belongs to the observed docker process ==="
expected_command=(omp "arg with spaces" 'semi;colon' '')
run_host caller-supplied -- "${expected_command[@]}"
check "host docker process receives command identity" omp "$(cat "$tmp/host-agent")"
check "docker process status is preserved" 37 "$host_status"
check_contains "docker process stdout is preserved" "docker stdout sentinel" "$(cat "$tmp/stdout")"
check "docker process stderr is preserved" "docker stderr sentinel" "$(cat "$tmp/stderr")"
check "command argv is preserved" \
  "$(array_repr "${expected_command[@]}")" "$(array_repr "${docker_command[@]}")"
check_absent "identity is not passed into the container" \
  "HERDR_AGENT=omp" "$(array_repr "${docker_args[@]}")"
claude_command=(claude --model opus)
run_host unset -- "${claude_command[@]}"
check "second host command receives its own identity" claude "$(cat "$tmp/host-agent")"
check "second command argv is preserved" \
  "$(array_repr "${claude_command[@]}")" "$(array_repr "${docker_command[@]}")"
check_absent "second identity is not passed into the container" \
  "HERDR_AGENT=claude" "$(array_repr "${docker_args[@]}")"

echo ""
echo "=== host interactive entry preserves the caller environment ==="
run_host caller-supplied
check "existing caller identity is unchanged" caller-supplied "$(cat "$tmp/host-agent")"
check "interactive entry passes no command" "" "$(array_repr "${docker_command[@]}")"
run_host unset
check "interactive entry invents no identity" unset "$(cat "$tmp/host-agent")"

echo ""
echo "=== container-local entry does not claim the host-only hint ==="
: >"$tmp/stdout"
: >"$tmp/stderr"
# shellcheck disable=SC2016 # variables expand in the nested Bash
env HERDR_AGENT=caller-supplied XNDV_CAPTURE_DIR="$tmp" \
  bash -c '
    source "$1"
    in_container() { return 0; }
    INITIAL_SHELL='"'"'printf "%s\n" "${HERDR_AGENT-unset}" >"$XNDV_CAPTURE_DIR/inside-agent"; printf "%s\0" "$@" >"$XNDV_CAPTURE_DIR/inside-argv"; printf "inside stdout sentinel\n"; printf "inside stderr sentinel\n" >&2; exit 23'"'"'
    shift
    enter_existing "$@"
  ' xndv "$launcher" -- "${expected_command[@]}" >"$tmp/stdout" 2>"$tmp/stderr"
inside_status=$?
mapfile -d '' -t inside_command <"$tmp/inside-argv"
check "container-local entry preserves caller environment" caller-supplied "$(cat "$tmp/inside-agent")"
check "container-local command status is preserved" 23 "$inside_status"
check_contains "container-local stdout is preserved" "inside stdout sentinel" "$(cat "$tmp/stdout")"
check "container-local stderr is preserved" "inside stderr sentinel" "$(cat "$tmp/stderr")"
check "container-local command argv is preserved" \
  "$(array_repr "${expected_command[@]}")" "$(array_repr "${inside_command[@]}")"

echo ""
echo "$pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
