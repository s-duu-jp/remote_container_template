#!/bin/bash

# nvm初期化（非インタラクティブシェルでもclaudeコマンドを使えるようにする）
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# 作業ディレクトリ
dir="/workspace"

# envファイル初期設定
for env in local stg prod; do
  [ -f "$dir/.env.$env" ] || cp -rp "$dir/.env_example" "$dir/.env.$env"
done

# claudeプラグインのインストール
claude plugins marketplace add anthropics/skills || true
claude plugins install example-skills@anthropic-agent-skills || true

exec bash