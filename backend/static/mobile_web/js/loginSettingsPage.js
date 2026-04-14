"use strict";

const LoginSettingsPage = (() => {
  const SECURITY_PIN_KEY = "nw_security_pin";
  const FACE_ID_ENABLED_KEY = "nw_faceid_enabled";
  const FACE_ID_PHONE_KEY = "nw_faceid_phone";
  const FACE_ID_DEVICE_TOKEN_KEY = "nw_faceid_device_token";
  const FACE_ID_CRED_ID_KEY = "nw_faceid_cred_id";

  let _phoneStep = 1; // 1 = enter new phone, 2 = enter OTP code
  let _pendingNewPhone = null;

  let _mode = "client";
  let _toastTimer = null;
  let _inlineAlertTimer = null;
  let _currentAction = null;
  let _biometricAvailable = false;
  let _biometricChecked = false;

  function init() {
    if (!Auth.isLoggedIn()) {
      window.location.href = "/login/?next=" + encodeURIComponent(window.location.pathname);
      return;
    }

    _mode = _resolveMode();
    _bindEvents();
    _renderProfile();
    _syncSecurityHints();
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

    _on("ls-modal-close", "click", _closeModal);
    _on("ls-modal-cancel", "click", _closeModal);
    _on("ls-modal-save", "click", _saveCurrentAction);

    const modal = document.getElementById("ls-action-modal");
    if (modal) {
      modal.addEventListener("click", (event) => {
        const target = event.target;
        if (!(target instanceof Element)) return;
        if (target === modal || target.closest('[data-ls-close="true"]')) {
          _closeModal();
        }
      });
    }

    document.addEventListener("keydown", (event) => {
      if (event.key === "Escape") _closeModal();
    });
  }

  async function _loadProfile() {
    const res = await ApiClient.get(_withMode("/api/accounts/me/"));
    if (res.status === 401) {
      window.location.href = "/login/?next=" + encodeURIComponent(window.location.pathname);
      return;
    }

    if (res.ok && res.data) {
      _profile = res.data;
      _renderProfile();
      return;
    }

    _notify("تعذر تحميل بيانات الحساب حاليًا.", "error");
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
    if (modal) {
      modal.classList.remove("hidden");
      _showInlineAlert(config.hint, "info", 2800);

      // For phone action: label the save button for step 1
      const saveBtn = document.getElementById("ls-modal-save");
      if (saveBtn) {
        saveBtn.textContent = action === "phone" ? "إرسال رمز التحقق" : "حفظ";
      }

      window.setTimeout(() => {
        const firstInput = modal.querySelector("input");
        if (firstInput) firstInput.focus();
      }, 20);
    }
  }

  function _closeModal() {
    const modal = document.getElementById("ls-action-modal");
    if (modal) modal.classList.add("hidden");
    _currentAction = null;
    _phoneStep = 1;
    _pendingNewPhone = null;
  }

  function _modalConfig(action) {
    if (action === "username") {
      return {
        title: "تغيير اسم العضوية",
        desc: "أدخل اسم العضوية الجديد. يسمح فقط بالأحرف الإنجليزية والأرقام و (_) و (.)",
        hint: "قم بتعديل اسم العضوية ثم احفظ التغييرات.",
        fields:
          '<div class="ls-modal-field">' +
          '<label for="ls-input-username">اسم العضوية الجديد</label>' +
          '<input id="ls-input-username" type="text" class="form-input" maxlength="50" placeholder="اسم العضوية الجديد" value="' + _escape(_norm(_profile && _profile.username)) + '" dir="ltr">' +
          "</div>",
      };
    }
    if (action === "password") {
      return {
        title: "تغيير كلمة المرور",
        desc: "أدخل كلمة المرور الحالية ثم الجديدة (8 أحرف على الأقل).",
        hint: "يفضل استخدام كلمة مرور قوية يصعب توقعها.",
        fields:
          '<div class="ls-modal-field">' +
          '<label for="ls-input-current-password">كلمة المرور الحالية</label>' +
          '<input id="ls-input-current-password" type="password" class="form-input" maxlength="128" placeholder="كلمة المرور الحالية" dir="ltr">' +
          "</div>" +
          '<div class="ls-modal-field">' +
          '<label for="ls-input-new-password">كلمة المرور الجديدة</label>' +
          '<input id="ls-input-new-password" type="password" class="form-input" maxlength="128" placeholder="كلمة المرور الجديدة" dir="ltr">' +
          "</div>" +
          '<div class="ls-modal-field">' +
          '<label for="ls-input-new-password-confirm">تأكيد كلمة المرور الجديدة</label>' +
          '<input id="ls-input-new-password-confirm" type="password" class="form-input" maxlength="128" placeholder="تأكيد كلمة المرور الجديدة" dir="ltr">' +
          "</div>",
      };
    }
    if (action === "email") {
      return {
        title: "تغيير البريد الإلكتروني",
        desc: "أدخل البريد الإلكتروني الجديد المرتبط بحسابك.",
        hint: "تأكد من صحة البريد حتى تصلك الإشعارات بشكل صحيح.",
        fields:
          '<div class="ls-modal-field">' +
          '<label for="ls-input-email">البريد الإلكتروني</label>' +
          '<input id="ls-input-email" type="email" class="form-input" maxlength="255" placeholder="example@mail.com" value="' + _escape(_norm(_profile && _profile.email)) + '" dir="ltr">' +
          "</div>",
      };
    }
    if (action === "phone") {
      return {
        title: "تغيير رقم الجوال",
        desc: "سيتم إرسال رمز تحقق إلى الرقم الجديد للتأكيد قبل تغيير رقم تسجيل الدخول.",
        hint: "استخدم رقم جوال سعودي صحيح يبدأ بـ 05.",
        fields:
          '<div class="ls-modal-field">' +
          '<label for="ls-input-phone">رقم الجوال الجديد</label>' +
          '<input id="ls-input-phone" type="tel" class="form-input" maxlength="10" placeholder="05XXXXXXXX" dir="ltr">' +
          "</div>",
      };
    }

    return {
      title: "إضافة رمز دخول أمان",
      desc: "احفظ الرمز في مكان آمن. يستخدم هذا الرمز للدخول السريع داخل الجهاز.",
      hint: "يمكنك إضافة رمز من 4 إلى 6 أرقام لحماية إضافية.",
      fields:
        '<div class="ls-modal-field">' +
        '<label for="ls-input-pin">رمز الأمان</label>' +
        '<input id="ls-input-pin" type="password" class="form-input" maxlength="6" placeholder="رمز الأمان (4-6 أرقام)" dir="ltr">' +
        "</div>" +
        '<div class="ls-modal-field">' +
        '<label for="ls-input-pin-confirm">تأكيد الرمز</label>' +
        '<input id="ls-input-pin-confirm" type="password" class="form-input" maxlength="6" placeholder="تأكيد الرمز" dir="ltr">' +
        "</div>",
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
      if (_phoneStep === 1) {
        await _requestPhoneChange();
      } else {
        await _confirmPhoneChange();
      }
      return;
    }
    if (action === "pin") {
      _savePin();
    }
  }

  async function _saveUsername() {
    const username = _norm(_val("ls-input-username"));
    if (!username) {
      _notify("اسم العضوية مطلوب", "error");
      return;
    }

    const res = await ApiClient.request("/api/accounts/change-username/", {
      method: "POST",
      body: { username: username },
    });

    if (!res.ok) {
      _notify(_extractError(res, "تعذر تغيير اسم العضوية."), "error");
      return;
    }

    if (!_profile) _profile = {};
    _profile.username = username;
    _renderProfile();
    _showInlineAlert("تم تعديل اسم العضوية وحفظه بنجاح.", "success", 3200);
    _closeModal();
    _toast("تم تغيير اسم العضوية بنجاح");
  }

  async function _savePassword() {
    const currentPassword = _val("ls-input-current-password");
    const newPassword = _val("ls-input-new-password");
    const newPasswordConfirm = _val("ls-input-new-password-confirm");

    if (!currentPassword || !newPassword || !newPasswordConfirm) {
      _notify("يرجى تعبئة جميع الحقول.", "error");
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
      _notify(_extractError(res, "تعذر تغيير كلمة المرور."), "error");
      return;
    }

    _showInlineAlert("تم تغيير كلمة المرور بنجاح.", "success", 3400);
    _closeModal();
    _toast("تم تغيير كلمة المرور بنجاح");
  }

  async function _saveEmail() {
    const email = _norm(_val("ls-input-email"));
    if (!email) {
      _notify("يرجى إدخال البريد الإلكتروني.", "error");
      return;
    }

    const res = await ApiClient.request(_withMode("/api/accounts/me/"), {
      method: "PATCH",
      body: { email: email },
    });

    if (!res.ok) {
      _notify(_extractError(res, "تعذر تحديث البريد الإلكتروني."), "error");
      return;
    }

    if (!_profile) _profile = {};
    _profile.email = email;
    _renderProfile();
    _showInlineAlert("تم تعديل البريد الإلكتروني وحفظه.", "success", 3200);
    _closeModal();
    _toast("تم تحديث البريد الإلكتروني بنجاح");
  }

  async function _requestPhoneChange() {
    const phone = _normalizePhone05(_val("ls-input-phone"));
    if (!phone) {
      _notify("صيغة رقم الجوال يجب أن تكون 05XXXXXXXX", "error");
      return;
    }

    const saveBtn = document.getElementById("ls-modal-save");
    if (saveBtn) { saveBtn.disabled = true; saveBtn.textContent = "جاري الإرسال..."; }

    const res = await ApiClient.request("/api/accounts/me/request-phone-change/", {
      method: "POST",
      body: { phone: phone },
    });

    if (saveBtn) { saveBtn.disabled = false; saveBtn.textContent = "تأكيد الرمز وتغيير"; }

    if (!res.ok) {
      _notify(_extractError(res, "تعذر إرسال رمز التحقق."), "error");
      return;
    }

    _pendingNewPhone = phone;
    _phoneStep = 2;

    // Replace fields area with OTP input
    const fieldsEl = document.getElementById("ls-modal-fields");
    const descEl = document.getElementById("ls-modal-desc");
    if (descEl) descEl.textContent = "أدخل رمز التحقق المرسل إلى " + phone + " للتأكيد.";
    if (fieldsEl) {
      fieldsEl.innerHTML =
        '<div class="ls-modal-field">' +
        '<label for="ls-input-phone-otp">رمز التحقق</label>' +
        '<input id="ls-input-phone-otp" type="tel" class="form-input" maxlength="4" placeholder="XXXX" dir="ltr" inputmode="numeric">' +
        "</div>";
      const otpInput = document.getElementById("ls-input-phone-otp");
      if (otpInput) otpInput.focus();
    }

    _showInlineAlert("تم إرسال رمز التحقق إلى الرقم الجديد. أدخله لتأكيد التغيير.", "info", 4000);
  }

  async function _confirmPhoneChange() {
    const code = (_val("ls-input-phone-otp") || "").trim();
    if (!code || code.length !== 4) {
      _notify("أدخل رمز التحقق المكون من 4 أرقام", "error");
      return;
    }
    if (!_pendingNewPhone) {
      _notify("حدث خطأ، يرجى البدء من جديد", "error");
      _closeModal();
      return;
    }

    const res = await ApiClient.request("/api/accounts/me/confirm-phone-change/", {
      method: "POST",
      body: { phone: _pendingNewPhone, code: code },
    });

    if (!res.ok) {
      _notify(_extractError(res, "رمز التحقق غير صحيح أو انتهت صلاحيته."), "error");
      return;
    }

    if (!_profile) _profile = {};
    _profile.phone = _pendingNewPhone;
    _renderProfile();
    _showInlineAlert("تم تغيير رقم الجوال بنجاح. استخدم الرقم الجديد لتسجيل الدخول.", "success", 4000);
    _closeModal();
    _toast("تم تغيير رقم الجوال بنجاح");
  }

  function _savePin() {
    const pin = _norm(_val("ls-input-pin"));
    const pinConfirm = _norm(_val("ls-input-pin-confirm"));

    if (!/^\d{4,6}$/.test(pin)) {
      _notify("رمز الأمان يجب أن يكون من 4 إلى 6 أرقام.", "error");
      return;
    }
    if (pin !== pinConfirm) {
      _notify("تأكيد الرمز غير مطابق.", "error");
      return;
    }

    _storageSet(SECURITY_PIN_KEY, pin);
    _syncSecurityHints();
    _showInlineAlert("تم حفظ رمز الأمان لهذا الجهاز.", "success", 3400);
    _closeModal();
    _toast("تم حفظ رمز الأمان.");
  }

  function _initBiometric() {
    const btn = document.getElementById("ls-action-faceid");
    if (!btn) return;

    if (!window.PublicKeyCredential) {
      _biometricChecked = true;
      _biometricAvailable = false;
      btn.disabled = true;
      btn.textContent = "غير مدعوم";
      _syncSecurityHints();
      return;
    }

    PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable()
      .then((available) => {
        _biometricChecked = true;
        _biometricAvailable = !!available;
        _updateFaceButton();
      })
      .catch(() => {
        _biometricChecked = true;
        _biometricAvailable = false;
        _updateFaceButton();
      });
  }

  function _updateFaceButton() {
    const btn = document.getElementById("ls-action-faceid");
    if (!btn) return;

    if (!_biometricAvailable) {
      btn.disabled = true;
      btn.textContent = "غير مدعوم";
      _syncSecurityHints();
      return;
    }

    const enabled = !!_getStoredBiometricData();
    btn.disabled = false;
    btn.textContent = enabled ? "إلغاء التفعيل" : "تفعيل";
    _syncSecurityHints();
  }

  async function _handleFaceIdAction() {
    if (!_biometricAvailable) {
      _notify("الجهاز لا يدعم البصمة/الوجه", "error");
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
      _notify("يرجى تحديث رقم الجوال أولاً", "error");
      return;
    }

    function _looksLikePhone(v) {
      var s = String(v || '').replace(/[\s\-\+\(\)@]/g, '');
      return /^0[0-9]{8,12}$/.test(s) || /^9665[0-9]{8}$/.test(s) || /^5[0-9]{8}$/.test(s);
    }
    var _rawUsername = _norm(_profile && _profile.username);
    const displayName = (_rawUsername && !_looksLikePhone(_rawUsername)) ? _rawUsername : "مستخدم";
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
        _notify(_extractError(enrollRes, "فشل تفعيل معرف الوجه."), "error");
        return;
      }

      const credIdArray = Array.from(new Uint8Array(credential.rawId || []));
      _storageSet(FACE_ID_CRED_ID_KEY, JSON.stringify(credIdArray));
      _storageSet(FACE_ID_PHONE_KEY, phone);
      _storageSet(FACE_ID_DEVICE_TOKEN_KEY, token);
      _storageSet(FACE_ID_ENABLED_KEY, "1");

      _updateFaceButton();
      _showInlineAlert("تم تفعيل الدخول بمعرف الوجه على هذا الجهاز.", "success", 3600);
      _toast("تم تفعيل الدخول بمعرف الوجه بنجاح");
    } catch (err) {
      if (err && err.name === "NotAllowedError") {
        _notify("تم إلغاء عملية التحقق.", "error");
      } else {
        _notify("فشل تفعيل معرف الوجه.", "error");
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
      _notify(_extractError(res, "تعذر إلغاء التفعيل من الخادم."), "error");
      return;
    }

    _clearStoredBiometricData();
    _updateFaceButton();
    _showInlineAlert("تم إلغاء تفعيل الدخول بمعرف الوجه.", "success", 3400);
    _toast("تم إلغاء تفعيل معرف الوجه");
  }

  function _renderProfile() {
    const username = _norm(_profile && _profile.username) || "غير محدد";
    const email = _norm(_profile && _profile.email) || "غير مضاف";
    const phone = _norm(_profile && _profile.phone) || "غير مضاف";

    _setText("ls-value-username", username);
    _setText("ls-value-email", email);
    _setText("ls-value-phone", phone);

    _setText("ls-view-username", username);
    _setText("ls-view-email", email);
    _setText("ls-view-phone", phone);
  }

  function _syncSecurityHints() {
    _setText("ls-pin-hint", _hasPinConfigured() ? "مفعل على هذا الجهاز" : "غير مفعل");

    if (!_biometricChecked) {
      _setText("ls-faceid-hint", "تحقق من توفر الميزة على جهازك.");
      return;
    }

    if (!_biometricAvailable) {
      _setText("ls-faceid-hint", "غير مدعوم على هذا الجهاز");
      return;
    }

    _setText("ls-faceid-hint", _getStoredBiometricData() ? "مفعل على هذا الجهاز" : "غير مفعل");
  }

  function _hasPinConfigured() {
    const pin = _norm(_storageGet(SECURITY_PIN_KEY));
    return /^\d{4,6}$/.test(pin);
  }

  function _notify(message, type) {
    const variant = type === "error" ? "error" : type === "info" ? "info" : "success";
    _showInlineAlert(message, variant);
    _toast(message, variant === "error");
  }

  function _showInlineAlert(message, type, durationMs) {
    const alertEl = document.getElementById("ls-inline-alert");
    if (!alertEl) return;

    const variant = type === "error" ? "is-error" : type === "info" ? "is-info" : "is-success";
    alertEl.textContent = _norm(message);
    alertEl.classList.remove("hidden", "is-error", "is-info", "is-success");
    alertEl.classList.add(variant);

    if (_inlineAlertTimer) window.clearTimeout(_inlineAlertTimer);

    const timeout = Number.isFinite(durationMs)
      ? durationMs
      : type === "error"
        ? 4600
        : 3200;

    if (timeout > 0) {
      _inlineAlertTimer = window.setTimeout(() => {
        alertEl.classList.add("hidden");
      }, timeout);
    }
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

  function _setText(id, value) {
    const el = document.getElementById(id);
    if (el) el.textContent = value;
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
