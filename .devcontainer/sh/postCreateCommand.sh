#!/bin/bash

# 作業ディレクトリ
dir="/workspace"

# .env.dev ファイルが存在しない場合は作成して初期値を設定
if [ ! -f ${dir}/.env.dev ]; then
  echo 'ENV="development"' > ${dir}/.env.dev
fi

# .env.stg ファイルが存在しない場合は作成して初期値を設定
if [ ! -f ${dir}/.env.stg ]; then
  echo 'ENV="staging"' > ${dir}/.env.stg
fi

# .env.prod ファイルが存在しない場合は作成して初期値を設定
if [ ! -f ${dir}/.env.prod ]; then
  echo 'ENV="production"' > ${dir}/.env.prod
fi
