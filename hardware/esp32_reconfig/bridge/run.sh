#!/bin/sh
set -eu

BRIDGE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$BRIDGE_DIR/../../.." && pwd)
VENV="$ROOT/.venv-esp-bridge"

test -d "$VENV" || python3 -m venv "$VENV"
"$VENV/bin/pip" -q install -r "$BRIDGE_DIR/requirements.txt"
exec "$VENV/bin/python" "$BRIDGE_DIR/bridge.py" "$@"
