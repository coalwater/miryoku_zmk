#!/usr/bin/env bash
# Print both split halves' battery levels, read from the dongle's USB CDC log.
#
# Requires a dongle built with the usb-logging snippet:
#   tools/local-build.sh splitkb_aurora_corne_dongle   (with SNIPPET=zmk-usb-logging)
# Without it the dongle is HID-only and no /dev/cu.usbmodem* appears.
#
# Usage: tools/battery.sh [seconds-to-wait]   (default 15)
set -uo pipefail

wait_s="${1:-15}"

port="$(ls -t /dev/cu.usbmodem* 2>/dev/null | head -1)"
if [ -z "$port" ]; then
  echo "no dongle serial port (/dev/cu.usbmodem*)." >&2
  echo "the dongle needs a build with -S zmk-usb-logging; HID-only builds expose no port." >&2
  exit 1
fi

# CDC ACM ignores the line settings, but the port must be opened raw or the tty
# layer swallows/echoes lines.
stty -f "$port" raw -echo 115200 2>/dev/null || true

l=""; r=""
end=$(( $(date +%s) + wait_s ))
while [ "$(date +%s)" -lt "$end" ]; do
  # -t so a silent port cannot block past the deadline
  IFS= read -r -t 2 line < "$port" || continue
  case "$line" in
    *"batt "*)
      # firmware format:  ... batt left=47 right=70
      # (names come from CONFIG_ZMK_BATTERY_LOG_LABELS on the dongle)
      lvl_l="$(echo "$line" | sed -n 's/.*left=\([0-9-]*\).*/\1/p')"
      lvl_r="$(echo "$line" | sed -n 's/.*right=\([0-9-]*\).*/\1/p')"
      [ -n "$lvl_l" ] && l="$lvl_l"
      [ -n "$lvl_r" ] && r="$lvl_r"
      ;;
  esac
  [ -n "$l" ] && [ -n "$r" ] && break
done

if [ -z "$l" ] && [ -z "$r" ]; then
  echo "port $port is open but printed no battery line in ${wait_s}s." >&2
  echo "either the dongle build lacks the battery-log module, or a half is disconnected." >&2
  exit 2
fi

# -1 means the central has no cached level for that slot at all.
echo "left:  ${l:-?}%"
echo "right: ${r:-?}%"
