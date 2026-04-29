/* ===================================================================
   apiClient.js — Minimal fetch wrapper for Nawafeth API
   Matches the same endpoints used by the Flutter mobile app.
   =================================================================== */
'use strict';

const ApiClient = (() => {
  // Base URL — auto-detect from current origin (same Django server)
  const BASE = window.location.origin;
  let _refreshing = null;
  const _getCache = new Map();
  const _getInFlight = new Map();

  const GET_CACHE_RULES = [
    { test: (path) => path === '/api/content/public/', ttl: 5 * 60 * 1000 },
    { test: (path) => path.indexOf('/api/providers/categories/') === 0, ttl: 5 * 60 * 1000 },
    { test: (path) => path.indexOf('/api/accounts/me/') === 0, ttl: 10 * 1000 },
    { test: (path) => path.indexOf('/api/core/unread-badges/') === 0, ttl: 15 * 1000 },
    { test: (path) => path.indexOf('/api/promo/active/') === 0, ttl: 2 * 60 * 1000 },
    { test: (path) => path.indexOf('/api/home/aggregate/') === 0, ttl: 30 * 1000 },
  ];
  const SENSITIVE_GET_RULES = [
    (path) => path.indexOf('/api/accounts/me/') === 0,
    (path) => path.indexOf('/api/core/unread-badges/') === 0,
  ];

  function _readStoredValue(key) {
    try {
      const sessionValue = window.sessionStorage ? window.sessionStorage.getItem(key) : null;
      if (sessionValue) return sessionValue;
    } catch (_) {}
    try {
      return window.localStorage ? window.localStorage.getItem(key) : null;
    } catch (_) {
      return null;
    }
  }

  function _writeStoredValue(key, value) {
    if (value === null || value === undefined || value === '') return;
    try {
      if (window.sessionStorage) window.sessionStorage.setItem(key, String(value));
    } catch (_) {}
    try {
      if (window.localStorage) window.localStorage.setItem(key, String(value));
    } catch (_) {}
  }

  function _removeStoredValue(key) {
    try {
      if (window.sessionStorage) window.sessionStorage.removeItem(key);
    } catch (_) {}
    try {
      if (window.localStorage) window.localStorage.removeItem(key);
    } catch (_) {}
  }

  /**
   * Get stored JWT access token (if user is authenticated).
   * Returns null for anonymous browsing (home page allows AllowAny).
   */
  function _getToken() {
    if (typeof Auth !== 'undefined' && Auth && typeof Auth.getAccessToken === 'function') {
      return Auth.getAccessToken();
    }
    return _readStoredValue('nw_access_token');
  }

  function _getRefreshToken() {
    if (typeof Auth !== 'undefined' && Auth && typeof Auth.getRefreshToken === 'function') {
      return Auth.getRefreshToken();
    }
    return _readStoredValue('nw_refresh_token');
  }

  function _getActiveAccountMode() {
    try {
      if (typeof Auth !== 'undefined' && Auth && typeof Auth.getActiveAccountMode === 'function') {
        const mode = String(Auth.getActiveAccountMode() || '').trim().toLowerCase();
        return mode === 'provider' ? 'provider' : 'client';
      }
    } catch (_) {}
    const storedMode = String(_readStoredValue('nw_account_mode') || '').trim().toLowerCase();
    return storedMode === 'provider' ? 'provider' : 'client';
  }

  function _clearStoredTokens() {
    if (typeof Auth !== 'undefined' && Auth && typeof Auth.logout === 'function') {
      try {
        Auth.logout();
        return;
      } catch (_) {}
    }
    _removeStoredValue('nw_access_token');
    _removeStoredValue('nw_refresh_token');
    _removeStoredValue('nw_user_id');
    _removeStoredValue('nw_role_state');
  }

  function _getCsrfToken() {
    try {
      const match = document.cookie.match(/(?:^|; )csrftoken=([^;]+)/);
      if (match && match[1]) return decodeURIComponent(match[1]);
    } catch (_) {}
    try {
      const input = document.querySelector('input[name="csrfmiddlewaretoken"]');
      return input && input.value ? String(input.value) : null;
    } catch (_) {
      return null;
    }
  }

  function _isUnsafeMethod(method) {
    const normalized = String(method || 'GET').trim().toUpperCase();
    return !['GET', 'HEAD', 'OPTIONS', 'TRACE'].includes(normalized);
  }

  function _isRefreshPath(path) {
    return String(path || '').indexOf('/api/accounts/token/refresh/') !== -1;
  }

  function _tokenExpiresSoon(token, skewSeconds) {
    try {
      const parts = String(token || '').split('.');
      if (parts.length < 2) return false;
      const payload = JSON.parse(atob(parts[1].replace(/-/g, '+').replace(/_/g, '/')));
      const exp = Number(payload && payload.exp);
      if (!Number.isFinite(exp)) return false;
      return (exp * 1000) <= (Date.now() + Math.max(10, Number(skewSeconds) || 60) * 1000);
    } catch (_) {
      return false;
    }
  }

  async function _getFreshTokenIfNeeded(token, path) {
    if (!token || _isRefreshPath(path) || !_tokenExpiresSoon(token, 75)) return token;
    const refreshed = await refreshAccessToken();
    return _getToken() || (refreshed && refreshed.ok ? token : '');
  }

  function _cacheRuleFor(path) {
    const cleanPath = String(path || '').split('#')[0];
    return GET_CACHE_RULES.find((rule) => rule.test(cleanPath)) || null;
  }

  function _isSensitiveGetPath(path) {
    const cleanPath = String(path || '').split('#')[0];
    return SENSITIVE_GET_RULES.some((test) => test(cleanPath));
  }

  function _cacheIdentity() {
    const mode = _getActiveAccountMode();
    let userId = '0';
    try {
      if (typeof Auth !== 'undefined' && Auth && typeof Auth.getUserId === 'function') {
        userId = String(Auth.getUserId() || '0').trim() || '0';
      }
    } catch (_) {}
    return 'user:' + userId + ':mode:' + mode;
  }

  function _cacheKeyFor(path) {
    const cleanPath = String(path || '').split('#')[0];
    if (!_isSensitiveGetPath(cleanPath)) return cleanPath;
    return cleanPath + '::' + _cacheIdentity();
  }

  async function _tryRefresh() {
    const refresh = _getRefreshToken();
    if (!refresh) return { ok: false, terminal: true };
    try {
      const res = await fetch(BASE + '/api/accounts/token/refresh/', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-Account-Mode': _getActiveAccountMode(),
        },
        body: JSON.stringify({ refresh }),
        credentials: 'same-origin',
      });
      if (res.ok) {
        const d = await res.json();
        if (d && d.access) {
          if (typeof Auth !== 'undefined' && Auth && typeof Auth.saveTokens === 'function') {
            Auth.saveTokens({ access: d.access });
          } else {
            _writeStoredValue('nw_access_token', d.access);
          }
          return { ok: true, terminal: false };
        }
      }
      if (res.status === 400 || res.status === 401) {
        _clearStoredTokens();
        return { ok: false, terminal: true };
      }
    } catch(_) { /* transient network/server failure */ }
    return { ok: false, terminal: false };
  }

  async function refreshAccessToken() {
    if (!_refreshing) {
      _refreshing = _tryRefresh().finally(() => { _refreshing = null; });
    }
    return _refreshing;
  }

  async function _parseResponse(res) {
    const data = res.headers.get('content-type')?.includes('json')
      ? await res.json()
      : null;
    return { ok: res.ok, status: res.status, data };
  }

  /**
   * Core fetch helper with timeout support and automatic 401 retry.
   * On 401: tries to refresh the JWT token and retries the request.
   * If refresh fails, retries once without auth header (for AllowAny endpoints).
   * @param {string} path  — API path starting with /
   * @param {object} opts  — { method, body, timeout, _retried }
   * @returns {Promise<{ok:boolean, status:number, data:*}>}
   */
  async function request(path, opts = {}) {
    const url = BASE + path;
    const headers = { 'Accept': 'application/json' };
    let token = _getToken();
    let shouldAttachAuth = Boolean(token) && !opts.omitAuth && !_isRefreshPath(path);
    if (shouldAttachAuth && !opts._refreshChecked) {
      token = await _getFreshTokenIfNeeded(token, path);
      shouldAttachAuth = Boolean(token) && !opts.omitAuth && !_isRefreshPath(path);
    }
    if (shouldAttachAuth) headers['Authorization'] = 'Bearer ' + token;
    headers['X-Account-Mode'] = _getActiveAccountMode();

    const isFormData = opts.formData === true || (opts.body instanceof FormData);
    // Only set Content-Type for non-FormData bodies (browser sets multipart boundary automatically)
    if (opts.body && !isFormData) headers['Content-Type'] = 'application/json';
    if (_isUnsafeMethod(opts.method || 'GET')) {
      const csrfToken = _getCsrfToken();
      if (csrfToken) headers['X-CSRFToken'] = csrfToken;
    }

    const controller = new AbortController();
    const timeoutId = opts.timeout
      ? setTimeout(() => controller.abort(), opts.timeout)
      : null;

    let body = undefined;
    if (opts.body) {
      body = isFormData ? opts.body : (typeof opts.body === 'string' ? opts.body : JSON.stringify(opts.body));
    }

    try {
      const res = await fetch(url, {
        method: opts.method || 'GET',
        headers,
        body,
        signal: controller.signal,
        credentials: 'same-origin',
      });
      if (timeoutId) clearTimeout(timeoutId);

      // Single-flight refresh with one controlled retry.
      if (res.status === 401 && !opts._retried && shouldAttachAuth) {
        const refreshResult = await refreshAccessToken();
        if (refreshResult.ok) {
          return request(path, Object.assign({}, opts, { _retried: true, _refreshChecked: true }));
        }
        // Public endpoints must still work even when stale credentials exist.
        // Retry once without Authorization after any refresh failure.
        return request(path, Object.assign({}, opts, { _retried: true, _refreshChecked: true, omitAuth: true }));
      }

      return _parseResponse(res);
    } catch (err) {
      if (timeoutId) clearTimeout(timeoutId);
      return { ok: false, status: 0, data: null, error: err.message };
    }
  }

  /**
   * GET helper.
   */
  function get(path, timeout, options) {
    const rule = _cacheRuleFor(path);
    const forceRefresh = !!(options && options.forceRefresh);
    if (!rule || forceRefresh) return request(path, { timeout: timeout || 12000 });

    const cacheKey = _cacheKeyFor(path);
    const cached = _getCache.get(cacheKey);
    if (cached && cached.expiresAt > Date.now()) {
      return Promise.resolve(cached.value);
    }

    const pending = _getInFlight.get(cacheKey);
    if (pending) return pending;

    const promise = request(path, { timeout: timeout || 12000 })
      .then((res) => {
        if (res && res.ok) {
          _getCache.set(cacheKey, {
            value: res,
            expiresAt: Date.now() + rule.ttl,
          });
        }
        return res;
      })
      .finally(() => {
        _getInFlight.delete(cacheKey);
      });
    _getInFlight.set(cacheKey, promise);
    return promise;
  }

  /**
   * Build full media URL for images/files.
   * @param {string|null} path
   * @returns {string|null}
   */
  function mediaUrl(path) {
    if (!path) return null;
    if (path.startsWith('http')) return path;
    return BASE + (path.startsWith('/') ? '' : '/') + path;
  }

  /** POST helper (JSON body). */
  function post(path, body) {
    return request(path, { method: 'POST', body }).then(r => r.data);
  }

  /** PATCH helper (JSON body). */
  function patch(path, body) {
    return request(path, { method: 'PATCH', body }).then(r => r.data);
  }

  /** DELETE helper. */
  function del(path) {
    return request(path, { method: 'DELETE' });
  }

  /** Upload helper (FormData / multipart). */
  function upload(path, formData) {
    return request(path, { method: 'POST', body: formData, formData: true }).then(r => r.data);
  }

  /* Original ApiClient — get() returns { ok, status, data } for backward compat */
    return { get, request, mediaUrl, refreshAccessToken, BASE };
})();

  window.ApiClient = ApiClient;

/**
 * NwApiClient — convenience layer used by new pages.
 * get() returns the parsed data directly (not the wrapper).
 */
window.NwApiClient = {
  get:      function(p) { return ApiClient.get(p).then(function(r){ return r.data; }); },
  post:     function(p, b) { return ApiClient.request(p, { method: 'POST', body: b }).then(function(r){ return r.data; }); },
  patch:    function(p, b) { return ApiClient.request(p, { method: 'PATCH', body: b }).then(function(r){ return r.data; }); },
  del:      function(p) { return ApiClient.request(p, { method: 'DELETE' }); },
  upload:   function(p, fd) { return ApiClient.request(p, { method: 'POST', body: fd, formData: true }).then(function(r){ return r.data; }); },
  mediaUrl: ApiClient.mediaUrl,
  BASE:     ApiClient.BASE
};
