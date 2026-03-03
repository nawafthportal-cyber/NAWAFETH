"use strict";
var ProviderPortfolioPage = (function () {
  var API = window.NwApiClient;
  var sections = [];

  function init() {
    load();
    bindEvents();
  }

  function load() {
    API.get("/api/providers/me/portfolio/").then(function (data) {
      sections = Array.isArray(data) ? data : (data && data.results ? data.results : data && data.sections ? data.sections : []);
      render();
      document.getElementById("pf-loading").style.display = "none";
      document.getElementById("pf-content").style.display = "";
    }).catch(function () {
      document.getElementById("pf-loading").innerHTML = '<p class="text-muted">تعذر تحميل المعرض</p>';
    });
  }

  function render() {
    if (!sections.length) {
      document.getElementById("pf-empty").style.display = "";
      document.getElementById("pf-sections").innerHTML = "";
      return;
    }
    document.getElementById("pf-empty").style.display = "none";
    document.getElementById("pf-sections").innerHTML = sections.map(function (sec) {
      var items = sec.items || sec.images || sec.media || [];
      return '<div class="pf-section" data-id="' + sec.id + '">' +
        '<div class="pf-section-header"><h3>' + (sec.title || sec.name || "") + '</h3>' +
        '<div class="pf-section-actions">' +
        '<label class="btn btn-sm btn-outline pf-upload-btn">رفع<input type="file" accept="image/*,video/*" multiple hidden data-section="' + sec.id + '"></label>' +
        '<button class="btn btn-sm btn-danger pf-del-section" data-id="' + sec.id + '">حذف القسم</button></div></div>' +
        (sec.description ? '<p class="text-muted">' + sec.description + '</p>' : '') +
        '<div class="pf-grid">' + items.map(function (item) {
          var src = typeof item === "string" ? item : item.image || item.file || item.url || "";
          var itemId = item.id || "";
          var isVideo = /\.(mp4|mov|avi|webm)/i.test(src);
          var likesCount = Number(item && item.likes_count) || 0;
          var savesCount = Number(item && item.saves_count) || 0;
          var isLiked = !!(item && item.is_liked);
          var isSaved = !!(item && item.is_saved);
          var statsHtml = '<div class="pf-item-stats">' +
            '<span class="pf-item-stat' + (isLiked ? ' active' : '') + '">❤ ' + likesCount + '</span>' +
            '<span class="pf-item-stat' + (isSaved ? ' active' : '') + '">🔖 ' + savesCount + '</span>' +
            '</div>';
          return '<div class="pf-item" data-item-id="' + itemId + '">' +
            (isVideo ? '<video src="' + API.mediaUrl(src) + '" class="pf-media"></video>' : '<img src="' + API.mediaUrl(src) + '" class="pf-media" alt="">') +
            statsHtml +
            '<button class="pf-item-delete" data-section="' + sec.id + '" data-item="' + itemId + '">×</button></div>';
        }).join("") + '</div></div>';
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
      btn.addEventListener("click", function () {
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
