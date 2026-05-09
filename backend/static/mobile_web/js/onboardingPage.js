/* ===================================================================
   onboardingPage.js — Onboarding slider with optional media from CMS
   =================================================================== */
'use strict';

const OnboardingPage = (() => {
  const PREVIEW_KEY = 'app_intro_preview';
  const COPY = {
    ar: {
      pageTitle: 'نوافــذ — البداية',
      loadingTitle: 'جاري تحميل شاشة البداية',
      loadingMessage: 'يتم جلب المحتوى مباشرة من لوحة التحكم.',
      loadFailed: 'تعذر تحميل شاشة البداية من الخادم.',
      unconfigured: 'محتوى شاشة البداية غير مُعد في لوحة التحكم.',
      skip: 'تخطي',
      next: 'التالي',
      login: 'دخول',
      home: 'الرئيسية',
      retry: 'إعادة المحاولة',
      startNow: 'ابدأ الآن',
      signIn: 'تسجيل الدخول',
      previewChip: 'بروفة التطبيق',
      previewNote: 'آخر خطوة قبل تسجيل الدخول',
      previewTitle: 'تعرف على نوافذ',
      previewDesc: 'واجهة سريعة وواضحة تساعدك تبدأ مباشرة من الويب.',
      stepLabel: 'الشاشة {index}',
      readyNote: 'جاهز للانطلاق',
      quickTour: 'جولة تعريفية سريعة',
      statusTitle: 'شاشة البداية',
      imageBadge: 'صورة',
      videoBadge: 'فيديو',
      mediaAlt: 'وسائط شاشة البداية',
    },
    en: {
      pageTitle: 'Nawafeth — Getting Started',
      loadingTitle: 'Loading onboarding',
      loadingMessage: 'Content is being loaded directly from the dashboard.',
      loadFailed: 'Failed to load onboarding from the server.',
      unconfigured: 'Onboarding content is not configured in the dashboard yet.',
      skip: 'Skip',
      next: 'Next',
      login: 'Sign in',
      home: 'Home',
      retry: 'Try again',
      startNow: 'Start now',
      signIn: 'Sign in',
      previewChip: 'App preview',
      previewNote: 'Final step before sign-in',
      previewTitle: 'Get to know Nawafeth',
      previewDesc: 'A fast, clear interface that helps you start directly from the web.',
      stepLabel: 'Screen {index}',
      readyNote: 'Ready to begin',
      quickTour: 'Quick guided tour',
      statusTitle: 'Onboarding',
      imageBadge: 'Image',
      videoBadge: 'Video',
      mediaAlt: 'Onboarding media',
    },
  };
  const SLIDE_DEFINITIONS = [
    {
      key: 'onboarding_first_time',
      icon: '🧩',
    },
    {
      key: 'onboarding_intro',
      icon: '🤝',
    },
    {
      key: 'onboarding_get_started',
      icon: '⚡',
    },
  ];

  let _index = 0;
  let _slidesData = [];
  let _introBlock = null;
  let _phase = 'slides';
  let _statusKey = 'loadingMessage';
  let _statusRetryable = false;
  let _statusLoading = true;

  function init() {
    _bind();
    window.addEventListener('nawafeth:languagechange', _handleLanguageChange);
    _renderLoading();
    _loadSlidesFromApi();
  }

  function _bind() {
    const nextBtn = document.getElementById('btn-onboard-next');
    const skipBtn = document.getElementById('btn-onboard-skip');
    const dotsWrap = document.getElementById('onboard-dots');

    if (nextBtn) nextBtn.addEventListener('click', _next);
    if (skipBtn) skipBtn.addEventListener('click', _finish);
    _applyStaticTemplateCopy();
    if (dotsWrap) {
      dotsWrap.addEventListener('click', (event) => {
        const dot = event.target.closest('.onboard-dot');
        if (!dot) return;
        const idx = Number(dot.dataset.index || 0);
        _setIndex(idx);
      });
    }
  }

  async function _loadSlidesFromApi() {
    const res = await ApiClient.get('/api/content/public/');
    if (!res.ok || !res.data || typeof res.data !== 'object') {
      _renderStatus('loadFailed', true);
      return;
    }

    const blocks = res.data.blocks || {};
    _introBlock = _mergePreviewBlock(blocks[PREVIEW_KEY]);
    _slidesData = SLIDE_DEFINITIONS
      .map((slide) => _mergeSlideWithBlock(slide, blocks[slide.key]))
      .filter((slide) => slide && (_resolveSlideTitle(slide) || _resolveSlideDesc(slide)));

    if (!_slidesData.length) {
      _renderStatus('unconfigured', false);
      return;
    }

    _renderSlides();
  }

  function _mergeSlideWithBlock(fallback, block) {
    if (!block || typeof block !== 'object') return null;

    const titleAr = String(block.title_ar || '').trim();
    const titleEn = String(block.title_en || '').trim();
    const descAr = String(block.body_ar || '').trim();
    const descEn = String(block.body_en || '').trim();
    if (!titleAr && !titleEn && !descAr && !descEn) return null;
    const mediaUrl = ApiClient.mediaUrl(block.media_url || '');
    const mediaType = String(block.media_type || '').trim().toLowerCase();

    return {
      ...fallback,
      title_ar: titleAr,
      title_en: titleEn,
      desc_ar: descAr,
      desc_en: descEn,
      media_url: mediaUrl || '',
      media_type: mediaType || '',
    };
  }

  function _mergePreviewBlock(block) {
    if (!block || typeof block !== 'object') return null;

    const titleAr = String(block.title_ar || '').trim();
    const titleEn = String(block.title_en || '').trim();
    const descAr = String(block.body_ar || '').trim();
    const descEn = String(block.body_en || '').trim();
    const mediaUrl = ApiClient.mediaUrl(block.media_url || '');
    const mediaType = String(block.media_type || '').trim().toLowerCase();

    if (!titleAr && !titleEn && !descAr && !descEn && !mediaUrl) return null;

    return {
      key: PREVIEW_KEY,
      icon: '📱',
      title_ar: titleAr,
      title_en: titleEn,
      desc_ar: descAr,
      desc_en: descEn,
      media_url: mediaUrl || '',
      media_type: mediaType || '',
    };
  }

  function _setIndex(nextIdx) {
    _index = Math.max(0, Math.min(_slidesData.length - 1, nextIdx));
    _render();
  }

  function _next() {
    if (_phase === 'preview') {
      _finish();
      return;
    }

    if (_index >= _slidesData.length - 1) {
      if (_introBlock) {
        _renderPreview();
        return;
      }
      _finish();
      return;
    }
    _setIndex(_index + 1);
  }

  function _finish() {
    if (Auth.isLoggedIn()) {
      window.location.href = '/';
      return;
    }
    window.location.href = '/login/';
  }

  function _renderSlides() {
    _phase = 'slides';
    const stage = document.getElementById('onboarding-stage');
    const dots = document.getElementById('onboard-dots');
    const nextBtn = document.getElementById('btn-onboard-next');
    const skipBtn = document.getElementById('btn-onboard-skip');
    if (!stage || !dots) return;

    stage.innerHTML = '';
    dots.innerHTML = '';

    if (skipBtn) skipBtn.textContent = _copy('skip');
    if (nextBtn) nextBtn.textContent = _copy('next');

    _slidesData.forEach((slide, idx) => {
      stage.appendChild(_buildSlide(slide, idx));
      dots.appendChild(
        UI.el('span', {
          className: 'onboard-dot' + (idx === _index ? ' active' : ''),
          'data-index': String(idx),
        }),
      );
    });

    if (_index >= _slidesData.length) {
      _index = _slidesData.length - 1;
    }
    _render();
  }

  function _renderPreview() {
    const stage = document.getElementById('onboarding-stage');
    const dots = document.getElementById('onboard-dots');
    const nextBtn = document.getElementById('btn-onboard-next');
    const skipBtn = document.getElementById('btn-onboard-skip');
    if (!stage || !dots || !_introBlock) {
      _finish();
      return;
    }

    _phase = 'preview';
    stage.innerHTML = '';
    dots.innerHTML = '';

    stage.appendChild(
      UI.el('article', { className: 'onboard-slide active', 'data-index': 'preview' }, [
        _buildMedia(_introBlock),
        UI.el('div', { className: 'onboard-copy-card' }, [
          UI.el('h1', { textContent: _resolveSlideTitle(_introBlock, 'previewTitle') }),
          UI.el('p', {
            textContent: _resolveSlideDesc(_introBlock, 'previewDesc'),
            style: { whiteSpace: 'pre-line' },
          }),
        ]),
      ]),
    );

    if (nextBtn) nextBtn.textContent = _copy('signIn');
    if (skipBtn) skipBtn.textContent = _copy('skip');
  }

  function _renderLoading() {
    _phase = 'slides';
    _renderStatus('loadingMessage', false, true);
  }

  function _renderStatus(messageKey, retryable, loading) {
    const stage = document.getElementById('onboarding-stage');
    const dots = document.getElementById('onboard-dots');
    const nextBtn = document.getElementById('btn-onboard-next');
    const skipBtn = document.getElementById('btn-onboard-skip');
    if (!stage || !dots) return;

    _statusKey = messageKey;
    _statusRetryable = !!retryable;
    _statusLoading = !!loading;

    stage.innerHTML = '';
    dots.innerHTML = '';

    stage.appendChild(
      UI.el('article', { className: 'onboard-status-card' }, [
        UI.el('div', {
          className: 'onboard-status-icon',
          textContent: loading ? '⟳' : '✦',
        }),
        UI.el('h1', { textContent: loading ? _copy('loadingTitle') : _copy('statusTitle') }),
        UI.el('p', { textContent: _copy(messageKey) }),
        retryable
          ? UI.el('button', {
              className: 'onboard-status-action',
              textContent: _copy('retry'),
              onclick: () => {
                _renderLoading();
                _loadSlidesFromApi();
              },
            })
          : null,
      ].filter(Boolean)),
    );

    if (nextBtn) nextBtn.textContent = _copy('login');
    if (skipBtn) skipBtn.textContent = retryable ? _copy('home') : _copy('skip');
  }

  function _buildSlide(slide, idx) {
    const article = UI.el('article', {
      className: 'onboard-slide' + (idx === _index ? ' active' : ' hidden'),
      'data-index': String(idx),
    });

    article.appendChild(_buildMedia(slide));

    article.appendChild(UI.el('div', { className: 'onboard-copy-card' }, [
      UI.el('h1', { textContent: _resolveSlideTitle(slide) }),
      UI.el('p', { textContent: _resolveSlideDesc(slide), style: { whiteSpace: 'pre-line' } }),
    ]));
    return article;
  }

  function _buildMedia(slide) {
    const wrap = UI.el('div', { className: 'onboard-media' });
    const mediaType = String(slide.media_type || '').toLowerCase();
    const mediaUrl = String(slide.media_url || '').trim();

    if (!mediaUrl) {
      wrap.appendChild(UI.el('div', { className: 'onboard-icon', textContent: slide.icon || '✨' }));
      return wrap;
    }

    if (mediaType === 'video') {
      const video = UI.el('video', {
        className: 'onboard-media-video',
        src: mediaUrl,
        muted: '',
        loop: '',
        autoplay: '',
        playsinline: '',
        preload: 'metadata',
      });
      video.muted = true;
      video.autoplay = true;
      video.loop = true;
      video.playsInline = true;
      wrap.appendChild(video);
      return wrap;
    }

    wrap.appendChild(UI.el('img', {
      className: 'onboard-media-image',
      src: mediaUrl,
      alt: _resolveSlideTitle(slide, 'mediaAlt'),
      loading: 'lazy',
    }));
    return wrap;
  }

  function _render() {
    const slides = Array.from(document.querySelectorAll('.onboard-slide'));
    const dots = Array.from(document.querySelectorAll('.onboard-dot'));

    slides.forEach((slide, idx) => {
      const isActive = idx === _index;
      slide.classList.toggle('hidden', !isActive);
      slide.classList.toggle('active', isActive);

      slide.querySelectorAll('video').forEach((video) => {
        if (isActive) {
          const playPromise = video.play();
          if (playPromise && typeof playPromise.catch === 'function') playPromise.catch(() => {});
        } else {
          video.pause();
        }
      });
    });

    dots.forEach((dot, idx) => {
      dot.classList.toggle('active', idx === _index);
    });

    const btn = document.getElementById('btn-onboard-next');
    if (btn) {
      btn.textContent = _index >= _slidesData.length - 1 ? _copy('startNow') : _copy('next');
      btn.setAttribute('aria-label', btn.textContent);
    }
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

  function _resolveField(primary, secondary, fallbackKey) {
    const first = String(primary || '').trim();
    if (first) return first;
    const second = String(secondary || '').trim();
    if (second) return second;
    return fallbackKey ? _copy(fallbackKey) : '';
  }

  function _resolveSlideTitle(slide, fallbackKey) {
    if (!slide) return fallbackKey ? _copy(fallbackKey) : '';
    if (_currentLang() === 'en') {
      return _resolveField(slide.title_en, slide.title_ar, fallbackKey);
    }
    return _resolveField(slide.title_ar, slide.title_en, fallbackKey);
  }

  function _resolveSlideDesc(slide, fallbackKey) {
    if (!slide) return fallbackKey ? _copy(fallbackKey) : '';
    if (_currentLang() === 'en') {
      return _resolveField(slide.desc_en, slide.desc_ar, fallbackKey);
    }
    return _resolveField(slide.desc_ar, slide.desc_en, fallbackKey);
  }

  function _applyStaticTemplateCopy() {
    document.title = _copy('pageTitle');
    const loadingTitle = document.getElementById('onboarding-loading-title');
    const loadingDesc = document.getElementById('onboarding-loading-desc');
    const nextBtn = document.getElementById('btn-onboard-next');
    const skipBtn = document.getElementById('btn-onboard-skip');
    if (loadingTitle) loadingTitle.textContent = _copy('loadingTitle');
    if (loadingDesc) loadingDesc.textContent = _copy('loadingMessage');
    if (skipBtn) skipBtn.textContent = _copy('skip');
    if (nextBtn) {
      nextBtn.textContent = _copy('next');
      nextBtn.setAttribute('aria-label', _copy('next'));
    }
  }

  function _handleLanguageChange() {
    _applyStaticTemplateCopy();
    if (_phase === 'preview' && _introBlock) {
      _renderPreview();
      return;
    }
    if (_slidesData.length) {
      _renderSlides();
      return;
    }
    _renderStatus(_statusKey, _statusRetryable, _statusLoading);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  return {};
})();
