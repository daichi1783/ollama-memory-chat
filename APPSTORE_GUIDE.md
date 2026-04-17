# Memoria — App Store 申請完全ガイド

> Phase 5: App Store 申請準備
> 作成: 2026-04-17

---

## 事前確認チェックリスト

- [ ] Apple Developer Program 登録済み（年額 $99 USD）
  → https://developer.apple.com/programs/enroll/
- [ ] Mac に Xcode 最新版インストール済み
- [ ] iPhone が Apple Developer アカウントに登録済み（実機テスト用）

---

## STEP 1: アイコンをXcodeプロジェクトに組み込む

### ターミナルで実行（簡単）
```bash
# Phase5セットアップスクリプトを実行
cd ~/Documents/Claude/Projects/ollamaメモリ機能PJ/ollama-memory-chat
bash setup_phase5.sh
```

### 手動で行う場合（Xcodeで）
1. Xcodeでプロジェクトを開く
2. 左パネルの `Assets.xcassets` をクリック
3. `AppIcon` が表示されたら、`memoria_ios_icons/` フォルダから各サイズの PNG を対応するスロットにドラッグ＆ドロップ
4. 1024×1024 は `App Store` のスロットに `icon_1024.png` をドロップ

---

## STEP 2: Info.plist プライバシー説明の追加

Xcodeで以下の手順を実行してください。

1. 左パネルで `Memoria` プロジェクトアイコンをクリック
2. `TARGETS` → `Memoria` をクリック
3. 上部の `Info` タブをクリック
4. `Custom iOS Target Properties` セクションの `+` ボタンをクリック

**追加するキー1:**
- Key: `Privacy - Microphone Usage Description`
- Type: String
- Value: `音声入力機能のためにマイクを使用します`

**追加するキー2:**
- Key: `Privacy - Speech Recognition Usage Description`
- Type: String
- Value: `オフラインでの音声認識に使用します`

> ✅ これらが未設定だとApp Store審査でリジェクトされます

---

## STEP 3: バージョン・ビルド番号の設定

1. Xcodeで `Memoria` ターゲット → `General` タブ
2. `Identity` セクションを確認:
   - **Version**: `1.0.0`
   - **Build**: `1`
3. `Signing & Capabilities` タブで:
   - **Team**: あなたの Apple Developer アカウントを選択
   - **Bundle Identifier**: `com.daichi.memoria` を確認

---

## STEP 4: Archiveの作成

```
1. Xcodeメニュー → Product → Destination → Any iOS Device (arm64)
   （シミュレーターではなく "Any iOS Device" を選択！）

2. Xcodeメニュー → Product → Archive
   （ビルドに数分かかります）

3. Organizer ウィンドウが自動で開きます
   （Window → Organizer でも開けます）
```

---

## STEP 5: App Store Connect でアプリを登録

### 5-1. App Store Connect にアクセス
https://appstoreconnect.apple.com

### 5-2. 新規アプリを作成
1. `マイ App` → `+` ボタン → `新規 App`
2. 以下を入力:

| 項目 | 値 |
|---|---|
| プラットフォーム | iOS |
| 名前 | `Memoria - 記憶するAI` |
| 主要言語 | 日本語 |
| Bundle ID | `com.daichi.memoria` |
| SKU | `memoria-ios-001` |
| ユーザーアクセス | 完全なアクセス |

### 5-3. バージョン情報を入力（APPSTORE_METADATA.md を参照）

**App情報 タブ:**
- サブタイトル: `会話を覚えるオフラインアシスタント`
- カテゴリ: 仕事効率化 / ユーティリティ
- プライバシーポリシーURL: `https://daichi1783.github.io/memoria/privacy`

**1.0 バージョン → App Store バージョン情報:**
- 説明（JA）: `APPSTORE_METADATA.md` の日本語説明文をコピペ
- キーワード: `AI,チャット,アシスタント,記憶,オフライン,プライバシー,音声入力,翻訳,LLM,Gemma`
- サポートURL: `https://github.com/daichi1783/memoria`（またはGitHub Pages）

---

## STEP 6: スクリーンショットの撮影と登録

### Xcodeシミュレーターで撮影

```bash
# iPhone 15 Plus (6.7インチ) でシミュレーター起動
open -a Simulator
# Xcodeで iPhone 15 Plus シミュレーターを選択して Cmd+R
```

**撮影するシーン（5枚推奨）:**

1. **チャット中** — AIと会話している画面（数メッセージ表示）
2. **セッション一覧** — 複数セッションが表示された画面
3. **音声入力** — マイクボタンをタップして録音中
4. **設定画面** — テーマ設定が表示された画面
5. **起動直後** — ウェルカム画面

**シミュレーターでのスクリーンショット保存:**
```
シミュレーター → File → Save Screenshot (Cmd+S)
保存先: デスクトップなど
```

**必要なサイズ:**
- iPhone 6.7インチ: iPhone 15 Plus または 16 Plus でキャプチャ
- iPhone 6.1インチ: iPhone 15 または 16 でキャプチャ
- iPad（任意）: iPad Pro 12.9インチ など

### App Store Connect にアップロード
1. `App Store` → `iOS App` → `1.0 バージョン`
2. `iPhone 6.7インチ ディスプレイ` セクションに撮影した画像をドラッグ
3. 順番を整えて保存

---

## STEP 7: App プライバシー設定

App Store Connect → `App プライバシー` タブ:

**質問への回答:**
- `データを収集しますか？` → **はい**（チャット履歴を端末に保存）
- `サードパーティとデータを共有しますか？` → **いいえ**
- `収集したデータであなたをトラッキングしますか？` → **いいえ**

**収集するデータカテゴリ:**
- `ユーザーコンテンツ` → `アプリ機能のため` → `デバイスにのみ保存（送信しない）`

---

## STEP 8: Organizer からアップロード

1. `Xcode → Window → Organizer`
2. 作成したアーカイブを選択
3. `Distribute App` ボタンをクリック
4. `App Store Connect` を選択 → `Upload`
5. 確認して `Upload` を実行

---

## STEP 9: TestFlight でのテスト（推奨）

1. App Store Connect → `TestFlight` タブ
2. アップロードが完了するとビルドが表示される（数分〜30分）
3. `テスター` → `+` → `内部テスター` にあなたのApple IDを追加
4. メールに届く招待リンクからMemoriaをインストール

**実機テスト確認ポイント:**
- [ ] 初回起動: モデルダウンロード（約600MB、Wi-Fi推奨）
- [ ] 2通目以降のメッセージで正常に応答が返る
- [ ] 音声入力でマイク許可ダイアログが表示される
- [ ] 音声入力で日本語が正しく認識される
- [ ] セッション切り替えが正常に動作する
- [ ] 機内モードでも動作する（モデルDL後）
- [ ] ダーク/ライトテーマ切替が動作する

---

## STEP 10: 審査への提出

1. App Store Connect → `1.0 バージョン`
2. `審査のために提出` ボタンをクリック
3. `審査ノート` に以下を入力（審査官向け説明）:

```
This app uses on-device AI inference (Gemma 3 1B via LLM.swift/llama.cpp).
No network requests are made after the initial model download from HuggingFace (~600MB).
Microphone permission is used for offline voice input only (SFSpeechRecognizer, on-device).
No user data is collected, transmitted, or shared.
The app works in Airplane Mode after initial setup.

Initial setup steps:
1. Launch the app
2. The app will prompt to download the AI model (~600MB via Wi-Fi)
3. Once downloaded, tap "+" to create a new chat session
4. Type a message and send
```

---

## プライバシーポリシーの公開

**GitHub Pagesを使う場合（無料・推奨）:**

```bash
# GitHubで新しいリポジトリ "memoria" を作成してから:
cd ~/Documents/Claude/Projects/ollamaメモリ機能PJ/ollama-memory-chat

# gh コマンドでリポジトリ作成（既存なら不要）
gh repo create daichi1783/memoria --public

# privacy_policy.html を index.html としてリポジトリに追加
mkdir -p /tmp/memoria-site
cp privacy_policy.html /tmp/memoria-site/index.html
cd /tmp/memoria-site
git init
git add index.html
git commit -m "Add privacy policy"
git branch -M main
git remote add origin https://github.com/daichi1783/memoria.git
git push -u origin main

# GitHub Pages を有効化:
# GitHub → リポジトリ → Settings → Pages → Source: main / (root)
# URL: https://daichi1783.github.io/memoria/
```

---

## 申請後のスケジュール（目安）

| フェーズ | 期間 |
|---|---|
| 審査中（In Review） | 1〜3営業日 |
| 承認後（Ready for Sale） | 即時〜数時間 |
| TestFlight（内部テスト） | 即時（審査なし） |

---

## よくある審査リジェクト理由と対策

| リジェクト理由 | 対策 |
|---|---|
| プライバシーポリシーURLが無効 | GitHub PagesでページをPublish後にURLを登録 |
| マイク説明が不十分 | Info.plistの説明文が具体的であること |
| スクリーンショットが実際のUIと異なる | 最新ビルドでキャプチャしたものを使用 |
| 4+レーティングとコンテンツが不一致 | チャット内容がAIなので基本4+で問題なし |
| サポートURLが無効 | GitHubリポジトリのURL（またはGH Pages）を使用 |

---

*作成: 2026-04-17 — Phase 5 完了*
