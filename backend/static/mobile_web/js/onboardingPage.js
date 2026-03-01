/* ===================================================================
   onboardingPage.js — Simple onboarding slider
   =================================================================== */
'use strict';

const OnboardingPage = (() => {
  let _index = 0;
  let _total = 0;

  function init() {
    const slides = _slides();
    _total = slides.length;
    if (!_total) return;

    const nextBtn = document.getElementById('btn-onboard-next');
    const skipBtn = document.getElementById('btn-onboard-skip');
    const dotsWrap = document.getElementById('onboard-dots');

    if (nextBtn) nextBtn.addEventListener('click', _next);
    if (skipBtn) skipBtn.addEventListener('click', _finish);
    if (dotsWrap) {
      dotsWrap.addEventListener('click', (e) => {
        const dot = e.target.closest('.onboard-dot');
        if (!dot) return;
        const idx = Number(dot.dataset.index || 0);
        _setIndex(idx);
      });
    }

    _render();
  }

  function _slides() {
    return Array.from(document.querySelectorAll('.onboard-slide'));
  }

  function _dots() {
    return Array.from(document.querySelectorAll('.onboard-dot'));
  }

  function _setIndex(nextIdx) {
    _index = Math.max(0, Math.min(_total - 1, nextIdx));
    _render();
  }

  function _next() {
    if (_index >= _total - 1) {
      _finish();
      return;
    }
    _setIndex(_index + 1);
  }

  function _finish() {
    window.location.href = '/';
  }

  function _render() {
    _slides().forEach((slide, idx) => {
      slide.classList.toggle('active', idx === _index);
    });
    _dots().forEach((dot, idx) => {
      dot.classList.toggle('active', idx === _index);
    });

    const btn = document.getElementById('btn-onboard-next');
    if (btn) {
      btn.textContent = _index >= _total - 1 ? '✓' : '←';
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  return {};
})();
