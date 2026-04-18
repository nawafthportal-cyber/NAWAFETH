'use strict';

window.NwAnalytics = (() => {
  const sentKeys = new Set();
  const endpoint = window.location.origin + '/api/analytics/events/';

  function _authHeaders() {
    const headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    try {
      const token = (window.Auth && typeof window.Auth.getAccessToken === 'function')
        ? window.Auth.getAccessToken()
        : ((window.sessionStorage && window.sessionStorage.getItem('nw_access_token'))
          || (window.localStorage && window.localStorage.getItem('nw_access_token')));
      if (token) headers.Authorization = 'Bearer ' + token;
    } catch (_) {}
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

    return fetch(endpoint, {
      method: 'POST',
      headers: _authHeaders(),
      body: JSON.stringify(body),
      keepalive: true,
    }).catch(() => null);
  }

  function trackOnce(eventName, payload = {}, dedupeKey = '') {
    return track(eventName, payload, { dedupeKey });
  }

  return { track, trackOnce };
})();
