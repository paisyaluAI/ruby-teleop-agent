#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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