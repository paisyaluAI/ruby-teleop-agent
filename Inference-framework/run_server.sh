#!/usr/bin/env bash
set -e

# ==============================================================================
# run_server.sh
# LeRobot HTTP 非同期推論サーバー起動スクリプト
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
VENV_ACTIVATE="${VENV_DIR:-$WORKSPACE_ROOT/.venv}/bin/activate"

# uv 共通仮想環境 (.venv) の有効化
if [ -f "$VENV_ACTIVATE" ]; then
    # shellcheck disable=SC1090
    source "$VENV_ACTIVATE"
elif [ -f "$SCRIPT_DIR/.venv/bin/activate" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/.venv/bin/activate"
else
    echo "警告: $WORKSPACE_ROOT/.venv が見つかりません。現在の Python 環境を使用します。"
fi

# ワークスペース内の lerobot ディレクトリを探索
if [ -z "${LEROBOT_DIR:-}" ]; then
  for candidate in \
    "$WORKSPACE_ROOT/third_party/lerobot" \
    "$WORKSPACE_ROOT/apps/ruby-teleop-agent/lerobot"; do
    if [ -d "$candidate/src" ]; then
      export LEROBOT_DIR="$candidate"
      export PYTHONPATH="$LEROBOT_DIR/src${PYTHONPATH:+:$PYTHONPATH}"
      break
    fi
  done
elif [ -d "$LEROBOT_DIR/src" ]; then
  export PYTHONPATH="$LEROBOT_DIR/src${PYTHONPATH:+:$PYTHONPATH}"
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


