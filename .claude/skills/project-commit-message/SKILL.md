---
name: project-commit-message
description: コミットメッセージの作成ガイド。Conventional Commits形式・1行のみ（body/footer/Co-Authored-By禁止）、type/scope一覧、日本語記述ルール。コミットメッセージに関する質問がある場合に使用。
user-invocable: false
---

# コミットメッセージガイド

## 形式

```
<type>(<scope>): <subject>
```

- **必ず1行のみ**。body（本文）・footer・`Co-Authored-By` 等は一切付けない
- **100文字以内**
- **日本語**で記述する

## type 一覧

| type       | 用途                                   |
| ---------- | -------------------------------------- |
| `feat`     | 新機能の実装                           |
| `fix`      | バグ修正                               |
| `refactor` | リファクタリング（動作変更なし）       |
| `docs`     | ドキュメントのみの変更                 |
| `chore`    | ビルド・CI・依存関係などの雑務         |
| `test`     | テストの追加・修正                     |
| `style`    | フォーマットのみの変更（動作変更なし） |

## scope 一覧

scopeにはアプリ名または機能領域を入れる。

| scope      | 用途                            |
| ---------- | ------------------------------- |
| `infra`    | インフラ（Terraform、Docker等） |
| `backend`  | バックエンド                    |
| `frontend` | フロントエンド                  |
| `auth`     | 認証関連（アプリをまたぐ場合）  |
| `ci`       | CI/CD                           |

## 記述例

```
feat(infra): CognitoにLINE OIDCプロバイダーを追加する
feat(backend): LINEログインAPIを実装する
feat(frontend): LINEログイン画面を実装する
fix(backend): ログイン後のリダイレクト失敗を修正する
refactor(frontend): 認証フックを整理する
chore(ci): GitHub Actionsのデプロイワークフローを追加する
```

## ルール

- subjectは動詞で終わる（「〜を実装する」「〜を修正する」）
- 過去形禁止（「実装した」→「実装する」）
- 句点（。）不要
- 1コミット = 1つの目的（複数の変更をまとめない）
- **プロダクト単位（infra / backend / frontend）でコミットを分ける**（STEP.6のプロダクト単位ブランチに対応）

## 実行例

```bash
git commit -m "feat(backend): LINEログインAPIを実装する"
```

**禁止例**（複数行・footer付与）:

```bash
# ❌ これは絶対にしない
git commit -m "$(cat <<'EOF'
feat(backend): LINEログインAPIを実装する

詳細な本文...

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```
