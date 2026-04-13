/* ===================================================================
   providerDetailPage.js — Provider public profile detail (redesigned)
   Mirrors the Flutter ProviderProfileScreen layout.
   =================================================================== */
'use strict';

const ProviderDetailPage = (() => {
  let _providerId = null;
  let _mode = 'client';
  let _isFollowing = false;
  let _isBookmarked = false;
  let _activeTab = 'profile';
  let _providerData = null;
  let _providerPhone = '';
  let _providerWhatsappUrl = '';
  let _spotlights = [];
  let _portfolioItems = [];
  let _profileLikesBase = 0;
  let _portfolioLikes = 0;
  let _spotlightLikes = 0;
  let _portfolioSaves = 0;
  let _spotlightSaves = 0;
  let _portfolioSavedByMe = false;
  let _spotlightSavedByMe = false;
  let _mediaLikesTotal = null;
  let _spotlightSyncBound = false;
  let _portfolioSyncBound = false;
  let _portfolioPreviewObserver = null;
  let _derivedMainCategory = '';
  let _derivedSubCategory = '';
  let _returnNav = null;
  let _socialUrls = {
    instagram: '',
    x: '',
    snapchat: '',
  };
  let _currentProfile = null;
  let _isOwnProviderProfile = false;
  let _serviceRangeMap = null;
  let _serviceRangeLayer = null;

  function init() {
    const match = window.location.pathname.match(/\/provider\/(\d+)(?:\/[^/?#]+)?\/?/);
    if (!match) {
      document.querySelector('.pd-page').textContent = '';
      const msg = UI.el('div', { className: 'pd-empty', style: { padding: '80px 20px' } });
      msg.appendChild(UI.el('div', { className: 'pd-empty-icon', textContent: '🔍' }));
      msg.appendChild(UI.el('p', { textContent: 'مقدم الخدمة غير موجود' }));
      document.querySelector('.pd-page').appendChild(msg);
      return;
    }
    _providerId = match[1];
    _mode = _resolveMode();
    _returnNav = _resolveReturnNavigation();

    _bindTabs();
    _bindActions();
    _bindSpotlightSync();
    _bindPortfolioSync();
    _renderModeBadge();
    _syncDirectChatAvailability();
    _loadAll();
  }

  /* ── Tabs ── */
  function _bindTabs() {
    const tabsRoot = document.getElementById('pd-tabs');
    if (!tabsRoot) return;

    tabsRoot.addEventListener('click', e => {
      const btn = e.target.closest('.pd-tab');
      if (!btn || !tabsRoot.contains(btn)) return;
      const tabName = String(btn.dataset.tab || '').trim();
      if (!tabName) return;
      _setActiveTab(tabName, { scrollIntoView: true });
    });

    tabsRoot.addEventListener('keydown', e => {
      const currentBtn = e.target.closest('.pd-tab');
      if (!currentBtn || !tabsRoot.contains(currentBtn)) return;

      const tabs = _tabButtons();
      if (!tabs.length) return;
      const currentIndex = tabs.indexOf(currentBtn);
      if (currentIndex < 0) return;

      const dir = String(document.documentElement.getAttribute('dir') || 'ltr').toLowerCase();
      const forwardKey = dir === 'rtl' ? 'ArrowLeft' : 'ArrowRight';
      const backwardKey = dir === 'rtl' ? 'ArrowRight' : 'ArrowLeft';

      let targetIndex = -1;
      if (e.key === forwardKey) {
        targetIndex = (currentIndex + 1) % tabs.length;
      } else if (e.key === backwardKey) {
        targetIndex = (currentIndex - 1 + tabs.length) % tabs.length;
      } else if (e.key === 'Home') {
        targetIndex = 0;
      } else if (e.key === 'End') {
        targetIndex = tabs.length - 1;
      } else if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        _setActiveTab(String(currentBtn.dataset.tab || '').trim(), { focusTab: true, scrollIntoView: true });
        return;
      } else {
        return;
      }

      e.preventDefault();
      const targetBtn = tabs[targetIndex];
      if (!targetBtn) return;
      _setActiveTab(String(targetBtn.dataset.tab || '').trim(), { focusTab: true, scrollIntoView: true });
    });

    _setActiveTab(_activeTab || 'profile');
    _setTabMeta('profile', 'أساسي');
    _setTabMeta('services', '...');
    _setTabMeta('portfolio', '...');
    _setTabMeta('reviews', '...');
  }

  function _tabButtons() {
    return Array.from(document.querySelectorAll('#pd-tabs .pd-tab'));
  }

  function _setActiveTab(nextTab, opts = {}) {
    const tabName = String(nextTab || '').trim();
    if (!tabName) return;

    const buttons = _tabButtons();
    const activeButton = buttons.find((btn) => String(btn.dataset.tab || '').trim() === tabName);
    if (!activeButton) return;

    _activeTab = tabName;
    buttons.forEach((btn) => {
      const isActive = btn === activeButton;
      btn.classList.toggle('active', isActive);
      btn.setAttribute('aria-selected', isActive ? 'true' : 'false');
      btn.setAttribute('tabindex', isActive ? '0' : '-1');
    });

    document.querySelectorAll('.pd-panel').forEach((panel) => {
      const isActive = panel.id === ('tab-' + tabName);
      panel.classList.toggle('active', isActive);
      if (isActive) {
        panel.removeAttribute('hidden');
      } else {
        panel.setAttribute('hidden', 'hidden');
      }
    });

    _syncPortfolioPreviewPlayback();
    if (_activeTab === 'profile') {
      _syncServiceRangeMapSize();
    }

    if (opts.scrollIntoView) {
      _ensureActiveTabVisible();
    }

    if (opts.focusTab && typeof activeButton.focus === 'function') {
      try {
        activeButton.focus({ preventScroll: true });
      } catch (_) {
        activeButton.focus();
      }
    }
  }

  function _ensureActiveTabVisible() {
    const active = document.querySelector('#pd-tabs .pd-tab.active');
    if (!active || typeof active.scrollIntoView !== 'function') return;
    try {
      active.scrollIntoView({ behavior: 'smooth', block: 'nearest', inline: 'center' });
    } catch (_) {
      active.scrollIntoView();
    }
  }

  function _setTabMeta(tabName, value) {
    const el = document.getElementById('pd-tab-meta-' + tabName);
    if (!el) return;
    const text = String(value === null || value === undefined ? '' : value).trim();
    if (!text) {
      el.textContent = '';
      el.classList.add('hidden');
      return;
    }
    el.textContent = text;
    el.classList.remove('hidden');
  }

  function _formatTabCount(count) {
    return _safeInt(count).toLocaleString('ar-SA');
  }

  function _setInitialShellLoading(loading) {
    const loadingShell = document.getElementById('pd-loading-shell');
    const contentShell = document.getElementById('pd-content-shell');
    if (loadingShell) loadingShell.classList.toggle('hidden', !loading);
    if (contentShell) {
      contentShell.classList.toggle('hidden', !!loading);
      contentShell.setAttribute('aria-busy', loading ? 'true' : 'false');
    }
  }

  function _setTabLoadingState(sectionName, loading) {
    const loadingEl = document.getElementById('pd-' + sectionName + '-loading');
    if (loadingEl) loadingEl.classList.toggle('hidden', !loading);
  }

  /* ── Action buttons ── */
  function _bindActions() {
    document.getElementById('btn-follow').addEventListener('click', _toggleFollow);

    const followersBtn = document.getElementById('btn-show-followers');
    if (followersBtn) {
      followersBtn.addEventListener('click', () => _openConnectionsSheet('followers'));
    }

    const followingBtn = document.getElementById('btn-show-following');
    if (followingBtn) {
      followingBtn.addEventListener('click', () => _openConnectionsSheet('following'));
    }

    const backBtn = document.getElementById('btn-back');
    if (backBtn) {
      backBtn.addEventListener('click', () => {
        if (_returnNav && _returnNav.href) {
          window.location.href = _returnNav.href;
          return;
        }
        if (window.history.length > 1) {
          window.history.back();
          return;
        }
        const fallback = document.referrer && document.referrer.startsWith(window.location.origin)
          ? document.referrer
          : '/search/';
        window.location.href = fallback;
      });
    }

    const returnToMapBtn = document.getElementById('btn-back-to-map');
    if (returnToMapBtn) {
      if (_returnNav && _returnNav.href) {
        returnToMapBtn.href = _returnNav.href;
        returnToMapBtn.textContent = _returnNav.label || 'العودة';
        returnToMapBtn.setAttribute('aria-label', _returnNav.label || 'العودة');
        returnToMapBtn.classList.remove('hidden');
      } else {
        returnToMapBtn.classList.add('hidden');
      }
    }

    // Message
    const msgBtn = document.getElementById('btn-message');
    if (msgBtn) msgBtn.addEventListener('click', _openDirectChat);

    // Call
    const callBtn = document.getElementById('btn-call');
    if (callBtn) callBtn.addEventListener('click', () => {
      if (_providerPhone) window.open('tel:' + _formatPhoneE164(_providerPhone));
    });

    // WhatsApp (header + profile tab)
    ['btn-whatsapp', 'pd-btn-whatsapp'].forEach(id => {
      const el = document.getElementById(id);
      if (el) el.addEventListener('click', e => {
        e.preventDefault();
        const name = _pickFirstText(_providerData?.display_name, _providerData?.displayName);
        const waUrl = _buildWhatsappChatUrl(
          _providerWhatsappUrl,
          _providerPhone,
          'السلام عليكم\nأتواصل معك بخصوص خدماتك في منصة نوافذ @' + name,
        );
        if (!waUrl) return;
        window.open(waUrl, '_blank');
      });
    });

    // Profile tab quick actions
    const qCall = document.getElementById('pd-btn-call');
    if (qCall) qCall.addEventListener('click', e => {
      e.preventDefault();
      if (_providerPhone) window.open('tel:' + _formatPhoneE164(_providerPhone));
    });
    const qChat = document.getElementById('pd-btn-chat');
    if (qChat) qChat.addEventListener('click', e => {
      e.preventDefault();
      _openDirectChat();
    });

    // Bookmark
    const bookmarkBtn = document.getElementById('btn-bookmark');
    if (bookmarkBtn) {
      bookmarkBtn.addEventListener('click', _handleBookmarkAction);
    }

    // Share
    const shareBtn = document.getElementById('btn-share');
    if (shareBtn) shareBtn.addEventListener('click', _openShareAndReportSheet);
  }

  async function _openDirectChat() {
    if (!Auth.isLoggedIn()) {
      window.location.href = '/login/?next=' + encodeURIComponent(window.location.pathname);
      return;
    }

    await _syncDirectChatAvailability();
    if (_isOwnProviderProfile) {
      _showToast('لا يمكنك محادثة نفسك');
      return;
    }

    const providerId = _safeInt(_providerId);
    if (!providerId) {
      _showToast('تعذر فتح الرسائل: معرف المزود غير صالح');
      return;
    }

    const res = await ApiClient.request(_withMode('/api/messaging/direct/thread/'), {
      method: 'POST',
      body: { provider_id: providerId },
    });

    if (res.ok && res.data && res.data.id) {
      window.location.href = '/chat/' + res.data.id + '/';
      return;
    }

    _showToast((res.data && (res.data.detail || res.data.error)) || 'تعذر فتح الرسائل حالياً');
  }

  async function _syncDirectChatAvailability() {
    _isOwnProviderProfile = false;
    if (!Auth.isLoggedIn()) {
      _applyDirectChatAvailability();
      return;
    }

    try {
      _currentProfile = await Auth.getProfile();
    } catch (_) {
      _currentProfile = null;
    }

    const currentProviderId = _safeInt(
      _currentProfile && (_currentProfile.provider_profile_id || _currentProfile.provider_id)
    );
    _isOwnProviderProfile = !!currentProviderId && String(currentProviderId) === String(_providerId);
    _applyDirectChatAvailability();
  }

  function _applyDirectChatAvailability() {
    ['btn-message', 'pd-btn-chat'].forEach((id) => {
      const button = document.getElementById(id);
      if (!button) return;
      button.disabled = _isOwnProviderProfile;
      button.setAttribute('aria-disabled', _isOwnProviderProfile ? 'true' : 'false');
      button.classList.toggle('hidden', _isOwnProviderProfile);
    });
  }

  function _bindSpotlightSync() {
    if (_spotlightSyncBound) return;
    _spotlightSyncBound = true;
    window.addEventListener('nw:spotlight-engagement-update', (event) => {
      const detail = event?.detail || {};
      const providerId = _safeInt(detail.provider_id);
      if (!providerId || String(providerId) !== String(_providerId)) return;
      const itemId = _safeInt(detail.id);
      if (!itemId) return;

      const target = _spotlights.find((item) => _safeInt(item.id) === itemId);
      if (!target) return;

      const previousLikes = _safeInt(target.likes_count);
      const previousSaves = _safeInt(target.saves_count);

      target.likes_count = _safeInt(detail.likes_count);
      target.saves_count = _safeInt(detail.saves_count);
      target.is_liked = _asBool(detail.is_liked);
      target.is_saved = _asBool(detail.is_saved);

      if (_mediaLikesTotal !== null) {
        _mediaLikesTotal = Math.max(0, _safeInt(_mediaLikesTotal) + (target.likes_count - previousLikes));
      }

      _syncSpotlightEngagementTotals();
      _updateSpotlightBadge(target);
      _recomputeEngagementView();
    });
  }

  function _bindPortfolioSync() {
    if (_portfolioSyncBound) return;
    _portfolioSyncBound = true;
    window.addEventListener('nw:portfolio-engagement-update', (event) => {
      const detail = event?.detail || {};
      const providerId = _safeInt(detail.provider_id);
      if (!providerId || String(providerId) !== String(_providerId)) return;
      const itemId = _safeInt(detail.id);
      if (!itemId) return;

      const target = _portfolioItems.find((item) => _safeInt(item.id) === itemId);
      if (!target) return;

      target.likes_count = _safeInt(detail.likes_count);
      target.saves_count = _safeInt(detail.saves_count);
      target.is_liked = _asBool(detail.is_liked);
      target.is_saved = _asBool(detail.is_saved);

      _syncPortfolioEngagementTotals();
      _updatePortfolioBadge(target);
      _recomputeEngagementView();
    });
  }

  function _resolveReturnNavigation() {
    try {
      const params = new URLSearchParams(window.location.search || '');
      const fromMap = params.get('from_map') === '1';
      const returnTo = String(params.get('return_to') || '').trim();
      const returnLabel = String(params.get('return_label') || '').trim();

      if (!fromMap && !returnTo) return null;

      const fallbackMapPath = '/providers-map/';
      const rawTarget = returnTo || fallbackMapPath;
      let href = _sanitizeInternalReturnPath(rawTarget);
      if (!href) return null;

      if (fromMap && href.startsWith('/search')) {
        const normalized = new URL(href, window.location.origin);
        if (normalized.searchParams.get('open_map') !== '1') {
          normalized.searchParams.set('open_map', '1');
        }
        href = normalized.pathname + normalized.search + normalized.hash;
      }

      return {
        href,
        label: returnLabel || (fromMap ? 'العودة إلى الخريطة' : 'العودة'),
      };
    } catch (_) {
      return {
        href: '/providers-map/',
        label: 'العودة إلى الخريطة',
      };
    }
  }

  function _sanitizeInternalReturnPath(rawPath) {
    const candidate = String(rawPath || '').trim();
    if (!candidate || candidate.startsWith('//')) return '';
    try {
      const parsed = new URL(candidate, window.location.origin);
      if (parsed.origin !== window.location.origin) return '';
      if (!parsed.pathname.startsWith('/')) return '';
      return parsed.pathname + parsed.search + parsed.hash;
    } catch (_) {
      return '';
    }
  }

  /* ── Load all data ── */
  async function _loadAll() {
    _setInitialShellLoading(true);
    const providerPath = _withMode('/api/providers/' + _providerId + '/');
    const statsPath = _withMode('/api/providers/' + _providerId + '/stats/');
    const [provRes, statsRes] = await Promise.all([
      ApiClient.get(providerPath),
      ApiClient.get(statsPath)
    ]);

    if (provRes.ok && provRes.data) {
      _providerData = provRes.data;
      _renderProvider(provRes.data, statsRes.ok ? statsRes.data : null);
      if (typeof NwAnalytics !== 'undefined') {
        NwAnalytics.trackOnce(
          'provider.profile_view',
          {
            surface: 'mobile_web.provider_detail',
            source_app: 'providers',
            object_type: 'ProviderProfile',
            object_id: String(_providerId || ''),
            payload: {
              mode: _mode || 'client',
              has_stats: !!(statsRes.ok && statsRes.data),
            },
          },
          'provider.profile_view:mobile_web:' + String(_providerId || '')
        );
      }
    }
    _setInitialShellLoading(false);
    _syncFollowState();

    // Parallel: services, portfolio, reviews, spotlights
    _loadServices();
    _loadPortfolio();
    _loadReviews();
    _loadSpotlights();
  }

  /* ═══════════════════════════════════════════════
     RENDER PROVIDER PROFILE
     ═══════════════════════════════════════════════ */
  function _renderProvider(p, stats) {
    _providerWhatsappUrl = _pickFirstText(p.whatsapp_url, p.whatsappUrl);
    _providerPhone = _pickFirstText(
      p.phone,
      p.whatsapp,
      p.phone_number,
      p.phoneNumber
    );

    // ── Cover ──
    const coverEl = document.getElementById('pd-cover');
    const coverImage = _pickFirstText(p.cover_image, p.coverImage);
    if (coverEl) {
      coverEl.querySelectorAll('img.pd-cover-media, img.pd-cover-bg').forEach((img) => img.remove());
    }
    if (coverImage && coverEl) {
      const coverUrl = ApiClient.mediaUrl(coverImage);
      const bg = UI.lazyImg(coverUrl, '');
      bg.className = 'pd-cover-bg';
      bg.setAttribute('aria-hidden', 'true');

      const img = UI.lazyImg(coverUrl, 'غلاف');
      img.className = 'pd-cover-media';

      coverEl.insertBefore(bg, coverEl.firstChild);
      coverEl.insertBefore(img, coverEl.firstChild);
      coverEl.classList.add('has-media');
    } else if (coverEl) {
      coverEl.classList.remove('has-media');
    }

    // ── Avatar ──
    const avatarEl = document.getElementById('pd-avatar');
    const profileImage = _pickFirstText(p.profile_image, p.profileImage);
    const displayName = _pickFirstText(p.display_name, p.displayName);
    if (profileImage) {
      avatarEl.textContent = '';
      avatarEl.appendChild(UI.lazyImg(ApiClient.mediaUrl(profileImage), displayName || ''));
    } else {
      avatarEl.textContent = displayName.charAt(0) || '؟';
    }

    // ── Verification badges (blue/green unified style) ──
    const blueBadge = document.getElementById('pd-verified-badge-blue');
    const greenBadge = document.getElementById('pd-verified-badge-green');
    if (blueBadge) {
      blueBadge.classList.toggle('hidden', !_asBool(p.is_verified_blue));
    }
    if (greenBadge) {
      greenBadge.classList.toggle('hidden', !_asBool(p.is_verified_green));
    }

    const excellenceWrap = _ensureExcellenceMount();
    if (excellenceWrap) {
      excellenceWrap.textContent = '';
      const excellence = UI.buildExcellenceBadges(p.excellence_badges, {
        className: 'excellence-badges pd-excellence-chip-row',
        iconSize: 12,
      });
      if (excellence) {
        excellenceWrap.classList.remove('hidden');
        excellenceWrap.style.display = 'flex';
        excellenceWrap.style.justifyContent = 'center';
        excellenceWrap.style.marginTop = '10px';
        excellenceWrap.appendChild(excellence);
      } else {
        excellenceWrap.classList.add('hidden');
        excellenceWrap.style.display = 'none';
      }
    }

    // ── Name & handle ──
    const username = _pickFirstText(p.username, p.user_name);
    _setText('pd-name', displayName);
    _setText('pd-handle', username ? ('@' + username) : '');
    _syncCategoryViews();

    // ── Stats ──
    const completed = stats?.completed_requests ?? p.completed_requests ?? p.completed_orders_count ?? 0;
    const followers = stats?.followers_count ?? p.followers_count ?? 0;
    const following = stats?.following_count ?? p.following_count ?? 0;
    const profileLikes = stats?.profile_likes_count ?? stats?.likes_count ?? p.likes_count ?? 0;
    _mediaLikesTotal = _safeNullableInt(stats?.media_likes_count);
    const rating = p.rating_avg ? parseFloat(p.rating_avg).toFixed(1) : '-';

    _setText('stat-completed', completed);
    _setText('stat-followers', followers);
    _profileLikesBase = _safeInt(profileLikes);
    _setText('stat-likes', _mediaLikesTotal !== null ? _mediaLikesTotal : _profileLikesBase);
    _setText('stat-rating', rating);

    _recomputeEngagementView();

    const followingBtn = document.getElementById('btn-show-following');
    if (followingBtn) {
      followingBtn.dataset.count = String(following || 0);
    }

    // ── Follow state ──
    _isFollowing = _asBool(p.is_following);
    _updateFollowBtn();

    // ── Profile tab content ──
    _renderProfileTab(p);

    // ── Page meta ──
    _applySeoMeta(p, displayName);
  }

  /* ── Render profile tab details ── */
  function _renderProfileTab(p) {
    const unavailable = 'غير متوفر';
    const bioText = _pickFirstText(p.bio, p.description);
    const providerTypeLabel = _pickFirstText(p.provider_type_label, p.providerTypeLabel);
    const whatsappRaw = _pickFirstText(p.whatsapp, p.phone, p.phone_number, p.phoneNumber);
    const websiteRaw = String(p.website || '').trim();
    const cityText = _displayOrUnavailable(UI.formatCityDisplay(p.city_display || p.city, p.region || p.region_name), unavailable);
    const experienceText = p.years_experience ? p.years_experience + ' سنوات' : unavailable;
    const serviceRangeText = _resolveServiceRangeKm(p) + ' كم';
    const socialCard = document.getElementById('pd-social-card');

    // Bio
    _setText('pd-bio', bioText || 'لا يوجد وصف');

    // Registration data
    const mainCategory = _resolveMainCategory(p);
    const subCategory = _resolveSubCategory(p);
    _setText('pd-provider-type', _displayOrUnavailable(providerTypeLabel, unavailable));
    _setText('pd-main-category', _displayOrUnavailable(mainCategory, unavailable));
    _setText('pd-sub-category', _displayOrUnavailable(subCategory, unavailable));

    // Experience
    _setText('pd-experience', experienceText);
    _setText('pd-whatsapp', _displayOrUnavailable(whatsappRaw, unavailable));
    _setText('pd-website', websiteRaw || unavailable);
    _setText('pd-city-name', cityText);
    _setText('pd-overview-city', cityText);
    _setText('pd-overview-experience', experienceText);
    _setText('pd-overview-range', serviceRangeText);

    // ── Website ──
    const websiteBtn = document.getElementById('pd-website-open');
    if (websiteBtn) {
      websiteBtn.disabled = !websiteRaw;
      websiteBtn.classList.toggle('disabled', !websiteRaw);
      websiteBtn.onclick = () => {
        if (!websiteRaw) return;
        const url = websiteRaw.startsWith('http') ? websiteRaw : ('https://' + websiteRaw);
        window.open(url, '_blank', 'noopener');
      };
    }

    // ── Social accounts (fixed 3 rows like Flutter) ──
    _socialUrls.instagram = _findSocialUrl(p, 'instagram');
    _socialUrls.x = _findSocialUrl(p, 'x.com') || _findSocialUrl(p, 'twitter');
    _socialUrls.snapchat = _findSocialUrl(p, 'snapchat');
    if (socialCard) {
      socialCard.classList.toggle(
        'hidden',
        !_socialUrls.instagram && !_socialUrls.x && !_socialUrls.snapchat,
      );
    }

    _setSocialRow('instagram', 'pd-social-instagram', 'pd-social-open-instagram', unavailable);
    _setSocialRow('x', 'pd-social-x', 'pd-social-open-x', unavailable);
    _setSocialRow('snapchat', 'pd-social-snapchat', 'pd-social-open-snapchat', unavailable);

    try {
      _renderServiceRangeMap(p);
    } catch (_) {
      _setText('pd-service-range-summary', 'تعذر عرض نطاق الخدمة على الخريطة حالياً.');
      const mapEl = document.getElementById('pd-service-range-map');
      const emptyEl = document.getElementById('pd-service-range-map-empty');
      if (mapEl) mapEl.classList.add('hidden');
      if (emptyEl) {
        emptyEl.textContent = 'تعذر عرض الخريطة حالياً.';
        emptyEl.classList.remove('hidden');
      }
    }
  }

  async function _openConnectionsSheet(kind) {
    const isFollowers = kind === 'followers';
    const endpoint = _withMode(isFollowers
      ? '/api/providers/' + _providerId + '/followers/'
      : '/api/providers/' + _providerId + '/following/');
    const title = isFollowers ? 'متابعون' : 'يتابع';
    const countEl = isFollowers ? document.getElementById('stat-followers') : document.getElementById('btn-show-following');
    const count = countEl ? (parseInt(isFollowers ? countEl.textContent : countEl.dataset.count, 10) || 0) : 0;

    const res = await ApiClient.get(endpoint);
    const items = res.ok
      ? (Array.isArray(res.data) ? res.data : (res.data?.results || []))
      : [];

    const backdrop = UI.el('div', { className: 'pd-sheet-backdrop' });
    const sheet = UI.el('div', { className: 'pd-sheet' });
    const handle = UI.el('div', { className: 'pd-sheet-handle' });
    const header = UI.el('div', { className: 'pd-sheet-header' });
    const heading = UI.el('div', {
      className: 'pd-sheet-title',
      textContent: title + ' (' + count + ')',
    });
    const closeBtn = UI.el('button', {
      className: 'pd-sheet-close',
      type: 'button',
      textContent: '×',
    });
    closeBtn.setAttribute('aria-label', 'إغلاق');
    closeBtn.addEventListener('click', closeSheet);

    header.appendChild(heading);
    header.appendChild(closeBtn);
    sheet.appendChild(handle);
    sheet.appendChild(header);

    const body = UI.el('div', { className: 'pd-sheet-body' });

    if (!res.ok && !items.length) {
      body.appendChild(UI.el('div', {
        className: 'pd-sheet-empty',
        textContent: res.error || 'تعذر تحميل القائمة',
      }));
    } else if (!items.length) {
      body.appendChild(UI.el('div', {
        className: 'pd-sheet-empty',
        textContent: isFollowers ? 'لا يوجد متابعون بعد' : 'لا يوجد متابَعون بعد',
      }));
    } else {
      const list = UI.el('div', { className: 'pd-sheet-list' });
      items.forEach(item => {
        const name = String(item.display_name || item.name || item.username || 'مستخدم').trim() || 'مستخدم';
        const username = String(item.username || item.username_display || '').trim();
        const avatarUrl = ApiClient.mediaUrl(item.profile_image || item.avatar || '');

        const row = UI.el('div', { className: 'pd-sheet-item' });
        const avatar = UI.el('div', { className: 'pd-sheet-avatar' });
        if (avatarUrl) avatar.appendChild(UI.lazyImg(avatarUrl, name));
        else avatar.appendChild(UI.el('span', { textContent: name.charAt(0) }));
        row.appendChild(avatar);

        const meta = UI.el('div', { className: 'pd-sheet-meta' });
        meta.appendChild(UI.el('div', { className: 'pd-sheet-name', textContent: name }));
        if (username) {
          meta.appendChild(UI.el('div', { className: 'pd-sheet-handle-text', textContent: '@' + username }));
        }
        row.appendChild(meta);
        list.appendChild(row);
      });
      body.appendChild(list);
    }

    sheet.appendChild(body);
    backdrop.appendChild(sheet);
    document.body.appendChild(backdrop);
    requestAnimationFrame(() => backdrop.classList.add('open'));

    backdrop.addEventListener('click', e => {
      if (e.target === backdrop) closeSheet();
    });

    function closeSheet() {
      backdrop.classList.remove('open');
      setTimeout(() => backdrop.remove(), 180);
    }
  }

  function _buildProviderLink() {
    const resolvedId = _safeInt(_providerData && (_providerData.id || _providerData.provider_id))
      || _safeInt(_providerId)
      || _providerId
      || 'provider';
    const base = String(ApiClient.baseUrl || window.location.origin || '').replace(/\/+$/, '');
    return base + '/provider/' + encodeURIComponent(String(resolvedId)) + '/';
  }

  function _buildQrImageUrl(targetUrl) {
    return 'https://api.qrserver.com/v1/create-qr-code/?size=420x420&data=' + encodeURIComponent(String(targetUrl || ''));
  }

  async function _openShareAndReportSheet() {
    const providerLink = _buildProviderLink();
    const qrImageUrl = _buildQrImageUrl(providerLink);
    const providerName = _trimText(document.getElementById('pd-name')?.textContent) || 'مقدم خدمة';

    const existing = document.querySelector('.pd-share-sheet-backdrop');
    if (existing) existing.remove();

    const backdrop = UI.el('div', { className: 'pd-sheet-backdrop pd-share-sheet-backdrop' });
    const sheet = UI.el('div', { className: 'pd-sheet pd-share-sheet' });
    const handle = UI.el('div', { className: 'pd-sheet-handle' });
    const header = UI.el('div', { className: 'pd-sheet-header' });
    const heading = UI.el('div', {
      className: 'pd-sheet-title',
      textContent: 'مشاركة نافذة مقدم الخدمة',
    });
    const closeBtn = UI.el('button', {
      className: 'pd-sheet-close',
      type: 'button',
      textContent: '×',
    });
    closeBtn.setAttribute('aria-label', 'إغلاق');
    closeBtn.addEventListener('click', closeSheet);

    header.appendChild(heading);
    header.appendChild(closeBtn);
    sheet.appendChild(handle);
    sheet.appendChild(header);

    const body = UI.el('div', { className: 'pd-sheet-body pd-share-sheet-body' });
    const card = UI.el('div', { className: 'pd-share-card' });
    const qrWrap = UI.el('div', { className: 'pd-share-qr-wrap' });
    const qrImg = UI.el('img', {
      className: 'pd-share-qr',
      src: qrImageUrl,
      alt: 'رمز QR',
    });
    qrImg.addEventListener('error', () => {
      qrWrap.innerHTML = '';
      qrWrap.appendChild(UI.el('div', { className: 'pd-share-qr-fallback', textContent: 'QR' }));
    });
    qrWrap.appendChild(qrImg);
    card.appendChild(qrWrap);

    card.appendChild(UI.el('p', {
      className: 'pd-share-link',
      textContent: providerLink,
    }));

    const actions = UI.el('div', { className: 'pd-share-actions' });
    const copyBtn = UI.el('button', {
      type: 'button',
      className: 'pd-share-btn',
      textContent: 'نسخ الرابط',
    });
    copyBtn.addEventListener('click', async () => {
      const copied = await _copyToClipboard(providerLink);
      closeSheet();
      _showToast(copied ? 'تم نسخ الرابط' : 'تعذر نسخ الرابط');
    });

    const shareBtn = UI.el('button', {
      type: 'button',
      className: 'pd-share-btn',
      textContent: 'مشاركة',
    });
    shareBtn.addEventListener('click', async () => {
      if (navigator.share) {
        try {
          await navigator.share({
            title: 'مشاركة نافذة مقدم الخدمة',
            text: providerName,
            url: providerLink,
          });
          closeSheet();
          _showToast('تمت مشاركة الرابط');
          return;
        } catch (err) {
          if (err && err.name === 'AbortError') return;
        }
      }
      const copied = await _copyToClipboard(providerLink);
      closeSheet();
      _showToast(copied ? 'تم نسخ الرابط' : 'تعذر مشاركة الرابط');
    });

    actions.appendChild(copyBtn);
    actions.appendChild(shareBtn);
    card.appendChild(actions);
    body.appendChild(card);

    const reportBtn = UI.el('button', {
      type: 'button',
      className: 'pd-share-report-btn',
    });
    reportBtn.innerHTML = [
      '<span class="pd-share-report-icon" aria-hidden="true">',
      '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">',
      '<path d="M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1z"></path>',
      '<line x1="4" y1="22" x2="4" y2="15"></line>',
      '</svg>',
      '</span>',
      '<span>الإبلاغ عن مقدم الخدمة</span>',
    ].join('');
    reportBtn.addEventListener('click', () => {
      closeSheet();
      _openProviderReportDialog();
    });
    body.appendChild(reportBtn);

    sheet.appendChild(body);
    backdrop.appendChild(sheet);
    document.body.appendChild(backdrop);
    requestAnimationFrame(() => backdrop.classList.add('open'));

    backdrop.addEventListener('click', (e) => {
      if (e.target === backdrop) closeSheet();
    });

    function closeSheet() {
      backdrop.classList.remove('open');
      setTimeout(() => backdrop.remove(), 180);
    }
  }

  async function _copyToClipboard(text) {
    const value = String(text || '');
    if (!value) return false;

    if (navigator.clipboard && window.isSecureContext) {
      try {
        await navigator.clipboard.writeText(value);
        return true;
      } catch (_) {}
    }

    try {
      const input = document.createElement('textarea');
      input.value = value;
      input.setAttribute('readonly', '');
      input.style.position = 'fixed';
      input.style.top = '-9999px';
      input.style.left = '-9999px';
      document.body.appendChild(input);
      input.focus();
      input.select();
      const ok = document.execCommand('copy');
      input.remove();
      return !!ok;
    } catch (_) {
      return false;
    }
  }

  function _openProviderReportDialog() {
    const reasons = [
      'محتوى غير لائق',
      'تحرش أو إزعاج',
      'احتيال أو نصب',
      'محتوى مسيء',
      'انتهاك الخصوصية',
      'أخرى',
    ];

    const providerName = _trimText(document.getElementById('pd-name')?.textContent) || 'مقدم خدمة';
    const providerHandle = _trimText(document.getElementById('pd-handle')?.textContent);
    const entityText = providerHandle ? (providerName + ' (' + providerHandle + ')') : providerName;

    const oldDialog = document.querySelector('.pd-report-backdrop');
    if (oldDialog) oldDialog.remove();

    const backdrop = UI.el('div', { className: 'pd-report-backdrop' });
    const dialog = UI.el('div', { className: 'pd-report-dialog' });

    const titleRow = UI.el('div', { className: 'pd-report-title-row' });
    const titleIcon = UI.el('span', { className: 'pd-report-title-icon' });
    titleIcon.innerHTML = [
      '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">',
      '<path d="M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1z"></path>',
      '<line x1="4" y1="22" x2="4" y2="15"></line>',
      '</svg>',
    ].join('');
    titleRow.appendChild(titleIcon);
    titleRow.appendChild(UI.el('h3', {
      className: 'pd-report-title',
      textContent: 'إبلاغ عن مزود خدمة',
    }));
    dialog.appendChild(titleRow);

    const infoBox = UI.el('div', { className: 'pd-report-info' });
    infoBox.appendChild(UI.el('p', {
      className: 'pd-report-info-label',
      textContent: 'بيانات المبلغ عنه:',
    }));
    infoBox.appendChild(UI.el('p', {
      className: 'pd-report-info-value',
      textContent: entityText,
    }));
    infoBox.appendChild(UI.el('p', {
      className: 'pd-report-context',
      textContent: 'نوع البلاغ: مزود خدمة',
    }));
    dialog.appendChild(infoBox);

    const reasonLabel = UI.el('label', {
      className: 'pd-report-label',
      textContent: 'سبب الإبلاغ:',
    });
    reasonLabel.setAttribute('for', 'pd-report-reason');
    dialog.appendChild(reasonLabel);

    const reasonSelect = UI.el('select', {
      className: 'pd-report-select',
      id: 'pd-report-reason',
    });
    reasons.forEach((reason) => {
      reasonSelect.appendChild(UI.el('option', { value: reason, textContent: reason }));
    });
    dialog.appendChild(reasonSelect);

    const detailsLabel = UI.el('label', {
      className: 'pd-report-label',
      textContent: 'تفاصيل إضافية (اختياري):',
    });
    detailsLabel.setAttribute('for', 'pd-report-details');
    dialog.appendChild(detailsLabel);

    const detailsInput = UI.el('textarea', {
      className: 'pd-report-textarea',
      id: 'pd-report-details',
      rows: 4,
      placeholder: 'اكتب التفاصيل هنا...',
    });
    detailsInput.maxLength = 500;
    dialog.appendChild(detailsInput);

    const actions = UI.el('div', { className: 'pd-report-actions' });
    const cancelBtn = UI.el('button', {
      type: 'button',
      className: 'pd-report-btn pd-report-btn-cancel',
      textContent: 'إلغاء',
    });
    cancelBtn.addEventListener('click', closeDialog);

    const submitBtn = UI.el('button', {
      type: 'button',
      className: 'pd-report-btn pd-report-btn-submit',
      textContent: 'إرسال البلاغ',
    });
    submitBtn.addEventListener('click', () => {
      closeDialog();
      _showToast('تم إرسال البلاغ للإدارة. شكراً لك');
    });

    actions.appendChild(cancelBtn);
    actions.appendChild(submitBtn);
    dialog.appendChild(actions);
    backdrop.appendChild(dialog);
    document.body.appendChild(backdrop);

    requestAnimationFrame(() => backdrop.classList.add('open'));
    backdrop.addEventListener('click', (e) => {
      if (e.target === backdrop) closeDialog();
    });

    function closeDialog() {
      backdrop.classList.remove('open');
      setTimeout(() => backdrop.remove(), 180);
    }
  }

  /* ═══ Follow / Unfollow ═══ */
  async function _toggleFollow() {
    if (!Auth.isLoggedIn()) { window.location.href = '/login/?next=' + encodeURIComponent(window.location.pathname); return; }
    const url = _withMode(_isFollowing
      ? '/api/providers/' + _providerId + '/unfollow/'
      : '/api/providers/' + _providerId + '/follow/');
    const btn = document.getElementById('btn-follow');
    btn.disabled = true;
    const res = await ApiClient.request(url, { method: 'POST' });
    btn.disabled = false;
    if (res.ok) {
      _isFollowing = !_isFollowing;
      _updateFollowBtn();
      const el = document.getElementById('stat-followers');
      if (el) {
        let c = parseInt(el.textContent) || 0;
        c += _isFollowing ? 1 : -1;
        el.textContent = Math.max(0, c);
      }
    }
  }

  async function _syncFollowState() {
    if (!Auth.isLoggedIn()) return;
    const res = await ApiClient.get(_withMode('/api/providers/me/following/'));
    if (!res.ok) return;
    const list = Array.isArray(res.data) ? res.data : (res.data?.results || []);
    const targetId = _safeInt(_providerId);
    const isFollowing = list.some(entry => {
      const provider = entry && (entry.provider || entry);
      return _safeInt(provider && provider.id) === targetId;
    });
    _isFollowing = isFollowing;
    _updateFollowBtn();
  }

  function _updateFollowBtn() {
    const btn = document.getElementById('btn-follow');
    if (!btn) return;
    if (_isFollowing) {
      btn.classList.add('following');
      btn.querySelector('span') ? null : null;
      // Replace inner content
      btn.textContent = '';
      const svg = _createSVG('<path d="M16 21v-2a4 4 0 00-4-4H5a4 4 0 00-4 4v2"/><circle cx="8.5" cy="7" r="4"/><line x1="23" y1="11" x2="17" y2="11"/>', 16);
      btn.appendChild(svg);
      btn.appendChild(document.createTextNode(' إلغاء المتابعة'));
    } else {
      btn.classList.remove('following');
      btn.textContent = '';
      const svg = _createSVG('<path d="M16 21v-2a4 4 0 00-4-4H5a4 4 0 00-4 4v2"/><circle cx="8.5" cy="7" r="4"/><line x1="20" y1="8" x2="20" y2="14"/><line x1="23" y1="11" x2="17" y2="11"/>', 16);
      btn.appendChild(svg);
      btn.appendChild(document.createTextNode(' متابعة'));
    }
  }

  /* ═══ Spotlights / Highlights ═══ */
  async function _loadSpotlights() {
    const res = await ApiClient.get(_withMode('/api/providers/' + _providerId + '/spotlights/'));
    if (!res.ok) return;
    const raw = Array.isArray(res.data) ? res.data : (res.data?.results || []);
    if (!raw.length) return;

    _spotlights = raw.map(item => {
      const rawCaption = String(item.caption || item.title || '').trim();
      return {
        id: item.id,
        source: 'spotlight',
        provider_id: item.provider_id || _safeInt(_providerId),
        provider_display_name: _pickFirstText(
          item.provider_display_name,
          item.providerDisplayName,
          _providerData?.display_name,
          _providerData?.displayName
        ),
        provider_profile_image: _pickFirstText(
          item.provider_profile_image,
          item.providerProfileImage,
          _providerData?.profile_image,
          _providerData?.profileImage
        ),
        file_type: item.file_type || 'image',
        file_url: item.file_url || item.media_url || '',
        thumbnail_url: item.thumbnail_url || item.file_url || item.media_url || '',
        mode_context: _mode || 'client',
        section_title: 'لمحات',
        media_label: _deriveSpotlightMediaLabel(item, rawCaption),
        caption: rawCaption,
        likes_count: _safeInt(item.likes_count),
        saves_count: _safeInt(item.saves_count),
        is_liked: _asBool(item.is_liked),
        is_saved: _asBool(item.is_saved),
      };
    }).filter(item => (item.file_url || item.thumbnail_url));

    _syncSpotlightEngagementTotals();
    _recomputeEngagementView();
    _renderSpotlightsRow();
  }

  function _renderSpotlightsRow() {
    const section = document.getElementById('pd-highlights-section');
    const row = document.getElementById('pd-highlights');
    if (!section || !row) return;
    if (!_spotlights.length) {
      section.classList.add('hidden');
      row.textContent = '';
      return;
    }

    section.classList.remove('hidden');
    row.textContent = '';
    _spotlights.forEach((item, idx) => {
      const el = UI.el('div', { className: 'pd-highlight-item' });
      el.dataset.itemId = String(_safeInt(item.id));
      const thumb = UI.el('div', { className: 'pd-highlight-thumb' });
      const imgUrl = item.thumbnail_url || item.file_url;
      if (imgUrl) thumb.appendChild(UI.lazyImg(ApiClient.mediaUrl(imgUrl), ''));

      const stats = UI.el('div', { className: 'pd-highlight-stats' });
      const likes = UI.el('span', {
        className: 'pd-highlight-stat' + (item.is_liked ? ' active' : ''),
        textContent: '❤ ' + String(_safeInt(item.likes_count)),
      });
      likes.dataset.stat = 'likes';
      const saves = UI.el('span', {
        className: 'pd-highlight-stat' + (item.is_saved ? ' active' : ''),
        textContent: '🔖 ' + String(_safeInt(item.saves_count)),
      });
      saves.dataset.stat = 'saves';
      stats.appendChild(likes);
      stats.appendChild(saves);
      thumb.appendChild(stats);

      el.appendChild(thumb);

      const caption = (item.caption || '').toString().trim();
      el.appendChild(UI.el('div', { className: 'pd-highlight-label', textContent: caption || 'لمحة' }));

      el.addEventListener('click', () => {
        if (typeof SpotlightViewer !== 'undefined') {
          SpotlightViewer.open(_spotlights, idx, {
            source: 'spotlight',
            label: 'لمحة',
            eventName: 'nw:spotlight-engagement-update',
            modeContext: _mode || 'client',
          });
        }
      });

      row.appendChild(el);
    });
  }

  function _syncSpotlightEngagementTotals() {
    _spotlightLikes = _spotlights.reduce((sum, item) => sum + _safeInt(item.likes_count), 0);
    _spotlightSaves = _spotlights.reduce((sum, item) => sum + _safeInt(item.saves_count), 0);
    _spotlightSavedByMe = _spotlights.some(item => !!item.is_saved);
  }

  function _updateSpotlightBadge(item) {
    const key = String(_safeInt(item?.id));
    if (!key) return;
    const root = document.querySelector('.pd-highlight-item[data-item-id="' + key + '"]');
    if (!root) return;
    const likesEl = root.querySelector('.pd-highlight-stat[data-stat="likes"]');
    const savesEl = root.querySelector('.pd-highlight-stat[data-stat="saves"]');
    if (likesEl) {
      likesEl.textContent = '❤ ' + String(_safeInt(item.likes_count));
      likesEl.classList.toggle('active', _asBool(item.is_liked));
    }
    if (savesEl) {
      savesEl.textContent = '🔖 ' + String(_safeInt(item.saves_count));
      savesEl.classList.toggle('active', _asBool(item.is_saved));
    }
  }

  /* ═══ Services ═══ */
  async function _loadServices() {
    const container = document.getElementById('pd-services-list');
    const emptyEl = document.getElementById('pd-services-empty');
    const countEl = document.getElementById('pd-services-count');
    _setTabLoadingState('services', true);
    const res = await ApiClient.get('/api/providers/' + _providerId + '/services/');
    if (!res.ok) {
      _setTabMeta('services', '0');
      _setTabLoadingState('services', false);
      return;
    }
    const list = Array.isArray(res.data) ? res.data : (res.data?.results || []);
    _refreshDerivedCategories(list);
    _syncCategoryViews();
    container.textContent = '';
    if (emptyEl) emptyEl.classList.add('hidden');
    _setTabLoadingState('services', false);
    if (countEl) {
      countEl.textContent = _serviceCountLabel(list.length);
    }
    _setTabMeta('services', _formatTabCount(list.length));

    if (!list.length) {
      if (emptyEl) emptyEl.classList.remove('hidden');
      return;
    }

    list.forEach((svc, idx) => {
      const title = String(svc.title || svc.name || '').trim() || 'خدمة بدون اسم';
      const description = String(svc.description || '').trim();
      const subcategory = (svc.subcategory && typeof svc.subcategory === 'object') ? svc.subcategory : null;
      const categoryLabel = String(
        (subcategory && subcategory.category_name) ||
        svc.category_name ||
        svc.main_category ||
        ''
      ).trim();
      const subCategoryLabel = String(
        (subcategory && subcategory.name) ||
        svc.subcategory_name ||
        svc.sub_category ||
        ''
      ).trim();
      const serviceTypeLabel = _serviceUnitLabel(svc);

      const card = UI.el('div', { className: 'pd-service-list-card' });
      card.appendChild(UI.el('div', { className: 'pd-service-list-glow' }));

      const head = UI.el('div', { className: 'pd-service-list-head' });
      const headMain = UI.el('div', { className: 'pd-service-list-head-main' });
      headMain.appendChild(UI.el('span', { className: 'pd-service-index', textContent: String(idx + 1) }));

      const titleWrap = UI.el('div', { className: 'pd-service-list-title-wrap' });
      titleWrap.appendChild(UI.el('span', { className: 'pd-service-list-kicker', textContent: 'خدمة منشورة' }));
      titleWrap.appendChild(UI.el('h4', { className: 'pd-service-list-title', textContent: title }));
      headMain.appendChild(titleWrap);
      head.appendChild(headMain);

      const priceBadge = UI.el('div', { className: 'pd-service-price-badge' });
      priceBadge.appendChild(UI.el('span', { className: 'pd-service-price-label', textContent: 'التسعير' }));
      priceBadge.appendChild(UI.el('strong', { className: 'pd-service-price-value', textContent: _servicePriceLabel(svc) }));
      head.appendChild(priceBadge);
      card.appendChild(head);

      if (description) {
        card.appendChild(UI.el('p', { className: 'pd-service-list-desc', textContent: description }));
      }

      const chips = UI.el('div', { className: 'pd-service-list-chips' });
      if (serviceTypeLabel) {
        chips.appendChild(UI.el('span', { className: 'pd-service-chip primary', textContent: serviceTypeLabel }));
      }
      if (categoryLabel) {
        chips.appendChild(UI.el('span', { className: 'pd-service-chip', textContent: categoryLabel }));
      }
      if (subCategoryLabel) {
        chips.appendChild(UI.el('span', { className: 'pd-service-chip', textContent: subCategoryLabel }));
      }
      card.appendChild(chips);

      const footer = UI.el('div', { className: 'pd-service-list-footer' });
      footer.appendChild(UI.el('span', {
        className: 'pd-service-footnote',
        textContent: 'للتفاهم حول هذه الخدمة استخدم أزرار المتابعة والتواصل أعلى الصفحة.',
      }));
      card.appendChild(footer);

      container.appendChild(card);
    });
  }

  function _servicePriceLabel(service) {
    const from = _asNumber(service.price_from);
    const to = _asNumber(service.price_to);
    const unit = _serviceUnitLabel(service);
    const suffix = unit ? (' / ' + unit) : '';

    if (!Number.isFinite(from) && !Number.isFinite(to)) return 'السعر: حسب الاتفاق';
    if (Number.isFinite(from) && Number.isFinite(to)) {
      if (Math.abs(from - to) < 0.0001) {
        return 'السعر: ' + _formatCompactNumber(from) + suffix;
      }
      return 'السعر: ' + _formatCompactNumber(from) + ' - ' + _formatCompactNumber(to) + suffix;
    }
    const value = Number.isFinite(from) ? from : to;
    if (Number.isFinite(value)) return 'السعر: ' + _formatCompactNumber(value) + suffix;
    return 'السعر: حسب الاتفاق';
  }

  function _serviceUnitLabel(service) {
    const explicitLabel = String(service.price_unit_label || service.priceUnitLabel || '').trim();
    if (explicitLabel) return explicitLabel;

    const raw = String(service.price_unit || service.priceUnit || '').trim();
    const mapping = {
      fixed: 'سعر ثابت',
      starting_from: 'يبدأ من',
      hour: 'بالساعة',
      day: 'باليوم',
      negotiable: 'قابل للتفاوض',
    };
    return mapping[raw] || raw;
  }

  function _serviceCountLabel(count) {
    if (count === 0) return '0 خدمة';
    if (count === 1) return 'خدمة واحدة';
    if (count === 2) return 'خدمتان';
    if (count >= 3 && count <= 10) return count + ' خدمات';
    return count + ' خدمة';
  }

  function _asNumber(value) {
    if (value === null || value === undefined || value === '') return NaN;
    const n = Number(value);
    return Number.isFinite(n) ? n : NaN;
  }

  /* ═══ Portfolio ═══ */
  async function _loadPortfolio() {
    const container = document.getElementById('pd-portfolio-sections');
    const emptyEl = document.getElementById('pd-portfolio-empty');
    if (!container) return;
    _setTabLoadingState('portfolio', true);
    const res = await ApiClient.get(_withMode('/api/providers/' + _providerId + '/portfolio/'));
    if (!res.ok) {
      _setTabMeta('portfolio', '0');
      _setTabLoadingState('portfolio', false);
      return;
    }
    const list = Array.isArray(res.data) ? res.data : (res.data?.results || []);

    container.textContent = '';
    _updatePortfolioHeroMetrics(0, 0);
    _resetPortfolioPreviewObserver();

    if (!list.length) {
      if (emptyEl) emptyEl.classList.remove('hidden');
      _setTabLoadingState('portfolio', false);
      _syncPortfolioPreviewPlayback();
      return;
    }
    if (emptyEl) emptyEl.classList.add('hidden');

    const grouped = new Map();
    _portfolioItems = [];
    list.forEach(item => {
      const fileType = String(item.file_type || 'image').toLowerCase();
      const fileUrl = String(item.file_url || item.image || item.media_url || item.file || '').trim();
      const thumbUrl = String(item.thumbnail_url || '').trim();
      const media = fileUrl || thumbUrl;
      if (!media) return;

      const rawCaption = String(item.caption || item.title || '').trim();
      const sectionTitle = _extractPortfolioSectionTitle(rawCaption);
      const description = _extractPortfolioItemDescription(rawCaption, sectionTitle);

      if (!grouped.has(sectionTitle)) grouped.set(sectionTitle, []);
      const normalizedItem = {
        id: _safeInt(item.id),
        source: 'portfolio',
        provider_id: _safeInt(item.provider_id) || _safeInt(_providerId),
        provider_display_name: _pickFirstText(
          item.provider_display_name,
          item.providerDisplayName,
          _providerData?.display_name,
          _providerData?.displayName
        ),
        provider_profile_image: _pickFirstText(
          item.provider_profile_image,
          item.providerProfileImage,
          _providerData?.profile_image,
          _providerData?.profileImage
        ),
        type: fileType.startsWith('video') ? 'video' : 'image',
        media: media,
        file_type: fileType.startsWith('video') ? 'video' : 'image',
        file_url: fileUrl || media,
        thumbnail: thumbUrl,
        thumbnail_url: thumbUrl || fileUrl || media,
        mode_context: _mode || 'client',
        section_title: sectionTitle,
        media_label: _derivePortfolioMediaLabel(item, description, fileUrl),
        caption: rawCaption,
        desc: description,
        likes_count: _safeInt(item.likes_count),
        saves_count: _safeInt(item.saves_count),
        is_liked: _asBool(item.is_liked),
        is_saved: _asBool(item.is_saved),
      };
      grouped.get(sectionTitle).push(normalizedItem);
      _portfolioItems.push(normalizedItem);
    });

    _syncPortfolioEngagementTotals();
    _recomputeEngagementView();

    const sections = _resolvePortfolioSections(grouped);
    _updatePortfolioHeroMetrics(_portfolioItems.length, sections.length);
    sections.forEach(({ sectionTitle, sectionDesc, items }) => {
      const section = UI.el('section', { className: 'pd-portfolio-section' });
      const header = UI.el('div', { className: 'pd-portfolio-section-head' });
      header.appendChild(UI.el('h4', { className: 'pd-portfolio-section-title', textContent: sectionTitle }));
      const meta = UI.el('div', { className: 'pd-portfolio-section-meta' });
      meta.appendChild(UI.el('span', { className: 'pd-portfolio-section-count', textContent: String(items.length) }));
      meta.appendChild(UI.el('span', { className: 'pd-portfolio-section-hint', textContent: 'مرر أفقياً وافتح أي بطاقة' }));
      header.appendChild(meta);
      section.appendChild(header);

      if (sectionDesc) {
        section.appendChild(UI.el('p', { className: 'pd-portfolio-section-desc', textContent: sectionDesc }));
      }

      if (!items.length) {
        const emptyCard = UI.el('div', { className: 'pd-empty-section-card' });
        emptyCard.appendChild(UI.el('p', { className: 'pd-empty-title', textContent: 'لا توجد عناصر في هذا القسم حالياً' }));
        emptyCard.appendChild(UI.el('p', { className: 'pd-empty-subtitle', textContent: 'سيظهر المحتوى هنا عند إضافته من ملف مقدم الخدمة.' }));
        section.appendChild(emptyCard);
        container.appendChild(section);
        return;
      }

      const grid = UI.el('div', { className: 'pd-portfolio-grid pd-portfolio-reel-rail' });
      items.forEach((item, index) => {
        const el = UI.el('article', { className: 'pd-portfolio-item pd-portfolio-reel-card' });
        el.dataset.itemId = String(_safeInt(item.id));
        el.setAttribute('role', 'button');
        el.setAttribute('tabindex', '0');
        const displayUrl = (item.type === 'video' && item.thumbnail) ? item.thumbnail : item.media;
        const frame = UI.el('div', { className: 'pd-portfolio-frame' });
        if (item.type === 'video') {
          frame.appendChild(_buildPortfolioPreviewVideo(item, displayUrl, item.desc || sectionTitle));
        } else {
          frame.appendChild(UI.lazyImg(ApiClient.mediaUrl(displayUrl), item.desc || sectionTitle));
        }

        const topline = UI.el('div', { className: 'pd-portfolio-topline' });
        topline.appendChild(UI.el('span', { className: 'pd-portfolio-top-chip', textContent: sectionTitle }));
        topline.appendChild(UI.el('span', { className: 'pd-portfolio-top-chip muted', textContent: item.type === 'video' ? 'فيديو قصير' : 'صورة' }));
        frame.appendChild(topline);

        if (item.type === 'video') {
          const badge = UI.el('div', { className: 'pd-portfolio-video-badge' });
          badge.appendChild(_createSVG('<polygon points="5 3 19 12 5 21 5 3" fill="#fff"/>', 14));
          frame.appendChild(badge);
        }

        const overlay = UI.el('div', { className: 'pd-portfolio-overlay' });
        overlay.appendChild(UI.el('span', { className: 'pd-portfolio-overlay-kicker', textContent: item.type === 'video' ? 'شاهد العرض العمودي' : 'استعرض العمل' }));
        overlay.appendChild(UI.el('strong', { className: 'pd-portfolio-overlay-title', textContent: (item.desc && item.desc !== 'بدون وصف') ? item.desc : item.media_label }));
        overlay.appendChild(UI.el('span', { className: 'pd-portfolio-open-indicator', textContent: 'فتح بملء الشاشة' }));
        frame.appendChild(overlay);

        const stats = UI.el('div', { className: 'pd-portfolio-item-stats' });
        const likesStat = UI.el('button', { className: 'pd-portfolio-item-stat pd-portfolio-item-action', type: 'button' });
        if (item.is_liked) likesStat.classList.add('active');
        likesStat.appendChild(_createSVG('<path d="M20.84 4.61a5.5 5.5 0 00-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 00-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 000-7.78z"/>', 12));
        likesStat.appendChild(UI.el('span', { textContent: String(_safeInt(item.likes_count)) }));
        likesStat.dataset.stat = 'likes';
        likesStat.setAttribute('aria-label', 'إعجاب');
        likesStat.addEventListener('click', (event) => {
          event.preventDefault();
          event.stopPropagation();
          _togglePortfolioLike(item, likesStat);
        });
        stats.appendChild(likesStat);

        const savesStat = UI.el('button', { className: 'pd-portfolio-item-stat pd-portfolio-item-action', type: 'button' });
        if (item.is_saved) savesStat.classList.add('active');
        savesStat.appendChild(_createSVG('<path d="M19 21l-7-5-7 5V5a2 2 0 012-2h10a2 2 0 012 2z"/>', 12));
        savesStat.appendChild(UI.el('span', { textContent: String(_safeInt(item.saves_count)) }));
        savesStat.dataset.stat = 'saves';
        savesStat.setAttribute('aria-label', 'حفظ في المفضلة');
        savesStat.addEventListener('click', (event) => {
          event.preventDefault();
          event.stopPropagation();
          _togglePortfolioSave(item, savesStat);
        });
        stats.appendChild(savesStat);

        frame.appendChild(stats);
        el.appendChild(frame);
        el.addEventListener('click', () => {
          if (typeof SpotlightViewer !== 'undefined') {
            SpotlightViewer.open(items, index, {
              source: 'portfolio',
              label: 'معرض',
              eventName: 'nw:portfolio-engagement-update',
              immersive: true,
              modeContext: _mode || 'client',
            });
          }
        });
        el.addEventListener('keydown', (event) => {
          if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            el.click();
          }
        });
        grid.appendChild(el);
      });

      section.appendChild(grid);
      container.appendChild(section);
    });

    if (!container.children.length && emptyEl) {
      emptyEl.classList.remove('hidden');
    }
    _setTabLoadingState('portfolio', false);
    _setupPortfolioPreviewObserver();
    _syncPortfolioPreviewPlayback();
  }

  function _buildPortfolioPreviewVideo(item, fallbackUrl, label) {
    const video = document.createElement('video');
    video.className = 'pd-portfolio-preview-video';
    video.muted = true;
    video.defaultMuted = true;
    video.loop = true;
    video.playsInline = true;
    video.preload = 'metadata';
    video.setAttribute('muted', 'muted');
    video.setAttribute('playsinline', 'playsinline');
    video.setAttribute('webkit-playsinline', 'webkit-playsinline');
    video.setAttribute('aria-label', label || item.media_label || 'فيديو من المعرض');
    video.dataset.previewVideo = 'true';
    video.dataset.inview = '0';

    const sourceUrl = ApiClient.mediaUrl(item.file_url || item.media || fallbackUrl);
    if (sourceUrl) video.src = sourceUrl;
    const posterUrl = ApiClient.mediaUrl(item.thumbnail || item.thumbnail_url || fallbackUrl || item.media);
    if (posterUrl) video.poster = posterUrl;

    video.addEventListener('error', () => {
      const replacement = UI.lazyImg(posterUrl || fallbackUrl || item.media, label || item.media_label || '');
      replacement.className = 'pd-portfolio-preview-fallback';
      if (video.parentNode) video.parentNode.replaceChild(replacement, video);
    }, { once: true });

    return video;
  }

  function _resetPortfolioPreviewObserver() {
    if (_portfolioPreviewObserver) {
      _portfolioPreviewObserver.disconnect();
      _portfolioPreviewObserver = null;
    }
  }

  function _setupPortfolioPreviewObserver() {
    _resetPortfolioPreviewObserver();
    if (typeof window === 'undefined' || typeof document === 'undefined') return;
    const videos = Array.from(document.querySelectorAll('.pd-portfolio-preview-video'));
    if (!videos.length) return;

    if (typeof window.IntersectionObserver !== 'function') {
      videos.forEach((video, index) => {
        video.dataset.inview = index === 0 ? '1' : '0';
      });
      return;
    }

    _portfolioPreviewObserver = new window.IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        const video = entry.target;
        video.dataset.inview = entry.isIntersecting && entry.intersectionRatio >= 0.65 ? '1' : '0';
      });
      _syncPortfolioPreviewPlayback();
    }, {
      threshold: [0.35, 0.65, 0.85],
    });

    videos.forEach((video) => _portfolioPreviewObserver.observe(video));
  }

  function _syncPortfolioPreviewPlayback() {
    if (typeof document === 'undefined') return;
    const shouldPlay = _activeTab === 'portfolio';
    document.querySelectorAll('.pd-portfolio-preview-video').forEach((video) => {
      const isVisible = video.dataset.inview === '1';
      if (shouldPlay && isVisible) {
        const playAttempt = video.play();
        if (playAttempt && typeof playAttempt.catch === 'function') {
          playAttempt.catch(() => {});
        }
        return;
      }
      try {
        video.pause();
      } catch (_) {
        // no-op
      }
    });
  }

  function _updatePortfolioHeroMetrics(totalItems, totalSections) {
    const totalEl = document.getElementById('pd-portfolio-total');
    const sectionsEl = document.getElementById('pd-portfolio-sections-total');
    if (totalEl) totalEl.textContent = String(_safeInt(totalItems)) + ' عنصر';
    if (sectionsEl) sectionsEl.textContent = String(_safeInt(totalSections)) + ' قسم';
    _setTabMeta('portfolio', _formatTabCount(totalItems));
  }

  function _syncPortfolioEngagementTotals() {
    _portfolioLikes = _portfolioItems.reduce((sum, item) => sum + _safeInt(item.likes_count), 0);
    _portfolioSaves = _portfolioItems.reduce((sum, item) => sum + _safeInt(item.saves_count), 0);
    _portfolioSavedByMe = _portfolioItems.some((item) => !!item.is_saved);
  }

  function _updatePortfolioBadge(item) {
    const key = String(_safeInt(item?.id));
    if (!key) return;
    const root = document.querySelector('.pd-portfolio-item[data-item-id="' + key + '"]');
    if (!root) return;
    const likesEl = root.querySelector('.pd-portfolio-item-stat[data-stat="likes"]');
    const savesEl = root.querySelector('.pd-portfolio-item-stat[data-stat="saves"]');
    if (likesEl) {
      const likesCount = likesEl.querySelector('span');
      if (likesCount) likesCount.textContent = String(_safeInt(item.likes_count));
      likesEl.classList.toggle('active', _asBool(item.is_liked));
    }
    if (savesEl) {
      const savesCount = savesEl.querySelector('span');
      if (savesCount) savesCount.textContent = String(_safeInt(item.saves_count));
      savesEl.classList.toggle('active', _asBool(item.is_saved));
    }
  }

  async function _togglePortfolioLike(item, triggerBtn) {
    const outcome = await _togglePortfolioReaction(item, 'like', triggerBtn);
    if (outcome) _showToast(outcome);
  }

  async function _togglePortfolioSave(item, triggerBtn) {
    const outcome = await _togglePortfolioReaction(item, 'save', triggerBtn);
    if (outcome) _showToast(outcome);
  }

  async function _togglePortfolioReaction(item, action, triggerBtn) {
    if (!Auth.isLoggedIn()) {
      window.location.href = '/login/?next=' + encodeURIComponent(window.location.pathname + window.location.search);
      return '';
    }

    const isLike = action === 'like';
    const previousFlag = isLike ? !!item.is_liked : !!item.is_saved;
    const previousCount = _safeInt(isLike ? item.likes_count : item.saves_count);
    const nextFlag = !previousFlag;
    const nextCount = Math.max(0, previousCount + (nextFlag ? 1 : -1));

    if (isLike) {
      item.is_liked = nextFlag;
      item.likes_count = nextCount;
    } else {
      item.is_saved = nextFlag;
      item.saves_count = nextCount;
    }

    _syncPortfolioEngagementTotals();
    _updatePortfolioBadge(item);
    _recomputeEngagementView();
    _emitPortfolioEngagementUpdate(item);

    if (triggerBtn) triggerBtn.disabled = true;
    const endpoint = '/api/providers/portfolio/' + item.id + '/' + (nextFlag ? action : 'un' + action) + '/';
    const res = await ApiClient.request(_withMode(endpoint), { method: 'POST' });
    if (triggerBtn) triggerBtn.disabled = false;

    if (res.ok) {
      return isLike
        ? (nextFlag ? 'تم تسجيل الإعجاب بصفتك ' + _getModeLabel() : 'تم إلغاء الإعجاب بصفتك ' + _getModeLabel())
        : (nextFlag ? 'تم الحفظ في المفضلة بصفتك ' + _getModeLabel() : 'تمت إزالة العنصر من المفضلة بصفتك ' + _getModeLabel());
    }

    if (isLike) {
      item.is_liked = previousFlag;
      item.likes_count = previousCount;
    } else {
      item.is_saved = previousFlag;
      item.saves_count = previousCount;
    }
    _syncPortfolioEngagementTotals();
    _updatePortfolioBadge(item);
    _recomputeEngagementView();
    _emitPortfolioEngagementUpdate(item);

    if (res.status === 401) {
      window.location.href = '/login/?next=' + encodeURIComponent(window.location.pathname + window.location.search);
      return '';
    }
    return isLike ? 'تعذر تحديث الإعجاب' : 'تعذر تحديث الحفظ';
  }

  function _emitPortfolioEngagementUpdate(item) {
    if (!item || typeof window === 'undefined') return;
    window.dispatchEvent(new CustomEvent('nw:portfolio-engagement-update', {
      detail: {
        id: item.id,
        provider_id: item.provider_id,
        likes_count: Number(item.likes_count) || 0,
        saves_count: Number(item.saves_count) || 0,
        is_liked: !!item.is_liked,
        is_saved: !!item.is_saved,
      },
    }));
  }

  function _recomputeEngagementView() {
    const totalLikes = _mediaLikesTotal !== null
      ? _safeInt(_mediaLikesTotal)
      : (_safeInt(_profileLikesBase) + _safeInt(_portfolioLikes) + _safeInt(_spotlightLikes));
    _setText('stat-likes', totalLikes);

    _isBookmarked = !!(_portfolioSavedByMe || _spotlightSavedByMe);
    const bookmarkBtn = document.getElementById('btn-bookmark');
    if (!bookmarkBtn) return;
    bookmarkBtn.classList.toggle('bookmarked', _isBookmarked);
    bookmarkBtn.setAttribute('aria-label', _isBookmarked ? 'فتح مفضلتي' : 'الانتقال إلى المعرض للحفظ');
    bookmarkBtn.title = _isBookmarked ? 'فتح مفضلتي' : 'احفظ من المعرض أو اللمحات';
    const svg = bookmarkBtn.querySelector('svg');
    if (svg) svg.setAttribute('fill', _isBookmarked ? '#fff' : 'none');
  }

  function _handleBookmarkAction() {
    if (!Auth.isLoggedIn()) {
      window.location.href = '/login/?next=' + encodeURIComponent(window.location.pathname + window.location.search);
      return;
    }

    if (_isBookmarked) {
      window.location.href = '/interactive/?tab=favorites';
      return;
    }

    _switchToTab('portfolio');
    const portfolioPanel = document.getElementById('tab-portfolio');
    if (portfolioPanel && typeof portfolioPanel.scrollIntoView === 'function') {
      portfolioPanel.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }
    _showToast('اضغط حفظ على أي صورة أو فيديو لإضافته إلى مفضلتك');
  }

  function _switchToTab(nextTab) {
    _setActiveTab(nextTab, { scrollIntoView: true });
  }

  /* ═══ Reviews ═══ */
  function _extractProviderReply(review) {
    return _pickFirstText(
      review && review.provider_reply,
      review && review.providerReply,
      review && review.provider_response,
      review && review.providerResponse,
      review && review.reply
    );
  }

  function _buildReviewCard(review) {
    const card = UI.el('article', { className: 'pd-review-card' });

    const header = UI.el('div', { className: 'pd-review-header' });
    header.appendChild(UI.el('span', {
      className: 'pd-review-author',
      textContent: review.reviewer_name || review.client_name || 'مستخدم',
    }));
    const stars = UI.el('span', { className: 'pd-review-stars' });
    const rating = Math.round(review.rating || 0);
    for (let i = 0; i < 5; i++) {
      stars.appendChild(UI.icon('star', 14, i < rating ? '#FFC107' : '#E0E0E0'));
    }
    header.appendChild(stars);
    card.appendChild(header);

    const reviewText = _pickFirstText(review.comment, review.text, review.review_text);
    if (reviewText) {
      card.appendChild(UI.el('div', { className: 'pd-review-text', textContent: reviewText }));
    }

    const providerReply = _extractProviderReply(review);
    if (providerReply) {
      const replyBox = UI.el('div', { className: 'pd-review-reply' });
      replyBox.appendChild(UI.el('div', {
        className: 'pd-review-reply-label',
        textContent: 'رد مقدم الخدمة',
      }));
      replyBox.appendChild(UI.el('div', {
        className: 'pd-review-reply-text',
        textContent: providerReply,
      }));
      card.appendChild(replyBox);
    }

    if (review.created_at || review.created) {
      const d = new Date(review.created_at || review.created);
      card.appendChild(UI.el('div', {
        className: 'pd-review-date',
        textContent: d.toLocaleDateString('ar-SA', { year: 'numeric', month: 'short', day: 'numeric' }),
      }));
    }

    return card;
  }

  async function _loadReviews() {
    const summaryEl = document.getElementById('pd-rating-summary');
    const listEl = document.getElementById('pd-reviews-list');
    const emptyEl = document.getElementById('pd-reviews-empty');
    _setTabLoadingState('reviews', true);
    let ratingCountForMeta = 0;

    const [ratingRes, reviewsRes] = await Promise.all([
      ApiClient.get('/api/reviews/providers/' + _providerId + '/rating/'),
      ApiClient.get('/api/reviews/providers/' + _providerId + '/reviews/')
    ]);

    // Rating summary
    if (ratingRes.ok && ratingRes.data && summaryEl) {
      const r = ratingRes.data;
      const ratingCount = _safeInt(r.rating_count || r.count || 0);
      ratingCountForMeta = ratingCount;
      const ratingAvgRaw = r.rating_avg !== undefined && r.rating_avg !== null ? r.rating_avg : r.average;
      const ratingAvg = Number.parseFloat(ratingAvgRaw);
      const distribution = r.distribution || {};
      summaryEl.textContent = '';
      const bigDiv = UI.el('div', { className: 'pd-rating-big' });
      bigDiv.appendChild(UI.text(ratingCount > 0 && Number.isFinite(ratingAvg) ? ratingAvg.toFixed(1) : '-'));
      bigDiv.appendChild(UI.icon('star', 24, '#FFC107'));
      summaryEl.appendChild(bigDiv);
      summaryEl.appendChild(UI.el('div', { className: 'pd-rating-count', textContent: ratingCount + ' تقييم' }));

      // Rating bars
      if (distribution) {
        const bars = UI.el('div', { className: 'pd-rating-bars' });
        for (let i = 5; i >= 1; i--) {
          const count = distribution[i] || distribution[String(i)] || 0;
          const total = ratingCount || 1;
          const pct = Math.round((count / total) * 100);
          const row = UI.el('div', { className: 'pd-rating-bar-row' });
          row.appendChild(UI.el('span', { className: 'pd-rating-bar-label', textContent: i }));
          row.appendChild(UI.icon('star', 12, '#FFC107'));
          const bar = UI.el('div', { className: 'pd-rating-bar' });
          const fill = UI.el('div', { className: 'pd-rating-bar-fill' });
          fill.style.width = pct + '%';
          bar.appendChild(fill);
          row.appendChild(bar);
          bars.appendChild(row);
        }
        summaryEl.appendChild(bars);
      }
    }

    // Reviews list
    let reviews = [];
    if (reviewsRes.ok && reviewsRes.data) {
      reviews = Array.isArray(reviewsRes.data) ? reviewsRes.data : (reviewsRes.data.results || []);
    }

    if (!ratingCountForMeta) {
      ratingCountForMeta = reviews.length;
    }
    _setTabMeta('reviews', _formatTabCount(ratingCountForMeta));

    if (listEl) listEl.textContent = '';

    if (!reviews.length) {
      _setTabLoadingState('reviews', false);
      if (emptyEl) emptyEl.classList.remove('hidden');
      return;
    }

    if (emptyEl) emptyEl.classList.add('hidden');
    if (!listEl) return;

    const marqueeReviews = reviews.slice();
    if (marqueeReviews.length <= 2) {
      const staticList = UI.el('div', { className: 'pd-reviews-static' });
      marqueeReviews.forEach((review) => {
        staticList.appendChild(_buildReviewCard(review));
      });
      listEl.appendChild(staticList);
      _setTabLoadingState('reviews', false);
      return;
    }

    const marquee = UI.el('div', { className: 'pd-reviews-marquee' });
    const track = UI.el('div', { className: 'pd-reviews-track' });
    const groupA = UI.el('div', { className: 'pd-reviews-track-group' });

    marqueeReviews.forEach((review) => {
      groupA.appendChild(_buildReviewCard(review));
    });
    const groupB = groupA.cloneNode(true);

    track.style.setProperty('--pd-reviews-duration', Math.max(18, marqueeReviews.length * 6) + 's');
    track.appendChild(groupA);
    track.appendChild(groupB);
    marquee.appendChild(track);
    listEl.appendChild(marquee);
    _setTabLoadingState('reviews', false);
  }

  /* ═══ Helpers ═══ */

  function _safeInt(value) {
    const n = parseInt(value, 10);
    return Number.isFinite(n) ? n : 0;
  }

  function _safeNullableInt(value) {
    if (value === null || value === undefined || value === '') return null;
    const n = parseInt(value, 10);
    return Number.isFinite(n) ? n : null;
  }

  function _asBool(value) {
    if (typeof value === 'boolean') return value;
    if (typeof value === 'number') return value !== 0;
    const text = String(value || '').trim().toLowerCase();
    if (!text) return false;
    if (text === 'true' || text === '1' || text === 'yes' || text === 'y' || text === 'on') return true;
    if (text === 'false' || text === '0' || text === 'no' || text === 'n' || text === 'off') return false;
    return false;
  }

  function _trimText(value) {
    return String(value || '').trim();
  }

  function _normalizeSeoSlug(value) {
    return _trimText(value)
      .toLowerCase()
      .replace(/[^\u0600-\u06ff0-9a-z]+/gi, '-')
      .replace(/^-+|-+$/g, '');
  }

  function _providerCanonicalPath(provider) {
    const providerId = _safeInt(provider && provider.id ? provider.id : _providerId);
    if (!providerId) return '';
    const seoSlug = _normalizeSeoSlug(provider && provider.seo_slug);
    return seoSlug ? ('/provider/' + providerId + '/' + seoSlug + '/') : ('/provider/' + providerId + '/');
  }

  function _setMetaContent(id, value) {
    const node = document.getElementById(id);
    if (!node) return;
    node.setAttribute('content', _trimText(value));
  }

  function _setCanonicalUrl(url) {
    if (!url) return;
    const node = document.getElementById('page-canonical');
    if (node) node.setAttribute('href', url);
  }

  function _applySeoMeta(provider, displayName) {
    const seoTitle = _pickFirstText(provider && provider.seo_title, displayName, 'مقدم خدمة');
    const pageTitle = seoTitle ? (seoTitle + ' | نوافــذ') : 'نوافــذ | مقدم خدمة';
    const description = _pickFirstText(
      provider && provider.seo_meta_description,
      provider && provider.bio,
      provider && provider.about_details,
      displayName ? ('تعرف على خدمات ' + displayName + ' عبر منصة نوافــذ.') : 'منصة نوافــذ للخدمات الرقمية والمهنية.'
    );
    const canonicalPath = _providerCanonicalPath(provider);
    const canonicalUrl = canonicalPath ? (window.location.origin + canonicalPath) : window.location.href;
    const imageUrl = _pickFirstText(provider && provider.cover_image, provider && provider.profile_image);
    const absoluteImageUrl = imageUrl
      ? (/^https?:\/\//i.test(imageUrl) ? imageUrl : (window.location.origin + (imageUrl.startsWith('/') ? '' : '/') + imageUrl))
      : '';

    document.title = pageTitle;
    _setMetaContent('meta-description', description);
    _setMetaContent('meta-keywords', provider && provider.seo_keywords);
    _setMetaContent('meta-og-title', pageTitle);
    _setMetaContent('meta-og-description', description);
    _setMetaContent('meta-og-url', canonicalUrl);
    _setMetaContent('meta-og-image', absoluteImageUrl);
    _setMetaContent('meta-twitter-title', pageTitle);
    _setMetaContent('meta-twitter-description', description);
    _setMetaContent('meta-twitter-image', absoluteImageUrl);
    _setCanonicalUrl(canonicalUrl);

    if (canonicalPath) {
      const currentPath = window.location.pathname.endsWith('/') ? window.location.pathname : (window.location.pathname + '/');
      if (currentPath !== canonicalPath && window.history && typeof window.history.replaceState === 'function') {
        window.history.replaceState({}, '', canonicalPath + window.location.search + window.location.hash);
      }
    }
  }

  function _pickFirstText() {
    for (let i = 0; i < arguments.length; i += 1) {
      const text = _trimText(arguments[i]);
      if (text) return text;
    }
    return '';
  }

  function _resolveMode() {
    let accountModeRaw = '';
    try {
      accountModeRaw = sessionStorage.getItem('nw_account_mode') || '';
    } catch {}
    const byAccountMode = _trimText(accountModeRaw).toLowerCase();
    if (byAccountMode === 'provider') return 'provider';
    if (byAccountMode === 'client') return 'client';
    const roleState = (typeof Auth !== 'undefined' && Auth.getRoleState)
      ? _trimText(Auth.getRoleState()).toLowerCase()
      : '';
    return roleState.includes('provider') ? 'provider' : 'client';
  }

  function _withMode(path) {
    const sep = path.includes('?') ? '&' : '?';
    return path + sep + 'mode=' + encodeURIComponent(_mode || 'client');
  }

  function _formatCompactNumber(value) {
    if (!Number.isFinite(value)) return '';
    if (Math.abs(value - Math.round(value)) < 0.0001) {
      return String(Math.round(value));
    }
    return Number(value)
      .toFixed(2)
      .replace(/0+$/, '')
      .replace(/\.$/, '');
  }

  function _uniqueNonEmpty(values) {
    const seen = new Set();
    const result = [];
    values.forEach((value) => {
      const clean = _trimText(value);
      if (!clean || seen.has(clean)) return;
      seen.add(clean);
      result.push(clean);
    });
    return result;
  }

  function _joinForDisplay(values, maxItems) {
    const list = _uniqueNonEmpty(values || []);
    const limit = Number.isFinite(maxItems) && maxItems > 0 ? maxItems : 3;
    if (!list.length) return '';
    if (list.length <= limit) return list.join('، ');
    return list.slice(0, limit).join('، ') + ' (+' + String(list.length - limit) + ')';
  }

  function _normalizeComparableText(value) {
    return _trimText(String(value || '').replace(/\s+/g, ' ')).toLowerCase();
  }

  function _serviceCategoryFromService(service) {
    const subcategory = service && typeof service.subcategory === 'object' ? service.subcategory : null;
    return _pickFirstText(
      subcategory ? subcategory.category_name : '',
      subcategory ? subcategory.categoryName : '',
      service ? service.category_name : '',
      service ? service.main_category : '',
      service ? service.categoryName : '',
      service ? service.mainCategory : ''
    );
  }

  function _serviceSubCategoryFromService(service) {
    const subcategory = service && typeof service.subcategory === 'object' ? service.subcategory : null;
    return _pickFirstText(
      subcategory ? subcategory.name : '',
      subcategory ? subcategory.subcategory_name : '',
      subcategory ? subcategory.subCategoryName : '',
      service ? service.subcategory_name : '',
      service ? service.sub_category : '',
      service ? service.subCategoryName : '',
      service ? service.subCategory : ''
    );
  }

  function _providerMainCategory(provider) {
    return _pickFirstText(
      provider ? provider.primary_category_name : '',
      provider ? provider.primaryCategoryName : '',
      provider && Array.isArray(provider.main_categories) ? provider.main_categories.join('، ') : '',
      provider && Array.isArray(provider.mainCategories) ? provider.mainCategories.join('، ') : '',
      provider ? provider.category_name : '',
      provider ? provider.main_category : '',
      provider ? provider.categoryName : '',
      provider ? provider.mainCategory : ''
    );
  }

  function _providerSubCategory(provider) {
    const selectedSubcategories = provider && Array.isArray(provider.selected_subcategories)
      ? provider.selected_subcategories
      : (provider && Array.isArray(provider.selectedSubcategories) ? provider.selectedSubcategories : []);
    const selectedNames = selectedSubcategories.map((item) => _pickFirstText(
      item && item.name,
      item && item.subcategory_name,
      item && item.subCategoryName
    ));
    return _pickFirstText(
      provider ? provider.primary_subcategory_name : '',
      provider ? provider.primarySubcategoryName : '',
      _joinForDisplay(selectedNames, 20),
      provider ? provider.subcategory_name : '',
      provider ? provider.sub_category : '',
      provider ? provider.subcategoryName : '',
      provider ? provider.subCategoryName : '',
      provider ? provider.subCategory : ''
    );
  }

  function _resolveMainCategory(provider) {
    return _providerMainCategory(provider) || _derivedMainCategory;
  }

  function _resolveSubCategory(provider) {
    return _providerSubCategory(provider) || _derivedSubCategory;
  }

  function _updateIdentityCategoryLine(mainCategory, subCategory) {
    const lineEl = document.getElementById('pd-category-line');
    if (!lineEl) return;
    const main = _trimText(mainCategory);
    const sub = _trimText(subCategory);
    if (!main) {
      lineEl.textContent = '';
      lineEl.classList.add('hidden');
      return;
    }
    lineEl.textContent = sub ? (main + ' • ' + sub) : main;
    lineEl.classList.remove('hidden');
  }

  function _syncCategoryViews() {
    if (!_providerData) return;
    const mainCategory = _resolveMainCategory(_providerData);
    const subCategory = _resolveSubCategory(_providerData);
    _updateIdentityCategoryLine(mainCategory, subCategory);
    _setText('pd-main-category', _displayOrUnavailable(mainCategory, 'غير متوفر'));
    _setText('pd-sub-category', _displayOrUnavailable(subCategory, 'غير متوفر'));
  }

  function _refreshDerivedCategories(services) {
    const list = Array.isArray(services) ? services : [];
    const categories = list.map((service) => _serviceCategoryFromService(service));
    const subcategories = list.map((service) => _serviceSubCategoryFromService(service));
    _derivedMainCategory = _joinForDisplay(categories, 3);
    _derivedSubCategory = _joinForDisplay(subcategories, 3);
  }

  function _setText(id, val) {
    const el = document.getElementById(id);
    if (el) el.textContent = val;
  }

  function _addContactRow(container, iconHtml, text, href) {
    const row = UI.el(href ? 'a' : 'div', { className: 'pd-contact-row' });
    if (href) { row.href = href.startsWith('http') ? href : ('https://' + href); row.target = '_blank'; row.rel = 'noopener'; }
    const iconWrap = UI.el('span', {});
    iconWrap.innerHTML = iconHtml; // safe: from our own _svgIcon
    row.appendChild(iconWrap);
    row.appendChild(UI.el('span', { textContent: text }));
    container.appendChild(row);
  }

  function _addSocialRow(container, iconHtml, label, url) {
    const row = UI.el('div', { className: 'pd-social-row' });
    const iconWrap = UI.el('div', { className: 'pd-social-icon' });
    iconWrap.innerHTML = iconHtml;
    row.appendChild(iconWrap);

    const info = UI.el('div', { className: 'pd-social-info' });
    info.appendChild(UI.el('div', { className: 'pd-social-label', textContent: label }));
    const handle = _extractHandle(url);
    info.appendChild(UI.el('div', { className: 'pd-social-value', textContent: handle || url }));
    row.appendChild(info);

    const link = UI.el('a', { className: 'pd-social-link', href: url.startsWith('http') ? url : ('https://' + url), target: '_blank', rel: 'noopener' });
    link.innerHTML = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 13v6a2 2 0 01-2 2H5a2 2 0 01-2-2V8a2 2 0 012-2h6"/><polyline points="15 3 21 3 21 9"/><line x1="10" y1="14" x2="21" y2="3"/></svg>';
    row.appendChild(link);
    container.appendChild(row);
  }

  function _extractHandle(url) {
    try {
      const uri = new URL(url.startsWith('http') ? url : ('https://' + url));
      const parts = uri.pathname.split('/').filter(Boolean);
      return parts.length ? '@' + parts[parts.length - 1] : '';
    } catch { return ''; }
  }

  function _displayOrUnavailable(value, unavailableText) {
    const text = String(value || '').trim();
    return text || unavailableText;
  }

  function _setSocialRow(kind, valueId, buttonId, unavailableText) {
    const url = String(_socialUrls[kind] || '').trim();
    const valueEl = document.getElementById(valueId);
    if (valueEl) {
      valueEl.textContent = url ? (_extractHandle(url) || url) : unavailableText;
    }
    const button = document.getElementById(buttonId);
    if (!button) return;
    button.disabled = !url;
    button.classList.toggle('disabled', !url);
    button.onclick = () => {
      if (!url) return;
      const href = url.startsWith('http') ? url : ('https://' + url);
      window.open(href, '_blank', 'noopener');
    };
  }

  function _findSocialUrl(provider, keyword) {
    const socialLinks = Array.isArray(provider.social_links) ? provider.social_links : [];
    const needle = String(keyword || '').trim().toLowerCase();
    if (!needle) return '';

    for (const item of socialLinks) {
      const url = (typeof item === 'string' ? item : (item?.url || '')).toString().trim();
      if (!url) continue;
      if (url.toLowerCase().includes(needle)) return url;
    }
    return '';
  }

  function _extractPortfolioSectionTitle(caption) {
    const text = String(caption || '').trim();
    if (!text) return 'أعمالي';
    const separators = [' - ', ' — ', ' – ', ' | ', '|'];
    for (const separator of separators) {
      const idx = text.indexOf(separator);
      if (idx > 0) return text.slice(0, idx).trim() || 'أعمالي';
    }
    return 'أعمالي';
  }

  function _extractPortfolioItemDescription(caption, sectionTitle) {
    const text = String(caption || '').trim();
    if (!text) return 'بدون وصف';
    const section = String(sectionTitle || '').trim();
    if (!section || section === 'أعمالي') return text;

    const separators = [' - ', ' — ', ' – ', ' | ', '|'];
    for (const separator of separators) {
      const prefix = section + separator;
      if (text.startsWith(prefix)) {
        const rest = text.slice(prefix.length).trim();
        if (rest) return rest;
      }
    }
    return text;
  }

  function _derivePortfolioMediaLabel(item, description, fileUrl) {
    const explicit = String(item?.title || item?.name || '').trim();
    if (explicit) return explicit;
    const desc = String(description || '').trim();
    if (desc && desc !== 'بدون وصف') return desc;
    const rawCaption = String(item?.caption || '').trim();
    if (rawCaption) return rawCaption;
    const fromPath = String(fileUrl || '').split('?')[0].split('/').pop() || '';
    if (fromPath) return decodeURIComponent(fromPath);
    return 'عنصر من المعرض';
  }

  function _deriveSpotlightMediaLabel(item, rawCaption) {
    const explicit = String(item?.title || item?.name || '').trim();
    if (explicit) return explicit;
    const caption = String(rawCaption || '').trim();
    if (caption) return caption;
    const fromPath = String(item?.file_url || item?.media_url || '').split('?')[0].split('/').pop() || '';
    if (fromPath) return decodeURIComponent(fromPath);
    return 'لمحة';
  }

  function _renderModeBadge() {
    const identity = document.querySelector('.pd-identity');
    if (!identity) return;

    let badge = document.getElementById('pd-mode-badge');
    if (!badge) {
      badge = UI.el('div', { className: 'pd-mode-badge', id: 'pd-mode-badge' });
      identity.appendChild(badge);
    }
    badge.textContent = 'وضع التفاعل الحالي: ' + _getModeLabel();
    badge.dataset.mode = _mode || 'client';
  }

  function _getModeLabel() {
    return String(_mode || 'client') === 'provider' ? 'مزود' : 'عميل';
  }

  function _resolveServiceRangeKm(provider) {
    const radiusRaw = Number(provider.coverage_radius_km);
    if (Number.isFinite(radiusRaw) && radiusRaw > 0) {
      return Math.round(radiusRaw);
    }
    return 5;
  }

  function _parseCoordinate(value) {
    if (value === null || value === undefined || value === '') return null;
    if (typeof value === 'number') return Number.isFinite(value) ? value : null;
    const normalized = String(value).trim().replace(',', '.');
    if (!normalized) return null;
    const parsed = Number.parseFloat(normalized);
    return Number.isFinite(parsed) ? parsed : null;
  }

  function _resolveServiceRangeCenter(provider) {
    const lat = _parseCoordinate(
      provider && (provider.lat ?? provider.latitude ?? provider.location_lat ?? provider.locationLat)
    );
    const lng = _parseCoordinate(
      provider && (provider.lng ?? provider.longitude ?? provider.location_lng ?? provider.locationLng)
    );
    return { lat, lng };
  }

  function _hasValidGeoPoint(lat, lng) {
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) return false;
    if (Math.abs(lat) > 90 || Math.abs(lng) > 180) return false;
    return Math.abs(lat) > 0.000001 || Math.abs(lng) > 0.000001;
  }

  function _serviceRangeSummaryText(city, rangeKm, hasMapPoint) {
    const cityText = _trimText(city);
    if (hasMapPoint) {
      if (cityText) return 'تغطية تصل إلى ' + rangeKm + ' كم حول ' + cityText + '.';
      return 'تغطية تصل إلى ' + rangeKm + ' كم حول موقع مقدم الخدمة.';
    }
    if (cityText) {
      return 'النطاق المحدد ' + rangeKm + ' كم داخل مدينة ' + cityText + ' دون نقطة خريطة دقيقة.';
    }
    return 'لا تتوفر إحداثيات دقيقة لعرض نطاق الخدمة على الخريطة حالياً.';
  }

  function _syncServiceRangeMapSize() {
    if (!_serviceRangeMap) return;
    setTimeout(() => {
      try {
        _serviceRangeMap.invalidateSize();
      } catch (_) {}
    }, 120);
  }

  function _renderServiceRangeMap(provider) {
    const mapEl = document.getElementById('pd-service-range-map');
    const emptyEl = document.getElementById('pd-service-range-map-empty');
    const summaryEl = document.getElementById('pd-service-range-summary');
    if (!mapEl) return;

    const rangeKm = _resolveServiceRangeKm(provider);
    const city = UI.formatCityDisplay(
      _pickFirstText(provider && (provider.city_display || provider.city)),
      _pickFirstText(provider && (provider.region || provider.region_name))
    );
    const center = _resolveServiceRangeCenter(provider);
    const hasPoint = _hasValidGeoPoint(center.lat, center.lng);

    if (summaryEl) {
      summaryEl.textContent = _serviceRangeSummaryText(city, rangeKm, hasPoint);
    }

    if (typeof L === 'undefined') {
      mapEl.classList.add('hidden');
      if (emptyEl) {
        emptyEl.textContent = 'تعذر تحميل الخريطة حالياً.';
        emptyEl.classList.remove('hidden');
      }
      return;
    }

    if (!hasPoint) {
      mapEl.classList.add('hidden');
      if (emptyEl) {
        emptyEl.textContent = 'لم يحدد مقدم الخدمة موقعًا دقيقًا على الخريطة بعد.';
        emptyEl.classList.remove('hidden');
      }
      if (_serviceRangeLayer) _serviceRangeLayer.clearLayers();
      return;
    }

    mapEl.classList.remove('hidden');
    if (emptyEl) emptyEl.classList.add('hidden');

    if (!_serviceRangeMap) {
      _serviceRangeMap = L.map(mapEl, {
        scrollWheelZoom: false,
      });
      L.tileLayer('https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png', {
        subdomains: 'abcd',
        maxZoom: 20,
        attribution: '&copy; OpenStreetMap &copy; CARTO',
      }).addTo(_serviceRangeMap);
    }

    if (!_serviceRangeMap._loaded) {
      _serviceRangeMap.setView([center.lat, center.lng], 12);
    }

    if (_serviceRangeLayer) {
      _serviceRangeLayer.clearLayers();
    } else {
      _serviceRangeLayer = L.layerGroup().addTo(_serviceRangeMap);
    }

    const radiusMeters = Math.max(1000, rangeKm * 1000);
    const circle = L.circle([center.lat, center.lng], {
      radius: radiusMeters,
      color: '#7C3AED',
      weight: 2,
      fillColor: '#8B5CF6',
      fillOpacity: 0.18,
    });
    const marker = L.circleMarker([center.lat, center.lng], {
      radius: 7,
      color: '#FFFFFF',
      weight: 2,
      fillColor: '#7C3AED',
      fillOpacity: 1,
    });

    _serviceRangeLayer.addLayer(circle);
    _serviceRangeLayer.addLayer(marker);

    const targetBounds = L.latLng(center.lat, center.lng).toBounds(radiusMeters * 2);
    if (targetBounds && targetBounds.isValid()) {
      _serviceRangeMap.fitBounds(targetBounds, { padding: [20, 20], maxZoom: 14 });
    } else {
      _serviceRangeMap.setView([center.lat, center.lng], 12);
    }

    _syncServiceRangeMapSize();
  }

  function _resolvePortfolioSections(grouped) {
    const rawSections = (_providerData && (_providerData.content_sections || _providerData.contentSections)) || [];
    const definedSections = Array.isArray(rawSections)
      ? rawSections.filter(section => section && typeof section === 'object')
      : [];

    if (definedSections.length) {
      const merged = new Map();
      return definedSections.map(section => {
        const title = String(section.section_title || section.title || section.name || 'أعمالي').trim() || 'أعمالي';
        const desc = String(section.section_desc || section.description || '').trim();
        if (merged.has(title)) {
          const current = merged.get(title);
          if (!current.sectionDesc && desc) current.sectionDesc = desc;
          return null;
        }
        const items = grouped.get(title) || [];
        const entry = { sectionTitle: title, sectionDesc: desc, items };
        merged.set(title, entry);
        return entry;
      }).filter(Boolean);
    }

    const results = [];
    grouped.forEach((items, title) => {
      results.push({
        sectionTitle: title,
        sectionDesc: '',
        items,
      });
    });
    return results;
  }

  function _detectPlatform(url) {
    const u = url.toLowerCase();
    if (u.includes('instagram')) return { label: 'انستقرام', icon: _svgIcon('instagram') };
    if (u.includes('x.com') || u.includes('twitter')) return { label: 'X (تويتر)', icon: _svgIcon('x') };
    if (u.includes('snapchat')) return { label: 'سناب شات', icon: _svgIcon('snapchat') };
    if (u.includes('tiktok')) return { label: 'تيك توك', icon: _svgIcon('web') };
    if (u.includes('facebook')) return { label: 'فيسبوك', icon: _svgIcon('web') };
    if (u.includes('youtube')) return { label: 'يوتيوب', icon: _svgIcon('web') };
    if (u.includes('linkedin')) return { label: 'لينكد إن', icon: _svgIcon('web') };
    return { label: 'رابط', icon: _svgIcon('web') };
  }

  function _svgIcon(name) {
    const icons = {
      location: '<svg width="16" height="16" viewBox="0 0 24 24" fill="#673AB7"><path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5z"/></svg>',
      phone: '<svg width="16" height="16" viewBox="0 0 24 24" fill="#673AB7"><path d="M6.62 10.79c1.44 2.83 3.76 5.14 6.59 6.59l2.2-2.2c.27-.27.67-.36 1.02-.24 1.12.37 2.32.57 3.57.57.55 0 1 .45 1 1V20c0 .55-.45 1-1 1-9.39 0-17-7.61-17-17 0-.55.45-1 1-1h3.5c.55 0 1 .45 1 1 0 1.25.2 2.45.57 3.57.11.35.03.74-.25 1.02l-2.2 2.2z"/></svg>',
      whatsapp: '<svg width="16" height="16" viewBox="0 0 24 24" fill="#25D366"><path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347z"/></svg>',
      web: '<svg width="16" height="16" viewBox="0 0 24 24" fill="#673AB7"><path d="M11.99 2C6.47 2 2 6.48 2 12s4.47 10 9.99 10C17.52 22 22 17.52 22 12S17.52 2 11.99 2zm6.93 6h-2.95a15.65 15.65 0 00-1.38-3.56A8.03 8.03 0 0118.92 8zM12 4.04c.83 1.2 1.48 2.53 1.91 3.96h-3.82c.43-1.43 1.08-2.76 1.91-3.96zM4.26 14C4.1 13.36 4 12.69 4 12s.1-1.36.26-2h3.38c-.08.66-.14 1.32-.14 2 0 .68.06 1.34.14 2H4.26zm.82 2h2.95c.32 1.25.78 2.45 1.38 3.56A7.987 7.987 0 015.08 16zm2.95-8H5.08a7.987 7.987 0 014.33-3.56A15.65 15.65 0 008.03 8zM12 19.96c-.83-1.2-1.48-2.53-1.91-3.96h3.82c-.43 1.43-1.08 2.76-1.91 3.96zM14.34 14H9.66c-.09-.66-.16-1.32-.16-2 0-.68.07-1.35.16-2h4.68c.09.65.16 1.32.16 2 0 .68-.07 1.34-.16 2zm.25 5.56c.6-1.11 1.06-2.31 1.38-3.56h2.95a8.03 8.03 0 01-4.33 3.56zM16.36 14c.08-.66.14-1.32.14-2 0-.68-.06-1.34-.14-2h3.38c.16.64.26 1.31.26 2s-.1 1.36-.26 2h-3.38z"/></svg>',
      instagram: '<svg width="16" height="16" viewBox="0 0 24 24" fill="#E1306C"><rect x="2" y="2" width="20" height="20" rx="5" fill="none" stroke="#E1306C" stroke-width="2"/><circle cx="12" cy="12" r="5" fill="none" stroke="#E1306C" stroke-width="2"/><circle cx="17.5" cy="6.5" r="1.5" fill="#E1306C"/></svg>',
      x: '<svg width="16" height="16" viewBox="0 0 24 24" fill="#000"><path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z"/></svg>',
      snapchat: '<svg width="16" height="16" viewBox="0 0 24 24" fill="#FFFC00"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2z"/></svg>',
    };
    return icons[name] || icons.web;
  }

  function _createSVG(paths, size) {
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('width', size || 16);
    svg.setAttribute('height', size || 16);
    svg.setAttribute('viewBox', '0 0 24 24');
    svg.setAttribute('fill', 'none');
    svg.setAttribute('stroke', 'currentColor');
    svg.setAttribute('stroke-width', '2');
    svg.innerHTML = paths;
    return svg;
  }

  function _formatPhoneE164(phone) {
    const raw = String(phone || '').trim();
    if (!raw) return '';
    const cleaned = raw.replace(/\s+/g, '');
    if (cleaned.startsWith('+')) {
      const plusDigits = cleaned.slice(1).replace(/\D+/g, '');
      return plusDigits ? ('+' + plusDigits) : '';
    }

    const digits = cleaned.replace(/\D+/g, '');
    if (!digits) return '';
    if (digits.startsWith('05') && digits.length === 10) return '+966' + digits.substring(1);
    if (digits.startsWith('5') && digits.length === 9) return '+966' + digits;
    if (digits.startsWith('9665') && digits.length === 12) return '+' + digits;
    if (digits.startsWith('009665') && digits.length === 14) return '+' + digits.substring(2);
    return cleaned;
  }

  function _normalizeWhatsappBaseUrl(raw) {
    const text = String(raw || '').trim();
    if (!text) return '';
    if (/^[\d+\s()-]+$/.test(text)) {
      const phone = _formatPhoneE164(text).replace('+', '');
      return phone ? ('https://wa.me/' + phone) : '';
    }
    let candidate = text;
    if (candidate.startsWith('wa.me/')) candidate = 'https://' + candidate;
    if (!/^https?:\/\//i.test(candidate)) candidate = 'https://' + candidate;
    try {
      const parsed = new URL(candidate);
      const host = parsed.hostname.toLowerCase();
      if (host === 'wa.me' || host.endsWith('.wa.me')) {
        const pathDigits = parsed.pathname.replace(/\D+/g, '');
        const phone = _formatPhoneE164(pathDigits).replace('+', '');
        return phone ? ('https://wa.me/' + phone) : '';
      }
      const phoneQuery = parsed.searchParams.get('phone');
      const phone = _formatPhoneE164(phoneQuery).replace('+', '');
      return phone ? ('https://wa.me/' + phone) : '';
    } catch (_) {
      const phone = _formatPhoneE164(text).replace('+', '');
      return phone ? ('https://wa.me/' + phone) : '';
    }
  }

  function _buildWhatsappChatUrl(rawUrl, fallbackPhone, message) {
    const base = _normalizeWhatsappBaseUrl(rawUrl) || _normalizeWhatsappBaseUrl(fallbackPhone);
    if (!base) return '';
    try {
      const url = new URL(base);
      url.searchParams.set('text', String(message || '').trim());
      return url.toString();
    } catch (_) {
      return base;
    }
  }

  function _ensureExcellenceMount() {
    let mount = document.getElementById('pd-excellence-badges');
    if (mount) return mount;

    const handle = document.getElementById('pd-handle');
    const categoryLine = document.getElementById('pd-category-line');
    if (!handle || !handle.parentNode) return null;

    mount = document.createElement('div');
    mount.id = 'pd-excellence-badges';
    mount.className = 'pd-excellence-badges hidden';
    if (categoryLine && categoryLine.parentNode === handle.parentNode) {
      handle.parentNode.insertBefore(mount, categoryLine);
    } else {
      handle.insertAdjacentElement('afterend', mount);
    }
    return mount;
  }

  function _showToast(msg) {
    const toast = UI.el('div', {
      textContent: msg,
      style: {
        position: 'fixed', bottom: '24px', left: '50%', transform: 'translateX(-50%)',
        background: '#333', color: '#fff', padding: '10px 24px',
        borderRadius: '12px', fontSize: '13px', fontWeight: '600',
        zIndex: '9999', fontFamily: 'Cairo, sans-serif',
        boxShadow: '0 4px 20px rgba(0,0,0,0.2)'
      }
    });
    document.body.appendChild(toast);
    setTimeout(() => toast.remove(), 2500);
  }

  // Boot
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else { init(); }

  return {};
})();
