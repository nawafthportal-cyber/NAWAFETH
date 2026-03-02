"use strict";
var AdditionalServicesPage = (function () {
  var API = window.NwApiClient;
  var level = "main"; // main, sub, detail
  var selectedMain = null;
  var selectedSub = null;
  var catalogItems = [];

  var SERVICES = [
    { title: "إدارة العملاء", icon: "👥", color: "#009688", subs: ["إضافة عميل جديد", "إدارة العقود", "إرسال إشعارات"] },
    { title: "الإدارة المالية", icon: "💰", color: "#663D90", subs: ["تسجيل الحساب البنكي (QR)", "خدمات الدفع الإلكتروني", "الفواتير", "كشف حساب شامل", "الربط مع ضريبة القيمة المضافة", "تصدير PDF/Excel"] },
    { title: "التقارير", icon: "📊", color: "#FF9800", subs: ["تقرير شهري", "تقرير ربع سنوي", "تقرير سنوي"] },
    { title: "تطوير تصميم المنصات", icon: "🎨", color: "#3F51B5", subs: ["تصميم واجهة جديدة", "تحسين تجربة المستخدم"] },
    { title: "زيادة السعة", icon: "📦", color: "#4CAF50", subs: ["رفع عدد الملفات", "زيادة مساحة التخزين"] }
  ];

  function init() {
    loadCatalog();
    renderMain();
    bindEvents();
  }

  function loadCatalog() {
    API.get("/api/extras/catalog/").then(function (data) {
      catalogItems = Array.isArray(data) ? data : (data && data.results ? data.results : []);
      document.getElementById("as-loading").style.display = "none";
    }).catch(function () { document.getElementById("as-loading").style.display = "none"; });
  }

  function renderMain() {
    level = "main"; selectedMain = null; selectedSub = null;
    document.getElementById("as-title").textContent = "الخدمات الإضافية";
    document.getElementById("as-main").style.display = "";
    document.getElementById("as-sub").style.display = "none";
    document.getElementById("as-detail").style.display = "none";

    document.getElementById("as-main").innerHTML = SERVICES.map(function (s) {
      return '<div class="as-item" data-title="' + s.title + '">' +
        '<div class="as-icon" style="background:' + s.color + '20">' + s.icon + '</div>' +
        '<span>' + s.title + '</span>' +
        '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#999" stroke-width="2"><polyline points="15 18 9 12 15 6"/></svg></div>';
    }).join("");
  }

  function renderSub(mainTitle) {
    level = "sub"; selectedMain = mainTitle;
    document.getElementById("as-title").textContent = mainTitle;
    document.getElementById("as-main").style.display = "none";
    document.getElementById("as-sub").style.display = "";
    document.getElementById("as-detail").style.display = "none";

    var svc = SERVICES.find(function (s) { return s.title === mainTitle; });
    if (!svc) return;
    document.getElementById("as-sub").innerHTML = svc.subs.map(function (sub) {
      return '<div class="as-item as-sub-item" data-sub="' + sub + '">' +
        '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#663D90" stroke-width="2"><polyline points="9 18 15 12 9 6"/></svg>' +
        '<span>' + sub + '</span>' +
        '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#999" stroke-width="2"><polyline points="15 18 9 12 15 6"/></svg></div>';
    }).join("");
  }

  function renderDetail(subTitle) {
    level = "detail"; selectedSub = subTitle;
    document.getElementById("as-title").textContent = subTitle;
    document.getElementById("as-main").style.display = "none";
    document.getElementById("as-sub").style.display = "none";
    document.getElementById("as-detail").style.display = "";
    document.getElementById("as-detail-title").textContent = "تفاصيل الخدمة";
    document.getElementById("as-detail-desc").textContent = subTitle;

    // Show catalog items if available
    if (catalogItems.length) {
      document.getElementById("as-catalog-items").innerHTML = catalogItems.map(function (item) {
        return '<div class="as-catalog-card">' +
          '<strong>' + (item.name || item.title || "") + '</strong>' +
          '<p class="text-muted">' + (item.description || "") + '</p>' +
          '<div class="as-catalog-footer"><span class="as-price">' + (item.price || "—") + ' ر.س</span>' +
          '<button class="btn btn-sm btn-primary as-buy-btn" data-sku="' + (item.sku || item.id || "") + '">شراء</button></div></div>';
      }).join("");
    } else {
      document.getElementById("as-catalog-items").innerHTML = '<p class="text-muted">لا توجد عناصر متاحة حالياً</p>';
    }
  }

  function bindEvents() {
    // Back button
    document.getElementById("as-back").addEventListener("click", function () {
      if (level === "detail") renderSub(selectedMain);
      else if (level === "sub") renderMain();
      else history.back();
    });

    // Main items
    document.getElementById("as-main").addEventListener("click", function (e) {
      var item = e.target.closest(".as-item");
      if (item) renderSub(item.dataset.title);
    });

    // Sub items
    document.getElementById("as-sub").addEventListener("click", function (e) {
      var item = e.target.closest(".as-sub-item");
      if (item) renderDetail(item.dataset.sub);
    });

    // Buy buttons
    document.getElementById("as-catalog-items").addEventListener("click", function (e) {
      var btn = e.target.closest(".as-buy-btn");
      if (!btn) return;
      var sku = btn.dataset.sku;
      if (!confirm("هل تريد شراء هذه الخدمة؟")) return;
      btn.disabled = true; btn.textContent = "جاري الطلب...";
      API.post("/api/extras/buy/", { sku: sku }).then(function () {
        alert("تم الطلب بنجاح");
        btn.textContent = "تم ✓";
      }).catch(function () {
        alert("فشل الطلب");
        btn.disabled = false; btn.textContent = "شراء";
      });
    });
  }

  document.addEventListener("DOMContentLoaded", init);
  return { init: init };
})();
