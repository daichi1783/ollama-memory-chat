# Memoria iPhone 版 — プロジェクト引き継ぎ書

> **このファイルを読めば iPhone アプリ開発を 0 から始められます。**
> 新しいプロジェクト（Cursor / Claude Code）を開始する際は **必ずこのファイルを最初に読んでください。**

---

## Mac版（引き継ぎ元）の最終状態

**Memoria v1.0.0 — 完成・動作確認済み（2026-04-16）**

| リソース | 場所 |
|---|---|
| GitHub | https://github.com/daichi1783/ollama-memory-chat |
| Notion技術仕様書 | https://www.notion.so/34287581c00f81c2a8dae48186a6299d |
| iPhone版引き継ぎ（Notion） | https://www.notion.so/34287581c00f81ddb12adcb38f69b7db |
| ローカルパス | `~/Documents/Claude/Projects/ollamaメモリ機能PJ/ollama-memory-chat` |

### Mac版で完成した機能（全部引き継ぎ対象）

- **マルチAI対応**: Ollama（完全オフライン）/ Claude / Gemini / OpenAI互換
- **記憶システム**: セッション内圧縮（N往復ごとに自動要約→プロンプト注入）+ グローバルメモリ（`/remember`）
- **スラッシュコマンド**: `/english` `/japanese` `/spanish` `/cal` `/remember` `/memory` `/clear` `/help` + ユーザー定義
- **UIテーマ**: Catppuccin Mocha（dark）/ Latte（light）自動切替
- **多言語**: JA / EN / ES（`i18n.js` に全辞書）
- **音声入力（オフライン）**: Python側で `sounddevice` + `faster-whisper`（Whisper base, CPU int8）
- **セットアップウィザード**: 工場出荷Mac でも使えるインストーラー付き
- **配布**: PyInstaller + DMG

### 音声入力の実装詳細（Mac版 → iPhone版への参考）

Mac版では Web Speech API（WKWebView非対応・ネット必須）の代わりに Python側でオフライン録音・文字起こしを実装した。

```
[マイクボタン押下]
  → POST /api/voice/start
     └─ sounddevice.InputStream で16kHz/mono録音開始（バックグラウンドスレッド）

[もう一度押す]
  → POST /api/voice/stop
     └─ 録音停止 → NumPy配列 → 一時WAVファイル
     └─ faster_whisper.WhisperModel("base", cpu, int8) で文字起こし
     └─ {"success": true, "text": "認識テキスト", "language": "ja"} を返す

[フロントエンド]
  → レスポンスのtext を入力欄に挿入
```

**iPhone版では `SFSpeechRecognizer`（Apple純正）を使う**ことを推奨。オフライン認識に対応しており、ライブラリ追加不要。

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
| バックエンド | Python FastAPI | **Swift（オンデバイス推論）** |
| 配布方法 | macOS DMG | App Store または TestFlight |
| ネット接続 | 任意 | **不要（完全オフライン）** |
| 音声入力 | sounddevice + faster-whisper（Python） | **SFSpeechRecognizer**（Apple純正・オフライン可）|

---

## 技術スタック（推奨）

**案C: Swift + llama.cpp（推奨）**

- `LLM.swift` または直接バインディングで GGUF モデルを読み込む
- `GRDB.swift` で SQLite 永続化
- `SFSpeechRecognizer` で音声入力（オフライン認識対応）
- App Store 審査が通りやすく、推論速度も高い

| ライブラリ | 用途 | URL |
|---|---|---|
| LLM.swift | Swift向け高レベルLLMライブラリ | https://github.com/eastriverlee/LLM.swift |
| llama.cpp | 推論エンジン本体 | https://github.com/ggerganov/llama.cpp |
| GRDB.swift | iOS SQLiteライブラリ | https://github.com/groue/GRDB.swift |
| swift-transformers | Hugging Face Swift SDK | https://github.com/huggingface/swift-transformers |
| Gemma 3 1B (GGUF) | デフォルトモデル | https://huggingface.co/bartowski/gemma-3-1b-it-GGUF |

---

## モデル選定（デバイスごとに対応モデルが異なる）

**起動時にデバイスを自動検出し、対応モデルを初回セットアップ画面で提示する。**

| デバイス | 対応モデル | 備考 |
|---|---|---|
| iPhone 15以前 | Gemma 3 1B Q4_K_M のみ | RAM 4〜6GB。固定、選択不可 |
| iPhone 16以降 | **Gemma 4 E2B Q4_K_M または Gemma 3 1B Q4_K_M** | RAM 8GB。初回DL時にユーザーが選択 |

| モデル | サイズ | 対応端末 | 特徴 |
|---|---|---|---|
| **Gemma 3 1B Q4_K_M**（デフォルト） | ~600MB | 全端末 | 安定・128Kコンテキスト・多言語140言語 |
| **Gemma 4 E2B Q4_K_M** | ~1.3GB | iPhone 16以降のみ | 高品質・最新世代 |

- モデルは初回起動時に Wi-Fi でダウンロード（以降はオフライン動作）
- Gemma 3 1B 入手先: `bartowski/gemma-3-1b-it-GGUF`（HuggingFace）
- Gemma 4 E2B 入手先: `unsloth/gemma-4-E2B-it-GGUF`（HuggingFace）

### デバイス検出ロジック（実装メモ）
```swift
// RAM 6GB以上 = iPhone 16以降の目安
let supportsLargeModel = ProcessInfo.processInfo.physicalMemory >= 6 * 1024 * 1024 * 1024
```
設定画面からも後から変更可能にする。

---

## 引き継ぐ設計

### データベース設計（そのまま流用）
Mac版の SQLite スキーマを Swift/GRDB で再実装する。

```sql
sessions        (id, title, created_at, updated_at)
messages        (id, role, content, created_at, session_id)
memory_summaries(id, summary, message_count, created_at, session_id)
user_commands   (id, name, description, prompt_template, created_at, updated_at)
global_memory   (id, content, source, created_at)
```

### 記憶圧縮ロジック（設計を流用）
```
N往復ごとに会話を自動要約 → システムプロンプトに注入
/remember コマンドでグローバルメモリに保存
新セッションでもグローバルメモリを参照
```
参照: `backend/memory_manager.py` の `compress_session_memory()` と `get_global_memory()`

### スラッシュコマンド（設計を流用）
```
/english  — 日→英翻訳
/japanese — 英→日翻訳
/spanish  — 日→西翻訳
/remember — 入力内容をグローバルメモリに保存
/memory   — 記憶サマリー表示
/clear    — セッションリセット
/help     — コマンド一覧
```
参照: `backend/command_manager.py`

### UI/UX デザイン方針（流用）
- **カラー**: Catppuccin Mocha（dark）/ Latte（light）
- **ロゴ**: Orbital SVG — `make_icon.py` / `memoria_logos.html` E案
- **レイアウト**: セッション一覧 + チャット（`NavigationSplitView`）
- **多言語**: JA/EN/ES（Mac版 `i18n.js` の辞書を `Localizable.strings` に移植）

---

## iPhone版独自の要件

### オフライン専用設計
- クラウドAI設定UI は不要（Ollama/Claude/Gemini 設定なし）
- Wi-Fi なしで完全動作
- 機内モードで動作確認が必要

### iPhone特有の制約と対応

| 制約 | 対応 |
|---|---|
| メモリ制限（RAM 4〜8GB） | 軽量モデル（1B）+ 量子化（Q4/Q8）|
| バックグラウンドで推論が停止 | セッション状態を都度SQLiteに保存 |
| App Sandbox | ドキュメントディレクトリ以下にのみファイルを保存 |
| App Store 審査 | サードパーティランタイム同梱に注意 |
| モデルサイズ | 初回DL（Wi-Fi）、以降はオフライン |

### 音声入力（iPhone版の実装方針）

```swift
// SFSpeechRecognizer — オフライン認識に対応（iOS 13+）
let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))!

// 録音開始
let request = SFSpeechAudioBufferRecognitionRequest()
request.requiresOnDeviceRecognition = true   // ← オフライン強制

let task = recognizer.recognitionTask(with: request) { result, error in
    if let result = result {
        // result.bestTranscription.formattedString → 入力欄に挿入
    }
}

// AVAudioEngine でマイク入力をrequestに流す
```

---

## 画面設計（案）

```
TabBar:
├── チャット（メイン）
│   ├── セッション一覧（NavigationSplitView）
│   ├── チャット画面
│   │   ├── メッセージバブル（ユーザー / AI）
│   │   ├── 入力エリア + 音声入力ボタン（SFSpeechRecognizer）
│   │   └── コマンドサジェスト（/ 入力時）
│   └── 推論中インジケーター（TypingIndicator）
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

## 開発ロードマップ

### Phase 1: 基盤構築
1. Xcode プロジェクト作成（SwiftUI + iOS 17+）
2. LLM 推論エンジンの選定と PoC（Gemma 3 1B が iPhone で動くか確認）
3. SQLite 連携（GRDB.swift）
4. 基本チャット画面（メッセージ送受信）

### Phase 2: 記憶機能
5. セッション管理（複数会話）
6. 記憶圧縮ロジック移植（`memory_manager.py` を参照）
7. グローバルメモリ（/remember）
8. コマンドシステム（/english 等）

### Phase 3: UI 完成
9. セッション一覧画面（NavigationSplitView）
10. 設定画面
11. モデルダウンロード画面（初回セットアップ、Mac版 setup.html に相当）
12. Catppuccin テーマ・多言語対応（JA/EN/ES）

### Phase 4: 音声・仕上げ
13. 音声入力（SFSpeechRecognizer、オフライン認識）
14. オフライン動作確認（機内モード）
15. パフォーマンスチューニング（メモリ・速度）
16. App Store 申請準備（プライバシーポリシー、権限説明等）

---

## 開発環境

- **Xcode:** 最新版（16+）
- **最低 iOS ターゲット:** iOS 17.0
- **テスト端末:** iPhone 14 以降推奨
- **開発補助:** Cursor / Claude Code（コーディング支援）

---

## 開発開始時に Claude/Cursor に渡すプロンプト例

```
このファイル（NEXT_PROJECT.md）と Mac版の HANDOFF.md を読んでください。
Memoria iPhone版の開発を始めます。
テーマは「旅先でオフライン使用できる記憶型AIチャットアプリ」です。

まず以下を確認してください：
1. Swift + LLM.swift (llama.cpp) で Gemma 3 1B が iPhone で動くか PoC を作成する
2. SwiftUI でシンプルなチャット画面のスケルトンを作成する
3. GRDB.swift で SQLite に会話を保存する機能を実装する
4. SFSpeechRecognizer でオフライン音声入力を実装する（requiresOnDeviceRecognition = true）

Mac版の設計（HANDOFF.md 参照）を引き継ぎながら、
iPhone の制約（オフライン・メモリ制限・App Sandbox）に適応させてください。

特に記憶圧縮ロジック（backend/memory_manager.py の compress_session_memory）と
コマンドシステム（backend/command_manager.py）は設計をそのまま Swift に移植してください。
```

---

*最終更新: 2026-04-16 — Memoria Mac版 v1.0.0 完成（音声入力オフライン化含む）*
*次のプロジェクト開始時は必ずこのファイルから読み始めること*

## 作成者
Daichi.T
