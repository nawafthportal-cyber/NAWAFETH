"use strict";

var PromotionPage = (function () {
  var STATUS_LABELS = {
    "new": "جديد",
    "in_review": "قيد المراجعة",
    "quoted": "تم التسعير",
    "pending_payment": "بانتظار الدفع",
    "active": "مفعل",
    "completed": "مكتمل",
    "rejected": "مرفوض",
    "expired": "منتهي",
    "cancelled": "ملغي"
  };

  var SERVICE_LABELS = {
    "home_banner": "بنر الصفحة الرئيسية",
    "featured_specialists": "شريط أبرز المختصين",
    "portfolio_showcase": "شريط البنرات والمشاريع",
    "snapshots": "شريط اللمحات",
    "search_results": "الظهور في قوائم البحث",
    "promo_messages": "الرسائل الدعائية",
    "sponsorship": "الرعاية"
  };

  var selectedServices = [];

  function init() {
    bindTabs();
    bindServicePicks();
    bindForm();
    loadRequests();
  }

  function bindTabs() {
    var tabs = document.getElementById("promo-tabs");
    tabs.addEventListener("click", function (e) {
      var tab = e.target.closest(".tab");
      if (!tab) return;
      var name = tab.dataset.tab;
      tabs.querySelectorAll(".tab").forEach(function (item) {
        item.classList.toggle("active", item === tab);
      });
      document.querySelectorAll(".tab-panel").forEach(function (panel) {
        panel.classList.toggle("active", panel.dataset.panel === name);
      });
    });
    document.getElementById("btn-go-new").addEventListener("click", function () {
      document.querySelector('[data-tab="new"]').click();
    });
  }

  function bindServicePicks() {
    document.querySelectorAll(".chip-btn").forEach(function (button) {
      button.addEventListener("click", function () {
        var service = button.dataset.service;
        var idx = selectedServices.indexOf(service);
        if (idx >= 0) {
          selectedServices.splice(idx, 1);
          button.classList.remove("active");
          toggleServiceBlock(service, false);
        } else {
          selectedServices.push(service);
          button.classList.add("active");
          toggleServiceBlock(service, true);
        }
      });
    });
  }

  function toggleServiceBlock(service, show) {
    var block = document.querySelector('[data-service-block="' + service + '"]');
    if (block) block.hidden = !show;
  }

  async function loadRequests() {
    var loading = document.getElementById("promo-loading");
    var empty = document.getElementById("promo-empty");
    var listEl = document.getElementById("promo-list");
    loading.style.display = "";
    empty.style.display = "none";
    listEl.innerHTML = "";

    try {
      var res = await ApiClient.get("/api/promo/requests/my/");
      loading.style.display = "none";
      if (!res.ok) {
        listEl.innerHTML = '<p class="text-muted">تعذر تحميل الطلبات</p>';
        return;
      }
      var rows = Array.isArray(res.data) ? res.data : ((res.data && res.data.results) || []);
      if (!rows.length) {
        empty.style.display = "";
        return;
      }
      listEl.innerHTML = rows.map(renderRequestCard).join("");
    } catch (err) {
      loading.style.display = "none";
      listEl.innerHTML = '<p class="text-muted">تعذر تحميل الطلبات</p>';
    }
  }

  function renderRequestCard(row) {
    var items = Array.isArray(row.items) ? row.items : [];
    var summary = items.slice(0, 3).map(function (item) {
      return SERVICE_LABELS[item.service_type] || item.service_type || "";
    }).join("، ");
    return '<div class="promo-card">' +
      '<div class="promo-card-header">' +
      '<div class="promo-info"><strong>' + escapeHtml(row.title || "طلب ترويج") + '</strong><span class="text-muted">' + escapeHtml(row.code || "") + '</span></div>' +
      '<span class="badge">' + escapeHtml(STATUS_LABELS[row.status] || row.status || "") + '</span>' +
      '</div>' +
      '<div class="promo-card-footer"><span>' + items.length + ' خدمة</span><span class="text-muted">' + escapeHtml(summary) + '</span></div>' +
      '</div>';
  }

  function bindForm() {
    document.getElementById("promo-form").addEventListener("submit", async function (e) {
      e.preventDefault();
      if (!selectedServices.length) {
        alert("اختر خدمة واحدة على الأقل");
        return;
      }

      var title = valueOf(document.getElementById("promo-title"));
      if (!title) {
        alert("أدخل عنوان الطلب");
        return;
      }

      var items = [];
      for (var i = 0; i < selectedServices.length; i += 1) {
        var service = selectedServices[i];
        var block = document.querySelector('[data-service-block="' + service + '"]');
        var payload = buildServicePayload(service, block, i);
        if (typeof payload === "string") {
          alert(payload);
          return;
        }
        items.push(payload);
      }

      var button = document.getElementById("promo-submit");
      button.disabled = true;
      button.textContent = "جاري الإرسال...";

      try {
        var createRes = await ApiClient.request("/api/promo/requests/create/", {
          method: "POST",
          body: { title: title, items: items }
        });
        if (!createRes.ok) {
          var errMsg = "فشل إرسال الطلب";
          if (createRes.data) {
            var details = [];
            if (typeof createRes.data === "object") {
              Object.keys(createRes.data).forEach(function (key) {
                var val = createRes.data[key];
                details.push(Array.isArray(val) ? val.join(", ") : String(val));
              });
            }
            if (details.length) errMsg += "\n" + details.join("\n");
          }
          alert(errMsg);
          return;
        }

        var requestId = createRes.data && createRes.data.id;
        var detailRes = requestId ? await ApiClient.get("/api/promo/requests/" + requestId + "/") : null;
        var detailItems = detailRes && detailRes.ok && detailRes.data && Array.isArray(detailRes.data.items)
          ? detailRes.data.items : ((createRes.data && createRes.data.items) || []);
        var ids = {};
        detailItems.forEach(function (item) {
          if (item && item.id) ids[(item.service_type || "") + ":" + (item.sort_order || 0)] = item.id;
        });

        for (var x = 0; x < selectedServices.length; x += 1) {
          var s = selectedServices[x];
          var sBlock = document.querySelector('[data-service-block="' + s + '"]');
          var fileInput = sBlock.querySelector('[data-field="files"]');
          var files = fileInput && fileInput.files ? Array.from(fileInput.files) : [];
          for (var y = 0; y < files.length; y += 1) {
            var fd = new FormData();
            fd.append("file", files[y]);
            fd.append("asset_type", detectAssetType(files[y].name));
            if (ids[s + ":" + x]) fd.append("item_id", String(ids[s + ":" + x]));
            await ApiClient.request("/api/promo/requests/" + requestId + "/assets/", {
              method: "POST",
              body: fd,
              formData: true
            });
          }
        }

        resetForm();
        document.querySelector('[data-tab="requests"]').click();
        loadRequests();
        alert("تم إرسال طلب الترويج بنجاح");
      } finally {
        button.disabled = false;
        button.textContent = "إرسال طلب الترويج";
      }
    });
  }

  function buildServicePayload(service, block, sortOrder) {
    var body = { service_type: service, title: SERVICE_LABELS[service] || service, sort_order: sortOrder };
    function field(name) {
      var element = block.querySelector('[data-field="' + name + '"]');
      return element ? element : null;
    }
    function localIso(name) {
      var val = valueOf(field(name));
      return val ? new Date(val).toISOString() : "";
    }

    if (["home_banner", "featured_specialists", "portfolio_showcase", "snapshots", "search_results", "sponsorship"].indexOf(service) >= 0) {
      body.start_at = localIso("start_at");
      body.end_at = localIso("end_at");
      if (!body.start_at || !body.end_at) return "حدد البداية والنهاية لكل خدمة مختارة";
    }
    if (["featured_specialists", "portfolio_showcase", "snapshots"].indexOf(service) >= 0) {
      body.frequency = valueOf(field("frequency")) || "60s";
    }
    if (service === "search_results") {
      body.search_scope = valueOf(field("search_scope")) || "default";
      body.search_position = valueOf(field("search_position")) || "first";
      body.target_category = valueOf(field("target_category"));
    }
    if (service === "promo_messages") {
      body.send_at = localIso("send_at");
      if (!body.send_at) return "حدد وقت الإرسال للرسائل الدعائية";
      body.use_notification_channel = !!(field("use_notification_channel") && field("use_notification_channel").checked);
      body.use_chat_channel = !!(field("use_chat_channel") && field("use_chat_channel").checked);
      if (!body.use_notification_channel && !body.use_chat_channel) return "اختر قناة واحدة على الأقل للرسائل الدعائية";
      body.message_body = valueOf(field("message_body"));
      body.attachment_specs = valueOf(field("attachment_specs"));
    }
    if (service === "sponsorship") {
      body.sponsor_name = valueOf(field("sponsor_name"));
      body.sponsorship_months = parseInt(valueOf(field("sponsorship_months")) || "0", 10);
      body.redirect_url = valueOf(field("redirect_url"));
      body.message_body = valueOf(field("message_body"));
      body.attachment_specs = valueOf(field("attachment_specs"));
      if (!body.sponsor_name || body.sponsorship_months <= 0) return "أكمل بيانات الرعاية";
    }
    if (service === "home_banner") {
      body.redirect_url = valueOf(field("redirect_url"));
      body.attachment_specs = valueOf(field("attachment_specs"));
    }
    return body;
  }

  function resetForm() {
    document.getElementById("promo-form").reset();
    selectedServices = [];
    document.querySelectorAll(".chip-btn").forEach(function (btn) { btn.classList.remove("active"); });
    document.querySelectorAll(".promo-service-block").forEach(function (block) { block.hidden = true; });
  }

  function valueOf(element) {
    return element && element.value ? String(element.value).trim() : "";
  }

  function detectAssetType(name) {
    var ext = (name.split(".").pop() || "").toLowerCase();
    if (["jpg", "jpeg", "png", "gif", "webp"].indexOf(ext) >= 0) return "image";
    if (["mp4", "mov", "avi", "mkv", "webm"].indexOf(ext) >= 0) return "video";
    if (ext === "pdf") return "pdf";
    return "other";
  }

  function escapeHtml(value) {
    return String(value || "").replace(/[&<>"']/g, function (char) {
      return ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char];
    });
  }

  document.addEventListener("DOMContentLoaded", init);
  return { init: init };
})();
