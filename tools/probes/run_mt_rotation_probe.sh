#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT_DIR/mt_rotation_probe.c"
BIN="/tmp/mt_rotation_probe"

clang -framework CoreFoundation -o "$BIN" "$SRC"
"$BIN" "$@"
