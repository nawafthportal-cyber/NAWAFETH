/* ===================================================================
   myQrPage.js — Build user's Nawafeth profile QR from API data.
   =================================================================== */
'use strict';

const MyQrPage = (() => {
  function init() {
    const authGate = document.getElementById('qr-auth-gate');
    const content = document.getElementById('qr-content');

    if (!Auth.isLoggedIn()) {
      if (authGate) authGate.classList.remove('hidden');
      if (content) content.classList.add('hidden');
      return;
    }

    if (authGate) authGate.classList.add('hidden');
    if (content) content.classList.remove('hidden');

    _loadQrData();
  }

  async function _loadQrData() {
    try {
      if (!window.NwProfileQr || typeof window.NwProfileQr.loadCurrent !== 'function') {
        throw new Error('تعذر تهيئة QR');
      }

      const current = await window.NwProfileQr.loadCurrent();
      const qr = current.qr;
      const titleEl = document.getElementById('qr-title');
      const textEl = document.getElementById('qr-link-text');
      const imgEl = document.getElementById('my-qr-image');
      const openEl = document.getElementById('open-qr-link');
      const copyBtn = document.getElementById('copy-qr-link');

      if (titleEl) titleEl.textContent = qr.title;
      if (textEl) textEl.textContent = qr.targetUrl;
      if (imgEl) imgEl.src = qr.imageUrl;
      if (openEl) openEl.href = qr.targetUrl;

      if (copyBtn) {
        copyBtn.addEventListener('click', async () => {
          try {
            await navigator.clipboard.writeText(qr.targetUrl);
            _showSuccess('تم نسخ الرابط');
          } catch (_) {
            _showError('تعذر نسخ الرابط');
          }
        });
      }
    } catch (error) {
      _showError(error && error.message ? error.message : 'تعذر تحميل بيانات QR');
    }
  }

  function _showSuccess(msg) {
    const success = document.getElementById('qr-success');
    const error = document.getElementById('qr-error');
    if (error) error.classList.add('hidden');
    if (!success) return;
    success.textContent = msg;
    success.classList.remove('hidden');
  }

  function _showError(msg) {
    const success = document.getElementById('qr-success');
    const error = document.getElementById('qr-error');
    if (success) success.classList.add('hidden');
    if (!error) return;
    error.textContent = msg;
    error.classList.remove('hidden');
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  return { init };
})();
