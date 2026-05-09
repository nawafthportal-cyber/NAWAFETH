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
  let _usernameCheckPending = false;
  let _usernameCheckToken = 0;
  let _skipLoading = false;
  let _locationMap = null;
  let _locationMarker = null;
  let _reverseLocationRequestId = 0;

  const DEFAULT_LOCATION = Object.freeze({ lat: 24.7136, lng: 46.6753, zoom: 11 });
  const _SAUDI_MAJOR_CITY_FALLBACKS = Object.freeze([
    { name: 'الرياض', aliases: ['الرياض', 'riyadh'], bounds: { minLat: 24.20, maxLat: 25.20, minLng: 46.20, maxLng: 47.30 } },
    { name: 'جدة', aliases: ['جدة', 'jeddah'], bounds: { minLat: 21.20, maxLat: 21.90, minLng: 38.90, maxLng: 39.50 } },
    { name: 'مكة المكرمة', aliases: ['مكة', 'مكة المكرمة', 'mecca', 'makkah'], bounds: { minLat: 21.20, maxLat: 21.70, minLng: 39.50, maxLng: 40.10 } },
    { name: 'المدينة المنورة', aliases: ['المدينة', 'المدينة المنورة', 'medina', 'madinah'], bounds: { minLat: 24.20, maxLat: 24.80, minLng: 39.30, maxLng: 39.90 } },
    { name: 'الدمام', aliases: ['الدمام', 'dammam'], bounds: { minLat: 26.20, maxLat: 26.60, minLng: 49.90, maxLng: 50.30 } },
    { name: 'الخبر', aliases: ['الخبر', 'khobar', 'alkhobar'], bounds: { minLat: 26.20, maxLat: 26.40, minLng: 50.10, maxLng: 50.35 } },
    { name: 'الطائف', aliases: ['الطائف', 'taif'], bounds: { minLat: 21.10, maxLat: 21.50, minLng: 40.20, maxLng: 40.70 } },
    { name: 'أبها', aliases: ['أبها', 'ابها', 'abha'], bounds: { minLat: 18.10, maxLat: 18.40, minLng: 42.30, maxLng: 42.70 } },
    { name: 'تبوك', aliases: ['تبوك', 'tabuk'], bounds: { minLat: 28.20, maxLat: 28.60, minLng: 36.30, maxLng: 36.80 } },
    { name: 'بريدة', aliases: ['بريدة', 'buraydah', 'buraidah'], bounds: { minLat: 26.20, maxLat: 26.50, minLng: 43.80, maxLng: 44.20 } },
    { name: 'حائل', aliases: ['حائل', 'hail', 'ha\'il'], bounds: { minLat: 27.40, maxLat: 27.70, minLng: 41.50, maxLng: 42.00 } },
    { name: 'جازان', aliases: ['جازان', 'جيزان', 'jazan', 'jizan'], bounds: { minLat: 16.70, maxLat: 17.20, minLng: 42.40, maxLng: 43.00 } },
  ]);

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
    _bindEvents();
    _setLocationLoadingState(false);
    _setCityInputManualMode(true);
    _updateCountryHint('اختيارية. حدّد نقطة على الخريطة لتعبئتها تلقائيًا أو اكتبها يدويًا.', null);
    _updateCityHint('', '');
    _setLocationCalloutText('', '', { state: 'idle' });
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

    const locationToggleBtn = document.getElementById('btn-toggle-location-map');
    if (locationToggleBtn) {
      locationToggleBtn.addEventListener('click', () => {
        _setLocationDetailsOpen(locationToggleBtn.getAttribute('aria-expanded') !== 'true');
      });
    }

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

    const useCurrentLocationBtn = document.getElementById('btn-use-current-location');
    if (useCurrentLocationBtn) {
      useCurrentLocationBtn.addEventListener('click', () => {
        _clearError('country');
        _clearError('city');
        _clearGeneralError();
        _useCurrentLocation();
      });
    }

    _bindFieldMotion();
  }

  function _setLocationDetailsOpen(open) {
    const shouldOpen = !!open;
    const panel = document.getElementById('signup-map-panel');
    const fields = document.getElementById('signup-location-fields');
    const toggle = document.getElementById('btn-toggle-location-map');

    if (panel) panel.classList.toggle('is-collapsed', !shouldOpen);
    if (fields) fields.classList.toggle('is-collapsed', !shouldOpen);
    if (toggle) {
      toggle.setAttribute('aria-expanded', shouldOpen ? 'true' : 'false');
      toggle.textContent = shouldOpen ? 'إخفاء الموقع' : 'إضافة الموقع من الخريطة';
    }

    if (!shouldOpen) return;
    if (!_locationMap) {
      _initLocationMap();
    }
    window.setTimeout(() => {
      if (_locationMap) _locationMap.invalidateSize();
    }, 120);
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

  function _setLocationLoadingState(loading) {
    const locationBtn = document.getElementById('btn-use-current-location');
    const mapText = document.getElementById('signup-location-map-text');
    if (locationBtn) locationBtn.disabled = !!loading;
    if (mapText && loading) {
      mapText.textContent = 'جاري تجهيز واجهة الخريطة وخدمات الموقع...';
    }
    if (!loading && mapText) {
      mapText.textContent = 'اضغط على أي نقطة داخل الخريطة أو استخدم موقعك الحالي لتعبئة الدولة والمدينة مباشرة.';
    }
    _setMapStatus(loading ? 'جاري تجهيز خدمات الموقع...' : 'الخريطة جاهزة لتحديد الموقع.', null);
  }

  function _initLocationMap() {
    const mapEl = document.getElementById('signup-location-map');
    if (!mapEl) return;

    if (!window.L || typeof window.L.map !== 'function') {
      _setMapStatus('تعذر تحميل الخريطة. حدّث الصفحة وأعد المحاولة.', false);
      return;
    }

    _locationMap = L.map(mapEl, {
      center: [DEFAULT_LOCATION.lat, DEFAULT_LOCATION.lng],
      zoom: DEFAULT_LOCATION.zoom,
      scrollWheelZoom: false,
      zoomControl: true,
    });

    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '&copy; <a href="https://www.openstreetmap.org/">OSM</a>',
      maxZoom: 18,
    }).addTo(_locationMap);

    _locationMap.on('click', (event) => {
      _clearError('country');
      _clearError('city');
      _clearGeneralError();
      _setMapLocation(event.latlng.lat, event.latlng.lng, { source: 'map' });
    });

    window.setTimeout(() => {
      if (_locationMap) _locationMap.invalidateSize();
    }, 180);
  }

  function _normalizeGeoLabel(value) {
    return String(value || '')
      .trim()
      .replace(/^المملكة العربية السعودية[\s،,-]*/i, '')
      .replace(/^region\s+/i, '')
      .replace(/\s+region$/i, '')
      .replace(/^منطقة\s+/, '')
      .replace(/^إمارة\s+/, '')
      .replace(/^محافظة\s+/, '')
      .replace(/\s+/g, ' ')
      .toLowerCase();
  }

  function _cleanAddressPart(value) {
    return typeof value === 'string' ? value.trim().replace(/\s+/g, ' ') : '';
  }

  function _setLocationField(id, value) {
    const input = document.getElementById(id);
    if (!input) return;
    input.value = value || '';
  }

  function _setCityInputManualMode(manualAllowed) {
    const input = document.getElementById('city');
    if (!input) return;
    input.readOnly = false;
    input.placeholder = manualAllowed
      ? 'يمكنك تعديلها يدويًا أو تركها كما تم تعبئتها'
      : 'اختيارية وتُملأ تلقائيًا إذا كانت متاحة';
  }

  function _setLocationCoordinates(lat, lng) {
    const latInput = document.getElementById('signup-latitude');
    const lngInput = document.getElementById('signup-longitude');
    const coords = document.getElementById('signup-map-coordinates');

    if (latInput) latInput.value = lat == null ? '' : String(lat);
    if (lngInput) lngInput.value = lng == null ? '' : String(lng);
    if (!coords) return;

    if (lat == null || lng == null) {
      coords.textContent = 'لم يتم اختيار نقطة بعد.';
      return;
    }

    coords.textContent = Number(lat).toFixed(5) + ' ، ' + Number(lng).toFixed(5);
  }

  function _ensureLocationMarker(lat, lng) {
    if (!_locationMap) return;

    if (!_locationMarker) {
      _locationMarker = L.marker([lat, lng], { draggable: true }).addTo(_locationMap);
      _locationMarker.on('dragend', () => {
        const next = _locationMarker.getLatLng();
        _setMapLocation(next.lat, next.lng, { source: 'drag' });
      });
      return;
    }

    _locationMarker.setLatLng([lat, lng]);
  }

  function _normalizeCoordinate(value) {
    const parsed = Number(value);
    if (!Number.isFinite(parsed)) return null;
    return Number(parsed.toFixed(6));
  }

  async function _useCurrentLocation() {
    const button = document.getElementById('btn-use-current-location');
    const originalText = button ? button.textContent : '';

    if (!navigator.geolocation) {
      _setMapStatus('المتصفح لا يدعم تحديد الموقع الحالي.', false);
      return;
    }

    if (button) {
      button.disabled = true;
      button.textContent = 'جارٍ تحديد موقعي...';
    }
    _setMapStatus('جارٍ التقاط موقعك الحالي...', null);

    navigator.geolocation.getCurrentPosition(
      async (position) => {
        try {
          await _setMapLocation(position.coords.latitude, position.coords.longitude, { source: 'device' });
        } finally {
          if (button) {
            button.disabled = false;
            button.textContent = originalText;
          }
        }
      },
      (error) => {
        if (button) {
          button.disabled = false;
          button.textContent = originalText;
        }
        if (error && error.code === 1) {
          _setMapStatus('تم رفض صلاحية الموقع. يمكنك تحديد النقطة يدويًا من الخريطة.', false);
          return;
        }
        _setMapStatus('تعذر تحديد موقعك الحالي. جرّب مرة أخرى أو اختر النقطة يدويًا.', false);
      },
      {
        enableHighAccuracy: true,
        timeout: 10000,
        maximumAge: 0,
      }
    );
  }

  async function _setMapLocation(lat, lng, options = {}) {
    const normalizedLat = _normalizeCoordinate(lat);
    const normalizedLng = _normalizeCoordinate(lng);
    if (normalizedLat == null || normalizedLng == null) {
      _setMapStatus('تعذر قراءة الإحداثيات من النقطة المحددة.', false);
      return;
    }

    if (_locationMap) {
      _ensureLocationMarker(normalizedLat, normalizedLng);
      _locationMap.setView([normalizedLat, normalizedLng], Math.max(_locationMap.getZoom(), 13), { animate: true });
    }

    _setLocationCoordinates(normalizedLat, normalizedLng);
    _setMapStatus(
      options.source === 'device'
        ? 'تم التقاط موقعك الحالي. جارٍ قراءة الدولة والمدينة...'
        : 'جارٍ قراءة الدولة والمدينة من النقطة المختارة...'
    , null);
    _updateCountryHint('جارٍ استخراج الدولة من الموقع المحدد...', null);
    _setHintState('city-hint', 'جارٍ محاولة قراءة المدينة إن وجدت...', null);
    _setLocationCalloutText('', '', { state: 'loading' });

    const requestId = ++_reverseLocationRequestId;

    try {
      const resolved = await _reverseGeocodeLocation(normalizedLat, normalizedLng);
      if (requestId !== _reverseLocationRequestId) return;
      _applyResolvedLocation(resolved);
    } catch (_) {
      if (requestId !== _reverseLocationRequestId) return;
      _setLocationField('country', '');
      _setLocationField('city', '');
      _setCityInputManualMode(true);
      _updateCountryHint('تعذر استخراج الدولة من هذه النقطة. يمكنك تجاهلها لأن الحقل اختياري أو تجربة نقطة أخرى.', false);
      _updateCityHint('', '');
      _setMapStatus('تعذر قراءة بيانات الموقع من الخريطة.', false);
      _setLocationCalloutText('', '', { state: 'error' });
    }
  }

  async function _reverseGeocodeLocation(lat, lng) {
    const params = new URLSearchParams({
      format: 'jsonv2',
      lat: String(lat),
      lon: String(lng),
      zoom: '11',
      addressdetails: '1',
      'accept-language': 'ar',
    });
    const response = await fetch('https://nominatim.openstreetmap.org/reverse?' + params.toString(), {
      headers: {
        Accept: 'application/json',
      },
    });
    if (!response.ok) {
      throw new Error('reverse_geocode_failed');
    }

    const data = await response.json();
    const address = data && typeof data === 'object' ? data.address || {} : {};
    const country = _resolveCountryFromAddress(address);
    const city = _resolveCityFromAddress(address, country, lat, lng);

    return { country, city };
  }

  function _resolveCountryFromAddress(address) {
    const candidates = [
      address && address.country,
      address && address.country_code,
    ]
      .map(_cleanAddressPart)
      .filter(Boolean);

    const country = candidates[0] || '';
    if (_normalizeGeoLabel(country) === 'السعودية') {
      return 'المملكة العربية السعودية';
    }

    return country;
  }

  function _looksLikeNeighborhoodLabel(value) {
    const normalized = _normalizeGeoLabel(value);
    return /^حي(?:\s|$)/.test(normalized) || /neighbou?rhood/.test(normalized);
  }

  function _isSaudiCountry(value) {
    const normalized = String(value || '').trim().toLowerCase();
    return normalized.includes('السعودية') || normalized.includes('saudi');
  }

  function _resolveSaudiMajorCity(address, lat, lng) {
    const tokens = [
      address && address.city,
      address && address.town,
      address && address.municipality,
      address && address.county,
      address && address.state,
      address && address.state_district,
      address && address.region,
      address && address.province,
    ]
      .map(_normalizeGeoLabel)
      .filter(Boolean);

    for (const cityConfig of _SAUDI_MAJOR_CITY_FALLBACKS) {
      if (tokens.some((token) => cityConfig.aliases.some((alias) => token === alias || token.includes(alias)))) {
        return cityConfig.name;
      }
    }

    const latValue = Number(lat);
    const lngValue = Number(lng);
    if (!Number.isFinite(latValue) || !Number.isFinite(lngValue)) {
      return '';
    }

    for (const cityConfig of _SAUDI_MAJOR_CITY_FALLBACKS) {
      const bounds = cityConfig.bounds;
      if (latValue >= bounds.minLat && latValue <= bounds.maxLat && lngValue >= bounds.minLng && lngValue <= bounds.maxLng) {
        return cityConfig.name;
      }
    }

    return '';
  }

  function _resolveCityFromAddress(address, countryValue, lat, lng) {
    const countryToken = _normalizeGeoLabel(countryValue);
    const candidates = [
      address && address.city,
      address && address.town,
      address && address.municipality,
      address && address.county,
      address && address.village,
      address && address.state_district,
    ]
      .map(_cleanAddressPart)
      .filter(Boolean);

    for (const candidate of candidates) {
      if (_normalizeGeoLabel(candidate) !== countryToken && !_looksLikeNeighborhoodLabel(candidate)) {
        return candidate;
      }
    }

    if (_isSaudiCountry(countryValue)) {
      return _resolveSaudiMajorCity(address, lat, lng);
    }

    return '';
  }

  function _applyResolvedLocation(location) {
    const country = _cleanAddressPart(location && location.country);
    const city = _cleanAddressPart(location && location.city);

    _setLocationField('country', country);
    _setLocationField('city', city);
    _setCityInputManualMode(true);

    if (country) {
      _updateCountryHint('تم تعبئة الدولة من الموقع المحدد.', true);
    } else {
      _updateCountryHint('تعذر تحديد الدولة من هذه النقطة. جرّب نقطة أخرى.', false);
    }

    _updateCityHint(country, city);
    _setLocationCalloutText(country, city, { state: country ? 'selected' : 'error' });
    _setMapStatus(country ? 'تم تحديث الموقع بنجاح.' : 'تم تحديد النقطة، لكن تعذر استخراج الدولة.', country ? true : false);

    if (country) _pulseElement(document.getElementById('signup-country-group'));
    if (city) _pulseElement(document.getElementById('signup-city-group'));
    _pulseElement(document.getElementById('signup-location-callout'), 'is-updated');
    _pulseElement(document.getElementById('signup-map-panel'));
  }

  function _setMapStatus(message, state) {
    const status = document.getElementById('signup-map-status');
    if (!status) return;
    status.textContent = message || '';
    status.classList.remove('ok');
    status.classList.remove('bad');
    if (state === true) status.classList.add('ok');
    if (state === false) status.classList.add('bad');
  }

  function _setLocationCalloutText(countryValue, cityValue, options = {}) {
    const text = document.getElementById('signup-location-callout-text');
    if (!text) return;

    if (options.state === 'loading') {
      text.textContent = 'جارٍ تحليل موقعك وتعبئة الدولة والمدينة تلقائيًا.';
      return;
    }

    if (options.state === 'error') {
      text.textContent = 'تعذر قراءة الموقع من النقطة المحددة. يمكنك تجاهله لأن الحقول اختيارية أو تجربة نقطة أخرى.';
      return;
    }

    if (!countryValue) {
      text.textContent = 'يمكنك المتابعة بدون موقع، أو تحديد نقطة من الخريطة لتعبئة الدولة والمدينة تلقائيًا.';
      return;
    }

    if (!cityValue) {
      text.textContent = countryValue + ' — لم نعثر على مدينة دقيقة، أدخل المدينة يدويًا إذا كنت تعرفها.';
      return;
    }

    text.textContent = countryValue + ' - ' + cityValue;
  }

  function _updateCountryHint(message, state) {
    _setHintState('country-hint', message, state);
  }

  function _updateCityHint(countryValue, cityValue) {
    if (!countryValue) {
      _setHintState('city-hint', 'اختيارية. يمكنك تركها فارغة أو تعبئتها من الخريطة أو يدويًا عند الحاجة.', null);
      return;
    }

    if (cityValue) {
      _setHintState('city-hint', 'تم تعبئة المدينة تلقائيًا من الموقع المحدد.', true);
      return;
    }

    _setHintState('city-hint', 'لم نعثر على مدينة دقيقة لهذه النقطة. أدخل المدينة يدويًا إذا كنت تعرفها.', null);
  }

  function _buildLocationLabel(countryValue, cityValue) {
    const country = String(countryValue || '').trim();
    const city = String(cityValue || '').trim();
    if (country && city) return country + ' - ' + city;
    return country || city;
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
    _usernameCheckPending = false;
    const checkToken = ++_usernameCheckToken;

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
    _usernameCheckPending = true;
    _debounce = setTimeout(async () => {
      _setUsernameHint('جاري التحقق...', null);
      const encoded = encodeURIComponent(username);
      const res = await ApiClient.get('/api/accounts/username-availability/?username=' + encoded);
      if (checkToken !== _usernameCheckToken || _value('username').trim() !== username) return;
      _usernameCheckPending = false;
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
    const password = _value('password');
    const passwordConfirm = _value('password-confirm');
    const acceptTerms = _checked('accept-terms');

    let valid = true;
    if (!firstName) valid = _setError('first-name', 'الاسم الأول مطلوب') && false;
    if (!lastName) valid = _setError('last-name', 'الاسم الأخير مطلوب') && false;
    if (!username) valid = _setError('username', 'اسم المستخدم مطلوب') && false;
    if (!email) valid = _setError('email', 'البريد الإلكتروني مطلوب') && false;
    const passwordIssue = _passwordIssue(password);
    if (passwordIssue) valid = _setError('password', passwordIssue) && false;
    if (password !== passwordConfirm) valid = _setError('password-confirm', 'كلمة المرور وتأكيدها غير متطابقين') && false;
    if (!acceptTerms) valid = _setError('accept-terms', 'يجب الموافقة على الشروط والأحكام') && false;
    if (_usernameCheckPending) valid = _setError('username', 'انتظر لحظة حتى يكتمل التحقق من اسم المستخدم') && false;
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
        country: _value('country').trim(),
        city: _value('city').trim(),
        location_label: _buildLocationLabel(_value('country').trim(), _value('city').trim()),
        lat: _value('signup-latitude').trim() || null,
        lng: _value('signup-longitude').trim() || null,
        password: _value('password'),
        password_confirm: _value('password-confirm'),
        accept_terms: _checked('accept-terms'),
      },
    });
    _setLoading(false);

    if (res.ok) {
      if (typeof Auth.saveTokens === 'function') {
        Auth.saveTokens({
          role_state: (res.data && res.data.role_state) || 'client',
          profile_status: (res.data && res.data.profile_status) || 'complete',
        });
      }
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
        country: 'country',
        city: 'city',
        location_label: 'country',
        lat: 'country',
        lng: 'country',
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
      Auth.saveTokens({
        role_state: (res.data && res.data.role_state) || 'client',
        profile_status: (res.data && res.data.profile_status) || 'phone_only',
      });
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
      country: 'err-country',
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
      country: 'err-country',
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
      'country',
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
