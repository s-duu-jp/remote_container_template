---
name: make-projects-repository
description: 新規プロジェクトのGitHubリポジトリを作成し、ローカルと紐付けて初期pushまで行うスキル。make-projectsの最初のステップとして必ず呼び出される。
user-invocable: false
---

# make-projects-repository: GitHubリポジトリ作成

## 開始時: タスク登録

スキル開始直後に `TaskCreate` で以下の4つのタスクを登録し、依存関係（`addBlockedBy`）を設定する：

| タスク | subject                | activeForm             |
| ------ | ---------------------- | ---------------------- |
| T1     | プロジェクト名の確認   | プロジェクト名を確認中 |
| T2     | GitHubリポジトリを作成 | リポジトリを作成中     |
| T3     | ローカルと紐付け       | リモートを設定中       |
| T4     | 初期push               | pushを実行中           |

依存関係: T2 は T1 が完了後、T3 は T2 が完了後、T4 は T3 が完了後に開始。

各STEPの開始前に `TaskUpdate` で `in_progress`、完了後に `completed` にする。

---

## STEP 1: プロジェクト名の確認

**親スキル（make-projects）から `project_name` と公開設定が渡されている場合は質問せず、そのまま使用する。**

直接呼ばれた場合のみ、以下を質問する：

```
プロジェクト名を教えてください（例: my-project, awesome-api）
※ GitHubリポジトリ名になります（小文字・ハイフン区切り推奨）
※ 公開リポジトリにしたい場合は「public」と一緒にどうぞ。指定なしは非公開になります
```

回答を受け取ったら以下を自動取得・決定し、ユーザーに提示して承認を得る：

```bash
gh api user --jq .login  # オーナー名を取得
```

| 項目           | 値                                        |
| -------------- | ----------------------------------------- |
| リポジトリ名   | `{project_name}`                          |
| 公開設定       | 指定があれば `public`、なければ `private` |
| GitHubオーナー | 取得した値                                |
| module_prefix  | `github.com/{owner}/{project_name}`       |
| ローカルパス   | `/workspace`                              |

ユーザーから承認を得たら T1 を `completed` にして次へ進む。

---

## STEP 2: GitHubリポジトリを作成

```bash
# privateの場合
gh repo create {project_name} --private

# publicの場合
gh repo create {project_name} --public
```

作成後、表示されたリポジトリURLをユーザーに伝え、T2 を `completed` にする。

---

## STEP 3: ローカルと紐付け

まず現在の状態を確認する：

```bash
git remote -v
```

結果に応じて分岐する：

**originが存在しない・git未初期化の場合：**

```bash
git init  # 未初期化の場合のみ
git remote add origin git@github.com:{owner}/{project_name}.git
```

**originが既に存在する場合（差し替え）：**

```bash
git remote set-url origin git@github.com:{owner}/{project_name}.git
```

`git remote -v` で設定を確認し、T3 を `completed` にする。

---

## STEP 4: 初期push

```bash
git add .
git commit -m "feat: プロジェクト初期構成"
git branch -M main
git push -u origin main
```

pushが成功したら T4 を `completed` にする。

---

## 完了後

以下の情報を次のスキルに引き継ぐ：

| 項目            | 値                                  |
| --------------- | ----------------------------------- |
| `project_name`  | `{project_name}`                    |
| `owner`         | `{owner}`                           |
| `module_prefix` | `github.com/{owner}/{project_name}` |
