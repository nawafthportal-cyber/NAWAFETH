/* ===================================================================
   loginPage.js — Login phone step
   POST /api/accounts/otp/send/ -> send OTP then redirect to /twofa/
   =================================================================== */
'use strict';

const LoginPage = (() => {
  function init() {
    if (Auth.isLoggedIn()) {
      const next = new URLSearchParams(window.location.search).get('next') || '/';
      window.location.href = next;
      return;
    }

    const phoneInput = document.getElementById('phone-input');
    const btnSend = document.getElementById('btn-send-otp');
    const btnGuest = document.getElementById('btn-guest');

    if (!phoneInput || !btnSend || !btnGuest) return;

    btnSend.addEventListener('click', () => _sendOTP(phoneInput));
    phoneInput.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') _sendOTP(phoneInput);
    });

    btnGuest.addEventListener('click', () => {
      Auth.logout();
      window.location.href = '/';
    });
  }

  function _normalizeDigits(value) {
    return String(value || '').replace(/[^\d]/g, '');
  }

  function _isValidPhone(phone) {
    const digits = _normalizeDigits(phone);
    return (
      /^05\d{8}$/.test(digits) ||
      /^5\d{8}$/.test(digits) ||
      /^9665\d{8}$/.test(digits)
    );
  }

  async function _sendOTP(phoneInput) {
    const rawPhone = phoneInput.value.trim();
    const errEl = document.getElementById('phone-error');

    if (!_isValidPhone(rawPhone)) {
      _showError(errEl, 'أدخل رقم جوال صحيح');
      return;
    }
    _hideError(errEl);
    _setLoading(true);

    const res = await ApiClient.request('/api/accounts/otp/send/', {
      method: 'POST',
      body: { phone: rawPhone },
    });

    _setLoading(false);

    if (!res.ok) {
      const msg = (res.data && (res.data.detail || res.data.error)) || 'فشل إرسال الرمز';
      _showError(errEl, msg);
      return;
    }

    try {
      sessionStorage.setItem('nw_auth_phone', rawPhone);
      if (res.data && res.data.dev_code) {
        sessionStorage.setItem('nw_auth_dev_code', String(res.data.dev_code));
      } else {
        sessionStorage.removeItem('nw_auth_dev_code');
      }
    } catch {}

    const qs = new URLSearchParams(window.location.search);
    const next = qs.get('next') || '/';
    const target = new URL('/twofa/', window.location.origin);
    target.searchParams.set('phone', rawPhone);
    target.searchParams.set('next', next);
    window.location.href = target.toString();
  }

  function _setLoading(loading) {
    const btn = document.getElementById('btn-send-otp');
    const txt = document.getElementById('send-otp-text');
    const spin = document.getElementById('send-otp-spinner');
    if (btn) btn.disabled = loading;
    if (txt) txt.classList.toggle('hidden', loading);
    if (spin) spin.classList.toggle('hidden', !loading);
  }

  function _showError(el, msg) {
    if (!el) return;
    el.textContent = msg;
    el.classList.remove('hidden');
  }

  function _hideError(el) {
    if (!el) return;
    el.textContent = '';
    el.classList.add('hidden');
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  return {};
})();
