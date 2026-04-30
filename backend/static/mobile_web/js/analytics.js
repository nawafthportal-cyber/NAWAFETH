'use strict';

window.NwAnalytics = (() => {
  const SENSITIVE_KEY_PATTERN = /token|auth|password|secret|email|phone|jwt|authorization|cookie|session|name/i;
  const sentKeys = new Set();
  const endpoint = window.location.origin + '/api/analytics/events/';
  const buffer = [];
  const MAX_BATCH_SIZE = 20;
  const MAX_BUFFER_SIZE = 100;
  const FLUSH_INTERVAL_MS = 6000;
  const AUTH_FAILURE_BACKOFF_MS = 5 * 60 * 1000;
  let flushTimer = null;
  let flushInFlight = null;
  let authBlockedUntil = 0;
  let lastAuthFailureStatus = 0;

  function _restoreBatch(batch) {
    if (!Array.isArray(batch) || !batch.length) return;
    buffer.unshift.apply(buffer, batch);
  }

  function _trimBuffer() {
    while (buffer.length > MAX_BUFFER_SIZE) {
      buffer.shift();
    }
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

  function _sanitizeValue(value) {
    if (Array.isArray(value)) {
      return value.slice(0, 20).map(_sanitizeValue);
    }
    if (!value || typeof value !== 'object') {
      return value;
    }
    const sanitized = {};
    Object.keys(value).forEach((key) => {
      if (SENSITIVE_KEY_PATTERN.test(String(key || ''))) {
        return;
      }
      sanitized[key] = _sanitizeValue(value[key]);
    });
    return sanitized;
  }

  function _canAttemptSend() {
    return !authBlockedUntil || Date.now() >= authBlockedUntil;
  }

  async function _authHeaders() {
    const headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    const token = await _freshAccessToken();
    if (token) headers.Authorization = 'Bearer ' + token;
    return { headers, token };
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
    if (!_canAttemptSend()) {
      return Promise.resolve({ skipped: true, reason: 'auth_blocked' });
    }

    const batch = buffer.splice(0, buffer.length);
    flushInFlight = _authHeaders().then(({ headers, token }) => {
      if (!token) {
        authBlockedUntil = Date.now() + AUTH_FAILURE_BACKOFF_MS;
        lastAuthFailureStatus = 401;
        return { skipped: true, reason: 'auth_missing' };
      }
      return fetch(endpoint, {
        method: 'POST',
        headers,
        body: JSON.stringify({ events: batch }),
        keepalive: true,
      });
    }).then((response) => {
      if (response && response.skipped) {
        return response;
      }
      if (response && (response.status === 401 || response.status === 403)) {
        authBlockedUntil = Date.now() + AUTH_FAILURE_BACKOFF_MS;
        lastAuthFailureStatus = response.status;
        return response;
      }
      authBlockedUntil = 0;
      lastAuthFailureStatus = 0;
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
    if (!_canAttemptSend()) return;
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
    if (!_canAttemptSend()) {
      return Promise.resolve({ skipped: true, reason: 'auth_blocked' });
    }
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
      payload: payload.payload && typeof payload.payload === 'object' ? _sanitizeValue(payload.payload) : {},
    };

    buffer.push(body);
    _trimBuffer();
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

  const api = { track, trackOnce, flush };
  if (window.__NW_ENABLE_TEST_HOOKS__) {
    window.__NW_TEST_HOOKS__ = window.__NW_TEST_HOOKS__ || {};
    window.__NW_TEST_HOOKS__.analytics = {
      api,
      debugState() {
        return {
          bufferLength: buffer.length,
          authBlockedUntil,
          lastAuthFailureStatus,
          flushInFlight: !!flushInFlight,
        };
      },
    };
  }
  return api;
})();
