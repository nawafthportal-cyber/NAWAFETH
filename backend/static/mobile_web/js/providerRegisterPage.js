"use strict";
var ProviderRegisterPage = (function () {
  var RAW_API = window.ApiClient;
  var API = window.NwApiClient;
  var regionCatalog = [];
  var ALLOWED_PROVIDER_TYPES = ["individual", "company"];
  var currentStep = 1;
  var categories = [];
  var providerType = "individual";
  var isSubmitting = false;
  var isSuggestionSubmitting = false;
  var toastTimer = null;
  var STEP_NARRATIVES = {
    1: {
      badge: "الخطوة 1 من 3",
      title: "أساس ملفك الاحترافي",
      hint: "ابدأ باسم عرض واضح ومنطقة دقيقة حتى يظهر ملفك للعملاء بالصورة الصحيحة.",
      tip: "كلما كانت البيانات الأولى أوضح، أصبح ظهورك في المنصة أكثر اتساقًا وسهولة للمراجعة والاعتماد."
    },
    2: {
      badge: "الخطوة 2 من 3",
      title: "اختيار التصنيف المناسب",
      hint: "حدّد القسم والتصنيف الأقرب لخدمتك حتى تصل للعميل في السياق الصحيح.",
      tip: "إذا كانت خدمتك متخصصة جدًا، اختر الأقرب ثم استخدم اقتراح التصنيف للحفاظ على سلاسة التسجيل."
    },
    3: {
      badge: "الخطوة 3 من 3",
      title: "اكتمال ناعم للمعلومات",
      hint: "أضف وسائل التواصل والخبرة بصورة واضحة ومختصرة قبل إنشاء الحساب.",
      tip: "ليس المطلوب كثرة بيانات، بل معلومات عملية تمنح العميل انطباعًا مريحًا وتمنح ملفك مظهرًا مكتملًا."
    },
    success: {
      badge: "الملف جاهز",
      title: "تم إنشاء حسابك بنجاح",
      hint: "أصبح بإمكانك الآن تطوير ملفك وإضافة خدماتك من لوحة التحكم.",
      tip: "ابدأ بإكمال الملف التعريفي والخدمة الأولى حتى يظهر حسابك بصورة أقوى داخل المنصة."
    }
  };
  var TOAST_TONES = {
    success: {
      title: "تم بنجاح",
      icon: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg>',
      role: "status",
      live: "polite"
    },
    warning: {
      title: "تنبيه لطيف",
      icon: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 9v4"/><path d="M12 17h.01"/><path d="M10.29 3.86 1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/></svg>',
      role: "status",
      live: "polite"
    },
    error: {
      title: "تعذر الإكمال",
      icon: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"/><path d="M15 9 9 15"/><path d="m9 9 6 6"/></svg>',
      role: "alert",
      live: "assertive"
    },
    info: {
      title: "معلومة سريعة",
      icon: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"/><path d="M12 16v-4"/><path d="M12 8h.01"/></svg>',
      role: "status",
      live: "polite"
    }
  };

  function init() {
    loadRegionsAndCities();
    loadCategories();
    bindEvents();
    syncProviderTypeFromDom();
    updateStepNarrative(currentStep);
  }

  function normalizeProviderType(value) {
    return ALLOWED_PROVIDER_TYPES.indexOf(value) >= 0 ? value : "individual";
  }

  function syncProviderTypeFromDom() {
    var chipsRoot = document.getElementById("reg-type-chips");
    if (!chipsRoot) {
      providerType = "individual";
      return;
    }
    var activeChip = chipsRoot.querySelector(".chip.active");
    providerType = normalizeProviderType(activeChip ? activeChip.dataset.val : providerType);
  }

  function loadRegionsAndCities() {
    API.get("/api/providers/geo/regions-cities/").then(function (rows) {
      regionCatalog = normalizeRegionCatalog(rows);
      populateRegions();
      populateCitiesForRegion("");
    }).catch(function () {
      regionCatalog = [];
      populateRegions();
      populateCitiesForRegion("");
      showToast("تعذر تحميل المناطق والمدن حاليًا. حاول تحديث الصفحة.", "error");
    });
  }

  function normalizeRegionCatalog(rows) {
    if (!Array.isArray(rows)) return [];
    return rows.map(function (row) {
      var regionName = String((row && row.name_ar) || "").trim();
      if (!regionName) return null;
      var citiesRaw = Array.isArray(row.cities) ? row.cities : [];
      var cities = citiesRaw.map(function (cityRow) {
        var cityName = String((cityRow && cityRow.name_ar) || "").trim();
        return cityName || null;
      }).filter(Boolean);
      return { region: regionName, cities: cities };
    }).filter(Boolean);
  }

  function populateRegions() {
    var regionSel = document.getElementById("reg-region");
    if (!regionSel) return;
    regionSel.innerHTML = '<option value="">اختر المنطقة</option>';
    regionCatalog.forEach(function (entry) {
      var o = document.createElement("option");
      o.value = entry.region;
      o.textContent = entry.region;
      regionSel.appendChild(o);
    });
  }

  function populateCitiesForRegion(regionName) {
    var citySel = document.getElementById("reg-city");
    if (!citySel) return;
    citySel.innerHTML = '<option value="">اختر المدينة</option>';
    if (!regionName) return;

    var found = regionCatalog.find(function (entry) {
      return entry.region === regionName;
    });
    if (!found || !Array.isArray(found.cities)) return;
    found.cities.forEach(function (cityName) {
      var o = document.createElement("option");
      o.value = cityName;
      o.textContent = cityName;
      citySel.appendChild(o);
    });
  }

  function loadCategories() {
    API.get("/api/providers/categories/").then(function (cats) {
      categories = cats || [];
      var sel = document.getElementById("reg-category");
      categories.forEach(function (c) {
        var o = document.createElement("option");
        o.value = c.id;
        o.textContent = c.name;
        sel.appendChild(o);
      });
    }).catch(function () {
      showToast("تعذر تحميل التصنيفات حاليًا. حدّث الصفحة أو أعد المحاولة بعد قليل.", "error");
    });
  }

  function bindEvents() {
    var regionSel = document.getElementById("reg-region");
    if (regionSel) {
      regionSel.addEventListener("change", function () {
        var regionValue = String(regionSel.value || "").trim();
        populateCitiesForRegion(regionValue);
      });
    }

    var whatsappInput = document.getElementById("reg-whatsapp");
    if (whatsappInput) {
      whatsappInput.addEventListener("input", function () {
        var digits = String(whatsappInput.value || "").replace(/\D+/g, "").slice(0, 10);
        whatsappInput.value = digits;
      });
    }

    document.getElementById("reg-type-chips").addEventListener("click", function (e) {
      var chip = e.target.closest(".chip");
      if (!chip) return;
      var selectedType = normalizeProviderType(chip.dataset.val);
      if (selectedType !== chip.dataset.val) return;
      providerType = selectedType;
      this.querySelectorAll(".chip").forEach(function (c) { c.classList.toggle("active", c === chip); });
    });

    document.getElementById("reg-category").addEventListener("change", function () {
      var cat = categories.find(function (c) { return c.id === parseInt(document.getElementById("reg-category").value, 10); });
      var subSel = document.getElementById("reg-subcategory");
      subSel.innerHTML = '<option value="">اختر التصنيف</option>';
      if (cat && cat.subcategories) {
        cat.subcategories.forEach(function (s) {
          var o = document.createElement("option");
          o.value = s.id;
          o.textContent = s.name;
          subSel.appendChild(o);
        });
      }
    });

    document.getElementById("reg-next-1").addEventListener("click", function () { if (validateStep1()) goToStep(2); });
    document.getElementById("reg-back-2").addEventListener("click", function () { goToStep(1); });
    document.getElementById("reg-next-2").addEventListener("click", function () { if (validateStep2()) goToStep(3); });
    document.getElementById("reg-back-3").addEventListener("click", function () { goToStep(2); });
    document.getElementById("reg-submit").addEventListener("click", function () {
      if (validateStep3()) submit();
    });

    var suggestOpenBtn = document.getElementById("reg-suggest-open");
    var suggestCloseBtn = document.getElementById("reg-suggest-close");
    var suggestSubmitBtn = document.getElementById("reg-suggest-submit");
    var toastCloseBtn = document.getElementById("reg-toast-close");
    if (suggestOpenBtn) {
      suggestOpenBtn.addEventListener("click", function () {
        toggleSuggestionForm(!isSuggestionFormVisible());
      });
    }
    if (suggestCloseBtn) suggestCloseBtn.addEventListener("click", function () { toggleSuggestionForm(false); });
    if (suggestSubmitBtn) suggestSubmitBtn.addEventListener("click", function () { submitCategorySuggestion(); });
    if (toastCloseBtn) toastCloseBtn.addEventListener("click", hideToast);
  }

  function focusField(fieldId) {
    var field = document.getElementById(fieldId);
    if (!field || typeof field.focus !== "function") return;
    try {
      field.focus({ preventScroll: false });
    } catch (_) {
      field.focus();
    }
  }

  function updateStepNarrative(stepKey) {
    var narrative = STEP_NARRATIVES.hasOwnProperty(stepKey) ? STEP_NARRATIVES[stepKey] : STEP_NARRATIVES[1];
    var badge = document.getElementById("reg-step-badge");
    var title = document.getElementById("reg-step-title");
    var hint = document.getElementById("reg-step-hint");
    var tip = document.getElementById("reg-step-tip");
    if (badge) badge.textContent = narrative.badge;
    if (title) title.textContent = narrative.title;
    if (hint) hint.textContent = narrative.hint;
    if (tip) tip.textContent = narrative.tip;
  }

  function isSuggestionFormVisible() {
    var form = document.getElementById("reg-suggest-form");
    return !!(form && !form.classList.contains("hidden"));
  }

  function selectedOptionText(selectId) {
    var select = document.getElementById(selectId);
    if (!select || select.selectedIndex < 0) return "";
    return String(select.options[select.selectedIndex].textContent || "").trim();
  }

  function toggleSuggestionForm(show) {
    var form = document.getElementById("reg-suggest-form");
    if (!form) return;
    form.classList.toggle("hidden", !show);
    if (!show) return;

    var mainInput = document.getElementById("reg-suggest-main");
    var subInput = document.getElementById("reg-suggest-sub");
    var selectedMain = selectedOptionText("reg-category");
    var selectedSub = selectedOptionText("reg-subcategory");
    if (mainInput && !mainInput.value.trim() && selectedMain && selectedMain !== "اختر القسم") {
      mainInput.value = selectedMain;
    }
    if (subInput && !subInput.value.trim() && selectedSub && selectedSub !== "اختر التصنيف") {
      subInput.value = selectedSub;
    }
    if (mainInput) mainInput.focus();
  }

  function buildCategorySuggestionDescription(mainName, subName, note) {
    var lines = [
      "اقتراح تصنيف جديد من صفحة تسجيل مزود الخدمة",
      "التصنيف الرئيسي المقترح: " + mainName,
      "التصنيف الفرعي المقترح: " + subName
    ];

    var selectedMain = selectedOptionText("reg-category");
    var selectedSub = selectedOptionText("reg-subcategory");
    if (selectedMain && selectedMain !== "اختر القسم") {
      lines.push("القسم المختار حاليًا: " + selectedMain);
    }
    if (selectedSub && selectedSub !== "اختر التصنيف") {
      lines.push("التصنيف المختار حاليًا: " + selectedSub);
    }
    if (note) {
      lines.push("ملاحظات: " + note);
    }

    return lines.join(" | ").slice(0, 300);
  }

  function requestWithHardTimeout(path, options, timeoutMs) {
    var ms = parseInt(timeoutMs, 10);
    if (!ms || ms < 1000) ms = 15000;

    return Promise.race([
      Promise.resolve().then(function () {
        if (!RAW_API || typeof RAW_API.request !== "function") {
          throw new Error("تعذر تهيئة الاتصال بالخادم. حدّث الصفحة ثم أعد المحاولة.");
        }
        return RAW_API.request(path, options || {});
      }),
      new Promise(function (resolve) {
        window.setTimeout(function () {
          resolve({
            ok: false,
            status: 0,
            data: { detail: "انتهت مهلة الاتصال. حاول مرة أخرى." },
            error: "hard-timeout"
          });
        }, ms);
      })
    ]);
  }

  async function submitCategorySuggestion() {
    if (isSuggestionSubmitting) return;

    if (window.Auth && typeof window.Auth.isLoggedIn === "function" && !window.Auth.isLoggedIn()) {
      showToast("يجب تسجيل الدخول أولًا لإرسال المقترح.", "warning");
      return;
    }

    var mainInput = document.getElementById("reg-suggest-main");
    var subInput = document.getElementById("reg-suggest-sub");
    var noteInput = document.getElementById("reg-suggest-note");
    if (!mainInput || !subInput) return;

    var mainName = mainInput.value.trim();
    var subName = subInput.value.trim();
    var note = noteInput ? noteInput.value.trim() : "";

    if (!mainName || !subName) {
      showToast("أدخل التصنيف الرئيسي والفرعي المقترحين أولًا.", "warning");
      return;
    }

    isSuggestionSubmitting = true;
    setSuggestionSubmitState(true);

    try {
      var res = await requestWithHardTimeout("/api/support/tickets/create/", {
        method: "POST",
        timeout: 12000,
        body: {
          ticket_type: "suggest",
          description: buildCategorySuggestionDescription(mainName, subName, note)
        }
      }, 16000);

      if (res && (res.status === 401 || res.status === 403)) {
        throw new Error("انتهت الجلسة. سجّل الدخول ثم أعد الإرسال.");
      }
      if (!res || !res.ok || !res.data) {
        throw new Error(apiErrorMessage(res ? res.data : null, "تعذر إرسال الاقتراح"));
      }

      if (noteInput) noteInput.value = "";
      mainInput.value = "";
      subInput.value = "";
      toggleSuggestionForm(false);
      showToast("تم إرسال طلبك للفريق المختص وسيتم إبلاغك. يمكنك متابعة الطلب من صفحة تواصل مع نوافذ (بلاغاتي).", "success");
    } catch (err) {
      showToast((err && err.message) ? err.message : "تعذر إرسال الاقتراح", "error");
    } finally {
      isSuggestionSubmitting = false;
      setSuggestionSubmitState(false);
    }
  }

  function setSuggestionSubmitState(isBusy) {
    var submitBtn = document.getElementById("reg-suggest-submit");
    var submitText = document.getElementById("reg-suggest-submit-text");
    var submitSpinner = document.getElementById("reg-suggest-submit-spinner");
    if (!submitBtn) return;

    submitBtn.disabled = !!isBusy;
    submitBtn.setAttribute("aria-busy", isBusy ? "true" : "false");

    if (submitText) {
      submitText.textContent = isBusy ? "جاري الإرسال..." : "إرسال الاقتراح";
    } else {
      submitBtn.textContent = isBusy ? "جاري الإرسال..." : "إرسال الاقتراح";
    }

    if (submitSpinner) {
      submitSpinner.classList.toggle("hidden", !isBusy);
    }
  }

  function goToStep(n) {
    currentStep = n;
    var stepValue = String(n);
    var numericStep = parseInt(stepValue, 10);
    var hasNumericStep = !isNaN(numericStep);
    var isSuccessStep = stepValue === "success";

    var shell = document.querySelector("main.page-shell");
    if (shell) {
      shell.setAttribute("data-current-step", stepValue);
    }

    document.querySelectorAll(".wizard-panel").forEach(function (p) { p.classList.toggle("active", p.dataset.panel == n); });
    document.querySelectorAll(".wizard-step").forEach(function (s) {
      var sn = parseInt(s.dataset.step, 10);
      s.classList.toggle("active", hasNumericStep && sn === numericStep);
      s.classList.toggle("done", isSuccessStep || (hasNumericStep && sn < numericStep));
    });
    updateStepNarrative(isSuccessStep ? "success" : numericStep);
  }

  function validateStep1() {
    if (!document.getElementById("reg-display-name").value.trim()) {
      focusField("reg-display-name");
      showToast("أدخل اسم العرض أولًا.", "warning");
      return false;
    }
    if (!document.getElementById("reg-region").value) {
      focusField("reg-region");
      showToast("اختر المنطقة أولًا.", "warning");
      return false;
    }
    if (!document.getElementById("reg-city").value) {
      focusField("reg-city");
      showToast("اختر المدينة أولًا.", "warning");
      return false;
    }
    return true;
  }

  function validateStep2() {
    if (!document.getElementById("reg-subcategory").value) {
      focusField("reg-subcategory");
      showToast("اختر التصنيف الفرعي أولًا.", "warning");
      return false;
    }
    return true;
  }

  function validateStep3() {
    var whatsappInput = document.getElementById("reg-whatsapp");
    if (!whatsappInput) return true;

    var whatsapp = String(whatsappInput.value || "").trim();
    if (!whatsapp) return true;

    if (!/^05\d{8}$/.test(whatsapp)) {
      focusField("reg-whatsapp");
      showToast("رقم الواتساب يجب أن يبدأ بـ 05 ويتكون من 10 أرقام.", "warning");
      return false;
    }
    return true;
  }

  function hideToast() {
    var toast = document.getElementById("reg-toast");
    if (!toast) return;
    toast.classList.remove("show");
    if (toastTimer) {
      window.clearTimeout(toastTimer);
      toastTimer = null;
    }
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

  function showToast(message, type) {
    var toast = document.getElementById("reg-toast");
    var toastTitle = document.getElementById("reg-toast-title");
    var toastMessage = document.getElementById("reg-toast-message");
    var toastIcon = document.getElementById("reg-toast-icon");
    var toneKey = TOAST_TONES[type] ? type : "info";
    var tone = TOAST_TONES[toneKey];
    if (!toast) {
      alert(message || "");
      return;
    }
    if (toastTitle) toastTitle.textContent = tone.title;
    if (toastMessage) {
      toastMessage.textContent = message || "";
    } else {
      toast.textContent = message || "";
    }
    if (toastIcon) toastIcon.innerHTML = tone.icon;
    toast.setAttribute("role", tone.role);
    toast.setAttribute("aria-live", tone.live);
    toast.classList.remove("show", "success", "error", "warning", "info");
    toast.classList.add(toneKey);
    requestAnimationFrame(function () {
      toast.classList.add("show");
    });
    if (toastTimer) window.clearTimeout(toastTimer);
    toastTimer = window.setTimeout(function () {
      hideToast();
    }, 4200);
  }

  function setSubmitState(isBusy, label) {
    var btn = document.getElementById("reg-submit");
    if (!btn) return;
    btn.disabled = !!isBusy;
    btn.textContent = label || (isBusy ? "جاري التسجيل..." : "إنشاء الحساب");
  }

  function isSuccessVisible() {
    var panel = document.getElementById("reg-success");
    return !!(panel && panel.classList.contains("active"));
  }

  function showSuccessPanel() {
    sessionStorage.setItem("nw_account_mode", "provider");
    if (window.Auth && typeof window.Auth.saveRoleState === "function") {
      window.Auth.saveRoleState("provider");
    } else {
      sessionStorage.setItem("nw_role_state", "provider");
      try {
        if (window.localStorage) window.localStorage.setItem("nw_role_state", "provider");
      } catch (_) {}
    }
    goToStep("success");
    document.getElementById("reg-success").classList.add("active");
    try {
      window.scrollTo({ top: 0, behavior: "smooth" });
    } catch (_) {
      window.scrollTo(0, 0);
    }
  }

  function saveInitialServiceIfNeeded(subcategoryId, serviceTitle, serviceDescription) {
    if (!serviceTitle || !subcategoryId) {
      return Promise.resolve(null);
    }
    return requestWithHardTimeout("/api/providers/me/services/", {
      method: "POST",
      timeout: 10000,
      body: {
        subcategory_id: subcategoryId,
        title: serviceTitle,
        description: serviceDescription
      }
    }, 12000).then(function (serviceRes) {
      if (!serviceRes || !serviceRes.ok || !serviceRes.data) {
        throw new Error(apiErrorMessage(serviceRes ? serviceRes.data : null, "تعذر حفظ الخدمة الأولى"));
      }
      showToast("تم حفظ الخدمة الأولى ضمن ملفك كمزود خدمة.", "success");
      return serviceRes.data;
    }).catch(function (err) {
      showToast(
        "تم إنشاء ملفك كمزود خدمة، لكن تعذر حفظ الخدمة الأولى. يمكنك إضافتها لاحقًا من لوحة المزوّد."
        + ((err && err.message) ? ("\n" + err.message) : ""),
        "warning"
      );
      return null;
    });
  }

  async function submit() {
    if (isSubmitting) return;

    var subcategoryId = parseInt(document.getElementById("reg-subcategory").value, 10);
    var serviceTitle = document.getElementById("reg-service-title").value.trim();
    var serviceDescription = document.getElementById("reg-service-desc").value.trim();

    isSubmitting = true;
    setSubmitState(true, "جاري التسجيل...");

    var providerBody = {
      provider_type: normalizeProviderType(providerType),
      display_name: document.getElementById("reg-display-name").value.trim(),
      bio: document.getElementById("reg-bio").value.trim(),
      region: document.getElementById("reg-region").value,
      city: document.getElementById("reg-city").value,
      subcategory_ids: subcategoryId ? [subcategoryId] : [],
      whatsapp: document.getElementById("reg-whatsapp").value.trim(),
      website: document.getElementById("reg-website").value.trim(),
      years_experience: parseInt(document.getElementById("reg-experience").value, 10) || 0
    };

    try {
      var res = await requestWithHardTimeout("/api/providers/register/", {
        method: "POST",
        timeout: 15000,
        body: providerBody
      }, 18000);

      if (res && (res.status === 401 || res.status === 403)) {
        throw new Error("انتهت الجلسة. سجّل الدخول مجددًا ثم أعد التسجيل.");
      }
      if (!res || !res.ok || !res.data) {
        throw new Error(apiErrorMessage(res ? res.data : null, "فشل التسجيل"));
      }
      showSuccessPanel();
      showToast("تم إنشاء حساب مزود الخدمة بنجاح.", "success");
      await saveInitialServiceIfNeeded(subcategoryId, serviceTitle, serviceDescription);
    } catch (err) {
      showToast((err && err.message) ? err.message : "فشل التسجيل", "error");
    } finally {
      isSubmitting = false;
      if (!isSuccessVisible()) {
        setSubmitState(false, "إنشاء الحساب");
      }
    }
  }

  document.addEventListener("DOMContentLoaded", init);
  return { init: init };
})();
