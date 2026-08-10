#!/usr/bin/env bash
# Verify microphone input: record five seconds, then play the recording back.

set -euo pipefail

duration=5
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
recording="$tmpdir/microphone.wav"

record_with_timeout() {
  local status

  if timeout --signal=INT "${duration}s" "$@"; then
    return 0
  else
    status=$?
  fi

  [[ "$status" -eq 124 ]] || return "$status"
}

echo "PULSE_SERVER=${PULSE_SERVER:-<unset>}"
echo "PIPEWIRE_REMOTE=${PIPEWIRE_REMOTE:-<unset>}"
echo "ALSA_CARD=${ALSA_CARD:-<unset>}"
echo "/dev/snd: $([ -d /dev/snd ] && find /dev/snd -mindepth 1 -maxdepth 1 -printf '%f ' || echo '<not shared>')"
echo

if command -v pactl &>/dev/null && pactl info &>/dev/null; then
  pactl info | grep -E 'Server (Name|String|Version)|Default Source'
  echo
  echo "[xndv] sources:"
  pactl list short sources
  echo
  echo "[xndv] recording for ${duration} seconds — speak now..."
  record_with_timeout parecord --file-format=wav "$recording"
  playback=(paplay "$recording")
elif [[ -n "${PIPEWIRE_REMOTE:-}" ]]; then
  if ! command -v pw-record &>/dev/null || ! command -v pw-play &>/dev/null; then
    echo "[xndv] ERROR: PipeWire is configured but pw-record/pw-play are unavailable" >&2
    echo "[xndv] rebuild with ENABLE_AUDIO=1, then relaunch" >&2
    exit 1
  fi

  echo "[xndv] using native PipeWire (${PIPEWIRE_REMOTE})"
  echo
  echo "[xndv] recording for ${duration} seconds — speak now..."
  record_with_timeout pw-record "$recording"
  playback=(pw-play "$recording")
elif [ -d /dev/snd ]; then
  if ! command -v arecord &>/dev/null || ! command -v aplay &>/dev/null; then
    echo "[xndv] ERROR: ALSA is shared but arecord/aplay are unavailable" >&2
    echo "[xndv] rebuild with ENABLE_AUDIO=1, then relaunch" >&2
    exit 1
  fi

  arecord -l
  echo
  echo "[xndv] recording for ${duration} seconds — speak now..."
  arecord -d "$duration" -f cd "$recording"
  playback=(aplay "$recording")
else
  echo "[xndv] ERROR: no sound server and no /dev/snd" >&2
  echo "[xndv] set ENABLE_AUDIO=1 in .env, rebuild (make build), relaunch" >&2
  exit 1
fi

if [[ ! -s "$recording" ]]; then
  echo "[xndv] ERROR: microphone recording is empty" >&2
  exit 1
fi

echo
echo "[xndv] playing microphone recording..."
"${playback[@]}"
