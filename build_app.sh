#!/bin/bash
# =============================================================
# Memoria ビルドスクリプト
# 実行すると dist/OllamaMemoryChat-x.x.x.dmg が生成されます
# 使い方: bash build_app.sh
# =============================================================
set -e
cd "$(dirname "$0")"

APP_NAME="Memoria"
VERSION="0.1.0"
DMG_FILE="dist/${APP_NAME}-${VERSION}.dmg"

echo "🔨 ${APP_NAME} v${VERSION} のビルドを開始します"
echo ""

# ===== 1. Python環境の確認 =====
echo "【1/5】Python環境を確認中..."

# Homebrew Python 3.12 を優先
PYTHON=""
for candidate in \
    /opt/homebrew/bin/python3.12 \
    /usr/local/bin/python3.12 \
    /opt/homebrew/bin/python3.11 \
    /opt/homebrew/bin/python3 \
    python3; do
  if command -v "$candidate" &>/dev/null; then
    PYTHON=$(command -v "$candidate")
    break
  fi
done

if [ -z "$PYTHON" ]; then
  echo "❌ Python 3が見つかりません"
  echo "   https://brew.sh でHomebrewをインストール後、以下を実行してください:"
  echo "   brew install python@3.12"
  exit 1
fi

PY_VERSION=$("$PYTHON" --version 2>&1)
echo "  ✅ $PY_VERSION を使用 ($PYTHON)"

# ===== 2. 仮想環境とパッケージ =====
echo ""
echo "【2/5】仮想環境とパッケージを準備中..."

if [ ! -f ".venv/bin/python" ]; then
  echo "  仮想環境を作成中..."
  "$PYTHON" -m venv .venv
fi

PIP=".venv/bin/pip"
VENV_PYTHON=".venv/bin/python"

echo "  パッケージをインストール中（初回は時間がかかります）..."
$PIP install \
  pywebview \
  fastapi \
  "uvicorn[standard]" \
  ollama \
  pyyaml \
  requests \
  python-multipart \
  pyinstaller \
  -q

echo "  ✅ パッケージ準備完了"
$PIP install pillow numpy -q

echo ""
echo "【2.5/5】アプリアイコンを生成中..."
$VENV_PYTHON make_icon.py

# ===== 3. PyInstallerでビルド =====
echo ""
echo "【3/5】アプリをビルド中（3〜10分かかります）..."

# 古いビルドを削除
rm -rf dist/ build/ 2>/dev/null || true

$VENV_PYTHON -m PyInstaller Memoria.spec --noconfirm --clean 2>&1 | \
  grep -E "^(INFO|WARNING|ERROR|Building|Copying|Appending|✅|❌)" || true

if [ ! -d "dist/${APP_NAME}.app" ]; then
  echo ""
  echo "❌ ビルドに失敗しました。詳細は上のログを確認してください。"
  exit 1
fi

echo "  ✅ .appビルド完了: dist/${APP_NAME}.app"

# ===== 4. DMGを作成 =====
echo ""
echo "【4/5】DMGを作成中..."

DMG_TMP="/tmp/${APP_NAME}_dmg_build_$$"
rm -rf "$DMG_TMP"
mkdir -p "$DMG_TMP"

# .appとApplicationsショートカットを配置
cp -r "dist/${APP_NAME}.app" "$DMG_TMP/"
ln -s /Applications "$DMG_TMP/Applications"

# DMGを生成
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_TMP" \
  -ov \
  -format UDZO \
  "$DMG_FILE" \
  2>&1 | grep -v "^hdiutil:" || true

rm -rf "$DMG_TMP"

if [ ! -f "$DMG_FILE" ]; then
  echo "❌ DMG作成に失敗しました"
  exit 1
fi

DMG_SIZE=$(du -sh "$DMG_FILE" | cut -f1)
echo "  ✅ DMG作成完了: $DMG_FILE ($DMG_SIZE)"

# ===== 5. 確認 =====
echo ""
echo "【5/5】確認..."
echo "  .app サイズ: $(du -sh "dist/${APP_NAME}.app" | cut -f1)"
echo "  DMG サイズ:  $DMG_SIZE"

echo ""
echo "============================================"
echo "🎉 ビルド完了！"
echo ""
echo "配布ファイル:"
echo "  $(pwd)/$DMG_FILE"
echo ""
echo "インストール方法:"
echo "  1. ${APP_NAME}-${VERSION}.dmg を開く"
echo "  2. Memoria を Applications にドラッグ"
echo "  3. アプリをダブルクリックして起動"
echo "============================================"
