#!/bin/bash
# ホスト用 Claude 認証ファイル
mkdir -p ~/.claude && touch ~/.claude/.credentials.json && touch ~/.claude.json
# devcontainer 用 Claude ディレクトリ
mkdir -p ~/.claude_XXXXX && cp -p ~/.claude/.credentials.json ~/.claude_XXXXX/.credentials.json
