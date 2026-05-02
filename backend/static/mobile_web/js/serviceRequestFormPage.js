/* ═══════════════════════════════════════════════════════
   serviceRequestFormPage.js — Grand Rebuild 2026-04-18
   ═══════════════════════════════════════════════════════ */
(function () {
  "use strict";

  /* ── Constants ── */
  var API = {
    CATEGORIES:    "/api/providers/categories/",
    REGIONS:       "/api/providers/geo/regions-cities/",
    CREATE:        "/api/marketplace/requests/create/",
    PROVIDERS:     "/api/providers/list/",
  };

  /* ── State ── */
  var categories       = [];
  var regionCatalog    = [];
  var requestType      = "competitive";
  var dispatchMode     = "all";
  var providerId       = null;
  var serviceId        = null;
  var fixedTargetCtx   = null;
  var nearestProvider  = null;
  var requestLat       = null;
  var requestLng       = null;
  var leafletMap       = null;
  var leafletMarker    = null;
  var providerMarkers  = [];
  var nearbyProviders  = [];
  var imageFiles       = [];
  var videoFiles       = [];
  var docFiles         = [];
  var audioBlob        = null;
  var mediaRecorder    = null;
  var audioChunks      = [];
  var isRecording      = false;
  var isSubmitting     = false;
  var submitOverlay    = null;
  var toastTimer       = null;
  var returnTimer      = null;
  var returnTargetUrl  = "/orders/";
  var holdSuccessState = false;

  function el(id) { return document.getElementById(id); }
  var dom = {};
  var languageObserver = null;

  var COPY = {
    ar: {
      pageTitle: "نوافــذ — طلب خدمة",
      submitOverlayTitle: "جارٍ إرسال الطلب...",
      submitOverlayMessage: "يرجى الانتظار حتى تكتمل العملية.",
      providerGateKicker: "وضع الحساب الحالي",
      providerGateTitle: "إنشاء الطلبات متاح في وضع العميل فقط",
      providerGateDescription: "أنت تستخدم المنصة الآن بوضع مقدم الخدمة، لذلك لا يمكن إرسال طلب مباشر أو تنافسي أو عاجل من هذا الوضع.",
      providerGateNote: "بدّل نوع الحساب إلى عميل الآن، ثم أكمل الطلب من نفس الصفحة مباشرة.",
      providerGateSwitch: "التبديل إلى عميل",
      providerGateProfile: "الذهاب إلى نافذتي",
      loginTitle: "سجّل دخولك لإرسال الطلب",
      loginDescription: "سيتم حفظ الطلب وربطه بحسابك حتى تتابع حالته وتستقبل العروض والردود.",
      loginButton: "تسجيل الدخول",
      headerTitle: "بيانات الطلب",
      headerSubtitle: "ابدأ بالمطلوب، واترك الحقول الاختيارية عند الحاجة.",
      sectionTypeTitle: "نوع الخدمة",
      sectionScopeTitle: "التصنيف المناسب",
      sectionDispatchTitle: "طريقة الوصول للمزودين",
      sectionDetailsTitle: "وصف الطلب",
      sectionAttachmentsTitle: "المرفقات",
      optionalLabel: "(اختياري)",
      typeCompetitive: "تنافسي",
      typeUrgent: "عاجل",
      typeDirect: "مباشر",
      categoryLabel: "القسم الرئيسي",
      subcategoryLabel: "التصنيف الفرعي",
      categoryPlaceholder: "اختر القسم",
      subcategoryPlaceholder: "اختر التصنيف",
      fixedProviderLabel: "المزود",
      fixedServiceLabel: "الخدمة",
      fixedCategoryLabel: "القسم",
      fixedSubcategoryLabel: "التصنيف",
      fixedCityLabel: "المدينة",
      directScopeTitle: "طلب مباشر لمزود خدمة",
      directScopeText: "تم تحديد المزود تلقائيًا بناءً على صفحة المزود.",
      serviceIdFallback: "خدمة #{id}",
      providerFallbackName: "مزود الخدمة",
      cityGroupLabel: "المنطقة والمدينة",
      regionPlaceholder: "اختر المنطقة",
      cityPlaceholder: "اختر المدينة",
      cityEmptyPlaceholder: "اختر المنطقة أولًا",
      cityClear: "مسح المدينة",
      dispatchModeTitle: "طريقة التوجيه",
      dispatchAll: "إرسال للجميع",
      dispatchNearest: "إرسال للأقرب",
      providerChange: "تغيير",
      providerRemove: "إزالة",
      requestTitleLabel: "عنوان الطلب",
      requestTitlePlaceholder: "مثال: تصميم موقع إلكتروني",
      descriptionLabel: "وصف الطلب",
      descriptionPlaceholder: "اشرح المطلوب بدقة ...",
      deadlineLabel: "آخر موعد لاستلام العروض",
      imagesLabel: "صور",
      videosLabel: "فيديو",
      filesLabel: "ملفات",
      audioLabel: "تسجيل صوتي",
      audioStop: "إيقاف التسجيل",
      audioRemove: "حذف",
      submitDefault: "إرسال الطلب",
      submitCompetitive: "إرسال الطلب التنافسي",
      submitUrgent: "إرسال الطلب العاجل",
      submitDirect: "إرسال الطلب المباشر",
      submitHelperDefault: "اكتب المطلوب بوضوح وأرفق ما يلزم فقط.",
      submitHelperCompetitive: "سيتمكن المزودون من تقديم عروضهم عليه.",
      submitHelperUrgent: "سيتم إرسال الطلب فورًا للمزودين المتاحين.",
      submitHelperDirect: "سيتم إرسال الطلب مباشرة إلى المزود المحدد.",
      mapTitle: "اختيار مزود قريب",
      closeAria: "إغلاق",
      mapLocating: "جاري تحديد موقعك...",
      mapUnsupported: "المتصفح لا يدعم تحديد الموقع. يتم استخدام الموقع الافتراضي.",
      mapReadError: "تعذر قراءة موقعك الحالي. حاول مرة أخرى.",
      mapSearching: "تم تحديد موقعك. جاري البحث عن المزودين...",
      mapDenied: "لم يتم السماح بتحديد الموقع. يتم استخدام الموقع الافتراضي.",
      mapEmpty: "لا يوجد مزودون قريبون في هذا النطاق.",
      providerCompleted: "{count} مكتمل",
      providerRequests: "{count} طلب",
      providerDistance: "{value} كم",
      popupCall: "اتصال",
      popupWhatsapp: "واتساب",
      popupChoose: "اختيار",
      providerSelectedTitle: "تم الاختيار",
      providerSelectedMessage: "تم اختيار {name} كمزود قريب.",
      validationCategory: "اختر القسم الرئيسي",
      validationSubcategory: "اختر التصنيف الفرعي",
      validationTitle: "أدخل عنوان الطلب",
      validationDescription: "أدخل وصف الطلب",
      validationDeadlinePast: "التاريخ يجب أن يكون اليوم أو لاحقًا",
      toastError: "خطأ",
      toastSuccess: "تم بنجاح",
      toastWarning: "تنبيه",
      toastInfo: "معلومة",
      submitUnexpectedError: "حدث خطأ غير متوقع. حاول مرة أخرى.",
      directSentButton: "تم إرسال الطلب",
      directSentHelper: "يمكنك متابعة الطلب من صفحة طلباتي. جارٍ إعادتك للصفحة السابقة...",
      directSentToastTitle: "تم إرسال طلبك",
      directSentToastMessage: "تم إرسال طلبك إلى {provider}. يمكنك متابعة الطلب من صفحة طلباتي.",
      successUrgentTitle: "تم إرسال الطلب العاجل",
      successUrgentMessage: "سيتم إشعار المزودين المتاحين فورًا.",
      successCompetitiveTitle: "تم إرسال الطلب التنافسي",
      successCompetitiveMessage: "ستبدأ العروض بالوصول قريبًا.",
      successNormalTitle: "تم إرسال الطلب",
      successNormalMessage: "تم إرسال طلبك بنجاح للمزود.",
      successToastTitle: "تم الإرسال",
      successToastMessage: "تم إرسال طلبك بنجاح ✓",
      submitErrorGeneric: "حدث خطأ أثناء إرسال الطلب. حاول مرة أخرى.",
      sessionExpiredTitle: "جلسة منتهية",
      sessionExpiredMessage: "يرجى تسجيل الدخول مرة أخرى.",
      ordersLink: "عرض طلباتي",
      homeLink: "العودة للرئيسية",
      heroCompetitiveBadge: "نوع الطلب: تنافسي",
      heroCompetitiveTitle: "طلب خدمة تنافسي",
      heroCompetitiveSubtitle: "أطلق طلبك ليصل إلى المزودين المطابقين ويقدموا لك عروضهم للمقارنة.",
      heroCompetitiveNoteTitle: "هذا النوع مناسب للمقارنة بين العروض",
      heroCompetitiveNoteBody: "يصل طلبك إلى المزودين المطابقين ليقدموا لك عروضهم، ثم تختار الأنسب من حيث السعر والمدة وطريقة التنفيذ.",
      heroCompetitivePill1: "مطابقة ذكية حسب التخصص",
      heroCompetitivePill2: "استقبال أكثر من عرض",
      heroCompetitivePill3: "إمكانية تحديد موعد العروض",
      heroUrgentBadge: "نوع الطلب: عاجل",
      heroUrgentTitle: "طلب خدمة عاجل",
      heroUrgentSubtitle: "مسار سريع للحالات التي تحتاج استجابة فورية من المزودين المطابقين.",
      heroUrgentNoteTitle: "هذا النوع مصمم للحالات العاجلة",
      heroUrgentNoteBody: "يمكنك الإرسال للجميع أو اختيار الأقرب عبر الخريطة، مع إبراز التطابق حسب التصنيف والمدينة.",
      heroUrgentPill1: "استجابة أسرع للطلب",
      heroUrgentPill2: "إرسال للجميع أو للأقرب",
      heroUrgentPill3: "خريطة تفاعلية للتوجيه",
      heroDirectBadge: "نوع الطلب: مباشر",
      heroDirectTitle: "طلب مباشر",
      heroDirectSubtitle: "سيتم إرسال طلبك مباشرة لـ {provider}، دون إدخاله في مسار تنافسي أو عاجل.",
      heroDirectNoteTitle: "هذا النوع موجه لمزود محدد",
      heroDirectNoteBody: "يصل الطلب مباشرة إلى المزود الذي اخترته، مع الحفاظ على نفس جودة التفاصيل والمرفقات.",
      heroDirectPill1: "موجه إلى مزود واحد",
      heroDirectPill2: "دقة في نطاق الإرسال",
      heroDirectPill3: "وضوح في نوع الطلب"
    },
    en: {
      pageTitle: "Nawafeth — Service Request",
      submitOverlayTitle: "Sending request...",
      submitOverlayMessage: "Please wait until the action completes.",
      providerGateKicker: "Current account mode",
      providerGateTitle: "Request creation is only available in client mode",
      providerGateDescription: "You are using the platform in provider mode right now, so direct, competitive, or urgent requests cannot be sent from this mode.",
      providerGateNote: "Switch your account type to client now, then continue the request from the same page.",
      providerGateSwitch: "Switch to client",
      providerGateProfile: "Go to My Profile",
      loginTitle: "Sign in to send the request",
      loginDescription: "The request will be saved to your account so you can track it and receive offers and replies.",
      loginButton: "Sign in",
      headerTitle: "Request details",
      headerSubtitle: "Start with the core need, and leave optional fields empty when needed.",
      sectionTypeTitle: "Service type",
      sectionScopeTitle: "Matching category",
      sectionDispatchTitle: "How providers will be reached",
      sectionDetailsTitle: "Request description",
      sectionAttachmentsTitle: "Attachments",
      optionalLabel: "(Optional)",
      typeCompetitive: "Competitive",
      typeUrgent: "Urgent",
      typeDirect: "Direct",
      categoryLabel: "Main category",
      subcategoryLabel: "Subcategory",
      categoryPlaceholder: "Choose a category",
      subcategoryPlaceholder: "Choose a subcategory",
      fixedProviderLabel: "Provider",
      fixedServiceLabel: "Service",
      fixedCategoryLabel: "Category",
      fixedSubcategoryLabel: "Subcategory",
      fixedCityLabel: "City",
      directScopeTitle: "Direct request to a provider",
      directScopeText: "The provider was selected automatically from the provider page.",
      serviceIdFallback: "Service #{id}",
      providerFallbackName: "the provider",
      cityGroupLabel: "Region and city",
      regionPlaceholder: "Choose a region",
      cityPlaceholder: "Choose a city",
      cityEmptyPlaceholder: "Choose the region first",
      cityClear: "Clear city",
      dispatchModeTitle: "Dispatch method",
      dispatchAll: "Send to all",
      dispatchNearest: "Send to nearest",
      providerChange: "Change",
      providerRemove: "Remove",
      requestTitleLabel: "Request title",
      requestTitlePlaceholder: "Example: Website design",
      descriptionLabel: "Request description",
      descriptionPlaceholder: "Explain what you need clearly...",
      deadlineLabel: "Offer deadline",
      imagesLabel: "Images",
      videosLabel: "Video",
      filesLabel: "Files",
      audioLabel: "Voice note",
      audioStop: "Stop recording",
      audioRemove: "Delete",
      submitDefault: "Send request",
      submitCompetitive: "Send competitive request",
      submitUrgent: "Send urgent request",
      submitDirect: "Send direct request",
      submitHelperDefault: "Describe the need clearly and attach only what is necessary.",
      submitHelperCompetitive: "Matching providers will be able to send their offers.",
      submitHelperUrgent: "The request will be sent immediately to available providers.",
      submitHelperDirect: "The request will be sent directly to the selected provider.",
      mapTitle: "Choose a nearby provider",
      closeAria: "Close",
      mapLocating: "Locating you...",
      mapUnsupported: "This browser does not support geolocation. The default location will be used.",
      mapReadError: "Could not read your current location. Please try again.",
      mapSearching: "Your location was found. Searching for providers...",
      mapDenied: "Location permission was not granted. The default location will be used.",
      mapEmpty: "No nearby providers were found in this range.",
      providerCompleted: "{count} completed",
      providerRequests: "{count} requests",
      providerDistance: "{value} km",
      popupCall: "Call",
      popupWhatsapp: "WhatsApp",
      popupChoose: "Choose",
      providerSelectedTitle: "Selected",
      providerSelectedMessage: "{name} was selected as the nearby provider.",
      validationCategory: "Choose the main category",
      validationSubcategory: "Choose the subcategory",
      validationTitle: "Enter the request title",
      validationDescription: "Enter the request description",
      validationDeadlinePast: "The date must be today or later",
      toastError: "Error",
      toastSuccess: "Done successfully",
      toastWarning: "Notice",
      toastInfo: "Information",
      submitUnexpectedError: "An unexpected error occurred. Please try again.",
      directSentButton: "Request sent",
      directSentHelper: "You can track the request from My Orders. Returning you to the previous page...",
      directSentToastTitle: "Your request was sent",
      directSentToastMessage: "Your request was sent to {provider}. You can track it from My Orders.",
      successUrgentTitle: "Urgent request sent",
      successUrgentMessage: "Available providers will be notified immediately.",
      successCompetitiveTitle: "Competitive request sent",
      successCompetitiveMessage: "Offers will start arriving soon.",
      successNormalTitle: "Request sent",
      successNormalMessage: "Your request was sent successfully to the provider.",
      successToastTitle: "Sent",
      successToastMessage: "Your request was sent successfully ✓",
      submitErrorGeneric: "An error occurred while sending the request. Please try again.",
      sessionExpiredTitle: "Session expired",
      sessionExpiredMessage: "Please sign in again.",
      ordersLink: "View My Orders",
      homeLink: "Back to home",
      heroCompetitiveBadge: "Request type: Competitive",
      heroCompetitiveTitle: "Competitive service request",
      heroCompetitiveSubtitle: "Launch your request so matching providers can send offers for comparison.",
      heroCompetitiveNoteTitle: "This type is best for comparing offers",
      heroCompetitiveNoteBody: "Your request reaches matching providers so they can send offers, then you choose the best one by price, timing, and delivery method.",
      heroCompetitivePill1: "Smart matching by specialty",
      heroCompetitivePill2: "Receive multiple offers",
      heroCompetitivePill3: "Optional offer deadline",
      heroUrgentBadge: "Request type: Urgent",
      heroUrgentTitle: "Urgent service request",
      heroUrgentSubtitle: "A fast path for cases that need an immediate response from matching providers.",
      heroUrgentNoteTitle: "This type is built for urgent cases",
      heroUrgentNoteBody: "You can send to all or choose the nearest provider from the map, with matching based on category and city.",
      heroUrgentPill1: "Faster response",
      heroUrgentPill2: "Send to all or nearest",
      heroUrgentPill3: "Interactive routing map",
      heroDirectBadge: "Request type: Direct",
      heroDirectTitle: "Direct request",
      heroDirectSubtitle: "Your request will be sent directly to {provider}, without entering a competitive or urgent flow.",
      heroDirectNoteTitle: "This type targets one provider",
      heroDirectNoteBody: "The request goes directly to the provider you selected, while preserving the same level of detail and attachments.",
      heroDirectPill1: "Sent to one provider",
      heroDirectPill2: "Precise delivery scope",
      heroDirectPill3: "Clear request mode"
    }
  };

  function currentLang() {
    try {
      if (window.NawafethI18n && typeof window.NawafethI18n.getLanguage === "function") {
        return window.NawafethI18n.getLanguage() === "en" ? "en" : "ar";
      }
    } catch (_) {}
    try {
      return (localStorage.getItem("nw_lang") || "ar").toLowerCase() === "en" ? "en" : "ar";
    } catch (_) {
      return "ar";
    }
  }

  function interpolate(template, replacements) {
    var value = String(template || "");
    if (!replacements || typeof replacements !== "object") return value;
    return value.replace(/\{(\w+)\}/g, function (_, key) {
      return Object.prototype.hasOwnProperty.call(replacements, key) ? String(replacements[key]) : "";
    });
  }

  function text(key, replacements) {
    var lang = currentLang();
    var bundle = COPY[lang] || COPY.ar;
    var template = Object.prototype.hasOwnProperty.call(bundle, key) ? bundle[key] : COPY.ar[key];
    return interpolate(template || "", replacements);
  }

  function setText(id, value) {
    var node = el(id);
    if (node) node.textContent = value;
  }

  function setAttr(id, name, value) {
    var node = el(id);
    if (node) node.setAttribute(name, value);
  }

  function setPlaceholder(id, value) {
    var node = el(id);
    if (node) node.setAttribute("placeholder", value);
  }

  function observeLanguageChanges() {
    if (languageObserver || typeof MutationObserver === "undefined" || !document.documentElement) return;
    languageObserver = new MutationObserver(function () { refreshLanguage(); });
    languageObserver.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ["lang", "dir"],
    });
  }

  function refreshSelectPlaceholders() {
    if (dom.category) {
      var categoryOption = dom.category.querySelector('option[value=""]');
      if (categoryOption) categoryOption.textContent = text("categoryPlaceholder");
    }
    if (dom.subcategory) {
      var subcategoryOption = dom.subcategory.querySelector('option[value=""]');
      if (subcategoryOption) subcategoryOption.textContent = text("subcategoryPlaceholder");
    }
  }

  function refreshRegionCityOptions() {
    var regionValue = dom.region ? String(dom.region.value || "") : "";
    var cityValue = dom.city ? String(dom.city.value || "") : "";
    if (regionCatalog.length) {
      UI.populateRegionOptions(dom.region, regionCatalog, {
        placeholder: text("regionPlaceholder"),
        currentValue: regionValue,
      });
      UI.populateCityOptions(dom.city, regionCatalog, regionValue, {
        currentValue: cityValue,
        placeholder: text("cityPlaceholder"),
        emptyPlaceholder: text("cityEmptyPlaceholder"),
      });
      dom.city.disabled = !regionValue;
    } else {
      if (dom.region) dom.region.innerHTML = '<option value="">' + escHtml(text("regionPlaceholder")) + '</option>';
      if (dom.city) {
        dom.city.innerHTML = '<option value="">' + escHtml(text("cityPlaceholder")) + '</option>';
        dom.city.disabled = true;
      }
    }
    if (dom.cityClear) dom.cityClear.classList.toggle("hidden", !cityValue);
  }

  function applyStaticCopy() {
    document.title = text("pageTitle");
    setText("sr-provider-kicker", text("providerGateKicker"));
    setText("sr-provider-title", text("providerGateTitle"));
    setText("sr-provider-description", text("providerGateDescription"));
    setText("sr-provider-switch", text("providerGateSwitch"));
    setText("sr-provider-profile", text("providerGateProfile"));
    setText("sr-provider-note", text("providerGateNote"));
    setText("sr-login-title", text("loginTitle"));
    setText("sr-login-description", text("loginDescription"));
    setText("sr-login-link", text("loginButton"));
    setText("sr-header-title", text("headerTitle"));
    setText("sr-header-subtitle", text("headerSubtitle"));
    setText("sr-section-type-title", text("sectionTypeTitle"));
    setText("sr-section-scope-title", text("sectionScopeTitle"));
    setText("sr-section-dispatch-title", text("sectionDispatchTitle"));
    setText("sr-section-details-title", text("sectionDetailsTitle"));
    setText("sr-section-attachments-title", text("sectionAttachmentsTitle"));
    setText("sr-section-attachments-optional", text("optionalLabel"));
    setText("sr-type-competitive-text", text("typeCompetitive"));
    setText("sr-type-urgent-text", text("typeUrgent"));
    setText("sr-type-direct-text", text("typeDirect"));
    setText("sr-category-label", text("categoryLabel"));
    setText("sr-subcategory-label", text("subcategoryLabel"));
    setText("sr-fixed-provider-label", text("fixedProviderLabel"));
    setText("sr-fixed-service-label", text("fixedServiceLabel"));
    setText("sr-fixed-category-label", text("fixedCategoryLabel"));
    setText("sr-fixed-subcategory-label", text("fixedSubcategoryLabel"));
    setText("sr-fixed-city-label", text("fixedCityLabel"));
    setText("sr-city-group-label", text("cityGroupLabel"));
    setText("sr-city-group-optional", text("optionalLabel"));
    setText("sr-city-clear", text("cityClear"));
    setText("sr-dispatch-mode-title", text("dispatchModeTitle"));
    setText("sr-dispatch-all-text", text("dispatchAll"));
    setText("sr-dispatch-nearest-text", text("dispatchNearest"));
    setText("sr-sp-change", text("providerChange"));
    setText("sr-sp-remove", text("providerRemove"));
    setText("sr-req-title-label", text("requestTitleLabel"));
    setPlaceholder("sr-req-title", text("requestTitlePlaceholder"));
    setText("sr-desc-label", text("descriptionLabel"));
    setPlaceholder("sr-desc", text("descriptionPlaceholder"));
    setText("sr-deadline-label", text("deadlineLabel"));
    setText("sr-deadline-optional", text("optionalLabel"));
    setText("sr-images-text", text("imagesLabel"));
    setText("sr-videos-text", text("videosLabel"));
    setText("sr-files-text", text("filesLabel"));
    setText("sr-audio-btn-text", isRecording ? text("audioStop") : text("audioLabel"));
    setText("sr-audio-remove", text("audioRemove"));
    setText("sr-map-title", text("mapTitle"));
    setText("sr-modal-empty", text("mapEmpty"));
    setText("sr-success-orders-link", text("ordersLink"));
    setText("sr-success-home-link", text("homeLink"));
    setAttr("sr-map-modal-close", "aria-label", text("closeAria"));
    setAttr("sr-toast-close", "aria-label", text("closeAria"));
    if (!holdSuccessState && dom.success && !dom.success.classList.contains("visible")) {
      setText("sr-success-title", text("successNormalTitle"));
      setText("sr-success-message", text("successNormalMessage"));
    }
    if (submitOverlay && typeof submitOverlay.update === "function") {
      submitOverlay.update({
        title: text("submitOverlayTitle"),
        message: text("submitOverlayMessage"),
      });
    }
    refreshSelectPlaceholders();
    refreshRegionCityOptions();
  }

  function refreshLanguage() {
    applyStaticCopy();
    applyCurrentTypeCopy();
    updateFixedTargetCopy();
    if (nearestProvider) showSelectedProviderCard(nearestProvider);
    if (dom.modalList && nearbyProviders.length) renderProvidersList();
  }

  function updateFixedTargetCopy() {
    if (!fixedTargetCtx) return;
    if (dom.scopeTitle) dom.scopeTitle.textContent = text("directScopeTitle");
    if (dom.scopeText) dom.scopeText.textContent = text("directScopeText");
    if (serviceId && dom.fixedService) dom.fixedService.textContent = text("serviceIdFallback", { id: serviceId });
  }

  function applyCurrentTypeCopy() {
    var isCompetitive = requestType === "competitive";
    if (fixedTargetCtx) {
      updateHeroTypeContent("normal", fixedTargetCtx.providerName);
      if (dom.submitText) dom.submitText.textContent = text("submitDirect");
      if (dom.submitHelper) dom.submitHelper.textContent = text("submitHelperDirect");
      return;
    }
    if (requestType === "urgent") {
      updateHeroTypeContent("urgent");
      if (dom.submitText) dom.submitText.textContent = text("submitUrgent");
      if (dom.submitHelper) dom.submitHelper.textContent = text("submitHelperUrgent");
    } else if (isCompetitive) {
      updateHeroTypeContent("competitive");
      if (dom.submitText) dom.submitText.textContent = text("submitCompetitive");
      if (dom.submitHelper) dom.submitHelper.textContent = text("submitHelperCompetitive");
    } else {
      updateHeroTypeContent("normal");
      if (dom.submitText) dom.submitText.textContent = text("submitDefault");
      if (dom.submitHelper) dom.submitHelper.textContent = text("submitHelperDefault");
    }
  }

  /* ═══════════════════════════════════════
     init()
     ═══════════════════════════════════════ */
  function init() {
    cacheDom();
    document.addEventListener("nawafeth:languagechange", refreshLanguage);
    observeLanguageChanges();
    applyStaticCopy();

    var serverAuth = window.NAWAFETH_SERVER_AUTH || null;
    var loggedIn = !!(
      (window.Auth && typeof Auth.isLoggedIn === "function" && Auth.isLoggedIn())
      || (serverAuth && serverAuth.isAuthenticated)
    );
    if (loggedIn && window.Auth && typeof window.Auth.ensureServiceRequestAccess === "function" && !window.Auth.ensureServiceRequestAccess({
      gateId: "auth-gate",
      contentId: "form-content",
      target: window.location.pathname + window.location.search,
      kicker: text("providerGateKicker"),
      title: text("providerGateTitle"),
      description: text("providerGateDescription"),
      note: text("providerGateNote"),
      switchLabel: text("providerGateSwitch"),
      profileLabel: text("providerGateProfile"),
    })) {
      return;
    }
    if (loggedIn) {
      dom.authGate.classList.add("hidden");
      dom.formContent.classList.remove("hidden");
    } else {
      dom.authGate.classList.remove("hidden");
      dom.formContent.classList.add("hidden");
      var next = encodeURIComponent(window.location.href);
      dom.loginLink.href = "/login/?next=" + next;
      return;
    }

    submitOverlay = (window.UI && UI.createSubmitOverlay)
      ? UI.createSubmitOverlay({ title: text("submitOverlayTitle"), message: text("submitOverlayMessage") })
      : null;
    returnTargetUrl = resolveReturnTarget();

    loadDirectTargetContext();
    loadCategories();
    loadRegionCatalog();
    bindEvents();
    syncTypeUI();
    renumberSteps();
  }

  /* ── Cache DOM refs ── */
  function cacheDom() {
    dom.container      = document.querySelector(".sr-container");
    dom.authGate       = el("auth-gate");
    dom.loginLink      = el("sr-login-link");
    dom.formContent    = el("form-content");
    dom.form           = el("sr-form");
    dom.title          = el("sr-title");
    dom.subtitle       = el("sr-subtitle");
    dom.typeBadge      = el("sr-type-badge");
    dom.typeBadgeText  = el("sr-type-badge-text");
    dom.heroPill1      = el("sr-pill-1");
    dom.heroPill2      = el("sr-pill-2");
    dom.heroPill3      = el("sr-pill-3");
    dom.typeNoteTitle  = el("sr-type-note-title");
    dom.typeNoteBody   = el("sr-type-note-body");

    dom.typeSection    = el("sr-type-section");
    dom.typeChips      = el("sr-type-chips");

    dom.scopeSection   = el("sr-scope-section");
    dom.scopeFields    = el("sr-scope-fields");
    dom.fixedTarget    = el("sr-fixed-target");
    dom.category       = el("sr-category");
    dom.subcategory    = el("sr-subcategory");

    dom.scopeTitle     = el("sr-scope-title");
    dom.scopeText      = el("sr-scope-text");
    dom.fixedProvName  = el("sr-fixed-provider-name");
    dom.fixedService   = el("sr-fixed-service");
    dom.fixedServiceRow= el("sr-fixed-service-row");
    dom.fixedCategory  = el("sr-fixed-category");
    dom.fixedSubcat    = el("sr-fixed-subcategory");
    dom.fixedCity      = el("sr-fixed-city");

    dom.dispatchSection = el("sr-dispatch-section");
    dom.dispatchWrap   = el("sr-dispatch-mode-wrap");
    dom.dispatchChips  = el("sr-dispatch-chips");
    dom.cityGroup      = el("sr-city-group");
    dom.region         = el("sr-region");
    dom.city           = el("sr-city");
    dom.cityClear      = el("sr-city-clear");

    dom.selectedProv   = el("sr-selected-provider");
    dom.spAvatar       = el("sr-sp-avatar");
    dom.spName         = el("sr-sp-name");
    dom.spMeta         = el("sr-sp-meta");
    dom.spChange       = el("sr-sp-change");
    dom.spRemove       = el("sr-sp-remove");

    dom.reqTitle       = el("sr-req-title");
    dom.desc           = el("sr-desc");
    dom.deadline       = el("sr-deadline");
    dom.deadlineGroup  = el("sr-deadline-group");
    dom.titleCount     = el("sr-title-count");
    dom.titleCountWrap = el("sr-title-count-wrap");
    dom.descCount      = el("sr-desc-count");
    dom.descCountWrap  = el("sr-desc-count-wrap");

    dom.imagesInput    = el("sr-images");
    dom.videosInput    = el("sr-videos");
    dom.filesInput     = el("sr-files");
    dom.audioBtn       = el("sr-audio-btn");
    dom.audioPreview   = el("sr-audio-preview");
    dom.audioPlayer    = el("sr-audio-player");
    dom.audioRemove    = el("sr-audio-remove");
    dom.attachments    = el("sr-attachments");

    dom.submitBtn      = el("sr-submit");
    dom.submitText     = el("sr-submit-text");
    dom.submitHelper   = el("sr-submit-helper");

    dom.mapModal       = el("sr-map-modal");
    dom.mapBackdrop    = el("sr-map-modal-backdrop");
    dom.mapClose       = el("sr-map-modal-close");
    dom.modalStatus    = el("sr-modal-status");
    dom.modalStatusText= el("sr-modal-status-text");
    dom.modalMap       = el("sr-modal-map");
    dom.modalList      = el("sr-modal-list");
    dom.modalEmpty     = el("sr-modal-empty");

    dom.success        = el("sr-success");
    dom.successTitle   = el("sr-success-title");
    dom.successMsg     = el("sr-success-message");

    dom.toast          = el("sr-toast");
    dom.toastIcon      = el("sr-toast-icon");
    dom.toastTitle     = el("sr-toast-title");
    dom.toastMsg       = el("sr-toast-message");
    dom.toastClose     = el("sr-toast-close");

    dom.catError       = el("sr-category-error");
    dom.subError       = el("sr-subcategory-error");
    dom.cityError      = el("sr-city-error");
    dom.titleError     = el("sr-req-title-error");
    dom.descError      = el("sr-desc-error");
    dom.deadlineError  = el("sr-deadline-error");
  }

  /* ═══════════════════════════════════════
     Load Data
     ═══════════════════════════════════════ */
  async function loadCategories() {
    try {
      var res = await ApiClient.get(API.CATEGORIES);
      if (res.ok && Array.isArray(res.data)) {
        categories = res.data;
        populateCategorySelect();
      }
    } catch (e) {
      console.warn("[SR] loadCategories error:", e);
    }
  }

  function populateCategorySelect() {
    dom.category.innerHTML = '<option value="">' + escHtml(text("categoryPlaceholder")) + '</option>';
    categories.forEach(function (cat) {
      var o = document.createElement("option");
      o.value = cat.id;
      o.textContent = cat.name;
      dom.category.appendChild(o);
    });
    if (fixedTargetCtx && fixedTargetCtx.categoryId) {
      dom.category.value = fixedTargetCtx.categoryId;
      onCategoryChange();
      if (fixedTargetCtx.subcategoryId) {
        dom.subcategory.value = fixedTargetCtx.subcategoryId;
      }
    }
  }

  function onCategoryChange() {
    var catId = parseInt(dom.category.value, 10);
    var cat = categories.find(function (c) { return c.id === catId; });
    var subs = cat ? (cat.subcategories || []) : [];
    dom.subcategory.innerHTML = '<option value="">' + escHtml(text("subcategoryPlaceholder")) + '</option>';
    subs.forEach(function (s) {
      var o = document.createElement("option");
      o.value = s.id;
      o.textContent = s.name;
      dom.subcategory.appendChild(o);
    });
  }

  async function loadRegionCatalog() {
    try {
      var res = await ApiClient.get(API.REGIONS);
      if (res.ok && Array.isArray(res.data)) {
        regionCatalog = UI.normalizeRegionCatalog(res.data);
      } else {
        regionCatalog = UI.getRegionCatalogFallback();
      }
    } catch (e) {
      regionCatalog = UI.getRegionCatalogFallback();
    }
    UI.populateRegionOptions(dom.region, regionCatalog, { placeholder: text("regionPlaceholder") });
    refreshRegionCityOptions();
  }

  /* ═══════════════════════════════════════
     Direct Target Context (from provider page)
     ═══════════════════════════════════════ */
  function loadDirectTargetContext() {
    var params = new URLSearchParams(window.location.search);
    var pid = params.get("provider_id") || params.get("provider");
    var sid = params.get("service_id") || params.get("service");
    if (!pid) return;

    providerId = parseInt(pid, 10) || null;
    serviceId  = sid ? parseInt(sid, 10) : null;

    var rt = params.get("type");
    if (rt === "urgent" || rt === "competitive" || rt === "normal") {
      requestType = rt;
    } else {
      requestType = "normal";
    }

    fetchProviderAndApply();
  }

  function normalizeReturnTarget(raw) {
    if (!raw) return "";
    try {
      var parsed = new URL(String(raw), window.location.origin);
      if (parsed.origin !== window.location.origin) return "";
      var path = String(parsed.pathname || "/").replace(/\/+$/, "") || "/";
      var lowered = path.toLowerCase();
      if (
        lowered === "/service-request" ||
        lowered === "/login" ||
        lowered === "/signup" ||
        lowered === "/twofa"
      ) {
        return "";
      }
      return parsed.pathname + parsed.search + parsed.hash;
    } catch (e) {
      return "";
    }
  }

  function resolveReturnTarget() {
    var params = new URLSearchParams(window.location.search);
    return (
      normalizeReturnTarget(params.get("return_to")) ||
      normalizeReturnTarget(document.referrer) ||
      "/orders/"
    );
  }

  function isDirectRequestFlow() {
    return requestType === "normal" && !!(fixedTargetCtx && fixedTargetCtx.providerId);
  }

  function scheduleReturnToSource() {
    if (returnTimer) {
      clearTimeout(returnTimer);
      returnTimer = null;
    }
    returnTimer = setTimeout(function () {
      window.location.href = returnTargetUrl || "/orders/";
    }, 2200);
  }

  async function fetchProviderAndApply() {
    if (!providerId) return;
    try {
      var res = await ApiClient.get(API.PROVIDERS + "?page_size=1&q=id:" + providerId);
      var prov = null;
      if (res.ok && res.data) {
        var results = res.data.results || res.data;
        prov = Array.isArray(results) ? results.find(function (p) { return p.id === providerId; }) : null;
      }
      if (!prov) {
        var res2 = await ApiClient.get("/api/providers/" + providerId + "/");
        if (res2.ok && res2.data) prov = res2.data;
      }
      if (prov) applyFixedTarget(prov);
    } catch (e) {
      console.warn("[SR] fetchProvider error:", e);
    }
  }

  function applyFixedTarget(prov) {
    fixedTargetCtx = {
      provider: prov,
      providerId: prov.id,
      providerName: prov.display_name || prov.username || ("\u0645\u0632\u0648\u062f #" + prov.id),
      categoryId: null,
      subcategoryId: null,
      city: prov.city_display || prov.city || "",
    };

    if (prov.subcategory_ids && prov.subcategory_ids.length > 0) {
      for (var ci = 0; ci < categories.length; ci++) {
        var cat = categories[ci];
        var subs = cat.subcategories || [];
        for (var si = 0; si < subs.length; si++) {
          if (prov.subcategory_ids.indexOf(subs[si].id) !== -1) {
            fixedTargetCtx.categoryId = cat.id;
            fixedTargetCtx.subcategoryId = subs[si].id;
            fixedTargetCtx.categoryName = cat.name;
            fixedTargetCtx.subcategoryName = subs[si].name;
            break;
          }
        }
        if (fixedTargetCtx.categoryId) break;
      }
    }

    dom.typeSection.classList.add("hidden");
    dom.scopeFields.classList.add("hidden");
    dom.fixedTarget.classList.remove("hidden");
    dom.dispatchSection.classList.add("hidden");
    toggleDirectDesktopLayout(true);

    dom.scopeTitle.textContent = text("directScopeTitle");
    dom.scopeText.textContent = text("directScopeText");
    dom.fixedProvName.textContent = fixedTargetCtx.providerName;

    if (serviceId) {
      dom.fixedService.textContent = text("serviceIdFallback", { id: serviceId });
      dom.fixedServiceRow.style.display = "";
    } else {
      dom.fixedServiceRow.style.display = "none";
    }

    dom.fixedCategory.textContent = fixedTargetCtx.categoryName || "\u2014";
    dom.fixedSubcat.textContent = fixedTargetCtx.subcategoryName || "\u2014";
    dom.fixedCity.textContent = fixedTargetCtx.city || "\u2014";

    if (fixedTargetCtx.categoryId) {
      dom.category.value = fixedTargetCtx.categoryId;
      onCategoryChange();
      if (fixedTargetCtx.subcategoryId) {
        dom.subcategory.value = fixedTargetCtx.subcategoryId;
      }
    }

    updateHeroTypeContent("normal", fixedTargetCtx.providerName);
    dom.submitText.textContent = text("submitDirect");
    dom.submitHelper.textContent = text("submitHelperDirect");

    renumberSteps();
  }

  /* ═══════════════════════════════════════
     Events
     ═══════════════════════════════════════ */
  function bindEvents() {
    // Type chips
    dom.typeChips.addEventListener("click", function (e) {
      var chip = e.target.closest(".sr-chip");
      if (!chip || chip.classList.contains("hidden")) return;
      dom.typeChips.querySelectorAll(".sr-chip").forEach(function (c) { c.classList.remove("active"); });
      chip.classList.add("active");
      requestType = chip.dataset.val;
      syncTypeUI();
    });

    // Category change
    dom.category.addEventListener("change", onCategoryChange);

    // Region change
    dom.region.addEventListener("change", function () {
      var val = dom.region.value;
      UI.populateCityOptions(dom.city, regionCatalog, val, {
        placeholder: text("cityPlaceholder"),
        emptyPlaceholder: text("cityEmptyPlaceholder"),
      });
      dom.cityClear.classList.toggle("hidden", !val);
    });

    // City change
    dom.city.addEventListener("change", function () {
      dom.cityClear.classList.toggle("hidden", !dom.city.value);
    });

    // City clear
    dom.cityClear.addEventListener("click", function () {
      dom.region.value = "";
      dom.city.innerHTML = '<option value="">' + escHtml(text("cityEmptyPlaceholder")) + '</option>';
      dom.city.disabled = true;
      dom.cityClear.classList.add("hidden");
    });

    // Dispatch chips
    dom.dispatchChips.addEventListener("click", function (e) {
      var chip = e.target.closest(".sr-chip");
      if (!chip) return;
      dom.dispatchChips.querySelectorAll(".sr-chip").forEach(function (c) { c.classList.remove("active"); });
      chip.classList.add("active");
      dispatchMode = chip.dataset.dispatch;
      syncDispatchUI();
    });

    // Selected provider actions
    dom.spChange.addEventListener("click", function () { openMapModal(); });
    dom.spRemove.addEventListener("click", function () { clearSelectedProvider(); });

    // Char counts
    dom.reqTitle.addEventListener("input", function () {
      updateCharCount(dom.reqTitle, dom.titleCount, dom.titleCountWrap, 50);
    });
    dom.desc.addEventListener("input", function () {
      updateCharCount(dom.desc, dom.descCount, dom.descCountWrap, 300);
    });

    // File inputs
    dom.imagesInput.addEventListener("change", function () {
      imageFiles = imageFiles.concat(Array.from(dom.imagesInput.files));
      dom.imagesInput.value = "";
      renderAttachments();
    });
    dom.videosInput.addEventListener("change", function () {
      videoFiles = videoFiles.concat(Array.from(dom.videosInput.files));
      dom.videosInput.value = "";
      renderAttachments();
    });
    dom.filesInput.addEventListener("change", function () {
      docFiles = docFiles.concat(Array.from(dom.filesInput.files));
      dom.filesInput.value = "";
      renderAttachments();
    });

    // Audio
    dom.audioBtn.addEventListener("click", toggleAudioRecording);
    dom.audioRemove.addEventListener("click", removeAudio);

    // Submit
    dom.form.addEventListener("submit", function (e) {
      e.preventDefault();
      submit();
    });

    // Toast close
    dom.toastClose.addEventListener("click", hideToast);

    // Map modal close
    dom.mapClose.addEventListener("click", closeMapModal);
    dom.mapBackdrop.addEventListener("click", closeMapModal);
  }

  /* ═══════════════════════════════════════
     Type & Dispatch UI Sync
     ═══════════════════════════════════════ */
  function syncTypeUI() {
    var isCompetitive = requestType === "competitive";
    toggleDirectDesktopLayout(!!fixedTargetCtx && requestType === "normal");

    // Deadline only for competitive
    dom.deadlineGroup.classList.toggle("hidden", !isCompetitive);

    // Dispatch section visible for competitive & urgent (not normal/direct)
    if (!fixedTargetCtx) {
      dom.dispatchSection.classList.toggle("hidden", requestType === "normal");
    }

    applyCurrentTypeCopy();

    syncDispatchUI();
    renumberSteps();
  }

  function toggleDirectDesktopLayout(enabled) {
    if (!dom.container) return;
    dom.container.classList.toggle("sr-direct-layout", !!enabled);
  }

  function syncDispatchUI() {
    var nearestChip = dom.dispatchChips.querySelector('[data-dispatch="nearest"]');
    if (requestType !== "urgent") {
      nearestChip.classList.add("hidden");
      if (dispatchMode === "nearest") {
        dispatchMode = "all";
        dom.dispatchChips.querySelectorAll(".sr-chip").forEach(function (c) { c.classList.remove("active"); });
        dom.dispatchChips.querySelector('[data-dispatch="all"]').classList.add("active");
      }
    } else {
      nearestChip.classList.remove("hidden");
    }

    if (dispatchMode === "nearest" && nearestProvider) {
      showSelectedProviderCard(nearestProvider);
    } else {
      dom.selectedProv.classList.remove("visible");
    }

    if (dispatchMode === "nearest" && !nearestProvider && requestType === "urgent") {
      setTimeout(function () { openMapModal(); }, 250);
    }
  }

  function renumberSteps() {
    var steps = document.querySelectorAll(".sr-section:not(.hidden) .sr-step");
    var n = 1;
    steps.forEach(function (el) { el.textContent = n++; });
  }

  function updateHeroTypeContent(type, providerName) {
    if (!dom.title || !dom.subtitle || !dom.typeBadge || !dom.typeBadgeText) return;

    var nextType = type || requestType || "competitive";
    var badgeText = text("heroCompetitiveBadge");
    var title = text("heroCompetitiveTitle");
    var subtitle = text("heroCompetitiveSubtitle");
    var noteTitle = text("heroCompetitiveNoteTitle");
    var noteBody = text("heroCompetitiveNoteBody");
    var pill1 = text("heroCompetitivePill1");
    var pill2 = text("heroCompetitivePill2");
    var pill3 = text("heroCompetitivePill3");

    if (nextType === "urgent") {
      badgeText = text("heroUrgentBadge");
      title = text("heroUrgentTitle");
      subtitle = text("heroUrgentSubtitle");
      noteTitle = text("heroUrgentNoteTitle");
      noteBody = text("heroUrgentNoteBody");
      pill1 = text("heroUrgentPill1");
      pill2 = text("heroUrgentPill2");
      pill3 = text("heroUrgentPill3");
    } else if (nextType === "normal") {
      var displayName = providerName || (fixedTargetCtx && fixedTargetCtx.providerName) || text("providerFallbackName");
      badgeText = text("heroDirectBadge");
      title = text("heroDirectTitle");
      subtitle = text("heroDirectSubtitle", { provider: displayName });
      noteTitle = text("heroDirectNoteTitle");
      noteBody = text("heroDirectNoteBody");
      pill1 = text("heroDirectPill1");
      pill2 = text("heroDirectPill2");
      pill3 = text("heroDirectPill3");
    }

    dom.typeBadge.dataset.tone = nextType;
    dom.typeBadgeText.textContent = badgeText;
    dom.title.textContent = title;
    dom.subtitle.textContent = subtitle;
    if (dom.typeNoteTitle) dom.typeNoteTitle.textContent = noteTitle;
    if (dom.typeNoteBody) dom.typeNoteBody.textContent = noteBody;
    if (dom.heroPill1) dom.heroPill1.textContent = pill1;
    if (dom.heroPill2) dom.heroPill2.textContent = pill2;
    if (dom.heroPill3) dom.heroPill3.textContent = pill3;
  }

  /* ═══════════════════════════════════════
     Char Count
     ═══════════════════════════════════════ */
  function updateCharCount(input, countEl, wrapEl, max) {
    var len = input.value.length;
    countEl.textContent = len;
    wrapEl.classList.remove("is-warning", "is-limit");
    if (len >= max) wrapEl.classList.add("is-limit");
    else if (len >= max * 0.85) wrapEl.classList.add("is-warning");
  }

  /* ═══════════════════════════════════════
     Attachments Preview
     ═══════════════════════════════════════ */
  function renderAttachments() {
    dom.attachments.innerHTML = "";
    imageFiles.forEach(function (f, i) {
      dom.attachments.appendChild(makeThumb(f, "image", i, imageFiles));
    });
    videoFiles.forEach(function (f, i) {
      dom.attachments.appendChild(makeThumb(f, "video", i, videoFiles));
    });
    docFiles.forEach(function (f, i) {
      dom.attachments.appendChild(makeFileThumb(f, i, docFiles));
    });
  }

  function makeThumb(file, type, idx, arr) {
    var div = document.createElement("div");
    div.className = "sr-attach-item";
    var img = document.createElement("img");
    img.src = URL.createObjectURL(file);
    img.alt = file.name;
    div.appendChild(img);

    var btn = document.createElement("button");
    btn.className = "sr-attach-remove";
    btn.innerHTML = "\u2715";
    btn.type = "button";
    btn.addEventListener("click", function () {
      arr.splice(idx, 1);
      renderAttachments();
    });
    div.appendChild(btn);
    return div;
  }

  function makeFileThumb(file, idx, arr) {
    var div = document.createElement("div");
    div.className = "sr-attach-item file-type";

    var icon = document.createElement("div");
    icon.innerHTML = '<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#64748b" stroke-width="1.5"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/></svg>';
    div.appendChild(icon);

    var span = document.createElement("span");
    span.textContent = file.name;
    div.appendChild(span);

    var btn = document.createElement("button");
    btn.className = "sr-attach-remove";
    btn.innerHTML = "\u2715";
    btn.type = "button";
    btn.addEventListener("click", function () {
      arr.splice(idx, 1);
      renderAttachments();
    });
    div.appendChild(btn);
    return div;
  }

  /* ═══════════════════════════════════════
     Audio Recording
     ═══════════════════════════════════════ */
  async function toggleAudioRecording() {
    if (isRecording) {
      stopRecording();
      return;
    }
    try {
      var stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      audioChunks = [];
      mediaRecorder = new MediaRecorder(stream);
      mediaRecorder.ondataavailable = function (e) {
        if (e.data.size > 0) audioChunks.push(e.data);
      };
      mediaRecorder.onstop = function () {
        stream.getTracks().forEach(function (t) { t.stop(); });
        audioBlob = new Blob(audioChunks, { type: "audio/webm" });
        dom.audioPlayer.src = URL.createObjectURL(audioBlob);
        dom.audioPreview.classList.add("visible");
      };
      mediaRecorder.start();
      isRecording = true;
      dom.audioBtn.classList.add("recording");
      setText("sr-audio-btn-text", text("audioStop"));
    } catch (e) {
      showToast("error", text("toastError"), text("submitUnexpectedError"));
    }
  }

  function findTextNode(el) {
    var nodes = el.childNodes;
    for (var i = 0; i < nodes.length; i++) {
      if (nodes[i].nodeType === 3 && nodes[i].textContent.trim()) return nodes[i];
    }
    return null;
  }

  function stopRecording() {
    if (mediaRecorder && mediaRecorder.state !== "inactive") {
      mediaRecorder.stop();
    }
    isRecording = false;
    dom.audioBtn.classList.remove("recording");
    setText("sr-audio-btn-text", text("audioLabel"));
  }

  function removeAudio() {
    audioBlob = null;
    audioChunks = [];
    dom.audioPlayer.src = "";
    dom.audioPreview.classList.remove("visible");
  }

  /* ═══════════════════════════════════════
     Selected Provider Card
     ═══════════════════════════════════════ */
  function showSelectedProviderCard(prov) {
    nearestProvider = prov;
    dom.spAvatar.src = prov.avatar || prov.profile_image || "";
    dom.spName.textContent = prov.name || prov.display_name || "";
    var parts = [];
    if (prov.rating != null) parts.push("\u2b50 " + Number(prov.rating).toFixed(1));
    if (prov.completed != null) parts.push(text("providerCompleted", { count: prov.completed }));
    dom.spMeta.textContent = parts.join(" \u2022 ");
    dom.selectedProv.classList.add("visible");
  }

  function clearSelectedProvider() {
    nearestProvider = null;
    dom.selectedProv.classList.remove("visible");
  }

  /* ═══════════════════════════════════════
     Map Modal
     ═══════════════════════════════════════ */
  function openMapModal() {
    dom.mapModal.classList.add("open");
    document.body.style.overflow = "hidden";
    dom.modalStatus.style.display = "flex";
    dom.modalStatusText.textContent = text("mapLocating");
    dom.modalList.innerHTML = "";
    dom.modalEmpty.classList.remove("visible");

    if (!leafletMap) {
      leafletMap = L.map(dom.modalMap, {
        center: [24.7136, 46.6753],
        zoom: 11,
        zoomControl: false,
      });
      L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
        attribution: '&copy; <a href="https://www.openstreetmap.org/">OSM</a>',
        maxZoom: 18,
      }).addTo(leafletMap);
    }
    setTimeout(function () { leafletMap.invalidateSize(); }, 350);
    geolocateAndFetch();
  }

  function closeMapModal() {
    dom.mapModal.classList.remove("open");
    document.body.style.overflow = "";
  }

  function normalizeCoordinate(value) {
    var parsed = Number(value);
    if (!Number.isFinite(parsed)) return null;
    return Number(parsed.toFixed(6));
  }

  function geolocateAndFetch() {
    if (!navigator.geolocation) {
      requestLat = 24.7136;
      requestLng = 46.6753;
      dom.modalStatusText.textContent = text("mapUnsupported");
      fetchNearbyProviders(24.7136, 46.6753);
      return;
    }
    navigator.geolocation.getCurrentPosition(
      function (pos) {
        requestLat = normalizeCoordinate(pos.coords.latitude);
        requestLng = normalizeCoordinate(pos.coords.longitude);
        if (requestLat === null || requestLng === null) {
          dom.modalStatusText.textContent = text("mapReadError");
          return;
        }
        dom.modalStatusText.textContent = text("mapSearching");
        leafletMap.setView([requestLat, requestLng], 13);

        if (leafletMarker) leafletMap.removeLayer(leafletMarker);
        leafletMarker = L.marker([requestLat, requestLng], {
          icon: L.divIcon({
            className: "",
            html: '<div style="width:16px;height:16px;border-radius:50%;background:#3b82f6;border:3px solid #fff;box-shadow:0 2px 6px rgba(0,0,0,0.3);"></div>',
            iconSize: [16, 16],
            iconAnchor: [8, 8],
          }),
        }).addTo(leafletMap);

        fetchNearbyProviders(requestLat, requestLng);
      },
      function () {
        requestLat = 24.7136;
        requestLng = 46.6753;
        dom.modalStatusText.textContent = text("mapDenied");
        fetchNearbyProviders(24.7136, 46.6753);
      },
      { enableHighAccuracy: true, timeout: 10000 }
    );
  }

  async function fetchNearbyProviders(lat, lng) {
    var subcatId = dom.subcategory.value;
    var url = API.PROVIDERS + "?has_location=true&accepts_urgent=true&page_size=30";
    if (subcatId) url += "&subcategory_id=" + subcatId;

    try {
      var res = await ApiClient.get(url);
      if (res.ok && res.data) {
        var results = res.data.results || res.data;
        nearbyProviders = Array.isArray(results) ? results : [];
      } else {
        nearbyProviders = [];
      }
    } catch (e) {
      nearbyProviders = [];
    }

    nearbyProviders.forEach(function (p) {
      if (p.lat && p.lng) {
        p._dist = haversineKm(lat, lng, parseFloat(p.lat), parseFloat(p.lng));
      } else {
        p._dist = 9999;
      }
    });
    nearbyProviders.sort(function (a, b) { return a._dist - b._dist; });

    dom.modalStatus.style.display = "none";
    renderProvidersOnMap(lat, lng);
    renderProvidersList();
  }

  function haversineKm(lat1, lon1, lat2, lon2) {
    var R = 6371;
    var dLat = ((lat2 - lat1) * Math.PI) / 180;
    var dLon = ((lon2 - lon1) * Math.PI) / 180;
    var a =
      Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos((lat1 * Math.PI) / 180) * Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLon / 2) * Math.sin(dLon / 2);
    return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  }

  function renderProvidersOnMap(lat, lng) {
    providerMarkers.forEach(function (m) { leafletMap.removeLayer(m); });
    providerMarkers = [];

    nearbyProviders.forEach(function (p) {
      if (!p.lat || !p.lng) return;
      var imgSrc = p.profile_image || "";
      var marker = L.marker([parseFloat(p.lat), parseFloat(p.lng)], {
        icon: L.divIcon({
          className: "sr-map-popup",
          html: '<div style="width:32px;height:32px;border-radius:10px;overflow:hidden;border:2px solid #0f766e;box-shadow:0 2px 8px rgba(0,0,0,0.2);background:#fff;">'
            + '<img src="' + escHtml(imgSrc) + '" style="width:100%;height:100%;object-fit:cover;" onerror="this.style.display=\'none\'" />'
            + '</div>',
          iconSize: [32, 32],
          iconAnchor: [16, 32],
        }),
      }).addTo(leafletMap);

      marker.bindPopup(buildPopupHtml(p), { className: "sr-map-popup", maxWidth: 250 });
      providerMarkers.push(marker);
    });

    if (nearbyProviders.length > 0) {
      var pts = nearbyProviders.filter(function (p) { return p.lat && p.lng; })
        .map(function (p) { return [parseFloat(p.lat), parseFloat(p.lng)]; });
      pts.push([lat, lng]);
      if (pts.length > 1) leafletMap.fitBounds(pts, { padding: [40, 40] });
    }
  }

  function escHtml(str) {
    var d = document.createElement("div");
    d.appendChild(document.createTextNode(str || ""));
    return d.innerHTML;
  }

  function buildPopupHtml(p) {
    var name = escHtml(p.display_name || p.username || "");
    var img = escHtml(p.profile_image || "");
    var rating = p.rating_avg != null ? Number(p.rating_avg).toFixed(1) : "\u2014";
    var completed = p.completed_requests || 0;
    var phone = escHtml(p.phone || "");
    var whatsapp = escHtml(p.whatsapp_url || "");

    var html = '<div class="sr-popup-inner">';
    if (img) html += '<img src="' + img + '" alt="" />';
    html += '<div class="sr-popup-name">' + name + '</div>';
    html += '<div class="sr-popup-stats">\u2b50 ' + rating + ' \u2022 ' + escHtml(text("providerRequests", { count: completed })) + '</div>';
    html += '<div class="sr-popup-actions">';
    if (phone) html += '<a href="tel:' + phone + '" class="sr-prov-action-btn call" onclick="event.stopPropagation()">\ud83d\udcde ' + escHtml(text("popupCall")) + '</a>';
    if (whatsapp) html += '<a href="' + whatsapp + '" target="_blank" rel="noopener" class="sr-prov-action-btn whatsapp" onclick="event.stopPropagation()">\ud83d\udcac ' + escHtml(text("popupWhatsapp")) + '</a>';
    html += '<button class="sr-prov-action-btn send" onclick="window._srSelectProvider(' + p.id + ')">\u2713 ' + escHtml(text("popupChoose")) + '</button>';
    html += '</div></div>';
    return html;
  }

  function renderProvidersList() {
    dom.modalList.innerHTML = "";
    if (nearbyProviders.length === 0) {
      dom.modalEmpty.classList.add("visible");
      return;
    }
    dom.modalEmpty.classList.remove("visible");

    nearbyProviders.forEach(function (p) {
      var card = document.createElement("div");
      card.className = "sr-prov-card";
      card.dataset.id = p.id;
      if (nearestProvider && nearestProvider.id === p.id) card.classList.add("selected");

      var name = escHtml(p.display_name || p.username || "");
      var img = escHtml(p.profile_image || "");
      var rating = p.rating_avg != null ? Number(p.rating_avg).toFixed(1) : "\u2014";
      var completed = p.completed_requests || 0;
      var dist = p._dist < 9999 ? text("providerDistance", { value: p._dist.toFixed(1) }) : "";
      var phone = escHtml(p.phone || "");
      var whatsapp = escHtml(p.whatsapp_url || "");

      var badge = "";
      if (p.is_verified_blue) {
        badge = '<div class="sr-prov-badge blue"><svg viewBox="0 0 24 24" fill="currentColor"><path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z"/></svg></div>';
      } else if (p.is_verified_green) {
        badge = '<div class="sr-prov-badge green"><svg viewBox="0 0 24 24" fill="currentColor"><path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z"/></svg></div>';
      }

      card.innerHTML =
        '<div class="sr-prov-card-avatar-wrap">'
        + '<img class="sr-prov-card-avatar" src="' + img + '" alt="" onerror="this.style.display=\'none\'" />'
        + badge
        + '</div>'
        + '<div class="sr-prov-card-info">'
        + '<div class="sr-prov-card-name">' + name + '</div>'
        + '<div class="sr-prov-card-stats">'
        + '<span><svg viewBox="0 0 24 24" fill="#f59e0b" stroke="none"><path d="M12 2l3.09 6.26L22 9.27l-5 4.87L18.18 22 12 18.56 5.82 22 7 14.14l-5-4.87 6.91-1.01z"/></svg> ' + rating + '</span>'
        + '<span>' + escHtml(text("providerCompleted", { count: completed })) + '</span>'
        + (dist ? '<span>' + dist + '</span>' : '')
        + '</div>'
        + '</div>'
        + '<div class="sr-prov-card-actions">'
        + (phone ? '<a href="tel:' + phone + '" class="sr-prov-action-btn call" onclick="event.stopPropagation()">\ud83d\udcde</a>' : '')
        + (whatsapp ? '<a href="' + whatsapp + '" target="_blank" rel="noopener" class="sr-prov-action-btn whatsapp" onclick="event.stopPropagation()">\ud83d\udcac</a>' : '')
        + '<button class="sr-prov-action-btn send" data-select="' + p.id + '">\u2713 ' + escHtml(text("popupChoose")) + '</button>'
        + '</div>';

      var avatarWrap = card.querySelector(".sr-prov-card-avatar-wrap");
      if (avatarWrap && p.username) {
        avatarWrap.addEventListener("click", function (e) {
          e.stopPropagation();
          window.open("/provider/" + p.username + "/", "_blank");
        });
      }

      var sendBtn = card.querySelector("[data-select]");
      if (sendBtn) {
        sendBtn.addEventListener("click", (function (prov) {
          return function (e) {
            e.stopPropagation();
            selectProviderFromModal(prov);
          };
        })(p));
      }

      dom.modalList.appendChild(card);
    });
  }

  function selectProviderFromModal(p) {
    nearestProvider = {
      id: p.id,
      name: p.display_name || p.username || "",
      avatar: p.profile_image || "",
      rating: p.rating_avg,
      completed: p.completed_requests || 0,
      phone: p.phone || "",
      whatsapp: p.whatsapp_url || "",
    };
    showSelectedProviderCard(nearestProvider);
    closeMapModal();
    showToast("success", text("providerSelectedTitle"), text("providerSelectedMessage", { name: nearestProvider.name }));
  }

  window._srSelectProvider = function (id) {
    var p = nearbyProviders.find(function (pv) { return pv.id === id; });
    if (p) selectProviderFromModal(p);
  };

  /* ═══════════════════════════════════════
     Validation
     ═══════════════════════════════════════ */
  function clearErrors() {
    [dom.catError, dom.subError, dom.cityError, dom.titleError, dom.descError, dom.deadlineError].forEach(function (e) {
      if (e) { e.textContent = ""; e.classList.remove("visible"); }
    });
    [dom.category, dom.subcategory, dom.region, dom.city, dom.reqTitle, dom.desc, dom.deadline].forEach(function (e) {
      if (e) e.classList.remove("is-invalid");
    });
  }

  function showFieldError(elem, errEl, msg) {
    if (elem) elem.classList.add("is-invalid");
    if (errEl) { errEl.textContent = msg; errEl.classList.add("visible"); }
  }

  function validate() {
    clearErrors();
    var ok = true;

    if (!fixedTargetCtx) {
      if (!dom.subcategory.value) {
        if (!dom.category.value) showFieldError(dom.category, dom.catError, text("validationCategory"));
        showFieldError(dom.subcategory, dom.subError, text("validationSubcategory"));
        ok = false;
      }
    }

    var title = dom.reqTitle.value.trim();
    if (!title) {
      showFieldError(dom.reqTitle, dom.titleError, text("validationTitle"));
      ok = false;
    }

    var desc = dom.desc.value.trim();
    if (!desc) {
      showFieldError(dom.desc, dom.descError, text("validationDescription"));
      ok = false;
    }

    if (requestType === "competitive" && dom.deadline.value) {
      var today = new Date().toISOString().slice(0, 10);
      if (dom.deadline.value < today) {
        showFieldError(dom.deadline, dom.deadlineError, text("validationDeadlinePast"));
        ok = false;
      }
    }

    return ok;
  }

  /* ═══════════════════════════════════════
     Submit
     ═══════════════════════════════════════ */
  async function submit() {
    if (isSubmitting) return;
    if (!validate()) return;

    isSubmitting = true;
    holdSuccessState = false;
    dom.submitBtn.disabled = true;
    if (submitOverlay) submitOverlay.show();

    var fd = new FormData();
    fd.append("request_type", requestType);

    var subcatVal = dom.subcategory.value;
    if (subcatVal) {
      fd.append("subcategory", subcatVal);
      fd.append("subcategory_ids", subcatVal);
    } else if (fixedTargetCtx && fixedTargetCtx.subcategoryId) {
      fd.append("subcategory", fixedTargetCtx.subcategoryId);
      fd.append("subcategory_ids", fixedTargetCtx.subcategoryId);
    }

    fd.append("title", dom.reqTitle.value.trim());
    fd.append("description", dom.desc.value.trim());

    var cityVal = getCityValue();
    if (cityVal) fd.append("city", cityVal);

    if (requestType !== "normal") {
      fd.append("dispatch_mode", dispatchMode);
    }

    if (dispatchMode === "nearest" && requestLat != null && requestLng != null) {
      fd.append("request_lat", requestLat.toFixed(6));
      fd.append("request_lng", requestLng.toFixed(6));
    }

    if (requestType === "normal" && fixedTargetCtx && fixedTargetCtx.providerId) {
      fd.append("provider", fixedTargetCtx.providerId);
    } else if (requestType === "urgent" && dispatchMode === "nearest" && nearestProvider) {
      fd.append("provider", nearestProvider.id);
    }

    if (requestType === "competitive" && dom.deadline.value) {
      fd.append("quote_deadline", dom.deadline.value);
    }

    imageFiles.forEach(function (f) { fd.append("images", f); });
    videoFiles.forEach(function (f) { fd.append("videos", f); });
    docFiles.forEach(function (f) { fd.append("files", f); });
    if (audioBlob) fd.append("audio", audioBlob, "voice_recording.webm");

    try {
      var res = await ApiClient.request(API.CREATE, {
        method: "POST",
        body: fd,
        formData: true,
      });
      if (res.ok) {
        onSubmitSuccess(res.data);
      } else {
        onSubmitError(res);
      }
    } catch (e) {
      showToast("error", text("toastError"), text("submitUnexpectedError"));
    } finally {
      isSubmitting = false;
      if (!holdSuccessState) {
        dom.submitBtn.disabled = false;
      }
      if (submitOverlay) submitOverlay.hide();
    }
  }

  function getCityValue() {
    if (fixedTargetCtx && fixedTargetCtx.city) return fixedTargetCtx.city;
    var region = dom.region.value;
    var city = dom.city.value;
    if (!region && !city) return "";
    if (city && region) return UI.formatCityDisplay(city, region);
    if (city) return city;
    return "";
  }

  function onSubmitSuccess(data) {
    if (isDirectRequestFlow()) {
      holdSuccessState = true;
      dom.submitBtn.disabled = true;
      dom.submitText.textContent = text("directSentButton");
      dom.submitHelper.textContent = text("directSentHelper");
      showToast(
        "success",
        text("directSentToastTitle"),
        text("directSentToastMessage", { provider: (fixedTargetCtx && fixedTargetCtx.providerName) || text("providerFallbackName") })
      );
      scheduleReturnToSource();
      return;
    }

    dom.form.style.display = "none";
    dom.success.classList.add("visible");

    if (requestType === "urgent") {
      dom.successTitle.textContent = text("successUrgentTitle");
      dom.successMsg.textContent = text("successUrgentMessage");
    } else if (requestType === "competitive") {
      dom.successTitle.textContent = text("successCompetitiveTitle");
      dom.successMsg.textContent = text("successCompetitiveMessage");
    } else {
      dom.successTitle.textContent = text("successNormalTitle");
      dom.successMsg.textContent = text("successNormalMessage");
    }

    showToast("success", text("successToastTitle"), text("successToastMessage"));
  }

  function onSubmitError(res) {
    var data = res.data || {};
    var status = res.status;

    if (data.subcategory) showFieldError(dom.subcategory, dom.subError, arrayToStr(data.subcategory));
    if (data.subcategory_ids) showFieldError(dom.subcategory, dom.subError, arrayToStr(data.subcategory_ids));
    if (data.city) showFieldError(dom.city, dom.cityError, arrayToStr(data.city));
    if (data.title) showFieldError(dom.reqTitle, dom.titleError, arrayToStr(data.title));
    if (data.description) showFieldError(dom.desc, dom.descError, arrayToStr(data.description));
    if (data.quote_deadline) showFieldError(dom.deadline, dom.deadlineError, arrayToStr(data.quote_deadline));

    var detail = data.detail || data.non_field_errors || data.provider || data.request_lat || data.request_lng;
    if (detail) {
      showToast("error", text("toastError"), arrayToStr(detail));
    } else if (status === 401) {
      showToast("warning", text("sessionExpiredTitle"), text("sessionExpiredMessage"));
    } else {
      showToast("error", text("toastError"), text("submitErrorGeneric"));
    }
  }

  function arrayToStr(val) {
    if (Array.isArray(val)) return val.join(" ");
    return String(val || "");
  }

  /* ═══════════════════════════════════════
     Toast
     ═══════════════════════════════════════ */
  function showToast(type, title, message) {
    hideToast();
    dom.toast.className = "sr-toast " + type;
    dom.toastTitle.textContent = title;
    dom.toastMsg.textContent = message;

    var icons = { success: "\u2713", error: "\u2715", warning: "\u26a0", info: "\u2139" };
    dom.toastIcon.textContent = icons[type] || "\u2139";

    requestAnimationFrame(function () { dom.toast.classList.add("show"); });
    toastTimer = setTimeout(hideToast, 5000);
  }

  function hideToast() {
    if (toastTimer) { clearTimeout(toastTimer); toastTimer = null; }
    dom.toast.classList.remove("show");
  }

  /* ═══════════════════════════════════════
     Module export + init
     ═══════════════════════════════════════ */
  window.ServiceRequestForm = { init: init, _selectProviderFromMap: window._srSelectProvider };
  window.ServiceRequestForm.refreshLanguage = refreshLanguage;

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
