#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
cd "$SCRIPT_DIR"

if ! command -v uv >/dev/null 2>&1; then
  echo "uv is required (https://docs.astral.sh/uv/)" >&2
  exit 1
fi

# 1. ワークスペース内の lerobot ディレクトリを探索
LEROBOT_DIR="${LEROBOT_DIR:-}"
if [ -z "$LEROBOT_DIR" ] || [ ! -d "$LEROBOT_DIR" ]; then
  for candidate in \
    "$WORKSPACE_ROOT/third_party/lerobot" \
    "$WORKSPACE_ROOT/apps/ruby-teleop-agent/lerobot"; do
    if [ -f "$candidate/pyproject.toml" ] || [ -d "$candidate/src/lerobot" ]; then
      LEROBOT_DIR="$candidate"
      break
    fi
  done
fi

# 2. 見つからない場合は third_party に clone
if [ -z "$LEROBOT_DIR" ] || [ ! -d "$LEROBOT_DIR" ]; then
  DEFAULT_LEROBOT_DIR="$WORKSPACE_ROOT/third_party/lerobot"
  echo "lerobot ディレクトリが見つかりませんでした。"
  echo "third_party ($DEFAULT_LEROBOT_DIR) に git clone します..."
  mkdir -p "$(dirname "$DEFAULT_LEROBOT_DIR")"
  git clone https://github.com/huggingface/lerobot.git "$DEFAULT_LEROBOT_DIR"
  LEROBOT_DIR="$DEFAULT_LEROBOT_DIR"
fi

echo "使用する LeRobot ディレクトリ: $LEROBOT_DIR"

if [ -f "$WORKSPACE_ROOT/pyproject.toml" ]; then
  echo "Syncing shared uv environment at $WORKSPACE_ROOT/.venv ..."
  (cd "$WORKSPACE_ROOT" && uv sync)
else
  VENV_DIR="${VENV_DIR:-$WORKSPACE_ROOT/.venv}"
  if [ ! -d "$VENV_DIR" ]; then
    uv venv "$VENV_DIR" --python 3.12
  fi
  uv pip install --python "$VENV_DIR/bin/python" -e "$LEROBOT_DIR[dataset,training,smolvla]"
  uv pip install --python "$VENV_DIR/bin/python" -r "$SCRIPT_DIR/requirements.txt"
fi

# shellcheck disable=SC1091
source "$WORKSPACE_ROOT/.venv/bin/activate"
export PYTHONPATH="$LEROBOT_DIR/src${PYTHONPATH:+:$PYTHONPATH}"
echo "Setup complete ($VIRTUAL_ENV)."
echo "Run: ./learning.sh <dataset_dir>"
