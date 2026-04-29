---
name: make-projects-backend
description: Goバックエンドプロジェクトの初期構成を生成するスキル。クリーンアーキテクチャ（Controller/UseCase/Interface/Domain/Infrastructure）のディレクトリ構造、ボイラープレートファイル（main.go・server.go・go.mod・.air.toml・Dockerfile）を一括作成する。「/make-projects-backend」コマンドで呼び出し、新規バックエンドアプリの雛形を作成する場合は必ずこのスキルを使用すること。
user-invocable: true
---

# make-projects-backend: Goバックエンド プロジェクト初期構成

参照アーキテクチャ: `backend-architecture` スキル

## 開始時: タスク登録

スキル開始直後に `TaskCreate` で以下のタスクを登録し、依存関係（`addBlockedBy`）を設定する：

| タスク | subject | activeForm |
|--------|---------|-----------|
| T1 | アプリ名の確認 | アプリ名を確認中 |
| T2 | ディレクトリ構造の生成 | ディレクトリを生成中 |
| T3 | ボイラープレートファイルの生成 | ファイルを生成中 |
| T4 | Hello World REST APIの生成 | APIを生成中 |
| T5 | .gitkeepの配置 | .gitkeepを配置中 |
| T6 | 完了報告 | 完了報告を作成中 |

依存関係: T2はT1完了後、T3はT2完了後、T4はT3完了後、T5はT4完了後、T6はT5完了後。

各STEPの開始前に `TaskUpdate` で `in_progress`、完了後に `completed` にする。

---

## STEP 1: アプリ名の確認

**親スキル（make-projects）から `app_name` と `module_prefix` が渡されている場合は質問せず、そのまま使用する。**

直接呼ばれた場合のみ、以下を質問する：

```
バックエンドアプリ名を教えてください（例: manage, api, admin）
```

回答後、以下を自動決定してユーザーに提示し承認を得る：

| 項目 | 値 | 備考 |
|------|-----|------|
| `app_name` | 入力値 | |
| `module_prefix` | 引き継ぎ値 or 質問 | make-projects-repositoryから引き継いだ値を使用。なければ質問する |
| `port` | `3010` + 既存アプリ数×10 | `backend/apps/` の既存アプリ数を確認して自動計算 |
| `debug_port` | `{port} + 1` | 自動計算 |
| `base_url` | `/api/{app_name}` | 自動生成 |
| `project_root` | `backend` | 固定 |

ユーザーから承認を得たら T1 を `completed` にする。

---

## STEP 2: ディレクトリ構造の生成

以下の構造を `/workspace/{project_root}/` 配下に生成する：

```
{project_root}/
├── apps/
│   └── {app_name}/
│       ├── assets/
│       │   └── locales/
│       ├── cmd/
│       │   └── app/
│       ├── internal/
│       │   ├── controller/
│       │   ├── usecase/
│       │   └── interface/
│       │       └── http/
└── common/                 # 存在しない場合のみ生成
    ├── assets/locales/
    ├── domain/shared/
    ├── helper/
    ├── infrastructure/
    └── interface/http/
```

`common/` が既に存在する場合はスキップする。完了後 T2 を `completed` にする。

---

## STEP 3: ボイラープレートファイルの生成

以下のファイルを生成する。完了後 T3 を `completed` にする。

### `apps/{app_name}/cmd/app/main.go`

```go
package main

import (
	"context"

	"{app_name}/internal/interface/http"
)

var ctx context.Context

func init() {
	ctx = context.Background()
}

func main() {
	http.StartServer(ctx)
}
```

### `apps/{app_name}/internal/interface/http/server.go`

```go
package http

import (
	"context"

	commonhttp "{module_prefix}/{project_root}/common/interface/http"
)

const (
	// APIのベースURL
	BaseURL  = "{base_url}"
	BasePort = "0.0.0.0:{port}"
)

// 認証除外パス（認証が不要なエンドポイント）
var excludedPaths = []string{
	"{base_url}/health",
}

func createServerConfig(ctx context.Context) commonhttp.ServerConfig {
	return commonhttp.ServerConfig{
		BaseURL:            BaseURL,
		Port:               BasePort,
		EndpointRegistrars: []commonhttp.EndpointRegistrar{},
	}
}

func StartServer(ctx context.Context) {
	config := createServerConfig(ctx)
	commonhttp.StartServerWithConfig(ctx, config)
}
```

> **注意**: `commonhttp.ServerConfig` / `commonhttp.StartServerWithConfig` は `common/interface/http/` に別途実装が必要。

### `apps/{app_name}/go.mod`

```
module {app_name}

go 1.24.4

require (
	github.com/labstack/echo/v4 v4.13.3
	{module_prefix}/{project_root}/common v0.0.0
)

replace {module_prefix}/{project_root}/common => ../../common
```

### `apps/{app_name}/.air.toml`

```toml
root = "/workspace/{project_root}"
tmp_dir = "/tmp/backend/{app_name}"

[build]
cmd = "go build -o /tmp/backend/{app_name}/main /workspace/{project_root}/apps/{app_name}/cmd/app && mkdir -p /tmp/backend/{app_name}/common/assets/locales && mkdir -p /tmp/backend/{app_name}/app/assets/locales && cp -r /workspace/{project_root}/common/assets/locales/* /tmp/backend/{app_name}/common/assets/locales/ && cp -r /workspace/{project_root}/apps/{app_name}/assets/locales/* /tmp/backend/{app_name}/app/assets/locales/ 2>/dev/null || true"
bin = "/tmp/backend/{app_name}/main"
full_bin = "sudo netstat -tulpn | grep -E ':({debug_port})' | awk '{print $7}' | cut -d/ -f1 | grep -v '^$' | sort -u | xargs -r sudo kill -9 || true && dlv --listen=:{debug_port} --headless=true --api-version=2 --accept-multiclient --check-go-version=false exec /tmp/backend/{app_name}/main --continue 2>&1 | grep -vE 'layer=(debugger|rpc)'"
include_ext = ["go", "tpl", "tmpl", "html", "json"]
exclude_dir = ["tmp", "apps/{app_name}/tmp", "common/tmp"]
delay = 2000
stop_on_root = false

[log]
time = true

[misc]
clean_on_exit = true
```

### `apps/{app_name}/.golangci.yml`

```yaml
linters:
  enable:
    - errcheck
    - gosimple
    - govet
    - ineffassign
    - staticcheck
    - unused

linters-settings:
  errcheck:
    check-type-assertions: true

issues:
  exclude-rules:
    - path: _test\.go
      linters:
        - errcheck
```

### `apps/{app_name}/Dockerfile`

```dockerfile
FROM golang:1.22-bullseye AS builder

ARG ENV=local

WORKDIR /build

COPY {project_root}/apps/{app_name}/ ./{app_name}/
COPY {project_root}/common/ ./common/

WORKDIR /build/{app_name}
RUN go mod download
RUN CGO_ENABLED=0 GOOS=linux go build -a -ldflags '-s -w -extldflags "-static"' -o app ./cmd/app

FROM gcr.io/distroless/static:nonroot

ARG ENV=local

USER nonroot:nonroot
WORKDIR /app

COPY --from=builder --chown=nonroot:nonroot /build/{app_name}/app .
COPY --from=builder --chown=nonroot:nonroot /build/{app_name}/assets ./app/assets
COPY --from=builder --chown=nonroot:nonroot /build/common/assets ./common/assets

ENV ENV=${ENV}

EXPOSE {port}

ENTRYPOINT ["/app/app"]
```

### `common/go.mod`（common が存在しない場合のみ）

```
module {module_prefix}/{project_root}/common

go 1.24.4

require (
	github.com/labstack/echo/v4 v4.13.3
)
```

---

## STEP 4: Hello World REST API の生成

デフォルトの `GET {base_url}/health` エンドポイントを生成する。完了後 T4 を `completed` にする。

### `apps/{app_name}/internal/controller/health/openapi.yml`

```yaml
openapi: "3.0.0"
info:
  title: Health API
  version: "1.0.0"
paths:
  {base_url}/health:
    get:
      operationId: getHealth
      summary: ヘルスチェック
      responses:
        "200":
          description: OK
          content:
            application/json:
              schema:
                type: object
                properties:
                  status:
                    type: string
                    example: "ok"
```

### `apps/{app_name}/internal/controller/health/controller.go`

```go
package health

import (
	"net/http"

	"github.com/labstack/echo/v4"
)

// RegisterHandlers はヘルスチェックエンドポイントを登録する
func RegisterHandlers(g *echo.Group) {
	g.GET("/health", getHealth)
}

func getHealth(c echo.Context) error {
	return c.JSON(http.StatusOK, map[string]string{"status": "ok"})
}
```

### `server.go` にエンドポイントを登録

`apps/{app_name}/internal/interface/http/server.go` の `EndpointRegistrars` に追加：

```go
import (
	healthcontroller "{app_name}/internal/controller/health"
)

// createServerConfig内
EndpointRegistrars: []commonhttp.EndpointRegistrar{
    func(g *echo.Group) {
        healthcontroller.RegisterHandlers(g)
    },
},
```

> `handler.go`（oapi-codegen自動生成）は `make back-{app_name}-gen-oapi` 実行後に生成する。

---

## STEP 5: .gitkeep の配置

空ディレクトリに `.gitkeep` を配置する。完了後 T5 を `completed` にする。

```
apps/{app_name}/internal/controller/.gitkeep
apps/{app_name}/internal/usecase/.gitkeep
apps/{app_name}/assets/locales/.gitkeep
```

`common/` を新規生成した場合も同様に配置する。

---

## STEP 6: 完了報告

生成したファイル・ディレクトリの一覧をツリー形式で報告し、T6 を `completed` にする。

ユーザーへ次のステップを案内する：

1. `go mod tidy` を実行して依存関係を整理する
   ```bash
   cd /workspace/{project_root}/apps/{app_name} && go mod tidy
   ```
2. `common/interface/http/` に `StartServerWithConfig` 等の共通実装が未存在の場合は別途実装が必要
3. 機能追加時は `backend-implementation-flow` スキルに従って実装する

---

## 重要なルール

- デフォルト値は一切使用しない。未確認の値があれば必ずユーザーに確認する
- `common/` が既に存在する場合は上書きしない
- 生成後にサービスを勝手に起動・再起動しない（`go mod tidy` の実行もユーザーに委ねる）
- `go.sum` はファイルを作成しない（`go mod tidy` 実行時に自動生成される）
