/* ===================================================================
   providerOrdersPage.js — Provider Orders Management
   - Assigned requests
   - Available competitive requests
   - Available urgent requests
   =================================================================== */
'use strict';

const ProviderOrdersPage = (() => {
  const STORAGE_KEY = 'nawafeth.providerOrders.ui.v1';
  const SORT_LABELS = {
    newest: 'الأحدث',
    oldest: 'الأقدم',
    status: 'حسب الحالة',
    city: 'حسب المدينة',
    amount_desc: 'الأعلى قيمة',
    deadline: 'الأقرب موعدًا',
  };

  const state = {
    assignedOrders: [],
    competitiveOrders: [],
    urgentOrders: [],
    activeTab: 'assigned', // assigned | competitive | urgent
    selectedStatusGroup: '',
    searchText: '',
    sortBy: 'newest',
    isFetching: false,
  };

  function init() {
    if (!Auth.isLoggedIn()) {
      byId('auth-gate').style.display = '';
      return;
    }
    _loadPersistedState();
    byId('porders-content').style.display = '';
    _applyInitialTabFromUrl();
    _bindMainTabs();
    _bindStatusTabs();
    _bindSearch();
    _bindSortControl();
    _bindUtilityButtons();
    _applyStateToControls();
    _syncTabUI();
    _fetchOrders();
  }

  function _loadPersistedState() {
    try {
      const raw = window.localStorage.getItem(STORAGE_KEY);
      if (!raw) return;
      const saved = JSON.parse(raw);
      if (!saved || typeof saved !== 'object') return;

      const tab = String(saved.activeTab || '').trim().toLowerCase();
      if (['assigned', 'competitive', 'urgent'].includes(tab)) {
        state.activeTab = tab;
      }

      const group = String(saved.selectedStatusGroup || '').trim();
      if (['', 'new', 'in_progress', 'completed', 'cancelled'].includes(group)) {
        state.selectedStatusGroup = group;
      }

      state.searchText = String(saved.searchText || '').trim().toLowerCase();

      const sortBy = String(saved.sortBy || '').trim();
      if (Object.prototype.hasOwnProperty.call(SORT_LABELS, sortBy)) {
        state.sortBy = sortBy;
      }
    } catch (_) {
      // ignore storage parsing errors
    }
  }

  function _persistState() {
    try {
      window.localStorage.setItem(
        STORAGE_KEY,
        JSON.stringify({
          activeTab: state.activeTab,
          selectedStatusGroup: state.selectedStatusGroup,
          searchText: state.searchText,
          sortBy: state.sortBy,
        }),
      );
    } catch (_) {
      // ignore storage write errors
    }
  }

  function _applyInitialTabFromUrl() {
    try {
      const tab = String(new URLSearchParams(window.location.search).get('tab') || '').trim().toLowerCase();
      if (['assigned', 'competitive', 'urgent'].includes(tab)) {
        state.activeTab = tab;
      }
    } catch (_) {
      // ignore malformed url
    }
  }

  function _bindMainTabs() {
    byId('po-request-tabs').addEventListener('click', (e) => {
      const btn = e.target.closest('.status-tab');
      if (!btn) return;
      const tab = String(btn.dataset.tab || '').trim();
      if (!['assigned', 'competitive', 'urgent'].includes(tab)) return;
      if (state.activeTab === tab) return;
      state.activeTab = tab;
      if (state.activeTab !== 'assigned') {
        state.selectedStatusGroup = '';
        _markStatusFilter('');
      }
      _persistState();
      _syncTabUI();
      _render();
    });
  }

  function _bindStatusTabs() {
    byId('po-status-tabs').addEventListener('click', (e) => {
      const btn = e.target.closest('.status-tab');
      if (!btn || state.activeTab !== 'assigned') return;
      const group = String(btn.dataset.group || '').trim();
      if (state.selectedStatusGroup === group) return;
      state.selectedStatusGroup = group;
      _persistState();
      _markStatusFilter(group);
      _render();
    });
  }

  function _bindSearch() {
    let timer = null;
    byId('po-search').addEventListener('input', (e) => {
      clearTimeout(timer);
      timer = setTimeout(() => {
        state.searchText = String(e.target.value || '').trim().toLowerCase();
        _updateClearSearchState();
        _persistState();
        _render();
      }, 220);
    });
  }

  function _bindSortControl() {
    const select = byId('po-sort-select');
    if (!select) return;
    select.addEventListener('change', (e) => {
      const next = String(e.target.value || '').trim();
      if (!Object.prototype.hasOwnProperty.call(SORT_LABELS, next)) return;
      state.sortBy = next;
      _persistState();
      _render();
    });
  }

  function _bindUtilityButtons() {
    const refreshBtn = byId('po-refresh-btn');
    if (refreshBtn) {
      refreshBtn.addEventListener('click', () => {
        if (state.isFetching) return;
        _fetchOrders();
      });
    }

    const clearBtn = byId('po-clear-search-btn');
    if (clearBtn) {
      clearBtn.addEventListener('click', () => {
        const input = byId('po-search');
        if (input) input.value = '';
        state.searchText = '';
        _persistState();
        _updateClearSearchState();
        _render();
      });
    }

    _updateClearSearchState();
  }

  function _syncTabUI() {
    qsa('#po-request-tabs .status-tab').forEach((btn) => {
      btn.classList.toggle('active', btn.dataset.tab === state.activeTab);
    });
    const statusTabs = byId('po-status-tabs');
    if (statusTabs) {
      statusTabs.style.display = state.activeTab === 'assigned' ? '' : 'none';
    }

    const legend = byId('po-status-legend');
    if (legend) {
      legend.style.display = state.activeTab === 'assigned' ? '' : 'none';
    }

    _updateSearchPlaceholder();
    _markStatusFilter(state.selectedStatusGroup);
    _updateSmartBar(_filteredOrders().length);
  }

  function _applyStateToControls() {
    const searchInput = byId('po-search');
    if (searchInput) {
      searchInput.value = state.searchText;
    }

    const sortSelect = byId('po-sort-select');
    if (sortSelect && Object.prototype.hasOwnProperty.call(SORT_LABELS, state.sortBy)) {
      sortSelect.value = state.sortBy;
    }

    _updateClearSearchState();
  }

  function _markStatusFilter(group) {
    qsa('#po-status-tabs .status-tab').forEach((btn) => {
      btn.classList.toggle('active', String(btn.dataset.group || '') === group);
    });
  }

  async function _fetchOrders() {
    state.isFetching = true;
    _syncRefreshButtonState();
    _setLoading(true);
    _setError('');

    const [assignedRes, competitiveRes, urgentRes] = await Promise.allSettled([
      ApiClient.get('/api/marketplace/provider/requests/'),
      ApiClient.get('/api/marketplace/provider/competitive/available/'),
      ApiClient.get('/api/marketplace/provider/urgent/available/'),
    ]);

    const assignedOk = assignedRes.status === 'fulfilled' && assignedRes.value.ok;
    const competitiveOk = competitiveRes.status === 'fulfilled' && competitiveRes.value.ok;
    const urgentOk = urgentRes.status === 'fulfilled' && urgentRes.value.ok;

    if (assignedOk) {
      state.assignedOrders = _extractList(assignedRes.value.data);
    }
    if (competitiveOk) {
      state.competitiveOrders = _extractList(competitiveRes.value.data);
    }
    if (urgentOk) {
      state.urgentOrders = _extractList(urgentRes.value.data);
    }

    state.isFetching = false;
    _syncRefreshButtonState();
    _setLoading(false);

    if (!assignedOk && !competitiveOk && !urgentOk) {
      _setError('تعذّر تحميل الطلبات. حاول مرة أخرى.');
      _render();
      return;
    }

    _updateCounts();
    _render();
  }

  function _updateCounts() {
    const assigned = String(state.assignedOrders.length);
    const competitive = String(state.competitiveOrders.length);
    const urgent = String(state.urgentOrders.length);
    const workflow = _assignedWorkflowCounts();

    setText('po-count-assigned', assigned);
    setText('po-count-competitive', competitive);
    setText('po-count-urgent', urgent);
    setText('po-kpi-assigned', assigned);
    setText('po-kpi-competitive', competitive);
    setText('po-kpi-urgent', urgent);
    setText(
      'po-workflow-count-label',
      'بانتظار القبول: ' + String(workflow.awaiting_acceptance) + ' • بانتظار اعتماد العميل: ' + String(workflow.awaiting_client),
    );
  }

  function _assignedWorkflowCounts() {
    const counts = { awaiting_acceptance: 0, awaiting_client: 0 };
    state.assignedOrders.forEach((order) => {
      const stage = String(order && order.status || '').toLowerCase();
      const type = String(order && order.request_type || '').toLowerCase();
      if (type === 'normal' && stage === 'new') counts.awaiting_acceptance += 1;
      if (stage === 'awaiting_client') counts.awaiting_client += 1;
    });
    return counts;
  }

  function _extractList(payload) {
    if (Array.isArray(payload)) return payload;
    if (payload && Array.isArray(payload.results)) return payload.results;
    return [];
  }

  function _currentOrders() {
    if (state.activeTab === 'competitive') return state.competitiveOrders;
    if (state.activeTab === 'urgent') return state.urgentOrders;
    if (!state.selectedStatusGroup) return state.assignedOrders;
    return state.assignedOrders.filter((order) => _statusGroup(order) === state.selectedStatusGroup);
  }

  function _orderCityText(order) {
    return UI.formatCityDisplay(order && (order.city_display || order.city), order && (order.region || order.region_name));
  }

  function _filteredOrders() {
    const list = _currentOrders();
    const filtered = !state.searchText ? list.slice() : list.filter((o) => {
      const id = String(o.display_id || o.id || '').toLowerCase();
      const title = String(o.title || '').toLowerCase();
      const client = String(o.client_name || '').toLowerCase();
      const city = (_orderCityText(o) + ' ' + String(o.city || '')).toLowerCase();
      return (
        id.includes(state.searchText) ||
        title.includes(state.searchText) ||
        client.includes(state.searchText) ||
        city.includes(state.searchText)
      );
    });

    return _sortOrders(filtered);
  }

  function _sortOrders(list) {
    const rows = Array.isArray(list) ? list.slice() : [];
    const rankByStatus = { new: 0, in_progress: 1, completed: 2, cancelled: 3 };

    rows.sort((a, b) => {
      const ta = _timestamp(a.created_at);
      const tb = _timestamp(b.created_at);

      if (state.sortBy === 'oldest') return ta - tb;
      if (state.sortBy === 'status') {
        const ra = rankByStatus[_statusGroup(a)] ?? 99;
        const rb = rankByStatus[_statusGroup(b)] ?? 99;
        if (ra !== rb) return ra - rb;
        return tb - ta;
      }
      if (state.sortBy === 'city') {
        const ca = _orderCityText(a);
        const cb = _orderCityText(b);
        const cityResult = ca.localeCompare(cb, 'ar');
        if (cityResult !== 0) return cityResult;
        return tb - ta;
      }
      if (state.sortBy === 'amount_desc') {
        const aa = _amountValue(a);
        const ab = _amountValue(b);
        if (ab !== aa) return ab - aa;
        return tb - ta;
      }
      if (state.sortBy === 'deadline') {
        const da = _deadlineValue(a);
        const db = _deadlineValue(b);
        if (da !== db) return da - db;
        return tb - ta;
      }

      // newest (default)
      return tb - ta;
    });

    return rows;
  }

  function _render() {
    const list = _filteredOrders();
    const container = byId('po-list');
    const empty = byId('po-empty');
    container.innerHTML = '';
    container.classList.toggle('is-single', list.length === 1);
    _updateSmartBar(list.length);

    if (!list.length) {
      empty.style.display = '';
      const text = empty.querySelector('p');
      const hint = empty.querySelector('small');
      if (text) {
        if (state.searchText) text.textContent = 'لا توجد نتائج مطابقة';
        else if (state.activeTab === 'competitive') text.textContent = 'لا توجد طلبات عروض أسعار متاحة';
        else if (state.activeTab === 'urgent') text.textContent = 'لا توجد طلبات عاجلة متاحة';
        else text.textContent = 'لا توجد طلبات';
      }
      if (hint) {
        if (state.searchText) hint.textContent = 'جرّب كلمات بحث مختلفة أو امسح البحث لعرض كل الطلبات.';
        else if (state.activeTab === 'assigned') hint.textContent = 'غيّر تبويب الحالة أو راجع الطلبات الأخرى في التبويبات العلوية.';
        else hint.textContent = 'يمكنك سحب الصفحة للتحديث أو الضغط على زر تحديث البيانات.';
      }
      return;
    }

    empty.style.display = 'none';
    const frag = document.createDocumentFragment();
    list.forEach((order, index) => frag.appendChild(_buildCard(order, index)));
    container.appendChild(frag);
  }

  function _buildCard(order, index) {
    const statusGroup = _statusGroup(order);
    const card = UI.el('a', {
      className: 'order-card po-card po-card-' + statusGroup,
      href: '/provider-orders/' + String(order.id) + '/',
    });
    card.style.setProperty('--po-card-delay', String(Math.min(index || 0, 10) * 28) + 'ms');

    const top = UI.el('div', { className: 'order-card-top po-card-top' });
    const start = UI.el('div', { className: 'po-card-head' });
    const headTitle = (String(order.display_id || order.id || '-') + '  ' + String(order.client_name || '')).trim();
    start.appendChild(UI.el('span', {
      className: 'order-id',
      textContent: headTitle,
    }));

    const type = String(order.request_type || '').toLowerCase();
    if (type && type !== 'normal') {
      const typeBadge = UI.el('span', {
        className: 'order-type-badge',
        textContent: _typeLabel(type),
      });
      start.appendChild(typeBadge);
    }

    if (state.activeTab !== 'assigned' && !order.provider) {
      start.appendChild(UI.el('span', {
        className: 'po-available-badge',
        textContent: 'متاح',
      }));
    }

    const status = UI.el('span', {
      className: 'order-status',
      textContent: _statusLabel(order),
      style: {
        color: _statusColor(order),
        borderColor: _statusColor(order),
        backgroundColor: _statusBg(order),
      },
    });

    top.appendChild(start);
    top.appendChild(status);

    const body = UI.el('div', { className: 'order-card-body' });
    body.appendChild(UI.el('h4', {
      textContent: String(order.title || 'طلب بدون عنوان'),
    }));
    body.appendChild(UI.el('p', {
      className: 'order-meta',
      textContent: _metaLine(order),
    }));
    const cityText = _orderCityText(order);
    if (cityText) {
      body.appendChild(UI.el('p', {
        className: 'order-date',
        textContent: 'المدينة: ' + cityText,
      }));
    }

    const pills = UI.el('div', { className: 'po-card-pills' });
    if (order.category_name) {
      pills.appendChild(UI.el('span', {
        className: 'po-card-pill',
        textContent: String(order.category_name),
      }));
    }
    if (order.subcategory_name) {
      pills.appendChild(UI.el('span', {
        className: 'po-card-pill po-card-pill-soft',
        textContent: String(order.subcategory_name),
      }));
    }
    if (order.quote_deadline) {
      pills.appendChild(UI.el('span', {
        className: 'po-card-pill po-card-pill-warning',
        textContent: 'آخر موعد عرض: ' + _formatDateOnly(order.quote_deadline),
      }));
    }
    if (order.expected_delivery_at) {
      pills.appendChild(UI.el('span', {
        className: 'po-card-pill po-card-pill-info',
        textContent: 'تسليم متوقع: ' + _formatDateOnly(order.expected_delivery_at),
      }));
    }
    if (order.estimated_service_amount !== null && order.estimated_service_amount !== undefined && order.estimated_service_amount !== '') {
      pills.appendChild(UI.el('span', {
        className: 'po-card-pill po-card-pill-success',
        textContent: 'قيمة مقدرة: ' + _formatMoney(order.estimated_service_amount),
      }));
    }
    if (pills.childElementCount) {
      body.appendChild(pills);
    }

    const footer = UI.el('div', { className: 'po-card-footer' });
    footer.appendChild(UI.el('span', {
      className: 'po-card-date',
      textContent: _formatDate(order.created_at),
    }));
    footer.appendChild(UI.el('span', {
      className: 'po-card-link',
      textContent: 'عرض التفاصيل',
    }));
    body.appendChild(footer);

    card.appendChild(top);
    card.appendChild(body);
    return card;
  }

  function _metaLine(order) {
    const parts = [];
    if (state.activeTab !== 'assigned' && order.client_name) {
      parts.push('العميل: ' + String(order.client_name));
    }
    if (order.category_name && !order.subcategory_name) {
      parts.push(String(order.category_name));
    }
    return parts.join(' • ');
  }

  function _activeTabLabel() {
    if (state.activeTab === 'competitive') return 'عروض الأسعار المتاحة';
    if (state.activeTab === 'urgent') return 'الطلبات العاجلة المتاحة';
    return 'الطلبات المسندة لي';
  }

  function _statusGroupLabel() {
    const map = {
      '': 'كل الحالات',
      new: 'جديد',
      in_progress: 'تحت التنفيذ',
      completed: 'مكتمل',
      cancelled: 'ملغي',
    };
    return map[String(state.selectedStatusGroup || '')] || 'كل الحالات';
  }

  function _updateSearchPlaceholder() {
    const input = byId('po-search');
    if (!input) return;
    if (state.activeTab === 'competitive') {
      input.placeholder = 'بحث في عروض الأسعار المتاحة برقم الطلب أو العنوان أو المدينة';
      return;
    }
    if (state.activeTab === 'urgent') {
      input.placeholder = 'بحث في الطلبات العاجلة برقم الطلب أو العنوان أو المدينة';
      return;
    }
    input.placeholder = 'بحث برقم الطلب أو العنوان أو العميل أو المدينة';
  }

  function _updateSmartBar(visibleCount) {
    const title = byId('po-active-view-label');
    const count = byId('po-visible-count-label');
    const sortHint = byId('po-sort-hint-label');

    if (title) {
      title.textContent = state.activeTab === 'assigned'
        ? (_activeTabLabel() + ' • ' + _statusGroupLabel())
        : _activeTabLabel();
    }

    if (count) {
      const totalLabel = Number(visibleCount || 0).toLocaleString('ar-SA');
      count.textContent = state.searchText
        ? (totalLabel + ' نتيجة بعد البحث')
        : (totalLabel + ' طلب ظاهر');
    }

    if (sortHint) {
      sortHint.textContent = 'الترتيب: ' + (SORT_LABELS[state.sortBy] || SORT_LABELS.newest);
    }
  }

  function _updateClearSearchState() {
    const btn = byId('po-clear-search-btn');
    if (!btn) return;
    const hasSearch = Boolean(state.searchText);
    btn.disabled = !hasSearch;
    btn.classList.toggle('is-disabled', !hasSearch);
  }

  function _syncRefreshButtonState() {
    const btn = byId('po-refresh-btn');
    if (!btn) return;
    btn.disabled = state.isFetching;
    btn.textContent = state.isFetching ? 'جاري التحديث...' : 'تحديث البيانات';
  }

  function _statusGroup(order) {
    const explicit = String(order.status_group || '').toLowerCase();
    if (['new', 'in_progress', 'completed', 'cancelled'].includes(explicit)) return explicit;
    const status = String(order.status || '').toLowerCase();
    if (['pending', 'new', 'submitted', 'provider_accepted', 'awaiting_client'].includes(status)) return 'new';
    if (['in_progress', 'accepted', 'started'].includes(status)) return 'in_progress';
    if (['completed', 'done', 'finished'].includes(status)) return 'completed';
    if (['cancelled', 'rejected', 'expired', 'canceled'].includes(status)) return 'cancelled';
    return 'new';
  }

  function _statusLabel(order) {
    const label = String(order.status_label || '').trim();
    if (label) return label;
    const map = {
      new: 'جديد',
      provider_accepted: 'تم قبول الطلب',
      awaiting_client: 'بانتظار اعتماد العميل للتفاصيل',
      in_progress: 'تحت التنفيذ',
      completed: 'مكتمل',
      cancelled: 'ملغي',
    };
    return map[_statusGroup(order)] || 'جديد';
  }

  function _statusColor(order) {
    const group = _statusGroup(order);
    if (group === 'completed') return '#2E7D32';
    if (group === 'cancelled') return '#C62828';
    if (group === 'in_progress') return '#E67E22';
    return '#A56800';
  }

  function _statusBg(order) {
    const group = _statusGroup(order);
    if (group === 'completed') return 'rgba(46, 125, 50, 0.11)';
    if (group === 'cancelled') return 'rgba(198, 40, 40, 0.11)';
    if (group === 'in_progress') return 'rgba(230, 126, 34, 0.11)';
    return 'rgba(165, 104, 0, 0.11)';
  }

  function _typeLabel(type) {
    return { normal: 'عادي', competitive: 'تنافسي', urgent: 'عاجل' }[type] || type || '';
  }

  function _formatDate(value) {
    const dt = value ? new Date(value) : null;
    if (!dt || Number.isNaN(dt.getTime())) return '';
    return dt.toLocaleString('ar-SA', {
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
    });
  }

  function _formatDateOnly(value) {
    const dt = value ? new Date(value) : null;
    if (!dt || Number.isNaN(dt.getTime())) return '';
    return dt.toLocaleDateString('ar-SA', {
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    });
  }

  function _formatMoney(value) {
    const num = Number(value);
    if (!Number.isFinite(num)) return String(value || '-');
    return num.toLocaleString('ar-SA') + ' ر.س';
  }

  function _amountValue(order) {
    const candidates = [
      order && order.estimated_service_amount,
      order && order.actual_service_amount,
      order && order.received_amount,
      order && order.remaining_amount,
    ];
    for (let i = 0; i < candidates.length; i += 1) {
      const val = Number(candidates[i]);
      if (Number.isFinite(val)) return val;
    }
    return -1;
  }

  function _deadlineValue(order) {
    const candidates = [
      order && order.expected_delivery_at,
      order && order.quote_deadline,
      order && order.delivered_at,
    ];
    for (let i = 0; i < candidates.length; i += 1) {
      const ts = _timestamp(candidates[i]);
      if (Number.isFinite(ts) && ts > 0) return ts;
    }
    return Number.POSITIVE_INFINITY;
  }

  function _timestamp(value) {
    const dt = value ? new Date(value) : null;
    if (!dt || Number.isNaN(dt.getTime())) return 0;
    return dt.getTime();
  }

  function _setLoading(loading) {
    const el = byId('po-loading');
    if (el) el.style.display = loading ? '' : 'none';
    const list = byId('po-list');
    if (list) list.classList.toggle('is-loading', !!loading);
  }

  function _setError(message) {
    const el = byId('po-error');
    if (!el) return;
    if (!message) {
      el.textContent = '';
      el.classList.add('hidden');
      return;
    }
    el.textContent = message;
    el.classList.remove('hidden');
  }

  function byId(id) {
    return document.getElementById(id);
  }

  function qsa(selector) {
    return Array.from(document.querySelectorAll(selector));
  }

  function setText(id, value) {
    const el = byId(id);
    if (el) el.textContent = value;
  }

  document.addEventListener('DOMContentLoaded', init);
  return { init };
})();
