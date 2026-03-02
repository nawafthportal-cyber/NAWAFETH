"use strict";
var ProviderProfileEditPage = (function () {
  var API = window.NwApiClient;
  var CITIES = ["الرياض","جدة","مكة المكرمة","المدينة المنورة","الدمام","الخبر","الظهران","الطائف","تبوك","بريدة","عنيزة","حائل","أبها","خميس مشيط","نجران","جازان","ينبع","الباحة","الجبيل","حفر الباطن","القطيف","الأحساء","سكاكا","عرعر","بيشة","الخرج","الدوادمي","المجمعة","القويعية","وادي الدواسر"];
  var profile = null;

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
    loadProfile();
    bindTabs();
  }

  function loadProfile() {
    Promise.all([
      API.get("/api/accounts/profile/me/"),
      API.get("/api/providers/me/profile/")
    ]).then(function (res) {
      var user = res[0] || {};
      var prov = res[1] || {};
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
    return '<div class="pe-field" data-key="' + f.key + '">' +
      '<div class="pe-field-header"><span class="pe-field-label">' + f.label + '</span>' +
      (!f.readOnly ? '<button class="btn-icon pe-edit-btn" data-key="' + f.key + '"><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#663D90" stroke-width="2"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/></svg></button>' : '') +
      '</div>' +
      '<div class="pe-field-display">' + (val || '<span class="text-muted">—</span>') + '</div>' +
      '<div class="pe-field-edit" style="display:none">' +
      (f.isCity ? '<select class="form-select pe-input" data-key="' + f.key + '"><option value="">اختر المدينة</option>' + CITIES.map(function (c) { return '<option' + (c === val ? ' selected' : '') + '>' + c + '</option>'; }).join("") + '</select>'
        : f.multiline ? '<textarea class="form-input pe-input" rows="3" data-key="' + f.key + '">' + val + '</textarea>'
        : '<input type="text" class="form-input pe-input" data-key="' + f.key + '" value="' + val.replace(/"/g, '&quot;') + '">') +
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
    API.patch("/api/providers/me/profile/", payload).then(function () {
      profile[key] = val;
      var field = document.querySelector('.pe-field[data-key="' + key + '"]');
      field.querySelector(".pe-field-display").textContent = val || "—";
      field.querySelector(".pe-field-display").style.display = "";
      field.querySelector(".pe-field-edit").style.display = "none";
      field.querySelector(".pe-edit-btn").style.display = "";
    }).catch(function () {
      alert("فشل في الحفظ");
    }).finally(function () {
      btn.disabled = false; btn.textContent = "حفظ";
    });
  }

  function bindTabs() {
    document.getElementById("pe-tabs").addEventListener("click", function (e) {
      var tab = e.target.closest(".tab");
      if (!tab) return;
      var name = tab.dataset.tab;
      this.querySelectorAll(".tab").forEach(function (t) { t.classList.toggle("active", t === tab); });
      document.querySelectorAll(".tab-panel").forEach(function (p) { p.classList.toggle("active", p.dataset.panel === name); });
    });
  }

  document.addEventListener("DOMContentLoaded", init);
  return { init: init };
})();
