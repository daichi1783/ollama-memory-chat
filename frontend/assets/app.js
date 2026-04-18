// frontend/assets/app.js
const API_BASE = 'http://127.0.0.1:18765';

// ===== Orbital ロゴ SVG (AIアバター用) =====
const ORBITAL_AVATAR_SVG = `<svg width="32" height="32" viewBox="0 0 80 80" fill="none" xmlns="http://www.w3.org/2000/svg" style="display:block;">
  <defs>
    <linearGradient id="avGrad" x1="0%" y1="100%" x2="100%" y2="0%">
      <stop offset="0%" stop-color="#89b4fa"/>
      <stop offset="50%" stop-color="#cba6f7"/>
      <stop offset="100%" stop-color="#f5c2e7"/>
    </linearGradient>
  </defs>
  <circle cx="40" cy="40" r="38" fill="url(#avGrad)"/>
  <circle cx="40" cy="40" r="21" fill="white" opacity="0.15"/>
  <circle cx="40" cy="40" r="11" fill="white" opacity="0.2"/>
  <circle cx="40" cy="40" r="4.5" fill="white" opacity="0.9"/>
  <circle cx="40" cy="17" r="4" fill="white" opacity="0.8"/>
  <circle cx="63" cy="40" r="4" fill="white" opacity="0.8"/>
  <circle cx="40" cy="63" r="4" fill="white" opacity="0.8"/>
  <circle cx="17" cy="40" r="4" fill="white" opacity="0.8"/>
</svg>`;

// ===== 状態管理 =====
let commandNames = [];
let isLoading = false;
let currentSessionId = null;
let _mismatchedModelName = null;
let _pullPollInterval = null;
let _currentEngine = 'ollama'; // 現在のエンジン状態

// ===== ダーク/ライトモード: システム外観に連動 =====
(function initTheme() {
  const mq = window.matchMedia('(prefers-color-scheme: dark)');
  const apply = dark => document.documentElement.setAttribute('data-theme', dark ? 'dark' : 'light');
  apply(mq.matches);
  mq.addEventListener('change', e => apply(e.matches));
})();

// ===== 初期化 =====
document.addEventListener('DOMContentLoaded', async () => {
  // i18n初期化（i18n.jsがロード済みなら）
  if (typeof applyTranslations === 'function') applyTranslations();
  await checkStatus();
  await loadCommandNames();
  await loadSessions();
  setupInputHandlers();
  // モデルミスマッチ確認（少し遅延してAPIが確実に起動してから）
  setTimeout(checkModelMismatch, 1500);
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
    updateEngineSwitchLabel(status.engine, status.model_label);
    updateOllamaOfflineBanner(status.ollama_running, status.engine);
  } catch (e) {
    updateStatusIndicator(false, 'unknown');
  }
}

function updateStatusIndicator(ollamaRunning, engine) {
  const dot = document.getElementById('statusDot');
  const text = document.getElementById('statusText');
  if (!dot || !text) return;
  const tFn = typeof t === 'function' ? t : k => k;

  if (engine === 'ollama') {
    dot.className = ollamaRunning ? 'status-dot online' : 'status-dot';
    text.textContent = ollamaRunning ? tFn('status.ollama.online') : tFn('status.ollama.offline');
  } else if (engine === 'claude') {
    dot.className = 'status-dot online';
    text.textContent = tFn('status.claude.ready');
  } else if (engine === 'gemini') {
    dot.className = 'status-dot online';
    text.textContent = tFn('status.gemini.ready');
  } else {
    dot.className = 'status-dot online';
    text.textContent = tFn('status.cloud.ready');
  }
}

// ===== エンジン切り替えUI =====
function updateEngineSwitchLabel(engine, modelLabel) {
  _currentEngine = engine || 'ollama';
  const label = document.getElementById('engineSwitchLabel');
  if (!label) return;

  const icons = { ollama: '🖥️', openai_compatible: '⚡', claude: '🟠', gemini: '💎' };
  const icon = icons[engine] || '🤖';
  const display = modelLabel || engine || '不明';
  label.textContent = `${icon} ${display}`;

  // ドロップダウンのアクティブ状態を更新
  document.querySelectorAll('.engine-option').forEach(el => {
    el.classList.toggle('active', el.dataset.engine === engine);
  });
}

function toggleEngineSwitchDropdown() {
  const dropdown = document.getElementById('engineSwitchDropdown');
  if (!dropdown) return;
  const isOpen = dropdown.style.display !== 'none';
  dropdown.style.display = isOpen ? 'none' : 'block';
}

// ドロップダウンの外クリックで閉じる
document.addEventListener('click', (e) => {
  const wrap = document.getElementById('engineSwitchWrap');
  if (wrap && !wrap.contains(e.target)) {
    const dropdown = document.getElementById('engineSwitchDropdown');
    if (dropdown) dropdown.style.display = 'none';
  }
});

async function switchEngine(engine) {
  // ドロップダウンを閉じる
  const dropdown = document.getElementById('engineSwitchDropdown');
  if (dropdown) dropdown.style.display = 'none';

  if (engine === _currentEngine) return; // 同じなら何もしない

  try {
    const data = await apiRequest('POST', '/api/switch-engine', { engine });
    // ラベル更新（model_labelはstatusから取得するため、再チェック）
    await checkStatus();
    showToast(`✅ エンジンを ${data.engine} に切り替えました（チャット履歴は保持されます）`);
  } catch (e) {
    showToast(`❌ 切り替え失敗: ${e.message}`, 'error');
  }
}

// ===== コマンド名読み込み =====
// コマンド詳細のキャッシュ（showSuggest がキー入力ごとにAPIを叩かないようにする）
let _commandDetailCache = {};

async function loadCommandNames() {
  try {
    // 名前リストと詳細を同時に取得してキャッシュ
    const [namesData, detailData] = await Promise.all([
      apiRequest('GET', '/api/commands/names'),
      apiRequest('GET', '/api/commands'),
    ]);
    commandNames = namesData.names || [];
    _commandDetailCache = {};
    (detailData.commands || []).forEach(cmd => {
      _commandDetailCache[cmd.name] = cmd.description;
    });
  } catch (e) {
    commandNames = [];
    _commandDetailCache = {};
  }
}

// コマンドキャッシュを再読み込みする（コマンド追加・削除後に呼ぶ）
async function refreshCommandCache() {
  try {
    const data = await apiRequest('GET', '/api/commands');
    _commandDetailCache = {};
    (data.commands || []).forEach(cmd => {
      _commandDetailCache[cmd.name] = cmd.description;
    });
  } catch (e) {}
}

// ===== チャット =====
function showWelcome() {
  const chat = document.getElementById('chatMessages');
  if (!chat || chat.children.length > 0) return;
  const tFn = typeof t === 'function' ? t : k => k;
  chat.innerHTML = `
    <div class="welcome">
      <h2>Memoria</h2>
      <p>${tFn('app.tagline')}<br><span style="font-size:13px;opacity:0.7;">${tFn('app.tagline.sub')}</span></p>
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
  // プログラム的な value 変更は input イベントを発火しないので手動更新
  updateSendButtonState();
}

function hideWelcome() {
  const chat = document.getElementById('chatMessages');
  const welcome = chat.querySelector('.welcome');
  if (welcome) welcome.remove();
}

async function sendMessage() {
  if (isLoading) return;
  if (!currentSessionId) return;

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
      session_id: currentSessionId
    });

    removeLoading(loadingId);
    appendMessage('ai', data.reply, {
      commandUsed: data.command_used,
      memoryCompressed: data.memory_compressed
    });
    // Fix⑬: /remember 実行後にバッジ更新
    if (data.command_used === 'remember') updateGlobalMemoryBadge();
  } catch (e) {
    removeLoading(loadingId);
    // Fix⑫: クラウドAI接続失敗時にOllamaへの切り替え提案
    const isCloudEngine = ['claude', 'gemini', 'openai_compatible'].includes(_currentEngine);
    appendMessage('ai', `❌ エラー: ${e.message}`, { isError: true, showOllamaFallback: isCloudEngine });
  } finally {
    isLoading = false;
    toggleSendButton(true);
    updateSendButtonState();
  }
}

function appendMessage(role, content, meta = {}) {
  const chat = document.getElementById('chatMessages');
  const div = document.createElement('div');
  div.className = `message ${role}`;

  const avatarContent = role === 'user' ? 'D' : ORBITAL_AVATAR_SVG;
  const avatarClass = role === 'user' ? 'user' : 'ai';

  // マークダウン風の簡易レンダリング
  const rendered = renderText(content);

  let badges = '';
  if (meta.memoryCompressed) {
    badges += '<div class="memory-badge">💾 記憶を更新しました</div>';
  }
  if (meta.commandUsed) {
    badges += `<div class="memory-badge">⚡ /${meta.commandUsed}</div>`;
  }
  // Fix⑫: クラウドAI失敗時にOllamaへの切り替え提案
  if (meta.isError && meta.showOllamaFallback) {
    badges += `<div class="memory-badge error-fallback">
      <button class="fallback-ollama-btn" onclick="switchEngine('ollama')">🖥️ Ollamaに切り替える</button>
    </div>`;
  }

  const copyBtn = role === 'ai' ? `<button class="msg-copy-btn" onclick="copyMessageText(this)" title="コピー">⎘</button>` : '';
  div.innerHTML = `
    <div class="avatar ${avatarClass}">${avatarContent}</div>
    <div class="message-content">
      <div class="message-bubble">${rendered}${copyBtn}</div>
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

// Fix⑧: ローディング中のメッセージ改善（エンジン名表示）
function appendLoading() {
  const chat = document.getElementById('chatMessages');
  const id = 'loading-' + Date.now();
  const div = document.createElement('div');
  div.id = id;
  div.className = 'message ai';

  // エンジン名ラベル
  const engineNames = {
    ollama: 'Ollama',
    claude: 'Claude',
    gemini: 'Gemini',
    openai_compatible: 'AI',
  };
  const engineLabel = engineNames[_currentEngine] || 'AI';

  div.innerHTML = `
    <div class="avatar ai">${ORBITAL_AVATAR_SVG}</div>
    <div class="message-content">
      <div class="typing-indicator">
        <div class="typing-dot"></div>
        <div class="typing-dot"></div>
        <div class="typing-dot"></div>
      </div>
      <div class="loading-engine-label"></div>
    </div>
  `;
  // textContent で安全にエンジン名を設定（XSS対策）
  div.querySelector('.loading-engine-label').textContent = `${engineLabel} が考えています...`;
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

  // Command+Enter送信（IME対応）
  // IME変換中（日本語入力中）は絶対に送信しない
  // Command+Enter で送信、通常Enterは改行
  input.addEventListener('keydown', (e) => {
    // IME変換中は無視
    if (e.isComposing || e.keyCode === 229) return;

    if (e.key === 'Enter' && e.metaKey) {
      e.preventDefault();
      sendMessage();
    }
    // Enter送信モード（設定でONにしているとき）
    if (e.key === 'Enter' && !e.metaKey && !e.shiftKey && _enterToSend) {
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

// Fix⑪: コマンドサジェストに使い方の例文を追加
const COMMAND_EXAMPLES = {
  english:   '例: /english 昨日、友達と映画を見ました',
  japanese:  '例: /japanese I went to the store yesterday.',
  spanish:   '例: /spanish 今日はいい天気ですね',
  cal:       '例: /cal I writed a letter to my friend.',
  grammar:   '例: /grammar She don\'t know nothing about it.',
  remember:  '例: /remember 私はエンジニアで猫が好きです',
  memory:    '最近の記憶サマリーを確認',
  clear:     '現在のセッション会話をリセット',
  help:      '使えるコマンド一覧を表示',
};

function showSuggest(names) {
  const suggest = document.getElementById('commandSuggest');
  if (!suggest) return;

  // キャッシュから詳細情報を取得（API呼び出しなし）
  // desc は escapeHtml でサニタイズ（ユーザー定義コマンドの説明文にHTMLが含まれる可能性）
  suggest.innerHTML = names.map((name, i) => {
    const rawDesc = _commandDetailCache[name] || '';
    const desc = escapeHtml(rawDesc);
    const example = COMMAND_EXAMPLES[name] ? escapeHtml(COMMAND_EXAMPLES[name]) : '';
    return `
    <div class="suggest-item ${i === 0 ? 'selected' : ''}"
         onclick="selectSuggest('${escapeHtml(name)}')"
         data-index="${i}">
      <span class="cmd-name">/${escapeHtml(name)}</span>
      <span class="cmd-desc">${desc}${example ? `<span class="cmd-example"> — ${example}</span>` : ''}</span>
    </div>
  `;
  }).join('');

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
    // プログラム的な value 変更は input イベントを発火しないので手動更新
    updateSendButtonState();
  }
  hideSuggest();
}

// ===== セッション管理 =====

async function loadSessions() {
  try {
    const data = await apiRequest('GET', '/api/sessions');
    const sessions = data.sessions || [];

    const listContainer = document.getElementById('session-list');
    if (!listContainer) return;

    // セッションリストを再度描画
    listContainer.innerHTML = '';

    if (sessions.length === 0) {
      // セッションがなければ新規作成
      await createNewSession();
    } else {
      // 最新のセッションを選択してロード
      sessions.forEach((session) => {
        const item = createSessionItem(session);
        listContainer.appendChild(item);
      });

      // 最初のセッションを選択（最新のセッション）
      await switchSession(sessions[0].id);
    }
  } catch (e) {
    console.error('セッション読み込みエラー:', e);
  }
}

function createSessionItem(session) {
  const item = document.createElement('div');
  item.className = 'session-item';
  item.dataset.sessionId = session.id;
  item.innerHTML = `
    <div class="session-title" onclick="switchSession('${session.id}')" ondblclick="startEditTitle('${session.id}', this)" title="ダブルクリックで編集">${escapeHtml(session.title)}</div>
    <button class="session-delete" onclick="deleteSession('${session.id}', event)" title="削除">×</button>
  `;
  return item;
}

function startEditTitle(sessionId, titleDiv) {
  const current = titleDiv.textContent;
  const input = document.createElement('input');
  input.type = 'text';
  input.value = current;
  input.className = 'session-title-input';
  input.maxLength = 40;

  const finishEdit = async () => {
    const newTitle = input.value.trim() || current;
    titleDiv.textContent = newTitle;
    titleDiv.style.display = '';
    input.replaceWith(titleDiv);
    if (newTitle !== current) {
      try {
        await apiRequest('PUT', `/api/sessions/${sessionId}/title`, { title: newTitle });
      } catch (e) {
        showToast('タイトルの保存に失敗しました', 'error');
      }
    }
  };

  input.addEventListener('blur', finishEdit);
  input.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') { e.preventDefault(); input.blur(); }
    if (e.key === 'Escape') { input.value = current; input.blur(); }
  });

  titleDiv.style.display = 'none';
  titleDiv.parentNode.insertBefore(input, titleDiv);
  input.focus();
  input.select();
}

async function createNewSession() {
  try {
    const data = await apiRequest('POST', '/api/sessions', {});
    const sessionId = data.session_id;
    await switchSession(sessionId);
    await loadSessions();
  } catch (e) {
    showToast(`セッション作成エラー: ${e.message}`, 'error');
  }
}

async function switchSession(sessionId) {
  currentSessionId = sessionId;

  // サイドバーでのアクティブ状態を更新
  document.querySelectorAll('.session-item').forEach(item => {
    item.classList.remove('active');
    if (item.dataset.sessionId === sessionId) {
      item.classList.add('active');
    }
  });

  // チャットメッセージをクリアして、DBからメッセージを読み込む
  const chatContainer = document.getElementById('chatMessages');
  if (chatContainer) {
    chatContainer.innerHTML = '';
  }

  try {
    const data = await apiRequest('GET', `/api/messages/${sessionId}`);
    const messages = data.messages || [];

    if (messages.length === 0) {
      showWelcome();
    } else {
      hideWelcome();
      messages.forEach(msg => {
        appendMessage(msg.role, msg.content);
      });
    }
  } catch (e) {
    console.error('メッセージ読み込みエラー:', e);
    showWelcome();
  }
}

// Fix⑦: セッション削除の「取り消し」機能
let _pendingDeleteId = null;
let _pendingDeleteTimer = null;
let _pendingDeleteItem = null; // DOM要素を保持

async function deleteSession(sessionId, e) {
  e.stopPropagation();

  // 前の保留中の削除があれば即実行
  if (_pendingDeleteId && _pendingDeleteId !== sessionId) {
    await _commitDelete(_pendingDeleteId);
  }

  // セッションアイテムのDOM要素を記憶（取り消し用）
  const item = document.querySelector(`.session-item[data-session-id="${sessionId}"]`);
  if (!item) return;

  _pendingDeleteId = sessionId;
  _pendingDeleteItem = item;

  // UIからは一時的に非表示（削除に見せる）
  item.style.opacity = '0.4';
  item.style.pointerEvents = 'none';

  // 取り消しバーを表示
  showUndoBar(sessionId);

  // 5秒後に本当に削除
  if (_pendingDeleteTimer) clearTimeout(_pendingDeleteTimer);
  _pendingDeleteTimer = setTimeout(async () => {
    await _commitDelete(sessionId);
  }, 5000);
}

function showUndoBar(sessionId) {
  let bar = document.getElementById('undoDeleteBar');
  if (!bar) {
    bar = document.createElement('div');
    bar.id = 'undoDeleteBar';
    bar.className = 'undo-delete-bar';
    document.body.appendChild(bar);
  }
  bar.innerHTML = `
    <span>🗑️ セッションを削除しました</span>
    <button onclick="undoDeleteSession()">↩️ 取り消し</button>
  `;
  bar.classList.add('visible');
  // 5秒後に自動非表示
  setTimeout(() => { bar.classList.remove('visible'); }, 5500);
}

function hideUndoBar() {
  const bar = document.getElementById('undoDeleteBar');
  if (bar) bar.classList.remove('visible');
}

function undoDeleteSession() {
  if (!_pendingDeleteId) return;
  clearTimeout(_pendingDeleteTimer);
  _pendingDeleteTimer = null;

  // 見た目を元に戻す
  if (_pendingDeleteItem) {
    _pendingDeleteItem.style.opacity = '';
    _pendingDeleteItem.style.pointerEvents = '';
  }
  _pendingDeleteId = null;
  _pendingDeleteItem = null;
  hideUndoBar();
  showToast('削除を取り消しました', 'success');
}

async function _commitDelete(sessionId) {
  if (_pendingDeleteTimer) { clearTimeout(_pendingDeleteTimer); _pendingDeleteTimer = null; }
  _pendingDeleteId = null;
  _pendingDeleteItem = null;
  hideUndoBar();

  try {
    await apiRequest('DELETE', `/api/sessions/${sessionId}`);
    await loadSessions();
  } catch (err) {
    showToast(`削除エラー: ${err.message}`, 'error');
  }
}

// ===== モデルミスマッチ検出・インストール =====

async function checkModelMismatch() {
  try {
    const [settings, modelsResp] = await Promise.all([
      apiRequest('GET', '/api/settings'),
      fetch(`${API_BASE}/api/setup/models`)
    ]);
    if (!modelsResp.ok) return;
    const modelsData = await modelsResp.json();

    const engine = settings.ai?.engine || 'ollama';
    if (engine !== 'ollama') return; // Ollama以外はチェック不要

    const configuredModel = settings.ai?.ollama_model;
    if (!configuredModel) return;

    const installedNames = (modelsData.installed || []).map(m => m.name);
    if (installedNames.length === 0) return; // Ollama未起動 or モデルなし → セットアップ画面で対処

    if (!installedNames.includes(configuredModel)) {
      _mismatchedModelName = configuredModel;
      showModelMismatchAlert(configuredModel);
    } else {
      hideModelMismatchAlert();
    }
  } catch (e) {
    // Ollama未起動 or API起動前 → 無視
  }
}

function showModelMismatchAlert(modelName) {
  const alert = document.getElementById('modelMismatchAlert');
  const nameSpan = document.getElementById('alertModelName');
  if (!alert || !nameSpan) return;
  nameSpan.textContent = `「${modelName}」がインストールされていません`;
  alert.style.display = '';
  // ボタンをリセット
  const btn = document.getElementById('alertInstallBtn');
  if (btn) { btn.disabled = false; btn.textContent = '今すぐインストール'; }
  document.getElementById('alertProgress').classList.remove('visible');
  document.getElementById('alertProgressBarWrap').classList.remove('visible');
  document.getElementById('alertProgressBar').style.width = '0%';
}

function hideModelMismatchAlert() {
  const alert = document.getElementById('modelMismatchAlert');
  if (alert) alert.style.display = 'none';
  if (_pullPollInterval) { clearInterval(_pullPollInterval); _pullPollInterval = null; }
}

async function installConfiguredModel() {
  if (!_mismatchedModelName) return;
  const modelName = _mismatchedModelName;

  const btn = document.getElementById('alertInstallBtn');
  const progress = document.getElementById('alertProgress');
  const barWrap = document.getElementById('alertProgressBarWrap');
  const bar = document.getElementById('alertProgressBar');

  btn.disabled = true;
  btn.textContent = 'インストール中...';
  progress.textContent = `${modelName} のダウンロードを開始しています...`;
  progress.classList.add('visible');
  barWrap.classList.add('visible');
  bar.style.width = '0%';

  try {
    const r = await fetch(`${API_BASE}/api/setup/pull/${encodeURIComponent(modelName)}`, { method: 'POST' });
    if (!r.ok) throw new Error('インストール開始に失敗しました');
    const data = await r.json();
    const taskId = data.task_id;
    if (!taskId) throw new Error('タスクIDが取得できませんでした');

    // 進捗をポーリング
    if (_pullPollInterval) clearInterval(_pullPollInterval);
    _pullPollInterval = setInterval(async () => {
      try {
        const pr = await fetch(`${API_BASE}/api/setup/pull/progress/${taskId}`);
        const pd = await pr.json();
        if (pd.status) progress.textContent = pd.status;
        if (pd.percent != null) bar.style.width = `${pd.percent}%`;

        if (pd.error) {
          clearInterval(_pullPollInterval); _pullPollInterval = null;
          progress.textContent = `❌ エラー: ${pd.error}`;
          btn.disabled = false; btn.textContent = '再試行';
        } else if (pd.done || pd.percent >= 100) {
          clearInterval(_pullPollInterval); _pullPollInterval = null;
          bar.style.width = '100%';
          progress.textContent = '✅ インストール完了！';
          btn.textContent = '完了';
          _mismatchedModelName = null;
          // 2秒後にアラートを閉じる
          setTimeout(() => hideModelMismatchAlert(), 2000);
        }
      } catch (e) { /* ポーリング中のエラーは無視 */ }
    }, 1500);
  } catch (e) {
    progress.textContent = `❌ ${e.message}`;
    btn.disabled = false; btn.textContent = '再試行';
  }
}

// ===== ユーティリティ =====
function showToast(message, type = 'success') {
  const toast = document.getElementById('toast');
  if (!toast) return;
  toast.textContent = message;
  toast.className = `toast ${type} show`;
  setTimeout(() => { toast.classList.remove('show'); }, 3000);
}

// ===== 音声入力 (オフライン: Python側 sounddevice + faster-whisper) =====
// Web Speech API / getUserMedia は使用しない。
// 録音・文字起こしはすべて Python バックエンドで行い、REST API 経由で制御する。

let _isRecording = false;

// i18n lang → Whisper language code
const WHISPER_LANG_MAP = { ja: 'ja', en: 'en', es: 'es' };

function _getWhisperLang() {
  const lang = typeof getCurrentLang === 'function' ? getCurrentLang() : 'ja';
  return WHISPER_LANG_MAP[lang] || null;   // null = 自動検出
}

function toggleVoiceInput() {
  if (_isRecording) {
    _stopRecording();
  } else {
    _startRecording();
  }
}

async function _startRecording() {
  if (_isRecording) return;
  const micBtn = document.getElementById('micBtn');
  try {
    const res = await fetch('/api/voice/start', { method: 'POST' });
    const data = await res.json();
    if (!data.success) {
      showToast(data.message || '録音を開始できませんでした', 'error');
      return;
    }
    _isRecording = true;
    micBtn?.classList.add('recording');
    showToast('🎤 録音中... もう一度押すと送信', 'success');
  } catch (e) {
    showToast('録音の開始に失敗しました: ' + e.message, 'error');
  }
}

async function _stopRecording() {
  if (!_isRecording) return;
  const micBtn = document.getElementById('micBtn');
  const input = document.getElementById('messageInput');
  _isRecording = false;
  micBtn?.classList.remove('recording');
  showToast('⏳ 音声を認識中...', 'success');

  // placeholder を一時的に変更してフィードバック
  const origPlaceholder = input ? input.placeholder : '';
  if (input) input.placeholder = '🔄 文字起こし中...';

  try {
    const lang = _getWhisperLang();
    const res = await fetch('/api/voice/stop', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ language: lang }),
    });
    const data = await res.json();
    if (data.success && data.text) {
      if (input) {
        const sep = input.value && !input.value.endsWith(' ') ? ' ' : '';
        input.value = input.value + sep + data.text;
        input.dispatchEvent(new Event('input'));  // 高さ自動調整
        updateSendButtonState();
      }
      showToast('✅ 認識完了', 'success');
    } else {
      showToast(data.message || '音声が認識できませんでした', 'error');
    }
  } catch (e) {
    showToast('認識エラー: ' + e.message, 'error');
  } finally {
    if (input) input.placeholder = origPlaceholder;
  }
}

// ===== UX Fix 1: オンボーディング =====
function initOnboarding() {
  if (!localStorage.getItem('memoria_onboarded')) {
    const overlay = document.getElementById('onboardingOverlay');
    if (overlay) overlay.style.display = 'flex';
  }
}

function closeOnboarding() {
  localStorage.setItem('memoria_onboarded', '1');
  const overlay = document.getElementById('onboardingOverlay');
  if (overlay) overlay.style.display = 'none';
}

// ===== UX Fix 2: Ollama オフライン案内 =====
function updateOllamaOfflineBanner(ollamaRunning, engine) {
  const banner = document.getElementById('ollamaOfflineBanner');
  if (!banner) return;
  banner.style.display = (engine === 'ollama' && !ollamaRunning) ? 'flex' : 'none';
}

// ===== UX Fix 3: 送信ボタン — 空のとき無効 =====
function updateSendButtonState() {
  const input = document.getElementById('messageInput');
  const btn = document.getElementById('sendBtn');
  if (!input || !btn) return;
  const empty = input.value.trim() === '';
  btn.disabled = empty || isLoading;
  btn.style.opacity = empty ? '0.4' : '1';
}

// ===== UX Fix 4: メッセージのコピーボタン =====
function copyMessageText(btn) {
  const bubble = btn.closest('.message-content')?.querySelector('.message-bubble');
  if (!bubble) return;
  navigator.clipboard.writeText(bubble.innerText || bubble.textContent).then(() => {
    btn.textContent = '✅';
    setTimeout(() => { btn.textContent = '⎘'; }, 1500);
  }).catch(() => showToast('コピーに失敗しました', 'error'));
}

// ===== UX Fix 5: Enter送信トグル =====
let _enterToSend = localStorage.getItem('memoria_enter_send') === '1';

function toggleEnterSend(enabled) {
  _enterToSend = enabled;
  localStorage.setItem('memoria_enter_send', enabled ? '1' : '0');
  const tFn = typeof t === 'function' ? t : k => k;
  const ph = enabled
    ? tFn('chat.placeholder.enter') || 'メッセージを入力...（Enter で送信、Shift+Enter で改行）'
    : tFn('chat.placeholder') || 'メッセージを入力...（/でコマンド、Cmd+Enter で送信）';
  const input = document.getElementById('messageInput');
  if (input) input.placeholder = ph;
}

function initEnterSendToggle() {
  const toggle = document.getElementById('enterToSendToggle');
  if (toggle) {
    toggle.checked = _enterToSend;
    toggleEnterSend(_enterToSend);
  }
}

// ===== UX Fix 6: フォントサイズ =====
function setFontSize(size) {
  const map = { small: '13px', medium: '15px', large: '17px' };
  document.documentElement.style.setProperty('--base-font-size', map[size] || '15px');
  localStorage.setItem('memoria_font_size', size);
  document.querySelectorAll('.font-size-btn').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.size === size);
  });
}

function initFontSize() {
  const saved = localStorage.getItem('memoria_font_size') || 'medium';
  setFontSize(saved);
}

// ===== UX Fix 7: エンジン名をメッセージバブルに表示 =====
// appendMessage に engine ラベルを追加（AI応答のみ）
// → appendMessage の meta 引数を拡張して engineLabel を渡す

// ===== Fix⑬: サイドバーに「記憶: N件」バッジを表示 =====
async function updateGlobalMemoryBadge() {
  try {
    const data = await apiRequest('GET', '/api/global-memory');
    const count = (data.items || []).length;
    let badge = document.getElementById('globalMemoryBadge');
    if (!badge) return;
    if (count > 0) {
      badge.textContent = `🧠 記憶: ${count}件`;
      badge.style.display = 'inline-block';
    } else {
      badge.style.display = 'none';
    }
  } catch (e) {}
}

// ===== Fix⑭: 「最新メッセージへ」スクロールボタン =====
function initScrollToBottomBtn() {
  const chat = document.getElementById('chatMessages');
  if (!chat) return;

  let btn = document.getElementById('scrollToBottomBtn');
  if (!btn) {
    btn = document.createElement('button');
    btn.id = 'scrollToBottomBtn';
    btn.className = 'scroll-to-bottom-btn';
    btn.textContent = '↓';
    btn.title = '最新メッセージへ';
    btn.onclick = () => {
      chat.scrollTo({ top: chat.scrollHeight, behavior: 'smooth' });
    };
    // chat の親要素に追加
    const main = document.querySelector('.main');
    if (main) main.appendChild(btn);
  }

  chat.addEventListener('scroll', () => {
    const isNearBottom = chat.scrollHeight - chat.scrollTop - chat.clientHeight < 120;
    btn.classList.toggle('visible', !isNearBottom);
  });
}

// ===== 初期化への統合 =====
const _originalDOMReady = document.addEventListener.bind(document);
// DOMContentLoaded に追加の初期化を注入
window.addEventListener('DOMContentLoaded', () => {
  initOnboarding();
  initFontSize();
  initEnterSendToggle();
  // 送信ボタンの空チェック
  const input = document.getElementById('messageInput');
  if (input) {
    input.addEventListener('input', updateSendButtonState);
    updateSendButtonState();
  }
  // Fix⑬: グローバルメモリバッジ初期化
  updateGlobalMemoryBadge();
  // Fix⑭: スクロールボタン初期化
  initScrollToBottomBtn();
});
