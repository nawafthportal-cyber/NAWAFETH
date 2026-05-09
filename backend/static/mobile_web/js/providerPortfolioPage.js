"use strict";
var ProviderPortfolioPage = (function () {
  var sections = [];
  var _profile = null;
  var _services = [];
  var _allViewerItems = [];
  var _providerInfo = { id: 0, display_name: "مزود خدمة", profile_image: "" };
  var _statusTimer = 0;
  var _cachedApi = null;
  var SECTION_FALLBACK_TITLE = "أعمالي";

  function isEmbeddedMode() {
    try {
      return new URLSearchParams(window.location.search).get("embedded") === "1";
    } catch (_err) {
      return /(?:\?|&)embedded=1(?:&|$)/.test(window.location.search || "");
    }
  }

  function notifyEmbeddedHeight() {
    if (!isEmbeddedMode() || window.parent === window) return;
    var doc = document.documentElement;
    var body = document.body;
    var height = Math.max(
      doc ? doc.scrollHeight || 0 : 0,
      body ? body.scrollHeight || 0 : 0,
      doc ? doc.offsetHeight || 0 : 0,
      body ? body.offsetHeight || 0 : 0
    );
    try {
      window.parent.postMessage({ type: "nw:portfolio-embed-height", height: height }, window.location.origin);
    } catch (_err) {}
  }

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
    var categoryCount = sections.filter(function (sec) {
      return !sec.isAuxiliary;
    }).length;
    var itemCount = sections.reduce(function (sum, sec) {
      return sum + (Array.isArray(sec.items) ? sec.items.length : 0);
    }, 0);
    setText("pf-section-count", categoryCount);
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
    if (mime === "application/pdf" || /\.pdf$/i.test(name)) return "document";
    return "";
  }

  function deriveFileLabel(name) {
    return trim(String(name || "")
      .replace(/\.[^.]+$/, "")
      .replace(/[_-]+/g, " ")
      .replace(/\s+/g, " ")) || "عمل جديد";
  }

  function uniqueNonEmpty(values) {
    var seen = Object.create(null);
    var result = [];
    (values || []).forEach(function (value) {
      var clean = trim(value);
      var key = clean.toLowerCase();
      if (!clean || seen[key]) return;
      seen[key] = true;
      result.push(clean);
    });
    return result;
  }

  function sectionKey(title) {
    return trim(title).toLowerCase();
  }

  function buildSectionId(title, index) {
    return "section-" + slugify(title || SECTION_FALLBACK_TITLE) + "-" + String(index || 0);
  }

  function buildCategorySectionId(categoryId, title, index) {
    var id = toInt(categoryId);
    return id ? ("category-" + id) : buildSectionId(title, index);
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

  function formatItemCaption(categoryTitle, itemDescription, categoryId) {
    var description = trim(itemDescription);
    return toInt(categoryId) ? description : formatCaption(categoryTitle, description);
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
    var categoryId = toInt(item && item.category_id);
    var categoryName = trim(item && item.category_name);
    var sectionTitle = categoryName || extractPortfolioSectionTitle(item && item.caption);
    var fileUrl = item && (item.file_url || item.file || item.url || item.image) || "";
    var fileType = trim(item && item.file_type).toLowerCase();
    if (!fileType) {
      if (/\.pdf$/i.test(fileUrl)) fileType = "document";
      else fileType = /\.(mp4|mov|avi|webm|mkv)$/i.test(fileUrl) ? "video" : "image";
    }
    return {
      id: toInt(item && item.id),
      category_id: categoryId,
      category_name: categoryName,
      file_type: fileType,
      file_url: fileUrl,
      thumbnail_url: item && item.thumbnail_url || fileUrl,
      caption: trim(item && item.caption),
      description: extractPortfolioItemDescription(item && item.caption, sectionTitle),
      section_title: sectionTitle,
      likes_count: toInt(item && item.likes_count),
      saves_count: toInt(item && item.saves_count),
      comments_count: toInt(item && item.comments_count),
      is_liked: !!(item && item.is_liked),
      is_saved: !!(item && item.is_saved),
      created_at: item && item.created_at || "",
    };
  }

  function getPrimaryCategoryEntries() {
    var byTitle = Object.create(null);
    var entries = [];

    function addEntry(title, subcategoryName, categoryId) {
      var cleanTitle = trim(title);
      if (!cleanTitle) return;
      var key = sectionKey(cleanTitle);
      if (!byTitle[key]) {
        byTitle[key] = {
          category_id: toInt(categoryId),
          title: cleanTitle,
          subcategories: [],
        };
        entries.push(byTitle[key]);
      } else if (!byTitle[key].category_id && toInt(categoryId)) {
        byTitle[key].category_id = toInt(categoryId);
      }
      var cleanSubcategory = trim(subcategoryName);
      if (cleanSubcategory && byTitle[key].subcategories.indexOf(cleanSubcategory) === -1) {
        byTitle[key].subcategories.push(cleanSubcategory);
      }
    }

    (_profile && Array.isArray(_profile.main_categories) ? _profile.main_categories : []).forEach(function (title) {
      addEntry(title, "", 0);
    });

    (_profile && Array.isArray(_profile.selected_subcategories) ? _profile.selected_subcategories : []).forEach(function (row) {
      addEntry(row && row.category_name, row && row.name, row && row.category_id);
    });

    (Array.isArray(_services) ? _services : []).forEach(function (service) {
      var sub = service && service.subcategory ? service.subcategory : {};
      addEntry(sub.category_name || (sub.category && sub.category.name), sub.name, sub.category_id || (sub.category && sub.category.id));
    });

    return entries;
  }

  function categorySectionDescription(entry) {
    var subcategories = uniqueNonEmpty(entry && entry.subcategories || []);
    if (subcategories.length) {
      return "أضف أكثر من محتوى لهذا التصنيف، ويمكنك تعديل الوصف أو استبدال الملف أو حذفه. التصنيفات الفرعية: " + subcategories.join("، ");
    }
    return "أضف أكثر من محتوى لهذا التصنيف، ويمكنك تعديل الوصف أو استبدال الملف أو حذفه مباشرة.";
  }

  function buildSections(profile, items) {
    var normalizedItems = normalizePortfolioList(items).map(normalizePortfolioItem);
    var categoryEntries = getPrimaryCategoryEntries();
    var groupedByTitle = Object.create(null);
    var seenCategories = Object.create(null);

    normalizedItems.forEach(function (item) {
      var title = trim(item.section_title) || SECTION_FALLBACK_TITLE;
      if (!groupedByTitle[title]) groupedByTitle[title] = [];
      groupedByTitle[title].push(item);
    });

    var result = categoryEntries.map(function (entry, index) {
      var title = entry.title;
      seenCategories[sectionKey(title)] = true;
      return {
        id: buildCategorySectionId(entry.category_id, title, index),
        category_id: toInt(entry.category_id),
        title: title,
        description: categorySectionDescription(entry),
        raw: null,
        isAuxiliary: false,
        items: groupedByTitle[title] || [],
      };
    });

    Object.keys(groupedByTitle).forEach(function (title) {
      if (seenCategories[sectionKey(title)]) return;
      result.push({
        id: buildSectionId(title || "legacy", result.length),
        title: title || "محتوى غير مرتبط بقسم رئيسي",
        description: "هذه العناصر لا تطابق أي تصنيف رئيسي محفوظ حاليًا.",
        raw: null,
        isAuxiliary: true,
        items: groupedByTitle[title],
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
    // Icon-only buttons contain an SVG and no text; preserving textContent
    // would erase the icon after the first click. For those buttons we just
    // toggle the disabled/loading state and skip the label swap.
    var hasText = !!trim(button.textContent || "");
    if (hasText && !button.dataset.defaultLabel) {
      button.dataset.defaultLabel = trim(button.textContent);
    }
    button.disabled = !!isBusy;
    button.classList.toggle("is-loading", !!isBusy);
    if (hasText) {
      button.textContent = isBusy ? (busyLabel || button.dataset.defaultLabel) : button.dataset.defaultLabel;
    }
  }

  function setUploadBusy(input, isBusy, busyLabel) {
    if (!input) return;
    input.disabled = !!isBusy;
    var label = input.parentElement;
    if (!label) return;
    label.classList.toggle("is-loading", !!isBusy);
    var text = label.querySelector(".pf-upload-label");
    if (text) {
      if (!text.dataset.defaultLabel) text.dataset.defaultLabel = trim(text.textContent);
      text.textContent = isBusy ? (busyLabel || "جار الرفع...") : text.dataset.defaultLabel;
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
    bindToolbar();
    _bindSpotlightSync();
    window.addEventListener("resize", notifyEmbeddedHeight);
    window.addEventListener("message", function (event) {
      if (event.origin !== window.location.origin) return;
      if (!event.data || event.data.type !== "nw:portfolio-embed-parent-ready") return;
      notifyEmbeddedHeight();
    });
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
        rawApi.get("/api/providers/me/services/"),
      ]);
      var profileResponse = responses[0];
      var portfolioResponse = responses[1];
      var servicesResponse = responses[2];

      if (!profileResponse.ok) {
        throw new Error(extractApiError(profileResponse, "تعذر تحميل ملف مقدم الخدمة"));
      }
      if (!portfolioResponse.ok) {
        throw new Error(extractApiError(portfolioResponse, "تعذر تحميل معرض الأعمال"));
      }

      _profile = profileResponse.data || {};
      _services = servicesResponse && servicesResponse.ok ? normalizePortfolioList(servicesResponse.data) : [];
      _providerInfo = {
        id: toInt(_profile.id),
        display_name: trim(_profile.display_name) || "مزود خدمة",
        profile_image: _profile.profile_image || "",
      };

      sections = buildSections(_profile, normalizePortfolioList(portfolioResponse.data));
      _buildAllViewerItems();
      render();
      window.setTimeout(notifyEmbeddedHeight, 0);

      if (loading) loading.style.display = "none";
      if (content) content.style.display = "";
    } catch (error) {
      if (loading) {
        loading.innerHTML = '<p class="text-muted">' + escapeHtml(error && error.message ? error.message : "تعذر تحميل المعرض") + '</p>';
      }
      showStatus(error && error.message ? error.message : "تعذر تحميل المعرض", "error");
      window.setTimeout(notifyEmbeddedHeight, 0);
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
          comments_count: toInt(item.comments_count),
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
      target.comments_count = toInt(detail.comments_count);
      target.is_liked = !!detail.is_liked;
      target.is_saved = !!detail.is_saved;
      _updateItemBadge(itemId, target);
    });
  }

  function _updateItemBadge(itemId, data) {
    var itemNode = document.querySelector('.pf-item[data-item-id="' + itemId + '"]');
    if (!itemNode) return;
  }

  function itemTypeLabel(item) {
    if (String(item && item.file_type || "").toLowerCase() === "video") return "فيديو";
    if (String(item && item.file_type || "").toLowerCase() === "document") return "PDF";
    return "صورة";
  }

  function itemTypeClass(item) {
    var type = String(item && item.file_type || "").toLowerCase();
    if (type === "video") return "is-video";
    if (type === "document") return "is-document";
    return "is-image";
  }

  function itemTypeIconSvg(item) {
    var type = String(item && item.file_type || "").toLowerCase();
    if (type === "video") return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="23 7 16 12 23 17 23 7"/><rect x="1" y="5" width="15" height="14" rx="2"/></svg>';
    if (type === "document") return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/></svg>';
    return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="18" height="18" rx="3"/><circle cx="9" cy="9" r="2"/><polyline points="21 15 15 9 5 19"/></svg>';
  }

  function renderItemStats(item) {
    return '<div class="pf-item-stat-list">' +
      '<span class="pf-item-stat" title="إعجابات"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z"/></svg>' + toInt(item && item.likes_count) + '</span>' +
      '<span class="pf-item-stat" title="حفظ"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 21l-7-5-7 5V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z"/></svg>' + toInt(item && item.saves_count) + '</span>' +
    '</div>';
  }

  function renderItemPreview(item, section, index) {
    var src = item.file_url || item.thumbnail_url || "";
    var mediaSrc = src ? mediaUrl(src) : "";
    var isVideo = String(item.file_type || "").toLowerCase() === "video" || /\.(mp4|mov|avi|webm|mkv)$/i.test(src);
    var isDocument = String(item.file_type || "").toLowerCase() === "document" || /\.pdf$/i.test(src);
    var typeLabel = itemTypeLabel(item);
    var typeClass = itemTypeClass(item);
    var typeIcon = itemTypeIconSvg(item);
    var inner = mediaSrc
      ? (isDocument
        ? '<div class="pf-item-doc"><span class="pf-item-doc-icon"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="9" y1="15" x2="15" y2="15"/><line x1="9" y1="18" x2="13" y2="18"/></svg></span><span class="pf-item-doc-copy">ملف PDF — اضغط للفتح أو الاستبدال</span></div>'
        : (isVideo
          ? '<video src="' + mediaSrc + '" class="pf-item-video" muted playsinline preload="metadata"></video>'
          : '<img src="' + mediaSrc + '" class="pf-item-image" loading="lazy" alt="' + escapeHtml(item.description || section.title) + '">'))
      : '<div class="pf-item-doc"><span class="pf-item-doc-copy">لا توجد معاينة متاحة</span></div>';
    return '<div class="pf-item-preview">' +
      inner +
      '<span class="pf-item-preview-media-badge ' + typeClass + '">' + typeIcon + '<span>' + escapeHtml(typeLabel) + '</span></span>' +
      '<button type="button" class="pf-item-preview-action" data-item-id="' + item.id + '" data-section-id="' + escapeHtml(section.id) + '" data-local-index="' + index + '" data-file-type="' + escapeHtml(String(item.file_type || '')) + '" data-file-url="' + escapeHtml(mediaSrc) + '" aria-label="عرض">' +
        '<span class="pf-item-preview-overlay"><span class="pf-item-preview-overlay-cta"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>عرض</span></span>' +
      '</button>' +
    '</div>';
  }

  function sectionIconSvg() {
    return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/></svg>';
  }

  function renderSection(section) {
    var items = Array.isArray(section.items) ? section.items : [];
    var cardTag = section.isAuxiliary ? 'قسم إضافي' : 'قسم رئيسي';
    return '<section class="detail-card pf-content-card' + (section.isAuxiliary ? ' is-auxiliary' : '') + '" data-id="' + escapeHtml(section.id) + '" data-drop-section="' + escapeHtml(section.id) + '">' +
      '<div class="pf-content-card-head">' +
        '<div class="pf-section-icon" aria-hidden="true">' + sectionIconSvg() + '</div>' +
        '<div class="pf-content-card-copy">' +
          '<div class="pf-content-card-badges">' +
            '<span class="pf-content-card-tag' + (section.isAuxiliary ? ' is-auxiliary' : '') + '">' + cardTag + '</span>' +
            '<span class="pf-content-card-count"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="18" height="18" rx="3"/><line x1="3" y1="9" x2="21" y2="9"/></svg>' + items.length + ' ملف</span>' +
          '</div>' +
          '<h3 class="pf-content-card-title">' + escapeHtml(section.title) + '</h3>' +
          '<p class="pf-content-card-subtitle">' + escapeHtml(section.description || '') + '</p>' +
        '</div>' +
        '<div class="pf-content-card-tools">' +
          (!section.isAuxiliary ? ('<label class="pf-upload-btn">' +
          '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="17 8 12 3 7 8"/><line x1="12" y1="3" x2="12" y2="15"/></svg>' +
          '<span class="pf-upload-label">رفع ملفات</span>' +
          '<input type="file" accept="image/*,video/*,.pdf" multiple hidden data-section="' + escapeHtml(section.id) + '" data-category-id="' + toInt(section.category_id) + '">' +
          '</label>') : '') +
        '</div>' +
      '</div>' +
      (!section.isAuxiliary ? '<div class="pf-dropzone-overlay" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="17 8 12 3 7 8"/><line x1="12" y1="3" x2="12" y2="15"/></svg><span>أفلت الملفات لإضافتها لهذا التصنيف</span></div>' : '') +
      (items.length ? ('<div class="pf-content-items-grid">' + items.map(function (item, index) {
        return '<article class="pf-item" data-item-id="' + item.id + '" data-item-type="' + escapeHtml(String(item.file_type || 'image').toLowerCase()) + '">' +
          renderItemPreview(item, section, index) +
          '<div class="pf-item-meta">' +
            '<div class="pf-item-meta-main">' +
              (item.file_url ? '<a class="pf-item-link" href="' + escapeHtml(mediaUrl(item.file_url)) + '" target="_blank" rel="noopener">فتح الأصلي</a>' : '<span class="pf-item-link is-muted">معاينة فقط</span>') +
            '</div>' +
            renderItemStats(item) +
          '</div>' +
          '<div class="pf-item-desc-wrap">' +
            '<label class="pf-item-desc-label">وصف البطاقة <span class="pf-item-desc-status" data-status></span></label>' +
            '<textarea class="form-input pf-item-desc" rows="2" placeholder="وصف مختصر يظهر للعملاء">' + escapeHtml(item.description || '') + '</textarea>' +
          '</div>' +
          '<div class="pf-item-actions">' +
            '<button type="button" class="btn pf-item-save" data-item-id="' + item.id + '" data-category="' + escapeHtml(section.title) + '" data-category-id="' + toInt(section.category_id) + '"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg> حفظ الوصف</button>' +
            '<label class="pf-icon-btn pf-item-replace" title="استبدال الملف" aria-label="استبدال الملف">' +
              '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="23 4 23 10 17 10"/><polyline points="1 20 1 14 7 14"/><path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"/></svg>' +
              '<input type="file" accept="image/*,video/*,.pdf" hidden class="pf-item-replace-input" data-item-id="' + item.id + '" data-category="' + escapeHtml(section.title) + '" data-category-id="' + toInt(section.category_id) + '">' +
            '</label>' +
            '<button type="button" class="pf-icon-btn is-danger pf-item-delete" data-item="' + item.id + '" title="حذف" aria-label="حذف"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/><path d="M10 11v6M14 11v6"/><path d="M9 6V4a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2"/></svg></button>' +
          '</div>' +
        '</article>';
      }).join('') + '</div>') : '<div class="pf-content-card-empty"><strong>لا توجد ملفات داخل هذا التصنيف بعد</strong>اضغط على «رفع ملفات» أو اسحب وأفلت ملفاتك هنا لإضافتها مباشرةً.</div>') +
    '</section>';
  }

  function render() {
    var emptyState = byId("pf-empty");
    var container = byId("pf-sections");
    var toolbar = byId("pf-toolbar");
    renderStats();
    if (!container || !emptyState) return;

    if (!sections.length) {
      emptyState.style.display = "";
      container.innerHTML = "";
      if (toolbar) toolbar.style.display = "none";
      return;
    }

    emptyState.style.display = "none";
    container.innerHTML = sections.map(renderSection).join("");
    if (toolbar) toolbar.style.display = "";
    bindItemEvents();
    bindSectionDropzones();
    applyFilter();
    window.setTimeout(notifyEmbeddedHeight, 0);
  }

  var _activeFilter = "all";
  var _activeQuery = "";

  function applyFilter() {
    var query = (_activeQuery || "").toLowerCase().trim();
    var filter = _activeFilter || "all";
    var anyVisible = false;
    Array.prototype.forEach.call(document.querySelectorAll(".pf-content-card"), function (card) {
      var sectionTitle = (card.querySelector(".pf-content-card-title") || {}).textContent || "";
      var items = card.querySelectorAll(".pf-item");
      var sectionHasVisible = false;
      Array.prototype.forEach.call(items, function (itemEl) {
        var type = (itemEl.getAttribute("data-item-type") || "image").toLowerCase();
        var desc = ((itemEl.querySelector(".pf-item-desc") || {}).value || "").toLowerCase();
        var matchesType = filter === "all" || type === filter;
        var matchesQuery = !query || desc.indexOf(query) !== -1 || sectionTitle.toLowerCase().indexOf(query) !== -1;
        var visible = matchesType && matchesQuery;
        itemEl.classList.toggle("is-hidden", !visible);
        if (visible) sectionHasVisible = true;
      });
      var sectionMatchesQuery = !query || sectionTitle.toLowerCase().indexOf(query) !== -1;
      var hideSection = items.length > 0 && !sectionHasVisible && !sectionMatchesQuery;
      card.style.display = hideSection ? "none" : "";
      if (!hideSection) anyVisible = true;
    });
  }

  function bindToolbar() {
    var input = byId("pf-search-input");
    if (input && !input.dataset.bound) {
      input.dataset.bound = "1";
      var debounceId = 0;
      input.addEventListener("input", function () {
        if (debounceId) clearTimeout(debounceId);
        var value = this.value;
        debounceId = window.setTimeout(function () {
          _activeQuery = value;
          applyFilter();
        }, 140);
      });
    }
    Array.prototype.forEach.call(document.querySelectorAll(".pf-filter-chip"), function (chip) {
      if (chip.dataset.bound) return;
      chip.dataset.bound = "1";
      chip.addEventListener("click", function () {
        Array.prototype.forEach.call(document.querySelectorAll(".pf-filter-chip"), function (other) {
          other.classList.remove("is-active");
          other.setAttribute("aria-selected", "false");
        });
        this.classList.add("is-active");
        this.setAttribute("aria-selected", "true");
        _activeFilter = this.getAttribute("data-filter") || "all";
        applyFilter();
      });
    });
  }

  function bindSectionDropzones() {
    Array.prototype.forEach.call(document.querySelectorAll(".pf-content-card[data-drop-section]"), function (card) {
      if (card.dataset.dropBound) return;
      var section = findSection(card.getAttribute("data-drop-section"));
      if (!section || section.isAuxiliary) return;
      card.dataset.dropBound = "1";
      var counter = 0;
      card.addEventListener("dragenter", function (event) {
        event.preventDefault();
        counter += 1;
        card.classList.add("is-dragover");
      });
      card.addEventListener("dragover", function (event) {
        event.preventDefault();
        if (event.dataTransfer) event.dataTransfer.dropEffect = "copy";
      });
      card.addEventListener("dragleave", function () {
        counter = Math.max(0, counter - 1);
        if (counter === 0) card.classList.remove("is-dragover");
      });
      card.addEventListener("drop", function (event) {
        event.preventDefault();
        counter = 0;
        card.classList.remove("is-dragover");
        var files = event.dataTransfer && event.dataTransfer.files ? Array.prototype.slice.call(event.dataTransfer.files) : [];
        if (!files.length) return;
        var input = card.querySelector(".pf-upload-btn input");
        uploadFiles(section, files, input);
      });
    });
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

  // Use event delegation on the sections container so every render keeps a
  // single, always-fresh set of handlers. This avoids losing handlers when
  // re-rendering, and prevents duplicate handler registration.
  function bindItemEvents() {
    var container = byId("pf-sections");
    if (!container) return;

    // Track initial textarea values for the dirty-status indicator.
    Array.prototype.forEach.call(container.querySelectorAll(".pf-item-desc"), function (input) {
      input.dataset.initial = String(input.value || '');
    });

    if (container.dataset.delegationBound === "1") return;
    container.dataset.delegationBound = "1";

    container.addEventListener("click", function (event) {
      var target = event.target;
      if (!target || !target.closest) return;

      var saveBtn = target.closest(".pf-item-save");
      if (saveBtn && container.contains(saveBtn)) {
        event.preventDefault();
        updateItemDescription(saveBtn.getAttribute("data-item-id"), saveBtn.getAttribute("data-category"), saveBtn.getAttribute("data-category-id"), saveBtn);
        return;
      }

      var deleteBtn = target.closest(".pf-item-delete");
      if (deleteBtn && container.contains(deleteBtn)) {
        event.preventDefault();
        deleteItem(deleteBtn.getAttribute("data-item"), deleteBtn);
        return;
      }

      var previewBtn = target.closest(".pf-item-preview-action");
      if (previewBtn && container.contains(previewBtn)) {
        event.preventDefault();
        if (String(previewBtn.getAttribute("data-file-type") || "").toLowerCase() === "document") {
          var fileUrl = previewBtn.getAttribute("data-file-url") || "";
          if (fileUrl) window.open(fileUrl, "_blank", "noopener");
          return;
        }
        if (typeof SpotlightViewer === "undefined" || !_allViewerItems.length) return;
        var sectionId = previewBtn.getAttribute("data-section-id");
        var localIndex = parseInt(previewBtn.getAttribute("data-local-index"), 10) || 0;
        var globalIndex = _viewerIndex(sectionId, localIndex);
        SpotlightViewer.open(_allViewerItems, globalIndex, {
          source: "portfolio",
          label: "معرض",
          eventName: "nw:portfolio-engagement-update",
          modeContext: "provider",
        });
        return;
      }
    });

    container.addEventListener("change", function (event) {
      var target = event.target;
      if (!target) return;

      // New uploads (multi-file) coming from the section's upload button.
      if (target.matches && target.matches(".pf-upload-btn input[type=file]")) {
        var files = Array.prototype.slice.call(target.files || []);
        var section = findSection(target.getAttribute("data-section"));
        target.value = "";
        if (!section || !files.length) return;
        uploadFiles(section, files, target);
        return;
      }

      // Replace a single existing file.
      if (target.matches && target.matches(".pf-item-replace-input")) {
        var file = target.files && target.files[0];
        target.value = "";
        if (!file) return;
        replaceItemFile(target.getAttribute("data-item-id"), target.getAttribute("data-category"), target.getAttribute("data-category-id"), file, target);
        return;
      }
    });

    container.addEventListener("input", function (event) {
      var input = event.target;
      if (!input || !input.classList || !input.classList.contains("pf-item-desc")) return;
      var card = input.closest ? input.closest('.pf-item') : null;
      var statusEl = card ? card.querySelector('[data-status]') : null;
      if (!statusEl) return;
      var dirty = String(input.value || '') !== (input.dataset.initial || '');
      statusEl.textContent = dirty ? "تغييرات غير محفوظة" : "";
      statusEl.className = "pf-item-desc-status" + (dirty ? " is-dirty" : "");
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
    window.setTimeout(notifyEmbeddedHeight, 0);
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
    window.setTimeout(notifyEmbeddedHeight, 0);
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
            var nextCaption = formatItemCaption(title, trim(item.description), item.category_id);
            var itemResponse = await rawApi.request("/api/providers/me/portfolio/" + item.id + "/", {
              method: "PATCH",
              body: { caption: nextCaption, category_id: item.category_id || null },
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

  async function updateItemDescription(itemId, categoryTitle, categoryId, button) {
    var id = toInt(itemId);
    var card = button && button.closest ? button.closest('.pf-item') : null;
    var input = card ? card.querySelector('.pf-item-desc') : null;
    if (!id || !input) return;
    setButtonBusy(button, true, 'جار الحفظ...');
    showStatus('جار حفظ وصف الملف...', 'info', true);
    try {
      var rawApi = getApi();
      var payload = { caption: formatItemCaption(categoryTitle, trim(input.value), categoryId) };
      if (toInt(categoryId)) payload.category_id = toInt(categoryId);
      var response = await rawApi.request('/api/providers/me/portfolio/' + id + '/', {
        method: 'PATCH',
        body: payload,
        timeout: 15000,
      });
      if (!response.ok) {
        throw new Error(extractApiError(response, 'تعذر حفظ وصف الملف'));
      }
      await load(false);
      showStatus('تم حفظ وصف الملف', 'success');
    } catch (error) {
      showStatus(error && error.message ? error.message : 'تعذر حفظ وصف الملف', 'error');
    } finally {
      setButtonBusy(button, false, 'جار الحفظ...');
    }
  }

  async function replaceItemFile(itemId, categoryTitle, categoryId, file, input) {
    var id = toInt(itemId);
    var card = input && input.closest ? input.closest('.pf-item') : null;
    var descInput = card ? card.querySelector('.pf-item-desc') : null;
    var fileType = inferFileType(file);
    if (!id || !fileType) {
      showStatus('اختر صورة أو فيديو أو PDF مدعومًا للاستبدال', 'warning');
      return;
    }
    setUploadBusy(input, true, 'جار الاستبدال...');
    showStatus('جار استبدال الملف...', 'info', true);
    try {
      var rawApi = getApi();
      var formData = new FormData();
      formData.append('file', file);
      formData.append('file_type', fileType);
      formData.append('caption', formatItemCaption(categoryTitle, trim(descInput && descInput.value), categoryId));
      if (toInt(categoryId)) formData.append('category_id', String(toInt(categoryId)));
      var response = await rawApi.request('/api/providers/me/portfolio/' + id + '/', {
        method: 'PATCH',
        body: formData,
        formData: true,
        timeout: 30000,
      });
      if (!response.ok) {
        throw new Error(extractApiError(response, 'تعذر استبدال الملف'));
      }
      await load(false);
      showStatus('تم استبدال الملف بنجاح', 'success');
    } catch (error) {
      showStatus(error && error.message ? error.message : 'تعذر استبدال الملف', 'error');
    } finally {
      setUploadBusy(input, false, 'جار الاستبدال...');
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
      showStatus("اختر صورًا أو فيديوهات أو ملفات PDF مدعومة للرفع", "warning");
      return;
    }

    setUploadBusy(input, true);
    showStatus("جار رفع الملفات إلى تصنيف " + section.title + "...", "info", true);
    try {
      var rawApi = getApi();
      for (var i = 0; i < validFiles.length; i++) {
        var file = validFiles[i];
        var formData = new FormData();
        formData.append("file", file);
        formData.append("file_type", inferFileType(file));
        formData.append("caption", formatItemCaption(section.title, "", section.category_id));
        if (toInt(section.category_id)) formData.append("category_id", String(toInt(section.category_id)));
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
        showStatus("تم رفع " + uploaded + " ملف/ملفات إلى التصنيف بنجاح", "success");
      } else if (uploaded) {
        showStatus("تم رفع " + uploaded + " ملف وتعذر رفع " + (failed + skipped) + " ملف", "warning");
      } else {
        showStatus("تعذر رفع الملفات المحددة", "error");
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

    setButtonBusy(button, true, "جار الحذف...");
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
      setButtonBusy(button, false, "جار الحذف...");
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
