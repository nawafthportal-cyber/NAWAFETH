/* ===================================================================
   auth.js — Authentication state manager
   Stores JWT tokens in browser storage, exposes helper methods.
   =================================================================== */
'use strict';

const Auth = (() => {
  const KEY_ACCESS  = 'nw_access_token';
  const KEY_REFRESH = 'nw_refresh_token';
  const KEY_USER_ID = 'nw_user_id';
  const KEY_ROLE    = 'nw_role_state';
  const AUTH_KEYS = [KEY_ACCESS, KEY_REFRESH, KEY_USER_ID, KEY_ROLE];

  function _serverAuth() {
    try {
      return window.NAWAFETH_SERVER_AUTH || null;
    } catch {
      return null;
    }
  }

  function _sessionStore() {
    try { return window.sessionStorage; } catch { return null; }
  }

  function _localStore() {
    try { return window.localStorage; } catch { return null; }
  }

  function _readFrom(store, key) {
    try { return store ? store.getItem(key) : null; } catch { return null; }
  }

  function _writeTo(store, key, value) {
    try {
      if (!store || value === null || value === undefined || value === '') return;
      store.setItem(key, String(value));
    } catch { /* quota / unavailable */ }
  }

  function _removeFrom(store, key) {
    try {
      if (!store) return;
      store.removeItem(key);
    } catch { /* unavailable */ }
  }

  function _syncStoredAuth() {
    const session = _sessionStore();
    const local = _localStore();
    AUTH_KEYS.forEach((key) => {
      const sessionValue = _readFrom(session, key);
      const localValue = _readFrom(local, key);
      const effectiveValue = sessionValue || localValue;
      if (!effectiveValue) return;
      if (!sessionValue) _writeTo(session, key, effectiveValue);
      if (!localValue) _writeTo(local, key, effectiveValue);
    });
    _writeModeCookie(_readStoredMode());
  }

  function _readAuthValue(key) {
    const session = _sessionStore();
    const local = _localStore();
    const sessionValue = _readFrom(session, key);
    if (sessionValue) return sessionValue;
    const localValue = _readFrom(local, key);
    if (localValue) _writeTo(session, key, localValue);
    return localValue;
  }

  function _writeAuthValue(key, value) {
    _writeTo(_sessionStore(), key, value);
    _writeTo(_localStore(), key, value);
  }

  function _clearAuthValue(key) {
    _removeFrom(_sessionStore(), key);
    _removeFrom(_localStore(), key);
  }

  function isLoggedIn() {
    const serverAuth = _serverAuth();
    return !!(getAccessToken() || getRefreshToken() || (serverAuth && serverAuth.isAuthenticated));
  }

  function isProviderAccount() {
    return String(getRoleState() || '').trim().toLowerCase() === 'provider';
  }

  function isProviderModeActive() {
    return String(getActiveAccountMode() || '').trim().toLowerCase() === 'provider';
  }

  function isServiceRequestBlockedForCurrentMode() {
    return !!(isLoggedIn() && isProviderAccount() && isProviderModeActive());
  }

  function switchToClientMode(options) {
    setActiveAccountMode('client');
    const target = options && options.target ? String(options.target).trim() : '';
    if (target) {
      window.location.href = target;
      return;
    }
    window.location.reload();
  }

  function _providerRequestBlockMarkup(options) {
    const kicker = String(options?.kicker || 'وضع الحساب الحالي').trim();
    const title = String(options?.title || 'طلبات الخدمة متاحة في وضع العميل فقط').trim();
    const description = String(
      options?.description
      || 'أنت الآن تستخدم المنصة بوضع مقدم الخدمة، لذلك تم إيقاف إنشاء الطلبات الجديدة من هذا المسار. بدّل نوع الحساب إلى عميل ثم أكمل الطلب بكل سلاسة.'
    ).trim();
    const note = String(
      options?.note
      || 'يمكنك التبديل مباشرة الآن دون تسجيل خروج، ثم المتابعة في نفس المسار.'
    ).trim();
    const switchLabel = String(options?.switchLabel || 'التبديل إلى عميل الآن').trim();
    const profileLabel = String(options?.profileLabel || 'الذهاب إلى نافذتي').trim();
    return '' +
      '<p class="auth-gate-unified-kicker">' + kicker + '</p>' +
      '<div class="auth-gate-unified-icon" aria-hidden="true">' +
        '<svg width="34" height="34" viewBox="0 0 24 24" fill="currentColor"><path d="M20 6h-4V4c0-1.11-.89-2-2-2h-4c-1.11 0-2 .89-2 2v2H4c-1.11 0-2 .9-2 2v11c0 1.1.89 2 2 2h16c1.1 0 2-.9 2-2V8c0-1.1-.9-2-2-2zm-6 0h-4V4h4v2z"/></svg>' +
      '</div>' +
      '<h2 class="auth-gate-unified-title">' + title + '</h2>' +
      '<p class="auth-gate-unified-desc">' + description + '</p>' +
      '<div class="auth-gate-unified-actions" style="display:flex;flex-wrap:wrap;gap:10px;justify-content:center;margin-top:16px">' +
        '<button type="button" class="btn btn-primary auth-gate-unified-btn" data-provider-request-switch="client">' + switchLabel + '</button>' +
        '<a href="/profile/" class="btn btn-secondary" style="min-height:48px;padding:0 18px;border-radius:14px;text-decoration:none;display:inline-flex;align-items:center;justify-content:center">' + profileLabel + '</a>' +
      '</div>' +
      '<p class="auth-gate-unified-note" style="margin-top:12px">' + note + '</p>';
  }

  function renderProviderRequestBlock(options) {
    const gate = document.getElementById(String(options?.gateId || 'auth-gate'));
    const content = document.getElementById(String(options?.contentId || 'form-content'));
    if (gate) {
      gate.innerHTML = _providerRequestBlockMarkup(options);
      gate.classList.remove('hidden');
      _bindProviderRequestSwitchButtons(gate, { target: options?.target || window.location.pathname });
    }
    if (content) content.classList.add('hidden');
  }

  function ensureServiceRequestAccess(options) {
    if (!isServiceRequestBlockedForCurrentMode()) return true;
    renderProviderRequestBlock(options || {});
    return false;
  }

  function getAccessToken() {
    return _readAuthValue(KEY_ACCESS);
  }

  function getRefreshToken() {
    return _readAuthValue(KEY_REFRESH);
  }

  function getUserId() {
    const stored = _readAuthValue(KEY_USER_ID);
    if (stored) return stored;
    const serverAuth = _serverAuth();
    if (serverAuth && serverAuth.isAuthenticated && serverAuth.userId !== null && serverAuth.userId !== undefined) {
      return String(serverAuth.userId);
    }
    return null;
  }

  function getRoleState() {
    const stored = _readAuthValue(KEY_ROLE);
    if (stored) return stored;
    const serverAuth = _serverAuth();
    if (serverAuth && serverAuth.isAuthenticated) {
      return String(serverAuth.roleState || 'client').trim().toLowerCase() || 'client';
    }
    return 'guest';
  }

  function needsCompletion() {
    const role = String(getRoleState() || '').trim().toLowerCase();
    return role === 'phone_only' || role === 'visitor';
  }

  function saveTokens(data) {
    if (!data || typeof data !== 'object') return;
    if (data.access) _writeAuthValue(KEY_ACCESS, data.access);
    if (data.refresh) _writeAuthValue(KEY_REFRESH, data.refresh);
    if (data.user_id) _writeAuthValue(KEY_USER_ID, String(data.user_id));
    if (data.role_state) _writeAuthValue(KEY_ROLE, data.role_state);
  }

  function saveRoleState(roleState) {
    if (!roleState) return;
    _writeAuthValue(KEY_ROLE, roleState);
  }

  function logout() {
    AUTH_KEYS.forEach(_clearAuthValue);
    _profileCache = Object.create(null);
    _clearModeCookie();
    try { window.dispatchEvent(new Event('nw:auth-logout')); } catch {}
  }

  function clearProfileCache() {
    _profileCache = Object.create(null);
  }

  /** Try to refresh the access token using the refresh token */
  async function refreshAccessToken() {
    const result = await ApiClient.refreshAccessToken();
    return !!(result && result.ok);
  }

  /** Require login — redirects to /login/ if not authenticated */
  function requireLogin(returnUrl) {
    if (isLoggedIn()) return true;
    const ret = returnUrl || window.location.pathname;
    window.location.href = '/login/?next=' + encodeURIComponent(ret);
    return false;
  }

  function _readStoredMode() {
    try {
      const mode = String(window.sessionStorage.getItem('nw_account_mode') || '').trim().toLowerCase();
      return mode === 'provider' ? 'provider' : 'client';
    } catch {
      return 'client';
    }
  }

  function _writeModeCookie(mode) {
    try {
      window.document.cookie = 'nw_account_mode=' + encodeURIComponent(mode) + '; path=/; max-age=31536000; SameSite=Lax';
    } catch {}
  }

  function _clearModeCookie() {
    try {
      window.document.cookie = 'nw_account_mode=; path=/; expires=Thu, 01 Jan 1970 00:00:00 GMT; SameSite=Lax';
    } catch {}
  }

  function _bindProviderRequestSwitchButtons(root, options) {
    if (!root || typeof root.querySelectorAll !== 'function') return;
    root.querySelectorAll('[data-provider-request-switch="client"]').forEach((button) => {
      if (!button || button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', () => {
        const target = String(button.getAttribute('data-provider-request-target') || options?.target || window.location.pathname || '').trim();
        switchToClientMode({ target });
      });
    });
  }

  function hydrateProviderRequestBlocks() {
    _bindProviderRequestSwitchButtons(window.document, { target: window.location.pathname });
  }

  function getActiveAccountMode() {
    return _readStoredMode();
  }

  function setActiveAccountMode(mode) {
    const normalized = String(mode || '').trim().toLowerCase() === 'provider' ? 'provider' : 'client';
    const previous = _readStoredMode();
    try {
      window.sessionStorage.setItem('nw_account_mode', normalized);
    } catch {}
    _writeModeCookie(normalized);
    if (previous !== normalized) {
      try {
        window.dispatchEvent(new CustomEvent('nw:account-mode-changed', {
          detail: { mode: normalized, previousMode: previous },
        }));
      } catch {}
    }
    return normalized;
  }

  function _normalizeProfileMode(modeOverride) {
    const normalized = String(modeOverride || '').trim().toLowerCase();
    if (normalized === 'provider' || normalized === 'client') return normalized;
    return getActiveAccountMode();
  }

  function _sleep(ms) {
    return new Promise((resolve) => {
      window.setTimeout(resolve, ms);
    });
  }

  async function _fetchProfileForMode(mode, force) {
    if (_profileCache[mode] && !force) {
      return { ok: true, status: 200, data: _profileCache[mode], mode, fromCache: true };
    }

    let res = await ApiClient.get('/api/accounts/me/?mode=' + mode);
    if ((res.status === 503 || res.status === 0) && isLoggedIn()) {
      await _sleep(450);
      res = await ApiClient.get('/api/accounts/me/?mode=' + mode);
    }

    if (res.ok && res.data) {
      _profileCache[mode] = res.data;
    }
    return Object.assign({ mode, fromCache: false }, res);
  }

  async function resolveProfile(force, modeOverride) {
    const requestedMode = _normalizeProfileMode(modeOverride);
    if (!isLoggedIn()) {
      return { ok: false, status: 401, profile: null, mode: requestedMode };
    }

    const tried = [];
    const modesToTry = requestedMode === 'provider'
      ? ['provider', 'client']
      : ['client', 'provider'];

    for (let index = 0; index < modesToTry.length; index += 1) {
      const mode = modesToTry[index];
      const res = await _fetchProfileForMode(mode, force);
      tried.push(res);

      if (res.ok && res.data) {
        if (mode !== requestedMode) setActiveAccountMode(mode);
        return { ok: true, status: res.status, profile: res.data, mode, recovered: mode !== requestedMode };
      }

      const shouldTryAlternate = index === 0 && (res.status === 401 || res.status === 403 || res.status === 404);
      if (!shouldTryAlternate) {
        return { ok: false, status: res.status || 0, profile: null, mode: requestedMode, responses: tried };
      }
    }

    const finalStatus = tried.length ? (tried[tried.length - 1].status || 0) : 0;
    return { ok: false, status: finalStatus, profile: null, mode: requestedMode, responses: tried };
  }

  /** Fetch current user profile (cached per active account mode) */
  let _profileCache = Object.create(null);
  async function getProfile(force, modeOverride) {
    const resolved = await resolveProfile(force, modeOverride);
    return resolved.ok ? resolved.profile : null;
  }

  _syncStoredAuth();
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', hydrateProviderRequestBlocks, { once: true });
  } else {
    hydrateProviderRequestBlocks();
  }

  return {
    isLoggedIn, getAccessToken, getRefreshToken, getUserId, getRoleState,
    isProviderAccount, isProviderModeActive, isServiceRequestBlockedForCurrentMode,
    needsCompletion,
    saveTokens, saveRoleState, logout, clearProfileCache, refreshAccessToken, requireLogin,
    switchToClientMode, renderProviderRequestBlock, ensureServiceRequestAccess,
    getActiveAccountMode, setActiveAccountMode, resolveProfile, getProfile,
  };
})();
