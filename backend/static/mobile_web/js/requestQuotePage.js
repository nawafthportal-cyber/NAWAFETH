/* ===================================================================
   requestQuotePage.js — Request Quote (competitive) form controller
   POST /api/marketplace/requests/create/  (request_type='competitive')
   =================================================================== */
'use strict';

const RequestQuotePage = (() => {
  let _selectedFiles = [];
  let _errorTimer = null;
  const _cities = [
    'أبها', 'الأحساء', 'الأفلاج', 'الباحة', 'البكيرية', 'البدائع', 'الجبيل', 'الجموم',
    'الحريق', 'الحوطة', 'الخبر', 'الخرج', 'الخفجي', 'الدرعية', 'الدلم', 'الدمام',
    'الدوادمي', 'الرس', 'الرياض', 'الزلفي', 'السليل', 'الطائف', 'الظهران', 'العرضيات',
    'العلا', 'القريات', 'القصيم', 'القطيف', 'القنفذة', 'القويعية', 'الليث', 'المجمعة',
    'المدينة المنورة', 'المذنب', 'المزاحمية', 'النماص', 'الوجه', 'أملج', 'بدر', 'بريدة',
    'بلجرشي', 'بيشة', 'تبوك', 'تربة', 'تنومة', 'ثادق', 'جازان', 'جدة', 'حائل',
    'حفر الباطن', 'حقل', 'حوطة بني تميم', 'خميس مشيط', 'خيبر', 'رابغ', 'رفحاء', 'رنية',
    'سراة عبيدة', 'سكاكا', 'شرورة', 'شقراء', 'صامطة', 'صبيا', 'ضباء', 'ضرما', 'طبرجل',
    'طريف', 'ظلم', 'عرعر', 'عفيف', 'عنيزة', 'محايل عسير', 'مكة المكرمة', 'نجران', 'ينبع',
  ];

  function init() {
    _resetSuccessOverlay();
    const isLoggedIn = !!Auth.isLoggedIn();
    _setAuthState(isLoggedIn);
    if (!isLoggedIn) return;

    _loadCities();
    _loadCategories();
    _bindDescriptionCounter();
    _bindLiveValidation();
    _syncDeadlineMin();
    _bindFilePickerTrigger();
    _renderAttachments();

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

  function _bindLiveValidation() {
    ['rq-title', 'rq-category', 'rq-subcategory', 'rq-details'].forEach((id) => {
      const field = document.getElementById(id);
      if (!field) return;
      const clear = () => { field.classList.remove('is-invalid'); };
      field.addEventListener('input', clear);
      field.addEventListener('change', clear);
    });
  }

  function _syncDeadlineMin() {
    const deadlineInput = document.getElementById('rq-deadline');
    if (!deadlineInput) return;
    const now = new Date();
    const minIso = _dateIso(now);
    const maxDate = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 30);
    const maxIso = _dateIso(maxDate);
    deadlineInput.min = minIso;
    deadlineInput.max = maxIso;
    if (deadlineInput.value && (deadlineInput.value < minIso || deadlineInput.value > maxIso)) {
      deadlineInput.value = '';
    }
  }

  function _bindFilePickerTrigger() {
    const trigger = document.getElementById('rq-file-trigger');
    const input = document.getElementById('rq-files');
    if (!trigger || !input) return;
    trigger.addEventListener('click', () => input.click());
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
    sel.classList.remove('is-invalid');
    subSel.classList.remove('is-invalid');
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
    _setAttachmentSummary(images, videos, others);

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

  function _setAttachmentSummary(images, videos, others) {
    const summary = document.getElementById('rq-file-summary');
    if (!summary) return;
    const total = images.length + videos.length + others.length;
    if (!total) {
      summary.textContent = 'لا توجد مرفقات مضافة';
      return;
    }
    const parts = [`${total} ملف`];
    if (images.length) parts.push(`${images.length} صورة`);
    if (videos.length) parts.push(`${videos.length} فيديو`);
    if (others.length) parts.push(`${others.length} ملف عام`);
    summary.textContent = parts.join(' - ');
  }

  function _markFieldInvalid(id) {
    const el = document.getElementById(id);
    if (el) el.classList.add('is-invalid');
  }

  function _validateRequiredFields() {
    const title = document.getElementById('rq-title')?.value?.trim() || '';
    const category = document.getElementById('rq-category')?.value || '';
    const subcategory = document.getElementById('rq-subcategory')?.value || '';
    const details = document.getElementById('rq-details')?.value?.trim() || '';

    const missing = [];
    if (!title) {
      missing.push('يرجى كتابة عنوان الطلب');
      _markFieldInvalid('rq-title');
    }
    if (!category) {
      missing.push('يرجى اختيار التصنيف الرئيسي');
      _markFieldInvalid('rq-category');
    }
    if (!subcategory) {
      missing.push('يرجى اختيار التصنيف الفرعي');
      _markFieldInvalid('rq-subcategory');
    }
    if (!details) {
      missing.push('يرجى كتابة تفاصيل الطلب');
      _markFieldInvalid('rq-details');
    }
    if (details.length > 500) {
      missing.push('تفاصيل الطلب يجب ألا تتجاوز 500 حرف');
      _markFieldInvalid('rq-details');
    }

    if (missing.length) {
      _showError(missing[0]);
      return null;
    }
    return { title, details, subcategory };
  }

  function _extractApiError(data) {
    if (!data) return '';
    if (typeof data.detail === 'string' && data.detail.trim()) return data.detail.trim();
    const keys = Object.keys(data);
    for (const key of keys) {
      const value = data[key];
      if (typeof value === 'string' && value.trim()) return value.trim();
      if (Array.isArray(value) && value.length) return String(value[0]);
    }
    return '';
  }

  /* ---- Submit ---- */
  async function _onSubmit(e) {
    e.preventDefault();
    _clearError();
    const required = _validateRequiredFields();
    if (!required) return;

    const btn = document.getElementById('rq-submit');
    if (btn) { btn.disabled = true; btn.innerHTML = '<span class="spinner-inline"></span> جاري الإرسال...'; }

    const title = required.title;
    const details = required.details;
    const subcat = required.subcategory;
    const city = document.getElementById('rq-city')?.value;
    const deadline = document.getElementById('rq-deadline')?.value;

    const fd = new FormData();
    fd.append('request_type', 'competitive');
    fd.append('title', title);
    if (details) fd.append('description', details);
    if (subcat) fd.append('subcategory', subcat);
    if (city) fd.append('city', city);
    if (deadline) fd.append('quote_deadline', deadline);
    _selectedFiles.forEach(f => fd.append('files', f));

    try {
      const res = await ApiClient.request('/api/marketplace/requests/create/', { method: 'POST', body: fd, formData: true });
      if (res.ok) {
        const success = document.getElementById('rq-success');
        success?.classList.remove('hidden');
        success?.classList.add('visible');
        setTimeout(() => { window.location.href = '/orders/'; }, 2000);
      } else {
        _showError(_extractApiError(res.data) || 'تعذر إرسال الطلب، تحقق من البيانات وحاول مرة أخرى');
      }
    } catch (err) {
      _showError('تعذر الاتصال بالخادم، حاول مرة أخرى');
    } finally {
      _resetBtn(btn);
    }
  }

  function _clearError() {
    const errEl = document.getElementById('rq-error');
    if (!errEl) return;
    errEl.style.display = 'none';
    if (_errorTimer) {
      clearTimeout(_errorTimer);
      _errorTimer = null;
    }
  }

  function _showError(msg) {
    let errEl = document.getElementById('rq-error');
    if (!errEl) {
      errEl = UI.el('div', { id: 'rq-error', className: 'form-error' });
      document.getElementById('rq-form')?.prepend(errEl);
    }
    errEl.textContent = msg;
    errEl.style.display = 'block';
    if (_errorTimer) clearTimeout(_errorTimer);
    _errorTimer = setTimeout(() => {
      errEl.style.display = 'none';
      _errorTimer = null;
    }, 4000);
  }

  function _resetBtn(btn) {
    if (!btn) return;
    btn.disabled = false;
    btn.innerHTML = '<svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M2.01 21L23 12 2.01 3 2 10l15 2-15 2z"/></svg><span>تقديم الطلب</span>';
  }

  function _dateIso(date) {
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
  }

  // Boot
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
  window.addEventListener('pageshow', _resetSuccessOverlay);
  return {};
})();
