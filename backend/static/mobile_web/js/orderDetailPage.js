/* ===================================================================
   orderDetailPage.js — Client order details
   GET/PATCH /api/marketplace/client/requests/<id>/
   =================================================================== */
'use strict';

const OrderDetailPage = (() => {
  let _requestId = null;
  let _order = null;
  let _editTitle = false;
  let _editDesc = false;

  function init() {
    _requestId = _parseRequestId();
    if (!_requestId) {
      _setError('تعذر تحديد رقم الطلب');
      return;
    }

    if (!Auth.isLoggedIn()) {
      _showGate();
      return;
    }
    _hideGate();
    _bindActions();
    _loadDetail();
  }

  function _parseRequestId() {
    const m = window.location.pathname.match(/\/orders\/(\d+)\/?$/);
    if (!m) return null;
    return Number(m[1]);
  }

  function _showGate() {
    const gate = document.getElementById('auth-gate');
    const content = document.getElementById('order-content');
    const loginLink = document.getElementById('order-login-link');
    if (gate) gate.classList.remove('hidden');
    if (content) content.classList.add('hidden');
    if (loginLink) {
      loginLink.href = '/login/?next=' + encodeURIComponent(window.location.pathname);
    }
  }

  function _hideGate() {
    const gate = document.getElementById('auth-gate');
    const content = document.getElementById('order-content');
    if (gate) gate.classList.add('hidden');
    if (content) content.classList.remove('hidden');
  }

  function _bindActions() {
    const tBtn = document.getElementById('btn-toggle-title');
    const dBtn = document.getElementById('btn-toggle-desc');
    const sBtn = document.getElementById('btn-save-order');
    if (tBtn) {
      tBtn.addEventListener('click', () => {
        _editTitle = !_editTitle;
        _applyEditableState();
      });
    }
    if (dBtn) {
      dBtn.addEventListener('click', () => {
        _editDesc = !_editDesc;
        _applyEditableState();
      });
    }
    if (sBtn) sBtn.addEventListener('click', _save);
  }

  async function _loadDetail() {
    _setLoading(true);
    _setError('');
    const res = await ApiClient.get('/api/marketplace/client/requests/' + _requestId + '/');
    _setLoading(false);

    if (!res.ok || !res.data) {
      _setError((res.data && res.data.detail) || 'تعذر تحميل تفاصيل الطلب');
      return;
    }

    _order = res.data;
    _render();
  }

  function _setLoading(loading) {
    const loadingEl = document.getElementById('order-loading');
    if (loadingEl) loadingEl.classList.toggle('hidden', !loading);
    if (loading) {
      const detail = document.getElementById('order-detail');
      if (detail) detail.classList.add('hidden');
    }
  }

  function _setError(message) {
    const err = document.getElementById('order-error');
    if (!err) return;
    if (!message) {
      err.textContent = '';
      err.classList.add('hidden');
      return;
    }
    err.textContent = message;
    err.classList.remove('hidden');
  }

  function _statusColor(group) {
    switch (String(group || '').toLowerCase()) {
      case 'new':
        return '#F59E0B';
      case 'in_progress':
        return '#2563EB';
      case 'completed':
        return '#16A34A';
      case 'cancelled':
        return '#DC2626';
      default:
        return '#6B7280';
    }
  }

  function _render() {
    if (!_order) return;

    const detail = document.getElementById('order-detail');
    if (detail) detail.classList.remove('hidden');

    const displayId = document.getElementById('order-display-id');
    if (displayId) {
      const id = _order.id || _requestId;
      displayId.textContent = 'R' + String(id).padStart(6, '0');
    }

    const statusBadge = document.getElementById('order-status-badge');
    if (statusBadge) {
      const color = _statusColor(_order.status_group || _order.status);
      statusBadge.textContent = _order.status_label || _order.status_group || _order.status || 'غير محدد';
      statusBadge.style.color = color;
      statusBadge.style.borderColor = color;
      statusBadge.style.backgroundColor = color + '1A';
    }

    const meta = document.getElementById('order-meta');
    if (meta) {
      meta.innerHTML = '';
      const lines = [];
      if (_order.created_at) lines.push('تاريخ الإنشاء: ' + _formatDate(_order.created_at));
      if (_order.request_type) lines.push('نوع الطلب: ' + _requestTypeLabel(_order.request_type));
      if (_order.category_name || _order.subcategory_name) {
        lines.push(
          'التصنيف: ' + (_order.category_name || '-') + ((_order.subcategory_name) ? (' / ' + _order.subcategory_name) : ''),
        );
      }
      if (_order.provider_name) lines.push('مقدم الخدمة: ' + _order.provider_name);
      if (_order.provider_phone) lines.push('رقم مقدم الخدمة: ' + _order.provider_phone);
      if (_order.city) lines.push('المدينة: ' + _order.city);
      lines.forEach((line) => {
        meta.appendChild(UI.el('div', { className: 'order-meta-line', textContent: line }));
      });
    }

    const titleInput = document.getElementById('order-title');
    const descInput = document.getElementById('order-description');
    if (titleInput) titleInput.value = _order.title || '';
    if (descInput) descInput.value = _order.description || '';

    _renderAttachments(_order.attachments || []);
    _renderStatusLogs(_order.status_logs || []);

    _editTitle = false;
    _editDesc = false;
    _applyEditableState();
  }

  function _renderAttachments(items) {
    const root = document.getElementById('order-attachments');
    if (!root) return;
    root.innerHTML = '';
    if (!Array.isArray(items) || !items.length) {
      root.appendChild(UI.el('p', { className: 'ticket-muted', textContent: 'لا يوجد مرفقات' }));
      return;
    }

    items.forEach((item) => {
      const href = ApiClient.mediaUrl(item.file_url || item.file || '');
      const name = String((item.file_url || item.file || '')).split('/').pop() || 'ملف';
      const line = UI.el('a', {
        className: 'order-line-link',
        href: href,
        target: '_blank',
        rel: 'noopener',
      });
      line.appendChild(UI.el('span', { textContent: name }));
      line.appendChild(UI.el('span', { className: 'order-line-type', textContent: String(item.file_type || '').toUpperCase() }));
      root.appendChild(line);
    });
  }

  function _renderStatusLogs(items) {
    const root = document.getElementById('order-status-logs');
    if (!root) return;
    root.innerHTML = '';
    if (!Array.isArray(items) || !items.length) {
      root.appendChild(UI.el('p', { className: 'ticket-muted', textContent: 'لا يوجد سجل حالة' }));
      return;
    }

    items.forEach((log) => {
      const row = UI.el('div', { className: 'order-log-row' });
      row.appendChild(UI.el('div', { className: 'order-log-title', textContent: (log.from_status || '—') + ' → ' + (log.to_status || '—') }));
      if (log.note) row.appendChild(UI.el('div', { className: 'order-log-note', textContent: log.note }));
      if (log.created_at) row.appendChild(UI.el('div', { className: 'order-log-time', textContent: _formatDate(log.created_at) }));
      root.appendChild(row);
    });
  }

  function _requestTypeLabel(type) {
    const t = String(type || '').toLowerCase();
    if (t === 'urgent') return 'عاجل';
    if (t === 'competitive') return 'تنافسي';
    if (t === 'normal') return 'عادي';
    return type || '';
  }

  function _formatDate(value) {
    const dt = new Date(value);
    if (Number.isNaN(dt.getTime())) return '';
    return dt.toLocaleString('ar-SA', {
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
    });
  }

  function _canEdit() {
    return String(_order && _order.status || '').toLowerCase() === 'new';
  }

  function _applyEditableState() {
    const canEdit = _canEdit();
    const titleInput = document.getElementById('order-title');
    const descInput = document.getElementById('order-description');
    const tBtn = document.getElementById('btn-toggle-title');
    const dBtn = document.getElementById('btn-toggle-desc');
    const saveBtn = document.getElementById('btn-save-order');

    if (titleInput) titleInput.disabled = !(canEdit && _editTitle);
    if (descInput) descInput.disabled = !(canEdit && _editDesc);
    if (tBtn) {
      tBtn.classList.toggle('hidden', !canEdit);
      tBtn.textContent = _editTitle ? 'إيقاف' : 'تعديل';
    }
    if (dBtn) {
      dBtn.classList.toggle('hidden', !canEdit);
      dBtn.textContent = _editDesc ? 'إيقاف' : 'تعديل';
    }
    if (saveBtn) saveBtn.classList.toggle('hidden', !canEdit);
  }

  async function _save() {
    if (!_order || !_canEdit()) return;
    const titleInput = document.getElementById('order-title');
    const descInput = document.getElementById('order-description');
    if (!titleInput || !descInput) return;

    const newTitle = String(titleInput.value || '').trim();
    const newDesc = String(descInput.value || '').trim();
    if (!newTitle || !newDesc) {
      _setError('العنوان والتفاصيل مطلوبان');
      return;
    }

    const patchBody = {};
    if (newTitle !== String(_order.title || '')) patchBody.title = newTitle;
    if (newDesc !== String(_order.description || '')) patchBody.description = newDesc;
    if (!Object.keys(patchBody).length) return;

    _setSaveLoading(true);
    const res = await ApiClient.request('/api/marketplace/client/requests/' + _requestId + '/', {
      method: 'PATCH',
      body: patchBody,
    });
    _setSaveLoading(false);

    if (!res.ok || !res.data) {
      _setError((res.data && res.data.detail) || 'فشل حفظ التعديلات');
      return;
    }

    _setError('');
    _order = res.data;
    _render();
  }

  function _setSaveLoading(loading) {
    const btn = document.getElementById('btn-save-order');
    const txt = document.getElementById('save-order-text');
    const spinner = document.getElementById('save-order-spinner');
    if (btn) btn.disabled = loading;
    if (txt) txt.classList.toggle('hidden', loading);
    if (spinner) spinner.classList.toggle('hidden', !loading);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  return {};
})();
