"use strict";
var ProviderRegisterPage = (function () {
  var API = window.NwApiClient;
  var CITIES = ["الرياض","جدة","مكة المكرمة","المدينة المنورة","الدمام","الخبر","الظهران","الطائف","تبوك","بريدة","عنيزة","حائل","أبها","خميس مشيط","نجران","جازان","ينبع","الباحة","الجبيل","حفر الباطن","القطيف","الأحساء","سكاكا","عرعر","بيشة","الخرج","الدوادمي","المجمعة","القويعية","وادي الدواسر"];
  var currentStep = 1;
  var categories = [];
  var providerType = "individual";

  function init() {
    populateCities();
    loadCategories();
    bindEvents();
  }

  function populateCities() {
    var sel = document.getElementById("reg-city");
    CITIES.forEach(function (c) { var o = document.createElement("option"); o.value = c; o.textContent = c; sel.appendChild(o); });
  }

  function loadCategories() {
    API.get("/api/providers/categories/").then(function (cats) {
      categories = cats || [];
      var sel = document.getElementById("reg-category");
      categories.forEach(function (c) { var o = document.createElement("option"); o.value = c.id; o.textContent = c.name; sel.appendChild(o); });
    });
  }

  function bindEvents() {
    // Type chips
    document.getElementById("reg-type-chips").addEventListener("click", function (e) {
      var chip = e.target.closest(".chip");
      if (!chip) return;
      providerType = chip.dataset.val;
      this.querySelectorAll(".chip").forEach(function (c) { c.classList.toggle("active", c === chip); });
    });

    // Category → subcategory
    document.getElementById("reg-category").addEventListener("change", function () {
      var cat = categories.find(function (c) { return c.id === parseInt(document.getElementById("reg-category").value); });
      var subSel = document.getElementById("reg-subcategory");
      subSel.innerHTML = '<option value="">اختر التصنيف</option>';
      if (cat && cat.subcategories) {
        cat.subcategories.forEach(function (s) { var o = document.createElement("option"); o.value = s.id; o.textContent = s.name; subSel.appendChild(o); });
      }
    });

    // Navigation
    document.getElementById("reg-next-1").addEventListener("click", function () { if (validateStep1()) goToStep(2); });
    document.getElementById("reg-back-2").addEventListener("click", function () { goToStep(1); });
    document.getElementById("reg-next-2").addEventListener("click", function () { if (validateStep2()) goToStep(3); });
    document.getElementById("reg-back-3").addEventListener("click", function () { goToStep(2); });
    document.getElementById("reg-submit").addEventListener("click", function () { submit(); });
  }

  function goToStep(n) {
    currentStep = n;
    document.querySelectorAll(".wizard-panel").forEach(function (p) { p.classList.toggle("active", p.dataset.panel == n); });
    document.querySelectorAll(".wizard-step").forEach(function (s) {
      var sn = parseInt(s.dataset.step);
      s.classList.toggle("active", sn === n);
      s.classList.toggle("done", sn < n);
    });
  }

  function validateStep1() {
    if (!document.getElementById("reg-display-name").value.trim()) { alert("أدخل اسم العرض"); return false; }
    if (!document.getElementById("reg-city").value) { alert("اختر المدينة"); return false; }
    return true;
  }

  function validateStep2() {
    if (!document.getElementById("reg-subcategory").value) { alert("اختر التصنيف الفرعي"); return false; }
    return true;
  }

  function submit() {
    var btn = document.getElementById("reg-submit");
    btn.disabled = true; btn.textContent = "جاري التسجيل...";

    var body = {
      provider_type: providerType,
      display_name: document.getElementById("reg-display-name").value.trim(),
      bio: document.getElementById("reg-bio").value.trim(),
      city: document.getElementById("reg-city").value,
      subcategory: parseInt(document.getElementById("reg-subcategory").value),
      service_title: document.getElementById("reg-service-title").value.trim(),
      service_description: document.getElementById("reg-service-desc").value.trim(),
      whatsapp: document.getElementById("reg-whatsapp").value.trim(),
      website: document.getElementById("reg-website").value.trim(),
      years_experience: parseInt(document.getElementById("reg-experience").value) || 0
    };

    API.post("/api/providers/register/", body).then(function (res) {
      // Set provider mode
      sessionStorage.setItem("nw_account_mode", "provider");
      sessionStorage.setItem("nw_role_state", "provider");
      goToStep("success");
      document.getElementById("reg-success").classList.add("active");
    }).catch(function (err) {
      alert(err.message || "فشل التسجيل");
      btn.disabled = false; btn.textContent = "إنشاء الحساب";
    });
  }

  document.addEventListener("DOMContentLoaded", init);
  return { init: init };
})();
