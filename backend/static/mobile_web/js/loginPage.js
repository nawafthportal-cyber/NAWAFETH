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
    phoneInput.addEventListener('input', () => {
      const sanitized = _sanitizePhoneInput(phoneInput.value);
      if (phoneInput.value !== sanitized) {
        phoneInput.value = sanitized;
      }
      _hideError(document.getElementById('phone-error'));
    });
    phoneInput.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') _sendOTP(phoneInput);
    });

    btnGuest.addEventListener('click', () => {
      Auth.logout();
      window.location.href = '/';
    });
  }

  function _sanitizePhoneInput(value) {
    return String(value || '').replace(/[^\d]/g, '').slice(0, 10);
  }

  function _isValidPhone(phone) {
    const digits = _sanitizePhoneInput(phone);
    return /^05\d{8}$/.test(digits);
  }

  async function _sendOTP(phoneInput) {
    const rawPhone = phoneInput.value.trim();
    const normalizedPhone = _sanitizePhoneInput(rawPhone);
    const errEl = document.getElementById('phone-error');

    if (phoneInput.value !== normalizedPhone) {
      phoneInput.value = normalizedPhone;
    }

    if (!_isValidPhone(normalizedPhone)) {
      _showError(errEl, 'الصيغة الصحيحة: 05XXXXXXXX');
      return;
    }
    _hideError(errEl);
    _setLoading(true);

    const res = await ApiClient.request('/api/accounts/otp/send/', {
      method: 'POST',
      body: { phone: normalizedPhone },
    });

    _setLoading(false);

    if (!res.ok) {
      const msg = (res.data && (res.data.detail || res.data.error)) || 'فشل إرسال الرمز';
      _showError(errEl, msg);
      return;
    }

    try {
      sessionStorage.setItem('nw_auth_phone', normalizedPhone);
      if (res.data && res.data.dev_code) {
        sessionStorage.setItem('nw_auth_dev_code', String(res.data.dev_code));
      } else {
        sessionStorage.removeItem('nw_auth_dev_code');
      }
    } catch {}

    const qs = new URLSearchParams(window.location.search);
    const next = qs.get('next') || '/';
    const target = new URL('/twofa/', window.location.origin);
    target.searchParams.set('phone', normalizedPhone);
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
