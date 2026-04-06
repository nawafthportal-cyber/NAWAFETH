/* ===================================================================
   profilePage.js v2.0 — "نافذتي" profile page (1:1 Flutter match)
   ───────────────────────────────────────────────────────────────────
   GET  /api/accounts/me/
   GET  /api/providers/me/profile/
   PATCH /api/accounts/me/   (multipart: profile_image / cover_image)
   GET  /api/marketplace/provider/urgent/available/
   GET  /api/marketplace/provider/requests/?status_group=new|completed
   =================================================================== */
'use strict';

const ProfilePage = (() => {
  const MODE_KEY = 'nw_account_mode';
  let _profile = null;
  let _mode = 'client';

  /* ──────── Init ──────── */
  function init() {
    if (!Auth.isLoggedIn()) { _showGate(); return; }
    _hideGate();
    _bindModeToggle();
    _bindStaticActions();
    _bindImageUploads();
    _loadProfile();
  }

  /* ──────── Auth gate ──────── */
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

  /* ──────── Mode toggle binding ──────── */
  function _bindModeToggle() {
    const toggle = document.getElementById('profile-mode-toggle');
    if (!toggle) return;
    toggle.addEventListener('click', (e) => {
      const btn = e.target.closest('.pv2-mode-chip[data-mode]');
      if (!btn) return;
      const nextMode = btn.dataset.mode === 'provider' ? 'provider' : 'client';
      if (nextMode === _mode) return;
      if (nextMode === 'provider') {
        if (!_canSwitchToProvider()) return;
        _saveMode('provider');
        window.location.href = '/provider-dashboard/';
        return;
      }
      _mode = 'client';
      _saveMode('client');
      _renderAll();
    });
  }

  /* ──────── Static button binding ──────── */
  function _bindStaticActions() {
    const qrBtn = document.getElementById('btn-qrcode');
    if (qrBtn) qrBtn.onclick = () => { window.location.href = '/my-qr/'; };

    const settingsBtn = document.getElementById('btn-settings');
    if (settingsBtn) settingsBtn.onclick = () => { window.location.href = '/login-settings/'; };
  }

  /* ──────── Image upload binding ──────── */
  function _bindImageUploads() {
    const coverInput = document.getElementById('input-cover-upload');
    const avatarInput = document.getElementById('input-avatar-upload');

    if (coverInput) {
      coverInput.addEventListener('change', () => {
        if (coverInput.files && coverInput.files[0]) _uploadImage(coverInput.files[0], 'cover_image');
        coverInput.value = '';
      });
    }
    if (avatarInput) {
      avatarInput.addEventListener('change', () => {
        if (avatarInput.files && avatarInput.files[0]) _uploadImage(avatarInput.files[0], 'profile_image');
        avatarInput.value = '';
      });
    }
  }

  async function _uploadImage(file, fieldName) {
    if (!file.type.startsWith('image/')) return;

    // Immediate preview
    const previewUrl = URL.createObjectURL(file);
    if (fieldName === 'profile_image') {
      const av = document.getElementById('profile-avatar');
      if (av) { av.innerHTML = ''; const img = document.createElement('img'); img.src = previewUrl; av.appendChild(img); }
    } else {
      const cv = document.getElementById('profile-cover');
      if (cv) { cv.innerHTML = ''; const img = document.createElement('img'); img.src = previewUrl; cv.appendChild(img); }
    }

    _toggleUploadProgress(true);

    const fd = new FormData();
    fd.append(fieldName, file);

    const res = await ApiClient.request('/api/accounts/me/', {
      method: 'PATCH',
      body: fd,
      formData: true,
    });

    _toggleUploadProgress(false);

    if (res.ok) {
      if (Auth.clearProfileCache) Auth.clearProfileCache();
      await _loadProfile();
    } else {
      alert('تعذر رفع الصورة');
    }
  }

  function _toggleUploadProgress(show) {
    const bar = document.getElementById('upload-progress');
    if (bar) bar.classList.toggle('hidden', !show);
  }

  /* ──────── Load profile data ──────── */
  async function _loadProfile() {
    const profileRes = await ApiClient.get('/api/accounts/me/?mode=client');
    const profile = (profileRes && profileRes.ok && profileRes.data) ? profileRes.data : null;
    if (!profile) { _showGate(); return; }

    _profile = profile;

    const preferred = _getSavedMode();
    if (_canSwitchToProvider() && preferred === 'provider') {
      window.location.href = '/provider-dashboard/';
      return;
    }
    _mode = 'client';

    _renderAll();
  }

  /* ──────── Render orchestrator ──────── */
  function _renderAll() {
    if (!_profile) return;
    _renderModeToggle();
    _renderHeader();
    _renderStats();
    _renderQuickActions();
    _renderMenu();
    _renderProviderCTA();
    _renderProviderSection();
  }

  /* ──────── Mode toggle render ──────── */
  function _renderModeToggle() {
    const toggle = document.getElementById('profile-mode-toggle');
    if (!toggle) return;
    const canSwitch = _canSwitchToProvider();
    toggle.classList.toggle('hidden', !canSwitch);

    const clientBtn = document.getElementById('mode-client-btn');
    const providerBtn = document.getElementById('mode-provider-btn');
    if (clientBtn) clientBtn.classList.toggle('active', _mode !== 'provider');
    if (providerBtn) providerBtn.classList.toggle('active', false);
  }

  /* ──────── Header render (cover + avatar + name + username) ──────── */
  function _renderHeader() {
    const coverPath = _profile.cover_image;
    const avatarPath = _profile.profile_image;
    const name = _displayName(_profile);

    // Cover
    const coverEl = document.getElementById('profile-cover');
    if (coverEl) {
      coverEl.innerHTML = '';
      if (coverPath) {
        const img = document.createElement('img');
        img.src = ApiClient.mediaUrl(coverPath);
        img.alt = '';
        coverEl.appendChild(img);
      } else {
        coverEl.appendChild(UI.el('div', { className: 'profile-cover-placeholder' }));
      }
      // Re-inject the top-bar (it gets cleared with innerHTML)
      const bar = document.createElement('div');
      bar.className = 'pv2-cover-bar';
      bar.innerHTML = `
        <label class="pv2-mini-btn" title="تغيير الغلاف">
          <input type="file" accept="image/*" id="input-cover-upload" hidden>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="#fff"><path d="M12 15.2l3.2-3.2H14V8h-4v4H8.8L12 15.2zM20 4h-3.17L15 2H9L7.17 4H4c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V6c0-1.1-.9-2-2-2zm0 14H4V6h4.05l1.83-2h4.24l1.83 2H20v12z"/><circle cx="12" cy="12" r="3.2"/></svg>
        </label>`;
      coverEl.appendChild(bar);
      // Re-bind file input
      const newCoverInput = bar.querySelector('#input-cover-upload');
      if (newCoverInput) {
        newCoverInput.addEventListener('change', () => {
          if (newCoverInput.files && newCoverInput.files[0]) _uploadImage(newCoverInput.files[0], 'cover_image');
          newCoverInput.value = '';
        });
      }
    }

    // Avatar
    const avatarEl = document.getElementById('profile-avatar');
    if (avatarEl) {
      // Preserve the file input
      const existingInput = avatarEl.querySelector('#input-avatar-upload');
      avatarEl.innerHTML = '';
      if (avatarPath) {
        const img = document.createElement('img');
        img.src = ApiClient.mediaUrl(avatarPath);
        img.alt = '';
        avatarEl.appendChild(img);
      } else {
        const initials = document.createElement('span');
        initials.className = 'pv2-avatar-initials';
        initials.textContent = (name || '؟').charAt(0);
        avatarEl.appendChild(initials);
      }
      // Re-add the hidden file input
      const input = document.createElement('input');
      input.type = 'file';
      input.accept = 'image/*';
      input.id = 'input-avatar-upload';
      input.hidden = true;
      avatarEl.appendChild(input);
      input.addEventListener('change', () => {
        if (input.files && input.files[0]) _uploadImage(input.files[0], 'profile_image');
        input.value = '';
      });
    }

    _setText('profile-name', name);
    _setText('profile-username', _profile.username ? '@' + _profile.username : '');
  }

  /* ──────── Stats render ──────── */
  function _renderStats() {
    if (!_profile) return;
    const following = _toInt(_profile.following_count);
    const likes = _toInt(_profile.likes_count);
    const favorites = _toInt(
      _profile.favorites_media_count || _profile.favorites_count || _profile.bookmarks_count
    );

    _setText('stat-following', following);
    _setText('stat-likes', likes);
    _setText('stat-favorites', favorites);
    _setText('stat-following-label', 'أتابع');
    _setText('stat-likes-label', 'إعجاب');
    _setText('stat-favorites-label', 'مفضلتي');
  }

  /* ──────── Quick actions render ──────── */
  function _renderQuickActions() {
    _setAction('action-orders', 'action-orders-label', '/orders/', 'طلباتي');
    _setAction('action-saved', 'action-saved-label', '/interactive/?tab=favorites', 'محفوظاتي');
    _setAction('action-interactive', 'action-interactive-label', '/interactive/', 'تفاعلي');
  }

  /* ──────── Menu render ──────── */
  function _renderMenu() {
    // Settings subtitle (email or phone)
    const sub = _profile.email || _profile.phone || '';
    _setText('menu-settings-sub', sub);

    // Saved label
    const savedLabel = document.getElementById('menu-saved-label');
    if (savedLabel) savedLabel.textContent = 'المحفوظات';

    const savedBtn = document.getElementById('btn-saved');
    if (savedBtn) {
      savedBtn.onclick = () => { window.location.href = '/interactive/'; };
    }

    // Saved badge count
    const badge = document.getElementById('menu-saved-badge');
    if (badge) {
      const count = _toInt(_profile.favorites_media_count || _profile.favorites_count || _profile.bookmarks_count);
      badge.textContent = String(count);
      badge.classList.remove('hidden');
    }
  }

  /* ──────── Provider CTA (for non-providers) ──────── */
  function _renderProviderCTA() {
    const cta = document.getElementById('provider-cta');
    if (!cta) return;
    const isProvider = _canSwitchToProvider();
    cta.classList.toggle('hidden', isProvider);
  }

  function _toggleProviderStrip(show) {
    const strip = document.getElementById('provider-dashboard-strip');
    if (!strip) return;
    strip.classList.toggle('hidden', !show);
    if (!show) { _setText('kpi-urgent', 0); _setText('kpi-new', 0); _setText('kpi-completed', 0); }
  }

  /* ──────── Provider section card ──────── */
  function _renderProviderSection() {
    _toggleProviderStrip(false);
    const section = document.getElementById('provider-section');
    if (section) section.classList.add('hidden');
  }

  /* ──────── Helpers ──────── */
  function _setAction(actionId, labelId, href, label) {
    const a = document.getElementById(actionId);
    if (a) a.setAttribute('href', href);
    _setText(labelId, label);
  }

  function _displayName(profile) {
    return [profile.first_name || '', profile.last_name || ''].join(' ').trim()
      || profile.username || profile.phone || 'مستخدم';
  }

  function _canSwitchToProvider() {
    if (!_profile) return false;
    return !!(_profile.role_state === 'provider' || _profile.is_provider || _profile.has_provider_profile);
  }

  function _getSavedMode() {
    try { return sessionStorage.getItem(MODE_KEY) === 'provider' ? 'provider' : 'client'; }
    catch { return 'client'; }
  }
  function _saveMode(mode) {
    try { sessionStorage.setItem(MODE_KEY, mode); } catch {}
  }

  function _toInt(v) { const n = parseInt(v, 10); return Number.isFinite(n) ? n : 0; }
  function _setText(id, val) { const el = document.getElementById(id); if (el) el.textContent = val; }

  /* ──────── Boot ──────── */
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else { init(); }

  return {};
})();
