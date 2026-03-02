"use strict";
var ServiceDetailPage = (function () {
  var API = window.NwApiClient;
  var Cache = window.NwCache;
  var serviceId = null;
  var serviceData = null;

  function init() {
    var m = location.pathname.match(/\/service\/(\d+)/);
    if (!m) { document.getElementById("sd-loading").innerHTML = '<p class="text-muted">خدمة غير موجودة</p>'; return; }
    serviceId = m[1];
    load();
  }

  function load() {
    var cached = Cache.get("service_" + serviceId);
    if (cached) { render(cached); }
    API.get("/api/providers/services/" + serviceId + "/")
      .then(function (d) { Cache.set("service_" + serviceId, d, 120); render(d); })
      .catch(function () { if (!cached) document.getElementById("sd-loading").innerHTML = '<p class="text-muted">تعذر تحميل الخدمة</p>'; });
  }

  function render(d) {
    serviceData = d;
    document.getElementById("sd-loading").style.display = "none";
    document.getElementById("sd-content").style.display = "";

    // Provider info
    var avatar = d.provider_avatar || d.provider?.avatar || "";
    document.getElementById("sd-provider-avatar").innerHTML = avatar
      ? '<img src="' + API.mediaUrl(avatar) + '" alt="">'
      : '<div class="avatar-placeholder">' + ((d.provider_name || d.provider?.name || "؟").charAt(0)) + '</div>';
    document.getElementById("sd-provider-name").textContent = d.provider_name || d.provider?.name || "";
    document.getElementById("sd-provider-category").textContent = d.category_name || d.category?.name || "";

    // Service
    document.getElementById("sd-name").textContent = d.name || d.title || "";
    document.getElementById("sd-likes").textContent = d.likes_count || d.likes || 0;
    document.getElementById("sd-description").textContent = d.description || "";

    // Price
    if (d.price || d.min_price) {
      var priceEl = document.getElementById("sd-price");
      priceEl.style.display = "";
      priceEl.textContent = (d.price || d.min_price) + " ر.س";
    }

    // Images slider
    var images = d.images || d.media || [];
    if (images.length) {
      document.getElementById("sd-slider").style.display = "";
      var track = document.getElementById("sd-slider-track");
      var thumbs = document.getElementById("sd-slider-thumbs");
      track.innerHTML = images.map(function (img) {
        var src = typeof img === "string" ? img : img.image || img.url || img.file;
        return '<div class="sd-slide"><img src="' + API.mediaUrl(src) + '" alt=""></div>';
      }).join("");
      thumbs.innerHTML = images.map(function (img, i) {
        var src = typeof img === "string" ? img : img.image || img.url || img.file;
        return '<div class="sd-thumb' + (i === 0 ? ' active' : '') + '" data-idx="' + i + '"><img src="' + API.mediaUrl(src) + '" alt=""></div>';
      }).join("");
      thumbs.addEventListener("click", function (e) {
        var th = e.target.closest(".sd-thumb");
        if (!th) return;
        var idx = parseInt(th.dataset.idx);
        track.style.transform = "translateX(" + (idx * 100) + "%)";
        thumbs.querySelectorAll(".sd-thumb").forEach(function (t, i) { t.classList.toggle("active", i === idx); });
      });
      document.getElementById("sd-media-count").textContent = images.length + " صور";
    }

    // Comments
    var comments = d.comments || [];
    if (comments.length) {
      document.getElementById("sd-comments-section").style.display = "";
      document.getElementById("sd-comments").innerHTML = comments.map(function (c) {
        return '<div class="sd-comment"><strong>' + (c.user_name || c.user?.name || "مستخدم") + '</strong>' +
          '<p>' + (c.text || c.content || "") + '</p>' +
          '<span class="text-muted">' + (c.created_at ? new Date(c.created_at).toLocaleDateString("ar-SA") : "") + '</span></div>';
      }).join("");
    }

    // Buttons
    var providerId = d.provider_id || d.provider?.id || d.provider;
    document.getElementById("sd-btn-request").href = "/service-request/?service_id=" + serviceId + "&provider_id=" + providerId;
    document.getElementById("sd-btn-chat").href = "/chat/?provider_id=" + providerId;
  }

  document.addEventListener("DOMContentLoaded", init);
  return { init: init };
})();
