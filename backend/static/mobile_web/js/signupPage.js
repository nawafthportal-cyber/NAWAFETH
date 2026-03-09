/* ===================================================================
   signupPage.js — Complete registration page
   GET  /api/accounts/username-availability/
   POST /api/accounts/complete/
   =================================================================== */
'use strict';

const SignupPage = (() => {
  let _next = '/';
  let _debounce = null;
  let _usernameAvailable = null;

  const SAUDI_CITIES = [
    'أبها', 'الأحساء', 'الأفلاج', 'الباحة', 'البكيرية', 'البدائع', 'الجبيل', 'الجموم',
    'الحريق', 'الحوطة', 'الخبر', 'الخرج', 'الخفجي', 'الدرعية', 'الدلم', 'الدمام',
    'الدوادمي', 'الرس', 'الرياض', 'الزلفي', 'السليل', 'الطائف', 'الظهران', 'العرضيات',
    'العلا', 'القريات', 'القصيم', 'القطيف', 'القنفذة', 'القويعية', 'الليث', 'المجمعة',
    'المدينة المنورة', 'المذنب', 'المزاحمية', 'النماص', 'الوجه', 'أملج', 'بدر', 'بريدة',
    'بلجرشي', 'بيشة', 'تبوك', 'تربة', 'تنومة', 'ثادق', 'جازان', 'جدة', 'حائل',
    'حفر الباطن', 'حقل', 'حوطة بني تميم', 'خميس مشيط', 'خيبر', 'رابغ', 'رفحاء', 'رنية',
    'سراة عبيدة', 'سكاكا', 'شرورة', 'شقراء', 'صامطة', 'صبيا', 'ضباء', 'ضرما', 'طبرجل',
    'طريف', 'ظلم', 'عرعر', 'عفيف', 'عنيزة', 'محايل عسير', 'مكة المكرمة', 'نجران', 'ينبع',
  ];

  function init() {
    if (!Auth.isLoggedIn()) {
      window.location.href = '/login/?next=' + encodeURIComponent('/signup/');
      return;
    }

    _next = new URLSearchParams(window.location.search).get('next') || '/';
    if (!Auth.needsCompletion || !Auth.needsCompletion()) {
      window.location.href = _next;
      return;
    }
    _loadContent();
    _initCities();
    _bindEvents();
  }

  async function _loadContent() {
    const res = await ApiClient.get('/api/content/public/');
    if (!res.ok || !res.data || typeof res.data !== 'object') return;
    const blocks = res.data.blocks || {};
    _setText('signup-title', _resolveTitle(blocks.signup_title, 'إكمال التسجيل'));
    _setText('signup-desc', _resolveTitle(blocks.signup_description, 'أكمل بياناتك مرة واحدة لتفعيل الحساب والانتقال مباشرة إلى المنصة.'));
    _setText('complete-signup-text', _resolveTitle(blocks.signup_submit_label, 'إكمال التسجيل'));

    const terms = _resolveTitle(blocks.signup_terms_label, 'أوافق على الشروط والأحكام');
    const linkLabel = 'الشروط والأحكام';
    const prefix = terms.endsWith(linkLabel)
      ? terms.slice(0, terms.length - linkLabel.length).trim()
      : terms;
    _setText('signup-terms-prefix', prefix || 'أوافق على');
    _setText('signup-terms-link', linkLabel);
  }

  function _bindEvents() {
    const submitBtn = document.getElementById('btn-complete-signup');
    if (submitBtn) submitBtn.addEventListener('click', _submit);

    const usernameInput = document.getElementById('username');
    if (usernameInput) {
      usernameInput.addEventListener('input', () => {
        _clearError('username');
        _checkUsernameDebounced();
      });
    }

    [
      'first-name',
      'last-name',
      'email',
      'city',
      'password',
      'password-confirm',
      'accept-terms',
    ].forEach((id) => {
      const el = document.getElementById(id);
      if (!el) return;
      const eventName = id === 'accept-terms' ? 'change' : 'input';
      el.addEventListener(eventName, () => {
        _clearGeneralError();
      });
    });
  }

  function _initCities() {
    const select = document.getElementById('city');
    if (!select) return;
    select.innerHTML = '';

    const placeholder = document.createElement('option');
    placeholder.value = '';
    placeholder.textContent = 'اختر المدينة';
    select.appendChild(placeholder);

    SAUDI_CITIES.forEach((city) => {
      const option = document.createElement('option');
      option.value = city;
      option.textContent = city;
      select.appendChild(option);
    });
  }

  function _checkUsernameDebounced() {
    const username = _value('username').trim();
    const hint = document.getElementById('username-hint');
    _usernameAvailable = null;

    if (hint) {
      hint.textContent = '';
      hint.classList.remove('ok');
      hint.classList.remove('bad');
    }

    if (!username) return;
    if (username.length < 3) {
      _setUsernameHint('اسم المستخدم يجب أن يكون 3 أحرف على الأقل', false);
      return;
    }
    if (!/^[A-Za-z0-9_.]+$/.test(username)) {
      _setUsernameHint('المسموح: حروف إنجليزية، أرقام، (_) و (.)', false);
      return;
    }

    if (_debounce) clearTimeout(_debounce);
    _debounce = setTimeout(async () => {
      _setUsernameHint('جاري التحقق...', null);
      const encoded = encodeURIComponent(username);
      const res = await ApiClient.get('/api/accounts/username-availability/?username=' + encoded);
      if (!res.ok || !res.data) {
        _setUsernameHint('تعذر التحقق من اسم المستخدم', false);
        return;
      }
      _usernameAvailable = !!res.data.available;
      _setUsernameHint(res.data.detail || (_usernameAvailable ? 'متاح' : 'محجوز'), _usernameAvailable);
    }, 500);
  }

  function _setUsernameHint(text, available) {
    const hint = document.getElementById('username-hint');
    if (!hint) return;
    hint.textContent = text || '';
    hint.classList.remove('ok');
    hint.classList.remove('bad');
    if (available === true) hint.classList.add('ok');
    if (available === false) hint.classList.add('bad');
  }

  function _value(id) {
    const el = document.getElementById(id);
    return el ? String(el.value || '') : '';
  }

  function _checked(id) {
    const el = document.getElementById(id);
    return !!(el && el.checked);
  }

  function _validate() {
    _clearAllErrors();
    _clearGeneralError();

    const firstName = _value('first-name').trim();
    const lastName = _value('last-name').trim();
    const username = _value('username').trim();
    const email = _value('email').trim();
    const city = _value('city').trim();
    const password = _value('password');
    const passwordConfirm = _value('password-confirm');
    const acceptTerms = _checked('accept-terms');

    let valid = true;
    if (!firstName) valid = _setError('first-name', 'الاسم الأول مطلوب') && false;
    if (!lastName) valid = _setError('last-name', 'الاسم الأخير مطلوب') && false;
    if (!username) valid = _setError('username', 'اسم المستخدم مطلوب') && false;
    if (!email) valid = _setError('email', 'البريد الإلكتروني مطلوب') && false;
    if (!city) valid = _setError('city', 'المدينة مطلوبة') && false;
    if (!password || password.length < 8) valid = _setError('password', 'كلمة المرور يجب أن تكون 8 أحرف على الأقل') && false;
    if (password !== passwordConfirm) valid = _setError('password-confirm', 'كلمة المرور وتأكيدها غير متطابقين') && false;
    if (!acceptTerms) valid = _setError('accept-terms', 'يجب الموافقة على الشروط والأحكام') && false;
    if (_usernameAvailable === false) valid = _setError('username', 'اسم المستخدم محجوز') && false;

    return valid;
  }

  async function _submit() {
    if (!_validate()) return;

    _setLoading(true);
    const res = await ApiClient.request('/api/accounts/complete/', {
      method: 'POST',
      body: {
        first_name: _value('first-name').trim(),
        last_name: _value('last-name').trim(),
        username: _value('username').trim(),
        email: _value('email').trim(),
        city: _value('city').trim(),
        password: _value('password'),
        password_confirm: _value('password-confirm'),
        accept_terms: _checked('accept-terms'),
      },
    });
    _setLoading(false);

    if (res.ok) {
      if (typeof Auth.clearProfileCache === 'function') {
        Auth.clearProfileCache();
      }
      window.location.href = _next;
      return;
    }

    if (res.data && typeof res.data === 'object') {
      const fieldMap = {
        first_name: 'first-name',
        last_name: 'last-name',
        username: 'username',
        email: 'email',
        city: 'city',
        password: 'password',
        password_confirm: 'password-confirm',
        accept_terms: 'accept-terms',
      };
      let hasField = false;
      Object.keys(fieldMap).forEach((key) => {
        if (!(key in res.data)) return;
        const val = res.data[key];
        const msg = Array.isArray(val) ? String(val[0] || '') : String(val || '');
        if (msg) {
          _setError(fieldMap[key], msg);
          hasField = true;
        }
      });
      if (hasField) return;
    }

    const msg = (res.data && (res.data.detail || res.data.error)) || 'فشل إكمال التسجيل';
    _setGeneralError(msg);
  }

  function _setLoading(loading) {
    const btn = document.getElementById('btn-complete-signup');
    const text = document.getElementById('complete-signup-text');
    const spinner = document.getElementById('complete-signup-spinner');
    if (btn) btn.disabled = loading;
    if (text) text.classList.toggle('hidden', loading);
    if (spinner) spinner.classList.toggle('hidden', !loading);
  }

  function _setGeneralError(message) {
    const el = document.getElementById('signup-general-error');
    if (!el) return;
    el.textContent = message;
    el.classList.remove('hidden');
  }

  function _clearGeneralError() {
    const el = document.getElementById('signup-general-error');
    if (!el) return;
    el.textContent = '';
    el.classList.add('hidden');
  }

  function _setError(fieldId, message) {
    const map = {
      'first-name': 'err-first-name',
      'last-name': 'err-last-name',
      username: 'err-username',
      email: 'err-email',
      city: 'err-city',
      password: 'err-password',
      'password-confirm': 'err-password-confirm',
      'accept-terms': 'err-accept-terms',
    };
    const errId = map[fieldId];
    if (!errId) return false;
    const el = document.getElementById(errId);
    if (!el) return false;
    el.textContent = message;
    el.classList.remove('hidden');
    return true;
  }

  function _clearError(fieldId) {
    const map = {
      'first-name': 'err-first-name',
      'last-name': 'err-last-name',
      username: 'err-username',
      email: 'err-email',
      city: 'err-city',
      password: 'err-password',
      'password-confirm': 'err-password-confirm',
      'accept-terms': 'err-accept-terms',
    };
    const errId = map[fieldId];
    if (!errId) return;
    const el = document.getElementById(errId);
    if (!el) return;
    el.textContent = '';
    el.classList.add('hidden');
  }

  function _clearAllErrors() {
    [
      'first-name',
      'last-name',
      'username',
      'email',
      'city',
      'password',
      'password-confirm',
      'accept-terms',
    ].forEach(_clearError);
  }

  function _resolveTitle(block, fallback) {
    if (!block || typeof block !== 'object') return fallback;
    const title = String(block.title_ar || '').trim();
    return title || fallback;
  }

  function _setText(id, value) {
    const el = document.getElementById(id);
    if (!el) return;
    el.textContent = value;
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  return {};
})();
