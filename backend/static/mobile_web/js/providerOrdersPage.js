/* ===================================================================
   providerOrdersPage.js — Provider Orders Management (إدارة الطلبات)
   1:1 parity with Flutter provider_orders_screen.dart
   =================================================================== */
'use strict';

const ProviderOrdersPage = (() => {
  let _orders = [];
  let _activeGroup = 'all';
  let _searchText = '';

  function init() {
    if (!Auth.isLoggedIn()) {
      document.getElementById('auth-gate').style.display = '';
      return;
    }
    document.getElementById('porders-content').style.display = '';
    _bindTabs();
    _bindSearch();
    _fetchOrders();
  }

  function _bindTabs() {
    document.getElementById('po-status-tabs').addEventListener('click', (e) => {
      const btn = e.target.closest('.status-tab');
      if (!btn) return;
      document.querySelectorAll('#po-status-tabs .status-tab').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      _activeGroup = btn.dataset.group;
      _render();
    });
  }

  function _bindSearch() {
    let timer;
    document.getElementById('po-search').addEventListener('input', (e) => {
      clearTimeout(timer);
      timer = setTimeout(() => {
        _searchText = e.target.value.trim().toLowerCase();
        _render();
      }, 300);
    });
  }

  async function _fetchOrders() {
    document.getElementById('po-loading').style.display = '';
    const res = await ApiClient.get('/api/marketplace/provider/requests/');
    document.getElementById('po-loading').style.display = 'none';
    if (res.ok) {
      _orders = res.data?.results || res.data || [];
      _render();
    }
  }

  function _getFiltered() {
    let list = _orders;
    if (_activeGroup !== 'all') {
      list = list.filter(o => _statusGroup(o.status) === _activeGroup);
    }
    if (_searchText) {
      list = list.filter(o =>
        (o.display_id || '').toLowerCase().includes(_searchText) ||
        (o.title || '').toLowerCase().includes(_searchText) ||
        (o.client_name || '').toLowerCase().includes(_searchText)
      );
    }
    return list;
  }

  function _statusGroup(status) {
    const s = (status || '').toLowerCase();
    if (['pending', 'new', 'submitted'].includes(s)) return 'new';
    if (['in_progress', 'accepted', 'started'].includes(s)) return 'in_progress';
    if (['completed', 'done', 'finished'].includes(s)) return 'completed';
    if (['cancelled', 'rejected', 'expired'].includes(s)) return 'cancelled';
    return 'new';
  }

  function _statusLabel(status) {
    const map = {
      new: 'جديد', pending: 'جديد', submitted: 'جديد',
      accepted: 'مقبول', in_progress: 'تحت التنفيذ', started: 'تحت التنفيذ',
      completed: 'مكتمل', done: 'مكتمل', finished: 'مكتمل',
      cancelled: 'ملغي', rejected: 'مرفوض', expired: 'منتهي',
    };
    return map[(status || '').toLowerCase()] || status;
  }

  function _statusColor(status) {
    const group = _statusGroup(status);
    return { new: '#2196F3', in_progress: '#FF9800', completed: '#4CAF50', cancelled: '#F44336' }[group] || '#999';
  }

  function _typeLabel(type) {
    return { normal: 'عادي', competitive: 'تنافسي', urgent: 'عاجل' }[(type || '').toLowerCase()] || type || '';
  }

  function _render() {
    const list = _getFiltered();
    const container = document.getElementById('po-list');
    const empty = document.getElementById('po-empty');
    container.innerHTML = '';
    if (!list.length) {
      empty.style.display = '';
      return;
    }
    empty.style.display = 'none';
    const frag = document.createDocumentFragment();
    list.forEach(o => frag.appendChild(_buildCard(o)));
    container.appendChild(frag);
  }

  function _buildCard(o) {
    const card = document.createElement('a');
    card.href = `/provider-orders/${o.id}/`;
    card.className = 'order-card';
    const color = _statusColor(o.status);
    card.innerHTML = `
      <div class="order-card-top">
        <span class="order-id">#${o.display_id || o.id}</span>
        <span class="order-type-badge">${_typeLabel(o.request_type)}</span>
        <span class="order-status" style="color:${color};border-color:${color}">${_statusLabel(o.status)}</span>
      </div>
      <div class="order-card-body">
        <h4>${UI.text(o.title || 'طلب بدون عنوان')}</h4>
        <p class="order-meta">${o.client_name || ''} ${o.category_name ? '• ' + o.category_name : ''}</p>
        <p class="order-date">${o.created_at ? new Date(o.created_at).toLocaleDateString('ar-SA') : ''}</p>
      </div>
    `;
    return card;
  }

  document.addEventListener('DOMContentLoaded', init);
  return { init };
})();
