"""
Memoria FastAPIバックエンド
全APIエンドポイントを定義する
"""
import sys
import os
import subprocess
import re as _re
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

def _get_system_language() -> str:
    """macOSのシステム言語を取得する。ja / en / es のいずれかを返す。"""
    try:
        result = subprocess.run(
            ["defaults", "read", ".GlobalPreferences", "AppleLanguages"],
            capture_output=True, text=True, timeout=2
        )
        # 出力例: (\n    ja,\n    "en-JP",\n    "es-MX"\n)
        match = _re.search(r'"?([a-z]{2})"?', result.stdout)
        if match:
            lang = match.group(1)
            if lang in ("ja", "en", "es"):
                return lang
    except Exception:
        pass
    # フォールバック: 環境変数 LANG から取得
    env_lang = os.environ.get("LANG", "ja_JP")
    code = env_lang[:2].lower()
    return code if code in ("ja", "en", "es") else "ja"

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

def _generate_smart_title(message: str, max_len: int = 20) -> str:
    """Fix⑨: メッセージから自然なタイトルを生成する。
    句読点・スペース・改行で切り、最大 max_len 文字で省略。
    コマンド（/から始まる）は除いてタイトル化する。
    """
    # コマンドプレフィックスを除去
    text = message.strip()
    if text.startswith('/'):
        parts = text.split(None, 1)
        text = parts[1].strip() if len(parts) > 1 else text

    # 最初の文（句読点・改行・スペースで分割）- re はモジュールレベルでインポート済み
    m = re.split(r'[。！？\n\r.!?]', text)
    first = m[0].strip() if m else text.strip()

    if not first:
        first = text.strip()

    if len(first) <= max_len:
        return first or "新しいチャット"

    # max_len 文字で切り「...」を付ける
    return first[:max_len - 1] + "…"


app = FastAPI(
    title="Memoria API",
    version="0.1.0",
    openapi_url=None,  # OpenAPI/SwaggerUIを無効化（公開不要）
    docs_url=None,
    redoc_url=None,
)

# CORS設定（ローカルのみ許可）
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:18765", "http://127.0.0.1:18765"],
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
    prompt_template: Optional[str] = Field(None, max_length=4000)  # 任意：指定なければdescriptionから自動生成

    @validator('name')
    def validate_cmd_name(cls, v):
        if not re.match(r'^[a-zA-Z0-9_\-]{1,50}$', v):
            raise ValueError('コマンド名は英数字・ハイフン・アンダースコアで50文字以内にしてください')
        return v

class CommandUpdate(BaseModel):
    description: str = Field(..., min_length=1, max_length=500)
    prompt_template: Optional[str] = Field(None, max_length=4000)

class AIEngineUpdate(BaseModel):
    engine: str           # "ollama" / "openai_compatible" / "claude" / "gemini"
    ollama_endpoint: Optional[str] = Field(None, max_length=300)
    ollama_model: Optional[str] = Field(None, max_length=100)
    openai_endpoint: Optional[str] = Field(None, max_length=300)
    openai_model: Optional[str] = Field(None, max_length=100)
    openai_api_key: Optional[str] = Field(None, max_length=500)
    claude_api_key: Optional[str] = Field(None, max_length=500)
    claude_model: Optional[str] = Field(None, max_length=100)
    gemini_api_key: Optional[str] = Field(None, max_length=500)
    gemini_model: Optional[str] = Field(None, max_length=100)

    @validator('engine')
    def validate_engine(cls, v):
        if v not in ["ollama", "openai_compatible", "claude", "gemini"]:
            raise ValueError('エンジンは "ollama" / "openai_compatible" / "claude" / "gemini" のいずれかです')
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
        # セッションが存在しない場合は作成（最初のメッセージの最初の20文字をタイトルに）
        mm.ensure_session_exists(req.session_id)
        existing_messages = mm.get_recent_messages(req.session_id, limit=1)
        if not existing_messages:
            # このセッションは初めて。タイトルを設定する（Fix⑨: スマートタイトル生成）
            title = _generate_smart_title(req.message)
            mm.update_session_title(req.session_id, title)

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
            reply = f"💾 **最新の記憶サマリー**（{latest['created_at'][:10]}更新）\n\n{latest['summary']}"
            return ChatResponse(reply=reply, command_used="memory")

        if command_name == "help":
            commands = cm.get_all_commands()
            help_text = "📋 **使用可能なコマンド一覧**\n\n"
            for cmd in commands:
                source_label = "（組み込み）" if cmd["source"] == "builtin" else "（ユーザー定義）"
                help_text += f"• `/{cmd['name']}` — {cmd['description']} {source_label}\n"
            help_text += "\n💡 コマンドの追加・編集は設定画面から行えます。"
            return ChatResponse(reply=help_text, command_used="help")

        if command_name == "remember":
            # グローバルメモリに保存（例: /remember 私の名前はDaichi）
            if not body.strip():
                return ChatResponse(reply="💡 使い方: `/remember 覚えておいてほしい内容`\n例: `/remember 私の名前はDaichi`", command_used="remember")
            result = mm.add_global_memory(body.strip(), source="manual")
            if result["success"]:
                return ChatResponse(reply=f"✅ 覚えました！\n\n「{body.strip()}」\n\nこの情報はすべてのセッションで参照されます。設定画面の「記憶の管理」から確認・削除できます。", command_used="remember")
            return ChatResponse(reply=f"❌ 保存に失敗しました: {result.get('message', '')}", command_used="remember")

        if command_name == "grammar":
            if not body.strip():
                return ChatResponse(reply="💡 使い方: `/grammar [分析したいテキスト]`\n例: `/grammar She don't know nothing about it.`", command_used="grammar")
            lang_code = _get_system_language()
            if lang_code == "en":
                grammar_prompt = f"""Language analysis example:
Text: She don't know nothing about it.
Translation: She doesn't know anything about it.
Recommended alternatives:
• She doesn't know anything about it.
• She has no knowledge of it.
• She knows nothing about it.
Grammar notes: "don't" is wrong with "She" — use "doesn't". "Don't know nothing" is a double negative; use "don't know anything".

---
Text: {body}
Translation:
Recommended alternatives:
•
•
•
Grammar notes:"""
            elif lang_code == "es":
                grammar_prompt = f"""Ejemplo de análisis:
Texto: She don't know nothing about it.
Traducción: Ella no sabe nada al respecto.
Expresiones alternativas recomendadas:
• She doesn't know anything about it.
• She has no knowledge of it.
• She knows nothing about it.
Explicación gramatical: "don't" es incorrecto con "She" — usar "doesn't". "Don't know nothing" es doble negación; usar "don't know anything".

---
Texto: {body}
Traducción:
Expresiones alternativas recomendadas:
•
•
•
Explicación gramatical:"""
            else:
                grammar_prompt = f"""語学分析の例:
テキスト: She don't know nothing about it.
翻訳: 彼女はそれについて何も知りません。
推奨される代替表現:
• She doesn't know anything about it.
• She has no knowledge of it.
• She knows nothing about it.
文法的な解説: "don't"は三人称単数の主語"She"には使えず"doesn't"が正しい。"don't know nothing"は二重否定のため"don't know anything"を使う。

---
テキスト: {body}
翻訳:
推奨される代替表現:
•
•
•
文法的な解説:"""
            reply = oc.chat(
                messages=[{"role": "user", "content": grammar_prompt}],
                system_prompt="あなたは語学教師です。指定されたフォーマットで正確に回答してください。"
            )
            return ChatResponse(reply=reply, command_used="grammar")

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

        # 最近の会話履歴を取得（20メッセージ = 10往復分）
        recent_messages = mm.get_recent_messages(session_id=req.session_id, limit=20)
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
        # APIキー未設定・APIエラーなど（すでにわかりやすいメッセージ）
        raise HTTPException(status_code=400, detail=str(e))
    except oc.ResponseError as e:
        import logging
        logging.error(f"Ollama model error: {str(e)}")
        raise HTTPException(status_code=400, detail="🔍 指定されたモデルが見つかりません。設定画面でモデルを確認してください。")
    except (ConnectionRefusedError, Exception) as e:
        import logging
        error_type_name = type(e).__name__
        err_str = str(e)
        logging.error(f"Chat error ({error_type_name}): {err_str}")

        if "Connection refused" in err_str or "ConnectionRefused" in error_type_name or "URLError" in error_type_name:
            raise HTTPException(status_code=500, detail="📡 Ollamaに接続できません。Ollamaが起動しているか確認してください。")
        if "timeout" in err_str.lower() or "Timeout" in error_type_name:
            raise HTTPException(status_code=500, detail="⏰ AIの応答がタイムアウトしました。しばらく待ってから再試行してください。")
        raise HTTPException(status_code=500, detail=f"❌ 予期しないエラーが発生しました ({error_type_name})")

# ===== セッション管理API =====

@app.get("/api/sessions")
async def list_sessions():
    """セッション一覧を返す"""
    sessions = mm.get_sessions()
    return {"sessions": sessions}

@app.post("/api/sessions")
async def create_session(body: dict):
    """新しいセッションを作成する"""
    session_id = body.get("session_id")
    title = body.get("title", "新しいチャット")

    if not session_id:
        # session_idが与えられない場合はUUIDで生成
        import uuid
        session_id = str(uuid.uuid4())

    result = mm.create_session(session_id, title)
    if not result["success"]:
        raise HTTPException(status_code=400, detail=result["message"])
    return result

@app.delete("/api/sessions/{session_id}")
async def delete_session(session_id: str):
    """セッションを削除する"""
    mm.delete_session(session_id)
    return {"success": True, "message": "セッションを削除しました"}

@app.put("/api/sessions/{session_id}/title")
async def rename_session(session_id: str, body: dict):
    """セッションのタイトルを更新する"""
    title = body.get("title")
    if not title:
        raise HTTPException(status_code=400, detail="タイトルは必須です")
    mm.update_session_title(session_id, title)
    return {"success": True, "message": "タイトルを更新しました"}

@app.get("/api/messages/{session_id}")
async def get_messages(session_id: str):
    """セッションのメッセージを取得する"""
    messages = mm.get_session_messages(session_id)
    return {"messages": messages}

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

# ===== グローバルメモリAPI =====

class GlobalMemoryCreate(BaseModel):
    content: str = Field(..., min_length=1, max_length=500)

@app.get("/api/global-memory")
async def list_global_memory():
    """グローバルメモリ一覧を返す"""
    items = mm.get_global_memory()
    return {"items": items}

@app.post("/api/global-memory")
async def add_global_memory(body: GlobalMemoryCreate):
    """グローバルメモリに追加する"""
    result = mm.add_global_memory(body.content, source="manual")
    if not result["success"]:
        raise HTTPException(status_code=400, detail=result.get("message", "保存に失敗しました"))
    return result

@app.delete("/api/global-memory/{item_id}")
async def delete_global_memory(item_id: int):
    """グローバルメモリの1件を削除する"""
    deleted = mm.delete_global_memory_item(item_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="指定の記憶が見つかりません")
    return {"success": True}

@app.delete("/api/global-memory")
async def clear_global_memory():
    """グローバルメモリをすべて削除する"""
    mm.clear_global_memory()
    return {"success": True, "message": "グローバルメモリをすべて削除しました"}

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
    """ユーザー定義コマンドを作成する（組み込みコマンド名でも上書き可能）"""
    result = cm.add_user_command(cmd.name, cmd.description, cmd.prompt_template or "")
    if not result["success"]:
        raise HTTPException(status_code=400, detail=result["message"])
    return result

@app.put("/api/commands/{name}")
async def update_command(name: str, cmd: CommandUpdate):
    """ユーザー定義コマンドを更新する"""
    result = cm.update_user_command(name, cmd.description, cmd.prompt_template or "")
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
    ai = config.get("ai", {})
    # APIキーはマスク（空なら空のまま、設定済みなら***に）
    for key in ["openai_api_key", "claude_api_key", "gemini_api_key"]:
        if ai.get(key):
            ai[key] = "***設定済み***"
    # 新フィールドが古いconfigになければ空文字を補完
    for k in ["claude_api_key", "claude_model", "gemini_api_key", "gemini_model"]:
        if k not in ai:
            ai[k] = ""
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
    # Claude
    if settings.claude_api_key:
        config["ai"]["claude_api_key"] = settings.claude_api_key
    if settings.claude_model:
        config["ai"]["claude_model"] = settings.claude_model
    # Gemini
    if settings.gemini_api_key:
        config["ai"]["gemini_api_key"] = settings.gemini_api_key
    if settings.gemini_model:
        config["ai"]["gemini_model"] = settings.gemini_model
    # 新フィールドが config.yaml になければ初期値を設定
    for k in ["claude_api_key", "claude_model", "gemini_api_key", "gemini_model"]:
        if k not in config["ai"]:
            config["ai"][k] = ""

    with open(config_path, "w") as f:
        yaml.dump(config, f, allow_unicode=True, default_flow_style=False)

    return {"success": True, "message": "設定を保存しました"}

@app.get("/api/status")
async def get_status():
    """Ollamaの起動状態などシステム状態を返す"""
    ollama_running = oc.is_ollama_running()
    engine = oc.get_client_type()
    model_label = oc.get_current_model_label()
    return {
        "status": "ok",
        "engine": engine,
        "ollama_running": ollama_running,
        "model_label": model_label,
    }

class EngineSwitch(BaseModel):
    engine: str
    model: Optional[str] = None

@app.post("/api/switch-engine")
async def switch_engine(req: EngineSwitch):
    """チャット画面からエンジンを素早く切り替える"""
    import yaml
    valid_engines = ["ollama", "openai_compatible", "claude", "gemini"]
    if req.engine not in valid_engines:
        raise HTTPException(status_code=400, detail=f"無効なエンジン: {req.engine}")
    config_path = _config_path()
    with open(config_path, "r") as f:
        config = yaml.safe_load(f)
    config["ai"]["engine"] = req.engine
    # モデル指定があれば合わせて更新
    if req.model:
        model_key = {
            "ollama": "ollama_model",
            "openai_compatible": "openai_model",
            "claude": "claude_model",
            "gemini": "gemini_model",
        }.get(req.engine)
        if model_key:
            config["ai"][model_key] = req.model
    with open(config_path, "w") as f:
        yaml.dump(config, f, allow_unicode=True, default_flow_style=False)
    return {"success": True, "engine": req.engine, "model_label": oc.get_current_model_label()}

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

# ===== 音声入力 API (オフライン: sounddevice + faster-whisper) =====
# voice_manager の import は遅延実行:
# sounddevice / faster-whisper が未インストールの環境でもアプリが起動できる。

def _get_voice_manager():
    """voice_manager をその場でインポートして返す。依存ライブラリがなければ None。"""
    try:
        import voice_manager as _vm
        return _vm
    except ImportError as e:
        return None

@app.post("/api/voice/start")
async def voice_start():
    """マイク録音を開始する"""
    vm = _get_voice_manager()
    if vm is None:
        return {"success": False, "message": "音声入力ライブラリが利用できません（sounddevice / faster-whisper）"}
    return vm.start_recording()

class VoiceStopRequest(BaseModel):
    language: Optional[str] = None   # "ja" / "en" / "es" / None（自動検出）

@app.post("/api/voice/stop")
async def voice_stop(req: VoiceStopRequest = VoiceStopRequest()):
    """録音を停止してWhisperで文字起こしする"""
    vm = _get_voice_manager()
    if vm is None:
        return {"success": False, "message": "音声入力ライブラリが利用できません"}
    return vm.stop_and_transcribe(language=req.language)

@app.get("/api/voice/status")
async def voice_status():
    """録音中かどうかを返す"""
    vm = _get_voice_manager()
    if vm is None:
        return {"recording": False, "available": False}
    return {"recording": vm.is_recording(), "available": True}

@app.get("/api/voice/model-status")
async def voice_model_status():
    """Whisperモデルの利用可否を返す"""
    vm = _get_voice_manager()
    if vm is None:
        return {"available": False, "message": "音声入力ライブラリが未インストールです"}
    return vm.get_model_status()

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

def start_server(port: int = 18765):
    """サーバーを起動する"""
    import yaml
    config_path = _config_path()
    with open(config_path, "r") as f:
        config = yaml.safe_load(f)
    port = config.get("app", {}).get("port", 18765)
    uvicorn.run(app, host="127.0.0.1", port=port, log_level="warning")

if __name__ == "__main__":
    start_server()
