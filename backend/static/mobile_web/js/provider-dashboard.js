(function () {
  "use strict";

  const api = window.NawafethApi;
  const ui = window.NawafethUi;
  if (!api || !ui) return;

  /* ── State ── */
  const state = {
    me: null,
    profile: null,
    subscriptions: [],
    categories: [],
    services: [],
    reviews: [],
    rating: null,
    promos: [],
    orders: [],
    urgentCount: 0,
    newCount: 0,
    clientsCount: 0,
  };

  /* ── DOM refs ── */
  const dom = {};
  function cacheDom() {
    dom.loading        = document.getElementById("provider-loading");
    dom.errorState     = document.getElementById("provider-error-state");
    dom.errorMsg       = document.getElementById("provider-error-msg");
    dom.retryBtn       = document.getElementById("provider-retry-btn");
    dom.main           = document.getElementById("provider-main");
    dom.cover          = document.getElementById("provider-cover");
    dom.avatar         = document.getElementById("provider-avatar");
    dom.name           = document.getElementById("provider-name");
    dom.meta           = document.getElementById("provider-meta");
    dom.followersCount = document.getElementById("followers-count");
    dom.followingCount = document.getElementById("following-count");
    dom.likesCount     = document.getElementById("likes-count");
    dom.clientsCount   = document.getElementById("clients-count");
    dom.favoritesCount = document.getElementById("favorites-count");
    dom.planName       = document.getElementById("plan-name");
    dom.completionPercent = document.getElementById("completion-percent");
    dom.completionBarFill = document.getElementById("completion-bar-fill");
    dom.urgentBadge    = document.getElementById("urgent-badge");
    dom.newBadge       = document.getElementById("new-badge");
    dom.switchClientBtn = document.getElementById("switch-client-btn");
    dom.qrBtn          = document.getElementById("qr-btn");
    dom.tabsShell      = document.getElementById("tabs-shell");
  }

  /* ── Helpers ── */
  function mediaUrl(path) {
    if (!path) return "";
    var p = String(path);
    if (/^https?:\/\//i.test(p)) return p;
    return window.location.origin.replace(/\/+$/, "") + (p.startsWith("/") ? p : "/" + p);
  }

  function asList(payload) {
    if (Array.isArray(payload)) return payload;
    if (payload && Array.isArray(payload.results)) return payload.results;
    return [];
  }

  function setText(el, value) {
    if (!el) return;
    el.textContent = value === undefined || value === null || value === "" ? "-" : String(value);
  }

  function showLoading() {
    if (dom.loading) dom.loading.hidden = false;
    if (dom.main) dom.main.hidden = true;
    if (dom.errorState) dom.errorState.hidden = true;
  }

  function showError(message) {
    if (dom.loading) dom.loading.hidden = true;
    if (dom.main) dom.main.hidden = true;
    if (dom.errorState) dom.errorState.hidden = false;
    if (dom.errorMsg) dom.errorMsg.textContent = message || "حدث خطأ في تحميل البيانات";
  }

  function showMain() {
    if (dom.loading) dom.loading.hidden = true;
    if (dom.errorState) dom.errorState.hidden = true;
    if (dom.main) dom.main.hidden = false;
  }

  function completionPercent(profile) {
    if (!profile || typeof profile !== "object") return 30;
    let score = 30;
    if (profile.display_name && profile.bio) score += 12;
    if (profile.about_details || (Array.isArray(profile.qualifications) && profile.qualifications.length)) score += 12;
    if (profile.whatsapp || profile.website || (Array.isArray(profile.social_links) && profile.social_links.length)) score += 12;
    if ((Array.isArray(profile.languages) && profile.languages.length) || Number(profile.coverage_radius_km || 0) > 0) score += 12;
    if (profile.profile_image || profile.cover_image || (Array.isArray(profile.content_sections) && profile.content_sections.length)) score += 12;
    if (profile.seo_keywords || profile.seo_meta_description || profile.seo_slug) score += 10;
    return Math.min(score, 100);
  }

  /* ── Render ── */
  function renderHeader() {
    const me = state.me || {};
    const profile = state.profile || {};

    // Cover image
    var coverUrl = profile.cover_image ? mediaUrl(profile.cover_image) : null;
    if (coverUrl && dom.cover) {
      dom.cover.style.backgroundImage = "url('" + coverUrl + "')";
    }

    // Avatar
    var avatarUrl = profile.profile_image ? mediaUrl(profile.profile_image) : null;
    if (dom.avatar) {
      if (avatarUrl) {
        dom.avatar.innerHTML = '<img src="' + ui.safeText(avatarUrl) + '" alt="avatar">';
      } else {
        dom.avatar.innerHTML = '<span class="material-icons-round">person</span>';
      }
    }

    // Name + meta
    setText(dom.name, profile.display_name || me.provider_display_name || "لوحة مزود الخدمة");
    setText(dom.meta, profile.city || me.provider_city || "—");
  }

  function renderStats() {
    const me = state.me || {};
    setText(dom.followersCount, me.provider_followers_count || 0);
    setText(dom.followingCount, me.following_count || 0);
    setText(dom.likesCount, me.provider_likes_received_count || 0);
    setText(dom.clientsCount, state.clientsCount || 0);
    setText(dom.favoritesCount, me.favorites_media_count || 0);
  }

  function renderPlan() {
    const activeSub = asList(state.subscriptions).find(function (item) {
      return item && item.status === "active";
    }) || asList(state.subscriptions)[0] || null;

    let planTitle = "الباقة المجانية";
    if (activeSub) {
      if (activeSub.plan && activeSub.plan.title) planTitle = activeSub.plan.title;
      else if (activeSub.plan_title) planTitle = activeSub.plan_title;
    }
    setText(dom.planName, planTitle);
  }

  function renderCompletion() {
    const pct = completionPercent(state.profile);
    if (dom.completionPercent) dom.completionPercent.textContent = pct + "%";
    if (dom.completionBarFill) dom.completionBarFill.style.width = pct + "%";
  }

  function renderOrderBadges() {
    if (dom.urgentBadge) dom.urgentBadge.textContent = state.urgentCount + " عاجلة";
    if (dom.newBadge) dom.newBadge.textContent = state.newCount + " جديدة";
  }

  function populateSubcategories() {
    var select = document.getElementById("service-subcategory");
    if (!select) return;
    var options = ['<option value="">اختر التصنيف الفرعي</option>'];
    asList(state.categories).forEach(function (cat) {
      asList(cat.subcategories).forEach(function (sub) {
        options.push(
          '<option value="' + ui.safeText(sub.id) + '">' +
          ui.safeText(cat.name) + " - " + ui.safeText(sub.name) +
          "</option>"
        );
      });
    });
    select.innerHTML = options.join("");
  }

  function renderServices() {
    var root = document.getElementById("services-list");
    if (!root) return;
    if (!state.services.length) {
      root.innerHTML = '<div class="nw-list-item" style="text-align:center;color:#667085">لا توجد خدمات بعد.</div>';
      return;
    }
    root.innerHTML = state.services.map(function (svc) {
      var priceFrom = svc.price_from || "";
      var priceTo = svc.price_to || "";
      var priceLabel = priceFrom && priceTo ? priceFrom + " - " + priceTo : (priceFrom || priceTo || "—");
      return (
        '<article class="nw-list-item">' +
        "<h4>" + ui.safeText(svc.title || "خدمة بدون عنوان") + "</h4>" +
        "<p>التصنيف: " + ui.safeText(svc.subcategory && svc.subcategory.name ? svc.subcategory.name : "—") + "</p>" +
        "<p>السعر: " + ui.safeText(priceLabel) + "</p>" +
        '<button class="nw-link-btn js-delete-service" data-id="' + ui.safeText(svc.id) + '" type="button">حذف</button>' +
        "</article>"
      );
    }).join("");
  }

  function renderReviews() {
    var summaryRoot = document.getElementById("reviews-summary");
    var listRoot = document.getElementById("reviews-list");
    if (!summaryRoot || !listRoot) return;

    var rating = state.rating || {};
    summaryRoot.textContent =
      "متوسط التقييم: " + String(Number(rating.rating_avg || 0).toFixed(2)) +
      " من 5 (" + String(rating.rating_count || 0) + " مراجعة)";

    if (!state.reviews.length) {
      listRoot.innerHTML = '<div class="nw-list-item" style="text-align:center;color:#667085">لا توجد مراجعات منشورة.</div>';
      return;
    }

    listRoot.innerHTML = state.reviews.map(function (review) {
      return (
        '<article class="nw-list-item">' +
        "<h4>" + ui.safeText(review.client_name || "عميل") + " — ⭐ " + ui.safeText(review.rating || 0) + "</h4>" +
        "<p>" + ui.safeText(review.comment || "بدون تعليق") + "</p>" +
        "<p>الرد الحالي: " + ui.safeText(review.provider_reply || "لا يوجد رد") + "</p>" +
        '<form class="js-reply-form nw-inline-form" data-id="' + ui.safeText(review.id) + '" style="grid-template-columns:1fr auto">' +
        '<input name="reply" type="text" placeholder="أضف ردًا على المراجعة" required>' +
        '<button class="nw-primary-btn" type="submit">حفظ الرد</button>' +
        "</form>" +
        "</article>"
      );
    }).join("");
  }

  function renderPromos() {
    var root = document.getElementById("promo-list");
    if (!root) return;
    if (!state.promos.length) {
      root.innerHTML = '<div class="nw-list-item" style="text-align:center;color:#667085">لا توجد طلبات ترويج بعد.</div>';
      return;
    }
    root.innerHTML = state.promos.map(function (promo) {
      return (
        '<article class="nw-list-item">' +
        "<h4>" + ui.safeText(promo.title || "حملة") + "</h4>" +
        "<p>النوع: " + ui.safeText(promo.ad_type || "-") + "</p>" +
        "<p>الحالة: " + ui.safeText(promo.status || "-") + "</p>" +
        "<p>الفترة: " + ui.formatDateTime(promo.start_at) + " - " + ui.formatDateTime(promo.end_at) + "</p>" +
        "</article>"
      );
    }).join("");
  }

  function renderOrders() {
    var root = document.getElementById("orders-list");
    if (!root) return;
    if (!state.orders.length) {
      root.innerHTML = '<div class="nw-list-item" style="text-align:center;color:#667085">لا توجد طلبات حالياً.</div>';
      return;
    }
    root.innerHTML = state.orders.map(function (order) {
      return (
        '<article class="nw-list-item">' +
        "<h4>" + ui.safeText(order.title || "طلب") + "</h4>" +
        "<p>الحالة: " + ui.safeText(order.status_label || order.status || "-") + "</p>" +
        "<p>المدينة: " + ui.safeText(order.city || "-") + "</p>" +
        "<p>تاريخ الإنشاء: " + ui.formatDateTime(order.created_at) + "</p>" +
        "</article>"
      );
    }).join("");
  }

  /* ── Data loading ── */
  async function loadCollections() {
    var results = await Promise.all([
      api.get("/api/providers/me/services/"),
      api.get("/api/providers/categories/", { auth: false }),
      api.get("/api/promo/requests/my/"),
      api.get("/api/marketplace/provider/requests/"),
    ]);
    state.services = asList(results[0]);
    state.categories = asList(results[1]);
    state.promos = asList(results[2]);
    state.orders = asList(results[3]);
  }

  async function loadOrderCounts() {
    try {
      var results = await Promise.all([
        api.get("/api/marketplace/requests/urgent/"),
        api.get("/api/marketplace/provider/requests/?status_group=pending"),
        api.get("/api/marketplace/provider/requests/?status_group=completed"),
      ]);
      state.urgentCount = asList(results[0]).length;
      state.newCount = asList(results[1]).length;
      state.clientsCount = asList(results[2]).length;
    } catch (_) {
      // non-critical
    }
  }

  async function loadReviewsIfPossible() {
    var providerId = state.profile && state.profile.id;
    if (!providerId) {
      state.reviews = [];
      state.rating = { rating_avg: 0, rating_count: 0 };
      return;
    }
    var results = await Promise.all([
      api.get("/api/reviews/providers/" + String(providerId) + "/reviews/", { auth: false }),
      api.get("/api/reviews/providers/" + String(providerId) + "/rating/", { auth: false }),
    ]);
    state.reviews = asList(results[0]);
    state.rating = results[1] || {};
  }

  async function reloadAll() {
    showLoading();
    try {
      var results = await Promise.all([
        api.get("/api/accounts/me/"),
        api.get("/api/providers/me/profile/"),
        api.get("/api/subscriptions/my/"),
      ]);
      state.me = results[0] || {};
      state.profile = results[1] || {};
      state.subscriptions = asList(results[2]);

      await Promise.all([loadCollections(), loadReviewsIfPossible(), loadOrderCounts()]);

      showMain();
      renderHeader();
      renderStats();
      renderPlan();
      renderCompletion();
      renderOrderBadges();
      populateSubcategories();
      renderServices();
      renderReviews();
      renderPromos();
      renderOrders();
    } catch (error) {
      showError(api.getErrorMessage(error && error.payload, error.message || "تعذر تحميل لوحة المزود"));
    }
  }

  /* ── Tabs ── */
  function setupTabs() {
    var tabs = Array.from(document.querySelectorAll(".nw-tab"));
    var panels = Array.from(document.querySelectorAll(".nw-tab-panel"));
    tabs.forEach(function (btn) {
      btn.addEventListener("click", function () {
        var target = btn.dataset.tab;
        tabs.forEach(function (b) { b.classList.toggle("is-active", b === btn); });
        panels.forEach(function (panel) { panel.classList.toggle("is-active", panel.dataset.panel === target); });
      });
    });
  }

  /* Dashboard grid buttons → scroll to tabs and activate */
  function setupDashboardGrid() {
    var btns = Array.from(document.querySelectorAll(".nw-dashboard-btn[data-tab-target]"));
    btns.forEach(function (btn) {
      btn.addEventListener("click", function () {
        var target = btn.dataset.tabTarget;
        // Activate matching tab
        var tab = document.querySelector('.nw-tab[data-tab="' + target + '"]');
        if (tab) tab.click();
        // Scroll to tabs shell
        if (dom.tabsShell) dom.tabsShell.scrollIntoView({ behavior: "smooth", block: "start" });
      });
    });
  }

  /* ── Switch to client mode ── */
  function setupSwitchClient() {
    if (dom.switchClientBtn) {
      dom.switchClientBtn.addEventListener("click", function () {
        window.location.href = "/m/profile/";
      });
    }
  }

  /* ── Forms ── */
  function setupServiceForm() {
    var form = document.getElementById("service-form");
    if (!form) return;

    form.addEventListener("submit", async function (event) {
      event.preventDefault();
      var title = String(document.getElementById("service-title").value || "").trim();
      var priceFrom = String(document.getElementById("service-price-from").value || "").trim();
      var priceTo = String(document.getElementById("service-price-to").value || "").trim();
      var subcategoryId = String(document.getElementById("service-subcategory").value || "").trim();

      if (!title || !subcategoryId) {
        alert("عنوان الخدمة والتصنيف الفرعي مطلوبان.");
        return;
      }

      try {
        await api.post("/api/providers/me/services/", {
          title: title,
          description: "",
          price_from: priceFrom || null,
          price_to: priceTo || null,
          price_unit: "fixed",
          subcategory_id: Number(subcategoryId),
        });
        form.reset();
        await reloadAll();
      } catch (error) {
        alert(api.getErrorMessage(error && error.payload, error.message || "فشل إنشاء الخدمة"));
      }
    });

    var servicesRoot = document.getElementById("services-list");
    if (servicesRoot) {
      servicesRoot.addEventListener("click", async function (event) {
        var target = event.target;
        if (!target || !target.classList.contains("js-delete-service")) return;
        var id = target.getAttribute("data-id");
        if (!id) return;
        try {
          await api.delete("/api/providers/me/services/" + String(id) + "/");
          await reloadAll();
        } catch (error) {
          alert(api.getErrorMessage(error && error.payload, error.message || "فشل حذف الخدمة"));
        }
      });
    }
  }

  function setupReviewReplies() {
    var root = document.getElementById("reviews-list");
    if (!root) return;
    root.addEventListener("submit", async function (event) {
      var form = event.target;
      if (!form || !form.classList.contains("js-reply-form")) return;
      event.preventDefault();
      var reviewId = form.getAttribute("data-id");
      var input = form.querySelector("input[name='reply']");
      var text = String(input && input.value ? input.value : "").trim();
      if (!reviewId || !text) {
        alert("اكتب نص الرد قبل الحفظ.");
        return;
      }
      try {
        await api.post("/api/reviews/reviews/" + String(reviewId) + "/provider-reply/", {
          provider_reply: text,
        });
        await reloadAll();
      } catch (error) {
        alert(api.getErrorMessage(error && error.payload, error.message || "تعذر حفظ الرد"));
      }
    });
  }

  function setupPromoForm() {
    var form = document.getElementById("promo-form");
    if (!form) return;
    form.addEventListener("submit", async function (event) {
      event.preventDefault();
      var title = String(document.getElementById("promo-title").value || "").trim();
      var adType = String(document.getElementById("promo-type").value || "").trim();
      var startAtLocal = String(document.getElementById("promo-start").value || "");
      var endAtLocal = String(document.getElementById("promo-end").value || "");
      var startAt = ui.toIsoFromLocalInput(startAtLocal);
      var endAt = ui.toIsoFromLocalInput(endAtLocal);

      if (!title || !adType || !startAt || !endAt) {
        alert("حقول الترويج الأساسية مطلوبة.");
        return;
      }

      try {
        await api.post("/api/promo/requests/create/", {
          title: title,
          ad_type: adType,
          start_at: startAt,
          end_at: endAt,
          frequency: "60s",
          position: "normal",
        });
        form.reset();
        await reloadAll();
      } catch (error) {
        alert(api.getErrorMessage(error && error.payload, error.message || "تعذر إرسال طلب الترويج"));
      }
    });
  }

  /* ── Init ── */
  document.addEventListener("DOMContentLoaded", function () {
    cacheDom();

    if (!api.isAuthenticated()) {
      window.location.href = api.urls.login;
      return;
    }

    setupTabs();
    setupDashboardGrid();
    setupSwitchClient();
    setupServiceForm();
    setupReviewReplies();
    setupPromoForm();

    if (dom.retryBtn) {
      dom.retryBtn.addEventListener("click", function () { reloadAll(); });
    }

    reloadAll();
  });
})();

