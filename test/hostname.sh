#!/usr/bin/env bash
#
# Verify the container hostname contract. A xndv container used to report either
# the server's own name (host-networked modes) or Docker's ephemeral container id
# (isolated modes such as sys); neither is a stable name for one instance. The
# launcher now states "<server>-<instance>" instead, and this checks that it is
# composed, normalized and length-capped deterministically, that every mode's
# generated command carries it, and that the runtime accepts the result.
# Asserts and exits non-zero on failure. Starts no xndv container.
# Usage: ./test/hostname.sh

launcher=$(readlink -f "$(dirname "$0")")/../bin.host/xndv

# shellcheck disable=SC1090 # resolved at run time, from this script's location
source "$launcher"
set +eu # the launcher's own `set -euo pipefail` follows it into this shell

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

# The generated command for one mode × runner, with the mode evaluated first so
# that IMAGE and the argument arrays are the ones the launcher would use.
generate() {
  local mode="$1" runner="$2"
  # shellcheck disable=SC2034 # both are read by launch_command, by name
  local env_args=() vol_args=()
  "mode_$mode"
  env_args+=(--env "XNDV_MODE=${mode}")
  launch_command "$runner" "$mode" "${3:-xndv-$mode}" env_args vol_args
}

# The docker half of a generated command: for x11docker everything after the
# first `--`, which is where the launcher's own docker options are handed over.
docker_section() {
  local cmd="$1"
  [[ "$cmd" == x11docker* ]] && cmd="${cmd#*' -- '}"
  echo "$cmd"
}

echo "=== identity is composed from the server and the instance ==="
check "both halves present" "srv1-xndv-sys-1" "$(container_hostname srv1 xndv-sys-1)"
check "recreating the same instance recomposes the same name" \
  "$(container_hostname srv1 xndv-sys-1)" "$(container_hostname srv1 xndv-sys-1)"
check "two instances on one server differ" "differ" \
  "$([[ "$(container_hostname srv1 xndv-sys-1)" != "$(container_hostname srv1 xndv-sys-2)" ]] \
    && echo differ || echo same)"
check "one instance name on two servers differs" "differ" \
  "$([[ "$(container_hostname srv1 xndv-sys-1)" != "$(container_hostname srv2 xndv-sys-1)" ]] \
    && echo differ || echo same)"
check "an FQDN contributes its short name only" "srv1-xndv-max" \
  "$(container_hostname srv1.internal.example.com xndv-max)"

echo ""
echo "=== normalization: a container name is not hostname-safe as given ==="
check "underscore becomes a hyphen" "srv-1-xndv-sys-1" "$(container_hostname srv_1 xndv_sys_1)"
check "dots inside the instance name become hyphens" "srv1-xndv-sys-1-2" \
  "$(container_hostname srv1 xndv.sys.1.2)"
check "case is folded" "srv1-xndv-sys-1" "$(container_hostname SRV1 XNDV-Sys-1)"
check "hyphen runs collapse and the ends are trimmed" "srv1-xndv-sys" \
  "$(container_hostname -srv1-- "__xndv--sys__")"
# shellcheck disable=SC2016 # the literal characters are the point
check "shell metacharacters do not survive" "srv1-xndv-a-b" \
  "$(container_hostname 'srv1' 'xndv-$(a) b')"
check "an unusable pair is refused, not guessed" "1" \
  "$(container_hostname '___' '...' >/dev/null 2>&1; echo $?)"
check "an empty instance name leaves the server alone" "srv1" \
  "$(container_hostname srv1 '')"

echo ""
echo "=== length: the emitted value stays inside the runtime's limit ==="
long_parent=$(printf 's%.0s' $(seq 1 80))
long_name=$(printf 'n%.0s' $(seq 1 80))

capped=$(container_hostname "$long_parent" xndv-sys-1)
check "a long server segment is capped at the budget" "$HOSTNAME_MAX" "${#capped}"
check "the instance name survives a long server whole" "yes" \
  "$([[ "$capped" == *-xndv-sys-1 ]] && echo yes || echo no)"
check "two instances stay distinct under a truncated server" "differ" \
  "$([[ "$capped" != "$(container_hostname "$long_parent" xndv-sys-2)" ]] \
    && echo differ || echo same)"

cut_name=$(container_hostname srv1 "$long_name")
check "a name that fills the budget alone is itself cut" "$HOSTNAME_MAX" "${#cut_name}"
check "the server segment yields entirely to it" "yes" \
  "$([[ "$cut_name" != *srv1* ]] && echo yes || echo no)"

seam=$(container_hostname "${long_parent}" "-$long_name")
check "cutting at a seam leaves no stray hyphen" "yes" \
  "$([[ "$seam" != *--* && "$seam" != -* && "$seam" != *- ]] && echo yes || echo no)"

echo ""
echo "=== every mode's generated command states the hostname ==="
export HOSTNAME=srv1
for mode in max min sys tty; do
  # shellcheck disable=SC2153 # RUNNERS is the launcher's array, set by mode_*
  read -r runners < <("mode_$mode"; echo "${RUNNERS[*]}")
  for runner in $runners; do
    cmd=$(generate "$mode" "$runner" "xndv-$mode-1")
    check "$mode·$runner passes --hostname to docker" "yes" \
      "$(grep -qF -- "--hostname=srv1-xndv-$mode-1" <<<"$(docker_section "$cmd")" \
        && echo yes || echo no)"
  done
done

# The two halves of the old behaviour, named: `tty` is host-networked and used to
# inherit the server's name, `sys` is isolated and used to take a container id.
cmd=$(generate tty docker "xndv-tty-1")
check "host-networked tty no longer settles for the bare server name" "yes" \
  "$(grep -qF -- "--network=host" <<<"$cmd" \
    && grep -qF -- "--hostname=srv1-xndv-tty-1" <<<"$cmd" && echo yes || echo no)"
cmd=$(generate sys docker "xndv-sys-1")
check "isolated sys is named rather than left to a container id" "yes" \
  "$(grep -qF -- "--runtime=sysbox-runc" <<<"$cmd" \
    && grep -qF -- "--hostname=srv1-xndv-sys-1" <<<"$cmd" && echo yes || echo no)"

echo ""
echo "=== the runtime reports back what was composed ==="
image="${XNDV_TEST_IMAGE:-alpine}"
if docker image inspect "$image" >/dev/null 2>&1; then
  for pair in "srv1:xndv-sys-1" "srv_1.example.com:XNDV_sys.2" "$long_parent:xndv-max"; do
    composed=$(container_hostname "${pair%%:*}" "${pair#*:}")
    check "docker accepts and reports \"$composed\"" "$composed" \
      "$(docker run --rm --hostname="$composed" "$image" hostname 2>&1 | tail -1)"
  done
else
  echo "skip runtime leg — no local image \"$image\" (set XNDV_TEST_IMAGE)"
fi

echo ""
echo "$pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
