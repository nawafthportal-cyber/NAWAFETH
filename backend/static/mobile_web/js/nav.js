/* ===================================================================
   nav.js — Shared navigation controller
   Sidebar toggle, auth-aware UI, bottom nav active state.
   =================================================================== */
'use strict';

const Nav = (() => {
  let _sidebarOpen = false;

  function init() {
    _ensureSingleBottomNav();
    _initSidebarController();
    _initQuickNavButtons();
    _initAuthUI();
    _initLogout();
    _initUnreadBadges();
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
    let badge = el.querySelector('.notif-badge');
    if (!badge) {
      badge = document.createElement('span');
      badge.className = 'notif-badge hidden';
      el.appendChild(badge);
    }
    return badge;
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

  async function _loadUnreadBadges() {
    if (!Auth.isLoggedIn()) return;

    const notificationsBtn = document.querySelector('a[href="/notifications/"]');
    const chatsBtn = document.querySelector('a[href="/chats/"]');
    const notificationsBadge = _ensureBadge(notificationsBtn);
    const chatsBadge = _ensureBadge(chatsBtn);
    if (!notificationsBadge && !chatsBadge) return;

    const mode = _activeMode();
    const [notifRes, chatsRes] = await Promise.all([
      ApiClient.get('/api/notifications/unread-count/?mode=' + mode),
      ApiClient.get('/api/messaging/direct/unread-count/?mode=' + mode),
    ]);

    const notifUnread = notifRes?.ok ? (notifRes.data?.unread || 0) : 0;
    const chatUnread = chatsRes?.ok ? (chatsRes.data?.unread || 0) : 0;
    _setBadge(notificationsBadge, notifUnread);
    _setBadge(chatsBadge, chatUnread);
  }

  function _initUnreadBadges() {
    _loadUnreadBadges();
    setInterval(_loadUnreadBadges, 20000);
  }

  // Boot
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  return { init };
})();
