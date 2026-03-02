"use strict";
var LoginSettingsPage = (function () {
  var API = window.NwApiClient;
  var profile = null;

  function init() { loadProfile(); bindEvents(); }

  function loadProfile() {
    API.get("/api/accounts/profile/me/").then(function (d) {
      profile = d;
      document.getElementById("ls-first-name").value = d.first_name || "";
      document.getElementById("ls-last-name").value = d.last_name || "";
      document.getElementById("ls-phone").value = d.phone || "";
      document.getElementById("ls-email").value = d.email || "";
      document.getElementById("ls-name").textContent = (d.first_name || "") + " " + (d.last_name || "") || d.phone || "مستخدم";
      document.getElementById("ls-phone-display").textContent = d.phone || "";
      document.getElementById("ls-loading").style.display = "none";
      document.getElementById("ls-content").style.display = "";
    }).catch(function () {
      document.getElementById("ls-loading").innerHTML = '<p class="text-muted">تعذر تحميل البيانات</p>';
    });
  }

  function bindEvents() {
    document.getElementById("ls-save").addEventListener("click", saveProfile);
    document.getElementById("ls-save-pin").addEventListener("click", savePin);
    document.getElementById("ls-logout").addEventListener("click", logout);
    document.getElementById("ls-delete").addEventListener("click", deleteAccount);
  }

  function saveProfile() {
    var data = {};
    var fn = document.getElementById("ls-first-name").value.trim();
    var ln = document.getElementById("ls-last-name").value.trim();
    var ph = document.getElementById("ls-phone").value.trim();
    var em = document.getElementById("ls-email").value.trim();
    if (fn !== (profile.first_name || "")) data.first_name = fn;
    if (ln !== (profile.last_name || "")) data.last_name = ln;
    if (ph !== (profile.phone || "")) data.phone = ph;
    if (em !== (profile.email || "")) data.email = em;
    if (!Object.keys(data).length) { alert("لا يوجد تغييرات"); return; }

    var btn = document.getElementById("ls-save");
    btn.disabled = true; btn.textContent = "جاري الحفظ...";
    API.patch("/api/accounts/profile/me/", data).then(function (d) {
      profile = d;
      alert("تم حفظ التغييرات بنجاح");
    }).catch(function () {
      alert("فشل الحفظ");
    }).finally(function () {
      btn.disabled = false; btn.textContent = "حفظ التغييرات";
    });
  }

  function savePin() {
    var pin = document.getElementById("ls-pin").value;
    var confirm = document.getElementById("ls-pin-confirm").value;
    if (!pin || pin.length < 4) { alert("أدخل رمز مكون من 4-6 أرقام"); return; }
    if (pin !== confirm) { alert("الرمز غير متطابق"); return; }
    localStorage.setItem("nw_security_pin", pin);
    alert("تم حفظ رمز الأمان");
    document.getElementById("ls-pin").value = "";
    document.getElementById("ls-pin-confirm").value = "";
  }

  function logout() {
    if (!confirm("هل تريد تسجيل الخروج؟")) return;
    sessionStorage.clear();
    localStorage.removeItem("nw_security_pin");
    window.location.href = "/login/";
  }

  function deleteAccount() {
    if (!confirm("تحذير: سيتم حذف حسابك نهائياً. هل أنت متأكد؟")) return;
    if (!confirm("هذا الإجراء لا يمكن التراجع عنه. هل تريد المتابعة؟")) return;
    API.del("/api/accounts/profile/me/").then(function () {
      sessionStorage.clear();
      alert("تم حذف الحساب");
      window.location.href = "/";
    }).catch(function () { alert("فشل حذف الحساب"); });
  }

  document.addEventListener("DOMContentLoaded", init);
  return { init: init };
})();
