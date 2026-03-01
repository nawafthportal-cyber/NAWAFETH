/* ===================================================================
   twofaPage.js — OTP verification page
   POST /api/accounts/otp/verify/
   POST /api/accounts/otp/send/ (resend)
   =================================================================== */
'use strict';

const TwofaPage = (() => {
  let _phone = '';
  let _next = '/';
  let _resendTimer = null;
  let _resendSeconds = 60;

  function init() {
    if (Auth.isLoggedIn()) {
      const next = new URLSearchParams(window.location.search).get('next') || '/';
      window.location.href = next;
      return;
    }

    const qs = new URLSearchParams(window.location.search);
    _phone = (qs.get('phone') || _sessionGet('nw_auth_phone') || '').trim();
    _next = (qs.get('next') || '/').trim() || '/';

    if (!_phone) {
      window.location.href = '/login/?next=' + encodeURIComponent(_next);
      return;
    }

    const label = document.getElementById('otp-phone-label');
    if (label) label.textContent = _phone;

    _bindOtpInputs();

    const verifyBtn = document.getElementById('btn-verify-otp');
    const resendBtn = document.getElementById('btn-resend-otp');
    if (verifyBtn) verifyBtn.addEventListener('click', _verifyOtp);
    if (resendBtn) resendBtn.addEventListener('click', _resendOtp);

    const devCode = _sessionGet('nw_auth_dev_code');
    if (/^\d{4}$/.test(devCode || '')) {
      _fillCode(String(devCode));
    }

    _startResendTimer();
  }

  function _sessionGet(key) {
    try {
      return sessionStorage.getItem(key);
    } catch {
      return null;
    }
  }

  function _sessionSet(key, value) {
    try {
      sessionStorage.setItem(key, value);
    } catch {}
  }

  function _sessionRemove(key) {
    try {
      sessionStorage.removeItem(key);
    } catch {}
  }

  function _otpInputs() {
    return [0, 1, 2, 3]
      .map((i) => document.getElementById('otp-digit-' + i))
      .filter(Boolean);
  }

  function _bindOtpInputs() {
    const boxes = _otpInputs();
    if (!boxes.length) return;

    boxes.forEach((input, idx) => {
      input.addEventListener('input', () => {
        const digits = String(input.value || '').replace(/[^\d]/g, '');
        input.value = digits ? digits.charAt(digits.length - 1) : '';
        _hideError();
        if (input.value && idx < boxes.length - 1) {
          boxes[idx + 1].focus();
        }
      });

      input.addEventListener('keydown', (e) => {
        if (e.key === 'Backspace' && !input.value && idx > 0) {
          boxes[idx - 1].focus();
        }
        if (e.key === 'Enter') {
          _verifyOtp();
        }
      });
    });

    const wrapper = document.getElementById('otp-boxes');
    if (wrapper) {
      wrapper.addEventListener('paste', (e) => {
        const text = (e.clipboardData || window.clipboardData).getData('text');
        if (!text) return;
        const digits = String(text).replace(/[^\d]/g, '').slice(0, 4);
        if (!digits) return;
        e.preventDefault();
        _fillCode(digits);
      });
    }
  }

  function _fillCode(code) {
    const boxes = _otpInputs();
    for (let i = 0; i < boxes.length; i += 1) {
      boxes[i].value = code[i] || '';
    }
    const nextEmpty = boxes.find((b) => !b.value);
    (nextEmpty || boxes[boxes.length - 1]).focus();
  }

  function _readCode() {
    return _otpInputs().map((input) => (input.value || '').trim()).join('');
  }

  async function _verifyOtp() {
    const code = _readCode();
    if (!/^\d{4}$/.test(code)) {
      _showError('أدخل رمز التحقق المكوّن من 4 أرقام');
      return;
    }

    _setLoading(true);
    _hideError();

    const res = await ApiClient.request('/api/accounts/otp/verify/', {
      method: 'POST',
      body: { phone: _phone, code },
    });

    _setLoading(false);

    if (!res.ok || !res.data) {
      const msg = (res.data && (res.data.detail || res.data.error)) || 'الرمز غير صحيح';
      _showError(msg);
      return;
    }

    Auth.saveTokens({
      access: res.data.access,
      refresh: res.data.refresh,
      user_id: res.data.user_id,
      role_state: res.data.role_state,
    });
    _sessionRemove('nw_auth_dev_code');

    if (res.data.needs_completion) {
      const target = new URL('/signup/', window.location.origin);
      target.searchParams.set('next', _next);
      window.location.href = target.toString();
      return;
    }

    window.location.href = _next;
  }

  async function _resendOtp() {
    const btn = document.getElementById('btn-resend-otp');
    if (!btn || btn.disabled) return;

    btn.disabled = true;
    const res = await ApiClient.request('/api/accounts/otp/send/', {
      method: 'POST',
      body: { phone: _phone },
    });

    if (!res.ok) {
      btn.disabled = false;
      const msg = (res.data && (res.data.detail || res.data.error)) || 'فشل إعادة الإرسال';
      _showError(msg);
      return;
    }

    _hideError();
    if (res.data && res.data.dev_code) {
      _sessionSet('nw_auth_dev_code', String(res.data.dev_code));
      if (/^\d{4}$/.test(String(res.data.dev_code))) {
        _fillCode(String(res.data.dev_code));
      }
    } else {
      _sessionRemove('nw_auth_dev_code');
    }
    _startResendTimer();
  }

  function _startResendTimer() {
    const btn = document.getElementById('btn-resend-otp');
    const timer = document.getElementById('resend-timer');
    if (!btn || !timer) return;

    _resendSeconds = 60;
    btn.disabled = true;
    timer.textContent = '(60)';

    if (_resendTimer) clearInterval(_resendTimer);
    _resendTimer = setInterval(() => {
      _resendSeconds -= 1;
      if (_resendSeconds <= 0) {
        clearInterval(_resendTimer);
        _resendTimer = null;
        btn.disabled = false;
        timer.textContent = '';
        return;
      }
      timer.textContent = '(' + _resendSeconds + ')';
    }, 1000);
  }

  function _setLoading(loading) {
    const btn = document.getElementById('btn-verify-otp');
    const txt = document.getElementById('verify-otp-text');
    const spin = document.getElementById('verify-otp-spinner');
    if (btn) btn.disabled = loading;
    if (txt) txt.classList.toggle('hidden', loading);
    if (spin) spin.classList.toggle('hidden', !loading);
  }

  function _showError(msg) {
    const el = document.getElementById('otp-error');
    if (!el) return;
    el.textContent = msg;
    el.classList.remove('hidden');
  }

  function _hideError() {
    const el = document.getElementById('otp-error');
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
