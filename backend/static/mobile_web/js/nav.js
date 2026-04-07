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
  let _topbarSponsorLoaded = false;
  let _topbarBrandLogoLoaded = false;
  let _topbarSponsorRotateTimer = 0;
  let _topbarSponsorFace = 'brand';
  let _topbarSponsorPayload = null;
  let _topbarSponsorDialogBound = false;
  const _badgePollIntervalMs = 45000;
  const _badgeLeaderTtlMs = 70000;
  const _badgeSocketBackoffMaxMs = 30000;
  const _badgeLeaderKey = 'nw_badge_poll_leader_v2';
  const _badgeSnapshotKey = 'nw_badge_snapshot_v2';
  const _badgeRealtimeLocalOverrideKey = 'nw_enable_local_ws';
  const _badgeTabId = Math.random().toString(36).slice(2) + Date.now().toString(36);
  const _topbarSponsorKey = 'nw_topbar_sponsor_v1';
  const _topbarBrandLogoKey = 'nw_topbar_brand_logo_v1';
  const _topbarSponsorTtlMs = 5 * 60 * 1000;
  const _topbarBrandLogoTtlMs = 5 * 60 * 1000;

  function init() {
    _ensureSingleBottomNav();
    _initTopNavbar();
    _initModeAwareProfileNav();
    _initSidebarController();
    _initQuickNavButtons();
    _initAuthUI();
    _initLogout();
    _initUnreadBadges();
    _initTopbarSponsor();
    _initTopbarBrandLogo();
  }

  function _initTopNavbar() {
    const topbar = document.getElementById('top-navbar');
    if (!topbar) return;

    const syncScrolled = () => {
      topbar.classList.toggle('scrolled', window.scrollY > 8);
    };

    syncScrolled();
    window.addEventListener('scroll', syncScrolled, { passive: true });
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

  function _setModeAwareOrdersHref(mode) {
    const href = mode === 'provider' ? '/provider-orders/' : '/orders/';
    document.querySelectorAll('[data-mode-orders-link="true"]').forEach((link) => {
      link.setAttribute('href', href);
    });
  }

  function _initModeAwareProfileNav() {
    const mode = _activeMode();
    _setProfileNavHref(mode);
    _setOrdersNavVisibility(mode);
    _setModeAwareOrdersHref(mode);
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

  function _parsePromoRows(data) {
    if (Array.isArray(data)) return data;
    if (Array.isArray(data?.results)) return data.results;
    if (Array.isArray(data?.items)) return data.items;
    return [];
  }

  function _normalizeTopbarSponsor(raw) {
    if (!raw || typeof raw !== 'object') return null;
    const assets = Array.isArray(raw.assets) ? raw.assets : [];
    const primaryAsset =
      assets.find((asset) => {
        if (!asset || typeof asset !== 'object') return false;
        const assetType = String(asset.asset_type || '').trim().toLowerCase();
        return assetType === 'image' && (asset.file || asset.file_url);
      })
      || assets.find((asset) => asset && (asset.file || asset.file_url))
      || null;
    const targetProviderId = Number(raw.target_provider_id || 0);
    const redirectUrl = String(raw.redirect_url || raw.sponsor_url || '').trim();
    const message = String(raw.message_body || raw.message_title || '').trim();
    return {
      name: String(raw.sponsor_name || raw.target_provider_display_name || '').trim(),
      assetUrl: primaryAsset ? ApiClient.mediaUrl(primaryAsset.file || primaryAsset.file_url) : '',
      href: redirectUrl || (targetProviderId > 0 ? '/provider/' + encodeURIComponent(String(targetProviderId)) + '/' : ''),
      message,
    };
  }

  function _readCachedTopbarSponsor() {
    const cached = _readStorageJson(_topbarSponsorKey);
    if (!cached) return null;
    if (Number(cached.expiresAt || 0) < Date.now()) return null;
    return cached.payload || null;
  }

  function _writeCachedTopbarSponsor(payload) {
    _writeStorageJson(_topbarSponsorKey, {
      expiresAt: Date.now() + _topbarSponsorTtlMs,
      payload,
    });
  }

  function _readCachedTopbarBrandLogo() {
    const cached = _readStorageJson(_topbarBrandLogoKey);
    if (!cached) return null;
    if (Number(cached.expiresAt || 0) < Date.now()) return null;
    return cached.payload || null;
  }

  function _writeCachedTopbarBrandLogo(payload) {
    _writeStorageJson(_topbarBrandLogoKey, {
      expiresAt: Date.now() + _topbarBrandLogoTtlMs,
      payload,
    });
  }

  function _normalizeTopbarBrandLogo(block) {
    if (!block || typeof block !== 'object') return null;
    const mediaUrl = String(block.media_url || '').trim();
    if (!mediaUrl) return null;
    return {
      assetUrl: ApiClient.mediaUrl(mediaUrl),
      title: String(block.title_ar || '').trim() || 'شعار المنصة',
    };
  }

  function _setTopbarFace(face) {
    const brandFace = document.getElementById('topbar-brand-face');
    const sponsorFace = document.getElementById('topbar-sponsor');
    if (!brandFace || !sponsorFace) return;

    const nextFace = face === 'sponsor' ? 'sponsor' : 'brand';
    _topbarSponsorFace = nextFace;
    brandFace.classList.toggle('is-active', nextFace === 'brand');
    sponsorFace.classList.toggle('is-active', nextFace === 'sponsor');
  }

  function _stopTopbarSponsorRotation() {
    if (_topbarSponsorRotateTimer) {
      window.clearInterval(_topbarSponsorRotateTimer);
      _topbarSponsorRotateTimer = 0;
    }
    _setTopbarFace('brand');
  }

  function _startTopbarSponsorRotation() {
    const payload = _topbarSponsorPayload;
    const hasSponsor = !!payload && (
      String(payload.name || '').trim()
      || String(payload.assetUrl || '').trim()
      || String(payload.href || '').trim()
    );
    if (!hasSponsor) {
      _stopTopbarSponsorRotation();
      return;
    }

    _stopTopbarSponsorRotation();
    _setTopbarFace('brand');
    _topbarSponsorRotateTimer = window.setInterval(() => {
      _setTopbarFace(_topbarSponsorFace === 'brand' ? 'sponsor' : 'brand');
    }, 2000);
  }

  function _openTopbarSponsorDialog(payload) {
    const modal = document.getElementById('topbar-sponsor-modal');
    const media = document.getElementById('topbar-sponsor-modal-media');
    const title = document.getElementById('topbar-sponsor-modal-title');
    const body = document.getElementById('topbar-sponsor-modal-body');
    const link = document.getElementById('topbar-sponsor-modal-link');
    if (!modal || !media || !title || !body || !link) return;

    const safePayload = payload && typeof payload === 'object' ? payload : {};
    const sponsorName = String(safePayload.name || '').trim() || 'الراعي الرسمي';
    const sponsorMessage = String(safePayload.message || '').trim() || 'لم يتم إضافة رسالة للرعاية بعد.';
    const sponsorHref = String(safePayload.href || '').trim();
    const sponsorAssetUrl = String(safePayload.assetUrl || '').trim();

    title.textContent = sponsorName;
    body.textContent = sponsorMessage;
    media.innerHTML = '';
    if (sponsorAssetUrl) {
      const img = document.createElement('img');
      img.src = sponsorAssetUrl;
      img.alt = sponsorName;
      media.appendChild(img);
    } else {
      const fallback = document.createElement('span');
      fallback.className = 'topbar-sponsor-modal-placeholder';
      fallback.textContent = sponsorName.charAt(0) || 'ر';
      media.appendChild(fallback);
    }
    if (sponsorHref) {
      link.classList.remove('hidden');
      link.setAttribute('href', sponsorHref);
      const isExternal = /^https?:\/\//i.test(sponsorHref);
      if (isExternal) {
        link.setAttribute('target', '_blank');
        link.setAttribute('rel', 'noopener');
      } else {
        link.removeAttribute('target');
        link.removeAttribute('rel');
      }
    } else {
      link.classList.add('hidden');
      link.removeAttribute('href');
      link.removeAttribute('target');
      link.removeAttribute('rel');
    }

    modal.classList.remove('hidden');
    document.body.style.overflow = 'hidden';
  }

  function _closeTopbarSponsorDialog() {
    const modal = document.getElementById('topbar-sponsor-modal');
    if (!modal || modal.classList.contains('hidden')) return;
    modal.classList.add('hidden');
    document.body.style.overflow = '';
  }

  function _bindTopbarSponsorDialog() {
    if (_topbarSponsorDialogBound) return;
    _topbarSponsorDialogBound = true;

    const sponsor = document.getElementById('topbar-sponsor');
    const closeBtn = document.getElementById('topbar-sponsor-modal-close');
    const backdrop = document.getElementById('topbar-sponsor-modal-backdrop');
    if (sponsor) {
      sponsor.addEventListener('click', (event) => {
        const payload = _topbarSponsorPayload;
        if (!payload || (!payload.message && !payload.href)) {
          return;
        }
        event.preventDefault();
        _openTopbarSponsorDialog(payload);
      });
    }
    if (closeBtn) {
      closeBtn.addEventListener('click', _closeTopbarSponsorDialog);
    }
    if (backdrop) {
      backdrop.addEventListener('click', _closeTopbarSponsorDialog);
    }
    document.addEventListener('keydown', (event) => {
      if (event.key === 'Escape') {
        _closeTopbarSponsorDialog();
      }
    });
  }

  function _resetTopbarSponsorMediaSizing(sponsorMedia) {
    if (!sponsorMedia) return;
    sponsorMedia.classList.remove('is-wide', 'is-tall', 'is-square');
    sponsorMedia.classList.add('is-square');
  }

  function _applyTopbarSponsorMediaSizing(sponsorMedia, img) {
    if (!sponsorMedia || !img) return;
    const width = Number(img.naturalWidth || 0);
    const height = Number(img.naturalHeight || 0);
    sponsorMedia.classList.remove('is-wide', 'is-tall', 'is-square');
    if (!width || !height) {
      sponsorMedia.classList.add('is-square');
      return;
    }
    const ratio = width / height;
    if (ratio >= 1.55) {
      sponsorMedia.classList.add('is-wide');
      return;
    }
    if (ratio <= 0.82) {
      sponsorMedia.classList.add('is-tall');
      return;
    }
    sponsorMedia.classList.add('is-square');
  }

  function _applyTopbarSponsor(payload) {
    const sponsor = document.getElementById('topbar-sponsor');
    const sponsorName = document.getElementById('topbar-sponsor-name');
    const sponsorMedia = document.getElementById('topbar-sponsor-media');
    if (!sponsor || !sponsorName || !sponsorMedia) return;

    const safePayload = payload && typeof payload === 'object' ? payload : null;
    _topbarSponsorPayload = safePayload;
    const name = (safePayload?.name || '').trim() || 'مساحة الرعاية';
    const href = (safePayload?.href || '').trim();
    const assetUrl = (safePayload?.assetUrl || '').trim();
    const message = (safePayload?.message || '').trim();

    sponsorName.textContent = name;
    sponsor.classList.toggle('is-placeholder', !safePayload || (!href && !assetUrl && name === 'مساحة الرعاية'));
    sponsor.classList.toggle('is-link', !!href);
    sponsor.setAttribute('aria-label', `الراعي الحالي: ${name}`);
    sponsor.setAttribute('title', name);
    sponsor.setAttribute('data-sponsor-name', name);
    sponsor.setAttribute('data-sponsor-message', message);
    sponsor.setAttribute('data-sponsor-href', href);

    if (href) {
      sponsor.setAttribute('href', href);
      const isExternal = /^https?:\/\//i.test(href);
      if (isExternal) {
        sponsor.setAttribute('target', '_blank');
        sponsor.setAttribute('rel', 'noopener');
      } else {
        sponsor.removeAttribute('target');
        sponsor.removeAttribute('rel');
      }
    } else {
      sponsor.removeAttribute('href');
      sponsor.removeAttribute('target');
      sponsor.removeAttribute('rel');
    }

    sponsorMedia.innerHTML = '';
    _resetTopbarSponsorMediaSizing(sponsorMedia);
    if (assetUrl) {
      const img = document.createElement('img');
      img.src = assetUrl;
      img.alt = name;
      img.addEventListener('load', () => {
        _applyTopbarSponsorMediaSizing(sponsorMedia, img);
      }, { once: true });
      img.addEventListener('error', () => {
        _resetTopbarSponsorMediaSizing(sponsorMedia);
      }, { once: true });
      sponsorMedia.appendChild(img);
      if (img.complete) {
        _applyTopbarSponsorMediaSizing(sponsorMedia, img);
      }
    } else {
      const fallback = document.createElement('span');
      fallback.className = 'topbar-sponsor-placeholder';
      fallback.textContent = name.charAt(0) || 'ر';
      sponsorMedia.appendChild(fallback);
    }
    _startTopbarSponsorRotation();
  }

  function _renderDefaultTopbarBrandMark(markEl, fallbackLabel) {
    if (!markEl) return;
    markEl.classList.remove('has-image');
    markEl.textContent = fallbackLabel;
  }

  function _applyTopbarBrandLogo(payload) {
    const markEl = document.getElementById('topbar-brand-mark');
    if (!markEl) return;

    const defaultMark = String(markEl.getAttribute('data-default-mark') || markEl.textContent || 'ن').trim() || 'ن';
    const safePayload = payload && typeof payload === 'object' ? payload : null;
    const assetUrl = String(safePayload?.assetUrl || '').trim();
    if (!assetUrl) {
      _renderDefaultTopbarBrandMark(markEl, defaultMark);
      return;
    }

    markEl.classList.add('has-image');
    markEl.textContent = '';
    const img = document.createElement('img');
    img.src = assetUrl;
    img.alt = String(safePayload?.title || 'شعار المنصة').trim() || 'شعار المنصة';
    img.addEventListener('error', () => {
      _renderDefaultTopbarBrandMark(markEl, defaultMark);
    }, { once: true });
    markEl.appendChild(img);
  }

  async function _initTopbarBrandLogo() {
    if (_topbarBrandLogoLoaded) return;
    _topbarBrandLogoLoaded = true;

    const markEl = document.getElementById('topbar-brand-mark');
    if (!markEl) return;

    const cached = _readCachedTopbarBrandLogo();
    if (cached) {
      _applyTopbarBrandLogo(cached);
    } else {
      _applyTopbarBrandLogo(null);
    }

    const res = await ApiClient.get('/api/content/public/');
    if (!res?.ok || !res.data) return;

    const blocks = res.data.blocks || {};
    const payload = _normalizeTopbarBrandLogo(blocks.topbar_brand_logo);
    _writeCachedTopbarBrandLogo(payload);
    _applyTopbarBrandLogo(payload);
  }

  async function _initTopbarSponsor() {
    if (_topbarSponsorLoaded) return;
    _topbarSponsorLoaded = true;

    const sponsor = document.getElementById('topbar-sponsor');
    if (!sponsor) return;
    _bindTopbarSponsorDialog();

    const cached = _readCachedTopbarSponsor();
    if (cached) {
      _applyTopbarSponsor(cached);
    } else {
      _applyTopbarSponsor(null);
    }

    const res = await ApiClient.get('/api/promo/active/?service_type=sponsorship&limit=6');
    if (!res?.ok) return;

    const rows = _parsePromoRows(res.data);
    const firstMatch = rows.find((row) => {
      const normalized = _normalizeTopbarSponsor(row);
      return normalized && (normalized.name || normalized.assetUrl || normalized.href);
    });
    const sponsorPayload = _normalizeTopbarSponsor(firstMatch);

    _writeCachedTopbarSponsor(sponsorPayload);
    _applyTopbarSponsor(sponsorPayload);
  }

  /* ---------- Auth-aware UI ---------- */
  async function _initAuthUI() {
    const loginLink = document.getElementById('sidebar-login-link');
    const desktopLoginLink = document.getElementById('home-desktop-login');
    const logoutBtn = document.getElementById('sidebar-logout');
    const nameEl = document.getElementById('sidebar-name');
    const roleEl = document.getElementById('sidebar-role');
    const avatarEl = document.getElementById('sidebar-avatar');
    const navAvatar = document.getElementById('user-avatar-nav');

    if (loginLink) {
      const returnPath = window.location.pathname === '/login/' ? '/' : window.location.pathname;
      loginLink.href = '/login/?next=' + encodeURIComponent(returnPath);
      if (desktopLoginLink) {
        desktopLoginLink.href = loginLink.href;
      }
    }

    if (!Auth.isLoggedIn()) {
      _setProfileNavHref('client');
      _setOrdersNavVisibility('client');
      _setModeAwareOrdersHref('client');
      if (loginLink) loginLink.classList.remove('hidden');
      if (desktopLoginLink) desktopLoginLink.classList.remove('hidden');
      if (logoutBtn) logoutBtn.classList.add('hidden');
      if (nameEl) nameEl.textContent = 'زائر';
      if (roleEl) roleEl.textContent = 'تصفح كضيف';
      if (avatarEl) avatarEl.textContent = '';
      if (navAvatar) navAvatar.classList.add('hidden');
      return;
    }

    if (loginLink) loginLink.classList.add('hidden');
    if (desktopLoginLink) desktopLoginLink.classList.add('hidden');
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
    _setModeAwareOrdersHref(effectiveMode);

    function _looksLikePhone(v) {
      var s = String(v || '').replace(/[\s\-\+\(\)@]/g, '');
      return /^0[0-9]{8,12}$/.test(s) || /^9665[0-9]{8}$/.test(s) || /^5[0-9]{8}$/.test(s);
    }
    function _safeVal(v) { var s = String(v || '').trim(); return (s && !_looksLikePhone(s)) ? s : ''; }
    const display = _safeVal(profile.display_name) || _safeVal(profile.provider_display_name) || _safeVal(profile.first_name) || _safeVal(profile.username) || 'مستخدم';
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
    return Auth.isLoggedIn() && _badgeOwnsLeadership && _isPageActive() && !_shouldSkipBadgeRealtime();
  }

  function _shouldSkipBadgeRealtime() {
    try {
      const localOverride = String(window.localStorage.getItem(_badgeRealtimeLocalOverrideKey) || '').trim().toLowerCase();
      if (localOverride === '1' || localOverride === 'true') {
        return false;
      }
    } catch (_) {}
    const host = String(window.location.hostname || '').trim().toLowerCase();
    const isLoopback = host === '127.0.0.1' || host === 'localhost' || host === '::1';
    return isLoopback && window.location.protocol === 'http:';
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
