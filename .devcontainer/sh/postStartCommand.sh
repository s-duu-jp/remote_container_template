#!/bin/bash

# 作業ディレクトリ
dir="/workspace"

# envファイル初期設定
for env in local stg prod; do
  [ -f "$dir/.env.$env" ] || cp -rp "$dir/.env_example" "$dir/.env.$env"
done

exec bash