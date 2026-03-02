/* ===================================================================
   apiClient.js — Minimal fetch wrapper for Nawafeth API
   Matches the same endpoints used by the Flutter mobile app.
   =================================================================== */
'use strict';

const ApiClient = (() => {
  // Base URL — auto-detect from current origin (same Django server)
  const BASE = window.location.origin;

  /**
   * Get stored JWT access token (if user is authenticated).
   * Returns null for anonymous browsing (home page allows AllowAny).
   */
  function _getToken() {
    try { return sessionStorage.getItem('nw_access_token'); } catch { return null; }
  }

  /**
   * Core fetch helper with timeout support.
   * @param {string} path  — API path starting with /
   * @param {object} opts  — { method, body, timeout }
   * @returns {Promise<{ok:boolean, status:number, data:*}>}
   */
  async function request(path, opts = {}) {
    const url = BASE + path;
    const headers = { 'Accept': 'application/json' };
    const token = _getToken();
    if (token) headers['Authorization'] = 'Bearer ' + token;

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
      const data = res.headers.get('content-type')?.includes('json')
        ? await res.json()
        : null;
      return { ok: res.ok, status: res.status, data };
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
  return { get, request, mediaUrl, BASE };
})();

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
