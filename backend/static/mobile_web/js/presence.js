/* Presence heartbeat for mobile-web.
 *
 * Pings POST /api/accounts/heartbeat/ once on load and every 60s while the
 * tab is visible. Backend throttles writes to one per 60s per user, so this
 * is cheap. Skipped entirely for anonymous visitors.
 */
(function () {
  'use strict';
  if (!window.ApiClient) return;

  var INTERVAL_MS = 60 * 1000;
  var timer = null;

  function _hasToken() {
    try {
      if (window.Auth && typeof window.Auth.getAccessToken === 'function') {
        return !!window.Auth.getAccessToken();
      }
    } catch (_) {}
    try {
      var ss = window.sessionStorage && window.sessionStorage.getItem('nw_access_token');
      var ls = window.localStorage && window.localStorage.getItem('nw_access_token');
      return !!(ss || ls);
    } catch (_) { return false; }
  }

  function _ping() {
    if (!_hasToken()) return;
    try {
      ApiClient.post('/api/accounts/heartbeat/', {}).catch(function () { /* ignore */ });
    } catch (_) { /* ignore */ }
  }

  function _start() {
    if (timer) return;
    _ping();
    timer = setInterval(function () {
      if (document.visibilityState === 'visible') _ping();
    }, INTERVAL_MS);
  }

  function _stop() {
    if (timer) { clearInterval(timer); timer = null; }
  }

  document.addEventListener('visibilitychange', function () {
    if (document.visibilityState === 'visible') {
      _ping();
      _start();
    } else {
      _stop();
    }
  });

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', _start);
  } else {
    _start();
  }
})();
