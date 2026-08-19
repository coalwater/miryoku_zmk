#!/usr/bin/env bash
# One-time local ZMK toolchain setup. No Homebrew: uv provides the venv,
# west and ninja come from PyPI, and the ARM compiler is the Zephyr SDK
# tarball unpacked into the workspace (nothing is installed system-wide).
#
# dtc is deliberately NOT installed - Zephyr treats it as optional and uses
# its own Python devicetree parser; a missing dtc is a warning, not an error.
#
# Usage: tools/local-setup.sh          (ZMK_WS overrides the workspace root)
set -euo pipefail

WS="${ZMK_WS:-$TMPDIR/zmk-ws}"
mkdir -p "$WS"
# macOS: /tmp is a symlink to /private/tmp. Zephyr builds relative include
# paths between the build and source trees, and they break unless both sides
# use the same spelling - so always work from the resolved path.
WS="$(cd "$WS" && pwd -P)"
ZMK_BRANCH="${ZMK_BRANCH:-v0.3-branch}"   # matches branches: in the workflows
SDK="${SDK:-0.16.9}"                      # matches zmkfirmware/zmk-build-arm:stable
HOST="macos-aarch64"

export UV_CACHE_DIR="${UV_CACHE_DIR:-$WS/.uv-cache}"
echo "== venv + west"
uv venv --python 3.12 "$WS/.venv"
PY="$WS/.venv/bin/python"
uv pip install --python "$PY" west ninja

echo "== zmk checkout"
[ -d "$WS/zmk/.git" ] || git clone --depth 1 -b "$ZMK_BRANCH" https://github.com/zmkfirmware/zmk.git "$WS/zmk"

echo "== west init/update (~3.5G)"
export PATH="$WS/.venv/bin:$PATH"
cd "$WS/zmk"
[ -d .west ] || west init -l app
west update

echo "== zephyr python requirements"
uv pip install --python "$PY" -r "$WS/zmk/zephyr/scripts/requirements-base.txt"

echo "== zephyr sdk $SDK (arm only)"
if [ ! -d "$WS/zephyr-sdk-$SDK/arm-zephyr-eabi" ]; then
  base="https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v$SDK"
  cd "$WS"
  curl -fL -o minimal.tar.xz "$base/zephyr-sdk-${SDK}_${HOST}_minimal.tar.xz"
  curl -fL -o arm.tar.xz     "$base/toolchain_${HOST}_arm-zephyr-eabi.tar.xz"
  tar xf minimal.tar.xz
  tar xf arm.tar.xz -C "zephyr-sdk-$SDK"
  rm -f minimal.tar.xz arm.tar.xz
fi
# setup.sh -c only registers a CMake package in ~/.cmake; local-build.sh sets
# ZEPHYR_SDK_INSTALL_DIR instead, so registration is not needed.

"$WS/zephyr-sdk-$SDK/arm-zephyr-eabi/bin/arm-zephyr-eabi-gcc" --version | head -1
echo
echo "== ready. build with:  tools/local-build.sh \"splitkb_aurora_corne_left nice_view_adapter nice_view\""
