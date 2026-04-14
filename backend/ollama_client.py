import yaml
import os
import requests
from pathlib import Path

# PyInstallerバンドル対応: OMCHAT_BASE_DIR 環境変数を優先
_base = Path(os.environ.get('OMCHAT_BASE_DIR', str(Path(__file__).parent.parent)))
_data = Path(os.environ.get('OMCHAT_DATA_DIR', str(_base / 'data')))
# ユーザー設定 > バンドルデフォルト の順で読む
CONFIG_PATH = (_data / "config.yaml") if (_data / "config.yaml").exists() else (_base / "config.yaml")

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
    else:
        raise ValueError(f"Unknown engine: {engine}")

def _chat_ollama(messages: list, system_prompt: str, config: dict) -> str:
    import ollama as ollama_lib
    model = config["ai"]["ollama_model"]
    endpoint = config["ai"]["ollama_endpoint"]

    # ollamaライブラリのクライアントを初期化
    client = ollama_lib.Client(host=endpoint)

    # messagesにsystem_promptを先頭に追加
    full_messages = []
    if system_prompt:
        full_messages.append({"role": "system", "content": system_prompt})
    full_messages.extend(messages)

    response = client.chat(model=model, messages=full_messages)
    return response["message"]["content"]

def _chat_openai(messages: list, system_prompt: str, config: dict) -> str:
    import openai
    api_key = config["ai"]["openai_api_key"]
    endpoint = config["ai"]["openai_endpoint"]
    model = config["ai"]["openai_model"]

    client = openai.OpenAI(api_key=api_key, base_url=endpoint)

    full_messages = []
    if system_prompt:
        full_messages.append({"role": "system", "content": system_prompt})
    full_messages.extend(messages)

    response = client.chat.completions.create(model=model, messages=full_messages)
    return response.choices[0].message.content

def get_client_type() -> str:
    config = load_config()
    return config["ai"]["engine"]
