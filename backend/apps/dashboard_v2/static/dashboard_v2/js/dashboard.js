(function () {
    "use strict";

    var body = document.body;
    var sidebarOpen = document.getElementById("sidebar-open");
    var sidebarClose = document.getElementById("sidebar-close");
    var sidebarOverlay = document.getElementById("v2-sidebar-overlay");
    var sidebarCollapse = document.getElementById("sidebar-collapse");
    var sidebarExpand = document.getElementById("sidebar-expand");
    var collapseKey = "dashboard_v2_sidebar_collapsed";

    function forEachNode(nodeList, callback) {
        Array.prototype.forEach.call(nodeList || [], callback);
    }

    function closeSidebar() {
        body.classList.remove("v2-sidebar-open");
        if (sidebarOpen) {
            sidebarOpen.setAttribute("aria-expanded", "false");
        }
    }

    function setCollapsed(isCollapsed) {
        if (isCollapsed) {
            body.classList.add("v2-sidebar-collapsed");
            localStorage.setItem(collapseKey, "1");
            return;
        }
        body.classList.remove("v2-sidebar-collapsed");
        localStorage.setItem(collapseKey, "0");
    }

    function setPageLoading(isLoading) {
        if (isLoading) {
            body.classList.add("v2-page-loading");
            return;
        }
        body.classList.remove("v2-page-loading");
    }

    function toastClassByTone(tone) {
        if (tone === "error") {
            return "border-rose-200 bg-rose-50 text-rose-700";
        }
        if (tone === "warning") {
            return "border-amber-200 bg-amber-50 text-amber-700";
        }
        if (tone === "success") {
            return "border-emerald-200 bg-emerald-50 text-emerald-700";
        }
        return "border-slate-200 bg-white text-slate-700";
    }

    function registerToastAutohide(toast, timeoutMs) {
        window.setTimeout(function () {
            toast.style.opacity = "0";
            toast.style.transform = "translateY(-4px)";
            window.setTimeout(function () {
                if (toast.parentNode) {
                    toast.parentNode.removeChild(toast);
                }
            }, 180);
        }, timeoutMs || 4200);
    }

    function ensureToastStack() {
        var stack = document.getElementById("toast-stack");
        if (stack) {
            return stack;
        }
        stack = document.createElement("div");
        stack.id = "toast-stack";
        stack.className = "fixed top-5 left-5 z-50 space-y-2 max-w-sm";
        stack.setAttribute("role", "status");
        stack.setAttribute("aria-live", "polite");
        document.body.appendChild(stack);
        return stack;
    }

    function pushToast(message, tone) {
        if (!message) {
            return;
        }
        var stack = ensureToastStack();
        var toast = document.createElement("div");
        toast.className = "toast-item rounded-xl border px-4 py-3 shadow-soft text-sm font-semibold " + toastClassByTone(tone);
        toast.textContent = message;
        stack.appendChild(toast);
        registerToastAutohide(toast, 2800);
    }

    function markSubmitting(form) {
        if (!form || form.dataset.v2Submitting === "1" || form.hasAttribute("data-no-loading")) {
            return;
        }
        form.dataset.v2Submitting = "1";
        form.setAttribute("aria-busy", "true");
        setPageLoading(true);

        forEachNode(form.querySelectorAll("button[type='submit'], input[type='submit']"), function (button) {
            if (button.disabled) {
                return;
            }
            button.dataset.v2OriginalText = button.tagName === "INPUT" ? button.value : button.textContent;
            if (button.tagName === "INPUT") {
                button.value = button.dataset.loadingText || "جاري التنفيذ...";
            } else {
                button.textContent = button.dataset.loadingText || "جاري التنفيذ...";
            }
            button.disabled = true;
            button.setAttribute("aria-disabled", "true");
        });

        if (String(form.method || "get").toUpperCase() === "POST") {
            pushToast("جارٍ تنفيذ الإجراء...", "info");
        }

        if (form.hasAttribute("data-loading-form")) {
            var filterBar = form.closest(".v2-filter-bar");
            var nextSection = filterBar ? filterBar.nextElementSibling : null;
            var tableShell = nextSection ? nextSection.querySelector("[data-table-shell]") : null;
            if (tableShell) {
                tableShell.setAttribute("data-loading", "1");
            }
        }
    }

    function restoreFormsAfterPageShow() {
        forEachNode(document.querySelectorAll("form[data-v2-submitting='1']"), function (form) {
            delete form.dataset.v2Submitting;
            form.setAttribute("aria-busy", "false");
        });
        forEachNode(document.querySelectorAll("button[aria-disabled='true'], input[aria-disabled='true']"), function (button) {
            button.disabled = false;
            button.removeAttribute("aria-disabled");
            if (button.dataset.v2OriginalText) {
                if (button.tagName === "INPUT") {
                    button.value = button.dataset.v2OriginalText;
                } else {
                    button.textContent = button.dataset.v2OriginalText;
                }
            }
        });
        forEachNode(document.querySelectorAll("[data-table-shell][data-loading='1']"), function (shell) {
            shell.removeAttribute("data-loading");
        });
        setPageLoading(false);
    }

    if (localStorage.getItem(collapseKey) === "1") {
        body.classList.add("v2-sidebar-collapsed");
    }

    if (sidebarOpen) {
        sidebarOpen.setAttribute("aria-expanded", "false");
        sidebarOpen.addEventListener("click", function () {
            body.classList.add("v2-sidebar-open");
            sidebarOpen.setAttribute("aria-expanded", "true");
        });
    }

    if (sidebarClose) {
        sidebarClose.addEventListener("click", closeSidebar);
    }

    if (sidebarOverlay) {
        sidebarOverlay.addEventListener("click", closeSidebar);
    }

    if (sidebarCollapse) {
        sidebarCollapse.addEventListener("click", function () {
            setCollapsed(true);
        });
    }

    if (sidebarExpand) {
        sidebarExpand.addEventListener("click", function () {
            setCollapsed(false);
        });
    }

    forEachNode(document.querySelectorAll("#toast-stack .toast-item"), function (toast) {
        registerToastAutohide(toast, 4200);
    });

    forEachNode(document.querySelectorAll("form"), function (form) {
        form.addEventListener("submit", function () {
            markSubmitting(form);
        });
    });

    forEachNode(document.querySelectorAll("[data-modal-close]"), function (button) {
        button.addEventListener("click", function () {
            var modal = document.getElementById("v2-generic-modal");
            if (modal) {
                modal.classList.add("hidden");
            }
        });
    });

    document.addEventListener("click", function (event) {
        forEachNode(document.querySelectorAll("details[data-auto-close='1']"), function (details) {
            if (!details.contains(event.target)) {
                details.removeAttribute("open");
            }
        });
    });

    document.addEventListener("keydown", function (event) {
        if (event.key === "Escape") {
            closeSidebar();
            var modal = document.getElementById("v2-generic-modal");
            if (modal) {
                modal.classList.add("hidden");
            }
        }
    });

    window.addEventListener("pageshow", function () {
        restoreFormsAfterPageShow();
        body.classList.remove("v2-preload");
    });

    body.classList.remove("v2-preload");
})();
