#!/usr/bin/env bash
#
# Verify mounts.conf resolution. Two rules meet here: a missing host *source* is
# made by the launcher as the invoking user, and a missing host *destination* is
# never made at all — it is the operator's mount point, and an unprepared one
# abandons the whole launch rather than letting the container runtime create it
# as root. Runs on throwaway paths under a temporary HOME; no xndv container is
# started and nothing is bound.
# Usage: ./test/mounts.sh

launcher=$(readlink -f "$(dirname "$0")")/../bin.host/xndv

tmp=$(mktemp -d)
trap 'chmod -R u+rwX "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT

export HOME="$tmp/home"
export XNDV_ROOT="$tmp/root"
export XDG_CONFIG_HOME="$HOME/.config"
conf="$XNDV_ROOT/conf.local/xndv"
mkdir -p "$HOME" "$conf"

# `dst/` stands in for the container-home tree the destinations land in. Every
# explicit mount point under it is made here, by this script, because that is
# exactly what the launcher refuses to do.
mkdir -p "$HOME/dst/existing" "$HOME/dst/missing" "$HOME/dst/readonly" "$HOME/dst/shared"
mkdir -p "$HOME/existing" "$HOME/locked"
echo "sentinel" >"$HOME/existing/keep"
echo "sentinel" >"$HOME/dst/existing/keep"
chmod 700 "$HOME/existing" "$HOME/dst/existing"
chmod 500 "$HOME/locked"
echo "not a directory" >"$HOME/dst/file"

# Every entry here has a destination that exists, so the whole set resolves.
cat >"$conf/ok.conf" <<'EOF'
+t:~/existing:~/dst/existing
+t:~/missing:~/dst/missing
+t:~/readonly:~/dst/readonly:ro
+t:~/shared:~/dst/shared:rshared
+t:~/default
+t:~/outside:/opt/outside
+t:~/locked/nope:~/dst/missing
EOF

# One unprepared mount point is enough to refuse the launch.
cat >"$conf/absent-dest.conf" <<'EOF'
+t:~/existing:~/dst/existing
+t:~/orphan:~/dst/deep/orphan
EOF

# A leaf whose parent is right there is the case a creating implementation would
# happily make: nothing about it looks like a typo.
cat >"$conf/leaf-dest.conf" <<'EOF'
+t:~/existing:~/dst/leaf
EOF

# A destination that exists but is not a directory is refused the same way.
cat >"$conf/file-dest.conf" <<'EOF'
+t:~/existing:~/dst/file
EOF

src_before=$(stat -c '%u:%g:%a:%i' "$HOME/existing")
dst_before=$(stat -c '%u:%g:%a:%i' "$HOME/dst/existing")
file_before=$(stat -c '%u:%g:%a:%i' "$HOME/dst/file")

# shellcheck disable=SC1090 # resolved at run time, from this script's location
source "$launcher"
set +eu # the launcher's own `set -euo pipefail` follows it into this shell

# The built-in MOUNTS, before any mounts.conf entry is appended to them.
builtin_mounts=("${MOUNTS[@]}")

# Resolve one mounts.conf from scratch, with every entry it defines selected.
# ARGS holds the resulting arguments and STATUS the resolution's verdict.
load_case() {
  local file="$1" i
  MOUNTS=("${builtin_mounts[@]}")
  MOUNT_CONF=()
  # shellcheck disable=SC2034 # both are read by the launcher, not by this script
  MOUNT_DEFAULT=()
  MOUNT_SELECTED=()
  load_mounts_conf "$file"
  # MOUNT_SELECTED is associative, so its subscript is a literal string: a bare
  # `[i]` would key the array on "i" rather than on the index i holds.
  # shellcheck disable=SC2034,SC2004 # read by mount_volume_args; subscript is a string
  for i in "${MOUNT_CONF[@]}"; do MOUNT_SELECTED[$i]=1; done
  ARGS=()
  mount_volume_args ARGS
  STATUS=$?
}

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
  for a in "${ARGS[@]}"; do [[ "$a" == "$needle" ]] && echo yes && return; done
  echo no
}

exists() { [[ -e "$1" ]] && echo yes || echo no; }

echo "=== every destination prepared: the set resolves ==="
load_case "$conf/ok.conf"
printf '  %s\n' "${ARGS[@]}"
check "resolution succeeds" "0" "$STATUS"
check "six of seven entries resolved" "6" "$((${#ARGS[@]} / 2))"
check "existing source mounted" "yes" "$(has_arg "$HOME/existing:/home/xndv/dst/existing")"
check "ro passed through" "yes" "$(has_arg "$HOME/readonly:/home/xndv/dst/readonly:ro")"
check "rshared passed through" "yes" "$(has_arg "$HOME/shared:/home/xndv/dst/shared:rshared")"
check "default destination resolves to the projected source" "yes" \
  "$(has_arg "$HOME/default:/home/xndv/default")"
check "destination outside the host home is left to the container" "yes" \
  "$(has_arg "$HOME/outside:/opt/outside")"

echo ""
echo "=== source policy still stands ==="
check "missing source created" "yes" "$(exists "$HOME/missing")"
check "created source owned by the invoking user" "$(id -u):$(id -g)" \
  "$(stat -c '%u:%g' "$HOME/missing" 2>/dev/null)"
check "uncreatable source dropped, rest kept" "no" \
  "$(has_arg "$HOME/locked/nope:/home/xndv/dst/missing")"

echo ""
echo "=== an existing destination is not touched ==="
check "destination ownership, mode and inode unchanged" "$dst_before" \
  "$(stat -c '%u:%g:%a:%i' "$HOME/dst/existing")"
check "destination contents intact" "sentinel" "$(cat "$HOME/dst/existing/keep" 2>/dev/null)"
check "source ownership, mode and inode unchanged" "$src_before" \
  "$(stat -c '%u:%g:%a:%i' "$HOME/existing")"

echo ""
echo "=== an absent destination refuses the whole launch ==="
load_case "$conf/absent-dest.conf"
check "resolution fails" "1" "$STATUS"
check "destination still absent" "no" "$(exists "$HOME/dst/deep/orphan")"
check "no topology created for it" "no" "$(exists "$HOME/dst/deep")"

echo ""
echo "=== a mount point whose parent exists is still not provisioned ==="
load_case "$conf/leaf-dest.conf"
check "resolution fails" "1" "$STATUS"
check "the mount point was not made" "no" "$(exists "$HOME/dst/leaf")"

echo ""
echo "=== a destination that is not a directory refuses it too ==="
load_case "$conf/file-dest.conf"
check "resolution fails" "1" "$STATUS"
check "the file is left as it was" "$file_before" "$(stat -c '%u:%g:%a:%i' "$HOME/dst/file")"
check "contents intact" "not a directory" "$(cat "$HOME/dst/file")"

echo ""
echo "=== live mount refuses an absent destination without making one ==="
mount_bind "$HOME/existing" "$HOME/dst/live" "" >/dev/null 2>&1
check "mount_bind fails" "1" "$?"
check "destination still absent" "no" "$(exists "$HOME/dst/live")"

# The runtime leg is deliberately thin. `bin.sys/docker` strips `--user` and
# then chowns root-owned files created during the run — under a HOME pointed at
# this fixture, that cleanup lands squarely on it — so nothing here may assert
# ownership through a `docker run`. Ownership is settled above, before any
# runtime is involved, which is where this fix does its work anyway. What is
# left is read-only enforcement, which the kernel applies regardless of uid.
echo ""
echo "=== the runtime accepts the arguments and honors :ro ==="
image="${XNDV_TEST_IMAGE:-alpine}"
if docker image inspect "$image" >/dev/null 2>&1; then
  load_case "$conf/ok.conf"
  # Propagation options are a property of the host mount the fixture sits on,
  # not of this code: `rshared` is refused outright under a private /tmp, and a
  # destination outside the host home has no fixture behind it.
  runtime_args=()
  for ((n = 0; n < ${#ARGS[@]}; n += 2)); do
    [[ "${ARGS[$((n + 1))]}" == *:rshared || "${ARGS[$((n + 1))]}" == *:/opt/* ]] && continue
    runtime_args+=("${ARGS[$n]}" "${ARGS[$((n + 1))]}")
  done
  docker run --rm "${runtime_args[@]}" "$image" \
    sh -c 'touch /home/xndv/dst/missing/w && ! touch /home/xndv/dst/readonly/w' \
    >/dev/null 2>&1
  check "writable mount writable, ro mount read-only" "0" "$?"
else
  echo "skip runtime leg — no local image \"$image\" (set XNDV_TEST_IMAGE)"
fi

echo ""
echo "$pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
