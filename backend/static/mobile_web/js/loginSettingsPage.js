"use strict";

const LoginSettingsPage = (() => {
  const SECURITY_PIN_KEY = "nw_security_pin";
  const FACE_ID_ENABLED_KEY = "nw_faceid_enabled";
  const FACE_ID_PHONE_KEY = "nw_faceid_phone";
  const FACE_ID_DEVICE_TOKEN_KEY = "nw_faceid_device_token";
  const FACE_ID_CRED_ID_KEY = "nw_faceid_cred_id";

  let _profile = null;
  let _mode = "client";
  let _toastTimer = null;
  let _currentAction = null;
  let _biometricAvailable = false;

  function init() {
    if (!Auth.isLoggedIn()) {
      window.location.href = "/login/?next=" + encodeURIComponent(window.location.pathname);
      return;
    }

    _mode = _resolveMode();
    _bindEvents();
    _loadProfile();
    _initBiometric();
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
    _on("ls-action-username", "click", () => _openModal("username"));
    _on("ls-action-password", "click", () => _openModal("password"));
    _on("ls-action-email", "click", () => _openModal("email"));
    _on("ls-action-phone", "click", () => _openModal("phone"));
    _on("ls-action-pin", "click", () => _openModal("pin"));
    _on("ls-action-faceid", "click", _handleFaceIdAction);

    _on("ls-modal-cancel", "click", _closeModal);
    _on("ls-modal-save", "click", _saveCurrentAction);

    const modal = document.getElementById("ls-action-modal");
    if (modal) {
      modal.addEventListener("click", (event) => {
        if (event.target === modal) _closeModal();
      });
    }
  }

  async function _loadProfile() {
    const res = await ApiClient.get(_withMode("/api/accounts/me/"));
    if (res.status === 401) {
      window.location.href = "/login/?next=" + encodeURIComponent(window.location.pathname);
      return;
    }
    if (res.ok && res.data) {
      _profile = res.data;
    }
  }

  function _openModal(action) {
    _currentAction = action;

    const titleEl = document.getElementById("ls-modal-title");
    const descEl = document.getElementById("ls-modal-desc");
    const fieldsEl = document.getElementById("ls-modal-fields");

    if (!titleEl || !descEl || !fieldsEl) return;

    const config = _modalConfig(action);
    titleEl.textContent = config.title;
    descEl.textContent = config.desc;
    fieldsEl.innerHTML = config.fields;

    const modal = document.getElementById("ls-action-modal");
    if (modal) modal.classList.remove("hidden");
  }

  function _closeModal() {
    const modal = document.getElementById("ls-action-modal");
    if (modal) modal.classList.add("hidden");
    _currentAction = null;
  }

  function _modalConfig(action) {
    if (action === "username") {
      return {
        title: "تغيير اسم العضوية",
        desc: "أدخل اسم العضوية الجديد. يسمح فقط بالأحرف الإنجليزية والأرقام و (_) و (.)",
        fields:
          '<input id="ls-input-username" type="text" class="form-input" maxlength="50" placeholder="اسم العضوية الجديد" value="' + _escape(_norm(_profile && _profile.username)) + '" dir="ltr">',
      };
    }
    if (action === "password") {
      return {
        title: "تغيير كلمة المرور",
        desc: "أدخل كلمة المرور الحالية ثم الجديدة (8 أحرف على الأقل).",
        fields:
          '<input id="ls-input-current-password" type="password" class="form-input" maxlength="128" placeholder="كلمة المرور الحالية" dir="ltr">' +
          '<input id="ls-input-new-password" type="password" class="form-input" maxlength="128" placeholder="كلمة المرور الجديدة" dir="ltr">' +
          '<input id="ls-input-new-password-confirm" type="password" class="form-input" maxlength="128" placeholder="تأكيد كلمة المرور الجديدة" dir="ltr">',
      };
    }
    if (action === "email") {
      return {
        title: "تغيير البريد الإلكتروني",
        desc: "أدخل البريد الإلكتروني الجديد المرتبط بحسابك.",
        fields:
          '<input id="ls-input-email" type="email" class="form-input" maxlength="255" placeholder="example@mail.com" value="' + _escape(_norm(_profile && _profile.email)) + '" dir="ltr">',
      };
    }
    if (action === "phone") {
      return {
        title: "تغيير رقم الجوال",
        desc: "أدخل رقم الجوال بالصيغة 05XXXXXXXX.",
        fields:
          '<input id="ls-input-phone" type="tel" class="form-input" maxlength="10" placeholder="05XXXXXXXX" value="' + _escape(_norm(_profile && _profile.phone)) + '" dir="ltr">',
      };
    }

    return {
      title: "إضافة رمز دخول أمان",
      desc: "احفظ الرمز في مكان آمن. يستخدم هذا الرمز للدخول السريع داخل الجهاز.",
      fields:
        '<input id="ls-input-pin" type="password" class="form-input" maxlength="6" placeholder="رمز الأمان (4-6 أرقام)" dir="ltr">' +
        '<input id="ls-input-pin-confirm" type="password" class="form-input" maxlength="6" placeholder="تأكيد الرمز" dir="ltr">',
    };
  }

  async function _saveCurrentAction() {
    const action = _currentAction;
    if (!action) return;

    if (action === "username") {
      await _saveUsername();
      return;
    }
    if (action === "password") {
      await _savePassword();
      return;
    }
    if (action === "email") {
      await _saveEmail();
      return;
    }
    if (action === "phone") {
      await _savePhone();
      return;
    }
    if (action === "pin") {
      _savePin();
    }
  }

  async function _saveUsername() {
    const username = _norm(_val("ls-input-username"));
    if (!username) {
      _toast("اسم العضوية مطلوب", true);
      return;
    }

    const res = await ApiClient.request("/api/accounts/change-username/", {
      method: "POST",
      body: { username: username },
    });

    if (!res.ok) {
      _toast(_extractError(res, "تعذر تغيير اسم العضوية."), true);
      return;
    }

    if (_profile) _profile.username = username;
    _closeModal();
    _toast("تم تغيير اسم العضوية بنجاح");
  }

  async function _savePassword() {
    const currentPassword = _val("ls-input-current-password");
    const newPassword = _val("ls-input-new-password");
    const newPasswordConfirm = _val("ls-input-new-password-confirm");

    if (!currentPassword || !newPassword || !newPasswordConfirm) {
      _toast("يرجى تعبئة جميع الحقول.", true);
      return;
    }

    const res = await ApiClient.request("/api/accounts/change-password/", {
      method: "POST",
      body: {
        current_password: currentPassword,
        new_password: newPassword,
        new_password_confirm: newPasswordConfirm,
      },
    });

    if (!res.ok) {
      _toast(_extractError(res, "تعذر تغيير كلمة المرور."), true);
      return;
    }

    _closeModal();
    _toast("تم تغيير كلمة المرور بنجاح");
  }

  async function _saveEmail() {
    const email = _norm(_val("ls-input-email"));
    const res = await ApiClient.request(_withMode("/api/accounts/me/"), {
      method: "PATCH",
      body: { email: email },
    });

    if (!res.ok) {
      _toast(_extractError(res, "تعذر تحديث البريد الإلكتروني."), true);
      return;
    }

    if (_profile) _profile.email = email;
    _closeModal();
    _toast("تم تحديث البريد الإلكتروني بنجاح");
  }

  async function _savePhone() {
    const phone = _normalizePhone05(_val("ls-input-phone"));
    if (!phone) {
      _toast("صيغة رقم الجوال يجب أن تكون 05XXXXXXXX", true);
      return;
    }

    const res = await ApiClient.request(_withMode("/api/accounts/me/"), {
      method: "PATCH",
      body: { phone: phone },
    });

    if (!res.ok) {
      _toast(_extractError(res, "تعذر تحديث رقم الجوال."), true);
      return;
    }

    if (_profile) _profile.phone = phone;
    _closeModal();
    _toast("تم تحديث رقم الجوال بنجاح");
  }

  function _savePin() {
    const pin = _norm(_val("ls-input-pin"));
    const pinConfirm = _norm(_val("ls-input-pin-confirm"));

    if (!/^\d{4,6}$/.test(pin)) {
      _toast("رمز الأمان يجب أن يكون من 4 إلى 6 أرقام.", true);
      return;
    }
    if (pin !== pinConfirm) {
      _toast("تأكيد الرمز غير مطابق.", true);
      return;
    }

    _storageSet(SECURITY_PIN_KEY, pin);
    _closeModal();
    _toast("تم حفظ رمز الأمان.");
  }

  function _initBiometric() {
    const btn = document.getElementById("ls-action-faceid");
    if (!btn) return;

    if (!window.PublicKeyCredential) {
      _biometricAvailable = false;
      btn.disabled = true;
      btn.textContent = "الدخول بمعرف الوجه (غير مدعوم على هذا الجهاز)";
      return;
    }

    PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable()
      .then((available) => {
        _biometricAvailable = !!available;
        _updateFaceButton();
      })
      .catch(() => {
        _biometricAvailable = false;
        _updateFaceButton();
      });
  }

  function _updateFaceButton() {
    const btn = document.getElementById("ls-action-faceid");
    if (!btn) return;

    if (!_biometricAvailable) {
      btn.disabled = true;
      btn.textContent = "الدخول بمعرف الوجه (غير مدعوم على هذا الجهاز)";
      return;
    }

    btn.disabled = false;
    btn.textContent = _getStoredBiometricData() ? "إلغاء الدخول بمعرف الوجه" : "الدخول بمعرف الوجه";
  }

  async function _handleFaceIdAction() {
    if (!_biometricAvailable) {
      _toast("الجهاز لا يدعم البصمة/الوجه", true);
      return;
    }

    if (_getStoredBiometricData()) {
      await _disableFaceId();
      return;
    }

    await _enrollFaceId();
  }

  async function _enrollFaceId() {
    const phone = _normalizePhone05(_norm(_profile && _profile.phone));
    if (!phone) {
      _toast("يرجى تحديث رقم الجوال أولاً", true);
      return;
    }

    const displayName = _norm(_profile && _profile.username) || "مستخدم";
    const btn = document.getElementById("ls-action-faceid");
    if (btn) btn.disabled = true;

    try {
      const challenge = new Uint8Array(32);
      crypto.getRandomValues(challenge);
      const userId = new TextEncoder().encode(phone);

      const credential = await navigator.credentials.create({
        publicKey: {
          challenge: challenge,
          rp: { name: "نوافذ" },
          user: {
            id: userId,
            name: phone,
            displayName: displayName,
          },
          pubKeyCredParams: [
            { alg: -7, type: "public-key" },
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

      const enrollRes = await ApiClient.request("/api/accounts/biometric/enroll/", {
        method: "POST",
        body: {},
      });

      const token = _extractDeviceToken(enrollRes);
      if (!enrollRes.ok || !token) {
        _toast(_extractError(enrollRes, "فشل تفعيل معرف الوجه."), true);
        return;
      }

      const credIdArray = Array.from(new Uint8Array(credential.rawId || []));
      _storageSet(FACE_ID_CRED_ID_KEY, JSON.stringify(credIdArray));
      _storageSet(FACE_ID_PHONE_KEY, phone);
      _storageSet(FACE_ID_DEVICE_TOKEN_KEY, token);
      _storageSet(FACE_ID_ENABLED_KEY, "1");

      _updateFaceButton();
      _toast("تم تفعيل الدخول بمعرف الوجه بنجاح");
    } catch (err) {
      if (err && err.name === "NotAllowedError") {
        _toast("تم إلغاء عملية التحقق.", true);
      } else {
        _toast("فشل تفعيل معرف الوجه.", true);
      }
    } finally {
      if (btn) btn.disabled = false;
      _updateFaceButton();
    }
  }

  async function _disableFaceId() {
    const confirmed = window.confirm("هل تريد إلغاء تفعيل الدخول بمعرف الوجه؟");
    if (!confirmed) return;

    const res = await ApiClient.request("/api/accounts/biometric/revoke/", {
      method: "POST",
      body: {},
    });

    if (!res.ok) {
      _toast(_extractError(res, "تعذر إلغاء التفعيل من الخادم."), true);
      return;
    }

    _clearStoredBiometricData();
    _updateFaceButton();
    _toast("تم إلغاء تفعيل معرف الوجه");
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

  function _extractDeviceToken(res) {
    const data = res && res.data;
    if (!data || typeof data !== "object") return "";
    return String(data.device_token || "").trim();
  }

  function _normalizePhone05(value) {
    const digits = String(value || "").replace(/[^\d]/g, "");
    if (/^05\d{8}$/.test(digits)) return digits;
    if (/^5\d{8}$/.test(digits)) return "0" + digits;
    if (/^9665\d{8}$/.test(digits)) return "0" + digits.slice(3);
    if (/^009665\d{8}$/.test(digits)) return "0" + digits.slice(5);
    return "";
  }

  function _getStoredBiometricData() {
    const enabled = _storageGet(FACE_ID_ENABLED_KEY) === "1";
    const phone = _normalizePhone05(_storageGet(FACE_ID_PHONE_KEY) || "");
    const deviceToken = _norm(_storageGet(FACE_ID_DEVICE_TOKEN_KEY));
    if (!enabled || !phone || !deviceToken) return null;
    return { phone: phone, deviceToken: deviceToken };
  }

  function _clearStoredBiometricData() {
    _storageRemove(FACE_ID_ENABLED_KEY);
    _storageRemove(FACE_ID_PHONE_KEY);
    _storageRemove(FACE_ID_DEVICE_TOKEN_KEY);
    _storageRemove(FACE_ID_CRED_ID_KEY);
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

  function _on(id, eventName, handler) {
    const el = document.getElementById(id);
    if (el) el.addEventListener(eventName, handler);
  }

  function _val(id) {
    const el = document.getElementById(id);
    return el ? el.value : "";
  }

  function _norm(value) {
    return (value == null ? "" : String(value)).trim();
  }

  function _escape(value) {
    return String(value || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/\"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  document.addEventListener("DOMContentLoaded", init);
  return { init: init };
})();
