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
  - SmolVLA (450M) モデルを用いた低遅延な非同期推論（FastAPI / Uvicorn による HTTP REST API）
  - 複数走行データのマージおよびファインチューニング学習基盤

---

## ディレクトリ構成

推奨ワークスペース配置:
```text
<ワークスペース>/
├── ruby-teleop-agent/          # 本リポジトリ
│   ├── machine-framework/      # Ruby 実機制御・データ収集クライアント
│   └── Inference-framework/    # Python SmolVLA 学習 & 非同期推論サーバー
├── Lerobot-Dataset-Ruby/       # LeRobot データセット記録・読込 Gem (別リポジトリ)
└── lerobot/                    # Hugging Face LeRobot ソースコード (同階層)
```

- [`machine-framework/`](machine-framework/): Ruby 製実機制御・テレオペデータ収集・自律走行クライアント
- [`Inference-framework/`](Inference-framework/): Python 製 SmolVLA 学習 & 非同期推論サーバー

---

## 前提条件とセットアップ

### 1. Python 推論サーバー側 (`Inference-framework`)

推論サーバーおよび学習の実行には、GPU ホストマシン上に **Conda 仮想環境** の構築が必要です。
公式 LeRobot リポジトリは `ruby-teleop-agent` と同じ親階層に配置して動作します。

```bash
cd Inference-framework

# セットアップスクリプトを実行
# (Python 3.12 の Conda 環境 'lerobot' を作成、同階層の lerobot を自動検出・セットアップ)
chmod +x setup_lerobot_env.sh
./setup_lerobot_env.sh

# (手動で構築する場合)
# conda create -n lerobot python=3.12 -y
# conda activate lerobot
# # ruby-teleop-agent と同階層で: git clone https://github.com/huggingface/lerobot.git
# pip install -e "../../lerobot[dataset,training,smolvla]"
# pip install -r requirements.txt
```

### 2. Ruby 実機/クライアント側 (`machine-framework`)

Raspberry Pi（または検証用 PC）に Ruby および必要なシステムライブラリをインストールし、Gem パッケージを導入します。

#### 📦 コアライブラリ: Lerobot-Dataset-Ruby (Gem)
ロボットカーのデータセット記録・読込および OpenCV 映像キャプチャは、専用 Gem **[`Lerobot-Dataset-Ruby`](https://rubygems.org/gems/Lerobot-Dataset-Ruby)** により提供されています。

- **RubyGems**: [https://rubygems.org/gems/Lerobot-Dataset-Ruby](https://rubygems.org/gems/Lerobot-Dataset-Ruby)  
- **GitHub リポジトリ**: [https://github.com/paisyaluAI/lerobot-dataset-ruby](https://github.com/paisyaluAI/lerobot-dataset-ruby)  

```bash
cd machine-framework

# 依存パッケージのインストール (Debian / Ubuntu / Raspberry Pi OS)
sudo apt-get update
sudo apt-get install -y ruby ruby-dev build-essential libsdl2-dev libopencv-dev libgpiod-dev

# Gem パッケージのインストール (RubyGems から)
gem install ruby-sdl2:0.3.7 parquet:0.9.0 Lerobot-Dataset-Ruby:0.2.1

# ※ ローカルの Lerobot-Dataset-Ruby リポジトリから直接ビルド・インストールする場合:
# cd /path/to/Lerobot-Dataset-Ruby
# gem build Lerobot-Dataset-Ruby.gemspec
# gem install ./Lerobot-Dataset-Ruby-0.2.1.gem

# (本番実機のみ) GPIO C++ 拡張モジュールのビルド
chmod +x build.sh
./build.sh
```

---

## 実行手順

### ステップ 1: Python 推論サーバーの起動

GPU マシン側で推論サーバーを起動します（デフォルト: ポート `8080` で待機）。

```bash
cd Inference-framework

# Conda 環境 (lerobot) を適用して起動
./run_server.sh 0.0.0.0 8080

# ※ 特定の学習済みチェックポイントを指定する場合:
# ./run_server.sh 0.0.0.0 8080 outputs/train/<モデルディレクトリ>/checkpoints/last/pretrained_model cuda
```

### ステップ 2: Ruby クライアントの実行

#### A. 自律走行（VLA 推論実行）
推論サーバーへカメラ映像を送信し、返信されたアクションで車体を自律走行させます。

- **実機 (Raspberry Pi) で走行:**
  ```bash
  cd machine-framework
  PRODUCTION=1 INFERENCE_SERVER_URL=http://<推論サーバーIP>:8080 PROMPT="青い星に向かう" ruby machine_vla.rb
  ```
- **PC 上で Mock 検証:**
  ```bash
  cd machine-framework
  INFERENCE_SERVER_URL=http://127.0.0.1:8080 ruby machine_vla.rb
  ```

#### B. テレオペレーション（学習データ収集）
手動でロボットを操縦し、カメラ映像と走行ログを LeRobotDataset v2 形式で記録します。

```bash
cd machine-framework

# 実機でデータ収集 (ゲームパッド操作)
PRODUCTION=1 PROMPT="青い星に向かう" ruby machine.rb

# Mock 環境でデータ収集テスト (キーボード操作)
ruby machine.rb
```

---

## 詳細ドキュメント

ハードウェア構成、ピン配置、学習コマンド等の詳細については、各ディレクトリの README を参照してください。

- [`machine-framework/README.md`](machine-framework/README.md): GPIO ピンアサイン、コントローラー操作一覧、Mock モード仕様
- [`Inference-framework/README.md`](Inference-framework/README.md): SmolVLA ファインチューニング手順、データセット結合、API 仕様
- [`Lerobot-Dataset-Ruby (Gem)`](https://rubygems.org/gems/Lerobot-Dataset-Ruby): データセット作成/読込・OpenCV C++拡張ライブラリ ([GitHub](https://github.com/paisyaluAI/lerobot-dataset-ruby))
