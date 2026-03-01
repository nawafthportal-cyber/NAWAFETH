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
    if (opts.body) headers['Content-Type'] = 'application/json';

    const controller = new AbortController();
    const timeoutId = opts.timeout
      ? setTimeout(() => controller.abort(), opts.timeout)
      : null;

    try {
      const res = await fetch(url, {
        method: opts.method || 'GET',
        headers,
        body: opts.body ? JSON.stringify(opts.body) : undefined,
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

  return { get, request, mediaUrl, BASE };
})();
