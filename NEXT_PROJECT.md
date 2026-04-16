# Memoria iPhone 版 — プロジェクト引き継ぎ書

> **このファイルを読めば iPhone アプリ開発を 0 から始められます。**
> 新しいプロジェクト（Cursor / Claude Code）を開始する際は **必ずこのファイルを最初に読んでください。**

---

## プロジェクトコンセプト

**アプリ名（仮）:** Memoria for iPhone
**テーマ:** 「旅先でネット環境なしで使えるローカルAI」
**一言説明:** オフラインで動く、会話を記憶する AI アシスタント。旅行中・機内・山奥でも使える。

### Mac版との違い

| 項目 | Mac版（完成済み） | iPhone版（これから） |
|---|---|---|
| AI エンジン | Ollama / Claude / Gemini | **オンデバイス LLM のみ**（オフライン専用）|
| デフォルトモデル | gemma3:4b | **Gemma 3 1B**（最軽量・iPhone向け）|
| UI フレームワーク | HTML/CSS/JS (PyWebView) | **Swift + SwiftUI** |
| バックエンド | Python FastAPI | **Swift（オンデバイス推論）** または **llama.cpp経由** |
| 配布方法 | macOS DMG | App Store または TestFlight |
| ネット接続 | 任意（Ollama=ローカル、Claude=クラウド） | **不要（完全オフライン）** |

---

## 技術スタック候補（要検討）

### 案A: Swift + Apple Intelligence / Core ML（推奨）
- `CoreML` でオンデバイス推論
- `swift-transformers`（Hugging Face）でモデル読み込み
- SwiftUI でチャットUI を構築
- メリット: ネイティブ、AppStore審査通りやすい
- デメリット: モデル変換作業が必要（GGUF → .mlpackage）

### 案B: Python + llama.cpp + Kivy/BeeWare
- Mac版と同じ Python コードをベースに移植
- llama.cpp の iOS ビルドでオンデバイス推論
- メリット: Mac版の知識を流用できる
- デメリット: App Store 審査が難しい（Python ランタイム同梱）

### 案C: Swift + llama.cpp（swift-llama.cppバインディング）
- `LLM.swift` や直接バインディングを使う
- GGUF 形式のモデルを直接読み込む
- メリット: App Store 審査通りやすい、高速
- デメリット: Swift での低レイヤー開発が必要

**推奨:** 案C（Swift + llama.cpp）が現時点でのバランスが最良。
Cursor / Claude Code で実装時に最新の状況をWebで調査してから決める。

---

## デフォルトモデル

**Gemma 3 1B** をデフォルトにする。

- Hugging Face: `google/gemma-3-1b-it`
- GGUF版: `bartowski/gemma-3-1b-it-GGUF`（llama.cpp対応）
- Core ML変換版: 変換ツールで `.mlpackage` に変換が必要
- サイズ: 約 600MB〜1GB（量子化による）
- iPhone 12 以降で動作見込み

### モデルサイズ比較（参考）

| モデル | サイズ | iPhone動作 | 品質 |
|---|---|---|---|
| Gemma 3 1B (Q4) | ~600MB | ◎ iPhone 12以降 | △ |
| Gemma 3 4B (Q4) | ~2.5GB | ○ iPhone 15 Pro以降 | ○ |
| Phi-3 Mini (Q4) | ~2.3GB | ○ | ○ |
| Llama 3.2 1B (Q4) | ~700MB | ◎ | △ |

---

## 引き継ぐ設計（Mac版から流用できるもの）

### データベース設計（そのまま流用）
Mac版の SQLite スキーマをそのまま使う。Swift では `GRDB.swift` で実装。

```sql
sessions (id, title, created_at, updated_at)
messages (id, role, content, created_at, session_id)
memory_summaries (id, summary, message_count, created_at, session_id)
user_commands (id, name, description, prompt_template, created_at, updated_at)
global_memory (id, content, source, created_at)
```

### 記憶圧縮ロジック（設計を流用）
```
N往復ごとに会話を自動要約 → システムプロンプトに注入
/remember コマンドでグローバルメモリに保存
新セッションでもグローバルメモリを参照
```

### スラッシュコマンド（設計を流用）
```
/english, /japanese, /spanish — 翻訳
/remember — グローバルメモリに保存
/memory — 記憶サマリー表示
/clear — セッションリセット
/help — コマンド一覧
```

### UI/UX デザイン方針（流用）
- Catppuccin カラーパレット（ダーク/ライト）
- Orbital SVG ロゴ（アイコンとして使用）
- セッション一覧 + チャットの構成
- 多言語対応（JA/EN/ES）

---

## iPhone版独自の要件

### オフライン専用設計
- クラウドAI設定UI は不要（Ollama/Claude/Gemini 設定なし）
- Wi-Fi なしで完全動作すること
- 機内モードで動作確認が必要

### iPhone特有の制約と対応

| 制約 | 対応 |
|---|---|
| メモリ制限（RAM 4〜8GB） | 軽量モデル（1B）+ 量子化（Q4/Q8）|
| バックグラウンドで推論が停止 | セッション状態を都度SQLiteに保存 |
| App Sandbox | ドキュメントディレクトリ以下にのみファイルを保存 |
| App Store 審査 | サードパーティランタイム同梱に注意 |
| ストレージ | 初回起動時にモデルをDL（Wi-Fi必要は初回のみ）|

### モデルのバンドル vs 初回DL
- **推奨:** 初回DL方式 + ダウンロード画面でプログレスバー表示
- Mac版のセットアップウィザードと同じ体験を提供する

---

## 画面設計（案）

```
TabBar:
├── チャット（メイン）
│   ├── セッション一覧（NavigationSplitView）
│   ├── チャット画面
│   │   ├── メッセージバブル（ユーザー / AI）
│   │   ├── 入力エリア + 音声入力ボタン
│   │   └── コマンドサジェスト（/入力時）
│   └── 推論中インジケーター
├── 設定
│   ├── モデル設定（使用モデル・量子化）
│   ├── 記憶設定（圧縮タイミング）
│   ├── グローバルメモリ一覧
│   ├── コマンド管理
│   ├── 言語設定（JA/EN/ES）
│   └── アプリ情報
└── モデル管理
    ├── インストール済みモデル
    ├── おすすめモデル（Gemma 3 1B / Phi-3 Mini など）
    └── ダウンロード進捗
```

---

## 開発ロードマップ（案）

### Phase 1: 基盤構築
1. Xcode プロジェクト作成（SwiftUI + iOS 17+）
2. LLM 推論エンジンの選定と PoC（Gemma 3 1B が動くか確認）
3. SQLite 連携（GRDB.swift）
4. 基本チャット画面（メッセージ送受信）

### Phase 2: 記憶機能
5. セッション管理（複数会話）
6. 記憶圧縮ロジック移植
7. グローバルメモリ（/remember）
8. コマンドシステム（/english 等）

### Phase 3: UI 完成
9. セッション一覧画面
10. 設定画面
11. モデルダウンロード画面（初回セットアップ）
12. Catppuccin テーマ・多言語対応

### Phase 4: 仕上げ
13. オフライン動作確認（機内モード）
14. パフォーマンスチューニング（メモリ・速度）
15. App Store 申請準備

---

## 開発環境

- **Xcode:** 最新版（16+）
- **最低 iOS ターゲット:** iOS 17.0
- **テスト端末:** iPhone 14 以降推奨
- **開発補助:** Cursor / Claude Code（コーディング支援）

---

## 参考リポジトリ・ライブラリ

| 名前 | 用途 | URL |
|---|---|---|
| LLM.swift | Swift向け高レベルLLMライブラリ | https://github.com/eastriverlee/LLM.swift |
| llama.cpp | 推論エンジン本体 | https://github.com/ggerganov/llama.cpp |
| GRDB.swift | iOS SQLiteライブラリ | https://github.com/groue/GRDB.swift |
| swift-transformers | Hugging Face Swift SDK | https://github.com/huggingface/swift-transformers |
| Gemma 3 1B (GGUF) | デフォルトモデル | https://huggingface.co/bartowski/gemma-3-1b-it-GGUF |

---

## Mac版の成果物（参照先）

- **GitHub:** https://github.com/daichi1783/ollama-memory-chat
- **HANDOFF.md:** 同リポジトリ内（設計詳細・バグ修正履歴）
- **Notion仕様書（完成版）:** https://www.notion.so/34287581c00f81c2a8dae48186a6299d
- **ローカルパス:** `~/Documents/Claude/Projects/ollamaメモリ機能PJ/ollama-memory-chat`

---

## 開発開始時に Claude/Cursor に渡すプロンプト例

```
このファイル（NEXT_PROJECT.md）と HANDOFF.md を読んでください。
Memoria iPhone版の開発を始めます。
テーマは「旅先でオフライン使用できる記憶型AIチャットアプリ」です。

まず以下を確認してください：
1. Swift + llama.cpp で Gemma 3 1B が iPhone で動くか PoC を作成する
2. SwiftUI でシンプルなチャット画面のスケルトンを作成する
3. GRDB.swift で SQLite に会話を保存する機能を実装する

Mac版の設計（HANDOFF.md参照）を引き継ぎながら、
iPhone の制約（オフライン・メモリ制限・App Sandbox）に適応させてください。
```

---

*作成: 2026-04-14 — Memoria Mac版 v1.0.0 完成時に作成*
*次のプロジェクト開始時は必ずこのファイルから読み始めること*
販売・配布については本 iPhone 版の完成後に別途検討。

## 作成者
Daichi.T

## macOS 版 (Memoria v1.0.0) — 完了済み機能一覧

### AIエンジン対応
- Ollama（ローカル / 完全オフライン動作）
- Claude (Anthropic) — `x-api-key` + `anthropic-version: 2023-06-01` ヘッダー
- Gemini (Google) — `Authorization: Bearer` ヘッダー（OpenAI互換エンドポイント）
- OpenAI 互換 API

### 記憶システム
- **セッション内記憶圧縮**: N往復ごとに自動要約してシステムプロンプトに注入
- **グローバルメモリ**: `/remember` コマンドでセッションをまたいで保持（SQLite `global_memory` テーブル）

### UI/UX
- Catppuccin カラーパレット（Mocha ダーク / Latte ライト）
- macOS システム外観に自動連動（ダーク/ライトモード）
- Orbital ロゴ（グラデーション円＋4方向ドット）
- チャット画面下部のエンジン切り替えピルボタン（履歴保持）
- セッションタイトルのインライン編集（ダブルクリック）

### 多言語対応
- 日本語 / English / Español
- `frontend/assets/i18n.js` に全翻訳辞書
- 設定画面で手動切替、`localStorage` に保存

### コマンド
`/english`, `/japanese`, `/spanish`, `/cal`, `/remember`, `/memory`, `/clear`, `/help` + ユーザー定義コマンド

### 配布形式
- PyInstaller + DMG (macOS)
- Python・依存ライブラリ・Ollama セットアップウィザードをすべて同梱
- 工場出荷状態の Mac でもインストール可能（Python 不要）
- **完全オフライン動作**（Ollama 使用時 / モデルインストール済みの場合）

## GitHub リポジトリ
https://github.com/daichi1783/ollama-memory-chat

## 技術スタック
| 層 | 技術 |
|---|---|
| Backend | Python 3.12 + FastAPI + Uvicorn |
| Frontend | Vanilla HTML/CSS/JS (フレームワークなし) |
| Window | PyWebView |
| DB | SQLite (memory_manager.py) |
| Local AI | Ollama Python SDK |
| Cloud AI | requests (Claude/Gemini direct API) / openai SDK |
| Packaging | PyInstaller + bash build script |

## iPhone 版で検討すべき項目
- [ ] Swift / SwiftUI で UI を構築
- [ ] バックエンド: Python → Swift 移植 or 外部 API サーバー経由
- [ ] ローカル AI: Core ML / llm.swift / on-device model
- [ ] クラウド AI: 同じく Claude / Gemini / OpenAI
- [ ] 記憶: UserDefaults or SQLite via GRDB
- [ ] 多言語: JA / EN / ES (Localizable.strings)
- [ ] 音声入力: iOS の SFSpeechRecognizer を活用
- [ ] App Store 審査対策（プライバシーポリシー、権限説明等）
- [ ] 価格モデルを別途検討

## デザインガイド（継承）
- カラー: Catppuccin Mocha (dark) / Latte (light)
- ロゴ: Orbital SVG — `make_icon.py` / `memoria_logos.html` E案 参照
- フォント: SF Pro (iOS システムフォント)
