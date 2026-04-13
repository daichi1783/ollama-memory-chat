"""
OllamaMemoryChat デスクトップアプリ起動スクリプト
PyWebViewでWebUIをネイティブMacウィンドウとして表示する
"""
import sys
import os
import threading
import time
from pathlib import Path

# バックエンドをパスに追加
sys.path.insert(0, str(Path(__file__).parent / "backend"))

def start_backend():
    """バックエンドサーバーをバックグラウンドスレッドで起動"""
    import uvicorn
    import yaml

    config_path = Path(__file__).parent / "config.yaml"
    with open(config_path, "r") as f:
        config = yaml.safe_load(f)
    port = config.get("app", {}).get("port", 8765)

    # ログを最小限に
    uvicorn.run(
        "main:app",
        app_dir=str(Path(__file__).parent / "backend"),
        host="127.0.0.1",
        port=port,
        log_level="error"
    )

def wait_for_server(port: int, timeout: int = 10) -> bool:
    """サーバーが起動するまで待機"""
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

    config_path = Path(__file__).parent / "config.yaml"
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
