/* ===================================================================
   profilePage.js — User profile ("نافذتي") page
   GET /api/accounts/me/
   GET /api/accounts/wallet/
   GET /api/providers/me/profile/   (if provider)
   =================================================================== */
'use strict';

const ProfilePage = (() => {
  function init() {
    if (!Auth.isLoggedIn()) { _showGate(); return; }
    _hideGate();
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

  async function _loadProfile() {
    // Fetch profile
    const profile = await Auth.getProfile(true);
    if (!profile) { _showGate(); return; }

    // Avatar
    const avatarEl = document.getElementById('profile-avatar');
    if (profile.profile_image) {
      avatarEl.innerHTML = '';
      avatarEl.appendChild(UI.lazyImg(ApiClient.mediaUrl(profile.profile_image), ''));
    } else {
      avatarEl.textContent = (profile.full_name || profile.phone || '؟').charAt(0);
    }

    // Cover
    const coverEl = document.getElementById('profile-cover');
    if (profile.cover_image) {
      coverEl.innerHTML = '';
      coverEl.appendChild(UI.lazyImg(ApiClient.mediaUrl(profile.cover_image), ''));
    }

    // Name, username, role
    const nameEl = document.getElementById('profile-name');
    namesEl(nameEl, profile);
    document.getElementById('profile-username').textContent = profile.username ? '@' + profile.username : '';
    document.getElementById('profile-role').textContent = _roleLabel(profile.role_state);

    // Stats
    _setText('stat-following', profile.following_count || 0);
    _setText('stat-likes', profile.likes_count || 0);
    _setText('stat-favorites', profile.favorites_count || profile.bookmarks_count || 0);

    // Settings click
    const settingsBtn = document.getElementById('btn-settings');
    if (settingsBtn) settingsBtn.addEventListener('click', () => { window.location.href = '/settings/'; });

    // Provider section
    if (profile.role_state === 'provider' || profile.is_provider) {
      _loadProvider();
    }
  }

  function namesEl(el, profile) {
    el.textContent = '';
    el.appendChild(UI.text(profile.full_name || profile.display_name || profile.phone || 'مستخدم'));
    if (profile.is_verified_blue) {
      el.appendChild(UI.text(' '));
      el.appendChild(UI.icon('verified_blue', 16, '#2196F3'));
    }
  }

  async function _loadWallet() {
    const el = document.getElementById('wallet-balance');
    if (!el) return;
    const res = await ApiClient.get('/api/accounts/wallet/');
    if (res.ok && res.data) {
      const balance = res.data.balance || res.data.amount || 0;
      el.textContent = parseFloat(balance).toLocaleString('ar-SA') + ' ر.س';
    }
  }

  async function _loadProvider() {
    const section = document.getElementById('provider-section');
    if (!section) return;

    const res = await ApiClient.get('/api/providers/me/profile/');
    if (!res.ok || !res.data) return;

    const p = res.data;
    section.classList.remove('hidden');

    const card = document.getElementById('provider-card');
    if (!card) return;
    card.innerHTML = '';

    // Provider card
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
    info.appendChild(meta);
    link.appendChild(info);

    card.appendChild(link);
  }

  function _roleLabel(role) {
    const map = { client: 'عميل', provider: 'مقدم خدمة', admin: 'مشرف' };
    return map[role] || role || 'مستخدم';
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
