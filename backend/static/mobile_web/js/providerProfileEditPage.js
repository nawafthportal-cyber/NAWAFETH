"use strict";
var ProviderProfileEditPage = (function () {
  var RAW_API = window.ApiClient;
  var API = window.NwApiClient;
  var CITIES = ["الرياض","جدة","مكة المكرمة","المدينة المنورة","الدمام","الخبر","الظهران","الطائف","تبوك","بريدة","عنيزة","حائل","أبها","خميس مشيط","نجران","جازان","ينبع","الباحة","الجبيل","حفر الباطن","القطيف","الأحساء","سكاكا","عرعر","بيشة","الخرج","الدوادمي","المجمعة","القويعية","وادي الدواسر"];
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
  var initialTab = null;
  var initialFocus = null;
  var initialSection = null;
  var serviceMap = null;
  var serviceMapMarker = null;
  var serviceMapCircle = null;
  var serviceLocationDraft = { lat: null, lng: null };
  var serviceRadiusDraft = 0;

  var SECTION_TITLES = {
    basic: "البيانات الأساسية",
    service_details: "تفاصيل الخدمة",
    additional: "معلومات إضافية",
    contact_full: "معلومات التواصل",
    lang_loc: "اللغة ونطاق الخدمة",
    seo: "تحسين الظهور في البحث"
  };

  var SECTION_CONFIG = {
    basic: {
      tab: "account",
      kicker: "تمت تعبئتها أثناء التسجيل الأولي",
      fields: ["fullName", "accountType", "mobilePhone", "about", "location", "accountEmail"],
      heading: "معلومات الحساب الأساسية",
      intro: "عدّل معلومات الحساب الأساسية من مكان واحد: الاسم، الصفة، رقم الجوال، النبذة، المدينة، والبريد الإلكتروني."
    },
    service_details: {
      tab: "account",
      fields: ["fullName", "about", "specialization"],
      kicker: "الانطباع الأول عن خدمتك",
      heading: "تفاصيل الخدمة",
      intro: "حدّث الاسم الظاهر والنبذة المختصرة والوصف المساند حتى تكون خدمتك واضحة للعميل من أول نظرة."
    },
    additional: {
      tab: "extra",
      fields: ["details", "qualification", "experiences"],
      kicker: "وسّع عرض خبرتك",
      heading: "معلومات إضافية",
      intro: "أضف التفاصيل الموسعة والمؤهلات والخبرات العملية حتى يرى العميل قيمة خبرتك بوضوح."
    },
    contact_full: {
      tab: "extra",
      fields: ["phone", "website", "xUrl", "snapchatUrl", "instagramUrl", "facebookUrl", "tiktokUrl", "contactEmail"],
      kicker: "قنوات الوصول إليك",
      heading: "معلومات التواصل",
      intro: "أكمل وسائل التواصل والروابط التي تساعد العميل على الوصول إليك بسرعة وبصورة مباشرة."
    },
    lang_loc: {
      tab: "general",
      fields: ["languages", "location", "serviceLocation", "coverageRadius"],
      kicker: "التغطية اللغوية والجغرافية",
      heading: "اللغة ونطاق الخدمة",
      intro: "حدد اللغات التي تعمل بها والمنطقة التي تغطيها حتى تظهر خدمتك للعملاء المناسبين في المواقع الصحيحة."
    },
    seo: {
      tab: "extra",
      fields: ["seoPreview", "seoTitle", "seoMetaDescription", "seoSlug", "keywords"],
      kicker: "جاهزية الصفحة للفهرسة",
      heading: "تحسين الظهور في البحث",
      intro: "اضبط عنوان الصفحة والوصف والرابط المخصص والكلمات المفتاحية، ثم راجع المعاينة قبل الحفظ حتى تظهر صفحتك بصورة احترافية في محركات البحث والمشاركة."
    }
  };

  var SECTION_LINKS = [
    { key: "basic", label: "البيانات الأساسية", href: "/provider-profile-edit/?tab=account&focus=fullName&section=basic" },
    { key: "service_details", label: "تفاصيل الخدمة", href: "/provider-profile-edit/?tab=account&focus=about&section=service_details" },
    { key: "additional", label: "معلومات إضافية", href: "/provider-profile-edit/?tab=extra&focus=details&section=additional" },
    { key: "contact_full", label: "معلومات التواصل", href: "/provider-profile-edit/?tab=extra&focus=phone&section=contact_full" },
    { key: "lang_loc", label: "اللغة ونطاق الخدمة", href: "/provider-profile-edit/?tab=general&focus=coverageRadius&section=lang_loc" },
    { key: "content", label: "محتوى أعمالك", href: "/provider-portfolio/?from=profile-completion&section=content" },
    { key: "seo", label: "تحسين الظهور في البحث", href: "/provider-profile-edit/?tab=extra&focus=seoTitle&section=seo" }
  ];

  var TAB_META = {
    account: {
      label: "معلومات الحساب",
      summary: "حدّث اسم الحساب، صفته، رقم الجوال، النبذة، المدينة، والبريد الإلكتروني من نفس الواجهة."
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
      summary: "حرّر معلومات الحساب الأساسية كاملة مع ربط مباشر ببيانات الحساب وملف مقدم الخدمة."
    },
    service_details: {
      label: "تفاصيل الخدمة",
      summary: "اضبط المعلومات التي تكوّن الانطباع الأول عن خدمتك أمام العميل داخل الصفحة."
    },
    additional: {
      label: "معلومات إضافية",
      summary: "أضف التفاصيل الموسعة التي تدعم قرار العميل وتوضح تخصصك بصورة أدق."
    },
    contact_full: {
      label: "معلومات التواصل",
      summary: "حدّث وسائل التواصل والروابط التي تساعد العميل على الوصول إليك بسرعة."
    },
    lang_loc: {
      label: "اللغة ونطاق الخدمة",
      summary: "راجع اللغات، المدينة، ونطاق التغطية حتى تكون خدمتك واضحة جغرافيًا."
    },
    seo: {
      label: "تحسين الظهور في البحث",
      summary: "حرّر عنوان الصفحة والوصف والرابط المخصص والكلمات المفتاحية مع معاينة فورية قبل الحفظ."
    }
  };

  var FIELD_MAP = {
    fullName: "display_name", accountType: "provider_type", about: "bio",
    specialization: "about_details", experience: "years_experience",
    languages: "languages", location: "city", coverageRadius: "coverage_radius_km",
    serviceLocation: "coordinates",
    latitude: "lat", longitude: "lng", details: "about_details",
    qualification: "qualifications", experiences: "experiences", website: "website", social: "social_links",
    xUrl: "social_links", snapchatUrl: "social_links", instagramUrl: "social_links",
    facebookUrl: "social_links", tiktokUrl: "social_links", contactEmail: "social_links",
    phone: "whatsapp", mobilePhone: "phone", accountEmail: "email", seoTitle: "seo_title", keywords: "seo_keywords", seoMetaDescription: "seo_meta_description", seoSlug: "seo_slug"
  };

  var TYPE_LABELS = { individual: "فرد", company: "منشأة", freelancer: "فرد" };

  var SOCIAL_FIELDS = [
    { key: "xUrl", platform: "x", label: "منصة X", icon: "x", hint: "أدخل رابط الحساب أو اسم المستخدم على منصة X.", inputType: "url", inputMode: "url", placeholder: "https://x.com/username", dir: "ltr", autocomplete: "url" },
    { key: "snapchatUrl", platform: "snapchat", label: "منصة سناب شات", icon: "snapchat", hint: "أدخل رابط الحساب أو اسم المستخدم على سناب شات.", inputType: "url", inputMode: "url", placeholder: "https://snapchat.com/add/username", dir: "ltr", autocomplete: "url" },
    { key: "instagramUrl", platform: "instagram", label: "منصة انستقرام", icon: "instagram", hint: "أدخل رابط الحساب أو اسم المستخدم على انستقرام.", inputType: "url", inputMode: "url", placeholder: "https://instagram.com/username", dir: "ltr", autocomplete: "url" },
    { key: "facebookUrl", platform: "facebook", label: "منصة فيس بوك", icon: "facebook", hint: "أدخل رابط الصفحة أو اسم المستخدم على فيس بوك.", inputType: "url", inputMode: "url", placeholder: "https://facebook.com/username", dir: "ltr", autocomplete: "url" },
    { key: "tiktokUrl", platform: "tiktok", label: "منصة تيك توك", icon: "tiktok", hint: "أدخل رابط الحساب أو اسم المستخدم على تيك توك.", inputType: "url", inputMode: "url", placeholder: "https://tiktok.com/@username", dir: "ltr", autocomplete: "url" },
    { key: "contactEmail", platform: "email", label: "البريد الإلكتروني", icon: "email", hint: "بريد التواصل المباشر الذي ترغب بإظهاره للعملاء.", inputType: "email", inputMode: "email", placeholder: "name@example.com", dir: "ltr", autocomplete: "email" }
  ];
  var SOCIAL_FIELD_KEYS = SOCIAL_FIELDS.map(function (field) { return field.key; });
  var SOCIAL_FIELD_PLATFORMS = {
    xUrl: "x",
    snapchatUrl: "snapchat",
    instagramUrl: "instagram",
    facebookUrl: "facebook",
    tiktokUrl: "tiktok",
    contactEmail: "email"
  };

  var TABS = {
    account: [
      { key: "fullName", label: "اسم الحساب", icon: "person", hint: "الاسم الذي سيظهر للعملاء داخل الملف التعريفي.", wide: true },
      { key: "accountType", label: "صفة الحساب", icon: "badge", hint: "اختر الصفة المناسبة كما ستظهر داخل الملف التعريفي.", isChoice: true, options: [
        { value: "individual", label: "فرد" },
        { value: "company", label: "منشأة" }
      ] },
      { key: "mobilePhone", label: "رقم الجوال", icon: "phone", hint: "رقم الجوال المرتبط بتسجيل الدخول. لتغييره اذهب إلى إعدادات الحساب.", readOnly: true },
      { key: "about", label: "نبذة عنك", icon: "info", hint: "تعريف مختصر بك أو بجهتك كما يراه العميل.", multiline: true, wide: true },
      { key: "location", label: "المدينة", icon: "location", hint: "اختر المدينة الأساسية التي تعمل منها.", isCity: true },
      { key: "accountEmail", label: "البريد الإلكتروني", icon: "email", hint: "البريد الإلكتروني الأساسي المرتبط بحسابك.", inputType: "email", inputMode: "email", placeholder: "name@example.com", dir: "ltr", autocomplete: "email" }
    ],
    general: [
      { key: "experience", label: "سنوات الخبرة", icon: "work", hint: "أدخل رقمًا تقريبيًا يوضح خبرتك في المجال." },
      { key: "languages", label: "لغات التواصل", icon: "language", hint: "اختر اللغات التي تتواصل بها مع العملاء.", languageField: true, wide: true },
      { key: "specialization", label: "تفاصيل إضافية", icon: "category", hint: "أضف وصفًا أوسع عن مجالك أو طريقة عملك.", multiline: true, wide: true },
      { key: "serviceLocation", label: "الموقع", icon: "map_pin", hint: "اضغط على الخريطة أو اسحب المؤشر لتحديد موقعك الدقيق داخل المدينة المختارة.", mapField: true, wide: true },
      { key: "coverageRadius", label: "نطاق الخدمة", icon: "radius", hint: "اختر نصف قطر التغطية بالكيلومتر وسيظهر كنطاق دائري حول موقعك.", radiusField: true, wide: true, inputType: "number", inputMode: "numeric", min: "0", step: "1", placeholder: "مثال: 2" }
    ],
    extra: [
      { key: "details", label: "شرح تفصيلي", icon: "notes", hint: "قدّم وصفًا أوسع للخدمات أو أسلوب العمل أو التخصص.", multiline: true, wide: true },
      { key: "qualification", label: "المؤهلات", icon: "school", hint: "افصل بين المؤهلات بفاصلة عند إدخال أكثر من عنصر.", wide: true },
      { key: "experiences", label: "الخبرات العملية", icon: "work", hint: "أضف خبراتك أو المشاريع المنجزة، ويفضل كتابة كل عنصر في سطر مستقل.", multiline: true, wide: true },
      { key: "website", label: "الموقع الإلكتروني", icon: "link", hint: "أدخل الرابط الكامل إذا كان لديك موقع أو صفحة تعريفية." },
      { key: "xUrl", platform: "x", label: "منصة X", icon: "x", hint: "أدخل رابط الحساب أو اسم المستخدم على منصة X.", inputType: "url", inputMode: "url", placeholder: "https://x.com/username", dir: "ltr", autocomplete: "url" },
      { key: "snapchatUrl", platform: "snapchat", label: "منصة سناب شات", icon: "snapchat", hint: "أدخل رابط الحساب أو اسم المستخدم على سناب شات.", inputType: "url", inputMode: "url", placeholder: "https://snapchat.com/add/username", dir: "ltr", autocomplete: "url" },
      { key: "instagramUrl", platform: "instagram", label: "منصة انستقرام", icon: "instagram", hint: "أدخل رابط الحساب أو اسم المستخدم على انستقرام.", inputType: "url", inputMode: "url", placeholder: "https://instagram.com/username", dir: "ltr", autocomplete: "url" },
      { key: "facebookUrl", platform: "facebook", label: "منصة فيس بوك", icon: "facebook", hint: "أدخل رابط الصفحة أو اسم المستخدم على فيس بوك.", inputType: "url", inputMode: "url", placeholder: "https://facebook.com/username", dir: "ltr", autocomplete: "url" },
      { key: "tiktokUrl", platform: "tiktok", label: "منصة تيك توك", icon: "tiktok", hint: "أدخل رابط الحساب أو اسم المستخدم على تيك توك.", inputType: "url", inputMode: "url", placeholder: "https://tiktok.com/@username", dir: "ltr", autocomplete: "url" },
      { key: "contactEmail", platform: "email", label: "بريد التواصل", icon: "email", hint: "بريد التواصل الذي ترغب بإظهاره للعملاء داخل الملف العام.", inputType: "email", inputMode: "email", placeholder: "name@example.com", dir: "ltr", autocomplete: "email" },
      { key: "phone", label: "واتساب التواصل", icon: "phone", hint: "رقم واتساب الذي ترغب بإظهاره للعملاء داخل الملف العام.", inputType: "tel", inputMode: "numeric", maxLength: "10", placeholder: "05XXXXXXXX" },
      { key: "seoPreview", label: "معاينة النتيجة", icon: "search", readOnly: true, wide: true, seoPreviewField: true },
      { key: "seoTitle", label: "عنوان SEO", icon: "headline", hint: "العنوان الذي سيظهر في نتائج البحث وعند مشاركة الصفحة. يفضّل أن يكون واضحًا ومباشرًا.", wide: true, inputType: "text", maxLength: "160", placeholder: "مثال: مصمم واجهات وتجارب رقمية في الرياض", seoMetric: "title" },
      { key: "seoMetaDescription", label: "وصف الصفحة (Meta Description)", icon: "notes", hint: "وصف مختصر يشرح طبيعة الخدمة ويزيد من قابلية النقر من نتائج البحث.", multiline: true, wide: true, maxLength: "320", placeholder: "مثال: أقدّم تصميم واجهات وتجارب رقمية للمتاجر والمواقع مع تركيز على السرعة والتحويل.", seoMetric: "description" },
      { key: "seoSlug", label: "الرابط المخصص", icon: "link", hint: "جزء الرابط الذي يسهّل قراءة الصفحة. استخدم كلمات قصيرة وواضحة.", dir: "ltr", autocomplete: "off", maxLength: "150", placeholder: "designer-riyadh", seoMetric: "slug" },
      { key: "keywords", label: "الكلمات المفتاحية", icon: "label", hint: "اكتب كلمات أو عبارات قصيرة تفصل بينها فاصلة أو سطر جديد، مثل: تصميم واجهات، تجربة مستخدم، مواقع أعمال.", multiline: true, wide: true, maxLength: "500", placeholder: "تصميم واجهات، تجربة مستخدم، مواقع أعمال", seoMetric: "keywords" }
    ]
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

  function getCityCenter(city) {
    var center = CITY_COORDINATES[String(city || "").trim()];
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
      ? parseInt(serviceRadiusDraft, 10)
      : parseInt(profile && profile.coverageRadius, 10);
    return Number.isFinite(radius) && radius >= 0 ? radius : 0;
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
    var radius = Number.isFinite(Number(value)) ? Math.max(0, parseInt(value, 10)) : 0;
    serviceRadiusDraft = radius;
    var range = document.getElementById("pe-radius-range");
    var numberInput = document.getElementById("pe-radius-number");
    var label = document.getElementById("pe-radius-live-value");
    if (range) range.value = String(radius);
    if (numberInput) numberInput.value = String(radius);
    if (label) label.textContent = radius + " كم";
    updateServiceRadiusPreview(radius);
  }

  function updateServiceRadiusPreview(radiusKm) {
    var radius = Math.max(0, parseInt(radiusKm, 10) || 0);
    if (serviceMapCircle && serviceMapMarker) {
      serviceMapCircle.setLatLng(serviceMapMarker.getLatLng());
      serviceMapCircle.setRadius(radius * 1000);
      if (typeof serviceMapCircle.redraw === "function") serviceMapCircle.redraw();
    }
    var helper = document.getElementById("pe-radius-helper");
    if (helper) {
      helper.textContent = radius > 0
        ? ("سيظهر نطاق الخدمة كدائرة حول موقعك بقطر تقريبي " + (radius * 2) + " كم.")
        : "اختر نصف قطر التغطية ليظهر كنطاق دائري حول موقعك.";
    }
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
    if (url.indexOf("instagram") !== -1) return "instagram";
    if (url.indexOf("snapchat") !== -1) return "snapchat";
    if (url.indexOf("tiktok") !== -1) return "tiktok";
    if (url.indexOf("facebook") !== -1 || url.indexOf("fb.com") !== -1) return "facebook";
    if (url.indexOf("x.com") !== -1 || url.indexOf("twitter") !== -1) return "x";
    return "";
  }

  function socialFieldKeyFromPlatform(platform) {
    switch (normalizeSocialPlatform(platform)) {
      case "x": return "xUrl";
      case "snapchat": return "snapchatUrl";
      case "instagram": return "instagramUrl";
      case "facebook": return "facebookUrl";
      case "tiktok": return "tiktokUrl";
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
      xUrl: "",
      snapchatUrl: "",
      instagramUrl: "",
      facebookUrl: "",
      tiktokUrl: "",
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
      case "xUrl":
        return text.match(/x\.com|twitter\.com|^https?:\/\//i) ? ensureAbsoluteUrl(text) : ("https://x.com/" + text.replace(/^@+/, ""));
      case "snapchatUrl":
        return text.match(/snapchat\.com|^https?:\/\//i) ? ensureAbsoluteUrl(text) : ("https://snapchat.com/add/" + text.replace(/^@+/, ""));
      case "instagramUrl":
        return text.match(/instagram\.com|^https?:\/\//i) ? ensureAbsoluteUrl(text) : ("https://instagram.com/" + text.replace(/^@+/, ""));
      case "facebookUrl":
        return text.match(/facebook\.com|fb\.com|^https?:\/\//i) ? ensureAbsoluteUrl(text) : ("https://facebook.com/" + text.replace(/^@+/, ""));
      case "tiktokUrl":
        return text.match(/tiktok\.com|^https?:\/\//i) ? ensureAbsoluteUrl(text) : ("https://tiktok.com/@" + text.replace(/^@+/, ""));
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

  function buildSocialLinksPayload(values) {
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
    return items.concat(Array.isArray(profile.socialExtras) ? profile.socialExtras : []);
  }

  function applySocialState(state) {
    var nextState = state || extractSocialState([]);
    profile.socialExtras = Array.isArray(nextState.extras) ? nextState.extras : [];
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
        avatarBadge.textContent = topBadge.name || topBadge.code || "شارة تميز";
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
        congratsNode.textContent = issuedOn
          ? ("تهانينا! حصلت على شارة " + (newBadge.name || "التميز") + " بتاريخ " + issuedOn + " وتم نشرها تلقائيًا في ملفك.")
          : ("تهانينا! حصلت على شارة " + (newBadge.name || "التميز") + " وتم نشرها تلقائيًا في ملفك.");
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

    uploadBtn.addEventListener("click", function () {
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

      uploadBtn.style.opacity = "0.5";
      uploadBtn.style.pointerEvents = "none";

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
        var avatarImg = document.getElementById("pe-avatar-img");
        var avatarFallback = document.getElementById("pe-avatar-fallback");
        if (avatarImg && newUrl) {
          avatarImg.src = newUrl;
          avatarImg.classList.remove("hidden");
          if (avatarFallback) avatarFallback.classList.add("hidden");
        }
        if (typeof NwToast !== "undefined") NwToast.success("تم تحديث الصورة بنجاح");
      }).catch(function (err) {
        alert((err && err.message) || "تعذر رفع الصورة، حاول مرة أخرى");
      }).finally(function () {
        uploadBtn.style.opacity = "";
        uploadBtn.style.pointerEvents = "";
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
    root.innerHTML = SECTION_LINKS.map(function (item) {
      var active = item.key === activeKey;
      return '<a class="pe-section-link' + (active ? ' is-active' : '') + '" href="' + item.href + '">' +
        '<span class="pe-section-link-label">' + escapeHtml(item.label) + '</span>' +
      '</a>';
    }).join("");
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

    var categories = uniqueNonEmpty(myServices.map(function (service) {
      var sub = service && service.subcategory ? service.subcategory : {};
      return sub.category_name || (sub.category && sub.category.name) || "";
    }));

    var subcategories = uniqueNonEmpty(myServices.map(function (service) {
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
    if (profile.location) contactLines.push("المدينة: " + profile.location);
    if (email) contactLines.push("البريد: " + email);

    return '<div class="pe-summary-grid">' +
      buildSummaryCard("الاسم والحساب", accountLines.join("\n")) +
      buildSummaryCard("التصنيف والتخصص", specializationLines.join("\n")) +
      buildSummaryCard("التواصل الأساسي", contactLines.join("\n")) +
      buildSummaryCard("نبذة التسجيل", profile.about || "") +
    '</div>';
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
    });
    if (!cfg) return;
    var targetPanel = document.getElementById("pe-panel-" + cfg.tab);
    if (!targetPanel) return;
    targetPanel.classList.add("active");
    if (cfg.mode === "summary") {
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
      case "instagram":
        return '<svg width="18" height="18" viewBox="0 0 24 24" fill="none"><rect x="3" y="3" width="18" height="18" rx="5" stroke="#E1306C" stroke-width="2"/><circle cx="12" cy="12" r="4" stroke="#E1306C" stroke-width="2"/><circle cx="17.5" cy="6.5" r="1.4" fill="#E1306C"/></svg>';
      case "x":
        return '<svg width="18" height="18" viewBox="0 0 24 24" fill="#111"><path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z"/></svg>';
      case "snapchat":
        return '<svg width="18" height="18" viewBox="0 0 24 24" fill="none"><path d="M12 3c3.06 0 5.2 2.26 5.2 5.14 0 .8-.19 1.51-.56 2.16.36.56.93 1 1.73 1.34.31.13.49.43.43.77-.06.36-.34.62-.69.68-.56.09-.99.17-1.37.28-.43 1-1.12 1.82-2.02 2.38-.22.13-.49.13-.71 0-.9-.56-1.59-1.38-2.02-2.38-.38-.11-.81-.19-1.37-.28-.35-.06-.63-.32-.69-.68-.06-.34.12-.64.43-.77.8-.34 1.37-.78 1.73-1.34-.37-.65-.56-1.36-.56-2.16C6.8 5.26 8.94 3 12 3z" fill="#FFFC00" stroke="#111" stroke-width="1.2"/></svg>';
      case "facebook":
        return '<svg width="18" height="18" viewBox="0 0 24 24" fill="none"><path d="M13.5 21v-7h2.4l.36-2.8H13.5V9.42c0-.81.23-1.36 1.39-1.36H16.4V5.56c-.26-.03-1.14-.11-2.18-.11-2.16 0-3.64 1.32-3.64 3.74v2.01H8.2V14h2.38v7h2.92z" fill="#1877F2"/></svg>';
      case "tiktok":
        return '<svg width="18" height="18" viewBox="0 0 24 24" fill="none"><path d="M14.5 3c.4 1.77 1.45 3.14 3.19 3.73v2.58a6.55 6.55 0 0 1-3.11-1v5.64a5.45 5.45 0 1 1-5.45-5.45c.3 0 .6.03.88.08v2.71a2.74 2.74 0 1 0 1.86 2.59V3h2.63z" fill="#111"/><path d="M14.5 3c.4 1.77 1.45 3.14 3.19 3.73" stroke="#25F4EE" stroke-width="1.2"/><path d="M12.64 13.88a2.74 2.74 0 1 1-2.63-3.45" stroke="#FE2C55" stroke-width="1.2"/></svg>';
      case "email":
        return '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#2563EB" stroke-width="2"><rect x="3" y="5" width="18" height="14" rx="2"/><path d="M4 7l8 6 8-6"/></svg>';
      case "phone":
        return '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72 12.84 12.84 0 0 0 .7 2.81 2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7A2 2 0 0 1 22 16.92z"/></svg>';
      case "label":
        return '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M20.59 13.41L11 3H4v7l9.59 9.59a2 2 0 0 0 2.82 0l4.18-4.18a2 2 0 0 0 0-2.82z"/><circle cx="7.5" cy="7.5" r="1.5"/></svg>';
      case "search":
        return '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/></svg>';
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
    if (display) display.innerHTML = displayValue(profile[key], cfg);
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

    if (key === "location") {
      var cityLabel = document.querySelector(".pe-map-city");
      if (cityLabel) cityLabel.textContent = "المدينة الحالية: " + (profile.location || "غير محددة");
      centerServiceMapOnCity(!hasPreciseCoordinates());
    }

    if (key === "coverageRadius") {
      syncRadiusInputs(profile.coverageRadius || 0);
    }

    if (isSeoFieldKey(key)) {
      updateSeoFieldFeedback(key);
      updateSeoPreview();
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

  function sanitizePhone(value) {
    return String(value || "").replace(/[^\d]/g, "").slice(0, 10);
  }

  function normalizePhone05(value) {
    var digits = sanitizePhone(value);
    return /^05\d{8}$/.test(digits) ? digits : "";
  }

  function loadProfile() {
    Promise.all([
      safeGet("/api/accounts/me/"),
      safeGet("/api/providers/me/profile/"),
      optionalGet("/api/providers/me/services/")
    ]).then(function (res) {
      var userResp = res[0] || {};
      var provResp = res[1] || {};
      var servicesResp = res[2] || {};
      if (!provResp.ok || !provResp.data) {
        throw new Error("provider_profile_not_found");
      }
      var user = userResp.ok && userResp.data ? userResp.data : {};
      var prov = provResp.data || {};
      var languageState = extractLanguageState(prov.languages);
      var socialState = extractSocialState(prov.social_links);
      userProfile = user;
      myServices = servicesResp.ok && servicesResp.data ? extractList(servicesResp.data) : [];
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
        location: prov.city || "",
        coverageRadius: prov.coverage_radius_km === null || prov.coverage_radius_km === undefined ? "" : String(prov.coverage_radius_km),
        latitude: formatCoord(prov.lat),
        longitude: formatCoord(prov.lng),
        details: prov.about_details || "",
        qualification: Array.isArray(prov.qualifications) ? prov.qualifications.map(function (q) { return q.title || q; }).join("، ") : "",
        experiences: Array.isArray(prov.experiences) ? prov.experiences.map(function (item) { return normalizeListEntry(item, ["title", "name", "label"]); }).filter(Boolean).join("\n") : "",
        website: prov.website || "",
        social: Array.isArray(prov.social_links) ? prov.social_links.map(function (s) { return s.url || s; }).join("\n") : "",
        xUrl: socialState.values.xUrl || "",
        snapchatUrl: socialState.values.snapchatUrl || "",
        instagramUrl: socialState.values.instagramUrl || "",
        facebookUrl: socialState.values.facebookUrl || "",
        tiktokUrl: socialState.values.tiktokUrl || "",
        contactEmail: socialState.values.contactEmail || "",
        socialExtras: socialState.extras || [],
        mobilePhone: user.phone || "",
        accountEmail: user.email || "",
        phone: prov.whatsapp || user.phone || "",
        seoTitle: prov.seo_title || "",
        keywords: prov.seo_keywords || "",
        seoMetaDescription: prov.seo_meta_description || "",
        seoSlug: prov.seo_slug || ""
      };
      serviceRadiusDraft = prov.coverage_radius_km === null || prov.coverage_radius_km === undefined
        ? 0
        : Math.max(0, parseInt(prov.coverage_radius_km, 10) || 0);
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

  function buildLanguageField(f) {
    return '<article class="pe-field pe-field-wide pe-language-field" data-key="' + f.key + '">' +
      '<div class="pe-field-head">' +
        '<div class="pe-field-title-wrap">' +
          '<span class="pe-field-icon" aria-hidden="true">' + iconSvg(f.icon) + '</span>' +
          '<div class="pe-field-copy">' +
            '<span class="pe-field-label">' + f.label + '</span>' +
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
    return '<article class="pe-field pe-field-wide pe-map-field" data-key="' + f.key + '">' +
      '<div class="pe-field-head">' +
        '<div class="pe-field-title-wrap">' +
          '<span class="pe-field-icon" aria-hidden="true">' + iconSvg(f.icon) + '</span>' +
          '<div class="pe-field-copy">' +
            '<span class="pe-field-label">' + f.label + '</span>' +
          '</div>' +
        '</div>' +
      '</div>' +
      '<div class="pe-map-caption">' + escapeHtml(f.hint || '') + '</div>' +
      '<div class="pe-service-map" id="pe-service-map"></div>' +
      '<div class="pe-map-meta">' +
        '<span class="pe-map-city">المدينة الحالية: ' + escapeHtml(profile.location || 'غير محددة') + '</span>' +
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
    return '<article class="pe-field pe-field-wide pe-radius-field" data-key="' + f.key + '">' +
      '<div class="pe-field-head">' +
        '<div class="pe-field-title-wrap">' +
          '<span class="pe-field-icon" aria-hidden="true">' + iconSvg(f.icon) + '</span>' +
          '<div class="pe-field-copy">' +
            '<span class="pe-field-label">' + f.label + '</span>' +
          '</div>' +
        '</div>' +
      '</div>' +
      '<div class="pe-radius-live">القيمة الحالية: <strong id="pe-radius-live-value">' + radius + ' كم</strong></div>' +
      '<div class="pe-radius-controls">' +
        '<input type="range" min="0" max="100" step="1" value="' + radius + '" class="pe-radius-range" id="pe-radius-range">' +
        '<input type="number" class="form-input pe-input pe-radius-number" id="pe-radius-number" data-key="coverageRadius" min="0" step="1" value="' + radius + '" inputmode="numeric">' +
      '</div>' +
      '<div class="pe-radius-helper" id="pe-radius-helper"></div>' +
      '<div class="pe-field-actions">' +
        '<button type="button" class="btn btn-primary pe-save-btn" data-key="coverageRadius">حفظ</button>' +
      '</div>' +
    '</article>';
  }

  function buildField(f) {
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
      (f.key === "mobilePhone" ? '<div class="pe-field-readonly-action"><a href="/login-settings/" class="pe-inline-link">تغيير رقم الجوال ←</a></div>' : '') +
      (!f.readOnly ? '<div class="pe-field-edit" style="display:none">' +
        (f.isCity ? '<select class="form-select pe-input" data-key="' + f.key + '"><option value="">اختر المدينة</option>' + CITIES.map(function (c) { return '<option' + (c === val ? ' selected' : '') + '>' + c + '</option>'; }).join("") + '</select>'
          : f.isChoice ? '<select class="form-select pe-input" data-key="' + f.key + '">' + (Array.isArray(f.options) ? f.options.map(function (option) { return '<option value="' + escapeHtml(option.value) + '"' + (String(option.value) === String(val) ? ' selected' : '') + '>' + escapeHtml(option.label) + '</option>'; }).join("") : "") + '</select>'
          : f.multiline ? '<textarea class="form-input form-textarea pe-input" rows="4"' + attrs + '>' + safeVal + '</textarea>'
          : '<input type="' + (f.inputType || "text") + '" class="form-input pe-input"' + attrs + ' value="' + safeVal + '">') +
        (f.seoMetric ? buildSeoFieldMeta(f) : '') +
        '<div class="pe-field-actions' + (f.geoAction ? ' has-secondary' : '') + '">' +
          (f.geoAction ? '<button class="btn btn-secondary pe-geo-btn" type="button" data-key="' + f.key + '">استخدام موقعي الحالي</button>' : '') +
          '<button type="button" class="btn btn-primary pe-save-btn" data-key="' + f.key + '">حفظ</button>' +
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
      });
    });
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
    var apiKey = FIELD_MAP[key];
    if (!apiKey) return;
    var input = document.querySelector('.pe-input[data-key="' + key + '"]');
    var val = input ? input.value.trim() : "";
    var nextValue = val;
    var payload = {};

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
          payload[apiKey] = buildSocialLinksPayload(socialValues);
          nextValue = String(socialValues[key] || "").trim();
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

    field.style.boxShadow = "0 0 0 2px rgba(103,58,183,0.22)";
    setTimeout(function () { field.style.boxShadow = ""; }, 1600);

    var input = field.querySelector('.pe-input[data-key="' + fieldKey + '"]');
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
