---
name: backend-architecture-usecase
description: バックエンドのUseCase層実装ガイド。usecase.goの構造（インターフェース定義・コンストラクタ）、types.goの入出力型定義、翻訳キー命名規則、Factoryパターン。UseCase層の実装に関する質問がある場合に使用。
user-invocable: false
---

# バックエンド UseCase層 実装ガイド

## 概要

`apps/{アプリ名}/internal/usecase/{ドメイン名}/` 配下に、アプリ固有のビジネスロジックを実装する。

## 🚨 UseCase層は全アプリで必須

**manage・sse・その他すべてのアプリで、UseCase層の省略は絶対禁止。**

Controllerは必ずUseCaseを経由してリポジトリ・Redisにアクセスすること。SSEアプリであっても例外はない。

## ディレクトリ構造

```
apps/{アプリ名}/internal/usecase/{ドメイン名}/
├── usecase.go         # インターフェース定義・useCase構造体・コンストラクタ・ビジネスロジック
├── service.go         # Application Service（該当ドメインで必要な場合のみ）
├── types.go           # 入出力型定義（Res等）
├── dispatcher.go      # Domain Event ディスパッチャ（該当ドメインで使用する場合のみ）
└── usecase_test.go    # UseCase のテスト（推奨）
```

## 📖 Application Service（`service.go`）

UseCase 内で再利用されるロジックや、複数のメソッドにまたがる複雑な処理を **Application Service** として分離する。DDDの「Domain Service」とは異なり、**アプリケーション固有のロジック**を担当する。

### 配置と使いどころ

- 単一の UseCase メソッド内に収まらない共通ロジック（例: 認証ユーザー存在確認・ユーザー作成リトライ・メール送信HTML生成）
- 複数の UseCase メソッドから呼ばれるヘルパーロジック

**採用例**:
- `apps/manage/internal/usecase/auth/service.go`: `CheckUserExistsByEmail` / `CreateUser`（UID重複リトライ付き）/ `CreateEncryptedConfirmationData` / `CreateConfirmationMail` など
- `apps/manage/internal/usecase/user_setting/service.go`: メール変更コード生成・HTMLテンプレート生成など

### 構造

```go
// apps/{アプリ}/internal/usecase/{ドメイン}/service.go
package {ドメイン名}

// サービス層で必要な狭いリポジトリ Interface（usecase.go の Interface と別）
type authRepositoryForService interface {
    GetUserByEmail(ctx context.Context, email string) (*shared.AuthUser, error)
    ...
}

// Application Service
type service struct {
    authRepo authRepositoryForService
    ...
}

func NewService(authRepo authRepositoryForService, ...) *service {
    return &service{authRepo: authRepo, ...}
}

// ビジネスメソッド（HTTP動詞禁止・ドメイン言語で命名）
func (s *service) CheckUserExistsByEmail(ctx context.Context, email string) (*UserExistsResult, error) { ... }
```

### UseCase 側の利用

```go
type authService interface {
    CheckUserExistsByEmail(ctx context.Context, email string) (*UserExistsResult, error)
    ...
}

type services struct {
    auth authService
}

type useCase struct {
    services services
    ...
}
```

### 導入判断

| 状況 | 判断 |
|---|---|
| ロジックが1メソッドに収まる | UseCase メソッド内に直接記述（`service.go` 不要） |
| 複数 UseCase メソッドから再利用される | `service.go` に抽出 |
| 複雑な合成ロジック（リトライ・複数リソース連携） | `service.go` に抽出 |

### Application Service の命名ガイド

UseCase メソッドと同様、**HTTP 動詞・時系列手続き名ではなく業務動詞・名詞**で命名する。

| ❌ 避けるべき | ✅ 推奨 | 理由 |
|---|---|---|
| `LoginAfterConfirmation` | `FinalizeActivation` / `CompleteConfirmationLogin` | 時系列（"After Xxx"）で呼ばれる場面を埋め込むより、成立する業務アクション（アクティベーション完了）で表現 |
| `CreateUser` | `EnsureUser` / `ProvisionUser` | 単なる「作る」ではなく、業務上の意図（確保する・プロビジョニング）を表現 |
| `GetOrCreateEvent` | `ResolveEvent` | 実装手続き（Get or Create）ではなく、業務意図（解決する）で表現 |
| `CheckXxx` | `VerifyXxx` / `DetectXxx` | 「チェック」は曖昧。検証なら `Verify`、検出結果を返すなら `Detect` |
| `DoXxxFlow` | 業務アクション名 | "Flow" は実装都合。業務動詞で何を成立させるかを表現 |

**方針**: メソッド名を読むだけで「何が成立するのか」がわかること。実装手順や呼び出し順序を名前に埋め込まない。

## 📖 Domain Events ディスパッチャ（EventDispatcher）

Entity が発行する Domain Event を受け取り、副作用（履歴記録・Pub/Sub・カウンタリセット等）にルーティングする機構。Domain Events パターンの詳細は `backend-architecture-domain` スキル参照。

### 配置と構造

```go
// apps/{アプリ}/internal/usecase/{ドメイン}/dispatcher.go
type EventDispatcher interface {
    Dispatch(ctx context.Context, events []shared.DomainEvent)
}

type eventDispatcher struct {
    // ハンドラが必要とする依存（Repository / Factory / Publisher など）
    historyFactory historyFactory
    historyRepo    historyRepository
    entryRepo      queueEntryRepository
    queueRepo      queueRepository
    publisher      publisher
}

func NewEventDispatcher(...) *eventDispatcher { ... }

func (d *eventDispatcher) Dispatch(ctx context.Context, events []shared.DomainEvent) {
    for _, ev := range events {
        switch e := ev.(type) {
        case queueentrydomain.EntryReceived:
            d.handleEntryReceived(ctx, e)
        case queueentrydomain.EntryStatusTransitioned:
            d.handleEntryStatusTransitioned(ctx, e)
        default:
            log.Printf("未知の Domain Event: %s", ev.EventName())
        }
    }
}
```

### UseCase 側の利用

```go
type useCase struct {
    // 必要な Repository / Factory のみ
    entryRepo    queueEntryRepository
    entryFactory queueEntryFactory
    dispatcher   EventDispatcher
}

func (uc *useCase) ReceiveEntry(ctx context.Context, token string) (*ReceiveEntryRes, error) {
    entity, err := uc.entryFactory.Create(...)
    if err != nil { return nil, err }
    if err := uc.entryRepo.Create(ctx, entity); err != nil { return nil, err }
    // 副作用は全て Dispatcher が実行する
    uc.dispatcher.Dispatch(ctx, entity.PullEvents())
    return &ReceiveEntryRes{...}, nil
}
```

### 実装ルール

- **同期ディスパッチ**: イベントは発行順に同期的にハンドラに渡す（Phase 1）
- **ハンドラ失敗時**: ログ出力のみで処理継続（副作用はベストエフォート）
- **ハンドラの配置**: dispatcher.go 内に private メソッドとして実装（`handleXxx`）
- **テスト**: Entity 側のイベント発行を単体テスト、Dispatcher は統合テストまたは実装を簡潔に保つ
- **インターフェース化**: `EventDispatcher` は interface として公開し、UseCase 側はこれに依存（テスト・差し替え容易性のため）

### 導入判断基準

- ✅ **導入する**: 1つの Entity 操作に対して複数の副作用（履歴・Pub/Sub・計算など）が発生する
- ❌ **導入しない**: 副作用が1つだけ・UseCase で直接呼び出して事足りる場合（過剰設計になる）

## 📖 横断関心事は `common/domain/shared/` に集約する

複数アプリ・複数 UseCase から参照される**トークン処理・認証クレーム・プロバイダー判定**などの横断関心事は、UseCase 層やミドルウェアに個別実装を散在させず、**`common/domain/shared/`** に値オブジェクト + 純粋関数として集約する。

### 集約すべきもの

| 関心事 | 場所 | 含まれる API の例 |
|---|---|---|
| HMAC ゲストトークン | `common/domain/shared/hmac_token.go` | `IssueQueueGuestToken` / `VerifyQueueGuestToken` / `ExtractQueueIDFromToken` / `ExtractNonceFromToken` |
| Cognito JWT クレーム | `common/domain/shared/cognito_jwt.go` | `CognitoJWTClaims` / `ParseCognitoJWTClaims` / `VerifyCognitoJWTClaims` |
| 認証プロバイダー判定 | `common/domain/shared/auth.go` | `Provider` / `UsernameProvider` / `AuthUser.IsFederated` / `IsLocal` / `IsSocialAuthUser` / `FederatedUserID` |
| AuthUser スライス検索 | `common/domain/shared/auth.go` | `FindLocalUser` / `FindGoogleFederatedUser` / `HasFederatedUserOtherThan` / `HasNonGoogleFederatedUser` |

### 集約の判断基準

- ✅ **集約する**: 2 箇所以上の UseCase / middleware / Service から参照される
- ✅ **集約する**: 仕様（トークン形式・Username プレフィックス等）の変更が全箇所に波及するもの
- ❌ **集約しない**: 単一 UseCase 内だけで使う private helper（private 関数のままで良い）

### 移行パターン

重複が発見されたら段階的に集約する:
1. まず `common/domain/shared/` に純粋関数 or 値オブジェクトを作る
2. 呼び出し元を 1 つずつ置換
3. 既存の private 実装を削除

前例: HMAC トークンは `apps/manage/usecase/queue` / `apps/manage/usecase/queueentry` / `apps/sse/usecase/queueentry` の 3 箇所に散在していたが `hmac_token.go` に集約。JWT クレームデコードも `middleware` / `apps/manage/usecase/auth/service` / `apps/sse/usecase/queue` の 3 箇所から集約。

## 📖 UseCase 内の重複プレフィックス処理は private helper に抽出する

複数の UseCase メソッドが同じ前処理（トークン解析 → Queue 取得 → 署名検証、OAuth コード → トークン → クレーム抽出 など）を冒頭で行っている場合、**private helper メソッド**に抽出して重複を排除する。

### 判断基準

- 2 つ以上の UseCase メソッドで 10 行以上の前処理が一致している
- 前処理の順序変更が全メソッドに影響する性質のもの
- 翻訳キーだけが異なる（パラメータで切替可能）場合も抽出対象

### 実装例

**ゲストトークン解析の共通化**:
```go
// usecase/queueentry/usecase.go
// ゲストトークンからキューを解決する共通処理
func (uc *useCase) resolveQueueFromGuestToken(ctx context.Context, token string, invalidTokenKey string) (*queuedomainpkg.Entity, string, int64, error) {
    queueIDStr, err := shared.ExtractQueueIDFromToken(token)
    if err != nil { return nil, "", 0, errors.New(helper.GetMessage(ctx, invalidTokenKey)) }
    queueEntity, err := uc.queueRepo.GetByQueueID(ctx, shared.RestoreQueueID(queueIDStr))
    if err != nil { return nil, "", 0, err }
    if queueEntity == nil { return nil, "", 0, errors.New(helper.GetMessage(ctx, invalidTokenKey)) }
    _, nonce, exp, err := shared.VerifyQueueGuestToken(token, queueEntity.SecretKey.Value())
    if err != nil { return nil, "", 0, errors.New(helper.GetMessage(ctx, invalidTokenKey)) }
    return queueEntity, nonce, exp, nil
}

// ReceiveEntry / GuestCancelEntry から呼び出す
func (uc *useCase) ReceiveEntry(ctx context.Context, token string) (*ReceiveEntryRes, error) {
    queueEntity, nonce, exp, err := uc.resolveQueueFromGuestToken(ctx, token, "usecase.queueentry.ReceiveEntry.invalidToken")
    // ...
}
```

**OAuth コールバック前処理の共通化**:
```go
// CallbackGoogle / CallbackLine の冒頭 25 行を共通化
func (uc *useCase) authenticateOAuthCallback(ctx context.Context, code string, redirectURI string) (*Token, *TokenClaims, *shared.AuthUser, error) {
    cognitoTokens, err := uc.repos.auth.ExchangeCodeForTokens(ctx, code, redirectURI)
    if err != nil { return nil, nil, nil, err }
    token := &Token{AccessToken: cognitoTokens.AccessToken, RefreshToken: cognitoTokens.RefreshToken}
    claims, err := uc.services.auth.ExtractTokenClaims(ctx, token.AccessToken)
    if err != nil { return nil, nil, nil, err }
    authUser, err := uc.repos.auth.GetBySub(ctx, claims.Sub)
    if err != nil { return nil, nil, nil, err }
    return token, claims, authUser, nil
}
```

## 📖 God Method 解体の指針

1 つの UseCase メソッドが **100 行を超え、複数のフロー分岐を含む**場合、ドメイン意図を明示する **private helper メソッド**（Application Service 相当）に分解する。

### 判断基準

- メソッド本体が 100 行超
- 複数のビジネスフロー（例: アカウントリンク / 競合検出 / 通常フロー）が switch / if-else で混在
- テストケースが 10 ケース超になる

### 分解例（前例）

| 対象 | Before | After | 分解先の命名パターン |
|---|---:|---:|---|
| `ConfirmSignup` | 130 行 | 46 行 | `validateXxxForYyy` / `buildXxxPending` / `completeXxxFlow` |
| `CallbackGoogle` | 113 行 | 45 行 | `buildLinkPendingForXxx` / `ensureXxxExists` |
| `CallbackLine` | 98 行 | 49 行 | `findXxxByYyy` / `handleXxxConflict` / `buildLinkForXxx` |
| `ConfirmLinkGoogle` | 112 行 | 14 行 | `completeXxxFlow` / `migrateOrCreateXxx` |

### 命名規則

- 検証系: `validateXxxFor{フロー}`
- 決定系: `detectXxxConflict` / `findXxxBy{条件}`
- 組立系: `buildXxxFor{フロー}`
- 完了系: `completeXxxFlow` / `finalizeXxx`
- 確保系: `ensureXxxExists`

時系列手続き名（`handleAfter...` / `processThen...` 等）は避け、**業務成立を示す動詞**で命名する。

## usecase.go の構造

```go
package {ドメイン名}

// 依存するリポジトリのインターフェース（小文字で非公開）
type {ドメイン}Repository interface {
    FindXxx(ctx context.Context, ...) (*domain.Entity, error)
    GetByXxx(ctx context.Context, ...) (*domain.Entity, error)
    Create(ctx context.Context, entity domain.Entity) error
}

// 依存するPub/Subのインターフェース（小文字で非公開）
// SSEアプリの場合、Redisなどを抽象化して受け取る
type {ドメイン}Subscriber interface {
    Subscribe(ctx context.Context, channel string) (<-chan string, func(), error)
}

// UseCase構造体（小文字で非公開）
type useCase struct {
    {ドメイン}Repo       {ドメイン}Repository
    {ドメイン}Subscriber {ドメイン}Subscriber  // SSEアプリの場合
}

// コンストラクタ（依存性注入）
func NewUseCase(repo {ドメイン}Repository, subscriber {ドメイン}Subscriber) *useCase {
    return &useCase{
        {ドメイン}Repo:       repo,
        {ドメイン}Subscriber: subscriber,
    }
}

// ビジネスロジックメソッド
func (uc *useCase) {Method}(ctx context.Context, ...) (*Res, error) { ... }
```

### 依存が多い場合はグループ化する

```go
type repositories struct {
    auth authRepository
    user userRepository
}

type services struct {
    auth authService
}

type useCase struct {
    repos    repositories
    services services
}
```

## エラーの返し方（全アプリ共通）

UseCase 層のエラー返却は manage・sse・その他すべてのアプリで統一する。

### 方針

| 種別 | 返し方 | 判別側 |
|------|--------|--------|
| **区別可能なドメインエラー**（NotFound・Unauthorized 等） | **sentinel エラー**（`var ErrXxxNotFound = errors.New("xxx not found")`）<br>identifier 用の英語メッセージを内部文字列にする | Controller で `errors.Is` で判別 → `helper.GetMessage` で i18n |
| **一般エラー**（バリデーション失敗等） | `errors.New(helper.GetMessage(ctx, "usecase.xxx.Method.errorKey"))` で翻訳済み文字列を生成 | Controller はそのまま `err.Error()` で返す |
| **下位層のエラー伝播** | `return err`（`fmt.Errorf("%w", err)` の無意味ラップは禁止） | - |
| **msg + err を両方残したい場合のみ** | `fmt.Errorf("%s: %w", helper.GetMessage(...), err)` | - |

### 禁止パターン

- ❌ `fmt.Errorf("%w", err)` — 情報付加ゼロのラップは意味なし。`return err` に統一
- ❌ `fmt.Errorf("%s", helper.GetMessage(...))` — `errors.New(helper.GetMessage(...))` に統一（他 UseCase との表記揃え）
- ❌ `errors.New("日本語ハードコード")` — i18n キーを経由すること

### sentinel エラーの定義例

```go
// usecase/queueentry/usecase.go
// 見つからない場合の sentinel エラー（Controller 側で errors.Is で判別）
var ErrEntryNotFound = errors.New("entry not found")

// Controller 側
if errors.Is(err, queueentryusecase.ErrEntryNotFound) {
    return ctx.JSON(http.StatusNotFound, ErrorResponse{
        Error: helper.GetMessage(reqCtx, "usecase.queueentry.EntryByToken.entryNotFound"),
    })
}
```

## 設定値の注入（環境変数の扱い）

### 🚨 UseCase / Application Service から `os.Getenv` 直接参照禁止

UseCase 層・Service 層のコードから `os.Getenv` を直接呼んではいけない。環境変数は Infrastructure の詳細であり、UseCase がそこに依存すると以下の問題が起きる。

- クリーンアーキテクチャの依存方向逆転（UseCase → Infrastructure）
- テスト時に環境変数操作が必須になりテスタビリティが落ちる
- 必須チェック漏れが箇所ごとに発生（ある場所は空文字エラー、別の場所は黙認など）

### 正しい注入方法

1. **factory 層（`interface/http/*/factory.go`）で環境変数を読む**。未設定時は `error` を返して起動を失敗させる（デフォルト値フォールバック禁止）
2. UseCase パッケージに Config 構造体を定義
3. `NewUseCase` / `NewService` コンストラクタで Config を受け取る

```go
// apps/manage/internal/usecase/auth/types.go
type Config struct {
    FrontendOwnerURL            string // https://example.com
    BackendManageURL            string // https://api.example.com
    ConfirmSignUpSecretPassphrase string
    ConfirmSignUpTTLSeconds     int
    PendingLinkSecretPassphrase string
}

// apps/manage/internal/usecase/auth/service.go
func NewService(cfg Config, authRepo ..., userRepo ..., userFactory ...) *service {
    return &service{cfg: cfg, ...}
}

// apps/manage/internal/interface/http/auth/factory.go
func NewAuthUseCase(ctx context.Context) (authcontroller.UseCase, error) {
    cfg := authusecase.Config{
        FrontendOwnerURL: mustEnv("NEXT_PUBLIC_FRONTEND_OWNER_URL"),
        // ...
    }
    // ...
}

func mustEnv(key string) string {
    v := os.Getenv(key)
    if v == "" {
        // factory 側で panic は許容（起動時失敗）。または error 返却版を使う
        panic(fmt.Sprintf("%s が未設定です", key))
    }
    return v
}
```

## SSEアプリでのUseCase責務例

SSE専用アプリ（`apps/sse`等）でのUseCaseの責務：

```go
// UseCaseが提供すべきメソッド例（queueentry SSE の場合）
type UseCase interface {
    // トークンから現在のエントリー情報（ID・ステータス）を取得
    EntryByToken(ctx context.Context, token string) (*Res, error)

    // エントリーIDに対応するRedisチャンネルを購読
    SubscribeEntry(ctx context.Context, entryID string) (<-chan string, func(), error)
}
```

Controllerはこれらを呼び出してSSEイベントを組み立てるだけにする。エラーの返し方は上記「エラーの返し方（全アプリ共通）」に従う。

## types.go の構造

```go
package {ドメイン名}

// メソッドの結果を表す型
type Res struct {
    {フィールド名} {型} // 説明
}
```

**ルール:**
- HTTP層の型（ステータスコード等）は含めない
- UseCase固有の複合型もここに定義する

## UseCase層のルール

| ルール | 説明 |
|--------|------|
| HTTP動詞禁止 | `PostXxx` / `GetXxx` / `PatchXxx` / `DeleteXxx` 等のHTTP動詞をメソッド名に使わない。ドメイン・ビジネス言語で命名する |
| sub受け取り | 認証ユーザーはmiddlewareが設定した `sub string` を引数で受け取る |
| エラー生成 | `errors.New(helper.GetMessage(ctx, "usecase.xxx.Yyy.errorKey"))`（詳細は「エラーの返し方（全アプリ共通）」） |
| エラー伝播 | Infrastructure/Domain層のエラーは `return nil, err` でそのまま伝播（`fmt.Errorf("%w", err)` の無意味ラップ禁止） |
| HTTPコード禁止 | ステータスコード判定はController層の責務 |
| 環境変数直接参照禁止 | `os.Getenv` の UseCase / Service からの直接呼び出し禁止。Config を factory から注入（詳細は「設定値の注入」） |
| UIパス禁止 | `/login` 等のフロントルーティング情報を UseCase が知るのは責務違反。Controller で解決する |

### HTTP動詞排除の命名例

| HTTP | ❌ 禁止（HTTP動詞） | ✅ 推奨（ドメイン言語） |
|------|------|------|
| GET | `GetMe` | `Me` |
| GET | `GetEvents` | `Events` / `ListEvents` |
| GET | `GetKioskPin` | `KioskPin` （名詞としてのメソッド名。返却値が名詞ならOK） |
| GET | `GetOrCreateEvent` | `ResolveEvent` （get+create の意図を業務語で表現） |
| POST | `PostLogin` | `Login` |
| POST | `PostSignup` | `SignUp` |
| POST | `PostQueueQr` | `IssueQueueQr` （業務動詞「発行する」） |
| POST | `PostQueueEntry` | `ReceiveEntry` （業務動詞「受付する」） |
| PUT / PATCH | `PutUser` / `PatchUserSetting` | `UpdateUser` / `UpdateUserSetting` |
| DELETE | `DeleteUser` | `RemoveUser` |

Res 型の命名も同様:
- ❌ `GetHistoryRes` / `PostQueueQrRes` / `PatchUserSettingRes`
- ✅ `HistoryRes` / `IssueQueueQrRes` / `UpdateUserSettingRes`

## 翻訳キーの命名規則

```
usecase.{ドメイン名}.{メソッド名}.{エラー種別}
```

例:
- `usecase.event.ResolveEvent.notFound`
- `usecase.queueentry.ReceiveEntry.entryExpired`
- `usecase.queueentry.EntryByToken.entryNotFound`（SSEアプリ）

翻訳ファイルの配置: `apps/{アプリ名}/assets/locales/{ja,en}.json`

**注意**: メソッド名を改名した場合、コード側と翻訳ファイル側のキーを**両方**更新すること。キー不一致の場合 `GetMessage()` はキー文字列をそのまま返すため、エラーメッセージ表示が壊れる。

## Controller層との接続（UseCase インターフェース）

Controller層は `UseCase` インターフェースを通じてUseCaseを利用する。
このインターフェースはController層（`controller.go`）に定義する。

```go
// controller/{domain}/controller.go
type UseCase interface {
    ResolveEvent(ctx context.Context, sub string, eventID *string, forceCreate bool) (*{domain}usecase.Res, error)
    Events(ctx context.Context, sub string) (*{domain}usecase.EventsRes, error)
    RemoveEvent(ctx context.Context, sub string, eventID string) error
}
```

## Factory（依存性注入）

`interface/http/{ドメイン名}/factory.go` でリポジトリ・インフラを初期化してUseCaseに注入する。

```go
package factory

func New{Domain}UseCase(ctx context.Context) ({domain}controller.UseCase, error) {
    repo, err := domainrepo.NewDynamoDBXxxRepo(ctx)
    if err != nil {
        return nil, err
    }
    // SSEアプリの場合はRedisも注入
    subscriber, err := redisclient.NewRedisClient()
    if err != nil {
        return nil, err
    }
    return usecase.NewUseCase(repo, subscriber), nil
}
```

## 参考実装

詳細なコード例は `reference.md` を参照。
