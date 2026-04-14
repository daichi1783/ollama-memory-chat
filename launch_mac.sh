#!/bin/bash
# =============================================================
# Memoria 起動スクリプト（開発・テスト用）
# 通常ユーザーは .dmg からインストールした .app を使ってください
# =============================================================
set -e
cd "$(dirname "$0")"

echo "✨ Memoria を起動しています..."

# ===== Python 3.x を探す（Homebrew優先）=====
PYTHON=""
for candidate in \
    /opt/homebrew/bin/python3.12 \
    /usr/local/bin/python3.12 \
    /opt/homebrew/bin/python3.11 \
    /opt/homebrew/bin/python3 \
    python3; do
  if command -v "$candidate" &>/dev/null; then
    VERSION=$("$candidate" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+')
    MAJOR=$(echo "$VERSION" | cut -d. -f1)
    MINOR=$(echo "$VERSION" | cut -d. -f2)
    # Python 3.9以上を要求
    if [ "$MAJOR" -ge 3 ] && [ "$MINOR" -ge 9 ]; then
      PYTHON=$(command -v "$candidate")
      break
    fi
  fi
done

if [ -z "$PYTHON" ]; then
  echo ""
  echo "❌ Python 3.9以上が見つかりません"
  echo ""
  echo "インストール方法:"
  echo "  1. https://brew.sh でHomebrewをインストール"
  echo "  2. ターミナルで: brew install python@3.12"
  echo ""
  # macOSのダイアログで通知
  osascript -e 'display dialog "Python 3.9以上が必要です。\nhttps://brew.sh からHomebrewをインストール後、\nbrew install python@3.12 を実行してください。" buttons {"OK"} default button "OK" with icon stop' 2>/dev/null || true
  exit 1
fi

echo "  Python: $("$PYTHON" --version)"

# ===== 仮想環境のセットアップ（初回のみ）=====
if [ ! -f ".venv/bin/python" ]; then
  echo "📦 初回セットアップ中（1〜3分かかります）..."
  "$PYTHON" -m venv .venv
  echo "  パッケージをインストール中..."
  .venv/bin/pip install \
    pywebview \
    fastapi \
    "uvicorn[standard]" \
    ollama \
    pyyaml \
    requests \
    python-multipart \
    -q
  echo "  ✅ セットアップ完了"
else
  # 起動するだけ（依存パッケージ確認不要）
  true
fi

# ===== 起動 =====
source .venv/bin/activate 2>/dev/null || true
python desktop_app.py
