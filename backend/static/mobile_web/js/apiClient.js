/* ===================================================================
   apiClient.js — Minimal fetch wrapper for Nawafeth API
   Matches the same endpoints used by the Flutter mobile app.
   =================================================================== */
'use strict';

const ApiClient = (() => {
  // Base URL — auto-detect from current origin (same Django server)
  const BASE = window.location.origin;
  let _refreshing = null;

  /**
   * Get stored JWT access token (if user is authenticated).
   * Returns null for anonymous browsing (home page allows AllowAny).
   */
  function _getToken() {
    try { return sessionStorage.getItem('nw_access_token'); } catch(_) { return null; }
  }

  function _clearStoredTokens() {
    if (typeof Auth !== 'undefined' && Auth && typeof Auth.logout === 'function') {
      try {
        Auth.logout();
        return;
      } catch (_) {}
    }
    try {
      sessionStorage.removeItem('nw_access_token');
      sessionStorage.removeItem('nw_refresh_token');
      sessionStorage.removeItem('nw_user_id');
      sessionStorage.removeItem('nw_role_state');
    } catch(_) {}
  }

  function _isRefreshPath(path) {
    return String(path || '').indexOf('/api/accounts/token/refresh/') !== -1;
  }

  async function _tryRefresh() {
    let refresh;
    try { refresh = sessionStorage.getItem('nw_refresh_token'); } catch(_) { return { ok: false, terminal: false }; }
    if (!refresh) return { ok: false, terminal: false };
    try {
      const res = await fetch(BASE + '/api/accounts/token/refresh/', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
        body: JSON.stringify({ refresh }),
      });
      if (res.ok) {
        const d = await res.json();
        if (d && d.access) {
          try { sessionStorage.setItem('nw_access_token', d.access); } catch(_) {}
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
    const token = _getToken();
    const shouldAttachAuth = Boolean(token) && !opts.omitAuth && !_isRefreshPath(path);
    if (shouldAttachAuth) headers['Authorization'] = 'Bearer ' + token;

    const isFormData = opts.formData === true || (opts.body instanceof FormData);
    // Only set Content-Type for non-FormData bodies (browser sets multipart boundary automatically)
    if (opts.body && !isFormData) headers['Content-Type'] = 'application/json';

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
      });
      if (timeoutId) clearTimeout(timeoutId);

      // Single-flight refresh with one controlled retry.
      if (res.status === 401 && !opts._retried && shouldAttachAuth) {
        const refreshResult = await refreshAccessToken();
        if (refreshResult.ok) {
          return request(path, Object.assign({}, opts, { _retried: true }));
        }
        if (refreshResult.terminal) {
          return request(path, Object.assign({}, opts, { _retried: true, omitAuth: true }));
        }
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
  function get(path, timeout) {
    return request(path, { timeout: timeout || 12000 });
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
