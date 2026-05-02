/* ===================================================================
   loginPage.js — Login phone step
   POST /api/accounts/otp/send/ -> send OTP then redirect to /twofa/
   =================================================================== */
'use strict';

const LoginPage = (() => {
  const FACE_ID_ENABLED_KEY = 'nw_faceid_enabled';
  const FACE_ID_PHONE_KEY = 'nw_faceid_phone';
  const FACE_ID_DEVICE_TOKEN_KEY = 'nw_faceid_device_token';
  const FACE_ID_CRED_ID_KEY = 'nw_faceid_cred_id';
  const COPY = {
    ar: {
      pageTitle: 'نوافــذ — تسجيل الدخول',
      title: 'تسجيل الدخول',
      description: 'أدخل رقم الجوال وسنرسل لك رمز تحقق لإكمال الدخول بأمان.',
      phoneLabel: 'رقم الجوال',
      phoneHint: 'الصيغة المعتمدة: 05XXXXXXXX',
      submit: 'إرسال رمز التحقق',
      guest: 'المتابعة كضيف',
      faceId: 'الدخول بمعرف الوجه',
      divider: 'أو',
      invalidPhone: 'الصيغة الصحيحة: 05XXXXXXXX',
      sendFailed: 'فشل إرسال الرمز',
      biometricFailed: 'فشل التحقق البيومتري.',
      biometricLoginFailed: 'فشل تسجيل الدخول بمعرف الوجه.',
      retryIn: 'أعد المحاولة بعد {time}',
      timeSecond: 'ث',
      timeMinute: 'د',
      timeHour: 'س',
      welcomeTitle: 'مرحبًا بعودتك',
      welcomeMessage: 'مرحبًا بعودتك إلى منصة نوافذ. يسعدنا استمرار ثقتك بنا، ونتمنى لك تجربة سلسة ومثمرة.',
    },
    en: {
      pageTitle: 'Nawafeth — Sign in',
      title: 'Sign in',
      description: 'Enter your mobile number and we will send a verification code to complete your sign-in securely.',
      phoneLabel: 'Mobile number',
      phoneHint: 'Accepted format: 05XXXXXXXX',
      submit: 'Send verification code',
      guest: 'Continue as guest',
      faceId: 'Sign in with Face ID',
      divider: 'or',
      invalidPhone: 'Use this format: 05XXXXXXXX',
      sendFailed: 'Failed to send the code.',
      biometricFailed: 'Biometric verification failed.',
      biometricLoginFailed: 'Face ID sign-in failed.',
      retryIn: 'Retry in {time}',
      timeSecond: 's',
      timeMinute: 'm',
      timeHour: 'h',
      welcomeTitle: 'Welcome back',
      welcomeMessage: 'Welcome back to Nawafeth. We are glad to continue serving you and hope your experience stays smooth and productive.',
    },
  };

  let _sendCooldownTimer = null;
  let _sendCooldownSeconds = 0;
  let _sendOtpDefaultLabel = COPY.ar.submit;
  let _contentBlocks = {};

  function init() {
    if (Auth.isLoggedIn()) {
      const next = _resolveNext();
      window.location.href = Auth.needsCompletion && Auth.needsCompletion()
        ? '/signup/?next=' + encodeURIComponent(next)
        : next;
      return;
    }

    const phoneInput = document.getElementById('phone-input');
    const btnSend = document.getElementById('btn-send-otp');
    const btnGuest = document.getElementById('btn-guest');

    if (!phoneInput || !btnSend || !btnGuest) return;
    _applyStaticCopy();
    _loadContent();
    _initFaceIdLogin();

    window.addEventListener('nawafeth:languagechange', _handleLanguageChange);

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

  async function _loadContent() {
    const res = await ApiClient.get('/api/content/public/');
    if (!res.ok || !res.data || typeof res.data !== 'object') return;
    _contentBlocks = res.data.blocks || {};
    _applyContentCopy();
  }

  function _sanitizePhoneInput(value) {
    const digits = String(value || '').replace(/\D/g, '');
    if (/^05\d{8}$/.test(digits)) return digits;
    if (/^5\d{8}$/.test(digits)) return '0' + digits;
    if (/^9665\d{8}$/.test(digits)) return '0' + digits.slice(3);
    if (/^009665\d{8}$/.test(digits)) return '0' + digits.slice(5);
    return digits.slice(0, 10);
  }

  function _isValidPhone(phone) {
    const digits = _sanitizePhoneInput(phone);
    return /^05\d{8}$/.test(digits);
  }

  async function _sendOTP(phoneInput) {
    if (_sendCooldownSeconds > 0) {
      return;
    }

    const rawPhone = phoneInput.value.trim();
    const normalizedPhone = _sanitizePhoneInput(rawPhone);
    const errEl = document.getElementById('phone-error');

    if (phoneInput.value !== normalizedPhone) {
      phoneInput.value = normalizedPhone;
    }

    if (!_isValidPhone(normalizedPhone)) {
      _showError(errEl, _copy('invalidPhone'));
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
      const retryAfterSeconds = _readPositiveInt(res.data && res.data.retry_after_seconds);
      if (retryAfterSeconds > 0) {
        _startSendCooldown(retryAfterSeconds);
      }
      const msg = (res.data && (res.data.detail || res.data.error)) || _copy('sendFailed');
      _showError(errEl, msg);
      return;
    }

    try {
      sessionStorage.setItem('nw_auth_phone', normalizedPhone);
      const cooldownSeconds = _readPositiveInt(res.data && res.data.cooldown_seconds);
      if (cooldownSeconds > 0) {
        sessionStorage.setItem('nw_auth_otp_cooldown', String(cooldownSeconds));
      } else {
        sessionStorage.removeItem('nw_auth_otp_cooldown');
      }
      if (res.data && res.data.dev_code) {
        sessionStorage.setItem('nw_auth_dev_code', String(res.data.dev_code));
      } else {
        sessionStorage.removeItem('nw_auth_dev_code');
      }
    } catch {}

    const qs = new URLSearchParams(window.location.search);
    const next = qs.get('next') || '/';
    const target = new URL('/twofa/', window.location.origin);
    target.searchParams.set('next', next);
    window.location.href = target.toString();
  }

  /* ── Face ID Login ── */

  function _initFaceIdLogin() {
    var data = _getStoredBiometricData();
    var section = document.getElementById('faceid-login-section');

    if (!data || !section) return;
    if (!window.PublicKeyCredential) return;

    section.classList.remove('hidden');

    var btn = document.getElementById('btn-faceid-login');
    if (btn) {
      btn.addEventListener('click', function () {
        _loginWithFaceId(data.phone, data.deviceToken, data.credJson);
      });
    }
  }

  async function _loginWithFaceId(phone, deviceToken, credJson) {
    var btn = document.getElementById('btn-faceid-login');
    var errEl = document.getElementById('phone-error');

    if (btn) { btn.disabled = true; btn.style.opacity = '0.65'; }

    try {
      await _assertBiometric(credJson);

      var res = await ApiClient.request('/api/accounts/biometric/login/', {
        method: 'POST',
        body: {
          phone: phone,
          device_token: deviceToken,
        },
      });

      if (!res.ok || !res.data) {
        _showError(errEl, _extractError(res, _copy('biometricLoginFailed')));
        return;
      }

      Auth.saveTokens({
        access: res.data.access,
        refresh: res.data.refresh,
        user_id: res.data.user_id,
        role_state: res.data.role_state,
      });

      try {
        sessionStorage.setItem('nw_auth_phone', phone);
        sessionStorage.removeItem('nw_auth_dev_code');
      } catch {}

      var next = _resolveNext();
      if (!res.data.needs_completion) {
        _queueWelcomeBackToast(res.data);
      }
      if (res.data.needs_completion) {
        window.location.href = '/signup/?next=' + encodeURIComponent(next);
        return;
      }
      window.location.href = next;
    } catch (err) {
      if (err.name !== 'NotAllowedError') {
        _showError(errEl, _copy('biometricFailed'));
      }
    } finally {
      if (btn) { btn.disabled = false; btn.style.opacity = ''; }
    }
  }

  function _setLoading(loading) {
    const btn = document.getElementById('btn-send-otp');
    const txt = document.getElementById('send-otp-text');
    const spin = document.getElementById('send-otp-spinner');
    if (btn) btn.disabled = loading || _sendCooldownSeconds > 0;
    if (txt) txt.classList.toggle('hidden', loading);
    if (spin) spin.classList.toggle('hidden', !loading);
    if (!loading) _syncSendOtpButton();
  }

  function _startSendCooldown(seconds) {
    const nextSeconds = _readPositiveInt(seconds);
    if (nextSeconds <= 0) return;

    if (_sendCooldownTimer) {
      clearInterval(_sendCooldownTimer);
      _sendCooldownTimer = null;
    }

    _sendCooldownSeconds = nextSeconds;
    _syncSendOtpButton();

    _sendCooldownTimer = setInterval(() => {
      _sendCooldownSeconds -= 1;
      if (_sendCooldownSeconds <= 0) {
        _sendCooldownSeconds = 0;
        clearInterval(_sendCooldownTimer);
        _sendCooldownTimer = null;
      }
      _syncSendOtpButton();
    }, 1000);
  }

  function _syncSendOtpButton() {
    const btn = document.getElementById('btn-send-otp');
    const txt = document.getElementById('send-otp-text');
    const spin = document.getElementById('send-otp-spinner');
    const loading = !!(spin && !spin.classList.contains('hidden'));

    if (btn) btn.disabled = loading || _sendCooldownSeconds > 0;
    if (txt && !loading) {
      txt.textContent = _sendCooldownSeconds > 0
        ? _copy('retryIn').replace('{time}', _formatWaitShort(_sendCooldownSeconds))
        : _sendOtpDefaultLabel;
    }
  }

  function _formatWaitShort(seconds) {
    const total = _readPositiveInt(seconds);
    if (total < 60) return total + ' ' + _copy('timeSecond');
    const minutes = Math.floor(total / 60);
    const remainingSeconds = total % 60;
    if (minutes < 60) {
      return remainingSeconds
        ? (minutes + ' ' + _copy('timeMinute') + ' ' + remainingSeconds + ' ' + _copy('timeSecond'))
        : (minutes + ' ' + _copy('timeMinute'));
    }
    const hours = Math.floor(minutes / 60);
    const remainingMinutes = minutes % 60;
    return remainingMinutes
      ? (hours + ' ' + _copy('timeHour') + ' ' + remainingMinutes + ' ' + _copy('timeMinute'))
      : (hours + ' ' + _copy('timeHour'));
  }

  function _readPositiveInt(value) {
    const parsed = Number.parseInt(value, 10);
    return Number.isFinite(parsed) && parsed > 0 ? parsed : 0;
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

  function _resolveLocalizedText(block, fallbackKey) {
    const fallback = _copy(fallbackKey);
    if (!block) return fallback;
    if (typeof block === 'string') {
      const raw = block.trim();
      return raw || fallback;
    }
    if (typeof block !== 'object') return fallback;

    const lang = _currentLang();
    const preferred = lang === 'en'
      ? ['title_en', 'body_en', 'title_ar', 'body_ar']
      : ['title_ar', 'body_ar', 'title_en', 'body_en'];

    for (let i = 0; i < preferred.length; i += 1) {
      const value = String(block[preferred[i]] || '').trim();
      if (value) return value;
    }

    return fallback;
  }

  function _applyStaticCopy() {
    document.title = _copy('pageTitle');
    _setText('login-phone-label', _copy('phoneLabel'));
    _setText('login-faceid-divider', _copy('divider'));
    _setText('login-faceid-label', _copy('faceId'));
    _setText('login-guest-divider', _copy('divider'));
    const phoneInput = document.getElementById('phone-input');
    if (phoneInput) {
      phoneInput.placeholder = '05XXXXXXXX';
      phoneInput.setAttribute('aria-label', _copy('phoneLabel'));
    }
    const faceIdButton = document.getElementById('btn-faceid-login');
    if (faceIdButton) {
      faceIdButton.setAttribute('aria-label', _copy('faceId'));
      faceIdButton.setAttribute('title', _copy('faceId'));
    }
  }

  function _applyContentCopy() {
    _setText('login-title', _resolveLocalizedText(_contentBlocks.login_title, 'title'));
    _setText('login-desc', _resolveLocalizedText(_contentBlocks.login_description, 'description'));
    _setText('login-phone-hint', _resolveLocalizedText(_contentBlocks.login_phone_hint, 'phoneHint'));
    _sendOtpDefaultLabel = _resolveLocalizedText(_contentBlocks.login_submit_label, 'submit');
    _setText('guest-login-text', _resolveLocalizedText(_contentBlocks.login_guest_label, 'guest'));
    _syncSendOtpButton();
  }

  function _handleLanguageChange() {
    _applyStaticCopy();
    _applyContentCopy();
  }

  function _setText(id, value) {
    const el = document.getElementById(id);
    if (!el) return;
    el.textContent = value;
  }

  async function _assertBiometric(credJson) {
    var challenge = new Uint8Array(32);
    crypto.getRandomValues(challenge);
    var publicKey = {
      challenge: challenge,
      userVerification: 'required',
      timeout: 60000,
    };

    var credId = _parseCredentialId(credJson);
    if (credId) {
      publicKey.allowCredentials = [{
        id: credId.buffer,
        type: 'public-key',
        transports: ['internal'],
      }];
    }

    await navigator.credentials.get({ publicKey: publicKey });
  }

  function _parseCredentialId(credJson) {
    if (!credJson) return null;
    try {
      var parsed = JSON.parse(credJson);
      if (!Array.isArray(parsed) || !parsed.length) return null;
      return new Uint8Array(parsed);
    } catch (_) {
      return null;
    }
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

  function _normalizePhone05(value) {
    var digits = String(value || '').replace(/[^\d]/g, '');
    if (/^05\d{8}$/.test(digits)) return digits;
    if (/^5\d{8}$/.test(digits)) return '0' + digits;
    if (/^9665\d{8}$/.test(digits)) return '0' + digits.slice(3);
    if (/^009665\d{8}$/.test(digits)) return '0' + digits.slice(5);
    return '';
  }

  function _getStoredBiometricData() {
    var enabled = _storageGet(FACE_ID_ENABLED_KEY) === '1';
    var phone = _normalizePhone05(_storageGet(FACE_ID_PHONE_KEY) || '');
    var deviceToken = String(_storageGet(FACE_ID_DEVICE_TOKEN_KEY) || '').trim();
    var credJson = String(_storageGet(FACE_ID_CRED_ID_KEY) || '').trim();
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
    var keys = Object.keys(res.data);
    for (var i = 0; i < keys.length; i += 1) {
      var value = res.data[keys[i]];
      if (typeof value === 'string' && value.trim()) return value.trim();
      if (Array.isArray(value) && value.length) return String(value[0]);
    }
    return fallback;
  }

  function _queueWelcomeBackToast(data) {
    if (!window.Toast || typeof window.Toast.queue !== 'function') return;
    window.Toast.queue(
      _copy('welcomeMessage'),
      {
        title: _copy('welcomeTitle'),
        type: 'success',
        duration: 6200,
      }
    );
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  return {};
})();
