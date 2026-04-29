# Interface/HTTP層 参考実装

## factory.go（Eventドメインの例）

```go
// apps/manage/internal/interface/http/event/factory.go
package factory

import (
	"context"

	eventcontroller "manage/internal/controller/event"
	eventusecase "manage/internal/usecase/event"

	eventdomain "github.com/s-duu-jp/qing/2.backend/common/domain/event"
	eventrepo "github.com/s-duu-jp/qing/2.backend/common/infrastructure/dynamodb/event"
	userrepo "github.com/s-duu-jp/qing/2.backend/common/infrastructure/dynamodb/user"
)

// イベントユースケースを作成します
func NewEventUseCase(ctx context.Context) (eventcontroller.UseCase, error) {
	eventRepository, err := eventrepo.NewDynamoDBEventRepo(ctx)
	if err != nil {
		return nil, err
	}

	userRepository, err := userrepo.NewDynamoDBUserRepo(ctx)
	if err != nil {
		return nil, err
	}

	eventFactory := eventdomain.NewFactory()
	useCase := eventusecase.NewUseCase(eventRepository, userRepository, eventFactory)

	return useCase, nil
}
```

---

## server.go（複数エンドポイント登録）

```go
// apps/manage/internal/interface/http/server.go
package http

import (
	"context"

	authcontroller "manage/internal/controller/auth"
	eventcontroller "manage/internal/controller/event"
	authfactory "manage/internal/interface/http/auth"
	eventfactory "manage/internal/interface/http/event"

	commonhttp "github.com/s-duu-jp/qing/2.backend/common/interface/http"
	commonmiddleware "github.com/s-duu-jp/qing/2.backend/common/interface/http/middleware"

	"github.com/labstack/echo/v4"
)

const (
	BaseURL  = "/api/manage"
	BasePort = "0.0.0.0:3010"
)

// 認証除外パス（認証が不要なエンドポイント）
// 認証必須エンドポイントはここに追加しない
var excludedPaths = []string{
	"/api/manage/auth/login",
	"/api/manage/auth/signup",
	"/api/manage/auth/confirm-signup",
	"/api/manage/auth/refresh",
	"/api/manage/auth/google/url",
	"/api/manage/auth/callback/google",
	"/api/manage/auth/line/url",
	"/api/manage/auth/callback/line",
	"/api/manage/health",
}

func createServerConfig(ctx context.Context) commonhttp.ServerConfig {
	authUseCase, err := authfactory.NewAuthUseCase(ctx)
	if err != nil {
		panic(err)
	}

	eventUseCase, err := eventfactory.NewEventUseCase(ctx)
	if err != nil {
		panic(err)
	}

	return commonhttp.ServerConfig{
		BaseURL: BaseURL,
		Port:    BasePort,
		EndpointRegistrars: []commonhttp.EndpointRegistrar{
			func(g *echo.Group) {
				authcontroller.RegisterHandlers(g, authcontroller.NewAuthController(authUseCase))
			},
			func(g *echo.Group) {
				eventcontroller.RegisterHandlers(g, eventcontroller.NewEventController(eventUseCase))
			},
		},
		AuthMiddleware: commonmiddleware.AuthMiddleware(excludedPaths),
		I18nExcludedPaths: []string{
			// OAuthコールバックは言語Cookieなしで動作する必要がある
			"/api/manage/auth/callback/google",
			"/api/manage/auth/callback/line",
		},
	}
}

func StartServer(ctx context.Context) {
	config := createServerConfig(ctx)
	commonhttp.StartServerWithConfig(ctx, config)
}
```
