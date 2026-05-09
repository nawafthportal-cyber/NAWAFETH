/* ===================================================================
   requestQuotePage.js — Request Quote (competitive) form controller
   POST /api/marketplace/requests/create/  (request_type='competitive')
   =================================================================== */
'use strict';

const RequestQuotePage = (() => {
  let _images = [];
  let _videos = [];
  let _files = [];
  let _audio = null;
  let _toastTimer = null;
  let _languageObserver = null;
  let _languageSyncTimer = null;
  let _lastAppliedLang = null;
  let _clientLocation = null;
  let _locationPromise = null;
  let _resolvedScopeLocation = null;
  let _reverseLocationPromise = null;
  const quoteContext = window.NAWAFETH_REQUEST_QUOTE_CONTEXT || {};
  const COPY = {
    ar: {
      pageTitle: 'نوافــذ — طلب عروض أسعار',
      providerGateKicker: 'وضع الحساب الحالي',
      providerGateTitle: 'طلب عروض الأسعار متاح في وضع العميل فقط',
      providerGateDescription: 'أنت تستخدم المنصة الآن بوضع مقدم الخدمة، لذلك لا يمكن إنشاء طلب عروض أسعار من هذا الوضع.',
      providerGateNote: 'بدّل نوع الحساب إلى عميل الآن، ثم أكمل طلب عروض الأسعار مباشرة.',
      providerGateSwitch: 'التبديل إلى عميل',
      providerGateProfile: 'الذهاب إلى نافذتي',
      loginGateTitle: 'سجّل دخولك لطلب عرض سعر',
      loginGateDescription: 'يمكنك تلقي عروض الأسعار بعد تسجيل الدخول',
      loginGateButton: 'تسجيل الدخول',
      heroBadge: 'عروض أسعار تنافسية',
      heroTitle: 'استقبل عروض أسعار من المزودين الأنسب',
      backAria: 'رجوع',
      headerTitle: 'طلب عروض أسعار',
      pageBadge: 'طلب تنافسي',
      subtitle: 'صِف الطلب بدقة لتحصل على عروض مناسبة بشكل أسرع وضمن هوية موحدة مع تجربة المنصة.',
      introChip: 'خطوات سريعة',
      introText: 'اكتب العنوان والتفاصيل، اختر التصنيف، ثم أضف المرفقات إذا لزم.',
      titleLabel: 'عنوان الطلب',
      titlePlaceholder: 'مثال: تصميم شعار لمتجر إلكتروني',
      titleHint: 'العنوان الواضح يزيد فرص وصول عروض دقيقة.',
      categoryLabel: 'التصنيف الرئيسي',
      categoryPlaceholder: 'اختر التصنيف...',
      subcategoryLabel: 'التصنيف الفرعي',
      subcategoryPlaceholder: '-- اختر التخصص --',
      regionLabel: 'المنطقة الإدارية',
      regionPlaceholder: 'اختر المنطقة الإدارية',
      cityLabel: 'المدينة',
      cityPlaceholder: 'اختر المدينة (اختياري)',
      cityEmptyPlaceholder: 'اختر المنطقة أولًا ثم المدينة...',
      cityClear: 'إلغاء المدينة (إرسال لجميع المدن)',
      deadlineLabel: 'آخر موعد لاستلام العروض (اختياري)',
      detailsLabel: 'تفاصيل الطلب',
      detailsPlaceholder: 'صِف الخدمة المطلوبة بالتفصيل...',
      filesLabel: 'مرفقات (اختياري)',
      fileTrigger: 'إرفاق صور/فيديو/صوت أو ملفات',
      uploadHint: 'يمكنك رفع أكثر من ملف، وسيتم إرسالها مع الطلب مباشرة.',
      attachmentEmpty: 'لا توجد مرفقات مضافة',
      attachmentPreparedOne: 'تمت إضافة مرفق واحد',
      attachmentPreparedMany: 'تم تجهيز المرفقات',
      cancel: 'إلغاء',
      submit: 'تقديم الطلب',
      submitLoading: 'جاري إرسال الطلب',
      submitStateTitle: 'جاري إرسال الطلب',
      submitStateMessage: 'يتم الآن تجهيز بيانات الطلب ورفع المرفقات.',
      submitStateProgressAria: 'نسبة رفع الطلب',
      successTitle: 'تم إرسال طلبك بنجاح!',
      successMessage: 'سيتقدم المزودون بعروضهم خلال الفترة القادمة. تابع من صفحة الطلبات',
      successOrders: 'متابعة الطلبات',
      successHome: 'العودة للرئيسية',
      toastDefaultTitle: 'تنبيه مهم',
      toastDefaultMessage: 'ستظهر هنا رسائل التحقق والتنبيه أثناء إرسال الطلب.',
      toastCloseAria: 'إغلاق التنبيه',
      toneInfo: 'معلومة سريعة',
      toneSuccess: 'تم بنجاح',
      toneWarning: 'انتبه قبل المتابعة',
      toneError: 'تعذر إكمال الطلب',
      warningAudioSingle: 'يمكن إرفاق تسجيل صوتي واحد فقط مع الطلب',
      warningNoNewAttachments: 'لم تتم إضافة مرفقات جديدة',
      sectionImages: 'الصور',
      sectionVideos: 'الفيديو',
      sectionAudio: 'الصوت',
      sectionFiles: 'الملفات',
      removeVideo: 'إزالة الفيديو',
      removeImage: 'إزالة الصورة',
      removeFile: 'إزالة',
      validationTitleRequired: 'يرجى كتابة عنوان الطلب',
      validationCategoryRequired: 'يرجى اختيار التصنيف الرئيسي',
      validationSubcategoryRequired: 'يرجى اختيار التصنيف الفرعي',
      validationDetailsRequired: 'يرجى كتابة تفاصيل الطلب',
      validationDetailsTooLong: 'تفاصيل الطلب يجب ألا تتجاوز 500 حرف',
      validationTitleTooLong: 'عنوان الطلب يجب ألا يتجاوز 50 حرفًا',
      enableLocationGeoScope: 'فعّل خدمة الموقع لتحديد مدينة الطلب تلقائيًا قبل إرسال طلب عروض الأسعار',
      locationRequiredTitle: 'حدد موقعك لمتابعة الطلب',
      locationRequiredBody: 'هذه الخدمة تتطلب تحديد موقعك على الخريطة لإرسال طلب عرض السعر لمزودي مدينتك.',
      detectLocationFailed: 'تعذر تحديد مدينة واضحة من موقعك الحالي. حاول مرة أخرى.',
      submitUploadingWithAttachments: 'يتم الآن رفع {count} مع بيانات الطلب. لا تغلق الصفحة حتى يكتمل الإرسال.',
      submitUploadingNoAttachments: 'يتم الآن إرسال بيانات الطلب. لا تغلق الصفحة حتى يكتمل الإرسال.',
      submitPreparingAttachments: 'جاري تجهيز المرفقات',
      submitPreparingAttachmentsMessage: 'تم تجهيز {count} وبدء رفعها الآن.',
      submitUploadingAttachments: 'جاري رفع المرفقات',
      submitUploadingAttachmentsMessage: 'تم رفع {percent}% من الطلب حتى الآن. انتظر قليلًا حتى يكتمل الإرسال.',
      submitApproving: 'جاري اعتماد الطلب',
      submitApprovingMessage: 'اكتمل رفع البيانات، وجارٍ اعتماد الطلب وإظهاره للمزوّدين.',
      submitSendingPlatform: 'يتم الآن إرسال بيانات الطلب إلى المنصة.',
      attachmentTypeFile: 'ملف',
      attachmentTypeImage: 'صورة',
      attachmentTypeVideo: 'فيديو',
      attachmentTypeAudio: 'تسجيل صوتي',
      attachmentTypeGeneralFile: 'ملف عام',
      attachmentWithoutAny: 'بدون مرفقات',
      attachmentOne: 'مرفق واحد',
      attachmentTwo: 'مرفقان',
      attachmentMany: '{count} مرفقات',
      attachmentNoteMessage: 'تمت إضافة {items}، وستُرسل مع الطلب مباشرة عند الإرسال.',
      submitErrorFallback: 'تعذر إرسال الطلب، تحقق من البيانات وحاول مرة أخرى',
      serverConnectionError: 'تعذر الاتصال بالخادم، حاول مرة أخرى',
    },
    en: {
      pageTitle: 'Nawafeth — Request Quotes',
      providerGateKicker: 'Current account mode',
      providerGateTitle: 'Quote requests are only available in client mode',
      providerGateDescription: 'You are using the platform in provider mode right now, so a quote request cannot be created from this mode.',
      providerGateNote: 'Switch to client mode now, then continue your quote request right away.',
      providerGateSwitch: 'Switch to client',
      providerGateProfile: 'Go to My Profile',
      loginGateTitle: 'Sign in to request quotes',
      loginGateDescription: 'You can receive quote offers after signing in',
      loginGateButton: 'Sign in',
      heroBadge: 'Competitive quotes',
      heroTitle: 'Receive quotes from the most suitable providers',
      backAria: 'Back',
      headerTitle: 'Request quotes',
      pageBadge: 'Competitive request',
      subtitle: 'Describe your request clearly to receive suitable offers faster while keeping the platform experience consistent.',
      introChip: 'Quick steps',
      introText: 'Write the title and details, choose the category, then add attachments if needed.',
      titleLabel: 'Request title',
      titlePlaceholder: 'Example: Logo design for an online store',
      titleHint: 'A clear title improves your chances of getting accurate offers.',
      categoryLabel: 'Main category',
      categoryPlaceholder: 'Choose a category...',
      subcategoryLabel: 'Subcategory',
      subcategoryPlaceholder: '-- Choose a specialty --',
      regionLabel: 'Administrative region',
      regionPlaceholder: 'Choose an administrative region',
      cityLabel: 'City',
      cityPlaceholder: 'Choose a city (optional)',
      cityEmptyPlaceholder: 'Choose the region first, then the city...',
      cityClear: 'Clear city (send to all cities)',
      deadlineLabel: 'Quote deadline (optional)',
      detailsLabel: 'Request details',
      detailsPlaceholder: 'Describe the requested service in detail...',
      filesLabel: 'Attachments (optional)',
      fileTrigger: 'Attach images, video, audio, or files',
      uploadHint: 'You can upload multiple files and they will be sent with the request directly.',
      attachmentEmpty: 'No attachments added',
      attachmentPreparedOne: 'One attachment added',
      attachmentPreparedMany: 'Attachments are ready',
      cancel: 'Cancel',
      submit: 'Submit request',
      submitLoading: 'Submitting request',
      submitStateTitle: 'Submitting request',
      submitStateMessage: 'Preparing your request data and uploading attachments.',
      submitStateProgressAria: 'Request upload progress',
      successTitle: 'Your request was sent successfully!',
      successMessage: 'Providers will start sending offers soon. Track everything from the orders page.',
      successOrders: 'Track orders',
      successHome: 'Back to home',
      toastDefaultTitle: 'Important notice',
      toastDefaultMessage: 'Validation and submission messages will appear here.',
      toastCloseAria: 'Close notification',
      toneInfo: 'Quick info',
      toneSuccess: 'Done successfully',
      toneWarning: 'Check before continuing',
      toneError: 'Could not complete the request',
      warningAudioSingle: 'Only one voice recording can be attached to the request',
      warningNoNewAttachments: 'No new attachments were added',
      sectionImages: 'Images',
      sectionVideos: 'Videos',
      sectionAudio: 'Audio',
      sectionFiles: 'Files',
      removeVideo: 'Remove video',
      removeImage: 'Remove image',
      removeFile: 'Remove',
      validationTitleRequired: 'Please enter a request title',
      validationCategoryRequired: 'Please choose the main category',
      validationSubcategoryRequired: 'Please choose the subcategory',
      validationDetailsRequired: 'Please enter the request details',
      validationDetailsTooLong: 'Request details must not exceed 500 characters',
      validationTitleTooLong: 'Request title must not exceed 50 characters',
      enableLocationGeoScope: 'Enable location access so the request city can be detected automatically before submitting the quote request.',
      locationRequiredTitle: 'Set your location to continue',
      locationRequiredBody: 'This service requires you to pin your location on the map so the quote request can reach providers in your city.',
      detectLocationFailed: 'Could not determine a clear city from your current location. Please try again.',
      submitUploadingWithAttachments: 'Uploading {count} with the request data. Do not close the page until sending is complete.',
      submitUploadingNoAttachments: 'Sending your request data now. Do not close the page until it finishes.',
      submitPreparingAttachments: 'Preparing attachments',
      submitPreparingAttachmentsMessage: '{count} prepared and upload has just started.',
      submitUploadingAttachments: 'Uploading attachments',
      submitUploadingAttachmentsMessage: '{percent}% of the request has been uploaded so far. Please wait a moment until it completes.',
      submitApproving: 'Finalizing request',
      submitApprovingMessage: 'The data upload is complete and the request is being finalized for providers.',
      submitSendingPlatform: 'Sending the request data to the platform.',
      attachmentTypeFile: 'file',
      attachmentTypeImage: 'image',
      attachmentTypeVideo: 'video',
      attachmentTypeAudio: 'voice note',
      attachmentTypeGeneralFile: 'general file',
      attachmentWithoutAny: 'No attachments',
      attachmentOne: '1 attachment',
      attachmentTwo: '2 attachments',
      attachmentMany: '{count} attachments',
      attachmentNoteMessage: 'Added {items}, and they will be sent with the request as soon as you submit it.',
      submitErrorFallback: 'Could not send the request. Check the data and try again.',
      serverConnectionError: 'Could not reach the server. Please try again.',
    },
  };
  const TOAST_ICONS = {
    info: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/></svg>',
    success: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg>',
    warning: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 9v4"/><path d="M12 17h.01"/><path d="M10.29 3.86 1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/></svg>',
    error: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="m15 9-6 6"/><path d="m9 9 6 6"/></svg>',
  };

  function init() {
    document.addEventListener('nawafeth:languagechange', _handleLanguageChange);
    _observeLanguageAttributes();
    _startLanguageSync();
    _resetSuccessOverlay();
    _syncLanguageUI(true);
    const isLoggedIn = _isLoggedIn();
    if (isLoggedIn && _ensureProviderAccess()) return;
    _setAuthState(isLoggedIn);
    if (!isLoggedIn) return;

    _loadCategories();
    _bindTextCounters();
    _bindLiveValidation();
    _syncDeadlineMin();
    _bindFilePickerTrigger();
    _bindToastControls();
    _renderAttachments();

    const catSel = document.getElementById('rq-category');
    if (catSel) catSel.addEventListener('change', _onCategoryChange);

    const subSel = document.getElementById('rq-subcategory');
    if (subSel) {
      subSel.addEventListener('change', () => {
        _clearFieldError('rq-subcategory');
        void _maybeResolveCompetitiveScope(false);
      });
    }

    const fileInput = document.getElementById('rq-files');
    if (fileInput) fileInput.addEventListener('change', _onFilesChanged);

    const form = document.getElementById('rq-form');
    if (form) form.addEventListener('submit', _onSubmit);

  }

  function _handleLanguageChange() {
    _syncLanguageUI(true);
    const isLoggedIn = _isLoggedIn();
    if (isLoggedIn && _ensureProviderAccess()) return;
    _setAuthState(isLoggedIn);
    if (!isLoggedIn) return;
    _renderAttachments();
    const overlay = document.getElementById('rq-submit-state');
    if (overlay && !overlay.classList.contains('hidden')) {
      const progressValue = Number(document.getElementById('rq-submit-state-progress')?.getAttribute('aria-valuenow') || 0);
      _setSubmitProgress(progressValue, _getAttachmentCount());
    }
  }

  function _observeLanguageAttributes() {
    if (_languageObserver || typeof MutationObserver !== 'function') return;
    const root = document.documentElement;
    if (!root) return;
    _languageObserver = new MutationObserver((mutations) => {
      if (!Array.isArray(mutations) || !mutations.length) return;
      _handleLanguageChange();
    });
    _languageObserver.observe(root, {
      attributes: true,
      attributeFilter: ['lang', 'dir'],
    });
  }

  function _startLanguageSync() {
    if (_languageSyncTimer) return;
    _languageSyncTimer = window.setInterval(() => {
      _syncLanguageUI(false);
    }, 250);
  }

  function _syncLanguageUI(force) {
    const lang = _currentLang();
    if (!force && _lastAppliedLang === lang) return;
    _lastAppliedLang = lang;
    _applyStaticCopy();
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

  function _isLoggedIn() {
    const serverAuth = window.NAWAFETH_SERVER_AUTH || null;
    return !!(
      (window.Auth && typeof Auth.isLoggedIn === 'function' && Auth.isLoggedIn())
      || (serverAuth && serverAuth.isAuthenticated)
    );
  }

  function _ensureProviderAccess() {
    if (!window.Auth || typeof window.Auth.ensureServiceRequestAccess !== 'function') return false;
    return !window.Auth.ensureServiceRequestAccess(_providerGateOptions());
  }

  function _providerGateOptions() {
    return {
      gateId: 'auth-gate',
      contentId: 'form-content',
      target: '/request-quote/',
      kicker: _copy('providerGateKicker'),
      title: _copy('providerGateTitle'),
      description: _copy('providerGateDescription'),
      note: _copy('providerGateNote'),
      switchLabel: _copy('providerGateSwitch'),
      profileLabel: _copy('providerGateProfile'),
    };
  }

  function _currentLang() {
    try {
      if (window.NawafethI18n && typeof window.NawafethI18n.getLanguage === 'function') {
        return window.NawafethI18n.getLanguage() === 'en' ? 'en' : 'ar';
      }
    } catch (_) {}
    try {
      return (localStorage.getItem('nw_lang') || 'ar').toLowerCase() === 'en' ? 'en' : 'ar';
    } catch (_) {
      return 'ar';
    }
  }

  function _copy(key, tokens = null) {
    const bundle = COPY[_currentLang()] || COPY.ar;
    const fallback = COPY.ar[key] || '';
    let value = Object.prototype.hasOwnProperty.call(bundle, key) ? bundle[key] : fallback;
    if (!tokens) return value;
    Object.entries(tokens).forEach(([token, replacement]) => {
      value = value.replace(new RegExp(`\\{${token}\\}`, 'g'), String(replacement));
    });
    return value;
  }

  function _setText(id, value) {
    const node = document.getElementById(id);
    if (node) node.textContent = value;
  }

  function _setAttr(id, name, value) {
    const node = document.getElementById(id);
    if (node) node.setAttribute(name, value);
  }

  function _setPlaceholder(id, value) {
    const node = document.getElementById(id);
    if (node) node.setAttribute('placeholder', value);
  }

  function _applyStaticCopy() {
    document.title = _copy('pageTitle');
    _setText('rq-provider-kicker', _copy('providerGateKicker'));
    _setText('rq-provider-title', _copy('providerGateTitle'));
    _setText('rq-provider-description', _copy('providerGateDescription'));
    _setText('rq-provider-switch', _copy('providerGateSwitch'));
    _setText('rq-provider-profile', _copy('providerGateProfile'));
    _setText('rq-provider-note', _copy('providerGateNote'));
    _setText('rq-login-title', _copy('loginGateTitle'));
    _setText('rq-login-description', _copy('loginGateDescription'));
    _setText('rq-login-button', _copy('loginGateButton'));
    _setText('rq-type-badge-text', _copy('heroBadge'));
    _setText('rq-hero-title', _copy('heroTitle'));
    _setAttr('rq-back-link', 'aria-label', _copy('backAria'));
    _setText('rq-header-title', _copy('headerTitle'));
    _setText('rq-page-badge-text', _copy('pageBadge'));
    _setText('rq-subtitle', _copy('subtitle'));
    _setText('rq-intro-chip', _copy('introChip'));
    _setText('rq-intro-text', _copy('introText'));
    _setText('rq-title-label', _copy('titleLabel'));
    _setPlaceholder('rq-title', _copy('titlePlaceholder'));
    _setText('rq-title-hint', _copy('titleHint'));
    _setText('rq-category-label', _copy('categoryLabel'));
    _setText('rq-subcategory-label', _copy('subcategoryLabel'));
    _setText('rq-deadline-label', _copy('deadlineLabel'));
    _setText('rq-details-label', _copy('detailsLabel'));
    _setPlaceholder('rq-details', _copy('detailsPlaceholder'));
    _setText('rq-files-label', _copy('filesLabel'));
    _setText('rq-file-trigger-text', _copy('fileTrigger'));
    _setText('rq-upload-hint', _copy('uploadHint'));
    _setText('rq-file-summary', _copy('attachmentEmpty'));
    _setText('rq-attachment-note-title', _copy('attachmentPreparedMany'));
    _setText('rq-attachment-note-text', _copy('submitUploadingNoAttachments'));
    _setText('rq-cancel-link', _copy('cancel'));
    const submitBtn = document.getElementById('rq-submit');
    if (submitBtn) {
      if (submitBtn.classList.contains('is-loading')) {
        submitBtn.innerHTML = `<span class="spinner-inline"></span><span>${_copy('submitLoading')}</span>`;
      } else {
        _resetBtn(submitBtn);
      }
    }
    _setText('rq-submit-state-title', _copy('submitStateTitle'));
    _setText('rq-submit-state-message', _copy('submitStateMessage'));
    _setAttr('rq-submit-state-progress', 'aria-label', _copy('submitStateProgressAria'));
    _setText('rq-success-title', _copy('successTitle'));
    _setText('rq-success-message', _copy('successMessage'));
    _setText('rq-success-orders-link', _copy('successOrders'));
    _setText('rq-success-home-link', _copy('successHome'));
    _setText('rq-toast-title', _copy('toastDefaultTitle'));
    _setText('rq-toast-message', _copy('toastDefaultMessage'));
    _setAttr('rq-toast-close', 'aria-label', _copy('toastCloseAria'));
    _refreshSelectPlaceholder('rq-category', _copy('categoryPlaceholder'));
    _refreshSelectPlaceholder('rq-subcategory', _copy('subcategoryPlaceholder'));
  }

  function _refreshSelectPlaceholder(id, label) {
    const select = document.getElementById(id);
    const placeholder = select?.querySelector('option[value=""]');
    if (placeholder) placeholder.textContent = label;
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
    _refreshSelectPlaceholder('rq-category', _copy('categoryPlaceholder'));
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
    subSel.innerHTML = `<option value="">${_copy('subcategoryPlaceholder')}</option>`;
    const opt = sel.options[sel.selectedIndex];
    if (!opt || !opt.dataset.subs) return;
    try {
      const subs = JSON.parse(opt.dataset.subs);
      subs.forEach(s => {
        const o = document.createElement('option');
        o.value = s.id;
        o.textContent = s.name;
        o.dataset.requiresGeoScope = s && s.requires_geo_scope ? '1' : '0';
        subSel.appendChild(o);
      });
    } catch (e) { /* ignore */ }
  }

  function _normalizeScopeText(value) {
    return String(value || '').trim();
  }

  function _requesterCity() {
    return _normalizeScopeText(quoteContext.requesterCity || '');
  }

  function _selectedSubcategoryRequiresGeoScope() {
    const option = document.getElementById('rq-subcategory')?.selectedOptions?.[0];
    if (!option || !option.value) return false;
    return option.dataset.requiresGeoScope !== '0';
  }

  function _firstNonEmpty(values) {
    for (const value of values) {
      const normalized = _normalizeScopeText(value);
      if (normalized) return normalized;
    }
    return '';
  }

  function _scopeAliasKey(value) {
    return _normalizeScopeText(value)
      .toLowerCase()
      .replace(/[إأآ]/g, 'ا')
      .replace(/ة/g, 'ه')
      .replace(/[^\u0600-\u06FFa-z0-9\s-]/gi, ' ')
      .replace(/\s+/g, ' ')
      .trim();
  }

  function _locationAlias(value) {
    const key = _scopeAliasKey(value);
    const aliases = {
      'الرياض': 'الرياض',
      'مكه': 'مكة',
      'جده': 'جدة',
      'الدمام': 'الدمام',
      'الخبر': 'الخبر',
      'المدينه المنوره': 'المدينة المنورة',
      'القصيم': 'القصيم',
      'تبوك': 'تبوك',
      'حائل': 'حائل',
      'حايل': 'حائل',
      'عسير': 'عسير',
      'ابها': 'أبها',
      'جازان': 'جازان',
      'جيزان': 'جازان',
      'نجران': 'نجران',
      'الباحه': 'الباحة',
      'الجوف': 'الجوف',
      'الحدود الشماليه': 'الحدود الشمالية',
      'عرعر': 'عرعر',
      'riyadh': 'الرياض',
      'riyadh city': 'الرياض',
      'riyadh region': 'الرياض',
      'riyadh province': 'الرياض',
      'riyadh governorate': 'الرياض',
      'makkah': 'مكة',
      'mecca': 'مكة',
      'makkah region': 'مكة',
      'mecca region': 'مكة',
      'jeddah': 'جدة',
      'jedda': 'جدة',
      'dammam': 'الدمام',
      'eastern province': 'الدمام',
      'ash sharqiyah': 'الدمام',
      'khobar': 'الخبر',
      'al khobar': 'الخبر',
      'madinah': 'المدينة المنورة',
      'medina': 'المدينة المنورة',
      'al madinah': 'المدينة المنورة',
      'qassim': 'القصيم',
      'al qassim': 'القصيم',
      'tabuk': 'تبوك',
      'hail': 'حائل',
      'ha il': 'حائل',
      'asir': 'عسير',
      'aseer': 'عسير',
      'abha': 'أبها',
      'jazan': 'جازان',
      'jizan': 'جازان',
      'najran': 'نجران',
      'al baha': 'الباحة',
      'baha': 'الباحة',
      'jawf': 'الجوف',
      'al jawf': 'الجوف',
      'northern borders': 'الحدود الشمالية',
      'arar': 'عرعر',
    };
    return aliases[key] || '';
  }

  function _cleanReverseGeocodeCity(value) {
    let text = _normalizeScopeText(value);
    if (!text) return '';

    const directAlias = _locationAlias(text);
    if (directAlias) return directAlias;

    text = text
      .replace(/^(إمارة|امارة)\s+منطقة\s+/u, '')
      .replace(/^(منطقة|محافظة|مدينة|بلدية|أمانة|امانة)\s+/u, '')
      .replace(/\s+(Province|Region|Governorate|Municipality|City)$/i, '')
      .replace(/\s+/g, ' ')
      .trim();

    return _locationAlias(text) || text;
  }

  function _extractCityFromReverseGeocode(data, address) {
    const candidates = [
      address.city,
      address.town,
      address.village,
      address.municipality,
      address.city_district,
      address.county,
      address.state_district,
      address.state,
      address.region,
      address.province,
    ];

    for (const candidate of candidates) {
      const city = _cleanReverseGeocodeCity(candidate);
      if (city) return city;
    }

    const displayParts = _normalizeScopeText(data?.display_name || '')
      .split(',')
      .map((part) => _cleanReverseGeocodeCity(part))
      .filter(Boolean);
    for (const part of displayParts) {
      const city = _locationAlias(part);
      if (city) return city;
    }
    return '';
  }

  function _distanceKm(lat1, lng1, lat2, lng2) {
    const toRad = (value) => (Number(value) * Math.PI) / 180;
    const earth = 6371;
    const dLat = toRad(lat2 - lat1);
    const dLng = toRad(lng2 - lng1);
    const a = Math.sin(dLat / 2) ** 2
      + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
    return 2 * earth * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  }

  function _nearestKnownSaudiCity(location) {
    const lat = Number(location?.lat);
    const lng = Number(location?.lng);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) return '';

    const knownCities = [
      ['الرياض', 24.7136, 46.6753],
      ['الخرج', 24.1554, 47.3346],
      ['جدة', 21.4858, 39.1925],
      ['مكة المكرمة', 21.3891, 39.8579],
      ['الطائف', 21.4373, 40.5127],
      ['المدينة المنورة', 24.5247, 39.5692],
      ['ينبع', 24.0895, 38.0618],
      ['الدمام', 26.4207, 50.0888],
      ['الخبر', 26.2172, 50.1971],
      ['الظهران', 26.2361, 50.0393],
      ['الجبيل', 27.0046, 49.6460],
      ['حفر الباطن', 28.4342, 45.9636],
      ['الأحساء', 25.3832, 49.5860],
      ['بريدة', 26.3592, 43.9818],
      ['عنيزة', 26.0880, 43.9930],
      ['حائل', 27.5114, 41.7208],
      ['تبوك', 28.3838, 36.5662],
      ['أبها', 18.2164, 42.5053],
      ['خميس مشيط', 18.3000, 42.7333],
      ['جازان', 16.8892, 42.5511],
      ['نجران', 17.5656, 44.2289],
      ['الباحة', 20.0129, 41.4677],
      ['عرعر', 30.9753, 41.0381],
      ['سكاكا', 29.9697, 40.2064],
      ['القريات', 31.3318, 37.3428],
    ];

    let nearest = null;
    knownCities.forEach(([city, cityLat, cityLng]) => {
      const distance = _distanceKm(lat, lng, cityLat, cityLng);
      if (!nearest || distance < nearest.distance) nearest = { city, distance };
    });

    return nearest && nearest.distance <= 260 ? nearest.city : '';
  }

  async function _resolveClientLocation(forcePrompt) {
    if (_clientLocation) return _clientLocation;
    if (!navigator.geolocation) return null;
    if (_locationPromise) return _locationPromise;

    if (forcePrompt === false) {
      try {
        const permission = await navigator.permissions?.query?.({ name: 'geolocation' });
        if (permission && permission.state === 'denied') return null;
      } catch (_) {}
    }

    _locationPromise = new Promise((resolve) => {
      navigator.geolocation.getCurrentPosition(
        (position) => {
          const lat = Number(position?.coords?.latitude);
          const lng = Number(position?.coords?.longitude);
          if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
            resolve(null);
            return;
          }
          _clientLocation = { lat, lng };
          resolve(_clientLocation);
        },
        () => resolve(null),
        { enableHighAccuracy: true, timeout: 9000, maximumAge: 120000 }
      );
    });

    try {
      return await _locationPromise;
    } finally {
      _locationPromise = null;
    }
  }

  async function _reverseGeocodeClientLocation(location) {
    if (!location) return null;
    if (_reverseLocationPromise) return _reverseLocationPromise;

    _reverseLocationPromise = (async () => {
      const params = new URLSearchParams({
        format: 'jsonv2',
        lat: String(location.lat),
        lon: String(location.lng),
        zoom: '11',
        addressdetails: '1',
        'accept-language': _currentLang() === 'ar' ? 'ar' : 'en',
      });
      let city = '';
      let address = {};
      try {
        const response = await fetch('https://nominatim.openstreetmap.org/reverse?' + params.toString(), {
          headers: {
            Accept: 'application/json',
          },
        });
        if (!response.ok) throw new Error('reverse_geocode_failed');

        const data = await response.json();
        address = data && typeof data === 'object' ? (data.address || {}) : {};
        city = _extractCityFromReverseGeocode(data, address);
      } catch (_) {
        city = '';
      }
      city = city || _nearestKnownSaudiCity(location);
      if (!city) throw new Error('city_not_found');

      _resolvedScopeLocation = {
        city,
        country: _firstNonEmpty([address.country, address.country_code]),
        source: 'geolocation',
      };
      return _resolvedScopeLocation;
    })();

    try {
      return await _reverseLocationPromise;
    } finally {
      _reverseLocationPromise = null;
    }
  }

  async function _resolveCompetitiveRequestScope(forcePrompt) {
    if (!_selectedSubcategoryRequiresGeoScope()) return { city: '' };

    const accountCity = _requesterCity();
    if (accountCity) {
      return {
        city: accountCity,
        country: _normalizeScopeText(quoteContext.requesterCountry || ''),
        source: 'account',
      };
    }

    if (_resolvedScopeLocation?.city) return _resolvedScopeLocation;

    const location = await _resolveClientLocation(forcePrompt);
    if (!location) return null;
    return _reverseGeocodeClientLocation(location);
  }

  async function _maybeResolveCompetitiveScope(forcePrompt) {
    if (!_selectedSubcategoryRequiresGeoScope() || _requesterCity()) return null;
    try {
      return await _resolveCompetitiveRequestScope(forcePrompt);
    } catch (_) {
      return null;
    }
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
      _showToast(_copy('warningAudioSingle'), 'warning');
      return;
    }
    if (!added) _showToast(_copy('warningNoNewAttachments'), 'warning');
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
          title: kind === 'video' ? _copy('removeVideo') : _copy('removeImage'),
          'aria-label': kind === 'video' ? _copy('removeVideo') : _copy('removeImage'),
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

    renderThumbSection(_copy('sectionImages'), _images, 'image');
    renderThumbSection(_copy('sectionVideos'), _videos, 'video');

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
          textContent: _copy('removeFile'),
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
        textContent: _copy('removeFile'),
      });
      removeBtn.addEventListener('click', () => {
        _audio = null;
        _renderAttachments();
      });

      item.appendChild(removeBtn);
      const section = UI.el('div', { className: 'attach-section' });
      section.appendChild(UI.el('strong', { className: 'attach-section-title', textContent: _copy('sectionAudio') }));
      section.appendChild(item);
      list.appendChild(section);
    }

    renderSection(_copy('sectionFiles'), _files, (idx) => { _files.splice(idx, 1); });

    if (!_images.length && !_videos.length && !_files.length && !_audio) {
      list.appendChild(UI.el('span', { className: 'attach-empty', textContent: _copy('attachmentEmpty') }));
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
      summary.textContent = _copy('attachmentEmpty');
      if (note) note.classList.add('hidden');
      return;
    }
    const parts = [_formatAttachmentPart(_copy('attachmentTypeFile'), total)];
    if (_images.length) parts.push(_formatAttachmentPart(_copy('attachmentTypeImage'), _images.length));
    if (_videos.length) parts.push(_formatAttachmentPart(_copy('attachmentTypeVideo'), _videos.length));
    if (_audio) parts.push(_copy('attachmentTypeAudio'));
    if (_files.length) parts.push(_formatAttachmentPart(_copy('attachmentTypeGeneralFile'), _files.length));
    summary.textContent = parts.join(' - ');
    if (note && noteTitle && noteText) {
      noteTitle.textContent = total === 1 ? _copy('attachmentPreparedOne') : _copy('attachmentPreparedMany');
      noteText.textContent = _copy('attachmentNoteMessage', { items: _joinList(parts) });
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
    if (!count) return _copy('attachmentWithoutAny');
    if (count === 1) return _copy('attachmentOne');
    if (count === 2) return _copy('attachmentTwo');
    return _copy('attachmentMany', { count });
  }

  function _formatAttachmentPart(label, count) {
    if (_currentLang() === 'en') {
      return `${count} ${label}${count === 1 ? '' : 's'}`;
    }
    return `${count} ${label}`;
  }

  function _joinList(parts) {
    if (!Array.isArray(parts) || !parts.length) return '';
    if (parts.length === 1) return parts[0];
    if (_currentLang() === 'en') return parts.join(', ');
    if (parts.length === 2) return `${parts[0]} و${parts[1]}`;
    return `${parts.slice(0, -1).join('، ')} و${parts[parts.length - 1]}`;
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
    ['rq-title', 'rq-category', 'rq-subcategory', 'rq-details', 'rq-deadline'].forEach(_clearFieldError);
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
      _setFieldError('rq-title', _copy('validationTitleRequired'));
      missing.push({ id: 'rq-title', message: _copy('validationTitleRequired') });
    }
    if (!category) {
      _setFieldError('rq-category', _copy('validationCategoryRequired'));
      missing.push({ id: 'rq-category', message: _copy('validationCategoryRequired') });
    }
    if (!subcategory) {
      _setFieldError('rq-subcategory', _copy('validationSubcategoryRequired'));
      missing.push({ id: 'rq-subcategory', message: _copy('validationSubcategoryRequired') });
    }
    if (!details) {
      _setFieldError('rq-details', _copy('validationDetailsRequired'));
      missing.push({ id: 'rq-details', message: _copy('validationDetailsRequired') });
    }
    if (details.length > 500) {
      _setFieldError('rq-details', _copy('validationDetailsTooLong'));
      missing.push({ id: 'rq-details', message: _copy('validationDetailsTooLong') });
    }
    if (title.length > 50) {
      _setFieldError('rq-title', _copy('validationTitleTooLong'));
      missing.push({ id: 'rq-title', message: _copy('validationTitleTooLong') });
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
    const toneKey = TOAST_ICONS[type] ? type : 'info';
    const tone = {
      title: _copy(`tone${toneKey.charAt(0).toUpperCase()}${toneKey.slice(1)}`),
      role: toneKey === 'info' || toneKey === 'success' ? 'status' : 'alert',
      live: toneKey === 'info' || toneKey === 'success' ? 'polite' : 'assertive',
      icon: TOAST_ICONS[toneKey],
    };
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
    const progressWrap = document.getElementById('rq-submit-state-progress');
    if (!overlay) return;

    if (!visible) {
      overlay.classList.add('hidden');
      overlay.classList.remove('visible');
      return;
    }

    const attachmentCount = Number(options.attachmentCount || 0);
    const progressValue = Math.max(0, Math.min(100, Math.round(Number(options.progress || 0))));
    if (title) title.textContent = options.title || _copy('submitStateTitle');
    if (message) {
      message.textContent = options.message || (attachmentCount
        ? _copy('submitUploadingWithAttachments', { count: _formatAttachmentCount(attachmentCount) })
        : _copy('submitUploadingNoAttachments'));
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
    let title = _copy('submitStateTitle');
    let message = attachmentCount
      ? _copy('submitUploadingWithAttachments', { count: _formatAttachmentCount(attachmentCount) })
      : _copy('submitSendingPlatform');

    if (attachmentCount && safeProgress <= 10) {
      title = _copy('submitPreparingAttachments');
      message = _copy('submitPreparingAttachmentsMessage', { count: _formatAttachmentCount(attachmentCount) });
    } else if (attachmentCount && safeProgress < 100) {
      title = _copy('submitUploadingAttachments');
      message = _copy('submitUploadingAttachmentsMessage', { percent: safeProgress });
    } else if (safeProgress >= 100) {
      title = _copy('submitApproving');
      message = _copy('submitApprovingMessage');
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

    let resolvedScope = null;
    if (_selectedSubcategoryRequiresGeoScope()) {
      try {
        resolvedScope = await _resolveCompetitiveRequestScope(true);
      } catch (_) {
        _showToast(_copy('detectLocationFailed'), 'error', { duration: 5200 });
        return;
      }
      if (!resolvedScope || !resolvedScope.city) {
        _showToast(_copy('enableLocationGeoScope'), 'warning', { duration: 5200 });
        return;
      }
    }

    const btn = document.getElementById('rq-submit');
    const attachmentCount = _getAttachmentCount();
    if (btn) {
      btn.disabled = true;
      btn.classList.add('is-loading');
      btn.innerHTML = `<span class="spinner-inline"></span><span>${_copy('submitLoading')}</span>`;
    }
    _setSubmitProgress(0, attachmentCount);

    const title = required.title;
    const details = required.details;
    const subcat = required.subcategory;
    const deadline = document.getElementById('rq-deadline')?.value;

    const fd = new FormData();
    fd.append('request_type', 'competitive');
    fd.append('title', title);
    if (details) fd.append('description', details);
    if (subcat) fd.append('subcategory', subcat);
    if (deadline) fd.append('quote_deadline', deadline);
    if (resolvedScope && resolvedScope.city) fd.append('city', resolvedScope.city);
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
        if (res.data && res.data.error_code === 'profile_completion_required') {
          _showToast(_extractApiError(res.data) || _copy('submitErrorFallback'), 'warning', { duration: 5200 });
          return;
        }
        if (res.data && res.data.error_code === 'profile_location_required') {
          _showToast(_copy('locationRequiredBody'), 'warning', { duration: 5500 });
          try { await _resolveCompetitiveRequestScope(true); } catch (_) {}
          return;
        }
        const apiFieldMessage = _applyApiFieldErrors(res.data);
        _showToast(apiFieldMessage || _extractApiError(res.data) || _copy('submitErrorFallback'), 'error', { duration: 5200 });
      }
    } catch (err) {
      _showToast(_copy('serverConnectionError'), 'error', { duration: 5200 });
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
    btn.innerHTML = `<svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M2.01 21L23 12 2.01 3 2 10l15 2-15 2z"/></svg><span>${_copy('submit')}</span>`;
  }

  function _dateIso(date) {
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
  }

  // Boot
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
  window.addEventListener('pageshow', _resetSuccessOverlay);
  return {
    refreshLanguage: _handleLanguageChange,
  };
})();
