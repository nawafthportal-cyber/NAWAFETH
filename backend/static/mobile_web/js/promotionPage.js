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

  function resolveProviderStatusCode(row) {
    if (row && row.provider_status_code) {
      return String(row.provider_status_code || "").trim();
    }

    var status = String((row && row.status) || "").trim();
    var opsStatus = String((row && row.ops_status) || "new").trim();
    var paymentEffective = !!(row && row.payment_effective === true);

    if (status === "rejected" || status === "cancelled" || status === "expired" || status === "completed") {
      return status;
    }
    if (status === "active" || opsStatus === "completed") {
      return "active";
    }
    if (paymentEffective) {
      if (opsStatus === "in_progress") {
        return "in_progress";
      }
      return "awaiting_review";
    }
    if (status === "quoted" || status === "pending_payment" || status === "in_review") {
      return status;
    }
    return "new";
  }

  function resolveProviderStatusLabel(row) {
    if (row && row.provider_status_label) {
      return String(row.provider_status_label || "").trim();
    }

    var providerStatusCode = resolveProviderStatusCode(row);
    if (providerStatusCode === "awaiting_review") {
      return "بانتظار المراجعة";
    }
    if (providerStatusCode === "in_progress") {
      return OPS_LABELS.in_progress;
    }
    return STATUS_LABELS[providerStatusCode] || OPS_LABELS[providerStatusCode] || providerStatusCode || "";
  }

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
  var PROMO_ASSET_UPLOAD_LIMITS_MB = {
    image: 10,
    video: 20,
    pdf: 10,
    other: 10,
    home_banner_image: 10,
    home_banner_video: 20
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
  var deepLinkedRequestId = 0;
  var paymentReturnNotice = null;
  var preferredProviderIdentityName = "";
  var homeBannerEditor = {
    previewUrl: ""
  };
  var portfolioPickerState = {
    portfolio_showcase: { loaded: false, loading: false, items: [], selectedId: 0 },
    snapshots: { loaded: false, loading: false, items: [], selectedId: 0 }
  };
  var uploadStatusState = {
    root: null,
    label: null,
    detail: null,
    percent: null,
    bar: null,
    progressWrap: null
  };

  function getUploadStatusState() {
    if (!uploadStatusState.root) {
      uploadStatusState.root = document.getElementById("promo-upload-status");
      uploadStatusState.label = document.getElementById("promo-upload-status-label");
      uploadStatusState.detail = document.getElementById("promo-upload-status-detail");
      uploadStatusState.percent = document.getElementById("promo-upload-status-percent");
      uploadStatusState.bar = document.getElementById("promo-upload-progress-bar");
      uploadStatusState.progressWrap = uploadStatusState.root
        ? uploadStatusState.root.querySelector(".promo-upload-progress")
        : null;
    }
    return uploadStatusState;
  }

  function setUploadStatus(state, label, detail, percent) {
    var ui = getUploadStatusState();
    if (!ui.root) return;
    var normalizedState = String(state || "").trim().toLowerCase();
    if (["waiting", "uploading", "success", "failed"].indexOf(normalizedState) < 0) {
      normalizedState = "waiting";
    }
    var rawPercent = Number(percent);
    var safePercent = Number.isFinite(rawPercent)
      ? Math.max(0, Math.min(100, Math.round(rawPercent)))
      : 0;
    ui.root.hidden = false;
    ui.root.classList.remove("state-waiting", "state-uploading", "state-success", "state-failed");
    ui.root.classList.add("state-" + normalizedState);
    if (ui.label) {
      ui.label.textContent = String(label || "جاري تجهيز الرفع");
    }
    if (ui.detail) {
      ui.detail.textContent = String(detail || "");
    }
    if (ui.percent) {
      ui.percent.textContent = safePercent + "%";
    }
    if (ui.bar) {
      ui.bar.style.width = safePercent + "%";
    }
    if (ui.progressWrap) {
      ui.progressWrap.setAttribute("aria-valuenow", String(safePercent));
    }
  }

  function resetUploadStatus() {
    var ui = getUploadStatusState();
    if (!ui.root) return;
    ui.root.hidden = true;
    ui.root.classList.remove("state-waiting", "state-uploading", "state-success", "state-failed");
    if (ui.label) ui.label.textContent = "جاهز للرفع";
    if (ui.detail) ui.detail.textContent = "";
    if (ui.percent) ui.percent.textContent = "0%";
    if (ui.bar) ui.bar.style.width = "0%";
    if (ui.progressWrap) ui.progressWrap.setAttribute("aria-valuenow", "0");
  }

  function init() {
    deepLinkedRequestId = getDeepLinkedRequestId();
    paymentReturnNotice = getPaymentReturnNotice();
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
      bindSponsorshipAutoEnd();
      bindPortfolioPicker();
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
    return (shell && shell.dataset && shell.dataset.promoRequestsUrl) || "/mobile-web/promotion/";
  }

  function getNewRequestUrl() {
    var shell = getMainShell();
    return (shell && shell.dataset && shell.dataset.promoNewRequestUrl) || "/mobile-web/promotion/new/";
  }

  function getPaymentPageUrl() {
    var shell = getMainShell();
    return (shell && shell.dataset && shell.dataset.promoPaymentUrl) || "/promotion/payment/";
  }

  function buildPromotionPaymentUrl(requestId, invoiceId) {
    var base = getPaymentPageUrl();
    var params = [];
    if (requestId > 0) {
      params.push("request_id=" + encodeURIComponent(String(requestId)));
    }
    if (invoiceId > 0) {
      params.push("invoice_id=" + encodeURIComponent(String(invoiceId)));
    }
    return base + (params.length ? ((base.indexOf("?") === -1 ? "?" : "&") + params.join("&")) : "");
  }

  function goToPromotionPaymentPage(requestId, invoiceId) {
    var nextUrl = buildPromotionPaymentUrl(requestId, invoiceId);
    window.location.href = nextUrl;
  }

  function goToRequestsPage() {
    window.location.href = getRequestsUrl();
  }

  function getPaymentReturnNotice() {
    try {
      var params = new URLSearchParams(window.location.search || "");
      var payment = String(params.get("payment") || "").trim().toLowerCase();
      var invoice = String(params.get("invoice") || "").trim();
      if (!payment) return null;
      return { payment: payment, invoice: invoice };
    } catch (_) {
      return null;
    }
  }

  function consumePaymentReturnNotice() {
    if (!paymentReturnNotice) return;
    paymentReturnNotice = null;
    try {
      var url = new URL(window.location.href);
      url.searchParams.delete("payment");
      url.searchParams.delete("invoice");
      window.history.replaceState({}, "", url.pathname + (url.search || "") + (url.hash || ""));
    } catch (_) {}
  }

  function buildPromoCheckoutNextPath(requestId) {
    try {
      var base = new URL(getRequestsUrl(), window.location.origin);
      if (requestId > 0) base.searchParams.set("request_id", String(requestId));
      return base.pathname + (base.search || "");
    } catch (_) {
      return requestId > 0 ? (getRequestsUrl() + "?request_id=" + encodeURIComponent(String(requestId))) : getRequestsUrl();
    }
  }

  function checkoutUrlWithNext(rawCheckoutUrl, requestId) {
    var checkout = String(rawCheckoutUrl || "").trim();
    if (!checkout) return "";
    try {
      var url = new URL(checkout, window.location.origin);
      url.searchParams.set("next", buildPromoCheckoutNextPath(requestId));
      return url.toString();
    } catch (_) {
      return checkout;
    }
  }

  function maybeShowPaymentReturnNotice() {
    if (!paymentReturnNotice) return;
    var notice = paymentReturnNotice;
    consumePaymentReturnNotice();

    if (notice.payment === "success") {
      alert("تم سداد الفاتورة بنجاح. الطلب الآن بانتظار مراجعة فريق الترويج، ولا يتم تفعيل الحملة إلا بعد اكتمال التنفيذ واعتماد الطلب.");
      return;
    }
    if (notice.payment === "cancelled") {
      alert("تم إلغاء عملية الدفع. الحملة ما زالت غير مفعلة ويمكنك العودة لإتمام السداد لاحقًا.");
      return;
    }
    if (notice.payment === "failed") {
      alert("فشل سداد الفاتورة. لم يتم تفعيل الحملة ويمكنك إعادة محاولة الدفع.");
    }
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
        var tooLarge = files.filter(function (file) {
          return isFileTooLargeForService(file, service);
        });
        if (!badFiles.length && !tooLarge.length) return;

        input.value = "";
        if (service === "home_banner") {
          renderHomeBannerPreview(null);
        }
        if (badFiles.length) {
          alert(
            "الملف المرفق غير مدعوم.\\n"
            + "الملفات المدعومة: "
            + supportedExtensionsLabel(service)
          );
          return;
        }
        var firstLargeFile = tooLarge[0];
        var assetType = detectAssetType(String(firstLargeFile.name || ""));
        var maxMb = resolveUploadLimitMb(service, assetType);
        alert(
          "حجم الملف أكبر من الحد المسموح.\\n"
          + "الملف: " + String(firstLargeFile.name || "مرفق") + "\\n"
          + "الحد الأقصى لهذا النوع: " + maxMb + "MB"
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
      applyAssetUploadLimitsFromGuide(res.data);
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
    if (!Number.isFinite(minHours) || minHours < 24) minHours = 24;

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
        "التكلفة اليومية تعتمد على نوع الخدمة المختارة."
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
        "يمكن اختيار التنبيهات أو الرسائل أو كلاهما."
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

  function looksLikePhone(val) {
    var s = String(val || "").replace(/[\s\-\+\(\)@]/g, "");
    return /^0[0-9]{8,12}$/.test(s) || /^9665[0-9]{8}$/.test(s) || /^5[0-9]{8}$/.test(s);
  }

  function safeDisplayValue(val) {
    var s = String(val == null ? "" : val).trim();
    return (s && !looksLikePhone(s)) ? s : "";
  }

  function resolveProviderDisplayName(profile, fallback) {
    var safeProfile = profile && typeof profile === "object" ? profile : {};
    var nestedUser = safeProfile.user && typeof safeProfile.user === "object" ? safeProfile.user : {};
    var nestedProvider = safeProfile.provider && typeof safeProfile.provider === "object"
      ? safeProfile.provider
      : (safeProfile.provider_profile && typeof safeProfile.provider_profile === "object" ? safeProfile.provider_profile : {});

    var firstName = safeDisplayValue(firstNonEmptyText([safeProfile.first_name, nestedUser.first_name]));
    var lastName = safeDisplayValue(firstNonEmptyText([safeProfile.last_name, nestedUser.last_name]));
    var fullName = [firstName, lastName].filter(Boolean).join(" ").trim();
    var username = firstNonEmptyText([safeProfile.username, nestedUser.username]);
    if (username && !looksLikePhone(username)) {
      if (username.charAt(0) !== "@") username = "@" + username;
    } else {
      username = "";
    }

    return firstNonEmptyText([
      safeDisplayValue(safeProfile.display_name),
      safeDisplayValue(safeProfile.provider_display_name),
      safeDisplayValue(safeProfile.name),
      safeDisplayValue(safeProfile.full_name),
      safeDisplayValue(safeProfile.provider_name),
      safeDisplayValue(nestedProvider.display_name),
      safeDisplayValue(nestedProvider.provider_display_name),
      safeDisplayValue(nestedProvider.name),
      safeDisplayValue(nestedProvider.business_name),
      safeDisplayValue(nestedUser.display_name),
      safeDisplayValue(nestedUser.name),
      safeDisplayValue(nestedUser.full_name),
      fullName,
      username,
      fallback
    ]);
  }

  function applyProviderIdentityName(chosen, fallback) {
    var input = document.getElementById("promo-provider-name");
    var display = document.getElementById("promo-provider-display");
    if (!input && !display) return;

    var finalName = firstNonEmptyText([preferredProviderIdentityName, chosen, fallback]);
    if (input) {
      input.value = finalName;
      input.title = finalName;
    }
    if (display) {
      display.textContent = finalName;
      display.title = finalName;
    }
  }

  function preferProviderIdentityFromRequest(row) {
    var chosen = resolveProviderDisplayName(row, "");
    if (!chosen) return;
    preferredProviderIdentityName = chosen;
    applyProviderIdentityName(chosen, getServerRenderedProviderName() || "مزود الخدمة");
  }

  function getServerRenderedProviderName() {
    var shell = getMainShell();
    var shellName = shell && shell.dataset ? String(shell.dataset.providerDisplayName || "").trim() : "";
    return shellName;
  }

  async function fetchProviderIdentityCandidates() {
    var candidates = [];
    var shellName = getServerRenderedProviderName();
    if (shellName) {
      candidates.push({ provider_display_name: shellName });
    }
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
    var fallback = getServerRenderedProviderName() || "مزود الخدمة";
    applyProviderIdentityName(fallback, fallback);

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
    if (!filesInput) return;

    filesInput.setAttribute("accept", ".jpg,.jpeg,.png,.mp4");

    filesInput.addEventListener("change", function () {
      var file = filesInput.files && filesInput.files[0] ? filesInput.files[0] : null;
      renderHomeBannerPreview(file);
    });
  }

  function bindPortfolioPicker() {
    document.querySelectorAll("[data-portfolio-picker]").forEach(function (root) {
      root.addEventListener("click", function (event) {
        var card = event.target.closest(".portfolio-picker-card");
        if (!card) return;
        var service = String(root.dataset.portfolioPicker || "").trim();
        var itemId = parseInt(String(card.dataset.itemId || "0"), 10);
        if (!service || !itemId) return;
        selectPortfolioItem(service, itemId);
        scheduleLiveQuote();
      });
    });
  }

  function getGalleryPickerRoot(service) {
    return document.querySelector('[data-portfolio-picker="' + service + '"]');
  }

  function pickerStateForService(service) {
    if (!portfolioPickerState[service]) {
      portfolioPickerState[service] = { loaded: false, loading: false, items: [], selectedId: 0 };
    }
    return portfolioPickerState[service];
  }

  function pickerFieldNameForService(service) {
    return service === "snapshots" ? "target_spotlight_item_id" : "target_portfolio_item_id";
  }

  function pickerEndpointForService(service) {
    return service === "snapshots" ? "/api/providers/me/spotlights/" : "/api/providers/me/portfolio/";
  }

  function getGalleryPickerElements(service) {
    var root = getGalleryPickerRoot(service);
    if (!root) return null;
    return {
      root: root,
      loading: root.querySelector("[data-picker-loading]"),
      error: root.querySelector("[data-picker-error]"),
      empty: root.querySelector("[data-picker-empty]"),
      grid: root.querySelector("[data-picker-grid]"),
      selection: root.querySelector("[data-picker-selection]"),
      previewWrap: root.querySelector("[data-picker-preview-wrap]"),
      previewEmpty: root.querySelector("[data-picker-preview-empty]"),
      previewImage: root.querySelector("[data-picker-preview-image]"),
      previewVideo: root.querySelector("[data-picker-preview-video]"),
      previewCaption: root.querySelector("[data-picker-preview-caption]"),
      hiddenInput: document.querySelector('[data-service-block="' + service + '"] [data-field="' + pickerFieldNameForService(service) + '"]')
    };
  }

  function setHiddenState(element, hidden) {
    if (!element) return;
    element.hidden = !!hidden;
    if (element.classList) {
      element.classList.toggle("hidden", !!hidden);
    }
  }

  function portfolioItemsForService(service) {
    return (pickerStateForService(service).items || []).filter(function (item) {
      if (!item) return false;
      var fileType = String(item.file_type || "").toLowerCase();
      var hasMedia = !!(item.file_url || item.thumbnail_url);
      if (!hasMedia) return false;
      if (service === "snapshots") {
        return fileType === "image" || fileType === "video";
      }
      return fileType === "image";
    });
  }

  function selectedPortfolioIdForService(service) {
    return Number(pickerStateForService(service).selectedId || 0);
  }

  function selectedPortfolioItemForService(service) {
    var selectedId = selectedPortfolioIdForService(service);
    if (!selectedId) return null;
    return portfolioItemsForService(service).find(function (item) {
      return Number(item.id) === selectedId;
    }) || null;
  }

  function selectionLabelForService(service) {
    return service === "snapshots"
      ? "الريل المختار لشريط اللمحات: "
      : "الصورة المختارة للترويج: ";
  }

  function previewCaptionForService(service, selected) {
    if (!selected) {
      return service === "snapshots"
        ? "المعاينة ستتحدث فور اختيار الريل، وهو نفسه الذي سيظهر داخل شريط اللمحات."
        : "المعاينة ستتحدث فور اختيار الصورة، وهي نفسها التي ستظهر داخل شريط البنرات والمشاريع.";
    }
    return service === "snapshots"
      ? "هذا هو الريل الذي سيستخدم داخل شريط اللمحات عند تفعيل الحملة."
      : "هذه هي الصورة التي ستستخدم داخل شريط البنرات والمشاريع عند تفعيل الحملة.";
  }

  function renderGalleryPickerPreview(service) {
    var elements = getGalleryPickerElements(service);
    if (!elements || !elements.previewWrap || !elements.previewEmpty || !elements.previewImage || !elements.previewCaption) {
      return;
    }
    var selected = selectedPortfolioItemForService(service);
    var mediaUrl = selected ? resolveMediaUrl(selected.file_url || selected.thumbnail_url || "") : "";
    var fileType = String((selected && selected.file_type) || "image").toLowerCase();
    setHiddenState(elements.previewWrap, false);
    if (!selected || !mediaUrl) {
      setHiddenState(elements.previewEmpty, false);
      setHiddenState(elements.previewImage, true);
      elements.previewImage.removeAttribute("src");
      if (elements.previewVideo) {
        setHiddenState(elements.previewVideo, true);
        elements.previewVideo.pause();
        elements.previewVideo.removeAttribute("src");
        elements.previewVideo.load();
      }
      elements.previewCaption.textContent = previewCaptionForService(service, null);
      return;
    }

    setHiddenState(elements.previewEmpty, true);
    if (fileType === "video" && elements.previewVideo) {
      setHiddenState(elements.previewImage, true);
      elements.previewImage.removeAttribute("src");
      setHiddenState(elements.previewVideo, false);
      elements.previewVideo.src = mediaUrl;
      if (selected.thumbnail_url) {
        elements.previewVideo.poster = resolveMediaUrl(selected.thumbnail_url);
      } else {
        elements.previewVideo.removeAttribute("poster");
      }
      elements.previewVideo.muted = true;
      elements.previewVideo.play().catch(function () {});
    } else {
      if (elements.previewVideo) {
        setHiddenState(elements.previewVideo, true);
        elements.previewVideo.pause();
        elements.previewVideo.removeAttribute("src");
        elements.previewVideo.removeAttribute("poster");
        elements.previewVideo.load();
      }
      setHiddenState(elements.previewImage, false);
      elements.previewImage.src = mediaUrl;
      elements.previewImage.alt = String(selected.caption || "صورة مختارة من معرض الأعمال").trim() || "صورة مختارة من معرض الأعمال";
    }
    elements.previewCaption.textContent = previewCaptionForService(service, selected);
  }

  async function ensurePortfolioPickerLoaded(service) {
    var state = pickerStateForService(service);
    if (state.loaded || state.loading) return;
    var elements = getGalleryPickerElements(service);
    if (elements && elements.loading) setHiddenState(elements.loading, false);
    if (elements && elements.error) {
      setHiddenState(elements.error, true);
      elements.error.textContent = "";
    }
    if (elements && elements.empty) setHiddenState(elements.empty, true);
    if (elements && elements.grid) {
      setHiddenState(elements.grid, true);
      elements.grid.innerHTML = "";
    }

    state.loading = true;
    try {
      var res = await ApiClient.get(pickerEndpointForService(service));
      if (!res.ok || !res.data) {
        throw new Error(extractError(res, service === "snapshots" ? "تعذر تحميل الريلز" : "تعذر تحميل معرض الأعمال"));
      }
      var rows = Array.isArray(res.data) ? res.data : ((res.data && res.data.results) || []);
      state.items = rows.filter(function (item) {
        var fileType = String((item && item.file_type) || "").toLowerCase();
        return !!item && (fileType === "image" || fileType === "video") && (item.thumbnail_url || item.file_url);
      });
      state.loaded = true;
      renderPortfolioPicker(service);
    } catch (err) {
      if (elements && elements.error) {
        elements.error.textContent = err && err.message ? err.message : (service === "snapshots" ? "تعذر تحميل الريلز حالياً." : "تعذر تحميل وسائط معرض الأعمال حالياً.");
        setHiddenState(elements.error, false);
      }
    } finally {
      state.loading = false;
      if (elements && elements.loading) setHiddenState(elements.loading, true);
    }
  }

  function renderPortfolioPicker(service) {
    var elements = getGalleryPickerElements(service);
    if (!elements || !elements.grid || !elements.empty || !elements.selection || !elements.hiddenInput) return;
    var gridEl = elements.grid;
    var emptyEl = elements.empty;
    var selectionEl = elements.selection;
    var hiddenInput = elements.hiddenInput;
    var selectedId = selectedPortfolioIdForService(service);

    var serviceItems = portfolioItemsForService(service);

    if (!serviceItems.length) {
      setHiddenState(gridEl, true);
      gridEl.innerHTML = "";
      setHiddenState(emptyEl, false);
      hiddenInput.value = "";
      setHiddenState(selectionEl, true);
      selectionEl.textContent = "";
      renderGalleryPickerPreview(service);
      return;
    }

    setHiddenState(emptyEl, true);
    setHiddenState(gridEl, false);
    gridEl.innerHTML = serviceItems.map(function (item) {
      var fileType = String(item.file_type || "image").toLowerCase();
      var caption = String(item.caption || (service === "snapshots" ? (fileType === "video" ? "ريل فيديو" : "ريل صورة") : (fileType === "video" ? "فيديو من معرض الأعمال" : "صورة من معرض الأعمال"))).trim() || (service === "snapshots" ? "ريل منشور" : "عنصر من معرض الأعمال");
      var mediaUrl = resolveMediaUrl(item.thumbnail_url || item.file_url || "");
      var dateText = formatDateTime(item.created_at || "") || (service === "snapshots" ? "من اللمحات" : "من معرض الأعمال");
      var selectedClass = Number(item.id) === selectedId ? " is-selected" : "";
      var mediaHtml = fileType === "video"
        ? '<video src="' + escapeHtml(resolveMediaUrl(item.file_url || item.thumbnail_url || "")) + '" preload="metadata" muted playsinline' + (item.thumbnail_url ? ' poster="' + escapeHtml(resolveMediaUrl(item.thumbnail_url)) + '"' : '') + '></video>'
        : '<img src="' + escapeHtml(mediaUrl) + '" alt="' + escapeHtml(caption) + '">';
      var badgeHtml = service === "snapshots"
        ? '<span class="portfolio-picker-type-badge">' + escapeHtml(fileType === "video" ? "فيديو" : "صورة") + '</span>'
        : '';
      return ''
        + '<button type="button" class="portfolio-picker-card' + selectedClass + '" data-item-id="' + escapeHtml(String(item.id || "")) + '">'
        + '  <div class="portfolio-picker-media">'
        + mediaHtml
        + badgeHtml
        + '    <span class="portfolio-picker-check" aria-hidden="true">✓</span>'
        + '  </div>'
        + '  <div class="portfolio-picker-meta">'
        + '    <p class="portfolio-picker-caption">' + escapeHtml(caption) + '</p>'
        + '    <span class="portfolio-picker-date">' + escapeHtml(dateText) + '</span>'
        + '  </div>'
        + '</button>';
    }).join("");

    hiddenInput.value = selectedId ? String(selectedId) : "";
    renderPortfolioSelectionSummary(service);
    renderGalleryPickerPreview(service);
  }

  function selectPortfolioItem(service, itemId) {
    pickerStateForService(service).selectedId = Number(itemId) || 0;
    renderPortfolioPicker(service);
  }

  function renderPortfolioSelectionSummary(service) {
    var elements = getGalleryPickerElements(service);
    var selectionEl = elements && elements.selection ? elements.selection : null;
    if (!selectionEl) return;
    var selected = selectedPortfolioItemForService(service);
    if (!selected) {
      setHiddenState(selectionEl, true);
      selectionEl.textContent = "";
      return;
    }
    setHiddenState(selectionEl, false);
    selectionEl.textContent = selectionLabelForService(service) + (String(selected.caption || (service === "snapshots" ? "ريل منشور" : (String(selected.file_type || "").toLowerCase() === "video" ? "فيديو من معرض الأعمال" : "صورة من معرض الأعمال"))).trim() || "عنصر مختار");
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
      note.textContent = "سيقوم النظام بضبط الفيديو تلقائياً إلى المقاس المعتمد 1920x840 عند الرفع.";
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
    note.textContent = "سيقوم النظام بضبط الصورة تلقائياً إلى المقاس المعتمد 1920x840 عند الرفع.";
  }

  function homeBannerAutoFitEnabled() {
    return true;
  }

  function collectHomeBannerScalePayload() {
    if (selectedServices.indexOf("home_banner") < 0) return {};
    return {
      mobile_scale: 100,
      tablet_scale: 100,
      desktop_scale: 100
    };
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

    if (service === "sponsorship" && show) {
      refreshSponsorshipSchedule(block);
    }

    if ((service === "portfolio_showcase" || service === "snapshots") && show) {
      ensurePortfolioPickerLoaded(service);
    }
  }

  function parseLocalDateTimeValue(rawValue) {
    var value = String(rawValue || "").trim();
    if (!value) return null;
    var parsed = new Date(value);
    return isNaN(parsed.getTime()) ? null : parsed;
  }

  function formatLocalDateTimeInput(dateValue) {
    if (!dateValue || isNaN(dateValue.getTime())) return "";
    var yy = String(dateValue.getFullYear());
    var mm = String(dateValue.getMonth() + 1).padStart(2, "0");
    var dd = String(dateValue.getDate()).padStart(2, "0");
    var hh = String(dateValue.getHours()).padStart(2, "0");
    var mi = String(dateValue.getMinutes()).padStart(2, "0");
    return yy + "-" + mm + "-" + dd + "T" + hh + ":" + mi;
  }

  function addMonthsClamped(dateValue, monthsCount) {
    if (!dateValue || isNaN(dateValue.getTime())) return null;
    var months = parseInt(String(monthsCount || "0"), 10);
    if (!months || months < 1) return null;
    var targetMonthIndex = dateValue.getMonth() + months;
    var targetYear = dateValue.getFullYear() + Math.floor(targetMonthIndex / 12);
    var targetMonth = targetMonthIndex % 12;
    var lastDayOfMonth = new Date(targetYear, targetMonth + 1, 0).getDate();
    var targetDay = Math.min(dateValue.getDate(), lastDayOfMonth);
    return new Date(
      targetYear,
      targetMonth,
      targetDay,
      dateValue.getHours(),
      dateValue.getMinutes(),
      dateValue.getSeconds(),
      dateValue.getMilliseconds()
    );
  }

  function calculateSponsorshipEndDate(startValue, monthsValue) {
    var startDate = parseLocalDateTimeValue(startValue);
    if (!startDate) return null;
    return addMonthsClamped(startDate, monthsValue);
  }

  function calculateSponsorshipEndIso(startValue, monthsValue) {
    var endDate = calculateSponsorshipEndDate(startValue, monthsValue);
    return endDate ? endDate.toISOString() : "";
  }

  function refreshSponsorshipSchedule(block) {
    var sponsorshipBlock = block || document.querySelector('[data-service-block="sponsorship"]');
    if (!sponsorshipBlock) return;
    var startInput = sponsorshipBlock.querySelector('[data-field="start_at"]');
    var monthsInput = sponsorshipBlock.querySelector('[data-field="sponsorship_months"]');
    var endInput = sponsorshipBlock.querySelector('[data-field="end_at"]');
    var note = sponsorshipBlock.querySelector('[data-sponsorship-end-note]');
    if (!startInput || !monthsInput || !endInput) return;

    var computedEndDate = calculateSponsorshipEndDate(startInput.value, monthsInput.value);
    if (!computedEndDate) {
      endInput.value = "";
      if (note) {
        note.textContent = "يتم تحديدها تلقائيًا بعد اختيار البداية وعدد الأشهر.";
      }
      return;
    }

    endInput.value = formatLocalDateTimeInput(computedEndDate);
    if (note) {
      note.textContent = "النهاية المتوقعة: " + formatDateTime(computedEndDate.toISOString());
    }
  }

  function bindSponsorshipAutoEnd() {
    var block = document.querySelector('[data-service-block="sponsorship"]');
    if (!block) return;
    var startInput = block.querySelector('[data-field="start_at"]');
    var monthsInput = block.querySelector('[data-field="sponsorship_months"]');
    if (startInput) {
      startInput.addEventListener("input", function () {
        refreshSponsorshipSchedule(block);
      });
      startInput.addEventListener("change", function () {
        refreshSponsorshipSchedule(block);
      });
    }
    if (monthsInput) {
      monthsInput.addEventListener("input", function () {
        refreshSponsorshipSchedule(block);
      });
      monthsInput.addEventListener("change", function () {
        refreshSponsorshipSchedule(block);
      });
    }
    refreshSponsorshipSchedule(block);
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
        listEl.innerHTML = '<div class="promo-inline-state promo-inline-state-error">تعذر تحميل الطلبات حالياً. حاول التحديث لاحقاً.</div>';
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
      await maybeOpenDeepLinkedRequest();
      maybeShowPaymentReturnNotice();
    } catch (err) {
      loading.style.display = "none";
      listEl.innerHTML = '<div class="promo-inline-state promo-inline-state-error">تعذر تحميل الطلبات حالياً. حاول التحديث لاحقاً.</div>';
    }
  }

  function getDeepLinkedRequestId() {
    try {
      var params = new URLSearchParams(window.location.search || "");
      var requestId = parseInt(params.get("request_id") || "0", 10);
      return requestId > 0 ? requestId : 0;
    } catch (_) {
      return 0;
    }
  }

  function consumeDeepLinkedRequestId() {
    if (!deepLinkedRequestId) return;
    deepLinkedRequestId = 0;
    try {
      var url = new URL(window.location.href);
      url.searchParams.delete("request_id");
      window.history.replaceState({}, "", url.pathname + (url.search || "") + (url.hash || ""));
    } catch (_) {}
  }

  async function maybeOpenDeepLinkedRequest() {
    if (!deepLinkedRequestId) return;

    var request = requestsCache[deepLinkedRequestId];
    if (!request) {
      try {
        var res = await ApiClient.get("/api/promo/requests/" + deepLinkedRequestId + "/");
        if (res && res.ok && res.data && res.data.id) {
          request = res.data;
          requestsCache[request.id] = request;
        }
      } catch (_) {}
    }

    if (!request) {
      consumeDeepLinkedRequestId();
      return;
    }

    preferProviderIdentityFromRequest(request);
    await showRequestDetails(request);
    consumeDeepLinkedRequestId();
  }

  function renderRequestsTable(rows) {
    var html = renderRequestsOverview(rows) +
      '<div class="promo-requests-head">' +
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
    var status = escapeHtml(resolveProviderStatusLabel(row));

    return '<tr data-request-id="' + row.id + '">' +
      '<td><span class="promo-request-code">' + code + '</span></td>' +
      '<td><div class="promo-request-type">' + (requestType || "—") + '</div></td>' +
      '<td><span class="promo-request-date">' + approvedAt + '</span></td>' +
      '<td><span class="promo-status-pill ' + escapeHtml(resolveProviderStatusClass(row)) + '">' + status + '</span></td>' +
      '</tr>';
  }

  function renderRequestsOverview(rows) {
    var reviewCount = 0;
    var paymentCount = 0;
    var activeCount = 0;

    rows.forEach(function (row) {
      var code = resolveProviderStatusCode(row);
      if (code === "quoted" || code === "pending_payment") {
        paymentCount += 1;
        return;
      }
      if (code === "active" || code === "in_progress" || code === "completed") {
        activeCount += 1;
        return;
      }
      reviewCount += 1;
    });

    return '<div class="promo-requests-overview">'
      + '<div class="promo-overview-chip is-primary"><span>إجمالي الطلبات</span><strong>' + rows.length + '</strong></div>'
      + '<div class="promo-overview-chip is-accent"><span>تحت المتابعة</span><strong>' + reviewCount + '</strong></div>'
      + '<div class="promo-overview-chip is-warning"><span>بانتظار الدفع</span><strong>' + paymentCount + '</strong></div>'
      + '<div class="promo-overview-chip is-success"><span>مفعلة أو مكتملة</span><strong>' + activeCount + '</strong></div>'
      + '</div>';
  }

  function resolveProviderStatusClass(row) {
    var code = String(resolveProviderStatusCode(row) || "").trim().toLowerCase();
    if (!code) return "status-default";
    return "status-" + code.replace(/_/g, "-");
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

  function canUploadAssets(row) {
    var status = String((row && row.status) || "").trim();
    return status === "new" || status === "in_review" || status === "rejected";
  }

  function canPreparePayment(row) {
    var invoiceId = parseInt(String((row && row.invoice) || ""), 10);
    var status = String((row && row.status) || "").trim();
    return !invoiceId && row && (status === "new" || status === "in_review");
  }

  function guessAssetContentType(file, assetType) {
    var explicitType = String(file && file.type || "").trim().toLowerCase();
    if (explicitType) return explicitType;
    var ext = String(fileExtension(file && file.name) || "").toLowerCase();
    if (ext === ".jpg" || ext === ".jpeg") return "image/jpeg";
    if (ext === ".png") return "image/png";
    if (ext === ".gif") return "image/gif";
    if (ext === ".mp4") return "video/mp4";
    if (ext === ".pdf") return "application/pdf";
    if (assetType === "video") return "video/mp4";
    if (assetType === "image") return "image/jpeg";
    return "application/octet-stream";
  }

  function uploadToPresignedUrl(opts) {
    return new Promise(function (resolve) {
      var xhr = new XMLHttpRequest();
      var method = String(opts && opts.method || "PUT").toUpperCase();
      var url = String(opts && opts.url || "");
      if (!url) {
        resolve({ ok: false, status: 0 });
        return;
      }
      try {
        xhr.open(method, url, true);
      } catch (_) {
        resolve({ ok: false, status: 0 });
        return;
      }
      xhr.timeout = 180000;
      var headers = opts && opts.headers && typeof opts.headers === "object" ? opts.headers : {};
      Object.keys(headers).forEach(function (key) {
        try {
          xhr.setRequestHeader(key, String(headers[key]));
        } catch (_) {}
      });
      if (xhr.upload && typeof (opts && opts.onProgress) === "function") {
        xhr.upload.addEventListener("progress", function (event) {
          if (!event || !event.lengthComputable || !event.total) return;
          opts.onProgress((event.loaded / event.total) * 100);
        });
      }
      xhr.onload = function () {
        var statusCode = Number(xhr.status || 0);
        resolve({ ok: statusCode >= 200 && statusCode < 300, status: statusCode });
      };
      xhr.onerror = function () {
        resolve({ ok: false, status: Number(xhr.status || 0) });
      };
      xhr.ontimeout = function () {
        resolve({ ok: false, status: 0 });
      };
      xhr.onabort = function () {
        resolve({ ok: false, status: Number(xhr.status || 0) });
      };
      try {
        xhr.send(opts ? opts.file : null);
      } catch (_) {
        resolve({ ok: false, status: 0 });
      }
    });
  }

  async function uploadPromoAssetLegacy(requestId, file, assetType, itemId, title) {
    var fd = new FormData();
    fd.append("file", file, file.name);
    fd.append("asset_type", assetType);
    if (itemId) fd.append("item_id", String(itemId));
    if (title) fd.append("title", String(title));
    return ApiClient.request("/api/promo/requests/" + requestId + "/assets/", {
      method: "POST",
      body: fd,
      formData: true
    });
  }

  async function uploadPromoAssetDirect(requestId, file, assetType, itemId, title, options) {
    var opts = options && typeof options === "object" ? options : {};
    var onStatus = typeof opts.onStatus === "function" ? opts.onStatus : null;
    var onProgress = typeof opts.onProgress === "function" ? opts.onProgress : null;
    if (onStatus) {
      onStatus({
        state: "waiting",
        label: "جاري تجهيز الرفع المباشر",
        detail: "جاري طلب رابط رفع مؤقت...",
        progress: 0
      });
    }
    var initBody = {
      asset_type: assetType,
      file_name: String(file && file.name || "asset"),
      file_size: Number(file && file.size || 0),
      content_type: guessAssetContentType(file, assetType)
    };
    if (itemId) initBody.item_id = String(itemId);
    if (title) initBody.title = String(title);

    var initRes = await ApiClient.request("/api/promo/requests/" + requestId + "/assets/init-upload/", {
      method: "POST",
      body: initBody
    });
    if (!initRes || !initRes.ok) {
      var initDetail = String(
        initRes && initRes.data && (initRes.data.detail || initRes.data.error)
          ? (initRes.data.detail || initRes.data.error)
          : ""
      );
      if (!initRes || initRes.status === 404 || initRes.status === 405) {
        return null;
      }
      if (initRes.status === 400 && initDetail.indexOf("غير متاح") >= 0) {
        return null;
      }
      return initRes;
    }

    var upload = initRes.data && initRes.data.upload ? initRes.data.upload : null;
    var uploadUrl = upload && upload.url ? String(upload.url) : "";
    var objectKey = upload && (upload.object_key || upload.key) ? String(upload.object_key || upload.key) : "";
    if (!uploadUrl || !objectKey) {
      return { ok: false, status: 0, data: { detail: "استجابة الرفع المباشر غير مكتملة." } };
    }
    var uploadMethod = String(upload.method || "PUT").toUpperCase();
    var uploadHeaders = {};
    if (upload.headers && typeof upload.headers === "object") {
      Object.keys(upload.headers).forEach(function (key) {
        uploadHeaders[key] = upload.headers[key];
      });
    }
    var putResponse = null;
    if (onStatus) {
      onStatus({
        state: "uploading",
        label: "جاري رفع الملف إلى التخزين السحابي",
        detail: "يتم الآن رفع الملف مباشرة دون المرور عبر الخادم...",
        progress: 0
      });
    }
    if (onProgress) {
      onProgress(0);
    }
    try {
      putResponse = await uploadToPresignedUrl({
        method: uploadMethod,
        url: uploadUrl,
        headers: uploadHeaders,
        file: file,
        onProgress: onProgress
      });
    } catch (_) {
      putResponse = { ok: false, status: 0 };
    }
    if (!putResponse || !putResponse.ok) {
      var putStatus = putResponse ? Number(putResponse.status || 0) : 0;
      var putErrorDetail = putStatus === 0
        ? "تعذر الاتصال بتخزين الملفات مباشرة. تحقق من إعدادات Cloudflare R2 CORS (السماح بـ PUT/HEAD/POST من نطاق المنصة)."
        : "فشل رفع الملف مباشرة إلى التخزين (رمز " + putStatus + ").";
      return {
        ok: false,
        status: putStatus,
        data: { detail: putErrorDetail }
      };
    }
    if (onProgress) {
      onProgress(100);
    }
    if (onStatus) {
      onStatus({
        state: "waiting",
        label: "جاري تثبيت الملف",
        detail: "تم رفع الملف، وجارٍ ربطه بطلب الترويج...",
        progress: 100
      });
    }

    var completeBody = {
      asset_type: assetType,
      object_key: objectKey,
      content_type: initBody.content_type
    };
    if (itemId) completeBody.item_id = String(itemId);
    if (title) completeBody.title = String(title);
    return ApiClient.request("/api/promo/requests/" + requestId + "/assets/complete-upload/", {
      method: "POST",
      body: completeBody
    });
  }

  async function uploadPromoAsset(requestId, file, assetType, itemId, title, options) {
    var normalizedType = String(assetType || "").trim().toLowerCase();
    var directRes = await uploadPromoAssetDirect(requestId, file, normalizedType, itemId, title, options);
    if (directRes === null) {
      if (normalizedType === "video") {
        return {
          ok: false,
          status: 400,
          data: {
            detail: "فيديوهات الترويج تتطلب رفعًا مباشرًا إلى التخزين السحابي. تعذر استخدام الرفع المباشر حاليًا."
          }
        };
      }
      return uploadPromoAssetLegacy(requestId, file, normalizedType, itemId, title);
    }
    return directRes;
  }

  function updateUploadUi(options, event) {
    var opts = options && typeof options === "object" ? options : {};
    var state = String(event && event.state || "waiting").trim().toLowerCase();
    var label = String(event && event.label || "جاري رفع المرفقات");
    var detail = String(event && event.detail || "");
    var progress = Number(event && event.progress);
    setUploadStatus(state, label, detail, Number.isFinite(progress) ? progress : 0);
    if (opts.submitButton) {
      if (state === "uploading") {
        opts.submitButton.textContent = "جاري الرفع... " + String(Math.max(0, Math.min(100, Math.round(progress || 0)))) + "%";
      } else if (state === "waiting") {
        opts.submitButton.textContent = label;
      } else if (state === "success") {
        opts.submitButton.textContent = "تم رفع المرفقات";
      } else if (state === "failed") {
        opts.submitButton.textContent = "فشل رفع المرفقات";
      }
    }
  }

  async function uploadAssetsToRequest(requestId) {
    var singleItemId = null;
    var singleServiceType = "";
    try {
      var detailRes = await ApiClient.get("/api/promo/requests/" + requestId + "/");
      var detailItems = detailRes && detailRes.ok && detailRes.data && Array.isArray(detailRes.data.items)
        ? detailRes.data.items
        : [];
      if (detailItems.length === 1 && detailItems[0] && detailItems[0].id) {
        singleItemId = detailItems[0].id;
        singleServiceType = String(detailItems[0].service_type || "").trim();
      }
    } catch (_) {}

    var input = document.createElement("input");
    input.type = "file";
    input.accept = ".jpg,.jpeg,.png,.gif,.mp4,.pdf";
    input.multiple = true;
    return new Promise(function (resolve) {
      input.addEventListener("change", async function () {
        var files = input.files ? Array.from(input.files) : [];
        if (!files.length) { resolve(false); return; }
        var failures = [];
        var MAX_RETRIES = 3;
        for (var i = 0; i < files.length; i++) {
          var f = files[i];
          var uploadType = detectAssetType(f.name);
          var statusMeta = {
            submitButton: null,
            fileName: String(f && f.name || "ملف")
          };
          if (isFileTooLargeForService(f, singleServiceType)) {
            failures.push(
              String(f.name || "مرفق")
              + ": حجم الملف أكبر من الحد المسموح (" + resolveUploadLimitMb(singleServiceType, uploadType) + "MB)"
            );
            continue;
          }
          var ok = false;
          var lastRes = null;
          for (var attempt = 0; attempt < MAX_RETRIES && !ok; attempt++) {
            if (attempt > 0) await new Promise(function (r) { setTimeout(r, 1000 * Math.pow(2, attempt - 1)); });
            if (attempt > 0) {
              updateUploadUi(statusMeta, {
                state: "waiting",
                label: "إعادة محاولة الرفع",
                detail: "إعادة رفع " + statusMeta.fileName + " (المحاولة " + (attempt + 1) + " من " + MAX_RETRIES + ")",
                progress: 0
              });
            }
            lastRes = await uploadPromoAsset(requestId, f, uploadType, singleItemId, "", {
              onStatus: function (event) {
                var eventDetail = String(event && event.detail || "").trim();
                updateUploadUi(statusMeta, Object.assign({}, event, {
                  detail: eventDetail ? (statusMeta.fileName + " - " + eventDetail) : statusMeta.fileName
                }));
              },
              onProgress: function (percent) {
                updateUploadUi(statusMeta, {
                  state: "uploading",
                  label: "جاري رفع الملف",
                  detail: statusMeta.fileName,
                  progress: percent
                });
              }
            });
            if (lastRes.ok) ok = true;
          }
          if (ok) {
            updateUploadUi(statusMeta, {
              state: "success",
              label: "اكتمل رفع الملف",
              detail: statusMeta.fileName,
              progress: 100
            });
          } else {
            updateUploadUi(statusMeta, {
              state: "failed",
              label: "فشل رفع الملف",
              detail: statusMeta.fileName,
              progress: 0
            });
            failures.push(f.name + ": " + extractError(lastRes, "تعذر رفع المرفق"));
          }
        }
        if (failures.length) {
          await discardIncompleteRequest(requestId, "manual_asset_upload_failed");
          alert(
            "تم إلغاء الطلب تلقائيًا لأن المرفقات المطلوبة لم تكتمل.\n"
            + "الأخطاء:\n" + failures.join("\n")
          );
        } else {
          alert("تم رفع جميع المرفقات بنجاح.");
        }
        resolve(true);
      });
      input.click();
    });
  }

  async function showRequestDetails(row) {
    var detailRow = row;
    try {
      var res = await ApiClient.get("/api/promo/requests/" + row.id + "/");
      if (res && res.ok && res.data && res.data.id) detailRow = res.data;
    } catch (_) {}
    preferProviderIdentityFromRequest(detailRow);

    var confirmLabel = null;
    if (canPayRequest(detailRow)) {
      confirmLabel = "الدفع الآن";
    } else if (canPreparePayment(detailRow)) {
      confirmLabel = "تجهيز الدفع";
    }

    var bodyHtml = buildRequestDetailsHtml(detailRow);
    if (canUploadAssets(detailRow)) {
      bodyHtml += '<div class="promo-modal-section" style="text-align:center;padding-top:12px">'
        + '<button type="button" class="btn btn-secondary" id="promo-detail-upload-btn" style="background:#663d90;color:#fff;padding:8px 20px;border:none;border-radius:8px;font-size:.95rem;cursor:pointer">رفع مرفقات إضافية</button>'
        + '</div>';
    }

    var modalPromise = openModal({
      title: detailRow.title || "طلب ترويج",
      bodyHtml: bodyHtml,
      confirmText: confirmLabel,
      cancelText: "إغلاق"
    });

    // Bind upload button while modal is open (before awaiting user action)
    var uploadBtn = document.getElementById("promo-detail-upload-btn");
    if (uploadBtn) {
      uploadBtn.addEventListener("click", async function () {
        var uploaded = await uploadAssetsToRequest(detailRow.id);
        if (uploaded) {
          closeModal(false);
          await showRequestDetails(row);
        }
      });
    }

    var confirmed = await modalPromise;

    if (confirmed) {
      if (canPayRequest(detailRow)) {
        await startPayment(detailRow);
      } else if (canPreparePayment(detailRow)) {
        var prepared = await preparePromoRequestPayment(detailRow.id);
        if (prepared && prepared.invoice) {
          goToPromotionPaymentPage(detailRow.id, prepared.invoice);
        } else {
          alert("تعذر تجهيز الفاتورة. حاول مرة أخرى.");
        }
      }
    }
  }

  function buildRequestDetailsHtml(row) {
    var items = Array.isArray(row.items) ? row.items : [];
    var assets = Array.isArray(row.assets) ? row.assets : [];
    var parts = [
      '<div class="promo-modal-section">',
      lineHtml("رقم الطلب", row.code || ""),
      lineHtml("الحالة", resolveProviderStatusLabel(row)),
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
    if (item.use_chat_channel) h += '<span style="background:#e3f2fd;color:#1565c0;padding:2px 8px;border-radius:10px;font-size:.8rem">رسائل</span>';
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
        goToPromotionPaymentPage(
          parseInt(String(pendingPayment.requestId || "0"), 10) || 0,
          parseInt(String(pendingPayment.invoiceId || "0"), 10) || 0
        );
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
        var redirected = await payPreparedInvoice();
        if (!redirected) return;
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
      resetUploadStatus();
      if (!selectedServices.length) {
        alert("اختر خدمة واحدة على الأقل");
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
        var requestBody = Object.assign({ items: items }, collectHomeBannerScalePayload());

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
    var createdRequestId = 0;
    if (!submitButton) return false;
    try {
      submitButton.textContent = "جاري إنشاء الطلب...";
      var createResult = await createRequestWithAssets(requestBody, submitButton);
      if (!createResult) {
        return false;
      }
      createdRequestId = parseInt(String(createResult.requestId || "0"), 10) || 0;

      if (createResult.uploadFailures.length) {
        setUploadStatus(
          "failed",
          "فشل رفع المرفقات",
          String(createResult.uploadFailures[0] || "تعذر رفع المرفقات المطلوبة."),
          0
        );
        await discardIncompleteRequest(createdRequestId, "asset_upload_failed");
        alert(
          "تم إلغاء الطلب تلقائيًا لأن المرفقات المطلوبة لم تكتمل.\n"
          + "سبب الفشل: " + String(createResult.uploadFailures[0] || "تعذر رفع المرفق.")
        );
        return false;
      }

      submitButton.textContent = "جاري تجهيز الفاتورة...";
      var prepared = await preparePromoRequestPayment(createResult.requestId);
      if (!prepared) {
        await discardIncompleteRequest(createdRequestId, "prepare_payment_failed");
        alert("تم إلغاء الطلب تلقائيًا لأن الدفع لم يُجهّز بنجاح.");
        return false;
      }
      var invoiceId = parseInt(String(prepared.invoice || ""), 10);
      if (!invoiceId) {
        await discardIncompleteRequest(createdRequestId, "missing_invoice_id");
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
      goToPromotionPaymentPage(createResult.requestId, invoiceId);
      return true;
    } catch (err) {
      console.error("Submit flow failed", err);
      if (createdRequestId) {
        await discardIncompleteRequest(createdRequestId, "submit_flow_exception");
      }
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
    var singleItemId = detailItems.length === 1 && detailItems[0] && detailItems[0].id
      ? detailItems[0].id
      : null;

    var uploadFailures = [];
    submitButton.textContent = "جاري رفع المرفقات...";
    setUploadStatus("waiting", "جاري تجهيز رفع المرفقات", "يتم تجهيز رفع الملفات مباشرة إلى التخزين السحابي.", 0);
    var MAX_UPLOAD_RETRIES = 3;
    for (var x = 0; x < selectedServices.length; x += 1) {
      var s = selectedServices[x];
      var sBlock = document.querySelector('[data-service-block="' + s + '"]');
      var fileInput = sBlock ? sBlock.querySelector('[data-field="files"]') : null;
      var files = fileInput && fileInput.files ? Array.from(fileInput.files) : [];
      for (var y = 0; y < files.length; y += 1) {
        var sourceFile = files[y];
        if (isFileTooLargeForService(sourceFile, s)) {
          uploadFailures.push(
            String(sourceFile.name || "مرفق")
            + ": حجم الملف أكبر من الحد المسموح (" + resolveUploadLimitMb(s, detectAssetType(sourceFile.name)) + "MB)"
          );
          continue;
        }
        var uploadFile = sourceFile;
        var uploadType = detectAssetType(sourceFile.name);
        var statusMeta = {
          submitButton: submitButton,
          fileName: String(uploadFile && uploadFile.name || "ملف")
        };
        var uploadOk = false;
        var lastUploadRes = null;
        for (var attempt = 0; attempt < MAX_UPLOAD_RETRIES && !uploadOk; attempt += 1) {
          if (attempt > 0) {
            submitButton.textContent = "إعادة محاولة رفع " + uploadFile.name + " (" + (attempt + 1) + "/" + MAX_UPLOAD_RETRIES + ")...";
            updateUploadUi(statusMeta, {
              state: "waiting",
              label: "إعادة محاولة الرفع",
              detail: "إعادة رفع " + statusMeta.fileName + " (المحاولة " + (attempt + 1) + " من " + MAX_UPLOAD_RETRIES + ")",
              progress: 0
            });
            await new Promise(function (r) { setTimeout(r, 1000 * Math.pow(2, attempt - 1)); });
          }
          var itemIdForUpload = ids[s + ":" + x] ? String(ids[s + ":" + x]) : (singleItemId ? String(singleItemId) : null);
          lastUploadRes = await uploadPromoAsset(
            requestId,
            uploadFile,
            uploadType,
            itemIdForUpload,
            SERVICE_LABELS[s] || s || "",
            {
              onStatus: function (event) {
                var eventDetail = String(event && event.detail || "").trim();
                updateUploadUi(statusMeta, Object.assign({}, event, {
                  detail: eventDetail ? (statusMeta.fileName + " - " + eventDetail) : statusMeta.fileName
                }));
              },
              onProgress: function (percent) {
                updateUploadUi(statusMeta, {
                  state: "uploading",
                  label: "جاري الرفع المباشر",
                  detail: statusMeta.fileName,
                  progress: percent
                });
              }
            }
          );
          if (lastUploadRes.ok) uploadOk = true;
        }
        if (!uploadOk) {
          updateUploadUi(statusMeta, {
            state: "failed",
            label: "فشل رفع الملف",
            detail: statusMeta.fileName,
            progress: 0
          });
          uploadFailures.push((uploadFile.name || "ملف") + ": " + extractError(lastUploadRes, "تعذر رفع المرفق"));
        } else {
          updateUploadUi(statusMeta, {
            state: "success",
            label: "اكتمل رفع الملف",
            detail: statusMeta.fileName,
            progress: 100
          });
        }
      }
    }

    if (!uploadFailures.length) {
      setUploadStatus("success", "اكتمل رفع المرفقات", "تم رفع جميع الملفات وربطها بالطلب.", 100);
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

  async function discardIncompleteRequest(requestId, reason) {
    var id = parseInt(String(requestId || "0"), 10) || 0;
    if (!id) return false;
    try {
      var res = await ApiClient.request("/api/promo/requests/" + id + "/discard/", {
        method: "DELETE",
        body: reason ? { reason: String(reason) } : undefined
      });
      return !!(res && res.ok);
    } catch (_) {
      return false;
    }
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
      body: { provider: "mock", idempotency_key: idempotencyKey, payment_method: pendingPayment.paymentMethod || "mada" }
    });
    if (!initRes.ok) {
      alert(extractError(initRes, "تعذر فتح صفحة الدفع"));
      return false;
    }
    var attempt = initRes.data || {};
    var checkoutUrl = checkoutUrlWithNext(attempt.checkout_url, requestId);
    if (!checkoutUrl) {
      alert("تعذر تحويلك إلى صفحة الدفع الفعلية.");
      return false;
    }
    window.location.href = checkoutUrl;
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
        if (isFileTooLargeForService(file, service)) {
          var uploadType = detectAssetType(String(file.name || ""));
          return "الملف " + String(file.name || "المرفق")
            + " أكبر من الحد المسموح (" + resolveUploadLimitMb(service, uploadType) + "MB).";
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

    if (homeBannerAutoFitEnabled()) {
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
    function localDate(name) {
      var val = valueOf(field(name));
      if (!val) return null;
      var parsed = new Date(val);
      return isNaN(parsed.getTime()) ? null : parsed;
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

    if (["home_banner", "featured_specialists", "portfolio_showcase", "snapshots", "search_results"].indexOf(service) >= 0) {
      body.start_at = localIso("start_at");
      body.end_at = localIso("end_at");
      if (!body.start_at || !body.end_at) return "حدد البداية والنهاية لكل خدمة مختارة";
    }
    if (["featured_specialists", "portfolio_showcase", "snapshots"].indexOf(service) >= 0) {
      body.title = body.title || (SERVICE_LABELS[service] || service);
    }
    if (service === "search_results") {
      body.search_scopes = checkedValues("search_scopes");
      if (!body.search_scopes.length) return "اختر قائمة ظهور واحدة على الأقل";
      body.search_scope = body.search_scopes[0];
      body.search_position = valueOf(field("search_position")) || "first";
      body.target_category = valueOf(field("target_category"));
    }
    if (service === "promo_messages") {
      var sendAtDate = localDate("send_at");
      body.send_at = sendAtDate ? sendAtDate.toISOString() : "";
      if (!body.send_at) return "حدد وقت الإرسال للرسائل الدعائية";
      if (sendAtDate.getTime() <= Date.now()) {
        return "وقت إرسال الرسائل الدعائية يجب أن يكون في المستقبل.";
      }
      body.use_notification_channel = !!(field("use_notification_channel") && field("use_notification_channel").checked);
      body.use_chat_channel = !!(field("use_chat_channel") && field("use_chat_channel").checked);
      if (!body.use_notification_channel && !body.use_chat_channel) return "اختر قناة واحدة على الأقل للرسائل الدعائية";
      body.message_body = valueOf(field("message_body"));
      if (!body.message_body && !body.asset_count) return "أدخل نص الرسالة أو أرفق مادة دعائية واحدة على الأقل";
      body.attachment_specs = valueOf(field("attachment_specs"));
    }
    if (service === "sponsorship") {
      body.start_at = localIso("start_at");
      body.sponsor_name = valueOf(field("sponsor_name"));
      body.sponsorship_months = parseInt(valueOf(field("sponsorship_months")) || "0", 10);
      body.end_at = calculateSponsorshipEndIso(valueOf(field("start_at")), body.sponsorship_months);
      body.redirect_url = valueOf(field("redirect_url"));
      body.message_body = valueOf(field("message_body"));
      body.attachment_specs = valueOf(field("attachment_specs"));
      refreshSponsorshipSchedule(block);
      if (!body.start_at || !body.end_at) return "حدد تاريخ بداية الرعاية ومدة الأشهر ليتم احتساب النهاية تلقائيًا";
      if (!body.sponsor_name || body.sponsorship_months <= 0) return "أكمل بيانات الرعاية";
      if (!body.message_body) return "اكتب نص رسالة الرعاية";
      if (!body.asset_count) return "أضف شعار الراعي أو ملفات الرعاية";
    }
    if (service === "home_banner") {
      body.redirect_url = valueOf(field("redirect_url"));
      body.attachment_specs = valueOf(field("attachment_specs"));
      if (!body.asset_count) return "أضف مرفقات البانر قبل المتابعة";
    }
    if (service === "portfolio_showcase" || service === "snapshots") {
      var targetFieldName = service === "snapshots" ? "target_spotlight_item_id" : "target_portfolio_item_id";
      body[targetFieldName] = parseInt(valueOf(field(targetFieldName)) || "0", 10);
      if (!body[targetFieldName]) {
        return service === "snapshots"
          ? "اختر ريلًا واحدًا من اللمحات لشريط اللمحات"
          : "اختر صورة واحدة من معرض الأعمال لهذا الشريط";
      }
      body.asset_count = 0;
    }
    return body;
  }

  function buildSelectedGalleryPreviewHtml(service) {
    if (service !== "portfolio_showcase" && service !== "snapshots") {
      return "";
    }
    var selected = selectedPortfolioItemForService(service);
    if (!selected) {
      return "";
    }
    var mediaUrl = resolveMediaUrl(selected.file_url || selected.thumbnail_url || "");
    if (!mediaUrl) {
      return "";
    }
    var fileType = String(selected.file_type || "image").toLowerCase();
    var caption = String(selected.caption || (fileType === "video" ? "فيديو من معرض الأعمال" : "صورة من معرض الأعمال")).trim() || "عنصر من معرض الأعمال";
    var title = service === "snapshots" ? "الريل المختار لشريط اللمحات" : "الصورة المختارة لشريط البنرات والمشاريع";
    var mediaHtml = fileType === "video"
      ? '<video src="' + escapeHtml(resolveMediaUrl(selected.file_url || selected.thumbnail_url || "")) + '" controls playsinline preload="metadata"' + (selected.thumbnail_url ? ' poster="' + escapeHtml(resolveMediaUrl(selected.thumbnail_url)) + '"' : '') + '></video>'
      : '<img src="' + escapeHtml(mediaUrl) + '" alt="' + escapeHtml(caption) + '">';
    return ''
      + '<div class="promo-modal-section promo-modal-selected-media">'
      + '  <h4>' + escapeHtml(title) + '</h4>'
      + '  <div class="promo-modal-selected-media-frame">'
      + mediaHtml
      + '  </div>'
      + '  <div class="promo-modal-selected-media-caption">' + escapeHtml(caption) + '</div>'
      + '</div>';
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
    var requestId = parseInt(String((row && row.id) || ""), 10);
    var invoiceId = parseInt(String((row && row.invoice) || ""), 10);
    if (!requestId && !invoiceId) {
      alert("لا توجد فاتورة أو طلب صالح لإتمام الدفع");
      return;
    }
    goToPromotionPaymentPage(requestId || 0, invoiceId || 0);
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
      '<p class="promo-note">سيتم تحويلك إلى صفحة الدفع لإتمام السداد. بعد نجاح الدفع لا يتم تفعيل الحملة مباشرة، بل تبقى بانتظار مراجعة واعتماد فريق الترويج حتى تكون حالة الفاتورة مدفوعة وحالة الطلب مكتملة.</p>'
    );
  }

  function resetForm() {
    resetUploadStatus();
    if (homeBannerEditor.previewUrl) {
      try { URL.revokeObjectURL(homeBannerEditor.previewUrl); } catch (e) {}
    }
    homeBannerEditor.previewUrl = "";
    portfolioPickerState.portfolio_showcase = { loaded: false, loading: false, items: [], selectedId: 0 };
    portfolioPickerState.snapshots = { loaded: false, loading: false, items: [], selectedId: 0 };

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
    ["portfolio_showcase", "snapshots"].forEach(function (service) {
      var elements = getGalleryPickerElements(service);
      if (!elements) return;
      if (elements.grid) {
        elements.grid.innerHTML = "";
        elements.grid.hidden = true;
      }
      if (elements.loading) elements.loading.hidden = true;
      if (elements.error) {
        elements.error.hidden = true;
        elements.error.textContent = "";
      }
      if (elements.empty) elements.empty.hidden = true;
      if (elements.selection) {
        elements.selection.hidden = true;
        elements.selection.textContent = "";
      }
      if (elements.hiddenInput) elements.hiddenInput.value = "";
      if (elements.previewWrap) elements.previewWrap.hidden = true;
      if (elements.previewImage) {
        elements.previewImage.hidden = true;
        elements.previewImage.removeAttribute("src");
      }
      if (elements.previewVideo) {
        elements.previewVideo.hidden = true;
        elements.previewVideo.pause();
        elements.previewVideo.removeAttribute("src");
        elements.previewVideo.removeAttribute("poster");
        elements.previewVideo.load();
      }
      if (elements.previewEmpty) elements.previewEmpty.hidden = false;
      if (elements.previewCaption) {
        elements.previewCaption.textContent = previewCaptionForService(service, null);
      }
    });
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

  function normalizeLimitMb(value, fallback) {
    var parsed = parseInt(String(value || ""), 10);
    if (!Number.isFinite(parsed) || parsed <= 0) return fallback;
    return parsed;
  }

  function applyAssetUploadLimitsFromGuide(data) {
    var incoming = data && data.asset_upload_limits_mb;
    if (!incoming || typeof incoming !== "object") return;
    PROMO_ASSET_UPLOAD_LIMITS_MB.image = normalizeLimitMb(incoming.image, PROMO_ASSET_UPLOAD_LIMITS_MB.image);
    PROMO_ASSET_UPLOAD_LIMITS_MB.video = normalizeLimitMb(incoming.video, PROMO_ASSET_UPLOAD_LIMITS_MB.video);
    PROMO_ASSET_UPLOAD_LIMITS_MB.pdf = normalizeLimitMb(incoming.pdf, PROMO_ASSET_UPLOAD_LIMITS_MB.pdf);
    PROMO_ASSET_UPLOAD_LIMITS_MB.other = normalizeLimitMb(incoming.other, PROMO_ASSET_UPLOAD_LIMITS_MB.other);
    PROMO_ASSET_UPLOAD_LIMITS_MB.home_banner_image = normalizeLimitMb(
      incoming.home_banner_image,
      PROMO_ASSET_UPLOAD_LIMITS_MB.home_banner_image
    );
    PROMO_ASSET_UPLOAD_LIMITS_MB.home_banner_video = normalizeLimitMb(
      incoming.home_banner_video,
      PROMO_ASSET_UPLOAD_LIMITS_MB.home_banner_video
    );
  }

  function resolveUploadLimitMb(service, assetType) {
    var type = String(assetType || "other").trim().toLowerCase();
    if (["image", "video", "pdf", "other"].indexOf(type) < 0) type = "other";
    if (service === "home_banner") {
      if (type === "video") return PROMO_ASSET_UPLOAD_LIMITS_MB.home_banner_video;
      return PROMO_ASSET_UPLOAD_LIMITS_MB.home_banner_image;
    }
    return PROMO_ASSET_UPLOAD_LIMITS_MB[type] || PROMO_ASSET_UPLOAD_LIMITS_MB.other || 10;
  }

  function isFileTooLargeForService(file, service) {
    var size = Number(file && file.size ? file.size : 0);
    if (!Number.isFinite(size) || size <= 0) return false;
    var assetType = detectAssetType(String(file && file.name || ""));
    var maxMb = resolveUploadLimitMb(service, assetType);
    var maxBytes = maxMb * 1024 * 1024;
    return size > maxBytes;
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

  function resolveMediaUrl(url) {
    var value = String(url || "").trim();
    if (!value) return "";
    if (window.ApiClient && typeof window.ApiClient.mediaUrl === "function") {
      return window.ApiClient.mediaUrl(value);
    }
    return value;
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

    if (!selectedServices.length) {
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
      var requestBody = Object.assign({ items: items }, collectHomeBannerScalePayload());
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

    var payload = buildServicePayload(service, block, idx);
    if (typeof payload === "string") {
      alert(SERVICE_LABELS[service] + ": " + payload);
      return;
    }

    var requestBody = Object.assign({ items: [payload] }, collectHomeBannerScalePayload());
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
      buildSelectedGalleryPreviewHtml(service) +
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
