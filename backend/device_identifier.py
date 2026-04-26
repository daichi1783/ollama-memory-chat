"""
device_identifier.py — Stable per-device ID for license activation.

Returns the Mac's IOPlatformUUID (a stable hardware UUID that survives
re-installs but changes on logic-board replacement, which is the desired
property for a 3-device license cap).

Falls back to a self-generated UUID stored in
`~/Library/Application Support/Memoria/device_id` when ioreg is
unavailable (e.g. in CI / containers / non-macOS dev).
"""
from __future__ import annotations

import os
import re
import subprocess
import uuid
from pathlib import Path


_FALLBACK_PATH = Path.home() / "Library" / "Application Support" / "Memoria" / "device_id"


def _read_ioreg_uuid() -> str | None:
    try:
        result = subprocess.run(
            ["ioreg", "-rd1", "-c", "IOPlatformExpertDevice"],
            capture_output=True,
            text=True,
            timeout=3,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return None
    match = re.search(r'"IOPlatformUUID"\s*=\s*"([0-9A-Fa-f-]+)"', result.stdout)
    return match.group(1) if match else None


def _fallback_uuid() -> str:
    if _FALLBACK_PATH.exists():
        text = _FALLBACK_PATH.read_text().strip()
        if text:
            return text
    _FALLBACK_PATH.parent.mkdir(parents=True, exist_ok=True)
    new_id = str(uuid.uuid4())
    _FALLBACK_PATH.write_text(new_id)
    os.chmod(_FALLBACK_PATH, 0o600)
    return new_id


def get_device_id() -> str:
    """Return a stable per-device identifier (≤ 256 chars, ≥ 4 chars)."""
    return _read_ioreg_uuid() or _fallback_uuid()


def get_hostname() -> str:
    """Best-effort short hostname for the activation payload (display only)."""
    try:
        result = subprocess.run(
            ["scutil", "--get", "ComputerName"],
            capture_output=True,
            text=True,
            timeout=2,
        )
        name = result.stdout.strip()
        if name:
            return name
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass
    return os.uname().nodename if hasattr(os, "uname") else "unknown"
