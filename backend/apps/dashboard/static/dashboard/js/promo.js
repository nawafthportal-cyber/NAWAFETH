(function () {
  "use strict";

  /* closeAlerts — handled globally by _base.html toast system */

  function attachCharCounters() {
    const textareas = document.querySelectorAll("textarea[maxlength]");
    textareas.forEach((textarea) => {
      const max = Number(textarea.getAttribute("maxlength") || 0);
      if (!Number.isFinite(max) || max <= 0) {
        return;
      }
      const counter = document.createElement("small");
      counter.className = "char-counter";
      textarea.insertAdjacentElement("afterend", counter);
      const update = function () {
        const size = (textarea.value || "").length;
        counter.textContent = size + " / " + max;
        counter.style.color = size > max ? "#b83838" : "#6f1d79";
      };
      textarea.addEventListener("input", update);
      update();
    });
  }

  function syncFileSpecs() {
    document.querySelectorAll("input[type='file']").forEach((input) => {
      input.addEventListener("change", () => {
        const form = input.closest("form");
        if (!form) {
          return;
        }
        const specs = form.querySelector("input[name='attachment_specs']");
        if (!specs) {
          return;
        }
        const file = input.files && input.files[0];
        if (!file) {
          specs.value = "";
          return;
        }
        const sizeMb = file.size / (1024 * 1024);
        specs.value = file.name + " - " + sizeMb.toFixed(2) + " MB";
      });
    });
  }

  function setupActionConfirmations() {
    const inquiryForm = document.getElementById("promoInquiryForm");
    if (inquiryForm) {
      inquiryForm.addEventListener("submit", (event) => {
        const submitter = event.submitter;
        if (!submitter) {
          return;
        }
        if ((submitter.value || "") === "close_inquiry") {
          if (!window.confirm("تأكيد إغلاق الاستفسار؟")) {
            event.preventDefault();
          }
        }
      });
    }

    document.querySelectorAll("form[data-single-submit-form='true']").forEach((form) => {
      form.addEventListener("submit", (event) => {
        const submitter = event.submitter;
        if (!submitter || submitter.dataset.lockOnSubmit !== "true") {
          return;
        }
        if (submitter.dataset.submitting === "1") {
          event.preventDefault();
          return;
        }

        submitter.dataset.submitting = "1";
        submitter.disabled = true;
        const pendingText = submitter.getAttribute("data-pending-text") || "";
        if (pendingText) {
          submitter.textContent = pendingText;
        }
      });
    });
  }

  function setupPromoLightbox() {
    const lightbox = document.getElementById("promoLightbox");
    const closeBtn = document.getElementById("promoLightboxClose");
    const image = document.getElementById("promoLightboxImage");
    const title = document.getElementById("promoLightboxTitle");
    if (!lightbox || !closeBtn || !image || !title) {
      return;
    }

    function closeLightbox() {
      lightbox.hidden = true;
      image.src = "";
      title.textContent = "";
    }

    document.querySelectorAll(".promo-asset-lightbox-trigger").forEach((btn) => {
      btn.addEventListener("click", () => {
        const src = btn.getAttribute("data-lightbox-src") || "";
        const label = btn.getAttribute("data-lightbox-title") || "مرفق ترويجي";
        if (!src) {
          return;
        }
        image.src = src;
        title.textContent = label;
        lightbox.hidden = false;
      });
    });

    closeBtn.addEventListener("click", closeLightbox);
    lightbox.addEventListener("click", (event) => {
      if (event.target === lightbox) {
        closeLightbox();
      }
    });
    document.addEventListener("keydown", (event) => {
      if (event.key === "Escape" && !lightbox.hidden) {
        closeLightbox();
      }
    });
  }

  function setupInquiryCommentLinkInsertion() {
    const form = document.getElementById("promoInquiryForm");
    if (!form) {
      return;
    }

    const insertBtn = document.getElementById("insertPromoDetailLinkBtn");
    const commentField = form.querySelector("textarea[name='operator_comment']");
    const detailUrlField = form.querySelector("input[name='detailed_request_url']");
    if (!insertBtn || !commentField || !detailUrlField) {
      return;
    }

    const linkLabel = "رابط خيارات الترويج التفصيلية: ";

    function updateButtonState() {
      const url = (detailUrlField.value || "").trim();
      insertBtn.disabled = !url;
      insertBtn.setAttribute("aria-disabled", insertBtn.disabled ? "true" : "false");
    }

    function insertAtSelection(textarea, text) {
      const value = textarea.value || "";
      const hasSelection =
        Number.isInteger(textarea.selectionStart) && Number.isInteger(textarea.selectionEnd);
      const start = hasSelection ? textarea.selectionStart : value.length;
      const end = hasSelection ? textarea.selectionEnd : value.length;
      const nextValue = value.slice(0, start) + text + value.slice(end);
      textarea.value = nextValue;
      const cursor = start + text.length;
      textarea.focus();
      if (typeof textarea.setSelectionRange === "function") {
        textarea.setSelectionRange(cursor, cursor);
      }
      textarea.dispatchEvent(new Event("input", { bubbles: true }));
    }

    insertBtn.addEventListener("click", () => {
      const url = (detailUrlField.value || "").trim();
      if (!url) {
        detailUrlField.focus();
        return;
      }

      if ((commentField.value || "").includes(url)) {
        commentField.focus();
        return;
      }

      const snippet = linkLabel + url;
      const rawValue = commentField.value || "";
      const max = Number(commentField.getAttribute("maxlength") || 0);

      let prefix = "";
      const hasSelection =
        Number.isInteger(commentField.selectionStart) && Number.isInteger(commentField.selectionEnd);
      const start = hasSelection ? commentField.selectionStart : rawValue.length;
      const beforeSelection = rawValue.slice(0, start);
      if (beforeSelection.trim()) {
        prefix = beforeSelection.endsWith("\n") ? "" : "\n";
      }

      const insertText = prefix + snippet;
      if (Number.isFinite(max) && max > 0 && rawValue.length + insertText.length > max) {
        window.alert("لا يمكن إدراج الرابط لأن تعليق المكلف سيتجاوز الحد الأقصى (300 حرف).");
        commentField.focus();
        return;
      }

      insertAtSelection(commentField, insertText);
    });

    detailUrlField.addEventListener("input", updateButtonState);
    updateButtonState();
  }

  function scrollActiveRow() {
    const row = document.querySelector(".active-ticket");
    if (row) {
      row.scrollIntoView({ block: "center", behavior: "smooth" });
    }
  }

  function hideLegacyPreviewSummary() {
    const section = document.querySelector("[data-legacy-preview-summary='true']");
    if (!section) {
      return;
    }
    section.hidden = true;
    section.setAttribute("aria-hidden", "true");
  }

  function setupModuleWorkflow() {
    const moduleForm = document.getElementById("promoModuleForm");
    if (!moduleForm) {
      return;
    }
    const moduleKey = String(moduleForm.dataset.moduleKey || "").toLowerCase();
    moduleForm.addEventListener("submit", (event) => {
      const submitter = event.submitter;
      if (!submitter) {
        return;
      }

      if (moduleForm.dataset.submitting === "1") {
        event.preventDefault();
        return;
      }

      const confirmMessage = submitter.getAttribute("data-require-confirm") || "";
      if (confirmMessage && !window.confirm(confirmMessage)) {
        event.preventDefault();
        return;
      }

      const value = (submitter.value || "").toLowerCase();
      const originalText = submitter.textContent;
      moduleForm.dataset.submitting = "1";
      moduleForm.querySelectorAll("button[type='submit']").forEach((button) => {
        button.disabled = true;
      });
      submitter.disabled = true;
      submitter.dataset.submitting = "1";
      if (value === "preview_item") {
        submitter.textContent = "جار تجهيز المعاينة...";
      } else if (
        moduleKey === "home_banner" ||
        moduleKey === "featured_specialists" ||
        moduleKey === "portfolio_showcase" ||
        moduleKey === "snapshots" ||
        moduleKey === "search_results"
      ) {
        submitter.textContent = "جار حفظ البند...";
      } else {
        submitter.textContent = "جار اعتماد البند...";
      }

      window.setTimeout(() => {
        if (submitter.dataset.submitting === "1") {
          delete moduleForm.dataset.submitting;
          moduleForm.querySelectorAll("button[type='submit']").forEach((button) => {
            button.disabled = false;
          });
          submitter.textContent = originalText;
          delete submitter.dataset.submitting;
        }
      }, 6500);
    });
  }

  function setupHomeBannerModulePreview() {
    const moduleForm = document.getElementById("promoModuleForm");
    if (!moduleForm) {
      return;
    }
    const moduleKey = String(moduleForm.dataset.moduleKey || "").toLowerCase();
    if (moduleKey !== "home_banner") {
      return;
    }

    const root = document.getElementById("homeBannerModule");
    const requestInput = moduleForm.querySelector("input[name='request_id']");
    const titleInput = moduleForm.querySelector("input[name='title']");
    const startAtInput = moduleForm.querySelector("input[name='start_at']");
    const endAtInput = moduleForm.querySelector("input[name='end_at']");
    const mediaInput = moduleForm.querySelector("input[name='media_file']");
    const previewScreen = document.getElementById("homeBannerPhonePreviewMedia");
    const emptyState = document.getElementById("homeBannerPhonePreviewEmpty");
    const metaText = document.getElementById("homeBannerPreviewMeta");
    const summaryText = document.getElementById("homeBannerPreviewSummary");
    const requesterLabel = document.getElementById("homeBannerRequesterLabel");
    const requestBadge = document.getElementById("homeBannerPreviewRequestBadge");
    const periodBadge = document.getElementById("homeBannerPreviewPeriodBadge");
    const specsInput = moduleForm.querySelector("input[name='attachment_specs']");
    const previewButton = moduleForm.querySelector("[data-live-preview-focus='true']");
    if (
      !root ||
      !requestInput ||
      !titleInput ||
      !startAtInput ||
      !endAtInput ||
      !mediaInput ||
      !previewScreen ||
      !emptyState ||
      !summaryText ||
      !requesterLabel ||
      !requestBadge ||
      !periodBadge
    ) {
      return;
    }
    hideLegacyPreviewSummary();

    let previewObjectUrl = "";
    let requestFetchTimer = 0;
    let requestFetchToken = 0;
    const previewApiUrl = String(root.dataset.previewApiUrl || "").trim();
    const requestState = {
      id: String(root.dataset.requestId || "").trim(),
      code: String(root.dataset.requestCode || "").trim(),
      requesterLabel: String(root.dataset.requesterLabel || "").trim(),
      assetUrl: String(root.dataset.existingSrc || "").trim(),
      assetType: String(root.dataset.existingType || "").trim(),
      assetName: String(root.dataset.existingName || "").trim(),
    };

    function cleanText(value) {
      return String(value || "").trim();
    }

    function basename(value) {
      return String(value || "")
        .split(/[\\/]/)
        .filter(Boolean)
        .pop() || "";
    }

    function formatDateTimeLabel(value) {
      const raw = cleanText(value);
      if (!raw) {
        return "";
      }
      const parts = raw.split("T");
      if (parts.length !== 2) {
        return raw;
      }
      return parts[0] + " - " + parts[1];
    }

    function revokePreviewUrl() {
      if (!previewObjectUrl) {
        return;
      }
      try {
        URL.revokeObjectURL(previewObjectUrl);
      } catch (_) {
        // Ignore URL revocation errors.
      }
      previewObjectUrl = "";
    }

    function clearPreviewScreen() {
      while (previewScreen.firstChild) {
        previewScreen.removeChild(previewScreen.firstChild);
      }
    }

    function renderEmptyState(message) {
      clearPreviewScreen();
      emptyState.hidden = false;
      emptyState.textContent = message || "اختر التصميم لعرضه داخل شاشة الجوال.";
      previewScreen.appendChild(emptyState);
    }

    function buildImage(src, altText) {
      const img = document.createElement("img");
      img.src = src;
      img.alt = altText || "معاينة البنر";
      img.loading = "lazy";
      return img;
    }

    function buildVideo(src, label) {
      const video = document.createElement("video");
      video.src = src;
      video.controls = true;
      video.preload = "metadata";
      video.muted = true;
      video.playsInline = true;
      video.setAttribute("playsinline", "");
      video.setAttribute("aria-label", label || "معاينة فيديو البنر");
      return video;
    }

    function updateToolbarState(fromPreviewAction, statusMessage) {
      const requestId = cleanText(requestInput.value);
      const startLabel = formatDateTimeLabel(startAtInput.value);
      const endLabel = formatDateTimeLabel(endAtInput.value);
      const title = cleanText(titleInput.value) || "بنر الصفحة الرئيسية";
      requesterLabel.textContent = requestState.requesterLabel || "-";
      requestBadge.textContent = requestState.code
        ? "الطلب: " + requestState.code
        : (requestId ? "الطلب: " + requestId : "اختر الطلب");
      periodBadge.textContent =
        startLabel && endLabel
          ? ("من " + startLabel + " إلى " + endLabel)
          : "حدد فترة الحملة";
      if (statusMessage) {
        summaryText.textContent = statusMessage;
        return;
      }
      summaryText.textContent = fromPreviewAction
        ? ("تم تحديث معاينة " + title + " مباشرة داخل شاشة الجوال.")
        : ("المعاينة الحية لــ " + title + " تتحدث مباشرة مع تغيير الطلب أو الملف أو فترة الحملة.");
    }

    function updateAttachmentSpecs(file) {
      if (!specsInput) {
        return;
      }
      if (file) {
        const sizeMb = (file.size || 0) / (1024 * 1024);
        specsInput.value = (file.name || "asset") + " - " + sizeMb.toFixed(2) + " MB";
        return;
      }
      specsInput.value = basename(requestState.assetName);
    }

    function renderExistingAsset() {
      const existingSrc = requestState.assetUrl;
      const existingType = String(requestState.assetType || "").toLowerCase();
      if (!existingSrc) {
        updateAttachmentSpecs(null);
        renderEmptyState("لا يوجد تصميم محفوظ لهذا الطلب بعد.");
        if (metaText) {
          metaText.textContent = "يمكنك رفع تصميم جديد أو اختيار طلب مرتبط بمرفق محفوظ.";
        }
        return;
      }

      updateAttachmentSpecs(null);
      clearPreviewScreen();
      const mediaNode =
        existingType === "video"
          ? buildVideo(existingSrc, basename(requestState.assetName) || "معاينة فيديو محفوظ")
          : buildImage(existingSrc, basename(requestState.assetName) || "معاينة تصميم محفوظ");
      previewScreen.appendChild(mediaNode);
      if (metaText) {
        metaText.textContent = "هذا هو آخر تصميم محفوظ للطلب المحدد وسيتم استخدامه ما لم ترفع ملفًا جديدًا.";
      }
    }

    function renderSelectedAsset(file) {
      if (!file) {
        revokePreviewUrl();
        renderExistingAsset();
        return;
      }

      updateAttachmentSpecs(file);
      revokePreviewUrl();

      const mime = String(file.type || "").toLowerCase();
      const isImage = mime.startsWith("image/");
      const isVideo = mime.startsWith("video/");

      if (!isImage && !isVideo) {
        renderEmptyState("نوع الملف غير مدعوم للمعاينة.");
        if (metaText) {
          metaText.textContent = "الأنواع المدعومة: صورة أو فيديو MP4.";
        }
        return;
      }

      previewObjectUrl = URL.createObjectURL(file);
      clearPreviewScreen();

      if (isVideo) {
        const video = buildVideo(previewObjectUrl, file.name || "معاينة فيديو");
        previewScreen.appendChild(video);
        if (metaText) {
          metaText.textContent = "جاري تحميل بيانات الفيديو...";
          video.addEventListener(
            "loadedmetadata",
            () => {
              const duration = Number.isFinite(video.duration)
                ? Math.max(0, Math.round(video.duration))
                : 0;
              metaText.textContent =
                "فيديو معاينة - المدة التقريبية: " + String(duration) + " ثانية.";
            },
            { once: true },
          );
        }
        return;
      }

      const image = buildImage(previewObjectUrl, file.name || "معاينة صورة");
      previewScreen.appendChild(image);
      if (metaText) {
        metaText.textContent = "جاري تحميل أبعاد الصورة...";
        image.addEventListener(
          "load",
          () => {
            metaText.textContent =
              "أبعاد الصورة: " +
              String(image.naturalWidth || 0) +
              "x" +
              String(image.naturalHeight || 0) +
              " بكسل.";
          },
          { once: true },
        );
      }
    }

    function currentDraftHasAsset() {
      const currentFile = mediaInput.files && mediaInput.files[0] ? mediaInput.files[0] : null;
      return Boolean(currentFile || requestState.assetUrl);
    }

    function focusFirstError() {
      if (!cleanText(requestInput.value)) {
        requestInput.focus();
        return;
      }
      if (!cleanText(startAtInput.value)) {
        startAtInput.focus();
        return;
      }
      if (!cleanText(endAtInput.value)) {
        endAtInput.focus();
        return;
      }
      if (!currentDraftHasAsset()) {
        mediaInput.focus();
      }
    }

    function validateWindow() {
      const startValue = cleanText(startAtInput.value);
      const endValue = cleanText(endAtInput.value);
      if (!startValue || !endValue) {
        return "";
      }
      const startMs = Date.parse(startValue);
      const endMs = Date.parse(endValue);
      if (Number.isFinite(startMs) && Number.isFinite(endMs) && endMs <= startMs) {
        return "نهاية الحملة يجب أن تكون بعد البداية.";
      }
      return "";
    }

    function applyRequestPreviewPayload(payload) {
      const requestPayload = payload && payload.request ? payload.request : {};
      const assetPayload = payload && payload.asset ? payload.asset : {};
      requestState.id = cleanText(requestPayload.id);
      requestState.code = cleanText(requestPayload.code);
      requestState.requesterLabel = cleanText(requestPayload.requester_label);
      requestState.assetUrl = cleanText(assetPayload.url);
      requestState.assetType = cleanText(assetPayload.type);
      requestState.assetName = cleanText(assetPayload.name);
      updateToolbarState(
        false,
        requestState.assetUrl
          ? "تم تحميل آخر تصميم محفوظ لهذا الطلب داخل المعاينة."
          : "لا يوجد تصميم محفوظ لهذا الطلب حاليًا. يمكنك رفع ملف جديد للمعاينة."
      );
      if (!(mediaInput.files && mediaInput.files[0])) {
        renderExistingAsset();
      }
    }

    function handleRequestPreviewFailure(message) {
      requestState.id = cleanText(requestInput.value);
      requestState.code = cleanText(requestInput.value);
      requestState.requesterLabel = "";
      requestState.assetUrl = "";
      requestState.assetType = "";
      requestState.assetName = "";
      updateToolbarState(false, message || "تعذر جلب بيانات الطلب الآن.");
      if (!(mediaInput.files && mediaInput.files[0])) {
        renderExistingAsset();
      }
    }

    function loadRequestPreview() {
      const requestId = cleanText(requestInput.value);
      if (!requestId) {
        handleRequestPreviewFailure("اختر رقم طلب الترويج ليتم تحميل معاينته.");
        return;
      }
      if (!previewApiUrl) {
        updateToolbarState(false, "المعاينة الحية تعمل على الملف المحلي فقط في هذه الصفحة.");
        return;
      }

      const token = ++requestFetchToken;
      updateToolbarState(false, "جارٍ تحميل بيانات الطلب المختار...");
      fetch(previewApiUrl + "?request_id=" + encodeURIComponent(requestId), {
        method: "GET",
        headers: { "X-Requested-With": "XMLHttpRequest" },
        credentials: "same-origin",
      })
        .then((response) =>
          response
            .json()
            .catch(() => ({}))
            .then((payload) => ({ response, payload }))
        )
        .then(({ response, payload }) => {
          if (token !== requestFetchToken) {
            return;
          }
          if (!response.ok || !payload || payload.ok !== true) {
            throw new Error((payload && payload.error) || "تعذر جلب بيانات الطلب.");
          }
          applyRequestPreviewPayload(payload);
        })
        .catch((error) => {
          if (token !== requestFetchToken) {
            return;
          }
          handleRequestPreviewFailure(error && error.message ? error.message : "تعذر جلب بيانات الطلب.");
        });
    }

    function scheduleRequestPreviewLoad() {
      if (requestFetchTimer) {
        window.clearTimeout(requestFetchTimer);
      }
      requestFetchTimer = window.setTimeout(loadRequestPreview, 240);
    }

    mediaInput.addEventListener("change", () => {
      const file = mediaInput.files && mediaInput.files[0] ? mediaInput.files[0] : null;
      renderSelectedAsset(file);
      updateToolbarState(false, file ? "يعرض الآن الملف المحلي الذي اخترته قبل الحفظ." : "");
    });
    requestInput.addEventListener("input", scheduleRequestPreviewLoad);
    requestInput.addEventListener("change", scheduleRequestPreviewLoad);
    requestInput.addEventListener("blur", scheduleRequestPreviewLoad);
    titleInput.addEventListener("input", () => updateToolbarState(false));
    startAtInput.addEventListener("input", () => updateToolbarState(false));
    startAtInput.addEventListener("change", () => updateToolbarState(false));
    endAtInput.addEventListener("input", () => updateToolbarState(false));
    endAtInput.addEventListener("change", () => updateToolbarState(false));

    if (previewButton) {
      previewButton.addEventListener("click", () => {
        const errors = [];
        if (!cleanText(requestInput.value)) {
          errors.push("اختر رقم طلب الترويج أولاً.");
        }
        if (!cleanText(startAtInput.value) || !cleanText(endAtInput.value)) {
          errors.push("حدد بداية ونهاية الحملة.");
        }
        const windowError = validateWindow();
        if (windowError) {
          errors.push(windowError);
        }
        if (!currentDraftHasAsset()) {
          errors.push("ارفع تصميم البنر أو اختر طلبًا مرتبطًا بتصميم محفوظ.");
        }
        if (errors.length) {
          focusFirstError();
          window.alert(errors.join("\n"));
          return;
        }
        const file = mediaInput.files && mediaInput.files[0] ? mediaInput.files[0] : null;
        renderSelectedAsset(file);
        updateToolbarState(true);
        const focusTarget = document.getElementById("homeBannerPreviewPanel") || previewScreen;
        focusTarget.scrollIntoView({ behavior: "smooth", block: "center" });
      });
    }

    updateToolbarState(false);
    renderExistingAsset();
    window.addEventListener("beforeunload", revokePreviewUrl);
  }

  function setupPortfolioShowcaseModule() {
    const moduleForm = document.getElementById("promoModuleForm");
    if (!moduleForm) {
      return;
    }
    const moduleKey = String(moduleForm.dataset.moduleKey || "").toLowerCase();
    if (moduleKey !== "portfolio_showcase") {
      return;
    }

    const root = document.getElementById("portfolioShowcaseModule");
    const requestInput = moduleForm.querySelector("input[name='request_id']");
    const providerInput = moduleForm.querySelector("input[name='target_provider_id']");
    const selectedItemInput = moduleForm.querySelector("input[name='target_spotlight_item_id']");
    const gallery = document.getElementById("portfolioShowcaseGallery");
    const galleryStatus = document.getElementById("portfolioShowcaseGalleryStatus");
    const galleryCount = document.getElementById("portfolioShowcaseGalleryCount");
    const providerName = document.getElementById("portfolioShowcaseProviderName");
    const preview = document.getElementById("portfolioShowcasePhonePreview");
    const previewEmpty = document.getElementById("portfolioShowcasePhoneEmpty");
    const previewCaption = document.getElementById("portfolioShowcasePreviewCaption");
    if (
      !requestInput ||
      !providerInput ||
      !selectedItemInput ||
      !gallery ||
      !galleryStatus ||
      !galleryCount ||
      !preview ||
      !previewEmpty
    ) {
      return;
    }

    const apiTemplate = String(gallery.dataset.apiTemplate || "");
    const previewApiUrl = String((root && root.dataset.previewApiUrl) || "").trim();
    const initialSelection = {
      id: Number(gallery.dataset.selectedItemId || 0),
      file_url: gallery.dataset.selectedItemFile || "",
      thumbnail_url: gallery.dataset.selectedItemThumbnail || "",
      file_type: gallery.dataset.selectedItemType || "",
      caption: gallery.dataset.selectedItemCaption || "",
    };
    const selectionState = {
      id: initialSelection.id,
      file_url: initialSelection.file_url,
      thumbnail_url: initialSelection.thumbnail_url,
      file_type: initialSelection.file_type,
      caption: initialSelection.caption,
    };

    let items = [];
    let requestToken = 0;
    let fetchTimer = 0;
    let requestPreviewToken = 0;
    let requestPreviewTimer = 0;

    function cleanText(value) {
      return String(value || "").trim();
    }

    function updateProviderLabel(text) {
      if (!providerName) {
        return;
      }
      providerName.textContent = cleanText(text) || "-";
    }

    function clearNode(node) {
      while (node.firstChild) {
        node.removeChild(node.firstChild);
      }
    }

    function setStatus(text, tone) {
      galleryStatus.textContent = text;
      galleryStatus.dataset.state = tone || "neutral";
    }

    function setCount(count) {
      galleryCount.textContent = String(count || 0) + " صورة";
    }

    function findItemById(itemId) {
      return items.find((item) => Number(item.id) === Number(itemId)) || null;
    }

    function setSelectionState(item) {
      selectionState.id = item && item.id ? Number(item.id) : 0;
      selectionState.file_url = item ? item.file_url || "" : "";
      selectionState.thumbnail_url = item ? item.thumbnail_url || "" : "";
      selectionState.caption = item ? item.caption || "" : "";
    }

    function renderPreview(item) {
      const imageUrl = item ? item.file_url || item.thumbnail_url || "" : "";
      clearNode(preview);
      if (!imageUrl) {
        previewEmpty.hidden = false;
        previewEmpty.textContent = "اختر صورة من معرض الأعمال لعرضها هنا.";
        preview.appendChild(previewEmpty);
        if (previewCaption) {
          previewCaption.textContent = "المعاينة ستظهر بعد اختيار صورة واحدة من المعرض.";
        }
        return;
      }

      const image = document.createElement("img");
      image.src = imageUrl;
      image.alt = item && item.caption ? item.caption : "صورة معرض الأعمال المختارة";
      preview.appendChild(image);
      previewEmpty.hidden = true;
      if (previewCaption) {
        previewCaption.textContent = item && item.caption ? item.caption : "تم اختيار صورة معرض الأعمال لهذا الشريط.";
      }
    }

    function updateSelectionVisuals() {
      const selectedId = Number(selectedItemInput.value || 0);
      gallery.querySelectorAll(".portfolio-showcase-card").forEach((button) => {
        const active = Number(button.dataset.itemId || 0) === selectedId;
        button.classList.toggle("is-selected", active);
        button.setAttribute("aria-pressed", active ? "true" : "false");
      });
    }

    function selectItem(item) {
      if (!item || !item.id) {
        selectedItemInput.value = "";
        setSelectionState(null);
        updateSelectionVisuals();
        renderPreview(null);
        return;
      }
      selectedItemInput.value = String(item.id);
      setSelectionState(item);
      updateSelectionVisuals();
      renderPreview(item);
      setStatus("تم اختيار صورة المعرض لهذا البند الترويجي.", "success");
    }

    function buildCard(item) {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "portfolio-showcase-card";
      button.dataset.itemId = String(item.id || "");
      button.setAttribute("aria-pressed", "false");

      const thumbWrap = document.createElement("div");
      thumbWrap.className = "portfolio-showcase-card-thumb";
      const image = document.createElement("img");
      image.src = item.thumbnail_url || item.file_url || "";
      image.alt = item.caption || "صورة معرض أعمال";
      image.loading = "lazy";
      thumbWrap.appendChild(image);

      const body = document.createElement("div");
      body.className = "portfolio-showcase-card-body";

      const title = document.createElement("strong");
      title.className = "portfolio-showcase-card-title";
      title.textContent = item.caption || "صورة بدون وصف";

      const meta = document.createElement("span");
      meta.className = "portfolio-showcase-card-meta";
      meta.textContent = "رقم الصورة #" + String(item.id || "");

      body.appendChild(title);
      body.appendChild(meta);
      button.appendChild(thumbWrap);
      button.appendChild(body);
      button.addEventListener("click", () => {
        selectItem(item);
      });
      return button;
    }

    function renderGallery(nextItems) {
      items = Array.isArray(nextItems) ? nextItems : [];
      clearNode(gallery);
      setCount(items.length);

      if (!items.length) {
        selectedItemInput.value = "";
        if (selectionState.id && (selectionState.file_url || selectionState.thumbnail_url)) {
          renderPreview(selectionState);
          setStatus("لا توجد صور أخرى متاحة لهذا المزود حاليًا، وتم الاحتفاظ بالصورة المرتبطة بالطلب.", "warning");
          return;
        }
        renderPreview(null);
        setStatus("لا توجد صور متاحة في معرض أعمال هذا المزود حاليًا.", "warning");
        return;
      }

      items.forEach((item) => {
        gallery.appendChild(buildCard(item));
      });

      const selectedId = Number(selectedItemInput.value || selectionState.id || initialSelection.id || 0);
      const matchedItem = selectedId ? findItemById(selectedId) : null;
      if (matchedItem) {
        selectItem(matchedItem);
      } else {
        selectedItemInput.value = "";
        updateSelectionVisuals();
        renderPreview(null);
        setStatus("تم جلب الصور بنجاح. اختر صورة واحدة لاعتمادها.", "neutral");
      }

      const providerLabel = items[0] && (items[0].provider_display_name || items[0].provider_username);
      if (providerLabel && providerName) {
        providerName.textContent = providerLabel;
      }
    }

    function normalizeItems(payload) {
      const rows = Array.isArray(payload) ? payload : Array.isArray(payload && payload.results) ? payload.results : [];
      return rows.filter((item) => String(item.file_type || "").toLowerCase() === "image");
    }

    function clearRequestContext(message, tone) {
      providerInput.value = "";
      selectedItemInput.value = "";
      setSelectionState(null);
      clearNode(gallery);
      setCount(0);
      updateProviderLabel("");
      renderPreview(null);
      setStatus(message, tone || "neutral");
    }

    function applyRequestPreviewPayload(payload) {
      const requestPayload = payload && payload.request ? payload.request : {};
      const portfolioItem = payload && payload.portfolio_item ? payload.portfolio_item : {};
      const nextProviderId = cleanText(requestPayload.target_provider_id);
      const nextProviderLabel = cleanText(requestPayload.target_provider_label || requestPayload.requester_label);

      providerInput.value = nextProviderId;
      updateProviderLabel(nextProviderLabel);

      if (portfolioItem && portfolioItem.id) {
        selectedItemInput.value = String(portfolioItem.id);
        setSelectionState(portfolioItem);
        renderPreview(selectionState);
      } else {
        selectedItemInput.value = "";
        setSelectionState(null);
        renderPreview(null);
      }

      if (!nextProviderId) {
        clearNode(gallery);
        setCount(0);
        setStatus("الطلب المحدد غير مرتبط بمزود خدمة يمكن عرض معرض أعماله.", "warning");
        return;
      }

      scheduleLoad();
    }

    function loadRequestPreview() {
      const requestId = cleanText(requestInput.value);
      if (!requestId) {
        clearRequestContext("اختر رقم طلب الترويج ليتم جلب مزود الخدمة وصور معرض أعماله.", "neutral");
        return;
      }
      if (!previewApiUrl) {
        scheduleLoad();
        return;
      }

      const currentToken = requestPreviewToken + 1;
      requestPreviewToken = currentToken;
      setStatus("جارٍ تحميل بيانات الطلب والمزود من الباكند...", "loading");

      window
        .fetch(previewApiUrl + "?request_id=" + encodeURIComponent(requestId), {
          method: "GET",
          credentials: "same-origin",
          headers: {
            Accept: "application/json",
            "X-Requested-With": "XMLHttpRequest",
          },
        })
        .then((response) =>
          response
            .json()
            .catch(() => ({}))
            .then((payload) => ({ response, payload }))
        )
        .then(({ response, payload }) => {
          if (currentToken !== requestPreviewToken) {
            return;
          }
          if (!response.ok || !payload || payload.ok !== true) {
            throw new Error((payload && payload.error) || "تعذر جلب بيانات الطلب.");
          }
          applyRequestPreviewPayload(payload);
        })
        .catch((error) => {
          if (currentToken !== requestPreviewToken) {
            return;
          }
          clearRequestContext(
            error && error.message ? error.message : "تعذر جلب بيانات الطلب الآن.",
            "error",
          );
        });
    }

    function scheduleRequestPreviewLoad() {
      if (requestPreviewTimer) {
        window.clearTimeout(requestPreviewTimer);
      }
      requestPreviewTimer = window.setTimeout(loadRequestPreview, 240);
    }

    function loadPortfolioItems() {
      const providerId = cleanText(providerInput.value);
      if (!providerId || !/^[0-9]+$/.test(providerId) || !apiTemplate) {
        clearNode(gallery);
        setCount(0);
        selectedItemInput.value = "";
        renderPreview(selectionState.id ? selectionState : null);
        setStatus("أدخل معرف مزود خدمة صحيح ليتم جلب صور معرض الأعمال.", "neutral");
        return;
      }

      const currentToken = requestToken + 1;
      requestToken = currentToken;
      setStatus("جار جلب صور معرض الأعمال من الباكند...", "loading");

      const url = apiTemplate.replace("__provider_id__", providerId);
      window
        .fetch(url, {
          method: "GET",
          credentials: "same-origin",
          headers: {
            Accept: "application/json",
            "X-Requested-With": "XMLHttpRequest",
          },
        })
        .then((response) => {
          if (!response.ok) {
            throw new Error("fetch_failed");
          }
          return response.json();
        })
        .then((payload) => {
          if (currentToken !== requestToken) {
            return;
          }
          renderGallery(normalizeItems(payload));
        })
        .catch(() => {
          if (currentToken !== requestToken) {
            return;
          }
          clearNode(gallery);
          setCount(0);
          selectedItemInput.value = "";
          renderPreview(null);
          setStatus("تعذر تحميل صور معرض الأعمال الآن. حاول مرة أخرى.", "error");
        });
    }

    function scheduleLoad() {
      if (fetchTimer) {
        window.clearTimeout(fetchTimer);
      }
      fetchTimer = window.setTimeout(loadPortfolioItems, 260);
    }

    providerInput.addEventListener("input", scheduleLoad);
    providerInput.addEventListener("change", scheduleLoad);
    providerInput.addEventListener("blur", scheduleLoad);
    requestInput.addEventListener("input", scheduleRequestPreviewLoad);
    requestInput.addEventListener("change", scheduleRequestPreviewLoad);
    requestInput.addEventListener("blur", scheduleRequestPreviewLoad);

    if (selectionState.id && (selectionState.file_url || selectionState.thumbnail_url)) {
      renderPreview(selectionState);
    } else {
      renderPreview(null);
    }
    updateProviderLabel(providerName && providerName.textContent ? providerName.textContent : "");
    if (cleanText(requestInput.value)) {
      loadRequestPreview();
    } else if (cleanText(providerInput.value)) {
      loadPortfolioItems();
    }
  }

  function setupSnapshotsModule() {
    const moduleForm = document.getElementById("promoModuleForm");
    if (!moduleForm) {
      return;
    }
    const moduleKey = String(moduleForm.dataset.moduleKey || "").toLowerCase();
    if (moduleKey !== "snapshots") {
      return;
    }

    const root = document.getElementById("snapshotsModule");
    const requestInput = moduleForm.querySelector("input[name='request_id']");
    const providerInput = moduleForm.querySelector("input[name='target_provider_id']");
    const selectedItemInput = moduleForm.querySelector("input[name='target_portfolio_item_id']");
    const gallery = document.getElementById("snapshotsGallery");
    const galleryStatus = document.getElementById("snapshotsGalleryStatus");
    const galleryCount = document.getElementById("snapshotsGalleryCount");
    const providerName = document.getElementById("snapshotsProviderName");
    const phoneStrip = document.getElementById("snapshotsPhoneStrip");
    const phoneViewer = document.getElementById("snapshotsPhoneViewer");
    const phoneEmpty = document.getElementById("snapshotsPhoneEmpty");
    const previewCaption = document.getElementById("snapshotsPreviewCaption");
    if (
      !requestInput ||
      !providerInput ||
      !selectedItemInput ||
      !gallery ||
      !galleryStatus ||
      !galleryCount ||
      !phoneStrip ||
      !phoneViewer ||
      !phoneEmpty
    ) {
      return;
    }

    const apiTemplate = String(gallery.dataset.apiTemplate || "");
    const previewApiUrl = String((root && root.dataset.previewApiUrl) || "").trim();
    const initialSelection = {
      id: Number(gallery.dataset.selectedItemId || 0),
      file_url: gallery.dataset.selectedItemFile || "",
      thumbnail_url: gallery.dataset.selectedItemThumbnail || "",
      file_type: gallery.dataset.selectedItemType || "",
      caption: gallery.dataset.selectedItemCaption || "",
    };
    const selectionState = {
      id: initialSelection.id,
      file_url: initialSelection.file_url,
      thumbnail_url: initialSelection.thumbnail_url,
      file_type: initialSelection.file_type,
      caption: initialSelection.caption,
    };
    let items = [];
    let requestToken = 0;
    let fetchTimer = 0;
    let requestPreviewToken = 0;
    let requestPreviewTimer = 0;

    function cleanText(value) {
      return String(value || "").trim();
    }

    function updateProviderLabel(text) {
      if (!providerName) {
        return;
      }
      providerName.textContent = cleanText(text) || "-";
    }

    function clearNode(node) {
      while (node.firstChild) {
        node.removeChild(node.firstChild);
      }
    }

    function setStatus(text, tone) {
      galleryStatus.textContent = text;
      galleryStatus.dataset.state = tone || "neutral";
    }

    function setCount(count) {
      galleryCount.textContent = String(count || 0) + " ريل";
    }

    function setSelectionState(item) {
      selectionState.id = item && item.id ? Number(item.id) : 0;
      selectionState.file_url = item ? item.file_url || "" : "";
      selectionState.thumbnail_url = item ? item.thumbnail_url || "" : "";
      selectionState.file_type = item ? item.file_type || "" : "";
      selectionState.caption = item ? item.caption || "" : "";
    }

    function buildMediaNode(item, muted) {
      const type = String(item.file_type || "").toLowerCase();
      const src = item.file_url || item.thumbnail_url || "";
      if (!src) {
        return null;
      }
      if (type === "video") {
        const video = document.createElement("video");
        video.src = src;
        video.preload = "metadata";
        video.playsInline = true;
        video.setAttribute("playsinline", "");
        if (muted) {
          video.muted = true;
          video.loop = true;
          video.autoplay = true;
        } else {
          video.controls = true;
        }
        return video;
      }

      const image = document.createElement("img");
      image.src = src;
      image.alt = item.caption || "لمحة";
      image.loading = "lazy";
      return image;
    }

    function renderPhonePreview(item) {
      clearNode(phoneViewer);
      if (!item) {
        phoneEmpty.hidden = false;
        phoneViewer.appendChild(phoneEmpty);
        if (previewCaption) {
          previewCaption.textContent = "اختر ريلًا من اللمحات ليظهر هنا داخل معاينة شريط اللمحات.";
        }
        return;
      }

      phoneEmpty.hidden = true;
      const mediaNode = buildMediaNode(item, false);
      if (mediaNode) {
        phoneViewer.appendChild(mediaNode);
      } else {
        phoneViewer.appendChild(phoneEmpty);
        phoneEmpty.hidden = false;
      }
      if (previewCaption) {
        previewCaption.textContent = item.caption || "تم تجهيز معاينة الريل المختار لشريط اللمحات.";
      }
    }

    function updateActiveStates(activeId) {
      gallery.querySelectorAll(".snapshots-card").forEach((card) => {
        const isActive = Number(card.dataset.itemId || 0) === Number(activeId || 0);
        card.classList.toggle("is-active", isActive);
      });
      phoneStrip.querySelectorAll(".snapshots-phone-avatar").forEach((avatar) => {
        const isActive = Number(avatar.dataset.itemId || 0) === Number(activeId || 0);
        avatar.classList.toggle("is-active", isActive);
      });
    }

    function activateItem(item) {
      if (!item || !item.id) {
        selectedItemInput.value = "";
        setSelectionState(null);
        updateActiveStates(0);
        renderPhonePreview(null);
        return;
      }
      selectedItemInput.value = String(item.id);
      setSelectionState(item);
      updateActiveStates(item.id);
      renderPhonePreview(item);
      setStatus("تم اختيار ريل اللمحات لهذا الشريط.", "success");
    }

    function buildGalleryCard(item) {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "snapshots-card";
      button.dataset.itemId = String(item.id || "");

      const thumbWrap = document.createElement("div");
      thumbWrap.className = "snapshots-card-thumb";
      const mediaNode = buildMediaNode(item, true);
      if (mediaNode) {
        thumbWrap.appendChild(mediaNode);
      }
      const badge = document.createElement("span");
      badge.className = "snapshots-card-badge";
      badge.textContent = String(item.file_type || "").toLowerCase() === "video" ? "فيديو" : "صورة";
      thumbWrap.appendChild(badge);

      const body = document.createElement("div");
      body.className = "snapshots-card-body";
      const title = document.createElement("strong");
      title.className = "snapshots-card-title";
      title.textContent = item.caption || "عنصر بدون وصف";
      const meta = document.createElement("span");
      meta.className = "snapshots-card-meta";
      meta.textContent = "رقم العنصر #" + String(item.id || "");
      body.appendChild(title);
      body.appendChild(meta);

      button.appendChild(thumbWrap);
      button.appendChild(body);
      button.addEventListener("click", () => activateItem(item));
      return button;
    }

    function buildPhoneAvatar(item) {
      const avatar = document.createElement("button");
      avatar.type = "button";
      avatar.className = "snapshots-phone-avatar";
      avatar.dataset.itemId = String(item.id || "");
      const mediaNode = buildMediaNode(item, true);
      if (mediaNode) {
        avatar.appendChild(mediaNode);
      }
      avatar.addEventListener("click", () => activateItem(item));
      return avatar;
    }

    function normalizeItems(payload) {
      const rows = Array.isArray(payload) ? payload : Array.isArray(payload && payload.results) ? payload.results : [];
      return rows.filter((item) => {
        const type = String(item.file_type || "").toLowerCase();
        return type === "image" || type === "video";
      });
    }

    function findItemById(itemId) {
      return items.find((item) => Number(item.id) === Number(itemId)) || null;
    }

    function renderItems(nextItems) {
      items = Array.isArray(nextItems) ? nextItems : [];
      clearNode(gallery);
      clearNode(phoneStrip);
      setCount(items.length);

      if (!items.length) {
        if (selectionState.id && (selectionState.file_url || selectionState.thumbnail_url)) {
          renderPhonePreview(selectionState);
          setStatus("لا توجد ريلز أخرى متاحة لهذا المزود حاليًا، وتم الاحتفاظ بالريل المرتبط بالطلب.", "warning");
          return;
        }
        activateItem(null);
        setStatus("لا توجد ريلز منشورة لهذا المزود حاليًا.", "warning");
        return;
      }

      items.forEach((item) => {
        gallery.appendChild(buildGalleryCard(item));
        phoneStrip.appendChild(buildPhoneAvatar(item));
      });

      const providerLabel = items[0] && (items[0].provider_display_name || items[0].provider_username);
      if (providerLabel && providerName) {
        providerName.textContent = providerLabel;
      }

      const selectedId = Number(selectedItemInput.value || selectionState.id || initialSelection.id || 0);
      const matchedItem = selectedId ? findItemById(selectedId) : null;
      if (matchedItem) {
        activateItem(matchedItem);
      } else {
        selectedItemInput.value = "";
        setSelectionState(null);
        updateActiveStates(0);
        renderPhonePreview(null);
        setStatus("تم جلب الريلز بنجاح. اختر ريلًا واحدًا لاعتماده داخل شريط اللمحات.", "neutral");
      }
    }

    function clearRequestContext(message, tone) {
      providerInput.value = "";
      selectedItemInput.value = "";
      setSelectionState(null);
      clearNode(gallery);
      clearNode(phoneStrip);
      setCount(0);
      updateProviderLabel("");
      renderPhonePreview(null);
      setStatus(message, tone || "neutral");
    }

    function applyRequestPreviewPayload(payload) {
      const requestPayload = payload && payload.request ? payload.request : {};
      const spotlightItem = payload && payload.spotlight_item ? payload.spotlight_item : {};
      const nextProviderId = cleanText(requestPayload.target_provider_id);
      const nextProviderLabel = cleanText(requestPayload.target_provider_label || requestPayload.requester_label);

      providerInput.value = nextProviderId;
      updateProviderLabel(nextProviderLabel);

      if (spotlightItem && spotlightItem.id) {
        selectedItemInput.value = String(spotlightItem.id);
        setSelectionState(spotlightItem);
        renderPhonePreview(selectionState);
      } else {
        selectedItemInput.value = "";
        setSelectionState(null);
        renderPhonePreview(null);
      }

      if (!nextProviderId) {
        clearNode(gallery);
        clearNode(phoneStrip);
        setCount(0);
        setStatus("الطلب المحدد غير مرتبط بمزود خدمة يمكن عرض ريلاته.", "warning");
        return;
      }

      scheduleLoad();
    }

    function loadRequestPreview() {
      const requestId = cleanText(requestInput.value);
      if (!requestId) {
        clearRequestContext("اختر رقم طلب الترويج ليتم جلب مزود الخدمة والريلز المنشورة له.", "neutral");
        return;
      }
      if (!previewApiUrl) {
        scheduleLoad();
        return;
      }

      const currentToken = requestPreviewToken + 1;
      requestPreviewToken = currentToken;
      setStatus("جارٍ تحميل بيانات الطلب والمزود من الباكند...", "loading");

      window
        .fetch(previewApiUrl + "?request_id=" + encodeURIComponent(requestId), {
          method: "GET",
          credentials: "same-origin",
          headers: {
            Accept: "application/json",
            "X-Requested-With": "XMLHttpRequest",
          },
        })
        .then((response) =>
          response
            .json()
            .catch(() => ({}))
            .then((payload) => ({ response, payload }))
        )
        .then(({ response, payload }) => {
          if (currentToken !== requestPreviewToken) {
            return;
          }
          if (!response.ok || !payload || payload.ok !== true) {
            throw new Error((payload && payload.error) || "تعذر جلب بيانات الطلب.");
          }
          applyRequestPreviewPayload(payload);
        })
        .catch((error) => {
          if (currentToken !== requestPreviewToken) {
            return;
          }
          clearRequestContext(
            error && error.message ? error.message : "تعذر جلب بيانات الطلب الآن.",
            "error",
          );
        });
    }

    function scheduleRequestPreviewLoad() {
      if (requestPreviewTimer) {
        window.clearTimeout(requestPreviewTimer);
      }
      requestPreviewTimer = window.setTimeout(loadRequestPreview, 240);
    }

    function loadSpotlights() {
      const providerId = cleanText(providerInput.value);
      if (!providerId || !/^[0-9]+$/.test(providerId) || !apiTemplate) {
        clearNode(gallery);
        clearNode(phoneStrip);
        setCount(0);
        renderPhonePreview(selectionState.id ? selectionState : null);
        setStatus("أدخل معرف مزود خدمة صحيح ليتم جلب الريلز المنشورة.", "neutral");
        return;
      }

      const currentToken = requestToken + 1;
      requestToken = currentToken;
      setStatus("جار جلب ريلز المزود من الباكند...", "loading");

      window
        .fetch(apiTemplate.replace("__provider_id__", providerId), {
          method: "GET",
          credentials: "same-origin",
          headers: {
            Accept: "application/json",
            "X-Requested-With": "XMLHttpRequest",
          },
        })
        .then((response) => {
          if (!response.ok) {
            throw new Error("fetch_failed");
          }
          return response.json();
        })
        .then((payload) => {
          if (currentToken !== requestToken) {
            return;
          }
          renderItems(normalizeItems(payload));
        })
        .catch(() => {
          if (currentToken !== requestToken) {
            return;
          }
          clearNode(gallery);
          clearNode(phoneStrip);
          setCount(0);
          renderPhonePreview(null);
          setStatus("تعذر تحميل ريلز المزود الآن. حاول مرة أخرى.", "error");
        });
    }

    function scheduleLoad() {
      if (fetchTimer) {
        window.clearTimeout(fetchTimer);
      }
      fetchTimer = window.setTimeout(loadSpotlights, 260);
    }

    providerInput.addEventListener("input", scheduleLoad);
    providerInput.addEventListener("change", scheduleLoad);
    providerInput.addEventListener("blur", scheduleLoad);
    requestInput.addEventListener("input", scheduleRequestPreviewLoad);
    requestInput.addEventListener("change", scheduleRequestPreviewLoad);
    requestInput.addEventListener("blur", scheduleRequestPreviewLoad);

    if (selectionState.id && (selectionState.file_url || selectionState.thumbnail_url)) {
      renderPhonePreview(selectionState);
    } else {
      renderPhonePreview(null);
    }
    updateProviderLabel(providerName && providerName.textContent ? providerName.textContent : "");
    if (cleanText(requestInput.value)) {
      loadRequestPreview();
    } else if (cleanText(providerInput.value)) {
      loadSpotlights();
    }
  }

  function setupSearchResultsModule() {
    const moduleForm = document.getElementById("promoModuleForm");
    if (!moduleForm) {
      return;
    }
    const moduleKey = String(moduleForm.dataset.moduleKey || "").toLowerCase();
    if (moduleKey !== "search_results") {
      return;
    }

    const providerInput = moduleForm.querySelector("input[name='target_provider_id']");
    const categoryInput = moduleForm.querySelector("input[name='target_category']");
    const positionSelect = moduleForm.querySelector("select[name='search_position']");
    const scopeInputs = Array.from(moduleForm.querySelectorAll("input[name='search_scopes']"));
    const providerName = document.getElementById("searchModuleProviderName");
    const providerMeta = document.getElementById("searchModuleProviderMeta");
    const providerStatus = document.getElementById("searchModuleProviderStatus");
    const categoryList = document.getElementById("searchModuleCategories");
    const scopeChips = document.getElementById("searchModuleScopeChips");
    const phoneCategory = document.getElementById("searchModulePhoneCategory");
    const phoneResults = document.getElementById("searchModulePhoneResults");
    const phonePositionBadge = document.getElementById("searchModulePhonePositionBadge");
    const previewSummary = document.getElementById("searchModulePreviewSummary");
    if (
      !providerInput ||
      !categoryInput ||
      !positionSelect ||
      !scopeInputs.length ||
      !providerName ||
      !providerMeta ||
      !providerStatus ||
      !categoryList ||
      !scopeChips ||
      !phoneCategory ||
      !phoneResults ||
      !phonePositionBadge ||
      !previewSummary
    ) {
      return;
    }

    const apiTemplate = String(phoneResults.dataset.providerApiTemplate || "");
    const initialProviderName =
      String(providerName.dataset.initialName || providerName.textContent || "").trim() || "المختص المستهدف";
    const demoResults = [
      { name: "محتوى بلس", category: "التسويق", city: "الرياض", rating: "4.8" },
      { name: "رؤية إبداع", category: "التصميم", city: "جدة", rating: "4.7" },
      { name: "حلول مرئية", category: "الهوية البصرية", city: "الدمام", rating: "4.9" },
      { name: "واجهة رقمية", category: "التقنية", city: "الخبر", rating: "4.6" },
      { name: "إدارة حملات", category: "الإعلانات", city: "مكة", rating: "4.5" },
    ];

    let providerData = null;
    let requestToken = 0;
    let fetchTimer = 0;

    function clearNode(node) {
      while (node.firstChild) {
        node.removeChild(node.firstChild);
      }
    }

    function readProviderId() {
      return String(providerInput.value || "").trim();
    }

    function selectedPositionValue() {
      return String(positionSelect.value || "").trim().toLowerCase() || "first";
    }

    function selectedPositionLabel() {
      const option = positionSelect.options[positionSelect.selectedIndex];
      return String((option && option.textContent) || "الأول في القائمة").trim();
    }

    function selectedPositionShortLabel() {
      const value = selectedPositionValue();
      if (value === "second") {
        return "الثاني";
      }
      if (value === "top5") {
        return "ضمن 5";
      }
      if (value === "top10") {
        return "ضمن 10";
      }
      return "الأول";
    }

    function selectedScopeEntries() {
      return scopeInputs
        .filter((input) => input.checked)
        .map((input) => {
          const label = input.closest("label");
          const text = label ? String(label.textContent || "").replace(/\s+/g, " ").trim() : String(input.value || "").trim();
          return {
            value: String(input.value || "").trim(),
            label: text || String(input.value || "").trim(),
          };
        });
    }

    function resolvePromotedIndex() {
      const value = selectedPositionValue();
      if (value === "second") {
        return 1;
      }
      if (value === "top5") {
        return 2;
      }
      if (value === "top10") {
        return 4;
      }
      return 0;
    }

    function providerDisplayName() {
      if (providerData && providerData.displayName) {
        return providerData.displayName;
      }
      const typedId = readProviderId();
      if (typedId) {
        return "المختص #" + typedId;
      }
      return initialProviderName;
    }

    function providerCategoryText() {
      const manual = String(categoryInput.value || "").trim();
      if (manual) {
        return manual;
      }
      if (providerData && providerData.primaryCategoryName) {
        return providerData.primaryCategoryName;
      }
      if (providerData && providerData.primarySubcategoryName) {
        return providerData.primarySubcategoryName;
      }
      return "غير محدد";
    }

    function providerMetaParts() {
      const parts = [];
      if (providerData && providerData.primaryCategoryName) {
        parts.push(providerData.primaryCategoryName);
      } else if (providerCategoryText() !== "غير محدد") {
        parts.push(providerCategoryText());
      }
      if (providerData && providerData.city) {
        parts.push(providerData.city);
      }
      if (providerData && providerData.ratingValue > 0) {
        parts.push("تقييم " + providerData.ratingValue.toFixed(1));
      }
      return parts;
    }

    function setStatus(text, tone) {
      providerStatus.textContent = text;
      providerStatus.dataset.state = tone || "neutral";
    }

    function createScopeChip(text, muted) {
      const chip = document.createElement("span");
      chip.className = "search-module-phone-chip";
      chip.textContent = text;
      if (muted) {
        chip.style.opacity = "0.72";
      }
      return chip;
    }

    function createAvatar(url, fallbackText) {
      const wrap = document.createElement("div");
      wrap.className = "search-module-phone-avatar";
      if (url) {
        const image = document.createElement("img");
        image.src = url;
        image.alt = fallbackText;
        image.loading = "lazy";
        wrap.appendChild(image);
      } else {
        wrap.textContent = fallbackText;
      }
      return wrap;
    }

    function renderProviderHeader() {
      providerName.textContent = providerDisplayName();
      const parts = providerMetaParts();
      providerMeta.textContent = parts.length
        ? parts.join(" • ")
        : "يمكن تعديل التصنيف المستهدف يدويًا عند الحاجة قبل الحفظ.";
    }

    function renderScopeChips() {
      const scopes = selectedScopeEntries();
      clearNode(scopeChips);
      if (!scopes.length) {
        scopeChips.appendChild(createScopeChip("اختر قائمة ظهور واحدة على الأقل", true));
        return scopes;
      }
      scopes.forEach((scope) => {
        scopeChips.appendChild(createScopeChip(scope.label, false));
      });
      return scopes;
    }

    function renderCategoryList() {
      clearNode(categoryList);
      const currentTarget = providerCategoryText();
      const labels = [];

      if (currentTarget && currentTarget !== "غير محدد") {
        labels.push("الاستهداف الحالي: " + currentTarget);
      }

      if (providerData && Array.isArray(providerData.selectedSubcategories)) {
        providerData.selectedSubcategories.forEach((row) => {
          const categoryName = String(row.category_name || "").trim();
          const subcategoryName = String(row.name || "").trim();
          const label = subcategoryName && categoryName && subcategoryName !== categoryName
            ? categoryName + " - " + subcategoryName
            : subcategoryName || categoryName;
          if (label && labels.indexOf(label) === -1) {
            labels.push(label);
          }
        });
      }

      if (!labels.length) {
        const item = document.createElement("li");
        item.className = "is-empty";
        item.textContent = "لا توجد تصنيفات مرتبطة ظاهرة حاليًا. يمكنك كتابة التصنيف المستهدف يدويًا.";
        categoryList.appendChild(item);
        return;
      }

      labels.slice(0, 8).forEach((label) => {
        const item = document.createElement("li");
        item.textContent = label;
        categoryList.appendChild(item);
      });
    }

    function buildPhoneResult(item, index, isPromoted) {
      const card = document.createElement("div");
      card.className = "search-module-phone-result" + (isPromoted ? " is-promoted" : "");

      const displayName = isPromoted ? providerDisplayName() : item.name;
      const categoryText = isPromoted ? providerCategoryText() : item.category;
      const cityText = isPromoted ? String((providerData && providerData.city) || "").trim() : item.city;
      const ratingText = isPromoted && providerData && providerData.ratingValue > 0
        ? providerData.ratingValue.toFixed(1)
        : item.rating;
      const avatar = createAvatar(
        isPromoted && providerData ? providerData.profileImage : "",
        String(displayName || "؟").trim().charAt(0) || "؟"
      );

      const copy = document.createElement("div");
      copy.className = "search-module-phone-result-copy";
      const name = document.createElement("strong");
      name.className = "search-module-phone-result-name";
      name.textContent = displayName || "مختص مستهدف";
      const meta = document.createElement("span");
      meta.className = "search-module-phone-result-meta";
      const metaParts = [];
      if (categoryText && categoryText !== "غير محدد") {
        metaParts.push(categoryText);
      }
      if (cityText) {
        metaParts.push(cityText);
      }
      if (ratingText) {
        metaParts.push("★ " + ratingText);
      }
      meta.textContent = metaParts.join(" • ") || "نتيجة بحث مرتبطة بالخدمة";
      copy.appendChild(name);
      copy.appendChild(meta);

      const side = document.createElement("div");
      side.className = "search-module-phone-result-side";
      const order = document.createElement("span");
      order.className = "search-module-phone-result-order";
      order.textContent = isPromoted ? selectedPositionShortLabel() : "#" + String(index + 1);
      side.appendChild(order);
      if (isPromoted) {
        const tag = document.createElement("span");
        tag.className = "search-module-phone-result-tag";
        tag.textContent = "ظهور مدفوع";
        side.appendChild(tag);
      }

      card.appendChild(avatar);
      card.appendChild(copy);
      card.appendChild(side);
      return card;
    }

    function renderPhoneResults() {
      const scopes = renderScopeChips();
      const categoryText = providerCategoryText();
      const positionLabel = selectedPositionLabel();
      const promotedIndex = resolvePromotedIndex();
      clearNode(phoneResults);

      phonePositionBadge.textContent = positionLabel;
      phoneCategory.textContent = "التصنيف المرتبط: " + categoryText;

      for (let index = 0; index < 5; index += 1) {
        phoneResults.appendChild(
          buildPhoneResult(demoResults[index % demoResults.length], index, index === promotedIndex)
        );
      }

      const scopeText = scopes.length
        ? scopes.map((scope) => scope.label).join(" + ")
        : "القوائم التي ستحددها";
      previewSummary.textContent =
        providerDisplayName() +
        " سيظهر ضمن " +
        scopeText +
        " بترتيب " +
        positionLabel +
        " خلال فترة الحملة المحددة.";
    }

    function syncCategoryFromProvider() {
      const nextValue =
        providerData && (providerData.primaryCategoryName || providerData.primarySubcategoryName || "");
      const currentValue = String(categoryInput.value || "").trim();
      const previousAutoValue = String(categoryInput.dataset.autofillValue || "").trim();
      if (nextValue && (!currentValue || currentValue === previousAutoValue)) {
        categoryInput.value = nextValue;
      }
      categoryInput.dataset.autofillValue = nextValue || "";
    }

    function normalizeProvider(payload) {
      const ratingValue = Number.parseFloat(String(payload && payload.rating_avg != null ? payload.rating_avg : ""));
      return {
        displayName: String((payload && payload.display_name) || "").trim(),
        city: String((payload && payload.city) || "").trim(),
        profileImage: String((payload && payload.profile_image) || "").trim(),
        primaryCategoryName: String((payload && payload.primary_category_name) || "").trim(),
        primarySubcategoryName: String((payload && payload.primary_subcategory_name) || "").trim(),
        ratingValue: Number.isFinite(ratingValue) ? ratingValue : 0,
        selectedSubcategories: Array.isArray(payload && payload.selected_subcategories)
          ? payload.selected_subcategories
          : [],
      };
    }

    function loadProvider() {
      const providerId = readProviderId();
      requestToken += 1;
      const currentToken = requestToken;

      if (!providerId || !/^[0-9]+$/.test(providerId) || !apiTemplate) {
        providerData = null;
        renderProviderHeader();
        renderCategoryList();
        renderPhoneResults();
        setStatus("أدخل معرف مختص صحيح ليتم جلب بياناته وتحديث المعاينة.", "neutral");
        return;
      }

      setStatus("جار جلب بيانات المختص من الباكند...", "loading");
      window
        .fetch(apiTemplate.replace("__provider_id__", providerId), {
          method: "GET",
          credentials: "same-origin",
          headers: {
            Accept: "application/json",
            "X-Requested-With": "XMLHttpRequest",
          },
        })
        .then((response) => {
          if (!response.ok) {
            throw new Error("fetch_failed");
          }
          return response.json();
        })
        .then((payload) => {
          if (currentToken !== requestToken) {
            return;
          }
          providerData = normalizeProvider(payload);
          syncCategoryFromProvider();
          renderProviderHeader();
          renderCategoryList();
          renderPhoneResults();
          setStatus("تم جلب بيانات المختص وتحديث معاينة نتائج البحث بنجاح.", "success");
        })
        .catch(() => {
          if (currentToken !== requestToken) {
            return;
          }
          providerData = null;
          renderProviderHeader();
          renderCategoryList();
          renderPhoneResults();
          setStatus("تعذر جلب بيانات المختص الآن. يمكنك متابعة الإدخال يدويًا ثم الحفظ.", "error");
        });
    }

    function scheduleLoad() {
      if (fetchTimer) {
        window.clearTimeout(fetchTimer);
      }
      fetchTimer = window.setTimeout(loadProvider, 260);
    }

    providerInput.addEventListener("input", scheduleLoad);
    providerInput.addEventListener("change", scheduleLoad);
    providerInput.addEventListener("blur", scheduleLoad);

    categoryInput.addEventListener("input", () => {
      renderProviderHeader();
      renderCategoryList();
      renderPhoneResults();
      if (providerStatus.dataset.state !== "error") {
        setStatus("تم تحديث التصنيف المستهدف داخل المعاينة.", "neutral");
      }
    });

    positionSelect.addEventListener("change", renderPhoneResults);
    scopeInputs.forEach((input) => {
      input.addEventListener("change", renderPhoneResults);
    });

    renderProviderHeader();
    renderCategoryList();
    renderPhoneResults();
    if (readProviderId()) {
      loadProvider();
    } else {
      setStatus("أدخل معرف المختص ليتم جلب بياناته من الباكند وتحديث المعاينة.", "neutral");
    }
  }

  function setupSponsorshipModule() {
    const moduleForm = document.getElementById("promoModuleForm");
    if (!moduleForm) {
      return;
    }
    const moduleKey = String(moduleForm.dataset.moduleKey || "").toLowerCase();
    if (moduleKey !== "sponsorship") {
      return;
    }

    const root = document.getElementById("sponsorshipModule");
    const requestIdInput = moduleForm.querySelector("input[name='request_id']");
    const sponsorNameInput = moduleForm.querySelector("input[name='sponsor_name']");
    const sponsorUrlInput = moduleForm.querySelector("input[name='sponsor_url']");
    const monthsInput = moduleForm.querySelector("input[name='sponsorship_months']");
    const startAtInput = moduleForm.querySelector("input[name='start_at']");
    const endAtInput = moduleForm.querySelector("input[name='end_at']");
    const bodyInput = moduleForm.querySelector("textarea[name='message_body']");
    const redirectUrlInput = moduleForm.querySelector("input[name='redirect_url']");
    const fileInput = moduleForm.querySelector("input[name='media_file']");
    const specsInput = moduleForm.querySelector("input[name='attachment_specs']");
    const previewPanel = document.getElementById("sponsorshipPreviewPanel");
    const monthsBadge = document.getElementById("sponsorshipPreviewMonthsBadge");
    const periodBadge = document.getElementById("sponsorshipPreviewPeriodBadge");
    const sectionMeta = document.getElementById("sponsorshipPreviewSectionMeta");
    const appLogoSlot = document.getElementById("sponsorshipPreviewAppLogo");
    const sponsorTap = document.getElementById("sponsorshipPreviewSponsorTap");
    const mediaBox = document.getElementById("sponsorshipPreviewMedia");
    const titleNode = document.getElementById("sponsorshipPreviewTitle");
    const bodyNode = document.getElementById("sponsorshipPreviewBody");
    const chipNode = document.getElementById("sponsorshipPreviewChip");
    const linkNode = document.getElementById("sponsorshipPreviewLink");
    const assetNameNode = document.getElementById("sponsorshipPreviewAssetName");
    const overlay = document.getElementById("sponsorshipPreviewOverlay");
    const overlayTitle = document.getElementById("sponsorshipPreviewOverlayTitle");
    const overlayBody = document.getElementById("sponsorshipPreviewOverlayBody");
    const overlayLink = document.getElementById("sponsorshipPreviewOverlayLink");
    const overlayClose = document.getElementById("sponsorshipPreviewOverlayClose");
    const previewButton = moduleForm.querySelector("[data-live-preview-focus='true']");
    if (
      !root ||
      !sponsorNameInput ||
      !sponsorUrlInput ||
      !monthsInput ||
      !startAtInput ||
      !endAtInput ||
      !bodyInput ||
      !redirectUrlInput ||
      !fileInput ||
      !specsInput ||
      !previewPanel ||
      !monthsBadge ||
      !periodBadge ||
      !sectionMeta ||
      !appLogoSlot ||
      !sponsorTap ||
      !mediaBox ||
      !titleNode ||
      !bodyNode ||
      !chipNode ||
      !linkNode ||
      !assetNameNode ||
      !overlay ||
      !overlayTitle ||
      !overlayBody ||
      !overlayLink ||
      !overlayClose
    ) {
      return;
    }
    hideLegacyPreviewSummary();

    let previewObjectUrl = "";
    let renderedMediaKey = "";
    let rotateTimer = 0;
    let showingSponsorLogo = false;

    function cleanText(value) {
      return String(value || "").trim();
    }

    function basename(value) {
      return String(value || "")
        .split(/[\\/]/)
        .filter(Boolean)
        .pop() || "";
    }

    function parsePositiveInt(value) {
      const parsed = Number.parseInt(String(value || "").trim(), 10);
      return Number.isFinite(parsed) && parsed > 0 ? parsed : 0;
    }

    function hasActiveSponsorData() {
      return !!(
        cleanText(sponsorNameInput.value)
        || (fileInput.files && fileInput.files[0])
        || cleanText(root.dataset.existingSrc)
      );
    }

    function formatSize(bytes) {
      const size = Number(bytes || 0);
      if (!Number.isFinite(size) || size <= 0) {
        return "0 MB";
      }
      return (size / (1024 * 1024)).toFixed(2) + " MB";
    }

    function formatDateTimeLabel(value) {
      const raw = cleanText(value);
      if (!raw) {
        return "";
      }
      const parts = raw.split("T");
      if (parts.length !== 2) {
        return raw;
      }
      return parts[0] + " - " + parts[1];
    }

    function revokePreviewUrl() {
      if (!previewObjectUrl) {
        return;
      }
      try {
        URL.revokeObjectURL(previewObjectUrl);
      } catch (_) {
        // Ignore URL revocation errors.
      }
      previewObjectUrl = "";
    }

    function setLogoFace(showSponsor) {
      showingSponsorLogo = !!showSponsor;
      appLogoSlot.classList.toggle("is-active", !showingSponsorLogo);
      sponsorTap.classList.toggle("is-active", showingSponsorLogo);
    }

    function stopLogoRotation() {
      if (rotateTimer) {
        window.clearInterval(rotateTimer);
        rotateTimer = 0;
      }
      setLogoFace(false);
    }

    function startLogoRotation() {
      if (!hasActiveSponsorData()) {
        stopLogoRotation();
        sectionMeta.textContent = "لا توجد رعاية مكتملة بعد";
        return;
      }
      stopLogoRotation();
      sectionMeta.textContent = "يتم التبديل بين الشعارات تلقائيًا";
      rotateTimer = window.setInterval(() => {
        setLogoFace(!showingSponsorLogo);
      }, 2000);
    }

    function detectExistingMediaType() {
      const storedType = cleanText(root.dataset.existingType).toLowerCase();
      if (storedType === "video" || storedType === "image") {
        return storedType;
      }
      const storedName = basename(root.dataset.existingName).toLowerCase();
      return storedName.endsWith(".mp4") ? "video" : "image";
    }

    function buildMediaNode(src, mediaType, label) {
      if (mediaType === "video") {
        const video = document.createElement("video");
        video.src = src;
        video.controls = true;
        video.muted = true;
        video.loop = true;
        video.playsInline = true;
        video.preload = "metadata";
        video.setAttribute("aria-label", label || "ملف رعاية");
        return video;
      }
      const img = document.createElement("img");
      img.src = src;
      img.alt = label || "شعار الراعي";
      img.loading = "lazy";
      return img;
    }

    function renderMedia(forceRender) {
      const currentFile = fileInput.files && fileInput.files[0];
      const existingSrc = cleanText(root.dataset.existingSrc);
      const mediaKey = currentFile
        ? "file:" + currentFile.name + ":" + currentFile.size + ":" + currentFile.lastModified
        : (existingSrc ? "existing:" + existingSrc : "empty");
      if (!forceRender && mediaKey === renderedMediaKey) {
        return;
      }
      renderedMediaKey = mediaKey;
      revokePreviewUrl();
      mediaBox.textContent = "";

      if (currentFile) {
        previewObjectUrl = URL.createObjectURL(currentFile);
        const mediaType = String(currentFile.type || "").toLowerCase().startsWith("video/") ? "video" : "image";
        mediaBox.appendChild(buildMediaNode(previewObjectUrl, mediaType, basename(currentFile.name)));
        assetNameNode.textContent = basename(currentFile.name);
        specsInput.value = basename(currentFile.name) + " - " + formatSize(currentFile.size);
        return;
      }

      if (existingSrc) {
        mediaBox.appendChild(
          buildMediaNode(existingSrc, detectExistingMediaType(), basename(root.dataset.existingName) || "ملف الرعاية")
        );
        assetNameNode.textContent = basename(root.dataset.existingName) || "ملف محفوظ";
        if (!cleanText(specsInput.value) && cleanText(root.dataset.existingName)) {
          specsInput.value = basename(root.dataset.existingName);
        }
        return;
      }

      const placeholder = document.createElement("div");
      placeholder.className = "sponsorship-preview-media-placeholder";
      placeholder.textContent = "شعار أو ملف الرعاية يظهر هنا";
      mediaBox.appendChild(placeholder);
      assetNameNode.textContent = "لا يوجد ملف مرفوع";
      if (!cleanText(fileInput.value)) {
        specsInput.value = "";
      }
    }

    function renderState(fromPreviewAction) {
      const sponsorName = cleanText(sponsorNameInput.value) || "راعٍ رسمي";
      const messageBody = cleanText(bodyInput.value);
      const months = parsePositiveInt(monthsInput.value);
      const startLabel = formatDateTimeLabel(startAtInput.value);
      const endLabel = formatDateTimeLabel(endAtInput.value);
      const redirectUrl = cleanText(redirectUrlInput.value);
      const sponsorUrl = cleanText(sponsorUrlInput.value);

      chipNode.textContent = months > 0 ? "رعاية " + months + "ش" : "رعاية";
      titleNode.textContent = sponsorName;
      bodyNode.textContent = messageBody || "النبذة التعريفية ستظهر هنا عند كتابة رسالة الرعاية.";
      monthsBadge.textContent = months > 0 ? "مدة الرعاية: " + months + " شهر" : "حدد مدة الرعاية";
      periodBadge.textContent =
        startLabel && endLabel
          ? ("من " + startLabel + " إلى " + endLabel)
          : "حدد فترة الرعاية";
      linkNode.textContent = redirectUrl || sponsorUrl || "لا يوجد رابط بعد";
      sectionMeta.textContent = fromPreviewAction
        ? "تم تحديث المعاينة مباشرة"
        : "المعاينة تتحدث مع كل تغيير";
      overlayTitle.textContent = sponsorName;
      overlayBody.textContent = messageBody || "سيظهر نص رسالة الرعاية هنا عند الضغط على شعار الراعي.";
      if (redirectUrl || sponsorUrl) {
        overlayLink.hidden = false;
        overlayLink.href = redirectUrl || sponsorUrl;
      } else {
        overlayLink.hidden = true;
        overlayLink.removeAttribute("href");
      }
      renderMedia(false);
      startLogoRotation();
    }

    function focusFirstError() {
      if (requestIdInput && !cleanText(requestIdInput.value)) {
        requestIdInput.focus();
        return;
      }
      if (!parsePositiveInt(monthsInput.value)) {
        monthsInput.focus();
        return;
      }
      if (!cleanText(startAtInput.value)) {
        startAtInput.focus();
        return;
      }
      if (!cleanText(endAtInput.value)) {
        endAtInput.focus();
      }
    }

    if (previewButton) {
      previewButton.addEventListener("click", () => {
        renderMedia(true);
        renderState(true);

        const errors = [];
        if (requestIdInput && !cleanText(requestIdInput.value)) {
          errors.push("اختر رقم طلب الترويج أولاً.");
        }
        if (!parsePositiveInt(monthsInput.value)) {
          errors.push("أدخل مدة الرعاية بالأشهر.");
        }
        if (!cleanText(startAtInput.value) || !cleanText(endAtInput.value)) {
          errors.push("حدد بداية ونهاية الرعاية.");
        }
        if (errors.length) {
          focusFirstError();
          window.alert(errors.join("\n"));
          return;
        }

        previewPanel.scrollIntoView({ behavior: "smooth", block: "start" });
      });
    }

    sponsorTap.addEventListener("click", (event) => {
      event.preventDefault();
      if (!hasActiveSponsorData()) {
        return;
      }
      overlay.hidden = false;
    });

    overlayClose.addEventListener("click", () => {
      overlay.hidden = true;
    });

    sponsorNameInput.addEventListener("input", () => renderState(false));
    sponsorUrlInput.addEventListener("input", () => renderState(false));
    monthsInput.addEventListener("input", () => renderState(false));
    startAtInput.addEventListener("input", () => renderState(false));
    startAtInput.addEventListener("change", () => renderState(false));
    endAtInput.addEventListener("input", () => renderState(false));
    endAtInput.addEventListener("change", () => renderState(false));
    bodyInput.addEventListener("input", () => renderState(false));
    redirectUrlInput.addEventListener("input", () => renderState(false));
    fileInput.addEventListener("change", () => {
      renderedMediaKey = "";
      renderMedia(true);
      renderState(false);
    });

    renderMedia(true);
    renderState(false);
    window.addEventListener("beforeunload", () => {
      revokePreviewUrl();
      stopLogoRotation();
    });
  }

  function setupPromoMessagesModule() {
    const moduleForm = document.getElementById("promoModuleForm");
    if (!moduleForm) {
      return;
    }
    const moduleKey = String(moduleForm.dataset.moduleKey || "").toLowerCase();
    if (moduleKey !== "promo_messages") {
      return;
    }

    const root = document.getElementById("promoMessageModule");
    const requestIdInput = moduleForm.querySelector("input[name='request_id']");
    const bodyInput = moduleForm.querySelector("textarea[name='message_body']");
    const titleInput = moduleForm.querySelector("input[name='message_title']");
    const notificationInput = moduleForm.querySelector("input[name='use_notification_channel']");
    const chatInput = moduleForm.querySelector("input[name='use_chat_channel']");
    const fileInput = moduleForm.querySelector("input[name='media_file']");
    const specsInput = moduleForm.querySelector("input[name='attachment_specs']");
    const sendAtInput = moduleForm.querySelector("input[name='send_at']");
    const requesterLabelNode = document.getElementById("promoMessageRequesterLabel");
    const requestBadge = document.getElementById("promoMessageRequestBadge");
    const channelsBadge = document.getElementById("promoMessageChannelsBadge");
    const scheduleBadge = document.getElementById("promoMessageScheduleBadge");
    const summary = document.getElementById("promoMessagePreviewSummary");
    const previewEmpty = document.getElementById("promoMessagePreviewEmpty");
    const previewPanel = document.getElementById("promoMessagePreviewPanel");
    const notificationCard = root ? root.querySelector("[data-channel-preview='notification']") : null;
    const chatCard = root ? root.querySelector("[data-channel-preview='chat']") : null;
    const notificationBanner = document.getElementById("promoMessageNotificationBanner");
    const notificationList = document.getElementById("promoMessageNotificationList");
    const chatThread = document.getElementById("promoMessageChatThread");
    const chatTopbarMeta = document.getElementById("promoMessageChatTopbarMeta");
    const previewButton = moduleForm.querySelector("[data-live-preview-focus='true']");
    if (
      !root ||
      !requestIdInput ||
      !bodyInput ||
      !notificationInput ||
      !chatInput ||
      !fileInput ||
      !specsInput ||
      !sendAtInput ||
      !requesterLabelNode ||
      !requestBadge ||
      !channelsBadge ||
      !scheduleBadge ||
      !summary ||
      !previewEmpty ||
      !previewPanel ||
      !notificationCard ||
      !chatCard ||
      !notificationBanner ||
      !notificationList ||
      !chatThread ||
      !chatTopbarMeta
    ) {
      return;
    }
    hideLegacyPreviewSummary();

    const previewApiUrl = String(root.dataset.previewApiUrl || "").trim();
    const requestContext = {
      id: String(root.dataset.requestId || "").trim(),
      code: String(root.dataset.requestCode || "").trim(),
      senderLabel: String(root.dataset.senderLabel || "مرسل الحملة").trim() || "مرسل الحملة",
      existingName: String(root.dataset.existingName || "").trim(),
    };
    const channelCards = Array.from(root.querySelectorAll("[data-channel-card]"));
    let previewObjectUrl = "";
    let selectedFileMeta = null;
    let fileToken = 0;
    let requestFetchTimer = 0;
    let requestFetchToken = 0;
    let referenceAttachmentLabel = String(specsInput.value || requestContext.existingName || "").trim();

    function clearNode(node) {
      while (node.firstChild) {
        node.removeChild(node.firstChild);
      }
    }

    function basename(value) {
      const text = String(value || "").trim();
      if (!text) {
        return "";
      }
      return text.split("/").pop().split("\\").pop();
    }

    function cleanText(value) {
      return String(value || "").trim();
    }

    function revokePreviewUrl() {
      if (!previewObjectUrl) {
        return;
      }
      try {
        URL.revokeObjectURL(previewObjectUrl);
      } catch (_) {
        // Ignore URL revocation failures.
      }
      previewObjectUrl = "";
    }

    function readSelectedFile() {
      return fileInput.files && fileInput.files[0] ? fileInput.files[0] : null;
    }

    function detectMediaKind(file) {
      if (!file) {
        return "";
      }
      const type = String(file.type || "").toLowerCase();
      const name = String(file.name || "").toLowerCase();
      if (type.startsWith("image/") || /\.(jpg|jpeg|png|gif)$/i.test(name)) {
        return "image";
      }
      if (type === "video/mp4" || /\.mp4$/i.test(name)) {
        return "video";
      }
      return "";
    }

    function formatSize(bytes) {
      const sizeMb = Number(bytes || 0) / (1024 * 1024);
      return sizeMb.toFixed(2) + " MB";
    }

    function formatDuration(seconds) {
      const total = Math.max(0, Math.round(Number(seconds) || 0));
      const minutes = Math.floor(total / 60);
      const remain = total % 60;
      if (minutes <= 0) {
        return remain + "ث";
      }
      return minutes + "د " + remain + "ث";
    }

    function formatDateTime(value) {
      const raw = String(value || "").trim();
      if (!raw) {
        return "غير محدد";
      }
      const candidate = new Date(raw);
      if (Number.isNaN(candidate.getTime())) {
        return raw.replace("T", " - ");
      }
      try {
        return new Intl.DateTimeFormat("ar-SA", {
          year: "numeric",
          month: "2-digit",
          day: "2-digit",
          hour: "2-digit",
          minute: "2-digit",
        }).format(candidate);
      } catch (_) {
        return raw.replace("T", " - ");
      }
    }

    function buildSpecsText(file, meta) {
      if (!file) {
        return referenceAttachmentLabel;
      }
      const kind = meta && meta.kind === "video" ? "MP4" : "IMAGE";
      const parts = [basename(file.name), kind, formatSize(file.size)];
      if (meta && meta.kind === "image" && meta.width && meta.height) {
        parts.push(meta.width + "x" + meta.height);
      }
      if (meta && meta.kind === "video") {
        if (meta.width && meta.height) {
          parts.push(meta.width + "x" + meta.height);
        }
        if (meta.duration) {
          parts.push(formatDuration(meta.duration));
        }
      }
      return parts.filter(Boolean).join(" - ");
    }

    function syncChannelCards() {
      channelCards.forEach((card) => {
        const key = card.getAttribute("data-channel-card") || "";
        const active =
          (key === "notification" && notificationInput.checked) ||
          (key === "chat" && chatInput.checked);
        card.classList.toggle("is-active", active);
      });
    }

    function selectedChannels() {
      const labels = [];
      if (notificationInput.checked) {
        labels.push("التنبيه الدعائي");
      }
      if (chatInput.checked) {
        labels.push("المحادثة الدعائية");
      }
      return labels;
    }

    function notificationTitle() {
      const raw = titleInput ? String(titleInput.value || "").trim() : "";
      return raw || "رسالة دعائية جديدة";
    }

    function messageBodyText() {
      return String(bodyInput.value || "").trim();
    }

    function currentDraftHasContent() {
      return Boolean(messageBodyText() || readSelectedFile());
    }

    function updateRequestMeta(statusMessage) {
      const requestId = cleanText(requestIdInput.value);
      requesterLabelNode.textContent = requestContext.senderLabel || "-";
      requestBadge.textContent = requestContext.code
        ? "الطلب: " + requestContext.code
        : (requestId ? "الطلب: " + requestId : "اختر الطلب");
      if (statusMessage) {
        summary.textContent = statusMessage;
      }
    }

    function createMediaNode(media, compact) {
      if (!media || !media.url) {
        return null;
      }
      if (media.kind === "video") {
        const video = document.createElement("video");
        video.src = media.url;
        video.muted = true;
        video.loop = true;
        video.autoplay = true;
        video.playsInline = true;
        if (!compact) {
          video.controls = true;
        }
        return video;
      }
      const image = document.createElement("img");
      image.src = media.url;
      image.alt = media.name || "معاينة المرفق";
      image.loading = "lazy";
      return image;
    }

    function buildMediaSummary(media) {
      if (!media) {
        return null;
      }
      const wrap = document.createElement("div");
      wrap.className = "messages-notification-media";
      const node = createMediaNode(media, true);
      if (node) {
        wrap.appendChild(node);
      }
      const tag = document.createElement("span");
      tag.className = "messages-notification-tag";
      tag.textContent = media.kind === "video" ? "فيديو MP4" : "مرفق مرئي";
      wrap.appendChild(tag);
      return wrap;
    }

    function buildNotificationItem(config) {
      const item = document.createElement("div");
      item.className = "messages-notification-item";

      const badge = document.createElement("div");
      badge.className = "messages-notification-badge";
      badge.textContent = "ت";

      const copy = document.createElement("div");
      copy.className = "messages-notification-copy";
      const title = document.createElement("strong");
      title.textContent = config.title;
      const body = document.createElement("p");
      body.textContent = config.body;
      copy.appendChild(title);
      copy.appendChild(body);
      if (config.media) {
        copy.appendChild(buildMediaSummary(config.media));
      }

      const time = document.createElement("span");
      time.className = "messages-notification-time";
      time.textContent = config.time;

      item.appendChild(badge);
      item.appendChild(copy);
      item.appendChild(time);
      return item;
    }

    function buildPlaceholder(text) {
      const empty = document.createElement("div");
      empty.className = "messages-preview-placeholder";
      empty.textContent = text;
      return empty;
    }

    function renderNotificationPreview(state) {
      clearNode(notificationBanner);
      clearNode(notificationList);
      if (!notificationInput.checked) {
        return;
      }

      const bannerHead = document.createElement("div");
      bannerHead.className = "messages-notification-list-head";
      const bannerTitle = document.createElement("strong");
      bannerTitle.textContent = "تنبيه دعائي";
      const bannerTime = document.createElement("span");
      bannerTime.textContent = "الآن";
      bannerHead.appendChild(bannerTitle);
      bannerHead.appendChild(bannerTime);
      notificationBanner.appendChild(bannerHead);

      if (!state.body && !state.media) {
        notificationBanner.appendChild(buildPlaceholder("اكتب نص الرسالة أو ارفع مرفقًا واحدًا لعرض شكل الإشعار."));
      } else {
        const copy = document.createElement("div");
        copy.className = "messages-notification-copy";
        const title = document.createElement("strong");
        title.textContent = state.title;
        const body = document.createElement("p");
        body.textContent = state.body || "تم إرفاق مادة دعائية بدون نص مكتوب.";
        copy.appendChild(title);
        copy.appendChild(body);
        if (state.media) {
          copy.appendChild(buildMediaSummary(state.media));
        }
        notificationBanner.appendChild(copy);
      }

      notificationList.appendChild(
        buildNotificationItem({
          title: state.title,
          body: state.body || "تم إرفاق مادة دعائية بدون نص مكتوب.",
          time: "الآن",
          media: state.media,
        })
      );
      notificationList.appendChild(
        buildNotificationItem({
          title: "تحديثات المنصة",
          body: "تم تحديث واجهة الاستخدام وتحسين مركز الإشعارات.",
          time: "08:10",
          media: null,
        })
      );
      notificationList.appendChild(
        buildNotificationItem({
          title: "طلب جديد",
          body: "لديك نشاط جديد على حسابك داخل المنصة.",
          time: "أمس",
          media: null,
        })
      );
    }

    function renderChatPreview(state) {
      clearNode(chatThread);
      if (!chatInput.checked) {
        return;
      }

      const datePill = document.createElement("div");
      datePill.className = "messages-chat-date";
      datePill.textContent = "اليوم";
      chatThread.appendChild(datePill);

      const systemBubble = document.createElement("div");
      systemBubble.className = "messages-chat-bubble is-system";
      systemBubble.textContent = "هذه معاينة لطريقة ظهور الرسالة الدعائية داخل المحادثة.";
      chatThread.appendChild(systemBubble);

      if (!state.body && !state.media) {
        chatThread.appendChild(buildPlaceholder("أضف نصًا أو مرفقًا ليظهر شكل الرسالة داخل المحادثة."));
        return;
      }

      const bubble = document.createElement("div");
      bubble.className = "messages-chat-bubble is-outgoing";
      if (state.body) {
        const text = document.createElement("div");
        text.textContent = state.body;
        bubble.appendChild(text);
      }
      if (state.media) {
        const mediaWrap = document.createElement("div");
        mediaWrap.className = "messages-chat-bubble-media";
        const mediaNode = createMediaNode(state.media, false);
        if (mediaNode) {
          mediaWrap.appendChild(mediaNode);
        }
        const label = document.createElement("strong");
        label.textContent = state.media.name || "مرفق دعائي";
        mediaWrap.appendChild(label);
        bubble.appendChild(mediaWrap);
      }
      const meta = document.createElement("span");
      meta.className = "messages-chat-bubble-meta";
      meta.textContent = "الآن • رسالة دعائية";
      bubble.appendChild(meta);
      chatThread.appendChild(bubble);
    }

    function currentMediaState() {
      const file = readSelectedFile();
      if (!file || !previewObjectUrl) {
        return null;
      }
      return {
        name: basename(file.name),
        kind: (selectedFileMeta && selectedFileMeta.kind) || detectMediaKind(file),
        url: previewObjectUrl,
      };
    }

    function updateSummary(state, forcedPreview) {
      const channels = selectedChannels();
      updateRequestMeta("");
      channelsBadge.textContent = channels.length ? channels.join(" + ") : "لم يتم اختيار قناة بعد";
      scheduleBadge.textContent = sendAtInput.value ? formatDateTime(sendAtInput.value) : "حدد وقت الإرسال";
      chatTopbarMeta.textContent = sendAtInput.value
        ? (requestContext.senderLabel + " • " + formatDateTime(sendAtInput.value))
        : (requestContext.senderLabel + " • حدد وقت الإرسال لإكمال الجدولة");

      if (!channels.length) {
        summary.textContent = "اختر قناة واحدة على الأقل لعرض شكل الرسالة الدعائية في الجوال.";
        return;
      }
      if (!state.body && !state.media) {
        summary.textContent =
          "المعاينة نشطة، لكن المسودة الحالية لا تحتوي على نص أو مرفق بعد. أضف واحدًا على الأقل قبل الاعتماد.";
        if (referenceAttachmentLabel) {
          summary.textContent += " المرفق السابق ظاهر كمرجع فقط، ولن يرسل ما لم يتم رفعه من جديد.";
        }
        return;
      }

      let nextText =
        "سترسل الرسالة المرتبطة بـ " +
        (requestContext.code || (cleanText(requestIdInput.value) || "الطلب المحدد")) +
        " عبر " +
        channels.join(" + ") +
        (sendAtInput.value ? " بتاريخ " + formatDateTime(sendAtInput.value) : " بعد تحديد وقت الإرسال");
      if (!state.body && state.media) {
        nextText += " اعتمادًا على المرفق فقط بدون نص مكتوب.";
      } else if (state.body && !state.media) {
        nextText += " كنص دعائي فقط بدون مرفقات.";
      } else if (state.body && state.media) {
        nextText += " مع نص ومرفق دعائي.";
      }
      if (forcedPreview) {
        nextText += " تمت مزامنة المعاينة الحية ويمكنك الآن الاعتماد.";
      }
      summary.textContent = nextText;
    }

    function renderState(forcedPreview) {
      const state = {
        title: notificationTitle(),
        body: messageBodyText(),
        media: currentMediaState(),
      };
      const showNotification = notificationInput.checked;
      const showChat = chatInput.checked;
      notificationCard.hidden = !showNotification;
      chatCard.hidden = !showChat;
      previewEmpty.hidden = showNotification || showChat;
      renderNotificationPreview(state);
      renderChatPreview(state);
      updateSummary(state, forcedPreview);
      syncChannelCards();
    }

    function readImageMeta(url) {
      return new Promise((resolve, reject) => {
        const image = new Image();
        image.onload = () => resolve({ width: image.naturalWidth || 0, height: image.naturalHeight || 0 });
        image.onerror = reject;
        image.src = url;
      });
    }

    function readVideoMeta(url) {
      return new Promise((resolve, reject) => {
        const video = document.createElement("video");
        video.preload = "metadata";
        video.onloadedmetadata = () =>
          resolve({
            width: video.videoWidth || 0,
            height: video.videoHeight || 0,
            duration: Number(video.duration || 0),
          });
        video.onerror = reject;
        video.src = url;
      });
    }

    function handleFileChange() {
      const file = readSelectedFile();
      revokePreviewUrl();
      selectedFileMeta = null;
      if (!file) {
        specsInput.value = referenceAttachmentLabel;
        renderState(false);
        return;
      }

      const kind = detectMediaKind(file);
      previewObjectUrl = URL.createObjectURL(file);
      selectedFileMeta = {
        kind: kind || "other",
        name: basename(file.name),
      };
      specsInput.value = buildSpecsText(file, selectedFileMeta);
      renderState(false);

      const currentToken = fileToken + 1;
      fileToken = currentToken;
      const loader = kind === "video" ? readVideoMeta(previewObjectUrl) : readImageMeta(previewObjectUrl);
      loader
        .then((meta) => {
          if (currentToken !== fileToken) {
            return;
          }
          selectedFileMeta = Object.assign({}, selectedFileMeta, meta);
          specsInput.value = buildSpecsText(file, selectedFileMeta);
          renderState(false);
        })
        .catch(() => {
          if (currentToken !== fileToken) {
            return;
          }
          specsInput.value = basename(file.name) + " - " + formatSize(file.size);
          renderState(false);
        });
    }

    function focusFirstError() {
      if (!cleanText(requestIdInput.value)) {
        requestIdInput.focus();
        return;
      }
      if (!notificationInput.checked && !chatInput.checked) {
        notificationInput.focus();
        return;
      }
      if (!String(sendAtInput.value || "").trim()) {
        sendAtInput.focus();
        return;
      }
      if (!currentDraftHasContent()) {
        bodyInput.focus();
      }
    }

    function applyRequestPreviewPayload(payload) {
      const requestPayload = payload && payload.request ? payload.request : {};
      const assetPayload = payload && payload.asset ? payload.asset : {};
      requestContext.id = cleanText(requestPayload.id);
      requestContext.code = cleanText(requestPayload.code);
      requestContext.senderLabel = cleanText(requestPayload.requester_label) || "مرسل الحملة";
      requestContext.existingName = cleanText(assetPayload.name);
      referenceAttachmentLabel = basename(requestContext.existingName);
      if (!readSelectedFile()) {
        specsInput.value = referenceAttachmentLabel;
      }
      renderState(false);
      if (referenceAttachmentLabel) {
        updateRequestMeta("تم تحديث بيانات الطلب ومرجع المرفق السابق داخل المعاينة.");
      } else {
        updateRequestMeta("تم تحديث بيانات الطلب. لا يوجد مرفق مرجعي محفوظ لهذا الطلب.");
      }
    }

    function handleRequestPreviewFailure(message) {
      requestContext.id = cleanText(requestIdInput.value);
      requestContext.code = cleanText(requestIdInput.value);
      requestContext.senderLabel = "-";
      requestContext.existingName = "";
      referenceAttachmentLabel = "";
      if (!readSelectedFile()) {
        specsInput.value = "";
      }
      renderState(false);
      updateRequestMeta(message || "تعذر جلب بيانات الطلب الآن.");
    }

    function loadRequestPreview() {
      const requestId = cleanText(requestIdInput.value);
      if (!requestId) {
        handleRequestPreviewFailure("اختر رقم طلب الترويج أولاً ليتم تحديث الحساب المرجعي.");
        return;
      }
      if (!previewApiUrl) {
        updateRequestMeta("المعاينة الحية تعمل بالبيانات الحالية فقط في هذه الصفحة.");
        return;
      }
      const token = ++requestFetchToken;
      updateRequestMeta("جارٍ تحميل بيانات الطلب المختار...");
      fetch(previewApiUrl + "?request_id=" + encodeURIComponent(requestId), {
        method: "GET",
        headers: { "X-Requested-With": "XMLHttpRequest" },
        credentials: "same-origin",
      })
        .then((response) =>
          response
            .json()
            .catch(() => ({}))
            .then((payload) => ({ response, payload }))
        )
        .then(({ response, payload }) => {
          if (token !== requestFetchToken) {
            return;
          }
          if (!response.ok || !payload || payload.ok !== true) {
            throw new Error((payload && payload.error) || "تعذر جلب بيانات الطلب.");
          }
          applyRequestPreviewPayload(payload);
        })
        .catch((error) => {
          if (token !== requestFetchToken) {
            return;
          }
          handleRequestPreviewFailure(error && error.message ? error.message : "تعذر جلب بيانات الطلب.");
        });
    }

    function scheduleRequestPreviewLoad() {
      if (requestFetchTimer) {
        window.clearTimeout(requestFetchTimer);
      }
      requestFetchTimer = window.setTimeout(loadRequestPreview, 240);
    }

    if (previewButton) {
      previewButton.addEventListener("click", () => {
        renderState(true);

        const errors = [];
        if (!cleanText(requestIdInput.value)) {
          errors.push("يرجى اختيار طلب الترويج أولاً.");
        }
        if (!notificationInput.checked && !chatInput.checked) {
          errors.push("يرجى اختيار قناة ترويج واحدة على الأقل.");
        }
        if (!String(sendAtInput.value || "").trim()) {
          errors.push("يرجى تحديد تاريخ ووقت الإرسال.");
        }
        if (!currentDraftHasContent()) {
          errors.push("لا يمكن معاينة رسالة فارغة. أضف نصًا أو ارفع مرفقًا واحدًا.");
        }
        if (errors.length) {
          focusFirstError();
          window.alert(errors.join("\n"));
          return;
        }

        previewPanel.scrollIntoView({ behavior: "smooth", block: "start" });
      });
    }

    notificationInput.addEventListener("change", () => renderState(false));
    chatInput.addEventListener("change", () => renderState(false));
    bodyInput.addEventListener("input", () => renderState(false));
    sendAtInput.addEventListener("input", () => renderState(false));
    sendAtInput.addEventListener("change", () => renderState(false));
    requestIdInput.addEventListener("input", scheduleRequestPreviewLoad);
    requestIdInput.addEventListener("change", scheduleRequestPreviewLoad);
    requestIdInput.addEventListener("blur", scheduleRequestPreviewLoad);
    fileInput.addEventListener("change", handleFileChange);

    updateRequestMeta("");
    renderState(false);
    window.addEventListener("beforeunload", revokePreviewUrl);
  }

  function setupTeamPanels() {
    const storageKey = "dashboard.promo.selectedTeamPanel";
    const menu = document.getElementById("teamFixedMenu");
    const panelRoot = document.getElementById("teamPanels");
    if (!menu || !panelRoot) {
      return;
    }

    const buttons = Array.from(menu.querySelectorAll(".team-fixed-btn"));
    const panels = Array.from(panelRoot.querySelectorAll(".team-panel-card"));
    if (!buttons.length || !panels.length) {
      return;
    }

    function activate(teamKey) {
      buttons.forEach((btn) => {
        const active = btn.dataset.teamTarget === teamKey;
        btn.classList.toggle("active", active);
        btn.setAttribute("aria-selected", active ? "true" : "false");
      });

      panels.forEach((panel) => {
        const active = panel.dataset.teamPanel === teamKey;
        panel.classList.toggle("active", active);
        panel.hidden = !active;
      });

      try {
        window.localStorage.setItem(storageKey, teamKey);
      } catch (_) {
        // Ignore storage failures in restricted browser modes.
      }
    }

    buttons.forEach((btn) => {
      btn.addEventListener("click", () => {
        const key = btn.dataset.teamTarget;
        if (!key) {
          return;
        }
        activate(key);
      });
    });

    try {
      const saved = window.localStorage.getItem(storageKey);
      if (saved && buttons.some((btn) => btn.dataset.teamTarget === saved)) {
        activate(saved);
      }
    } catch (_) {
      // Ignore storage failures in restricted browser modes.
    }
  }

  document.addEventListener("DOMContentLoaded", () => {
    attachCharCounters();
    syncFileSpecs();
    setupActionConfirmations();
    setupPromoLightbox();
    setupInquiryCommentLinkInsertion();
    setupModuleWorkflow();
    setupHomeBannerModulePreview();
    setupPortfolioShowcaseModule();
    setupSnapshotsModule();
    setupSearchResultsModule();
    setupSponsorshipModule();
    setupPromoMessagesModule();
    scrollActiveRow();
    setupTeamPanels();
  });
})();
