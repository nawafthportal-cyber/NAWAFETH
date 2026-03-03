"use strict";
var ProviderProfileEditPage = (function () {
  var RAW_API = window.ApiClient;
  var API = window.NwApiClient;
  var CITIES = ["الرياض","جدة","مكة المكرمة","المدينة المنورة","الدمام","الخبر","الظهران","الطائف","تبوك","بريدة","عنيزة","حائل","أبها","خميس مشيط","نجران","جازان","ينبع","الباحة","الجبيل","حفر الباطن","القطيف","الأحساء","سكاكا","عرعر","بيشة","الخرج","الدوادمي","المجمعة","القويعية","وادي الدواسر"];
  var profile = null;
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

  var FIELD_MAP = {
    fullName: "display_name", accountType: "provider_type", about: "bio",
    specialization: "about_details", experience: "years_experience",
    languages: "languages", location: "city", details: "about_details",
    qualification: "qualifications", website: "website", social: "social_links",
    phone: "whatsapp", keywords: "seo_keywords"
  };

  var TYPE_LABELS = { individual: "فرد", company: "مؤسسة", freelancer: "مستقل" };

  var TABS = {
    account: [
      { key: "fullName", label: "اسم العرض", icon: "person" },
      { key: "accountType", label: "صفة الحساب", icon: "badge", readOnly: true },
      { key: "about", label: "نبذة عنك", icon: "info", multiline: true },
      { key: "specialization", label: "تفاصيل إضافية", icon: "category", multiline: true }
    ],
    general: [
      { key: "experience", label: "سنوات الخبرة", icon: "work" },
      { key: "languages", label: "لغات التواصل", icon: "language" },
      { key: "location", label: "المدينة", icon: "location", isCity: true }
    ],
    extra: [
      { key: "details", label: "شرح تفصيلي", icon: "notes", multiline: true },
      { key: "qualification", label: "المؤهلات", icon: "school" },
      { key: "website", label: "الموقع الإلكتروني", icon: "link" },
      { key: "social", label: "روابط التواصل", icon: "share", multiline: true },
      { key: "phone", label: "واتساب", icon: "phone" },
      { key: "keywords", label: "الكلمات المفتاحية (SEO)", icon: "label", multiline: true }
    ]
  };

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

  function safeGet(path) {
    if (RAW_API && typeof RAW_API.get === "function") {
      return RAW_API.get(path);
    }
    return API.get(path).then(function (data) {
      return { ok: !!data, status: data ? 200 : 0, data: data };
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
      safeGet("/api/accounts/profile/me/"),
      safeGet("/api/providers/me/profile/")
    ]).then(function (res) {
      var userResp = res[0] || {};
      var provResp = res[1] || {};
      if (!provResp.ok || !provResp.data) {
        throw new Error("provider_profile_not_found");
      }
      var user = userResp.ok && userResp.data ? userResp.data : {};
      var prov = provResp.data || {};
      profile = {
        fullName: prov.display_name || "",
        accountType: TYPE_LABELS[prov.provider_type] || prov.provider_type || "",
        about: prov.bio || "",
        specialization: prov.about_details || "",
        experience: prov.years_experience > 0 ? prov.years_experience + " سنوات" : "",
        languages: Array.isArray(prov.languages) ? prov.languages.map(function (l) { return l.name || l; }).join("، ") : "",
        location: prov.city || "",
        details: prov.about_details || "",
        qualification: Array.isArray(prov.qualifications) ? prov.qualifications.map(function (q) { return q.title || q; }).join("، ") : "",
        website: prov.website || "",
        social: Array.isArray(prov.social_links) ? prov.social_links.map(function (s) { return s.url || s; }).join("\n") : "",
        phone: prov.whatsapp || user.phone || "",
        keywords: prov.seo_keywords || ""
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
    Object.keys(TABS).forEach(function (tab) {
      var panel = document.getElementById("pe-panel-" + tab);
      panel.innerHTML = TABS[tab].map(function (f) {
        return buildField(f);
      }).join("");
    });
    bindFieldEvents();
  }

  function buildField(f) {
    var val = profile[f.key] || "";
    var safeVal = escapeHtml(val);
    return '<div class="pe-field" data-key="' + f.key + '">' +
      '<div class="pe-field-header"><span class="pe-field-label">' + f.label + '</span>' +
      (!f.readOnly ? '<button class="btn-icon pe-edit-btn" data-key="' + f.key + '"><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#663D90" stroke-width="2"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/></svg></button>' : '') +
      '</div>' +
      '<div class="pe-field-display">' + (safeVal || '<span class="text-muted">—</span>') + '</div>' +
      '<div class="pe-field-edit" style="display:none">' +
      (f.isCity ? '<select class="form-select pe-input" data-key="' + f.key + '"><option value="">اختر المدينة</option>' + CITIES.map(function (c) { return '<option' + (c === val ? ' selected' : '') + '>' + c + '</option>'; }).join("") + '</select>'
        : f.multiline ? '<textarea class="form-input pe-input" rows="3" data-key="' + f.key + '">' + safeVal + '</textarea>'
        : '<input type="text" class="form-input pe-input" data-key="' + f.key + '" value="' + safeVal + '">') +
      '<button class="btn btn-sm btn-primary pe-save-btn" data-key="' + f.key + '">حفظ</button>' +
      '</div></div>';
  }

  function bindFieldEvents() {
    document.querySelectorAll(".pe-edit-btn").forEach(function (btn) {
      btn.addEventListener("click", function () {
        var key = this.dataset.key;
        var field = document.querySelector('.pe-field[data-key="' + key + '"]');
        field.querySelector(".pe-field-display").style.display = "none";
        field.querySelector(".pe-field-edit").style.display = "";
        this.style.display = "none";
      });
    });
    document.querySelectorAll(".pe-save-btn").forEach(function (btn) {
      btn.addEventListener("click", function () { saveField(this.dataset.key, this); });
    });
  }

  function saveField(key, btn) {
    var apiKey = FIELD_MAP[key];
    if (!apiKey) return;
    var input = document.querySelector('.pe-input[data-key="' + key + '"]');
    var val = input.value.trim();
    var payload = {};

    switch (apiKey) {
      case "years_experience": payload[apiKey] = parseInt(val.replace(/[^\d]/g, "")) || 0; break;
      case "languages": payload[apiKey] = val.split(/[،,]/).filter(Boolean).map(function (s) { return { name: s.trim() }; }); break;
      case "qualifications": payload[apiKey] = val.split(/[،,]/).filter(Boolean).map(function (s) { return { title: s.trim() }; }); break;
      case "social_links": payload[apiKey] = val.split("\n").filter(Boolean).map(function (s) { return { url: s.trim() }; }); break;
      default: payload[apiKey] = val;
    }

    btn.disabled = true; btn.textContent = "جاري الحفظ...";
    safePatch("/api/providers/me/profile/", payload).then(function (resp) {
      if (!resp || !resp.ok) {
        throw new Error(apiErrorMessage(resp ? resp.data : null, "فشل في الحفظ"));
      }
      profile[key] = val;
      var field = document.querySelector('.pe-field[data-key="' + key + '"]');
      field.querySelector(".pe-field-display").innerHTML = escapeHtml(val) || '<span class="text-muted">—</span>';
      field.querySelector(".pe-field-display").style.display = "";
      field.querySelector(".pe-field-edit").style.display = "none";
      var editBtn = field.querySelector(".pe-edit-btn");
      if (editBtn) editBtn.style.display = "";
    }).catch(function (err) {
      alert((err && err.message) ? err.message : "فشل في الحفظ");
    }).finally(function () {
      btn.disabled = false; btn.textContent = "حفظ";
    });
  }

  function activateTab(name) {
    var tabsWrap = document.getElementById("pe-tabs");
    if (!tabsWrap || !name) return;
    var tabBtn = tabsWrap.querySelector('.tab[data-tab="' + name + '"]');
    if (!tabBtn) return;
    tabsWrap.querySelectorAll(".tab").forEach(function (t) { t.classList.toggle("active", t === tabBtn); });
    document.querySelectorAll(".tab-panel").forEach(function (p) { p.classList.toggle("active", p.dataset.panel === name); });
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

    var display = field.querySelector(".pe-field-display");
    var editBlock = field.querySelector(".pe-field-edit");
    var editBtn = field.querySelector(".pe-edit-btn");
    if (display && editBlock && editBtn) {
      display.style.display = "none";
      editBlock.style.display = "";
      editBtn.style.display = "none";
    }

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
