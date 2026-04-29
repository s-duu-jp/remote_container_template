# インフラストラクチャ層 実装リファレンス

## Eventリポジトリの実装例（フル）

```go
package event

import (
    "context"
    "fmt"
    "log"
    "os"
    "time"

    "github.com/aws/aws-sdk-go-v2/aws"
    "github.com/aws/aws-sdk-go-v2/service/dynamodb"
    ddbTypes "github.com/aws/aws-sdk-go-v2/service/dynamodb/types"

    "github.com/s-duu-jp/qing/2.backend/common/domain/event"
    "github.com/s-duu-jp/qing/2.backend/common/domain/shared"
    "github.com/s-duu-jp/qing/2.backend/common/helper"
    dynamodbCommon "github.com/s-duu-jp/qing/2.backend/common/infrastructure/dynamodb"
)

type DynamoDBEventRepo struct {
    *dynamodbCommon.DynamoDBBaseRepo
}

func NewDynamoDBEventRepo(ctx context.Context) (*DynamoDBEventRepo, error) {
    tableName := os.Getenv("AWS_DYNAMODB_TABLE_NAME")
    if tableName == "" {
        return nil, fmt.Errorf("%s", helper.GetMessage(ctx, "common.infrastructure.dynamodb.event.NewDynamoDBEventRepo.tableNameNotSet"))
    }
    base, err := dynamodbCommon.NewDynamoDBBaseRepo(ctx, tableName)
    if err != nil {
        return nil, err
    }
    return &DynamoDBEventRepo{DynamoDBBaseRepo: base}, nil
}

// PK: USER#{sub}, SK: EVENT#{eventId}
func (r *DynamoDBEventRepo) Create(ctx context.Context, entity event.Entity) error {
    item := map[string]ddbTypes.AttributeValue{
        "PK":        &ddbTypes.AttributeValueMemberS{Value: fmt.Sprintf("USER#%s", entity.Sub)},
        "SK":        &ddbTypes.AttributeValueMemberS{Value: fmt.Sprintf("EVENT#%s", entity.EventID.Value())},
        "EventID":   &ddbTypes.AttributeValueMemberS{Value: entity.EventID.Value()},
        "Sub":       &ddbTypes.AttributeValueMemberS{Value: entity.Sub},
        "CreatedAt": &ddbTypes.AttributeValueMemberS{Value: entity.CreatedAt.Format(time.RFC3339)},
        "UpdatedAt": &ddbTypes.AttributeValueMemberS{Value: entity.UpdatedAt.Format(time.RFC3339)},
        "CreatedBy": &ddbTypes.AttributeValueMemberS{Value: entity.CreatedBy.Get()},
        "UpdatedBy": &ddbTypes.AttributeValueMemberS{Value: entity.UpdatedBy.Get()},
    }
    _, err := r.Client.PutItem(ctx, &dynamodb.PutItemInput{
        TableName: &r.TableName,
        Item:      item,
    })
    if err != nil {
        log.Printf("[DynamoDB Error] PutItem failed: %v", err)
        return fmt.Errorf("%s", helper.GetMessage(ctx, "common.infrastructure.dynamodb.event.Create.saveFailed"))
    }
    return nil
}

// 降順クエリ+Limit=1でユーザーの最新イベントを取得（存在しない場合はnil）
func (r *DynamoDBEventRepo) FindLatestByUserSub(ctx context.Context, sub string) (*event.Entity, error) {
    result, err := r.Client.Query(ctx, &dynamodb.QueryInput{
        TableName:              &r.TableName,
        KeyConditionExpression: aws.String("PK = :pk AND begins_with(SK, :skPrefix)"),
        ExpressionAttributeValues: map[string]ddbTypes.AttributeValue{
            ":pk":       &ddbTypes.AttributeValueMemberS{Value: fmt.Sprintf("USER#%s", sub)},
            ":skPrefix": &ddbTypes.AttributeValueMemberS{Value: "EVENT#"},
        },
        ScanIndexForward: aws.Bool(false), // 降順（ULIDの最新が先頭）
        Limit:            aws.Int32(1),
    })
    if err != nil {
        log.Printf("[DynamoDB Error] Query failed: %v", err)
        return nil, fmt.Errorf("%s", helper.GetMessage(ctx, "common.infrastructure.dynamodb.event.FindLatestByUserSub.searchFailed"))
    }
    if len(result.Items) == 0 {
        return nil, nil
    }
    return convertItemToEntity(ctx, result.Items[0])
}

// PK+SKで直接取得（存在しない場合はnil）
func (r *DynamoDBEventRepo) GetByID(ctx context.Context, sub string, eventID string) (*event.Entity, error) {
    result, err := r.Client.GetItem(ctx, &dynamodb.GetItemInput{
        TableName: &r.TableName,
        Key: map[string]ddbTypes.AttributeValue{
            "PK": &ddbTypes.AttributeValueMemberS{Value: fmt.Sprintf("USER#%s", sub)},
            "SK": &ddbTypes.AttributeValueMemberS{Value: fmt.Sprintf("EVENT#%s", eventID)},
        },
    })
    if err != nil {
        log.Printf("[DynamoDB Error] GetItem failed: %v", err)
        return nil, fmt.Errorf("%s", helper.GetMessage(ctx, "common.infrastructure.dynamodb.event.GetByID.searchFailed"))
    }
    if len(result.Item) == 0 {
        return nil, nil
    }
    return convertItemToEntity(ctx, result.Item)
}
```

---

## convertItemToEntity パターン

```go
func convertItemToEntity(ctx context.Context, item map[string]ddbTypes.AttributeValue) (*event.Entity, error) {
    // 安全な文字列取得ヘルパー（内部関数）
    getString := func(key string) (string, error) {
        attr, exists := item[key]
        if !exists || attr == nil {
            return "", fmt.Errorf("%s: %s", helper.GetMessage(ctx, "...fieldMissing"), key)
        }
        s, ok := attr.(*ddbTypes.AttributeValueMemberS)
        if !ok {
            return "", fmt.Errorf("%s: %s", helper.GetMessage(ctx, "...fieldMissing"), key)
        }
        return s.Value, nil
    }

    // 各フィールドを取得
    eventIDValue, err := getString("EventID")
    ...

    // 時刻のパース
    createdAt, err := time.Parse(time.RFC3339, createdAtValue)
    if err != nil {
        log.Printf("[DynamoDB Error] Failed to parse CreatedAt: %v", err)
        return nil, fmt.Errorf("%s", helper.GetMessage(ctx, "...dateParseFailed"))
    }

    return &event.Entity{...}, nil
}
```

---

## DynamoDBスキーマ設計まとめ

```
ユーザー:
  PK: USER#{sub}    SK: PROFILE
  GSI1PK: EMAIL#{email}  GSI1SK: USER#{sub}   ← メール検索用
  GSI2PK: UID#{uid}      GSI2SK: USER#{sub}   ← UID検索用

イベント:
  PK: USER#{sub}    SK: EVENT#{eventId(ULID)}
  ← ULIDはタイムスタンプ順なので ScanIndexForward=false で最新取得可能
```

---

## 翻訳ファイルへの追記例

`2.backend/common/assets/locales/ja.json` に追記:

```json
{
  "common": {
    "infrastructure": {
      "dynamodb": {
        "event": {
          "NewDynamoDBEventRepo": {
            "tableNameNotSet": "DynamoDBテーブル名が設定されていません"
          },
          "Create": {
            "saveFailed": "イベントの保存に失敗しました"
          },
          "FindLatestByUserSub": {
            "searchFailed": "イベントの検索に失敗しました"
          },
          "GetByID": {
            "searchFailed": "イベントの取得に失敗しました"
          },
          "convertItemToEntity": {
            "fieldMissing": "必須フィールドが見つかりません",
            "dateParseFailed": "日時のパースに失敗しました"
          }
        }
      }
    }
  }
}
```
