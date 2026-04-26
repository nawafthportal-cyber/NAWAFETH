/* ===================================================================
   onboardingPage.js — Onboarding slider with optional media from CMS
   =================================================================== */
'use strict';

const OnboardingPage = (() => {
  const PREVIEW_KEY = 'app_intro_preview';
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

  function init() {
    _bind();
    _renderLoading();
    _loadSlidesFromApi();
  }

  function _bind() {
    const nextBtn = document.getElementById('btn-onboard-next');
    const skipBtn = document.getElementById('btn-onboard-skip');
    const dotsWrap = document.getElementById('onboard-dots');

    if (nextBtn) nextBtn.addEventListener('click', _next);
    if (skipBtn) skipBtn.addEventListener('click', _finish);
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
      _renderStatus('تعذر تحميل شاشة البداية من الخادم.', true);
      return;
    }

    const blocks = res.data.blocks || {};
    _introBlock = _mergePreviewBlock(blocks[PREVIEW_KEY]);
    _slidesData = SLIDE_DEFINITIONS
      .map((slide) => _mergeSlideWithBlock(slide, blocks[slide.key]))
      .filter((slide) => slide && slide.title && slide.desc);

    if (!_slidesData.length) {
      _renderStatus('محتوى شاشة البداية غير مُعد في لوحة التحكم.', false);
      return;
    }

    _renderSlides();
  }

  function _mergeSlideWithBlock(fallback, block) {
    if (!block || typeof block !== 'object') return null;

    const title = String(block.title_ar || '').trim();
    const desc = String(block.body_ar || '').trim();
    if (!title && !desc) return null;
    const mediaUrl = ApiClient.mediaUrl(block.media_url || '');
    const mediaType = String(block.media_type || '').trim().toLowerCase();

    return {
      ...fallback,
      title,
      desc,
      media_url: mediaUrl || '',
      media_type: mediaType || '',
    };
  }

  function _mergePreviewBlock(block) {
    if (!block || typeof block !== 'object') return null;

    const title = String(block.title_ar || '').trim();
    const desc = String(block.body_ar || '').trim();
    const mediaUrl = ApiClient.mediaUrl(block.media_url || '');
    const mediaType = String(block.media_type || '').trim().toLowerCase();

    if (!title && !desc && !mediaUrl) return null;

    return {
      key: PREVIEW_KEY,
      icon: '📱',
      title,
      desc,
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

    if (skipBtn) skipBtn.textContent = 'تخطي';
    if (nextBtn) nextBtn.textContent = 'التالي';

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
        UI.el('div', { className: 'onboard-slide-meta' }, [
          UI.el('span', {
            className: 'onboard-step-chip',
            textContent: 'بروفة التطبيق',
          }),
          UI.el('span', {
            className: 'onboard-step-note',
            textContent: 'آخر خطوة قبل تسجيل الدخول',
          }),
        ]),
        _buildMedia(_introBlock),
        UI.el('div', { className: 'onboard-copy-card' }, [
          UI.el('h1', { textContent: _introBlock.title || 'تعرف على نوافذ' }),
          UI.el('p', {
            textContent: _introBlock.desc || 'واجهة سريعة وواضحة تساعدك تبدأ مباشرة من الويب.',
            style: { whiteSpace: 'pre-line' },
          }),
        ]),
      ]),
    );

    if (nextBtn) nextBtn.textContent = 'تسجيل الدخول';
    if (skipBtn) skipBtn.textContent = 'تخطي';
  }

  function _renderLoading() {
    _phase = 'slides';
    _renderStatus('يتم جلب المحتوى مباشرة من لوحة التحكم.', false, true);
  }

  function _renderStatus(message, retryable, loading) {
    const stage = document.getElementById('onboarding-stage');
    const dots = document.getElementById('onboard-dots');
    const nextBtn = document.getElementById('btn-onboard-next');
    const skipBtn = document.getElementById('btn-onboard-skip');
    if (!stage || !dots) return;

    stage.innerHTML = '';
    dots.innerHTML = '';

    stage.appendChild(
      UI.el('article', { className: 'onboard-status-card' }, [
        UI.el('div', {
          className: 'onboard-status-icon',
          textContent: loading ? '⟳' : '✦',
        }),
        UI.el('h1', { textContent: loading ? 'جاري تحميل شاشة البداية' : 'شاشة البداية' }),
        UI.el('p', { textContent: message }),
        retryable
          ? UI.el('button', {
              className: 'onboard-status-action',
              textContent: 'إعادة المحاولة',
              onclick: () => {
                _renderLoading();
                _loadSlidesFromApi();
              },
            })
          : null,
      ].filter(Boolean)),
    );

    if (nextBtn) nextBtn.textContent = 'دخول';
    if (skipBtn) skipBtn.textContent = retryable ? 'الرئيسية' : 'تخطي';
  }

  function _buildSlide(slide, idx) {
    const article = UI.el('article', {
      className: 'onboard-slide' + (idx === _index ? ' active' : ' hidden'),
      'data-index': String(idx),
    });

    article.appendChild(UI.el('div', { className: 'onboard-slide-meta' }, [
      UI.el('span', {
        className: 'onboard-step-chip',
        textContent: `الشاشة ${idx + 1}`,
      }),
      UI.el('span', {
        className: 'onboard-step-note',
        textContent: idx >= _slidesData.length - 1 ? 'جاهز للانطلاق' : 'جولة تعريفية سريعة',
      }),
    ]));
    article.appendChild(_buildMedia(slide));

    article.appendChild(UI.el('div', { className: 'onboard-copy-card' }, [
      UI.el('h1', { textContent: slide.title || '' }),
      UI.el('p', { textContent: slide.desc || '', style: { whiteSpace: 'pre-line' } }),
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
      wrap.appendChild(UI.el('span', { className: 'onboard-media-badge', textContent: 'فيديو' }));
      return wrap;
    }

    wrap.appendChild(UI.el('img', {
      className: 'onboard-media-image',
      src: mediaUrl,
      alt: slide.title || 'onboarding media',
      loading: 'lazy',
    }));
    wrap.appendChild(UI.el('span', { className: 'onboard-media-badge', textContent: 'صورة' }));
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
      btn.textContent = _index >= _slidesData.length - 1 ? 'ابدأ الآن' : 'التالي';
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  return {};
})();
