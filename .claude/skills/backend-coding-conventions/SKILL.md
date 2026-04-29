---
name: backend-coding-conventions
description: バックエンドのコーディング規約。ID/UID設計、Get/Find命名規則、UseCase層のHTTP動詞禁止、メソッド順序、コメント規則。命名規則やコーディングルールに関する質問がある場合に使用。
user-invocable: false
---

# バックエンド コーディング規約

## ID と UID の使い分け（必須）

| フィールド | 値 | 公開範囲 | 用途 |
|-----------|-----|---------|------|
| **ID** | Cognitoのsub | 内部のみ | DBの主キー、CreatedBy/UpdatedBy、内部処理 |
| **UID** | ランダム生成 | 外部公開 | URL、APIレスポンス、ユーザー表示 |
| **CreatedBy** | ID（sub） | 内部のみ | 作成者の追跡 |
| **UpdatedBy** | ID（sub） | 内部のみ | 更新者の追跡 |

```go
// ✅ 外部APIレスポンスにはUID
return &UserResponse{UID: user.UID.Get()}

// ❌ 外部にIDを公開しない
return &UserResponse{ID: user.ID}  // NG
```

## Get と Find の命名規則（必須）

| メソッド名 | 存在保証 | 値がない場合 | 呼び出し側のnilチェック |
|-----------|---------|------------|---------------------|
| `Get*` | 必ず存在 | `(nil, error)` | **不要** |
| `Find*` | 存在しない可能性 | `(nil, nil)` | **必須** |

```go
// Get: 存在しない場合はエラー
func (r *repo) GetBySub(ctx context.Context, sub string) (*AuthUser, error) {
    if len(output.Users) == 0 {
        return nil, errors.New("ユーザーが見つかりません")  // ✅ エラー
    }
}

// Find: 存在しない場合はnil
func (r *repo) FindByUID(ctx context.Context, uid UserID) (*Entity, error) {
    if len(result.Items) == 0 {
        return nil, nil  // ✅ nilを返す
    }
}
```

## UseCase層の関数命名（必須）

UseCase層ではHTTP動詞プレフィックス（Get, Post, Put, Delete）を使用しない。

| HTTP動詞 | Controller層 | UseCase層 |
|---------|-------------|----------|
| GET | `GetMe` | `Me` |
| POST | `PostLogin` | `Login` |
| POST | `PostSignup` | `Signup` |
| PUT | `PutUser` | `UpdateUser` |
| DELETE | `DeleteUser` | `RemoveUser` |

```go
// ✅ UseCase層: ビジネスドメイン言語
type UseCase interface {
    Me(ctx context.Context, sub string) (*user.Entity, error)
    Login(ctx context.Context, email shared.Email, password string) (*auth.Res, error)
}

// ❌ UseCase層にHTTP動詞は禁止
type UseCase interface {
    GetMe(ctx context.Context, sub string) (*user.Entity, error)   // NG
    PostLogin(ctx context.Context, ...) (*auth.Res, error)          // NG
}
```

## メソッドの配置順序

```
1. type定義（構造体、インターフェース）
2. コンストラクタ（New* 関数）
3. 公開メソッド（大文字で始まるメソッド）
4. プライベートメソッド（小文字で始まるヘルパーメソッド）
```

## コメントの書き方

メソッド名を除いた簡潔な説明を記述する。

```go
// ✅ メソッド名を繰り返さない
// メールアドレスでユーザー存在確認を行います
func (s *service) CheckUserExistsByEmail(...) { }

// ❌ メソッド名を冗長に繰り返す
// CheckUserExistsByEmail はメールアドレスでユーザー存在確認を行います
func (s *service) CheckUserExistsByEmail(...) { }
```

## デフォルト値フォールバック禁止（CLAUDE.md最優先ルール）

**意図しない不具合の温床となるため、フォールバック用のデフォルト値は一切使用しないこと。**

値が必須なパラメータに対し、以下は禁止:
- nil引数を受け取ってデフォルト値で埋める
- 不正値を受け取って既定値（例: `RoleOwner`）にフォールバックする
- 空値を受け取ってランダム生成や固定値で補完する（空文字が明示的仕様である場合を除く）

### Factoryの実装パターン

```go
// ❌ 禁止パターン
func (f factory) Create(userName *shared.UserName, role *shared.Role) Entity {
    if userName == nil { userName = shared.NewUserName() }  // nilデフォルト
    if role == nil { r := shared.RoleOwner; role = &r }     // nilデフォルト
    return Entity{UserName: *userName, Role: *role}
}

// ✅ 正しいパターン
func (f factory) Create(userName shared.UserName, role shared.Role) (Entity, error) {
    return Entity{UserName: userName, Role: role}, nil
}
```

### Validation系関数の実装パターン

```go
// ❌ 禁止パターン: 不正値→デフォルト値フォールバック
func NewRole(role string) Role {
    r := Role(role)
    if r.IsValid() { return r }
    return RoleOwner  // フォールバック
}

// ✅ 正しいパターン: 不正値はエラー返却
func NewRole(role string) (Role, error) {
    r := Role(role)
    if !r.IsValid() {
        return "", fmt.Errorf("無効なRoleです: %s", role)
    }
    return r, nil
}
```

### エラー無視の禁止

```go
// ❌ 禁止: エラー無視
uid, _ := shared.NewUserID("")

// ✅ 正しい: エラーを明示的にハンドリング
uid, err := shared.NewUserID("")
if err != nil {
    return nil, err
}
```

## 重要なルール

- ✅ ID（内部）とUID（外部公開）を正しく使い分ける
- ✅ Getは存在保証、Findは存在しない可能性を明示
- ✅ UseCase層はビジネスドメイン言語で命名
- ✅ 公開メソッドを先、プライベートメソッドを後に配置
- ✅ コメントはメソッド名を繰り返さず簡潔に
- ✅ **デフォルト値フォールバックを使用しない**（nil→デフォルト禁止、不正値→既定値フォールバック禁止、`_` によるエラー無視禁止）
- ❌ 外部APIレスポンスにID（sub）を含めない
- ❌ UseCase層にHTTP動詞を使用しない

## パッケージ・ディレクトリ命名規則

Goのパッケージ名はハイフン・アンダースコアを使えないため、複合語は**小文字連結**にする。

| 種別 | 規則 | 例 |
|-----|------|-----|
| パッケージ名 | 小文字・連結（ハイフン/アンダースコア禁止） | `queueentry`, `forgetpassword` |
| ディレクトリ名 | パッケージ名と同じ | `queueentry/`, `forgetpassword/` |

```go
// ✅ 小文字連結
package queueentry

// ❌ ハイフンはGoの識別子として無効
package queue-entry  // コンパイルエラー

// ❌ アンダースコアも非推奨（Goの公式規約）
package queue_entry
```

> **補足:** ディレクトリ名にハイフンを使うとインポート時にエイリアスが必須になるため避ける。
> ```go
> // ディレクトリが queue-entry の場合、エイリアスが必要になり煩雑
> queueentry "github.com/.../queue-entry"
> ```
