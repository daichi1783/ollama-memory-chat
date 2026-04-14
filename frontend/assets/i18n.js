// frontend/assets/i18n.js — Memoria multilingual support
// Languages: ja (Japanese), en (English), es (Spanish)

const TRANSLATIONS = {
  ja: {
    // App
    'app.name': 'Memoria',
    'app.tagline': '会話を記憶するAIチャット',
    'app.tagline.sub': 'あなたのデータは、あなたのMacの中だけに保存されます。',
    'app.version': 'バージョン',

    // Navigation
    'nav.chat': 'チャット',
    'nav.settings': '設定・コマンド管理',

    // Chat
    'chat.new': '✏️ 新しいチャット',
    'chat.placeholder': 'メッセージを入力...（/でコマンド、Cmd+Enterで送信）',
    'chat.hint': 'Cmd+Enter で送信 · Enter で改行 · / でコマンド補完',
    'chat.send': '送信',

    // Status
    'status.checking': '確認中...',
    'status.ollama.online': 'Ollama: 接続中',
    'status.ollama.offline': 'Ollama: 未起動',
    'status.cloud.ready': 'AI: 設定済み',
    'status.claude.ready': 'Claude: 設定済み',
    'status.gemini.ready': 'Gemini: 設定済み',

    // Session
    'session.delete.confirm': 'このセッションを削除しますか？',
    'session.delete.success': 'セッションを削除しました',
    'session.title.edit.hint': 'ダブルクリックで編集',

    // Model mismatch
    'mismatch.title': '設定されたモデルがインストールされていません',
    'mismatch.install': '今すぐインストール',
    'mismatch.done': '完了',
    'mismatch.retrying': '再試行',

    // Engine switch
    'engine.label': 'AIエンジン',
    'engine.ollama': '🖥️ Ollama（ローカル）',
    'engine.openai': '⚡ OpenAI互換API',
    'engine.claude': '🟠 Claude (Anthropic)',
    'engine.gemini': '💎 Gemini (Google)',
    'engine.switch.success': 'エンジンを切り替えました（チャット履歴は保持されます）',

    // Settings
    'settings.title': '設定・コマンド管理',
    'settings.ai.section': 'AIエンジン設定',
    'settings.ai.engine.label': 'エンジン',
    'settings.ai.engine.sub': '使用するAIを選択',
    'settings.ai.save': '保存する',
    'settings.memory.section': '記憶設定',
    'settings.memory.threshold.label': '記憶圧縮タイミング',
    'settings.memory.threshold.sub': '何往復ごとに会話を要約・圧縮するか',
    'settings.memory.threshold.unit': '往復',
    'settings.memory.clear.label': 'セッション記憶をすべて削除',
    'settings.memory.clear.sub': '会話履歴とすべてのサマリーを削除します',
    'settings.memory.clear.btn': 'すべて削除',
    'settings.global.section': 'グローバル記憶（セッションをまたいで保持）',
    'settings.global.hint': 'チャット中に /remember 覚えておいてほしい内容 と入力すると保存されます。新しいチャットでも自動的に参照されます。',
    'settings.global.add.label': '手動で追加',
    'settings.global.add.placeholder': '例: 私の名前はDaichi、エンジニアです',
    'settings.global.add.btn': '追加',
    'settings.global.clear.btn': 'グローバル記憶をすべて削除',
    'settings.model.section': 'Ollamaモデル管理',
    'settings.model.add.label': 'モデルを追加',
    'settings.model.add.sub': 'モデル名を入力（例: llama3.2:3b）',
    'settings.model.add.btn': '追加',
    'settings.model.use.btn': '使う',
    'settings.model.update.btn': '🔄 更新',
    'settings.commands.section': 'コマンド管理',
    'settings.commands.add.title': '＋ 新しいコマンドを追加',
    'settings.commands.add.btn': '追加する',
    'settings.commands.builtin': '組み込み',
    'settings.commands.custom': 'カスタム',
    'settings.lang.section': '言語 / Language / Idioma',
    'settings.lang.label': '表示言語',
    'settings.appinfo.section': 'アプリ情報',
    'settings.appinfo.version.label': 'バージョン',
    'settings.appinfo.privacy.label': 'プライバシー',
    'settings.appinfo.privacy.sub': 'すべてのデータはあなたのMac内にのみ保存されます',
    'settings.appinfo.privacy.badge': '🔒 完全ローカル',
    'settings.appinfo.author': '作成者',
    'settings.appinfo.price': '価格',

    // Toast messages
    'toast.saved': '✅ 設定を保存しました',
    'toast.save.error': '❌ 保存に失敗しました',
    'toast.memory.cleared': '✅ 記憶をすべて削除しました',
    'toast.memory.added': '✅ 記憶に追加しました',
    'toast.memory.deleted': '✅ 削除しました',
    'toast.command.added': '✅ コマンドを追加しました',
    'toast.command.deleted': '✅ コマンドを削除しました',
    'toast.model.updated': '✅ モデルを最新版に更新しました',
    'voice.btn.title': '音声入力（クリックで開始/停止）',
    'voice.listening': '🎤 聞いています...',
    'voice.error.no_speech': '音声が検出されませんでした',
    'voice.error.not_allowed': 'マイクの使用が拒否されています。システム設定でMemoriaのマイクアクセスを許可してください。',
    'voice.error.no_support': 'このブラウザは音声入力に対応していません',
  },

  en: {
    'app.name': 'Memoria',
    'app.tagline': 'AI chat that remembers',
    'app.tagline.sub': 'Your data stays on your Mac. Always.',
    'app.version': 'Version',

    'nav.chat': 'Chat',
    'nav.settings': 'Settings & Commands',

    'chat.new': '✏️ New Chat',
    'chat.placeholder': 'Type a message... (/ for commands, Cmd+Enter to send)',
    'chat.hint': 'Cmd+Enter to send · Enter for new line · / for commands',
    'chat.send': 'Send',

    'status.checking': 'Checking...',
    'status.ollama.online': 'Ollama: Connected',
    'status.ollama.offline': 'Ollama: Not running',
    'status.cloud.ready': 'AI: Ready',
    'status.claude.ready': 'Claude: Ready',
    'status.gemini.ready': 'Gemini: Ready',

    'session.delete.confirm': 'Delete this session?',
    'session.delete.success': 'Session deleted',
    'session.title.edit.hint': 'Double-click to rename',

    'mismatch.title': 'Configured model is not installed',
    'mismatch.install': 'Install Now',
    'mismatch.done': 'Done',
    'mismatch.retrying': 'Retry',

    'engine.label': 'AI Engine',
    'engine.ollama': '🖥️ Ollama (Local)',
    'engine.openai': '⚡ OpenAI-compatible API',
    'engine.claude': '🟠 Claude (Anthropic)',
    'engine.gemini': '💎 Gemini (Google)',
    'engine.switch.success': 'Engine switched (chat history preserved)',

    'settings.title': 'Settings & Commands',
    'settings.ai.section': 'AI Engine',
    'settings.ai.engine.label': 'Engine',
    'settings.ai.engine.sub': 'Select the AI to use',
    'settings.ai.save': 'Save',
    'settings.memory.section': 'Memory Settings',
    'settings.memory.threshold.label': 'Compression interval',
    'settings.memory.threshold.sub': 'How many exchanges before summarizing',
    'settings.memory.threshold.unit': 'exchanges',
    'settings.memory.clear.label': 'Clear all session memory',
    'settings.memory.clear.sub': 'Deletes conversation history and all summaries',
    'settings.memory.clear.btn': 'Clear All',
    'settings.global.section': 'Global Memory (persists across sessions)',
    'settings.global.hint': 'Use /remember in chat to save info. It will be referenced in all future chats.',
    'settings.global.add.label': 'Add manually',
    'settings.global.add.placeholder': 'e.g. My name is Daichi, I\'m an engineer',
    'settings.global.add.btn': 'Add',
    'settings.global.clear.btn': 'Clear All Global Memory',
    'settings.model.section': 'Ollama Model Manager',
    'settings.model.add.label': 'Add model',
    'settings.model.add.sub': 'Enter model name (e.g. llama3.2:3b)',
    'settings.model.add.btn': 'Add',
    'settings.model.use.btn': 'Use',
    'settings.model.update.btn': '🔄 Update',
    'settings.commands.section': 'Command Manager',
    'settings.commands.add.title': '＋ Add New Command',
    'settings.commands.add.btn': 'Add',
    'settings.commands.builtin': 'Built-in',
    'settings.commands.custom': 'Custom',
    'settings.lang.section': '言語 / Language / Idioma',
    'settings.lang.label': 'Display Language',
    'settings.appinfo.section': 'App Info',
    'settings.appinfo.version.label': 'Version',
    'settings.appinfo.privacy.label': 'Privacy',
    'settings.appinfo.privacy.sub': 'All data is stored locally on your Mac only',
    'settings.appinfo.privacy.badge': '🔒 100% Local',
    'settings.appinfo.author': 'Created by',
    'settings.appinfo.price': 'Price',

    'toast.saved': '✅ Settings saved',
    'toast.save.error': '❌ Failed to save',
    'toast.memory.cleared': '✅ Memory cleared',
    'toast.memory.added': '✅ Added to memory',
    'toast.memory.deleted': '✅ Deleted',
    'toast.command.added': '✅ Command added',
    'toast.command.deleted': '✅ Command deleted',
    'toast.model.updated': '✅ Model updated to latest',
    'voice.btn.title': 'Voice input (click to start/stop)',
    'voice.listening': '🎤 Listening...',
    'voice.error.no_speech': 'No speech detected',
    'voice.error.not_allowed': 'Microphone access denied. Please allow microphone access for Memoria in System Settings.',
    'voice.error.no_support': 'This browser does not support voice input',
  },

  es: {
    'app.name': 'Memoria',
    'app.tagline': 'Chat con IA que recuerda',
    'app.tagline.sub': 'Tus datos se guardan solo en tu Mac.',
    'app.version': 'Versión',

    'nav.chat': 'Chat',
    'nav.settings': 'Configuración y Comandos',

    'chat.new': '✏️ Chat Nuevo',
    'chat.placeholder': 'Escribe un mensaje... (/ para comandos, Cmd+Enter para enviar)',
    'chat.hint': 'Cmd+Enter para enviar · Enter para nueva línea · / para comandos',
    'chat.send': 'Enviar',

    'status.checking': 'Verificando...',
    'status.ollama.online': 'Ollama: Conectado',
    'status.ollama.offline': 'Ollama: No iniciado',
    'status.cloud.ready': 'IA: Lista',
    'status.claude.ready': 'Claude: Listo',
    'status.gemini.ready': 'Gemini: Listo',

    'session.delete.confirm': '¿Eliminar esta sesión?',
    'session.delete.success': 'Sesión eliminada',
    'session.title.edit.hint': 'Doble clic para editar',

    'mismatch.title': 'El modelo configurado no está instalado',
    'mismatch.install': 'Instalar Ahora',
    'mismatch.done': 'Listo',
    'mismatch.retrying': 'Reintentar',

    'engine.label': 'Motor de IA',
    'engine.ollama': '🖥️ Ollama (Local)',
    'engine.openai': '⚡ API compatible con OpenAI',
    'engine.claude': '🟠 Claude (Anthropic)',
    'engine.gemini': '💎 Gemini (Google)',
    'engine.switch.success': 'Motor cambiado (historial conservado)',

    'settings.title': 'Configuración y Comandos',
    'settings.ai.section': 'Motor de IA',
    'settings.ai.engine.label': 'Motor',
    'settings.ai.engine.sub': 'Selecciona la IA a usar',
    'settings.ai.save': 'Guardar',
    'settings.memory.section': 'Configuración de Memoria',
    'settings.memory.threshold.label': 'Intervalo de compresión',
    'settings.memory.threshold.sub': 'Cada cuántos intercambios resumir',
    'settings.memory.threshold.unit': 'intercambios',
    'settings.memory.clear.label': 'Borrar toda la memoria de sesión',
    'settings.memory.clear.sub': 'Elimina el historial y todos los resúmenes',
    'settings.memory.clear.btn': 'Borrar Todo',
    'settings.global.section': 'Memoria Global (persiste entre sesiones)',
    'settings.global.hint': 'Usa /remember en el chat. Se referenciará en futuros chats.',
    'settings.global.add.label': 'Añadir manualmente',
    'settings.global.add.placeholder': 'Ej. Mi nombre es Daichi, soy ingeniero',
    'settings.global.add.btn': 'Añadir',
    'settings.global.clear.btn': 'Borrar Toda la Memoria Global',
    'settings.model.section': 'Gestor de Modelos Ollama',
    'settings.model.add.label': 'Añadir modelo',
    'settings.model.add.sub': 'Nombre del modelo (ej. llama3.2:3b)',
    'settings.model.add.btn': 'Añadir',
    'settings.model.use.btn': 'Usar',
    'settings.model.update.btn': '🔄 Actualizar',
    'settings.commands.section': 'Gestor de Comandos',
    'settings.commands.add.title': '＋ Nuevo Comando',
    'settings.commands.add.btn': 'Añadir',
    'settings.commands.builtin': 'Integrado',
    'settings.commands.custom': 'Personalizado',
    'settings.lang.section': '言語 / Language / Idioma',
    'settings.lang.label': 'Idioma',
    'settings.appinfo.section': 'Información de la App',
    'settings.appinfo.version.label': 'Versión',
    'settings.appinfo.privacy.label': 'Privacidad',
    'settings.appinfo.privacy.sub': 'Todos los datos se guardan solo en tu Mac',
    'settings.appinfo.privacy.badge': '🔒 100% Local',
    'settings.appinfo.author': 'Creado por',
    'settings.appinfo.price': 'Precio',

    'toast.saved': '✅ Configuración guardada',
    'toast.save.error': '❌ Error al guardar',
    'toast.memory.cleared': '✅ Memoria borrada',
    'toast.memory.added': '✅ Añadido a la memoria',
    'toast.memory.deleted': '✅ Eliminado',
    'toast.command.added': '✅ Comando añadido',
    'toast.command.deleted': '✅ Comando eliminado',
    'toast.model.updated': '✅ Modelo actualizado',
    'voice.btn.title': 'Entrada de voz (clic para iniciar/detener)',
    'voice.listening': '🎤 Escuchando...',
    'voice.error.no_speech': 'No se detectó voz',
    'voice.error.not_allowed': 'Acceso al micrófono denegado. Permite el acceso al micrófono en Configuración del Sistema.',
    'voice.error.no_support': 'Este navegador no admite entrada de voz',
  }
};

// ===== Core i18n functions =====

function getCurrentLang() {
  return localStorage.getItem('memoria_lang') || 'ja';
}

function setLang(lang) {
  if (!TRANSLATIONS[lang]) return;
  localStorage.setItem('memoria_lang', lang);
  applyTranslations();
  // 動的コンテンツの再描画（各ページで onLangChange を定義すれば呼ばれる）
  if (typeof onLangChange === 'function') onLangChange();
}

function t(key) {
  const lang = getCurrentLang();
  return TRANSLATIONS[lang]?.[key] ?? TRANSLATIONS['en']?.[key] ?? key;
}

function applyTranslations() {
  // data-i18n: textContent
  document.querySelectorAll('[data-i18n]').forEach(el => {
    el.textContent = t(el.dataset.i18n);
  });
  // data-i18n-placeholder: placeholder attribute
  document.querySelectorAll('[data-i18n-placeholder]').forEach(el => {
    el.placeholder = t(el.dataset.i18nPlaceholder);
  });
  // data-i18n-title: title attribute
  document.querySelectorAll('[data-i18n-title]').forEach(el => {
    el.title = t(el.dataset.i18nTitle);
  });
  // Update html lang attribute
  const langMap = { ja: 'ja', en: 'en', es: 'es' };
  document.documentElement.lang = langMap[getCurrentLang()] || 'ja';
}

// Auto-apply on DOM ready
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', applyTranslations);
} else {
  applyTranslations();
}
