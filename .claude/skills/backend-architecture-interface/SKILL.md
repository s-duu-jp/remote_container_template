---
name: backend-architecture-interface
description: バックエンドのInterface/HTTP層実装ガイド。factory.goによる依存性注入、server.goへのエンドポイント登録・excludedPaths（認証除外パス）・I18nExcludedPathsの管理。Interface/HTTP層の実装に関する質問がある場合に使用。
user-invocable: false
---

# バックエンド Interface/HTTP層 実装ガイド

## 概要

`apps/manage/internal/interface/http/` 配下に、依存性注入とサーバー設定を配置する。

```
apps/manage/internal/interface/http/
├── {ドメイン}/
│   └── factory.go  # 依存性注入ファクトリー
└── server.go        # エンドポイント登録・サーバー設定
```

---

## factory.go の作成

**ファイル:** `interface/http/{ドメイン}/factory.go`

```go
package factory

import (
    "context"

    {domain}controller "manage/internal/controller/{domain}"
    {domain}usecase "manage/internal/usecase/{domain}"

    {domain}domain "github.com/s-duu-jp/qing/2.backend/common/domain/{domain}"
    {domain}repo "github.com/s-duu-jp/qing/2.backend/common/infrastructure/dynamodb/{domain}"
)

// {Domain}UseCaseを作成します
func New{Domain}UseCase(ctx context.Context) ({domain}controller.UseCase, error) {
    repo, err := {domain}repo.NewDynamoDB{Domain}Repo(ctx)
    if err != nil {
        return nil, err
    }
    domainFactory := {domain}domain.NewFactory()
    useCase := {domain}usecase.NewUseCase(repo, domainService)
    return useCase, nil
}
```

**ルール:**
- パッケージ名は `factory`
- 戻り値の型は `{domain}controller.UseCase`（具体型ではなくインターフェースを返す）
- リポジトリ・ドメインファクトリの初期化を集約する
- 複数リポジトリが必要な場合は順番に初期化して `NewUseCase` に渡す

---

## server.go への登録

**ファイル:** `interface/http/server.go`

```go
package http

import (
    "context"

    {domain}controller "manage/internal/controller/{domain}"
    {domain}factory "manage/internal/interface/http/{domain}"

    commonhttp "github.com/s-duu-jp/qing/2.backend/common/interface/http"
    commonmiddleware "github.com/s-duu-jp/qing/2.backend/common/interface/http/middleware"

    "github.com/labstack/echo/v4"
)

const (
    BaseURL  = "/api/manage"
    BasePort = "0.0.0.0:3010"
)

// 認証除外パス（認証が不要なエンドポイント）
var excludedPaths = []string{
    "/api/manage/auth/login",
    "/api/manage/auth/signup",
    // ...
}

func createServerConfig(ctx context.Context) commonhttp.ServerConfig {
    {domain}UseCase, err := {domain}factory.New{Domain}UseCase(ctx)
    if err != nil {
        panic(err)
    }

    return commonhttp.ServerConfig{
        BaseURL: BaseURL,
        Port:    BasePort,
        EndpointRegistrars: []commonhttp.EndpointRegistrar{
            func(g *echo.Group) {
                {domain}controller.RegisterHandlers(g, {domain}controller.New{Domain}Controller({domain}UseCase))
            },
        },
        AuthMiddleware: commonmiddleware.AuthMiddleware(excludedPaths),
        I18nExcludedPaths: []string{
            // 言語Cookieなしで動作すべきパス（OAuthコールバック等）
        },
    }
}

func StartServer(ctx context.Context) {
    config := createServerConfig(ctx)
    commonhttp.StartServerWithConfig(ctx, config)
}
```

---

## excludedPaths のルール

| 追加するもの | 追加しないもの |
|-------------|--------------|
| ログイン・サインアップ | 認証必須エンドポイント |
| パスワードリセット系 | 通常のAPIエンドポイント |
| OAuthコールバック | ユーザー操作が必要なAPI |
| ヘルスチェック | |

認証必須エンドポイントは `excludedPaths` に追加しない（middlewareが自動で保護する）。

---

## I18nExcludedPaths のルール

言語Cookieなしで動作する必要があるパスを指定する。
OAuthコールバックは外部サービス（Google/LINE）からのリダイレクトのため、言語Cookieが存在しない。

```go
I18nExcludedPaths: []string{
    "/api/manage/auth/callback/google",
    "/api/manage/auth/callback/line",
},
```

## 参考実装

詳細なコード例は `reference.md` を参照。
