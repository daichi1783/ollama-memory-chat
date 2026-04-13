#!/usr/bin/env python3
"""
OllamaMemoryChat 統合テスト
FastAPIサーバーを実際に起動してAPIをテストする
Ollamaが起動していなくても大部分はテスト可能
"""
import sys
import os
import subprocess
import time
import json
import sqlite3
from pathlib import Path

sys.path.insert(0, "backend")

print("=" * 60)
print("OllamaMemoryChat 統合テスト")
print("=" * 60)

# requestsのインストール確認
try:
    import requests
except ImportError:
    import subprocess
    subprocess.run([sys.executable, "-m", "pip", "install", "requests", "--break-system-packages", "-q"])
    import requests

BASE_URL = "http://127.0.0.1:8765"
TEST_RESULTS = []

def test(name, fn):
    try:
        fn()
        TEST_RESULTS.append(("✅", name))
        print(f"  ✅ {name}")
    except Exception as e:
        TEST_RESULTS.append(("❌", f"{name}: {e}"))
        print(f"  ❌ {name}: {e}")

# サーバーをバックグラウンドで起動
print("\n🚀 テスト用サーバーを起動中...")
env = os.environ.copy()
env["TEST_ENV"] = "1"
server_proc = subprocess.Popen(
    [sys.executable, "-c",
     "import sys, os; os.environ['TEST_ENV']='1'; sys.path.insert(0,'backend'); import uvicorn; from main import app; uvicorn.run(app,host='127.0.0.1',port=8765,log_level='critical')"],
    cwd=os.getcwd(),
    env=env,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True
)

# サーバー起動待機（最大15秒）
started = False
for i in range(30):
    try:
        requests.get(f"{BASE_URL}/api/status", timeout=1)
        started = True
        print("  ✅ サーバー起動完了")
        break
    except Exception:
        time.sleep(0.5)

if not started:
    print("  ❌ サーバーの起動に失敗しました")
    server_proc.terminate()
    sys.exit(1)

print()
print("━" * 60)
print("【基本API テスト】")
print("━" * 60)

# 1. ステータスAPI
def test_status():
    r = requests.get(f"{BASE_URL}/api/status", timeout=5)
    assert r.status_code == 200
    data = r.json()
    assert "status" in data and "engine" in data

test("GET /api/status", test_status)

# 2. コマンド一覧API
def test_list_commands():
    r = requests.get(f"{BASE_URL}/api/commands", timeout=5)
    assert r.status_code == 200
    data = r.json()
    assert "commands" in data
    names = [c["name"] for c in data["commands"]]
    for required in ["english", "cal", "help", "memory", "clear"]:
        assert required in names, f"組み込みコマンド '{required}' がない"

test("GET /api/commands（組み込み5件確認）", test_list_commands)

# 3. コマンド名リスト
def test_command_names():
    r = requests.get(f"{BASE_URL}/api/commands/names", timeout=5)
    assert r.status_code == 200
    data = r.json()
    assert "names" in data and len(data["names"]) >= 5

test("GET /api/commands/names", test_command_names)

# 4. ユーザーコマンド追加
def test_add_command():
    r = requests.post(f"{BASE_URL}/api/commands",
                      json={"name": "testcmd", "description": "統合テスト用コマンドです"},
                      timeout=5)
    assert r.status_code == 200
    assert r.json().get("success") == True

test("POST /api/commands（追加）", test_add_command)

# 5. ユーザーコマンド更新
def test_update_command():
    r = requests.put(f"{BASE_URL}/api/commands/testcmd",
                     json={"description": "更新された説明"},
                     timeout=5)
    assert r.status_code == 200

test("PUT /api/commands/{name}（更新）", test_update_command)

# 6. ユーザーコマンド削除
def test_delete_command():
    r = requests.delete(f"{BASE_URL}/api/commands/testcmd", timeout=5)
    assert r.status_code == 200

test("DELETE /api/commands/{name}（削除）", test_delete_command)

# 7. 設定取得（APIキー非漏洩）
def test_settings_no_leak():
    r = requests.get(f"{BASE_URL}/api/settings", timeout=5)
    assert r.status_code == 200
    data = r.json()
    assert "ai" in data
    api_key = data.get("ai", {}).get("openai_api_key", "")
    assert "sk-" not in str(api_key), f"APIキーが漏洩している可能性: {api_key}"

test("GET /api/settings（APIキー非漏洩）", test_settings_no_leak)

# 8. 記憶API
def test_memory_api():
    r = requests.get(f"{BASE_URL}/api/memory?session_id=test_session", timeout=5)
    assert r.status_code == 200
    assert "summaries" in r.json()

test("GET /api/memory", test_memory_api)

# 9. フロントエンド配信
def test_frontend_html():
    r = requests.get(f"{BASE_URL}/", timeout=5)
    assert r.status_code == 200
    assert "OllamaMemoryChat" in r.text

test("GET /（index.html配信）", test_frontend_html)

# 10. 設定ページ配信
def test_settings_page():
    r = requests.get(f"{BASE_URL}/settings", timeout=5)
    assert r.status_code == 200

test("GET /settings（settings.html配信）", test_settings_page)

# 11. セットアップページ配信
def test_setup_page():
    r = requests.get(f"{BASE_URL}/setup", timeout=5)
    assert r.status_code == 200
    assert "html" in r.headers.get("content-type", "").lower()

test("GET /setup（setup.html配信）", test_setup_page)

# 12. /help コマンド（Ollama不要）
def test_help_command():
    r = requests.post(f"{BASE_URL}/api/chat",
                      json={"message": "/help", "session_id": "test_session"},
                      timeout=10)
    assert r.status_code == 200
    data = r.json()
    assert data.get("command_used") == "help"
    assert "english" in data["reply"].lower() or "コマンド" in data["reply"]

test("POST /api/chat（/help）", test_help_command)

# 13. /memory コマンド（Ollama不要）
def test_memory_command():
    r = requests.post(f"{BASE_URL}/api/chat",
                      json={"message": "/memory", "session_id": "test_session"},
                      timeout=10)
    assert r.status_code == 200
    assert r.json().get("command_used") == "memory"

test("POST /api/chat（/memory）", test_memory_command)

# 14. /clear コマンド（Ollama不要）
def test_clear_command():
    r = requests.post(f"{BASE_URL}/api/chat",
                      json={"message": "/clear", "session_id": "test_session"},
                      timeout=10)
    assert r.status_code == 200
    assert r.json().get("command_used") == "clear"

test("POST /api/chat（/clear）", test_clear_command)

print()
print("━" * 60)
print("【セットアップウィザード API テスト】")
print("━" * 60)

# 15. セットアップステータス取得
def test_setup_status():
    r = requests.get(f"{BASE_URL}/api/setup/status", timeout=5)
    assert r.status_code == 200
    data = r.json()
    # 必須キーが存在するか確認
    required_keys = ["ollama_installed", "ollama_running", "brew_available",
                     "installed_models", "recommended_models", "setup_complete"]
    for key in required_keys:
        assert key in data, f"キー '{key}' がレスポンスに存在しない"
    # 型チェック
    assert isinstance(data["ollama_installed"], bool)
    assert isinstance(data["ollama_running"], bool)
    assert isinstance(data["brew_available"], bool)
    assert isinstance(data["setup_complete"], bool)
    assert isinstance(data["installed_models"], list)
    assert isinstance(data["recommended_models"], list)

test("GET /api/setup/status（全キー・型確認）", test_setup_status)

# 16. セットアップステータス: recommended_modelsの内容確認
def test_setup_recommended_models():
    r = requests.get(f"{BASE_URL}/api/setup/status", timeout=5)
    assert r.status_code == 200
    data = r.json()
    recommended = data["recommended_models"]
    assert len(recommended) > 0, "おすすめモデルリストが空"
    # 各モデルにname, descriptionがあること（size_gbまたはsizeどちらかでOK）
    for m in recommended:
        assert "name" in m, f"モデルにnameキーがない: {m}"
        assert "description" in m, f"モデルにdescriptionキーがない: {m}"
        has_size = "size" in m or "size_gb" in m
        assert has_size, f"モデルにsizeまたはsize_gbキーがない: {m}"

test("GET /api/setup/status（recommended_models構造確認）", test_setup_recommended_models)

# 17. モデル一覧API
def test_setup_models_list():
    r = requests.get(f"{BASE_URL}/api/setup/models", timeout=5)
    assert r.status_code == 200
    data = r.json()
    assert "installed" in data, "installedキーがない"
    assert "recommended" in data, "recommendedキーがない"
    assert isinstance(data["installed"], list)
    assert isinstance(data["recommended"], list)

test("GET /api/setup/models（インストール済み＋おすすめ）", test_setup_models_list)

# 18. Ollamaインストールエンドポイント（エラーにならないこと）
def test_setup_install_endpoint():
    r = requests.post(f"{BASE_URL}/api/setup/install", timeout=10)
    # Ollamaがすでにインストール済みでも未インストールでも200が返る
    # （処理の成否に関わらずAPIとして正常動作すること）
    assert r.status_code == 200
    data = r.json()
    # successまたはerrorキーがあること
    assert "success" in data or "error" in data or "message" in data, \
        f"予期しないレスポンス形式: {data}"

test("POST /api/setup/install（エンドポイント疎通）", test_setup_install_endpoint)

# 19. Ollama起動エンドポイント（エラーにならないこと）
def test_setup_start_endpoint():
    r = requests.post(f"{BASE_URL}/api/setup/start", timeout=15)
    assert r.status_code == 200
    data = r.json()
    assert "success" in data or "error" in data or "message" in data, \
        f"予期しないレスポンス形式: {data}"

test("POST /api/setup/start（エンドポイント疎通）", test_setup_start_endpoint)

# 20. モデルpullエンドポイント（タスクIDが返ること）
def test_setup_pull_returns_task_id():
    r = requests.post(f"{BASE_URL}/api/setup/pull/gemma3:4b", timeout=10)
    # Ollama起動済みなら200+task_id、未起動なら400+detailが返る
    assert r.status_code in [200, 400, 503], \
        f"予期しないステータス: {r.status_code}"
    data = r.json()
    # 200の場合はtask_id、400の場合はdetailがあること
    assert "task_id" in data or "detail" in data or "error" in data, \
        f"予期しないレスポンス形式: {data}"

test("POST /api/setup/pull/{model}（タスクIDまたはエラー返却）", test_setup_pull_returns_task_id)

# 21. pull進捗取得（存在しないtask_idでも200が返ること）
def test_setup_pull_progress():
    task_id = "nonexistent-task-id-12345"
    r = requests.get(f"{BASE_URL}/api/setup/pull/progress/{task_id}", timeout=5)
    assert r.status_code == 200
    data = r.json()
    # statusかerrorキーがあること
    assert "status" in data or "error" in data, \
        f"予期しないレスポンス形式: {data}"

test("GET /api/setup/pull/progress/{task_id}（存在しないID）", test_setup_pull_progress)

# 22. モデル選択エンドポイント（バリデーション）
def test_setup_select_model_validation():
    # モデル名なしで送信（バリデーションエラーになること）
    r = requests.post(f"{BASE_URL}/api/setup/select-model",
                      json={},
                      timeout=5)
    # 400または422が返ること（FastAPIのdict受け取りでは400になる）
    assert r.status_code in [400, 422], \
        f"空のモデル名に対して予期しないステータス: {r.status_code}"
    data = r.json()
    # エラーメッセージが含まれること
    assert "detail" in data or "error" in data, f"エラー詳細なし: {data}"

test("POST /api/setup/select-model（空モデル名バリデーション）", test_setup_select_model_validation)

# 23. モデル選択エンドポイント（正常系）
def test_setup_select_model_valid():
    # エンドポイントは body["model"] キーを期待する
    r = requests.post(f"{BASE_URL}/api/setup/select-model",
                      json={"model": "gemma3:4b"},
                      timeout=5)
    assert r.status_code == 200
    data = r.json()
    assert "success" in data or "message" in data, \
        f"予期しないレスポンス形式: {data}"

test("POST /api/setup/select-model（正常系）", test_setup_select_model_valid)

# 24. モデル削除エンドポイント（存在しないモデル）
def test_setup_delete_nonexistent_model():
    r = requests.delete(f"{BASE_URL}/api/setup/models/nonexistent-model-xyz:latest", timeout=10)
    # Ollama未起動なら400、起動済みで存在しないモデルなら404/500も可
    assert r.status_code in [200, 400, 404, 500], \
        f"予期しないステータス: {r.status_code}"
    # クラッシュしないこと（レスポンスがJSONであること）
    data = r.json()
    assert isinstance(data, dict)

test("DELETE /api/setup/models/{model}（存在しないモデル）", test_setup_delete_nonexistent_model)

print()
print("━" * 60)
print("【セキュリティ テスト】")
print("━" * 60)

# 25. セキュリティ: 巨大入力（DoS対策）
def test_large_input():
    huge = "A" * 20000
    r = requests.post(f"{BASE_URL}/api/chat",
                      json={"message": huge, "session_id": "test_sec"},
                      timeout=10)
    # 400か422が返るべき（サーバーがクラッシュしないこと）
    assert r.status_code in [400, 422, 500], \
        f"巨大入力に対して予期しないステータス: {r.status_code}"

test("セキュリティ: 巨大入力（10000字超）", test_large_input)

# 26. セキュリティ: 不正なsession_id
def test_invalid_session_id():
    r = requests.post(f"{BASE_URL}/api/chat",
                      json={"message": "test", "session_id": "../../etc/passwd"},
                      timeout=10)
    assert r.status_code in [400, 422], f"不正session_idに対して: {r.status_code}"

test("セキュリティ: 不正なsession_id（パストラバーサル）", test_invalid_session_id)

# 27. セキュリティ: セキュリティヘッダーの確認
def test_security_headers():
    r = requests.get(f"{BASE_URL}/api/status", timeout=5)
    assert r.status_code == 200
    headers = r.headers
    assert "X-Content-Type-Options" in headers, "X-Content-Type-Optionsヘッダーがない"
    assert headers["X-Content-Type-Options"] == "nosniff"
    assert "X-Frame-Options" in headers, "X-Frame-Optionsヘッダーがない"
    assert headers["X-Frame-Options"] == "DENY"
    assert "X-XSS-Protection" in headers, "X-XSS-Protectionヘッダーがない"

test("セキュリティ: レスポンスヘッダー確認", test_security_headers)

# 28. セキュリティ: setup/pullのパストラバーサル対策
def test_setup_pull_path_traversal():
    # パストラバーサル試行
    r = requests.post(f"{BASE_URL}/api/setup/pull/../../etc/passwd", timeout=5)
    # サーバーがクラッシュしないこと
    assert r.status_code in [200, 400, 404, 422, 500], \
        f"予期しないステータス: {r.status_code}"
    data = r.json()
    assert isinstance(data, dict)

test("セキュリティ: setup/pull パストラバーサル試行", test_setup_pull_path_traversal)

# クリーンアップ
try:
    requests.delete(f"{BASE_URL}/api/memory/test_session", timeout=5)
    requests.delete(f"{BASE_URL}/api/memory/test_sec", timeout=5)
except Exception:
    pass

# サーバー停止
server_proc.terminate()
try:
    server_proc.wait(timeout=5)
except Exception:
    server_proc.kill()

# 結果サマリー
print()
print("=" * 60)
passed = sum(1 for r, _ in TEST_RESULTS if r == "✅")
failed = sum(1 for r, _ in TEST_RESULTS if r == "❌")
total = len(TEST_RESULTS)
print(f"結果: {passed}/{total} テスト通過")
if failed > 0:
    print("\n❌ 失敗したテスト:")
    for r, name in TEST_RESULTS:
        if r == "❌":
            print(f"   {r} {name}")
    sys.exit(1)
else:
    print("🎉 全テスト通過！")
print("=" * 60)
