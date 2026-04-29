"use strict";
var AdditionalServicesPage = (function () {
  var SECTION_ORDER = ["reports", "clients", "finance"];

  var PURCHASE_STATUS_LABELS = {
    pending_payment: "بانتظار الدفع",
    active: "نشط",
    consumed: "مستهلك",
    expired: "منتهي",
    cancelled: "ملغي"
  };

  var PURCHASE_STATUS_COLORS = {
    pending_payment: "#B45309",
    active: "#15803D",
    consumed: "#1D4ED8",
    expired: "#6B7280",
    cancelled: "#B91C1C"
  };

  var REQUEST_STATUS_COLORS = {
    new: "#0369A1",
    in_progress: "#B45309",
    returned: "#B91C1C",
    closed: "#15803D"
  };

  var endpoints = {
    catalogUrl: "/api/extras/catalog/",
    myUrl: "/api/extras/my/",
    meUrl: "/api/accounts/me/",
    buyUrlTemplate: "/api/extras/buy/__SKU__/",
    bundleCreateUrl: "/api/extras/bundle-requests/",
    bundleMyUrl: "/api/extras/bundle-requests/my/",
    portalHomeUrl: "/portal/extras/"
  };

  var state = {
    loading: true,
    loadingSilent: false,
    bundleHistoryLoading: false,
    activeSection: "reports",
    catalogItems: [],
    myExtras: [],
    bundleHistory: [],
    buyingSkus: {},
    submitPending: false,
    paymentReturnHandled: false,
    optionGroups: {
      reports: { title: "خدمات التقارير", items: [] },
      clients: { title: "خدمات إدارة العملاء", items: [] },
      finance: { title: "خدمات الإدارة المالية", items: [] }
    },
    form: emptyForm()
  };

  function emptyForm() {
    return {
      reports: {
        enabled: false,
        options: [],
        start_at: "",
        end_at: ""
      },
      clients: {
        enabled: false,
        options: [],
        subscription_years: 1,
        bulk_message_count: 0
      },
      finance: {
        enabled: false,
        options: [],
        subscription_years: 1
      },
      notes: ""
    };
  }

  function asText(value) {
    if (value === null || value === undefined) return "";
    return String(value).trim();
  }

  function asInt(value, fallback) {
    var n = Number(value);
    if (Number.isFinite(n)) return Math.trunc(n);
    return typeof fallback === "number" ? fallback : 0;
  }

  function clampInt(value, min, max) {
    var n = asInt(value, min);
    if (n < min) return min;
    if (n > max) return max;
    return n;
  }

  function asList(payload) {
    if (Array.isArray(payload)) return payload;
    if (payload && Array.isArray(payload.results)) return payload.results;
    return [];
  }

  function normalizeOptionItems(items) {
    if (!Array.isArray(items)) return [];
    return items
      .map(function (item) {
        var key = asText(item && item.key);
        var label = asText(item && item.label);
        if (!key || !label) return null;
        return { key: key, label: label, unavailable: Boolean(item && item.unavailable) };
      })
      .filter(Boolean);
  }

  function parseOptionGroups() {
    var script = document.getElementById("as-option-groups");
    if (!script) return;
    try {
      var parsed = JSON.parse(script.textContent || "{}");
      for (var i = 0; i < SECTION_ORDER.length; i++) {
        var groupKey = SECTION_ORDER[i];
        var group = parsed && parsed[groupKey];
        if (!group || typeof group !== "object") continue;
        state.optionGroups[groupKey] = {
          title: asText(group.title) || state.optionGroups[groupKey].title,
          items: normalizeOptionItems(group.items)
        };
      }
    } catch (_) {
      // Keep default groups if JSON payload is malformed.
    }
  }

  function readConfig() {
    var root = document.getElementById("as-config");
    if (!root) return;
    endpoints.catalogUrl = asText(root.getAttribute("data-catalog-url")) || endpoints.catalogUrl;
    endpoints.myUrl = asText(root.getAttribute("data-my-url")) || endpoints.myUrl;
    endpoints.meUrl = asText(root.getAttribute("data-me-url")) || endpoints.meUrl;
    endpoints.buyUrlTemplate = asText(root.getAttribute("data-buy-url-template")) || endpoints.buyUrlTemplate;
    endpoints.bundleCreateUrl = asText(root.getAttribute("data-bundle-create-url")) || endpoints.bundleCreateUrl;
    endpoints.bundleMyUrl = asText(root.getAttribute("data-bundle-my-url")) || endpoints.bundleMyUrl;
    endpoints.portalHomeUrl = asText(root.getAttribute("data-portal-home-url")) || endpoints.portalHomeUrl;
  }

  function pickProviderDisplayName(payload) {
    var data = payload && typeof payload === "object" ? payload : {};
    var profile = (data.provider_profile && typeof data.provider_profile === "object") ? data.provider_profile : null;
    var direct = asText(data.provider_display_name) || asText(profile && profile.display_name);
    if (direct) return direct;

    var full = asText(data.full_name);
    if (full) return full;

    var first = asText(data.first_name);
    var last = asText(data.last_name);
    return [first, last].filter(Boolean).join(" ").trim();
  }

  async function hydrateProviderDisplayName() {
    var valueEl = document.querySelector(".as-provider-value");
    if (!valueEl) return;

    var current = asText(valueEl.textContent);
    if (current && current !== "-" && current !== "—") return;

    try {
      var res = await ApiClient.get(endpoints.meUrl);
      if (!res || !res.ok) return;
      var providerName = pickProviderDisplayName(res.data);
      if (providerName) {
        valueEl.textContent = providerName;
      }
    } catch (_) {
      // Keep the existing placeholder if account data is unavailable.
    }
  }

  function statusCode(value) {
    return asText(value).toLowerCase();
  }

  function purchaseStatusLabel(value) {
    return PURCHASE_STATUS_LABELS[statusCode(value)] || "غير معروف";
  }

  function purchaseStatusColor(value) {
    return PURCHASE_STATUS_COLORS[statusCode(value)] || "#374151";
  }

  function requestStatusColor(value) {
    return REQUEST_STATUS_COLORS[statusCode(value)] || "#374151";
  }

  function escapeHtml(value) {
    return asText(value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/\"/g, "&quot;")
      .replace(/'/g, "&#039;");
  }

  function formatDate(raw) {
    var text = asText(raw);
    if (!text) return "—";
    var parsed = new Date(text);
    if (Number.isNaN(parsed.getTime())) return text;
    return parsed.toLocaleDateString("ar-SA");
  }

  function formatDateTime(raw) {
    var text = asText(raw);
    if (!text) return "—";
    var parsed = new Date(text);
    if (Number.isNaN(parsed.getTime())) return text;
    return parsed.toLocaleString("ar-SA", { hour: "2-digit", minute: "2-digit" });
  }

  function formatPrice(value, currency) {
    var amount = asText(value);
    if (!amount) amount = "0";
    var curr = asText(currency).toUpperCase();
    var suffix = curr && curr !== "SAR" ? curr : "ر.س";
    return amount + " " + suffix;
  }

  function searchParams() {
    try {
      return new URLSearchParams(window.location.search || "");
    } catch (_) {
      return new URLSearchParams("");
    }
  }

  function paymentReturnRequestId() {
    var params = searchParams();
    if (asText(params.get("payment")).toLowerCase() !== "success") return 0;
    return asInt(params.get("request_id"), 0);
  }

  function clearPaymentReturnParams() {
    if (!window.history || typeof window.history.replaceState !== "function") return;
    try {
      var url = new URL(window.location.href);
      url.searchParams.delete("payment");
      url.searchParams.delete("request_id");
      url.searchParams.delete("invoice_id");
      window.history.replaceState({}, document.title, url.pathname + url.search + url.hash);
    } catch (_) {
      // Keep the current URL if replacement fails.
    }
  }

  function scrollToBundleHistory(requestId) {
    var section = document.getElementById("as-bundle-history-section") || document.getElementById("as-bundle-history");
    if (section && typeof section.scrollIntoView === "function") {
      section.scrollIntoView({ behavior: "smooth", block: "start" });
    }

    if (!requestId) return;
    window.setTimeout(function () {
      var card = document.querySelector('.as-card-bundle[data-request-id="' + String(requestId) + '"]');
      if (!card) return;
      card.classList.add("as-card-highlight");
      if (typeof card.scrollIntoView === "function") {
        card.scrollIntoView({ behavior: "smooth", block: "center" });
      }
    }, 260);
  }

  function maybeHandlePaymentReturn() {
    if (state.paymentReturnHandled) return;
    var requestId = paymentReturnRequestId();
    if (!requestId) return;

    state.paymentReturnHandled = true;
    var matched = state.bundleHistory.find(function (item) {
      return asInt(item && item.request_id, 0) === requestId;
    }) || null;

    showSuccess(matched || { request_code: "—", status_label: "تحت المعالجة" }, {
      eyebrow: "تم السداد بنجاح",
      message: "تم تسجيل السداد لهذا الطلب بنجاح، والطلب الآن قيد المعالجة لدى فريق الخدمات الإضافية حتى اكتمال التنفيذ.",
      statusText: "الطلب قيد المعالجة وسنتابع تحديثه لك في هذه الصفحة.",
      closeLabel: "عرض الطلب"
    });
    scrollToBundleHistory(requestId);
    clearPaymentReturnParams();
  }

  function extractErrorMessage(res, fallback) {
    if (!res) return fallback;
    var data = res.data || {};
    if (typeof data === "string" && data.trim()) return data.trim();
    if (asText(data.detail)) return asText(data.detail);
    if (asText(data.message)) return asText(data.message);
    if (typeof data.non_field_errors === "string" && data.non_field_errors) return data.non_field_errors;
    if (Array.isArray(data.non_field_errors) && data.non_field_errors.length) return asText(data.non_field_errors[0]);
    if (typeof data === "object") {
      var keys = Object.keys(data);
      for (var i = 0; i < keys.length; i++) {
        var value = data[keys[i]];
        if (Array.isArray(value) && value.length) return asText(value[0]);
        if (asText(value)) return asText(value);
      }
    }
    return fallback;
  }

  function latestPurchaseBySku() {
    var sorted = state.myExtras.slice().sort(function (a, b) {
      return asInt(b.id) - asInt(a.id);
    });
    var map = {};
    for (var i = 0; i < sorted.length; i++) {
      var item = sorted[i];
      var sku = asText(item && item.sku);
      if (!sku) continue;
      if (!map[sku]) map[sku] = item;
    }
    return map;
  }

  function setLoading(value, silent) {
    state.loading = value;
    state.loadingSilent = !!silent;
    var loadingEl = document.getElementById("as-loading");
    var contentEl = document.getElementById("as-content");
    if (!loadingEl || !contentEl) return;

    if (value && !state.loadingSilent) {
      loadingEl.hidden = false;
      loadingEl.style.display = "flex";
      contentEl.hidden = true;
      contentEl.style.display = "none";
      return;
    }

    loadingEl.hidden = true;
    loadingEl.style.display = "none";
    contentEl.hidden = false;
    contentEl.style.display = "block";
  }

  function setError(message) {
    var errorEl = document.getElementById("as-error");
    if (!errorEl) return;
    if (message) {
      errorEl.textContent = message;
      errorEl.hidden = false;
      return;
    }
    errorEl.hidden = true;
    errorEl.textContent = "";
  }

  function setSubmitError(message) {
    var errorEl = document.getElementById("as-submit-error");
    if (!errorEl) return;
    if (message) {
      errorEl.textContent = message;
      errorEl.hidden = false;
      return;
    }
    errorEl.hidden = true;
    errorEl.textContent = "";
  }

  function buyUrlForSku(sku) {
    return endpoints.buyUrlTemplate.replace("__SKU__", encodeURIComponent(sku));
  }

  function isOptionSelected(groupKey, optionKey) {
    var options = state.form[groupKey] && state.form[groupKey].options;
    if (!Array.isArray(options)) return false;
    return options.indexOf(optionKey) >= 0;
  }

  function selectedCount(groupKey) {
    var options = state.form[groupKey] && state.form[groupKey].options;
    return Array.isArray(options) ? options.length : 0;
  }

  function optionLabelMap(groupKey) {
    var map = {};
    var group = state.optionGroups[groupKey];
    var items = group && Array.isArray(group.items) ? group.items : [];
    for (var i = 0; i < items.length; i++) {
      map[items[i].key] = items[i].label;
    }
    return map;
  }

  function renderOptionsGroup(groupKey, rootId) {
    var root = document.getElementById(rootId);
    if (!root) return;
    var group = state.optionGroups[groupKey] || { items: [] };
    var items = Array.isArray(group.items) ? group.items : [];
    if (!items.length) {
      root.innerHTML = '<div class="as-empty">لا توجد خيارات متاحة حالياً.</div>';
      return;
    }

    root.innerHTML = items.map(function (item) {
      var isUnavailable = Boolean(item.unavailable);
      var checked = !isUnavailable && isOptionSelected(groupKey, item.key);
      if (isUnavailable) {
        return [
          '<label class="as-option-item is-unavailable" title="قريباً">',
            '<input class="as-option-checkbox" type="checkbox" data-group="', escapeHtml(groupKey), '" data-option="', escapeHtml(item.key), '" disabled />',
            '<span>', escapeHtml(item.label), '</span>',
            '<span class="as-coming-soon-badge">قريباً</span>',
          '</label>'
        ].join("");
      }
      return [
        '<label class="as-option-item', checked ? ' is-selected' : '', '">',
          '<input class="as-option-checkbox" type="checkbox" data-group="', escapeHtml(groupKey), '" data-option="', escapeHtml(item.key), '"', checked ? ' checked' : '', ' />',
          '<span>', escapeHtml(item.label), '</span>',
        '</label>'
      ].join("");
    }).join("");
  }

  function renderSectionVisibility() {
    var cards = document.querySelectorAll("#as-main-cards .as-main-card");
    for (var i = 0; i < cards.length; i++) {
      var card = cards[i];
      var section = asText(card.getAttribute("data-section"));
      var active = section === state.activeSection;
      card.classList.toggle("is-active", active);
      card.setAttribute("aria-selected", active ? "true" : "false");
      card.classList.toggle("has-selection", selectedCount(section) > 0);
    }

    var panels = document.querySelectorAll(".as-section-panel");
    for (var j = 0; j < panels.length; j++) {
      var panel = panels[j];
      var panelSection = asText(panel.getAttribute("data-section-panel"));
      var show = panelSection === state.activeSection;
      panel.hidden = !show;
      panel.classList.toggle("is-active", show);
    }
  }

  function renderCardCounters() {
    for (var i = 0; i < SECTION_ORDER.length; i++) {
      var key = SECTION_ORDER[i];
      var el = document.getElementById("as-card-count-" + key);
      if (!el) continue;
      var count = selectedCount(key);
      el.textContent = String(count);
      el.classList.toggle("is-filled", count > 0);
    }
  }

  function renderSubmitState() {
    var submitBtn = document.getElementById("as-submit");
    if (!submitBtn) return;
    submitBtn.disabled = state.submitPending;
    submitBtn.textContent = state.submitPending ? "جاري الإرسال..." : "إرسال الطلب";
  }

  function readFormInputs() {
    var reportsStart = document.getElementById("as-reports-start");
    var reportsEnd = document.getElementById("as-reports-end");
    var clientsYears = document.getElementById("as-clients-years");
    var clientsBulk = document.getElementById("as-clients-bulk");
    var financeYears = document.getElementById("as-finance-years");
    var notes = document.getElementById("as-notes");

    state.form.reports.start_at = asText(reportsStart && reportsStart.value);
    state.form.reports.end_at = asText(reportsEnd && reportsEnd.value);
    state.form.clients.subscription_years = clampInt(clientsYears && clientsYears.value, 1, 5);
    state.form.clients.bulk_message_count = Math.max(0, asInt(clientsBulk && clientsBulk.value, 0));
    state.form.finance.subscription_years = clampInt(financeYears && financeYears.value, 1, 5);
    state.form.notes = asText(notes && notes.value);
  }

  function renderFormInputs() {
    var reportsEnabled = document.getElementById("as-reports-enabled");
    var clientsEnabled = document.getElementById("as-clients-enabled");
    var financeEnabled = document.getElementById("as-finance-enabled");
    var reportsCounter = document.getElementById("as-reports-counter");
    var clientsCounter = document.getElementById("as-clients-counter");
    var financeCounter = document.getElementById("as-finance-counter");
    var reportsStart = document.getElementById("as-reports-start");
    var reportsEnd = document.getElementById("as-reports-end");
    var clientsYears = document.getElementById("as-clients-years");
    var clientsBulk = document.getElementById("as-clients-bulk");
    var financeYears = document.getElementById("as-finance-years");
    var notes = document.getElementById("as-notes");

    if (reportsEnabled) reportsEnabled.checked = !!state.form.reports.enabled;
    if (clientsEnabled) clientsEnabled.checked = !!state.form.clients.enabled;
    if (financeEnabled) financeEnabled.checked = !!state.form.finance.enabled;

    if (reportsCounter) reportsCounter.textContent = selectedCount("reports") + " خيار";
    if (clientsCounter) clientsCounter.textContent = selectedCount("clients") + " خيار";
    if (financeCounter) financeCounter.textContent = selectedCount("finance") + " خيار";

    if (reportsStart) reportsStart.value = asText(state.form.reports.start_at);
    if (reportsEnd) reportsEnd.value = asText(state.form.reports.end_at);
    if (clientsYears) clientsYears.value = String(clampInt(state.form.clients.subscription_years, 1, 5));
    if (clientsBulk) clientsBulk.value = String(Math.max(0, asInt(state.form.clients.bulk_message_count, 0)));
    if (financeYears) financeYears.value = String(clampInt(state.form.finance.subscription_years, 1, 5));
    if (notes) notes.value = asText(state.form.notes);
  }

  function summarySectionsFromState() {
    readFormInputs();

    var reportLabels = [];
    var reportMap = optionLabelMap("reports");
    state.form.reports.options.forEach(function (key) {
      if (reportMap[key]) reportLabels.push(reportMap[key]);
    });
    if (state.form.reports.start_at) reportLabels.push("بداية التقرير: " + state.form.reports.start_at);
    if (state.form.reports.end_at) reportLabels.push("نهاية التقرير: " + state.form.reports.end_at);

    var clientLabels = [];
    var clientMap = optionLabelMap("clients");
    state.form.clients.options.forEach(function (key) {
      if (clientMap[key]) clientLabels.push(clientMap[key]);
    });
    if (clientLabels.length) {
      clientLabels.push("مدة الاشتراك (بالسنوات): " + clampInt(state.form.clients.subscription_years, 1, 5));
      clientLabels.push("عدد الرسائل الجماعية: " + Math.max(0, asInt(state.form.clients.bulk_message_count, 0)));
    }

    var financeLabels = [];
    var financeMap = optionLabelMap("finance");
    state.form.finance.options.forEach(function (key) {
      if (financeMap[key]) financeLabels.push(financeMap[key]);
    });
    if (financeLabels.length) {
      financeLabels.push("مدة الاشتراك (بالسنوات): " + clampInt(state.form.finance.subscription_years, 1, 5));
    }

    return [
      { key: "reports", title: "التقارير", items: reportLabels },
      { key: "clients", title: "إدارة العملاء", items: clientLabels },
      { key: "finance", title: "الإدارة المالية", items: financeLabels }
    ];
  }

  function renderSummary() {
    var root = document.getElementById("as-summary-sections");
    if (!root) return;

    var sections = summarySectionsFromState();
    var withItems = sections.filter(function (section) {
      return Array.isArray(section.items) && section.items.length > 0;
    });

    if (!withItems.length) {
      root.innerHTML = '<div class="as-empty">لم يتم اختيار أي قسم بعد.</div>';
      return;
    }

    root.innerHTML = withItems.map(function (section) {
      return [
        '<article class="as-summary-card">',
          '<h5>', escapeHtml(section.title), '</h5>',
          '<ul>',
            section.items.map(function (item) {
              return '<li>' + escapeHtml(item) + '</li>';
            }).join(""),
          '</ul>',
        '</article>'
      ].join("");
    }).join("");
  }

  function renderWizard() {
    renderOptionsGroup("reports", "as-reports-options");
    renderOptionsGroup("clients", "as-clients-options");
    renderOptionsGroup("finance", "as-finance-options");
    renderFormInputs();
    renderCardCounters();
    renderSectionVisibility();
    renderSummary();
    renderSubmitState();
  }

  function setActiveSection(sectionKey) {
    var key = asText(sectionKey);
    if (SECTION_ORDER.indexOf(key) < 0) return;
    state.activeSection = key;
    setSubmitError("");
    renderSectionVisibility();
  }

  function activateNextSection() {
    var currentIndex = SECTION_ORDER.indexOf(state.activeSection);
    var nextIndex = currentIndex >= 0 ? (currentIndex + 1) % SECTION_ORDER.length : 0;
    setActiveSection(SECTION_ORDER[nextIndex]);
  }

  function renderCatalog() {
    var root = document.getElementById("as-catalog-items");
    var count = document.getElementById("as-catalog-count");
    if (!root) return;

    if (count) count.textContent = state.catalogItems.length + " عنصر";

    if (!state.catalogItems.length) {
      root.innerHTML = '<div class="as-empty">لا توجد خدمات إضافية فورية متاحة حالياً.</div>';
      return;
    }

    var latestBySku = latestPurchaseBySku();
    root.innerHTML = state.catalogItems.map(function (item) {
      var sku = asText(item && item.sku);
      var title = asText(item && item.title) || sku || "خدمة إضافية";
      var price = formatPrice(item && item.price, item && item.currency);
      var purchase = latestBySku[sku] || null;
      var purchaseStatus = purchase ? statusCode(purchase.status) : "";
      var purchaseStatusLabelText = purchase ? purchaseStatusLabel(purchase.status) : "";
      var purchaseStatusColorValue = purchaseStatusColor(purchaseStatus);
      var isLocked = purchaseStatus === "active" || purchaseStatus === "pending_payment";
      var isBuying = !!state.buyingSkus[sku];
      var disabled = !sku || isBuying || isLocked;
      var buttonLabel = "طلب الخدمة";

      if (isBuying) buttonLabel = "جاري الطلب...";
      else if (purchaseStatus === "pending_payment") buttonLabel = "قيد المعالجة";
      else if (purchaseStatus === "active") buttonLabel = "مفعلة حالياً";

      return [
        '<article class="as-card">',
          '<div class="as-card-head">',
            '<div class="as-title-wrap">',
              '<strong>', escapeHtml(title), '</strong>',
              '<div class="as-sub">SKU: ', escapeHtml(sku || "—"), '</div>',
            '</div>',
            '<div class="as-price">', escapeHtml(price), '</div>',
          '</div>',
          '<div class="as-card-footer">',
            purchaseStatusLabelText ? '<span class="as-pill" style="color:' + purchaseStatusColorValue + ';background:' + purchaseStatusColorValue + '1F">' + escapeHtml(purchaseStatusLabelText) + '</span>' : '<span class="as-pill muted">جديد</span>',
            '<button class="as-buy-btn" data-sku="', escapeHtml(sku), '" data-title="', escapeHtml(title), '"', disabled ? " disabled" : "", '>', escapeHtml(buttonLabel), '</button>',
          '</div>',
        '</article>'
      ].join("");
    }).join("");
  }

  function renderPurchaseHistory() {
    var root = document.getElementById("as-my-items");
    var count = document.getElementById("as-history-count");
    if (!root) return;

    if (count) count.textContent = state.myExtras.length + " طلب";

    if (!state.myExtras.length) {
      root.innerHTML = '<div class="as-empty">لا توجد مشتريات إضافية سابقة.</div>';
      return;
    }

    root.innerHTML = state.myExtras.map(function (item) {
      var title = asText(item && item.title) || "خدمة إضافية";
      var sku = asText(item && item.sku) || "—";
      var createdAt = formatDate(item && item.created_at);
      var invoice = asText(item && item.invoice) || "—";
      var amount = formatPrice(item && item.subtotal, item && item.currency);
      var purchaseStatus = statusCode(item && item.status);
      var purchaseStatusText = purchaseStatusLabel(item && item.status);
      var purchaseColor = purchaseStatusColor(purchaseStatus);

      return [
        '<article class="as-card as-card-history">',
          '<div class="as-card-head">',
            '<div class="as-title-wrap">',
              '<strong>', escapeHtml(title), '</strong>',
              '<div class="as-sub">SKU: ', escapeHtml(sku), '</div>',
            '</div>',
            '<span class="as-pill" style="color:', purchaseColor, ';background:', purchaseColor, '1F">', escapeHtml(purchaseStatusText), '</span>',
          '</div>',
          '<div class="as-meta-grid">',
            '<div class="as-meta-row"><span>التاريخ</span><b>', escapeHtml(createdAt), '</b></div>',
            '<div class="as-meta-row"><span>المبلغ</span><b>', escapeHtml(amount), '</b></div>',
            '<div class="as-meta-row"><span>رقم الفاتورة</span><b>', escapeHtml(invoice), '</b></div>',
          '</div>',
        '</article>'
      ].join("");
    }).join("");
  }

  function renderBundleHistory() {
    var root = document.getElementById("as-bundle-history");
    var count = document.getElementById("as-bundle-history-count");
    if (!root) return;

    if (state.bundleHistoryLoading) {
      if (count) count.textContent = "";
      root.innerHTML = '<div class="as-empty">جاري تحميل الطلبات...</div>';
      return;
    }

    if (count) count.textContent = state.bundleHistory.length + " طلب";

    if (!state.bundleHistory.length) {
      root.innerHTML = '<div class="as-empty">لا توجد طلبات تفصيلية مرسلة بعد.</div>';
      return;
    }

    root.innerHTML = state.bundleHistory.map(function (item) {
      var requestCode = asText(item && item.request_code) || "—";
      var summary = asText(item && item.summary) || "طلب خدمات إضافية";
      var status = statusCode(item && item.status);
      var statusLabel = asText(item && item.status_label) || status || "غير معروف";
      var statusColor = requestStatusColor(status);
      var portalUrl = asText(endpoints.portalHomeUrl);
      var showPortalEntry = status === "closed" && !!portalUrl;
      var submittedAt = formatDateTime(item && item.submitted_at);
      var sections = asList(item && item.summary_sections).filter(function (section) {
        return section && Array.isArray(section.items) && section.items.length > 0;
      });
      var notes = asText(item && item.notes);
      var invoiceSummary = item && typeof item.invoice_summary === "object" ? item.invoice_summary : null;
      var paymentUrl = asText(item && item.payment_url);
      var invoiceCode = asText(invoiceSummary && invoiceSummary.code) || "—";
      var invoiceStatus = asText(invoiceSummary && invoiceSummary.status_label) || "لا توجد فاتورة";
      var invoiceTotal = invoiceSummary ? formatPrice(invoiceSummary.total, invoiceSummary.currency) : "—";
      var canPay = !!paymentUrl && invoiceSummary && invoiceSummary.payment_effective !== true;

      return [
        '<article class="as-card as-card-bundle" data-request-id="', escapeHtml(item && item.request_id), '">',
          '<div class="as-card-head">',
            '<div class="as-title-wrap">',
              '<strong>', escapeHtml(summary), '</strong>',
              '<div class="as-sub">رقم الطلب: ', escapeHtml(requestCode), '</div>',
            '</div>',
            '<div class="as-card-head-side">',
              showPortalEntry
                ? '<a class="as-portal-entry" href="' + escapeHtml(portalUrl) + '" title="الانتقال إلى بوابة الخدمات الإضافية" aria-label="الانتقال إلى بوابة الخدمات الإضافية">'
                    + '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'
                      + '<rect x="3" y="3" width="7" height="7" rx="1.5"></rect>'
                      + '<rect x="14" y="3" width="7" height="7" rx="1.5"></rect>'
                      + '<rect x="3" y="14" width="7" height="7" rx="1.5"></rect>'
                      + '<rect x="14" y="14" width="7" height="7" rx="1.5"></rect>'
                    + '</svg>'
                  + '</a>'
                : '',
              '<span class="as-pill" style="color:', statusColor, ';background:', statusColor, '1F">', escapeHtml(statusLabel), '</span>',
            '</div>',
          '</div>',
          '<div class="as-meta-grid">',
            '<div class="as-meta-row"><span>تاريخ الإرسال</span><b>', escapeHtml(submittedAt), '</b></div>',
            '<div class="as-meta-row"><span>رقم الفاتورة</span><b>', escapeHtml(invoiceCode), '</b></div>',
            '<div class="as-meta-row"><span>حالة الفاتورة</span><b>', escapeHtml(invoiceStatus), '</b></div>',
            '<div class="as-meta-row"><span>إجمالي الفاتورة</span><b>', escapeHtml(invoiceTotal), '</b></div>',
          '</div>',
          sections.length ? '<div class="as-section-list">' + sections.map(function (section) {
            return '<div class="as-section-item"><h6>' + escapeHtml(section.title) + '</h6><ul>' + section.items.map(function (it) {
              return '<li>' + escapeHtml(it) + '</li>';
            }).join("") + '</ul></div>';
          }).join("") + '</div>' : '',
          notes ? '<div class="as-note"><b>ملاحظات:</b> ' + escapeHtml(notes) + '</div>' : '',
          canPay ? '<div class="as-card-footer"><a class="as-buy-btn" href="' + escapeHtml(paymentUrl) + '">دفع الفاتورة</a></div>' : '',
        '</article>'
      ].join("");
    }).join("");
  }

  function render() {
    renderWizard();
    renderCatalog();
    renderPurchaseHistory();
    renderBundleHistory();
  }

  function shouldLoadCatalog() {
    return !!document.getElementById("as-catalog-items");
  }

  function shouldLoadPurchaseHistory() {
    return !!document.getElementById("as-my-items");
  }

  function shouldLoadBundleHistory() {
    return !!document.getElementById("as-bundle-history");
  }

  function buildPayload() {
    readFormInputs();
    return {
      reports: {
        enabled: !!state.form.reports.enabled,
        options: state.form.reports.options.slice(),
        start_at: state.form.reports.start_at || null,
        end_at: state.form.reports.end_at || null
      },
      clients: {
        enabled: !!state.form.clients.enabled,
        options: state.form.clients.options.slice(),
        subscription_years: clampInt(state.form.clients.subscription_years, 1, 5),
        bulk_message_count: Math.max(0, asInt(state.form.clients.bulk_message_count, 0))
      },
      finance: {
        enabled: !!state.form.finance.enabled,
        options: state.form.finance.options.slice(),
        subscription_years: clampInt(state.form.finance.subscription_years, 1, 5)
      },
      notes: asText(state.form.notes)
    };
  }

  function validateBeforeSubmit() {
    readFormInputs();

    if (state.form.reports.enabled && state.form.reports.options.length < 1) {
      setActiveSection("reports");
      setSubmitError("اختر خياراً واحداً على الأقل في قسم التقارير.");
      return false;
    }

    if (state.form.reports.enabled && (!state.form.reports.start_at || !state.form.reports.end_at)) {
      setActiveSection("reports");
      setSubmitError("حدد تاريخ بداية ونهاية التقرير.");
      return false;
    }

    if (state.form.reports.enabled && state.form.reports.start_at > state.form.reports.end_at) {
      setActiveSection("reports");
      setSubmitError("تاريخ نهاية التقرير يجب أن يكون بعد تاريخ البداية.");
      return false;
    }

    if (state.form.clients.enabled && state.form.clients.options.length < 1) {
      setActiveSection("clients");
      setSubmitError("اختر خياراً واحداً على الأقل في قسم إدارة العملاء.");
      return false;
    }

    if (state.form.finance.enabled && state.form.finance.options.length < 1) {
      setActiveSection("finance");
      setSubmitError("اختر خياراً واحداً على الأقل في قسم الإدارة المالية.");
      return false;
    }

    var anySelected =
      (state.form.reports.enabled && state.form.reports.options.length > 0) ||
      (state.form.clients.enabled && state.form.clients.options.length > 0) ||
      (state.form.finance.enabled && state.form.finance.options.length > 0);

    if (!anySelected) {
      setSubmitError("اختر على الأقل قسماً واحداً من الخدمات الإضافية قبل الإرسال.");
      return false;
    }

    return true;
  }

  function showSuccess(result, options) {
    var modal = document.getElementById("as-success-modal");
    var codeEl = document.getElementById("as-success-code");
    var statusEl = document.getElementById("as-success-status");
    var eyebrowEl = document.getElementById("as-success-eyebrow");
    var messageEl = document.getElementById("as-success-message");
    var closeEl = document.getElementById("as-success-close");
    var opts = options && typeof options === "object" ? options : {};

    if (codeEl) codeEl.textContent = asText(result && result.request_code) || "—";

    if (eyebrowEl) {
      eyebrowEl.textContent = asText(opts.eyebrow) || "تم استلام الطلب بنجاح";
    }

    if (messageEl) {
      messageEl.textContent = asText(opts.message) || "تم استلام الطلب بنجاح وسيتم التواصل معكم من قبل فريق إدارة الخدمات الإضافية قريبًا.";
    }

    if (statusEl) {
      var statusText = asText(opts.statusText);
      var label = asText(result && result.status_label) || "تم الاستلام";
      statusEl.textContent = statusText || ("الحالة الحالية: " + label);
    }

    if (closeEl) {
      closeEl.textContent = asText(opts.closeLabel) || "حسنًا";
    }

    if (modal) {
      modal.hidden = false;
      modal.style.display = "flex";
      document.body.style.overflow = "hidden";
    }
  }

  function hideSuccess() {
    var modal = document.getElementById("as-success-modal");
    if (modal) {
      modal.hidden = true;
      modal.style.display = "none";
    }
    document.body.style.overflow = "";
  }

  async function loadData(opts) {
    var options = opts || {};
    var silent = !!options.silent;
    var needsCatalog = shouldLoadCatalog();
    var needsPurchaseHistory = shouldLoadPurchaseHistory();
    var needsBundleHistory = shouldLoadBundleHistory();

    state.bundleHistoryLoading = needsBundleHistory;
    setLoading(true, silent);
    setError("");
    if (silent && needsBundleHistory) {
      renderBundleHistory();
    }

    try {
      var requests = [];
      if (needsCatalog) {
        requests.push({ key: "catalog", promise: ApiClient.get(endpoints.catalogUrl) });
      }
      if (needsPurchaseHistory) {
        requests.push({ key: "my", promise: ApiClient.get(endpoints.myUrl) });
      }
      if (needsBundleHistory) {
        requests.push({ key: "bundle", promise: ApiClient.get(endpoints.bundleMyUrl) });
      }

      var responses = await Promise.all(requests.map(function (entry) {
        return entry.promise;
      }));
      var responsesByKey = {};
      requests.forEach(function (entry, index) {
        responsesByKey[entry.key] = responses[index];
      });

      var catalogRes = responsesByKey.catalog;
      var myRes = responsesByKey.my;
      var bundleRes = responsesByKey.bundle;

      state.catalogItems = needsCatalog && catalogRes && catalogRes.ok ? asList(catalogRes.data) : [];
      state.myExtras = needsPurchaseHistory && myRes && myRes.ok ? asList(myRes.data) : [];
      state.bundleHistory = needsBundleHistory && bundleRes && bundleRes.ok ? asList(bundleRes.data) : [];

      var errors = [];
      if (needsCatalog && (!catalogRes || !catalogRes.ok)) {
        errors.push(extractErrorMessage(catalogRes, "تعذر تحميل كتالوج الخدمات الإضافية"));
      }
      if (needsPurchaseHistory && (!myRes || !myRes.ok)) {
        errors.push(extractErrorMessage(myRes, "تعذر تحميل سجل المشتريات السابقة"));
      }
      if (needsBundleHistory && (!bundleRes || !bundleRes.ok)) {
        errors.push(extractErrorMessage(bundleRes, "تعذر تحميل سجل الطلبات التفصيلية"));
      }

      setError(errors.join(" • "));
      state.bundleHistoryLoading = false;
      render();
      maybeHandlePaymentReturn();
    } catch (_) {
      setError("تعذر تحميل البيانات حالياً");
      if (needsCatalog) state.catalogItems = [];
      if (needsPurchaseHistory) state.myExtras = [];
      if (needsBundleHistory) state.bundleHistory = [];
      state.bundleHistoryLoading = false;
      render();
    } finally {
      state.bundleHistoryLoading = false;
      setLoading(false, false);
    }
  }

  async function buyExtra(sku, title) {
    var cleanSku = asText(sku);
    if (!cleanSku || state.buyingSkus[cleanSku]) return;

    var confirmed = window.confirm('هل تريد طلب الخدمة الفورية "' + (asText(title) || cleanSku) + '"؟');
    if (!confirmed) return;

    state.buyingSkus[cleanSku] = true;
    renderCatalog();

    try {
      var res = await ApiClient.request(buyUrlForSku(cleanSku), {
        method: "POST"
      });

      if (!res.ok) {
        alert(extractErrorMessage(res, "فشل تنفيذ طلب الخدمة"));
        return;
      }

      var code = asText(res.data && res.data.unified_request_code);
      if (code) alert("تم إرسال طلب الخدمة بنجاح (" + code + ")");
      else alert("تم إرسال طلب الخدمة بنجاح");

      await loadData({ silent: true });
    } catch (_) {
      alert("فشل تنفيذ طلب الخدمة");
    } finally {
      delete state.buyingSkus[cleanSku];
      renderCatalog();
    }
  }

  async function submitBundleRequest() {
    if (state.submitPending) return;

    setSubmitError("");
    hideSuccess();

    if (!validateBeforeSubmit()) return;

    state.submitPending = true;
    renderSubmitState();

    try {
      var payload = buildPayload();
      var res = await ApiClient.request(endpoints.bundleCreateUrl, {
        method: "POST",
        body: payload
      });

      if (!res.ok) {
        setSubmitError(extractErrorMessage(res, "تعذر إرسال الطلب حالياً"));
        return;
      }

      showSuccess(res.data || {});
      state.form = emptyForm();
      state.activeSection = "reports";
      setSubmitError("");
      renderWizard();
      await loadData({ silent: true });
    } catch (_) {
      setSubmitError("تعذر إرسال الطلب حالياً");
    } finally {
      state.submitPending = false;
      renderSubmitState();
    }
  }

  function updateGroupEnabled(groupKey, enabled) {
    state.form[groupKey].enabled = !!enabled;
    if (!enabled) {
      state.form[groupKey].options = [];
      if (groupKey === "reports") {
        state.form.reports.start_at = "";
        state.form.reports.end_at = "";
      }
    }
    renderWizard();
  }

  function updateGroupOption(groupKey, optionKey, checked) {
    var options = state.form[groupKey].options;
    var idx = options.indexOf(optionKey);
    if (checked && idx < 0) {
      options.push(optionKey);
    }
    if (!checked && idx >= 0) {
      options.splice(idx, 1);
    }
    if (options.length > 0) {
      state.form[groupKey].enabled = true;
    }
    renderWizard();
  }

  function bindGeneralEvents() {
    var backBtn = document.getElementById("as-back");
    if (backBtn) {
      backBtn.addEventListener("click", function () {
        history.back();
      });
    }

    var refreshBtn = document.getElementById("as-refresh");
    if (refreshBtn) {
      refreshBtn.addEventListener("click", function () {
        loadData({ silent: true });
      });
    }

    var catalogRoot = document.getElementById("as-catalog-items");
    if (catalogRoot) {
      catalogRoot.addEventListener("click", function (e) {
        var btn = e.target.closest(".as-buy-btn");
        if (!btn) return;
        buyExtra(btn.getAttribute("data-sku"), btn.getAttribute("data-title"));
      });
    }
  }

  function bindCardsEvents() {
    var cardsRoot = document.getElementById("as-main-cards");
    if (cardsRoot) {
      cardsRoot.addEventListener("click", function (e) {
        var btn = e.target.closest(".as-main-card");
        if (!btn) return;
        setActiveSection(btn.getAttribute("data-section"));
      });
    }

    var nextCardBtn = document.getElementById("as-next-card");
    if (nextCardBtn) {
      nextCardBtn.addEventListener("click", function () {
        activateNextSection();
      });
    }
  }

  function bindFormEvents() {
    var form = document.getElementById("as-bundle-form");
    if (!form) return;

    form.addEventListener("submit", function (e) {
      e.preventDefault();
      submitBundleRequest();
    });

    form.addEventListener("change", function (e) {
      var target = e.target;
      if (!target) return;

      var id = asText(target.id);
      if (id === "as-reports-enabled") {
        updateGroupEnabled("reports", !!target.checked);
        return;
      }
      if (id === "as-clients-enabled") {
        updateGroupEnabled("clients", !!target.checked);
        return;
      }
      if (id === "as-finance-enabled") {
        updateGroupEnabled("finance", !!target.checked);
        return;
      }
      if (target.classList.contains("as-option-checkbox")) {
        updateGroupOption(asText(target.getAttribute("data-group")), asText(target.getAttribute("data-option")), !!target.checked);
        return;
      }

      readFormInputs();
      renderSummary();
    });

    form.addEventListener("input", function () {
      readFormInputs();
      renderSummary();
    });

    var successClose = document.getElementById("as-success-close");
    if (successClose) {
      successClose.addEventListener("click", function () {
        hideSuccess();
      });
    }

    var successModal = document.getElementById("as-success-modal");
    if (successModal) {
      successModal.addEventListener("click", function (e) {
        var target = e.target;
        if (target && target.getAttribute("data-success-close") === "true") {
          hideSuccess();
        }
      });
    }

    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape") {
        hideSuccess();
      }
    });
  }

  function init() {
    readConfig();
    parseOptionGroups();
    hydrateProviderDisplayName();
    hideSuccess();
    bindGeneralEvents();
    bindCardsEvents();
    bindFormEvents();
    render();
    setLoading(false, false);
    loadData({ silent: true });
  }

  document.addEventListener("DOMContentLoaded", function () {
    try {
      init();
    } catch (err) {
      setLoading(false, false);
      setError("تعذر تهيئة صفحة الخدمات الإضافية");
      if (typeof console !== "undefined" && console && typeof console.error === "function") {
        console.error(err);
      }
    }
  });

  return { init: init, loadData: loadData };
})();
