/* ===================================================================
   spotlightViewer.js — TikTok-style fullscreen spotlight viewer
   Mirrors Flutter SpotlightViewerPage: vertical swipe, side actions,
   provider info, like/save, close button.
   =================================================================== */
'use strict';

const SpotlightViewer = (() => {

  let _overlay = null;
  let _items = [];
  let _currentIndex = 0;
  let _options = {};
  let _touchStartX = 0;
  let _touchStartY = 0;
  let _touchStartTs = 0;
  let _swiping = false;
  let _currentVideo = null;
  let _navDirection = 0;
  let _speedHoldTimer = null;
  let _speedBoostActive = false;
  let _skipNextPlaybackToggle = false;
  let _baseItemsCount = 0;
  let _maxSequenceItems = 0;
  let _randomFeedEnabled = false;
  let _randomFeedBatchSize = 0;
  let _randomFeedEndpoint = '';
  let _randomFeedPromise = null;
  let _navInFlight = false;
  let _optionsMenu = null;
  let _dialogSheet = null;
  let _shareSheet = null;
  let _commentsSheet = null;
  let _shareSearchTimer = null;
  let _shareSearchToken = 0;
  let _shareSendInFlight = false;
  let _reportSubmitInFlight = false;
  let _commentSubmitInFlight = false;
  let _commentsFetchToken = 0;
  let _commentReplyTarget = null;
  let _commentActionsMenu = null;
  let _seenItemKeys = new Set();
  const _preloadedVideoPool = new Map();

  /* ----------------------------------------------------------
     PUBLIC: open viewer
  ---------------------------------------------------------- */
  function open(items, startIndex, options) {
    if (!items || !items.length) return;
    _options = options || {};
    _items = Array.isArray(items) ? items.slice() : [];
    _baseItemsCount = _items.length;
    _maxSequenceItems = Math.max(
      _baseItemsCount,
      Math.min(100, Math.max(1, Number(_options.maxSessionItems) || _baseItemsCount))
    );
    _randomFeedEnabled = !!(_options.randomizeAfterEnd && String(_options.source || 'spotlight') === 'spotlight');
    _randomFeedBatchSize = Math.max(1, Math.min(50, Number(_options.randomBatchSize) || 20));
    _randomFeedEndpoint = String(_options.randomFeedEndpoint || '/api/providers/spotlights/feed/');
    _randomFeedPromise = null;
    _navInFlight = false;
    _seenItemKeys = new Set(_items.map(_itemKey).filter(Boolean));
    _currentIndex = Math.max(0, Math.min(startIndex || 0, _items.length - 1));
    _buildOverlay();
    _renderCurrent();
    document.body.style.overflow = 'hidden';
    if (_currentVideo) {
      const playAttempt = _currentVideo.play();
      if (playAttempt && typeof playAttempt.catch === 'function') playAttempt.catch(() => {});
    }
  }

  /* ----------------------------------------------------------
     PUBLIC: close viewer
  ---------------------------------------------------------- */
  function close() {
    _closeTransientPanels();
    _cancelSpeedHold({ restoreRate: true });
    if (_currentVideo) {
      try {
        _currentVideo.pause();
        _currentVideo.removeAttribute('src');
        _currentVideo.load();
      } catch (_) {
        // no-op
      }
      _currentVideo = null;
    }
    if (_overlay) {
      _overlay.remove();
      _overlay = null;
    }
    document.removeEventListener('keydown', _onKeyDown);
    document.body.style.overflow = '';
    _releasePreloadedVideos();
    _items = [];
    _currentIndex = 0;
    _options = {};
    _navDirection = 0;
    _baseItemsCount = 0;
    _maxSequenceItems = 0;
    _randomFeedEnabled = false;
    _randomFeedBatchSize = 0;
    _randomFeedEndpoint = '';
    _randomFeedPromise = null;
    _navInFlight = false;
    _shareSearchToken = 0;
    _shareSendInFlight = false;
    _reportSubmitInFlight = false;
    _commentSubmitInFlight = false;
    _commentReplyTarget = null;
    _commentActionsMenu = null;
    _seenItemKeys = new Set();
  }

  function _isTikTokMode() {
    return !!(_options && _options.tiktokMode);
  }

  function _wrapIndex(index) {
    const count = _items.length;
    if (!count) return 0;
    return ((index % count) + count) % count;
  }

  function _itemKey(item) {
    if (!item || typeof item !== 'object') return '';
    if (item.id !== undefined && item.id !== null && String(item.id).trim()) {
      return 'id:' + String(item.id).trim();
    }
    return [
      String(item.provider_id || ''),
      String(item.file_url || ''),
      String(item.thumbnail_url || ''),
    ].join('|');
  }

  function _canAppendRandomSpotlights() {
    return _randomFeedEnabled && _items.length < _maxSequenceItems;
  }

  async function _appendRandomSpotlights() {
    if (!_canAppendRandomSpotlights()) return false;
    if (_randomFeedPromise) return _randomFeedPromise;

    _randomFeedPromise = (async () => {
      const remaining = _maxSequenceItems - _items.length;
      if (remaining <= 0) return false;

      const query = new URLSearchParams({
        limit: String(Math.min(_randomFeedBatchSize, remaining)),
        random: '1',
        _: String(Date.now()),
      });
      const excludeIds = _items
        .map((item) => {
          const rawId = Number(item && item.id);
          return Number.isFinite(rawId) && rawId > 0 ? String(rawId) : '';
        })
        .filter(Boolean);
      if (excludeIds.length) {
        query.set('exclude_ids', excludeIds.join(','));
      }

      const separator = _randomFeedEndpoint.indexOf('?') === -1 ? '?' : '&';
      const res = await ApiClient.get(_randomFeedEndpoint + separator + query.toString());
      if (!res || !res.ok || !res.data) return false;

      const rows = Array.isArray(res.data) ? res.data : (res.data.results || []);
      const appended = [];
      rows.forEach((item) => {
        if (_items.length + appended.length >= _maxSequenceItems) return;
        const key = _itemKey(item);
        if (!key || _seenItemKeys.has(key)) return;
        _seenItemKeys.add(key);
        appended.push(item);
      });

      if (!appended.length) return false;
      _items = _items.concat(appended);
      return true;
    })();

    try {
      return await _randomFeedPromise;
    } finally {
      _randomFeedPromise = null;
    }
  }

  /* ----------------------------------------------------------
     BUILD: Overlay shell
  ---------------------------------------------------------- */
  function _buildOverlay() {
    if (_overlay) _overlay.remove();

    _overlay = document.createElement('div');
    _overlay.className = 'sv-overlay';
    if (_options && _options.immersive) _overlay.classList.add('sv-immersive');
    if (_isTikTokMode()) _overlay.classList.add('sv-tiktok');
    _overlay.setAttribute('role', 'dialog');
    _overlay.setAttribute('aria-label', 'عارض اللمحات');

    // Close button (top-left for RTL)
    const closeBtn = document.createElement('button');
    closeBtn.className = 'sv-close';
    closeBtn.setAttribute('aria-label', 'إغلاق');
    closeBtn.innerHTML = '<svg width="22" height="22" viewBox="0 0 24 24" fill="white"><path d="M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z"/></svg>';
    closeBtn.addEventListener('click', close);

    const menuBtn = document.createElement('button');
    menuBtn.className = 'sv-menu-btn';
    menuBtn.setAttribute('type', 'button');
    menuBtn.setAttribute('aria-label', _shareCopy('optionsAction'));
    menuBtn.innerHTML = '<svg width="22" height="22" viewBox="0 0 24 24" fill="none"><circle cx="12" cy="5" r="2" fill="white"/><circle cx="12" cy="12" r="2" fill="white"/><circle cx="12" cy="19" r="2" fill="white"/></svg>';
    menuBtn.addEventListener('click', (event) => {
      event.stopPropagation();
      _toggleOptionsMenu();
    });

    // Counter
    const counter = document.createElement('div');
    counter.className = 'sv-counter';
    counter.id = 'sv-counter';

    const prevBtn = document.createElement('button');
    prevBtn.className = 'sv-nav sv-nav-prev';
    prevBtn.id = 'sv-nav-prev';
    prevBtn.setAttribute('type', 'button');
    prevBtn.setAttribute('aria-label', 'العنصر السابق');
    prevBtn.innerHTML = '<svg width="24" height="24" viewBox="0 0 24 24" fill="none"><path d="M15 6L9 12L15 18" stroke="white" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>';
    prevBtn.addEventListener('click', () => _goPrev());

    const nextBtn = document.createElement('button');
    nextBtn.className = 'sv-nav sv-nav-next';
    nextBtn.id = 'sv-nav-next';
    nextBtn.setAttribute('type', 'button');
    nextBtn.setAttribute('aria-label', 'العنصر التالي');
    nextBtn.innerHTML = '<svg width="24" height="24" viewBox="0 0 24 24" fill="none"><path d="M9 6L15 12L9 18" stroke="white" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>';
    nextBtn.addEventListener('click', () => _goNext());

    // Media container
    const media = document.createElement('div');
    media.className = 'sv-media';
    media.id = 'sv-media';

    // Bottom info
    const bottom = document.createElement('div');
    bottom.className = 'sv-bottom';
    bottom.id = 'sv-bottom';

    // Side actions
    const side = document.createElement('div');
    side.className = 'sv-side';
    side.id = 'sv-side';

    const speedPill = document.createElement('div');
    speedPill.className = 'sv-speed-pill';
    speedPill.id = 'sv-speed-pill';
    speedPill.hidden = true;
    speedPill.textContent = '2x';

    _overlay.appendChild(menuBtn);
    _overlay.appendChild(closeBtn);
    _overlay.appendChild(counter);
    _overlay.appendChild(prevBtn);
    _overlay.appendChild(nextBtn);
    _overlay.appendChild(media);
    _overlay.appendChild(bottom);
    _overlay.appendChild(side);
    _overlay.appendChild(speedPill);

    // Event listeners
    _overlay.addEventListener('touchstart', _onTouchStart, { passive: true });
    _overlay.addEventListener('touchmove', _onTouchMove, { passive: true });
    _overlay.addEventListener('touchend', _onTouchEnd, { passive: true });
    _overlay.addEventListener('wheel', _onWheel, { passive: false });
    document.addEventListener('keydown', _onKeyDown);

    document.body.appendChild(_overlay);
  }

  /* ----------------------------------------------------------
     RENDER: Current item
  ---------------------------------------------------------- */
  function _renderCurrent() {
    if (!_overlay) return;
    const item = _items[_currentIndex];
    if (!item) return;
    _closeTransientPanels();

    if (_currentVideo) {
      try {
        _currentVideo.pause();
      } catch (_) {
        // no-op
      }
      _currentVideo = null;
    }

    // Counter
    const counter = document.getElementById('sv-counter');
    if (counter) {
      counter.textContent = (_currentIndex + 1) + ' / ' + _items.length;
      counter.hidden = _isTikTokMode() || _items.length <= 1;
    }

    const prevBtn = document.getElementById('sv-nav-prev');
    if (prevBtn) {
      prevBtn.disabled = _items.length <= 1;
      prevBtn.hidden = _items.length <= 1 || _isTikTokMode();
    }
    const nextBtn = document.getElementById('sv-nav-next');
    if (nextBtn) {
      nextBtn.disabled = _items.length <= 1;
      nextBtn.hidden = _items.length <= 1 || _isTikTokMode();
    }

    // Media
    const mediaEl = document.getElementById('sv-media');
    if (mediaEl) {
      mediaEl.innerHTML = '';
      mediaEl.classList.remove('is-video', 'is-image');
      const isVideo = _isVideo(item);
      const posterUrl = _resolveUrl(item.thumbnail_url || item.file_url);

      const backdrop = document.createElement('div');
      backdrop.className = 'sv-media-backdrop';
      backdrop.classList.add(isVideo ? 'is-video' : 'is-image');
      if (posterUrl) backdrop.style.backgroundImage = 'url("' + posterUrl.replace(/"/g, '\\"') + '")';
      mediaEl.appendChild(backdrop);

      const frame = document.createElement('div');
      frame.className = 'sv-media-frame';
      frame.classList.add(isVideo ? 'is-video' : 'is-image');
      if (_isTikTokMode()) frame.classList.add('sv-feed-frame');
      if (_navDirection > 0) frame.classList.add('sv-enter-next');
      else if (_navDirection < 0) frame.classList.add('sv-enter-prev');
      else frame.classList.add('sv-enter-fade');
      mediaEl.appendChild(frame);

      if (_navDirection > 0) backdrop.classList.add('sv-enter-next');
      else if (_navDirection < 0) backdrop.classList.add('sv-enter-prev');
      else backdrop.classList.add('sv-enter-fade');

      if (isVideo) {
        mediaEl.classList.add('is-video');
        const video = document.createElement('video');
        video.className = 'sv-video';
        video.autoplay = true;
        video.loop = true;
        video.preload = 'auto';
        video.controls = false;
        video.playsInline = true;
        video.muted = true;
        video.defaultMuted = true;
        video.src = _resolveUrl(item.file_url);
        if (posterUrl) video.poster = posterUrl;
        video.setAttribute('muted', 'muted');
        video.setAttribute('playsinline', 'playsinline');
        video.setAttribute('webkit-playsinline', 'webkit-playsinline');
        video.setAttribute('disablepictureinpicture', '');
        video.playbackRate = 1;
        video.addEventListener('error', () => {
          video.style.display = 'none';
          const errIcon = document.createElement('div');
          errIcon.className = 'sv-media-error';
          errIcon.innerHTML = '<svg width="40" height="40" viewBox="0 0 24 24" fill="rgba(255,255,255,0.5)"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-2h2v2zm0-4h-2V7h2v6z"/></svg>';
          frame.appendChild(errIcon);
        });
        video.addEventListener('loadedmetadata', () => {
          const playAttempt = video.play();
          if (playAttempt && typeof playAttempt.catch === 'function') playAttempt.catch(() => {});
        });
        _currentVideo = video;
        frame.appendChild(video);

        const playToggle = document.createElement('button');
        playToggle.className = 'sv-play-toggle';
        playToggle.setAttribute('type', 'button');
        playToggle.setAttribute('aria-label', 'تشغيل أو إيقاف الفيديو');
        playToggle.innerHTML = '<svg width="34" height="34" viewBox="0 0 24 24" fill="white"><path d="M8 5v14l11-7z"/></svg>';
        playToggle.addEventListener('click', (event) => {
          event.stopPropagation();
          _togglePlayback(video, playToggle);
        });
        frame.appendChild(playToggle);

        const muteBtn = document.createElement('button');
        muteBtn.className = 'sv-mute-btn';
        muteBtn.setAttribute('type', 'button');
        muteBtn.setAttribute('aria-label', 'تشغيل أو كتم الصوت');
        muteBtn.innerHTML = _soundIcon(true);
        muteBtn.addEventListener('click', (event) => {
          event.stopPropagation();
          video.muted = !video.muted;
          muteBtn.innerHTML = _soundIcon(video.muted);
        });
        frame.appendChild(muteBtn);

        video.addEventListener('play', () => playToggle.classList.add('hidden'));
        video.addEventListener('pause', () => playToggle.classList.remove('hidden'));

        if (_isTikTokMode()) {
          _bindTikTokVideoGestures(frame, video, playToggle);
        } else {
          frame.addEventListener('click', () => _togglePlayback(video, playToggle));
        }
      } else {
        _currentVideo = null;
        mediaEl.classList.add('is-image');
        const imgUrl = _resolveUrl(item.thumbnail_url || item.file_url);
        if (imgUrl) {
          const imageShell = document.createElement('div');
          imageShell.className = 'sv-image-shell';

          const img = document.createElement('img');
          img.className = 'sv-image';
          img.src = imgUrl;
          img.alt = item.caption || 'لمحة';
          img.addEventListener('error', () => {
            img.style.display = 'none';
            const errIcon = document.createElement('div');
            errIcon.className = 'sv-media-error';
            errIcon.innerHTML = '<svg width="40" height="40" viewBox="0 0 24 24" fill="rgba(255,255,255,0.5)"><path d="M21 5v6.59l-3-3.01-4 4.01-4-4-4 4-3-3.01V5c0-1.1.9-2 2-2h14c1.1 0 2 .9 2 2zm-3 6.42l3 3.01V19c0 1.1-.9 2-2 2H5c-1.1 0-2-.9-2-2v-6.58l3 2.99 4-4 4 4 4-3.99z"/></svg>';
            frame.appendChild(errIcon);
          });
          imageShell.appendChild(img);
          frame.appendChild(imageShell);
        }
      }
    }

    _primeAdjacentVideos();
    _navDirection = 0;

    const thumbsEl = document.getElementById('sv-thumbs');
    if (thumbsEl) {
      thumbsEl.innerHTML = '';
      if (_items.length <= 1) {
        thumbsEl.hidden = true;
      } else {
        thumbsEl.hidden = false;
        _items.forEach((entry, index) => {
          const thumbBtn = document.createElement('button');
          thumbBtn.className = 'sv-thumb' + (index === _currentIndex ? ' active' : '');
          thumbBtn.setAttribute('type', 'button');
          thumbBtn.setAttribute('aria-label', 'فتح العنصر ' + (index + 1));
          thumbBtn.addEventListener('click', () => _goToIndex(index));

          const thumbUrl = _resolveUrl(entry.thumbnail_url || entry.file_url);
          if (thumbUrl) {
            const img = document.createElement('img');
            img.src = thumbUrl;
            img.alt = entry.caption || ((_options.label || 'عنصر') + ' ' + (index + 1));
            thumbBtn.appendChild(img);
          } else {
            const fallback = document.createElement('span');
            fallback.className = 'sv-thumb-fallback';
            fallback.textContent = String(index + 1);
            thumbBtn.appendChild(fallback);
          }

          if (_isVideo(entry)) {
            const videoBadge = document.createElement('span');
            videoBadge.className = 'sv-thumb-video';
            videoBadge.innerHTML = '<svg width="12" height="12" viewBox="0 0 24 24" fill="white"><path d="M8 5v14l11-7z"/></svg>';
            thumbBtn.appendChild(videoBadge);
          }

          thumbsEl.appendChild(thumbBtn);
        });

        const activeThumb = thumbsEl.querySelector('.sv-thumb.active');
        if (activeThumb && typeof activeThumb.scrollIntoView === 'function') {
          activeThumb.scrollIntoView({ inline: 'center', block: 'nearest', behavior: 'smooth' });
        }
      }
    }

    // Keep the spotlight media clean in web view.
    const bottomEl = document.getElementById('sv-bottom');
    if (bottomEl) {
      bottomEl.innerHTML = '';
      bottomEl.hidden = true;
    }

    // Side actions
    const sideEl = document.getElementById('sv-side');
    if (sideEl) {
      sideEl.innerHTML = '';

      const avatarBtn = _buildSideAvatar(item);
      if (avatarBtn) {
        sideEl.appendChild(avatarBtn);
      }

      // Like button
      const likeBtn = _buildSideAction(
        item.is_liked ? 'like-filled' : 'like-outline',
        item.is_liked ? '#4da3ff' : '#fff',
        _formatCount(item.likes_count || 0),
        () => _toggleLike(item)
      );
      likeBtn.id = 'sv-like-btn';
      sideEl.appendChild(likeBtn);

      // Save button
      const saveBtn = _buildSideAction(
        item.is_saved ? 'bookmark-filled' : 'bookmark-outline',
        item.is_saved ? '#ffc107' : '#fff',
        _formatCount(item.saves_count || 0),
        () => _toggleSave(item)
      );
      saveBtn.id = 'sv-save-btn';
      sideEl.appendChild(saveBtn);

      const commentBtn = _buildSideAction(
        'comment-outline',
        '#fff',
        _formatCount(item.comments_count || 0),
        () => _toggleCommentsSheet(item)
      );
      commentBtn.id = 'sv-comment-btn';
      sideEl.appendChild(commentBtn);

      const shareBtn = _buildSideAction(
        'share-outline',
        '#fff',
        _shareCopy('shareAction'),
        () => _toggleShareSheet(item)
      );
      shareBtn.id = 'sv-share-btn';
      sideEl.appendChild(shareBtn);
    }
  }

  /* ----------------------------------------------------------
     SIDE ACTION BUTTON
  ---------------------------------------------------------- */
  function _buildSideAction(iconType, color, label, onTap) {
    const wrap = document.createElement('button');
    wrap.className = 'sv-action';
    wrap.setAttribute('type', 'button');
    wrap.setAttribute('aria-label', label);
    wrap.addEventListener('click', onTap);

    const iconSvg = document.createElement('div');
    iconSvg.className = 'sv-action-icon';

    const svgPaths = {
      'like-filled': '<path d="M14 9V5.8c0-1.02-.83-1.8-1.8-1.8-.43 0-.84.16-1.16.45L7 8v12h9.06c.82 0 1.54-.5 1.84-1.26l2.7-6.75c.26-.66-.22-1.39-.93-1.39H14z"/><path d="M3 8h3v12H3z"/>',
      'like-outline': '<path d="M2 9h4v12H2z"/><path d="M22 10.88c0-1.03-.84-1.88-1.88-1.88h-5.68l.86-4.02.03-.32c0-.41-.17-.79-.44-1.06L13.88 2 7.29 8.59C7.11 8.77 7 9.03 7 9.31V19c0 1.1.9 2 2 2h8.55c.8 0 1.52-.48 1.84-1.21l2.89-6.63c.11-.25.17-.52.17-.79v-1.49zM9 19V10.14l4.34-4.34L12.23 11h7.89v1.31L17.23 19H9z"/>',
      'bookmark-filled': '<path d="M17 3H7c-1.1 0-1.99.9-1.99 2L5 21l7-3 7 3V5c0-1.1-.9-2-2-2z"/>',
      'bookmark-outline': '<path d="M17 3H7c-1.1 0-1.99.9-1.99 2L5 21l7-3 7 3V5c0-1.1-.9-2-2-2zm0 15l-5-2.18L7 18V5h10v13z"/>',
      'comment-outline': '<path d="M4 5.5C4 4.12 5.12 3 6.5 3h11C18.88 3 20 4.12 20 5.5v8c0 1.38-1.12 2.5-2.5 2.5H11l-4.5 4v-4H6.5C5.12 16 4 14.88 4 13.5v-8z"/>',
      'share-outline': '<path d="M18 16.08c-.76 0-1.44.3-1.96.77L8.91 12.7a2.48 2.48 0 0 0 0-1.39l7-4.11A2.99 2.99 0 1 0 15 5a3 3 0 0 0 .04.49l-7 4.12a3 3 0 1 0 0 4.78l7.05 4.14c-.03.15-.05.31-.05.47a3 3 0 1 0 3-2.92z"/>',
    };

    iconSvg.innerHTML = '<svg width="30" height="30" viewBox="0 0 24 24" fill="' + color + '">' + (svgPaths[iconType] || '') + '</svg>';
    wrap.appendChild(iconSvg);

    const lbl = document.createElement('span');
    lbl.className = 'sv-action-label';
    lbl.textContent = label;
    wrap.appendChild(lbl);

    return wrap;
  }

  function _buildSideAvatar(item) {
    const providerId = Number(item?.provider_id || 0);
    const providerName = _getProviderDisplayName(item);
    const providerAvatarUrl = _getProviderAvatarUrl(item);
    if (!providerId && !providerName && !providerAvatarUrl) return null;

    const avatar = document.createElement(providerId > 0 ? 'button' : 'div');
    avatar.className = 'sv-side-avatar' + (providerId > 0 ? ' is-clickable' : '');
    if (providerId > 0) {
      avatar.setAttribute('type', 'button');
      avatar.setAttribute('aria-label', 'فتح حساب ' + (providerName || 'صاحب اللمحة'));
      avatar.addEventListener('click', (event) => {
        event.stopPropagation();
        window.location.href = '/provider/' + encodeURIComponent(String(providerId)) + '/';
      });
    }

    if (providerAvatarUrl) {
      const img = document.createElement('img');
      img.src = providerAvatarUrl;
      img.alt = providerName || 'صاحب اللمحة';
      avatar.appendChild(img);
    } else {
      avatar.textContent = _getProviderInitial(providerName || 'ن');
    }

    if (typeof UI !== 'undefined' && UI && typeof UI.presenceDot === 'function') {
      avatar.appendChild(UI.presenceDot(!!item?.provider_is_online, { size: 'lg' }));
    }

    const verificationBadges = _buildAvatarVerificationBadges(item);
    if (verificationBadges) {
      avatar.appendChild(verificationBadges);
    }

    return avatar;
  }

  function _buildAvatarVerificationBadges(item) {
    const hasBlue = !!item?.is_verified_blue;
    const hasGreen = !!item?.is_verified_green;
    if (!hasBlue && !hasGreen) return null;

    const frag = document.createDocumentFragment();
    if (hasBlue) {
      frag.appendChild(_buildAvatarVerificationBadge('blue'));
    }
    if (hasGreen) {
      frag.appendChild(_buildAvatarVerificationBadge('green'));
    }
    return frag;
  }

  function _buildAvatarVerificationBadge(kind) {
    const isBlue = kind === 'blue';
    const badge = document.createElement('span');
    badge.className = 'sv-side-avatar-badge ' + (isBlue ? 'is-blue' : 'is-green');
    badge.setAttribute('aria-hidden', 'true');
    badge.innerHTML = [
      '<svg viewBox="0 0 16 16" width="10" height="10" focusable="false" aria-hidden="true">',
      '<path d="M3.5 8.4 6.4 11.1 12.4 5.2" fill="none" stroke="#fff" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>',
      '</svg>',
    ].join('');
    return badge;
  }

  function _toggleCommentsSheet(item) {
    if (_commentsSheet) {
      _closeCommentsSheet();
      return;
    }
    _openCommentsSheet(item);
  }

  function _openCommentsSheet(item) {
    if (!item || !document.body) return;
    _closeShareSheet();
    _closeOptionsMenu();
    _closeDialogSheet();
    _closeCommentsSheet();

    const sheet = document.createElement('div');
    sheet.className = 'sv-comments-sheet';

    const backdrop = document.createElement('button');
    backdrop.className = 'sv-comments-backdrop';
    backdrop.setAttribute('type', 'button');
    backdrop.setAttribute('aria-label', _shareCopy('commentsClose'));
    backdrop.addEventListener('click', () => _closeCommentsSheet());
    sheet.appendChild(backdrop);

    const card = document.createElement('div');
    card.className = 'sv-comments-card';
    card.addEventListener('click', (event) => {
      event.stopPropagation();
      _closeCommentActionsMenu();
    });

    const header = document.createElement('div');
    header.className = 'sv-comments-header';

    const headerText = document.createElement('div');
    headerText.className = 'sv-comments-header-text';
    const title = document.createElement('h3');
    title.className = 'sv-comments-title';
    title.textContent = _shareCopy('commentsTitle');
    const subtitle = document.createElement('p');
    subtitle.className = 'sv-comments-subtitle';
    subtitle.textContent = _shareCopy('commentsSubtitle');
    headerText.appendChild(title);
    headerText.appendChild(subtitle);

    const actions = document.createElement('div');
    actions.className = 'sv-comments-header-actions';
    const countPill = document.createElement('span');
    countPill.className = 'sv-comments-count-pill';
    countPill.id = 'sv-comments-count-pill';
    countPill.textContent = _formatCount(item.comments_count || 0);
    const closeBtn = document.createElement('button');
    closeBtn.className = 'sv-comments-close';
    closeBtn.setAttribute('type', 'button');
    closeBtn.setAttribute('aria-label', _shareCopy('commentsClose'));
    closeBtn.innerHTML = '<svg width="20" height="20" viewBox="0 0 24 24" fill="none"><path d="M18 6L6 18M6 6l12 12" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>';
    closeBtn.addEventListener('click', () => _closeCommentsSheet());
    actions.appendChild(countPill);
    actions.appendChild(closeBtn);

    header.appendChild(headerText);
    header.appendChild(actions);
    card.appendChild(header);

    const status = document.createElement('div');
    status.className = 'sv-comments-status';
    status.id = 'sv-comments-status';
    status.textContent = _shareCopy('commentsLoading');
    card.appendChild(status);

    const list = document.createElement('div');
    list.className = 'sv-comments-list';
    list.id = 'sv-comments-list';
    card.appendChild(list);

    const composer = document.createElement('div');
    composer.className = 'sv-comments-composer';

    const replyBar = document.createElement('div');
    replyBar.className = 'sv-comments-replybar';
    replyBar.id = 'sv-comments-replybar';
    replyBar.hidden = true;
    const replyText = document.createElement('div');
    replyText.className = 'sv-comments-replybar-text';
    replyText.id = 'sv-comments-replybar-text';
    const cancelReplyBtn = document.createElement('button');
    cancelReplyBtn.className = 'sv-comments-replybar-cancel';
    cancelReplyBtn.setAttribute('type', 'button');
    cancelReplyBtn.textContent = _shareCopy('commentsCancelReply');
    cancelReplyBtn.addEventListener('click', () => _setCommentReplyTarget(null));
    replyBar.appendChild(replyText);
    replyBar.appendChild(cancelReplyBtn);

    const input = document.createElement('textarea');
    input.className = 'sv-comments-input';
    input.id = 'sv-comments-input';
    input.rows = 2;
    input.maxLength = 1000;
    input.placeholder = _isAuthenticated() ? _shareCopy('commentsPlaceholder') : _shareCopy('commentsLoginPrompt');
    input.setAttribute('aria-label', _shareCopy('commentsPlaceholder'));
    input.addEventListener('input', () => _resizeCommentsInput(input));
    if (!_isAuthenticated()) {
      input.readOnly = true;
      input.addEventListener('focus', () => _redirectToLogin());
      input.addEventListener('click', () => _redirectToLogin());
    }

    const sendBtn = document.createElement('button');
    sendBtn.className = 'sv-comments-send';
    sendBtn.id = 'sv-comments-send';
    sendBtn.setAttribute('type', 'button');
    sendBtn.textContent = _isAuthenticated() ? _shareCopy('commentsSend') : _shareCopy('commentsLoginAction');
    sendBtn.addEventListener('click', () => {
      if (!_isAuthenticated()) {
        _redirectToLogin();
        return;
      }
      _submitComment(item);
    });

    const composeRow = document.createElement('div');
    composeRow.className = 'sv-comments-compose-row';
    composeRow.appendChild(input);
    composeRow.appendChild(sendBtn);

    input.addEventListener('keydown', (event) => {
      if (event.key === 'Enter' && !event.shiftKey) {
        event.preventDefault();
        if (!_isAuthenticated()) {
          _redirectToLogin();
          return;
        }
        _submitComment(item);
      }
    });

    composer.appendChild(replyBar);
    composer.appendChild(composeRow);
    card.appendChild(composer);

    sheet.appendChild(card);
    document.body.appendChild(sheet);
    _commentsSheet = sheet;
    _resizeCommentsInput(input);
    requestAnimationFrame(() => sheet.classList.add('is-visible'));
    _setCommentReplyTarget(null);
    _loadComments(item);
  }

  function _resizeCommentsInput(input) {
    if (!input) return;
    input.style.height = 'auto';
    input.style.height = Math.min(input.scrollHeight, 144) + 'px';
  }

  async function _loadComments(item) {
    const status = document.getElementById('sv-comments-status');
    const list = document.getElementById('sv-comments-list');
    if (!status || !list) return;
    status.textContent = _shareCopy('commentsLoading');
    list.innerHTML = '';
    const token = ++_commentsFetchToken;
    try {
      const res = await ApiClient.get(_withMode(_contentDetailPath(item, 'comments/') + '?limit=50', _options.modeContext || 'client'));
      if (token !== _commentsFetchToken) return;
      if (!res || !res.ok || !res.data) throw new Error('comments_load_failed');
      const rows = Array.isArray(res.data.results) ? res.data.results : [];
      item.comments_count = Number(res.data.count) || rows.length || 0;
      _syncCommentsCount(item);
      if (!rows.length) {
        status.textContent = _shareCopy('commentsEmpty');
        list.innerHTML = '<div class="sv-comments-empty"><span class="sv-comments-empty-icon">💬</span><strong>' + _shareCopy('commentsEmpty') + '</strong></div>';
        return;
      }
      status.textContent = '';
      rows.forEach((comment) => list.appendChild(_buildCommentThread(comment)));
    } catch (_) {
      if (token !== _commentsFetchToken) return;
      status.textContent = _shareCopy('commentsLoadFailed');
      list.innerHTML = '';
    }
  }

  function _buildCommentThread(comment) {
    const thread = document.createElement('div');
    thread.className = 'sv-comment-thread';
    const currentItem = _items[_currentIndex];
    thread.appendChild(_buildCommentRow(comment, { isReply: false, item: currentItem }));

    const replies = Array.isArray(comment && comment.replies) ? comment.replies : [];
    if (replies.length) {
      const repliesHost = document.createElement('div');
      repliesHost.className = 'sv-comment-replies';
      replies.forEach((reply) => repliesHost.appendChild(_buildCommentRow(reply, { isReply: true, parentComment: comment, item: currentItem })));
      thread.appendChild(repliesHost);
    }
    return thread;
  }

  function _buildCommentRow(comment, options = {}) {
    const row = document.createElement('div');
    row.className = 'sv-comment-row' + (options.isReply ? ' is-reply' : '');
    row.setAttribute('data-comment-id', String(comment && comment.id || ''));

    const avatar = document.createElement('span');
    avatar.className = 'sv-comment-avatar';
    const avatarUrl = _resolveUrl(comment && comment.profile_image);
    if (avatarUrl) {
      const img = document.createElement('img');
      img.src = avatarUrl;
      img.alt = comment.display_name || comment.username || 'مستخدم';
      avatar.appendChild(img);
    } else {
      avatar.textContent = _getProviderInitial(comment && (comment.display_name || comment.username || 'ن'));
    }
    row.appendChild(avatar);

    const content = document.createElement('div');
    content.className = 'sv-comment-content';
    const meta = document.createElement('div');
    meta.className = 'sv-comment-meta';
    const author = document.createElement('strong');
    author.className = 'sv-comment-author';
    author.textContent = comment.display_name || comment.username || 'مستخدم';
    meta.appendChild(author);

    const verificationBadge = _buildCommentVerificationBadge(comment);
    if (verificationBadge) meta.appendChild(verificationBadge);

    const time = document.createElement('span');
    time.className = 'sv-comment-time';
    time.textContent = _formatRelativeTime(comment.created_at);
    meta.appendChild(time);

    const body = document.createElement('p');
    body.className = 'sv-comment-body';
    body.textContent = comment.body || '';

    const footer = document.createElement('div');
    footer.className = 'sv-comment-footer';
    const likeBtn = document.createElement('button');
    likeBtn.className = 'sv-comment-like-btn';
    likeBtn.setAttribute('type', 'button');
    _renderCommentLikeButtonState(likeBtn, comment);
    likeBtn.addEventListener('click', () => _toggleCommentLike(options.item || _items[_currentIndex], comment, likeBtn));
    footer.appendChild(likeBtn);

    if (!options.isReply && _isAuthenticated()) {
      const replyBtn = document.createElement('button');
      replyBtn.className = 'sv-comment-reply-btn';
      replyBtn.setAttribute('type', 'button');
      replyBtn.textContent = _shareCopy('commentsReplyAction');
      replyBtn.addEventListener('click', () => _setCommentReplyTarget(comment));
      footer.appendChild(replyBtn);
    }

    if (_isAuthenticated()) {
      const moreBtn = document.createElement('button');
      moreBtn.className = 'sv-comment-more-btn';
      moreBtn.setAttribute('type', 'button');
      moreBtn.setAttribute('aria-label', _shareCopy('commentsMoreAction'));
      moreBtn.innerHTML = '<svg width="18" height="18" viewBox="0 0 24 24" fill="none"><circle cx="12" cy="5" r="1.8" fill="currentColor"/><circle cx="12" cy="12" r="1.8" fill="currentColor"/><circle cx="12" cy="19" r="1.8" fill="currentColor"/></svg>';
      moreBtn.addEventListener('click', (event) => _toggleCommentActionsMenu(event, options.item || _items[_currentIndex], comment));
      footer.appendChild(moreBtn);
    }

    content.appendChild(meta);
    content.appendChild(body);
    if (footer.childNodes.length) content.appendChild(footer);
    row.appendChild(content);
    return row;
  }

  function _buildCommentVerificationBadge(comment) {
    if (typeof UI === 'undefined' || !UI || typeof UI.buildVerificationBadges !== 'function') return null;
    if (!comment || (!comment.is_verified_blue && !comment.is_verified_green)) return null;
    const badges = UI.buildVerificationBadges({
      isVerifiedBlue: !!comment.is_verified_blue,
      isVerifiedGreen: !!comment.is_verified_green,
      className: 'sv-comment-badges',
      iconSize: 11,
      gap: '2px',
    });
    if (!badges) return null;
    badges.setAttribute('aria-hidden', 'true');
    return badges;
  }

  async function _submitComment(item) {
    if (_commentSubmitInFlight) return;
    const input = document.getElementById('sv-comments-input');
    const sendBtn = document.getElementById('sv-comments-send');
    const status = document.getElementById('sv-comments-status');
    const list = document.getElementById('sv-comments-list');
    if (!input || !sendBtn || !list) return;
    const body = String(input.value || '').trim();
    if (!body) return;

    _commentSubmitInFlight = true;
    sendBtn.disabled = true;
    if (status) status.textContent = _shareCopy('sending');
    try {
      const res = await ApiClient.request(
        _withMode(_contentDetailPath(item, 'comments/'), _options.modeContext || 'client'),
        {
          method: 'POST',
          body: {
            body,
            parent: _commentReplyTarget ? _commentReplyTarget.id : null,
          },
        }
      );
      if (!res || !res.ok || !res.data) throw new Error('comment_failed');
      item.comments_count = (Number(item.comments_count) || 0) + 1;
      _syncCommentsCount(item);
      if (status) status.textContent = '';
      const empty = list.querySelector('.sv-comments-empty');
      if (empty) list.innerHTML = '';
      if (_commentReplyTarget) {
        _appendReplyToExistingThread(res.data, _commentReplyTarget.id);
      } else {
        list.prepend(_buildCommentThread(res.data));
      }
      input.value = '';
      _resizeCommentsInput(input);
      _showToast(_commentReplyTarget ? _shareCopy('commentsReplyAdded') : _shareCopy('commentsAdded'));
      _setCommentReplyTarget(null);
    } catch (_) {
      if (status) status.textContent = _shareCopy('commentsSendFailed');
    } finally {
      _commentSubmitInFlight = false;
      sendBtn.disabled = false;
    }
  }

  function _syncCommentsCount(item) {
    const count = Math.max(0, Number(item && item.comments_count) || 0);
    const label = document.querySelector('#sv-comment-btn .sv-action-label');
    if (label) label.textContent = _formatCount(count);
    const pill = document.getElementById('sv-comments-count-pill');
    if (pill) pill.textContent = _formatCount(count);
    _emitEngagementUpdate(item);
  }

  function _setCommentReplyTarget(comment) {
    _commentReplyTarget = comment || null;
    const bar = document.getElementById('sv-comments-replybar');
    const barText = document.getElementById('sv-comments-replybar-text');
    const input = document.getElementById('sv-comments-input');
    if (bar) bar.hidden = !_commentReplyTarget;
    if (barText) {
      barText.textContent = _commentReplyTarget
        ? (_shareCopy('commentsReplyingTo') + ' ' + (_commentReplyTarget.display_name || _commentReplyTarget.username || ''))
        : '';
    }
    if (input) {
      input.placeholder = _commentReplyTarget ? _shareCopy('commentsReplyPlaceholder') : _shareCopy('commentsPlaceholder');
      if (_commentReplyTarget) input.focus();
    }
  }

  function _appendReplyToExistingThread(reply, parentId) {
    const list = document.getElementById('sv-comments-list');
    if (!list) return;
    const parentRow = list.querySelector('.sv-comment-row[data-comment-id="' + String(parentId) + '"]');
    if (!parentRow) {
      list.prepend(_buildCommentThread(reply));
      return;
    }
    const thread = parentRow.closest('.sv-comment-thread');
    if (!thread) return;
    let repliesHost = thread.querySelector('.sv-comment-replies');
    if (!repliesHost) {
      repliesHost = document.createElement('div');
      repliesHost.className = 'sv-comment-replies';
      thread.appendChild(repliesHost);
    }
    repliesHost.appendChild(_buildCommentRow(reply, { isReply: true, item: _items[_currentIndex] }));

    const parentData = _commentReplyTarget;
    if (parentData) {
      parentData.replies_count = (Number(parentData.replies_count) || 0) + 1;
      if (!Array.isArray(parentData.replies)) parentData.replies = [];
      parentData.replies.push(reply);
    }
  }

  function _toggleCommentActionsMenu(event, item, comment) {
    event.preventDefault();
    event.stopPropagation();
    const trigger = event.currentTarget;
    if (_commentActionsMenu && _commentActionsMenu.dataset.commentId === String(comment.id)) {
      _closeCommentActionsMenu();
      return;
    }
    _closeCommentActionsMenu();
    const menu = document.createElement('div');
    menu.className = 'sv-comment-actions-menu';
    menu.dataset.commentId = String(comment.id);

    if (comment && comment.is_mine) {
      const deleteBtn = document.createElement('button');
      deleteBtn.className = 'sv-comment-actions-item is-danger';
      deleteBtn.setAttribute('type', 'button');
      deleteBtn.textContent = _shareCopy('commentsDeleteAction');
      deleteBtn.addEventListener('click', () => {
        _closeCommentActionsMenu();
        _openConfirmSheet({
          title: _shareCopy('commentsDeleteConfirmTitle'),
          body: _shareCopy('commentsDeleteConfirmBody'),
          confirmLabel: _shareCopy('commentsDeleteConfirm'),
          destructive: true,
          onConfirm: () => _deleteComment(comment),
        });
      });
      menu.appendChild(deleteBtn);
    } else {
      const reportBtn = document.createElement('button');
      reportBtn.className = 'sv-comment-actions-item';
      reportBtn.setAttribute('type', 'button');
      reportBtn.textContent = _shareCopy('commentsReportAction');
      reportBtn.addEventListener('click', () => {
        _closeCommentActionsMenu();
        _openCommentReportSheet(item, comment);
      });
      menu.appendChild(reportBtn);
    }

    document.body.appendChild(menu);
    const rect = trigger.getBoundingClientRect();
    menu.style.top = Math.max(12, rect.bottom + 6) + 'px';
    menu.style.left = Math.max(12, rect.left - 96) + 'px';
    _commentActionsMenu = menu;
  }

  function _closeCommentActionsMenu() {
    if (_commentActionsMenu) {
      _commentActionsMenu.remove();
      _commentActionsMenu = null;
    }
  }

  async function _deleteComment(comment) {
    const item = _items[_currentIndex];
    if (!item || !comment || !comment.id) return;
    const response = await ApiClient.request(
      _withMode(_contentDetailPath(item, 'comments/' + encodeURIComponent(String(comment.id)) + '/'), _options.modeContext || 'client'),
      { method: 'DELETE' }
    );
    if (!response || !response.ok) {
      _showToast(_shareCopy('commentsDeleteFailed'));
      return;
    }
    const removedCount = 1 + Math.max(0, Number(comment.replies_count) || 0);
    item.comments_count = Math.max(0, (Number(item.comments_count) || 0) - removedCount);
    _syncCommentsCount(item);
    _removeCommentFromSheet(comment);
    if (_commentReplyTarget && Number(_commentReplyTarget.id) === Number(comment.id)) {
      _setCommentReplyTarget(null);
    }
    _closeDialogSheet();
    _showToast(_shareCopy('commentsDeleted'));
  }

  function _renderCommentLikeButtonState(button, comment) {
    if (!button) return;
    const count = Math.max(0, Number(comment && comment.likes_count) || 0);
    const isLiked = !!(comment && comment.is_liked);
    button.classList.toggle('is-active', isLiked);
    button.setAttribute('aria-label', isLiked ? _shareCopy('commentsUnlikeAction') : _shareCopy('commentsLikeAction'));
    button.textContent = (isLiked ? '♥ ' : '♡ ') + String(count);
  }

  async function _toggleCommentLike(item, comment, button) {
    if (!_isAuthenticated()) {
      _redirectToLogin();
      return;
    }
    if (!item || !comment || !comment.id || !button || button.disabled) return;
    const wasLiked = !!comment.is_liked;
    const previousCount = Math.max(0, Number(comment.likes_count) || 0);
    comment.is_liked = !wasLiked;
    comment.likes_count = Math.max(0, previousCount + (wasLiked ? -1 : 1));
    button.disabled = true;
    _renderCommentLikeButtonState(button, comment);
    try {
      const endpoint = _withMode(
        _contentDetailPath(item, 'comments/' + encodeURIComponent(String(comment.id)) + '/' + (wasLiked ? 'unlike/' : 'like/')),
        _options.modeContext || 'client'
      );
      const response = await ApiClient.request(endpoint, { method: 'POST' });
      if (!response || !response.ok) throw new Error('comment_like_failed');
      if (response.data && Number.isFinite(Number(response.data.likes_count))) {
        comment.likes_count = Math.max(0, Number(response.data.likes_count) || 0);
      }
      _renderCommentLikeButtonState(button, comment);
    } catch (_) {
      comment.is_liked = wasLiked;
      comment.likes_count = previousCount;
      _renderCommentLikeButtonState(button, comment);
      _showToast(_shareCopy('commentsLikeFailed'));
    } finally {
      button.disabled = false;
    }
  }

  function _openCommentReportSheet(item, comment) {
    if (!_isAuthenticated()) {
      _redirectToLogin();
      return;
    }
    _closeDialogSheet();
    const sheet = document.createElement('div');
    sheet.className = 'sv-dialog-sheet';
    const backdrop = document.createElement('button');
    backdrop.className = 'sv-dialog-backdrop';
    backdrop.setAttribute('type', 'button');
    backdrop.addEventListener('click', () => _closeDialogSheet());
    sheet.appendChild(backdrop);

    const card = document.createElement('div');
    card.className = 'sv-dialog-card';

    const title = document.createElement('h3');
    title.className = 'sv-dialog-title';
    title.textContent = _shareCopy('commentsReportTitle');
    const subtitle = document.createElement('p');
    subtitle.className = 'sv-dialog-subtitle';
    subtitle.textContent = _shareCopy('commentsReportSubtitle');
    card.appendChild(title);
    card.appendChild(subtitle);

    const label = document.createElement('label');
    label.className = 'sv-dialog-label';
    label.textContent = _shareCopy('reportReasonLabel');
    const select = document.createElement('select');
    select.className = 'sv-dialog-select';
    [
      _shareCopy('reportReasonInappropriate'),
      _shareCopy('reportReasonSpam'),
      _shareCopy('reportReasonViolence'),
      _shareCopy('reportReasonCopyright'),
      _shareCopy('reportReasonOther'),
    ].forEach((reason) => {
      const option = document.createElement('option');
      option.value = reason;
      option.textContent = reason;
      select.appendChild(option);
    });
    card.appendChild(label);
    card.appendChild(select);

    const detailsLabel = document.createElement('label');
    detailsLabel.className = 'sv-dialog-label';
    detailsLabel.textContent = _shareCopy('reportDetailsLabel');
    const textarea = document.createElement('textarea');
    textarea.className = 'sv-dialog-textarea';
    textarea.placeholder = _shareCopy('reportDetailsPlaceholder');
    textarea.maxLength = 500;
    card.appendChild(detailsLabel);
    card.appendChild(textarea);

    const actions = document.createElement('div');
    actions.className = 'sv-dialog-actions';
    const cancelBtn = document.createElement('button');
    cancelBtn.className = 'sv-dialog-btn is-secondary';
    cancelBtn.setAttribute('type', 'button');
    cancelBtn.textContent = _shareCopy('cancelAction');
    cancelBtn.addEventListener('click', () => _closeDialogSheet());
    const submitBtn = document.createElement('button');
    submitBtn.className = 'sv-dialog-btn is-primary';
    submitBtn.setAttribute('type', 'button');
    submitBtn.textContent = _shareCopy('reportSubmit');
    submitBtn.addEventListener('click', () => _submitCommentReport(item, comment, select.value, textarea.value));
    actions.appendChild(cancelBtn);
    actions.appendChild(submitBtn);
    card.appendChild(actions);

    sheet.appendChild(card);
    document.body.appendChild(sheet);
    _dialogSheet = sheet;
    requestAnimationFrame(() => sheet.classList.add('is-visible'));
  }

  async function _submitCommentReport(item, comment, reason, details) {
    if (_reportSubmitInFlight) return;
    _reportSubmitInFlight = true;
    try {
      const response = await ApiClient.request(
        _withMode(_contentDetailPath(item, 'comments/' + encodeURIComponent(String(comment.id)) + '/report/'), _activeMode(item)),
        {
          method: 'POST',
          body: {
            reason: String(reason || '').trim() || _shareCopy('reportReasonOther'),
            details: String(details || '').trim(),
            reported_label: String(comment && comment.body || '').trim(),
          },
        }
      );
      if (!response || !response.ok) throw new Error('comment_report_failed');
      _showToast(_shareCopy('commentsReportSuccess'));
      _closeDialogSheet();
    } catch (_) {
      _showToast(_shareCopy('commentsReportFailed'));
    } finally {
      _reportSubmitInFlight = false;
    }
  }

  function _removeCommentFromSheet(comment) {
    const list = document.getElementById('sv-comments-list');
    if (!list || !comment) return;
    const row = list.querySelector('.sv-comment-row[data-comment-id="' + String(comment.id) + '"]');
    if (!row) return;
    const replyHost = row.closest('.sv-comment-replies');
    if (replyHost) {
      row.remove();
      if (!replyHost.children.length) replyHost.remove();
      return;
    }
    const thread = row.closest('.sv-comment-thread');
    if (thread) thread.remove();
    if (!list.children.length) {
      const status = document.getElementById('sv-comments-status');
      if (status) status.textContent = _shareCopy('commentsEmpty');
      list.innerHTML = '<div class="sv-comments-empty"><span class="sv-comments-empty-icon">💬</span><strong>' + _shareCopy('commentsEmpty') + '</strong></div>';
    }
  }

  function _formatRelativeTime(value) {
    if (!value) return '';
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return '';
    const diffSeconds = Math.round((date.getTime() - Date.now()) / 1000);
    const absSeconds = Math.abs(diffSeconds);
    const locale = String(document.documentElement.lang || 'ar').toLowerCase().startsWith('en') ? 'en' : 'ar';
    const rtf = typeof Intl !== 'undefined' && Intl.RelativeTimeFormat
      ? new Intl.RelativeTimeFormat(locale, { numeric: 'auto' })
      : null;

    const steps = [
      [60, 'second'],
      [3600, 'minute'],
      [86400, 'hour'],
      [604800, 'day'],
      [2629800, 'week'],
      [31557600, 'month'],
      [Infinity, 'year'],
    ];
    let unit = 'second';
    let amount = diffSeconds;
    for (let index = 0; index < steps.length; index += 1) {
      const [threshold, nextUnit] = steps[index];
      if (absSeconds < threshold) {
        unit = nextUnit;
        if (unit === 'second') amount = diffSeconds;
        else if (unit === 'minute') amount = Math.round(diffSeconds / 60);
        else if (unit === 'hour') amount = Math.round(diffSeconds / 3600);
        else if (unit === 'day') amount = Math.round(diffSeconds / 86400);
        else if (unit === 'week') amount = Math.round(diffSeconds / 604800);
        else if (unit === 'month') amount = Math.round(diffSeconds / 2629800);
        else amount = Math.round(diffSeconds / 31557600);
        break;
      }
    }
    if (rtf) return rtf.format(amount, unit);
    return date.toLocaleDateString(locale === 'en' ? 'en-US' : 'ar-SA');
  }

  /* ----------------------------------------------------------
     TOGGLE LIKE / SAVE
  ---------------------------------------------------------- */
  async function _toggleLike(item) {
    if (!_isAuthenticated()) {
      _redirectToLogin();
      return;
    }
    const wasLiked = !!item.is_liked;
    // Optimistic update
    item.is_liked = !wasLiked;
    item.likes_count = (item.likes_count || 0) + (wasLiked ? -1 : 1);
    if (item.likes_count < 0) item.likes_count = 0;
    _renderCurrent();
    _emitEngagementUpdate(item);

    try {
      const endpoint = _buildReactionEndpoint(item, 'like', wasLiked);
      const res = await ApiClient.request(endpoint, { method: 'POST' });
      if (!res.ok) throw new Error();
      _showToast(item.is_liked ? 'تم تسجيل الإعجاب بصفتك ' + _getModeLabel() : 'تم إلغاء الإعجاب بصفتك ' + _getModeLabel());
    } catch (_) {
      // Revert
      item.is_liked = wasLiked;
      item.likes_count += wasLiked ? 1 : -1;
      _renderCurrent();
      _emitEngagementUpdate(item);
    }
  }

  async function _toggleSave(item) {
    if (!_isAuthenticated()) {
      _redirectToLogin();
      return;
    }
    const wasSaved = !!item.is_saved;
    item.is_saved = !wasSaved;
    item.saves_count = (item.saves_count || 0) + (wasSaved ? -1 : 1);
    if (item.saves_count < 0) item.saves_count = 0;
    _renderCurrent();
    _emitEngagementUpdate(item);

    try {
      const endpoint = _buildReactionEndpoint(item, 'save', wasSaved);
      const res = await ApiClient.request(endpoint, { method: 'POST' });
      if (!res.ok) throw new Error();
      _showToast(item.is_saved ? 'تم الحفظ بصفتك ' + _getModeLabel() : 'تمت إزالة الحفظ بصفتك ' + _getModeLabel());
    } catch (_) {
      item.is_saved = wasSaved;
      item.saves_count += wasSaved ? 1 : -1;
      _renderCurrent();
      _emitEngagementUpdate(item);
    }
  }

  function _shareCopy(key) {
    const isEnglish = String(document.documentElement.lang || '').toLowerCase().startsWith('en');
    const copy = {
      optionsAction: isEnglish ? 'Options' : 'الخيارات',
      shareAction: isEnglish ? 'Share' : 'مشاركة',
      commentsAction: isEnglish ? 'Comments' : 'التعليقات',
      commentsTitle: isEnglish ? 'Comments' : 'التعليقات',
      commentsPlaceholder: isEnglish ? 'Write a respectful comment...' : 'اكتب تعليقًا محترمًا...',
      commentsReplyPlaceholder: isEnglish ? 'Write your reply...' : 'اكتب ردك...',
      commentsSend: isEnglish ? 'Send' : 'إرسال',
      commentsLoading: isEnglish ? 'Loading comments...' : 'جارٍ تحميل التعليقات...',
      commentsEmpty: isEnglish ? 'No comments yet. Be the first.' : 'لا توجد تعليقات بعد. كن أول من يعلّق.',
      commentsLoginPrompt: isEnglish ? 'Log in to comment' : 'سجّل الدخول لإضافة تعليق',
      commentsLoginAction: isEnglish ? 'Log in' : 'تسجيل الدخول',
      commentsSendFailed: isEnglish ? 'Could not post your comment right now.' : 'تعذر نشر تعليقك حالياً.',
      commentsLoadFailed: isEnglish ? 'Comments are unavailable right now.' : 'التعليقات غير متاحة حالياً.',
      commentsAdded: isEnglish ? 'Your comment has been posted.' : 'تم نشر تعليقك.',
      commentsReplyAdded: isEnglish ? 'Your reply has been posted.' : 'تم نشر الرد.',
      commentsClose: isEnglish ? 'Close comments' : 'إغلاق التعليقات',
      commentsReplyAction: isEnglish ? 'Reply' : 'رد',
      commentsLikeAction: isEnglish ? 'Like' : 'إعجاب',
      commentsUnlikeAction: isEnglish ? 'Unlike' : 'إلغاء الإعجاب',
      commentsCancelReply: isEnglish ? 'Cancel reply' : 'إلغاء الرد',
      commentsReplyingTo: isEnglish ? 'Replying to' : 'الرد على',
      commentsDeleteAction: isEnglish ? 'Delete comment' : 'حذف التعليق',
      commentsReportAction: isEnglish ? 'Report comment' : 'الإبلاغ عن التعليق',
      commentsDeleteConfirmTitle: isEnglish ? 'Delete this comment?' : 'حذف هذا التعليق؟',
      commentsDeleteConfirmBody: isEnglish ? 'This will remove the comment and its replies permanently.' : 'سيؤدي ذلك إلى حذف التعليق وردوده نهائيًا.',
      commentsDeleteConfirm: isEnglish ? 'Delete' : 'حذف',
      commentsDeleteFailed: isEnglish ? 'Could not delete the comment right now.' : 'تعذر حذف التعليق حالياً.',
      commentsDeleted: isEnglish ? 'Comment deleted.' : 'تم حذف التعليق.',
      commentsLikeFailed: isEnglish ? 'Could not update the comment like right now.' : 'تعذر تحديث الإعجاب بالتعليق حالياً.',
      commentsReportTitle: isEnglish ? 'Report comment' : 'الإبلاغ عن التعليق',
      commentsReportSubtitle: isEnglish ? 'This report goes to the content management team with a clear comment label.' : 'سيصل هذا البلاغ إلى فريق إدارة المحتوى مع توضيح أنه بلاغ على تعليق.',
      commentsReportSuccess: isEnglish ? 'Comment report sent to the content team.' : 'تم إرسال بلاغ التعليق إلى فريق المحتوى.',
      commentsReportFailed: isEnglish ? 'Could not send the comment report right now.' : 'تعذر إرسال بلاغ التعليق حالياً.',
      commentsOptionsAction: isEnglish ? 'Comment options' : 'خيارات التعليق',
      commentsMoreAction: isEnglish ? 'More' : 'المزيد',
      shareTitle: isEnglish ? 'Share content' : 'مشاركة المحتوى',
      shareSubtitle: isEnglish ? 'Send it inside or outside the platform.' : 'شاركها داخل المنصة أو خارجها.',
      shareInside: isEnglish ? 'Inside platform' : 'داخل المنصة',
      shareWhatsApp: isEnglish ? 'WhatsApp' : 'واتساب',
      shareCopyLink: isEnglish ? 'Copy link' : 'نسخ الرابط',
      shareEmail: isEnglish ? 'Email' : 'إيميل',
      shareLinkCopied: isEnglish ? 'Link copied.' : 'تم نسخ الرابط.',
      shareLinkFailed: isEnglish ? 'Could not copy the link.' : 'تعذر نسخ الرابط.',
      shareSent: isEnglish ? 'Content sent in chat.' : 'تم إرسال المحتوى داخل المحادثة.',
      shareSendFailed: isEnglish ? 'Could not send the content right now.' : 'تعذر إرسال المحتوى حالياً.',
      searchPlaceholder: isEnglish ? 'Search by name or username' : 'ابحث بالاسم أو اسم المستخدم',
      searchHint: isEnglish ? 'Type at least 2 characters.' : 'اكتب حرفين على الأقل.',
      searchLoading: isEnglish ? 'Searching...' : 'جارٍ البحث...',
      searchEmpty: isEnglish ? 'No matching users found.' : 'لا يوجد مستخدمون مطابقون.',
      searchError: isEnglish ? 'Search is unavailable right now.' : 'البحث غير متاح حالياً.',
      sending: isEnglish ? 'Sending...' : 'جارٍ الإرسال...',
      openProfile: isEnglish ? 'Open profile' : 'فتح الملف',
      shareSubject: isEnglish ? 'Check out this content on Nawafeth' : 'شاهد هذا المحتوى على نوافذ',
      reportAction: isEnglish ? 'Report content' : 'الإبلاغ عن المحتوى',
      hideContentAction: isEnglish ? 'Hide this content' : 'حظر المحتوى',
      blockProviderAction: isEnglish ? 'Block provider' : 'حظر مزود الخدمة',
      optionsTitle: isEnglish ? 'Spotlight options' : 'خيارات اللمحة',
      optionsSubtitle: isEnglish ? 'Control what you see and report issues.' : 'تحكم بما يظهر لك وبلّغ عن المحتوى المخالف.',
      reportTitle: isEnglish ? 'Report content' : 'الإبلاغ عن المحتوى',
      reportSubtitle: isEnglish ? 'This report is sent to the content review queue for moderation.' : 'سيُرسل هذا البلاغ إلى مسار مراجعة المحتوى لاتخاذ الإجراء المناسب.',
      reportReasonLabel: isEnglish ? 'Reason' : 'سبب البلاغ',
      reportDetailsLabel: isEnglish ? 'Additional details' : 'تفاصيل إضافية',
      reportDetailsPlaceholder: isEnglish ? 'Add a short note for the moderation team' : 'اكتب ملاحظة قصيرة لفريق المراجعة',
      reportSubmit: isEnglish ? 'Send report' : 'إرسال البلاغ',
      reportSuccess: isEnglish ? 'Report submitted for content review.' : 'تم استلام البلاغ وإحالته إلى مراجعة المحتوى.',
      reportFailed: isEnglish ? 'Could not send the report right now.' : 'تعذر إرسال البلاغ حالياً.',
      blockContentTitle: isEnglish ? 'Hide this spotlight?' : 'حظر هذه اللمحة؟',
      blockContentBody: isEnglish ? 'This spotlight will stop appearing for you in the viewer and spotlight feeds.' : 'لن تظهر هذه اللمحة لك مرة أخرى داخل العارض أو خلاصات اللمحات.',
      blockContentConfirm: isEnglish ? 'Hide content' : 'حظر المحتوى',
      blockContentSuccess: isEnglish ? 'Content hidden from your account.' : 'تم حظر المحتوى من حسابك.',
      blockProviderTitle: isEnglish ? 'Block this provider?' : 'حظر هذا المزود؟',
      blockProviderBody: isEnglish ? 'This provider and their spotlights will no longer appear for you.' : 'لن يظهر هذا المزود ولمحاته لك بعد الآن.',
      blockProviderConfirm: isEnglish ? 'Block provider' : 'حظر المزود',
      blockProviderSuccess: isEnglish ? 'Provider blocked from your view.' : 'تم حظر المزود من واجهتك.',
      actionFailed: isEnglish ? 'The action could not be completed right now.' : 'تعذر تنفيذ الإجراء حالياً.',
      cancelAction: isEnglish ? 'Cancel' : 'إلغاء',
      reportReasonSpam: isEnglish ? 'Spam or misleading' : 'سبام أو تضليل',
      reportReasonInappropriate: isEnglish ? 'Inappropriate content' : 'محتوى غير مناسب',
      reportReasonViolence: isEnglish ? 'Violence or abuse' : 'عنف أو إساءة',
      reportReasonCopyright: isEnglish ? 'Copyright issue' : 'مخالفة حقوق',
      reportReasonOther: isEnglish ? 'Other' : 'سبب آخر',
    };
    return copy[key] || '';
  }

  function _closeTransientPanels() {
    _closeCommentActionsMenu();
    _closeCommentsSheet();
    _closeShareSheet();
    _closeOptionsMenu();
    _closeDialogSheet();
  }

  function _toggleOptionsMenu() {
    if (_optionsMenu) {
      _closeOptionsMenu();
      return;
    }
    const item = _items[_currentIndex];
    if (!item || !document.body) return;
    _closeShareSheet();
    _closeDialogSheet();

    const sheet = document.createElement('div');
    sheet.className = 'sv-options-menu';

    const backdrop = document.createElement('button');
    backdrop.className = 'sv-options-backdrop';
    backdrop.setAttribute('type', 'button');
    backdrop.setAttribute('aria-label', _shareCopy('optionsAction'));
    backdrop.addEventListener('click', () => _closeOptionsMenu());
    sheet.appendChild(backdrop);

    const card = document.createElement('div');
    card.className = 'sv-options-card';

    const title = document.createElement('div');
    title.className = 'sv-options-title';
    title.textContent = _shareCopy('optionsTitle');
    const subtitle = document.createElement('div');
    subtitle.className = 'sv-options-subtitle';
    subtitle.textContent = _shareCopy('optionsSubtitle');
    card.appendChild(title);
    card.appendChild(subtitle);

    card.appendChild(_buildOptionsItem('report', _shareCopy('reportAction'), _shareCopy('reportSubtitle'), () => _openReportSheet(item)));
    card.appendChild(_buildOptionsItem('hide', _shareCopy('hideContentAction'), _shareCopy('blockContentBody'), () => _openConfirmSheet({
      title: _shareCopy('blockContentTitle'),
      body: _shareCopy('blockContentBody'),
      confirmLabel: _shareCopy('blockContentConfirm'),
      destructive: false,
      onConfirm: () => _blockSpotlight(item),
    })));
    card.appendChild(_buildOptionsItem('block', _shareCopy('blockProviderAction'), _shareCopy('blockProviderBody'), () => _openConfirmSheet({
      title: _shareCopy('blockProviderTitle'),
      body: _shareCopy('blockProviderBody'),
      confirmLabel: _shareCopy('blockProviderConfirm'),
      destructive: true,
      onConfirm: () => _blockProvider(item),
    })));

    sheet.appendChild(card);
    document.body.appendChild(sheet);
    _optionsMenu = sheet;
    requestAnimationFrame(() => sheet.classList.add('is-visible'));
  }

  function _buildOptionsItem(kind, title, subtitle, onTap) {
    const button = document.createElement('button');
    button.className = 'sv-options-item';
    button.setAttribute('type', 'button');
    button.setAttribute('data-kind', kind);
    button.addEventListener('click', () => {
      _closeOptionsMenu();
      onTap();
    });

    const icon = document.createElement('span');
    icon.className = 'sv-options-item-icon';
    const icons = {
      report: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none"><path d="M12 9v4" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><path d="M12 17h.01" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><path d="M10.29 3.86 1.82 18a2 2 0 0 0 1.72 3h16.92a2 2 0 0 0 1.72-3L13.71 3.86a2 2 0 0 0-3.42 0z" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/></svg>',
      hide: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none"><path d="M3 3l18 18" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><path d="M10.58 10.58A2 2 0 0 0 13.41 13.4" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><path d="M9.88 5.09A9.77 9.77 0 0 1 12 4.8c5.45 0 9.27 4.69 10.39 6.2a1.3 1.3 0 0 1 0 1.6 19.6 19.6 0 0 1-3.19 3.39" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><path d="M6.61 6.61A19.67 19.67 0 0 0 1.61 11a1.3 1.3 0 0 0 0 1.6C2.73 14.11 6.55 18.8 12 18.8c1.5 0 2.89-.31 4.15-.84" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>',
      block: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="9" stroke="currentColor" stroke-width="2"/><path d="M7 17 17 7" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>',
    };
    icon.innerHTML = icons[kind] || '';
    button.appendChild(icon);

    const text = document.createElement('span');
    text.className = 'sv-options-item-text';
    const titleEl = document.createElement('strong');
    titleEl.textContent = title;
    const subtitleEl = document.createElement('small');
    subtitleEl.textContent = subtitle;
    text.appendChild(titleEl);
    text.appendChild(subtitleEl);
    button.appendChild(text);
    return button;
  }

  function _openReportSheet(item) {
    if (!_isAuthenticated()) {
      _redirectToLogin();
      return;
    }
    _closeDialogSheet();
    const sheet = document.createElement('div');
    sheet.className = 'sv-dialog-sheet';
    const backdrop = document.createElement('button');
    backdrop.className = 'sv-dialog-backdrop';
    backdrop.setAttribute('type', 'button');
    backdrop.addEventListener('click', () => _closeDialogSheet());
    sheet.appendChild(backdrop);

    const card = document.createElement('div');
    card.className = 'sv-dialog-card';

    const title = document.createElement('h3');
    title.className = 'sv-dialog-title';
    title.textContent = _shareCopy('reportTitle');
    const subtitle = document.createElement('p');
    subtitle.className = 'sv-dialog-subtitle';
    subtitle.textContent = _shareCopy('reportSubtitle');
    card.appendChild(title);
    card.appendChild(subtitle);

    const label = document.createElement('label');
    label.className = 'sv-dialog-label';
    label.textContent = _shareCopy('reportReasonLabel');
    const select = document.createElement('select');
    select.className = 'sv-dialog-select';
    [
      _shareCopy('reportReasonInappropriate'),
      _shareCopy('reportReasonSpam'),
      _shareCopy('reportReasonViolence'),
      _shareCopy('reportReasonCopyright'),
      _shareCopy('reportReasonOther'),
    ].forEach((reason) => {
      const option = document.createElement('option');
      option.value = reason;
      option.textContent = reason;
      select.appendChild(option);
    });
    card.appendChild(label);
    card.appendChild(select);

    const detailsLabel = document.createElement('label');
    detailsLabel.className = 'sv-dialog-label';
    detailsLabel.textContent = _shareCopy('reportDetailsLabel');
    const textarea = document.createElement('textarea');
    textarea.className = 'sv-dialog-textarea';
    textarea.placeholder = _shareCopy('reportDetailsPlaceholder');
    textarea.maxLength = 500;
    card.appendChild(detailsLabel);
    card.appendChild(textarea);

    const actions = document.createElement('div');
    actions.className = 'sv-dialog-actions';
    const cancelBtn = document.createElement('button');
    cancelBtn.className = 'sv-dialog-btn is-secondary';
    cancelBtn.setAttribute('type', 'button');
    cancelBtn.textContent = _shareCopy('cancelAction');
    cancelBtn.addEventListener('click', () => _closeDialogSheet());
    const submitBtn = document.createElement('button');
    submitBtn.className = 'sv-dialog-btn is-primary';
    submitBtn.setAttribute('type', 'button');
    submitBtn.textContent = _shareCopy('reportSubmit');
    submitBtn.addEventListener('click', () => _submitSpotlightReport(item, select.value, textarea.value));
    actions.appendChild(cancelBtn);
    actions.appendChild(submitBtn);
    card.appendChild(actions);

    sheet.appendChild(card);
    document.body.appendChild(sheet);
    _dialogSheet = sheet;
    requestAnimationFrame(() => sheet.classList.add('is-visible'));
  }

  function _openConfirmSheet(options) {
    if (!_isAuthenticated()) {
      _redirectToLogin();
      return;
    }
    _closeDialogSheet();
    const sheet = document.createElement('div');
    sheet.className = 'sv-dialog-sheet';
    const backdrop = document.createElement('button');
    backdrop.className = 'sv-dialog-backdrop';
    backdrop.setAttribute('type', 'button');
    backdrop.addEventListener('click', () => _closeDialogSheet());
    sheet.appendChild(backdrop);

    const card = document.createElement('div');
    card.className = 'sv-dialog-card';
    const title = document.createElement('h3');
    title.className = 'sv-dialog-title';
    title.textContent = options.title || '';
    const body = document.createElement('p');
    body.className = 'sv-dialog-subtitle';
    body.textContent = options.body || '';
    card.appendChild(title);
    card.appendChild(body);

    const actions = document.createElement('div');
    actions.className = 'sv-dialog-actions';
    const cancelBtn = document.createElement('button');
    cancelBtn.className = 'sv-dialog-btn is-secondary';
    cancelBtn.setAttribute('type', 'button');
    cancelBtn.textContent = _shareCopy('cancelAction');
    cancelBtn.addEventListener('click', () => _closeDialogSheet());
    const confirmBtn = document.createElement('button');
    confirmBtn.className = 'sv-dialog-btn ' + (options.destructive ? 'is-danger' : 'is-primary');
    confirmBtn.setAttribute('type', 'button');
    confirmBtn.textContent = options.confirmLabel || _shareCopy('cancelAction');
    confirmBtn.addEventListener('click', async () => {
      try {
        await options.onConfirm();
      } catch (_) {
        _showToast(_shareCopy('actionFailed'));
      }
    });
    actions.appendChild(cancelBtn);
    actions.appendChild(confirmBtn);
    card.appendChild(actions);

    sheet.appendChild(card);
    document.body.appendChild(sheet);
    _dialogSheet = sheet;
    requestAnimationFrame(() => sheet.classList.add('is-visible'));
  }

  async function _submitSpotlightReport(item, reason, details) {
    if (_reportSubmitInFlight) return;
    _reportSubmitInFlight = true;
    try {
      const response = await ApiClient.request(
        _withMode(_contentDetailPath(item, 'report/'), _activeMode(item)),
        {
          method: 'POST',
          body: {
            reason: String(reason || '').trim() || _shareCopy('reportReasonOther'),
            details: String(details || '').trim(),
            surface: _contentSource(item) === 'portfolio' ? 'mobile_web.portfolio_viewer' : 'mobile_web.spotlight_viewer',
          },
        }
      );
      if (!response || !response.ok) throw new Error('report_failed');
      _showToast(_shareCopy('reportSuccess'));
      _closeDialogSheet();
    } catch (_) {
      _showToast(_shareCopy('reportFailed'));
    } finally {
      _reportSubmitInFlight = false;
    }
  }

  async function _blockSpotlight(item) {
    const response = await ApiClient.request(
      _withMode(_contentDetailPath(item, 'hide/'), _activeMode(item)),
      {
        method: 'POST',
      }
    );
    if (!response || !response.ok) throw new Error('block_spotlight_failed');
    _closeDialogSheet();
    _showToast(_shareCopy('blockContentSuccess'));
    _removeItemsMatching((entry) => Number(entry && entry.id) === Number(item.id));
  }

  async function _blockProvider(item) {
    const providerId = Number(item && item.provider_id);
    if (!providerId) throw new Error('provider_missing');
    const response = await ApiClient.request(
      _withMode('/api/providers/' + encodeURIComponent(String(providerId)) + '/block/', _activeMode(item)),
      {
        method: 'POST',
      }
    );
    if (!response || !response.ok) throw new Error('block_provider_failed');
    _closeDialogSheet();
    _showToast(_shareCopy('blockProviderSuccess'));
    _removeItemsMatching((entry) => Number(entry && entry.provider_id) === providerId);
  }

  function _removeItemsMatching(predicate) {
    if (typeof predicate !== 'function') return;
    _closeCommentsSheet();
    const remaining = _items.filter((entry) => !predicate(entry));
    if (remaining.length === _items.length) return;
    _items = remaining;
    if (!_items.length) {
      close();
      return;
    }
    _currentIndex = Math.max(0, Math.min(_currentIndex, _items.length - 1));
    _renderCurrent();
  }

  function _toggleShareSheet(item) {
    if (_shareSheet) {
      _closeShareSheet();
      return;
    }
    _openShareSheet(item);
  }

  function _openShareSheet(item) {
    if (!item || !document.body) return;
    _closeShareSheet();

    const sheet = document.createElement('div');
    sheet.className = 'sv-share-sheet';

    const backdrop = document.createElement('button');
    backdrop.className = 'sv-share-backdrop';
    backdrop.setAttribute('type', 'button');
    backdrop.setAttribute('aria-label', _shareCopy('shareAction'));
    backdrop.addEventListener('click', () => _closeShareSheet());
    sheet.appendChild(backdrop);

    const card = document.createElement('div');
    card.className = 'sv-share-card';
    card.addEventListener('click', (event) => event.stopPropagation());

    const header = document.createElement('div');
    header.className = 'sv-share-header';

    const headerText = document.createElement('div');
    headerText.className = 'sv-share-header-text';
    const title = document.createElement('h3');
    title.className = 'sv-share-title';
    title.textContent = _shareCopy('shareTitle');
    const subtitle = document.createElement('p');
    subtitle.className = 'sv-share-subtitle';
    subtitle.textContent = _shareCopy('shareSubtitle');
    headerText.appendChild(title);
    headerText.appendChild(subtitle);

    const closeBtn = document.createElement('button');
    closeBtn.className = 'sv-share-close';
    closeBtn.setAttribute('type', 'button');
    closeBtn.setAttribute('aria-label', 'Close');
    closeBtn.innerHTML = '<svg width="20" height="20" viewBox="0 0 24 24" fill="none"><path d="M18 6L6 18M6 6l12 12" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>';
    closeBtn.addEventListener('click', () => _closeShareSheet());

    header.appendChild(headerText);
    header.appendChild(closeBtn);
    card.appendChild(header);

    const link = document.createElement('p');
    link.className = 'sv-share-link';
    link.textContent = _buildSpotlightShareUrl(item);
    card.appendChild(link);

    const actions = document.createElement('div');
    actions.className = 'sv-share-actions';
    actions.appendChild(_buildShareOption('inside', _shareCopy('shareInside'), () => _activateInternalShare(item)));
    actions.appendChild(_buildShareOption('whatsapp', _shareCopy('shareWhatsApp'), () => _shareToWhatsApp(item)));
    actions.appendChild(_buildShareOption('copy', _shareCopy('shareCopyLink'), () => _copySpotlightLink(item)));
    actions.appendChild(_buildShareOption('email', _shareCopy('shareEmail'), () => _shareByEmail(item)));
    card.appendChild(actions);

    const searchPanel = document.createElement('div');
    searchPanel.className = 'sv-share-search';
    searchPanel.id = 'sv-share-search';
    searchPanel.hidden = true;

    const searchInput = document.createElement('input');
    searchInput.className = 'sv-share-search-input';
    searchInput.id = 'sv-share-search-input';
    searchInput.type = 'search';
    searchInput.placeholder = _shareCopy('searchPlaceholder');
    searchInput.autocomplete = 'off';
    searchInput.spellcheck = false;

    const status = document.createElement('div');
    status.className = 'sv-share-search-status';
    status.id = 'sv-share-search-status';
    status.textContent = _shareCopy('searchHint');

    const results = document.createElement('div');
    results.className = 'sv-share-results';
    results.id = 'sv-share-results';

    searchInput.addEventListener('input', () => _queueRecipientSearch(item));
    searchPanel.appendChild(searchInput);
    searchPanel.appendChild(status);
    searchPanel.appendChild(results);
    card.appendChild(searchPanel);

    sheet.appendChild(card);
    document.body.appendChild(sheet);
    _shareSheet = sheet;
    requestAnimationFrame(() => sheet.classList.add('is-visible'));
  }

  function _buildShareOption(kind, label, onTap) {
    const option = document.createElement('button');
    option.className = 'sv-share-option';
    option.setAttribute('type', 'button');
    option.setAttribute('data-kind', kind);
    option.addEventListener('click', onTap);

    const icon = document.createElement('span');
    icon.className = 'sv-share-option-icon';
    const icons = {
      inside: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none"><path d="M7 8h10M7 12h7M7 16h10" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><path d="M5 4h14a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H9l-4 3v-3H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2z" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/></svg>',
      whatsapp: '<svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><path d="M20.52 3.48A11.86 11.86 0 0 0 12.07 0C5.55 0 .25 5.3.25 11.82c0 2.08.54 4.12 1.57 5.92L0 24l6.44-1.69a11.81 11.81 0 0 0 5.63 1.43h.01c6.52 0 11.82-5.3 11.82-11.82 0-3.16-1.23-6.13-3.38-8.44zm-8.45 18.26h-.01a9.9 9.9 0 0 1-5.05-1.39l-.36-.21-3.82 1 1.02-3.72-.23-.38a9.86 9.86 0 0 1-1.52-5.22C2.1 6.8 6.15 2.75 11.17 2.75c2.65 0 5.13 1.03 6.99 2.9a9.8 9.8 0 0 1 2.89 6.98c0 5.02-4.06 9.11-9.08 9.11zm4.99-6.78c-.27-.13-1.62-.8-1.87-.9-.25-.09-.43-.13-.61.13-.18.27-.7.9-.86 1.09-.16.18-.31.2-.58.07-.27-.13-1.12-.41-2.13-1.31-.79-.7-1.32-1.57-1.47-1.84-.16-.27-.02-.42.11-.55.12-.12.27-.31.4-.47.13-.16.18-.27.27-.45.09-.18.05-.34-.02-.47-.07-.13-.61-1.48-.84-2.03-.22-.53-.44-.46-.61-.47h-.52c-.18 0-.47.07-.72.34-.25.27-.95.93-.95 2.27s.98 2.64 1.12 2.82c.13.18 1.92 2.94 4.64 4.13.65.28 1.16.45 1.55.57.65.21 1.24.18 1.7.11.52-.08 1.62-.66 1.84-1.3.23-.65.23-1.2.16-1.31-.07-.11-.25-.18-.52-.31z"/></svg>',
      copy: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none"><rect x="9" y="9" width="11" height="11" rx="2" stroke="currentColor" stroke-width="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>',
      email: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none"><rect x="3" y="5" width="18" height="14" rx="2" stroke="currentColor" stroke-width="2"/><path d="m4 7 8 6 8-6" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    };
    icon.innerHTML = icons[kind] || '';
    option.appendChild(icon);

    const text = document.createElement('span');
    text.className = 'sv-share-option-label';
    text.textContent = label;
    option.appendChild(text);
    return option;
  }

  function _activateInternalShare(item) {
    if (!_isAuthenticated()) {
      _redirectToLogin();
      return;
    }
    const panel = document.getElementById('sv-share-search');
    const input = document.getElementById('sv-share-search-input');
    const status = document.getElementById('sv-share-search-status');
    if (!panel || !input || !status) return;
    panel.hidden = false;
    status.textContent = _shareCopy('searchHint');
    input.focus();
    _queueRecipientSearch(item);
  }

  function _queueRecipientSearch(item) {
    const input = document.getElementById('sv-share-search-input');
    const status = document.getElementById('sv-share-search-status');
    const results = document.getElementById('sv-share-results');
    if (!input || !status || !results) return;
    const query = String(input.value || '').trim();
    if (_shareSearchTimer) {
      window.clearTimeout(_shareSearchTimer);
      _shareSearchTimer = null;
    }
    if (query.length < 2) {
      results.innerHTML = '';
      status.textContent = _shareCopy('searchHint');
      return;
    }
    status.textContent = _shareCopy('searchLoading');
    const token = ++_shareSearchToken;
    _shareSearchTimer = window.setTimeout(() => {
      _performRecipientSearch(item, query, token);
    }, 240);
  }

  async function _performRecipientSearch(item, query, token) {
    const status = document.getElementById('sv-share-search-status');
    const results = document.getElementById('sv-share-results');
    if (!status || !results) return;
    try {
      const res = await ApiClient.get(_withMode('/api/messaging/direct/recipients/search/?q=' + encodeURIComponent(query), _options.modeContext || 'client'));
      if (token !== _shareSearchToken) return;
      if (!res || !res.ok) throw new Error('search_failed');
      const rows = Array.isArray(res.data) ? res.data : [];
      results.innerHTML = '';
      if (!rows.length) {
        status.textContent = _shareCopy('searchEmpty');
        return;
      }
      status.textContent = '';
      rows.forEach((recipient) => {
        results.appendChild(_buildRecipientRow(item, recipient));
      });
    } catch (_) {
      if (token !== _shareSearchToken) return;
      results.innerHTML = '';
      status.textContent = _shareCopy('searchError');
    }
  }

  function _buildRecipientRow(item, recipient) {
    const row = document.createElement('button');
    row.className = 'sv-share-recipient';
    row.setAttribute('type', 'button');
    row.addEventListener('click', () => _sendSpotlightToRecipient(item, recipient));

    const avatar = document.createElement('span');
    avatar.className = 'sv-share-recipient-avatar';
    const avatarUrl = _resolveUrl(recipient && recipient.profile_image);
    if (avatarUrl) {
      const img = document.createElement('img');
      img.src = avatarUrl;
      img.alt = recipient.name || recipient.username || _shareCopy('openProfile');
      avatar.appendChild(img);
    } else {
      avatar.textContent = _getProviderInitial(recipient && (recipient.name || recipient.username || 'ن'));
    }
    row.appendChild(avatar);

    const text = document.createElement('span');
    text.className = 'sv-share-recipient-text';
    const name = document.createElement('strong');
    name.textContent = recipient.name || recipient.username || '';
    const meta = document.createElement('small');
    meta.textContent = recipient.username ? ('@' + recipient.username) : (recipient.phone || '');
    text.appendChild(name);
    text.appendChild(meta);
    row.appendChild(text);
    return row;
  }

  async function _sendSpotlightToRecipient(item, recipient) {
    if (!recipient || !recipient.id || _shareSendInFlight) return;
    const status = document.getElementById('sv-share-search-status');
    const modeContext = String(item?.mode_context || _options.modeContext || 'client');
    _shareSendInFlight = true;
    if (status) status.textContent = _shareCopy('sending');
    try {
      const createThreadRes = await ApiClient.request(
        _withMode('/api/messaging/direct/thread/', modeContext),
        {
          method: 'POST',
          body: { recipient_user_id: recipient.id },
        }
      );
      if (!createThreadRes || !createThreadRes.ok || !createThreadRes.data || !createThreadRes.data.id) {
        throw new Error('thread_failed');
      }
      const threadId = createThreadRes.data.id;
      const sendRes = await ApiClient.request(
        _withMode('/api/messaging/direct/thread/' + encodeURIComponent(String(threadId)) + '/messages/send/', modeContext),
        {
          method: 'POST',
          body: { body: _buildSpotlightShareMessage(item) },
        }
      );
      if (!sendRes || !sendRes.ok) throw new Error('send_failed');
      await _trackSpotlightShare(item, 'other');
      _showToast(_shareCopy('shareSent'));
      _closeShareSheet();
      close();
      window.location.href = '/chat/' + encodeURIComponent(String(threadId)) + '/?mode=' + encodeURIComponent(modeContext);
    } catch (_) {
      if (status) status.textContent = _shareCopy('shareSendFailed');
    } finally {
      _shareSendInFlight = false;
    }
  }

  async function _shareToWhatsApp(item) {
    const url = 'https://wa.me/?text=' + encodeURIComponent(_buildSpotlightShareMessage(item));
    await _trackSpotlightShare(item, 'whatsapp');
    window.open(url, '_blank', 'noopener');
    _closeShareSheet();
  }

  async function _copySpotlightLink(item) {
    const copied = await _copyToClipboard(_buildSpotlightShareUrl(item));
    if (copied) {
      await _trackSpotlightShare(item, 'copy_link');
      _showToast(_shareCopy('shareLinkCopied'));
      _closeShareSheet();
      return;
    }
    _showToast(_shareCopy('shareLinkFailed'));
  }

  async function _shareByEmail(item) {
    await _trackSpotlightShare(item, 'other');
    const subject = _shareCopy('shareSubject');
    const body = _buildSpotlightShareMessage(item);
    window.location.href = 'mailto:?subject=' + encodeURIComponent(subject) + '&body=' + encodeURIComponent(body);
    _closeShareSheet();
  }

  async function _trackSpotlightShare(item, channel) {
    const providerId = Number(item && item.provider_id);
    const contentId = Number(item && item.id);
    if (!providerId || !contentId || !window.ApiClient || typeof ApiClient.request !== 'function') return;
    try {
      const source = _contentSource(item);
      await ApiClient.request('/api/providers/' + encodeURIComponent(String(providerId)) + '/share/', {
        method: 'POST',
        body: {
          content_type: source === 'portfolio' ? 'portfolio' : 'spotlight',
          content_id: contentId,
          channel: channel || 'other',
        },
      });
    } catch (_) {
      // no-op
    }
  }

  function _buildSpotlightShareUrl(item) {
    const contentId = Number(item && item.id);
    const queryKey = _contentSource(item) === 'portfolio' ? 'portfolio' : 'spotlight';
    const path = '/?' + queryKey + '=' + encodeURIComponent(String(contentId || 0));
    return window.location.origin ? (window.location.origin + path) : path;
  }

  function _buildSpotlightShareMessage(item) {
    const providerName = _getProviderDisplayName(item) || 'نوافذ';
    const caption = String(item && item.caption || '').trim();
    const lines = [];
    lines.push(_shareCopy('shareSubject'));
    lines.push(providerName);
    if (caption) lines.push(caption);
    lines.push(_buildSpotlightShareUrl(item));
    return lines.join('\n');
  }

  async function _copyToClipboard(value) {
    const text = String(value || '');
    if (!text) return false;
    if (navigator.clipboard && typeof navigator.clipboard.writeText === 'function') {
      try {
        await navigator.clipboard.writeText(text);
        return true;
      } catch (_) {
        // continue to fallback
      }
    }
    const textarea = document.createElement('textarea');
    textarea.value = text;
    textarea.setAttribute('readonly', 'readonly');
    textarea.style.position = 'fixed';
    textarea.style.opacity = '0';
    textarea.style.pointerEvents = 'none';
    document.body.appendChild(textarea);
    textarea.focus();
    textarea.select();
    let copied = false;
    try {
      copied = document.execCommand('copy');
    } catch (_) {
      copied = false;
    }
    textarea.remove();
    return copied;
  }

  function _closeShareSheet() {
    if (_shareSearchTimer) {
      window.clearTimeout(_shareSearchTimer);
      _shareSearchTimer = null;
    }
    if (_shareSheet) {
      _shareSheet.remove();
      _shareSheet = null;
    }
  }

  function _closeCommentsSheet() {
    _closeCommentActionsMenu();
    _commentReplyTarget = null;
    if (_commentsSheet) {
      _commentsSheet.remove();
      _commentsSheet = null;
    }
  }

  function _closeOptionsMenu() {
    if (_optionsMenu) {
      _optionsMenu.remove();
      _optionsMenu = null;
    }
  }

  function _closeDialogSheet() {
    if (_dialogSheet) {
      _dialogSheet.remove();
      _dialogSheet = null;
    }
  }

  function _emitEngagementUpdate(item) {
    if (!item || typeof window === 'undefined') return;
    window.dispatchEvent(new CustomEvent(_options.eventName || 'nw:spotlight-engagement-update', {
      detail: {
        id: item.id,
        provider_id: item.provider_id,
        likes_count: Number(item.likes_count) || 0,
        saves_count: Number(item.saves_count) || 0,
        comments_count: Number(item.comments_count) || 0,
        is_liked: !!item.is_liked,
        is_saved: !!item.is_saved,
      },
    }));
  }

  /* ----------------------------------------------------------
     NAVIGATION: swipe / wheel / keyboard
  ---------------------------------------------------------- */
  async function _goNext() {
    if (_navInFlight) return;
    _closeCommentsSheet();
    if (_currentIndex < _items.length - 1) {
      _cancelSpeedHold({ restoreRate: true });
      _navDirection = 1;
      _currentIndex = _wrapIndex(_currentIndex + 1);
      _renderCurrent();
      return;
    }

    _navInFlight = true;
    try {
      const appended = await _appendRandomSpotlights();
      if (appended && _currentIndex < _items.length - 1) {
        _cancelSpeedHold({ restoreRate: true });
        _navDirection = 1;
        _currentIndex += 1;
        _renderCurrent();
        return;
      }

      if (_items.length <= 1) return;
      _cancelSpeedHold({ restoreRate: true });
      _navDirection = 1;
      _currentIndex = 0;
      _renderCurrent();
    } finally {
      _navInFlight = false;
    }
  }

  function _goPrev() {
    if (_navInFlight) return;
    _closeCommentsSheet();
    _cancelSpeedHold({ restoreRate: true });
    _navDirection = -1;
    _currentIndex = _wrapIndex(_currentIndex - 1);
    _renderCurrent();
  }

  function _goToIndex(index) {
    if (_navInFlight) return;
    if (_items.length <= 1) return;
    _closeCommentsSheet();
    const nextIndex = _wrapIndex(index);
    if (nextIndex === _currentIndex) return;
    _cancelSpeedHold({ restoreRate: true });
    if (index < 0) _navDirection = -1;
    else if (index >= _items.length) _navDirection = 1;
    else _navDirection = nextIndex > _currentIndex ? 1 : -1;
    _currentIndex = nextIndex;
    _renderCurrent();
  }

  function _onTouchStart(e) {
    _touchStartX = e.touches[0].clientX;
    _touchStartY = e.touches[0].clientY;
    _touchStartTs = Date.now();
    _swiping = true;
    _beginSpeedHold(e.target);
  }

  function _onTouchMove(e) {
    if (!_swiping) return;
    const touch = e.touches[0];
    if (!touch) return;
    const dx = Math.abs(touch.clientX - _touchStartX);
    const dy = Math.abs(touch.clientY - _touchStartY);
    if (dx > 10 || dy > 10) {
      _cancelSpeedHold({ restoreRate: false });
    }
  }

  function _onTouchEnd(e) {
    if (!_swiping) return;
    _swiping = false;
    const touch = e.changedTouches[0];
    const dx = touch.clientX - _touchStartX;
    const dy = touch.clientY - _touchStartY;
    const elapsed = Date.now() - _touchStartTs;
    const absDx = Math.abs(dx);
    const absDy = Math.abs(dy);
    const isVerticalSwipe = absDy > absDx * 1.15;
    const isQuickFlick = elapsed < 240 && absDy > 26;
    const isCommittedSwipe = absDy > 54;
    _cancelSpeedHold({ restoreRate: true });
    if (isVerticalSwipe && (isQuickFlick || isCommittedSwipe)) {
      if (dy < 0) _goNext();   // swipe up → next
      else _goPrev();          // swipe down → prev
    }
  }

  function _onWheel(e) {
    e.preventDefault();
    if (e.deltaY > 30) _goNext();
    else if (e.deltaY < -30) _goPrev();
  }

  function _onKeyDown(e) {
    if (!_overlay) { document.removeEventListener('keydown', _onKeyDown); return; }
    if (e.key === 'Escape') close();
    else if (e.key === 'ArrowDown' || e.key === 'ArrowRight') _goNext();
    else if (e.key === 'ArrowUp' || e.key === 'ArrowLeft') _goPrev();
  }

  /* ----------------------------------------------------------
     HELPERS
  ---------------------------------------------------------- */
  function _resolveUrl(path) {
    if (!path) return '';
    return ApiClient.mediaUrl(path);
  }

  function _isAuthenticated() {
    if (window.Auth && typeof window.Auth.isLoggedIn === 'function') {
      return !!window.Auth.isLoggedIn();
    }
    try {
      return !!(
        (window.sessionStorage && (window.sessionStorage.getItem('nw_access_token') || window.sessionStorage.getItem('nw_refresh_token')))
        || (window.localStorage && (window.localStorage.getItem('nw_access_token') || window.localStorage.getItem('nw_refresh_token')))
      );
    } catch (_) {
      return false;
    }
  }

  function _redirectToLogin() {
    const next = encodeURIComponent(window.location.pathname + window.location.search);
    window.location.href = '/login/?next=' + next;
  }

  function _contentSource(item) {
    return String(item?.source || _options.source || 'spotlight').trim().toLowerCase();
  }

  function _contentApiBase(item) {
    return _contentSource(item) === 'portfolio' ? '/api/providers/portfolio/' : '/api/providers/spotlights/';
  }

  function _contentDetailPath(item, suffix) {
    return _contentApiBase(item) + encodeURIComponent(String(item?.id || 0)) + '/' + suffix;
  }

  function _buildReactionEndpoint(item, action, wasActive) {
    const endpoint = _contentApiBase(item) + encodeURIComponent(String(item.id)) + '/' + (wasActive ? 'un' + action : action) + '/';
    return _withMode(endpoint, _activeMode(item));
  }

  function _activeMode(item) {
    try {
      if (typeof Auth !== 'undefined' && Auth && typeof Auth.getActiveAccountMode === 'function') {
        const mode = String(Auth.getActiveAccountMode() || '').trim().toLowerCase();
        if (mode === 'provider' || mode === 'client') return mode;
      }
    } catch (_) {}
    const fallback = String(item?.mode_context || _options.modeContext || 'client').trim().toLowerCase();
    return fallback === 'provider' ? 'provider' : 'client';
  }

  function _withMode(path, mode) {
    const sep = path.includes('?') ? '&' : '?';
    return path + sep + 'mode=' + encodeURIComponent(mode || 'client');
  }

  function _isVideo(item) {
    const fileType = String(item?.file_type || '').toLowerCase();
    if (fileType === 'video') return true;

    const mediaType = String(item?.media_type || '').toLowerCase();
    if (mediaType.startsWith('video')) return true;

    const url = (item.file_url || '').toLowerCase();
    return url.endsWith('.mp4') || url.endsWith('.mov') || url.endsWith('.webm')
      || url.includes('.mp4?') || url.includes('.mov?') || url.includes('.webm?');
  }

  function _resolveMediaLabel(item) {
    const explicit = String(item?.media_label || item?.title || item?.name || item?.desc || '').trim();
    if (explicit && explicit !== 'بدون وصف') return explicit;

    const caption = String(item?.caption || '').trim();
    if (caption) return caption;

    const rawPath = String(item?.file_url || item?.thumbnail_url || '').split('?')[0];
    const tail = rawPath.split('/').pop() || '';
    if (tail) {
      try {
        return decodeURIComponent(tail);
      } catch (_) {
        return tail;
      }
    }

    return '';
  }

  function _getProviderDisplayName(item) {
    const candidates = [
      item?.provider_display_name,
      item?.provider_name,
      item?.display_name,
      item?.name,
    ];
    for (const candidate of candidates) {
      const value = String(candidate || '').trim();
      if (value) return value;
    }
    return '';
  }

  function _getProviderAvatarUrl(item) {
    const candidates = [
      item?.provider_profile_image,
      item?.profile_image,
      item?.provider_avatar,
    ];
    for (const candidate of candidates) {
      const value = String(candidate || '').trim();
      if (value) return _resolveUrl(value);
    }
    return '';
  }

  function _getProviderInitial(name) {
    const value = String(name || '').trim();
    return value ? value.charAt(0) : 'ن';
  }

  function _formatCount(count) {
    if (!count || count < 1) return '0';
    if (count < 1000) return String(count);
    if (count < 10000) {
      const k = count / 1000;
      return (k === Math.floor(k)) ? Math.floor(k) + 'K' : k.toFixed(1) + 'K';
    }
    return Math.floor(count / 1000) + 'K';
  }

  function _getModeLabel() {
    return _activeMode() === 'provider' ? 'مزود' : 'عميل';
  }

  function _showToast(message) {
    if (!message || typeof document === 'undefined') return;
    const existing = document.getElementById('sv-toast');
    if (existing) existing.remove();

    const toast = document.createElement('div');
    toast.className = 'sv-toast';
    toast.id = 'sv-toast';
    toast.textContent = message;
    document.body.appendChild(toast);
    requestAnimationFrame(() => toast.classList.add('show'));
    window.setTimeout(() => {
      toast.classList.remove('show');
      window.setTimeout(() => toast.remove(), 180);
    }, 1800);
  }

  function _togglePlayback(video, toggleBtn) {
    if (!video) return;
    if (video.paused) {
      const playAttempt = video.play();
      if (playAttempt && typeof playAttempt.catch === 'function') playAttempt.catch(() => {});
      if (toggleBtn) toggleBtn.classList.add('hidden');
      return;
    }
    video.pause();
    if (toggleBtn) toggleBtn.classList.remove('hidden');
  }

  function _bindTikTokVideoGestures(frame, video, toggleBtn) {
    frame.addEventListener('click', () => {
      if (_skipNextPlaybackToggle) {
        _skipNextPlaybackToggle = false;
        return;
      }
      _togglePlayback(video, toggleBtn);
    });

    const cancelSpeed = () => _cancelSpeedHold({ restoreRate: true });
    frame.addEventListener('pointerup', cancelSpeed);
    frame.addEventListener('pointercancel', cancelSpeed);
    frame.addEventListener('pointerleave', cancelSpeed);
  }

  function _beginSpeedHold(target) {
    if (!_isTikTokMode() || !_currentVideo) return;
    if (target && target.closest && target.closest('.sv-close, .sv-menu-btn, .sv-mute-btn, .sv-side, .sv-action, .sv-side-avatar, .sv-options-menu, .sv-dialog-sheet, .sv-share-sheet, .sv-comments-sheet')) return;
    _cancelSpeedHold({ restoreRate: false });
    _speedHoldTimer = window.setTimeout(() => {
      if (!_currentVideo || _currentVideo.paused) return;
      _speedBoostActive = true;
      _skipNextPlaybackToggle = true;
      _currentVideo.playbackRate = 2;
      _setSpeedPillVisible(true);
    }, 220);
  }

  function _cancelSpeedHold(options = {}) {
    if (_speedHoldTimer) {
      window.clearTimeout(_speedHoldTimer);
      _speedHoldTimer = null;
    }
    if (options.restoreRate && _currentVideo) {
      _currentVideo.playbackRate = 1;
    }
    if (_speedBoostActive) {
      _speedBoostActive = false;
      _setSpeedPillVisible(false);
    }
  }

  function _setSpeedPillVisible(visible) {
    const pill = document.getElementById('sv-speed-pill');
    if (!pill) return;
    pill.hidden = !visible;
    pill.classList.toggle('show', !!visible);
  }

  function _primeAdjacentVideos() {
    const keepUrls = new Set();
    if (_items.length <= 1) return;
    [_wrapIndex(_currentIndex - 1), _wrapIndex(_currentIndex + 1)].forEach((index) => {
      const item = _items[index];
      if (!_isVideo(item)) return;
      const url = _resolveUrl(item.file_url);
      if (!url) return;
      keepUrls.add(url);
      if (_preloadedVideoPool.has(url)) return;
      const probe = document.createElement('video');
      probe.preload = 'metadata';
      probe.muted = true;
      probe.playsInline = true;
      probe.src = url;
      probe.load();
      _preloadedVideoPool.set(url, probe);
    });

    Array.from(_preloadedVideoPool.keys()).forEach((url) => {
      if (!keepUrls.has(url)) {
        const probe = _preloadedVideoPool.get(url);
        if (probe) {
          try {
            probe.pause();
            probe.removeAttribute('src');
            probe.load();
          } catch (_) {
            // no-op
          }
        }
        _preloadedVideoPool.delete(url);
      }
    });
  }

  function _releasePreloadedVideos() {
    _preloadedVideoPool.forEach((probe) => {
      try {
        probe.pause();
        probe.removeAttribute('src');
        probe.load();
      } catch (_) {
        // no-op
      }
    });
    _preloadedVideoPool.clear();
  }

  function _soundIcon(isMuted) {
    if (isMuted) {
      return '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"></polygon><line x1="23" y1="9" x2="17" y2="15"></line><line x1="17" y1="9" x2="23" y2="15"></line></svg>';
    }
    return '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"></polygon><path d="M15.54 8.46a5 5 0 0 1 0 7.07"></path><path d="M19.07 4.93a10 10 0 0 1 0 14.14"></path></svg>';
  }

  return { open, close };
})();
