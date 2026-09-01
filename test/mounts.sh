#!/usr/bin/env bash
#
# Verify mounts.conf resolution: a missing host source is made by the launcher,
# as the invoking user, before any `--volume` argument reaches the container
# runtime — which would otherwise make it as root. Runs entirely on throwaway
# paths under a temporary HOME; no container is started.
# Usage: ./test/mounts.sh

launcher=$(readlink -f "$(dirname "$0")")/../bin.host/xndv

tmp=$(mktemp -d)
trap 'chmod -R u+rwX "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT

export HOME="$tmp/home"
export XNDV_ROOT="$tmp/root"
export XDG_CONFIG_HOME="$HOME/.config"
# `dst/` stands in for the container-home tree the destinations land in; without
# it every entry would only report a missing destination parent.
mkdir -p "$HOME/dst" "$XNDV_ROOT/conf.local/xndv"

# Fixtures: one source already present (must survive untouched), one missing
# (must be created), two carrying option suffixes, one that cannot be created.
mkdir -p "$HOME/existing"
echo "sentinel" >"$HOME/existing/keep"
chmod 700 "$HOME/existing"
mkdir -p "$HOME/locked"
chmod 500 "$HOME/locked"

cat >"$XNDV_ROOT/conf.local/xndv/mounts.conf" <<'EOF'
+t:~/existing:~/dst/existing
+t:~/missing:~/dst/missing
+t:~/readonly:~/dst/readonly:ro
+t:~/shared:~/dst/shared:rshared
+t:~/locked/nope:~/dst/nope
EOF

before=$(stat -c '%u:%g:%a:%i' "$HOME/existing")

# shellcheck disable=SC1090 # resolved at run time, from this script's location
source "$launcher"
set +eu # the launcher's own `set -euo pipefail` follows it into this shell

# MOUNT_SELECTED is associative, so its subscript is a literal string: a bare
# `[i]` would key the array on "i" rather than on the index i holds.
# shellcheck disable=SC2034,SC2004 # read by mount_volume_args; subscript is a string
for i in "${MOUNT_CONF[@]}"; do MOUNT_SELECTED[$i]=1; done
args=()
mount_volume_args args
printf '%s\n' "${args[@]}"
echo ""

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

has_arg() {
  local needle="$1" a
  for a in "${args[@]}"; do [[ "$a" == "$needle" ]] && echo yes && return; done
  echo no
}

echo "=== missing source is created, owned by the invoking user ==="
check "missing source exists" "yes" "$([[ -d "$HOME/missing" ]] && echo yes || echo no)"
check "owned by invoking user" "$(id -u):$(id -g)" \
  "$(stat -c '%u:%g' "$HOME/missing" 2>/dev/null)"
check "missing source is mounted" "yes" \
  "$(has_arg "$HOME/missing:/home/xndv/dst/missing")"

echo ""
echo "=== existing source is left exactly as it was ==="
check "ownership, mode and inode unchanged" "$before" "$(stat -c '%u:%g:%a:%i' "$HOME/existing")"
check "contents intact" "sentinel" "$(cat "$HOME/existing/keep" 2>/dev/null)"

echo ""
echo "=== option suffixes reach the runtime unchanged ==="
check "ro passed through" "yes" "$(has_arg "$HOME/readonly:/home/xndv/dst/readonly:ro")"
check "rshared passed through" "yes" "$(has_arg "$HOME/shared:/home/xndv/dst/shared:rshared")"

echo ""
echo "=== an uncreatable source is dropped, not handed to the runtime ==="
check "not mounted" "no" "$(has_arg "$HOME/locked/nope:/home/xndv/dst/nope")"
check "the other four entries still resolved" "4" "$((${#args[@]} / 2))"

# The assertions above stop at the argument list; this one hands that list to
# the runtime that actually consumes it. Skipped rather than failed where the
# image is absent, so the test still runs on a host without one.
echo ""
echo "=== the runtime accepts the arguments and adds no root-owned path ==="
image="${XNDV_TEST_IMAGE:-alpine}"
if docker image inspect "$image" >/dev/null 2>&1; then
  # Propagation options are a property of the host mount the fixture sits on,
  # not of this code: `rshared` is refused outright under a private /tmp, so the
  # runtime leg carries every other mount and leaves that one to the argument
  # assertion above.
  runtime_args=()
  for ((n = 0; n < ${#args[@]}; n += 2)); do
    [[ "${args[$((n + 1))]}" == *:rshared ]] && continue
    runtime_args+=("${args[$n]}" "${args[$((n + 1))]}")
  done

  # As the host user, the way the launcher runs the container (`--user=RETAIN`).
  docker run --rm --user "$(id -u):$(id -g)" "${runtime_args[@]}" "$image" \
    sh -c 'touch /home/xndv/dst/missing/w && ! touch /home/xndv/dst/readonly/w' \
    >/dev/null 2>&1
  check "created mount writable, ro mount read-only" "0" "$?"
  check "no root-owned path under the temporary home" "" \
    "$(find "$HOME" ! -user "$(id -un)" -printf '%p ' 2>/dev/null)"
else
  echo "skip runtime leg — no local image \"$image\" (set XNDV_TEST_IMAGE)"
fi

echo ""
echo "$pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
