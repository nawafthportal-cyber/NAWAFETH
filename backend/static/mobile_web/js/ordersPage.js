/* ===================================================================
   ordersPage.js — Orders / client requests page controller
   GET /api/marketplace/client/requests/?status_group=X
   =================================================================== */
'use strict';

const OrdersPage = (() => {
  const COPY = {
    ar: {
      pageTitle: 'نوافــذ — طلباتي',
      gateKicker: 'طلباتك الشخصية',
      gateTitle: 'سجّل دخولك لعرض طلباتك',
      gateDescription: 'يمكنك متابعة حالة الطلبات والتفاصيل بعد تسجيل الدخول.',
      gateNote: 'حسابك يفتح لك كل تفاصيل الطلب في مكان واحد.',
      gateButton: 'تسجيل الدخول',
      menu: 'القائمة',
      heroAria: 'ملخص الطلبات',
      listAria: 'قائمة الطلبات',
      title: 'طلباتي',
      subtitle: 'لوحة موحّدة لمتابعة الحالة والإجراءات',
      heroTitle: 'ملخص الطلبات',
      heroSubtitle: 'ابدأ بالأهم ثم افتح التفاصيل عند الحاجة.',
      activeLabel: 'طلبات نشطة',
      totalLabel: 'إجمالي الطلبات',
      preExecutionLabel: 'قبل التنفيذ',
      preExecutionNote: 'تم قبول الطلب: {accepted} • بانتظار اعتماد العميل: {awaiting}',
      listTitle: 'قائمة الطلبات',
      searchPlaceholder: 'بحث',
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
      requestTypeUrgent: 'عاجل',
      requestTypeCompetitive: 'تنافسي',
      requestTypeNormal: 'عادي',
      requestTypeDefault: 'طلب',
      requestFallback: 'طلب #{id}',
      currency: 'ر.س',
      openDetails: 'عرض التفاصيل',
    },
    en: {
      pageTitle: 'Nawafeth — My Orders',
      gateKicker: 'Your personal orders',
      gateTitle: 'Sign in to view your orders',
      gateDescription: 'You can track order status and details after signing in.',
      gateNote: 'Your account opens all order details in one place.',
      gateButton: 'Sign in',
      menu: 'Menu',
      heroAria: 'Orders summary',
      listAria: 'Orders list',
      title: 'My Orders',
      subtitle: 'A unified board to track statuses and actions',
      heroTitle: 'Orders summary',
      heroSubtitle: 'Start with what matters most, then open details when needed.',
      activeLabel: 'Active orders',
      totalLabel: 'Total orders',
      preExecutionLabel: 'Before execution',
      preExecutionNote: 'Accepted by provider: {accepted} • Awaiting client approval: {awaiting}',
      listTitle: 'Orders list',
      searchPlaceholder: 'Search',
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
      requestTypeUrgent: 'Urgent',
      requestTypeCompetitive: 'Competitive',
      requestTypeNormal: 'Standard',
      requestTypeDefault: 'Request',
      requestFallback: 'Request #{id}',
      currency: 'SAR',
      openDetails: 'Open details',
    },
  };

  let _all = [];
  let _activeTab = 'all';
  let _searchQuery = '';
  let _emptyMessage = '';

  function init() {
    _emptyMessage = _copy('empty');
    _applyStaticCopy();
    // Auth gate
    if (!Auth.isLoggedIn()) {
      _showGate(); return;
    }
    _hideGate();

    if (_activeMode() === 'provider') {
      window.location.href = '/provider-orders/';
      return;
    }

    // Tab clicks
    document.getElementById('status-tabs').addEventListener('click', e => {
      const btn = e.target.closest('.tab-btn');
      if (!btn) return;
      document.querySelectorAll('#status-tabs .tab-btn').forEach(t => t.classList.remove('active'));
      btn.classList.add('active');
      _activeTab = btn.dataset.status || 'all';
      _fetchOrders();
    });

    // Search
    const searchInput = document.getElementById('orders-search');
    const clearSearchBtn = document.getElementById('orders-search-clear');
    if (searchInput) {
      searchInput.addEventListener('input', e => {
        _searchQuery = String(e.target.value || '').trim();
        _toggleSearchClear();
      });
      searchInput.addEventListener('keydown', e => {
        if (e.key !== 'Enter') return;
        e.preventDefault();
        _searchQuery = String(searchInput.value || '').trim();
        _fetchOrders();
      });
    }
    if (clearSearchBtn && searchInput) {
      clearSearchBtn.addEventListener('click', () => {
        searchInput.value = '';
        _searchQuery = '';
        _toggleSearchClear();
        _fetchOrders();
      });
    }

    _toggleSearchClear();
    window.addEventListener('nawafeth:languagechange', _handleLanguageChange);
    _fetchOrders();
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

  function _buildEndpoint() {
    const params = new URLSearchParams();
    if (_activeTab && _activeTab !== 'all') {
      params.set('status_group', _activeTab);
    }
    if (_searchQuery) {
      params.set('q', _searchQuery);
    }
    const qs = params.toString();
    return '/api/marketplace/client/requests/' + (qs ? ('?' + qs) : '');
  }

  function _setLoadingState(loading) {
    const container = document.getElementById('orders-list');
    const emptyEl = document.getElementById('orders-empty');
    if (!container || !loading) return;

    container.innerHTML = [
      '<div class="orders-skeleton-card shimmer"></div>',
      '<div class="orders-skeleton-card shimmer"></div>',
      '<div class="orders-skeleton-card shimmer"></div>',
    ].join('');
    if (emptyEl) emptyEl.classList.add('hidden');
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
      _emptyMessage = _copy('syncingMode');
      _renderOrders();
      return;
    }
    const res = await ApiClient.get(_buildEndpoint());
    _setLoadingState(false);

    if (res.ok && res.data) {
      _all = Array.isArray(res.data) ? res.data : (res.data.results || []);
      _emptyMessage = _copy('empty');
      _renderOrders();
    } else if (res.status === 401) {
      const recovered = await Auth.resolveProfile(true, _activeMode());
      if (!recovered.ok && !Auth.isLoggedIn()) {
        _showGate();
        return;
      }
      _all = [];
      _emptyMessage = _copy('syncingSession');
      _renderOrders();
    } else {
      _all = [];
      _emptyMessage = _copy('loadFailed');
      _renderOrders();
    }
  }

  function _renderOrders() {
    const container = document.getElementById('orders-list');
    const emptyEl = document.getElementById('orders-empty');
    const emptyText = document.getElementById('orders-empty-text');
    if (!container || !emptyEl) return;

    const list = _sortByDateDesc(_all);
    const counts = _buildStatusCounts(list);

    _renderCounters(counts, list.length);

    container.innerHTML = '';
    if (!list.length) {
      if (emptyText) {
        if (_searchQuery) emptyText.textContent = _copy('emptySearch');
        else if (_activeTab !== 'all') emptyText.textContent = _copy('emptyStatus');
        else emptyText.textContent = _emptyMessage;
      }
      emptyEl.classList.remove('hidden');
      return;
    }
    emptyEl.classList.add('hidden');

    const frag = document.createDocumentFragment();
    list.forEach(order => frag.appendChild(_buildCard(order)));
    container.appendChild(frag);
  }

  function _statusGroup(orderOrStatus) {
    const explicit = String(
      orderOrStatus && typeof orderOrStatus === 'object'
        ? (orderOrStatus.status_group || orderOrStatus.status || '')
        : (orderOrStatus || '')
    ).toLowerCase();
    if (['new', 'in_progress', 'completed', 'cancelled'].includes(explicit)) return explicit;

    const map = {
      pending: 'new', submitted: 'new', waiting: 'new', new: 'new', provider_accepted: 'new', awaiting_client: 'new',
      accepted: 'in_progress', in_progress: 'in_progress', ongoing: 'in_progress',
      completed: 'completed', done: 'completed',
      cancelled: 'cancelled', rejected: 'cancelled', expired: 'cancelled'
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
      pending: 'جديد', submitted: 'مرسل', waiting: 'بانتظار', provider_accepted: 'تم قبول الطلب', awaiting_client: 'بانتظار اعتماد العميل للتفاصيل',
      accepted: 'قيد التنفيذ', in_progress: 'قيد التنفيذ', ongoing: 'قيد التنفيذ',
      completed: 'مكتمل', done: 'مكتمل',
      cancelled: 'ملغى', rejected: 'مرفوض', expired: 'منتهي'
    };
    return labels[raw] || (statusOrOrder && statusOrOrder.status_label) || _copy('statusUnknown');
  }

  function _statusColor(orderOrStatus) {
    const group = _statusGroup(orderOrStatus);
    switch (group) {
      case 'new': return '#FFA726';
      case 'in_progress': return '#42A5F5';
      case 'completed': return '#66BB6A';
      case 'cancelled': return '#EF5350';
      default: return '#9E9E9E';
    }
  }

  function _buildCard(order) {
    const orderId = order.id || order.request_id;
    const card = UI.el(orderId ? 'a' : 'div', { className: 'order-card' });
    if (orderId && card.tagName === 'A') {
      card.setAttribute('href', '/orders/' + orderId + '/');
    }

    // Header row: date + status
    const header = UI.el('div', { className: 'order-header' });
    const createdAt = order.created_at || order.created;
    if (createdAt) {
      header.appendChild(UI.el('span', {
        className: 'order-date',
        textContent: _formatDateTime(createdAt)
      }));
    }

    const badge = UI.el('span', {
      className: 'status-badge',
      textContent: _statusLabel(order)
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
        textContent: _requestTypeLabel(order.request_type)
      }));
    }
    if (orderId) {
      chips.appendChild(UI.el('span', {
        className: 'order-ref-chip',
        textContent: 'R' + String(orderId).padStart(6, '0')
      }));
    }
    card.appendChild(chips);

    const title = order.title || order.service_name || order.description || _copy('requestFallback').replace('{id}', String(order.id || ''));
    card.appendChild(UI.el('div', { className: 'order-title', textContent: title }));

    const description = String(order.description || '').trim();
    if (description && description !== title) {
      card.appendChild(UI.el('div', {
        className: 'order-snippet',
        textContent: description.length > 120 ? (description.slice(0, 120) + '...') : description
      }));
    }

    const footer = UI.el('div', { className: 'order-card-footer' });

    if (order.provider_name || order.provider) {
      const provRow = UI.el('div', { className: 'order-provider' });
      provRow.appendChild(UI.icon('storefront', 14, '#757575'));
      provRow.appendChild(UI.text(' ' + (order.provider_name || order.provider_display_name || _copy('providerFallback'))));
      footer.appendChild(provRow);
    }

    if (order.price || order.total_price || order.amount) {
      const price = order.price || order.total_price || order.amount;
      const numericPrice = Number(price);
      const safePrice = Number.isFinite(numericPrice) ? numericPrice.toLocaleString(_numberLocale()) : String(price);
      const priceEl = UI.el('div', { className: 'order-price', textContent: safePrice + ' ' + _copy('currency') });
      footer.appendChild(priceEl);
    }

    footer.appendChild(UI.el('span', { className: 'order-open-hint', textContent: _copy('openDetails') }));
    card.appendChild(footer);

    return card;
  }

  function _requestTypeLabel(type) {
    const key = String(type || '').toLowerCase();
    if (key === 'urgent') return _copy('requestTypeUrgent');
    if (key === 'competitive') return _copy('requestTypeCompetitive');
    if (key === 'normal') return _copy('requestTypeNormal');
    return type || _copy('requestTypeDefault');
  }

  function _buildStatusCounts(items) {
    const counts = {
      all: items.length,
      new: 0,
      provider_accepted: 0,
      awaiting_client: 0,
      in_progress: 0,
      completed: 0,
      cancelled: 0
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

  function _renderCounters(counts, filteredCount) {
    _setText('orders-total-count', String(counts.all || 0));
    _setText('orders-active-count', String((counts.new || 0) + (counts.in_progress || 0)));
    _setText(
      'orders-pre-execution-note',
      _copy('preExecutionNote')
        .replace('{accepted}', String(counts.provider_accepted || 0))
        .replace('{awaiting}', String(counts.awaiting_client || 0)),
    );
    _setText('orders-results-count', String(filteredCount || 0));

    document.querySelectorAll('#status-tabs .orders-tab-count').forEach((node) => {
      const key = String(node.dataset.countFor || 'all');
      node.textContent = String(counts[key] || 0);
    });
  }

  function _sortByDateDesc(items) {
    return [...items].sort((a, b) => _asTime(b) - _asTime(a));
  }

  function _asTime(item) {
    const source = item && (item.created_at || item.created);
    if (!source) return 0;
    const d = new Date(source);
    return Number.isNaN(d.getTime()) ? 0 : d.getTime();
  }

  function _workflowStage(order) {
    return String(order && order.status || '').toLowerCase();
  }

  function _formatDateTime(value) {
    const d = new Date(value);
    if (Number.isNaN(d.getTime())) return '';
    try {
      return new Intl.DateTimeFormat(_currentLang() === 'en' ? 'en-GB' : 'ar-SA', {
        hour: '2-digit',
        minute: '2-digit',
        day: '2-digit',
        month: '2-digit',
        year: 'numeric',
      }).format(d);
    } catch (_) {
      const hh = String(d.getHours()).padStart(2, '0');
      const mm = String(d.getMinutes()).padStart(2, '0');
      const dd = String(d.getDate()).padStart(2, '0');
      const mo = String(d.getMonth() + 1).padStart(2, '0');
      const yyyy = d.getFullYear();
      return hh + ':' + mm + '  ' + dd + '/' + mo + '/' + yyyy;
    }
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
    _setText('orders-page-title', _copy('title'));
    _setText('orders-page-subtitle', _copy('subtitle'));
    _setText('orders-hero-title', _copy('heroTitle'));
    _setText('orders-hero-subtitle', _copy('heroSubtitle'));
    _setText('orders-active-label', _copy('activeLabel'));
    _setText('orders-total-label', _copy('totalLabel'));
    _setText('orders-pre-execution-label', _copy('preExecutionLabel'));
    _setText('orders-list-title', _copy('listTitle'));
    _setText('orders-tab-all', _copy('tabAll'));
    _setText('orders-tab-new', _copy('tabNew'));
    _setText('orders-tab-in-progress', _copy('tabInProgress'));
    _setText('orders-tab-completed', _copy('tabCompleted'));
    _setText('orders-tab-cancelled', _copy('tabCancelled'));
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

  // Boot
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else { init(); }

  return {};
})();
