---
name: backend-architecture-domain
description: バックエンドのドメイン層実装ガイド。entity.goの構造、factory.goのドメインファクトリパターン（DDDのFactoryであってDomain Serviceではない）、Aggregate境界、Entity状態遷移メソッド、共有値オブジェクト（ID系/Email/Sub/Theme/Language/SecretKey/KioskPin/JTI/TicketNumber/LanguageCycleInterval等）の使い方、panic禁止、マジックストリング禁止、Repository Interfaceの配置方針、Entityテストパターン。ドメイン層の実装に関する質問がある場合に使用。
user-invocable: false
---

# バックエンド ドメイン層 実装ガイド

## 概要

`2.backend/common/domain/` 配下に、アプリをまたいで共有するドメインモデルを実装する。

## ディレクトリ構造

```
2.backend/common/domain/
├── shared/                         # 共有値オブジェクト・型
│   ├── valueobject.go              # StringValueObject / IntValueObject / StringListValueObject 基底型
│   ├── timestamps.go               # TimeStamps（CreatedAt/UpdatedAt/CreatedBy/UpdatedBy）
│   ├── sub.go                      # Cognito Sub値オブジェクト + SubGuest定数
│   ├── auth.go                     # 認証関連共有型（UserStatus等）
│   ├── role.go                     # Role型（Admin/System/Owner/Member/Guest）
│   │
│   ├── eventid.go                  # EventID（12桁ランダム、error返却）
│   ├── queueid.go                  # QueueID（12桁ランダム、error返却）
│   ├── entryid.go                  # EntryID（12桁ランダム、error返却）
│   ├── historyid.go                # HistoryID（タイムスタンプ+ランダム）
│   ├── userid.go                   # UserID（12桁ランダム、error返却）
│   │
│   ├── email.go                    # Email値オブジェクト + パスワード検証
│   ├── username.go                 # UserName値オブジェクト
│   ├── eventname.go                # EventName値オブジェクト
│   │
│   ├── secretkey.go                # QRコード用HMAC署名鍵（32バイト→Base64URL）
│   ├── kioskpin.go                 # キオスク画面PIN（4桁数字）
│   ├── theme.go                    # 画面テーマ（light/dark/空文字）
│   ├── language.go                 # 表示言語（ISO 639-1/空文字）
│   ├── languagecycleinterval.go    # 言語切替間隔（3〜5秒、IntValueObject基底）
│   ├── jti.go                      # JWT識別子
│   └── ticketnumber.go             # 受付番号（非負整数）
└── {ドメイン名}/                    # 例: user, event, queue, queueentry, history
    ├── entity.go                   # Aggregate Root / Entity / Value Object定義
    ├── factory.go                  # ドメインファクトリ（Entity生成ロジック）
    └── entity_test.go              # Entity振る舞い（状態遷移等）のテスト
```

## 📖 DDD上の位置づけ：Factory と Domain Service の違い

本プロジェクトの `factory.go` は **DDDのFactory** の責務を持つ（Domain Serviceではない）。

| パターン | 責務 | 本プロジェクトでの扱い |
|---------|------|---------------------|
| **Factory** | 複雑なEntity/Aggregate生成ロジックのカプセル化（`Create()` 等） | ✅ `factory.go` に実装 |
| **Domain Service** | 単一Entityに自然に帰属しない、複数Entityにまたがる振る舞い | ❌ 現状なし。必要になった時点で別途 `service.go` を作成する |

真のDomain Serviceが必要になった場合は、`factory.go` と別に `service.go` を新規作成し、責務を分離すること。

## 📖 Aggregate 境界

本プロジェクトは **5つの独立した Aggregate Root** で構成される。他 Aggregate は ID参照のみで関係する。

| Aggregate Root | 主なID | 他 Aggregate との関係 |
|---|---|---|
| `user.Entity` | `Sub` / `UID` | 単独 |
| `event.Entity` | `EventID` | User は `Sub` で参照、Queue は `EventID` で参照される |
| `queue.Entity` | `QueueID` | Event は `EventID` で参照、QueueEntry は `QueueID` で参照される |
| `queueentry.Entity` | `EntryID` | Queue は `QueueID` で参照（子Entityではなく**別Aggregate**） |
| `history.Entity` | `HistoryID` | Queue / Entry を ID参照（append-only 監査ログ） |

**設計原則:**
- Aggregate 間は ID 参照のみ（オブジェクト参照・埋め込み禁止）
- 各 Aggregate は独自のリポジトリを持つ
- トランザクション境界 = Aggregate 境界（他 Aggregate 更新は結果整合性）
- 各 `entity.go` の先頭に `// Xxx Aggregate Root` のコメントを記載

**QueueとQueueEntryを別Aggregateにしている理由:**
1 つの Queue に多数のエントリーが紐づくため、子Entityにすると全エントリーをロードする必要が生じ、大規模イベントでパフォーマンス問題になる。`NumberCounter` の更新と Entry 作成は別トランザクションだが、カウンタが進むだけで整合性は許容される。

## 📖 Entity の振る舞い（Anemic Domain Model 禁止）

Entity は単なるデータ構造体にせず、**不変条件を Entity 自身が保証する**ためのメソッドを持つこと（必要な場合）。

### 状態遷移メソッドの実装例（`queueentry.Entity`）

```go
type Status string

const (
    StatusWaiting              Status = "Waiting"
    StatusPreCalling           Status = "PreCalling"
    StatusCalling              Status = "Calling"
    StatusDone                 Status = "Done"
    StatusCancelledFromWaiting Status = "CancelledFromWaiting"
)

// 状態遷移メソッドで不変条件（正しい遷移元か）を保証する
func (e *Entity) TransitionToCalling(updatedBy shared.Sub) error {
    if e.Status != StatusWaiting && e.Status != StatusPreCalling {
        return fmt.Errorf("無効な状態遷移: %s → Calling", e.Status)
    }
    e.Status = StatusCalling
    e.UpdateInfo(updatedBy)   // shared.TimeStamps の UpdateInfo で UpdatedAt / UpdatedBy を更新
    return nil
}
```

**UseCase 層からは次のように利用する:**

```go
// ❌ 禁止: UseCase で状態を直接書き換え・遷移ルールを散らばらせる
if entry.Status != queueentrydomain.StatusWaiting {
    return errors.New("invalid status")
}
repo.UpdateStatus(ctx, queueID, entryID, queueentrydomain.StatusCalling, updatedBy)

// ✅ 正しい: Entity メソッドで遷移 → 永続化は Entity の値で
if err := entry.TransitionToCalling(updatedBy); err != nil {
    return err
}
repo.UpdateStatus(ctx, queueID, entryID, entry.Status, entry.UpdatedBy)
```

### 定数値は型化する

```go
// ❌ 禁止: 裸の string
type Entity struct {
    Status string
}

// ✅ 正しい: 名前付き型（定数もこの型で宣言）
type Status string
const (
    StatusWaiting Status = "Waiting"
    // ...
)
type Entity struct {
    Status Status
}
```

DB書き込み・読み込み境界で `string(status)` / `Status(str)` 変換する。JSON シリアライズは変換不要（underlying が string のため）。

## 📖 Entity のメソッド化判断基準

Entity にメソッドを持たせるかどうかは、**状態遷移ルールの有無**と**永続化方式**で判断する。

| Entity種別 | 判断 | 例 |
|---|---|---|
| **状態遷移ルールがある**（例: Waiting → Calling → Done） | ✅ Entity メソッドで保証する（load-modify-save パターン） | `queueentry.Entity.TransitionToCalling()` |
| **単純な属性更新**（項目単位の書き換え、遷移ルールなし） | ⚠️ リポジトリの `Update{Field}` で直接更新してよい（UpdateItem でアトミック更新するため load-modify-save 不要） | `queue.Entity` の `UpdateKioskPin` / `event.Entity` の `UpdateName` |
| **append-only（Immutable）** | ✅ Entity メソッド不要（TimeStamps 埋め込みも不要） | `history.Entity` |

**補足:**
- 状態遷移 Entity は、UseCase で `repo.Get()` → `entity.Transition*()` → `repo.UpdateStatus()` の流れで扱う
- 単純更新 Entity は、UseCase で `repo.Update{Field}()` を直接呼ぶ
- 両者が混在する Entity もあり得る（その場合は遷移メソッドは Entity に置き、単純更新はリポジトリに置く）

## entity.go の構造

### 基本形（Aggregate Root / 状態遷移なし）

```go
package {ドメイン名}

import "github.com/s-duu-jp/qing/2.backend/common/domain/shared"

// {Xxx} Aggregate Root
// 他Aggregateとの関係を記述（例: User は Sub で参照、Queue は {MyID} で参照される）
type Entity struct {
    {ID}               shared.{XxxID}       // 主キー（値オブジェクト）
    {関連ID}           shared.{YyyID}       // 他Aggregateへの参照（値オブジェクト）
    {属性}             shared.{XxxValue}    // 値オブジェクト（可能な限り）
    shared.TimeStamps                        // 埋め込み（例外: append-onlyなら省略）
}
```

### 状態遷移付きEntity

```go
// 状態型を定義
type Status string
const (
    StatusA Status = "A"
    StatusB Status = "B"
)

// Entity
type Entity struct {
    {ID}              shared.{XxxID}
    Status            Status
    shared.TimeStamps
}

// 終端判定・状態遷移メソッド
func (e *Entity) IsTerminal() bool { ... }
func (e *Entity) TransitionToB(updatedBy shared.Sub) error { ... }
```

**ルール:**
- 先頭コメントに `// Xxx Aggregate Root` を必ず記載
- `shared.TimeStamps` は原則埋め込む（**例外**: append-only な監査ログ系のEntity（`history.Entity`）は `CreatedAt` / `CreatedBy` のみ持つ）
- 外部公開する文字列/整数フィールドは可能な限り **shared値オブジェクト**で持つ（裸の `string` / `int` は最小限に）
- Cognitoのsubは `shared.Sub` 値オブジェクトとして持つ（内部識別子）
- 状態遷移がある場合は Entity メソッドで表現し、UseCase 層から直接 Status 比較しない

## factory.go の構造

```go
package {ドメイン名}

import "github.com/s-duu-jp/qing/2.backend/common/domain/shared"

type factory struct{}

func NewFactory() factory { return factory{} }

// エンティティ生成メソッド（コンストラクタ）
// 値オブジェクトのバリデーションやランダム生成が失敗する可能性があるため (Entity, error) を返す
func (f factory) Create(...) (Entity, error) {
    id, err := shared.New{XxxID}()
    if err != nil {
        return Entity{}, err
    }
    return Entity{
        {ID}:       id,
        ...,
        TimeStamps: shared.NewTimeStamps(createdBy),
    }, nil
}
```

**ルール:**
- `factory` 構造体はエクスポートしない（小文字）
- `NewFactory()` でインスタンスを返す
- 生成ロジックはすべてここに集約する（UseCase層では直接Entityを組み立てない）
- レシーバ名は `f`（factoryの頭文字）
- **シグネチャは `(Entity, error)` を既定とする**（値オブジェクトの検証・ランダム生成が error を返すため）
- **デフォルト値フォールバック禁止**（CLAUDE.md最優先ルール）: nil引数を受け取ってデフォルト値で埋めることは禁止。ポインタ引数ではなく値渡しにして、呼び出し側で明示的に値を指定させる

### Factoryの実装パターン（デフォルト値禁止対応）

```go
// ❌ 禁止: nil引数をデフォルト値で埋める
func (f factory) Create(userName *shared.UserName, role *shared.Role) Entity {
    if userName == nil { userName = shared.NewUserName() }  // デフォルト値フォールバック
    if role == nil { r := shared.RoleOwner; role = &r }     // デフォルト値フォールバック
    return Entity{UserName: *userName, Role: *role}
}

// ✅ 正しい: 値渡し + error返却。デフォルト値は呼び出し側で明示指定
func (f factory) Create(userName shared.UserName, role shared.Role) (Entity, error) {
    uid, err := shared.NewUserID("")
    if err != nil { return Entity{}, err }
    return Entity{UserName: userName, Role: role, UID: *uid}, nil
}

// 呼び出し側（UseCase層）でデフォルト値を明示
userName := shared.NewUserName()   // 必要ならデフォルト名を呼び出し側で生成
newUser, err := factory.Create(*userName, shared.RoleOwner)
```

## 共有値オブジェクトの使い方

| 型 | 用途 | 生成 |
|----|------|------|
| `shared.EventID` | イベントID（12桁ランダム） | `shared.NewEventID() (EventID, error)` |
| `shared.QueueID` | キューID | `shared.NewQueueID() (QueueID, error)` |
| `shared.EntryID` | エントリーID | `shared.NewEntryID() (EntryID, error)` |
| `shared.UserID` | ユーザー外部ID（12桁） | `shared.NewUserID("") (*UserID, error)` でランダム生成 |
| `shared.HistoryID` | 履歴ID（タイムスタンプ+ランダム） | `shared.NewHistoryID()` |
| `shared.TimeStamps` | 作成・更新日時 | `shared.NewTimeStamps(createdBy)` |
| `shared.Email` | メールアドレス | `shared.NewEmail(str) (*Email, error)` |
| `shared.UserName` | ユーザー名（空文字/50文字超過/禁止ワードはerror） | `shared.NewUserName(str) (*UserName, error)` / デフォルト名定数 `shared.DefaultUserName` |
| `shared.EventName` | イベント名 | `shared.NewEventName(str) (*EventName, error)` |
| `shared.Sub` | Cognitoの不変識別子 | `shared.NewSub(value)` / 定数 `shared.SubGuest` |
| `shared.Role` | ユーザー権限（Admin/System/Owner/Member/Guest） | `shared.NewRole(value) (Role, error)` |
| `shared.SecretKey` | QRコード用HMAC署名鍵（32バイト→Base64URL） | `shared.NewRandomSecretKey() (SecretKey, error)` / `shared.NewSecretKey(value)` |
| `shared.KioskPin` | キオスク画面PIN（4桁数字） | `shared.NewRandomKioskPin() (KioskPin, error)` / `shared.NewKioskPin(value) (KioskPin, error)` |
| `shared.Theme` | 画面テーマ（light/dark、空文字は未設定） | `shared.NewTheme(value) (Theme, error)` |
| `shared.Language` | 表示言語（ISO 639-1、空文字は未設定） | `shared.NewLanguage(value) (Language, error)` |
| `shared.LanguageCycleInterval` | 言語自動切替間隔（3〜5秒） | `shared.NewLanguageCycleInterval(value) (LanguageCycleInterval, error)` |
| `shared.JTI` | JWT識別子 | `shared.NewJTI(value) (JTI, error)` |
| `shared.TicketNumber` | 受付番号（0以上） | `shared.NewTicketNumber(value) (TicketNumber, error)` |

**ガイドライン:**
- バリデーション（範囲・フォーマット）を値オブジェクト内で保証し、呼び出し側での重複チェックを廃止する
- ランダム生成系は `rand.Read` / `rand.Int` の失敗時に `error` を返す（panicは禁止）
- Infrastructure層（DB書き込み）では `.Value()` / `.Get()` で原始値に変換する（**必須**: `.Value()` 呼び忘れでstruct表現が書き込まれるバグの温床）
- Infrastructure層（DB読み込み）では `New*` 関数で値オブジェクトに戻す（不正値はここで検出される）

### 生成（New）と復元（Restore）を区別する

ID 系値オブジェクトは「新規採番」と「既存値からの復元」で異なるコンストラクタを用意する:

| 用途 | コンストラクタ | 例 |
|---|---|---|
| 新規採番（ランダム生成） | `shared.NewXxxID() (XxxID, error)` | ファクトリ / UseCase での新規 Entity 作成時 |
| 復元（永続層・外部入力） | `shared.RestoreXxxID(value string) XxxID` | UseCase / Infrastructure での既存値の値オブジェクト化 |

```go
// ❌ 避ける: SetValue 直打ちはカプセル化破り
queueID := shared.QueueID{}
queueID.SetValue(parts[0])

// ✅ 推奨: 復元コンストラクタを使う
queueID := shared.RestoreQueueID(parts[0])
```

対象: `shared.EventID` / `QueueID` / `EntryID` が復元コンストラクタを持つ（今後追加するID値オブジェクトも同様の構成とする）。

### 値オブジェクトでの `fmt.Stringer` 実装ルール

`StringValueObject` / `IntValueObject` / `StringListValueObject` 基底型は `String() string` メソッドを実装し **`fmt.Stringer` を満たす**。これにより:
- `fmt.Sprintf("%s", vo)` / `fmt.Sprintf("%v", vo)` で `.value` が出力される（struct表現 `{xxx}` ではない）
- `.Value()` 呼び忘れがあっても struct 表現が出力されるバグは防げる

**ただし明示的な `.Value()` 呼び出しは引き続き推奨**:
- 意図が明確になる
- 型安全性が保たれる
- Infrastructure層（DB書き込み）等では**必ず `.Value()` を明示**する

```go
// ✅ 推奨: .Value() を明示
"JTI": &ddbTypes.AttributeValueMemberS{Value: entity.JTI.Value()},

// ⚠️ 動くが非推奨: Stringer 暗黙に依存
"JTI": &ddbTypes.AttributeValueMemberS{Value: fmt.Sprintf("%s", entity.JTI)},
```

## 📖 Entity / 値オブジェクトへのドメインメソッド追加（Anemic 回避）

Entity やドメイン型が単なるデータ運搬器（貧血ドメイン）になっていないか定期的に点検する。**同じ判定・抽出ロジックが UseCase / Service / middleware の複数箇所で繰り返されている場合、ドメイン側のメソッドに昇格させる**。

### 昇格の判断基準

- UseCase / Service / middleware の 2 箇所以上で **同じフィールドを同じ方法で参照して判定** している
- 判定ロジックが**ドメイン知識に属する**（Username プレフィックス、Attributes の意味、ID の構造等）
- 呼び出し側は「何を判定するか」ではなく「**判定結果を受け取る**」だけにできる

### 採用例（`shared.AuthUser`）

| ドメインメソッド | 判定内容 | 置換前の散在 |
|---|---|---|
| `Provider()` | Username プレフィックスから Provider 種別（Local/Google/LINE/Facebook）を返す | `strings.HasPrefix(u.Username, "GoogleOIDC_")` 等が 14+ 箇所 |
| `IsFederated()` / `IsLocal()` | フェデレーテッド/ローカルユーザー判定 | 複数箇所で個別判定 |
| `IsGoogleFederated()` / `IsLineFederated()` | プロバイダー別判定 | プレフィックス比較が複数箇所 |
| `IsSocialAuthUser()` | Attributes["identities"] からソーシャル認証ユーザー判定（リンク済みローカルも含む） | middleware / auth.Refresh で重複 |
| `FederatedUserID()` | Username からプロバイダープレフィックスを剥がして ID を返す | `strings.TrimPrefix` が複数箇所 |

### 採用例（パッケージ関数）

スライス走査や Username 文字列からの判定など、Entity に持たせるほどではないが複数箇所で使うものはパッケージ関数として置く:

- `shared.UsernameProvider(username) Provider` — JWT claims など AuthUser 未構築の場面向け
- `shared.FederatedUsername(provider, id) (string, error)` — Username 組み立て用
- `shared.FindLocalUser(users) *AuthUser` — スライス検索
- `shared.FindGoogleFederatedUser(users) *AuthUser`
- `shared.HasNonGoogleFederatedUser(users) bool`
- `shared.HasFederatedUserOtherThan(users, excludeUsername) bool`

### プロバイダー定数の配置

Cognito の Username プレフィックスや正式プロバイダー名は、**domain/shared 内で package private 定数**として置く:
- `providerPrefixGoogle = "GoogleOIDC_"` / `providerPrefixLINE = "LINE_"` / `providerPrefixFacebook = "Facebook_"` (非公開)
- `ProviderNameGoogle = "GoogleOIDC"` / `ProviderNameLINE = "LINE"` (公開、`LinkProviderForUser` 呼び出し用)

外部から直接プレフィックス文字列を参照させない（ドメイン API 経由でのみアクセス）。

## 📖 横断関心事の純粋関数・値オブジェクトを `shared/` に集約

**トークン処理・認証クレーム・プロトコル変換**など、複数アプリ（manage / sse / middleware）で参照される横断関心事は、`common/domain/shared/` に **純粋関数 + 値オブジェクト**として集約する。

### 集約例

| ファイル | 内容 | 提供 API |
|---|---|---|
| `shared/hmac_token.go` | プレーン HMAC ゲストトークンの発行・検証 | `IssueQueueGuestToken` / `VerifyQueueGuestToken` / `ExtractQueueIDFromToken` / `ExtractNonceFromToken` |
| `shared/cognito_jwt.go` | Cognito JWT クレームのパース・検証 | `CognitoJWTClaims` / `ParseCognitoJWTClaims` / `VerifyCognitoJWTClaims` |
| `shared/auth.go` | 認証プロバイダー判定・AuthUser ドメインメソッド | 上表のとおり |

### 集約の設計原則

- **純粋関数**: 副作用を持たない（I/O なし・状態なし）。依存は引数のみ
- **値オブジェクト**: イミュータブル。コンストラクタでバリデーションを保証
- **UseCase 層から参照可能**: 下位層（Infrastructure）を経由しない
- **アプリ間依存禁止**: manage / sse は互いに参照しない。共通は `common/domain/shared/` へ

### 判断基準

- ✅ 集約する: 2 箇所以上のアプリ・UseCase・middleware から参照される
- ✅ 集約する: 仕様変更（トークン形式など）が全箇所に波及する性質のもの
- ❌ 集約しない: 単一 UseCase 内だけで使う helper

### テスト配置

横断関心事として集約したユーティリティは、**`shared/*_test.go` にテーブル駆動テストを配置する**。これにより UseCase 側はドメインメソッド呼び出しだけを検証すればよく、各所での再テストが不要になる。

## 📖 Repository Interface の配置方針

**Repository Interface は UseCase 層に配置する（ポート&アダプターパターン）**。domain 層には配置しない。

```
apps/{アプリ}/internal/usecase/{ドメイン}/usecase.go   # Repository Interface をここに定義
common/infrastructure/dynamodb/{ドメイン}/repository.go  # 実装
```

**理由（古典DDDとの違い）:**
- UseCase が必要とするメソッドだけを狭く定義できる（Interface Segregation Principle）
- 各アプリが独自の Interface を持てる（manage/sse で必要なメソッドが異なる）
- domain 層は **値オブジェクト・Entity・Factory・状態遷移ルール** に集中できる

**実装ガイド:**
- 各 UseCase で必要なメソッドだけを定義する（例: `entryRepo` が Create/Get/UpdateStatus のみ必要なら、他メソッドは書かない）
- Infrastructure 実装（`DynamoDB{Xxx}Repo`）は複数 Interface を満たすよう構造的に対応

## 📖 Entity / Factory のテストパターン

Entity の振る舞い（状態遷移メソッド等）には `entity_test.go` を作成してテストすること。値オブジェクトのバリデーションも `shared/*_test.go` でテストする。

### 状態遷移メソッドのテストパターン

```go
package queueentry

import (
    "testing"
    "github.com/s-duu-jp/qing/2.backend/common/domain/shared"
    "github.com/stretchr/testify/assert"
)

// テスト用エンティティを指定ステータスで生成するヘルパー
func newTestEntity(status Status) *Entity {
    return &Entity{
        Status:     status,
        TimeStamps: shared.NewTimeStamps(shared.NewSub("creator")),
    }
}

func TestEntity_TransitionToCalling(t *testing.T) {
    updatedBy := shared.NewSub("operator")

    t.Run("正常系: Waiting → Calling", func(t *testing.T) {
        e := newTestEntity(StatusWaiting)
        assert.NoError(t, e.TransitionToCalling(updatedBy))
        assert.Equal(t, StatusCalling, e.Status)
        assert.Equal(t, updatedBy, e.UpdatedBy)
    })

    t.Run("異常系: Done からは遷移不可", func(t *testing.T) {
        e := newTestEntity(StatusDone)
        assert.Error(t, e.TransitionToCalling(updatedBy))
    })
}
```

**テスト観点:**
- **正常遷移**: 全ての有効な遷移元 → 遷移後の状態と `UpdatedBy` / `UpdatedAt` 更新を検証
- **無効遷移**: 全ての無効な遷移元 → `error` 返却と状態が変わっていないことを検証
- **終端判定**: `IsTerminal()` 等のヘルパーメソッドも正常系・異常系を網羅

### 値オブジェクトのテストパターン

```go
func TestNewKioskPin(t *testing.T) {
    t.Run("正常系: 4桁数字で生成される", func(t *testing.T) {
        pin, err := shared.NewKioskPin("1234")
        assert.NoError(t, err)
        assert.Equal(t, "1234", pin.Value())
    })

    t.Run("異常系: 5桁はエラー", func(t *testing.T) {
        _, err := shared.NewKioskPin("12345")
        assert.Error(t, err)
    })
}
```

## 🚫 ドメイン層での panic 禁止

ドメイン層からの panic は禁止。`crypto/rand` 等の低確率失敗も含め `error` を返すこと。

```go
// ❌ 禁止
func NewEventID() EventID {
    // ...
    if err != nil {
        panic("ランダム生成に失敗: " + err.Error())
    }
    // ...
}

// ✅ 正しい
func NewEventID() (EventID, error) {
    // ...
    if err != nil {
        return EventID{}, fmt.Errorf("イベントIDのランダム生成に失敗しました: %w", err)
    }
    // ...
}
```

## 📖 Domain Events パターン

Entity の状態遷移時に発生する副作用（履歴記録・通知など）は、**Domain Event** として Entity が発行し、UseCase 層の EventDispatcher がハンドラにルーティングする。

### 設計原則

- Entity は `[]shared.DomainEvent` を蓄積する（`events` フィールド）
- 状態遷移メソッドが成功した場合のみイベントを蓄積する
- UseCase は DB永続化後に `entity.PullEvents()` で取り出し、`dispatcher.Dispatch()` に渡す
- ハンドラ失敗はログ出力のみで処理を継続する（副作用はベストエフォート）

### Entity 側の実装

```go
// domain/queueentry/entity.go
type Entity struct {
    // ...既存フィールド...
    events []shared.DomainEvent
}

func (e *Entity) RecordEvent(ev shared.DomainEvent) {
    e.events = append(e.events, ev)
}

func (e *Entity) PullEvents() []shared.DomainEvent {
    ev := e.events
    e.events = nil
    return ev
}

// 状態遷移メソッド内でイベントを蓄積
func (e *Entity) TransitionToCalling(updatedBy shared.Sub) error {
    if e.Status != StatusWaiting && e.Status != StatusPreCalling {
        return fmt.Errorf("無効な状態遷移: ...")
    }
    from := e.Status
    e.Status = StatusCalling
    e.UpdateInfo(updatedBy)
    e.RecordEvent(EntryStatusTransitioned{
        FromStatus: from, ToStatus: StatusCalling,
        ChangedBy: updatedBy, At: e.UpdatedAt,
    })
    return nil
}
```

### イベント型の定義（`events.go`）

```go
// domain/queueentry/events.go
type EntryReceived struct {
    EntryID shared.EntryID
    QueueID shared.QueueID
    // ...必要なフィールド...
    At time.Time
}

func (e EntryReceived) EventName() string     { return "queueentry.EntryReceived" }
func (e EntryReceived) OccurredAt() time.Time { return e.At }
```

### UseCase 側の利用

```go
entity, err := uc.entryFactory.Create(...)   // Factoryが EntryReceived を蓄積
if err != nil { return err }
if err := uc.entryRepo.Create(ctx, entity); err != nil { return err }
uc.dispatcher.Dispatch(ctx, entity.PullEvents())
```

EventDispatcher の実装詳細は `backend-architecture-usecase` スキル参照。

### 導入判断基準

- **導入する**: Entity の1つの操作に対して**複数の副作用**（履歴記録、Pub/Sub、計算・リセット等）が発生する場合
- **導入しない**: 副作用が単純な場合（UseCase で直接呼び出しで足りる場合は過剰設計）

## 🚫 マジックストリング禁止

ドメイン定数値は `shared` パッケージの定数として定義し、コード中に生文字列を書かないこと。

```go
// ❌ 禁止
createdBy := shared.NewSub("guest")

// ✅ 正しい
createdBy := shared.SubGuest  // shared/sub.go に定義
```

## ⚠️ ドメイン層変更時の必須確認：インフラ層への反映

ドメイン層はインフラ層に依存しないが、**インフラ層はドメイン層を参照して実装されている**。
そのため、エンティティにフィールドを追加・変更した場合は、必ずインフラ層のリポジトリも合わせて更新すること。

### 確認・更新が必要な場所

`2.backend/common/infrastructure/dynamodb/{ドメイン名}/repository.go`

| 確認箇所 | 内容 |
|---------|------|
| `PutItem` のアイテムmap | 新フィールドを `AttributeValue` として追加しているか |
| `convertItemToEntity` 関数 | DynamoDBアイテムから新フィールドを取得・復元してエンティティに設定しているか |

### チェックリスト

エンティティにフィールドを追加したら必ず確認：

- [ ] `repository.go` の `PutItem` に新フィールドを追加した
- [ ] `repository.go` の `convertItemToEntity` で新フィールドを復元している（値オブジェクトは `New*` 関数で構築）
- [ ] Entity の振る舞いに変更がある場合は `entity_test.go` にテストを追加した
- [ ] `go build ./...` / `go vet ./...` がエラーなく通る
- [ ] `go test ./...` が通る

### 実装例（EventName を追加した場合）

**PutItem:**
```go
item := map[string]ddbTypes.AttributeValue{
    // ...既存フィールド...
    "EventName": &ddbTypes.AttributeValueMemberS{Value: entity.EventName.Value()}, // 追加
}
```

**convertItemToEntity:**
```go
eventNameValue, err := getString("EventName")
if err != nil {
    return nil, err
}
eventName, err := shared.NewEventName(eventNameValue)
if err != nil {
    return nil, err
}

return &event.Entity{
    // ...既存フィールド...
    EventName: *eventName, // 追加
}, nil
```

## 参考実装

詳細なコード例は `reference.md` を参照。
