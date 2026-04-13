#!/bin/bash
# OllamaMemoryChat 起動スクリプト（Mac用）
cd "$(dirname "$0")"

echo "🧠 OllamaMemoryChat を起動しています..."

# Python依存関係の確認
python3 -c "import webview, fastapi, uvicorn, ollama, yaml" 2>/dev/null
if [ $? -ne 0 ]; then
  echo "📦 依存パッケージをインストール中..."
  pip3 install pywebview fastapi uvicorn ollama pyyaml --break-system-packages -q
fi

# アプリ起動
python3 desktop_app.py
