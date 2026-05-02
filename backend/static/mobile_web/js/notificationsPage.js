/* ===================================================================
   notificationsPage.js — Notifications page controller
   GET    /api/notifications/?limit=20&offset=0&mode=client|provider
   POST   /api/notifications/mark-read/<id>/
   POST   /api/notifications/mark-all-read/
   POST   /api/notifications/delete-old/
   POST   /api/notifications/actions/<id>/   { action: pin | follow_up }
   DELETE /api/notifications/actions/<id>/
   =================================================================== */
'use strict';

const NotificationsPage = (() => {
  const PAGE_LIMIT = 20;
  const COPY = {
    ar: {
      pageTitle: 'الإشعارات',
      authTitle: 'سجّل دخولك لعرض الإشعارات',
      authDesc: 'يمكنك تصفح إشعاراتك وآخر التحديثات بعد تسجيل الدخول',
      authCta: 'تسجيل الدخول',
      heading: 'الإشعارات',
      subtitle: 'تابع آخر التحديثات والعروض والرسائل في مكان واحد.',
      settings: 'إعدادات الإشعارات',
      markAllRead: 'تمييز الكل كمقروء',
      deleteOld: 'حذف القديم',
      retry: 'إعادة المحاولة',
      empty: 'لا توجد إشعارات حالياً',
      loadMore: 'تحميل المزيد',
      loadingMore: 'جار التحميل...',
      unreadBadge: '{count} غير مقروء',
      verifyModeFailed: 'تعذر التحقق من نوع الحساب الحالي. أعد المحاولة بعد لحظة.',
      sessionRefreshing: 'يتم تحديث الجلسة أو نوع الحساب الآن. أعد المحاولة بعد قليل.',
      loadFailed: 'تعذر تحميل الإشعارات حاليًا. حاول مرة أخرى بعد قليل.',
      notificationFallback: 'إشعار',
      flagPromo: 'دعائي',
      flagPromoUpdate: 'ترويج',
      flagFollowUp: 'متابعة',
      flagPinned: 'مثبت',
      promoReadHint: 'دعائي - مقروء',
      promoUnreadHint: 'دعائي - جديد',
      promoUpdateReadHint: 'تحديث ترويج - مقروء',
      promoUpdateUnreadHint: 'تحديث ترويج - جديد',
      readHint: 'مقروء',
      unreadHint: 'جديد',
      options: 'خيارات',
      notificationOptions: 'خيارات الإشعار',
      markRead: 'تمييز كمقروء',
      removeFollowUp: 'إزالة التمييز',
      addFollowUp: 'تمييز مهم للمتابعة',
      unpin: 'إلغاء التثبيت',
      pinTop: 'تثبيت بالأعلى',
      delete: 'حذف',
      promoMessage: 'رسالة دعائية',
      close: 'إغلاق',
      attachments: 'المرفقات',
      noAttachments: 'لا توجد مرفقات في هذه الرسالة.',
      attachmentFallback: 'مرفق',
      fileAttachment: 'ملف مرفق',
      openAttachment: 'فتح المرفق',
      noMessageBody: 'لا يوجد نص للرسالة.',
      loadingAttachments: 'جار تحميل المرفقات...',
      promoDetailsFailed: 'تعذر تحميل تفاصيل الرسالة الدعائية.',
      pinFailed: 'تعذر تحديث حالة التثبيت',
      followUpFailed: 'تعذر تحديث حالة المتابعة',
      deleteFailed: 'تعذر حذف الإشعار',
      actionFailed: 'تعذر تنفيذ العملية',
      markAllReadSuccess: 'تم تمييز الكل كمقروء',
      deleteOldFailed: 'تعذر حذف الإشعارات القديمة في الوقت الحالي.',
      deleteOldSuccess: 'تم حذف {deleted} إشعار قديم (أقدم من {days} يوم)',
      justNow: 'الآن',
      minutesAgo: 'منذ {count} دقيقة',
      hoursAgo: 'منذ {count} ساعة',
      daysAgo: 'منذ {count} يوم',
    },
    en: {
      pageTitle: 'Notifications',
      authTitle: 'Sign in to view notifications',
      authDesc: 'You can browse your notifications and latest updates after signing in',
      authCta: 'Sign in',
      heading: 'Notifications',
      subtitle: 'Keep up with the latest updates, offers, and messages in one place.',
      settings: 'Notification settings',
      markAllRead: 'Mark all as read',
      deleteOld: 'Delete old',
      retry: 'Retry',
      empty: 'There are no notifications right now',
      loadMore: 'Load more',
      loadingMore: 'Loading...',
      unreadBadge: '{count} unread',
      verifyModeFailed: 'Unable to verify the current account mode. Please try again shortly.',
      sessionRefreshing: 'The session or account mode is being refreshed right now. Please try again shortly.',
      loadFailed: 'Unable to load notifications right now. Please try again later.',
      notificationFallback: 'Notification',
      flagPromo: 'Promoted',
      flagPromoUpdate: 'Promotion',
      flagFollowUp: 'Follow-up',
      flagPinned: 'Pinned',
      promoReadHint: 'Promoted - read',
      promoUnreadHint: 'Promoted - new',
      promoUpdateReadHint: 'Promotion update - read',
      promoUpdateUnreadHint: 'Promotion update - new',
      readHint: 'Read',
      unreadHint: 'New',
      options: 'Options',
      notificationOptions: 'Notification options',
      markRead: 'Mark as read',
      removeFollowUp: 'Remove highlight',
      addFollowUp: 'Mark for follow-up',
      unpin: 'Unpin',
      pinTop: 'Pin to top',
      delete: 'Delete',
      promoMessage: 'Promotional message',
      close: 'Close',
      attachments: 'Attachments',
      noAttachments: 'There are no attachments in this message.',
      attachmentFallback: 'Attachment',
      fileAttachment: 'Attached file',
      openAttachment: 'Open attachment',
      noMessageBody: 'There is no message text.',
      loadingAttachments: 'Loading attachments...',
      promoDetailsFailed: 'Unable to load the promotional message details.',
      pinFailed: 'Unable to update the pin state',
      followUpFailed: 'Unable to update the follow-up state',
      deleteFailed: 'Unable to delete the notification',
      actionFailed: 'Unable to complete the action',
      markAllReadSuccess: 'All notifications were marked as read',
      deleteOldFailed: 'Unable to delete old notifications right now.',
      deleteOldSuccess: 'Deleted {deleted} old notifications (older than {days} days)',
      justNow: 'Now',
      minutesAgo: '{count} minute ago',
      hoursAgo: '{count} hour ago',
      daysAgo: '{count} day ago',
    },
  };

  let _notifications = [];
  let _totalCount = 0;
  let _offset = 0;
  let _hasMore = true;
  let _loading = false;
  let _loadingMore = false;
  let _eventsBound = false;
  let _scrollBound = false;
  let _toastTimer = null;
  let _promoModal = null;
  let _promoModalKeyBound = false;
  let _lastErrorMessage = '';
  let _lastErrorCopyKey = '';

  function init() {
    _applyStaticCopy();
    document.addEventListener('nawafeth:languagechange', _handleLanguageChange);

    if (!Auth.isLoggedIn()) {
      _showGate();
      return;
    }
    _hideGate();

    const markAllBtn = document.getElementById('btn-mark-all');
    const deleteOldBtn = document.getElementById('btn-delete-old');
    const loadMoreBtn = document.getElementById('notif-load-more');
    const retryBtn = document.getElementById('notif-retry');

    if (markAllBtn) markAllBtn.addEventListener('click', _markAllRead);
    if (deleteOldBtn) deleteOldBtn.addEventListener('click', _deleteOld);
    if (loadMoreBtn) {
      loadMoreBtn.addEventListener('click', () => _fetchNotifications({ reset: false }));
    }
    if (retryBtn) {
      retryBtn.addEventListener('click', () => _fetchNotifications({ reset: true }));
    }

    _bindEvents();
    _fetchNotifications({ reset: true });
  }

  function _activeMode() {
    try {
      const params = new URLSearchParams(window.location.search || '');
      const modeFromUrl = (params.get('mode') || '').trim().toLowerCase();
      if (modeFromUrl === 'provider' || modeFromUrl === 'client') {
        sessionStorage.setItem('nw_account_mode', modeFromUrl);
        return modeFromUrl;
      }
    } catch (_) {}
    try {
      const mode = (sessionStorage.getItem('nw_account_mode') || '').trim().toLowerCase();
      if (mode === 'provider' || mode === 'client') return mode;
    } catch (_) {}
    const role = (Auth.getRoleState() || '').trim().toLowerCase();
    return role === 'provider' ? 'provider' : 'client';
  }

  function _withMode(path) {
    const mode = _activeMode();
    if (!mode) return path;
    return path + (path.includes('?') ? '&' : '?') + 'mode=' + encodeURIComponent(mode);
  }

  function _matchesActiveMode(notif) {
    const audienceMode = String((notif && notif.audience_mode) || 'shared').trim().toLowerCase();
    return audienceMode === 'shared' || audienceMode === _activeMode();
  }

  function _bindEvents() {
    if (_eventsBound) return;
    _eventsBound = true;

    window.addEventListener('nw:notification-created', _handleRealtimeNotification);
    document.addEventListener('click', _closeAllMenus);

    if (!_scrollBound) {
      _scrollBound = true;
      window.addEventListener('scroll', _onScroll, { passive: true });
    }
  }

  function _onScroll() {
    if (_loading || _loadingMore || !_hasMore) return;
    const doc = document.documentElement;
    const nearBottom = (window.innerHeight + window.scrollY) >= (doc.scrollHeight - 220);
    if (nearBottom) _fetchNotifications({ reset: false });
  }

  function _handleRealtimeNotification(event) {
    const notif = event && event.detail ? event.detail : null;
    if (!notif || !_matchesActiveMode(notif)) return;

    const existingIndex = _findIndexById(notif.id);
    if (existingIndex >= 0) {
      _notifications.splice(existingIndex, 1);
    } else {
      _totalCount += 1;
    }
    _notifications.unshift(notif);
    _offset = _notifications.length;

    _render();
  }

  function _appendUniqueNotifications(list) {
    if (!Array.isArray(list) || !list.length) return;
    const known = new Set(_notifications.map((item) => String(item.id)));
    list.forEach((item) => {
      const key = String(item && item.id);
      if (!key || known.has(key)) return;
      known.add(key);
      _notifications.push(item);
    });
  }

  async function _fetchNotifications(options) {
    const reset = !options || options.reset !== false;
    if (reset) {
      if (_loading) return;
      _setLoading(true);
      _setError('', { retry: false });
      _offset = 0;
      _hasMore = true;
    } else {
      if (_loading || _loadingMore || !_hasMore) return;
      _setLoadingMore(true);
    }

    const requestOffset = reset ? 0 : _offset;
    const profileState = await Auth.resolveProfile(false, _activeMode());
    if (!profileState.ok) {
      if (!Auth.isLoggedIn()) {
        _showGate();
        return;
      }
      _setError(_copy('verifyModeFailed'), { retry: true, copyKey: 'verifyModeFailed' });
      return;
    }
    const url = _withMode('/api/notifications/?limit=' + PAGE_LIMIT + '&offset=' + requestOffset);
    const res = await ApiClient.get(url);

    if (reset) _setLoading(false);
    else _setLoadingMore(false);

    if (res.ok && res.data) {
      const data = res.data;
      const rows = Array.isArray(data) ? data : (data.results || data.notifications || []);

      if (reset) {
        _notifications = Array.isArray(rows) ? rows.slice() : [];
      } else {
        _appendUniqueNotifications(rows);
      }

      let total = 0;
      if (!Array.isArray(data) && typeof data.count === 'number') total = data.count;
      else if (!Array.isArray(data) && typeof data.total_count === 'number') total = data.total_count;
      else total = Math.max(_totalCount, _notifications.length);

      _totalCount = Math.max(0, _safeInt(total));
      _offset = _notifications.length;

      const hasMoreByApi = !Array.isArray(data) && (Boolean(data.next) || Boolean(data.has_more));
      _hasMore = hasMoreByApi || (_offset < _totalCount);

      _render();
      return;
    }

    if (res.status === 401) {
      const recovered = await Auth.resolveProfile(true, _activeMode());
      if (!recovered.ok && !Auth.isLoggedIn()) {
        _showGate();
        return;
      }
      _setError(_copy('sessionRefreshing'), { retry: true, copyKey: 'sessionRefreshing' });
      return;
    }

    if (reset && !_notifications.length) {
      _notifications = [];
      _totalCount = 0;
      _offset = 0;
      _hasMore = false;
      _render();
    }

    _setError(_copy('loadFailed'), { retry: reset, copyKey: 'loadFailed' });
  }

  function _render() {
    const container = document.getElementById('notif-list');
    const emptyEl = document.getElementById('notif-empty');
    if (!container || !emptyEl) return;

    _closeAllMenus();
    container.innerHTML = '';

    if (!_notifications.length) {
      emptyEl.classList.remove('hidden');
      _refreshCounters();
      _updateLoadMoreUi();
      return;
    }

    emptyEl.classList.add('hidden');

    const frag = document.createDocumentFragment();
    _notifications.forEach((notif) => frag.appendChild(_buildCard(notif)));
    container.appendChild(frag);

    _refreshCounters();
    _updateLoadMoreUi();
  }

  function _buildCard(notif) {
    const isRead = !!notif.is_read;
    const isUrgent = !!notif.is_urgent;
    const isFollowUp = !!notif.is_follow_up;
    const isPinned = !!notif.is_pinned;
    const kind = String(notif.kind || '').toLowerCase();
    const notificationClass = _notificationClassification(notif, kind);
    const isPromo = notificationClass === 'promo_ad';
    const isPromoUpdate = notificationClass === 'promo_update';

    const card = UI.el('div', {
      className:
        'notif-card' +
        (isRead ? ' read' : ' unread') +
        (isPromo ? ' promo' : '') +
        (isPromoUpdate ? ' promo-update' : '') +
        (isUrgent ? ' urgent' : '') +
        (isFollowUp ? ' follow-up' : '') +
        (isPinned ? ' pinned' : ''),
      role: 'button',
      tabindex: '0',
    });

    card.addEventListener('click', () => _openNotification(notif));
    card.addEventListener('keydown', (event) => {
      if (event.key !== 'Enter' && event.key !== ' ') return;
      event.preventDefault();
      _openNotification(notif);
    });

    const iconWrap = UI.el('div', { className: 'notif-icon' });
    const iconName = _iconForKind(kind, notificationClass);
    const iconColor = isUrgent ? '#FFFFFF' : _colorForKind(kind, notificationClass);
    iconWrap.style.background = isUrgent ? 'rgba(255, 255, 255, 0.14)' : iconColor + '15';
    if (isUrgent) iconWrap.style.borderColor = 'rgba(255, 255, 255, 0.3)';
    iconWrap.appendChild(UI.icon(iconName, 22, iconColor));
    card.appendChild(iconWrap);

    const body = UI.el('div', { className: 'notif-body' });

    const headerRow = UI.el('div', { className: 'notif-header-row' });

    const titleWrap = UI.el('div', { className: 'notif-title-wrap' });
    const titleEl = UI.el('span', { className: 'notif-title', textContent: notif.title || _copy('notificationFallback') });
    _setAutoDirection(titleEl, notif.title);
    titleWrap.appendChild(titleEl);

    const flagsWrap = UI.el('div', { className: 'notif-flags' });
    if (isPromo) flagsWrap.appendChild(UI.el('span', { className: 'notif-flag promo', textContent: _copy('flagPromo') }));
    if (isPromoUpdate) flagsWrap.appendChild(UI.el('span', { className: 'notif-flag promo-update', textContent: _copy('flagPromoUpdate') }));
    if (isFollowUp) flagsWrap.appendChild(UI.el('span', { className: 'notif-flag follow', textContent: _copy('flagFollowUp') }));
    if (isPinned) flagsWrap.appendChild(UI.el('span', { className: 'notif-flag pin', textContent: _copy('flagPinned') }));
    if (!isRead) flagsWrap.appendChild(UI.el('span', { className: 'notif-dot' }));
    if (flagsWrap.childNodes.length) titleWrap.appendChild(flagsWrap);

    headerRow.appendChild(titleWrap);
    headerRow.appendChild(_buildCardActions(notif));

    body.appendChild(headerRow);

    if (notif.body || notif.message) {
      const bodyEl = UI.el('div', { className: 'notif-text', textContent: notif.body || notif.message });
      _setAutoDirection(bodyEl, notif.body || notif.message);
      body.appendChild(bodyEl);
    }

    if (notif.created_at || notif.created) {
      const metaRow = UI.el('div', { className: 'notif-meta-row' });
      metaRow.appendChild(
        UI.el('div', {
          className: 'notif-time',
          textContent: _relativeTime(notif.created_at || notif.created),
        })
      );
      const hintText = isPromo
        ? (isRead ? _copy('promoReadHint') : _copy('promoUnreadHint'))
        : isPromoUpdate
          ? (isRead ? _copy('promoUpdateReadHint') : _copy('promoUpdateUnreadHint'))
        : (isRead ? _copy('readHint') : _copy('unreadHint'));
      metaRow.appendChild(UI.el('div', { className: 'notif-open-hint', textContent: hintText }));
      body.appendChild(metaRow);
    }

    card.appendChild(body);
    return card;
  }

  function _buildCardActions(notif) {
    const wrap = UI.el('div', { className: 'notif-card-actions' });

    const menuBtn = UI.el('button', {
      type: 'button',
      className: 'notif-menu-btn',
      title: _copy('options'),
      ariaLabel: _copy('notificationOptions'),
    });
    menuBtn.innerHTML = [
      '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">',
      '<circle cx="12" cy="5" r="1.4"></circle>',
      '<circle cx="12" cy="12" r="1.4"></circle>',
      '<circle cx="12" cy="19" r="1.4"></circle>',
      '</svg>',
    ].join('');
    menuBtn.addEventListener('click', (event) => {
      event.preventDefault();
      event.stopPropagation();
      _toggleMenu(menu);
    });

    const menu = UI.el('div', { className: 'notif-menu hidden' });
    menu.addEventListener('click', (event) => event.stopPropagation());

    if (!notif.is_read) {
      menu.appendChild(
        _buildMenuItem(_copy('markRead'), async () => {
          await _markRead(notif.id);
        })
      );
    }

    menu.appendChild(
      _buildMenuItem(notif.is_follow_up ? _copy('removeFollowUp') : _copy('addFollowUp'), async () => {
        await _toggleFollowUp(notif.id);
      })
    );

    menu.appendChild(
      _buildMenuItem(notif.is_pinned ? _copy('unpin') : _copy('pinTop'), async () => {
        await _togglePin(notif.id);
      })
    );

    menu.appendChild(
      _buildMenuItem(
        _copy('delete'),
        async () => {
          await _deleteNotification(notif.id);
        },
        true
      )
    );

    wrap.appendChild(menuBtn);
    wrap.appendChild(menu);
    return wrap;
  }

  function _buildMenuItem(label, onClick, isDanger) {
    const item = UI.el('button', {
      type: 'button',
      className: 'notif-menu-item' + (isDanger ? ' danger' : ''),
      textContent: label,
    });

    item.addEventListener('click', async (event) => {
      event.preventDefault();
      event.stopPropagation();
      _closeAllMenus();
      await onClick();
    });

    return item;
  }

  function _toggleMenu(menu) {
    if (!menu) return;
    const wasOpen = menu.classList.contains('open');
    _closeAllMenus();
    if (wasOpen) return;
    menu.classList.remove('hidden');
    requestAnimationFrame(() => {
      menu.classList.add('open');
    });
  }

  function _closeAllMenus() {
    document.querySelectorAll('.notif-menu').forEach((menu) => {
      menu.classList.remove('open');
      menu.classList.add('hidden');
    });
  }

  function _findIndexById(id) {
    const target = String(id);
    return _notifications.findIndex((item) => String(item.id) === target);
  }

  function _withModeOnNavigation(targetUrl) {
    const raw = String(targetUrl || '').trim();
    if (!raw) return '';
    if (/^https?:\/\//i.test(raw)) return raw;
    return _withMode(raw);
  }

  function _notificationClassification(notif, kindOverride) {
    const kind = String(kindOverride || (notif && notif.kind) || '').trim().toLowerCase();
    if (kind === 'promo_offer') return 'promo_ad';
    if (kind === 'promo_status_change') return 'promo_update';
    if (_notificationHasPromoItemLink(notif)) return 'promo_ad';
    return 'standard';
  }

  function _notificationHasPromoItemLink(notif) {
    const raw = String((notif && notif.url) || '').trim();
    if (!raw) return false;
    try {
      const parsed = /^https?:\/\//i.test(raw) ? new URL(raw) : new URL(raw, window.location.origin);
      return parsed.searchParams.has('promo_item_id');
    } catch (_) {
      return /(?:^|[?&])promo_item_id=\d+/i.test(raw);
    }
  }

  function _isPromotionalNotification(notif, kindOverride) {
    return _notificationClassification(notif, kindOverride) === 'promo_ad';
  }

  async function _openNotification(notif) {
    if (!notif) return;
    if (notif.id) await _markRead(notif.id);
    if (_isPromotionalNotification(notif)) {
      await _openPromoModal(notif);
      return;
    }
    const targetUrl = _withModeOnNavigation(notif.url || '');
    if (!targetUrl) return;
    window.location.href = targetUrl;
  }

  function _ensurePromoModal() {
    if (_promoModal) return _promoModal;
    const root = UI.el('div', { className: 'notif-promo-modal hidden', id: 'notif-promo-modal' });
    root.innerHTML = [
      '<div class="notif-promo-backdrop" data-close-promo-modal="1"></div>',
      '<section class="notif-promo-dialog" role="dialog" aria-modal="true" aria-label="' + _escapeHtml(_copy('promoMessage')) + '">',
      '<button type="button" class="notif-promo-close" data-close-promo-modal="1" aria-label="' + _escapeHtml(_copy('close')) + '">×</button>',
      '<div class="notif-promo-head">',
      '<span class="notif-promo-badge">' + _escapeHtml(_copy('promoMessage')) + '</span>',
      '<h3 class="notif-promo-title" id="notif-promo-title"></h3>',
      '<div class="notif-promo-time" id="notif-promo-time"></div>',
      '</div>',
      '<div class="notif-promo-message" id="notif-promo-message"></div>',
      '<div class="notif-promo-section-title">' + _escapeHtml(_copy('attachments')) + '</div>',
      '<div class="notif-promo-attachments" id="notif-promo-attachments"></div>',
      '</section>',
    ].join('');
    root.addEventListener('click', (event) => {
      const target = event.target;
      if (!(target instanceof Element)) return;
      if (target.closest('[data-close-promo-modal="1"]')) _closePromoModal();
    });
    document.body.appendChild(root);
    _promoModal = root;
    if (!_promoModalKeyBound) {
      _promoModalKeyBound = true;
      document.addEventListener('keydown', (event) => {
        if (event.key === 'Escape') _closePromoModal();
      });
    }
    return root;
  }

  function _closePromoModal() {
    const root = document.getElementById('notif-promo-modal');
    if (!root) return;
    root.classList.remove('open');
    window.setTimeout(() => {
      root.classList.add('hidden');
    }, 160);
  }

  function _assetVisualType(asset) {
    const type = String((asset && asset.asset_type) || '').trim().toLowerCase();
    if (type === 'video') return 'video';
    if (type === 'image') return 'image';
    return 'file';
  }

  function _renderPromoAttachments(container, attachments) {
    container.innerHTML = '';
    if (!Array.isArray(attachments) || !attachments.length) {
      container.appendChild(UI.el('div', { className: 'notif-promo-empty', textContent: _copy('noAttachments') }));
      return;
    }
    const frag = document.createDocumentFragment();
    attachments.forEach((asset) => {
      const card = UI.el('div', { className: 'notif-promo-asset' });
      const fileUrl = String((asset && asset.file_url) || '').trim();
      const caption = String((asset && asset.title) || (asset && asset.file_name) || _copy('attachmentFallback'));
      const visualType = _assetVisualType(asset);

      if (visualType === 'image' && fileUrl) {
        const img = UI.el('img', { className: 'notif-promo-asset-image', alt: caption });
        img.src = fileUrl;
        card.appendChild(img);
      } else if (visualType === 'video' && fileUrl) {
        const video = UI.el('video', { className: 'notif-promo-asset-video', controls: 'controls', preload: 'metadata' });
        video.src = fileUrl;
        card.appendChild(video);
      } else {
        const fileRow = UI.el('a', {
          className: 'notif-promo-asset-file',
          href: fileUrl || '#',
          target: '_blank',
          rel: 'noopener',
        });
        fileRow.appendChild(UI.icon('attach_file', 16, '#9a3412'));
        fileRow.appendChild(UI.el('span', { textContent: String((asset && asset.file_name) || _copy('fileAttachment')) }));
        card.appendChild(fileRow);
      }

      card.appendChild(UI.el('div', { className: 'notif-promo-asset-caption', textContent: caption }));
      if (fileUrl) {
        card.appendChild(UI.el('a', {
          className: 'notif-promo-asset-open',
          href: fileUrl,
          target: '_blank',
          rel: 'noopener',
          textContent: _copy('openAttachment'),
        }));
      }
      frag.appendChild(card);
    });
    container.appendChild(frag);
  }

  async function _openPromoModal(notif) {
    const root = _ensurePromoModal();
    const titleEl = document.getElementById('notif-promo-title');
    const timeEl = document.getElementById('notif-promo-time');
    const messageEl = document.getElementById('notif-promo-message');
    const attachmentsEl = document.getElementById('notif-promo-attachments');
    if (!titleEl || !timeEl || !messageEl || !attachmentsEl) return;

    titleEl.textContent = String(notif.title || '').trim() || _copy('promoMessage');
    timeEl.textContent = _relativeTime(notif.created_at || notif.created) || '';
    messageEl.textContent = String(notif.body || notif.message || '').trim() || _copy('noMessageBody');
    attachmentsEl.innerHTML = '<div class="notif-promo-loading">' + _escapeHtml(_copy('loadingAttachments')) + '</div>';
    _setAutoDirection(titleEl, notif.title);
    _setAutoDirection(messageEl, notif.body || notif.message);

    root.classList.remove('hidden');
    requestAnimationFrame(() => root.classList.add('open'));

    if (!notif.id) {
      _renderPromoAttachments(attachmentsEl, []);
      return;
    }

    const res = await ApiClient.get(_withMode('/api/notifications/promo-preview/' + notif.id + '/'));
    if (!res.ok || !res.data) {
      _showToast(_copy('promoDetailsFailed'), 'error');
      _renderPromoAttachments(attachmentsEl, []);
      return;
    }

    const payload = res.data || {};
    titleEl.textContent = String(payload.title || titleEl.textContent).trim() || _copy('promoMessage');
    messageEl.textContent = String(payload.body || messageEl.textContent).trim() || _copy('noMessageBody');
    timeEl.textContent = _relativeTime(payload.created_at || notif.created_at || notif.created) || '';
    _setAutoDirection(titleEl, payload.title || titleEl.textContent);
    _setAutoDirection(messageEl, payload.body || messageEl.textContent);
    _renderPromoAttachments(attachmentsEl, payload.attachments || []);
  }

  async function _markRead(id) {
    if (!id) return false;
    const index = _findIndexById(id);
    if (index < 0) return false;
    if (_notifications[index].is_read) return true;

    const res = await ApiClient.request(_withMode('/api/notifications/mark-read/' + id + '/'), { method: 'POST' });
    if (!res.ok) return false;

    _notifications[index].is_read = true;
    _render();
    window.dispatchEvent(new Event('nw:badge-refresh'));
    return true;
  }

  async function _togglePin(id) {
    if (!id) return;
    const index = _findIndexById(id);
    if (index < 0) return;

    const res = await ApiClient.request(_withMode('/api/notifications/actions/' + id + '/'), {
      method: 'POST',
      body: { action: 'pin' },
    });

    if (!res.ok) {
      _showToast(_copy('pinFailed'), 'error');
      return;
    }

    const fallback = !_notifications[index].is_pinned;
    const nextValue = res.data && typeof res.data.is_pinned === 'boolean'
      ? !!res.data.is_pinned
      : fallback;

    _notifications[index].is_pinned = nextValue;
    _render();
  }

  async function _toggleFollowUp(id) {
    if (!id) return;
    const index = _findIndexById(id);
    if (index < 0) return;

    const res = await ApiClient.request(_withMode('/api/notifications/actions/' + id + '/'), {
      method: 'POST',
      body: { action: 'follow_up' },
    });

    if (!res.ok) {
      _showToast(_copy('followUpFailed'), 'error');
      return;
    }

    const fallback = !_notifications[index].is_follow_up;
    const nextValue = res.data && typeof res.data.is_follow_up === 'boolean'
      ? !!res.data.is_follow_up
      : fallback;

    _notifications[index].is_follow_up = nextValue;
    _render();
  }

  async function _deleteNotification(id) {
    if (!id) return;
    const index = _findIndexById(id);
    if (index < 0) return;

    const res = await ApiClient.request(_withMode('/api/notifications/actions/' + id + '/'), {
      method: 'DELETE',
    });

    if (!res.ok) {
      _showToast(_copy('deleteFailed'), 'error');
      return;
    }

    _notifications.splice(index, 1);
    _totalCount = Math.max(0, _totalCount - 1);
    _offset = _notifications.length;
    _hasMore = _offset < _totalCount;
    _render();
    window.dispatchEvent(new Event('nw:badge-refresh'));
  }

  async function _markAllRead() {
    if (_loading || _loadingMore) return;

    const res = await ApiClient.request(_withMode('/api/notifications/mark-all-read/'), { method: 'POST' });
    if (!res.ok) {
      _showToast(_copy('actionFailed'), 'error');
      return;
    }

    _notifications.forEach((notif) => {
      notif.is_read = true;
    });
    _render();
    window.dispatchEvent(new Event('nw:badge-refresh'));
    _showToast(_copy('markAllReadSuccess'), 'success');
  }

  async function _deleteOld() {
    if (_loading || _loadingMore) return;

    _setLoading(true);
    const res = await ApiClient.request(_withMode('/api/notifications/delete-old/'), { method: 'POST' });
    _setLoading(false);

    if (!res.ok) {
      _setError(_copy('deleteOldFailed'), { retry: false, copyKey: 'deleteOldFailed' });
      return;
    }

    const deleted = _safeInt(res.data && res.data.deleted);
    const retentionDays = Math.max(1, _safeInt(res.data && res.data.retention_days) || 90);

    _showToast(_copy('deleteOldSuccess', { deleted, days: retentionDays }), 'success');
    window.dispatchEvent(new Event('nw:badge-refresh'));
    _fetchNotifications({ reset: true });
  }

  function _iconForKind(kind, classification) {
    if (classification === 'promo_ad') return 'campaign';
    if (classification === 'promo_update') return 'info';
    if (kind.includes('request') || kind.includes('offer')) return 'category';
    if (kind.includes('message')) return 'campaign';
    if (kind.includes('urgent')) return 'fitness';
    return 'info';
  }

  function _colorForKind(kind, classification) {
    if (classification === 'promo_ad') return '#D97706';
    if (classification === 'promo_update') return '#4F46E5';
    if (kind.includes('urgent') || kind.includes('error')) return '#F44336';
    if (kind.includes('offer') || kind.includes('success')) return '#4CAF50';
    if (kind.includes('message')) return '#2196F3';
    if (kind.includes('warn')) return '#FF9800';
    return '#673AB7';
  }

  function _relativeTime(dateStr) {
    const now = new Date();
    const dt = new Date(dateStr);
    if (Number.isNaN(dt.getTime())) return '';
    const diff = Math.floor((now - dt) / 1000);
    if (diff < 60) return _copy('justNow');
    if (diff < 3600) return _copy('minutesAgo', { count: Math.floor(diff / 60) });
    if (diff < 86400) return _copy('hoursAgo', { count: Math.floor(diff / 3600) });
    if (diff < 604800) return _copy('daysAgo', { count: Math.floor(diff / 86400) });
    return dt.toLocaleDateString(_locale(), { day: 'numeric', month: 'short', year: 'numeric' });
  }

  function _refreshCounters() {
    const total = Math.max(_totalCount, _notifications.length);
    _setText('notif-total', String(total));

    const unread = _notifications.filter((notif) => !notif.is_read).length;
    const unreadEl = document.getElementById('notif-unread');
    if (!unreadEl) return;
    unreadEl.textContent = _copy('unreadBadge', { count: unread });
    unreadEl.classList.toggle('hidden', unread <= 0);
  }

  function _updateLoadMoreUi() {
    const wrap = document.getElementById('notif-load-more-wrap');
    const btn = document.getElementById('notif-load-more');
    if (!wrap || !btn) return;

    const visible = _notifications.length > 0 && (_hasMore || _loadingMore);
    wrap.classList.toggle('hidden', !visible);

    btn.disabled = _loading || _loadingMore;
    btn.textContent = _loadingMore ? _copy('loadingMore') : _copy('loadMore');
  }

  function _showGate() {
    const gate = document.getElementById('auth-gate');
    const content = document.getElementById('notif-content');
    if (gate) gate.classList.remove('hidden');
    if (content) content.classList.add('hidden');
  }

  function _hideGate() {
    const gate = document.getElementById('auth-gate');
    const content = document.getElementById('notif-content');
    if (gate) gate.classList.add('hidden');
    if (content) content.classList.remove('hidden');
  }

  function _setLoading(value) {
    _loading = !!value;
    const loader = document.getElementById('notif-loader');
    if (loader) loader.classList.toggle('hidden', !_loading);

    const markAll = document.getElementById('btn-mark-all');
    const deleteOld = document.getElementById('btn-delete-old');
    const retry = document.getElementById('notif-retry');
    if (markAll) markAll.disabled = _loading;
    if (deleteOld) deleteOld.disabled = _loading;
    if (retry) retry.disabled = _loading;

    _updateLoadMoreUi();
  }

  function _setLoadingMore(value) {
    _loadingMore = !!value;
    _updateLoadMoreUi();
  }

  function _setError(message, options) {
    const errorEl = document.getElementById('notif-error');
    const retryWrap = document.getElementById('notif-retry-wrap');
    if (!errorEl) return;
    const showRetry = !options || options.retry !== false;
    _lastErrorMessage = message || '';
    _lastErrorCopyKey = options && options.copyKey ? options.copyKey : '';

    if (!message) {
      errorEl.textContent = '';
      errorEl.classList.add('hidden');
      if (retryWrap) retryWrap.classList.add('hidden');
      return;
    }

    errorEl.textContent = message;
    errorEl.classList.remove('hidden');
    if (retryWrap) retryWrap.classList.toggle('hidden', !showRetry);
  }

  function _setText(id, value) {
    const el = document.getElementById(id);
    if (el) el.textContent = value;
  }

  function _setAttr(id, name, value) {
    const el = document.getElementById(id);
    if (el) el.setAttribute(name, value);
  }

  function _setAutoDirection(el, value) {
    if (!el) return;
    if (String(value || '').trim()) el.setAttribute('dir', 'auto');
    else el.removeAttribute('dir');
  }

  function _safeInt(value) {
    const num = Number(value);
    if (!Number.isFinite(num)) return 0;
    return Math.max(0, Math.floor(num));
  }

  function _showToast(message, type, options) {
    if (!message) return;
    const existing = document.getElementById('notif-toast');
    if (existing) existing.remove();
    const title = String((options && options.title) || '').trim();
    const durationMs = Number(options && options.durationMs) > 0 ? Number(options.durationMs) : 2200;

    const toast = UI.el('div', {
      id: 'notif-toast',
      className: 'notif-toast' + (type ? (' ' + type) : ''),
    });
    if (title) {
      toast.classList.add('with-title');
      toast.appendChild(UI.el('div', { className: 'notif-toast-title', textContent: title }));
      toast.appendChild(UI.el('div', { className: 'notif-toast-body', textContent: message }));
    } else {
      toast.textContent = message;
    }

    document.body.appendChild(toast);
    requestAnimationFrame(() => toast.classList.add('show'));

    window.clearTimeout(_toastTimer);
    _toastTimer = window.setTimeout(() => {
      toast.classList.remove('show');
      window.setTimeout(() => {
        if (toast.parentNode) toast.remove();
      }, 180);
    }, durationMs);
  }

  function _handleLanguageChange() {
    _applyStaticCopy();
    if (_lastErrorMessage) {
      _setError(_lastErrorCopyKey ? _copy(_lastErrorCopyKey) : _lastErrorMessage, { retry: true, copyKey: _lastErrorCopyKey });
    }
    _render();
  }

  function _applyStaticCopy() {
    if (window.NawafethI18n && typeof window.NawafethI18n.t === 'function') {
      document.title = window.NawafethI18n.t('siteTitle') + ' — ' + _copy('pageTitle');
    }
    _setText('notif-auth-title', _copy('authTitle'));
    _setText('notif-auth-desc', _copy('authDesc'));
    _setText('notif-auth-cta', _copy('authCta'));
    _setText('notif-page-title', _copy('heading'));
    _setText('notif-page-subtitle', _copy('subtitle'));
    _setText('notif-settings-link', _copy('settings'));
    _setText('btn-mark-all', _copy('markAllRead'));
    _setText('btn-delete-old', _copy('deleteOld'));
    _setText('notif-retry', _copy('retry'));
    _setText('notif-empty-text', _copy('empty'));
    _setText('notif-load-more', _loadingMore ? _copy('loadingMore') : _copy('loadMore'));
  }

  function _currentLang() {
    try {
      if (window.NawafethI18n && typeof window.NawafethI18n.getLanguage === 'function') {
        return window.NawafethI18n.getLanguage() === 'en' ? 'en' : 'ar';
      }
      return (localStorage.getItem('nw_lang') || 'ar').toLowerCase() === 'en' ? 'en' : 'ar';
    } catch (_) {
      return 'ar';
    }
  }

  function _copy(key, replacements) {
    const bundle = COPY[_currentLang()] || COPY.ar;
    const value = Object.prototype.hasOwnProperty.call(bundle, key) ? bundle[key] : COPY.ar[key];
    return _replaceTokens(value, replacements);
  }

  function _replaceTokens(text, replacements) {
    if (typeof text !== 'string' || !replacements) return text;
    return text.replace(/\{(\w+)\}/g, (_, token) => (
      Object.prototype.hasOwnProperty.call(replacements, token) ? String(replacements[token]) : ''
    ));
  }

  function _escapeHtml(value) {
    return String(value || '').replace(/[&<>"']/g, (char) => {
      return ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char] || char;
    });
  }

  function _locale() {
    return _currentLang() === 'en' ? 'en-US' : 'ar-SA';
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
  return {};
})();
