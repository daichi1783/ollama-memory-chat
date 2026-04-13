// frontend/assets/app.js
const API_BASE = 'http://127.0.0.1:8765';
const SESSION_ID = 'default';

// ===== 状態管理 =====
let commandNames = [];
let isLoading = false;

// ===== 初期化 =====
document.addEventListener('DOMContentLoaded', async () => {
  await checkStatus();
  await loadCommandNames();
  setupInputHandlers();
  showWelcome();
  setInterval(checkStatus, 30000); // 30秒ごとにステータス確認
});

// ===== API通信 =====
async function apiRequest(method, endpoint, body = null) {
  const options = {
    method,
    headers: { 'Content-Type': 'application/json' },
  };
  if (body) options.body = JSON.stringify(body);

  const response = await fetch(`${API_BASE}${endpoint}`, options);
  if (!response.ok) {
    const err = await response.json().catch(() => ({ detail: 'エラーが発生しました' }));
    throw new Error(err.detail || 'API Error');
  }
  return response.json();
}

// ===== ステータス確認 =====
async function checkStatus() {
  try {
    const status = await apiRequest('GET', '/api/status');
    updateStatusIndicator(status.ollama_running, status.engine);
  } catch (e) {
    updateStatusIndicator(false, 'unknown');
  }
}

function updateStatusIndicator(ollamaRunning, engine) {
  const dot = document.getElementById('statusDot');
  const text = document.getElementById('statusText');
  if (!dot || !text) return;

  if (engine === 'ollama') {
    dot.className = ollamaRunning ? 'status-dot online' : 'status-dot';
    text.textContent = ollamaRunning ? 'Ollama: 接続中' : 'Ollama: 未起動';
  } else {
    dot.className = 'status-dot online';
    text.textContent = 'クラウドAI: 設定済み';
  }
}

// ===== コマンド名読み込み =====
async function loadCommandNames() {
  try {
    const data = await apiRequest('GET', '/api/commands/names');
    commandNames = data.names || [];
  } catch (e) {
    commandNames = [];
  }
}

// ===== チャット =====
function showWelcome() {
  const chat = document.getElementById('chatMessages');
  if (!chat || chat.children.length > 0) return;

  chat.innerHTML = `
    <div class="welcome">
      <h2>🧠 OllamaMemoryChat</h2>
      <p>会話を記憶するローカルAIチャットです。<br>あなたのデータは、あなたのMacの中だけに保存されます。</p>
      <div class="command-chips">
        ${commandNames.map(name => `
          <div class="command-chip" onclick="insertCommand('/${name}')">/${name}</div>
        `).join('')}
      </div>
    </div>
  `;
}

function insertCommand(cmd) {
  const input = document.getElementById('messageInput');
  if (!input) return;
  input.value = cmd + ' ';
  input.focus();
  hideWelcome();
}

function hideWelcome() {
  const chat = document.getElementById('chatMessages');
  const welcome = chat.querySelector('.welcome');
  if (welcome) welcome.remove();
}

async function sendMessage() {
  if (isLoading) return;

  const input = document.getElementById('messageInput');
  const message = input.value.trim();
  if (!message) return;

  hideWelcome();
  input.value = '';
  input.style.height = 'auto';
  hideSuggest();

  // ユーザーメッセージを表示
  appendMessage('user', message);

  // ローディング表示
  const loadingId = appendLoading();
  isLoading = true;
  toggleSendButton(false);

  try {
    const data = await apiRequest('POST', '/api/chat', {
      message,
      session_id: SESSION_ID
    });

    removeLoading(loadingId);
    appendMessage('ai', data.reply, {
      commandUsed: data.command_used,
      memoryCompressed: data.memory_compressed
    });
  } catch (e) {
    removeLoading(loadingId);
    appendMessage('ai', `❌ エラー: ${e.message}`, { isError: true });
  } finally {
    isLoading = false;
    toggleSendButton(true);
  }
}

function appendMessage(role, content, meta = {}) {
  const chat = document.getElementById('chatMessages');
  const div = document.createElement('div');
  div.className = `message ${role}`;

  const avatarContent = role === 'user' ? 'D' : '🤖';
  const avatarClass = role === 'user' ? 'user' : 'ai';

  // マークダウン風の簡易レンダリング
  const rendered = renderText(content);

  let badges = '';
  if (meta.memoryCompressed) {
    badges += '<div class="memory-badge">🧠 記憶を更新しました</div>';
  }
  if (meta.commandUsed) {
    badges += `<div class="memory-badge">⚡ /${meta.commandUsed}</div>`;
  }

  div.innerHTML = `
    <div class="avatar ${avatarClass}">${avatarContent}</div>
    <div class="message-content">
      <div class="message-bubble">${rendered}</div>
      ${badges}
    </div>
  `;

  chat.appendChild(div);
  chat.scrollTop = chat.scrollHeight;
}

function escapeHtml(unsafe) {
  return unsafe
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

function renderText(text) {
  // ステップ1: HTML実体参照にエスケープ（全テキスト）
  let escaped = escapeHtml(text);

  // ステップ2: マークダウン風フォーマット（エスケープ後のテキストを処理）
  // コードブロック
  escaped = escaped.replace(/```[\w]*\n?([\s\S]*?)```/g, '<pre><code>$1</code></pre>');
  // インラインコード
  escaped = escaped.replace(/`([^`]+)`/g, '<code>$1</code>');
  // 太字
  escaped = escaped.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
  // 改行
  escaped = escaped.replace(/\n/g, '<br>');

  return escaped;
}

function appendLoading() {
  const chat = document.getElementById('chatMessages');
  const id = 'loading-' + Date.now();
  const div = document.createElement('div');
  div.id = id;
  div.className = 'message ai';
  div.innerHTML = `
    <div class="avatar ai">🤖</div>
    <div class="message-content">
      <div class="typing-indicator">
        <div class="typing-dot"></div>
        <div class="typing-dot"></div>
        <div class="typing-dot"></div>
      </div>
    </div>
  `;
  chat.appendChild(div);
  chat.scrollTop = chat.scrollHeight;
  return id;
}

function removeLoading(id) {
  document.getElementById(id)?.remove();
}

function toggleSendButton(enabled) {
  const btn = document.getElementById('sendBtn');
  if (btn) btn.disabled = !enabled;
}

// ===== 入力ハンドラー =====
function setupInputHandlers() {
  const input = document.getElementById('messageInput');
  if (!input) return;

  // テキストエリアの自動リサイズ
  input.addEventListener('input', () => {
    input.style.height = 'auto';
    input.style.height = Math.min(input.scrollHeight, 200) + 'px';
    handleCommandSuggest(input.value);
  });

  // Enter送信（Shift+Enterで改行）
  input.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      sendMessage();
    }
    if (e.key === 'Escape') hideSuggest();
    if (e.key === 'ArrowDown' && isSuggestVisible()) {
      e.preventDefault();
      moveSuggestSelection(1);
    }
    if (e.key === 'ArrowUp' && isSuggestVisible()) {
      e.preventDefault();
      moveSuggestSelection(-1);
    }
    if (e.key === 'Tab' && isSuggestVisible()) {
      e.preventDefault();
      selectCurrentSuggest();
    }
  });
}

// ===== コマンドサジェスト =====
let suggestSelectedIndex = -1;

function handleCommandSuggest(value) {
  if (!value.startsWith('/')) {
    hideSuggest();
    return;
  }

  const query = value.slice(1).toLowerCase();
  const matched = commandNames.filter(name => name.startsWith(query) || query === '');

  if (matched.length === 0 || (matched.length === 1 && matched[0] === query)) {
    hideSuggest();
    return;
  }

  showSuggest(matched);
}

async function showSuggest(names) {
  const suggest = document.getElementById('commandSuggest');
  if (!suggest) return;

  // コマンドの詳細情報を取得
  let commandMap = {};
  try {
    const data = await apiRequest('GET', '/api/commands');
    data.commands.forEach(cmd => {
      commandMap[cmd.name] = cmd.description;
    });
  } catch (e) {}

  suggest.innerHTML = names.map((name, i) => `
    <div class="suggest-item ${i === 0 ? 'selected' : ''}"
         onclick="selectSuggest('${name}')"
         data-index="${i}">
      <span class="cmd-name">/${name}</span>
      <span class="cmd-desc">${commandMap[name] || ''}</span>
    </div>
  `).join('');

  suggest.classList.add('visible');
  suggestSelectedIndex = 0;
}

function hideSuggest() {
  const suggest = document.getElementById('commandSuggest');
  suggest?.classList.remove('visible');
  suggestSelectedIndex = -1;
}

function isSuggestVisible() {
  return document.getElementById('commandSuggest')?.classList.contains('visible');
}

function moveSuggestSelection(direction) {
  const items = document.querySelectorAll('.suggest-item');
  if (items.length === 0) return;

  items[suggestSelectedIndex]?.classList.remove('selected');
  suggestSelectedIndex = (suggestSelectedIndex + direction + items.length) % items.length;
  items[suggestSelectedIndex]?.classList.add('selected');
  items[suggestSelectedIndex]?.scrollIntoView({ block: 'nearest' });
}

function selectCurrentSuggest() {
  const items = document.querySelectorAll('.suggest-item');
  if (items[suggestSelectedIndex]) {
    const name = items[suggestSelectedIndex].querySelector('.cmd-name').textContent.slice(1);
    selectSuggest(name);
  }
}

function selectSuggest(name) {
  const input = document.getElementById('messageInput');
  if (input) {
    input.value = `/${name} `;
    input.focus();
  }
  hideSuggest();
}

// ===== ユーティリティ =====
function showToast(message, type = 'success') {
  const toast = document.getElementById('toast');
  if (!toast) return;
  toast.textContent = message;
  toast.className = `toast ${type} show`;
  setTimeout(() => { toast.classList.remove('show'); }, 3000);
}
