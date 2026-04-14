"""
OllamaMemoryChat FastAPIバックエンド
全APIエンドポイントを定義する
"""
import sys
import os
from pathlib import Path

# バックエンドディレクトリをパスに追加
sys.path.insert(0, str(Path(__file__).parent))

from fastapi import FastAPI, HTTPException
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, validator, Field
from typing import Optional
import uvicorn
import re
from pathlib import Path

import memory_manager as mm
import command_manager as cm
import ollama_client as oc
import ollama_setup as os_mgr

# DBの初期化（アプリケーション起動時）
mm.init_db()

# PyInstallerバンドル対応: OMCHAT_BASE_DIR 環境変数を優先
_base = Path(os.environ.get('OMCHAT_BASE_DIR', str(Path(__file__).parent.parent)))
_data = Path(os.environ.get('OMCHAT_DATA_DIR', str(_base / 'data')))

# フロントエンドのパス（バンドル内でも通常起動でも正しく解決）
FRONTEND_DIR = _base / "frontend"

def _config_path() -> Path:
    """ユーザー設定 > バンドルデフォルト の順で config.yaml を返す"""
    user_cfg = _data / "config.yaml"
    return user_cfg if user_cfg.exists() else _base / "config.yaml"

app = FastAPI(
    title="OllamaMemoryChat API",
    version="0.1.0",
    openapi_url=None,  # OpenAPI/SwaggerUIを無効化（公開不要）
    docs_url=None,
    redoc_url=None,
)

# CORS設定（ローカルのみ許可）
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:8765", "http://127.0.0.1:8765"],
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["Content-Type"],
)

# セキュリティヘッダーの追加
from starlette.middleware.base import BaseHTTPMiddleware

class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        response = await call_next(request)
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["X-XSS-Protection"] = "1; mode=block"
        response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
        return response

app.add_middleware(SecurityHeadersMiddleware)

# ===== リクエスト・レスポンスモデル =====

class ChatRequest(BaseModel):
    message: str
    session_id: str = "default"

    @validator('message')
    def validate_message(cls, v):
        if len(v) > 10000:
            raise ValueError('メッセージは10000文字以内にしてください')
        return v

    @validator('session_id')
    def validate_session_id(cls, v):
        if not re.match(r'^[a-zA-Z0-9_\-]{1,50}$', v):
            raise ValueError('session_idは英数字・ハイフン・アンダースコアで50文字以内にしてください')
        return v

class ChatResponse(BaseModel):
    reply: str
    command_used: Optional[str] = None
    memory_compressed: bool = False

class CommandCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=50)
    description: str = Field(..., min_length=1, max_length=500)

    @validator('name')
    def validate_cmd_name(cls, v):
        if not re.match(r'^[a-zA-Z0-9_\-]{1,50}$', v):
            raise ValueError('コマンド名は英数字・ハイフン・アンダースコアで50文字以内にしてください')
        return v

class CommandUpdate(BaseModel):
    description: str = Field(..., min_length=1, max_length=500)

class AIEngineUpdate(BaseModel):
    engine: str           # "ollama" or "openai_compatible"
    ollama_endpoint: Optional[str] = Field(None, max_length=300)
    ollama_model: Optional[str] = Field(None, max_length=100)
    openai_endpoint: Optional[str] = Field(None, max_length=300)
    openai_model: Optional[str] = Field(None, max_length=100)
    openai_api_key: Optional[str] = Field(None, max_length=500)

    @validator('engine')
    def validate_engine(cls, v):
        if v not in ["ollama", "openai_compatible"]:
            raise ValueError('エンジンは "ollama" または "openai_compatible" である必要があります')
        return v

    @validator('ollama_endpoint', 'openai_endpoint', pre=True, always=True)
    def validate_endpoint_url(cls, v):
        if v and not (v.startswith('http://') or v.startswith('https://')):
            raise ValueError('エンドポイントは http:// または https:// で始まる必要があります')
        return v

# ===== チャットAPI =====

@app.post("/api/chat", response_model=ChatResponse)
async def chat_endpoint(req: ChatRequest):
    """メインチャットエンドポイント"""
    try:
        command_name, body = cm.parse_command(req.message)
        memory_compressed = False

        # 特殊コマンドの処理（AIを呼ばないもの）
        if command_name == "clear":
            mm.clear_session(req.session_id)
            return ChatResponse(reply="✅ 会話履歴をリセットしました。記憶サマリーは保持されています。", command_used="clear")

        if command_name == "memory":
            summaries = mm.get_all_summaries(req.session_id)
            if not summaries:
                return ChatResponse(reply="📭 まだ記憶サマリーがありません。会話を続けると自動的に記憶が作成されます。", command_used="memory")
            latest = summaries[0]
            reply = f"🧠 **最新の記憶サマリー**（{latest['created_at'][:10]}更新）\n\n{latest['summary']}"
            return ChatResponse(reply=reply, command_used="memory")

        if command_name == "help":
            commands = cm.get_all_commands()
            help_text = "📋 **使用可能なコマンド一覧**\n\n"
            for cmd in commands:
                source_label = "（組み込み）" if cmd["source"] == "builtin" else "（ユーザー定義）"
                help_text += f"• `/{cmd['name']}` — {cmd['description']} {source_label}\n"
            help_text += "\n💡 コマンドの追加・編集は設定画面から行えます。"
            return ChatResponse(reply=help_text, command_used="help")

        # AI呼び出しが必要なコマンドまたは通常会話
        if command_name:
            # コマンドプロンプトを取得
            command_prompt = cm.get_command_prompt(command_name, body)
            if command_prompt:
                # コマンドは記憶を使わずに直接処理
                reply = oc.chat(
                    messages=[{"role": "user", "content": command_prompt}],
                    system_prompt="あなたは指示に従って正確に作業を行うAIアシスタントです。余計な説明は不要です。"
                )
                return ChatResponse(reply=reply, command_used=command_name)
            else:
                raise HTTPException(status_code=404, detail=f"コマンド /{command_name} が見つかりません")

        # 通常の会話処理
        # 記憶注入したシステムプロンプトを構築
        system_prompt = mm.build_system_prompt(session_id=req.session_id)

        # 最近の会話履歴を取得
        recent_messages = mm.get_recent_messages(session_id=req.session_id, limit=10)
        recent_messages.append({"role": "user", "content": req.message})

        # AI呼び出し
        reply = oc.chat(messages=recent_messages, system_prompt=system_prompt)

        # 会話を保存
        mm.add_message("user", req.message, req.session_id)
        mm.add_message("assistant", reply, req.session_id)

        # 圧縮が必要か確認
        if mm.should_compress(req.session_id):
            mm.compress_memory(req.session_id)
            memory_compressed = True

        return ChatResponse(reply=reply, memory_compressed=memory_compressed)

    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        # 詳細なエラーメッセージをログに記録（外部には返さない）
        import logging
        logging.error(f"Chat error: {str(e)}")
        raise HTTPException(status_code=500, detail="チャット処理中にエラーが発生しました")

# ===== 記憶API =====

@app.get("/api/memory")
async def get_memory(session_id: str = "default"):
    """記憶サマリー一覧を返す"""
    summaries = mm.get_all_summaries(session_id)
    return {"summaries": summaries}

@app.delete("/api/memory/{session_id}")
async def clear_memory(session_id: str = "default"):
    """記憶とメッセージをすべてクリアする"""
    mm.clear_session(session_id)
    conn = mm.get_db_connection()
    conn.execute("DELETE FROM memory_summaries WHERE session_id = ?", (session_id,))
    conn.commit()
    conn.close()
    return {"success": True, "message": "記憶をすべて削除しました"}

# ===== コマンドAPI =====

@app.get("/api/commands")
async def list_commands():
    """全コマンド一覧を返す"""
    return {"commands": cm.get_all_commands()}

@app.get("/api/commands/names")
async def get_command_names():
    """コマンド名リストを返す（UI補完用）"""
    return {"names": cm.get_command_names()}

@app.post("/api/commands")
async def create_command(cmd: CommandCreate):
    """ユーザー定義コマンドを作成する"""
    result = cm.add_user_command(cmd.name, cmd.description)
    if not result["success"]:
        raise HTTPException(status_code=400, detail=result["message"])
    return result

@app.put("/api/commands/{name}")
async def update_command(name: str, cmd: CommandUpdate):
    """ユーザー定義コマンドを更新する"""
    result = cm.update_user_command(name, cmd.description)
    if not result["success"]:
        raise HTTPException(status_code=404, detail=result["message"])
    return result

@app.delete("/api/commands/{name}")
async def delete_command(name: str):
    """ユーザー定義コマンドを削除する"""
    result = cm.delete_user_command(name)
    if not result["success"]:
        raise HTTPException(status_code=404, detail=result["message"])
    return result

# ===== 設定API =====

@app.get("/api/settings")
async def get_settings():
    """現在の設定を返す（APIキーは除く）"""
    import yaml
    config_path = _config_path()
    with open(config_path, "r") as f:
        config = yaml.safe_load(f)
    # APIキーはマスク
    if config.get("ai", {}).get("openai_api_key"):
        config["ai"]["openai_api_key"] = "***設定済み***"
    return config

@app.post("/api/settings/ai")
async def update_ai_settings(settings: AIEngineUpdate):
    """AI設定を更新する"""
    import yaml
    config_path = _config_path()
    with open(config_path, "r") as f:
        config = yaml.safe_load(f)

    config["ai"]["engine"] = settings.engine
    if settings.ollama_endpoint:
        config["ai"]["ollama_endpoint"] = settings.ollama_endpoint
    if settings.ollama_model:
        config["ai"]["ollama_model"] = settings.ollama_model
    if settings.openai_endpoint:
        config["ai"]["openai_endpoint"] = settings.openai_endpoint
    if settings.openai_model:
        config["ai"]["openai_model"] = settings.openai_model
    if settings.openai_api_key:
        config["ai"]["openai_api_key"] = settings.openai_api_key

    with open(config_path, "w") as f:
        yaml.dump(config, f, allow_unicode=True, default_flow_style=False)

    return {"success": True, "message": "設定を保存しました"}

@app.get("/api/status")
async def get_status():
    """Ollamaの起動状態などシステム状態を返す"""
    ollama_running = oc.is_ollama_running()
    engine = oc.get_client_type()
    return {
        "status": "ok",
        "engine": engine,
        "ollama_running": ollama_running,
    }

# ===== Ollama セットアップ管理API =====

@app.get("/api/setup/status")
async def get_setup_status():
    """アプリ起動時の完全なステータス（インストール・起動・モデル状況）"""
    return os_mgr.get_full_status()


@app.post("/api/setup/install")
async def install_ollama():
    """
    Ollamaを自動インストールする。
    Homebrew優先、なければ直接バイナリダウンロード。
    """
    if os_mgr.is_ollama_installed():
        return {"success": True, "message": "Ollamaはすでにインストールされています"}

    progress_messages = []

    def on_progress(msg: str):
        progress_messages.append(msg)

    result = os_mgr.install_ollama(progress_callback=on_progress)
    result["progress"] = progress_messages
    return result


@app.post("/api/setup/start")
async def start_ollama():
    """ollama serve を起動する"""
    result = os_mgr.start_ollama_service()
    return result


@app.get("/api/setup/models")
async def list_models():
    """インストール済みモデル一覧 + おすすめモデル一覧"""
    installed = os_mgr.get_installed_models()
    installed_names = {m["name"] for m in installed}

    recommended = []
    for m in os_mgr.RECOMMENDED_MODELS:
        recommended.append({
            **m,
            "installed": m["name"] in installed_names
        })

    return {
        "installed": installed,
        "recommended": recommended
    }


@app.post("/api/setup/pull/{model_name:path}")
async def pull_model(model_name: str):
    """モデルのダウンロードを開始する（非同期）"""
    if not os_mgr.is_ollama_running():
        raise HTTPException(status_code=400, detail="Ollamaが起動していません。先にサービスを起動してください。")

    task_id = os_mgr.pull_model_async(model_name)
    return {"task_id": task_id, "message": f"{model_name} のダウンロードを開始しました"}


@app.get("/api/setup/pull/progress/{task_id}")
async def get_pull_progress(task_id: str):
    """モデルダウンロードの進捗を返す"""
    return os_mgr.get_pull_progress(task_id)


@app.delete("/api/setup/models/{model_name:path}")
async def delete_model(model_name: str):
    """モデルを削除する"""
    result = os_mgr.delete_model(model_name)
    if not result["success"]:
        raise HTTPException(status_code=400, detail=result["message"])
    return result


@app.post("/api/setup/select-model")
async def select_model(body: dict):
    """使用するモデルを設定ファイルに保存する"""
    model_name = body.get("model")
    if not model_name:
        raise HTTPException(status_code=400, detail="モデル名が必要です")

    import yaml
    config_path = _config_path()
    with open(config_path, "r") as f:
        config = yaml.safe_load(f)

    config["ai"]["ollama_model"] = model_name
    config["ai"]["engine"] = "ollama"

    with open(config_path, "w") as f:
        yaml.dump(config, f, allow_unicode=True, default_flow_style=False)

    return {"success": True, "message": f"モデルを {model_name} に設定しました"}


@app.get("/setup")
async def serve_setup():
    """セットアップ画面を配信"""
    setup_path = FRONTEND_DIR / "setup.html"
    if setup_path.exists():
        return FileResponse(str(setup_path))
    raise HTTPException(status_code=404, detail="setup.html not found")

# ===== フロントエンド配信 =====

# 静的ファイルのマウント
if FRONTEND_DIR.exists():
    app.mount("/assets", StaticFiles(directory=str(FRONTEND_DIR / "assets")), name="assets")

@app.get("/")
async def serve_index():
    return FileResponse(str(FRONTEND_DIR / "index.html"))

@app.get("/settings")
async def serve_settings():
    return FileResponse(str(FRONTEND_DIR / "settings.html"))

# ===== 起動 =====

def start_server(port: int = 8765):
    """サーバーを起動する"""
    import yaml
    config_path = _config_path()
    with open(config_path, "r") as f:
        config = yaml.safe_load(f)
    port = config.get("app", {}).get("port", 8765)
    uvicorn.run(app, host="127.0.0.1", port=port, log_level="warning")

if __name__ == "__main__":
    start_server()
