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
  }

  function attachCharCounter(textarea, limit) {
    if (!textarea) {
      return;
    }
    const counter = document.createElement("small");
    counter.className = "char-counter";
    textarea.insertAdjacentElement("afterend", counter);

    function updateCounter() {
      const value = (textarea.value || "").length;
      counter.textContent = value + " / " + limit;
      counter.style.color = value > limit ? "#b83838" : "#6f1d79";
    }

    textarea.addEventListener("input", updateCounter);
    updateCounter();
  }

  function setupLiveSearch() {
    const searchInput = document.querySelector("input[name='q']");
    const rows = Array.from(document.querySelectorAll("#supportTicketsTable tbody tr"));
    if (!searchInput || !rows.length) {
      return;
    }

    searchInput.addEventListener("input", () => {
      const term = (searchInput.value || "").trim().toLowerCase();
      rows.forEach((row) => {
        const text = (row.textContent || "").toLowerCase();
        row.style.display = !term || text.includes(term) ? "" : "none";
      });
    });
  }

  function setupActionForm() {
    const form = document.getElementById("supportActionForm");
    if (!form) {
      return;
    }

    const description = form.querySelector("textarea[name='description']");
    const comment = form.querySelector("textarea[name='assignee_comment']");
    attachCharCounter(description, 300);
    attachCharCounter(comment, 300);

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

      form.querySelectorAll("button[type='submit']").forEach((button) => {
        button.disabled = true;
        button.style.opacity = "0.65";
      });
    });
  }

  function markActiveTicket() {
    const row = document.querySelector(".support-row.active-ticket");
    if (!row) {
      return;
    }
    row.scrollIntoView({ block: "center", behavior: "smooth" });
  }

  document.addEventListener("DOMContentLoaded", () => {
    closeAlerts();
    setupLiveSearch();
    setupActionForm();
    markActiveTicket();
  });
})();

