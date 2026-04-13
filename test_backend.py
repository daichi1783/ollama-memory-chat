"""
バックエンドの単体テスト
Ollamaが起動していなくてもDBとコマンド機能はテストできる
"""
import sys
import os
sys.path.insert(0, "backend")

# テスト用にDBパスを一時ディレクトリに変更
import memory_manager as mm
import command_manager as cm

print("=" * 50)
print("OllamaMemoryChat バックエンドテスト")
print("=" * 50)

# テスト1: DB初期化
print("\n[1] DB初期化テスト...")
try:
    mm.init_db()
    print("  ✅ DB初期化 OK")
except Exception as e:
    print(f"  ❌ DB初期化 NG: {e}")
    sys.exit(1)

# テスト2: メッセージ保存・取得
print("\n[2] メッセージ保存・取得テスト...")
try:
    mm.add_message("user", "テストメッセージ1", "test_session")
    mm.add_message("assistant", "テスト応答1", "test_session")
    mm.add_message("user", "テストメッセージ2", "test_session")
    messages = mm.get_recent_messages("test_session")
    assert len(messages) == 3, f"メッセージ数が不正: {len(messages)}"
    assert messages[0]["role"] == "user"
    print(f"  ✅ メッセージ保存・取得 OK（{len(messages)}件）")
except Exception as e:
    print(f"  ❌ メッセージ保存・取得 NG: {e}")

# テスト3: コマンド解析
print("\n[3] コマンド解析テスト...")
test_cases = [
    ("/english こんにちは", ("english", "こんにちは")),
    ("/cal I goed to store", ("cal", "I goed to store")),
    ("/help", ("help", "")),
    ("普通の会話", (None, "普通の会話")),
]
all_ok = True
for input_text, expected in test_cases:
    result = cm.parse_command(input_text)
    if result != expected:
        print(f"  ❌ '{input_text}' → {result} (期待値: {expected})")
        all_ok = False
if all_ok:
    print(f"  ✅ コマンド解析 OK（{len(test_cases)}ケース）")

# テスト4: 組み込みコマンド取得
print("\n[4] 組み込みコマンド取得テスト...")
try:
    builtin = cm.get_builtin_commands()
    assert len(builtin) > 0, "コマンドが0件"
    print(f"  ✅ 組み込みコマンド OK（{len(builtin)}件: {[c['name'] for c in builtin]}）")
except Exception as e:
    print(f"  ❌ 組み込みコマンド取得 NG: {e}")

# テスト5: ユーザーコマンドCRUD
print("\n[5] ユーザーコマンドCRUDテスト...")
try:
    # 追加
    result = cm.add_user_command("test_cmd", "テスト用コマンドです")
    assert result["success"], f"追加失敗: {result}"

    # 取得
    user_cmds = cm.get_user_commands()
    test_cmd = next((c for c in user_cmds if c["name"] == "test_cmd"), None)
    assert test_cmd is not None, "追加したコマンドが取得できない"

    # 更新
    update_result = cm.update_user_command("test_cmd", "更新されたテスト用コマンド")
    assert update_result["success"], "更新失敗"

    # 削除
    delete_result = cm.delete_user_command("test_cmd")
    assert delete_result["success"], "削除失敗"

    print("  ✅ ユーザーコマンドCRUD OK（追加・取得・更新・削除）")
except Exception as e:
    print(f"  ❌ ユーザーコマンドCRUD NG: {e}")

# テスト6: コマンドプロンプト生成
print("\n[6] コマンドプロンプト生成テスト...")
try:
    prompt = cm.get_command_prompt("english", "こんにちは")
    assert "こんにちは" in prompt, "入力テキストがプロンプトに含まれていない"
    assert len(prompt) > 10, "プロンプトが短すぎる"
    print(f"  ✅ コマンドプロンプト生成 OK")
    print(f"     生成プロンプト（先頭50字）: {prompt[:50]}...")
except Exception as e:
    print(f"  ❌ コマンドプロンプト生成 NG: {e}")

# テスト7: システムプロンプト構築
print("\n[7] システムプロンプト構築テスト...")
try:
    prompt = mm.build_system_prompt(session_id="test_session")
    assert isinstance(prompt, str), "文字列でない"
    assert len(prompt) > 0, "空のプロンプト"
    print(f"  ✅ システムプロンプト構築 OK")
except Exception as e:
    print(f"  ❌ システムプロンプト構築 NG: {e}")

# テスト8: セッションクリア
print("\n[8] セッションクリアテスト...")
try:
    mm.clear_session("test_session")
    messages_after = mm.get_recent_messages("test_session")
    assert len(messages_after) == 0, f"クリア後もメッセージが残っている: {len(messages_after)}件"
    print("  ✅ セッションクリア OK")
except Exception as e:
    print(f"  ❌ セッションクリア NG: {e}")

print("\n" + "=" * 50)
print("テスト完了")
print("=" * 50)
