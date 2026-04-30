// serviceWorkerRegister.js
// Handles Service Worker registration, skipping unsupported environments.
(function (global) {
  'use strict';

  const PRIMARY_SW_PATH = '/service-worker.js';
  const FALLBACK_SW_PATH = '/sw.js';
  const SW_MISSING_STATUSES = new Set([404, 410]);

  function isProbablyWebView() {
    const ua = (global.navigator && global.navigator.userAgent) || '';
    return (
      /wv/.test(ua) ||
      /WebView/i.test(ua) ||
      (global.flutter_inappwebview !== undefined) ||
      (global.ReactNativeWebView !== undefined)
    );
  }

  async function resolveServiceWorkerPath(fetchImpl) {
    if (typeof fetchImpl !== 'function') return PRIMARY_SW_PATH;
    const candidates = [PRIMARY_SW_PATH, FALLBACK_SW_PATH];
    for (let index = 0; index < candidates.length; index += 1) {
      const candidate = candidates[index];
      try {
        const response = await fetchImpl(candidate, {
          method: 'HEAD',
          credentials: 'same-origin',
          cache: 'no-store',
        });
        if (response && response.ok) return candidate;
        if (!response || !SW_MISSING_STATUSES.has(Number(response.status) || 0)) {
          return candidate;
        }
      } catch (_) {
        return PRIMARY_SW_PATH;
      }
    }
    return null;
  }

  async function registerServiceWorker(env = global) {
    const nav = env && env.navigator;
    if (!nav || !nav.serviceWorker || typeof nav.serviceWorker.register !== 'function') {
      return { skipped: true, reason: 'unsupported' };
    }
    if (isProbablyWebView()) {
      return { skipped: true, reason: 'webview' };
    }

    const path = await resolveServiceWorkerPath(env.fetch ? env.fetch.bind(env) : null);
    if (!path) {
      return { skipped: true, reason: 'missing' };
    }

    try {
      await nav.serviceWorker.register(path);
      return { registered: true, path };
    } catch (error) {
      return { skipped: true, reason: 'register_failed', error: error && error.message ? error.message : '' };
    }
  }

  if (global && typeof global.addEventListener === 'function') {
    global.addEventListener('load', () => {
      void registerServiceWorker(global);
    });
  }

  if (global) {
    global.NawafethServiceWorker = { registerServiceWorker, resolveServiceWorkerPath, isProbablyWebView };
    if (global.__NW_ENABLE_TEST_HOOKS__) {
      global.__NW_TEST_HOOKS__ = global.__NW_TEST_HOOKS__ || {};
      global.__NW_TEST_HOOKS__.serviceWorker = global.NawafethServiceWorker;
    }
  }
}(typeof window !== 'undefined' ? window : globalThis));
