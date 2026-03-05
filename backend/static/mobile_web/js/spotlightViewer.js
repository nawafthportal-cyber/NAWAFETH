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
  let _touchStartY = 0;
  let _swiping = false;

  /* ----------------------------------------------------------
     PUBLIC: open viewer
  ---------------------------------------------------------- */
  function open(items, startIndex) {
    if (!items || !items.length) return;
    _items = items;
    _currentIndex = Math.max(0, Math.min(startIndex || 0, items.length - 1));
    _buildOverlay();
    _renderCurrent();
    document.body.style.overflow = 'hidden';
  }

  /* ----------------------------------------------------------
     PUBLIC: close viewer
  ---------------------------------------------------------- */
  function close() {
    if (_overlay) {
      _overlay.remove();
      _overlay = null;
    }
    document.body.style.overflow = '';
    _items = [];
    _currentIndex = 0;
  }

  /* ----------------------------------------------------------
     BUILD: Overlay shell
  ---------------------------------------------------------- */
  function _buildOverlay() {
    if (_overlay) _overlay.remove();

    _overlay = document.createElement('div');
    _overlay.className = 'sv-overlay';
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
    badge.textContent = 'لمحة';

    // Counter
    const counter = document.createElement('div');
    counter.className = 'sv-counter';
    counter.id = 'sv-counter';

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

    _overlay.appendChild(closeBtn);
    _overlay.appendChild(badge);
    _overlay.appendChild(counter);
    _overlay.appendChild(media);
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

    // Counter
    const counter = document.getElementById('sv-counter');
    if (counter) counter.textContent = (_currentIndex + 1) + ' / ' + _items.length;

    // Media
    const mediaEl = document.getElementById('sv-media');
    if (mediaEl) {
      mediaEl.innerHTML = '';
      const isVideo = _isVideo(item);

      if (isVideo) {
        const video = document.createElement('video');
        video.className = 'sv-video';
        video.autoplay = true;
        video.loop = true;
        video.playsInline = true;
        video.muted = false;
        video.src = _resolveUrl(item.file_url);
        video.addEventListener('error', () => {
          video.style.display = 'none';
          const errIcon = document.createElement('div');
          errIcon.className = 'sv-media-error';
          errIcon.innerHTML = '<svg width="40" height="40" viewBox="0 0 24 24" fill="rgba(255,255,255,0.5)"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-2h2v2zm0-4h-2V7h2v6z"/></svg>';
          mediaEl.appendChild(errIcon);
        });
        mediaEl.appendChild(video);
      } else {
        const imgUrl = _resolveUrl(item.thumbnail_url || item.file_url);
        if (imgUrl) {
          const img = document.createElement('img');
          img.className = 'sv-image';
          img.src = imgUrl;
          img.alt = item.caption || 'لمحة';
          img.addEventListener('error', () => {
            img.style.display = 'none';
            const errIcon = document.createElement('div');
            errIcon.className = 'sv-media-error';
            errIcon.innerHTML = '<svg width="40" height="40" viewBox="0 0 24 24" fill="rgba(255,255,255,0.5)"><path d="M21 5v6.59l-3-3.01-4 4.01-4-4-4 4-3-3.01V5c0-1.1.9-2 2-2h14c1.1 0 2 .9 2 2zm-3 6.42l3 3.01V19c0 1.1-.9 2-2 2H5c-1.1 0-2-.9-2-2v-6.58l3 2.99 4-4 4 4 4-3.99z"/></svg>';
            mediaEl.appendChild(errIcon);
          });
          mediaEl.appendChild(img);
        }
      }
    }

    // Bottom info (provider + caption)
    const bottomEl = document.getElementById('sv-bottom');
    if (bottomEl) {
      bottomEl.innerHTML = '';
      const provName = (item.provider_display_name || '').trim();
      const caption = (item.caption || '').trim();
      const provId = item.provider_id;

      if (provName) {
        const provRow = document.createElement('div');
        provRow.className = 'sv-provider-row';
        if (provId) provRow.style.cursor = 'pointer';

        // Avatar
        const avatar = document.createElement('div');
        avatar.className = 'sv-provider-avatar';
        const profileImg = _resolveUrl(item.provider_profile_image);
        if (profileImg) {
          const img = document.createElement('img');
          img.src = profileImg;
          img.alt = provName;
          img.addEventListener('error', () => { img.style.display = 'none'; avatar.textContent = provName.charAt(0); });
          avatar.appendChild(img);
        } else {
          avatar.textContent = provName.charAt(0) || '؟';
        }
        provRow.appendChild(avatar);

        const nameSpan = document.createElement('span');
        nameSpan.className = 'sv-provider-name';
        nameSpan.textContent = provName;
        provRow.appendChild(nameSpan);

        if (provId) {
          provRow.addEventListener('click', () => {
            close();
            window.location.href = '/provider/' + encodeURIComponent(String(provId)) + '/';
          });
        }
        bottomEl.appendChild(provRow);
      }

      if (caption) {
        const cap = document.createElement('div');
        cap.className = 'sv-caption';
        cap.textContent = caption;
        bottomEl.appendChild(cap);
      }
    }

    // Side actions
    const sideEl = document.getElementById('sv-side');
    if (sideEl) {
      sideEl.innerHTML = '';

      // Provider avatar (big)
      const provId = item.provider_id;
      const provImgUrl = _resolveUrl(item.provider_profile_image);
      const provAvatar = document.createElement('div');
      provAvatar.className = 'sv-side-avatar';
      if (provId) provAvatar.style.cursor = 'pointer';
      if (provImgUrl) {
        const img = document.createElement('img');
        img.src = provImgUrl;
        img.alt = '';
        img.addEventListener('error', () => { img.style.display = 'none'; });
        provAvatar.appendChild(img);
      } else {
        provAvatar.innerHTML = '<svg width="24" height="24" viewBox="0 0 24 24" fill="white"><path d="M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z"/></svg>';
      }
      if (provId) {
        provAvatar.addEventListener('click', () => {
          close();
          window.location.href = '/provider/' + encodeURIComponent(String(provId)) + '/';
        });
      }
      sideEl.appendChild(provAvatar);

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

  /* ----------------------------------------------------------
     TOGGLE LIKE / SAVE
  ---------------------------------------------------------- */
  async function _toggleLike(item) {
    const wasLiked = !!item.is_liked;
    // Optimistic update
    item.is_liked = !wasLiked;
    item.likes_count = (item.likes_count || 0) + (wasLiked ? -1 : 1);
    if (item.likes_count < 0) item.likes_count = 0;
    _renderCurrent();
    _emitEngagementUpdate(item);

    try {
      const endpoint = wasLiked
        ? '/api/providers/spotlights/' + item.id + '/unlike/'
        : '/api/providers/spotlights/' + item.id + '/like/';
      const res = await ApiClient.request(endpoint, { method: 'POST' });
      if (!res.ok) throw new Error();
    } catch (_) {
      // Revert
      item.is_liked = wasLiked;
      item.likes_count += wasLiked ? 1 : -1;
      _renderCurrent();
      _emitEngagementUpdate(item);
    }
  }

  async function _toggleSave(item) {
    const wasSaved = !!item.is_saved;
    item.is_saved = !wasSaved;
    item.saves_count = (item.saves_count || 0) + (wasSaved ? -1 : 1);
    if (item.saves_count < 0) item.saves_count = 0;
    _renderCurrent();
    _emitEngagementUpdate(item);

    try {
      const endpoint = wasSaved
        ? '/api/providers/spotlights/' + item.id + '/unsave/'
        : '/api/providers/spotlights/' + item.id + '/save/';
      const res = await ApiClient.request(endpoint, { method: 'POST' });
      if (!res.ok) throw new Error();
    } catch (_) {
      item.is_saved = wasSaved;
      item.saves_count += wasSaved ? 1 : -1;
      _renderCurrent();
      _emitEngagementUpdate(item);
    }
  }

  function _emitEngagementUpdate(item) {
    if (!item || typeof window === 'undefined') return;
    window.dispatchEvent(new CustomEvent('nw:spotlight-engagement-update', {
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

  function _isVideo(item) {
    const url = (item.file_url || '').toLowerCase();
    return url.endsWith('.mp4') || url.endsWith('.mov') || url.endsWith('.webm')
        || (item.media_type && item.media_type.toLowerCase() === 'video');
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

  return { open, close };
})();
