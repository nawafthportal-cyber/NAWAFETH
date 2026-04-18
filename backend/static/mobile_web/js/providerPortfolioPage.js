"use strict";
var ProviderPortfolioPage = (function () {
  var sections = [];
  var _profile = null;
  var _allViewerItems = [];
  var _providerInfo = { id: 0, display_name: "مزود خدمة", profile_image: "" };
  var _statusTimer = 0;
  var _cachedApi = null;
  var SECTION_FALLBACK_TITLE = "أعمالي";

  function byId(id) {
    return document.getElementById(id);
  }

  /* ── Inline fallback API client ─────────────────────────────
     Uses window.ApiClient when available, otherwise falls back
     to a minimal fetch-based client so the page never fails
     with "تعذر تهيئة الاتصال".                                 */
  function _getToken() {
    if (window.Auth && typeof window.Auth.getAccessToken === 'function') {
      return window.Auth.getAccessToken();
    }
    try {
      return (window.sessionStorage && window.sessionStorage.getItem("nw_access_token"))
        || (window.localStorage && window.localStorage.getItem("nw_access_token"));
    } catch (_) {
      return null;
    }
  }

  function _buildFallbackApi() {
    var BASE = window.location.origin;
    function _req(path, opts) {
      opts = opts || {};
      var url = BASE + path;
      var headers = { "Accept": "application/json" };
      var token = _getToken();
      if (token) headers["Authorization"] = "Bearer " + token;
      var isForm = opts.formData === true || (opts.body instanceof FormData);
      if (opts.body && !isForm) headers["Content-Type"] = "application/json";
      var body;
      if (opts.body) {
        body = isForm ? opts.body : (typeof opts.body === "string" ? opts.body : JSON.stringify(opts.body));
      }
      var controller = new AbortController();
      var tid = opts.timeout ? setTimeout(function () { controller.abort(); }, opts.timeout) : null;
      return fetch(url, { method: opts.method || "GET", headers: headers, body: body, signal: controller.signal })
        .then(function (res) {
          if (tid) clearTimeout(tid);
          var ct = res.headers.get("content-type") || "";
          var p = ct.indexOf("json") !== -1 ? res.json() : Promise.resolve(null);
          return p.then(function (data) { return { ok: res.ok, status: res.status, data: data }; });
        })
        .catch(function (err) {
          if (tid) clearTimeout(tid);
          return { ok: false, status: 0, data: null, error: err.message };
        });
    }
    return {
      get: function (path, timeout) { return _req(path, { timeout: timeout || 12000 }); },
      request: _req,
      mediaUrl: function (p) {
        if (!p) return null;
        if (/^https?:\/\//i.test(p)) return p;
        return BASE + (p.charAt(0) === "/" ? "" : "/") + p;
      },
    };
  }

  function getRawApi() {
    if (_cachedApi) return _cachedApi;
    var rawApi = window.ApiClient;
    if (rawApi && typeof rawApi.get === "function" && typeof rawApi.request === "function") {
      _cachedApi = rawApi;
      return rawApi;
    }
    return null;
  }

  function getApi() {
    var api = getRawApi();
    if (api) return api;
    _cachedApi = _buildFallbackApi();
    return _cachedApi;
  }

  function mediaUrl(path) {
    var dataApi = window.NwApiClient;
    if (dataApi && typeof dataApi.mediaUrl === "function") {
      return dataApi.mediaUrl(path);
    }
    if (!path) return "";
    if (/^https?:\/\//i.test(path)) return path;
    return window.location.origin + (String(path).charAt(0) === "/" ? "" : "/") + path;
  }

  function escapeHtml(value) {
    return String(value || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  function trim(value) {
    return String(value || "").trim();
  }

  function toInt(value) {
    var num = Number(value);
    return Number.isFinite(num) ? num : 0;
  }

  function slugify(value) {
    return trim(value)
      .toLowerCase()
      .replace(/[^\u0600-\u06ff0-9a-z]+/gi, "-")
      .replace(/^-+|-+$/g, "") || "section";
  }

  function setText(id, value) {
    var node = byId(id);
    if (node) node.textContent = String(value);
  }

  function renderStats() {
    var itemCount = sections.reduce(function (sum, sec) {
      return sum + (Array.isArray(sec.items) ? sec.items.length : 0);
    }, 0);
    setText("pf-section-count", sections.length);
    setText("pf-item-count", itemCount);
  }

  function flattenSectionItems(sectionList) {
    var collected = [];
    (Array.isArray(sectionList) ? sectionList : []).forEach(function (section) {
      (Array.isArray(section.items) ? section.items : []).forEach(function (item) {
        collected.push(Object.assign({}, item));
      });
    });
    return collected;
  }

  function applyLocalSections(rawSections, items) {
    _profile = Object.assign({}, _profile || {}, {
      content_sections: serializeSectionsForSave(rawSections || []),
    });
    sections = buildSections(_profile, Array.isArray(items) ? items : flattenSectionItems(sections));
    _buildAllViewerItems();
    render();
  }

  function showStatus(message, type, persist) {
    var node = byId("pf-status");
    if (!node) return;
    if (_statusTimer) {
      clearTimeout(_statusTimer);
      _statusTimer = 0;
    }
    node.textContent = String(message || "");
    node.className = "pf-status is-" + (type || "info");
    node.style.display = message ? "flex" : "none";
    if (message && !persist) {
      _statusTimer = window.setTimeout(function () {
        node.style.display = "none";
      }, 3400);
    }
  }

  function extractApiError(response, fallbackMessage) {
    if (response && response.error) return String(response.error);
    var data = response && response.data;
    if (!data) return fallbackMessage;
    if (typeof data === "string") return data;
    if (data.detail) return String(data.detail);
    if (Array.isArray(data.non_field_errors) && data.non_field_errors[0]) {
      return String(data.non_field_errors[0]);
    }
    var keys = Object.keys(data || {});
    for (var i = 0; i < keys.length; i++) {
      var value = data[keys[i]];
      if (Array.isArray(value) && value[0]) return String(value[0]);
      if (typeof value === "string" && value) return value;
    }
    return fallbackMessage;
  }

  function inferFileType(file) {
    var mime = trim(file && file.type).toLowerCase();
    var name = trim(file && file.name).toLowerCase();
    if (mime.indexOf("video/") === 0 || /\.(mp4|mov|avi|webm|mkv)$/i.test(name)) return "video";
    if (mime.indexOf("image/") === 0 || /\.(jpg|jpeg|png|webp|gif|bmp)$/i.test(name)) return "image";
    return "";
  }

  function deriveFileLabel(name) {
    return trim(String(name || "")
      .replace(/\.[^.]+$/, "")
      .replace(/[_-]+/g, " ")
      .replace(/\s+/g, " ")) || "عمل جديد";
  }

  function sectionKey(title) {
    return trim(title).toLowerCase();
  }

  function buildSectionId(title, index) {
    return "section-" + slugify(title || SECTION_FALLBACK_TITLE) + "-" + String(index || 0);
  }

  function extractPortfolioSectionTitle(caption) {
    var text = trim(caption);
    if (!text) return SECTION_FALLBACK_TITLE;
    var separators = [" - ", " — ", " – ", " | ", "|"];
    for (var i = 0; i < separators.length; i++) {
      var separator = separators[i];
      var idx = text.indexOf(separator);
      if (idx > 0) return trim(text.slice(0, idx)) || SECTION_FALLBACK_TITLE;
    }
    return SECTION_FALLBACK_TITLE;
  }

  function extractPortfolioItemDescription(caption, sectionTitle) {
    var text = trim(caption);
    if (!text) return "";
    var section = trim(sectionTitle);
    if (!section || section === SECTION_FALLBACK_TITLE) return text;
    var separators = [" - ", " — ", " – ", " | ", "|"];
    for (var i = 0; i < separators.length; i++) {
      var separator = separators[i];
      var prefix = section + separator;
      if (text.indexOf(prefix) === 0) {
        return trim(text.slice(prefix.length));
      }
    }
    return text;
  }

  function formatCaption(sectionTitle, itemDescription) {
    var title = trim(sectionTitle) || SECTION_FALLBACK_TITLE;
    var description = trim(itemDescription);
    return description ? (title + " | " + description) : title;
  }

  function normalizePortfolioList(data) {
    if (Array.isArray(data)) return data.filter(Boolean);
    if (data && Array.isArray(data.results)) return data.results.filter(Boolean);
    if (data && Array.isArray(data.items)) return data.items.filter(Boolean);
    return [];
  }

  function normalizeSectionEntry(raw, index) {
    var source = raw && typeof raw === "object" ? raw : { title: raw };
    var title = trim(source.section_title || source.title || source.name || SECTION_FALLBACK_TITLE) || SECTION_FALLBACK_TITLE;
    var description = trim(source.section_desc || source.description || "");
    return {
      id: trim(source.id) || buildSectionId(title, index),
      title: title,
      description: description,
      raw: source,
      isImplicit: false,
      items: [],
    };
  }

  function serializeSectionsForSave(nextSections) {
    return nextSections.map(function (section, index) {
      var raw = section && section.raw && typeof section.raw === "object" ? Object.assign({}, section.raw) : {};
      var title = trim(section && section.title) || SECTION_FALLBACK_TITLE;
      var description = trim(section && section.description);
      raw.id = trim(section && section.id) || trim(raw.id) || buildSectionId(title, index);
      raw.order = index;
      raw.title = title;
      raw.section_title = title;
      raw.description = description;
      raw.section_desc = description;
      return raw;
    });
  }

  function normalizePortfolioItem(item) {
    var sectionTitle = extractPortfolioSectionTitle(item && item.caption);
    var fileUrl = item && (item.file_url || item.file || item.url || item.image) || "";
    var fileType = trim(item && item.file_type).toLowerCase();
    if (!fileType) fileType = /\.(mp4|mov|avi|webm|mkv)$/i.test(fileUrl) ? "video" : "image";
    return {
      id: toInt(item && item.id),
      file_type: fileType,
      file_url: fileUrl,
      thumbnail_url: item && item.thumbnail_url || fileUrl,
      caption: trim(item && item.caption),
      description: extractPortfolioItemDescription(item && item.caption, sectionTitle),
      section_title: sectionTitle,
      likes_count: toInt(item && item.likes_count),
      saves_count: toInt(item && item.saves_count),
      is_liked: !!(item && item.is_liked),
      is_saved: !!(item && item.is_saved),
      created_at: item && item.created_at || "",
    };
  }

  function buildSections(profile, items) {
    var rawSections = Array.isArray(profile && profile.content_sections) ? profile.content_sections : [];
    var normalizedSections = [];
    var seenTitles = Object.create(null);
    var groupedItems = Object.create(null);
    var i;

    for (i = 0; i < rawSections.length; i++) {
      var section = normalizeSectionEntry(rawSections[i], i);
      var key = sectionKey(section.title);
      if (seenTitles[key]) continue;
      seenTitles[key] = true;
      normalizedSections.push(section);
    }

    for (i = 0; i < items.length; i++) {
      var normalizedItem = normalizePortfolioItem(items[i]);
      var groupTitle = normalizedItem.section_title || SECTION_FALLBACK_TITLE;
      if (!groupedItems[groupTitle]) groupedItems[groupTitle] = [];
      groupedItems[groupTitle].push(normalizedItem);
    }

    var result = normalizedSections.map(function (section) {
      return {
        id: section.id,
        title: section.title,
        description: section.description,
        raw: section.raw,
        isImplicit: false,
        items: groupedItems[section.title] || [],
      };
    });

    Object.keys(groupedItems).forEach(function (title) {
      var key = sectionKey(title);
      if (seenTitles[key]) return;
      result.push({
        id: buildSectionId(title, result.length),
        title: title,
        description: "",
        raw: null,
        isImplicit: true,
        items: groupedItems[title],
      });
    });

    return result;
  }

  function getExplicitSections() {
    return sections.filter(function (section) {
      return !section.isImplicit;
    });
  }

  function findSection(sectionId) {
    for (var i = 0; i < sections.length; i++) {
      if (String(sections[i].id) === String(sectionId)) return sections[i];
    }
    return null;
  }

  function setButtonBusy(button, isBusy, busyLabel) {
    if (!button) return;
    if (!button.dataset.defaultLabel) {
      button.dataset.defaultLabel = trim(button.textContent);
    }
    button.disabled = !!isBusy;
    button.classList.toggle("is-loading", !!isBusy);
    button.textContent = isBusy ? busyLabel : button.dataset.defaultLabel;
  }

  function setUploadBusy(input, isBusy) {
    if (!input) return;
    input.disabled = !!isBusy;
    var label = input.parentElement;
    if (!label) return;
    label.classList.toggle("is-loading", !!isBusy);
    var text = label.querySelector(".pf-upload-label");
    if (text) {
      if (!text.dataset.defaultLabel) text.dataset.defaultLabel = trim(text.textContent);
      text.textContent = isBusy ? "جار الرفع..." : text.dataset.defaultLabel;
    }
  }

  async function saveSections(nextSections) {
    var rawApi = getApi();
    var payload = { content_sections: serializeSectionsForSave(nextSections) };
    var response = await rawApi.request("/api/providers/me/profile/", {
      method: "PATCH",
      body: payload,
      timeout: 15000,
    });
    if (!response.ok) {
      throw new Error(extractApiError(response, "تعذر حفظ الأقسام الحالية"));
    }
    _profile = response.data || _profile;
    return response.data;
  }

  async function init() {
    bindEvents();
    _bindSpotlightSync();
    window.addEventListener("pageshow", function (event) {
      if (event && event.persisted) {
        load(false);
      }
    });
    await load(true);
  }

  async function load(initialLoad) {
    var rawApi = getApi();
    var loading = byId("pf-loading");
    var content = byId("pf-content");
    if (initialLoad && loading) loading.style.display = "flex";

    try {
      var responses = await Promise.all([
        rawApi.get("/api/providers/me/profile/"),
        rawApi.get("/api/providers/me/portfolio/"),
      ]);
      var profileResponse = responses[0];
      var portfolioResponse = responses[1];

      if (!profileResponse.ok) {
        throw new Error(extractApiError(profileResponse, "تعذر تحميل ملف مقدم الخدمة"));
      }
      if (!portfolioResponse.ok) {
        throw new Error(extractApiError(portfolioResponse, "تعذر تحميل معرض الأعمال"));
      }

      _profile = profileResponse.data || {};
      _providerInfo = {
        id: toInt(_profile.id),
        display_name: trim(_profile.display_name) || "مزود خدمة",
        profile_image: _profile.profile_image || "",
      };

      sections = buildSections(_profile, normalizePortfolioList(portfolioResponse.data));
      _buildAllViewerItems();
      render();

      if (loading) loading.style.display = "none";
      if (content) content.style.display = "";
    } catch (error) {
      if (loading) {
        loading.innerHTML = '<p class="text-muted">' + escapeHtml(error && error.message ? error.message : "تعذر تحميل المعرض") + '</p>';
      }
      showStatus(error && error.message ? error.message : "تعذر تحميل المعرض", "error");
    }
  }

  function _buildAllViewerItems() {
    _allViewerItems = [];
    sections.forEach(function (section) {
      var items = Array.isArray(section.items) ? section.items : [];
      items.forEach(function (item) {
        var src = item.file_url || item.thumbnail_url || "";
        var isVideo = String(item.file_type || "image").toLowerCase() === "video" || /\.(mp4|mov|avi|webm|mkv)$/i.test(src);
        _allViewerItems.push({
          id: toInt(item.id),
          source: "portfolio",
          provider_id: _providerInfo.id,
          provider_display_name: _providerInfo.display_name,
          provider_profile_image: _providerInfo.profile_image,
          file_type: isVideo ? "video" : "image",
          media_type: isVideo ? "video" : "image",
          file_url: src,
          thumbnail_url: item.thumbnail_url || src,
          caption: item.caption || "",
          section_title: section.title,
          likes_count: toInt(item.likes_count),
          saves_count: toInt(item.saves_count),
          is_liked: !!item.is_liked,
          is_saved: !!item.is_saved,
          mode_context: "provider",
        });
      });
    });
  }

  function _viewerIndex(sectionId, localIndex) {
    var offset = 0;
    for (var i = 0; i < sections.length; i++) {
      var items = Array.isArray(sections[i].items) ? sections[i].items : [];
      if (String(sections[i].id) === String(sectionId)) return offset + localIndex;
      offset += items.length;
    }
    return localIndex;
  }

  function _bindSpotlightSync() {
    window.addEventListener("nw:portfolio-engagement-update", function (event) {
      var detail = event.detail;
      if (!detail) return;
      var itemId = toInt(detail.id);
      var target = _allViewerItems.find(function (item) {
        return toInt(item.id) === itemId;
      });
      if (!target) return;
      target.likes_count = toInt(detail.likes_count);
      target.saves_count = toInt(detail.saves_count);
      target.is_liked = !!detail.is_liked;
      target.is_saved = !!detail.is_saved;
      _updateItemBadge(itemId, target);
    });
  }

  function _updateItemBadge(itemId, data) {
    var itemNode = document.querySelector('.pf-item[data-item-id="' + itemId + '"]');
    if (!itemNode) return;
    var stats = itemNode.querySelectorAll(".pf-item-stat");
    if (stats[0]) {
      stats[0].textContent = "♥ " + toInt(data.likes_count);
      stats[0].classList.toggle("active", !!data.is_liked);
    }
    if (stats[1]) {
      stats[1].textContent = "⚑ " + toInt(data.saves_count);
      stats[1].classList.toggle("active", !!data.is_saved);
    }
  }

  function renderSection(section) {
    var items = Array.isArray(section.items) ? section.items : [];
    var itemCount = items.length;
    var tagsHtml = '<div class="pf-section-tags">' +
      '<span class="pf-section-count">' + itemCount + ' عنصر</span>' +
      (section.isImplicit ? '<span class="pf-section-tag">مستخرج من العناصر الحالية</span>' : '<span class="pf-section-tag is-saved">قسم محفوظ في الملف</span>') +
      '</div>';
    var sectionDescription = section.description
      ? escapeHtml(section.description)
      : 'أضف وصفًا مختصرًا لهذا القسم لشرح نوع الأعمال المعروضة فيه.';

    return '<section class="pf-section" data-id="' + escapeHtml(section.id) + '">' +
      '<div class="pf-section-top">' +
        '<div class="pf-section-copy">' +
          '<h3>' + escapeHtml(section.title) + '</h3>' +
          '<p class="pf-section-desc' + (section.description ? '' : ' is-empty') + '">' + sectionDescription + '</p>' +
        '</div>' +
        tagsHtml +
      '</div>' +
      '<div class="pf-section-actions">' +
        '<label class="btn btn-secondary pf-upload-btn">' +
          '<span class="pf-upload-label">رفع محتوى</span>' +
          '<input type="file" accept="image/*,video/*" multiple hidden data-section="' + escapeHtml(section.id) + '">' +
        '</label>' +
        '<button class="btn btn-secondary pf-edit-section" data-id="' + escapeHtml(section.id) + '">تعديل القسم</button>' +
        '<button class="btn btn-danger-outline pf-del-section" data-id="' + escapeHtml(section.id) + '">' + (itemCount ? 'حذف القسم ومحتواه' : 'حذف القسم') + '</button>' +
      '</div>' +
      (itemCount ? '<div class="pf-grid">' + items.map(function (item, index) {
        var src = item.file_url || item.thumbnail_url || "";
        var mediaSrc = src ? mediaUrl(src) : "";
        var isVideo = String(item.file_type || "image").toLowerCase() === "video" || /\.(mp4|mov|avi|webm|mkv)$/i.test(src);
        var mediaHtml = mediaSrc
          ? (isVideo
            ? '<video src="' + mediaSrc + '" class="pf-media" muted playsinline preload="metadata"></video>'
            : '<img src="' + mediaSrc + '" class="pf-media" loading="lazy" alt="' + escapeHtml(item.description || section.title) + '">')
          : '<div class="pf-media pf-media-empty">لا توجد معاينة</div>';
        return '<div class="pf-item" data-item-id="' + item.id + '" data-section-id="' + escapeHtml(section.id) + '" data-local-index="' + index + '">' +
          mediaHtml +
          (isVideo ? '<span class="pf-video-badge">▶</span>' : '') +
          '<div class="pf-item-overlay">' +
            '<span class="pf-item-stat' + (item.is_liked ? ' active' : '') + '">♥ ' + toInt(item.likes_count) + '</span>' +
            '<span class="pf-item-stat' + (item.is_saved ? ' active' : '') + '">⚑ ' + toInt(item.saves_count) + '</span>' +
          '</div>' +
          '<div class="pf-item-caption' + (item.description ? '' : ' is-empty') + '">' + escapeHtml(item.description || (isVideo ? 'فيديو من القسم' : 'صورة من القسم')) + '</div>' +
          '<button class="pf-item-delete" data-section="' + escapeHtml(section.id) + '" data-item="' + item.id + '" aria-label="حذف العنصر">×</button>' +
        '</div>';
      }).join("") + '</div>' : '<div class="pf-section-empty">لا توجد عناصر في هذا القسم بعد. ارفع صورًا أو فيديوهات قصيرة وسيتم ربطها بهذا القسم مباشرة.</div>') +
    '</section>';
  }

  function render() {
    var emptyState = byId("pf-empty");
    var container = byId("pf-sections");
    renderStats();
    if (!container || !emptyState) return;

    if (!sections.length) {
      emptyState.style.display = "";
      container.innerHTML = "";
      return;
    }

    emptyState.style.display = "none";
    container.innerHTML = sections.map(renderSection).join("");
    bindItemEvents();
  }

  function bindEvents() {
    var addButton = byId("btn-add-section");
    var firstAddButton = byId("btn-add-first-section");
    var closeButton = byId("pf-modal-close");
    var modal = byId("pf-modal");
    var form = byId("pf-section-form");

    if (addButton) addButton.addEventListener("click", openModal);
    if (firstAddButton) firstAddButton.addEventListener("click", openModal);
    if (closeButton) closeButton.addEventListener("click", closeModal);
    if (modal) {
      modal.addEventListener("click", function (event) {
        if (event.target === modal) closeModal();
      });
    }
    if (form) {
      form.addEventListener("submit", function (event) {
        event.preventDefault();
        createSection();
      });
    }
    document.addEventListener("keydown", function (event) {
      if (event.key === "Escape") closeModal();
    });
  }

  function bindItemEvents() {
    Array.prototype.forEach.call(document.querySelectorAll(".pf-upload-btn input"), function (input) {
      input.addEventListener("change", function () {
        var files = Array.prototype.slice.call(this.files || []);
        var section = findSection(this.getAttribute("data-section"));
        this.value = "";
        if (!section || !files.length) return;
        uploadFiles(section, files, this);
      });
    });

    Array.prototype.forEach.call(document.querySelectorAll(".pf-item-delete"), function (button) {
      button.addEventListener("click", function (event) {
        event.stopPropagation();
        deleteItem(this.getAttribute("data-item"), this);
      });
    });

    Array.prototype.forEach.call(document.querySelectorAll(".pf-del-section"), function (button) {
      button.addEventListener("click", function () {
        deleteSection(this.getAttribute("data-id"), this);
      });
    });

    Array.prototype.forEach.call(document.querySelectorAll(".pf-edit-section"), function (button) {
      button.addEventListener("click", function () {
        openModal(this.getAttribute("data-id"));
      });
    });

    Array.prototype.forEach.call(document.querySelectorAll(".pf-item"), function (itemNode) {
      itemNode.addEventListener("click", function () {
        if (typeof SpotlightViewer === "undefined" || !_allViewerItems.length) return;
        var sectionId = this.getAttribute("data-section-id");
        var localIndex = parseInt(this.getAttribute("data-local-index"), 10) || 0;
        var globalIndex = _viewerIndex(sectionId, localIndex);
        SpotlightViewer.open(_allViewerItems, globalIndex, {
          source: "portfolio",
          label: "معرض",
          eventName: "nw:portfolio-engagement-update",
          modeContext: "provider",
        });
      });
    });
  }

  function openModal(sectionId) {
    var modal = byId("pf-modal");
    var titleNode = byId("pf-modal-title");
    var noteNode = byId("pf-modal-note");
    var idInput = byId("pf-section-id");
    var titleInput = byId("pf-section-title");
    var descInput = byId("pf-section-desc");
    var submitButton = byId("pf-section-submit");
    var section = sectionId ? findSection(sectionId) : null;
    if (idInput) idInput.value = section ? String(section.id) : "";
    if (titleInput) titleInput.value = section ? section.title : "";
    if (descInput) descInput.value = section ? (section.description || "") : "";
    if (titleNode) titleNode.textContent = section ? "تعديل القسم" : "إضافة قسم جديد";
    if (submitButton) submitButton.textContent = section ? "حفظ التعديلات" : "إنشاء القسم";
    if (noteNode) {
      noteNode.textContent = section
        ? "عند تعديل اسم القسم سيتم تحديث اسم المجموعة على العناصر الحالية داخله أيضًا."
        : "يمكنك رفع الصور والفيديوهات داخل القسم مباشرة بعد إنشائه، وسيتم ربط العناصر به تلقائيًا.";
    }
    if (modal) modal.style.display = "";
  }

  function closeModal() {
    var modal = byId("pf-modal");
    var form = byId("pf-section-form");
    var submitButton = byId("pf-section-submit");
    var titleNode = byId("pf-modal-title");
    var noteNode = byId("pf-modal-note");
    if (form) form.reset();
    if (submitButton) submitButton.textContent = "إنشاء القسم";
    if (titleNode) titleNode.textContent = "إضافة قسم جديد";
    if (noteNode) noteNode.textContent = "يمكنك رفع الصور والفيديوهات داخل القسم مباشرة بعد إنشائه، وسيتم ربط العناصر به تلقائيًا.";
    if (modal) modal.style.display = "none";
  }

  async function createSection() {
    var sectionIdInput = byId("pf-section-id");
    var titleInput = byId("pf-section-title");
    var descInput = byId("pf-section-desc");
    var submitButton = byId("pf-section-submit");
    var sectionId = trim(sectionIdInput && sectionIdInput.value);
    var title = trim(titleInput && titleInput.value);
    var description = trim(descInput && descInput.value);
    var existingSection = null;
    var editingSection = sectionId ? findSection(sectionId) : null;

    if (!title) {
      showStatus("اسم القسم مطلوب", "warning");
      return;
    }
    existingSection = sections.find(function (section) {
      return sectionKey(section.title) === sectionKey(title) && String(section.id) !== String(sectionId);
    });
    if (existingSection && !existingSection.isImplicit) {
      showStatus("يوجد قسم بهذا الاسم بالفعل. استخدم اسمًا مختلفًا.", "warning");
      return;
    }

    setButtonBusy(submitButton, true, editingSection ? "جار الحفظ..." : "جار الإنشاء...");
    showStatus(editingSection ? "جار حفظ التعديلات..." : "جار إنشاء القسم...", "info", true);
    try {
      var rawApi = getApi();
      var nextSection = null;
      var nextSections = null;
      var currentItems = flattenSectionItems(sections);
      if (editingSection) {
        var titleChanged = sectionKey(editingSection.title) !== sectionKey(title);
        if (titleChanged) {
          for (var i = 0; i < editingSection.items.length; i++) {
            var item = editingSection.items[i];
            var nextCaption = formatCaption(title, trim(item.description));
            var itemResponse = await rawApi.request("/api/providers/me/portfolio/" + item.id + "/", {
              method: "PATCH",
              body: { caption: nextCaption },
              timeout: 15000,
            });
            if (!itemResponse.ok) {
              throw new Error(extractApiError(itemResponse, "تعذر تحديث اسم القسم على العناصر الحالية"));
            }
            currentItems = currentItems.map(function (row) {
              if (String(row.id) !== String(item.id)) return row;
              return Object.assign({}, row, {
                caption: nextCaption,
                section_title: title,
              });
            });
          }
        }

        nextSection = {
          id: editingSection.id,
          title: title,
          description: description,
          raw: editingSection.raw || {},
          isImplicit: false,
          items: editingSection.items || [],
        };

        if (editingSection.isImplicit) {
          nextSections = getExplicitSections().concat([nextSection]);
        } else {
          nextSections = getExplicitSections().map(function (section) {
            return String(section.id) === String(editingSection.id) ? nextSection : section;
          });
        }
      } else {
        nextSection = existingSection && existingSection.isImplicit
          ? {
              id: existingSection.id,
              title: title,
              description: description,
              raw: existingSection.raw || {},
              isImplicit: false,
              items: existingSection.items || [],
            }
          : {
              id: "section-" + Date.now().toString(36),
              title: title,
              description: description,
              raw: {},
              isImplicit: false,
              items: [],
            };
        nextSections = getExplicitSections().concat([nextSection]);
      }

      var savedProfile = await saveSections(nextSections);
      if (savedProfile && savedProfile.content_sections) {
        _profile.content_sections = savedProfile.content_sections;
      }
      applyLocalSections(
        savedProfile && savedProfile.content_sections ? savedProfile.content_sections : nextSections,
        currentItems
      );
      if (titleInput) titleInput.value = "";
      if (descInput) descInput.value = "";
      if (sectionIdInput) sectionIdInput.value = "";
      closeModal();
      if (editingSection) {
        showStatus("تم تحديث القسم بنجاح", "success");
      } else {
        showStatus(existingSection && existingSection.isImplicit ? "تم حفظ القسم وربطه بالعناصر الحالية" : "تم إنشاء القسم بنجاح", "success");
      }
    } catch (error) {
      showStatus(error && error.message ? error.message : (editingSection ? "تعذر تحديث القسم" : "تعذر إنشاء القسم"), "error");
    } finally {
      setButtonBusy(submitButton, false, editingSection ? "جار الحفظ..." : "جار الإنشاء...");
    }
  }

  async function uploadFiles(section, files, input) {
    var validFiles = [];
    var skipped = 0;
    var uploaded = 0;
    var failed = 0;

    files.forEach(function (file) {
      if (inferFileType(file)) validFiles.push(file);
      else skipped += 1;
    });

    if (!validFiles.length) {
      showStatus("اختر صورًا أو فيديوهات مدعومة للرفع", "warning");
      return;
    }

    setUploadBusy(input, true);
    showStatus("جار رفع المحتوى إلى قسم " + section.title + "...", "info", true);
    try {
      var rawApi = getApi();
      for (var i = 0; i < validFiles.length; i++) {
        var file = validFiles[i];
        var formData = new FormData();
        formData.append("file", file);
        formData.append("file_type", inferFileType(file));
        formData.append("caption", formatCaption(section.title, deriveFileLabel(file.name)));
        var response = await rawApi.request("/api/providers/me/portfolio/", {
          method: "POST",
          body: formData,
          formData: true,
          timeout: 30000,
        });
        if (response.ok) uploaded += 1;
        else failed += 1;
      }

      await load(false);
      if (uploaded && !failed && !skipped) {
        showStatus("تم رفع " + uploaded + " عنصر/عناصر إلى القسم بنجاح", "success");
      } else if (uploaded) {
        showStatus("تم رفع " + uploaded + " عنصر وتعذر رفع " + (failed + skipped) + " عنصر", "warning");
      } else {
        showStatus("تعذر رفع العناصر المحددة", "error");
      }
    } catch (error) {
      showStatus(error && error.message ? error.message : "تعذر رفع الملفات الآن", "error");
    } finally {
      setUploadBusy(input, false);
    }
  }

  async function deleteItem(itemId, button) {
    var id = toInt(itemId);
    if (!id) {
      showStatus("تعذر تحديد العنصر المطلوب حذفه", "error");
      return;
    }
    if (!window.confirm("حذف هذا العنصر من معرض الأعمال؟")) return;

    setButtonBusy(button, true, "...");
    showStatus("جار حذف العنصر...", "info", true);
    try {
      var rawApi = getApi();
      var response = await rawApi.request("/api/providers/me/portfolio/" + id + "/", {
        method: "DELETE",
        timeout: 12000,
      });
      if (!response.ok) {
        throw new Error(extractApiError(response, "تعذر حذف العنصر"));
      }
      await load(false);
      showStatus("تم حذف العنصر", "success");
    } catch (error) {
      showStatus(error && error.message ? error.message : "تعذر حذف العنصر", "error");
    } finally {
      setButtonBusy(button, false, "...");
    }
  }

  async function deleteSection(sectionId, button) {
    var section = findSection(sectionId);
    if (!section) {
      showStatus("تعذر العثور على القسم المطلوب", "error");
      return;
    }

    var message = section.items.length
      ? "حذف القسم سيؤدي إلى حذف " + section.items.length + " عنصر/عناصر داخله. هل تريد المتابعة؟"
      : "حذف هذا القسم من معرض الأعمال؟";
    if (!window.confirm(message)) return;

    setButtonBusy(button, true, "جار الحذف...");
    showStatus("جار حذف القسم...", "info", true);
    try {
      var rawApi = getApi();
      for (var i = 0; i < section.items.length; i++) {
        var response = await rawApi.request("/api/providers/me/portfolio/" + section.items[i].id + "/", {
          method: "DELETE",
          timeout: 12000,
        });
        if (!response.ok) {
          throw new Error(extractApiError(response, "تعذر حذف بعض عناصر القسم"));
        }
      }

      if (!section.isImplicit) {
        var nextSections = getExplicitSections().filter(function (entry) {
          return String(entry.id) !== String(section.id);
        });
        await saveSections(nextSections);
      }

      await load(false);
      showStatus("تم حذف القسم ومحتواه", "success");
    } catch (error) {
      showStatus(error && error.message ? error.message : "تعذر حذف القسم", "error");
    } finally {
      setButtonBusy(button, false, "جار الحذف...");
    }
  }

  document.addEventListener("DOMContentLoaded", init);
  return { init: init };
})();
