#!/bin/bash
#
# Verify bin/x-skill-usage. It prints a skill's `metadata.usage` literal block
# verbatim, found by name under the working directory or given by path, and
# refuses in one line when the skill is missing, ambiguous or has no usage.
# Runs against throwaway skills under a temporary directory.
# Asserts and exits non-zero on failure. Starts no xndv container.
# Usage: ./test/skill-usage.sh

script=$(readlink -f "$(dirname "$0")")/../bin/x-skill-usage

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

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

# run <dir> <args...> → "<exit>|<stdout+stderr>"
run() {
  local dir="$1" out rc
  shift
  out=$(cd "$dir" && "$script" "$@" 2>&1)
  rc=$?
  echo "$rc|$out"
}

# skill <dir> — write SKILL.md from stdin
skill() {
  mkdir -p "$1"
  cat >"$1/SKILL.md"
}

ws="$tmp/ws"

skill "$ws/.agents/skills/good" <<'EOF'
---
name: good
description: A skill with usage.
metadata:
  author: someone
  usage: |
    /good add <thing> [--flag]
      indented continuation

    /good rm <thing>


  other: value
---

# good
EOF

skill "$ws/.agents/skills/no-usage" <<'EOF'
---
name: no-usage
description: No usage here.
usage: |
  top-level usage is not metadata.usage
metadata:
  nested:
    usage: |
      too deep to count
---
EOF

skill "$ws/.agents/skills/folded" <<'EOF'
---
name: folded
metadata:
  usage: >
    /folded run
---
EOF

skill "$ws/.agents/skills/tabbed" <<EOF
---
name: tabbed
metadata:
  usage: |
	/tabbed run
---
EOF

skill "$ws/.agents/skills/bare" <<'EOF'
# no frontmatter at all
EOF

skill "$ws/.agents/skills/twice" <<'EOF'
---
metadata:
  usage: |
    /twice one
---
EOF
skill "$ws/.claude/skills/twice" <<'EOF'
---
metadata:
  usage: |
    /twice two
---
EOF

# A linked skills dir points at a skill already found: one match, not two.
mkdir -p "$ws/linked"
ln -s ../.agents/skills/good "$ws/linked/good"

good_usage='/good add <thing> [--flag]
  indented continuation

/good rm <thing>'

echo "=== found by name ==="
check "prints usage verbatim" "0|$good_usage" "$(run "$ws" good)"
check "from a subdirectory, searches below it only" \
  "1|[xndv] ERROR: skill not found: good" "$(run "$ws/.claude" good)"

echo "=== given by path ==="
check "skill directory" "0|$good_usage" "$(run "$tmp" ws/.agents/skills/good)"
check "SKILL.md itself" "0|$good_usage" "$(run "$tmp" ws/.agents/skills/good/SKILL.md)"
check "missing path" "1|[xndv] ERROR: skill not found: ws/nope" "$(run "$tmp" ws/nope)"

echo "=== refusals ==="
check "unknown name" "1|[xndv] ERROR: skill not found: nope" "$(run "$ws" nope)"
check "ambiguous name" \
  "1|[xndv] ERROR: more than one skill matches 'twice': $ws/.agents/skills/twice/SKILL.md $ws/.claude/skills/twice/SKILL.md" \
  "$(run "$ws" twice)"
check "only metadata.usage counts" \
  "1|[xndv] ERROR: no metadata.usage in $ws/.agents/skills/no-usage/SKILL.md" "$(run "$ws" no-usage)"
check "no frontmatter" \
  "1|[xndv] ERROR: no metadata.usage in $ws/.agents/skills/bare/SKILL.md" "$(run "$ws" bare)"
check "folded block refused" \
  "1|[xndv] ERROR: metadata.usage is not a literal block (usage: |) in $ws/.agents/skills/folded/SKILL.md" \
  "$(run "$ws" folded)"
check "tab indentation refused" \
  "1|[xndv] ERROR: metadata.usage is indented with tabs in $ws/.agents/skills/tabbed/SKILL.md" \
  "$(run "$ws" tabbed)"

echo "=== arguments ==="
check "--help succeeds" "0" "$(run "$ws" --help | head -n1 | cut -d"|" -f1)"
check "no argument fails" "1" "$(run "$ws" | head -n1 | cut -d"|" -f1)"
check "two arguments fail" "1" "$(run "$ws" good bad | head -n1 | cut -d"|" -f1)"

echo
echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]

# vim: ft=sh
