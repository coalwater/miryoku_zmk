#!/usr/bin/env bash
# Local ZMK build for this config repo - replaces a CI round-trip.
#
# Mirrors .github/workflows/main.yml: it stages a copy of the repo, appends the
# MIRYOKU_* defines to miryoku/custom_config.h and any extra Kconfig lines to
# the shield's .conf, then runs the same `west build` the container runs.
#
# Usage:
#   tools/local-build.sh "splitkb_aurora_corne_left nice_view_adapter nice_view"
#   KCONFIG=$'CONFIG_ZMK_USB_LOGGING=y\nCONFIG_LVGL_LOG_LEVEL_DBG=y' tools/local-build.sh "..."
#
# Env:
#   ZMK_WS   workspace root      (default: $TMPDIR/zmk-ws)
#   BOARD    target board        (default: nice_nano_v2)
#   ALPHAS / EXTRA / TAP / NAV / CLIPBOARD / LAYERS / MAPPING   miryoku options
#   KCONFIG  extra Kconfig lines appended to config/<shield>.conf
#   SNIPPET  space-separated Zephyr snippets, e.g. SNIPPET=zmk-usb-logging
#            (USB logging NEEDS the snippet: CONFIG_ZMK_USB_LOGGING alone
#             selects SERIAL but nothing provides a serial driver, and the
#             build dies with "SERIAL_HAS_DRIVER ... value n". The snippet
#             adds the cdc-acm DT node and the zephyr,console chosen.)
#   PRISTINE set to 1 to force a full reconfigure
#   EXTRA_OVERLAY  path to a .overlay applied LAST (after every shield overlay).
#            Needed to override a shield: a config-repo <shield>.overlay is
#            applied BEFORE the shield overlays, so it can only add nodes.
#   MODULES  space-separated user/repo/branch ZMK modules, cloned into
#            $ZMK_WS/modules/ and passed as -DZMK_EXTRA_MODULES. Same spelling
#            the `modules:` input of .github/workflows/main.yml takes, e.g.
#            MODULES=petejohanson/cirque-input-module/main
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WS="${ZMK_WS:-$TMPDIR/zmk-ws}"
mkdir -p "$WS"
# macOS: /tmp is a symlink to /private/tmp. Zephyr builds relative include
# paths between the build and source trees, and they break unless both sides
# use the same spelling - so always work from the resolved path.
WS="$(cd "$WS" && pwd -P)"
BOARD="${BOARD:-nice_nano_v2}"
SHIELD="${1:?usage: local-build.sh \"<shield ...>\"}"

: "${ALPHAS:=QWERTY}" "${NAV:=vi}"
: "${EXTRA:=}" "${TAP:=}" "${CLIPBOARD:=}" "${LAYERS:=}" "${MAPPING:=}"
: "${KCONFIG:=}" "${SNIPPET:=}" "${EXTRA_OVERLAY:=}" "${MODULES:=}"

[ -d "$WS/zmk/zephyr" ] || { echo "no zmk workspace at $WS - run tools/local-setup.sh first" >&2; exit 1; }

export ZEPHYR_TOOLCHAIN_VARIANT=zephyr
export ZEPHYR_SDK_INSTALL_DIR="$WS/zephyr-sdk-0.16.9"
export ZEPHYR_BASE="$WS/zmk/zephyr"
export PATH="$WS/.venv/bin:$PATH"

shield_first="${SHIELD%% *}"                             # splitkb_aurora_corne_left
base="$(echo "$shield_first" | sed -e 's/_\(left\|right\|dongle\)//' -e 's/@.*//')"
slug="$(echo "$SHIELD" | tr ' ' '-')"
snippet_arg=""
for sn in $SNIPPET; do
  snippet_arg="$snippet_arg -S $sn"
  slug="$slug-$sn"
done

# Stage a copy so the real repo is never mutated.
stage="$WS/stage/$slug"
rm -rf "$stage"; mkdir -p "$stage"
cp -R "$REPO/config" "$REPO/miryoku" "$stage/"

cfg="$stage/miryoku/custom_config.h"
{
  echo "#define MIRYOKU_KEYBOARD_$(echo "$base" | tr -c '[:alnum:]' '_' | tr '[:lower:]' '[:upper:]')"
  cat "$cfg"
} > "$cfg.tmp" && mv "$cfg.tmp" "$cfg"

for opt in "alphas_$ALPHAS" "extra_$EXTRA" "tap_$TAP" "nav_$NAV" \
           "clipboard_$CLIPBOARD" "layers_$LAYERS" "mapping_$MAPPING"; do
  case "$opt" in
    *_ | *_default ) ;;
    * ) echo "#define MIRYOKU_$(echo "$opt" | tr 'a-z' 'A-Z')" >> "$cfg" ;;
  esac
done

if [ -n "$KCONFIG" ]; then
  printf '%b\n' "$KCONFIG" >> "$stage/config/$shield_first.conf"
  echo "== extra Kconfig appended to $shield_first.conf:"
  printf '%b\n' "$KCONFIG" | sed 's/^/   /'
fi

# Out-of-tree ZMK modules, cloned the same way main.yml does it.
module_dirs=""
for m in $MODULES; do
  user="$(echo "$m" | cut -f 1 -d /)"
  repo="$(echo "$m" | cut -f 2 -d /)"
  branch="$(echo "$m" | cut -f 3- -d /)"
  d="$WS/modules/$user-$repo-$(echo "$branch" | tr / _)"
  [ -d "$d" ] || git clone -b "$branch" --depth 1 "https://github.com/$user/$repo.git" "$d"
  module_dirs="$module_dirs$d;"
  slug="$slug-$repo"
done
modules_arg=""
[ -n "$module_dirs" ] && modules_arg="-DZMK_EXTRA_MODULES=$module_dirs"

build="$WS/build/$slug"

pristine_arg=""
[ "${PRISTINE:-0}" = 1 ] && pristine_arg="-p"

cd "$WS/zmk/app"
extra_overlay_arg=""
[ -n "$EXTRA_OVERLAY" ] && extra_overlay_arg="-DEXTRA_DTC_OVERLAY_FILE=$EXTRA_OVERLAY"

west build $pristine_arg $snippet_arg -b "$BOARD" -d "$build" -- \
  -DSHIELD="$SHIELD" -DZMK_CONFIG="$stage/config" $modules_arg $extra_overlay_arg

out="${OUT_DIR:-$WS/out}"
mkdir -p "$out"
cp "$build/zephyr/zmk.uf2" "$out/$slug.uf2"
echo
echo "== built: $out/$slug.uf2"
ls -l "$out/$slug.uf2"
