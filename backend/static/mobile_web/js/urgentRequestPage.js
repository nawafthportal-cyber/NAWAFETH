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
    resolvedScopeLocation: null,
    reverseLocationPromise: null,
  };

  const dom = {};
  let languageObserver = null;
  const urgentContext = window.NAWAFETH_URGENT_REQUEST_CONTEXT || {};

  const COPY = {
    ar: {
      pageTitle: 'نوافــذ — الطلب العاجل',
      providerGateKicker: 'وضع الحساب الحالي',
      providerGateTitle: 'الطلب العاجل متاح في وضع العميل فقط',
      providerGateDescription: 'أنت تستخدم المنصة الآن بوضع مقدم الخدمة، لذلك تم إيقاف إنشاء الطلبات العاجلة من هذا الوضع.',
      providerGateNote: 'بدّل نوع الحساب إلى عميل الآن، ثم أكمل إرسال الطلب العاجل مباشرة.',
      providerGateSwitch: 'التبديل إلى عميل',
      providerGateProfile: 'الذهاب إلى نافذتي',
      loginTitle: 'سجّل دخولك لإنشاء طلب عاجل',
      loginDescription: 'لإرسال طلب عاجل للمزوّدين المطابقين فورًا.',
      loginButton: 'تسجيل الدخول',
      heroKicker: 'طلب عاجل',
      heroTitle: 'أرسل طلبك للمزوّد الأنسب خلال دقائق',
      formBadge: 'طلب عاجل',
      formTitle: 'نموذج الطلب',
      stepCategory: 'التصنيف',
      stepScope: 'نطاق الإرسال',
      stepDetails: 'التفاصيل',
      stepAttachments: 'المرفقات',
      categoryLabel: 'التصنيف الرئيسي',
      categoryPlaceholder: 'اختر التصنيف الرئيسي',
      categoryLoadError: 'تعذر تحميل التصنيفات حاليًا',
      subcategoryLabel: 'التصنيف الفرعي',
      subcategoryPlaceholder: 'اختر التصنيف الفرعي',
      dispatchAllTitle: 'إرسال للجميع',
      dispatchAllDescription: 'لجميع المختصين المطابقين لنفس التصنيف الرئيسي والفرعي.',
      dispatchNearestTitle: 'إرسال للأقرب',
      dispatchNearestDescription: 'تحديد موقعك تلقائيًا ثم اختيار مزوّد قريب من الخريطة.',
      regionLabel: 'المنطقة الإدارية',
      regionPlaceholder: 'اختر المنطقة الإدارية',
      cityLabel: 'المدينة',
      cityPlaceholder: 'اختر المدينة',
      cityEmptyPlaceholder: 'اختر المنطقة أولًا ثم المدينة',
      cityClear: 'إلغاء المدينة',
      openMap: 'فتح الخريطة',
      selectedProviderNone: 'لم يتم اختيار مزوّد بعد',
      selectedProviderPrompt: 'اختر مزوّدًا من الخريطة.',
      providerWithinCity: 'قريب من موقعك الحالي',
      providerOutOfCoverageNote: 'هذا المزوّد يقدّم الخدمة داخل نطاق مكاني محدد حتى {radius} كم تقريبًا، بينما موقعك الحالي يبعد {distance} كم. يمكنك إرسال الطلب، لكن قد يعتذر المزوّد لأنك خارج نطاقه المكاني.',
      providerOutOfCoverageShort: 'خارج النطاق المكاني للمزوّد: التغطية حتى {radius} كم، وموقعك الحالي يبعد {distance} كم.',
      providerOutOfCoverageToast: 'تم اختيار المزوّد، لكنك خارج نطاقه المكاني المحدد.',
      providerRating: 'التقييم {value}',
      providerCompleted: 'المكتملة {value}',
      providerDistance: 'المسافة {value} كم',
      providerCall: 'اتصال',
      providerWhatsapp: 'واتس',
      providerChange: 'تغيير',
      titleLabel: 'عنوان الطلب',
      titlePlaceholder: 'مثال: صيانة عاجلة لمكيف منزل',
      descriptionLabel: 'تفاصيل الطلب',
      descriptionPlaceholder: 'اكتب وصفًا مختصرًا وواضحًا...',
      pickGallery: 'صور / فيديو',
      pickCamera: 'كاميرا',
      pickAudio: 'تسجيل صوت',
      stopAudio: 'إيقاف التسجيل',
      pickPdf: 'PDF',
      recordingActive: 'جارٍ التسجيل...',
      attachmentSummaryEmpty: 'لا توجد مرفقات حتى الآن.',
      attachmentSummaryBare: 'لا توجد مرفقات مضافة.',
      attachmentsTitle: 'المرفقات',
      attachmentsImages: 'الصور',
      attachmentsVideos: 'الفيديو',
      attachmentsFiles: 'الملفات',
      attachmentsAudio: 'التسجيل الصوتي',
      attachmentFileFallback: 'ملف مرفق',
      attachmentSummaryPrefix: 'تمت إضافة: {items}',
      itemImage: 'صورة',
      itemVideo: 'فيديو',
      itemFile: 'ملف',
      itemAudio: 'تسجيل صوتي',
      cancel: 'إلغاء',
      submit: 'إرسال الطلب العاجل',
      submitPending: 'جارٍ إرسال الطلب...',
      mapTitle: 'المزوّدون الأقرب',
      closeAria: 'إغلاق',
      mapLoading: 'جارٍ تحميل موقعك ونتائج المزوّدين...',
      successTitle: 'تم إرسال طلبك بنجاح',
      successMessage: 'سيتم تحويلك إلى صفحة الطلبات.',
      successNearest: 'تم إنشاء الطلب العاجل وتوجيهه مباشرة إلى {provider}. سيتم تحويلك إلى صفحة الطلبات الآن.',
      successAll: 'تم إنشاء الطلب العاجل وإرساله إلى جميع المزوّدين المطابقين. سيتم تحويلك إلى صفحة الطلبات الآن.',
      toastDefaultTitle: 'تنبيه',
      toastDefaultMessage: 'ستظهر الرسائل المهمة هنا.',
      toneSuccess: 'تم بنجاح',
      toneWarning: 'تنبيه',
      toneError: 'تعذر التنفيذ',
      toneInfo: 'معلومة',
      noNewAttachments: 'لم تتم إضافة مرفقات جديدة',
      audioUnsupported: 'التسجيل الصوتي غير مدعوم في هذا المتصفح',
      audioSaved: 'تم حفظ التسجيل الصوتي',
      audioStarted: 'بدأ التسجيل الصوتي',
      audioPermissionError: 'تعذر الوصول إلى الميكروفون',
      dispatchSummaryNearest: 'سيتم تحديد موقعك تلقائيًا ثم فتح الخريطة لعرض أقرب المزوّدين المطابقين كي تختار واحدًا منهم.',
      dispatchSummaryAll: 'سيتم إرسال الطلب لجميع المختصين المطابقين لنفس التصنيف الرئيسي والفرعي.',
      dispatchSummaryAllGeo: 'سيتم تحديد موقعك تلقائيًا لحصر الطلب على المختصين المطابقين داخل نفس النطاق الجغرافي.',
      mapSubtitleWithCity: 'يتم ترتيب المزوّدين حسب القرب من موقعك الحالي.',
      mapSubtitleEmpty: 'فعّل الموقع لعرض أقرب المزوّدين المطابقين على الخريطة.',
      summaryCategorySet: 'التصنيف: {value}',
      summaryCategoryEmpty: 'التصنيف: غير محدد',
      summarySubcategorySet: 'التخصص الفرعي: {value}',
      summarySubcategoryEmpty: 'اختر التصنيف الفرعي لإكمال المطابقة.',
      summaryScopeNearest: 'النطاق: إرسال للأقرب',
      summaryScopeAll: 'النطاق: إرسال للجميع',
      summaryLocationSet: 'الموقع الحالي: {city}',
      summaryLocationNearestEmpty: 'سيتم استخدام موقعك الحالي عند فتح الخريطة.',
      summaryLocationAllEmpty: 'بدون تقييد مكاني إضافي.',
      summaryLocationAccountCity: 'مدينة الحساب: {city}',
      summaryLocationAllPending: 'سيتم تحديد المدينة تلقائيًا من موقعك الحالي عند الإرسال.',
      summaryAttachments: 'المرفقات: {count}',
      summaryProviderSet: 'المزوّد المختار: {provider}',
      summaryProviderNearestEmpty: 'لم يتم اختيار مزوّد مباشر بعد.',
      summaryProviderAllEmpty: 'سيتم التوجيه تلقائيًا إلى جميع المزوّدين المطابقين.',
      mapNearestOnly: 'هذه النافذة مخصصة لنمط الإرسال للأقرب',
      chooseCategoryFirstError: 'اختر التصنيف الرئيسي أولًا',
      chooseCategoryFirstToast: 'اختر التصنيف الرئيسي قبل فتح الخريطة',
      chooseSubcategoryFirstError: 'اختر التصنيف الفرعي أولًا',
      chooseSubcategoryFirstToast: 'اختر التصنيف الفرعي قبل فتح الخريطة',
      chooseCityFirstError: 'فعّل الموقع لعرض الأقرب',
      chooseCityFirstToast: 'فعّل الموقع أولًا ثم افتح الخريطة',
      enableLocationMap: 'فعّل خدمة الموقع لاستخدام اختيار الأقرب على الخريطة',
      providersFound: 'تم العثور على {count} مزوّد داخل النطاق.',
      providersEmpty: 'لا يوجد مزوّدون مطابقون لهذا التصنيف بالقرب من موقعك حاليًا.',
      providersLoadError: 'تعذر تحميل المزوّدين الآن.',
      providersMapLoadError: 'تعذر تحميل المزوّدين على الخريطة',
      currentLocationPopup: 'موقعك الحالي',
      providerCountCompleted: '{count} مكتملة',
      popupProfile: 'الملف',
      popupCall: 'اتصال',
      popupWhatsapp: 'واتس',
      popupSend: 'إرسال الطلب',
      noProvidersSelectedCity: 'لا يوجد مزوّدون مطابقون بالقرب من موقعك الحالي.',
      providerCardAlt: 'صورة المزوّد',
      providerSelected: 'تم اختيار المزوّد ويمكنك الآن إرسال الطلب مباشرة له',
      validateCategory: 'اختر التصنيف الرئيسي',
      validateSubcategory: 'اختر التصنيف الفرعي',
      validateTitle: 'أدخل عنوان الطلب',
      validateDescription: 'أدخل تفاصيل الطلب',
      validateCityNearest: 'فعّل الموقع لاستخدام الإرسال للأقرب',
      validateProviderNearest: 'اختر مزوّدًا من الخريطة قبل الإرسال',
      enableLocationSubmit: 'فعّل خدمة الموقع لإرسال الطلب للأقرب',
      enableLocationAll: 'فعّل خدمة الموقع لتحديد مدينة الطلب تلقائيًا قبل الإرسال للجميع',
      detectLocationFailed: 'تعذر تحديد مدينة واضحة من موقعك الحالي. حاول مرة أخرى.',
      submitError: 'تعذر إرسال الطلب حاليًا',
      locationRequiredTitle: 'حدد موقعك لمتابعة الطلب',
      locationRequiredBody: 'هذه الخدمة تتطلب تحديد موقعك على الخريطة لإرسال الطلب لمزودي مدينتك.',
      connectionError: 'تعذر الاتصال بالخادم، حاول مرة أخرى',
    },
    en: {
      pageTitle: 'Nawafeth — Urgent Request',
      providerGateKicker: 'Current account mode',
      providerGateTitle: 'Urgent requests are only available in client mode',
      providerGateDescription: 'You are using the platform in provider mode right now, so creating urgent requests is disabled from this mode.',
      providerGateNote: 'Switch to client mode now, then continue sending the urgent request right away.',
      providerGateSwitch: 'Switch to client',
      providerGateProfile: 'Go to My Profile',
      loginTitle: 'Sign in to create an urgent request',
      loginDescription: 'To send an urgent request to matching providers right away.',
      loginButton: 'Sign in',
      heroKicker: 'Urgent request',
      heroTitle: 'Send your request to the right provider within minutes',
      formBadge: 'Urgent request',
      formTitle: 'Request form',
      stepCategory: 'Category',
      stepScope: 'Dispatch scope',
      stepDetails: 'Details',
      stepAttachments: 'Attachments',
      categoryLabel: 'Main category',
      categoryPlaceholder: 'Choose the main category',
      categoryLoadError: 'Could not load categories right now',
      subcategoryLabel: 'Subcategory',
      subcategoryPlaceholder: 'Choose the subcategory',
      dispatchAllTitle: 'Send to all',
      dispatchAllDescription: 'To all specialists matching the same main and subcategory.',
      dispatchNearestTitle: 'Send to nearest',
      dispatchNearestDescription: 'Detect your location automatically, then pick one nearby provider from the map.',
      regionLabel: 'Administrative region',
      regionPlaceholder: 'Choose an administrative region',
      cityLabel: 'City',
      cityPlaceholder: 'Choose a city',
      cityEmptyPlaceholder: 'Choose the region first, then the city',
      cityClear: 'Clear city',
      openMap: 'Open map',
      selectedProviderNone: 'No provider selected yet',
      selectedProviderPrompt: 'Choose a provider from the map.',
      providerWithinCity: 'Near your current location',
      providerOutOfCoverageNote: 'This provider serves within an approximate {radius} km coverage area, while your current location is {distance} km away. You can still send the request, but the provider may decline because you are outside the defined service area.',
      providerOutOfCoverageShort: 'Outside the provider service area: coverage up to {radius} km and your location is {distance} km away.',
      providerOutOfCoverageToast: 'The provider was selected, but your location is outside the provider service area.',
      providerRating: 'Rating {value}',
      providerCompleted: 'Completed {value}',
      providerDistance: 'Distance {value} km',
      providerCall: 'Call',
      providerWhatsapp: 'WhatsApp',
      providerChange: 'Change',
      titleLabel: 'Request title',
      titlePlaceholder: 'Example: Urgent home AC repair',
      descriptionLabel: 'Request details',
      descriptionPlaceholder: 'Write a short, clear description...',
      pickGallery: 'Images / Video',
      pickCamera: 'Camera',
      pickAudio: 'Voice note',
      stopAudio: 'Stop recording',
      pickPdf: 'PDF',
      recordingActive: 'Recording in progress...',
      attachmentSummaryEmpty: 'No attachments yet.',
      attachmentSummaryBare: 'No attachments added.',
      attachmentsTitle: 'Attachments',
      attachmentsImages: 'Images',
      attachmentsVideos: 'Videos',
      attachmentsFiles: 'Files',
      attachmentsAudio: 'Voice note',
      attachmentFileFallback: 'Attached file',
      attachmentSummaryPrefix: 'Added: {items}',
      itemImage: 'image',
      itemVideo: 'video',
      itemFile: 'file',
      itemAudio: 'voice note',
      cancel: 'Cancel',
      submit: 'Send urgent request',
      submitPending: 'Sending request...',
      mapTitle: 'Nearest providers',
      closeAria: 'Close',
      mapLoading: 'Loading your location and nearby providers...',
      successTitle: 'Your request was sent successfully',
      successMessage: 'You will be redirected to the orders page.',
      successNearest: 'The urgent request was created and sent directly to {provider}. You will be redirected to the orders page now.',
      successAll: 'The urgent request was created and sent to all matching providers. You will be redirected to the orders page now.',
      toastDefaultTitle: 'Notice',
      toastDefaultMessage: 'Important messages will appear here.',
      toneSuccess: 'Done successfully',
      toneWarning: 'Notice',
      toneError: 'Action failed',
      toneInfo: 'Information',
      noNewAttachments: 'No new attachments were added',
      audioUnsupported: 'Voice recording is not supported in this browser',
      audioSaved: 'Voice recording saved',
      audioStarted: 'Voice recording started',
      audioPermissionError: 'Could not access the microphone',
      dispatchSummaryNearest: 'Your current location will be detected automatically, then the map will open so you can choose one nearby matching provider.',
      dispatchSummaryAll: 'The request will be sent to all specialists matching the same main and subcategory.',
      dispatchSummaryAllGeo: 'Your location will be detected automatically so the request stays within the matching geographic scope.',
      mapSubtitleWithCity: 'Providers are ordered by distance from your current location.',
      mapSubtitleEmpty: 'Enable location to view the nearest matching providers on the map.',
      summaryCategorySet: 'Category: {value}',
      summaryCategoryEmpty: 'Category: not selected',
      summarySubcategorySet: 'Subcategory: {value}',
      summarySubcategoryEmpty: 'Choose the subcategory to complete the match.',
      summaryScopeNearest: 'Scope: send to nearest',
      summaryScopeAll: 'Scope: send to all',
      summaryLocationSet: 'Current location: {city}',
      summaryLocationNearestEmpty: 'Your current location will be used when the map opens.',
      summaryLocationAllEmpty: 'No extra location restriction.',
      summaryLocationAccountCity: 'Account city: {city}',
      summaryLocationAllPending: 'Your city will be detected automatically from your current location when you submit.',
      summaryAttachments: 'Attachments: {count}',
      summaryProviderSet: 'Selected provider: {provider}',
      summaryProviderNearestEmpty: 'No direct provider selected yet.',
      summaryProviderAllEmpty: 'The request will be routed automatically to all matching providers.',
      mapNearestOnly: 'This window is only for the send-to-nearest mode',
      chooseCategoryFirstError: 'Choose the main category first',
      chooseCategoryFirstToast: 'Choose the main category before opening the map',
      chooseSubcategoryFirstError: 'Choose the subcategory first',
      chooseSubcategoryFirstToast: 'Choose the subcategory before opening the map',
      chooseCityFirstError: 'Enable location to view the nearest providers',
      chooseCityFirstToast: 'Enable location first, then open the map',
      enableLocationMap: 'Enable location services to use nearest-provider selection on the map',
      providersFound: 'Found {count} providers within range.',
      providersEmpty: 'No providers currently match this category near your location.',
      providersLoadError: 'Could not load providers right now.',
      providersMapLoadError: 'Could not load providers on the map',
      currentLocationPopup: 'Your current location',
      providerCountCompleted: '{count} completed',
      popupProfile: 'Profile',
      popupCall: 'Call',
      popupWhatsapp: 'WhatsApp',
      popupSend: 'Send request',
      noProvidersSelectedCity: 'No providers currently match near your location.',
      providerCardAlt: 'Provider image',
      providerSelected: 'The provider was selected and you can now send the request directly',
      validateCategory: 'Choose the main category',
      validateSubcategory: 'Choose the subcategory',
      validateTitle: 'Enter the request title',
      validateDescription: 'Enter the request details',
      validateCityNearest: 'Enable location to use send-to-nearest',
      validateProviderNearest: 'Choose a provider from the map before sending',
      enableLocationSubmit: 'Enable location services to send the request to the nearest provider',
      enableLocationAll: 'Enable location services so the request city can be detected automatically before sending to all',
      detectLocationFailed: 'Could not detect a clear city from your current location. Please try again.',
      submitError: 'Could not send the request right now',
      locationRequiredTitle: 'Set your location to continue',
      locationRequiredBody: 'This service requires you to pin your location on the map so the request can reach providers in your city.',
      connectionError: 'Could not connect to the server. Please try again.',
    },
  };

  function currentLang() {
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

  function copy(key, tokens) {
    const bundle = COPY[currentLang()] || COPY.ar;
    let value = Object.prototype.hasOwnProperty.call(bundle, key) ? bundle[key] : (COPY.ar[key] || '');
    if (!tokens) return value;
    Object.entries(tokens).forEach(([token, replacement]) => {
      value = value.replace(new RegExp(`\\{${token}\\}`, 'g'), String(replacement));
    });
    return value;
  }

  function setText(id, value) {
    const node = document.getElementById(id);
    if (node) node.textContent = value;
  }

  function setAttr(id, name, value) {
    const node = document.getElementById(id);
    if (node) node.setAttribute(name, value);
  }

  function setPlaceholder(id, value) {
    const node = document.getElementById(id);
    if (node) node.setAttribute('placeholder', value);
  }

  function observeLanguageChanges() {
    if (languageObserver || typeof MutationObserver !== 'function' || !document.documentElement) return;
    languageObserver = new MutationObserver(() => refreshLanguage());
    languageObserver.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ['lang', 'dir'],
    });
  }

  function refreshLanguage() {
    applyStaticCopy();
    updateDispatchUI();
    updateRecordingUI();
    renderAttachments();
    hydrateSelectedProvider();
    renderProviderCards();
    if (state.map && state.clientLocation) renderMapProviders(state.clientLocation);
  }

  function applyStaticCopy() {
    document.title = copy('pageTitle');
    setText('ur-provider-kicker', copy('providerGateKicker'));
    setText('ur-provider-title', copy('providerGateTitle'));
    setText('ur-provider-description', copy('providerGateDescription'));
    setText('ur-provider-switch', copy('providerGateSwitch'));
    setText('ur-provider-profile', copy('providerGateProfile'));
    setText('ur-provider-note', copy('providerGateNote'));
    setText('ur-login-title', copy('loginTitle'));
    setText('ur-login-description', copy('loginDescription'));
    setText('ur-login-button', copy('loginButton'));
    setText('ur-hero-kicker-text', copy('heroKicker'));
    setText('ur-hero-title', copy('heroTitle'));
    setText('ur-form-badge-text', copy('formBadge'));
    setText('ur-form-title', copy('formTitle'));
    setText('ur-step-category-title', copy('stepCategory'));
    setText('ur-step-scope-title', copy('stepScope'));
    setText('ur-step-details-title', copy('stepDetails'));
    setText('ur-step-attachments-title', copy('stepAttachments'));
    setText('ur-category-label', copy('categoryLabel'));
    setText('ur-subcategory-label', copy('subcategoryLabel'));
    setText('ur-dispatch-all-title', copy('dispatchAllTitle'));
    setText('ur-dispatch-all-description', copy('dispatchAllDescription'));
    setText('ur-dispatch-nearest-title', copy('dispatchNearestTitle'));
    setText('ur-dispatch-nearest-description', copy('dispatchNearestDescription'));
    setText('ur-open-map', copy('openMap'));
    setText('ur-provider-change', copy('providerChange'));
    setText('ur-provider-call', copy('providerCall'));
    setText('ur-provider-whatsapp', copy('providerWhatsapp'));
    setText('ur-title-label', copy('titleLabel'));
    setPlaceholder('ur-title', copy('titlePlaceholder'));
    setText('ur-description-label', copy('descriptionLabel'));
    setPlaceholder('ur-description', copy('descriptionPlaceholder'));
    setText('ur-pick-gallery-text', copy('pickGallery'));
    setText('ur-pick-camera-text', copy('pickCamera'));
    setText('ur-record-audio-text', state.isRecording ? copy('stopAudio') : copy('pickAudio'));
    setText('ur-pick-pdf-text', copy('pickPdf'));
    setText('ur-cancel-link', copy('cancel'));
    setText('ur-submit-text', state.isSubmitting ? copy('submitPending') : copy('submit'));
    setText('ur-map-title', copy('mapTitle'));
    setText('ur-success-title', copy('successTitle'));
    if (!dom['ur-success']?.classList.contains('visible')) {
      setText('ur-success-message', copy('successMessage'));
    }
    setText('ur-toast-title', copy('toastDefaultTitle'));
    setText('ur-toast-message', copy('toastDefaultMessage'));
    setAttr('ur-map-backdrop', 'aria-label', copy('closeAria'));
    setAttr('ur-map-close', 'aria-label', copy('closeAria'));
    setAttr('ur-toast-close', 'aria-label', copy('closeAria'));
    refreshCategoryPlaceholder();
    refreshRegionCityPlaceholders();
  }

  function refreshCategoryPlaceholder() {
    const categoryPlaceholder = dom['ur-category']?.querySelector('option[value=""]');
    if (categoryPlaceholder) categoryPlaceholder.textContent = copy('categoryPlaceholder');
    const subcategoryPlaceholder = dom['ur-subcategory']?.querySelector('option[value=""]');
    if (subcategoryPlaceholder) subcategoryPlaceholder.textContent = copy('subcategoryPlaceholder');
  }

  function refreshRegionCityPlaceholders() {
    return;
  }

  function init() {
    document.addEventListener('nawafeth:languagechange', refreshLanguage);
    observeLanguageChanges();
    cacheDom();
    bindStaticEvents();
    resetSuccessOverlay();
    applyStaticCopy();
    const serverAuth = window.NAWAFETH_SERVER_AUTH || null;
    const isLoggedIn = !!(
      (window.Auth && typeof Auth.isLoggedIn === 'function' && Auth.isLoggedIn())
      || (serverAuth && serverAuth.isAuthenticated)
    );
    if (isLoggedIn && window.Auth && typeof window.Auth.ensureServiceRequestAccess === 'function' && !window.Auth.ensureServiceRequestAccess({
      gateId: 'auth-gate',
      contentId: 'form-content',
      target: '/urgent-request/',
      kicker: copy('providerGateKicker'),
      title: copy('providerGateTitle'),
      description: copy('providerGateDescription'),
      note: copy('providerGateNote'),
      switchLabel: copy('providerGateSwitch'),
      profileLabel: copy('providerGateProfile'),
    })) return;
    setAuthState(isLoggedIn);
    if (dom['form-content']?.classList.contains('hidden')) return;
    void bootstrap();
  }

  async function bootstrap() {
    await loadCategories();
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
      if (getDispatchMode() === 'nearest' && dom['ur-category']?.value && dom['ur-subcategory']?.value) {
        void openMapModal();
      } else if (getDispatchMode() === 'all' && selectedSubcategoryRequiresGeoScope() && !requesterCity()) {
        void resolveAllDispatchScope(false);
      }
    });

    document.querySelectorAll('input[name="dispatch_mode"]').forEach((input) => {
      input.addEventListener('change', () => {
        if (input.checked && input.value === 'nearest') {
          void resolveClientLocation(false);
          if (dom['ur-category']?.value && dom['ur-subcategory']?.value) {
            void openMapModal();
          }
        }
        if (input.checked && input.value === 'all') {
          clearSelectedProvider();
          if (selectedSubcategoryRequiresGeoScope() && !requesterCity()) {
            void resolveAllDispatchScope(false);
          }
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
      select.innerHTML = '<option value="">' + escapeHtml(copy('categoryPlaceholder')) + '</option>';
      state.categories.forEach((category) => {
        const option = document.createElement('option');
        option.value = String(category.id);
        option.textContent = category.name || ('#' + category.id);
        option.dataset.subs = JSON.stringify(Array.isArray(category.subcategories) ? category.subcategories : []);
        select.appendChild(option);
      });
    } catch (_) {
      showToast(copy('categoryLoadError'), 'error');
    }
  }

  function onCategoryChange() {
    const categorySelect = dom['ur-category'];
    const subSelect = dom['ur-subcategory'];
    if (!categorySelect || !subSelect) return;
    clearFieldError('ur-category');
    clearFieldError('ur-subcategory');
    subSelect.innerHTML = '<option value="">' + escapeHtml(copy('subcategoryPlaceholder')) + '</option>';
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
        subOption.textContent = sub.name || ('#' + sub.id);
        subOption.dataset.requiresGeoScope = sub && sub.requires_geo_scope ? '1' : '0';
        subSelect.appendChild(subOption);
      });
    } catch (_) {}
    clearSelectedProvider();
    updateSummary();
  }

  function getDispatchMode() {
    return document.querySelector('input[name="dispatch_mode"]:checked')?.value || 'all';
  }

  function updateDispatchUI() {
    const dispatch = getDispatchMode();
    const isNearest = dispatch === 'nearest';
    const needsGeoScope = dispatch === 'all' && selectedSubcategoryRequiresGeoScope();

    dom['ur-open-map']?.classList.toggle('hidden', !isNearest);

    if (dom['ur-dispatch-summary']) {
      dom['ur-dispatch-summary'].textContent = isNearest
        ? copy('dispatchSummaryNearest')
        : copy(needsGeoScope ? 'dispatchSummaryAllGeo' : 'dispatchSummaryAll');
    }

    if (dom['ur-map-subtitle']) {
      dom['ur-map-subtitle'].textContent = state.clientLocation
        ? copy('mapSubtitleWithCity', { city: '' })
        : copy('mapSubtitleEmpty');
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
    if (!added) showToast(copy('noNewAttachments'), 'warning');
  }

  async function toggleAudioRecording() {
    if (state.isRecording) {
      stopAudioRecording();
      return;
    }
    if (!navigator.mediaDevices?.getUserMedia || typeof MediaRecorder === 'undefined') {
      showToast(copy('audioUnsupported'), 'error');
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
        showToast(copy('audioSaved'), 'success');
      });
      state.mediaRecorder.start();
      state.isRecording = true;
      updateRecordingUI();
      showToast(copy('audioStarted'), 'info');
    } catch (_) {
      showToast(copy('audioPermissionError'), 'error');
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
    setText('ur-recording', copy('recordingActive'));
    setText('ur-record-audio-text', state.isRecording ? copy('stopAudio') : copy('pickAudio'));
  }

  function attachmentCount() {
    return state.images.length + state.videos.length + state.files.length + (state.audio ? 1 : 0);
  }

  function renderAttachments() {
    const root = dom['ur-attachment-list'];
    if (!root) return;
    root.innerHTML = '';

    renderThumbGroup(root, copy('attachmentsImages'), state.images, 'image', (index) => {
      state.images.splice(index, 1);
      renderAttachments();
    });
    renderThumbGroup(root, copy('attachmentsVideos'), state.videos, 'video', (index) => {
      state.videos.splice(index, 1);
      renderAttachments();
    });
    renderFileGroup(root, copy('attachmentsFiles'), state.files, (index) => {
      state.files.splice(index, 1);
      renderAttachments();
    });
    if (state.audio) {
      renderFileGroup(root, copy('attachmentsAudio'), [state.audio], () => {
        state.audio = null;
        renderAttachments();
      });
    }

    if (!attachmentCount()) {
      const empty = document.createElement('div');
      empty.className = 'ur-attachment-group';
      empty.innerHTML = '<h4>' + escapeHtml(copy('attachmentsTitle')) + '</h4><div class="ur-attachment-file"><span>' + escapeHtml(copy('attachmentSummaryBare')) + '</span></div>';
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
      removeButton.setAttribute('aria-label', copy('closeAria'));
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
      name.textContent = file.name || copy('attachmentFileFallback');
      const removeButton = document.createElement('button');
      removeButton.type = 'button';
      removeButton.className = 'ur-remove-btn';
      removeButton.textContent = '×';
      removeButton.setAttribute('aria-label', copy('closeAria'));
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
    if (state.images.length) parts.push(formatAttachmentItem(state.images.length, 'itemImage'));
    if (state.videos.length) parts.push(formatAttachmentItem(state.videos.length, 'itemVideo'));
    if (state.files.length) parts.push(formatAttachmentItem(state.files.length, 'itemFile'));
    if (state.audio) parts.push(copy('itemAudio'));
    summary.textContent = parts.length
      ? copy('attachmentSummaryPrefix', { items: parts.join(' • ') })
      : copy('attachmentSummaryEmpty');
  }

  function formatAttachmentItem(count, key) {
    return String(count) + ' ' + copy(key);
  }

  function updateSummary() {
    const categoryName = dom['ur-category']?.selectedOptions?.[0]?.textContent?.trim() || '';
    const subcategoryName = dom['ur-subcategory']?.selectedOptions?.[0]?.textContent?.trim() || '';
    const dispatch = getDispatchMode();
    const provider = state.selectedProvider;
    const locationLabel = state.clientLocation
      ? `${state.clientLocation.lat.toFixed(4)}, ${state.clientLocation.lng.toFixed(4)}`
      : '';
    const geoScopedAll = dispatch === 'all' && selectedSubcategoryRequiresGeoScope();
    const accountCity = requesterCity();
    const resolvedCity = state.resolvedScopeLocation?.city || '';

    if (dom['ur-summary-service']) {
      dom['ur-summary-service'].textContent = categoryName ? copy('summaryCategorySet', { value: categoryName }) : copy('summaryCategoryEmpty');
    }
    if (dom['ur-summary-service-sub']) {
      dom['ur-summary-service-sub'].textContent = subcategoryName
        ? copy('summarySubcategorySet', { value: subcategoryName })
        : copy('summarySubcategoryEmpty');
    }
    if (dom['ur-summary-scope']) {
      dom['ur-summary-scope'].textContent = dispatch === 'nearest' ? copy('summaryScopeNearest') : copy('summaryScopeAll');
    }
    if (dom['ur-summary-location']) {
      dom['ur-summary-location'].textContent = dispatch === 'nearest'
        ? (locationLabel ? copy('summaryLocationSet', { city: locationLabel }) : copy('summaryLocationNearestEmpty'))
        : geoScopedAll
          ? (resolvedCity
            ? copy('summaryLocationSet', { city: resolvedCity })
            : (accountCity
              ? copy('summaryLocationAccountCity', { city: accountCity })
              : copy('summaryLocationAllPending')))
          : copy('summaryLocationAllEmpty');
    }
    if (dom['ur-summary-attachments']) {
      dom['ur-summary-attachments'].textContent = copy('summaryAttachments', { count: attachmentCount() });
    }
    if (dom['ur-summary-provider']) {
      dom['ur-summary-provider'].textContent = provider
        ? copy('summaryProviderSet', { provider: provider.display_name })
        : (dispatch === 'nearest' ? copy('summaryProviderNearestEmpty') : copy('summaryProviderAllEmpty'));
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

  function normalizeScopeText(value) {
    return String(value || '').trim();
  }

  function requesterCity() {
    return normalizeScopeText(urgentContext.requesterCity || '');
  }

  function selectedSubcategoryRequiresGeoScope() {
    const option = dom['ur-subcategory']?.selectedOptions?.[0];
    if (!option || !option.value) return false;
    return option.dataset.requiresGeoScope !== '0';
  }

  function firstNonEmpty(values) {
    for (const value of values) {
      const normalized = normalizeScopeText(value);
      if (normalized) return normalized;
    }
    return '';
  }

  function scopeAliasKey(value) {
    return normalizeScopeText(value)
      .toLowerCase()
      .replace(/[إأآ]/g, 'ا')
      .replace(/ة/g, 'ه')
      .replace(/[^\u0600-\u06FFa-z0-9\s-]/gi, ' ')
      .replace(/\s+/g, ' ')
      .trim();
  }

  function locationAlias(value) {
    const key = scopeAliasKey(value);
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

  function cleanReverseGeocodeCity(value) {
    let text = normalizeScopeText(value);
    if (!text) return '';

    const directAlias = locationAlias(text);
    if (directAlias) return directAlias;

    text = text
      .replace(/^(إمارة|امارة)\s+منطقة\s+/u, '')
      .replace(/^(منطقة|محافظة|مدينة|بلدية|أمانة|امانة)\s+/u, '')
      .replace(/\s+(Province|Region|Governorate|Municipality|City)$/i, '')
      .replace(/\s+/g, ' ')
      .trim();

    return locationAlias(text) || text;
  }

  function extractCityFromReverseGeocode(data, address) {
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
      const city = cleanReverseGeocodeCity(candidate);
      if (city) return city;
    }

    const displayParts = normalizeScopeText(data?.display_name || '')
      .split(',')
      .map((part) => cleanReverseGeocodeCity(part))
      .filter(Boolean);
    for (const part of displayParts) {
      const city = locationAlias(part);
      if (city) return city;
    }
    return '';
  }

  function nearestKnownSaudiCity(location) {
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
      const distance = haversineDistanceKm(lat, lng, cityLat, cityLng);
      if (!nearest || distance < nearest.distance) nearest = { city, distance };
    });

    return nearest && nearest.distance <= 260 ? nearest.city : '';
  }

  async function resolveAllDispatchScope(forcePrompt) {
    if (!selectedSubcategoryRequiresGeoScope()) return { city: '' };

    const accountCity = requesterCity();
    if (accountCity) {
      return {
        city: accountCity,
        country: normalizeScopeText(urgentContext.requesterCountry || ''),
        source: 'account',
      };
    }

    if (state.resolvedScopeLocation?.city) return state.resolvedScopeLocation;

    const location = await resolveClientLocation(forcePrompt);
    if (!location) return null;
    return reverseGeocodeClientLocation(location);
  }

  async function reverseGeocodeClientLocation(location) {
    if (!location) return null;
    if (state.reverseLocationPromise) return state.reverseLocationPromise;

    state.reverseLocationPromise = (async () => {
      const params = new URLSearchParams({
        format: 'jsonv2',
        lat: String(location.lat),
        lon: String(location.lng),
        zoom: '11',
        addressdetails: '1',
        'accept-language': currentLang() === 'ar' ? 'ar' : 'en',
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
        city = extractCityFromReverseGeocode(data, address);
      } catch (_) {
        city = '';
      }
      city = city || nearestKnownSaudiCity(location);
      if (!city) throw new Error('city_not_found');

      state.resolvedScopeLocation = {
        city,
        country: firstNonEmpty([address.country, address.country_code]),
        source: 'geolocation',
      };
      updateSummary();
      return state.resolvedScopeLocation;
    })();

    try {
      return await state.reverseLocationPromise;
    } finally {
      state.reverseLocationPromise = null;
    }
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
          updateDispatchUI();
          updateSummary();
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
      showToast(copy('mapNearestOnly'), 'warning');
      return;
    }
    if (!dom['ur-category']?.value) {
      setFieldError('ur-category', copy('chooseCategoryFirstError'));
      focusField('ur-category');
      showToast(copy('chooseCategoryFirstToast'), 'warning');
      return;
    }
    if (!dom['ur-subcategory']?.value) {
      setFieldError('ur-subcategory', copy('chooseSubcategoryFirstError'));
      focusField('ur-subcategory');
      showToast(copy('chooseSubcategoryFirstToast'), 'warning');
      return;
    }
    dom['ur-map-modal']?.classList.add('open');
    dom['ur-map-modal']?.setAttribute('aria-hidden', 'false');
    if (dom['ur-map-status']) dom['ur-map-status'].textContent = copy('mapLoading');
    ensureMap();

    const location = await resolveClientLocation(true);
    if (!location) {
      closeMapModal();
      showToast(copy('enableLocationMap'), 'error');
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
          ? copy('providersFound', { count: state.nearbyProviders.length })
          : copy('providersEmpty');
      }
    } catch (_) {
      state.nearbyProviders = [];
      if (dom['ur-map-status']) dom['ur-map-status'].textContent = copy('providersLoadError');
      showToast(copy('providersMapLoadError'), 'error');
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
      display_name: provider.display_name || provider.username || ('Provider #' + provider.id),
      profile_href: '/provider/' + encodeURIComponent(String(provider.id || '')) + '/',
      _distance: distance,
    };
  }

  function selectedSubcategoryId() {
    const rawValue = Number(dom['ur-subcategory']?.value || 0);
    return Number.isFinite(rawValue) && rawValue > 0 ? rawValue : null;
  }

  function providerRequiresGeoScope(provider) {
    const subcategoryId = selectedSubcategoryId();
    const rows = Array.isArray(provider?.selected_subcategories) ? provider.selected_subcategories : [];
    const matched = rows.find((row) => Number(row?.id) === subcategoryId);
    return matched ? !!matched.requires_geo_scope : true;
  }

  function formatKm(value) {
    const number = Number(value);
    if (!Number.isFinite(number)) return '—';
    return Number.isInteger(number) ? String(number) : number.toFixed(1);
  }

  function isProviderOutsideCoverage(provider) {
    const radius = Number(provider?.coverage_radius_km);
    const distance = Number(provider?._distance);
    if (!providerRequiresGeoScope(provider)) return false;
    if (!Number.isFinite(radius) || radius <= 0) return false;
    if (!Number.isFinite(distance)) return false;
    return distance > (radius + 0.05);
  }

  function coverageWarningMessage(provider, short = false) {
    if (!isProviderOutsideCoverage(provider)) return '';
    return copy(short ? 'providerOutOfCoverageShort' : 'providerOutOfCoverageNote', {
      radius: formatKm(provider.coverage_radius_km),
      distance: formatKm(provider._distance),
    });
  }

  function renderMapProviders(location) {
    if (!state.map || typeof L === 'undefined') return;
    state.providerMarkers.forEach((marker) => state.map.removeLayer(marker));
    state.providerMarkers = [];

    if (state.clientMarker) {
      state.map.removeLayer(state.clientMarker);
      state.clientMarker = null;
    }

    state.clientMarker = L.marker([location.lat, location.lng]).addTo(state.map).bindPopup(copy('currentLocationPopup'));

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
    const coverageNote = coverageWarningMessage(provider, true);
    const inlineBadgeHtml = [
      provider.is_verified_blue
        ? '<span style="display:inline-flex;align-items:center;justify-content:center;vertical-align:middle">' + UI.icon('verified_blue', 12, '#2196F3').outerHTML + '</span>'
        : '',
      provider.is_verified_green
        ? '<span style="display:inline-flex;align-items:center;justify-content:center;vertical-align:middle">' + UI.icon('verified_green', 12, '#16A34A').outerHTML + '</span>'
        : '',
    ].filter(Boolean).join('<span style="display:inline-block;width:4px"></span>');
    const badgeClass = provider.is_verified_blue ? 'blue' : (provider.is_verified_green ? 'green' : '');
    const badge = badgeClass
      ? '<span class="ur-provider-badge ' + badgeClass + '"><svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor"><path d="M9 16.17 4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z"/></svg></span>'
      : '';
    const image = provider.profile_image
      ? '<img src="' + escapeHtml(provider.profile_image) + '" alt="">'
      : '<div class="ur-provider-avatar-fallback">' + escapeHtml((provider.display_name || 'P').charAt(0)) + '</div>';
    const call = provider.phone
      ? '<a class="call" href="tel:' + escapeHtml(provider.phone) + '">' + escapeHtml(copy('popupCall')) + '</a>'
      : '<span class="call is-disabled">' + escapeHtml(copy('popupCall')) + '</span>';
    const whatsapp = provider.whatsapp_url
      ? '<a class="whatsapp" target="_blank" rel="noopener" href="' + escapeHtml(provider.whatsapp_url) + '">' + escapeHtml(copy('popupWhatsapp')) + '</a>'
      : '<span class="whatsapp is-disabled">' + escapeHtml(copy('popupWhatsapp')) + '</span>';
    return [
      '<div class="ur-popup">',
      '<div class="ur-popup-head">',
      '<div class="ur-popup-avatar">' + image + badge + '</div>',
      '<div class="ur-popup-copy">',
      '<div class="ur-popup-title-row"><div class="ur-popup-title"><span>' + escapeHtml(provider.display_name) + '</span>' + inlineBadgeHtml + '</div></div>',
      '<div class="ur-popup-meta-chips">',
      '<span class="ur-popup-chip">⭐ ' + formatRating(provider.rating_avg) + '</span>',
      '<span class="ur-popup-chip">' + escapeHtml(copy('providerCountCompleted', { count: String(provider.completed_requests || 0) })) + '</span>',
      '</div>',
      '<div class="ur-popup-meta">' + escapeHtml(provider.city_display || copy('providerWithinCity')) + '</div>',
      '</div>',
      '</div>',
      coverageNote ? '<div class="ur-provider-coverage-note">' + escapeHtml(coverageNote) + '</div>' : '',
      '<div class="ur-popup-actions">',
      '<a class="profile" href="' + escapeHtml(provider.profile_href) + '">' + escapeHtml(copy('popupProfile')) + '</a>',
      call,
      whatsapp,
      '<button class="send send-primary" type="button" data-provider-select="' + String(provider.id) + '">' + escapeHtml(copy('popupSend')) + '</button>',
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
      empty.textContent = copy('noProvidersSelectedCity');
      list.appendChild(empty);
      return;
    }

    state.nearbyProviders.forEach((provider) => {
      const card = document.createElement('div');
      card.className = 'ur-provider-card' + (state.selectedProvider?.id === provider.id ? ' selected' : '');
      const coverageNote = coverageWarningMessage(provider, true);

      const inlineBadgeHtml = [
        provider.is_verified_blue
          ? '<span style="display:inline-flex;align-items:center;justify-content:center;vertical-align:middle">' + UI.icon('verified_blue', 12, '#2196F3').outerHTML + '</span>'
          : '',
        provider.is_verified_green
          ? '<span style="display:inline-flex;align-items:center;justify-content:center;vertical-align:middle">' + UI.icon('verified_green', 12, '#16A34A').outerHTML + '</span>'
          : '',
      ].filter(Boolean).join('<span style="display:inline-block;width:4px"></span>');
      const badgeClass = provider.is_verified_blue ? 'blue' : (provider.is_verified_green ? 'green' : '');
      const badgeHtml = badgeClass
        ? '<span class="ur-provider-badge ' + badgeClass + '"><svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor"><path d="M9 16.17 4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z"/></svg></span>'
        : '';
      const avatarHtml = provider.profile_image
        ? '<img src="' + escapeHtml(provider.profile_image) + '" alt="' + escapeHtml(copy('providerCardAlt')) + '">'
        : '<div class="ur-provider-avatar-fallback">' + escapeHtml((provider.display_name || 'P').charAt(0)) + '</div>';

      card.innerHTML = [
        '<div class="ur-provider-card-head">',
        '<div class="ur-provider-card-avatar">' + avatarHtml + badgeHtml + '</div>',
        '<div style="min-width:0;flex:1 1 auto">',
        '<h4 class="ur-provider-card-name" style="display:flex;align-items:center;gap:6px;flex-wrap:wrap"><span>' + escapeHtml(provider.display_name) + '</span>' + inlineBadgeHtml + '</h4>',
        '<div class="ur-provider-card-sub">',
        '<span>⭐ ' + formatRating(provider.rating_avg) + '</span>',
        '<span>' + escapeHtml(copy('providerCountCompleted', { count: String(provider.completed_requests || 0) })) + '</span>',
        '<span>' + escapeHtml(copy('providerDistance', { value: provider._distance.toFixed(1) })) + '</span>',
        '</div>',
        coverageNote ? '<div class="ur-provider-coverage-note">' + escapeHtml(coverageNote) + '</div>' : '',
        '</div>',
        '</div>',
        '<div class="ur-provider-card-actions">',
        provider.phone ? '<a href="tel:' + escapeHtml(provider.phone) + '" class="ur-action-btn ur-action-call">' + escapeHtml(copy('providerCall')) + '</a>' : '',
        provider.whatsapp_url ? '<a href="' + escapeHtml(provider.whatsapp_url) + '" target="_blank" rel="noopener" class="ur-action-btn ur-action-whatsapp">' + escapeHtml(copy('providerWhatsapp')) + '</a>' : '',
        '<button type="button" class="ur-action-btn ur-action-send" data-select-provider="' + String(provider.id) + '">' + escapeHtml(copy('popupSend')) + '</button>',
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
    showToast(
      isProviderOutsideCoverage(provider) ? copy('providerOutOfCoverageToast') : copy('providerSelected'),
      isProviderOutsideCoverage(provider) ? 'warning' : 'success'
    );
  }

  function clearSelectedProvider(update = true) {
    state.selectedProvider = null;
    if (update) {
      hydrateSelectedProvider();
      renderProviderCards();
      updateSummary();
    } else {
      hydrateSelectedProvider();
    }
  }

  function hydrateSelectedProvider() {
    const provider = state.selectedProvider;
    dom['ur-selected-provider']?.classList.toggle('hidden', !provider || getDispatchMode() !== 'nearest');
    if (!provider) {
      if (dom['ur-provider-name']) dom['ur-provider-name'].textContent = copy('selectedProviderNone');
      if (dom['ur-provider-location']) dom['ur-provider-location'].textContent = copy('selectedProviderPrompt');
      if (dom['ur-provider-rating']) dom['ur-provider-rating'].textContent = copy('providerRating', { value: '—' });
      if (dom['ur-provider-completed']) dom['ur-provider-completed'].textContent = copy('providerCompleted', { value: '—' });
      if (dom['ur-provider-distance']) dom['ur-provider-distance'].textContent = copy('providerDistance', { value: '—' });
      const warning = dom['ur-provider-coverage-warning'];
      if (warning) {
        warning.textContent = '';
        warning.classList.add('hidden');
      }
      dom['ur-provider-call']?.classList.add('hidden');
      dom['ur-provider-whatsapp']?.classList.add('hidden');
      return;
    }

    if (dom['ur-provider-name']) {
      const inlineBadgeHtml = [
        provider.is_verified_blue
          ? '<span style="display:inline-flex;align-items:center;justify-content:center;vertical-align:middle">' + UI.icon('verified_blue', 12, '#2196F3').outerHTML + '</span>'
          : '',
        provider.is_verified_green
          ? '<span style="display:inline-flex;align-items:center;justify-content:center;vertical-align:middle">' + UI.icon('verified_green', 12, '#16A34A').outerHTML + '</span>'
          : '',
      ].filter(Boolean).join('<span style="display:inline-block;width:4px"></span>');
      dom['ur-provider-name'].innerHTML = '<span>' + escapeHtml(provider.display_name) + '</span>' + inlineBadgeHtml;
      dom['ur-provider-name'].style.display = 'flex';
      dom['ur-provider-name'].style.alignItems = 'center';
      dom['ur-provider-name'].style.gap = '6px';
      dom['ur-provider-name'].style.flexWrap = 'wrap';
    }
    if (dom['ur-provider-location']) dom['ur-provider-location'].textContent = provider.city_display || copy('providerWithinCity');
    if (dom['ur-provider-rating']) dom['ur-provider-rating'].textContent = copy('providerRating', { value: formatRating(provider.rating_avg) });
    if (dom['ur-provider-completed']) dom['ur-provider-completed'].textContent = copy('providerCompleted', { value: String(provider.completed_requests || 0) });
    if (dom['ur-provider-distance']) dom['ur-provider-distance'].textContent = copy('providerDistance', { value: provider._distance.toFixed(1) });
    const warning = dom['ur-provider-coverage-warning'];
    if (warning) {
      const message = coverageWarningMessage(provider);
      warning.textContent = message;
      warning.classList.toggle('hidden', !message);
    }

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
        fallback.textContent = (provider.display_name || 'P').charAt(0);
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
    const dispatch = getDispatchMode();

    if (!category) {
      setFieldError('ur-category', copy('validateCategory'));
      focusField('ur-category');
      return copy('validateCategory');
    }
    if (!subcategory) {
      setFieldError('ur-subcategory', copy('validateSubcategory'));
      focusField('ur-subcategory');
      return copy('validateSubcategory');
    }
    if (!title) {
      setFieldError('ur-title', copy('validateTitle'));
      focusField('ur-title');
      return copy('validateTitle');
    }
    if (!description) {
      setFieldError('ur-description', copy('validateDescription'));
      focusField('ur-description');
      return copy('validateDescription');
    }
    if (dispatch === 'nearest' && !state.selectedProvider) {
      showToast(copy('validateProviderNearest'), 'warning');
      return copy('validateProviderNearest');
    }
    return '';
  }

  function applyApiErrors(data) {
    if (!data || typeof data !== 'object') return '';
    const fieldMap = {
      subcategory: 'ur-subcategory',
      subcategory_ids: 'ur-subcategory',
      title: 'ur-title',
      description: 'ur-description',
      provider: 'ur-subcategory',
      request_lat: 'ur-subcategory',
      request_lng: 'ur-subcategory',
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
    const title = String(dom['ur-title']?.value || '').trim();
    const description = String(dom['ur-description']?.value || '').trim();
    const subcategory = String(dom['ur-subcategory']?.value || '').trim();

    state.isSubmitting = true;
    setSubmitPending(true);

    try {
      let location = null;
      let resolvedScope = null;
      if (dispatch === 'nearest') {
        location = await resolveClientLocation(true);
        if (!location) {
          showToast(copy('enableLocationSubmit'), 'error');
          return;
        }
      } else if (dispatch === 'all' && selectedSubcategoryRequiresGeoScope()) {
        try {
          resolvedScope = await resolveAllDispatchScope(true);
        } catch (_) {
          showToast(copy('detectLocationFailed'), 'error');
          return;
        }
        if (!resolvedScope?.city) {
          showToast(copy(state.clientLocation ? 'detectLocationFailed' : 'enableLocationAll'), 'error');
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
      if (dispatch === 'all' && resolvedScope?.city) {
        formData.append('city', resolvedScope.city);
      }
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
        disableCompletionRedirect: true,
      });

      if (res.ok) {
        onSubmitSuccess(dispatch);
      } else {
        if (res.data && res.data.error_code === 'profile_completion_required') {
          showToast(res.data.detail || copy('submitError'), 'warning');
          return;
        }
        if (res.data && res.data.error_code === 'profile_location_required') {
          showToast(copy('locationRequiredBody'), 'warning');
          try { await resolveAllDispatchScope(true); updateSummary(); } catch (_) {}
          return;
        }
        const message = applyApiErrors(res.data) || res.data?.detail || copy('submitError');
        showToast(message, 'error');
      }
    } catch (_) {
      showToast(copy('connectionError'), 'error');
    } finally {
      state.isSubmitting = false;
      setSubmitPending(false);
    }
  }

  function setSubmitPending(isPending) {
    const button = dom['ur-submit'];
    if (!button) return;
    button.disabled = !!isPending;
    setText('ur-submit-text', isPending ? copy('submitPending') : copy('submit'));
  }

  function onSubmitSuccess(dispatch) {
    state.images = [];
    state.videos = [];
    state.files = [];
    state.audio = null;
    renderAttachments();
    if (dom['ur-success-message']) {
      dom['ur-success-message'].textContent = dispatch === 'nearest' && state.selectedProvider
        ? copy('successNearest', { provider: state.selectedProvider.display_name })
        : copy('successAll');
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
        success: copy('toneSuccess'),
        warning: copy('toneWarning'),
        error: copy('toneError'),
        info: copy('toneInfo'),
      })[type];
    }
    if (dom['ur-toast-message']) dom['ur-toast-message'].textContent = message || copy('toastDefaultMessage');
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

  return {
    refreshLanguage,
  };
})();
