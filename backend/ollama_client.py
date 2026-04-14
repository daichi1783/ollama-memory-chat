import yaml
import os
import requests
from pathlib import Path

# PyInstallerバンドル対応: OMCHAT_BASE_DIR 環境変数を優先
_base = Path(os.environ.get('OMCHAT_BASE_DIR', str(Path(__file__).parent.parent)))
_data = Path(os.environ.get('OMCHAT_DATA_DIR', str(_base / 'data')))
# ユーザー設定 > バンドルデフォルト の順で読む
CONFIG_PATH = (_data / "config.yaml") if (_data / "config.yaml").exists() else (_base / "config.yaml")

# Ollama ResponseError を外部から参照できるようにエクスポート
try:
    from ollama import ResponseError
except ImportError:
    class ResponseError(Exception):
        pass

def load_config():
    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
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

def _chat_claude(messages: list, system_prompt: str, config: dict) -> str:
    """Anthropic Claude APIを直接呼び出す"""
    api_key = config["ai"].get("claude_api_key", "")
    model = config["ai"].get("claude_model", "claude-sonnet-4-6")

    if not api_key:
        raise ValueError("Anthropic APIキーが設定されていません。設定画面で入力してください。")

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
        raise ValueError(f"Claude API エラー ({resp.status_code}): {resp.text[:200]}")
    return resp.json()["content"][0]["text"]

def _chat_gemini(messages: list, system_prompt: str, config: dict) -> str:
    """Google Gemini API（OpenAI互換エンドポイント）を呼び出す"""
    api_key = config["ai"].get("gemini_api_key", "")
    model = config["ai"].get("gemini_model", "gemini-2.0-flash")

    if not api_key:
        raise ValueError("Google API キーが設定されていません。設定画面で入力してください。")

    full_messages = []
    if system_prompt:
        full_messages.append({"role": "system", "content": system_prompt})
    full_messages.extend(messages)

    headers = {
        "Content-Type": "application/json",
    }
    body = {
        "model": model,
        "messages": full_messages,
        "max_tokens": 4096,
    }

    resp = requests.post(
        f"https://generativelanguage.googleapis.com/v1beta/openai/chat/completions?key={api_key}",
        headers=headers,
        json=body,
        timeout=60,
    )
    if not resp.ok:
        raise ValueError(f"Gemini API エラー ({resp.status_code}): {resp.text[:200]}")
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
