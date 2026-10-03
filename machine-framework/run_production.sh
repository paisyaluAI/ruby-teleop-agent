#!/usr/bin/env bash
set -e

# ==============================================================================
# run_production.sh
# Raspberry Pi 実機用 本番起動スクリプト
# GPIO, SDL2 ゲームパッド, 実機カメラ (ID: 0) を使用して
# リモート推論サーバーとリアルタイム双方向制御を行います。
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLIENT_SCRIPT="$SCRIPT_DIR/machine_vla.rb"

# 推論サーバーのホスト/ポート (環境変数または第1引数で指定可能)
SERVER_HOST="${1:-${SERVER_HOST:-127.0.0.1}}"
SERVER_PORT="${2:-${SERVER_PORT:-8080}}"
export INFERENCE_SERVER_URL="http://${SERVER_HOST}:${SERVER_PORT}"
export PRODUCTION=1
export PROMPT="${3:-${PROMPT:-Go to the blue star}}"

if [ -z "$1" ] && [ -z "$SERVER_HOST" ]; then
    echo "----------------------------------------------------------------------"
    echo "[INFO] サーバーIPが指定されていないため、ローカル (127.0.0.1) を参照します。"
    echo "  別マシンのGPU推論サーバーに接続する場合は、引数でIPを指定してください:"
    echo "  使用例: ./run_production.sh 192.168.1.100 8080 \"青い星に向かう\""
    echo "----------------------------------------------------------------------"
fi

echo "======================================================================"
echo "  [本番実機] LeRobot 4WD リアルタイム非同期制御クライアント"
echo "  推論サーバー: $INFERENCE_SERVER_URL"
echo "  指示タスク: '$PROMPT'"
echo "======================================================================"

# 実行
ruby "$CLIENT_SCRIPT"
