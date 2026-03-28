"use strict";

var PromotionPage = (function () {
  var STATUS_LABELS = {
    "new": "جديد",
    "in_review": "قيد المراجعة",
    "quoted": "تم التسعير",
    "pending_payment": "بانتظار الدفع",
    "active": "مفعل",
    "completed": "مكتمل",
    "rejected": "مرفوض",
    "expired": "منتهي",
    "cancelled": "ملغي"
  };

  var INVOICE_STATUS_LABELS = {
    "draft": "مسودة",
    "pending": "بانتظار الدفع",
    "paid": "مدفوعة",
    "failed": "فشلت",
    "cancelled": "ملغاة",
    "refunded": "مسترجعة"
  };

  var OPS_LABELS = {
    "new": "جديد",
    "in_progress": "تحت المعالجة",
    "completed": "مكتمل"
  };

  var SERVICE_LABELS = {
    "home_banner": "بنر الصفحة الرئيسية",
    "featured_specialists": "شريط أبرز المختصين",
    "portfolio_showcase": "شريط البنرات والمشاريع",
    "snapshots": "شريط اللمحات",
    "search_results": "الظهور في قوائم البحث",
    "promo_messages": "الرسائل الدعائية",
    "sponsorship": "الرعاية"
  };

  var PRICING_SERVICE_ORDER = [
    "home_banner",
    "featured_specialists",
    "portfolio_showcase",
    "snapshots",
    "search_results",
    "promo_messages",
    "sponsorship"
  ];

  var PRICING_UNIT_LABELS = {
    "day": "لكل يوم",
    "campaign": "لكل حملة",
    "month": "لكل شهر"
  };

  var AD_TYPE_LABELS = {
    "bundle": "طلب ترويج متعدد الخدمات",
    "banner_home": "بنر الصفحة الرئيسية",
    "featured_top5": "شريط أبرز المختصين",
    "featured_top10": "شريط أبرز المختصين",
    "boost_profile": "شريط أبرز المختصين",
    "push_notification": "الرسائل الدعائية",
    "banner_category": "بنر صفحة القسم",
    "banner_search": "بنر صفحة البحث",
    "popup_home": "نافذة منبثقة رئيسية",
    "popup_category": "نافذة منبثقة داخل قسم"
  };

  var HOME_BANNER_REQUIRED_WIDTH = 1920;
  var HOME_BANNER_REQUIRED_HEIGHT = 840;
  var SERVICE_ALLOWED_EXTENSIONS = {
    home_banner: [".jpg", ".jpeg", ".png", ".mp4"],
    promo_messages: [".jpg", ".jpeg", ".png", ".mp4"],
    sponsorship: [".jpg", ".jpeg", ".png", ".mp4"]
  };

  var selectedServices = [];
  var requestsCache = {};
  var modalState = { resolve: null };
  var modalElements = null;
  var liveQuoteTimer = null;
  var liveQuoteData = null;
  var pendingSummary = { preview: null, requestBody: null };
  var pricingGuideState = { loaded: false, loading: false, payload: null };
  var pendingPayment = {
    requestId: null,
    requestCode: "",
    invoiceId: null,
    invoiceCode: "",
    invoiceTotal: 0,
    invoiceVat: 0,
    paymentMethod: "mada"
  };
  var homeBannerEditor = {
    activeDevice: "mobile",
    scales: { mobile: 100, tablet: 100, desktop: 100 },
    previewUrl: ""
  };

  function init() {
    bindTabs();
    bindModal();

    var hasRequestsPanel = !!document.getElementById("promo-list");
    var hasComposerForm = !!document.getElementById("promo-form");

    if (hasRequestsPanel) {
      bindRequestActions();
      bindTableRowClicks();
      loadRequests();
    }

    if (hasComposerForm) {
      bindPromoComposerViewToggle();
      bindPricingGuideActions();
      bindServicePicks();
      bindAttachmentPolicyHints();
      bindHomeBannerEditor();
      bindForm();
      bindLiveQuote();
      bindPreviewButtons();
      bindSummaryActions();
      bindPaymentActions();
      hydrateProviderIdentity();
      loadPricingGuide();
    }
  }

  function getMainShell() {
    return document.querySelector(".page-shell[data-promo-requests-url], .page-shell[data-promo-new-request-url]");
  }

  function getRequestsUrl() {
    var shell = getMainShell();
    return (shell && shell.dataset && shell.dataset.promoRequestsUrl) || "/promotion/";
  }

  function getNewRequestUrl() {
    var shell = getMainShell();
    return (shell && shell.dataset && shell.dataset.promoNewRequestUrl) || "/promotion/new/";
  }

  function goToRequestsPage() {
    window.location.href = getRequestsUrl();
  }

  function goToNewRequestPage() {
    window.location.href = getNewRequestUrl();
  }

  function bindAttachmentPolicyHints() {
    ["home_banner", "promo_messages", "sponsorship"].forEach(function (service) {
      var input = document.querySelector('[data-service-block="' + service + '"] [data-field="files"]');
      if (!input) return;

      var allowed = SERVICE_ALLOWED_EXTENSIONS[service] || [];
      if (allowed.length) {
        input.setAttribute("accept", allowed.join(","));
      }

      input.addEventListener("change", function () {
        var files = input.files ? Array.from(input.files) : [];
        var badFiles = files.filter(function (file) {
          return !isSupportedAttachmentForService(service, file);
        });
        if (!badFiles.length) return;

        input.value = "";
        if (service === "home_banner") {
          renderHomeBannerPreview(null);
        }
        alert(
          "الملف المرفق غير مدعوم.\\n"
          + "الملفات المدعومة: "
          + supportedExtensionsLabel(service)
        );
      });
    });
  }

  function bindTabs() {
    var tabs = document.getElementById("promo-tabs");
    if (!tabs) return;
    tabs.addEventListener("click", function (e) {
      var tab = e.target.closest(".tab");
      if (!tab) return;
      var name = tab.dataset.tab;
      if (name === "new") {
        goToNewRequestPage();
        return;
      }
      tabs.querySelectorAll(".tab").forEach(function (item) {
        item.classList.toggle("active", item === tab);
      });
      document.querySelectorAll(".tab-panel").forEach(function (panel) {
        panel.classList.toggle("active", panel.dataset.panel === name);
      });
    });
    var btnGoNew = document.getElementById("btn-go-new");
    if (btnGoNew) {
      btnGoNew.addEventListener("click", function () {
        goToNewRequestPage();
      });
    }
  }

  function bindPromoComposerViewToggle() {
    var buttons = Array.from(document.querySelectorAll("[data-promo-view]"));
    var composerView = document.getElementById("promo-composer-view");
    var pricingView = document.getElementById("promo-pricing-view");
    var summaryView = document.getElementById("promo-summary-view");
    var paymentView = document.getElementById("promo-payment-view");
    var topShell = document.querySelector(".promo-top-shell");
    if (!buttons.length || !composerView || !pricingView || !summaryView) return;

    buttons.forEach(function (button) {
      button.addEventListener("click", function () {
        switchComposerScreen(String(button.dataset.promoView || "composer"));
      });
    });

    function switchComposerScreen(view) {
      composerView.hidden = view !== "composer";
      pricingView.hidden = view !== "pricing";
      summaryView.hidden = view !== "summary";
      if (paymentView) paymentView.hidden = view !== "payment";
      if (topShell) topShell.hidden = view === "summary" || view === "payment";
      buttons.forEach(function (button) {
        button.classList.toggle("active", String(button.dataset.promoView) === view);
      });
      if (view === "pricing") {
        loadPricingGuide();
      }
    }

    window.__promoSwitchComposerScreen = switchComposerScreen;
    switchComposerScreen("composer");
  }

  function switchComposerScreen(view) {
    if (typeof window.__promoSwitchComposerScreen === "function") {
      window.__promoSwitchComposerScreen(view);
      return;
    }
    var composerView = document.getElementById("promo-composer-view");
    var pricingView = document.getElementById("promo-pricing-view");
    var summaryView = document.getElementById("promo-summary-view");
    var paymentView = document.getElementById("promo-payment-view");
    var topShell = document.querySelector(".promo-top-shell");
    if (!composerView || !pricingView || !summaryView) return;
    composerView.hidden = view !== "composer";
    pricingView.hidden = view !== "pricing";
    summaryView.hidden = view !== "summary";
    if (paymentView) paymentView.hidden = view !== "payment";
    if (topShell) topShell.hidden = view === "summary" || view === "payment";
    if (view === "pricing") {
      loadPricingGuide();
    }
  }

  function bindPricingGuideActions() {
    var pricingView = document.getElementById("promo-pricing-view");
    if (!pricingView || pricingView.dataset.bindPricingActions === "1") return;
    pricingView.dataset.bindPricingActions = "1";
    pricingView.addEventListener("click", function (event) {
      var reloadBtn = event.target.closest("[data-pricing-reload]");
      if (!reloadBtn) return;
      loadPricingGuide({ force: true });
    });
  }

  async function loadPricingGuide(options) {
    var force = !!(options && options.force);
    var loadingEl = document.getElementById("promo-pricing-loading");
    var errorEl = document.getElementById("promo-pricing-error");
    var metaEl = document.getElementById("promo-pricing-guide-meta");
    var gridEl = document.getElementById("promo-pricing-guide-grid");
    if (!loadingEl || !errorEl || !metaEl || !gridEl) return;

    if (pricingGuideState.loading) return;
    if (pricingGuideState.loaded && !force) return;

    pricingGuideState.loading = true;
    loadingEl.hidden = false;
    errorEl.hidden = true;
    metaEl.hidden = true;
    gridEl.hidden = true;

    try {
      var res = await ApiClient.get("/api/promo/pricing/guide/");
      if (!res.ok || !res.data || typeof res.data !== "object") {
        throw new Error("pricing_guide_load_failed");
      }

      pricingGuideState.payload = res.data;
      pricingGuideState.loaded = true;
      renderPricingGuide(res.data);

      loadingEl.hidden = true;
      errorEl.hidden = true;
      metaEl.hidden = false;
      gridEl.hidden = false;
    } catch (_) {
      pricingGuideState.loaded = false;
      errorEl.innerHTML = '<span>تعذر تحميل الأسعار الفعلية الآن.</span>'
        + '<button type="button" class="pricing-reload-btn" data-pricing-reload="1">إعادة المحاولة</button>';
      loadingEl.hidden = true;
      errorEl.hidden = false;
      metaEl.hidden = true;
      gridEl.hidden = true;
    } finally {
      pricingGuideState.loading = false;
    }
  }

  function renderPricingGuide(data) {
    var metaEl = document.getElementById("promo-pricing-guide-meta");
    var gridEl = document.getElementById("promo-pricing-guide-grid");
    if (!metaEl || !gridEl) return;

    var minHours = parseInt(String((data && data.min_campaign_hours) || "24"), 10);
    if (!Number.isFinite(minHours) || minHours <= 0) minHours = 24;

    var generatedAt = formatDateTime((data && data.generated_at) || "");
    var currencyLabel = String((data && data.currency_label) || "ريال سعودي").trim() || "ريال سعودي";
    metaEl.innerHTML =
      '<span class="pricing-meta-chip">المصدر: لوحة إدارة الترويج</span>'
      + '<span class="pricing-meta-chip">أقل مدة للحملة: ' + minHours + ' ساعة</span>'
      + '<span class="pricing-meta-chip">العملة: ' + escapeHtml(currencyLabel) + '</span>'
      + '<span class="pricing-meta-chip">آخر تحديث: ' + escapeHtml(generatedAt || "—") + '</span>';

    var services = Array.isArray(data && data.services) ? data.services : [];
    var byService = {};
    services.forEach(function (entry) {
      if (!entry || typeof entry !== "object") return;
      var serviceType = String(entry.service_type || "").trim();
      if (!serviceType) return;
      byService[serviceType] = entry;
    });

    var orderedServiceTypes = Array.isArray(data && data.service_order) && data.service_order.length
      ? data.service_order.map(function (item) { return String(item || "").trim(); })
      : PRICING_SERVICE_ORDER.slice();
    PRICING_SERVICE_ORDER.forEach(function (serviceType) {
      if (orderedServiceTypes.indexOf(serviceType) < 0) {
        orderedServiceTypes.push(serviceType);
      }
    });

    gridEl.innerHTML = orderedServiceTypes.map(function (serviceType) {
      var serviceEntry = byService[serviceType] || { service_type: serviceType, service_label: SERVICE_LABELS[serviceType] || serviceType, rules: [] };
      return renderPricingServiceCard(serviceEntry, minHours);
    }).join("");
  }

  function renderPricingServiceCard(serviceEntry, minHours) {
    var serviceType = String((serviceEntry && serviceEntry.service_type) || "").trim();
    var serviceLabel = String((serviceEntry && serviceEntry.service_label) || SERVICE_LABELS[serviceType] || serviceType).trim();
    var rules = Array.isArray(serviceEntry && serviceEntry.rules) ? serviceEntry.rules : [];
    var hints = pricingServiceHints(serviceType, minHours);
    var hintsHtml = hints.map(function (hint) {
      return "<li>" + escapeHtml(hint) + "</li>";
    }).join("");

    var tableHtml = "";
    if (!rules.length) {
      tableHtml = '<p class="pricing-empty">لا توجد قواعد تسعير مفعلة لهذا البند حاليًا.</p>';
    } else {
      tableHtml = '<div class="pricing-table-wrap"><table class="pricing-table"><thead><tr>'
        + '<th>التفصيل</th><th>التكلفة</th><th>وحدة الاحتساب</th>'
        + '</tr></thead><tbody>'
        + rules.map(function (rule) {
          var rowLabel = resolvePricingRuleLabel(rule);
          var amount = moneyHuman((rule && rule.amount) || 0);
          var unitLabel = resolvePricingRuleUnitLabel(rule);
          return '<tr>'
            + '<td>' + escapeHtml(rowLabel || "—") + '</td>'
            + '<td><span class="pricing-price-value">' + escapeHtml(amount) + ' ريال</span></td>'
            + '<td>' + escapeHtml(unitLabel || "—") + '</td>'
            + '</tr>';
        }).join("")
        + '</tbody></table></div>';
    }

    return '<article class="pricing-card">'
      + '<div class="pricing-card-head">'
      + '<h4>' + escapeHtml(serviceLabel || "—") + '</h4>'
      + '<span class="pricing-rule-count">عدد قواعد التسعير: ' + rules.length + '</span>'
      + '</div>'
      + '<ul class="pricing-hints">' + hintsHtml + '</ul>'
      + tableHtml
      + '</article>';
  }

  function pricingServiceHints(serviceType, minHours) {
    if (serviceType === "home_banner") {
      return [
        "أقل مدة للحملة " + minHours + " ساعة.",
        "يتم احتساب التكلفة لكل 24 ساعة."
      ];
    }
    if (serviceType === "featured_specialists" || serviceType === "portfolio_showcase" || serviceType === "snapshots") {
      return [
        "أقل مدة للحملة " + minHours + " ساعة.",
        "التكلفة اليومية تعتمد على معدل الظهور المختار."
      ];
    }
    if (serviceType === "search_results") {
      return [
        "أقل مدة للحملة " + minHours + " ساعة.",
        "التكلفة اليومية تعتمد على ترتيب الظهور في النتائج."
      ];
    }
    if (serviceType === "promo_messages") {
      return [
        "يتم التسعير لكل حملة بحسب قناة الإرسال.",
        "يمكن اختيار التنبيهات أو المحادثات أو كلاهما."
      ];
    }
    if (serviceType === "sponsorship") {
      return [
        "يتم التسعير لكل شهر رعاية.",
        "يتم تحديد المحتوى وجدول الإظهار أثناء إعداد الطلب."
      ];
    }
    return ["الأسعار معتمدة مباشرة من لوحة إدارة الترويج."];
  }

  function resolvePricingRuleLabel(rule) {
    if (!rule || typeof rule !== "object") return "";
    var displayKey = String(rule.display_key || "").trim();
    if (displayKey) return displayKey;
    var frequencyLabel = String(rule.frequency_label || "").trim();
    if (frequencyLabel) return frequencyLabel;
    var positionLabel = String(rule.search_position_label || "").trim();
    if (positionLabel) return positionLabel;
    var channelLabel = String(rule.message_channel_label || "").trim();
    if (channelLabel) return channelLabel;
    return String(rule.title || rule.code || "").trim();
  }

  function resolvePricingRuleUnitLabel(rule) {
    if (!rule || typeof rule !== "object") return "";
    var fromApi = String(rule.unit_label || "").trim();
    if (fromApi) return fromApi;
    var unit = String(rule.unit || "").trim();
    if (!unit) return "";
    return PRICING_UNIT_LABELS[unit] || unit;
  }

  function moneyHuman(value) {
    var parsed = Number(value);
    if (!Number.isFinite(parsed)) return "0.00";
    return parsed.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  }

  function firstNonEmptyText(values) {
    for (var index = 0; index < values.length; index += 1) {
      var value = String(values[index] == null ? "" : values[index]).trim();
      if (value) return value;
    }
    return "";
  }

  function resolveProviderDisplayName(profile, fallback) {
    var safeProfile = profile && typeof profile === "object" ? profile : {};
    var nestedUser = safeProfile.user && typeof safeProfile.user === "object" ? safeProfile.user : {};
    var nestedProvider = safeProfile.provider && typeof safeProfile.provider === "object"
      ? safeProfile.provider
      : (safeProfile.provider_profile && typeof safeProfile.provider_profile === "object" ? safeProfile.provider_profile : {});

    var firstName = firstNonEmptyText([safeProfile.first_name, nestedUser.first_name]);
    var lastName = firstNonEmptyText([safeProfile.last_name, nestedUser.last_name]);
    var fullName = [firstName, lastName].filter(Boolean).join(" ").trim();
    var username = firstNonEmptyText([safeProfile.username, nestedUser.username]);
    if (username && username.charAt(0) !== "@") {
      username = "@" + username;
    }

    return firstNonEmptyText([
      safeProfile.display_name,
      safeProfile.provider_display_name,
      safeProfile.full_name,
      safeProfile.provider_name,
      nestedProvider.display_name,
      nestedProvider.provider_display_name,
      nestedProvider.business_name,
      nestedUser.display_name,
      nestedUser.full_name,
      fullName,
      username,
      safeProfile.phone,
      nestedUser.phone,
      fallback
    ]);
  }

  function applyProviderIdentityName(chosen, fallback) {
    var input = document.getElementById("promo-provider-name");
    var display = document.getElementById("promo-provider-display");
    if (!input && !display) return;

    var finalName = firstNonEmptyText([chosen, fallback]);
    if (input) {
      input.value = finalName;
      input.title = finalName;
    }
    if (display) {
      display.textContent = finalName;
      display.title = finalName;
    }
  }

  async function fetchProviderIdentityCandidates() {
    var candidates = [];
    try {
      if (window.Auth && typeof window.Auth.getProfile === "function") {
        var profile = await window.Auth.getProfile();
        if (profile && typeof profile === "object") {
          candidates.push(profile);
          if (profile.provider && typeof profile.provider === "object") {
            candidates.push(profile.provider);
          }
          if (profile.provider_profile && typeof profile.provider_profile === "object") {
            candidates.push(profile.provider_profile);
          }
        }
      }
    } catch (_) {}

    try {
      if (window.ApiClient && typeof window.ApiClient.get === "function") {
        var providerRes = await window.ApiClient.get("/api/providers/me/profile/");
        if (providerRes && providerRes.ok && providerRes.data && typeof providerRes.data === "object") {
          candidates.push(providerRes.data);
          if (providerRes.data.user && typeof providerRes.data.user === "object") {
            candidates.push(providerRes.data.user);
          }
        }

        var meProviderRes = await window.ApiClient.get("/api/accounts/me/?mode=provider");
        if (meProviderRes && meProviderRes.ok && meProviderRes.data && typeof meProviderRes.data === "object") {
          candidates.push(meProviderRes.data);
        }

        var meRes = await window.ApiClient.get("/api/accounts/me/");
        if (meRes && meRes.ok && meRes.data && typeof meRes.data === "object") {
          candidates.push(meRes.data);
        }
      }
    } catch (_) {}

    return candidates;
  }

  async function hydrateProviderIdentity() {
    var fallback = "مزود الخدمة";
    applyProviderIdentityName("", fallback);

    var attemptsLeft = 4;
    while (attemptsLeft > 0) {
      var candidates = await fetchProviderIdentityCandidates();
      var chosen = "";
      candidates.some(function (candidate) {
        chosen = resolveProviderDisplayName(candidate, "");
        return !!chosen;
      });

      if (chosen) {
        applyProviderIdentityName(chosen, fallback);
        return;
      }

      attemptsLeft -= 1;
      if (attemptsLeft <= 0) break;
      await new Promise(function (resolve) { setTimeout(resolve, 250); });
    }

    applyProviderIdentityName("", fallback);
  }

  function bindServicePicks() {
    var toggles = Array.from(document.querySelectorAll("[data-service-toggle]"));
    if (!toggles.length) return;
    toggles.forEach(function (input) {
      var service = String(input.dataset.serviceToggle || "").trim();
      if (!service) return;
      input.addEventListener("change", function () {
        if (input.checked) {
          if (selectedServices.indexOf(service) < 0) {
            selectedServices.push(service);
          }
          toggleServiceBlock(service, true);
        } else {
          selectedServices = selectedServices.filter(function (item) {
            return item !== service;
          });
          toggleServiceBlock(service, false);
        }
        scheduleLiveQuote();
      });
    });

    selectedServices = [];
    toggles.forEach(function (input) {
      var service = String(input.dataset.serviceToggle || "").trim();
      if (!service) return;
      if (input.checked && selectedServices.indexOf(service) < 0) {
        selectedServices.push(service);
      }
      toggleServiceBlock(service, !!input.checked);
    });
  }

  function bindHomeBannerEditor() {
    var filesInput = document.querySelector('[data-service-block="home_banner"] [data-field="files"]');
    var tabsRoot = document.getElementById("home-banner-device-tabs");
    var scaleRange = document.getElementById("home-banner-scale-range");
    if (!filesInput || !tabsRoot || !scaleRange) return;

    // Keep picker aligned with backend-allowed extensions for home banner.
    filesInput.setAttribute("accept", ".jpg,.jpeg,.png,.mp4");

    filesInput.addEventListener("change", function () {
      var file = filesInput.files && filesInput.files[0] ? filesInput.files[0] : null;
      renderHomeBannerPreview(file);
    });

    tabsRoot.addEventListener("click", function (e) {
      var tab = e.target.closest(".banner-device-tab");
      if (!tab) return;
      homeBannerEditor.activeDevice = String(tab.dataset.device || "mobile");
      updateHomeBannerScaleUi();
    });

    scaleRange.addEventListener("input", function () {
      var limits = scaleLimitsForDevice(homeBannerEditor.activeDevice);
      var value = clampScale(scaleRange.value, limits.min, limits.max);
      homeBannerEditor.scales[homeBannerEditor.activeDevice] = value;
      updateHomeBannerScaleUi();
    });

    updateHomeBannerScaleUi();
  }

  function renderHomeBannerPreview(file) {
    var editor = document.getElementById("home-banner-editor");
    var wrap = document.getElementById("home-banner-preview-media-wrap");
    var empty = document.getElementById("home-banner-preview-empty");
    var dims = document.getElementById("home-banner-dims");
    var note = document.getElementById("home-banner-editor-note");
    if (!editor || !wrap || !empty || !dims || !note) return;

    if (homeBannerEditor.previewUrl) {
      try { URL.revokeObjectURL(homeBannerEditor.previewUrl); } catch (e) {}
      homeBannerEditor.previewUrl = "";
    }
    wrap.innerHTML = "";

    if (!file) {
      editor.hidden = true;
      empty.hidden = false;
      dims.textContent = "لم يتم اختيار ملف بعد";
      return;
    }

    editor.hidden = false;
    empty.hidden = true;

    var assetType = detectAssetType(String(file.name || ""));
    dims.textContent = "جاري تحميل المعاينة...";

    if (assetType !== "image" && assetType !== "video") {
      empty.hidden = false;
      dims.textContent = "نوع الملف غير مدعوم للمعاينة";
      note.textContent = "الأنواع المدعومة لبنر الصفحة الرئيسية: صور أو فيديو MP4 فقط.";
      return;
    }

    if (assetType === "video" && !isMp4File(file)) {
      empty.hidden = false;
      dims.textContent = "الفيديو يجب أن يكون بصيغة MP4";
      note.textContent = "يرجى اختيار فيديو MP4 ليعمل معاينة البنر والرفع بشكل صحيح.";
      return;
    }

    homeBannerEditor.previewUrl = URL.createObjectURL(file);

    if (assetType === "video") {
      var video = document.createElement("video");
      video.className = "banner-preview-media";
      video.src = homeBannerEditor.previewUrl;
      video.controls = true;
      video.muted = true;
      video.loop = true;
      video.playsInline = true;
      video.onloadedmetadata = function () {
        dims.textContent = "الأبعاد: " + video.videoWidth + "x" + video.videoHeight + " • فيديو";
      };
      video.onerror = function () {
        dims.textContent = "تعذر معاينة الفيديو المختار";
      };
      wrap.appendChild(video);
      note.textContent = "الفيديو لا تتم إعادة ترميزه في المتصفح. يجب أن يكون MP4 بالأبعاد المعتمدة.";
      updateHomeBannerScaleUi();
      return;
    }

    var img = document.createElement("img");
    img.className = "banner-preview-media";
    img.alt = "معاينة البنر";
    img.src = homeBannerEditor.previewUrl;
    img.onload = function () {
      dims.textContent = "الأبعاد: " + img.naturalWidth + "x" + img.naturalHeight + " • صورة";
    };
    img.onerror = function () {
      dims.textContent = "تعذر معاينة الصورة المختارة";
    };
    wrap.appendChild(img);
    note.textContent = "يمكن ضبط الصورة تلقائياً إلى 1920x840 قبل الرفع عند تفعيل الخيار أدناه.";
    updateHomeBannerScaleUi();
  }

  function scaleLimitsForDevice(device) {
    if (device === "mobile") return { min: 40, max: 140 };
    if (device === "tablet") return { min: 40, max: 150 };
    return { min: 40, max: 160 };
  }

  function clampScale(value, min, max) {
    var parsed = parseInt(String(value || ""), 10);
    if (!Number.isFinite(parsed)) return min;
    if (parsed < min) return min;
    if (parsed > max) return max;
    return parsed;
  }

  function updateHomeBannerScaleUi() {
    var tabsRoot = document.getElementById("home-banner-device-tabs");
    var scaleRange = document.getElementById("home-banner-scale-range");
    var valueEl = document.getElementById("home-banner-scale-value");
    var stage = document.getElementById("home-banner-preview-stage");
    if (!tabsRoot || !scaleRange || !valueEl || !stage) return;

    tabsRoot.querySelectorAll(".banner-device-tab").forEach(function (tab) {
      var isActive = String(tab.dataset.device || "") === homeBannerEditor.activeDevice;
      tab.classList.toggle("active", isActive);
    });

    var limits = scaleLimitsForDevice(homeBannerEditor.activeDevice);
    var value = clampScale(homeBannerEditor.scales[homeBannerEditor.activeDevice], limits.min, limits.max);
    homeBannerEditor.scales[homeBannerEditor.activeDevice] = value;
    scaleRange.min = String(limits.min);
    scaleRange.max = String(limits.max);
    scaleRange.value = String(value);
    valueEl.textContent = value + "%";
    stage.style.setProperty("--hb-preview-scale", String(value / 100));
  }

  function homeBannerAutoFitEnabled() {
    var checkbox = document.getElementById("home-banner-auto-fit");
    return !!(checkbox && checkbox.checked);
  }

  function collectHomeBannerScalePayload() {
    if (selectedServices.indexOf("home_banner") < 0) return {};
    return {
      mobile_scale: clampScale(homeBannerEditor.scales.mobile, 40, 140),
      tablet_scale: clampScale(homeBannerEditor.scales.tablet, 40, 150),
      desktop_scale: clampScale(homeBannerEditor.scales.desktop, 40, 160)
    };
  }

  async function normalizeHomeBannerImage(file) {
    return new Promise(function (resolve, reject) {
      var imageUrl = URL.createObjectURL(file);
      var img = new Image();
      img.onload = function () {
        try {
          var canvas = document.createElement("canvas");
          canvas.width = HOME_BANNER_REQUIRED_WIDTH;
          canvas.height = HOME_BANNER_REQUIRED_HEIGHT;
          var ctx = canvas.getContext("2d");
          if (!ctx) throw new Error("canvas-context-unavailable");

          ctx.fillStyle = "#0f172a";
          ctx.fillRect(0, 0, canvas.width, canvas.height);

          var scale = Math.min(canvas.width / img.naturalWidth, canvas.height / img.naturalHeight);
          var drawWidth = img.naturalWidth * scale;
          var drawHeight = img.naturalHeight * scale;
          var offsetX = (canvas.width - drawWidth) / 2;
          var offsetY = (canvas.height - drawHeight) / 2;
          ctx.imageSmoothingEnabled = true;
          ctx.imageSmoothingQuality = "high";
          ctx.drawImage(img, offsetX, offsetY, drawWidth, drawHeight);

          canvas.toBlob(function (blob) {
            try { URL.revokeObjectURL(imageUrl); } catch (e) {}
            if (!blob) {
              reject(new Error("image-export-failed"));
              return;
            }
            var baseName = String(file.name || "banner").replace(/\.[^/.]+$/, "");
            var outputName = baseName + "-banner.jpg";
            resolve(new File([blob], outputName, { type: "image/jpeg", lastModified: Date.now() }));
          }, "image/jpeg", 0.92);
        } catch (err) {
          try { URL.revokeObjectURL(imageUrl); } catch (e) {}
          reject(err);
        }
      };
      img.onerror = function () {
        try { URL.revokeObjectURL(imageUrl); } catch (e) {}
        reject(new Error("image-load-failed"));
      };
      img.src = imageUrl;
    });
  }

  function bindRequestActions() {
    var listRoot = document.getElementById("promo-list");
    if (!listRoot) return;
    listRoot.addEventListener("click", async function (e) {
      var button = e.target.closest("[data-request-action]");
      if (!button) return;
      var requestId = parseInt(button.dataset.requestId || "0", 10);
      if (!requestId || !requestsCache[requestId]) return;
      var request = requestsCache[requestId];
      var action = button.dataset.requestAction;
      if (action === "pay") {
        await startPayment(request);
        return;
      }
      await showRequestDetails(request);
    });
  }

  function bindModal() {
    modalElements = {
      root: document.getElementById("promo-modal"),
      title: document.getElementById("promo-modal-title"),
      body: document.getElementById("promo-modal-body"),
      cancel: document.getElementById("promo-modal-cancel"),
      confirm: document.getElementById("promo-modal-confirm")
    };
    if (!modalElements.root || !modalElements.title || !modalElements.body || !modalElements.cancel || !modalElements.confirm) {
      modalElements = null;
      return;
    }
    modalElements.root.addEventListener("click", function (e) {
      if (e.target && e.target.dataset && e.target.dataset.closeModal === "1") {
        closeModal(false);
      }
    });
    modalElements.cancel.addEventListener("click", function () {
      closeModal(false);
    });
    modalElements.confirm.addEventListener("click", function () {
      closeModal(true);
    });
  }

  function openModal(options) {
    if (!modalElements) bindModal();
    if (!modalElements) {
      if (options && options.confirmText === null) {
        alert(options.title || "تفاصيل الترويج");
        return Promise.resolve(false);
      }
      return Promise.resolve(window.confirm(options && options.title ? options.title : "متابعة"));
    }
    if (modalState.resolve) closeModal(false);
    modalElements.title.textContent = options.title || "تفاصيل الترويج";
    modalElements.body.innerHTML = options.bodyHtml || "";
    modalElements.cancel.textContent = options.cancelText || "إلغاء";
    if (options.confirmText === null) {
      modalElements.confirm.hidden = true;
    } else {
      modalElements.confirm.hidden = false;
      modalElements.confirm.textContent = options.confirmText || "متابعة";
    }
    modalElements.root.hidden = false;
    document.body.style.overflow = "hidden";
    return new Promise(function (resolve) {
      modalState.resolve = resolve;
    });
  }

  function closeModal(result) {
    if (!modalElements || modalElements.root.hidden) {
      if (modalState.resolve) {
        var pendingResolve = modalState.resolve;
        modalState.resolve = null;
        pendingResolve(Boolean(result));
      }
      return;
    }
    modalElements.root.hidden = true;
    document.body.style.overflow = "";
    if (modalState.resolve) {
      var resolve = modalState.resolve;
      modalState.resolve = null;
      resolve(Boolean(result));
    }
  }

  function toggleServiceBlock(service, show) {
    var block = document.querySelector('[data-service-block="' + service + '"]');
    if (!block) return;

    block.classList.toggle("is-active", !!show);
    var body = block.querySelector(".service-body");
    if (body) {
      body.hidden = !show;
    } else {
      block.hidden = !show;
    }

    var previewBtn = block.querySelector(".btn-preview-service");
    if (previewBtn) {
      previewBtn.hidden = !show;
    }
  }

  async function loadRequests() {
    var loading = document.getElementById("promo-loading");
    var empty = document.getElementById("promo-empty");
    var listEl = document.getElementById("promo-list");
    if (!loading || !empty || !listEl) return;
    loading.style.display = "";
    empty.style.display = "none";
    listEl.innerHTML = "";
    requestsCache = {};

    try {
      var res = await ApiClient.get("/api/promo/requests/my/");
      loading.style.display = "none";
      if (!res.ok) {
        listEl.innerHTML = '<p class="text-muted">تعذر تحميل الطلبات</p>';
        return;
      }
      var rows = Array.isArray(res.data) ? res.data : ((res.data && res.data.results) || []);
      if (!rows.length) {
        empty.style.display = "";
        return;
      }
      rows.forEach(function (row) {
        if (row && row.id) requestsCache[row.id] = row;
      });
      listEl.innerHTML = renderRequestsTable(rows);
    } catch (err) {
      loading.style.display = "none";
      listEl.innerHTML = '<p class="text-muted">تعذر تحميل الطلبات</p>';
    }
  }

  function renderRequestsTable(rows) {
    var html = '<div class="promo-requests-head">' +
      '<h3>قائمة طلبات الترويج</h3>' +
      '<span class="dot"></span>' +
      '</div>' +
      '<div class="promo-requests-table-wrap">' +
      '<table class="promo-requests-table">' +
      '<thead><tr>' +
        '<th>رقم الطلب</th>' +
        '<th>نوع الطلب</th>' +
        '<th>تاريخ ووقت اعتماد الطلب</th>' +
        '<th>حالة الطلب</th>' +
      '</tr></thead><tbody>';

    rows.forEach(function (row) {
      html += renderRequestRow(row);
    });

    html += '</tbody></table></div>';
    return html;
  }

  function renderRequestRow(row) {
    var code = escapeHtml(row.code || "");
    var requestType = escapeHtml(resolveRequestTypeLabel(row));
    var approvedAt = formatDateTime(
      row.reviewed_at
      || row.activated_at
      || row.quoted_at
      || row.created_at
      || ""
    );
    var status = escapeHtml(STATUS_LABELS[row.status] || row.status || "");

    return '<tr data-request-id="' + row.id + '">' +
      '<td style="color:#663d90;font-weight:600">' + code + '</td>' +
      '<td>' + (requestType || "—") + '</td>' +
      '<td>' + approvedAt + '</td>' +
      '<td>' + status + '</td>' +
      '</tr>';
  }

  function resolveRequestTypeLabel(row) {
    var items = Array.isArray(row && row.items) ? row.items : [];
    var labels = [];

    items.forEach(function (item) {
      if (!item || typeof item !== "object") return;
      var serviceType = String(item.service_type || "").trim();
      var label = String(item.service_type_label || "").trim();
      if (!label && serviceType) {
        label = SERVICE_LABELS[serviceType] || serviceType;
      }
      if (label && labels.indexOf(label) < 0) {
        labels.push(label);
      }
    });

    if (labels.length) {
      return labels.join(" + ");
    }

    var adType = String((row && row.ad_type) || "").trim();
    if (adType) {
      return AD_TYPE_LABELS[adType] || adType;
    }

    return String((row && row.title) || "").trim() || "—";
  }

  function formatDateTime(isoStr) {
    if (!isoStr) return "—";
    try {
      var d = new Date(isoStr);
      if (isNaN(d.getTime())) return "—";
      var dd = String(d.getDate()).padStart(2, "0");
      var mm = String(d.getMonth() + 1).padStart(2, "0");
      var yy = d.getFullYear();
      var hh = String(d.getHours()).padStart(2, "0");
      var mi = String(d.getMinutes()).padStart(2, "0");
      return dd + "/" + mm + "/" + yy + " – " + hh + ":" + mi;
    } catch (e) {
      return "—";
    }
  }

  function bindTableRowClicks() {
    var listEl = document.getElementById("promo-list");
    if (!listEl || listEl.dataset.rowClicksBound === "1") return;
    listEl.dataset.rowClicksBound = "1";
    listEl.addEventListener("click", async function (e) {
      var tr = e.target.closest("tr[data-request-id]");
      if (!tr) return;
      var requestId = parseInt(tr.dataset.requestId || "0", 10);
      if (!requestId || !requestsCache[requestId]) return;
      var request = requestsCache[requestId];
      await showRequestDetails(request);
    });
  }

  function canPayRequest(row) {
    var invoiceId = parseInt(String((row && row.invoice) || ""), 10);
    var status = String((row && row.status) || "").trim();
    return !!invoiceId && row && row.payment_effective !== true && (status === "pending_payment" || status === "quoted");
  }

  async function showRequestDetails(row) {
    var detailRow = row;
    try {
      var res = await ApiClient.get("/api/promo/requests/" + row.id + "/");
      if (res && res.ok && res.data && res.data.id) detailRow = res.data;
    } catch (_) {}
    var confirmed = await openModal({
      title: detailRow.title || "طلب ترويج",
      bodyHtml: buildRequestDetailsHtml(detailRow),
      confirmText: canPayRequest(detailRow) ? "الدفع الآن" : null,
      cancelText: "إغلاق"
    });
    if (confirmed && canPayRequest(detailRow)) {
      await startPayment(detailRow);
    }
  }

  function buildRequestDetailsHtml(row) {
    var items = Array.isArray(row.items) ? row.items : [];
    var assets = Array.isArray(row.assets) ? row.assets : [];
    var parts = [
      '<div class="promo-modal-section">',
      lineHtml("رقم الطلب", row.code || ""),
      lineHtml("الحالة", STATUS_LABELS[row.status] || row.status || ""),
      lineHtml("التنفيذ", OPS_LABELS[row.ops_status] || row.ops_status || ""),
      row.start_at ? lineHtml("بداية الحملة", formatDateTime(row.start_at)) : "",
      row.end_at ? lineHtml("نهاية الحملة", formatDateTime(row.end_at)) : "",
      row.invoice_code ? lineHtml("رقم الفاتورة", row.invoice_code) : "",
      row.invoice_status ? lineHtml("حالة الفاتورة", row.payment_effective === true ? "مدفوعة" : (INVOICE_STATUS_LABELS[row.invoice_status] || row.invoice_status)) : "",
      row.invoice_total != null ? lineHtml("الإجمالي", money(row.invoice_total) + " ريال") : "",
      row.invoice_vat != null ? lineHtml("VAT", money(row.invoice_vat) + " ريال") : "",
      row.quote_note ? lineHtml("ملاحظة الاعتماد", row.quote_note) : "",
      row.reject_reason ? lineHtml("سبب الرفض", row.reject_reason) : "",
      '</div>'
    ];

    if (String(row.status || "") === "rejected") {
      parts.push(buildRejectedRequestGuidanceHtml(row));
    }

    if (items.length) {
      parts.push('<div class="promo-modal-section"><h4 style="margin-bottom:10px">تفاصيل الخدمات</h4>');
      items.forEach(function (item) {
        var itemAssets = assets.filter(function (a) { return a.item === item.id; });
        parts.push(buildItemDetailHtml(item, itemAssets));
      });
      parts.push('</div>');
    }

    var unlinkedAssets = assets.filter(function (a) { return !a.item; });
    if (unlinkedAssets.length) {
      parts.push('<div class="promo-modal-section"><h4 style="margin-bottom:8px">مرفقات عامة</h4>');
      unlinkedAssets.forEach(function (a) {
        parts.push(buildAssetRowHtml(a));
      });
      parts.push('</div>');
    }

    return parts.join("");
  }

  function buildItemDetailHtml(item, itemAssets) {
    var label = SERVICE_LABELS[item.service_type] || item.service_type || "";
    var h = '<div class="promo-modal-item" style="border:1px solid #e2e8f0;border-radius:8px;padding:12px;margin-bottom:10px">';
    h += '<div style="display:flex;gap:8px;flex-wrap:wrap;margin-bottom:8px">';
    h += '<span style="background:#663d90;color:#fff;padding:2px 10px;border-radius:12px;font-size:.85rem">' + escapeHtml(label) + '</span>';
    if (item.subtotal != null) h += '<span style="background:#e8f5e9;color:#2e7d32;padding:2px 10px;border-radius:12px;font-size:.85rem">' + money(item.subtotal) + ' ريال</span>';
    if (item.duration_days) h += '<span style="background:#e3f2fd;color:#1565c0;padding:2px 10px;border-radius:12px;font-size:.85rem">' + item.duration_days + ' يوم</span>';
    h += '</div>';
    if (item.title) h += lineHtml("العنوان", item.title);
    if (item.start_at) h += lineHtml("بداية", formatDateTime(item.start_at));
    if (item.end_at) h += lineHtml("نهاية", formatDateTime(item.end_at));
    if (item.frequency_label) h += lineHtml("معدل الظهور", item.frequency_label);
    if (item.search_scope_label) h += lineHtml("نطاق البحث", item.search_scope_label);
    if (item.search_position_label) h += lineHtml("ترتيب الظهور", item.search_position_label);
    if (item.target_category) h += lineHtml("التصنيف", item.target_category);
    if (item.target_city) h += lineHtml("المدينة", item.target_city);
    if (item.send_at) h += lineHtml("وقت الإرسال", formatDateTime(item.send_at));
    if (item.redirect_url) h += lineHtml("رابط التحويل", '<a href="' + escapeHtml(item.redirect_url) + '" target="_blank" rel="noopener">' + escapeHtml(item.redirect_url) + '</a>');
    if (item.message_title) h += lineHtml("عنوان الرسالة", item.message_title);
    if (item.message_body) h += lineHtml("نص الرسالة", item.message_body);
    if (item.operator_note) h += lineHtml("تعليق المكلف", item.operator_note);
    if (item.use_notification_channel) h += '<span style="background:#e8f5e9;color:#2e7d32;padding:2px 8px;border-radius:10px;font-size:.8rem;margin-inline-end:4px">إشعار</span>';
    if (item.use_chat_channel) h += '<span style="background:#e3f2fd;color:#1565c0;padding:2px 8px;border-radius:10px;font-size:.8rem">محادثة</span>';
    if (item.sponsor_name) h += lineHtml("اسم الراعي", item.sponsor_name);
    if (item.sponsor_url) h += lineHtml("رابط الراعي", '<a href="' + escapeHtml(item.sponsor_url) + '" target="_blank" rel="noopener">' + escapeHtml(item.sponsor_url) + '</a>');
    if (item.sponsorship_months) h += lineHtml("مدة الرعاية", item.sponsorship_months + " شهر");
    if (itemAssets && itemAssets.length) {
      h += '<div style="margin-top:8px"><strong style="font-size:.9rem">المرفقات:</strong>';
      itemAssets.forEach(function (a) { h += buildAssetRowHtml(a); });
      h += '</div>';
    }
    h += '</div>';
    return h;
  }

  function buildAssetRowHtml(asset) {
    var typeLabel = {"image":"صورة","video":"فيديو","pdf":"PDF","audio":"صوت"}[asset.asset_type] || asset.asset_type || "ملف";
    var title = asset.title || "ملف مرفق";
    var url = asset.file || "";
    var h = '<div style="display:flex;align-items:center;gap:8px;padding:4px 0;border-bottom:1px dashed #e2e8f0;font-size:.88rem">';
    h += '<span>' + escapeHtml(typeLabel) + ' - ' + escapeHtml(title) + '</span>';
    if (url) {
      h += '<a href="' + escapeHtml(url) + '" target="_blank" rel="noopener" style="color:#663d90">عرض</a>';
      h += '<a href="' + escapeHtml(url) + '" download style="color:#2e7d32">تنزيل</a>';
    }
    h += '</div>';
    return h;
  }

  function buildRejectedRequestGuidanceHtml(row) {
    var reason = String((row && row.reject_reason) || "").trim();
    return (
      '<div class="promo-modal-section">'
      + '<div class="promo-modal-item" style="background:#fff4f4;border:1px solid #f3c7c7">'
      + '<strong style="color:#9f1239">الطلب مرفوض ويحتاج تعديل قبل إعادة الإرسال</strong>'
      + (reason
        ? '<div class="text-muted" style="margin-top:6px">سبب الرفض: ' + escapeHtml(reason) + '</div>'
        : '<div class="text-muted" style="margin-top:6px">لا يوجد سبب رفض مفصل. تواصل مع فريق إدارة الترويج.</div>')
      + '<div class="text-muted" style="margin-top:8px">خطوات الإجراء:</div>'
      + '<ol style="margin:6px 0 0;padding-inline-start:18px;color:#6b7280;line-height:1.8">'
      + '<li>عدّل المحتوى أو المرفقات حسب سبب الرفض.</li>'
      + '<li>تأكد من نوع الملف والمقاسات المطلوبة للخدمة.</li>'
      + '<li>أنشئ طلبًا جديدًا بالصيغة المصححة ثم أعد الإرسال.</li>'
      + '</ol>'
      + '</div>'
      + '</div>'
    );
  }

  function bindSummaryActions() {
    var cancelBtn = document.getElementById("promo-summary-cancel");
    var confirmBtn = document.getElementById("promo-summary-confirm");
    if (!cancelBtn || !confirmBtn) return;

    cancelBtn.addEventListener("click", function () {
      switchComposerScreen("composer");
    });

    confirmBtn.addEventListener("click", async function () {
      if (!pendingSummary.requestBody) {
        switchComposerScreen("composer");
        return;
      }
      if (pendingPayment.requestId && pendingPayment.invoiceId) {
        renderPaymentView();
        switchComposerScreen("payment");
        return;
      }
      var defaultText = confirmBtn.textContent || "استمرار";
      confirmBtn.disabled = true;
      cancelBtn.disabled = true;
      try {
        confirmBtn.textContent = "جاري تجهيز الدفع...";
        await submitRequestFlow(pendingSummary.requestBody, confirmBtn);
      } finally {
        confirmBtn.disabled = false;
        cancelBtn.disabled = false;
        confirmBtn.textContent = defaultText;
      }
    });
  }

  function bindPaymentActions() {
    var backBtn = document.getElementById("promo-payment-back");
    var payBtn = document.getElementById("promo-payment-submit");
    if (!backBtn || !payBtn) return;

    var numberInput = document.getElementById("promo-card-number");
    var expiryInput = document.getElementById("promo-card-expiry");
    var cvvInput = document.getElementById("promo-card-cvv");
    var methodInputs = Array.from(document.querySelectorAll('input[name="promo-payment-method"]'));

    if (numberInput) {
      numberInput.addEventListener("input", function () {
        var digits = normalizeCardDigits(numberInput.value).slice(0, 19);
        numberInput.value = formatCardNumberDisplay(digits);
      });
    }
    if (expiryInput) {
      expiryInput.addEventListener("input", function () {
        expiryInput.value = formatExpiryValue(expiryInput.value);
      });
    }
    if (cvvInput) {
      cvvInput.addEventListener("input", function () {
        cvvInput.value = normalizeCardDigits(cvvInput.value).slice(0, 4);
      });
    }

    methodInputs.forEach(function (input) {
      input.addEventListener("change", function () {
        if (input.checked) {
          pendingPayment.paymentMethod = String(input.value || "mada").trim() || "mada";
          updatePaymentMethodSelectionUi();
        }
      });
    });
    updatePaymentMethodSelectionUi();

    backBtn.addEventListener("click", function () {
      clearPaymentCardFields();
      switchComposerScreen("summary");
    });

    payBtn.addEventListener("click", async function () {
      if (!pendingPayment.invoiceId) {
        switchComposerScreen("summary");
        return;
      }
      var validation = validatePaymentFields();
      if (!validation.ok) {
        alert(validation.message || "يرجى استكمال بيانات البطاقة");
        return;
      }
      pendingPayment.paymentMethod = validation.method || pendingPayment.paymentMethod || "mada";
      updatePaymentMethodSelectionUi();

      var defaultText = payBtn.textContent || "دفع";
      payBtn.disabled = true;
      backBtn.disabled = true;
      try {
        payBtn.textContent = "جاري تنفيذ الدفع...";
        var paid = await payPreparedInvoice();
        if (!paid) return;
        var requestCode = pendingPayment.requestCode || "—";
        clearPaymentCardFields();
        resetForm();
        showSuccessDialog(requestCode, {
          title: "تمت عملية الدفع بنجاح",
          message: "سيتم التواصل معكم لتنفيذ طلبكم",
          onClose: goToRequestsPage
        });
      } finally {
        payBtn.disabled = false;
        backBtn.disabled = false;
        payBtn.textContent = defaultText;
      }
    });
  }

  function renderPaymentView() {
    var requestCodeEl = document.getElementById("promo-payment-request-code");
    var totalEl = document.getElementById("promo-payment-total");

    if (requestCodeEl) {
      requestCodeEl.textContent = pendingPayment.requestCode || "—";
    }
    var invoiceTotal = Number(pendingPayment.invoiceTotal);
    if (!Number.isFinite(invoiceTotal)) {
      invoiceTotal = Number(pendingSummary.preview && pendingSummary.preview.total);
    }
    if (totalEl) {
      totalEl.textContent = money(invoiceTotal) + " ريال";
    }

    var method = pendingPayment.paymentMethod || "mada";
    var selectedInput = document.querySelector('input[name="promo-payment-method"][value="' + method + '"]');
    if (selectedInput) selectedInput.checked = true;
    updatePaymentMethodSelectionUi();
  }

  function updatePaymentMethodSelectionUi() {
    document.querySelectorAll(".promo-payment-method-option").forEach(function (label) {
      var input = label.querySelector('input[name="promo-payment-method"]');
      label.classList.toggle("is-selected", !!(input && input.checked));
    });
  }

  function normalizeCardDigits(value) {
    return String(value || "").replace(/\D+/g, "");
  }

  function formatCardNumberDisplay(digits) {
    return String(digits || "").replace(/(.{4})/g, "$1 ").trim();
  }

  function formatExpiryValue(value) {
    var digits = normalizeCardDigits(value).slice(0, 4);
    if (digits.length <= 2) return digits;
    return digits.slice(0, 2) + "/" + digits.slice(2);
  }

  function luhnCheck(numberDigits) {
    var sum = 0;
    var alt = false;
    for (var i = numberDigits.length - 1; i >= 0; i -= 1) {
      var n = parseInt(numberDigits.charAt(i), 10);
      if (!Number.isFinite(n)) return false;
      if (alt) {
        n *= 2;
        if (n > 9) n -= 9;
      }
      sum += n;
      alt = !alt;
    }
    return sum % 10 === 0;
  }

  function validatePaymentFields() {
    var methodInput = document.querySelector('input[name="promo-payment-method"]:checked');
    var method = methodInput ? String(methodInput.value || "").trim() : "";
    if (!method) {
      return { ok: false, message: "اختر وسيلة الدفع أولاً." };
    }

    var cardName = valueOf(document.getElementById("promo-card-name"));
    if (cardName.length < 3) {
      return { ok: false, message: "أدخل اسم حامل البطاقة بشكل صحيح." };
    }

    var cardNumber = normalizeCardDigits(valueOf(document.getElementById("promo-card-number")));
    if (cardNumber.length < 12 || cardNumber.length > 19 || !luhnCheck(cardNumber)) {
      return { ok: false, message: "رقم البطاقة غير صالح." };
    }

    var expiryRaw = valueOf(document.getElementById("promo-card-expiry"));
    var expiryMatch = /^(\d{2})\/(\d{2})$/.exec(expiryRaw);
    if (!expiryMatch) {
      return { ok: false, message: "أدخل تاريخ الانتهاء بصيغة MM/YY." };
    }
    var expMonth = parseInt(expiryMatch[1], 10);
    var expYear = 2000 + parseInt(expiryMatch[2], 10);
    if (!Number.isFinite(expMonth) || expMonth < 1 || expMonth > 12) {
      return { ok: false, message: "شهر انتهاء البطاقة غير صحيح." };
    }
    var expiryDate = new Date(expYear, expMonth, 0, 23, 59, 59, 999);
    if (expiryDate.getTime() < Date.now()) {
      return { ok: false, message: "البطاقة منتهية الصلاحية." };
    }

    var cvv = normalizeCardDigits(valueOf(document.getElementById("promo-card-cvv")));
    if (cvv.length < 3 || cvv.length > 4) {
      return { ok: false, message: "رمز CVV غير صحيح." };
    }

    return { ok: true, method: method };
  }

  function clearPaymentCardFields() {
    var nameInput = document.getElementById("promo-card-name");
    var numberInput = document.getElementById("promo-card-number");
    var expiryInput = document.getElementById("promo-card-expiry");
    var cvvInput = document.getElementById("promo-card-cvv");
    if (nameInput) nameInput.value = "";
    if (numberInput) numberInput.value = "";
    if (expiryInput) expiryInput.value = "";
    if (cvvInput) cvvInput.value = "";
  }

  function renderSummaryView(preview) {
    var providerEl = document.getElementById("promo-summary-provider");
    var itemsEl = document.getElementById("promo-summary-items");
    var subtotalEl = document.getElementById("promo-summary-subtotal");
    var vatEl = document.getElementById("promo-summary-vat");
    var totalEl = document.getElementById("promo-summary-total");
    if (!providerEl || !itemsEl || !subtotalEl || !vatEl || !totalEl) return;

    var providerInput = document.getElementById("promo-provider-name");
    var providerName = valueOf(providerInput) || "مزود الخدمة";
    providerEl.textContent = providerName;

    var items = Array.isArray(preview && preview.items) ? preview.items : [];
    if (!items.length) {
      itemsEl.innerHTML = '<tr><td colspan="2">لا توجد بنود لعرضها</td></tr>';
    } else {
      itemsEl.innerHTML = items.map(function (item) {
        var title = escapeHtml(item.title || SERVICE_LABELS[item.service_type] || item.service_type || "خدمة");
        var price = money(item.subtotal) + " ريال";
        return "<tr><td>" + title + "</td><td>" + price + "</td></tr>";
      }).join("");
    }

    subtotalEl.textContent = money(preview && preview.subtotal) + " ريال";
    vatEl.textContent = money(preview && preview.vat_amount) + " ريال";
    totalEl.textContent = money(preview && preview.total) + " ريال";
  }

  function bindForm() {
    var form = document.getElementById("promo-form");
    if (!form) return;
    form.addEventListener("submit", async function (e) {
      e.preventDefault();
      if (!selectedServices.length) {
        alert("اختر خدمة واحدة على الأقل");
        return;
      }

      var title = valueOf(document.getElementById("promo-title"));
      if (!title) {
        alert("أدخل عنوان الطلب");
        return;
      }

      var mediaValidationError = await validateSelectedServiceFiles();
      if (mediaValidationError) {
        alert(mediaValidationError);
        return;
      }

      var items = [];
      for (var i = 0; i < selectedServices.length; i += 1) {
        var service = selectedServices[i];
        var block = document.querySelector('[data-service-block="' + service + '"]');
        var payload = buildServicePayload(service, block, i);
        if (typeof payload === "string") {
          alert(payload);
          return;
        }
        items.push(payload);
      }

      var button = document.getElementById("promo-submit");
      var defaultLabel = button ? button.textContent : "استمرار";
      button.disabled = true;
      try {
        button.textContent = "جاري احتساب التسعير...";
        pendingPayment.requestId = null;
        pendingPayment.requestCode = "";
        pendingPayment.invoiceId = null;
        pendingPayment.invoiceCode = "";
        pendingPayment.invoiceTotal = 0;
        pendingPayment.invoiceVat = 0;
        pendingPayment.paymentMethod = "mada";
        clearPaymentCardFields();
        var defaultPaymentMethod = document.querySelector('input[name="promo-payment-method"][value="mada"]');
        if (defaultPaymentMethod) defaultPaymentMethod.checked = true;
        updatePaymentMethodSelectionUi();
        var requestBody = Object.assign({ title: title, items: items }, collectHomeBannerScalePayload());

        var previewRes = await ApiClient.request("/api/promo/requests/preview/", {
          method: "POST",
          body: requestBody
        });
        if (!previewRes.ok) {
          alert(extractError(previewRes, "تعذر معاينة التسعير"));
          return;
        }

        pendingSummary.preview = previewRes.data || {};
        pendingSummary.requestBody = requestBody;
        renderSummaryView(pendingSummary.preview);
        switchComposerScreen("summary");
      } catch (err) {
        console.error("Promo submit failed", err);
        alert("تعذر إكمال عملية الترويج. حاول مرة أخرى.");
      } finally {
        button.disabled = false;
        button.textContent = defaultLabel;
      }
    });
  }

  async function submitRequestFlow(requestBody, submitButton) {
    if (!submitButton) return false;
    try {
      submitButton.textContent = "جاري إنشاء الطلب...";
      var createResult = await createRequestWithAssets(requestBody, submitButton);
      if (!createResult) {
        return false;
      }

      if (createResult.uploadFailures.length) {
        alert("تم إنشاء الطلب، لكن فشل رفع " + createResult.uploadFailures.length + " مرفق/مرفقات.\n" + createResult.uploadFailures[0]);
      }

      submitButton.textContent = "جاري تجهيز الفاتورة...";
      var prepared = await preparePromoRequestPayment(createResult.requestId);
      if (!prepared) {
        return false;
      }
      var invoiceId = parseInt(String(prepared.invoice || ""), 10);
      if (!invoiceId) {
        alert("تعذر تجهيز الفاتورة لهذا الطلب. حاول مرة أخرى.");
        return false;
      }

      pendingPayment.requestId = createResult.requestId;
      pendingPayment.requestCode = String(prepared.code || createResult.requestCode || "").trim();
      pendingPayment.invoiceId = invoiceId;
      pendingPayment.invoiceCode = String(prepared.invoice_code || "").trim();
      pendingPayment.invoiceTotal = Number(prepared.invoice_total != null ? prepared.invoice_total : (pendingSummary.preview && pendingSummary.preview.total));
      pendingPayment.invoiceVat = Number(prepared.invoice_vat != null ? prepared.invoice_vat : 0);
      pendingPayment.paymentMethod = pendingPayment.paymentMethod || "mada";
      renderPaymentView();
      switchComposerScreen("payment");
      return true;
    } catch (err) {
      console.error("Submit flow failed", err);
      alert("تعذر إكمال تجهيز الطلب للدفع. حاول مرة أخرى.");
      return false;
    }
  }

  async function createRequestWithAssets(requestBody, submitButton) {
    var createRes = await ApiClient.request("/api/promo/requests/create/", {
      method: "POST",
      body: requestBody
    });
    if (!createRes.ok) {
      alert(extractError(createRes, "فشل إنشاء الطلب"));
      return null;
    }

    var requestId = createRes.data && createRes.data.id;
    if (!requestId) {
      alert("تم إنشاء الطلب لكن تعذر قراءة معرف الطلب.");
      return null;
    }

    var detailRes = await ApiClient.get("/api/promo/requests/" + requestId + "/");
    var detailItems = detailRes && detailRes.ok && detailRes.data && Array.isArray(detailRes.data.items)
      ? detailRes.data.items : ((createRes.data && createRes.data.items) || []);
    var ids = {};
    detailItems.forEach(function (item) {
      if (item && item.id) ids[(item.service_type || "") + ":" + (item.sort_order || 0)] = item.id;
    });

    var uploadFailures = [];
    submitButton.textContent = "جاري رفع المرفقات...";
    for (var x = 0; x < selectedServices.length; x += 1) {
      var s = selectedServices[x];
      var sBlock = document.querySelector('[data-service-block="' + s + '"]');
      var fileInput = sBlock ? sBlock.querySelector('[data-field="files"]') : null;
      var files = fileInput && fileInput.files ? Array.from(fileInput.files) : [];
      for (var y = 0; y < files.length; y += 1) {
        var sourceFile = files[y];
        var uploadFile = sourceFile;
        var uploadType = detectAssetType(sourceFile.name);
        if (s === "home_banner" && uploadType === "image" && homeBannerAutoFitEnabled()) {
          try {
            uploadFile = await normalizeHomeBannerImage(sourceFile);
            uploadType = "image";
          } catch (normalizeErr) {
            uploadFailures.push((sourceFile.name || "ملف") + ": تعذر ضبط الصورة تلقائياً قبل الرفع.");
            continue;
          }
        }
        var fd = new FormData();
        fd.append("file", uploadFile, uploadFile.name);
        fd.append("asset_type", uploadType);
        if (ids[s + ":" + x]) fd.append("item_id", String(ids[s + ":" + x]));
        var uploadRes = await ApiClient.request("/api/promo/requests/" + requestId + "/assets/", {
          method: "POST",
          body: fd,
          formData: true
        });
        if (!uploadRes.ok) {
          uploadFailures.push((uploadFile.name || "ملف") + ": " + extractError(uploadRes, "تعذر رفع المرفق"));
        }
      }
    }

    var requestCode = (createRes.data && createRes.data.code) || "";
    var detailCode = detailRes && detailRes.ok && detailRes.data && detailRes.data.code;
    if (detailCode) requestCode = detailCode;

    return {
      requestId: requestId,
      requestCode: String(requestCode || "").trim(),
      uploadFailures: uploadFailures
    };
  }

  async function preparePromoRequestPayment(requestId) {
    var prepareRes = await ApiClient.request("/api/promo/requests/" + requestId + "/prepare-payment/", {
      method: "POST",
      body: {}
    });
    if (!prepareRes.ok) {
      alert(extractError(prepareRes, "تعذر تجهيز الفاتورة"));
      return null;
    }
    return prepareRes.data || {};
  }

  async function payPreparedInvoice() {
    var invoiceId = parseInt(String(pendingPayment.invoiceId || ""), 10);
    if (!invoiceId) {
      alert("لا توجد فاتورة صالحة لإتمام الدفع.");
      return false;
    }
    var requestId = parseInt(String(pendingPayment.requestId || ""), 10) || 0;
    var idempotencyKey = "promo-checkout-" + requestId + "-" + invoiceId;
    var initRes = await ApiClient.request("/api/billing/invoices/" + invoiceId + "/init-payment/", {
      method: "POST",
      body: { provider: "mock", idempotency_key: idempotencyKey }
    });
    if (!initRes.ok) {
      alert(extractError(initRes, "تعذر فتح صفحة الدفع"));
      return false;
    }
    var payRes = await ApiClient.request("/api/billing/invoices/" + invoiceId + "/complete-mock-payment/", {
      method: "POST",
      body: { idempotency_key: idempotencyKey }
    });
    if (!payRes.ok) {
      alert(extractError(payRes, "تعذر إتمام الدفع"));
      return false;
    }
    return true;
  }

  async function validateSelectedServiceFiles() {
    for (var i = 0; i < selectedServices.length; i += 1) {
      var service = selectedServices[i];
      var block = document.querySelector('[data-service-block="' + service + '"]');
      var input = block ? block.querySelector('[data-field="files"]') : null;
      var files = input && input.files ? Array.from(input.files) : [];

      for (var j = 0; j < files.length; j += 1) {
        var file = files[j];
        if (!isSupportedAttachmentForService(service, file)) {
          return "الملف المرفق غير مدعوم. الملفات المدعومة: " + supportedExtensionsLabel(service);
        }
      }

      if (service !== "home_banner") continue;

      for (var j = 0; j < files.length; j += 1) {
        var err = await validateHomeBannerFile(files[j]);
        if (err) return err;
      }
    }
    return "";
  }

  async function validateHomeBannerFile(file) {
    var assetType = detectAssetType(String(file && file.name || ""));
    if (assetType !== "image" && assetType !== "video") {
      return "بنر الصفحة الرئيسية يقبل الصور أو الفيديو فقط.";
    }

    if (assetType === "video" && !isMp4File(file)) {
      return "بنر الصفحة الرئيسية يدعم الفيديو بصيغة MP4 فقط.";
    }

    if (assetType === "image" && homeBannerAutoFitEnabled()) {
      return "";
    }

    var dims;
    try {
      dims = await readMediaDimensions(file, assetType);
    } catch (err) {
      return "تعذر قراءة أبعاد الملف " + String(file.name || "") + ".";
    }

    if (!dims || !dims.width || !dims.height) {
      return "تعذر قراءة أبعاد الملف " + String(file.name || "") + ".";
    }

    if (dims.width !== HOME_BANNER_REQUIRED_WIDTH || dims.height !== HOME_BANNER_REQUIRED_HEIGHT) {
      return "ملف " + String(file.name || "") + " يجب أن يكون بأبعاد "
        + HOME_BANNER_REQUIRED_WIDTH + "x" + HOME_BANNER_REQUIRED_HEIGHT
        + " بكسل. الأبعاد الحالية: " + dims.width + "x" + dims.height + ".";
    }

    return "";
  }

  function readMediaDimensions(file, assetType) {
    return new Promise(function (resolve, reject) {
      var objectUrl = URL.createObjectURL(file);
      var done = false;
      function finish(result, error) {
        if (done) return;
        done = true;
        try { URL.revokeObjectURL(objectUrl); } catch (e) {}
        if (error) reject(error);
        else resolve(result);
      }

      if (assetType === "image") {
        var img = new Image();
        img.onload = function () {
          finish({ width: img.naturalWidth, height: img.naturalHeight });
        };
        img.onerror = function () {
          finish(null, new Error("image-load-failed"));
        };
        img.src = objectUrl;
        return;
      }

      var video = document.createElement("video");
      video.preload = "metadata";
      video.onloadedmetadata = function () {
        finish({ width: video.videoWidth, height: video.videoHeight });
      };
      video.onerror = function () {
        finish(null, new Error("video-load-failed"));
      };
      video.src = objectUrl;
    });
  }

  function buildServicePayload(service, block, sortOrder) {
    var body = {
      service_type: service,
      title: SERVICE_LABELS[service] || service,
      sort_order: sortOrder
    };
    function field(name) {
      var element = block.querySelector('[data-field="' + name + '"]');
      return element ? element : null;
    }
    function localIso(name) {
      var val = valueOf(field(name));
      return val ? new Date(val).toISOString() : "";
    }
    function fileCount() {
      var input = field("files");
      return input && input.files ? input.files.length : 0;
    }
    function checkedValues(name) {
      return Array.from(block.querySelectorAll('[data-field="' + name + '"]:checked')).map(function (el) {
        return String(el.value || "").trim();
      }).filter(Boolean);
    }

    body.asset_count = fileCount();

    if (["home_banner", "featured_specialists", "portfolio_showcase", "snapshots", "search_results", "sponsorship"].indexOf(service) >= 0) {
      body.start_at = localIso("start_at");
      body.end_at = localIso("end_at");
      if (!body.start_at || !body.end_at) return "حدد البداية والنهاية لكل خدمة مختارة";
    }
    if (["featured_specialists", "portfolio_showcase", "snapshots"].indexOf(service) >= 0) {
      body.frequency = valueOf(field("frequency")) || "60s";
    }
    if (service === "search_results") {
      body.search_scopes = checkedValues("search_scopes");
      if (!body.search_scopes.length) return "اختر قائمة ظهور واحدة على الأقل";
      body.search_scope = body.search_scopes[0];
      body.search_position = valueOf(field("search_position")) || "first";
      body.target_category = valueOf(field("target_category"));
    }
    if (service === "promo_messages") {
      body.send_at = localIso("send_at");
      if (!body.send_at) return "حدد وقت الإرسال للرسائل الدعائية";
      body.use_notification_channel = !!(field("use_notification_channel") && field("use_notification_channel").checked);
      body.use_chat_channel = !!(field("use_chat_channel") && field("use_chat_channel").checked);
      if (!body.use_notification_channel && !body.use_chat_channel) return "اختر قناة واحدة على الأقل للرسائل الدعائية";
      body.message_body = valueOf(field("message_body"));
      if (!body.message_body && !body.asset_count) return "أدخل نص الرسالة أو أرفق مادة دعائية واحدة على الأقل";
      body.attachment_specs = valueOf(field("attachment_specs"));
    }
    if (service === "sponsorship") {
      body.sponsor_name = valueOf(field("sponsor_name"));
      body.sponsorship_months = parseInt(valueOf(field("sponsorship_months")) || "0", 10);
      body.redirect_url = valueOf(field("redirect_url"));
      body.message_body = valueOf(field("message_body"));
      body.attachment_specs = valueOf(field("attachment_specs"));
      if (!body.sponsor_name || body.sponsorship_months <= 0) return "أكمل بيانات الرعاية";
      if (!body.message_body) return "اكتب نص رسالة الرعاية";
      if (!body.asset_count) return "أضف شعار الراعي أو ملفات الرعاية";
    }
    if (service === "home_banner") {
      body.redirect_url = valueOf(field("redirect_url"));
      body.attachment_specs = valueOf(field("attachment_specs"));
      if (!body.asset_count) return "أضف مرفقات البانر قبل المتابعة";
    }
    return body;
  }

  function buildQuotePreviewHtml(preview) {
    var items = Array.isArray(preview.items) ? preview.items : [];
    var parts = [];
    if (items.length) {
      parts.push('<div class="promo-modal-section"><h4>تفاصيل التسعير</h4>');
      items.forEach(function (item) {
        parts.push(
          '<div class="promo-modal-item">' +
            '<strong>' + escapeHtml(item.title || SERVICE_LABELS[item.service_type] || item.service_type || "") + '</strong>' +
            '<div class="text-muted">' +
              money(item.subtotal) + ' ريال' +
              (item.duration_days != null ? ' • ' + escapeHtml(String(item.duration_days)) + ' يوم' : "") +
            '</div>' +
          '</div>'
        );
      });
      parts.push('</div>');
    }
    parts.push(
      '<div class="promo-modal-section">' +
        '<div class="promo-summary-grid">' +
          '<div class="promo-modal-item"><strong>قبل الضريبة</strong><div>' + money(preview.subtotal) + ' ريال</div></div>' +
          '<div class="promo-modal-item"><strong>VAT</strong><div>' + money(preview.vat_amount) + ' ريال</div></div>' +
          '<div class="promo-modal-item"><strong>الإجمالي النهائي</strong><div>' + money(preview.total) + ' ريال</div></div>' +
          '<div class="promo-modal-item"><strong>مدة الحملة</strong><div>' + escapeHtml(String(preview.total_days || 0)) + ' يوم</div></div>' +
        '</div>' +
      '</div>' +
      '<p class="promo-note">عند المتابعة سيتم إنشاء الطلب ثم الانتقال مباشرة إلى صفحة الدفع.</p>'
    );
    return parts.join("");
  }

  async function startPayment(row) {
    var invoiceId = parseInt(String((row && row.invoice) || ""), 10);
    if (!invoiceId) {
      alert("لا توجد فاتورة مرتبطة بهذا الطلب");
      return;
    }

    var idempotencyKey = "promo-" + invoiceId;
    var initRes = await ApiClient.request("/api/billing/invoices/" + invoiceId + "/init-payment/", {
      method: "POST",
      body: { provider: "mock", idempotency_key: idempotencyKey }
    });
    if (!initRes.ok) {
      alert(extractError(initRes, "تعذر فتح صفحة الدفع"));
      return;
    }

    var attempt = initRes.data || {};
    var confirmed = await openModal({
      title: "صفحة دفع الترويج",
      bodyHtml: buildPaymentHtml(row, attempt),
      confirmText: "تأكيد الدفع",
      cancelText: "إلغاء"
    });
    if (!confirmed) return;

    var payRes = await ApiClient.request("/api/billing/invoices/" + invoiceId + "/complete-mock-payment/", {
      method: "POST",
      body: { idempotency_key: idempotencyKey }
    });
    if (!payRes.ok) {
      alert(extractError(payRes, "تعذر إتمام الدفع"));
      return;
    }
    await loadRequests();
    alert("تم سداد الفاتورة وتفعيل العرض الترويجي");
  }

  function buildPaymentHtml(row, attempt) {
    return (
      '<div class="promo-modal-section">' +
        lineHtml("رقم الطلب", row.code || "") +
        (row.invoice_code ? lineHtml("رقم الفاتورة", row.invoice_code) : "") +
        lineHtml("الإجمالي", money(row.invoice_total) + " ريال") +
        (row.invoice_vat != null ? lineHtml("VAT", money(row.invoice_vat) + " ريال") : "") +
        (attempt && attempt.provider_reference ? lineHtml("مرجع الدفع", attempt.provider_reference) : "") +
      '</div>' +
      '<p class="promo-note">سيتم تنفيذ السداد التجريبي ثم تفعيل الحملة مباشرة بعد تأكيد الدفع.</p>'
    );
  }

  function resetForm() {
    if (homeBannerEditor.previewUrl) {
      try { URL.revokeObjectURL(homeBannerEditor.previewUrl); } catch (e) {}
    }
    homeBannerEditor.previewUrl = "";
    homeBannerEditor.activeDevice = "mobile";
    homeBannerEditor.scales = { mobile: 100, tablet: 100, desktop: 100 };

    document.getElementById("promo-form").reset();
    selectedServices = [];
    liveQuoteData = null;
    pendingSummary.preview = null;
    pendingSummary.requestBody = null;
    pendingPayment.requestId = null;
    pendingPayment.requestCode = "";
    pendingPayment.invoiceId = null;
    pendingPayment.invoiceCode = "";
    pendingPayment.invoiceTotal = 0;
    pendingPayment.invoiceVat = 0;
    pendingPayment.paymentMethod = "mada";
    clearPaymentCardFields();
    var defaultMethod = document.querySelector('input[name="promo-payment-method"][value="mada"]');
    if (defaultMethod) defaultMethod.checked = true;
    updatePaymentMethodSelectionUi();
    switchComposerScreen("composer");
    document.querySelectorAll("[data-service-toggle]").forEach(function (input) {
      input.checked = false;
    });
    Object.keys(SERVICE_LABELS).forEach(function (service) {
      toggleServiceBlock(service, false);
    });

    var liveRoot = document.getElementById("promo-live-total");
    var liveBreakdown = document.getElementById("promo-live-breakdown");
    if (liveRoot) liveRoot.hidden = true;
    if (liveBreakdown) {
      liveBreakdown.innerHTML = "";
      liveBreakdown.hidden = true;
    }

    var editor = document.getElementById("home-banner-editor");
    var mediaWrap = document.getElementById("home-banner-preview-media-wrap");
    var empty = document.getElementById("home-banner-preview-empty");
    var dims = document.getElementById("home-banner-dims");
    if (editor) editor.hidden = true;
    if (mediaWrap) mediaWrap.innerHTML = "";
    if (empty) empty.hidden = false;
    if (dims) dims.textContent = "لم يتم اختيار ملف بعد";
    updateHomeBannerScaleUi();
  }

  function valueOf(element) {
    return element && element.value ? String(element.value).trim() : "";
  }

  function detectAssetType(name) {
    var ext = (name.split(".").pop() || "").toLowerCase();
    if (["jpg", "jpeg", "png", "gif", "webp"].indexOf(ext) >= 0) return "image";
    if (["mp4", "mov", "avi", "mkv", "webm"].indexOf(ext) >= 0) return "video";
    if (ext === "pdf") return "pdf";
    return "other";
  }

  function fileExtension(name) {
    var clean = String(name || "").trim().toLowerCase();
    if (!clean || clean.indexOf(".") < 0) return "";
    return "." + clean.split(".").pop();
  }

  function isSupportedAttachmentForService(service, file) {
    var allowed = SERVICE_ALLOWED_EXTENSIONS[service];
    if (!allowed || !allowed.length) return true;
    var ext = fileExtension(file && file.name);
    if (!ext) return false;
    return allowed.indexOf(ext) >= 0;
  }

  function supportedExtensionsLabel(service) {
    var allowed = SERVICE_ALLOWED_EXTENSIONS[service] || [];
    if (!allowed.length) return "غير محدد";
    return allowed.map(function (ext) { return ext.toUpperCase().replace(".", ""); }).join(", ");
  }

  function isMp4File(file) {
    var name = String(file && file.name || "").toLowerCase();
    return name.endsWith(".mp4");
  }

  function money(value) {
    var parsed = Number(value);
    return Number.isFinite(parsed) ? parsed.toFixed(2) : "0.00";
  }

  function lineHtml(label, value) {
    if (value == null || value === "") return "";
    return '<div class="promo-line"><span>' + escapeHtml(String(label)) + '</span><strong>' + escapeHtml(String(value)) + '</strong></div>';
  }

  function flattenErrorMessages(value, bucket) {
    if (value == null) return;
    if (typeof value === "string") {
      var text = value.trim();
      if (text) bucket.push(text);
      return;
    }
    if (Array.isArray(value)) {
      value.forEach(function (item) {
        flattenErrorMessages(item, bucket);
      });
      return;
    }
    if (typeof value === "object") {
      Object.keys(value).forEach(function (key) {
        flattenErrorMessages(value[key], bucket);
      });
      return;
    }
    bucket.push(String(value));
  }

  function extractError(response, fallback) {
    if (!response || !response.data) return fallback;
    if (typeof response.data.detail === "string" && response.data.detail) return response.data.detail;
    if (typeof response.data === "string") return response.data;
    var details = [];
    flattenErrorMessages(response.data, details);
    return details.length ? details.join("\n") : fallback;
  }

  function escapeHtml(value) {
    return String(value || "").replace(/[&<>"']/g, function (char) {
      return ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char];
    });
  }

  /* ====================================================================
     Live Quote Calculation (debounced)
     ==================================================================== */

  function scheduleLiveQuote() {
    if (liveQuoteTimer) clearTimeout(liveQuoteTimer);
    liveQuoteTimer = setTimeout(calculateLiveQuote, 550);
  }

  async function calculateLiveQuote() {
    var totalEl = document.getElementById("promo-live-total");
    var amountEl = document.getElementById("promo-live-amount");
    var detailEl = document.getElementById("promo-live-detail");
    var breakdownEl = document.getElementById("promo-live-breakdown");
    var spinnerEl = document.getElementById("promo-live-spinner");

    var title = valueOf(document.getElementById("promo-title"));
    if (!title || !selectedServices.length) {
      if (totalEl) totalEl.hidden = true;
      if (breakdownEl) {
        breakdownEl.innerHTML = "";
        breakdownEl.hidden = true;
      }
      return;
    }

    var items = [];
    for (var i = 0; i < selectedServices.length; i++) {
      var service = selectedServices[i];
      var block = document.querySelector('[data-service-block="' + service + '"]');
      var payload = buildServicePayload(service, block, i);
      if (typeof payload === "string") {
        if (totalEl) totalEl.hidden = true;
        if (breakdownEl) {
          breakdownEl.innerHTML = "";
          breakdownEl.hidden = true;
        }
        return;
      }
      items.push(payload);
    }

    if (totalEl) totalEl.hidden = false;
    if (spinnerEl) spinnerEl.hidden = false;

    try {
      var requestBody = Object.assign({ title: title, items: items }, collectHomeBannerScalePayload());
      var res = await ApiClient.request("/api/promo/requests/preview/", {
        method: "POST",
        body: requestBody
      });
      if (spinnerEl) spinnerEl.hidden = true;
      if (!res.ok) {
        if (breakdownEl) {
          breakdownEl.innerHTML = "";
          breakdownEl.hidden = true;
        }
        return;
      }

      liveQuoteData = res.data || {};
      if (amountEl) amountEl.textContent = money(liveQuoteData.total) + " ريال";
      if (detailEl) detailEl.textContent = "قبل الضريبة: " + money(liveQuoteData.subtotal) + " ريال • VAT: " + money(liveQuoteData.vat_amount) + " ريال";
      renderLiveQuoteBreakdown(liveQuoteData, breakdownEl);
    } catch (err) {
      if (spinnerEl) spinnerEl.hidden = true;
      if (breakdownEl) {
        breakdownEl.innerHTML = "";
        breakdownEl.hidden = true;
      }
    }
  }

  function renderLiveQuoteBreakdown(preview, root) {
    if (!root) return;
    var items = Array.isArray(preview && preview.items) ? preview.items : [];
    if (!items.length) {
      root.innerHTML = "";
      root.hidden = true;
      return;
    }
    var html = items.map(function (item) {
      var label = escapeHtml(item.title || SERVICE_LABELS[item.service_type] || item.service_type || "خدمة");
      var subtotal = money(item.subtotal) + " ريال";
      var duration = item.duration_days != null ? " • " + escapeHtml(String(item.duration_days)) + " يوم" : "";
      return (
        '<div class="promo-live-breakdown-item">' +
          '<strong>' + label + '</strong>' +
          '<span>' + subtotal + duration + '</span>' +
        '</div>'
      );
    }).join("");
    root.innerHTML = html;
    root.hidden = false;
  }

  function bindLiveQuote() {
    var form = document.getElementById("promo-form");
    if (!form) return;

    form.addEventListener("input", function (e) {
      var tag = (e.target.tagName || "").toLowerCase();
      if (tag === "input" || tag === "textarea" || tag === "select") {
        scheduleLiveQuote();
      }
    });
    form.addEventListener("change", function (e) {
      var tag = (e.target.tagName || "").toLowerCase();
      if (tag === "input" || tag === "select") {
        scheduleLiveQuote();
      }
    });
  }

  /* ====================================================================
     Per-Service Preview
     ==================================================================== */

  function bindPreviewButtons() {
    var blocksRoot = document.getElementById("promo-service-blocks");
    if (!blocksRoot) return;
    blocksRoot.addEventListener("click", async function (e) {
      var btn = e.target.closest(".btn-preview-service");
      if (!btn) return;
      var service = btn.dataset.previewService;
      if (!service) return;
      await previewServiceQuote(service);
    });
  }

  async function previewServiceQuote(service) {
    var block = document.querySelector('[data-service-block="' + service + '"]');
    if (!block) return;

    var idx = selectedServices.indexOf(service);
    if (idx < 0) {
      alert("هذه الخدمة غير مختارة");
      return;
    }

    var title = valueOf(document.getElementById("promo-title")) || "معاينة " + (SERVICE_LABELS[service] || service);
    var payload = buildServicePayload(service, block, idx);
    if (typeof payload === "string") {
      alert(SERVICE_LABELS[service] + ": " + payload);
      return;
    }

    var requestBody = Object.assign({ title: title, items: [payload] }, collectHomeBannerScalePayload());
    var res = await ApiClient.request("/api/promo/requests/preview/", {
      method: "POST",
      body: requestBody
    });
    if (!res.ok) {
      alert(extractError(res, "تعذر معاينة تسعير البند"));
      return;
    }

    var data = res.data || {};
    var items = Array.isArray(data.items) ? data.items : [];
    var item = items.length ? items[0] : {};

    var bodyHtml =
      '<div class="promo-modal-section">' +
        lineHtml("البند", SERVICE_LABELS[service] || service) +
        lineHtml("سعر البند", money(item.subtotal) + " ريال") +
        (item.duration_days != null ? lineHtml("مدة الحملة", item.duration_days + " يوم") : "") +
        lineHtml("الإجمالي قبل الضريبة", money(data.subtotal) + " ريال") +
        lineHtml("VAT", money(data.vat_amount) + " ريال") +
        lineHtml("الإجمالي النهائي", money(data.total) + " ريال") +
      '</div>' +
      '<p class="promo-note">تم احتساب السعر حسب قواعد صفحة الأسعار الحالية لكل بند.</p>';

    await openModal({
      title: "معاينة " + (SERVICE_LABELS[service] || service),
      bodyHtml: bodyHtml,
      confirmText: null,
      cancelText: "إغلاق"
    });
  }

  /* ====================================================================
     Success Dialog
     ==================================================================== */

  function showSuccessDialog(requestCode, options) {
    options = options || {};
    var modal = document.getElementById("promo-success-modal");
    var codeEl = document.getElementById("success-request-code");
    var titleEl = document.getElementById("success-title");
    var messageEl = document.getElementById("success-text");
    var closeBtn = document.getElementById("success-close-btn");
    if (!modal || !closeBtn || !codeEl) {
      if (typeof options.onClose === "function") {
        options.onClose();
      }
      return;
    }

    codeEl.textContent = "رقم الطلب: " + (requestCode || "—");
    if (titleEl && options.title) titleEl.textContent = options.title;
    if (messageEl && options.message) messageEl.textContent = options.message;
    modal.hidden = false;
    document.body.style.overflow = "hidden";

    function close() {
      modal.hidden = true;
      document.body.style.overflow = "";
      closeBtn.removeEventListener("click", close);
      if (typeof options.onClose === "function") {
        options.onClose();
      }
    }
    closeBtn.addEventListener("click", close);
  }

  document.addEventListener("DOMContentLoaded", init);
  return { init: init };
})();
