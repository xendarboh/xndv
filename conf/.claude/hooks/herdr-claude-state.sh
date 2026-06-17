#!/bin/sh
# xndv: report Claude Code lifecycle state to herdr.
#
# Why this exists
# ---------------
# herdr identifies an agent's pane by detecting the `claude` *process* on the host.
# Inside an xndv container the pane's foreground process (from host herdr's view) is
# `docker exec ... sh -c bash`, never `claude`, so herdr never labels the pane and the
# status is stuck at "unknown".
#
# This hook supplies the missing identity: `report-agent --agent claude` labels the pane,
# which lets herdr apply its `claude.toml` manifest and screen-scrape live state from the
# pane's OSC title (those escape codes pass through `docker exec`). NOTE: contrary to
# earlier belief, herdr does NOT grant a custom source lifecycle authority — it keeps
# screen-scraping (`screen_detection_skipped: false`). So the `--agent` label is what
# matters most; the `--state` value is a secondary/fallback signal. Drop this source
# (`release-agent`) and the pane reverts to "unknown" instantly. See
# docs/20260616-herdr-claude.md for the full mechanism + validation.
#
# Registered container-wide via conf/.claude/settings.json (symlinked over the user
# settings in CLAUDE_CONFIG_DIR by conf/.bash_xndv).
# Note: state under the reserved `herdr:claude` source is ignored (identity-only), so we
# report under the custom source `xndv-claude`.
#
# Usage: herdr-claude-state.sh <idle|working|blocked>
set -eu

state="${1:-}"
[ -n "$state" ] || exit 0
[ "${HERDR_ENV:-}" = "1" ] || exit 0
[ -n "${HERDR_PANE_ID:-}" ] || exit 0
[ -n "${HERDR_SOCKET_PATH:-}" ] || exit 0
command -v herdr >/dev/null 2>&1 || exit 0

# --seq must be monotonic; herdr drops stale (lower-seq) reports.
herdr pane report-agent "$HERDR_PANE_ID" \
  --source xndv-claude --agent claude --state "$state" \
  --seq "$(date +%s%N)" >/dev/null 2>&1 || true

exit 0
