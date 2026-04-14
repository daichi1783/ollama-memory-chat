# Memoria — セッション引き継ぎ書
> このファイルを読めば前のセッションの文脈を完全に把握できます。  
> 新しいセッションを始める際は **必ずこのファイルを最初に読んでください。**

---

## プロジェクト概要

**アプリ名:** Memoria v1.0.0  
**リポジトリ:** https://github.com/daichi1783/ollama-memory-chat  
**作成者:** Daichi.T  
**ローカルパス:** `~/Documents/Claude/Projects/ollamaメモリ機能PJ/ollama-memory-chat`

会話を記憶するローカルAIチャットアプリ（macOS DMG）。  
Ollama（完全オフライン）/ Claude / Gemini / OpenAI互換に対応。  
PyInstaller + PyWebView でビルドし DMG 配布。

---

## 技術スタック

| 層 | 技術 |
|---|---|
| Backend | Python 3.12 + FastAPI + Uvicorn（ポート 8765）|
| Frontend | Vanilla HTML/CSS/JS（フレームワークなし）|
| Window | PyWebView（ネイティブ Mac ウィンドウ）|
| DB | SQLite（`data/chat_memory.db`）|
| AI | Ollama SDK / requests（Claude・Gemini 直接呼び出し）|
| 多言語 | `frontend/assets/i18n.js`（JA/EN/ES）|
| ビルド | PyInstaller → DMG（`bash build_app.sh`）|

---

## 主要ファイル

```
ollama-memory-chat/
├── HANDOFF.md              ← ★このファイル★
├── NEXT_PROJECT.md         ← iPhoneアプリ引き継ぎメモ
├── config.yaml             ← AI設定（engine/model/key等）
├── build_app.sh            ← DMGビルドスクリプト
├── make_icon.py            ← Orbitalアイコン生成（Pillow）
├── Memoria.spec            ← PyInstaller設定
├── desktop_app.py          ← アプリ起動スクリプト
├── backend/
│   ├── main.py             ← FastAPI エンドポイント全定義
│   ├── memory_manager.py   ← SQLite CRUD + 記憶圧縮 + グローバルメモリ
│   ├── ollama_client.py    ← 全AIエンジン呼び出し（_resolve_config_path で毎回動的解決）
│   ├── command_manager.py  ← /english /japanese /remember 等のコマンド管理
│   └── ollama_setup.py     ← Ollama インストール・起動・モデル管理
└── frontend/
    ├── index.html          ← チャット画面
    ├── settings.html       ← 設定画面
    ├── setup.html          ← 初回セットアップウィザード
    └── assets/
        ├── app.js          ← フロントエンドメインJS
        ├── i18n.js         ← 多言語辞書 + applyTranslations()
        └── style.css       ← Catppuccin Mocha/Latte テーマ
```

---

## 実装済み機能（完了）

### コア機能
- セッション管理（複数セッション、タイトルインライン編集）
- セッション内記憶圧縮（N往復ごとに自動要約→システムプロンプト注入）
- グローバルメモリ（`/remember` コマンド、セッション間で保持）
- スラッシュコマンド（/english /japanese /spanish /cal /remember /memory /clear /help + ユーザー定義）
- マルチAIエンジン（Ollama / Claude / Gemini / OpenAI互換）
- チャット画面下部のエンジン切り替えピルボタン（履歴保持）

### UI/UX
- Catppuccin カラーパレット（ダーク/ライト自動切替）
- Orbital SVG ロゴ（サイドバー + AIアバター）
- 多言語対応 JA/EN/ES（設定画面で切替、localStorage 保存）
- 音声入力（Web Speech API、getUserMedia でシステム許可ダイアログ）
- モデル未インストール時のアラートバナー + 1クリックインストール
- 未インストールモデルをドロップダウンに表示 → 選択時に自動インストール
- モデル更新ボタン（再プルで最新版に）

### UX改善（最新セッションで実装）
1. ✅ オンボーディングモーダル（初回起動時のみ、3ステップ説明）
2. ✅ Ollama停止時オレンジバナー（起動ページへのリンク付き）
3. ✅ 送信ボタン：テキスト空のとき自動で無効化
4. ✅ AIメッセージにホバーでコピーボタン（⎘）表示
5. ✅ Enter送信トグル（設定 → 操作設定）
6. ✅ フォントサイズ切替 小/中/大（localStorage 保存）
7. ✅ APIキー取得リンクボタン（Anthropic・Google）
8. ✅ 更新ボタンのテキストを「🔄 最新版に更新」に変更
9. ✅ i18n 完全対応（全ラベル・ボタン・エラーメッセージ）
10. ✅ マイク許可：NSMicrophoneUsageDescription + getUserMedia で先にシステムダイアログ表示

---

## 次セッションでやること（UX改善 残り10項目）

優先度順に実装してください。

### Fix⑦: セッション削除の「取り消し」機能
- 削除後5秒間だけ「↩️ 取り消し」ボタンをサイドバー下部に表示
- タイムアウトしたら本当に削除（今は削除が即時確定）
- 実装場所: `frontend/assets/app.js` の `deleteSession()` を修正

### Fix⑧: ローディング中のメッセージ改善
- 「考えています...」テキストをタイピングアニメーション下に追加
- エンジン名も表示（例：「Claude が考えています...」）
- 実装場所: `frontend/assets/app.js` の `appendLoading()` + i18n キー追加

### Fix⑨: セッションタイトルの自動スマート生成
- 現在は最初のメッセージ先頭20文字で切れる
- 改善案：AIに「この会話を5文字以内で表すタイトルを生成して」と自動依頼
- または単純改善として：句読点・スペースで自然に切る + 「...」省略
- 実装場所: `backend/main.py` のチャットエンドポイント（セッション作成部分）

### Fix⑩: 設定保存後、チャット画面のエンジンラベルを即更新
- 保存後に `/api/status` を再取得してラベルを更新する
- 実装場所: `frontend/settings.html` の `_saveAISettingsCore()` 末尾に `if (typeof checkStatus === 'function') checkStatus();` を追加（簡単）

### Fix⑪: コマンドサジェストに使い方の例文を追加
- `/english こんにちは → "Hello"` のように入力例を示す
- 実装場所: `frontend/assets/app.js` の `showSuggest()` の description 表示を改善

### Fix⑫: クラウドAI接続失敗時にOllamaへの切り替え提案
- エラーバブル内に「Ollamaに切り替える」ボタンを表示
- クリックで `switchEngine('ollama')` を呼ぶ
- 実装場所: `frontend/assets/app.js` の `appendMessage()` エラー表示部分

### Fix⑬: サイドバーに「記憶: N件」バッジを表示
- グローバルメモリの件数をサイドバーのステータス近くに小さく表示
- `/api/global-memory` を初回と `/remember` 実行後にポーリング
- 実装場所: `frontend/index.html` + `app.js`

### Fix⑭: 「最新メッセージへ」スクロールボタン
- チャット欄を上にスクロールしているとき、右下に「↓」ボタンを表示
- クリックで最下部にスクロール
- 実装場所: `frontend/assets/app.js` + `style.css`

### Fix⑮: APIキーのフォーマット検証
- `claude_api_key` 入力時: `sk-ant-` で始まるか確認
- `gemini_api_key` 入力時: `AIza` で始まるか確認
- 不正なら保存前にインライン警告表示
- 実装場所: `frontend/settings.html` の `_saveAISettingsCore()` 内

### Fix⑯: カスタムコマンド追加フォームの説明文を改善
- 「コマンドを追加すると何ができるか」の一言説明と例を追加
- 例：「追加したコマンドは /コマンド名 で使えます。例: /summarize → 文章を要約」
- 実装場所: `frontend/settings.html` の「コマンド追加フォーム」セクション上部

---

## 開発・ビルド手順

```bash
# 開発サーバー起動
cd ~/Documents/Claude/Projects/ollamaメモリ機能PJ/ollama-memory-chat
source .venv/bin/activate
cd backend && uvicorn main:app --host 127.0.0.1 --port 8765 --reload

# ブラウザで確認
open http://127.0.0.1:8765

# DMGビルド（全自動: アイコン生成 → PyInstaller → DMG）
cd ~/Documents/Claude/Projects/ollamaメモリ機能PJ/ollama-memory-chat
bash build_app.sh
```

---

## 重要な設計メモ

### エンジン切り替えバグの修正（修正済み）
`ollama_client.py` の `CONFIG_PATH` をモジュールレベル定数にすると PyInstaller バンドル内で `main.py` と別ファイルを参照してしまい、エンジン切り替えが反映されなかった。`_resolve_config_path()` として毎回動的に解決するよう修正済み。

### Gemini API 認証方式
`Authorization: Bearer {api_key}` ヘッダー形式（`?key=` URL パラメーターは廃止済み）。`ollama_client.py` の `_chat_gemini()` で対応済み。

### PyWebView でのマイク許可
`NSMicrophoneUsageDescription` を `Memoria.spec` の `info_plist` に追加済み。`getUserMedia()` を先に呼ぶことで macOS のシステム許可ダイアログを表示。

### データパス
- バンドル時: `~/Library/Application Support/Memoria/`
- 開発時: `ollama-memory-chat/data/`
- 環境変数 `OMCHAT_BASE_DIR` / `OMCHAT_DATA_DIR` で制御

---

## ユーザー情報
- **名前:** Daichi
- **スキルレベル:** コーディング素人だがターミナル操作は可能
- **好む言語:** Python
- **目標:** 工場出荷状態の Mac でも 80 歳のおばあちゃんが使えるレベルのアプリ

---

*最終更新: 2026-04-14 — セッション移行時に作成*
