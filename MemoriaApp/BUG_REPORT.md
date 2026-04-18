# Memoria for iPhone - バグ報告・次セッション引き継ぎ

## 環境
- デバイス: iPhone 12 Pro (iOS 26.3.1)
- モデル: Gemma 3 1B Q4_K_M (unsloth/gemma-3-1b-it-GGUF)
- LLM.swift v1.8.0
- GRDB.swift (SQLite)

## 確認済みバグ一覧

### BUG-1: テキスト部分選択ができない（優先度: 中）
**症状**: チャットバブル内のテキストをロングプレスしても、テキスト選択ハンドル（青いカーソル）が表示されず、部分選択ができない。
**試したこと**:
1. `.textSelection(.enabled)` を Text に追加 → `.contextMenu` と競合して動作せず
2. UITextView ラッパー (SelectableTextView) → レイアウト崩壊（ゴースト表示、高さ計算不正）
3. `.contextMenu` を完全除去 + `.textSelection(.enabled)` のみ → まだ動作しない

**考えられる原因**:
- `.clipShape(BubbleShape)` がテキスト選択UIをクリップしている可能性
- `LazyVStack` + `ScrollView` の中でテキスト選択がうまく動作しない可能性
- `ForEach` 内の `Text` に対する `.textSelection(.enabled)` の既知の制限

**次に試すべきアプローチ**:
- `BubbleShape` の代わりに `.cornerRadius()` を使う（clipShape が選択ハンドルを遮っていないか検証）
- バブル外に `.textSelection(.enabled)` を適用（VStack レベルなど）
- 最小再現テスト: 新規SwiftUIプロジェクトで ScrollView > LazyVStack > Text(.textSelection(.enabled)) が動くか確認
- UITextView ラッパーを再挑戦する場合: `intrinsicContentSize` を正しくオーバーライドし、`sizeThatFits` で高さを報告する

### BUG-2: AI応答が表示されない / ハングする（優先度: 高）
**症状**: メッセージを送信するとユーザーバブルは表示されるが、AI応答のタイピングインジケータ（3つのドット）が出たまま応答が来ない。
**試したこと**:
- `LLMService.generate()` に `.generating` 状態のリカバリーロジックを追加
- `ChatService.generateResponse()` に `defer { isGenerating = false }` を追加

**考えられる原因**:
- `llm.respond(to:)` の async stream が正しく完了していない
- `LLM(from: localURL, ...)` でモデルは読み込めているが推論が失敗している
- Gemma テンプレートの `system` タプルの形式が LLM.swift の期待と合っていない可能性
- `respond(to:with:)` のクロージャ内の `for await token in response` が永久にブロックされている

**デバッグ手順**:
1. Xcode の Console でログを確認: `[LLM]` タグのログが出ているか
2. `generate()` 内に print デバッグを追加して、どこでスタックしているか特定
3. テンプレートを `Template.gemma` (LLM.swift 組み込み) に変更して試す
4. `maxTokenCount` を小さくして（例: 256）テスト
5. `llm.respond(to:)` を使わず `llm.output` を直接参照する方法を試す

### BUG-3: ホーム画面に戻るとチャット履歴が消える（優先度: 高）
**症状**: チャット画面から戻るボタンでセッション一覧に戻ると、セッション内のメッセージが全て消え、再度セッションを開いても空になっている。
**試したこと**:
- `SessionListView.loadSessions()` を効率的な `getSessionsWithPreview()` に変更
- `ContentView` で NavigationStack 破棄を防止（`hasLoadedOnce` フラグ）
- `.onAppear` を `.task` に変更

**考えられる原因**:
- メッセージがDBに保存されていない（`addMessage()` が失敗している）
- `chatService.loadSession(id:)` が正しくDBからメッセージを読み込めていない
- NavigationStack + NavigationLink のライフサイクル問題
- `currentSessionId` が nil になっている

**デバッグ手順**:
1. `DatabaseService.addMessage()` に print ログを追加して保存が成功しているか確認
2. `chatService.loadSession(id:)` で取得したメッセージ数をログ出力
3. SQLiteブラウザでDBファイルの中身を直接確認
4. `chatService.currentSessionId` の値の変遷をログで追跡

### BUG-4: 連続メッセージ送信ができない（優先度: 高）
**症状**: 2回目以降のメッセージ送信でUIに何も表示されない。
**関連**: BUG-2 と BUG-3 が組み合わさった結果の可能性が高い。AI応答がハングすると `isGenerating = true` のままになり、次のメッセージ送信がブロックされる。

### BUG-5: インプット欄にゴーストテキストが残る（優先度: 低）
**症状**: UITextView ラッパー使用時に、送信済みテキストがインプット欄に透けて見える。
**状態**: UITextView ラッパーを撤去したため、現在は解消している可能性あり。要確認。

## 変更済みファイル一覧
- `MemoriaApp/Memoria/Views/ChatView.swift` — テキスト選択対応、UITextView撤去
- `MemoriaApp/Memoria/Views/ContentView.swift` — NavigationStack破棄防止
- `MemoriaApp/Memoria/Views/SessionListView.swift` — loadSessions効率化、.task変更
- `MemoriaApp/Memoria/Services/ChatService.swift` — defer追加、空応答フォールバック
- `MemoriaApp/Memoria/Services/LLMService.swift` — .generating状態リカバリー、Gemmaテンプレート

## 推奨アプローチ（次セッション）
1. **BUG-2 を最優先で修正**（AI応答のハング）— これが直れば BUG-3, BUG-4 も改善する可能性大
2. BUG-2 の原因特定のため、`LLMService.generate()` 内に詳細なログを追加
3. テンプレートを `Template.gemma`（LLM.swift 組み込み）に戻して検証
4. テキスト選択は後回しにし、まず基本機能（チャット送受信、履歴保持）を安定させる
