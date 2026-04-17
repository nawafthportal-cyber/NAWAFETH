/* ===================================================================
   ordersPage.js — Orders / client requests page controller
   GET /api/marketplace/client/requests/?status_group=X
   =================================================================== */
'use strict';

const OrdersPage = (() => {
  let _all = [];
  let _activeTab = 'all';
  let _searchQuery = '';
  let _emptyMessage = 'لا توجد طلبات';

  function init() {
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
    const res = await ApiClient.get(_buildEndpoint());
    _setLoadingState(false);

    if (res.ok && res.data) {
      _all = Array.isArray(res.data) ? res.data : (res.data.results || []);
      _emptyMessage = 'لا توجد طلبات';
      _renderOrders();
    } else if (res.status === 401) {
      _showGate();
    } else {
      _all = [];
      _emptyMessage = 'تعذر تحميل الطلبات حاليًا';
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
        if (_searchQuery) emptyText.textContent = 'لا توجد نتائج مطابقة لبحثك';
        else if (_activeTab !== 'all') emptyText.textContent = 'لا توجد طلبات في هذه الحالة';
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
    return labels[raw] || (statusOrOrder && statusOrOrder.status_label) || 'غير محدد';
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

    const title = order.title || order.service_name || order.description || 'طلب #' + (order.id || '');
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
      provRow.appendChild(UI.text(' ' + (order.provider_name || order.provider_display_name || 'مقدم خدمة')));
      footer.appendChild(provRow);
    }

    if (order.price || order.total_price || order.amount) {
      const price = order.price || order.total_price || order.amount;
      const numericPrice = Number(price);
      const safePrice = Number.isFinite(numericPrice) ? numericPrice.toLocaleString('ar-SA') : String(price);
      const priceEl = UI.el('div', { className: 'order-price', textContent: safePrice + ' ر.س' });
      footer.appendChild(priceEl);
    }

    footer.appendChild(UI.el('span', { className: 'order-open-hint', textContent: 'عرض التفاصيل' }));
    card.appendChild(footer);

    return card;
  }

  function _requestTypeLabel(type) {
    const key = String(type || '').toLowerCase();
    if (key === 'urgent') return 'عاجل';
    if (key === 'competitive') return 'تنافسي';
    if (key === 'normal') return 'عادي';
    return type || 'طلب';
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
      'تم قبول الطلب: ' + String(counts.provider_accepted || 0) + ' • بانتظار اعتماد العميل: ' + String(counts.awaiting_client || 0),
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
    const hh = String(d.getHours()).padStart(2, '0');
    const mm = String(d.getMinutes()).padStart(2, '0');
    const dd = String(d.getDate()).padStart(2, '0');
    const mo = String(d.getMonth() + 1).padStart(2, '0');
    const yyyy = d.getFullYear();
    return hh + ':' + mm + '  ' + dd + '/' + mo + '/' + yyyy;
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

  // Boot
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else { init(); }

  return {};
})();
