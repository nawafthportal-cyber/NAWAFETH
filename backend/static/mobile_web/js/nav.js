/* ===================================================================
   nav.js — Shared navigation controller
   Sidebar toggle, auth-aware UI, bottom nav active state.
   =================================================================== */
'use strict';

const Nav = (() => {
  let _sidebarOpen = false;
  let _badgeRefreshInFlight = false;
  let _badgeUnauthorizedUntil = 0;
  let _badgePollTimer = null;
  let _badgeSocket = null;
  let _badgeSocketReconnectTimer = null;
  let _badgeSocketBackoffMs = 1000;
  let _badgeOwnsLeadership = false;
  let _badgeEventsBound = false;
  const _badgePollIntervalMs = 45000;
  const _badgeLeaderTtlMs = 70000;
  const _badgeSocketBackoffMaxMs = 30000;
  const _badgeLeaderKey = 'nw_badge_poll_leader_v2';
  const _badgeSnapshotKey = 'nw_badge_snapshot_v2';
  const _badgeTabId = Math.random().toString(36).slice(2) + Date.now().toString(36);

  function init() {
    _ensureSingleBottomNav();
    _initModeAwareProfileNav();
    _initSidebarController();
    _initQuickNavButtons();
    _initAuthUI();
    _initLogout();
    _initUnreadBadges();
  }

  function _setProfileNavHref(mode) {
    const profileNav = document.querySelector('#bottom-nav a.bnav-item[data-index="3"]');
    if (!profileNav) return;
    profileNav.setAttribute('href', mode === 'provider' ? '/provider-dashboard/' : '/profile/');
  }

  function _setOrdersNavVisibility(mode) {
    const ordersNav = document.querySelector('#bottom-nav a.bnav-item[data-index="1"]');
    if (!ordersNav) return;
    ordersNav.classList.toggle('hidden', mode === 'provider');
  }

  function _initModeAwareProfileNav() {
    const mode = _activeMode();
    _setProfileNavHref(mode);
    _setOrdersNavVisibility(mode);
  }

  function _ensureSingleBottomNav() {
    const navs = Array.from(document.querySelectorAll('nav#bottom-nav'));
    if (navs.length <= 1) return;

    const primary = navs[0];
    for (let index = 1; index < navs.length; index += 1) {
      navs[index].remove();
    }

    primary.style.display = 'flex';
  }

  /* ---------- Sidebar ---------- */
  function _initSidebarController() {
    const buttons = [
      document.getElementById('btn-menu'),
      document.getElementById('hero-menu-btn'),
    ].filter(Boolean);
    const sidebar = document.getElementById('sidebar');
    const overlay = document.getElementById('sidebar-overlay');
    const close = document.getElementById('sidebar-close');
    if (!buttons.length || !sidebar) return;

    const open = () => {
      if (_sidebarOpen) return;
      _sidebarOpen = true;
      sidebar.classList.add('open');
      sidebar.setAttribute('aria-hidden', 'false');
      if (overlay) {
        overlay.classList.remove('hidden');
        overlay.setAttribute('aria-hidden', 'false');
      }
      document.body.style.overflow = 'hidden';
    };

    const shut = () => {
      if (!_sidebarOpen) return;
      _sidebarOpen = false;
      sidebar.classList.remove('open');
      sidebar.setAttribute('aria-hidden', 'true');
      if (overlay) {
        overlay.classList.add('hidden');
        overlay.setAttribute('aria-hidden', 'true');
      }
      document.body.style.overflow = '';
    };

    const toggle = () => {
      if (_sidebarOpen) shut();
      else open();
    };

    buttons.forEach(btn => btn.addEventListener('click', toggle));
    if (overlay) overlay.addEventListener('click', shut);
    if (close) close.addEventListener('click', shut);

    sidebar.querySelectorAll('a.sidebar-link, button.sidebar-link').forEach(link => {
      link.addEventListener('click', () => {
        if (link.id !== 'sidebar-logout') shut();
      });
    });

    document.addEventListener('keydown', e => {
      if (e.key === 'Escape' && _sidebarOpen) shut();
    });
  }

  function _initQuickNavButtons() {
    const notifBtn = document.getElementById('btn-notifications') || document.querySelector('a[href="/notifications/"]');
    if (notifBtn) {
      notifBtn.addEventListener('click', () => {
        window.location.href = '/notifications/';
      });
    }

    const chatBtn = document.getElementById('btn-chat') || document.querySelector('a[href="/chats/"]');
    if (chatBtn) {
      chatBtn.addEventListener('click', () => {
        window.location.href = '/chats/';
      });
    }
  }

  /* ---------- Auth-aware UI ---------- */
  async function _initAuthUI() {
    const loginLink = document.getElementById('sidebar-login-link');
    const logoutBtn = document.getElementById('sidebar-logout');
    const nameEl = document.getElementById('sidebar-name');
    const roleEl = document.getElementById('sidebar-role');
    const avatarEl = document.getElementById('sidebar-avatar');
    const navAvatar = document.getElementById('user-avatar-nav');

    if (loginLink) {
      const returnPath = window.location.pathname === '/login/' ? '/' : window.location.pathname;
      loginLink.href = '/login/?next=' + encodeURIComponent(returnPath);
    }

    if (!Auth.isLoggedIn()) {
      _setProfileNavHref('client');
      _setOrdersNavVisibility('client');
      if (loginLink) loginLink.classList.remove('hidden');
      if (logoutBtn) logoutBtn.classList.add('hidden');
      if (nameEl) nameEl.textContent = 'زائر';
      if (roleEl) roleEl.textContent = 'تصفح كضيف';
      if (avatarEl) avatarEl.textContent = '';
      if (navAvatar) navAvatar.classList.add('hidden');
      return;
    }

    if (loginLink) loginLink.classList.add('hidden');
    if (logoutBtn) logoutBtn.classList.remove('hidden');

    const profile = await Auth.getProfile();
    if (!profile) return;

    const canUseProviderMode = !!(
      profile.role_state === 'provider'
      || profile.is_provider
      || profile.has_provider_profile
    );
    const requestedMode = (() => {
      try {
        return (sessionStorage.getItem('nw_account_mode') || '').trim().toLowerCase();
      } catch (_) {
        return '';
      }
    })();
    const effectiveMode = (requestedMode === 'provider' && canUseProviderMode) ? 'provider' : 'client';
    try {
      sessionStorage.setItem('nw_account_mode', effectiveMode);
    } catch (_) {}
    _setProfileNavHref(effectiveMode);
    _setOrdersNavVisibility(effectiveMode);

    const display = profile.display_name || profile.first_name || profile.username || 'مستخدم';
    const role = profile.role_state === 'provider'
      ? 'مقدم خدمة'
      : profile.role_state === 'client'
        ? 'عميل'
        : 'حساب مستخدم';
    const initial = (display || 'م').charAt(0);

    if (nameEl) nameEl.textContent = display;
    if (roleEl) roleEl.textContent = role;

    if (avatarEl) {
      if (profile.profile_image) {
        avatarEl.innerHTML = '';
        const img = document.createElement('img');
        img.src = ApiClient.mediaUrl(profile.profile_image);
        img.alt = display;
        avatarEl.appendChild(img);
      } else {
        avatarEl.textContent = initial;
      }
    }

    if (navAvatar) {
      navAvatar.classList.remove('hidden');
      navAvatar.title = 'الملف الشخصي';
      navAvatar.addEventListener('click', () => {
        const mode = sessionStorage.getItem('nw_account_mode');
        window.location.href = mode === 'provider' ? '/provider-dashboard/' : '/profile/';
      });
      if (profile.profile_image) {
        navAvatar.innerHTML = '';
        const img = document.createElement('img');
        img.src = ApiClient.mediaUrl(profile.profile_image);
        img.alt = display;
        navAvatar.appendChild(img);
      } else {
        navAvatar.textContent = initial;
      }
    }

  }

  /* ---------- Logout ---------- */
  function _initLogout() {
    const btn = document.getElementById('sidebar-logout');
    if (!btn) return;
    btn.addEventListener('click', async () => {
      const refresh = Auth.getRefreshToken();
      if (refresh) {
        await ApiClient.request('/api/accounts/logout/', {
          method: 'POST', body: { refresh },
        });
      }
      Auth.logout();
      window.location.href = '/';
    });
  }

  function _activeMode() {
    try {
      const mode = (sessionStorage.getItem('nw_account_mode') || '').trim().toLowerCase();
      if (mode === 'provider' || mode === 'client') return mode;
    } catch (_) {}
    const role = (Auth.getRoleState() || '').trim().toLowerCase();
    return role === 'provider' ? 'provider' : 'client';
  }

  function _ensureBadge(el) {
    if (!el) return null;
    el.classList.add('badge-host');
    let badge = el.querySelector('.notif-badge');
    if (!badge) {
      badge = document.createElement('span');
      badge.className = 'notif-badge hidden';
      el.appendChild(badge);
    }
    return badge;
  }

  function _ensureBadges(selector) {
    const nodes = Array.from(document.querySelectorAll(selector));
    if (!nodes.length) return [];
    return nodes
      .map(_ensureBadge)
      .filter(Boolean);
  }

  function _setBadge(badge, count) {
    if (!badge) return;
    const value = Number.isFinite(count) ? Math.max(0, count) : 0;
    if (value <= 0) {
      badge.textContent = '';
      badge.classList.add('hidden');
      return;
    }
    badge.textContent = value > 99 ? '99+' : String(value);
    badge.classList.remove('hidden');
  }

  function _clearUnreadBadges() {
    _ensureBadges('a[href="/notifications/"], #btn-notifications').forEach((badge) => _setBadge(badge, 0));
    _ensureBadges('a[href="/chats/"], #btn-chat').forEach((badge) => _setBadge(badge, 0));
  }

  function _readStorageJson(key) {
    try {
      const raw = window.localStorage.getItem(key);
      return raw ? JSON.parse(raw) : null;
    } catch (_) {
      return null;
    }
  }

  function _writeStorageJson(key, value) {
    try {
      window.localStorage.setItem(key, JSON.stringify(value));
    } catch (_) {}
  }

  function _removeStorageKey(key) {
    try {
      window.localStorage.removeItem(key);
    } catch (_) {}
  }

  function _isPageActive() {
    return document.visibilityState === 'visible' && document.hasFocus();
  }

  function _hasFreshLeader(record) {
    return !!record && record.id && Number(record.expiresAt || 0) > Date.now();
  }

  function _claimBadgeLeadership(force) {
    if (!Auth.isLoggedIn() || !_isPageActive()) {
      _badgeOwnsLeadership = false;
      return false;
    }
    const currentLeader = _readStorageJson(_badgeLeaderKey);
    if (!force && _hasFreshLeader(currentLeader) && currentLeader.id !== _badgeTabId) {
      _badgeOwnsLeadership = false;
      return false;
    }
    _writeStorageJson(_badgeLeaderKey, {
      id: _badgeTabId,
      expiresAt: Date.now() + _badgeLeaderTtlMs,
    });
    const confirmedLeader = _readStorageJson(_badgeLeaderKey);
    _badgeOwnsLeadership = !!confirmedLeader && confirmedLeader.id === _badgeTabId;
    return _badgeOwnsLeadership;
  }

  function _renewBadgeLeadership() {
    if (!_badgeOwnsLeadership) return;
    _writeStorageJson(_badgeLeaderKey, {
      id: _badgeTabId,
      expiresAt: Date.now() + _badgeLeaderTtlMs,
    });
  }

  function _releaseBadgeLeadership() {
    const currentLeader = _readStorageJson(_badgeLeaderKey);
    if (currentLeader && currentLeader.id === _badgeTabId) {
      _removeStorageKey(_badgeLeaderKey);
    }
    _badgeOwnsLeadership = false;
  }

  function _clearBadgeSocketReconnect() {
    if (_badgeSocketReconnectTimer) {
      clearTimeout(_badgeSocketReconnectTimer);
      _badgeSocketReconnectTimer = null;
    }
  }

  function _closeBadgeSocket() {
    _clearBadgeSocketReconnect();
    if (!_badgeSocket) return;
    const socket = _badgeSocket;
    _badgeSocket = null;
    try {
      socket.onopen = null;
      socket.onmessage = null;
      socket.onerror = null;
      socket.onclose = null;
      socket.close(1000, 'badge polling stopped');
    } catch (_) {}
  }

  function _canUseBadgeRealtime() {
    return Auth.isLoggedIn() && _badgeOwnsLeadership && _isPageActive();
  }

  function _badgeSocketUrl() {
    const token = Auth.getAccessToken();
    if (!token) return null;
    try {
      const url = new URL('/ws/notifications/', ApiClient.BASE || window.location.origin);
      url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:';
      url.searchParams.set('token', token);
      return url.toString();
    } catch (_) {
      return null;
    }
  }

  function _scheduleBadgeSocketReconnect() {
    if (_badgeSocketReconnectTimer || !_canUseBadgeRealtime()) {
      return;
    }
    const delay = _badgeSocketBackoffMs;
    _badgeSocketReconnectTimer = window.setTimeout(() => {
      _badgeSocketReconnectTimer = null;
      _connectBadgeSocket();
    }, delay);
    _badgeSocketBackoffMs = Math.min(_badgeSocketBackoffMaxMs, Math.max(1000, delay * 2));
  }

  function _handleBadgeSocketMessage(rawEvent) {
    let payload = null;
    try {
      payload = JSON.parse(rawEvent.data || '{}');
    } catch (_) {
      return;
    }
    if (!payload || payload.type !== 'notification.created') return;
    try {
      window.dispatchEvent(new CustomEvent('nw:notification-created', {
        detail: payload.notification || {},
      }));
    } catch (_) {}
    _syncBadgePolling(true);
  }

  function _connectBadgeSocket() {
    if (!_canUseBadgeRealtime()) {
      _closeBadgeSocket();
      return;
    }
    if (_badgeSocket || _badgeSocketReconnectTimer) {
      return;
    }
    const url = _badgeSocketUrl();
    if (!url) return;

    let socket;
    try {
      socket = new WebSocket(url);
    } catch (_) {
      _scheduleBadgeSocketReconnect();
      return;
    }

    _badgeSocket = socket;
    socket.onopen = () => {
      if (_badgeSocket !== socket) return;
      _badgeSocketBackoffMs = 1000;
      _syncBadgePolling(true);
    };
    socket.onmessage = (event) => {
      if (_badgeSocket !== socket) return;
      _handleBadgeSocketMessage(event);
    };
    socket.onerror = () => {};
    socket.onclose = async (event) => {
      if (_badgeSocket === socket) {
        _badgeSocket = null;
      }
      if (!_canUseBadgeRealtime()) return;
      if (event && event.code === 4401 && typeof Auth.refreshAccessToken === 'function') {
        try {
          const refreshed = await Auth.refreshAccessToken();
          if (refreshed && _canUseBadgeRealtime()) {
            _connectBadgeSocket();
            return;
          }
        } catch (_) {}
      }
      _scheduleBadgeSocketReconnect();
    };
  }

  function _applyBadgePayload(payload) {
    if (!payload) return;
    const notificationsBadges = _ensureBadges('a[href="/notifications/"], #btn-notifications');
    const chatsBadges = _ensureBadges('a[href="/chats/"], #btn-chat');
    notificationsBadges.forEach((badge) => _setBadge(badge, payload.notifications || 0));
    chatsBadges.forEach((badge) => _setBadge(badge, payload.chats || 0));
  }

  function _publishBadgePayload(payload) {
    _writeStorageJson(_badgeSnapshotKey, {
      notifications: Math.max(0, Number(payload.notifications) || 0),
      chats: Math.max(0, Number(payload.chats) || 0),
      publishedAt: Date.now(),
    });
  }

  async function _loadUnreadBadges(forceLeadership) {
    if (_badgeRefreshInFlight) return;
    if (_badgeUnauthorizedUntil && Date.now() < _badgeUnauthorizedUntil) {
      return;
    }
    if (!Auth.isLoggedIn()) {
      _badgeUnauthorizedUntil = 0;
      _clearUnreadBadges();
      _stopBadgePolling();
      return;
    }

    const notificationsBadges = _ensureBadges('a[href="/notifications/"], #btn-notifications');
    const chatsBadges = _ensureBadges('a[href="/chats/"], #btn-chat');
    if (!notificationsBadges.length && !chatsBadges.length) {
      _stopBadgePolling();
      return;
    }

    if (!_claimBadgeLeadership(!!forceLeadership)) {
      const snapshot = _readStorageJson(_badgeSnapshotKey);
      if (snapshot) _applyBadgePayload(snapshot);
      return;
    }

    _badgeRefreshInFlight = true;
    try {
      _renewBadgeLeadership();
      const mode = _activeMode();
      const res = await ApiClient.get('/api/core/unread-badges/?mode=' + mode);
      if (res?.status === 401) {
        _badgeUnauthorizedUntil = Date.now() + (2 * 60 * 1000);
        _clearUnreadBadges();
        _stopBadgePolling();
        return;
      }

      if (!res?.ok || !res.data) {
        return;
      }

      _badgeUnauthorizedUntil = 0;
      const payload = {
        notifications: res.data.notifications || 0,
        chats: res.data.chats || 0,
      };
      _applyBadgePayload(payload);
      _publishBadgePayload(payload);
    } finally {
      _badgeRefreshInFlight = false;
    }
  }

  function _stopBadgePolling() {
    if (_badgePollTimer) {
      clearInterval(_badgePollTimer);
      _badgePollTimer = null;
    }
    _closeBadgeSocket();
    _releaseBadgeLeadership();
  }

  function _startBadgePolling(forceLeadership) {
    if (!Auth.isLoggedIn() || !_isPageActive()) {
      _stopBadgePolling();
      return;
    }
    if (!_claimBadgeLeadership(forceLeadership)) {
      _stopBadgePolling();
      const snapshot = _readStorageJson(_badgeSnapshotKey);
      if (snapshot) _applyBadgePayload(snapshot);
      return;
    }
    _connectBadgeSocket();
    if (_badgePollTimer) return;
    _badgePollTimer = window.setInterval(() => {
      if (!_isPageActive()) {
        _stopBadgePolling();
        return;
      }
      if (!_claimBadgeLeadership(false)) {
        _stopBadgePolling();
        return;
      }
      _connectBadgeSocket();
      _loadUnreadBadges(false);
    }, _badgePollIntervalMs);
  }

  function _syncBadgePolling(forceRefresh) {
    if (!Auth.isLoggedIn() || !_isPageActive()) {
      _stopBadgePolling();
      return;
    }
    _startBadgePolling(true);
    if (forceRefresh) _loadUnreadBadges(true);
  }

  function _handleBadgeStorage(event) {
    if (event.key === _badgeSnapshotKey && event.newValue) {
      try {
        _applyBadgePayload(JSON.parse(event.newValue));
      } catch (_) {}
      return;
    }
    if (event.key === _badgeLeaderKey && _badgeOwnsLeadership) {
      try {
        const leader = event.newValue ? JSON.parse(event.newValue) : null;
        if (leader && leader.id !== _badgeTabId && _hasFreshLeader(leader)) {
          _badgeOwnsLeadership = false;
          if (_badgePollTimer) {
            clearInterval(_badgePollTimer);
            _badgePollTimer = null;
          }
          _closeBadgeSocket();
        }
      } catch (_) {}
    }
  }

  function _initUnreadBadges() {
    const snapshot = _readStorageJson(_badgeSnapshotKey);
    if (snapshot) _applyBadgePayload(snapshot);

    if (!_badgeEventsBound) {
      _badgeEventsBound = true;
      document.addEventListener('visibilitychange', () => {
        if (document.visibilityState === 'visible') _syncBadgePolling(true);
        else _stopBadgePolling();
      });
      window.addEventListener('focus', () => _syncBadgePolling(true));
      window.addEventListener('blur', _stopBadgePolling);
      window.addEventListener('pageshow', () => _syncBadgePolling(true));
      window.addEventListener('beforeunload', _stopBadgePolling);
      window.addEventListener('storage', _handleBadgeStorage);
      window.addEventListener('nw:badge-refresh', () => _syncBadgePolling(true));
      window.addEventListener('nw:auth-logout', () => {
        _badgeUnauthorizedUntil = 0;
        _clearUnreadBadges();
        _stopBadgePolling();
      });
    }

    _syncBadgePolling(true);
  }

  // Boot
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  return {
    init,
    refreshUnreadBadges: _loadUnreadBadges,
  };
})();
