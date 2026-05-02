/* ===================================================================
   searchPage.js — Search providers (Flutter-like compact flow)
   GET /api/providers/list/?page_size=30&q=X&category_id=Y
   GET /api/providers/categories/
   =================================================================== */
'use strict';

const SearchPage = (() => {
  const COPY = {
    ar: {
      pageTitle: 'بحث مقدمي الخدمات',
      back: 'رجوع',
      liveResults: 'نتائج محدثة لحظيًا',
      kicker: 'اكتشاف احترافي',
      heading: 'البحث عن مزود خدمة',
      subtitle: 'ابحث بسرعة، قارن بثقة، وابدأ الطلب مباشرة من نفس النتيجة بدون خطوات مشتتة.',
      searchPlaceholder: 'ابحث باسم المزود، التخصص أو القسم...',
      clear: 'مسح',
      signalVerified: 'مزودون موثقون',
      signalRequest: 'طلب فوري',
      signalMap: 'خريطة حية',
      totalResults: 'إجمالي النتائج',
      resultsCount: '{count} نتيجة',
      map: 'الخريطة',
      sortResults: 'فرز النتائج',
      activeCategory: 'التصنيف الحالي: {name}',
      allCategories: 'كل التصنيفات',
      changeCategory: 'تغيير التصنيف - {name}',
      chooseCategory: 'اختيار التصنيف',
      readyProviders: 'مزودون جاهزون للعمل',
      resultsNote: 'البطاقات تعرض الثقة، النشاط، والإجراء الأسرع من أول نظرة.',
      noSearchResults: 'لا توجد نتائج تطابق البحث الحالي.',
      chooseCategoryTitle: 'اختر التصنيف',
      close: 'إغلاق',
      searchCategoryPlaceholder: 'ابحث عن تصنيف...',
      categoriesCount: '{count} تصنيف',
      categoriesCountOfTotal: '{count} من {total} تصنيف',
      chooseAll: 'اختيار الكل',
      sortBy: 'فرز حسب',
      sortDefault: 'الافتراضي',
      sortNearest: 'الأقرب',
      sortRating: 'أعلى تقييم',
      sortCompleted: 'الأكثر طلبات مكتملة',
      sortFollowers: 'الأكثر متابعة',
      providersMap: 'خريطة المزوّدين',
      providersMapInCity: 'خريطة المزوّدين - {city}',
      locationUnavailableDistance: 'تعذر تحديد الموقع حالياً. سيتم عرض النتائج بدون مسافة.',
      clearCategoryAria: 'إلغاء تصنيف {name}',
      all: 'الكل',
      categoryFallback: 'تصنيف',
      noCategoryMatch: 'لا توجد تصنيفات تطابق كلمة البحث.',
      recentlyUsed: 'المستخدمة مؤخراً',
      loadResultsFailed: 'تعذر تحميل النتائج',
      specializeIn: 'متخصص في {service}',
      noResults: 'لا توجد نتائج',
      currentLocation: 'موقعك الحالي',
      currentLocationFailed: 'تعذر تحديد موقعك الحالي.',
      providerFallback: 'مزود خدمة',
      viewProfile: 'عرض ملف {name}',
      featured: 'مميز',
      kilometersShort: '{distance} كم',
      verified: 'موثّق',
      excellenceBadge: 'شارة تميز',
      distanceFromYou: 'يبعد عنك {distance} كم',
      ratingsCount: '{count} تقييم',
      noRatings: 'بدون تقييمات',
      completedRequests: 'طلبات مكتملة',
      followers: 'متابعون',
      directRequestFrom: 'طلب خدمة مباشرة من {name}',
      requestService: 'طلب خدمة',
      startRequestWithProvider: 'ابدأ الطلب مع هذا المزود',
      greetingWhatsapp: 'السلام عليكم، أتواصل معك عبر منصة نوافذ بخصوص طلب خدمة.',
      completedRequestsWithCount: 'طلبات مكتملة: {count}',
      startNow: 'ابدأ الآن',
      profile: 'الملف',
      call: 'اتصال',
      whatsapp: 'واتس اب',
      messages: 'رسائل',
      promoOffer: 'عرض ترويجي',
    },
    en: {
      pageTitle: 'Search Providers',
      back: 'Back',
      liveResults: 'Live results updates',
      kicker: 'Professional discovery',
      heading: 'Find a service provider',
      subtitle: 'Search quickly, compare confidently, and start the request directly from the same result without distracting extra steps.',
      searchPlaceholder: 'Search by provider name, specialty, or category...',
      clear: 'Clear',
      signalVerified: 'Verified providers',
      signalRequest: 'Instant request',
      signalMap: 'Live map',
      totalResults: 'Total results',
      resultsCount: '{count} results',
      map: 'Map',
      sortResults: 'Sort results',
      activeCategory: 'Current category: {name}',
      allCategories: 'All categories',
      changeCategory: 'Change category - {name}',
      chooseCategory: 'Choose category',
      readyProviders: 'Providers ready for work',
      resultsNote: 'Cards show trust, activity, and the fastest action at a glance.',
      noSearchResults: 'No results match the current search.',
      chooseCategoryTitle: 'Choose a category',
      close: 'Close',
      searchCategoryPlaceholder: 'Search for a category...',
      categoriesCount: '{count} categories',
      categoriesCountOfTotal: '{count} of {total} categories',
      chooseAll: 'Select all',
      sortBy: 'Sort by',
      sortDefault: 'Default',
      sortNearest: 'Nearest',
      sortRating: 'Highest rated',
      sortCompleted: 'Most completed requests',
      sortFollowers: 'Most followed',
      providersMap: 'Providers map',
      providersMapInCity: 'Providers map - {city}',
      locationUnavailableDistance: 'Unable to determine your location right now. Results will be shown without distance.',
      clearCategoryAria: 'Clear category {name}',
      all: 'All',
      categoryFallback: 'Category',
      noCategoryMatch: 'No categories match the search term.',
      recentlyUsed: 'Recently used',
      loadResultsFailed: 'Unable to load results',
      specializeIn: 'Specialized in {service}',
      noResults: 'No results',
      currentLocation: 'Your current location',
      currentLocationFailed: 'Unable to determine your current location.',
      providerFallback: 'Service provider',
      viewProfile: 'View profile {name}',
      featured: 'Featured',
      kilometersShort: '{distance} km',
      verified: 'Verified',
      excellenceBadge: 'Excellence badge',
      distanceFromYou: '{distance} km away from you',
      ratingsCount: '{count} ratings',
      noRatings: 'No ratings',
      completedRequests: 'Completed requests',
      followers: 'Followers',
      directRequestFrom: 'Direct request from {name}',
      requestService: 'Request service',
      startRequestWithProvider: 'Start the request with this provider',
      greetingWhatsapp: 'Hello, I am contacting you via Nawafeth regarding a service request.',
      completedRequestsWithCount: 'Completed requests: {count}',
      startNow: 'Start now',
      profile: 'Profile',
      call: 'Call',
      whatsapp: 'WhatsApp',
      messages: 'Messages',
      promoOffer: 'Promotional offer',
    },
  };

  let _providers = [];
  let _activeCat = '';
  let _activeSubcategory = '';
  let _query = '';
  let _activeCity = '';
  let _urgentOnly = false;
  let _selectedSort = 'default';
  let _debounce = null;
  let _distanceKmByProviderId = {};
  let _clientPosition = null;
  let _sortSheetOpen = false;
  let _openMapAfterFirstRender = false;
  let _mapModalOpen = false;
  let _mapInstance = null;
  let _mapMarkersLayer = null;
  let _featuredProviderIds = new Set();
  let _searchPromoPlacements = [];
  let _categoriesById = new Map();
  let _categories = [];
  let _promoBannerEl = null;
  let _lastCategoryPopupKey = '';
  let _isProvidersMapPage = false;
  let _providerFetchSeq = 0;
  const _providerListCache = new Map();
  let _categoryPickerOpen = false;
  let _categoryPickerFilter = '';
  let _categoryPickerVisibleIds = [];
  let _categoryPickerHighlightIndex = -1;

  const _quickCategoryLimit = 6;
  const _recentCategoryLimit = 6;
  const _recentCategoryStorageKey = 'nw_search_recent_category_ids';

  let _input;
  let _clearBtn;
  let _providersList;
  let _emptyState;
  let _resultsCount;
  let _sortSheet;
  let _sortBackdrop;
  let _mapBtn;
  let _mapBackdrop;
  let _mapModal;
  let _resultsLink;
  let _myLocationBtn;
  let _categorySummary;
  let _categoryOpenBtn;
  let _categoryPickerBackdrop;
  let _categoryPickerModal;
  let _categoryPickerSearch;
  let _categoryPickerCount;
  let _categoryPickerQuick;
  let _categoryPickerList;

  function init() {
    _isProvidersMapPage = !!(document.body && document.body.classList.contains('page-providers-map'));
    _input = document.getElementById('search-input');
    _clearBtn = document.getElementById('search-clear');
    _providersList = document.getElementById('providers-list');
    _emptyState = document.getElementById('empty-state');
    _resultsCount = document.getElementById('results-count');
    _sortSheet = document.getElementById('sort-sheet');
    _sortBackdrop = document.getElementById('sort-sheet-backdrop');
    _mapBtn = document.getElementById('search-map-btn');
    _mapBackdrop = document.getElementById('search-map-backdrop');
    _mapModal = document.getElementById('search-map-modal');
    _resultsLink = document.getElementById('search-results-link');
    _myLocationBtn = document.getElementById('providers-map-my-location');
    _categorySummary = document.getElementById('search-active-category');
    _categoryOpenBtn = document.getElementById('search-open-categories');
    _categoryPickerBackdrop = document.getElementById('category-picker-backdrop');
    _categoryPickerModal = document.getElementById('category-picker-modal');
    _categoryPickerSearch = document.getElementById('category-picker-search');
    _categoryPickerCount = document.getElementById('category-picker-count');
    _categoryPickerQuick = document.getElementById('category-picker-quick');
    _categoryPickerList = document.getElementById('category-picker-list');

    _applyStaticCopy();
    _renderCategoryChips(_categories);
    document.addEventListener('nawafeth:languagechange', _handleLanguageChange);

    if (!_input || !_providersList) return;

    _promoBannerEl = document.getElementById('search-promo-banner');

    _bindHeader();
    _bindSearch();
    _bindCategoryFilter();
    _bindCategoryPicker();
    _bindSortSheet();
    _bindMapModal();

    const params = new URLSearchParams(window.location.search);
    const urlQ = (params.get('q') || '').trim();
    const urlCat = (params.get('category') || params.get('category_id') || '').trim();
    const urlSubcategory = (params.get('subcategory') || params.get('subcategory_id') || '').trim();
    const urlCity = (params.get('city') || '').trim();
    const urlSort = (params.get('sort') || '').trim();
    _urgentOnly = (params.get('urgent') || '').trim() === '1';
    _openMapAfterFirstRender = (params.get('open_map') || '').trim() === '1';
    if (urlQ) {
      _input.value = urlQ;
      _query = urlQ;
      _clearBtn.classList.remove('hidden');
    }
    if (urlCat) _activeCat = urlCat;
    if (urlSubcategory) _activeSubcategory = urlSubcategory;
    if (urlCity) _activeCity = urlCity;
    if (urlSort) _selectedSort = urlSort;
    _syncResultsLink();

    _renderLoading();
    _fetchCategories().finally(() => {
      _loadSearchPromos();
    });
    _fetchProviders();
  }

  function _bindHeader() {
    const backBtn = document.getElementById('search-back-btn');
    if (!backBtn) return;
    backBtn.addEventListener('click', () => {
      if (window.history.length > 1) window.history.back();
      else window.location.href = '/';
    });
  }

  function _bindSearch() {
    _input.addEventListener('input', () => {
      _clearBtn.classList.toggle('hidden', !_input.value);
      clearTimeout(_debounce);
      _debounce = setTimeout(() => {
        _query = _input.value.trim();
        _fetchProviders();
      }, 400);
    });

    _clearBtn.addEventListener('click', () => {
      _input.value = '';
      _clearBtn.classList.add('hidden');
      _query = '';
      _fetchProviders();
      _input.focus();
    });
  }

  function _bindCategoryFilter() {
    const row = document.getElementById('filter-row');
    if (row) {
      row.addEventListener('click', e => {
        const chip = e.target.closest('.filter-chip');
        if (!chip) return;
        if (chip.dataset.categoryAction === 'open-picker') {
          _openCategoryPicker();
          return;
        }
        _selectCategory(chip.dataset.catId || '');
      });
    }

    if (_categoryOpenBtn) {
      _categoryOpenBtn.addEventListener('click', _openCategoryPicker);
    }
  }

  function _bindCategoryPicker() {
    const closeBtn = document.getElementById('category-picker-close');
    const resetBtn = document.getElementById('category-picker-reset');

    if (_categoryPickerBackdrop) _categoryPickerBackdrop.addEventListener('click', _closeCategoryPicker);
    if (closeBtn) closeBtn.addEventListener('click', _closeCategoryPicker);
    if (resetBtn) {
      resetBtn.addEventListener('click', () => {
        _selectCategory('', { closePicker: true, focusSearchInput: false });
      });
    }

    if (_categoryPickerQuick) {
      _categoryPickerQuick.addEventListener('click', (event) => {
        const chip = event.target.closest('[data-cat-id]');
        if (!chip) return;
        _selectCategory(chip.dataset.catId || '', { closePicker: true, focusSearchInput: false });
      });
    }

    if (_categoryPickerList) {
      _categoryPickerList.addEventListener('click', (event) => {
        const row = event.target.closest('[data-cat-id]');
        if (!row) return;
        _selectCategory(row.dataset.catId || '', { closePicker: true, focusSearchInput: false });
      });
    }

    if (_categoryPickerSearch) {
      _categoryPickerSearch.addEventListener('input', () => {
        _categoryPickerFilter = _categoryPickerSearch.value.trim();
        _categoryPickerHighlightIndex = -1;
        _renderCategoryPickerList();
      });

      _categoryPickerSearch.addEventListener('keydown', (event) => {
        if (!_categoryPickerOpen) return;
        if (event.key === 'Escape') {
          event.preventDefault();
          _closeCategoryPicker();
          return;
        }
        if (event.key === 'ArrowDown') {
          event.preventDefault();
          _moveCategoryPickerHighlight(1);
          return;
        }
        if (event.key === 'ArrowUp') {
          event.preventDefault();
          _moveCategoryPickerHighlight(-1);
          return;
        }
        if (event.key === 'Enter') {
          const activeId = _categoryPickerVisibleIds[_categoryPickerHighlightIndex];
          if (typeof activeId === 'undefined') return;
          event.preventDefault();
          _selectCategory(String(activeId || ''), { closePicker: true, focusSearchInput: false });
        }
      });
    }

    document.addEventListener('keydown', (event) => {
      if (event.key === 'Escape' && _categoryPickerOpen) {
        _closeCategoryPicker();
      }
    });
  }

  function _bindSortSheet() {
    const sortBtn = document.getElementById('search-sort-btn');
    if (sortBtn) sortBtn.addEventListener('click', _openSortSheet);

    if (_sortBackdrop) _sortBackdrop.addEventListener('click', _closeSortSheet);

    if (_sortSheet) {
      _sortSheet.addEventListener('click', async e => {
        const option = e.target.closest('.sort-sheet-option');
        if (!option) return;
        await _applySort(option.dataset.sortKey || 'default', true);
        _closeSortSheet();
      });
    }

    document.addEventListener('keydown', e => {
      if (e.key === 'Escape' && _sortSheetOpen) _closeSortSheet();
    });
  }

  function _bindMapModal() {
    if (_myLocationBtn) {
      _myLocationBtn.addEventListener('click', _focusClientLocation);
    }

    if (_isProvidersMapPage) {
      return;
    }

    if (_mapBtn) _mapBtn.addEventListener('click', _openMapModal);

    const closeBtn = document.getElementById('search-map-close');
    if (closeBtn) closeBtn.addEventListener('click', _closeMapModal);
    if (_mapBackdrop) _mapBackdrop.addEventListener('click', _closeMapModal);

    document.addEventListener('keydown', e => {
      if (e.key === 'Escape' && _mapModalOpen) _closeMapModal();
    });
  }

  function _openSortSheet() {
    if (_sortSheetOpen || !_sortSheet || !_sortBackdrop) return;
    _closeCategoryPicker();
    _sortSheetOpen = true;
    _syncSortOptions();
    _sortBackdrop.classList.remove('hidden');
    _sortSheet.classList.remove('hidden');
    requestAnimationFrame(() => {
      _sortBackdrop.classList.add('active');
      _sortSheet.classList.add('open');
    });
    _syncBodyScrollLock();
  }

  function _closeSortSheet() {
    if (!_sortSheetOpen || !_sortSheet || !_sortBackdrop) return;
    _sortSheetOpen = false;
    _sortBackdrop.classList.remove('active');
    _sortSheet.classList.remove('open');
    setTimeout(() => {
      _sortBackdrop.classList.add('hidden');
      _sortSheet.classList.add('hidden');
    }, 180);
    _syncBodyScrollLock();
  }

  function _syncSortOptions() {
    if (!_sortSheet) return;
    _sortSheet.querySelectorAll('.sort-sheet-option').forEach(btn => {
      btn.classList.toggle('active', (btn.dataset.sortKey || '') === _selectedSort);
    });
  }

  function _syncBodyScrollLock() {
    const shouldLock = _sortSheetOpen || _mapModalOpen || _categoryPickerOpen;
    document.body.style.overflow = shouldLock ? 'hidden' : '';
  }

  async function _applySort(sortKey, requestLocationPermission) {
    _selectedSort = sortKey || 'default';
    _syncSortOptions();
    if (_selectedSort === 'nearest') {
      await _ensureDistanceMap(!!requestLocationPermission);
      if (!Object.keys(_distanceKmByProviderId).length) {
        _showToast(_copy('locationUnavailableDistance'));
      }
    }
    _renderProviders();
    _syncResultsLink();
  }

  async function _fetchCategories() {
    const cached = NwCache.get('search_categories');
    if (cached && Array.isArray(cached.data)) _renderCategoryChips(cached.data);

    const res = await ApiClient.get('/api/providers/categories/');
    if (!res.ok || !res.data) return;
    const list = Array.isArray(res.data) ? res.data : (res.data.results || []);
    NwCache.set('search_categories', list, 300);
    _renderCategoryChips(list);
  }

  function _renderCategoryChips(cats) {
    const row = document.getElementById('filter-row');
    if (!row) return;
    row.textContent = '';
    _categories = Array.isArray(cats)
      ? cats.filter(cat => cat && cat.id !== null && typeof cat.id !== 'undefined')
      : [];
    _categoriesById = new Map();

    if (!_activeCat && _activeSubcategory) {
      const matchedCategory = _categories.find(cat => Array.isArray(cat?.subcategories) && cat.subcategories.some(sub => String(sub?.id || '') === String(_activeSubcategory)));
      if (matchedCategory && matchedCategory.id) {
        _activeCat = String(matchedCategory.id);
      }
    }

    // 1) Active category as a prominent dismissable chip (if any)
    if (_activeCat) {
      const activeCatObj = _categories.find(c => String(c.id) === String(_activeCat));
      if (activeCatObj) {
        const activeChip = _createFilterChip(activeCatObj.name || '', String(activeCatObj.id), true, '');
        activeChip.classList.add('filter-chip-active-pinned');
        const x = document.createElement('span');
        x.className = 'filter-chip-x';
        x.setAttribute('aria-hidden', 'true');
        x.textContent = '×';
        activeChip.appendChild(x);
        activeChip.setAttribute('aria-label', _copy('clearCategoryAria', { name: activeCatObj.name || '' }));
        // Clicking the active chip clears (handled by existing handler that toggles to '' when same id)
        activeChip.dataset.catId = '';
        row.appendChild(activeChip);
      }
    }

    // 2) "All" chip
    row.appendChild(_createFilterChip(_copy('all'), '', !_activeCat, ''));

    // 3) Quick category chips
    const quickCategories = _buildQuickCategories(_categories);
    quickCategories.forEach(cat => {
      // Skip the active one — already shown as pinned dismissable chip
      if (_activeCat && String(cat.id) === String(_activeCat)) return;
      row.appendChild(_createFilterChip(cat.name || '', String(cat.id), false, ''));
      _categoriesById.set(String(cat.id), {
        id: cat.id,
        name: String(cat.name || '').trim(),
      });
    });

    _categories.forEach(cat => {
      if (_categoriesById.has(String(cat.id))) return;
      _categoriesById.set(String(cat.id), {
        id: cat.id,
        name: String(cat.name || '').trim(),
      });
    });

    _syncCategorySummary();
    _renderCategoryPicker();
  }

  function _createFilterChip(label, catId, active, action) {
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'filter-chip' + (active ? ' active' : '');
    btn.dataset.catId = String(catId || '');
    if (action) btn.dataset.categoryAction = action;
    btn.textContent = String(label || '').trim() || _copy('categoryFallback');
    return btn;
  }

  function _buildQuickCategories(cats) {
    const quick = [];
    const seen = new Set();
    const byId = new Map((Array.isArray(cats) ? cats : []).map(cat => [String(cat.id), cat]));

    const push = (cat) => {
      if (!cat || cat.id === null || typeof cat.id === 'undefined') return;
      const key = String(cat.id);
      if (seen.has(key)) return;
      seen.add(key);
      quick.push(cat);
    };

    if (_activeCat) push(byId.get(String(_activeCat)));
    _readRecentCategoryIds().forEach(id => push(byId.get(String(id))));
    (Array.isArray(cats) ? cats : []).forEach(push);

    return quick.slice(0, _quickCategoryLimit);
  }

  function _selectCategory(catId, options) {
    const opts = options || {};
    const nextCat = String(catId || '');
    const changed = String(_activeCat || '') !== nextCat || !!_activeSubcategory;

    _activeCat = nextCat;
    _activeSubcategory = '';

    if (_activeCat) _rememberRecentCategory(_activeCat);
    _renderCategoryChips(_categories);

    if (opts.closePicker) _closeCategoryPicker();
    if (!changed) return;

    _loadSearchPromos();
    _fetchProviders();
  }

  function _openCategoryPicker() {
    if (_categoryPickerOpen || !_categoryPickerModal || !_categoryPickerBackdrop) return;
    _closeSortSheet();
    _closeMapModal();
    _categoryPickerOpen = true;
    _categoryPickerFilter = '';
    _categoryPickerHighlightIndex = -1;
    if (_categoryPickerSearch) _categoryPickerSearch.value = '';
    _renderCategoryPicker();

    _categoryPickerBackdrop.classList.remove('hidden');
    _categoryPickerModal.classList.remove('hidden');
    requestAnimationFrame(() => {
      _categoryPickerBackdrop.classList.add('active');
      _categoryPickerModal.classList.add('open');
      if (_categoryPickerSearch) _categoryPickerSearch.focus();
    });
    _syncBodyScrollLock();
  }

  function _closeCategoryPicker() {
    if (!_categoryPickerOpen || !_categoryPickerModal || !_categoryPickerBackdrop) return;
    _categoryPickerOpen = false;
    _categoryPickerBackdrop.classList.remove('active');
    _categoryPickerModal.classList.remove('open');
    setTimeout(() => {
      _categoryPickerBackdrop.classList.add('hidden');
      _categoryPickerModal.classList.add('hidden');
    }, 180);
    _syncBodyScrollLock();
  }

  function _renderCategoryPicker() {
    _renderCategoryPickerQuick();
    _renderCategoryPickerList();
    _syncCategorySummary();
  }

  function _renderCategoryPickerQuick() {
    if (!_categoryPickerQuick) return;
    _categoryPickerQuick.textContent = '';
    const frag = document.createDocumentFragment();
    frag.appendChild(_createQuickPickerItem(_copy('all'), '', !_activeCat));
    _buildQuickCategories(_categories).forEach(cat => {
      frag.appendChild(
        _createQuickPickerItem(
          String(cat.name || '').trim() || _copy('categoryFallback'),
          String(cat.id || ''),
          String(_activeCat) === String(cat.id)
        )
      );
    });
    _categoryPickerQuick.appendChild(frag);
  }

  function _createQuickPickerItem(label, catId, active) {
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'category-picker-quick-item' + (active ? ' active' : '');
    btn.dataset.catId = String(catId || '');
    btn.textContent = label;
    return btn;
  }

  function _filteredCategoriesForPicker() {
    const needle = _normalizeSearchText(_categoryPickerFilter);
    if (!needle) return [..._categories];
    return _categories.filter(cat => _normalizeSearchText(cat?.name).includes(needle));
  }

  function _renderCategoryPickerList() {
    if (!_categoryPickerList) return;
    const filtered = _filteredCategoriesForPicker();
    _categoryPickerVisibleIds = filtered.map(cat => String(cat.id || ''));

    if (_categoryPickerCount) {
      _categoryPickerCount.textContent = _copy('categoriesCountOfTotal', {
        count: filtered.length,
        total: _categories.length,
      });
    }

    _categoryPickerList.textContent = '';
    if (!filtered.length) {
      const empty = document.createElement('div');
      empty.className = 'category-picker-empty';
      empty.textContent = _copy('noCategoryMatch');
      _categoryPickerList.appendChild(empty);
      _categoryPickerHighlightIndex = -1;
      return;
    }

    const frag = document.createDocumentFragment();
    const isSearching = !!_normalizeSearchText(_categoryPickerFilter);
    const recentSet = new Set();

    // Recents section (only shown when not searching)
    if (!isSearching) {
      const recentIds = _readRecentCategoryIds();
      const byId = new Map(_categories.map(c => [String(c.id), c]));
      const recents = recentIds.map(id => byId.get(String(id))).filter(Boolean);
      if (recents.length) {
        frag.appendChild(_makePickerSectionHeader(_copy('recentlyUsed'), recents.length, 'recent'));
        recents.forEach(cat => {
          recentSet.add(String(cat.id));
          frag.appendChild(_makePickerItem(cat));
        });
      }
    }

    // Group remaining by Arabic first letter (or A-Z), excluding ones already shown in recents
    const groups = new Map();
    filtered.forEach(cat => {
      if (recentSet.has(String(cat.id))) return;
      const name = String(cat.name || '').trim();
      const ch = name.charAt(0).toUpperCase() || '#';
      if (!groups.has(ch)) groups.set(ch, []);
      groups.get(ch).push(cat);
    });

    // Sort group keys (Arabic locale aware)
    const sortedKeys = Array.from(groups.keys()).sort((a, b) => a.localeCompare(b, 'ar'));
    sortedKeys.forEach(letter => {
      const items = groups.get(letter);
      frag.appendChild(_makePickerSectionHeader(letter, items.length, 'letter'));
      items
        .slice()
        .sort((a, b) => String(a.name || '').localeCompare(String(b.name || ''), 'ar'))
        .forEach(cat => frag.appendChild(_makePickerItem(cat)));
    });

    _categoryPickerList.appendChild(frag);

    if (_categoryPickerHighlightIndex < 0 || _categoryPickerHighlightIndex >= filtered.length) {
      const selectedIndex = filtered.findIndex(cat => String(cat.id || '') === String(_activeCat || ''));
      _categoryPickerHighlightIndex = selectedIndex >= 0 ? selectedIndex : 0;
    }
    _applyCategoryPickerHighlight();
  }

  function _makePickerSectionHeader(label, count, kind) {
    const h = document.createElement('div');
    h.className = 'category-picker-section' + (kind ? ' is-' + kind : '');
    const lbl = document.createElement('span');
    lbl.className = 'category-picker-section-label';
    lbl.textContent = label;
    const cnt = document.createElement('span');
    cnt.className = 'category-picker-section-count';
    cnt.textContent = String(count);
    h.appendChild(lbl);
    h.appendChild(cnt);
    return h;
  }

  function _makePickerItem(cat) {
    const id = String(cat.id || '');
    const isActive = String(_activeCat || '') === id;
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'category-picker-item' + (isActive ? ' is-active' : '');
    btn.dataset.catId = id;
    btn.setAttribute('aria-pressed', isActive ? 'true' : 'false');
    btn.appendChild(document.createTextNode(String(cat.name || '').trim() || (_copy('categoryFallback') + ' ' + id)));
    const check = document.createElement('span');
    check.className = 'category-picker-item-check';
    check.textContent = isActive ? '✓' : '';
    btn.appendChild(check);
    return btn;
  }

  function _moveCategoryPickerHighlight(delta) {
    if (!_categoryPickerVisibleIds.length) return;
    const last = _categoryPickerVisibleIds.length - 1;
    const step = delta > 0 ? 1 : -1;
    if (_categoryPickerHighlightIndex < 0) {
      const selectedIndex = _categoryPickerVisibleIds.findIndex(id => String(id) === String(_activeCat || ''));
      _categoryPickerHighlightIndex = selectedIndex >= 0 ? selectedIndex : 0;
      if (step < 0 && _categoryPickerHighlightIndex === 0) {
        _applyCategoryPickerHighlight();
        return;
      }
    } else {
      _categoryPickerHighlightIndex += step;
    }
    if (_categoryPickerHighlightIndex < 0) _categoryPickerHighlightIndex = 0;
    if (_categoryPickerHighlightIndex > last) _categoryPickerHighlightIndex = last;
    _applyCategoryPickerHighlight();
  }

  function _applyCategoryPickerHighlight() {
    if (!_categoryPickerList) return;
    const rows = Array.from(_categoryPickerList.querySelectorAll('.category-picker-item'));
    rows.forEach((row, index) => {
      row.classList.toggle('is-highlighted', index === _categoryPickerHighlightIndex);
    });
    const activeRow = rows[_categoryPickerHighlightIndex];
    if (activeRow && typeof activeRow.scrollIntoView === 'function') {
      activeRow.scrollIntoView({ block: 'nearest' });
    }
  }

  function _syncCategorySummary() {
    const selectedName = _selectedCategoryName();
    const total = _categories.length;
    if (_categorySummary) {
      _categorySummary.textContent = _copy('activeCategory', { name: selectedName || _copy('all') });
    }
    if (_categoryOpenBtn) {
      _categoryOpenBtn.setAttribute('title', selectedName ? _copy('changeCategory', { name: selectedName }) : _copy('chooseCategory'));
      // Maintain a count badge inside the button (created on demand)
      let badge = _categoryOpenBtn.querySelector('.search-open-categories-count');
      if (total > 0) {
        if (!badge) {
          badge = document.createElement('span');
          badge.className = 'search-open-categories-count';
          _categoryOpenBtn.appendChild(badge);
        }
        badge.textContent = String(total);
      } else if (badge) {
        badge.remove();
      }
    }
  }

  function _readRecentCategoryIds() {
    try {
      const raw = localStorage.getItem(_recentCategoryStorageKey);
      const list = raw ? JSON.parse(raw) : [];
      if (!Array.isArray(list)) return [];
      return list
        .map(value => String(value || '').trim())
        .filter(Boolean)
        .slice(0, _recentCategoryLimit);
    } catch (_) {
      return [];
    }
  }

  function _writeRecentCategoryIds(ids) {
    try {
      localStorage.setItem(_recentCategoryStorageKey, JSON.stringify(ids.slice(0, _recentCategoryLimit)));
    } catch (_) {
      // Ignore storage errors.
    }
  }

  function _rememberRecentCategory(catId) {
    const normalized = String(catId || '').trim();
    if (!normalized) return;
    const next = [normalized, ..._readRecentCategoryIds().filter(id => id !== normalized)];
    _writeRecentCategoryIds(next);
  }

  async function _fetchProviders() {
    const fetchSeq = ++_providerFetchSeq;
    _renderLoading();

    const primaryUrl = _buildProvidersUrl({
      includeQuery: true,
      pageSize: _query ? 90 : 30,
    });
    const res = await _getProvidersResponse(primaryUrl);
    if (fetchSeq !== _providerFetchSeq) return;
    if (!res.ok || !res.data) {
      _providers = [];
      _distanceKmByProviderId = {};
      _showEmpty(res.error || _copy('loadResultsFailed'));
      return;
    }

    _providers = _applyProviderFilters(Array.isArray(res.data) ? res.data : (res.data.results || []));

    if (_query && !_providers.length) {
      const fallbackUrl = _buildProvidersUrl({
        includeQuery: false,
        pageSize: 90,
      });
      const fallbackRes = await _getProvidersResponse(fallbackUrl);
      if (fetchSeq !== _providerFetchSeq) return;
      if (fallbackRes.ok && fallbackRes.data) {
        _providers = _applyProviderFilters(
          Array.isArray(fallbackRes.data) ? fallbackRes.data : (fallbackRes.data.results || [])
        );
      }
    }

    await _ensureDistanceMap(_isProvidersMapPage || _selectedSort === 'nearest');
    if (fetchSeq !== _providerFetchSeq) return;
    _renderProviders();
    _syncResultsLink();
  }

  async function _getProvidersResponse(url) {
    const cached = _providerListCache.get(url);
    if (cached && cached.expiresAt > Date.now()) return cached.value;
    const res = await ApiClient.get(url);
    if (res && res.ok) {
      _providerListCache.set(url, {
        value: res,
        expiresAt: Date.now() + 30000,
      });
      if (_providerListCache.size > 24) {
        const firstKey = _providerListCache.keys().next().value;
        if (firstKey) _providerListCache.delete(firstKey);
      }
    }
    return res;
  }

  function _buildProvidersUrl(options) {
    const settings = options || {};
    const includeQuery = settings.includeQuery !== false;
    const pageSize = Number(settings.pageSize) || 30;
    let url = '/api/providers/list/?page_size=' + pageSize;
    if (includeQuery && _query) url += '&q=' + encodeURIComponent(_query);
    if (_activeCat) url += '&category_id=' + encodeURIComponent(_activeCat);
    if (_activeSubcategory) url += '&subcategory_id=' + encodeURIComponent(_activeSubcategory);
    if (_activeCity) url += '&city=' + encodeURIComponent(_activeCity);
    if (_urgentOnly) url += '&accepts_urgent=1';
    return url;
  }

  function _applyProviderFilters(providers) {
    let filtered = Array.isArray(providers) ? [...providers] : [];
    if (_activeCity) {
      filtered = filtered.filter(provider => {
        const providerCity = _normalizeSearchText(provider?.city);
        const providerCityDisplay = _normalizeSearchText(provider?.city_display);
        const activeCity = _normalizeSearchText(_activeCity);
        return !!activeCity && (providerCity === activeCity || providerCityDisplay === activeCity);
      });
    }
    if (_urgentOnly) {
      filtered = filtered.filter(provider => {
        const urgent = provider?.accepts_urgent ?? provider?.isUrgentEnabled ?? provider?.is_urgent_enabled;
        return !!urgent;
      });
    }
    return _filterProvidersByQuery(filtered);
  }

  function _filterProvidersByQuery(providers) {
    if (!_query) return providers;
    const tokens = _normalizeSearchText(_query).split(/\s+/).filter(Boolean);
    if (!tokens.length) return providers;
    return providers.filter(provider => {
      const haystack = _providerSearchHaystack(provider);
      return tokens.every(token => haystack.includes(token));
    });
  }

  function _providerSearchHaystack(provider) {
    const selectedSubcategories = Array.isArray(provider?.selected_subcategories)
      ? provider.selected_subcategories.map(item => item?.name)
      : [];
    const mainCategories = Array.isArray(provider?.main_categories)
      ? provider.main_categories
      : [];
    return _normalizeSearchText([
      provider?.display_name,
      provider?.headline,
      provider?.short_bio,
      provider?.bio,
      provider?.about,
      provider?.description,
      provider?.about_me,
      provider?.city_display,
      provider?.city,
      provider?.region,
      provider?.region_name,
      provider?.primary_subcategory_name,
      provider?.subcategory_name,
      provider?.primary_category_name,
      provider?.category_name,
      ...selectedSubcategories,
      ...mainCategories,
    ].join(' '));
  }

  function _normalizeSearchText(value) {
    return String(value || '')
      .toLowerCase()
      .replace(/[\u064B-\u065F\u0670]/g, '')
      .replace(/ـ/g, '')
      .replace(/[أإآ]/g, 'ا')
      .replace(/ى/g, 'ي')
      .replace(/ة/g, 'ه')
      .replace(/ؤ/g, 'و')
      .replace(/ئ/g, 'ي')
      .replace(/[^\p{L}\p{N}\s]+/gu, ' ')
      .replace(/\s+/g, ' ')
      .trim();
  }

  async function _ensureDistanceMap(requestPermission) {
    if (!_providers.length) {
      _distanceKmByProviderId = {};
      return;
    }
    if (_selectedSort !== 'nearest' && _clientPosition === null && !requestPermission) {
      return;
    }

    const pos = await _resolveClientPosition(requestPermission);
    if (!pos) {
      if (_selectedSort === 'nearest') _distanceKmByProviderId = {};
      return;
    }

    const map = {};
    _providers.forEach(provider => {
      const lat = _safeNum(provider.lat ?? provider.latitude);
      const lng = _safeNum(provider.lng ?? provider.longitude);
      if (!Number.isFinite(lat) || !Number.isFinite(lng)) return;
      map[provider.id] = _haversineKm(pos.lat, pos.lng, lat, lng);
    });
    _distanceKmByProviderId = map;
  }

  async function _resolveClientPosition(requestPermission) {
    if (_clientPosition) return _clientPosition;
    if (!navigator.geolocation || !requestPermission) return null;

    try {
      const pos = await new Promise((resolve, reject) => {
        navigator.geolocation.getCurrentPosition(resolve, reject, {
          enableHighAccuracy: true,
          timeout: 8000,
          maximumAge: 120000,
        });
      });
      _clientPosition = {
        lat: _safeNum(pos.coords.latitude),
        lng: _safeNum(pos.coords.longitude),
      };
      if (!Number.isFinite(_clientPosition.lat) || !Number.isFinite(_clientPosition.lng)) {
        _clientPosition = null;
      }
    } catch (_) {
      _clientPosition = null;
    }
    return _clientPosition;
  }

  function _renderLoading() {
    if (!_providersList) return;
    _providersList.innerHTML = [
      _providerSkeleton(),
      _providerSkeleton(),
      _providerSkeleton(),
    ].join('');
    if (_emptyState) _emptyState.classList.add('hidden');
  }

  function _providerSkeleton() {
    return [
      '<div class="provider-search-skeleton">',
      '<div class="provider-search-skeleton-cover"></div>',
      '<div class="provider-search-skeleton-body">',
      '<div class="provider-search-skeleton-line is-short"></div>',
      '<div class="provider-search-skeleton-line is-wide"></div>',
      '<div class="provider-search-skeleton-meta">',
      '<span class="provider-search-skeleton-pill"></span>',
      '<span class="provider-search-skeleton-pill"></span>',
      '<span class="provider-search-skeleton-pill"></span>',
      '</div>',
      '<div class="provider-search-skeleton-actions">',
      '<span class="provider-search-skeleton-btn is-primary"></span>',
      '<span class="provider-search-skeleton-btn is-secondary"></span>',
      '</div>',
      '</div>',
      '</div>',
    ].join('');
  }

  function _providerServiceLabel(provider) {
    const subcategories = Array.isArray(provider?.selected_subcategories)
      ? provider.selected_subcategories
          .map(item => String(item?.name || '').trim())
          .filter(Boolean)
      : [];
    const categories = Array.isArray(provider?.main_categories)
      ? provider.main_categories
          .map(item => String(item || '').trim())
          .filter(Boolean)
      : [];
    const candidates = [
      subcategories.slice(0, 2).join(' • '),
      categories.slice(0, 2).join(' • '),
      String(provider?.primary_subcategory_name || '').trim(),
      String(provider?.subcategory_name || '').trim(),
      String(provider?.primary_category_name || '').trim(),
      String(provider?.category_name || '').trim(),
      _selectedCategoryName(),
    ];
    return candidates.find(Boolean) || '';
  }

  function _truncateText(value, maxLength) {
    const text = String(value || '').trim();
    if (!text || text.length <= maxLength) return text;
    return text.slice(0, Math.max(0, maxLength - 1)).trim() + '…';
  }

  function _providerSnippet(provider, serviceLabel) {
    const raw = [
      provider?.headline,
      provider?.short_bio,
      provider?.bio,
      provider?.about,
      provider?.description,
      provider?.about_me,
    ].map(value => String(value || '').trim()).find(Boolean);
    if (raw) return _truncateText(raw, 120);
    if (serviceLabel) return _copy('specializeIn', { service: serviceLabel });
    return '';
  }

  function _renderProviders() {
    if (!_providersList) return;
    let sorted = _applyPromoOrdering(_sortProviders(_providers));

    if (_resultsCount) _resultsCount.textContent = _copy('resultsCount', { count: sorted.length });
    if (_mapBtn) _mapBtn.classList.toggle('hidden', sorted.length === 0);

    _providersList.textContent = '';
    if (!sorted.length) {
      _showEmpty(_copy('noResults'));
      if (_isProvidersMapPage) _renderMap();
      return;
    }

    if (_emptyState) _emptyState.classList.add('hidden');

    const frag = document.createDocumentFragment();
    sorted.forEach(provider => {
      const card = _buildProviderCard(provider);
      if (_featuredProviderIds.has(String(provider.id))) {
        card.classList.add('promo-featured');
      }
      frag.appendChild(card);
    });
    _providersList.appendChild(frag);

    if (_isProvidersMapPage) {
      _renderMap();
      return;
    }

    if (_openMapAfterFirstRender) {
      _openMapAfterFirstRender = false;
      _openMapModal();
    }
  }

  function _openMapModal() {
    if (_isProvidersMapPage) {
      _renderMap();
      return;
    }
    if (_mapModalOpen || !_mapModal || !_mapBackdrop) return;
    _closeCategoryPicker();
    _closeSortSheet();
    _mapModalOpen = true;
    _mapBackdrop.classList.remove('hidden');
    _mapModal.classList.remove('hidden');
    requestAnimationFrame(() => {
      _mapBackdrop.classList.add('active');
      _mapModal.classList.add('open');
      _renderMap();
    });
    _syncBodyScrollLock();
  }

  function _closeMapModal() {
    if (!_mapModalOpen || !_mapModal || !_mapBackdrop) return;
    _mapModalOpen = false;
    _mapBackdrop.classList.remove('active');
    _mapModal.classList.remove('open');
    setTimeout(() => {
      _mapBackdrop.classList.add('hidden');
      _mapModal.classList.add('hidden');
    }, 180);
    _syncBodyScrollLock();
  }

  function _renderMap() {
    const canvas = document.getElementById('search-map-canvas');
    const title = document.getElementById('search-map-title');
    if (!canvas || typeof L === 'undefined') return;
    const hasClientPosition = !!(
      _clientPosition &&
      Number.isFinite(_clientPosition.lat) &&
      Number.isFinite(_clientPosition.lng)
    );

    const sorted = _applyPromoOrdering(_sortProviders(_providers)).filter(provider => {
      const lat = _safeNum(provider.lat ?? provider.latitude);
      const lng = _safeNum(provider.lng ?? provider.longitude);
      return Number.isFinite(lat) && Number.isFinite(lng) && (lat !== 0 || lng !== 0);
    });

    if (title) {
      title.textContent = _activeCity
        ? _copy('providersMapInCity', { city: _activeCity })
        : _copy('providersMap');
    }

    if (!_mapInstance) {
      _mapInstance = L.map(canvas, { scrollWheelZoom: false });
      L.tileLayer('https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png', {
        subdomains: 'abcd',
        maxZoom: 20,
        attribution: '&copy; OpenStreetMap &copy; CARTO',
      }).addTo(_mapInstance);
    }

    if (_mapMarkersLayer) {
      _mapMarkersLayer.clearLayers();
    } else {
      _mapMarkersLayer = L.layerGroup().addTo(_mapInstance);
    }

    if (!sorted.length) {
      if (hasClientPosition) {
        _mapInstance.setView([_clientPosition.lat, _clientPosition.lng], 12);
      } else {
        _mapInstance.setView([24.7136, 46.6753], 6);
      }
      setTimeout(() => {
        try { _mapInstance.invalidateSize(); } catch (_) {}
      }, 120);
      return;
    }

    const points = [];
    sorted.forEach(provider => {
      const lat = _safeNum(provider.lat ?? provider.latitude);
      const lng = _safeNum(provider.lng ?? provider.longitude);
      const marker = L.marker([lat, lng]);
      marker.bindPopup(_buildProviderMapPopupHtml(provider), {
        maxWidth: 290,
        className: 'search-map-provider-popup-wrap',
      });
      _mapMarkersLayer.addLayer(marker);
      points.push([lat, lng]);
    });

    if (_isProvidersMapPage && hasClientPosition) {
      const currentMarker = L.circleMarker([_clientPosition.lat, _clientPosition.lng], {
        radius: 7,
        color: '#4F46E5',
        fillColor: '#4F46E5',
        fillOpacity: 0.85,
        weight: 2,
      });
      currentMarker.bindPopup(_copy('currentLocation'));
      _mapMarkersLayer.addLayer(currentMarker);
    }

    if (points.length === 1) {
      _mapInstance.setView(points[0], 12);
    } else {
      const bounds = L.latLngBounds(points);
      _mapInstance.fitBounds(bounds, { padding: [24, 24] });
    }

    setTimeout(() => {
      try { _mapInstance.invalidateSize(); } catch (_) {}
    }, 120);
  }

  async function _focusClientLocation() {
    const pos = await _resolveClientPosition(true);
    if (!pos) {
      _showToast(_copy('currentLocationFailed'));
      return;
    }
    if (_mapInstance) {
      _mapInstance.setView([pos.lat, pos.lng], 13);
      return;
    }
    _renderMap();
    setTimeout(() => {
      if (_mapInstance) {
        _mapInstance.setView([pos.lat, pos.lng], 13);
      }
    }, 160);
  }

  function _syncResultsLink() {
    if (!_resultsLink) return;
    let baseHref = String(_resultsLink.getAttribute('href') || '/search/').trim();
    if (!baseHref) baseHref = '/search/';
    baseHref = baseHref.split('?')[0];

    const params = new URLSearchParams();
    if (_query) params.set('q', _query);
    if (_activeCat) params.set('category_id', _activeCat);
    if (_activeSubcategory) params.set('subcategory_id', _activeSubcategory);
    if (_activeCity) params.set('city', _activeCity);
    if (_urgentOnly) params.set('urgent', '1');
    if (_selectedSort && _selectedSort !== 'default') params.set('sort', _selectedSort);

    const query = params.toString();
    _resultsLink.href = query ? (baseHref + '?' + query) : baseHref;
  }

  function _sortProviders(list) {
    const sorted = [...list];
    if (_selectedSort === 'rating') {
      sorted.sort((a, b) => _safeNum(b.rating_avg) - _safeNum(a.rating_avg));
      return sorted;
    }
    if (_selectedSort === 'completed') {
      sorted.sort((a, b) => _completedCount(b) - _completedCount(a));
      return sorted;
    }
    if (_selectedSort === 'followers') {
      sorted.sort((a, b) => _safeInt(b.followers_count) - _safeInt(a.followers_count));
      return sorted;
    }
    if (_selectedSort === 'nearest') {
      sorted.sort((a, b) => {
        const da = _distanceKmByProviderId[a.id];
        const db = _distanceKmByProviderId[b.id];
        return (Number.isFinite(da) ? da : Number.POSITIVE_INFINITY) -
          (Number.isFinite(db) ? db : Number.POSITIVE_INFINITY);
      });
      return sorted;
    }
    return sorted;
  }

  function _applyPromoOrdering(sortedProviders) {
    let ordered = [...sortedProviders];
    const placements = [..._searchPromoPlacements].sort((a, b) => _promoPositionRank(a) - _promoPositionRank(b));
    let exactSlotsPlaced = 0;
    let top5Offset = 0;
    let top10Offset = 0;
    const handledProviderIds = new Set();

    placements.forEach(placement => {
      const providerId = String(placement?.target_provider_id || '').trim();
      if (!providerId || handledProviderIds.has(providerId)) return;
      const currentIndex = ordered.findIndex(provider => String(provider?.id || '') === providerId);
      if (currentIndex < 0) return;

      const [provider] = ordered.splice(currentIndex, 1);
      const position = String(placement?.search_position || '').trim().toLowerCase();
      let targetIndex = 0;
      if (position === 'first') {
        targetIndex = 0;
        exactSlotsPlaced = Math.max(exactSlotsPlaced, 1);
      }
      else if (position === 'second') {
        targetIndex = 1;
        exactSlotsPlaced = Math.max(exactSlotsPlaced, 2);
      }
      else if (position === 'top10') {
        targetIndex = exactSlotsPlaced + top5Offset + top10Offset;
        top10Offset += 1;
      } else {
        targetIndex = exactSlotsPlaced + top5Offset;
        top5Offset += 1;
      }
      if (targetIndex > ordered.length) targetIndex = ordered.length;
      ordered.splice(targetIndex, 0, provider);
      handledProviderIds.add(providerId);
    });

    if (!handledProviderIds.size && _featuredProviderIds.size) {
      const featured = ordered.filter(provider => _featuredProviderIds.has(String(provider.id)));
      const rest = ordered.filter(provider => !_featuredProviderIds.has(String(provider.id)));
      ordered = [...featured, ...rest];
    }

    return ordered;
  }

  function _promoPositionRank(placement) {
    const position = String(placement?.search_position || '').trim().toLowerCase();
    if (position === 'first') return 0;
    if (position === 'second') return 1;
    if (position === 'top5') return 2;
    if (position === 'top10') return 3;
    return 9;
  }

  function _readPromoString(value) {
    return String(value || '').trim();
  }

  function _selectedCategoryName() {
    if (!_activeCat) return '';
    const row = _categoriesById.get(String(_activeCat));
    return _readPromoString(row && row.name);
  }

  function _matchesSearchPromoScope(placement) {
    const scope = _readPromoString(placement?.search_scope).toLowerCase();
    if (!scope || scope === 'default' || scope === 'main_results') return true;
    if (scope === 'category_match') return !!_selectedCategoryName();
    return true;
  }

  function _matchesSearchPromoTargeting(placement) {
    const categoryContext = _selectedCategoryName().toLowerCase();
    const targetCategory = _readPromoString(placement?.target_category).toLowerCase();

    if (targetCategory) {
      if (!categoryContext) return false;
      if (targetCategory !== categoryContext) return false;
    }

    return true;
  }

  function _currentDirectRequestReturnTo() {
    return window.location.pathname + window.location.search;
  }

  function _buildDirectRequestHref(providerId) {
    if (!providerId) return '#';
    const params = new URLSearchParams();
    params.set('provider_id', String(providerId));
    params.set('return_to', _currentDirectRequestReturnTo());
    return '/service-request/?' + params.toString();
  }

  function _buildProviderCard(provider) {
    const displayName = (provider.display_name || '').trim() || _copy('providerFallback');
    const city = UI.formatCityDisplay(provider.city_display || provider.city, provider.region || provider.region_name);
    const profileUrl = ApiClient.mediaUrl(provider.profile_image);
    const coverUrl = ApiClient.mediaUrl(provider.cover_image);
    const providerProfileHref = '/provider/' + encodeURIComponent(String(provider.id || '')) + '/';
    const directRequestHref = _buildDirectRequestHref(provider.id || '');
    const initial = displayName.charAt(0) || '؟';
    const distanceKm = _distanceKmByProviderId[provider.id];
    const rating = _safeNum(provider.rating_avg);
    const ratingLabel = rating > 0 ? rating.toFixed(1) : '-';
    const ratingCount = _safeInt(provider.rating_count);
    const completed = _completedCount(provider);
    const followers = _safeInt(provider.followers_count);
    const serviceLabel = _providerServiceLabel(provider);
    const snippet = _providerSnippet(provider, serviceLabel);
    const isFeatured = _featuredProviderIds.has(String(provider.id));

    const card = UI.el('article', {
      className: 'provider-search-card',
      tabindex: '0',
      role: 'link',
      'aria-label': _copy('viewProfile', { name: displayName }),
    });
    if (isFeatured) card.classList.add('promo-featured');

    const trackProfileClick = () => {
      if (typeof NwAnalytics === 'undefined') return;
      NwAnalytics.track('search.result_click', {
        surface: 'mobile_web.search.results',
        source_app: 'providers',
        object_type: 'ProviderProfile',
        object_id: String(provider.id || ''),
        payload: {
          query: (_input && _input.value ? _input.value.trim() : ''),
          selected_category_id: _activeCat ? _safeInt(_activeCat) : null,
          featured: _featuredProviderIds.has(String(provider.id)),
        },
      });
    };
    card.addEventListener('click', event => {
      if (event.target.closest('.provider-search-actions a')) return;
      trackProfileClick();
      window.location.href = providerProfileHref;
    });
    card.addEventListener('keydown', event => {
      if (event.key !== 'Enter' && event.key !== ' ') return;
      if (event.target.closest('.provider-search-actions a')) return;
      event.preventDefault();
      trackProfileClick();
      window.location.href = providerProfileHref;
    });

    const media = UI.el('div', { className: 'provider-search-cover' });
    const mediaFrame = UI.el('div', { className: 'provider-search-cover-frame' });
    if (coverUrl) {
      mediaFrame.appendChild(UI.lazyImg(coverUrl, displayName));
    } else {
      const fallback = UI.el('div', { className: 'provider-search-cover-fallback' });
      fallback.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="3" y="4" width="18" height="16" rx="3"></rect><path d="M7 14l3-3 3 3 4-4 3 3"></path></svg>';
      mediaFrame.appendChild(fallback);
    }
    mediaFrame.appendChild(UI.el('div', { className: 'provider-search-cover-overlay' }));

    const mediaTags = UI.el('div', { className: 'provider-search-media-tags' });
    if (isFeatured) {
      mediaTags.appendChild(UI.el('span', {
        className: 'provider-search-featured',
        textContent: _copy('featured'),
      }));
    }
    if (Number.isFinite(distanceKm)) {
      mediaTags.appendChild(UI.el('span', {
        className: 'provider-search-distance-tag',
        textContent: _copy('kilometersShort', { distance: distanceKm.toFixed(1) }),
      }));
    }
    if (mediaTags.childNodes.length) {
      mediaFrame.appendChild(mediaTags);
    }
    media.appendChild(mediaFrame);

    const avatar = UI.el('div', { className: 'provider-search-avatar' });
    if (profileUrl) avatar.appendChild(UI.lazyImg(profileUrl, displayName));
    else avatar.appendChild(UI.el('span', { textContent: initial }));
    media.appendChild(avatar);

    card.appendChild(media);

    const body = UI.el('div', { className: 'provider-search-body' });
    const titleRow = UI.el('div', { className: 'provider-search-title-row' });
    const nameWrap = UI.el('div', { className: 'provider-search-name-wrap' });
    const nameLine = UI.el('div', { className: 'provider-search-name-line' });
    nameLine.style.display = 'flex';
    nameLine.style.alignItems = 'center';
    nameLine.style.gap = '6px';
    nameLine.style.flexWrap = 'wrap';
    const nameEl = UI.el('h2', { className: 'provider-search-name', textContent: displayName });
    nameLine.appendChild(nameEl);
    const inlineVerifiedBadges = UI.buildVerificationBadges({
      isVerifiedBlue: provider.is_verified_blue,
      isVerifiedGreen: provider.is_verified_green,
      iconSize: 14,
      gap: '4px',
    });
    if (inlineVerifiedBadges) nameLine.appendChild(inlineVerifiedBadges);
    nameWrap.appendChild(nameLine);

    const badgesRow = UI.el('div', { className: 'provider-search-badges' });

    const excellenceItems = UI.normalizeExcellenceBadges(provider.excellence_badges);
    if (excellenceItems.length) {
      excellenceItems.forEach((item) => {
        const label = (item && (item.name || item.code)) || _copy('excellenceBadge');
        const chip = UI.el('span', {
          className: 'provider-search-badge is-excellence',
          textContent: label,
        });
        if (item && item.description) {
          chip.title = item.description;
        }
        badgesRow.appendChild(chip);
      });
    }

    if (badgesRow.childNodes.length) {
      nameWrap.appendChild(badgesRow);
    }

    titleRow.appendChild(nameWrap);

    // Rating/trust pill removed from header — rating is shown in the stats row below.
    const titleAside = UI.el('div', { className: 'provider-search-title-aside' });
    if (titleAside.childNodes.length) {
      titleRow.appendChild(titleAside);
    }
    body.appendChild(titleRow);

    const meta = UI.el('div', { className: 'provider-search-meta' });
    if (serviceLabel) {
      const serviceRow = UI.el('div', { className: 'provider-search-meta-row' });
      serviceRow.appendChild(_tinyIcon('service', '#0f766e', 14));
      serviceRow.appendChild(UI.el('span', { textContent: serviceLabel }));
      meta.appendChild(serviceRow);
    }
    if (city) {
      const cityRow = UI.el('div', { className: 'provider-search-meta-row' });
      cityRow.appendChild(_tinyIcon('location', '#8A8A93', 14));
      cityRow.appendChild(UI.el('span', { textContent: city }));
      meta.appendChild(cityRow);
    }
    if (Number.isFinite(distanceKm)) {
      const distanceRow = UI.el('div', { className: 'provider-search-meta-row' });
      distanceRow.appendChild(_tinyIcon('near', '#3F51B5', 14));
      distanceRow.appendChild(UI.el('span', { textContent: _copy('distanceFromYou', { distance: distanceKm.toFixed(1) }) }));
      meta.appendChild(distanceRow);
    }

    if (meta.childNodes.length) body.appendChild(meta);

    if (snippet) {
      body.appendChild(UI.el('p', {
        className: 'provider-search-snippet',
        textContent: snippet,
      }));
    }

    const stats = UI.el('div', { className: 'provider-search-stats' });
    stats.appendChild(_statChip('star', ratingLabel, '#F9A825', ratingCount ? _copy('ratingsCount', { count: ratingCount }) : _copy('noRatings')));
    stats.appendChild(_statChip('done', String(completed), '#2E7D32', _copy('completedRequests')));
    if (followers > 0) {
      stats.appendChild(_statChip('people', String(followers), '#2563EB', _copy('followers')));
    }
    body.appendChild(stats);

    const actions = UI.el('div', { className: 'provider-search-actions' });
    const requestAction = UI.el('a', {
      className: 'provider-search-primary',
      href: directRequestHref,
      title: _copy('directRequestFrom', { name: displayName }),
      'aria-label': _copy('directRequestFrom', { name: displayName }),
    });
    requestAction.addEventListener('click', event => {
      event.stopPropagation();
      if (typeof NwAnalytics === 'undefined') return;
      NwAnalytics.track('search.direct_request_click', {
        surface: 'mobile_web.search.results',
        source_app: 'marketplace',
        object_type: 'ProviderProfile',
        object_id: String(provider.id || ''),
        payload: {
          query: (_input && _input.value ? _input.value.trim() : ''),
          selected_category_id: _activeCat ? _safeInt(_activeCat) : null,
        },
      });
    });
    const requestActionIcon = UI.el('span', { className: 'provider-search-primary-icon' });
    requestActionIcon.appendChild(_tinyIcon('request', '#ffffff', 17));
    requestAction.appendChild(requestActionIcon);
    const requestActionCopy = UI.el('span', { className: 'provider-search-primary-copy' });
    requestActionCopy.appendChild(UI.el('strong', { textContent: _copy('requestService') }));
    requestActionCopy.appendChild(UI.el('small', { textContent: _copy('startRequestWithProvider') }));
    requestAction.appendChild(requestActionCopy);
    const requestActionTail = UI.el('span', { className: 'provider-search-primary-tail' });
    requestActionTail.appendChild(_tinyIcon('launch', '#ffffff', 14));
    requestAction.appendChild(requestActionTail);
    actions.appendChild(requestAction);
    body.appendChild(actions);

    card.appendChild(body);

    return card;
  }

  function _statChip(kind, value, color, label) {
    const chip = UI.el('span', { className: 'provider-search-stat' });
    const iconWrap = UI.el('span', { className: 'provider-search-stat-icon' });
    if (kind === 'star') iconWrap.appendChild(UI.icon('star', 12, color));
    else if (kind === 'people') iconWrap.appendChild(UI.icon('people', 12, color));
    else iconWrap.appendChild(_tinyIcon('done', color));
    chip.appendChild(iconWrap);

    const textWrap = UI.el('span', { className: 'provider-search-stat-copy' });
    textWrap.appendChild(UI.el('strong', { textContent: value }));
    if (label) {
      textWrap.appendChild(UI.el('span', { textContent: label }));
    }
    chip.appendChild(textWrap);
    return chip;
  }

  function _tinyIcon(name, color, size) {
    const paths = {
      location: '<path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5S10.62 6.5 12 6.5s2.5 1.12 2.5 2.5S13.38 11.5 12 11.5z"/>',
      near: '<path d="M12 2l4 9-4 2-4-2 4-9zm0 12c3.31 0 6 2.69 6 6h-2a4 4 0 00-8 0H6c0-3.31 2.69-6 6-6z"/>',
      done: '<path d="M12 2a10 10 0 100 20 10 10 0 000-20zm-1.2 13.2L7.6 12l1.4-1.4 1.8 1.8 4.2-4.2 1.4 1.4-5.6 5.6z"/>',
      request: '<path d="M3.9 11.8 19.6 4.2c.6-.29 1.28.24 1.12.88l-3.76 14.06c-.14.52-.82.71-1.23.34l-4.39-3.96-2.6 2.48c-.4.38-1.06.15-1.14-.39l-.59-4.06-3.8-1.55c-.62-.25-.67-1.12-.07-1.41z"/><path d="M9.06 13.11 18.86 6.2" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/>',
      arrow: '<path d="M15 18l-6-6 6-6"/>',
      launch: '<path d="M7 17 17 7"/><path d="M9 7h8v8"/>',
      spark: '<path d="m12 2 1.7 4.2L18 8l-4.3 1.8L12 14l-1.7-4.2L6 8l4.3-1.8L12 2zm6 10 1 2.3 2.3 1-2.3 1-1 2.3-1-2.3-2.3-1 2.3-1 1-2.3zM6 15l1 2.5L9.5 18 7 19l-1 2.5L5 19l-2.5-1L5 17.5 6 15z"/>',
      profile: '<path d="M12 12a5 5 0 1 0-5-5 5 5 0 0 0 5 5zm0 2c-4.33 0-8 2.17-8 5v1h16v-1c0-2.83-3.67-5-8-5z"/>',
      service: '<path d="M5 6h14v2H5zm0 5h11v2H5zm0 5h8v2H5z"/>',
    };
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('width', String(size || 12));
    svg.setAttribute('height', String(size || 12));
    svg.setAttribute('viewBox', '0 0 24 24');
    const strokeIcons = new Set(['arrow', 'launch']);
    svg.setAttribute('fill', strokeIcons.has(name) ? 'none' : (color || 'currentColor'));
    if (strokeIcons.has(name)) {
      svg.setAttribute('stroke', color || 'currentColor');
      svg.setAttribute('stroke-width', '2');
      svg.setAttribute('stroke-linecap', 'round');
      svg.setAttribute('stroke-linejoin', 'round');
    }
    svg.innerHTML = paths[name] || paths.arrow;
    return svg;
  }

  function _tinyIconMarkup(name, color, size) {
    return _tinyIcon(name, color, size).outerHTML;
  }

  function _showEmpty(message) {
    if (_providersList) _providersList.textContent = '';
    if (_emptyState) {
      _emptyState.classList.remove('hidden');
      const text = _emptyState.querySelector('p');
      if (text) text.textContent = message || _copy('noResults');
    }
    if (_resultsCount) _resultsCount.textContent = _copy('resultsCount', { count: 0 });
  }

  function _completedCount(provider) {
    return _safeInt(
      provider.completed_requests ??
      provider.completed_orders_count ??
      provider.completed_requests_count
    );
  }

  function _safeNum(value) {
    const n = Number(value);
    return Number.isFinite(n) ? n : 0;
  }

  function _safeInt(value) {
    return Math.max(0, Math.floor(_safeNum(value)));
  }

  function _haversineKm(lat1, lng1, lat2, lng2) {
    const toRad = n => (n * Math.PI) / 180;
    const r = 6371;
    const dLat = toRad(lat2 - lat1);
    const dLng = toRad(lng2 - lng1);
    const a = Math.sin(dLat / 2) ** 2 +
      Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
    return r * (2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a)));
  }

  function _escapeHtml(value) {
    return String(value || '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  function _resolveProviderPhone(provider) {
    const raw = String(
      provider?.whatsapp || provider?.phone || provider?.phone_number || provider?.phoneNumber || ''
    ).trim();
    if (!raw) return '';
    return raw.replace(/\s+/g, '');
  }

  function _normalizeSaudiMobileLocal05(value) {
    const digits = String(value || '').replace(/\D+/g, '');
    if (digits.length === 10 && digits.startsWith('05')) return digits;
    if (digits.length === 9 && digits.startsWith('5')) return '0' + digits;
    if (digits.length === 12 && digits.startsWith('9665')) return '0' + digits.slice(3);
    if (digits.length === 14 && digits.startsWith('009665')) return '0' + digits.slice(5);
    return '';
  }

  function _toSaudiE164(value) {
    const local05 = _normalizeSaudiMobileLocal05(value);
    return local05 ? ('+966' + local05.slice(1)) : '';
  }

  function _resolveProviderTelHref(provider) {
    const phone = _toSaudiE164(_resolveProviderPhone(provider));
    return phone ? ('tel:' + phone) : '';
  }

  function _resolveProviderWhatsappHref(provider) {
    const text = _copy('greetingWhatsapp');
    const whatsappRaw = String(provider?.whatsapp_url || '').trim();
    if (whatsappRaw) {
      const normalized = whatsappRaw.startsWith('http') ? whatsappRaw : ('https://' + whatsappRaw);
      try {
        const url = new URL(normalized);
        url.searchParams.set('text', text);
        return url.toString();
      } catch (_) {
        // Fallback to phone normalization below.
      }
    }
    const e164 = _toSaudiE164(_resolveProviderPhone(provider)).replace('+', '');
    if (!e164) return '';
    const url = new URL('https://wa.me/' + e164);
    url.searchParams.set('text', text);
    return url.toString();
  }

  function _buildProviderMapPopupHtml(provider) {
    const providerId = String(provider?.id || '').trim();
    const name = _escapeHtml((provider?.display_name || _copy('providerFallback')).trim());
    const verifiedIcons = [
      provider?.is_verified_blue
        ? '<span style="display:inline-flex;align-items:center;justify-content:center;vertical-align:middle">' + UI.icon('verified_blue', 12, '#2196F3').outerHTML + '</span>'
        : '',
      provider?.is_verified_green
        ? '<span style="display:inline-flex;align-items:center;justify-content:center;vertical-align:middle">' + UI.icon('verified_green', 12, '#16A34A').outerHTML + '</span>'
        : '',
    ].filter(Boolean).join('<span style="display:inline-block;width:4px"></span>');
    const returnUrl = (() => {
      try {
        const url = new URL(window.location.href);
        if (url.searchParams.get('open_map') !== '1') {
          url.searchParams.set('open_map', '1');
        }
        return url.pathname + (url.search || '');
      } catch (_) {
        return '/providers-map/';
      }
    })();
    const profileUrl = providerId
      ? (
        '/provider/' + encodeURIComponent(providerId) + '/?from_map=1&return_to=' +
        encodeURIComponent(returnUrl)
      )
      : '#';
    const imageUrl = ApiClient.mediaUrl(provider?.profile_image || provider?.profileImage || '');
    const rating = _safeNum(provider?.rating_avg);
    const ratingLabel = rating > 0 ? rating.toFixed(1) : '-';
    const completed = _completedCount(provider);
    const telHref = _resolveProviderTelHref(provider);
    const waHref = _resolveProviderWhatsappHref(provider);
    const chatHref = providerId ? ('/chats/?start=' + encodeURIComponent(providerId)) : '/chats/';
    const directRequestHref = _buildDirectRequestHref(providerId);

    return [
      '<div class="search-map-provider-popup">',
      '<a class="search-map-provider-avatar-link" href="' + profileUrl + '">',
      imageUrl
        ? ('<img class="search-map-provider-avatar" src="' + _escapeHtml(imageUrl) + '" alt="' + name + '">')
        : '<span class="search-map-provider-avatar-fallback">👤</span>',
      '</a>',
      '<div class="search-map-provider-name" style="display:flex;align-items:center;gap:6px;flex-wrap:wrap"><span>' + name + '</span>' + verifiedIcons + '</div>',
      '<div class="search-map-provider-meta">',
      '<span>⭐ ' + ratingLabel + '</span>',
      '<span>•</span>',
      '<span>' + _escapeHtml(_copy('completedRequestsWithCount', { count: completed })) + '</span>',
      '</div>',
      '<div class="search-map-provider-actions">',
      providerId
        ? (
          '<a class="map-provider-action is-primary" href="' + directRequestHref + '">' +
          '<span class="map-provider-action-icon">' + _tinyIconMarkup('request', '#ffffff', 14) + '</span>' +
          '<span class="map-provider-action-copy"><strong>' + _escapeHtml(_copy('requestService')) + '</strong><small>' + _escapeHtml(_copy('startNow')) + '</small></span>' +
          '</a>'
        )
        : '',
      '<a class="map-provider-action" href="' + profileUrl + '">' + _escapeHtml(_copy('profile')) + '</a>',
      telHref
        ? ('<a class="map-provider-action" href="' + telHref + '">' + _escapeHtml(_copy('call')) + '</a>')
        : '<span class="map-provider-action is-disabled">' + _escapeHtml(_copy('call')) + '</span>',
      waHref
        ? ('<a class="map-provider-action" href="' + waHref + '" target="_blank" rel="noopener">' + _escapeHtml(_copy('whatsapp')) + '</a>')
        : '<span class="map-provider-action is-disabled">' + _escapeHtml(_copy('whatsapp')) + '</span>',
      '<a class="map-provider-action" href="' + chatHref + '">' + _escapeHtml(_copy('messages')) + '</a>',
      '</div>',
      '</div>',
    ].join('');
  }

  async function _loadSearchPromos() {
    try {
      const selectedCategoryName = _selectedCategoryName();
      const searchQuery = new URLSearchParams();
      searchQuery.set('service_type', 'search_results');
      searchQuery.set('limit', '10');
      searchQuery.set(
        'search_scope',
        selectedCategoryName ? 'default,main_results,category_match' : 'default,main_results'
      );
      if (selectedCategoryName) searchQuery.set('category', selectedCategoryName);
      const categoryBannerQuery = new URLSearchParams();
      if (selectedCategoryName) {
        categoryBannerQuery.set('ad_type', 'banner_category');
        categoryBannerQuery.set('limit', '1');
        categoryBannerQuery.set('category', selectedCategoryName);
        if (_activeCity) categoryBannerQuery.set('city', _activeCity);
      }

      const categoryPopupQuery = new URLSearchParams();
      if (selectedCategoryName) {
        categoryPopupQuery.set('ad_type', 'popup_category');
        categoryPopupQuery.set('limit', '1');
        categoryPopupQuery.set('category', selectedCategoryName);
        if (_activeCity) categoryPopupQuery.set('city', _activeCity);
      }

      const categoryBannerPromise = selectedCategoryName
        ? ApiClient.get('/api/promo/active/?' + categoryBannerQuery.toString())
        : Promise.resolve({ ok: false, data: [] });
      const categoryPopupPromise = selectedCategoryName
        ? ApiClient.get('/api/promo/active/?' + categoryPopupQuery.toString())
        : Promise.resolve({ ok: false, data: [] });

      const [categoryBannerRes, bannerRes, categoryPopupRes, searchRes] = await Promise.allSettled([
        categoryBannerPromise,
        ApiClient.get('/api/promo/active/?ad_type=banner_search&limit=5'),
        categoryPopupPromise,
        ApiClient.get('/api/promo/active/?' + searchQuery.toString()),
      ]);
      if (_promoBannerEl) {
        _promoBannerEl.textContent = '';
        _promoBannerEl.classList.add('hidden');
      }

      const pickFirstPromo = (result) => {
        if (result.status !== 'fulfilled' || !result.value.ok) return null;
        const rows = result.value.data?.results || result.value.data || [];
        if (!Array.isArray(rows) || !rows.length || typeof rows[0] !== 'object') return null;
        return rows[0];
      };

      const chosenBanner = pickFirstPromo(categoryBannerRes) || pickFirstPromo(bannerRes);

      // Banner
      if (chosenBanner && _promoBannerEl) {
          const promo = chosenBanner;
          const asset = (promo.assets || [])[0];
          const assetFile = asset && (asset.file || asset.file_url);
          if (assetFile) {
            const fileType = String((asset && asset.file_type) || 'image').toLowerCase();
            const mediaUrl = ApiClient.mediaUrl(assetFile);
            const media = fileType === 'video'
              ? document.createElement('video')
              : document.createElement('img');
            media.className = 'promo-banner-media';
            if (fileType === 'video') {
              media.src = mediaUrl;
              media.autoplay = true;
              media.loop = true;
              media.muted = true;
              media.playsInline = true;
            } else {
              media.src = mediaUrl;
              media.alt = promo.title || '';
            }

            const providerId = promo.target_provider_id ? String(promo.target_provider_id) : '';
            const providerHref = providerId
              ? ('/provider/' + encodeURIComponent(providerId) + '/')
              : '';
            if (promo.redirect_url || providerHref) {
              const link = document.createElement('a');
              link.href = promo.redirect_url || providerHref;
              link.className = 'promo-slide';
              if (promo.redirect_url) {
                link.target = '_blank';
                link.rel = 'noopener';
              }
              link.addEventListener('click', () => {
                if (typeof NwAnalytics === 'undefined') return;
                NwAnalytics.track('promo.banner_click', {
                  surface: 'mobile_web.search.banner',
                  source_app: 'promo',
                  object_type: 'ProviderProfile',
                  object_id: providerId,
                  payload: {
                    redirect_url: promo.redirect_url || '',
                    title: promo.title || '',
                    media_type: fileType,
                  },
                });
              });
              link.appendChild(media);
              _promoBannerEl.appendChild(link);
            } else {
              const wrap = document.createElement('div');
              wrap.className = 'promo-slide';
              wrap.appendChild(media);
              _promoBannerEl.appendChild(wrap);
            }
            _promoBannerEl.classList.remove('hidden');
            if (typeof NwAnalytics !== 'undefined') {
              NwAnalytics.trackOnce(
                'promo.banner_impression',
                {
                  surface: 'mobile_web.search.banner',
                  source_app: 'promo',
                  object_type: 'ProviderProfile',
                  object_id: providerId,
                  payload: {
                    title: promo.title || '',
                    media_type: fileType,
                  },
                },
                'promo.banner_impression:mobile_web.search:' + providerId
              );
            }
          }
      }

      const popupPromo = pickFirstPromo(categoryPopupRes);
      const popupKey = String(selectedCategoryName || '').trim().toLowerCase();
      if (popupPromo && popupKey && popupKey !== _lastCategoryPopupKey) {
        _lastCategoryPopupKey = popupKey;
        _showSearchPromoPopup(popupPromo);
      }
      // Search placements + featured providers
      const searchItems = searchRes.status === 'fulfilled' && searchRes.value.ok
        ? (searchRes.value.data?.results || searchRes.value.data || [])
        : [];
      _searchPromoPlacements = [];
      _featuredProviderIds = new Set();
      searchItems.forEach(item => {
        if (item && item.target_provider_id) {
          if (!_matchesSearchPromoScope(item) || !_matchesSearchPromoTargeting(item)) return;
          _featuredProviderIds.add(String(item.target_provider_id));
          _searchPromoPlacements.push(item);
        }
      });
      if (_providers.length) _renderProviders();
    } catch (_) { /* non-critical */ }
  }

  function _showSearchPromoPopup(promo) {
    if (!promo || typeof promo !== 'object') return;
    const asset = (promo.assets && promo.assets.length) ? promo.assets[0] : null;
    const assetFile = asset && (asset.file || asset.file_url);
    if (!assetFile) return;
    const mediaUrl = ApiClient.mediaUrl(assetFile);
    if (!mediaUrl) return;
    const fileType = String((asset && asset.file_type) || 'image').toLowerCase();
    const title = String(promo.title || '').trim();
    const redirectUrl = String(promo.redirect_url || '').trim();
    const providerId = promo.target_provider_id ? String(promo.target_provider_id) : '';
    const providerHref = providerId
      ? ('/provider/' + encodeURIComponent(providerId) + '/')
      : '';
    const href = redirectUrl || providerHref;

    const overlay = UI.el('div', { className: 'promo-popup-overlay' });
    const modal = UI.el('div', { className: 'promo-popup-modal' });
    const closeBtn = UI.el('button', { className: 'promo-popup-close', textContent: '✕', type: 'button' });
    Object.assign(overlay.style, {
      position: 'fixed',
      inset: '0',
      background: 'rgba(0,0,0,0.55)',
      zIndex: '9999',
      display: 'grid',
      placeItems: 'center',
      padding: '18px',
    });
    Object.assign(modal.style, {
      width: 'min(420px, 100%)',
      maxHeight: '90vh',
      overflow: 'hidden',
      borderRadius: '16px',
      background: '#fff',
      position: 'relative',
      boxShadow: '0 18px 36px rgba(0,0,0,.25)',
    });
    Object.assign(closeBtn.style, {
      position: 'absolute',
      top: '8px',
      left: '8px',
      width: '32px',
      height: '32px',
      borderRadius: '999px',
      border: 'none',
      background: 'rgba(0,0,0,.45)',
      color: '#fff',
      cursor: 'pointer',
      zIndex: '2',
    });

    const media = fileType === 'video'
      ? UI.el('video', {
          className: 'promo-popup-media promo-popup-video',
          src: mediaUrl,
          autoplay: true,
          loop: true,
          muted: true,
          playsinline: true,
        })
      : UI.el('img', { className: 'promo-popup-media promo-popup-img', alt: title || _copy('promoOffer') });
    if (fileType !== 'video') media.src = mediaUrl;

    const body = UI.el('div', { className: 'promo-popup-body' });
    Object.assign(body.style, { padding: '10px 12px 14px' });
    if (title) {
      body.appendChild(UI.el('p', { className: 'promo-popup-title', textContent: title }));
    }

    const content = href
      ? UI.el('a', { href, className: 'promo-popup-media-link' }, [media])
      : media;
    if (content && content.style) {
      Object.assign(content.style, {
        display: 'block',
        textDecoration: 'none',
        color: 'inherit',
      });
    }
    Object.assign(media.style, {
      width: '100%',
      display: 'block',
      maxHeight: '62vh',
      objectFit: 'cover',
      background: '#111',
    });
    if (redirectUrl) {
      content.target = '_blank';
      content.rel = 'noopener';
    }

    const close = () => overlay.remove();
    closeBtn.addEventListener('click', close);
    overlay.addEventListener('click', (event) => {
      if (event.target === overlay) close();
    });

    modal.appendChild(closeBtn);
    modal.appendChild(content);
    modal.appendChild(body);
    overlay.appendChild(modal);
    document.body.appendChild(overlay);
  }

  function _showToast(message) {
    const toast = UI.el('div', {
      className: 'search-toast',
      textContent: message,
    });
    document.body.appendChild(toast);
    requestAnimationFrame(() => toast.classList.add('show'));
    setTimeout(() => {
      toast.classList.remove('show');
      setTimeout(() => toast.remove(), 180);
    }, 2200);
  }

  function _handleLanguageChange() {
    _applyStaticCopy();
    _renderCategoryChips(_categories);
    _renderProviders();
    if (_mapModalOpen || _isProvidersMapPage) _renderMap();
  }

  function _applyStaticCopy() {
    if (window.NawafethI18n && typeof window.NawafethI18n.t === 'function') {
      document.title = window.NawafethI18n.t('siteTitle') + ' — ' + _copy('pageTitle');
    }
    _setAttr('search-back-btn', 'aria-label', _copy('back'));
    _setText('search-status-text', _copy('liveResults'));
    _setText('search-kicker', _copy('kicker'));
    _setText('search-page-title', _copy('heading'));
    _setText('search-page-subtitle', _copy('subtitle'));
    _setAttr('search-input', 'placeholder', _copy('searchPlaceholder'));
    _setAttr('search-clear', 'aria-label', _copy('clear'));
    _setText('search-signal-verified', _copy('signalVerified'));
    _setText('search-signal-request', _copy('signalRequest'));
    _setText('search-signal-map', _copy('signalMap'));
    _setText('search-results-eyebrow', _copy('totalResults'));
    _setText('search-map-btn-label', _copy('map'));
    _setText('search-sort-btn-label', _copy('sortResults'));
    _setText('search-open-categories-label', _copy('allCategories'));
    _setText('search-results-title', _copy('readyProviders'));
    _setText('search-results-note', _copy('resultsNote'));
    _setText('search-empty-text', _copy('noSearchResults'));
    _setText('category-picker-title', _copy('chooseCategoryTitle'));
    _setAttr('category-picker-close', 'aria-label', _copy('close'));
    _setAttr('category-picker-search', 'placeholder', _copy('searchCategoryPlaceholder'));
    _setText('category-picker-reset', _copy('chooseAll'));
    _setAttr('sort-sheet', 'aria-label', _copy('sortBy'));
    _setText('sort-sheet-title', _copy('sortBy'));
    _setText('sort-option-default', _copy('sortDefault'));
    _setText('sort-option-nearest', _copy('sortNearest'));
    _setText('sort-option-rating', _copy('sortRating'));
    _setText('sort-option-completed', _copy('sortCompleted'));
    _setText('sort-option-followers', _copy('sortFollowers'));
    _setAttr('search-map-modal', 'aria-label', _copy('providersMap'));
    _setText('search-map-title', _activeCity ? _copy('providersMapInCity', { city: _activeCity }) : _copy('providersMap'));
    _setAttr('search-map-close', 'aria-label', _copy('close'));
    if (_resultsCount) {
      const match = String(_resultsCount.textContent || '').match(/\d+/);
      const count = match ? Number(match[0]) : 0;
      _resultsCount.textContent = _copy('resultsCount', { count });
    }
    if (_categoryPickerCount) {
      _categoryPickerCount.textContent = _copy('categoriesCount', { count: _categories.length });
    }
    _syncCategorySummary();
  }

  function _setText(id, value) {
    const el = document.getElementById(id);
    if (el) el.textContent = value;
  }

  function _setAttr(id, name, value) {
    const el = document.getElementById(id);
    if (el) el.setAttribute(name, value);
  }

  function _currentLang() {
    try {
      if (window.NawafethI18n && typeof window.NawafethI18n.getLanguage === 'function') {
        return window.NawafethI18n.getLanguage() === 'en' ? 'en' : 'ar';
      }
      return (localStorage.getItem('nw_lang') || 'ar').toLowerCase() === 'en' ? 'en' : 'ar';
    } catch (_) {
      return 'ar';
    }
  }

  function _copy(key, replacements) {
    const bundle = COPY[_currentLang()] || COPY.ar;
    const value = Object.prototype.hasOwnProperty.call(bundle, key) ? bundle[key] : COPY.ar[key];
    return _replaceTokens(value, replacements);
  }

  function _replaceTokens(text, replacements) {
    if (typeof text !== 'string' || !replacements) return text;
    return text.replace(/\{(\w+)\}/g, (_, token) => (
      Object.prototype.hasOwnProperty.call(replacements, token) ? String(replacements[token]) : ''
    ));
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  return {};
})();
