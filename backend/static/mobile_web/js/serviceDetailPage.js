"use strict";
var ServiceDetailPage = (function () {
  var RAW_API = window.ApiClient;
  var API = window.NwApiClient;
  var Cache = window.NwCache || {
    get: function () { return null; },
    set: function () {},
  };
  var serviceId = null;
  var serviceData = null;
  var COPY = {
    ar: {
      pageTitle: "تفاصيل الخدمة",
      notFound: "خدمة غير موجودة",
      loadFailed: "تعذر تحميل الخدمة",
      fallbackTitle: "تفاصيل الخدمة",
      noDescription: "لا يوجد وصف للخدمة.",
      userFallback: "مستخدم",
      reportButtonTitle: "إبلاغ عن الخدمة",
      providerProfileAria: "فتح ملف مقدم الخدمة",
      requestService: "طلب الخدمة",
      providerMessages: "رسائل مقدم الخدمة",
      commentsTitle: "التعليقات",
      mediaCount: "فيديو {videos} • صور {images}",
      currency: "ر.س",
      originalLanguageNotice: "بعض تفاصيل الخدمة والأسماء والتعليقات تُعرض بلغتها الأصلية.",
      reportFallbackAlert: "تم إرسال البلاغ للإدارة. شكراً لك",
      reportTitle: "إبلاغ عن محتوى خدمة",
      serviceLabel: "الخدمة:",
      providerLabel: "مزود الخدمة: {provider}",
      reportReasonLabel: "سبب الإبلاغ:",
      reportDetailsLabel: "تفاصيل إضافية (اختياري):",
      reportDetailsPlaceholder: "اكتب التفاصيل هنا...",
      reportCancel: "إلغاء",
      reportSubmit: "إرسال البلاغ",
      reportSuccess: "تم إرسال البلاغ للإدارة. شكراً لك",
      reportReasonInappropriate: "محتوى غير لائق",
      reportReasonHarassment: "تحرش أو إزعاج",
      reportReasonFraud: "احتيال أو نصب",
      reportReasonAbuse: "محتوى مسيء",
      reportReasonPrivacy: "انتهاك الخصوصية",
      reportReasonOther: "أخرى",
      serviceFallback: "خدمة",
      providerFallbackLabel: "مقدم خدمة",
    },
    en: {
      pageTitle: "Service details",
      notFound: "Service not found",
      loadFailed: "Unable to load the service",
      fallbackTitle: "Service details",
      noDescription: "No service description is available.",
      userFallback: "User",
      reportButtonTitle: "Report service",
      providerProfileAria: "Open provider profile",
      requestService: "Request service",
      providerMessages: "Message provider",
      commentsTitle: "Comments",
      mediaCount: "Videos {videos} • Images {images}",
      currency: "SAR",
      originalLanguageNotice: "Some service details, names, and comments are shown in their original language.",
      reportFallbackAlert: "Your report has been sent to the administrators. Thank you.",
      reportTitle: "Report service content",
      serviceLabel: "Service:",
      providerLabel: "Provider: {provider}",
      reportReasonLabel: "Report reason:",
      reportDetailsLabel: "Additional details (optional):",
      reportDetailsPlaceholder: "Write the details here...",
      reportCancel: "Cancel",
      reportSubmit: "Send report",
      reportSuccess: "Your report has been sent to the administrators. Thank you.",
      reportReasonInappropriate: "Inappropriate content",
      reportReasonHarassment: "Harassment or disturbance",
      reportReasonFraud: "Fraud or scam",
      reportReasonAbuse: "Abusive content",
      reportReasonPrivacy: "Privacy violation",
      reportReasonOther: "Other",
      serviceFallback: "Service",
      providerFallbackLabel: "Provider",
    },
  };

  function init() {
    var m = location.pathname.match(/\/service\/(\d+)/);
    document.addEventListener("nawafeth:languagechange", _handleLanguageChange);
    _applyStaticCopy();
    if (!m) { document.getElementById("sd-loading").innerHTML = '<p class="text-muted">' + _copy().notFound + '</p>'; return; }
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
      .catch(function () { if (!cached) document.getElementById("sd-loading").innerHTML = '<p class="text-muted">' + _copy().loadFailed + '</p>'; });
  }

  function render(d) {
    serviceData = d;
    _applyStaticCopy();
    document.getElementById("sd-loading").style.display = "none";
    document.getElementById("sd-content").style.display = "";

    // Provider info
    var avatar = d.provider_avatar || d.provider?.avatar || "";
    var sdAvatarEl = document.getElementById("sd-provider-avatar");
    sdAvatarEl.innerHTML = avatar
      ? '<img src="' + API.mediaUrl(avatar) + '" alt="">'
      : '<div class="avatar-placeholder">' + ((d.provider_name || d.provider?.name || "؟").charAt(0)) + '</div>';
    // Presence dot – service detail always shows a provider.
    var sdIsOnline = !!(d.provider_is_online || d.provider?.is_online);
    var sdDot = document.createElement('span');
    sdDot.className = 'nw-presence-dot ' + (sdIsOnline ? 'is-online' : 'is-offline');
    sdDot.setAttribute('aria-hidden', 'true');
    sdAvatarEl.appendChild(sdDot);
    document.getElementById("sd-provider-name").textContent = d.provider_name || d.provider?.name || "";
    document.getElementById("sd-provider-category").textContent =
      d.category_name || d.subcategory?.category_name || d.category?.name || "";
    _setAutoDirection(document.getElementById("sd-provider-name"), d.provider_name || d.provider?.name || "");
    _setAutoDirection(document.getElementById("sd-provider-category"), d.category_name || d.subcategory?.category_name || d.category?.name || "");

    // Service
    var serviceTitle = d.name || d.title || _copy().fallbackTitle;
    document.getElementById("sd-name").textContent = serviceTitle;
    var pageTitle = document.getElementById("sd-page-title");
    if (pageTitle) pageTitle.textContent = serviceTitle;
    _setAutoDirection(document.getElementById("sd-name"), serviceTitle);
    _setAutoDirection(pageTitle, serviceTitle);
    document.getElementById("sd-likes").textContent = d.likes_count || d.likes || 0;
    var description = String(d.description || "").trim();
    document.getElementById("sd-description").textContent = description || _copy().noDescription;
    _setAutoDirection(document.getElementById("sd-description"), description);

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
    if (mediaCountEl) mediaCountEl.textContent = _replaceTokens(_copy().mediaCount, { videos: videoCount, images: imageCount });

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
      commentsWrap.innerHTML = "";
      comments.forEach(function (c) {
        var item = document.createElement("div");
        item.className = "sd-comment";

        var author = document.createElement("strong");
        var authorText = c.user_name || c.user?.name || _copy().userFallback;
        author.textContent = authorText;
        _setAutoDirection(author, authorText);
        item.appendChild(author);

        var body = document.createElement("p");
        var commentText = c.text || c.content || "";
        body.textContent = commentText;
        _setAutoDirection(body, commentText);
        item.appendChild(body);

        var meta = document.createElement("span");
        meta.className = "text-muted";
        meta.textContent = c.created_at ? new Date(c.created_at).toLocaleDateString("ar-SA") : "";
        item.appendChild(meta);

        commentsWrap.appendChild(item);
      });
    } else if (commentsSection && commentsWrap) {
      commentsSection.style.display = "none";
      commentsWrap.innerHTML = "";
    }

    _updateOriginalLanguageNotice();

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
        requestBtn.href = "/service-request/?service_id=" + encodeURIComponent(String(serviceId)) + "&provider_id=" + normalizedProviderId + "&return_to=" + encodeURIComponent(window.location.pathname + window.location.search);
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

  function _currentLang() {
    try {
      if (window.NawafethI18n && typeof window.NawafethI18n.getLanguage === "function") {
        return window.NawafethI18n.getLanguage() === "en" ? "en" : "ar";
      }
      return (localStorage.getItem("nw_lang") || "ar").toLowerCase() === "en" ? "en" : "ar";
    } catch (_) {
      return "ar";
    }
  }

  function _copy() {
    return COPY[_currentLang()] || COPY.ar;
  }

  function _replaceTokens(text, replacements) {
    return String(text || "").replace(/\{(\w+)\}/g, function (_, key) {
      return Object.prototype.hasOwnProperty.call(replacements || {}, key)
        ? String(replacements[key])
        : "";
    });
  }

  function _applyStaticCopy() {
    var copy = _copy();
    if (window.NawafethI18n && typeof window.NawafethI18n.t === "function") {
      document.title = window.NawafethI18n.t("siteTitle") + " — " + copy.pageTitle;
    }
    _setText("sd-page-title", serviceData && (serviceData.name || serviceData.title) ? (serviceData.name || serviceData.title) : copy.pageTitle);
    _setText("sd-btn-request", copy.requestService);
    _setText("sd-btn-chat", copy.providerMessages);
    _setText("sd-comments-title", copy.commentsTitle);
    _setAttr("btn-report", "title", copy.reportButtonTitle);
    _setAttr("btn-report", "aria-label", copy.reportButtonTitle);
    _setAttr("sd-provider-link", "aria-label", copy.providerProfileAria);
  }

  function _setText(id, value) {
    var el = document.getElementById(id);
    if (el) el.textContent = value;
  }

  function _setAttr(id, attr, value) {
    var el = document.getElementById(id);
    if (el) el.setAttribute(attr, value);
  }

  function _locale() {
    return _currentLang() === "en" ? "en-US" : "ar-SA";
  }

  function _containsArabicScript(value) {
    return /[\u0600-\u06FF]/.test(String(value || "").trim());
  }

  function _setAutoDirection(el, value) {
    if (!el) return;
    if (String(value || "").trim()) el.setAttribute("dir", "auto");
    else el.removeAttribute("dir");
  }

  function _hasOriginalLanguageContent() {
    if (!serviceData || _currentLang() !== "en") return false;

    var directFields = [
      serviceData.name,
      serviceData.title,
      serviceData.description,
      serviceData.provider_name,
      serviceData.provider?.name,
    ];
    if (directFields.some(_containsArabicScript)) return true;

    var comments = Array.isArray(serviceData.comments) ? serviceData.comments : [];
    return comments.some(function (c) {
      return _containsArabicScript(c && (c.user_name || c.user?.name)) || _containsArabicScript(c && (c.text || c.content));
    });
  }

  function _updateOriginalLanguageNotice() {
    var note = document.getElementById("sd-original-language-note");
    if (!note) return;
    note.textContent = _copy().originalLanguageNotice;
    note.style.display = _hasOriginalLanguageContent() ? "" : "none";
  }

  function _handleLanguageChange() {
    if (!serviceData) {
      _updateOriginalLanguageNotice();
      return;
    }
    render(serviceData);
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
    var currency = _copy().currency;

    if (!isFinite(from) && !isFinite(to)) return "";
    if (isFinite(from) && isFinite(to)) {
      if (Math.abs(from - to) < 0.0001) return formatCompactNumber(from) + suffix + " " + currency;
      return formatCompactNumber(from) + " - " + formatCompactNumber(to) + suffix + " " + currency;
    }
    var value = isFinite(from) ? from : to;
    if (!isFinite(value)) return "";
    return formatCompactNumber(value) + suffix + " " + currency;
  }

  function _trimText(value) {
    return String(value || "").trim();
  }

  function _openReportDialog() {
    if (typeof UI === "undefined" || !UI.el) {
      alert(_copy().reportFallbackAlert);
      return;
    }

    var reasons = [
      _copy().reportReasonInappropriate,
      _copy().reportReasonHarassment,
      _copy().reportReasonFraud,
      _copy().reportReasonAbuse,
      _copy().reportReasonPrivacy,
      _copy().reportReasonOther,
    ];

    var serviceName = _trimText(document.getElementById("sd-name")?.textContent) || _copy().serviceFallback;
    var providerName = _trimText(document.getElementById("sd-provider-name")?.textContent) || _copy().providerFallbackLabel;

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
      textContent: _copy().reportTitle,
    }));
    dialog.appendChild(titleRow);

    var infoBox = UI.el("div", { className: "pd-report-info" });
    infoBox.appendChild(UI.el("p", {
      className: "pd-report-info-label",
      textContent: _copy().serviceLabel,
    }));
    infoBox.appendChild(UI.el("p", {
      className: "pd-report-info-value",
      textContent: serviceName,
    }));
    infoBox.appendChild(UI.el("p", {
      className: "pd-report-context",
      textContent: _replaceTokens(_copy().providerLabel, { provider: providerName }),
    }));
    dialog.appendChild(infoBox);

    var reasonLabel = UI.el("label", {
      className: "pd-report-label",
      textContent: _copy().reportReasonLabel,
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
      textContent: _copy().reportDetailsLabel,
    });
    detailsLabel.setAttribute("for", "sd-report-details");
    dialog.appendChild(detailsLabel);

    var detailsInput = UI.el("textarea", {
      className: "pd-report-textarea",
      id: "sd-report-details",
      rows: 4,
      placeholder: _copy().reportDetailsPlaceholder,
    });
    detailsInput.maxLength = 500;
    dialog.appendChild(detailsInput);

    var actions = UI.el("div", { className: "pd-report-actions" });
    var cancelBtn = UI.el("button", {
      type: "button",
      className: "pd-report-btn pd-report-btn-cancel",
      textContent: _copy().reportCancel,
    });
    cancelBtn.addEventListener("click", closeDialog);

    var submitBtn = UI.el("button", {
      type: "button",
      className: "pd-report-btn pd-report-btn-submit",
      textContent: _copy().reportSubmit,
    });
    submitBtn.addEventListener("click", function () {
      closeDialog();
      _showToast(_copy().reportSuccess);
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
