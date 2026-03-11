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
  let _loading = false;
  let _eventsBound = false;

  function init() {
    if (!Auth.isLoggedIn()) { _showGate(); return; }
    _hideGate();

    document.getElementById('btn-mark-all').addEventListener('click', _markAllRead);
    document.getElementById('btn-delete-old').addEventListener('click', _deleteOld);
    _bindEvents();

    _fetchNotifications();
  }

  function _activeMode() {
    try {
      const mode = (sessionStorage.getItem('nw_account_mode') || '').trim().toLowerCase();
      if (mode === 'provider' || mode === 'client') return mode;
    } catch (_) {}
    const role = (Auth.getRoleState() || '').trim().toLowerCase();
    return role === 'provider' ? 'provider' : 'client';
  }

  function _withMode(path) {
    const mode = _activeMode();
    if (!mode) return path;
    return path + (path.includes('?') ? '&' : '?') + 'mode=' + encodeURIComponent(mode);
  }

  function _matchesActiveMode(notif) {
    const audienceMode = String(notif?.audience_mode || 'shared').trim().toLowerCase();
    return audienceMode === 'shared' || audienceMode === _activeMode();
  }

  function _bindEvents() {
    if (_eventsBound) return;
    _eventsBound = true;
    window.addEventListener('nw:notification-created', _handleRealtimeNotification);
  }

  function _handleRealtimeNotification(event) {
    const notif = event?.detail || null;
    if (!notif || !_matchesActiveMode(notif)) return;
    const existingIndex = _notifications.findIndex((item) => item.id === notif.id);
    if (existingIndex >= 0) {
      _notifications.splice(existingIndex, 1);
    } else {
      _setText('notif-total', String((_notifications.length || 0) + 1));
    }
    _notifications.unshift(notif);
    _render();
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
    _setLoading(true);
    _setError('');
    const res = await ApiClient.get(_withMode('/api/notifications/'));
    _setLoading(false);
    if (res.ok && res.data) {
      const data = res.data;
      _notifications = data.results || data.notifications || (Array.isArray(data) ? data : []);
      _hasMore = !!data.next || !!data.has_more;
      const total = data.total_count || data.count || _notifications.length;
      _setText('notif-total', String(total));
      _render();
    } else if (res.status === 401) {
      _showGate();
    } else {
      _notifications = [];
      _render();
      _setError('تعذر تحميل الإشعارات حاليًا. حاول مرة أخرى بعد قليل.');
    }
  }

  function _render() {
    const container = document.getElementById('notif-list');
    const emptyEl = document.getElementById('notif-empty');
    if (!container || !emptyEl) return;
    container.innerHTML = '';

    if (!_notifications.length) {
      emptyEl.classList.remove('hidden');
      _refreshCounters();
      return;
    }
    emptyEl.classList.add('hidden');

    const frag = document.createDocumentFragment();
    _notifications.forEach((n, idx) => frag.appendChild(_buildCard(n, idx)));
    container.appendChild(frag);
    _refreshCounters();
  }

  function _buildCard(notif, index) {
    const isRead = notif.is_read;
    const isUrgent = notif.is_urgent;
    const kind = String(notif.kind || '').toLowerCase();

    const card = UI.el('div', {
      className: 'notif-card' + (isRead ? ' read' : ' unread') + (isUrgent ? ' urgent' : ''),
      role: 'button',
      tabindex: '0',
    });

    card.addEventListener('click', () => _markRead(notif.id, index));
    card.addEventListener('keydown', (ev) => {
      if (ev.key === 'Enter' || ev.key === ' ') {
        ev.preventDefault();
        _markRead(notif.id, index);
      }
    });

    // Icon
    const iconWrap = UI.el('div', { className: 'notif-icon' });
    const iconName = _iconForKind(kind);
    const color = _colorForKind(kind);
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
      const metaRow = UI.el('div', { className: 'notif-meta-row' });
      metaRow.appendChild(UI.el('div', { className: 'notif-time', textContent: _relativeTime(notif.created_at || notif.created) }));
      metaRow.appendChild(UI.el('div', { className: 'notif-open-hint', textContent: 'فتح' }));
      body.appendChild(metaRow);
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
    if (Number.isNaN(dt.getTime())) return '';
    const diff = Math.floor((now - dt) / 1000);
    if (diff < 60) return 'الآن';
    if (diff < 3600) return 'منذ ' + Math.floor(diff / 60) + ' دقيقة';
    if (diff < 86400) return 'منذ ' + Math.floor(diff / 3600) + ' ساعة';
    if (diff < 604800) return 'منذ ' + Math.floor(diff / 86400) + ' يوم';
    return dt.toLocaleDateString('ar-SA', { day: 'numeric', month: 'short', year: 'numeric' });
  }

  async function _markRead(id, index) {
    if (!id) return;
    if (_notifications[index] && _notifications[index].is_read) return;
    const res = await ApiClient.request(_withMode('/api/notifications/mark-read/' + id + '/'), { method: 'POST' });
    if (res.ok) {
      _notifications[index].is_read = true;
      _render();
      window.dispatchEvent(new Event('nw:badge-refresh'));
    }
  }

  async function _markAllRead() {
    if (_loading) return;
    const res = await ApiClient.request(_withMode('/api/notifications/mark-all-read/'), { method: 'POST' });
    if (res.ok) {
      _notifications.forEach(n => n.is_read = true);
      _render();
      window.dispatchEvent(new Event('nw:badge-refresh'));
    }
  }

  async function _deleteOld() {
    if (!confirm('هل أنت متأكد من حذف الإشعارات القديمة؟')) return;
    if (_loading) return;
    _setLoading(true);
    const res = await ApiClient.request(_withMode('/api/notifications/delete-old/'), { method: 'POST' });
    _setLoading(false);
    if (res.ok) {
      _fetchNotifications();
      window.dispatchEvent(new Event('nw:badge-refresh'));
    } else {
      _setError('تعذر حذف الإشعارات القديمة في الوقت الحالي.');
    }
  }

  function _refreshCounters() {
    const total = _notifications.length;
    const unread = _notifications.filter((n) => !n.is_read).length;
    _setText('notif-total', String(total));

    const unreadEl = document.getElementById('notif-unread');
    if (!unreadEl) return;
    unreadEl.textContent = String(unread) + ' غير مقروء';
    unreadEl.classList.toggle('hidden', unread <= 0);
  }

  function _setLoading(v) {
    _loading = !!v;
    const loader = document.getElementById('notif-loader');
    if (loader) loader.classList.toggle('hidden', !v);

    const markAll = document.getElementById('btn-mark-all');
    const deleteOld = document.getElementById('btn-delete-old');
    if (markAll) markAll.disabled = _loading;
    if (deleteOld) deleteOld.disabled = _loading;
  }

  function _setError(message) {
    const errorEl = document.getElementById('notif-error');
    if (!errorEl) return;
    if (!message) {
      errorEl.textContent = '';
      errorEl.classList.add('hidden');
      return;
    }
    errorEl.textContent = message;
    errorEl.classList.remove('hidden');
  }

  function _setText(id, value) {
    const el = document.getElementById(id);
    if (el) el.textContent = value;
  }

  // Boot
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
  return {};
})();
