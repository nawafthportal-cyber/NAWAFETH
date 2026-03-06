/* ===================================================================
   interactivePage.js — 1:1 parity with Flutter InteractiveScreen
   =================================================================== */
'use strict';

const InteractivePage = (() => {
  let _activeTab = 'following';
  let _mode = 'client';
  let _isProviderMode = false;
  let _favorites = [];
  const _roleModes = ['client', 'provider'];

  async function init() {
    _setInitialLoading(true);

    const loggedIn = !!Auth.isLoggedIn();
    if (!loggedIn) {
      _setInitialLoading(false);
      _showGate();
      return;
    }

    _mode = _resolveMode();
    _isProviderMode = _mode === 'provider';
    _hideGate();
    _renderTabs();
    _bindTabs();
    _switchTab('following');
    _setInitialLoading(false);
    await _loadAll();
  }

  function _setInitialLoading(show) {
    const loading = document.getElementById('interactive-loading');
    if (loading) loading.classList.toggle('hidden', !show);
  }

  function _resolveMode() {
    const mode = (sessionStorage.getItem('nw_account_mode') || 'client').toLowerCase();
    return mode === 'provider' ? 'provider' : 'client';
  }

  function _withMode(path, modeOverride) {
    const activeMode = (modeOverride || _mode || 'client').toLowerCase() === 'provider' ? 'provider' : 'client';
    const sep = path.includes('?') ? '&' : '?';
    return path + sep + 'mode=' + encodeURIComponent(activeMode);
  }

  function _uniqueModes() {
    const first = (_mode || 'client').toLowerCase() === 'provider' ? 'provider' : 'client';
    return first === 'provider' ? ['provider', 'client'] : ['client', 'provider'];
  }

  function _parseList(payload) {
    if (Array.isArray(payload)) return payload;
    if (payload && Array.isArray(payload.results)) return payload.results;
    return [];
  }

  function _toInt(value) {
    const n = Number(value);
    return Number.isFinite(n) ? n : 0;
  }

  function _showGate() {
    const gate = document.getElementById('auth-gate');
    const content = document.getElementById('interactive-content');
    if (gate) gate.classList.remove('hidden');
    if (content) content.classList.add('hidden');
  }

  function _hideGate() {
    const gate = document.getElementById('auth-gate');
    const content = document.getElementById('interactive-content');
    if (gate) gate.classList.add('hidden');
    if (content) content.classList.remove('hidden');
  }

  function _renderTabs() {
    const tabsWrap = document.getElementById('interact-tabs');
    if (!tabsWrap) return;
    tabsWrap.innerHTML = '';

    const tabs = [{ id: 'following', label: 'من أتابع', icon: 'people' }];
    if (_isProviderMode) tabs.push({ id: 'followers', label: 'متابعيني', icon: 'person' });
    tabs.push({ id: 'favorites', label: 'مفضلتي', icon: 'bookmark' });

    tabs.forEach((tab, idx) => {
      const btn = UI.el('button', {
        type: 'button',
        className: 'tab-btn interactive-tab-btn' + (idx === 0 ? ' active' : ''),
        'data-tab': tab.id,
      });
      const icon = UI.el('span', { className: 'interactive-tab-icon' });
      icon.innerHTML = _tabIcon(tab.icon);
      btn.appendChild(icon);
      btn.appendChild(UI.el('span', { className: 'interactive-tab-label', textContent: tab.label }));
      tabsWrap.appendChild(btn);
    });

    const followersPanel = document.getElementById('tab-followers');
    if (followersPanel) followersPanel.classList.toggle('hidden', !_isProviderMode);
  }

  function _bindTabs() {
    const tabsWrap = document.getElementById('interact-tabs');
    if (!tabsWrap) return;
    tabsWrap.addEventListener('click', (event) => {
      const btn = event.target.closest('.tab-btn');
      if (!btn) return;
      _switchTab(btn.dataset.tab || 'following');
    });
  }

  function _switchTab(nextTab) {
    _activeTab = nextTab;
    document.querySelectorAll('#interact-tabs .tab-btn').forEach((btn) => {
      btn.classList.toggle('active', (btn.dataset.tab || '') === _activeTab);
    });

    ['following', 'followers', 'favorites'].forEach((name) => {
      const panel = document.getElementById('tab-' + name);
      if (!panel) return;
      if (name === 'followers' && !_isProviderMode) {
        panel.classList.remove('active');
        return;
      }
      panel.classList.toggle('active', name === _activeTab);
    });
  }

  async function _loadAll() {
    await Promise.all([
      _fetchFollowing(),
      _fetchFavorites(),
      _isProviderMode ? _fetchFollowers() : Promise.resolve(),
    ]);
  }

  function _renderLoading(container, message) {
    if (!container) return;
    container.innerHTML = '';
    const state = UI.el('div', { className: 'interactive-state' });
    state.appendChild(UI.el('div', { className: 'spinner' }));
    state.appendChild(UI.el('p', { className: 'interactive-state-text', textContent: message }));
    container.appendChild(state);
  }

  function _renderEmpty(container, iconName, message) {
    if (!container) return;
    container.innerHTML = '';
    const state = UI.el('div', { className: 'interactive-state' });
    const iconWrap = UI.el('div', { className: 'interactive-state-icon' });
    iconWrap.innerHTML = _stateIcon(iconName);
    state.appendChild(iconWrap);
    state.appendChild(UI.el('p', { className: 'interactive-state-text', textContent: message }));
    container.appendChild(state);
  }

  function _renderError(container, message, onRetry) {
    if (!container) return;
    container.innerHTML = '';
    const state = UI.el('div', { className: 'interactive-state' });
    const iconWrap = UI.el('div', { className: 'interactive-state-icon' });
    iconWrap.innerHTML = _stateIcon('cloud');
    state.appendChild(iconWrap);
    state.appendChild(UI.el('p', { className: 'interactive-state-text', textContent: message }));

    const retryBtn = UI.el('button', {
      type: 'button',
      className: 'interactive-retry-btn',
      textContent: 'إعادة المحاولة',
    });
    retryBtn.addEventListener('click', onRetry);
    state.appendChild(retryBtn);
    container.appendChild(state);
  }

  async function _fetchFollowing() {
    const container = document.getElementById('following-list');
    _renderLoading(container, 'جاري تحميل المتابَعين...');

    const modes = _uniqueModes();
    const responses = await Promise.all(
      modes.map((mode) => ApiClient.get(_withMode('/api/providers/me/following/', mode)))
    );

    if (responses.every((res) => res.status === 401)) {
      _showGate();
      return;
    }

    const hasSuccess = responses.some((res) => res.ok);
    if (!hasSuccess) {
      const firstError = responses.find((res) => !res.ok)?.error;
      _renderError(container, firstError || 'تعذر تحميل القائمة', _fetchFollowing);
      return;
    }

    const mergedMap = new Map();
    responses
      .filter((res) => res.ok)
      .forEach((res) => {
        _parseList(res.data).forEach((entry) => {
          const provider = entry && (entry.provider || entry);
          const providerId = _toInt(provider && provider.id);
          if (providerId <= 0) return;
          if (!mergedMap.has(providerId)) {
            mergedMap.set(providerId, entry);
          }
        });
      });

    const list = Array.from(mergedMap.values());
    if (!list.length) {
      _renderEmpty(container, 'group-off', 'لا تتابع أي مزود خدمة حتى الآن');
      return;
    }

    container.innerHTML = '';
    const frag = document.createDocumentFragment();
    list.forEach((entry) => {
      const provider = entry && (entry.provider || entry);
      if (!provider || !provider.id) return;
      frag.appendChild(_buildFollowingCard(provider));
    });
    container.appendChild(frag);
  }

  function _buildFollowingCard(provider) {
    const providerId = encodeURIComponent(String(provider.id));
    const card = UI.el('article', {
      className: 'interactive-following-card interactive-following-card-clean',
      role: 'button',
      tabindex: '0',
    });

    const openProvider = () => {
      window.location.href = '/provider/' + providerId + '/';
    };
    card.addEventListener('click', openProvider);
    card.addEventListener('keydown', (event) => {
      if (event.key === 'Enter' || event.key === ' ') {
        event.preventDefault();
        openProvider();
      }
    });

    const header = UI.el('div', { className: 'interactive-following-head' });
    const avatar = UI.el('div', { className: 'interactive-following-avatar' });
    const profileUrl = ApiClient.mediaUrl(provider.profile_image || '');
    if (profileUrl) avatar.appendChild(UI.lazyImg(profileUrl, provider.display_name || ''));
    else avatar.appendChild(UI.text(((provider.display_name || '').trim().charAt(0)) || '؟'));
    header.appendChild(avatar);

    const meta = UI.el('div', { className: 'interactive-following-meta' });
    const nameRow = UI.el('div', { className: 'interactive-following-name-row' });
    nameRow.appendChild(UI.el('span', {
      className: 'interactive-following-name',
      textContent: provider.display_name || 'مقدم خدمة',
    }));
    if (provider.is_verified_blue || provider.is_verified_green || provider.is_verified) {
      const badge = UI.el('span', {
        className: 'interactive-verified-badge',
        title: 'مزود موثق',
        'aria-label': 'مزود موثق',
      });
      badge.innerHTML = '<svg width="10" height="10" viewBox="0 0 24 24" fill="currentColor"><path d="M9 16.2l-3.5-3.5L4 14.2l5 5 11-11-1.5-1.5z"/></svg>';
      if (provider.is_verified_blue) badge.classList.add('blue');
      nameRow.appendChild(badge);
    }
    meta.appendChild(nameRow);

    const cityText = String(provider.city || '').trim() || 'غير محدد';
    const rating = Number(provider.rating_avg || provider.ratingAvg || 0);
    const ratingText = Number.isFinite(rating) && rating > 0 ? rating.toFixed(1) : '0.0';

    const metaRow = UI.el('div', { className: 'interactive-following-meta-row' });
    metaRow.appendChild(UI.el('span', {
      className: 'interactive-following-pill city',
      textContent: cityText,
    }));
    const ratingPill = UI.el('span', { className: 'interactive-following-pill rating' });
    ratingPill.innerHTML = '<span class="interactive-following-pill-icon">' + _miniIcon('star') + '</span><span>' + ratingText + '</span>';
    metaRow.appendChild(ratingPill);

    meta.appendChild(metaRow);
    header.appendChild(meta);
    card.appendChild(header);

    return card;
  }

  function _openProviderChat(providerId) {
    if (!providerId) return;
    window.location.href = '/chats/?start=' + encodeURIComponent(String(providerId));
  }

  async function _fetchFollowers() {
    const container = document.getElementById('followers-list');
    _renderLoading(container, 'جاري تحميل المتابعين...');

    const res = await ApiClient.get('/api/providers/me/followers/');
    if (res.status === 401) {
      _showGate();
      return;
    }
    if (!res.ok) {
      _renderError(container, res.error || 'تعذر تحميل المتابعين', _fetchFollowers);
      return;
    }

    const list = _parseList(res.data);
    if (!list.length) {
      _renderEmpty(container, 'person-off', 'لا يوجد متابعون بعد');
      return;
    }

    container.innerHTML = '';
    const frag = document.createDocumentFragment();
    list.forEach((user) => {
      if (!user || !user.id) return;
      frag.appendChild(_buildFollowerTile(user));
    });
    container.appendChild(frag);
  }

  function _buildFollowerTile(user) {
    const tile = UI.el('div', { className: 'interactive-follower-tile' });

    const avatar = UI.el('div', { className: 'interactive-follower-avatar' });
    const displayName = String(user.display_name || user.name || user.username || 'مستخدم').trim() || 'مستخدم';
    avatar.appendChild(UI.text(displayName.charAt(0) || '؟'));
    tile.appendChild(avatar);

    const meta = UI.el('div', { className: 'interactive-follower-meta' });
    meta.appendChild(UI.el('strong', { className: 'interactive-follower-name', textContent: displayName }));
    const handle = String(user.username_display || user.username || '').trim();
    meta.appendChild(UI.el('span', { className: 'interactive-follower-handle', textContent: handle || '@-' }));
    tile.appendChild(meta);

    const action = UI.el('button', {
      type: 'button',
      className: 'interactive-follower-chat-btn',
    });
    action.innerHTML = '<span class="interactive-follower-chat-icon">' + _chatIcon() + '</span><span>مراسلة</span>';
    action.addEventListener('click', () => {
      const providerId = _toInt(user.provider_id || user.providerId);
      if (providerId > 0) {
        _openProviderChat(providerId);
      } else {
        _toast('لا يمكن مراسلة هذا المستخدم — ليس لديه ملف مزود خدمة', 'warn');
      }
    });
    tile.appendChild(action);
    return tile;
  }

  async function _fetchFavorites() {
    const container = document.getElementById('favorites-list');
    _renderLoading(container, 'جاري تحميل المفضلة...');

    const modes = _uniqueModes();
    const responses = await Promise.all(
      modes.map(async (mode) => {
        const [portfolioRes, spotlightsRes] = await Promise.all([
          ApiClient.get(_withMode('/api/providers/me/favorites/', mode)),
          ApiClient.get(_withMode('/api/providers/me/favorites/spotlights/', mode)),
        ]);
        return { mode, portfolioRes, spotlightsRes };
      })
    );

    const allUnauthorized = responses.every(
      ({ portfolioRes, spotlightsRes }) => portfolioRes.status === 401 && spotlightsRes.status === 401
    );
    if (allUnauthorized) {
      _showGate();
      return;
    }

    const hasAnySuccess = responses.some(
      ({ portfolioRes, spotlightsRes }) => portfolioRes.ok || spotlightsRes.ok
    );
    if (!hasAnySuccess) {
      _renderError(container, 'تعذر تحميل عناصر المفضلة', _fetchFavorites);
      return;
    }

    const merged = [];
    responses.forEach(({ mode, portfolioRes, spotlightsRes }) => {
      if (portfolioRes.ok) {
        merged.push(..._parseList(portfolioRes.data).map((row) => _normalizeMedia(row, 'portfolio', mode)));
      }
      if (spotlightsRes.ok) {
        merged.push(..._parseList(spotlightsRes.data).map((row) => _normalizeMedia(row, 'spotlight', mode)));
      }
    });

    const dedupedMap = new Map();
    merged.forEach((item) => {
      const key = item.source + '::' + item.id;
      if (!dedupedMap.has(key)) dedupedMap.set(key, item);
    });

    _favorites = Array.from(dedupedMap.values()).sort((a, b) => (Date.parse(b.created_at || '') || 0) - (Date.parse(a.created_at || '') || 0));
    _renderFavorites();
  }

  function _normalizeMedia(raw, source, modeContext) {
    const providerObj = raw && raw.provider ? raw.provider : null;
    const fileTypeRaw = String((raw && raw.file_type) || 'image').toLowerCase();
    return {
      id: _toInt(raw && raw.id),
      source,
      provider_id: _toInt((raw && raw.provider_id) || (providerObj && providerObj.id)),
      provider_display_name: (raw && raw.provider_display_name) || (raw && raw.provider_name) || (providerObj && providerObj.display_name) || 'مقدم خدمة',
      provider_profile_image: (raw && raw.provider_profile_image) || (providerObj && providerObj.profile_image) || '',
      file_type: fileTypeRaw.startsWith('video') ? 'video' : 'image',
      file_url: (raw && raw.file_url) || (raw && raw.media_url) || (raw && raw.image) || '',
      thumbnail_url: (raw && raw.thumbnail_url) || (raw && raw.image) || '',
      caption: (raw && raw.caption) || '',
      likes_count: _toInt(raw && raw.likes_count),
      saves_count: _toInt(raw && raw.saves_count),
      is_liked: !!(raw && raw.is_liked),
      is_saved: raw ? raw.is_saved !== false : true,
      created_at: (raw && raw.created_at) || '',
      mode_context: modeContext || 'client',
    };
  }

  function _renderFavorites() {
    const container = document.getElementById('favorites-list');
    if (!container) return;
    container.innerHTML = '';

    if (!_favorites.length) {
      _renderEmpty(container, 'bookmark', 'لا توجد عناصر محفوظة في المفضلة');
      return;
    }

    const frag = document.createDocumentFragment();
    _favorites.forEach((item, index) => frag.appendChild(_buildFavoriteCard(item, index)));
    container.appendChild(frag);
  }

  function _buildFavoriteCard(item, index) {
    const card = UI.el('article', { className: 'interactive-favorite-card', role: 'button', tabindex: '0' });
    card.addEventListener('click', () => _openFavoriteViewer(index));
    card.addEventListener('keydown', (event) => {
      if (event.key === 'Enter' || event.key === ' ') {
        event.preventDefault();
        _openFavoriteViewer(index);
      }
    });

    const media = UI.el('div', { className: 'interactive-favorite-media' });
    const imageUrl = ApiClient.mediaUrl(item.thumbnail_url || item.file_url || '');
    if (imageUrl) {
      const img = UI.lazyImg(imageUrl, item.caption || '');
      img.classList.add('interactive-favorite-thumb');
      media.appendChild(img);
    } else {
      const ph = UI.el('div', { className: 'interactive-favorite-placeholder' });
      ph.innerHTML = _stateIcon('image');
      media.appendChild(ph);
    }

    if (item.file_type === 'video') {
      const videoBadge = UI.el('div', { className: 'interactive-video-badge' });
      videoBadge.innerHTML = _miniIcon('play');
      media.appendChild(videoBadge);
    }

    media.appendChild(UI.el('span', {
      className: 'interactive-source-badge ' + (item.source === 'spotlight' ? 'spotlight' : 'portfolio'),
      textContent: item.source === 'spotlight' ? 'أضواء' : 'معرض',
    }));

    const statsBar = UI.el('div', { className: 'interactive-favorite-stats' });

    const likesStat = UI.el('span', {
      className: 'interactive-favorite-stat' + (item.is_liked ? ' active' : ''),
    });
    likesStat.appendChild(UI.el('span', { className: 'interactive-favorite-stat-icon', textContent: item.is_liked ? '❤' : '♡' }));
    likesStat.appendChild(UI.el('span', { textContent: String(_toInt(item.likes_count)) }));
    statsBar.appendChild(likesStat);

    const savesStat = UI.el('span', {
      className: 'interactive-favorite-stat' + (item.is_saved ? ' active' : ''),
    });
    savesStat.appendChild(UI.el('span', { className: 'interactive-favorite-stat-icon', textContent: item.is_saved ? '🔖' : '📑' }));
    savesStat.appendChild(UI.el('span', { textContent: String(_toInt(item.saves_count)) }));
    statsBar.appendChild(savesStat);

    media.appendChild(statsBar);

    const bottom = UI.el('div', { className: 'interactive-favorite-bottom' });
    bottom.appendChild(UI.el('strong', {
      className: 'interactive-favorite-provider',
      textContent: item.provider_display_name || 'مقدم خدمة',
    }));

    const removeBtn = UI.el('button', {
      type: 'button',
      className: 'interactive-favorite-remove-btn',
      'aria-label': 'إزالة من المفضلة',
      title: 'إزالة من المفضلة',
    });
    removeBtn.innerHTML = _miniIcon('bookmark');
    removeBtn.addEventListener('click', (event) => {
      event.preventDefault();
      event.stopPropagation();
      _showRemoveConfirm(item, removeBtn);
    });

    bottom.appendChild(removeBtn);
    media.appendChild(bottom);
    card.appendChild(media);
    return card;
  }

  function _openFavoriteViewer(index) {
    if (!_favorites.length) return;
    if (typeof SpotlightViewer !== 'undefined') {
      SpotlightViewer.open(_favorites, index);
      return;
    }
    _toast('تعذر فتح العارض حالياً', 'error');
  }

  function _showRemoveConfirm(item, triggerBtn) {
    const backdrop = UI.el('div', { className: 'interactive-confirm-backdrop' });
    const dialog = UI.el('div', { className: 'interactive-confirm-dialog' });
    dialog.appendChild(UI.el('h3', { className: 'interactive-confirm-title', textContent: 'تأكيد الإزالة' }));
    dialog.appendChild(UI.el('p', { className: 'interactive-confirm-text', textContent: 'هل تريد إزالة المحتوى من المفضلة؟' }));

    const actions = UI.el('div', { className: 'interactive-confirm-actions' });
    const cancelBtn = UI.el('button', { type: 'button', className: 'interactive-btn interactive-btn-cancel', textContent: 'إلغاء' });
    const okBtn = UI.el('button', { type: 'button', className: 'interactive-btn interactive-btn-confirm', textContent: 'تأكيد' });

    cancelBtn.addEventListener('click', () => backdrop.remove());
    okBtn.addEventListener('click', async () => {
      okBtn.disabled = true;
      await _unsaveFavorite(item, triggerBtn);
      backdrop.remove();
    });

    actions.appendChild(cancelBtn);
    actions.appendChild(okBtn);
    dialog.appendChild(actions);
    backdrop.appendChild(dialog);
    backdrop.addEventListener('click', (event) => {
      if (event.target === backdrop) backdrop.remove();
    });
    document.body.appendChild(backdrop);
  }

  async function _unsaveFavorite(item, triggerBtn) {
    const endpoint = item.source === 'spotlight'
      ? '/api/providers/spotlights/' + item.id + '/unsave/'
      : '/api/providers/portfolio/' + item.id + '/unsave/';

    if (triggerBtn) triggerBtn.disabled = true;
    const res = await ApiClient.request(_withMode(endpoint, item.mode_context), { method: 'POST' });
    if (triggerBtn) triggerBtn.disabled = false;

    if (!res.ok) {
      _toast('فشل إزالة العنصر — حاول مرة أخرى', 'error');
      return;
    }

    _favorites = _favorites.filter((entry) => !(entry.id === item.id && entry.source === item.source));
    _renderFavorites();
    _toast('تم إزالة العنصر من المفضلة', 'success');
  }

  function _tabIcon(kind) {
    if (kind === 'people') return '<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M16 11c1.66 0 2.99-1.34 2.99-3S17.66 5 16 5c-1.66 0-3 1.34-3 3s1.34 3 3 3zm-8 0c1.66 0 2.99-1.34 2.99-3S9.66 5 8 5C6.34 5 5 6.34 5 8s1.34 3 3 3zm0 2c-2.33 0-7 1.17-7 3.5V19h14v-2.5c0-2.33-4.67-3.5-7-3.5z"/></svg>';
    if (kind === 'person') return '<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z"/></svg>';
    return '<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M17 3H5a2 2 0 0 0-2 2v16l8-3.5 8 3.5V5a2 2 0 0 0-2-2z"/></svg>';
  }

  function _stateIcon(kind) {
    if (kind === 'cloud') return '<svg width="38" height="38" viewBox="0 0 24 24" fill="#C4C4CF"><path d="M19.35 10.04A7.49 7.49 0 0 0 5 10a5 5 0 0 0 0 10h14a4 4 0 0 0 .35-7.96zM8 14l8-8 1.41 1.41-8 8H8v-1.41z"/></svg>';
    if (kind === 'group-off') return '<svg width="38" height="38" viewBox="0 0 24 24" fill="#C4C4CF"><path d="M10 8a3 3 0 1 1-6 0 3 3 0 0 1 6 0zm4 6c2.33 0 7 1.17 7 3.5V20H3v-2.5C3 15.17 7.67 14 10 14h4zm8.19 7.19L2.81 1.81 1.39 3.22l3.2 3.2A2.99 2.99 0 0 0 4 8c0 1.66 1.34 3 3 3 .5 0 .97-.12 1.38-.34l2.12 2.12c-3.63.36-7.5 1.74-7.5 4.72V20h14.78l2 2z"/></svg>';
    if (kind === 'person-off') return '<svg width="38" height="38" viewBox="0 0 24 24" fill="#C4C4CF"><path d="M12 12c2.21 0 4-1.79 4-4 0-.9-.3-1.73-.8-2.4L8.6 12.2c.67.5 1.5.8 2.4.8zm0 2c-2.67 0-8 1.34-8 4v2h12.78l-5-5H12zM1.41 1.69 0 3.1l4.05 4.05A3.9 3.9 0 0 0 4 8c0 2.21 1.79 4 4 4 .3 0 .59-.03.87-.1L21 24l1.41-1.41z"/></svg>';
    if (kind === 'bookmark') return '<svg width="38" height="38" viewBox="0 0 24 24" fill="#C4C4CF"><path d="M17 3H7a2 2 0 0 0-2 2v16l7-3 7 3V5a2 2 0 0 0-2-2z"/></svg>';
    return '<svg width="38" height="38" viewBox="0 0 24 24" fill="#C4C4CF"><path d="M21 5v14H3V5h18zm0-2H3a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h18a2 2 0 0 0 2-2V5a2 2 0 0 0-2-2z"/></svg>';
  }

  function _chatIcon() {
    return '<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M20 2H4a2 2 0 0 0-2 2v18l4-4h14a2 2 0 0 0 2-2V4a2 2 0 0 0-2-2z"/></svg>';
  }

  function _miniIcon(kind) {
    if (kind === 'people') return '<svg width="11" height="11" viewBox="0 0 24 24" fill="currentColor"><path d="M16 11c1.66 0 2.99-1.34 2.99-3S17.66 5 16 5c-1.66 0-3 1.34-3 3s1.34 3 3 3zm-8 0c1.66 0 2.99-1.34 2.99-3S9.66 5 8 5C6.34 5 5 6.34 5 8s1.34 3 3 3z"/></svg>';
    if (kind === 'heart') return '<svg width="11" height="11" viewBox="0 0 24 24" fill="currentColor"><path d="M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54z"/></svg>';
    if (kind === 'star') return '<svg width="11" height="11" viewBox="0 0 24 24" fill="currentColor"><path d="M12 17.27L18.18 21l-1.64-7.03L22 9.24l-7.19-.61L12 2 9.19 8.63 2 9.24l5.46 4.73L5.82 21z"/></svg>';
    if (kind === 'play') return '<svg width="13" height="13" viewBox="0 0 24 24" fill="#fff"><path d="M8 5v14l11-7z"/></svg>';
    return '<svg width="13" height="13" viewBox="0 0 24 24" fill="#fff"><path d="M17 3H5a2 2 0 0 0-2 2v16l8-3.5 8 3.5V5a2 2 0 0 0-2-2z"/></svg>';
  }

  function _toast(message, type) {
    const old = document.getElementById('interactive-toast');
    if (old) old.remove();

    const toast = UI.el('div', {
      id: 'interactive-toast',
      className: 'interactive-toast' + (type ? (' ' + type) : ''),
      textContent: message,
    });
    document.body.appendChild(toast);
    requestAnimationFrame(() => toast.classList.add('show'));
    setTimeout(() => {
      toast.classList.remove('show');
      setTimeout(() => toast.remove(), 240);
    }, 2200);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  return {};
})();
