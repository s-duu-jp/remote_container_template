---
name: backend-architecture
description: バックエンドのクリーンアーキテクチャ。ディレクトリ構造、レイヤー設計（Controller/UseCase/Service/Domain/Infrastructure）、依存関係の方向、各層の責務。アーキテクチャや設計に関する質問がある場合に使用。
user-invocable: false
---

# バックエンド アーキテクチャ

## 🚨 必須: 各層のサブスキルを必ず読み込むこと

バックエンドのコードを**読む・書く・レビューする・評価する**際は、**対象となる層のサブスキルを必ず先に読み込む**こと。本スキル（`backend-architecture`）は**全体像とレイヤー責務の索引**であり、具体的な実装規則・命名規則・パターンはすべてサブスキル側に書かれている。

### 作業別の必須スキル

| 作業 | 必ず読み込むサブスキル |
|---|---|
| Controller / HTTP ハンドラ実装 | `backend-architecture-controller` |
| UseCase / Service 実装 | `backend-architecture-usecase` |
| factory.go / 依存性注入 | `backend-architecture-interface` |
| Entity / 値オブジェクト / ドメインファクトリ | `backend-architecture-domain` |
| DynamoDB / Cognito / SES / Redis リポジトリ実装 | `backend-architecture-infrastructure` |
| 認証・JWT・アカウントリンク | `backend-auth` + 対応する `backend-auth-*` スキル |
| 複数層にまたがる評価・再設計 | 関連する全サブスキル |

### 読み込み順の推奨

1. **本スキル**（`backend-architecture`）で層責務・依存方向・ディレクトリ構造を把握
2. **対象層のサブスキル**で具体的な実装パターン・命名規則・禁止事項を確認
3. 必要に応じて隣接層のサブスキルも参照（例: UseCase を書くなら Domain / Controller も参照）

**サブスキルを読まずに実装すると、過去の評価サイクルで確立したパターン（God Method 解体、横断関心事集約、ドメインメソッド化、値オブジェクト復元など）を見落とす**。必ず先に読み込むこと。

## 技術スタック

- 言語: Go
- Webフレームワーク: Echo v4
- API定義: OpenAPI 3.0
- 認証: AWS Cognito
- データベース: DynamoDB
- メール送信: AWS SES
- テスト: testify, mockery

## ディレクトリ構造

### アプリケーション層

```
/workspace/2.backend/apps/{アプリ名}/
├── cmd/
│   └── main.go                    # エントリーポイント
├── internal/
│   ├── controller/                # コントローラー層
│   │   └── 機能グループ/
│   │       ├── openapi.yml       # OpenAPI定義
│   │       ├── handler.go        # oapi-codegenで自動生成（編集禁止）
│   │       └── controller.go     # HTTPハンドラー実装
│   ├── usecase/                  # ユースケース層（全アプリで必須・省略禁止）
│   │   └── 機能グループ/
│   │       ├── types.go          # 型定義
│   │       └── usecase.go        # ビジネスロジック・リポジトリ呼び出し
│   └── interface/                 # インターフェース層
│       └── http/
│           └── 機能グループ/
│               └── factory.go    # 依存性注入
```

### 共通モジュール

```
/workspace/2.backend/common/
├── domain/                       # ドメイン層
│   ├── event/ queue/ queueentry/ history/ user/
│   │                             # 各Aggregate（entity.go / factory.go / events.go）
│   └── shared/                  # 値オブジェクト・横断関心事
│       ├── auth.go              # AuthUser / Provider / ドメインメソッド
│       ├── email.go userid.go eventid.go queueid.go entryid.go ...
│       │                        # 値オブジェクト（New* / Restore* コンストラクタ）
│       ├── hmac_token.go        # HMAC ゲストトークンの発行/検証（横断関心事）
│       └── cognito_jwt.go       # Cognito JWTクレームのパース/検証（横断関心事）
├── helper/                       # i18n / 暗号化 / 環境変数など横断ヘルパー
│   ├── i18n.go env.go crypto.go
├── interface/http/middleware/   # 共通ミドルウェア（認証など）
└── infrastructure/               # インフラストラクチャ層
    ├── dynamodb/                # DynamoDBリポジトリ実装
    ├── cognito/                 # Cognito認証
    ├── redis/                   # Redis Pub/Sub
    └── ses/                     # SESメール送信
```

### 📖 横断関心事は `common/domain/shared/` に集約する

複数アプリ（manage / sse / middleware）で参照されるトークン処理・認証クレーム・プロバイダー判定などは、各アプリの UseCase やミドルウェアに個別実装を散在させず、**`common/domain/shared/` に純粋関数 + 値オブジェクト**として集約する。

| 関心事 | 場所 | 典型的な API |
|---|---|---|
| HMAC ゲストトークン | `shared/hmac_token.go` | `IssueQueueGuestToken` / `VerifyQueueGuestToken` / `ExtractQueueIDFromToken` |
| Cognito JWT クレーム | `shared/cognito_jwt.go` | `CognitoJWTClaims` / `ParseCognitoJWTClaims` / `VerifyCognitoJWTClaims` |
| 認証ユーザー判定 | `shared/auth.go` | `AuthUser.IsFederated` / `IsSocialAuthUser` / `FederatedUserID` / `FindLocalUser` |

判断基準・設計原則の詳細は `backend-architecture-domain` を参照。

## 🚨 最重要ルール：UseCase層は全アプリで必須

**manage・sse・その他すべてのアプリでUseCase層の省略は絶対禁止。**

| 禁止パターン | 正しいパターン |
|-------------|--------------|
| Controller → Repository（直接アクセス） | Controller → UseCase → Repository |
| Controller → Redis（直接アクセス） | Controller → UseCase → Repository/Service |
| Controller にビジネスロジックを書く | UseCase にビジネスロジックを書く |

SSEのような長時間接続でも、以下の責務分離を必ず守ること：
- **Controller**: SSEヘッダー設定・イベントループ（HTTPの責務）
- **UseCase**: 初期ステータス取得・チャンネル名解決・ビジネスロジック
- **Repository/Infrastructure**: DB・Redis操作

## 依存関係の方向（必須）

```
[Infrastructure層] → [UseCase/Service層] → [Domain層]
※ 内側の層は外側の層に依存してはならない
```

### 命名規則の原則

内側の層（UseCase, Service, Domain）で**インフラストラクチャの詳細を明示してはならない**。

```go
// ✅ 正しい: 抽象的なインターフェース名
type authRepository interface {
    GetUserByEmail(ctx context.Context, email string) (*shared.AuthUser, error)
}
type service struct {
    authRepo authRepository  // ✅ 抽象的な名前
}

// ❌ 間違い: 具体的なインフラ名
type cognitoRepository interface { ... }  // ❌ Cognitoを明示
type service struct {
    cognito cognitoRepository  // ❌ AWS Cognitoに依存
}
```

## 各層の責務

### 1. Controller層（/internal/controller/）

**責務**: HTTPリクエスト/レスポンスの処理のみ

- ✅ リクエストの解析とバリデーション
- ✅ UseCaseの呼び出し（ビジネスロジックはUseCaseに委譲）
- ✅ レスポンスの生成、HTTPステータスコードの設定
- ✅ SSEの場合: ヘッダー設定・flusher・イベントループ（HTTP処理）
- ❌ ビジネスロジックの実装禁止
- ❌ Service層の直接呼び出し禁止（必ずUseCase経由）
- ❌ **リポジトリ・Redis・DB操作の直接呼び出し禁止**

📖 **実装詳細**: `backend-architecture-controller` スキル参照（openapi.yml定義、oapi-codegen、controller.goの構造）

### 2. UseCase層（/internal/usecase/）

**責務**: ワークフロー制御とビジネスロジック

- ✅ 複数のサービス/リポジトリの呼び出しを組み合わせたワークフロー
- ✅ ビジネスロジックの実装
- ✅ トランザクション境界の管理
- ✅ SSEの場合: 初期ステータス取得・チャンネル名解決・ステータスとイベントのマッピング
- ❌ 直接的なHTTPリクエスト/レスポンス処理

📖 **実装詳細**: `backend-architecture-usecase` スキル参照（usecase.goの構造、types.go、リポジトリIFの定義）

### 3. Interface層（/internal/interface/http/）

**責務**: 依存性注入とルーティング接続

- ✅ Controller・UseCase・Repositoryの具体実装を組み立てる（DI）
- ✅ 抽象インターフェースに具体実装を注入
- ❌ ビジネスロジックの実装禁止

📖 **実装詳細**: `backend-architecture-interface` スキル参照（factory.goの構造、依存性注入パターン）

### 4. Domain層（/common/domain/）

**責務**: ビジネスルールとドメインロジックの定義

- エンティティの定義（entity.go）
- リポジトリインターフェースの定義
- ドメインファクトリの実装（DDDのFactoryパターン）

📖 **実装詳細**: `backend-architecture-domain` スキル参照（entity.goの構造、値オブジェクト、ドメインファクトリ）

### 5. Infrastructure層（/common/infrastructure/）

**責務**: 外部システムとのIO操作のみ

- ✅ データベースCRUD、外部API呼び出し、データフォーマット変換
- ❌ ビジネスロジックの実装禁止
- ❌ 条件分岐によるビジネスルールの判定禁止

📖 **実装詳細**: `backend-architecture-infrastructure` スキル参照（DynamoDBリポジトリ実装、repository.goの構造）

## 実装判断のフローチャート

```
新しいロジックを実装する必要がある
├─ 他のUseCaseでも使用される？ → YES → Service層（usecase/配下）
└─ NO → ビジネスロジックである？
         ├─ YES → UseCase層
         └─ NO → UseCaseで既存のRepository/Serviceを呼び出すだけで実現？
                  ├─ YES → UseCaseに直接記述
                  └─ NO → UseCase層に追加実装
```

## 実装詳細ガイド（関連スキル一覧）

各層の実装詳細は、以下のサブスキルを参照すること。**対象層のコードを書く・読む・評価する前に必ず読み込むこと**（冒頭の「必須」ルール参照）。

| 層 | スキル名 | 主な内容 |
|---|---------|---------|
| Controller層 | `backend-architecture-controller` | openapi.ymlの定義、oapi-codegenによるhandler.go自動生成、controller.goの構造、UseCaseインターフェース定義 |
| UseCase層 | `backend-architecture-usecase` | usecase.goの構造、types.go、リポジトリIF定義、God Method解体指針、横断関心事の集約、private helper抽出、エラー/Config/Domain Events/Application Service |
| Interface層 | `backend-architecture-interface` | factory.goの構造、依存性注入パターン、Controller・UseCase・Repositoryの組み立て |
| Domain層 | `backend-architecture-domain` | entity.goの構造、Aggregate境界、状態遷移メソッド、値オブジェクト（New/Restore）、Stringer、ドメインメソッド昇格（Anemic回避）、横断関心事の集約、Domain Events |
| Infrastructure層 | `backend-architecture-infrastructure` | DynamoDBリポジトリ実装、repository.goの構造、外部システムとのIO操作 |
| 認証（横断） | `backend-auth`, `backend-auth-*`, `backend-middleware` | 認証フロー・JWT・アカウントリンク・ミドルウェア |

**使い分けの目安**:
- アーキテクチャ全体像・層の責務・依存関係の方向を確認したい → 本スキル（`backend-architecture`）
- 特定の層の実装コードを書く・読む・レビューする → 対応するサブスキル（**必須**）
- 複数層にまたがる評価・リファクタリング → 関連する全サブスキル（**必須**）

### 評価・再設計時の追加ルール

UseCase 層の継続的な再評価（6〜11 回目）で以下のパターンが確立されている。**評価前に UseCase スキルと Domain スキルを必ず読み込んで**、過去の判断基準を踏襲すること:

- God Method 解体: 100行超メソッドは private helper に分解（命名: `validate~` / `detect~` / `build~` / `complete~` / `ensure~`）
- 横断関心事の集約: 2箇所以上で重複するトークン処理・認証判定は `common/domain/shared/` に値オブジェクト/純粋関数として集約
- 重複プレフィックス処理: 2メソッド以上で10行以上一致する前処理は private helper（例: `resolveQueueFromGuestToken` / `authenticateOAuthCallback`）
- ドメインメソッド昇格: `strings.HasPrefix(u.Username, ...)` のような判定は AuthUser のドメインメソッドに昇格
- 値オブジェクト復元: `shared.XxxID{}; SetValue(...)` は禁止、`shared.RestoreXxxID(value)` を使う

## 重要なルール

- ✅ クリーンアーキテクチャの依存関係の方向を厳守
- ✅ **全アプリ（manage/sse含む）でUseCase層を必ず実装する**
- ✅ 各層の責務を明確に分離
- ✅ インターフェースベースの設計
- ✅ Factory層で具体的な実装を抽象的なインターフェースとして注入
- ❌ Controller層からリポジトリ・Redisを直接呼び出さない
- ❌ Controller層からService層を直接呼び出さない
- ❌ Infrastructure層でビジネスロジックを実装しない
