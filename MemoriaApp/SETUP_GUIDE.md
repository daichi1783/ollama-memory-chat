# Memoria for iPhone — Phase 1 セットアップガイド

> このガイドに従ってXcodeプロジェクトにPhase 1のコードを導入してください。

---

## 前提条件

- Xcode 16+ がインストール済み
- Xcodeプロジェクト「Memoria」が作成済み（`/Users/daichi/Documents/Claude/Projects/memoria-ios/Memoria/`）
- LLM.swift と GRDB.swift がSPMで追加済み

---

## 手順

### Step 1: Swiftファイルをプロジェクトにコピー

ターミナルで以下を実行してください：

```bash
# コピー元
SOURCE=~/Documents/Claude/Projects/ollamaメモリ機能PJ/ollama-memory-chat/MemoriaApp/Memoria

# コピー先（Xcodeプロジェクトの場所）
DEST=~/Documents/Claude/Projects/memoria-ios/Memoria/Memoria

# ディレクトリ作成
mkdir -p "$DEST/Models"
mkdir -p "$DEST/Views"
mkdir -p "$DEST/Services"

# ファイルをコピー
cp "$SOURCE/MemoriaApp.swift" "$DEST/"
cp "$SOURCE/Models/DatabaseModels.swift" "$DEST/Models/"
cp "$SOURCE/Views/ContentView.swift" "$DEST/Views/"
cp "$SOURCE/Views/ChatView.swift" "$DEST/Views/"
cp "$SOURCE/Services/DatabaseService.swift" "$DEST/Services/"
cp "$SOURCE/Services/LLMService.swift" "$DEST/Services/"
cp "$SOURCE/Services/ChatService.swift" "$DEST/Services/"
```

### Step 2: Xcodeにファイルを登録

1. Xcodeで `Memoria.xcodeproj` を開く
2. 左のProject Navigatorで「Memoria」フォルダを右クリック
3. 「Add Files to "Memoria"...」を選択
4. 以下のファイル/フォルダを選択して追加：
   - `Models/` フォルダ
   - `Views/` フォルダ
   - `Services/` フォルダ
   - `MemoriaApp.swift`
5. **「Copy items if needed」のチェックを外す**（既にプロジェクトフォルダ内にあるため）
6. 「Add」をクリック

### Step 3: 既存のContentView.swiftを削除

- Xcodeが自動生成した元の `ContentView.swift` があれば削除
- 新しい `Views/ContentView.swift` が使われるようにする

### Step 4: SPMパッケージの確認

Xcode → File → Packages で以下が入っていることを確認：

| パッケージ | URL |
|---|---|
| LLM.swift | `https://github.com/eastriverlee/LLM.swift` |
| GRDB.swift | `https://github.com/groue/GRDB.swift` |

もし入っていなければ：
1. File → Add Package Dependencies...
2. URLを入力してAdd Package

### Step 5: ビルド & 実行

1. ビルドターゲットを「iPhone 15 Pro」シミュレーターに設定
2. `Cmd + B` でビルド
3. エラーが出なければ `Cmd + R` で実行
4. 初回はモデルダウンロード画面が表示される（Wi-Fi必要、約600MB）

---

## ファイル構成（Phase 1）

```
Memoria/
├── MemoriaApp.swift          ← アプリエントリーポイント
├── Models/
│   └── DatabaseModels.swift  ← GRDB データモデル（5テーブル）
├── Views/
│   ├── ContentView.swift     ← メイン画面（状態に応じて切替）
│   └── ChatView.swift        ← チャットUI（バブル・入力・コマンド）
└── Services/
    ├── DatabaseService.swift ← SQLite操作（CRUD・記憶圧縮）
    ├── LLMService.swift      ← LLM推論（Gemma 3 1B / 4 E2B）
    └── ChatService.swift     ← チャット統合（送信・記憶・コマンド）
```

---

## 動作確認ポイント

- [ ] ビルドが通る（Cmd + B）
- [ ] シミュレーターで起動する
- [ ] モデル読み込み画面が表示される
- [ ] モデルダウンロード後、チャット画面に遷移する
- [ ] メッセージ送信でAI応答がストリーミング表示される
- [ ] `/help` でコマンド一覧が表示される
- [ ] `/remember テスト` で記憶が保存される
- [ ] `/memory` で保存した記憶が表示される

---

*Phase 1 完了後は IOS_HANDOFF.md を更新して Phase 2（記憶機能の完成）に進みます*
