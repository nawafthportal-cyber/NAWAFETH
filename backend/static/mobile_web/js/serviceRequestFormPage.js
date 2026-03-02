"use strict";
var ServiceRequestFormPage = (function () {
  var API = window.NwApiClient;
  var categories = [];
  var requestType = "normal";
  var providerId = null;
  var serviceId = null;
  var allImages = [];
  var allVideos = [];
  var allFiles = [];

  /* Saudi cities */
  var CITIES = ["الرياض","جدة","مكة المكرمة","المدينة المنورة","الدمام","الخبر","الظهران","الطائف","تبوك","بريدة","عنيزة","حائل","أبها","خميس مشيط","نجران","جازان","ينبع","الباحة","الجبيل","حفر الباطن","القطيف","الأحساء","سكاكا","عرعر","بيشة","الخرج","الدوادمي","المجمعة","القويعية","وادي الدواسر","رفحاء","شقراء","الزلفي","الرس","المذنب","الليث","القنفذة","محايل عسير","صبيا","أحد رفيدة","النماص","ظهران الجنوب","بلجرشي","رجال ألمع","الحناكية","بدر","العلا","الطريف","حقل","ضباء","الوجه","أملج","تيماء"];

  function init() {
    var params = new URLSearchParams(location.search);
    providerId = params.get("provider_id");
    serviceId = params.get("service_id");
    if (providerId) {
      requestType = "normal";
      document.getElementById("sr-title").textContent = "طلب خدمة";
    }

    loadCategories();
    populateCities();
    bindEvents();
  }

  function loadCategories() {
    API.get("/api/providers/categories/").then(function (cats) {
      categories = cats || [];
      var sel = document.getElementById("sr-category");
      categories.forEach(function (c) {
        var o = document.createElement("option");
        o.value = c.id; o.textContent = c.name;
        sel.appendChild(o);
      });
    });
  }

  function populateCities() {
    var sel = document.getElementById("sr-city");
    CITIES.forEach(function (c) {
      var o = document.createElement("option");
      o.value = c; o.textContent = c;
      sel.appendChild(o);
    });
  }

  function bindEvents() {
    // Type chips
    document.getElementById("sr-type-chips").addEventListener("click", function (e) {
      var chip = e.target.closest(".chip");
      if (!chip || providerId) return;
      requestType = chip.dataset.val;
      this.querySelectorAll(".chip").forEach(function (c) { c.classList.toggle("active", c === chip); });
      // urgent hides city
      document.getElementById("sr-city-group").style.display = requestType === "urgent" ? "none" : "";
    });

    // Category → subcategory
    document.getElementById("sr-category").addEventListener("change", function () {
      var catId = parseInt(this.value);
      var cat = categories.find(function (c) { return c.id === catId; });
      var subSel = document.getElementById("sr-subcategory");
      subSel.innerHTML = '<option value="">اختر التصنيف</option>';
      if (cat && cat.subcategories) {
        cat.subcategories.forEach(function (s) {
          var o = document.createElement("option");
          o.value = s.id; o.textContent = s.name;
          subSel.appendChild(o);
        });
      }
    });

    // Char counts
    document.getElementById("sr-req-title").addEventListener("input", function () {
      document.getElementById("sr-title-count").textContent = this.value.length;
    });
    document.getElementById("sr-desc").addEventListener("input", function () {
      document.getElementById("sr-desc-count").textContent = this.value.length;
    });

    // File inputs
    document.getElementById("sr-images").addEventListener("change", function () {
      allImages = allImages.concat(Array.from(this.files)); renderAttachments();
    });
    document.getElementById("sr-videos").addEventListener("change", function () {
      allVideos = allVideos.concat(Array.from(this.files)); renderAttachments();
    });
    document.getElementById("sr-files").addEventListener("change", function () {
      allFiles = allFiles.concat(Array.from(this.files)); renderAttachments();
    });

    // Submit
    document.getElementById("sr-form").addEventListener("submit", function (e) {
      e.preventDefault(); submit();
    });
  }

  function renderAttachments() {
    var box = document.getElementById("sr-attachments");
    var html = "";
    allImages.forEach(function (f, i) {
      html += '<div class="attach-item"><img src="' + URL.createObjectURL(f) + '"><button type="button" data-type="img" data-idx="' + i + '" class="attach-remove">×</button></div>';
    });
    allVideos.forEach(function (f, i) {
      html += '<div class="attach-item file-item"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#663D90" stroke-width="2"><polygon points="23 7 16 12 23 17 23 7"/><rect x="1" y="5" width="15" height="14" rx="2"/></svg><span>' + f.name + '</span><button type="button" data-type="vid" data-idx="' + i + '" class="attach-remove">×</button></div>';
    });
    allFiles.forEach(function (f, i) {
      html += '<div class="attach-item file-item"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#663D90" stroke-width="2"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/></svg><span>' + f.name + '</span><button type="button" data-type="file" data-idx="' + i + '" class="attach-remove">×</button></div>';
    });
    box.innerHTML = html;
    box.querySelectorAll(".attach-remove").forEach(function (btn) {
      btn.addEventListener("click", function () {
        var t = this.dataset.type, idx = parseInt(this.dataset.idx);
        if (t === "img") allImages.splice(idx, 1);
        else if (t === "vid") allVideos.splice(idx, 1);
        else allFiles.splice(idx, 1);
        renderAttachments();
      });
    });
  }

  function submit() {
    var subcat = document.getElementById("sr-subcategory").value;
    if (!subcat) { alert("الرجاء اختيار التصنيف الفرعي"); return; }

    var city = document.getElementById("sr-city").value;
    if (requestType !== "urgent" && !city) { alert("الرجاء اختيار المدينة"); return; }

    var btn = document.getElementById("sr-submit");
    btn.disabled = true; btn.textContent = "جاري الإرسال...";

    var fd = new FormData();
    fd.append("title", document.getElementById("sr-req-title").value.trim());
    fd.append("description", document.getElementById("sr-desc").value.trim());
    fd.append("request_type", requestType);
    fd.append("subcategory", subcat);
    if (city) fd.append("city", city);
    if (providerId) fd.append("provider", providerId);
    var deadline = document.getElementById("sr-deadline").value;
    if (deadline) fd.append("quote_deadline", deadline);

    allImages.forEach(function (f) { fd.append("images", f); });
    allVideos.forEach(function (f) { fd.append("videos", f); });
    allFiles.forEach(function (f) { fd.append("files", f); });

    API.upload("/api/marketplace/requests/create/", fd)
      .then(function () {
        document.getElementById("sr-form").style.display = "none";
        document.getElementById("sr-success").style.display = "";
      })
      .catch(function (err) {
        alert(err.message || "فشل إرسال الطلب");
        btn.disabled = false; btn.textContent = "تقديم الطلب";
      });
  }

  document.addEventListener("DOMContentLoaded", init);
  return { init: init };
})();
