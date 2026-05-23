# claude-code-config (Linux 派生版)

> **Fork について。** これは
> [ngc-shj/claude-code-config](https://github.com/ngc-shj/claude-code-config)
> (MIT) の Linux 適合派生版です。上流の著作権表示は `LICENSE` に保全しています。

[Claude Code](https://docs.anthropic.com/en/docs/claude-code) の安全なデフォルト設定と、複数モデルを協調させるエージェント構成。

## 上流からの変更点

| 対象                       | 変更内容 |
| -------------------------- | -------- |
| `install.sh`               | `settings.json` を**上書きではなくマージ**するよう変更。ユーザの `mcpServers` 等の既存トップレベルキーを保全。マージ前にタイムスタンプ付きバックアップを作成。 |
| `settings.json`            | `rtk hook claude` PreToolUse フックを削除 (上流が前提とする依存ツール `rtk` 未導入のため)。`:(Skill*)` deny を削除 (Claude Code 組み込み skill を全部ブロックしてしまうため)。`Bash(eval *)` / `Bash(source *)` / `Bash(xargs *)` deny を削除 (通常開発で過剰に制限的なため)。 |
| `hooks/notify.sh`, `hooks/stop-notify.sh` | Linux 用に書き直し: `afplay` → `paplay`/`aplay`、`osascript` → `notify-send`。サウンドは freedesktop テーマから解決。 |
| `hooks/resolve-ollama-host.sh` | mDNS による `gx10-*` ホスト自動検出を削除 (上流作者環境固有)。`OLLAMA_HOST` 環境変数を尊重、未設定時は `http://localhost:11434`。 |
| `hooks/block-sensitive-files.sh` | deny メッセージ内のリポジトリパスを `~/ghq/github.com/ngc-shj/claude-code-config` から `~/src/claude-code-config` に変更。 |
| `CLAUDE.md`                | RTK セクションを削除 (使用しないため)。モデル表から `deepseek-r1` 行を削除 (ローカル未導入)。 |
| `skills/`                  | `simplify/`, `explore/`, `security-scan/` を削除 — いずれも Claude Code 組み込み skill と名前衝突するため。 |

**残したもの**: `block-*.sh` セキュリティフック、`check-*.sh` (`triangulate` skill から参照)、`commit-msg-check.sh`、`pre-review.sh`、`rules/`、skill 4種 (`triangulate` / `test-gen` / `pr-create` / `context-budget`)。

## 必要要件

- Linux 上の `bash`, `jq`, `curl`
- (任意) デスクトップ通知用に `notify-send` + `paplay`
- (任意) ローカル LLM 機能用に `ollama` (`http://localhost:11434`)。推奨モデル: `gpt-oss:20b` (コミットメッセージ検査) と `gpt-oss:120b` (コードレビュー事前スクリーニング)
- (任意) AST ベースのフック用: `node`/`npm`, `go`, `java`+`mvn` (いずれも欠如時はランタイムで自動スキップ)

## インストール

```bash
git clone <your fork URL> ~/src/claude-code-config
cd ~/src/claude-code-config
bash install.sh
```

インストーラは冪等。`git pull` 後に再実行すれば変更点だけ反映されます。
既存 `~/.claude/settings.json` は自動でバックアップされた上でマージされます。

### ローカルモデルの取得 (任意)

```bash
ollama pull gpt-oss:20b
ollama pull gpt-oss:120b
```

## リポジトリ構成

```text
claude-code-config/
├── CLAUDE.md                       # グローバル動作ルール + モデル振り分け方針
├── settings.json                   # 権限定義 + フック設定
├── install.sh                      # マージ型インストーラ
├── hooks/
│   ├── block-sensitive-files.sh    # 秘密ファイル/ロックファイル編集ブロック
│   ├── block-*.sh                  # 破壊的コマンドブロック群
│   ├── commit-msg-check.sh         # ローカル LLM によるコミットメッセージ検査
│   ├── pre-review.sh               # ローカル LLM による事前コード/プランレビュー
│   ├── check-*.sh                  # triangulate skill から呼ばれる個別チェック
│   ├── ollama-utils.sh             # skill 共通の Ollama ユーティリティ
│   ├── resolve-ollama-host.sh      # OLLAMA_HOST 解決 (env or localhost)
│   ├── notify.sh                   # デスクトップ通知 (Linux)
│   └── stop-notify.sh              # 応答完了通知 (Linux)
├── skills/
│   ├── triangulate/                # 3 フェーズ × 3 観点レビューワークフロー
│   ├── test-gen/                   # テスト自動生成
│   ├── pr-create/                  # PR 自動作成
│   └── context-budget/             # コンテキスト消費量の監査
└── rules/
    ├── common/                     # 言語非依存のベースライン (常時適用)
    ├── typescript/                 # *.ts, *.tsx, *.js, *.jsx 用オーバーレイ
    ├── python/                     # *.py 用オーバーレイ
    └── golang/                     # *.go 用オーバーレイ
```

## アーキテクチャ

```text
┌──────────────────────────────────────────────────┐
│  Claude Opus (主オーケストレータ)                 │
│  アーキテクチャ設計・計画策定・最終判断           │
└──┬────────────────┬─────────────────┬────────────┘
   │                │                 │
   ▼                ▼                 ▼
┌────────┐  ┌─────────────┐  ┌──────────────────┐
│Sonnet  │  │gpt-oss:120b │  │gpt-oss:20b       │
│        │  │(Ollama)     │  │(Ollama)          │
│探索    │  │コードレビュ │  │コミットメッセー  │
│実装    │  │事前スクリー │  │ジ検査            │
│テスト  │  │ニング       │  │簡易検証          │
│        │  │セキュリティ │  │分類              │
└────────┘  └─────────────┘  └──────────────────┘
```

### モデル振り分け

| モデル | 役割 | 用途 |
| --- | --- | --- |
| Claude Opus | 主オーケストレータ | アーキテクチャ・計画・最終判断 |
| Claude Sonnet | サブエージェント | 探索・実装・テスト |
| gpt-oss:120b | ローカル事前スクリーニング | コードレビュー・セキュリティ解析 (Claude の前に実行) |
| gpt-oss:20b | ローカル軽量チェック | コミットメッセージ・lint・整形・分類 |

ローカル LLM は [Ollama](https://ollama.com/) 経由で動作 — **API コストゼロ、データは端末外に出ません**。
ファイル参照が必要なタスクはフック (shell + curl) 経由、その場の短文分析は MCP 経由で呼び出します。

## 権限設計

コマンドは 3 段階に分類されます:

- **deny** — 無条件ブロック (破壊的・流出・不可逆)
- **allow** — 自動承認 (読み取り専用・ローカル限定・開発で安全)
- **ask** — 毎回ユーザ確認 (副作用ありだが開発に必要)

### deny の例

- `rm -rf`, `sudo`, `chmod 777`, `dd`
- `git push --force`, `git reset --hard`, `git clean -fd`
- `curl -X POST/PUT/DELETE`, `curl --data`
- `docker system prune`, `docker push`, `docker login`
- `npm publish`, `npx -y`

### allow の例

- 読み取り系: `ls`, `cat`, `grep`, `find`, `head`, `tail`, `wc`, `diff`
- Git (安全): `status`, `log`, `diff`, `add`, `commit`, `checkout`, `switch`, `fetch`, `pull`
- Docker (安全): `ps`, `images`, `logs`, `inspect`, `build`, `compose up`, `exec`, `run`
- npm: `list`, `run`, `test`, `install`, `ci`

### ask の例

- `git push`, `rm`, `mv`, `kill`
- `docker stop`, `docker rm`, `docker rmi`, `docker compose down`
- `gh pr merge`, `gh pr close`

## フック

### block-sensitive-files.sh (PreToolUse)

以下への Edit/Write/MultiEdit をブロック:

- 環境ファイル: `.env`, `.env.local`, `.env.production` 等
- 認証情報: `credentials.json`, `secrets.yaml`, `*.pem`, `*.key`
- ロックファイル: `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `Cargo.lock` 等
- Git 内部: `.git/*`
- Claude Code 自身の設定: `~/.claude/hooks/`, `settings.json`, `CLAUDE.md` (本リポジトリが唯一の真実の源)

### commit-msg-check.sh (PreToolUse)

ローカル LLM (`gpt-oss:20b` via Ollama) でコミットメッセージを検証:

- Conventional Commits 形式 (feat/fix/refactor/docs/test/chore) のチェック
- 英語・簡潔性の確認
- 改善提案
- Ollama 利用不可時は無音でスキップ

### pre-review.sh (skill から呼ばれるユーティリティ)

ローカル LLM (`gpt-oss:120b` via Ollama) でコード・計画を事前レビュー:

```bash
# 計画のレビュー
PLAN_FILE=path/to/plan.md bash ~/.claude/hooks/pre-review.sh plan

# コード変更のレビュー
bash ~/.claude/hooks/pre-review.sh code
```

- ファイルは shell が直接読む (git diff, cat) — Claude トークン消費ゼロ
- `OLLAMA_HOST` と `REVIEW_MODEL` 環境変数で挙動を調整可
- Ollama 利用不可時は無音でスキップ

### ollama-utils.sh (skill から呼ばれるユーティリティ)

skill とフック共通の Ollama ユーティリティ群。例:

```bash
# タスク説明から kebab-case のスラッグを生成
echo "Add user authentication" | bash ~/.claude/hooks/ollama-utils.sh generate-slug

# git diff の要約
git diff main...HEAD | bash ~/.claude/hooks/ollama-utils.sh summarize-diff

# 複数エージェントのレビュー結果をマージ・重複除去
cat findings1.txt findings2.txt | bash ~/.claude/hooks/ollama-utils.sh merge-findings

# 変更ファイルの分類 (feature/fix/refactor/docs/test/chore)
git diff --name-only | bash ~/.claude/hooks/ollama-utils.sh classify-changes
```

全コマンドは stdin から読み stdout へ書く構成でパイプ可能。Ollama 不調時は空出力で fail-open します。

### notify.sh / stop-notify.sh (通知)

`paplay` + `notify-send` を使った Linux 用デスクトップ通知:

- **permission_prompt**: 権限承認待ち
- **idle_prompt**: 入力待ち
- **end_turn**: タスク完了
- **max_tokens**: トークン上限到達 (応答が途切れている可能性)

サウンドは `/usr/share/sounds/freedesktop/stereo/` から解決。
`paplay` や `notify-send` が未インストールでも黙ってスキップします。

## Skills

### triangulate

3 フェーズで構成されるレビューワークフロー:

1. **計画作成・レビュー** — ローカル LLM 事前スクリーニング + Claude エキスパート 3 種
2. **コーディング** — Sonnet サブエージェントが実装、計画からの逸脱を追跡
3. **コードレビュー** — ローカル LLM 事前スクリーニング + Claude エキスパート 3 種

各レビューフェーズでローカル LLM (`gpt-oss:120b`) が明らかな問題を先に拾い、Claude サブエージェントの起動を減らします。Opus がオーケストレート、Sonnet が実装、というモデル使い分けで API コストを抑えつつ品質を維持。

### test-gen

指定箇所または変更箇所のテストを自動生成:

- テストフレームワークと既存規約を自動検出
- ローカル LLM がテストケースの骨子を生成 (Claude トークン消費ゼロ)
- Sonnet サブエージェントが実装・検証・修正ループ (最大 3 回)

### pr-create

説明文を自動生成して PR を作成:

- ローカル LLM が差分要約と変更種別分類 (Claude トークン消費ゼロ)
- ローカル LLM が要約・動機・テスト計画を含む PR 本文を作成
- ユーザがドラフトを確認した上で `gh pr create`

### context-budget

エージェント・skill・rules・CLAUDE.md・MCP サーバのトークン消費量を監査し、削減候補を優先度付きで提示:

- 棚卸し段階は純シェル (word count / line count) — Claude トークン消費ゼロ
- Claude が各要素を「常時必要 / 時々必要 / ほぼ不要」に分類
- 肥大化した description・重いファイル・MCP の過剰登録・CLAUDE.md の肥大などを検出

## Rules

レイヤー化された記法・テスト・セキュリティ規約。ファイルを編集するときに該当言語のオーバーレイが参照されます。

- `rules/common/` — 言語非依存のベースライン (KISS/DRY/YAGNI、テスト最低限、機密の扱い)。常時適用。
- `rules/{lang}/` — 言語固有のオーバーレイ。各ファイルは YAML フロントマターで `paths:` を宣言。Go の不変性のように言語慣習で差し替わる箇所をベースラインに上書き。

同梱: `typescript/`, `python/`, `golang/`。`paths:` フロントマター付きで `rules/{lang}/coding-style.md` を置けば言語を追加可能。

rules は自動注入ではなく**参照型**。Claude は `CLAUDE.md` の指示に従い、編集対象のファイル種別に該当する rule を読みに行きます。

## カスタマイズ

- `settings.json` を編集して権限ルールとフックを調整
- `CLAUDE.md` を編集してグローバル動作ルールとモデル振り分けを変更
- フックを追加・削除 (`hooks/`)
- skill を追加・削除 (`skills/`)
- 言語固有 rule を `rules/{lang}/` 配下に追加 (各ファイルの `paths:` フロントマターで適用範囲を宣言)
- プロジェクト固有のルールはプロジェクトルートの `CLAUDE.md` で

**インストールを跨いで残したいローカル変更は `~/.claude/settings.local.json` に置いてください**。`install.sh` はこのファイルを一切触りません。

## ライセンス

MIT
