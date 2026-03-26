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
  var pendingPreviewData = null;
  var pendingRequestBody = null;
  var homeBannerEditor = {
    activeDevice: "mobile",
    scales: { mobile: 100, tablet: 100, desktop: 100 },
    previewUrl: ""
  };

  function init() {
    bindTabs();
    bindServicePicks();
    bindAttachmentPolicyHints();
    bindHomeBannerEditor();
    bindForm();
    bindRequestActions();
    bindModal();
    bindLiveQuote();
    bindPreviewButtons();
    bindSummaryScreen();
    bindPaymentScreen();
    loadRequests();
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
    tabs.addEventListener("click", function (e) {
      var tab = e.target.closest(".tab");
      if (!tab) return;
      var name = tab.dataset.tab;
      tabs.querySelectorAll(".tab").forEach(function (item) {
        item.classList.toggle("active", item === tab);
      });
      document.querySelectorAll(".tab-panel").forEach(function (panel) {
        panel.classList.toggle("active", panel.dataset.panel === name);
      });
    });
    document.getElementById("btn-go-new").addEventListener("click", function () {
      document.querySelector('[data-tab="new"]').click();
    });
  }

  function bindServicePicks() {
    document.querySelectorAll(".chip-btn").forEach(function (button) {
      button.addEventListener("click", function () {
        var service = button.dataset.service;
        var idx = selectedServices.indexOf(service);
        if (idx >= 0) {
          selectedServices.splice(idx, 1);
          button.classList.remove("active");
          toggleServiceBlock(service, false);
        } else {
          selectedServices.push(service);
          button.classList.add("active");
          toggleServiceBlock(service, true);
        }
        scheduleLiveQuote();
      });
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
    document.getElementById("promo-list").addEventListener("click", async function (e) {
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
    if (block) block.hidden = !show;
  }

  async function loadRequests() {
    var loading = document.getElementById("promo-loading");
    var empty = document.getElementById("promo-empty");
    var listEl = document.getElementById("promo-list");
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
      bindTableRowClicks();
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
        '<th>اسم العميل</th>' +
        '<th>الأولوية</th>' +
        '<th>تاريخ ووقت اعتماد الطلب</th>' +
        '<th>حالة الطلب</th>' +
        '<th>المكلف بالطلب</th>' +
        '<th>تاريخ ووقت التكليف</th>' +
      '</tr></thead><tbody>';

    rows.forEach(function (row) {
      html += renderRequestRow(row);
    });

    html += '</tbody></table></div>';
    return html;
  }

  function renderRequestRow(row) {
    var code = escapeHtml(row.code || "");
    var title = escapeHtml(row.title || "");
    var priority = row.priority != null ? escapeHtml(String(row.priority)) : "—";
    var createdAt = formatDateTime(row.created_at || row.quoted_at || "");
    var status = escapeHtml(STATUS_LABELS[row.status] || row.status || "");
    var assignee = escapeHtml(row.assigned_to_name || row.assigned_to || "—");
    var assignedAt = formatDateTime(row.assigned_at || "");

    return '<tr data-request-id="' + row.id + '">' +
      '<td style="color:#663d90;font-weight:600">' + code + '</td>' +
      '<td>' + (title || "—") + '</td>' +
      '<td>' + priority + '</td>' +
      '<td>' + createdAt + '</td>' +
      '<td>' + status + '</td>' +
      '<td>' + assignee + '</td>' +
      '<td>' + assignedAt + '</td>' +
      '</tr>';
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
      if (res && res.id) detailRow = res;
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

  function bindForm() {
    document.getElementById("promo-form").addEventListener("submit", async function (e) {
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
      button.disabled = true;
      try {
        button.textContent = "جاري احتساب التسعير...";
        var requestBody = Object.assign({ title: title, items: items }, collectHomeBannerScalePayload());

        var previewRes = await ApiClient.request("/api/promo/requests/preview/", {
          method: "POST",
          body: requestBody
        });
        if (!previewRes.ok) {
          alert(extractError(previewRes, "تعذر معاينة التسعير"));
          return;
        }

        var confirmed = await openModal({
          title: "مراجعة التسعيرة قبل الإرسال",
          bodyHtml: buildQuotePreviewHtml(previewRes.data || {}),
          confirmText: "إرسال الطلب",
          cancelText: "إلغاء"
        });
        if (!confirmed) return;

        pendingPreviewData = previewRes.data || {};
        pendingRequestBody = requestBody;
        showSummaryScreen(pendingPreviewData);
      } catch (err) {
        console.error("Promo submit failed", err);
        alert("تعذر إكمال عملية الترويج. حاول مرة أخرى.");
      } finally {
        button.disabled = false;
        button.textContent = "معاينة التسعير ثم الإرسال";
      }
    });
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
      '<p class="promo-note">سيتم إنشاء الطلب بهذه التسعيرة الحالية، ثم ينتقل إلى الاعتماد قبل فتح صفحة الدفع لمزود الخدمة.</p>'
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
    document.querySelectorAll(".chip-btn").forEach(function (btn) { btn.classList.remove("active"); });
    document.querySelectorAll(".promo-service-block").forEach(function (block) { block.hidden = true; });

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
    var spinnerEl = document.getElementById("promo-live-spinner");

    var title = valueOf(document.getElementById("promo-title"));
    if (!title || !selectedServices.length) {
      if (totalEl) totalEl.hidden = true;
      return;
    }

    var items = [];
    for (var i = 0; i < selectedServices.length; i++) {
      var service = selectedServices[i];
      var block = document.querySelector('[data-service-block="' + service + '"]');
      var payload = buildServicePayload(service, block, i);
      if (typeof payload === "string") {
        if (totalEl) totalEl.hidden = true;
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
      if (!res.ok) return;

      liveQuoteData = res.data || {};
      if (amountEl) amountEl.textContent = money(liveQuoteData.total) + " ريال";
      if (detailEl) detailEl.textContent = "قبل الضريبة: " + money(liveQuoteData.subtotal) + " ريال • VAT: " + money(liveQuoteData.vat_amount) + " ريال";
    } catch (err) {
      if (spinnerEl) spinnerEl.hidden = true;
    }
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
    document.getElementById("promo-service-blocks").addEventListener("click", async function (e) {
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
     Screen Navigation (form → summary → payment)
     ==================================================================== */

  function navigateToScreen(screenId) {
    document.querySelector(".page-shell:not(.promo-screen)").hidden = (screenId !== "main");
    document.getElementById("promo-summary-screen").hidden = (screenId !== "summary");
    document.getElementById("promo-payment-screen").hidden = (screenId !== "payment");
    window.scrollTo(0, 0);
  }

  /* ====================================================================
     Summary Screen
     ==================================================================== */

  function showSummaryScreen(preview) {
    var items = Array.isArray(preview.items) ? preview.items : [];
    var title = valueOf(document.getElementById("promo-title")) || "مزود الخدمة";

    document.getElementById("summary-provider-name").textContent = "اسم المختص: " + escapeHtml(title);

    var tbody = document.getElementById("summary-items-body");
    tbody.innerHTML = items.map(function (item) {
      var label = escapeHtml(item.title || SERVICE_LABELS[item.service_type] || item.service_type || "");
      var cost = money(item.subtotal) + " ريال";
      if (item.duration_days != null) cost += " • " + item.duration_days + " يوم";
      return "<tr><td>" + label + "</td><td>" + escapeHtml(cost) + "</td></tr>";
    }).join("");

    document.getElementById("summary-subtotal").textContent = money(preview.subtotal) + " ريال";
    document.getElementById("summary-vat").textContent = money(preview.vat_amount) + " ريال";
    document.getElementById("summary-total").textContent = money(preview.total) + " ريال";

    navigateToScreen("summary");
  }

  function bindSummaryScreen() {
    document.getElementById("summary-back").addEventListener("click", function () {
      navigateToScreen("main");
    });
    document.getElementById("summary-cancel").addEventListener("click", function () {
      navigateToScreen("main");
    });
    document.getElementById("summary-continue").addEventListener("click", function () {
      var total = pendingPreviewData ? money(pendingPreviewData.total) : "0.00";
      document.getElementById("payment-amount-label").textContent = "المبلغ المطلوب: " + total + " ريال";
      resetPaymentForm();
      navigateToScreen("payment");
    });
  }

  /* ====================================================================
     Payment Screen
     ==================================================================== */

  var paymentMethod = "apple_pay";

  function resetPaymentForm() {
    paymentMethod = "apple_pay";
    updatePaymentMethodUi();
    var nameEl = document.getElementById("pay-card-name");
    var numEl = document.getElementById("pay-card-number");
    var expEl = document.getElementById("pay-card-expiry");
    var cvvEl = document.getElementById("pay-card-cvv");
    if (nameEl) nameEl.value = "";
    if (numEl) numEl.value = "";
    if (expEl) expEl.value = "";
    if (cvvEl) cvvEl.value = "";
  }

  function updatePaymentMethodUi() {
    var tabs = document.querySelectorAll("#payment-method-tabs .payment-tab");
    tabs.forEach(function (tab) {
      tab.classList.toggle("active", tab.dataset.method === paymentMethod);
    });
    document.getElementById("payment-apple-section").hidden = (paymentMethod !== "apple_pay");
    document.getElementById("payment-card-section").hidden = (paymentMethod !== "card");
  }

  function bindPaymentScreen() {
    document.getElementById("payment-back").addEventListener("click", function () {
      navigateToScreen("summary");
    });

    document.getElementById("payment-method-tabs").addEventListener("click", function (e) {
      var tab = e.target.closest(".payment-tab");
      if (!tab || !tab.dataset.method) return;
      paymentMethod = tab.dataset.method;
      updatePaymentMethodUi();
    });

    document.getElementById("payment-pay-btn").addEventListener("click", async function () {
      if (paymentMethod === "card") {
        var cardNo = (valueOf(document.getElementById("pay-card-number")) || "").replace(/\s/g, "");
        if (!isValidCardNumber(cardNo)) { alert("رقم البطاقة غير صالح."); return; }
        if (!isValidExpiry(valueOf(document.getElementById("pay-card-expiry")))) { alert("تاريخ الانتهاء غير صالح."); return; }
        if (!isValidCvv(valueOf(document.getElementById("pay-card-cvv")))) { alert("CVV غير صالح."); return; }
        if (!valueOf(document.getElementById("pay-card-name"))) { alert("أدخل اسم حامل البطاقة."); return; }
      }

      await completeCheckoutFlow(paymentMethod);
    });
  }

  /* ====================================================================
     Full Checkout Flow: create → upload → init payment → complete
     ==================================================================== */

  async function completeCheckoutFlow(method) {
    var payBtn = document.getElementById("payment-pay-btn");
    payBtn.disabled = true;
    payBtn.textContent = "جاري الإرسال...";

    try {
      // 1. Create promo request
      var createRes = await ApiClient.request("/api/promo/requests/create/", {
        method: "POST",
        body: pendingRequestBody
      });
      if (!createRes.ok) {
        alert(extractError(createRes, "فشل إرسال الطلب"));
        return;
      }

      var requestId = createRes.data && createRes.data.id;

      // 2. Get detail to map item IDs
      var detailRes = requestId ? await ApiClient.get("/api/promo/requests/" + requestId + "/") : null;
      var detailItems = detailRes && detailRes.ok && detailRes.data && Array.isArray(detailRes.data.items)
        ? detailRes.data.items : ((createRes.data && createRes.data.items) || []);
      var ids = {};
      detailItems.forEach(function (item) {
        if (item && item.id) ids[(item.service_type || "") + ":" + (item.sort_order || 0)] = item.id;
      });

      // 3. Upload assets
      payBtn.textContent = "جاري رفع المرفقات...";
      var uploadFailures = [];
      for (var x = 0; x < selectedServices.length; x++) {
        var s = selectedServices[x];
        var sBlock = document.querySelector('[data-service-block="' + s + '"]');
        var fileInput = sBlock ? sBlock.querySelector('[data-field="files"]') : null;
        var files = fileInput && fileInput.files ? Array.from(fileInput.files) : [];
        for (var y = 0; y < files.length; y++) {
          var sourceFile = files[y];
          var uploadFile = sourceFile;
          var uploadType = detectAssetType(sourceFile.name);
          if (s === "home_banner" && uploadType === "image" && homeBannerAutoFitEnabled()) {
            try {
              uploadFile = await normalizeHomeBannerImage(sourceFile);
              uploadType = "image";
            } catch (normalizeErr) {
              uploadFailures.push(
                (sourceFile.name || "ملف") + ": تعذر ضبط الصورة تلقائياً قبل الرفع."
              );
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

      // 4. Init payment
      payBtn.textContent = "جاري تهيئة الدفع...";
      var invoiceId = createRes.data && createRes.data.invoice;
      if (invoiceId) {
        var idempotencyKey = "promo-" + invoiceId + "-" + Date.now();
        var initRes = await ApiClient.request("/api/billing/invoices/" + invoiceId + "/init-payment/", {
          method: "POST",
          body: { provider: "mock", idempotency_key: idempotencyKey }
        });

        if (initRes.ok) {
          // 5. Complete payment
          payBtn.textContent = "جاري إتمام الدفع...";
          var payRes = await ApiClient.request("/api/billing/invoices/" + invoiceId + "/complete-mock-payment/", {
            method: "POST",
            body: { idempotency_key: idempotencyKey }
          });
          if (!payRes.ok) {
            alert(extractError(payRes, "تعذر إتمام الدفع. تم إنشاء الطلب ويمكنك الدفع لاحقاً من طلباتي."));
          }
        }
      }

      var requestCode = (createRes.data && createRes.data.code) || "";
      var detailCode = detailRes && detailRes.ok && detailRes.data && detailRes.data.code;
      if (detailCode) requestCode = detailCode;

      // 6. Done — go back to requests list
      navigateToScreen("main");
      resetForm();
      document.querySelector('[data-tab="requests"]').click();
      await loadRequests();

      if (uploadFailures.length) {
        alert("تم إنشاء الطلب والدفع، لكن فشل رفع " + uploadFailures.length + " مرفق/مرفقات.\n" + uploadFailures[0]);
      } else {
        showSuccessDialog(requestCode);
      }
    } catch (err) {
      console.error("Checkout flow failed", err);
      alert("تعذر إكمال عملية الدفع. حاول مرة أخرى.");
    } finally {
      payBtn.disabled = false;
      payBtn.textContent = "دفع";
      pendingPreviewData = null;
      pendingRequestBody = null;
    }
  }

  /* ====================================================================
     Success Dialog
     ==================================================================== */

  function showSuccessDialog(requestCode) {
    var modal = document.getElementById("promo-success-modal");
    var codeEl = document.getElementById("success-request-code");
    var closeBtn = document.getElementById("success-close-btn");
    if (!modal) return;

    codeEl.textContent = "رقم الطلب: " + (requestCode || "—");
    modal.hidden = false;
    document.body.style.overflow = "hidden";

    function close() {
      modal.hidden = true;
      document.body.style.overflow = "";
      closeBtn.removeEventListener("click", close);
    }
    closeBtn.addEventListener("click", close);
  }

  /* ====================================================================
     Card Validation
     ==================================================================== */

  function isValidCardNumber(value) {
    if (!value || value.length < 12 || value.length > 19 || !/^\d+$/.test(value)) return false;
    var sum = 0;
    var alternate = false;
    for (var i = value.length - 1; i >= 0; i--) {
      var n = parseInt(value[i], 10);
      if (alternate) {
        n *= 2;
        if (n > 9) n -= 9;
      }
      sum += n;
      alternate = !alternate;
    }
    return sum % 10 === 0;
  }

  function isValidExpiry(value) {
    var normalized = (value || "").trim();
    if (!/^\d{2}\/\d{2}$/.test(normalized)) return false;
    var parts = normalized.split("/");
    var month = parseInt(parts[0], 10);
    var year = parseInt(parts[1], 10);
    if (month < 1 || month > 12) return false;
    var now = new Date();
    var fullYear = 2000 + year;
    var expiry = new Date(fullYear, month, 0, 23, 59, 59);
    return expiry > now;
  }

  function isValidCvv(value) {
    return /^\d{3,4}$/.test((value || "").trim());
  }

  document.addEventListener("DOMContentLoaded", init);
  return { init: init };
})();
