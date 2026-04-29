---
name: backend-implementation-flow
description: バックエンドの新機能実装手順。9ステップ（OpenAPI定義→コード生成→UseCase層→Repository層→Controller層→Factory→サーバー組み込み→テスト→品質チェック）。実装手順に関する質問がある場合に使用。
user-invocable: false
---

# バックエンド 実装フロー

## 実装の流れ

```
0. インフラ前提条件の確認（外部サービス依存時）→ Terraform設定確認
1. OpenAPI定義 → openapi.yml作成
2. コード生成 → make back-{app_name}-gen-oapi
3. UseCase層実装 → types.go, service.go, usecase.go
4. Repository層実装（必要に応じて）→ Infrastructure層
5. Controller層実装 → controller.go
6. Factory作成 → factory.goで依存性注入
7. サーバー組み込み → server.goに登録
8. テスト作成 → 既存ファイルにテスト追加
9. 品質チェック → make back-{app_name}-quality-check
```

## ステップ0: インフラ前提条件の確認（外部サービス依存時）

**外部サービス（Cognito、SES、S3、DynamoDB等）に依存する機能を実装する場合、必ず最初にTerraform設定を確認する。**

### 確認が必要なケース

| ケース | 確認するTerraformリソース | 確認場所 |
|--------|-------------------------|---------|
| **認証（ソーシャルログイン）** | Cognito IdP設定、callback_urls | `1.infra/{env}/modules/aws/cognito/main.tf` |
| **メール送信** | SES設定、送信元メール | `1.infra/{env}/modules/aws/ses/main.tf` |
| **データ保存** | DynamoDBテーブル、GSI | `1.infra/{env}/modules/aws/dynamodb/main.tf` |
| **ファイルストレージ** | S3バケット、CORS設定 | `1.infra/{env}/modules/aws/s3/main.tf` |

### 確認手順

```
1. 該当環境のTerraformモジュールを確認
   - 1.infra/local/modules/aws/{サービス名}/main.tf
   - 1.infra/dev/modules/aws/{サービス名}/main.tf
2. ルートmain.tfでモジュール呼び出しを確認
   - 1.infra/{env}/main.tf
3. 環境変数が.envファイルに設定されているか確認
   - .env.local / .env.dev
4. 不足している設定がある場合、Terraform設定の追加を先に行う
```

### ソーシャル認証（Google/LINE）の場合の確認項目

| 確認項目 | 確認内容 |
|---------|---------|
| `aws_cognito_identity_provider.google` | IdPリソースが定義されているか |
| `callback_urls` | バックエンドのコールバックURLが登録されているか |
| `supported_identity_providers` | `"Google"` が含まれているか |
| `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` | `.env.{env}` に値が設定されているか |
| `AWS_COGNITO_USER_POOL_DOMAIN` | Hosted UI用のドメインが設定されているか |

## ステップ1: OpenAPI定義の作成

```bash
# ディレクトリ作成
mkdir -p /workspace/2.backend/apps/manage/internal/controller/{機能グループ}/
```

`openapi.yml`にエンドポイント、リクエスト/レスポンススキーマを定義。

### コントローラーディレクトリとエンドポイントパスの命名規則

リソースのサブ項目を扱う場合、ディレクトリ名とパスで異なる区切り文字を使用する。

| 対象 | 規則 | 例 |
|------|------|-----|
| コントローラーディレクトリ名 | アンダースコア区切り | `event_setting` |
| OpenAPI の `operationId` | キャメルケース | `getEventSetting` |
| エンドポイントパス | スラッシュ区切り | `/event/setting` |

```
# ✅ 良い例
ディレクトリ: controller/event_setting/
パス:         GET /event/setting

# ❌ 悪い例
パス:         GET /event_setting   ← アンダースコアをパスに使わない
```

## ステップ2: コード生成

```bash
make back-manage-gen-oapi
```

生成ファイル: `/workspace/2.backend/apps/manage/internal/controller/{機能グループ}/handler.go`

## ステップ3: UseCase層の実装

### types.go（型定義）

リクエスト/レスポンス構造体を定義。

### service.go（ビジネスロジック）

再利用可能なビジネスロジックとプライベートメソッドを配置。

### usecase.go（ワークフロー）

ユースケースインターフェースと処理の流れを実装。

## ステップ4: Repository層の実装（必要に応じて）

DynamoDB、Cognito、SES等のインフラ層を実装。

## ステップ5: Controller層の実装

HTTPハンドラー: リクエスト解析 → UseCase呼び出し → レスポンス生成。

## ステップ6: Factory作成

```go
// factory.go: 依存性注入
func NewAuthUseCase(ctx context.Context) (authcontroller.UseCase, error) {
    authService := authusecase.NewService()
    authRepository, err := authrepo.NewCognitoRepository(ctx)
    userRepository, err := userrepo.NewDynamoDBUserRepo(ctx)
    userFactory := userdomain.NewFactory()
    return authusecase.NewUseCase(authService, userFactory, authRepository, userRepository)
}
```

## ステップ7: サーバー組み込み

`server.go`の更新:

1. Factoryのインポート追加
2. 認証除外パスの追加（必要に応じて）
3. UseCase初期化とエンドポイント登録

```go
func createServerConfig(ctx context.Context) commonhttp.ServerConfig {
    authUseCase, err := authfactory.NewAuthUseCase(ctx)
    return commonhttp.ServerConfig{
        EndpointRegistrars: []commonhttp.EndpointRegistrar{
            func(g *echo.Group) {
                authcontroller.RegisterHandlers(g, authcontroller.NewAuthController(authUseCase))
            },
        },
        AuthMiddleware: commonmiddleware.AuthMiddleware(excludedPaths),
    }
}
```

## ステップ8: テスト作成

既存の`usecase_test.go`にテストを追加。新しいファイルは作成しない。

```bash
# モック生成
make back-manage-gen-mock
```

## ステップ9: 品質チェック

```bash
make back-manage-quality-check   # apps層
make back-common-quality-check   # common層（修正した場合）
```

## API未実装時の仮実装

```go
func (uc *useCase) FeatureName(ctx context.Context, req *Request) (*Response, error) {
    // TODO: 実際のビジネスロジック実装
    time.Sleep(500 * time.Millisecond)
    log.Printf("仮実装：リクエスト受信 - %v", req)
    return &Response{Message: "仮実装：処理が完了しました"}, nil
}
```

## 既存機能への追加パターン

既存の機能グループにエンドポイントを追加する場合（例: authにlogoutを追加）、一部のステップを省略できる。

```
0. インフラ前提条件の確認（外部サービス依存時）→ Terraform設定確認
1. OpenAPI定義 → 既存openapi.ymlにエンドポイント追加
2. コード生成 → make back-{app_name}-gen-oapi
3. UseCase層 → 既存usecase.goにメソッド追加、必要に応じてインターフェースにも追加
4. Repository層 → 既存インターフェースにメソッド追加（必要に応じて）
5. Controller層 → 既存controller.goにハンドラー追加、UseCaseインターフェースにメソッド追加
6. モック再生成 → make back-{app_name}-gen-mock
7. テスト追加 → 既存テストファイルにテストケース追加
8. 品質チェック → make back-{app_name}-quality-check
```

**省略されるステップ**:

- Factory作成（依存性注入は既存のまま）
- サーバー組み込み（エンドポイント登録は既存のまま）
- 認証除外パスの追加（認証が必要なエンドポイントの場合）

## 重要なルール

- ✅ **外部サービス依存の機能はステップ0（インフラ確認）を必ず実施**
- ✅ 上記の順序で段階的に実装
- ✅ テストは既存ファイルに追加（新規作成しない）
- ✅ Factory パターンで依存性注入を一元管理
- ✅ 品質チェックは毎回実行
- ❌ 自動生成されたhandler.goの手動編集禁止
- ❌ **Terraform/インフラの確認なしに外部サービス依存の機能を実装しない**
