"use strict";

const LoginSettingsPage = (() => {
  const FACE_ID_ENABLED_KEY = "nw_faceid_enabled";
  const FACE_ID_PHONE_KEY = "nw_faceid_phone";
  const FACE_ID_DEVICE_TOKEN_KEY = "nw_faceid_device_token";
  const FACE_ID_CRED_ID_KEY = "nw_faceid_cred_id";

  let _profile = null;
  let _mode = "client";
  let _toastTimer = null;
  let _biometricAvailable = false;
  let _supportContent = { help: null, info: null };

  function init() {
    if (!Auth.isLoggedIn()) {
      window.location.href = "/login/?next=" + encodeURIComponent(window.location.pathname);
      return;
    }
    _mode = _resolveMode();
    _bindEvents();
    _renderSupportContent();
    _loadSupportContent();
    _loadProfile();
  }

  function _resolveMode() {
    const mode = (sessionStorage.getItem("nw_account_mode") || "client").toLowerCase();
    return mode === "provider" ? "provider" : "client";
  }

  function _withMode(path) {
    const sep = path.includes("?") ? "&" : "?";
    return path + sep + "mode=" + encodeURIComponent(_mode);
  }

  function _bindEvents() {
    _on("ls-save", "click", _saveProfile);
    _on("ls-retry", "click", _loadProfile);

    _on("ls-security-btn", "click", () => _openModal("ls-security-modal"));
    _on("ls-pin-cancel", "click", () => _closeModal("ls-security-modal"));
    _on("ls-pin-save", "click", _savePin);

    _on("ls-faceid-btn", "click", _enrollFaceId);
    _on("ls-faceid-disable", "click", _disableFaceId);

    const securityModal = document.getElementById("ls-security-modal");
    if (securityModal) {
      securityModal.addEventListener("click", (event) => {
        if (event.target === securityModal) _closeModal("ls-security-modal");
      });
    }
  }

  async function _loadSupportContent() {
    try {
      const res = await ApiClient.get("/api/content/public/");
      if (!res.ok || !res.data || typeof res.data !== "object") return;
      const blocks = res.data.blocks && typeof res.data.blocks === "object" ? res.data.blocks : {};
      _supportContent = {
        help: _normalizeSupportBlock(blocks.settings_help),
        info: _normalizeSupportBlock(blocks.settings_info),
      };
      _renderSupportContent();
    } catch (_) {
      // Optional content; ignore failures.
    }
  }

  async function _loadProfile() {
    _setLoading(true);
    _setError("");

    const res = await ApiClient.get(_withMode("/api/accounts/me/"));
    if (res.status === 401) {
      window.location.href = "/login/?next=" + encodeURIComponent(window.location.pathname);
      return;
    }
    if (!res.ok || !res.data) {
      _setLoading(false);
      _setError(_extractError(res, "تعذر تحميل بيانات الحساب."));
      return;
    }

    _profile = res.data;
    _fillProfile(_profile);
    _setLoading(false);
    _setContentVisible(true);
    _initFaceId();
  }

  function _fillProfile(profile) {
    const firstName = _norm(profile.first_name);
    const lastName = _norm(profile.last_name);
    const displayName = (firstName + " " + lastName).trim() || _norm(profile.username) || "مستخدم";
    const email = _norm(profile.email);
    const phone = _norm(profile.phone);
    const username = _norm(profile.username);

    _setVal("ls-username", username);
    _setVal("ls-first-name", firstName);
    _setVal("ls-last-name", lastName);
    _setVal("ls-phone", phone);
    _setVal("ls-email", email);

    _setText("ls-name", displayName);
    _setText("ls-email-display", email || phone);
    _renderAvatar(displayName, _norm(profile.profile_image));
  }

  function _renderAvatar(displayName, profileImage) {
    const avatar = document.getElementById("ls-avatar");
    if (!avatar) return;

    avatar.innerHTML = "";
    if (profileImage) {
      const img = document.createElement("img");
      img.src = ApiClient.mediaUrl(profileImage);
      img.alt = displayName;
      img.loading = "lazy";
      img.addEventListener("error", () => {
        img.remove();
        avatar.textContent = (displayName || "م").charAt(0);
      }, { once: true });
      avatar.appendChild(img);
      return;
    }
    avatar.textContent = (displayName || "م").charAt(0);
  }

  async function _saveProfile() {
    if (!_profile) return;

    const next = {
      first_name: _norm(_val("ls-first-name")),
      last_name: _norm(_val("ls-last-name")),
      phone: _norm(_val("ls-phone")),
      email: _norm(_val("ls-email")),
    };

    const data = {};
    if (next.first_name !== _norm(_profile.first_name)) data.first_name = next.first_name;
    if (next.last_name !== _norm(_profile.last_name)) data.last_name = next.last_name;
    if (next.phone !== _norm(_profile.phone)) data.phone = next.phone;
    if (next.email !== _norm(_profile.email)) data.email = next.email;

    if (!Object.keys(data).length) {
      _toast("لا يوجد تغييرات.");
      return;
    }

    const btn = document.getElementById("ls-save");
    if (btn) {
      btn.disabled = true;
      btn.textContent = "جاري الحفظ...";
    }

    const res = await ApiClient.request(_withMode("/api/accounts/me/"), {
      method: "PATCH",
      body: data,
    });

    if (btn) {
      btn.disabled = false;
      btn.textContent = "حفظ التغييرات";
    }

    if (!res.ok || !res.data) {
      _toast(_extractError(res, "فشل حفظ التغييرات."), true);
      return;
    }

    _profile = res.data;
    _fillProfile(_profile);
    _toast("تم حفظ التغييرات بنجاح.");
  }

  function _savePin() {
    _setVal("ls-pin", "");
    _setVal("ls-pin-confirm", "");
    _closeModal("ls-security-modal");
    _toast("تم حفظ رمز الأمان.");
  }

  function _normalizeSupportBlock(block) {
    if (!block || typeof block !== "object") return null;
    const title = _pickFirstText([block.title_ar, block.title, block.name]);
    const body = _pickFirstText([block.body_ar, block.body, block.description]);
    const mediaUrl = _pickFirstText([block.media_url, block.image_url, block.url]);
    const mediaType = _pickFirstText([block.media_type, block.type]);
    if (!title && !body && !mediaUrl) return null;
    return { title, body, mediaUrl, mediaType };
  }

  function _renderSupportContent() {
    _setSupportCard("ls-help-card", _supportContent.help, {
      title: "مساعدة",
      icon: "help",
      className: "ls-support-help",
    });
    _setSupportCard("ls-info-card", _supportContent.info, {
      title: "معلومات",
      icon: "info",
      className: "ls-support-info",
    });
  }

  function _setSupportCard(id, block, options) {
    const card = document.getElementById(id);
    if (!card) return;
    card.innerHTML = "";
    if (!block) {
      card.classList.add("hidden");
      return;
    }

    card.classList.remove("hidden");
    card.classList.remove("ls-support-help", "ls-support-info");
    if (options && options.className) card.classList.add(options.className);

    const head = document.createElement("div");
    head.className = "ls-support-head";
    const iconWrap = document.createElement("span");
    iconWrap.className = "ls-support-icon";
    iconWrap.appendChild(_supportIcon(options && options.icon));
    const heading = document.createElement("h3");
    heading.className = "ls-support-title";
    heading.textContent = block.title || (options && options.title) || "";
    head.appendChild(iconWrap);
    head.appendChild(heading);
    card.appendChild(head);

    const mediaUrl = block.mediaUrl ? ApiClient.mediaUrl(block.mediaUrl) : "";
    if (mediaUrl) {
      const media = _buildSupportMedia(mediaUrl, block.mediaType, heading.textContent || "media");
      if (media) card.appendChild(media);
    }

    if (block.body) {
      const body = document.createElement("p");
      body.className = "ls-support-body";
      body.textContent = block.body;
      card.appendChild(body);
    }
  }

  function _buildSupportMedia(url, mediaType, alt) {
    const wrap = document.createElement("div");
    wrap.className = "ls-support-media";
    const type = _norm(mediaType).toLowerCase();
    const isVideo = type.includes("video");
    if (isVideo) {
      const video = document.createElement("video");
      video.className = "ls-support-media-video";
      video.controls = true;
      video.preload = "metadata";
      video.src = url;
      wrap.appendChild(video);
      return wrap;
    }
    const img = document.createElement("img");
    img.className = "ls-support-media-image";
    img.src = url;
    img.alt = alt || "media";
    img.loading = "lazy";
    img.addEventListener("error", () => {
      if (wrap.parentNode) wrap.remove();
    }, { once: true });
    wrap.appendChild(img);
    return wrap;
  }

  function _supportIcon(kind) {
    const svgNS = "http://www.w3.org/2000/svg";
    const svg = document.createElementNS(svgNS, "svg");
    svg.setAttribute("width", "18");
    svg.setAttribute("height", "18");
    svg.setAttribute("viewBox", "0 0 24 24");
    svg.setAttribute("fill", "none");
    svg.setAttribute("stroke", "currentColor");
    svg.setAttribute("stroke-width", "2");
    svg.setAttribute("stroke-linecap", "round");
    svg.setAttribute("stroke-linejoin", "round");

    if (kind === "help") {
      const circle = document.createElementNS(svgNS, "circle");
      circle.setAttribute("cx", "12");
      circle.setAttribute("cy", "12");
      circle.setAttribute("r", "10");
      const p1 = document.createElementNS(svgNS, "path");
      p1.setAttribute("d", "M9.09 9a3 3 0 1 1 5.82 1c0 2-3 2-3 4");
      const p2 = document.createElementNS(svgNS, "path");
      p2.setAttribute("d", "M12 17h.01");
      svg.appendChild(circle);
      svg.appendChild(p1);
      svg.appendChild(p2);
      return svg;
    }

    const circle = document.createElementNS(svgNS, "circle");
    circle.setAttribute("cx", "12");
    circle.setAttribute("cy", "12");
    circle.setAttribute("r", "10");
    const p1 = document.createElementNS(svgNS, "path");
    p1.setAttribute("d", "M12 16v-4");
    const p2 = document.createElementNS(svgNS, "path");
    p2.setAttribute("d", "M12 8h.01");
    svg.appendChild(circle);
    svg.appendChild(p1);
    svg.appendChild(p2);
    return svg;
  }

  function _saveFaceIdCode() {
    // Legacy — replaced by WebAuthn enrollment
  }

  /* ── Face ID: WebAuthn Biometric Enrollment ── */

  function _initFaceId() {
    var btn = document.getElementById("ls-faceid-btn");
    var hint = document.getElementById("ls-faceid-hint");
    var unavailable = document.getElementById("ls-faceid-unavailable");

    if (!window.PublicKeyCredential) {
      _biometricAvailable = false;
      if (hint) hint.textContent = "متصفحك لا يدعم التحقق البيومتري.";
      if (unavailable) unavailable.classList.remove("hidden");
      if (btn) {
        btn.disabled = true;
        btn.style.opacity = "0.5";
      }
      _updateFaceIdStatus();
      return;
    }

    PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable()
      .then(function (available) {
        _biometricAvailable = !!available;
        if (!available) {
          if (unavailable) unavailable.classList.remove("hidden");
          if (hint) hint.textContent = "جهازك لا يدعم التحقق البيومتري (معرف الوجه / البصمة).";
          if (btn) {
            btn.disabled = true;
            btn.style.opacity = "0.5";
          }
        } else if (btn) {
          if (unavailable) unavailable.classList.add("hidden");
          btn.disabled = false;
          btn.style.opacity = "";
          if (hint) hint.textContent = "";
        }
        _updateFaceIdStatus();
      })
      .catch(function () {
        _biometricAvailable = false;
        if (unavailable) unavailable.classList.remove("hidden");
        _updateFaceIdStatus();
      });
  }

  function _updateFaceIdStatus() {
    var hasStoredData = !!_getStoredBiometricData();
    var isEnabled = _biometricAvailable && hasStoredData;
    var status = document.getElementById("ls-faceid-status");
    var btn = document.getElementById("ls-faceid-btn");
    var unavailable = document.getElementById("ls-faceid-unavailable");
    var hideEnrollBtn = isEnabled || !_biometricAvailable;

    if (status) status.classList.toggle("hidden", !isEnabled);
    if (btn) btn.classList.toggle("hidden", hideEnrollBtn);
    if (unavailable) unavailable.classList.toggle("hidden", _biometricAvailable);
  }

  async function _enrollFaceId() {
    var phone = _normalizePhone05(_norm(_val("ls-phone")) || (_profile && _norm(_profile.phone)));
    if (!phone) {
      _toast("تعذر تحديد رقم الجوال المرتبط بالحساب.", true);
      return;
    }

    var displayName = (
      (_norm(_val("ls-first-name")) + " " + _norm(_val("ls-last-name"))).trim()
      || _norm(_profile && _profile.username)
      || "مستخدم"
    );

    var btn = document.getElementById("ls-faceid-btn");
    if (btn) { btn.disabled = true; btn.style.opacity = "0.65"; }

    try {
      var challenge = new Uint8Array(32);
      crypto.getRandomValues(challenge);

      var userId = new TextEncoder().encode(phone);

      var credential = await navigator.credentials.create({
        publicKey: {
          challenge: challenge,
          rp: { name: "نوافذ" },
          user: {
            id: userId,
            name: phone,
            displayName: displayName,
          },
          pubKeyCredParams: [
            { alg: -7,   type: "public-key" },
            { alg: -257, type: "public-key" },
          ],
          authenticatorSelection: {
            authenticatorAttachment: "platform",
            userVerification: "required",
            residentKey: "preferred",
          },
          timeout: 60000,
        },
      });

      var enrollRes = await ApiClient.request("/api/accounts/biometric/enroll/", {
        method: "POST",
        body: {},
      });

      var deviceToken = _extractDeviceToken(enrollRes);
      if (!enrollRes.ok || !deviceToken) {
        _toast(_extractError(enrollRes, "فشل تسجيل المصادقة البيومترية."), true);
        return;
      }

      var credIdArray = Array.from(new Uint8Array(credential.rawId || []));
      _storageSet(FACE_ID_CRED_ID_KEY, JSON.stringify(credIdArray));
      _storageSet(FACE_ID_PHONE_KEY, phone);
      _storageSet(FACE_ID_DEVICE_TOKEN_KEY, deviceToken);
      _storageSet(FACE_ID_ENABLED_KEY, "1");

      _updateFaceIdStatus();
      _toast("تم تفعيل الدخول بمعرف الوجه بنجاح ✓");
    } catch (err) {
      if (err.name === "NotAllowedError") {
        _toast("تم إلغاء عملية التحقق البيومتري.", true);
      } else {
        _toast("فشل تسجيل معرف الوجه.", true);
      }
    } finally {
      if (btn) { btn.disabled = false; btn.style.opacity = ""; }
    }
  }

  async function _disableFaceId() {
    if (!window.confirm("هل تريد إلغاء تفعيل الدخول بمعرف الوجه؟")) return;

    var revokeRes = await ApiClient.request("/api/accounts/biometric/revoke/", {
      method: "POST",
      body: {},
    });
    if (!revokeRes.ok) {
      _toast(_extractError(revokeRes, "تعذر إلغاء التفعيل من الخادم."), true);
    }

    _clearStoredBiometricData();
    _updateFaceIdStatus();
    _toast("تم إلغاء تفعيل معرف الوجه.");
  }

  async function _logout() {
    const confirmed = window.confirm("هل تريد تسجيل الخروج الآن؟");
    if (!confirmed) return;

    const refresh = Auth.getRefreshToken();
    if (refresh) {
      await ApiClient.request("/api/accounts/logout/", {
        method: "POST",
        body: { refresh: refresh },
      });
    }
    Auth.logout();
    window.location.href = "/login/";
  }

  async function _deleteAccount() {
    const first = window.confirm("سيتم حذف حسابك نهائيًا. هل أنت متأكد؟");
    if (!first) return;
    const second = window.confirm("هذا الإجراء غير قابل للتراجع. متابعة؟");
    if (!second) return;

    const res = await ApiClient.request(_withMode("/api/accounts/me/"), { method: "DELETE" });
    if (!res.ok) {
      _toast(_extractError(res, "فشل حذف الحساب."), true);
      return;
    }
    Auth.logout();
    _clearStoredBiometricData();
    window.location.href = "/";
  }

  function _openModal(id) {
    const modal = document.getElementById(id);
    if (modal) modal.classList.remove("hidden");
  }

  function _closeModal(id) {
    const modal = document.getElementById(id);
    if (modal) modal.classList.add("hidden");
  }

  function _setLoading(isLoading) {
    const loading = document.getElementById("ls-loading");
    if (loading) loading.classList.toggle("hidden", !isLoading);
    if (isLoading) _setContentVisible(false);
  }

  function _setError(message) {
    const errorCard = document.getElementById("ls-error");
    const text = document.getElementById("ls-error-text");
    if (!errorCard) return;
    const hasError = !!_norm(message);
    errorCard.classList.toggle("hidden", !hasError);
    if (text) text.textContent = message || "";
  }

  function _setContentVisible(visible) {
    const content = document.getElementById("ls-content");
    if (content) content.classList.toggle("hidden", !visible);
  }

  function _extractError(res, fallback) {
    const data = res && res.data;
    if (data && typeof data === "object") {
      if (typeof data.detail === "string" && data.detail.trim()) return data.detail.trim();
      const keys = Object.keys(data);
      for (let i = 0; i < keys.length; i += 1) {
        const value = data[keys[i]];
        if (Array.isArray(value) && value.length) return String(value[0]);
        if (typeof value === "string" && value.trim()) return value.trim();
      }
    }
    return fallback;
  }

  function _toast(message, isError) {
    const toast = document.getElementById("ls-toast");
    if (!toast) {
      window.alert(message);
      return;
    }
    toast.textContent = message;
    toast.classList.toggle("error", !!isError);
    toast.classList.add("show");
    if (_toastTimer) window.clearTimeout(_toastTimer);
    _toastTimer = window.setTimeout(() => {
      toast.classList.remove("show");
    }, 2400);
  }

  function _on(id, eventName, handler) {
    const el = document.getElementById(id);
    if (el) el.addEventListener(eventName, handler);
  }

  function _setText(id, text) {
    const el = document.getElementById(id);
    if (el) el.textContent = text || "";
  }

  function _setVal(id, value) {
    const el = document.getElementById(id);
    if (el) el.value = value || "";
  }

  function _val(id) {
    const el = document.getElementById(id);
    return el ? el.value : "";
  }

  function _norm(value) {
    return (value == null ? "" : String(value)).trim();
  }

  function _pickFirstText(values) {
    if (!Array.isArray(values)) return "";
    for (let i = 0; i < values.length; i += 1) {
      const text = _norm(values[i]);
      if (text) return text;
    }
    return "";
  }

  function _normalizePhone05(value) {
    var digits = String(value || "").replace(/[^\d]/g, "");
    if (/^05\d{8}$/.test(digits)) return digits;
    if (/^5\d{8}$/.test(digits)) return "0" + digits;
    if (/^9665\d{8}$/.test(digits)) return "0" + digits.slice(3);
    if (/^009665\d{8}$/.test(digits)) return "0" + digits.slice(5);
    return "";
  }

  function _storageGet(key) {
    try {
      return localStorage.getItem(key);
    } catch (_) {
      return null;
    }
  }

  function _storageSet(key, value) {
    try {
      localStorage.setItem(key, value);
    } catch (_) {}
  }

  function _storageRemove(key) {
    try {
      localStorage.removeItem(key);
    } catch (_) {}
  }

  function _extractDeviceToken(res) {
    var data = res && res.data;
    if (!data || typeof data !== "object") return "";
    var token = String(data.device_token || "").trim();
    return token;
  }

  function _getStoredBiometricData() {
    var enabled = _storageGet(FACE_ID_ENABLED_KEY) === "1";
    var phone = _normalizePhone05(_storageGet(FACE_ID_PHONE_KEY) || "");
    var deviceToken = _norm(_storageGet(FACE_ID_DEVICE_TOKEN_KEY));
    if (!enabled || !phone || !deviceToken) return null;
    return {
      phone: phone,
      deviceToken: deviceToken,
      credJson: _norm(_storageGet(FACE_ID_CRED_ID_KEY)),
    };
  }

  function _clearStoredBiometricData() {
    _storageRemove(FACE_ID_ENABLED_KEY);
    _storageRemove(FACE_ID_PHONE_KEY);
    _storageRemove(FACE_ID_DEVICE_TOKEN_KEY);
    _storageRemove(FACE_ID_CRED_ID_KEY);
    // legacy keys
    _storageRemove("nw_faceid_cred_id");
    _storageRemove("nw_faceid_phone");
  }

  document.addEventListener("DOMContentLoaded", init);
  return { init: init };
})();
