(function () {
  "use strict";

  const api = window.NawafethApi;
  const ui = window.NawafethUi;
  if (!api || !ui) return;

  const dom = {
    loginRequired: document.getElementById("interactive-login-required"),
    content: document.getElementById("interactive-content"),
    tabs: document.getElementById("interactive-tabs"),
    panels: document.getElementById("interactive-panels"),
    error: document.getElementById("interactive-error"),
  };

  const state = {
    me: null,
    providerMode: false,
    activeTab: "following",
    following: [],
    followers: [],
    favorites: [],
    loading: {
      following: false,
      followers: false,
      favorites: false,
    },
    errors: {
      following: "",
      followers: "",
      favorites: "",
    },
  };

  function asList(payload) {
    if (Array.isArray(payload)) return payload;
    if (payload && Array.isArray(payload.results)) return payload.results;
    return [];
  }

  function mediaUrl(path) {
    if (!path) return "";
    const p = String(path);
    if (/^https?:\/\//i.test(p)) return p;
    return window.location.origin.replace(/\/+$/, "") + (p.startsWith("/") ? p : "/" + p);
  }

  function setError(message) {
    if (!dom.error) return;
    dom.error.textContent = message || "";
    dom.error.hidden = !message;
  }

  function safe(value, fallback) {
    if (value === undefined || value === null || value === "") return fallback || "-";
    return String(value);
  }

  function availableTabs() {
    const tabs = [
      { key: "following", icon: "people_outline", label: "من أتابع" },
      { key: "favorites", icon: "bookmark_outline", label: "مفضلتي" },
    ];
    if (state.providerMode) {
      tabs.splice(1, 0, { key: "followers", icon: "person_outline", label: "متابعيني" });
    }
    return tabs;
  }

  function showLoginRequired() {
    if (dom.loginRequired) dom.loginRequired.hidden = false;
    if (dom.content) dom.content.hidden = true;
  }

  function showMainContent() {
    if (dom.loginRequired) dom.loginRequired.hidden = true;
    if (dom.content) dom.content.hidden = false;
  }

  function renderTabs() {
    if (!dom.tabs) return;
    const tabs = availableTabs();
    if (!tabs.some(function (tab) { return tab.key === state.activeTab; })) {
      state.activeTab = tabs[0].key;
    }
    dom.tabs.innerHTML = tabs
      .map(function (tab) {
        return (
          '<button type="button" class="nw-interactive-tab' +
          (tab.key === state.activeTab ? ' is-active' : '') +
          '" data-tab="' + ui.safeText(tab.key) + '">' +
          '<span class="material-icons-round">' + ui.safeText(tab.icon) + '</span>' +
          ui.safeText(tab.label) +
          '</button>'
        );
      })
      .join('');
  }

  function emptyCard(icon, message) {
    return (
      '<div class="nw-interactive-empty">' +
      '<div class="nw-interactive-empty-icon"><span class="material-icons-round">' + ui.safeText(icon || 'info') + '</span></div>' +
      '<p>' + ui.safeText(message) + '</p></div>'
    );
  }

  function loadingCard() {
    return '<div class="nw-interactive-empty"><p>جاري التحميل...</p></div>';
  }

  function errorCard(message, retryAction) {
    return (
      '<div class="nw-interactive-empty">' +
      '<div class="nw-interactive-empty-icon"><span class="material-icons-round">cloud_off</span></div>' +
      '<p>' + ui.safeText(message || 'تعذر تحميل البيانات') + '</p>' +
      '<button type="button" class="nw-retry-btn" data-action="' + ui.safeText(retryAction) + '">' +
      '<span class="material-icons-round">refresh</span>إعادة المحاولة</button></div>'
    );
  }

  function renderFollowingPanel() {
    if (state.loading.following) return loadingCard();
    if (state.errors.following) return errorCard(state.errors.following, 'reload-following');
    if (!state.following.length) return emptyCard('group_off', 'لا تتابع أي مزود خدمة حتى الآن');

    return (
      '<div class="nw-following-grid">' +
      state.following
        .map(function (provider) {
          var cover = mediaUrl(provider.cover_image || '');
          var avatar = mediaUrl(provider.profile_image || '');
          var initial = safe(provider.display_name, '؟').charAt(0);
          var verified = provider.is_verified
            ? '<span class="material-icons-round nw-verified-icon">verified</span>'
            : '';
          var coverHtml = cover
            ? '<div class="nw-following-cover" style="background-image:url(\'' + ui.safeText(cover) + '\')"></div>'
            : '<div class="nw-following-cover"><span class="material-icons-round">image</span></div>';
          var avatarStyle = avatar
            ? ' style="background-image:url(\'' + ui.safeText(avatar) + '\');background-size:cover;background-position:center"'
            : '';

          return (
            '<article class="nw-following-card">' +
            '<div class="nw-following-header">' +
            '<div class="nw-following-avatar"' + avatarStyle + '>' + (avatar ? '' : ui.safeText(initial)) + '</div>' +
            '<div class="nw-following-info">' +
            '<p class="nw-following-name">' + ui.safeText(safe(provider.display_name, 'مزود خدمة')) + verified + '</p>' +
            (provider.city ? '<p class="nw-following-city">' + ui.safeText(provider.city) + '</p>' : '') +
            '</div>' +
            '<button type="button" class="nw-following-chat-btn" title="مراسلة"><span class="material-icons-round">chat_bubble_outline</span></button>' +
            '</div>' +
            coverHtml +
            '<div class="nw-following-stats">' +
            '<span class="nw-following-stat"><span class="material-icons-round">people_outline</span>' + ui.safeText(safe(provider.followers_count, 0)) + '</span>' +
            '<span class="nw-following-stat"><span class="material-icons-round">favorite_outline</span>' + ui.safeText(safe(provider.likes_count, 0)) + '</span>' +
            (Number(provider.rating_avg) > 0 ? '<span class="nw-following-stat"><span class="material-icons-round">star_outline</span>' + ui.safeText(Number(provider.rating_avg).toFixed(1)) + '</span>' : '') +
            '</div>' +
            '<div class="nw-following-actions">' +
            '<button type="button" class="nw-unfollow-btn" data-action="unfollow" data-provider-id="' + ui.safeText(provider.id) + '">إلغاء المتابعة</button>' +
            '</div>' +
            '</article>'
          );
        })
        .join('') +
      '</div>'
    );
  }

  function renderFollowersPanel() {
    if (!state.providerMode) return '';
    if (state.loading.followers) return loadingCard();
    if (state.errors.followers) return errorCard(state.errors.followers, 'reload-followers');
    if (!state.followers.length) return emptyCard('person_off', 'لا يوجد متابعون بعد');

    return (
      '<div class="nw-followers-list">' +
      state.followers
        .map(function (user) {
          var initial = safe(user.display_name, '؟').charAt(0);
          return (
            '<div class="nw-follower-tile">' +
            '<div class="nw-follower-avatar">' + ui.safeText(initial) + '</div>' +
            '<div class="nw-follower-info">' +
            '<p class="nw-follower-name">' + ui.safeText(safe(user.display_name, 'مستخدم')) + '</p>' +
            '<p class="nw-follower-username">@' + ui.safeText(safe(user.username, '---')) + '</p>' +
            '</div>' +
            '<button type="button" class="nw-follower-chat-btn" title="مراسلة">' +
            '<span class="material-icons-round">chat_bubble_outline</span>مراسلة</button>' +
            '</div>'
          );
        })
        .join('') +
      '</div>'
    );
  }

  function renderFavoritesPanel() {
    if (state.loading.favorites) return loadingCard();
    if (state.errors.favorites) return errorCard(state.errors.favorites, 'reload-favorites');
    if (!state.favorites.length) return emptyCard('bookmark_outline', 'لا توجد عناصر محفوظة في المفضلة');

    return (
      '<div class="nw-favorites-grid">' +
      state.favorites
        .map(function (item) {
          var image = mediaUrl(item.thumbnail_url || item.file_url || '');
          var isVideo = /\.(mp4|mov|webm|avi)/i.test(safe(item.file_url, ''));
          var sourceClass = item.__source === 'spotlight' ? 'source-spotlight' : 'source-portfolio';
          var sourceLabel = item.__source === 'spotlight' ? 'أضواء' : 'معرض';

          var imageHtml = image
            ? '<img class="nw-favorite-image" src="' + ui.safeText(image) + '" alt="" loading="lazy">'
            : '<div class="nw-favorite-placeholder"><span class="material-icons-round">broken_image</span></div>';

          return (
            '<article class="nw-favorite-card">' +
            imageHtml +
            (isVideo ? '<div class="nw-favorite-video-icon"><span class="material-icons-round">play_arrow</span></div>' : '') +
            '<span class="nw-favorite-source ' + sourceClass + '">' + ui.safeText(sourceLabel) + '</span>' +
            '<div class="nw-favorite-overlay">' +
            '<p class="nw-favorite-provider-name">' + ui.safeText(safe(item.provider_display_name, 'مزود خدمة')) + '</p>' +
            '<button type="button" class="nw-favorite-remove-btn" data-action="unsave" data-item-id="' + ui.safeText(item.id) + '" data-source="' + ui.safeText(item.__source) + '">' +
            '<span class="material-icons-round">favorite</span></button>' +
            '</div></article>'
          );
        })
        .join('') +
      '</div>'
    );
  }

  function renderPanels() {
    if (!dom.panels) return;
    const tabs = availableTabs();
    dom.panels.innerHTML = tabs
      .map(function (tab) {
        let content = "";
        if (tab.key === "following") content = renderFollowingPanel();
        if (tab.key === "followers") content = renderFollowersPanel();
        if (tab.key === "favorites") content = renderFavoritesPanel();
        return (
          '<section class="nw-interactive-panel' +
          (tab.key === state.activeTab ? " is-active" : "") +
          '" data-panel="' +
          ui.safeText(tab.key) +
          '">' +
          content +
          "</section>"
        );
      })
      .join("");
  }

  async function loadFollowing() {
    state.loading.following = true;
    state.errors.following = "";
    try {
      const payload = await api.get("/api/providers/me/following/");
      state.following = asList(payload);
    } catch (error) {
      state.following = [];
      state.errors.following = api.getErrorMessage(error && error.payload, error.message || "تعذر تحميل المتابَعين");
    } finally {
      state.loading.following = false;
    }
  }

  async function loadFollowers() {
    if (!state.providerMode) {
      state.followers = [];
      state.errors.followers = "";
      state.loading.followers = false;
      return;
    }
    state.loading.followers = true;
    state.errors.followers = "";
    try {
      const payload = await api.get("/api/providers/me/followers/");
      state.followers = asList(payload);
    } catch (error) {
      state.followers = [];
      state.errors.followers = api.getErrorMessage(error && error.payload, error.message || "تعذر تحميل المتابعين");
    } finally {
      state.loading.followers = false;
    }
  }

  async function loadFavorites() {
    state.loading.favorites = true;
    state.errors.favorites = "";
    try {
      const results = await Promise.all([
        api.get("/api/providers/me/favorites/"),
        api.get("/api/providers/me/favorites/spotlights/"),
      ]);
      const portfolio = asList(results[0]).map(function (item) {
        return { ...item, __source: "portfolio" };
      });
      const spotlights = asList(results[1]).map(function (item) {
        return { ...item, __source: "spotlight" };
      });
      state.favorites = portfolio.concat(spotlights);
      state.favorites.sort(function (a, b) {
        const ad = new Date(safe(a.created_at, "1970-01-01T00:00:00Z")).getTime();
        const bd = new Date(safe(b.created_at, "1970-01-01T00:00:00Z")).getTime();
        return bd - ad;
      });
    } catch (error) {
      state.favorites = [];
      state.errors.favorites = api.getErrorMessage(error && error.payload, error.message || "تعذر تحميل المفضلة");
    } finally {
      state.loading.favorites = false;
    }
  }

  async function reloadAllData() {
    setError("");
    await Promise.all([loadFollowing(), loadFollowers(), loadFavorites()]);
    renderTabs();
    renderPanels();
  }

  async function handleActionClick(event) {
    const button = event.target.closest("button[data-action]");
    if (!button) return;
    const action = button.getAttribute("data-action");
    if (!action) return;
    button.disabled = true;
    setError("");
    try {
      if (action === "reload-following") {
        await loadFollowing();
      } else if (action === "reload-followers") {
        await loadFollowers();
      } else if (action === "reload-favorites") {
        await loadFavorites();
      } else if (action === "unfollow") {
        const providerId = Number(button.getAttribute("data-provider-id"));
        if (Number.isFinite(providerId) && providerId > 0) {
          await api.post("/api/providers/" + String(providerId) + "/unfollow/", {});
          state.following = state.following.filter(function (item) {
            return Number(item.id) !== providerId;
          });
        }
      } else if (action === "unsave") {
        const itemId = Number(button.getAttribute("data-item-id"));
        const source = String(button.getAttribute("data-source") || "portfolio");
        if (Number.isFinite(itemId) && itemId > 0) {
          const path =
            source === "spotlight"
              ? "/api/providers/spotlights/" + String(itemId) + "/unsave/"
              : "/api/providers/portfolio/" + String(itemId) + "/unsave/";
          await api.post(path, {});
          state.favorites = state.favorites.filter(function (item) {
            return Number(item.id) !== itemId || String(item.__source) !== source;
          });
        }
      }
      renderTabs();
      renderPanels();
    } catch (error) {
      setError(api.getErrorMessage(error && error.payload, error.message || "تعذر تنفيذ الإجراء"));
    } finally {
      button.disabled = false;
    }
  }

  function handleTabClick(event) {
    const tab = event.target.closest(".nw-interactive-tab[data-tab]");
    if (!tab) return;
    state.activeTab = tab.getAttribute("data-tab") || "following";
    renderTabs();
    renderPanels();
  }

  async function init() {
    if (!api.isAuthenticated()) {
      showLoginRequired();
      return;
    }

    showMainContent();
    if (dom.tabs) dom.tabs.addEventListener("click", handleTabClick);
    if (dom.panels) dom.panels.addEventListener("click", handleActionClick);

    try {
      state.me = await api.get("/api/accounts/me/");
      state.providerMode = api.ensureProviderModeFromProfile(state.me || {});
      await reloadAllData();
    } catch (error) {
      const status = Number(error && error.status ? error.status : 0);
      if (status === 401) {
        api.clearSession();
        showLoginRequired();
        return;
      }
      setError(api.getErrorMessage(error && error.payload, error.message || "تعذر تحميل الصفحة"));
      renderTabs();
      renderPanels();
    }
  }

  document.addEventListener("DOMContentLoaded", init);
})();
