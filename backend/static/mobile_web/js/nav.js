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

    /* ---------- Provider-mode sidebar links ---------- */
    _injectProviderNav(profile);
  }

  function _injectProviderNav(profile) {
    const mode = sessionStorage.getItem('nw_account_mode');
    const isProvider = mode === 'provider' || profile.role_state === 'provider' || profile.is_provider;
    if (!isProvider) return;

    const nav = document.querySelector('.sidebar-nav');
    if (!nav) return;

    const sep = document.createElement('div');
    sep.className = 'sidebar-separator';
    sep.setAttribute('aria-hidden', 'true');
    nav.appendChild(sep);

    const heading = document.createElement('div');
    heading.className = 'sidebar-section-heading';
    heading.textContent = 'لوحة مقدم الخدمة';
    heading.style.cssText = 'padding:12px 16px 4px;font-size:12px;font-weight:700;color:#663D90;';
    nav.appendChild(heading);

    const providerLinks = [
      { href: '/provider-dashboard/', label: 'لوحة التحكم', icon: '<svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor"><path d="M3 13h8V3H3v10zm0 8h8v-6H3v6zm10 0h8V11h-8v10zm0-18v6h8V3h-8z"/></svg>' },
      { href: '/provider-orders/', label: 'الطلبات الواردة', icon: '<svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor"><path d="M19 3H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm-5 14H7v-2h7v2zm3-4H7v-2h10v2zm0-4H7V7h10v2z"/></svg>' },
      { href: '/provider-services/', label: 'خدماتي', icon: '<svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor"><path d="M14 6l-3.75 5 2.85 3.8-1.6 1.2C9.81 13.75 7 10 7 10l-6 8h22L14 6z"/></svg>' },
      { href: '/provider-reviews/', label: 'التقييمات', icon: '<svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor"><path d="M12 17.27L18.18 21l-1.64-7.03L22 9.24l-7.19-.61L12 2 9.19 8.63 2 9.24l5.46 4.73L5.82 21z"/></svg>' },
      { href: '/provider-profile-edit/', label: 'تعديل الملف', icon: '<svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor"><path d="M3 17.25V21h3.75L17.81 9.94l-3.75-3.75L3 17.25zM20.71 7.04c.39-.39.39-1.02 0-1.41l-2.34-2.34c-.39-.39-1.02-.39-1.41 0l-1.83 1.83 3.75 3.75 1.83-1.83z"/></svg>' },
      { href: '/plans/', label: 'الباقات', icon: '<svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor"><path d="M20 4H4c-1.11 0-1.99.89-1.99 2L2 18c0 1.11.89 2 2 2h16c1.11 0 2-.89 2-2V6c0-1.11-.89-2-2-2zm0 14H4v-6h16v6zm0-10H4V6h16v2z"/></svg>' },
      { href: '/promotion/', label: 'الترويج', icon: '<svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor"><path d="M18 11v2h4v-2h-4zm-2 6.61c.96.71 2.21 1.65 3.2 2.39.4-.53.8-1.07 1.2-1.6-.99-.74-2.24-1.68-3.2-2.4-.4.54-.8 1.08-1.2 1.61zM20.4 5.6c-.4-.53-.8-1.07-1.2-1.6-.99.74-2.24 1.68-3.2 2.4.4.53.8 1.07 1.2 1.6.96-.72 2.21-1.65 3.2-2.4zM4 9c-1.1 0-2 .9-2 2v2c0 1.1.9 2 2 2h1l5 3V6L5 9H4zm11.5 3c0-1.33-.58-2.53-1.5-3.35v6.69c.92-.81 1.5-2.01 1.5-3.34z"/></svg>' },
    ];

    providerLinks.forEach(l => {
      const a = document.createElement('a');
      a.href = l.href;
      a.className = 'sidebar-link';
      if (window.location.pathname === l.href) a.classList.add('active');
      a.innerHTML = '<span class="sidebar-label">' + l.label + '</span><span class="sidebar-icon">' + l.icon + '</span>';
      nav.appendChild(a);
      a.addEventListener('click', () => {
        const sidebar = document.getElementById('sidebar');
        if (sidebar) sidebar.classList.remove('open');
        document.body.style.overflow = '';
      });
    });
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
