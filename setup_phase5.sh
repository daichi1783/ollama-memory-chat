#!/bin/bash
# =============================================================================
# Memoria Phase 5 セットアップスクリプト
# 実行方法: bash setup_phase5.sh
# =============================================================================

set -e

XCODE_PROJECT_DIR="$HOME/Documents/Claude/Projects/memoria-ios/Memoria"
MEMORIA_DIR="$XCODE_PROJECT_DIR/Memoria"
XCASSETS_DIR="$MEMORIA_DIR/Assets.xcassets"
APPICON_DIR="$XCASSETS_DIR/AppIcon.appiconset"
ICONS_SRC="$(dirname "$0")/memoria_ios_icons"

echo "============================================="
echo " Memoria Phase 5: App Store 申請準備"
echo "============================================="

# ── STEP 1: AppIcon.appiconset ディレクトリ作成 ──────────────
echo ""
echo "📁 STEP 1: AppIcon.appiconset を準備..."

if [ ! -d "$XCASSETS_DIR" ]; then
    echo "  ⚠️  Assets.xcassets が見つかりません: $XCASSETS_DIR"
    echo "  → Xcodeでプロジェクトを開いて Assets.xcassets を作成してください"
    echo "     (Xcodeメニュー: File → New → Asset Catalog)"
else
    mkdir -p "$APPICON_DIR"
    echo "  ✅ AppIcon.appiconset: $APPICON_DIR"
fi

# ── STEP 2: アイコンをコピー ──────────────────────────────────
echo ""
echo "🎨 STEP 2: アプリアイコンをXcodeプロジェクトにコピー..."

if [ -d "$APPICON_DIR" ] && [ -d "$ICONS_SRC" ]; then
    cp "$ICONS_SRC"/*.png "$APPICON_DIR/"
    cp "$ICONS_SRC/Contents.json" "$APPICON_DIR/"
    echo "  ✅ $(ls "$APPICON_DIR"/*.png | wc -l | tr -d ' ') 枚のアイコンをコピーしました"
    echo "  ✅ Contents.json をコピーしました"
else
    echo "  ⚠️  アイコンのコピーをスキップ（パスを確認してください）"
    echo "     ソース: $ICONS_SRC"
    echo "     宛先: $APPICON_DIR"
fi

# ── STEP 3: Info.plist にプライバシー説明を追加 ───────────────
echo ""
echo "🔒 STEP 3: Info.plist にプライバシー説明を追加..."

# Xcode 13以降はInfo.plistがxcodeproj内に統合されている場合があるため
# 両方のパスを確認
INFO_PLIST_PATHS=(
    "$MEMORIA_DIR/Info.plist"
    "$XCODE_PROJECT_DIR/Memoria/Info.plist"
    "$MEMORIA_DIR/../Info.plist"
)

INFO_PLIST=""
for p in "${INFO_PLIST_PATHS[@]}"; do
    if [ -f "$p" ]; then
        INFO_PLIST="$p"
        break
    fi
done

if [ -n "$INFO_PLIST" ]; then
    echo "  📄 Info.plist found: $INFO_PLIST"

    # NSMicrophoneUsageDescription が未設定なら追加
    if ! /usr/libexec/PlistBuddy -c "Print :NSMicrophoneUsageDescription" "$INFO_PLIST" &>/dev/null; then
        /usr/libexec/PlistBuddy -c "Add :NSMicrophoneUsageDescription string '音声入力機能のためにマイクを使用します'" "$INFO_PLIST"
        echo "  ✅ NSMicrophoneUsageDescription を追加しました"
    else
        echo "  ℹ️  NSMicrophoneUsageDescription は既に設定済みです"
    fi

    # NSSpeechRecognitionUsageDescription が未設定なら追加
    if ! /usr/libexec/PlistBuddy -c "Print :NSSpeechRecognitionUsageDescription" "$INFO_PLIST" &>/dev/null; then
        /usr/libexec/PlistBuddy -c "Add :NSSpeechRecognitionUsageDescription string 'オフラインでの音声認識に使用します'" "$INFO_PLIST"
        echo "  ✅ NSSpeechRecognitionUsageDescription を追加しました"
    else
        echo "  ℹ️  NSSpeechRecognitionUsageDescription は既に設定済みです"
    fi

else
    echo "  ⚠️  Info.plist が見つかりません"
    echo "  → Xcode で手動追加が必要です（下記「手動追加手順」を参照）"
    echo ""
    echo "  ─── Xcode での手動追加手順 ─────────────────────────"
    echo "  1. Xcode でプロジェクトを開く"
    echo "  2. 左ツリーで 'Memoria' ターゲットをクリック"
    echo "  3. 'Info' タブを選択"
    echo "  4. '+' ボタンをクリックして以下2項目を追加:"
    echo "     Key: NSMicrophoneUsageDescription"
    echo "     Value: 音声入力機能のためにマイクを使用します"
    echo ""
    echo "     Key: NSSpeechRecognitionUsageDescription"
    echo "     Value: オフラインでの音声認識に使用します"
    echo "  ──────────────────────────────────────────────────────"
fi

# ── 完了メッセージ ──────────────────────────────────────────
echo ""
echo "============================================="
echo " ✨ Phase 5 セットアップ完了！"
echo "============================================="
echo ""
echo "📋 次のステップ:"
echo "  1. Xcode でプロジェクトを開いて AppIcon を確認"
echo "  2. Product → Archive でアーカイブ作成"
echo "  3. App Store Connect でアプリを登録"
echo "  4. Organizer から App Store Connect にアップロード"
echo ""
echo "📄 詳細は APPSTORE_GUIDE.md を参照してください"
