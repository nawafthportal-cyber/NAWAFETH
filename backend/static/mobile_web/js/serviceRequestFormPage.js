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
  var isAuthenticated = false;

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
    isAuthenticated = !!(window.Auth && typeof window.Auth.isLoggedIn === "function" && window.Auth.isLoggedIn());
    _setAuthState(isAuthenticated);
    _setLoginHref();
    if (!isAuthenticated) return;

    var params = new URLSearchParams(location.search);
    providerId = params.get("provider_id");
    serviceId = params.get("service_id");
    if (providerId) {
      requestType = "normal";
      document.getElementById("sr-title").textContent = "طلب مباشر إلى مزود الخدمة";
    }

    loadCategories();
    populateCities();
    syncDeadlineBounds();
    setProviderTypeMode();
    bindEvents();
    updateCityClearVisibility();
    updateRequestTypePresentation();
  }

  function _setAuthState(loggedIn) {
    var gate = document.getElementById("auth-gate");
    var content = document.getElementById("form-content");
    if (gate) gate.classList.toggle("hidden", loggedIn);
    if (content) content.classList.toggle("hidden", !loggedIn);
  }

  function _setLoginHref() {
    var loginLink = document.getElementById("sr-login-link");
    if (!loginLink) return;
    var next = window.location.pathname + window.location.search;
    loginLink.href = "/login/?next=" + encodeURIComponent(next);
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
      updateRequestTypePresentation();
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
    updateRequestTypePresentation();
  }

  function updateRequestTypePresentation() {
    var mode = providerId ? "provider_direct" : requestType;
    var variants = {
      provider_direct: {
        label: "إرسال مباشر",
        title: "طلب مباشر إلى مزود محدد",
        text: "سيصل الطلب إلى المزود الذي اخترته فقط، ما يجعل هذا المسار مناسباً عندما تكون قد حددت مقدم الخدمة مسبقاً.",
        helper: "اكتب تفاصيل الطلب كما تريد أن تصل مباشرة إلى المزود، ثم أرفق أي ملفات توضيحية لازمة.",
        submitText: "إرسال الطلب",
        successTitle: "تم إرسال الطلب إلى المزود",
        successMessage: "تم حفظ طلبك وإرساله مباشرة إلى مزود الخدمة. تابع الردود وتحديثات التنفيذ من صفحة الطلبات.",
        showDeadline: false,
        showProviderNote: true,
      },
      normal: {
        label: "طلب مباشر",
        title: "اختر مزوداً ثم أرسل الطلب مباشرة",
        text: "هذا المسار المباشر يحتاج إلى مزود خدمة محدد. إذا لم تختر مزوداً بعد، استخدم البحث أو ملف المزود أولاً.",
        helper: "الطلب المباشر مناسب عندما تكون قد حددت الجهة المنفذة وتريد بدء التواصل التنفيذي مباشرة.",
        submitText: "إرسال الطلب",
        successTitle: "تم حفظ الطلب",
        successMessage: "تم حفظ طلبك بنجاح. ستتمكن من متابعة حالته من صفحة الطلبات.",
        showDeadline: false,
        showProviderNote: false,
      },
      competitive: {
        label: "طلب تنافسي",
        title: "استقبال عروض أسعار متعددة",
        text: "سيتمكن المزوّدون المطابقون من إرسال عروضهم خلال الفترة التي تحددها، ثم تختار الأنسب لاحقاً.",
        helper: "في الطلب التنافسي، حدّد وصفاً واضحاً وموعداً نهائياً مناسباً لإغلاق استقبال العروض.",
        submitText: "إرسال الطلب التنافسي",
        successTitle: "تم إرسال طلب عروض الأسعار",
        successMessage: "تم فتح الطلب للمزوّدين المؤهلين. ستظهر لك العروض الواردة في صفحة الطلبات فور وصولها.",
        showDeadline: true,
        showProviderNote: false,
      },
      urgent: {
        label: "طلب عاجل",
        title: "مسار سريع للحالات العاجلة",
        text: "سيُرسل الطلب إلى المزوّدين المؤهلين بحسب التخصص والمدينة، مع أولوية أعلى للمعالجة السريعة.",
        helper: "اكتب وصفاً مباشراً ومختصراً للحالة العاجلة حتى يصل المطلوب بوضوح منذ اللحظة الأولى.",
        submitText: "إرسال الطلب العاجل",
        successTitle: "تم إرسال الطلب العاجل",
        successMessage: "تم توجيه الطلب العاجل وفق المسار المتاح. تابع حالته من صفحة الطلبات وتحقق من الردود أولاً بأول.",
        showDeadline: false,
        showProviderNote: false,
      },
    };

    var variant = variants[mode] || variants.normal;
    setText("sr-request-kind-label", variant.label);
    setText("sr-request-kind-title", variant.title);
    setText("sr-request-kind-text", variant.text);
    setText("sr-submit-helper", variant.helper);
    setText("sr-submit-text", variant.submitText);
    setText("sr-success-title", variant.successTitle);
    setText("sr-success-message", variant.successMessage);

    var providerNote = document.getElementById("sr-provider-note");
    if (providerNote) providerNote.classList.toggle("hidden", !variant.showProviderNote);

    var deadlineGroup = document.getElementById("sr-deadline-group");
    if (deadlineGroup) {
      deadlineGroup.classList.toggle("hidden", !variant.showDeadline);
      if (!variant.showDeadline) {
        document.getElementById("sr-deadline").value = "";
      }
    }
  }

  function setText(id, value) {
    var el = document.getElementById(id);
    if (el) el.textContent = value;
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
    var btnText = document.getElementById("sr-submit-text");
    btn.disabled = true;
    if (btnText) btnText.textContent = "جاري الإرسال...";

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
        document.getElementById("sr-form").classList.add("hidden");
        document.getElementById("sr-success").classList.remove("hidden");
      })
      .catch(function (err) {
        alert(err.message || "فشل إرسال الطلب");
        btn.disabled = false;
        updateRequestTypePresentation();
      });
  }

  document.addEventListener("DOMContentLoaded", init);
  return { init: init };
})();
