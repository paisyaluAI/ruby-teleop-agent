#!/usr/bin/env bash
set -e

# ==============================================================================
# run_server.sh
# LeRobot HTTP 非同期推論サーバー起動スクリプト
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
PYTHON_BIN="${VENV_DIR:-$WORKSPACE_ROOT/.venv}/bin/python"
if [ ! -x "$PYTHON_BIN" ]; then
    echo "uv environment not found: $PYTHON_BIN" >&2
    echo "Run: (cd $WORKSPACE_ROOT && uv sync)" >&2
    exit 1
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
ACT_MODE="${ACT_MODE:-0}"

if [ "$ACT_MODE" = "1" ]; then
    SERVER_SCRIPT="$SCRIPT_DIR/lerobot_act_server.py"
    POLICY_LABEL="ACT"
else
    SERVER_SCRIPT="$SCRIPT_DIR/lerobot_async_server.py"
    POLICY_LABEL="SmolVLA"
fi

echo "======================================================================"
echo "  LeRobot HTTP Inference Server"
echo "  Policy: $POLICY_LABEL (ACT_MODE=$ACT_MODE)"
echo "  Listen: $HOST:$PORT"
echo "  Checkpoint: ${CHECKPOINT:-デフォルト (最新学習モデル)}"
echo "  Device: $DEVICE"
echo "======================================================================"

CMD=("$SERVER_SCRIPT" --host "$HOST" --port "$PORT" --device "$DEVICE")
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

exec "$PYTHON_BIN" "${CMD[@]}"


