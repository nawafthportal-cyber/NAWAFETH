"use strict";

const LoginSettingsPage = (() => {
  const SECURITY_PIN_KEY = "nw_security_pin";
  const FACE_ID_ENABLED_KEY = "nw_faceid_enabled";
  const FACE_ID_PHONE_KEY = "nw_faceid_phone";
  const FACE_ID_DEVICE_TOKEN_KEY = "nw_faceid_device_token";
  const FACE_ID_CRED_ID_KEY = "nw_faceid_cred_id";
  const COPY = {
    ar: {
      pageTitle: "إعدادات الدخول — نوافــذ",
      heroAria: "ملخص إعدادات الدخول",
      settingsAria: "بيانات تسجيل الدخول",
      securityAria: "خيارات الأمان الإضافية",
      back: "رجوع",
      close: "إغلاق",
      heroKicker: "الهوية والأمان",
      heroTitle: "إعدادات الدخول",
      heroSubtitle: "البيانات معروضة مسبقًا ويمكن تعديلها مباشرة من نفس الصفحة بسهولة.",
      username: "اسم العضوية",
      email: "البريد الإلكتروني",
      phone: "رقم الجوال",
      credentialsTitle: "بيانات تسجيل الدخول",
      credentialsDesc: "يمكنك تعديل كل حقل وحفظه فورًا، مع إشعارات واضحة عند النجاح أو وجود خطأ.",
      edit: "تعديل",
      change: "تغيير",
      password: "كلمة المرور",
      passwordDesc: "محمية ولا يمكن عرضها. يمكنك تغييرها في أي وقت.",
      securityTitle: "الأمان الإضافي",
      securityDesc: "فعّل وسائل حماية إضافية لحسابك على هذا الجهاز.",
      pinTitle: "رمز دخول الأمان",
      pinButton: "إضافة أو تعديل",
      faceIdTitle: "الدخول بمعرف الوجه",
      faceIdButton: "الدخول بمعرف الوجه",
      cancel: "إلغاء",
      saveChanges: "حفظ التغييرات",
      save: "حفظ",
      sendOtp: "إرسال رمز التحقق",
      confirmPhone: "تأكيد الرمز وتغيير",
      usernameUnset: "غير محدد",
      fieldUnset: "غير مضاف",
      pinEnabled: "مفعل على هذا الجهاز",
      pinDisabled: "غير مفعل",
      faceIdCheck: "تحقق من توفر الميزة على جهازك.",
      faceIdUnsupported: "غير مدعوم على هذا الجهاز",
      faceIdEnable: "تفعيل",
      faceIdDisable: "إلغاء التفعيل",
      unsupported: "غير مدعوم",
      sessionError: "تعذر التحقق من بيانات الجلسة الآن. حاول مرة أخرى بعد لحظة.",
      modeRecovered: "تمت مزامنة نوع الحساب الحالي تلقائيًا للحفاظ على جلستك.",
      requiredUsername: "اسم العضوية مطلوب",
      usernameChangeFailed: "تعذر تغيير اسم العضوية.",
      usernameChanged: "تم تعديل اسم العضوية وحفظه بنجاح.",
      usernameToast: "تم تغيير اسم العضوية بنجاح",
      requiredFields: "يرجى تعبئة جميع الحقول.",
      passwordChangeFailed: "تعذر تغيير كلمة المرور.",
      passwordChanged: "تم تغيير كلمة المرور بنجاح.",
      passwordToast: "تم تغيير كلمة المرور بنجاح",
      requiredEmail: "يرجى إدخال البريد الإلكتروني.",
      emailUpdateFailed: "تعذر تحديث البريد الإلكتروني.",
      emailChanged: "تم تعديل البريد الإلكتروني وحفظه.",
      emailToast: "تم تحديث البريد الإلكتروني بنجاح",
      phoneFormat: "صيغة رقم الجوال يجب أن تكون 05XXXXXXXX",
      sending: "جاري الإرسال...",
      otpSendFailed: "تعذر إرسال رمز التحقق.",
      phoneOtpDesc: "أدخل رمز التحقق المرسل إلى {phone} للتأكيد.",
      phoneOtpSent: "تم إرسال رمز التحقق إلى الرقم الجديد. أدخله لتأكيد التغيير.",
      phoneCodeRequired: "أدخل رمز التحقق المكون من 4 أرقام",
      phoneRestart: "حدث خطأ، يرجى البدء من جديد",
      phoneConfirmFailed: "رمز التحقق غير صحيح أو انتهت صلاحيته.",
      phoneChanged: "تم تغيير رقم الجوال بنجاح. استخدم الرقم الجديد لتسجيل الدخول.",
      phoneToast: "تم تغيير رقم الجوال بنجاح",
      pinFormat: "رمز الأمان يجب أن يكون من 4 إلى 6 أرقام.",
      pinMismatch: "تأكيد الرمز غير مطابق.",
      pinSaved: "تم حفظ رمز الأمان لهذا الجهاز.",
      pinToast: "تم حفظ رمز الأمان.",
      deviceNoBiometric: "الجهاز لا يدعم البصمة/الوجه",
      updatePhoneFirst: "يرجى تحديث رقم الجوال أولاً",
      genericUser: "مستخدم",
      brandName: "نوافذ",
      faceIdEnableFailed: "فشل تفعيل معرف الوجه.",
      faceIdEnabled: "تم تفعيل الدخول بمعرف الوجه على هذا الجهاز.",
      faceIdEnabledToast: "تم تفعيل الدخول بمعرف الوجه بنجاح",
      faceIdCancelled: "تم إلغاء عملية التحقق.",
      faceIdDisableConfirm: "هل تريد إلغاء تفعيل الدخول بمعرف الوجه؟",
      faceIdDisableFailed: "تعذر إلغاء التفعيل من الخادم.",
      faceIdDisabled: "تم إلغاء تفعيل الدخول بمعرف الوجه.",
      faceIdDisabledToast: "تم إلغاء تفعيل معرف الوجه",
      modal: {
        username: {
          title: "تغيير اسم العضوية",
          desc: "أدخل اسم العضوية الجديد. يسمح فقط بالأحرف الإنجليزية والأرقام و (_) و (.)",
          hint: "قم بتعديل اسم العضوية ثم احفظ التغييرات.",
          label: "اسم العضوية الجديد",
          placeholder: "اسم العضوية الجديد",
        },
        password: {
          title: "تغيير كلمة المرور",
          desc: "أدخل كلمة المرور الحالية ثم الجديدة (8 أحرف على الأقل).",
          hint: "يفضل استخدام كلمة مرور قوية يصعب توقعها.",
          currentLabel: "كلمة المرور الحالية",
          currentPlaceholder: "كلمة المرور الحالية",
          newLabel: "كلمة المرور الجديدة",
          newPlaceholder: "كلمة المرور الجديدة",
          confirmLabel: "تأكيد كلمة المرور الجديدة",
          confirmPlaceholder: "تأكيد كلمة المرور الجديدة",
        },
        email: {
          title: "تغيير البريد الإلكتروني",
          desc: "أدخل البريد الإلكتروني الجديد المرتبط بحسابك.",
          hint: "تأكد من صحة البريد حتى تصلك الإشعارات بشكل صحيح.",
          label: "البريد الإلكتروني",
        },
        phone: {
          title: "تغيير رقم الجوال",
          desc: "سيتم إرسال رمز تحقق إلى الرقم الجديد للتأكيد قبل تغيير رقم تسجيل الدخول.",
          hint: "استخدم رقم جوال سعودي صحيح يبدأ بـ 05.",
          label: "رقم الجوال الجديد",
          otpLabel: "رمز التحقق",
          otpPlaceholder: "XXXX",
        },
        pin: {
          title: "إضافة رمز دخول أمان",
          desc: "احفظ الرمز في مكان آمن. يستخدم هذا الرمز للدخول السريع داخل الجهاز.",
          hint: "يمكنك إضافة رمز من 4 إلى 6 أرقام لحماية إضافية.",
          label: "رمز الأمان",
          placeholder: "رمز الأمان (4-6 أرقام)",
          confirmLabel: "تأكيد الرمز",
          confirmPlaceholder: "تأكيد الرمز",
        },
      },
    },
    en: {
      pageTitle: "Nawafeth — Login Settings",
      heroAria: "Login settings summary",
      settingsAria: "Login details",
      securityAria: "Additional security options",
      back: "Back",
      close: "Close",
      heroKicker: "Identity and security",
      heroTitle: "Login settings",
      heroSubtitle: "Your current details are shown here and can be updated directly from the same page.",
      username: "Username",
      email: "Email",
      phone: "Mobile number",
      credentialsTitle: "Login details",
      credentialsDesc: "Update any field and save it instantly, with clear feedback for success or failure.",
      edit: "Edit",
      change: "Change",
      password: "Password",
      passwordDesc: "Protected and never shown. You can change it at any time.",
      securityTitle: "Additional security",
      securityDesc: "Enable extra protection for your account on this device.",
      pinTitle: "Security PIN",
      pinButton: "Add or edit",
      faceIdTitle: "Face ID sign-in",
      faceIdButton: "Face ID sign-in",
      cancel: "Cancel",
      saveChanges: "Save changes",
      save: "Save",
      sendOtp: "Send verification code",
      confirmPhone: "Confirm code and update",
      usernameUnset: "Not set",
      fieldUnset: "Not added",
      pinEnabled: "Enabled on this device",
      pinDisabled: "Not enabled",
      faceIdCheck: "Check whether this feature is available on your device.",
      faceIdUnsupported: "Not supported on this device",
      faceIdEnable: "Enable",
      faceIdDisable: "Disable",
      unsupported: "Unsupported",
      sessionError: "Unable to verify your session details right now. Please try again in a moment.",
      modeRecovered: "The current account mode was synced automatically to preserve your session.",
      requiredUsername: "Username is required.",
      usernameChangeFailed: "Unable to change the username.",
      usernameChanged: "The username was updated successfully.",
      usernameToast: "Username updated successfully",
      requiredFields: "Please complete all fields.",
      passwordChangeFailed: "Unable to change the password.",
      passwordChanged: "Password updated successfully.",
      passwordToast: "Password updated successfully",
      requiredEmail: "Please enter your email address.",
      emailUpdateFailed: "Unable to update the email address.",
      emailChanged: "The email address was updated successfully.",
      emailToast: "Email updated successfully",
      phoneFormat: "The mobile number must follow this format: 05XXXXXXXX",
      sending: "Sending...",
      otpSendFailed: "Unable to send the verification code.",
      phoneOtpDesc: "Enter the verification code sent to {phone} to confirm the change.",
      phoneOtpSent: "A verification code was sent to the new number. Enter it to confirm the change.",
      phoneCodeRequired: "Enter the 4-digit verification code",
      phoneRestart: "Something went wrong. Please start again.",
      phoneConfirmFailed: "The verification code is invalid or has expired.",
      phoneChanged: "The mobile number was changed successfully. Use the new number to sign in.",
      phoneToast: "Mobile number updated successfully",
      pinFormat: "The security PIN must be 4 to 6 digits.",
      pinMismatch: "The confirmation PIN does not match.",
      pinSaved: "The security PIN was saved for this device.",
      pinToast: "Security PIN saved.",
      deviceNoBiometric: "This device does not support biometric authentication.",
      updatePhoneFirst: "Please update your mobile number first.",
      genericUser: "User",
      brandName: "Nawafeth",
      faceIdEnableFailed: "Failed to enable Face ID sign-in.",
      faceIdEnabled: "Face ID sign-in was enabled on this device.",
      faceIdEnabledToast: "Face ID enabled successfully",
      faceIdCancelled: "The verification flow was cancelled.",
      faceIdDisableConfirm: "Do you want to disable Face ID sign-in?",
      faceIdDisableFailed: "Unable to disable the feature on the server.",
      faceIdDisabled: "Face ID sign-in was disabled.",
      faceIdDisabledToast: "Face ID disabled",
      modal: {
        username: {
          title: "Change username",
          desc: "Enter the new username. Only English letters, numbers, (_) and (.) are allowed.",
          hint: "Update the username and save your changes.",
          label: "New username",
          placeholder: "New username",
        },
        password: {
          title: "Change password",
          desc: "Enter the current password, then the new one (at least 8 characters).",
          hint: "Use a strong password that is hard to guess.",
          currentLabel: "Current password",
          currentPlaceholder: "Current password",
          newLabel: "New password",
          newPlaceholder: "New password",
          confirmLabel: "Confirm new password",
          confirmPlaceholder: "Confirm new password",
        },
        email: {
          title: "Change email",
          desc: "Enter the new email address linked to your account.",
          hint: "Make sure the email is valid so notifications reach you correctly.",
          label: "Email address",
        },
        phone: {
          title: "Change mobile number",
          desc: "A verification code will be sent to the new number before changing your login number.",
          hint: "Use a valid Saudi mobile number starting with 05.",
          label: "New mobile number",
          otpLabel: "Verification code",
          otpPlaceholder: "XXXX",
        },
        pin: {
          title: "Add a security PIN",
          desc: "Store the PIN somewhere safe. It is used for faster sign-in on this device.",
          hint: "You can add a 4 to 6 digit PIN for extra protection.",
          label: "Security PIN",
          placeholder: "Security PIN (4-6 digits)",
          confirmLabel: "Confirm PIN",
          confirmPlaceholder: "Confirm PIN",
        },
      },
    },
  };

  let _profile = null;
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
    _applyStaticCopy();
    _renderProfile();
    _syncSecurityHints();
    _loadProfile();
    _initBiometric();
    window.addEventListener("nawafeth:languagechange", _handleLanguageChange);
  }

  function _resolveMode(profile) {
    const requestedMode = _readStoredMode();
    if (requestedMode !== "provider") return "client";

    const currentProfile = profile || _profile;
    if (_canUseProviderMode(currentProfile)) return "provider";

    const roleState = String(Auth.getRoleState() || "").trim().toLowerCase();
    return roleState === "provider" ? "provider" : "client";
  }

  function _readStoredMode() {
    try {
      return (sessionStorage.getItem("nw_account_mode") || "client").toLowerCase();
    } catch (_) {
      return "client";
    }
  }

  function _saveMode(mode) {
    try {
      sessionStorage.setItem("nw_account_mode", mode === "provider" ? "provider" : "client");
    } catch (_) {
      // ignore storage failures
    }
  }

  function _canUseProviderMode(profile) {
    return !!(
      profile && (
        profile.role_state === "provider"
        || profile.is_provider
        || profile.has_provider_profile
      )
    );
  }

  function _clearCachedProfile() {
    if (Auth && typeof Auth.clearProfileCache === "function") {
      Auth.clearProfileCache();
    }
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
    const resolved = await Auth.resolveProfile(true, _mode);
    if (!resolved.ok) {
      if (!Auth.isLoggedIn()) {
        window.location.href = "/login/?next=" + encodeURIComponent(window.location.pathname);
        return;
      }
      _notify(_copy("sessionError"), "error");
      return;
    }

    _profile = resolved.profile;
    _mode = _resolveMode(_profile);
    if (resolved.mode) {
      _mode = resolved.mode;
    }
    _saveMode(_mode);
    _clearCachedProfile();
    _renderProfile();
    if (resolved.recovered) {
      _showInlineAlert(_copy("modeRecovered"), "info", 3600);
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
    if (modal) {
      modal.classList.remove("hidden");
      _showInlineAlert(config.hint, "info", 2800);

      // For phone action: label the save button for step 1
      const saveBtn = document.getElementById("ls-modal-save");
      if (saveBtn) {
        saveBtn.textContent = action === "phone" ? _copy("sendOtp") : _copy("save");
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
        title: _copy("modal.username.title"),
        desc: _copy("modal.username.desc"),
        hint: _copy("modal.username.hint"),
        fields:
          '<div class="ls-modal-field">' +
          '<label for="ls-input-username">' + _escape(_copy("modal.username.label")) + '</label>' +
          '<input id="ls-input-username" type="text" class="form-input" maxlength="50" placeholder="' + _escape(_copy("modal.username.placeholder")) + '" value="' + _escape(_norm(_profile && _profile.username)) + '" dir="ltr">' +
          "</div>",
      };
    }
    if (action === "password") {
      return {
        title: _copy("modal.password.title"),
        desc: _copy("modal.password.desc"),
        hint: _copy("modal.password.hint"),
        fields:
          '<div class="ls-modal-field">' +
          '<label for="ls-input-current-password">' + _escape(_copy("modal.password.currentLabel")) + '</label>' +
          '<input id="ls-input-current-password" type="password" class="form-input" maxlength="128" placeholder="' + _escape(_copy("modal.password.currentPlaceholder")) + '" dir="ltr">' +
          "</div>" +
          '<div class="ls-modal-field">' +
          '<label for="ls-input-new-password">' + _escape(_copy("modal.password.newLabel")) + '</label>' +
          '<input id="ls-input-new-password" type="password" class="form-input" maxlength="128" placeholder="' + _escape(_copy("modal.password.newPlaceholder")) + '" dir="ltr">' +
          "</div>" +
          '<div class="ls-modal-field">' +
          '<label for="ls-input-new-password-confirm">' + _escape(_copy("modal.password.confirmLabel")) + '</label>' +
          '<input id="ls-input-new-password-confirm" type="password" class="form-input" maxlength="128" placeholder="' + _escape(_copy("modal.password.confirmPlaceholder")) + '" dir="ltr">' +
          "</div>",
      };
    }
    if (action === "email") {
      return {
        title: _copy("modal.email.title"),
        desc: _copy("modal.email.desc"),
        hint: _copy("modal.email.hint"),
        fields:
          '<div class="ls-modal-field">' +
          '<label for="ls-input-email">' + _escape(_copy("modal.email.label")) + '</label>' +
          '<input id="ls-input-email" type="email" class="form-input" maxlength="255" placeholder="example@mail.com" value="' + _escape(_norm(_profile && _profile.email)) + '" dir="ltr">' +
          "</div>",
      };
    }
    if (action === "phone") {
      return {
        title: _copy("modal.phone.title"),
        desc: _copy("modal.phone.desc"),
        hint: _copy("modal.phone.hint"),
        fields:
          '<div class="ls-modal-field">' +
          '<label for="ls-input-phone">' + _escape(_copy("modal.phone.label")) + '</label>' +
          '<input id="ls-input-phone" type="tel" class="form-input" maxlength="10" placeholder="05XXXXXXXX" dir="ltr">' +
          "</div>",
      };
    }

    return {
      title: _copy("modal.pin.title"),
      desc: _copy("modal.pin.desc"),
      hint: _copy("modal.pin.hint"),
      fields:
        '<div class="ls-modal-field">' +
        '<label for="ls-input-pin">' + _escape(_copy("modal.pin.label")) + '</label>' +
        '<input id="ls-input-pin" type="password" class="form-input" maxlength="6" placeholder="' + _escape(_copy("modal.pin.placeholder")) + '" dir="ltr">' +
        "</div>" +
        '<div class="ls-modal-field">' +
        '<label for="ls-input-pin-confirm">' + _escape(_copy("modal.pin.confirmLabel")) + '</label>' +
        '<input id="ls-input-pin-confirm" type="password" class="form-input" maxlength="6" placeholder="' + _escape(_copy("modal.pin.confirmPlaceholder")) + '" dir="ltr">' +
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
      _notify(_copy("requiredUsername"), "error");
      return;
    }

    const res = await ApiClient.request("/api/accounts/change-username/", {
      method: "POST",
      body: { username: username },
    });

    if (!res.ok) {
      _notify(_extractError(res, _copy("usernameChangeFailed")), "error");
      return;
    }

    if (!_profile) _profile = {};
    _profile.username = username;
    _clearCachedProfile();
    _renderProfile();
    _showInlineAlert(_copy("usernameChanged"), "success", 3200);
    _closeModal();
    _toast(_copy("usernameToast"));
  }

  async function _savePassword() {
    const currentPassword = _val("ls-input-current-password");
    const newPassword = _val("ls-input-new-password");
    const newPasswordConfirm = _val("ls-input-new-password-confirm");

    if (!currentPassword || !newPassword || !newPasswordConfirm) {
      _notify(_copy("requiredFields"), "error");
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
      _notify(_extractError(res, _copy("passwordChangeFailed")), "error");
      return;
    }

    _showInlineAlert(_copy("passwordChanged"), "success", 3400);
    _closeModal();
    _toast(_copy("passwordToast"));
  }

  async function _saveEmail() {
    const email = _norm(_val("ls-input-email"));
    if (!email) {
      _notify(_copy("requiredEmail"), "error");
      return;
    }

    const res = await ApiClient.request(_withMode("/api/accounts/me/"), {
      method: "PATCH",
      body: { email: email },
    });

    if (!res.ok) {
      _notify(_extractError(res, _copy("emailUpdateFailed")), "error");
      return;
    }

    if (!_profile) _profile = {};
    _profile.email = email;
    _clearCachedProfile();
    _renderProfile();
    _showInlineAlert(_copy("emailChanged"), "success", 3200);
    _closeModal();
    _toast(_copy("emailToast"));
  }

  async function _requestPhoneChange() {
    const phone = _normalizePhone05(_val("ls-input-phone"));
    if (!phone) {
      _notify(_copy("phoneFormat"), "error");
      return;
    }

    const saveBtn = document.getElementById("ls-modal-save");
    if (saveBtn) { saveBtn.disabled = true; saveBtn.textContent = _copy("sending"); }

    const res = await ApiClient.request("/api/accounts/me/request-phone-change/", {
      method: "POST",
      body: { phone: phone },
    });

    if (saveBtn) { saveBtn.disabled = false; saveBtn.textContent = _copy("confirmPhone"); }

    if (!res.ok) {
      _notify(_extractError(res, _copy("otpSendFailed")), "error");
      return;
    }

    _pendingNewPhone = phone;
    _phoneStep = 2;

    // Replace fields area with OTP input
    const fieldsEl = document.getElementById("ls-modal-fields");
    const descEl = document.getElementById("ls-modal-desc");
    if (descEl) descEl.textContent = _copy("phoneOtpDesc").replace("{phone}", phone);
    if (fieldsEl) {
      fieldsEl.innerHTML =
        '<div class="ls-modal-field">' +
        '<label for="ls-input-phone-otp">' + _escape(_copy("modal.phone.otpLabel")) + '</label>' +
        '<input id="ls-input-phone-otp" type="tel" class="form-input" maxlength="4" placeholder="' + _escape(_copy("modal.phone.otpPlaceholder")) + '" dir="ltr" inputmode="numeric">' +
        "</div>";
      const otpInput = document.getElementById("ls-input-phone-otp");
      if (otpInput) otpInput.focus();
    }

    _showInlineAlert(_copy("phoneOtpSent"), "info", 4000);
  }

  async function _confirmPhoneChange() {
    const code = (_val("ls-input-phone-otp") || "").trim();
    if (!code || code.length !== 4) {
      _notify(_copy("phoneCodeRequired"), "error");
      return;
    }
    if (!_pendingNewPhone) {
      _notify(_copy("phoneRestart"), "error");
      _closeModal();
      return;
    }

    const res = await ApiClient.request("/api/accounts/me/confirm-phone-change/", {
      method: "POST",
      body: { phone: _pendingNewPhone, code: code },
    });

    if (!res.ok) {
      _notify(_extractError(res, _copy("phoneConfirmFailed")), "error");
      return;
    }

    if (!_profile) _profile = {};
    _profile.phone = _pendingNewPhone;
    _clearCachedProfile();
    _renderProfile();
    _showInlineAlert(_copy("phoneChanged"), "success", 4000);
    _closeModal();
    _toast(_copy("phoneToast"));
  }

  function _savePin() {
    const pin = _norm(_val("ls-input-pin"));
    const pinConfirm = _norm(_val("ls-input-pin-confirm"));

    if (!/^\d{4,6}$/.test(pin)) {
      _notify(_copy("pinFormat"), "error");
      return;
    }
    if (pin !== pinConfirm) {
      _notify(_copy("pinMismatch"), "error");
      return;
    }

    _storageSet(SECURITY_PIN_KEY, pin);
    _syncSecurityHints();
    _showInlineAlert(_copy("pinSaved"), "success", 3400);
    _closeModal();
    _toast(_copy("pinToast"));
  }

  function _initBiometric() {
    const btn = document.getElementById("ls-action-faceid");
    if (!btn) return;

    if (!window.PublicKeyCredential) {
      _biometricChecked = true;
      _biometricAvailable = false;
      btn.disabled = true;
      btn.textContent = _copy("unsupported");
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
      btn.textContent = _copy("unsupported");
      _syncSecurityHints();
      return;
    }

    const enabled = !!_getStoredBiometricData();
    btn.disabled = false;
    btn.textContent = enabled ? _copy("faceIdDisable") : _copy("faceIdEnable");
    _syncSecurityHints();
  }

  async function _handleFaceIdAction() {
    if (!_biometricAvailable) {
      _notify(_copy("deviceNoBiometric"), "error");
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
      _notify(_copy("updatePhoneFirst"), "error");
      return;
    }

    function _looksLikePhone(v) {
      var s = String(v || '').replace(/[\s\-\+\(\)@]/g, '');
      return /^0[0-9]{8,12}$/.test(s) || /^9665[0-9]{8}$/.test(s) || /^5[0-9]{8}$/.test(s);
    }
    var _rawUsername = _norm(_profile && _profile.username);
    const displayName = (_rawUsername && !_looksLikePhone(_rawUsername)) ? _rawUsername : _copy("genericUser");
    const btn = document.getElementById("ls-action-faceid");
    if (btn) btn.disabled = true;

    try {
      const challenge = new Uint8Array(32);
      crypto.getRandomValues(challenge);
      const userId = new TextEncoder().encode(phone);

      const credential = await navigator.credentials.create({
        publicKey: {
          challenge: challenge,
          rp: { name: _copy("brandName") },
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
        _notify(_extractError(enrollRes, _copy("faceIdEnableFailed")), "error");
        return;
      }

      const credIdArray = Array.from(new Uint8Array(credential.rawId || []));
      _storageSet(FACE_ID_CRED_ID_KEY, JSON.stringify(credIdArray));
      _storageSet(FACE_ID_PHONE_KEY, phone);
      _storageSet(FACE_ID_DEVICE_TOKEN_KEY, token);
      _storageSet(FACE_ID_ENABLED_KEY, "1");

      _updateFaceButton();
      _showInlineAlert(_copy("faceIdEnabled"), "success", 3600);
      _toast(_copy("faceIdEnabledToast"));
    } catch (err) {
      if (err && err.name === "NotAllowedError") {
        _notify(_copy("faceIdCancelled"), "error");
      } else {
        _notify(_copy("faceIdEnableFailed"), "error");
      }
    } finally {
      if (btn) btn.disabled = false;
      _updateFaceButton();
    }
  }

  async function _disableFaceId() {
    const confirmed = window.confirm(_copy("faceIdDisableConfirm"));
    if (!confirmed) return;

    const res = await ApiClient.request("/api/accounts/biometric/revoke/", {
      method: "POST",
      body: {},
    });

    if (!res.ok) {
      _notify(_extractError(res, _copy("faceIdDisableFailed")), "error");
      return;
    }

    _clearStoredBiometricData();
    _updateFaceButton();
    _showInlineAlert(_copy("faceIdDisabled"), "success", 3400);
    _toast(_copy("faceIdDisabledToast"));
  }

  function _renderProfile() {
    const username = _norm(_profile && _profile.username) || _copy("usernameUnset");
    const email = _norm(_profile && _profile.email) || _copy("fieldUnset");
    const phone = _norm(_profile && _profile.phone) || _copy("fieldUnset");

    _setText("ls-value-username", username);
    _setText("ls-value-email", email);
    _setText("ls-value-phone", phone);

    _setText("ls-view-username", username);
    _setText("ls-view-email", email);
    _setText("ls-view-phone", phone);
  }

  function _syncSecurityHints() {
    _setText("ls-pin-hint", _hasPinConfigured() ? _copy("pinEnabled") : _copy("pinDisabled"));

    if (!_biometricChecked) {
      _setText("ls-faceid-hint", _copy("faceIdCheck"));
      return;
    }

    if (!_biometricAvailable) {
      _setText("ls-faceid-hint", _copy("faceIdUnsupported"));
      return;
    }

    _setText("ls-faceid-hint", _getStoredBiometricData() ? _copy("pinEnabled") : _copy("pinDisabled"));
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

  function _currentLang() {
    if (window.NawafethI18n && typeof window.NawafethI18n.getLanguage === "function") {
      return window.NawafethI18n.getLanguage() === "en" ? "en" : "ar";
    }
    return document.documentElement.lang === "en" ? "en" : "ar";
  }

  function _copy(key) {
    const lang = _currentLang();
    const segments = String(key || "").split(".");
    let value = COPY[lang] || COPY.ar;
    for (let i = 0; i < segments.length; i += 1) {
      if (!value || typeof value !== "object") break;
      value = value[segments[i]];
    }
    if (typeof value === "string") return value;

    value = COPY.ar;
    for (let i = 0; i < segments.length; i += 1) {
      if (!value || typeof value !== "object") break;
      value = value[segments[i]];
    }
    return typeof value === "string" ? value : "";
  }

  function _applyStaticCopy() {
    document.title = _copy("pageTitle");
    const heroCard = document.getElementById("ls-hero-card");
    const settingsCard = document.getElementById("ls-settings-card");
    const securityCard = document.getElementById("ls-security-card");
    if (heroCard) heroCard.setAttribute("aria-label", _copy("heroAria"));
    if (settingsCard) settingsCard.setAttribute("aria-label", _copy("settingsAria"));
    if (securityCard) securityCard.setAttribute("aria-label", _copy("securityAria"));
    _setText("ls-hero-kicker", _copy("heroKicker"));
    _setText("ls-hero-title", _copy("heroTitle"));
    _setText("ls-hero-subtitle", _copy("heroSubtitle"));
    _setText("ls-meta-label-username", _copy("username"));
    _setText("ls-meta-label-email", _copy("email"));
    _setText("ls-meta-label-phone", _copy("phone"));
    _setText("ls-section-title-credentials", _copy("credentialsTitle"));
    _setText("ls-section-desc-credentials", _copy("credentialsDesc"));
    _setText("ls-label-username", _copy("username"));
    _setText("ls-label-email", _copy("email"));
    _setText("ls-label-phone", _copy("phone"));
    _setText("ls-label-password", _copy("password"));
    _setText("ls-desc-password", _copy("passwordDesc"));
    _setText("ls-section-title-security", _copy("securityTitle"));
    _setText("ls-section-desc-security", _copy("securityDesc"));
    _setText("ls-label-pin", _copy("pinTitle"));
    _setText("ls-label-faceid", _copy("faceIdTitle"));
    _setText("ls-modal-cancel", _copy("cancel"));
    _setText("ls-modal-save", _currentAction === "phone" && _phoneStep === 2 ? _copy("confirmPhone") : (_currentAction === "phone" ? _copy("sendOtp") : _copy("saveChanges")));
    const backBtn = document.getElementById("ls-back-btn");
    const closeBtn = document.getElementById("ls-modal-close");
    if (backBtn) backBtn.setAttribute("aria-label", _copy("back"));
    if (closeBtn) closeBtn.setAttribute("aria-label", _copy("close"));
    _setActionButtonLabels();
  }

  function _setActionButtonLabels() {
    _setText("ls-action-username", _copy("edit"));
    _setText("ls-action-email", _copy("edit"));
    _setText("ls-action-phone", _copy("edit"));
    _setText("ls-action-password", _copy("change"));
    _setText("ls-action-pin", _copy("pinButton"));
    const faceBtn = document.getElementById("ls-action-faceid");
    if (faceBtn && !faceBtn.disabled && !_biometricChecked) {
      faceBtn.textContent = _copy("faceIdButton");
    }
  }

  function _handleLanguageChange() {
    _applyStaticCopy();
    _renderProfile();
    _syncSecurityHints();
  }

  document.addEventListener("DOMContentLoaded", init);
  return { init: init };
})();
