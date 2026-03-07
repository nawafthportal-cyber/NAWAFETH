/* ===================================================================
   providerOrdersPage.js — Provider Orders Management
   - Assigned requests
   - Available competitive requests
   - Available urgent requests
   =================================================================== */
'use strict';

const ProviderOrdersPage = (() => {
  const state = {
    assignedOrders: [],
    competitiveOrders: [],
    urgentOrders: [],
    activeTab: 'assigned', // assigned | competitive | urgent
    selectedStatusGroup: '',
    searchText: '',
  };

  function init() {
    if (!Auth.isLoggedIn()) {
      byId('auth-gate').style.display = '';
      return;
    }
    byId('porders-content').style.display = '';
    _applyInitialTabFromUrl();
    _bindMainTabs();
    _bindStatusTabs();
    _bindSearch();
    _syncTabUI();
    _fetchOrders();
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
      _markStatusFilter(group);
      _fetchOrders();
    });
  }

  function _bindSearch() {
    let timer = null;
    byId('po-search').addEventListener('input', (e) => {
      clearTimeout(timer);
      timer = setTimeout(() => {
        state.searchText = String(e.target.value || '').trim().toLowerCase();
        _render();
      }, 220);
    });
  }

  function _syncTabUI() {
    qsa('#po-request-tabs .status-tab').forEach((btn) => {
      btn.classList.toggle('active', btn.dataset.tab === state.activeTab);
    });
    const statusTabs = byId('po-status-tabs');
    if (statusTabs) {
      statusTabs.style.display = state.activeTab === 'assigned' ? '' : 'none';
    }
  }

  function _markStatusFilter(group) {
    qsa('#po-status-tabs .status-tab').forEach((btn) => {
      btn.classList.toggle('active', String(btn.dataset.group || '') === group);
    });
  }

  async function _fetchOrders() {
    _setLoading(true);
    _setError('');
    const statusQuery = state.selectedStatusGroup
      ? ('?status_group=' + encodeURIComponent(state.selectedStatusGroup))
      : '';

    const [assignedRes, competitiveRes, urgentRes] = await Promise.allSettled([
      ApiClient.get('/api/marketplace/provider/requests/' + statusQuery),
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
    setText('po-count-assigned', String(state.assignedOrders.length));
    setText('po-count-competitive', String(state.competitiveOrders.length));
    setText('po-count-urgent', String(state.urgentOrders.length));
  }

  function _extractList(payload) {
    if (Array.isArray(payload)) return payload;
    if (payload && Array.isArray(payload.results)) return payload.results;
    return [];
  }

  function _currentOrders() {
    if (state.activeTab === 'competitive') return state.competitiveOrders;
    if (state.activeTab === 'urgent') return state.urgentOrders;
    return state.assignedOrders;
  }

  function _filteredOrders() {
    const list = _currentOrders();
    if (!state.searchText) return list;
    return list.filter((o) => {
      const id = String(o.display_id || o.id || '').toLowerCase();
      const title = String(o.title || '').toLowerCase();
      const client = String(o.client_name || '').toLowerCase();
      const city = String(o.city || '').toLowerCase();
      return (
        id.includes(state.searchText) ||
        title.includes(state.searchText) ||
        client.includes(state.searchText) ||
        city.includes(state.searchText)
      );
    });
  }

  function _render() {
    const list = _filteredOrders();
    const container = byId('po-list');
    const empty = byId('po-empty');
    container.innerHTML = '';

    if (!list.length) {
      empty.style.display = '';
      const text = empty.querySelector('p');
      if (text) {
        if (state.activeTab === 'competitive') text.textContent = 'لا توجد طلبات عروض أسعار متاحة';
        else if (state.activeTab === 'urgent') text.textContent = 'لا توجد طلبات عاجلة متاحة';
        else text.textContent = 'لا توجد طلبات';
      }
      return;
    }

    empty.style.display = 'none';
    const frag = document.createDocumentFragment();
    list.forEach((order) => frag.appendChild(_buildCard(order)));
    container.appendChild(frag);
  }

  function _buildCard(order) {
    const card = UI.el('a', {
      className: 'order-card po-card',
      href: '/provider-orders/' + String(order.id) + '/',
    });

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
    if (order.city) {
      body.appendChild(UI.el('p', {
        className: 'order-date',
        textContent: 'المدينة: ' + String(order.city),
      }));
    }
    body.appendChild(UI.el('p', {
      className: 'order-date',
      textContent: _formatDate(order.created_at),
    }));

    card.appendChild(top);
    card.appendChild(body);
    return card;
  }

  function _metaLine(order) {
    const parts = [];
    if (order.client_name) parts.push(String(order.client_name));
    if (order.category_name) parts.push(String(order.category_name));
    return parts.join(' • ');
  }

  function _statusGroup(order) {
    const explicit = String(order.status_group || '').toLowerCase();
    if (['new', 'in_progress', 'completed', 'cancelled'].includes(explicit)) return explicit;
    const status = String(order.status || '').toLowerCase();
    if (['pending', 'new', 'submitted'].includes(status)) return 'new';
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

  function _setLoading(loading) {
    const el = byId('po-loading');
    if (el) el.style.display = loading ? '' : 'none';
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
