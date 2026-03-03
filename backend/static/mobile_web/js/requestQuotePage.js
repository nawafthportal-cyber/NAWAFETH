/* ===================================================================
   requestQuotePage.js — Request Quote (competitive) form controller
   POST /api/marketplace/requests/create/  (request_type='competitive')
   =================================================================== */
'use strict';

const RequestQuotePage = (() => {
  let _selectedFiles = [];
  const _cities = [
    'الرياض','جدة','مكة المكرمة','المدينة المنورة','الدمام','الخبر','الظهران','الطائف','تبوك','بريدة',
    'عنيزة','حائل','أبها','خميس مشيط','نجران','جازان','ينبع','الباحة','الجبيل','حفر الباطن',
    'القطيف','الأحساء','سكاكا','عرعر','بيشة','الخرج','الدوادمي','المجمعة','القويعية','وادي الدواسر'
  ];

  function init() {
    _resetSuccessOverlay();
    const isLoggedIn = !!Auth.isLoggedIn();
    _setAuthState(isLoggedIn);
    if (!isLoggedIn) return;

    _loadCities();
    _loadCategories();
    _bindDescriptionCounter();

    const catSel = document.getElementById('rq-category');
    if (catSel) catSel.addEventListener('change', _onCategoryChange);

    const fileInput = document.getElementById('rq-files');
    if (fileInput) fileInput.addEventListener('change', _onFilesChanged);

    const form = document.getElementById('rq-form');
    if (form) form.addEventListener('submit', _onSubmit);

    const citySel = document.getElementById('rq-city');
    if (citySel) citySel.addEventListener('change', _updateCityClearVisibility);

    const clearCityBtn = document.getElementById('rq-city-clear');
    if (clearCityBtn) {
      clearCityBtn.addEventListener('click', () => {
        if (citySel) citySel.value = '';
        _updateCityClearVisibility();
      });
    }
  }

  function _resetSuccessOverlay() {
    const overlay = document.getElementById('rq-success');
    if (!overlay) return;
    overlay.classList.remove('visible');
    overlay.classList.add('hidden');
  }

  function _setAuthState(isLoggedIn) {
    const gate = document.getElementById('auth-gate');
    const formContent = document.getElementById('form-content');
    if (gate) gate.classList.toggle('hidden', isLoggedIn);
    if (formContent) formContent.classList.toggle('hidden', !isLoggedIn);
  }

  function _loadCities() {
    const citySel = document.getElementById('rq-city');
    if (!citySel) return;
    _cities.forEach((city) => {
      const option = document.createElement('option');
      option.value = city;
      option.textContent = city;
      citySel.appendChild(option);
    });
    _updateCityClearVisibility();
  }

  function _updateCityClearVisibility() {
    const clearBtn = document.getElementById('rq-city-clear');
    if (!clearBtn) return;
    const cityValue = (document.getElementById('rq-city')?.value || '').trim();
    clearBtn.classList.toggle('hidden', cityValue.length === 0);
  }

  function _bindDescriptionCounter() {
    const textarea = document.getElementById('rq-details');
    const counter = document.getElementById('rq-desc-count');
    if (!textarea || !counter) return;
    const update = () => { counter.textContent = String((textarea.value || '').length); };
    textarea.addEventListener('input', update);
    update();
  }

  /* ---- Categories cascade ---- */
  async function _loadCategories() {
    const res = await ApiClient.get('/api/providers/categories/');
    if (!res.ok || !res.data) return;
    const cats = Array.isArray(res.data) ? res.data : (res.data.results || []);
    const sel = document.getElementById('rq-category');
    if (!sel) return;
    cats.forEach(c => {
      const opt = document.createElement('option');
      opt.value = c.id;
      opt.textContent = c.name;
      opt.dataset.subs = JSON.stringify(c.subcategories || []);
      sel.appendChild(opt);
    });
  }

  function _onCategoryChange() {
    const sel = document.getElementById('rq-category');
    const subSel = document.getElementById('rq-subcategory');
    if (!sel || !subSel) return;
    subSel.innerHTML = '<option value="">-- اختر التخصص --</option>';
    const opt = sel.options[sel.selectedIndex];
    if (!opt || !opt.dataset.subs) return;
    try {
      const subs = JSON.parse(opt.dataset.subs);
      subs.forEach(s => {
        const o = document.createElement('option');
        o.value = s.id;
        o.textContent = s.name;
        subSel.appendChild(o);
      });
    } catch (e) { /* ignore */ }
  }

  /* ---- File handling ---- */
  function _onFilesChanged(e) {
    const incoming = Array.from((e && e.target && e.target.files) || []);
    let added = 0;

    incoming.forEach((file) => {
      if (_hasFile(file)) return;
      _selectedFiles.push(file);
      added += 1;
    });

    const input = document.getElementById('rq-files');
    if (input) input.value = '';

    _renderAttachments();
    if (!added) _showError('لم تتم إضافة مرفقات جديدة');
  }

  function _fileKey(file) {
    return [file.name, file.size, file.lastModified].join('::');
  }

  function _hasFile(file) {
    const key = _fileKey(file);
    return _selectedFiles.some((item) => _fileKey(item) === key);
  }

  function _renderAttachments() {
    const list = document.getElementById('rq-file-list');
    if (!list) return;
    list.innerHTML = '';

    const images = [];
    const videos = [];
    const others = [];
    _selectedFiles.forEach((file) => {
      const mime = String(file.type || '').toLowerCase();
      const name = String(file.name || '').toLowerCase();
      const isImage = mime.startsWith('image/') || /\.(jpg|jpeg|png|gif|webp|bmp)$/.test(name);
      const isVideo = mime.startsWith('video/') || /\.(mp4|mov|avi|mkv|webm|m4v)$/.test(name);
      if (isImage) images.push(file);
      else if (isVideo) videos.push(file);
      else others.push(file);
    });

    const renderThumbSection = (title, items, kind) => {
      if (!items.length) return;
      const section = UI.el('div', { className: 'attach-section' });
      section.appendChild(UI.el('strong', { className: 'attach-section-title', textContent: title }));
      const grid = UI.el('div', { className: 'attach-image-grid' });

      items.forEach((file) => {
        const idx = _selectedFiles.indexOf(file);
        if (idx === -1) return;

        const thumb = UI.el('div', { className: 'attach-thumb' });
        const url = URL.createObjectURL(file);

        if (kind === 'video') {
          const video = UI.el('video', {
            src: url,
            muted: true,
            playsInline: true,
            preload: 'metadata',
          });
          const revoke = () => URL.revokeObjectURL(url);
          video.addEventListener('loadeddata', revoke, { once: true });
          video.addEventListener('error', revoke, { once: true });
          thumb.appendChild(video);
          thumb.appendChild(UI.el('span', {
            className: 'attach-thumb-video-badge',
            textContent: '▶',
            'aria-hidden': 'true',
          }));
        } else {
          const img = UI.el('img', { src: url, alt: file.name });
          const revoke = () => URL.revokeObjectURL(url);
          img.addEventListener('load', revoke, { once: true });
          img.addEventListener('error', revoke, { once: true });
          thumb.appendChild(img);
        }

        const removeBtn = UI.el('button', {
          type: 'button',
          className: 'attach-thumb-remove',
          textContent: '×',
          title: kind === 'video' ? 'إزالة الفيديو' : 'إزالة الصورة',
          'aria-label': kind === 'video' ? 'إزالة الفيديو' : 'إزالة الصورة',
        });
        removeBtn.addEventListener('click', () => {
          _selectedFiles.splice(idx, 1);
          _renderAttachments();
        });

        thumb.appendChild(removeBtn);
        grid.appendChild(thumb);
      });

      section.appendChild(grid);
      list.appendChild(section);
    };

    renderThumbSection('الصور', images, 'image');
    renderThumbSection('الفيديو', videos, 'video');

    others.forEach((file) => {
      const idx = _selectedFiles.indexOf(file);
      if (idx === -1) return;
      const item = UI.el('div', { className: 'file-item' });
      item.appendChild(UI.el('span', { className: 'file-name', textContent: file.name }));

      const removeBtn = UI.el('button', {
        type: 'button',
        className: 'file-remove-btn',
        textContent: 'إزالة',
      });
      removeBtn.addEventListener('click', () => {
        _selectedFiles.splice(idx, 1);
        _renderAttachments();
      });

      item.appendChild(removeBtn);
      list.appendChild(item);
    });

    if (!_selectedFiles.length) {
      list.appendChild(UI.el('span', { className: 'attach-empty', textContent: 'لا توجد مرفقات مضافة' }));
    }
  }

  /* ---- Submit ---- */
  async function _onSubmit(e) {
    e.preventDefault();
    const btn = document.getElementById('rq-submit');
    if (btn) { btn.disabled = true; btn.innerHTML = '<span class="spinner-inline"></span> جاري الإرسال...'; }

    const title = document.getElementById('rq-title')?.value?.trim();
    const details = document.getElementById('rq-details')?.value?.trim();
    const subcat = document.getElementById('rq-subcategory')?.value;
    const city = document.getElementById('rq-city')?.value;
    const deadline = document.getElementById('rq-deadline')?.value;

    if (!title) {
      _showError('يرجى كتابة عنوان الطلب');
      _resetBtn(btn);
      return;
    }

    const fd = new FormData();
    fd.append('request_type', 'competitive');
    fd.append('title', title);
    if (details) fd.append('description', details);
    if (subcat) fd.append('subcategory', subcat);
    if (city) fd.append('city', city);
    if (deadline) fd.append('quote_deadline', deadline);
    _selectedFiles.forEach(f => fd.append('files', f));

    const res = await ApiClient.request('/api/marketplace/requests/create/', { method: 'POST', body: fd, formData: true });
    if (res.ok) {
      const success = document.getElementById('rq-success');
      success?.classList.remove('hidden');
      success?.classList.add('visible');
      setTimeout(() => { window.location.href = '/orders/'; }, 2000);
    } else {
      _showError(res.data?.detail || 'حدث خطأ، حاول مرة أخرى');
    }
    _resetBtn(btn);
  }

  function _showError(msg) {
    let errEl = document.getElementById('rq-error');
    if (!errEl) {
      errEl = UI.el('div', { id: 'rq-error', className: 'form-error' });
      document.getElementById('rq-form')?.prepend(errEl);
    }
    errEl.textContent = msg;
    errEl.style.display = 'block';
    setTimeout(() => { errEl.style.display = 'none'; }, 4000);
  }

  function _resetBtn(btn) {
    if (!btn) return;
    btn.disabled = false;
    btn.innerHTML = '<svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor" style="vertical-align:middle;margin-inline-end:4px"><path d="M2.01 21L23 12 2.01 3 2 10l15 2-15 2z"/></svg>تقديم الطلب';
  }

  // Boot
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
  window.addEventListener('pageshow', _resetSuccessOverlay);
  return {};
})();
