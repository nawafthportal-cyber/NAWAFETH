/* ===================================================================
   auth.js — Authentication state manager
   Stores JWT tokens in sessionStorage, exposes helper methods.
   =================================================================== */
'use strict';

const Auth = (() => {
  const KEY_ACCESS  = 'nw_access_token';
  const KEY_REFRESH = 'nw_refresh_token';
  const KEY_USER_ID = 'nw_user_id';
  const KEY_ROLE    = 'nw_role_state';

  function isLoggedIn() {
    try { return !!sessionStorage.getItem(KEY_ACCESS); } catch { return false; }
  }

  function getAccessToken() {
    try { return sessionStorage.getItem(KEY_ACCESS); } catch { return null; }
  }

  function getRefreshToken() {
    try { return sessionStorage.getItem(KEY_REFRESH); } catch { return null; }
  }

  function getUserId() {
    try { return sessionStorage.getItem(KEY_USER_ID); } catch { return null; }
  }

  function getRoleState() {
    try { return sessionStorage.getItem(KEY_ROLE) || 'guest'; } catch { return 'guest'; }
  }

  function needsCompletion() {
    const role = String(getRoleState() || '').trim().toLowerCase();
    return role === 'phone_only' || role === 'visitor';
  }

  function saveTokens(data) {
    try {
      if (data.access) sessionStorage.setItem(KEY_ACCESS, data.access);
      if (data.refresh) sessionStorage.setItem(KEY_REFRESH, data.refresh);
      if (data.user_id) sessionStorage.setItem(KEY_USER_ID, String(data.user_id));
      if (data.role_state) sessionStorage.setItem(KEY_ROLE, data.role_state);
    } catch { /* quota */ }
  }

  function logout() {
    try {
      sessionStorage.removeItem(KEY_ACCESS);
      sessionStorage.removeItem(KEY_REFRESH);
      sessionStorage.removeItem(KEY_USER_ID);
      sessionStorage.removeItem(KEY_ROLE);
      _profileCache = null;
    } catch { /* ok */ }
  }

  function clearProfileCache() {
    _profileCache = null;
  }

  /** Try to refresh the access token using the refresh token */
  async function refreshAccessToken() {
    const refresh = getRefreshToken();
    if (!refresh) return false;
    const res = await ApiClient.request('/api/accounts/token/refresh/', {
      method: 'POST',
      body: { refresh },
    });
    if (res.ok && res.data && res.data.access) {
      try { sessionStorage.setItem(KEY_ACCESS, res.data.access); } catch {}
      return true;
    }
    // Refresh token invalid — force logout
    logout();
    return false;
  }

  /** Require login — redirects to /login/ if not authenticated */
  function requireLogin(returnUrl) {
    if (isLoggedIn()) return true;
    const ret = returnUrl || window.location.pathname;
    window.location.href = '/login/?next=' + encodeURIComponent(ret);
    return false;
  }

  /** Fetch current user profile (cached) */
  let _profileCache = null;
  async function getProfile(force) {
    if (_profileCache && !force) return _profileCache;
    if (!isLoggedIn()) return null;
    const res = await ApiClient.get('/api/accounts/me/');
    if (res.ok && res.data) {
      _profileCache = res.data;
      return res.data;
    }
    // Token might be expired — try refresh
    const refreshed = await refreshAccessToken();
    if (refreshed) {
      const res2 = await ApiClient.get('/api/accounts/me/');
      if (res2.ok && res2.data) {
        _profileCache = res2.data;
        return res2.data;
      }
    }
    return null;
  }

  return {
    isLoggedIn, getAccessToken, getRefreshToken, getUserId, getRoleState,
    needsCompletion,
    saveTokens, logout, clearProfileCache, refreshAccessToken, requireLogin, getProfile,
  };
})();
