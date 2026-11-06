#!/usr/bin/env bash
# Poll the dongle once and cache the levels for the shell prompt.
#
# Reading the CDC port means waiting for the dongle's next log line, which is
# seconds - far too slow for a prompt. So this runs on a timer (launchd, see
# tools/kbd-battery.plist) and the prompt only ever reads the cache file.
#
# Cache format, one line:  <left> <right> <unix-time>
# A half with no cached level on the dongle reads -1.
set -uo pipefail

cache="$HOME/.cache/keyboard-battery"
mkdir -p "$(dirname "$cache")"

out="$("$(dirname "${BASH_SOURCE[0]}")/battery.sh" 30 2>/dev/null)" || exit 0

l="$(echo "$out" | sed -n 's/^left: *\([0-9-]*\)%.*/\1/p')"
r="$(echo "$out" | sed -n 's/^right: *\([0-9-]*\)%.*/\1/p')"
[ -z "$l" ] && [ -z "$r" ] && exit 0

# macOS has no sponge: write a tempfile and rename, so the prompt never reads a
# half-written line.
tmp="$(mktemp "$cache.XXXXXX")"
echo "${l:--1} ${r:--1} $(date +%s)" > "$tmp"
mv "$tmp" "$cache"

# Keep every reading too: the cache only holds the latest, and a drain rate
# needs days of history (single readings are ADC noise on a flat curve).
cat "$cache" >> "$cache.log"
