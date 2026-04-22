'use strict';

const UrgentRequestPage = (() => {
  const API = {
    categories: '/api/providers/categories/',
    regions: '/api/providers/geo/regions-cities/',
    providers: '/api/providers/list/',
    create: '/api/marketplace/requests/create/',
  };

  const LIMITS = {
    title: 50,
    description: 300,
  };

  const state = {
    categories: [],
    regionCatalog: [],
    images: [],
    videos: [],
    files: [],
    audio: null,
    mediaRecorder: null,
    audioChunks: [],
    isRecording: false,
    isSubmitting: false,
    clientLocation: null,
    locationPromise: null,
    nearbyProviders: [],
    selectedProvider: null,
    map: null,
    clientMarker: null,
    providerMarkers: [],
    toastTimer: null,
  };

  const dom = {};

  function init() {
    cacheDom();
    bindStaticEvents();
    resetSuccessOverlay();
    const serverAuth = window.NAWAFETH_SERVER_AUTH || null;
    const isLoggedIn = !!(
      (window.Auth && typeof Auth.isLoggedIn === 'function' && Auth.isLoggedIn())
      || (serverAuth && serverAuth.isAuthenticated)
    );
    if (isLoggedIn && window.Auth && typeof window.Auth.ensureServiceRequestAccess === 'function' && !window.Auth.ensureServiceRequestAccess({
      gateId: 'auth-gate',
      contentId: 'form-content',
      target: '/urgent-request/',
      title: 'الطلب العاجل متاح في وضع العميل فقط',
      description: 'أنت تستخدم المنصة الآن بوضع مقدم الخدمة، لذلك تم إيقاف إنشاء الطلبات العاجلة من هذا الوضع.',
      note: 'بدّل نوع الحساب إلى عميل الآن، ثم أكمل إرسال الطلب العاجل مباشرة.',
      switchLabel: 'التبديل إلى عميل',
      profileLabel: 'الذهاب إلى نافذتي',
    })) return;
    setAuthState(isLoggedIn);
    if (dom['form-content']?.classList.contains('hidden')) return;
    void bootstrap();
  }

  async function bootstrap() {
    await Promise.all([loadCategories(), loadRegions()]);
    updateDispatchUI();
    updateSummary();
    renderAttachments();
  }

  function cacheDom() {
    [
      'auth-gate', 'form-content', 'ur-form', 'ur-category', 'ur-subcategory', 'ur-region', 'ur-city',
      'ur-city-clear', 'ur-open-map', 'ur-title', 'ur-description', 'ur-title-count', 'ur-title-count-wrap',
      'ur-desc-count', 'ur-desc-count-wrap', 'ur-gallery-input', 'ur-camera-input', 'ur-pdf-input',
      'ur-pick-gallery', 'ur-pick-camera', 'ur-pick-pdf', 'ur-record-audio', 'ur-recording',
      'ur-attachment-summary', 'ur-attachment-list', 'ur-submit', 'ur-success', 'ur-success-message',
      'ur-toast', 'ur-toast-title', 'ur-toast-message', 'ur-toast-close', 'ur-dispatch-summary',
      'ur-summary-service', 'ur-summary-service-sub', 'ur-summary-scope', 'ur-summary-location',
      'ur-summary-attachments', 'ur-summary-provider', 'ur-map-modal', 'ur-map-backdrop',
      'ur-map-close', 'ur-map-canvas', 'ur-map-status', 'ur-map-list', 'ur-map-subtitle',
      'ur-selected-provider', 'ur-provider-image', 'ur-provider-avatar-fallback', 'ur-provider-badge',
      'ur-provider-name', 'ur-provider-location', 'ur-provider-rating', 'ur-provider-completed',
      'ur-provider-distance', 'ur-provider-call', 'ur-provider-whatsapp', 'ur-provider-change',
      'ur-city-required', 'ur-category-error', 'ur-subcategory-error', 'ur-city-error',
      'ur-title-error', 'ur-description-error',
    ].forEach((id) => { dom[id] = document.getElementById(id); });
  }

  function bindStaticEvents() {
    const form = dom['ur-form'];
    if (form) form.addEventListener('submit', onSubmit);

    const category = dom['ur-category'];
    if (category) category.addEventListener('change', onCategoryChange);

    const subcategory = dom['ur-subcategory'];
    if (subcategory) subcategory.addEventListener('change', () => {
      clearFieldError('ur-subcategory');
      updateSummary();
    });

    const region = dom['ur-region'];
    if (region) {
      region.addEventListener('change', () => {
        populateCities('');
        clearFieldError('ur-city');
        updateCityClearButton();
        clearSelectedProvider();
      });
    }

    const city = dom['ur-city'];
    if (city) {
      city.addEventListener('change', () => {
        clearFieldError('ur-city');
        updateCityClearButton();
        updateDispatchUI();
        clearSelectedProvider();
      });
    }

    const clearCity = dom['ur-city-clear'];
    if (clearCity) {
      clearCity.addEventListener('click', () => {
        if (dom['ur-region']) dom['ur-region'].value = '';
        populateCities('');
        if (dom['ur-city']) dom['ur-city'].value = '';
        updateCityClearButton();
        updateDispatchUI();
        clearSelectedProvider();
      });
    }

    document.querySelectorAll('input[name="dispatch_mode"]').forEach((input) => {
      input.addEventListener('change', () => {
        if (input.checked && input.value === 'nearest') {
          void resolveClientLocation(false);
        }
        if (input.checked && input.value === 'all') {
          clearSelectedProvider();
        }
        clearFieldError('ur-city');
        updateDispatchUI();
        updateSummary();
      });
    });

    bindCounter(dom['ur-title'], dom['ur-title-count'], dom['ur-title-count-wrap'], LIMITS.title);
    bindCounter(dom['ur-description'], dom['ur-desc-count'], dom['ur-desc-count-wrap'], LIMITS.description);

    if (dom['ur-pick-gallery'] && dom['ur-gallery-input']) {
      dom['ur-pick-gallery'].addEventListener('click', () => dom['ur-gallery-input'].click());
      dom['ur-gallery-input'].addEventListener('change', (event) => onFilesChosen(event, 'gallery'));
    }
    if (dom['ur-pick-camera'] && dom['ur-camera-input']) {
      dom['ur-pick-camera'].addEventListener('click', () => dom['ur-camera-input'].click());
      dom['ur-camera-input'].addEventListener('change', (event) => onFilesChosen(event, 'camera'));
    }
    if (dom['ur-pick-pdf'] && dom['ur-pdf-input']) {
      dom['ur-pick-pdf'].addEventListener('click', () => dom['ur-pdf-input'].click());
      dom['ur-pdf-input'].addEventListener('change', (event) => onFilesChosen(event, 'pdf'));
    }
    if (dom['ur-record-audio']) {
      dom['ur-record-audio'].addEventListener('click', toggleAudioRecording);
    }

    if (dom['ur-open-map']) dom['ur-open-map'].addEventListener('click', openMapModal);
    if (dom['ur-provider-change']) dom['ur-provider-change'].addEventListener('click', openMapModal);
    if (dom['ur-map-backdrop']) dom['ur-map-backdrop'].addEventListener('click', closeMapModal);
    if (dom['ur-map-close']) dom['ur-map-close'].addEventListener('click', closeMapModal);
    if (dom['ur-toast-close']) dom['ur-toast-close'].addEventListener('click', hideToast);
    window.addEventListener('pageshow', resetSuccessOverlay);
  }

  function setAuthState(isLoggedIn) {
    if (dom['auth-gate']) dom['auth-gate'].classList.toggle('hidden', isLoggedIn);
    if (dom['form-content']) dom['form-content'].classList.toggle('hidden', !isLoggedIn);
  }

  async function loadCategories() {
    try {
      const res = await ApiClient.get(API.categories);
      if (!res.ok || !res.data) return;
      state.categories = Array.isArray(res.data) ? res.data : (res.data.results || []);
      const select = dom['ur-category'];
      if (!select) return;
      select.innerHTML = '<option value="">اختر التصنيف الرئيسي</option>';
      state.categories.forEach((category) => {
        const option = document.createElement('option');
        option.value = String(category.id);
        option.textContent = category.name || ('تصنيف #' + category.id);
        option.dataset.subs = JSON.stringify(Array.isArray(category.subcategories) ? category.subcategories : []);
        select.appendChild(option);
      });
    } catch (_) {
      showToast('تعذر تحميل التصنيفات حاليًا', 'error');
    }
  }

  function onCategoryChange() {
    const categorySelect = dom['ur-category'];
    const subSelect = dom['ur-subcategory'];
    if (!categorySelect || !subSelect) return;
    clearFieldError('ur-category');
    clearFieldError('ur-subcategory');
    subSelect.innerHTML = '<option value="">اختر التصنيف الفرعي</option>';
    const option = categorySelect.options[categorySelect.selectedIndex];
    if (!option || !option.dataset.subs) {
      updateSummary();
      return;
    }
    try {
      const subs = JSON.parse(option.dataset.subs);
      subs.forEach((sub) => {
        const subOption = document.createElement('option');
        subOption.value = String(sub.id);
        subOption.textContent = sub.name || ('فرعي #' + sub.id);
        subSelect.appendChild(subOption);
      });
    } catch (_) {}
    clearSelectedProvider();
  }

  async function loadRegions() {
    try {
      const res = await ApiClient.get(API.regions);
      if (res.ok && res.data) {
        state.regionCatalog = UI.normalizeRegionCatalog(Array.isArray(res.data) ? res.data : (res.data.results || []));
      }
    } catch (_) {}
    if (!state.regionCatalog.length) {
      state.regionCatalog = UI.getRegionCatalogFallback();
    }
    UI.populateRegionOptions(dom['ur-region'], state.regionCatalog, { placeholder: 'اختر المنطقة الإدارية' });
    populateCities('');
    updateCityClearButton();
  }

  function populateCities(selectedValue) {
    UI.populateCityOptions(dom['ur-city'], state.regionCatalog, dom['ur-region']?.value || '', {
      currentValue: selectedValue || '',
      placeholder: 'اختر المدينة',
      emptyPlaceholder: 'اختر المنطقة أولًا ثم المدينة',
    });
  }

  function getDispatchMode() {
    return document.querySelector('input[name="dispatch_mode"]:checked')?.value || 'all';
  }

  function getScopedCity() {
    const region = String(dom['ur-region']?.value || '').trim();
    const city = String(dom['ur-city']?.value || '').trim();
    if (!city) return '';
    return window.UI && typeof UI.formatCityDisplay === 'function'
      ? UI.formatCityDisplay(city, region)
      : (region ? (region + ' - ' + city) : city);
  }

  function updateCityClearButton() {
    const hasCity = !!getScopedCity();
    dom['ur-city-clear']?.classList.toggle('hidden', !hasCity);
  }

  function updateDispatchUI() {
    const dispatch = getDispatchMode();
    const city = getScopedCity();
    const isNearest = dispatch === 'nearest';

    dom['ur-open-map']?.classList.toggle('hidden', !isNearest);
    dom['ur-city-required']?.classList.toggle('hidden', !isNearest);

    if (dom['ur-dispatch-summary']) {
      dom['ur-dispatch-summary'].textContent = isNearest
        ? 'سيتم استخدام موقعك الحالي ثم عرض المزوّدين داخل المدينة المختارة لاختيار مزوّد وإرسال الطلب له مباشرة.'
        : 'سيتم إرسال الطلب لجميع المزوّدين المطابقين للتصنيف، ومع اختيار المدينة سيتم تقييد الإرسال داخلها فقط.';
    }

    if (dom['ur-map-subtitle']) {
      dom['ur-map-subtitle'].textContent = city
        ? ('نتائج المدينة المختارة: ' + city)
        : 'اختر مدينة أولًا ثم افتح الخريطة لعرض المزوّدين الأقرب.';
    }

    if (!isNearest) {
      closeMapModal();
    }
  }

  function bindCounter(input, counter, wrap, limit) {
    if (!input || !counter || !wrap) return;
    const update = () => {
      const length = String(input.value || '').length;
      counter.textContent = String(length);
      wrap.classList.toggle('is-warning', length >= Math.floor(limit * 0.8) && length < limit);
      wrap.classList.toggle('is-limit', length >= limit);
    };
    input.addEventListener('input', update);
    input.addEventListener('input', updateSummary);
    update();
  }

  function fileKey(file) {
    return [file.name, file.size, file.lastModified].join('::');
  }

  function hasFile(file) {
    const key = fileKey(file);
    if (state.images.some((item) => fileKey(item) === key)) return true;
    if (state.videos.some((item) => fileKey(item) === key)) return true;
    if (state.files.some((item) => fileKey(item) === key)) return true;
    return !!(state.audio && fileKey(state.audio) === key);
  }

  function classifyFile(file) {
    const mime = String(file?.type || '').toLowerCase();
    const name = String(file?.name || '').toLowerCase();
    if (mime.startsWith('image/') || /\.(jpg|jpeg|png|gif|webp|bmp)$/i.test(name)) return 'image';
    if (mime.startsWith('video/') || /\.(mp4|mov|avi|mkv|webm|m4v)$/i.test(name)) return 'video';
    if (mime.startsWith('audio/') || /\.(mp3|wav|aac|ogg|m4a|webm)$/i.test(name)) return 'audio';
    return 'file';
  }

  function onFilesChosen(event) {
    const files = Array.from(event?.target?.files || []);
    let added = 0;

    files.forEach((file) => {
      if (hasFile(file)) return;
      const type = classifyFile(file);
      if (type === 'image') {
        state.images.push(file);
      } else if (type === 'video') {
        state.videos.push(file);
      } else if (type === 'audio') {
        state.audio = file;
      } else {
        state.files.push(file);
      }
      added += 1;
    });

    if (event?.target) event.target.value = '';
    renderAttachments();
    if (!added) showToast('لم تتم إضافة مرفقات جديدة', 'warning');
  }

  async function toggleAudioRecording() {
    if (state.isRecording) {
      stopAudioRecording();
      return;
    }
    if (!navigator.mediaDevices?.getUserMedia || typeof MediaRecorder === 'undefined') {
      showToast('التسجيل الصوتي غير مدعوم في هذا المتصفح', 'error');
      return;
    }

    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      state.audioChunks = [];
      state.mediaRecorder = new MediaRecorder(stream);
      state.mediaRecorder.addEventListener('dataavailable', (event) => {
        if (event.data && event.data.size > 0) state.audioChunks.push(event.data);
      });
      state.mediaRecorder.addEventListener('stop', () => {
        stream.getTracks().forEach((track) => track.stop());
        if (!state.audioChunks.length) return;
        const blob = new Blob(state.audioChunks, { type: state.mediaRecorder?.mimeType || 'audio/webm' });
        const file = new File([blob], 'voice-recording.webm', { type: blob.type });
        state.audio = file;
        state.isRecording = false;
        updateRecordingUI();
        renderAttachments();
        showToast('تم حفظ التسجيل الصوتي', 'success');
      });
      state.mediaRecorder.start();
      state.isRecording = true;
      updateRecordingUI();
      showToast('بدأ التسجيل الصوتي', 'info');
    } catch (_) {
      showToast('تعذر الوصول إلى الميكروفون', 'error');
    }
  }

  function stopAudioRecording() {
    if (state.mediaRecorder && state.isRecording) {
      state.mediaRecorder.stop();
    }
    state.isRecording = false;
    updateRecordingUI();
  }

  function updateRecordingUI() {
    dom['ur-recording']?.classList.toggle('hidden', !state.isRecording);
    if (dom['ur-record-audio']) {
      dom['ur-record-audio'].textContent = state.isRecording ? 'إيقاف التسجيل' : 'تسجيل صوت';
    }
  }

  function attachmentCount() {
    return state.images.length + state.videos.length + state.files.length + (state.audio ? 1 : 0);
  }

  function renderAttachments() {
    const root = dom['ur-attachment-list'];
    if (!root) return;
    root.innerHTML = '';

    renderThumbGroup(root, 'الصور', state.images, 'image', (index) => {
      state.images.splice(index, 1);
      renderAttachments();
    });
    renderThumbGroup(root, 'الفيديو', state.videos, 'video', (index) => {
      state.videos.splice(index, 1);
      renderAttachments();
    });
    renderFileGroup(root, 'الملفات', state.files, (index) => {
      state.files.splice(index, 1);
      renderAttachments();
    });
    if (state.audio) {
      renderFileGroup(root, 'التسجيل الصوتي', [state.audio], () => {
        state.audio = null;
        renderAttachments();
      });
    }

    if (!attachmentCount()) {
      const empty = document.createElement('div');
      empty.className = 'ur-attachment-group';
      empty.innerHTML = '<h4>المرفقات</h4><div class="ur-attachment-file"><span>لا توجد مرفقات مضافة.</span></div>';
      root.appendChild(empty);
    }

    updateAttachmentSummary();
    updateSummary();
  }

  function renderThumbGroup(root, title, items, kind, removeHandler) {
    if (!Array.isArray(items) || !items.length) return;
    const group = document.createElement('div');
    group.className = 'ur-attachment-group';
    const heading = document.createElement('h4');
    heading.textContent = title;
    group.appendChild(heading);
    const grid = document.createElement('div');
    grid.className = 'ur-attachment-grid';

    items.forEach((file, index) => {
      const thumb = document.createElement('div');
      thumb.className = 'ur-attachment-thumb';
      const objectUrl = URL.createObjectURL(file);
      let media;
      if (kind === 'video') {
        media = document.createElement('video');
        media.src = objectUrl;
        media.muted = true;
        media.playsInline = true;
        media.preload = 'metadata';
      } else {
        media = document.createElement('img');
        media.src = objectUrl;
        media.alt = file.name || '';
      }
      media.addEventListener('load', () => URL.revokeObjectURL(objectUrl), { once: true });
      media.addEventListener('loadeddata', () => URL.revokeObjectURL(objectUrl), { once: true });
      media.addEventListener('error', () => URL.revokeObjectURL(objectUrl), { once: true });
      thumb.appendChild(media);

      const removeButton = document.createElement('button');
      removeButton.type = 'button';
      removeButton.className = 'ur-remove-btn';
      removeButton.textContent = '×';
      removeButton.addEventListener('click', () => removeHandler(index));
      thumb.appendChild(removeButton);
      grid.appendChild(thumb);
    });

    group.appendChild(grid);
    root.appendChild(group);
  }

  function renderFileGroup(root, title, items, removeHandler) {
    if (!Array.isArray(items) || !items.length) return;
    const group = document.createElement('div');
    group.className = 'ur-attachment-group';
    const heading = document.createElement('h4');
    heading.textContent = title;
    group.appendChild(heading);
    items.forEach((file, index) => {
      const row = document.createElement('div');
      row.className = 'ur-attachment-file';
      const name = document.createElement('span');
      name.textContent = file.name || 'ملف مرفق';
      const removeButton = document.createElement('button');
      removeButton.type = 'button';
      removeButton.className = 'ur-remove-btn';
      removeButton.textContent = '×';
      removeButton.addEventListener('click', () => removeHandler(index));
      row.append(name, removeButton);
      group.appendChild(row);
    });
    root.appendChild(group);
  }

  function updateAttachmentSummary() {
    const summary = dom['ur-attachment-summary'];
    if (!summary) return;
    const parts = [];
    if (state.images.length) parts.push(state.images.length + ' صورة');
    if (state.videos.length) parts.push(state.videos.length + ' فيديو');
    if (state.files.length) parts.push(state.files.length + ' ملف');
    if (state.audio) parts.push('تسجيل صوتي');
    summary.textContent = parts.length
      ? ('تمت إضافة: ' + parts.join(' • '))
      : 'لا توجد مرفقات مضافة حتى الآن.';
  }

  function updateSummary() {
    const categoryName = dom['ur-category']?.selectedOptions?.[0]?.textContent?.trim() || '';
    const subcategoryName = dom['ur-subcategory']?.selectedOptions?.[0]?.textContent?.trim() || '';
    const city = getScopedCity();
    const dispatch = getDispatchMode();
    const provider = state.selectedProvider;

    if (dom['ur-summary-service']) {
      dom['ur-summary-service'].textContent = categoryName ? ('التصنيف: ' + categoryName) : 'التصنيف: غير محدد';
    }
    if (dom['ur-summary-service-sub']) {
      dom['ur-summary-service-sub'].textContent = subcategoryName
        ? ('التخصص الفرعي: ' + subcategoryName)
        : 'اختر التصنيف الفرعي لإكمال المطابقة.';
    }
    if (dom['ur-summary-scope']) {
      dom['ur-summary-scope'].textContent = dispatch === 'nearest' ? 'النطاق: إرسال للأقرب' : 'النطاق: إرسال للجميع';
    }
    if (dom['ur-summary-location']) {
      dom['ur-summary-location'].textContent = city
        ? ('المدينة المحددة: ' + city)
        : (dispatch === 'nearest' ? 'اختر مدينة لعرض المزوّدين على الخريطة.' : 'بدون تقييد مدينة حتى الآن.');
    }
    if (dom['ur-summary-attachments']) {
      dom['ur-summary-attachments'].textContent = 'المرفقات: ' + attachmentCount();
    }
    if (dom['ur-summary-provider']) {
      dom['ur-summary-provider'].textContent = provider
        ? ('المزوّد المختار: ' + provider.display_name)
        : (dispatch === 'nearest' ? 'لم يتم اختيار مزوّد مباشر بعد.' : 'سيتم التوجيه تلقائيًا إلى جميع المزوّدين المطابقين.');
    }
  }

  function clearFieldError(fieldId) {
    const field = document.getElementById(fieldId);
    const error = document.getElementById(fieldId + '-error');
    if (field) {
      field.classList.remove('is-invalid');
      field.removeAttribute('aria-invalid');
    }
    if (error) {
      error.textContent = '';
      error.classList.add('hidden');
    }
  }

  function setFieldError(fieldId, message) {
    const field = document.getElementById(fieldId);
    const error = document.getElementById(fieldId + '-error');
    if (field) {
      field.classList.add('is-invalid');
      field.setAttribute('aria-invalid', 'true');
    }
    if (error) {
      error.textContent = message || '';
      error.classList.toggle('hidden', !message);
    }
  }

  function clearAllErrors() {
    ['ur-category', 'ur-subcategory', 'ur-city', 'ur-title', 'ur-description'].forEach(clearFieldError);
  }

  function focusField(id) {
    const element = document.getElementById(id);
    if (!element) return;
    try { element.focus({ preventScroll: false }); } catch (_) { element.focus(); }
  }

  async function resolveClientLocation(forcePrompt) {
    if (state.clientLocation) return state.clientLocation;
    if (!navigator.geolocation) return null;
    if (state.locationPromise) return state.locationPromise;

    if (forcePrompt === false) {
      try {
        const permission = await navigator.permissions?.query?.({ name: 'geolocation' });
        if (permission && permission.state === 'denied') return null;
      } catch (_) {}
    }

    state.locationPromise = new Promise((resolve) => {
      navigator.geolocation.getCurrentPosition(
        (position) => {
          const lat = safeCoordinate(position?.coords?.latitude);
          const lng = safeCoordinate(position?.coords?.longitude);
          if (lat == null || lng == null) {
            resolve(null);
            return;
          }
          state.clientLocation = { lat, lng };
          resolve(state.clientLocation);
        },
        () => resolve(null),
        { enableHighAccuracy: true, timeout: 9000, maximumAge: 120000 }
      );
    });

    const result = await state.locationPromise;
    state.locationPromise = null;
    return result;
  }

  function safeCoordinate(value) {
    const number = Number(value);
    return Number.isFinite(number) ? Number(number.toFixed(6)) : null;
  }

  function haversineDistanceKm(lat1, lng1, lat2, lng2) {
    const toRad = (value) => (value * Math.PI) / 180;
    const earth = 6371;
    const dLat = toRad(lat2 - lat1);
    const dLng = toRad(lng2 - lng1);
    const a = Math.sin(dLat / 2) ** 2
      + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
    return earth * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  }

  async function openMapModal() {
    if (getDispatchMode() !== 'nearest') {
      showToast('هذه النافذة مخصصة لنمط الإرسال للأقرب', 'warning');
      return;
    }
    if (!dom['ur-category']?.value) {
      setFieldError('ur-category', 'اختر التصنيف الرئيسي أولًا');
      focusField('ur-category');
      showToast('اختر التصنيف الرئيسي قبل فتح الخريطة', 'warning');
      return;
    }
    if (!dom['ur-subcategory']?.value) {
      setFieldError('ur-subcategory', 'اختر التصنيف الفرعي أولًا');
      focusField('ur-subcategory');
      showToast('اختر التصنيف الفرعي قبل فتح الخريطة', 'warning');
      return;
    }
    const city = getScopedCity();
    if (!city) {
      setFieldError('ur-city', 'اختر المدينة عند الإرسال للأقرب');
      focusField('ur-city');
      showToast('اختر المدينة قبل فتح الخريطة', 'warning');
      return;
    }

    dom['ur-map-modal']?.classList.add('open');
    dom['ur-map-modal']?.setAttribute('aria-hidden', 'false');
    if (dom['ur-map-status']) dom['ur-map-status'].textContent = 'جارٍ تحميل موقعك ونتائج المزوّدين...';
    ensureMap();

    const location = await resolveClientLocation(true);
    if (!location) {
      closeMapModal();
      showToast('فعّل خدمة الموقع لاستخدام اختيار الأقرب على الخريطة', 'error');
      return;
    }

    await fetchNearbyProviders(location);
    renderMapProviders(location);
    renderProviderCards();
  }

  function closeMapModal() {
    dom['ur-map-modal']?.classList.remove('open');
    dom['ur-map-modal']?.setAttribute('aria-hidden', 'true');
  }

  function ensureMap() {
    if (state.map || typeof L === 'undefined' || !dom['ur-map-canvas']) return;
    state.map = L.map(dom['ur-map-canvas'], { scrollWheelZoom: false, zoomControl: true }).setView([24.7136, 46.6753], 10);
    L.tileLayer('https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png', {
      attribution: '&copy; OpenStreetMap &copy; CARTO',
      subdomains: 'abcd',
      maxZoom: 19,
    }).addTo(state.map);
    setTimeout(() => state.map?.invalidateSize(), 250);
  }

  async function fetchNearbyProviders(location) {
    const params = new URLSearchParams();
    params.set('city', getScopedCity());
    params.set('has_location', '1');
    params.set('accepts_urgent', '1');
    if (dom['ur-category']?.value) params.set('category_id', String(dom['ur-category'].value));
    if (dom['ur-subcategory']?.value) params.set('subcategory_id', String(dom['ur-subcategory'].value));

    try {
      const res = await ApiClient.get(API.providers + '?' + params.toString());
      if (!res.ok || !res.data) {
        state.nearbyProviders = [];
        return;
      }
      const rawResults = Array.isArray(res.data) ? res.data : (res.data.results || []);
      state.nearbyProviders = rawResults
        .map((provider) => normalizeProvider(provider, location))
        .filter(Boolean)
        .sort((a, b) => a._distance - b._distance);
      if (dom['ur-map-status']) {
        dom['ur-map-status'].textContent = state.nearbyProviders.length
          ? ('تم العثور على ' + state.nearbyProviders.length + ' مزوّد داخل النطاق.')
          : 'لا يوجد مزوّدون مطابقون بهذه المدينة والتصنيف حاليًا.';
      }
    } catch (_) {
      state.nearbyProviders = [];
      if (dom['ur-map-status']) dom['ur-map-status'].textContent = 'تعذر تحميل المزوّدين الآن.';
      showToast('تعذر تحميل المزوّدين على الخريطة', 'error');
    }
  }

  function normalizeProvider(provider, location) {
    const lat = Number(provider?.lat);
    const lng = Number(provider?.lng);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
    const distance = haversineDistanceKm(location.lat, location.lng, lat, lng);
    return {
      ...provider,
      lat,
      lng,
      display_name: provider.display_name || provider.username || ('مزود #' + provider.id),
      profile_href: '/provider/' + encodeURIComponent(String(provider.id || '')) + '/',
      _distance: distance,
    };
  }

  function renderMapProviders(location) {
    if (!state.map || typeof L === 'undefined') return;
    state.providerMarkers.forEach((marker) => state.map.removeLayer(marker));
    state.providerMarkers = [];

    if (state.clientMarker) {
      state.map.removeLayer(state.clientMarker);
      state.clientMarker = null;
    }

    state.clientMarker = L.marker([location.lat, location.lng]).addTo(state.map).bindPopup('موقعك الحالي');

    state.nearbyProviders.forEach((provider) => {
      const marker = L.marker([provider.lat, provider.lng]).addTo(state.map);
      marker.bindPopup(buildPopupHtml(provider), { className: 'ur-map-popup', maxWidth: 260 });
      marker.on('popupopen', () => bindPopupActions(provider));
      state.providerMarkers.push(marker);
    });

    const points = state.nearbyProviders.map((provider) => [provider.lat, provider.lng]);
    points.push([location.lat, location.lng]);
    if (points.length > 1) {
      state.map.fitBounds(points, { padding: [40, 40], maxZoom: 13 });
    } else {
      state.map.setView([location.lat, location.lng], 13);
    }
    setTimeout(() => state.map?.invalidateSize(), 150);
  }

  function buildPopupHtml(provider) {
    const badgeClass = provider.is_verified_blue ? 'blue' : (provider.is_verified_green ? 'green' : '');
    const badge = badgeClass
      ? '<span class="ur-provider-badge ' + badgeClass + '"><svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor"><path d="M9 16.17 4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z"/></svg></span>'
      : '';
    const image = provider.profile_image
      ? '<img src="' + escapeHtml(provider.profile_image) + '" alt="">'
      : '<div class="ur-provider-avatar-fallback">' + escapeHtml((provider.display_name || 'م').charAt(0)) + '</div>';
    const call = provider.phone
      ? '<a class="call" href="tel:' + escapeHtml(provider.phone) + '">اتصال</a>'
      : '<span class="call" style="opacity:.45;pointer-events:none">اتصال</span>';
    const whatsapp = provider.whatsapp_url
      ? '<a class="whatsapp" target="_blank" rel="noopener" href="' + escapeHtml(provider.whatsapp_url) + '">واتس</a>'
      : '<span class="whatsapp" style="opacity:.45;pointer-events:none">واتس</span>';
    return [
      '<div class="ur-popup">',
      '<div class="ur-popup-head">',
      '<div class="ur-popup-avatar">' + image + badge + '</div>',
      '<div><div class="ur-popup-title">' + escapeHtml(provider.display_name) + '</div>',
      '<div class="ur-popup-meta">⭐ ' + formatRating(provider.rating_avg) + ' • ' + String(provider.completed_requests || 0) + ' مكتملة</div></div>',
      '</div>',
      '<div class="ur-popup-actions">',
      call,
      whatsapp,
      '<button class="send" type="button" data-provider-select="' + String(provider.id) + '">إرسال الطلب</button>',
      '</div>',
      '</div>',
    ].join('');
  }

  function bindPopupActions(provider) {
    const button = document.querySelector('[data-provider-select="' + String(provider.id) + '"]');
    if (!button) return;
    button.addEventListener('click', () => selectProvider(provider), { once: true });
  }

  function renderProviderCards() {
    const list = dom['ur-map-list'];
    if (!list) return;
    list.innerHTML = '';
    if (!state.nearbyProviders.length) {
      const empty = document.createElement('div');
      empty.className = 'ur-map-empty';
      empty.textContent = 'لا يوجد مزوّدون مطابقون في المدينة المختارة حاليًا.';
      list.appendChild(empty);
      return;
    }

    state.nearbyProviders.forEach((provider) => {
      const card = document.createElement('div');
      card.className = 'ur-provider-card' + (state.selectedProvider?.id === provider.id ? ' selected' : '');

      const badgeClass = provider.is_verified_blue ? 'blue' : (provider.is_verified_green ? 'green' : '');
      const badgeHtml = badgeClass
        ? '<span class="ur-provider-badge ' + badgeClass + '"><svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor"><path d="M9 16.17 4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z"/></svg></span>'
        : '';
      const avatarHtml = provider.profile_image
        ? '<img src="' + escapeHtml(provider.profile_image) + '" alt="صورة المزوّد">'
        : '<div class="ur-provider-avatar-fallback">' + escapeHtml((provider.display_name || 'م').charAt(0)) + '</div>';

      card.innerHTML = [
        '<div class="ur-provider-card-head">',
        '<div class="ur-provider-card-avatar">' + avatarHtml + badgeHtml + '</div>',
        '<div style="min-width:0;flex:1 1 auto">',
        '<h4 class="ur-provider-card-name">' + escapeHtml(provider.display_name) + '</h4>',
        '<div class="ur-provider-card-sub">',
        '<span>⭐ ' + formatRating(provider.rating_avg) + '</span>',
        '<span>' + String(provider.completed_requests || 0) + ' مكتملة</span>',
        '<span>' + provider._distance.toFixed(1) + ' كم</span>',
        '</div>',
        '</div>',
        '</div>',
        '<div class="ur-provider-card-actions">',
        provider.phone ? '<a href="tel:' + escapeHtml(provider.phone) + '" class="ur-action-btn ur-action-call">اتصال</a>' : '',
        provider.whatsapp_url ? '<a href="' + escapeHtml(provider.whatsapp_url) + '" target="_blank" rel="noopener" class="ur-action-btn ur-action-whatsapp">واتس</a>' : '',
        '<button type="button" class="ur-action-btn ur-action-send" data-select-provider="' + String(provider.id) + '">إرسال الطلب</button>',
        '</div>',
      ].join('');

      const avatar = card.querySelector('.ur-provider-card-avatar');
      if (avatar) {
        avatar.addEventListener('click', () => { window.location.href = provider.profile_href; });
      }
      const selectButton = card.querySelector('[data-select-provider]');
      if (selectButton) {
        selectButton.addEventListener('click', () => selectProvider(provider));
      }
      list.appendChild(card);
    });
  }

  function selectProvider(provider) {
    state.selectedProvider = provider;
    hydrateSelectedProvider();
    renderProviderCards();
    updateSummary();
    closeMapModal();
    showToast('تم اختيار المزوّد ويمكنك الآن إرسال الطلب مباشرة له', 'success');
  }

  function clearSelectedProvider(update = true) {
    state.selectedProvider = null;
    if (update) {
      hydrateSelectedProvider();
      updateSummary();
    } else {
      hydrateSelectedProvider();
    }
  }

  function hydrateSelectedProvider() {
    const provider = state.selectedProvider;
    dom['ur-selected-provider']?.classList.toggle('hidden', !provider || getDispatchMode() !== 'nearest');
    if (!provider) {
      if (dom['ur-provider-name']) dom['ur-provider-name'].textContent = 'لم يتم اختيار مزوّد بعد';
      return;
    }

    if (dom['ur-provider-name']) dom['ur-provider-name'].textContent = provider.display_name;
    if (dom['ur-provider-location']) dom['ur-provider-location'].textContent = provider.city_display || getScopedCity() || 'ضمن المدينة المختارة';
    if (dom['ur-provider-rating']) dom['ur-provider-rating'].textContent = 'التقييم ' + formatRating(provider.rating_avg);
    if (dom['ur-provider-completed']) dom['ur-provider-completed'].textContent = 'المكتملة ' + String(provider.completed_requests || 0);
    if (dom['ur-provider-distance']) dom['ur-provider-distance'].textContent = 'المسافة ' + provider._distance.toFixed(1) + ' كم';

    const badge = dom['ur-provider-badge'];
    if (badge) {
      const badgeClass = provider.is_verified_blue ? 'blue' : (provider.is_verified_green ? 'green' : '');
      badge.className = 'ur-provider-badge' + (badgeClass ? (' ' + badgeClass) : ' hidden');
      if (badgeClass) {
        badge.innerHTML = '<svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor"><path d="M9 16.17 4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z"/></svg>';
      } else {
        badge.innerHTML = '';
      }
      badge.classList.toggle('hidden', !badgeClass);
    }

    const image = dom['ur-provider-image'];
    const fallback = dom['ur-provider-avatar-fallback'];
    if (image && fallback) {
      if (provider.profile_image) {
        image.src = provider.profile_image;
        image.classList.remove('hidden');
        fallback.classList.add('hidden');
      } else {
        image.removeAttribute('src');
        image.classList.add('hidden');
        fallback.textContent = (provider.display_name || 'م').charAt(0);
        fallback.classList.remove('hidden');
      }
      image.onclick = () => { window.location.href = provider.profile_href; };
    }

    const call = dom['ur-provider-call'];
    if (call) {
      if (provider.phone) {
        call.href = 'tel:' + provider.phone;
        call.classList.remove('hidden');
      } else {
        call.classList.add('hidden');
      }
    }
    const whatsapp = dom['ur-provider-whatsapp'];
    if (whatsapp) {
      if (provider.whatsapp_url) {
        whatsapp.href = provider.whatsapp_url;
        whatsapp.classList.remove('hidden');
      } else {
        whatsapp.classList.add('hidden');
      }
    }
  }

  function formatRating(value) {
    const rating = Number(value);
    return Number.isFinite(rating) ? rating.toFixed(1) : '—';
  }

  function appendRequestFiles(formData) {
    state.images.forEach((file) => formData.append('images', file));
    state.videos.forEach((file) => formData.append('videos', file));
    state.files.forEach((file) => formData.append('files', file));
    if (state.audio) formData.append('audio', state.audio);
  }

  function validateForm() {
    clearAllErrors();
    const category = String(dom['ur-category']?.value || '').trim();
    const subcategory = String(dom['ur-subcategory']?.value || '').trim();
    const title = String(dom['ur-title']?.value || '').trim();
    const description = String(dom['ur-description']?.value || '').trim();
    const city = getScopedCity();
    const dispatch = getDispatchMode();

    if (!category) {
      setFieldError('ur-category', 'اختر التصنيف الرئيسي');
      focusField('ur-category');
      return 'اختر التصنيف الرئيسي';
    }
    if (!subcategory) {
      setFieldError('ur-subcategory', 'اختر التصنيف الفرعي');
      focusField('ur-subcategory');
      return 'اختر التصنيف الفرعي';
    }
    if (!title) {
      setFieldError('ur-title', 'أدخل عنوان الطلب');
      focusField('ur-title');
      return 'أدخل عنوان الطلب';
    }
    if (!description) {
      setFieldError('ur-description', 'أدخل تفاصيل الطلب');
      focusField('ur-description');
      return 'أدخل تفاصيل الطلب';
    }
    if (dispatch === 'nearest' && !city) {
      setFieldError('ur-city', 'اختر المدينة عند الإرسال للأقرب');
      focusField('ur-city');
      return 'اختر المدينة عند الإرسال للأقرب';
    }
    if (dispatch === 'nearest' && !state.selectedProvider) {
      showToast('اختر مزوّدًا من الخريطة قبل الإرسال', 'warning');
      return 'اختر مزوّدًا من الخريطة قبل الإرسال';
    }
    return '';
  }

  function applyApiErrors(data) {
    if (!data || typeof data !== 'object') return '';
    const fieldMap = {
      subcategory: 'ur-subcategory',
      subcategory_ids: 'ur-subcategory',
      city: 'ur-city',
      title: 'ur-title',
      description: 'ur-description',
      provider: 'ur-city',
      request_lat: 'ur-city',
      request_lng: 'ur-city',
    };
    let first = '';
    Object.entries(fieldMap).forEach(([apiField, fieldId]) => {
      const message = firstErrorMessage(data[apiField]);
      if (!message) return;
      setFieldError(fieldId, message);
      if (!first) first = message;
    });
    if (first) return first;
    for (const value of Object.values(data)) {
      const message = firstErrorMessage(value);
      if (message) return message;
    }
    return '';
  }

  function firstErrorMessage(value) {
    if (typeof value === 'string' && value.trim()) return value.trim();
    if (Array.isArray(value) && value.length) return String(value[0] || '').trim();
    return '';
  }

  async function onSubmit(event) {
    event.preventDefault();
    if (state.isSubmitting) return;

    const validationMessage = validateForm();
    if (validationMessage) {
      showToast(validationMessage, 'warning');
      return;
    }

    const dispatch = getDispatchMode();
    const city = getScopedCity();
    const title = String(dom['ur-title']?.value || '').trim();
    const description = String(dom['ur-description']?.value || '').trim();
    const subcategory = String(dom['ur-subcategory']?.value || '').trim();

    state.isSubmitting = true;
    setSubmitPending(true);

    try {
      let location = null;
      if (dispatch === 'nearest') {
        location = await resolveClientLocation(true);
        if (!location) {
          showToast('فعّل خدمة الموقع لإرسال الطلب للأقرب', 'error');
          return;
        }
      }

      const formData = new FormData();
      formData.append('request_type', 'urgent');
      formData.append('title', title);
      formData.append('description', description);
      formData.append('subcategory', subcategory);
      formData.append('subcategory_ids', subcategory);
      formData.append('dispatch_mode', dispatch);
      if (city) formData.append('city', city);
      if (dispatch === 'nearest' && location) {
        formData.append('request_lat', String(location.lat));
        formData.append('request_lng', String(location.lng));
      }
      if (dispatch === 'nearest' && state.selectedProvider?.id) {
        formData.append('provider', String(state.selectedProvider.id));
      }
      appendRequestFiles(formData);

      const res = await ApiClient.request(API.create, {
        method: 'POST',
        body: formData,
        formData: true,
      });

      if (res.ok) {
        onSubmitSuccess(dispatch);
      } else {
        const message = applyApiErrors(res.data) || res.data?.detail || 'تعذر إرسال الطلب حاليًا';
        showToast(message, 'error');
      }
    } catch (_) {
      showToast('تعذر الاتصال بالخادم، حاول مرة أخرى', 'error');
    } finally {
      state.isSubmitting = false;
      setSubmitPending(false);
    }
  }

  function setSubmitPending(isPending) {
    const button = dom['ur-submit'];
    if (!button) return;
    if (isPending) {
      button.disabled = true;
      button.textContent = 'جارٍ إرسال الطلب...';
      return;
    }
    button.disabled = false;
    button.textContent = 'إرسال الطلب العاجل';
  }

  function onSubmitSuccess(dispatch) {
    state.images = [];
    state.videos = [];
    state.files = [];
    state.audio = null;
    renderAttachments();
    if (dom['ur-success-message']) {
      dom['ur-success-message'].textContent = dispatch === 'nearest' && state.selectedProvider
        ? ('تم إنشاء الطلب العاجل وتوجيهه مباشرة إلى ' + state.selectedProvider.display_name + '. سيتم تحويلك إلى صفحة الطلبات الآن.')
        : 'تم إنشاء الطلب العاجل وإرساله إلى جميع المزوّدين المطابقين. سيتم تحويلك إلى صفحة الطلبات الآن.';
    }
    dom['ur-success']?.classList.remove('hidden');
    dom['ur-success']?.classList.add('visible');
    setTimeout(() => { window.location.href = '/orders/'; }, 1800);
  }

  function resetSuccessOverlay() {
    dom['ur-success']?.classList.remove('visible');
    dom['ur-success']?.classList.add('hidden');
  }

  function hideToast() {
    dom['ur-toast']?.classList.remove('show');
    if (state.toastTimer) {
      clearTimeout(state.toastTimer);
      state.toastTimer = null;
    }
  }

  function showToast(message, tone) {
    const toast = dom['ur-toast'];
    if (!toast) {
      window.alert(message || '');
      return;
    }
    hideToast();
    const type = ['success', 'warning', 'error', 'info'].includes(tone) ? tone : 'info';
    toast.className = 'ur-toast ' + type;
    if (dom['ur-toast-title']) {
      dom['ur-toast-title'].textContent = ({
        success: 'تم بنجاح',
        warning: 'تنبيه',
        error: 'تعذر التنفيذ',
        info: 'معلومة',
      })[type];
    }
    if (dom['ur-toast-message']) dom['ur-toast-message'].textContent = message || '';
    requestAnimationFrame(() => toast.classList.add('show'));
    state.toastTimer = setTimeout(hideToast, 4600);
  }

  function escapeHtml(value) {
    const div = document.createElement('div');
    div.appendChild(document.createTextNode(String(value || '')));
    return div.innerHTML;
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  return {};
})();
