(function () {
  "use strict";

  const api = window.NawafethApi;
  const ui = window.NawafethUi;
  const config = window.NAWAFETH_WEB_CONFIG || {};
  const urls = config.urls || {};
  if (!api || !ui) return;

  let reelsTimer = null;
  let reelsPos = 0;

  function asList(payload) {
    if (Array.isArray(payload)) return payload;
    if (payload && Array.isArray(payload.results)) return payload.results;
    return [];
  }

  function mediaUrl(path) {
    if (!path) return "";
    const value = String(path);
    if (/^https?:\/\//i.test(value)) return value;
    const origin = window.location.origin.replace(/\/+$/, "");
    return origin + (value.startsWith("/") ? value : "/" + value);
  }

  function webBasePath() {
    const homeUrl = urls.home || "/web/";
    return homeUrl.replace(/\/+$/, "");
  }

  function providerProfileUrl(providerId) {
    if (!providerId) return "#";
    return webBasePath() + "/providers/" + encodeURIComponent(providerId) + "/";
  }

  function searchProvidersUrl(categoryId) {
    const base = urls.searchProviders || (webBasePath() + "/search/providers/");
    if (!categoryId) return base;
    const separator = base.includes("?") ? "&" : "?";
    return base + separator + "category=" + encodeURIComponent(categoryId);
  }

  function categoryIconName(name) {
    const n = String(name || "").toLowerCase();
    if (n.includes("قانون") || n.includes("محام")) return "gavel";
    if (n.includes("هندس")) return "engineering";
    if (n.includes("تصميم")) return "design_services";
    if (n.includes("توصيل")) return "delivery_dining";
    if (n.includes("صح") || n.includes("طب")) return "health_and_safety";
    if (n.includes("ترجم")) return "translate";
    if (n.includes("برمج") || n.includes("تقن")) return "code";
    if (n.includes("صيان")) return "build";
    if (n.includes("رياض")) return "fitness_center";
    if (n.includes("منزل")) return "home_repair_service";
    if (n.includes("مال") || n.includes("محاسب")) return "attach_money";
    if (n.includes("تسويق")) return "campaign";
    if (n.includes("تعليم") || n.includes("تدريب")) return "school";
    if (n.includes("سيار") || n.includes("نقل")) return "directions_car";
    return "category";
  }

  function renderCategories(items) {
    const root = document.getElementById("categories-list");
    if (!root) return;

    const fallback = [
      { id: 0, name: "استشارات قانونية" },
      { id: 0, name: "خدمات هندسية" },
      { id: 0, name: "تصميم جرافيك" },
      { id: 0, name: "توصيل سريع" },
      { id: 0, name: "رعاية صحية" },
      { id: 0, name: "ترجمة لغات" },
      { id: 0, name: "برمجة مواقع" },
      { id: 0, name: "صيانة أجهزة" },
    ];

    const list = items.length ? items : fallback;
    root.innerHTML = list
      .map(function (category) {
        const categoryName = category && category.name ? category.name : "تصنيف";
        const rawId = category && category.id !== undefined ? category.id : "";
        const categoryId = Number(rawId);
        const href = categoryId > 0 ? searchProvidersUrl(categoryId) : searchProvidersUrl("");
        return (
          '<a class="nw-category-chip" href="' + ui.safeText(href) + '">' +
          '<div class="nw-category-chip__icon">' +
          '<span class="material-icons-round">' + ui.safeText(categoryIconName(categoryName)) + "</span>" +
          "</div>" +
          '<span class="nw-category-chip__name">' + ui.safeText(categoryName) + "</span>" +
          "</a>"
        );
      })
      .join("");
  }

  function firstLetter(text, fallback) {
    const value = String(text || "").trim();
    if (!value) return fallback || "؟";
    return value.charAt(0);
  }

  function numericValue(raw, fallback) {
    if (raw === undefined || raw === null || raw === "") return fallback;
    const number = Number(raw);
    return Number.isFinite(number) ? number : fallback;
  }

  function providerName(provider) {
    return provider.display_name || provider.displayName || "مزود خدمة";
  }

  function providerAvatar(provider) {
    return mediaUrl(provider.profile_image || provider.profileImage || "");
  }

  function renderProviders(items) {
    const root = document.getElementById("providers-list");
    if (!root) return;

    if (!items.length) {
      root.innerHTML =
        '<div class="nw-home-empty">' +
        '<span class="material-icons-round">info_outline</span>' +
        "<span>لا يوجد مزودو خدمة حالياً</span>" +
        "</div>";
      return;
    }

    root.innerHTML = items
      .map(function (provider) {
        const id = provider.id || provider.provider_id || "";
        const name = providerName(provider);
        const city = provider.city || "";
        const cover = mediaUrl(provider.cover_image || provider.coverImage || "");
        const avatar = providerAvatar(provider);
        const rating = numericValue(provider.rating_avg ?? provider.ratingAvg, 0);
        const followers = numericValue(provider.followers_count ?? provider.followersCount, 0);
        const likes = numericValue(provider.likes_count ?? provider.likesCount, 0);
        const isVerified = provider.is_verified === true || provider.isVerified === true;
        const isVerifiedBlue = provider.is_verified_blue === true || provider.isVerifiedBlue === true;
        const providerLink = providerProfileUrl(id);
        const ratingText = rating > 0 ? rating.toFixed(1) : "-";
        const verifiedClass = isVerifiedBlue ? "nw-provider-verified is-blue" : "nw-provider-verified";
        const avatarHtml = avatar
          ? '<div class="nw-provider-avatar" style="background-image:url(\'' + ui.safeText(avatar) + "')\"></div>"
          : '<div class="nw-provider-avatar">' + ui.safeText(firstLetter(name, "؟")) + "</div>";
        const coverStyle = cover ? "background-image:url('" + ui.safeText(cover) + "')" : "";

        return (
          '<a class="nw-provider-card" href="' + ui.safeText(providerLink) + '">' +
          '<div class="nw-provider-cover" style="' + coverStyle + '"></div>' +
          '<div class="nw-provider-body">' +
          '<div class="nw-provider-top">' +
          avatarHtml +
          '<div class="nw-provider-meta">' +
          '<div class="nw-provider-name-row">' +
          '<p class="nw-provider-name">' + ui.safeText(name) + "</p>" +
          (isVerified
            ? '<span class="' + verifiedClass + ' material-icons-round">verified</span>'
            : "") +
          "</div>" +
          '<p class="nw-provider-city">' + ui.safeText(city || "—") + "</p>" +
          "</div>" +
          "</div>" +
          '<div class="nw-provider-stats">' +
          '<span class="nw-provider-stat nw-provider-stat--rating"><span class="material-icons-round">star</span>' +
          ui.safeText(ratingText) +
          "</span>" +
          '<span class="nw-provider-stat"><span class="material-icons-round">people</span>' +
          ui.safeText(followers) +
          "</span>" +
          '<span class="nw-provider-stat"><span class="material-icons-round">favorite</span>' +
          ui.safeText(likes) +
          "</span>" +
          "</div>" +
          "</div>" +
          "</a>"
        );
      })
      .join("");
  }

  function renderBanners(items) {
    const root = document.getElementById("banners-list");
    if (!root) return;

    if (!items.length) {
      root.innerHTML =
        '<div class="nw-home-empty">' +
        '<span class="material-icons-round">campaign</span>' +
        "<span>لا توجد حملات ترويجية مفعلة الآن</span>" +
        "</div>";
      return;
    }

    root.innerHTML = items
      .map(function (banner) {
        const imageUrl = mediaUrl(banner.file_url || banner.fileUrl || "");
        const providerId = banner.provider_id || banner.providerId || "";
        const caption = banner.caption || "عرض ترويجي";
        const provider = banner.provider_display_name || banner.providerDisplayName || "";
        const href = Number(providerId) > 0 ? providerProfileUrl(providerId) : "#";
        const imageStyle = imageUrl ? "background-image:url('" + ui.safeText(imageUrl) + "')" : "";

        return (
          '<a class="nw-banner-card" href="' + ui.safeText(href) + '">' +
          '<div class="nw-banner-image" style="' + imageStyle + '"></div>' +
          '<div class="nw-banner-overlay">' +
          '<p class="nw-banner-caption">' + ui.safeText(caption) + "</p>" +
          (provider ? '<p class="nw-banner-provider">' + ui.safeText(provider) + "</p>" : "") +
          "</div>" +
          "</a>"
        );
      })
      .join("");
  }

  function ensureReelBindings(root) {
    if (!root || root.dataset.reelsBound === "1") return;
    root.dataset.reelsBound = "1";

    root.addEventListener("mouseenter", stopReelsAutoScroll);
    root.addEventListener("mouseleave", startReelsAutoScroll);
    root.addEventListener("touchstart", stopReelsAutoScroll, { passive: true });
    root.addEventListener("touchend", startReelsAutoScroll, { passive: true });
  }

  function renderReels() {
    const root = document.getElementById("reels-strip");
    if (!root) return;

    const logos = [
      "/static/mobile_web/images/32.jpeg",
      "/static/mobile_web/images/841015.jpeg",
      "/static/mobile_web/images/879797.jpeg",
    ];

    const reelLink = urls.interactive || "#";
    let itemsHtml = "";
    for (let i = 0; i < 20; i += 1) {
      const logoHtml = '<img src="' + ui.safeText(logos[i % logos.length]) + '" alt="شعار">';
      itemsHtml +=
        '<a class="nw-reel-item" href="' + ui.safeText(reelLink) + '">' +
        '<div class="nw-reel-logo">' + logoHtml + "</div>" +
        "</a>";
    }

    /* duplicate strip so reset point is invisible during auto-scroll */
    root.innerHTML = itemsHtml + itemsHtml;
    ensureReelBindings(root);
    window.setTimeout(startReelsAutoScroll, 0);
  }

  function stopReelsAutoScroll() {
    if (reelsTimer) {
      window.clearInterval(reelsTimer);
      reelsTimer = null;
    }
  }

  function startReelsAutoScroll() {
    const root = document.getElementById("reels-strip");
    if (!root) return;

    stopReelsAutoScroll();
    reelsPos = 0;
    root.scrollLeft = 0;

    if (root.scrollWidth <= root.clientWidth) return;

    reelsTimer = window.setInterval(function () {
      const maxScroll = root.scrollWidth - root.clientWidth;
      if (maxScroll <= 0) return;

      reelsPos += 1;
      const half = maxScroll / 2;
      if (reelsPos >= half) {
        root.scrollLeft = 0;
        reelsPos = 0;
        return;
      }
      root.scrollLeft = reelsPos;
    }, 50);
  }

  function setupHeroVideoFallback() {
    const hero = document.querySelector(".nw-home-hero");
    const video = hero ? hero.querySelector(".nw-hero-video") : null;
    if (!hero || !video) return;

    let resolved = false;

    function failVideo() {
      if (resolved) return;
      resolved = true;
      hero.classList.add("nw-home-hero--no-video");
    }

    function okVideo() {
      resolved = true;
    }

    video.addEventListener("canplay", okVideo, { once: true });
    video.addEventListener("error", failVideo, { once: true });
    video.addEventListener("stalled", failVideo, { once: true });

    window.setTimeout(function () {
      if (resolved) return;
      if (video.readyState < 2) failVideo();
    }, 2500);
  }

  function updateHeroProviderCount(providersPayload) {
    const countElement = document.getElementById("hero-provider-count");
    if (!countElement) return;

    let providerCount = 0;
    if (providersPayload && typeof providersPayload.count === "number") {
      providerCount = providersPayload.count;
    } else {
      providerCount = asList(providersPayload).length;
    }

    if (providerCount > 0) {
      countElement.textContent = "أكثر من " + providerCount + " مقدم خدمة بين يديك";
    } else {
      countElement.textContent = "أكثر من 100 مقدم خدمة بين يديك";
    }
  }

  async function loadHomeData() {
    try {
      const [categoriesPayload, providersPayload, bannersPayload] = await Promise.all([
        api.get("/api/providers/categories/", { auth: false }),
        api.get("/api/providers/list/?page_size=10", { auth: false }),
        api.get("/api/promo/banners/home/?limit=6", { auth: false }),
      ]);

      const categories = asList(categoriesPayload);
      const providers = asList(providersPayload);
      const banners = asList(bannersPayload);

      renderCategories(categories);
      renderProviders(providers);
      renderBanners(banners);
      renderReels();
      updateHeroProviderCount(providersPayload);
    } catch (_error) {
      renderCategories([]);
      renderProviders([]);
      renderBanners([]);
      renderReels();
      updateHeroProviderCount(null);
    }
  }

  document.addEventListener("visibilitychange", function () {
    if (document.hidden) stopReelsAutoScroll();
    else startReelsAutoScroll();
  });

  window.addEventListener("beforeunload", stopReelsAutoScroll);

  document.addEventListener("DOMContentLoaded", function () {
    setupHeroVideoFallback();
    renderReels();
    loadHomeData();
  });
})();
