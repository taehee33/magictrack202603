#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT_DIR/iohid_event_probe.c"
BIN="/tmp/iohid_event_probe"

clang -framework IOKit -framework CoreFoundation -o "$BIN" "$SRC"
"$BIN" "$@"
