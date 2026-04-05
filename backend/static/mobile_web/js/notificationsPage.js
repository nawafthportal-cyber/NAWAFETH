/* ===================================================================
   notificationsPage.js — Notifications page controller
   GET    /api/notifications/?limit=20&offset=0&mode=client|provider
   POST   /api/notifications/mark-read/<id>/
   POST   /api/notifications/mark-all-read/
   POST   /api/notifications/delete-old/
   POST   /api/notifications/actions/<id>/   { action: pin | follow_up }
   DELETE /api/notifications/actions/<id>/
   =================================================================== */
'use strict';

const NotificationsPage = (() => {
  const PAGE_LIMIT = 20;

  let _notifications = [];
  let _totalCount = 0;
  let _offset = 0;
  let _hasMore = true;
  let _loading = false;
  let _loadingMore = false;
  let _eventsBound = false;
  let _scrollBound = false;
  let _toastTimer = null;

  function init() {
    if (!Auth.isLoggedIn()) {
      _showGate();
      return;
    }
    _hideGate();

    const markAllBtn = document.getElementById('btn-mark-all');
    const deleteOldBtn = document.getElementById('btn-delete-old');
    const loadMoreBtn = document.getElementById('notif-load-more');
    const retryBtn = document.getElementById('notif-retry');

    if (markAllBtn) markAllBtn.addEventListener('click', _markAllRead);
    if (deleteOldBtn) deleteOldBtn.addEventListener('click', _deleteOld);
    if (loadMoreBtn) {
      loadMoreBtn.addEventListener('click', () => _fetchNotifications({ reset: false }));
    }
    if (retryBtn) {
      retryBtn.addEventListener('click', () => _fetchNotifications({ reset: true }));
    }

    _bindEvents();
    _fetchNotifications({ reset: true });
  }

  function _activeMode() {
    try {
      const params = new URLSearchParams(window.location.search || '');
      const modeFromUrl = (params.get('mode') || '').trim().toLowerCase();
      if (modeFromUrl === 'provider' || modeFromUrl === 'client') {
        sessionStorage.setItem('nw_account_mode', modeFromUrl);
        return modeFromUrl;
      }
    } catch (_) {}
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
    const audienceMode = String((notif && notif.audience_mode) || 'shared').trim().toLowerCase();
    return audienceMode === 'shared' || audienceMode === _activeMode();
  }

  function _bindEvents() {
    if (_eventsBound) return;
    _eventsBound = true;

    window.addEventListener('nw:notification-created', _handleRealtimeNotification);
    document.addEventListener('click', _closeAllMenus);

    if (!_scrollBound) {
      _scrollBound = true;
      window.addEventListener('scroll', _onScroll, { passive: true });
    }
  }

  function _onScroll() {
    if (_loading || _loadingMore || !_hasMore) return;
    const doc = document.documentElement;
    const nearBottom = (window.innerHeight + window.scrollY) >= (doc.scrollHeight - 220);
    if (nearBottom) _fetchNotifications({ reset: false });
  }

  function _handleRealtimeNotification(event) {
    const notif = event && event.detail ? event.detail : null;
    if (!notif || !_matchesActiveMode(notif)) return;

    const existingIndex = _findIndexById(notif.id);
    if (existingIndex >= 0) {
      _notifications.splice(existingIndex, 1);
    } else {
      _totalCount += 1;
    }
    _notifications.unshift(notif);
    _offset = _notifications.length;

    _render();
  }

  function _appendUniqueNotifications(list) {
    if (!Array.isArray(list) || !list.length) return;
    const known = new Set(_notifications.map((item) => String(item.id)));
    list.forEach((item) => {
      const key = String(item && item.id);
      if (!key || known.has(key)) return;
      known.add(key);
      _notifications.push(item);
    });
  }

  async function _fetchNotifications(options) {
    const reset = !options || options.reset !== false;
    if (reset) {
      if (_loading) return;
      _setLoading(true);
      _setError('', { retry: false });
      _offset = 0;
      _hasMore = true;
    } else {
      if (_loading || _loadingMore || !_hasMore) return;
      _setLoadingMore(true);
    }

    const requestOffset = reset ? 0 : _offset;
    const url = _withMode('/api/notifications/?limit=' + PAGE_LIMIT + '&offset=' + requestOffset);
    const res = await ApiClient.get(url);

    if (reset) _setLoading(false);
    else _setLoadingMore(false);

    if (res.ok && res.data) {
      const data = res.data;
      const rows = Array.isArray(data) ? data : (data.results || data.notifications || []);

      if (reset) {
        _notifications = Array.isArray(rows) ? rows.slice() : [];
      } else {
        _appendUniqueNotifications(rows);
      }

      let total = 0;
      if (!Array.isArray(data) && typeof data.count === 'number') total = data.count;
      else if (!Array.isArray(data) && typeof data.total_count === 'number') total = data.total_count;
      else total = Math.max(_totalCount, _notifications.length);

      _totalCount = Math.max(0, _safeInt(total));
      _offset = _notifications.length;

      const hasMoreByApi = !Array.isArray(data) && (Boolean(data.next) || Boolean(data.has_more));
      _hasMore = hasMoreByApi || (_offset < _totalCount);

      _render();
      return;
    }

    if (res.status === 401) {
      _showGate();
      return;
    }

    if (reset && !_notifications.length) {
      _notifications = [];
      _totalCount = 0;
      _offset = 0;
      _hasMore = false;
      _render();
    }

    _setError('تعذر تحميل الإشعارات حاليًا. حاول مرة أخرى بعد قليل.', { retry: reset });
  }

  function _render() {
    const container = document.getElementById('notif-list');
    const emptyEl = document.getElementById('notif-empty');
    if (!container || !emptyEl) return;

    _closeAllMenus();
    container.innerHTML = '';

    if (!_notifications.length) {
      emptyEl.classList.remove('hidden');
      _refreshCounters();
      _updateLoadMoreUi();
      return;
    }

    emptyEl.classList.add('hidden');

    const frag = document.createDocumentFragment();
    _notifications.forEach((notif) => frag.appendChild(_buildCard(notif)));
    container.appendChild(frag);

    _refreshCounters();
    _updateLoadMoreUi();
  }

  function _buildCard(notif) {
    const isRead = !!notif.is_read;
    const isUrgent = !!notif.is_urgent;
    const isFollowUp = !!notif.is_follow_up;
    const isPinned = !!notif.is_pinned;
    const kind = String(notif.kind || '').toLowerCase();

    const card = UI.el('div', {
      className:
        'notif-card' +
        (isRead ? ' read' : ' unread') +
        (isUrgent ? ' urgent' : '') +
        (isFollowUp ? ' follow-up' : '') +
        (isPinned ? ' pinned' : ''),
      role: 'button',
      tabindex: '0',
    });

    card.addEventListener('click', () => _openNotification(notif));
    card.addEventListener('keydown', (event) => {
      if (event.key !== 'Enter' && event.key !== ' ') return;
      event.preventDefault();
      _openNotification(notif);
    });

    const iconWrap = UI.el('div', { className: 'notif-icon' });
    const iconName = _iconForKind(kind);
    const iconColor = isUrgent ? '#FFFFFF' : _colorForKind(kind);
    iconWrap.style.background = isUrgent ? 'rgba(255, 255, 255, 0.14)' : iconColor + '15';
    if (isUrgent) iconWrap.style.borderColor = 'rgba(255, 255, 255, 0.3)';
    iconWrap.appendChild(UI.icon(iconName, 22, iconColor));
    card.appendChild(iconWrap);

    const body = UI.el('div', { className: 'notif-body' });

    const headerRow = UI.el('div', { className: 'notif-header-row' });

    const titleWrap = UI.el('div', { className: 'notif-title-wrap' });
    titleWrap.appendChild(UI.el('span', { className: 'notif-title', textContent: notif.title || 'إشعار' }));

    const flagsWrap = UI.el('div', { className: 'notif-flags' });
    if (isFollowUp) flagsWrap.appendChild(UI.el('span', { className: 'notif-flag follow', textContent: 'متابعة' }));
    if (isPinned) flagsWrap.appendChild(UI.el('span', { className: 'notif-flag pin', textContent: 'مثبت' }));
    if (!isRead) flagsWrap.appendChild(UI.el('span', { className: 'notif-dot' }));
    if (flagsWrap.childNodes.length) titleWrap.appendChild(flagsWrap);

    headerRow.appendChild(titleWrap);
    headerRow.appendChild(_buildCardActions(notif));

    body.appendChild(headerRow);

    if (notif.body || notif.message) {
      body.appendChild(UI.el('div', { className: 'notif-text', textContent: notif.body || notif.message }));
    }

    if (notif.created_at || notif.created) {
      const metaRow = UI.el('div', { className: 'notif-meta-row' });
      metaRow.appendChild(
        UI.el('div', {
          className: 'notif-time',
          textContent: _relativeTime(notif.created_at || notif.created),
        })
      );
      metaRow.appendChild(UI.el('div', { className: 'notif-open-hint', textContent: isRead ? 'مقروء' : 'جديد' }));
      body.appendChild(metaRow);
    }

    card.appendChild(body);
    return card;
  }

  function _buildCardActions(notif) {
    const wrap = UI.el('div', { className: 'notif-card-actions' });

    const menuBtn = UI.el('button', {
      type: 'button',
      className: 'notif-menu-btn',
      title: 'خيارات',
      ariaLabel: 'خيارات الإشعار',
    });
    menuBtn.innerHTML = [
      '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">',
      '<circle cx="12" cy="5" r="1.4"></circle>',
      '<circle cx="12" cy="12" r="1.4"></circle>',
      '<circle cx="12" cy="19" r="1.4"></circle>',
      '</svg>',
    ].join('');
    menuBtn.addEventListener('click', (event) => {
      event.preventDefault();
      event.stopPropagation();
      _toggleMenu(menu);
    });

    const menu = UI.el('div', { className: 'notif-menu hidden' });
    menu.addEventListener('click', (event) => event.stopPropagation());

    if (!notif.is_read) {
      menu.appendChild(
        _buildMenuItem('تمييز كمقروء', async () => {
          await _markRead(notif.id);
        })
      );
    }

    menu.appendChild(
      _buildMenuItem(notif.is_follow_up ? 'إزالة التمييز' : 'تمييز مهم للمتابعة', async () => {
        await _toggleFollowUp(notif.id);
      })
    );

    menu.appendChild(
      _buildMenuItem(notif.is_pinned ? 'إلغاء التثبيت' : 'تثبيت بالأعلى', async () => {
        await _togglePin(notif.id);
      })
    );

    menu.appendChild(
      _buildMenuItem(
        'حذف',
        async () => {
          await _deleteNotification(notif.id);
        },
        true
      )
    );

    wrap.appendChild(menuBtn);
    wrap.appendChild(menu);
    return wrap;
  }

  function _buildMenuItem(label, onClick, isDanger) {
    const item = UI.el('button', {
      type: 'button',
      className: 'notif-menu-item' + (isDanger ? ' danger' : ''),
      textContent: label,
    });

    item.addEventListener('click', async (event) => {
      event.preventDefault();
      event.stopPropagation();
      _closeAllMenus();
      await onClick();
    });

    return item;
  }

  function _toggleMenu(menu) {
    if (!menu) return;
    const wasOpen = menu.classList.contains('open');
    _closeAllMenus();
    if (wasOpen) return;
    menu.classList.remove('hidden');
    requestAnimationFrame(() => {
      menu.classList.add('open');
    });
  }

  function _closeAllMenus() {
    document.querySelectorAll('.notif-menu').forEach((menu) => {
      menu.classList.remove('open');
      menu.classList.add('hidden');
    });
  }

  function _findIndexById(id) {
    const target = String(id);
    return _notifications.findIndex((item) => String(item.id) === target);
  }

  function _withModeOnNavigation(targetUrl) {
    const raw = String(targetUrl || '').trim();
    if (!raw) return '';
    if (/^https?:\/\//i.test(raw)) return raw;
    return _withMode(raw);
  }

  async function _openNotification(notif) {
    if (!notif) return;
    if (notif.id) await _markRead(notif.id);
    const targetUrl = _withModeOnNavigation(notif.url || '');
    if (!targetUrl) return;
    window.location.href = targetUrl;
  }

  async function _markRead(id) {
    if (!id) return false;
    const index = _findIndexById(id);
    if (index < 0) return false;
    if (_notifications[index].is_read) return true;

    const res = await ApiClient.request(_withMode('/api/notifications/mark-read/' + id + '/'), { method: 'POST' });
    if (!res.ok) return false;

    _notifications[index].is_read = true;
    _render();
    window.dispatchEvent(new Event('nw:badge-refresh'));
    return true;
  }

  async function _togglePin(id) {
    if (!id) return;
    const index = _findIndexById(id);
    if (index < 0) return;

    const res = await ApiClient.request(_withMode('/api/notifications/actions/' + id + '/'), {
      method: 'POST',
      body: { action: 'pin' },
    });

    if (!res.ok) {
      _showToast('تعذر تحديث حالة التثبيت', 'error');
      return;
    }

    const fallback = !_notifications[index].is_pinned;
    const nextValue = res.data && typeof res.data.is_pinned === 'boolean'
      ? !!res.data.is_pinned
      : fallback;

    _notifications[index].is_pinned = nextValue;
    _render();
  }

  async function _toggleFollowUp(id) {
    if (!id) return;
    const index = _findIndexById(id);
    if (index < 0) return;

    const res = await ApiClient.request(_withMode('/api/notifications/actions/' + id + '/'), {
      method: 'POST',
      body: { action: 'follow_up' },
    });

    if (!res.ok) {
      _showToast('تعذر تحديث حالة المتابعة', 'error');
      return;
    }

    const fallback = !_notifications[index].is_follow_up;
    const nextValue = res.data && typeof res.data.is_follow_up === 'boolean'
      ? !!res.data.is_follow_up
      : fallback;

    _notifications[index].is_follow_up = nextValue;
    _render();
  }

  async function _deleteNotification(id) {
    if (!id) return;
    const index = _findIndexById(id);
    if (index < 0) return;

    const res = await ApiClient.request(_withMode('/api/notifications/actions/' + id + '/'), {
      method: 'DELETE',
    });

    if (!res.ok) {
      _showToast('تعذر حذف الإشعار', 'error');
      return;
    }

    _notifications.splice(index, 1);
    _totalCount = Math.max(0, _totalCount - 1);
    _offset = _notifications.length;
    _hasMore = _offset < _totalCount;
    _render();
    window.dispatchEvent(new Event('nw:badge-refresh'));
  }

  async function _markAllRead() {
    if (_loading || _loadingMore) return;

    const res = await ApiClient.request(_withMode('/api/notifications/mark-all-read/'), { method: 'POST' });
    if (!res.ok) {
      _showToast('تعذر تنفيذ العملية', 'error');
      return;
    }

    _notifications.forEach((notif) => {
      notif.is_read = true;
    });
    _render();
    window.dispatchEvent(new Event('nw:badge-refresh'));
    _showToast('تم تمييز الكل كمقروء', 'success');
  }

  async function _deleteOld() {
    if (_loading || _loadingMore) return;

    _setLoading(true);
    const res = await ApiClient.request(_withMode('/api/notifications/delete-old/'), { method: 'POST' });
    _setLoading(false);

    if (!res.ok) {
      _setError('تعذر حذف الإشعارات القديمة في الوقت الحالي.', { retry: false });
      return;
    }

    const deleted = _safeInt(res.data && res.data.deleted);
    const retentionDays = Math.max(1, _safeInt(res.data && res.data.retention_days) || 90);

    _showToast('تم حذف ' + deleted + ' إشعار قديم (أقدم من ' + retentionDays + ' يوم)', 'success');
    window.dispatchEvent(new Event('nw:badge-refresh'));
    _fetchNotifications({ reset: true });
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

  function _refreshCounters() {
    const total = Math.max(_totalCount, _notifications.length);
    _setText('notif-total', String(total));

    const unread = _notifications.filter((notif) => !notif.is_read).length;
    const unreadEl = document.getElementById('notif-unread');
    if (!unreadEl) return;
    unreadEl.textContent = String(unread) + ' غير مقروء';
    unreadEl.classList.toggle('hidden', unread <= 0);
  }

  function _updateLoadMoreUi() {
    const wrap = document.getElementById('notif-load-more-wrap');
    const btn = document.getElementById('notif-load-more');
    if (!wrap || !btn) return;

    const visible = _notifications.length > 0 && (_hasMore || _loadingMore);
    wrap.classList.toggle('hidden', !visible);

    btn.disabled = _loading || _loadingMore;
    btn.textContent = _loadingMore ? 'جار التحميل...' : 'تحميل المزيد';
  }

  function _showGate() {
    const gate = document.getElementById('auth-gate');
    const content = document.getElementById('notif-content');
    if (gate) gate.classList.remove('hidden');
    if (content) content.classList.add('hidden');
  }

  function _hideGate() {
    const gate = document.getElementById('auth-gate');
    const content = document.getElementById('notif-content');
    if (gate) gate.classList.add('hidden');
    if (content) content.classList.remove('hidden');
  }

  function _setLoading(value) {
    _loading = !!value;
    const loader = document.getElementById('notif-loader');
    if (loader) loader.classList.toggle('hidden', !_loading);

    const markAll = document.getElementById('btn-mark-all');
    const deleteOld = document.getElementById('btn-delete-old');
    const retry = document.getElementById('notif-retry');
    if (markAll) markAll.disabled = _loading;
    if (deleteOld) deleteOld.disabled = _loading;
    if (retry) retry.disabled = _loading;

    _updateLoadMoreUi();
  }

  function _setLoadingMore(value) {
    _loadingMore = !!value;
    _updateLoadMoreUi();
  }

  function _setError(message, options) {
    const errorEl = document.getElementById('notif-error');
    const retryWrap = document.getElementById('notif-retry-wrap');
    if (!errorEl) return;
    const showRetry = !options || options.retry !== false;

    if (!message) {
      errorEl.textContent = '';
      errorEl.classList.add('hidden');
      if (retryWrap) retryWrap.classList.add('hidden');
      return;
    }

    errorEl.textContent = message;
    errorEl.classList.remove('hidden');
    if (retryWrap) retryWrap.classList.toggle('hidden', !showRetry);
  }

  function _setText(id, value) {
    const el = document.getElementById(id);
    if (el) el.textContent = value;
  }

  function _safeInt(value) {
    const num = Number(value);
    if (!Number.isFinite(num)) return 0;
    return Math.max(0, Math.floor(num));
  }

  function _showToast(message, type) {
    if (!message) return;
    const existing = document.getElementById('notif-toast');
    if (existing) existing.remove();

    const toast = UI.el('div', {
      id: 'notif-toast',
      className: 'notif-toast' + (type ? (' ' + type) : ''),
      textContent: message,
    });

    document.body.appendChild(toast);
    requestAnimationFrame(() => toast.classList.add('show'));

    window.clearTimeout(_toastTimer);
    _toastTimer = window.setTimeout(() => {
      toast.classList.remove('show');
      window.setTimeout(() => {
        if (toast.parentNode) toast.remove();
      }, 180);
    }, 2200);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
  return {};
})();
