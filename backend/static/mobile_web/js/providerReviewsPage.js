"use strict";
var ProviderReviewsPage = (function () {
  var RAW_API = window.ApiClient;
  var API = window.NwApiClient;
  var providerId = null;
  var reviews = [];
  var ratingData = {};

  function init() {
    loadProfile().then(function () { if (providerId) loadData(); });
    document.getElementById("rv-sort").addEventListener("change", function () { sortAndRender(); });
  }

  function apiErrorMessage(data, fallback) {
    if (data && typeof data === "object") {
      if (typeof data.detail === "string" && data.detail.trim()) return data.detail.trim();
      var firstKey = Object.keys(data)[0];
      var firstVal = data[firstKey];
      if (typeof firstVal === "string" && firstVal.trim()) return firstVal.trim();
      if (Array.isArray(firstVal) && firstVal.length) return String(firstVal[0]);
    }
    return fallback || "فشل العملية";
  }

  function loadProfile() {
    return RAW_API.get("/api/accounts/me/").then(function (resp) {
      if (!resp || !resp.ok || !resp.data) {
        throw new Error(apiErrorMessage(resp ? resp.data : null, "تعذر تحميل بيانات الحساب"));
      }
      var d = resp.data;
      providerId = d.provider_profile_id || d.provider_profile || null;
      if (!providerId) {
        document.getElementById("rv-loading").innerHTML = '<p class="text-muted">لا يوجد ملف مزود مرتبط بحسابك</p>';
      }
    });
  }

  function loadData() {
    Promise.all([
      RAW_API.get("/api/reviews/providers/" + providerId + "/reviews/"),
      RAW_API.get("/api/reviews/providers/" + providerId + "/rating/")
    ]).then(function (res) {
      var reviewsResp = res[0] || {};
      var ratingResp = res[1] || {};
      if (!reviewsResp.ok || !ratingResp.ok) {
        throw new Error("reviews_load_failed");
      }
      var reviewsData = reviewsResp.data;
      var ratingDataResp = ratingResp.data;
      var rvRaw = Array.isArray(reviewsData) ? reviewsData : (reviewsData && reviewsData.results ? reviewsData.results : []);
      reviews = rvRaw;
      ratingData = ratingDataResp || {};
      renderSummary();
      sortAndRender();
      document.getElementById("rv-loading").style.display = "none";
      document.getElementById("rv-content").style.display = "";
    }).catch(function () {
      document.getElementById("rv-loading").innerHTML = '<p class="text-muted">تعذر تحميل التقييمات</p>';
    });
  }

  function renderSummary() {
    var avg = parseFloat(ratingData.rating_avg || 0).toFixed(1);
    document.getElementById("rv-score").textContent = avg;
    document.getElementById("rv-count").textContent = (ratingData.rating_count || 0) + " تقييم";
    document.getElementById("rv-stars").innerHTML = buildStars(parseFloat(avg));
    
    var breakdown = [
      { label: "سرعة الاستجابة", val: ratingData.response_speed_avg },
      { label: "جودة العمل", val: ratingData.quality_avg },
      { label: "القيمة مقابل السعر", val: ratingData.cost_value_avg },
      { label: "المصداقية", val: ratingData.credibility_avg },
      { label: "الالتزام بالمواعيد", val: ratingData.on_time_avg }
    ];
    document.getElementById("rv-breakdown").innerHTML = breakdown.map(function (b) {
      var v = parseFloat(b.val || 0).toFixed(1);
      return '<div class="rv-bar-row"><span>' + b.label + '</span><div class="rv-bar"><div class="rv-bar-fill" style="width:' + (v / 5 * 100) + '%"></div></div><span>' + v + '</span></div>';
    }).join("");
  }

  function buildStars(rating) {
    var html = "";
    for (var i = 1; i <= 5; i++) {
      if (i <= Math.floor(rating)) html += '<span class="star full">★</span>';
      else if (i - 0.5 <= rating) html += '<span class="star half">★</span>';
      else html += '<span class="star empty">☆</span>';
    }
    return html;
  }

  function sortAndRender() {
    var sort = document.getElementById("rv-sort").value;
    var sorted = reviews.slice();
    if (sort === "highest") sorted.sort(function (a, b) { return (b.rating || 0) - (a.rating || 0); });
    else if (sort === "lowest") sorted.sort(function (a, b) { return (a.rating || 0) - (b.rating || 0); });
    else sorted.sort(function (a, b) { return (b.id || 0) - (a.id || 0); });
    renderList(sorted);
  }

  function renderList(list) {
    if (!list.length) {
      document.getElementById("rv-list").innerHTML = "";
      document.getElementById("rv-empty").style.display = "";
      return;
    }
    document.getElementById("rv-empty").style.display = "none";
    document.getElementById("rv-list").innerHTML = list.map(function (r) {
      var name = r.client_name || r.user_name || r.user?.name || "عميل";
      var date = r.created_at ? new Date(r.created_at).toLocaleDateString("ar-SA") : "";
      var reply = r.provider_reply || r.reply || "";
      return '<div class="review-card">' +
        '<div class="rv-card-header"><strong>' + name + '</strong><span class="text-muted">' + date + '</span></div>' +
        '<div class="rv-card-stars">' + buildStars(r.rating || 0) + '</div>' +
        '<p class="rv-card-text">' + (r.comment || r.text || "") + '</p>' +
        (reply ? '<div class="rv-reply"><strong>ردك:</strong> ' + reply + '</div>' : '') +
        (!reply ? '<div class="rv-reply-form" data-id="' + r.id + '"><textarea class="form-input rv-reply-input" rows="2" placeholder="اكتب ردك..."></textarea><button class="btn btn-sm btn-primary rv-reply-btn">إرسال الرد</button></div>' : '') +
        '</div>';
    }).join("");

    // Bind reply buttons
    document.querySelectorAll(".rv-reply-btn").forEach(function (btn) {
      btn.addEventListener("click", function () {
        var form = this.closest(".rv-reply-form");
        var reviewId = form.dataset.id;
        var text = form.querySelector(".rv-reply-input").value.trim();
        var button = this;
        if (!text) return;
        button.disabled = true; button.textContent = "جاري الإرسال...";
        RAW_API.request("/api/reviews/reviews/" + reviewId + "/provider-reply/", {
          method: "POST",
          body: { provider_reply: text }
        }).then(function (resp) {
          if (!resp || !resp.ok) {
            throw new Error(apiErrorMessage(resp ? resp.data : null, "فشل إرسال الرد"));
          }
          loadData();
        }).catch(function (err) {
          alert((err && err.message) ? err.message : "فشل إرسال الرد");
          button.disabled = false;
          button.textContent = "إرسال الرد";
        });
      });
    });
  }

  document.addEventListener("DOMContentLoaded", init);
  return { init: init };
})();
