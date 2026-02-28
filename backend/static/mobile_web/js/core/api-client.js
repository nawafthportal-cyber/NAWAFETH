(function () {
  "use strict";

  const KEY_ACCESS = "nawafeth_access_token";
  const KEY_REFRESH = "nawafeth_refresh_token";
  const KEY_USER_ID = "nawafeth_user_id";
  const KEY_ROLE_STATE = "nawafeth_role_state";
  const KEY_PROVIDER_MODE = "nawafeth_is_provider_mode";

  const config = window.NAWAFETH_WEB_CONFIG || {};
  const urls = config.urls || {};

  function buildUrl(path) {
    if (/^https?:\/\//i.test(path)) {
      return path;
    }
    const base = (config.apiBaseUrl || window.location.origin || "").replace(/\/+$/, "");
    const normalized = path.startsWith("/") ? path : "/" + path;
    return base + normalized;
  }

  async function parseResponse(response) {
    const contentType = response.headers.get("content-type") || "";
    if (contentType.includes("application/json")) {
      return response.json();
    }
    const text = await response.text();
    return text ? { detail: text } : {};
  }

  function getSession() {
    return {
      access: localStorage.getItem(KEY_ACCESS) || "",
      refresh: localStorage.getItem(KEY_REFRESH) || "",
      userId: localStorage.getItem(KEY_USER_ID) || "",
      roleState: localStorage.getItem(KEY_ROLE_STATE) || "",
    };
  }

  function setSession(session) {
    if (session.access) {
      localStorage.setItem(KEY_ACCESS, session.access);
    }
    if (session.refresh) {
      localStorage.setItem(KEY_REFRESH, session.refresh);
    }
    if (session.userId !== undefined && session.userId !== null && session.userId !== "") {
      localStorage.setItem(KEY_USER_ID, String(session.userId));
    }
    if (session.roleState) {
      localStorage.setItem(KEY_ROLE_STATE, String(session.roleState));
    }
    syncTopbarAuthState();
  }

  function clearSession() {
    localStorage.removeItem(KEY_ACCESS);
    localStorage.removeItem(KEY_REFRESH);
    localStorage.removeItem(KEY_USER_ID);
    localStorage.removeItem(KEY_ROLE_STATE);
    localStorage.removeItem(KEY_PROVIDER_MODE);
    syncTopbarAuthState();
  }

  function isAuthenticated() {
    return Boolean(localStorage.getItem(KEY_ACCESS));
  }

  function isProviderMode() {
    return localStorage.getItem(KEY_PROVIDER_MODE) === "1";
  }

  function setProviderMode(enabled) {
    localStorage.setItem(KEY_PROVIDER_MODE, enabled ? "1" : "0");
  }

  function ensureProviderModeFromProfile(mePayload) {
    const canProvider = Boolean(
      mePayload &&
      (mePayload.is_provider === true || mePayload.has_provider_profile === true)
    );

    if (!canProvider) {
      setProviderMode(false);
      return false;
    }
    return isProviderMode();
  }

  function getErrorMessage(payload, fallback) {
    if (!payload) return fallback || "حدث خطأ غير متوقع";
    if (typeof payload === "string") return payload;
    if (payload.detail) return String(payload.detail);
    if (payload.error) return String(payload.error);
    const firstKey = Object.keys(payload)[0];
    if (!firstKey) return fallback || "حدث خطأ غير متوقع";
    const value = payload[firstKey];
    if (Array.isArray(value) && value.length > 0) return String(value[0]);
    if (typeof value === "string") return value;
    return fallback || "حدث خطأ غير متوقع";
  }

  async function refreshAccessToken() {
    const refresh = localStorage.getItem(KEY_REFRESH);
    if (!refresh) {
      return false;
    }

    try {
      const response = await fetch(buildUrl("/api/accounts/token/refresh/"), {
        method: "POST",
        headers: {
          "Accept": "application/json",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ refresh: refresh }),
      });
      const payload = await parseResponse(response);
      if (!response.ok || !payload.access) {
        clearSession();
        return false;
      }
      localStorage.setItem(KEY_ACCESS, String(payload.access));
      return true;
    } catch (_error) {
      clearSession();
      return false;
    }
  }

  async function request(method, path, options) {
    const opts = options || {};
    const auth = opts.auth !== false;
    const allowRetry = opts.retry !== false;
    const raw = opts.raw === true;
    const body = opts.body;
    const customHeaders = opts.headers || {};
    const isFormData = typeof FormData !== "undefined" && body instanceof FormData;

    const headers = {
      "Accept": "application/json",
      ...customHeaders,
    };
    if (!isFormData && body !== undefined && body !== null) {
      headers["Content-Type"] = "application/json";
    }

    if (auth) {
      const token = localStorage.getItem(KEY_ACCESS);
      if (token) {
        headers["Authorization"] = "Bearer " + token;
      }
    }

    const response = await fetch(buildUrl(path), {
      method: method,
      headers: headers,
      body: body === undefined || body === null ? undefined : (isFormData ? body : JSON.stringify(body)),
    });

    const payload = await parseResponse(response);

    if (response.status === 401 && auth && allowRetry) {
      const refreshed = await refreshAccessToken();
      if (refreshed) {
        return request(method, path, { ...opts, retry: false });
      }
    }

    if (raw) {
      return response;
    }

    if (!response.ok) {
      const error = new Error(getErrorMessage(payload, "HTTP " + response.status));
      error.status = response.status;
      error.payload = payload;
      throw error;
    }

    return payload;
  }

  function syncTopbarAuthState() {
    const authLink = document.getElementById("nav-auth-link");
    const logoutBtn = document.getElementById("nav-logout-btn");
    const mobileAuthLink = document.getElementById("mobile-auth-link");
    const mobileLogoutBtn = document.getElementById("mobile-logout-btn");

    if (isAuthenticated()) {
      if (authLink) authLink.hidden = true;
      if (logoutBtn) logoutBtn.hidden = false;
      if (mobileAuthLink) mobileAuthLink.hidden = true;
      if (mobileLogoutBtn) mobileLogoutBtn.hidden = false;
    } else {
      if (authLink) authLink.hidden = false;
      if (logoutBtn) logoutBtn.hidden = true;
      if (mobileAuthLink) mobileAuthLink.hidden = false;
      if (mobileLogoutBtn) mobileLogoutBtn.hidden = true;
    }
  }

  function safeText(value) {
    const val = value === undefined || value === null ? "" : String(value);
    return val
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");
  }

  function formatDateTime(dateValue) {
    if (!dateValue) return "-";
    const d = new Date(dateValue);
    if (Number.isNaN(d.getTime())) return "-";
    return d.toLocaleString("ar-SA");
  }

  function toIsoFromLocalInput(value) {
    if (!value) return "";
    const local = new Date(value);
    if (Number.isNaN(local.getTime())) return "";
    return local.toISOString();
  }

  document.addEventListener("DOMContentLoaded", function () {
    syncTopbarAuthState();

    function doLogout() {
      clearSession();
      window.location.href = urls.home || "/";
    }

    var logoutBtn = document.getElementById("nav-logout-btn");
    if (logoutBtn) logoutBtn.addEventListener("click", doLogout);

    var mobileLogoutBtn = document.getElementById("mobile-logout-btn");
    if (mobileLogoutBtn) mobileLogoutBtn.addEventListener("click", doLogout);
  });

  window.NawafethApi = Object.freeze({
    request: request,
    get: function (path, options) {
      return request("GET", path, options || {});
    },
    post: function (path, body, options) {
      return request("POST", path, { ...(options || {}), body: body });
    },
    patch: function (path, body, options) {
      return request("PATCH", path, { ...(options || {}), body: body });
    },
    put: function (path, body, options) {
      return request("PUT", path, { ...(options || {}), body: body });
    },
    delete: function (path, options) {
      return request("DELETE", path, options || {});
    },
    setSession: setSession,
    getSession: getSession,
    clearSession: clearSession,
    isAuthenticated: isAuthenticated,
    isProviderMode: isProviderMode,
    setProviderMode: setProviderMode,
    ensureProviderModeFromProfile: ensureProviderModeFromProfile,
    getErrorMessage: getErrorMessage,
    urls: urls,
  });

  window.NawafethUi = Object.freeze({
    safeText: safeText,
    formatDateTime: formatDateTime,
    toIsoFromLocalInput: toIsoFromLocalInput,
  });
})();
