"use strict";
var ProviderServicesPage = (function () {
  var RAW_API = window.ApiClient;
  var API = window.NwApiClient;
  var services = [];
  var categories = [];
  var editingId = null;
  var providerId = null;
  var readOnlyMode = false;

  function request(path, options) {
    var opts = options || {};
    if (RAW_API && typeof RAW_API.request === "function") {
      return RAW_API.request(path, opts);
    }

    var method = opts.method || "GET";
    if (method === "GET") {
      if (RAW_API && typeof RAW_API.get === "function") {
        return RAW_API.get(path);
      }
      if (API && typeof API.get === "function") {
        return API.get(path).then(function (data) {
          return { ok: true, status: 200, data: data };
        }).catch(function () {
          return { ok: false, status: 0, data: null };
        });
      }
    }
    if (method === "POST" && API && typeof API.post === "function") {
      return API.post(path, opts.body || {}).then(function (data) {
        return { ok: !!data, status: data ? 200 : 0, data: data };
      }).catch(function () {
        return { ok: false, status: 0, data: null };
      });
    }
    if (method === "PATCH" && API && typeof API.patch === "function") {
      return API.patch(path, opts.body || {}).then(function (data) {
        return { ok: !!data, status: data ? 200 : 0, data: data };
      }).catch(function () {
        return { ok: false, status: 0, data: null };
      });
    }
    if (method === "DELETE" && API && typeof API.del === "function") {
      return API.del(path).then(function (resp) {
        return resp && typeof resp.ok === "boolean" ? resp : { ok: true, status: 204, data: null };
      }).catch(function () {
        return { ok: false, status: 0, data: null };
      });
    }
    return Promise.resolve({ ok: false, status: 0, data: null });
  }

  function apiErrorMessage(data, fallback) {
    if (data && typeof data === "object") {
      if (typeof data.detail === "string" && data.detail.trim()) return data.detail.trim();
      var firstKey = Object.keys(data)[0];
      var firstVal = data[firstKey];
      if (typeof firstVal === "string" && firstVal.trim()) return firstVal.trim();
      if (Array.isArray(firstVal) && firstVal.length) return String(firstVal[0]);
    }
    return fallback || "حدث خطأ غير متوقع";
  }

  function extractList(payload) {
    if (Array.isArray(payload)) return payload;
    if (payload && Array.isArray(payload.results)) return payload.results;
    return [];
  }

  function extractProviderId(payload) {
    if (!payload || typeof payload !== "object") return null;
    if (payload.provider_profile_id) return payload.provider_profile_id;
    if (payload.provider_profile && typeof payload.provider_profile === "number") return payload.provider_profile;
    if (payload.provider_profile && typeof payload.provider_profile === "object") return payload.provider_profile.id || null;
    return null;
  }

  function setComposerEnabled(enabled) {
    var addBtn = document.getElementById("btn-add-service");
    var addFirstBtn = document.getElementById("btn-add-first");
    if (addBtn) {
      addBtn.style.opacity = enabled ? "1" : "0.45";
      addBtn.style.pointerEvents = enabled ? "" : "none";
      addBtn.title = enabled ? "إضافة خدمة" : "غير متاح حالياً";
    }
    if (addFirstBtn) {
      addFirstBtn.disabled = !enabled;
      addFirstBtn.style.opacity = enabled ? "1" : "0.6";
    }
  }

  function showError(msg) {
    document.getElementById("ps-loading").style.display = "none";
    var el = document.getElementById("ps-error");
    el.style.display = "";
    el.querySelector("p").textContent = msg || "تعذر جلب الخدمات";
  }

  function clearError() {
    document.getElementById("ps-error").style.display = "none";
  }

  function init() {
    bindEvents();
    loadData();
  }

  function loadProviderId() {
    return request("/api/accounts/me/?mode=provider").then(function (resp) {
      if (resp && resp.ok && resp.data) return resp;
      return request("/api/accounts/me/");
    }).then(function (resp) {
      if (!resp || !resp.ok || !resp.data) return null;
      providerId = extractProviderId(resp.data);
      return providerId;
    }).catch(function () {
      return null;
    });
  }

  function loadCategories() {
    return request("/api/providers/categories/").then(function (resp) {
      if (!resp || !resp.ok) return { ok: false, data: [] };
      return { ok: true, data: extractList(resp.data) };
    });
  }

  function loadServices() {
    return request("/api/providers/me/services/").then(function (resp) {
      if (resp && resp.ok) {
        readOnlyMode = false;
        return { ok: true, data: extractList(resp.data) };
      }
      return loadProviderId().then(function (pid) {
        if (!pid) {
          return { ok: false, reason: resp };
        }
        return request("/api/providers/" + pid + "/services/").then(function (fallbackResp) {
          if (!fallbackResp || !fallbackResp.ok) {
            return { ok: false, reason: fallbackResp || resp };
          }
          readOnlyMode = true;
          return { ok: true, data: extractList(fallbackResp.data) };
        });
      });
    });
  }

  function loadData() {
    document.getElementById("ps-loading").style.display = "";
    clearError();
    document.getElementById("ps-empty").style.display = "none";
    document.getElementById("ps-list").style.display = "none";

    Promise.allSettled([
      loadCategories(),
      loadServices(),
    ]).then(function (responses) {
      var catResp = (responses[0] && responses[0].status === "fulfilled") ? responses[0].value : { ok: false, data: [] };
      var svcResp = (responses[1] && responses[1].status === "fulfilled") ? responses[1].value : { ok: false, data: [] };

      categories = catResp.ok ? catResp.data : [];
      services = svcResp.ok ? svcResp.data : [];

      if (!catResp.ok && !svcResp.ok) {
        throw new Error("تعذر جلب الخدمات. تأكد من تسجيل الدخول كمزود");
      }

      setComposerEnabled(!readOnlyMode && categories.length > 0);
      populateCategoryDropdown();
      render();

      if (!catResp.ok) {
        showError("تم تحميل الخدمات، لكن تعذر تحميل التصنيفات");
      } else if (!svcResp.ok) {
        showError("تم تحميل التصنيفات، لكن تعذر تحميل الخدمات");
      }
    }).catch(function (err) {
      setComposerEnabled(false);
      showError((err && err.message) ? err.message : "تعذر جلب الخدمات");
    });
  }

  function populateCategoryDropdown() {
    var sel = document.getElementById("svc-category");
    sel.innerHTML = '<option value="">اختر القسم</option>';
    categories.forEach(function (category) {
      var option = document.createElement("option");
      option.value = category.id;
      option.textContent = category.name;
      sel.appendChild(option);
    });
  }

  function render() {
    document.getElementById("ps-loading").style.display = "none";
    var list = document.getElementById("ps-list");
    list.style.display = "";
    if (!services.length) {
      document.getElementById("ps-empty").style.display = "";
      list.style.display = "none";
      return;
    }

    document.getElementById("ps-empty").style.display = "none";
    list.innerHTML = services.map(function (service) {
      var subcat = service.subcategory || {};
      var catName = subcat.category_name || (subcat.category && subcat.category.name) || "";
      var subName = subcat.name || "";
      var priceUnit = {
        fixed: "ثابت",
        starting_from: "يبدأ من",
        hour: "بالساعة",
        day: "باليوم",
        negotiable: "قابل للتفاوض",
      }[service.price_unit] || service.price_unit || "";

      var priceStr = service.price_unit === "negotiable"
        ? "قابل للتفاوض"
        : ((service.price_from || "0") + " - " + (service.price_to || "0") + " ر.س");
      var urgentBadge = service.accepts_urgent
        ? '<span class="svc-urgent-badge">يستقبل الطلبات العاجلة</span>'
        : '<span class="svc-urgent-badge is-muted">العاجل غير مفعل</span>';

      return '<div class="service-card" data-id="' + service.id + '">' +
        '<div class="svc-header"><h3>' + (service.title || "") + '</h3><span class="badge ' + (service.is_active ? "badge-success" : "badge-muted") + '">' + (service.is_active ? "مفعلة" : "معطلة") + '</span></div>' +
        '<p class="svc-cat">' + catName + (subName ? " \u2192 " + subName : "") + '</p>' +
        '<div class="svc-badges">' + urgentBadge + '</div>' +
        '<p class="svc-desc">' + (service.description || "").substring(0, 100) + '</p>' +
        '<div class="svc-footer"><span class="svc-price">' + priceStr + '</span><span class="svc-price-type">' + priceUnit + '</span></div>' +
        (readOnlyMode ? '<div class="svc-readonly">عرض فقط</div>' : '<div class="svc-actions"><button class="btn btn-sm btn-outline btn-edit" data-id="' + service.id + '">تعديل</button><button class="btn btn-sm btn-danger btn-delete" data-id="' + service.id + '">حذف</button></div>') +
        '</div>';
    }).join("");
  }

  function bindEvents() {
    document.getElementById("btn-add-service").addEventListener("click", function () { openModal(); });

    var firstBtn = document.getElementById("btn-add-first");
    if (firstBtn) {
      firstBtn.addEventListener("click", function () { openModal(); });
    }

    document.getElementById("svc-category").addEventListener("change", function () {
      var catId = parseInt(this.value, 10);
      var category = categories.find(function (c) { return c.id === catId; });
      var subSel = document.getElementById("svc-subcategory");
      subSel.innerHTML = '<option value="">اختر التصنيف</option>';
      if (!category || !Array.isArray(category.subcategories)) return;
      category.subcategories.forEach(function (sub) {
        var option = document.createElement("option");
        option.value = sub.id;
        option.textContent = sub.name;
        subSel.appendChild(option);
      });
    });

    document.getElementById("svc-price-unit").addEventListener("change", function () {
      document.getElementById("svc-price-row").style.display = this.value === "negotiable" ? "none" : "";
    });

    document.getElementById("svc-modal-close").addEventListener("click", closeModal);
    document.getElementById("svc-modal").addEventListener("click", function (e) {
      if (e.target === this) closeModal();
    });

    document.getElementById("svc-form").addEventListener("submit", function (e) {
      e.preventDefault();
      save();
    });

    document.getElementById("ps-list").addEventListener("click", function (e) {
      var editBtn = e.target.closest(".btn-edit");
      var delBtn = e.target.closest(".btn-delete");
      if (editBtn) editService(parseInt(editBtn.dataset.id, 10));
      if (delBtn) deleteService(parseInt(delBtn.dataset.id, 10));
    });
  }

  function openModal(service) {
    if (readOnlyMode) {
      alert("الوضع الحالي للعرض فقط. تأكد من تسجيل الدخول كمزود.");
      return;
    }
    if (!categories.length) {
      alert("تعذر تحميل التصنيفات. حاول إعادة المحاولة.");
      return;
    }
    editingId = service ? service.id : null;
    document.getElementById("svc-modal-title").textContent = service ? "تعديل الخدمة" : "إضافة خدمة جديدة";

    if (service) {
      var sub = service.subcategory || {};
      var catId = sub.category_id || (sub.category && sub.category.id) || "";

      document.getElementById("svc-category").value = catId;
      document.getElementById("svc-category").dispatchEvent(new Event("change"));
      setTimeout(function () {
        document.getElementById("svc-subcategory").value = sub.id || "";
      }, 50);

      document.getElementById("svc-title").value = service.title || "";
      document.getElementById("svc-desc").value = service.description || "";
      document.getElementById("svc-price-unit").value = service.price_unit || "fixed";
      document.getElementById("svc-price-from").value = service.price_from || "";
      document.getElementById("svc-price-to").value = service.price_to || "";
      document.getElementById("svc-active").checked = service.is_active !== false;
      document.getElementById("svc-accepts-urgent").checked = !!service.accepts_urgent;
      document.getElementById("svc-price-row").style.display = service.price_unit === "negotiable" ? "none" : "";
    } else {
      document.getElementById("svc-form").reset();
      document.getElementById("svc-active").checked = true;
      document.getElementById("svc-accepts-urgent").checked = false;
      document.getElementById("svc-price-row").style.display = "";
    }

    document.getElementById("svc-modal").style.display = "";
  }

  function closeModal() {
    document.getElementById("svc-modal").style.display = "none";
    editingId = null;
  }

  function editService(id) {
    var service = services.find(function (s) { return s.id === id; });
    if (service) openModal(service);
  }

  function deleteService(id) {
    var service = services.find(function (s) { return s.id === id; });
    if (!confirm('هل تريد حذف "' + (service ? service.title : "") + '"؟')) return;

    request("/api/providers/me/services/" + id + "/", { method: "DELETE" }).then(function (resp) {
      if (!resp || !resp.ok) {
        throw new Error(apiErrorMessage(resp ? resp.data : null, "فشل حذف الخدمة"));
      }
      services = services.filter(function (s) { return s.id !== id; });
      render();
    }).catch(function (err) {
      alert((err && err.message) ? err.message : "فشل حذف الخدمة");
    });
  }

  function save() {
    var subcat = document.getElementById("svc-subcategory").value;
    if (!subcat) {
      alert("يرجى اختيار التصنيف الفرعي");
      return;
    }

    var title = document.getElementById("svc-title").value.trim();
    if (!title) {
      alert("أدخل اسم الخدمة");
      return;
    }

    var priceUnit = document.getElementById("svc-price-unit").value;
    var body = {
      title: title,
      description: document.getElementById("svc-desc").value.trim(),
      subcategory_id: parseInt(subcat, 10),
      price_unit: priceUnit,
      is_active: document.getElementById("svc-active").checked,
      accepts_urgent: document.getElementById("svc-accepts-urgent").checked,
    };

    if (priceUnit !== "negotiable") {
      var priceFromRaw = document.getElementById("svc-price-from").value;
      var priceToRaw = document.getElementById("svc-price-to").value;
      body.price_from = priceFromRaw ? Number(priceFromRaw) : null;
      body.price_to = priceToRaw ? Number(priceToRaw) : null;
    }

    var btn = document.getElementById("svc-submit-btn");
    btn.disabled = true;
    btn.textContent = "جاري الحفظ...";

    var path = editingId
      ? ("/api/providers/me/services/" + editingId + "/")
      : "/api/providers/me/services/";
    var method = editingId ? "PATCH" : "POST";

    request(path, { method: method, body: body }).then(function (resp) {
      if (!resp || !resp.ok) {
        throw new Error(apiErrorMessage(resp ? resp.data : null, "فشل حفظ الخدمة"));
      }
      closeModal();
      loadData();
    }).catch(function (err) {
      alert((err && err.message) ? err.message : "فشل حفظ الخدمة");
    }).finally(function () {
      btn.disabled = false;
      btn.textContent = "حفظ";
    });
  }

  function reload() {
    readOnlyMode = false;
    loadData();
  }

  document.addEventListener("DOMContentLoaded", init);
  return { init: init, reload: reload };
})();
