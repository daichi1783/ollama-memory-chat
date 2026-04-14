"""
会話記憶管理モジュール
- SQLiteに会話履歴を保存
- N往復ごとにAIで要約・圧縮
- 圧縮サマリーを次の会話のシステムプロンプトに注入
"""
import sqlite3
import json
import os
from pathlib import Path
from datetime import datetime
import yaml

# PyInstallerバンドル対応: OMCHAT_BASE_DIR / OMCHAT_DATA_DIR 環境変数を優先
_base = Path(os.environ.get('OMCHAT_BASE_DIR', str(Path(__file__).parent.parent)))
_data = Path(os.environ.get('OMCHAT_DATA_DIR', str(_base / 'data')))
# ユーザー設定 > バンドルデフォルト の順で読む
CONFIG_PATH = (_data / "config.yaml") if (_data / "config.yaml").exists() else (_base / "config.yaml")
# テスト環境では別のDBパスを使用
_is_test = os.environ.get("TEST_ENV") == "1"
if _is_test:
    DB_PATH = Path("/tmp/test_chat_memory.db")
else:
    # データディレクトリを確保してからDBパスを設定
    _data.mkdir(parents=True, exist_ok=True)
    DB_PATH = _data / "chat_memory.db"

def load_config():
    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)

def get_db_connection():
    """DBへの接続を返す"""
    try:
        conn = sqlite3.connect(str(DB_PATH), timeout=10.0)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA synchronous = NORMAL")
        return conn
    except sqlite3.OperationalError as e:
        # DBが破損している場合は削除して再作成
        if "disk I/O error" in str(e):
            try:
                DB_PATH.unlink(missing_ok=True)
            except Exception:
                pass
            conn = sqlite3.connect(str(DB_PATH), timeout=10.0)
            conn.row_factory = sqlite3.Row
            conn.execute("PRAGMA synchronous = NORMAL")
            return conn
        raise

def init_db():
    """データベースとテーブルの初期化"""
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)

    conn = get_db_connection()
    # 同期設定の調整
    conn.execute("PRAGMA synchronous = NORMAL")
    cursor = conn.cursor()

    # セッションテーブル
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS sessions (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL DEFAULT '新しいチャット',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)

    # 会話履歴テーブル
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            role TEXT NOT NULL,           -- 'user' or 'assistant'
            content TEXT NOT NULL,
            created_at TEXT NOT NULL,
            session_id TEXT NOT NULL DEFAULT 'default'
        )
    """)

    # 記憶サマリーテーブル
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS memory_summaries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            summary TEXT NOT NULL,
            message_count INTEGER NOT NULL,
            created_at TEXT NOT NULL,
            session_id TEXT NOT NULL DEFAULT 'default'
        )
    """)

    # ユーザー定義コマンドテーブル
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS user_commands (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,    -- コマンド名（スラッシュなし）
            description TEXT NOT NULL,    -- ユーザーが書いた説明
            prompt_template TEXT NOT NULL, -- AIへのプロンプトテンプレート（{input}プレースホルダー）
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
    """)

    conn.commit()
    conn.close()

def create_session(session_id: str, title: str = "新しいチャット") -> dict:
    """セッションを作成する"""
    conn = get_db_connection()
    try:
        conn.execute(
            "INSERT INTO sessions (id, title, created_at, updated_at) VALUES (?, ?, ?, ?)",
            (session_id, title, datetime.now().isoformat(), datetime.now().isoformat())
        )
        conn.commit()
        conn.close()
        return {"success": True, "session_id": session_id}
    except sqlite3.IntegrityError:
        conn.close()
        return {"success": False, "message": "セッションはすでに存在します"}
    except Exception as e:
        conn.close()
        return {"success": False, "message": str(e)}

def get_sessions() -> list:
    """セッション一覧を取得する（updated_at降順）"""
    conn = get_db_connection()
    rows = conn.execute(
        "SELECT id, title, created_at, updated_at FROM sessions ORDER BY updated_at DESC"
    ).fetchall()
    conn.close()
    return [{"id": r["id"], "title": r["title"], "created_at": r["created_at"], "updated_at": r["updated_at"]} for r in rows]

def update_session_title(session_id: str, title: str):
    """セッションのタイトルを更新する"""
    conn = get_db_connection()
    conn.execute(
        "UPDATE sessions SET title = ?, updated_at = ? WHERE id = ?",
        (title, datetime.now().isoformat(), session_id)
    )
    conn.commit()
    conn.close()

def delete_session(session_id: str):
    """セッションを削除する（messages と memory_summaries も削除）"""
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute("DELETE FROM messages WHERE session_id = ?", (session_id,))
    cursor.execute("DELETE FROM memory_summaries WHERE session_id = ?", (session_id,))
    cursor.execute("DELETE FROM sessions WHERE id = ?", (session_id,))
    conn.commit()
    conn.close()

def get_session_messages(session_id: str) -> list:
    """UI表示用にセッションのメッセージを取得する"""
    conn = get_db_connection()
    rows = conn.execute(
        "SELECT role, content, created_at FROM messages WHERE session_id = ? ORDER BY id ASC",
        (session_id,)
    ).fetchall()
    conn.close()
    return [{"role": r["role"], "content": r["content"], "timestamp": r["created_at"]} for r in rows]

def ensure_session_exists(session_id: str):
    """セッションが存在しなければ作成する"""
    conn = get_db_connection()
    existing = conn.execute("SELECT id FROM sessions WHERE id = ?", (session_id,)).fetchone()
    conn.close()

    if not existing:
        create_session(session_id, "新しいチャット")

def add_message(role: str, content: str, session_id: str = "default"):
    """メッセージを保存する"""
    conn = get_db_connection()
    conn.execute(
        "INSERT INTO messages (role, content, created_at, session_id) VALUES (?, ?, ?, ?)",
        (role, content, datetime.now().isoformat(), session_id)
    )
    # update_at を更新
    conn.execute(
        "UPDATE sessions SET updated_at = ? WHERE id = ?",
        (datetime.now().isoformat(), session_id)
    )
    conn.commit()
    conn.close()

def get_recent_messages(session_id: str = "default", limit: int = 20) -> list:
    """最近のメッセージを取得する（古い順）"""
    conn = get_db_connection()
    rows = conn.execute(
        "SELECT role, content FROM messages WHERE session_id = ? ORDER BY id DESC LIMIT ?",
        (session_id, limit)
    ).fetchall()
    conn.close()
    return [{"role": r["role"], "content": r["content"]} for r in reversed(rows)]

def get_message_count(session_id: str = "default") -> int:
    """セッションのメッセージ数を返す"""
    conn = get_db_connection()
    count = conn.execute(
        "SELECT COUNT(*) FROM messages WHERE session_id = ?", (session_id,)
    ).fetchone()[0]
    conn.close()
    return count

def get_latest_summary(session_id: str = "default") -> str:
    """最新の記憶サマリーを返す（なければ空文字）"""
    conn = get_db_connection()
    row = conn.execute(
        "SELECT summary FROM memory_summaries WHERE session_id = ? ORDER BY id DESC LIMIT 1",
        (session_id,)
    ).fetchone()
    conn.close()
    return row["summary"] if row else ""

def save_summary(summary: str, message_count: int, session_id: str = "default"):
    """サマリーを保存する"""
    conn = get_db_connection()
    conn.execute(
        "INSERT INTO memory_summaries (summary, message_count, created_at, session_id) VALUES (?, ?, ?, ?)",
        (summary, message_count, datetime.now().isoformat(), session_id)
    )
    conn.commit()
    conn.close()

def should_compress(session_id: str = "default") -> bool:
    """圧縮が必要か判定する"""
    config = load_config()
    threshold = config["memory"]["compression_threshold"]

    conn = get_db_connection()
    # 最後のサマリー以降のメッセージ数を確認
    last_summary = conn.execute(
        "SELECT message_count FROM memory_summaries WHERE session_id = ? ORDER BY id DESC LIMIT 1",
        (session_id,)
    ).fetchone()

    total_count = conn.execute(
        "SELECT COUNT(*) FROM messages WHERE session_id = ?", (session_id,)
    ).fetchone()[0]
    conn.close()

    if last_summary is None:
        return total_count >= threshold
    else:
        messages_since_last = total_count - last_summary["message_count"]
        return messages_since_last >= threshold

def compress_memory(session_id: str = "default") -> str:
    """
    過去の会話をAIに要約させてサマリーを生成・保存する
    戻り値: 生成されたサマリー文字列
    """
    from ollama_client import chat

    messages = get_recent_messages(session_id=session_id, limit=30)
    existing_summary = get_latest_summary(session_id)

    # 会話テキストを整形
    conversation_text = "\n".join(
        [f"{'ユーザー' if m['role'] == 'user' else 'AI'}: {m['content']}" for m in messages]
    )

    # 既存のサマリーがある場合はそれを含める
    context = ""
    if existing_summary:
        context = f"\n\n【前回までの要約】\n{existing_summary}"

    summary_prompt = f"""以下の会話履歴を読んで、重要な情報・文脈・ユーザーについての情報を簡潔にまとめてください。
将来の会話でこのサマリーを読んだAIが、ユーザーのことをよく理解して会話を続けられるように書いてください。
箇条書きで、200字以内に収めてください。{context}

【会話履歴】
{conversation_text}

【要約】"""

    summary = chat(
        messages=[{"role": "user", "content": summary_prompt}],
        system_prompt="あなたは会話の要約を作成する専門家です。重要な情報を簡潔にまとめてください。"
    )

    message_count = get_message_count(session_id)
    save_summary(summary, message_count, session_id)
    return summary

def build_system_prompt(base_prompt: str = "", session_id: str = "default") -> str:
    """
    記憶サマリーを含むシステムプロンプトを構築する
    """
    summary = get_latest_summary(session_id)

    parts = []
    if base_prompt:
        parts.append(base_prompt)

    if summary:
        parts.append(f"【あなたの記憶】\n以下はこれまでの会話の要約です。これを踏まえて返答してください：\n{summary}")

    return "\n\n".join(parts) if parts else "あなたは親切で知識豊富なAIアシスタントです。"

def clear_session(session_id: str = "default"):
    """セッションの会話履歴をリセット（サマリーは保持）"""
    conn = get_db_connection()
    conn.execute("DELETE FROM messages WHERE session_id = ?", (session_id,))
    conn.commit()
    conn.close()

def get_all_summaries(session_id: str = "default") -> list:
    """すべての記憶サマリーを返す"""
    conn = get_db_connection()
    rows = conn.execute(
        "SELECT summary, created_at, message_count FROM memory_summaries WHERE session_id = ? ORDER BY id DESC",
        (session_id,)
    ).fetchall()
    conn.close()
    return [{"summary": r["summary"], "created_at": r["created_at"], "message_count": r["message_count"]} for r in rows]

# 初期化（初回インポート時に自動実行）
# ここではコメントアウト。アプリケーション起動時に main.py で明示的に呼ぶ
# init_db()
