/* ===================================================================
   twofaPage.js — OTP verification page
   POST /api/accounts/otp/verify/
   POST /api/accounts/otp/send/ (resend)
   =================================================================== */
'use strict';

const TwofaPage = (() => {
  const FACE_ID_ENABLED_KEY = 'nw_faceid_enabled';
  const FACE_ID_PHONE_KEY = 'nw_faceid_phone';
  const FACE_ID_DEVICE_TOKEN_KEY = 'nw_faceid_device_token';
  const FACE_ID_CRED_ID_KEY = 'nw_faceid_cred_id';

  let _phone = '';
  let _next = '/';
  let _resendTimer = null;
  let _resendSeconds = 60;
  let _isResending = false;
  let _content = {
    title: 'التحقق من الرمز',
    description: 'أدخل رمز التحقق المكوّن من 4 أرقام الذي تم إرساله إلى رقم الجوال.',
    submitLabel: 'تأكيد الرمز',
    resendLabel: 'إعادة الإرسال',
    successResendLabel: 'تم إرسال رمز جديد',
    phoneNotice: 'تم إرسال الرمز إلى',
    resendPrompt: 'لم يصلك الرمز؟',
  };

  function init() {
    const qs = new URLSearchParams(window.location.search);
    _phone = _normalizePhone05(qs.get('phone') || _sessionGet('nw_auth_phone') || '');
    _next = (qs.get('next') || '/').trim() || '/';
    _cleanSensitiveQuery(qs);

    const hasPendingPhone = !!(_phone && _isValidPhone05(_phone));
    if (!hasPendingPhone) {
      if (Auth.isLoggedIn()) {
        const next = _resolveNext();
        window.location.href = Auth.needsCompletion && Auth.needsCompletion()
          ? '/signup/?next=' + encodeURIComponent(next)
          : next;
        return;
      }
      window.location.href = '/login/?next=' + encodeURIComponent(_next);
      return;
    }

    _setText('otp-phone-label', _phone);
    _bindOtpInputs();

    const verifyBtn = document.getElementById('btn-verify-otp');
    const resendBtn = document.getElementById('btn-resend-otp');
    if (verifyBtn) verifyBtn.addEventListener('click', _verifyOtp);
    if (resendBtn) resendBtn.addEventListener('click', _resendOtp);

    _loadContent();
    _initFaceIdLogin();

    const devCode = _sessionGet('nw_auth_dev_code');
    if (/^\d{4}$/.test(devCode || '')) _fillCode(String(devCode));

    const initialCooldown = _readPositiveInt(_sessionGet('nw_auth_otp_cooldown')) || 60;
    _sessionRemove('nw_auth_otp_cooldown');
    _startResendTimer(initialCooldown);
  }

  function _sessionGet(key) {
    try {
      return sessionStorage.getItem(key);
    } catch (_) {}
    return null;
  }

  function _sessionSet(key, value) {
    try {
      sessionStorage.setItem(key, value);
    } catch (_) {}
  }

  function _sessionRemove(key) {
    try {
      sessionStorage.removeItem(key);
    } catch (_) {}
  }

  function _clearOtpFlowState() {
    _sessionRemove('nw_auth_phone');
    _sessionRemove('nw_auth_dev_code');
    _sessionRemove('nw_auth_otp_cooldown');
  }

  function _cleanSensitiveQuery(qs) {
    if (!qs || !qs.has('phone') || !window.history || !window.history.replaceState) return;
    try {
      if (_phone) _sessionSet('nw_auth_phone', _phone);
      const clean = new URL(window.location.href);
      clean.searchParams.delete('phone');
      window.history.replaceState({}, document.title, clean.pathname + clean.search + clean.hash);
    } catch (_) {}
  }

  function _normalizePhone05(value) {
    const digits = String(value || '').replace(/[^\d]/g, '');
    if (/^05\d{8}$/.test(digits)) return digits;
    if (/^5\d{8}$/.test(digits)) return '0' + digits;
    if (/^9665\d{8}$/.test(digits)) return '0' + digits.slice(3);
    if (/^009665\d{8}$/.test(digits)) return '0' + digits.slice(5);
    return '';
  }

  function _isValidPhone05(phone) {
    return /^05\d{8}$/.test(String(phone || ''));
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
        _refreshOtpVisual(input);
        _hideError();

        if (input.value && idx < boxes.length - 1) {
          boxes[idx + 1].focus();
        }
      });

      input.addEventListener('keydown', (event) => {
        if (event.key === 'Backspace' && !input.value && idx > 0) {
          boxes[idx - 1].focus();
        }
        if (event.key === 'Enter') {
          _verifyOtp();
        }
      });
    });

    const wrapper = document.getElementById('otp-boxes');
    if (wrapper) {
      wrapper.addEventListener('paste', (event) => {
        const text = (event.clipboardData || window.clipboardData).getData('text');
        if (!text) return;
        const digits = String(text).replace(/[^\d]/g, '').slice(0, 4);
        if (!digits) return;
        event.preventDefault();
        _fillCode(digits);
      });
    }

    boxes.forEach(_refreshOtpVisual);
  }

  function _refreshOtpVisual(input) {
    if (!input) return;
    input.classList.toggle('is-filled', String(input.value || '').trim().length > 0);
  }

  function _fillCode(code) {
    const boxes = _otpInputs();
    for (let i = 0; i < boxes.length; i += 1) {
      boxes[i].value = code[i] || '';
      _refreshOtpVisual(boxes[i]);
    }

    const nextEmpty = boxes.find((box) => !box.value);
    if (nextEmpty) nextEmpty.focus();
    else boxes[boxes.length - 1].focus();
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
      // Keep web parity with Flutter QA/dev OTP behavior.
      body: { phone: _phone, code, mobile_any_otp: true },
    });

    _setLoading(false);

    if (!res.ok || !res.data) {
      _showError(_extractError(res, 'الرمز غير صحيح'));
      return;
    }

    Auth.saveTokens({
      access: res.data.access,
      refresh: res.data.refresh,
      user_id: res.data.user_id,
      role_state: res.data.role_state,
      profile_status: res.data.profile_status,
    });
    _clearOtpFlowState();

    if (!res.data.needs_completion) {
      _queueWelcomeBackToast(res.data);
    }

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
    if (!btn || btn.disabled || _isResending) return;

    _setResending(true);
    _hideError();

    let success = false;
    let nextCooldownSeconds = _resendSeconds > 0 ? _resendSeconds : 60;
    try {
      const res = await ApiClient.request('/api/accounts/otp/send/', {
        method: 'POST',
        body: { phone: _phone },
      });

      if (!res.ok) {
        const retryAfterSeconds = _readPositiveInt(res.data && res.data.retry_after_seconds);
        if (retryAfterSeconds > 0) {
          nextCooldownSeconds = retryAfterSeconds;
          _startResendTimer(retryAfterSeconds);
        }
        _showError(_extractError(res, 'فشل إعادة الإرسال'));
        return;
      }

      nextCooldownSeconds = _readPositiveInt(res.data && res.data.cooldown_seconds) || 60;

      const message = res.data && res.data.dev_code
        ? _content.successResendLabel + ' - رمز التطوير: ' + String(res.data.dev_code)
        : _content.successResendLabel;

      if (res.data && res.data.dev_code) {
        _sessionSet('nw_auth_dev_code', String(res.data.dev_code));
        if (/^\d{4}$/.test(String(res.data.dev_code))) {
          _fillCode(String(res.data.dev_code));
        }
      } else {
        _sessionRemove('nw_auth_dev_code');
      }

      _showToast(message, 'success');
      success = true;
    } catch (_) {
      _showError('فشل إعادة الإرسال');
    } finally {
      _setResending(false);
    }

    if (success) _startResendTimer(nextCooldownSeconds);
  }

  async function _loadContent() {
    const res = await ApiClient.get('/api/content/public/');
    if (!res.ok || !res.data || typeof res.data !== 'object') return;

    const blocks = res.data.blocks || {};
    _content = {
      title: _resolveTitle(blocks.twofa_title, _content.title),
      description: _resolveTitle(blocks.twofa_description, _content.description),
      submitLabel: _resolveTitle(blocks.twofa_submit_label, _content.submitLabel),
      resendLabel: _resolveTitle(blocks.twofa_resend_label, _content.resendLabel),
      successResendLabel: _resolveTitle(blocks.twofa_success_resend_label, _content.successResendLabel),
      phoneNotice: _resolveTitle(blocks.twofa_phone_notice, _content.phoneNotice),
      resendPrompt: _resolveTitle(blocks.twofa_resend_prompt, _content.resendPrompt),
    };

    _setText('twofa-title', _content.title);
    _setText('twofa-desc', _content.description);
    _setText('verify-otp-text', _content.submitLabel);
    _setText('twofa-resend-prompt', _content.resendPrompt);
    _setText('twofa-resend-label', _content.resendLabel);
    _setText('twofa-phone-notice', _content.phoneNotice);
    _updateResendCountdownText();
  }

  function _startResendTimer(seconds) {
    if (_resendTimer) clearInterval(_resendTimer);

    _resendSeconds = _readPositiveInt(seconds) || 0;
    if (_resendSeconds <= 0) {
      _setResendAvailability(true);
      _updateResendCountdownText();
      return;
    }
    _setResendAvailability(false);
    _updateResendCountdownText();

    _resendTimer = setInterval(() => {
      _resendSeconds -= 1;
      if (_resendSeconds <= 0) {
        _resendSeconds = 0;
        clearInterval(_resendTimer);
        _resendTimer = null;
        _setResendAvailability(true);
        return;
      }
      _updateResendCountdownText();
    }, 1000);
  }

  function _setResendAvailability(canResend) {
    const btn = document.getElementById('btn-resend-otp');
    const pill = document.getElementById('resend-countdown-pill');
    if (btn) btn.disabled = !canResend || _isResending;
    if (pill) pill.classList.toggle('hidden', !!canResend);
    if (canResend) _setText('resend-countdown-text', '');
  }

  function _setResending(isResending) {
    _isResending = !!isResending;
    const btn = document.getElementById('btn-resend-otp');
    const label = document.getElementById('twofa-resend-label');
    const spinner = document.getElementById('resend-otp-spinner');

    if (btn) btn.disabled = _isResending || _resendSeconds > 0;
    if (label) label.classList.toggle('hidden', _isResending);
    if (spinner) spinner.classList.toggle('hidden', !_isResending);
  }

  function _updateResendCountdownText() {
    if (_resendSeconds <= 0) {
      _setText('resend-countdown-text', '');
      return;
    }
    _setText('resend-countdown-text', _content.resendLabel + ' بعد ' + _formatWaitShort(_resendSeconds));
  }

  function _formatWaitShort(seconds) {
    const total = _readPositiveInt(seconds);
    if (total < 60) return total + ' ث';
    const minutes = Math.floor(total / 60);
    const remainingSeconds = total % 60;
    if (minutes < 60) {
      return remainingSeconds ? (minutes + ' د ' + remainingSeconds + ' ث') : (minutes + ' د');
    }
    const hours = Math.floor(minutes / 60);
    const remainingMinutes = minutes % 60;
    return remainingMinutes ? (hours + ' س ' + remainingMinutes + ' د') : (hours + ' س');
  }

  function _readPositiveInt(value) {
    const parsed = Number.parseInt(value, 10);
    return Number.isFinite(parsed) && parsed > 0 ? parsed : 0;
  }

  function _setLoading(loading) {
    const btn = document.getElementById('btn-verify-otp');
    const text = document.getElementById('verify-otp-text');
    const spinner = document.getElementById('verify-otp-spinner');
    if (btn) btn.disabled = !!loading;
    if (text) text.classList.toggle('hidden', !!loading);
    if (spinner) spinner.classList.toggle('hidden', !loading);
  }

  function _showError(message) {
    const errorEl = document.getElementById('otp-error');
    if (!errorEl) return;
    errorEl.textContent = String(message || '');
    errorEl.classList.remove('hidden');
  }

  function _hideError() {
    const errorEl = document.getElementById('otp-error');
    if (!errorEl) return;
    errorEl.textContent = '';
    errorEl.classList.add('hidden');
  }

  /* ── Face ID Login ── */

  function _initFaceIdLogin() {
    const section = document.getElementById('faceid-twofa-section');
    if (!section || !window.PublicKeyCredential) return;

    const data = _getStoredBiometricData();
    if (!data || data.phone !== _phone) return;

    section.classList.remove('hidden');
    const btn = document.getElementById('btn-faceid-twofa');
    if (!btn) return;

    btn.addEventListener('click', () => {
      _loginWithFaceId(data.phone, data.deviceToken, data.credJson);
    });
  }

  async function _loginWithFaceId(phone, deviceToken, credJson) {
    const btn = document.getElementById('btn-faceid-twofa');
    const label = document.getElementById('twofa-faceid-label');
    const defaultLabel = btn ? (btn.getAttribute('data-default-label') || 'الدخول بمعرف الوجه') : 'الدخول بمعرف الوجه';

    if (btn) btn.disabled = true;
    if (label) label.textContent = 'جاري التحقق...';

    try {
      await _assertBiometric(credJson);

      const res = await ApiClient.request('/api/accounts/biometric/login/', {
        method: 'POST',
        body: {
          phone: phone,
          device_token: deviceToken,
        },
      });

      if (!res.ok || !res.data) {
        _showError(_extractError(res, 'فشل تسجيل الدخول بمعرف الوجه.'));
        return;
      }

      Auth.saveTokens({
        access: res.data.access,
        refresh: res.data.refresh,
        user_id: res.data.user_id,
        role_state: res.data.role_state,
        profile_status: res.data.profile_status,
      });

      _clearOtpFlowState();

      if (!res.data.needs_completion) {
        _queueWelcomeBackToast(res.data);
      }

      if (res.data.needs_completion) {
        window.location.href = '/signup/?next=' + encodeURIComponent(_next);
        return;
      }
      window.location.href = _next;
    } catch (error) {
      if (!error || error.name !== 'NotAllowedError') {
        _showError('فشل التحقق البيومتري.');
      }
    } finally {
      if (btn) btn.disabled = false;
      if (label) label.textContent = defaultLabel;
    }
  }

  async function _assertBiometric(credJson) {
    const challenge = new Uint8Array(32);
    crypto.getRandomValues(challenge);
    const publicKey = {
      challenge: challenge,
      userVerification: 'required',
      timeout: 60000,
    };

    const credentialId = _parseCredentialId(credJson);
    if (credentialId) {
      publicKey.allowCredentials = [{
        id: credentialId.buffer,
        type: 'public-key',
        transports: ['internal'],
      }];
    }

    await navigator.credentials.get({ publicKey: publicKey });
  }

  function _parseCredentialId(credJson) {
    if (!credJson) return null;
    try {
      const parsed = JSON.parse(credJson);
      if (!Array.isArray(parsed) || !parsed.length) return null;
      return new Uint8Array(parsed);
    } catch (_) {
      return null;
    }
  }

  function _resolveTitle(block, fallback) {
    if (!block || typeof block !== 'object') return fallback;
    const title = String(block.title_ar || '').trim();
    return title || fallback;
  }

  function _setText(id, value) {
    const el = document.getElementById(id);
    if (!el) return;
    el.textContent = String(value || '');
  }

  function _resolveNext() {
    return new URLSearchParams(window.location.search).get('next') || '/';
  }

  function _storageGet(key) {
    try {
      return localStorage.getItem(key);
    } catch (_) {
      return null;
    }
  }

  function _getStoredBiometricData() {
    const enabled = _storageGet(FACE_ID_ENABLED_KEY) === '1';
    const phone = _normalizePhone05(_storageGet(FACE_ID_PHONE_KEY) || '');
    const deviceToken = String(_storageGet(FACE_ID_DEVICE_TOKEN_KEY) || '').trim();
    const credJson = String(_storageGet(FACE_ID_CRED_ID_KEY) || '').trim();
    if (!enabled || !phone || !deviceToken) return null;
    return {
      phone: phone,
      deviceToken: deviceToken,
      credJson: credJson,
    };
  }

  function _extractError(res, fallback) {
    if (!res || !res.data || typeof res.data !== 'object') return fallback;
    if (typeof res.data.detail === 'string' && res.data.detail.trim()) return res.data.detail.trim();
    if (typeof res.data.error === 'string' && res.data.error.trim()) return res.data.error.trim();
    const keys = Object.keys(res.data);
    for (let i = 0; i < keys.length; i += 1) {
      const value = res.data[keys[i]];
      if (typeof value === 'string' && value.trim()) return value.trim();
      if (Array.isArray(value) && value.length) return String(value[0]);
    }
    return fallback;
  }

  function _queueWelcomeBackToast(data) {
    if (!window.Toast || typeof window.Toast.queue !== 'function') return;
    const isNewUser = !!(data && data.is_new_user);
    window.Toast.queue(
      isNewUser
        ? 'يسعدنا انضمامك إلى منصة نوافذ. نتمنى لك تجربة موفقة ومتكاملة.'
        : 'مرحبًا بعودتك إلى منصة نوافذ. يسعدنا استمرار ثقتك بنا، ونتمنى لك تجربة سلسة ومثمرة.',
      {
        title: isNewUser ? 'أهلًا بك في نوافذ' : 'مرحبًا بعودتك',
        type: 'success',
        duration: 6200,
      }
    );
  }

  function _showToast(message, type) {
    if (!message) return;

    if (window.Toast && typeof window.Toast.show === 'function') {
      window.Toast.show(message, { type: type || 'success' });
      return;
    }

    const existing = document.getElementById('twofa-toast');
    if (existing) existing.remove();

    const toast = document.createElement('div');
    toast.id = 'twofa-toast';
    toast.className = 'twofa-toast' + (type ? (' ' + type) : '');
    toast.textContent = message;
    document.body.appendChild(toast);

    requestAnimationFrame(() => toast.classList.add('show'));
    window.setTimeout(() => {
      toast.classList.remove('show');
      window.setTimeout(() => {
        if (toast.parentNode) toast.remove();
      }, 180);
    }, 2400);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  window.addEventListener('beforeunload', () => {
    if (_resendTimer) clearInterval(_resendTimer);
  });

  return {};
})();
