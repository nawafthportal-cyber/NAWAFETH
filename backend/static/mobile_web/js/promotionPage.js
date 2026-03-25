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
    promo_messages: [".jpg", ".jpeg", ".png", ".mp4", ".pdf"],
    sponsorship: [".jpg", ".jpeg", ".png", ".mp4", ".pdf"]
  };

  var selectedServices = [];
  var requestsCache = {};
  var modalState = { resolve: null };
  var modalElements = null;
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
      listEl.innerHTML = rows.map(renderRequestCard).join("");
    } catch (err) {
      loading.style.display = "none";
      listEl.innerHTML = '<p class="text-muted">تعذر تحميل الطلبات</p>';
    }
  }

  function canPayRequest(row) {
    var invoiceId = parseInt(String((row && row.invoice) || ""), 10);
    var status = String((row && row.status) || "").trim();
    return !!invoiceId && row && row.payment_effective !== true && (status === "pending_payment" || status === "quoted");
  }

  function renderRequestCard(row) {
    var items = Array.isArray(row.items) ? row.items : [];
    var summary = items.slice(0, 3).map(function (item) {
      return SERVICE_LABELS[item.service_type] || item.service_type || "";
    }).join("، ");
    var footerBits = [
      '<span>' + items.length + ' خدمة</span>',
      summary ? '<span class="text-muted">' + escapeHtml(summary) + '</span>' : ""
    ].filter(Boolean).join("");
    var actions = [
      '<button type="button" class="btn btn-secondary" data-request-action="details" data-request-id="' + row.id + '">التفاصيل</button>'
    ];
    if (canPayRequest(row)) {
      actions.push('<button type="button" class="btn btn-primary" data-request-action="pay" data-request-id="' + row.id + '">الدفع الآن</button>');
    }
    return '<div class="promo-card">' +
      '<div class="promo-card-header">' +
      '<div class="promo-info"><strong>' + escapeHtml(row.title || "طلب ترويج") + '</strong><span class="text-muted">' + escapeHtml(row.code || "") + '</span></div>' +
      '<span class="badge">' + escapeHtml(STATUS_LABELS[row.status] || row.status || "") + '</span>' +
      '</div>' +
      '<div class="promo-card-footer">' + footerBits + '</div>' +
      (row.invoice_total != null ? '<div class="promo-card-footer"><span>الإجمالي</span><strong>' + money(row.invoice_total) + ' ريال</strong></div>' : "") +
      '<div class="promo-card-actions">' + actions.join("") + '</div>' +
      '</div>';
  }

  async function showRequestDetails(row) {
    var confirmed = await openModal({
      title: row.title || "طلب ترويج",
      bodyHtml: buildRequestDetailsHtml(row),
      confirmText: canPayRequest(row) ? "الدفع الآن" : null,
      cancelText: "إغلاق"
    });
    if (confirmed && canPayRequest(row)) {
      await startPayment(row);
    }
  }

  function buildRequestDetailsHtml(row) {
    var items = Array.isArray(row.items) ? row.items : [];
    var parts = [
      '<div class="promo-modal-section">',
      lineHtml("رقم الطلب", row.code || ""),
      lineHtml("الحالة", STATUS_LABELS[row.status] || row.status || ""),
      lineHtml("التنفيذ", OPS_LABELS[row.ops_status] || row.ops_status || ""),
      row.invoice_code ? lineHtml("رقم الفاتورة", row.invoice_code) : "",
      row.invoice_status ? lineHtml("حالة الفاتورة", row.payment_effective === true ? "مدفوعة" : (INVOICE_STATUS_LABELS[row.invoice_status] || row.invoice_status)) : "",
      row.invoice_total != null ? lineHtml("الإجمالي", money(row.invoice_total) + " ريال") : "",
      row.invoice_vat != null ? lineHtml("VAT", money(row.invoice_vat) + " ريال") : "",
      row.quote_note ? lineHtml("ملاحظة الاعتماد", row.quote_note) : "",
      '</div>'
    ];
    if (items.length) {
      parts.push('<div class="promo-modal-section"><h4>الخدمات</h4>');
      items.forEach(function (item) {
        parts.push(
          '<div class="promo-modal-item">' +
            '<strong>' + escapeHtml(item.title || SERVICE_LABELS[item.service_type] || item.service_type || "") + '</strong>' +
            '<div class="text-muted">' +
              escapeHtml(SERVICE_LABELS[item.service_type] || item.service_type || "") +
              (item.subtotal != null ? ' • ' + money(item.subtotal) + ' ريال' : "") +
              '</div>' +
          '</div>'
        );
      });
      parts.push('</div>');
    }
    return parts.join("");
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

        button.textContent = "جاري الإرسال...";
        var createRes = await ApiClient.request("/api/promo/requests/create/", {
          method: "POST",
          body: requestBody
        });
        if (!createRes.ok) {
          alert(extractError(createRes, "فشل إرسال الطلب"));
          return;
        }

        var requestId = createRes.data && createRes.data.id;
        var detailRes = requestId ? await ApiClient.get("/api/promo/requests/" + requestId + "/") : null;
        var detailItems = detailRes && detailRes.ok && detailRes.data && Array.isArray(detailRes.data.items)
          ? detailRes.data.items : ((createRes.data && createRes.data.items) || []);
        var ids = {};
        detailItems.forEach(function (item) {
          if (item && item.id) ids[(item.service_type || "") + ":" + (item.sort_order || 0)] = item.id;
        });

        var uploadFailures = [];
        for (var x = 0; x < selectedServices.length; x += 1) {
          var s = selectedServices[x];
          var sBlock = document.querySelector('[data-service-block="' + s + '"]');
          var fileInput = sBlock.querySelector('[data-field="files"]');
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
                uploadFailures.push(
                  (sourceFile && sourceFile.name ? sourceFile.name : "ملف")
                  + ": تعذر ضبط الصورة تلقائياً قبل الرفع. استخدم صورة صالحة أو ألغِ خيار الضبط التلقائي."
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
              uploadFailures.push((uploadFile && uploadFile.name ? uploadFile.name : "ملف") + ": " + extractError(uploadRes, "تعذر رفع المرفق"));
            }
          }
        }

        if (uploadFailures.length) {
          resetForm();
          document.querySelector('[data-tab="requests"]').click();
          await loadRequests();
          alert("تم إنشاء الطلب، لكن فشل رفع " + uploadFailures.length + " مرفق/مرفقات. " + uploadFailures[0]);
          return;
        }

        resetForm();
        document.querySelector('[data-tab="requests"]').click();
        await loadRequests();
        alert("تم إرسال طلب الترويج بنجاح");
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

  function extractError(response, fallback) {
    if (!response || !response.data) return fallback;
    if (typeof response.data.detail === "string" && response.data.detail) return response.data.detail;
    if (typeof response.data === "string") return response.data;
    var details = [];
    Object.keys(response.data).forEach(function (key) {
      var value = response.data[key];
      details.push(Array.isArray(value) ? value.join(", ") : String(value));
    });
    return details.length ? details.join("\n") : fallback;
  }

  function escapeHtml(value) {
    return String(value || "").replace(/[&<>"']/g, function (char) {
      return ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char];
    });
  }

  document.addEventListener("DOMContentLoaded", init);
  return { init: init };
})();
