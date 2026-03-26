(function () {
  "use strict";

  const state = window.dashboardPageState || { section: "access" };

  function formatNumber(value) {
    const numeric = Number(value);
    if (!Number.isFinite(numeric)) {
      return String(value || "0");
    }
    return new Intl.NumberFormat("ar-SA").format(numeric);
  }

  function animateValue(node) {
    const rawText = (node.textContent || "").replace(/,/g, "").trim();
    const target = Number(rawText);
    if (!Number.isFinite(target)) {
      return;
    }
    const duration = 700;
    const start = performance.now();
    function tick(now) {
      const progress = Math.min(1, (now - start) / duration);
      const current = Math.round(target * progress);
      node.textContent = formatNumber(current);
      if (progress < 1) {
        window.requestAnimationFrame(tick);
      }
    }
    window.requestAnimationFrame(tick);
  }

  function animateCounters() {
    const values = document.querySelectorAll("[data-animate-number]");
    values.forEach(animateValue);
  }

  function fillMetricBars(scope) {
    const groups = (scope || document).querySelectorAll(".kpi-content");
    groups.forEach((group) => {
      const valueNodes = Array.from(group.querySelectorAll(".metric .value"));
      if (!valueNodes.length) {
        return;
      }
      const numbers = valueNodes
        .map((node) => Number((node.textContent || "").replace(/,/g, "").trim()))
        .filter((num) => Number.isFinite(num));
      const max = Math.max(1, ...numbers);
      const metricNodes = Array.from(group.querySelectorAll(".metric"));
      metricNodes.forEach((metricNode) => {
        const valueNode = metricNode.querySelector(".value");
        const bar = metricNode.querySelector("[data-bar-fill]");
        if (!valueNode || !bar) {
          return;
        }
        const value = Number((valueNode.textContent || "").replace(/,/g, "").trim());
        const ratio = Number.isFinite(value) ? Math.max(3, Math.round((value / max) * 100)) : 0;
        window.setTimeout(() => {
          bar.style.width = ratio + "%";
        }, 120);
      });
    });
  }

  function closeAlerts() {
    const alertList = document.getElementById("alertsList");
    if (!alertList) {
      return;
    }
    alertList.querySelectorAll("button").forEach((btn) => {
      btn.addEventListener("click", () => {
        const alert = btn.closest(".alert");
        if (alert) {
          alert.remove();
        }
      });
    });
    window.setTimeout(() => {
      alertList.querySelectorAll(".alert").forEach((alert) => alert.remove());
    }, 8000);
  }

  function applyAccessFilters() {
    const search = document.getElementById("accessSearch");
    const level = document.getElementById("levelFilter");
    const rows = Array.from(document.querySelectorAll("#accessTable tbody tr"));
    if (!rows.length || !search || !level) {
      return;
    }

    const searchValue = (search.value || "").trim().toLowerCase();
    const levelValue = (level.value || "").trim().toLowerCase();

    rows.forEach((row) => {
      if (!row.dataset.username) {
        return;
      }
      const haystack = [row.dataset.username, row.dataset.mobile, row.dataset.dashboard, row.dataset.level]
        .join(" ")
        .toLowerCase();
      const levelOk = !levelValue || row.dataset.level === levelValue;
      const searchOk = !searchValue || haystack.indexOf(searchValue) >= 0;
      row.classList.toggle("dim", !(levelOk && searchOk));
      row.style.display = levelOk && searchOk ? "" : "none";
    });
  }

  function setupAccessFilters() {
    const search = document.getElementById("accessSearch");
    const level = document.getElementById("levelFilter");
    const clearBtn = document.getElementById("clearFiltersBtn");
    if (!search || !level) {
      return;
    }
    search.addEventListener("input", applyAccessFilters);
    level.addEventListener("change", applyAccessFilters);
    if (clearBtn) {
      clearBtn.addEventListener("click", () => {
        search.value = "";
        level.value = "";
        applyAccessFilters();
      });
    }
    applyAccessFilters();
  }

  function setupAccessLevelHints() {
    const form = document.getElementById("accessForm");
    if (!form) {
      return;
    }

    const levelSelect = form.querySelector("select[name='level']");
    const dashboardChecks = Array.from(form.querySelectorAll("input[name='dashboards']"));
    const levelHint = document.getElementById("accessLevelHint");
    const dashboardsHint = document.getElementById("accessDashboardsHint");
    if (!levelSelect || !dashboardChecks.length) {
      return;
    }

    const hints = {
      admin: {
        level: "Admin: صلاحية كاملة على جميع اللوحات وجميع العمليات.",
        dashboards: "سيتم منح جميع اللوحات الداخلية تلقائيًا عند الحفظ.",
        lock: true,
        pickOne: false,
      },
      power: {
        level: "Power User: يمكنه العمل على لوحة واحدة أو أكثر بكامل العمليات.",
        dashboards: "اختر لوحة واحدة على الأقل.",
        lock: false,
        pickOne: false,
      },
      user: {
        level: "User: يعمل على لوحة واحدة فقط وضمن نطاق الطلبات المكلف بها.",
        dashboards: "اختر لوحة تحكم واحدة فقط.",
        lock: false,
        pickOne: true,
      },
      qa: {
        level: "QA: وصول لجميع اللوحات بدون صلاحيات تنفيذ (قراءة فقط).",
        dashboards: "سيتم منح جميع اللوحات الداخلية تلقائيًا (قراءة فقط).",
        lock: true,
        pickOne: false,
      },
      client: {
        level: "Client: وصول إلى لوحة العميل للخدمات الإضافية فقط.",
        dashboards: "سيتم تعيين لوحة العميل للخدمات الإضافية تلقائيًا عند الحفظ.",
        lock: true,
        pickOne: false,
      },
    };

    function applyUserSingleSelectionRule(changedInput) {
      if ((levelSelect.value || "") !== "user") {
        return;
      }
      if (!changedInput || !changedInput.checked) {
        return;
      }
      dashboardChecks.forEach((input) => {
        if (input !== changedInput) {
          input.checked = false;
        }
      });
    }

    function applyHints() {
      const selectedLevel = (levelSelect.value || "").trim().toLowerCase();
      const cfg = hints[selectedLevel] || {
        level: "اختر مستوى الصلاحية لتظهر القاعدة التشغيلية.",
        dashboards: "اختر اللوحات المناسبة حسب المستوى.",
        lock: false,
        pickOne: false,
      };

      if (levelHint) {
        levelHint.textContent = cfg.level;
      }
      if (dashboardsHint) {
        dashboardsHint.textContent = cfg.dashboards;
      }

      dashboardChecks.forEach((input) => {
        input.disabled = !!cfg.lock;
      });

      if (cfg.pickOne) {
        const checked = dashboardChecks.filter((input) => input.checked);
        if (checked.length > 1) {
          checked.slice(1).forEach((input) => {
            input.checked = false;
          });
        }
      }
    }

    dashboardChecks.forEach((input) => {
      input.addEventListener("change", () => {
        applyUserSingleSelectionRule(input);
      });
    });
    levelSelect.addEventListener("change", applyHints);
    applyHints();
  }

  function updateQueryString(section) {
    const url = new URL(window.location.href);
    url.searchParams.set("section", section);
    window.history.replaceState({}, "", url.toString());
  }

  function toggleSection(section) {
    const views = Array.from(document.querySelectorAll("[data-section-view]"));
    if (!views.length) {
      return;
    }
    views.forEach((view) => {
      const shouldShow = view.getAttribute("data-section-view") === section;
      view.classList.toggle("hidden", !shouldShow);
    });

    document.querySelectorAll("[data-section-link]").forEach((link) => {
      link.classList.toggle("active", link.getAttribute("data-section-link") === section);
    });

    const reportsCards = [
      document.getElementById("reportsFiltersCard"),
      document.getElementById("reportsExportCard"),
    ];
    reportsCards.forEach((card) => {
      if (!card) {
        return;
      }
      card.classList.toggle("hidden", section !== "reports");
    });

    if (section === "reports") {
      animateCounters();
      fillMetricBars(document.querySelector("[data-section-view='reports']"));
    }
    updateQueryString(section);
  }

  function setupSectionTabs() {
    const links = Array.from(document.querySelectorAll("[data-section-link]"));
    if (!links.length) {
      return;
    }
    links.forEach((link) => {
      link.addEventListener("click", (event) => {
        event.preventDefault();
        const section = link.getAttribute("data-section-link") || "access";
        toggleSection(section);
      });
    });
    toggleSection(state.section || "access");
  }

  function setupExportButtons() {
    document.querySelectorAll(".export-btn").forEach((btn) => {
      btn.addEventListener("click", () => {
        btn.classList.add("loading");
        btn.setAttribute("aria-busy", "true");
        window.setTimeout(() => {
          btn.classList.remove("loading");
          btn.removeAttribute("aria-busy");
        }, 1200);
      });
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    closeAlerts();
    setupSectionTabs();
    setupAccessFilters();
    setupAccessLevelHints();
    setupExportButtons();
    if ((state.section || "") !== "reports") {
      animateCounters();
      fillMetricBars();
    }
  });
})();

