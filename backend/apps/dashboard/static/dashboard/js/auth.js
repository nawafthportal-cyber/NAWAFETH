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

    const slots = Array.from(container.querySelectorAll(".otp-slot"));
    if (!slots.length) {
      return;
    }

    function rebuildCode() {
      hiddenInput.value = slots.map((slot) => (slot.value || "").trim()).join("");
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
      });
    });

    form.addEventListener("submit", () => {
      rebuildCode();
    });

    populateFromHidden();
  }

  document.addEventListener("DOMContentLoaded", () => {
    closeAlerts();
    setupOtpSlots();
  });
})();

