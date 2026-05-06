/* ===================================================================
  onboardingOverlay.js — Full-screen onboarding overlay for first-time visitors
  Shows 3 CMS-driven slides over the home page, then a login screen.
  Uses localStorage to remember whether the onboarding was shown today.
  =================================================================== */
'use strict';

const OnboardingOverlay = (() => {
  const STORAGE_KEY = 'nw_onboarding_seen';
  const LOCKED_HOME_CLASS = 'home-mobile-layout--locked';
  const COPY = {
    ar: {
      overlayLabel: 'مرحبا بك في نوافذ',
      skip: 'تخطي',
      next: 'التالي',
      startNow: 'ابدأ الآن',
      continue: 'متابعة',
      promoAlt: 'تعرف على نوافذ',
      signInTitle: 'تسجيل الدخول',
      signInSubtitle: 'أدخل رقم جوالك وسنرسل لك رمز تحقق للدخول',
      sendOtp: 'إرسال رمز التحقق',
      sending: 'جاري الإرسال...',
      divider: 'أو',
      guest: 'الدخول كزائر',
      invalidPhone: 'أدخل رقم جوال صحيح يبدأ بـ 05 ومكون من 10 أرقام',
      sendFailed: 'تعذر إرسال رمز التحقق، حاول مرة أخرى',
      connectionFailed: 'حدث خطأ في الاتصال، حاول مرة أخرى',
      resend: 'إعادة إرسال رمز التحقق',
      resendAfter: 'يمكنك إعادة الإرسال بعد {time}',
      stepLabel: '{index} / {total}',
    },
    en: {
      overlayLabel: 'Welcome to Nawafeth',
      skip: 'Skip',
      next: 'Next',
      startNow: 'Start now',
      continue: 'Continue',
      promoAlt: 'Discover Nawafeth',
      signInTitle: 'Sign in',
      signInSubtitle: 'Enter your mobile number and we will send you a verification code to sign in.',
      sendOtp: 'Send verification code',
      sending: 'Sending...',
      divider: 'or',
      guest: 'Continue as guest',
      invalidPhone: 'Enter a valid mobile number starting with 05 and containing 10 digits.',
      sendFailed: 'Unable to send the verification code. Please try again.',
      connectionFailed: 'A connection error occurred. Please try again.',
      resend: 'Resend verification code',
      resendAfter: 'You can resend after {time}',
      stepLabel: '{index} / {total}',
    },
  };
  const SLIDE_KEYS = [
    { key: 'onboarding_first_time',  iconSvg: 'widgets' },
    { key: 'onboarding_intro',       iconSvg: 'people' },
    { key: 'onboarding_get_started', iconSvg: 'bolt' },
  ];

  const ICONS = {
    widgets: '<path d="M13 13v8h8v-8h-8zM3 21h8v-8H3v8zM3 3v8h8V3H3zm13.66-1.31L11 7.34 16.66 13l5.66-5.66-5.66-5.65z"/>',
    people: '<path d="M16 11c1.66 0 2.99-1.34 2.99-3S17.66 5 16 5c-1.66 0-3 1.34-3 3s1.34 3 3 3zm-8 0c1.66 0 2.99-1.34 2.99-3S9.66 5 8 5C6.34 5 5 6.34 5 8s1.34 3 3 3zm0 2c-2.33 0-7 1.17-7 3.5V19h14v-2.5c0-2.33-4.67-3.5-7-3.5zm8 0c-.29 0-.62.02-.97.05 1.16.84 1.97 1.97 1.97 3.45V19h6v-2.5c0-2.33-4.67-3.5-7-3.5z"/>',
    bolt: '<path d="M11 21h-1l1-7H7.5c-.88 0-.33-.75-.31-.78C8.48 10.94 10.42 7.54 13.01 3h1l-1 7h3.51c.4 0 .62.19.4.66C12.97 17.55 11 21 11 21z"/>',
  };

  /* State */
  let _overlay = null;
  let _slides = [];
  let _introBlock = null;          /* dedicated app preview block shown after slides */
  let _index = 0;
  let _touchStartX = 0;
  let _phase = 'slides';          /* 'slides' | 'promo' | 'login' */
  let _otpCooldownTimer = null;
  let _otpCooldownEnd = 0;

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

  function _resolveText(arValue, enValue, fallbackKey) {
    const primary = _currentLang() === 'en' ? String(enValue || '').trim() : String(arValue || '').trim();
    if (primary) return primary;
    const secondary = _currentLang() === 'en' ? String(arValue || '').trim() : String(enValue || '').trim();
    if (secondary) return secondary;
    return fallbackKey ? _copy(fallbackKey) : '';
  }

  function _todayStamp() {
    const now = new Date();
    const year = now.getFullYear();
    const month = String(now.getMonth() + 1).padStart(2, '0');
    const day = String(now.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  }

  function _normalizePhone05(value) {
    const digits = String(value || '').replace(/\D/g, '');
    if (/^05\d{8}$/.test(digits)) return digits;
    if (/^5\d{8}$/.test(digits)) return '0' + digits;
    if (/^9665\d{8}$/.test(digits)) return '0' + digits.slice(3);
    if (/^009665\d{8}$/.test(digits)) return '0' + digits.slice(5);
    return digits.slice(0, 10);
  }

  /* ── public ── */
  function init() {
    if (_hasSeenOnboarding()) return;
    _fetchAndShow();
  }

  /* ── storage ── */
  function _hasSeenOnboarding() {
    try { return localStorage.getItem(STORAGE_KEY) === _todayStamp(); } catch (_) { return false; }
  }
  function _markSeen() {
    try { localStorage.setItem(STORAGE_KEY, _todayStamp()); } catch (_) {}
  }

  function _setHomeLockedState(locked) {
    if (!document.body) return;
    document.body.classList.toggle(LOCKED_HOME_CLASS, !!locked);
  }

  /* ── data ── */
  async function _fetchAndShow() {
    _createOverlayShell();
    _showLoading();

    let res = null;
    try {
      res = await ApiClient.get('/api/content/public/');
    } catch (_) {
      _dismissFinal({ markSeen: false });
      return;
    }

    if (!res.ok || !res.data || typeof res.data !== 'object') {
      _dismissFinal({ markSeen: false });
      return;
    }

    const blocks = res.data.blocks || {};
    _slides = SLIDE_KEYS
      .map(def => _mergeBlock(def, blocks[def.key]))
      .filter(s => s && _resolveSlideTitle(s));

    /* Save standalone app preview block shown after the 3 onboarding slides */
    const introRaw = blocks['app_intro_preview'];
    if (introRaw && introRaw.media_url) {
      _introBlock = {
        title_ar:  String(introRaw.title_ar || '').trim(),
        title_en:  String(introRaw.title_en || '').trim(),
        desc_ar:   String(introRaw.body_ar  || '').trim(),
        desc_en:   String(introRaw.body_en  || '').trim(),
        mediaUrl:  ApiClient.mediaUrl(introRaw.media_url) || '',
        mediaType: String(introRaw.media_type || '').toLowerCase(),
        hasMedia:  !!introRaw.has_media,
      };
    }

    if (!_slides.length) {
      _dismissFinal({ markSeen: true });
      return;
    }

    _index = 0;
    _phase = 'slides';
    _renderSlides();
  }

  function _mergeBlock(def, block) {
    if (!block || typeof block !== 'object') return null;
    const titleAr = String(block.title_ar || '').trim();
    const titleEn = String(block.title_en || '').trim();
    const descAr = String(block.body_ar || '').trim();
    const descEn = String(block.body_en || '').trim();
    if (!titleAr && !titleEn && !descAr && !descEn) return null;
    return {
      ...def,
      title_ar: titleAr,
      title_en: titleEn,
      desc_ar: descAr,
      desc_en: descEn,
      mediaUrl:  ApiClient.mediaUrl(block.media_url || '') || '',
      mediaType: String(block.media_type || '').toLowerCase(),
    };
  }

  /* ── overlay shell ── */
  function _createOverlayShell() {
    if (_overlay) return;
    _overlay = document.createElement('div');
    _overlay.className = 'ob-overlay';
    _overlay.setAttribute('role', 'dialog');
    _overlay.setAttribute('aria-modal', 'true');
    _overlay.setAttribute('aria-label', _copy('overlayLabel'));
    document.body.appendChild(_overlay);
    document.body.style.overflow = 'hidden';
    _setHomeLockedState(true);

    requestAnimationFrame(() => {
      requestAnimationFrame(() => _overlay.classList.add('ob-overlay--visible'));
    });
  }

  function _showLoading() {
    _overlay.innerHTML = '<div class="ob-loader"><div class="ob-loader-ring"></div></div>';
  }

  /* ================================================================
     PHASE 1 — ONBOARDING SLIDES
     ================================================================ */
  function _renderSlides() {
    _overlay.innerHTML = '';
    _phase = 'slides';

    /* Background particles */
    _overlay.appendChild(_buildParticles());

    /* Container */
    const container = document.createElement('div');
    container.className = 'ob-container';
    _overlay.appendChild(container);

    /* Page counter */
    const counter = document.createElement('div');
    counter.className = 'ob-counter';
    counter.id = 'ob-counter';
    container.appendChild(counter);

    /* Stage */
    const stage = document.createElement('div');
    stage.className = 'ob-stage';
    stage.id = 'ob-stage';
    container.appendChild(stage);
    _slides.forEach((slide, idx) => stage.appendChild(_buildSlide(slide, idx)));

    /* Dots */
    const dots = document.createElement('div');
    dots.className = 'ob-dots';
    dots.id = 'ob-dots';
    _slides.forEach((_, idx) => {
      const dot = document.createElement('span');
      dot.className = 'ob-dot';
      dot.dataset.index = String(idx);
      dot.addEventListener('click', () => _goTo(idx));
      dots.appendChild(dot);
    });
    container.appendChild(dots);

    /* Actions */
    const actions = document.createElement('div');
    actions.className = 'ob-actions';

    const skipBtn = document.createElement('button');
    skipBtn.className = 'ob-btn-skip';
    skipBtn.textContent = _copy('skip');
    skipBtn.addEventListener('click', _dismiss);

    const nextBtn = document.createElement('button');
    nextBtn.className = 'ob-btn-next';
    nextBtn.id = 'ob-btn-next';
    nextBtn.addEventListener('click', _next);

    actions.appendChild(skipBtn);
    actions.appendChild(nextBtn);
    container.appendChild(actions);

    /* Swipe */
    _bindSwipe(stage);
    /* Keyboard */
    _bindKeyboard();

    _updateView();
  }

  function _buildSlide(slide, idx) {
    const el = document.createElement('article');
    el.className = 'ob-slide';
    el.dataset.index = String(idx);

    const meta = document.createElement('div');
    meta.className = 'ob-slide-meta';

    const chip = document.createElement('span');
    chip.className = 'ob-step-chip';
     meta.appendChild(chip);

    const caption = document.createElement('span');
    caption.className = 'ob-step-caption';
     meta.appendChild(caption);

    el.appendChild(meta);

    const mediaWrap = document.createElement('div');
    mediaWrap.className = 'ob-media';

    if (slide.mediaUrl) {
      if (slide.mediaType === 'video') {
        const video = document.createElement('video');
        video.className = 'ob-media-asset';
        video.src = slide.mediaUrl;
        video.muted = true;
        video.loop = true;
        video.playsInline = true;
        video.preload = 'metadata';
        video.setAttribute('playsinline', '');
        mediaWrap.appendChild(video);
      } else {
        const img = document.createElement('img');
        img.className = 'ob-media-asset';
        img.src = slide.mediaUrl;
        img.alt = _resolveSlideTitle(slide, 'promoAlt');
        img.loading = idx === 0 ? 'eager' : 'lazy';
        mediaWrap.appendChild(img);
      }
    } else {
      const iconWrap = document.createElement('div');
      iconWrap.className = 'ob-icon-circle';
      const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
      svg.setAttribute('viewBox', '0 0 24 24');
      svg.setAttribute('width', '48');
      svg.setAttribute('height', '48');
      svg.setAttribute('fill', 'currentColor');
      svg.innerHTML = ICONS[slide.iconSvg] || ICONS.bolt;
      iconWrap.appendChild(svg);
      mediaWrap.appendChild(iconWrap);
    }
    el.appendChild(mediaWrap);

    const textWrap = document.createElement('div');
    textWrap.className = 'ob-text ob-copy-card';
    const h = document.createElement('h2');
    h.className = 'ob-title';
    h.textContent = _resolveSlideTitle(slide);
    textWrap.appendChild(h);
    const p = document.createElement('p');
    p.className = 'ob-desc';
    p.textContent = _resolveSlideDesc(slide);
    p.style.whiteSpace = 'pre-line';
    textWrap.appendChild(p);
    el.appendChild(textWrap);
    return el;
  }

  /* Slide navigation */
  function _goTo(idx) {
    _index = Math.max(0, Math.min(_slides.length - 1, idx));
    _updateView();
  }
  function _next() {
    if (_index >= _slides.length - 1) {
      /* After slides → promo (if available) → login */
      if (_introBlock && _introBlock.mediaUrl) _showPromoScreen();
      else _openPostOnboardingDestination();
      return;
    }
    _goTo(_index + 1);
  }
  function _prev() {
    if (_index > 0) _goTo(_index - 1);
  }

  function _updateView() {
    const allSlides = _overlay.querySelectorAll('.ob-slide');
    allSlides.forEach((s, i) => {
      s.classList.remove('ob-slide--active', 'ob-slide--prev', 'ob-slide--next');
      if (i === _index) {
        s.classList.add('ob-slide--active');
        const video = s.querySelector('video');
        if (video) { const p = video.play(); if (p && p.catch) p.catch(() => {}); }
      } else {
        s.classList.add(i < _index ? 'ob-slide--prev' : 'ob-slide--next');
        const video = s.querySelector('video');
        if (video) video.pause();
      }
    });

    const dots = _overlay.querySelectorAll('.ob-dot');
    dots.forEach((d, i) => d.classList.toggle('ob-dot--active', i === _index));

    const counter = document.getElementById('ob-counter');
    if (counter) {
      const current = String(_index + 1).padStart(2, '0');
      counter.textContent = _copy('stepLabel')
        .replace('{index}', current)
        .replace('{total}', String(_slides.length));
    }

    const nextBtn = document.getElementById('ob-btn-next');
    if (nextBtn) {
      const isLast = _index >= _slides.length - 1;
      nextBtn.innerHTML = isLast
        ? '<span>' + _copy('startNow') + '</span>' + _checkSvg()
        : '<span>' + _copy('next') + '</span>' + _arrowSvg();
      nextBtn.classList.toggle('ob-btn-next--finish', isLast);
    }
  }

  /* ================================================================
     PHASE 2 — PROMO / INTRO SHOWCASE
     ================================================================ */
  function _openPostOnboardingDestination() {
    if (Auth.isLoggedIn()) {
      _dismissFinal();
      return;
    }
    _showLoginScreen();
  }

  function _showPromoScreen() {
    _phase = 'promo';

    const oldContainer = _overlay.querySelector('.ob-container');
    if (oldContainer) {
      oldContainer.style.transition = 'opacity .35s ease, transform .35s ease';
      oldContainer.style.opacity = '0';
      oldContainer.style.transform = 'translateY(-30px) scale(.97)';
    }

    setTimeout(() => {
      _overlay.innerHTML = '';
      _overlay.appendChild(_buildPromoScreen());
      _bindKeyboard();
    }, 350);
  }

  function _buildPromoScreen() {
    const wrap = document.createElement('div');
    wrap.className = 'ob-promo';

    /* ── Media (fills most of the screen) ── */
    const mediaWrap = document.createElement('div');
    mediaWrap.className = 'ob-promo-media';

    if (_introBlock.mediaType === 'video') {
      const video = document.createElement('video');
      video.className = 'ob-promo-asset';
      video.src = _introBlock.mediaUrl;
      video.autoplay = true;
      video.muted = true;
      video.loop = true;
      video.playsInline = true;
      video.setAttribute('playsinline', '');
      video.preload = 'auto';
      mediaWrap.appendChild(video);
    } else {
      const img = document.createElement('img');
      img.className = 'ob-promo-asset';
      img.src = _introBlock.mediaUrl;
      img.alt = _resolveSlideTitle(_introBlock, 'promoAlt');
      mediaWrap.appendChild(img);
    }
    wrap.appendChild(mediaWrap);

    /* ── Bottom action bar (no text, just button) ── */
    const bottomBar = document.createElement('div');
    bottomBar.className = 'ob-promo-bottom';

    const continueBtn = document.createElement('button');
    continueBtn.className = 'ob-promo-continue';
    continueBtn.innerHTML = '<span>' + _copy('continue') + '</span>' + _arrowSvg();
    continueBtn.addEventListener('click', _openPostOnboardingDestination);
    bottomBar.appendChild(continueBtn);

    wrap.appendChild(bottomBar);

    return wrap;
  }

  /* ================================================================
     PHASE 3 — LOGIN SCREEN
     ================================================================ */
  function _showLoginScreen() {
    _phase = 'login';
    _markSeen();

    /* Animate current container / promo out */
    const oldEl = _overlay.querySelector('.ob-container') || _overlay.querySelector('.ob-promo');
    if (oldEl) {
      oldEl.style.transition = 'opacity .35s ease, transform .35s ease';
      oldEl.style.opacity = '0';
      oldEl.style.transform = 'translateY(-30px) scale(.97)';
    }

    setTimeout(() => {
      _overlay.innerHTML = '';
      _overlay.appendChild(_buildParticles());
      _overlay.appendChild(_buildLoginCard());
      _bindKeyboard();
    }, 350);
  }

  function _buildLoginCard() {
    const card = document.createElement('div');
    card.className = 'ob-container ob-login-card';

    /* ── Header icon ── */
    const headerIcon = document.createElement('div');
    headerIcon.className = 'ob-login-icon';
    const lockSvg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    lockSvg.setAttribute('viewBox', '0 0 24 24');
    lockSvg.setAttribute('width', '36');
    lockSvg.setAttribute('height', '36');
    lockSvg.setAttribute('fill', 'currentColor');
    lockSvg.innerHTML = '<path d="M18 8h-1V6c0-2.76-2.24-5-5-5S7 3.24 7 6v2H6c-1.1 0-2 .9-2 2v10c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V10c0-1.1-.9-2-2-2zm-6 9c-1.1 0-2-.9-2-2s.9-2 2-2 2 .9 2 2-.9 2-2 2zm3.1-9H8.9V6c0-1.71 1.39-3.1 3.1-3.1s3.1 1.39 3.1 3.1v2z"/>';
    headerIcon.appendChild(lockSvg);
    card.appendChild(headerIcon);

    /* ── Title ── */
    const title = document.createElement('h2');
    title.className = 'ob-login-title';
    title.textContent = _copy('signInTitle');
    card.appendChild(title);

    const subtitle = document.createElement('p');
    subtitle.className = 'ob-login-subtitle';
    subtitle.textContent = _copy('signInSubtitle');
    card.appendChild(subtitle);

    /* ── Phone input ── */
    const fieldWrap = document.createElement('div');
    fieldWrap.className = 'ob-login-field';

    const inputWrap = document.createElement('div');
    inputWrap.className = 'ob-login-input-wrap';

    const input = document.createElement('input');
    input.type = 'tel';
    input.id = 'ob-phone-input';
    input.className = 'ob-login-input';
    input.placeholder = '05XXXXXXXX';
    input.maxLength = 10;
    input.pattern = '05[0-9]{8}';
    input.dir = 'ltr';
    input.autocomplete = 'tel';
    input.inputMode = 'numeric';
    inputWrap.appendChild(input);

    fieldWrap.appendChild(inputWrap);

    const errorEl = document.createElement('div');
    errorEl.className = 'ob-login-error';
    errorEl.id = 'ob-login-error';
    fieldWrap.appendChild(errorEl);

    card.appendChild(fieldWrap);

    /* ── Send OTP button ── */
    const sendBtn = document.createElement('button');
    sendBtn.className = 'ob-login-submit';
    sendBtn.id = 'ob-login-submit';
    sendBtn.innerHTML = '<span>' + _copy('sendOtp') + '</span>';
    sendBtn.addEventListener('click', _handleSendOtp);
    card.appendChild(sendBtn);

    /* ── Cooldown display ── */
    const cooldown = document.createElement('div');
    cooldown.className = 'ob-login-cooldown';
    cooldown.id = 'ob-login-cooldown';
    card.appendChild(cooldown);

    /* ── Divider ── */
    const divider = document.createElement('div');
    divider.className = 'ob-login-divider';
    const divLine1 = document.createElement('span');
    const divText = document.createElement('span');
    divText.textContent = _copy('divider');
    const divLine2 = document.createElement('span');
    divider.appendChild(divLine1);
    divider.appendChild(divText);
    divider.appendChild(divLine2);
    card.appendChild(divider);

    /* ── Guest button ── */
    const guestBtn = document.createElement('button');
    guestBtn.className = 'ob-login-guest';
    guestBtn.innerHTML = _guestSvg() + '<span>' + _copy('guest') + '</span>';
    guestBtn.addEventListener('click', _dismissFinal);
    card.appendChild(guestBtn);

    /* Enter key */
    input.addEventListener('input', () => {
      const normalized = _normalizePhone05(input.value);
      if (input.value !== normalized) {
        input.value = normalized;
      }
      errorEl.textContent = '';
    });

    input.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') _handleSendOtp();
    });

    /* Auto-focus with delay for animation */
    setTimeout(() => { if (input) input.focus(); }, 600);

    return card;
  }

  /* ── OTP send ── */
  async function _handleSendOtp() {
    const input = document.getElementById('ob-phone-input');
    const errorEl = document.getElementById('ob-login-error');
    const submitBtn = document.getElementById('ob-login-submit');
    if (!input || !submitBtn) return;

    const phone = _normalizePhone05(input.value);
    errorEl.textContent = '';

    if (input.value !== phone) {
      input.value = phone;
    }

    /* Validate */
    if (!phone || !/^05\d{8}$/.test(phone)) {
      errorEl.textContent = _copy('invalidPhone');
      _shakeElement(input.parentElement);
      return;
    }

    /* Loading */
    submitBtn.disabled = true;
    submitBtn.innerHTML = '<span class="ob-login-spinner"></span><span>' + _copy('sending') + '</span>';

    try {
      const res = await ApiClient.request('/api/accounts/otp/send/', {
        method: 'POST',
        body: JSON.stringify({ phone }),
        headers: { 'Content-Type': 'application/json' },
      });

      if (res.ok) {
        /* Store phone and dev code (dev only) */
        try {
          sessionStorage.setItem('nw_auth_phone', phone);
          localStorage.setItem('nw_auth_phone', phone);
          if (res.data && res.data.dev_code) {
            localStorage.setItem('nw_auth_dev_code', res.data.dev_code);
          }
        } catch (_) {}

        /* Start cooldown */
        const cooldownSec = (res.data && res.data.cooldown_seconds) || 60;
        _startCooldown(cooldownSec);

        /* Dismiss overlay and navigate to TwoFA */
        _dismissFinal();
        window.location.href = '/twofa/?next=/';
      } else {
        const msg = (res.data && (res.data.detail || res.data.error || res.data.phone))
          || _copy('sendFailed');
        errorEl.textContent = typeof msg === 'string' ? msg : String(msg);
        submitBtn.disabled = false;
        submitBtn.innerHTML = '<span>' + _copy('sendOtp') + '</span>';
      }
    } catch (_) {
      errorEl.textContent = _copy('connectionFailed');
      submitBtn.disabled = false;
      submitBtn.innerHTML = '<span>' + _copy('sendOtp') + '</span>';
    }
  }

  function _startCooldown(seconds) {
    _otpCooldownEnd = Date.now() + seconds * 1000;
    const cooldownEl = document.getElementById('ob-login-cooldown');
    const submitBtn = document.getElementById('ob-login-submit');
    if (!cooldownEl) return;

    function tick() {
      const remaining = Math.max(0, Math.ceil((_otpCooldownEnd - Date.now()) / 1000));
      if (remaining <= 0) {
        cooldownEl.textContent = '';
        if (submitBtn) {
          submitBtn.disabled = false;
          submitBtn.innerHTML = '<span>' + _copy('resend') + '</span>';
        }
        clearInterval(_otpCooldownTimer);
        return;
      }
      const m = Math.floor(remaining / 60);
      const s = remaining % 60;
      const time = (m > 0 ? m + ':' : '') + String(s).padStart(2, '0');
      cooldownEl.textContent = _copy('resendAfter').replace('{time}', time);
    }
    tick();
    _otpCooldownTimer = setInterval(tick, 1000);
  }

  function _resolveSlideTitle(slide, fallbackKey) {
    if (!slide) return fallbackKey ? _copy(fallbackKey) : '';
    return _resolveText(slide.title_ar, slide.title_en, fallbackKey);
  }

  function _resolveSlideDesc(slide, fallbackKey) {
    if (!slide) return fallbackKey ? _copy(fallbackKey) : '';
    return _resolveText(slide.desc_ar, slide.desc_en, fallbackKey);
  }

  function _shakeElement(el) {
    if (!el) return;
    el.style.animation = 'none';
    el.offsetHeight; /* reflow */
    el.style.animation = 'ob-shake .4s ease';
  }

  /* ================================================================
     SHARED UTILITIES
     ================================================================ */
  function _buildParticles() {
    const particles = document.createElement('div');
    particles.className = 'ob-particles';
    for (let i = 0; i < 6; i++) {
      const p = document.createElement('span');
      p.className = 'ob-particle';
      p.style.setProperty('--i', String(i));
      particles.appendChild(p);
    }
    return particles;
  }

  function _bindSwipe(el) {
    el.addEventListener('touchstart', (e) => {
      _touchStartX = e.touches[0].clientX;
    }, { passive: true });
    el.addEventListener('touchend', (e) => {
      const diff = _touchStartX - e.changedTouches[0].clientX;
      if (Math.abs(diff) > 50) {
        if (diff > 0) _next();
        else _prev();
      }
    }, { passive: true });
  }

  function _bindKeyboard() {
    if (_overlay._keyHandler) {
      document.removeEventListener('keydown', _overlay._keyHandler);
    }
    _overlay._keyHandler = (e) => {
      if (_phase === 'login') {
        if (e.key === 'Escape') _dismissFinal();
        return;
      }
      if (_phase === 'promo') {
        if (e.key === 'Enter' || e.key === ' ') _openPostOnboardingDestination();
        else if (e.key === 'Escape') _dismissFinal();
        return;
      }
      if (e.key === 'ArrowLeft') _next();
      else if (e.key === 'ArrowRight') _prev();
      else if (e.key === 'Escape') _dismiss();
    };
    document.addEventListener('keydown', _overlay._keyHandler);
  }

  function _arrowSvg() {
    return '<svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M15.41 7.41L14 6l-6 6 6 6 1.41-1.41L10.83 12z"/></svg>';
  }
  function _checkSvg() {
    return '<svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41L9 16.17z"/></svg>';
  }
  function _guestSvg() {
    return '<svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><path d="M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z"/></svg>';
  }

  /* ── dismiss (after slides → go to login) ── */
  function _dismiss() {
    _dismissFinal({ markSeen: true });
  }

  /* ── final dismiss (remove overlay completely) ── */
  function _dismissFinal(options = {}) {
    const { markSeen = true } = options;
    if (markSeen) _markSeen();
    if (_otpCooldownTimer) clearInterval(_otpCooldownTimer);
    document.body.style.overflow = '';
    _setHomeLockedState(false);
    if (!_overlay) return;

    if (_overlay._keyHandler) {
      document.removeEventListener('keydown', _overlay._keyHandler);
    }

    _overlay.classList.remove('ob-overlay--visible');
    _overlay.classList.add('ob-overlay--exit');

    _overlay.addEventListener('transitionend', () => {
      if (_overlay && _overlay.parentNode) _overlay.parentNode.removeChild(_overlay);
      _overlay = null;
    }, { once: true });

    setTimeout(() => {
      if (_overlay && _overlay.parentNode) {
        _overlay.parentNode.removeChild(_overlay);
        _overlay = null;
      }
    }, 900);
  }

  /* ── boot ── */
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  return { init };
})();
