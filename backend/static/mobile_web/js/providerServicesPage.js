"use strict";
var ProviderServicesPage = (function () {
  var API = window.NwApiClient;
  var Cache = window.NwCache;
  var services = [];
  var categories = [];
  var editingId = null;

  function init() {
    loadData();
    bindEvents();
  }

  function loadData() {
    Promise.all([
      API.get("/api/providers/categories/"),
      API.get("/api/providers/me/services/")
    ]).then(function (res) {
      categories = res[0] || [];
      var raw = Array.isArray(res[1]) ? res[1] : (res[1] && res[1].results ? res[1].results : []);
      services = raw;
      populateCategoryDropdown();
      render();
    }).catch(function (err) {
      document.getElementById("ps-loading").style.display = "none";
      var el = document.getElementById("ps-error");
      el.style.display = ""; el.querySelector("p").textContent = "تعذر جلب الخدمات";
    });
  }

  function populateCategoryDropdown() {
    var sel = document.getElementById("svc-category");
    sel.innerHTML = '<option value="">اختر القسم</option>';
    categories.forEach(function (c) {
      var o = document.createElement("option");
      o.value = c.id; o.textContent = c.name;
      sel.appendChild(o);
    });
  }

  function render() {
    document.getElementById("ps-loading").style.display = "none";
    if (!services.length) {
      document.getElementById("ps-empty").style.display = "";
      document.getElementById("ps-list").style.display = "none";
      return;
    }
    document.getElementById("ps-empty").style.display = "none";
    var list = document.getElementById("ps-list");
    list.style.display = "";
    list.innerHTML = services.map(function (s) {
      var subcat = s.subcategory || {};
      var catName = (subcat.category && subcat.category.name) || "";
      var subName = subcat.name || "";
      var priceUnit = { fixed: "ثابت", starting_from: "يبدأ من", hour: "بالساعة", day: "باليوم", negotiable: "قابل للتفاوض" }[s.price_unit] || s.price_unit || "";
      var priceStr = s.price_unit === "negotiable" ? "قابل للتفاوض" : (s.price_from || "0") + " - " + (s.price_to || "0") + " ر.س";
      return '<div class="service-card" data-id="' + s.id + '">' +
        '<div class="svc-header"><h3>' + (s.title || "") + '</h3><span class="badge ' + (s.is_active ? "badge-success" : "badge-muted") + '">' + (s.is_active ? "مفعلة" : "معطلة") + '</span></div>' +
        '<p class="svc-cat">' + catName + (subName ? " → " + subName : "") + '</p>' +
        '<p class="svc-desc">' + (s.description || "").substring(0, 100) + '</p>' +
        '<div class="svc-footer"><span class="svc-price">' + priceStr + '</span><span class="svc-price-type">' + priceUnit + '</span></div>' +
        '<div class="svc-actions"><button class="btn btn-sm btn-outline btn-edit" data-id="' + s.id + '">تعديل</button><button class="btn btn-sm btn-danger btn-delete" data-id="' + s.id + '">حذف</button></div>' +
        '</div>';
    }).join("");
  }

  function bindEvents() {
    // Add buttons
    document.getElementById("btn-add-service").addEventListener("click", function () { openModal(); });
    document.getElementById("btn-add-first") && document.getElementById("btn-add-first").addEventListener("click", function () { openModal(); });

    // Category change → subcategory
    document.getElementById("svc-category").addEventListener("change", function () {
      var catId = parseInt(this.value);
      var cat = categories.find(function (c) { return c.id === catId; });
      var subSel = document.getElementById("svc-subcategory");
      subSel.innerHTML = '<option value="">اختر التصنيف</option>';
      if (cat && cat.subcategories) {
        cat.subcategories.forEach(function (s) {
          var o = document.createElement("option"); o.value = s.id; o.textContent = s.name;
          subSel.appendChild(o);
        });
      }
    });

    // Price unit
    document.getElementById("svc-price-unit").addEventListener("change", function () {
      document.getElementById("svc-price-row").style.display = this.value === "negotiable" ? "none" : "";
    });

    // Modal close
    document.getElementById("svc-modal-close").addEventListener("click", closeModal);
    document.getElementById("svc-modal").addEventListener("click", function (e) { if (e.target === this) closeModal(); });

    // Form submit
    document.getElementById("svc-form").addEventListener("submit", function (e) { e.preventDefault(); save(); });

    // List delegation for edit/delete
    document.getElementById("ps-list").addEventListener("click", function (e) {
      var editBtn = e.target.closest(".btn-edit");
      var delBtn = e.target.closest(".btn-delete");
      if (editBtn) { editService(parseInt(editBtn.dataset.id)); }
      if (delBtn) { deleteService(parseInt(delBtn.dataset.id)); }
    });
  }

  function openModal(svc) {
    editingId = svc ? svc.id : null;
    document.getElementById("svc-modal-title").textContent = svc ? "تعديل الخدمة" : "إضافة خدمة جديدة";
    if (svc) {
      var sub = svc.subcategory || {};
      var catId = (sub.category && sub.category.id) || "";
      document.getElementById("svc-category").value = catId;
      document.getElementById("svc-category").dispatchEvent(new Event("change"));
      setTimeout(function () { document.getElementById("svc-subcategory").value = sub.id || ""; }, 100);
      document.getElementById("svc-title").value = svc.title || "";
      document.getElementById("svc-desc").value = svc.description || "";
      document.getElementById("svc-price-unit").value = svc.price_unit || "fixed";
      document.getElementById("svc-price-from").value = svc.price_from || "";
      document.getElementById("svc-price-to").value = svc.price_to || "";
      document.getElementById("svc-active").checked = svc.is_active !== false;
      document.getElementById("svc-price-row").style.display = svc.price_unit === "negotiable" ? "none" : "";
    } else {
      document.getElementById("svc-form").reset();
      document.getElementById("svc-active").checked = true;
      document.getElementById("svc-price-row").style.display = "";
    }
    document.getElementById("svc-modal").style.display = "";
  }

  function closeModal() { document.getElementById("svc-modal").style.display = "none"; editingId = null; }

  function editService(id) {
    var svc = services.find(function (s) { return s.id === id; });
    if (svc) openModal(svc);
  }

  function deleteService(id) {
    var svc = services.find(function (s) { return s.id === id; });
    if (!confirm('هل تريد حذف "' + (svc ? svc.title : "") + '"؟')) return;
    API.del("/api/providers/me/services/" + id + "/").then(function () {
      services = services.filter(function (s) { return s.id !== id; });
      render();
    }).catch(function () { alert("فشل الحذف"); });
  }

  function save() {
    var subcat = document.getElementById("svc-subcategory").value;
    if (!subcat) { alert("يرجى اختيار التصنيف الفرعي"); return; }
    var title = document.getElementById("svc-title").value.trim();
    if (!title) { alert("أدخل اسم الخدمة"); return; }

    var priceUnit = document.getElementById("svc-price-unit").value;
    var body = {
      title: title,
      description: document.getElementById("svc-desc").value.trim(),
      subcategory: parseInt(subcat),
      price_unit: priceUnit,
      is_active: document.getElementById("svc-active").checked
    };
    if (priceUnit !== "negotiable") {
      body.price_from = document.getElementById("svc-price-from").value || null;
      body.price_to = document.getElementById("svc-price-to").value || null;
    }

    var btn = document.getElementById("svc-submit-btn");
    btn.disabled = true; btn.textContent = "جاري الحفظ...";

    var promise = editingId
      ? API.patch("/api/providers/me/services/" + editingId + "/", body)
      : API.post("/api/providers/me/services/", body);

    promise.then(function (res) {
      closeModal();
      loadData();
    }).catch(function (err) {
      alert(err.message || "فشل الحفظ");
    }).finally(function () {
      btn.disabled = false; btn.textContent = "حفظ";
    });
  }

  function reload() { loadData(); }

  document.addEventListener("DOMContentLoaded", init);
  return { init: init, reload: reload };
})();
