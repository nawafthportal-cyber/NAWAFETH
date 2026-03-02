"use strict";
var PromotionPage = (function () {
  var API = window.NwApiClient;
  var STATUS_LABELS = { "new": "جديد", "in_review": "قيد المراجعة", "quoted": "تم التسعير", "pending_payment": "بانتظار الدفع", "active": "مفعل", "rejected": "مرفوض", "expired": "منتهي", "cancelled": "ملغي" };
  var STATUS_COLORS = { "new": "#2196F3", "in_review": "#FF9800", "quoted": "#009688", "pending_payment": "#FFC107", "active": "#4CAF50", "rejected": "#F44336", "expired": "#9E9E9E", "cancelled": "#607D8B" };
  var AD_LABELS = { "banner_home": "بانر الصفحة الرئيسية", "banner_category": "بانر صفحة القسم", "banner_search": "بانر صفحة البحث", "popup_home": "نافذة منبثقة رئيسية", "popup_category": "نافذة منبثقة داخل قسم", "featured_top5": "تمييز ضمن أول 5", "featured_top10": "تمييز ضمن أول 10", "boost_profile": "تعزيز ملف مقدم الخدمة", "push_notification": "إشعار دفع (Push)" };

  function init() {
    loadRequests();
    bindEvents();
  }

  function loadRequests() {
    API.get("/api/promo/requests/").then(function (data) {
      var list = Array.isArray(data) ? data : (data && data.results ? data.results : []);
      document.getElementById("promo-loading").style.display = "none";
      if (!list.length) { document.getElementById("promo-empty").style.display = ""; return; }
      document.getElementById("promo-empty").style.display = "none";
      document.getElementById("promo-list").innerHTML = list.map(function (r) {
        var status = r.status || "new";
        var color = STATUS_COLORS[status] || "#9E9E9E";
        var date = r.created_at ? r.created_at.substring(0, 10) : "";
        return '<div class="promo-card">' +
          '<div class="promo-card-header"><div class="promo-icon"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#663D90" stroke-width="2"><path d="M22 12h-9l-3 9L5.6 2.7 2 12h3"/></svg></div>' +
          '<div class="promo-info"><strong>' + (r.title || "طلب ترويج") + '</strong>' + (r.code ? '<span class="text-muted">' + r.code + '</span>' : '') + '</div>' +
          '<span class="badge" style="background:' + color + '20;color:' + color + '">' + (STATUS_LABELS[status] || status) + '</span></div>' +
          '<div class="promo-card-footer"><span>' + (AD_LABELS[r.ad_type] || r.ad_type || "") + '</span><span class="text-muted">' + date + '</span></div></div>';
      }).join("");
    }).catch(function () {
      document.getElementById("promo-loading").innerHTML = '<p class="text-muted">تعذر تحميل الطلبات</p>';
    });
  }

  function bindEvents() {
    // Tabs
    document.getElementById("promo-tabs").addEventListener("click", function (e) {
      var tab = e.target.closest(".tab");
      if (!tab) return;
      var name = tab.dataset.tab;
      this.querySelectorAll(".tab").forEach(function (t) { t.classList.toggle("active", t === tab); });
      document.querySelectorAll(".tab-panel").forEach(function (p) { p.classList.toggle("active", p.dataset.panel === name); });
    });

    document.getElementById("btn-go-new") && document.getElementById("btn-go-new").addEventListener("click", function () {
      document.querySelector('[data-tab="new"]').click();
    });

    // Submit form
    document.getElementById("promo-form").addEventListener("submit", function (e) {
      e.preventDefault();
      var btn = document.getElementById("promo-submit");
      btn.disabled = true; btn.textContent = "جاري الإرسال...";

      var fd = new FormData();
      fd.append("title", document.getElementById("promo-title").value.trim());
      fd.append("ad_type", document.getElementById("promo-ad-type").value);
      var redirect = document.getElementById("promo-redirect").value.trim();
      if (redirect) fd.append("redirect_url", redirect);
      var start = document.getElementById("promo-start").value;
      if (start) fd.append("start_date", start);
      var end = document.getElementById("promo-end").value;
      if (end) fd.append("end_date", end);
      var cities = document.getElementById("promo-cities").value.trim();
      if (cities) fd.append("target_cities", cities);
      var img = document.getElementById("promo-image").files[0];
      if (img) fd.append("image", img);

      API.upload("/api/promo/requests/", fd).then(function () {
        alert("تم إرسال طلب الترويج بنجاح");
        document.getElementById("promo-form").reset();
        document.querySelector('[data-tab="requests"]').click();
        loadRequests();
      }).catch(function (err) {
        alert(err.message || "فشل إرسال الطلب");
      }).finally(function () {
        btn.disabled = false; btn.textContent = "إرسال الطلب";
      });
    });
  }

  document.addEventListener("DOMContentLoaded", init);
  return { init: init };
})();
