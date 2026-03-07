"use strict";
var ProviderReviewsPage = (function () {
  var RAW_API = window.ApiClient;
  var API = window.NwApiClient;
  var providerId = null;
  var reviews = [];
  var ratingData = {};

  function init() {
    var sort = document.getElementById("rv-sort");
    if (sort) sort.addEventListener("change", function () { sortAndRender(); });
    var retry = document.getElementById("rv-retry");
    if (retry) retry.addEventListener("click", bootstrap);
    bootstrap();
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

  function safeGet(path) {
    if (RAW_API && typeof RAW_API.get === "function") {
      return RAW_API.get(path);
    }
    if (API && typeof API.get === "function") {
      return API.get(path).then(function (data) {
        return { ok: !!data, status: data ? 200 : 0, data: data };
      });
    }
    return Promise.resolve({ ok: false, status: 0, data: null });
  }

  function safeRequest(path, options) {
    if (RAW_API && typeof RAW_API.request === "function") {
      return RAW_API.request(path, options || {});
    }
    if (API && typeof API.post === "function") {
      return API.post(path, (options && options.body) || {}).then(function (data) {
        return { ok: !!data, status: data ? 200 : 0, data: data };
      });
    }
    return Promise.resolve({ ok: false, status: 0, data: null });
  }

  function setLoading(loading) {
    var loadingEl = document.getElementById("rv-loading");
    if (loadingEl) loadingEl.style.display = loading ? "" : "none";
  }

  function showError(message) {
    var err = document.getElementById("rv-error");
    var retry = document.getElementById("rv-retry");
    if (err) {
      err.textContent = message || "تعذر تحميل البيانات";
      err.classList.remove("hidden");
    }
    if (retry) retry.style.display = "";
  }

  function clearError() {
    var err = document.getElementById("rv-error");
    var retry = document.getElementById("rv-retry");
    if (err) {
      err.textContent = "";
      err.classList.add("hidden");
    }
    if (retry) retry.style.display = "none";
  }

  function extractProviderId(data) {
    if (!data || typeof data !== "object") return null;
    if (data.provider_profile_id) return data.provider_profile_id;
    if (data.provider_profile && typeof data.provider_profile === "object") {
      return data.provider_profile.id || null;
    }
    if (typeof data.provider_profile === "number") return data.provider_profile;
    if (data.provider && typeof data.provider === "object") return data.provider.id || null;
    return null;
  }

  function bootstrap() {
    setLoading(true);
    clearError();
    var content = document.getElementById("rv-content");
    if (content) content.style.display = "none";
    loadProfile().then(function () {
      if (!providerId) {
        setLoading(false);
        showError("لا يوجد ملف مزود مرتبط بحسابك");
        return;
      }
      return loadData();
    }).catch(function (err) {
      setLoading(false);
      showError((err && err.message) ? err.message : "تعذر تحميل التقييمات");
    });
  }

  function loadProfile() {
    return safeGet("/api/accounts/me/?mode=provider").then(function (resp) {
      if (!resp || !resp.ok || !resp.data) {
        return safeGet("/api/accounts/me/");
      }
      return resp;
    }).then(function (resp) {
      if (!resp || !resp.ok || !resp.data) {
        throw new Error(apiErrorMessage(resp ? resp.data : null, "تعذر تحميل بيانات الحساب"));
      }
      var d = resp.data;
      providerId = extractProviderId(d);
    });
  }

  function loadData() {
    return Promise.allSettled([
      safeGet("/api/reviews/providers/" + providerId + "/reviews/"),
      safeGet("/api/reviews/providers/" + providerId + "/rating/")
    ]).then(function (res) {
      var reviewsResp = (res[0] && res[0].status === "fulfilled") ? res[0].value : null;
      var ratingResp = (res[1] && res[1].status === "fulfilled") ? res[1].value : null;
      var reviewsOk = !!(reviewsResp && reviewsResp.ok);
      var ratingOk = !!(ratingResp && ratingResp.ok);

      if (!reviewsOk && !ratingOk) {
        throw new Error("تعذر تحميل التقييمات");
      }

      var reviewsData = reviewsOk ? reviewsResp.data : [];
      var ratingDataResp = ratingOk ? ratingResp.data : {};
      reviews = Array.isArray(reviewsData) ? reviewsData : (reviewsData && reviewsData.results ? reviewsData.results : []);
      ratingData = ratingDataResp || {};

      renderSummary();
      sortAndRender();
      setLoading(false);
      var content = document.getElementById("rv-content");
      if (content) content.style.display = "";
      if (!reviewsOk) {
        showError("تم تحميل الملخص وتعذر تحميل قائمة التقييمات");
      } else if (!ratingOk) {
        showError("تم تحميل التقييمات وتعذر تحميل الملخص");
      }
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
    else sorted.sort(function (a, b) {
      var da = a && a.created_at ? new Date(a.created_at).getTime() : 0;
      var db = b && b.created_at ? new Date(b.created_at).getTime() : 0;
      return db - da;
    });
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
        '<p class="rv-card-text">' + (r.comment || r.text || r.review_text || "") + '</p>' +
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
        safeRequest("/api/reviews/reviews/" + reviewId + "/provider-reply/", {
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
