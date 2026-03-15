# Plan: consolidate-claude-permissions

## Context

各プロジェクトの `.claude/settings.local.json` に個別で許可されたパーミッションが散在しており、グローバル設定と重複している。
特に passwd-sso の `Bash(git:*)` は全 git コマンドを許可し、deny ルールをバイパスするセキュリティリスクがある。
グローバル `~/.claude/settings.json` に統合し、プロジェクト別設定をクリーンアップする。

## Objective

- プロジェクト横断で有用なパーミッションをグローバルに昇格
- グローバルで既にカバー済みの冗長エントリを削除
- 危険なワイルドカードパーミッション (`Bash(git:*)`) を削除
- `settings.local.json` の重複エントリを整理

## Requirements

### Functional
- 既存の許可済みコマンドが引き続き動作すること
- 各プロジェクトでの開発ワークフローに影響しないこと

### Non-functional
- パーミッション設定の一元管理
- deny ルールがバイパスされないセキュリティの確保

## Technical Approach

### グローバルに昇格するパーミッション（4件）

| パーミッション | 現在の場所 | 理由 |
|---|---|---|
| `Bash(git submodule status *)` | EgoX | git read 系、元の EgoX エントリのスコープを維持 |
| `Bash(git ls-tree *)` | passwd-sso | git read 系、安全で汎用的 |
| `WebFetch(domain:raw.githubusercontent.com)` | EgoX | GitHub raw コンテンツ取得、汎用的 |
| `Bash(nvidia-smi*)` | settings.local.json | マシン固有だが常に安全 |

### 削除対象（冗長または危険）

| パーミッション | ファイル | 理由 |
|---|---|---|
| `Bash(git:*)` | passwd-sso | **危険**: 全 git コマンドを許可、deny バイパス |
| passwd-sso の 14 エントリ | passwd-sso | グローバルでカバー済み |
| `gh issue list --search ...` | passwd-sso | ワンオフ、不要 |
| EgoX の 3 エントリ全て | EgoX | グローバルでカバー済み or 昇格 |
| `Bash(git fetch:*)` | settings.local.json | settings.json でカバー済み |

## Implementation Steps

### Step 1: `settings.json`（リポジトリ）にパーミッション追加

ファイル: `settings.json` (リポジトリルート)

`allow` 配列に以下を追加:

- `"Bash(git submodule status *)"` — git read コマンド群の `"Bash(git branch*)"` の後
- `"Bash(git ls-tree *)"` — 同上
- `"Bash(nvidia-smi*)"` — 開発ツール群の `"Bash(node *)"` の後
- `"WebFetch(domain:raw.githubusercontent.com)"` — allow 配列末尾

### Step 2: デプロイ

```bash
bash install.sh
```

で `~/.claude/settings.json` を更新。

### Step 3: `settings.local.json` クリーンアップ（手動編集、Step 2 完了後に実施）

**重要**: Step 2 完了後に実行すること。先に実行すると `nvidia-smi` 等がグローバルにもローカルにも存在しない状態になる。

#### 3a: `~/.claude/settings.local.json`

`nvidia-smi` と `git fetch` はグローバルに昇格済み。`python` は任意コード実行のリスクがあるためここに残す:

```json
{
  "permissions": {
    "allow": [
      "Bash(python *)"
    ],
    "deny": [],
    "ask": []
  }
}
```

#### 3b: EgoX `settings.local.json`

ファイル: `/home/noguchi/ghq/github.com/shi3z/EgoX/.claude/settings.local.json`

全エントリがグローバルでカバーされるため allow を空にする。

#### 3c: passwd-sso `settings.local.json`

ファイル: `/home/noguchi/ghq/github.com/ngc-shj/passwd-sso/.claude/settings.local.json`

全 19 エントリを削除（大半はグローバルでカバー済み、`Bash(git:*)` は危険、`gh issue list --search ...` はワンオフ）。

## Testing Strategy

1. `settings.json` の JSON 構文が正しいことを `jq` で確認
2. `install.sh` を実行して `~/.claude/settings.json` が更新されることを確認（既存の .bak バックアップ機構あり）
3. デプロイ後のファイル内容がソースと一致することを `diff` で検証
4. deny ルールが引き続き有効であることを確認（deny リスト内のコマンドパターンが allow に含まれていないことを検証）
5. 各プロジェクトで基本的なコマンド（git status, npm test 等）が許可プロンプトなしで実行可能なことを確認

## Considerations & Constraints

- `settings.local.json` は gitignore されているため、EgoX / passwd-sso の変更はローカル操作
- passwd-sso の `Bash(git:*)` 削除は**セキュリティ上最も重要な変更** — deny ルール（force push, reset --hard 等）のバイパスを防止
- `nvidia-smi` は GPU 搭載マシン固有だが、非 GPU マシンでも害はないのでグローバルで問題ない
- パターン形式はグローバル設定の慣例 `Bash(command *)` に統一（コロン形式 `command:*` はレガシー記法で等価だが非推奨）
- コロン構文（`:*`）とスペース構文（` *`）は Claude Code のパーミッションマッチャーで等価であることを確認済み
- Claude Code の権限評価順序: deny → ask → allow（deny が常に優先）。allow と deny の重複パターンがあっても deny が勝つ

## Critical Files

- `settings.json` (リポジトリ) — グローバルパーミッション定義
- `~/.claude/settings.local.json` — グローバル拡張設定
- `/home/noguchi/ghq/github.com/shi3z/EgoX/.claude/settings.local.json`
- `/home/noguchi/ghq/github.com/ngc-shj/passwd-sso/.claude/settings.local.json`
- `install.sh` — デプロイスクリプト
