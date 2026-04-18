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
    return !!(getAccessToken() || getRefreshToken());
  }

  function getAccessToken() {
    return _readAuthValue(KEY_ACCESS);
  }

  function getRefreshToken() {
    return _readAuthValue(KEY_REFRESH);
  }

  function getUserId() {
    return _readAuthValue(KEY_USER_ID);
  }

  function getRoleState() {
    return _readAuthValue(KEY_ROLE) || 'guest';
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

  function _activeAccountMode() {
    try {
      const mode = String(window.sessionStorage.getItem('nw_account_mode') || '').trim().toLowerCase();
      return mode === 'provider' ? 'provider' : 'client';
    } catch {
      return 'client';
    }
  }

  function _normalizeProfileMode(modeOverride) {
    const normalized = String(modeOverride || '').trim().toLowerCase();
    if (normalized === 'provider' || normalized === 'client') return normalized;
    return _activeAccountMode();
  }

  /** Fetch current user profile (cached per active account mode) */
  let _profileCache = Object.create(null);
  async function getProfile(force, modeOverride) {
    const mode = _normalizeProfileMode(modeOverride);
    if (_profileCache[mode] && !force) return _profileCache[mode];
    if (!isLoggedIn()) return null;
    const res = await ApiClient.get('/api/accounts/me/?mode=' + mode);
    if (res.ok && res.data) {
      _profileCache[mode] = res.data;
      return res.data;
    }
    return null;
  }

  _syncStoredAuth();

  return {
    isLoggedIn, getAccessToken, getRefreshToken, getUserId, getRoleState,
    needsCompletion,
    saveTokens, saveRoleState, logout, clearProfileCache, refreshAccessToken, requireLogin, getProfile,
  };
})();
