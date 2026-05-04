/* ===================================================================
   interactivePage.js — 1:1 parity with Flutter InteractiveScreen
   =================================================================== */
'use strict';

const InteractivePage = (() => {
  const COPY = {
    ar: {
      pageTitle: 'نوافــذ — تفاعلي',
      gateKicker: 'شبكة تفاعلك',
      gateTitle: 'سجّل دخولك لعرض تفاعلك على المنصة ',
      gateDescription: 'يلزم تسجيل الدخول للوصول إلى المتابعة، المتابعين، والمفضلة.',
      gateNote: 'تابع المهتمين بك ووسائطك المفضلة من مكان واحد.',
      gateButton: 'تسجيل الدخول',
      heroKicker: 'لوحة تفاعلك',
      heroTitle: 'شبكتك التفاعلية',
      summaryFollowing: 'من أتابع',
      summaryFollowers: 'متابعيني',
      summaryFavorites: 'مفضلتي',
      summaryBlocks: 'قوائم الحظر',
      tabsKicker: 'إدارة التفاعل',
      tabsNote: 'بدّل بين الأقسام للوصول السريع إلى الأشخاص والوسائط التي تهمك.',
      followingTitle: 'من أتابع',
      followingSubtitle: 'مزودو الخدمة والأشخاص الذين تتابع نشاطهم.',
      followersTitle: 'متابعيني',
      followersSubtitle: 'العملاء والأشخاص الذين يتابعون ملفك.',
      favoritesTitle: 'مفضلتي',
      favoritesSubtitle: 'الريلز والوسائط التي احتفظت بها للرجوع إليها بسرعة.',
      blocksTitle: 'قوائم الحظر',
      blocksSubtitle: 'الحسابات والمحتوى الذي أخفيته عن تجربتك مع إمكانية فك الحظر في أي وقت.',
      searchFollowingLabel: 'ابحث في من أتابع',
      searchFollowingPlaceholder: 'ابحث بالاسم أو المدينة…',
      searchFollowersLabel: 'ابحث في المتابعين',
      searchFollowersPlaceholder: 'ابحث بالاسم…',
      searchFavoritesLabel: 'ابحث في المفضلة',
      searchFavoritesPlaceholder: 'ابحث في المفضلة…',
      searchBlocksLabel: 'ابحث في قوائم الحظر',
      searchBlocksPlaceholder: 'ابحث بالحساب أو بالمحتوى المحظور…',
      densityLabel: 'كثافة العرض',
      normalDensity: 'عرض شبكي',
      compactDensity: 'عرض مدمج',
      tabFollowing: 'من أتابع',
      tabFollowers: 'متابعيني',
      tabFavorites: 'مفضلتي',
      tabBlocks: 'قوائم الحظر',
      modeSyncError: 'يجري الآن تثبيت نوع الحساب الحالي. أعد المحاولة بعد لحظة.',
      retry: 'إعادة المحاولة',
      loadingFollowing: 'جاري تحميل المتابَعين...',
      loadingFollowers: 'جاري تحميل المتابعين...',
      loadingFavorites: 'جاري تحميل المفضلة...',
      loadingBlocks: 'جاري تحميل قوائم الحظر...',
      sessionRefresh: 'يتم تحديث الجلسة أو نوع الحساب. أعد المحاولة بعد قليل.',
      listLoadFailed: 'تعذر تحميل القائمة',
      followingEmpty: 'لا تتابع أي مزود خدمة حتى الآن',
      verifiedProvider: 'مزود موثق',
      excellence: 'تميز',
      providerType: 'مزود خدمة',
      providerName: 'مقدم خدمة',
      cityUnset: 'غير محدد',
      followersCount: 'متابع',
      completedCount: 'مكتمل',
      viewProfile: 'عرض الملف والتفاصيل الكاملة',
      followersLoadFailed: 'تعذر تحميل المتابعين',
      followersEmpty: 'لا يوجد متابعون بعد',
      userFallback: 'مستخدم',
      openProfile: 'فتح الملف',
      favoritesLoadFailed: 'تعذر تحميل عناصر المفضلة',
      favoritesEmpty: 'لا توجد عناصر محفوظة في المفضلة',
      blocksLoadFailed: 'تعذر تحميل قوائم الحظر',
      blocksEmpty: 'لا توجد حسابات أو محتويات محظورة حالياً',
      blockedAccounts: 'الحسابات المحظورة',
      blockedContent: 'المحتوى المحظور',
      blockedAccountsEmpty: 'لا توجد حسابات محظورة حالياً',
      blockedContentEmpty: 'لا يوجد محتوى محظور حالياً',
      reelsSaved: 'الريلز المحفوظة',
      mediaSaved: 'الوسائط المحفوظة',
      spotlightSource: 'أضواء',
      portfolioSource: 'معرض',
      favoriteRemoveLabel: 'إزالة من المفضلة',
      unblockProviderAction: 'إلغاء حظر الحساب',
      unblockContentAction: 'إلغاء حظر المحتوى',
      unblockProviderSuccess: 'تم إلغاء حظر الحساب',
      unblockContentSuccess: 'تم إلغاء حظر المحتوى',
      unblockFailed: 'تعذر إلغاء الحظر حالياً',
      viewerLabel: 'مفضلتي',
      viewerOpenFailed: 'تعذر فتح العارض حالياً',
      removeConfirmTitle: 'تأكيد الإزالة',
      removeConfirmText: 'هل تريد إزالة المحتوى من المفضلة؟',
      cancel: 'إلغاء',
      confirm: 'تأكيد',
      removeFailed: 'فشل إزالة العنصر — حاول مرة أخرى',
      removedSuccess: 'تم إزالة العنصر من المفضلة',
      blueBadgeVerified: 'توثيق أزرق',
      greenBadgeVerified: 'توثيق أخضر',
    },
    en: {
      pageTitle: 'Nawafeth — Interactive',
      gateKicker: 'Your interaction network',
      gateTitle: 'Sign in to view Interactive',
      gateDescription: 'You need to sign in to access following, followers, and favorites.',
      gateNote: 'Track the people interested in you and your saved media from one place.',
      gateButton: 'Sign in',
      heroKicker: 'Your activity board',
      heroTitle: 'Your interactive network',
      summaryFollowing: 'Following',
      summaryFollowers: 'Followers',
      summaryFavorites: 'Favorites',
      summaryBlocks: 'Blocked lists',
      tabsKicker: 'Interaction control',
      tabsNote: 'Switch between sections for quick access to the people and media that matter to you.',
      followingTitle: 'Following',
      followingSubtitle: 'Service providers and people whose activity you follow.',
      followersTitle: 'Followers',
      followersSubtitle: 'Clients and people following your profile.',
      favoritesTitle: 'Favorites',
      favoritesSubtitle: 'Reels and media you saved to return to quickly.',
      blocksTitle: 'Blocked lists',
      blocksSubtitle: 'Accounts and content you hid from your experience, with the ability to unblock at any time.',
      searchFollowingLabel: 'Search following',
      searchFollowingPlaceholder: 'Search by name or city…',
      searchFollowersLabel: 'Search followers',
      searchFollowersPlaceholder: 'Search by name…',
      searchFavoritesLabel: 'Search favorites',
      searchFavoritesPlaceholder: 'Search favorites…',
      searchBlocksLabel: 'Search blocked lists',
      searchBlocksPlaceholder: 'Search blocked accounts or content…',
      densityLabel: 'View density',
      normalDensity: 'Grid view',
      compactDensity: 'Compact view',
      tabFollowing: 'Following',
      tabFollowers: 'Followers',
      tabFavorites: 'Favorites',
      tabBlocks: 'Blocked lists',
      modeSyncError: 'The current account mode is still being stabilized. Please try again shortly.',
      retry: 'Try again',
      loadingFollowing: 'Loading following...',
      loadingFollowers: 'Loading followers...',
      loadingFavorites: 'Loading favorites...',
      loadingBlocks: 'Loading blocked lists...',
      sessionRefresh: 'The session or account mode is being refreshed. Please try again shortly.',
      listLoadFailed: 'Unable to load the list',
      followingEmpty: 'You are not following any service providers yet',
      verifiedProvider: 'Verified provider',
      excellence: 'Excellence',
      providerType: 'Service provider',
      providerName: 'Provider',
      cityUnset: 'Not specified',
      followersCount: 'followers',
      completedCount: 'completed',
      viewProfile: 'Open full profile and details',
      followersLoadFailed: 'Unable to load followers',
      followersEmpty: 'No followers yet',
      userFallback: 'User',
      openProfile: 'Open profile',
      favoritesLoadFailed: 'Unable to load favorite items',
      favoritesEmpty: 'No saved items in favorites',
      blocksLoadFailed: 'Unable to load blocked lists',
      blocksEmpty: 'There are no blocked accounts or content right now',
      blockedAccounts: 'Blocked accounts',
      blockedContent: 'Blocked content',
      blockedAccountsEmpty: 'No blocked accounts right now',
      blockedContentEmpty: 'No blocked content right now',
      reelsSaved: 'Saved reels',
      mediaSaved: 'Saved media',
      spotlightSource: 'Spotlights',
      portfolioSource: 'Portfolio',
      favoriteRemoveLabel: 'Remove from favorites',
      unblockProviderAction: 'Unblock account',
      unblockContentAction: 'Unblock content',
      unblockProviderSuccess: 'The account has been unblocked',
      unblockContentSuccess: 'The content has been unblocked',
      unblockFailed: 'Unable to unblock right now',
      viewerLabel: 'Favorites',
      viewerOpenFailed: 'Unable to open the viewer right now',
      removeConfirmTitle: 'Confirm removal',
      removeConfirmText: 'Do you want to remove this item from favorites?',
      cancel: 'Cancel',
      confirm: 'Confirm',
      removeFailed: 'Failed to remove the item. Please try again.',
      removedSuccess: 'The item was removed from favorites',
      blueBadgeVerified: 'Blue verification',
      greenBadgeVerified: 'Green verification',
    },
  };

  let _activeTab = 'following';
  let _mode = 'client';
  let _isProviderMode = false;
  let _favorites = [];
  let _blockedProviders = [];
  let _blockedSpotlights = [];
  const _roleModes = ['client', 'provider'];

  async function init() {
    _applyStaticCopy();
    _setInitialLoading(true);

    const loggedIn = !!Auth.isLoggedIn();
    if (!loggedIn) {
      _setInitialLoading(false);
      _showGate();
      return;
    }

    _mode = _resolveMode();
    _isProviderMode = _mode === 'provider';
    _activeTab = _resolveInitialTab();
    _hideGate();
    _renderTabs();
    _bindTabs();
    _switchTab(_activeTab);
    _setInitialLoading(false);
    window.addEventListener('nawafeth:languagechange', _handleLanguageChange);
    await _loadAll();
  }

  function _resolveInitialTab() {
    try {
      const params = new URLSearchParams(window.location.search || '');
      const requested = String(params.get('tab') || '').trim().toLowerCase();
      if (requested === 'favorites') return 'favorites';
      if (requested === 'blocks') return 'blocks';
      if (requested === 'followers' && _isProviderMode) return 'followers';
    } catch (_) {
      // no-op
    }
    return 'following';
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

    const tabs = [{ id: 'following', label: _copy('tabFollowing'), icon: 'people' }];
    if (_isProviderMode) tabs.push({ id: 'followers', label: _copy('tabFollowers'), icon: 'person' });
    tabs.push({ id: 'favorites', label: _copy('tabFavorites'), icon: 'bookmark' });
    tabs.push({ id: 'blocks', label: _copy('tabBlocks'), icon: 'shield' });

    tabs.forEach((tab, idx) => {
      const btn = UI.el('button', {
        type: 'button',
        className: 'tab-btn interactive-tab-btn' + (((_activeTab || (idx === 0 ? tab.id : '')) === tab.id) ? ' active' : ''),
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

    ['following', 'followers', 'favorites', 'blocks'].forEach((name) => {
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
    const profileState = await Auth.resolveProfile(false, _mode);
    if (!profileState.ok) {
      if (!Auth.isLoggedIn()) {
        _showGate();
        return;
      }
      _toast(_copy('modeSyncError'), 'error');
      return;
    }
    if (profileState.mode && profileState.mode !== _mode) {
      _mode = profileState.mode;
      _isProviderMode = _mode === 'provider';
      _renderTabs();
      _switchTab(_resolveInitialTab());
    }
    await Promise.all([
      _fetchFollowing(),
      _fetchFavorites(),
      _fetchBlocks(),
      _isProviderMode ? _fetchFollowers() : Promise.resolve(),
    ]);
  }

  function _renderLoading(container, message) {
    if (!container) return;
    const targetId = String(container.id || '');
    if (targetId === 'favorites-list') {
      container.innerHTML = _favoritesSkeletonMarkup();
      return;
    }
    if (targetId === 'following-list' || targetId === 'followers-list' || targetId === 'blocks-list') {
      container.innerHTML = _peopleSkeletonMarkup();
      return;
    }

    container.innerHTML = '';
    const state = UI.el('div', { className: 'interactive-state' });
    state.appendChild(UI.el('div', { className: 'spinner' }));
    state.appendChild(UI.el('p', { className: 'interactive-state-text', textContent: message }));
    container.appendChild(state);
  }

  function _peopleSkeletonMarkup() {
    return [
      '<div class="interactive-skeleton-grid">',
      '  <article class="interactive-skeleton-card nw-skeleton-surface">',
      '    <span class="interactive-skeleton-avatar nw-skeleton-block"></span>',
      '    <span class="interactive-skeleton-line nw-skeleton-block"></span>',
      '    <span class="interactive-skeleton-line short nw-skeleton-block"></span>',
      '    <span class="interactive-skeleton-button nw-skeleton-block"></span>',
      '  </article>',
      '  <article class="interactive-skeleton-card nw-skeleton-surface">',
      '    <span class="interactive-skeleton-avatar nw-skeleton-block"></span>',
      '    <span class="interactive-skeleton-line nw-skeleton-block"></span>',
      '    <span class="interactive-skeleton-line short nw-skeleton-block"></span>',
      '    <span class="interactive-skeleton-button nw-skeleton-block"></span>',
      '  </article>',
      '  <article class="interactive-skeleton-card nw-skeleton-surface">',
      '    <span class="interactive-skeleton-avatar nw-skeleton-block"></span>',
      '    <span class="interactive-skeleton-line nw-skeleton-block"></span>',
      '    <span class="interactive-skeleton-line short nw-skeleton-block"></span>',
      '    <span class="interactive-skeleton-button nw-skeleton-block"></span>',
      '  </article>',
      '</div>'
    ].join('');
  }

  function _favoritesSkeletonMarkup() {
    return [
      '<section class="interactive-skeleton-favorites">',
      '  <div class="interactive-skeleton-reels">',
      '    <span class="interactive-skeleton-reel nw-skeleton-surface"></span>',
      '    <span class="interactive-skeleton-reel nw-skeleton-surface"></span>',
      '    <span class="interactive-skeleton-reel nw-skeleton-surface"></span>',
      '  </div>',
      '  <div class="interactive-skeleton-grid compact">',
      '    <article class="interactive-skeleton-card nw-skeleton-surface">',
      '      <span class="interactive-skeleton-media nw-skeleton-block"></span>',
      '      <span class="interactive-skeleton-line nw-skeleton-block"></span>',
      '      <span class="interactive-skeleton-line short nw-skeleton-block"></span>',
      '    </article>',
      '    <article class="interactive-skeleton-card nw-skeleton-surface">',
      '      <span class="interactive-skeleton-media nw-skeleton-block"></span>',
      '      <span class="interactive-skeleton-line nw-skeleton-block"></span>',
      '      <span class="interactive-skeleton-line short nw-skeleton-block"></span>',
      '    </article>',
      '  </div>',
      '</section>'
    ].join('');
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
      textContent: _copy('retry'),
    });
    retryBtn.addEventListener('click', onRetry);
    state.appendChild(retryBtn);
    container.appendChild(state);
  }

  async function _fetchFollowing() {
    const container = document.getElementById('following-list');
    _renderLoading(container, _copy('loadingFollowing'));

    const response = await ApiClient.get(_withMode('/api/providers/me/following/', _mode));

    if (response.status === 401) {
      const recovered = await Auth.resolveProfile(true, _mode);
      if (!recovered.ok && !Auth.isLoggedIn()) {
        _showGate();
        return;
      }
      _renderError(container, _copy('sessionRefresh'), _fetchFollowing);
      return;
    }

    if (!response.ok) {
      _renderError(container, response.error || _copy('listLoadFailed'), _fetchFollowing);
      return;
    }

    const mergedMap = new Map();
    _parseList(response.data).forEach((entry) => {
      const provider = entry && (entry.provider || entry);
      const providerId = _toInt(provider && provider.id);
      if (providerId <= 0) return;
      if (!mergedMap.has(providerId)) {
        mergedMap.set(providerId, entry);
      }
      });

    const list = Array.from(mergedMap.values());
    if (!list.length) {
      _renderEmpty(container, 'group-off', _copy('followingEmpty'));
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
      className: 'interactive-following-card interactive-person-card',
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

    card.appendChild(UI.el('div', { className: 'interactive-person-accent' }));

    const header = UI.el('div', { className: 'interactive-person-head interactive-following-head' });
    const avatarWrap = UI.el('div', { className: 'interactive-following-avatar-wrap' });
    const avatar = UI.el('div', { className: 'interactive-following-avatar' });
    const profileUrl = ApiClient.mediaUrl(provider.profile_image || '');
    if (profileUrl) avatar.appendChild(UI.lazyImg(profileUrl, provider.display_name || ''));
    else avatar.appendChild(UI.text(((provider.display_name || '').trim().charAt(0)) || '؟'));

    const excellenceItems = UI.normalizeExcellenceBadges(provider.excellence_badges);
    if (excellenceItems.length) {
      avatarWrap.appendChild(UI.el('span', {
        className: 'interactive-following-avatar-excellence-top',
        textContent: excellenceItems[0].name || excellenceItems[0].code || _copy('excellence'),
      }));
    }
    avatarWrap.appendChild(avatar);
    header.appendChild(avatarWrap);

    const meta = UI.el('div', { className: 'interactive-person-meta interactive-following-meta' });
    meta.appendChild(UI.el('span', {
      className: 'interactive-person-kicker',
      textContent: provider.provider_type_label || _copy('providerType'),
    }));
    const nameRow = UI.el('div', { className: 'interactive-following-name-row' });
    nameRow.appendChild(UI.el('span', {
      className: 'interactive-following-name',
      textContent: provider.display_name || _copy('providerName'),
    }));
    const verificationBadges = UI.buildVerificationBadges({
      isVerifiedBlue: !!provider.is_verified_blue,
      isVerifiedGreen: !!provider.is_verified_green || (!provider.is_verified_blue && !!provider.is_verified),
      iconSize: 10,
      gap: '3px',
      blueLabel: _copy('blueBadgeVerified'),
      greenLabel: _copy('greenBadgeVerified'),
    });
    if (verificationBadges) nameRow.appendChild(verificationBadges);
    meta.appendChild(nameRow);

    const usernameRaw = String(provider.username || '').trim();
    if (usernameRaw) {
      meta.appendChild(UI.el('p', {
        className: 'interactive-following-handle',
        textContent: '@' + usernameRaw,
      }));
    }

    const excellence = UI.buildExcellenceBadges(excellenceItems, {
      className: 'excellence-badges compact interactive-excellence-badges',
      compact: true,
      iconSize: 10,
    });
    if (excellence) nameRow.appendChild(excellence);

    const cityText = UI.formatCityDisplay(provider.city_display || provider.city, provider.region || provider.region_name) || _copy('cityUnset');
    const rating = Number(provider.rating_avg || provider.ratingAvg || 0);
    const ratingText = Number.isFinite(rating) && rating > 0 ? rating.toFixed(1) : '0.0';
    const categoryText = String(provider.primary_category_name || '').trim();
    const subcategoryText = String(provider.primary_subcategory_name || '').trim();
    const subtitleParts = [categoryText, subcategoryText || cityText].filter(Boolean);
    meta.appendChild(UI.el('p', {
      className: 'interactive-person-subtitle',
      textContent: subtitleParts.join(' • ') || cityText,
    }));

    const metaRow = UI.el('div', { className: 'interactive-following-meta-row interactive-person-chip-row' });
    metaRow.appendChild(UI.el('span', {
      className: 'interactive-following-pill city',
      textContent: cityText,
    }));
    const ratingPill = UI.el('span', { className: 'interactive-following-pill rating' });
    ratingPill.innerHTML = '<span class="interactive-following-pill-icon">' + _miniIcon('star') + '</span><span>' + ratingText + '</span>';
    metaRow.appendChild(ratingPill);
    const followersPill = UI.el('span', { className: 'interactive-following-pill stat' });
    followersPill.innerHTML = '<span class="interactive-following-pill-icon">' + _miniIcon('people') + '</span><span>' + _toInt(provider.followers_count || 0) + ' ' + _copy('followersCount') + '</span>';
    metaRow.appendChild(followersPill);
    const completed = _toInt(provider.completed_requests || 0);
    if (completed > 0) {
      const completedPill = UI.el('span', { className: 'interactive-following-pill stat soft' });
      completedPill.innerHTML = '<span>' + completed + ' ' + _copy('completedCount') + '</span>';
      metaRow.appendChild(completedPill);
    }

    meta.appendChild(metaRow);
    header.appendChild(meta);
    card.appendChild(header);

    const footer = UI.el('div', { className: 'interactive-person-footer' });
    footer.appendChild(UI.el('span', {
      className: 'interactive-person-footnote',
      textContent: _copy('viewProfile'),
    }));
    const arrow = UI.el('span', { className: 'interactive-person-arrow', 'aria-hidden': 'true' });
    arrow.innerHTML = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none"><path d="M9 6L15 12L9 18" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>';
    footer.appendChild(arrow);
    card.appendChild(footer);

    return card;
  }

  async function _fetchFollowers() {
    const container = document.getElementById('followers-list');
    _renderLoading(container, _copy('loadingFollowers'));

    const res = await ApiClient.get(_withMode('/api/providers/me/followers/', _mode));
    if (res.status === 401) {
      const recovered = await Auth.resolveProfile(true, _mode);
      if (!recovered.ok && !Auth.isLoggedIn()) {
        _showGate();
        return;
      }
      _renderError(container, _copy('sessionRefresh'), _fetchFollowers);
      return;
    }
    if (!res.ok) {
      _renderError(container, res.error || _copy('followersLoadFailed'), _fetchFollowers);
      return;
    }

    const list = _parseList(res.data);
    if (!list.length) {
      _renderEmpty(container, 'person-off', _copy('followersEmpty'));
      return;
    }

    container.innerHTML = '';
    const fragment = document.createDocumentFragment();
    list.forEach((user) => {
      if (!user || !user.id) return;
      fragment.appendChild(_buildFollowerTile(user));
    });
    container.appendChild(fragment);
  }

  function _buildFollowerTile(user) {
    const followRole = String(user.follow_role_context || user.followRoleContext || 'client').trim().toLowerCase();
    const isProviderFollower = followRole === 'provider';
    const providerId = isProviderFollower ? _toInt(user.provider_id || user.providerId) : 0;
    const tile = UI.el('article', {
      className: 'interactive-follower-tile interactive-person-card interactive-follower-card'
        + (isProviderFollower ? ' is-provider-follower' : ' is-client-follower')
        + (providerId > 0 ? ' is-clickable' : ''),
    });
    if (providerId > 0) {
      tile.setAttribute('role', 'button');
      tile.setAttribute('tabindex', '0');
      const openProvider = () => {
        window.location.href = '/provider/' + encodeURIComponent(String(providerId)) + '/';
      };
      tile.addEventListener('click', openProvider);
      tile.addEventListener('keydown', (event) => {
        if (event.key === 'Enter' || event.key === ' ') {
          event.preventDefault();
          openProvider();
        }
      });
    }

    tile.appendChild(UI.el('div', { className: 'interactive-person-accent' + (isProviderFollower ? '' : ' muted') }));

    const header = UI.el('div', { className: 'interactive-person-head' });

    const avatar = UI.el('div', { className: 'interactive-follower-avatar' });
    const displayName = String(user.display_name || user.name || user.username || _copy('userFallback')).trim() || _copy('userFallback');
    const profileUrl = ApiClient.mediaUrl(user.profile_image || user.avatar || '');
    if (profileUrl) avatar.appendChild(UI.lazyImg(profileUrl, displayName));
    else avatar.appendChild(UI.text(displayName.charAt(0) || '؟'));
    header.appendChild(avatar);

    const meta = UI.el('div', { className: 'interactive-person-meta interactive-follower-meta' });
    meta.appendChild(UI.el('strong', { className: 'interactive-follower-name', textContent: displayName }));
    const handleRaw = String(user.username_display || user.username || '').trim();
    const handle = handleRaw
      ? (handleRaw.startsWith('@') ? handleRaw : ('@' + handleRaw))
      : '@-';
    meta.appendChild(UI.el('span', { className: 'interactive-follower-handle', textContent: handle }));
    header.appendChild(meta);
    tile.appendChild(header);

    if (providerId > 0) {
      const footer = UI.el('div', { className: 'interactive-person-footer' });
      footer.appendChild(UI.el('span', {
        className: 'interactive-person-footnote',
        textContent: _copy('openProfile'),
      }));
      const arrow = UI.el('span', { className: 'interactive-person-arrow', 'aria-hidden': 'true' });
      arrow.innerHTML = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none"><path d="M9 6L15 12L9 18" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>';
      footer.appendChild(arrow);
      tile.appendChild(footer);
    }
    return tile;
  }

  async function _fetchFavorites() {
    const container = document.getElementById('favorites-list');
    _renderLoading(container, _copy('loadingFavorites'));

    const [portfolioRes, spotlightsRes] = await Promise.all([
      ApiClient.get(_withMode('/api/providers/me/favorites/', _mode)),
      ApiClient.get(_withMode('/api/providers/me/favorites/spotlights/', _mode)),
    ]);

    if (portfolioRes.status === 401 && spotlightsRes.status === 401) {
      const recovered = await Auth.resolveProfile(true, _mode);
      if (!recovered.ok && !Auth.isLoggedIn()) {
        _showGate();
        return;
      }
      _renderError(container, _copy('sessionRefresh'), _fetchFavorites);
      return;
    }

    if (!portfolioRes.ok && !spotlightsRes.ok) {
      _renderError(container, _copy('favoritesLoadFailed'), _fetchFavorites);
      return;
    }

    const merged = [];
    if (portfolioRes.ok) {
      merged.push(..._parseList(portfolioRes.data).map((row) => _normalizeMedia(row, 'portfolio', _mode)));
    }
    if (spotlightsRes.ok) {
      merged.push(..._parseList(spotlightsRes.data).map((row) => _normalizeMedia(row, 'spotlight', _mode)));
    }

    const dedupedMap = new Map();
    merged.forEach((item) => {
      const key = item.source + '::' + item.id;
      if (!dedupedMap.has(key)) dedupedMap.set(key, item);
    });

    _favorites = Array.from(dedupedMap.values()).sort((a, b) => (Date.parse(b.created_at || '') || 0) - (Date.parse(a.created_at || '') || 0));
    _renderFavorites();
  }

  async function _fetchBlocks() {
    const container = document.getElementById('blocks-list');
    if (!container) return;
    _renderLoading(container, _copy('loadingBlocks'));

    const res = await ApiClient.get(_withMode('/api/providers/me/visibility-blocks/', _mode));

    if (res.status === 401) {
      const recovered = await Auth.resolveProfile(true, _mode);
      if (!recovered.ok && !Auth.isLoggedIn()) {
        _showGate();
        return;
      }
      _renderError(container, _copy('sessionRefresh'), _fetchBlocks);
      return;
    }

    if (!res.ok) {
      _renderError(container, _copy('blocksLoadFailed'), _fetchBlocks);
      return;
    }

    const payload = res.data || {};
    _blockedProviders = Array.isArray(payload.blocked_providers) ? payload.blocked_providers.slice() : [];
    _blockedSpotlights = Array.isArray(payload.blocked_spotlights) ? payload.blocked_spotlights.slice() : [];
    _renderBlocks();
  }

  function _invalidateVisibilityDependentCaches(options) {
    if (typeof NwCache === 'undefined' || !NwCache || typeof NwCache.remove !== 'function') return;
    NwCache.remove('home_spotlights');
    if (options && options.providerRelated) {
      NwCache.remove('home_providers');
      NwCache.remove('home_featured_specialists');
    }
  }

  function _normalizeMedia(raw, source, modeContext) {
    const providerObj = raw && raw.provider ? raw.provider : null;
    const fileTypeRaw = String((raw && raw.file_type) || 'image').toLowerCase();
    return {
      id: _toInt(raw && raw.id),
      source,
      provider_id: _toInt((raw && raw.provider_id) || (providerObj && providerObj.id)),
      provider_display_name: (raw && raw.provider_display_name) || (raw && raw.provider_name) || (providerObj && providerObj.display_name) || _copy('providerName'),
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
      _renderEmpty(container, 'bookmark', _copy('favoritesEmpty'));
      return;
    }

    const frag = document.createDocumentFragment();
    const spotlightItems = _favorites.filter((item) => item.source === 'spotlight');
    const otherItems = _favorites.filter((item) => item.source !== 'spotlight');

    if (spotlightItems.length) {
      const section = UI.el('section', { className: 'interactive-favorites-section interactive-favorites-section-reels' });
      section.appendChild(UI.el('div', {
        className: 'interactive-favorites-section-title',
        textContent: _copy('reelsSaved'),
      }));

      const track = UI.el('div', { className: 'reels-track interactive-favorites-reels' });
      spotlightItems.forEach((item) => {
        const globalIndex = _favorites.indexOf(item);
        track.appendChild(_buildFavoriteReel(item, globalIndex));
      });
      section.appendChild(track);
      frag.appendChild(section);
    }

    if (otherItems.length) {
      const section = UI.el('section', { className: 'interactive-favorites-section' });
      if (spotlightItems.length) {
        section.appendChild(UI.el('div', {
          className: 'interactive-favorites-section-title',
          textContent: _copy('mediaSaved'),
        }));
      }

      const grid = UI.el('div', { className: 'interactive-favorites-grid' });
      otherItems.forEach((item) => {
        const globalIndex = _favorites.indexOf(item);
        grid.appendChild(_buildFavoriteCard(item, globalIndex));
      });
      section.appendChild(grid);
      frag.appendChild(section);
    }

    container.appendChild(frag);
  }

  function _renderBlocks() {
    const container = document.getElementById('blocks-list');
    if (!container) return;
    container.innerHTML = '';

    if (!_blockedProviders.length && !_blockedSpotlights.length) {
      _renderEmpty(container, 'shield-off', _copy('blocksEmpty'));
      return;
    }

    const fragment = document.createDocumentFragment();

    if (_blockedProviders.length) {
      const section = UI.el('section', { className: 'interactive-favorites-section interactive-blocked-section' });
      section.appendChild(UI.el('div', {
        className: 'interactive-favorites-section-title',
        textContent: _copy('blockedAccounts'),
      }));
      const grid = UI.el('div', { className: 'interactive-following-grid interactive-blocked-providers-grid' });
      _blockedProviders.forEach((provider) => {
        grid.appendChild(_buildBlockedProviderCard(provider));
      });
      section.appendChild(grid);
      fragment.appendChild(section);
    }

    if (_blockedSpotlights.length) {
      const section = UI.el('section', { className: 'interactive-favorites-section interactive-blocked-section' });
      section.appendChild(UI.el('div', {
        className: 'interactive-favorites-section-title',
        textContent: _copy('blockedContent'),
      }));
      const grid = UI.el('div', { className: 'interactive-favorites-grid interactive-blocked-content-grid' });
      _blockedSpotlights.forEach((item) => {
        grid.appendChild(_buildBlockedSpotlightCard(item));
      });
      section.appendChild(grid);
      fragment.appendChild(section);
    }

    container.appendChild(fragment);
  }

  function _buildBlockedProviderCard(provider) {
    const providerId = _toInt(provider && provider.provider_id);
    const displayName = String(provider && provider.display_name || _copy('providerName')).trim() || _copy('providerName');
    const card = UI.el('article', {
      className: 'interactive-following-card interactive-person-card interactive-blocked-provider-card' + (providerId > 0 ? ' is-clickable' : ''),
    });
    if (providerId > 0) {
      card.setAttribute('role', 'button');
      card.setAttribute('tabindex', '0');
    }

    if (providerId > 0) {
      const openProvider = () => {
        window.location.href = '/provider/' + encodeURIComponent(String(providerId)) + '/';
      };
      card.addEventListener('click', openProvider);
      card.addEventListener('keydown', (event) => {
        if (event.key === 'Enter' || event.key === ' ') {
          event.preventDefault();
          openProvider();
        }
      });
    }

    card.appendChild(UI.el('div', { className: 'interactive-person-accent' }));
    const header = UI.el('div', { className: 'interactive-person-head interactive-following-head' });
    const avatarWrap = UI.el('div', { className: 'interactive-following-avatar-wrap' });
    const avatar = UI.el('div', { className: 'interactive-following-avatar' });
    const profileUrl = ApiClient.mediaUrl(provider && provider.profile_image || '');
    if (profileUrl) avatar.appendChild(UI.lazyImg(profileUrl, displayName));
    else avatar.appendChild(UI.text(displayName.charAt(0) || '؟'));
    avatarWrap.appendChild(avatar);
    header.appendChild(avatarWrap);

    const meta = UI.el('div', { className: 'interactive-person-meta interactive-following-meta' });
    meta.appendChild(UI.el('span', {
      className: 'interactive-person-kicker',
      textContent: _copy('blockedAccounts'),
    }));
    const nameRow = UI.el('div', { className: 'interactive-following-name-row' });
    nameRow.appendChild(UI.el('span', {
      className: 'interactive-following-name',
      textContent: displayName,
    }));
    const verificationBadges = UI.buildVerificationBadges({
      isVerifiedBlue: !!(provider && provider.is_verified_blue),
      isVerifiedGreen: !!(provider && provider.is_verified_green),
      iconSize: 10,
      gap: '3px',
      blueLabel: _copy('blueBadgeVerified'),
      greenLabel: _copy('greenBadgeVerified'),
    });
    if (verificationBadges) nameRow.appendChild(verificationBadges);
    meta.appendChild(nameRow);

    const username = String(provider && provider.username || '').trim();
    if (username) {
      meta.appendChild(UI.el('p', {
        className: 'interactive-following-handle',
        textContent: '@' + username,
      }));
    }
    meta.appendChild(UI.el('p', {
      className: 'interactive-person-subtitle',
      textContent: UI.formatCityDisplay(provider && (provider.city_display || provider.city), provider && provider.region) || _copy('cityUnset'),
    }));
    header.appendChild(meta);
    card.appendChild(header);

    const footer = UI.el('div', { className: 'interactive-person-footer interactive-blocked-footer' });
    footer.appendChild(UI.el('span', {
      className: 'interactive-person-footnote',
      textContent: _copy('viewProfile'),
    }));
    const unblockBtn = UI.el('button', {
      type: 'button',
      className: 'interactive-blocked-unblock-btn',
      textContent: _copy('unblockProviderAction'),
    });
    unblockBtn.addEventListener('click', (event) => {
      event.preventDefault();
      event.stopPropagation();
      _unblockProvider(providerId, unblockBtn);
    });
    footer.appendChild(unblockBtn);
    card.appendChild(footer);
    return card;
  }

  function _buildBlockedSpotlightCard(item) {
    const spotlightId = _toInt(item && item.spotlight_id);
    const imageUrl = ApiClient.mediaUrl(item && (item.thumbnail_url || item.file_url) || '');
    const mediaUrl = ApiClient.mediaUrl(item && item.file_url || '');
    const isVideoCard = String(item && item.file_type || '').toLowerCase() === 'video' && !!mediaUrl;
    const card = UI.el('article', {
      className: 'interactive-favorite-card interactive-blocked-spotlight-card ' + (isVideoCard ? 'is-video' : 'is-image'),
    });

    const media = UI.el('div', { className: 'interactive-favorite-media ' + (isVideoCard ? 'is-video' : 'is-image') });
    if (!isVideoCard && imageUrl) {
      media.style.setProperty('--interactive-favorite-image', 'url("' + imageUrl.replace(/"/g, '\\"') + '")');
    }

    if (isVideoCard) {
      const video = document.createElement('video');
      video.className = 'interactive-favorite-thumb interactive-favorite-video';
      video.src = mediaUrl;
      video.muted = true;
      video.defaultMuted = true;
      video.autoplay = true;
      video.loop = true;
      video.playsInline = true;
      video.preload = 'metadata';
      video.setAttribute('muted', 'muted');
      video.setAttribute('autoplay', 'autoplay');
      video.setAttribute('loop', 'loop');
      video.setAttribute('playsinline', 'playsinline');
      if (imageUrl) video.poster = imageUrl;
      video.addEventListener('loadedmetadata', () => {
        const playAttempt = video.play();
        if (playAttempt && typeof playAttempt.catch === 'function') playAttempt.catch(() => {});
      });
      media.appendChild(video);
      const videoBadge = UI.el('div', { className: 'interactive-video-badge' });
      videoBadge.innerHTML = _miniIcon('play');
      media.appendChild(videoBadge);
    } else if (imageUrl) {
      const img = UI.lazyImg(imageUrl, item && item.caption || '');
      img.classList.add('interactive-favorite-thumb', 'interactive-favorite-image');
      media.appendChild(img);
    } else {
      const ph = UI.el('div', { className: 'interactive-favorite-placeholder' });
      ph.innerHTML = _stateIcon('image');
      media.appendChild(ph);
    }

    media.appendChild(UI.el('span', {
      className: 'interactive-source-badge spotlight',
      textContent: _copy('spotlightSource'),
    }));

    const bottom = UI.el('div', { className: 'interactive-favorite-bottom' });
    bottom.appendChild(UI.el('strong', {
      className: 'interactive-favorite-provider',
      textContent: item && item.provider_display_name || _copy('providerName'),
    }));

    const unblockBtn = UI.el('button', {
      type: 'button',
      className: 'interactive-favorite-remove-btn interactive-blocked-unblock-btn',
      'aria-label': _copy('unblockContentAction'),
      title: _copy('unblockContentAction'),
    });
    unblockBtn.innerHTML = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none"><path d="M7 17 17 7" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><circle cx="12" cy="12" r="9" stroke="currentColor" stroke-width="2"/></svg>';
    unblockBtn.addEventListener('click', (event) => {
      event.preventDefault();
      event.stopPropagation();
      _unblockSpotlight(spotlightId, unblockBtn);
    });

    bottom.appendChild(unblockBtn);
    media.appendChild(bottom);
    card.appendChild(media);

    if (item && item.caption) {
      card.appendChild(UI.el('div', {
        className: 'interactive-blocked-caption',
        textContent: item.caption,
      }));
    }

    return card;
  }

  async function _unblockProvider(providerId, triggerBtn) {
    if (!providerId) return;
    if (triggerBtn) triggerBtn.disabled = true;
    const res = await ApiClient.request(_withMode('/api/providers/' + providerId + '/block/', _mode), { method: 'DELETE' });
    if (triggerBtn) triggerBtn.disabled = false;
    if (!res.ok) {
      _toast(_copy('unblockFailed'), 'error');
      return;
    }
    _blockedProviders = _blockedProviders.filter((entry) => _toInt(entry.provider_id) !== providerId);
    _invalidateVisibilityDependentCaches({ providerRelated: true });
    _renderBlocks();
    _toast(_copy('unblockProviderSuccess'), 'success');
  }

  async function _unblockSpotlight(spotlightId, triggerBtn) {
    if (!spotlightId) return;
    if (triggerBtn) triggerBtn.disabled = true;
    const res = await ApiClient.request(_withMode('/api/providers/spotlights/' + spotlightId + '/hide/', _mode), { method: 'DELETE' });
    if (triggerBtn) triggerBtn.disabled = false;
    if (!res.ok) {
      _toast(_copy('unblockFailed'), 'error');
      return;
    }
    _blockedSpotlights = _blockedSpotlights.filter((entry) => _toInt(entry.spotlight_id) !== spotlightId);
    _invalidateVisibilityDependentCaches({ providerRelated: false });
    _renderBlocks();
    _toast(_copy('unblockContentSuccess'), 'success');
  }

  function _buildFavoriteReel(item, index) {
    const thumb = ApiClient.mediaUrl(item.thumbnail_url || item.file_url || '');
    const mediaUrl = ApiClient.mediaUrl(item.file_url || '');
    const isVideo = String(item.file_type || '').toLowerCase() === 'video' && !!mediaUrl;
    const caption = (item.caption || '').trim() || (item.provider_display_name || _copy('providerName'));

    const reel = UI.el('div', {
      className: 'reel-item interactive-favorite-reel',
      role: 'button',
      tabindex: '0',
    });

    const ring = UI.el('div', { className: 'reel-ring' });
    const inner = UI.el('div', { className: 'reel-inner' });

    if (isVideo) {
      const preview = document.createElement('video');
      preview.className = 'reel-preview-video';
      preview.preload = 'metadata';
      preview.muted = true;
      preview.defaultMuted = true;
      preview.loop = true;
      preview.playsInline = true;
      preview.tabIndex = -1;
      preview.setAttribute('aria-hidden', 'true');
      preview.setAttribute('playsinline', '');
      preview.setAttribute('webkit-playsinline', '');
      preview.src = mediaUrl;
      if (thumb) preview.poster = thumb;
      preview.addEventListener('loadedmetadata', () => {
        const playAttempt = preview.play();
        if (playAttempt && typeof playAttempt.catch === 'function') playAttempt.catch(() => {});
      });
      inner.appendChild(preview);
    } else if (thumb) {
      inner.appendChild(UI.lazyImg(thumb, caption));
    } else {
      inner.appendChild(UI.el('div', { className: 'reel-placeholder' }));
    }

    ring.appendChild(inner);
    reel.appendChild(ring);
    reel.appendChild(UI.el('div', { className: 'reel-caption', textContent: caption }));

    reel.addEventListener('click', () => _openFavoriteViewer(index));
    reel.addEventListener('keydown', (event) => {
      if (event.key === 'Enter' || event.key === ' ') {
        event.preventDefault();
        _openFavoriteViewer(index);
      }
    });

    return reel;
  }

  function _buildFavoriteCard(item, index) {
    const imageUrl = ApiClient.mediaUrl(item.thumbnail_url || item.file_url || '');
    const mediaUrl = ApiClient.mediaUrl(item.file_url || '');
    const isVideoCard = item.file_type === 'video' && !!mediaUrl;

    const card = UI.el('article', {
      className: 'interactive-favorite-card ' + (isVideoCard ? 'is-video' : 'is-image'),
      role: 'button',
      tabindex: '0',
    });
    card.addEventListener('click', () => _openFavoriteViewer(index));
    card.addEventListener('keydown', (event) => {
      if (event.key === 'Enter' || event.key === ' ') {
        event.preventDefault();
        _openFavoriteViewer(index);
      }
    });

    const media = UI.el('div', { className: 'interactive-favorite-media ' + (isVideoCard ? 'is-video' : 'is-image') });
    if (!isVideoCard && imageUrl) {
      media.style.setProperty('--interactive-favorite-image', 'url("' + imageUrl.replace(/"/g, '\\"') + '")');
    }

    if (isVideoCard) {
      const video = document.createElement('video');
      video.className = 'interactive-favorite-thumb interactive-favorite-video';
      video.src = mediaUrl;
      video.muted = true;
      video.defaultMuted = true;
      video.autoplay = true;
      video.loop = true;
      video.playsInline = true;
      video.preload = 'metadata';
      video.setAttribute('muted', 'muted');
      video.setAttribute('autoplay', 'autoplay');
      video.setAttribute('loop', 'loop');
      video.setAttribute('playsinline', 'playsinline');
      video.setAttribute('webkit-playsinline', 'webkit-playsinline');
      if (imageUrl) video.poster = imageUrl;
      video.addEventListener('loadedmetadata', () => {
        const playAttempt = video.play();
        if (playAttempt && typeof playAttempt.catch === 'function') playAttempt.catch(() => {});
      });
      video.addEventListener('error', () => {
        video.classList.add('hidden');
      }, { once: true });
      media.appendChild(video);
    } else if (imageUrl) {
      const img = UI.lazyImg(imageUrl, item.caption || '');
      img.classList.add('interactive-favorite-thumb', 'interactive-favorite-image');
      img.setAttribute('loading', 'lazy');
      media.appendChild(img);
    } else {
      const ph = UI.el('div', { className: 'interactive-favorite-placeholder' });
      ph.innerHTML = _stateIcon('image');
      media.appendChild(ph);
    }

    if (isVideoCard) {
      const videoBadge = UI.el('div', { className: 'interactive-video-badge' });
      videoBadge.innerHTML = _miniIcon('play');
      media.appendChild(videoBadge);
    }

    media.appendChild(UI.el('span', {
      className: 'interactive-source-badge ' + (item.source === 'spotlight' ? 'spotlight' : 'portfolio'),
      textContent: item.source === 'spotlight' ? _copy('spotlightSource') : _copy('portfolioSource'),
    }));

    // Stats overlay — visible on hover (Instagram style)
    const statsBar = UI.el('div', { className: 'interactive-favorite-stats' });

    const likesStat = UI.el('span', {
      className: 'interactive-favorite-stat' + (item.is_liked ? ' active' : ''),
    });
    likesStat.appendChild(UI.el('span', { className: 'interactive-favorite-stat-icon', textContent: '♥' }));
    likesStat.appendChild(UI.el('span', { textContent: String(_toInt(item.likes_count)) }));
    statsBar.appendChild(likesStat);

    const savesStat = UI.el('span', {
      className: 'interactive-favorite-stat' + (item.is_saved ? ' active' : ''),
    });
    savesStat.appendChild(UI.el('span', { className: 'interactive-favorite-stat-icon', textContent: '⚑' }));
    savesStat.appendChild(UI.el('span', { textContent: String(_toInt(item.saves_count)) }));
    statsBar.appendChild(savesStat);

    media.appendChild(statsBar);

    // Bottom gradient bar with provider name
    const bottom = UI.el('div', { className: 'interactive-favorite-bottom' });
    bottom.appendChild(UI.el('strong', {
      className: 'interactive-favorite-provider',
      textContent: item.provider_display_name || _copy('providerName'),
    }));

    const removeBtn = UI.el('button', {
      type: 'button',
      className: 'interactive-favorite-remove-btn',
      'aria-label': _copy('favoriteRemoveLabel'),
      title: _copy('favoriteRemoveLabel'),
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
      SpotlightViewer.open(_favorites, index, {
        label: _copy('viewerLabel'),
        modeContext: _mode || 'client',
        immersive: true,
      });
      return;
    }
    _toast(_copy('viewerOpenFailed'), 'error');
  }

  function _showRemoveConfirm(item, triggerBtn) {
    const backdrop = UI.el('div', { className: 'interactive-confirm-backdrop' });
    const dialog = UI.el('div', { className: 'interactive-confirm-dialog' });
    dialog.appendChild(UI.el('h3', { className: 'interactive-confirm-title', textContent: _copy('removeConfirmTitle') }));
    dialog.appendChild(UI.el('p', { className: 'interactive-confirm-text', textContent: _copy('removeConfirmText') }));

    const actions = UI.el('div', { className: 'interactive-confirm-actions' });
    const cancelBtn = UI.el('button', { type: 'button', className: 'interactive-btn interactive-btn-cancel', textContent: _copy('cancel') });
    const okBtn = UI.el('button', { type: 'button', className: 'interactive-btn interactive-btn-confirm', textContent: _copy('confirm') });

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
      _toast(_copy('removeFailed'), 'error');
      return;
    }

    _favorites = _favorites.filter((entry) => !(entry.id === item.id && entry.source === item.source));
    _renderFavorites();
    _toast(_copy('removedSuccess'), 'success');
  }

  function _tabIcon(kind) {
    if (kind === 'people') return '<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M16 11c1.66 0 2.99-1.34 2.99-3S17.66 5 16 5c-1.66 0-3 1.34-3 3s1.34 3 3 3zm-8 0c1.66 0 2.99-1.34 2.99-3S9.66 5 8 5C6.34 5 5 6.34 5 8s1.34 3 3 3zm0 2c-2.33 0-7 1.17-7 3.5V19h14v-2.5c0-2.33-4.67-3.5-7-3.5z"/></svg>';
    if (kind === 'person') return '<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z"/></svg>';
    if (kind === 'shield') return '<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2 5 5v6c0 5.25 3.44 10.04 7 11 3.56-.96 7-5.75 7-11V5l-7-3zm3.59 13L14.17 16.41 12 14.24l-2.17 2.17L8.41 15 10.59 12.83 8.41 10.66l1.42-1.42L12 11.41l2.17-2.17 1.42 1.42-2.17 2.17L15.59 15z"/></svg>';
    return '<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M17 3H5a2 2 0 0 0-2 2v16l8-3.5 8 3.5V5a2 2 0 0 0-2-2z"/></svg>';
  }

  function _stateIcon(kind) {
    if (kind === 'cloud') return '<svg width="38" height="38" viewBox="0 0 24 24" fill="#C4C4CF"><path d="M19.35 10.04A7.49 7.49 0 0 0 5 10a5 5 0 0 0 0 10h14a4 4 0 0 0 .35-7.96zM8 14l8-8 1.41 1.41-8 8H8v-1.41z"/></svg>';
    if (kind === 'group-off') return '<svg width="38" height="38" viewBox="0 0 24 24" fill="#C4C4CF"><path d="M10 8a3 3 0 1 1-6 0 3 3 0 0 1 6 0zm4 6c2.33 0 7 1.17 7 3.5V20H3v-2.5C3 15.17 7.67 14 10 14h4zm8.19 7.19L2.81 1.81 1.39 3.22l3.2 3.2A2.99 2.99 0 0 0 4 8c0 1.66 1.34 3 3 3 .5 0 .97-.12 1.38-.34l2.12 2.12c-3.63.36-7.5 1.74-7.5 4.72V20h14.78l2 2z"/></svg>';
    if (kind === 'person-off') return '<svg width="38" height="38" viewBox="0 0 24 24" fill="#C4C4CF"><path d="M12 12c2.21 0 4-1.79 4-4 0-.9-.3-1.73-.8-2.4L8.6 12.2c.67.5 1.5.8 2.4.8zm0 2c-2.67 0-8 1.34-8 4v2h12.78l-5-5H12zM1.41 1.69 0 3.1l4.05 4.05A3.9 3.9 0 0 0 4 8c0 2.21 1.79 4 4 4 .3 0 .59-.03.87-.1L21 24l1.41-1.41z"/></svg>';
    if (kind === 'bookmark') return '<svg width="38" height="38" viewBox="0 0 24 24" fill="#C4C4CF"><path d="M17 3H7a2 2 0 0 0-2 2v16l7-3 7 3V5a2 2 0 0 0-2-2z"/></svg>';
    if (kind === 'shield-off') return '<svg width="38" height="38" viewBox="0 0 24 24" fill="#C4C4CF"><path d="M12 2 5 5v6c0 5.25 3.44 10.04 7 11 1.62-.44 3.19-1.65 4.45-3.31L5.31 7.55C5.11 8.56 5 9.72 5 11c0 5.25 3.44 10.04 7 11 3.56-.96 7-5.75 7-11V5l-7-3zm8.71 19.29-18-18L1.29 4.71l18 18 1.42-1.42z"/></svg>';
    return '<svg width="38" height="38" viewBox="0 0 24 24" fill="#C4C4CF"><path d="M21 5v14H3V5h18zm0-2H3a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h18a2 2 0 0 0 2-2V5a2 2 0 0 0-2-2z"/></svg>';
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

  function _currentLang() {
    if (window.NawafethI18n && typeof window.NawafethI18n.getLanguage === 'function') {
      return window.NawafethI18n.getLanguage() === 'en' ? 'en' : 'ar';
    }
    return document.documentElement.lang === 'en' ? 'en' : 'ar';
  }

  function _copy(key) {
    const lang = _currentLang();
    return (COPY[lang] && COPY[lang][key]) || COPY.ar[key] || '';
  }

  function _setText(id, value) {
    const el = document.getElementById(id);
    if (el) el.textContent = value;
  }

  function _applyStaticCopy() {
    document.title = _copy('pageTitle');
    const gate = document.getElementById('auth-gate');
    if (gate) {
      const kicker = gate.querySelector('.auth-gate-unified-kicker');
      const title = gate.querySelector('.auth-gate-unified-title');
      const desc = gate.querySelector('.auth-gate-unified-desc');
      const note = gate.querySelector('.auth-gate-unified-note');
      const cta = gate.querySelector('.auth-gate-unified-btn');
      if (kicker) kicker.textContent = _copy('gateKicker');
      if (title) title.textContent = _copy('gateTitle');
      if (desc) desc.textContent = _copy('gateDescription');
      if (note) note.textContent = _copy('gateNote');
      if (cta) cta.textContent = _copy('gateButton');
    }
    _setText('interactive-hero-kicker', _copy('heroKicker'));
    _setText('interactive-hero-title', _copy('heroTitle'));
    _setText('interactive-summary-following', _copy('summaryFollowing'));
    _setText('interactive-summary-followers', _copy('summaryFollowers'));
    _setText('interactive-summary-favorites', _copy('summaryFavorites'));
    _setText('interactive-summary-blocks', _copy('summaryBlocks'));
    _setText('interactive-tabs-kicker', _copy('tabsKicker'));
    _setText('interactive-tabs-note', _copy('tabsNote'));
    _setText('interactive-panel-title-following', _copy('followingTitle'));
    _setText('interactive-panel-subtitle-following', _copy('followingSubtitle'));
    _setText('interactive-panel-title-followers', _copy('followersTitle'));
    _setText('interactive-panel-subtitle-followers', _copy('followersSubtitle'));
    _setText('interactive-panel-title-favorites', _copy('favoritesTitle'));
    _setText('interactive-panel-subtitle-favorites', _copy('favoritesSubtitle'));
    _setText('interactive-panel-title-blocks', _copy('blocksTitle'));
    _setText('interactive-panel-subtitle-blocks', _copy('blocksSubtitle'));
    const searchFollowingLabel = document.getElementById('interactive-search-label-following');
    const searchFollowersLabel = document.getElementById('interactive-search-label-followers');
    const searchFavoritesLabel = document.getElementById('interactive-search-label-favorites');
    const searchBlocksLabel = document.getElementById('interactive-search-label-blocks');
    const searchFollowingInput = document.getElementById('interactive-search-input-following');
    const searchFollowersInput = document.getElementById('interactive-search-input-followers');
    const searchFavoritesInput = document.getElementById('interactive-search-input-favorites');
    const searchBlocksInput = document.getElementById('interactive-search-input-blocks');
    const densityGroup = document.getElementById('interactive-density-group');
    if (searchFollowingLabel) searchFollowingLabel.setAttribute('aria-label', _copy('searchFollowingLabel'));
    if (searchFollowersLabel) searchFollowersLabel.setAttribute('aria-label', _copy('searchFollowersLabel'));
    if (searchFavoritesLabel) searchFavoritesLabel.setAttribute('aria-label', _copy('searchFavoritesLabel'));
    if (searchBlocksLabel) searchBlocksLabel.setAttribute('aria-label', _copy('searchBlocksLabel'));
    if (searchFollowingInput) searchFollowingInput.placeholder = _copy('searchFollowingPlaceholder');
    if (searchFollowersInput) searchFollowersInput.placeholder = _copy('searchFollowersPlaceholder');
    if (searchFavoritesInput) searchFavoritesInput.placeholder = _copy('searchFavoritesPlaceholder');
    if (searchBlocksInput) searchBlocksInput.placeholder = _copy('searchBlocksPlaceholder');
    if (densityGroup) densityGroup.setAttribute('aria-label', _copy('densityLabel'));
    document.querySelectorAll('[data-density-btn="normal"]').forEach((btn) => {
      btn.setAttribute('title', _copy('normalDensity'));
      btn.setAttribute('aria-label', _copy('normalDensity'));
    });
    document.querySelectorAll('[data-density-btn="compact"]').forEach((btn) => {
      btn.setAttribute('title', _copy('compactDensity'));
      btn.setAttribute('aria-label', _copy('compactDensity'));
    });
  }

  async function _handleLanguageChange() {
    _applyStaticCopy();
    if (!Auth.isLoggedIn()) {
      _showGate();
      return;
    }
    _renderTabs();
    _switchTab(_activeTab);
    await _loadAll();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  return {};
})();
