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
    document.querySelectorAll("textarea[maxlength]").forEach((textarea) => {
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

  function setupInquiryConfirmations() {
    const form = document.getElementById("verificationInquiryForm");
    if (!form) {
      return;
    }
    form.addEventListener("submit", (event) => {
      const submitter = event.submitter;
      if (!submitter) {
        return;
      }
      if ((submitter.value || "") === "close_inquiry") {
        if (!window.confirm("تأكيد إغلاق استفسار التوثيق؟")) {
          event.preventDefault();
          return;
        }
      }
      form.querySelectorAll("button[type='submit']").forEach((button) => {
        button.style.opacity = "0.65";
        if (submitter && button === submitter) {
          // Keep the clicked submitter enabled for this tick so its name/value
          // stays in the submitted payload (needed for server action routing).
          window.setTimeout(() => {
            button.disabled = true;
          }, 0);
          return;
        }
        button.disabled = true;
      });
    });
  }

  function setupRequestSubmitState() {
    const form = document.getElementById("verificationRequestActionForm");
    if (!form) {
      return;
    }
    form.addEventListener("submit", (event) => {
      const submitter = event.submitter;
      form.querySelectorAll("button[type='submit']").forEach((button) => {
        button.style.opacity = "0.65";
        if (submitter && button === submitter) {
          // Keep the clicked submitter enabled for this tick so its name/value
          // stays in the submitted payload (needed for server action routing).
          window.setTimeout(() => {
            button.disabled = true;
          }, 0);
          return;
        }
        button.disabled = true;
      });
    });
  }

  function setupRequestAutoSave() {
    const form = document.getElementById("verificationRequestActionForm");
    if (!form) {
      return;
    }

    const stageInput = form.querySelector("input[name='request_stage']");
    const isReviewStage = stageInput && (stageInput.value || "").trim().toLowerCase() === "review";
    if (!isReviewStage) {
      return;
    }

    const saveButton = form.querySelector("button[type='submit'][name='action'][value='save_request']");
    if (!saveButton) {
      return;
    }

    const actionsRow = saveButton.closest(".actions");
    if (!actionsRow) {
      return;
    }

    const statusSelect = form.querySelector("select[name='status']");
    const assigneeSelect = form.querySelector("select[name='assigned_to']");

    const indicator = document.createElement("small");
    indicator.className = "verification-autosave-indicator";
    indicator.style.marginInlineStart = "8px";
    indicator.style.color = "#6f1d79";
    indicator.textContent = "سيتم الحفظ تلقائيًا عند التعديل";
    actionsRow.insertBefore(indicator, saveButton);

    let autosaveTimer = 0;
    let isSaving = false;
    let hasQueuedSave = false;

    function setIndicator(text, color) {
      indicator.textContent = text;
      if (color) {
        indicator.style.color = color;
      }
    }

    function buildAutosaveFormData() {
      const payload = new FormData(form);
      payload.set("action", "save_request");
      payload.set("request_stage", "review");
      return payload;
    }

    async function runAutosave() {
      if (isSaving) {
        hasQueuedSave = true;
        return;
      }
      isSaving = true;
      setIndicator("جاري الحفظ...", "#1e40af");
      try {
        const response = await fetch(form.getAttribute("action") || window.location.href, {
          method: "POST",
          body: buildAutosaveFormData(),
          headers: { "X-Requested-With": "XMLHttpRequest" },
          credentials: "same-origin",
        });
        if (response.ok) {
          setIndicator("تم الحفظ تلقائيًا", "#15803d");
        } else {
          setIndicator("تعذر الحفظ التلقائي - استخدم زر حفظ", "#b91c1c");
        }
      } catch (_) {
        setIndicator("تعذر الحفظ التلقائي - تحقق من الاتصال", "#b91c1c");
      } finally {
        isSaving = false;
        if (hasQueuedSave) {
          hasQueuedSave = false;
          runAutosave();
        }
      }
    }

    function scheduleAutosave() {
      if (autosaveTimer) {
        window.clearTimeout(autosaveTimer);
      }
      autosaveTimer = window.setTimeout(runAutosave, 850);
    }

    function onReviewFieldChange() {
      if (statusSelect && (statusSelect.value || "").trim() === "new") {
        statusSelect.value = "in_review";
      }
      scheduleAutosave();
    }

    const watchedSelectors = [
      "select[name='assigned_to']",
      "select[name='status']",
      "textarea[name='admin_note']",
      "input[name^='decision_']",
      "input[name^='evidence_expires_at_']",
    ];

    watchedSelectors.forEach((selector) => {
      form.querySelectorAll(selector).forEach((element) => {
        const eventName = element.matches("textarea") || element.matches("input[type='datetime-local']") ? "input" : "change";
        element.addEventListener(eventName, onReviewFieldChange);
      });
    });

    if (statusSelect && (statusSelect.value || "").trim() === "") {
      statusSelect.value = "new";
    }

    if (assigneeSelect && !assigneeSelect.value) {
      setIndicator("اختر المكلف وسيتم حفظه تلقائيًا", "#6f1d79");
    }
  }

  function setupConfirmationButtons() {
    document.querySelectorAll("button[data-confirm-message]").forEach((button) => {
      button.addEventListener("click", (event) => {
        const message = button.getAttribute("data-confirm-message") || "";
        if (message && !window.confirm(message)) {
          event.preventDefault();
        }
      });
    });
  }

  function setupInquiryCommentLinkInsertion() {
    const form = document.getElementById("verificationInquiryForm");
    if (!form) {
      return;
    }

    const insertBtn = document.getElementById("insertVerificationDetailLinkBtn");
    const commentField = form.querySelector("textarea[name='operator_comment']");
    const detailUrlField = form.querySelector("input[name='detailed_request_url']");
    if (!insertBtn || !commentField || !detailUrlField) {
      return;
    }

    const linkLabel = "رابط صفحة طلب التوثيق التفصيلي: ";

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

  function scrollSelectionIntoView() {
    const activeRow = document.querySelector(".active-ticket");
    if (activeRow) {
      activeRow.scrollIntoView({ block: "center", behavior: "smooth" });
    }

    const hash = window.location.hash || "";
    if (
      hash === "#verificationInquiryForm" ||
      hash === "#verificationRequestActionForm" ||
      hash === "#verifiedAccountDetailCard"
    ) {
      const target = document.querySelector(hash);
      if (target) {
        target.scrollIntoView({ block: "start", behavior: "smooth" });
      }
      return;
    }

    const params = new URLSearchParams(window.location.search || "");
    const selector = params.has("request")
      ? "#verificationRequestActionForm"
      : (params.has("inquiry")
        ? "#verificationInquiryForm"
        : (params.has("verified_badge") ? "#verifiedAccountDetailCard" : ""));
    if (selector) {
      const target = document.querySelector(selector);
      if (target) {
        target.scrollIntoView({ block: "start", behavior: "smooth" });
      }
    }
  }

  document.addEventListener("DOMContentLoaded", () => {
    closeAlerts();
    attachCharCounters();
    setupInquiryConfirmations();
    setupRequestSubmitState();
    setupRequestAutoSave();
    setupConfirmationButtons();
    setupInquiryCommentLinkInsertion();
    scrollSelectionIntoView();
  });
})();
