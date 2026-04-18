# Memoria for iPhone — プロジェクト計画書

> **作成日:** 2026-04-16（最終更新: 2026-04-16）  
> **PM:** Claude (Sonnet 4.6) via Cowork  
> **開発者:** Daichi.T  
> **ステータス:** Phase 1 開始準備完了

---

## 1. プロジェクト概要

| 項目 | 内容 |
|---|---|
| アプリ名 | Memoria for iPhone |
| テーマ | 旅先でオフライン使用できる記憶型AIチャットアプリ |
| 前身 | Memoria macOS版 v1.0.0（2026-04-16 完成） |
| 最低iOS | iOS 17.0 |
| テスト端末 | iPhone 12（iOS 18、RAM 4GB）|
| 配布形式 | App Store / TestFlight |

### 引き継ぎ元リソース
| リソース | URL / パス |
|---|---|
| GitHub | https://github.com/daichi1783/ollama-memory-chat |
| Mac版 Notion仕様書 | https://www.notion.so/34287581c00f81c2a8dae48186a6299d |
| iPhone版 Notion引き継ぎ | https://www.notion.so/34287581c00f81ddb12adcb38f69b7db |
| ローカルパス | `~/Documents/Claude/Projects/ollamaメモリ機能PJ/ollama-memory-chat` |

---

## 2. 確定技術スタック

### 採用案: Case C — Swift + llama.cpp（LLM.swift経由）

| 層 | 技術 | 備考 |
|---|---|---|
| UI | SwiftUI（iOS 17+） | ネイティブ、App Store審査通過しやすい |
| LLM推論 | LLM.swift v1.7.2（llama.cppラッパー） | GGUF形式直接読み込み |
| **デフォルトモデル** | **Gemma 3 1B Q4_K_M（~600MB）** | iPhone 12で安定動作確認済み水準 |
| DB | SQLite + GRDB.swift | Mac版と同スキーマ流用 |
| 音声入力 | SFSpeechRecognizer | Apple純正・オフライン認識対応 |
| パッケージ管理 | Swift Package Manager (SPM) | Xcode標準 |

### モデル選定の根拠（2026-04-16 調査済み）

**デバイスの世代によって搭載可能なモデルが異なる。起動時にデバイスを自動検出し、対応モデルを提示する。**

| デバイス | チップ | RAM | 対応モデル |
|---|---|---|---|
| iPhone 12〜15 | A14〜A17 | 4〜6GB | Gemma 3 1B Q4_K_M のみ |
| **iPhone 16以降** | **A18以降** | **8GB** | **Gemma 4 E2B Q4_K_M または Gemma 3 1B Q4_K_M を選択可** |

#### モデル詳細

| モデル | サイズ | iPhone 12 | iPhone 16+ | 特徴 |
|---|---|---|---|---|
| **Gemma 3 1B Q4_K_M** | ~600MB | ◎ デフォルト | ◎ 選択可 | 安定・128Kコンテキスト・多言語140言語 |
| **Gemma 4 E2B Q4_K_M** | ~1.3GB | ✕ 不可（A18推奨） | ◎ 選択可 | 高品質・最新世代・iPhone 16以降専用 |
| Gemma 4 E4B | ~2.5GB以上 | ✕ 不可 | ✕ 非推奨 | RAM 4〜6GB必要、現状スコープ外 |

#### デバイス検出ロジック（実装方針）

```swift
import UIKit

struct DeviceCapability {
    /// iPhone 16以降（A18チップ相当）かどうかを判定
    static var supportsLargeModel: Bool {
        // ProcessInfo でRAM量を確認（8GB以上 = iPhone 16以降の目安）
        let ram = ProcessInfo.processInfo.physicalMemory
        return ram >= 6 * 1024 * 1024 * 1024  // 6GB以上
    }

    /// 利用可能なモデル一覧を返す
    static var availableModels: [LLMModel] {
        var models: [LLMModel] = [.gemma3_1b]  // 全端末対応
        if supportsLargeModel {
            models.insert(.gemma4_e2b, at: 0)  // iPhone 16以降は先頭に追加
        }
        return models
    }
}
```

初回起動時（モデルダウンロード画面）で対応モデルを表示し、ユーザーが選択できるようにする。設定画面からも後から変更可能。

---

## 3. 要件定義（確定スコープ）

### Must Have（必須）
- [ ] オフライン完全動作（LLM推論がオンデバイス）
- [ ] Gemma 3 1B のダウンロード＆推論（初回Wi-Fiのみ）
- [ ] チャット画面（メッセージ送受信・ストリーミング表示）
- [ ] セッション管理（複数会話）
- [ ] 記憶圧縮（N往復で自動要約 → システムプロンプト注入）
- [ ] グローバルメモリ（/remember コマンド）
- [ ] スラッシュコマンド（/english, /japanese, /memory, /clear, /help）
- [ ] SQLite永続化（GRDB.swift）
- [ ] 初回モデルダウンロード画面（プログレスバー付き）
- [ ] 設定画面（モデル・記憶設定）
- [ ] 音声入力（SFSpeechRecognizer、オフライン認識）

### Should Have（できれば）
- [ ] Catppuccin テーマ（ダーク/ライト自動切替）
- [ ] 多言語対応（JA/EN/ES）
- [ ] コマンドサジェスト（/ 入力時に候補表示）
- [ ] モデル管理画面（他モデルの追加・切替）

### Out of Scope（今回対象外）
- クラウドAI（Claude/Gemini/OpenAI）への接続
- Mac版との同期
- 課金・サブスクリプション機能
- iPad対応

---

## 4. データベーススキーマ（Mac版から流用）

```sql
sessions        (id, title, created_at, updated_at)
messages        (id, role, content, created_at, session_id)
memory_summaries(id, summary, message_count, created_at, session_id)
user_commands   (id, name, description, prompt_template, created_at, updated_at)
global_memory   (id, content, source, created_at)
```
参照: `backend/memory_manager.py`（移植元）

---

## 5. 画面設計

```
TabBar（3タブ）
├── 💬 チャット（メイン）
│   ├── NavigationSplitView
│   │   ├── セッション一覧（左）
│   │   │   ├── 新規チャットボタン
│   │   │   ├── セッションセル（タイトル + 日時）
│   │   │   └── 🧠 記憶バッジ（件数表示）
│   │   └── チャット画面（右）
│   │       ├── メッセージバブル（ユーザー青 / AI紫）
│   │       ├── 推論中インジケーター（TypingIndicator）
│   │       ├── コマンドサジェスト（/ 入力時）
│   │       └── テキスト入力 + 送信ボタン + 🎤マイクボタン
│   └── 初回起動: モデルダウンロード画面（プログレスバー）
│
├── ⚙️ 設定
│   ├── モデル設定（使用モデル・量子化レベル）
│   ├── 記憶設定（圧縮タイミング N往復）
│   ├── グローバルメモリ一覧・編集
│   ├── コマンド管理
│   ├── 言語設定（JA/EN/ES）
│   └── アプリ情報・ライセンス
│
└── 📦 モデル管理
    ├── インストール済みモデル一覧
    ├── おすすめモデル（Gemma 3 1B / Llama 3.2 1B / Qwen 3 0.6B）
    └── ダウンロード進捗バー
```

---

## 6. 開発フェーズ計画

### Phase 1: 基盤構築（目安 2〜3週間）
**目標:** テキストを入力するとGemma 3 1Bが返答する最小動作版

| # | タスク | 詳細 |
|---|---|---|
| P1-1 | Xcodeプロジェクト作成 | `MemoriaApp`、SwiftUI、iOS 17 |
| P1-2 | LLM.swift SPM導入 | Package URL追加、ビルド確認 |
| P1-3 | Gemma 3 1B PoC | シミュレーター / 実機でモデル推論確認 |
| P1-4 | GRDB.swift 導入 + スキーマ実装 | Mac版スキーマをSwiftに移植 |
| P1-5 | 基本チャットUI（SwiftUI） | バブル表示・入力エリア |
| P1-6 | LLM ↔ チャット接続 | ストリーミング出力 |

**フェーズ完了条件:** 実機でGemma 3 1Bと会話ができる

---

### Phase 2: 記憶機能（目安 1〜2週間）
**目標:** Mac版の記憶システムをSwiftに移植

| # | タスク | 参照元 |
|---|---|---|
| P2-1 | セッション管理 | `memory_manager.py` |
| P2-2 | 記憶圧縮ロジック | `compress_session_memory()` |
| P2-3 | グローバルメモリ（/remember） | `get_global_memory()` |
| P2-4 | スラッシュコマンドシステム | `command_manager.py` |

---

### Phase 3: UI完成（目安 1〜2週間）
**目標:** 製品品質のUIに仕上げる

| # | タスク | 詳細 |
|---|---|---|
| P3-1 | Catppuccin テーマ | Mocha（dark）/ Latte（light）自動切替 |
| P3-2 | モデルダウンロード画面 | 初回セットアップ、プログレスバー |
| P3-3 | 設定画面 | モデル・記憶・コマンド管理 |
| P3-4 | 多言語対応 | JA/EN/ES（Mac版辞書をLocalizable.stringsに移植） |

---

### Phase 4: 音声入力 + 仕上げ（目安 1週間）
**目標:** App Store提出できる状態に

| # | タスク | 詳細 |
|---|---|---|
| P4-1 | 音声入力実装 | SFSpeechRecognizer（requiresOnDeviceRecognition=true） |
| P4-2 | オフライン動作確認 | 機内モードでの全機能テスト |
| P4-3 | パフォーマンス最適化 | メモリ・速度チューニング |
| P4-4 | App Store申請準備 | プライバシーポリシー・スクリーンショット |
| P4-5 | TestFlight配布 → App Store申請 | |

---

## 7. リスク管理

| リスク | 対策 |
|---|---|
| iPhone 12でGemma 3 1Bが重い | Qwen 3 0.6B または Llama 3.2 1B に切替 |
| LLM.swift SPM導入が失敗 | llama.cpp直接バインディングに切替 |
| App StoreでモデルDL方式が審査却下 | モデル同梱（On-Demand Resources）に変更 |
| メモリ不足でOOMクラッシュ | Q4量子化 + KVキャッシュ最適化（q4_0） |

---

## 8. 参考リソース

| 名前 | URL |
|---|---|
| LLM.swift | https://github.com/eastriverlee/LLM.swift |
| GRDB.swift | https://github.com/groue/GRDB.swift |
| Gemma 3 1B GGUF | https://huggingface.co/bartowski/gemma-3-1b-it-GGUF |
| Mac版 GitHub | https://github.com/daichi1783/ollama-memory-chat |
| Mac版 Notion仕様書 | https://www.notion.so/34287581c00f81c2a8dae48186a6299d |
| iPhone版 Notion引き継ぎ | https://www.notion.so/34287581c00f81ddb12adcb38f69b7db |

---

*最終更新: 2026-04-16 — モデル調査完了・音声入力方針（SFSpeechRecognizer）確定*
