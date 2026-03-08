/* ===================================================================
   searchPage.js — Search providers (Flutter-like compact flow)
   GET /api/providers/list/?page_size=30&q=X&category_id=Y
   GET /api/providers/categories/
   =================================================================== */
'use strict';

const SearchPage = (() => {
  let _providers = [];
  let _activeCat = '';
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

  function init() {
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

    if (!_input || !_providersList) return;

    _bindHeader();
    _bindSearch();
    _bindCategoryFilter();
    _bindSortSheet();
    _bindMapModal();

    const params = new URLSearchParams(window.location.search);
    const urlQ = (params.get('q') || '').trim();
    const urlCat = (params.get('category') || params.get('category_id') || '').trim();
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
    if (urlCity) _activeCity = urlCity;
    if (urlSort) _selectedSort = urlSort;

    _renderLoading();
    _fetchCategories();
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
    });
  }

  async function _fetchProviders() {
    _renderLoading();

    let url = '/api/providers/list/?page_size=30';
    if (_query) url += '&q=' + encodeURIComponent(_query);
    if (_activeCat) url += '&category_id=' + encodeURIComponent(_activeCat);
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
    await _ensureDistanceMap(false);
    _renderProviders();
  }

  async function _ensureDistanceMap(requestPermission) {
    if (!_providers.length) {
      _distanceKmByProviderId = {};
      return;
    }
    if (_selectedSort !== 'nearest' && _clientPosition === null) {
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
    const sorted = _sortProviders(_providers);

    if (_resultsCount) _resultsCount.textContent = sorted.length + ' نتيجة';
    if (_mapBtn) _mapBtn.classList.toggle('hidden', sorted.length === 0);

    _providersList.textContent = '';
    if (!sorted.length) {
      _showEmpty('لا توجد نتائج');
      return;
    }

    if (_emptyState) _emptyState.classList.add('hidden');

    const frag = document.createDocumentFragment();
    sorted.forEach(provider => frag.appendChild(_buildProviderCard(provider)));
    _providersList.appendChild(frag);

    if (_openMapAfterFirstRender) {
      _openMapAfterFirstRender = false;
      _openMapModal();
    }
  }

  function _openMapModal() {
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

    const sorted = _sortProviders(_providers).filter(provider => {
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
      L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
        attribution: '&copy; OpenStreetMap',
      }).addTo(_mapInstance);
    }

    if (_mapMarkersLayer) {
      _mapMarkersLayer.clearLayers();
    } else {
      _mapMarkersLayer = L.layerGroup().addTo(_mapInstance);
    }

    if (!sorted.length) {
      _mapInstance.setView([24.7136, 46.6753], 6);
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

  function _buildProviderCard(provider) {
    const displayName = (provider.display_name || '').trim() || 'مزود خدمة';
    const city = (provider.city || '').trim();
    const profileUrl = ApiClient.mediaUrl(provider.profile_image);
    const coverUrl = ApiClient.mediaUrl(provider.cover_image);
    const initial = displayName.charAt(0) || '؟';
    const distanceKm = _distanceKmByProviderId[provider.id];
    const rating = _safeNum(provider.rating_avg);
    const ratingLabel = rating > 0 ? rating.toFixed(1) : '-';
    const completed = _completedCount(provider);

    const card = UI.el('a', {
      className: 'provider-list-card',
      href: '/provider/' + encodeURIComponent(String(provider.id || '')) + '/',
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
    nameWrap.appendChild(UI.el('div', { className: 'provider-list-name', textContent: displayName }));
    const excellence = UI.buildExcellenceBadges(provider.excellence_badges, {
      className: 'excellence-badges compact provider-list-excellence',
      compact: true,
      iconSize: 10,
    });
    if (excellence) nameWrap.appendChild(excellence);
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
      distanceRow.appendChild(UI.el('span', { textContent: distanceKm.toFixed(1) + ' كم' }));
      body.appendChild(distanceRow);
    }

    const stats = UI.el('div', { className: 'provider-list-stats' });
    stats.appendChild(_statChip('star', ratingLabel, '#F9A825'));
    stats.appendChild(_statChip('people', String(_safeInt(provider.followers_count)), '#8A8A93'));
    stats.appendChild(_statChip('done', String(completed), '#2E7D32'));
    body.appendChild(stats);

    card.appendChild(body);

    const arrow = UI.el('div', { className: 'provider-list-arrow' });
    arrow.appendChild(_tinyIcon('arrow', '#B0B0B8'));
    card.appendChild(arrow);

    return card;
  }

  function _statChip(kind, value, color) {
    const chip = UI.el('span', { className: 'provider-list-stat-chip' });
    if (kind === 'star') chip.appendChild(UI.icon('star', 11, color));
    else if (kind === 'people') chip.appendChild(UI.icon('people', 11, color));
    else chip.appendChild(_tinyIcon('done', color));
    chip.appendChild(UI.el('span', { textContent: value }));
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
      provider?.phone || provider?.phone_number || provider?.phoneNumber || provider?.whatsapp || ''
    ).trim();
    if (!raw) return '';
    return raw.replace(/\s+/g, '');
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
        return '/search/?open_map=1';
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
    const phone = _resolveProviderPhone(provider);
    const telHref = phone ? ('tel:' + encodeURIComponent(phone)) : '';
    const waPhone = phone ? phone.replace(/^\+/, '') : '';
    const waText = encodeURIComponent('السلام عليكم، أتواصل معك عبر منصة نوافذ بخصوص طلب خدمة.');
    const waHref = waPhone ? ('https://wa.me/' + encodeURIComponent(waPhone) + '?text=' + waText) : '';
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
      '<a class="map-provider-action" href="' + chatHref + '">محادثة</a>',
      '</div>',
      '</div>',
    ].join('');
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
