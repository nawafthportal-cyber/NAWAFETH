(function () {
  "use strict";

  const api = window.NawafethApi;
  const ui = window.NawafethUi;
  if (!api || !ui) return;

  const dom = {
    title: document.getElementById("orders-title"),
    subtitle: document.getElementById("orders-subtitle"),
    modeClientBtn: document.getElementById("mode-client-btn"),
    modeProviderBtn: document.getElementById("mode-provider-btn"),
    searchInput: document.getElementById("orders-search-input"),
    statusFilters: document.getElementById("orders-status-filters"),
    error: document.getElementById("orders-error"),
    list: document.getElementById("orders-list"),
    detailEmpty: document.getElementById("order-detail-empty"),
    detailContent: document.getElementById("order-detail-content"),
    detailTitle: document.getElementById("order-detail-title"),
    detailMeta: document.getElementById("order-detail-meta"),
    detailDescription: document.getElementById("order-detail-description"),
    detailFinance: document.getElementById("order-detail-finance"),
    detailActions: document.getElementById("order-detail-actions"),
    detailAttachments: document.getElementById("order-detail-attachments"),
    detailLogs: document.getElementById("order-detail-logs"),
    detailOffers: document.getElementById("order-detail-offers"),
  };

  const state = {
    me: null,
    canProvider: false,
    providerMode: false,
    status: "",
    query: "",
    allOrders: [],
    filteredOrders: [],
    selectedOrderId: null,
    selectedOrder: null,
    selectedOffers: [],
    searchTimer: null,
  };

  function asList(payload) {
    if (Array.isArray(payload)) return payload;
    if (payload && Array.isArray(payload.results)) return payload.results;
    return [];
  }

  function setError(message) {
    if (!dom.error) return;
    dom.error.textContent = message || "";
    dom.error.hidden = !message;
  }

  function safe(value, fallback) {
    if (value === undefined || value === null || value === "") {
      return fallback || "-";
    }
    return String(value);
  }

  function toStatusClass(statusGroup) {
    if (statusGroup === "new") return "status-new";
    if (statusGroup === "in_progress") return "status-in-progress";
    if (statusGroup === "completed") return "status-completed";
    if (statusGroup === "cancelled") return "status-cancelled";
    return "";
  }

  function requestTypeLabel(requestType) {
    if (requestType === "urgent") return "عاجل";
    if (requestType === "competitive") return "تنافسي";
    return "عادي";
  }

  function displayId(order) {
    const id = Number(order && order.id ? order.id : 0);
    const padded = String(Number.isFinite(id) ? id : 0).padStart(6, "0");
    return "R" + padded;
  }

  function formatMoney(raw) {
    if (raw === undefined || raw === null || raw === "") return "-";
    const n = Number(raw);
    if (!Number.isFinite(n)) return safe(raw);
    return n.toFixed(2) + " SR";
  }

  function updateModeHeader() {
    if (dom.title) {
      dom.title.textContent = state.providerMode ? "طلبات الخدمة" : "طلباتي";
    }
    if (dom.subtitle) {
      dom.subtitle.textContent = state.providerMode
        ? "عرض وإدارة الطلبات كمقدم خدمة."
        : "عرض وإدارة طلباتك كعميل.";
    }
  }

  function updateModeButtons() {
    if (dom.modeClientBtn) {
      dom.modeClientBtn.classList.toggle("is-active", !state.providerMode);
    }
    if (dom.modeProviderBtn) {
      dom.modeProviderBtn.classList.toggle("is-active", state.providerMode);
      dom.modeProviderBtn.disabled = !state.canProvider;
      dom.modeProviderBtn.title = state.canProvider ? "" : "لا يوجد ملف مزود خدمة";
    }
    updateModeHeader();
  }

  function updateStatusFilterButtons() {
    if (!dom.statusFilters) return;
    const chips = dom.statusFilters.querySelectorAll(".nw-status-chip");
    chips.forEach(function (chip) {
      chip.classList.toggle("is-active", (chip.dataset.status || "") === state.status);
    });
  }

  function showDetailLoading() {
    if (dom.detailEmpty) {
      dom.detailEmpty.hidden = false;
      dom.detailEmpty.textContent = "جاري تحميل التفاصيل...";
    }
    if (dom.detailContent) {
      dom.detailContent.hidden = true;
    }
  }

  function clearDetail(message) {
    if (dom.detailEmpty) {
      dom.detailEmpty.hidden = false;
      dom.detailEmpty.textContent = message || "اختر طلبًا لعرض التفاصيل.";
    }
    if (dom.detailContent) {
      dom.detailContent.hidden = true;
    }
    state.selectedOrder = null;
    state.selectedOffers = [];
  }

  function renderListLoading() {
    if (!dom.list) return;
    dom.list.innerHTML = '<div class="nw-order-card"><h3>جاري تحميل الطلبات...</h3></div>';
  }

  function buildListUrl() {
    const base = state.providerMode
      ? "/api/marketplace/provider/requests/"
      : "/api/marketplace/client/requests/";
    const params = [];
    if (state.status) {
      params.push("status_group=" + encodeURIComponent(state.status));
    }
    if (!state.providerMode) {
      const q = (state.query || "").trim();
      if (q) params.push("q=" + encodeURIComponent(q));
    }
    return params.length ? base + "?" + params.join("&") : base;
  }

  function filterProviderOrders() {
    if (!state.providerMode) {
      state.filteredOrders = state.allOrders.slice();
      return;
    }
    const query = String(state.query || "").trim().toLowerCase();
    if (!query) {
      state.filteredOrders = state.allOrders.slice();
      return;
    }
    state.filteredOrders = state.allOrders.filter(function (order) {
      const haystack = [
        safe(order.title, ""),
        safe(order.description, ""),
        safe(order.client_name, ""),
        safe(displayId(order), ""),
      ]
        .join(" ")
        .toLowerCase();
      return haystack.includes(query);
    });
  }

  function buildOrderCard(order) {
    const statusGroup = safe(order.status_group, "new");
    const statusLabel = safe(order.status_label, statusGroup);
    const type = safe(order.request_type, "normal");
    const requestTypePill =
      type === "normal"
        ? ""
        : '<span class="nw-pill ' +
          (type === "urgent" ? "request-urgent" : "request-competitive") +
          '">' +
          ui.safeText(requestTypeLabel(type)) +
          "</span>";

    const providerInfo = order.provider_name
      ? '<p class="nw-order-card-provider">' + ui.safeText(order.provider_name) + '</p>'
      : '';

    const isActive = Number(order.id) === Number(state.selectedOrderId);
    return (
      '<article class="nw-order-card' +
      (isActive ? " is-active" : "") +
      '" data-order-id="' +
      ui.safeText(order.id) +
      '">' +
      '<div class="nw-order-card-info">' +
      '<div class="nw-order-card-row1">' +
      '<span class="nw-order-card-id">' + ui.safeText(displayId(order)) + '</span>' +
      requestTypePill +
      '</div>' +
      '<p class="nw-order-card-title">' + ui.safeText(order.title || "طلب") + '</p>' +
      providerInfo +
      '<p class="nw-order-card-date">' + ui.safeText(ui.formatDateTime(order.created_at)) + '</p>' +
      '</div>' +
      '<span class="nw-order-status-badge ' + toStatusClass(statusGroup) + '">' +
      ui.safeText(statusLabel) +
      '</span>' +
      '</article>'
    );
  }

  function renderOrdersList() {
    if (!dom.list) return;
    if (!state.filteredOrders.length) {
      dom.list.innerHTML =
        '<div class="nw-order-card nw-order-card-empty"><h3>لا توجد طلبات</h3><p>غيّر الفلتر أو نص البحث</p></div>';
      return;
    }
    dom.list.innerHTML = state.filteredOrders.map(buildOrderCard).join("");
  }

  function makeKv(label, value) {
    return (
      '<div class="nw-order-kv"><strong>' +
      ui.safeText(label) +
      "</strong><span>" +
      ui.safeText(safe(value)) +
      "</span></div>"
    );
  }

  function renderDetailMeta(order) {
    if (!dom.detailMeta) return;
    const rows = [
      makeKv("رقم الطلب", displayId(order)),
      makeKv("الحالة", safe(order.status_label, order.status_group)),
      makeKv("نوع الطلب", requestTypeLabel(order.request_type)),
      makeKv("التاريخ", ui.formatDateTime(order.created_at)),
      makeKv("المدينة", safe(order.city)),
      makeKv("التصنيف", safe(order.category_name)),
      makeKv("التصنيف الفرعي", safe(order.subcategory_name)),
    ];
    if (state.providerMode) {
      rows.push(makeKv("العميل", safe(order.client_name)));
      rows.push(makeKv("جوال العميل", safe(order.client_phone)));
    } else {
      rows.push(makeKv("المزود", safe(order.provider_name)));
      rows.push(makeKv("جوال المزود", safe(order.provider_phone)));
    }
    dom.detailMeta.innerHTML = rows.join("");
  }

  function renderDetailDescription(order) {
    if (!dom.detailDescription) return;
    dom.detailDescription.innerHTML =
      '<strong>الوصف</strong><p>' + ui.safeText(safe(order.description)) + "</p>";
  }

  function renderDetailFinance(order) {
    if (!dom.detailFinance) return;
    const rows = [];
    if (order.expected_delivery_at) {
      rows.push(makeKv("التسليم المتوقع", ui.formatDateTime(order.expected_delivery_at)));
    }
    if (order.delivered_at) {
      rows.push(makeKv("التسليم الفعلي", ui.formatDateTime(order.delivered_at)));
    }
    if (order.estimated_service_amount !== null && order.estimated_service_amount !== undefined && order.estimated_service_amount !== "") {
      rows.push(makeKv("القيمة المقدرة", formatMoney(order.estimated_service_amount)));
    }
    if (order.received_amount !== null && order.received_amount !== undefined && order.received_amount !== "") {
      rows.push(makeKv("المبلغ المستلم", formatMoney(order.received_amount)));
    }
    if (order.remaining_amount !== null && order.remaining_amount !== undefined && order.remaining_amount !== "") {
      rows.push(makeKv("المبلغ المتبقي", formatMoney(order.remaining_amount)));
    }
    if (order.actual_service_amount !== null && order.actual_service_amount !== undefined && order.actual_service_amount !== "") {
      rows.push(makeKv("القيمة الفعلية", formatMoney(order.actual_service_amount)));
    }
    if (order.canceled_at) {
      rows.push(makeKv("تاريخ الإلغاء", ui.formatDateTime(order.canceled_at)));
    }
    if (order.cancel_reason) {
      rows.push(makeKv("سبب الإلغاء", safe(order.cancel_reason)));
    }
    if (order.provider_inputs_approved === true) {
      rows.push(makeKv("اعتماد مدخلات المزود", "معتمد"));
    }
    if (order.provider_inputs_approved === false) {
      rows.push(makeKv("اعتماد مدخلات المزود", "مرفوض"));
    }

    if (!rows.length) {
      dom.detailFinance.innerHTML = '<strong>البيانات المالية</strong><p>لا توجد بيانات مالية حتى الآن.</p>';
      return;
    }
    dom.detailFinance.innerHTML = "<strong>البيانات المالية</strong>" + rows.join("");
  }

  function actionButtonHtml(spec) {
    return (
      '<button type="button" data-action="' +
      ui.safeText(spec.action) +
      '" class="' +
      ui.safeText(spec.kind || "") +
      '">' +
      ui.safeText(spec.label) +
      "</button>"
    );
  }

  function getActionSpecs(order) {
    const list = [];
    const status = safe(order.status_group, "");
    if (state.providerMode) {
      if (status === "new") {
        if (safe(order.request_type, "normal") !== "competitive") {
          list.push({ action: "provider_accept", label: "قبول الطلب", kind: "primary" });
        }
        list.push({ action: "provider_start", label: "بدء التنفيذ", kind: "primary" });
        list.push({ action: "provider_reject", label: "رفض الطلب", kind: "danger" });
      } else if (status === "in_progress") {
        list.push({ action: "provider_update_progress", label: "تحديث التقدم", kind: "primary" });
        list.push({ action: "provider_complete", label: "إكمال الطلب", kind: "primary" });
        list.push({ action: "provider_cancel", label: "إلغاء الطلب", kind: "danger" });
      }
      return list;
    }

    if (status === "new") {
      list.push({ action: "client_cancel", label: "إلغاء الطلب", kind: "danger" });
    }
    if (status === "in_progress" && order.provider_inputs_approved === null) {
      list.push({ action: "approve_inputs", label: "اعتماد مدخلات المزود", kind: "primary" });
      list.push({ action: "reject_inputs", label: "رفض المدخلات", kind: "danger" });
    }
    if (status === "cancelled") {
      list.push({ action: "reopen", label: "إعادة فتح الطلب", kind: "primary" });
    }
    return list;
  }

  function renderDetailActions(order) {
    if (!dom.detailActions) return;
    const specs = getActionSpecs(order);
    if (!specs.length) {
      dom.detailActions.innerHTML = "<strong>الإجراءات</strong><p>لا توجد إجراءات متاحة للحالة الحالية.</p>";
      return;
    }
    dom.detailActions.innerHTML =
      "<strong>الإجراءات</strong>" +
      '<div class="nw-order-actions-row">' +
      specs.map(actionButtonHtml).join("") +
      "</div>";
  }

  function extractFileName(url) {
    const clean = String(url || "").split("?")[0];
    const parts = clean.split("/");
    return parts.length ? parts[parts.length - 1] : "attachment";
  }

  function renderDetailAttachments(order) {
    if (!dom.detailAttachments) return;
    const items = Array.isArray(order.attachments) ? order.attachments : [];
    if (!items.length) {
      dom.detailAttachments.innerHTML = "<strong>المرفقات</strong><p>لا توجد مرفقات.</p>";
      return;
    }
    dom.detailAttachments.innerHTML =
      "<strong>المرفقات</strong>" +
      items
        .map(function (item) {
          const fileUrl = safe(item.file_url, "");
          return (
            '<div class="nw-order-kv"><strong>' +
            ui.safeText(item.file_type || "file") +
            '</strong><span><a href="' +
            ui.safeText(fileUrl) +
            '" target="_blank" rel="noopener">' +
            ui.safeText(extractFileName(fileUrl)) +
            "</a></span></div>"
          );
        })
        .join("");
  }

  function renderDetailLogs(order) {
    if (!dom.detailLogs) return;
    const logs = Array.isArray(order.status_logs) ? order.status_logs : [];
    if (!logs.length) {
      dom.detailLogs.innerHTML = "<strong>سجل الحالة</strong><p>لا يوجد سجل حتى الآن.</p>";
      return;
    }
    dom.detailLogs.innerHTML =
      "<strong>سجل الحالة</strong>" +
      logs
        .map(function (log) {
          const title = safe(log.from_status, "-") + " → " + safe(log.to_status, "-");
          const note = safe(log.note, "-");
          const actor = safe(log.actor_name, "-");
          const when = ui.formatDateTime(log.created_at);
          return (
            '<div class="nw-order-offer">' +
            "<strong>" +
            ui.safeText(title) +
            "</strong>" +
            "<span>" +
            ui.safeText(note) +
            "</span>" +
            "<span>" +
            ui.safeText(actor) +
            " - " +
            ui.safeText(when) +
            "</span>" +
            "</div>"
          );
        })
        .join("");
  }

  async function loadOffersIfNeeded(orderId, requestType) {
    if (state.providerMode || requestType !== "competitive") {
      state.selectedOffers = [];
      return;
    }
    try {
      const payload = await api.get("/api/marketplace/requests/" + String(orderId) + "/offers/");
      state.selectedOffers = asList(payload);
    } catch (_error) {
      state.selectedOffers = [];
    }
  }

  function renderDetailOffers(order) {
    if (!dom.detailOffers) return;
    if (state.providerMode || safe(order.request_type, "normal") !== "competitive") {
      dom.detailOffers.hidden = true;
      dom.detailOffers.innerHTML = "";
      return;
    }

    dom.detailOffers.hidden = false;
    if (!state.selectedOffers.length) {
      dom.detailOffers.innerHTML = "<strong>العروض</strong><p>لا توجد عروض حتى الآن.</p>";
      return;
    }

    const canAccept = safe(order.status_group, "") === "new";
    dom.detailOffers.innerHTML =
      "<strong>العروض</strong>" +
      state.selectedOffers
        .map(function (offer) {
          return (
            '<div class="nw-order-offer">' +
            "<strong>" +
            ui.safeText(safe(offer.provider_name, "مزود خدمة")) +
            "</strong>" +
            "<span>السعر: " +
            ui.safeText(formatMoney(offer.price)) +
            "</span>" +
            "<span>المدة: " +
            ui.safeText(safe(offer.duration_days, "-")) +
            " يوم</span>" +
            "<span>الحالة: " +
            ui.safeText(safe(offer.status, "-")) +
            "</span>" +
            (canAccept
              ? '<button type="button" data-offer-accept="' + ui.safeText(offer.id) + '" class="primary">قبول العرض</button>'
              : "") +
            "</div>"
          );
        })
        .join("");
  }

  function renderOrderDetail(order) {
    if (!dom.detailContent || !dom.detailEmpty || !dom.detailTitle) return;
    dom.detailEmpty.hidden = true;
    dom.detailContent.hidden = false;
    dom.detailTitle.textContent = displayId(order) + " - " + safe(order.title, "طلب");
    renderDetailMeta(order);
    renderDetailDescription(order);
    renderDetailFinance(order);
    renderDetailActions(order);
    renderDetailAttachments(order);
    renderDetailLogs(order);
    renderDetailOffers(order);

    /* On mobile, open the detail panel as overlay */
    var panel = document.getElementById("order-detail-panel");
    var closeBtn = document.getElementById("detail-close-btn");
    if (panel && window.innerWidth < 769) {
      panel.classList.add("is-open");
      if (closeBtn) closeBtn.style.display = "";
    }
  }

  async function loadOrderDetail(orderId) {
    if (!orderId) return;
    showDetailLoading();
    setError("");
    try {
      const path = state.providerMode
        ? "/api/marketplace/provider/requests/" + String(orderId) + "/detail/"
        : "/api/marketplace/client/requests/" + String(orderId) + "/";
      const detail = await api.get(path);
      state.selectedOrderId = Number(orderId);
      state.selectedOrder = detail || null;
      await loadOffersIfNeeded(orderId, safe(detail && detail.request_type, "normal"));
      renderOrdersList();
      renderOrderDetail(detail || {});
    } catch (error) {
      clearDetail("تعذر تحميل تفاصيل الطلب.");
      setError(api.getErrorMessage(error && error.payload, error.message || "تعذر تحميل التفاصيل"));
    }
  }

  async function loadOrders(preferredId) {
    setError("");
    renderListLoading();
    try {
      const payload = await api.get(buildListUrl());
      state.allOrders = asList(payload);
      filterProviderOrders();
      renderOrdersList();

      if (!state.filteredOrders.length) {
        state.selectedOrderId = null;
        clearDetail("لا توجد طلبات حالياً.");
        return;
      }

      let nextId = null;
      const preferred = Number(preferredId || state.selectedOrderId);
      if (preferred && state.filteredOrders.some(function (item) { return Number(item.id) === preferred; })) {
        nextId = preferred;
      } else {
        nextId = Number(state.filteredOrders[0].id);
      }
      await loadOrderDetail(nextId);
    } catch (error) {
      state.allOrders = [];
      state.filteredOrders = [];
      renderOrdersList();
      clearDetail("تعذر تحميل الطلبات.");
      setError(api.getErrorMessage(error && error.payload, error.message || "تعذر تحميل الطلبات"));
    }
  }

  function parseRequiredIso(input, errorText) {
    const raw = String(input || "").trim();
    if (!raw) {
      setError(errorText);
      return "";
    }
    const d = new Date(raw);
    if (Number.isNaN(d.getTime())) {
      setError("صيغة التاريخ غير صحيحة.");
      return "";
    }
    return d.toISOString();
  }

  function parseRequiredAmount(input, errorText) {
    const raw = String(input || "").trim();
    if (!raw) {
      setError(errorText);
      return "";
    }
    const n = Number(raw);
    if (!Number.isFinite(n) || n < 0) {
      setError("القيمة المالية غير صحيحة.");
      return "";
    }
    return String(n);
  }

  async function runOrderAction(action) {
    const order = state.selectedOrder;
    if (!order || !order.id) return false;
    const requestId = Number(order.id);

    if (action === "client_cancel") {
      const reason = window.prompt("سبب الإلغاء (اختياري):", "") || "";
      const body = reason.trim() ? { reason: reason.trim() } : {};
      await api.post("/api/marketplace/requests/" + String(requestId) + "/cancel/", body);
      return true;
    }

    if (action === "reopen") {
      await api.post("/api/marketplace/requests/" + String(requestId) + "/reopen/", {});
      return true;
    }

    if (action === "approve_inputs") {
      await api.post(
        "/api/marketplace/requests/" + String(requestId) + "/provider-inputs/decision/",
        { approved: true }
      );
      return true;
    }

    if (action === "reject_inputs") {
      const note = window.prompt("ملاحظة (اختياري):", "") || "";
      const body = { approved: false };
      if (note.trim()) body.note = note.trim();
      await api.post(
        "/api/marketplace/requests/" + String(requestId) + "/provider-inputs/decision/",
        body
      );
      return true;
    }

    if (action === "provider_accept") {
      await api.post("/api/marketplace/provider/requests/" + String(requestId) + "/accept/", {});
      return true;
    }

    if (action === "provider_reject") {
      const reasonRaw = window.prompt("سبب الإلغاء:", safe(order.cancel_reason, ""));
      if (reasonRaw === null) return false;
      const reason = reasonRaw.trim();
      if (!reason) {
        setError("سبب الإلغاء مطلوب.");
        return false;
      }
      await api.post("/api/marketplace/provider/requests/" + String(requestId) + "/reject/", {
        canceled_at: new Date().toISOString(),
        cancel_reason: reason,
        note: reason,
      });
      return true;
    }

    if (action === "provider_cancel") {
      const reason = window.prompt("سبب الإلغاء (اختياري):", "") || "";
      const body = reason.trim() ? { reason: reason.trim() } : {};
      await api.post("/api/marketplace/requests/" + String(requestId) + "/cancel/", body);
      return true;
    }

    if (action === "provider_start") {
      const expectedRaw = window.prompt(
        "موعد التسليم المتوقع (صيغة ISO):",
        new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString()
      );
      if (expectedRaw === null) return false;
      const expected = parseRequiredIso(expectedRaw, "موعد التسليم المتوقع مطلوب.");
      if (!expected) return false;

      const estimatedRaw = window.prompt(
        "قيمة الخدمة المقدرة (SR):",
        safe(order.estimated_service_amount, "")
      );
      if (estimatedRaw === null) return false;
      const estimated = parseRequiredAmount(estimatedRaw, "القيمة المقدرة مطلوبة.");
      if (!estimated) return false;

      const receivedRaw = window.prompt(
        "المبلغ المستلم (SR):",
        safe(order.received_amount, "")
      );
      if (receivedRaw === null) return false;
      const received = parseRequiredAmount(receivedRaw, "المبلغ المستلم مطلوب.");
      if (!received) return false;

      if (Number(received) > Number(estimated)) {
        setError("المبلغ المستلم لا يمكن أن يكون أكبر من القيمة المقدرة.");
        return false;
      }

      const note = window.prompt("ملاحظة (اختياري):", "") || "";
      const body = {
        expected_delivery_at: expected,
        estimated_service_amount: estimated,
        received_amount: received,
      };
      if (note.trim()) body.note = note.trim();

      await api.post("/api/marketplace/requests/" + String(requestId) + "/start/", body);
      return true;
    }

    if (action === "provider_update_progress") {
      const expectedRaw = window.prompt(
        "موعد التسليم المتوقع (ISO) - اتركه فارغًا بدون تغيير:",
        safe(order.expected_delivery_at, "")
      );
      if (expectedRaw === null) return false;
      const estimatedRaw = window.prompt(
        "قيمة الخدمة المقدرة (SR) - اتركه فارغًا بدون تغيير:",
        safe(order.estimated_service_amount, "")
      );
      if (estimatedRaw === null) return false;
      const receivedRaw = window.prompt(
        "المبلغ المستلم (SR) - اتركه فارغًا بدون تغيير:",
        safe(order.received_amount, "")
      );
      if (receivedRaw === null) return false;
      const noteRaw = window.prompt("ملاحظة (اختياري):", "");
      if (noteRaw === null) return false;

      const body = {};
      if (String(expectedRaw).trim()) {
        const parsed = parseRequiredIso(expectedRaw, "صيغة الموعد غير صحيحة.");
        if (!parsed) return false;
        body.expected_delivery_at = parsed;
      }

      const hasEstimated = String(estimatedRaw).trim() !== "";
      const hasReceived = String(receivedRaw).trim() !== "";
      if (hasEstimated !== hasReceived) {
        setError("يجب إدخال القيمة المقدرة والمبلغ المستلم معًا.");
        return false;
      }
      if (hasEstimated) {
        const estimated = parseRequiredAmount(estimatedRaw, "القيمة المقدرة مطلوبة.");
        if (!estimated) return false;
        const received = parseRequiredAmount(receivedRaw, "المبلغ المستلم مطلوب.");
        if (!received) return false;
        if (Number(received) > Number(estimated)) {
          setError("المبلغ المستلم لا يمكن أن يكون أكبر من القيمة المقدرة.");
          return false;
        }
        body.estimated_service_amount = estimated;
        body.received_amount = received;
      }

      if (String(noteRaw).trim()) {
        body.note = String(noteRaw).trim();
      }

      if (!Object.keys(body).length) {
        setError("لا توجد بيانات محدثة للإرسال.");
        return false;
      }

      await api.post(
        "/api/marketplace/provider/requests/" + String(requestId) + "/progress-update/",
        body
      );
      return true;
    }

    if (action === "provider_complete") {
      const deliveredRaw = window.prompt(
        "موعد التسليم الفعلي (صيغة ISO):",
        new Date().toISOString()
      );
      if (deliveredRaw === null) return false;
      const delivered = parseRequiredIso(deliveredRaw, "موعد التسليم الفعلي مطلوب.");
      if (!delivered) return false;

      const actualRaw = window.prompt(
        "قيمة الخدمة الفعلية (SR):",
        safe(order.actual_service_amount, "")
      );
      if (actualRaw === null) return false;
      const actual = parseRequiredAmount(actualRaw, "قيمة الخدمة الفعلية مطلوبة.");
      if (!actual) return false;

      const note = window.prompt("ملاحظة (اختياري):", "") || "";
      const body = {
        delivered_at: delivered,
        actual_service_amount: actual,
      };
      if (note.trim()) body.note = note.trim();

      await api.post("/api/marketplace/requests/" + String(requestId) + "/complete/", body);
      return true;
    }

    return false;
  }

  async function runAcceptOffer(offerId) {
    await api.post("/api/marketplace/offers/" + String(offerId) + "/accept/", {});
  }

  function onListClick(event) {
    const card = event.target.closest(".nw-order-card[data-order-id]");
    if (!card) return;
    const id = Number(card.getAttribute("data-order-id"));
    if (!Number.isFinite(id) || id <= 0) return;
    loadOrderDetail(id);
  }

  async function onDetailClick(event) {
    const offerBtn = event.target.closest("button[data-offer-accept]");
    if (offerBtn) {
      const offerId = Number(offerBtn.getAttribute("data-offer-accept"));
      if (!Number.isFinite(offerId)) return;
      offerBtn.disabled = true;
      setError("");
      try {
        await runAcceptOffer(offerId);
        await loadOrders(state.selectedOrderId);
      } catch (error) {
        setError(api.getErrorMessage(error && error.payload, error.message || "تعذر قبول العرض"));
      } finally {
        offerBtn.disabled = false;
      }
      return;
    }

    const actionBtn = event.target.closest("button[data-action]");
    if (!actionBtn) return;
    const action = actionBtn.getAttribute("data-action");
    if (!action) return;

    actionBtn.disabled = true;
    setError("");
    try {
      const changed = await runOrderAction(action);
      if (changed) {
        await loadOrders(state.selectedOrderId);
      }
    } catch (error) {
      setError(api.getErrorMessage(error && error.payload, error.message || "تعذر تنفيذ الإجراء"));
    } finally {
      actionBtn.disabled = false;
    }
  }

  function onSearchInput() {
    state.query = String(dom.searchInput && dom.searchInput.value ? dom.searchInput.value : "");
    if (state.providerMode) {
      filterProviderOrders();
      renderOrdersList();
      return;
    }
    if (state.searchTimer) {
      clearTimeout(state.searchTimer);
    }
    state.searchTimer = setTimeout(function () {
      loadOrders(state.selectedOrderId);
    }, 320);
  }

  function onStatusFilterClick(event) {
    const chip = event.target.closest(".nw-status-chip");
    if (!chip) return;
    state.status = chip.dataset.status || "";
    updateStatusFilterButtons();
    loadOrders(state.selectedOrderId);
  }

  async function onModeChange(providerMode) {
    if (providerMode === state.providerMode) return;
    if (providerMode && !state.canProvider) {
      setError("لا يمكنك التحويل لوضع المزود قبل استكمال ملف المزود.");
      return;
    }
    state.providerMode = providerMode;
    api.setProviderMode(providerMode);
    updateModeButtons();
    state.selectedOrderId = null;
    clearDetail("جاري تحميل الطلبات...");
    await loadOrders();
  }

  function bindEvents() {
    if (dom.modeClientBtn) {
      dom.modeClientBtn.addEventListener("click", function () {
        onModeChange(false);
      });
    }
    if (dom.modeProviderBtn) {
      dom.modeProviderBtn.addEventListener("click", function () {
        onModeChange(true);
      });
    }
    if (dom.searchInput) {
      dom.searchInput.addEventListener("input", onSearchInput);
      dom.searchInput.addEventListener("keydown", function (event) {
        if (event.key === "Enter") {
          event.preventDefault();
          loadOrders(state.selectedOrderId);
        }
      });
    }
    if (dom.statusFilters) {
      dom.statusFilters.addEventListener("click", onStatusFilterClick);
    }
    if (dom.list) {
      dom.list.addEventListener("click", onListClick);
    }
    if (dom.detailActions || dom.detailOffers) {
      var detailRoot = document.getElementById("order-detail-panel");
      if (detailRoot) detailRoot.addEventListener("click", onDetailClick);
    }

    /* Mobile: close detail panel overlay */
    var detailCloseBtn = document.getElementById("detail-close-btn");
    if (detailCloseBtn) {
      detailCloseBtn.addEventListener("click", function () {
        var panel = document.getElementById("order-detail-panel");
        if (panel) panel.classList.remove("is-open");
      });
    }
  }

  function renderLoginRequired() {
    setError("يجب تسجيل الدخول أولاً لعرض وإدارة الطلبات.");
    if (dom.list) {
      dom.list.innerHTML =
        '<div class="nw-order-card"><h3>تسجيل الدخول مطلوب</h3><p><a class="nw-primary-btn" href="' +
        ui.safeText(api.urls.login || "/web/auth/login/") +
        '">تسجيل الدخول</a></p></div>';
    }
    clearDetail("بعد تسجيل الدخول ستظهر تفاصيل الطلب هنا.");
  }

  async function init() {
    updateStatusFilterButtons();
    bindEvents();

    if (!api.isAuthenticated()) {
      renderLoginRequired();
      return;
    }

    try {
      state.me = await api.get("/api/accounts/me/");
      state.canProvider = Boolean(
        state.me && (state.me.is_provider === true || state.me.has_provider_profile === true)
      );
      state.providerMode = api.ensureProviderModeFromProfile(state.me || {});
      updateModeButtons();
      await loadOrders();
    } catch (error) {
      const status = Number(error && error.status ? error.status : 0);
      if (status === 401) {
        api.clearSession();
        renderLoginRequired();
        return;
      }
      setError(api.getErrorMessage(error && error.payload, error.message || "تعذر تهيئة الصفحة"));
      clearDetail("تعذر تهيئة الصفحة.");
    }
  }

  document.addEventListener("DOMContentLoaded", init);
})();
