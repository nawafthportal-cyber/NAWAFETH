/* ===================================================================
   profilePage.js — User profile ("نافذتي") page
   GET /api/accounts/me/
   GET /api/providers/me/profile/   (if provider mode enabled)
   GET /api/marketplace/provider/urgent/available/
   GET /api/marketplace/provider/requests/?status_group=new|completed
   =================================================================== */
'use strict';

const ProfilePage = (() => {
  const MODE_KEY = 'nw_account_mode';
  let _profile = null;
  let _providerProfile = null;
  let _mode = 'client'; // client | provider

  function init() {
    if (!Auth.isLoggedIn()) { _showGate(); return; }
    _hideGate();
    _bindModeToggle();
    _bindStaticActions();
    _loadProfile();
  }

  function _showGate() {
    const g = document.getElementById('auth-gate');
    const c = document.getElementById('profile-content');
    if (g) g.classList.remove('hidden');
    if (c) c.classList.add('hidden');
  }

  function _hideGate() {
    const g = document.getElementById('auth-gate');
    const c = document.getElementById('profile-content');
    if (g) g.classList.add('hidden');
    if (c) c.classList.remove('hidden');
  }

  function _bindModeToggle() {
    const toggle = document.getElementById('profile-mode-toggle');
    if (!toggle) return;

    toggle.addEventListener('click', (e) => {
      const btn = e.target.closest('.mode-chip[data-mode]');
      if (!btn) return;
      const nextMode = btn.dataset.mode === 'provider' ? 'provider' : 'client';
      if (nextMode === _mode) return;
      if (nextMode === 'provider' && !_canSwitchToProvider()) return;

      _mode = nextMode;
      _saveMode(_mode);
      _renderAll();
      if (_mode === 'provider') _loadProviderKpis();
    });
  }

  function _bindStaticActions() {
    const qrBtn = document.getElementById('btn-qrcode');
    if (qrBtn) {
      qrBtn.onclick = () => {
        alert('ميزة QR ستكون متاحة قريبًا.');
      };
    }
  }

  async function _loadProfile() {
    const profile = await Auth.getProfile(true);
    if (!profile) {
      _showGate();
      return;
    }

    _profile = profile;
    _providerProfile = null;

    if (_canSwitchToProvider()) {
      const providerRes = await ApiClient.get('/api/providers/me/profile/');
      if (providerRes.ok && providerRes.data && typeof providerRes.data === 'object') {
        _providerProfile = providerRes.data;
      }
    }

    const preferred = _getSavedMode();
    _mode = (_canSwitchToProvider() && preferred === 'provider') ? 'provider' : 'client';

    _renderAll();
    if (_mode === 'provider') _loadProviderKpis();
  }

  function _renderAll() {
    if (!_profile) return;
    _renderModeToggle();
    _renderHeader();
    _renderStats();
    _renderQuickActions();
    _renderMenuActions();
    _renderProviderSection();
    _toggleProviderStrip(_mode === 'provider' && _canSwitchToProvider());
  }

  function _renderModeToggle() {
    const toggle = document.getElementById('profile-mode-toggle');
    if (!toggle) return;

    const canSwitch = _canSwitchToProvider();
    toggle.classList.toggle('hidden', !canSwitch);

    const clientBtn = document.getElementById('mode-client-btn');
    const providerBtn = document.getElementById('mode-provider-btn');
    if (clientBtn) clientBtn.classList.toggle('active', _mode !== 'provider');
    if (providerBtn) providerBtn.classList.toggle('active', _mode === 'provider');
  }

  function _renderHeader() {
    const useProviderMode = _mode === 'provider' && !!_providerProfile;
    const coverPath = useProviderMode ? _providerProfile.cover_image : _profile.cover_image;
    const avatarPath = useProviderMode ? _providerProfile.profile_image : _profile.profile_image;
    const name = useProviderMode
      ? (_providerProfile.display_name || _displayName(_profile))
      : _displayName(_profile);

    const coverEl = document.getElementById('profile-cover');
    if (coverEl) {
      coverEl.innerHTML = '';
      if (coverPath) {
        coverEl.appendChild(UI.lazyImg(ApiClient.mediaUrl(coverPath), ''));
      } else {
        coverEl.appendChild(UI.el('div', { className: 'profile-cover-placeholder' }));
      }
    }

    const avatarEl = document.getElementById('profile-avatar');
    if (avatarEl) {
      avatarEl.innerHTML = '';
      if (avatarPath) {
        avatarEl.appendChild(UI.lazyImg(ApiClient.mediaUrl(avatarPath), ''));
      } else {
        avatarEl.textContent = (name || '؟').charAt(0);
      }
    }

    _setText('profile-name', name);
    _setText('profile-username', _profile.username ? '@' + _profile.username : '');
    _setText('profile-role', _mode === 'provider' ? 'مقدم خدمة' : _roleLabel(_profile.role_state));
  }

  function _renderStats() {
    if (!_profile) return;

    const isProviderMode = _mode === 'provider';
    const following = _toInt(_profile.following_count);
    const likes = isProviderMode
      ? _toInt(_profile.provider_likes_received_count || _profile.likes_count)
      : _toInt(_profile.likes_count);
    const favorites = _toInt(
      _profile.favorites_media_count ||
      _profile.favorites_count ||
      _profile.bookmarks_count
    );

    _setText('stat-following', following);
    _setText('stat-likes', likes);
    _setText('stat-favorites', favorites);

    _setText('stat-following-label', isProviderMode ? 'يتابع' : 'متابعاتي');
    _setText('stat-likes-label', 'إعجابات');
    _setText('stat-favorites-label', isProviderMode ? 'محفوظ' : 'مفضلتي');
  }

  function _renderQuickActions() {
    const isProviderMode = _mode === 'provider';
    const actions = {
      orders: {
        href: '/orders/',
        label: isProviderMode ? 'طلبات الخدمة' : 'طلباتي',
      },
      interactive: {
        href: '/interactive/',
        label: isProviderMode ? 'المتابعون' : 'تفاعلي',
      },
      notifications: {
        href: '/notifications/',
        label: 'الإشعارات',
      },
      last: isProviderMode
        ? { href: '/add-service/', label: 'خدماتي' }
        : { href: '/chats/', label: 'المحادثات' },
    };

    _setAction('action-orders', 'action-orders-label', actions.orders.href, actions.orders.label);
    _setAction('action-interactive', 'action-interactive-label', actions.interactive.href, actions.interactive.label);
    _setAction('action-notifications', 'action-notifications-label', actions.notifications.href, actions.notifications.label);
    _setAction('action-last', 'action-last-label', actions.last.href, actions.last.label);
  }

  function _renderMenuActions() {
    const isProviderMode = _mode === 'provider';
    const savedBtn = document.getElementById('btn-saved');
    if (savedBtn) {
      const textEl = savedBtn.querySelector('span');
      if (textEl) textEl.textContent = isProviderMode ? 'إدارة الخدمات' : 'المحفوظات';
      savedBtn.onclick = () => {
        window.location.href = isProviderMode ? '/add-service/' : '/interactive/';
      };
    }

    _setText('provider-section-title', isProviderMode ? 'لوحة مقدم الخدمة' : 'ملفي كمقدم خدمة');
  }

  async function _loadProviderKpis() {
    const strip = document.getElementById('provider-dashboard-strip');
    if (!strip || strip.classList.contains('hidden')) return;

    const [urgentRes, newRes, completedRes] = await Promise.all([
      ApiClient.get('/api/marketplace/provider/urgent/available/'),
      ApiClient.get('/api/marketplace/provider/requests/?status_group=new'),
      ApiClient.get('/api/marketplace/provider/requests/?status_group=completed'),
    ]);

    _setText('kpi-urgent', _responseCount(urgentRes));
    _setText('kpi-new', _responseCount(newRes));
    _setText('kpi-completed', _responseCount(completedRes));
  }

  function _toggleProviderStrip(show) {
    const strip = document.getElementById('provider-dashboard-strip');
    if (!strip) return;
    strip.classList.toggle('hidden', !show);
    if (!show) {
      _setText('kpi-urgent', 0);
      _setText('kpi-new', 0);
      _setText('kpi-completed', 0);
    }
  }

  function _setAction(actionId, labelId, href, label) {
    const action = document.getElementById(actionId);
    if (action) action.setAttribute('href', href);
    _setText(labelId, label);
  }

  function _displayName(profile) {
    const fullName = [profile.first_name || '', profile.last_name || '']
      .join(' ')
      .trim();
    return fullName || profile.username || profile.phone || 'مستخدم';
  }

  function _renderProviderSection() {
    const section = document.getElementById('provider-section');
    if (!section) return;

    if (!_providerProfile) {
      section.classList.add('hidden');
      return;
    }
    section.classList.remove('hidden');

    const card = document.getElementById('provider-card');
    if (!card) return;
    card.innerHTML = '';

    const p = _providerProfile;
    const link = UI.el('a', { className: 'provider-card', href: '/provider/' + p.id + '/' });

    const cover = UI.el('div', { className: 'provider-cover' });
    if (p.cover_image) cover.appendChild(UI.lazyImg(ApiClient.mediaUrl(p.cover_image), ''));
    link.appendChild(cover);

    const info = UI.el('div', { className: 'provider-info' });
    const avatar = UI.el('div', { className: 'provider-avatar' });
    if (p.profile_image) avatar.appendChild(UI.lazyImg(ApiClient.mediaUrl(p.profile_image), ''));
    else avatar.textContent = (p.display_name || '').charAt(0) || '؟';
    info.appendChild(avatar);

    const meta = UI.el('div', { className: 'provider-meta' });
    meta.appendChild(UI.el('span', { className: 'provider-name', textContent: p.display_name || '' }));
    if (p.city) {
      meta.appendChild(UI.el('div', { className: 'provider-city', textContent: p.city }));
    }
    info.appendChild(meta);
    link.appendChild(info);

    card.appendChild(link);
  }

  function _responseCount(res) {
    if (!res || !res.ok || !res.data) return 0;
    if (Array.isArray(res.data)) return res.data.length;
    if (Array.isArray(res.data.results)) return res.data.results.length;
    if (typeof res.data.count === 'number') return res.data.count;
    return 0;
  }

  function _canSwitchToProvider() {
    if (!_profile) return false;
    return !!(
      _profile.role_state === 'provider' ||
      _profile.is_provider ||
      _profile.has_provider_profile
    );
  }

  function _getSavedMode() {
    try {
      return sessionStorage.getItem(MODE_KEY) === 'provider' ? 'provider' : 'client';
    } catch {
      return 'client';
    }
  }

  function _saveMode(mode) {
    try {
      sessionStorage.setItem(MODE_KEY, mode);
    } catch {}
  }

  function _roleLabel(role) {
    const map = { client: 'عميل', provider: 'مقدم خدمة', admin: 'مشرف' };
    return map[role] || role || 'مستخدم';
  }

  function _toInt(value) {
    const n = parseInt(value, 10);
    return Number.isFinite(n) ? n : 0;
  }

  function _setText(id, val) {
    const el = document.getElementById(id);
    if (el) el.textContent = val;
  }

  // Boot
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else { init(); }

  return {};
})();
