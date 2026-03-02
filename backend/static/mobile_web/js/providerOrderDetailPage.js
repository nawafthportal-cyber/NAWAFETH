/* ===================================================================
   providerOrderDetailPage.js — Provider Order Detail
   1:1 parity with Flutter provider_order_details_screen.dart
   =================================================================== */
'use strict';

const ProviderOrderDetailPage = (() => {
  let _order = null;
  let _orderId = null;

  function init() {
    if (!Auth.isLoggedIn()) {
      document.getElementById('auth-gate').style.display = '';
      return;
    }
    document.getElementById('pod-content').style.display = '';
    // Parse ID from URL: /provider-orders/123/
    const m = location.pathname.match(/provider-orders\/(\d+)/);
    if (!m) { _showError('رابط غير صحيح'); return; }
    _orderId = m[1];
    _loadDetail();
  }

  async function _loadDetail() {
    document.getElementById('pod-loading').style.display = '';
    const res = await ApiClient.get(`/api/marketplace/provider/requests/${_orderId}/detail/`);
    document.getElementById('pod-loading').style.display = 'none';
    if (!res.ok) {
      // Fallback: try without /detail/
      const res2 = await ApiClient.get(`/api/marketplace/provider/requests/${_orderId}/`);
      if (!res2.ok) { _showError('تعذر تحميل الطلب'); return; }
      _order = res2.data;
    } else {
      _order = res.data;
    }
    _render();
  }

  function _render() {
    const o = _order;
    document.getElementById('pod-detail').style.display = '';

    // Client info
    document.getElementById('pod-client-name').textContent = o.client_name || o.client?.full_name || '—';
    document.getElementById('pod-client-phone').textContent = o.client_phone || o.client?.phone || '—';
    document.getElementById('pod-client-city').textContent = o.client_city || o.client?.city || '—';

    // Header
    document.getElementById('pod-display-id').textContent = `#${o.display_id || o.id}`;
    const typeBadge = document.getElementById('pod-type');
    const typeMap = { normal: 'عادي', competitive: 'تنافسي', urgent: 'عاجل' };
    typeBadge.textContent = typeMap[(o.request_type || '').toLowerCase()] || o.request_type || '';

    const statusEl = document.getElementById('pod-status');
    statusEl.textContent = _statusLabel(o.status);
    statusEl.style.color = _statusColor(o.status);
    statusEl.style.borderColor = _statusColor(o.status);

    document.getElementById('pod-category').textContent = o.category_name || o.category?.name || '—';
    document.getElementById('pod-date').textContent = o.created_at ? new Date(o.created_at).toLocaleDateString('ar-SA') : '—';
    document.getElementById('pod-title').textContent = o.title || '—';
    document.getElementById('pod-description').textContent = o.description || '—';

    // Attachments
    const attachments = o.attachments || [];
    if (attachments.length) {
      document.getElementById('pod-attachments-section').style.display = '';
      const container = document.getElementById('pod-attachments');
      container.innerHTML = '';
      attachments.forEach(a => {
        const link = document.createElement('a');
        link.href = ApiClient.mediaUrl(a.file || a.file_url || a.url);
        link.target = '_blank';
        link.className = 'attachment-link';
        link.textContent = a.original_name || a.name || 'مرفق';
        container.appendChild(link);
      });
    }

    // Status logs
    const logs = o.status_logs || o.logs || [];
    if (logs.length) {
      document.getElementById('pod-logs-section').style.display = '';
      const container = document.getElementById('pod-logs');
      container.innerHTML = '';
      logs.forEach(log => {
        const item = document.createElement('div');
        item.className = 'timeline-item';
        item.innerHTML = `
          <span class="timeline-dot" style="background:${_statusColor(log.status || log.new_status)}"></span>
          <div class="timeline-body">
            <strong>${_statusLabel(log.status || log.new_status)}</strong>
            <span>${log.created_at ? new Date(log.created_at).toLocaleDateString('ar-SA') : ''}</span>
            ${log.note ? `<p>${UI.text(log.note)}</p>` : ''}
          </div>
        `;
        container.appendChild(item);
      });
    }

    _renderActions(o);
  }

  function _renderActions(o) {
    const actions = document.getElementById('pod-actions');
    const group = _statusGroup(o.status);
    actions.style.display = '';

    if (group === 'new') {
      document.getElementById('action-new').style.display = '';
      document.getElementById('btn-accept').onclick = _accept;
      document.getElementById('btn-start').onclick = _start;
      document.getElementById('btn-reject-new').onclick = () => _showRejectForm();
    } else if (group === 'in_progress') {
      document.getElementById('action-progress').style.display = '';
      document.getElementById('btn-update-progress').onclick = _updateProgress;
      document.getElementById('btn-complete').onclick = _complete;
      document.getElementById('btn-reject-progress').onclick = () => _showRejectForm();
    } else if (group === 'completed') {
      document.getElementById('action-completed').style.display = '';
      document.getElementById('completed-date').textContent = o.actual_delivery_date || o.completed_at || '—';
      document.getElementById('completed-amount').textContent = o.actual_amount ? `${o.actual_amount} ر.س` : '—';
    } else if (group === 'cancelled') {
      document.getElementById('action-cancelled').style.display = '';
      document.getElementById('cancelled-date').textContent = o.cancelled_at || '—';
      document.getElementById('cancelled-reason').textContent = o.cancel_reason || o.rejection_reason || '—';
    }

    // Reject form
    document.getElementById('btn-confirm-reject').onclick = _reject;
    document.getElementById('btn-cancel-reject').onclick = () => {
      document.getElementById('reject-form').style.display = 'none';
    };
  }

  async function _accept() {
    const res = await ApiClient.request(`/api/marketplace/provider/requests/${_orderId}/accept/`, { method: 'POST' });
    if (res.ok) {
      document.getElementById('start-form').style.display = '';
      document.getElementById('btn-accept').style.display = 'none';
    } else {
      alert(res.data?.detail || 'فشل القبول');
    }
  }

  async function _start() {
    const body = {};
    const d = document.getElementById('start-delivery-date').value;
    const a = document.getElementById('start-amount').value;
    const r = document.getElementById('start-received').value;
    const n = document.getElementById('start-note').value;
    if (d) body.expected_delivery_date = d;
    if (a) body.estimated_amount = parseFloat(a);
    if (r) body.received_amount = parseFloat(r);
    if (n) body.note = n;
    const res = await ApiClient.request(`/api/marketplace/requests/${_orderId}/start/`, { method: 'POST', body });
    if (res.ok) location.reload();
    else alert(res.data?.detail || 'فشل بدء التنفيذ');
  }

  async function _updateProgress() {
    const note = document.getElementById('progress-note').value.trim();
    if (!note) { alert('أضف ملاحظة'); return; }
    const res = await ApiClient.request(`/api/marketplace/provider/requests/${_orderId}/progress-update/`, {
      method: 'POST', body: { note }
    });
    if (res.ok) {
      document.getElementById('progress-note').value = '';
      _loadDetail();
    } else {
      alert(res.data?.detail || 'فشل التحديث');
    }
  }

  async function _complete() {
    const body = {};
    const d = document.getElementById('complete-date').value;
    const a = document.getElementById('complete-amount').value;
    if (d) body.actual_delivery_date = d;
    if (a) body.actual_amount = parseFloat(a);
    const res = await ApiClient.request(`/api/marketplace/requests/${_orderId}/complete/`, { method: 'POST', body });
    if (res.ok) location.reload();
    else alert(res.data?.detail || 'فشل الإكمال');
  }

  function _showRejectForm() {
    document.getElementById('reject-form').style.display = '';
  }

  async function _reject() {
    const reason = document.getElementById('reject-reason').value.trim();
    const res = await ApiClient.request(`/api/marketplace/provider/requests/${_orderId}/reject/`, {
      method: 'POST', body: { reason }
    });
    if (res.ok) location.reload();
    else alert(res.data?.detail || 'فشل الرفض');
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
      new: 'جديد', pending: 'جديد', submitted: 'جديد', accepted: 'مقبول',
      in_progress: 'تحت التنفيذ', started: 'تحت التنفيذ',
      completed: 'مكتمل', done: 'مكتمل',
      cancelled: 'ملغي', rejected: 'مرفوض', expired: 'منتهي',
    };
    return map[(status || '').toLowerCase()] || status;
  }

  function _statusColor(status) {
    const group = _statusGroup(status);
    return { new: '#2196F3', in_progress: '#FF9800', completed: '#4CAF50', cancelled: '#F44336' }[group] || '#999';
  }

  function _showError(msg) {
    const el = document.getElementById('pod-error');
    el.textContent = msg;
    el.style.display = '';
    document.getElementById('pod-loading').style.display = 'none';
  }

  document.addEventListener('DOMContentLoaded', init);
  return { init };
})();
