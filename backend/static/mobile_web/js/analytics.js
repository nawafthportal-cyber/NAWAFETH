'use strict';

window.NwAnalytics = (() => {
  const sentKeys = new Set();
  const endpoint = window.location.origin + '/api/analytics/events/';
  const buffer = [];
  const MAX_BATCH_SIZE = 20;
  const FLUSH_INTERVAL_MS = 6000;
  let flushTimer = null;
  let flushInFlight = null;

  function _restoreBatch(batch) {
    if (!Array.isArray(batch) || !batch.length) return;
    buffer.unshift.apply(buffer, batch);
  }

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

  function _scheduleFlush() {
    if (flushTimer) return;
    flushTimer = window.setTimeout(() => {
      flushTimer = null;
      flush();
    }, FLUSH_INTERVAL_MS);
  }

  function flush() {
    if (flushInFlight) return flushInFlight;
    if (flushTimer) {
      clearTimeout(flushTimer);
      flushTimer = null;
    }
    if (!buffer.length) return Promise.resolve({ skipped: true, empty: true });

    const batch = buffer.splice(0, buffer.length);
    flushInFlight = _authHeaders().then((headers) => fetch(endpoint, {
      method: 'POST',
      headers,
      body: JSON.stringify({ events: batch }),
      keepalive: true,
    })).then((response) => {
      if (!response || (response.status >= 500 && response.status <= 599)) {
        _restoreBatch(batch);
      }
      return response;
    }).catch(() => {
      _restoreBatch(batch);
      return null;
    }).finally(() => {
      flushInFlight = null;
    });
    return flushInFlight;
  }

  function _flushWithBeacon() {
    if (!buffer.length) return;
    const batch = buffer.splice(0, buffer.length);
    if (!navigator.sendBeacon) {
      _restoreBatch(batch);
      void flush();
      return;
    }
    try {
      const payload = JSON.stringify({ events: batch });
      const blob = new Blob([payload], { type: 'application/json; charset=UTF-8' });
      const queued = navigator.sendBeacon(endpoint, blob);
      if (!queued) {
        _restoreBatch(batch);
      }
    } catch (_) {
      _restoreBatch(batch);
    }
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

    buffer.push(body);
    _scheduleFlush();
    if (buffer.length >= MAX_BATCH_SIZE) {
      return flush();
    }
    return Promise.resolve({ accepted: true, buffered: true });
  }

  function trackOnce(eventName, payload = {}, dedupeKey = '') {
    return track(eventName, payload, { dedupeKey });
  }

  window.addEventListener('pagehide', _flushWithBeacon, { capture: true });
  window.addEventListener('beforeunload', _flushWithBeacon, { capture: true });
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'hidden') {
      _flushWithBeacon();
    }
  });

  return { track, trackOnce, flush };
})();
