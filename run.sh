#!/usr/bin/env bash
# run.sh — start the freshly built Rigs with a throwaway configuration directory,
# so experiments never touch ~/.config/rigs. Build first with ./build.sh.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="${SCRIPT_DIR}/build/src/rigs"
[[ -x "$BIN" ]] || { echo "No build found at $BIN — run ./build.sh first." >&2; exit 1; }

KEEP=0
if [[ "${1:-}" == "--keep" ]]; then KEEP=1; shift; fi
CONFIG="$(mktemp -d "${TMPDIR:-/tmp}/rigs-run-XXXXXX")"
if [[ $KEEP -eq 1 ]]; then echo "Config directory: $CONFIG/rigs"; else trap 'rm -rf "$CONFIG"' EXIT INT TERM; fi

# A separate application ID would be cleaner, but the D-Bus name is fixed; quit a running Rigs first.
XDG_CONFIG_HOME="$CONFIG" "$BIN" "$@"
