"""
Ollama ライフサイクル管理モジュール
- Ollamaのインストール検出
- 自動インストール（Homebrew優先、なければ公式バイナリダウンロード）
- ollama serve の起動・停止
- モデルの一覧取得・ダウンロード
"""
import os
import sys
import subprocess
import shutil
import platform
import threading
import time
import json
import urllib.request
import zipfile
import tempfile
from pathlib import Path
from typing import Optional, Callable

# Ollamaバイナリの候補パス（Mac）
OLLAMA_PATHS = [
    "/usr/local/bin/ollama",
    "/opt/homebrew/bin/ollama",
    "/usr/bin/ollama",
    str(Path.home() / ".local" / "bin" / "ollama"),
    str(Path.home() / "bin" / "ollama"),
]

# ollama serveのプロセス（グローバル）
_ollama_process: Optional[subprocess.Popen] = None

# ダウンロード進捗管理
_pull_progress: dict = {}  # model_name -> {"status": str, "percent": int, "done": bool, "error": str}


# ===== インストール検出 =====

def find_ollama_binary() -> Optional[str]:
    """Ollamaバイナリのパスを返す。見つからなければNone。"""
    # shutil.whichで環境変数PATHから検索
    found = shutil.which("ollama")
    if found:
        return found
    # 候補パスを直接チェック
    for path in OLLAMA_PATHS:
        if os.path.isfile(path) and os.access(path, os.X_OK):
            return path
    return None


def is_ollama_installed() -> bool:
    """Ollamaがインストールされているか"""
    return find_ollama_binary() is not None


def is_ollama_running() -> bool:
    """Ollamaサービス（API）が起動しているか"""
    try:
        import urllib.request
        req = urllib.request.urlopen("http://localhost:11434/api/tags", timeout=2)
        return req.status == 200
    except Exception:
        return False


# ===== インストール =====

def check_homebrew() -> Optional[str]:
    """Homebrewのパスを返す。なければNone。"""
    brew = shutil.which("brew")
    if brew:
        return brew
    for path in ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]:
        if os.path.isfile(path):
            return path
    return None


def install_ollama_via_brew(progress_callback: Optional[Callable] = None) -> dict:
    """
    Homebrewを使ってOllamaをインストールする。
    戻り値: {"success": bool, "message": str}
    """
    brew = check_homebrew()
    if not brew:
        return {"success": False, "message": "Homebrewが見つかりません"}

    if progress_callback:
        progress_callback("Homebrewでollamaをインストール中... (数分かかる場合があります)")

    try:
        result = subprocess.run(
            [brew, "install", "ollama"],
            capture_output=True, text=True, timeout=300
        )
        if result.returncode == 0:
            return {"success": True, "message": "Homebrewでollamaのインストールが完了しました"}
        else:
            return {"success": False, "message": f"Homebrewインストール失敗: {result.stderr[:200]}"}
    except subprocess.TimeoutExpired:
        return {"success": False, "message": "インストールがタイムアウトしました"}
    except Exception as e:
        return {"success": False, "message": str(e)}


def install_ollama_binary(progress_callback: Optional[Callable] = None) -> dict:
    """
    公式バイナリを直接ダウンロードしてインストールする（Homebrew不要）。
    Mac用: GitHub releasesからollama-darwin バイナリをダウンロード
    戻り値: {"success": bool, "message": str, "path": str}
    """
    arch = platform.machine()  # "arm64" or "x86_64"

    if progress_callback:
        progress_callback("公式サイトからOllamaをダウンロード中...")

    # GitHub releases から最新バイナリURLを取得
    try:
        api_url = "https://api.github.com/repos/ollama/ollama/releases/latest"
        req = urllib.request.Request(api_url, headers={"User-Agent": "Memoria/1.0"})
        with urllib.request.urlopen(req, timeout=10) as resp:
            release_info = json.loads(resp.read())

        # Mac用バイナリを探す
        target_name = "ollama-darwin" if arch == "arm64" else "ollama-darwin"
        download_url = None
        for asset in release_info.get("assets", []):
            name = asset["name"]
            if name == "ollama-darwin" or (arch == "x86_64" and name == "ollama-darwin-amd64"):
                download_url = asset["browser_download_url"]
                break

        if not download_url:
            # フォールバック: 固定URLを試みる
            download_url = "https://github.com/ollama/ollama/releases/latest/download/ollama-darwin"

    except Exception:
        download_url = "https://github.com/ollama/ollama/releases/latest/download/ollama-darwin"

    # ダウンロード先: ~/.local/bin/ollama
    install_dir = Path.home() / ".local" / "bin"
    install_dir.mkdir(parents=True, exist_ok=True)
    install_path = install_dir / "ollama"

    if progress_callback:
        progress_callback(f"ダウンロード中: {download_url}")

    try:
        def reporthook(count, block_size, total_size):
            if total_size > 0 and progress_callback:
                percent = int(count * block_size * 100 / total_size)
                progress_callback(f"ダウンロード中... {min(percent, 100)}%")

        urllib.request.urlretrieve(download_url, str(install_path), reporthook)
        os.chmod(str(install_path), 0o755)

        # PATHに追加するため、シェル設定ファイルにエクスポートを追記
        _add_to_path(str(install_dir))

        if progress_callback:
            progress_callback("Ollamaのインストールが完了しました")

        return {"success": True, "message": "Ollamaのインストールが完了しました", "path": str(install_path)}

    except Exception as e:
        return {"success": False, "message": f"ダウンロード失敗: {str(e)}"}


def _add_to_path(directory: str):
    """~/.zshrc や ~/.bash_profile にPATHを追加する（既にある場合はスキップ）"""
    export_line = f'\nexport PATH="{directory}:$PATH"\n'
    for rc_file in [Path.home() / ".zshrc", Path.home() / ".bash_profile", Path.home() / ".bashrc"]:
        if rc_file.exists():
            content = rc_file.read_text()
            if directory not in content:
                with open(rc_file, "a") as f:
                    f.write(export_line)


def install_ollama(progress_callback: Optional[Callable] = None) -> dict:
    """
    Ollamaを自動インストールする。
    Homebrew優先 → 直接バイナリダウンロード
    """
    # まずHomebrewを試みる
    brew = check_homebrew()
    if brew:
        result = install_ollama_via_brew(progress_callback)
        if result["success"]:
            return result
        # Homebrewが失敗したら直接ダウンロードへ

    # 直接ダウンロード
    return install_ollama_binary(progress_callback)


# ===== サービス起動・停止 =====

def start_ollama_service(progress_callback: Optional[Callable] = None) -> dict:
    """
    ollama serve を起動する。
    既に起動中なら何もしない。
    戻り値: {"success": bool, "message": str}
    """
    global _ollama_process

    if is_ollama_running():
        return {"success": True, "message": "Ollamaはすでに起動しています"}

    binary = find_ollama_binary()
    if not binary:
        return {"success": False, "message": "Ollamaがインストールされていません"}

    if progress_callback:
        progress_callback("Ollamaサービスを起動中...")

    try:
        env = os.environ.copy()
        # PATHにbinaryのディレクトリを追加
        bin_dir = str(Path(binary).parent)
        env["PATH"] = bin_dir + ":" + env.get("PATH", "")

        _ollama_process = subprocess.Popen(
            [binary, "serve"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env=env
        )

        # 起動を最大10秒待つ
        for _ in range(20):
            time.sleep(0.5)
            if is_ollama_running():
                if progress_callback:
                    progress_callback("Ollamaサービスの起動が完了しました")
                return {"success": True, "message": "Ollamaサービスを起動しました"}

        return {"success": False, "message": "Ollamaの起動がタイムアウトしました"}

    except Exception as e:
        return {"success": False, "message": f"起動エラー: {str(e)}"}


def stop_ollama_service():
    """管理しているollamaプロセスを停止する"""
    global _ollama_process
    if _ollama_process and _ollama_process.poll() is None:
        _ollama_process.terminate()
        _ollama_process = None


# ===== モデル管理 =====

def get_installed_models() -> list:
    """
    インストール済みモデルの一覧を返す。
    戻り値: [{"name": str, "size_gb": float, "modified": str}, ...]
    """
    if not is_ollama_running():
        return []
    try:
        import urllib.request
        with urllib.request.urlopen("http://localhost:11434/api/tags", timeout=5) as resp:
            data = json.loads(resp.read())
        models = []
        for m in data.get("models", []):
            models.append({
                "name": m.get("name", ""),
                "size_gb": round(m.get("size", 0) / 1e9, 1),
                "modified": m.get("modified_at", "")[:10] if m.get("modified_at") else ""
            })
        return models
    except Exception:
        return []


def pull_model_async(model_name: str) -> str:
    """
    モデルをバックグラウンドでダウンロードする。
    戻り値: task_id（進捗確認に使う）
    """
    task_id = model_name.replace(":", "_").replace("/", "_")
    _pull_progress[task_id] = {
        "model": model_name,
        "status": "開始中...",
        "percent": 0,
        "done": False,
        "error": ""
    }

    def _do_pull():
        binary = find_ollama_binary()
        if not binary:
            _pull_progress[task_id]["error"] = "Ollamaが見つかりません"
            _pull_progress[task_id]["done"] = True
            return

        env = os.environ.copy()
        bin_dir = str(Path(binary).parent)
        env["PATH"] = bin_dir + ":" + env.get("PATH", "")

        try:
            proc = subprocess.Popen(
                [binary, "pull", model_name],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                env=env
            )
            for line in proc.stdout:
                line = line.strip()
                if line:
                    _pull_progress[task_id]["status"] = line[:100]
                    # "pulling xx%" のような行からパーセントを抽出
                    if "%" in line:
                        try:
                            pct = int(line.split("%")[0].split()[-1])
                            _pull_progress[task_id]["percent"] = min(pct, 99)
                        except Exception:
                            pass
            proc.wait()
            if proc.returncode == 0:
                _pull_progress[task_id]["percent"] = 100
                _pull_progress[task_id]["status"] = "ダウンロード完了"
            else:
                _pull_progress[task_id]["error"] = "ダウンロードに失敗しました"
        except Exception as e:
            _pull_progress[task_id]["error"] = str(e)
        finally:
            _pull_progress[task_id]["done"] = True

    thread = threading.Thread(target=_do_pull, daemon=True)
    thread.start()
    return task_id


def get_pull_progress(task_id: str) -> dict:
    """モデルダウンロードの進捗を返す"""
    return _pull_progress.get(task_id, {"error": "タスクが見つかりません", "done": True})


def delete_model(model_name: str) -> dict:
    """モデルを削除する"""
    binary = find_ollama_binary()
    if not binary:
        return {"success": False, "message": "Ollamaが見つかりません"}
    try:
        result = subprocess.run(
            [binary, "rm", model_name],
            capture_output=True, text=True, timeout=30
        )
        if result.returncode == 0:
            return {"success": True, "message": f"{model_name} を削除しました"}
        return {"success": False, "message": result.stderr[:200]}
    except Exception as e:
        return {"success": False, "message": str(e)}


# ===== おすすめモデル一覧 =====

RECOMMENDED_MODELS = [
    {
        "name": "gemma3:4b",
        "display_name": "Gemma 3 (4B) ★おすすめ",
        "description": "Google製。高速・軽量で日本語も得意。M1/M2 Macで快適に動作。",
        "size_gb": 3.3,
        "tags": ["速い", "日本語OK", "軽量"]
    },
    {
        "name": "llama3.2:3b",
        "display_name": "Llama 3.2 (3B)",
        "description": "Meta製。非常に軽量で応答が速い。日常会話に最適。",
        "size_gb": 2.0,
        "tags": ["超軽量", "高速"]
    },
    {
        "name": "qwen2.5:7b",
        "display_name": "Qwen 2.5 (7B)",
        "description": "Alibaba製。日本語・中国語に非常に強い。やや重いが高精度。",
        "size_gb": 4.7,
        "tags": ["日本語最強", "高精度"]
    },
    {
        "name": "mistral:7b",
        "display_name": "Mistral (7B)",
        "description": "フランス製。英語タスクに強く汎用性が高い。",
        "size_gb": 4.1,
        "tags": ["英語得意", "汎用"]
    },
    {
        "name": "phi4:14b",
        "display_name": "Phi-4 (14B)",
        "description": "Microsoft製。大きいが高精度。M2 Pro以上のMac推奨。",
        "size_gb": 8.9,
        "tags": ["高精度", "ハイスペック向け"]
    }
]


def get_full_status() -> dict:
    """アプリ起動時に必要な全ステータスを返す"""
    installed = is_ollama_installed()
    running = is_ollama_running() if installed else False
    models = get_installed_models() if running else []
    brew_available = check_homebrew() is not None

    return {
        "ollama_installed": installed,
        "ollama_running": running,
        "ollama_path": find_ollama_binary(),
        "brew_available": brew_available,
        "installed_models": models,
        "recommended_models": RECOMMENDED_MODELS,
        "setup_complete": installed and running and len(models) > 0
    }
