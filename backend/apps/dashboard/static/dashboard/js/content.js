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
        const inputName = String(input.name || "");
        const specsName = inputName.includes("design_file")
          ? inputName.replace("design_file", "file_specs")
          : "file_specs";
        let specs = form.querySelector("input[name='" + specsName + "']");
        if (!specs) {
          const card = input.closest(".first-time-media-card");
          if (card) {
            specs = card.querySelector("input[name$='file_specs']");
          }
        }
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
        const ok = window.confirm("سيتم إغلاق البلاغ مع حذف/إخفاء المحتوى محل الشكوى. هل تريد المتابعة؟");
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
        btn.classList.add("is-loading");
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

  function setupAssigneeFilterByTeam() {
    const form = document.getElementById("contentReviewsActionForm");
    if (!form) {
      return;
    }

    const teamSelect = form.querySelector("select[name='assigned_team']");
    const assigneeSelect = form.querySelector("select[name='assigned_to']");
    const state = window.contentDashboardState || {};
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

  function scrollSelectedRow() {
    const row = document.querySelector(".support-row.active-ticket");
    if (!row) {
      return;
    }
    row.scrollIntoView({ block: "center", behavior: "smooth" });
  }

  function setupTeamPanels() {
    const storageKey = "dashboard.content.selectedTeamPanel";
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
        const isActive = panel.dataset.teamPanel === teamKey;
        panel.classList.toggle("active", isActive);
        panel.hidden = !isActive;
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

  function setupDesignPreview(config) {
    const form = document.getElementById(config.formId);
    if (!form) {
      return;
    }

    const fileInput = form.querySelector("input[type='file'][name='design_file']");
    const previewBtn = document.getElementById(config.previewBtnId);
    const previewWrap = document.getElementById(config.previewWrapId);
    const placeholder = document.getElementById(config.placeholderId);
    const appPreviewWrap = document.getElementById(config.appPreviewWrapId);
    const appPlaceholder = document.getElementById(config.appPlaceholderId);
    if (!fileInput || !previewBtn || !previewWrap || !placeholder) {
      return;
    }

    function clearPreview() {
      previewWrap.innerHTML = "";
      previewWrap.hidden = true;
      placeholder.hidden = false;
    }

    function setAppPlaceholderVisibility(hidden) {
      if (appPlaceholder) {
        appPlaceholder.hidden = hidden;
      }
    }

    function renderForContainer(target) {
      const file = fileInput.files && fileInput.files[0];
      if (!file || !target) {
        return false;
      }

      const objectUrl = URL.createObjectURL(file);
      target.innerHTML = "";

      const isVideo = /^video\//i.test(file.type || "");
      if (isVideo) {
        const video = document.createElement("video");
        video.controls = true;
        video.preload = "metadata";
        video.src = objectUrl;
        target.appendChild(video);
      } else {
        const image = document.createElement("img");
        image.alt = "معاينة التصميم الجديد";
        image.src = objectUrl;
        target.appendChild(image);
      }
      return true;
    }

    function renderPreview() {
      const file = fileInput.files && fileInput.files[0];
      if (!file) {
        clearPreview();
        return;
      }

      renderForContainer(previewWrap);
      if (appPreviewWrap) {
        renderForContainer(appPreviewWrap);
        appPreviewWrap.hidden = false;
      }
      setAppPlaceholderVisibility(true);

      previewWrap.hidden = false;
      placeholder.hidden = true;
    }

    previewBtn.addEventListener("click", renderPreview);
    fileInput.addEventListener("change", () => {
      clearPreview();
      setAppPlaceholderVisibility(!appPreviewWrap || !appPreviewWrap.innerHTML);
    });
  }

  function setupFirstTimeDesignPreview() {
    const form = document.getElementById("contentFirstTimeMediaForm");
    if (!form) {
      return;
    }

    const entries = [
      {
        inputName: "intro_design_file",
        uploadPreviewId: "contentFirstTimeSlide1UploadPreview",
        uploadPlaceholderId: "contentFirstTimeSlide1UploadPlaceholder",
        slidePreviewId: "contentFirstTime01MediaPreview",
        slidePlaceholderId: "contentFirstTime01MediaPlaceholder",
        alt: "وسائط الشريحة الأولى",
      },
      {
        inputName: "client_design_file",
        uploadPreviewId: "contentFirstTimeSlide2UploadPreview",
        uploadPlaceholderId: "contentFirstTimeSlide2UploadPlaceholder",
        slidePreviewId: "contentFirstTime02MediaPreview",
        slidePlaceholderId: "contentFirstTime02MediaPlaceholder",
        alt: "وسائط الشريحة الثانية",
      },
      {
        inputName: "provider_design_file",
        uploadPreviewId: "contentFirstTimeSlide3UploadPreview",
        uploadPlaceholderId: "contentFirstTimeSlide3UploadPlaceholder",
        slidePreviewId: "contentFirstTime03MediaPreview",
        slidePlaceholderId: "contentFirstTime03MediaPlaceholder",
        alt: "وسائط الشريحة الثالثة",
      },
    ];

    function renderFile(target, file, alt) {
      if (!target || !file) {
        return false;
      }

      const objectUrl = URL.createObjectURL(file);
      target.innerHTML = "";
      if (/^video\//i.test(file.type || "")) {
        const video = document.createElement("video");
        video.controls = true;
        video.preload = "metadata";
        video.src = objectUrl;
        target.appendChild(video);
      } else {
        const image = document.createElement("img");
        image.alt = alt;
        image.src = objectUrl;
        target.appendChild(image);
      }
      target.hidden = false;
      return true;
    }

    entries.forEach((entry) => {
      const input = form.querySelector("input[name='" + entry.inputName + "']");
      const uploadPreview = document.getElementById(entry.uploadPreviewId);
      const uploadPlaceholder = document.getElementById(entry.uploadPlaceholderId);
      const slidePreview = document.getElementById(entry.slidePreviewId);
      const slidePlaceholder = document.getElementById(entry.slidePlaceholderId);
      if (!input) {
        return;
      }

      input.addEventListener("change", () => {
        const file = input.files && input.files[0];
        if (!file) {
          return;
        }

        if (renderFile(uploadPreview, file, entry.alt) && uploadPlaceholder) {
          uploadPlaceholder.hidden = true;
        }
        if (renderFile(slidePreview, file, entry.alt) && slidePlaceholder) {
          slidePlaceholder.hidden = true;
        }
      });
    });
  }

  function setupIntroDesignPreview() {
    setupDesignPreview({
      formId: "contentIntroForm",
      previewBtnId: "contentIntroPreviewBtn",
      previewWrapId: "contentIntroDesignPreview",
      placeholderId: "contentIntroDesignPlaceholder",
      appPreviewWrapId: "contentIntroAppMediaPreview",
      appPlaceholderId: "contentIntroAppMediaPlaceholder",
    });
  }

  function setupFirstTimeTextLivePreview() {
    const bindings = [
      { input: "intro_title", target: "previewSlide1Title" },
      { input: "intro_body", target: "previewSlide1Body" },
      { input: "client_title", target: "previewSlide2Title" },
      { input: "client_body", target: "previewSlide2Body" },
      { input: "provider_title", target: "previewSlide3Title" },
      { input: "provider_body", target: "previewSlide3Body" },
    ];

    bindings.forEach((entry) => {
      const source = document.querySelector("[name='" + entry.input + "']");
      const target = document.getElementById(entry.target);
      if (!source || !target) {
        return;
      }

      const update = function () {
        const value = (source.value || "").trim();
        target.textContent = value || "-";
      };
      source.addEventListener("input", update);
      update();
    });
  }

  function setupContentSettingsPanels() {
    const switchRoot = document.getElementById("contentSettingsSwitch");
    if (!switchRoot) {
      return;
    }

    const buttons = Array.from(switchRoot.querySelectorAll(".settings-switch-btn[data-target]"));
    if (!buttons.length) {
      return;
    }

    const panels = buttons
      .map((btn) => document.getElementById(btn.dataset.target || ""))
      .filter(Boolean);
    if (!panels.length) {
      return;
    }

    function activate(targetId) {
      buttons.forEach((btn) => {
        const isActive = btn.dataset.target === targetId;
        btn.classList.toggle("active", isActive);
        btn.setAttribute("aria-selected", isActive ? "true" : "false");
      });

      panels.forEach((panel) => {
        const isActive = panel.id === targetId;
        panel.classList.toggle("active", isActive);
        panel.hidden = !isActive;
      });
    }

    buttons.forEach((btn) => {
      btn.addEventListener("click", () => {
        const targetId = btn.dataset.target || "";
        if (!targetId) {
          return;
        }
        activate(targetId);
      });
    });

    const initial = switchRoot.dataset.initialTarget || buttons[0].dataset.target || "";
    if (initial) {
      activate(initial);
    }
  }

  function setupContentSettingsLegalPreview() {
    const form = document.getElementById("contentSettingsLegalForm");
    const previewBtn = document.getElementById("contentSettingsLegalPreviewBtn");
    const previewWrap = document.getElementById("contentSettingsLegalPreviewWrap");
    const hint = document.getElementById("legalPreviewHint");
    if (!form || !previewBtn || !previewWrap) {
      return;
    }

    const fileInput = form.querySelector("input[name='file']");
    if (!fileInput) {
      return;
    }

    function showHint(message) {
      if (hint) {
        hint.textContent = message;
      }
    }

    function clearPreview() {
      previewWrap.innerHTML = "";
      previewWrap.hidden = true;
    }

    function renderPreview() {
      const file = fileInput.files && fileInput.files[0];
      if (!file) {
        clearPreview();
        showHint("لم يتم اختيار ملف بعد. يمكنك الحفظ بالنص فقط أو اختيار ملف ثم المعاينة.");
        return;
      }

      const objectUrl = URL.createObjectURL(file);
      const mime = (file.type || "").toLowerCase();
      const extension = (file.name.split(".").pop() || "").toLowerCase();

      previewWrap.innerHTML = "";

      if (mime.includes("image/") || ["png", "jpg", "jpeg", "webp", "gif", "bmp", "svg"].includes(extension)) {
        const image = document.createElement("img");
        image.alt = "معاينة الملف المحدد";
        image.src = objectUrl;
        previewWrap.appendChild(image);
        previewWrap.hidden = false;
        showHint("هذه معاينة الملف قبل الحفظ. لن يظهر للعميل إلا بعد الضغط على حفظ.");
        return;
      }

      if (mime.includes("pdf") || extension === "pdf") {
        const frame = document.createElement("iframe");
        frame.src = objectUrl;
        frame.title = "معاينة ملف PDF";
        previewWrap.appendChild(frame);
        previewWrap.hidden = false;
        showHint("تمت معاينة PDF محليًا قبل الحفظ.");
        return;
      }

      const fileRow = document.createElement("div");
      fileRow.className = "preview-file-row";
      const title = document.createElement("strong");
      title.textContent = file.name;
      const link = document.createElement("a");
      link.href = objectUrl;
      link.target = "_blank";
      link.rel = "noopener";
      link.textContent = "فتح الملف";
      fileRow.appendChild(title);
      fileRow.appendChild(link);
      previewWrap.appendChild(fileRow);
      previewWrap.hidden = false;
      showHint("نوع الملف لا يدعم معاينة داخلية كاملة، ويمكن فتحه في تبويب جديد.");
    }

    previewBtn.addEventListener("click", renderPreview);
    fileInput.addEventListener("change", () => {
      clearPreview();
      showHint("تم اختيار ملف جديد. اضغط معاينة الملف المحدد لعرضه قبل الحفظ.");
    });
  }

  function escapeHtml(value) {
    return String(value || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/\"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  function setupContentExcellenceDashboard() {
    const state = window.contentExcellenceState || {};
    if (!state.apiUrl) {
      return;
    }

    const tabRoot = document.getElementById("excellenceTabs");
    const searchForm = document.getElementById("contentExcellenceFiltersForm");
    const searchInput = document.getElementById("excellenceSearchInput");
    const clearBtn = document.getElementById("excellenceClearFiltersBtn");
    const rowsBody = document.getElementById("contentExcellenceRowsBody");
    const totalRows = document.getElementById("excellenceTotalRows");
    const cycleEnd = document.getElementById("excellenceCycleEnd");
    const exportPdf = document.getElementById("excellenceExportPdf");
    const exportXlsx = document.getElementById("excellenceExportXlsx");
    const exportCsv = document.getElementById("excellenceExportCsv");
    if (!tabRoot || !searchForm || !searchInput || !clearBtn || !rowsBody) {
      return;
    }

    const tabButtons = Array.from(tabRoot.querySelectorAll(".excellence-tab[data-badge]"));
    let selectedBadge = (state.badgeFilter || "").trim();
    let searchQuery = (state.query || "").trim();
    let isLoading = false;

    function setActiveTab() {
      tabButtons.forEach((btn) => {
        const isActive = (btn.dataset.badge || "") === selectedBadge;
        btn.classList.toggle("active", isActive);
        btn.setAttribute("aria-selected", isActive ? "true" : "false");
      });
    }

    function updateExportLinks() {
      const params = new URLSearchParams();
      if (selectedBadge) {
        params.set("badge", selectedBadge);
      }
      if (searchQuery) {
        params.set("q", searchQuery);
      }

      function setLink(anchor, format) {
        if (!anchor) {
          return;
        }
        const linkParams = new URLSearchParams(params);
        linkParams.set("export", format);
        anchor.href = state.exportBaseUrl + "?" + linkParams.toString();
      }

      setLink(exportPdf, "pdf");
      setLink(exportXlsx, "xlsx");
      setLink(exportCsv, "csv");
    }

    function pushStateUrl() {
      const params = new URLSearchParams();
      if (selectedBadge) {
        params.set("badge", selectedBadge);
      }
      if (searchQuery) {
        params.set("q", searchQuery);
      }
      const queryString = params.toString();
      const next = queryString ? state.exportBaseUrl + "?" + queryString : state.exportBaseUrl;
      window.history.replaceState({}, "", next);
    }

    function renderRows(rows) {
      if (!Array.isArray(rows) || !rows.length) {
        rowsBody.innerHTML = '<tr><td colspan="8">لا توجد بيانات مرشحين ضمن الفلاتر الحالية.</td></tr>';
        return;
      }

      const html = rows.map((row) => {
        const rating = Number(row.rating_avg || 0).toFixed(2);
        return (
          "<tr>"
          + "<td>" + escapeHtml(row.provider_name || "-") + "</td>"
          + "<td>" + escapeHtml(row.rank_position || "-") + "</td>"
          + "<td>" + escapeHtml(row.followers_count || 0) + "</td>"
          + "<td>" + escapeHtml(row.completed_orders_count || 0) + "</td>"
          + "<td>" + escapeHtml(rating) + " / 5 (" + escapeHtml(row.rating_count || 0) + ")</td>"
          + "<td>" + escapeHtml(row.subcategory_name || "-") + "</td>"
          + "<td>" + escapeHtml(row.category_name || "-") + "</td>"
          + "<td>" + escapeHtml(row.badge_name || "-") + "</td>"
          + "</tr>"
        );
      }).join("");
      rowsBody.innerHTML = html;
    }

    function renderBadgeCounts(tabs) {
      if (!Array.isArray(tabs)) {
        return;
      }
      tabs.forEach((tab) => {
        const countNode = document.querySelector('[data-badge-count="' + (tab.code || "") + '"]');
        if (countNode) {
          countNode.textContent = String(tab.count || 0);
        }
      });
    }

    async function refreshData() {
      if (isLoading) {
        return;
      }
      isLoading = true;
      rowsBody.innerHTML = '<tr><td colspan="8">جاري تحميل بيانات التميز...</td></tr>';

      const apiUrl = new URL(state.apiUrl, window.location.origin);
      if (selectedBadge) {
        apiUrl.searchParams.set("badge", selectedBadge);
      }
      if (searchQuery) {
        apiUrl.searchParams.set("q", searchQuery);
      }

      try {
        const response = await window.fetch(apiUrl.toString(), {
          headers: {
            "X-Requested-With": "XMLHttpRequest",
          },
          credentials: "same-origin",
        });
        if (!response.ok) {
          throw new Error("تعذر تحميل بيانات لوحة التميز");
        }

        const payload = await response.json();
        renderRows(payload.rows || []);
        renderBadgeCounts(payload.badge_tabs || []);
        if (totalRows) {
          totalRows.textContent = String(payload.total_rows || 0);
        }
        if (cycleEnd && payload.cycle_end) {
          cycleEnd.textContent = String(payload.cycle_end);
        }
        updateExportLinks();
        setActiveTab();
        pushStateUrl();
      } catch (_) {
        rowsBody.innerHTML = '<tr><td colspan="8">تعذر تحميل البيانات الآن. حاول مرة أخرى.</td></tr>';
      } finally {
        isLoading = false;
      }
    }

    tabButtons.forEach((btn) => {
      btn.addEventListener("click", () => {
        selectedBadge = (btn.dataset.badge || "").trim();
        refreshData();
      });
    });

    searchForm.addEventListener("submit", (event) => {
      event.preventDefault();
      searchQuery = (searchInput.value || "").trim();
      refreshData();
    });

    clearBtn.addEventListener("click", () => {
      selectedBadge = "";
      searchQuery = "";
      searchInput.value = "";
      refreshData();
    });

    searchInput.value = searchQuery;
    updateExportLinks();
    setActiveTab();
    refreshData();
  }

  document.addEventListener("DOMContentLoaded", () => {
    attachCharCounters();
    updateFileSpecs();
    setupReviewFormConfirmations();
    setupLiveTableSearch();
    setupAssigneeFilterByTeam();
    scrollSelectedRow();
    setupTeamPanels();
    setupFirstTimeDesignPreview();
    setupIntroDesignPreview();
    setupFirstTimeTextLivePreview();
    setupContentSettingsPanels();
    setupContentSettingsLegalPreview();
    setupContentExcellenceDashboard();
  });
})();
