#!/usr/bin/env bash
set -e

# ==============================================================================
# run_server.sh
# LeRobot HTTP 非同期推論サーバー起動スクリプト
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONDA_BASE="${CONDA_BASE:-$HOME/miniforge3}"
if [ ! -d "$CONDA_BASE" ] && [ -d "$(dirname "$SCRIPT_DIR")/miniforge3" ]; then
    CONDA_BASE="$(dirname "$SCRIPT_DIR")/miniforge3"
fi

# Conda 環境の有効化
if [ -f "$CONDA_BASE/bin/activate" ]; then
    source "$CONDA_BASE/bin/activate" lerobot
elif command -v conda >/dev/null 2>&1; then
    eval "$(conda shell.bash hook)"
    conda activate lerobot
else
    echo "警告: miniforge3 が見つかりません。現在の Python 環境を使用します。"
fi

HOST="${1:-0.0.0.0}"
PORT="${2:-8080}"
CHECKPOINT="${3:-}"
DEVICE="${4:-auto}"

echo "======================================================================"
echo "  LeRobot HTTP Inference Server"
echo "  Listen: $HOST:$PORT"
echo "  Checkpoint: ${CHECKPOINT:-デフォルト (最新学習モデル)}"
echo "  Device: $DEVICE"
echo "======================================================================"

CMD=("$SCRIPT_DIR/lerobot_async_server.py" --host "$HOST" --port "$PORT" --device "$DEVICE")
if [ -n "$CHECKPOINT" ]; then
    CMD+=(--checkpoint "$CHECKPOINT")
fi
if [ -n "$CREATE_STEPS" ]; then
    CMD+=(--create-steps "$CREATE_STEPS")
elif [ -n "$CHUNK_SIZE" ]; then
    CMD+=(--create-steps "$CHUNK_SIZE")
fi
if [ -n "$EXEC_STEPS" ]; then
    CMD+=(--exec-steps "$EXEC_STEPS")
fi
if [ -n "$TIMEOUT_KEEP_ALIVE" ]; then
    CMD+=(--timeout-keep-alive "$TIMEOUT_KEEP_ALIVE")
fi
if [ $# -ge 5 ]; then
    CMD+=("${@:5}")
fi

exec python "${CMD[@]}"


