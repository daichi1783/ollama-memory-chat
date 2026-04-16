# -*- mode: python ; coding: utf-8 -*-
"""
Memoria PyInstaller spec
Mac .app バンドル + DMG配布用
"""
from PyInstaller.utils.hooks import collect_all, collect_data_files, collect_submodules

# ===== pywebview (macOS: WebKit / pyobjc) =====
webview_datas, webview_binaries, webview_hiddenimports = collect_all('webview')

# ===== FastAPI / Starlette / Uvicorn =====
starlette_hidden = collect_submodules('starlette')
fastapi_hidden   = collect_submodules('fastapi')
uvicorn_hidden   = collect_submodules('uvicorn')
anyio_hidden     = collect_submodules('anyio')

# ===== 音声入力: sounddevice + faster-whisper (optional) =====
try:
    sd_datas, sd_binaries, sd_hidden = collect_all('sounddevice')
except Exception:
    sd_datas, sd_binaries, sd_hidden = [], [], []

try:
    fw_datas, fw_binaries, fw_hidden = collect_all('faster_whisper')
except Exception:
    fw_datas, fw_binaries, fw_hidden = [], [], []

try:
    ct_datas, ct_binaries, ct_hidden = collect_all('ctranslate2')
except Exception:
    ct_datas, ct_binaries, ct_hidden = [], [], []

try:
    tok_datas, tok_binaries, tok_hidden = collect_all('tokenizers')
except Exception:
    tok_datas, tok_binaries, tok_hidden = [], [], []

# ===== pyobjc (macOS WebView が依存する Obj-C バインディング) =====
pyobjc_modules = [
    'objc',
    'Foundation', 'AppKit', 'WebKit', 'Cocoa',
    'CoreFoundation', 'CoreGraphics', 'CoreServices',
    'Quartz', 'QuartzCore',
]

a = Analysis(
    ['desktop_app.py'],
    pathex=['.'],
    binaries=[*webview_binaries, *sd_binaries, *fw_binaries, *ct_binaries, *tok_binaries],
    datas=[
        ('frontend',    'frontend'),     # HTML/JS/CSS
        ('config.yaml', '.'),            # デフォルト設定
        ('backend',     'backend'),      # Pythonバックエンド
        *webview_datas,
        *collect_data_files('starlette'),
        *collect_data_files('fastapi'),
        *collect_data_files('ollama'),
        *sd_datas,
        *fw_datas,
        *ct_datas,
        *tok_datas,
    ],
    hiddenimports=[
        # === pywebview ===
        *webview_hiddenimports,
        'webview.platforms.cocoa',
        'webview.js',
        'webview.menu',
        # === pyobjc ===
        *pyobjc_modules,
        # === FastAPI / Starlette ===
        *fastapi_hidden,
        *starlette_hidden,
        'starlette.middleware.base',
        'starlette.middleware.cors',
        'starlette.routing',
        'starlette.staticfiles',
        'starlette.responses',
        'starlette.requests',
        'starlette.datastructures',
        'starlette.types',
        'starlette.background',
        'starlette.concurrency',
        # === Uvicorn ===
        *uvicorn_hidden,
        'uvicorn.main',
        'uvicorn.config',
        'uvicorn.server',
        'uvicorn.logging',
        'uvicorn.loops.auto',
        'uvicorn.loops.asyncio',
        'uvicorn.protocols.http.auto',
        'uvicorn.protocols.http.h11_impl',
        'uvicorn.protocols.websockets.auto',
        'uvicorn.lifespan.on',
        'uvicorn.lifespan.off',
        'uvicorn.middleware.proxy_headers',
        # === anyio / httpx ===
        *anyio_hidden,
        'anyio._backends._asyncio',
        # === Pydantic ===
        'pydantic',
        'pydantic.validators',
        'pydantic.fields',
        # === その他 ===
        'yaml',
        'sqlite3',
        'ollama',
        'requests',
        'multipart',
        'python_multipart',
        'h11',
        'h2',
        'click',
        'email.mime.text',
        'email.mime.multipart',
        'importlib.metadata',
        # === 音声入力 (optional) ===
        *sd_hidden,
        *fw_hidden,
        *ct_hidden,
        *tok_hidden,
        'sounddevice',
        'soundfile',
        'faster_whisper',
        'faster_whisper.transcribe',
        'faster_whisper.audio',
        'faster_whisper.tokenizer',
        'ctranslate2',
        'tokenizers',
        'scipy',
        'scipy.io',
        'scipy.io.wavfile',
        'numpy',
        'numpy.core',
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=['tkinter', '_tkinter'],
    noarchive=False,
    optimize=0,
)

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='Memoria',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=False,           # Macウィンドウアプリ（ターミナル非表示）
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=False,
    upx_exclude=[],
    name='Memoria',
)

app = BUNDLE(
    coll,
    name='Memoria.app',
    icon='Memoria.icns',
    bundle_identifier='com.daichit.memoria',
    version='0.1.0',
    info_plist={
        'NSPrincipalClass': 'NSApplication',
        'NSAppleScriptEnabled': False,
        'CFBundleDisplayName': 'Memoria',
        'CFBundleShortVersionString': '0.1.0',
        'NSHighResolutionCapable': True,
        'NSRequiresAquaSystemAppearance': False,   # ダークモード対応
        'LSMinimumSystemVersion': '12.0',
        # プライバシー説明（App Store非対象でも明示しておく）
        'NSLocalNetworkUsageDescription': 'Memoriaはローカルのオープンソースサービスと通信します。',
        'NSMicrophoneUsageDescription': 'Memoriaは音声入力のためにマイクを使用します。マイクへのアクセスを許可してください。',
    },
)
