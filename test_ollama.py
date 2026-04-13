import sys
sys.path.insert(0, "backend")
from ollama_client import is_ollama_running, chat

print("=== Ollama接続テスト ===")
if is_ollama_running():
    print("✅ Ollamaが起動しています")
    try:
        resp = chat(
            messages=[{"role": "user", "content": "こんにちは！一言で自己紹介してください。"}],
            system_prompt="あなたは親切なAIアシスタントです。"
        )
        print(f"✅ AI応答テスト成功:\n{resp}")
    except Exception as e:
        print(f"❌ AI応答テスト失敗: {e}")
else:
    print("⚠️ Ollamaが起動していません（後でUIから設定可能）")
    print("   Ollamaを起動するには: ollama serve")
