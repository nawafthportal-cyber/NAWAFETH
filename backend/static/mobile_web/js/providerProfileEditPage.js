"use strict";
var ProviderProfileEditPage = (function () {
  var RAW_API = window.ApiClient;
  var API = window.NwApiClient;
  var CITIES = ["الرياض","جدة","مكة المكرمة","المدينة المنورة","الدمام","الخبر","الظهران","الطائف","تبوك","بريدة","عنيزة","حائل","أبها","خميس مشيط","نجران","جازان","ينبع","الباحة","الجبيل","حفر الباطن","القطيف","الأحساء","سكاكا","عرعر","بيشة","الخرج","الدوادمي","المجمعة","القويعية","وادي الدواسر"];
  var profile = null;
  var userProfile = null;
  var myServices = [];
  var initialTab = null;
  var initialFocus = null;
  var initialSection = null;

  var SECTION_TITLES = {
    basic: "البيانات الأساسية",
    service_details: "تفاصيل الخدمة",
    additional: "معلومات إضافية",
    contact_full: "معلومات التواصل",
    lang_loc: "اللغة ونطاق الخدمة",
    seo: "SEO والكلمات المفتاحية"
  };

  var SECTION_CONFIG = {
    basic: {
      tab: "account",
      mode: "summary",
      kicker: "تمت تعبئتها أثناء التسجيل الأولي",
      heading: "بيانات التسجيل الأساسية",
      intro: "هذه البيانات مرتبطة بالتسجيل الأساسي وتظهر هنا بصيغة ملخصة مشابهة لشاشة التطبيق على الجوال."
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
      fields: ["phone", "website", "social"],
      kicker: "قنوات الوصول إليك",
      heading: "معلومات التواصل",
      intro: "أكمل وسائل التواصل والروابط التي تساعد العميل على الوصول إليك بسرعة وبصورة مباشرة."
    },
    lang_loc: {
      tab: "general",
      fields: ["languages", "location", "coverageRadius", "latitude", "longitude"],
      kicker: "التغطية اللغوية والجغرافية",
      heading: "اللغة ونطاق الخدمة",
      intro: "حدد اللغات التي تعمل بها والمنطقة التي تغطيها حتى تظهر خدمتك للعملاء المناسبين في المواقع الصحيحة."
    },
    seo: {
      tab: "extra",
      fields: ["keywords", "seoMetaDescription", "seoSlug"],
      kicker: "الظهور في البحث",
      heading: "SEO والكلمات المفتاحية",
      intro: "أضف الكلمات المفتاحية ووصف الميتا والرابط المختصر لتحسين ظهورك داخل البحث وعلى صفحات الخدمة."
    }
  };

  var SECTION_LINKS = [
    { key: "basic", label: "البيانات الأساسية", href: "/provider-profile-edit/?tab=account&focus=fullName&section=basic" },
    { key: "service_details", label: "تفاصيل الخدمة", href: "/provider-profile-edit/?tab=account&focus=about&section=service_details" },
    { key: "additional", label: "معلومات إضافية", href: "/provider-profile-edit/?tab=extra&focus=details&section=additional" },
    { key: "contact_full", label: "معلومات التواصل", href: "/provider-profile-edit/?tab=extra&focus=phone&section=contact_full" },
    { key: "lang_loc", label: "اللغة ونطاق الخدمة", href: "/provider-profile-edit/?tab=general&focus=coverageRadius&section=lang_loc" },
    { key: "content", label: "محتوى أعمالك", href: "/provider-portfolio/?from=profile-completion&section=content" },
    { key: "seo", label: "SEO والكلمات المفتاحية", href: "/provider-profile-edit/?tab=extra&focus=keywords&section=seo" }
  ];

  var TAB_META = {
    account: {
      label: "معلومات الحساب",
      summary: "حدّث الاسم، صفة الحساب، والنبذة التي تظهر للعملاء داخل الملف التعريفي."
    },
    general: {
      label: "معلومات عامة",
      summary: "أضف الخبرة، المدينة، اللغات، ونطاق الخدمة مع الموقع الجغرافي عند الحاجة."
    },
    extra: {
      label: "معلومات إضافية",
      summary: "أكمل المؤهلات، الروابط، التفاصيل الموسعة، والكلمات المفتاحية لتحسين ظهورك."
    }
  };

  var SECTION_META = {
    basic: {
      label: "البيانات الأساسية",
      summary: "حرّر الاسم، صفة الحساب، والنبذة المختصرة التي تظهر داخل ملفك التعريفي."
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
      label: "SEO والكلمات المفتاحية",
      summary: "أضف الكلمات المفتاحية التي ترفع قابلية ظهورك في البحث داخل المنصة."
    }
  };

  var FIELD_MAP = {
    fullName: "display_name", accountType: "provider_type", about: "bio",
    specialization: "about_details", experience: "years_experience",
    languages: "languages", location: "city", coverageRadius: "coverage_radius_km",
    latitude: "lat", longitude: "lng", details: "about_details",
    qualification: "qualifications", experiences: "experiences", website: "website", social: "social_links",
    phone: "whatsapp", keywords: "seo_keywords", seoMetaDescription: "seo_meta_description", seoSlug: "seo_slug"
  };

  var TYPE_LABELS = { individual: "فرد", company: "مؤسسة", freelancer: "مستقل" };

  var TABS = {
    account: [
      { key: "fullName", label: "اسم العرض", icon: "person", hint: "الاسم الذي سيظهر للعملاء داخل الملف التعريفي.", wide: true },
      { key: "accountType", label: "صفة الحساب", icon: "badge", hint: "تُحدد أثناء التسجيل ولا يمكن تعديلها من هذه الصفحة.", readOnly: true },
      { key: "about", label: "نبذة عنك", icon: "info", hint: "تعريف مختصر بك أو بجهتك كما يراه العميل.", multiline: true, wide: true },
      { key: "specialization", label: "تفاصيل إضافية", icon: "category", hint: "أضف وصفًا أوسع عن مجالك أو طريقة عملك.", multiline: true, wide: true }
    ],
    general: [
      { key: "experience", label: "سنوات الخبرة", icon: "work", hint: "أدخل رقمًا تقريبيًا يوضح خبرتك في المجال." },
      { key: "languages", label: "لغات التواصل", icon: "language", hint: "افصل بين اللغات بفاصلة عربية أو إنجليزية." },
      { key: "location", label: "المدينة", icon: "location", hint: "اختر المدينة الأساسية التي تعمل منها.", isCity: true },
      { key: "coverageRadius", label: "نطاق الخدمة (كم)", icon: "radius", hint: "المسافة التقريبية التي تغطيها خدماتك.", inputType: "number", inputMode: "numeric", min: "0", step: "1", placeholder: "مثال: 25" },
      { key: "latitude", label: "خط العرض", icon: "my_location", hint: "يمكنك إدخاله يدويًا أو استخدام موقعك الحالي.", inputType: "number", inputMode: "decimal", step: "0.000001", min: "-90", max: "90", placeholder: "مثال: 24.713551", geoAction: true },
      { key: "longitude", label: "خط الطول", icon: "explore", hint: "استخدمه لتحسين دقة موقعك على الخريطة.", inputType: "number", inputMode: "decimal", step: "0.000001", min: "-180", max: "180", placeholder: "مثال: 46.675296" }
    ],
    extra: [
      { key: "details", label: "شرح تفصيلي", icon: "notes", hint: "قدّم وصفًا أوسع للخدمات أو أسلوب العمل أو التخصص.", multiline: true, wide: true },
      { key: "qualification", label: "المؤهلات", icon: "school", hint: "افصل بين المؤهلات بفاصلة عند إدخال أكثر من عنصر.", wide: true },
      { key: "experiences", label: "الخبرات العملية", icon: "work", hint: "أضف خبراتك أو المشاريع المنجزة، ويفضل كتابة كل عنصر في سطر مستقل.", multiline: true, wide: true },
      { key: "website", label: "الموقع الإلكتروني", icon: "link", hint: "أدخل الرابط الكامل إذا كان لديك موقع أو صفحة تعريفية." },
      { key: "social", label: "روابط التواصل", icon: "share", hint: "ضع كل رابط في سطر مستقل لتسهيل عرضه لاحقًا.", multiline: true, wide: true },
      { key: "phone", label: "واتساب", icon: "phone", hint: "رقم التواصل السريع الذي ترغب بإظهاره للعملاء." },
      { key: "keywords", label: "الكلمات المفتاحية (SEO)", icon: "label", hint: "أضف كلمات مرتبطة بتخصصك لتحسين الوصول إليك في البحث.", multiline: true, wide: true },
      { key: "seoMetaDescription", label: "وصف الصفحة (Meta Description)", icon: "notes", hint: "وصف موجز يظهر في نتائج البحث ويشرح طبيعة خدمتك.", multiline: true, wide: true },
      { key: "seoSlug", label: "الرابط المخصص", icon: "link", hint: "اسم رابط مختصر وسهل القراءة لصفحتك أو خدمتك." }
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
    loadProfile();
  }

  function parseEntryQuery() {
    var params = new URLSearchParams(window.location.search || "");
    var tab = (params.get("tab") || "").trim();
    var focus = (params.get("focus") || "").trim();
    var section = (params.get("section") || "").trim();
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
    if (profile.accountType) accountLines.push("نوع الحساب: " + profile.accountType);

    var specializationLines = [];
    if (categories.length) specializationLines.push("التصنيف: " + categories.join("، "));
    if (subcategories.length) specializationLines.push("التخصصات: " + subcategories.join("، "));

    var contactLines = [];
    if (phone) contactLines.push("الجوال: " + phone);
    if (profile.phone) contactLines.push("واتساب: " + profile.phone);
    if (profile.location) contactLines.push("المدينة: " + profile.location);

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
      case "phone":
        return '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72 12.84 12.84 0 0 0 .7 2.81 2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7A2 2 0 0 1 22 16.92z"/></svg>';
      case "label":
        return '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M20.59 13.41L11 3H4v7l9.59 9.59a2 2 0 0 0 2.82 0l4.18-4.18a2 2 0 0 0 0-2.82z"/><circle cx="7.5" cy="7.5" r="1.5"/></svg>';
      default:
        return '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/></svg>';
    }
  }

  function displayValue(value, field) {
    if (value === null || value === undefined || value === "") {
      return '<span class="pe-empty-value">لم تتم إضافة هذه المعلومة بعد</span>';
    }
    var safeValue = escapeHtml(value);
    if (field && field.key === "experience") {
      return safeValue + ' سنوات';
    }
    if (field && field.key === "coverageRadius") {
      return safeValue + ' كم';
    }
    if (field && field.key === "website") {
      return '<a class="pe-inline-link" href="' + safeValue + '" target="_blank" rel="noopener noreferrer">' + safeValue + '</a>';
    }
    return field && field.multiline ? safeValue.replace(/\n/g, "<br>") : safeValue;
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
    if (!field) return;
    var cfg = fieldConfig(key);
    field.querySelector(".pe-field-display").innerHTML = displayValue(profile[key], cfg);
    var input = field.querySelector('.pe-input[data-key="' + key + '"]');
    if (input) input.value = profile[key];
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
      userProfile = user;
      myServices = servicesResp.ok && servicesResp.data ? extractList(servicesResp.data) : [];
      profile = {
        fullName: prov.display_name || "",
        accountType: TYPE_LABELS[prov.provider_type] || prov.provider_type || "",
        about: prov.bio || "",
        specialization: prov.about_details || "",
        experience: prov.years_experience > 0 ? String(prov.years_experience) : "",
        languages: Array.isArray(prov.languages) ? prov.languages.map(function (l) { return l.name || l; }).join("، ") : "",
        location: prov.city || "",
        coverageRadius: prov.coverage_radius_km === null || prov.coverage_radius_km === undefined ? "" : String(prov.coverage_radius_km),
        latitude: formatCoord(prov.lat),
        longitude: formatCoord(prov.lng),
        details: prov.about_details || "",
        qualification: Array.isArray(prov.qualifications) ? prov.qualifications.map(function (q) { return q.title || q; }).join("، ") : "",
        experiences: Array.isArray(prov.experiences) ? prov.experiences.map(function (item) { return normalizeListEntry(item, ["title", "name", "label"]); }).filter(Boolean).join("\n") : "",
        website: prov.website || "",
        social: Array.isArray(prov.social_links) ? prov.social_links.map(function (s) { return s.url || s; }).join("\n") : "",
        phone: prov.whatsapp || user.phone || "",
        keywords: prov.seo_keywords || "",
        seoMetaDescription: prov.seo_meta_description || "",
        seoSlug: prov.seo_slug || ""
      };
      renderAll();
      applyEntryNavigation();
      document.getElementById("pe-loading").style.display = "none";
      document.getElementById("pe-content").style.display = "";
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

  function buildField(f) {
    var val = profile[f.key] || "";
    var safeVal = escapeHtml(val);
    var attrs = ' data-key="' + f.key + '"';
    if (f.placeholder) attrs += ' placeholder="' + escapeHtml(f.placeholder) + '"';
    if (f.inputMode) attrs += ' inputmode="' + f.inputMode + '"';
    if (f.min !== undefined) attrs += ' min="' + f.min + '"';
    if (f.max !== undefined) attrs += ' max="' + f.max + '"';
    if (f.step) attrs += ' step="' + f.step + '"';
    var classes = ["pe-field"];
    if (f.readOnly) classes.push("pe-field-readonly");
    if (f.wide) classes.push("pe-field-wide");
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
        (f.isCity ? '<select class="form-select pe-input" data-key="' + f.key + '"><option value="">اختر المدينة</option>' + CITIES.map(function (c) { return '<option' + (c === val ? ' selected' : '') + '>' + c + '</option>'; }).join("") + '</select>'
          : f.multiline ? '<textarea class="form-input form-textarea pe-input" rows="4" data-key="' + f.key + '">' + safeVal + '</textarea>'
          : '<input type="' + (f.inputType || "text") + '" class="form-input pe-input"' + attrs + ' value="' + safeVal + '">') +
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
    document.querySelectorAll(".pe-geo-btn").forEach(function (btn) {
      btn.addEventListener("click", function () { useCurrentLocation(this); });
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
      var lat = Number(position.coords.latitude);
      var lng = Number(position.coords.longitude);
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
    var val = input.value.trim();
    var nextValue = val;
    var payload = {};

    switch (apiKey) {
      case "years_experience": payload[apiKey] = parseInt(val.replace(/[^\d]/g, "")) || 0; break;
      case "languages": payload[apiKey] = val.split(/[،,]/).filter(Boolean).map(function (s) { return { name: s.trim() }; }); break;
      case "qualifications": payload[apiKey] = val.split(/[،,]/).filter(Boolean).map(function (s) { return { title: s.trim() }; }); break;
      case "experiences": payload[apiKey] = splitEntries(val); break;
      case "social_links": payload[apiKey] = val.split("\n").filter(Boolean).map(function (s) { return { url: s.trim() }; }); break;
      case "coverage_radius_km":
        if (!val) {
          payload[apiKey] = 0;
          nextValue = "0";
          break;
        }
        payload[apiKey] = parseInt(val.replace(/[^\d]/g, ""), 10);
        if (!isFinite(payload[apiKey]) || payload[apiKey] < 0) {
          alert("أدخل نطاق خدمة صحيحًا");
          return;
        }
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
      default: payload[apiKey] = val;
    }

    btn.disabled = true; btn.textContent = "جاري الحفظ...";
    safePatch("/api/providers/me/profile/", payload).then(function (resp) {
      if (!resp || !resp.ok) {
        throw new Error(apiErrorMessage(resp ? resp.data : null, "فشل في الحفظ"));
      }
      var field = document.querySelector('.pe-field[data-key="' + key + '"]');
      setFieldValue(key, nextValue);
      setFieldEditingState(field, false);
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
    });
    document.querySelectorAll(".tab-panel").forEach(function (p) { p.classList.toggle("active", p.dataset.panel === name); });
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

    closeAllEditors(fieldKey);
    setFieldEditingState(field, true);

    field.style.boxShadow = "0 0 0 2px rgba(103,58,183,0.22)";
    setTimeout(function () { field.style.boxShadow = ""; }, 1600);

    var input = field.querySelector('.pe-input[data-key="' + fieldKey + '"]');
    if (input && typeof input.focus === "function") {
      input.focus();
      if (typeof input.select === "function") input.select();
    }
    field.scrollIntoView({ behavior: "smooth", block: "center" });
  }

  function applyEntryNavigation() {
    if (isSectionFlowActive()) {
      var sectionCfg = SECTION_CONFIG[initialSection];
      if (sectionCfg && sectionCfg.tab) activateTab(sectionCfg.tab, true);
      if (!initialFocus || (sectionCfg && sectionCfg.mode === "summary")) return;
      setTimeout(function () { openFieldEditor(initialFocus); }, 80);
      return;
    }
    var tabToOpen = initialTab || (initialFocus ? resolveTabByField(initialFocus) : null);
    if (tabToOpen) activateTab(tabToOpen);
    if (!initialFocus) return;
    setTimeout(function () { openFieldEditor(initialFocus); }, 80);
  }

  function bindTabs() {
    document.getElementById("pe-tabs").addEventListener("click", function (e) {
      var tab = e.target.closest(".tab");
      if (!tab) return;
      activateTab(tab.dataset.tab);
    });
  }

  document.addEventListener("DOMContentLoaded", init);
  return { init: init };
})();
