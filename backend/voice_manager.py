"""
オフライン音声認識モジュール
- sounddevice でマイク入力を録音（Python側で直接制御）
- faster-whisper でローカル完結の音声テキスト変換
- インターネット不要・Web Speech API 不使用
"""
import threading
import tempfile
import os

import numpy as np

# 録音状態
_is_recording = False
_recording_data: list = []
_recording_thread = None
_stop_event = threading.Event()
_SAMPLE_RATE = 16000   # Whisperが16kHzを期待する

# Whisperモデル（シングルトン: 初回のみダウンロード・以降はキャッシュ）
_model = None
_model_lock = threading.Lock()
_MODEL_SIZE = "base"   # tiny(40MB) / base(145MB) / small(488MB)


# ──────────────────────────────────────────────
# モデル管理
# ──────────────────────────────────────────────

def _get_model():
    """Whisperモデルを返す。初回のみ ~/.cache/huggingface/ にダウンロード。"""
    global _model
    if _model is None:
        with _model_lock:
            if _model is None:
                from faster_whisper import WhisperModel
                _model = WhisperModel(
                    _MODEL_SIZE,
                    device="cpu",
                    compute_type="int8",   # CPU向け量子化（速度向上）
                )
    return _model


def get_model_status() -> dict:
    """モデルのロード状態を返す"""
    try:
        from faster_whisper import WhisperModel
        # モデルキャッシュが存在するか確認
        import huggingface_hub
        model_id = f"guillaumekln/faster-whisper-{_MODEL_SIZE}"
        try:
            huggingface_hub.cached_download(
                huggingface_hub.hf_hub_url(model_id, "model.bin"),
                cache_dir=None,
                force_download=False,
                local_files_only=True,
            )
            cached = True
        except Exception:
            cached = False
        return {"available": True, "model": _MODEL_SIZE, "cached": cached, "loaded": _model is not None}
    except ImportError:
        return {"available": False, "model": _MODEL_SIZE, "cached": False, "loaded": False,
                "error": "faster-whisper がインストールされていません"}


# ──────────────────────────────────────────────
# 録音制御
# ──────────────────────────────────────────────

def is_recording() -> bool:
    return _is_recording


def start_recording() -> dict:
    """マイク録音を開始する（バックグラウンドスレッドで録音）"""
    global _is_recording, _recording_data, _recording_thread, _stop_event

    if _is_recording:
        return {"success": False, "message": "すでに録音中です"}

    try:
        import sounddevice as sd  # noqa: F401 — インポート確認
    except ImportError:
        return {"success": False, "message": "sounddevice がインストールされていません。pip install sounddevice を実行してください。"}

    _is_recording = True
    _recording_data = []
    _stop_event = threading.Event()

    def _record_loop():
        import sounddevice as sd
        with sd.InputStream(
            samplerate=_SAMPLE_RATE,
            channels=1,
            dtype="float32",
            blocksize=1024,
        ) as stream:
            while not _stop_event.is_set():
                frames, _ = stream.read(1024)
                _recording_data.append(frames.copy())

    _recording_thread = threading.Thread(target=_record_loop, daemon=True)
    _recording_thread.start()

    return {"success": True, "message": "録音を開始しました"}


def stop_and_transcribe(language: str | None = None) -> dict:
    """録音を停止してWhisperでテキストに変換する。
    language: "ja" / "en" / "es" / None（自動検出）
    """
    global _is_recording

    if not _is_recording:
        return {"success": False, "message": "録音中ではありません", "text": ""}

    # 録音停止
    _is_recording = False
    _stop_event.set()
    if _recording_thread and _recording_thread.is_alive():
        _recording_thread.join(timeout=2.0)

    if not _recording_data:
        return {"success": False, "message": "音声データがありません", "text": ""}

    # numpy 配列に結合
    audio = np.concatenate(_recording_data, axis=0).flatten()

    # 無音チェック（0.3秒未満は短すぎる）
    if len(audio) < _SAMPLE_RATE * 0.3:
        return {"success": False, "message": "録音が短すぎます。もう少し長く話してください。", "text": ""}

    # 一時WAVファイルに書き出す
    import scipy.io.wavfile as wav_io
    tmp_path = None
    try:
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
            tmp_path = tmp.name

        # float32 [-1, 1] → int16 [-32768, 32767] に変換してWAV保存
        audio_int16 = np.clip(audio * 32767, -32768, 32767).astype(np.int16)
        wav_io.write(tmp_path, _SAMPLE_RATE, audio_int16)

        # Whisper で文字起こし
        model = _get_model()
        segments, info = model.transcribe(
            tmp_path,
            language=language,   # None で自動検出
            beam_size=5,
            vad_filter=True,     # 無音区間をフィルタリング
            vad_parameters=dict(min_silence_duration_ms=500),
        )
        text = "".join(seg.text for seg in segments).strip()

        if not text:
            return {"success": False, "message": "音声が認識できませんでした", "text": ""}

        return {
            "success": True,
            "text": text,
            "language": info.language,
            "language_probability": round(info.language_probability, 2),
        }

    except Exception as e:
        import traceback
        return {"success": False, "message": f"認識エラー: {str(e)}", "text": "",
                "detail": traceback.format_exc()}
    finally:
        if tmp_path and os.path.exists(tmp_path):
            os.unlink(tmp_path)
