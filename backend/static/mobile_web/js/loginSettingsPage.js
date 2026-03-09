"use strict";

const LoginSettingsPage = (() => {
  let _profile = null;
  let _mode = "client";
  let _toastTimer = null;

  function init() {
    if (!Auth.isLoggedIn()) {
      window.location.href = "/login/?next=" + encodeURIComponent(window.location.pathname);
      return;
    }
    _mode = _resolveMode();
    _bindEvents();
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
    _on("ls-logout", "click", _logout);
    _on("ls-delete", "click", _deleteAccount);

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
    const pin = _norm(_val("ls-pin"));
    const confirmPin = _norm(_val("ls-pin-confirm"));

    if (!/^\d{4,6}$/.test(pin)) {
      _toast("أدخل رمز أمان من 4 إلى 6 أرقام.", true);
      return;
    }
    if (pin !== confirmPin) {
      _toast("رمز الأمان غير متطابق.", true);
      return;
    }

    localStorage.setItem("nw_security_pin", pin);
    _setVal("ls-pin", "");
    _setVal("ls-pin-confirm", "");
    _closeModal("ls-security-modal");
    _toast("تم حفظ رمز الأمان.");
  }

  function _saveFaceIdCode() {
    // Legacy — replaced by WebAuthn enrollment
  }

  /* ── Face ID: WebAuthn Biometric Enrollment ── */

  function _initFaceId() {
    var btn = document.getElementById("ls-faceid-btn");
    var hint = document.getElementById("ls-faceid-hint");

    if (!window.PublicKeyCredential) {
      if (hint) hint.textContent = "متصفحك لا يدعم التحقق البيومتري.";
      if (btn) { btn.disabled = true; btn.style.opacity = "0.5"; }
      _updateFaceIdStatus();
      return;
    }

    PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable()
      .then(function (available) {
        if (!available) {
          if (hint) hint.textContent = "جهازك لا يدعم التحقق البيومتري (معرف الوجه / البصمة).";
          if (btn) { btn.disabled = true; btn.style.opacity = "0.5"; }
        }
        _updateFaceIdStatus();
      })
      .catch(function () {
        _updateFaceIdStatus();
      });
  }

  function _updateFaceIdStatus() {
    var isEnabled = localStorage.getItem("nw_faceid_enabled") === "1";
    var status = document.getElementById("ls-faceid-status");
    var btn = document.getElementById("ls-faceid-btn");

    if (status) status.classList.toggle("hidden", !isEnabled);
    if (btn) btn.classList.toggle("hidden", isEnabled);
  }

  async function _enrollFaceId() {
    var phone = _norm(_val("ls-phone")) || (_profile && _norm(_profile.phone));
    if (!phone) {
      _toast("لا يوجد رقم جوال مسجّل في الحساب.", true);
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

      var credIdArray = Array.from(new Uint8Array(credential.rawId));
      localStorage.setItem("nw_faceid_cred_id", JSON.stringify(credIdArray));
      localStorage.setItem("nw_faceid_phone", phone);
      localStorage.setItem("nw_faceid_enabled", "1");

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

  function _disableFaceId() {
    if (!window.confirm("هل تريد إلغاء تفعيل الدخول بمعرف الوجه؟")) return;
    localStorage.removeItem("nw_faceid_enabled");
    localStorage.removeItem("nw_faceid_cred_id");
    localStorage.removeItem("nw_faceid_phone");
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
    localStorage.removeItem("nw_security_pin");
    localStorage.removeItem("nw_faceid_enabled");
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

  document.addEventListener("DOMContentLoaded", init);
  return { init: init };
})();
