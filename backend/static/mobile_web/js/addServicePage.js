/* ===================================================================
   addServicePage.js — Add Service hub page controller
   GET /api/providers/categories/
   =================================================================== */
'use strict';

const AddServicePage = (() => {
  function init() {
    _bindAuthRequiredLinks();
    _fetchCategories();
  }

  function _bindAuthRequiredLinks() {
    document.querySelectorAll('a[data-auth-required="true"]').forEach((link) => {
      link.addEventListener('click', (event) => {
        if (Auth.isLoggedIn()) return;
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
      _setCount(countEl, cats.length);

      const frag = document.createDocumentFragment();
      cats.forEach(cat => {
        const categoryId = String(cat.id || '').trim();
        const href = categoryId ? ('/search/?category_id=' + encodeURIComponent(categoryId)) : '/search/';
        const subcategoryCount = Array.isArray(cat.subcategories) ? cat.subcategories.length : 0;

        const item = UI.el('a', {
          className: 'cat-item',
          href,
          'aria-label': 'استعراض مزودي تصنيف ' + String(cat.name || '').trim(),
        });
        const iconWrap = UI.el('div', { className: 'cat-icon' });
        iconWrap.appendChild(UI.icon(UI.categoryIconKey(cat.name), 24, '#673AB7'));
        item.appendChild(iconWrap);
        item.appendChild(UI.el('div', { className: 'cat-name', textContent: cat.name }));
        item.appendChild(UI.el('div', {
          className: 'cat-meta',
          textContent: subcategoryCount ? (subcategoryCount + ' تخصص') : 'تصنيف متاح',
        }));
        item.appendChild(UI.el('div', { className: 'cat-link-hint', textContent: 'عرض المزوّدين' }));
        frag.appendChild(item);
      });
      grid.appendChild(frag);
    } catch (_) {
      _renderMessage(grid, 'حدث خطأ أثناء تحميل التصنيفات.');
    }
  }

  function _setCount(node, count) {
    if (!node) return;
    node.textContent = String(Math.max(0, Number(count) || 0));
  }

  function _renderMessage(grid, message) {
    if (!grid) return;
    grid.innerHTML = '';
    const msg = UI.el('div', { className: 'add-service-cats-message', textContent: message });
    grid.appendChild(msg);
  }

  // Boot
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
  return {};
})();
