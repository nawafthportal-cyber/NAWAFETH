"use strict";
var ServiceDetailPage = (function () {
  var RAW_API = window.ApiClient;
  var API = window.NwApiClient;
  var Cache = window.NwCache;
  var serviceId = null;
  var serviceData = null;

  function init() {
    var m = location.pathname.match(/\/service\/(\d+)/);
    if (!m) { document.getElementById("sd-loading").innerHTML = '<p class="text-muted">خدمة غير موجودة</p>'; return; }
    serviceId = m[1];
    var reportBtn = document.getElementById("btn-report");
    if (reportBtn) reportBtn.addEventListener("click", _openReportDialog);
    load();
  }

  function load() {
    var cached = Cache.get("service_" + serviceId);
    if (cached) { render(cached); }
    RAW_API.get("/api/providers/services/" + serviceId + "/")
      .then(function (resp) {
        if (!resp || !resp.ok || !resp.data) {
          throw new Error("service_not_found");
        }
        Cache.set("service_" + serviceId, resp.data, 120);
        render(resp.data);
      })
      .catch(function () { if (!cached) document.getElementById("sd-loading").innerHTML = '<p class="text-muted">تعذر تحميل الخدمة</p>'; });
  }

  function render(d) {
    serviceData = d;
    document.getElementById("sd-loading").style.display = "none";
    document.getElementById("sd-content").style.display = "";

    // Provider info
    var avatar = d.provider_avatar || d.provider?.avatar || "";
    document.getElementById("sd-provider-avatar").innerHTML = avatar
      ? '<img src="' + API.mediaUrl(avatar) + '" alt="">'
      : '<div class="avatar-placeholder">' + ((d.provider_name || d.provider?.name || "؟").charAt(0)) + '</div>';
    document.getElementById("sd-provider-name").textContent = d.provider_name || d.provider?.name || "";
    document.getElementById("sd-provider-category").textContent =
      d.category_name || d.subcategory?.category_name || d.category?.name || "";

    // Service
    var serviceTitle = d.name || d.title || "تفاصيل الخدمة";
    document.getElementById("sd-name").textContent = serviceTitle;
    var pageTitle = document.getElementById("sd-page-title");
    if (pageTitle) pageTitle.textContent = serviceTitle;
    document.getElementById("sd-likes").textContent = d.likes_count || d.likes || 0;
    var description = String(d.description || "").trim();
    document.getElementById("sd-description").textContent = description || "لا يوجد وصف للخدمة.";

    var mediaCountEl = document.getElementById("sd-media-count");
    var filesCountRaw = asNumber(d.files_count || d.filesCount || d.media_count || d.mediaCount);

    // Price
    var priceLabel = buildPriceLabel(d);
    var priceEl = document.getElementById("sd-price");
    if (priceLabel) {
      priceEl.style.display = "";
      priceEl.textContent = priceLabel;
    } else if (priceEl) {
      priceEl.style.display = "none";
      priceEl.textContent = "";
    }

    // Images slider
    var images = d.images || d.media || [];
    if (!Array.isArray(images)) images = [];
    var totalFiles = isFinite(filesCountRaw)
      ? Math.max(0, Math.floor(filesCountRaw))
      : images.length;
    if (!totalFiles && images.length) totalFiles = images.length;
    var videoCount = totalFiles > 0 ? 1 : 0;
    var imageCount = totalFiles > 1 ? (totalFiles - 1) : totalFiles;
    if (mediaCountEl) mediaCountEl.textContent = "فيديو " + videoCount + " • صور " + imageCount;

    var slider = document.getElementById("sd-slider");
    var track = document.getElementById("sd-slider-track");
    var thumbs = document.getElementById("sd-slider-thumbs");
    if (images.length) {
      slider.style.display = "";
      track.innerHTML = images.map(function (img) {
        var src = typeof img === "string" ? img : img.image || img.url || img.file;
        return '<div class="sd-slide"><img src="' + API.mediaUrl(src) + '" alt=""></div>';
      }).join("");
      thumbs.innerHTML = images.map(function (img, i) {
        var src = typeof img === "string" ? img : img.image || img.url || img.file;
        return '<div class="sd-thumb' + (i === 0 ? ' active' : '') + '" data-idx="' + i + '"><img src="' + API.mediaUrl(src) + '" alt=""></div>';
      }).join("");
      thumbs.onclick = function (e) {
        var th = e.target.closest(".sd-thumb");
        if (!th) return;
        var idx = parseInt(th.dataset.idx);
        track.style.transform = "translateX(" + (idx * 100) + "%)";
        thumbs.querySelectorAll(".sd-thumb").forEach(function (t, i) { t.classList.toggle("active", i === idx); });
      };
    } else if (slider && track && thumbs) {
      slider.style.display = "none";
      track.innerHTML = "";
      thumbs.innerHTML = "";
      thumbs.onclick = null;
    }

    // Comments
    var comments = d.comments || [];
    var commentsSection = document.getElementById("sd-comments-section");
    var commentsWrap = document.getElementById("sd-comments");
    if (comments.length) {
      commentsSection.style.display = "";
      commentsWrap.innerHTML = comments.map(function (c) {
        return '<div class="sd-comment"><strong>' + (c.user_name || c.user?.name || "مستخدم") + '</strong>' +
          '<p>' + (c.text || c.content || "") + '</p>' +
          '<span class="text-muted">' + (c.created_at ? new Date(c.created_at).toLocaleDateString("ar-SA") : "") + '</span></div>';
      }).join("");
    } else if (commentsSection && commentsWrap) {
      commentsSection.style.display = "none";
      commentsWrap.innerHTML = "";
    }

    // Buttons
    var providerId = d.provider_id || d.provider?.id || d.provider;
    var providerLink = document.getElementById("sd-provider-link");
    var requestBtn = document.getElementById("sd-btn-request");
    var chatBtn = document.getElementById("sd-btn-chat");

    if (providerId) {
      var normalizedProviderId = encodeURIComponent(String(providerId));
      if (providerLink) {
        providerLink.href = "/provider/" + normalizedProviderId + "/";
        providerLink.classList.remove("is-disabled");
        providerLink.removeAttribute("aria-disabled");
      }
      if (requestBtn) {
        requestBtn.href = "/service-request/?service_id=" + encodeURIComponent(String(serviceId)) + "&provider_id=" + normalizedProviderId;
        requestBtn.classList.remove("is-disabled");
        requestBtn.removeAttribute("aria-disabled");
      }
      if (chatBtn) {
        chatBtn.href = "/chats/?start=" + normalizedProviderId;
        chatBtn.classList.remove("is-disabled");
        chatBtn.removeAttribute("aria-disabled");
      }
      return;
    }

    [providerLink, requestBtn, chatBtn].forEach(function (el) {
      if (!el) return;
      el.href = "#";
      el.classList.add("is-disabled");
      el.setAttribute("aria-disabled", "true");
    });
  }

  function asNumber(value) {
    if (value === null || value === undefined || value === "") return NaN;
    var n = Number(value);
    return isFinite(n) ? n : NaN;
  }

  function formatCompactNumber(value) {
    if (!isFinite(value)) return "";
    if (Math.abs(value - Math.round(value)) < 0.0001) return String(Math.round(value));
    return value.toFixed(2).replace(/0+$/, "").replace(/\.$/, "");
  }

  function buildPriceLabel(service) {
    var from = asNumber(service.price_from || service.min_price);
    var to = asNumber(service.price_to || service.max_price);
    var unit = String(service.price_unit || "").trim();
    var suffix = unit ? (" / " + unit) : "";

    if (!isFinite(from) && !isFinite(to)) return "";
    if (isFinite(from) && isFinite(to)) {
      if (Math.abs(from - to) < 0.0001) return formatCompactNumber(from) + suffix + " ر.س";
      return formatCompactNumber(from) + " - " + formatCompactNumber(to) + suffix + " ر.س";
    }
    var value = isFinite(from) ? from : to;
    if (!isFinite(value)) return "";
    return formatCompactNumber(value) + suffix + " ر.س";
  }

  function _trimText(value) {
    return String(value || "").trim();
  }

  function _openReportDialog() {
    if (typeof UI === "undefined" || !UI.el) {
      alert("تم إرسال البلاغ للإدارة. شكراً لك");
      return;
    }

    var reasons = [
      "محتوى غير لائق",
      "تحرش أو إزعاج",
      "احتيال أو نصب",
      "محتوى مسيء",
      "انتهاك الخصوصية",
      "أخرى",
    ];

    var serviceName = _trimText(document.getElementById("sd-name")?.textContent) || "خدمة";
    var providerName = _trimText(document.getElementById("sd-provider-name")?.textContent) || "مقدم خدمة";

    var oldDialog = document.querySelector(".pd-report-backdrop");
    if (oldDialog) oldDialog.remove();

    var backdrop = UI.el("div", { className: "pd-report-backdrop" });
    var dialog = UI.el("div", { className: "pd-report-dialog" });

    var titleRow = UI.el("div", { className: "pd-report-title-row" });
    var titleIcon = UI.el("span", { className: "pd-report-title-icon" });
    titleIcon.innerHTML = [
      '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">',
      '<path d="M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1z"></path>',
      '<line x1="4" y1="22" x2="4" y2="15"></line>',
      "</svg>",
    ].join("");
    titleRow.appendChild(titleIcon);
    titleRow.appendChild(UI.el("h3", {
      className: "pd-report-title",
      textContent: "إبلاغ عن محتوى خدمة",
    }));
    dialog.appendChild(titleRow);

    var infoBox = UI.el("div", { className: "pd-report-info" });
    infoBox.appendChild(UI.el("p", {
      className: "pd-report-info-label",
      textContent: "الخدمة:",
    }));
    infoBox.appendChild(UI.el("p", {
      className: "pd-report-info-value",
      textContent: serviceName,
    }));
    infoBox.appendChild(UI.el("p", {
      className: "pd-report-context",
      textContent: "مزود الخدمة: " + providerName,
    }));
    dialog.appendChild(infoBox);

    var reasonLabel = UI.el("label", {
      className: "pd-report-label",
      textContent: "سبب الإبلاغ:",
    });
    reasonLabel.setAttribute("for", "sd-report-reason");
    dialog.appendChild(reasonLabel);

    var reasonSelect = UI.el("select", {
      className: "pd-report-select",
      id: "sd-report-reason",
    });
    reasons.forEach(function (reason) {
      reasonSelect.appendChild(UI.el("option", { value: reason, textContent: reason }));
    });
    dialog.appendChild(reasonSelect);

    var detailsLabel = UI.el("label", {
      className: "pd-report-label",
      textContent: "تفاصيل إضافية (اختياري):",
    });
    detailsLabel.setAttribute("for", "sd-report-details");
    dialog.appendChild(detailsLabel);

    var detailsInput = UI.el("textarea", {
      className: "pd-report-textarea",
      id: "sd-report-details",
      rows: 4,
      placeholder: "اكتب التفاصيل هنا...",
    });
    detailsInput.maxLength = 500;
    dialog.appendChild(detailsInput);

    var actions = UI.el("div", { className: "pd-report-actions" });
    var cancelBtn = UI.el("button", {
      type: "button",
      className: "pd-report-btn pd-report-btn-cancel",
      textContent: "إلغاء",
    });
    cancelBtn.addEventListener("click", closeDialog);

    var submitBtn = UI.el("button", {
      type: "button",
      className: "pd-report-btn pd-report-btn-submit",
      textContent: "إرسال البلاغ",
    });
    submitBtn.addEventListener("click", function () {
      closeDialog();
      _showToast("تم إرسال البلاغ للإدارة. شكراً لك");
    });

    actions.appendChild(cancelBtn);
    actions.appendChild(submitBtn);
    dialog.appendChild(actions);

    backdrop.appendChild(dialog);
    document.body.appendChild(backdrop);

    requestAnimationFrame(function () {
      backdrop.classList.add("open");
    });

    backdrop.addEventListener("click", function (e) {
      if (e.target === backdrop) closeDialog();
    });

    function closeDialog() {
      backdrop.classList.remove("open");
      setTimeout(function () {
        backdrop.remove();
      }, 180);
    }
  }

  function _showToast(message) {
    var toast = document.createElement("div");
    toast.textContent = message;
    toast.style.position = "fixed";
    toast.style.left = "50%";
    toast.style.bottom = "24px";
    toast.style.transform = "translateX(-50%)";
    toast.style.background = "#2E2650";
    toast.style.color = "#fff";
    toast.style.padding = "10px 18px";
    toast.style.borderRadius = "12px";
    toast.style.fontSize = "12px";
    toast.style.fontWeight = "700";
    toast.style.fontFamily = "Cairo, sans-serif";
    toast.style.boxShadow = "0 8px 20px rgba(20, 14, 38, 0.2)";
    toast.style.zIndex = "9999";
    document.body.appendChild(toast);
    setTimeout(function () { toast.remove(); }, 2200);
  }

  document.addEventListener("DOMContentLoaded", init);
  return { init: init };
})();
