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

      function update() {
        const count = (textarea.value || "").length;
        counter.textContent = count + " / " + max;
        counter.style.color = count > max ? "#b83838" : "#6f1d79";
      }
      textarea.addEventListener("input", update);
      update();
    });
  }

  function updateFileSpecs() {
    const fileInputs = document.querySelectorAll("input[type='file']");
    fileInputs.forEach((input) => {
      input.addEventListener("change", () => {
        const form = input.closest("form");
        if (!form) {
          return;
        }
        const specs = form.querySelector("input[name='file_specs']");
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

  function setupReviewFormConfirmations() {
    const form = document.getElementById("contentReviewsActionForm");
    if (!form) {
      return;
    }
    form.addEventListener("submit", (event) => {
      const submitter = event.submitter;
      if (!submitter) {
        return;
      }
      const action = submitter.value || "";
      if (action === "close_ticket") {
        const ok = window.confirm("هل تريد إغلاق الطلب؟");
        if (!ok) {
          event.preventDefault();
          return;
        }
      }
      if (action === "return_ticket") {
        const ok = window.confirm("هل تريد إعادة الطلب للعميل؟");
        if (!ok) {
          event.preventDefault();
          return;
        }
      }

      const moderation = form.querySelector("select[name='moderation_action']");
      if (moderation && moderation.value === "delete_target") {
        const ok = window.confirm("سيتم حذف/إخفاء المحتوى محل الشكوى. هل تريد المتابعة؟");
        if (!ok) {
          event.preventDefault();
          return;
        }
      }

      form.querySelectorAll("button[type='submit']").forEach((btn) => {
        btn.disabled = true;
        btn.style.opacity = "0.68";
      });
    });
  }

  function setupLiveTableSearch() {
    const searchInput = document.querySelector("input[name='q']");
    const tableRows = Array.from(document.querySelectorAll("#contentReviewsTable tbody tr"));
    if (!searchInput || !tableRows.length) {
      return;
    }
    searchInput.addEventListener("input", () => {
      const term = (searchInput.value || "").trim().toLowerCase();
      tableRows.forEach((row) => {
        const text = (row.textContent || "").toLowerCase();
        row.style.display = !term || text.includes(term) ? "" : "none";
      });
    });
  }

  function scrollSelectedRow() {
    const row = document.querySelector(".support-row.active-ticket");
    if (!row) {
      return;
    }
    row.scrollIntoView({ block: "center", behavior: "smooth" });
  }

  document.addEventListener("DOMContentLoaded", () => {
    closeAlerts();
    attachCharCounters();
    updateFileSpecs();
    setupReviewFormConfirmations();
    setupLiveTableSearch();
    scrollSelectedRow();
  });
})();
