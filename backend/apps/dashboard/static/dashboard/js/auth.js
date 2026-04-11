(function () {
  "use strict";

  function closeAlerts() {
    const list = document.getElementById("alertsList");
    if (!list) {
      return;
    }
    list.querySelectorAll("button").forEach((btn) => {
      btn.addEventListener("click", () => {
        const item = btn.closest(".alert");
        if (item) {
          item.remove();
        }
      });
    });
  }

  function setupOtpSlots() {
    const container = document.querySelector("[data-otp-slots]");
    const hiddenInput = document.getElementById("otpCode");
    const form = document.getElementById("otpForm");
    if (!container || !hiddenInput || !form) {
      return;
    }

    const slots = Array.from(container.querySelectorAll(".otp-slot, .nx-auth__otp-slot"));
    if (!slots.length) {
      return;
    }

    function rebuildCode() {
      hiddenInput.value = slots.map((slot) => (slot.value || "").trim()).join("");
      slots.forEach((slot) => {
        slot.classList.toggle("is-filled", Boolean((slot.value || "").trim()));
      });
    }

    function populateFromHidden() {
      const value = (hiddenInput.value || "").trim();
      if (!value) {
        slots[0].focus();
        return;
      }
      for (let i = 0; i < slots.length; i += 1) {
        slots[i].value = value[i] || "";
      }
      const firstEmpty = slots.find((slot) => !slot.value);
      (firstEmpty || slots[slots.length - 1]).focus();
    }

    slots.forEach((slot, index) => {
      slot.addEventListener("input", () => {
        slot.value = (slot.value || "").replace(/[^\d]/g, "").slice(-1);
        rebuildCode();
        if (slot.value && index < slots.length - 1) {
          slots[index + 1].focus();
        }
      });

      slot.addEventListener("keydown", (event) => {
        if (event.key === "Backspace" && !slot.value && index > 0) {
          slots[index - 1].focus();
        }
      });

      slot.addEventListener("paste", (event) => {
        const pasted = (event.clipboardData?.getData("text") || "").replace(/[^\d]/g, "");
        if (!pasted) {
          return;
        }
        event.preventDefault();
        for (let i = 0; i < slots.length; i += 1) {
          slots[i].value = pasted[i] || "";
        }
        rebuildCode();
        const firstEmpty = slots.find((input) => !input.value);
        (firstEmpty || slots[slots.length - 1]).focus();
      });
    });

    form.addEventListener("submit", () => {
      rebuildCode();
    });

    populateFromHidden();
    rebuildCode();
  }

  function setupPasswordToggle() {
    const toggle = document.querySelector("[data-password-toggle]");
    const passwordInput = document.querySelector("#loginForm input[type='password'], #loginForm input[name='password']");
    if (!toggle || !passwordInput) {
      return;
    }

    const text = toggle.querySelector("[data-password-toggle-text]");

    toggle.addEventListener("click", () => {
      const isPassword = passwordInput.type === "password";
      passwordInput.type = isPassword ? "text" : "password";
      if (text) {
        text.textContent = isPassword ? "إخفاء" : "إظهار";
      }
      toggle.setAttribute("aria-pressed", isPassword ? "true" : "false");
    });
  }

  function setupOtpResendCooldown() {
    const resendForm = document.querySelector(".nx-auth__resend");
    const resendBtn = resendForm ? resendForm.querySelector("[data-resend-btn]") : null;
    const resendTimer = resendForm ? resendForm.querySelector("[data-resend-timer]") : null;
    if (!resendForm || !resendBtn || !resendTimer) {
      return;
    }

    const storageKey = "dashboard_auth_otp_resend_until";
    const serverCooldownSeconds = Number.parseInt(resendForm.dataset.resendCooldownSeconds || "0", 10) || 0;
    const defaultCooldownSeconds = Math.max(
      5,
      Number.parseInt(resendForm.dataset.resendDefaultCooldown || "60", 10) || 60
    );
    let tickHandle = null;

    function nowSeconds() {
      return Math.floor(Date.now() / 1000);
    }

    function readUntilTs() {
      try {
        const raw = sessionStorage.getItem(storageKey);
        const parsed = Number.parseInt(raw || "0", 10) || 0;
        return parsed > 0 ? parsed : 0;
      } catch (_err) {
        return 0;
      }
    }

    function writeUntilTs(untilTs) {
      try {
        sessionStorage.setItem(storageKey, String(untilTs));
      } catch (_err) {
        // best effort only
      }
    }

    function clearUntilTs() {
      try {
        sessionStorage.removeItem(storageKey);
      } catch (_err) {
        // best effort only
      }
    }

    function formatRemaining(remainingSeconds) {
      const total = Math.max(0, Number.parseInt(remainingSeconds, 10) || 0);
      const mins = Math.floor(total / 60);
      const secs = total % 60;
      return mins > 0 ? `${mins}:${String(secs).padStart(2, "0")}` : `${secs}ث`;
    }

    function updateButtonState(remainingSeconds) {
      const remaining = Math.max(0, Number.parseInt(remainingSeconds, 10) || 0);
      const isLocked = remaining > 0;
      resendBtn.disabled = isLocked;
      resendBtn.classList.toggle("is-disabled", isLocked);
      resendBtn.setAttribute("aria-disabled", isLocked ? "true" : "false");
      resendTimer.textContent = isLocked ? `(${formatRemaining(remaining)})` : "";
    }

    function startTicker() {
      if (tickHandle) {
        window.clearInterval(tickHandle);
      }
      tickHandle = window.setInterval(() => {
        const untilTs = readUntilTs();
        const remaining = Math.max(0, untilTs - nowSeconds());
        updateButtonState(remaining);
        if (remaining <= 0) {
          clearUntilTs();
          window.clearInterval(tickHandle);
          tickHandle = null;
        }
      }, 1000);
    }

    const activeUntil = readUntilTs();
    const serverUntil = serverCooldownSeconds > 0 ? nowSeconds() + serverCooldownSeconds : 0;
    const resolvedUntil = Math.max(activeUntil, serverUntil);

    if (resolvedUntil > nowSeconds()) {
      writeUntilTs(resolvedUntil);
      updateButtonState(resolvedUntil - nowSeconds());
      startTicker();
    } else {
      clearUntilTs();
      updateButtonState(0);
    }

    resendForm.addEventListener("submit", (event) => {
      const untilTs = readUntilTs();
      const remaining = Math.max(0, untilTs - nowSeconds());
      if (remaining > 0) {
        event.preventDefault();
        updateButtonState(remaining);
        return;
      }
      const nextUntil = nowSeconds() + defaultCooldownSeconds;
      writeUntilTs(nextUntil);
      updateButtonState(defaultCooldownSeconds);
      startTicker();
    });
  }

  document.addEventListener("DOMContentLoaded", () => {
    closeAlerts();
    setupOtpSlots();
    setupPasswordToggle();
    setupOtpResendCooldown();
  });
})();
