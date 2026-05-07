/* ===================================================================
   nav.js — Shared navigation controller
   Sidebar toggle, auth-aware UI, bottom nav active state.
   =================================================================== */
'use strict';

const Toast = (() => {
  const PENDING_KEY = 'nw_pending_toast_v1';
  let _timer = 0;

  function _storage() {
    try { return window.sessionStorage; } catch (_) { return null; }
  }

  function show(message, options = {}) {
    const toast = document.getElementById('global-toast');
    const titleEl = document.getElementById('global-toast-title');
    const messageEl = document.getElementById('global-toast-message');
    if (!toast || !messageEl) return;

    const title = String(options.title || '').trim();
    const text = String(message || '').trim();
    if (!title && !text) return;

    toast.classList.remove('success', 'warning', 'error', 'info', 'show');
    toast.classList.add(String(options.type || 'success').trim() || 'success');
    if (titleEl) titleEl.textContent = title;
    messageEl.textContent = text;

    requestAnimationFrame(() => toast.classList.add('show'));
    if (_timer) window.clearTimeout(_timer);
    _timer = window.setTimeout(() => {
      toast.classList.remove('show');
    }, Number(options.duration || 5200));
  }

  function queue(message, options = {}) {
    const store = _storage();
    if (!store) return;
    try {
      store.setItem(PENDING_KEY, JSON.stringify({
        title: String(options.title || '').trim(),
        message: String(message || '').trim(),
        type: String(options.type || 'success').trim() || 'success',
        duration: Number(options.duration || 5200),
      }));
    } catch (_) {}
  }

  function flushPending() {
    const store = _storage();
    if (!store) return;
    let payload = null;
    try {
      payload = JSON.parse(store.getItem(PENDING_KEY) || 'null');
      store.removeItem(PENDING_KEY);
    } catch (_) {
      try { store.removeItem(PENDING_KEY); } catch (__) {}
      return;
    }
    if (!payload || !payload.message) return;
    show(payload.message, payload);
  }

  return { show, queue, flushPending };
})();

window.Toast = Toast;

const Nav = (() => {
  let _sidebarOpen = false;
  let _badgeRefreshInFlight = false;
  let _badgeUnauthorizedUntil = 0;
  let _badgePollTimer = null;
  let _badgeSocket = null;
  let _badgeSocketConnectPromise = null;
  let _badgeSocketReconnectTimer = null;
  let _badgeSocketHeartbeatTimer = null;
  let _badgeSocketBackoffMs = 1000;
  let _badgeOwnsLeadership = false;
  let _badgeEventsBound = false;
  let _badgeSocketLastActivityAt = 0;
  let _badgeSocketOpenedAt = 0;
  let _badgeLastFetchAt = 0;
  let _badgeSocketCloseIntent = '';
  let _badgeSocketLastCloseReason = 'unknown';
  let _topbarSponsorLoaded = false;
  let _topbarBrandLogoLoaded = false;
  let _topbarSponsorRotateTimer = 0;
  let _topbarSponsorFace = 'brand';
  let _topbarSponsorPayload = null;
  let _topbarSponsorDialogBound = false;
  const _badgePollIntervalMs = 45000;
  const _badgeHealthySyncIntervalMs = 3 * 60 * 1000;
  const _badgeLeaderTtlMs = 70000;
  const _badgeSocketBackoffMaxMs = 30000;
  const _badgeSocketHeartbeatIntervalMs = 27000;
  const _badgeSocketHeartbeatTimeoutMs = 75000;
  const _badgeShortConnectionMs = 5000;
  const _badgeLeaderKey = 'nw_badge_poll_leader_v2';
  const _badgeSnapshotKey = 'nw_badge_snapshot_v2';
  const _badgeRealtimeLocalOverrideKey = 'nw_enable_local_ws';
  const _badgeTabId = Math.random().toString(36).slice(2) + Date.now().toString(36);
  const _topbarSponsorKey = 'nw_topbar_sponsor_v1';
  const _topbarBrandLogoKey = 'nw_topbar_brand_logo_v1';
  const _topbarSponsorTtlMs = 5 * 60 * 1000;
  const _topbarBrandLogoTtlMs = 5 * 60 * 1000;

  function _t(key, replacements, fallback) {
    if (window.NawafethI18n && typeof window.NawafethI18n.t === 'function') {
      const value = window.NawafethI18n.t(key, replacements);
      if (value) return value;
    }
    return fallback || '';
  }

  function _currentLang() {
    if (window.NawafethI18n && typeof window.NawafethI18n.getLanguage === 'function') {
      return window.NawafethI18n.getLanguage();
    }
    return 'ar';
  }

  function init() {
    _ensureSingleBottomNav();
    _initTopNavbar();
    _initModeAwareProfileNav();
    _initSidebarController();
    _initQuickNavButtons();
    Toast.flushPending();
    _initAuthUI();
    _initLogout();
    _initDeleteAccount();
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
        if (link.id !== 'sidebar-logout' && link.id !== 'sidebar-delete-account') shut();
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
      title: String(block.title_ar || '').trim() || _t('platformLogoAlt', null, 'شعار المنصة'),
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
    }, 5000);
  }

  function _openTopbarSponsorDialog(payload) {
    const modal = document.getElementById('topbar-sponsor-modal');
    const media = document.getElementById('topbar-sponsor-modal-media');
    const title = document.getElementById('topbar-sponsor-modal-title');
    const body = document.getElementById('topbar-sponsor-modal-body');
    const link = document.getElementById('topbar-sponsor-modal-link');
    if (!modal || !media || !title || !body || !link) return;

    const safePayload = payload && typeof payload === 'object' ? payload : {};
    const sponsorName = String(safePayload.name || '').trim() || _t('officialSponsor', null, 'الراعي الرسمي');
    const sponsorMessage = String(safePayload.message || '').trim() || _t('sponsorMessageEmpty', null, 'تظهر تفاصيل الرعاية هنا عند توفر رسالة.');
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

    modal.scrollTop = 0;
    body.scrollTop = 0;
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

  function _resetTopbarBrandMediaSizing(markEl) {
    if (!markEl) return;
    markEl.classList.remove('is-wide', 'is-tall', 'is-square');
    markEl.classList.add('is-square');
  }

  function _applyTopbarBrandMediaSizing(markEl, img) {
    if (!markEl || !img) return;
    const width = Number(img.naturalWidth || 0);
    const height = Number(img.naturalHeight || 0);
    markEl.classList.remove('is-wide', 'is-tall', 'is-square');
    if (!width || !height) {
      markEl.classList.add('is-square');
      return;
    }
    const ratio = width / height;
    if (ratio >= 1.55) {
      markEl.classList.add('is-wide');
      return;
    }
    if (ratio <= 0.82) {
      markEl.classList.add('is-tall');
      return;
    }
    markEl.classList.add('is-square');
  }

  function _applyTopbarSponsor(payload) {
    const sponsor = document.getElementById('topbar-sponsor');
    const sponsorName = document.getElementById('topbar-sponsor-name');
    const sponsorMedia = document.getElementById('topbar-sponsor-media');
    if (!sponsor || !sponsorName || !sponsorMedia) return;

    const safePayload = payload && typeof payload === 'object' ? payload : null;
    _topbarSponsorPayload = safePayload;
    const name = (safePayload?.name || '').trim() || _t('sponsorPlaceholder', null, 'مساحة الرعاية');
    const href = (safePayload?.href || '').trim();
    const assetUrl = (safePayload?.assetUrl || '').trim();
    const message = (safePayload?.message || '').trim();

    sponsorName.textContent = name;
    sponsor.classList.toggle('is-placeholder', !safePayload || (!href && !assetUrl && name === _t('sponsorPlaceholder', null, 'مساحة الرعاية')));
    sponsor.classList.toggle('is-link', !!href);
    sponsor.setAttribute('aria-label', _t('currentSponsorAria', { name }, `الراعي الحالي: ${name}`));
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
    markEl.classList.remove('is-wide', 'is-tall', 'is-square');
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
    _resetTopbarBrandMediaSizing(markEl);
    markEl.textContent = '';
    const img = document.createElement('img');
    img.src = assetUrl;
    img.alt = String(safePayload?.title || 'شعار المنصة').trim() || 'شعار المنصة';
    img.addEventListener('load', () => {
      _applyTopbarBrandMediaSizing(markEl, img);
    }, { once: true });
    img.addEventListener('error', () => {
      _renderDefaultTopbarBrandMark(markEl, defaultMark);
    }, { once: true });
    markEl.appendChild(img);
    if (img.complete) {
      _applyTopbarBrandMediaSizing(markEl, img);
    }
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
    const deleteAccountBtn = document.getElementById('sidebar-delete-account');
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
      if (deleteAccountBtn) deleteAccountBtn.classList.add('hidden');
      if (nameEl) nameEl.textContent = _t('guestName', null, 'زائر');
      if (roleEl) roleEl.textContent = _t('guestRole', null, 'تصفح كضيف');
      if (avatarEl) avatarEl.textContent = '';
      if (navAvatar) navAvatar.classList.add('hidden');
      return;
    }

    if (loginLink) loginLink.classList.add('hidden');
    if (desktopLoginLink) desktopLoginLink.classList.add('hidden');
    if (logoutBtn) logoutBtn.classList.remove('hidden');
    if (deleteAccountBtn) deleteAccountBtn.classList.remove('hidden');

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
      if (window.Auth && typeof window.Auth.setActiveAccountMode === 'function') {
        window.Auth.setActiveAccountMode(effectiveMode);
      } else {
        sessionStorage.setItem('nw_account_mode', effectiveMode);
      }
    } catch (_) {}
    _setProfileNavHref(effectiveMode);
    _setOrdersNavVisibility(effectiveMode);
    _setModeAwareOrdersHref(effectiveMode);

    function _looksLikePhone(v) {
      var s = String(v || '').replace(/[\s\-\+\(\)@]/g, '');
      return /^0[0-9]{8,12}$/.test(s) || /^9665[0-9]{8}$/.test(s) || /^5[0-9]{8}$/.test(s);
    }
    function _safeVal(v) { var s = String(v || '').trim(); return (s && !_looksLikePhone(s)) ? s : ''; }
    const display = _safeVal(profile.display_name) || _safeVal(profile.provider_display_name) || _safeVal(profile.first_name) || _safeVal(profile.username) || _t('genericUser', null, 'مستخدم');
    const role = _currentLang() === 'en'
      ? (
        profile.role_state === 'provider'
          ? _t('roleProvider', null, 'Provider')
          : profile.role_state === 'client'
            ? _t('roleClient', null, 'Client')
            : _t('roleUser', null, 'User Account')
      )
      : String(profile.role_label || '').trim() || (
        profile.role_state === 'provider'
          ? _t('roleProvider', null, 'مقدم خدمة')
          : profile.role_state === 'client'
            ? _t('roleClient', null, 'عميل')
            : _t('roleUser', null, 'حساب مستخدم')
      );
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
      navAvatar.title = _t('profileAria', null, 'الملف الشخصي');
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
      await ApiClient.request('/api/accounts/logout/', {
        method: 'POST', body: refresh ? { refresh } : {},
      });
      Auth.logout();
      window.location.href = '/';
    });
  }

  /* ---------- Delete account ---------- */
  function _initDeleteAccount() {
    const btn = document.getElementById('sidebar-delete-account');
    if (!btn) return;
    btn.addEventListener('click', async () => {
      const confirmed = window.confirm(
        _t('deleteConfirm', null, 'سيتم حذف حسابك نهائيًا من قاعدة البيانات ولن يمكن استعادته. هل تريد المتابعة؟')
      );
      if (!confirmed) return;

      btn.disabled = true;
      const label = btn.querySelector('.sidebar-label');
      const previousLabel = label ? label.textContent : '';
      if (label) label.textContent = _t('deleteBusy', null, 'جارٍ حذف الحساب...');

      const res = await ApiClient.request('/api/accounts/delete/', {
        method: 'DELETE',
        timeout: 20000,
      });

      if (res?.ok) {
        Toast.queue(
          _t('deleteSuccessMessage', null, 'نعتذر لك عن أي تقصير في تجربتك معنا. تم حذف حسابك وبياناته المرتبطة من قاعدة البيانات، ونسعد بخدمتك مرة أخرى متى رغبت بالعودة.'),
          { title: _t('deleteSuccessTitle', null, 'تم حذف الحساب نهائيًا'), type: 'warning', duration: 7600 }
        );
        Auth.logout();
        window.location.href = '/login/';
        return;
      }

      btn.disabled = false;
      if (label) label.textContent = previousLabel || _t('sidebarDelete', null, 'حذف الحساب نهائيًا');
      window.alert((res && res.data && (res.data.detail || res.data.error)) || _t('deleteError', null, 'تعذر حذف الحساب، حاول مرة أخرى.'));
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

  function _setBadgeSocketIntent(reason) {
    _badgeSocketCloseIntent = String(reason || '').trim().toLowerCase();
  }

  function _consumeBadgeSocketIntent() {
    const reason = _badgeSocketCloseIntent || '';
    _badgeSocketCloseIntent = '';
    return reason;
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

  function _closeBadgeSocket(reason) {
    _clearBadgeSocketReconnect();
    if (_badgeSocketHeartbeatTimer) {
      clearInterval(_badgeSocketHeartbeatTimer);
      _badgeSocketHeartbeatTimer = null;
    }
    _setBadgeSocketIntent(reason || 'unknown');
    if (!_badgeSocket) return;
    const socket = _badgeSocket;
    _badgeSocket = null;
    _badgeSocketLastActivityAt = 0;
    try {
      socket.onopen = null;
      socket.onmessage = null;
      socket.onerror = null;
      socket.__nwCloseIntent = _badgeSocketCloseIntent || String(reason || 'unknown');
      socket.close(1000, _badgeSocketCloseIntent || 'badge socket closing');
    } catch (_) {}
  }

  function _startBadgeSocketHeartbeat() {
    if (_badgeSocketHeartbeatTimer) {
      clearInterval(_badgeSocketHeartbeatTimer);
    }
    _badgeSocketHeartbeatTimer = window.setInterval(() => {
      if (!_badgeSocket) return;
      if (_badgeSocketLastActivityAt && (Date.now() - _badgeSocketLastActivityAt) > _badgeSocketHeartbeatTimeoutMs) {
        try {
          _badgeSocket.close(4008, 'heartbeat_timeout');
        } catch (_) {}
        return;
      }
      try {
        _badgeSocket.send(JSON.stringify({ type: 'ping' }));
      } catch (_) {}
    }, _badgeSocketHeartbeatIntervalMs);
  }

  function _canUseBadgeRealtime() {
    return Auth.isLoggedIn() && _badgeOwnsLeadership && !_shouldSkipBadgeRealtime();
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

  function _jwtExpiresSoon(token, skewSeconds) {
    try {
      const parts = String(token || '').split('.');
      if (parts.length < 2) return false;
      const payload = JSON.parse(atob(parts[1].replace(/-/g, '+').replace(/_/g, '/')));
      const exp = Number(payload && payload.exp);
      if (!Number.isFinite(exp)) return false;
      return (exp * 1000) <= (Date.now() + Math.max(10, Number(skewSeconds) || 60) * 1000);
    } catch (_) {
      return false;
    }
  }

  async function _badgeSocketToken() {
    let token = Auth.getAccessToken();
    if (token && _jwtExpiresSoon(token, 75) && typeof Auth.refreshAccessToken === 'function') {
      try {
        const refreshed = await Auth.refreshAccessToken();
        if (refreshed) token = Auth.getAccessToken();
      } catch (_) {}
    }
    if (!token) return null;
    return token;
  }

  function _badgeSocketUrl() {
    try {
      const url = new URL('/ws/notifications/', ApiClient.BASE || window.location.origin);
      url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:';
      return url.toString();
    } catch (_) {
      return null;
    }
  }

  function _scheduleBadgeSocketReconnect() {
    if (_badgeSocketReconnectTimer || _badgeSocketConnectPromise || !_canUseBadgeRealtime()) {
      return;
    }
    const delay = _badgeSocketBackoffMs;
    _badgeSocketReconnectTimer = window.setTimeout(() => {
      _badgeSocketReconnectTimer = null;
      void _connectBadgeSocket();
    }, delay);
    _badgeSocketBackoffMs = Math.min(_badgeSocketBackoffMaxMs, Math.max(1000, delay * 2));
  }

  function _classifyBadgeSocketClose(event, socket, explicitReason) {
    const reason = String(explicitReason || socket && socket.__nwCloseIntent || '').trim().toLowerCase();
    if (reason === 'navigation' || reason === 'logout' || reason === 'auth_blocked') {
      return reason;
    }
    const code = Number(event && event.code);
    if (code === 4401 || code === 4403) return 'auth_blocked';
    if ((typeof navigator !== 'undefined' && navigator.onLine === false) || code === 1006 || code === 1012 || code === 1013 || code === 4408) {
      return 'network';
    }
    return 'unknown';
  }

  function _shouldReconnectBadgeSocket(reason) {
    return (reason === 'network' || reason === 'unknown') && _canUseBadgeRealtime();
  }

  function _logBadgeSocketClose(reason, socket) {
    const openedAt = Number(socket && socket.__nwOpenedAt) || 0;
    if (!openedAt) return;
    if ((Date.now() - openedAt) < _badgeShortConnectionMs && (reason === 'network' || reason === 'unknown')) {
      try {
        console.warn('notifications websocket closed too quickly:', reason);
      } catch (_) {}
    }
  }

  function _handleBadgeSocketMessage(rawEvent) {
    let payload = null;
    try {
      payload = JSON.parse(rawEvent.data || '{}');
    } catch (_) {
      return;
    }
    _badgeSocketLastActivityAt = Date.now();
    if (!payload) return;
    if (payload.type === 'ping') {
      try {
        if (_badgeSocket) _badgeSocket.send(JSON.stringify({ type: 'pong' }));
      } catch (_) {}
      return;
    }
    if (payload.type === 'pong' || payload.type === 'connected') return;
    if (payload.type !== 'notification.created') return;
    try {
      window.dispatchEvent(new CustomEvent('nw:notification-created', {
        detail: payload.notification || {},
      }));
    } catch (_) {}
    _syncBadgePolling(true);
  }

  function _connectBadgeSocket() {
    if (!_canUseBadgeRealtime()) {
      _closeBadgeSocket('auth_blocked');
      return Promise.resolve(false);
    }
    if (_badgeSocket || _badgeSocketReconnectTimer || _badgeSocketConnectPromise) {
      return _badgeSocketConnectPromise || Promise.resolve(true);
    }
    const connectTask = (async () => {
      const url = _badgeSocketUrl();
      if (!url) return false;
      const token = await _badgeSocketToken();
      if (!token) return false;

      let socket;
      try {
        socket = new WebSocket(url, ['nawafeth.jwt', token]);
      } catch (_) {
        _scheduleBadgeSocketReconnect();
        return false;
      }

      socket.__nwCloseIntent = '';
      socket.__nwOpenedAt = 0;
      _badgeSocket = socket;
      socket.onopen = () => {
        if (_badgeSocket !== socket) return;
        _consumeBadgeSocketIntent();
        _badgeSocketBackoffMs = 1000;
        _badgeSocketLastActivityAt = Date.now();
        _badgeSocketOpenedAt = _badgeSocketLastActivityAt;
        socket.__nwOpenedAt = _badgeSocketOpenedAt;
        _startBadgeSocketHeartbeat();
        _syncBadgePolling(false);
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
        if (_badgeSocketHeartbeatTimer) {
          clearInterval(_badgeSocketHeartbeatTimer);
          _badgeSocketHeartbeatTimer = null;
        }
        const explicitReason = _consumeBadgeSocketIntent();
        const closeReason = _classifyBadgeSocketClose(event, socket, explicitReason);
        _badgeSocketLastCloseReason = closeReason;
        _logBadgeSocketClose(closeReason, socket);
        if (closeReason === 'auth_blocked' && event && event.code === 4401 && typeof Auth.refreshAccessToken === 'function') {
          try {
            const refreshed = await Auth.refreshAccessToken();
            if (refreshed && _canUseBadgeRealtime()) {
              void _connectBadgeSocket();
              return;
            }
          } catch (_) {}
        }
        if (_shouldReconnectBadgeSocket(closeReason)) {
          _scheduleBadgeSocketReconnect();
        }
      };
      return true;
    })();
    _badgeSocketConnectPromise = connectTask.finally(() => {
      if (_badgeSocketConnectPromise && _badgeSocketConnectPromise.__nwSourcePromise === connectTask) {
        _badgeSocketConnectPromise = null;
      }
    });
    _badgeSocketConnectPromise.__nwSourcePromise = connectTask;
    return _badgeSocketConnectPromise;
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
      _shutdownBadgeRealtime('logout');
      return;
    }

    const notificationsBadges = _ensureBadges('a[href="/notifications/"], #btn-notifications');
    const chatsBadges = _ensureBadges('a[href="/chats/"], #btn-chat');
    if (!notificationsBadges.length && !chatsBadges.length) {
      _shutdownBadgeRealtime('unknown');
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
      const now = Date.now();
      if (
        !forceLeadership &&
        _badgeSocket &&
        _badgeSocket.readyState === WebSocket.OPEN &&
        _badgeSocketLastActivityAt &&
        (now - _badgeSocketLastActivityAt) < _badgeSocketHeartbeatTimeoutMs &&
        _badgeLastFetchAt &&
        (now - _badgeLastFetchAt) < _badgeHealthySyncIntervalMs
      ) {
        return;
      }
      const mode = _activeMode();
      const res = await ApiClient.get(
        '/api/core/unread-badges/?mode=' + mode,
        null,
        { forceRefresh: !!forceLeadership }
      );
      if (res?.status === 401) {
        _badgeUnauthorizedUntil = Date.now() + (2 * 60 * 1000);
        _clearUnreadBadges();
        _shutdownBadgeRealtime('auth_blocked');
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
      _badgeLastFetchAt = Date.now();
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
    _closeBadgeSocket('unknown');
    _releaseBadgeLeadership();
  }

  function _shutdownBadgeRealtime(reason) {
    if (_badgePollTimer) {
      clearInterval(_badgePollTimer);
      _badgePollTimer = null;
    }
    _closeBadgeSocket(reason || 'unknown');
    _releaseBadgeLeadership();
  }

  function _startBadgePolling(forceLeadership) {
    if (!Auth.isLoggedIn() || !_isPageActive()) {
      return;
    }
    if (!_claimBadgeLeadership(forceLeadership)) {
      _closeBadgeSocket('navigation');
      if (_badgePollTimer) {
        clearInterval(_badgePollTimer);
        _badgePollTimer = null;
      }
      const snapshot = _readStorageJson(_badgeSnapshotKey);
      if (snapshot) _applyBadgePayload(snapshot);
      return;
    }
    void _connectBadgeSocket();
    if (_badgePollTimer) return;
    _badgePollTimer = window.setInterval(() => {
      if (!_badgeOwnsLeadership || !Auth.isLoggedIn()) {
        _shutdownBadgeRealtime(!Auth.isLoggedIn() ? 'logout' : 'navigation');
        return;
      }
      if (!_isPageActive()) {
        return;
      }
      if (!_claimBadgeLeadership(false)) {
        _shutdownBadgeRealtime('navigation');
        return;
      }
      void _connectBadgeSocket();
      _loadUnreadBadges(false);
    }, _badgePollIntervalMs);
  }

  function _syncBadgePolling(forceRefresh) {
    if (!Auth.isLoggedIn()) {
      _shutdownBadgeRealtime('logout');
      return;
    }
    if (!_isPageActive()) {
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
        if (document.visibilityState === 'visible') _syncBadgePolling(false);
      });
      window.addEventListener('focus', () => _syncBadgePolling(false));
      window.addEventListener('pageshow', () => _syncBadgePolling(false));
      window.addEventListener('pagehide', () => _shutdownBadgeRealtime('navigation'));
      window.addEventListener('beforeunload', () => _shutdownBadgeRealtime('navigation'));
      window.addEventListener('storage', _handleBadgeStorage);
      window.addEventListener('nw:badge-refresh', () => _syncBadgePolling(true));
      window.addEventListener('nw:auth-logout', () => {
        _badgeUnauthorizedUntil = 0;
        _clearUnreadBadges();
        _shutdownBadgeRealtime('logout');
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
    __test: window.__NW_ENABLE_TEST_HOOKS__ ? {
      connectBadgeSocket: _connectBadgeSocket,
      claimBadgeLeadership: _claimBadgeLeadership,
      loadUnreadBadges: _loadUnreadBadges,
      syncBadgePolling: _syncBadgePolling,
      shutdownBadgeRealtime: _shutdownBadgeRealtime,
      debugState() {
        return {
          hasSocket: !!_badgeSocket,
          hasConnectPromise: !!_badgeSocketConnectPromise,
          hasReconnectTimer: !!_badgeSocketReconnectTimer,
          lastCloseReason: _badgeSocketLastCloseReason,
          ownsLeadership: _badgeOwnsLeadership,
          refreshInFlight: _badgeRefreshInFlight,
        };
      },
    } : undefined,
  };
})();

window.Nav = Nav;

if (window.__NW_ENABLE_TEST_HOOKS__) {
  window.__NW_TEST_HOOKS__ = window.__NW_TEST_HOOKS__ || {};
  window.__NW_TEST_HOOKS__.nav = Nav.__test;
}
