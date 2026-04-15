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
  let _touchStartY = 0;
  let _swiping = false;
  let _currentVideo = null;

  /* ----------------------------------------------------------
     PUBLIC: open viewer
  ---------------------------------------------------------- */
  function open(items, startIndex, options) {
    if (!items || !items.length) return;
    _items = items;
    _currentIndex = Math.max(0, Math.min(startIndex || 0, items.length - 1));
    _options = options || {};
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
    _items = [];
    _currentIndex = 0;
    _options = {};
  }

  /* ----------------------------------------------------------
     BUILD: Overlay shell
  ---------------------------------------------------------- */
  function _buildOverlay() {
    if (_overlay) _overlay.remove();

    _overlay = document.createElement('div');
    _overlay.className = 'sv-overlay';
    if (_options && _options.immersive) _overlay.classList.add('sv-immersive');
    _overlay.setAttribute('role', 'dialog');
    _overlay.setAttribute('aria-label', 'عارض اللمحات');

    // Close button (top-left for RTL)
    const closeBtn = document.createElement('button');
    closeBtn.className = 'sv-close';
    closeBtn.setAttribute('aria-label', 'إغلاق');
    closeBtn.innerHTML = '<svg width="22" height="22" viewBox="0 0 24 24" fill="white"><path d="M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z"/></svg>';
    closeBtn.addEventListener('click', close);

    // Badge "لمحة" (top-right)
    const badge = document.createElement('div');
    badge.className = 'sv-badge';
    badge.textContent = _options.label || 'لمحة';

    const modeBadge = document.createElement('div');
    modeBadge.className = 'sv-mode-badge';
    modeBadge.id = 'sv-mode-badge';
    modeBadge.textContent = 'وضع التفاعل: ' + _getModeLabel();

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
    prevBtn.addEventListener('click', () => _goToIndex(_currentIndex - 1));

    const nextBtn = document.createElement('button');
    nextBtn.className = 'sv-nav sv-nav-next';
    nextBtn.id = 'sv-nav-next';
    nextBtn.setAttribute('type', 'button');
    nextBtn.setAttribute('aria-label', 'العنصر التالي');
    nextBtn.innerHTML = '<svg width="24" height="24" viewBox="0 0 24 24" fill="none"><path d="M9 6L15 12L9 18" stroke="white" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>';
    nextBtn.addEventListener('click', () => _goToIndex(_currentIndex + 1));

    // Media container
    const media = document.createElement('div');
    media.className = 'sv-media';
    media.id = 'sv-media';

    const thumbs = document.createElement('div');
    thumbs.className = 'sv-thumbs';
    thumbs.id = 'sv-thumbs';

    // Bottom info
    const bottom = document.createElement('div');
    bottom.className = 'sv-bottom';
    bottom.id = 'sv-bottom';

    // Side actions
    const side = document.createElement('div');
    side.className = 'sv-side';
    side.id = 'sv-side';

    _overlay.appendChild(closeBtn);
    _overlay.appendChild(badge);
    _overlay.appendChild(modeBadge);
    _overlay.appendChild(counter);
    _overlay.appendChild(prevBtn);
    _overlay.appendChild(nextBtn);
    _overlay.appendChild(media);
    _overlay.appendChild(thumbs);
    _overlay.appendChild(bottom);
    _overlay.appendChild(side);

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
    if (counter) counter.textContent = (_currentIndex + 1) + ' / ' + _items.length;

    const prevBtn = document.getElementById('sv-nav-prev');
    if (prevBtn) {
      prevBtn.disabled = _currentIndex <= 0;
      prevBtn.hidden = _items.length <= 1;
    }
    const nextBtn = document.getElementById('sv-nav-next');
    if (nextBtn) {
      nextBtn.disabled = _currentIndex >= (_items.length - 1);
      nextBtn.hidden = _items.length <= 1;
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
      mediaEl.appendChild(frame);

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

        frame.addEventListener('click', () => _togglePlayback(video, playToggle));
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
        item.is_liked ? 'heart-filled' : 'heart-outline',
        item.is_liked ? '#ff4757' : '#fff',
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
    }
  }

  /* ----------------------------------------------------------
     SIDE ACTION BUTTON
  ---------------------------------------------------------- */
  function _buildSideAction(iconType, color, label, onTap) {
    const wrap = document.createElement('div');
    wrap.className = 'sv-action';
    wrap.addEventListener('click', onTap);

    const iconSvg = document.createElement('div');
    iconSvg.className = 'sv-action-icon';

    const svgPaths = {
      'heart-filled': '<path d="M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z"/>',
      'heart-outline': '<path d="M16.5 3c-1.74 0-3.41.81-4.5 2.09C10.91 3.81 9.24 3 7.5 3 4.42 3 2 5.42 2 8.5c0 3.78 3.4 6.86 8.55 11.54L12 21.35l1.45-1.32C18.6 15.36 22 12.28 22 8.5 22 5.42 19.58 3 16.5 3zm-4.4 15.55l-.1.1-.1-.1C7.14 14.24 4 11.39 4 8.5 4 6.5 5.5 5 7.5 5c1.54 0 3.04.99 3.57 2.36h1.87C13.46 5.99 14.96 5 16.5 5c2 0 3.5 1.5 3.5 3.5 0 2.89-3.14 5.74-7.9 10.05z"/>',
      'bookmark-filled': '<path d="M17 3H7c-1.1 0-1.99.9-1.99 2L5 21l7-3 7 3V5c0-1.1-.9-2-2-2z"/>',
      'bookmark-outline': '<path d="M17 3H7c-1.1 0-1.99.9-1.99 2L5 21l7-3 7 3V5c0-1.1-.9-2-2-2zm0 15l-5-2.18L7 18V5h10v13z"/>',
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
      return avatar;
    }

    avatar.textContent = _getProviderInitial(providerName || 'ن');
    return avatar;
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

  function _emitEngagementUpdate(item) {
    if (!item || typeof window === 'undefined') return;
    window.dispatchEvent(new CustomEvent(_options.eventName || 'nw:spotlight-engagement-update', {
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

  /* ----------------------------------------------------------
     NAVIGATION: swipe / wheel / keyboard
  ---------------------------------------------------------- */
  function _goNext() {
    if (_currentIndex < _items.length - 1) {
      _currentIndex++;
      _renderCurrent();
    }
  }

  function _goPrev() {
    if (_currentIndex > 0) {
      _currentIndex--;
      _renderCurrent();
    }
  }

  function _goToIndex(index) {
    if (index < 0 || index >= _items.length || index === _currentIndex) return;
    _currentIndex = index;
    _renderCurrent();
  }

  function _onTouchStart(e) {
    _touchStartY = e.touches[0].clientY;
    _swiping = true;
  }

  function _onTouchMove(e) {
    // intentionally empty — we track in touchend
  }

  function _onTouchEnd(e) {
    if (!_swiping) return;
    _swiping = false;
    const dy = e.changedTouches[0].clientY - _touchStartY;
    if (Math.abs(dy) > 60) {
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
    try {
      return !!sessionStorage.getItem('nw_access_token');
    } catch (_) {
      return false;
    }
  }

  function _redirectToLogin() {
    const next = encodeURIComponent(window.location.pathname + window.location.search);
    window.location.href = '/login/?next=' + next;
  }

  function _buildReactionEndpoint(item, action, wasActive) {
    const source = String(item?.source || _options.source || 'spotlight').trim().toLowerCase();
    const base = source === 'portfolio' ? '/api/providers/portfolio/' : '/api/providers/spotlights/';
    const endpoint = base + encodeURIComponent(String(item.id)) + '/' + (wasActive ? 'un' + action : action) + '/';
    return _withMode(endpoint, item?.mode_context || _options.modeContext || 'client');
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
    return String(_options.modeContext || 'client') === 'provider' ? 'مزود' : 'عميل';
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

  function _soundIcon(isMuted) {
    if (isMuted) {
      return '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"></polygon><line x1="23" y1="9" x2="17" y2="15"></line><line x1="17" y1="9" x2="23" y2="15"></line></svg>';
    }
    return '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"></polygon><path d="M15.54 8.46a5 5 0 0 1 0 7.07"></path><path d="M19.07 4.93a10 10 0 0 1 0 14.14"></path></svg>';
  }

  return { open, close };
})();
