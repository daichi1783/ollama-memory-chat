"""
license_service.py — Memoria activation token + 20-question free tier.

Talks to the kotomori web API at /api/memoria/activate to exchange a
user-pasted license key for an ES256-signed JWT, then keeps that token in
the macOS Keychain (with a file fallback) so subsequent launches verify
locally and offline.

Free tier (no token):
    20 chat messages total. Counter is per-device, persisted to
    ~/Library/Application Support/Memoria/usage.json. After 20, /api/chat
    returns 402 and the frontend shows a paywall.

Pro tier (valid token):
    Unlimited chat. Counter is still incremented for analytics but never
    blocks.

Public-key bundling:
    Looks for `mac-app/backend/memoria-public-key.json` (a JWK as printed
    by `pnpm --filter web gen:memoria-keys` Block 3). If absent, activation
    still succeeds but the token can't be locally verified — the service
    falls into a "configuration_missing" state that the UI surfaces.
"""
from __future__ import annotations

import json
import logging
import os
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import requests

try:
    import jwt
    from jwt.algorithms import ECAlgorithm
    _JWT_AVAILABLE = True
except ImportError:
    _JWT_AVAILABLE = False

try:
    import keyring
    _KEYRING_AVAILABLE = True
except ImportError:
    _KEYRING_AVAILABLE = False

import device_identifier

log = logging.getLogger("memoria.license")

# ─────────────────────────────────────────────────────────────────────────────
# Config

KOTOMORI_BASE_URL = os.environ.get("KOTOMORI_BASE_URL", "https://kotomori.app")
ACTIVATE_PATH = "/api/memoria/activate"
PRODUCT_ID = "memoria.license.standard"
FREE_QUESTION_LIMIT = 20

KEYCHAIN_SERVICE = "kotomori-memoria"
KEYCHAIN_ACCOUNT = "activation_token"

_APP_SUPPORT = Path.home() / "Library" / "Application Support" / "Memoria"
_USAGE_PATH = _APP_SUPPORT / "usage.json"
_TOKEN_FALLBACK_PATH = _APP_SUPPORT / "license_token.txt"  # used only when keyring unavailable
_PUBLIC_KEY_JWK_PATH = Path(__file__).parent / "memoria-public-key.json"


# ─────────────────────────────────────────────────────────────────────────────
# Public-key loader

def _load_public_key():
    """Load the bundled JWK and return it as a cryptography PublicKey, or None."""
    if not _JWT_AVAILABLE or not _PUBLIC_KEY_JWK_PATH.exists():
        return None
    try:
        jwk_dict = json.loads(_PUBLIC_KEY_JWK_PATH.read_text())
        return ECAlgorithm.from_jwk(json.dumps(jwk_dict))
    except Exception as e:
        log.warning("failed to load public key JWK: %s", e)
        return None


_PUBLIC_KEY = _load_public_key()


# ─────────────────────────────────────────────────────────────────────────────
# Token store

def _store_token(token: str) -> None:
    if _KEYRING_AVAILABLE:
        try:
            keyring.set_password(KEYCHAIN_SERVICE, KEYCHAIN_ACCOUNT, token)
            return
        except Exception as e:
            log.warning("keychain write failed, falling back to file: %s", e)
    _APP_SUPPORT.mkdir(parents=True, exist_ok=True)
    _TOKEN_FALLBACK_PATH.write_text(token)
    os.chmod(_TOKEN_FALLBACK_PATH, 0o600)


def _read_token() -> Optional[str]:
    if _KEYRING_AVAILABLE:
        try:
            t = keyring.get_password(KEYCHAIN_SERVICE, KEYCHAIN_ACCOUNT)
            if t:
                return t
        except Exception as e:
            log.warning("keychain read failed, trying file fallback: %s", e)
    if _TOKEN_FALLBACK_PATH.exists():
        return _TOKEN_FALLBACK_PATH.read_text().strip() or None
    return None


def _clear_token() -> None:
    if _KEYRING_AVAILABLE:
        try:
            keyring.delete_password(KEYCHAIN_SERVICE, KEYCHAIN_ACCOUNT)
        except Exception:
            pass
    if _TOKEN_FALLBACK_PATH.exists():
        _TOKEN_FALLBACK_PATH.unlink()


# ─────────────────────────────────────────────────────────────────────────────
# Usage counter

def _read_usage() -> int:
    if not _USAGE_PATH.exists():
        return 0
    try:
        data = json.loads(_USAGE_PATH.read_text())
        return int(data.get("question_count", 0))
    except Exception:
        return 0


def _write_usage(count: int) -> None:
    _APP_SUPPORT.mkdir(parents=True, exist_ok=True)
    _USAGE_PATH.write_text(json.dumps({"question_count": count}))


# ─────────────────────────────────────────────────────────────────────────────
# Public service

@dataclass
class LicenseState:
    is_pro: bool
    question_count: int
    free_limit: int
    license_masked: Optional[str]
    expires_at: Optional[int]  # unix seconds
    configuration_missing: bool  # True when public key isn't bundled yet
    error: Optional[str] = None  # last activation error code, if any


class LicenseService:
    """Process-singleton holding the current license state."""

    def __init__(self):
        self._state = self._compute_state()

    def _compute_state(self) -> LicenseState:
        token = _read_token()
        usage = _read_usage()
        is_pro = False
        license_masked = None
        expires_at = None

        if token and _PUBLIC_KEY is not None:
            try:
                payload = jwt.decode(
                    token,
                    _PUBLIC_KEY,
                    algorithms=["ES256"],
                    audience="memoria.app",
                    issuer="kotomori.app",
                )
                if payload.get("prd") == PRODUCT_ID:
                    is_pro = True
                    license_masked = "MEMR-…-" + str(payload.get("lic", ""))[-4:]
                    expires_at = int(payload.get("exp", 0))
            except jwt.ExpiredSignatureError:
                log.info("activation token expired")
            except jwt.InvalidTokenError as e:
                log.warning("activation token invalid: %s", e)

        return LicenseState(
            is_pro=is_pro,
            question_count=usage,
            free_limit=FREE_QUESTION_LIMIT,
            license_masked=license_masked,
            expires_at=expires_at,
            configuration_missing=(_PUBLIC_KEY is None),
        )

    def state(self) -> LicenseState:
        return self._state

    def can_send_message(self) -> bool:
        s = self._state
        return s.is_pro or s.question_count < s.free_limit

    def increment_question_count(self) -> None:
        s = self._state
        new_count = s.question_count + 1
        _write_usage(new_count)
        self._state = LicenseState(
            is_pro=s.is_pro,
            question_count=new_count,
            free_limit=s.free_limit,
            license_masked=s.license_masked,
            expires_at=s.expires_at,
            configuration_missing=s.configuration_missing,
            error=s.error,
        )

    def activate(self, license_key: str) -> tuple[bool, dict]:
        """Call kotomori activation API, persist the returned JWT.

        Returns (ok, payload) where payload mirrors the API response on success
        or contains {"error": "code"} on failure.
        """
        device_id = device_identifier.get_device_id()
        hostname = device_identifier.get_hostname()
        try:
            resp = requests.post(
                f"{KOTOMORI_BASE_URL}{ACTIVATE_PATH}",
                json={
                    "license_key": license_key,
                    "device_id": device_id,
                    "hostname": hostname,
                    "user_agent": "Memoria/1.0 (macOS; python)",
                },
                timeout=15,
            )
        except requests.RequestException as e:
            log.error("activate network error: %s", e)
            return False, {"error": "network_error"}

        try:
            body = resp.json()
        except ValueError:
            return False, {"error": "invalid_response"}

        if resp.status_code != 200 or not body.get("activation_token"):
            return False, {"error": body.get("error", f"http_{resp.status_code}")}

        _store_token(body["activation_token"])
        self._state = self._compute_state()
        return True, body

    def deactivate(self) -> None:
        """Local-only: forget the saved token. Doesn't free up a device slot
        on the server; that requires a separate /deactivate endpoint (TODO)."""
        _clear_token()
        self._state = self._compute_state()

    def reset_for_test(self) -> None:
        """Wipe local state. Not exposed via API; used by smoke tests only."""
        _clear_token()
        if _USAGE_PATH.exists():
            _USAGE_PATH.unlink()
        self._state = self._compute_state()


_singleton: Optional[LicenseService] = None


def get_service() -> LicenseService:
    global _singleton
    if _singleton is None:
        _singleton = LicenseService()
    return _singleton
