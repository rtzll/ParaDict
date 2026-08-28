#!/bin/bash
# Compiles the MLX Metal shaders into a metallib.
#
# SwiftPM (command line) cannot compile .metal files, but MLX (used by the
# optional S1-mini cleanup stage) needs its default Metal library at runtime.
# This script builds it from the resolved mlx-swift checkout and caches it in
# .build/metallib/. Consumers place it next to the binary that links Cmlx:
#
#   - the app bundle:  ParaDict.app/Contents/MacOS/mlx.metallib
#   - test runners:    alongside the xctest executable
#
# MLX searches (see mlx backend/metal/device.cpp):
#   <binary dir>/mlx.metallib, <SwiftPM bundle>/default.metallib, ...
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT_DIR="$ROOT/.build/metallib"
OUT_LIB="$OUT_DIR/mlx.metallib"
FINGERPRINT_FILE="$OUT_DIR/build.fingerprint"

CHECKOUT=$(ls -d "$ROOT"/.build/checkouts/mlx-swift 2>/dev/null || true)
if [ -z "$CHECKOUT" ]; then
  echo "error: mlx-swift checkout not found; run 'swift package resolve' first" >&2
  exit 1
fi

METAL_SRC_DIR="$CHECKOUT/Source/Cmlx/mlx-generated/metal"
if [ ! -d "$METAL_SRC_DIR" ]; then
  echo "error: metal sources not found at $METAL_SRC_DIR" >&2
  exit 1
fi

# The generated shaders include local headers, so cache by all shader inputs,
# the compiler version, and this build recipe rather than file timestamps.
SOURCE_HASH=$(
  find "$METAL_SRC_DIR" -type f \( -name '*.metal' -o -name '*.h' \) -print \
    | LC_ALL=C sort \
    | while IFS= read -r source; do shasum "$source"; done \
    | shasum \
    | awk '{print $1}'
)
COMPILER_VERSION=$(xcrun -sdk macosx metal --version 2>&1)
SCRIPT_HASH=$(shasum "$0" | awk '{print $1}')
FINGERPRINT=$(
  printf '%s\n%s\n%s\n' "$SOURCE_HASH" "$COMPILER_VERSION" "$SCRIPT_HASH" \
    | shasum \
    | awk '{print $1}'
)

if [ -f "$OUT_LIB" ] && [ -f "$FINGERPRINT_FILE" ]; then
  if [ "$(cat "$FINGERPRINT_FILE")" = "$FINGERPRINT" ]; then
    echo "metallib up to date: $OUT_LIB"
    exit 0
  fi
fi

mkdir -p "$OUT_DIR"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

echo "Compiling MLX metal kernels..."
for src in "$METAL_SRC_DIR"/*.metal; do
  xcrun -sdk macosx metal -Wall -Wno-unused-function \
    -I "$METAL_SRC_DIR" -c "$src" -o "$WORK_DIR/$(basename "${src%.metal}").air"
done

xcrun -sdk macosx metallib "$WORK_DIR"/*.air -o "$OUT_LIB"
printf '%s\n' "$FINGERPRINT" > "$FINGERPRINT_FILE"

echo "metallib built: $OUT_LIB"
