#!/usr/bin/env bash
set -e

# ==============================================================================
# run_mock_test.sh
# 開発・ローカル環境向け Mock検証スクリプト
# 推論サーバーとMock走行クライアントをローカルで起動してテストします。
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SERVER_SCRIPT="$PROJECT_ROOT/Inference-framework/lerobot_async_server.py"
if [ ! -f "$SERVER_SCRIPT" ]; then
    SERVER_SCRIPT="$PROJECT_ROOT/../VLA-Learning/lerobot_async_server.py"
fi
CLIENT_SCRIPT="$SCRIPT_DIR/machine_vla.rb"
PORT=8080

export PROMPT="${1:-${PROMPT:-Go to the blue star}}"
export INFERENCE_SERVER_URL="http://127.0.0.1:$PORT"
unset PRODUCTION

echo "======================================================================"
echo "  [Mock検証] LeRobot 4WD リアルタイム非同期推論テスト"
echo "  タスク指示: '$PROMPT'"
echo "  推論サーバー: $INFERENCE_SERVER_URL"
echo "======================================================================"

# 既存サーバーの稼働チェック
if curl -s "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
    echo "[1/2] 推論サーバーは既に起動しています (Port: $PORT)。"
    SERVER_PID=""
else
    CONDA_PYTHON="$HOME/miniforge3/envs/lerobot/bin/python"
    if [ ! -f "$CONDA_PYTHON" ]; then
        CONDA_PYTHON="$PROJECT_ROOT/miniforge3/envs/lerobot/bin/python"
    fi
    if [ ! -f "$CONDA_PYTHON" ]; then
        CONDA_PYTHON="python"
    fi

    echo "[1/2] 推論サーバーを起動中 (Port: $PORT)..."
    "$CONDA_PYTHON" "$SERVER_SCRIPT" --port "$PORT" &
    SERVER_PID=$!

    # サーバー待機
    for i in {1..30}; do
        if curl -s "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
            echo "推論サーバーがオンラインになりました！"
            break
        fi
        sleep 1
    done
fi

cleanup() {
    if [ -n "$SERVER_PID" ]; then
        echo -e "\n[シャットダウン] 推論サーバーを終了します (PID: $SERVER_PID)..."
        kill -TERM "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

# クライアント実行
echo "[2/2] Mock走行クライアントを起動します (停止は Ctrl+C)..."
ruby "$CLIENT_SCRIPT"
