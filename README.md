# ruby-teleop-agent

[![Gem Version](https://badge.fury.io/rb/Lerobot-Dataset-Ruby.svg)](https://rubygems.org/gems/Lerobot-Dataset-Ruby)
[![Ruby](https://img.shields.io/badge/Ruby-3.2+-red.svg)](https://www.ruby-lang.org/)
[![Python](https://img.shields.io/badge/Python-3.12-blue.svg)](https://www.python.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-purple.svg)](LICENSE)

Ruby で実機（4WD ロボットカー）を制御し、Python 側の推論サーバー（SmolVLA / LeRobot）と HTTP 通信を行うことで、リアルタイム推論による自律走行および学習データ収集を実現するシステムです。

---

## 全体概要

- **実機制御 / クライアント側 (`machine-framework`)**: **Ruby**
  - Raspberry Pi 搭載の実機（GPIO、カメラ、ゲームパッド）の制御
  - テレオペレーション（手動操縦）による LeRobotDataset v2 形式の学習データ収集
  - 推論サーバーから予測アクション（左右モーター速度）を非同期受信して自律走行
  - 実機なしで動作確認できる Mock モード対応
- **推論サーバー側 (`Inference-framework`)**: **Python**
  - SmolVLA (450M) または ACT モデルを用いた低遅延な非同期推論（FastAPI / Uvicorn による HTTP REST API、`ACT_MODE=1` で ACT 切替）
  - 複数走行データのマージおよびファインチューニング学習基盤

---

## ディレクトリ構成

推奨ワークスペース配置:
```text
robot-stack/
├── .venv/                          # Python 共通仮想環境 (uv 管理: LeRobot / 推論サーバー / 学習)
├── pyproject.toml                  # Python 依存パッケージ定義 (uv)
├── apps/ruby-teleop-agent/         # 本リポジトリ (Ruby クライアント + Python 推論サーバー)
├── libraries/Lerobot-Dataset-Ruby/ # Dataset記録・読込Gem (独立した Ruby Gem 環境)
├── training/VLA-Learning/          # 学習・推論環境 (共通 .venv 利用)
└── third_party/lerobot/            # Hugging Face LeRobot (Editable インストール)
```

- [`machine-framework/`](machine-framework/): Ruby 製実機制御・テレオペデータ収集・自律走行クライアント
- [`Inference-framework/`](Inference-framework/): Python 製 SmolVLA 学習 & 非同期推論サーバー（共通 `robot-stack/.venv` を利用）

---

## 前提条件とセットアップ

### 1. Python 推論サーバー側 (`Inference-framework`)

推論サーバーおよび学習の実行には、ワークスペース共通の **uv 仮想環境 (`robot-stack/.venv`)** を利用します（既存の Conda 環境は廃止し、`uv` に統合しました）。
公式 LeRobot リポジトリは `robot-stack/third_party/lerobot` に配置します。

```bash
# 方法A: robot-stack ルートで uv sync を実行 (推奨)
cd /path/to/robot-stack
uv sync

# 方法B: Inference-framework のセットアップスクリプトを実行
# (Python 3.12 の共通仮想環境 robot-stack/.venv を作成・同期し、third_party/lerobot をセットアップ)
cd apps/ruby-teleop-agent/Inference-framework
chmod +x setup_lerobot_env.sh
./setup_lerobot_env.sh

# (手動で uv pip により構築する場合)
# cd /path/to/robot-stack
# uv venv .venv --python 3.12
# source .venv/bin/activate
# uv pip install -e "third_party/lerobot[dataset,training,smolvla]"
# uv pip install -r apps/ruby-teleop-agent/Inference-framework/requirements.txt
```

### 2. Ruby 実機/クライアント側 (`machine-framework`)

Raspberry Pi（または検証用 PC）に Ruby および必要なシステムライブラリをインストールし、Gem パッケージを導入します。

#### 📦 コアライブラリ: Lerobot-Dataset-Ruby (Gem)
ロボットカーのデータセット記録・読込および OpenCV 映像キャプチャは、専用 Gem **[`Lerobot-Dataset-Ruby`](https://rubygems.org/gems/Lerobot-Dataset-Ruby)** により提供されています。

- **RubyGems**: [https://rubygems.org/gems/Lerobot-Dataset-Ruby](https://rubygems.org/gems/Lerobot-Dataset-Ruby)  
- **GitHub リポジトリ**: [https://github.com/paisyaluAI/lerobot-dataset-ruby](https://github.com/paisyaluAI/lerobot-dataset-ruby)  

```bash
# 1. 依存ライブラリのインストール (システム全体に導入されるため任意のディレクトリで実行可能)
sudo apt-get update
sudo apt-get install -y ruby ruby-dev build-essential libsdl2-dev libopencv-dev libgpiod-dev

# 2. Gem パッケージのインストール (RubyGems から)
gem install ruby-sdl2:0.3.7 parquet:0.9.0 Lerobot-Dataset-Ruby:0.2.1

# ※ ローカルの Lerobot-Dataset-Ruby リポジトリから直接ビルド・インストールする場合:
# cd ../../libraries/Lerobot-Dataset-Ruby
# gem build Lerobot-Dataset-Ruby.gemspec
# gem install ./Lerobot-Dataset-Ruby-*.gem

# 3. machine-framework へ移動して実機用モジュールをビルド (本番実機のみ)
cd machine-framework
chmod +x build.sh
./build.sh
```

---

## 実行手順 (全体の流れ)

本システムは、**「①データ収集 → ②モデル学習 → ③推論サーバー起動 & 自律走行」** の流れで動作します。

```text
[1. テレオペ操縦]                [2. 学習 (GPU)]                 [3. 自律走行]
実機 / Mock 走行                収集データをマージ              推論サーバー起動
     ↓                               ↓                              ↓
LeRobotDataset 収集  ────→  SmolVLA ファインチューニング ────→ カメラ映像から自律走行
(machine-framework)         (Inference-framework)         (推論 ⇔ 実機制御)
```

### ステップ 1: データ収集（テレオペレーション）

まずは実機（または Mock 環境）でロボットを手動操縦し、学習用の走行データセット（カメラ映像 + 操縦ログ）を記録します。

```bash
cd machine-framework

# 実機でデータ収集 (ゲームパッド操作、カメラ映像と走行ログを記録)
PRODUCTION=1 PROMPT="青い星に向かう" ruby machine.rb

# Mock 環境でデータ収集テスト (キーボード操作)
ruby machine.rb
```
※ 走行データは `machine-framework/output_dataset/<YYYYMMDD_HHMM>/` に自動保存されます。

---

### ステップ 2: データセット準備とモデル学習 (SmolVLA)

自律走行を行うには、事前に収集したデータセットで SmolVLA モデルを学習（ファインチューニング）する必要があります。

1. **データセットの配置:**  
   収集したデータセットディレクトリを `Inference-framework/data/` 配下に配置します。
   ```bash
   mkdir -p Inference-framework/data
   cp -r machine-framework/output_dataset/<YYYYMMDD_HHMM> Inference-framework/data/
   ```

2. **データセットのマージ (複数回走行データがある場合):**  
   [`merge.sh`](Inference-framework/merge.sh) を実行すると、`data/` 配下の走行データを結合して `data/merged` を作成します。
   ```bash
   cd Inference-framework
   ./merge.sh
   ```

3. **モデル学習の実行 (GPU マシン):**  
   [`learning.sh`](Inference-framework/learning.sh) を実行して SmolVLA ベースモデルをファインチューニングします。
   ```bash
   cd Inference-framework
   ./learning.sh data/merged
   ```
   ※ 学習チェックポイントは `outputs/train/<セッション名>/` に保存され、最新モデルは `checkpoints/last/pretrained_model` に自動配置されます。

---

### ステップ 3: Python 推論サーバーの起動

学習したチェックポイントをロードして推論サーバーを起動します（デフォルト: ポート `8080` で待機）。

```bash
cd Inference-framework

# 最新の学習モデルを自動ロードして起動 (SmolVLA)
./run_server.sh 0.0.0.0 8080

# ACT モデルで起動する場合
# ACT_MODE=1 ./run_server.sh 0.0.0.0 8080

# ※ 特定のチェックポイントを指定して起動する場合:
# ./run_server.sh 0.0.0.0 8080 outputs/train/<セッション名>/checkpoints/last/pretrained_model cuda
```

---

### ステップ 4: Ruby クライアントによる自律走行（VLA 推論実行）

推論サーバーへカメラ映像をリアルタイム送信し、返信された予測アクションで車体を自律走行させます。

- **実機 (Raspberry Pi) で自律走行:**
  ```bash
  cd machine-framework
  PRODUCTION=1 INFERENCE_SERVER_URL=http://<推論サーバーIP>:8080 PROMPT="青い星に向かう" ruby machine_vla.rb
  # 非同期先読みモードを使う場合:
  # ASYNC_PREFETCH=1 PRODUCTION=1 INFERENCE_SERVER_URL=http://<推論サーバーIP>:8080 PROMPT="青い星に向かう" ruby machine_vla.rb
  ```

- **PC 上で Mock 検証 (実機なし):**
  ```bash
  cd machine-framework
  INFERENCE_SERVER_URL=http://127.0.0.1:8080 ruby machine_vla.rb
  # 非同期先読みモード: ruby machine_vla.rb --async
  ```

> [!TIP]
> **ワンコマンドでのローカル Mock 検証**  
> 学習済みモデルがある場合、[`run_mock_test.sh`](machine-framework/run_mock_test.sh) を実行すると推論サーバーのバックグラウンド起動と Mock 自律走行クライアントの起動を一度に行えます：
> ```bash
> cd machine-framework
> ./run_mock_test.sh "青い星に向かう"
> # ACT サーバーを使う場合: ACT_MODE=1 ./run_mock_test.sh
> ```

---

## 詳細ドキュメント

ハードウェア構成、ピン配置、学習コマンド等の詳細については、各ディレクトリの README を参照してください。

- [`machine-framework/README.md`](machine-framework/README.md): GPIO ピンアサイン、コントローラー操作一覧、Mock モード仕様
- [`Inference-framework/README.md`](Inference-framework/README.md): SmolVLA ファインチューニング手順、データセット結合、API 仕様
- [`Lerobot-Dataset-Ruby (Gem)`](https://rubygems.org/gems/Lerobot-Dataset-Ruby): データセット作成/読込・OpenCV C++拡張ライブラリ ([GitHub](https://github.com/paisyaluAI/lerobot-dataset-ruby))
