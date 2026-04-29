"use strict";
var ProviderReviewsPage = (function () {
  var RAW_API = window.ApiClient;
  var API = window.NwApiClient;
  var providerId = null;
  var reviews = [];
  var ratingData = {};
  var reportDialog = {
    modal: null,
    overlay: null,
    closeBtn: null,
    cancelBtn: null,
    submitBtn: null,
    reasonInput: null,
    detailsInput: null,
    reviewerEl: null,
    dateEl: null,
    starsEl: null,
    textEl: null,
    counterEl: null,
    toastEl: null,
    closeTimer: null,
    toastTimer: null,
    activeReviewId: "",
    activeClientId: null,
    isSubmitting: false
  };

  function init() {
    bindReportDialog();
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
    var avgValue = parseFloat(ratingData.rating_avg || 0);
    var avg = avgValue.toFixed(1);
    var count = parseInt(ratingData.rating_count || 0, 10) || 0;
    var descriptor = getRatingDescriptor(avgValue, count);
    var summarySubtitle = document.getElementById("rv-summary-subtitle");
    var trustScore = document.getElementById("rv-trust-score");
    var metricsStrip = document.getElementById("rv-metrics-strip");
    var distributionEl = document.getElementById("rv-distribution");
    var toolbarNote = document.getElementById("rv-toolbar-note");

    document.getElementById("rv-score").textContent = avg;
    document.getElementById("rv-count").textContent = count + " تقييم";
    document.getElementById("rv-stars").innerHTML = buildStars(avgValue);

    if (summarySubtitle) summarySubtitle.textContent = descriptor;
    if (trustScore) trustScore.textContent = count ? Math.round((avgValue / 5) * 100) + "%" : "--";
    if (metricsStrip) metricsStrip.innerHTML = buildMetricsStrip(avgValue, count);
    if (distributionEl) distributionEl.innerHTML = buildDistributionRows(ratingData.distribution || {}, count);
    if (toolbarNote) {
      toolbarNote.textContent = count
        ? "إجمالي " + count + " تقييم، منها " + countReviewsWithReply() + " تقييمات لديها رد من مقدم الخدمة."
        : "لا توجد تقييمات منشورة بعد، وسيظهر السجل هنا فور وصول أول تقييم.";
    }

    var breakdown = [
      { label: "سرعة الاستجابة", val: ratingData.response_speed_avg },
      { label: "جودة العمل", val: ratingData.quality_avg },
      { label: "القيمة مقابل السعر", val: ratingData.cost_value_avg },
      { label: "المصداقية", val: ratingData.credibility_avg },
      { label: "الالتزام بالمواعيد", val: ratingData.on_time_avg }
    ];
    document.getElementById("rv-breakdown").innerHTML = breakdown.map(function (b) {
      var value = parseFloat(b.val || 0);
      var v = value.toFixed(1);
      var percent = Math.max(0, Math.min(100, (value / 5) * 100));
      return '<div class="rv-bar-row">' +
        '<div class="rv-bar-copy"><strong>' + b.label + '</strong><span>' + getCriterionTone(value) + '</span></div>' +
        '<div class="rv-bar-track"><div class="rv-bar"><div class="rv-bar-fill" style="width:' + percent + '%"></div></div></div>' +
        '<span class="rv-bar-value">' + v + '</span>' +
      '</div>';
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

  function escapeHtml(value) {
    return String(value || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/\"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  function getReviewAuthorName(review) {
    if (!review || typeof review !== "object") return "عميل";
    if (review.client_name) return review.client_name;
    if (review.user_name) return review.user_name;
    if (review.user && review.user.name) return review.user.name;
    return "عميل";
  }

  function getReviewText(review) {
    if (!review || typeof review !== "object") return "";
    return String(review.comment || review.text || review.review_text || "").trim();
  }

  function getReviewDateLabel(review) {
    if (!review || typeof review !== "object") return "بدون تاريخ";
    var raw = review.created_at || review.created;
    return getDateLabel(raw, "بدون تاريخ");
  }

  function getDateLabel(raw, fallback) {
    if (!raw) return fallback || "بدون تاريخ";
    var date = new Date(raw);
    if (!Number.isFinite(date.getTime())) return fallback || "بدون تاريخ";
    return date.toLocaleDateString("ar-SA", {
      year: "numeric",
      month: "long",
      day: "numeric"
    });
  }

  function getReplyDateLabel(review) {
    if (!review || typeof review !== "object") return "";
    return getDateLabel(review.provider_reply_edited_at || review.provider_reply_at, "");
  }

  function getRatingDescriptor(avg, count) {
    if (!count || avg <= 0) return "لا توجد بيانات كافية بعد، وسيتم تحديث المؤشرات فور وصول تقييمات العملاء.";
    if (avg >= 4.8) return "مستوى استثنائي يعكس رضا عاليًا جدًا وثقة قوية من العملاء.";
    if (avg >= 4.4) return "أداء ممتاز ومتوازن مع انطباع احترافي ثابت عبر التجارب.";
    if (avg >= 4.0) return "تقييم قوي يدل على جودة واضحة وتجربة مرضية في أغلب الطلبات.";
    if (avg >= 3.5) return "النتيجة جيدة، مع مساحة واضحة لتعزيز بعض المحاور للوصول لمستوى أعلى.";
    return "النتيجة الحالية تحتاج إلى مزيد من التحسين ورفع جودة التجربة في المحاور الأضعف.";
  }

  function getCriterionTone(value) {
    if (value >= 4.7) return "ممتاز جدًا";
    if (value >= 4.2) return "قوي";
    if (value >= 3.5) return "جيد";
    if (value > 0) return "يحتاج دعم";
    return "بدون بيانات";
  }

  function countReviewsWithReply() {
    return reviews.filter(function (review) {
      return !!String(review && (review.provider_reply || review.reply) || "").trim();
    }).length;
  }

  function countLikedReviews() {
    return reviews.filter(function (review) {
      return !!(review && review.provider_liked);
    }).length;
  }

  function countRecentReviews(days) {
    var now = Date.now();
    var duration = (days || 30) * 24 * 60 * 60 * 1000;
    return reviews.filter(function (review) {
      var raw = review && (review.created_at || review.created);
      var stamp = raw ? new Date(raw).getTime() : 0;
      return Number.isFinite(stamp) && (now - stamp) <= duration;
    }).length;
  }

  function buildMetricsStrip(avgValue, count) {
    var recentCount = countRecentReviews(30);
    var repliesCount = countReviewsWithReply();
    var likedCount = countLikedReviews();
    var featuredMetric = getFeaturedCriterion();
    var items = [
      { label: "إجمالي التقييمات", value: count, tone: "is-neutral" },
      { label: "ردودك المنشورة", value: repliesCount, tone: "is-primary" },
      { label: "تقييمات أعجبتك", value: likedCount, tone: "is-warm" },
      { label: featuredMetric.label, value: featuredMetric.value, tone: "is-cool" }
    ];

    return items.map(function (item) {
      return '<div class="rv-metric-card ' + item.tone + '">' +
        '<strong>' + escapeHtml(String(item.value)) + '</strong>' +
        '<span>' + escapeHtml(item.label) + '</span>' +
      '</div>';
    }).join("");
  }

  function getFeaturedCriterion() {
    var items = [
      { label: "أفضل محور", shortLabel: "أفضل محور", value: parseFloat(ratingData.quality_avg || 0), name: "جودة العمل" },
      { label: "أفضل محور", shortLabel: "أفضل محور", value: parseFloat(ratingData.response_speed_avg || 0), name: "سرعة الاستجابة" },
      { label: "أفضل محور", shortLabel: "أفضل محور", value: parseFloat(ratingData.cost_value_avg || 0), name: "القيمة مقابل السعر" },
      { label: "أفضل محور", shortLabel: "أفضل محور", value: parseFloat(ratingData.credibility_avg || 0), name: "المصداقية" },
      { label: "أفضل محور", shortLabel: "أفضل محور", value: parseFloat(ratingData.on_time_avg || 0), name: "الالتزام بالمواعيد" }
    ];
    items.sort(function (a, b) { return b.value - a.value; });
    if (!items.length || items[0].value <= 0) {
      return { label: "أحدث 30 يوم", value: countRecentReviews(30) };
    }
    return { label: items[0].name, value: items[0].value.toFixed(1) + " / 5" };
  }

  function buildDistributionRows(distribution, count) {
    var total = count || 0;
    var html = "";
    for (var rating = 5; rating >= 1; rating--) {
      var itemCount = parseInt(distribution && distribution[String(rating)] || 0, 10) || 0;
      var percent = total ? Math.round((itemCount / total) * 100) : 0;
      html += '<div class="rv-distribution-row">' +
        '<span class="rv-distribution-label">' + rating + ' نجوم</span>' +
        '<div class="rv-distribution-bar"><div class="rv-distribution-fill" style="width:' + percent + '%"></div></div>' +
        '<span class="rv-distribution-meta">' + itemCount + ' • ' + percent + '%</span>' +
      '</div>';
    }
    return html;
  }

  function getReviewerInitial(name) {
    var clean = String(name || "").trim();
    return clean ? clean.charAt(0) : "ع";
  }

  function buildReviewCriteria(review) {
    var criteria = [
      { label: "الاستجابة", value: review && review.response_speed },
      { label: "الجودة", value: review && review.quality },
      { label: "السعر", value: review && review.cost_value },
      { label: "المصداقية", value: review && review.credibility },
      { label: "المواعيد", value: review && review.on_time }
    ].filter(function (item) {
      return Number(item.value) > 0;
    });

    if (!criteria.length) return "";
    return criteria.map(function (item) {
      return '<span class="rv-criterion-chip"><strong>' + escapeHtml(String(item.value)) + '</strong><span>' + escapeHtml(item.label) + '</span></span>';
    }).join("");
  }

  function buildReplyMeta(review) {
    var replyDate = getReplyDateLabel(review);
    var isEdited = !!(review && review.provider_reply_is_edited);
    if (!replyDate) return "";
    return '<span class="rv-reply-meta">' + escapeHtml(replyDate) + (isEdited ? ' • تم التعديل' : '') + '</span>';
  }

  function findReviewById(reviewId) {
    var normalized = String(reviewId || "");
    for (var i = 0; i < reviews.length; i++) {
      if (String(reviews[i] && reviews[i].id || "") === normalized) return reviews[i];
    }
    return null;
  }

  function bindReportDialog() {
    reportDialog.modal = document.getElementById("rv-report-modal");
    reportDialog.overlay = reportDialog.modal ? reportDialog.modal.querySelector(".rv-report-overlay") : null;
    reportDialog.closeBtn = document.getElementById("rv-report-close");
    reportDialog.cancelBtn = document.getElementById("rv-report-cancel");
    reportDialog.submitBtn = document.getElementById("rv-report-submit");
    reportDialog.reasonInput = document.getElementById("rv-report-reason");
    reportDialog.detailsInput = document.getElementById("rv-report-details");
    reportDialog.reviewerEl = document.getElementById("rv-report-reviewer");
    reportDialog.dateEl = document.getElementById("rv-report-date");
    reportDialog.starsEl = document.getElementById("rv-report-stars");
    reportDialog.textEl = document.getElementById("rv-report-text");
    reportDialog.counterEl = document.getElementById("rv-report-counter");
    reportDialog.toastEl = document.getElementById("rv-toast");

    if (reportDialog.overlay) reportDialog.overlay.addEventListener("click", requestCloseReportDialog);
    if (reportDialog.closeBtn) reportDialog.closeBtn.addEventListener("click", requestCloseReportDialog);
    if (reportDialog.cancelBtn) reportDialog.cancelBtn.addEventListener("click", requestCloseReportDialog);
    if (reportDialog.submitBtn) reportDialog.submitBtn.addEventListener("click", submitReportDialog);
    if (reportDialog.detailsInput) reportDialog.detailsInput.addEventListener("input", updateReportCounter);

    document.addEventListener("keydown", function (event) {
      if (event.key !== "Escape") return;
      if (!reportDialog.modal || reportDialog.modal.classList.contains("hidden")) return;
      event.preventDefault();
      requestCloseReportDialog();
    });

    updateReportCounter();
  }

  function updateReportCounter() {
    if (!reportDialog.counterEl || !reportDialog.detailsInput) return;
    var count = String(reportDialog.detailsInput.value || "").length;
    reportDialog.counterEl.textContent = count + " / 500";
    reportDialog.counterEl.classList.toggle("is-limit", count >= 450);
  }

  function setReportSubmitting(submitting) {
    reportDialog.isSubmitting = !!submitting;

    if (reportDialog.submitBtn) {
      reportDialog.submitBtn.disabled = !!submitting;
      reportDialog.submitBtn.textContent = submitting ? "جارٍ إرسال البلاغ..." : "إرسال البلاغ";
    }
    if (reportDialog.cancelBtn) reportDialog.cancelBtn.disabled = !!submitting;
    if (reportDialog.closeBtn) reportDialog.closeBtn.disabled = !!submitting;
    if (reportDialog.reasonInput) reportDialog.reasonInput.disabled = !!submitting;
    if (reportDialog.detailsInput) reportDialog.detailsInput.disabled = !!submitting;
  }

  function showToast(message, type) {
    if (!reportDialog.toastEl) {
      alert(message || "");
      return;
    }
    reportDialog.toastEl.textContent = message || "";
    reportDialog.toastEl.classList.remove("show", "success", "error");
    if (type) reportDialog.toastEl.classList.add(type);
    requestAnimationFrame(function () {
      reportDialog.toastEl.classList.add("show");
    });
    window.clearTimeout(reportDialog.toastTimer);
    reportDialog.toastTimer = window.setTimeout(function () {
      reportDialog.toastEl.classList.remove("show");
    }, 2600);
  }

  function openReportDialog(review) {
    if (!reportDialog.modal) return;

    window.clearTimeout(reportDialog.closeTimer);
    reportDialog.activeReviewId = review && review.id !== undefined && review.id !== null ? String(review.id) : "";
    var clientId = parseInt(review && review.client_id || "", 10);
    reportDialog.activeClientId = (!Number.isNaN(clientId) && clientId > 0) ? clientId : null;

    if (reportDialog.reviewerEl) reportDialog.reviewerEl.textContent = getReviewAuthorName(review);
    if (reportDialog.dateEl) reportDialog.dateEl.textContent = getReviewDateLabel(review);
    if (reportDialog.starsEl) reportDialog.starsEl.innerHTML = buildStars(parseFloat(review && review.rating || 0));
    if (reportDialog.textEl) {
      var reviewText = getReviewText(review);
      reportDialog.textEl.textContent = reviewText || "لا يوجد نص مرفق في هذا التقييم.";
      reportDialog.textEl.classList.toggle("is-empty", !reviewText);
    }
    if (reportDialog.reasonInput) reportDialog.reasonInput.value = "";
    if (reportDialog.detailsInput) reportDialog.detailsInput.value = "";
    updateReportCounter();
    setReportSubmitting(false);

    reportDialog.modal.classList.remove("hidden");
    reportDialog.modal.setAttribute("aria-hidden", "false");
    document.body.classList.add("rv-report-open");
    requestAnimationFrame(function () {
      if (reportDialog.modal) reportDialog.modal.classList.add("open");
    });
    window.setTimeout(function () {
      if (reportDialog.reasonInput) reportDialog.reasonInput.focus();
    }, 100);
  }

  function requestCloseReportDialog() {
    if (reportDialog.isSubmitting) return;
    closeReportDialog(true);
  }

  function closeReportDialog(resetForm) {
    if (!reportDialog.modal) return;

    reportDialog.modal.classList.remove("open");
    reportDialog.modal.setAttribute("aria-hidden", "true");
    document.body.classList.remove("rv-report-open");
    window.clearTimeout(reportDialog.closeTimer);
    reportDialog.closeTimer = window.setTimeout(function () {
      if (!reportDialog.modal) return;
      reportDialog.modal.classList.add("hidden");
      if (!resetForm) return;

      reportDialog.activeReviewId = "";
      reportDialog.activeClientId = null;
      if (reportDialog.reasonInput) reportDialog.reasonInput.value = "";
      if (reportDialog.detailsInput) reportDialog.detailsInput.value = "";
      if (reportDialog.textEl) {
        reportDialog.textEl.textContent = "-";
        reportDialog.textEl.classList.remove("is-empty");
      }
      if (reportDialog.starsEl) reportDialog.starsEl.innerHTML = "";
      if (reportDialog.reviewerEl) reportDialog.reviewerEl.textContent = "-";
      if (reportDialog.dateEl) reportDialog.dateEl.textContent = "-";
      updateReportCounter();
    }, 180);
  }

  function submitReportDialog() {
    if (!reportDialog.activeReviewId) {
      showToast("تعذر تحديد التقييم المراد الإبلاغ عنه", "error");
      return;
    }

    var reason = String(reportDialog.reasonInput && reportDialog.reasonInput.value || "").trim();
    var details = String(reportDialog.detailsInput && reportDialog.detailsInput.value || "").trim();
    if (!reason) {
      showToast("اختر سبب البلاغ أولاً", "error");
      if (reportDialog.reasonInput) reportDialog.reasonInput.focus();
      return;
    }

    var description = "سبب البلاغ: " + reason;
    if (details) {
      description += "\n\nتفاصيل إضافية:\n" + details;
    }

    var body = {
      ticket_type: "complaint",
      description: description,
      reported_kind: "review",
      reported_object_id: String(reportDialog.activeReviewId)
    };
    if (reportDialog.activeClientId) {
      body.reported_user = reportDialog.activeClientId;
    }

    setReportSubmitting(true);
    safeRequest("/api/support/tickets/create/", {
      method: "POST",
      body: body
    }).then(function (resp) {
      if (!resp || !resp.ok) {
        throw new Error(apiErrorMessage(resp ? resp.data : null, "تعذر إرسال البلاغ"));
      }
      closeReportDialog(true);
      showToast("تم إرسال البلاغ للإدارة. شكراً لك", "success");
    }).catch(function (err) {
      showToast((err && err.message) ? err.message : "تعذر إرسال البلاغ", "error");
    }).finally(function () {
      setReportSubmitting(false);
    });
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
      var date = getReviewDateLabel(r);
      var reply = r.provider_reply || r.reply || "";
      var liked = !!r.provider_liked;
      var requestId = r.request_id || "";
      var reviewId = r.id;
      var reviewText = getReviewText(r);
      var criteriaHtml = buildReviewCriteria(r);
      return '<article class="review-card">' +
        '<div class="rv-card-top">' +
          '<div class="rv-card-author">' +
            '<span class="rv-card-avatar">' + escapeHtml(getReviewerInitial(name)) + '</span>' +
            '<div class="rv-card-author-copy"><strong>' + escapeHtml(name) + '</strong><span>' + escapeHtml(date) + '</span></div>' +
          '</div>' +
          '<div class="rv-card-score-badge"><strong>' + escapeHtml(parseFloat(r.rating || 0).toFixed(1)) + '</strong><span>من 5</span></div>' +
        '</div>' +
        '<div class="rv-card-stars">' + buildStars(r.rating || 0) + '</div>' +
        '<div class="rv-card-meta">' +
          (requestId ? '<span class="rv-meta-pill">طلب #' + escapeHtml(String(requestId)) + '</span>' : '') +
          (liked ? '<span class="rv-meta-pill is-liked">تم تمييزه</span>' : '') +
        '</div>' +
        (criteriaHtml ? '<div class="rv-criteria-grid">' + criteriaHtml + '</div>' : '') +
        '<p class="rv-card-text' + (!reviewText ? ' is-empty' : '') + '">' + escapeHtml(reviewText || "لم يترك العميل تعليقًا نصيًا، وتم تسجيل التقييم الرقمي فقط.") + '</p>' +
        '<div class="rv-actions" data-review-id="' + reviewId + '">' +
          '<button type="button" class="btn btn-sm btn-outline rv-like-btn' + (liked ? ' is-active' : '') + '" data-id="' + reviewId + '" data-liked="' + (liked ? "1" : "0") + '">' + (liked ? 'إلغاء التقدير' : 'تمييز التقييم') + '</button>' +
          '<button type="button" class="btn btn-sm btn-outline rv-chat-btn" data-id="' + reviewId + '" data-client-name="' + escapeHtml(name) + '">مراسلة العميل</button>' +
          '<button type="button" class="btn btn-sm btn-outline rv-request-btn" data-request-id="' + requestId + '" ' + (requestId ? '' : 'disabled') + '>تفاصيل الطلب</button>' +
          '<button type="button" class="btn btn-sm btn-outline rv-report-btn" data-id="' + reviewId + '" data-client-id="' + (r.client_id || '') + '">إبلاغ</button>' +
        '</div>' +
        (reply ? '<div class="rv-reply"><div class="rv-reply-head"><strong>ردك على العميل</strong>' + buildReplyMeta(r) + '</div><p>' + escapeHtml(reply) + '</p></div>' : '') +
        (!reply ? '<div class="rv-reply-form" data-id="' + reviewId + '"><label class="rv-reply-label">أضف ردًا احترافيًا على هذا التقييم</label><textarea class="form-input rv-reply-input" rows="3" maxlength="500" placeholder="اكتب ردًا يشكر العميل أو يوضح تفاصيل الخدمة..."></textarea><button type="button" class="btn btn-sm btn-primary rv-reply-btn">نشر الرد</button></div>' : '') +
      '</article>';
    }).join("");

    document.querySelectorAll('.rv-like-btn').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var reviewId = this.getAttribute('data-id');
        var currentLiked = this.getAttribute('data-liked') === '1';
        var nextLiked = !currentLiked;
        var button = this;
        button.disabled = true;
        safeRequest('/api/reviews/reviews/' + reviewId + '/provider-like/', {
          method: 'POST',
          body: { liked: nextLiked }
        }).then(function (resp) {
          if (!resp || !resp.ok) {
            throw new Error(apiErrorMessage(resp ? resp.data : null, 'تعذر تحديث الإعجاب'));
          }
          loadData();
        }).catch(function (err) {
          alert((err && err.message) ? err.message : 'تعذر تحديث الإعجاب');
          button.disabled = false;
        });
      });
    });

    document.querySelectorAll('.rv-chat-btn').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var reviewId = this.getAttribute('data-id');
        var button = this;
        button.disabled = true;
        safeRequest('/api/reviews/reviews/' + reviewId + '/provider-chat-thread/', {
          method: 'POST'
        }).then(function (resp) {
          if (!resp || !resp.ok) {
            throw new Error(apiErrorMessage(resp ? resp.data : null, 'تعذر فتح الرسائل'));
          }
          var threadId = resp.data && resp.data.thread_id;
          if (!threadId) {
            throw new Error('تعذر فتح الرسائل');
          }
          window.location.href = '/chat/' + threadId + '/';
        }).catch(function (err) {
          alert((err && err.message) ? err.message : 'تعذر فتح الرسائل');
          button.disabled = false;
        });
      });
    });

    document.querySelectorAll('.rv-request-btn').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var requestId = this.getAttribute('data-request-id');
        if (!requestId) return;
        window.location.href = '/provider-orders/' + requestId + '/';
      });
    });

    document.querySelectorAll('.rv-report-btn').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var reviewId = this.getAttribute('data-id');
        var review = findReviewById(reviewId) || {
          id: reviewId,
          client_id: this.getAttribute('data-client-id') || ''
        };
        openReportDialog(review);
      });
    });

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
