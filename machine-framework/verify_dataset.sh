#!/usr/bin/env bash
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATASET_PATH="${1:-$SCRIPT_DIR/output_dataset}"

PYTHON_BIN="$(which python3)"
if [ -f "$SCRIPT_DIR/../miniforge3/envs/lerobot/bin/python" ]; then
    PYTHON_BIN="$SCRIPT_DIR/../miniforge3/envs/lerobot/bin/python"
elif [ -f "$HOME/miniforge3/envs/lerobot/bin/python" ]; then
    PYTHON_BIN="$HOME/miniforge3/envs/lerobot/bin/python"
fi

"$PYTHON_BIN" "$SCRIPT_DIR/test/test_dataset.py" "$DATASET_PATH"
