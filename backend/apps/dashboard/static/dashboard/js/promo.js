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
      } else if (moduleKey === "home_banner") {
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
    scrollActiveRow();
    setupTeamPanels();
  });
})();
