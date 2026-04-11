(function () {
  "use strict";

  /* closeAlerts — handled globally by _base.html toast system */

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
      const confirmMsg = submitter.getAttribute("data-confirm-message");
      if (confirmMsg) {
        const ok = window.confirm(confirmMsg);
        if (!ok) {
          event.preventDefault();
          return;
        }
      } else if (action === "close_ticket") {
        const ok = window.confirm("هل تريد إغلاق الطلب؟");
        if (!ok) {
          event.preventDefault();
          return;
        }
      } else if (action === "return_ticket") {
        const ok = window.confirm("هل تريد إعادة الطلب للعميل؟");
        if (!ok) {
          event.preventDefault();
          return;
        }
      }

      form.querySelectorAll("button[type='submit']").forEach((button) => {
        button.disabled = true;
        button.classList.add("is-loading");
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

  function shouldScrollToDetails() {
    if ((window.location.hash || "") === "#supportActionForm") {
      return true;
    }
    if (/\/support\/\d+\/?$/i.test(window.location.pathname || "")) {
      return true;
    }
    const params = new URLSearchParams(window.location.search || "");
    return params.has("ticket");
  }

  function scrollToTicketDetailsIfNeeded() {
    if (!shouldScrollToDetails()) {
      return;
    }
    const details = document.querySelector(".support-detail-shell") || document.getElementById("supportActionForm");
    if (!details) {
      return;
    }
    details.scrollIntoView({ block: "start", behavior: "smooth" });
  }

  function setupAssigneeFilterByTeam() {
    const form = document.getElementById("supportActionForm");
    if (!form) {
      return;
    }

    const teamSelect = form.querySelector("select[name='assigned_team']");
    const assigneeSelect = form.querySelector("select[name='assigned_to']");
    const state = window.supportDashboardState || {};
    const assigneesByTeam = state.assigneesByTeam || {};
    if (!teamSelect || !assigneeSelect || !Object.keys(assigneesByTeam).length) {
      return;
    }

    function renderOptions(teamId) {
      const currentValue = assigneeSelect.value || "";
      const choices = Array.isArray(assigneesByTeam[String(teamId)]) ? assigneesByTeam[String(teamId)] : [];

      assigneeSelect.innerHTML = "";
      const blank = document.createElement("option");
      blank.value = "";
      blank.textContent = "غير محدد";
      assigneeSelect.appendChild(blank);

      choices.forEach((entry) => {
        if (!Array.isArray(entry) || entry.length < 2) {
          return;
        }
        const option = document.createElement("option");
        option.value = String(entry[0] || "");
        option.textContent = String(entry[1] || "");
        assigneeSelect.appendChild(option);
      });

      if (currentValue && choices.some((entry) => String(entry[0] || "") === currentValue)) {
        assigneeSelect.value = currentValue;
      } else {
        assigneeSelect.value = "";
      }
    }

    teamSelect.addEventListener("change", () => {
      renderOptions(teamSelect.value || "");
    });

    renderOptions(teamSelect.value || "");
  }

  function setupTeamPanels() {
    const storageKey = "dashboard.support.selectedTeamPanel";
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
    setupLiveSearch();
    setupActionForm();
    markActiveTicket();
    scrollToTicketDetailsIfNeeded();
    setupAssigneeFilterByTeam();
    setupTeamPanels();
  });
})();

