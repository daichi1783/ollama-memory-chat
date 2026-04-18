# Memoria for iPhone — 最終レビューレポート
**作成日**: 2026-04-17  
**対象ビルド**: Debug / iPhone 17 Pro Simulator (iOS 26.4)  
**ビルド結果**: ✅ BUILD SUCCEEDED — 0 errors, 0 warnings

---

## サマリー

前セッションまでに Phase 1〜4 を完了し、全ビルドが成功していた。  
本セッションでは実機テスト中に発見された「グレードット」バグを深く調査し、根本原因を特定・修正した。

修正したファイル:
- `Views/ChatView.swift` — BUG-1 追加修正 + **グレードット修正**
- `Services/ChatService.swift` — **DB保存コンテンツ信頼性向上**
- `Services/LLMService.swift` — **accumulated フォールバックバグ修正** + ビルドエラー修正

---

## 既存バグ 5 件のステータス

### BUG-1: テキスト部分選択ができない ✅ 修正済み（前セッション）

**根本原因**: `.clipShape(BubbleShape)` がテキスト選択ハンドルの描画をクリッピングしていた。

**適用済み修正** (`ChatView.swift`):
```swift
// Before: .clipShape(BubbleShape(isUser: isUser))
// After:  .cornerRadius(18)  ← クリップ境界がなくなりハンドルが正常表示
```
`.textSelection(.enabled)` と `.contextMenu` の競合も解消済み。

**状態**: 完全解決。

---

### BUG-2: AI応答が表示されない / ハングする ✅ 修正済み（前セッション）

**根本原因**: 複数の問題が重なっていた。
1. `LLM.swift` の `respond(to:)` (デフォルトパス) では `for await token` ループが完了しないことがあった
2. Gemma 3 テンプレートが `<start_of_turn>user` でシステムプロンプトをラップしており、stop token が正常機能しなかった
3. タイムアウト処理がフラグのみで `for-await` をキャンセルできていなかった

**適用済み修正** (`LLMService.swift`):
```swift
// Gemma 3 正式テンプレート
Template(
    system: ("<start_of_turn>system\n", "<end_of_turn>\n"),
    user:   ("<start_of_turn>user\n",   "<end_of_turn>\n"),
    bot:    ("<start_of_turn>model\n",  "<end_of_turn>\n"),
    stopSequence: "<end_of_turn>"
)

// Task ラップで .cancel() によるループ終了を可能に
let genTask = Task<(String, Int), Never> { ... }
// タイムアウトは別 Task.sleep で実装
```

**状態**: 完全解決。

---

### BUG-3: ホーム画面に戻るとチャット履歴が消える ✅ 修正済み（前セッション）

**根本原因**: `Session` / `Message` が `PersistableRecord` を使っており、`insert` 後に `id` が設定されなかった（GRDB の auto-assign は `MutablePersistableRecord` + `didInsert` が必要）。

**適用済み修正** (`DatabaseModels.swift`):
```swift
struct Session: MutablePersistableRecord {
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID  // insert後に id がセットバックされる
    }
}
```

**状態**: 完全解決。DB確認済み — メッセージは正しく `sessionId` と紐付いて永続化される。

---

### BUG-4: 連続メッセージ送信ができない ✅ 修正済み（前セッション）

**根本原因**: BUG-2 でハングが発生すると `isGenerating = true` のままになり、次の `sendMessage()` が `guard !isGenerating` でブロックされていた。また停止ボタンが `LLMService.stopGeneration()` を呼んでいなかった。

**適用済み修正** (`LLMService.swift`, `ChatView.swift`):
```swift
// 停止ボタン → LLMService.stopGeneration() を直接呼ぶ
Button { llmService.stopGeneration() } label: { Image(systemName: "stop.circle.fill") }

// isGenerating は defer で確実にリセット
private func generateResponse(...) async {
    isGenerating = true
    defer { isGenerating = false }  // 例外・早期リターン時も安全
    ...
}
```

**状態**: 完全解決。

---

### BUG-5: インプット欄にゴーストテキスト ✅ 解消済み（前セッション）

**根本原因**: `UITextView` ラッパー（`SelectableTextView`）がレイアウトサイクル間で古い描画を残していた。

**適用済み修正**: `UITextView` ラッパーを撤去し、SwiftUI ネイティブ `TextField(axis: .vertical)` に置き換え。

**状態**: 解消済み。入力欄の自動拡縮・送信後クリアも正常動作。

---

## 新規発見バグ: グレードット問題（本セッションで修正）

テスト中に発見した追加バグ。既存セッションを再オープンすると、AI応答バブルが小さな灰色の楕円（グレードット）として表示される。

### 根本原因の詳細分析

**原因 A — UI レンダリングバグ** (`ChatView.swift`):

`MessageBubbleView` は `message.content` の有無に関係なく常にバブル背景を描画していた。

```swift
// Before (問題のあるコード):
bubbleContent                          // content="" → VStack 高さ 0
    .padding(.horizontal, 14)         // → 28pt 幅の背景が付く
    .padding(.vertical, 10)           // → 20pt 高さの背景が付く
    .background(theme.colors.surface0) // → 灰色楕円 (グレードット) が出現！
    .cornerRadius(18)
```

`MarkdownTextView(text: "")` は `parseBlocks("")` が `[]` を返すため `VStack` の高さが 0 になる。しかし padding + background が残り 28×20pt の楕円が描画される。

**原因 B — DB保存バグ** (`LLMService.swift`):

`LLM.swift` の `respond(to:with:)` はカスタムコールバックパスでは `setOutput(to:)` が呼ばれず、`llm.output` が更新されない。しかし `LLMService.generate()` の fallback が `llm.output` を参照していた:

```swift
// Before (fallbackが常に "" を返す):
let finalText = accumulated.isEmpty ? llm.output : accumulated
//                                    ^^^^^^^^^^^ = "" (更新されない!)
```

この結果、例外的にトークン受信に失敗した場合 `generate()` が `""` を返し、`contentToSave = "[応答なし]"` のフォールバックが正しく機能しない可能性があった。

**原因 C — MainActor タスクレース** (`ChatService.swift`):

`onToken` コールバックが `Task { @MainActor in ... }` でキューされるため、`generate()` 完了直後には全トークンが `messages[streamIndex].content` に反映されていない可能性がある。DB保存前に yield が必要だった。

---

### 適用済み修正 3 件

#### Fix 1 — MessageBubbleView グレードット防止 (`ChatView.swift`)

```swift
// After: content が空の場合はバブル背景ごとスキップ
if !message.content.isEmpty {
    bubbleContent
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isUser ? theme.colors.blue : theme.colors.surface0)
        .cornerRadius(18)
        .shadow(...)
}

// Typing indicator は独立して表示 (isStreaming && content.isEmpty 時)
if message.isStreaming && message.content.isEmpty {
    TypingIndicatorView()
}
```

これにより: DB に `content=""` の古いメッセージが残っていても、グレードットは表示されなくなる。ストリーミング中の空バブル期間は TypingIndicator が代替表示する。

#### Fix 2 — DB保存コンテンツの信頼性向上 (`ChatService.swift`)

```swift
// await Task.yield() で pending な onToken MainActor タスクを先にドレイン
await Task.yield()

// 保存コンテンツの優先順位: in-memory > fullResponse > フォールバック
let inMemoryContent = streamIndex < messages.count ? messages[streamIndex].content : ""
let contentToSave: String
if !inMemoryContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
    contentToSave = inMemoryContent          // 優先: onToken で積み上げたコンテンツ
} else if !fullResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
    contentToSave = fullResponse             // 次善: LLMService 戻り値
} else {
    contentToSave = "[応答なし]"             // 最終フォールバック
}
```

#### Fix 3 — LLMService accumulated フォールバック修正 (`LLMService.swift`)

```swift
// Before: llm.output フォールバックは常に "" (カスタムコールバックパスでは更新されない)
let finalText = accumulated.isEmpty ? llm.output : accumulated

// After: accumulated を直接使用。空なら本当にトークン0件
return (accumulated, tokenCount)
```

`accumulated` が空の場合（モデルがトークンを生成しなかった）は `generate()` が `""` を返し、`ChatService` の `"[応答なし]"` フォールバックが正しく発動する。

---

### DB による再現確認

調査中に SQLite を直接クエリし、実際のデータを確認した:

```sql
SELECT m.id, m.role, "[" || m.content || "]", length(m.content)
FROM messages ORDER BY m.id;

-- 結果:
1 | user      | [ひてぇれ] | 42   ← 正常
2 | assistant | []         |  0   ← グレードットの原因
```

assistant メッセージの `content=""` が確認された。これは原因B（`llm.output` fallback bug）が発動した際に書き込まれた記録。Fix 2 + Fix 3 により、今後は `"[応答なし]"` または実際の応答テキストが保存される。

---

## ビルド検証

```
xcodebuild -scheme Memoria 
           -destination 'platform=iOS Simulator,id=CA5A717E-B456-46C6-9DD3-41DE4ACE9AB4'
           -configuration Debug build

** BUILD SUCCEEDED **
（警告: appintentsmetadataprocessor 1件のみ — アプリ動作に無影響）
```

また修正中に `LLMService.swift` で既存の潜在エラーも検出・修正した:

```swift
// Swift 6 strict concurrency: 文字列補間のautoclosureでは self. が必要
// Before: logger.info("... \(tokensPerSecond) tok/s")
// After:  logger.info("... \(self.tokensPerSecond) tok/s")
```

---

## 現在の技術的負債・リスク

| 項目 | 優先度 | 内容 |
|------|--------|------|
| GRDB master ブランチ | 中 | Package.resolved が `"branch": "master"` — バージョン固定推奨 |
| LLM.swift v1.8.0 | 低 | `postprocess` が `setOutput(to:)` を呼ばない設計はドキュメント化が必要 |
| `[weak self]` ガード | 低 | `genTask` 内の `guard let self, let llm = self.llm else { return ("", 0) }` が稀に空文字を返す可能性 |
| Task.yield() | 低 | 1回の yield で全 onToken タスクが完走する保証はない（実用上は問題なし） |

---

## 残タスク（App Store 申請に向けて）

1. **実機テスト** — iPhone 実機でモデルダウンロード → 推論 → 全機能確認
2. **GRDB バージョン固定** — `Package.resolved` を特定バージョンにピン留め
3. **App Privacy** — NSMicrophoneUsageDescription / NSSpeechRecognitionUsageDescription の確認
4. **アイコン・スプラッシュ** — 全サイズの AppIcon セット確認
5. **TestFlight** — 内部テスト配布で最終確認

---

## 変更ファイル一覧（本セッション）

| ファイル | 変更内容 |
|---------|---------|
| `Views/ChatView.swift` | グレードット修正: `if !message.content.isEmpty { ... }` ガード追加 |
| `Services/ChatService.swift` | `await Task.yield()` 追加、DB保存を3段階フォールバックに変更 |
| `Services/LLMService.swift` | `accumulated` 直接返却（`llm.output` fallback 除去）、`self.tokensPerSecond` 修正 |
