// frontend/assets/license.js — Memoria license activation + paywall
// 1. Renders a "License" panel on settings.html when the host page exposes
//    <div id="licensePanel"></div>.
// 2. Exposes window.MemoriaPaywall.show() / .hide() — called from app.js
//    when /api/chat returns 402 (free question quota exhausted).
//
// All UI strings come from i18n.js (TRANSLATIONS). Keys live under
// "license.*" and "paywall.*".

(function () {
  const API_BASE = "http://127.0.0.1:18765";
  const PRICING_URL = "https://kotomori.app";

  function tFn(key, fallback) {
    return typeof t === "function" ? t(key) || fallback || key : fallback || key;
  }

  async function fetchState() {
    try {
      const r = await fetch(`${API_BASE}/api/license/state`);
      if (!r.ok) return null;
      return await r.json();
    } catch (e) {
      return null;
    }
  }

  // ── Settings panel ──────────────────────────────────────────────────────
  function renderSettingsPanel(state) {
    const root = document.getElementById("licensePanel");
    if (!root) return;

    const isPro = state && state.is_pro;
    const remaining = state ? state.remaining_free : 20;
    const masked = state ? state.license_masked : null;
    const configMissing = state ? state.configuration_missing : false;
    const expiresStr = state && state.expires_at
      ? new Date(state.expires_at * 1000).toLocaleDateString()
      : "—";

    root.innerHTML = `
      <div class="license-panel">
        <div class="license-status">
          <div class="license-status-icon">${isPro ? "🔓" : "🔐"}</div>
          <div class="license-status-text">
            <div class="license-status-label">${tFn(isPro ? "license.status.pro" : "license.status.free", isPro ? "Pro" : "Free")}</div>
            <div class="license-status-sub">${
              isPro
                ? tFn("license.status.pro_sub", `Activated · ${masked || ""} · expires ${expiresStr}`).replace("{key}", masked || "").replace("{date}", expiresStr)
                : tFn("license.status.free_sub", `${remaining} of ${state ? state.free_limit : 20} free questions left`).replace("{remaining}", String(remaining)).replace("{limit}", String(state ? state.free_limit : 20))
            }</div>
          </div>
        </div>

        ${configMissing ? `<div class="license-warning">${tFn("license.config_missing", "Public key not bundled — license verification disabled")}</div>` : ""}

        ${
          isPro
            ? `<button class="license-btn-secondary" onclick="window.MemoriaLicense.deactivate()">${tFn("license.btn.deactivate", "Deactivate on this Mac")}</button>`
            : `
              <div class="license-input-row">
                <input id="licenseKeyInput" type="text" class="license-input" placeholder="MEMR-XXXX-XXXX-XXXX-XXXX-XXXX" autocapitalize="characters" autocorrect="off" spellcheck="false" />
                <button class="license-btn-primary" onclick="window.MemoriaLicense.activate()">${tFn("license.btn.activate", "Activate")}</button>
              </div>
              <a href="${PRICING_URL}" target="_blank" class="license-buy-link">${tFn("license.no_key", "Don't have a key? Buy Memoria")}</a>
            `
        }
      </div>
    `;
  }

  async function refreshSettingsPanel() {
    const state = await fetchState();
    renderSettingsPanel(state);
  }

  async function activate() {
    const input = document.getElementById("licenseKeyInput");
    if (!input) return;
    const key = input.value.trim();
    if (!key) return;

    const btn = input.nextElementSibling;
    if (btn) btn.disabled = true;

    try {
      const r = await fetch(`${API_BASE}/api/license/activate`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ license_key: key }),
      });
      const body = await r.json();
      if (!r.ok) {
        const code = (body && body.detail && body.detail.error) || (body && body.error) || `http_${r.status}`;
        showToast(tFn("license.error." + code, tFn("license.error.generic", `Activation failed: ${code}`)), "error");
        return;
      }
      showToast(tFn("license.toast.activated", "✅ License activated"));
      await refreshSettingsPanel();
      MemoriaPaywall.hide();
    } finally {
      if (btn) btn.disabled = false;
    }
  }

  async function deactivate() {
    if (!confirm(tFn("license.confirm.deactivate", "Remove the license from this Mac?"))) return;
    await fetch(`${API_BASE}/api/license/deactivate`, { method: "POST" });
    showToast(tFn("license.toast.deactivated", "License removed from this Mac"));
    await refreshSettingsPanel();
  }

  // ── Paywall overlay ─────────────────────────────────────────────────────
  function ensurePaywallOverlay() {
    let el = document.getElementById("paywallOverlay");
    if (el) return el;
    el = document.createElement("div");
    el.id = "paywallOverlay";
    el.className = "paywall-overlay";
    el.style.display = "none";
    el.innerHTML = `
      <div class="paywall-card">
        <div class="paywall-icon">🎉</div>
        <h2 class="paywall-title">${tFn("paywall.title", "Thanks for trying Memoria!")}</h2>
        <p class="paywall-body">${tFn("paywall.body", "You've used your 20 free questions. Unlock unlimited chat for $14.99 (one-time, 3 devices).")}</p>
        <div class="paywall-actions">
          <a href="${PRICING_URL}" target="_blank" class="paywall-btn-primary">${tFn("paywall.btn.buy", "Buy Memoria — $14.99")}</a>
          <button class="paywall-btn-secondary" onclick="window.MemoriaPaywall.openActivate()">${tFn("paywall.btn.have_key", "I already have a key")}</button>
          <button class="paywall-btn-tertiary" onclick="window.MemoriaPaywall.hide()">${tFn("paywall.btn.later", "Maybe later")}</button>
        </div>
      </div>
    `;
    document.body.appendChild(el);
    return el;
  }

  function showPaywall() {
    const el = ensurePaywallOverlay();
    el.style.display = "flex";
  }

  function hidePaywall() {
    const el = document.getElementById("paywallOverlay");
    if (el) el.style.display = "none";
  }

  function openActivateFromPaywall() {
    // Navigate to settings (where the License panel lives)
    window.location.href = "/settings#license";
  }

  // ── showToast fallback ──────────────────────────────────────────────────
  function showToast(msg, kind) {
    if (typeof window.showToast === "function" && window.showToast !== showToast) {
      window.showToast(msg, kind);
      return;
    }
    const el = document.getElementById("toast");
    if (!el) {
      console.log("[memoria]", msg);
      return;
    }
    el.textContent = msg;
    el.className = "toast" + (kind === "error" ? " toast-error" : "");
    el.style.display = "block";
    setTimeout(() => { el.style.display = "none"; }, 3000);
  }

  window.MemoriaLicense = {
    activate,
    deactivate,
    refresh: refreshSettingsPanel,
  };
  window.MemoriaPaywall = {
    show: showPaywall,
    hide: hidePaywall,
    openActivate: openActivateFromPaywall,
  };

  // Auto-init: if the host page has a #licensePanel slot, render into it.
  document.addEventListener("DOMContentLoaded", () => {
    if (document.getElementById("licensePanel")) {
      refreshSettingsPanel();
    }
  });
})();
