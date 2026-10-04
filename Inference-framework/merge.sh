#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ -z "${CONDA_DEFAULT_ENV:-}" ] || [ "${CONDA_DEFAULT_ENV}" != "lerobot" ]; then
  CONDA_PROFILE="${CONDA_BASE:-$HOME/miniforge3}/etc/profile.d/conda.sh"
  if [ -f "$CONDA_PROFILE" ]; then
    source "$CONDA_PROFILE"
    conda activate lerobot
  elif command -v conda >/dev/null 2>&1; then
    eval "$(conda shell.bash hook)"
    conda activate lerobot
  fi
fi

# lerobot ディレクトリの探索 (ruby-teleop-agent と同階層を優先)
if [ -z "${LEROBOT_DIR:-}" ]; then
  for candidate in \
    "$(cd "$SCRIPT_DIR/../.." && pwd)/lerobot" \
    "$(cd "$SCRIPT_DIR/.." && pwd)/lerobot" \
    "$SCRIPT_DIR/lerobot" \
    "$(cd "$SCRIPT_DIR/../.." && pwd)/VLA-Learning/lerobot"; do
    if [ -d "$candidate/src" ]; then
      export LEROBOT_DIR="$candidate"
      export PYTHONPATH="$LEROBOT_DIR/src${PYTHONPATH:+:$PYTHONPATH}"
      break
    fi
  done
elif [ -d "$LEROBOT_DIR/src" ]; then
  export PYTHONPATH="$LEROBOT_DIR/src${PYTHONPATH:+:$PYTHONPATH}"
fi

BASE_DIR="${BASE_DIR:-$SCRIPT_DIR/data}"
NEW_REPO_ID="${BASE_DIR}/merged"

# BASE_DIR 直下のサブディレクトリ一覧を取得
mapfile -t all_dirs < <(find "$BASE_DIR" -mindepth 1 -maxdepth 1 -type d | sort)

# yyyymmdd_hhmm 形式のディレクトリのみをフィルタ
dirs=()
for d in "${all_dirs[@]}"; do
  name=$(basename "$d")
  # 正規表現: 8桁_4桁 のみマッチ
  if [[ "$name" =~ ^[0-9]{8}_[0-9]{4}$ ]]; then
    dirs+=("$d")
  fi
done

# 対象が0個の場合はエラーにして止める（必要なければこのブロックは削除可）
if [ "${#dirs[@]}" -eq 0 ]; then
  echo "Error: yyyymmdd_hhmm 形式のディレクトリが ${BASE_DIR} に見つかりませんでした。" >&2
  exit 1
fi

# Python 風のリスト文字列を構築: ['/path/a', '/path/b', ...]
repo_ids="["
first=true
for d in "${dirs[@]}"; do
  if [ "$first" = true ]; then
    first=false
  else
    repo_ids+=", "
  fi
  repo_ids+="'$d'"
done
repo_ids+="]"
echo "Merging the following directories: $repo_ids"

lerobot-edit-dataset \
  --new_repo_id "$NEW_REPO_ID" \
  --operation.type merge \
  --operation.repo_ids "$repo_ids"