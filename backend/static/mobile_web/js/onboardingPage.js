/* ===================================================================
   onboardingPage.js — Onboarding slider with optional media from CMS
   =================================================================== */
'use strict';

const OnboardingPage = (() => {
  const DEFAULT_SLIDES = [
    {
      key: 'onboarding_first_time',
      icon: '🧩',
      title: 'مرحباً بك في نوافذ',
      desc: 'منصتك الأولى لربط العملاء بمقدمي الخدمات.',
      media_url: '',
      media_type: '',
    },
    {
      key: 'onboarding_intro',
      icon: '🤝',
      title: 'لكل عميل ومقدم خدمة',
      desc: 'اختر خدماتك أو اعرض خبراتك وابدأ التواصل مباشرة.',
      media_url: '',
      media_type: '',
    },
    {
      key: 'onboarding_static_final',
      icon: '⚡',
      title: 'انطلق الآن',
      desc: 'تجربة سلسة وسريعة للوصول لما تحتاجه خلال ثوانٍ.',
      media_url: '',
      media_type: '',
    },
  ];

  let _index = 0;
  let _slidesData = DEFAULT_SLIDES.map((item) => ({ ...item }));

  function init() {
    _bind();
    _renderSlides();
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
    if (!res.ok || !res.data || typeof res.data !== 'object') return;

    const blocks = res.data.blocks || {};
    _slidesData = DEFAULT_SLIDES.map((slide) => _mergeSlideWithBlock(slide, blocks[slide.key]));
    _renderSlides();
  }

  function _mergeSlideWithBlock(fallback, block) {
    if (!block || typeof block !== 'object') return { ...fallback };

    const title = String(block.title_ar || '').trim();
    const desc = String(block.body_ar || '').trim();
    const mediaUrl = ApiClient.mediaUrl(block.media_url || '');
    const mediaType = String(block.media_type || '').trim().toLowerCase();

    return {
      ...fallback,
      title: title || fallback.title,
      desc: desc || fallback.desc,
      media_url: mediaUrl || fallback.media_url,
      media_type: mediaType || fallback.media_type,
    };
  }

  function _setIndex(nextIdx) {
    _index = Math.max(0, Math.min(_slidesData.length - 1, nextIdx));
    _render();
  }

  function _next() {
    if (_index >= _slidesData.length - 1) {
      _finish();
      return;
    }
    _setIndex(_index + 1);
  }

  function _finish() {
    window.location.href = '/';
  }

  function _renderSlides() {
    const stage = document.getElementById('onboarding-stage');
    const dots = document.getElementById('onboard-dots');
    if (!stage || !dots) return;

    stage.innerHTML = '';
    dots.innerHTML = '';

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

  function _buildSlide(slide, idx) {
    const article = UI.el('article', {
      className: 'onboard-slide' + (idx === _index ? ' active' : ' hidden'),
      'data-index': String(idx),
    });

    article.appendChild(_buildMedia(slide));
    article.appendChild(UI.el('h1', { textContent: slide.title || '' }));
    article.appendChild(UI.el('p', { textContent: slide.desc || '', style: { whiteSpace: 'pre-line' } }));
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
      btn.textContent = _index >= _slidesData.length - 1 ? '✓' : '←';
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  return {};
})();
