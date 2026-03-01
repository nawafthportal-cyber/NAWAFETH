/* ===================================================================
   nav.js — Shared navigation controller
   Sidebar toggle, auth-aware UI, bottom nav active state.
   =================================================================== */
'use strict';

const Nav = (() => {
  let _sidebarOpen = false;

  function init() {
    _initSidebarController();
    _initQuickNavButtons();
    _initAuthUI();
    _initLogout();
  }

  /* ---------- Sidebar ---------- */
  function _initSidebarController() {
    const btn = document.getElementById('btn-menu');
    const sidebar = document.getElementById('sidebar');
    const overlay = document.getElementById('sidebar-overlay');
    const close = document.getElementById('sidebar-close');
    if (!btn || !sidebar) return;

    const open = () => {
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
      _sidebarOpen = false;
      sidebar.classList.remove('open');
      sidebar.setAttribute('aria-hidden', 'true');
      if (overlay) {
        overlay.classList.add('hidden');
        overlay.setAttribute('aria-hidden', 'true');
      }
      document.body.style.overflow = '';
    };

    btn.addEventListener('click', open);
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
    const notifBtn = document.getElementById('btn-notifications');
    if (notifBtn) {
      notifBtn.addEventListener('click', () => {
        window.location.href = '/notifications/';
      });
    }

    const chatBtn = document.getElementById('btn-chat');
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
        window.location.href = '/profile/';
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

  // Boot
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  return { init };
})();
