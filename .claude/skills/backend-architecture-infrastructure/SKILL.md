---
name: backend-architecture-infrastructure
description: バックエンドのインフラ層（DynamoDB）実装ガイド。repository.goの構造、PK/SKシングルテーブル設計、Get/Find命名規則、PutItem/GetItem/Queryの実装パターン、エラーハンドリングと翻訳キー命名。インフラ層の実装に関する質問がある場合に使用。
user-invocable: false
---

# バックエンド インフラストラクチャ層（DynamoDB）実装ガイド

## 概要

`2.backend/common/infrastructure/dynamodb/` 配下に、ドメインごとのDynamoDBリポジトリを実装する。

## ディレクトリ構造

```
2.backend/common/infrastructure/dynamodb/
├── common.go              # DynamoDBBaseRepo・クライアント初期化・共通インターフェース
├── common_mock.go         # テスト用モック
└── {ドメイン名}/
    └── repository.go      # リポジトリ実装
```

## DynamoDBスキーマ設計（シングルテーブル）

```
PK（パーティションキー）: {エンティティ種別}#{識別子}
SK（ソートキー）        : {サブ種別}#{識別子}
```

| エンティティ | PK | SK |
|------------|----|----|
| ユーザー | `USER#{sub}` | `PROFILE` |
| イベント | `USER#{sub}` | `EVENT#{eventId}` |

**GSIの命名規則:**
- `GSI1PK` / `GSI1SK` : 1つ目のGSI（例: メールアドレスで検索）
- `GSI2PK` / `GSI2SK` : 2つ目のGSI（例: UIDで検索）

## repository.go の構造

```go
// リポジトリ構造体（DynamoDBBaseRepoを埋め込む）
type DynamoDB{Domain}Repo struct {
    *dynamodbCommon.DynamoDBBaseRepo
}

// コンストラクタ（環境変数からテーブル名を取得）
func NewDynamoDB{Domain}Repo(ctx context.Context) (*DynamoDB{Domain}Repo, error) {
    tableName := os.Getenv("AWS_DYNAMODB_TABLE_NAME")
    if tableName == "" {
        return nil, fmt.Errorf("%s", helper.GetMessage(ctx, "...tableNameNotSet"))
    }
    base, err := dynamodbCommon.NewDynamoDBBaseRepo(ctx, tableName)
    ...
}

// 各操作メソッド
func (r *DynamoDB{Domain}Repo) Create(ctx, entity) error { ... }
func (r *DynamoDB{Domain}Repo) FindXxx(ctx, ...) (*entity.Entity, error) { ... }
func (r *DynamoDB{Domain}Repo) GetByXxx(ctx, ...) (*entity.Entity, error) { ... }
```

## 命名規則（Get vs Find）

| プレフィックス | 意味 | 存在しない場合 |
|-------------|------|-------------|
| `Get` | 存在前提で取得 | エラーを返す |
| `Find` | 存在しない可能性あり | `(nil, nil)` を返す |

## 主要なDynamoDB操作パターン

### PutItem（作成）
```go
r.Client.PutItem(ctx, &dynamodb.PutItemInput{
    TableName: &r.TableName,
    Item: map[string]ddbTypes.AttributeValue{
        "PK": &ddbTypes.AttributeValueMemberS{Value: fmt.Sprintf("USER#%s", sub)},
        "SK": &ddbTypes.AttributeValueMemberS{Value: "PROFILE"},
        ...
    },
})
```

### GetItem（PK+SKで直接取得）
```go
r.Client.GetItem(ctx, &dynamodb.GetItemInput{
    TableName: &r.TableName,
    Key: map[string]ddbTypes.AttributeValue{
        "PK": &ddbTypes.AttributeValueMemberS{Value: fmt.Sprintf("USER#%s", sub)},
        "SK": &ddbTypes.AttributeValueMemberS{Value: fmt.Sprintf("EVENT#%s", eventId)},
    },
})
// len(result.Item) == 0 なら nil を返す
```

### Query（最新1件取得 / GSI検索）
```go
r.Client.Query(ctx, &dynamodb.QueryInput{
    TableName:              &r.TableName,
    KeyConditionExpression: aws.String("PK = :pk AND begins_with(SK, :skPrefix)"),
    ExpressionAttributeValues: map[string]ddbTypes.AttributeValue{
        ":pk":       &ddbTypes.AttributeValueMemberS{Value: fmt.Sprintf("USER#%s", sub)},
        ":skPrefix": &ddbTypes.AttributeValueMemberS{Value: "EVENT#"},
    },
    ScanIndexForward: aws.Bool(false), // 降順（ULIDの最新が先頭）
    Limit:            aws.Int32(1),
})
// len(result.Items) == 0 なら nil を返す
```

## エラーハンドリングのルール

- DynamoDB操作失敗時は `log.Printf("[DynamoDB Error] ...")` でログ出力
- 返却するエラーメッセージは `helper.GetMessage()` で多言語化
- 内部エラーの詳細は外部に漏らさない

## 翻訳キーの命名規則

```
common.infrastructure.dynamodb.{ドメイン名}.{メソッド名}.{エラー種別}
```

例:
- `common.infrastructure.dynamodb.event.NewDynamoDBEventRepo.tableNameNotSet`
- `common.infrastructure.dynamodb.event.Create.saveFailed`
- `common.infrastructure.dynamodb.event.FindLatestByUserSub.searchFailed`
- `common.infrastructure.dynamodb.event.convertItemToEntity.fieldMissing`
- `common.infrastructure.dynamodb.event.convertItemToEntity.dateParseFailed`

## 参考実装

詳細なコード例は `reference.md` を参照。
