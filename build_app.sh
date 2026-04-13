#!/bin/bash
# OllamaMemoryChat .appビルドスクリプト
set -e
cd "$(dirname "$0")"

APP_NAME="OllamaMemoryChat"
VERSION="0.1.0-beta"

echo "🔨 ${APP_NAME} v${VERSION} をビルドします..."

# PyInstallerのインストール確認
python3 -c "import PyInstaller" 2>/dev/null || {
  echo "📦 PyInstallerをインストール中..."
  pip3 install pyinstaller --break-system-packages -q
}

# 古いビルドを削除
rm -rf dist/ build/ 2>/dev/null || true

echo "📦 アプリをパッケージ化中..."

python3 -m PyInstaller \
  --name "${APP_NAME}" \
  --windowed \
  --onedir \
  --add-data "frontend:frontend" \
  --add-data "config.yaml:." \
  --hidden-import "webview" \
  --hidden-import "fastapi" \
  --hidden-import "uvicorn" \
  --hidden-import "uvicorn.logging" \
  --hidden-import "uvicorn.loops" \
  --hidden-import "uvicorn.loops.auto" \
  --hidden-import "uvicorn.protocols" \
  --hidden-import "uvicorn.protocols.http" \
  --hidden-import "uvicorn.protocols.http.auto" \
  --hidden-import "uvicorn.lifespan" \
  --hidden-import "uvicorn.lifespan.on" \
  --hidden-import "ollama" \
  --hidden-import "yaml" \
  --hidden-import "sqlite3" \
  desktop_app.py \
  --noconfirm \
  --clean

echo ""
if [ -d "dist/${APP_NAME}.app" ] || [ -d "dist/${APP_NAME}" ]; then
  echo "✅ ビルド成功！"
  echo ""
  echo "使い方:"
  echo "  dist/${APP_NAME}.app をダブルクリックして起動"
  echo "  または Applications フォルダにドラッグ＆ドロップ"
else
  echo "❌ ビルドに失敗しました（ログを確認してください）"
  exit 1
fi
