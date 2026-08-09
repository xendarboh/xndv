#!/usr/bin/env bash
# Verify container sound: report what the launcher wired up, then make noise.

echo "PULSE_SERVER=${PULSE_SERVER:-<unset>}"
echo "PIPEWIRE_REMOTE=${PIPEWIRE_REMOTE:-<unset>}"
echo "ALSA_CARD=${ALSA_CARD:-<unset>}"
echo "/dev/snd: $([ -d /dev/snd ] && ls /dev/snd | tr '\n' ' ' || echo '<not shared>')"
echo

if command -v pactl &>/dev/null && pactl info &>/dev/null; then
  pactl info | grep -E 'Server (Name|String|Version)|Default Sink'
  echo
  echo "[xndv] sinks:"
  pactl list short sinks
elif [ -d /dev/snd ]; then
  echo "[xndv] no sound server reachable — falling back to ALSA"
  aplay -l
else
  echo "[xndv] ERROR: no sound server and no /dev/snd" >&2
  echo "[xndv] set ENABLE_AUDIO=1 in .env, rebuild (make build), relaunch" >&2
  exit 1
fi

echo
echo "[xndv] playing test sound..."
if command -v paplay &>/dev/null && [ -n "${PULSE_SERVER:-}${PIPEWIRE_REMOTE:-}" ]; then
  paplay /usr/share/sounds/freedesktop/stereo/complete.oga
else
  speaker-test -t sine -f 440 -l 1 -P 2
fi
