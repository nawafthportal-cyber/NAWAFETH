/* ===================================================================
   notificationsPage.js — Notifications page controller
   GET  /api/notifications/
   POST /api/notifications/mark-read/<id>/
   POST /api/notifications/mark-all-read/
   POST /api/notifications/delete-old/
   GET  /api/notifications/unread-count/
   =================================================================== */
'use strict';

const NotificationsPage = (() => {
  let _notifications = [];
  let _hasMore = true;

  function init() {
    if (!Auth.isLoggedIn()) { _showGate(); return; }
    _hideGate();

    document.getElementById('btn-mark-all').addEventListener('click', _markAllRead);
    document.getElementById('btn-delete-old').addEventListener('click', _deleteOld);

    _fetchNotifications();
  }

  function _showGate() {
    const g = document.getElementById('auth-gate');
    const c = document.getElementById('notif-content');
    if (g) g.classList.remove('hidden');
    if (c) c.classList.add('hidden');
  }
  function _hideGate() {
    const g = document.getElementById('auth-gate');
    const c = document.getElementById('notif-content');
    if (g) g.classList.add('hidden');
    if (c) c.classList.remove('hidden');
  }

  async function _fetchNotifications() {
    const res = await ApiClient.get('/api/notifications/');
    if (res.ok && res.data) {
      const data = res.data;
      _notifications = data.results || data.notifications || (Array.isArray(data) ? data : []);
      _hasMore = !!data.next || !!data.has_more;
      const total = data.total_count || data.count || _notifications.length;
      const totalEl = document.getElementById('notif-total');
      if (totalEl && total) totalEl.textContent = total;
      _render();
    } else if (res.status === 401) {
      _showGate();
    }
  }

  function _render() {
    const container = document.getElementById('notif-list');
    const emptyEl = document.getElementById('notif-empty');
    container.innerHTML = '';

    if (!_notifications.length) {
      emptyEl.classList.remove('hidden');
      return;
    }
    emptyEl.classList.add('hidden');

    const frag = document.createDocumentFragment();
    _notifications.forEach((n, idx) => frag.appendChild(_buildCard(n, idx)));
    container.appendChild(frag);
  }

  function _buildCard(notif, index) {
    const isRead = notif.is_read;
    const isUrgent = notif.is_urgent;

    const card = UI.el('div', {
      className: 'notif-card' + (isRead ? ' read' : '') + (isUrgent ? ' urgent' : ''),
    });

    card.addEventListener('click', () => _markRead(notif.id, index));

    // Icon
    const iconWrap = UI.el('div', { className: 'notif-icon' });
    const iconName = _iconForKind(notif.kind || '');
    const color = _colorForKind(notif.kind || '');
    iconWrap.style.background = color + '15';
    iconWrap.appendChild(UI.icon(iconName, 22, color));
    card.appendChild(iconWrap);

    // Body
    const body = UI.el('div', { className: 'notif-body' });

    const headerRow = UI.el('div', { className: 'notif-header-row' });
    headerRow.appendChild(UI.el('span', { className: 'notif-title', textContent: notif.title || 'إشعار' }));
    if (!isRead) {
      headerRow.appendChild(UI.el('span', { className: 'notif-dot' }));
    }
    body.appendChild(headerRow);

    if (notif.body || notif.message) {
      body.appendChild(UI.el('div', { className: 'notif-text', textContent: notif.body || notif.message }));
    }

    if (notif.created_at || notif.created) {
      body.appendChild(UI.el('div', { className: 'notif-time', textContent: _relativeTime(notif.created_at || notif.created) }));
    }

    card.appendChild(body);
    return card;
  }

  function _iconForKind(kind) {
    if (kind.includes('request') || kind.includes('offer')) return 'category';
    if (kind.includes('message')) return 'campaign';
    if (kind.includes('urgent')) return 'fitness';
    return 'info';
  }

  function _colorForKind(kind) {
    if (kind.includes('urgent') || kind.includes('error')) return '#F44336';
    if (kind.includes('offer') || kind.includes('success')) return '#4CAF50';
    if (kind.includes('message')) return '#2196F3';
    if (kind.includes('warn')) return '#FF9800';
    return '#673AB7';
  }

  function _relativeTime(dateStr) {
    const now = new Date();
    const dt = new Date(dateStr);
    const diff = Math.floor((now - dt) / 1000);
    if (diff < 60) return 'الآن';
    if (diff < 3600) return 'منذ ' + Math.floor(diff / 60) + ' دقيقة';
    if (diff < 86400) return 'منذ ' + Math.floor(diff / 3600) + ' ساعة';
    if (diff < 604800) return 'منذ ' + Math.floor(diff / 86400) + ' يوم';
    return dt.toLocaleDateString('ar-SA', { day: 'numeric', month: 'short', year: 'numeric' });
  }

  async function _markRead(id, index) {
    if (_notifications[index] && _notifications[index].is_read) return;
    const res = await ApiClient.request('/api/notifications/mark-read/' + id + '/', { method: 'POST' });
    if (res.ok) {
      _notifications[index].is_read = true;
      _render();
      window.dispatchEvent(new Event('nw:badge-refresh'));
    }
  }

  async function _markAllRead() {
    const res = await ApiClient.request('/api/notifications/mark-all-read/', { method: 'POST' });
    if (res.ok) {
      _notifications.forEach(n => n.is_read = true);
      _render();
      window.dispatchEvent(new Event('nw:badge-refresh'));
    }
  }

  async function _deleteOld() {
    if (!confirm('هل أنت متأكد من حذف الإشعارات القديمة؟')) return;
    const res = await ApiClient.request('/api/notifications/delete-old/', { method: 'POST' });
    if (res.ok) {
      _fetchNotifications();
      window.dispatchEvent(new Event('nw:badge-refresh'));
    }
  }

  // Boot
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
  return {};
})();
