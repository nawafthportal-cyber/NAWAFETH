(function () {
  "use strict";

  const state = window.dashboardPageState || { section: "access" };

  function formatNumber(value, decimals) {
    const numeric = Number(value);
    if (!Number.isFinite(numeric)) {
      return String(value || "0");
    }
    return new Intl.NumberFormat("ar-SA", {
      minimumFractionDigits: decimals || 0,
      maximumFractionDigits: decimals || 0,
    }).format(numeric);
  }

  function animateValue(node) {
    const rawText = (node.textContent || "").replace(/,/g, "").trim();
    const target = Number(rawText);
    if (!Number.isFinite(target)) {
      return;
    }
    const decimals = rawText.includes(".") ? Math.min(2, (rawText.split(".")[1] || "").length) : 0;
    const duration = 700;
    const start = performance.now();
    function tick(now) {
      const progress = Math.min(1, (now - start) / duration);
      const current = target * progress;
      node.textContent = formatNumber(progress < 1 ? current : target, decimals);
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

    const reportLists = (scope || document).querySelectorAll("[data-report-list]");
    reportLists.forEach((group) => {
      const valueNodes = Array.from(group.querySelectorAll(".admin-report-item__value"));
      if (!valueNodes.length) {
        return;
      }
      const numbers = valueNodes
        .map((node) => Number((node.textContent || "").replace(/,/g, "").trim()))
        .filter((num) => Number.isFinite(num));
      const max = Math.max(1, ...numbers);
      Array.from(group.querySelectorAll(".admin-report-item")).forEach((itemNode) => {
        const valueNode = itemNode.querySelector(".admin-report-item__value");
        const bar = itemNode.querySelector("[data-bar-fill]");
        if (!valueNode || !bar) {
          return;
        }
        const value = Number((valueNode.textContent || "").replace(/,/g, "").trim());
        const ratio = Number.isFinite(value) ? Math.max(6, Math.round((value / max) * 100)) : 0;
        window.setTimeout(() => {
          bar.style.width = ratio + "%";
        }, 120);
      });
    });
  }

  /* closeAlerts — handled globally by _base.html toast system */

  function showToast(message, type, duration) {
    if (!message) {
      return;
    }
    if (window.NwToast && typeof window.NwToast.show === "function") {
      window.NwToast.show(message, type || "info", duration || 4500);
      return;
    }
    window.alert(message);
  }

  function applyAccessFilters() {
    const search = document.getElementById("accessSearch");
    const level = document.getElementById("levelFilter");
    const rows = Array.from(document.querySelectorAll("#accessTable tbody tr"));
    const countNode = document.getElementById("accessFilterCount");
    if (!rows.length || !search || !level) {
      return;
    }

    const searchValue = (search.value || "").trim().toLowerCase();
    const levelValue = (level.value || "").trim().toLowerCase();
    let visibleCount = 0;
    let emptyRow = document.getElementById("accessTableEmptyState");

    function ensureEmptyRow() {
      if (emptyRow) {
        return emptyRow;
      }
      const tbody = document.querySelector("#accessTable tbody");
      if (!tbody) {
        return null;
      }
      emptyRow = document.createElement("tr");
      emptyRow.id = "accessTableEmptyState";
      emptyRow.className = "admin-control-empty-row hidden";
      emptyRow.innerHTML = "<td colspan='8'>لا توجد نتائج مطابقة للفلاتر الحالية. جرّب تعديل البحث أو مستوى الصلاحية.</td>";
      tbody.appendChild(emptyRow);
      return emptyRow;
    }

    rows.forEach((row) => {
      if (!row.dataset.username) {
        return;
      }
      const haystack = [row.dataset.username, row.dataset.mobile, row.dataset.dashboard, row.dataset.level, row.dataset.permissions]
        .join(" ")
        .toLowerCase();
      const levelOk = !levelValue || row.dataset.level === levelValue;
      const searchOk = !searchValue || haystack.indexOf(searchValue) >= 0;
      if (levelOk && searchOk) {
        visibleCount += 1;
      }
      row.classList.toggle("dim", !(levelOk && searchOk));
      row.style.display = levelOk && searchOk ? "" : "none";
    });

    if (countNode) {
      countNode.textContent = "عرض " + formatNumber(visibleCount) + " حساب";
    }

    const emptyStateRow = ensureEmptyRow();
    if (emptyStateRow) {
      emptyStateRow.classList.toggle("hidden", visibleCount > 0);
    }
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

  function setupAccessFormExperience() {
    const form = document.getElementById("accessForm");
    if (!form) {
      return;
    }

    const levelSelect = form.querySelector("select[name='level']");
    const dashboardChecks = Array.from(form.querySelectorAll("input[name='dashboards']"));
    const permissionChecks = Array.from(form.querySelectorAll("input[name='permissions']"));
    const profileIdInput = form.querySelector("input[name='profile_id']");
    if (!levelSelect || !dashboardChecks.length) {
      return;
    }

    const manualDashboardSelection = new Set(
      dashboardChecks.filter((input) => input.checked).map((input) => input.value)
    );
    const manualPermissionSelection = new Set(
      permissionChecks.filter((input) => input.checked).map((input) => input.value)
    );

    const hints = {
      admin: {
        level: "Admin: صلاحية كاملة على جميع اللوحات وجميع العمليات.",
        dashboards: "سيتم منح جميع اللوحات الداخلية تلقائيًا عند الحفظ.",
        permissions: "كل الصلاحيات الدقيقة تُمنح تلقائيًا ولا تحتاج اختيارًا يدويًا.",
        lockDashboards: true,
        pickOne: false,
        autoDashboard(value) {
          return value !== "client_extras";
        },
      },
      power: {
        level: "Power User: يمكنه العمل على لوحة واحدة أو أكثر بكامل العمليات.",
        dashboards: "اختر لوحة واحدة على الأقل.",
        permissions: "الصلاحيات الدقيقة تمنح تلقائيًا حسب اللوحات المحددة لهذا المستوى.",
        lockDashboards: false,
        pickOne: false,
        autoDashboard() {
          return false;
        },
      },
      user: {
        level: "User: يعمل على لوحة واحدة فقط وضمن نطاق الطلبات المكلف بها.",
        dashboards: "اختر لوحة تحكم واحدة فقط.",
        permissions: "ستظهر فقط الصلاحيات التابعة للوحة المختارة ويمكنك تخصيصها بدقة.",
        lockDashboards: false,
        pickOne: true,
        autoDashboard() {
          return false;
        },
      },
      qa: {
        level: "QA: وصول لجميع اللوحات بدون صلاحيات تنفيذ (قراءة فقط).",
        dashboards: "سيتم منح جميع اللوحات الداخلية تلقائيًا (قراءة فقط).",
        permissions: "هذا المستوى لا يمنح صلاحيات تنفيذ، لذلك يتم تعطيل الصلاحيات الدقيقة.",
        lockDashboards: true,
        pickOne: false,
        autoDashboard(value) {
          return value !== "client_extras";
        },
      },
      client: {
        level: "Client: وصول إلى لوحة العميل للخدمات الإضافية فقط.",
        dashboards: "سيتم تعيين لوحة العميل للخدمات الإضافية تلقائيًا عند الحفظ.",
        permissions: "هذا المستوى لا يستخدم صلاحيات تشغيل داخلية.",
        lockDashboards: true,
        pickOne: false,
        autoDashboard(value) {
          return value === "client_extras";
        },
      },
    };

    function getConfig(selectedLevel) {
      return hints[selectedLevel] || {
        level: "اختر مستوى الصلاحية لتظهر القاعدة التشغيلية.",
        dashboards: "اختر اللوحات المناسبة حسب المستوى.",
        permissions: "تتحدث الصلاحيات الدقيقة بعد اختيار المستوى واللوحات.",
        lockDashboards: false,
        pickOne: false,
        autoDashboard() {
          return false;
        },
      };
    }

    function getSelectedDashboardInputs() {
      return dashboardChecks.filter((input) => input.checked);
    }

    function getSelectedPermissionInputs() {
      return permissionChecks.filter((input) => input.checked);
    }

    function permissionDashboardCode(input) {
      return String((input && input.value) || "").split(".")[0].trim().toLowerCase();
    }

    function ensureRuntimeMessage(fieldShell) {
      if (!fieldShell) {
        return null;
      }
      let node = fieldShell.querySelector(".field-runtime-message");
      if (!node) {
        node = document.createElement("small");
        node.className = "field-runtime-message";
        fieldShell.appendChild(node);
      }
      return node;
    }

    function setFieldState(name, message, stateName) {
      const fieldShell = form.querySelector("[data-field-name='" + name + "']");
      if (!fieldShell) {
        return;
      }
      fieldShell.classList.toggle("is-invalid", stateName === "error");
      fieldShell.classList.toggle("is-warning", stateName === "warning");
      const runtimeMessage = ensureRuntimeMessage(fieldShell);
      if (!runtimeMessage) {
        return;
      }
      runtimeMessage.textContent = message || "";
      runtimeMessage.hidden = !message;
    }

    function syncManualDashboardSelection() {
      manualDashboardSelection.clear();
      dashboardChecks.forEach((input) => {
        if (input.checked) {
          manualDashboardSelection.add(input.value);
        }
      });
    }

    function applyDashboardRules(selectedLevel) {
      const cfg = getConfig(selectedLevel);
      dashboardChecks.forEach((input) => {
        const label = input.closest("label");
        if (cfg.lockDashboards) {
          input.checked = !!cfg.autoDashboard(input.value);
        } else {
          input.checked = manualDashboardSelection.has(input.value);
        }
        input.disabled = !!cfg.lockDashboards;
        if (label) {
          label.classList.toggle("is-disabled", !!cfg.lockDashboards);
        }
      });

      if (cfg.pickOne) {
        const checkedInputs = getSelectedDashboardInputs();
        if (checkedInputs.length > 1) {
          checkedInputs.slice(1).forEach((input) => {
            input.checked = false;
          });
        }
      }

      syncManualDashboardSelection();
    }

    function applyPermissionRules(selectedLevel) {
      if (!permissionChecks.length) {
        return;
      }
      const selectedDashboardCodes = new Set(
        getSelectedDashboardInputs().map((input) => String(input.value || "").trim().toLowerCase())
      );

      permissionChecks.forEach((input) => {
        const label = input.closest("label");
        const scopedDashboard = permissionDashboardCode(input);
        const allowedForUser = selectedDashboardCodes.has(scopedDashboard);

        if (selectedLevel === "admin" || selectedLevel === "power") {
          input.checked = true;
          input.disabled = true;
          if (label) {
            label.hidden = false;
            label.classList.add("is-disabled");
          }
          return;
        }

        if (selectedLevel === "qa" || selectedLevel === "client") {
          input.checked = false;
          input.disabled = true;
          if (label) {
            label.hidden = false;
            label.classList.add("is-disabled");
          }
          return;
        }

        const allowed = selectedLevel === "user" ? allowedForUser : true;
        input.disabled = !allowed;
        input.checked = allowed && manualPermissionSelection.has(input.value);
        if (label) {
          label.hidden = selectedLevel === "user" && selectedDashboardCodes.size > 0 && !allowed;
          label.classList.toggle("is-disabled", !allowed);
        }
      });

    }

    function validateUsername() {
      const input = form.querySelector("input[name='username']");
      const value = String((input && input.value) || "").trim();
      const normalized = value.replace(/_/g, "");
      if (!value) {
        return "اسم المستخدم مطلوب.";
      }
      if (normalized.length < 8 || !/^[a-z0-9_]+$/i.test(value)) {
        return "اسم المستخدم يجب أن يكون 8 أحرف أو أرقام على الأقل وبدون رموز.";
      }
      return "";
    }

    function isCreatingNewProfile() {
      const profileIdValue = String((profileIdInput && profileIdInput.value) || "").trim();
      return !profileIdValue;
    }

    function validateMobile() {
      const input = form.querySelector("input[name='mobile_number']");
      const normalized = String((input && input.value) || "").trim().replace(/[\s-]/g, "");
      if (!normalized) {
        return "رقم الجوال مطلوب.";
      }
      if (!/^\d+$/.test(normalized)) {
        return "رقم الجوال يجب أن يحتوي أرقامًا فقط.";
      }
      if (isCreatingNewProfile() && !/^05\d{8}$/.test(normalized)) {
        return "رقم الجوال يجب أن يتكون من 10 خانات ويبدأ بـ 05.";
      }
      if (!isCreatingNewProfile() && normalized.length < 9) {
        return "رقم الجوال غير صالح.";
      }
      return "";
    }

    function validatePassword() {
      const input = form.querySelector("input[name='password']");
      const value = String((input && input.value) || "").trim();
      const profileIdValue = String((profileIdInput && profileIdInput.value) || "").trim();
      if (!value && !profileIdValue) {
        return "كلمة المرور مطلوبة عند إنشاء حساب جديد.";
      }
      if (!value) {
        return "";
      }
      if (value.length < 8 || !/[A-Za-z\u0600-\u06FF]/.test(value) || !/\d/.test(value)) {
        return "كلمة المرور يجب أن تكون 8 أحرف على الأقل وتحتوي على حروف وأرقام.";
      }
      return "";
    }

    function validateDashboards(selectedLevel) {
      const count = getSelectedDashboardInputs().length;
      if (selectedLevel === "power" && count < 1) {
        return "مستوى Power User يتطلب اختيار لوحة واحدة على الأقل.";
      }
      if (selectedLevel === "user" && count !== 1) {
        return "مستوى User يتطلب اختيار لوحة تحكم واحدة فقط.";
      }
      return "";
    }

    function validatePermissions(selectedLevel) {
      if (!permissionChecks.length) {
        return "";
      }
      if (selectedLevel !== "user") {
        return "";
      }
      const allowedDashboardCodes = new Set(
        getSelectedDashboardInputs().map((input) => String(input.value || "").trim().toLowerCase())
      );
      const invalidSelections = getSelectedPermissionInputs().filter((input) => !allowedDashboardCodes.has(permissionDashboardCode(input)));
      if (invalidSelections.length) {
        return "بعض الصلاحيات المختارة لا تنتمي إلى اللوحة المحددة.";
      }
      return "";
    }

    function refreshFormState() {
      const selectedLevel = (levelSelect.value || "").trim().toLowerCase();

      applyDashboardRules(selectedLevel);
      applyPermissionRules(selectedLevel);

      const errors = [];

      const usernameError = validateUsername();
      const mobileError = validateMobile();
      const passwordError = validatePassword();
      const dashboardsError = validateDashboards(selectedLevel);
      const permissionsError = validatePermissions(selectedLevel);

      setFieldState("username", usernameError, usernameError ? "error" : "");
      setFieldState("mobile_number", mobileError, mobileError ? "error" : "");
      setFieldState("password", passwordError, passwordError ? "error" : "");
      setFieldState("dashboards", dashboardsError, dashboardsError ? "error" : "");
      setFieldState("permissions", permissionsError, permissionsError ? "error" : "");

      [usernameError, mobileError, passwordError, dashboardsError, permissionsError].forEach((message) => {
        if (message) {
          errors.push(message);
        }
      });

      return { errors };
    }

    dashboardChecks.forEach((input) => {
      input.addEventListener("change", () => {
        if ((levelSelect.value || "").trim().toLowerCase() === "user" && input.checked) {
          dashboardChecks.forEach((otherInput) => {
            if (otherInput !== input) {
              otherInput.checked = false;
            }
          });
        }
        syncManualDashboardSelection();
        refreshFormState();
      });
    });

    permissionChecks.forEach((input) => {
      input.addEventListener("change", () => {
        if ((levelSelect.value || "").trim().toLowerCase() === "user") {
          if (input.checked) {
            manualPermissionSelection.add(input.value);
          } else {
            manualPermissionSelection.delete(input.value);
          }
        }
        refreshFormState();
      });
    });

    ["username", "mobile_number", "password"].forEach((fieldName) => {
      const input = form.querySelector("[name='" + fieldName + "']");
      if (!input) {
        return;
      }
      if (fieldName === "mobile_number") {
        input.addEventListener("input", () => {
          if (!isCreatingNewProfile()) {
            refreshFormState();
            return;
          }
          const digitsOnly = String(input.value || "").replace(/\D/g, "").slice(0, 10);
          if (input.value !== digitsOnly) {
            input.value = digitsOnly;
          }
          refreshFormState();
        });
        return;
      }
      input.addEventListener("input", refreshFormState);
    });

    levelSelect.addEventListener("change", refreshFormState);

    form.addEventListener("submit", (event) => {
      const validationState = refreshFormState();
      if (validationState.errors.length) {
        event.preventDefault();
        validationState.errors.slice(0, 3).forEach((message) => {
          showToast(message, "error", 5200);
        });
      }
    });

    form.addEventListener("access-form-reset", () => {
      manualDashboardSelection.clear();
      manualPermissionSelection.clear();
      refreshFormState();
    });

    refreshFormState();
  }

  function surfaceServerFormErrors() {
    const form = document.getElementById("accessForm");
    if (!form) {
      return;
    }
    const messages = Array.from(form.querySelectorAll("[data-field-error]"))
      .map((node) => (node.textContent || "").trim())
      .filter(Boolean);
    Array.from(new Set(messages))
      .slice(0, 4)
      .forEach((message) => {
        showToast(message, "error", 5200);
      });
  }

  function setupAccessFieldFocus() {
    const form = document.getElementById("accessForm");
    if (!form) {
      return;
    }
    form.querySelectorAll("[data-field-shell] input, [data-field-shell] select").forEach((input) => {
      input.addEventListener("focus", () => {
        const shell = input.closest("[data-field-shell]");
        if (shell) {
          shell.classList.add("is-active");
        }
      });
      input.addEventListener("blur", () => {
        const shell = input.closest("[data-field-shell]");
        if (shell) {
          shell.classList.remove("is-active");
        }
      });
    });
  }

  function setupAccessFormToggle() {
    const shell = document.getElementById("accessFormShell");
    const openBtn = document.getElementById("openAccessFormBtn");
    const closeBtn = document.getElementById("closeAccessFormBtn");
    const cancelBtn = document.getElementById("cancelAccessFormBtn");
    const form = document.getElementById("accessForm");
    if (!shell || !openBtn || !form) {
      return;
    }

    const levelSelect = form.querySelector("select[name='level']");
    const dashboardChecks = Array.from(form.querySelectorAll("input[name='dashboards']"));
    const profileIdInput = form.querySelector("input[name='profile_id']");

    function syncExpandedState() {
      openBtn.setAttribute("aria-expanded", shell.classList.contains("hidden") ? "false" : "true");
    }

    function syncAccessFormQuery(isOpen) {
      const url = new URL(window.location.href);
      url.searchParams.set("section", "access");
      if (isOpen) {
        url.searchParams.set("new", "1");
        url.searchParams.delete("edit");
      } else {
        url.searchParams.delete("new");
        url.searchParams.delete("edit");
      }
      window.history.replaceState({}, "", url.toString());
    }

    function clearFormForNewAccount() {
      form.reset();
      if (profileIdInput) {
        profileIdInput.value = "";
      }
      dashboardChecks.forEach((input) => {
        input.checked = false;
        input.disabled = false;
      });
      Array.from(form.querySelectorAll("input[name='permissions']")).forEach((input) => {
        input.checked = false;
        input.disabled = false;
      });
      if (levelSelect) {
        const firstOption = levelSelect.options[0];
        if (firstOption) {
          levelSelect.value = firstOption.value;
        }
        levelSelect.dispatchEvent(new Event("change", { bubbles: true }));
      }
      form.dispatchEvent(new Event("access-form-reset"));
    }

    function openFormInline() {
      shell.classList.remove("hidden");
      state.accessFormOpen = true;
      state.editingAccessProfile = false;
      state.accessFormHasErrors = false;
      syncExpandedState();
      syncAccessFormQuery(true);
    }

    function closeFormInline() {
      shell.classList.add("hidden");
      clearFormForNewAccount();
      state.accessFormOpen = false;
      state.editingAccessProfile = false;
      state.accessFormHasErrors = false;
      syncExpandedState();
      syncAccessFormQuery(false);
    }

    openBtn.addEventListener("click", (event) => {
      if (state.editingAccessProfile || state.accessFormHasErrors) {
        return;
      }
      event.preventDefault();
      openFormInline();
    });

    [closeBtn, cancelBtn].forEach((btn) => {
      if (!btn) {
        return;
      }
      btn.addEventListener("click", (event) => {
        event.preventDefault();
        closeFormInline();
      });
    });

    if (state.accessFormOpen || state.editingAccessProfile || state.accessFormHasErrors) {
      shell.classList.remove("hidden");
    } else {
      shell.classList.add("hidden");
    }
    syncExpandedState();
  }

  function updateQueryString(section) {
    const url = new URL(window.location.href);
    url.searchParams.set("section", section);
    window.history.replaceState({}, "", url.toString());
  }

  function revealReportCards() {
    const reportsSection = document.querySelector("[data-section-view='reports']");
    if (!reportsSection || reportsSection.classList.contains("hidden")) {
      return;
    }
    const cards = Array.from(reportsSection.querySelectorAll("[data-report-card]"));
    cards.forEach((card, index) => {
      card.classList.remove("is-visible");
      window.setTimeout(() => {
        card.classList.add("is-visible");
      }, 60 * (index + 1));
    });
  }

  function setupReportsPeriodForm() {
    const form = document.getElementById("reportsPeriodForm");
    if (!form) {
      return;
    }
    form.addEventListener("submit", (event) => {
      const start = form.querySelector("input[name='start']");
      const end = form.querySelector("input[name='end']");
      if (!start || !end || !start.value || !end.value) {
        return;
      }
      const startDate = new Date(start.value + "T00:00:00");
      const endDate = new Date(end.value + "T00:00:00");
      if (!Number.isFinite(startDate.getTime()) || !Number.isFinite(endDate.getTime())) {
        return;
      }
      if (startDate.getTime() > endDate.getTime()) {
        event.preventDefault();
        showToast("تاريخ البداية يجب أن يسبق أو يساوي تاريخ النهاية.", "error", 5000);
      }
    });
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
      revealReportCards();
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

  /* setupExportButtons — handled globally by _base.html */

  document.addEventListener("DOMContentLoaded", function () {
    setupSectionTabs();
    setupReportsPeriodForm();
    setupAccessFilters();
    setupAccessFormExperience();
    setupAccessFieldFocus();
    setupAccessFormToggle();
    surfaceServerFormErrors();
    if ((state.section || "") === "reports") {
      revealReportCards();
    } else {
      animateCounters();
      fillMetricBars();
    }
  });
})();
