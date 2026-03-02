"use strict";
var ProfileCompletionPage = (function () {
  var API = window.NwApiClient;

  function init() { loadProfile(); }

  function loadProfile() {
    API.get("/api/providers/me/profile/").then(function (p) {
      if (!p) { document.getElementById("pc-loading").innerHTML = '<p class="text-muted">لا يوجد ملف مزود</p>'; return; }
      var completion = p.profile_completion || 0.3;
      var percent = Math.round(completion * 100);
      document.getElementById("pc-percent").textContent = percent + "%";
      document.getElementById("pc-bar-fill").style.width = percent + "%";

      // Section checks
      var checks = {
        basic: !!(p.display_name && p.bio),
        service_details: !!(p.service_title || p.services_count > 0),
        additional: !!(p.about_details || p.qualifications_count > 0),
        contact_full: !!(p.whatsapp || p.website || (p.social_links && p.social_links.length)),
        lang_loc: !!(p.languages && p.languages.length && p.city),
        content: !!(p.portfolio_count > 0 || (p.portfolio && p.portfolio.length)),
        seo: !!(p.seo_keywords)
      };

      Object.keys(checks).forEach(function (k) {
        var el = document.getElementById("pc-check-" + k);
        if (el) {
          el.innerHTML = checks[k]
            ? '<svg width="20" height="20" viewBox="0 0 24 24" fill="#4CAF50" stroke="white" stroke-width="2"><circle cx="12" cy="12" r="10"/><polyline points="9 12 11 14 15 10"/></svg>'
            : '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#ccc" stroke-width="2"><circle cx="12" cy="12" r="10"/></svg>';
        }
      });

      document.getElementById("pc-loading").style.display = "none";
      document.getElementById("pc-content").style.display = "";
    }).catch(function () {
      document.getElementById("pc-loading").innerHTML = '<p class="text-muted">تعذر تحميل بيانات الملف</p>';
    });
  }

  document.addEventListener("DOMContentLoaded", init);
  return { init: init };
})();
