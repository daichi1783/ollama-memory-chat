// frontend/assets/app.js
const API_BASE = 'http://127.0.0.1:8765';

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
    <div class="avatar ai">${ORBITAL_AVATAR_SVG}</div>
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

async function deleteSession(sessionId, e) {
  e.stopPropagation();

  if (!confirm('このセッションを削除しますか？')) return;

  try {
    await apiRequest('DELETE', `/api/sessions/${sessionId}`);
    await loadSessions();
    showToast('セッションを削除しました', 'success');
  } catch (e) {
    showToast(`削除エラー: ${e.message}`, 'error');
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

// ===== 音声入力 (Web Speech API) =====
let _recognition = null;
let _isRecording = false;
let _interimText = '';   // 認識中（暫定）のテキスト

// 言語コードマッピング: i18n lang → BCP-47
const SPEECH_LANG_MAP = { ja: 'ja-JP', en: 'en-US', es: 'es-ES' };

function _getSpeechLang() {
  const lang = typeof getCurrentLang === 'function' ? getCurrentLang() : 'ja';
  return SPEECH_LANG_MAP[lang] || 'ja-JP';
}

function toggleVoiceInput() {
  if (_isRecording) {
    _stopRecording();
  } else {
    _startRecording();
  }
}

async function _startRecording() {
  const tFn = typeof t === 'function' ? t : k => k;
  const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
  if (!SR) {
    showToast(tFn('voice.error.no_support'), 'error');
    return;
  }

  // ── マイク権限を先に取得 ──────────────────────────────────────────
  // getUserMedia() を先に呼ぶことで macOS のシステム許可ダイアログが表示される
  if (navigator.mediaDevices && navigator.mediaDevices.getUserMedia) {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      stream.getTracks().forEach(track => track.stop()); // 許可確認のみ・即解放
    } catch (err) {
      if (err.name === 'NotAllowedError' || err.name === 'PermissionDeniedError') {
        showToast(tFn('voice.error.not_allowed'), 'error');
        return;
      }
      // その他のエラーは無視して SpeechRecognition に任せる
    }
  }

  _recognition = new SR();
  _recognition.lang = _getSpeechLang();
  _recognition.continuous = false;       // 一文ごとに停止
  _recognition.interimResults = true;    // 暫定テキストも表示

  const input = document.getElementById('messageInput');
  const micBtn = document.getElementById('micBtn');
  const baseText = input.value;          // 録音前のテキストを保持

  _recognition.onstart = () => {
    _isRecording = true;
    _interimText = '';
    micBtn?.classList.add('recording');
    const tFn3 = typeof t === 'function' ? t : k => k;
    showToast(tFn3('voice.listening'), 'success');
  };

  _recognition.onresult = (event) => {
    let interim = '';
    let final   = '';
    for (let i = event.resultIndex; i < event.results.length; i++) {
      const text = event.results[i][0].transcript;
      if (event.results[i].isFinal) {
        final += text;
      } else {
        interim += text;
      }
    }
    // 確定テキストは入力欄に追記、暫定テキストはプレビュー表示
    if (final) {
      const sep = baseText && !baseText.endsWith(' ') ? ' ' : '';
      input.value = baseText + sep + final.trim();
      input.dispatchEvent(new Event('input'));   // 高さ自動調整
    }
    _interimText = interim;
    if (interim) {
      // placeholderを暫定テキストで上書き（視覚的フィードバック）
      input.placeholder = '🎤 ' + interim;
    }
  };

  _recognition.onerror = (event) => {
    _stopRecording();
    const msg = {
      'no-speech':       '音声が検出されませんでした',
      'not-allowed':     'マイクの使用が拒否されています。システム設定でMemoriaのマイクアクセスを許可してください。',
      'network':         'ネットワークエラーが発生しました',
      'audio-capture':   'マイクが見つかりません',
    }[event.error] || `エラー: ${event.error}`;
    showToast(msg, 'error');
  };

  _recognition.onend = () => {
    _stopRecording();
    // placeholder を元に戻す
    const tFn = typeof t === 'function' ? t : () => '';
    const ph = tFn('chat.placeholder') || 'メッセージを入力...';
    const input = document.getElementById('messageInput');
    if (input) input.placeholder = ph;
  };

  _recognition.start();
}

function _stopRecording() {
  _isRecording = false;
  const micBtn = document.getElementById('micBtn');
  micBtn?.classList.remove('recording');
  _recognition?.stop();
  _recognition = null;
}
