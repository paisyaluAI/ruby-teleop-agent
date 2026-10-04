#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if ! command -v conda >/dev/null 2>&1; then
  CONDA_PROFILE="${CONDA_BASE:-$HOME/miniforge3}/etc/profile.d/conda.sh"
  if [ -f "$CONDA_PROFILE" ]; then
    source "$CONDA_PROFILE"
  else
    echo "conda is required" >&2
    exit 1
  fi
fi

eval "$(conda shell.bash hook)"
if ! conda env list | awk '{print $1}' | grep -qx 'lerobot'; then
  conda create -n lerobot python=3.12 -y
fi
conda activate lerobot

# 1. lerobot ディレクトリの探索 (ruby-teleop-agent と同階層を優先)
LEROBOT_DIR="${LEROBOT_DIR:-}"
if [ -z "$LEROBOT_DIR" ] || [ ! -d "$LEROBOT_DIR" ]; then
  for candidate in \
    "$(cd "$SCRIPT_DIR/../.." && pwd)/lerobot" \
    "$(cd "$SCRIPT_DIR/.." && pwd)/lerobot" \
    "$SCRIPT_DIR/lerobot" \
    "$(cd "$SCRIPT_DIR/../.." && pwd)/VLA-Learning/lerobot"; do
    if [ -f "$candidate/pyproject.toml" ] || [ -d "$candidate/src/lerobot" ]; then
      LEROBOT_DIR="$candidate"
      break
    fi
  done
fi

# 2. 見つからない場合は ruby-teleop-agent と同じ階層に git clone
if [ -z "$LEROBOT_DIR" ] || [ ! -d "$LEROBOT_DIR" ]; then
  DEFAULT_LEROBOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)/lerobot"
  echo "lerobot ディレクトリが見つかりませんでした。"
  echo "ruby-teleop-agent と同じ階層 ($DEFAULT_LEROBOT_DIR) に git clone します..."
  git clone https://github.com/huggingface/lerobot.git "$DEFAULT_LEROBOT_DIR"
  LEROBOT_DIR="$DEFAULT_LEROBOT_DIR"
fi

echo "使用する LeRobot ディレクトリ: $LEROBOT_DIR"

python -m pip install --upgrade pip
python -m pip install -e "$LEROBOT_DIR[dataset,training,smolvla]"
python -m pip install -r "$SCRIPT_DIR/requirements.txt"

export PYTHONPATH="$LEROBOT_DIR/src${PYTHONPATH:+:$PYTHONPATH}"
echo "Setup complete."
echo "Run: ./learning.sh"
