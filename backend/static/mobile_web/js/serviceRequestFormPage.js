/* ═══════════════════════════════════════════════════════
   serviceRequestFormPage.js — Grand Rebuild 2026-04-18
   ═══════════════════════════════════════════════════════ */
(function () {
  "use strict";

  /* ── Constants ── */
  var API = {
    CATEGORIES:    "/api/providers/categories/",
    REGIONS:       "/api/providers/geo/regions-cities/",
    CREATE:        "/api/marketplace/requests/create/",
    PROVIDERS:     "/api/providers/list/",
  };

  /* ── State ── */
  var categories       = [];
  var regionCatalog    = [];
  var requestType      = "competitive";
  var dispatchMode     = "all";
  var providerId       = null;
  var serviceId        = null;
  var fixedTargetCtx   = null;
  var nearestProvider  = null;
  var requestLat       = null;
  var requestLng       = null;
  var leafletMap       = null;
  var leafletMarker    = null;
  var providerMarkers  = [];
  var nearbyProviders  = [];
  var imageFiles       = [];
  var videoFiles       = [];
  var docFiles         = [];
  var audioBlob        = null;
  var mediaRecorder    = null;
  var audioChunks      = [];
  var isRecording      = false;
  var isSubmitting     = false;
  var submitOverlay    = null;
  var toastTimer       = null;
  var returnTimer      = null;
  var returnTargetUrl  = "/orders/";
  var holdSuccessState = false;

  function el(id) { return document.getElementById(id); }
  var dom = {};

  /* ═══════════════════════════════════════
     init()
     ═══════════════════════════════════════ */
  function init() {
    cacheDom();

    var serverAuth = window.NAWAFETH_SERVER_AUTH || null;
    var loggedIn = !!(
      (window.Auth && typeof Auth.isLoggedIn === "function" && Auth.isLoggedIn())
      || (serverAuth && serverAuth.isAuthenticated)
    );
    if (loggedIn && window.Auth && typeof window.Auth.ensureServiceRequestAccess === "function" && !window.Auth.ensureServiceRequestAccess({
      gateId: "auth-gate",
      contentId: "form-content",
      target: window.location.pathname + window.location.search,
      title: "إنشاء الطلبات متاح في وضع العميل فقط",
      description: "أنت تستخدم المنصة الآن بوضع مقدم الخدمة، لذلك لا يمكن إرسال طلب مباشر أو تنافسي أو عاجل من هذا الوضع.",
      note: "بدّل نوع الحساب إلى عميل الآن، ثم أكمل الطلب من نفس الصفحة مباشرة.",
      switchLabel: "التبديل إلى عميل",
      profileLabel: "الذهاب إلى نافذتي",
    })) {
      return;
    }
    if (loggedIn) {
      dom.authGate.classList.add("hidden");
      dom.formContent.classList.remove("hidden");
    } else {
      dom.authGate.classList.remove("hidden");
      dom.formContent.classList.add("hidden");
      var next = encodeURIComponent(window.location.href);
      dom.loginLink.href = "/login/?next=" + next;
      return;
    }

    submitOverlay = (window.UI && UI.createSubmitOverlay)
      ? UI.createSubmitOverlay({ title: "\u062c\u0627\u0631\u064d \u0625\u0631\u0633\u0627\u0644 \u0627\u0644\u0637\u0644\u0628..." })
      : null;
    returnTargetUrl = resolveReturnTarget();

    loadDirectTargetContext();
    loadCategories();
    loadRegionCatalog();
    bindEvents();
    syncTypeUI();
    renumberSteps();
  }

  /* ── Cache DOM refs ── */
  function cacheDom() {
    dom.container      = document.querySelector(".sr-container");
    dom.authGate       = el("auth-gate");
    dom.loginLink      = el("sr-login-link");
    dom.formContent    = el("form-content");
    dom.form           = el("sr-form");
    dom.title          = el("sr-title");
    dom.subtitle       = el("sr-subtitle");
    dom.typeBadge      = el("sr-type-badge");
    dom.typeBadgeText  = el("sr-type-badge-text");
    dom.heroPill1      = el("sr-pill-1");
    dom.heroPill2      = el("sr-pill-2");
    dom.heroPill3      = el("sr-pill-3");
    dom.typeNoteTitle  = el("sr-type-note-title");
    dom.typeNoteBody   = el("sr-type-note-body");

    dom.typeSection    = el("sr-type-section");
    dom.typeChips      = el("sr-type-chips");

    dom.scopeSection   = el("sr-scope-section");
    dom.scopeFields    = el("sr-scope-fields");
    dom.fixedTarget    = el("sr-fixed-target");
    dom.category       = el("sr-category");
    dom.subcategory    = el("sr-subcategory");

    dom.scopeTitle     = el("sr-scope-title");
    dom.scopeText      = el("sr-scope-text");
    dom.fixedProvName  = el("sr-fixed-provider-name");
    dom.fixedService   = el("sr-fixed-service");
    dom.fixedServiceRow= el("sr-fixed-service-row");
    dom.fixedCategory  = el("sr-fixed-category");
    dom.fixedSubcat    = el("sr-fixed-subcategory");
    dom.fixedCity      = el("sr-fixed-city");

    dom.dispatchSection = el("sr-dispatch-section");
    dom.dispatchWrap   = el("sr-dispatch-mode-wrap");
    dom.dispatchChips  = el("sr-dispatch-chips");
    dom.cityGroup      = el("sr-city-group");
    dom.region         = el("sr-region");
    dom.city           = el("sr-city");
    dom.cityClear      = el("sr-city-clear");

    dom.selectedProv   = el("sr-selected-provider");
    dom.spAvatar       = el("sr-sp-avatar");
    dom.spName         = el("sr-sp-name");
    dom.spMeta         = el("sr-sp-meta");
    dom.spChange       = el("sr-sp-change");
    dom.spRemove       = el("sr-sp-remove");

    dom.reqTitle       = el("sr-req-title");
    dom.desc           = el("sr-desc");
    dom.deadline       = el("sr-deadline");
    dom.deadlineGroup  = el("sr-deadline-group");
    dom.titleCount     = el("sr-title-count");
    dom.titleCountWrap = el("sr-title-count-wrap");
    dom.descCount      = el("sr-desc-count");
    dom.descCountWrap  = el("sr-desc-count-wrap");

    dom.imagesInput    = el("sr-images");
    dom.videosInput    = el("sr-videos");
    dom.filesInput     = el("sr-files");
    dom.audioBtn       = el("sr-audio-btn");
    dom.audioPreview   = el("sr-audio-preview");
    dom.audioPlayer    = el("sr-audio-player");
    dom.audioRemove    = el("sr-audio-remove");
    dom.attachments    = el("sr-attachments");

    dom.submitBtn      = el("sr-submit");
    dom.submitText     = el("sr-submit-text");
    dom.submitHelper   = el("sr-submit-helper");

    dom.mapModal       = el("sr-map-modal");
    dom.mapBackdrop    = el("sr-map-modal-backdrop");
    dom.mapClose       = el("sr-map-modal-close");
    dom.modalStatus    = el("sr-modal-status");
    dom.modalStatusText= el("sr-modal-status-text");
    dom.modalMap       = el("sr-modal-map");
    dom.modalList      = el("sr-modal-list");
    dom.modalEmpty     = el("sr-modal-empty");

    dom.success        = el("sr-success");
    dom.successTitle   = el("sr-success-title");
    dom.successMsg     = el("sr-success-message");

    dom.toast          = el("sr-toast");
    dom.toastIcon      = el("sr-toast-icon");
    dom.toastTitle     = el("sr-toast-title");
    dom.toastMsg       = el("sr-toast-message");
    dom.toastClose     = el("sr-toast-close");

    dom.catError       = el("sr-category-error");
    dom.subError       = el("sr-subcategory-error");
    dom.cityError      = el("sr-city-error");
    dom.titleError     = el("sr-req-title-error");
    dom.descError      = el("sr-desc-error");
    dom.deadlineError  = el("sr-deadline-error");
  }

  /* ═══════════════════════════════════════
     Load Data
     ═══════════════════════════════════════ */
  async function loadCategories() {
    try {
      var res = await ApiClient.get(API.CATEGORIES);
      if (res.ok && Array.isArray(res.data)) {
        categories = res.data;
        populateCategorySelect();
      }
    } catch (e) {
      console.warn("[SR] loadCategories error:", e);
    }
  }

  function populateCategorySelect() {
    dom.category.innerHTML = '<option value="">\u0627\u062e\u062a\u0631 \u0627\u0644\u0642\u0633\u0645</option>';
    categories.forEach(function (cat) {
      var o = document.createElement("option");
      o.value = cat.id;
      o.textContent = cat.name;
      dom.category.appendChild(o);
    });
    if (fixedTargetCtx && fixedTargetCtx.categoryId) {
      dom.category.value = fixedTargetCtx.categoryId;
      onCategoryChange();
      if (fixedTargetCtx.subcategoryId) {
        dom.subcategory.value = fixedTargetCtx.subcategoryId;
      }
    }
  }

  function onCategoryChange() {
    var catId = parseInt(dom.category.value, 10);
    var cat = categories.find(function (c) { return c.id === catId; });
    var subs = cat ? (cat.subcategories || []) : [];
    dom.subcategory.innerHTML = '<option value="">\u0627\u062e\u062a\u0631 \u0627\u0644\u062a\u0635\u0646\u064a\u0641</option>';
    subs.forEach(function (s) {
      var o = document.createElement("option");
      o.value = s.id;
      o.textContent = s.name;
      dom.subcategory.appendChild(o);
    });
  }

  async function loadRegionCatalog() {
    try {
      var res = await ApiClient.get(API.REGIONS);
      if (res.ok && Array.isArray(res.data)) {
        regionCatalog = UI.normalizeRegionCatalog(res.data);
      } else {
        regionCatalog = UI.getRegionCatalogFallback();
      }
    } catch (e) {
      regionCatalog = UI.getRegionCatalogFallback();
    }
    UI.populateRegionOptions(dom.region, regionCatalog);
  }

  /* ═══════════════════════════════════════
     Direct Target Context (from provider page)
     ═══════════════════════════════════════ */
  function loadDirectTargetContext() {
    var params = new URLSearchParams(window.location.search);
    var pid = params.get("provider_id") || params.get("provider");
    var sid = params.get("service_id") || params.get("service");
    if (!pid) return;

    providerId = parseInt(pid, 10) || null;
    serviceId  = sid ? parseInt(sid, 10) : null;

    var rt = params.get("type");
    if (rt === "urgent" || rt === "competitive" || rt === "normal") {
      requestType = rt;
    } else {
      requestType = "normal";
    }

    fetchProviderAndApply();
  }

  function normalizeReturnTarget(raw) {
    if (!raw) return "";
    try {
      var parsed = new URL(String(raw), window.location.origin);
      if (parsed.origin !== window.location.origin) return "";
      var path = String(parsed.pathname || "/").replace(/\/+$/, "") || "/";
      var lowered = path.toLowerCase();
      if (
        lowered === "/service-request" ||
        lowered === "/login" ||
        lowered === "/signup" ||
        lowered === "/twofa"
      ) {
        return "";
      }
      return parsed.pathname + parsed.search + parsed.hash;
    } catch (e) {
      return "";
    }
  }

  function resolveReturnTarget() {
    var params = new URLSearchParams(window.location.search);
    return (
      normalizeReturnTarget(params.get("return_to")) ||
      normalizeReturnTarget(document.referrer) ||
      "/orders/"
    );
  }

  function isDirectRequestFlow() {
    return requestType === "normal" && !!(fixedTargetCtx && fixedTargetCtx.providerId);
  }

  function scheduleReturnToSource() {
    if (returnTimer) {
      clearTimeout(returnTimer);
      returnTimer = null;
    }
    returnTimer = setTimeout(function () {
      window.location.href = returnTargetUrl || "/orders/";
    }, 2200);
  }

  async function fetchProviderAndApply() {
    if (!providerId) return;
    try {
      var res = await ApiClient.get(API.PROVIDERS + "?page_size=1&q=id:" + providerId);
      var prov = null;
      if (res.ok && res.data) {
        var results = res.data.results || res.data;
        prov = Array.isArray(results) ? results.find(function (p) { return p.id === providerId; }) : null;
      }
      if (!prov) {
        var res2 = await ApiClient.get("/api/providers/" + providerId + "/");
        if (res2.ok && res2.data) prov = res2.data;
      }
      if (prov) applyFixedTarget(prov);
    } catch (e) {
      console.warn("[SR] fetchProvider error:", e);
    }
  }

  function applyFixedTarget(prov) {
    fixedTargetCtx = {
      provider: prov,
      providerId: prov.id,
      providerName: prov.display_name || prov.username || ("\u0645\u0632\u0648\u062f #" + prov.id),
      categoryId: null,
      subcategoryId: null,
      city: prov.city_display || prov.city || "",
    };

    if (prov.subcategory_ids && prov.subcategory_ids.length > 0) {
      for (var ci = 0; ci < categories.length; ci++) {
        var cat = categories[ci];
        var subs = cat.subcategories || [];
        for (var si = 0; si < subs.length; si++) {
          if (prov.subcategory_ids.indexOf(subs[si].id) !== -1) {
            fixedTargetCtx.categoryId = cat.id;
            fixedTargetCtx.subcategoryId = subs[si].id;
            fixedTargetCtx.categoryName = cat.name;
            fixedTargetCtx.subcategoryName = subs[si].name;
            break;
          }
        }
        if (fixedTargetCtx.categoryId) break;
      }
    }

    dom.typeSection.classList.add("hidden");
    dom.scopeFields.classList.add("hidden");
    dom.fixedTarget.classList.remove("hidden");
    dom.dispatchSection.classList.add("hidden");
    toggleDirectDesktopLayout(true);

    dom.scopeTitle.textContent = "\u0637\u0644\u0628 \u0645\u0628\u0627\u0634\u0631 \u0644\u0645\u0632\u0648\u062f \u062e\u062f\u0645\u0629";
    dom.scopeText.textContent = "\u062a\u0645 \u062a\u062d\u062f\u064a\u062f \u0627\u0644\u0645\u0632\u0648\u062f \u062a\u0644\u0642\u0627\u0626\u064a\u0627\u064b \u0628\u0646\u0627\u0621\u064b \u0639\u0644\u0649 \u0635\u0641\u062d\u0629 \u0627\u0644\u0645\u0632\u0648\u062f.";
    dom.fixedProvName.textContent = fixedTargetCtx.providerName;

    if (serviceId) {
      dom.fixedService.textContent = "\u062e\u062f\u0645\u0629 #" + serviceId;
      dom.fixedServiceRow.style.display = "";
    } else {
      dom.fixedServiceRow.style.display = "none";
    }

    dom.fixedCategory.textContent = fixedTargetCtx.categoryName || "\u2014";
    dom.fixedSubcat.textContent = fixedTargetCtx.subcategoryName || "\u2014";
    dom.fixedCity.textContent = fixedTargetCtx.city || "\u2014";

    if (fixedTargetCtx.categoryId) {
      dom.category.value = fixedTargetCtx.categoryId;
      onCategoryChange();
      if (fixedTargetCtx.subcategoryId) {
        dom.subcategory.value = fixedTargetCtx.subcategoryId;
      }
    }

    updateHeroTypeContent("normal", fixedTargetCtx.providerName);
    dom.submitText.textContent = "\u0625\u0631\u0633\u0627\u0644 \u0627\u0644\u0637\u0644\u0628 \u0627\u0644\u0645\u0628\u0627\u0634\u0631";

    renumberSteps();
  }

  /* ═══════════════════════════════════════
     Events
     ═══════════════════════════════════════ */
  function bindEvents() {
    // Type chips
    dom.typeChips.addEventListener("click", function (e) {
      var chip = e.target.closest(".sr-chip");
      if (!chip || chip.classList.contains("hidden")) return;
      dom.typeChips.querySelectorAll(".sr-chip").forEach(function (c) { c.classList.remove("active"); });
      chip.classList.add("active");
      requestType = chip.dataset.val;
      syncTypeUI();
    });

    // Category change
    dom.category.addEventListener("change", onCategoryChange);

    // Region change
    dom.region.addEventListener("change", function () {
      var val = dom.region.value;
      UI.populateCityOptions(dom.city, regionCatalog, val);
      dom.cityClear.classList.toggle("hidden", !val);
    });

    // City change
    dom.city.addEventListener("change", function () {
      dom.cityClear.classList.toggle("hidden", !dom.city.value);
    });

    // City clear
    dom.cityClear.addEventListener("click", function () {
      dom.region.value = "";
      dom.city.innerHTML = '<option value="">\u0627\u062e\u062a\u0631 \u0627\u0644\u0645\u062f\u064a\u0646\u0629</option>';
      dom.city.disabled = true;
      dom.cityClear.classList.add("hidden");
    });

    // Dispatch chips
    dom.dispatchChips.addEventListener("click", function (e) {
      var chip = e.target.closest(".sr-chip");
      if (!chip) return;
      dom.dispatchChips.querySelectorAll(".sr-chip").forEach(function (c) { c.classList.remove("active"); });
      chip.classList.add("active");
      dispatchMode = chip.dataset.dispatch;
      syncDispatchUI();
    });

    // Selected provider actions
    dom.spChange.addEventListener("click", function () { openMapModal(); });
    dom.spRemove.addEventListener("click", function () { clearSelectedProvider(); });

    // Char counts
    dom.reqTitle.addEventListener("input", function () {
      updateCharCount(dom.reqTitle, dom.titleCount, dom.titleCountWrap, 50);
    });
    dom.desc.addEventListener("input", function () {
      updateCharCount(dom.desc, dom.descCount, dom.descCountWrap, 300);
    });

    // File inputs
    dom.imagesInput.addEventListener("change", function () {
      imageFiles = imageFiles.concat(Array.from(dom.imagesInput.files));
      dom.imagesInput.value = "";
      renderAttachments();
    });
    dom.videosInput.addEventListener("change", function () {
      videoFiles = videoFiles.concat(Array.from(dom.videosInput.files));
      dom.videosInput.value = "";
      renderAttachments();
    });
    dom.filesInput.addEventListener("change", function () {
      docFiles = docFiles.concat(Array.from(dom.filesInput.files));
      dom.filesInput.value = "";
      renderAttachments();
    });

    // Audio
    dom.audioBtn.addEventListener("click", toggleAudioRecording);
    dom.audioRemove.addEventListener("click", removeAudio);

    // Submit
    dom.form.addEventListener("submit", function (e) {
      e.preventDefault();
      submit();
    });

    // Toast close
    dom.toastClose.addEventListener("click", hideToast);

    // Map modal close
    dom.mapClose.addEventListener("click", closeMapModal);
    dom.mapBackdrop.addEventListener("click", closeMapModal);
  }

  /* ═══════════════════════════════════════
     Type & Dispatch UI Sync
     ═══════════════════════════════════════ */
  function syncTypeUI() {
    var isCompetitive = requestType === "competitive";
    toggleDirectDesktopLayout(!!fixedTargetCtx && requestType === "normal");

    // Deadline only for competitive
    dom.deadlineGroup.classList.toggle("hidden", !isCompetitive);

    // Dispatch section visible for competitive & urgent (not normal/direct)
    if (!fixedTargetCtx) {
      dom.dispatchSection.classList.toggle("hidden", requestType === "normal");
    }

    // Update submit text
    if (!fixedTargetCtx) {
      if (requestType === "urgent") {
        updateHeroTypeContent("urgent");
        dom.submitText.textContent = "\u0625\u0631\u0633\u0627\u0644 \u0627\u0644\u0637\u0644\u0628 \u0627\u0644\u0639\u0627\u062c\u0644";
        dom.submitHelper.textContent = "\u0633\u064a\u062a\u0645 \u0625\u0631\u0633\u0627\u0644 \u0627\u0644\u0637\u0644\u0628 \u0641\u0648\u0631\u0627\u064b \u0644\u0644\u0645\u0632\u0648\u062f\u064a\u0646 \u0627\u0644\u0645\u062a\u0627\u062d\u064a\u0646.";
      } else if (isCompetitive) {
        updateHeroTypeContent("competitive");
        dom.submitText.textContent = "\u0625\u0631\u0633\u0627\u0644 \u0627\u0644\u0637\u0644\u0628 \u0627\u0644\u062a\u0646\u0627\u0641\u0633\u064a";
        dom.submitHelper.textContent = "\u0633\u064a\u062a\u0645\u0643\u0646 \u0627\u0644\u0645\u0632\u0648\u062f\u0648\u0646 \u0645\u0646 \u062a\u0642\u062f\u064a\u0645 \u0639\u0631\u0648\u0636\u0647\u0645 \u0639\u0644\u064a\u0647.";
      } else {
        updateHeroTypeContent("normal");
        dom.submitText.textContent = "\u0625\u0631\u0633\u0627\u0644 \u0627\u0644\u0637\u0644\u0628";
        dom.submitHelper.textContent = "\u0627\u0643\u062a\u0628 \u0627\u0644\u0645\u0637\u0644\u0648\u0628 \u0628\u0648\u0636\u0648\u062d \u0648\u0623\u0631\u0641\u0642 \u0645\u0627 \u064a\u0644\u0632\u0645 \u0641\u0642\u0637.";
      }
    }

    syncDispatchUI();
    renumberSteps();
  }

  function toggleDirectDesktopLayout(enabled) {
    if (!dom.container) return;
    dom.container.classList.toggle("sr-direct-layout", !!enabled);
  }

  function syncDispatchUI() {
    var nearestChip = dom.dispatchChips.querySelector('[data-dispatch="nearest"]');
    if (requestType !== "urgent") {
      nearestChip.classList.add("hidden");
      if (dispatchMode === "nearest") {
        dispatchMode = "all";
        dom.dispatchChips.querySelectorAll(".sr-chip").forEach(function (c) { c.classList.remove("active"); });
        dom.dispatchChips.querySelector('[data-dispatch="all"]').classList.add("active");
      }
    } else {
      nearestChip.classList.remove("hidden");
    }

    if (dispatchMode === "nearest" && nearestProvider) {
      showSelectedProviderCard(nearestProvider);
    } else {
      dom.selectedProv.classList.remove("visible");
    }

    if (dispatchMode === "nearest" && !nearestProvider && requestType === "urgent") {
      setTimeout(function () { openMapModal(); }, 250);
    }
  }

  function renumberSteps() {
    var steps = document.querySelectorAll(".sr-section:not(.hidden) .sr-step");
    var n = 1;
    steps.forEach(function (el) { el.textContent = n++; });
  }

  function updateHeroTypeContent(type, providerName) {
    if (!dom.title || !dom.subtitle || !dom.typeBadge || !dom.typeBadgeText) return;

    var nextType = type || requestType || "competitive";
    var badgeText = "\u0646\u0648\u0639 \u0627\u0644\u0637\u0644\u0628: \u062a\u0646\u0627\u0641\u0633\u064a";
    var title = "\u0637\u0644\u0628 \u062e\u062f\u0645\u0629 \u062a\u0646\u0627\u0641\u0633\u064a";
    var subtitle = "\u0623\u0637\u0644\u0642 \u0637\u0644\u0628\u0643 \u0644\u064a\u0635\u0644 \u0625\u0644\u0649 \u0627\u0644\u0645\u0632\u0648\u062f\u064a\u0646 \u0627\u0644\u0645\u0637\u0627\u0628\u0642\u064a\u0646 \u0648\u064a\u0642\u062f\u0645\u0648\u0627 \u0644\u0643 \u0639\u0631\u0648\u0636\u0647\u0645 \u0644\u0644\u0645\u0642\u0627\u0631\u0646\u0629.";
    var noteTitle = "\u0647\u0630\u0627 \u0627\u0644\u0646\u0648\u0639 \u0645\u0646\u0627\u0633\u0628 \u0644\u0644\u0645\u0642\u0627\u0631\u0646\u0629 \u0628\u064a\u0646 \u0627\u0644\u0639\u0631\u0648\u0636";
    var noteBody = "\u064a\u0635\u0644 \u0637\u0644\u0628\u0643 \u0625\u0644\u0649 \u0627\u0644\u0645\u0632\u0648\u062f\u064a\u0646 \u0627\u0644\u0645\u0637\u0627\u0628\u0642\u064a\u0646 \u0644\u064a\u0642\u062f\u0645\u0648\u0627 \u0644\u0643 \u0639\u0631\u0648\u0636\u0647\u0645\u060c \u062b\u0645 \u062a\u062e\u062a\u0627\u0631 \u0627\u0644\u0623\u0646\u0633\u0628 \u0645\u0646 \u062d\u064a\u062b \u0627\u0644\u0633\u0639\u0631 \u0648\u0627\u0644\u0645\u062f\u0629 \u0648\u0637\u0631\u064a\u0642\u0629 \u0627\u0644\u062a\u0646\u0641\u064a\u0630.";
    var pill1 = "\u0645\u0637\u0627\u0628\u0642\u0629 \u0630\u0643\u064a\u0629 \u062d\u0633\u0628 \u0627\u0644\u062a\u062e\u0635\u0635";
    var pill2 = "\u0627\u0633\u062a\u0642\u0628\u0627\u0644 \u0623\u0643\u062b\u0631 \u0645\u0646 \u0639\u0631\u0636";
    var pill3 = "\u0625\u0645\u0643\u0627\u0646\u064a\u0629 \u062a\u062d\u062f\u064a\u062f \u0645\u0648\u0639\u062f \u0627\u0644\u0639\u0631\u0648\u0636";

    if (nextType === "urgent") {
      badgeText = "\u0646\u0648\u0639 \u0627\u0644\u0637\u0644\u0628: \u0639\u0627\u062c\u0644";
      title = "\u0637\u0644\u0628 \u062e\u062f\u0645\u0629 \u0639\u0627\u062c\u0644";
      subtitle = "\u0645\u0633\u0627\u0631 \u0633\u0631\u064a\u0639 \u0644\u0644\u062d\u0627\u0644\u0627\u062a \u0627\u0644\u062a\u064a \u062a\u062d\u062a\u0627\u062c \u0627\u0633\u062a\u062c\u0627\u0628\u0629 \u0641\u0648\u0631\u064a\u0629 \u0645\u0646 \u0627\u0644\u0645\u0632\u0648\u062f\u064a\u0646 \u0627\u0644\u0645\u0637\u0627\u0628\u0642\u064a\u0646.";
      noteTitle = "\u0647\u0630\u0627 \u0627\u0644\u0646\u0648\u0639 \u0645\u0635\u0645\u0645 \u0644\u0644\u062d\u0627\u0644\u0627\u062a \u0627\u0644\u0639\u0627\u062c\u0644\u0629";
      noteBody = "\u064a\u0645\u0643\u0646\u0643 \u0627\u0644\u0625\u0631\u0633\u0627\u0644 \u0644\u0644\u062c\u0645\u064a\u0639 \u0623\u0648 \u0627\u062e\u062a\u064a\u0627\u0631 \u0627\u0644\u0623\u0642\u0631\u0628 \u0639\u0628\u0631 \u0627\u0644\u062e\u0631\u064a\u0637\u0629\u060c \u0645\u0639 \u0625\u0628\u0631\u0627\u0632 \u0627\u0644\u062a\u0637\u0627\u0628\u0642 \u062d\u0633\u0628 \u0627\u0644\u062a\u0635\u0646\u064a\u0641 \u0648\u0627\u0644\u0645\u062f\u064a\u0646\u0629.";
      pill1 = "\u0627\u0633\u062a\u062c\u0627\u0628\u0629 \u0623\u0633\u0631\u0639 \u0644\u0644\u0637\u0644\u0628";
      pill2 = "\u0625\u0631\u0633\u0627\u0644 \u0644\u0644\u062c\u0645\u064a\u0639 \u0623\u0648 \u0644\u0644\u0623\u0642\u0631\u0628";
      pill3 = "\u062e\u0631\u064a\u0637\u0629 \u062a\u0641\u0627\u0639\u0644\u064a\u0629 \u0644\u0644\u062a\u0648\u062c\u064a\u0647";
    } else if (nextType === "normal") {
      var displayName = providerName || (fixedTargetCtx && fixedTargetCtx.providerName) || "\u0645\u0632\u0648\u062f \u0627\u0644\u062e\u062f\u0645\u0629";
      badgeText = "\u0646\u0648\u0639 \u0627\u0644\u0637\u0644\u0628: \u0645\u0628\u0627\u0634\u0631";
      title = "\u0637\u0644\u0628 \u0645\u0628\u0627\u0634\u0631";
      subtitle = "\u0633\u064a\u062a\u0645 \u0625\u0631\u0633\u0627\u0644 \u0637\u0644\u0628\u0643 \u0645\u0628\u0627\u0634\u0631\u0629 \u0644\u0640 " + displayName + "\u060c \u062f\u0648\u0646 \u0625\u062f\u062e\u0627\u0644\u0647 \u0641\u064a \u0645\u0633\u0627\u0631 \u062a\u0646\u0627\u0641\u0633\u064a \u0623\u0648 \u0639\u0627\u062c\u0644.";
      noteTitle = "\u0647\u0630\u0627 \u0627\u0644\u0646\u0648\u0639 \u0645\u0648\u062c\u0647 \u0644\u0645\u0632\u0648\u062f \u0645\u062d\u062f\u062f";
      noteBody = "\u064a\u0635\u0644 \u0627\u0644\u0637\u0644\u0628 \u0645\u0628\u0627\u0634\u0631\u0629 \u0625\u0644\u0649 \u0627\u0644\u0645\u0632\u0648\u062f \u0627\u0644\u0630\u064a \u0627\u062e\u062a\u0631\u062a\u0647\u060c \u0645\u0639 \u0627\u0644\u062d\u0641\u0627\u0638 \u0639\u0644\u0649 \u0646\u0641\u0633 \u062c\u0648\u062f\u0629 \u0627\u0644\u062a\u0641\u0627\u0635\u064a\u0644 \u0648\u0627\u0644\u0645\u0631\u0641\u0642\u0627\u062a.";
      pill1 = "\u0645\u0648\u062c\u0647 \u0625\u0644\u0649 \u0645\u0632\u0648\u062f \u0648\u0627\u062d\u062f";
      pill2 = "\u062f\u0642\u0629 \u0641\u064a \u0646\u0637\u0627\u0642 \u0627\u0644\u0625\u0631\u0633\u0627\u0644";
      pill3 = "\u0648\u0636\u0648\u062d \u0641\u064a \u0646\u0648\u0639 \u0627\u0644\u0637\u0644\u0628";
    }

    dom.typeBadge.dataset.tone = nextType;
    dom.typeBadgeText.textContent = badgeText;
    dom.title.textContent = title;
    dom.subtitle.textContent = subtitle;
    if (dom.typeNoteTitle) dom.typeNoteTitle.textContent = noteTitle;
    if (dom.typeNoteBody) dom.typeNoteBody.textContent = noteBody;
    if (dom.heroPill1) dom.heroPill1.textContent = pill1;
    if (dom.heroPill2) dom.heroPill2.textContent = pill2;
    if (dom.heroPill3) dom.heroPill3.textContent = pill3;
  }

  /* ═══════════════════════════════════════
     Char Count
     ═══════════════════════════════════════ */
  function updateCharCount(input, countEl, wrapEl, max) {
    var len = input.value.length;
    countEl.textContent = len;
    wrapEl.classList.remove("is-warning", "is-limit");
    if (len >= max) wrapEl.classList.add("is-limit");
    else if (len >= max * 0.85) wrapEl.classList.add("is-warning");
  }

  /* ═══════════════════════════════════════
     Attachments Preview
     ═══════════════════════════════════════ */
  function renderAttachments() {
    dom.attachments.innerHTML = "";
    imageFiles.forEach(function (f, i) {
      dom.attachments.appendChild(makeThumb(f, "image", i, imageFiles));
    });
    videoFiles.forEach(function (f, i) {
      dom.attachments.appendChild(makeThumb(f, "video", i, videoFiles));
    });
    docFiles.forEach(function (f, i) {
      dom.attachments.appendChild(makeFileThumb(f, i, docFiles));
    });
  }

  function makeThumb(file, type, idx, arr) {
    var div = document.createElement("div");
    div.className = "sr-attach-item";
    var img = document.createElement("img");
    img.src = URL.createObjectURL(file);
    img.alt = file.name;
    div.appendChild(img);

    var btn = document.createElement("button");
    btn.className = "sr-attach-remove";
    btn.innerHTML = "\u2715";
    btn.type = "button";
    btn.addEventListener("click", function () {
      arr.splice(idx, 1);
      renderAttachments();
    });
    div.appendChild(btn);
    return div;
  }

  function makeFileThumb(file, idx, arr) {
    var div = document.createElement("div");
    div.className = "sr-attach-item file-type";

    var icon = document.createElement("div");
    icon.innerHTML = '<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#64748b" stroke-width="1.5"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/></svg>';
    div.appendChild(icon);

    var span = document.createElement("span");
    span.textContent = file.name;
    div.appendChild(span);

    var btn = document.createElement("button");
    btn.className = "sr-attach-remove";
    btn.innerHTML = "\u2715";
    btn.type = "button";
    btn.addEventListener("click", function () {
      arr.splice(idx, 1);
      renderAttachments();
    });
    div.appendChild(btn);
    return div;
  }

  /* ═══════════════════════════════════════
     Audio Recording
     ═══════════════════════════════════════ */
  async function toggleAudioRecording() {
    if (isRecording) {
      stopRecording();
      return;
    }
    try {
      var stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      audioChunks = [];
      mediaRecorder = new MediaRecorder(stream);
      mediaRecorder.ondataavailable = function (e) {
        if (e.data.size > 0) audioChunks.push(e.data);
      };
      mediaRecorder.onstop = function () {
        stream.getTracks().forEach(function (t) { t.stop(); });
        audioBlob = new Blob(audioChunks, { type: "audio/webm" });
        dom.audioPlayer.src = URL.createObjectURL(audioBlob);
        dom.audioPreview.classList.add("visible");
      };
      mediaRecorder.start();
      isRecording = true;
      dom.audioBtn.classList.add("recording");
      var textNode = findTextNode(dom.audioBtn);
      if (textNode) textNode.textContent = " \u0625\u064a\u0642\u0627\u0641 \u0627\u0644\u062a\u0633\u062c\u064a\u0644";
    } catch (e) {
      showToast("error", "\u062e\u0637\u0623", "\u0644\u0645 \u064a\u062a\u0645 \u0627\u0644\u0633\u0645\u0627\u062d \u0628\u0627\u0644\u0648\u0635\u0648\u0644 \u0625\u0644\u0649 \u0627\u0644\u0645\u064a\u0643\u0631\u0648\u0641\u0648\u0646.");
    }
  }

  function findTextNode(el) {
    var nodes = el.childNodes;
    for (var i = 0; i < nodes.length; i++) {
      if (nodes[i].nodeType === 3 && nodes[i].textContent.trim()) return nodes[i];
    }
    return null;
  }

  function stopRecording() {
    if (mediaRecorder && mediaRecorder.state !== "inactive") {
      mediaRecorder.stop();
    }
    isRecording = false;
    dom.audioBtn.classList.remove("recording");
    var textNode = findTextNode(dom.audioBtn);
    if (textNode) textNode.textContent = " \u062a\u0633\u062c\u064a\u0644 \u0635\u0648\u062a\u064a";
  }

  function removeAudio() {
    audioBlob = null;
    audioChunks = [];
    dom.audioPlayer.src = "";
    dom.audioPreview.classList.remove("visible");
  }

  /* ═══════════════════════════════════════
     Selected Provider Card
     ═══════════════════════════════════════ */
  function showSelectedProviderCard(prov) {
    nearestProvider = prov;
    dom.spAvatar.src = prov.avatar || prov.profile_image || "";
    dom.spName.textContent = prov.name || prov.display_name || "";
    var parts = [];
    if (prov.rating != null) parts.push("\u2b50 " + Number(prov.rating).toFixed(1));
    if (prov.completed != null) parts.push(prov.completed + " \u0637\u0644\u0628 \u0645\u0643\u062a\u0645\u0644");
    dom.spMeta.textContent = parts.join(" \u2022 ");
    dom.selectedProv.classList.add("visible");
  }

  function clearSelectedProvider() {
    nearestProvider = null;
    dom.selectedProv.classList.remove("visible");
  }

  /* ═══════════════════════════════════════
     Map Modal
     ═══════════════════════════════════════ */
  function openMapModal() {
    dom.mapModal.classList.add("open");
    document.body.style.overflow = "hidden";
    dom.modalStatus.style.display = "flex";
    dom.modalStatusText.textContent = "\u062c\u0627\u0631\u064a \u062a\u062d\u062f\u064a\u062f \u0645\u0648\u0642\u0639\u0643...";
    dom.modalList.innerHTML = "";
    dom.modalEmpty.classList.remove("visible");

    if (!leafletMap) {
      leafletMap = L.map(dom.modalMap, {
        center: [24.7136, 46.6753],
        zoom: 11,
        zoomControl: false,
      });
      L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
        attribution: '&copy; <a href="https://www.openstreetmap.org/">OSM</a>',
        maxZoom: 18,
      }).addTo(leafletMap);
    }
    setTimeout(function () { leafletMap.invalidateSize(); }, 350);
    geolocateAndFetch();
  }

  function closeMapModal() {
    dom.mapModal.classList.remove("open");
    document.body.style.overflow = "";
  }

  function normalizeCoordinate(value) {
    var parsed = Number(value);
    if (!Number.isFinite(parsed)) return null;
    return Number(parsed.toFixed(6));
  }

  function geolocateAndFetch() {
    if (!navigator.geolocation) {
      dom.modalStatusText.textContent = "\u0627\u0644\u0645\u062a\u0635\u0641\u062d \u0644\u0627 \u064a\u062f\u0639\u0645 \u062a\u062d\u062f\u064a\u062f \u0627\u0644\u0645\u0648\u0642\u0639. \u064a\u062a\u0645 \u0627\u0633\u062a\u062e\u062f\u0627\u0645 \u0627\u0644\u0645\u0648\u0642\u0639 \u0627\u0644\u0627\u0641\u062a\u0631\u0627\u0636\u064a.";
      fetchNearbyProviders(24.7136, 46.6753);
      return;
    }
    navigator.geolocation.getCurrentPosition(
      function (pos) {
        requestLat = normalizeCoordinate(pos.coords.latitude);
        requestLng = normalizeCoordinate(pos.coords.longitude);
        if (requestLat === null || requestLng === null) {
          dom.modalStatusText.textContent = "تعذر قراءة موقعك الحالي. حاول مرة أخرى.";
          return;
        }
        dom.modalStatusText.textContent = "\u062a\u0645 \u062a\u062d\u062f\u064a\u062f \u0645\u0648\u0642\u0639\u0643. \u062c\u0627\u0631\u064a \u0627\u0644\u0628\u062d\u062b \u0639\u0646 \u0627\u0644\u0645\u0632\u0648\u062f\u064a\u0646...";
        leafletMap.setView([requestLat, requestLng], 13);

        if (leafletMarker) leafletMap.removeLayer(leafletMarker);
        leafletMarker = L.marker([requestLat, requestLng], {
          icon: L.divIcon({
            className: "",
            html: '<div style="width:16px;height:16px;border-radius:50%;background:#3b82f6;border:3px solid #fff;box-shadow:0 2px 6px rgba(0,0,0,0.3);"></div>',
            iconSize: [16, 16],
            iconAnchor: [8, 8],
          }),
        }).addTo(leafletMap);

        fetchNearbyProviders(requestLat, requestLng);
      },
      function () {
        dom.modalStatusText.textContent = "\u0644\u0645 \u064a\u062a\u0645 \u0627\u0644\u0633\u0645\u0627\u062d \u0628\u062a\u062d\u062f\u064a\u062f \u0627\u0644\u0645\u0648\u0642\u0639. \u064a\u062a\u0645 \u0627\u0633\u062a\u062e\u062f\u0627\u0645 \u0627\u0644\u0645\u0648\u0642\u0639 \u0627\u0644\u0627\u0641\u062a\u0631\u0627\u0636\u064a.";
        fetchNearbyProviders(24.7136, 46.6753);
      },
      { enableHighAccuracy: true, timeout: 10000 }
    );
  }

  async function fetchNearbyProviders(lat, lng) {
    var subcatId = dom.subcategory.value;
    var url = API.PROVIDERS + "?has_location=true&accepts_urgent=true&page_size=30";
    if (subcatId) url += "&subcategory_id=" + subcatId;

    try {
      var res = await ApiClient.get(url);
      if (res.ok && res.data) {
        var results = res.data.results || res.data;
        nearbyProviders = Array.isArray(results) ? results : [];
      } else {
        nearbyProviders = [];
      }
    } catch (e) {
      nearbyProviders = [];
    }

    nearbyProviders.forEach(function (p) {
      if (p.lat && p.lng) {
        p._dist = haversineKm(lat, lng, parseFloat(p.lat), parseFloat(p.lng));
      } else {
        p._dist = 9999;
      }
    });
    nearbyProviders.sort(function (a, b) { return a._dist - b._dist; });

    dom.modalStatus.style.display = "none";
    renderProvidersOnMap(lat, lng);
    renderProvidersList();
  }

  function haversineKm(lat1, lon1, lat2, lon2) {
    var R = 6371;
    var dLat = ((lat2 - lat1) * Math.PI) / 180;
    var dLon = ((lon2 - lon1) * Math.PI) / 180;
    var a =
      Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos((lat1 * Math.PI) / 180) * Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLon / 2) * Math.sin(dLon / 2);
    return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  }

  function renderProvidersOnMap(lat, lng) {
    providerMarkers.forEach(function (m) { leafletMap.removeLayer(m); });
    providerMarkers = [];

    nearbyProviders.forEach(function (p) {
      if (!p.lat || !p.lng) return;
      var imgSrc = p.profile_image || "";
      var marker = L.marker([parseFloat(p.lat), parseFloat(p.lng)], {
        icon: L.divIcon({
          className: "sr-map-popup",
          html: '<div style="width:32px;height:32px;border-radius:10px;overflow:hidden;border:2px solid #0f766e;box-shadow:0 2px 8px rgba(0,0,0,0.2);background:#fff;">'
            + '<img src="' + escHtml(imgSrc) + '" style="width:100%;height:100%;object-fit:cover;" onerror="this.style.display=\'none\'" />'
            + '</div>',
          iconSize: [32, 32],
          iconAnchor: [16, 32],
        }),
      }).addTo(leafletMap);

      marker.bindPopup(buildPopupHtml(p), { className: "sr-map-popup", maxWidth: 250 });
      providerMarkers.push(marker);
    });

    if (nearbyProviders.length > 0) {
      var pts = nearbyProviders.filter(function (p) { return p.lat && p.lng; })
        .map(function (p) { return [parseFloat(p.lat), parseFloat(p.lng)]; });
      pts.push([lat, lng]);
      if (pts.length > 1) leafletMap.fitBounds(pts, { padding: [40, 40] });
    }
  }

  function escHtml(str) {
    var d = document.createElement("div");
    d.appendChild(document.createTextNode(str || ""));
    return d.innerHTML;
  }

  function buildPopupHtml(p) {
    var name = escHtml(p.display_name || p.username || "");
    var img = escHtml(p.profile_image || "");
    var rating = p.rating_avg != null ? Number(p.rating_avg).toFixed(1) : "\u2014";
    var completed = p.completed_requests || 0;
    var phone = escHtml(p.phone || "");
    var whatsapp = escHtml(p.whatsapp_url || "");

    var html = '<div class="sr-popup-inner">';
    if (img) html += '<img src="' + img + '" alt="" />';
    html += '<div class="sr-popup-name">' + name + '</div>';
    html += '<div class="sr-popup-stats">\u2b50 ' + rating + ' \u2022 ' + completed + ' \u0637\u0644\u0628</div>';
    html += '<div class="sr-popup-actions">';
    if (phone) html += '<a href="tel:' + phone + '" class="sr-prov-action-btn call" onclick="event.stopPropagation()">\ud83d\udcde \u0627\u062a\u0635\u0627\u0644</a>';
    if (whatsapp) html += '<a href="' + whatsapp + '" target="_blank" rel="noopener" class="sr-prov-action-btn whatsapp" onclick="event.stopPropagation()">\ud83d\udcac \u0648\u0627\u062a\u0633\u0627\u0628</a>';
    html += '<button class="sr-prov-action-btn send" onclick="window._srSelectProvider(' + p.id + ')">\u2713 \u0627\u062e\u062a\u064a\u0627\u0631</button>';
    html += '</div></div>';
    return html;
  }

  function renderProvidersList() {
    dom.modalList.innerHTML = "";
    if (nearbyProviders.length === 0) {
      dom.modalEmpty.classList.add("visible");
      return;
    }
    dom.modalEmpty.classList.remove("visible");

    nearbyProviders.forEach(function (p) {
      var card = document.createElement("div");
      card.className = "sr-prov-card";
      card.dataset.id = p.id;
      if (nearestProvider && nearestProvider.id === p.id) card.classList.add("selected");

      var name = escHtml(p.display_name || p.username || "");
      var img = escHtml(p.profile_image || "");
      var rating = p.rating_avg != null ? Number(p.rating_avg).toFixed(1) : "\u2014";
      var completed = p.completed_requests || 0;
      var dist = p._dist < 9999 ? p._dist.toFixed(1) + " \u0643\u0645" : "";
      var phone = escHtml(p.phone || "");
      var whatsapp = escHtml(p.whatsapp_url || "");

      var badge = "";
      if (p.is_verified_blue) {
        badge = '<div class="sr-prov-badge blue"><svg viewBox="0 0 24 24" fill="currentColor"><path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z"/></svg></div>';
      } else if (p.is_verified_green) {
        badge = '<div class="sr-prov-badge green"><svg viewBox="0 0 24 24" fill="currentColor"><path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z"/></svg></div>';
      }

      card.innerHTML =
        '<div class="sr-prov-card-avatar-wrap">'
        + '<img class="sr-prov-card-avatar" src="' + img + '" alt="" onerror="this.style.display=\'none\'" />'
        + badge
        + '</div>'
        + '<div class="sr-prov-card-info">'
        + '<div class="sr-prov-card-name">' + name + '</div>'
        + '<div class="sr-prov-card-stats">'
        + '<span><svg viewBox="0 0 24 24" fill="#f59e0b" stroke="none"><path d="M12 2l3.09 6.26L22 9.27l-5 4.87L18.18 22 12 18.56 5.82 22 7 14.14l-5-4.87 6.91-1.01z"/></svg> ' + rating + '</span>'
        + '<span>' + completed + ' \u0645\u0643\u062a\u0645\u0644</span>'
        + (dist ? '<span>' + dist + '</span>' : '')
        + '</div>'
        + '</div>'
        + '<div class="sr-prov-card-actions">'
        + (phone ? '<a href="tel:' + phone + '" class="sr-prov-action-btn call" onclick="event.stopPropagation()">\ud83d\udcde</a>' : '')
        + (whatsapp ? '<a href="' + whatsapp + '" target="_blank" rel="noopener" class="sr-prov-action-btn whatsapp" onclick="event.stopPropagation()">\ud83d\udcac</a>' : '')
        + '<button class="sr-prov-action-btn send" data-select="' + p.id + '">\u2713 \u0625\u0631\u0633\u0627\u0644</button>'
        + '</div>';

      var avatarWrap = card.querySelector(".sr-prov-card-avatar-wrap");
      if (avatarWrap && p.username) {
        avatarWrap.addEventListener("click", function (e) {
          e.stopPropagation();
          window.open("/provider/" + p.username + "/", "_blank");
        });
      }

      var sendBtn = card.querySelector("[data-select]");
      if (sendBtn) {
        sendBtn.addEventListener("click", (function (prov) {
          return function (e) {
            e.stopPropagation();
            selectProviderFromModal(prov);
          };
        })(p));
      }

      dom.modalList.appendChild(card);
    });
  }

  function selectProviderFromModal(p) {
    nearestProvider = {
      id: p.id,
      name: p.display_name || p.username || "",
      avatar: p.profile_image || "",
      rating: p.rating_avg,
      completed: p.completed_requests || 0,
      phone: p.phone || "",
      whatsapp: p.whatsapp_url || "",
    };
    showSelectedProviderCard(nearestProvider);
    closeMapModal();
    showToast("success", "\u062a\u0645 \u0627\u0644\u0627\u062e\u062a\u064a\u0627\u0631", "\u062a\u0645 \u0627\u062e\u062a\u064a\u0627\u0631 " + nearestProvider.name + " \u0643\u0645\u0632\u0648\u062f \u0642\u0631\u064a\u0628.");
  }

  window._srSelectProvider = function (id) {
    var p = nearbyProviders.find(function (pv) { return pv.id === id; });
    if (p) selectProviderFromModal(p);
  };

  /* ═══════════════════════════════════════
     Validation
     ═══════════════════════════════════════ */
  function clearErrors() {
    [dom.catError, dom.subError, dom.cityError, dom.titleError, dom.descError, dom.deadlineError].forEach(function (e) {
      if (e) { e.textContent = ""; e.classList.remove("visible"); }
    });
    [dom.category, dom.subcategory, dom.region, dom.city, dom.reqTitle, dom.desc, dom.deadline].forEach(function (e) {
      if (e) e.classList.remove("is-invalid");
    });
  }

  function showFieldError(elem, errEl, msg) {
    if (elem) elem.classList.add("is-invalid");
    if (errEl) { errEl.textContent = msg; errEl.classList.add("visible"); }
  }

  function validate() {
    clearErrors();
    var ok = true;

    if (!fixedTargetCtx) {
      if (!dom.subcategory.value) {
        if (!dom.category.value) showFieldError(dom.category, dom.catError, "\u0627\u062e\u062a\u0631 \u0627\u0644\u0642\u0633\u0645 \u0627\u0644\u0631\u0626\u064a\u0633\u064a");
        showFieldError(dom.subcategory, dom.subError, "\u0627\u062e\u062a\u0631 \u0627\u0644\u062a\u0635\u0646\u064a\u0641 \u0627\u0644\u0641\u0631\u0639\u064a");
        ok = false;
      }
    }

    var title = dom.reqTitle.value.trim();
    if (!title) {
      showFieldError(dom.reqTitle, dom.titleError, "\u0623\u062f\u062e\u0644 \u0639\u0646\u0648\u0627\u0646 \u0627\u0644\u0637\u0644\u0628");
      ok = false;
    }

    var desc = dom.desc.value.trim();
    if (!desc) {
      showFieldError(dom.desc, dom.descError, "\u0623\u062f\u062e\u0644 \u0648\u0635\u0641 \u0627\u0644\u0637\u0644\u0628");
      ok = false;
    }

    if (requestType === "competitive" && dom.deadline.value) {
      var today = new Date().toISOString().slice(0, 10);
      if (dom.deadline.value < today) {
        showFieldError(dom.deadline, dom.deadlineError, "\u0627\u0644\u062a\u0627\u0631\u064a\u062e \u064a\u062c\u0628 \u0623\u0646 \u064a\u0643\u0648\u0646 \u0627\u0644\u064a\u0648\u0645 \u0623\u0648 \u0644\u0627\u062d\u0642\u0627\u064b");
        ok = false;
      }
    }

    return ok;
  }

  /* ═══════════════════════════════════════
     Submit
     ═══════════════════════════════════════ */
  async function submit() {
    if (isSubmitting) return;
    if (!validate()) return;

    isSubmitting = true;
    holdSuccessState = false;
    dom.submitBtn.disabled = true;
    if (submitOverlay) submitOverlay.show();

    var fd = new FormData();
    fd.append("request_type", requestType);

    var subcatVal = dom.subcategory.value;
    if (subcatVal) {
      fd.append("subcategory", subcatVal);
      fd.append("subcategory_ids", subcatVal);
    } else if (fixedTargetCtx && fixedTargetCtx.subcategoryId) {
      fd.append("subcategory", fixedTargetCtx.subcategoryId);
      fd.append("subcategory_ids", fixedTargetCtx.subcategoryId);
    }

    fd.append("title", dom.reqTitle.value.trim());
    fd.append("description", dom.desc.value.trim());

    var cityVal = getCityValue();
    if (cityVal) fd.append("city", cityVal);

    if (requestType !== "normal") {
      fd.append("dispatch_mode", dispatchMode);
    }

    if (dispatchMode === "nearest" && requestLat != null && requestLng != null) {
      fd.append("request_lat", requestLat.toFixed(6));
      fd.append("request_lng", requestLng.toFixed(6));
    }

    if (requestType === "normal" && fixedTargetCtx && fixedTargetCtx.providerId) {
      fd.append("provider", fixedTargetCtx.providerId);
    } else if (requestType === "urgent" && dispatchMode === "nearest" && nearestProvider) {
      fd.append("provider", nearestProvider.id);
    }

    if (requestType === "competitive" && dom.deadline.value) {
      fd.append("quote_deadline", dom.deadline.value);
    }

    imageFiles.forEach(function (f) { fd.append("images", f); });
    videoFiles.forEach(function (f) { fd.append("videos", f); });
    docFiles.forEach(function (f) { fd.append("files", f); });
    if (audioBlob) fd.append("audio", audioBlob, "voice_recording.webm");

    try {
      var res = await ApiClient.request(API.CREATE, {
        method: "POST",
        body: fd,
        formData: true,
      });
      if (res.ok) {
        onSubmitSuccess(res.data);
      } else {
        onSubmitError(res);
      }
    } catch (e) {
      showToast("error", "\u062e\u0637\u0623", "\u062d\u062f\u062b \u062e\u0637\u0623 \u063a\u064a\u0631 \u0645\u062a\u0648\u0642\u0639. \u062d\u0627\u0648\u0644 \u0645\u0631\u0629 \u0623\u062e\u0631\u0649.");
    } finally {
      isSubmitting = false;
      if (!holdSuccessState) {
        dom.submitBtn.disabled = false;
      }
      if (submitOverlay) submitOverlay.hide();
    }
  }

  function getCityValue() {
    if (fixedTargetCtx && fixedTargetCtx.city) return fixedTargetCtx.city;
    var region = dom.region.value;
    var city = dom.city.value;
    if (!region && !city) return "";
    if (city && region) return UI.formatCityDisplay(city, region);
    if (city) return city;
    return "";
  }

  function onSubmitSuccess(data) {
    if (isDirectRequestFlow()) {
      holdSuccessState = true;
      dom.submitBtn.disabled = true;
      dom.submitText.textContent = "\u062a\u0645 \u0625\u0631\u0633\u0627\u0644 \u0627\u0644\u0637\u0644\u0628";
      dom.submitHelper.textContent = "\u064a\u0645\u0643\u0646\u0643 \u0645\u062a\u0627\u0628\u0639\u0629 \u0627\u0644\u0637\u0644\u0628 \u0645\u0646 \u0635\u0641\u062d\u0629 \u0637\u0644\u0628\u0627\u062a\u064a. \u062c\u0627\u0631\u064d \u0625\u0639\u0627\u062f\u062a\u0643 \u0644\u0644\u0635\u0641\u062d\u0629 \u0627\u0644\u0633\u0627\u0628\u0642\u0629...";
      showToast(
        "success",
        "\u062a\u0645 \u0625\u0631\u0633\u0627\u0644 \u0637\u0644\u0628\u0643",
        "\u062a\u0645 \u0625\u0631\u0633\u0627\u0644 \u0637\u0644\u0628\u0643 \u0625\u0644\u0649 " +
          ((fixedTargetCtx && fixedTargetCtx.providerName) || "\u0627\u0644\u0645\u0632\u0648\u062f") +
          ". \u064a\u0645\u0643\u0646\u0643 \u0645\u062a\u0627\u0628\u0639\u0629 \u0627\u0644\u0637\u0644\u0628 \u0645\u0646 \u0635\u0641\u062d\u0629 \u0637\u0644\u0628\u0627\u062a\u064a."
      );
      scheduleReturnToSource();
      return;
    }

    dom.form.style.display = "none";
    dom.success.classList.add("visible");

    if (requestType === "urgent") {
      dom.successTitle.textContent = "\u062a\u0645 \u0625\u0631\u0633\u0627\u0644 \u0627\u0644\u0637\u0644\u0628 \u0627\u0644\u0639\u0627\u062c\u0644";
      dom.successMsg.textContent = "\u0633\u064a\u062a\u0645 \u0625\u0634\u0639\u0627\u0631 \u0627\u0644\u0645\u0632\u0648\u062f\u064a\u0646 \u0627\u0644\u0645\u062a\u0627\u062d\u064a\u0646 \u0641\u0648\u0631\u0627\u064b.";
    } else if (requestType === "competitive") {
      dom.successTitle.textContent = "\u062a\u0645 \u0625\u0631\u0633\u0627\u0644 \u0627\u0644\u0637\u0644\u0628 \u0627\u0644\u062a\u0646\u0627\u0641\u0633\u064a";
      dom.successMsg.textContent = "\u0633\u062a\u0628\u062f\u0623 \u0627\u0644\u0639\u0631\u0648\u0636 \u0628\u0627\u0644\u0648\u0635\u0648\u0644 \u0642\u0631\u064a\u0628\u0627\u064b.";
    } else {
      dom.successTitle.textContent = "\u062a\u0645 \u0625\u0631\u0633\u0627\u0644 \u0627\u0644\u0637\u0644\u0628";
      dom.successMsg.textContent = "\u062a\u0645 \u0625\u0631\u0633\u0627\u0644 \u0637\u0644\u0628\u0643 \u0628\u0646\u062c\u0627\u062d \u0644\u0644\u0645\u0632\u0648\u062f.";
    }

    showToast("success", "\u062a\u0645 \u0627\u0644\u0625\u0631\u0633\u0627\u0644", "\u062a\u0645 \u0625\u0631\u0633\u0627\u0644 \u0637\u0644\u0628\u0643 \u0628\u0646\u062c\u0627\u062d \u2713");
  }

  function onSubmitError(res) {
    var data = res.data || {};
    var status = res.status;

    if (data.subcategory) showFieldError(dom.subcategory, dom.subError, arrayToStr(data.subcategory));
    if (data.subcategory_ids) showFieldError(dom.subcategory, dom.subError, arrayToStr(data.subcategory_ids));
    if (data.city) showFieldError(dom.city, dom.cityError, arrayToStr(data.city));
    if (data.title) showFieldError(dom.reqTitle, dom.titleError, arrayToStr(data.title));
    if (data.description) showFieldError(dom.desc, dom.descError, arrayToStr(data.description));
    if (data.quote_deadline) showFieldError(dom.deadline, dom.deadlineError, arrayToStr(data.quote_deadline));

    var detail = data.detail || data.non_field_errors || data.provider || data.request_lat || data.request_lng;
    if (detail) {
      showToast("error", "\u062e\u0637\u0623", arrayToStr(detail));
    } else if (status === 401) {
      showToast("warning", "\u062c\u0644\u0633\u0629 \u0645\u0646\u062a\u0647\u064a\u0629", "\u064a\u0631\u062c\u0649 \u062a\u0633\u062c\u064a\u0644 \u0627\u0644\u062f\u062e\u0648\u0644 \u0645\u0631\u0629 \u0623\u062e\u0631\u0649.");
    } else {
      showToast("error", "\u062e\u0637\u0623", "\u062d\u062f\u062b \u062e\u0637\u0623 \u0623\u062b\u0646\u0627\u0621 \u0625\u0631\u0633\u0627\u0644 \u0627\u0644\u0637\u0644\u0628. \u062d\u0627\u0648\u0644 \u0645\u0631\u0629 \u0623\u062e\u0631\u0649.");
    }
  }

  function arrayToStr(val) {
    if (Array.isArray(val)) return val.join(" ");
    return String(val || "");
  }

  /* ═══════════════════════════════════════
     Toast
     ═══════════════════════════════════════ */
  function showToast(type, title, message) {
    hideToast();
    dom.toast.className = "sr-toast " + type;
    dom.toastTitle.textContent = title;
    dom.toastMsg.textContent = message;

    var icons = { success: "\u2713", error: "\u2715", warning: "\u26a0", info: "\u2139" };
    dom.toastIcon.textContent = icons[type] || "\u2139";

    requestAnimationFrame(function () { dom.toast.classList.add("show"); });
    toastTimer = setTimeout(hideToast, 5000);
  }

  function hideToast() {
    if (toastTimer) { clearTimeout(toastTimer); toastTimer = null; }
    dom.toast.classList.remove("show");
  }

  /* ═══════════════════════════════════════
     Module export + init
     ═══════════════════════════════════════ */
  window.ServiceRequestForm = { init: init, _selectProviderFromMap: window._srSelectProvider };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
