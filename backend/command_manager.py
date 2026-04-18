"""
スラッシュコマンド管理モジュール
- config.yamlの組み込みコマンド
- SQLiteのユーザー定義コマンド
- コマンドの解析・実行
"""
import yaml
import sqlite3
from pathlib import Path
from datetime import datetime
from memory_manager import get_db_connection

CONFIG_PATH = Path(__file__).parent.parent / "config.yaml"

# 常に利用できる組み込みコマンド（config.yamlに依存しない）
_HARDCODED_COMMANDS = [
    {
        "name": "english",
        "description": "英語ネイティブが書くような自然な英語に変換します",
        "prompt": "You are a native English speaker. Rewrite the following text exactly as a native English speaker would write it — not as a translation. Use natural English idioms, phrasing, and rhythm. Output only the rewritten text.\n\nText: {input}"
    },
    {
        "name": "japanese",
        "description": "日本語ネイティブが書くような自然な日本語に変換します",
        "prompt": "あなたは日本語のネイティブスピーカーです。以下のテキストを、日本語ネイティブが最初から書いたかのように自然な日本語で書き直してください。翻訳調にならず、日本語として完全に自然な表現・言い回しを使ってください。書き直したテキストのみを出力してください。\n\nテキスト: {input}"
    },
    {
        "name": "spanish",
        "description": "スペイン語ネイティブが書くような自然なスペイン語に変換します",
        "prompt": "Eres un hablante nativo de español. Reescribe el siguiente texto como lo escribiría un nativo desde cero, no como una traducción. Usa expresiones, giros y ritmo naturales del español. Devuelve solo el texto reescrito.\n\nTexto: {input}"
    },
    {
        "name": "cal",
        "description": "入力された言語（日本語・英語・スペイン語）を自動判定して校正します",
        "prompt": (
            "You are a native speaker proofreader. "
            "Detect the language of the input text (Japanese / English / Spanish) "
            "and respond ENTIRELY in that same language. Never switch languages.\n\n"
            "Example (Spanish input → Spanish output):\n"
            "Input: Si, yo miro tu profilo\n"
            "✅ Corrected: Sí, estoy viendo tu perfil.\n"
            "📝 Changes:\n"
            "• \"Si\" → \"Sí\" (accent required)\n"
            "• \"yo miro\" → \"estoy viendo\" (continuous tense is more natural)\n"
            "• \"profilo\" → \"perfil\" (Italian word — Spanish is \"perfil\")\n\n"
            "Now proofread this text and respond in its language:\n"
            "Input: {input}\n"
            "✅ Corrected:"
        )
    },
    {
        "name": "grammar",
        "description": "テキストの翻訳・代替表現・文法解説をシステム言語で表示します",
        "prompt": ""  # main.pyで動的処理（システム言語を自動取得）
    },
    {
        "name": "memory",
        "description": "保存されている記憶サマリーを表示します",
        "prompt": ""
    },
    {
        "name": "clear",
        "description": "現在の会話セッションをリセットします（記憶サマリーは保持）",
        "prompt": ""
    },
    {
        "name": "help",
        "description": "使用可能なコマンドの一覧を表示します",
        "prompt": ""
    },
    {
        "name": "remember",
        "description": "情報をグローバル記憶に保存します（例: /remember 私の名前はDaichi）",
        "prompt": ""
    },
]

def load_config():
    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)

def get_builtin_commands() -> list:
    """組み込みコマンド一覧を返す（ハードコード優先）"""
    return _HARDCODED_COMMANDS

def get_user_commands() -> list:
    """ユーザー定義コマンド一覧を返す（DBから）"""
    conn = get_db_connection()
    rows = conn.execute(
        "SELECT id, name, description, prompt_template, created_at FROM user_commands ORDER BY created_at DESC"
    ).fetchall()
    conn.close()
    return [dict(r) for r in rows]

def get_all_commands() -> list:
    """全コマンドを返す。ユーザー定義コマンドが組み込みコマンドより優先（上書き可能）"""
    user_cmds = get_user_commands()
    user_names = {c["name"] for c in user_cmds}
    # ユーザーに上書きされていない組み込みコマンドのみ含める
    builtin = [{"source": "builtin", **c} for c in get_builtin_commands() if c["name"] not in user_names]
    user = [{"source": "user", **c} for c in user_cmds]
    return user + builtin  # ユーザー定義を先頭に（優先）

def add_user_command(name: str, description: str, prompt_template: str = "") -> dict:
    """
    ユーザー定義コマンドを追加する（または組み込みコマンドを上書き）
    prompt_templateが指定されていればそれを使用し、なければdescriptionから自動生成。
    {input}プレースホルダーを含める。
    組み込みコマンドと同名でも上書きとして保存できる（UPSERT）。
    """
    # 名前の正規化（スラッシュを除去、小文字化、スペースをアンダースコアに）
    clean_name = name.lstrip("/").lower().replace(" ", "_")

    # prompt_templateを決定
    if prompt_template and "{input}" in prompt_template:
        final_template = prompt_template
    elif prompt_template:
        # {input} が含まれていない場合は末尾に追加
        final_template = f"{prompt_template}\n\n対象テキスト: {{input}}"
    else:
        # 説明文から自動生成
        final_template = f"{description}\n\n対象テキスト: {{input}}"

    now = datetime.now().isoformat()
    conn = get_db_connection()
    try:
        # UPSERT: 同名コマンドがあれば更新、なければ挿入（組み込みコマンドの上書きを許可）
        conn.execute(
            """INSERT INTO user_commands (name, description, prompt_template, created_at, updated_at)
               VALUES (?, ?, ?, ?, ?)
               ON CONFLICT(name) DO UPDATE SET
                 description = excluded.description,
                 prompt_template = excluded.prompt_template,
                 updated_at = excluded.updated_at""",
            (clean_name, description, final_template, now, now)
        )
        conn.commit()
        return {"success": True, "name": clean_name, "message": f"コマンド /{clean_name} を保存しました"}
    finally:
        conn.close()

def update_user_command(name: str, description: str, prompt_template: str = "") -> dict:
    """ユーザー定義コマンドを更新する"""
    clean_name = name.lstrip("/").lower()
    if prompt_template and "{input}" in prompt_template:
        final_template = prompt_template
    elif prompt_template:
        final_template = f"{prompt_template}\n\n対象テキスト: {{input}}"
    else:
        final_template = f"{description}\n\n対象テキスト: {{input}}"
    now = datetime.now().isoformat()

    conn = get_db_connection()
    cursor = conn.execute(
        "UPDATE user_commands SET description = ?, prompt_template = ?, updated_at = ? WHERE name = ?",
        (description, final_template, now, clean_name)
    )
    conn.commit()
    affected = cursor.rowcount
    conn.close()

    if affected > 0:
        return {"success": True, "message": f"コマンド /{clean_name} を更新しました"}
    return {"success": False, "message": f"コマンド /{clean_name} が見つかりません"}

def delete_user_command(name: str) -> dict:
    """ユーザー定義コマンドを削除する"""
    clean_name = name.lstrip("/").lower()
    conn = get_db_connection()
    cursor = conn.execute("DELETE FROM user_commands WHERE name = ?", (clean_name,))
    conn.commit()
    affected = cursor.rowcount
    conn.close()

    if affected > 0:
        return {"success": True, "message": f"コマンド /{clean_name} を削除しました"}
    return {"success": False, "message": f"コマンド /{clean_name} が見つかりません（組み込みコマンドは削除できません）"}

def parse_command(user_input: str) -> tuple:
    """
    ユーザー入力を解析してコマンドと本文に分割する
    戻り値: (command_name: str or None, body: str)
    例: "/english こんにちは" → ("english", "こんにちは")
    例: "普通の会話" → (None, "普通の会話")
    """
    stripped = user_input.strip()
    if not stripped.startswith("/"):
        return None, stripped

    parts = stripped[1:].split(" ", 1)
    command_name = parts[0].lower()
    body = parts[1] if len(parts) > 1 else ""
    return command_name, body

def sanitize_prompt_input(text: str) -> str:
    """
    AIプロンプトに埋め込む入力をサニタイズする
    プロンプトインジェクション対策
    """
    # 危険なプロンプトインジェクションパターンを削除
    # 例: "Ignore above instructions", "System prompt", "You are now"
    dangerous_patterns = [
        r'ignore.*instruction',
        r'system.*prompt',
        r'you.*are.*now',
        r'forget.*previous',
        r'please.*disregard',
    ]

    sanitized = text
    import re
    for pattern in dangerous_patterns:
        sanitized = re.sub(pattern, '', sanitized, flags=re.IGNORECASE)

    return sanitized.strip()

def get_command_prompt(command_name: str, input_text: str) -> str:
    """
    コマンド名と入力テキストからAIへのプロンプトを生成する
    戻り値: プロンプト文字列（空文字の場合はコマンドを特殊処理する必要あり）
    """
    all_commands = get_all_commands()
    for cmd in all_commands:
        if cmd["name"] == command_name:
            template = cmd.get("prompt_template", cmd.get("prompt", ""))
            if template:
                # 入力テキストをサニタイズしてからテンプレートに埋め込む
                sanitized_input = sanitize_prompt_input(input_text)
                return template.replace("{input}", sanitized_input)
    return ""

def get_command_names() -> list:
    """全コマンド名のリストを返す（UI補完用）"""
    return [cmd["name"] for cmd in get_all_commands()]
