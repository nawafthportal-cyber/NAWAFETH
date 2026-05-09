/* ===================================================================
   ordersPage.js — Orders / client requests page controller
   Loads the full client request list once, then applies local search,
   status filtering, and sorting so counters stay accurate.
   =================================================================== */
'use strict';

const OrdersPage = (() => {
  const COPY = {
    ar: {
      pageTitle: 'نوافــذ — طلباتي',
      pageEyebrow: 'متابعة احترافية',
      gateKicker: 'طلباتك الشخصية',
      gateTitle: 'سجّل دخولك لعرض طلباتك',
      gateDescription: 'يمكنك متابعة حالة الطلبات والتفاصيل بعد تسجيل الدخول.',
      gateNote: 'حسابك يفتح لك كل تفاصيل الطلب في مكان واحد.',
      gateButton: 'تسجيل الدخول',
      menu: 'القائمة',
      browseServices: 'استعرض الخدمات',
      refresh: 'تحديث',
      heroAria: 'ملخص الطلبات',
      listAria: 'قائمة الطلبات',
      title: 'طلباتي',
      subtitle: 'لوحة موحّدة لمتابعة الحالة والإجراءات',
      heroKicker: 'مركز المتابعة',
      heroTitle: 'ملخص الطلبات',
      heroSubtitle: 'ابدأ بالأهم ثم افتح التفاصيل عند الحاجة.',
      heroPill1: 'بحث لحظي',
      heroPill2: 'فرز واضح',
      heroPill3: 'تجربة متوازنة',
      activeLabel: 'طلبات نشطة',
      totalLabel: 'إجمالي الطلبات',
      providerAcceptedLabel: 'تم قبولها',
      awaitingClientLabel: 'تحتاج موافقتك',
      preExecutionLabel: 'قبل التنفيذ',
      preExecutionNote: 'تم قبول الطلب: {accepted} • بانتظار اعتماد العميل: {awaiting}',
      lastSyncNow: 'آخر تحديث الآن',
      lastSyncAt: 'آخر تحديث {time}',
      listTitle: 'قائمة الطلبات',
      resultsHelper: 'فرز مباشر وبحث سريع داخل جميع طلباتك.',
      resultsHelperAll: 'تعرض هذه القائمة جميع طلباتك مرتبة بوضوح حسب آخر تحديث.',
      resultsHelperSearch: '{count} نتيجة مطابقة لعبارة البحث الحالية.',
      resultsHelperStatus: '{count} طلب ضمن حالة {status}.',
      resultsHelperSearchStatus: '{count} نتيجة مطابقة ضمن حالة {status}.',
      sortLabel: 'الترتيب',
      sortNewest: 'الأحدث',
      sortOldest: 'الأقدم',
      sortStatus: 'حسب الحالة',
      sortAmount: 'الأعلى قيمة',
      sortDeadline: 'الأقرب موعدًا',
      searchPlaceholder: 'ابحث برقم الطلب أو العنوان أو التصنيف أو المدينة',
      clearSearch: 'مسح البحث',
      tabAll: 'الكل',
      tabNew: 'جديد',
      tabInProgress: 'تحت التنفيذ',
      tabCompleted: 'مكتمل',
      tabCancelled: 'ملغي',
      syncingMode: 'جار مزامنة نوع الحساب الحالي. حاول مرة أخرى خلال لحظة.',
      syncingSession: 'يتم تحديث الجلسة الآن. أعد المحاولة بعد لحظة.',
      loadFailed: 'تعذر تحميل الطلبات حاليًا',
      empty: 'لا توجد طلبات',
      emptySearch: 'لا توجد نتائج مطابقة لبحثك',
      emptyStatus: 'لا توجد طلبات في هذه الحالة',
      emptyHintDefault: 'ابدأ بطلب خدمة جديدة أو استعرض الخدمات لاكتشاف خيارات تناسبك.',
      emptyHintSearch: 'جرّب تقليل كلمات البحث أو امسحها لعرض مزيد من الطلبات.',
      emptyHintStatus: 'بدّل الحالة أو اعرض كل الطلبات للوصول إلى عناصر أخرى.',
      emptyCta: 'استعرض الخدمات',
      statusNew: 'جديد',
      statusSubmitted: 'مرسل',
      statusWaiting: 'بانتظار',
      statusAcceptedProvider: 'تم قبول الطلب',
      statusAwaitingClient: 'بانتظار اعتماد العميل للتفاصيل',
      statusInProgress: 'قيد التنفيذ',
      statusCompleted: 'مكتمل',
      statusCancelled: 'ملغى',
      statusRejected: 'مرفوض',
      statusExpired: 'منتهي',
      statusUnknown: 'غير محدد',
      providerFallback: 'مقدم خدمة',
      providerPending: 'بانتظار اختيار مقدم الخدمة',
      requestTypeUrgent: 'عاجل',
      requestTypeCompetitive: 'تنافسي',
      requestTypeNormal: 'عادي',
      requestTypeDefault: 'طلب',
      requestFallback: 'طلب #{id}',
      categoryFallback: 'بدون تصنيف',
      cityFallback: 'غير محددة',
      amountFallback: 'غير محددة',
      deadlineFallback: 'لا يوجد موعد محدد',
      cityLabel: 'المدينة',
      categoryLabel: 'التصنيف',
      amountLabel: 'القيمة',
      deadlineLabel: 'الموعد',
      providerLabel: 'مقدم الخدمة',
      openDetails: 'عرض التفاصيل',
      requestNumberPrefix: 'طلب',
      currency: 'ر.س',
      attentionRequired: 'تحتاج اعتمادك',
      nextAction: 'الإجراء التالي',
      continueTracking: 'متابعة الطلب',
      stepCreated: 'إنشاء',
      stepAccepted: 'قبول',
      stepProgress: 'تنفيذ',
      stepCompleted: 'إغلاق',
      stepCancelled: 'ملغي',
      actionAwaitingClient: 'راجع تفاصيل التنفيذ واعتمدها أو ارفضها.',
      actionAccepted: 'مزود الخدمة قبل الطلب وينتظر اعتماد تفاصيل التنفيذ.',
      actionInProgress: 'تابع تقدم التنفيذ والدفعات والمرفقات.',
      actionCompleted: 'الخدمة مكتملة ويمكنك مراجعة التقييم والتفاصيل.',
      actionCancelled: 'الطلب متوقف ويمكنك مراجعة سبب الإلغاء.',
      actionDefault: 'افتح التفاصيل لمتابعة الطلب.',
    },
    en: {
      pageTitle: 'Nawafeth — My Orders',
      pageEyebrow: 'Premium tracking',
      gateKicker: 'Your personal orders',
      gateTitle: 'Sign in to view your orders',
      gateDescription: 'You can track order status and details after signing in.',
      gateNote: 'Your account opens all order details in one place.',
      gateButton: 'Sign in',
      menu: 'Menu',
      browseServices: 'Browse services',
      refresh: 'Refresh',
      heroAria: 'Orders summary',
      listAria: 'Orders list',
      title: 'My Orders',
      subtitle: 'A unified board to track statuses and actions',
      heroKicker: 'Tracking center',
      heroTitle: 'Orders summary',
      heroSubtitle: 'Start with what matters most, then open details when needed.',
      heroPill1: 'Live search',
      heroPill2: 'Clear sorting',
      heroPill3: 'Balanced experience',
      activeLabel: 'Active orders',
      totalLabel: 'Total orders',
      providerAcceptedLabel: 'Accepted',
      awaitingClientLabel: 'Needs your approval',
      preExecutionLabel: 'Before execution',
      preExecutionNote: 'Accepted by provider: {accepted} • Awaiting your approval: {awaiting}',
      lastSyncNow: 'Updated just now',
      lastSyncAt: 'Updated {time}',
      listTitle: 'Orders list',
      resultsHelper: 'Fast search and direct sorting across all your orders.',
      resultsHelperAll: 'This list shows all your orders in a clean, recent-first view.',
      resultsHelperSearch: '{count} result(s) match your search.',
      resultsHelperStatus: '{count} order(s) in status {status}.',
      resultsHelperSearchStatus: '{count} matching result(s) in status {status}.',
      sortLabel: 'Sort',
      sortNewest: 'Newest',
      sortOldest: 'Oldest',
      sortStatus: 'By status',
      sortAmount: 'Highest value',
      sortDeadline: 'Nearest deadline',
      searchPlaceholder: 'Search by request number, title, category, or city',
      clearSearch: 'Clear search',
      tabAll: 'All',
      tabNew: 'New',
      tabInProgress: 'In progress',
      tabCompleted: 'Completed',
      tabCancelled: 'Cancelled',
      syncingMode: 'The current account mode is being synced. Please try again shortly.',
      syncingSession: 'The session is being refreshed. Please try again in a moment.',
      loadFailed: 'Unable to load orders right now',
      empty: 'No orders found',
      emptySearch: 'No results match your search',
      emptyStatus: 'No orders in this status',
      emptyHintDefault: 'Start a new request or browse services to discover suitable options.',
      emptyHintSearch: 'Try fewer search terms or clear the field to show more orders.',
      emptyHintStatus: 'Switch status or view all orders to find more items.',
      emptyCta: 'Browse services',
      statusNew: 'New',
      statusSubmitted: 'Submitted',
      statusWaiting: 'Waiting',
      statusAcceptedProvider: 'Accepted by provider',
      statusAwaitingClient: 'Awaiting client approval',
      statusInProgress: 'In progress',
      statusCompleted: 'Completed',
      statusCancelled: 'Cancelled',
      statusRejected: 'Rejected',
      statusExpired: 'Expired',
      statusUnknown: 'Unspecified',
      providerFallback: 'Provider',
      providerPending: 'Waiting for provider assignment',
      requestTypeUrgent: 'Urgent',
      requestTypeCompetitive: 'Competitive',
      requestTypeNormal: 'Standard',
      requestTypeDefault: 'Request',
      requestFallback: 'Request #{id}',
      categoryFallback: 'No category',
      cityFallback: 'Unspecified',
      amountFallback: 'Unspecified',
      deadlineFallback: 'No deadline set',
      cityLabel: 'City',
      categoryLabel: 'Category',
      amountLabel: 'Amount',
      deadlineLabel: 'Deadline',
      providerLabel: 'Provider',
      openDetails: 'Open details',
      requestNumberPrefix: 'Request',
      currency: 'SAR',
      attentionRequired: 'Needs approval',
      nextAction: 'Next action',
      continueTracking: 'Track order',
      stepCreated: 'Created',
      stepAccepted: 'Accepted',
      stepProgress: 'Execution',
      stepCompleted: 'Closed',
      stepCancelled: 'Cancelled',
      actionAwaitingClient: 'Review execution details, then approve or reject.',
      actionAccepted: 'The provider accepted and is waiting on execution details.',
      actionInProgress: 'Track execution progress, payments, and attachments.',
      actionCompleted: 'The service is complete. Review rating and details.',
      actionCancelled: 'The order is stopped. Review the cancellation reason.',
      actionDefault: 'Open details to continue tracking.',
    },
  };

  const PAGE_LIMIT = 100;
  const SEARCH_DEBOUNCE_MS = 160;
  const STATUS_SORT_WEIGHT = {
    new: 0,
    in_progress: 1,
    completed: 2,
    cancelled: 3,
  };

  let _all = [];
  let _activeTab = 'all';
  let _searchQuery = '';
  let _sortValue = 'newest';
  let _emptyMessage = '';
  let _lastUpdatedAt = null;
  let _searchTimer = null;

  function init() {
    _emptyMessage = _copy('empty');
    _applyStaticCopy();

    if (!Auth.isLoggedIn()) {
      _showGate();
      return;
    }
    _hideGate();

    if (_activeMode() === 'provider') {
      window.location.href = '/provider-orders/';
      return;
    }

    _bindEvents();
    window.addEventListener('nawafeth:languagechange', _handleLanguageChange);
    _fetchOrders();
  }

  function _bindEvents() {
    const tabs = document.getElementById('status-tabs');
    const searchInput = document.getElementById('orders-search');
    const clearSearchBtn = document.getElementById('orders-search-clear');
    const sortSelect = document.getElementById('orders-sort');
    const refreshBtn = document.getElementById('orders-refresh-btn');

    if (tabs) {
      tabs.addEventListener('click', (event) => {
        const btn = event.target.closest('.tab-btn');
        if (!btn) return;
        document.querySelectorAll('#status-tabs .tab-btn').forEach((node) => node.classList.remove('active'));
        btn.classList.add('active');
        _activeTab = btn.dataset.status || 'all';
        _renderOrders();
      });
    }

    if (searchInput) {
      searchInput.addEventListener('input', (event) => {
        _searchQuery = String(event.target.value || '').trim();
        _toggleSearchClear();
        if (_searchTimer) window.clearTimeout(_searchTimer);
        _searchTimer = window.setTimeout(() => {
          _renderOrders();
        }, SEARCH_DEBOUNCE_MS);
      });
      searchInput.addEventListener('keydown', (event) => {
        if (event.key !== 'Enter') return;
        event.preventDefault();
        if (_searchTimer) window.clearTimeout(_searchTimer);
        _searchQuery = String(searchInput.value || '').trim();
        _toggleSearchClear();
        _renderOrders();
      });
    }

    if (clearSearchBtn && searchInput) {
      clearSearchBtn.addEventListener('click', () => {
        searchInput.value = '';
        _searchQuery = '';
        _toggleSearchClear();
        _renderOrders();
      });
    }

    if (sortSelect) {
      sortSelect.addEventListener('change', (event) => {
        _sortValue = String(event.target.value || 'newest');
        _renderOrders();
      });
    }

    if (refreshBtn) {
      refreshBtn.addEventListener('click', () => {
        _fetchOrders();
      });
    }
  }

  function _showGate() {
    const gate = document.getElementById('auth-gate');
    const content = document.getElementById('orders-content');
    if (gate) gate.classList.remove('hidden');
    if (content) content.classList.add('hidden');
  }

  function _hideGate() {
    const gate = document.getElementById('auth-gate');
    const content = document.getElementById('orders-content');
    if (gate) gate.classList.add('hidden');
    if (content) content.classList.remove('hidden');
  }

  function _activeMode() {
    try {
      const mode = (sessionStorage.getItem('nw_account_mode') || '').trim().toLowerCase();
      if (mode === 'provider' || mode === 'client') return mode;
    } catch (_) {}
    const role = (Auth.getRoleState() || '').trim().toLowerCase();
    return role === 'provider' ? 'provider' : 'client';
  }

  function _setLoadingState(loading) {
    const container = document.getElementById('orders-list');
    const emptyEl = document.getElementById('orders-empty');
    if (!container) return;

    if (loading) {
      container.innerHTML = [
        '<div class="orders-skeleton-card shimmer"></div>',
        '<div class="orders-skeleton-card shimmer"></div>',
        '<div class="orders-skeleton-card shimmer"></div>',
      ].join('');
      if (emptyEl) emptyEl.classList.add('hidden');
      return;
    }
  }

  async function _fetchOrders() {
    _setLoadingState(true);

    const profileState = await Auth.resolveProfile(false, _activeMode());
    if (!profileState.ok) {
      _setLoadingState(false);
      if (!Auth.isLoggedIn()) {
        _showGate();
        return;
      }
      _all = [];
      _lastUpdatedAt = null;
      _emptyMessage = _copy('syncingMode');
      _renderOrders();
      return;
    }

    const res = await _loadAllOrders();
    _setLoadingState(false);

    if (res.ok) {
      _all = _dedupeById(res.data || []);
      _lastUpdatedAt = new Date();
      _emptyMessage = _copy('empty');
      _renderOrders();
      return;
    }

    if (res.status === 401) {
      const recovered = await Auth.resolveProfile(true, _activeMode());
      if (!recovered.ok && !Auth.isLoggedIn()) {
        _showGate();
        return;
      }
      _all = [];
      _lastUpdatedAt = null;
      _emptyMessage = _copy('syncingSession');
      _renderOrders();
      return;
    }

    _all = [];
    _lastUpdatedAt = null;
    _emptyMessage = _copy('loadFailed');
    _renderOrders();
  }

  async function _loadAllOrders() {
    let items = [];
    let offset = 0;
    let guard = 0;

    while (guard < 30) {
      const path = '/api/marketplace/client/requests/?limit=' + PAGE_LIMIT + '&offset=' + offset;
      const res = await ApiClient.request(path, { timeout: 12000 });
      if (!res.ok) return res;

      const batch = Array.isArray(res.data) ? res.data : (res.data && res.data.results) || [];
      items = items.concat(batch);

      const hasMoreHeader = res.headers && typeof res.headers.get === 'function'
        ? String(res.headers.get('X-Has-More') || '')
        : '';
      const hasMore = hasMoreHeader
        ? hasMoreHeader === '1'
        : batch.length === PAGE_LIMIT;

      if (!batch.length || !hasMore) {
        return { ok: true, status: res.status, data: items };
      }

      offset += batch.length;
      guard += 1;
    }

    return { ok: true, status: 200, data: items };
  }

  function _dedupeById(items) {
    const seen = new Set();
    return items.filter((item) => {
      const key = String(item && (item.id || item.request_id || ''));
      if (!key || seen.has(key)) return false;
      seen.add(key);
      return true;
    });
  }

  function _renderOrders() {
    const container = document.getElementById('orders-list');
    const emptyEl = document.getElementById('orders-empty');
    const emptyText = document.getElementById('orders-empty-text');
    const emptyHint = document.getElementById('orders-empty-hint');
    if (!container || !emptyEl) return;

    const searchedList = _filterBySearch(_all);
    const visibleList = _sortOrders(_filterByStatus(searchedList));
    const heroCounts = _buildStatusCounts(_all);
    const filterCounts = _buildStatusCounts(searchedList);

    _renderCounters(heroCounts, filterCounts, visibleList.length);
    _renderHelperText(visibleList.length, searchedList.length);
    _renderLastSync();

    container.innerHTML = '';

    if (!visibleList.length) {
      if (emptyText) {
        if (_searchQuery) emptyText.textContent = _copy('emptySearch');
        else if (_activeTab !== 'all') emptyText.textContent = _copy('emptyStatus');
        else emptyText.textContent = _emptyMessage;
      }
      if (emptyHint) {
        if (_searchQuery) emptyHint.textContent = _copy('emptyHintSearch');
        else if (_activeTab !== 'all') emptyHint.textContent = _copy('emptyHintStatus');
        else emptyHint.textContent = _copy('emptyHintDefault');
      }
      emptyEl.classList.remove('hidden');
      return;
    }

    emptyEl.classList.add('hidden');
    const frag = document.createDocumentFragment();
    visibleList.forEach((order) => frag.appendChild(_buildCard(order)));
    container.appendChild(frag);
  }

  function _filterBySearch(items) {
    if (!_searchQuery) return [...items];
    const q = _normalizeText(_searchQuery);
    return items.filter((item) => {
      const haystack = [
        item && item.id ? (_copy('requestNumberPrefix') + ' ' + item.id) : '',
        item && item.title,
        item && item.description,
        item && item.subcategory_name,
        item && item.subcategory_name_en,
        item && item.category_name,
        item && item.category_name_en,
        item && item.city_display,
        item && item.city_display_en,
        item && item.client_city_display,
        item && item.client_city_display_en,
        item && item.provider_name,
        item && item.status_label,
      ].map(_normalizeText).join(' ');
      return haystack.includes(q);
    });
  }

  function _filterByStatus(items) {
    if (!_activeTab || _activeTab === 'all') return [...items];
    return items.filter((item) => _statusGroup(item) === _activeTab);
  }

  function _sortOrders(items) {
    const list = [...items];
    list.sort((a, b) => {
      if (_sortValue === 'oldest') return _asTime(a) - _asTime(b);
      if (_sortValue === 'status') {
        const byStatus = (STATUS_SORT_WEIGHT[_statusGroup(a)] || 99) - (STATUS_SORT_WEIGHT[_statusGroup(b)] || 99);
        if (byStatus !== 0) return byStatus;
        return _asTime(b) - _asTime(a);
      }
      if (_sortValue === 'amount_desc') {
        const byAmount = _extractAmount(b) - _extractAmount(a);
        if (byAmount !== 0) return byAmount;
        return _asTime(b) - _asTime(a);
      }
      if (_sortValue === 'deadline') {
        const byDeadline = _deadlineTime(a) - _deadlineTime(b);
        if (byDeadline !== 0) return byDeadline;
        return _asTime(b) - _asTime(a);
      }
      return _asTime(b) - _asTime(a);
    });
    return list;
  }

  function _statusGroup(orderOrStatus) {
    const explicit = String(
      orderOrStatus && typeof orderOrStatus === 'object'
        ? (orderOrStatus.status_group || orderOrStatus.status || '')
        : (orderOrStatus || '')
    ).toLowerCase();

    if (['new', 'in_progress', 'completed', 'cancelled'].includes(explicit)) return explicit;

    const map = {
      pending: 'new',
      submitted: 'new',
      waiting: 'new',
      new: 'new',
      provider_accepted: 'new',
      awaiting_client: 'new',
      accepted: 'in_progress',
      in_progress: 'in_progress',
      ongoing: 'in_progress',
      completed: 'completed',
      done: 'completed',
      cancelled: 'cancelled',
      rejected: 'cancelled',
      expired: 'cancelled',
    };
    return map[explicit] || 'in_progress';
  }

  function _statusLabel(statusOrOrder) {
    const raw = String(
      statusOrOrder && typeof statusOrOrder === 'object'
        ? (statusOrOrder.status_label || statusOrOrder.status_group || statusOrOrder.status || '')
        : (statusOrOrder || '')
    ).toLowerCase();

    const labels = {
      pending: _copy('statusNew'),
      submitted: _copy('statusSubmitted'),
      waiting: _copy('statusWaiting'),
      new: _copy('statusNew'),
      provider_accepted: _copy('statusAcceptedProvider'),
      awaiting_client: _copy('statusAwaitingClient'),
      accepted: _copy('statusInProgress'),
      in_progress: _copy('statusInProgress'),
      ongoing: _copy('statusInProgress'),
      completed: _copy('statusCompleted'),
      done: _copy('statusCompleted'),
      cancelled: _copy('statusCancelled'),
      rejected: _copy('statusRejected'),
      expired: _copy('statusExpired'),
    };
    return labels[raw] || (statusOrOrder && statusOrOrder.status_label) || _copy('statusUnknown');
  }

  function _statusColor(orderOrStatus) {
    const group = _statusGroup(orderOrStatus);
    switch (group) {
      case 'new':
        return '#D38B28';
      case 'in_progress':
        return '#0F8EA2';
      case 'completed':
        return '#1F8D5A';
      case 'cancelled':
        return '#D24646';
      default:
        return '#7D6AAB';
    }
  }

  function _buildCard(order) {
    const orderId = order.id || order.request_id;
    const statusGroup = _statusGroup(order);
    const stage = _workflowStage(order);
    const needsAttention = stage === 'awaiting_client';
    const card = UI.el(orderId ? 'a' : 'article', {
      className: 'order-card order-card-' + statusGroup + (needsAttention ? ' order-card-attention' : ''),
    });
    if (orderId && card.tagName === 'A') {
      card.setAttribute('href', '/orders/' + orderId + '/');
    }
    card.style.setProperty('--order-accent', _statusColor(order));
    card.setAttribute('aria-label', _buildCardAriaLabel(order));

    const header = UI.el('div', { className: 'order-header' });
    const headerCopy = UI.el('div', { className: 'order-header-copy' });
    headerCopy.appendChild(UI.el('span', {
      className: 'order-date',
      textContent: _formatDateTime(order.created_at || order.created),
    }));
    if (needsAttention) {
      headerCopy.appendChild(UI.el('span', {
        className: 'order-attention-pill',
        textContent: _copy('attentionRequired'),
      }));
    }
    header.appendChild(headerCopy);

    const badge = UI.el('span', {
      className: 'status-badge',
      textContent: _statusLabel(order),
    });
    const statusColor = _statusColor(order);
    badge.style.backgroundColor = statusColor + '1A';
    badge.style.color = statusColor;
    badge.style.borderColor = statusColor + '55';
    header.appendChild(badge);
    card.appendChild(header);

    const chips = UI.el('div', { className: 'order-card-chips' });
    if (order.request_type && String(order.request_type).toLowerCase() !== 'normal') {
      chips.appendChild(UI.el('span', {
        className: 'order-type-chip order-type-' + String(order.request_type).toLowerCase(),
        textContent: _requestTypeLabel(order.request_type),
      }));
    }
    const categoryText = _categoryText(order);
    if (categoryText) {
      chips.appendChild(UI.el('span', {
        className: 'order-category-chip',
        textContent: categoryText,
      }));
    }
    if (orderId) {
      chips.appendChild(UI.el('span', {
        className: 'order-ref-chip',
        textContent: 'R' + String(orderId).padStart(6, '0'),
      }));
    }
    card.appendChild(chips);

    const title = order.title
      || order.service_name
      || order.description
      || _copy('requestFallback').replace('{id}', String(order.id || ''));
    card.appendChild(UI.el('div', { className: 'order-title', textContent: title }));

    const description = String(order.description || '').trim();
    if (description && description !== title) {
      card.appendChild(UI.el('div', {
        className: 'order-snippet',
        textContent: description.length > 140 ? (description.slice(0, 140) + '...') : description,
      }));
    }

    const metaGrid = UI.el('div', { className: 'order-meta-grid' });
    metaGrid.appendChild(_buildMetaItem(_copy('cityLabel'), _cityText(order)));
    metaGrid.appendChild(_buildMetaItem(_copy('categoryLabel'), categoryText || _copy('categoryFallback')));
    metaGrid.appendChild(_buildMetaItem(_copy('amountLabel'), _formatAmountText(order)));
    metaGrid.appendChild(_buildMetaItem(_copy('deadlineLabel'), _formatDeadlineText(order)));
    card.appendChild(metaGrid);

    card.appendChild(_buildProgressRail(order));

    const actionBox = UI.el('div', { className: 'order-next-action' });
    actionBox.appendChild(UI.el('span', { className: 'order-next-action-label', textContent: _copy('nextAction') }));
    actionBox.appendChild(UI.el('strong', { textContent: _nextActionText(order) }));
    card.appendChild(actionBox);

    const footer = UI.el('div', { className: 'order-card-footer' });
    const footerCopy = UI.el('div', { className: 'order-footer-copy' });
    footerCopy.appendChild(UI.el('div', {
      className: 'order-provider',
      textContent: _copy('providerLabel') + ': ' + _providerText(order),
    }));
    footerCopy.appendChild(UI.el('div', {
      className: 'order-timing',
      textContent: _statusLabel(order) + ' • ' + _formatDateShort(order.created_at || order.created),
    }));
    footer.appendChild(footerCopy);

    const amount = _formatAmountText(order);
    if (amount !== _copy('amountFallback')) {
      footerCopy.appendChild(UI.el('div', {
        className: 'order-price',
        textContent: amount,
      }));
    }

    footer.appendChild(UI.el('span', {
      className: 'order-card-cta',
      textContent: _copy('continueTracking'),
    }));

    card.appendChild(footer);
    return card;
  }

  function _buildProgressRail(order) {
    const group = _statusGroup(order);
    const stage = _workflowStage(order);
    const rail = UI.el('div', { className: 'order-progress-rail order-progress-' + group });
    const steps = group === 'cancelled'
      ? [
        { key: 'created', label: _copy('stepCreated'), active: true },
        { key: 'cancelled', label: _copy('stepCancelled'), active: true },
      ]
      : [
        { key: 'created', label: _copy('stepCreated'), active: true },
        { key: 'accepted', label: _copy('stepAccepted'), active: ['provider_accepted', 'awaiting_client', 'in_progress', 'completed'].includes(stage) || ['in_progress', 'completed'].includes(group) },
        { key: 'progress', label: _copy('stepProgress'), active: ['in_progress', 'completed'].includes(group) },
        { key: 'completed', label: _copy('stepCompleted'), active: group === 'completed' },
      ];

    steps.forEach((step) => {
      const item = UI.el('span', { className: 'order-progress-step' + (step.active ? ' is-active' : '') });
      item.appendChild(UI.el('span', { className: 'order-progress-dot' }));
      item.appendChild(UI.el('span', { className: 'order-progress-label', textContent: step.label }));
      rail.appendChild(item);
    });
    return rail;
  }

  function _nextActionText(order) {
    const stage = _workflowStage(order);
    const group = _statusGroup(order);
    if (stage === 'awaiting_client') return _copy('actionAwaitingClient');
    if (stage === 'provider_accepted') return _copy('actionAccepted');
    if (group === 'in_progress') return _copy('actionInProgress');
    if (group === 'completed') return _copy('actionCompleted');
    if (group === 'cancelled') return _copy('actionCancelled');
    return _copy('actionDefault');
  }

  function _buildMetaItem(label, value) {
    const item = UI.el('div', { className: 'order-meta-item' });
    item.appendChild(UI.el('span', { className: 'order-meta-label', textContent: label }));
    item.appendChild(UI.el('span', { className: 'order-meta-value', textContent: value }));
    return item;
  }

  function _buildCardAriaLabel(order) {
    const title = order.title || _copy('requestFallback').replace('{id}', String(order.id || ''));
    return title + ' - ' + _statusLabel(order);
  }

  function _requestTypeLabel(type) {
    const key = String(type || '').toLowerCase();
    if (key === 'urgent') return _copy('requestTypeUrgent');
    if (key === 'competitive') return _copy('requestTypeCompetitive');
    if (key === 'normal') return _copy('requestTypeNormal');
    return type || _copy('requestTypeDefault');
  }

  function _categoryText(order) {
    return order.subcategory_name || order.category_name || '';
  }

  function _cityText(order) {
    return order.city_display || order.client_city_display || order.city || _copy('cityFallback');
  }

  function _providerText(order) {
    return order.provider_name || order.provider_display_name || _copy('providerPending');
  }

  function _formatAmountText(order) {
    const amount = _extractAmount(order);
    if (!Number.isFinite(amount) || amount <= 0) return _copy('amountFallback');
    return amount.toLocaleString(_numberLocale()) + ' ' + _copy('currency');
  }

  function _extractAmount(order) {
    const candidates = [
      order.actual_service_amount,
      order.estimated_service_amount,
      order.received_amount,
      order.remaining_amount,
      order.price,
      order.total_price,
      order.amount,
    ];
    for (let idx = 0; idx < candidates.length; idx += 1) {
      const num = Number(candidates[idx]);
      if (Number.isFinite(num) && num > 0) return num;
    }
    return 0;
  }

  function _formatDeadlineText(order) {
    const source = order.expected_delivery_at || order.quote_deadline || order.delivered_at;
    return source ? _formatDateShort(source) : _copy('deadlineFallback');
  }

  function _deadlineTime(order) {
    const source = order.expected_delivery_at || order.quote_deadline || '';
    if (!source) return Number.MAX_SAFE_INTEGER;
    const date = new Date(source);
    return Number.isNaN(date.getTime()) ? Number.MAX_SAFE_INTEGER : date.getTime();
  }

  function _buildStatusCounts(items) {
    const counts = {
      all: items.length,
      new: 0,
      provider_accepted: 0,
      awaiting_client: 0,
      in_progress: 0,
      completed: 0,
      cancelled: 0,
    };

    items.forEach((item) => {
      const group = _statusGroup(item);
      if (Object.prototype.hasOwnProperty.call(counts, group)) counts[group] += 1;
      const stage = _workflowStage(item);
      if (stage === 'provider_accepted') counts.provider_accepted += 1;
      if (stage === 'awaiting_client') counts.awaiting_client += 1;
    });

    return counts;
  }

  function _renderCounters(heroCounts, filterCounts, visibleCount) {
    _setText('orders-total-count', String(heroCounts.all || 0));
    _setText('orders-active-count', String((heroCounts.new || 0) + (heroCounts.in_progress || 0)));
    _setText('orders-provider-accepted-count', String(heroCounts.provider_accepted || 0));
    _setText('orders-awaiting-client-count', String(heroCounts.awaiting_client || 0));
    _setText(
      'orders-pre-execution-note',
      _copy('preExecutionNote')
        .replace('{accepted}', String(heroCounts.provider_accepted || 0))
        .replace('{awaiting}', String(heroCounts.awaiting_client || 0))
    );
    _setText('orders-results-count', String(visibleCount || 0));

    document.querySelectorAll('#status-tabs .orders-tab-count').forEach((node) => {
      const key = String(node.dataset.countFor || 'all');
      node.textContent = String(filterCounts[key] || 0);
    });
  }

  function _renderHelperText(visibleCount, searchedCount) {
    const helper = document.getElementById('orders-results-helper');
    if (!helper) return;

    if (!_all.length && _emptyMessage !== _copy('empty') && !_searchQuery && _activeTab === 'all') {
      helper.textContent = _emptyMessage;
      return;
    }

    if (_searchQuery && _activeTab !== 'all') {
      helper.textContent = _copy('resultsHelperSearchStatus')
        .replace('{count}', String(visibleCount))
        .replace('{status}', _tabLabel(_activeTab));
      return;
    }

    if (_searchQuery) {
      helper.textContent = _copy('resultsHelperSearch').replace('{count}', String(searchedCount));
      return;
    }

    if (_activeTab !== 'all') {
      helper.textContent = _copy('resultsHelperStatus')
        .replace('{count}', String(visibleCount))
        .replace('{status}', _tabLabel(_activeTab));
      return;
    }

    helper.textContent = _copy('resultsHelperAll');
  }

  function _renderLastSync() {
    if (!_lastUpdatedAt) {
      _setText('orders-last-sync', _copy('lastSyncNow'));
      return;
    }
    _setText('orders-last-sync', _copy('lastSyncAt').replace('{time}', _formatTimeOnly(_lastUpdatedAt)));
  }

  function _tabLabel(key) {
    if (key === 'new') return _copy('tabNew');
    if (key === 'in_progress') return _copy('tabInProgress');
    if (key === 'completed') return _copy('tabCompleted');
    if (key === 'cancelled') return _copy('tabCancelled');
    return _copy('tabAll');
  }

  function _asTime(item) {
    const source = item && (item.created_at || item.created);
    if (!source) return 0;
    const date = new Date(source);
    return Number.isNaN(date.getTime()) ? 0 : date.getTime();
  }

  function _workflowStage(order) {
    return String((order && order.status) || '').toLowerCase();
  }

  function _formatDateTime(value) {
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return '';
    try {
      return new Intl.DateTimeFormat(_currentLang() === 'en' ? 'en-GB' : 'ar-SA', {
        hour: '2-digit',
        minute: '2-digit',
        day: '2-digit',
        month: 'short',
        year: 'numeric',
      }).format(date);
    } catch (_) {
      return _formatDateShort(date) + ' ' + _formatTimeOnly(date);
    }
  }

  function _formatDateShort(value) {
    const date = value instanceof Date ? value : new Date(value);
    if (Number.isNaN(date.getTime())) return '';
    try {
      return new Intl.DateTimeFormat(_currentLang() === 'en' ? 'en-GB' : 'ar-SA', {
        day: '2-digit',
        month: 'short',
        year: 'numeric',
      }).format(date);
    } catch (_) {
      const dd = String(date.getDate()).padStart(2, '0');
      const mm = String(date.getMonth() + 1).padStart(2, '0');
      const yyyy = date.getFullYear();
      return dd + '/' + mm + '/' + yyyy;
    }
  }

  function _formatTimeOnly(value) {
    const date = value instanceof Date ? value : new Date(value);
    if (Number.isNaN(date.getTime())) return '';
    try {
      return new Intl.DateTimeFormat(_currentLang() === 'en' ? 'en-GB' : 'ar-SA', {
        hour: '2-digit',
        minute: '2-digit',
      }).format(date);
    } catch (_) {
      const hh = String(date.getHours()).padStart(2, '0');
      const mm = String(date.getMinutes()).padStart(2, '0');
      return hh + ':' + mm;
    }
  }

  function _normalizeText(value) {
    return String(value || '')
      .toLowerCase()
      .replace(/[إأآا]/g, 'ا')
      .replace(/ى/g, 'ي')
      .replace(/ة/g, 'ه')
      .replace(/\s+/g, ' ')
      .trim();
  }

  function _toggleSearchClear() {
    const clearBtn = document.getElementById('orders-search-clear');
    if (!clearBtn) return;
    clearBtn.classList.toggle('hidden', !_searchQuery);
  }

  function _setText(id, value) {
    const node = document.getElementById(id);
    if (node) node.textContent = value;
  }

  function _currentLang() {
    if (window.NawafethI18n && typeof window.NawafethI18n.getLanguage === 'function') {
      return window.NawafethI18n.getLanguage() === 'en' ? 'en' : 'ar';
    }
    return document.documentElement.lang === 'en' ? 'en' : 'ar';
  }

  function _numberLocale() {
    return _currentLang() === 'en' ? 'en-US' : 'ar-SA';
  }

  function _copy(key) {
    const lang = _currentLang();
    return (COPY[lang] && COPY[lang][key]) || COPY.ar[key] || '';
  }

  function _applyStaticCopy() {
    document.title = _copy('pageTitle');

    const gate = document.getElementById('auth-gate');
    if (gate) {
      const kicker = gate.querySelector('.auth-gate-unified-kicker');
      const title = gate.querySelector('.auth-gate-unified-title');
      const desc = gate.querySelector('.auth-gate-unified-desc');
      const note = gate.querySelector('.auth-gate-unified-note');
      const cta = gate.querySelector('.auth-gate-unified-btn');
      if (kicker) kicker.textContent = _copy('gateKicker');
      if (title) title.textContent = _copy('gateTitle');
      if (desc) desc.textContent = _copy('gateDescription');
      if (note) note.textContent = _copy('gateNote');
      if (cta) cta.textContent = _copy('gateButton');
    }

    const menuBtn = document.getElementById('hero-menu-btn');
    const heroPanel = document.getElementById('orders-hero-panel');
    const mobileSheet = document.getElementById('orders-mobile-sheet');
    if (menuBtn) menuBtn.setAttribute('aria-label', _copy('menu'));
    if (heroPanel) heroPanel.setAttribute('aria-label', _copy('heroAria'));
    if (mobileSheet) mobileSheet.setAttribute('aria-label', _copy('listAria'));

    _setText('orders-page-eyebrow', _copy('pageEyebrow'));
    _setText('orders-page-title', _copy('title'));
    _setText('orders-page-subtitle', _copy('subtitle'));
    _setText('orders-hero-kicker', _copy('heroKicker'));
    _setText('orders-hero-title', _copy('heroTitle'));
    _setText('orders-hero-subtitle', _copy('heroSubtitle'));
    _setText('orders-hero-pill-1', _copy('heroPill1'));
    _setText('orders-hero-pill-2', _copy('heroPill2'));
    _setText('orders-hero-pill-3', _copy('heroPill3'));
    _setText('orders-active-label', _copy('activeLabel'));
    _setText('orders-total-label', _copy('totalLabel'));
    _setText('orders-provider-accepted-label', _copy('providerAcceptedLabel'));
    _setText('orders-awaiting-client-label', _copy('awaitingClientLabel'));
    _setText('orders-pre-execution-label', _copy('preExecutionLabel'));
    _setText('orders-list-title', _copy('listTitle'));
    _setText('orders-results-helper', _copy('resultsHelper'));
    _setText('orders-sort-label', _copy('sortLabel'));
    _setText('orders-sort-newest', _copy('sortNewest'));
    _setText('orders-sort-oldest', _copy('sortOldest'));
    _setText('orders-sort-status', _copy('sortStatus'));
    _setText('orders-sort-amount', _copy('sortAmount'));
    _setText('orders-sort-deadline', _copy('sortDeadline'));
    _setText('orders-tab-all', _copy('tabAll'));
    _setText('orders-tab-new', _copy('tabNew'));
    _setText('orders-tab-in-progress', _copy('tabInProgress'));
    _setText('orders-tab-completed', _copy('tabCompleted'));
    _setText('orders-tab-cancelled', _copy('tabCancelled'));
    _setText('orders-empty-hint', _copy('emptyHintDefault'));
    _setText('orders-empty-cta', _copy('emptyCta'));
    _setText('orders-browse-link', _copy('browseServices'));
    _setText('orders-refresh-btn', _copy('refresh'));
    _setText('orders-last-sync', _lastUpdatedAt ? _copy('lastSyncAt').replace('{time}', _formatTimeOnly(_lastUpdatedAt)) : _copy('lastSyncNow'));

    const searchInput = document.getElementById('orders-search');
    const clearBtn = document.getElementById('orders-search-clear');
    if (searchInput) searchInput.placeholder = _copy('searchPlaceholder');
    if (clearBtn) clearBtn.setAttribute('aria-label', _copy('clearSearch'));
  }

  function _handleLanguageChange() {
    _emptyMessage = _copy('empty');
    _applyStaticCopy();
    _renderOrders();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  return {};
})();
