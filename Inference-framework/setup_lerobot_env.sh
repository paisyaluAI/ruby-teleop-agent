#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if ! command -v conda >/dev/null 2>&1; then
  echo "conda is required" >&2
  exit 1
fi

eval "$(conda shell.bash hook)"
if ! conda env list | awk '{print $1}' | grep -qx 'lerobot'; then
  conda create -n lerobot python=3.12 -y
fi
conda activate lerobot

python -m pip install --upgrade pip
python -m pip install -e "$SCRIPT_DIR/lerobot[dataset,training,smolvla]"

export PYTHONPATH="$SCRIPT_DIR/lerobot/src${PYTHONPATH:+:$PYTHONPATH}"
echo "Setup complete."
echo "Run: ./learning.sh"
