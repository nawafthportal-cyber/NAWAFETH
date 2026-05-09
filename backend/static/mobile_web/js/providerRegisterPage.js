"use strict";
var ProviderRegisterPage = (function () {
  var RAW_API = window.ApiClient;
  var API = window.NwApiClient;
  var ALLOWED_PROVIDER_TYPES = ["individual", "company"];
  var currentStep = 1;
  var categories = [];
  var categoryGroupSequence = 0;
  var providerType = "individual";
  var isSubmitting = false;
  var isSuggestionSubmitting = false;
  var toastTimer = null;
  var locationMap = null;
  var locationMarker = null;
  var reverseLocationRequestId = 0;
  var DEFAULT_LOCATION = { lat: 24.7136, lng: 46.6753, zoom: 11 };
  var SAUDI_MAJOR_CITY_FALLBACKS = [
    { name: "الرياض", aliases: ["الرياض", "riyadh"], bounds: { minLat: 24.20, maxLat: 25.20, minLng: 46.20, maxLng: 47.30 } },
    { name: "جدة", aliases: ["جدة", "jeddah"], bounds: { minLat: 21.20, maxLat: 21.90, minLng: 38.90, maxLng: 39.50 } },
    { name: "مكة المكرمة", aliases: ["مكة", "مكة المكرمة", "mecca", "makkah"], bounds: { minLat: 21.20, maxLat: 21.70, minLng: 39.50, maxLng: 40.10 } },
    { name: "المدينة المنورة", aliases: ["المدينة", "المدينة المنورة", "medina", "madinah"], bounds: { minLat: 24.20, maxLat: 24.80, minLng: 39.30, maxLng: 39.90 } },
    { name: "الدمام", aliases: ["الدمام", "dammam"], bounds: { minLat: 26.20, maxLat: 26.60, minLng: 49.90, maxLng: 50.30 } },
    { name: "الخبر", aliases: ["الخبر", "khobar", "alkhobar"], bounds: { minLat: 26.20, maxLat: 26.40, minLng: 50.10, maxLng: 50.35 } },
    { name: "الطائف", aliases: ["الطائف", "taif"], bounds: { minLat: 21.10, maxLat: 21.50, minLng: 40.20, maxLng: 40.70 } },
    { name: "أبها", aliases: ["أبها", "ابها", "abha"], bounds: { minLat: 18.10, maxLat: 18.40, minLng: 42.30, maxLng: 42.70 } },
    { name: "تبوك", aliases: ["تبوك", "tabuk"], bounds: { minLat: 28.20, maxLat: 28.60, minLng: 36.30, maxLng: 36.80 } },
    { name: "بريدة", aliases: ["بريدة", "buraydah", "buraidah"], bounds: { minLat: 26.20, maxLat: 26.50, minLng: 43.80, maxLng: 44.20 } },
    { name: "حائل", aliases: ["حائل", "hail", "ha'il"], bounds: { minLat: 27.40, maxLat: 27.70, minLng: 41.50, maxLng: 42.00 } },
    { name: "جازان", aliases: ["جازان", "جيزان", "jazan", "jizan"], bounds: { minLat: 16.70, maxLat: 17.20, minLng: 42.40, maxLng: 43.00 } },
  ];
  var STEP_NARRATIVES = {
    1: {
      badge: "الخطوة 1 من 3",
      title: "أساس ملفك الاحترافي",
      hint: "ابدأ باسم عرض واضح وموقع جغرافي دقيق حتى يظهر ملفك للعملاء بالصورة الصحيحة.",
      tip: "كلما كانت بيانات الموقع والإحداثيات أوضح، أصبح ظهورك في المنصة أكثر اتساقًا وسهولة للمراجعة والاعتماد."
    },
    2: {
      badge: "الخطوة 2 من 3",
      title: "اختيار التصنيف المناسب",
      hint: "حدّد الأقسام الرئيسية المناسبة، واختر تحت كل قسم أكثر من تصنيف فرعي عند الحاجة.",
      tip: "إذا كانت خدمتك متخصصة جدًا، اختر الأقرب ثم استخدم اقتراح التصنيف مع إمكانية إضافة أكثر من قسم رئيسي." 
    },
    3: {
      badge: "الخطوة 3 من 3",
      title: "اكتمال ناعم للمعلومات",
      hint: "أضف وسائل التواصل والخبرة بصورة واضحة ومختصرة قبل إنشاء الحساب.",
      tip: "ليس المطلوب كثرة بيانات، بل معلومات عملية تمنح العميل انطباعًا مريحًا وتمنح ملفك مظهرًا مكتملًا."
    },
    success: {
      badge: "الملف جاهز",
      title: "تم إنشاء حسابك بنجاح",
      hint: "أصبح بإمكانك الآن تطوير ملفك وإضافة خدماتك من لوحة التحكم.",
      tip: "ابدأ بإكمال الملف التعريفي والخدمة الأولى حتى يظهر حسابك بصورة أقوى داخل المنصة."
    }
  };
  var TOAST_TONES = {
    success: {
      title: "تم بنجاح",
      icon: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg>',
      role: "status",
      live: "polite"
    },
    warning: {
      title: "تنبيه لطيف",
      icon: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 9v4"/><path d="M12 17h.01"/><path d="M10.29 3.86 1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/></svg>',
      role: "status",
      live: "polite"
    },
    error: {
      title: "تعذر الإكمال",
      icon: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"/><path d="M15 9 9 15"/><path d="m9 9 6 6"/></svg>',
      role: "alert",
      live: "assertive"
    },
    info: {
      title: "معلومة سريعة",
      icon: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"/><path d="M12 16v-4"/><path d="M12 8h.01"/></svg>',
      role: "status",
      live: "polite"
    }
  };

  function init() {
    if (window.Auth && typeof Auth.needsCompletion === "function" && Auth.needsCompletion()) {
      Auth.redirectToCompletion ? Auth.redirectToCompletion("/provider-register/") : (window.location.href = "/signup/?next=%2Fprovider-register%2F");
      return;
    }
    loadCategories();
    bindEvents();
    initLocationMap();
    setCityInputManualMode(true);
    setCityHint("إذا لم تُقرأ مدينة دقيقة، سيمكنك إدخالها يدويًا.", null);
    syncProviderTypeFromDom();
    updateStepNarrative(currentStep);
  }

  function getCategoryGroupsRoot() {
    return document.getElementById("reg-category-groups");
  }

  function getCategoryGroupCards() {
    var root = getCategoryGroupsRoot();
    return root ? Array.prototype.slice.call(root.querySelectorAll(".reg-category-group")) : [];
  }

  function findCategoryById(categoryId) {
    return categories.find(function (category) {
      return category.id === categoryId;
    }) || null;
  }

  function getGroupId(groupEl) {
    return groupEl ? String(groupEl.getAttribute("data-group-id") || "") : "";
  }

  function getSelectedCategoryIds(exceptGroupId) {
    return getCategoryGroupCards().reduce(function (selected, groupEl) {
      var groupId = getGroupId(groupEl);
      if (exceptGroupId && groupId === String(exceptGroupId)) return selected;
      var select = groupEl.querySelector(".reg-category-select");
      var categoryId = select ? parseInt(select.value, 10) : NaN;
      if (!isNaN(categoryId) && selected.indexOf(categoryId) === -1) {
        selected.push(categoryId);
      }
      return selected;
    }, []);
  }

  function findGroupByCategoryId(categoryId, exceptGroupId) {
    if (!categoryId) return null;
    var groups = getCategoryGroupCards();
    for (var i = 0; i < groups.length; i += 1) {
      var groupEl = groups[i];
      if (exceptGroupId && getGroupId(groupEl) === String(exceptGroupId)) continue;
      var select = groupEl.querySelector(".reg-category-select");
      var selectedId = select ? parseInt(select.value, 10) : NaN;
      if (!isNaN(selectedId) && selectedId === categoryId) return groupEl;
    }
    return null;
  }

  function collectGroupSubcategoryIds(groupEl) {
    if (!groupEl) return [];
    return Array.prototype.slice.call(groupEl.querySelectorAll(".reg-subcategory-checkbox:checked")).map(function (checkbox) {
      return parseInt(checkbox.value, 10);
    }).filter(function (subId) {
      return !isNaN(subId);
    });
  }

  function getSelectedSubcategoryIds() {
    var seen = {};
    return getCategoryGroupCards().reduce(function (allIds, groupEl) {
      collectGroupSubcategoryIds(groupEl).forEach(function (subId) {
        if (!seen[subId]) {
          seen[subId] = true;
          allIds.push(subId);
        }
      });
      return allIds;
    }, []);
  }

  function getSelectedCategoryNames() {
    return getCategoryGroupCards().map(function (groupEl) {
      var select = groupEl.querySelector(".reg-category-select");
      if (!select || !String(select.value || "").trim()) return "";
      var selectedOption = select.options[select.selectedIndex];
      return selectedOption ? String(selectedOption.textContent || "").trim() : "";
    }).filter(Boolean);
  }

  function getSelectedSubcategoryNames() {
    return getCategoryGroupCards().reduce(function (names, groupEl) {
      Array.prototype.slice.call(groupEl.querySelectorAll(".reg-subcategory-checkbox:checked")).forEach(function (checkbox) {
        var name = String(checkbox.getAttribute("data-name") || "").trim();
        if (name) names.push(name);
      });
      return names;
    }, []);
  }

  function renderCategoryOptions(select, groupId, selectedId) {
    if (!select) return;
    var takenIds = getSelectedCategoryIds(groupId);
    select.innerHTML = "";

    var placeholder = document.createElement("option");
    placeholder.value = "";
    placeholder.textContent = "اختر القسم";
    select.appendChild(placeholder);

    categories.forEach(function (category) {
      if (takenIds.indexOf(category.id) !== -1 && category.id !== selectedId) return;
      var option = document.createElement("option");
      option.value = String(category.id);
      option.textContent = category.name;
      if (selectedId === category.id) option.selected = true;
      select.appendChild(option);
    });
  }

  function renderSubcategoryOptions(groupEl, categoryId, selectedSubcategoryIds) {
    var list = groupEl ? groupEl.querySelector("[data-role='subcategory-list']") : null;
    if (!list) return;
    list.innerHTML = "";

    if (!categoryId) {
      list.innerHTML = '<p class="reg-subcategory-empty">اختر القسم الرئيسي أولًا لتظهر لك التصنيفات الفرعية المتاحة لهذا القسم.</p>';
      return;
    }

    var category = findCategoryById(categoryId);
    var subcategories = category && Array.isArray(category.subcategories) ? category.subcategories : [];
    if (!subcategories.length) {
      list.innerHTML = '<p class="reg-subcategory-empty">لا توجد تصنيفات فرعية متاحة حاليًا داخل هذا القسم.</p>';
      return;
    }

    var selectedLookup = {};
    (selectedSubcategoryIds || []).forEach(function (subId) {
      selectedLookup[subId] = true;
    });

    subcategories.forEach(function (subcategory) {
      var label = document.createElement("label");
      label.className = "reg-subcategory-option";

      var checkbox = document.createElement("input");
      checkbox.type = "checkbox";
      checkbox.className = "reg-subcategory-checkbox";
      checkbox.value = String(subcategory.id);
      checkbox.checked = !!selectedLookup[subcategory.id];
      checkbox.setAttribute("data-name", subcategory.name);
      checkbox.setAttribute("data-category-name", category.name);

      var text = document.createElement("span");
      text.textContent = subcategory.name;

      label.appendChild(checkbox);
      label.appendChild(text);
      list.appendChild(label);
    });
  }

  function refreshCategoryGroup(groupEl) {
    if (!groupEl) return;
    var select = groupEl.querySelector(".reg-category-select");
    if (!select) return;
    var groupId = getGroupId(groupEl);
    var selectedCategoryId = parseInt(select.value, 10);
    if (isNaN(selectedCategoryId)) selectedCategoryId = null;
    var selectedSubcategoryIds = collectGroupSubcategoryIds(groupEl);
    renderCategoryOptions(select, groupId, selectedCategoryId);

    selectedCategoryId = parseInt(select.value, 10);
    if (isNaN(selectedCategoryId)) selectedCategoryId = null;
    renderSubcategoryOptions(groupEl, selectedCategoryId, selectedSubcategoryIds);
  }

  function updateCategoryGroupHeadings() {
    var groups = getCategoryGroupCards();
    groups.forEach(function (groupEl, index) {
      var title = groupEl.querySelector(".reg-category-group-title");
      var removeBtn = groupEl.querySelector(".reg-category-remove");
      if (title) title.textContent = "القسم " + (index + 1);
      if (removeBtn) removeBtn.classList.toggle("hidden", groups.length <= 1);
    });
  }

  function updateAddCategoryGroupState() {
    var addBtn = document.getElementById("reg-add-category-group");
    if (!addBtn) return;
    addBtn.disabled = !categories.length || getCategoryGroupCards().length >= categories.length;
  }

  function refreshCategoryGroups() {
    getCategoryGroupCards().forEach(refreshCategoryGroup);
    updateCategoryGroupHeadings();
    updateAddCategoryGroupState();
  }

  function createCategoryGroup() {
    var root = getCategoryGroupsRoot();
    if (!root) return null;

    var groupEl = document.createElement("section");
    groupEl.className = "reg-category-group";
    groupEl.setAttribute("data-group-id", String(++categoryGroupSequence));
    groupEl.innerHTML = [
      '<div class="reg-category-group-head">',
      '  <strong class="reg-category-group-title">القسم</strong>',
      '  <button type="button" class="reg-category-remove">حذف القسم</button>',
      '</div>',
      '<div class="reg-category-group-grid">',
      '  <div class="form-group">',
      '    <label class="form-label">القسم الرئيسي</label>',
      '    <select class="form-select reg-category-select"><option value="">اختر القسم</option></select>',
      '    <p class="form-hint">اختر المجال الرئيسي مرة واحدة، ثم حدّد تحته كل التصنيفات الفرعية المناسبة.</p>',
      '  </div>',
      '  <div class="form-group form-group-wide">',
      '    <label class="form-label">التصنيفات الفرعية</label>',
      '    <div class="reg-subcategory-checklist" data-role="subcategory-list">',
      '      <p class="reg-subcategory-empty">اختر القسم الرئيسي أولًا لتظهر لك التصنيفات الفرعية المتاحة لهذا القسم.</p>',
      '    </div>',
      '    <p class="form-hint">يمكنك اختيار أكثر من تصنيف فرعي داخل القسم نفسه.</p>',
      '  </div>',
      '</div>'
    ].join("");
    root.appendChild(groupEl);
    refreshCategoryGroups();
    return groupEl;
  }

  function normalizeProviderType(value) {
    return ALLOWED_PROVIDER_TYPES.indexOf(value) >= 0 ? value : "individual";
  }

  function syncProviderTypeFromDom() {
    var chipsRoot = document.getElementById("reg-type-chips");
    if (!chipsRoot) {
      providerType = "individual";
      return;
    }
    var activeChip = chipsRoot.querySelector(".chip.active");
    providerType = normalizeProviderType(activeChip ? activeChip.dataset.val : providerType);
  }

  function cleanAddressPart(value) {
    return typeof value === "string" ? value.trim().replace(/\s+/g, " ") : "";
  }

  function normalizeGeoLabel(value) {
    return String(value || "")
      .trim()
      .replace(/^المملكة العربية السعودية[\s،,-]*/i, "")
      .replace(/^country\s+/i, "")
      .replace(/\s+/g, " ")
      .toLowerCase();
  }

  function normalizeCoordinate(value) {
    var parsed = Number(value);
    if (!Number.isFinite(parsed)) return null;
    return Number(parsed.toFixed(6));
  }

  function buildLocationLabel(countryValue, cityValue) {
    var country = String(countryValue || "").trim();
    var city = String(cityValue || "").trim();
    if (country && city) return country + " - " + city;
    return country || city;
  }

  function setLocationField(id, value) {
    var input = document.getElementById(id);
    if (!input) return;
    input.value = value || "";
  }

  function setCityInputManualMode(manualAllowed) {
    var input = document.getElementById("reg-city");
    if (!input) return;
    input.readOnly = false;
    input.placeholder = manualAllowed
      ? "يمكنك تعديلها يدويًا أو تركها كما تم تعبئتها"
      : "اختيارية وتُملأ تلقائيًا إذا كانت متاحة";
  }

  function setCityHint(message, state) {
    var hint = document.getElementById("reg-city-hint");
    if (!hint) return;
    hint.textContent = message || "";
    hint.classList.remove("ok", "bad");
    if (state === true) hint.classList.add("ok");
    if (state === false) hint.classList.add("bad");
  }

  function setMapStatus(message, state) {
    var status = document.getElementById("reg-map-status");
    if (!status) return;
    status.textContent = message || "";
    status.classList.remove("ok", "bad");
    if (state === true) status.classList.add("ok");
    if (state === false) status.classList.add("bad");
  }

  function setCoordinates(lat, lng) {
    var latInput = document.getElementById("reg-lat");
    var lngInput = document.getElementById("reg-lng");
    var coords = document.getElementById("reg-map-coordinates");
    if (latInput) latInput.value = lat == null ? "" : String(lat);
    if (lngInput) lngInput.value = lng == null ? "" : String(lng);
    if (!coords) return;
    if (lat == null || lng == null) {
      coords.textContent = "لم يتم اختيار نقطة بعد.";
      return;
    }
    coords.textContent = Number(lat).toFixed(5) + " ، " + Number(lng).toFixed(5);
  }

  function ensureLocationMarker(lat, lng) {
    if (!locationMap) return;
    if (!locationMarker) {
      locationMarker = L.marker([lat, lng], { draggable: true }).addTo(locationMap);
      locationMarker.on("dragend", function () {
        var next = locationMarker.getLatLng();
        setMapLocation(next.lat, next.lng, { source: "drag" });
      });
      return;
    }
    locationMarker.setLatLng([lat, lng]);
  }

  function initLocationMap() {
    var mapEl = document.getElementById("reg-location-map");
    if (!mapEl) return;
    if (!window.L || typeof window.L.map !== "function") {
      setMapStatus("تعذر تحميل الخريطة. حدّث الصفحة وأعد المحاولة.", false);
      return;
    }
    locationMap = L.map(mapEl, {
      center: [DEFAULT_LOCATION.lat, DEFAULT_LOCATION.lng],
      zoom: DEFAULT_LOCATION.zoom,
      scrollWheelZoom: false,
      zoomControl: true,
    });
    L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
      attribution: '&copy; <a href="https://www.openstreetmap.org/">OSM</a>',
      maxZoom: 18,
    }).addTo(locationMap);
    locationMap.on("click", function (event) {
      setMapLocation(event.latlng.lat, event.latlng.lng, { source: "map" });
    });
    window.setTimeout(function () {
      if (locationMap) locationMap.invalidateSize();
    }, 180);
  }

  function resolveCountryFromAddress(address) {
    var country = cleanAddressPart((address && address.country) || (address && address.country_code) || "");
    if (normalizeGeoLabel(country) === "السعودية") return "المملكة العربية السعودية";
    return country;
  }

  function looksLikeNeighborhoodLabel(value) {
    var normalized = normalizeGeoLabel(value);
    return /^حي(?:\s|$)/.test(normalized) || /neighbou?rhood/.test(normalized);
  }

  function isSaudiCountry(value) {
    var normalized = String(value || "").trim().toLowerCase();
    return normalized.indexOf("السعودية") >= 0 || normalized.indexOf("saudi") >= 0;
  }

  function resolveSaudiMajorCity(address, lat, lng) {
    var tokens = [
      address && address.city,
      address && address.town,
      address && address.municipality,
      address && address.county,
      address && address.state,
      address && address.state_district,
      address && address.region,
      address && address.province,
    ].map(normalizeGeoLabel).filter(Boolean);
    for (var i = 0; i < SAUDI_MAJOR_CITY_FALLBACKS.length; i += 1) {
      var cityConfig = SAUDI_MAJOR_CITY_FALLBACKS[i];
      for (var tokenIndex = 0; tokenIndex < tokens.length; tokenIndex += 1) {
        for (var aliasIndex = 0; aliasIndex < cityConfig.aliases.length; aliasIndex += 1) {
          var alias = cityConfig.aliases[aliasIndex];
          if (tokens[tokenIndex] === alias || tokens[tokenIndex].indexOf(alias) >= 0) {
            return cityConfig.name;
          }
        }
      }
    }
    var latValue = Number(lat);
    var lngValue = Number(lng);
    if (!Number.isFinite(latValue) || !Number.isFinite(lngValue)) return "";
    for (var cityIndex = 0; cityIndex < SAUDI_MAJOR_CITY_FALLBACKS.length; cityIndex += 1) {
      var bounds = SAUDI_MAJOR_CITY_FALLBACKS[cityIndex].bounds;
      if (latValue >= bounds.minLat && latValue <= bounds.maxLat && lngValue >= bounds.minLng && lngValue <= bounds.maxLng) {
        return SAUDI_MAJOR_CITY_FALLBACKS[cityIndex].name;
      }
    }
    return "";
  }

  function resolveCityFromAddress(address, countryValue, lat, lng) {
    var countryToken = normalizeGeoLabel(countryValue);
    var candidates = [
      address && address.city,
      address && address.town,
      address && address.municipality,
      address && address.county,
      address && address.village,
      address && address.state_district,
    ].map(cleanAddressPart).filter(Boolean);
    for (var i = 0; i < candidates.length; i += 1) {
      if (normalizeGeoLabel(candidates[i]) !== countryToken && !looksLikeNeighborhoodLabel(candidates[i])) return candidates[i];
    }
    if (isSaudiCountry(countryValue)) return resolveSaudiMajorCity(address, lat, lng);
    return "";
  }

  function applyResolvedLocation(location) {
    var country = cleanAddressPart(location && location.country);
    var city = cleanAddressPart(location && location.city);
    setLocationField("reg-country", country);
    setLocationField("reg-city", city);
    setCityInputManualMode(true);
    setCityHint(city ? "تم تعبئة المدينة تلقائيًا من الموقع المحدد." : (country ? "لم نعثر على مدينة دقيقة لهذه النقطة. أدخل المدينة يدويًا إذا كنت تعرفها." : "إذا لم تُقرأ مدينة دقيقة، سيمكنك إدخالها يدويًا."), city ? true : null);
    setMapStatus(country ? "تم تحديث الموقع بنجاح." : "تم تحديد النقطة، لكن تعذر استخراج الدولة.", !!country);
  }

  async function reverseGeocodeLocation(lat, lng) {
    var params = new URLSearchParams({
      format: "jsonv2",
      lat: String(lat),
      lon: String(lng),
      zoom: "11",
      addressdetails: "1",
      "accept-language": "ar",
    });
    var response = await fetch("https://nominatim.openstreetmap.org/reverse?" + params.toString(), {
      headers: { Accept: "application/json" },
    });
    if (!response.ok) throw new Error("reverse_geocode_failed");
    var data = await response.json();
    var address = data && typeof data === "object" ? (data.address || {}) : {};
    var country = resolveCountryFromAddress(address);
    var city = resolveCityFromAddress(address, country, lat, lng);
    return { country: country, city: city };
  }

  async function setMapLocation(lat, lng, options) {
    var normalizedLat = normalizeCoordinate(lat);
    var normalizedLng = normalizeCoordinate(lng);
    if (normalizedLat === null || normalizedLng === null) {
      setMapStatus("تعذر قراءة الإحداثيات من النقطة المحددة.", false);
      return;
    }
    if (locationMap) {
      ensureLocationMarker(normalizedLat, normalizedLng);
      locationMap.setView([normalizedLat, normalizedLng], Math.max(locationMap.getZoom(), 13), { animate: true });
    }
    setCoordinates(normalizedLat, normalizedLng);
    setMapStatus(options && options.source === "device" ? "تم التقاط موقعك الحالي. جارٍ قراءة الدولة والمدينة..." : "جارٍ قراءة الدولة والمدينة من النقطة المختارة...", null);
    var requestId = ++reverseLocationRequestId;
    try {
      var resolved = await reverseGeocodeLocation(normalizedLat, normalizedLng);
      if (requestId !== reverseLocationRequestId) return;
      applyResolvedLocation(resolved);
    } catch (_) {
      if (requestId !== reverseLocationRequestId) return;
      setLocationField("reg-country", "");
      setLocationField("reg-city", "");
      setMapStatus("تعذر قراءة بيانات الموقع من الخريطة.", false);
    }
  }

  function useCurrentLocation() {
    var button = document.getElementById("reg-use-current-location");
    var originalText = button ? button.textContent : "";
    if (!navigator.geolocation) {
      setMapStatus("المتصفح لا يدعم تحديد الموقع الحالي.", false);
      return;
    }
    if (button) {
      button.disabled = true;
      button.textContent = "جارٍ تحديد موقعي...";
    }
    setMapStatus("جارٍ التقاط موقعك الحالي...", null);
    navigator.geolocation.getCurrentPosition(function (position) {
      Promise.resolve(setMapLocation(position.coords.latitude, position.coords.longitude, { source: "device" }))
        .finally(function () {
          if (button) {
            button.disabled = false;
            button.textContent = originalText;
          }
        });
    }, function (error) {
      if (button) {
        button.disabled = false;
        button.textContent = originalText;
      }
      if (error && error.code === 1) {
        setMapStatus("تم رفض صلاحية الموقع. يمكنك تحديد النقطة يدويًا من الخريطة.", false);
        return;
      }
      setMapStatus("تعذر تحديد موقعك الحالي. جرّب مرة أخرى أو اختر النقطة يدويًا.", false);
    }, {
      enableHighAccuracy: true,
      timeout: 10000,
      maximumAge: 0,
    });
  }

  function loadCategories() {
    API.get("/api/providers/categories/").then(function (cats) {
      categories = cats || [];
      if (!getCategoryGroupCards().length) {
        createCategoryGroup();
      } else {
        refreshCategoryGroups();
      }
    }).catch(function () {
      showToast("تعذر تحميل التصنيفات حاليًا. حدّث الصفحة أو أعد المحاولة بعد قليل.", "error");
    });
  }

  function bindEvents() {
    var currentLocationBtn = document.getElementById("reg-use-current-location");
    if (currentLocationBtn) currentLocationBtn.addEventListener("click", useCurrentLocation);

    var whatsappInput = document.getElementById("reg-whatsapp");
    if (whatsappInput) {
      whatsappInput.addEventListener("input", function () {
        var digits = String(whatsappInput.value || "").replace(/\D+/g, "").slice(0, 10);
        whatsappInput.value = digits;
      });
    }

    document.getElementById("reg-type-chips").addEventListener("click", function (e) {
      var chip = e.target.closest(".chip");
      if (!chip) return;
      var selectedType = normalizeProviderType(chip.dataset.val);
      if (selectedType !== chip.dataset.val) return;
      providerType = selectedType;
      this.querySelectorAll(".chip").forEach(function (c) { c.classList.toggle("active", c === chip); });
    });

    var categoryGroupsRoot = getCategoryGroupsRoot();
    if (categoryGroupsRoot) {
      categoryGroupsRoot.addEventListener("change", function (event) {
        var select = event.target.closest(".reg-category-select");
        if (!select) return;
        var groupEl = select.closest(".reg-category-group");
        var selectedCategoryId = parseInt(select.value, 10);
        var duplicateGroup = findGroupByCategoryId(selectedCategoryId, getGroupId(groupEl));
        if (!isNaN(selectedCategoryId) && duplicateGroup) {
          select.value = "";
          showToast("يمكن اختيار كل قسم رئيسي مرة واحدة فقط. أضف كل التصنيفات الفرعية التابعة له داخل نفس القسم.", "warning");
        }
        refreshCategoryGroups();
      });

      categoryGroupsRoot.addEventListener("click", function (event) {
        var removeBtn = event.target.closest(".reg-category-remove");
        if (!removeBtn) return;
        var groupEl = removeBtn.closest(".reg-category-group");
        if (!groupEl) return;
        groupEl.remove();
        if (!getCategoryGroupCards().length) createCategoryGroup();
        refreshCategoryGroups();
      });
    }

    var addCategoryGroupBtn = document.getElementById("reg-add-category-group");
    if (addCategoryGroupBtn) {
      addCategoryGroupBtn.addEventListener("click", function () {
        if (!categories.length) {
          showToast("انتظر حتى يكتمل تحميل الأقسام أولًا.", "warning");
          return;
        }
        if (getCategoryGroupCards().length >= categories.length) {
          showToast("تمت إضافة كل الأقسام الرئيسية المتاحة حاليًا.", "info");
          return;
        }
        var groupEl = createCategoryGroup();
        var select = groupEl ? groupEl.querySelector(".reg-category-select") : null;
        if (select && typeof select.focus === "function") select.focus();
      });
    }

    document.getElementById("reg-next-1").addEventListener("click", function () { if (validateStep1()) goToStep(2); });
    document.getElementById("reg-back-2").addEventListener("click", function () { goToStep(1); });
    document.getElementById("reg-next-2").addEventListener("click", function () { if (validateStep2()) goToStep(3); });
    document.getElementById("reg-back-3").addEventListener("click", function () { goToStep(2); });
    document.getElementById("reg-submit").addEventListener("click", function () {
      if (validateStep3()) submit();
    });

    var suggestOpenBtn = document.getElementById("reg-suggest-open");
    var suggestCloseBtn = document.getElementById("reg-suggest-close");
    var suggestSubmitBtn = document.getElementById("reg-suggest-submit");
    var toastCloseBtn = document.getElementById("reg-toast-close");
    if (suggestOpenBtn) {
      suggestOpenBtn.addEventListener("click", function () {
        toggleSuggestionForm(!isSuggestionFormVisible());
      });
    }
    if (suggestCloseBtn) suggestCloseBtn.addEventListener("click", function () { toggleSuggestionForm(false); });
    if (suggestSubmitBtn) suggestSubmitBtn.addEventListener("click", function () { submitCategorySuggestion(); });
    if (toastCloseBtn) toastCloseBtn.addEventListener("click", hideToast);
  }

  function focusField(fieldId) {
    var field = document.getElementById(fieldId);
    if (!field || typeof field.focus !== "function") return;
    try {
      field.focus({ preventScroll: false });
    } catch (_) {
      field.focus();
    }
  }

  function updateStepNarrative(stepKey) {
    var narrative = STEP_NARRATIVES.hasOwnProperty(stepKey) ? STEP_NARRATIVES[stepKey] : STEP_NARRATIVES[1];
    var badge = document.getElementById("reg-step-badge");
    var title = document.getElementById("reg-step-title");
    var hint = document.getElementById("reg-step-hint");
    var tip = document.getElementById("reg-step-tip");
    if (badge) badge.textContent = narrative.badge;
    if (title) title.textContent = narrative.title;
    if (hint) hint.textContent = narrative.hint;
    if (tip) tip.textContent = narrative.tip;
  }

  function isSuggestionFormVisible() {
    var form = document.getElementById("reg-suggest-form");
    return !!(form && !form.classList.contains("hidden"));
  }

  function toggleSuggestionForm(show) {
    var form = document.getElementById("reg-suggest-form");
    if (!form) return;
    form.classList.toggle("hidden", !show);
    if (!show) return;

    var mainInput = document.getElementById("reg-suggest-main");
    var subInput = document.getElementById("reg-suggest-sub");
    var selectedMain = getSelectedCategoryNames();
    var selectedSub = getSelectedSubcategoryNames();
    if (mainInput && !mainInput.value.trim() && selectedMain.length) {
      mainInput.value = selectedMain.join("، ");
    }
    if (subInput && !subInput.value.trim() && selectedSub.length) {
      subInput.value = selectedSub.join("، ");
    }
    if (mainInput) mainInput.focus();
  }

  function buildCategorySuggestionDescription(mainName, subName, note) {
    var lines = [
      "اقتراح تصنيف جديد من صفحة تسجيل مزود الخدمة",
      "التصنيف الرئيسي المقترح: " + mainName,
      "التصنيف الفرعي المقترح: " + subName
    ];

    var selectedMain = getSelectedCategoryNames();
    var selectedSub = getSelectedSubcategoryNames();
    if (selectedMain.length) {
      lines.push("الأقسام المختارة حاليًا: " + selectedMain.join("، "));
    }
    if (selectedSub.length) {
      lines.push("التصنيفات الفرعية المختارة حاليًا: " + selectedSub.join("، "));
    }
    if (note) {
      lines.push("ملاحظات: " + note);
    }

    return lines.join(" | ").slice(0, 300);
  }

  function requestWithHardTimeout(path, options, timeoutMs) {
    var ms = parseInt(timeoutMs, 10);
    if (!ms || ms < 1000) ms = 15000;

    return Promise.race([
      Promise.resolve().then(function () {
        if (!RAW_API || typeof RAW_API.request !== "function") {
          throw new Error("تعذر تهيئة الاتصال بالخادم. حدّث الصفحة ثم أعد المحاولة.");
        }
        return RAW_API.request(path, options || {});
      }),
      new Promise(function (resolve) {
        window.setTimeout(function () {
          resolve({
            ok: false,
            status: 0,
            data: { detail: "انتهت مهلة الاتصال. حاول مرة أخرى." },
            error: "hard-timeout"
          });
        }, ms);
      })
    ]);
  }

  async function submitCategorySuggestion() {
    if (isSuggestionSubmitting) return;

    if (window.Auth && typeof window.Auth.isLoggedIn === "function" && !window.Auth.isLoggedIn()) {
      showToast("يجب تسجيل الدخول أولًا لإرسال المقترح.", "warning");
      return;
    }

    var mainInput = document.getElementById("reg-suggest-main");
    var subInput = document.getElementById("reg-suggest-sub");
    var noteInput = document.getElementById("reg-suggest-note");
    if (!mainInput || !subInput) return;

    var mainName = mainInput.value.trim();
    var subName = subInput.value.trim();
    var note = noteInput ? noteInput.value.trim() : "";

    if (!mainName || !subName) {
      showToast("أدخل التصنيف الرئيسي والفرعي المقترحين أولًا.", "warning");
      return;
    }

    isSuggestionSubmitting = true;
    setSuggestionSubmitState(true);

    try {
      var res = await requestWithHardTimeout("/api/support/tickets/create/", {
        method: "POST",
        timeout: 12000,
        body: {
          ticket_type: "suggest",
          description: buildCategorySuggestionDescription(mainName, subName, note)
        }
      }, 16000);

      if (res && (res.status === 401 || res.status === 403)) {
        throw new Error("انتهت الجلسة. سجّل الدخول ثم أعد الإرسال.");
      }
      if (!res || !res.ok || !res.data) {
        throw new Error(apiErrorMessage(res ? res.data : null, "تعذر إرسال الاقتراح"));
      }

      if (noteInput) noteInput.value = "";
      mainInput.value = "";
      subInput.value = "";
      toggleSuggestionForm(false);
      showToast("تم إرسال طلبك للفريق المختص وسيتم إبلاغك. يمكنك متابعة الطلب من صفحة تواصل مع نوافذ (بلاغاتي).", "success");
    } catch (err) {
      showToast((err && err.message) ? err.message : "تعذر إرسال الاقتراح", "error");
    } finally {
      isSuggestionSubmitting = false;
      setSuggestionSubmitState(false);
    }
  }

  function setSuggestionSubmitState(isBusy) {
    var submitBtn = document.getElementById("reg-suggest-submit");
    var submitText = document.getElementById("reg-suggest-submit-text");
    var submitSpinner = document.getElementById("reg-suggest-submit-spinner");
    if (!submitBtn) return;

    submitBtn.disabled = !!isBusy;
    submitBtn.setAttribute("aria-busy", isBusy ? "true" : "false");

    if (submitText) {
      submitText.textContent = isBusy ? "جاري الإرسال..." : "إرسال الاقتراح";
    } else {
      submitBtn.textContent = isBusy ? "جاري الإرسال..." : "إرسال الاقتراح";
    }

    if (submitSpinner) {
      submitSpinner.classList.toggle("hidden", !isBusy);
    }
  }

  function goToStep(n) {
    currentStep = n;
    var stepValue = String(n);
    var numericStep = parseInt(stepValue, 10);
    var hasNumericStep = !isNaN(numericStep);
    var isSuccessStep = stepValue === "success";

    var shell = document.querySelector("main.page-shell");
    if (shell) {
      shell.setAttribute("data-current-step", stepValue);
    }

    document.querySelectorAll(".wizard-panel").forEach(function (p) { p.classList.toggle("active", p.dataset.panel == n); });
    document.querySelectorAll(".wizard-step").forEach(function (s) {
      var sn = parseInt(s.dataset.step, 10);
      s.classList.toggle("active", hasNumericStep && sn === numericStep);
      s.classList.toggle("done", isSuccessStep || (hasNumericStep && sn < numericStep));
    });
    updateStepNarrative(isSuccessStep ? "success" : numericStep);
  }

  function validateStep1() {
    if (!document.getElementById("reg-display-name").value.trim()) {
      focusField("reg-display-name");
      showToast("أدخل اسم العرض أولًا.", "warning");
      return false;
    }
    return true;
  }

  function validateStep2() {
    var groups = getCategoryGroupCards();
    var hasAnySelected = false;
    for (var i = 0; i < groups.length; i += 1) {
      var groupEl = groups[i];
      var select = groupEl.querySelector(".reg-category-select");
      var categoryId = select ? parseInt(select.value, 10) : NaN;
      var selectedIds = collectGroupSubcategoryIds(groupEl);
      if (!isNaN(categoryId) && selectedIds.length === 0) {
        if (select && typeof select.focus === "function") select.focus();
        showToast("اختر تصنيفًا فرعيًا واحدًا على الأقل لكل قسم رئيسي تضيفه.", "warning");
        return false;
      }
      if (selectedIds.length) hasAnySelected = true;
    }
    if (!hasAnySelected) {
      showToast("أضف قسمًا رئيسيًا واحدًا على الأقل، ثم اختر تحته تصنيفًا فرعيًا أو أكثر.", "warning");
      return false;
    }
    return true;
  }

  function validateStep3() {
    var whatsappInput = document.getElementById("reg-whatsapp");
    if (!whatsappInput) return true;

    var whatsapp = String(whatsappInput.value || "").trim();
    if (!whatsapp) return true;

    if (!/^05\d{8}$/.test(whatsapp)) {
      focusField("reg-whatsapp");
      showToast("رقم الواتساب يجب أن يبدأ بـ 05 ويتكون من 10 أرقام.", "warning");
      return false;
    }
    return true;
  }

  function hideToast() {
    var toast = document.getElementById("reg-toast");
    if (!toast) return;
    toast.classList.remove("show");
    if (toastTimer) {
      window.clearTimeout(toastTimer);
      toastTimer = null;
    }
  }

  function apiErrorMessage(data, fallback) {
    if (data && typeof data === "object") {
      if (typeof data.detail === "string" && data.detail.trim()) return data.detail.trim();
      var firstKey = Object.keys(data)[0];
      var firstVal = data[firstKey];
      if (typeof firstVal === "string" && firstVal.trim()) return firstVal.trim();
      if (Array.isArray(firstVal) && firstVal.length) return String(firstVal[0]);
    }
    return fallback || "فشل العملية";
  }

  function showToast(message, type) {
    var toast = document.getElementById("reg-toast");
    var toastTitle = document.getElementById("reg-toast-title");
    var toastMessage = document.getElementById("reg-toast-message");
    var toastIcon = document.getElementById("reg-toast-icon");
    var toneKey = TOAST_TONES[type] ? type : "info";
    var tone = TOAST_TONES[toneKey];
    if (!toast) {
      alert(message || "");
      return;
    }
    if (toastTitle) toastTitle.textContent = tone.title;
    if (toastMessage) {
      toastMessage.textContent = message || "";
    } else {
      toast.textContent = message || "";
    }
    if (toastIcon) toastIcon.innerHTML = tone.icon;
    toast.setAttribute("role", tone.role);
    toast.setAttribute("aria-live", tone.live);
    toast.classList.remove("show", "success", "error", "warning", "info");
    toast.classList.add(toneKey);
    requestAnimationFrame(function () {
      toast.classList.add("show");
    });
    if (toastTimer) window.clearTimeout(toastTimer);
    toastTimer = window.setTimeout(function () {
      hideToast();
    }, 4200);
  }

  function setSubmitState(isBusy, label) {
    var btn = document.getElementById("reg-submit");
    if (!btn) return;
    btn.disabled = !!isBusy;
    btn.textContent = label || (isBusy ? "جاري التسجيل..." : "إنشاء الحساب");
  }

  function isSuccessVisible() {
    var panel = document.getElementById("reg-success");
    return !!(panel && panel.classList.contains("active"));
  }

  function showSuccessPanel() {
    if (window.Auth && typeof window.Auth.setActiveAccountMode === "function") {
      window.Auth.setActiveAccountMode("provider");
    } else {
      sessionStorage.setItem("nw_account_mode", "provider");
    }
    if (window.Auth && typeof window.Auth.saveRoleState === "function") {
      window.Auth.saveRoleState("provider");
    } else {
      sessionStorage.setItem("nw_role_state", "provider");
      try {
        if (window.localStorage) window.localStorage.setItem("nw_role_state", "provider");
      } catch (_) {}
    }
    goToStep("success");
    document.getElementById("reg-success").classList.add("active");
    try {
      window.scrollTo({ top: 0, behavior: "smooth" });
    } catch (_) {
      window.scrollTo(0, 0);
    }
  }

  async function submit() {
    if (isSubmitting) return;

    var subcategoryIds = getSelectedSubcategoryIds();

    isSubmitting = true;
    setSubmitState(true, "جاري التسجيل...");

    var providerBody = {
      provider_type: normalizeProviderType(providerType),
      display_name: document.getElementById("reg-display-name").value.trim(),
      bio: document.getElementById("reg-bio").value.trim(),
      country: document.getElementById("reg-country").value.trim(),
      city: document.getElementById("reg-city").value,
      location_label: buildLocationLabel(document.getElementById("reg-country").value.trim(), document.getElementById("reg-city").value.trim()),
      lat: document.getElementById("reg-lat").value || null,
      lng: document.getElementById("reg-lng").value || null,
      subcategory_ids: subcategoryIds,
      whatsapp: document.getElementById("reg-whatsapp").value.trim(),
      website: document.getElementById("reg-website").value.trim(),
      years_experience: parseInt(document.getElementById("reg-experience").value, 10) || 0
    };

    try {
      var res = await requestWithHardTimeout("/api/providers/register/", {
        method: "POST",
        timeout: 15000,
        body: providerBody
      }, 18000);

      if (res && (res.status === 401 || res.status === 403)) {
        throw new Error("انتهت الجلسة. سجّل الدخول مجددًا ثم أعد التسجيل.");
      }
      if (!res || !res.ok || !res.data) {
        throw new Error(apiErrorMessage(res ? res.data : null, "فشل التسجيل"));
      }
      showSuccessPanel();
      showToast("تم إنشاء حساب مزود الخدمة بنجاح.", "success");
    } catch (err) {
      showToast((err && err.message) ? err.message : "فشل التسجيل", "error");
    } finally {
      isSubmitting = false;
      if (!isSuccessVisible()) {
        setSubmitState(false, "إنشاء الحساب");
      }
    }
  }

  document.addEventListener("DOMContentLoaded", init);
  return { init: init };
})();
