/* ===================================================================
   urgentRequestPage.js — Urgent Request form controller
   POST /api/marketplace/requests/create/  (request_type='urgent')
   =================================================================== */
'use strict';

const UrgentRequestPage = (() => {
  let _images = [];
  let _videos = [];
  let _files = [];
  let _audio = null;
  let _clientLocation = null;
  let _clientLocationPromise = null;
  const _cities = [
    'أبها', 'الأحساء', 'الأفلاج', 'الباحة', 'البكيرية', 'البدائع', 'الجبيل', 'الجموم',
    'الحريق', 'الحوطة', 'الخبر', 'الخرج', 'الخفجي', 'الدرعية', 'الدلم', 'الدمام',
    'الدوادمي', 'الرس', 'الرياض', 'الزلفي', 'السليل', 'الطائف', 'الظهران', 'العرضيات',
    'العلا', 'القريات', 'القصيم', 'القطيف', 'القنفذة', 'القويعية', 'الليث', 'المجمعة',
    'المدينة المنورة', 'المذنب', 'المزاحمية', 'النماص', 'الوجه', 'أملج', 'بدر', 'بريدة',
    'بلجرشي', 'بيشة', 'تبوك', 'تربة', 'تنومة', 'ثادق', 'جازان', 'جدة', 'حائل',
    'حفر الباطن', 'حقل', 'حوطة بني تميم', 'خميس مشيط', 'خيبر', 'رابغ', 'رفحاء', 'رنية',
    'سراة عبيدة', 'سكاكا', 'شرورة', 'شقراء', 'صامطة', 'صبيا', 'ضباء', 'ضرما', 'طبرجل',
    'طريف', 'ظلم', 'عرعر', 'عفيف', 'عنيزة', 'محايل عسير', 'مكة المكرمة', 'نجران', 'ينبع'
  ];

  function init() {
    _resetSuccessOverlay();
    const isLoggedIn = !!Auth.isLoggedIn();
    _setAuthState(isLoggedIn);
    if (!isLoggedIn) return;

    _loadCities();
    _loadCategories();
    _bindDispatchMode();
    _bindDescriptionCounter();

    const catSel = document.getElementById('ur-category');
    if (catSel) catSel.addEventListener('change', _onCategoryChange);

    const subSel = document.getElementById('ur-subcategory');
    if (subSel) {
      subSel.addEventListener('change', _updateNearestCityHint);
    }

    const fileInput = document.getElementById('ur-files');
    if (fileInput) fileInput.addEventListener('change', _onFilesChanged);

    const fileTrigger = document.getElementById('ur-file-trigger');
    if (fileTrigger && fileInput) {
      fileTrigger.addEventListener('click', () => fileInput.click());
    }

    const form = document.getElementById('ur-form');
    if (form) form.addEventListener('submit', _onSubmit);

    const citySel = document.getElementById('ur-city');
    if (citySel) {
      citySel.addEventListener('change', () => {
        _updateCityClearVisibility();
        _updateNearestCityHint();
      });
    }

    const clearCityBtn = document.getElementById('ur-city-clear');
    if (clearCityBtn) {
      clearCityBtn.addEventListener('click', () => {
        if (citySel) citySel.value = '';
        _updateCityClearVisibility();
        _updateNearestCityHint();
      });
    }

    _updateNearestCityHint();
    _renderAttachments();
  }

  function _resetSuccessOverlay() {
    const overlay = document.getElementById('ur-success');
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
    const citySel = document.getElementById('ur-city');
    if (!citySel) return;
    _cities.forEach((city) => {
      const option = document.createElement('option');
      option.value = city;
      option.textContent = city;
      citySel.appendChild(option);
    });
    _updateCityClearVisibility();
    _updateNearestCityHint();
  }

  function _bindDispatchMode() {
    const labels = document.querySelectorAll('.radio-chip-label');
    labels.forEach((label) => {
      const input = label.querySelector('input[type="radio"]');
      const chip = label.querySelector('.radio-chip');
      if (!input || !chip) return;
      input.addEventListener('change', () => {
        document.querySelectorAll('.radio-chip-label .radio-chip').forEach((node) => {
          node.classList.remove('active');
        });
        chip.classList.add('active');
        if (input.checked && input.value === 'nearest') {
          void _resolveClientLocation(false);
        }
        _updateCityClearVisibility();
        _updateNearestCityHint();
      });
    });
  }

  function _safeNum(value) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }

  async function _resolveClientLocation(forcePrompt) {
    if (_clientLocation) return _clientLocation;
    if (!navigator.geolocation) return null;
    if (_clientLocationPromise) return _clientLocationPromise;

    if (forcePrompt === false) {
      try {
        const permission = await navigator.permissions?.query?.({ name: 'geolocation' });
        if (permission && permission.state === 'denied') return null;
      } catch (_) {
        // Ignore permission API errors and fall back to the browser prompt.
      }
    }

    _clientLocationPromise = new Promise((resolve) => {
      navigator.geolocation.getCurrentPosition(
        (pos) => {
          const lat = _safeNum(pos?.coords?.latitude);
          const lng = _safeNum(pos?.coords?.longitude);
          if (lat === null || lng === null) {
            resolve(null);
            return;
          }
          _clientLocation = { lat, lng };
          resolve(_clientLocation);
        },
        () => resolve(null),
        {
          enableHighAccuracy: true,
          timeout: 8000,
          maximumAge: 120000,
        }
      );
    });

    const resolved = await _clientLocationPromise;
    _clientLocationPromise = null;
    return resolved;
  }

  function _updateNearestCityHint() {
    const hint = document.getElementById('ur-city-hint');
    const hintText = document.getElementById('ur-city-hint-text');
    const mapLink = document.getElementById('ur-city-map-link');
    if (!hint || !hintText || !mapLink) return;

    const dispatch = document.querySelector('input[name="dispatch_mode"]:checked')?.value || 'all';
    const city = (document.getElementById('ur-city')?.value || '').trim();
    const shouldShow = dispatch === 'nearest' && city;

    hint.classList.toggle('hidden', !shouldShow);
    if (!shouldShow) {
      hintText.textContent = '';
      mapLink.classList.add('hidden');
      mapLink.removeAttribute('href');
      return;
    }

    hintText.textContent = _clientLocation
      ? ('سيتم توجيه الطلب إلى المزوّدين الأقرب لموقعك الحالي داخل ' + city + '.')
      : ('سيتم طلب موقعك الحالي عند الإرسال لتوجيه الطلب إلى الأقرب داخل ' + city + '.');
    const params = new URLSearchParams();
    params.set('city', city);
    params.set('sort', 'nearest');
    params.set('urgent', '1');

    const categoryId = _selectedCategoryId();
    const subcategoryId = _selectedSubcategoryId();
    if (categoryId) params.set('category_id', categoryId);
    if (subcategoryId) params.set('subcategory_id', subcategoryId);

    mapLink.href = '/providers-map/?' + params.toString();
    mapLink.classList.remove('hidden');
  }

  function _selectedCategoryId() {
    return String(document.getElementById('ur-category')?.value || '').trim();
  }

  function _selectedSubcategoryId() {
    return String(document.getElementById('ur-subcategory')?.value || '').trim();
  }

  function _updateCityClearVisibility() {
    const clearBtn = document.getElementById('ur-city-clear');
    if (!clearBtn) return;
    const dispatch = document.querySelector('input[name="dispatch_mode"]:checked')?.value || 'all';
    const cityValue = (document.getElementById('ur-city')?.value || '').trim();
    clearBtn.classList.toggle('hidden', !(dispatch === 'all' && cityValue.length > 0));
  }

  function _bindDescriptionCounter() {
    const textarea = document.getElementById('ur-description');
    const counter = document.getElementById('ur-desc-count');
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
    const sel = document.getElementById('ur-category');
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
    const sel = document.getElementById('ur-category');
    const subSel = document.getElementById('ur-subcategory');
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
    _updateNearestCityHint();
  }

  /* ---- File handling ---- */
  function _onFilesChanged(e) {
    const incoming = Array.from((e && e.target && e.target.files) || []);
    let added = 0;

    incoming.forEach((file) => {
      if (_hasFile(file)) return;
      const kind = _classifyFile(file);

      if (kind === 'image') {
        _images.push(file);
        added += 1;
        return;
      }
      if (kind === 'video') {
        _videos.push(file);
        added += 1;
        return;
      }
      if (kind === 'audio') {
        _audio = file;
        added += 1;
        return;
      }

      _files.push(file);
      added += 1;
    });

    const input = document.getElementById('ur-files');
    if (input) input.value = '';

    _renderAttachments();
    if (!added) _showError('لم تتم إضافة مرفقات جديدة');
  }

  function _fileExt(name) {
    const value = String(name || '');
    const idx = value.lastIndexOf('.');
    return idx === -1 ? '' : value.slice(idx + 1).toLowerCase();
  }

  function _classifyFile(file) {
    const mime = String((file && file.type) || '').toLowerCase();
    const ext = _fileExt((file && file.name) || '');

    if (mime.startsWith('image/') || ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].includes(ext)) return 'image';
    if (mime.startsWith('video/') || ['mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v'].includes(ext)) return 'video';
    if (mime.startsWith('audio/') || ['mp3', 'wav', 'aac', 'ogg', 'm4a'].includes(ext)) return 'audio';
    return 'file';
  }

  function _fileKey(file) {
    return [file.name, file.size, file.lastModified].join('::');
  }

  function _hasFile(file) {
    const key = _fileKey(file);
    if (_images.some((f) => _fileKey(f) === key)) return true;
    if (_videos.some((f) => _fileKey(f) === key)) return true;
    if (_files.some((f) => _fileKey(f) === key)) return true;
    if (_audio && _fileKey(_audio) === key) return true;
    return false;
  }

  function _renderAttachments() {
    const list = document.getElementById('ur-file-list');
    if (!list) return;
    list.innerHTML = '';

    const renderThumbSection = (title, items, kind, removeFn) => {
      if (!items.length) return;
      const section = UI.el('div', { className: 'attach-section' });
      section.appendChild(UI.el('strong', { className: 'attach-section-title', textContent: title }));
      const grid = UI.el('div', { className: 'attach-image-grid' });

      items.forEach((file, idx) => {
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
          removeFn(idx);
          _renderAttachments();
        });

        thumb.appendChild(removeBtn);
        grid.appendChild(thumb);
      });

      section.appendChild(grid);
      list.appendChild(section);
    };

    renderThumbSection('الصور', _images, 'image', (idx) => { _images.splice(idx, 1); });
    renderThumbSection('الفيديو', _videos, 'video', (idx) => { _videos.splice(idx, 1); });

    const renderSection = (title, items, removeFn) => {
      if (!items.length) return;
      const section = UI.el('div', { className: 'attach-section' });
      section.appendChild(UI.el('strong', { className: 'attach-section-title', textContent: title }));

      const rows = UI.el('div', { className: 'attach-rows' });
      items.forEach((file, idx) => {
        const row = UI.el('div', { className: 'file-item' });
        row.appendChild(UI.el('span', { className: 'file-name', textContent: file.name }));

        const removeBtn = UI.el('button', {
          type: 'button',
          className: 'file-remove-btn',
          textContent: 'إزالة',
        });
        removeBtn.addEventListener('click', () => {
          removeFn(idx);
          _renderAttachments();
        });

        row.appendChild(removeBtn);
        rows.appendChild(row);
      });

      section.appendChild(rows);
      list.appendChild(section);
    };

    if (_audio) renderSection('الصوت', [_audio], () => { _audio = null; });
    renderSection('الملفات', _files, (idx) => { _files.splice(idx, 1); });

    if (!_images.length && !_videos.length && !_files.length && !_audio) {
      list.appendChild(UI.el('span', { className: 'attach-empty', textContent: 'لا توجد مرفقات مضافة' }));
    }

    _updateAttachmentSummary();
  }

  function _updateAttachmentSummary() {
    const summary = document.getElementById('ur-file-summary');
    if (!summary) return;

    const parts = [];
    if (_images.length) parts.push(_images.length + ' صورة');
    if (_videos.length) parts.push(_videos.length + ' فيديو');
    if (_audio) parts.push('تسجيل صوتي');
    if (_files.length) parts.push(_files.length + ' ملف');

    summary.textContent = parts.length ? ('تمت إضافة: ' + parts.join(' • ')) : 'لا توجد مرفقات مضافة';
  }

  function _appendRequestFiles(formData) {
    _images.forEach((file) => formData.append('images', file));
    _videos.forEach((file) => formData.append('videos', file));
    _files.forEach((file) => formData.append('files', file));
    if (_audio) formData.append('audio', _audio);
  }

  function _clearAttachments() {
    _images = [];
    _videos = [];
    _files = [];
    _audio = null;
    _renderAttachments();
  }

  /* ---- Submit ---- */
  async function _onSubmit(e) {
    e.preventDefault();
    const btn = document.getElementById('ur-submit');
    if (btn) { btn.disabled = true; btn.innerHTML = '<span class="spinner-inline"></span> جاري الإرسال...'; }

    const desc = document.getElementById('ur-description')?.value?.trim();
    const subcat = document.getElementById('ur-subcategory')?.value;
    const city = document.getElementById('ur-city')?.value;
    const dispatch = document.querySelector('input[name="dispatch_mode"]:checked')?.value || 'all';

    if (!subcat) {
      _showError('اختر التصنيف الفرعي');
      _resetBtn(btn);
      return;
    }

    if (!desc) {
      _showError('يرجى كتابة وصف الطلب');
      _resetBtn(btn);
      return;
    }

    if (dispatch === 'nearest' && !city) {
      _showError('اختر المدينة عند البحث عن الأقرب');
      _resetBtn(btn);
      return;
    }

    let clientLocation = null;
    if (dispatch === 'nearest') {
      clientLocation = await _resolveClientLocation(true);
      if (!clientLocation) {
        _showError('فعّل خدمة الموقع للسماح بتوجيه الطلب إلى المزوّدين الأقرب');
        _resetBtn(btn);
        return;
      }
    }

    const fd = new FormData();
    fd.append('request_type', 'urgent');
    const categorySel = document.getElementById('ur-category');
    const categoryName = categorySel && categorySel.value
      ? String(categorySel.options[categorySel.selectedIndex]?.textContent || '').trim()
      : '';
    fd.append('title', 'طلب عاجل - ' + categoryName);
    fd.append('description', desc);
    fd.append('subcategory', subcat);
    if (city) fd.append('city', city);
    fd.append('dispatch_mode', dispatch);
    if (clientLocation) {
      fd.append('request_lat', String(clientLocation.lat));
      fd.append('request_lng', String(clientLocation.lng));
    }
    _appendRequestFiles(fd);

    const res = await ApiClient.request('/api/marketplace/requests/create/', { method: 'POST', body: fd, formData: true });
    if (res.ok) {
      _clearAttachments();
      const success = document.getElementById('ur-success');
      success?.classList.remove('hidden');
      success?.classList.add('visible');
      setTimeout(() => { window.location.href = '/orders/'; }, 2000);
    } else {
      _showError(res.data?.detail || 'حدث خطأ، حاول مرة أخرى');
    }
    _resetBtn(btn);
  }

  function _showError(msg) {
    let errEl = document.getElementById('ur-error');
    if (!errEl) {
      errEl = UI.el('div', { id: 'ur-error', className: 'form-error' });
      document.getElementById('ur-form')?.prepend(errEl);
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
