# Next Project: Memoria for iPhone

## 概要
Memoria の iOS アプリ版の開発。
macOS 版 (Memoria v1.0.0) をベースに、iPhone 向けに UI/UX を再設計する。
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
