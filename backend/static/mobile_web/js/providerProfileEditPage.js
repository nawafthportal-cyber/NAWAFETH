"use strict";
/* global L */
var ProviderProfileEditPage = (function () {
  var RAW_API = window.ApiClient;
  var API = window.NwApiClient;
  var CITIES = ["الرياض","جدة","مكة المكرمة","المدينة المنورة","الدمام","الخبر","الظهران","الطائف","تبوك","بريدة","عنيزة","حائل","أبها","خميس مشيط","نجران","جازان","ينبع","الباحة","الجبيل","حفر الباطن","القطيف","الأحساء","سكاكا","عرعر","بيشة","الخرج","الدوادمي","المجمعة","القويعية","وادي الدواسر"];
  var REGION_CATALOG = UI && typeof UI.getRegionCatalogFallback === "function"
    ? UI.getRegionCatalogFallback()
    : [];
  var CITY_COORDINATES = {
    "الرياض": [24.7136, 46.6753],
    "جدة": [21.5433, 39.1728],
    "مكة المكرمة": [21.3891, 39.8579],
    "المدينة المنورة": [24.5247, 39.5692],
    "الدمام": [26.4207, 50.0888],
    "الخبر": [26.2172, 50.1971],
    "الظهران": [26.2886, 50.1139],
    "الطائف": [21.2703, 40.4158],
    "تبوك": [28.3998, 36.5715],
    "بريدة": [26.3260, 43.9750],
    "عنيزة": [26.0911, 43.9930],
    "حائل": [27.5114, 41.7208],
    "أبها": [18.2164, 42.5053],
    "خميس مشيط": [18.3008, 42.7290],
    "نجران": [17.5650, 44.2289],
    "جازان": [16.8892, 42.5511],
    "ينبع": [24.0895, 38.0618],
    "الباحة": [20.0129, 41.4677],
    "الجبيل": [27.0174, 49.6225],
    "حفر الباطن": [28.4328, 45.9708],
    "القطيف": [26.5654, 50.0089],
    "الأحساء": [25.3839, 49.5861],
    "سكاكا": [29.9697, 40.2064],
    "عرعر": [30.9753, 41.0381],
    "بيشة": [20.0129, 42.6052],
    "الخرج": [24.1556, 47.3346],
    "الدوادمي": [24.5077, 44.3924],
    "المجمعة": [25.9017, 45.3566],
    "القويعية": [24.0735, 45.2811],
    "وادي الدواسر": [20.4607, 44.7930]
  };
  var DEFAULT_CITY_CENTER = [24.7136, 46.6753];
  var LANGUAGE_PRESETS = [
    { key: "arabic", label: "عربي" },
    { key: "english", label: "انجليزي" },
    { key: "other", label: "لغة أخرى" }
  ];
  var profile = null;
  var userProfile = null;
  var myServices = [];
  var providerProfileRaw = null;
  var sectionCompletionState = { percent: 30, checks: {} };
  var categoryCatalog = [];
  var providerSubcategoryIds = [];
  var providerSelectedSubcategories = [];
  var providerSubcategorySettingsById = {};
  var categoryGroupSequence = 0;
  var initialTab = null;
  var initialFocus = null;
  var initialSection = null;
  var serviceMap = null;
  var serviceMapMarker = null;
  var serviceMapCircle = null;
  var serviceLocationDraft = { lat: null, lng: null };
  var profileLocationMap = null;
  var profileLocationMarker = null;
  var profileLocationDraft = { lat: null, lng: null };
  var profileLocationRequestId = 0;
  var serviceRadiusDraft = 0;
  var SERVICE_RADIUS_MAX_KM = 300;
  var pendingPhoneOtp = { phone: "", active: false };
  var portfolioItems = [];
  var SAUDI_MAJOR_CITY_FALLBACKS = [
    { name: "الرياض", aliases: ["الرياض", "riyadh"], bounds: { minLat: 24.20, maxLat: 25.20, minLng: 46.20, maxLng: 47.30 } },
    { name: "جدة", aliases: ["جدة", "jeddah"], bounds: { minLat: 21.20, maxLat: 21.90, minLng: 38.90, maxLng: 39.50 } },
    { name: "مكة المكرمة", aliases: ["مكة", "مكة المكرمة", "mecca", "makkah"], bounds: { minLat: 21.20, maxLat: 21.70, minLng: 39.50, maxLng: 40.10 } },
    { name: "المدينة المنورة", aliases: ["المدينة", "المدينة المنورة", "medina", "madinah"], bounds: { minLat: 24.20, maxLat: 24.80, minLng: 39.30, maxLng: 39.90 } },
    { name: "الدمام", aliases: ["الدمام", "dammam"], bounds: { minLat: 26.20, maxLat: 26.60, minLng: 49.90, maxLng: 50.30 } },
    { name: "الخبر", aliases: ["الخبر", "khobar", "alkhobar"], bounds: { minLat: 26.20, maxLat: 26.40, minLng: 50.10, maxLng: 50.35 } },
    { name: "الطائف", aliases: ["الطائف", "taif"], bounds: { minLat: 21.10, maxLat: 21.50, minLng: 40.20, maxLng: 40.70 } },
    { name: "أبها", aliases: ["أبها", "ابها", "abha"], bounds: { minLat: 18.10, maxLat: 18.40, minLng: 42.30, maxLng: 42.70 } },
    { name: "تبوك", aliases: ["تبوك", "tabuk"], bounds: { minLat: 28.20, maxLat: 28.60, minLng: 36.30, maxLng: 36.80 } },
    { name: "بريدة", aliases: ["بريدة", "buraydah", "buraidah"], bounds: { minLat: 26.20, maxLat: 26.50, minLng: 43.80, maxLng: 44.20 } },
    { name: "حائل", aliases: ["حائل", "hail", "ha'il"], bounds: { minLat: 27.40, maxLat: 27.70, minLng: 41.50, maxLng: 42.00 } },
    { name: "جازان", aliases: ["جازان", "جيزان", "jazan", "jizan"], bounds: { minLat: 16.70, maxLat: 17.20, minLng: 42.40, maxLng: 43.00 } }
  ];

  var SECTION_TITLES = {
    basic: "البيانات الأساسية",
    service_details: "تفاصيل الخدمة",
    additional: "معلومات إضافية",
    contact_full: "معلومات التواصل",
    lang_loc: "اللغة ونطاق الخدمة",
    content: "محتوى أعمالك",
    seo: "SEO والكلمات المفتاحية"
  };

  var SECTION_CONFIG = {
    basic: {
      tab: "account",
      kicker: "تمت تعبئتها أثناء التسجيل الأولي",
      fields: ["fullName", "accountType", "mobilePhone", "about", "location", "accountEmail"],
      heading: "معلومات الحساب الأساسية",
      intro: "عدّل معلومات الحساب الأساسية من مكان واحد: الاسم، الصفة، رقم الجوال، النبذة، الموقع، والبريد الإلكتروني."
    },
    service_details: {
      tab: "general",
      fields: ["serviceCategories"],
      kicker: "قلب ملفك المهني",
      heading: "تفاصيل الخدمة",
      intro: "أدر الأقسام الرئيسية والتصنيفات الفرعية من مكان واحد، وفعّل استقبال الطلبات العاجلة فقط للتخصصات التي تريدها بدقة."
    },
    additional: {
      tab: "extra",
      fields: ["additionalOverview", "details", "qualification", "experiences"],
      kicker: "وسّع عرض خبرتك",
      heading: "معلومات إضافية",
      intro: "أضف التفاصيل الموسعة والمؤهلات والخبرات العملية حتى يرى العميل قيمة خبرتك بوضوح."
    },
    contact_full: {
      tab: "extra",
      fields: ["phone", "website", "linkedinUrl", "facebookUrl", "youtubeUrl", "instagramUrl", "xUrl", "snapchatUrl", "pinterestUrl", "tiktokUrl", "behanceUrl", "contactEmail", "additionalLinks"],
      kicker: "قنوات الوصول إليك",
      heading: "معلومات التواصل",
      intro: "أكمل وسائل التواصل والروابط التي تساعد العميل على الوصول إليك بسرعة وبصورة مباشرة."
    },
    lang_loc: {
      tab: "general",
      fields: ["languages", "serviceLocation", "coverageRadius"],
      kicker: "التغطية اللغوية والجغرافية",
      heading: "اللغة ونطاق الخدمة",
      intro: "حدد اللغات التي تعمل بها والمنطقة التي تغطيها حتى تظهر خدمتك للعملاء المناسبين في المواقع الصحيحة."
    },
    content: {
      tab: "account",
      mode: "summary",
      kicker: "الصور والمحتوى الظاهر",
      heading: "محتوى أعمالك",
      intro: "راجع ما يظهر حاليًا من صور ومحتوى داخل ملفك العام دون مغادرة صفحة التعديل."
    },
    seo: {
      tab: "extra",
      fields: ["seoPreview", "seoTitle", "seoMetaDescription", "seoSlug", "keywords"],
      kicker: "جاهزية الصفحة للفهرسة",
      heading: "SEO والكلمات المفتاحية",
      intro: "عرّف محركات البحث بنوعية خدمتك عبر العنوان والوصف والرابط المخصص والكلمات المفتاحية، ثم راجع المعاينة قبل الحفظ."
    }
  };

  function currentLang() {
    try {
      if (window.NawafethI18n && typeof window.NawafethI18n.getLanguage === 'function') {
        return window.NawafethI18n.getLanguage() === 'en' ? 'en' : 'ar';
      }
    } catch (_) {}
    return String(document.documentElement.getAttribute('lang') || '').toLowerCase() === 'en' ? 'en' : 'ar';
  }

  function badgeName(badge) {
    if (!badge || typeof badge !== 'object') return '';
    if (currentLang() === 'en') {
      return String(badge.name_en || badge.name || badge.name_ar || badge.code || '').trim();
    }
    return String(badge.name_ar || badge.name || badge.name_en || badge.code || '').trim();
  }

  function badgeFallbackLabel() {
    return currentLang() === 'en' ? 'Excellence Badge' : 'شارة تميز';
  }

  function hasTextValue(value) {
    return typeof value === "string" && value.trim().length > 0;
  }

  function hasNonEmptyListValue(value) {
    if (!Array.isArray(value) || !value.length) return false;
    return value.some(function (item) {
      if (item == null) return false;
      if (typeof item === "string") return item.trim().length > 0;
      if (Array.isArray(item)) return item.length > 0;
      if (typeof item === "object") return Object.keys(item).length > 0;
      return true;
    });
  }

  function toSectionPercent(completion) {
    return Math.max(0, Math.min(100, Math.round(completion * 100)));
  }

  function resolveSectionChecks() {
    var raw = providerProfileRaw || {};
    var socialValues = SOCIAL_FIELD_KEYS.map(function (fieldKey) {
      return profile && profile[fieldKey];
    }).filter(function (item) {
      return hasTextValue(item);
    });
    var socialExtras = Array.isArray(profile && profile.socialExtras) ? profile.socialExtras.filter(Boolean) : [];
    return {
      basic: true,
      service_details: providerSubcategoryIds.length > 0,
      additional: hasTextValue(profile && (profile.details || profile.specialization)) || hasTextValue(profile && profile.qualification) || hasTextValue(profile && profile.experiences),
      contact_full: hasTextValue(raw && raw.whatsapp) || hasTextValue(profile && profile.website) || socialValues.length > 0 || socialExtras.length > 0,
      lang_loc: hasTextValue(profile && profile.languages) && Number(profile && profile.coverageRadius || 0) > 0,
      content: portfolioItems.length > 0 || hasTextValue(raw.profile_image) || hasTextValue(raw.cover_image) || hasNonEmptyListValue(raw.content_sections),
      seo: hasTextValue(profile && profile.keywords) || hasTextValue(profile && profile.seoMetaDescription) || hasTextValue(profile && profile.seoSlug)
    };
  }

  function computeSectionCompletionState() {
    var checks = resolveSectionChecks();
    var doneOptional = [checks.service_details, checks.additional, checks.contact_full, checks.lang_loc, checks.content, checks.seo].filter(Boolean).length;
    sectionCompletionState = {
      checks: checks,
      percent: toSectionPercent(0.30 + (doneOptional * (0.70 / 6)))
    };
  }

  function sectionCheckSvg(done) {
    if (done) {
      return '<svg width="22" height="22" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="10" fill="#4CAF50"/><path d="M9.1 12.3l2 2 4-4" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>';
    }
    return '<svg width="22" height="22" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="10" fill="none" stroke="#c7c7cd" stroke-width="2"/></svg>';
  }

  function badgeCongratsText(badge, issuedOn) {
    var resolvedName = badgeName(badge) || (currentLang() === 'en' ? 'Excellence' : 'التميز');
    if (currentLang() === 'en') {
      return issuedOn
        ? ('Congratulations! You earned the ' + resolvedName + ' badge on ' + issuedOn + ' and it has been published automatically on your profile.')
        : ('Congratulations! You earned the ' + resolvedName + ' badge and it has been published automatically on your profile.');
    }
    return issuedOn
      ? ('تهانينا! حصلت على شارة ' + resolvedName + ' بتاريخ ' + issuedOn + ' وتم نشرها تلقائيًا في ملفك.')
      : ('تهانينا! حصلت على شارة ' + resolvedName + ' وتم نشرها تلقائيًا في ملفك.');
  }

  var SECTION_LINKS = [
    { key: "basic", label: "البيانات الأساسية", summary: "الاسم، صفة الحساب، نبذة", icon: "person", tone: "violet", href: "/provider-profile-edit/?tab=account&focus=fullName&section=basic" },
    { key: "service_details", label: "تفاصيل الخدمة", summary: "الأقسام الرئيسية، الفرعية، والعاجل", icon: "work", tone: "indigo", href: "/provider-profile-edit/?tab=general&focus=serviceCategories&section=service_details" },
    { key: "additional", label: "معلومات إضافية", summary: "تفاصيل موسّعة عن خدماتك ومؤهلاتك", icon: "notes", tone: "teal", href: "/provider-profile-edit/?tab=extra&focus=details&section=additional" },
    { key: "contact_full", label: "معلومات التواصل", summary: "روابط التواصل الاجتماعي، واتساب، موقع", icon: "phone", tone: "blue", href: "/provider-profile-edit/?tab=extra&focus=phone&section=contact_full" },
    { key: "lang_loc", label: "اللغة ونطاق الخدمة", summary: "اللغات التي تجيدها ونطاق تقديم خدماتك", icon: "language", tone: "mint", href: "/provider-profile-edit/?tab=general&focus=coverageRadius&section=lang_loc" },
    { key: "content", label: "محتوى أعمالك", summary: "راجع الصور وأقسام المحتوى داخل نفس الصفحة", icon: "image", tone: "rose", href: "/provider-profile-edit/?section=content" },
    { key: "seo", label: "SEO والكلمات المفتاحية", summary: "تعريف محركات البحث بنوعية خدمتك", icon: "search", tone: "slate", href: "/provider-profile-edit/?tab=extra&focus=seoTitle&section=seo" }
  ];

  var TAB_META = {
    account: {
      label: "معلومات الحساب",
      summary: "حدّث اسم الحساب، صفته، رقم الجوال، النبذة، الموقع، والبريد الإلكتروني من نفس الواجهة."
    },
    general: {
      label: "معلومات عامة",
      summary: "أضف الخبرة، المدينة، اللغات، ونطاق الخدمة مع الموقع الجغرافي عند الحاجة."
    },
    extra: {
      label: "معلومات إضافية",
      summary: "أكمل المؤهلات، الروابط، التفاصيل الموسعة، وعناصر الظهور في البحث ضمن صفحة واحدة واضحة."
    }
  };

  var TAB_WORKFLOW = {
    account: {
      action: "راجع الهوية الأساسية وصياغة النبذة بشكل احترافي.",
      hint: "الاسم والصفة والنبذة هي أول ما يراه العميل، اجعلها دقيقة ومباشرة."
    },
    general: {
      action: "حدد اللغات والموقع ونطاق التغطية بدقة.",
      hint: "اختيار نطاق خدمة واضح يساعد العملاء القريبين منك على الوصول إليك بسرعة."
    },
    extra: {
      action: "أكمل الروابط والمؤهلات لتحسين الثقة والظهور.",
      hint: "المعلومات الإضافية المكتملة ترفع جودة الصفحة وتزيد فرص التواصل الفعال."
    }
  };

  var SECTION_META = {
    basic: {
      label: "البيانات الأساسية",
      summary: "الاسم، صفة الحساب، نبذة"
    },
    service_details: {
      label: "تفاصيل الخدمة",
      summary: "الأقسام الرئيسية والتصنيفات الفرعية مع تفعيل الطلب العاجل لكل تخصص"
    },
    additional: {
      label: "معلومات إضافية",
      summary: "تفاصيل موسّعة عن خدماتك ومؤهلاتك"
    },
    contact_full: {
      label: "معلومات التواصل",
      summary: "روابط التواصل الاجتماعي، واتساب، موقع"
    },
    lang_loc: {
      label: "اللغة ونطاق الخدمة",
      summary: "اللغات التي تجيدها ونطاق تقديم خدماتك"
    },
    content: {
      label: "محتوى أعمالك",
      summary: "الصور وأقسام المحتوى الظاهرة حاليًا في ملفك"
    },
    seo: {
      label: "SEO والكلمات المفتاحية",
      summary: "تعريف محركات البحث بنوعية خدمتك"
    }
  };

  var FIELD_MAP = {
    fullName: "display_name", accountType: "provider_type", about: "bio",
    specialization: "about_details", experience: "years_experience",
    languages: "languages", location: "city", coverageRadius: "coverage_radius_km",
    serviceLocation: "coordinates",
    latitude: "lat", longitude: "lng", details: "about_details",
    qualification: "qualifications", experiences: "experiences", website: "website", social: "social_links",
    linkedinUrl: "social_links", facebookUrl: "social_links", youtubeUrl: "social_links",
    instagramUrl: "social_links", xUrl: "social_links", snapchatUrl: "social_links",
    pinterestUrl: "social_links", tiktokUrl: "social_links", behanceUrl: "social_links",
    contactEmail: "social_links", additionalLinks: "social_links",
    phone: "whatsapp", mobilePhone: "phone", accountEmail: "email", seoTitle: "seo_title", keywords: "seo_keywords", seoMetaDescription: "seo_meta_description", seoSlug: "seo_slug"
  };

  var TYPE_LABELS = { individual: "فرد", company: "منشأة", freelancer: "فرد" };

  var SOCIAL_FIELDS = [
    { key: "linkedinUrl", platform: "linkedin", label: "لينكدإن", icon: "linkedin", hint: "أدخل رابط الحساب أو اسم المستخدم على لينكدإن.", inputType: "url", inputMode: "url", placeholder: "https://www.linkedin.com/in/username", dir: "ltr", autocomplete: "url" },
    { key: "facebookUrl", platform: "facebook", label: "منصة فيس بوك", icon: "facebook", hint: "أدخل رابط الصفحة أو اسم المستخدم على فيس بوك.", inputType: "url", inputMode: "url", placeholder: "https://facebook.com/username", dir: "ltr", autocomplete: "url" },
    { key: "youtubeUrl", platform: "youtube", label: "يوتيوب", icon: "youtube", hint: "أدخل رابط القناة أو اسم المستخدم على يوتيوب.", inputType: "url", inputMode: "url", placeholder: "https://www.youtube.com/@channel", dir: "ltr", autocomplete: "url" },
    { key: "instagramUrl", platform: "instagram", label: "انستقرام", icon: "instagram", hint: "أدخل رابط الحساب أو اسم المستخدم على انستقرام.", inputType: "url", inputMode: "url", placeholder: "https://instagram.com/username", dir: "ltr", autocomplete: "url" },
    { key: "xUrl", platform: "x", label: "منصة X", icon: "x", hint: "أدخل رابط الحساب أو اسم المستخدم على منصة X.", inputType: "url", inputMode: "url", placeholder: "https://x.com/username", dir: "ltr", autocomplete: "url" },
    { key: "snapchatUrl", platform: "snapchat", label: "سناب شات", icon: "snapchat", hint: "أدخل رابط الحساب أو اسم المستخدم على سناب شات.", inputType: "url", inputMode: "url", placeholder: "https://snapchat.com/add/username", dir: "ltr", autocomplete: "url" },
    { key: "pinterestUrl", platform: "pinterest", label: "بنترست", icon: "pinterest", hint: "أدخل رابط الحساب أو اسم المستخدم على بنترست.", inputType: "url", inputMode: "url", placeholder: "https://www.pinterest.com/username", dir: "ltr", autocomplete: "url" },
    { key: "tiktokUrl", platform: "tiktok", label: "منصة تيك توك", icon: "tiktok", hint: "أدخل رابط الحساب أو اسم المستخدم على تيك توك.", inputType: "url", inputMode: "url", placeholder: "https://tiktok.com/@username", dir: "ltr", autocomplete: "url" },
    { key: "behanceUrl", platform: "behance", label: "بيهانس", icon: "behance", hint: "أدخل رابط الحساب أو اسم المستخدم على بيهانس.", inputType: "url", inputMode: "url", placeholder: "https://www.behance.net/username", dir: "ltr", autocomplete: "url" },
    { key: "contactEmail", platform: "email", label: "بريد التواصل", icon: "email", hint: "بريد التواصل الذي ترغب بإظهاره للعملاء داخل الملف العام.", inputType: "email", inputMode: "email", placeholder: "name@example.com", dir: "ltr", autocomplete: "email" }
  ];
  var SOCIAL_FIELD_KEYS = SOCIAL_FIELDS.map(function (field) { return field.key; });
  var SOCIAL_FIELD_PLATFORMS = SOCIAL_FIELDS.reduce(function (map, field) {
    map[field.key] = field.platform;
    return map;
  }, {});
  var SOCIAL_PLATFORM_LABELS = SOCIAL_FIELDS.reduce(function (map, field) {
    map[field.platform] = field.label;
    return map;
  }, {});

  var TABS = {
    account: [
      { key: "fullName", label: "اسم الحساب", icon: "person", hint: "الاسم الذي سيظهر للعملاء داخل الملف التعريفي.", wide: true },
      { key: "accountType", label: "صفة الحساب", icon: "badge", hint: "اختر الصفة المناسبة كما ستظهر داخل الملف التعريفي.", isChoice: true, options: [
        { value: "individual", label: "فرد" },
        { value: "company", label: "منشأة" }
      ] },
      { key: "mobilePhone", label: "رقم الجوال", icon: "phone", hint: "رقم الجوال الأساسي المرتبط بحسابك ويمكن تحديثه من هنا بعد التحقق برمز OTP." },
      { key: "about", label: "نبذة عنك", icon: "info", hint: "تعريف مختصر بك أو بجهتك كما يراه العميل.", multiline: true, wide: true },
      { key: "location", label: "الدولة - المدينة", icon: "location", hint: "حدّد النقطة على الخريطة وسنعبئ الدولة والمدينة تلقائيًا، مع إمكانية تعديل المدينة يدويًا قبل الحفظ.", isCity: true, wide: true },
      { key: "accountEmail", label: "البريد الإلكتروني", icon: "email", hint: "البريد الإلكتروني الأساسي المرتبط بحسابك ويمكن تحديثه من هنا.", inputType: "email", inputMode: "email", placeholder: "name@example.com", dir: "ltr", autocomplete: "email" }
    ],
    general: [
      { key: "experience", label: "سنوات الخبرة", icon: "work", hint: "أدخل رقمًا تقريبيًا يوضح خبرتك في المجال." },
      { key: "serviceCategories", label: "الأقسام والتصنيفات الفرعية", icon: "category", hint: "اختر قسمًا رئيسيًا واحدًا في كل بطاقة، ويمكنك اختيار أكثر من تصنيف فرعي داخل كل قسم مع تفعيل الطلب العاجل من أيقونة البرق بجانبه.", categoryPickerField: true, wide: true },
      { key: "languages", label: "لغات التواصل", icon: "language", hint: "اختر اللغات التي تتواصل بها مع العملاء.", languageField: true, wide: true },
      { key: "specialization", label: "تفاصيل إضافية", icon: "category", hint: "أضف وصفًا أوسع عن مجالك أو طريقة عملك.", multiline: true, wide: true },
      { key: "serviceLocation", label: "الموقع", icon: "map_pin", hint: "اضغط على الخريطة أو اسحب المؤشر لتحديد موقعك الدقيق داخل المدينة المختارة.", mapField: true, wide: true },
      { key: "coverageRadius", label: "نطاق الخدمة", icon: "radius", hint: "اختر نصف قطر التغطية بالكيلومتر وسيظهر كنطاق دائري حول موقعك.", radiusField: true, wide: true, inputType: "number", inputMode: "numeric", min: "0", max: String(SERVICE_RADIUS_MAX_KM), step: "1", placeholder: "مثال: 2" }
    ],
    extra: [
      { key: "additionalOverview", label: "ملخص القسم", icon: "notes", readOnly: true, wide: true, additionalOverviewField: true },
      { key: "details", label: "شرح تفصيلي", icon: "notes", hint: "قدّم وصفًا أوسع للخدمات أو أسلوب العمل أو التخصص.", multiline: true, wide: true },
      { key: "qualification", label: "المؤهلات", icon: "school", hint: "افصل بين المؤهلات بفاصلة عند إدخال أكثر من عنصر.", wide: true },
      { key: "experiences", label: "الخبرات العملية", icon: "work", hint: "أضف خبراتك أو المشاريع المنجزة، ويفضل كتابة كل عنصر في سطر مستقل.", multiline: true, wide: true },
      { key: "website", label: "الموقع الإلكتروني", icon: "link", hint: "أدخل الرابط الكامل إذا كان لديك موقع أو صفحة تعريفية.", inputType: "url", inputMode: "url", placeholder: "https://example.com", dir: "ltr", autocomplete: "url" },
    ].concat(SOCIAL_FIELDS).concat([
      { key: "additionalLinks", label: "روابط إضافية", icon: "share", hint: "أضف روابط أخرى لمواقع أو منصات غير موجودة ضمن الحقول الثابتة، ويمكنك كتابة اسم مخصص لكل رابط.", wide: true, additionalLinksField: true },
      { key: "phone", label: "واتساب التواصل", icon: "phone", hint: "رقم واتساب الذي ترغب بإظهاره للعملاء داخل الملف العام.", inputType: "tel", inputMode: "numeric", maxLength: "10", placeholder: "05XXXXXXXX" },
      { key: "seoPreview", label: "معاينة النتيجة", icon: "search", readOnly: true, wide: true, seoPreviewField: true },
      { key: "seoTitle", label: "عنوان SEO", icon: "headline", hint: "العنوان الذي سيظهر في نتائج البحث وعند مشاركة الصفحة. يفضّل أن يكون واضحًا ومباشرًا.", wide: true, inputType: "text", maxLength: "160", placeholder: "مثال: مصمم واجهات وتجارب رقمية في الرياض", seoMetric: "title" },
      { key: "seoMetaDescription", label: "وصف الصفحة (Meta Description)", icon: "notes", hint: "وصف مختصر يشرح طبيعة الخدمة ويزيد من قابلية النقر من نتائج البحث.", multiline: true, wide: true, maxLength: "320", placeholder: "مثال: أقدّم تصميم واجهات وتجارب رقمية للمتاجر والمواقع مع تركيز على السرعة والتحويل.", seoMetric: "description" },
      { key: "seoSlug", label: "الرابط المخصص", icon: "link", hint: "جزء الرابط الذي يسهّل قراءة الصفحة. استخدم كلمات قصيرة وواضحة.", dir: "ltr", autocomplete: "off", maxLength: "150", placeholder: "designer-riyadh", seoMetric: "slug" },
      { key: "keywords", label: "الكلمات المفتاحية", icon: "label", hint: "اكتب كلمات أو عبارات قصيرة تفصل بينها فاصلة أو سطر جديد، مثل: تصميم واجهات، تجربة مستخدم، مواقع أعمال.", multiline: true, wide: true, maxLength: "500", placeholder: "تصميم واجهات، تجربة مستخدم، مواقع أعمال", seoMetric: "keywords" }
    ])
  };
  var FIELD_CONFIG = {};
  Object.keys(TABS).forEach(function (tabName) {
    TABS[tabName].forEach(function (field) {
      FIELD_CONFIG[field.key] = field;
    });
  });

  function init() {
    parseEntryQuery();
    applyEntryHeader();
    bindTabs();
    bindAvatarUpload();
    loadProfile();
  }

  function parseEntryQuery() {
    var params = new URLSearchParams(window.location.search || "");
    var tab = (params.get("tab") || "").trim();
    var focus = (params.get("focus") || "").trim();
    var section = (params.get("section") || "").trim();
    if (focus === "social") focus = "xUrl";
    if (focus === "latitude" || focus === "longitude") focus = "serviceLocation";
    if (tab && TABS[tab]) initialTab = tab;
    if (focus && FIELD_MAP[focus]) initialFocus = focus;
    if (section && SECTION_TITLES[section]) initialSection = section;
  }

  function applyEntryHeader() {
    if (!initialSection) return;
    var title = document.getElementById("pe-page-title");
    if (!title) return;
    title.textContent = SECTION_TITLES[initialSection] || "الملف الشخصي";
  }

  function escapeHtml(value) {
    return String(value || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  function fieldConfig(key) {
    return FIELD_CONFIG[key] || {};
  }

  function extractList(payload) {
    if (Array.isArray(payload)) return payload;
    if (payload && Array.isArray(payload.results)) return payload.results;
    return [];
  }

  function normalizeListEntry(item, keys) {
    if (item === null || item === undefined) return "";
    if (typeof item === "string") return item.trim();
    if (typeof item === "number") return String(item);
    if (typeof item === "object") {
      var candidateKeys = Array.isArray(keys) ? keys : [];
      for (var i = 0; i < candidateKeys.length; i++) {
        var key = candidateKeys[i];
        if (item[key] !== null && item[key] !== undefined && String(item[key]).trim()) {
          return String(item[key]).trim();
        }
      }
      var firstKey = Object.keys(item)[0];
      if (firstKey && item[firstKey] !== null && item[firstKey] !== undefined) {
        return String(item[firstKey]).trim();
      }
    }
    return "";
  }

  function splitEntries(value) {
    return String(value || "")
      .split(/\n|،|,/)
      .map(function (part) { return part.trim(); })
      .filter(Boolean);
  }

  function additionalEntries(value) {
    return uniqueNonEmpty(splitEntries(value));
  }

  function countWords(value) {
    var text = String(value || "").trim();
    return text ? text.split(/\s+/).filter(Boolean).length : 0;
  }

  function additionalOverviewState() {
    var detailsText = String(profile && profile.details || "").trim();
    var qualifications = additionalEntries(profile && profile.qualification);
    var experiences = additionalEntries(profile && profile.experiences);
    return {
      detailsText: detailsText,
      detailsWords: countWords(detailsText),
      qualificationCount: qualifications.length,
      experienceCount: experiences.length,
      qualifications: qualifications,
      experiences: experiences
    };
  }

  function additionalOverviewStatus(count, singularLabel, pluralLabel) {
    if (!count) {
      return {
        tone: "empty",
        metric: "غير مكتمل",
        description: "لم تتم إضافة " + singularLabel + " بعد."
      };
    }
    return {
      tone: "ready",
      metric: count + " " + (count === 1 ? singularLabel : pluralLabel),
      description: "تمت إضافة " + (count === 1 ? singularLabel : pluralLabel) + " ويمكنك مراجعتها أو تطويرها أدناه."
    };
  }

  function renderAdditionalTags(items, tone) {
    if (!items.length) return '<span class="pe-empty-value">لم تتم إضافة عناصر بعد</span>';
    return items.map(function (item) {
      return '<span class="pe-additional-tag pe-additional-tag--' + escapeHtml(tone) + '">' + escapeHtml(item) + '</span>';
    }).join('');
  }

  function renderAdditionalList(items, emptyText) {
    if (!items.length) return '<span class="pe-empty-value">' + escapeHtml(emptyText) + '</span>';
    return '<div class="pe-additional-list">' + items.map(function (item, index) {
      return '<div class="pe-additional-list-item"><span class="pe-additional-list-index">' + String(index + 1) + '</span><span class="pe-additional-list-copy">' + escapeHtml(item) + '</span></div>';
    }).join('') + '</div>';
  }

  function renderAdditionalOverviewBody() {
    var state = additionalOverviewState();
    var storyStatus = state.detailsWords > 0
      ? {
          tone: "ready",
          metric: state.detailsWords + " كلمة",
          description: "تمت إضافة نبذة موسعة ويمكنك تحسين الصياغة أو تعميق التفاصيل من البطاقة التالية."
        }
      : {
          tone: "empty",
          metric: "غير مكتمل",
          description: "أضف شرحًا يوضح أسلوبك وقيمة خدمتك قبل أن يراه العميل."
        };
    var qualificationStatus = additionalOverviewStatus(state.qualificationCount, "مؤهل", "مؤهلات");
    var experienceStatus = additionalOverviewStatus(state.experienceCount, "خبرة", "خبرات");
    return '<div class="pe-additional-overview-grid">' +
      '<section class="pe-additional-overview-card pe-additional-overview-card--story">' +
        '<div class="pe-additional-overview-head"><strong>الشرح التفصيلي</strong><span class="pe-additional-overview-metric is-' + storyStatus.tone + '">' + storyStatus.metric + '</span></div>' +
        '<p>هذا الحقل يشرح للعميل كيف تعمل وما الذي يميزك عن غيرك.</p>' +
        '<div class="pe-additional-overview-note">' + escapeHtml(storyStatus.description) + '</div>' +
      '</section>' +
      '<section class="pe-additional-overview-card pe-additional-overview-card--qualifications">' +
        '<div class="pe-additional-overview-head"><strong>المؤهلات</strong><span class="pe-additional-overview-metric is-' + qualificationStatus.tone + '">' + qualificationStatus.metric + '</span></div>' +
        '<p>أضف الشهادات والدورات والاعتمادات التي ترفع الثقة في ملفك.</p>' +
        '<div class="pe-additional-overview-note">' + escapeHtml(qualificationStatus.description) + '</div>' +
      '</section>' +
      '<section class="pe-additional-overview-card pe-additional-overview-card--experience">' +
        '<div class="pe-additional-overview-head"><strong>الخبرات العملية</strong><span class="pe-additional-overview-metric is-' + experienceStatus.tone + '">' + experienceStatus.metric + '</span></div>' +
        '<p>هذا الجزء يعطي العميل أمثلة سريعة على أعمالك أو خبراتك السابقة.</p>' +
        '<div class="pe-additional-overview-note">' + escapeHtml(experienceStatus.description) + '</div>' +
      '</section>' +
    '</div>';
  }


  function buildLangLocOverviewField(f) {
    return '<article class="pe-field pe-field-wide pe-langloc-overview-field" data-key="' + f.key + '">' +
      '<div class="pe-field-head">' +
        '<div class="pe-field-title-wrap">' +
          '<span class="pe-field-icon" aria-hidden="true">' + iconSvg(f.icon) + '</span>' +
          '<div class="pe-field-copy">' +
            '<span class="pe-field-label">مشهد التغطية</span>' +
            '<span class="pe-field-hint">عرض سريع يربط اللغات ونقطة الخدمة ونصف القطر في صورة واحدة قبل التعديل التفصيلي.</span>' +
          '</div>' +
        '</div>' +
      '</div>' +
      '<div class="pe-langloc-overview-body" id="pe-langloc-overview-body">' + renderLangLocOverviewBody() + '</div>' +
    '</article>';
  }
  function refreshAdditionalOverview() {
    var container = document.getElementById('pe-additional-overview-body');
    if (container) container.innerHTML = renderAdditionalOverviewBody();
  }

  function currentLanguagePreviewState() {
    var languageField = document.querySelector('.pe-language-field');
    if (!languageField) {
      return {
        arabic: !!(profile && profile.languageArabic),
        english: !!(profile && profile.languageEnglish),
        other: !!(profile && profile.languageOther),
        otherText: String(profile && profile.languageOtherText || '').trim()
      };
    }
    return collectLanguageStateFromDom();
  }

  function languagePreviewEntries() {
    var state = currentLanguagePreviewState();
    var values = [];
    if (state.arabic) values.push('عربي');
    if (state.english) values.push('انجليزي');
    if (state.other) {
      splitEntries(state.otherText).forEach(function (entry) {
        values.push(entry);
      });
    }
    return uniqueNonEmpty(values);
  }

  function serviceLocationPreviewLabel() {
    return String((profile && profile.location) || '').trim() || 'غير محدد بعد';
  }

  function serviceLocationPreviewCoords() {
    var lat = Number.isFinite(Number(serviceLocationDraft.lat)) ? serviceLocationDraft.lat : normalizeCoordinateValue(profile && profile.latitude);
    var lng = Number.isFinite(Number(serviceLocationDraft.lng)) ? serviceLocationDraft.lng : normalizeCoordinateValue(profile && profile.longitude);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) return 'لم يتم تحديد نقطة دقيقة بعد';
    return lat.toFixed(5) + ' ، ' + lng.toFixed(5);
  }

  function renderLanguagePreviewTags(items) {
    if (!items.length) return '<span class="pe-empty-value">لم يتم اختيار لغات بعد</span>';
    return items.map(function (item) {
      return '<span class="pe-langloc-tag pe-langloc-tag--language">' + escapeHtml(item) + '</span>';
    }).join('');
  }

  function renderLangLocOverviewBody() {
    var languageEntries = languagePreviewEntries();
    var geoSummary = getGeoScopeSummaryData();
    var radius = getServiceRadiusKm();
    var locationReady = String(serviceLocationPreviewLabel() || '').trim() !== 'غير محدد بعد';
    return '<div class="pe-langloc-hero">' +
      '<div class="pe-langloc-hero-copy">' +
        '<strong>صغ تغطيتك بدقة</strong>' +
        '<span>هذا القسم يحدد كيف يراك العميل: بأي لغة، وفي أي منطقة، وما إذا كانت التصنيفات التي اخترتها محلية أو عن بُعد وفق سياسة المنصة.</span>' +
      '</div>' +
      '<div class="pe-langloc-hero-stats">' +
        '<span class="pe-langloc-stat"><strong>' + languageEntries.length + '</strong><em>لغة</em></span>' +
        '<span class="pe-langloc-stat"><strong>' + geoSummary.localNames.length + '</strong><em>محلي</em></span>' +
        '<span class="pe-langloc-stat"><strong>' + geoSummary.remoteNames.length + '</strong><em>عن بُعد</em></span>' +
      '</div>' +
    '</div>' +
    '<div class="pe-langloc-overview-grid">' +
      '<section class="pe-langloc-card pe-langloc-card--language">' +
        '<div class="pe-langloc-card-head"><strong>اللغات الفعالة</strong><span>' + (languageEntries.length ? 'جاهز' : 'بحاجة ضبط') + '</span></div>' +
        '<p>اختر اللغات التي تتواصل بها فعليًا حتى تظهر للعملاء المناسبين.</p>' +
        '<div class="pe-langloc-tags">' + renderLanguagePreviewTags(languageEntries) + '</div>' +
      '</section>' +
      '<section class="pe-langloc-card pe-langloc-card--location">' +
        '<div class="pe-langloc-card-head"><strong>نقطة الخدمة</strong><span>' + (locationReady ? 'محددة' : 'غير مكتملة') + '</span></div>' +
        '<p>الموقع الأساسي الذي تُبنى عليه دائرة التغطية للخدمات المحلية.</p>' +
        '<div class="pe-langloc-location-summary">' +
          '<strong>' + escapeHtml(serviceLocationPreviewLabel()) + '</strong>' +
          '<span>' + escapeHtml(serviceLocationPreviewCoords()) + '</span>' +
        '</div>' +
      '</section>' +
      '<section class="pe-langloc-card pe-langloc-card--radius">' +
        '<div class="pe-langloc-card-head"><strong>نطاق الخدمة</strong><span>' + radius + ' كم</span></div>' +
        '<p>نصف القطر يطبّق على الخدمات المحلية فقط حسب سياسة التصنيف، بينما الخدمات عن بُعد لا تتأثر به.</p>' +
        '<div class="pe-langloc-scope-mini">' +
          '<span class="pe-langloc-tag pe-langloc-tag--local">محلي: ' + geoSummary.localNames.length + '</span>' +
          '<span class="pe-langloc-tag pe-langloc-tag--remote">عن بُعد: ' + geoSummary.remoteNames.length + '</span>' +
        '</div>' +
      '</section>' +
    '</div>';
  }

  function refreshLangLocOverview() {
    var container = document.getElementById('pe-langloc-overview-body');
    if (container) container.innerHTML = renderLangLocOverviewBody();
  }

  function normalizeLanguageLabel(value) {
    var text = String(value || "").trim();
    if (!text) return "";
    var lower = text.toLowerCase();
    if (lower === "arabic" || lower === "ar" || text === "عربي" || text === "العربية" || text === "عربيه") return "عربي";
    if (lower === "english" || lower === "en" || text === "انجليزي" || text === "الإنجليزية" || text === "الانجليزية") return "انجليزي";
    return text;
  }

  function extractLanguageState(items) {
    var values = [];
    (Array.isArray(items) ? items : []).forEach(function (item) {
      var raw = normalizeListEntry(item, ["name", "label", "title", "value"]);
      var normalized = normalizeLanguageLabel(raw);
      if (normalized) values.push(normalized);
    });

    var unique = uniqueNonEmpty(values);
    var hasArabic = unique.indexOf("عربي") >= 0;
    var hasEnglish = unique.indexOf("انجليزي") >= 0;
    var others = unique.filter(function (entry) {
      return entry !== "عربي" && entry !== "انجليزي";
    });

    return {
      arabic: hasArabic,
      english: hasEnglish,
      other: others.length > 0,
      otherText: others.join("، "),
      display: unique.join("، ")
    };
  }

  function collectLanguageStateFromDom() {
    var arabic = !!document.getElementById("pe-language-arabic") && document.getElementById("pe-language-arabic").checked;
    var english = !!document.getElementById("pe-language-english") && document.getElementById("pe-language-english").checked;
    var other = !!document.getElementById("pe-language-other") && document.getElementById("pe-language-other").checked;
    var otherInput = document.getElementById("pe-language-other-input");
    return {
      arabic: arabic,
      english: english,
      other: other,
      otherText: otherInput ? String(otherInput.value || "").trim() : ""
    };
  }

  function buildLanguagesPayload(state) {
    var items = [];
    if (state.arabic) items.push({ name: "عربي" });
    if (state.english) items.push({ name: "انجليزي" });
    if (state.other) {
      splitEntries(state.otherText).forEach(function (entry) {
        items.push({ name: entry });
      });
    }
    return items;
  }

  function formatLanguagesDisplay(state) {
    var parts = [];
    if (state.arabic) parts.push("عربي");
    if (state.english) parts.push("انجليزي");
    if (state.other) {
      splitEntries(state.otherText).forEach(function (entry) {
        parts.push(entry);
      });
    }
    return uniqueNonEmpty(parts).join("، ");
  }

  function hasPreciseCoordinates() {
    return Number.isFinite(Number(profile && profile.latitude)) && Number.isFinite(Number(profile && profile.longitude));
  }

  function splitLocationScope(value, region) {
    var scope = UI && typeof UI.splitCityScope === "function"
      ? UI.splitCityScope(value)
      : { region: "", city: String(value || "").trim() };
    var city = String((scope && scope.city) || value || "").trim();
    var resolvedRegion = String(region || (scope && scope.region) || "").trim();
    if (!resolvedRegion && UI && typeof UI.inferRegionByCity === "function") {
      var inferred = UI.inferRegionByCity(city);
      resolvedRegion = inferred && inferred.nameAr ? inferred.nameAr : "";
    }
    return { region: resolvedRegion, city: city };
  }

  function formatLocationDisplay(city, region) {
    if (UI && typeof UI.formatCityDisplay === "function") {
      return UI.formatCityDisplay(city, region);
    }
    return String(city || "").trim();
  }

  function buildProfileLocationLabel(country, city) {
    var countryText = String(country || "").trim();
    var cityText = String(city || "").trim();
    if (countryText && cityText) return countryText + " - " + cityText;
    return countryText || cityText;
  }

  function cleanAddressPart(value) {
    return typeof value === "string" ? value.trim().replace(/\s+/g, " ") : "";
  }

  function normalizeGeoLabel(value) {
    return String(value || "")
      .trim()
      .replace(/^المملكة العربية السعودية[\s،,-]*/i, "")
      .replace(/^country\s+/i, "")
      .replace(/\s+/g, " ")
      .toLowerCase();
  }

  function buildLocationFieldEditor() {
    return '<div class="pe-location-editor-shell">' +
      '<div class="pe-location-overview">' +
        '<div class="pe-location-pill">' +
          '<span class="pe-location-pill-label">الدولة</span>' +
          '<strong class="pe-location-pill-value" id="pe-location-country-label">' + escapeHtml(profile.locationCountry || 'غير محددة') + '</strong>' +
        '</div>' +
        '<div class="pe-location-pill">' +
          '<span class="pe-location-pill-label">المدينة</span>' +
          '<strong class="pe-location-pill-value" id="pe-location-city-label">' + escapeHtml(profile.locationCity || 'غير محددة') + '</strong>' +
        '</div>' +
      '</div>' +
      '<div class="pe-location-caption">اختر نقطة واحدة تمثل موقعك الأساسي. هذه النقطة تُستخدم فقط للخدمات المحلية التي فعّلت لها النطاق الجغرافي.</div>' +
      '<div class="pe-geo-scope-explainer" id="pe-location-scope-summary"></div>' +
      '<div class="pe-profile-location-map" id="pe-profile-location-map"></div>' +
      '<div class="pe-location-editor-meta">' +
        '<span class="pe-location-status" id="pe-location-status">اختر نقطة من الخريطة أو استخدم موقعك الحالي.</span>' +
        '<span class="pe-location-coords" id="pe-location-coords">لم يتم اختيار نقطة بعد.</span>' +
      '</div>' +
      '<div class="pe-location-inputs">' +
        '<div class="form-group">' +
          '<label class="form-label">الدولة</label>' +
          '<input type="text" class="form-input pe-location-country-input" value="' + escapeHtml(profile.locationCountry || '') + '" readonly>' +
        '</div>' +
        '<div class="form-group">' +
          '<label class="form-label">المدينة</label>' +
          '<input type="text" class="form-input pe-input pe-location-city-input" data-key="location" value="' + escapeHtml(profile.locationCity || '') + '" placeholder="يمكنك تعديل المدينة يدويًا إذا لزم الأمر">' +
        '</div>' +
      '</div>' +
      '<p class="pe-location-city-hint" id="pe-location-city-hint">إذا لم تُقرأ مدينة دقيقة، يمكنك تعديلها يدويًا قبل الحفظ.</p>' +
      '<button type="button" class="btn btn-secondary pe-location-use-current-btn">استخدام موقعي الحالي</button>' +
    '</div>';
  }

  function looksLikeNeighborhoodLabel(value) {
    var normalized = normalizeGeoLabel(value);
    return /^حي(?:\s|$)/.test(normalized) || /neighbou?rhood/.test(normalized);
  }

  function isSaudiCountry(value) {
    var normalized = String(value || "").trim().toLowerCase();
    return normalized.indexOf("السعودية") >= 0 || normalized.indexOf("saudi") >= 0;
  }

  function resolveCountryFromAddress(address) {
    var country = cleanAddressPart((address && address.country) || (address && address.country_code) || "");
    if (normalizeGeoLabel(country) === "السعودية") return "المملكة العربية السعودية";
    return country;
  }

  function resolveSaudiMajorCity(address, lat, lng) {
    var tokens = [
      address && address.city,
      address && address.town,
      address && address.municipality,
      address && address.county,
      address && address.state,
      address && address.state_district,
      address && address.region,
      address && address.province
    ].map(normalizeGeoLabel).filter(Boolean);
    for (var i = 0; i < SAUDI_MAJOR_CITY_FALLBACKS.length; i += 1) {
      var cityConfig = SAUDI_MAJOR_CITY_FALLBACKS[i];
      for (var tokenIndex = 0; tokenIndex < tokens.length; tokenIndex += 1) {
        for (var aliasIndex = 0; aliasIndex < cityConfig.aliases.length; aliasIndex += 1) {
          var alias = cityConfig.aliases[aliasIndex];
          if (tokens[tokenIndex] === alias || tokens[tokenIndex].indexOf(alias) >= 0) {
            return cityConfig.name;
          }
        }
      }
    }
    var latValue = Number(lat);
    var lngValue = Number(lng);
    if (!Number.isFinite(latValue) || !Number.isFinite(lngValue)) return "";
    for (var cityIndex = 0; cityIndex < SAUDI_MAJOR_CITY_FALLBACKS.length; cityIndex += 1) {
      var bounds = SAUDI_MAJOR_CITY_FALLBACKS[cityIndex].bounds;
      if (latValue >= bounds.minLat && latValue <= bounds.maxLat && lngValue >= bounds.minLng && lngValue <= bounds.maxLng) {
        return SAUDI_MAJOR_CITY_FALLBACKS[cityIndex].name;
      }
    }
    return "";
  }

  function resolveCityFromAddress(address, countryValue, lat, lng) {
    var countryToken = normalizeGeoLabel(countryValue);
    var candidates = [
      address && address.city,
      address && address.town,
      address && address.municipality,
      address && address.county,
      address && address.village,
      address && address.state_district
    ].map(cleanAddressPart).filter(Boolean);
    for (var i = 0; i < candidates.length; i += 1) {
      if (normalizeGeoLabel(candidates[i]) !== countryToken && !looksLikeNeighborhoodLabel(candidates[i])) return candidates[i];
    }
    if (isSaudiCountry(countryValue)) return resolveSaudiMajorCity(address, lat, lng);
    return "";
  }

  function setProfileLocationDraft(lat, lng) {
    profileLocationDraft.lat = normalizeCoordinateValue(lat);
    profileLocationDraft.lng = normalizeCoordinateValue(lng);
    var coords = document.getElementById("pe-location-coords");
    if (!coords) return;
    if (!Number.isFinite(profileLocationDraft.lat) || !Number.isFinite(profileLocationDraft.lng)) {
      coords.textContent = "لم يتم اختيار نقطة بعد.";
      return;
    }
    coords.textContent = profileLocationDraft.lat.toFixed(5) + " ، " + profileLocationDraft.lng.toFixed(5);
  }

  function setProfileLocationStatus(message, state) {
    var status = document.getElementById("pe-location-status");
    if (!status) return;
    status.textContent = message || "";
    status.classList.remove("is-ok", "is-bad");
    if (state === true) status.classList.add("is-ok");
    if (state === false) status.classList.add("is-bad");
  }

  function setProfileLocationHint(message, state) {
    var hint = document.getElementById("pe-location-city-hint");
    if (!hint) return;
    hint.textContent = message || "";
    hint.classList.remove("is-ok", "is-bad");
    if (state === true) hint.classList.add("is-ok");
    if (state === false) hint.classList.add("is-bad");
  }

  function syncProfileLocationLabels(country, city) {
    var countryLabel = document.getElementById("pe-location-country-label");
    var cityLabel = document.getElementById("pe-location-city-label");
    var countryInput = document.querySelector(".pe-location-country-input");
    var cityInput = document.querySelector(".pe-location-city-input");
    if (countryLabel) countryLabel.textContent = country || "غير محددة";
    if (cityLabel) cityLabel.textContent = city || "غير محددة";
    if (countryInput) countryInput.value = country || "";
    if (cityInput) cityInput.value = city || "";
  }

  function applyResolvedProfileLocation(location) {
    var country = cleanAddressPart(location && location.country);
    var city = cleanAddressPart(location && location.city);
    syncProfileLocationLabels(country, city);
    setProfileLocationHint(city ? "تم تعبئة المدينة تلقائيًا من الموقع المحدد." : (country ? "لم نعثر على مدينة دقيقة. يمكنك تعديل المدينة يدويًا قبل الحفظ." : "إذا لم تُقرأ مدينة دقيقة، يمكنك تعديلها يدويًا قبل الحفظ."), city ? true : null);
    setProfileLocationStatus(country ? "تم تحديث الموقع من الخريطة بنجاح." : "تم تحديد النقطة، لكن تعذر استخراج الدولة.", !!country);
  }

  function getProfileLocationCenter() {
    if (Number.isFinite(profileLocationDraft.lat) && Number.isFinite(profileLocationDraft.lng)) {
      return [profileLocationDraft.lat, profileLocationDraft.lng];
    }
    if (hasPreciseCoordinates()) {
      return [Number(profile.latitude), Number(profile.longitude)];
    }
    return getCityCenter(profile && profile.location);
  }

  function ensureProfileLocationMarker(lat, lng) {
    if (!profileLocationMap) return;
    if (!profileLocationMarker) {
      profileLocationMarker = L.marker([lat, lng], { draggable: true }).addTo(profileLocationMap);
      profileLocationMarker.on("dragend", function () {
        var next = profileLocationMarker.getLatLng();
        setProfileLocationMapPoint(next.lat, next.lng, { source: "drag" });
      });
      return;
    }
    profileLocationMarker.setLatLng([lat, lng]);
  }

  function ensureProfileLocationMap() {
    var mapEl = document.getElementById("pe-profile-location-map");
    if (!mapEl || typeof L === "undefined") return;
    var center = getProfileLocationCenter();
    setProfileLocationDraft(center[0], center[1]);
    if (!profileLocationMap) {
      profileLocationMap = L.map(mapEl, {
        center: center,
        zoom: hasPreciseCoordinates() ? 13 : 11,
        scrollWheelZoom: false,
        zoomControl: true
      });
      L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
        attribution: '&copy; <a href="https://www.openstreetmap.org/">OSM</a>',
        maxZoom: 18
      }).addTo(profileLocationMap);
      profileLocationMap.on("click", function (event) {
        setProfileLocationMapPoint(event.latlng.lat, event.latlng.lng, { source: "map" });
      });
    } else {
      profileLocationMap.invalidateSize();
    }
    ensureProfileLocationMarker(center[0], center[1]);
    profileLocationMap.setView(center, hasPreciseCoordinates() ? 13 : 11, { animate: false });
    syncProfileLocationLabels(profile.locationCountry || "", profile.locationCity || "");
    setProfileLocationStatus(profile.location ? "الموقع الحالي محفوظ. يمكنك تغييره من الخريطة إذا لزم." : "اختر نقطة من الخريطة أو استخدم موقعك الحالي.", profile.location ? true : null);
    setProfileLocationHint(profile.locationCity ? "يمكنك تعديل اسم المدينة يدويًا إذا رغبت." : "إذا لم تُقرأ مدينة دقيقة، يمكنك تعديلها يدويًا قبل الحفظ.", profile.locationCity ? true : null);
  }

  function reverseGeocodeProfileLocation(lat, lng) {
    var params = new URLSearchParams({
      format: "jsonv2",
      lat: String(lat),
      lon: String(lng),
      zoom: "11",
      addressdetails: "1",
      "accept-language": "ar"
    });
    return fetch("https://nominatim.openstreetmap.org/reverse?" + params.toString(), {
      headers: { Accept: "application/json" }
    }).then(function (response) {
      if (!response.ok) throw new Error("reverse_geocode_failed");
      return response.json();
    }).then(function (data) {
      var address = data && typeof data === "object" ? (data.address || {}) : {};
      var country = resolveCountryFromAddress(address);
      var city = resolveCityFromAddress(address, country, lat, lng);
      return { country: country, city: city };
    });
  }

  function setProfileLocationMapPoint(lat, lng, options) {
    var normalizedLat = normalizeCoordinateValue(lat);
    var normalizedLng = normalizeCoordinateValue(lng);
    if (!Number.isFinite(normalizedLat) || !Number.isFinite(normalizedLng)) {
      setProfileLocationStatus("تعذر قراءة إحداثيات صالحة من النقطة المحددة.", false);
      return;
    }
    ensureProfileLocationMap();
    ensureProfileLocationMarker(normalizedLat, normalizedLng);
    setProfileLocationDraft(normalizedLat, normalizedLng);
    if (profileLocationMap) {
      profileLocationMap.setView([normalizedLat, normalizedLng], Math.max(profileLocationMap.getZoom(), 13), { animate: true });
    }
    setProfileLocationStatus(options && options.source === "device" ? "تم التقاط موقعك الحالي. جارٍ قراءة الدولة والمدينة..." : "جارٍ قراءة الدولة والمدينة من النقطة المختارة...", null);
    var requestId = ++profileLocationRequestId;
    reverseGeocodeProfileLocation(normalizedLat, normalizedLng).then(function (resolved) {
      if (requestId !== profileLocationRequestId) return;
      applyResolvedProfileLocation(resolved);
    }).catch(function () {
      if (requestId !== profileLocationRequestId) return;
      syncProfileLocationLabels("", "");
      setProfileLocationHint("تعذر استخراج المدينة. يمكنك تعبئتها يدويًا قبل الحفظ.", false);
      setProfileLocationStatus("تعذر قراءة بيانات الموقع من الخريطة.", false);
    });
  }

  function useCurrentProfileLocation(btn) {
    if (!navigator.geolocation) {
      setProfileLocationStatus("المتصفح لا يدعم تحديد الموقع الحالي.", false);
      return;
    }
    var originalText = btn ? btn.textContent : "";
    if (btn) {
      btn.disabled = true;
      btn.textContent = "جارٍ تحديد موقعي...";
    }
    setProfileLocationStatus("جارٍ التقاط موقعك الحالي...", null);
    navigator.geolocation.getCurrentPosition(function (position) {
      Promise.resolve(setProfileLocationMapPoint(position.coords.latitude, position.coords.longitude, { source: "device" })).finally(function () {
        if (!btn) return;
        btn.disabled = false;
        btn.textContent = originalText;
      });
    }, function (error) {
      if (btn) {
        btn.disabled = false;
        btn.textContent = originalText;
      }
      if (error && error.code === 1) {
        setProfileLocationStatus("تم رفض صلاحية الموقع. يمكنك اختيار النقطة يدويًا من الخريطة.", false);
        return;
      }
      setProfileLocationStatus("تعذر تحديد موقعك الحالي. جرّب مرة أخرى أو اختر النقطة يدويًا.", false);
    }, {
      enableHighAccuracy: true,
      timeout: 10000,
      maximumAge: 0
    });
  }

  function getCityCenter(city) {
    var scope = splitLocationScope(city);
    var center = CITY_COORDINATES[String(scope.city || "").trim()];
    return Array.isArray(center) ? center.slice() : DEFAULT_CITY_CENTER.slice();
  }

  function getServiceLocationCenter() {
    if (hasPreciseCoordinates()) {
      return [Number(profile.latitude), Number(profile.longitude)];
    }
    return getCityCenter(profile && profile.location);
  }

  function normalizeCoordinateValue(value) {
    var parsed = Number(value);
    if (!Number.isFinite(parsed)) return null;
    return Number(parsed.toFixed(6));
  }

  function getServiceRadiusKm() {
    var radius = Number.isFinite(Number(serviceRadiusDraft))
      ? serviceRadiusDraft
      : profile && profile.coverageRadius;
    return clampServiceRadiusKm(radius);
  }

  function clampServiceRadiusKm(value) {
    var radius = parseInt(value, 10);
    if (!Number.isFinite(radius)) return 0;
    return Math.min(SERVICE_RADIUS_MAX_KM, Math.max(0, radius));
  }

  function updateLanguageOtherVisibility() {
    var otherToggle = document.getElementById("pe-language-other");
    var otherWrap = document.getElementById("pe-language-other-wrap");
    if (!otherToggle || !otherWrap) return;
    otherWrap.classList.toggle("hidden", !otherToggle.checked);
  }

  function updateServiceLocationDraft(lat, lng) {
    serviceLocationDraft.lat = normalizeCoordinateValue(lat);
    serviceLocationDraft.lng = normalizeCoordinateValue(lng);
    var summary = document.getElementById("pe-service-map-coords");
    if (summary) {
      summary.textContent = Number.isFinite(serviceLocationDraft.lat) && Number.isFinite(serviceLocationDraft.lng)
        ? (serviceLocationDraft.lat.toFixed(6) + " ، " + serviceLocationDraft.lng.toFixed(6))
        : "لم يتم تحديد الموقع بعد";
    }
  }

  function syncRadiusInputs(value) {
    var radius = clampServiceRadiusKm(value);
    serviceRadiusDraft = radius;
    var range = document.getElementById("pe-radius-range");
    var numberInput = document.getElementById("pe-radius-number");
    var label = document.getElementById("pe-radius-live-value");
    if (range) range.value = String(radius);
    if (numberInput) numberInput.value = String(radius);
    if (label) label.textContent = radius + " كم";
    updateServiceRadiusPreview(radius);
    refreshLangLocOverview();
  }

  function updateServiceRadiusPreview(radiusKm) {
    var radius = clampServiceRadiusKm(radiusKm);
    if (serviceMapCircle && serviceMapMarker) {
      serviceMapCircle.setLatLng(serviceMapMarker.getLatLng());
      serviceMapCircle.setRadius(radius * 1000);
      if (typeof serviceMapCircle.redraw === "function") serviceMapCircle.redraw();
    }
    refreshGeoScopeSummaries();
  }

  function centerServiceMapOnCity(forceMarkerReset) {
    if (!serviceMap) return;
    var cityCenter = getCityCenter(profile && profile.location);
    var currentMarker = serviceMapMarker ? serviceMapMarker.getLatLng() : null;
    var nextCenter = (!forceMarkerReset && currentMarker)
      ? [currentMarker.lat, currentMarker.lng]
      : cityCenter;
    serviceMap.setView(nextCenter, forceMarkerReset ? 11 : 13, { animate: false });
    if (forceMarkerReset && serviceMapMarker) {
      serviceMapMarker.setLatLng(cityCenter);
      updateServiceLocationDraft(cityCenter[0], cityCenter[1]);
      updateServiceRadiusPreview(getServiceRadiusKm());
    }
  }

  function ensureServiceMap() {
    var mapCanvas = document.getElementById("pe-service-map");
    if (!mapCanvas || typeof L === "undefined") return;

    var center = getServiceLocationCenter();
    updateServiceLocationDraft(center[0], center[1]);

    if (!serviceMap) {
      serviceMap = L.map(mapCanvas, { scrollWheelZoom: false, zoomControl: true }).setView(center, 11);
      L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
        attribution: '&copy; OpenStreetMap contributors'
      }).addTo(serviceMap);

      serviceMapMarker = L.marker(center, { draggable: true }).addTo(serviceMap);
      serviceMapCircle = L.circle(center, {
        radius: getServiceRadiusKm() * 1000,
        color: "#673AB7",
        weight: 2,
        fillColor: "#8B5CF6",
        fillOpacity: 0.14
      }).addTo(serviceMap);

      serviceMap.on("click", function (event) {
        var latlng = event.latlng;
        serviceMapMarker.setLatLng(latlng);
        updateServiceLocationDraft(latlng.lat, latlng.lng);
        updateServiceRadiusPreview(getServiceRadiusKm());
      });

      serviceMapMarker.on("dragend", function () {
        var markerPoint = serviceMapMarker.getLatLng();
        updateServiceLocationDraft(markerPoint.lat, markerPoint.lng);
        updateServiceRadiusPreview(getServiceRadiusKm());
      });
    } else {
      serviceMap.invalidateSize();
      serviceMapMarker.setLatLng(center);
      serviceMap.setView(center, hasPreciseCoordinates() ? 13 : 11, { animate: false });
      updateServiceLocationDraft(center[0], center[1]);
      updateServiceRadiusPreview(getServiceRadiusKm());
    }
  }

  function normalizeSocialPlatform(value) {
    var text = String(value || "").trim().toLowerCase();
    if (!text) return "";
    if (text === "twitter" || text === "twitter_url" || text === "x_url") return "x";
    if (text === "fb" || text === "fb_url") return "facebook";
    if (text === "linkedin_url" || text === "linked_in" || text === "linkedin-profile") return "linkedin";
    if (text === "youtube_url" || text === "yt" || text === "youtube_channel") return "youtube";
    if (text === "pin" || text === "pinterest_url") return "pinterest";
    if (text === "behance_url") return "behance";
    if (text === "mail" || text === "mail_to" || text === "e-mail") return "email";
    return text;
  }

  function normalizeSocialLinkObject(item) {
    if (typeof item === "string") {
      var text = item.trim();
      return text ? { url: text } : null;
    }
    if (!item || typeof item !== "object") return null;

    var url = String(item.url || item.href || item.link || item.value || "").trim();
    if (!url) return null;

    var normalized = { url: url };
    var platform = normalizeSocialPlatform(item.platform || item.key || item.type || item.name);
    if (platform) normalized.platform = platform;
    if (item.label) normalized.label = String(item.label).trim();
    return normalized;
  }

  function detectSocialPlatform(item) {
    var normalized = normalizeSocialLinkObject(item);
    if (!normalized) return "";
    if (normalized.platform) return normalized.platform;

    var url = String(normalized.url || "").trim().toLowerCase();
    if (!url) return "";
    if (url.indexOf("mailto:") === 0) return "email";
    if (url.indexOf("linkedin.com") !== -1) return "linkedin";
    if (url.indexOf("youtube.com") !== -1 || url.indexOf("youtu.be") !== -1) return "youtube";
    if (url.indexOf("instagram") !== -1) return "instagram";
    if (url.indexOf("snapchat") !== -1) return "snapchat";
    if (url.indexOf("pinterest") !== -1) return "pinterest";
    if (url.indexOf("tiktok") !== -1) return "tiktok";
    if (url.indexOf("behance") !== -1) return "behance";
    if (url.indexOf("facebook") !== -1 || url.indexOf("fb.com") !== -1) return "facebook";
    if (url.indexOf("x.com") !== -1 || url.indexOf("twitter") !== -1) return "x";
    return "";
  }

  function socialFieldKeyFromPlatform(platform) {
    switch (normalizeSocialPlatform(platform)) {
      case "linkedin": return "linkedinUrl";
      case "youtube": return "youtubeUrl";
      case "facebook": return "facebookUrl";
      case "instagram": return "instagramUrl";
      case "x": return "xUrl";
      case "snapchat": return "snapchatUrl";
      case "pinterest": return "pinterestUrl";
      case "tiktok": return "tiktokUrl";
      case "behance": return "behanceUrl";
      case "email": return "contactEmail";
      default: return "";
    }
  }

  function normalizeSocialDisplayValue(platform, value) {
    var text = String(value || "").trim();
    if (!text) return "";
    return normalizeSocialPlatform(platform) === "email"
      ? text.replace(/^mailto:/i, "").trim()
      : text;
  }

  function extractSocialState(items) {
    var values = {
      linkedinUrl: "",
      youtubeUrl: "",
      facebookUrl: "",
      instagramUrl: "",
      xUrl: "",
      snapchatUrl: "",
      pinterestUrl: "",
      tiktokUrl: "",
      behanceUrl: "",
      contactEmail: ""
    };
    var extras = [];

    (Array.isArray(items) ? items : []).forEach(function (item) {
      var normalized = normalizeSocialLinkObject(item);
      if (!normalized) return;

      var platform = detectSocialPlatform(normalized);
      var fieldKey = socialFieldKeyFromPlatform(platform);
      if (!fieldKey) {
        extras.push(normalized);
        return;
      }

      var nextValue = normalizeSocialDisplayValue(platform, normalized.url);
      if (!values[fieldKey]) {
        values[fieldKey] = nextValue;
      } else {
        extras.push(normalized);
      }
    });

    return { values: values, extras: extras };
  }

  function collectSocialFormValues(activeKey, activeValue) {
    var values = {};
    SOCIAL_FIELD_KEYS.forEach(function (fieldKey) {
      values[fieldKey] = String(profile[fieldKey] || "");
    });
    if (activeKey && Object.prototype.hasOwnProperty.call(values, activeKey)) {
      values[activeKey] = String(activeValue || "").trim();
    }
    return values;
  }

  function ensureAbsoluteUrl(value) {
    var text = String(value || "").trim();
    if (!text) return "";
    if (/^[a-z][a-z0-9+.-]*:\/\//i.test(text)) return text;
    return "https://" + text.replace(/^\/+/, "");
  }

  function normalizeSocialEntryValue(fieldKey, value) {
    var text = String(value || "").trim();
    if (!text) return "";

    switch (fieldKey) {
      case "linkedinUrl":
        return text.match(/linkedin\.com|^https?:\/\//i) ? ensureAbsoluteUrl(text) : ("https://www.linkedin.com/in/" + text.replace(/^[@/]+/, ""));
      case "youtubeUrl":
        return text.match(/youtube\.com|youtu\.be|^https?:\/\//i) ? ensureAbsoluteUrl(text) : ("https://www.youtube.com/" + (text.charAt(0) === "@" ? text : ("@" + text.replace(/^[@/]+/, ""))));
      case "facebookUrl":
        return text.match(/facebook\.com|fb\.com|^https?:\/\//i) ? ensureAbsoluteUrl(text) : ("https://facebook.com/" + text.replace(/^@+/, ""));
      case "instagramUrl":
        return text.match(/instagram\.com|^https?:\/\//i) ? ensureAbsoluteUrl(text) : ("https://instagram.com/" + text.replace(/^@+/, ""));
      case "xUrl":
        return text.match(/x\.com|twitter\.com|^https?:\/\//i) ? ensureAbsoluteUrl(text) : ("https://x.com/" + text.replace(/^@+/, ""));
      case "snapchatUrl":
        return text.match(/snapchat\.com|^https?:\/\//i) ? ensureAbsoluteUrl(text) : ("https://snapchat.com/add/" + text.replace(/^@+/, ""));
      case "pinterestUrl":
        return text.match(/pinterest\.com|^https?:\/\//i) ? ensureAbsoluteUrl(text) : ("https://www.pinterest.com/" + text.replace(/^[@/]+/, ""));
      case "tiktokUrl":
        return text.match(/tiktok\.com|^https?:\/\//i) ? ensureAbsoluteUrl(text) : ("https://tiktok.com/@" + text.replace(/^@+/, ""));
      case "behanceUrl":
        return text.match(/behance\.net|^https?:\/\//i) ? ensureAbsoluteUrl(text) : ("https://www.behance.net/" + text.replace(/^[@/]+/, ""));
      case "contactEmail":
        return text.replace(/^mailto:/i, "").trim();
      default:
        return text;
    }
  }

  function isValidEmail(value) {
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(value || "").trim());
  }

  function validateSocialEntry(fieldKey, value) {
    var normalized = normalizeSocialEntryValue(fieldKey, value);
    if (!normalized) return "";

    if (fieldKey === "contactEmail") {
      if (!isValidEmail(normalized)) {
        throw new Error("أدخل بريدًا إلكترونيًا صحيحًا");
      }
      return normalized;
    }

    try {
      var parsed = new URL(normalized);
      if (!parsed.hostname) throw new Error("invalid-url");
    } catch (_err) {
      throw new Error("أدخل رابطًا صحيحًا لـ " + (fieldConfig(fieldKey).label || "وسيلة التواصل"));
    }
    return normalized;
  }

  function guessSocialLinkLabel(platform, url) {
    var normalizedPlatform = normalizeSocialPlatform(platform);
    if (normalizedPlatform && SOCIAL_PLATFORM_LABELS[normalizedPlatform]) return SOCIAL_PLATFORM_LABELS[normalizedPlatform];
    try {
      var parsed = new URL(ensureAbsoluteUrl(url));
      return parsed.hostname.replace(/^www\./i, "") || "رابط إضافي";
    } catch (_err) {
      return "رابط إضافي";
    }
  }

  function buildSocialExtraItem(label, url, platform) {
    var cleanLabel = String(label || "").trim();
    var cleanUrl = String(url || "").trim();
    if (!cleanLabel && !cleanUrl) return null;
    if (!cleanUrl) {
      throw new Error("أدخل الرابط أو احذف الصف الفارغ من الروابط الإضافية.");
    }
    var normalizedUrl = ensureAbsoluteUrl(cleanUrl);
    try {
      var parsed = new URL(normalizedUrl);
      if (!parsed.hostname) throw new Error("invalid-url");
    } catch (_err) {
      throw new Error("أدخل رابطًا صحيحًا داخل الروابط الإضافية.");
    }
    var resolvedPlatform = normalizeSocialPlatform(platform) || detectSocialPlatform({ url: normalizedUrl });
    return {
      platform: resolvedPlatform || undefined,
      label: cleanLabel || guessSocialLinkLabel(resolvedPlatform, normalizedUrl),
      url: normalizedUrl
    };
  }

  function sanitizeSocialExtraItems(items) {
    var extras = [];
    (Array.isArray(items) ? items : []).forEach(function (item) {
      var normalized = normalizeSocialLinkObject(item);
      if (!normalized) return;
      try {
        var extraItem = buildSocialExtraItem(normalized.label, normalized.url, normalized.platform);
        if (extraItem) extras.push(extraItem);
      } catch (_err) {}
    });
    return extras;
  }

  function collectAdditionalSocialItems() {
    var field = document.querySelector('.pe-field[data-key="additionalLinks"]');
    var rows = field ? field.querySelectorAll('.pe-additional-link-row') : [];
    var extras = [];
    for (var index = 0; index < rows.length; index += 1) {
      var row = rows[index];
      var labelInput = row.querySelector('.pe-additional-link-label');
      var urlInput = row.querySelector('.pe-additional-link-url');
      var extraItem = buildSocialExtraItem(labelInput && labelInput.value, urlInput && urlInput.value);
      if (extraItem) extras.push(extraItem);
    }
    return extras;
  }

  function buildSocialLinksPayload(values, extrasOverride) {
    var items = [];
    SOCIAL_FIELD_KEYS.forEach(function (fieldKey) {
      var platform = SOCIAL_FIELD_PLATFORMS[fieldKey];
      var clean = validateSocialEntry(fieldKey, values[fieldKey]);
      if (!clean) return;
      items.push({
        platform: platform,
        url: platform === "email" ? ("mailto:" + clean) : clean,
        label: fieldConfig(fieldKey).label || ""
      });
    });
    return items.concat(sanitizeSocialExtraItems(extrasOverride !== undefined ? extrasOverride : profile.socialExtras));
  }

  function applySocialState(state) {
    var nextState = state || extractSocialState([]);
    profile.socialExtras = sanitizeSocialExtraItems(nextState.extras);
    profile.additionalLinks = profile.socialExtras.length ? String(profile.socialExtras.length) : "";
    SOCIAL_FIELD_KEYS.forEach(function (fieldKey) {
      profile[fieldKey] = String((nextState.values && nextState.values[fieldKey]) || "");
    });
  }

  function normalizeSeoText(value) {
    return String(value || "").replace(/\s+/g, " ").trim();
  }

  function normalizeSeoKeywordsText(value) {
    return uniqueNonEmpty(splitEntries(value)).join("، ");
  }

  function normalizeSeoSlugValue(value) {
    return String(value || "")
      .trim()
      .toLowerCase()
      .replace(/[^\u0600-\u06ff0-9a-z]+/gi, "-")
      .replace(/^-+|-+$/g, "");
  }

  function isSeoFieldKey(key) {
    return key === "seoTitle" || key === "seoMetaDescription" || key === "seoSlug" || key === "keywords";
  }

  function buildProviderPublicPath(slugValue) {
    var providerId = profile && profile.providerId ? String(profile.providerId) : "";
    if (!providerId) return "/provider/";
    var normalizedSlug = normalizeSeoSlugValue(slugValue);
    return normalizedSlug ? ("/provider/" + providerId + "/" + normalizedSlug + "/") : ("/provider/" + providerId + "/");
  }

  function splitSeoKeywords(value) {
    return uniqueNonEmpty(splitEntries(value));
  }

  function seoMetricConfig(key) {
    if (key === "seoTitle") return { idealMin: 45, idealMax: 65, hardMax: 160, unit: "حرف" };
    if (key === "seoMetaDescription") return { idealMin: 120, idealMax: 160, hardMax: 320, unit: "حرف" };
    if (key === "seoSlug") return { idealMin: 12, idealMax: 60, hardMax: 150, unit: "حرف" };
    if (key === "keywords") return { idealMin: 3, idealMax: 8, hardMax: 20, unit: "كلمة" };
    return { idealMin: 0, idealMax: 0, hardMax: 0, unit: "" };
  }

  function seoMetricTone(length, config) {
    if (!config.hardMax) return "neutral";
    if (length === 0) return "empty";
    if (length > config.hardMax) return "danger";
    if (length < config.idealMin || length > config.idealMax) return "warning";
    return "good";
  }

  function seoMetricAdvice(key, length, config) {
    if (key === "keywords") {
      if (!length) return "ابدأ بثلاث كلمات أو عبارات مرتبطة مباشرة بخدمتك.";
      if (length > config.hardMax) return "قلّل الكلمات المفتاحية واحتفظ بالأكثر صلة بخدمتك.";
      if (length < config.idealMin) return "أضف كلمات أكثر لزيادة تغطية البحث.";
      if (length > config.idealMax) return "العدد جيد، لكن اختصر للقائمة الأكثر أهمية فقط.";
      return "العدد مناسب ويغطي البحث بصورة متوازنة.";
    }
    if (!length) return "اكتب قيمة واضحة بدل ترك هذا الحقل فارغًا.";
    if (length > config.hardMax) return "تجاوزت الحد المناسب. اختصر النص قبل الحفظ.";
    if (length < config.idealMin) return "النص قصير أكثر من اللازم وقد يفقد المعنى في نتائج البحث.";
    if (length > config.idealMax) return "النص طويل نسبيًا وقد يتم اقتطاعه في نتائج البحث.";
    return "الطول مناسب للظهور بصورة جيدة في نتائج البحث.";
  }

  function readSeoDraftValue(key) {
    var input = document.querySelector('.pe-input[data-key="' + key + '"]');
    if (input) return String(input.value || "");
    return String((profile && profile[key]) || "");
  }

  function buildSeoPreviewState() {
    var title = normalizeSeoText(readSeoDraftValue("seoTitle")) || normalizeSeoText(profile.fullName) || "مقدم خدمة على نوافذ";
    var description = normalizeSeoText(readSeoDraftValue("seoMetaDescription")) || normalizeSeoText(profile.about) || "أضف وصف الصفحة لتظهر هنا معاينة النتيجة كما يراها المستخدم في نتائج البحث.";
    var slugValue = normalizeSeoSlugValue(readSeoDraftValue("seoSlug"));
    var keywords = splitSeoKeywords(readSeoDraftValue("keywords"));
    return {
      title: title,
      description: description,
      slug: slugValue,
      path: buildProviderPublicPath(slugValue),
      keywords: keywords,
      fallbackPath: buildProviderPublicPath("")
    };
  }

  function renderSeoKeywordChips(items) {
    var keywords = Array.isArray(items) ? items : splitSeoKeywords(items);
    if (!keywords.length) {
      return '<span class="pe-empty-value">لم تتم إضافة كلمات مفتاحية بعد</span>';
    }
    return keywords.map(function (entry) {
      return '<span class="pe-seo-keyword-chip">' + escapeHtml(entry) + '</span>';
    }).join("");
  }

  function updateSeoFieldFeedback(key) {
    if (!isSeoFieldKey(key)) return;
    var counterNode = document.getElementById("pe-seo-counter-" + key);
    var adviceNode = document.getElementById("pe-seo-advice-" + key);
    var slugNode = key === "seoSlug" ? document.getElementById("pe-seo-slug-preview") : null;
    var config = seoMetricConfig(key);
    var rawValue = readSeoDraftValue(key);
    var length = key === "keywords" ? splitSeoKeywords(rawValue).length : normalizeSeoText(key === "seoSlug" ? normalizeSeoSlugValue(rawValue) : rawValue).length;
    var tone = seoMetricTone(length, config);

    if (counterNode) {
      counterNode.textContent = length + " " + config.unit;
      counterNode.className = "pe-seo-counter is-" + tone;
    }
    if (adviceNode) {
      adviceNode.textContent = seoMetricAdvice(key, length, config);
    }
    if (slugNode) {
      slugNode.textContent = buildProviderPublicPath(rawValue);
    }
  }

  function updateSeoPreview() {
    var state = buildSeoPreviewState();
    var titleNode = document.getElementById("pe-seo-preview-title");
    var urlNode = document.getElementById("pe-seo-preview-url");
    var descNode = document.getElementById("pe-seo-preview-description");
    var keywordsNode = document.getElementById("pe-seo-preview-keywords");
    var noteNode = document.getElementById("pe-seo-preview-note");
    if (titleNode) titleNode.textContent = state.title + " | نوافــذ";
    if (urlNode) urlNode.textContent = state.path;
    if (descNode) descNode.textContent = state.description;
    if (keywordsNode) keywordsNode.innerHTML = renderSeoKeywordChips(state.keywords);
    if (noteNode) {
      noteNode.textContent = state.slug
        ? "سيتم استخدام الرابط المخصص أعلاه كرابط أساسي لصفحتك العامة."
        : ("إذا تركت الرابط المخصص فارغًا فسيبقى الرابط الحالي: " + state.fallbackPath);
    }
  }

  function uniqueNonEmpty(values) {
    var seen = {};
    var result = [];
    (values || []).forEach(function (value) {
      var clean = String(value || "").trim();
      if (!clean || seen[clean]) return;
      seen[clean] = true;
      result.push(clean);
    });
    return result;
  }

  function uniqueNumeric(values) {
    var seen = {};
    var result = [];
    (values || []).forEach(function (value) {
      var parsed = parseInt(value, 10);
      if (!isFinite(parsed) || seen[parsed]) return;
      seen[parsed] = true;
      result.push(parsed);
    });
    return result;
  }

  function normalizeCategoryCatalog(items) {
    return extractList(items).map(function (item) {
      var categoryId = parseInt(item && item.id, 10);
      if (!isFinite(categoryId)) return null;
      return {
        id: categoryId,
        name: String(item && item.name || "").trim(),
        subcategories: extractList(item && item.subcategories).map(function (sub) {
          var subId = parseInt(sub && sub.id, 10);
          if (!isFinite(subId)) return null;
          return {
            id: subId,
            name: String(sub && sub.name || "").trim(),
            category_id: categoryId,
            category_name: String(item && item.name || "").trim(),
            requires_geo_scope: !(sub && sub.requires_geo_scope === false),
            allows_urgent_requests: !!(sub && sub.allows_urgent_requests)
          };
        }).filter(Boolean)
      };
    }).filter(Boolean);
  }

  function applyProviderSubcategoryState(ids, settings, selectedSubcategories) {
    providerSubcategoryIds = uniqueNumeric(ids);
    providerSelectedSubcategories = Array.isArray(selectedSubcategories) ? selectedSubcategories.slice() : [];
    providerSubcategorySettingsById = {};
    (settings || []).forEach(function (item) {
      var subId = parseInt(item && item.subcategory_id, 10);
      if (!isFinite(subId)) return;
      providerSubcategorySettingsById[subId] = normalizeSubcategorySetting(item);
    });
  }

  function normalizeSubcategorySetting(item) {
    return {
      accepts_urgent: !!(item && item.accepts_urgent)
    };
  }

  function getSubcategorySetting(subcategoryId) {
    var subId = parseInt(subcategoryId, 10);
    if (!isFinite(subId)) {
      return normalizeSubcategorySetting(null);
    }
    return normalizeSubcategorySetting(providerSubcategorySettingsById[subId]);
  }

  function setSubcategorySetting(subcategoryId, changes) {
    var subId = parseInt(subcategoryId, 10);
    if (!isFinite(subId)) return;
    var current = getSubcategorySetting(subId);
    providerSubcategorySettingsById[subId] = {
      accepts_urgent: Object.prototype.hasOwnProperty.call(changes || {}, "accepts_urgent")
        ? !!changes.accepts_urgent
        : current.accepts_urgent
    };
  }

  function findCategoryById(categoryId) {
    var wanted = parseInt(categoryId, 10);
    if (!isFinite(wanted)) return null;
    for (var i = 0; i < categoryCatalog.length; i++) {
      if (categoryCatalog[i].id === wanted) return categoryCatalog[i];
    }
    return null;
  }

  function findSubcategoryById(subcategoryId) {
    var wanted = parseInt(subcategoryId, 10);
    if (!isFinite(wanted)) return null;
    for (var i = 0; i < categoryCatalog.length; i++) {
      var category = categoryCatalog[i];
      for (var j = 0; j < category.subcategories.length; j++) {
        if (category.subcategories[j].id === wanted) {
          return category.subcategories[j];
        }
      }
    }
    for (var k = 0; k < providerSelectedSubcategories.length; k++) {
      var item = providerSelectedSubcategories[k] || {};
      if (parseInt(item.id, 10) === wanted) {
        return {
          id: wanted,
          name: String(item.name || "").trim(),
          category_id: parseInt(item.category_id, 10),
          category_name: String(item.category_name || "").trim(),
          requires_geo_scope: !(item && item.requires_geo_scope === false),
          allows_urgent_requests: !!(item && item.allows_urgent_requests)
        };
      }
    }
    return null;
  }

  function getSubcategoryPolicy(subcategoryId) {
    var subcategory = findSubcategoryById(subcategoryId);
    return {
      requires_geo_scope: !(subcategory && subcategory.requires_geo_scope === false),
      allows_urgent_requests: !!(subcategory && subcategory.allows_urgent_requests)
    };
  }

  function buildCategorySummaryData(ids, settingsById) {
    var groupsByKey = {};
    var orderedGroups = [];

    uniqueNumeric(ids).forEach(function (subId) {
      var sub = findSubcategoryById(subId);
      if (!sub) return;
      var key = isFinite(sub.category_id) ? String(sub.category_id) : String(sub.category_name || "بدون قسم");
      if (!groupsByKey[key]) {
        groupsByKey[key] = {
          categoryName: String(sub.category_name || "بدون قسم").trim(),
          subcategoryNames: [],
          urgentSubcategoryNames: []
        };
        orderedGroups.push(groupsByKey[key]);
      }
      if (sub.name) groupsByKey[key].subcategoryNames.push(sub.name);
      var subcategorySetting = settingsById ? normalizeSubcategorySetting(settingsById[subId]) : normalizeSubcategorySetting(null);
      if (sub.name && subcategorySetting.accepts_urgent) groupsByKey[key].urgentSubcategoryNames.push(sub.name);
    });

    return {
      groups: orderedGroups.map(function (group) {
        return {
          categoryName: group.categoryName,
          subcategoryNames: uniqueNonEmpty(group.subcategoryNames),
          urgentSubcategoryNames: uniqueNonEmpty(group.urgentSubcategoryNames)
        };
      }).filter(function (group) {
        return group.categoryName || group.subcategoryNames.length;
      }),
      categories: uniqueNonEmpty(orderedGroups.map(function (group) { return group.categoryName; })),
      subcategories: uniqueNonEmpty([].concat.apply([], orderedGroups.map(function (group) { return group.subcategoryNames; })))
    };
  }

  function getDraftOrSavedSubcategoryIds() {
    var groupCards = getCategoryGroupCards();
    if (groupCards.length) return collectDraftServiceCategoryIds();
    return providerSubcategoryIds;
  }

  function buildGeoScopeSummaryData(ids, settingsById) {
    var localNames = [];
    var remoteNames = [];
    uniqueNumeric(ids).forEach(function (subId) {
      var sub = findSubcategoryById(subId);
      if (!sub || !sub.name) return;
      var policy = getSubcategoryPolicy(subId);
      if (policy.requires_geo_scope === false) {
        remoteNames.push(sub.name);
      } else {
        localNames.push(sub.name);
      }
    });
    return {
      localNames: uniqueNonEmpty(localNames),
      remoteNames: uniqueNonEmpty(remoteNames)
    };
  }

  function getGeoScopeSummaryData() {
    return buildGeoScopeSummaryData(getDraftOrSavedSubcategoryIds(), providerSubcategorySettingsById);
  }

  function renderGeoScopeTags(names, tone) {
    if (!Array.isArray(names) || !names.length) return '<span class="pe-empty-value">لا يوجد</span>';
    return names.map(function (name) {
      return '<span class="pe-scope-tag pe-scope-tag--' + escapeHtml(tone) + '">' + escapeHtml(name) + '</span>';
    }).join('');
  }

  function renderGeoScopeSummaryHtml(summary) {
    var data = summary || getGeoScopeSummaryData();
    return '<div class="pe-scope-summary-grid">' +
      '<section class="pe-scope-card pe-scope-card--local">' +
        '<div class="pe-scope-card-head">' +
          '<strong>الخدمات المحلية</strong>' +
          '<span>' + data.localNames.length + ' تخصص</span>' +
        '</div>' +
        '<p>هذه الخدمات محلية وفق سياسة التصنيفات المحددة، لذلك تخضع لموقعك المحدد على الخريطة ولنصف القطر بالكيلومتر.</p>' +
        '<div class="pe-scope-tags">' + renderGeoScopeTags(data.localNames, 'local') + '</div>' +
      '</section>' +
      '<section class="pe-scope-card pe-scope-card--remote">' +
        '<div class="pe-scope-card-head">' +
          '<strong>الخدمات عن بُعد</strong>' +
          '<span>' + data.remoteNames.length + ' تخصص</span>' +
        '</div>' +
        '<p>هذه الخدمات مفعّلة عن بُعد وفق سياسة التصنيفات المحددة، لذلك لا تتقيّد بالمدينة أو نصف القطر.</p>' +
        '<div class="pe-scope-tags">' + renderGeoScopeTags(data.remoteNames, 'remote') + '</div>' +
      '</section>' +
    '</div>';
  }

  function refreshGeoScopeSummaries() {
    var summary = getGeoScopeSummaryData();
    var locationSummary = document.getElementById('pe-location-scope-summary');
    var radiusSummary = document.getElementById('pe-radius-scope-summary');
    var helper = document.getElementById('pe-radius-helper');
    if (locationSummary) locationSummary.innerHTML = renderGeoScopeSummaryHtml(summary);
    if (radiusSummary) radiusSummary.innerHTML = renderGeoScopeSummaryHtml(summary);
    if (helper) {
      var radius = getServiceRadiusKm();
      if (!summary.localNames.length && summary.remoteNames.length) {
        helper.textContent = 'لا توجد حاليًا خدمات محلية مرتبطة بالخريطة. نصف القطر لن يؤثر إلا عند تفعيل تخصصات محلية.';
      } else if (!summary.localNames.length) {
        helper.textContent = 'اختر تخصصًا محليًا واحدًا على الأقل ليؤثر نصف القطر على نطاق ظهورك.';
      } else if (radius > 0) {
        helper.textContent = 'سيظهر نطاق الخدمات المحلية كدائرة حول موقعك بقطر تقريبي ' + (radius * 2) + ' كم، بينما تبقى خدمات عن بُعد خارج هذا التقييد.';
      } else {
        helper.textContent = 'حدّد نصف قطر التغطية ليظهر كنطاق للخدمات المحلية فقط؛ أما خدمات عن بُعد فلن تتأثر به.';
      }
    }
  }

  function buildSelectedCategorySummaryData() {
    return buildCategorySummaryData(providerSubcategoryIds, providerSubcategorySettingsById);
  }

  function renderServiceCategoriesSummaryHtml(ids, settingsById) {
    var summary = buildCategorySummaryData(ids || providerSubcategoryIds, settingsById || providerSubcategorySettingsById);
    if (!summary.groups.length) {
      return '<span class="pe-empty-value">لم تتم إضافة أي تصنيفات فرعية بعد</span>';
    }
    return summary.groups.map(function (group) {
      var countText = group.subcategoryNames.length + ' ' + (group.subcategoryNames.length === 1 ? 'تصنيف فرعي' : 'تصنيفات فرعية');
      return '<div class="pe-category-summary-group">' +
        '<div class="pe-category-summary-head"><strong>' + escapeHtml(group.categoryName || 'قسم غير محدد') + '</strong><span>' + escapeHtml(countText) + '</span></div>' +
        '<div class="pe-category-summary-tags">' + group.subcategoryNames.map(function (name) {
          var isUrgent = group.urgentSubcategoryNames.indexOf(name) !== -1;
          return '<span class="pe-category-summary-tag' + (isUrgent ? ' is-urgent' : '') + '">' + escapeHtml(name) + (isUrgent ? '<em>عاجل</em>' : '') + '</span>';
        }).join('') + '</div>' +
      '</div>';
    }).join('');
  }

  function parseIsoDate(value) {
    var text = String(value || "").trim();
    if (!text) return null;
    var parsed = new Date(text);
    return isNaN(parsed.getTime()) ? null : parsed;
  }

  function formatAwardDate(value) {
    var parsed = parseIsoDate(value);
    if (!parsed) return "";
    try {
      return parsed.toLocaleDateString("ar-SA");
    } catch (_err) {
      return parsed.toISOString().slice(0, 10);
    }
  }

  function _isRecentlyAwarded(badge, windowDays) {
    var awarded = parseIsoDate(badge && badge.awarded_at);
    if (!awarded) return false;
    var maxAgeDays = Number(windowDays || 14);
    var diffMs = Date.now() - awarded.getTime();
    return diffMs >= 0 && diffMs <= (maxAgeDays * 24 * 60 * 60 * 1000);
  }

  function _identityInitial(name) {
    var clean = String(name || "").trim();
    return clean ? clean.charAt(0) : "ن";
  }

  function renderIdentityCard(prov, user) {
    var card = document.getElementById("pe-identity-card");
    if (!card) return;

    var badges = UI.normalizeExcellenceBadges(prov && prov.excellence_badges);
    var displayName = String((prov && prov.display_name) || (user && user.full_name) || "مزود الخدمة").trim();
    var avatarUrl = String((prov && prov.profile_image) || "").trim();

    var nameNode = document.getElementById("pe-display-name");
    if (nameNode) nameNode.textContent = displayName || "مزود الخدمة";

    var avatarImg = document.getElementById("pe-avatar-img");
    var avatarFallback = document.getElementById("pe-avatar-fallback");
    if (avatarFallback) avatarFallback.textContent = _identityInitial(displayName);
    if (avatarImg) {
      if (avatarUrl) {
        avatarImg.src = avatarUrl;
        avatarImg.classList.remove("hidden");
        if (avatarFallback) avatarFallback.classList.add("hidden");
        avatarImg.onerror = function () {
          avatarImg.classList.add("hidden");
          if (avatarFallback) avatarFallback.classList.remove("hidden");
        };
      } else {
        avatarImg.removeAttribute("src");
        avatarImg.classList.add("hidden");
        if (avatarFallback) avatarFallback.classList.remove("hidden");
      }
    }

    var inlineMount = document.getElementById("pe-inline-badges");
    if (inlineMount) {
      inlineMount.innerHTML = "";
      var inlineBadges = UI.buildExcellenceBadges(badges, {
        className: "excellence-badges compact pe-name-excellence",
        compact: true,
      });
      if (inlineBadges) {
        inlineMount.appendChild(inlineBadges);
        inlineMount.classList.remove("hidden");
      } else {
        inlineMount.classList.add("hidden");
      }
    }

    var avatarBadge = document.getElementById("pe-avatar-badge");
    if (avatarBadge) {
      var topBadge = badges.length ? badges[0] : null;
      if (topBadge) {
        avatarBadge.textContent = badgeName(topBadge) || topBadge.code || badgeFallbackLabel();
        avatarBadge.classList.remove("hidden");
      } else {
        avatarBadge.classList.add("hidden");
        avatarBadge.textContent = "";
      }
    }

    var congratsNode = document.getElementById("pe-congrats-banner");
    if (congratsNode) {
      var newBadge = badges.find(function (badge) {
        return _isRecentlyAwarded(badge, 14);
      });
      if (newBadge) {
        var issuedOn = formatAwardDate(newBadge.awarded_at);
        congratsNode.textContent = badgeCongratsText(newBadge, issuedOn);
        congratsNode.classList.remove("hidden");
      } else {
        congratsNode.classList.add("hidden");
        congratsNode.textContent = "";
      }
    }

    card.style.display = "";
  }

  function bindAvatarUpload() {
    var uploadBtn = document.getElementById("pe-avatar-upload-btn");
    var fileInput = document.getElementById("pe-avatar-file");
    if (!uploadBtn || !fileInput) return;

    function setAvatarUploadState(loading, message) {
      var status = document.getElementById("pe-avatar-upload-status");
      uploadBtn.classList.toggle("is-uploading", !!loading);
      uploadBtn.disabled = !!loading;
      fileInput.disabled = !!loading;
      if (status) {
        status.classList.toggle("hidden", !loading);
        status.textContent = loading ? (message || "جاري رفع الصورة...") : "";
      }
    }

    uploadBtn.addEventListener("click", function () {
      if (uploadBtn.disabled) return;
      fileInput.value = "";
      fileInput.click();
    });

    fileInput.addEventListener("change", function () {
      var file = fileInput.files && fileInput.files[0];
      if (!file) return;

      var maxSize = 20 * 1024 * 1024;
      if (file.size > maxSize) {
        alert("حجم الصورة يجب ألا يتجاوز 20 ميغابايت");
        return;
      }

      var allowedTypes = ["image/jpeg", "image/png", "image/webp"];
      if (allowedTypes.indexOf(file.type) === -1) {
        alert("يجب أن تكون الصورة بصيغة JPEG أو PNG أو WebP");
        return;
      }

      setAvatarUploadState(true, "جاري رفع صورة الملف الشخصي...");

      var fd = new FormData();
      fd.append("profile_image", file);

      var RAW = (typeof ApiClient !== "undefined" && ApiClient && typeof ApiClient.request === "function") ? ApiClient : null;
      var uploadPromise;
      if (RAW) {
        uploadPromise = RAW.request("/api/providers/me/profile/", { method: "PATCH", body: fd, formData: true });
      } else {
        var accessToken = (window.Auth && typeof window.Auth.getAccessToken === "function")
          ? (window.Auth.getAccessToken() || "")
          : (((window.sessionStorage && window.sessionStorage.getItem("nw_access_token"))
            || (window.localStorage && window.localStorage.getItem("nw_access_token"))) || "");
        uploadPromise = fetch(window.location.origin + "/api/providers/me/profile/", {
          method: "PATCH",
          headers: { "Authorization": "Bearer " + accessToken },
          body: fd
        }).then(function (res) {
          return res.json().then(function (data) { return { ok: res.ok, data: data }; });
        });
      }

      uploadPromise.then(function (resp) {
        if (!resp || !resp.ok) {
          throw new Error("فشل رفع الصورة");
        }
        var newUrl = (resp.data && resp.data.profile_image) || "";
        if (providerProfileRaw) providerProfileRaw.profile_image = newUrl;
        var avatarImg = document.getElementById("pe-avatar-img");
        var avatarFallback = document.getElementById("pe-avatar-fallback");
        if (avatarImg && newUrl) {
          avatarImg.src = newUrl;
          avatarImg.classList.remove("hidden");
          if (avatarFallback) avatarFallback.classList.add("hidden");
        }
        if (isSectionFlowActive()) renderSectionLinks(initialSection);
        if (typeof NwToast !== "undefined") NwToast.success("تم تحديث الصورة بنجاح");
      }).catch(function (err) {
        alert((err && err.message) || "تعذر رفع الصورة، حاول مرة أخرى");
      }).finally(function () {
        setAvatarUploadState(false);
      });
    });
  }

  function isSectionFlowActive() {
    return !!(initialSection && SECTION_CONFIG[initialSection]);
  }

  function setSectionFlow(active) {
    document.body.classList.toggle("pe-section-flow", !!active);
    var tabsCard = document.querySelector(".pe-tabs-card");
    var hero = document.getElementById("pe-section-hero");
    var linksCard = document.getElementById("pe-section-links-card");
    if (tabsCard) tabsCard.style.display = active ? "none" : "";
    if (hero) hero.style.display = active ? "" : "none";
    if (linksCard) linksCard.style.display = active ? "" : "none";
  }

  function renderSectionHero(sectionKey) {
    var cfg = SECTION_CONFIG[sectionKey];
    var kicker = document.getElementById("pe-section-kicker");
    var heading = document.getElementById("pe-section-heading");
    var intro = document.getElementById("pe-section-intro");
    if (!cfg) return;
    if (kicker) kicker.textContent = cfg.kicker;
    if (heading) heading.textContent = cfg.heading;
    if (intro) intro.textContent = cfg.intro;
  }

  function renderSectionLinks(activeKey) {
    var root = document.getElementById("pe-section-links");
    if (!root) return;
    computeSectionCompletionState();
    root.innerHTML = '<div class="pe-section-progress">' +
      '<div class="pe-section-progress-head">' +
        '<strong class="pe-section-progress-percent">' + sectionCompletionState.percent + '%</strong>' +
        '<span class="pe-section-progress-title">نسبة اكتمال الملف</span>' +
      '</div>' +
      '<div class="pe-section-progress-bar"><span style="width:' + sectionCompletionState.percent + '%"></span></div>' +
      '<p class="pe-section-progress-hint">30٪ من التسجيل الأساسي، والباقي من إكمال الأقسام أدناه.</p>' +
    '</div>' +
    '<div class="pe-section-links-list">' + SECTION_LINKS.map(function (item) {
      var active = item.key === activeKey;
      var done = !!sectionCompletionState.checks[item.key];
      return '<a class="pe-section-link pe-section-link--' + escapeHtml(item.tone || 'violet') + (active ? ' is-active' : '') + (done ? ' is-complete' : ' is-incomplete') + '" data-complete="' + (done ? '1' : '0') + '" href="' + item.href + '">' +
        '<span class="pe-section-link-status">' + sectionCheckSvg(done) + '</span>' +
        '<span class="pe-section-link-copy">' +
          '<span class="pe-section-link-label">' + escapeHtml(item.label) + '</span>' +
          (item.summary ? '<span class="pe-section-link-desc">' + escapeHtml(item.summary) + '</span>' : '') +
        '</span>' +
        '<span class="pe-section-link-icon" aria-hidden="true">' + iconSvg(item.icon || 'category') + '</span>' +
      '</a>';
    }).join("") + '</div>';
  }

  function buildSummaryCard(title, value) {
    var body = String(value || "").trim();
    var content = body
      ? escapeHtml(body).replace(/\n/g, "<br>")
      : '<span class="pe-empty-value">غير متوفر</span>';
    return '<article class="pe-summary-card">' +
      '<h3 class="pe-summary-title">' + escapeHtml(title) + '</h3>' +
      '<div class="pe-summary-value">' + content + '</div>' +
    '</article>';
  }

  function buildBasicSummary() {
    var username = userProfile && userProfile.username ? String(userProfile.username).trim() : "";
    var phone = userProfile && userProfile.phone ? String(userProfile.phone).trim() : "";
    var email = userProfile && userProfile.email ? String(userProfile.email).trim() : "";
    if (username && username.charAt(0) !== "@") username = "@" + username;

    var selectedSummary = buildSelectedCategorySummaryData();
    var categories = selectedSummary.categories.length ? selectedSummary.categories : uniqueNonEmpty(myServices.map(function (service) {
      var sub = service && service.subcategory ? service.subcategory : {};
      return sub.category_name || (sub.category && sub.category.name) || "";
    }));

    var subcategories = selectedSummary.subcategories.length ? selectedSummary.subcategories : uniqueNonEmpty(myServices.map(function (service) {
      var sub = service && service.subcategory ? service.subcategory : {};
      return sub.name || "";
    }));

    var accountLines = [];
    if (profile.fullName) accountLines.push(profile.fullName);
    if (username) accountLines.push(username);
    if (profile.accountType) accountLines.push("نوع الحساب: " + (TYPE_LABELS[profile.accountType] || profile.accountType));

    var specializationLines = [];
    if (categories.length) specializationLines.push("التصنيف: " + categories.join("، "));
    if (subcategories.length) specializationLines.push("التخصصات: " + subcategories.join("، "));

    var contactLines = [];
    if (phone) contactLines.push("الجوال: " + phone);
    if (profile.phone) contactLines.push("واتساب: " + profile.phone);
    if (profile.location) contactLines.push("المنطقة والمدينة: " + profile.location);
    if (email) contactLines.push("البريد: " + email);

    return '<div class="pe-summary-grid">' +
      buildSummaryCard("الاسم والحساب", accountLines.join("\n")) +
      buildSummaryCard("التصنيف والتخصص", specializationLines.join("\n")) +
      buildSummaryCard("التواصل الأساسي", contactLines.join("\n")) +
      buildSummaryCard("نبذة التسجيل", profile.about || "") +
    '</div>';
  }

  function extractContentSectionTitle(caption) {
    var text = String(caption || "").trim();
    if (!text) return "";
    var separators = [" | ", "|", " - ", " — ", " – "];
    for (var i = 0; i < separators.length; i++) {
      var separator = separators[i];
      var index = text.indexOf(separator);
      if (index > 0) return String(text.slice(0, index)).trim();
    }
    return text;
  }

  function extractContentItemDescription(caption, sectionTitle) {
    var text = String(caption || "").trim();
    var title = String(sectionTitle || "").trim();
    if (!text || !title) return "";
    var prefixes = [title + " | ", title + "|", title + " - ", title + " — ", title + " – "];
    for (var i = 0; i < prefixes.length; i++) {
      if (text.indexOf(prefixes[i]) === 0) return String(text.slice(prefixes[i].length)).trim();
    }
    return text === title ? "" : text;
  }

  function buildContentItemCaption(sectionTitle, description) {
    var title = String(sectionTitle || "").trim();
    var desc = String(description || "").trim();
    if (!title) return desc;
    return desc ? (title + " | " + desc) : title;
  }

  function normalizeContentPortfolioList(payload) {
    return extractList(payload).map(function (item) {
      var itemId = parseInt(item && item.id, 10);
      if (!isFinite(itemId)) return null;
      var sectionTitle = extractContentSectionTitle(item && item.caption);
      return {
        id: itemId,
        fileType: String(item && item.file_type || "").trim().toLowerCase(),
        fileUrl: String(item && (item.file_url || item.file) || "").trim(),
        thumbnailUrl: String(item && (item.thumbnail_url || item.file_url || item.file) || "").trim(),
        caption: String(item && item.caption || "").trim(),
        sectionTitle: sectionTitle,
        description: extractContentItemDescription(item && item.caption, sectionTitle),
        createdAt: String(item && item.created_at || "").trim()
      };
    }).filter(Boolean);
  }

  function getContentCategoryNames() {
    var selectedSummary = buildSelectedCategorySummaryData();
    return selectedSummary.categories.length ? selectedSummary.categories : uniqueNonEmpty(myServices.map(function (service) {
      var sub = service && service.subcategory ? service.subcategory : {};
      return sub.category_name || (sub.category && sub.category.name) || "";
    }));
  }

  function buildContentCardsData() {
    var categories = getContentCategoryNames();
    var cards = categories.map(function (name) {
      return { key: String(name || "").trim().toLowerCase(), title: String(name || "").trim(), items: [], auxiliary: false };
    }).filter(function (card) {
      return !!card.title;
    });
    var byKey = {};
    cards.forEach(function (card) {
      byKey[card.key] = card;
    });
    var unmatched = [];
    portfolioItems.forEach(function (item) {
      var key = String(item.sectionTitle || "").trim().toLowerCase();
      if (key && byKey[key]) {
        byKey[key].items.push(item);
      } else {
        unmatched.push(item);
      }
    });
    if (unmatched.length) {
      cards.push({ key: "__unmatched__", title: "محتوى غير مرتبط بقسم رئيسي", items: unmatched, auxiliary: true });
    }
    return cards;
  }

  function contentFileTypeLabel(fileType) {
    if (fileType === "video") return "فيديو";
    if (fileType === "document") return "PDF";
    return "صورة";
  }

  function buildContentItemPreview(item) {
    var fileUrl = escapeHtml(item.fileUrl || "");
    var previewUrl = escapeHtml(item.thumbnailUrl || item.fileUrl || "");
    if (item.fileType === "video") {
      return '<video class="pe-content-item-video" src="' + fileUrl + '" controls preload="metadata"></video>';
    }
    if (item.fileType === "document") {
      return '<div class="pe-content-item-doc">' +
        '<span class="pe-content-item-doc-icon" aria-hidden="true">PDF</span>' +
        '<span class="pe-content-item-doc-copy">ملف PDF جاهز للعرض أو الاستبدال</span>' +
      '</div>';
    }
    if (previewUrl) {
      return '<img class="pe-content-item-image" src="' + previewUrl + '" alt="معاينة العنصر" loading="lazy">';
    }
    return '<div class="pe-content-item-doc pe-content-item-doc--empty"><span class="pe-content-item-doc-copy">لا توجد معاينة متاحة</span></div>';
  }

  function buildContentItemCard(item, categoryTitle) {
    return '<article class="pe-content-item" data-item-id="' + item.id + '">' +
      '<div class="pe-content-item-preview">' + buildContentItemPreview(item) + '</div>' +
      '<div class="pe-content-item-meta">' +
        '<span class="pe-content-item-type">' + escapeHtml(contentFileTypeLabel(item.fileType)) + '</span>' +
        (item.fileUrl ? '<a class="pe-content-item-link" href="' + escapeHtml(item.fileUrl) + '" target="_blank" rel="noopener">فتح الملف</a>' : '') +
      '</div>' +
      '<textarea class="form-input pe-content-item-desc" rows="2" placeholder="اكتب وصفًا مختصرًا لهذا الملف">' + escapeHtml(item.description || "") + '</textarea>' +
      '<div class="pe-content-item-actions">' +
        '<button type="button" class="btn btn-primary pe-content-item-save" data-item-id="' + item.id + '" data-category="' + escapeHtml(categoryTitle) + '">حفظ الوصف</button>' +
        '<label class="btn btn-secondary pe-content-item-replace">' +
          '<span class="pe-content-upload-text">استبدال الملف</span>' +
          '<input type="file" class="pe-content-item-replace-input" accept="image/*,video/*,.pdf" hidden data-item-id="' + item.id + '" data-category="' + escapeHtml(categoryTitle) + '">' +
        '</label>' +
        '<button type="button" class="btn btn-light pe-content-item-delete" data-item-id="' + item.id + '">حذف</button>' +
      '</div>' +
    '</article>';
  }

  function buildContentCard(card) {
    return '<section class="detail-card pe-content-card' + (card.auxiliary ? ' is-auxiliary' : '') + '">' +
      '<div class="pe-content-card-head">' +
        '<div>' +
          '<h3 class="pe-content-card-title">' + escapeHtml(card.title) + '</h3>' +
          '<p class="pe-content-card-subtitle">' + (card.auxiliary ? 'هذه العناصر لا تطابق أي تصنيف رئيسي محفوظ حاليًا.' : 'يمكنك رفع صور أو فيديوهات أو ملفات PDF وربطها بهذا التصنيف مباشرة.') + '</p>' +
        '</div>' +
        '<span class="pe-content-card-count">' + card.items.length + ' عنصر</span>' +
      '</div>' +
      (!card.auxiliary ? ('<label class="btn btn-secondary pe-content-upload">' +
        '<span class="pe-content-upload-text">إضافة ملفات</span>' +
        '<input type="file" class="pe-content-upload-input" accept="image/*,video/*,.pdf" multiple hidden data-category="' + escapeHtml(card.title) + '">' +
      '</label>') : '') +
      (card.items.length
        ? ('<div class="pe-content-items-grid">' + card.items.map(function (item) { return buildContentItemCard(item, card.title); }).join('') + '</div>')
        : '<div class="pe-content-card-empty">لا توجد ملفات داخل هذا التصنيف بعد. ارفع أول صورة أو فيديو أو PDF للبدء.</div>') +
    '</section>';
  }

  function buildContentSummary() {
    var cards = buildContentCardsData();
    if (!cards.length) {
      return '<section class="detail-card pe-content-empty-state">' +
        '<strong>أضف التصنيفات الرئيسية أولًا</strong>' +
        '<p>بمجرد اختيار الأقسام الرئيسية في تفاصيل الخدمة، سيظهر هنا كرت مستقل لكل قسم لتدير ملفاته من نفس الصفحة.</p>' +
      '</section>';
    }
    return '<section class="pe-content-manager">' + cards.map(buildContentCard).join('') + '</section>';
  }

  function setContentFileControlBusy(input, isBusy, busyLabel) {
    if (!input) return;
    var label = input.closest('label');
    var text = label ? label.querySelector('.pe-content-upload-text') : null;
    if (label) label.classList.toggle('is-loading', !!isBusy);
    input.disabled = !!isBusy;
    if (text) {
      if (!text.dataset.defaultLabel) text.dataset.defaultLabel = text.textContent;
      text.textContent = isBusy ? busyLabel : text.dataset.defaultLabel;
    }
  }

  function setContentButtonBusy(button, isBusy, busyLabel) {
    if (!button) return;
    if (!button.dataset.defaultLabel) button.dataset.defaultLabel = button.textContent;
    button.disabled = !!isBusy;
    button.classList.toggle('is-loading', !!isBusy);
    button.textContent = isBusy ? busyLabel : button.dataset.defaultLabel;
  }

  function inferContentUploadType(file) {
    var mime = String(file && file.type || '').trim().toLowerCase();
    var name = String(file && file.name || '').trim().toLowerCase();
    if (mime.indexOf('video/') === 0 || /\.(mp4|mov|avi|webm|mkv|m4v)$/.test(name)) return 'video';
    if (mime.indexOf('image/') === 0 || /\.(jpg|jpeg|png|webp|gif|bmp|svg)$/.test(name)) return 'image';
    if (mime === 'application/pdf' || /\.pdf$/.test(name)) return 'document';
    return '';
  }

  function refreshContentSection(message, type, title) {
    return optionalGet('/api/providers/me/portfolio/').then(function (resp) {
      portfolioItems = resp.ok && resp.data ? normalizeContentPortfolioList(resp.data) : [];
      renderFocusedSection('content');
      renderSectionLinks('content');
      if (message) showProfileToast(message, type || 'success', title || 'تم الحفظ');
    });
  }

  function uploadContentFiles(categoryTitle, files, input) {
    var selectedFiles = Array.prototype.slice.call(files || []);
    if (!selectedFiles.length) return;
    var invalid = selectedFiles.find(function (file) {
      return !inferContentUploadType(file);
    });
    if (invalid) {
      showProfileToast('الملفات المدعومة هنا هي: صورة، فيديو، أو PDF فقط.', 'error', 'نوع ملف غير مدعوم');
      return;
    }
    setContentFileControlBusy(input, true, 'جار الرفع...');
    Promise.all(selectedFiles.map(function (file) {
      var fileType = inferContentUploadType(file);
      var formData = new FormData();
      formData.append('file', file);
      formData.append('file_type', fileType);
      formData.append('caption', buildContentItemCaption(categoryTitle, ''));
      return safeFormRequest('/api/providers/me/portfolio/', 'POST', formData).then(function (resp) {
        if (!resp || !resp.ok) {
          throw new Error(apiErrorMessage(resp ? resp.data : null, 'تعذر رفع بعض الملفات'));
        }
        return resp;
      });
    })).then(function () {
      return refreshContentSection('تم رفع الملفات داخل هذا التصنيف.', 'success', 'تم الرفع');
    }).catch(function (err) {
      showProfileToast((err && err.message) ? err.message : 'تعذر رفع الملفات', 'error', 'فشل الرفع');
    }).finally(function () {
      if (input) input.value = '';
      setContentFileControlBusy(input, false, 'جار الرفع...');
    });
  }

  function replaceContentItemFile(itemId, categoryTitle, file, input) {
    var fileType = inferContentUploadType(file);
    if (!fileType) {
      showProfileToast('الملفات المدعومة هنا هي: صورة، فيديو، أو PDF فقط.', 'error', 'نوع ملف غير مدعوم');
      return;
    }
    var card = input ? input.closest('.pe-content-item') : null;
    var descInput = card ? card.querySelector('.pe-content-item-desc') : null;
    var formData = new FormData();
    formData.append('file', file);
    formData.append('file_type', fileType);
    formData.append('caption', buildContentItemCaption(categoryTitle, descInput ? descInput.value : ''));
    setContentFileControlBusy(input, true, 'جار الاستبدال...');
    safeFormRequest('/api/providers/me/portfolio/' + itemId + '/', 'PATCH', formData).then(function (resp) {
      if (!resp || !resp.ok) {
        throw new Error(apiErrorMessage(resp ? resp.data : null, 'تعذر استبدال الملف'));
      }
      return refreshContentSection('تم استبدال الملف بنجاح.', 'success', 'تم التحديث');
    }).catch(function (err) {
      showProfileToast((err && err.message) ? err.message : 'تعذر استبدال الملف', 'error', 'فشل التحديث');
    }).finally(function () {
      if (input) input.value = '';
      setContentFileControlBusy(input, false, 'جار الاستبدال...');
    });
  }

  function saveContentItemDescription(button) {
    var card = button ? button.closest('.pe-content-item') : null;
    var descInput = card ? card.querySelector('.pe-content-item-desc') : null;
    var itemId = button ? button.getAttribute('data-item-id') : '';
    var categoryTitle = button ? button.getAttribute('data-category') : '';
    setContentButtonBusy(button, true, 'جار الحفظ...');
    safePatch('/api/providers/me/portfolio/' + itemId + '/', {
      caption: buildContentItemCaption(categoryTitle, descInput ? descInput.value : '')
    }).then(function (resp) {
      if (!resp || !resp.ok) {
        throw new Error(apiErrorMessage(resp ? resp.data : null, 'تعذر حفظ الوصف'));
      }
      return refreshContentSection('تم تحديث وصف الملف.', 'success', 'تم الحفظ');
    }).catch(function (err) {
      showProfileToast((err && err.message) ? err.message : 'تعذر حفظ الوصف', 'error', 'فشل الحفظ');
    }).finally(function () {
      setContentButtonBusy(button, false, 'جار الحفظ...');
    });
  }

  function deleteContentItem(button) {
    var itemId = button ? button.getAttribute('data-item-id') : '';
    if (!itemId) return;
    if (!window.confirm('سيتم حذف هذا الملف من محتوى أعمالك. هل تريد المتابعة؟')) return;
    setContentButtonBusy(button, true, 'جار الحذف...');
    safeDelete('/api/providers/me/portfolio/' + itemId + '/').then(function (resp) {
      if (!resp || !resp.ok) {
        throw new Error(apiErrorMessage(resp ? resp.data : null, 'تعذر حذف الملف'));
      }
      return refreshContentSection('تم حذف الملف من محتوى أعمالك.', 'success', 'تم الحذف');
    }).catch(function (err) {
      showProfileToast((err && err.message) ? err.message : 'تعذر حذف الملف', 'error', 'فشل الحذف');
    }).finally(function () {
      setContentButtonBusy(button, false, 'جار الحذف...');
    });
  }

  function initContentManager(panel) {
    if (!panel || panel.dataset.contentManagerBound === '1') return;
    panel.dataset.contentManagerBound = '1';
    panel.addEventListener('click', function (event) {
      var saveButton = event.target.closest('.pe-content-item-save');
      if (saveButton) {
        event.preventDefault();
        saveContentItemDescription(saveButton);
        return;
      }
      var deleteButton = event.target.closest('.pe-content-item-delete');
      if (deleteButton) {
        event.preventDefault();
        deleteContentItem(deleteButton);
      }
    });
    panel.addEventListener('change', function (event) {
      var uploadInput = event.target.closest('.pe-content-upload-input');
      if (uploadInput) {
        uploadContentFiles(uploadInput.getAttribute('data-category') || '', uploadInput.files, uploadInput);
        return;
      }
      var replaceInput = event.target.closest('.pe-content-item-replace-input');
      if (replaceInput && replaceInput.files && replaceInput.files[0]) {
        replaceContentItemFile(replaceInput.getAttribute('data-item-id') || '', replaceInput.getAttribute('data-category') || '', replaceInput.files[0], replaceInput);
      }
    });
  }

  function renderStandardPanels() {
    Object.keys(TABS).forEach(function (tab) {
      var panel = document.getElementById("pe-panel-" + tab);
      panel.innerHTML = TABS[tab].map(function (f) {
        return buildField(f);
      }).join("");
    });
  }

  function renderFocusedSection(sectionKey) {
    var cfg = SECTION_CONFIG[sectionKey];
    Object.keys(TABS).forEach(function (tab) {
      var panel = document.getElementById("pe-panel-" + tab);
      if (!panel) return;
      panel.innerHTML = "";
      panel.classList.remove("active");
      panel.setAttribute("hidden", "hidden");
    });
    if (!cfg) return;
    var targetPanel = document.getElementById("pe-panel-" + cfg.tab);
    if (!targetPanel) return;
    targetPanel.classList.add("active");
    targetPanel.removeAttribute("hidden");
    if (cfg.mode === "summary") {
      if (sectionKey === "content") {
        initContentManager(targetPanel);
        targetPanel.innerHTML = buildContentSummary();
        return;
      }
      targetPanel.innerHTML = buildBasicSummary();
      return;
    }
    targetPanel.innerHTML = cfg.fields.map(function (fieldKey) {
      var cfgField = fieldConfig(fieldKey);
      return cfgField && cfgField.key ? buildField(cfgField) : "";
    }).join("");
  }

  function iconSvg(name) {
    switch (String(name || "")) {
      case "person":
        return '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>';
      case "badge":
        return '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 15l-3.5 2 1-4L6 9.5l4.2-.3L12 5l1.8 4.2L18 9.5 14.5 13l1 4z"/><path d="M8 17v3l4-2 4 2v-3"/></svg>';
      case "info":
        return '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/></svg>';
      case "category":
        return '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/></svg>';
      case "work":
        return '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="2" y="7" width="20" height="14" rx="2"/><path d="M16 7V5a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v2"/></svg>';
      case "language":
        return '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 5h12"/><path d="M10 5a17.3 17.3 0 0 1-4 12"/><path d="M12 17h8"/><path d="M16 5l4 12"/><path d="M18 11h-4"/></svg>';
      case "location":
        return '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z"/><circle cx="12" cy="10" r="3"/></svg>';
      case "map_pin":
        return '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 21s-6-4.35-6-10a6 6 0 1 1 12 0c0 5.65-6 10-6 10z"/><circle cx="12" cy="11" r="2.5"/></svg>';
      case "radius":
        return '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3"/><path d="M12 2v2"/><path d="M12 20v2"/><path d="M2 12h2"/><path d="M20 12h2"/></svg>';
      case "my_location":
        return '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 2v4"/><path d="M12 18v4"/><path d="M2 12h4"/><path d="M18 12h4"/><circle cx="12" cy="12" r="4"/></svg>';
      case "explore":
        return '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><polygon points="16 8 14 14 8 16 10 10 16 8"/></svg>';
      case "notes":
        return '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6"/><path d="M8 13h8"/><path d="M8 17h5"/></svg>';
      case "school":
        return '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M22 10L12 5 2 10l10 5 10-5z"/><path d="M6 12v5c3 2 9 2 12 0v-5"/></svg>';
      case "link":
        return '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M10 13a5 5 0 0 0 7.54.54l2.92-2.92a5 5 0 0 0-7.07-7.07L11.7 5.24"/><path d="M14 11a5 5 0 0 0-7.54-.54l-2.92 2.92a5 5 0 1 0 7.07 7.07l1.67-1.67"/></svg>';
      case "share":
        return '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="18" cy="5" r="3"/><circle cx="6" cy="12" r="3"/><circle cx="18" cy="19" r="3"/><path d="M8.59 13.51l6.83 3.98"/><path d="M15.41 6.51L8.59 10.49"/></svg>';
      case "linkedin":
        return '<svg width="18" height="18" viewBox="0 0 24 24" fill="none"><rect x="3" y="3" width="18" height="18" rx="4" fill="#0A66C2"/><path d="M8.1 10.2h2.3V18H8.1zm1.16-1.23a1.33 1.33 0 1 1 0-2.66 1.33 1.33 0 0 1 0 2.66zM12 10.2h2.2v1.07h.03c.31-.58 1.06-1.2 2.18-1.2 2.33 0 2.76 1.53 2.76 3.53V18h-2.3v-3.91c0-.93-.02-2.13-1.3-2.13-1.3 0-1.5 1.01-1.5 2.06V18H12z" fill="#fff"/></svg>';
      case "youtube":
        return '<svg width="18" height="18" viewBox="0 0 24 24" fill="none"><rect x="3" y="6" width="18" height="12" rx="4" fill="#FF0000"/><path d="M10 9.5l5 2.5-5 2.5z" fill="#fff"/></svg>';
      case "instagram":
        return '<svg width="18" height="18" viewBox="0 0 24 24" fill="none"><rect x="3" y="3" width="18" height="18" rx="5" stroke="#E1306C" stroke-width="2"/><circle cx="12" cy="12" r="4" stroke="#E1306C" stroke-width="2"/><circle cx="17.5" cy="6.5" r="1.4" fill="#E1306C"/></svg>';
      case "x":
        return '<svg width="18" height="18" viewBox="0 0 24 24" fill="#111"><path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z"/></svg>';
      case "snapchat":
        return '<svg width="18" height="18" viewBox="0 0 24 24" fill="none"><path d="M12 3c3.06 0 5.2 2.26 5.2 5.14 0 .8-.19 1.51-.56 2.16.36.56.93 1 1.73 1.34.31.13.49.43.43.77-.06.36-.34.62-.69.68-.56.09-.99.17-1.37.28-.43 1-1.12 1.82-2.02 2.38-.22.13-.49.13-.71 0-.9-.56-1.59-1.38-2.02-2.38-.38-.11-.81-.19-1.37-.28-.35-.06-.63-.32-.69-.68-.06-.34.12-.64.43-.77.8-.34 1.37-.78 1.73-1.34-.37-.65-.56-1.36-.56-2.16C6.8 5.26 8.94 3 12 3z" fill="#FFFC00" stroke="#111" stroke-width="1.2"/></svg>';
      case "facebook":
        return '<svg width="18" height="18" viewBox="0 0 24 24" fill="none"><path d="M13.5 21v-7h2.4l.36-2.8H13.5V9.42c0-.81.23-1.36 1.39-1.36H16.4V5.56c-.26-.03-1.14-.11-2.18-.11-2.16 0-3.64 1.32-3.64 3.74v2.01H8.2V14h2.38v7h2.92z" fill="#1877F2"/></svg>';
      case "pinterest":
        return '<svg width="18" height="18" viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="9" fill="#E60023"/><path d="M12.34 17.78c-.9 0-1.75-.48-2.04-1.03l-.58 2.24-.04.13c-.1.36-.42.61-.8.61H8l1.12-4.41c-.2-.52-.32-1.18-.32-1.82 0-2.35 1.73-4.11 4.09-4.11 2.05 0 3.39 1.46 3.39 3.3 0 2.26-1 4.09-2.55 4.09-.8 0-1.4-.67-1.22-1.48.24-.97.7-2.01.7-2.71 0-.62-.33-1.14-1.01-1.14-.8 0-1.44.83-1.44 1.94 0 .71.24 1.19.24 1.19l-.98 4.15c.72.22 1.5.34 2.31.34" fill="#fff"/></svg>';
      case "tiktok":
        return '<svg width="18" height="18" viewBox="0 0 24 24" fill="none"><path d="M14.5 3c.4 1.77 1.45 3.14 3.19 3.73v2.58a6.55 6.55 0 0 1-3.11-1v5.64a5.45 5.45 0 1 1-5.45-5.45c.3 0 .6.03.88.08v2.71a2.74 2.74 0 1 0 1.86 2.59V3h2.63z" fill="#111"/><path d="M14.5 3c.4 1.77 1.45 3.14 3.19 3.73" stroke="#25F4EE" stroke-width="1.2"/><path d="M12.64 13.88a2.74 2.74 0 1 1-2.63-3.45" stroke="#FE2C55" stroke-width="1.2"/></svg>';
      case "behance":
        return '<svg width="18" height="18" viewBox="0 0 24 24" fill="none"><rect x="3" y="5" width="18" height="14" rx="4" fill="#1769FF"/><path d="M8.2 10.1h2.42c.98 0 1.68.55 1.68 1.44 0 .75-.42 1.18-.94 1.32v.03c.74.11 1.21.7 1.21 1.56 0 1.05-.78 1.84-2.09 1.84H8.2zm1.41 2.48h.85c.46 0 .74-.23.74-.63 0-.39-.28-.62-.74-.62h-.85zm0 2.72h1.01c.54 0 .87-.27.87-.74s-.33-.73-.87-.73H9.61zM15.18 10.37h2.84v.68h-2.84zm3.23 4.18c-.08 1.29-1.1 2.11-2.56 2.11-1.68 0-2.72-1.1-2.72-2.88 0-1.77 1.05-2.91 2.68-2.91 1.6 0 2.59 1.08 2.59 2.82v.42h-3.87c.02.86.52 1.38 1.3 1.38.56 0 .96-.24 1.08-.94zm-3.79-1.29h2.47c-.03-.77-.47-1.22-1.18-1.22-.7 0-1.18.47-1.29 1.22z" fill="#fff"/></svg>';
      case "email":
        return '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#2563EB" stroke-width="2"><rect x="3" y="5" width="18" height="14" rx="2"/><path d="M4 7l8 6 8-6"/></svg>';
      case "phone":
        return '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72 12.84 12.84 0 0 0 .7 2.81 2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7A2 2 0 0 1 22 16.92z"/></svg>';
      case "label":
        return '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M20.59 13.41L11 3H4v7l9.59 9.59a2 2 0 0 0 2.82 0l4.18-4.18a2 2 0 0 0 0-2.82z"/><circle cx="7.5" cy="7.5" r="1.5"/></svg>';
      case "search":
        return '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/></svg>';
      case "image":
        return '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="4" width="18" height="16" rx="2"/><circle cx="8.5" cy="9" r="1.5"/><path d="M21 15l-5-5L5 20"/></svg>';
      case "headline":
        return '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 6h16"/><path d="M4 12h16"/><path d="M4 18h10"/></svg>';
      default:
        return '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/></svg>';
    }
  }

  function displayValue(value, field) {
    if (value === null || value === undefined || value === "") {
      return '<span class="pe-empty-value">لم تتم إضافة هذه المعلومة بعد</span>';
    }
    if (field && field.key === "details") {
      return '<div class="pe-additional-story-copy">' + escapeHtml(value).replace(/\n/g, "<br>") + '</div>';
    }
    if (field && field.key === "qualification") {
      return '<div class="pe-additional-tag-wrap">' + renderAdditionalTags(additionalEntries(value), 'qualification') + '</div>';
    }
    if (field && field.key === "experiences") {
      return renderAdditionalList(additionalEntries(value), 'لم تتم إضافة خبرات عملية بعد');
    }
    if (field && field.key === "accountType") {
      return escapeHtml(TYPE_LABELS[value] || value);
    }
    if (field && field.key === "keywords") {
      return '<div class="pe-seo-keywords">' + renderSeoKeywordChips(value) + '</div>';
    }
    var safeValue = escapeHtml(value);
    if (field && field.key === "experience") {
      return safeValue + ' سنوات';
    }
    if (field && field.key === "coverageRadius") {
      return safeValue + ' كم';
    }
    if (field && field.key === "seoSlug") {
      return '<span class="pe-seo-slug-display">' + escapeHtml(buildProviderPublicPath(value)) + '</span>';
    }
    if (field && (field.key === "phone" || field.key === "mobilePhone")) {
      return '<a class="pe-inline-link" href="tel:' + safeValue + '">' + safeValue + '</a>';
    }
    if (field && field.inputType === "email") {
      return '<a class="pe-inline-link" href="mailto:' + safeValue + '">' + safeValue + '</a>';
    }
    if (field && (field.key === "website" || field.inputType === "url")) {
      var href = /^https?:\/\//i.test(String(value || "")) ? safeValue : ('https://' + safeValue);
      return '<a class="pe-inline-link" href="' + href + '" target="_blank" rel="noopener noreferrer">' + safeValue + '</a>';
    }
    return field && field.multiline ? safeValue.replace(/\n/g, "<br>") : safeValue;
  }

  function renderAdditionalLinksSummary() {
    var items = sanitizeSocialExtraItems(profile && profile.socialExtras);
    if (!items.length) return '<span class="pe-empty-value">لم تتم إضافة روابط إضافية بعد</span>';
    return '<div class="pe-additional-links-summary">' + items.map(function (item) {
      var label = item.label || guessSocialLinkLabel(item.platform, item.url);
      var display = normalizeSocialDisplayValue(item.platform, item.url).replace(/^https?:\/\//i, '').replace(/\/$/, '');
      return '<div class="pe-additional-link-chip"><strong>' + escapeHtml(label) + '</strong><span>' + escapeHtml(display) + '</span></div>';
    }).join('') + '</div>';
  }

  function buildAdditionalLinksRow(item) {
    var normalized = normalizeSocialLinkObject(item) || { label: '', url: '' };
    return '<div class="pe-additional-link-row">' +
      '<input type="text" class="form-input pe-additional-link-label" placeholder="اسم المنصة أو الموقع" value="' + escapeHtml(normalized.label || '') + '">' +
      '<input type="url" class="form-input pe-additional-link-url" placeholder="https://example.com/profile" value="' + escapeHtml(normalized.url || '') + '" dir="ltr" inputmode="url" autocomplete="url">' +
      '<button type="button" class="btn btn-secondary pe-additional-links-remove">حذف</button>' +
    '</div>';
  }

  function renderAdditionalLinksRows(items) {
    var rows = sanitizeSocialExtraItems(items);
    if (!rows.length) rows = [{ label: '', url: '' }];
    return rows.map(function (item) {
      return buildAdditionalLinksRow(item);
    }).join('');
  }

  function appendAdditionalLinksRow(item) {
    var rows = document.getElementById('pe-additional-links-rows');
    if (!rows) return;
    rows.insertAdjacentHTML('beforeend', buildAdditionalLinksRow(item || {}));
  }

  function buildAdditionalLinksField(f) {
    return '<article class="pe-field pe-field-wide pe-additional-links-field" data-key="' + f.key + '">' +
      '<div class="pe-field-head">' +
        '<div class="pe-field-title-wrap">' +
          '<span class="pe-field-icon" aria-hidden="true">' + iconSvg(f.icon) + '</span>' +
          '<div class="pe-field-copy">' +
            '<span class="pe-field-label">' + f.label + '</span>' +
            (f.hint ? '<span class="pe-field-hint">' + escapeHtml(f.hint) + '</span>' : '') +
          '</div>' +
        '</div>' +
        '<button type="button" class="pe-edit-btn" data-key="' + f.key + '" aria-label="تحرير ' + escapeHtml(f.label) + '"><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/></svg></button>' +
      '</div>' +
      '<div class="pe-field-display">' + renderAdditionalLinksSummary() + '</div>' +
      '<div class="pe-field-edit" style="display:none">' +
        '<div class="pe-additional-links-editor">' +
          '<div class="pe-additional-links-note">أضف أي رابط إضافي تريد ظهوره في ملفك العام، مع اسم واضح يساعد العميل على فهم الوجهة.</div>' +
          '<div class="pe-additional-links-rows" id="pe-additional-links-rows">' + renderAdditionalLinksRows(profile.socialExtras) + '</div>' +
          '<button type="button" class="btn btn-secondary pe-additional-links-add-btn">إضافة رابط آخر</button>' +
          '<div class="pe-field-actions">' +
            '<button type="button" class="btn btn-primary pe-save-btn" data-key="' + f.key + '">حفظ</button>' +
          '</div>' +
        '</div>' +
      '</div>' +
    '</article>';
  }

  function buildSeoPreviewField(f) {
    var preview = buildSeoPreviewState();
    return '<article class="pe-field pe-field-wide pe-seo-preview-field" data-key="' + f.key + '">' +
      '<div class="pe-field-head">' +
        '<div class="pe-field-title-wrap">' +
          '<span class="pe-field-icon" aria-hidden="true">' + iconSvg(f.icon) + '</span>' +
          '<div class="pe-field-copy">' +
            '<span class="pe-field-label">' + f.label + '</span>' +
            '<span class="pe-field-hint">هذه المعاينة توضح كيف قد تظهر صفحتك في نتائج البحث وعند المشاركة.</span>' +
          '</div>' +
        '</div>' +
      '</div>' +
      '<div class="pe-seo-preview-shell">' +
        '<div class="pe-seo-search-card">' +
          '<div class="pe-seo-search-title" id="pe-seo-preview-title">' + escapeHtml(preview.title + ' | نوافــذ') + '</div>' +
          '<div class="pe-seo-search-url" id="pe-seo-preview-url">' + escapeHtml(preview.path) + '</div>' +
          '<p class="pe-seo-search-description" id="pe-seo-preview-description">' + escapeHtml(preview.description) + '</p>' +
        '</div>' +
        '<div class="pe-seo-metric-grid">' +
          '<div class="pe-seo-metric-card"><strong id="pe-seo-counter-seoTitle">0 حرف</strong><span id="pe-seo-advice-seoTitle">الطول المناسب يحسن الظهور.</span></div>' +
          '<div class="pe-seo-metric-card"><strong id="pe-seo-counter-seoMetaDescription">0 حرف</strong><span id="pe-seo-advice-seoMetaDescription">الوصف يشرح الخدمة بإيجاز.</span></div>' +
          '<div class="pe-seo-metric-card"><strong id="pe-seo-counter-seoSlug">0 حرف</strong><span id="pe-seo-advice-seoSlug">الرابط المختصر يسهل القراءة والمشاركة.</span></div>' +
          '<div class="pe-seo-metric-card"><strong id="pe-seo-counter-keywords">0 كلمة</strong><span id="pe-seo-advice-keywords">اختر كلمات مرتبطة مباشرة بخدمتك.</span></div>' +
        '</div>' +
        '<div class="pe-seo-keywords-wrap">' +
          '<div class="pe-seo-keywords-label">الكلمات المفتاحية الحالية</div>' +
          '<div class="pe-seo-keywords" id="pe-seo-preview-keywords">' + renderSeoKeywordChips(preview.keywords) + '</div>' +
        '</div>' +
        '<p class="pe-seo-preview-note" id="pe-seo-preview-note"></p>' +
      '</div>' +
    '</article>';
  }

  function buildSeoFieldMeta(f) {
    var counterLabel = f.seoMetric === "keywords" ? "0 كلمة" : "0 حرف";
    return '<div class="pe-seo-field-meta">' +
      '<span class="pe-seo-counter" id="pe-seo-counter-' + f.key + '">' + counterLabel + '</span>' +
      '<span class="pe-seo-advice" id="pe-seo-advice-' + f.key + '"></span>' +
      (f.key === "seoSlug" ? '<span class="pe-seo-slug-preview" id="pe-seo-slug-preview"></span>' : '') +
    '</div>';
  }

  function setFieldEditingState(field, editing) {
    if (!field) return;
    var display = field.querySelector(".pe-field-display");
    var editBlock = field.querySelector(".pe-field-edit");
    var editBtn = field.querySelector(".pe-edit-btn");
    if (display) display.style.display = editing ? "none" : "";
    if (editBlock) editBlock.style.display = editing ? "" : "none";
    if (editBtn) editBtn.style.display = editing ? "none" : "";
    field.classList.toggle("is-editing", !!editing);
  }

  function closeAllEditors(exceptKey) {
    document.querySelectorAll(".pe-field").forEach(function (field) {
      if (exceptKey && field.dataset.key === exceptKey) return;
      setFieldEditingState(field, false);
    });
  }

  function updateSectionHelper(tabName) {
    var meta = TAB_META[tabName] || TAB_META.account;
    if (initialSection && SECTION_META[initialSection]) {
      meta = SECTION_META[initialSection];
    }
    var labelNode = document.getElementById("pe-section-label");
    var summaryNode = document.getElementById("pe-section-summary");
    if (labelNode) labelNode.textContent = meta.label;
    if (summaryNode) summaryNode.textContent = meta.summary;

    var workflowMeta = TAB_WORKFLOW[tabName] || TAB_WORKFLOW.account;
    if (initialSection && SECTION_CONFIG[initialSection]) {
      workflowMeta = {
        action: "الخطوة الحالية: " + (SECTION_CONFIG[initialSection].heading || meta.label),
        hint: SECTION_CONFIG[initialSection].intro || (TAB_WORKFLOW[tabName] && TAB_WORKFLOW[tabName].hint) || ""
      };
    }

    var actionNode = document.getElementById("pe-current-action");
    var hintNode = document.getElementById("pe-current-hint");
    if (actionNode) actionNode.textContent = workflowMeta.action || "";
    if (hintNode) hintNode.textContent = workflowMeta.hint || "";

    document.querySelectorAll(".pe-workflow-step").forEach(function (step) {
      var target = String(step.getAttribute("data-tab-target") || "").trim();
      var isActive = target === tabName;
      step.classList.toggle("is-active", isActive);
      if (isActive) {
        step.setAttribute("aria-current", "step");
      } else {
        step.removeAttribute("aria-current");
      }
    });
  }

  function formatCoord(value) {
    if (value === null || value === undefined || value === "") return "";
    var parsed = Number(value);
    if (!isFinite(parsed)) return "";
    return parsed.toFixed(6).replace(/0+$/, "").replace(/\.$/, "");
  }

  function setFieldValue(key, value) {
    profile[key] = value === null || value === undefined ? "" : String(value);
    if (key === "location") {
      var scope = splitLocationScope(profile[key], profile && (profile.locationCountry || profile.locationRegion));
      profile.locationCountry = scope.region || profile.locationCountry || "";
      profile.locationRegion = scope.region;
      profile.locationCity = scope.city;
      profile.location = buildProfileLocationLabel(profile.locationCountry, profile.locationCity) || String(profile[key] || "");
    }
    var field = document.querySelector('.pe-field[data-key="' + key + '"]');
    if (!field) {
      if (isSeoFieldKey(key)) {
        updateSeoFieldFeedback(key);
        updateSeoPreview();
      }
      return;
    }
    var cfg = fieldConfig(key);
    var display = field.querySelector(".pe-field-display");
    if (display) display.innerHTML = key === 'additionalLinks' ? renderAdditionalLinksSummary() : displayValue(profile[key], cfg);
    var input = field.querySelector('.pe-input[data-key="' + key + '"]');
    if (input) input.value = profile[key];

    if (key === "languages") {
      var summary = document.getElementById("pe-language-summary");
      if (summary) {
        summary.innerHTML = profile.languages
          ? escapeHtml(profile.languages)
          : '<span class="pe-empty-value">لم تتم إضافة هذه المعلومة بعد</span>';
      }
    }

    if (key === 'additionalLinks') {
      var rows = document.getElementById('pe-additional-links-rows');
      if (rows) rows.innerHTML = renderAdditionalLinksRows(profile.socialExtras);
    }

    if (key === "location") {
      var countryInput = document.querySelector(".pe-location-country-input");
      if (countryInput) countryInput.value = profile.locationCountry || "";
      syncProfileLocationLabels(profile.locationCountry || "", profile.locationCity || "");
      var cityLabel = document.querySelector(".pe-map-city");
      if (cityLabel) cityLabel.textContent = "المنطقة الحالية: " + (profile.location || "غير محددة");
      centerServiceMapOnCity(!hasPreciseCoordinates());
    }

    if (key === "coverageRadius") {
      syncRadiusInputs(profile.coverageRadius || 0);
    }

    if (isSeoFieldKey(key)) {
      updateSeoFieldFeedback(key);
      updateSeoPreview();
    }

    if (key === "details" || key === "qualification" || key === "experiences") {
      refreshAdditionalOverview();
    }

    if (key === "languages" || key === "serviceLocation" || key === "coverageRadius" || key === "location") {
      refreshLangLocOverview();
    }

    if (isSectionFlowActive()) {
      renderSectionLinks(initialSection);
      updateSectionHelper((SECTION_CONFIG[initialSection] && SECTION_CONFIG[initialSection].tab) || "account");
    }
  }

  function safeGet(path) {
    if (RAW_API && typeof RAW_API.get === "function") {
      return RAW_API.get(path);
    }
    return API.get(path).then(function (data) {
      return { ok: !!data, status: data ? 200 : 0, data: data };
    });
  }

  function optionalGet(path) {
    return safeGet(path).catch(function () {
      return { ok: false, status: 0, data: null };
    });
  }

  function safePut(path, body) {
    if (RAW_API && typeof RAW_API.request === "function") {
      return RAW_API.request(path, { method: "PUT", body: body });
    }
    if (API && typeof API.request === "function") {
      return API.request(path, { method: "PUT", body: body }).then(function (data) {
        return { ok: !!data, status: data ? 200 : 0, data: data };
      });
    }
    return fetch(path, {
      method: "PUT",
      headers: {
        "Content-Type": "application/json",
        "X-CSRFToken": getCsrfToken()
      },
      credentials: "same-origin",
      body: JSON.stringify(body || {})
    }).then(function (resp) {
      return resp.json().catch(function () { return null; }).then(function (data) {
        return { ok: resp.ok, status: resp.status, data: data };
      });
    });
  }

  function safePost(path, body) {
    if (RAW_API && typeof RAW_API.request === "function") {
      return RAW_API.request(path, { method: "POST", body: body });
    }
    if (API && typeof API.request === "function") {
      return API.request(path, { method: "POST", body: body }).then(function (data) {
        return { ok: !!data, status: data ? 200 : 0, data: data };
      });
    }
    return fetch(path, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRFToken": getCsrfToken()
      },
      credentials: "same-origin",
      body: JSON.stringify(body || {})
    }).then(function (resp) {
      return resp.json().catch(function () { return null; }).then(function (data) {
        return { ok: resp.ok, status: resp.status, data: data };
      });
    });
  }

  function safeDelete(path) {
    if (RAW_API && typeof RAW_API.request === "function") {
      return RAW_API.request(path, { method: "DELETE" });
    }
    if (API && typeof API.request === "function") {
      return API.request(path, { method: "DELETE" }).then(function (data) {
        return { ok: true, status: 204, data: data || null };
      });
    }
    return fetch(path, {
      method: "DELETE",
      headers: {
        "X-CSRFToken": getCsrfToken()
      },
      credentials: "same-origin"
    }).then(function (resp) {
      return resp.json().catch(function () { return null; }).then(function (data) {
        return { ok: resp.ok, status: resp.status, data: data };
      });
    });
  }

  function safeFormRequest(path, method, formData) {
    if (RAW_API && typeof RAW_API.request === "function") {
      return RAW_API.request(path, { method: method, body: formData, formData: true });
    }
    return fetch(path, {
      method: method,
      headers: {
        "X-CSRFToken": getCsrfToken()
      },
      credentials: "same-origin",
      body: formData
    }).then(function (resp) {
      return resp.json().catch(function () { return null; }).then(function (data) {
        return { ok: resp.ok, status: resp.status, data: data };
      });
    });
  }

  function getCsrfToken() {
    var match = document.cookie.match(/(?:^|; )csrftoken=([^;]+)/);
    return match ? decodeURIComponent(match[1]) : "";
  }

  function safePatch(path, body) {
    if (RAW_API && typeof RAW_API.request === "function") {
      return RAW_API.request(path, { method: "PATCH", body: body });
    }
    return API.patch(path, body).then(function (data) {
      return { ok: !!data, status: data ? 200 : 0, data: data };
    });
  }

  function apiErrorMessage(data, fallback) {
    if (data && typeof data === "object") {
      if (typeof data.detail === "string" && data.detail.trim()) return data.detail.trim();
      var firstKey = Object.keys(data)[0];
      var firstVal = data[firstKey];
      if (typeof firstVal === "string" && firstVal.trim()) return firstVal.trim();
      if (Array.isArray(firstVal) && firstVal.length) return String(firstVal[0]);
    }
    return fallback || "فشل العملية";
  }

  function renderLocalProfileToast(message, type, title) {
    var host = document.getElementById("pe-local-toast-stack");
    if (!host) {
      host = document.createElement("div");
      host.id = "pe-local-toast-stack";
      host.className = "pe-local-toast-stack";
      document.body.appendChild(host);
    }
    var toast = document.createElement("div");
    toast.className = "pe-local-toast is-" + String(type || "success");
    toast.innerHTML =
      '<span class="pe-local-toast-title"></span>' +
      '<span class="pe-local-toast-message"></span>';
    var titleEl = toast.querySelector(".pe-local-toast-title");
    var messageEl = toast.querySelector(".pe-local-toast-message");
    if (titleEl) titleEl.textContent = String(title || "تنبيه").trim();
    if (messageEl) messageEl.textContent = String(message || "").trim();
    host.appendChild(toast);
    requestAnimationFrame(function () {
      toast.classList.add("is-visible");
    });
    window.setTimeout(function () {
      toast.classList.remove("is-visible");
      window.setTimeout(function () {
        if (toast.parentNode) toast.parentNode.removeChild(toast);
      }, 180);
    }, 3600);
  }

  function showProfileToast(message, type, title) {
    var text = String(message || "").trim();
    if (!text) return;
    if (window.Toast && typeof window.Toast.show === "function") {
      window.Toast.show(text, {
        type: type || "success",
        title: title || "",
        duration: 3600
      });
      return;
    }
    renderLocalProfileToast(text, type || "success", title || "");
  }

  function sanitizePhone(value) {
    return String(value || "").replace(/[^\d]/g, "").slice(0, 10);
  }

  function normalizePhone05(value) {
    var digits = sanitizePhone(value);
    return /^05\d{8}$/.test(digits) ? digits : "";
  }

  function getMobilePhoneOtpBox(field) {
    return field ? field.querySelector(".pe-phone-otp-box") : null;
  }

  function setMobilePhoneOtpStatus(field, message, tone) {
    var box = getMobilePhoneOtpBox(field);
    var status = box ? box.querySelector(".pe-phone-otp-status") : null;
    if (!status) return;
    status.textContent = String(message || "").trim();
    status.className = "pe-phone-otp-status" + (tone ? (" is-" + tone) : "");
  }

  function resetMobilePhoneOtpState(field) {
    pendingPhoneOtp = { phone: "", active: false };
    var box = getMobilePhoneOtpBox(field);
    if (box) {
      var input = box.querySelector(".pe-phone-otp-input");
      var note = box.querySelector(".pe-phone-otp-note");
      if (input) input.value = "";
      if (note) note.textContent = "";
      setMobilePhoneOtpStatus(field, "", "");
      box.classList.add("hidden");
    }
    var saveBtn = field ? field.querySelector('.pe-save-btn[data-key="mobilePhone"]') : null;
    if (saveBtn) saveBtn.textContent = "إرسال الرمز";
  }

  function ensureMobilePhoneOtpUi(field, phone) {
    if (!field) return null;
    var editBlock = field.querySelector(".pe-field-edit");
    var actions = field.querySelector(".pe-field-actions");
    if (!editBlock || !actions) return null;

    var box = getMobilePhoneOtpBox(field);
    if (!box) {
      box = document.createElement("div");
      box.className = "pe-phone-otp-box hidden";
      box.innerHTML =
        '<strong class="pe-phone-otp-title">تأكيد رقم الجوال</strong>' +
        '<span class="pe-phone-otp-note"></span>' +
        '<input type="tel" class="form-input pe-phone-otp-input" maxlength="4" inputmode="numeric" autocomplete="one-time-code" placeholder="XXXX">' +
        '<div class="pe-phone-otp-status" aria-live="polite"></div>';
      editBlock.insertBefore(box, actions);
    }

    var note = box.querySelector(".pe-phone-otp-note");
    var input = box.querySelector(".pe-phone-otp-input");
    if (note) note.textContent = "أرسلنا رمز التحقق إلى الرقم الجديد " + phone + " . أدخله هنا لإتمام التغيير.";
    if (input) {
      input.value = "";
      input.focus();
    }
    box.classList.remove("hidden");
    pendingPhoneOtp = { phone: phone, active: true };
    var saveBtn = field.querySelector('.pe-save-btn[data-key="mobilePhone"]');
    if (saveBtn) saveBtn.textContent = "تأكيد الرمز";
    setMobilePhoneOtpStatus(field, "تم إرسال رمز التحقق. أدخله ثم اضغط تأكيد الرمز.", "info");
    return box;
  }

  function saveMobilePhoneWithOtp(phone, btn, input) {
    var field = document.querySelector('.pe-field[data-key="mobilePhone"]');
    var otpBox = getMobilePhoneOtpBox(field);
    var otpInput = otpBox ? otpBox.querySelector(".pe-phone-otp-input") : null;

    if (pendingPhoneOtp.active && pendingPhoneOtp.phone === phone && otpBox && !otpBox.classList.contains("hidden")) {
      var code = String(otpInput && otpInput.value || "").replace(/[^\d]/g, "").slice(0, 4);
      if (code.length !== 4) {
        setMobilePhoneOtpStatus(field, "أدخل رمز تحقق مكوّنًا من 4 أرقام.", "error");
        showProfileToast("أدخل رمز تحقق مكوّنًا من 4 أرقام", "error", "رمز التحقق");
        if (otpInput) otpInput.focus();
        return Promise.resolve();
      }

      btn.disabled = true;
      btn.textContent = "جاري التحقق...";
      return safePost("/api/accounts/me/confirm-phone-change/", {
        phone: phone,
        code: code
      }).then(function (resp) {
        if (!resp || !resp.ok) {
          throw new Error(apiErrorMessage(resp ? resp.data : null, "فشل تأكيد تغيير رقم الجوال"));
        }

        var responseData = resp.data || {};
        var nextValue = typeof responseData.phone === "string" ? responseData.phone : phone;
        resetMobilePhoneOtpState(field);
        setFieldValue("mobilePhone", nextValue);
        if (userProfile) userProfile.phone = nextValue;
        if (input && input.value !== nextValue) input.value = nextValue;
        if (field) setFieldEditingState(field, false);
        showProfileToast("تم تغيير رقم الجوال بنجاح", "success", "تم الحفظ");
      }).catch(function (err) {
        setMobilePhoneOtpStatus(field, (err && err.message) ? err.message : "تعذر تأكيد تغيير رقم الجوال", "error");
        showProfileToast((err && err.message) ? err.message : "تعذر تأكيد تغيير رقم الجوال", "error", "تعذر الحفظ");
      }).finally(function () {
        btn.disabled = false;
        btn.textContent = pendingPhoneOtp.active ? "تأكيد الرمز" : "إرسال الرمز";
      });
    }

    btn.disabled = true;
    btn.textContent = "إرسال الرمز...";
    return safePost("/api/accounts/me/request-phone-change/", { phone: phone }).then(function (resp) {
      if (!resp || !resp.ok) {
        throw new Error(apiErrorMessage(resp ? resp.data : null, "تعذر إرسال رمز التحقق"));
      }
      ensureMobilePhoneOtpUi(field, phone);
      showProfileToast("تم إرسال رمز التحقق إلى الرقم الجديد", "info", "رمز التحقق");
    }).catch(function (err) {
      setMobilePhoneOtpStatus(field, (err && err.message) ? err.message : "تعذر إرسال رمز التحقق", "error");
      showProfileToast((err && err.message) ? err.message : "تعذر إرسال رمز التحقق", "error", "تعذر الإرسال");
    }).finally(function () {
      btn.disabled = false;
      btn.textContent = pendingPhoneOtp.active ? "تأكيد الرمز" : "إرسال الرمز";
    });
  }

  function loadProfile() {
    Promise.all([
      safeGet("/api/accounts/me/"),
      safeGet("/api/providers/me/profile/"),
      optionalGet("/api/providers/me/services/"),
      optionalGet("/api/providers/categories/"),
      optionalGet("/api/providers/me/subcategories/"),
      optionalGet("/api/providers/me/portfolio/")
    ]).then(function (res) {
      var userResp = res[0] || {};
      var provResp = res[1] || {};
      var servicesResp = res[2] || {};
      var categoriesResp = res[3] || {};
      var providerSubcategoriesResp = res[4] || {};
      var portfolioResp = res[5] || {};
      if (!provResp.ok || !provResp.data) {
        throw new Error("provider_profile_not_found");
      }
      var user = userResp.ok && userResp.data ? userResp.data : {};
      var prov = provResp.data || {};
      providerProfileRaw = prov;
      var languageState = extractLanguageState(prov.languages);
      var socialState = extractSocialState(prov.social_links);
      var locationScope = splitLocationScope(prov.city_display || prov.city || "", prov.country || prov.region || "");
      categoryCatalog = categoriesResp.ok ? normalizeCategoryCatalog(categoriesResp.data) : [];
      applyProviderSubcategoryState(
        providerSubcategoriesResp.ok && providerSubcategoriesResp.data ? providerSubcategoriesResp.data.subcategory_ids : prov.subcategory_ids,
        providerSubcategoriesResp.ok && providerSubcategoriesResp.data ? providerSubcategoriesResp.data.subcategory_settings : [],
        prov.selected_subcategories
      );
      userProfile = user;
      myServices = servicesResp.ok && servicesResp.data ? extractList(servicesResp.data) : [];
      portfolioItems = portfolioResp.ok && portfolioResp.data ? normalizeContentPortfolioList(portfolioResp.data) : [];
      profile = {
        providerId: prov.id || "",
        fullName: prov.display_name || "",
        accountType: prov.provider_type || "",
        about: prov.bio || "",
        specialization: prov.about_details || "",
        experience: prov.years_experience > 0 ? String(prov.years_experience) : "",
        languages: languageState.display || "",
        languageArabic: !!languageState.arabic,
        languageEnglish: !!languageState.english,
        languageOther: !!languageState.other,
        languageOtherText: languageState.otherText || "",
        location: buildProfileLocationLabel(prov.country || locationScope.region, locationScope.city) || String(prov.city_display || prov.city || "").trim(),
        locationCountry: prov.country || locationScope.region || "",
        locationRegion: locationScope.region,
        locationCity: locationScope.city,
        coverageRadius: prov.coverage_radius_km === null || prov.coverage_radius_km === undefined ? "" : String(prov.coverage_radius_km),
        latitude: formatCoord(prov.lat),
        longitude: formatCoord(prov.lng),
        details: prov.about_details || "",
        qualification: Array.isArray(prov.qualifications) ? prov.qualifications.map(function (q) { return q.title || q; }).join("، ") : "",
        experiences: Array.isArray(prov.experiences) ? prov.experiences.map(function (item) { return normalizeListEntry(item, ["title", "name", "label"]); }).filter(Boolean).join("\n") : "",
        website: prov.website || "",
        social: Array.isArray(prov.social_links) ? prov.social_links.map(function (s) { return s.url || s; }).join("\n") : "",
        linkedinUrl: socialState.values.linkedinUrl || "",
        youtubeUrl: socialState.values.youtubeUrl || "",
        facebookUrl: socialState.values.facebookUrl || "",
        instagramUrl: socialState.values.instagramUrl || "",
        xUrl: socialState.values.xUrl || "",
        snapchatUrl: socialState.values.snapchatUrl || "",
        pinterestUrl: socialState.values.pinterestUrl || "",
        tiktokUrl: socialState.values.tiktokUrl || "",
        behanceUrl: socialState.values.behanceUrl || "",
        contactEmail: socialState.values.contactEmail || "",
        socialExtras: sanitizeSocialExtraItems(socialState.extras),
        additionalLinks: socialState.extras && socialState.extras.length ? String(socialState.extras.length) : "",
        mobilePhone: user.phone || "",
        accountEmail: user.email || "",
        phone: prov.whatsapp || user.phone || "",
        seoTitle: prov.seo_title || "",
        keywords: prov.seo_keywords || "",
        seoMetaDescription: prov.seo_meta_description || "",
        seoSlug: prov.seo_slug || ""
      };
      setProfileLocationDraft(prov.lat, prov.lng);
      serviceRadiusDraft = prov.coverage_radius_km === null || prov.coverage_radius_km === undefined
        ? 0
        : clampServiceRadiusKm(prov.coverage_radius_km);
      renderIdentityCard(prov, user);
      renderAll();
      applyEntryNavigation();
      document.getElementById("pe-loading").style.display = "none";
      document.getElementById("pe-content").style.display = "";
      requestAnimationFrame(function () {
        ensureServiceMap();
        if (serviceMap) serviceMap.invalidateSize();
      });
    }).catch(function () {
      document.getElementById("pe-loading").innerHTML = '<p class="text-muted">تعذر تحميل الملف الشخصي</p>';
    });
  }

  function renderAll() {
    if (isSectionFlowActive()) {
      setSectionFlow(true);
      renderSectionLinks(initialSection);
      renderSectionHero(initialSection);
      renderFocusedSection(initialSection);
      bindFieldEvents();
      updateSectionHelper((SECTION_CONFIG[initialSection] && SECTION_CONFIG[initialSection].tab) || "account");
      return;
    }
    setSectionFlow(false);
    renderStandardPanels();
    bindFieldEvents();
    updateSectionHelper(initialTab || "account");
  }

  function buildCategoryPickerField(f) {
    return '<article class="pe-field pe-field-wide pe-category-picker-field" data-key="' + f.key + '">' +
      '<div class="pe-field-head">' +
        '<div class="pe-field-title-wrap">' +
          '<span class="pe-field-icon" aria-hidden="true">' + iconSvg(f.icon) + '</span>' +
          '<div class="pe-field-copy">' +
            '<span class="pe-field-label">' + f.label + '</span>' +
            (f.hint ? '<span class="pe-category-caption">' + escapeHtml(f.hint || '') + '</span>' : '') +
          '</div>' +
        '</div>' +
      '</div>' +
      '<div class="pe-category-note-band">' +
        '<span class="pe-category-note-icon" aria-hidden="true">' + iconSvg("work") + '</span>' +
        '<div class="pe-category-note-copy">' +
          '<strong>ابنِ خارطة تخصصاتك بشكل أدق</strong>' +
          '<span>اختر القسم الرئيسي، ثم أضف التصنيفات الفرعية المناسبة، وحدد لكل تخصص هل يعمل داخل نطاقك الجغرافي فقط أم يمكن تقديمه عن بُعد، مع تفعيل الطلبات العاجلة من أيقونة البرق عند الحاجة.</span>' +
        '</div>' +
      '</div>' +
      '<div class="pe-category-toolbar">' +
        '<button type="button" class="btn btn-secondary pe-category-add-btn" id="pe-category-add-group">إضافة قسم آخر</button>' +
      '</div>' +
      '<div class="pe-category-groups" id="pe-category-groups"></div>' +
      '<div class="pe-field-actions">' +
        '<button type="button" class="btn btn-primary pe-save-btn" data-key="serviceCategories">حفظ التصنيفات</button>' +
      '</div>' +
    '</article>';
  }

  function getCategoryGroupsRoot() {
    return document.getElementById("pe-category-groups");
  }

  function getCategoryGroupCards() {
    return Array.prototype.slice.call(document.querySelectorAll(".pe-category-group"));
  }

  function getCategoryGroupId(groupEl) {
    return groupEl ? String(groupEl.getAttribute("data-group-id") || "") : "";
  }

  function collectGroupSubcategoryIds(groupEl) {
    return uniqueNumeric(Array.prototype.slice.call(groupEl.querySelectorAll(".pe-category-subcheckbox:checked")).map(function (checkbox) {
      return checkbox.value;
    }));
  }

  function collectDraftServiceCategoryIds() {
    return uniqueNumeric([].concat.apply([], getCategoryGroupCards().map(function (groupEl) {
      return collectGroupSubcategoryIds(groupEl);
    })));
  }

  function getSelectedCategoryIds(exceptGroupId) {
    return getCategoryGroupCards().reduce(function (allIds, groupEl) {
      var groupId = getCategoryGroupId(groupEl);
      if (exceptGroupId && groupId === exceptGroupId) return allIds;
      var select = groupEl.querySelector(".pe-category-select");
      var categoryId = parseInt(select && select.value, 10);
      if (isFinite(categoryId)) allIds.push(categoryId);
      return allIds;
    }, []);
  }

  function findGroupByCategoryId(categoryId, exceptGroupId) {
    if (!isFinite(categoryId)) return null;
    var groups = getCategoryGroupCards();
    for (var i = 0; i < groups.length; i++) {
      var groupEl = groups[i];
      if (exceptGroupId && getCategoryGroupId(groupEl) === exceptGroupId) continue;
      var select = groupEl.querySelector(".pe-category-select");
      if (parseInt(select && select.value, 10) === categoryId) return groupEl;
    }
    return null;
  }

  function renderCategoryGroupOptions(select, groupId, selectedCategoryId) {
    if (!select) return;
    var takenIds = getSelectedCategoryIds(groupId);
    select.innerHTML = "";

    var placeholder = document.createElement("option");
    placeholder.value = "";
    placeholder.textContent = "اختر القسم";
    select.appendChild(placeholder);

    categoryCatalog.forEach(function (category) {
      if (takenIds.indexOf(category.id) !== -1 && category.id !== selectedCategoryId) return;
      var option = document.createElement("option");
      option.value = String(category.id);
      option.textContent = category.name;
      if (selectedCategoryId === category.id) option.selected = true;
      select.appendChild(option);
    });
  }

  function renderCategoryGroupSubcategories(groupEl, categoryId, selectedSubcategoryIds) {
    var list = groupEl ? groupEl.querySelector("[data-role='subcategory-list']") : null;
    if (!list) return;
    list.innerHTML = "";

    if (!categoryId) {
      list.innerHTML = '<p class="pe-category-empty">اختر القسم الرئيسي أولًا لتظهر التصنيفات الفرعية التابعة له.</p>';
      return;
    }

    var category = findCategoryById(categoryId);
    var subcategories = category && Array.isArray(category.subcategories) ? category.subcategories : [];
    if (!subcategories.length) {
      list.innerHTML = '<p class="pe-category-empty">لا توجد تصنيفات فرعية متاحة داخل هذا القسم حاليًا.</p>';
      return;
    }

    var selectedLookup = {};
    uniqueNumeric(selectedSubcategoryIds).forEach(function (subId) {
      selectedLookup[subId] = true;
    });

    subcategories.forEach(function (subcategory) {
      var checkbox = document.createElement("input");
      checkbox.type = "checkbox";
      checkbox.className = "pe-category-subcheckbox";
      checkbox.value = String(subcategory.id);
      checkbox.checked = !!selectedLookup[subcategory.id];

      var option = document.createElement("div");
      option.className = "pe-category-option";
      option.setAttribute("data-subcategory-id", String(subcategory.id));
      option.innerHTML =
        '<label class="pe-category-option-check">' +
          '<span class="pe-category-option-control"></span>' +
          '<span class="pe-category-option-copy">' +
            '<strong class="pe-category-option-title"></strong>' +
            '<span class="pe-category-option-status"></span>' +
            '<span class="pe-category-option-scope"></span>' +
            '<span class="pe-category-option-note">ستظهر سياسة النطاق لهذا التخصص تلقائيًا وفق إعدادات المنصة، ويمكنك فقط التحكم في استقبال الطلبات العاجلة إذا كان التصنيف يدعمها.</span>' +
          '</span>' +
        '</label>' +
        '<div class="pe-category-option-actions">' +
          '<button type="button" class="pe-category-urgent-toggle" data-subcategory-id="' + String(subcategory.id) + '">' +
            '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M13 2 6 14h5l-1 8 8-13h-5l0-7z"/></svg>' +
            '<span>عاجل</span>' +
          '</button>' +
        '</div>';

      var control = option.querySelector(".pe-category-option-control");
      var title = option.querySelector(".pe-category-option-title");
      if (control) control.appendChild(checkbox);
      if (title) title.textContent = subcategory.name;

      list.appendChild(option);
      syncCategoryOptionState(option);
    });
  }

  function syncCategoryOptionState(optionEl) {
    if (!optionEl) return;
    var checkbox = optionEl.querySelector(".pe-category-subcheckbox");
    var toggle = optionEl.querySelector(".pe-category-urgent-toggle");
    var status = optionEl.querySelector(".pe-category-option-status");
    var scope = optionEl.querySelector(".pe-category-option-scope");
    var note = optionEl.querySelector(".pe-category-option-note");
    var subId = parseInt(checkbox && checkbox.value, 10);
    var isSelected = !!(checkbox && checkbox.checked);
    var setting = isSelected && isFinite(subId) ? getSubcategorySetting(subId) : normalizeSubcategorySetting(null);
    var policy = isFinite(subId) ? getSubcategoryPolicy(subId) : getSubcategoryPolicy(null);
    var allowsUrgentRequests = !!policy.allows_urgent_requests;
    var isUrgent = isSelected && allowsUrgentRequests && setting.accepts_urgent;
    var requiresGeoScope = !isSelected || policy.requires_geo_scope;

    optionEl.classList.toggle("is-selected", isSelected);
    optionEl.classList.toggle("is-urgent", isUrgent);
    optionEl.classList.toggle("is-remote", isSelected && !requiresGeoScope);

    if (status) {
      status.classList.toggle("is-urgent", isUrgent);
      status.classList.toggle("is-normal", isSelected && !isUrgent);
      status.textContent = isUrgent
        ? "مفعّل للطلبات العاجلة"
        : (isSelected ? (allowsUrgentRequests ? "استقبال عادي" : "استقبال عادي فقط") : "غير مفعّل");
    }

    if (scope) {
      scope.classList.toggle("is-remote", isSelected && !requiresGeoScope);
      scope.classList.toggle("is-local", isSelected && requiresGeoScope);
      scope.textContent = !isSelected
        ? "بدون نطاق محدد بعد"
        : (requiresGeoScope ? "سياسة المنصة: يخضع للنطاق الجغرافي والمسافة" : "سياسة المنصة: يمكن تقديمه عن بُعد بدون تقييد المدينة");
    }

    if (note) {
      if (!isSelected) {
        note.textContent = "فعّل التصنيف أولًا، وستظهر سياسة النطاق تلقائيًا وفق إعدادات المنصة. يمكنك فقط تفعيل الطلبات العاجلة إذا كان هذا التصنيف يدعمها.";
      } else if (!allowsUrgentRequests && !requiresGeoScope) {
        note.textContent = "هذا التخصص يعمل عن بُعد وفق سياسة المنصة، ولا يدعم الطلبات العاجلة لهذا التصنيف.";
      } else if (!allowsUrgentRequests) {
        note.textContent = "هذا التخصص محلي وفق سياسة المنصة ويخضع لمدينتك ونطاقك، لكنه لا يدعم الطلبات العاجلة.";
      } else if (!requiresGeoScope && isUrgent) {
        note.textContent = "هذا التخصص يعمل عن بُعد وفق سياسة المنصة، وسيظهر أيضًا ضمن الخدمات المستعدة لاستقبال الطلبات العاجلة.";
      } else if (!requiresGeoScope) {
        note.textContent = "هذا التخصص يمكن تقديمه عن بُعد وفق سياسة المنصة، لذلك لن يتم تقييده بمدينتك أو نصف قطر التغطية.";
      } else if (isUrgent) {
        note.textContent = "هذا التخصص محلي وفق سياسة المنصة ويخضع لمدينتك ونطاقك بالكيلومتر، مع تفعيل استقبال الطلبات العاجلة له.";
      } else {
        note.textContent = "هذا التخصص محلي وفق سياسة المنصة ويخضع لمدينتك ونطاقك بالكيلومتر بشكل افتراضي.";
      }
    }

    if (toggle) {
      toggle.disabled = !isSelected || !allowsUrgentRequests;
      toggle.classList.toggle("is-active", isUrgent);
      toggle.setAttribute("aria-pressed", isUrgent ? "true" : "false");
      toggle.setAttribute("title", !isSelected
        ? "اختر التصنيف الفرعي أولًا"
        : (!allowsUrgentRequests
          ? "الطلبات العاجلة غير متاحة لهذا التصنيف"
          : (isUrgent ? "إلغاء استقبال الطلبات العاجلة" : "تفعيل استقبال الطلبات العاجلة")));
    }
  }

  function refreshCategoryGroup(groupEl) {
    if (!groupEl) return;
    var select = groupEl.querySelector(".pe-category-select");
    if (!select) return;
    var groupId = getCategoryGroupId(groupEl);
    var selectedCategoryId = parseInt(select.value, 10);
    if (!isFinite(selectedCategoryId)) selectedCategoryId = null;
    var selectedSubcategoryIds = collectGroupSubcategoryIds(groupEl);
    renderCategoryGroupOptions(select, groupId, selectedCategoryId);
    selectedCategoryId = parseInt(select.value, 10);
    if (!isFinite(selectedCategoryId)) selectedCategoryId = null;
    renderCategoryGroupSubcategories(groupEl, selectedCategoryId, selectedSubcategoryIds);
  }

  function updateCategoryGroupHeadings() {
    var groups = getCategoryGroupCards();
    groups.forEach(function (groupEl, index) {
      var title = groupEl.querySelector(".pe-category-group-title");
      var removeBtn = groupEl.querySelector(".pe-category-remove");
      if (title) title.textContent = "القسم " + (index + 1);
      if (removeBtn) removeBtn.classList.toggle("hidden", groups.length <= 1);
    });
  }

  function updateCategoryAddButtonState() {
    var addBtn = document.getElementById("pe-category-add-group");
    if (!addBtn) return;
    addBtn.disabled = !categoryCatalog.length || getCategoryGroupCards().length >= categoryCatalog.length;
  }

  function refreshCategoryGroups() {
    getCategoryGroupCards().forEach(refreshCategoryGroup);
    updateCategoryGroupHeadings();
    updateCategoryAddButtonState();
    refreshServiceCategoriesSummary();
    refreshGeoScopeSummaries();
  }

  function createCategoryGroup(selectedCategoryId, selectedSubcategoryIds) {
    var root = getCategoryGroupsRoot();
    if (!root) return null;

    var groupEl = document.createElement("section");
    groupEl.className = "pe-category-group";
    groupEl.setAttribute("data-group-id", String(++categoryGroupSequence));
    groupEl.innerHTML = [
      '<div class="pe-category-group-head">',
      '  <div class="pe-category-group-head-copy">',
      '    <strong class="pe-category-group-title">القسم</strong>',
      '    <span class="pe-category-group-meta">اختر قسمًا رئيسيًا واحدًا، ثم أضف تحته التصنيفات الفرعية المناسبة.</span>',
      '  </div>',
      '  <button type="button" class="pe-category-remove">حذف القسم</button>',
      '</div>',
      '<div class="pe-category-group-grid">',
      '  <div class="form-group">',
      '    <label class="form-label">القسم الرئيسي</label>',
      '    <select class="form-select pe-category-select"><option value="">اختر القسم</option></select>',
      '  </div>',
      '  <div class="form-group form-group-wide">',
      '    <label class="form-label">التصنيفات الفرعية</label>',
      '    <div class="pe-category-checklist" data-role="subcategory-list">',
      '      <p class="pe-category-empty">اختر القسم الرئيسي أولًا لتظهر التصنيفات الفرعية التابعة له.</p>',
      '    </div>',
      '  </div>',
      '</div>'
    ].join("");
    root.appendChild(groupEl);

    var select = groupEl.querySelector(".pe-category-select");
    if (select) {
      renderCategoryGroupOptions(select, getCategoryGroupId(groupEl), isFinite(selectedCategoryId) ? selectedCategoryId : null);
      if (isFinite(selectedCategoryId)) {
        select.value = String(selectedCategoryId);
        renderCategoryGroupSubcategories(groupEl, selectedCategoryId, selectedSubcategoryIds);
      } else {
        renderCategoryGroupSubcategories(groupEl, null, []);
      }
    }
    return groupEl;
  }

  function buildCategoryGroupsFromSelection() {
    var root = getCategoryGroupsRoot();
    if (!root) return;
    root.innerHTML = "";
    categoryGroupSequence = 0;

    var groupsByCategory = {};
    providerSubcategoryIds.forEach(function (subId) {
      var sub = findSubcategoryById(subId);
      var categoryId = sub && isFinite(sub.category_id) ? sub.category_id : null;
      if (!isFinite(categoryId)) return;
      if (!groupsByCategory[categoryId]) groupsByCategory[categoryId] = [];
      groupsByCategory[categoryId].push(subId);
    });

    var categoryIds = Object.keys(groupsByCategory).map(function (value) { return parseInt(value, 10); }).filter(function (value) { return isFinite(value); });
    if (!categoryIds.length) {
      createCategoryGroup(null, []);
      refreshCategoryGroups();
      return;
    }

    categoryIds.forEach(function (categoryId) {
      createCategoryGroup(categoryId, groupsByCategory[categoryId]);
    });
    refreshCategoryGroups();
  }

  function bindCategoryPickerEvents() {
    var root = getCategoryGroupsRoot();
    if (!root) return;
    buildCategoryGroupsFromSelection();

    root.addEventListener("change", function (event) {
      var subcheckbox = event.target.closest(".pe-category-subcheckbox");
      if (subcheckbox) {
        var optionEl = subcheckbox.closest(".pe-category-option");
        var subId = parseInt(subcheckbox.value, 10);
        if (!subcheckbox.checked && isFinite(subId)) {
          providerSubcategorySettingsById[subId] = normalizeSubcategorySetting(null);
        }
        syncCategoryOptionState(optionEl);
        refreshServiceCategoriesSummary();
        return;
      }

      var select = event.target.closest(".pe-category-select");
      if (!select) return;
      var groupEl = select.closest(".pe-category-group");
      var selectedCategoryId = parseInt(select.value, 10);
      var duplicateGroup = findGroupByCategoryId(selectedCategoryId, getCategoryGroupId(groupEl));
      if (isFinite(selectedCategoryId) && duplicateGroup) {
        select.value = "";
        alert("يمكن اختيار كل قسم رئيسي مرة واحدة فقط. أضف جميع التصنيفات الفرعية التابعة له داخل نفس القسم.");
      }
      refreshCategoryGroups();
    });

    root.addEventListener("click", function (event) {
      var urgentToggle = event.target.closest(".pe-category-urgent-toggle");
      if (urgentToggle) {
        var optionEl = urgentToggle.closest(".pe-category-option");
        var checkbox = optionEl && optionEl.querySelector(".pe-category-subcheckbox");
        var subId = parseInt(urgentToggle.getAttribute("data-subcategory-id"), 10);
        if (!checkbox || !checkbox.checked || !isFinite(subId) || !getSubcategoryPolicy(subId).allows_urgent_requests) return;
        setSubcategorySetting(subId, {
          accepts_urgent: !getSubcategorySetting(subId).accepts_urgent
        });
        syncCategoryOptionState(optionEl);
        refreshServiceCategoriesSummary();
        return;
      }

      var removeBtn = event.target.closest(".pe-category-remove");
      if (!removeBtn) return;
      var groupEl = removeBtn.closest(".pe-category-group");
      if (!groupEl) return;
      groupEl.remove();
      if (!getCategoryGroupCards().length) createCategoryGroup(null, []);
      refreshCategoryGroups();
    });

    var addBtn = document.getElementById("pe-category-add-group");
    if (addBtn) {
      addBtn.addEventListener("click", function () {
        if (!categoryCatalog.length) {
          alert("تعذر تحميل الأقسام حاليًا. حدّث الصفحة ثم أعد المحاولة.");
          return;
        }
        if (getCategoryGroupCards().length >= categoryCatalog.length) return;
        createCategoryGroup(null, []);
        refreshCategoryGroups();
      });
    }
  }

  function collectServiceCategoryPayload() {
    var allIds = [];
    var hasSelection = false;
    var groups = getCategoryGroupCards();

    for (var i = 0; i < groups.length; i++) {
      var groupEl = groups[i];
      var select = groupEl.querySelector(".pe-category-select");
      var categoryId = parseInt(select && select.value, 10);
      var subcategoryIds = collectGroupSubcategoryIds(groupEl);
      var hasCategory = isFinite(categoryId);
      var hasSubcategories = subcategoryIds.length > 0;

      if (!hasCategory && !hasSubcategories) continue;
      if (!hasCategory) throw new Error("اختر قسمًا رئيسيًا لكل مجموعة تحتوي تصنيفات فرعية.");
      if (!hasSubcategories) throw new Error("اختر تصنيفًا فرعيًا واحدًا على الأقل داخل كل قسم.");

      hasSelection = true;
      subcategoryIds.forEach(function (subId) {
        if (allIds.indexOf(subId) === -1) allIds.push(subId);
      });
    }

    if (!hasSelection) {
      throw new Error("اختر تصنيفًا فرعيًا واحدًا على الأقل قبل الحفظ.");
    }

    return {
      subcategory_ids: allIds,
      subcategory_settings: allIds.map(function (subId) {
        var setting = getSubcategorySetting(subId);
        return {
          subcategory_id: subId,
          accepts_urgent: !!setting.accepts_urgent
        };
      })
    };
  }

  function refreshServiceCategoriesSummary() {
    var summary = document.getElementById("pe-category-summary");
    if (!summary) return;
    var draftIds = getCategoryGroupCards().length ? collectDraftServiceCategoryIds() : providerSubcategoryIds;
    summary.innerHTML = renderServiceCategoriesSummaryHtml(draftIds, providerSubcategorySettingsById);
  }

  function buildLanguageField(f) {
    return '<article class="pe-field pe-field-wide pe-language-field pe-langloc-field pe-langloc-field--language" data-key="' + f.key + '">' +
      '<div class="pe-field-head">' +
        '<div class="pe-field-title-wrap">' +
          '<span class="pe-field-icon" aria-hidden="true">' + iconSvg(f.icon) + '</span>' +
          '<div class="pe-field-copy">' +
            '<span class="pe-field-label">' + f.label + '</span>' +
            '<span class="pe-field-hint">' + escapeHtml(f.hint || '') + '</span>' +
          '</div>' +
        '</div>' +
      '</div>' +
      '<div class="pe-language-summary" id="pe-language-summary">' + (profile.languages ? escapeHtml(profile.languages) : '<span class="pe-empty-value">لم تتم إضافة هذه المعلومة بعد</span>') + '</div>' +
      '<div class="pe-language-options">' + LANGUAGE_PRESETS.map(function (preset) {
        var checked = !!profile["language" + preset.key.charAt(0).toUpperCase() + preset.key.slice(1)];
        return '<label class="pe-language-chip' + (checked ? ' is-selected' : '') + '">' +
          '<input class="pe-language-option-input" type="checkbox" id="pe-language-' + preset.key + '" data-language-key="' + preset.key + '"' + (checked ? ' checked' : '') + '>' +
          '<span>' + preset.label + '</span>' +
        '</label>';
      }).join('') + '</div>' +
      '<div class="pe-language-other-wrap' + (profile.languageOther ? '' : ' hidden') + '" id="pe-language-other-wrap">' +
        '<input type="text" class="form-input pe-language-other-input" id="pe-language-other-input" value="' + escapeHtml(profile.languageOtherText || '') + '" placeholder="اكتب اللغة الأخرى">' +
      '</div>' +
      '<div class="pe-field-actions">' +
        '<button type="button" class="btn btn-primary pe-save-btn" data-key="languages">حفظ</button>' +
      '</div>' +
    '</article>';
  }

  function buildServiceLocationField(f) {
    return '<article class="pe-field pe-field-wide pe-map-field pe-langloc-field pe-langloc-field--map" data-key="' + f.key + '">' +
      '<div class="pe-field-head">' +
        '<div class="pe-field-title-wrap">' +
          '<span class="pe-field-icon" aria-hidden="true">' + iconSvg(f.icon) + '</span>' +
          '<div class="pe-field-copy">' +
            '<span class="pe-field-label">' + f.label + '</span>' +
            '<span class="pe-field-hint">' + escapeHtml(f.hint || '') + '</span>' +
          '</div>' +
        '</div>' +
      '</div>' +
      '<div class="pe-map-caption">' + escapeHtml(f.hint || '') + '</div>' +
      '<div class="pe-service-map" id="pe-service-map"></div>' +
      '<div class="pe-map-meta">' +
        '<span class="pe-map-city">المنطقة الحالية: ' + escapeHtml(profile.location || 'غير محددة') + '</span>' +
        '<span class="pe-map-coords" id="pe-service-map-coords">' + (hasPreciseCoordinates() ? (escapeHtml(String(profile.latitude)) + ' ، ' + escapeHtml(String(profile.longitude))) : 'لم يتم تحديد الموقع بعد') + '</span>' +
      '</div>' +
      '<div class="pe-field-actions has-secondary">' +
        '<button type="button" class="btn btn-secondary pe-map-use-location-btn" data-key="serviceLocation">استخدام موقعي الحالي</button>' +
        '<button type="button" class="btn btn-primary pe-save-btn" data-key="serviceLocation">حفظ الموقع</button>' +
      '</div>' +
    '</article>';
  }

  function buildCoverageRadiusField(f) {
    var radius = getServiceRadiusKm();
    return '<article class="pe-field pe-field-wide pe-radius-field pe-langloc-field pe-langloc-field--radius" data-key="' + f.key + '">' +
      '<div class="pe-field-head">' +
        '<div class="pe-field-title-wrap">' +
          '<span class="pe-field-icon" aria-hidden="true">' + iconSvg(f.icon) + '</span>' +
          '<div class="pe-field-copy">' +
            '<span class="pe-field-label">' + f.label + '</span>' +
            '<span class="pe-field-hint">' + escapeHtml(f.hint || '') + '</span>' +
          '</div>' +
        '</div>' +
      '</div>' +
      '<div class="pe-radius-live">القيمة الحالية: <strong id="pe-radius-live-value">' + radius + ' كم</strong></div>' +
      '<div class="pe-geo-scope-explainer pe-geo-scope-explainer--compact" id="pe-radius-scope-summary"></div>' +
      '<div class="pe-radius-controls">' +
        '<input type="range" min="0" max="' + SERVICE_RADIUS_MAX_KM + '" step="1" value="' + radius + '" class="pe-radius-range" id="pe-radius-range">' +
        '<input type="number" class="form-input pe-input pe-radius-number" id="pe-radius-number" data-key="coverageRadius" min="0" max="' + SERVICE_RADIUS_MAX_KM + '" step="1" value="' + radius + '" inputmode="numeric">' +
      '</div>' +
      '<div class="pe-radius-helper" id="pe-radius-helper"></div>' +
      '<div class="pe-field-actions">' +
        '<button type="button" class="btn btn-primary pe-save-btn" data-key="coverageRadius">حفظ</button>' +
      '</div>' +
    '</article>';
  }

  function buildAdditionalOverviewField(f) {
    return '<article class="pe-field pe-field-wide pe-additional-overview-field" data-key="' + f.key + '">' +
      '<div class="pe-field-head">' +
        '<div class="pe-field-title-wrap">' +
          '<span class="pe-field-icon" aria-hidden="true">' + iconSvg(f.icon) + '</span>' +
          '<div class="pe-field-copy">' +
            '<span class="pe-field-label">نظرة سريعة</span>' +
            '<span class="pe-field-hint">مؤشرات مختصرة تساعدك على معرفة ما اكتمل في هذا القسم قبل التعديل على التفاصيل أدناه.</span>' +
          '</div>' +
        '</div>' +
      '</div>' +
      '<div class="pe-additional-overview-body" id="pe-additional-overview-body">' + renderAdditionalOverviewBody() + '</div>' +
    '</article>';
  }

  function buildField(f) {
    if (f.additionalOverviewField) return buildAdditionalOverviewField(f);
    if (f.additionalLinksField) return buildAdditionalLinksField(f);
    if (f.categoryPickerField) return buildCategoryPickerField(f);
    if (f.seoPreviewField) return buildSeoPreviewField(f);
    if (f.languageField) return buildLanguageField(f);
    if (f.mapField) return buildServiceLocationField(f);
    if (f.radiusField) return buildCoverageRadiusField(f);
    var val = profile[f.key] || "";
    var safeVal = escapeHtml(val);
    var attrs = ' data-key="' + f.key + '"';
    if (f.seoMetric) attrs += ' data-seo-metric="1"';
    if (f.placeholder) attrs += ' placeholder="' + escapeHtml(f.placeholder) + '"';
    if (f.inputMode) attrs += ' inputmode="' + f.inputMode + '"';
    if (f.dir) attrs += ' dir="' + f.dir + '"';
    if (f.autocomplete) attrs += ' autocomplete="' + f.autocomplete + '"';
    if (f.maxLength) attrs += ' maxlength="' + f.maxLength + '"';
    if (f.min !== undefined) attrs += ' min="' + f.min + '"';
    if (f.max !== undefined) attrs += ' max="' + f.max + '"';
    if (f.step) attrs += ' step="' + f.step + '"';
    var classes = ["pe-field"];
    if (f.readOnly) classes.push("pe-field-readonly");
    if (f.wide) classes.push("pe-field-wide");
    if (f.platform) classes.push("pe-social-link-field");
    if (f.key === "details" || f.key === "qualification" || f.key === "experiences") classes.push("pe-additional-field");
    if (f.key === "fullName" || f.key === "accountType" || f.key === "about" || f.key === "location") classes.push("pe-basic-field");
    if (f.isCity) classes.push("pe-location-picker-field");
    return '<article class="' + classes.join(" ") + '" data-key="' + f.key + '">' +
      '<div class="pe-field-head">' +
        '<div class="pe-field-title-wrap">' +
          '<span class="pe-field-icon" aria-hidden="true">' + iconSvg(f.icon) + '</span>' +
          '<div class="pe-field-copy">' +
            '<span class="pe-field-label">' + f.label + '</span>' +
            (f.hint ? '<span class="pe-field-hint">' + escapeHtml(f.hint) + '</span>' : '') +
          '</div>' +
        '</div>' +
        (!f.readOnly ? '<button type="button" class="pe-edit-btn" data-key="' + f.key + '" aria-label="تحرير ' + escapeHtml(f.label) + '"><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/></svg></button>' : '') +
      '</div>' +
      '<div class="pe-field-display">' + displayValue(val, f) + '</div>' +
      (!f.readOnly ? '<div class="pe-field-edit" style="display:none">' +
        (f.isCity ? buildLocationFieldEditor()
          : f.isChoice ? '<select class="form-select pe-input" data-key="' + f.key + '">' + (Array.isArray(f.options) ? f.options.map(function (option) { return '<option value="' + escapeHtml(option.value) + '"' + (String(option.value) === String(val) ? ' selected' : '') + '>' + escapeHtml(option.label) + '</option>'; }).join("") : "") + '</select>'
          : f.multiline ? '<textarea class="form-input form-textarea pe-input" rows="4"' + attrs + '>' + safeVal + '</textarea>'
          : '<input type="' + (f.inputType || "text") + '" class="form-input pe-input"' + attrs + ' value="' + safeVal + '">') +
        (f.seoMetric ? buildSeoFieldMeta(f) : '') +
        '<div class="pe-field-actions' + (f.geoAction ? ' has-secondary' : '') + '">' +
          (f.geoAction ? '<button class="btn btn-secondary pe-geo-btn" type="button" data-key="' + f.key + '">استخدام موقعي الحالي</button>' : '') +
          '<button type="button" class="btn btn-primary pe-save-btn" data-key="' + f.key + '">' + (f.key === "mobilePhone" ? 'إرسال الرمز' : 'حفظ') + '</button>' +
        '</div>' +
      '</div>' : '') +
    '</article>';
  }

  function bindFieldEvents() {
    document.querySelectorAll(".pe-edit-btn").forEach(function (btn) {
      btn.addEventListener("click", function () {
        openFieldEditor(this.dataset.key);
      });
    });
    document.querySelectorAll(".pe-save-btn").forEach(function (btn) {
      btn.addEventListener("click", function () { saveField(this.dataset.key, this); });
    });
    bindCategoryPickerEvents();
    document.querySelectorAll('.pe-additional-links-add-btn').forEach(function (btn) {
      btn.addEventListener('click', function () {
        appendAdditionalLinksRow({});
      });
    });
    document.querySelectorAll('.pe-additional-links-rows').forEach(function (rows) {
      rows.addEventListener('click', function (event) {
        var removeBtn = event.target.closest('.pe-additional-links-remove');
        if (!removeBtn) return;
        var row = removeBtn.closest('.pe-additional-link-row');
        if (row) row.remove();
        if (!rows.querySelector('.pe-additional-link-row')) appendAdditionalLinksRow({});
      });
    });
    document.querySelectorAll(".pe-location-city-input").forEach(function (input) {
      input.addEventListener("input", function () {
        syncProfileLocationLabels(profile.locationCountry || "", input.value.trim());
        setProfileLocationHint(input.value.trim() ? "سيتم اعتماد اسم المدينة المكتوب عند الحفظ." : "إذا لم تُقرأ مدينة دقيقة، يمكنك تعديلها يدويًا قبل الحفظ.", input.value.trim() ? true : null);
      });
    });
    document.querySelectorAll(".pe-location-use-current-btn").forEach(function (btn) {
      btn.addEventListener("click", function () { useCurrentProfileLocation(btn); });
    });
    document.querySelectorAll('.pe-input[data-key="phone"], .pe-input[data-key="mobilePhone"]').forEach(function (input) {
      input.addEventListener("input", function () {
        var sanitized = sanitizePhone(input.value);
        if (input.value !== sanitized) input.value = sanitized;
      });
    });
    document.querySelectorAll('.pe-input[data-seo-metric="1"]').forEach(function (input) {
      input.addEventListener("input", function () {
        updateSeoFieldFeedback(this.dataset.key);
        updateSeoPreview();
      });
      if (input.dataset.key === "seoSlug") {
        input.addEventListener("blur", function () {
          var normalized = normalizeSeoSlugValue(input.value);
          if (input.value !== normalized) input.value = normalized;
          updateSeoFieldFeedback("seoSlug");
          updateSeoPreview();
        });
      }
    });
    document.querySelectorAll(".pe-language-option-input").forEach(function (input) {
      input.addEventListener("change", function () {
        var chip = input.closest(".pe-language-chip");
        if (chip) chip.classList.toggle("is-selected", input.checked);
        updateLanguageOtherVisibility();
        refreshLangLocOverview();
      });
    });
    var languageOtherInput = document.getElementById("pe-language-other-input");
    if (languageOtherInput) {
      languageOtherInput.addEventListener("input", function () {
        refreshLangLocOverview();
      });
    }
    var radiusRange = document.getElementById("pe-radius-range");
    var radiusNumber = document.getElementById("pe-radius-number");
    if (radiusRange) {
      radiusRange.addEventListener("input", function () {
        syncRadiusInputs(radiusRange.value);
      });
    }
    if (radiusNumber) {
      radiusNumber.addEventListener("input", function () {
        syncRadiusInputs(radiusNumber.value);
      });
    }
    document.querySelectorAll(".pe-map-use-location-btn").forEach(function (btn) {
      btn.addEventListener("click", function () { useCurrentLocationOnMap(btn); });
    });
    document.querySelectorAll(".pe-geo-btn").forEach(function (btn) {
      btn.addEventListener("click", function () { useCurrentLocation(this); });
    });

    updateLanguageOtherVisibility();
    syncRadiusInputs(getServiceRadiusKm());
    ensureServiceMap();
    refreshGeoScopeSummaries();
    refreshLangLocOverview();
    ["seoTitle", "seoMetaDescription", "seoSlug", "keywords"].forEach(function (key) {
      updateSeoFieldFeedback(key);
    });
    updateSeoPreview();
  }

  function useCurrentLocationOnMap(btn) {
    if (!navigator.geolocation) {
      alert("المتصفح لا يدعم تحديد الموقع");
      return;
    }
    var originalText = btn.textContent;
    btn.disabled = true;
    btn.textContent = "جاري تحديد الموقع...";
    navigator.geolocation.getCurrentPosition(function (position) {
      var lat = Number(position.coords.latitude);
      var lng = Number(position.coords.longitude);
      ensureServiceMap();
      if (serviceMap && serviceMapMarker) {
        var next = [lat, lng];
        serviceMapMarker.setLatLng(next);
        serviceMap.setView(next, 13, { animate: true });
        updateServiceLocationDraft(lat, lng);
        updateServiceRadiusPreview(getServiceRadiusKm());
      }
      btn.disabled = false;
      btn.textContent = originalText;
    }, function (error) {
      btn.disabled = false;
      btn.textContent = originalText;
      if (error && error.code === 1) {
        alert("تم رفض صلاحية الموقع");
        return;
      }
      alert("تعذر تحديد موقعك الحالي");
    }, {
      enableHighAccuracy: true,
      timeout: 10000,
      maximumAge: 0
    });
  }

  function useCurrentLocation(btn) {
    if (!navigator.geolocation) {
      alert("المتصفح لا يدعم تحديد الموقع");
      return;
    }
    var originalText = btn.textContent;
    btn.disabled = true;
    btn.textContent = "جاري تحديد الموقع...";
    navigator.geolocation.getCurrentPosition(function (position) {
      var lat = normalizeCoordinateValue(position.coords.latitude);
      var lng = normalizeCoordinateValue(position.coords.longitude);
      if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
        btn.disabled = false;
        btn.textContent = originalText;
        alert("تعذر قراءة موقعك الحالي بدقة صالحة للحفظ");
        return;
      }
      safePatch("/api/providers/me/profile/", { lat: lat, lng: lng }).then(function (resp) {
        if (!resp || !resp.ok) {
          throw new Error(apiErrorMessage(resp ? resp.data : null, "تعذر تحديث الموقع"));
        }
        var data = resp.data || {};
        setFieldValue("latitude", formatCoord(data.lat !== undefined ? data.lat : lat));
        setFieldValue("longitude", formatCoord(data.lng !== undefined ? data.lng : lng));
        alert("تم تحديث موقعك الحالي");
      }).catch(function (err) {
        alert((err && err.message) ? err.message : "تعذر تحديث الموقع");
      }).finally(function () {
        btn.disabled = false;
        btn.textContent = originalText;
      });
    }, function (error) {
      btn.disabled = false;
      btn.textContent = originalText;
      if (error && error.code === 1) {
        alert("تم رفض صلاحية الموقع");
        return;
      }
      alert("تعذر تحديد موقعك الحالي");
    }, {
      enableHighAccuracy: true,
      timeout: 10000,
      maximumAge: 0
    });
  }

  function saveField(key, btn) {
    if (key === "serviceCategories") {
      saveServiceCategories(btn);
      return;
    }
    var apiKey = FIELD_MAP[key];
    if (!apiKey) return;
    var input = document.querySelector('.pe-input[data-key="' + key + '"]');
    var val = input ? input.value.trim() : "";
    var nextValue = val;
    var payload = {};

    if (key === "location") {
      var fieldNode = document.querySelector('.pe-field[data-key="location"]');
      var countryInput = fieldNode ? fieldNode.querySelector('.pe-location-country-input') : null;
      var cityInput = fieldNode ? fieldNode.querySelector('.pe-location-city-input') : null;
      var countryValue = countryInput ? String(countryInput.value || "").trim() : "";
      var cityValue = cityInput ? String(cityInput.value || "").trim() : "";
      if (!Number.isFinite(profileLocationDraft.lat) || !Number.isFinite(profileLocationDraft.lng)) {
        alert("حدّد موقعك على الخريطة أولًا ثم احفظ الدولة والمدينة.");
        return;
      }
      if (!countryValue || !cityValue) {
        alert("تأكد من تعبئة الدولة والمدينة قبل الحفظ.");
        return;
      }
      payload.country = countryValue || null;
      payload.city = cityValue || null;
      payload.location_label = buildProfileLocationLabel(countryValue, cityValue) || null;
      payload.lat = normalizeCoordinateValue(profileLocationDraft.lat);
      payload.lng = normalizeCoordinateValue(profileLocationDraft.lng);
      nextValue = buildProfileLocationLabel(countryValue, cityValue);
    } else {

    switch (apiKey) {
      case "years_experience": payload[apiKey] = parseInt(val.replace(/[^\d]/g, "")) || 0; break;
      case "provider_type":
        if (val !== "individual" && val !== "company") {
          alert("اختر صفة حساب صحيحة");
          return;
        }
        payload[apiKey] = val;
        nextValue = val;
        break;
      case "seo_title":
        payload[apiKey] = normalizeSeoText(val);
        nextValue = payload[apiKey];
        break;
      case "seo_meta_description":
        payload[apiKey] = normalizeSeoText(val);
        nextValue = payload[apiKey];
        break;
      case "seo_keywords":
        payload[apiKey] = normalizeSeoKeywordsText(val);
        nextValue = payload[apiKey];
        if (input && input.value !== nextValue) input.value = nextValue;
        break;
      case "seo_slug":
        payload[apiKey] = normalizeSeoSlugValue(val);
        if (val && !payload[apiKey]) {
          alert("أدخل رابطًا مخصصًا صالحًا");
          return;
        }
        nextValue = payload[apiKey];
        if (input && input.value !== nextValue) input.value = nextValue;
        break;
      case "languages":
        var languageState = collectLanguageStateFromDom();
        if (!languageState.arabic && !languageState.english && !languageState.other) {
          alert("اختر لغة تواصل واحدة على الأقل");
          return;
        }
        if (languageState.other && !splitEntries(languageState.otherText).length) {
          alert("اكتب اللغة الأخرى أولًا");
          return;
        }
        payload[apiKey] = buildLanguagesPayload(languageState);
        nextValue = formatLanguagesDisplay(languageState);
        break;
      case "qualifications": payload[apiKey] = val.split(/[،,]/).filter(Boolean).map(function (s) { return { title: s.trim() }; }); break;
      case "experiences": payload[apiKey] = splitEntries(val); break;
      case "coordinates":
        if (!Number.isFinite(serviceLocationDraft.lat) || !Number.isFinite(serviceLocationDraft.lng)) {
          alert("حدد موقعك على الخريطة أولًا");
          return;
        }
        payload.lat = normalizeCoordinateValue(serviceLocationDraft.lat);
        payload.lng = normalizeCoordinateValue(serviceLocationDraft.lng);
        if (!Number.isFinite(payload.lat) || !Number.isFinite(payload.lng)) {
          alert("تعذر قراءة الإحداثيات الحالية. حرّك المؤشر على الخريطة ثم أعد المحاولة.");
          return;
        }
        nextValue = formatCoord(payload.lat) + " ، " + formatCoord(payload.lng);
        break;
      case "social_links":
        try {
          var socialValues = collectSocialFormValues(key, val);
          var extraSocialItems = key === 'additionalLinks' ? collectAdditionalSocialItems() : profile.socialExtras;
          payload[apiKey] = buildSocialLinksPayload(socialValues, extraSocialItems);
          nextValue = key === 'additionalLinks'
            ? String(extraSocialItems.length || '')
            : String(socialValues[key] || "").trim();
        } catch (socialErr) {
          alert((socialErr && socialErr.message) ? socialErr.message : "تعذر حفظ روابط التواصل");
          return;
        }
        break;
      case "coverage_radius_km":
        if (!val) {
          payload[apiKey] = 0;
          nextValue = "0";
          serviceRadiusDraft = 0;
          break;
        }
        payload[apiKey] = parseInt(val.replace(/[^\d]/g, ""), 10);
        if (!isFinite(payload[apiKey]) || payload[apiKey] < 0) {
          alert("أدخل نطاق خدمة صحيحًا");
          return;
        }
        payload[apiKey] = clampServiceRadiusKm(payload[apiKey]);
        serviceRadiusDraft = payload[apiKey];
        nextValue = String(payload[apiKey]);
        break;
      case "lat":
      case "lng":
        if (!val) {
          payload[apiKey] = null;
          nextValue = "";
          break;
        }
        payload[apiKey] = Number(val);
        if (!isFinite(payload[apiKey])) {
          alert(apiKey === "lat" ? "خط العرض غير صالح" : "خط الطول غير صالح");
          return;
        }
        if (apiKey === "lat" && (payload[apiKey] < -90 || payload[apiKey] > 90)) {
          alert("خط العرض يجب أن يكون بين -90 و90");
          return;
        }
        if (apiKey === "lng" && (payload[apiKey] < -180 || payload[apiKey] > 180)) {
          alert("خط الطول يجب أن يكون بين -180 و180");
          return;
        }
        nextValue = formatCoord(payload[apiKey]);
        break;
      case "whatsapp":
        if (!val) {
          payload[apiKey] = "";
          nextValue = "";
          break;
        }
        payload[apiKey] = normalizePhone05(val);
        if (!payload[apiKey]) {
          alert("رقم الجوال يجب أن يكون 10 خانات ويبدأ بـ 05");
          return;
        }
        nextValue = payload[apiKey];
        if (input.value !== nextValue) input.value = nextValue;
        break;
      case "phone":
        if (!val) {
          alert("رقم الجوال مطلوب");
          return;
        }
        payload[apiKey] = normalizePhone05(val);
        if (!payload[apiKey]) {
          alert("رقم الجوال يجب أن يكون 10 خانات ويبدأ بـ 05");
          return;
        }
        nextValue = payload[apiKey];
        if (input && input.value !== nextValue) input.value = nextValue;
        break;
      default: payload[apiKey] = val;
    }
    }

    if (key === "mobilePhone") {
      saveMobilePhoneWithOtp(nextValue, btn, input);
      return;
    }

    btn.disabled = true; btn.textContent = "جاري الحفظ...";
    var saveRequest = (key === "mobilePhone" || key === "accountEmail")
      ? safePatch("/api/accounts/me/", payload)
      : safePatch("/api/providers/me/profile/", payload);
    saveRequest.then(function (resp) {
      if (!resp || !resp.ok) {
        throw new Error(apiErrorMessage(resp ? resp.data : null, "فشل في الحفظ"));
      }
      var responseData = resp.data || {};
      if (key === "accountType" && typeof responseData.provider_type === "string") nextValue = responseData.provider_type;
      if (key === "mobilePhone" && typeof responseData.phone === "string") nextValue = responseData.phone;
      if (key === "accountEmail" && typeof responseData.email === "string") nextValue = responseData.email;
      if (key === "seoTitle" && typeof responseData.seo_title === "string") nextValue = responseData.seo_title;
      if (key === "seoMetaDescription" && typeof responseData.seo_meta_description === "string") nextValue = responseData.seo_meta_description;
      if (key === "keywords" && typeof responseData.seo_keywords === "string") nextValue = responseData.seo_keywords;
      if (key === "seoSlug" && typeof responseData.seo_slug === "string") nextValue = responseData.seo_slug;
      var field = document.querySelector('.pe-field[data-key="' + key + '"]');
      if (key === "languages") {
        profile.languageArabic = payload.languages.some(function (item) { return normalizeLanguageLabel(item.name) === "عربي"; });
        profile.languageEnglish = payload.languages.some(function (item) { return normalizeLanguageLabel(item.name) === "انجليزي"; });
        profile.languageOther = payload.languages.some(function (item) { return normalizeLanguageLabel(item.name) !== "عربي" && normalizeLanguageLabel(item.name) !== "انجليزي"; });
        profile.languageOtherText = payload.languages
          .map(function (item) { return normalizeLanguageLabel(item.name); })
          .filter(function (item) { return item !== "عربي" && item !== "انجليزي"; })
          .join("، ");
      }
      if (key === "serviceLocation") {
        profile.latitude = formatCoord(payload.lat);
        profile.longitude = formatCoord(payload.lng);
        updateServiceLocationDraft(payload.lat, payload.lng);
        updateServiceRadiusPreview(getServiceRadiusKm());
      }
      if (key === "location") {
        var responseLocationLabel = String(responseData.city_display || responseData.city || payload.location_label || "").trim();
        var responseScope = splitLocationScope(responseLocationLabel, responseData.country || payload.country || "");
        profile.locationCountry = String(responseData.country || responseScope.region || payload.country || "").trim();
        profile.locationRegion = profile.locationCountry;
        profile.locationCity = String(responseScope.city || payload.city || "").trim();
        profile.location = buildProfileLocationLabel(profile.locationCountry, profile.locationCity) || responseLocationLabel;
        profile.latitude = formatCoord(responseData.lat !== undefined ? responseData.lat : payload.lat);
        profile.longitude = formatCoord(responseData.lng !== undefined ? responseData.lng : payload.lng);
        setProfileLocationDraft(responseData.lat !== undefined ? responseData.lat : payload.lat, responseData.lng !== undefined ? responseData.lng : payload.lng);
        nextValue = profile.location;
        if (providerProfileRaw) {
          providerProfileRaw.country = profile.locationCountry;
          providerProfileRaw.city = nextValue;
          providerProfileRaw.lat = responseData.lat !== undefined ? responseData.lat : payload.lat;
          providerProfileRaw.lng = responseData.lng !== undefined ? responseData.lng : payload.lng;
        }
        if (serviceMap && serviceMapMarker) {
          serviceMapMarker.setLatLng([Number(profile.latitude), Number(profile.longitude)]);
          centerServiceMapOnCity(false);
          updateServiceLocationDraft(profile.latitude, profile.longitude);
          updateServiceRadiusPreview(getServiceRadiusKm());
        }
      }
      if (key === "coverageRadius") {
        profile.coverageRadius = nextValue;
        serviceRadiusDraft = payload.coverage_radius_km;
        updateServiceRadiusPreview(serviceRadiusDraft);
      }
      if (apiKey === "social_links") {
        applySocialState(extractSocialState((resp.data && resp.data.social_links) || payload[apiKey]));
        SOCIAL_FIELD_KEYS.forEach(function (socialKey) {
          setFieldValue(socialKey, profile[socialKey] || "");
        });
        setFieldValue('additionalLinks', profile.additionalLinks || '');
      } else {
        setFieldValue(key, nextValue);
      }
      if (key === "mobilePhone" && userProfile) userProfile.phone = nextValue;
      if (key === "accountEmail" && userProfile) userProfile.email = nextValue;
      if (field && !field.classList.contains("pe-language-field") && !field.classList.contains("pe-map-field") && !field.classList.contains("pe-radius-field")) {
        setFieldEditingState(field, false);
      }
    }).catch(function (err) {
      alert((err && err.message) ? err.message : "فشل في الحفظ");
    }).finally(function () {
      btn.disabled = false; btn.textContent = "حفظ";
    });
  }

  function saveServiceCategories(btn) {
    var payload;
    try {
      payload = collectServiceCategoryPayload();
    } catch (err) {
      alert((err && err.message) ? err.message : "تعذر تجهيز التصنيفات للحفظ");
      return;
    }

    btn.disabled = true;
    btn.textContent = "جاري الحفظ...";
    safePut("/api/providers/me/subcategories/", payload).then(function (resp) {
      if (!resp || !resp.ok) {
        throw new Error(apiErrorMessage(resp ? resp.data : null, "فشل في حفظ التصنيفات"));
      }
      var data = resp.data || {};
      applyProviderSubcategoryState(
        data.subcategory_ids || payload.subcategory_ids,
        data.subcategory_settings || payload.subcategory_settings,
        providerSelectedSubcategories
      );
      refreshServiceCategoriesSummary();
      refreshGeoScopeSummaries();
      buildCategoryGroupsFromSelection();
      showProfileToast("تم حفظ التصنيفات بنجاح", "success", "تم الحفظ");
    }).catch(function (err) {
      showProfileToast((err && err.message) ? err.message : "فشل في حفظ التصنيفات", "error", "تعذر الحفظ");
    }).finally(function () {
      btn.disabled = false;
      btn.textContent = "حفظ التصنيفات";
    });
  }

  function activateTab(name, preserveSection) {
    var tabsWrap = document.getElementById("pe-tabs");
    if (!tabsWrap || !name) return;
    var tabBtn = tabsWrap.querySelector('.tab[data-tab="' + name + '"]');
    if (!tabBtn) return;
    tabsWrap.querySelectorAll(".tab").forEach(function (t) {
      var isActive = t === tabBtn;
      t.classList.toggle("active", isActive);
      t.setAttribute("aria-selected", isActive ? "true" : "false");
      t.setAttribute("tabindex", isActive ? "0" : "-1");
    });
    document.querySelectorAll(".tab-panel").forEach(function (p) {
      var isActive = p.dataset.panel === name;
      p.classList.toggle("active", isActive);
      if (isActive) {
        p.removeAttribute("hidden");
      } else {
        p.setAttribute("hidden", "hidden");
      }
    });
    if (typeof tabBtn.scrollIntoView === "function") {
      try {
        tabBtn.scrollIntoView({ behavior: "smooth", block: "nearest", inline: "center" });
      } catch (_err) {
        tabBtn.scrollIntoView();
      }
    }
    closeAllEditors();
    if (!preserveSection) initialSection = null;
    updateSectionHelper(name);
  }

  function resolveTabByField(fieldKey) {
    var tabNames = Object.keys(TABS);
    for (var i = 0; i < tabNames.length; i++) {
      var tabName = tabNames[i];
      var hasField = TABS[tabName].some(function (f) { return f.key === fieldKey; });
      if (hasField) return tabName;
    }
    return null;
  }

  function openFieldEditor(fieldKey) {
    var field = document.querySelector('.pe-field[data-key="' + fieldKey + '"]');
    if (!field) return;

    if (field.classList.contains("pe-language-field") || field.classList.contains("pe-map-field") || field.classList.contains("pe-radius-field")) {
      if (field.classList.contains("pe-map-field")) ensureServiceMap();
      field.scrollIntoView({ behavior: "smooth", block: "center" });
      var directInput = field.querySelector("input, textarea, select");
      if (directInput && typeof directInput.focus === "function") directInput.focus();
      return;
    }

    closeAllEditors(fieldKey);
    setFieldEditingState(field, true);
    if (fieldKey === "mobilePhone") resetMobilePhoneOtpState(field);

    field.style.boxShadow = "0 0 0 2px rgba(103,58,183,0.22)";
    setTimeout(function () { field.style.boxShadow = ""; }, 1600);

    var input = field.querySelector('.pe-input[data-key="' + fieldKey + '"]') || field.querySelector('.pe-field-edit input, .pe-field-edit textarea, .pe-field-edit select');
    if (field.classList.contains("pe-location-picker-field")) {
      ensureProfileLocationMap();
    }
    if (input && typeof input.focus === "function") {
      input.focus();
      if (typeof input.select === "function") input.select();
    }
    if (isSeoFieldKey(fieldKey)) {
      updateSeoFieldFeedback(fieldKey);
      updateSeoPreview();
    }
    field.scrollIntoView({ behavior: "smooth", block: "center" });
  }

  function focusFieldPreview(fieldKey) {
    var field = document.querySelector('.pe-field[data-key="' + fieldKey + '"]');
    if (!field) return;
    closeAllEditors();
    field.classList.remove("is-editing");
    field.style.boxShadow = "0 0 0 2px rgba(15,118,110,0.24)";
    setTimeout(function () { field.style.boxShadow = ""; }, 1600);
    if (field.classList.contains("pe-map-field")) ensureServiceMap();
    field.scrollIntoView({ behavior: "smooth", block: "center" });
  }

  function applyEntryNavigation() {
    if (isSectionFlowActive()) {
      var sectionCfg = SECTION_CONFIG[initialSection];
      if (sectionCfg && sectionCfg.tab) activateTab(sectionCfg.tab, true);
      if (!initialFocus || (sectionCfg && sectionCfg.mode === "summary")) return;
      setTimeout(function () { focusFieldPreview(initialFocus); }, 80);
      return;
    }
    var tabToOpen = initialTab || (initialFocus ? resolveTabByField(initialFocus) : null);
    if (tabToOpen) activateTab(tabToOpen);
    if (!initialFocus) return;
    setTimeout(function () { focusFieldPreview(initialFocus); }, 80);
  }

  function bindTabs() {
    var tabsWrap = document.getElementById("pe-tabs");
    if (!tabsWrap) return;

    tabsWrap.addEventListener("click", function (e) {
      var tab = e.target.closest(".tab");
      if (!tab || !tabsWrap.contains(tab)) return;
      initialFocus = null;
      activateTab(tab.dataset.tab);
    });

    tabsWrap.addEventListener("keydown", function (e) {
      var current = e.target.closest(".tab");
      if (!current || !tabsWrap.contains(current)) return;

      var tabs = Array.from(tabsWrap.querySelectorAll(".tab"));
      if (!tabs.length) return;
      var index = tabs.indexOf(current);
      if (index < 0) return;

      var dir = String((document.documentElement && document.documentElement.getAttribute("dir")) || "rtl").toLowerCase();
      var forwardKey = dir === "rtl" ? "ArrowLeft" : "ArrowRight";
      var backwardKey = dir === "rtl" ? "ArrowRight" : "ArrowLeft";

      var nextIndex = -1;
      if (e.key === forwardKey) {
        nextIndex = (index + 1) % tabs.length;
      } else if (e.key === backwardKey) {
        nextIndex = (index - 1 + tabs.length) % tabs.length;
      } else if (e.key === "Home") {
        nextIndex = 0;
      } else if (e.key === "End") {
        nextIndex = tabs.length - 1;
      } else if (e.key === "Enter" || e.key === " ") {
        e.preventDefault();
        initialFocus = null;
        activateTab(current.dataset.tab);
        return;
      } else {
        return;
      }

      e.preventDefault();
      var target = tabs[nextIndex];
      if (!target) return;
      initialFocus = null;
      activateTab(target.dataset.tab);
      if (typeof target.focus === "function") target.focus();
    });

    var workflow = document.getElementById("pe-workflow-progress");
    if (workflow) {
      workflow.addEventListener("click", function (e) {
        var step = e.target.closest(".pe-workflow-step");
        if (!step || !workflow.contains(step)) return;
        var targetTab = String(step.getAttribute("data-tab-target") || "").trim();
        if (!targetTab) return;
        initialFocus = null;
        activateTab(targetTab);
      });
    }
  }

  document.addEventListener("DOMContentLoaded", init);
  return { init: init };
})();
