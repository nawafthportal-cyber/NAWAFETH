/* ===================================================================
   myQrPage.js — Build user's Nawafeth profile QR from API data.
   =================================================================== */
'use strict';

const MyQrPage = (() => {
  let _qrData = null;
  let _eventsBound = false;
  let _toastTimer = null;

  function init() {
    const authGate = document.getElementById('qr-auth-gate');
    const app = document.getElementById('qr-app');

    if (!Auth.isLoggedIn()) {
      if (authGate) authGate.classList.remove('hidden');
      if (app) app.classList.add('hidden');
      return;
    }

    if (authGate) authGate.classList.add('hidden');
    if (app) app.classList.remove('hidden');

    _bindEvents();
    _loadQrData();
  }

  function _bindEvents() {
    if (_eventsBound) return;
    _eventsBound = true;

    const retryBtn = document.getElementById('qr-retry');
    const copyBtn = document.getElementById('copy-qr-link');
    const shareBtn = document.getElementById('share-qr-link');
    const openBtn = document.getElementById('open-qr-link');

    if (retryBtn) retryBtn.addEventListener('click', () => _loadQrData());
    if (copyBtn) copyBtn.addEventListener('click', () => _copyLink());
    if (shareBtn) shareBtn.addEventListener('click', () => _shareLink());
    if (openBtn) {
      openBtn.addEventListener('click', (event) => {
        if (!_qrData || !_qrData.targetUrl) {
          event.preventDefault();
          _showToast('الرابط غير متاح حاليًا', 'error');
        }
      });
    }
  }

  async function _loadQrData() {
    _setLoadingState(true);
    _setErrorState('');

    try {
      if (!window.NwProfileQr || typeof window.NwProfileQr.loadCurrent !== 'function') {
        throw new Error('تعذر تهيئة QR');
      }

      const current = await window.NwProfileQr.loadCurrent();
      const qr = current && current.qr ? current.qr : null;
      if (!qr || !qr.targetUrl) {
        throw new Error('تعذر إنشاء بيانات QR');
      }

      _qrData = qr;

      const titleEl = document.getElementById('qr-title');
      const subtitleEl = document.getElementById('qr-subtitle');
      const textEl = document.getElementById('qr-link-text');
      const imgEl = document.getElementById('my-qr-image');
      const fallbackEl = document.getElementById('my-qr-fallback');
      const openEl = document.getElementById('open-qr-link');

      if (titleEl) titleEl.textContent = qr.title;
      if (subtitleEl) subtitleEl.textContent = _subtitleFromCurrent(current);
      if (textEl) textEl.textContent = qr.targetUrl;
      if (openEl) openEl.href = qr.targetUrl;

      if (imgEl) {
        imgEl.onload = () => {
          if (fallbackEl) fallbackEl.classList.add('hidden');
          imgEl.classList.remove('hidden');
        };
        imgEl.onerror = () => {
          imgEl.classList.add('hidden');
          if (fallbackEl) fallbackEl.classList.remove('hidden');
        };
        imgEl.classList.remove('hidden');
        if (fallbackEl) fallbackEl.classList.add('hidden');
        imgEl.src = qr.imageUrl;
      }

      _setLoadingState(false);
      _setContentVisible(true);
    } catch (error) {
      _qrData = null;
      _setLoadingState(false);
      _setErrorState(error && error.message ? error.message : 'تعذر تحميل بيانات QR');
    }
  }

  async function _copyLink() {
    if (!_qrData || !_qrData.targetUrl) {
      _showToast('الرابط غير متاح حاليًا', 'error');
      return;
    }
    try {
      await navigator.clipboard.writeText(_qrData.targetUrl);
      _showToast('تم نسخ الرابط', 'success');
    } catch (_) {
      _showToast('تعذر نسخ الرابط', 'error');
    }
  }

  async function _shareLink() {
    if (!_qrData || !_qrData.targetUrl) {
      _showToast('الرابط غير متاح حاليًا', 'error');
      return;
    }
    const sharePayload = {
      title: _qrData.title || 'QR نافذتي',
      text: _qrData.targetUrl,
      url: _qrData.targetUrl,
    };

    if (navigator.share) {
      try {
        await navigator.share(sharePayload);
        return;
      } catch (_) {
        // fallback to copy
      }
    }
    await _copyLink();
  }

  function _subtitleFromCurrent(current) {
    const provider = current && current.providerProfile ? current.providerProfile : null;
    const me = current && current.me ? current.me : null;
    const subtitle = _pickFirstText([
      provider && provider.displayName,
      provider && provider.display_name,
      provider && provider.businessName,
      provider && provider.business_name,
      provider && provider.name,
      me && me.displayName,
      me && me.display_name,
      me && me.fullName,
      me && me.full_name,
      me && me.name,
      me && me.username,
    ]);
    return subtitle || 'حسابك في نوافذ';
  }

  function _pickFirstText(values) {
    if (!Array.isArray(values)) return '';
    for (const value of values) {
      const text = String(value || '').trim();
      if (text) return text;
    }
    return '';
  }

  function _setLoadingState(loading) {
    const loadingEl = document.getElementById('qr-loading');
    const card = document.getElementById('qr-card');
    const error = document.getElementById('qr-error-state');
    if (loadingEl) loadingEl.classList.toggle('hidden', !loading);
    if (card && loading) card.classList.add('hidden');
    if (error && loading) error.classList.add('hidden');
  }

  function _setContentVisible(visible) {
    const card = document.getElementById('qr-card');
    const error = document.getElementById('qr-error-state');
    if (card) card.classList.toggle('hidden', !visible);
    if (error && visible) error.classList.add('hidden');
  }

  function _setErrorState(message) {
    const card = document.getElementById('qr-card');
    const error = document.getElementById('qr-error-state');
    const messageEl = document.getElementById('qr-error-message');
    if (!error || !messageEl) return;
    if (!message) {
      error.classList.add('hidden');
      messageEl.textContent = '';
      return;
    }
    if (card) card.classList.add('hidden');
    messageEl.textContent = message;
    error.classList.remove('hidden');
  }

  function _showToast(message, type) {
    if (!message) return;
    const existing = document.getElementById('my-qr-toast');
    if (existing) existing.remove();

    const toast = UI.el('div', {
      id: 'my-qr-toast',
      className: 'my-qr-toast' + (type ? (' ' + type) : ''),
      textContent: message,
    });

    document.body.appendChild(toast);
    requestAnimationFrame(() => toast.classList.add('show'));
    window.clearTimeout(_toastTimer);
    _toastTimer = window.setTimeout(() => {
      toast.classList.remove('show');
      window.setTimeout(() => {
        if (toast.parentNode) toast.remove();
      }, 180);
    }, 2200);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  return { init };
})();
