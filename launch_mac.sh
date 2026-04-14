#!/bin/bash
# OllamaMemoryChat 起動スクリプト（Mac用）
set -e
cd "$(dirname "$0")"

echo "🧠 OllamaMemoryChat を起動しています..."

# Python 3.12（Homebrew）を優先して使用
PYTHON=""
for candidate in /opt/homebrew/bin/python3.12 /usr/local/bin/python3.12 /opt/homebrew/bin/python3 python3; do
  if command -v "$candidate" &>/dev/null; then
    PYTHON="$candidate"
    break
  fi
done

if [ -z "$PYTHON" ]; then
  echo "❌ Python3が見つかりません。https://www.python.org からインストールしてください。"
  exit 1
fi

echo "  Pythonを使用: $($PYTHON --version)"

# 仮想環境の作成（初回のみ）
if [ ! -f ".venv/bin/activate" ]; then
  echo "📦 初回セットアップ中（1〜2分かかります）..."
  "$PYTHON" -m venv .venv
  source .venv/bin/activate
  pip install pywebview fastapi "uvicorn[standard]" ollama pyyaml requests python-multipart -q
  echo "  ✅ セットアップ完了"
else
  source .venv/bin/activate
fi

# アプリ起動
python desktop_app.py
