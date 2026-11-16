#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
cd "$SCRIPT_DIR"

VENV_ACTIVATE="${VENV_DIR:-$WORKSPACE_ROOT/.venv}/bin/activate"
if [ -f "$VENV_ACTIVATE" ]; then
  # shellcheck disable=SC1090
  source "$VENV_ACTIVATE"
elif [ -f "$SCRIPT_DIR/.venv/bin/activate" ]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/.venv/bin/activate"
fi

# 1. ワークスペース内の lerobot ディレクトリを探索
LEROBOT_DIR="${LEROBOT_DIR:-}"
if [ -z "$LEROBOT_DIR" ] || [ ! -d "$LEROBOT_DIR" ]; then
  for candidate in \
    "$WORKSPACE_ROOT/third_party/lerobot" \
    "$WORKSPACE_ROOT/apps/ruby-teleop-agent/lerobot"; do
    if [ -d "$candidate/src" ]; then
      LEROBOT_DIR="$candidate"
      break
    fi
  done
fi

if [ -n "$LEROBOT_DIR" ] && [ -d "$LEROBOT_DIR/src" ]; then
  export PYTHONPATH="$LEROBOT_DIR/src${PYTHONPATH:+:$PYTHONPATH}"
  echo "[learning.sh] LeRobot source detected: $LEROBOT_DIR/src"
fi

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <dataset_dir>" >&2
  exit 1
fi

DATASET_ROOT="$1"

if [ ! -d "$DATASET_ROOT" ]; then
  echo "Error: dataset directory does not exist: $DATASET_ROOT" >&2
  exit 1
fi

OUTPUT_DIR="$SCRIPT_DIR/outputs/train/ruby_physicalAI_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$(dirname "$OUTPUT_DIR")"

python -m lerobot.scripts.lerobot_train \
  --dataset.root="$DATASET_ROOT" \
  --dataset.repo_id="$DATASET_ROOT" \
  --dataset.use_imagenet_stats=false \
  --tolerance_s=0.1 \
  --policy.path=lerobot/smolvla_base \
  --policy.push_to_hub=false \
  --output_dir="$OUTPUT_DIR" \
  --job_name=lerobot_training \
  --policy.device=cuda \
  --wandb.enable=true \
  --rename_map='{"state":"observation.state","rgb":"observation.images.camera1"}' \
  --policy.empty_cameras=2 \
  --dataset.eval_split=0.1 \
  --eval_steps=100 \
  --save_checkpoint=true \
  --save_freq=1000 \
  --steps=6000 \