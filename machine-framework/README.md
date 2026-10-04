# Paisyalu-AI: 4WDロボットカー 実機 & Mock 制御クライアント

[![Gem Version](https://badge.fury.io/rb/Lerobot-Dataset-Ruby.svg)](https://rubygems.org/gems/Lerobot-Dataset-Ruby)
[![Ruby](https://img.shields.io/badge/Ruby-3.x-red.svg)](https://www.ruby-lang.org/)
[![SDL2](https://img.shields.io/badge/Library-SDL2-blue.svg)](https://www.libsdl.org/)
[![OpenCV](https://img.shields.io/badge/OpenCV-C%2B%2B%20Ext-brightgreen.svg)](https://opencv.org/)
[![Raspberry Pi](https://img.shields.io/badge/Platform-Raspberry%20Pi-c51a4a.svg)](https://www.raspberrypi.com/)
[![LeRobot Compatible](https://img.shields.io/badge/Format-LeRobotDataset%20v2-yellow.svg)](https://github.com/huggingface/lerobot)
[![License: MIT](https://img.shields.io/badge/License-MIT-purple.svg)](LICENSE)

Raspberry Pi 搭載 4輪駆動ロボットカー向けの **Ruby 制御クライアントシステム** です。  
カメラ映像とモーター制御をリアルタイムに扱い、**「手動テレオペレーション（データ収集）」** と **「SmolVLA モデルによる自律走行（推論実行）」** の両方に対応します。

また、実機ハードウェアを持たないローカル PC 上でも開発・動作検証ができる **Mock モード** を標準搭載しています。

---

## 目次
- [システムアーキテクチャ](#システムアーキテクチャ)
- [プログラムの役割分担](#プログラムの役割分担)
- [実機モードと Mock モードの比較](#実機モードと-mock-モードの比較)
- [ディレクトリ・ファイル構成](#ディレクトリファイル構成)
- [前提要件とセットアップ](#前提要件とセットアップ)
- [1. VLA 自律走行の実行 (`machine_vla.rb`)](#1-vla-自律走行の実行-machine_vlarb)
  - [A. 本番実機モード (Raspberry Pi)](#a-本番実機モード-raspberry-pi)
  - [B. Mock 検証モード (開発 PC)](#b-mock-検証モード-開発-pc)
  - [非同期通信クライアント (VLAAsyncClient) の仕組み](#非同期通信クライアント-vlaasyncclient-の仕組み)
- [2. テレオペレーション・データ収集の実行 (`machine.rb`)](#2-テレオペレーションデータ収集の実行-machinerb)
  - [操作方法一覧](#操作方法一覧)
  - [出力データセットの構造](#出力データセットの構造)
- [3. 記録データのリプレイ再生 (`player.rb`)](#3-記録データのリプレイ再生-playerrb)
- [パラメータ・環境変数一覧と公式出典](#パラメータ環境変数一覧と公式出典)
- [ハードウェア構成と GPIO ピンアサイン](#ハードウェア構成と-gpio-ピンアサイン)
- [トラブルシューティング](#トラブルシューティング)

---

## システムアーキテクチャ

本システムは、GPU ホストサーバー上の [VLA-Learning](../VLA-Learning) と HTTP REST API（Keep-Alive）経由で通信を行いながら、10 FPS (100ms 周期) の安定した制御ループを実現します。

```mermaid
flowchart LR
    subgraph ClientSide["クライアント側 (machine)"]
        direction TB
        subgraph HardwareInput["入力ソース"]
            Cam["カメラ映像<br>(/dev/video0 または test.mp4)"]
            State["現在速度<br>[-1.0, 1.0]"]
        end

        subgraph CoreLoop["制御ループ (10 FPS)"]
            Main["machine_vla.rb<br>(メイン走行ループ)"]
            Client["VLAAsyncClient<br>(非同期ワーカースレッド)"]
            Queue[("Action Queue<br>(先行受信キュー)")]
            Main <-->|キュー監視 & 取得| Queue
            Client -->|推論結果を追加| Queue
        end

        subgraph HardwareOutput["出力先"]
            Motor["左右モータードライバ<br>(GPIO または コンソール)"]
        end

        Cam & State -->|最新観測| Client
        Main -->|確定制御値| Motor
    end

    subgraph ServerSide["推論サーバー側 (VLA-Learning)"]
        Server["lerobot_async_server.py<br>(FastAPI / Uvicorn)"]
        Model["SmolVLA Policy<br>(450M パラメータ)"]
        Server <--> Model
    end

    Client <-->|HTTP POST /predict<br>(画像 Base64 + State + Prompt)| Server
```

---

## プログラムの役割分担

| プログラム | 役割 | 制御方式 | 操作・終了方法 |
| :--- | :--- | :--- | :--- |
| **[`machine_vla.rb`](machine_vla.rb)** | **VLA 自律走行**<br>（SmolVLA モデル推論による自動走行） | 推論サーバーから受け取った `action_chunk` を順次タイヤへ反映 | ・起動で走行開始<br>・`Ctrl + C` で安全停止 |
| **[`machine.rb`](machine.rb)** | **テレオペレーション**<br>（手動操縦 ＆ 学習データ収集） | ゲームパッド / キーボードで車体を操縦し、映像と制御値を記録 | ・コントローラー操作（開始・保存・破棄）<br>・終了時に LeRobotDataset v2 を自動出力 |
| **[`player.rb`](player.rb)** | **エピソードリプレイ**<br>（記録データの再生検証） | 保存した Parquet データを読み込み、記録された速度で実機/Mockを再現駆動 | ・`ruby player.rb <DATASET_DIR>` |

---

## 実機モードと Mock モードの比較

環境変数 `PRODUCTION=1` の有無によって、実機ハードウェアとダミーモックが自動的に切り替わります。コードの書き換えは不要です。

| 項目 | 本番実機モード (`PRODUCTION=1`) | Mock モード (未設定 / デフォルト) |
| :--- | :--- | :--- |
| **カメラ映像** | 物理 Web カメラ (`/dev/video0`, 640x480) | ダミー動画（黒画面） ([`test/dummy_video.mp4`](test/dummy_video.mp4) または自動生成） |
| **モーター駆動** | Raspberry Pi GPIO 出力 ([`tire.rb`](tire.rb), `libgpiod`) | ターミナルログ出力 ([`tire_mock.rb`](tire_mock.rb)) |
| **コントローラー** | 実機ゲームパッド ([`controller.rb`](controller.rb), SDL2) | キーボード入力 ([`controller_mock.rb`](controller_mock.rb)) |
| **推論通信** | リモート GPU サーバーへの HTTP 通信 | ローカル/リモート GPU サーバーへの HTTP 通信（同一クライアント使用） |
| **制御周波数** | 10 FPS (100ms 周期) | 10 FPS (100ms 周期) |

---

## ディレクトリ・ファイル構成

```
machine-framework/
├── README.md                   # 本ドキュメント
├── machine_vla.rb              # VLA 自律走行メインスクリプト
├── machine.rb                  # テレオペレーション & 学習データセット収集スクリプト
├── player.rb                   # 記録したデータセットのエピソード再生（リプレイ）スクリプト
├── server_send.rb              # machine_vla.rb のエイリアス起動スクリプト
├── lerobot_client_wrapper.rb   # HTTP 非同期推論クライアント (VLAAsyncClient)
├── run_production.sh           # Raspberry Pi 実機用 本番起動シェルスクリプト
├── run_mock_test.sh            # ローカル PC 向け Mock 検証スクリプト (サーバー自動連動)
├── build.sh                    # Raspberry Pi 実機用 GPIO C++ 拡張モジュールのビルドスクリプト
├── verify_dataset.sh           # データセット整合性テストスクリプト
├── tire.rb                     # 本番用モーター制御 (libgpiod C拡張連携)
├── tire_mock.rb                # Mock 用ダミーモーター制御
├── controller.rb               # 本番用ゲームパッド入力 (SDL2 Joystick)
├── controller_mock.rb          # Mock 用キーボード入力 (SDL2 Keyboard Event)
├── ext/                        # C/C++ 拡張モジュール
│   └── gpio/                   # libgpiod 連携拡張ソース (extconf.rb, libgpiod_ext.cpp)
├── output_dataset/             # データ収集時にエピソードが保存されるディレクトリ (git無視)
└── test/                       # Mock 用ダミー動画 (dummy_video.mp4), テストスクリプト
```

---

## 前提要件とセットアップ

### 必要な環境
- **OS**: Raspberry Pi OS (Debian系) または Linux (Ubuntu 20.04/22.04/24.04 LTS)
- **Ruby**: 3.0 以上
- **システムライブラリ**:
  ```bash
  sudo apt-get update
  sudo apt-get install -y ruby-dev build-essential libsdl2-dev libopencv-dev libgpiod-dev
  ```
- **Ruby Gem**:
  本クライアントは、データセット処理および映像キャプチャに専用 Gem **[`Lerobot-Dataset-Ruby`](https://rubygems.org/gems/Lerobot-Dataset-Ruby)** を利用しています。
  - **RubyGems**: [https://rubygems.org/gems/Lerobot-Dataset-Ruby](https://rubygems.org/gems/Lerobot-Dataset-Ruby)
  - **GitHub**: [https://github.com/paisyaluAI/lerobot-dataset-ruby](https://github.com/paisyaluAI/lerobot-dataset-ruby)
  ```bash
  gem install ruby-sdl2:0.3.7 parquet:0.9.0 Lerobot-Dataset-Ruby:0.2.0
  ```
  *(※ OpenCV C++ 拡張およびデータセット Writer/Reader は `Lerobot-Dataset-Ruby` Gem に統合されています)*

### 実機用 GPIO 拡張のビルド (本番実機のみ)
Raspberry Pi 実機のモータードライバを制御するため、GPIO C++ 拡張を使用しています。
実機で実行する前に [`build.sh`](build.sh) を実行してコンパイルしてください（Mockモードのみで動かす場合は不要です）。

```bash
# ※ プロジェクトルートから実行する場合は cd machine-framework してください
chmod +x build.sh run_production.sh run_mock_test.sh
./build.sh
```

---

## 1. VLA 自律走行の実行 (`machine_vla.rb`)

推論サーバーから予測されたアクション（左右モーター制御値）を受け取り、車体を自律走行させます。

### A. 本番実機モード (Raspberry Pi)
推論サーバーが動作しているホストマシンの IP アドレス、ポート番号、指示タスクを指定して起動します。

```bash
# 起動スクリプトを使用 (推奨): ./run_production.sh <サーバーIP> <ポート> "<タスク指示>"
./run_production.sh <INFERENCE_SERVER_IP> 8080 "青い星に向かう"

# または環境変数で直接実行
PRODUCTION=1 INFERENCE_SERVER_URL=http://<INFERENCE_SERVER_IP>:8080 PROMPT="青い星に向かう" ruby machine_vla.rb
```

### B. Mock 検証モード (開発 PC)
推論サーバーと Mock クライアントを同時に起動してテストできます。カメラや実機ロボットは不要です。

```bash
# 起動スクリプト (推論サーバーが未起動なら自動起動します)
./run_mock_test.sh "青い星に向かう"

# 推論サーバーがすでに起動済みの場合は直接起動
ruby machine_vla.rb
```

> **安全停止方法**:  
> 走行中にコンソールで `Ctrl + C` を押すと、フェイルセーフが作動して左右モーターが即座に `0.0`（停止）になり、GPIO ピンが安全に解放されます。

---

### 非同期通信クライアント (VLAAsyncClient) の仕組み

[`lerobot_client_wrapper.rb`](lerobot_client_wrapper.rb) 内の `VLAAsyncClient` は、走行の連続性を維持するために以下のアーキテクチャを採用しています。

1. **メインスレッド (10 FPS)**:
   - カメラからフレームを取得し、現在のモーター値とともにクライアントへ渡します。
   - `next_action` をノンブロッキングで呼び出し、キューの先頭から次の `[left, right]` を取り出してタイヤを動かします。
2. **ワーカースレッド (バックグラウンド)**:
   - アクションキューの残数が **1 ステップ以下** になると、最新の観測画像・状態・プロンプトを用いてサーバーへ推論リクエスト（`POST /predict`）を送信します。
   - 受信した 10 ステップの計画（Action Chunk）をキューの末尾に追加します。
3. **フェイルセーフ**:
   - ネットワーク一時切断などでキューが完全に枯渇した場合、直ちに左右モーターを `0.0` にして安全停止します。

---

## 2. テレオペレーション・データ収集の実行 (`machine.rb`)

手動操縦を行いながら、車載カメラの映像、左右モーター制御値（`[-1.0, 1.0]`）、自然言語タスク指示を **LeRobotDataset v2** 準拠フォーマットで記録します。

```bash
# 実機でデータ収集 (ゲームパッド操作)
PRODUCTION=1 PROMPT="青い星に向かう" ruby machine.rb

# Mock環境でデータ収集の動作確認 (キーボード操作)
ruby machine.rb
```

### 操作方法一覧

| 操作 | 本番実機 (ゲームパッド) | Mock (キーボード) | 動作説明 |
| :--- | :--- | :--- | :--- |
| **左タイヤ前進 / 後退** | 左スティック Y軸 (`LEFTY`) | `W` / `S` | 左モーター速度を `-1.0` 〜 `1.0` で入力 |
| **右タイヤ前進 / 後退** | 右スティック Y軸 (`RIGHTY`) | `↑` / `↓` | 右モーター速度を `-1.0` 〜 `1.0` で入力 |
| **エピソード記録開始** | `START` ボタン | `T` キー | 新しいエピソードの録画を開始します |
| **エピソード保存 & 一時停止** | `BACK` ボタン | `F` キー | 現在のエピソードを Parquet/MP4 にコミット保存し、待機状態に戻ります |
| **エピソード破棄 & 一時停止** | 十字キー下 (`DPAD_DOWN`) | `G` キー | 失敗した走行エピソードを保存せずに破棄します |
| **セッション終了 & 完全保存** | `GUIDE` (Home) ボタン | `E` キー | 全エピソードを確定保存し、プログラムを終了します |

---

### 出力データセットの構造

データは `output_dataset/<YYYYMMDD_HHMM>`（Mock 時は `output_dataset/mock_<YYYYMMDD_HHMM>`）に自動保存されます。  
そのまま [Inference-framework](../Inference-framework) の `data/` 配下に転送して学習に使用できます。

```
output_dataset/<YYYYMMDD_HHMM>/
├── meta/
│   ├── info.json              # 特徴量定義、FPS、バージョン情報
│   ├── stats.json             # action, state の平均/最大/最小値
│   ├── tasks.parquet          # 記録されたタスクプロンプト一覧
│   └── episodes/chunk-000/    # エピソードメタデータ
├── data/chunk-000/            # action, state, timestamp 等の Parquet
└── videos/rgb/chunk-000/      # H.264 / MP4 形式の同期録画映像
```

---

## 3. 記録データのリプレイ再生 (`player.rb`)

記録したデータセットが正しく保存されているか、どのような走行軌道を描くかを実機や Mock で再現テストできます。

```bash
# 基本実行: ruby player.rb <データセットパス> [エピソード番号]
ruby player.rb output_dataset/<YYYYMMDD_HHMM> 0

# 実機で再生する場合
PRODUCTION=1 ruby player.rb output_dataset/<YYYYMMDD_HHMM> 0
```

---

## パラメータ・環境変数一覧と公式出典

各スクリプトで利用可能な環境変数およびパラメータ一覧です。

| 環境変数 / 設定項目 | デフォルト値 | 説明 | 公式ドキュメント・出典 |
| :--- | :--- | :--- | :--- |
| `PRODUCTION` | `0` (Mock) | `1` を指定すると実機モード（GPIO, 実カメラ, ゲームパッド）で動作。未指定または `0` で Mock モード。 | - |
| `INFERENCE_SERVER_URL` | `http://127.0.0.1:8080` | 推論サーバーのベース URL。`ws://` 形式で指定された場合も自動で `http://` に正規化されます。 | [FastAPI / HTTP](https://fastapi.tiangolo.com/) |
| `PROMPT` | `"Go to the blue star"` | ロボットに指示する自然言語タスク文字列。SmolVLA モデルへ条件付け入力として送られます。 | [SmolVLA Model Card](https://huggingface.co/lerobot/smolvla_base) |
| `CREATE_STEPS` | `10` | 推論サーバーに要求する生成アクションステップ数（10ステップ = 10 FPS で 1秒分）。 | [LeRobot Policy Inference](https://github.com/huggingface/lerobot) |
| `EXEC_STEPS` | `10` | クライアントが実際に実行キューに投入する先頭ステップ数。 | - |
| `TARGET_FPS` | `10` | 制御およびデータ収集の目標フレームレート（100ms 周期）。 | [LeRobot Dataset Specs](https://huggingface.co/docs/lerobot/en/datasets) |

### 関連公式リソース
- **Lerobot-Dataset-Ruby Gem**: [RubyGems ページ](https://rubygems.org/gems/Lerobot-Dataset-Ruby) / [GitHub リポジトリ](https://github.com/paisyaluAI/lerobot-dataset-ruby)
- **Ruby SDL2 バインディング**: [ruby-sdl2 Documentation](https://github.com/ohai/ruby-sdl2) / [Simple DirectMedia Layer (SDL2)](https://www.libsdl.org/)
- **Linux GPIO キャラクターデバイス (libgpiod)**: [libgpiod Kernel Docs](https://git.kernel.org/pub/scm/libs/libgpiod/libgpiod.git/)
- **OpenCV**: [OpenCV Official Site](https://opencv.org/)
- **LeRobot データセット仕様**: [Hugging Face LeRobot Datasets Format](https://huggingface.co/docs/lerobot/en/datasets)

---

## ハードウェア構成と GPIO ピンアサイン

本番実機モード（[`tire.rb`](tire.rb)）では、Raspberry Pi の GPIO コントローラ `/dev/gpiochip0` を介してモータードライバを制御します。

| モーター側 | 動作方向 | Raspberry Pi GPIO ピン (BCM) | 備考 |
| :--- | :--- | :--- | :--- |
| **左モーター** | 前進 (`forward`) | **GPIO 12** | デッドゾーン: `0.05` |
| **左モーター** | 後退 (`back`) | **GPIO 16** | 同時オン禁止 (インターロック保護) |
| **右モーター** | 前進 (`forward`) | **GPIO 20** | デッドゾーン: `0.05` |
| **右モーター** | 後退 (`back`) | **GPIO 21** | 同時オン禁止 (インターロック保護) |

---

## トラブルシューティング

### Q1. 推論サーバーへの接続に失敗する (`推論サーバーに接続できませんでした`)
- **原因**: サーバーが起動していない、または IP アドレス・ポートが誤っている。
- **対処法**:
  1. ホスト側で `./run_server.sh 0.0.0.0 8080` が実行中であることを確認してください。
  2. Raspberry Pi 側から `curl http://<INFERENCE_SERVER_IP>:8080/health` を実行し、`{"status":"ok"}` が返るか確認してください。
  3. ホストマシンのファイアウォール（`ufw` 等）でポート 8080 が許可されているか確認してください。

### Q2. カメラが開けない (`cam_open failed`)
- **原因**: カメラデバイス `/dev/video0` が存在しない、または他のプロセスが占有している。
- **対処法**:
  - `ls -l /dev/video*` でデバイスが認識されているか確認してください。
  - ユーザーが `video` グループに所属しているか確認してください（`sudo usermod -aG video $USER`）。

### Q3. ゲームコントローラーが反応しない
- **原因**: SDL2 でジョイスティックデバイスが認識されていない。
- **対処法**:
  - コントローラーが USB または Bluetooth で正しくペアリングされているか確認してください。
  - `ls -l /dev/input/js*` を確認してください。
