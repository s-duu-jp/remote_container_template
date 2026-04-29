---
name: backend-architecture-controller
description: バックエンドのController層実装ガイド。openapi.ymlの定義方法、oapi-codegenによるhandler.go自動生成、controller.goの構造（UseCaseインターフェース定義・ハンドラー実装・subの取得）。Controller層の実装に関する質問がある場合に使用。
user-invocable: false
---

# バックエンド Controller層 実装ガイド

## 概要

`apps/{アプリ名}/internal/controller/{ドメイン}/` 配下に、HTTPハンドラーとOpenAPI定義を配置する。

```
apps/{アプリ名}/internal/controller/{ドメイン}/
├── openapi.yml    # OpenAPI定義（手書き）
├── handler.go     # oapi-codegenで自動生成（編集禁止）
└── controller.go  # UseCaseインターフェース定義 + ハンドラー実装
```

## 🚨 Controller層の絶対ルール

| 禁止 | 理由 |
|------|------|
| リポジトリへの直接アクセス | UseCase層を経由すること |
| Redisへの直接アクセス | UseCase層を経由すること |
| ビジネスロジックの実装 | UseCase層に委譲すること |
| Service層の直接呼び出し | 必ずUseCase経由 |
| `os.Getenv` の直接参照 | factory で Config を注入（詳細は「Config 注入」） |
| `err.Error() == helper.GetMessage(...)` による分岐 | UseCase で sentinel エラーを定義し `errors.Is` で判別する（詳細は「エラーハンドリング」） |
| `ctx.Get("sub")` の直接参照 | `middleware.AuthSub(ctx)` ヘルパーを使う（詳細は「認証コンテキストの取得」） |
| デフォルト値フォールバック | オプショナル値は `*int` / `*bool` などポインタで受け取り、未指定時は UseCase 側でバリデーションエラー |
| inline JSON の `fmt.Fprintf` 直接書き込み（SSE） | `sse_event.go` に書き出しヘルパーを分離 |

**SSEアプリも例外なし。** SSEの場合、Controller層の責務は以下のみ：
- SSEヘッダー設定（`text/event-stream` 等）
- `http.Flusher` の取得・イベントループ（HTTP処理）
- `sse_event.go` のヘルパー呼び出しと `flusher.Flush()`（payload 組立は別ファイルに分離）

---

## Step 1: openapi.yml を作成

**ファイル:** `controller/{ドメイン}/openapi.yml`

```yaml
openapi: 3.0.3
info:
  title: {ドメイン} API
  version: 1.0.0
servers:
  - url: http://localhost:3010/api/manage
    description: ローカル開発サーバー
paths:
  /{ドメイン}:
    post:
      summary: {操作の説明}
      operationId: post{Domain}    # キャメルケース → ハンドラーメソッド名
      tags:
        - {ドメイン}
      security:
        - cookieAuth: []           # 認証必須の場合のみ付ける
      requestBody:
        required: false
        content:
          application/json:
            schema:
              $ref: "#/components/schemas/Post{Domain}Request"
      responses:
        "200":
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/Post{Domain}Response"
        "401":
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/ErrorResponse"
        "500":
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/ErrorResponse"
components:
  securitySchemes:
    cookieAuth:
      type: apiKey
      in: header
      name: Cookie
  schemas:
    ErrorResponse:
      type: object
      properties:
        error:
          type: string
      required:
        - error
```

**ルール:**
- `operationId` がハンドラーメソッド名（キャメルケース）になる
  - `postEvent` → `PostEvent(ctx echo.Context) error`
  - `getUser` → `GetUser(ctx echo.Context) error`
- 認証必須エンドポイントは `security: - cookieAuth: []` を付ける
- 認証不要エンドポイントは `security` を省略し、server.go の `excludedPaths` に追加する

---

## Step 2: コード生成

```bash
make back-manage-gen-oapi
```

`controller/{ドメイン}/handler.go` が自動生成される。生成物：

| 生成物 | 説明 |
|--------|------|
| スキーマ型 | `Post{Domain}Request`, `Post{Domain}Response`, `ErrorResponse` 等 |
| `ServerInterface` | operationId に対応するメソッド群 |
| `RegisterHandlers` | ルート登録関数 |

**注意: `handler.go` は手動編集禁止（再生成で上書きされる）**

---

## Step 3: controller.go を作成

```go
package controller

import (
    "context"
    "errors"
    "net/http"

    "github.com/labstack/echo/v4"
    "github.com/s-duu-jp/qing/2.backend/common/helper"
    "github.com/s-duu-jp/qing/2.backend/common/interface/http/middleware"
    {domain}usecase "{アプリ名}/internal/usecase/{domain}"
)

// UseCaseインターフェース（Controller層に定義）
type UseCase interface {
    {Method}(ctx context.Context, ...) (*{domain}usecase.Res, error)
}

// controller構造体（非公開）
type controller struct {
    uc UseCase
}

// コンストラクタ（ServerInterfaceを返す）
func New{Domain}Controller(uc UseCase) ServerInterface {
    return &controller{uc: uc}
}

// ハンドラー実装（operationIdに対応）
func (c *controller) Post{Domain}(ctx echo.Context) error {
    reqCtx := ctx.Request().Context()

    // 認証済みユーザーの sub を取得（middleware.AuthSub で集約）
    sub, err := middleware.AuthSub(ctx)
    if err != nil {
        if errors.Is(err, middleware.ErrSubNotFound) {
            return ctx.JSON(http.StatusUnauthorized, ErrorResponse{
                Error: helper.GetMessage(reqCtx, "controller.{domain}.Post{Domain}.subNotFound"),
            })
        }
        return ctx.JSON(http.StatusInternalServerError, ErrorResponse{
            Error: helper.GetMessage(reqCtx, "controller.{domain}.Post{Domain}.subTypeCastFailed"),
        })
    }

    // リクエストボディのバインド
    var req Post{Domain}JSONRequestBody
    if err := ctx.Bind(&req); err != nil {
        return ctx.JSON(http.StatusBadRequest, ErrorResponse{Error: err.Error()})
    }

    // UseCaseを呼び出し（ビジネスロジックはすべてUseCaseに委譲）
    res, err := c.uc.{Method}(reqCtx, sub, ...)
    if err != nil {
        // 区別可能なエラーは sentinel + errors.Is で判定し HTTP ステータスを決定する
        switch {
        case errors.Is(err, {domain}usecase.ErrNotFound):
            return ctx.JSON(http.StatusNotFound, ErrorResponse{
                Error: helper.GetMessage(reqCtx, "usecase.{domain}.{Method}.notFound"),
            })
        case errors.Is(err, {domain}usecase.ErrInvalid):
            return ctx.JSON(http.StatusBadRequest, ErrorResponse{
                Error: helper.GetMessage(reqCtx, "usecase.{domain}.{Method}.invalid"),
            })
        }
        return ctx.JSON(http.StatusInternalServerError, ErrorResponse{Error: err.Error()})
    }

    return ctx.JSON(http.StatusOK, Post{Domain}Response{...})
}
```

**ルール:**
- `UseCase` インターフェースは Controller層（`controller.go`）に定義する
- `controller` 構造体は非公開（小文字）
- コンストラクタは `ServerInterface` を返す
- sub の取得: `middleware.AuthSub(ctx)` ヘルパーを使う（`ctx.Get("sub")` 直接参照は禁止）
- **リポジトリ・Redisを `controller` 構造体のフィールドに持たせない**

---

## 📖 認証コンテキストの取得

Controller 層で認証済みユーザーの情報にアクセスする場合、**必ず `common/interface/http/middleware/` のヘルパーを経由する**。`ctx.Get("sub")` の直接参照は禁止。

```go
import "github.com/s-duu-jp/qing/2.backend/common/interface/http/middleware"

// sub を取得（未認証 / 型不一致は sentinel エラー）
sub, err := middleware.AuthSub(ctx)
if err != nil {
    if errors.Is(err, middleware.ErrSubNotFound) { ... } // 401
    // 型不一致 → 500
}

// ログインプロバイダー（shared.Provider 値オブジェクト）
provider := middleware.AuthLoginProvider(ctx)

// ローカル認証の有無
hasLocalAuth := middleware.AuthHasLocalAuth(ctx)
```

提供ヘルパー:
- `AuthSub(ctx) (string, error)` — sub。エラーは `ErrSubNotFound` / `ErrSubTypeCastFailed`
- `AuthLoginProvider(ctx) shared.Provider` — プロバイダー種別（キーなし・型不一致は `ProviderLocal`）
- `AuthHasLocalAuth(ctx) bool` — ローカル認証の有無

---

## 📖 エラーハンドリング（sentinel + errors.Is）

UseCase 層の区別可能なエラーは **sentinel エラー**として定義し、Controller 側で `errors.Is` で判定して HTTP ステータスと翻訳キーを決定する。

### 禁止パターン

```go
// ❌ 絶対禁止: 翻訳文字列比較はアンチパターン
if err.Error() == helper.GetMessage(ctx, "usecase.x.y.notFound") {
    return ctx.JSON(http.StatusNotFound, ...)
}
```

翻訳が変更されると動作が壊れる・言語依存で動作が分岐するため禁止。

### 正しいパターン

UseCase 層:
```go
var (
    ErrEventNotFound = errors.New("event not found")
    ErrInvalidStatus = errors.New("invalid status transition")
)

func (uc *useCase) RemoveEvent(...) error {
    if entity == nil {
        return ErrEventNotFound
    }
    ...
}
```

Controller 層:
```go
if err := c.uc.RemoveEvent(reqCtx, sub, eventId); err != nil {
    switch {
    case errors.Is(err, eventusecase.ErrEventNotFound):
        return ctx.JSON(http.StatusNotFound, ErrorResponse{
            Error: helper.GetMessage(reqCtx, "usecase.event.RemoveEvent.notFound"),
        })
    case errors.Is(err, eventusecase.ErrInvalidStatus):
        return ctx.JSON(http.StatusBadRequest, ErrorResponse{
            Error: helper.GetMessage(reqCtx, "usecase.event.RemoveEvent.invalidStatus"),
        })
    }
    return ctx.JSON(http.StatusInternalServerError, ErrorResponse{Error: err.Error()})
}
```

翻訳キーの解決は Controller 側（i18n 責務は境界で処理）。UseCase の sentinel は identifier 英語文字列のみ。

---

## 📖 Config 注入（os.Getenv 禁止）

Controller 層から `os.Getenv` の直接参照は**禁止**。環境変数に依存する設定（Cookie 属性・フロントエンド URL など）は factory で読み取り、Config 構造体として注入する。

### パターン

Controller 内:
```go
// Cookie 属性を環境依存で切り替える Config（Controller 層に定義）
type CookieConfig struct {
    IsSecure         bool
    Domain           string
    SameSite         http.SameSite
    FrontendOwnerURL string
}

type controller struct {
    uc     UseCase
    cookie CookieConfig
}

func NewXxxController(uc UseCase, cookie CookieConfig) ServerInterface {
    return &controller{uc: uc, cookie: cookie}
}
```

factory:
```go
func NewXxxController(ctx context.Context) (xxxcontroller.ServerInterface, error) {
    uc, err := NewXxxUseCase(ctx)
    if err != nil { return nil, err }
    cookie, err := buildCookieConfig()
    if err != nil { return nil, err }
    return xxxcontroller.NewXxxController(uc, cookie), nil
}

func buildCookieConfig() (xxxcontroller.CookieConfig, error) {
    env, err := helper.MustEnv("ENV")
    if err != nil { return xxxcontroller.CookieConfig{}, err }
    // ... 必要な環境変数を読む（未設定は error 返却・デフォルト値フォールバック禁止）
}
```

Cookie 発行は共通ヘルパーに集約:
```go
func (c *controller) setCookie(ctx echo.Context, name, value string, maxAge int, httpOnly bool) {
    ctx.SetCookie(&http.Cookie{
        Name: name, Value: value, Path: "/",
        Domain: c.cookie.Domain, MaxAge: maxAge,
        Secure: c.cookie.IsSecure, HttpOnly: httpOnly, SameSite: c.cookie.SameSite,
    })
}
```

---

## 📖 オプショナル入力の扱い（デフォルト値フォールバック禁止）

OpenAPI の optional フィールドを Controller で「nil なら既定値」に変換するのは**禁止**。値は **ポインタのまま UseCase に渡し、UseCase 側でバリデーションエラーにする**。

```go
// ❌ 禁止: Controller でのデフォルト値フォールバック
interval := 3
if req.LanguageCycleInterval != nil {
    interval = *req.LanguageCycleInterval
}

// ✅ 推奨: *int のまま UseCase へ
languageCycle = &xxxusecase.LanguageCyclePatchParams{
    Enabled:  *req.LanguageCycleEnabled,
    Interval: req.LanguageCycleInterval, // *int
}
```

UseCase 側で nil を sentinel エラーで拒否:
```go
if params.Interval == nil {
    return ErrInvalidLanguageCycleInterval
}
if *params.Interval < 3 || *params.Interval > 5 {
    return ErrInvalidLanguageCycleInterval
}
```

---

## 📖 SSE Controller の payload 組立分離

SSE Controller では `fmt.Fprintf` / `json.Marshal` の直接記述を**禁止**。SSE イベント書き出しは `sse_event.go` に分離する。

### ディレクトリ構成

```
apps/{sseアプリ}/internal/controller/{ドメイン}/
├── openapi.yml
├── handler.go       # 自動生成
├── controller.go    # SSEヘッダー設定・イベントループ・Flush だけを担う
└── sse_event.go     # payload 型 + 書き出しヘルパー
```

### sse_event.go の例

```go
package controller

import (
    "encoding/json"
    "fmt"
    "io"
)

// Redis から受信する JSON のユニオン型
type queueChannelPayload struct {
    Type    string `json:"type"`
    EntryID string `json:"entry_id"`
    // ...
}

// Redis メッセージを SSE イベントとして書き出す
func writeQueueSSEEvent(w io.Writer, msg string) bool {
    var payload queueChannelPayload
    if err := json.Unmarshal([]byte(msg), &payload); err != nil || payload.Type == "" {
        return false
    }
    event, ok := buildQueueSSEEvent(payload)
    if !ok { return false }
    fmt.Fprintf(w, "data: %s\n\n", event)
    return true
}

// payload → SSE イベント JSON バイト列に変換
func buildQueueSSEEvent(payload queueChannelPayload) ([]byte, bool) {
    switch payload.Type {
    case "new_entry":
        b, err := json.Marshal(map[string]string{"type": "new_entry", "entry_id": payload.EntryID})
        if err != nil { return nil, false }
        return b, true
    // ...
    default:
        return nil, false
    }
}

// シンプルなイベント（connected / ping 等）は個別ヘルパーに分ける
func writeConnectedEvent(w io.Writer, entryID string) { ... }
func writePingEvent(w io.Writer) { ... }
```

### Controller 側の責務

```go
case msg, ok := <-msgCh:
    if !ok { return nil }
    if writeQueueSSEEvent(w, msg) {
        flusher.Flush()
    }
case <-ticker.C:
    writePingEvent(w)
    flusher.Flush()
```

Controller は「ストリーム書き出しヘルパーの呼び出し + `flusher.Flush()`」のみ。payload 形式の知識は Controller から完全に排除する。

---

## 翻訳キーの命名規則

```
controller.{ドメイン名}.{ハンドラーメソッド名}.{エラー種別}
```

例:
- `controller.event.PostEvent.subNotFound`
- `controller.event.PostEvent.subTypeCastFailed`
- `controller.auth.Me.userIdNotFound`

翻訳ファイル: `apps/{アプリ名}/assets/locales/{ja,en}.json` の `controller` セクション

```json
{
  "controller": {
    "{ドメイン}": {
      "Post{Domain}": {
        "subNotFound": "認証情報が見つかりません",
        "subTypeCastFailed": "認証情報の型変換に失敗しました"
      }
    }
  }
}
```

## 参考実装

詳細なコード例は `reference.md` を参照。
