/* ===================================================================
   ordersPage.js — Orders / client requests page controller
   GET /api/marketplace/client/requests/?status_group=X
   =================================================================== */
'use strict';

const OrdersPage = (() => {
  let _all = [];
  let _activeTab = 'all';
  let _searchQuery = '';

  function init() {
    // Auth gate
    if (!Auth.isLoggedIn()) {
      _showGate(); return;
    }
    _hideGate();

    // Tab clicks
    document.getElementById('status-tabs').addEventListener('click', e => {
      const btn = e.target.closest('.tab-btn');
      if (!btn) return;
      document.querySelectorAll('#status-tabs .tab-btn').forEach(t => t.classList.remove('active'));
      btn.classList.add('active');
      _activeTab = btn.dataset.status || 'all';
      _renderOrders();
    });

    // Search
    const searchInput = document.getElementById('orders-search');
    if (searchInput) {
      searchInput.addEventListener('input', e => {
        _searchQuery = e.target.value.trim().toLowerCase();
        _renderOrders();
      });
    }

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

  async function _fetchOrders() {
    const res = await ApiClient.get('/api/marketplace/client/requests/');
    if (res.ok && res.data) {
      _all = Array.isArray(res.data) ? res.data : (res.data.results || []);
      _renderOrders();
    } else if (res.status === 401) {
      _showGate();
    }
  }

  function _renderOrders() {
    const container = document.getElementById('orders-list');
    const emptyEl = document.getElementById('orders-empty');

    let list = _all;
    if (_activeTab !== 'all') {
      list = _all.filter(o => _statusGroup(o.status) === _activeTab);
    }
    // Search filter
    if (_searchQuery) {
      list = list.filter(o => {
        const text = (o.title || '') + ' ' + (o.description || '') + ' ' + (o.provider_name || '') + ' ' + (o.service_name || '');
        return text.toLowerCase().includes(_searchQuery);
      });
    }

    container.innerHTML = '';
    if (!list.length) { emptyEl.classList.remove('hidden'); return; }
    emptyEl.classList.add('hidden');

    const frag = document.createDocumentFragment();
    list.forEach(order => frag.appendChild(_buildCard(order)));
    container.appendChild(frag);
  }

  function _statusGroup(status) {
    const map = {
      pending: 'new', submitted: 'new', waiting: 'new', new: 'new',
      accepted: 'in_progress', in_progress: 'in_progress', ongoing: 'in_progress',
      completed: 'completed', done: 'completed',
      cancelled: 'cancelled', rejected: 'cancelled', expired: 'cancelled'
    };
    return map[(status || '').toLowerCase()] || 'in_progress';
  }

  function _statusLabel(status) {
    const labels = {
      pending: 'بانتظار', submitted: 'مرسل', waiting: 'بانتظار',
      accepted: 'مقبول', in_progress: 'قيد التنفيذ', ongoing: 'جارٍ',
      completed: 'مكتمل', done: 'مكتمل',
      cancelled: 'ملغى', rejected: 'مرفوض', expired: 'منتهي'
    };
    return labels[(status || '').toLowerCase()] || status || 'غير محدد';
  }

  function _statusColor(status) {
    const group = _statusGroup(status);
    switch (group) {
      case 'new': return '#FFA726';
      case 'in_progress': return '#42A5F5';
      case 'completed': return '#66BB6A';
      case 'cancelled': return '#EF5350';
      default: return '#9E9E9E';
    }
  }

  function _buildCard(order) {
    const card = UI.el('div', { className: 'order-card' });

    // Header row: status badge + date
    const header = UI.el('div', { className: 'order-header' });
    const badge = UI.el('span', {
      className: 'status-badge',
      textContent: _statusLabel(order.status)
    });
    badge.style.backgroundColor = _statusColor(order.status) + '22';
    badge.style.color = _statusColor(order.status);
    badge.style.borderColor = _statusColor(order.status);
    header.appendChild(badge);

    if (order.created_at || order.created) {
      const d = new Date(order.created_at || order.created);
      header.appendChild(UI.el('span', {
        className: 'order-date',
        textContent: d.toLocaleDateString('ar-SA', { day: 'numeric', month: 'short', year: 'numeric' })
      }));
    }
    card.appendChild(header);

    // Title / description
    const title = order.title || order.service_name || order.description || 'طلب #' + (order.id || '');
    card.appendChild(UI.el('div', { className: 'order-title', textContent: title }));

    // Provider row
    if (order.provider_name || order.provider) {
      const provRow = UI.el('div', { className: 'order-provider' });
      provRow.appendChild(UI.icon('storefront', 14, '#757575'));
      provRow.appendChild(UI.text(' ' + (order.provider_name || order.provider_display_name || 'مقدم خدمة')));
      card.appendChild(provRow);
    }

    // Price
    if (order.price || order.total_price || order.amount) {
      const price = order.price || order.total_price || order.amount;
      const priceEl = UI.el('div', { className: 'order-price', textContent: parseFloat(price).toLocaleString('ar-SA') + ' ر.س' });
      card.appendChild(priceEl);
    }

    return card;
  }

  // Boot
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else { init(); }

  return {};
})();
