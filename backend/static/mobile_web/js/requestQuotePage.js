/* ===================================================================
   requestQuotePage.js — Request Quote (competitive) form controller
   POST /api/marketplace/requests/create/  (request_type='competitive')
   =================================================================== */
'use strict';

const RequestQuotePage = (() => {
  let _regionCatalog = [];
  let _images = [];
  let _videos = [];
  let _files = [];
  let _audio = null;
  let _toastTimer = null;
  const _submitButtonMarkup = '<svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M2.01 21L23 12 2.01 3 2 10l15 2-15 2z"/></svg><span>تقديم الطلب</span>';
  const _toastTones = {
    info: {
      title: 'معلومة سريعة',
      role: 'status',
      live: 'polite',
      icon: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/></svg>',
    },
    success: {
      title: 'تم بنجاح',
      role: 'status',
      live: 'polite',
      icon: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg>',
    },
    warning: {
      title: 'انتبه قبل المتابعة',
      role: 'alert',
      live: 'assertive',
      icon: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 9v4"/><path d="M12 17h.01"/><path d="M10.29 3.86 1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/></svg>',
    },
    error: {
      title: 'تعذر إكمال الطلب',
      role: 'alert',
      live: 'assertive',
      icon: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="m15 9-6 6"/><path d="m9 9 6 6"/></svg>',
    },
  };
  function init() {
    _resetSuccessOverlay();
    const serverAuth = window.NAWAFETH_SERVER_AUTH || null;
    const isLoggedIn = !!(
      (window.Auth && typeof Auth.isLoggedIn === 'function' && Auth.isLoggedIn())
      || (serverAuth && serverAuth.isAuthenticated)
    );
    if (isLoggedIn && window.Auth && typeof window.Auth.ensureServiceRequestAccess === 'function' && !window.Auth.ensureServiceRequestAccess({
      gateId: 'auth-gate',
      contentId: 'form-content',
      target: '/request-quote/',
      title: 'طلب عروض الأسعار متاح في وضع العميل فقط',
      description: 'أنت تستخدم المنصة الآن بوضع مقدم الخدمة، لذلك لا يمكن إنشاء طلب عروض أسعار من هذا الوضع.',
      note: 'بدّل نوع الحساب إلى عميل الآن، ثم أكمل طلب عروض الأسعار مباشرة.',
      switchLabel: 'التبديل إلى عميل',
      profileLabel: 'الذهاب إلى نافذتي',
    })) return;
    _setAuthState(isLoggedIn);
    if (!isLoggedIn) return;

    _loadRegionCatalog();
    _loadCategories();
    _bindTextCounters();
    _bindLiveValidation();
    _syncDeadlineMin();
    _bindFilePickerTrigger();
    _bindToastControls();
    _renderAttachments();

    const catSel = document.getElementById('rq-category');
    if (catSel) catSel.addEventListener('change', _onCategoryChange);

    const fileInput = document.getElementById('rq-files');
    if (fileInput) fileInput.addEventListener('change', _onFilesChanged);

    const form = document.getElementById('rq-form');
    if (form) form.addEventListener('submit', _onSubmit);

    const citySel = document.getElementById('rq-city');
    if (citySel) citySel.addEventListener('change', _updateCityClearVisibility);

    const regionSel = document.getElementById('rq-region');
    if (regionSel) {
      regionSel.addEventListener('change', () => {
        _clearFieldError('rq-city');
        _populateCitiesForRegion('');
        _updateCityClearVisibility();
      });
    }

    const clearCityBtn = document.getElementById('rq-city-clear');
    if (clearCityBtn) {
      clearCityBtn.addEventListener('click', () => {
        const regionSel = document.getElementById('rq-region');
        if (regionSel) regionSel.value = '';
        if (citySel) citySel.value = '';
        _populateCitiesForRegion('');
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

  async function _loadRegionCatalog() {
    const res = await ApiClient.get('/api/providers/geo/regions-cities/');
    if (res.ok && res.data) {
      _regionCatalog = UI.normalizeRegionCatalog(Array.isArray(res.data) ? res.data : (res.data.results || []));
    }
    if (!_regionCatalog.length) {
      _regionCatalog = UI.getRegionCatalogFallback();
    }
    UI.populateRegionOptions(document.getElementById('rq-region'), _regionCatalog, {
      placeholder: 'اختر المنطقة الإدارية',
    });
    _populateCitiesForRegion('');
    _updateCityClearVisibility();
  }

  function _populateCitiesForRegion(selectedCity) {
    UI.populateCityOptions(document.getElementById('rq-city'), _regionCatalog, document.getElementById('rq-region')?.value || '', {
      currentValue: selectedCity || '',
      placeholder: 'اختر المدينة (اختياري)',
      emptyPlaceholder: 'اختر المنطقة أولًا ثم المدينة...',
    });
  }

  function _selectedScopedCity() {
    const region = (document.getElementById('rq-region')?.value || '').trim();
    const city = (document.getElementById('rq-city')?.value || '').trim();
    return city ? UI.formatCityDisplay(city, region) : '';
  }

  function _updateCityClearVisibility() {
    const clearBtn = document.getElementById('rq-city-clear');
    if (!clearBtn) return;
    const cityValue = _selectedScopedCity();
    clearBtn.classList.toggle('hidden', cityValue.length === 0);
  }

  function _bindTextCounters() {
    const titleField = document.getElementById('rq-title');
    const detailsField = document.getElementById('rq-details');
    if (titleField) {
      titleField.addEventListener('input', () => _updateCounterState('rq-title', 'rq-title-count', 'rq-title-count-wrap', 50));
      _updateCounterState('rq-title', 'rq-title-count', 'rq-title-count-wrap', 50);
    }
    if (detailsField) {
      detailsField.addEventListener('input', () => _updateCounterState('rq-details', 'rq-desc-count', 'rq-desc-count-wrap', 500));
      _updateCounterState('rq-details', 'rq-desc-count', 'rq-desc-count-wrap', 500);
    }
  }

  function _updateCounterState(fieldId, countId, wrapId, max) {
    const field = document.getElementById(fieldId);
    const count = document.getElementById(countId);
    const wrap = document.getElementById(wrapId);
    const length = String((field && field.value) || '').length;
    const warningThreshold = max >= 100 ? Math.floor(max * 0.8) : Math.max(max - 10, 0);
    const limitThreshold = max >= 100 ? Math.floor(max * 0.94) : Math.max(max - 3, 0);
    if (count) count.textContent = String(length);
    if (!wrap) return;
    wrap.classList.toggle('is-warning', length >= warningThreshold && length < limitThreshold);
    wrap.classList.toggle('is-limit', length >= limitThreshold);
  }

  function _bindLiveValidation() {
    ['rq-title', 'rq-category', 'rq-subcategory', 'rq-details'].forEach((id) => {
      const field = document.getElementById(id);
      if (!field) return;
      const clear = () => { _clearFieldError(id); };
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

  function _bindToastControls() {
    const closeBtn = document.getElementById('rq-toast-close');
    if (!closeBtn) return;
    closeBtn.addEventListener('click', _hideToast);
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
    _clearFieldError('rq-category');
    _clearFieldError('rq-subcategory');
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
    let audioSkipped = false;

    incoming.forEach((file) => {
      if (_hasFile(file)) return;
      const mime = String(file.type || '').toLowerCase();
      const name = String(file.name || '').toLowerCase();

      if (mime.startsWith('image/') || /\.(jpg|jpeg|png|gif|webp|bmp)$/.test(name)) {
        _images.push(file);
      } else if (mime.startsWith('video/') || /\.(mp4|mov|avi|mkv|webm|m4v)$/.test(name)) {
        _videos.push(file);
      } else if (mime.startsWith('audio/') || /\.(mp3|wav|aac|ogg|m4a)$/.test(name)) {
        if (_audio) {
          audioSkipped = true;
          return;
        }
        _audio = file;
      } else {
        _files.push(file);
      }
      added += 1;
    });

    const input = document.getElementById('rq-files');
    if (input) input.value = '';

    _renderAttachments();
    if (audioSkipped) {
      _showToast('يمكن إرفاق تسجيل صوتي واحد فقط مع الطلب', 'warning');
      return;
    }
    if (!added) _showToast('لم تتم إضافة مرفقات جديدة', 'warning');
  }

  function _fileKey(file) {
    return [file.name, file.size, file.lastModified].join('::');
  }

  function _hasFile(file) {
    const key = _fileKey(file);
    if (_images.some((item) => _fileKey(item) === key)) return true;
    if (_videos.some((item) => _fileKey(item) === key)) return true;
    if (_files.some((item) => _fileKey(item) === key)) return true;
    return !!(_audio && _fileKey(_audio) === key);
  }

  function _renderAttachments() {
    const list = document.getElementById('rq-file-list');
    if (!list) return;
    list.innerHTML = '';

    _setAttachmentSummary();

    const renderThumbSection = (title, items, kind) => {
      if (!items.length) return;
      const section = UI.el('div', { className: 'attach-section' });
      section.appendChild(UI.el('strong', { className: 'attach-section-title', textContent: title }));
      const grid = UI.el('div', { className: 'attach-image-grid' });

      items.forEach((file) => {
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
          const idx = items.indexOf(file);
          if (idx !== -1) items.splice(idx, 1);
          _renderAttachments();
        });

        thumb.appendChild(removeBtn);
        grid.appendChild(thumb);
      });

      section.appendChild(grid);
      list.appendChild(section);
    };

    renderThumbSection('الصور', _images, 'image');
    renderThumbSection('الفيديو', _videos, 'video');

    const renderSection = (title, items, removeItem) => {
      if (!items.length) return;
      const section = UI.el('div', { className: 'attach-section' });
      section.appendChild(UI.el('strong', { className: 'attach-section-title', textContent: title }));

      items.forEach((file, idx) => {
        const item = UI.el('div', { className: 'file-item' });
        item.appendChild(UI.el('span', { className: 'file-name', textContent: file.name }));

        const removeBtn = UI.el('button', {
          type: 'button',
          className: 'file-remove-btn',
          textContent: 'إزالة',
        });
        removeBtn.addEventListener('click', () => {
          removeItem(idx);
          _renderAttachments();
        });

        item.appendChild(removeBtn);
        section.appendChild(item);
      });

      list.appendChild(section);
    };

    if (_audio) {
      const item = UI.el('div', { className: 'file-item' });
      item.appendChild(UI.el('span', { className: 'file-name', textContent: _audio.name }));

      const removeBtn = UI.el('button', {
        type: 'button',
        className: 'file-remove-btn',
        textContent: 'إزالة',
      });
      removeBtn.addEventListener('click', () => {
        _audio = null;
        _renderAttachments();
      });

      item.appendChild(removeBtn);
      const section = UI.el('div', { className: 'attach-section' });
      section.appendChild(UI.el('strong', { className: 'attach-section-title', textContent: 'الصوت' }));
      section.appendChild(item);
      list.appendChild(section);
    }

    renderSection('الملفات', _files, (idx) => { _files.splice(idx, 1); });

    if (!_images.length && !_videos.length && !_files.length && !_audio) {
      list.appendChild(UI.el('span', { className: 'attach-empty', textContent: 'لا توجد مرفقات مضافة' }));
    }
  }

  function _setAttachmentSummary() {
    const summary = document.getElementById('rq-file-summary');
    const note = document.getElementById('rq-attachment-note');
    const noteTitle = document.getElementById('rq-attachment-note-title');
    const noteText = document.getElementById('rq-attachment-note-text');
    if (!summary) return;
    const total = _images.length + _videos.length + _files.length + (_audio ? 1 : 0);
    if (!total) {
      summary.textContent = 'لا توجد مرفقات مضافة';
      if (note) note.classList.add('hidden');
      return;
    }
    const parts = [`${total} ملف`];
    if (_images.length) parts.push(`${_images.length} صورة`);
    if (_videos.length) parts.push(`${_videos.length} فيديو`);
    if (_audio) parts.push('تسجيل صوتي');
    if (_files.length) parts.push(`${_files.length} ملف عام`);
    summary.textContent = parts.join(' - ');
    if (note && noteTitle && noteText) {
      noteTitle.textContent = total === 1 ? 'تمت إضافة مرفق واحد' : 'تم تجهيز المرفقات';
      noteText.textContent = `تمت إضافة ${parts.join(' و')}، وستُرسل مع الطلب مباشرة عند الإرسال.`;
      note.classList.remove('hidden');
    }
  }

  function _appendRequestFiles(formData) {
    _images.forEach((file) => formData.append('images', file));
    _videos.forEach((file) => formData.append('videos', file));
    _files.forEach((file) => formData.append('files', file));
    if (_audio) formData.append('audio', _audio);
  }

  function _getAttachmentCount() {
    return _images.length + _videos.length + _files.length + (_audio ? 1 : 0);
  }

  function _formatAttachmentCount(count) {
    if (!count) return 'بدون مرفقات';
    if (count === 1) return 'مرفق واحد';
    if (count === 2) return 'مرفقان';
    return `${count} مرفقات`;
  }

  function _markFieldInvalid(id) {
    const el = document.getElementById(id);
    if (el) {
      el.classList.add('is-invalid');
      el.setAttribute('aria-invalid', 'true');
    }
  }

  function _fieldErrorId(id) {
    return `${id}-error`;
  }

  function _setFieldError(id, message) {
    const errorEl = document.getElementById(_fieldErrorId(id));
    _markFieldInvalid(id);
    if (!errorEl) return;
    errorEl.textContent = message || '';
    errorEl.classList.toggle('hidden', !message);
  }

  function _clearFieldError(id) {
    const el = document.getElementById(id);
    const errorEl = document.getElementById(_fieldErrorId(id));
    if (el) {
      el.classList.remove('is-invalid');
      el.removeAttribute('aria-invalid');
    }
    if (errorEl) {
      errorEl.textContent = '';
      errorEl.classList.add('hidden');
    }
  }

  function _clearAllFieldErrors() {
    ['rq-title', 'rq-category', 'rq-subcategory', 'rq-details', 'rq-city', 'rq-deadline'].forEach(_clearFieldError);
  }

  function _focusField(id) {
    const el = document.getElementById(id);
    if (!el || typeof el.focus !== 'function') return;
    try {
      el.focus({ preventScroll: false });
    } catch (_) {
      el.focus();
    }
  }

  function _validateRequiredFields() {
    _clearAllFieldErrors();
    const title = document.getElementById('rq-title')?.value?.trim() || '';
    const category = document.getElementById('rq-category')?.value || '';
    const subcategory = document.getElementById('rq-subcategory')?.value || '';
    const details = document.getElementById('rq-details')?.value?.trim() || '';

    const missing = [];
    if (!title) {
      _setFieldError('rq-title', 'يرجى كتابة عنوان الطلب');
      missing.push({ id: 'rq-title', message: 'يرجى كتابة عنوان الطلب' });
    }
    if (!category) {
      _setFieldError('rq-category', 'يرجى اختيار التصنيف الرئيسي');
      missing.push({ id: 'rq-category', message: 'يرجى اختيار التصنيف الرئيسي' });
    }
    if (!subcategory) {
      _setFieldError('rq-subcategory', 'يرجى اختيار التصنيف الفرعي');
      missing.push({ id: 'rq-subcategory', message: 'يرجى اختيار التصنيف الفرعي' });
    }
    if (!details) {
      _setFieldError('rq-details', 'يرجى كتابة تفاصيل الطلب');
      missing.push({ id: 'rq-details', message: 'يرجى كتابة تفاصيل الطلب' });
    }
    if (details.length > 500) {
      _setFieldError('rq-details', 'تفاصيل الطلب يجب ألا تتجاوز 500 حرف');
      missing.push({ id: 'rq-details', message: 'تفاصيل الطلب يجب ألا تتجاوز 500 حرف' });
    }
    if (title.length > 50) {
      _setFieldError('rq-title', 'عنوان الطلب يجب ألا يتجاوز 50 حرفًا');
      missing.push({ id: 'rq-title', message: 'عنوان الطلب يجب ألا يتجاوز 50 حرفًا' });
    }

    if (missing.length) {
      _focusField(missing[0].id);
      _showToast(missing[0].message, 'warning');
      return null;
    }
    return { title, details, subcategory };
  }

  function _firstErrorMessage(value) {
    if (typeof value === 'string' && value.trim()) return value.trim();
    if (Array.isArray(value) && value.length) return String(value[0] || '').trim();
    return '';
  }

  function _applyApiFieldErrors(data) {
    if (!data || typeof data !== 'object') return '';
    const fieldMap = {
      title: 'rq-title',
      subcategory: 'rq-subcategory',
      description: 'rq-details',
      city: 'rq-city',
      quote_deadline: 'rq-deadline',
    };
    let firstMessage = '';
    let firstFieldId = '';

    Object.entries(fieldMap).forEach(([apiField, fieldId]) => {
      const message = _firstErrorMessage(data[apiField]);
      if (!message) return;
      _setFieldError(fieldId, message);
      if (!firstMessage) {
        firstMessage = message;
        firstFieldId = fieldId;
      }
    });

    if (firstFieldId) _focusField(firstFieldId);
    return firstMessage;
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

  function _readStoredValue(key) {
    try {
      const sessionValue = window.sessionStorage ? window.sessionStorage.getItem(key) : null;
      if (sessionValue) return sessionValue;
    } catch (_) {}
    try {
      return window.localStorage ? window.localStorage.getItem(key) : null;
    } catch (_) {
      return null;
    }
  }

  function _getAccessToken() {
    if (typeof Auth !== 'undefined' && Auth && typeof Auth.getAccessToken === 'function') {
      return Auth.getAccessToken();
    }
    return _readStoredValue('nw_access_token');
  }

  function _getActiveAccountMode() {
    try {
      if (typeof Auth !== 'undefined' && Auth && typeof Auth.getActiveAccountMode === 'function') {
        const mode = String(Auth.getActiveAccountMode() || '').trim().toLowerCase();
        return mode === 'provider' ? 'provider' : 'client';
      }
    } catch (_) {}
    const storedMode = String(_readStoredValue('nw_account_mode') || '').trim().toLowerCase();
    return storedMode === 'provider' ? 'provider' : 'client';
  }

  function _sendFormDataWithXhr(path, formData, options = {}) {
    return new Promise((resolve) => {
      const xhr = new XMLHttpRequest();
      const baseUrl = (window.ApiClient && window.ApiClient.BASE) ? window.ApiClient.BASE : window.location.origin;
      try {
        xhr.open('POST', `${baseUrl}${path}`, true);
      } catch (_) {
        resolve({ ok: false, status: 0, data: null });
        return;
      }

      xhr.timeout = 180000;
      xhr.setRequestHeader('Accept', 'application/json');
      xhr.setRequestHeader('X-Account-Mode', _getActiveAccountMode());
      if (options.token) {
        try {
          xhr.setRequestHeader('Authorization', `Bearer ${options.token}`);
        } catch (_) {}
      }

      if (xhr.upload && typeof options.onProgress === 'function') {
        xhr.upload.addEventListener('progress', (event) => {
          if (!event || !event.lengthComputable || !event.total) return;
          options.onProgress((event.loaded / event.total) * 100);
        });
      }

      xhr.onload = () => {
        const status = Number(xhr.status || 0);
        const contentType = String(xhr.getResponseHeader('content-type') || '').toLowerCase();
        let data = null;
        if (xhr.responseText && contentType.includes('json')) {
          try {
            data = JSON.parse(xhr.responseText);
          } catch (_) {
            data = null;
          }
        }
        resolve({ ok: status >= 200 && status < 300, status, data });
      };
      xhr.onerror = () => resolve({ ok: false, status: Number(xhr.status || 0), data: null });
      xhr.ontimeout = () => resolve({ ok: false, status: 0, data: null });
      xhr.onabort = () => resolve({ ok: false, status: Number(xhr.status || 0), data: null });

      try {
        xhr.send(formData);
      } catch (_) {
        resolve({ ok: false, status: 0, data: null });
      }
    });
  }

  async function _submitFormData(path, formData, onProgress) {
    const token = _getAccessToken();
    let response = await _sendFormDataWithXhr(path, formData, { token, onProgress });
    if (response.status === 401 && token && window.ApiClient && typeof window.ApiClient.refreshAccessToken === 'function') {
      const refresh = await window.ApiClient.refreshAccessToken();
      if (refresh && refresh.ok) {
        response = await _sendFormDataWithXhr(path, formData, { token: _getAccessToken(), onProgress });
      }
    }
    return response;
  }

  function _hideToast() {
    const toast = document.getElementById('rq-toast');
    if (!toast) return;
    toast.classList.remove('show');
    if (_toastTimer) {
      clearTimeout(_toastTimer);
      _toastTimer = null;
    }
  }

  function _showToast(message, type = 'info', options = {}) {
    const toast = document.getElementById('rq-toast');
    const toastTitle = document.getElementById('rq-toast-title');
    const toastMessage = document.getElementById('rq-toast-message');
    const toastIcon = document.getElementById('rq-toast-icon');
    const toneKey = _toastTones[type] ? type : 'info';
    const tone = _toastTones[toneKey];
    if (!toast) {
      window.alert(message || '');
      return;
    }

    if (toastTitle) toastTitle.textContent = tone.title;
    if (toastMessage) toastMessage.textContent = message || '';
    if (toastIcon) toastIcon.innerHTML = tone.icon;
    toast.setAttribute('role', tone.role);
    toast.setAttribute('aria-live', tone.live);
    toast.classList.remove('show', 'success', 'error', 'warning', 'info');
    toast.classList.add(toneKey);
    requestAnimationFrame(() => {
      toast.classList.add('show');
    });

    if (_toastTimer) clearTimeout(_toastTimer);
    _toastTimer = setTimeout(() => {
      _hideToast();
    }, Number(options.duration || 4600));
  }

  function _setSubmitOverlay(visible, options = {}) {
    const overlay = document.getElementById('rq-submit-state');
    const title = document.getElementById('rq-submit-state-title');
    const message = document.getElementById('rq-submit-state-message');
    const count = document.getElementById('rq-submit-state-count');
    const percent = document.getElementById('rq-submit-state-percent');
    const progress = document.getElementById('rq-submit-state-bar');
    const progressWrap = document.querySelector('.rq-submit-state-progress');
    if (!overlay) return;

    if (!visible) {
      overlay.classList.add('hidden');
      overlay.classList.remove('visible');
      return;
    }

    const attachmentCount = Number(options.attachmentCount || 0);
    const progressValue = Math.max(0, Math.min(100, Math.round(Number(options.progress || 0))));
    if (title) title.textContent = options.title || 'جاري إرسال الطلب';
    if (message) {
      message.textContent = options.message || (attachmentCount
        ? `يتم الآن رفع ${_formatAttachmentCount(attachmentCount)} مع بيانات الطلب. لا تغلق الصفحة حتى يكتمل الإرسال.`
        : 'يتم الآن إرسال بيانات الطلب. لا تغلق الصفحة حتى يكتمل الإرسال.');
    }
    if (count) count.textContent = _formatAttachmentCount(attachmentCount);
    if (percent) percent.textContent = `${progressValue}%`;
    if (progress) progress.style.width = `${Math.max(progressValue, 6)}%`;
    if (progressWrap) progressWrap.setAttribute('aria-valuenow', String(progressValue));

    overlay.classList.remove('hidden');
    requestAnimationFrame(() => {
      overlay.classList.add('visible');
    });
  }

  function _setSubmitProgress(progress, attachmentCount) {
    const safeProgress = Math.max(0, Math.min(100, Math.round(Number(progress || 0))));
    let title = 'جاري إرسال الطلب';
    let message = attachmentCount
      ? `يتم الآن رفع ${_formatAttachmentCount(attachmentCount)} مع بيانات الطلب.`
      : 'يتم الآن إرسال بيانات الطلب إلى المنصة.';

    if (attachmentCount && safeProgress <= 10) {
      title = 'جاري تجهيز المرفقات';
      message = `تم تجهيز ${_formatAttachmentCount(attachmentCount)} وبدء رفعها الآن.`;
    } else if (attachmentCount && safeProgress < 100) {
      title = 'جاري رفع المرفقات';
      message = `تم رفع ${safeProgress}% من الطلب حتى الآن. انتظر قليلًا حتى يكتمل الإرسال.`;
    } else if (safeProgress >= 100) {
      title = 'جاري اعتماد الطلب';
      message = 'اكتمل رفع البيانات، وجارٍ اعتماد الطلب وإظهاره للمزوّدين.';
    }

    _setSubmitOverlay(true, {
      title,
      message,
      attachmentCount,
      progress: safeProgress,
    });
  }

  /* ---- Submit ---- */
  async function _onSubmit(e) {
    e.preventDefault();
    _clearError();
    const required = _validateRequiredFields();
    if (!required) return;

    const btn = document.getElementById('rq-submit');
    const attachmentCount = _getAttachmentCount();
    if (btn) {
      btn.disabled = true;
      btn.classList.add('is-loading');
      btn.innerHTML = '<span class="spinner-inline"></span><span>جاري إرسال الطلب</span>';
    }
    _setSubmitProgress(0, attachmentCount);

    const title = required.title;
    const details = required.details;
    const subcat = required.subcategory;
    const city = _selectedScopedCity();
    const deadline = document.getElementById('rq-deadline')?.value;

    const fd = new FormData();
    fd.append('request_type', 'competitive');
    fd.append('title', title);
    if (details) fd.append('description', details);
    if (subcat) fd.append('subcategory', subcat);
    if (city) fd.append('city', city);
    if (deadline) fd.append('quote_deadline', deadline);
    _appendRequestFiles(fd);

    try {
      const res = await _submitFormData('/api/marketplace/requests/create/', fd, (percent) => {
        _setSubmitProgress(percent, attachmentCount);
      });
      if (res.ok) {
        _setSubmitProgress(100, attachmentCount);
        const success = document.getElementById('rq-success');
        success?.classList.remove('hidden');
        success?.classList.add('visible');
        setTimeout(() => { window.location.href = '/orders/'; }, 2000);
      } else {
        const apiFieldMessage = _applyApiFieldErrors(res.data);
        _showToast(apiFieldMessage || _extractApiError(res.data) || 'تعذر إرسال الطلب، تحقق من البيانات وحاول مرة أخرى', 'error', { duration: 5200 });
      }
    } catch (err) {
      _showToast('تعذر الاتصال بالخادم، حاول مرة أخرى', 'error', { duration: 5200 });
    } finally {
      _setSubmitOverlay(false);
      _resetBtn(btn);
    }
  }

  function _clearError() {
    _hideToast();
  }

  function _showError(msg) {
    _showToast(msg, 'error', { duration: 5200 });
  }

  function _resetBtn(btn) {
    if (!btn) return;
    btn.disabled = false;
    btn.classList.remove('is-loading');
    btn.innerHTML = _submitButtonMarkup;
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
