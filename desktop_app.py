"""
OllamaMemoryChat デスクトップアプリ起動スクリプト
PyWebViewでWebUIをネイティブMacウィンドウとして表示する
PyInstaller .appバンドルにも対応
"""
import sys
import os
import shutil
import threading
import time
from pathlib import Path

# ===== PyInstaller バンドル vs 通常起動 の判定 =====
if getattr(sys, 'frozen', False):
    # PyInstallerバンドル内で実行中
    # sys._MEIPASS = バンドルされたリソースの展開先ディレクトリ
    BUNDLE_DIR = Path(sys._MEIPASS)
    # データ（DB・ユーザー設定）はユーザーのApplication Supportへ
    DATA_DIR = Path.home() / "Library" / "Application Support" / "OllamaMemoryChat"
else:
    # 通常実行（開発時 / launch_mac.sh 経由）
    BUNDLE_DIR = Path(__file__).parent
    DATA_DIR = Path(__file__).parent / "data"

# バンドルパス・データパスを環境変数で全バックエンドモジュールに共有
os.environ['OMCHAT_BASE_DIR'] = str(BUNDLE_DIR)
os.environ['OMCHAT_DATA_DIR'] = str(DATA_DIR)

# データディレクトリを作成（初回 or バンドル実行時）
DATA_DIR.mkdir(parents=True, exist_ok=True)

# config.yaml: バンドル内のデフォルト設定をデータディレクトリにコピー（初回のみ）
user_config = DATA_DIR / "config.yaml"
default_config = BUNDLE_DIR / "config.yaml"
if not user_config.exists() and default_config.exists():
    shutil.copy(str(default_config), str(user_config))

# バックエンドをパスに追加
sys.path.insert(0, str(BUNDLE_DIR / "backend"))


def start_backend():
    """バックエンドサーバーをバックグラウンドスレッドで起動"""
    import uvicorn
    import yaml

    config_path = DATA_DIR / "config.yaml"
    if not config_path.exists():
        config_path = BUNDLE_DIR / "config.yaml"

    with open(config_path, "r") as f:
        config = yaml.safe_load(f)
    port = config.get("app", {}).get("port", 8765)

    uvicorn.run(
        "main:app",
        app_dir=str(BUNDLE_DIR / "backend"),
        host="127.0.0.1",
        port=port,
        log_level="error"
    )


def wait_for_server(port: int, timeout: int = 15) -> bool:
    """サーバーが起動するまで待機（最大15秒）"""
    import urllib.request
    for _ in range(timeout * 10):
        try:
            urllib.request.urlopen(f"http://127.0.0.1:{port}/api/status", timeout=1)
            return True
        except Exception:
            time.sleep(0.1)
    return False


def main():
    import webview
    import yaml

    config_path = DATA_DIR / "config.yaml"
    if not config_path.exists():
        config_path = BUNDLE_DIR / "config.yaml"

    with open(config_path, "r") as f:
        config = yaml.safe_load(f)

    port = config.get("app", {}).get("port", 8765)
    app_name = config.get("app", {}).get("name", "OllamaMemoryChat")

    print(f"🧠 {app_name} を起動しています...")

    # バックエンドをバックグラウンドで起動
    server_thread = threading.Thread(target=start_backend, daemon=True)
    server_thread.start()

    # サーバー起動を待機
    print("  サーバーを起動中...")
    if not wait_for_server(port):
        print("❌ サーバーの起動に失敗しました")
        sys.exit(1)

    print("  ✅ サーバー起動完了")

    # PyWebViewウィンドウを作成
    window = webview.create_window(
        title=app_name,
        url=f"http://127.0.0.1:{port}/",
        width=1100,
        height=750,
        min_size=(800, 600),
        resizable=True,
    )

    print("  ✅ アプリウィンドウを開きます")
    webview.start(debug=False)


if __name__ == "__main__":
    main()
