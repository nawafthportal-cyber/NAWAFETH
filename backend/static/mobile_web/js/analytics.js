'use strict';

window.NwAnalytics = (() => {
  const sentKeys = new Set();
  const endpoint = window.location.origin + '/api/analytics/events/';

  function _tokenExpiresSoon(token) {
    try {
      const parts = String(token || '').split('.');
      if (parts.length < 2) return false;
      const payload = JSON.parse(atob(parts[1].replace(/-/g, '+').replace(/_/g, '/')));
      const exp = Number(payload && payload.exp);
      return Number.isFinite(exp) && (exp * 1000) <= (Date.now() + 75000);
    } catch (_) {
      return false;
    }
  }

  async function _freshAccessToken() {
    let token = '';
    try {
      token = (window.Auth && typeof window.Auth.getAccessToken === 'function')
        ? window.Auth.getAccessToken()
        : ((window.sessionStorage && window.sessionStorage.getItem('nw_access_token'))
          || (window.localStorage && window.localStorage.getItem('nw_access_token')));
    } catch (_) {}
    if (token && _tokenExpiresSoon(token) && window.Auth && typeof window.Auth.refreshAccessToken === 'function') {
      try {
        const refreshed = await window.Auth.refreshAccessToken();
        if (refreshed && typeof window.Auth.getAccessToken === 'function') token = window.Auth.getAccessToken();
      } catch (_) {}
    }
    return token || '';
  }

  async function _authHeaders() {
    const headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    const token = await _freshAccessToken();
    if (token) headers.Authorization = 'Bearer ' + token;
    return headers;
  }

  function track(eventName, payload = {}, options = {}) {
    const dedupeKey = String(options.dedupeKey || payload.dedupe_key || '').trim();
    if (dedupeKey) {
      if (sentKeys.has(dedupeKey)) {
        return Promise.resolve({ skipped: true, deduped: true });
      }
      sentKeys.add(dedupeKey);
    }

    const body = {
      event_name: eventName,
      channel: 'mobile_web',
      surface: String(payload.surface || '').trim(),
      source_app: String(payload.source_app || '').trim(),
      object_type: String(payload.object_type || '').trim(),
      object_id: String(payload.object_id || '').trim(),
      session_id: String(payload.session_id || '').trim(),
      dedupe_key: dedupeKey,
      payload: payload.payload && typeof payload.payload === 'object' ? payload.payload : {},
    };

    return _authHeaders().then((headers) => fetch(endpoint, {
      method: 'POST',
      headers,
      body: JSON.stringify(body),
      keepalive: true,
    })).catch(() => null);
  }

  function trackOnce(eventName, payload = {}, dedupeKey = '') {
    return track(eventName, payload, { dedupeKey });
  }

  return { track, trackOnce };
})();
