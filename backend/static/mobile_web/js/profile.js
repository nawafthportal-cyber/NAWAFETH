(function () {
  "use strict";

  const api = window.NawafethApi;
  if (!api) return;

  const dom = {
    loginRequired: document.getElementById("profile-login-required"),
    content: document.getElementById("profile-content"),
    avatar: document.getElementById("profile-avatar"),
    displayName: document.getElementById("profile-display-name"),
    username: document.getElementById("profile-username"),
    following: document.getElementById("stat-following"),
    likes: document.getElementById("stat-likes"),
    favorites: document.getElementById("stat-favorites"),
    modeToggle: document.getElementById("profile-mode-toggle"),
    modeClient: document.getElementById("profile-mode-client"),
    modeProvider: document.getElementById("profile-mode-provider"),
    providerCTA: document.getElementById("profile-provider-cta"),
    providerRegisterBtn: document.getElementById("provider-register-btn"),
    menuSettingsInfo: document.getElementById("menu-settings-info"),
    menuFavoritesCount: document.getElementById("menu-favorites-count"),
    error: document.getElementById("profile-error"),
    logoutBtn: document.getElementById("profile-logout-btn"),
  };

  const state = {
    me: null,
    providerProfile: null,
    canSwitch: false,
    providerMode: false,
  };

  function safe(value, fallback) {
    if (value === undefined || value === null || value === "") return fallback || "-";
    return String(value);
  }

  function setError(message) {
    if (!dom.error) return;
    dom.error.textContent = message || "";
    dom.error.hidden = !message;
  }

  function setText(node, value, fallback) {
    if (!node) return;
    node.textContent = safe(value, fallback || "-");
  }

  function showLoginRequired() {
    if (dom.loginRequired) dom.loginRequired.hidden = false;
    if (dom.content) dom.content.hidden = true;
  }

  function showContent() {
    if (dom.loginRequired) dom.loginRequired.hidden = true;
    if (dom.content) dom.content.hidden = false;
  }

  function resolveDisplayName(me) {
    const first = String(me && me.first_name ? me.first_name : "").trim();
    const last = String(me && me.last_name ? me.last_name : "").trim();
    if (first || last) return (first + " " + last).trim();
    if (me && me.username) return String(me.username);
    if (me && me.phone) return String(me.phone);
    return "مستخدم";
  }

  function resolveUsernameDisplay(me) {
    const username = String(me && me.username ? me.username : "").trim();
    if (!username) return "@---";
    return username.startsWith("@") ? username : "@" + username;
  }

  async function loadProviderProfileIfAny() {
    state.providerProfile = null;
    if (!state.canSwitch) return;
    try {
      state.providerProfile = await api.get("/api/providers/me/profile/");
    } catch (_error) {
      state.providerProfile = null;
    }
  }

  function renderAvatar(displayName) {
    if (!dom.avatar) return;
    var image = state.providerProfile && state.providerProfile.profile_image
      ? String(state.providerProfile.profile_image) : "";
    if (image) {
      var absolute = /^https?:\/\//i.test(image)
        ? image
        : window.location.origin.replace(/\/+$/, "") + (image.startsWith("/") ? image : "/" + image);
      dom.avatar.style.backgroundImage = "url('" + absolute + "')";
      dom.avatar.innerHTML = "";
    } else {
      dom.avatar.style.backgroundImage = "";
      dom.avatar.innerHTML = '<span class="material-icons-round">person</span>';
    }
  }

  function renderModeToggle() {
    if (!dom.modeToggle) return;
    if (!state.canSwitch) {
      dom.modeToggle.hidden = true;
      /* Show provider CTA if not registered */
      if (dom.providerCTA) dom.providerCTA.hidden = false;
      return;
    }
    dom.modeToggle.hidden = false;
    if (dom.providerCTA) dom.providerCTA.hidden = true;

    if (dom.modeClient) dom.modeClient.classList.toggle("is-active", !state.providerMode);
    if (dom.modeProvider) dom.modeProvider.classList.toggle("is-active", state.providerMode);
  }

  function renderProfile() {
    var me = state.me || {};
    var displayName = resolveDisplayName(me);

    showContent();
    setText(dom.displayName, displayName, "مستخدم");
    setText(dom.username, resolveUsernameDisplay(me), "@---");

    setText(dom.following, me.following_count || 0, "0");
    setText(dom.likes, me.likes_count || 0, "0");
    var favCount = me.favorites_media_count || 0;
    setText(dom.favorites, favCount, "0");

    /* Menu settings info */
    var email = String(me.email || "").trim();
    var phone = String(me.phone || "").trim();
    if (dom.menuSettingsInfo) {
      dom.menuSettingsInfo.textContent = email || phone || "";
    }
    if (dom.menuFavoritesCount) {
      dom.menuFavoritesCount.textContent = String(favCount);
    }

    renderAvatar(displayName);
    renderModeToggle();
  }

  function switchToProviderMode() {
    if (!state.canSwitch) return;
    api.setProviderMode(true);
    state.providerMode = true;
    window.location.href = api.urls.providerDashboard || "/web/provider/dashboard/";
  }

  function switchToClientMode() {
    api.setProviderMode(false);
    state.providerMode = false;
    renderModeToggle();
  }

  function bindEvents() {
    if (dom.modeClient) {
      dom.modeClient.addEventListener("click", function () { switchToClientMode(); });
    }
    if (dom.modeProvider) {
      dom.modeProvider.addEventListener("click", function () { switchToProviderMode(); });
    }
    if (dom.logoutBtn) {
      dom.logoutBtn.addEventListener("click", function () {
        api.clearSession();
        window.location.href = api.urls.home || "/";
      });
    }
  }

  async function init() {
    bindEvents();
    if (!api.isAuthenticated()) {
      showLoginRequired();
      return;
    }

    try {
      setError("");
      state.me = await api.get("/api/accounts/me/");
      state.canSwitch = Boolean(
        state.me && (state.me.is_provider === true || state.me.has_provider_profile === true)
      );
      state.providerMode = api.ensureProviderModeFromProfile(state.me || {});
      await loadProviderProfileIfAny();
      renderProfile();
    } catch (error) {
      var status = Number(error && error.status ? error.status : 0);
      if (status === 401) {
        api.clearSession();
        showLoginRequired();
        return;
      }
      setError(api.getErrorMessage(error && error.payload, error.message || "تعذر تحميل بيانات الحساب"));
      showContent();
    }
  }

  document.addEventListener("DOMContentLoaded", init);
})();
