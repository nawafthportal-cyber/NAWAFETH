/**
 * Dashboard shared utilities.
 * Provides modal handling, inline edit toggling, and common helpers.
 */

/* ── Modal Management ──────────────────────────────────────── */

/**
 * Initialize a modal by wiring open/close buttons.
 * @param {string} modalId - The ID of the modal element
 * @param {string} openBtnId - The ID of the button that opens the modal
 * @param {string[]} closeBtnIds - IDs of buttons that close the modal
 */
function initModal(modalId, openBtnId, closeBtnIds) {
  const modal = document.getElementById(modalId);
  const openBtn = document.getElementById(openBtnId);

  if (!modal) return;

  function open() { modal.classList.remove("hidden"); }
  function close() { modal.classList.add("hidden"); }

  if (openBtn) openBtn.addEventListener("click", open);

  (closeBtnIds || []).forEach(function (id) {
    var btn = document.getElementById(id);
    if (btn) btn.addEventListener("click", close);
  });

  // Close on backdrop click
  modal.addEventListener("click", function (e) {
    if (e.target === modal || e.target === modal.firstElementChild) {
      close();
    }
  });

  // Close on Escape key
  document.addEventListener("keydown", function (e) {
    if (e.key === "Escape" && !modal.classList.contains("hidden")) {
      close();
    }
  });
}


/* ── Inline Edit Toggle ───────────────────────────────────── */

/**
 * Toggle visibility of an inline edit row.
 * @param {string|number} id - The identifier used in the row's element ID
 * @param {string} [prefix] - Optional prefix (default: "edit-row-")
 */
function toggleEdit(id, prefix) {
  var rowId = (prefix || "edit-row-") + id;
  var row = document.getElementById(rowId);
  if (row) row.classList.toggle("hidden");
}


/* ── Auto-init on DOMContentLoaded ────────────────────────── */

document.addEventListener("DOMContentLoaded", function () {
  // Auto-init accept modal if present (request_detail page)
  if (document.getElementById("acceptModal")) {
    initModal("acceptModal", "openAcceptModal", ["closeAcceptModal", "cancelAcceptModal"]);
  }
});
