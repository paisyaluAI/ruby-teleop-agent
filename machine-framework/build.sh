#!/usr/bin/env bash
set -e

# ==============================================================================
# build.sh
# Raspberry Pi 実機用 GPIO C++ 拡張モジュール (ext/gpio) のビルド
# (※ OpenCV C++ 拡張は Lerobot-Dataset-Ruby gem に同梱されています)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/ext/gpio"

if [ -f Makefile ]; then
  make clean || true
fi

echo "[build.sh] ext/gpio/libgpiod_ext のビルドを開始します..."
ruby extconf.rb
make
echo "[build.sh] ext/gpio/libgpiod_ext.so のビルドが完了しました。"