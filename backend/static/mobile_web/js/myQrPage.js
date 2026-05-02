/* ===================================================================
   myQrPage.js — Build user's Nawafeth profile QR from API data.
   =================================================================== */
'use strict';

const MyQrPage = (() => {
  const COPY = {
    ar: {
      pageTitle: 'نوافــذ — QR نافذتي',
      authTitle: 'سجّل دخولك',
      authDesc: 'لعرض كود نافذتي، سجّل دخولك أولاً',
      authCta: 'تسجيل الدخول',
      retry: 'إعادة المحاولة',
      qrTitle: 'رابط نافذتي',
      qrImageAlt: 'QR نافذتي',
      qrImageFallback: 'تعذر تحميل صورة QR',
      copy: 'نسخ الرابط',
      share: 'مشاركة',
      open: 'فتح الرابط',
      linkUnavailable: 'الرابط غير متاح حاليًا',
      initFailed: 'تعذر تهيئة QR',
      buildFailed: 'تعذر إنشاء بيانات QR',
      loadFailed: 'تعذر تحميل بيانات QR',
      copySuccess: 'تم نسخ الرابط',
      copyFailed: 'تعذر نسخ الرابط',
      subtitleFallback: 'حسابك في نوافذ',
      shareTitle: 'QR نافذتي',
    },
    en: {
      pageTitle: 'Nawafeth — My QR',
      authTitle: 'Sign in',
      authDesc: 'Sign in first to view your Nawafeth QR code.',
      authCta: 'Sign in',
      retry: 'Try again',
      qrTitle: 'My Nawafeth link',
      qrImageAlt: 'My Nawafeth QR',
      qrImageFallback: 'Unable to load the QR image',
      copy: 'Copy link',
      share: 'Share',
      open: 'Open link',
      linkUnavailable: 'The link is not available right now.',
      initFailed: 'Unable to initialize the QR flow.',
      buildFailed: 'Unable to build the QR data.',
      loadFailed: 'Unable to load the QR data.',
      copySuccess: 'Link copied',
      copyFailed: 'Unable to copy the link',
      subtitleFallback: 'Your Nawafeth account',
      shareTitle: 'My Nawafeth QR',
    },
  };

  let _qrData = null;
  let _currentPayload = null;
  let _providerProfileId = null;
  let _eventsBound = false;
  let _toastTimer = null;

  function init() {
    _applyStaticCopy();
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
    window.addEventListener('nawafeth:languagechange', _handleLanguageChange);
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
          _showToast(_copy('linkUnavailable'), 'error');
        }
      });
    }
  }

  async function _loadQrData() {
    _setLoadingState(true);
    _setErrorState('');

    try {
      if (!window.NwProfileQr || typeof window.NwProfileQr.loadCurrent !== 'function') {
        throw new Error(_copy('initFailed'));
      }

      const current = await window.NwProfileQr.loadCurrent();
      const qr = current && current.qr ? current.qr : null;
      if (!qr || !qr.targetUrl) {
        throw new Error(_copy('buildFailed'));
      }

      _currentPayload = current;
      _qrData = qr;
      _providerProfileId = current && current.providerProfile && current.providerProfile.id
        ? current.providerProfile.id
        : null;

      _renderQrCard();

      _setLoadingState(false);
      _setContentVisible(true);
    } catch (error) {
      _qrData = null;
      _currentPayload = null;
      _setLoadingState(false);
      _setErrorState(error && error.message ? error.message : _copy('loadFailed'));
    }
  }

  async function _copyLink() {
    if (!_qrData || !_qrData.targetUrl) {
      _showToast(_copy('linkUnavailable'), 'error');
      return;
    }
    try {
      await navigator.clipboard.writeText(_qrData.targetUrl);
      if (_providerProfileId && window.ApiClient && typeof ApiClient.request === 'function') {
        await ApiClient.request('/api/providers/' + encodeURIComponent(String(_providerProfileId)) + '/share/', {
          method: 'POST',
          body: { content_type: 'profile', channel: 'copy_link' },
        });
      }
      _showToast(_copy('copySuccess'), 'success');
    } catch (_) {
      _showToast(_copy('copyFailed'), 'error');
    }
  }

  async function _shareLink() {
    if (!_qrData || !_qrData.targetUrl) {
      _showToast(_copy('linkUnavailable'), 'error');
      return;
    }
    const sharePayload = {
      title: _qrData.title || _copy('shareTitle'),
      text: _qrData.targetUrl,
      url: _qrData.targetUrl,
    };

    if (navigator.share) {
      try {
        await navigator.share(sharePayload);
        if (_providerProfileId && window.ApiClient && typeof ApiClient.request === 'function') {
          await ApiClient.request('/api/providers/' + encodeURIComponent(String(_providerProfileId)) + '/share/', {
            method: 'POST',
            body: { content_type: 'profile', channel: 'other' },
          });
        }
        return;
      } catch (_) {
        // fallback to copy
      }
    }
    await _copyLink();
  }

  function _looksLikePhone(v) {
    var s = String(v || '').replace(/[\s\-\+\(\)@]/g, '');
    return /^0[0-9]{8,12}$/.test(s) || /^9665[0-9]{8}$/.test(s) || /^5[0-9]{8}$/.test(s);
  }
  function _safeText(v) { var s = _pickFirstText([v]); return (s && !_looksLikePhone(s)) ? s : ''; }

  function _subtitleFromCurrent(current) {
    const provider = current && current.providerProfile ? current.providerProfile : null;
    const me = current && current.me ? current.me : null;
    const subtitle = _pickFirstText([
      _safeText(provider && provider.displayName),
      _safeText(provider && provider.display_name),
      _safeText(provider && provider.businessName),
      _safeText(provider && provider.business_name),
      _safeText(provider && provider.name),
      _safeText(me && me.displayName),
      _safeText(me && me.display_name),
      _safeText(me && me.fullName),
      _safeText(me && me.full_name),
      _safeText(me && me.name),
      _safeText(me && me.username),
    ]);
    return subtitle || _copy('subtitleFallback');
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

  function _currentLang() {
    if (window.NawafethI18n && typeof window.NawafethI18n.getLanguage === 'function') {
      return window.NawafethI18n.getLanguage() === 'en' ? 'en' : 'ar';
    }
    return document.documentElement.lang === 'en' ? 'en' : 'ar';
  }

  function _copy(key) {
    const lang = _currentLang();
    return (COPY[lang] && COPY[lang][key]) || COPY.ar[key] || '';
  }

  function _setText(id, value) {
    const el = document.getElementById(id);
    if (!el) return;
    el.textContent = value;
  }

  function _applyStaticCopy() {
    document.title = _copy('pageTitle');
    _setText('qr-auth-title', _copy('authTitle'));
    _setText('qr-auth-desc', _copy('authDesc'));
    _setText('qr-auth-cta', _copy('authCta'));
    _setText('qr-retry', _copy('retry'));
    _setText('qr-title', _copy('qrTitle'));
    _setText('my-qr-fallback', _copy('qrImageFallback'));
    _setText('copy-qr-link', _copy('copy'));
    _setText('share-qr-link', _copy('share'));
    _setText('open-qr-link', _copy('open'));
    const imgEl = document.getElementById('my-qr-image');
    if (imgEl) imgEl.alt = _copy('qrImageAlt');
  }

  function _renderQrCard() {
    if (!_qrData) return;

    const titleEl = document.getElementById('qr-title');
    const subtitleEl = document.getElementById('qr-subtitle');
    const textEl = document.getElementById('qr-link-text');
    const imgEl = document.getElementById('my-qr-image');
    const fallbackEl = document.getElementById('my-qr-fallback');
    const openEl = document.getElementById('open-qr-link');

    if (titleEl) titleEl.textContent = _qrData.title || _copy('qrTitle');
    if (subtitleEl) subtitleEl.textContent = _subtitleFromCurrent(_currentPayload);
    if (textEl) textEl.textContent = _qrData.targetUrl;
    if (openEl) openEl.href = _qrData.targetUrl;

    if (imgEl) {
      imgEl.alt = _copy('qrImageAlt');
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
      imgEl.src = _qrData.imageUrl;
    }
  }

  function _handleLanguageChange() {
    _applyStaticCopy();
    if (_qrData) {
      _renderQrCard();
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  return { init };
})();
