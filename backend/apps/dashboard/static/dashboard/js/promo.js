(function () {
  "use strict";

  function closeAlerts() {
    const list = document.getElementById("alertsList");
    if (!list) {
      return;
    }
    list.querySelectorAll("button").forEach((btn) => {
      btn.addEventListener("click", () => {
        const alert = btn.closest(".alert");
        if (alert) {
          alert.remove();
        }
      });
    });
    window.setTimeout(() => {
      list.querySelectorAll(".alert").forEach((alert) => alert.remove());
    }, 9000);
  }

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

      const confirmMessage = submitter.getAttribute("data-require-confirm") || "";
      if (confirmMessage && !window.confirm(confirmMessage)) {
        event.preventDefault();
        return;
      }

      const value = (submitter.value || "").toLowerCase();
      const originalText = submitter.textContent;
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
          submitter.disabled = false;
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

    const mediaInput = moduleForm.querySelector("input[name='media_file']");
    const previewScreen = document.getElementById("homeBannerPhonePreviewMedia");
    const emptyState = document.getElementById("homeBannerPhonePreviewEmpty");
    const metaText = document.getElementById("homeBannerPreviewMeta");
    const specsInput = moduleForm.querySelector("input[name='attachment_specs']");
    if (!mediaInput || !previewScreen || !emptyState) {
      return;
    }

    let previewObjectUrl = "";

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

    function renderExistingAsset() {
      const existingSrc = previewScreen.dataset.existingSrc || "";
      const existingType = String(previewScreen.dataset.existingType || "").toLowerCase();
      if (!existingSrc) {
        renderEmptyState("اختر التصميم لعرضه داخل شاشة الجوال.");
        if (metaText) {
          metaText.textContent = "المعاينة الفورية تظهر هنا قبل الحفظ.";
        }
        return;
      }

      clearPreviewScreen();
      const mediaNode =
        existingType === "video"
          ? buildVideo(existingSrc, "معاينة فيديو محفوظ")
          : buildImage(existingSrc, "معاينة تصميم محفوظ");
      previewScreen.appendChild(mediaNode);
      if (metaText) {
        metaText.textContent = "هذا هو آخر تصميم محفوظ وسيتم عرضه تلقائيًا وقت الحملة.";
      }
    }

    function updateAttachmentSpecs(file) {
      if (!specsInput || !file) {
        return;
      }
      const sizeMb = (file.size || 0) / (1024 * 1024);
      specsInput.value = (file.name || "asset") + " - " + sizeMb.toFixed(2) + " MB";
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

    mediaInput.addEventListener("change", () => {
      const file = mediaInput.files && mediaInput.files[0] ? mediaInput.files[0] : null;
      renderSelectedAsset(file);
    });

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

    const providerInput = moduleForm.querySelector("input[name='target_provider_id']");
    const selectedItemInput = moduleForm.querySelector("input[name='target_portfolio_item_id']");
    const gallery = document.getElementById("portfolioShowcaseGallery");
    const galleryStatus = document.getElementById("portfolioShowcaseGalleryStatus");
    const galleryCount = document.getElementById("portfolioShowcaseGalleryCount");
    const providerName = document.getElementById("portfolioShowcaseProviderName");
    const preview = document.getElementById("portfolioShowcasePhonePreview");
    const previewEmpty = document.getElementById("portfolioShowcasePhoneEmpty");
    const previewCaption = document.getElementById("portfolioShowcasePreviewCaption");
    if (!providerInput || !selectedItemInput || !gallery || !galleryStatus || !galleryCount || !preview || !previewEmpty) {
      return;
    }

    const apiTemplate = String(gallery.dataset.apiTemplate || "");
    const initialSelection = {
      id: Number(gallery.dataset.selectedItemId || 0),
      file_url: gallery.dataset.selectedItemFile || "",
      thumbnail_url: gallery.dataset.selectedItemThumbnail || "",
      caption: gallery.dataset.selectedItemCaption || "",
    };

    let items = [];
    let requestToken = 0;
    let fetchTimer = 0;

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
        updateSelectionVisuals();
        renderPreview(null);
        return;
      }
      selectedItemInput.value = String(item.id);
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
        renderPreview(null);
        setStatus("لا توجد صور متاحة في معرض أعمال هذا المزود حاليًا.", "warning");
        return;
      }

      items.forEach((item) => {
        gallery.appendChild(buildCard(item));
      });

      const selectedId = Number(selectedItemInput.value || initialSelection.id || 0);
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

    function loadPortfolioItems() {
      const providerId = String(providerInput.value || "").trim();
      if (!providerId || !/^[0-9]+$/.test(providerId) || !apiTemplate) {
        clearNode(gallery);
        setCount(0);
        selectedItemInput.value = "";
        renderPreview(initialSelection.id ? initialSelection : null);
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

    if (initialSelection.id && (initialSelection.file_url || initialSelection.thumbnail_url)) {
      renderPreview(initialSelection);
    } else {
      renderPreview(null);
    }
    if ((providerInput.value || "").trim()) {
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

    const providerInput = moduleForm.querySelector("input[name='target_provider_id']");
    const gallery = document.getElementById("snapshotsGallery");
    const galleryStatus = document.getElementById("snapshotsGalleryStatus");
    const galleryCount = document.getElementById("snapshotsGalleryCount");
    const providerName = document.getElementById("snapshotsProviderName");
    const phoneStrip = document.getElementById("snapshotsPhoneStrip");
    const phoneViewer = document.getElementById("snapshotsPhoneViewer");
    const phoneEmpty = document.getElementById("snapshotsPhoneEmpty");
    const previewCaption = document.getElementById("snapshotsPreviewCaption");
    if (!providerInput || !gallery || !galleryStatus || !galleryCount || !phoneStrip || !phoneViewer || !phoneEmpty) {
      return;
    }

    const apiTemplate = String(gallery.dataset.apiTemplate || "");
    let items = [];
    let requestToken = 0;
    let fetchTimer = 0;

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
      galleryCount.textContent = String(count || 0) + " لمحة";
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
          previewCaption.textContent = "اللمحات تظهر بشكل دائري، وعند فتحها تعرض المحتوى بشكل رأسي شبيه بتجربة المقاطع القصيرة.";
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
        previewCaption.textContent = item.caption || "تم تجهيز معاينة اللمحة الحالية.";
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
        updateActiveStates(0);
        renderPhonePreview(null);
        return;
      }
      updateActiveStates(item.id);
      renderPhonePreview(item);
      setStatus("تم تحميل لمحات المزود. الحفظ سيعتمد ربط الحملة بالمزود نفسه.", "success");
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
      title.textContent = item.caption || "لمحة بدون وصف";
      const meta = document.createElement("span");
      meta.className = "snapshots-card-meta";
      meta.textContent = "رقم اللمحة #" + String(item.id || "");
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
      return Array.isArray(payload) ? payload : Array.isArray(payload && payload.results) ? payload.results : [];
    }

    function renderItems(nextItems) {
      items = Array.isArray(nextItems) ? nextItems : [];
      clearNode(gallery);
      clearNode(phoneStrip);
      setCount(items.length);

      if (!items.length) {
        activateItem(null);
        setStatus("لا توجد لمحات منشورة لهذا المزود حاليًا.", "warning");
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
      activateItem(items[0]);
    }

    function loadSpotlights() {
      const providerId = String(providerInput.value || "").trim();
      if (!providerId || !/^[0-9]+$/.test(providerId) || !apiTemplate) {
        clearNode(gallery);
        clearNode(phoneStrip);
        setCount(0);
        activateItem(null);
        setStatus("أدخل معرف مزود خدمة صحيح ليتم جلب اللمحات.", "neutral");
        return;
      }

      const currentToken = requestToken + 1;
      requestToken = currentToken;
      setStatus("جار جلب لمحات المزود من الباكند...", "loading");

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
          activateItem(null);
          setStatus("تعذر تحميل اللمحات الآن. حاول مرة أخرى.", "error");
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

    activateItem(null);
    if ((providerInput.value || "").trim()) {
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
    closeAlerts();
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
    scrollActiveRow();
    setupTeamPanels();
  });
})();
