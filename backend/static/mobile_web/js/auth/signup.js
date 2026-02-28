(function () {
  "use strict";

  const api = window.NawafethApi;
  if (!api) return;

  const saudiCities = [
    "أبها",
    "الأحساء",
    "الأفلاج",
    "الباحة",
    "البكيرية",
    "البدائع",
    "الجبيل",
    "الجموم",
    "الحريق",
    "الحوطة",
    "الخبر",
    "الخرج",
    "الخفجي",
    "الدرعية",
    "الدلم",
    "الدمام",
    "الدوادمي",
    "الرس",
    "الرياض",
    "الزلفي",
    "السليل",
    "الطائف",
    "الظهران",
    "العرضيات",
    "العلا",
    "القريات",
    "القصيم",
    "القطيف",
    "القنفذة",
    "القويعية",
    "الليث",
    "المجمعة",
    "المدينة المنورة",
    "المذنب",
    "المزاحمية",
    "النماص",
    "الوجه",
    "أملج",
    "بدر",
    "بريدة",
    "بلجرشي",
    "بيشة",
    "تبوك",
    "تربة",
    "تنومة",
    "ثادق",
    "جازان",
    "جدة",
    "حائل",
    "حفر الباطن",
    "حقل",
    "حوطة بني تميم",
    "خميس مشيط",
    "خيبر",
    "رابغ",
    "رفحاء",
    "رنية",
    "سراة عبيدة",
    "سكاكا",
    "شرورة",
    "شقراء",
    "صامطة",
    "صبيا",
    "ضباء",
    "ضرما",
    "طبرجل",
    "طريف",
    "ظلم",
    "عرعر",
    "عفيف",
    "عنيزة",
    "محايل عسير",
    "مكة المكرمة",
    "نجران",
    "ينبع",
  ];

  function setError(message) {
    const el = document.getElementById("signup-error");
    if (!el) return;
    el.textContent = message || "";
    el.hidden = !message;
  }

  function setUsernameHint(message, color) {
    const el = document.getElementById("username-hint");
    if (!el) return;
    el.textContent = message || "";
    el.style.color = color || "#667085";
  }

  function isUsernameCharsValid(username) {
    return /^[A-Za-z0-9_.]+$/.test(username);
  }

  function passwordRules(password) {
    return (
      password.length >= 8 &&
      /[a-z]/.test(password) &&
      /[A-Z]/.test(password) &&
      /[0-9]/.test(password) &&
      /[!@#$&*~%^()\-_=+{};:,<.>]/.test(password)
    );
  }

  document.addEventListener("DOMContentLoaded", function () {
    if (!api.isAuthenticated()) {
      window.location.href = api.urls.login;
      return;
    }

    const citySelect = document.getElementById("city");
    const usernameInput = document.getElementById("username");
    const signupBtn = document.getElementById("signup-btn");
    const firstNameInput = document.getElementById("first-name");
    const lastNameInput = document.getElementById("last-name");
    const emailInput = document.getElementById("email");
    const passwordInput = document.getElementById("password");
    const passwordConfirmInput = document.getElementById("password-confirm");
    const termsInput = document.getElementById("terms");

    /* ── Password rules visual feedback (matching Flutter pills) ── */
    var passwordRulesBox = document.getElementById("password-rules");
    function updatePasswordRulesUI() {
      if (!passwordRulesBox || !passwordInput) return;
      var pw = String(passwordInput.value || "");
      var checks = {
        length: pw.length >= 8,
        lowercase: /[a-z]/.test(pw),
        uppercase: /[A-Z]/.test(pw),
        digit: /[0-9]/.test(pw),
        special: /[!@#$&*~%^()\-_=+{};:,<.>]/.test(pw)
      };
      var pills = passwordRulesBox.querySelectorAll(".nw-password-rule");
      pills.forEach(function(pill) {
        var rule = pill.getAttribute("data-rule");
        var icon = pill.querySelector(".material-icons-round");
        if (checks[rule]) {
          pill.classList.add("is-valid");
          if (icon) icon.textContent = "check_circle";
        } else {
          pill.classList.remove("is-valid");
          if (icon) icon.textContent = "radio_button_unchecked";
        }
      });
    }
    if (passwordInput) {
      passwordInput.addEventListener("input", updatePasswordRulesUI);
    }

    if (
      !citySelect ||
      !usernameInput ||
      !signupBtn ||
      !firstNameInput ||
      !lastNameInput ||
      !emailInput ||
      !passwordInput ||
      !passwordConfirmInput ||
      !termsInput
    ) {
      return;
    }

    saudiCities.forEach(function (city) {
      const option = document.createElement("option");
      option.value = city;
      option.textContent = city;
      citySelect.appendChild(option);
    });

    let usernameAvailable = null;
    let usernameDebounce = null;

    async function checkUsername() {
      const username = String(usernameInput.value || "").trim();
      usernameAvailable = null;
      if (!username) {
        setUsernameHint("");
        return;
      }
      if (username.length < 3) {
        setUsernameHint("اسم المستخدم يجب أن يكون 3 أحرف على الأقل", "#b42318");
        return;
      }
      if (!isUsernameCharsValid(username)) {
        setUsernameHint("المسموح: حروف إنجليزية، أرقام، (_) و (.)", "#b42318");
        return;
      }

      setUsernameHint("جاري التحقق...", "#667085");
      try {
        const payload = await api.get(
          "/api/accounts/username-availability/?username=" + encodeURIComponent(username),
          { auth: false }
        );
        usernameAvailable = Boolean(payload && payload.available);
        setUsernameHint(
          payload && payload.detail ? payload.detail : (usernameAvailable ? "اسم المستخدم متاح" : "اسم المستخدم محجوز"),
          usernameAvailable ? "#127c2e" : "#b42318"
        );
      } catch (error) {
        setUsernameHint(api.getErrorMessage(error && error.payload, "فشل فحص اسم المستخدم"), "#b42318");
      }
    }

    usernameInput.addEventListener("input", function () {
      setError("");
      if (usernameDebounce) {
        clearTimeout(usernameDebounce);
      }
      usernameDebounce = window.setTimeout(checkUsername, 500);
    });

    signupBtn.addEventListener("click", async function () {
      setError("");
      const firstName = String(firstNameInput.value || "").trim();
      const lastName = String(lastNameInput.value || "").trim();
      const username = String(usernameInput.value || "").trim();
      const email = String(emailInput.value || "").trim();
      const city = String(citySelect.value || "").trim();
      const password = String(passwordInput.value || "");
      const passwordConfirm = String(passwordConfirmInput.value || "");
      const terms = Boolean(termsInput.checked);

      if (!firstName || !lastName || !username || !email || !city) {
        setError("جميع الحقول الأساسية مطلوبة.");
        return;
      }
      if (!isUsernameCharsValid(username) || username.length < 3) {
        setError("اسم المستخدم غير صالح.");
        return;
      }
      if (usernameAvailable !== true) {
        setError("تحقق من توفر اسم المستخدم أولًا.");
        return;
      }
      if (!passwordRules(password)) {
        setError("كلمة المرور يجب أن تحتوي على 8 أحرف ورقم وحرف كبير وصغير ورمز.");
        return;
      }
      if (password !== passwordConfirm) {
        setError("كلمة المرور وتأكيدها غير متطابقين.");
        return;
      }
      if (!terms) {
        setError("يجب الموافقة على الشروط والأحكام.");
        return;
      }

      signupBtn.disabled = true;
      signupBtn.textContent = "جارٍ حفظ البيانات...";
      try {
        const payload = await api.post("/api/accounts/complete/", {
          first_name: firstName,
          last_name: lastName,
          username: username,
          email: email,
          city: city,
          password: password,
          password_confirm: passwordConfirm,
          accept_terms: true,
        });

        if (payload && payload.role_state) {
          api.setSession({ roleState: payload.role_state });
        }
        window.location.href = api.urls.home;
      } catch (error) {
        const payload = error && error.payload;
        if (payload && typeof payload === "object") {
          const messages = [];
          Object.keys(payload).forEach(function (key) {
            const val = payload[key];
            if (Array.isArray(val) && val.length) {
              messages.push(String(val[0]));
            } else if (typeof val === "string") {
              messages.push(val);
            }
          });
          if (messages.length) {
            setError(messages.join(" | "));
          } else {
            setError(api.getErrorMessage(payload, error.message || "فشل إكمال التسجيل"));
          }
        } else {
          setError(error.message || "فشل إكمال التسجيل");
        }
      } finally {
        signupBtn.disabled = false;
        signupBtn.textContent = "إكمال التسجيل";
      }
    });
  });
})();

