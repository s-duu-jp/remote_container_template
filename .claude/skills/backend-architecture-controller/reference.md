# Controller層 参考実装

## Event Controller（シンプルなパターン）

### openapi.yml

```yaml
openapi: 3.0.3
info:
  title: event API
  version: 1.0.0
servers:
  - url: http://localhost:3010/api/manage
    description: ローカル開発サーバー
paths:
  /event:
    post:
      summary: イベントを取得または作成します
      operationId: postEvent
      tags:
        - event
      security:
        - cookieAuth: []
      requestBody:
        required: false
        content:
          application/json:
            schema:
              $ref: "#/components/schemas/PostEventRequest"
      responses:
        "200":
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/PostEventResponse"
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
    PostEventRequest:
      type: object
      properties:
        event_id:
          type: string
          description: 取得対象のイベントID（省略時は最新イベントを返すか新規作成）
          example: "01ARZ3NDEKTSV4RRFFQ69G5FAV"
    PostEventResponse:
      type: object
      properties:
        event_id:
          type: string
          description: イベントID（ULID形式）
          example: "01ARZ3NDEKTSV4RRFFQ69G5FAV"
        created_at:
          type: string
          format: date-time
          description: イベント作成日時（RFC3339形式）
          example: "2024-01-01T00:00:00Z"
      required:
        - event_id
        - created_at
    ErrorResponse:
      type: object
      properties:
        error:
          type: string
      required:
        - error
```

---

### controller.go

```go
package controller

import (
	"context"
	"net/http"

	"github.com/labstack/echo/v4"
	"github.com/s-duu-jp/qing/2.backend/common/helper"
	eventusecase "manage/internal/usecase/event"
)

// イベントユースケースのインターフェース
type UseCase interface {
	GetOrCreateEvent(ctx context.Context, sub string, eventID *string) (*eventusecase.Res, error)
}

// イベントコントローラの実装
type controller struct {
	uc UseCase
}

// EventControllerのコンストラクタ
func NewEventController(uc UseCase) ServerInterface {
	return &controller{uc: uc}
}

// イベントを取得または作成します
func (c *controller) PostEvent(ctx echo.Context) error {
	// ミドルウェアで設定されたsubを取得
	subValue := ctx.Get("sub")
	if subValue == nil {
		return ctx.JSON(http.StatusUnauthorized, ErrorResponse{
			Error: helper.GetMessage(ctx.Request().Context(), "controller.event.PostEvent.subNotFound"),
		})
	}

	sub, ok := subValue.(string)
	if !ok {
		return ctx.JSON(http.StatusInternalServerError, ErrorResponse{
			Error: helper.GetMessage(ctx.Request().Context(), "controller.event.PostEvent.subTypeCastFailed"),
		})
	}

	// リクエストボディのバインド（オプション）
	var req PostEventJSONRequestBody
	if err := ctx.Bind(&req); err != nil {
		return ctx.JSON(http.StatusBadRequest, ErrorResponse{Error: err.Error()})
	}

	// UseCaseを呼び出してイベントを取得または作成
	res, err := c.uc.GetOrCreateEvent(ctx.Request().Context(), sub, req.EventId)
	if err != nil {
		return ctx.JSON(http.StatusInternalServerError, ErrorResponse{Error: err.Error()})
	}

	return ctx.JSON(http.StatusOK, PostEventResponse{
		EventId:   res.EventID,
		CreatedAt: res.CreatedAt,
	})
}
```

---

### oapi-codegen 生成物（handler.go）の構造

```
生成されるもの:
- スキーマ型 (PostEventRequest, PostEventResponse, ErrorResponse 等)
- ServerInterface インターフェース
  → operationId: postEvent → メソッド名: PostEvent(ctx echo.Context) error
- ServerInterfaceWrapper 構造体
- RegisterHandlers / RegisterHandlersWithBaseURL 関数
```

**コード生成コマンド:**
```bash
make back-manage-gen-oapi
```

`internal/` 配下のすべての `openapi.yml` を検索して `handler.go` を生成する。
パッケージ名は常に `controller`（ディレクトリ名に関わらず固定）。

---

### 翻訳キー（controller セクション例）

```json
{
  "controller": {
    "event": {
      "PostEvent": {
        "subNotFound": "認証情報が見つかりません",
        "subTypeCastFailed": "認証情報の型変換に失敗しました"
      }
    },
    "auth": {
      "Me": {
        "userIdNotFound": "ユーザーIDが見つかりません",
        "userIdTypeCastFailed": "ユーザーIDの型変換に失敗しました"
      },
      "PostRefresh": {
        "refreshTokenNotFound": "リフレッシュトークンが見つかりません"
      },
      "GetGoogleUrl": {
        "urlGenerationFailed": "Google認証URLの生成に失敗しました"
      }
    }
  }
}
```
