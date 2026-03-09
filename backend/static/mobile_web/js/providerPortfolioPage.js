"use strict";
var ProviderPortfolioPage = (function () {
  var API = window.NwApiClient;
  var sections = [];
  var _allViewerItems = []; // normalized items for SpotlightViewer
  var _providerInfo = null; // { id, display_name, profile_image }

  function escapeHtml(value) {
    return String(value || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  function setText(id, value) {
    var node = document.getElementById(id);
    if (node) node.textContent = String(value);
  }

  function toInt(v) { var n = Number(v); return Number.isFinite(n) ? n : 0; }

  function renderStats() {
    var itemCount = sections.reduce(function (sum, sec) {
      var items = sec.items || sec.images || sec.media || [];
      return sum + items.length;
    }, 0);
    setText("pf-section-count", sections.length);
    setText("pf-item-count", itemCount);
  }

  async function init() {
    bindEvents();
    _bindSpotlightSync();
    _providerInfo = await _fetchProviderInfo();
    load();
  }

  async function _fetchProviderInfo() {
    try {
      var profile = await Auth.getProfile();
      if (profile) {
        return {
          id: toInt(profile.provider_id || profile.id),
          display_name: profile.display_name || profile.full_name || 'مزود خدمة',
          profile_image: profile.profile_image || '',
        };
      }
    } catch (_) {}
    return { id: 0, display_name: 'مزود خدمة', profile_image: '' };
  }

  function load() {
    API.get("/api/providers/me/portfolio/").then(function (data) {
      sections = Array.isArray(data) ? data : (data && data.results ? data.results : data && data.sections ? data.sections : []);
      _buildAllViewerItems();
      render();
      document.getElementById("pf-loading").style.display = "none";
      document.getElementById("pf-content").style.display = "";
    }).catch(function () {
      document.getElementById("pf-loading").innerHTML = '<p class="text-muted">تعذر تحميل المعرض</p>';
    });
  }

  /* Build normalized items for SpotlightViewer */
  function _buildAllViewerItems() {
    _allViewerItems = [];
    sections.forEach(function (sec) {
      var items = sec.items || sec.images || sec.media || [];
      var sectionTitle = sec.title || sec.name || '';
      items.forEach(function (item) {
        var src = typeof item === 'string' ? item : item.image || item.file || item.url || item.file_url || '';
        var fileType = (item.file_type || 'image').toString().toLowerCase();
        var isVideo = fileType === 'video' || /\.(mp4|mov|avi|webm)/i.test(src);
        _allViewerItems.push({
          id: toInt(item.id),
          source: 'portfolio',
          provider_id: _providerInfo ? _providerInfo.id : 0,
          provider_display_name: _providerInfo ? _providerInfo.display_name : '',
          provider_profile_image: _providerInfo ? _providerInfo.profile_image : '',
          file_type: isVideo ? 'video' : 'image',
          media_type: isVideo ? 'video' : 'image',
          file_url: src,
          thumbnail_url: item.thumbnail_url || src,
          caption: item.caption || '',
          section_title: sectionTitle,
          likes_count: toInt(item.likes_count),
          saves_count: toInt(item.saves_count),
          is_liked: !!(item.is_liked),
          is_saved: !!(item.is_saved),
          mode_context: 'provider',
        });
      });
    });
  }

  /* Find the global viewer-item index for a section + local index */
  function _viewerIndex(sectionId, localIndex) {
    var offset = 0;
    for (var i = 0; i < sections.length; i++) {
      var items = sections[i].items || sections[i].images || sections[i].media || [];
      if (String(sections[i].id) === String(sectionId)) return offset + localIndex;
      offset += items.length;
    }
    return localIndex;
  }

  /* Sync engagement updates from SpotlightViewer back to sections data */
  function _bindSpotlightSync() {
    window.addEventListener('nw:portfolio-engagement-update', function (event) {
      var d = event.detail;
      if (!d) return;
      var itemId = toInt(d.id);
      var target = _allViewerItems.find(function (it) { return toInt(it.id) === itemId; });
      if (!target) return;
      target.likes_count = toInt(d.likes_count);
      target.saves_count = toInt(d.saves_count);
      target.is_liked = !!d.is_liked;
      target.is_saved = !!d.is_saved;
      _updateItemBadge(itemId, target);
    });
  }

  /* Update the overlay stats for a specific item in the DOM */
  function _updateItemBadge(itemId, data) {
    var el = document.querySelector('.pf-item[data-item-id="' + itemId + '"]');
    if (!el) return;
    var stats = el.querySelectorAll('.pf-item-stat');
    if (stats[0]) {
      stats[0].textContent = '♥ ' + toInt(data.likes_count);
      stats[0].classList.toggle('active', !!data.is_liked);
    }
    if (stats[1]) {
      stats[1].textContent = '⚑ ' + toInt(data.saves_count);
      stats[1].classList.toggle('active', !!data.is_saved);
    }
  }

  function render() {
    renderStats();
    if (!sections.length) {
      document.getElementById("pf-empty").style.display = "";
      document.getElementById("pf-sections").innerHTML = "";
      return;
    }
    document.getElementById("pf-empty").style.display = "none";
    document.getElementById("pf-sections").innerHTML = sections.map(function (sec) {
      var items = sec.items || sec.images || sec.media || [];
      var itemCount = items.length;
      return '<section class="pf-section" data-id="' + sec.id + '">' +
        '<div class="pf-section-top">' +
          '<div class="pf-section-copy">' +
            '<h3>' + escapeHtml(sec.title || sec.name || "") + '</h3>' +
            '<p class="pf-section-desc' + (sec.description ? '' : ' is-empty') + '">' + (sec.description ? escapeHtml(sec.description) : 'أضف وصفًا مختصرًا لهذا القسم لشرح نوع الأعمال المعروضة فيه.') + '</p>' +
          '</div>' +
          '<span class="pf-section-count">' + itemCount + ' عنصر</span>' +
        '</div>' +
        '<div class="pf-section-actions">' +
          '<label class="btn btn-secondary pf-upload-btn">رفع عناصر<input type="file" accept="image/*,video/*" multiple hidden data-section="' + sec.id + '"></label>' +
          '<button class="btn btn-danger pf-del-section" data-id="' + sec.id + '">حذف القسم</button>' +
        '</div>' +
        (itemCount ? '<div class="pf-grid">' + items.map(function (item, idx) {
          var src = typeof item === "string" ? item : item.image || item.file || item.url || item.file_url || "";
          var itemId = item.id || "";
          var fileType = (item.file_type || 'image').toString().toLowerCase();
          var isVideo = fileType === 'video' || /\.(mp4|mov|avi|webm)/i.test(src);
          var likesCount = toInt(item.likes_count);
          var savesCount = toInt(item.saves_count);
          var isLiked = !!(item.is_liked);
          var isSaved = !!(item.is_saved);
          var overlayHtml = '<div class="pf-item-overlay">' +
            '<span class="pf-item-stat' + (isLiked ? ' active' : '') + '">♥ ' + likesCount + '</span>' +
            '<span class="pf-item-stat' + (isSaved ? ' active' : '') + '">⚑ ' + savesCount + '</span>' +
            '</div>';
          var videoBadge = isVideo ? '<span class="pf-video-badge">▶</span>' : '';
          return '<div class="pf-item" data-item-id="' + itemId + '" data-section-id="' + sec.id + '" data-local-index="' + idx + '">' +
            (isVideo ? '<video src="' + API.mediaUrl(src) + '" class="pf-media" muted></video>' : '<img src="' + API.mediaUrl(src) + '" class="pf-media" loading="lazy" alt="">') +
            videoBadge +
            overlayHtml +
            '<button class="pf-item-delete" data-section="' + sec.id + '" data-item="' + itemId + '">×</button></div>';
        }).join("") + '</div>' : '<div class="pf-section-empty">لا توجد عناصر في هذا القسم بعد. ابدأ برفع صور أو فيديوهات توضح أعمالك.</div>') +
      '</section>';
    }).join("");
    bindItemEvents();
  }

  function bindEvents() {
    document.getElementById("btn-add-section").addEventListener("click", openModal);
    document.getElementById("btn-add-first-section") && document.getElementById("btn-add-first-section").addEventListener("click", openModal);
    document.getElementById("pf-modal-close").addEventListener("click", closeModal);
    document.getElementById("pf-modal").addEventListener("click", function (e) { if (e.target === this) closeModal(); });
    document.getElementById("pf-section-form").addEventListener("submit", function (e) { e.preventDefault(); createSection(); });
  }

  function bindItemEvents() {
    // Upload files
    document.querySelectorAll(".pf-upload-btn input").forEach(function (inp) {
      inp.addEventListener("change", function () {
        var sectionId = this.dataset.section;
        var files = this.files;
        if (!files.length) return;
        var fd = new FormData();
        Array.from(files).forEach(function (f) { fd.append("files", f); });
        API.upload("/api/providers/me/portfolio/" + sectionId + "/items/", fd)
          .then(function () { load(); })
          .catch(function () { alert("فشل رفع الملفات"); });
      });
    });
    // Delete items
    document.querySelectorAll(".pf-item-delete").forEach(function (btn) {
      btn.addEventListener("click", function (e) {
        e.stopPropagation();
        if (!confirm("حذف هذا العنصر؟")) return;
        var sectionId = this.dataset.section;
        var itemId = this.dataset.item;
        API.del("/api/providers/me/portfolio/" + sectionId + "/items/" + itemId + "/")
          .then(function () { load(); })
          .catch(function () { alert("فشل الحذف"); });
      });
    });
    // Delete sections
    document.querySelectorAll(".pf-del-section").forEach(function (btn) {
      btn.addEventListener("click", function () {
        if (!confirm("حذف هذا القسم وكل محتواه؟")) return;
        API.del("/api/providers/me/portfolio/" + this.dataset.id + "/")
          .then(function () { load(); })
          .catch(function () { alert("فشل الحذف"); });
      });
    });
    // Open SpotlightViewer on item click
    document.querySelectorAll('.pf-item').forEach(function (el) {
      el.addEventListener('click', function () {
        if (typeof SpotlightViewer === 'undefined' || !_allViewerItems.length) return;
        var sectionId = this.dataset.sectionId;
        var localIndex = parseInt(this.dataset.localIndex, 10) || 0;
        var globalIndex = _viewerIndex(sectionId, localIndex);
        SpotlightViewer.open(_allViewerItems, globalIndex, {
          source: 'portfolio',
          label: 'معرض',
          eventName: 'nw:portfolio-engagement-update',
          modeContext: 'provider',
        });
      });
    });
  }

  function openModal() { document.getElementById("pf-modal").style.display = ""; }
  function closeModal() { document.getElementById("pf-modal").style.display = "none"; }

  function createSection() {
    var title = document.getElementById("pf-section-title").value.trim();
    if (!title) return;
    API.post("/api/providers/me/portfolio/", {
      title: title,
      description: document.getElementById("pf-section-desc").value.trim()
    }).then(function () {
      closeModal();
      document.getElementById("pf-section-form").reset();
      load();
    }).catch(function () { alert("فشل إنشاء القسم"); });
  }

  document.addEventListener("DOMContentLoaded", init);
  return { init: init };
})();
