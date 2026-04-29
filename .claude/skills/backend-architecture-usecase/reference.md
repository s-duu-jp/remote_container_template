# UseCase層 参考実装

## Event UseCase（シンプルなパターン）

### usecase.go

```go
package event

import (
	"context"
	"errors"

	"github.com/s-duu-jp/qing/2.backend/common/domain/event"
	"github.com/s-duu-jp/qing/2.backend/common/domain/shared"
	"github.com/s-duu-jp/qing/2.backend/common/domain/user"
	"github.com/s-duu-jp/qing/2.backend/common/helper"
)

// イベントリポジトリのインターフェース
type eventRepository interface {
	FindLatestByUserSub(ctx context.Context, sub string) (*event.Entity, error)
	GetByID(ctx context.Context, sub string, eventID string) (*event.Entity, error)
	Create(ctx context.Context, entity event.Entity) error
}

// ユーザーリポジトリのインターフェース（createdBy取得用）
type userRepository interface {
	FindBySub(ctx context.Context, sub string) (*user.Entity, error)
}

// イベントドメインファクトリのインターフェース
type eventFactory interface {
	Create(sub string, createdBy shared.UserID) event.Entity
}

// イベント関連のユースケース
type useCase struct {
	eventRepo   eventRepository
	userRepo    userRepository
	eventFactory eventFactory
}

// 新しいEventUseCaseインスタンスを生成
func NewUseCase(eventRepo eventRepository, userRepo userRepository, eventFactory eventFactory) *useCase {
	return &useCase{
		eventRepo:   eventRepo,
		userRepo:    userRepo,
		eventFactory: eventFactory,
	}
}

// イベントを取得または作成する
// eventIDが指定された場合: 指定IDのイベントを取得（存在しなければエラー）
// eventIDがない場合: 最新イベントを取得し、存在しなければ新規作成して返す
func (uc *useCase) GetOrCreateEvent(ctx context.Context, sub string, eventID *string) (*Res, error) {
	if eventID != nil {
		// 指定されたEventIDでイベントを検索
		entity, err := uc.eventRepo.GetByID(ctx, sub, *eventID)
		if err != nil {
			return nil, err
		}
		if entity == nil {
			return nil, errors.New(helper.GetMessage(ctx, "usecase.event.GetOrCreateEvent.notFound"))
		}
		return &Res{
			EventID:   entity.EventID.Value(),
			CreatedAt: entity.CreatedAt,
		}, nil
	}

	// 最新のイベントを検索
	entity, err := uc.eventRepo.FindLatestByUserSub(ctx, sub)
	if err != nil {
		return nil, err
	}

	// 存在しない場合は新規作成
	if entity == nil {
		// ユーザー情報を取得してcreatedByに設定
		userEntity, err := uc.userRepo.FindBySub(ctx, sub)
		if err != nil {
			return nil, err
		}
		if userEntity == nil {
			return nil, errors.New(helper.GetMessage(ctx, "usecase.event.GetOrCreateEvent.userNotFound"))
		}

		newEntity := uc.eventFactory.Create(sub, userEntity.UID)
		if err := uc.eventRepo.Create(ctx, newEntity); err != nil {
			return nil, err
		}
		entity = &newEntity
	}

	return &Res{
		EventID:   entity.EventID.Value(),
		CreatedAt: entity.CreatedAt,
	}, nil
}
```

### types.go

```go
package event

import "time"

// GetOrCreateEvent の結果を表す
type Res struct {
	EventID   string    // イベントID（ULID文字列）
	CreatedAt time.Time // イベント作成日時
}
```

---

## Auth UseCase（依存が多い場合のグループ化パターン）

### usecase.go（依存定義部分）

```go
package auth

// リポジトリインターフェースをまとめた構造体
type repositories struct {
	auth authRepository
	ses  sesRepository
	user userRepository
}

// アプリケーションサービスをまとめた構造体
type services struct {
	auth authService
}

// ドメインファクトリをまとめた構造体
type factories struct {
	user userFactory
}

// 認証関連のユースケース
type useCase struct {
	services services
	repos    repositories
	factories factories
}

func NewUseCase(authService authService, authRepo authRepository, sesRepo sesRepository, userRepo userRepository, userFactory userFactory) (*useCase, error) {
	return &useCase{
		services: services{auth: authService},
		repos:    repositories{auth: authRepo, ses: sesRepo, user: userRepo},
		factories: factories{user: userFactory},
	}, nil
}
```

### types.go（複合型パターン）

```go
package auth

import "time"

// アクセストークンとリフレッシュトークンのペアを表します
type Token struct {
	AccessToken  string
	RefreshToken string
}

// ログイン処理の結果を表します
type Res struct {
	Token  *Token
	Claims *TokenClaims
}

// JWTトークンのペイロード部分を表す構造体
type TokenClaims struct {
	Iss      string `json:"iss"`
	Sub      string `json:"sub"`
	ClientID string `json:"client_id"`
	TokenUse string `json:"token_use"`
	Exp      int64  `json:"exp"`
}

// Googleコールバック処理の結果を表します
type CallbackGoogleResult struct {
	Res         *Res   // 通常ログインレスポンス（リンク時はnil）
	Linked      bool   // アカウントリンクが実行されたか
	LinkedEmail string // リンク時のメールアドレス（リンク時のみ設定）
}
```

---

## Factory パターン

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
	// イベントリポジトリの初期化
	eventRepository, err := eventrepo.NewDynamoDBEventRepo(ctx)
	if err != nil {
		return nil, err
	}

	// ユーザーリポジトリの初期化（createdBy取得用）
	userRepository, err := userrepo.NewDynamoDBUserRepo(ctx)
	if err != nil {
		return nil, err
	}

	// イベントドメインファクトリの初期化
	eventFactory := eventdomain.NewFactory()

	// イベントユースケースの初期化
	useCase := eventusecase.NewUseCase(eventRepository, userRepository, eventFactory)

	return useCase, nil
}
```

---

## 翻訳キー（apps/manage/assets/locales/ja.json の usecase セクション例）

```json
{
  "usecase": {
    "auth": {
      "SignUp": {
        "emailAlreadyRegistered": "既に登録済みのメールアドレスです"
      },
      "Me": {
        "userNotFound": "ユーザーが見つかりません"
      },
      "Refresh": {
        "userVerificationFailed": "ユーザーの確認に失敗しました",
        "userDisabled": "このアカウントは無効化されています",
        "userUnconfirmed": "アカウントが未確認です"
      }
    },
    "event": {
      "GetOrCreateEvent": {
        "notFound": "指定されたイベントが見つかりません",
        "userNotFound": "ユーザーが見つかりません"
      }
    }
  }
}
```

---

## Controller側のUseCaseインターフェース定義

UseCaseインターフェースはController層（`controller.go`）に定義する。
これによりController→UseCase方向の依存を明示する。

```go
// apps/manage/internal/controller/event/controller.go
package controller

import (
	"context"
	eventusecase "manage/internal/usecase/event"
)

// イベントユースケースのインターフェース
type UseCase interface {
	GetOrCreateEvent(ctx context.Context, sub string, eventID *string) (*eventusecase.Res, error)
}

type controller struct {
	uc UseCase
}

func NewEventController(uc UseCase) ServerInterface {
	return &controller{uc: uc}
}
```

---

## server.goへの組み込み

```go
// apps/manage/internal/interface/http/server.go
func createServerConfig(ctx context.Context) commonhttp.ServerConfig {
	eventUseCase, err := eventfactory.NewEventUseCase(ctx)
	if err != nil {
		panic(err)
	}

	return commonhttp.ServerConfig{
		EndpointRegistrars: []commonhttp.EndpointRegistrar{
			func(g *echo.Group) {
				eventcontroller.RegisterHandlers(g, eventcontroller.NewEventController(eventUseCase))
			},
		},
	}
}
```
