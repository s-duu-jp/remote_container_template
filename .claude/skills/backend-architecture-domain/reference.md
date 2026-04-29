# ドメイン層 実装リファレンス

## Userドメインの実装例

### entity.go

```go
package user

import "github.com/s-duu-jp/qing/2.backend/common/domain/shared"

type Entity struct {
    Sub               shared.Sub      // ユーザー内部ID(Cognitoのsub)
    UID               shared.UserID   // ユーザー外部ID
    UserName          shared.UserName // ユーザー名
    Email             shared.Email    // メールアドレス
    Role              shared.Role     // ユーザー権限
    Settings          Config          // ユーザー設定（Config Value Object）
    shared.TimeStamps                 // 共通タイムスタンプ情報
}

type Config struct {
    Account struct {
        NewsSub bool // ニュース購読
    }
}
```

### factory.go

```go
package user

import "github.com/s-duu-jp/qing/2.backend/common/domain/shared"

type factory struct{}

func NewFactory() factory { return factory{} }

// すべての引数は呼び出し側で明示的に指定する（デフォルト値フォールバックは禁止）
func (f factory) Create(sub string, email shared.Email, userName shared.UserName, role shared.Role, newsSub bool, createdBy shared.Sub) (Entity, error) {
    uid, err := shared.NewUserID("") // 空文字でランダム生成
    if err != nil {
        return Entity{}, err
    }
    return Entity{
        Sub:        shared.NewSub(sub),
        UID:        *uid,
        UserName:   userName,
        Email:      email,
        Role:       role,
        Settings:   NewConfig(newsSub),
        TimeStamps: shared.NewTimeStamps(createdBy),
    }, nil
}
```

---

## Eventドメインの実装例（新規作成する場合）

### entity.go

```go
package event

import (
    "github.com/s-duu-jp/qing/2.backend/common/domain/shared"
)

type Entity struct {
    EventID           shared.EventID  // イベントID（ULID）
    Sub               string          // オーナーのCognito sub（内部識別子）
    shared.TimeStamps                 // 共通タイムスタンプ情報
}
```

### factory.go

```go
package event

import "github.com/s-duu-jp/qing/2.backend/common/domain/shared"

type factory struct{}

func NewFactory() factory { return factory{} }

func (f factory) Create(sub string, createdBy shared.UserID) Entity {
    return Entity{
        EventID:    shared.NewEventID(),
        Sub:        sub,
        TimeStamps: shared.NewTimeStamps(createdBy),
    }
}
```

---

## 共有値オブジェクトの詳細

### StringValueObject（基底型）

IDや名前などの文字列値オブジェクトの基底。`SetValue` / `Value()` を持つ。

```go
type EventID struct {
    shared.StringValueObject
}
// 使い方
id := shared.NewEventID()
id.Value() // ULID文字列を返す
```

### TimeStamps

全エンティティに埋め込む。作成・更新の日時と操作者IDを管理。

```go
// 作成時
ts := shared.NewTimeStamps(createdBy) // createdBy: shared.UserID

// 更新時
entity.TimeStamps.UpdateInfo(updatedBy)
```

### UserID（外部公開ID）

ランダム12桁の英数字。外部に公開するユーザー識別子として使う。

```go
uid, _ := shared.NewUserID("")  // ランダム生成
uid, _ := shared.NewUserID("abc123") // 既存値から生成
uid.Get() // 文字列を返す
```

### EventID（ULID）

時系列ソート可能なID。DynamoDBのSKとして使うと降順クエリで最新取得できる。

```go
id := shared.NewEventID()
id.Value() // ULID文字列（例: "01ARZ3NDEKTSV4RRFFQ69G5FAV"）
```
