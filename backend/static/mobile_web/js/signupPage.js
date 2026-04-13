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
  let _regionCatalog = [];
  let _skipLoading = false;

  const REGION_CITY_FALLBACK = [
    { name_ar: 'منطقة الرياض', cities: ['الرياض', 'الخرج', 'الدلم', 'الدرعية', 'الدوادمي', 'الزلفي', 'السليل', 'القويعية', 'المجمعة', 'المزاحمية', 'ثادق', 'حوطة بني تميم', 'شقراء', 'ضرما', 'عفيف', 'الأفلاج'] },
    { name_ar: 'منطقة مكة المكرمة', cities: ['مكة المكرمة', 'جدة', 'الطائف', 'الجموم', 'رابغ', 'القنفذة', 'الليث', 'تربة', 'رنية', 'ظلم'] },
    { name_ar: 'منطقة المدينة المنورة', cities: ['المدينة المنورة', 'ينبع', 'بدر', 'خيبر', 'العلا'] },
    { name_ar: 'المنطقة الشرقية', cities: ['الدمام', 'الخبر', 'الظهران', 'الأحساء', 'الجبيل', 'الخفجي', 'القطيف', 'حفر الباطن'] },
    { name_ar: 'منطقة القصيم', cities: ['بريدة', 'عنيزة', 'الرس', 'البكيرية', 'البدائع', 'المذنب'] },
    { name_ar: 'منطقة عسير', cities: ['أبها', 'خميس مشيط', 'بيشة', 'محايل عسير', 'النماص', 'تنومة', 'سراة عبيدة'] },
    { name_ar: 'منطقة تبوك', cities: ['تبوك', 'ضباء', 'الوجه', 'حقل', 'أملج'] },
    { name_ar: 'منطقة حائل', cities: ['حائل'] },
    { name_ar: 'منطقة الجوف', cities: ['سكاكا', 'القريات', 'طبرجل'] },
    { name_ar: 'منطقة الحدود الشمالية', cities: ['عرعر', 'رفحاء', 'طريف'] },
    { name_ar: 'منطقة نجران', cities: ['نجران', 'شرورة'] },
    { name_ar: 'منطقة جازان', cities: ['جازان', 'صامطة', 'صبيا'] },
    { name_ar: 'منطقة الباحة', cities: ['الباحة', 'بلجرشي', 'العرضيات'] },
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
    _loadRegionCatalog();
    _bindEvents();
    _initMotion();
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

    const skipBtn = document.getElementById('btn-skip-signup');
    if (skipBtn) skipBtn.addEventListener('click', _skipCompletion);

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

    const regionSelect = document.getElementById('region');
    if (regionSelect) {
      regionSelect.addEventListener('change', () => {
        _clearError('region');
        _clearError('city');
        _clearGeneralError();
        _populateCityOptions(_value('region').trim());
      });
    }

    const citySelect = document.getElementById('city');
    if (citySelect) {
      citySelect.addEventListener('change', () => {
        _clearError('city');
        _clearGeneralError();
        _updateCityHint(_value('region').trim(), _value('city').trim());
        _pulseElement(document.getElementById('signup-city-group'));
        _pulseElement(document.getElementById('signup-location-callout'), 'is-updated');
        _setLocationCalloutText(_value('region').trim(), _value('city').trim());
      });
    }

    _bindFieldMotion();
  }

  function _initMotion() {
    const pageBody = document.body;
    if (!pageBody) return;

    window.requestAnimationFrame(() => {
      window.requestAnimationFrame(() => {
        pageBody.classList.add('signup-animate-in');
      });
    });
  }

  function _bindFieldMotion() {
    const fields = document.querySelectorAll('.page-signup .form-input, .page-signup .form-select');
    fields.forEach((field) => {
      const group = field.closest('.form-group');
      if (!group) return;

      field.addEventListener('focus', () => {
        group.classList.add('is-live');
      });

      field.addEventListener('blur', () => {
        group.classList.remove('is-live');
      });

      const activityEvent = field.tagName === 'SELECT' ? 'change' : 'input';
      field.addEventListener(activityEvent, () => {
        if (_value(field.id).trim()) {
          _pulseElement(group);
        }
      });
    });
  }

  function _pulseElement(element, className = 'is-highlighted') {
    if (!element) return;
    element.classList.remove(className);
    window.requestAnimationFrame(() => {
      element.classList.add(className);
      window.setTimeout(() => element.classList.remove(className), 760);
    });
  }

  async function _loadRegionCatalog() {
    _setLocationLoadingState(true);

    let catalog = [];
    const res = await ApiClient.get('/api/providers/geo/regions-cities/');
    if (res.ok && res.data) {
      const payload = Array.isArray(res.data)
        ? res.data
        : Array.isArray(res.data.results)
          ? res.data.results
          : [];
      catalog = _normalizeRegionCatalog(payload);
    }

    if (!catalog.length) {
      catalog = _normalizeRegionCatalog(REGION_CITY_FALLBACK);
    }

    _regionCatalog = catalog;
    _renderRegionOptions();
    _setLocationLoadingState(false);
    _updateRegionHint(catalog.length ? 'اختر المنطقة أولًا.' : 'تعذر تحميل المناطق.', catalog.length ? null : false);
    _setLocationCalloutText('', '');
  }

  function _normalizeRegionCatalog(items) {
    if (!Array.isArray(items)) return [];

    return items
      .map((item) => {
        const rawName = _extractDisplayValue(item, ['name_ar', 'name', 'region']);
        const cities = Array.isArray(item && item.cities)
          ? item.cities
              .map((city) => {
                if (typeof city === 'string') return city.trim();
                return _extractDisplayValue(city, ['name_ar', 'name', 'city']);
              })
              .filter(Boolean)
          : [];
        const uniqueCities = Array.from(new Set(cities));
        if (!rawName || !uniqueCities.length) return null;
        return {
          value: rawName,
          label: _regionDisplayName(rawName),
          cities: uniqueCities,
        };
      })
      .filter(Boolean)
      .sort((left, right) => left.label.localeCompare(right.label, 'ar'));
  }

  function _extractDisplayValue(item, keys) {
    if (!item) return '';
    for (const key of keys) {
      const value = typeof item === 'object' ? item[key] : '';
      if (typeof value === 'string' && value.trim()) {
        return value.trim();
      }
    }
    return '';
  }

  function _regionDisplayName(name) {
    return String(name || '').replace(/^منطقة\s+/, '').trim() || String(name || '').trim();
  }

  function _renderRegionOptions() {
    const regionSelect = document.getElementById('region');
    if (!regionSelect) return;

    const currentRegion = _value('region').trim();
    regionSelect.innerHTML = '';

    const placeholder = document.createElement('option');
    placeholder.value = '';
    placeholder.textContent = 'اختر المنطقة';
    regionSelect.appendChild(placeholder);

    _regionCatalog.forEach((region) => {
      const option = document.createElement('option');
      option.value = region.value;
      option.textContent = region.label;
      regionSelect.appendChild(option);
    });

    if (_findRegion(currentRegion)) {
      regionSelect.value = currentRegion;
    }

    _populateCityOptions(regionSelect.value, _value('city').trim());
  }

  function _populateCityOptions(regionValue, selectedCity) {
    const citySelect = document.getElementById('city');
    if (!citySelect) return;
    const cityGroup = document.getElementById('signup-city-group');
    const regionGroup = document.getElementById('signup-region-group');

    const region = _findRegion(regionValue);
    citySelect.innerHTML = '';

    const placeholder = document.createElement('option');
    placeholder.value = '';
    placeholder.textContent = region ? 'اختر المدينة' : 'اختر المنطقة أولًا';
    citySelect.appendChild(placeholder);
    citySelect.disabled = !region;
    if (regionGroup && regionValue) {
      _pulseElement(regionGroup);
    }

    if (!region) {
      _setLocationCalloutText('', '');
      _updateCityHint('', '');
      return;
    }

    region.cities.forEach((city) => {
      const option = document.createElement('option');
      option.value = city;
      option.textContent = city;
      citySelect.appendChild(option);
    });

    if (selectedCity && region.cities.includes(selectedCity)) {
      citySelect.value = selectedCity;
    }

    _updateRegionHint('تم تحديد المنطقة.', true);
    _updateCityHint(regionValue, citySelect.value);
    _setLocationCalloutText(regionValue, citySelect.value);
    _pulseElement(cityGroup);
    _pulseElement(document.getElementById('signup-location-callout'), 'is-updated');
  }

  function _findRegion(regionValue) {
    return _regionCatalog.find((region) => region.value === regionValue) || null;
  }

  function _setLocationLoadingState(loading) {
    const regionSelect = document.getElementById('region');
    const citySelect = document.getElementById('city');
    if (regionSelect) regionSelect.disabled = loading;
    if (citySelect) {
      citySelect.disabled = true;
      if (loading) {
        citySelect.innerHTML = '<option value="">جاري تحميل المدن...</option>';
      }
    }
    _updateRegionHint(loading ? 'جاري تحميل المناطق...' : 'اختر المنطقة أولًا.', loading ? null : null);
    _updateCityHint('', '');
    _setLocationCalloutText('', '');
  }

  function _setLocationCalloutText(regionValue, cityValue) {
    const text = document.getElementById('signup-location-callout-text');
    if (!text) return;

    const region = _findRegion(regionValue);
    if (!region) {
      text.textContent = 'اختر المنطقة أولًا ثم المدينة.';
      return;
    }

    if (!cityValue) {
      text.textContent = 'تم تحديد ' + region.label + '. اختر المدينة الآن.';
      return;
    }

    text.textContent = region.label + ' - ' + cityValue;
  }

  function _updateRegionHint(message, state) {
    _setHintState('region-hint', message, state);
  }

  function _updateCityHint(regionValue, cityValue) {
    if (!regionValue) {
      _setHintState('city-hint', 'اختر المدينة.', null);
      return;
    }

    const region = _findRegion(regionValue);
    if (!region) {
      _setHintState('city-hint', 'تعذر تحميل المدن.', false);
      return;
    }

    if (cityValue) {
      _setHintState('city-hint', 'تم تحديد المدينة.', true);
      return;
    }

    _setHintState('city-hint', 'اختر مدينة من ' + region.label + '.', null);
  }

  function _setHintState(id, message, state) {
    const hint = document.getElementById(id);
    if (!hint) return;
    hint.textContent = message || '';
    hint.classList.remove('ok');
    hint.classList.remove('bad');
    if (state === true) hint.classList.add('ok');
    if (state === false) hint.classList.add('bad');
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
    const region = _value('region').trim();
    const city = _value('city').trim();
    const password = _value('password');
    const passwordConfirm = _value('password-confirm');
    const acceptTerms = _checked('accept-terms');

    let valid = true;
    if (!firstName) valid = _setError('first-name', 'الاسم الأول مطلوب') && false;
    if (!lastName) valid = _setError('last-name', 'الاسم الأخير مطلوب') && false;
    if (!username) valid = _setError('username', 'اسم المستخدم مطلوب') && false;
    if (!email) valid = _setError('email', 'البريد الإلكتروني مطلوب') && false;
    if (!region) valid = _setError('region', 'المنطقة الإدارية مطلوبة') && false;
    if (!city) valid = _setError('city', 'المدينة مطلوبة') && false;
    if (region && city) {
      const selectedRegion = _findRegion(region);
      if (!selectedRegion || !selectedRegion.cities.includes(city)) {
        valid = _setError('city', 'المدينة المختارة لا تتبع المنطقة المحددة') && false;
      }
    }
    const passwordIssue = _passwordIssue(password);
    if (passwordIssue) valid = _setError('password', passwordIssue) && false;
    if (password !== passwordConfirm) valid = _setError('password-confirm', 'كلمة المرور وتأكيدها غير متطابقين') && false;
    if (!acceptTerms) valid = _setError('accept-terms', 'يجب الموافقة على الشروط والأحكام') && false;
    if (_usernameAvailable === false) valid = _setError('username', 'اسم المستخدم محجوز') && false;

    return valid;
  }

  function _passwordIssue(password) {
    if (!password || password.length < 8) return 'كلمة المرور يجب أن تكون 8 أحرف على الأقل';
    if (!/[a-z]/.test(password)) return 'كلمة المرور يجب أن تحتوي على حرف صغير';
    if (!/[A-Z]/.test(password)) return 'كلمة المرور يجب أن تحتوي على حرف كبير';
    if (!/[0-9]/.test(password)) return 'كلمة المرور يجب أن تحتوي على رقم';
    if (!/[!@#\$&*~%^()\-_=+{};:,<.>]/.test(password)) return 'كلمة المرور يجب أن تحتوي على رمز خاص';
    return '';
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

  async function _skipCompletion() {
    if (_skipLoading) return;

    _clearAllErrors();
    _clearGeneralError();
    _setSkipLoading(true);

    const res = await ApiClient.request('/api/accounts/skip-completion/', {
      method: 'POST',
      body: {},
    });

    _setSkipLoading(false);

    if (!res.ok) {
      const msg = (res.data && (res.data.detail || res.data.error)) || 'تعذر تخطي إكمال البيانات';
      _setGeneralError(msg);
      return;
    }

    if (typeof Auth.saveTokens === 'function') {
      Auth.saveTokens({ role_state: (res.data && res.data.role_state) || 'client' });
    }
    if (typeof Auth.clearProfileCache === 'function') {
      Auth.clearProfileCache();
    }
    window.location.href = _next;
  }

  function _setLoading(loading) {
    const btn = document.getElementById('btn-complete-signup');
    const text = document.getElementById('complete-signup-text');
    const spinner = document.getElementById('complete-signup-spinner');
    if (btn) btn.disabled = loading;
    const skipBtn = document.getElementById('btn-skip-signup');
    if (skipBtn) skipBtn.disabled = loading || _skipLoading;
    if (text) text.classList.toggle('hidden', loading);
    if (spinner) spinner.classList.toggle('hidden', !loading);
  }

  function _setSkipLoading(loading) {
    _skipLoading = !!loading;
    const skipBtn = document.getElementById('btn-skip-signup');
    const skipText = document.getElementById('skip-signup-text');
    const skipIcon = document.getElementById('skip-signup-icon');
    const skipSpinner = document.getElementById('skip-signup-spinner');
    const submitBtn = document.getElementById('btn-complete-signup');

    if (skipBtn) skipBtn.disabled = _skipLoading;
    if (submitBtn) submitBtn.disabled = _skipLoading;
    if (skipText) skipText.classList.toggle('hidden', _skipLoading);
    if (skipIcon) skipIcon.classList.toggle('hidden', _skipLoading);
    if (skipSpinner) skipSpinner.classList.toggle('hidden', !_skipLoading);
  }

  function _setGeneralError(message) {
    const el = document.getElementById('signup-general-error');
    if (!el) return;
    el.textContent = message;
    el.classList.remove('hidden');
    _pulseElement(el);
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
      region: 'err-region',
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
      region: 'err-region',
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
      'region',
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
