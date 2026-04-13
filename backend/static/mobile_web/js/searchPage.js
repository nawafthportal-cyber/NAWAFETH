/* ===================================================================
   searchPage.js — Search providers (Flutter-like compact flow)
   GET /api/providers/list/?page_size=30&q=X&category_id=Y
   GET /api/providers/categories/
   =================================================================== */
'use strict';

const SearchPage = (() => {
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
  let _promoBannerEl = null;
  let _lastCategoryPopupKey = '';
  let _isProvidersMapPage = false;

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

    if (!_input || !_providersList) return;

    _promoBannerEl = document.getElementById('search-promo-banner');

    _bindHeader();
    _bindSearch();
    _bindCategoryFilter();
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
    if (!row) return;
    row.addEventListener('click', e => {
      const chip = e.target.closest('.filter-chip');
      if (!chip) return;
      row.querySelectorAll('.filter-chip').forEach(c => c.classList.remove('active'));
      chip.classList.add('active');
      _activeCat = chip.dataset.catId || '';
      _activeSubcategory = '';
      _loadSearchPromos();
      _fetchProviders();
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
    _sortSheetOpen = true;
    _syncSortOptions();
    _sortBackdrop.classList.remove('hidden');
    _sortSheet.classList.remove('hidden');
    requestAnimationFrame(() => {
      _sortBackdrop.classList.add('active');
      _sortSheet.classList.add('open');
    });
    document.body.style.overflow = 'hidden';
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
    document.body.style.overflow = '';
  }

  function _syncSortOptions() {
    if (!_sortSheet) return;
    _sortSheet.querySelectorAll('.sort-sheet-option').forEach(btn => {
      btn.classList.toggle('active', (btn.dataset.sortKey || '') === _selectedSort);
    });
  }

  async function _applySort(sortKey, requestLocationPermission) {
    _selectedSort = sortKey || 'default';
    _syncSortOptions();
    if (_selectedSort === 'nearest') {
      await _ensureDistanceMap(!!requestLocationPermission);
      if (!Object.keys(_distanceKmByProviderId).length) {
        _showToast('تعذر تحديد الموقع حالياً. سيتم عرض النتائج بدون مسافة.');
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
    row.innerHTML = '';
    _categoriesById = new Map();

    if (!_activeCat && _activeSubcategory) {
      const matchedCategory = cats.find(cat => Array.isArray(cat?.subcategories) && cat.subcategories.some(sub => String(sub?.id || '') === String(_activeSubcategory)));
      if (matchedCategory && matchedCategory.id) {
        _activeCat = String(matchedCategory.id);
      }
    }

    const allBtn = document.createElement('button');
    allBtn.className = 'filter-chip' + (!_activeCat ? ' active' : '');
    allBtn.dataset.catId = '';
    allBtn.textContent = 'الكل';
    row.appendChild(allBtn);

    cats.forEach(cat => {
      const btn = document.createElement('button');
      btn.className = 'filter-chip' + (String(_activeCat) === String(cat.id) ? ' active' : '');
      btn.dataset.catId = String(cat.id);
      btn.textContent = cat.name || '';
      row.appendChild(btn);
      _categoriesById.set(String(cat.id), {
        id: cat.id,
        name: String(cat.name || '').trim(),
      });
    });
  }

  async function _fetchProviders() {
    _renderLoading();

    let url = '/api/providers/list/?page_size=30';
    if (_query) url += '&q=' + encodeURIComponent(_query);
    if (_activeCat) url += '&category_id=' + encodeURIComponent(_activeCat);
    if (_activeSubcategory) url += '&subcategory_id=' + encodeURIComponent(_activeSubcategory);
    if (_activeCity) url += '&city=' + encodeURIComponent(_activeCity);
    if (_urgentOnly) url += '&accepts_urgent=1';

    const res = await ApiClient.get(url);
    if (!res.ok || !res.data) {
      _providers = [];
      _distanceKmByProviderId = {};
      _showEmpty(res.error || 'تعذر تحميل النتائج');
      return;
    }

    _providers = Array.isArray(res.data) ? res.data : (res.data.results || []);
    if (_activeCity) {
      _providers = _providers.filter(provider => {
        const providerCity = String(provider?.city || '').trim().toLowerCase();
        return providerCity && providerCity === _activeCity.trim().toLowerCase();
      });
    }
    if (_urgentOnly) {
      _providers = _providers.filter(provider => {
        const urgent = provider?.accepts_urgent ?? provider?.isUrgentEnabled ?? provider?.is_urgent_enabled;
        return !!urgent;
      });
    }
    await _ensureDistanceMap(_isProvidersMapPage || _selectedSort === 'nearest');
    _renderProviders();
    _syncResultsLink();
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
      '<div class="provider-list-card skeleton-provider-list">',
      '<div class="provider-list-media shimmer"></div>',
      '<div class="provider-list-body">',
      '<div class="shimmer" style="width:48%;height:11px;border-radius:4px"></div>',
      '<div class="shimmer" style="width:34%;height:9px;border-radius:4px;margin-top:6px"></div>',
      '<div class="shimmer" style="width:60%;height:9px;border-radius:4px;margin-top:8px"></div>',
      '</div>',
      '</div>',
    ].join('');
  }

  function _renderProviders() {
    if (!_providersList) return;
    let sorted = _applyPromoOrdering(_sortProviders(_providers));

    if (_resultsCount) _resultsCount.textContent = sorted.length + ' نتيجة';
    if (_mapBtn) _mapBtn.classList.toggle('hidden', sorted.length === 0);

    _providersList.textContent = '';
    if (!sorted.length) {
      _showEmpty('لا توجد نتائج');
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
    _mapModalOpen = true;
    _mapBackdrop.classList.remove('hidden');
    _mapModal.classList.remove('hidden');
    requestAnimationFrame(() => {
      _mapBackdrop.classList.add('active');
      _mapModal.classList.add('open');
      _renderMap();
    });
    document.body.style.overflow = 'hidden';
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
    document.body.style.overflow = '';
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
        ? ('خريطة المزوّدين - ' + _activeCity)
        : 'خريطة المزوّدين';
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
      currentMarker.bindPopup('موقعك الحالي');
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
      _showToast('تعذر تحديد موقعك الحالي.');
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

  function _buildProviderCard(provider) {
    const displayName = (provider.display_name || '').trim() || 'مزود خدمة';
    const city = UI.formatCityDisplay(provider.city_display || provider.city, provider.region || provider.region_name);
    const profileUrl = ApiClient.mediaUrl(provider.profile_image);
    const coverUrl = ApiClient.mediaUrl(provider.cover_image);
    const initial = displayName.charAt(0) || '؟';
    const distanceKm = _distanceKmByProviderId[provider.id];
    const rating = _safeNum(provider.rating_avg);
    const ratingLabel = rating > 0 ? rating.toFixed(1) : '-';
    const ratingCount = _safeInt(provider.rating_count);
    const completed = _completedCount(provider);

    const card = UI.el('a', {
      className: 'provider-list-card',
      href: '/provider/' + encodeURIComponent(String(provider.id || '')) + '/',
    });
    card.addEventListener('click', () => {
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
    });

    const media = UI.el('div', { className: 'provider-list-media' });
    if (coverUrl) media.appendChild(UI.lazyImg(coverUrl, displayName));
    else media.appendChild(UI.el('div', { className: 'provider-list-media-fallback' }));
    media.appendChild(UI.el('div', { className: 'provider-list-media-overlay' }));

    const avatarWrap = UI.el('div', { className: 'provider-list-avatar-wrap' });
    const avatar = UI.el('div', { className: 'provider-list-avatar' });
    if (profileUrl) avatar.appendChild(UI.lazyImg(profileUrl, displayName));
    else avatar.appendChild(UI.el('span', { textContent: initial }));
    avatarWrap.appendChild(avatar);
    media.appendChild(avatarWrap);

    const excellenceItems = UI.normalizeExcellenceBadges(provider.excellence_badges);
    if (excellenceItems.length) {
      const topBadge = UI.el('span', {
        className: 'provider-list-excellence-top',
        textContent: excellenceItems[0].name || excellenceItems[0].code || 'تميز',
      });
      media.appendChild(topBadge);
    }

    if (provider.is_verified_blue || provider.is_verified_green) {
      const badge = UI.el('span', { className: 'provider-list-verified' });
      badge.appendChild(
        UI.icon(
          provider.is_verified_blue ? 'verified_blue' : 'verified_green',
          14,
          provider.is_verified_blue ? '#2196F3' : '#4CAF50'
        )
      );
      media.appendChild(badge);
    }

    card.appendChild(media);

    const body = UI.el('div', { className: 'provider-list-body' });
    const nameWrap = UI.el('div', { className: 'provider-list-name-wrap' });
    const nameLine = UI.el('div', { className: 'provider-list-name-line' });
    nameLine.appendChild(UI.el('div', { className: 'provider-list-name', textContent: displayName }));
    nameWrap.appendChild(nameLine);

    const badgesRow = UI.el('div', { className: 'provider-list-badges' });
    if (provider.is_verified_blue || provider.is_verified_green) {
      const verifiedChip = UI.el('span', { className: 'provider-list-badge is-verified' });
      verifiedChip.appendChild(
        UI.icon(
          provider.is_verified_blue ? 'verified_blue' : 'verified_green',
          14,
          provider.is_verified_blue ? '#2196F3' : '#2E7D32'
        )
      );
      verifiedChip.appendChild(UI.el('span', { textContent: 'موثّق' }));
      badgesRow.appendChild(verifiedChip);
    }

    if (_featuredProviderIds.has(String(provider.id))) {
      badgesRow.appendChild(UI.el('span', { className: 'provider-list-badge is-featured', textContent: 'مميز' }));
    }

    if (excellenceItems.length) {
      badgesRow.appendChild(
        UI.el('span', {
          className: 'provider-list-badge is-excellence',
          textContent: excellenceItems[0].name || excellenceItems[0].code || 'شارة تميز',
        })
      );
    }

    if (badgesRow.childNodes.length) {
      nameWrap.appendChild(badgesRow);
    }

    body.appendChild(nameWrap);

    if (city) {
      const cityRow = UI.el('div', { className: 'provider-list-meta' });
      cityRow.appendChild(_tinyIcon('location', '#8A8A93'));
      cityRow.appendChild(UI.el('span', { textContent: city }));
      body.appendChild(cityRow);
    }

    if (Number.isFinite(distanceKm)) {
      const distanceRow = UI.el('div', { className: 'provider-list-distance' });
      distanceRow.appendChild(_tinyIcon('near', '#3F51B5'));
      distanceRow.appendChild(UI.el('span', { className: 'provider-list-distance-label', textContent: 'يبعد عنك' }));
      distanceRow.appendChild(UI.el('strong', { className: 'provider-list-distance-value', textContent: distanceKm.toFixed(1) + ' كم' }));
      body.appendChild(distanceRow);
    }

    const stats = UI.el('div', { className: 'provider-list-stats' });
    stats.appendChild(_statChip('star', ratingLabel, '#F9A825', ratingCount ? (ratingCount + ' تقييم') : 'بدون تقييمات'));
    stats.appendChild(_statChip('done', String(completed), '#2E7D32', 'طلبات مكتملة'));
    body.appendChild(stats);

    card.appendChild(body);

    const arrow = UI.el('div', { className: 'provider-list-arrow' });
    arrow.appendChild(_tinyIcon('arrow', '#B0B0B8'));
    card.appendChild(arrow);

    return card;
  }

  function _statChip(kind, value, color, label) {
    const chip = UI.el('span', { className: 'provider-list-stat-chip' });
    const iconWrap = UI.el('span', { className: 'provider-list-stat-icon' });
    if (kind === 'star') iconWrap.appendChild(UI.icon('star', 12, color));
    else if (kind === 'people') iconWrap.appendChild(UI.icon('people', 12, color));
    else iconWrap.appendChild(_tinyIcon('done', color));
    chip.appendChild(iconWrap);

    const textWrap = UI.el('span', { className: 'provider-list-stat-copy' });
    textWrap.appendChild(UI.el('strong', { className: 'provider-list-stat-value', textContent: value }));
    if (label) {
      textWrap.appendChild(UI.el('span', { className: 'provider-list-stat-label', textContent: label }));
    }
    chip.appendChild(textWrap);
    return chip;
  }

  function _tinyIcon(name, color) {
    const paths = {
      location: '<path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5S10.62 6.5 12 6.5s2.5 1.12 2.5 2.5S13.38 11.5 12 11.5z"/>',
      near: '<path d="M12 2l4 9-4 2-4-2 4-9zm0 12c3.31 0 6 2.69 6 6h-2a4 4 0 00-8 0H6c0-3.31 2.69-6 6-6z"/>',
      done: '<path d="M12 2a10 10 0 100 20 10 10 0 000-20zm-1.2 13.2L7.6 12l1.4-1.4 1.8 1.8 4.2-4.2 1.4 1.4-5.6 5.6z"/>',
      arrow: '<path d="M15 18l-6-6 6-6"/>',
    };
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('width', '12');
    svg.setAttribute('height', '12');
    svg.setAttribute('viewBox', '0 0 24 24');
    svg.setAttribute('fill', name === 'arrow' ? 'none' : (color || 'currentColor'));
    if (name === 'arrow') {
      svg.setAttribute('stroke', color || 'currentColor');
      svg.setAttribute('stroke-width', '2');
      svg.setAttribute('stroke-linecap', 'round');
      svg.setAttribute('stroke-linejoin', 'round');
    }
    svg.innerHTML = paths[name] || paths.arrow;
    return svg;
  }

  function _showEmpty(message) {
    if (_providersList) _providersList.textContent = '';
    if (_emptyState) {
      _emptyState.classList.remove('hidden');
      const text = _emptyState.querySelector('p');
      if (text) text.textContent = message || 'لا توجد نتائج';
    }
    if (_resultsCount) _resultsCount.textContent = '0 نتيجة';
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
    const text = 'السلام عليكم، أتواصل معك عبر منصة نوافذ بخصوص طلب خدمة.';
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
    const name = _escapeHtml((provider?.display_name || 'مزود خدمة').trim());
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

    return [
      '<div class="search-map-provider-popup">',
      '<a class="search-map-provider-avatar-link" href="' + profileUrl + '">',
      imageUrl
        ? ('<img class="search-map-provider-avatar" src="' + _escapeHtml(imageUrl) + '" alt="' + name + '">')
        : '<span class="search-map-provider-avatar-fallback">👤</span>',
      '</a>',
      '<div class="search-map-provider-name">' + name + '</div>',
      '<div class="search-map-provider-meta">',
      '<span>⭐ ' + ratingLabel + '</span>',
      '<span>•</span>',
      '<span>طلبات مكتملة: ' + completed + '</span>',
      '</div>',
      '<div class="search-map-provider-actions">',
      telHref
        ? ('<a class="map-provider-action" href="' + telHref + '">اتصال</a>')
        : '<span class="map-provider-action is-disabled">اتصال</span>',
      waHref
        ? ('<a class="map-provider-action" href="' + waHref + '" target="_blank" rel="noopener">واتس اب</a>')
        : '<span class="map-provider-action is-disabled">واتس اب</span>',
      '<a class="map-provider-action" href="' + chatHref + '">رسائل</a>',
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

      const [categoryBannerRes, bannerRes, categoryPopupRes, searchRes, featuredRes] = await Promise.allSettled([
        categoryBannerPromise,
        ApiClient.get('/api/promo/active/?ad_type=banner_search&limit=5'),
        categoryPopupPromise,
        ApiClient.get('/api/promo/active/?' + searchQuery.toString()),
        ApiClient.get('/api/promo/active/?ad_type=featured_top5&limit=10'),
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
      const featuredItems = featuredRes.status === 'fulfilled' && featuredRes.value.ok
        ? (featuredRes.value.data?.results || featuredRes.value.data || [])
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
      featuredItems.forEach(item => {
        if (item && item.target_provider_id) {
          if (!_matchesSearchPromoScope(item) || !_matchesSearchPromoTargeting(item)) return;
          _featuredProviderIds.add(String(item.target_provider_id));
          _searchPromoPlacements.push({
            ...item,
            search_position: item.search_position || 'top5',
          });
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
      : UI.el('img', { className: 'promo-popup-media promo-popup-img', alt: title || 'عرض ترويجي' });
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

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  return {};
})();
