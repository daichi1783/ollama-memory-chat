import yaml
import os
import requests
from pathlib import Path

# Ollama ResponseError を外部から参照できるようにエクスポート
try:
    from ollama import ResponseError
except ImportError:
    class ResponseError(Exception):
        pass

def _resolve_config_path() -> Path:
    """
    設定ファイルパスを毎回動的に解決する。
    モジュールインポート時に固定すると PyInstaller バンドル内で
    main.py と異なるパスを参照してしまうため、呼び出しごとに評価する。
    """
    base = Path(os.environ.get('OMCHAT_BASE_DIR', str(Path(__file__).parent.parent)))
    data = Path(os.environ.get('OMCHAT_DATA_DIR', str(base / 'data')))
    user_cfg = data / "config.yaml"
    return user_cfg if user_cfg.exists() else base / "config.yaml"

def load_config():
    with open(_resolve_config_path(), "r", encoding="utf-8") as f:
        return yaml.safe_load(f)

def is_ollama_running() -> bool:
    """Ollamaが起動しているか確認する"""
    config = load_config()
    endpoint = config["ai"]["ollama_endpoint"]
    try:
        import urllib.request
        with urllib.request.urlopen(f"{endpoint}/api/tags", timeout=3) as r:
            return r.status == 200
    except Exception:
        return False

def chat(messages: list, system_prompt: str = "") -> str:
    """
    messages: [{"role": "user"/"assistant", "content": "..."}]
    system_prompt: システムプロンプト文字列
    戻り値: AIの応答テキスト
    """
    config = load_config()
    engine = config["ai"]["engine"]

    if engine == "ollama":
        return _chat_ollama(messages, system_prompt, config)
    elif engine == "openai_compatible":
        return _chat_openai(messages, system_prompt, config)
    elif engine == "claude":
        return _chat_claude(messages, system_prompt, config)
    elif engine == "gemini":
        return _chat_gemini(messages, system_prompt, config)
    else:
        raise ValueError(f"Unknown engine: {engine}")

def _chat_ollama(messages: list, system_prompt: str, config: dict) -> str:
    import ollama as ollama_lib
    model = config["ai"]["ollama_model"]
    endpoint = config["ai"]["ollama_endpoint"]

    client = ollama_lib.Client(host=endpoint)

    full_messages = []
    if system_prompt:
        full_messages.append({"role": "system", "content": system_prompt})
    full_messages.extend(messages)

    response = client.chat(model=model, messages=full_messages)
    return response["message"]["content"]

def _chat_openai(messages: list, system_prompt: str, config: dict) -> str:
    import openai
    api_key = config["ai"].get("openai_api_key", "")
    endpoint = config["ai"].get("openai_endpoint", "")
    model = config["ai"].get("openai_model", "gpt-4o")

    client = openai.OpenAI(api_key=api_key, base_url=endpoint)

    full_messages = []
    if system_prompt:
        full_messages.append({"role": "system", "content": system_prompt})
    full_messages.extend(messages)

    response = client.chat.completions.create(model=model, messages=full_messages)
    return response.choices[0].message.content

def _parse_api_error(status_code: int, resp_text: str, provider: str) -> str:
    """APIエラーレスポンスをユーザー向けのわかりやすい日本語メッセージに変換する"""
    import json
    # JSONからメッセージを抽出
    raw_msg = ""
    try:
        err = json.loads(resp_text)
        # Gemini: [{"error": {"message": "..."}}]
        if isinstance(err, list) and err:
            err = err[0]
        # {"error": {"message": "..."}} 形式
        if isinstance(err, dict):
            raw_msg = (err.get("error", {}).get("message", "")
                       or err.get("message", "")
                       or str(err))
    except Exception:
        raw_msg = resp_text[:150]

    # ステータスコード別の日本語メッセージ
    if status_code == 401 or status_code == 403:
        return f"🔑 {provider} APIキーが無効または権限がありません。設定画面でAPIキーを確認してください。"
    if status_code == 429:
        if "spending cap" in raw_msg or "quota" in raw_msg.lower():
            return (f"⚠️ {provider} の月間利用上限に達しました。"
                    "APIコンソールで上限を確認・変更してください。")
        return f"⏱ {provider} のリクエスト制限に達しました。しばらく待ってから再試行してください。"
    if status_code == 400:
        if "Authorization" in raw_msg or "auth" in raw_msg.lower():
            return f"🔑 {provider} の認証に失敗しました。APIキーを確認してください。"
        if "model" in raw_msg.lower():
            return f"🔍 {provider} モデル名が無効です。設定画面でモデルを確認してください。"
        return f"❌ {provider} へのリクエストが無効です: {raw_msg[:100]}"
    if status_code in (500, 502, 503):
        return f"🌐 {provider} のサービスが一時的に利用できません。しばらく待ってから再試行してください。"
    return f"❌ {provider} API エラー ({status_code}): {raw_msg[:120]}"


def _chat_claude(messages: list, system_prompt: str, config: dict) -> str:
    """Anthropic Claude APIを直接呼び出す"""
    api_key = config["ai"].get("claude_api_key", "")
    model = config["ai"].get("claude_model", "claude-sonnet-4-6")

    if not api_key:
        raise ValueError("🔑 Anthropic APIキーが設定されていません。設定画面で入力してください。")

    headers = {
        "x-api-key": api_key,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
    }

    body = {
        "model": model,
        "max_tokens": 4096,
        "messages": messages,
    }
    if system_prompt:
        body["system"] = system_prompt

    resp = requests.post(
        "https://api.anthropic.com/v1/messages",
        headers=headers,
        json=body,
        timeout=60,
    )
    if not resp.ok:
        raise ValueError(_parse_api_error(resp.status_code, resp.text, "Claude"))
    return resp.json()["content"][0]["text"]

def _chat_gemini(messages: list, system_prompt: str, config: dict) -> str:
    """Google Gemini API（OpenAI互換エンドポイント）を呼び出す"""
    api_key = config["ai"].get("gemini_api_key", "")
    model = config["ai"].get("gemini_model", "gemini-2.0-flash")

    if not api_key:
        raise ValueError("🔑 Google API キーが設定されていません。設定画面で入力してください。")

    full_messages = []
    if system_prompt:
        full_messages.append({"role": "system", "content": system_prompt})
    full_messages.extend(messages)

    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}",  # OpenAI互換エンドポイントはBearerヘッダーで認証
    }
    body = {
        "model": model,
        "messages": full_messages,
        "max_tokens": 4096,
    }

    resp = requests.post(
        "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
        headers=headers,
        json=body,
        timeout=60,
    )
    if not resp.ok:
        raise ValueError(_parse_api_error(resp.status_code, resp.text, "Gemini"))
    return resp.json()["choices"][0]["message"]["content"]

def get_client_type() -> str:
    config = load_config()
    return config["ai"]["engine"]

def get_current_model_label() -> str:
    """チャット画面に表示するエンジン+モデル名を返す"""
    config = load_config()
    engine = config["ai"]["engine"]
    if engine == "ollama":
        return f"Ollama / {config['ai'].get('ollama_model', '?')}"
    elif engine == "openai_compatible":
        return f"OpenAI互換 / {config['ai'].get('openai_model', '?')}"
    elif engine == "claude":
        return f"Claude / {config['ai'].get('claude_model', '?')}"
    elif engine == "gemini":
        return f"Gemini / {config['ai'].get('gemini_model', '?')}"
    return engine
