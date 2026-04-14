# Next Project: Memoria for iPhone

## 概要
Memoria の iOS アプリ版の開発。
macOS 版 (Memoria v1.0.0) をベースに、iPhone 向けに UI/UX を再設計する。

## 引き継ぎ情報

### 作成者
Daichi.T

### macOS 版の主要技術スタック
- Backend: Python + FastAPI + SQLite
- AI エンジン: Ollama (local) / Claude (Anthropic) / Gemini (Google) / OpenAI compatible
- Memory: セッション内圧縮記憶 + グローバルクロスセッション記憶
- Language: JA / EN / ES

### iPhone 版で検討すべき項目
- [ ] Swift / SwiftUI で UI を構築
- [ ] バックエンドは Python → Swift 移植 or API サーバー経由
- [ ] ローカル AI: Core ML / llm.swift / on-device LLM
- [ ] クラウド AI: 同じく Claude / Gemini / OpenAI を選択可能
- [ ] 記憶: UserDefaults or SQLite via GRDB
- [ ] 多言語: JA / EN / ES (Localizable.strings)
- [ ] App Store 向けの審査対策（プライバシーポリシー等）
- [ ] 価格モデル: 有料 or サブスクリプション or フリーミアム

### GitHub リポジトリ
https://github.com/daichi1783/ollama-memory-chat

### デザインガイド
- カラー: Catppuccin Mocha (dark) / Latte (light)
- ロゴ: Orbital (グラデーション円 + 四方のドット) — memoria_logos.html 参照
- フォント: SF Pro (iOS システムフォント)

## 販売・配布
macOS 版・iOS 版の販売は別プロジェクトで検討。
