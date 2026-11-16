#!/usr/bin/env bash
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
DATASET_PATH="${1:-$SCRIPT_DIR/output_dataset}"

PYTHON_BIN="$(command -v python3 || command -v python)"
if [ -n "${VIRTUAL_ENV:-}" ] && [ -x "$VIRTUAL_ENV/bin/python" ]; then
    PYTHON_BIN="$VIRTUAL_ENV/bin/python"
elif [ -x "$WORKSPACE_ROOT/.venv/bin/python" ]; then
    PYTHON_BIN="$WORKSPACE_ROOT/.venv/bin/python"
elif [ -x "$SCRIPT_DIR/../.venv/bin/python" ]; then
    PYTHON_BIN="$SCRIPT_DIR/../.venv/bin/python"
fi

"$PYTHON_BIN" "$SCRIPT_DIR/test/test_dataset.py" "$DATASET_PATH"
