/* ===================================================================
   addServicePage.js — Add Service hub page controller
   GET /api/providers/categories/
   =================================================================== */
'use strict';

const AddServicePage = (() => {
  function init() {
    if (_guardProviderMode()) return;
    _bindAuthRequiredLinks();
    _fetchCategories();
  }

  function _guardProviderMode() {
    if (!Auth || typeof Auth.ensureServiceRequestAccess !== 'function') return;
    if (!Auth.ensureServiceRequestAccess({
      gateId: 'add-service-provider-block',
      contentId: 'add-service-client-content',
      target: '/add-service/',
      title: 'إنشاء الطلبات متاح في وضع العميل',
      description: 'أنت تستخدم المنصة الآن بوضع مقدم الخدمة، لذلك تم إيقاف مسارات طلب الخدمات الجديدة حتى لا تختلط أدوات المزود بمسارات العميل.',
      note: 'بدّل نوع الحساب إلى عميل الآن، ثم ستظهر لك جميع مسارات الطلب مباشرة في نفس الصفحة.',
      switchLabel: 'التبديل إلى عميل',
      profileLabel: 'فتح نافذتي',
    })) return true;
    return false;
  }

  function _bindAuthRequiredLinks() {
    document.querySelectorAll('a[data-auth-required="true"]').forEach((link) => {
      link.addEventListener('click', (event) => {
        if (Auth && typeof Auth.isServiceRequestBlockedForCurrentMode === 'function' && Auth.isServiceRequestBlockedForCurrentMode()) {
          event.preventDefault();
          Auth.renderProviderRequestBlock({
            gateId: 'add-service-provider-block',
            contentId: 'add-service-client-content',
            target: '/add-service/',
            title: 'مسارات الطلب غير متاحة في وضع مقدم الخدمة',
            description: 'لإنشاء طلب عاجل أو طلب عروض أسعار أو أي طلب خدمة جديد، بدّل نوع الحساب إلى عميل أولًا.',
            note: 'بعد التبديل ستتمكن من متابعة نفس المسار بدون تسجيل خروج.',
            switchLabel: 'التبديل إلى عميل',
            profileLabel: 'الذهاب إلى نافذتي',
          });
          return;
        }
        const serverAuth = window.NAWAFETH_SERVER_AUTH || null;
        const isLoggedIn = !!(
          (window.Auth && typeof Auth.isLoggedIn === 'function' && Auth.isLoggedIn())
          || (serverAuth && serverAuth.isAuthenticated)
        );
        if (isLoggedIn) return;
        event.preventDefault();
        const next = link.getAttribute('href') || '/';
        window.location.href = '/login/?next=' + encodeURIComponent(next);
      });
    });
  }

  async function _fetchCategories() {
    const grid = document.getElementById('cats-grid');
    const countEl = document.getElementById('cats-count');
    if (!grid) return;

    _setCount(countEl, 0);

    try {
      const res = await ApiClient.get('/api/providers/categories/');
      if (!res.ok || !res.data) {
        _renderMessage(grid, 'تعذر تحميل التصنيفات حالياً.');
        return;
      }

      const cats = Array.isArray(res.data) ? res.data : (res.data.results || []);
      if (!cats.length) {
        _renderMessage(grid, 'لا توجد تصنيفات متاحة حالياً.');
        return;
      }

      cats.sort((a, b) => String(a.name || '').localeCompare(String(b.name || ''), 'ar'));

      grid.innerHTML = '';
      grid.classList.remove('is-ready');
      _setCount(countEl, cats.length);

      const frag = document.createDocumentFragment();
      const repeats = Math.max(2, Math.ceil(14 / cats.length));
      for (let round = 0; round < repeats * 2; round += 1) {
        cats.forEach(cat => {
          frag.appendChild(_buildCategoryItem(cat, round >= repeats));
        });
      }
      grid.appendChild(frag);
      window.requestAnimationFrame(() => {
        grid.classList.add('is-ready');
        _initMarqueeDrag(grid);
      });
    } catch (_) {
      _renderMessage(grid, 'حدث خطأ أثناء تحميل التصنيفات.');
    }
  }

  function _initMarqueeDrag(track) {
    const viewport = track.closest('.asv2-categories-viewport');
    const hint = document.querySelector('.asv2-categories-scroll-hint');
    if (!viewport) return;

    let isDragging = false;
    let startX = 0;
    let currentOffset = 0;
    let resumeTimer = null;

    function _getTranslateX() {
      const style = window.getComputedStyle(track);
      const matrix = new DOMMatrix(style.transform);
      return matrix.m41;
    }

    function _pause() {
      track.classList.add('is-paused');
      clearTimeout(resumeTimer);
    }

    function _scheduleResume() {
      clearTimeout(resumeTimer);
      resumeTimer = setTimeout(() => {
        track.classList.remove('is-paused');
        viewport.classList.remove('is-dragging');
      }, 2500);
    }

    function _hideHint() {
      if (hint) hint.classList.add('hidden');
    }

    function _onPointerDown(e) {
      if (e.button && e.button !== 0) return;
      isDragging = true;
      startX = e.clientX || (e.touches && e.touches[0].clientX) || 0;
      currentOffset = _getTranslateX();
      _pause();
      viewport.classList.add('is-dragging');
      _hideHint();
      track.style.transform = 'translateX(' + currentOffset + 'px)';
      track.style.animation = 'none';
    }

    function _onPointerMove(e) {
      if (!isDragging) return;
      e.preventDefault();
      const clientX = e.clientX || (e.touches && e.touches[0].clientX) || 0;
      const delta = clientX - startX;
      const halfWidth = track.scrollWidth / 2;
      let newOffset = currentOffset + delta;
      if (newOffset > 0) newOffset = newOffset % halfWidth - halfWidth;
      else if (Math.abs(newOffset) > halfWidth) newOffset = -(Math.abs(newOffset) % halfWidth);
      track.style.transform = 'translateX(' + newOffset + 'px)';
    }

    function _onPointerUp() {
      if (!isDragging) return;
      isDragging = false;
      const offset = _getTranslateX();
      const halfWidth = track.scrollWidth / 2;
      const progress = Math.abs(offset) / halfWidth;
      track.style.animation = '';
      track.style.transform = '';
      track.style.animationDelay = '-' + (progress * 60) + 's';
      _scheduleResume();
    }

    viewport.addEventListener('mousedown', _onPointerDown);
    window.addEventListener('mousemove', _onPointerMove);
    window.addEventListener('mouseup', _onPointerUp);
    viewport.addEventListener('touchstart', _onPointerDown, { passive: true });
    viewport.addEventListener('touchmove', _onPointerMove, { passive: false });
    viewport.addEventListener('touchend', _onPointerUp);

    viewport.addEventListener('touchstart', function() {
      _pause();
      _hideHint();
    }, { passive: true, once: false });
    viewport.addEventListener('touchend', _scheduleResume);
  }

  function _buildCategoryItem(cat, isClone) {
    const categoryId = String(cat.id || '').trim();
    const href = categoryId ? ('/search/?category_id=' + encodeURIComponent(categoryId)) : '/search/';
    const subcategoryCount = Array.isArray(cat.subcategories) ? cat.subcategories.length : 0;

    const item = UI.el('a', {
      className: 'cat-item',
      href,
      'aria-label': 'استعراض مزودي تصنيف ' + String(cat.name || '').trim(),
    });
    if (isClone) {
      item.setAttribute('aria-hidden', 'true');
      item.setAttribute('tabindex', '-1');
    }
    const iconWrap = UI.el('div', { className: 'cat-icon' });
    iconWrap.appendChild(UI.icon(UI.categoryIconKey(cat.name), 24, '#673AB7'));
    item.appendChild(iconWrap);
    item.appendChild(UI.el('div', { className: 'cat-name', textContent: cat.name }));
    item.appendChild(UI.el('div', {
      className: 'cat-meta',
      textContent: subcategoryCount ? (subcategoryCount + ' تخصص') : 'تصنيف متاح',
    }));
    item.appendChild(UI.el('div', { className: 'cat-link-hint', textContent: 'عرض المزوّدين' }));
    return item;
  }

  function _setCount(node, count) {
    if (!node) return;
    node.textContent = String(Math.max(0, Number(count) || 0));
  }

  function _renderMessage(grid, message) {
    if (!grid) return;
    grid.innerHTML = '';
    grid.classList.remove('is-ready');
    const msg = UI.el('div', { className: 'add-service-cats-message', textContent: message });
    grid.appendChild(msg);
  }

  // Boot
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
  return {};
})();
