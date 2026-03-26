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
    const requestForm = document.getElementById("promoRequestActionForm");
    if (requestForm) {
      requestForm.addEventListener("submit", (event) => {
        const submitter = event.submitter;
        if (!submitter) {
          return;
        }
        const action = submitter.value || "";
        if (action === "quote_request") {
          if (!window.confirm("اعتماد التسعير وإنشاء فاتورة للطلب؟")) {
            event.preventDefault();
            return;
          }
        }
        if (action === "activate_request") {
          if (!window.confirm("تفعيل الطلب بعد التحقق من الدفع؟")) {
            event.preventDefault();
            return;
          }
        }
        if (action === "complete_request") {
          if (!window.confirm("تأكيد إكمال تنفيذ الطلب؟")) {
            event.preventDefault();
            return;
          }
        }
      });
    }

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
      submitter.textContent = value === "preview_item" ? "جار تجهيز المعاينة..." : "جار اعتماد البند...";

      window.setTimeout(() => {
        if (submitter.dataset.submitting === "1") {
          submitter.disabled = false;
          submitter.textContent = originalText;
          delete submitter.dataset.submitting;
        }
      }, 6500);
    });
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
    setupModuleWorkflow();
    scrollActiveRow();
    setupTeamPanels();
  });
})();
