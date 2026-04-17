# Memoria for iPhone — iOS開発セッション引き継ぎ書

> **このファイルを読めば iOS 開発を即座に再開できます。**
> 新しいセッション開始時は **必ずこのファイルを最初に読んでください。**

---

## 環境構築ステータス（2026-04-17 更新）

| 項目 | 状態 | 内容 |
|---|---|---|
| Xcodeプロジェクト | ✅ 作成済み | `Memoria`、SwiftUI、iOS 17、com.daichi.memoria |
| LLM.swift | ✅ ローカルパッケージ化 | `LocalLLM/`（KVキャッシュバグ修正パッチ永続化済み） |
| GRDB.swift | ✅ 追加済み | SPM（リモート） |
| 全Phaseコード | ✅ 作成済み | `MemoriaApp/` に全14ファイル |
| Gemma 3 1B モデル | ⬜ 未ダウンロード | 初回ビルド時にアプリ内でDL |

> **Xcodeプロジェクトの場所:**
> `/Users/daichi/Documents/Claude/Projects/memoria-ios/Memoria/Memoria.xcodeproj`
>
> **Phase 1 Swiftコードの場所:**
> `~/Documents/Claude/Projects/ollamaメモリ機能PJ/ollama-memory-chat/MemoriaApp/Memoria/`
>
> **セットアップガイド:**
> `~/Documents/Claude/Projects/ollamaメモリ機能PJ/ollama-memory-chat/MemoriaApp/SETUP_GUIDE.md`

---

## 現在のフェーズ

**Phase 1: 基盤構築** — ✅ 完了（2026-04-16 ビルド成功）

| # | タスク | 状態 |
|---|---|---|
| P1-1 | Xcodeプロジェクト作成 | ✅ 完了 |
| P1-2 | LLM.swift + GRDB.swift SPM導入 | ✅ 完了 |
| P1-3 | LLM推論エンジン実装（LLMService.swift） | ✅ 完了 |
| P1-4 | SQLite スキーマ実装（DatabaseModels + DatabaseService） | ✅ 完了 |
| P1-5 | 基本チャットUI（ContentView + ChatView） | ✅ 完了 |
| P1-6 | LLM ↔ チャット接続 + 記憶・コマンド（ChatService） | ✅ 完了 |
| P1-7 | Xcodeへのファイル統合 & ビルドテスト | ✅ 完了（BUILD SUCCEEDED） |

### Phase 1 ビルド時の修正履歴
- **GRDB-dynamic削除**: GRDB と GRDB-dynamic の両方がSPMに入っていて競合 → project.pbxproj から GRDB-dynamic を除去
- **LLMService.swift修正**: LLM.swift の実際のAPIに合わせて修正
  - `init` が `async throws` → `try await` に変更
  - `respond(to:with:)` のAsyncStreamベースAPI に合わせた
  - テンプレート変更を `llm.template = .chatML(...)` に修正

---

**Phase 2: 記憶機能の完成** — ✅ 完了（2026-04-16 ビルド成功・warning 0）

| # | タスク | 状態 |
|---|---|---|
| P2-1 | セッション一覧画面（SessionListView.swift 新規） | ✅ 完了 |
| P2-2 | NavigationSplitView統合（ContentView改修） | ✅ 完了 |
| P2-3 | セッション切替・削除・検索 | ✅ 完了 |
| P2-4 | ユーザー定義コマンドCRUD（/addcommand, /deletecommand, /commands） | ✅ 完了 |
| P2-5 | ChatView UIリッチ化（Markdown, タイピングインジケータ, iMessageバブル, ハプティクス） | ✅ 完了 |
| P2-6 | DatabaseService改善（WALモード, インデックス, v2マイグレーション） | ✅ 完了 |
| P2-7 | LLMService改善（メモリ監視, バックグラウンド対応, 推論キャンセル） | ✅ 完了 |
| P2-8 | ChatService改善（プロンプトインジェクション防御, セッション管理） | ✅ 完了 |
| P2-9 | ビルドテスト & warning修正 | ✅ 完了（BUILD SUCCEEDED, 0 warnings） |

### Phase 2 で追加・変更したファイル

| ファイル | 変更種別 | 内容 |
|---|---|---|
| Views/SessionListView.swift | **新規** | セッション一覧・検索・スワイプ削除・新規作成ボタン |
| Views/ContentView.swift | 改修 | NavigationSplitView化、.paused状態対応 |
| Views/ChatView.swift | 大幅改修 | iMessageバブル、タイピングインジケータ、簡易Markdown、ハプティクス |
| Services/DatabaseService.swift | 大幅改修 | WALモード、エラーenum、セッションプレビュー、ユーザーコマンドCRUD、v2マイグレーション |
| Services/ChatService.swift | 大幅改修 | セッション管理、プロンプトインジェクション防御、ユーザー定義コマンド |
| Services/LLMService.swift | 改修 | メモリ監視、バックグラウンド対応、推論キャンセル、UIKit import |
| Models/DatabaseModels.swift | 変更なし | Phase 1のまま |
| MemoriaApp.swift | 変更なし | Phase 1のまま |

### Phase 2 ビルド時の修正履歴
- **UIKit未インポート**: LLMService.swiftで`UIApplication`を使用 → `import UIKit`追加
- **.paused未処理**: ContentView.swiftのswitch文 → `.paused`ケースを`.ready, .generating`と同列に追加
- **Swift 6 concurrencyワーニング**: NotificationCenter/Timer/download closureの`[weak self]`キャプチャ修正
- **nil coalescing不要警告**: `error.localizedDescription`は非オプショナル → `?? "不明なエラー"`削除
- **var→let**: DatabaseServiceの5つの変数をlet定数に変更

---

**Phase 3: UI完成** — ✅ 完了（2026-04-16 ビルド成功・warning 0）

| # | タスク | 状態 |
|---|---|---|
| P3-1 | ThemeManager（Catppuccin Mocha/Latte切り替え） | ✅ 完了 |
| P3-2 | 設定画面（SettingsView） | ✅ 完了 |
| P3-3 | モデル管理画面（ModelManagementView） | ✅ 完了 |
| P3-4 | 多言語対応（LocalizationService: JA/EN/ES） | ✅ 完了 |
| P3-5 | 全Viewのハードコード色をテーマシステムに移行 | ✅ 完了 |
| P3-6 | MemoriaApp.swiftにThemeManager注入 | ✅ 完了 |
| P3-7 | ビルドテスト & warning修正 | ✅ 完了（BUILD SUCCEEDED, 0 warnings） |

### Phase 3 で追加・変更したファイル

| ファイル | 変更種別 | 内容 |
|---|---|---|
| Theme/ThemeManager.swift | **新規** | Catppuccin Mocha/Latte全色定義、テーマ切り替え、UserDefaults永続化 |
| Views/SettingsView.swift | **新規** | 外観・モデル・記憶・言語・アプリ情報の5セクション設定画面 |
| Views/ModelManagementView.swift | **新規** | モデル一覧カード、メモリゲージ、ダウンロード進捗、切り替えUI |
| Services/LocalizationService.swift | **新規** | JA/EN/ES 30キーの多言語辞書、UserDefaults永続化 |
| MemoriaApp.swift | 改修 | ThemeManager注入、preferredColorScheme連動 |
| Views/ContentView.swift | 改修 | 全Color(hex:)をtheme.colors.xxxに置換 |
| Views/ChatView.swift | 改修 | 全Color(hex:)をtheme.colors.xxxに置換 |
| Views/SessionListView.swift | 改修 | 全Color(hex:)をtheme.colors.xxxに置換、設定ボタン追加 |

### Phase 3 ビルド時の修正履歴
- **AppLanguage重複定義**: SettingsViewとLocalizationServiceの両方で定義 → SettingsView側を削除
- **Combine未インポート**: MemberImportVisibility有効のためLocalizationServiceにimport Combine追加
- **不要なawait**: ModelManagementViewのunloadModel()にawait不要 → 削除

---

**Phase 4: 音声・仕上げ** — ✅ 完了（2026-04-16 ビルド成功・warning 0）

| # | タスク | 状態 |
|---|---|---|
| P4-1 | 音声入力サービス（VoiceInputService: SFSpeechRecognizer オフライン） | ✅ 完了 |
| P4-2 | ChatViewに音声入力UI統合（パルスアニメーション、ライブ文字起こし） | ✅ 完了 |
| P4-3 | アニメーション付き起動画面（LaunchScreenView） | ✅ 完了 |
| P4-4 | MemoriaApp.swiftライフサイクル改善（起動画面、LocalizationService注入） | ✅ 完了 |
| P4-5 | パフォーマンス最適化（トークン速度計測、生成タイムアウト120秒） | ✅ 完了 |
| P4-6 | オフライン堅牢性（モデルキャッシュ確認、DB統計、DBエクスポート） | ✅ 完了 |
| P4-7 | セッション管理強化（チャットエクスポート、下書き保存、500件警告） | ✅ 完了 |
| P4-8 | 古いセッション自動クリーンアップ（90日超を削除） | ✅ 完了 |
| P4-9 | ビルドテスト & warning修正 | ✅ 完了（BUILD SUCCEEDED, 0 warnings） |

### Phase 4 で追加・変更したファイル

| ファイル | 変更種別 | 内容 |
|---|---|---|
| Services/VoiceInputService.swift | **新規** | SFSpeechRecognizer オフライン音声入力、JA/EN/ES対応 |
| Views/LaunchScreenView.swift | **新規** | Catppuccin Mocha アニメーション起動画面（回転リング3重） |
| MemoriaApp.swift | 改修 | 起動画面フェーズ、LocalizationService注入、scenePhase監視 |
| Views/ChatView.swift | 改修 | 音声入力ボタン統合（パルスアニメ、ライブ文字起こし） |
| Services/DatabaseService.swift | 改修 | DBエクスポート、統計取得、古セッションクリーンアップ |
| Services/LLMService.swift | 改修 | トークン速度計測、モデルキャッシュ確認、生成タイムアウト |
| Services/ChatService.swift | 改修 | チャットエクスポート、下書き保存、500件メッセージ警告 |

### Phase 4 ビルド時の修正履歴
- **guard body fallthrough**: VoiceInputServiceのguard文をif文に変更
- **iOS 17非推奨API**: `AVAudioSession.recordPermission` → `AVAudioApplication.shared.recordPermission`に更新

**全Phase完了 — 実機テスト準備完了！**

---

## バグ修正セッション（2026-04-17）— 継続チャット不具合の完全修正

### 問題
2通目以降のメッセージで「[応答を生成できませんでした]」が表示される。

### 根本原因
llama.cpp の KV キャッシュが前回の生成パス（positions 0..M+K-1）を保持したまま。
2回目の `llama_decode` 呼び出し時にスタントスロットと競合して非ゼロを返す
→ `prepareContext()` が false → トークン数 0 → 空応答。

### 修正内容（LocalLLM/Sources/LLM/LLM.swift）

```swift
// LLMCore クラス内に追加
private var hasPreviousContext = false

// prepareContext() 内 tokenBuffer.removeAll() の直前に追加
if hasPreviousContext {
    llama_memory_seq_rm(llama_get_memory(context), 0, -1, -1)
}
hasPreviousContext = true
```

- **1回目**: `hasPreviousContext = false` → `seq_rm` をスキップ（空コンテキストに対して呼ぶと内部状態が壊れる）
- **2回目以降**: `seq_rm` でスタントスロットを削除 → `llama_decode` がクリーンに動作

### LLM.swift のローカルパッケージ化（パッチの永続化）

修正を DerivedData に直接当てると Xcode が消去する可能性があるため、ローカル SPM パッケージとして永続化。

| パス | 内容 |
|---|---|
| `../LocalLLM/` | ローカル SPM パッケージルート |
| `../LocalLLM/Sources/LLM/LLM.swift` | パッチ済み LLM.swift |
| `../LocalLLM/llama.cpp/llama.xcframework` | llama.cpp バイナリ（323MB） |
| `../LocalLLM/Package.swift` | SPM マニフェスト |

`project.pbxproj` の LLM 参照を `XCLocalSwiftPackageReference`（`relativePath = ../LocalLLM`）に変更。
`Package.resolved` から `llm.swift` のリモートエントリを削除済み。

### その他の修正（同セッション）

| ファイル | 修正内容 |
|---|---|
| LLMService.swift | `maxTokenCount: 2048 → 4096`（コンテキスト拡大） |
| LLMService.swift | デバッグログ削除（リリース品質） |
| LLMService.swift | `[weak self] responseStream in / guard let self` → `responseStream in`（0 warnings達成） |
| ChatService.swift | `historyMessages.suffix(6)` 追加（トークンオーバーフロー防止） |

### ビルド確認
- シミュレーター: `BUILD SUCCEEDED`（0 warnings）
- 実機（`generic/platform=iOS`）: `BUILD SUCCEEDED`（0 warnings）

---

## 包括的デバッグ監査（2026-04-17）— 全14ファイル精査・追加バグ修正

### 背景
マイクボタンクラッシュ修正後、全ソースファイルを体系的に精査。

### 精査した全14ファイル
MemoriaApp.swift / ContentView / ChatView / SessionListView / SettingsView / ModelManagementView / LaunchScreenView / DatabaseModels / DatabaseService / LLMService / ChatService / VoiceInputService / LocalizationService / ThemeManager

### 追加で発見・修正したバグ

| # | ファイル | バグ内容 | 深刻度 |
|---|---|---|---|
| Bug #5 | ChatView.swift | `Timer.scheduledTimer(repeats: true)` の戻り値を破棄 → タイマーが永続動作（メモリリーク/バッテリードレイン） | 🔴 中 |
| Bug #6 | DatabaseService.swift | `cleanupOldSessions()` で `Calendar.date()!` 強制アンラップ | 🟡 低 |
| Bug #7 | ContentView.swift | `llmService` が `SessionListView` の環境に未注入（一貫性の問題） | 🟡 低 |

**修正内容（Bug #5）:**
```swift
// 修正前: Timer戻り値を破棄
Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { _ in ... }

// 修正後: @State に保存、onDisappear で invalidate
@State private var placeholderTimer: Timer?
placeholderTimer = Timer.scheduledTimer(...)
// body に追加:
.onDisappear { placeholderTimer?.invalidate(); placeholderTimer = nil }
```

**修正内容（Bug #6）:**
```swift
// 修正前
let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
// 修正後
guard let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else { return 0 }
```

**修正内容（Bug #7）:**
```swift
// ContentView.mainSplitView に追加
SessionListView()
    .environmentObject(chatService)
    .environmentObject(llmService)  // ← 追加
```

### 「問題なし」と判断したファイル（理由付き）
- **SessionListView**: NavigationLink で ChatView に `.environmentObject(LLMService.shared)` を明示的に渡している ✅
- **SettingsView**: llmService と db は `@StateObject` で直接取得（EnvironmentObject不要）✅
- **ModelManagementView**: 現時点で遷移パスがない（SettingsView は placeholder を表示）✅
- **LaunchScreenView**: ThemeManager を使わず色をハードコード（設計上の意図あり）、`repeatForever` アニメは SwiftUI が管理するためリークなし ✅
- **ThemeManager / LocalizationService**: `@Published` と UserDefaults の同期が正しく実装 ✅

### GitHub コミット
| ハッシュ | 内容 |
|---|---|
| `39fc947` | fix: タイマーリーク・force-unwrap修正（包括的デバッグ監査） |
| `7f6f552` | fix: ContentView - llmService を環境オブジェクトとして注入 |

### ビルド確認
```
** BUILD SUCCEEDED ** / Warnings: 0 / Errors: 0
Target: Memoria (generic/platform=iOS)
```

---

## Phase 1 で作成したファイル一覧

```
MemoriaApp/Memoria/                  14ファイル（全Phase完了）
├── MemoriaApp.swift              ← エントリーポイント（起動画面、テーマ・多言語注入）
├── Models/
│   └── DatabaseModels.swift      ← GRDBデータモデル（5テーブル）
├── Theme/
│   └── ThemeManager.swift        ← Catppuccin Mocha/Latte テーマシステム
├── Views/
│   ├── ContentView.swift         ← メイン画面（NavigationSplitView）
│   ├── ChatView.swift            ← チャットUI（バブル、Markdown、音声入力）
│   ├── SessionListView.swift     ← セッション一覧（検索、削除、設定）
│   ├── SettingsView.swift        ← 設定画面
│   ├── ModelManagementView.swift ← モデル管理画面
│   └── LaunchScreenView.swift    ← アニメーション起動画面（Phase 4新規）
└── Services/
    ├── DatabaseService.swift     ← SQLite（記憶圧縮、エクスポート、統計、クリーンアップ）
    ├── LLMService.swift          ← LLM推論（速度計測、タイムアウト、キャッシュ確認）
    ├── ChatService.swift         ← チャット統合（コマンド、下書き保存、エクスポート）
    ├── LocalizationService.swift ← 多言語 JA/EN/ES
    └── VoiceInputService.swift   ← オフライン音声入力（Phase 4新規）
```

---

## Phase 6: クラウドAI対応 — ✅ 完了（2026-04-17）

| # | タスク | 状態 |
|---|---|---|
| P6-1 | KeychainService（APIキー暗号化保管・CRUD） | ✅ 完了 |
| P6-2 | CloudLLMService（OpenAI / Claude / Gemini SSEストリーミング） | ✅ 完了 |
| P6-3 | LLMService拡張（ModelType+6クラウドモデル、クラウドルーティング） | ✅ 完了 |
| P6-4 | APIKeySetupView（貼り付け入力UI・形式チェック・Keychain保存） | ✅ 完了 |
| P6-5 | ModelManagementView再設計（ローカル+クラウド統合一覧） | ✅ 完了 |

### Phase 6 で追加・変更したファイル

| ファイル | 変更種別 | 内容 |
|---|---|---|
| Services/KeychainService.swift | **新規** | APIProvider enum（Gemini/Claude/OpenAI）、iOSキーチェーンCRUD |
| Services/CloudLLMService.swift | **新規** | OpenAI/Claude/Gemini SSEストリーミング（URLSession.bytes） |
| Services/LLMService.swift | **改修** | ModelType拡張（6クラウドモデル）、generateCloud()、stopGeneration()更新 |
| Views/APIKeySetupView.swift | **新規** | APIキー貼り付け入力シート（SecureField、クリップボード貼付、形式検証） |
| Views/ModelManagementView.swift | **全面改修** | ローカル/クラウド2セクション構成、プロバイダーグループ、オフライン検知 |

### Phase 6 で対応したクラウドモデル

| プロバイダー | モデル | モデルID |
|---|---|---|
| Google Gemini | Gemini 2.0 Flash | gemini-2.0-flash |
| Google Gemini | Gemini 1.5 Pro | gemini-1.5-pro |
| Anthropic | Claude Haiku | claude-haiku-4-5-20251001 |
| Anthropic | Claude Sonnet | claude-sonnet-4-6 |
| OpenAI | GPT-4o mini | gpt-4o-mini |
| OpenAI | GPT-4o | gpt-4o |

### Phase 6 アーキテクチャ

- **BYOKモデル**: ユーザーが自分のAPIキーを持ち込む（開発者課金なし）
- **安全保管**: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`（デバイスローカルのみ）
- **SSEストリーミング**: `URLSession.shared.bytes(for:).lines` で全プロバイダー共通実装
- **ネットワーク監視**: `NWPathMonitor` + `AsyncStream` でオフライン時クラウドモデルをグレーアウト

### ⚠️ Xcode への手動追加が必要なファイル（3ファイル）

Cowork からファイルは作成済みですが、Xcode プロジェクトへの追加は手動で行う必要があります。

**手順:**
1. Xcode でプロジェクトを開く
2. 左サイドバーの `Memoria/Services/` グループを右クリック → "Add Files to Memoria..."
3. 以下の2ファイルを選択して追加：
   - `KeychainService.swift`
   - `CloudLLMService.swift`
4. 同様に `Memoria/Views/` グループに追加：
   - `APIKeySetupView.swift`
5. Cmd+B でビルド確認

---

## 次のセッションで最初にやること

**次のステージ: App Store 申請（Phase 5〜6 完了後）**

### ⚠️ Xcode 手動作業（ビルドの前に必須）

| # | 作業 | 内容 |
|---|---|---|
| 1 | Phase 6 ファイル追加 | KeychainService.swift + CloudLLMService.swift（Services/）, APIKeySetupView.swift（Views/）を Xcode プロジェクトに追加 |
| 2 | Phase 5 ファイル追加 | OnboardingView.swift（Views/）を Xcode プロジェクトに追加 |
| 3 | アイコン設定 | `setup_phase5.sh` 実行 → `memoria_ios_icons/Contents.json` を AppIcon.appiconset にコピー |
| 4 | ビルド確認 | Cmd+B → BUILD SUCCEEDED を確認 |

### 残作業（Daichi が手動で行うもの）
- [ ] Xcode に Phase 6 の3ファイル（上記）を追加
- [ ] Xcode に OnboardingView.swift を追加
- [ ] `setup_phase5.sh` を実行してアイコンを Xcode にコピー
- [ ] App Store Connect でアプリを登録（APPSTORE_GUIDE.md 参照）
- [ ] privacy_policy.html を GitHub Pages で公開
- [ ] スクリーンショット撮影（シミュレーター）
- [ ] TestFlight でベータテスト実施

### Info.plist に追加必要なキー
```xml
<key>NSMicrophoneUsageDescription</key>
<string>音声入力に使用します</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>オフラインでの音声認識に使用します</string>
```

### 実機での最終動作確認手順
1. iPhoneをMacに接続 → Xcode でデバイスを選択
2. Cmd+R でビルド＆実機インストール
3. 初回起動: モデルダウンロード（Wi-Fi必要、約600MB）
4. **2通目以降のメッセージで応答が返るか確認**（修正済みのKVキャッシュ）
5. 機内モードでのオフライン動作確認
6. 音声入力テスト（マイク許可ダイアログ）
7. セッション管理、記憶圧縮、テーマ切替の動作確認

---

## Phase 1 で実装済みの機能詳細

### LLM推論（LLMService.swift）
- HuggingFaceモデル自動ダウンロード（初回Wi-Fi必要）
- Gemma 3 1B Q4_K_M（全端末対応）
- Gemma 4 E2B Q4_K_M（iPhone 16以降、RAM 6GB超）
- デバイス自動判定（`ProcessInfo.physicalMemory`）
- ストリーミングトークン生成
- システムプロンプト動的更新（記憶注入用）

### データベース（DatabaseService.swift + DatabaseModels.swift）
- GRDB.swift によるSQLite管理
- 5テーブル: sessions, messages, memory_summaries, global_memory, user_commands
- マイグレーション付き（v1_initial）
- 記憶圧縮判定（shouldCompress: N往復ごと）
- システムプロンプトビルダー（グローバルメモリ＋セッションサマリー注入）

### チャットUI（ChatView.swift）
- Catppuccin Mocha ダークテーマ
- メッセージバブル（ユーザー: 青、AI: Surface0）
- ストリーミング表示（トークンごとにリアルタイム更新）
- コマンドサジェスト（`/` 入力時にポップアップ）
- モデル状態バッジ（接続状態表示）
- 空状態のウェルカム画面

### スラッシュコマンド（ChatService.swift）
- `/english [テキスト]` — 日→英翻訳
- `/japanese [テキスト]` — 英→日翻訳
- `/spanish [テキスト]` — 日→西翻訳
- `/cal [テキスト]` — 文法・表現チェック
- `/remember [内容]` — グローバルメモリに保存
- `/memory` — 記憶一覧表示
- `/clear` — セッションリセット
- `/help` — コマンドヘルプ

### 記憶圧縮（ChatService.swift + DatabaseService.swift）
- Mac版 `memory_manager.py` の `compress_session_memory()` を移植
- 10往復（20メッセージ）ごとに自動圧縮
- 直近30メッセージをLLMで200文字以内に要約
- 前回サマリーをコンテキストとしてインクリメンタル要約
- グローバルメモリ＋セッションサマリーをシステムプロンプトに注入

---

## 技術スタック（確定）

| 層 | 技術 | バージョン |
|---|---|---|
| UI | SwiftUI | iOS 17+ |
| LLM推論 | LLM.swift | 1.8.0 |
| DB | GRDB.swift | SPM最新 |
| デフォルトモデル | Gemma 3 1B Q4_K_M | ~600MB |
| 高性能モデル | Gemma 4 E2B Q4_K_M | ~1.3GB（iPhone 16以降） |
| 音声入力 | SFSpeechRecognizer | オフラインon-device認識（JA/EN/ES） |
| テーマ | Catppuccin Mocha/Latte | ThemeManagerで切り替え可能 |
| 多言語 | LocalizationService | JA/EN/ES 30キー |

---

## 今後のロードマップ

### Phase 2: 記憶機能の完成 — ✅ 完了（2026-04-16）
- セッション一覧画面（SessionListView + NavigationSplitView）
- セッション切替・削除・検索
- ユーザー定義コマンド（CRUD: /addcommand, /deletecommand, /commands）
- ChatView大幅リッチ化（Markdown, タイピングインジケータ, ハプティクス）
- DatabaseService改善（WAL, インデックス, v2マイグレーション）
- LLMService改善（メモリ監視, バックグラウンド対応, 推論キャンセル）
- プロンプトインジェクション防御

### Phase 3: UI完成 — ✅ 完了（2026-04-16）
- ThemeManager（Catppuccin Mocha/Latte全色定義 + 切り替え + UserDefaults永続化）
- 設定画面（外観・モデル・記憶・言語・アプリ情報）
- モデル管理画面（カードUI、メモリゲージ、ダウンロード進捗）
- 多言語対応（LocalizationService: JA/EN/ES 30キー）
- 全Viewのハードコード色をテーマシステムに移行

### Phase 4: 音声・仕上げ — ✅ 完了（2026-04-16）
- SFSpeechRecognizer オフライン音声入力（JA/EN/ES対応）
- アニメーション起動画面（Catppuccin Mocha 3重回転リング）
- トークン速度計測、生成タイムアウト120秒
- モデルキャッシュ確認、DBエクスポート、古セッションクリーンアップ
- チャットエクスポート、下書き保存、500件メッセージ警告

---

## PMとしての開発方針（重要）

- **Daichiへの報告・相談はCoworkセッションで行う**
- **実際のコーディングはCursorまたはClaude Codeで自律的に進める**
- Daichiはコーディング素人だがターミナル操作は可能
- 複雑なターミナル操作は手順を丁寧に説明する
- フェーズ完了ごとにDaichiに報告・レビューをもらう

---

## 参考リソース

| 名前 | URL |
|---|---|
| LLM.swift README | https://github.com/eastriverlee/LLM.swift |
| GRDB.swift README | https://github.com/groue/GRDB.swift |
| Gemma 3 1B GGUF | https://huggingface.co/bartowski/gemma-3-1b-it-GGUF |
| Gemma 4 E2B GGUF | https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF |
| Mac版コード（設計参照用） | ~/Documents/Claude/Projects/ollamaメモリ機能PJ/ollama-memory-chat |
| Mac版 memory_manager.py | backend/memory_manager.py（記憶圧縮ロジック） |
| Mac版 command_manager.py | backend/command_manager.py（スラッシュコマンド） |

---

*作成: 2026-04-16 — 環境構築完了時点*
*更新: 2026-04-16 — Phase 1 コード完成（P1-3〜P1-6）*
*更新: 2026-04-16 — Phase 1 ビルド成功（P1-7）*
*更新: 2026-04-16 — Phase 2 完了（記憶機能・UI改善・ビルド成功 0 warnings）*
*更新: 2026-04-16 — Phase 3 完了（テーマ・設定・モデル管理・多言語・ビルド成功 0 warnings）*
*更新: 2026-04-16 — Phase 4 完了（音声入力・起動画面・パフォーマンス最適化・ビルド成功 0 warnings）*
*更新: 2026-04-17 — バグ修正（継続チャット KVキャッシュ修正・LocalLLM ローカルパッケージ化・0 warnings）*
*更新: 2026-04-17 — 包括的デバッグ監査（全14ファイル精査・Bug #5-#7修正・BUILD SUCCEEDED 0 warnings）*
*更新: 2026-04-17 — Phase 5 完了（アイコン・メタデータ・免責事項・プライバシーポリシー作成）*
*更新: 2026-04-17 — Phase 6 完了（クラウドAI対応: Gemini / Claude / OpenAI BYOK・SSEストリーミング・Keychain保管）*
*次のステージ: App Store 申請（Xcode手動ファイル追加 → BUILD SUCCESS → TestFlight → 申請）*
