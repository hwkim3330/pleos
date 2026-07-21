#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
VENV="$ROOT/.venv-esp-bridge"

test -d "$VENV" || python3 -m venv "$VENV"
"$VENV/bin/pip" -q install -r "$ROOT/tools/esp_bridge/requirements.txt"
exec "$VENV/bin/python" "$ROOT/tools/esp_bridge/bridge.py" "$@"
