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
  var CITIES = [
    "أبها", "الأحساء", "الأفلاج", "الباحة", "البكيرية", "البدائع", "الجبيل", "الجموم",
    "الحريق", "الحوطة", "الخبر", "الخرج", "الخفجي", "الدرعية", "الدلم", "الدمام",
    "الدوادمي", "الرس", "الرياض", "الزلفي", "السليل", "الطائف", "الظهران", "العرضيات",
    "العلا", "القريات", "القصيم", "القطيف", "القنفذة", "القويعية", "الليث", "المجمعة",
    "المدينة المنورة", "المذنب", "المزاحمية", "النماص", "الوجه", "أملج", "بدر", "بريدة",
    "بلجرشي", "بيشة", "تبوك", "تربة", "تنومة", "ثادق", "جازان", "جدة", "حائل",
    "حفر الباطن", "حقل", "حوطة بني تميم", "خميس مشيط", "خيبر", "رابغ", "رفحاء", "رنية",
    "سراة عبيدة", "سكاكا", "شرورة", "شقراء", "صامطة", "صبيا", "ضباء", "ضرما", "طبرجل",
    "طريف", "ظلم", "عرعر", "عفيف", "عنيزة", "محايل عسير", "مكة المكرمة", "نجران", "ينبع"
  ];

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
    syncDeadlineBounds();
    setProviderTypeMode();
    bindEvents();
    updateCityClearVisibility();
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
    document.getElementById("sr-title-count").textContent = String((document.getElementById("sr-req-title").value || "").length);
    document.getElementById("sr-desc-count").textContent = String((document.getElementById("sr-desc").value || "").length);

    var citySel = document.getElementById("sr-city");
    if (citySel) {
      citySel.addEventListener("change", updateCityClearVisibility);
    }
    var clearCityBtn = document.getElementById("sr-city-clear");
    if (clearCityBtn) {
      clearCityBtn.addEventListener("click", function () {
        if (citySel) citySel.value = "";
        updateCityClearVisibility();
      });
    }

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

  function updateCityClearVisibility() {
    var clearBtn = document.getElementById("sr-city-clear");
    if (!clearBtn) return;
    var city = (document.getElementById("sr-city").value || "").trim();
    clearBtn.classList.toggle("hidden", city.length === 0);
  }

  function dateIso(d) {
    return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
  }

  function syncDeadlineBounds() {
    var deadlineInput = document.getElementById("sr-deadline");
    if (!deadlineInput) return;
    var now = new Date();
    var minIso = dateIso(now);
    var maxDate = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 365);
    var maxIso = dateIso(maxDate);
    deadlineInput.min = minIso;
    deadlineInput.max = maxIso;
    if (deadlineInput.value && (deadlineInput.value < minIso || deadlineInput.value > maxIso)) {
      deadlineInput.value = "";
    }
  }

  function setProviderTypeMode() {
    if (!providerId) return;
    var chipsRoot = document.getElementById("sr-type-chips");
    if (!chipsRoot) return;
    chipsRoot.querySelectorAll(".chip").forEach(function (chip) {
      var isNormal = chip.dataset.val === "normal";
      chip.classList.toggle("active", isNormal);
      chip.disabled = !isNormal;
      if (!isNormal) chip.classList.add("hidden");
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

    var title = document.getElementById("sr-req-title").value.trim();
    var desc = document.getElementById("sr-desc").value.trim();
    if (!title) { alert("يرجى إدخال عنوان الطلب"); return; }
    if (!desc) { alert("يرجى إدخال تفاصيل الطلب"); return; }
    if (title.length > 50) { alert("عنوان الطلب يجب ألا يتجاوز 50 حرفًا"); return; }
    if (desc.length > 500) { alert("تفاصيل الطلب يجب ألا تتجاوز 500 حرف"); return; }

    var effectiveRequestType = providerId ? "normal" : requestType;
    if (effectiveRequestType === "normal" && !providerId) {
      alert("الطلب العادي يتطلب تحديد مزود خدمة");
      return;
    }

    var city = document.getElementById("sr-city").value;

    var deadline = document.getElementById("sr-deadline").value;
    if (deadline) {
      var min = document.getElementById("sr-deadline").min;
      var max = document.getElementById("sr-deadline").max;
      if ((min && deadline < min) || (max && deadline > max)) {
        alert("آخر موعد لاستلام العروض يجب أن يكون خلال 365 يومًا من اليوم");
        return;
      }
    }

    var btn = document.getElementById("sr-submit");
    btn.disabled = true; btn.textContent = "جاري الإرسال...";

    var fd = new FormData();
    fd.append("title", title);
    fd.append("description", desc);
    fd.append("request_type", effectiveRequestType);
    fd.append("subcategory", subcat);
    if (city) fd.append("city", city);
    if (providerId) fd.append("provider", providerId);
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
