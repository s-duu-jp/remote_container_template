#!/bin/bash

# 作業ディレクトリ
dir="/workspace"

# envファイル初期設定
declare -A envs=( ["dev"]="development" ["stg"]="staging" ["prod"]="production" )
for env in "${!envs[@]}"; do
  [ -f "$dir/.env.$env" ] || cp -rp "$dir/.env_example" "$dir/.env.$env"
done