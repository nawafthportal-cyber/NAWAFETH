/* ===================================================================
  chatsPage.js — Messages threads list controller
   GET /api/messaging/direct/threads/
   =================================================================== */
'use strict';

const ChatsPage = (() => {
  const COPY = {
    ar: {
      pageTitle: 'الرسائل',
      authTitle: 'سجّل دخولك لعرض الرسائل',
      authDesc: 'يمكنك التواصل مع مقدمي الخدمات بعد تسجيل الدخول',
      authCta: 'تسجيل الدخول',
      pageHeading: 'الرسائل',
      pageSubtitle: 'تابع رسائلك مع مزودي الخدمة واطلع على أحدث الرسائل بسهولة.',
      heroTagDirect: 'رسائل مباشرة',
      heroTagTeam: 'فرق المنصة',
      heroTagSafe: 'مرفقات آمنة',
      listTitle: 'قائمة الرسائل',
      filterAll: 'الكل',
      filterUnread: 'غير مقروءة',
      filterFavorite: 'مفضلة',
      filterClients: 'عملاء',
      filterRecent: 'الأحدث',
      searchPlaceholder: 'ابحث في الرسائل...',
      clearSearch: 'مسح البحث',
      retry: 'إعادة المحاولة',
      unreadBadge: '{count} غير مقروء',
      resultsOne: '{count} نتيجة',
      resultsMany: '{count} نتائج',
      emptySearch: 'لا توجد نتائج مطابقة للبحث.',
      emptyUnread: 'لا توجد رسائل غير مقروءة.',
      emptyFavorite: 'لا توجد رسائل مفضلة.',
      emptyClients: 'لا توجد رسائل عملاء حالياً.',
      emptyRecent: 'لا توجد رسائل حديثة حالياً.',
      emptyDefault: 'لا توجد رسائل بعد.',
      sessionChecking: 'يجري الآن التحقق من الجلسة ونوع الحساب. حاول مرة أخرى بعد لحظة.',
      sessionRefreshing: 'يتم تحديث الجلسة أو نوع الحساب الآن. أعد المحاولة بعد قليل.',
      loadFailed: 'تعذر تحميل الرسائل حالياً.',
      loadUnexpected: 'حدث خطأ غير متوقع أثناء تحميل الرسائل. حاول مرة أخرى.',
      excellenceFallback: 'تميز',
      unknownUser: 'مستخدم',
      teamRole: 'فريق المنصة',
      providerRole: 'مزود خدمة',
      clientRole: 'عميل',
      teamSubtitle: 'متابعة مباشرة مع فريق المنصة',
      providerInCity: 'مقدم خدمة في {city}',
      providerSubtitle: 'مقدم خدمة على المنصة',
      clientSubtitle: 'عميل يتابع معك مباشرة',
      directSubtitle: 'رسائل مباشرة داخل نوافذ',
      teamPreview: 'رسالة فريق',
      serviceRequest: 'طلب خدمة',
      directPreview: 'مباشر',
      noMessagesYet: 'لا توجد رسائل بعد',
      directServiceRequestPreview: '🛠️ طلب خدمة مباشر',
      unreadNew: '{count} جديد',
      favoriteChip: 'مفضلة',
      potentialClient: 'عميل محتمل',
      currentClient: 'عميل حالي',
      pastClient: 'عميل سابق',
      incompleteContact: 'تواصل غير مكتمل',
      openMessages: 'فتح الرسائل',
      messageOptions: 'خيارات الرسائل',
      markRead: 'اجعلها مقروءة',
      markUnread: 'اجعلها غير مقروءة',
      addFavorite: 'إضافة للمفضلة',
      removeFavorite: 'إزالة من المفضلة',
      block: 'حظر',
      unblock: 'إلغاء الحظر',
      report: 'إبلاغ',
      archive: 'أرشفة',
      unarchive: 'إلغاء الأرشفة',
      markReadFailed: 'تعذر تحديث حالة القراءة',
      markedRead: 'تم تحديد الرسائل كمقروءة',
      markedUnread: 'تم تحديد الرسائل كغير مقروءة',
      favoriteFailed: 'تعذر تحديث المفضلة',
      favoriteAdded: 'تمت إضافة الرسائل للمفضلة',
      favoriteRemoved: 'تمت إزالة الرسائل من المفضلة',
      potentialClientFailed: 'تعذر تحديث العميل المحتمل',
      potentialClientAdded: 'تم حفظ العميل كعميل محتمل',
      potentialClientRemoved: 'تمت إزالة العميل من العملاء المحتملين',
      archiveConfirm: 'أرشفة هذه الرسائل؟ سيتم إخفاؤها من قائمة الرسائل.',
      archiveFailed: 'تعذر تحديث الأرشفة',
      archiveAdded: 'تمت أرشفة الرسائل',
      archiveRemoved: 'تم إلغاء أرشفة الرسائل',
      unblockConfirm: 'هل تريد إلغاء الحظر عن هذا العضو؟',
      blockConfirm: 'هل أنت متأكد من حظر هذا العضو؟ لن يتمكن من مراسلتك.',
      blockFailed: 'تعذر تحديث حالة الحظر',
      blocked: 'تم حظر العضو',
      unblocked: 'تم إلغاء الحظر',
      reportDialogTitle: 'إبلاغ عن الرسائل',
      reportReasonLabel: 'سبب الإبلاغ:',
      reportDetailsLabel: 'تفاصيل إضافية (اختياري):',
      reportDetailsPlaceholder: 'اكتب التفاصيل هنا...',
      reportCancel: 'إلغاء',
      reportSend: 'إرسال البلاغ',
      reportSending: 'جارٍ الإرسال...',
      reportChooseReason: 'اختر سبب الإبلاغ أولاً',
      reportFailed: 'تعذر إرسال البلاغ',
      reportSuccess: 'تم إرسال البلاغ للإدارة. شكراً لك',
      reportReasonInappropriate: 'محتوى غير لائق',
      reportReasonFraud: 'احتيال أو نصب',
      reportReasonHarassment: 'إزعاج أو مضايقة',
      reportReasonImpersonation: 'انتحال شخصية',
      reportReasonTerms: 'محتوى مخالف للشروط',
      reportReasonOther: 'أخرى',
      justNow: 'الآن',
      minutesAgo: 'منذ {count} د',
      yesterday: 'الأمس',
    },
    en: {
      pageTitle: 'Messages',
      authTitle: 'Sign in to view messages',
      authDesc: 'You can contact providers after signing in',
      authCta: 'Sign in',
      pageHeading: 'Messages',
      pageSubtitle: 'Keep up with your conversations with providers and see the latest messages easily.',
      heroTagDirect: 'Direct messages',
      heroTagTeam: 'Platform teams',
      heroTagSafe: 'Secure attachments',
      listTitle: 'Messages list',
      filterAll: 'All',
      filterUnread: 'Unread',
      filterFavorite: 'Favorites',
      filterClients: 'Clients',
      filterRecent: 'Recent',
      searchPlaceholder: 'Search messages...',
      clearSearch: 'Clear search',
      retry: 'Retry',
      unreadBadge: '{count} unread',
      resultsOne: '{count} result',
      resultsMany: '{count} results',
      emptySearch: 'No messages match your search.',
      emptyUnread: 'There are no unread messages.',
      emptyFavorite: 'There are no favorite messages.',
      emptyClients: 'There are no client chats right now.',
      emptyRecent: 'There are no recent messages right now.',
      emptyDefault: 'No messages yet.',
      sessionChecking: 'The session and account mode are being verified right now. Try again in a moment.',
      sessionRefreshing: 'The session or account mode is being refreshed right now. Please try again shortly.',
      loadFailed: 'Unable to load messages right now.',
      loadUnexpected: 'An unexpected error occurred while loading messages. Please try again.',
      excellenceFallback: 'Excellence',
      unknownUser: 'User',
      teamRole: 'Platform team',
      providerRole: 'Provider',
      clientRole: 'Client',
      teamSubtitle: 'Direct follow-up with the platform team',
      providerInCity: 'Provider in {city}',
      providerSubtitle: 'Provider on the platform',
      clientSubtitle: 'Client following up with you directly',
      directSubtitle: 'Direct messages inside Nawafeth',
      teamPreview: 'Team message',
      serviceRequest: 'Service request',
      directPreview: 'Direct',
      noMessagesYet: 'No messages yet',
      directServiceRequestPreview: '🛠️ Direct service request',
      unreadNew: '{count} new',
      favoriteChip: 'Favorite',
      potentialClient: 'Potential client',
      currentClient: 'Current client',
      pastClient: 'Past client',
      incompleteContact: 'Incomplete contact',
      openMessages: 'Open messages',
      messageOptions: 'Message options',
      markRead: 'Mark as read',
      markUnread: 'Mark as unread',
      addFavorite: 'Add to favorites',
      removeFavorite: 'Remove from favorites',
      block: 'Block',
      unblock: 'Unblock',
      report: 'Report',
      archive: 'Archive',
      unarchive: 'Remove archive',
      markReadFailed: 'Unable to update the read state',
      markedRead: 'Messages marked as read',
      markedUnread: 'Messages marked as unread',
      favoriteFailed: 'Unable to update favorites',
      favoriteAdded: 'Messages added to favorites',
      favoriteRemoved: 'Messages removed from favorites',
      potentialClientFailed: 'Unable to update the potential client state',
      potentialClientAdded: 'Client saved as a potential client',
      potentialClientRemoved: 'Client removed from potential clients',
      archiveConfirm: 'Archive these messages? They will be hidden from the messages list.',
      archiveFailed: 'Unable to update the archive state',
      archiveAdded: 'Messages archived',
      archiveRemoved: 'Messages unarchived',
      unblockConfirm: 'Do you want to unblock this member?',
      blockConfirm: 'Are you sure you want to block this member? They will not be able to message you.',
      blockFailed: 'Unable to update the block state',
      blocked: 'Member blocked',
      unblocked: 'Member unblocked',
      reportDialogTitle: 'Report messages',
      reportReasonLabel: 'Report reason:',
      reportDetailsLabel: 'Additional details (optional):',
      reportDetailsPlaceholder: 'Write the details here...',
      reportCancel: 'Cancel',
      reportSend: 'Send report',
      reportSending: 'Sending...',
      reportChooseReason: 'Choose a report reason first',
      reportFailed: 'Unable to send the report',
      reportSuccess: 'The report was sent to the admin. Thank you.',
      reportReasonInappropriate: 'Inappropriate content',
      reportReasonFraud: 'Fraud or scam',
      reportReasonHarassment: 'Harassment',
      reportReasonImpersonation: 'Impersonation',
      reportReasonTerms: 'Content against the terms',
      reportReasonOther: 'Other',
      justNow: 'Now',
      minutesAgo: '{count} min ago',
      yesterday: 'Yesterday',
    },
  };

  let _threads = [];
  let _activeFilter = 'all';
  let _searchQuery = '';
  let _isLoading = false;
  let _isProviderMode = false;
  let _activeMenuThreadId = null;
  let _toastTimer = null;
  let _reportDialogState = null;
  let _eventsBound = false;
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
    _isProviderMode = _activeMode() === 'provider';

    _bindFilters();
    _bindSearch();
    _bindRetry();
    _bindGlobalEvents();
    _syncModeFilters();

    const params = new URLSearchParams(window.location.search);
    const startProviderId = params.get('start') || params.get('provider_id');
    if (startProviderId) {
      _startDirectChat(startProviderId);
      return;
    }

    _fetchThreads();
  }

  function _bindFilters() {
    const filterRoot = document.getElementById('chat-filters');
    if (!filterRoot) return;

    filterRoot.addEventListener('click', (event) => {
      const chip = event.target.closest('.filter-chip');
      if (!chip) return;

      filterRoot.querySelectorAll('.filter-chip').forEach((node) => node.classList.remove('active'));
      chip.classList.add('active');
      _activeFilter = chip.dataset.filter || 'all';
      _render();
    });
  }

  function _syncModeFilters() {
    const clientsChip = document.getElementById('chat-filter-clients');
    if (!clientsChip) return;

    clientsChip.classList.toggle('hidden', !_isProviderMode);
    if (!_isProviderMode && _activeFilter === 'clients') {
      _activeFilter = 'all';
      const allChip = document.querySelector('#chat-filters .filter-chip[data-filter="all"]');
      if (allChip) {
        document.querySelectorAll('#chat-filters .filter-chip').forEach((node) => node.classList.remove('active'));
        allChip.classList.add('active');
      }
    }
  }

  function _bindSearch() {
    const input = document.getElementById('chat-search');
    const clearBtn = document.getElementById('chat-search-clear');
    if (!input) return;

    input.addEventListener('input', (event) => {
      _searchQuery = (event.target.value || '').trim().toLowerCase();
      _toggleSearchClear(Boolean(_searchQuery));
      _render();
    });

    if (clearBtn) {
      clearBtn.addEventListener('click', () => {
        input.value = '';
        _searchQuery = '';
        _toggleSearchClear(false);
        input.focus();
        _render();
      });
    }
  }

  function _toggleSearchClear(show) {
    const btn = document.getElementById('chat-search-clear');
    if (!btn) return;
    btn.classList.toggle('hidden', !show);
  }

  function _bindRetry() {
    const retryBtn = document.getElementById('chats-retry');
    if (!retryBtn) return;
    retryBtn.addEventListener('click', () => _fetchThreads());
  }

  function _bindGlobalEvents() {
    if (_eventsBound) return;
    _eventsBound = true;

    document.addEventListener('click', () => _closeActionMenus());
    document.addEventListener('keydown', (event) => {
      if (event.key !== 'Escape') return;
      _closeActionMenus();
      _closeReportDialog();
    });
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
    const sep = path.includes('?') ? '&' : '?';
    return path + sep + 'mode=' + encodeURIComponent(mode);
  }

  function _threadUrl(threadId) {
    return _withMode('/chat/' + threadId + '/');
  }

  async function _startDirectChat(providerId) {
    const id = parseInt(providerId, 10);
    if (!id) {
      _fetchThreads();
      return;
    }

    const res = await ApiClient.request(_withMode('/api/messaging/direct/thread/'), {
      method: 'POST',
      body: { provider_id: id },
    });

    if (res.ok && res.data && res.data.id) {
      window.location.href = _threadUrl(res.data.id);
      return;
    }

    _fetchThreads();
  }

  function _showGate() {
    const gate = document.getElementById('auth-gate');
    const content = document.getElementById('chats-content');
    if (gate) gate.classList.remove('hidden');
    if (content) content.classList.add('hidden');
  }

  function _hideGate() {
    const gate = document.getElementById('auth-gate');
    const content = document.getElementById('chats-content');
    if (gate) gate.classList.add('hidden');
    if (content) content.classList.remove('hidden');
  }

  async function _fetchThreads() {
    _setLoading(true);
    _setError('');
    const profileState = await Auth.resolveProfile(false, _activeMode());
    if (!profileState.ok) {
      _setLoading(false);
      if (!Auth.isLoggedIn()) {
        _showGate();
        return;
      }
      _setError(_copy('sessionChecking'), 'sessionChecking');
      return;
    }

    try {
      const [threadsRes, statesRes] = await Promise.all([
        ApiClient.get(_withMode('/api/messaging/direct/threads/')),
        ApiClient.get(_withMode('/api/messaging/threads/states/')),
      ]);

      if (threadsRes.status === 401 || statesRes.status === 401) {
        const recovered = await Auth.resolveProfile(true, _activeMode());
        if (!recovered.ok && !Auth.isLoggedIn()) {
          _showGate();
          return;
        }
        _setError(_copy('sessionRefreshing'), 'sessionRefreshing');
        return;
      }

      if (!threadsRes.ok || !threadsRes.data) {
        _threads = [];
        _render();
        _setError(_extractError(threadsRes, _copy('loadFailed')), 'loadFailed');
        return;
      }

      const rawThreads = Array.isArray(threadsRes.data)
        ? threadsRes.data
        : (threadsRes.data.results || []);

      const stateMap = _threadStateMap(statesRes);
      _threads = rawThreads.map((thread) => _mergeThreadState(thread, stateMap.get(_threadId(thread))));
      _threads.sort((a, b) => _dateValue(b.last_message_at) - _dateValue(a.last_message_at));

      _render();
    } catch (_) {
      _threads = [];
      _render();
      _setError(_copy('loadUnexpected'), 'loadUnexpected');
    } finally {
      _setLoading(false);
    }
  }

  function _threadStateMap(statesRes) {
    const map = new Map();
    if (!statesRes || !statesRes.ok || !statesRes.data) return map;

    const list = Array.isArray(statesRes.data)
      ? statesRes.data
      : (statesRes.data.results || []);

    list.forEach((state) => {
      const threadId = Number(state && state.thread);
      if (!threadId) return;
      map.set(threadId, state);
    });

    return map;
  }

  function _mergeThreadState(thread, state) {
    const merged = Object.assign({}, thread);

    if (state) {
      merged.is_favorite = Boolean(state.is_favorite);
      merged.favorite_label = (state.favorite_label || '').trim();
      merged.client_label = (state.client_label || '').trim();
      merged.is_archived = Boolean(state.is_archived);
      merged.is_blocked = Boolean(state.is_blocked);
      return merged;
    }

    merged.is_favorite = Boolean(merged.is_favorite);
    merged.favorite_label = (merged.favorite_label || '').trim();
    merged.client_label = (merged.client_label || '').trim();
    merged.is_archived = Boolean(merged.is_archived);
    merged.is_blocked = Boolean(merged.is_blocked);
    return merged;
  }

  function _threadId(thread) {
    return Number(thread.thread_id || thread.id || 0);
  }

  function _visibleThreads() {
    return _threads.filter((thread) => !thread.is_blocked && !thread.is_archived);
  }

  function _buildCounts() {
    const visible = _visibleThreads();
    const unreadThreads = visible.filter((thread) => (thread.unread_count || 0) > 0).length;
    const unreadMessages = visible.reduce((sum, thread) => sum + Math.max(0, Number(thread.unread_count) || 0), 0);

    return {
      all: visible.length,
      unread: unreadThreads,
      favorite: visible.filter((thread) => thread.is_favorite).length,
      clients: visible.filter((thread) => _threadKind(thread, _peerDisplayName(thread)) === 'client').length,
      recent: visible.length,
      unreadMessages,
    };
  }

  function _getFiltered() {
    let list = _visibleThreads();

    if (_searchQuery) {
      list = list.filter((thread) => {
        const displayName = _peerDisplayName(thread).toLowerCase();
        const phone = (thread.peer_phone || '').toLowerCase();
        const favoriteLabel = _favoriteLabelDisplay(thread).toLowerCase();
        const clientLabel = _clientLabelDisplay(thread).toLowerCase();
        return (
          displayName.includes(_searchQuery)
          || phone.includes(_searchQuery)
          || favoriteLabel.includes(_searchQuery)
          || clientLabel.includes(_searchQuery)
        );
      });
    }

    switch (_activeFilter) {
      case 'unread':
        list = list.filter((thread) => (thread.unread_count || 0) > 0);
        break;
      case 'favorite':
        list = list.filter((thread) => thread.is_favorite);
        break;
      case 'clients':
        if (_isProviderMode) {
          list = list.filter((thread) => _threadKind(thread, _peerDisplayName(thread)) === 'client');
        }
        break;
      case 'recent':
        list.sort((a, b) => _dateValue(b.last_message_at) - _dateValue(a.last_message_at));
        return list;
      default:
        break;
    }

    list.sort((a, b) => {
      const aUnread = (a.unread_count || 0) > 0 ? 1 : 0;
      const bUnread = (b.unread_count || 0) > 0 ? 1 : 0;
      if (aUnread !== bUnread) return bUnread - aUnread;
      return _dateValue(b.last_message_at) - _dateValue(a.last_message_at);
    });

    return list;
  }

  function _dateValue(value) {
    const parsed = Date.parse(value || '');
    return Number.isFinite(parsed) ? parsed : 0;
  }

  function _render() {
    const container = document.getElementById('threads-list');
    const emptyEl = document.getElementById('chats-empty');
    const emptyText = document.getElementById('chats-empty-text');

    if (!container || !emptyEl) return;
    _closeActionMenus();

    const counts = _buildCounts();
    const list = _getFiltered();

    _renderCounters(counts, list.length);

    if (_isLoading) {
      container.innerHTML = _skeletonMarkup();
      emptyEl.classList.add('hidden');
      return;
    }

    container.innerHTML = '';

    if (!list.length) {
      emptyEl.classList.remove('hidden');
      if (emptyText) emptyText.textContent = _emptyMessage();
      return;
    }

    emptyEl.classList.add('hidden');
    const fragment = document.createDocumentFragment();
    list.forEach((thread) => fragment.appendChild(_buildThreadCard(thread)));
    container.appendChild(fragment);
  }

  function _renderCounters(counts, visibleCount) {
    const totalEl = document.getElementById('chats-total-count');
    const unreadEl = document.getElementById('chats-unread-count');
    const resultsEl = document.getElementById('chats-results-count');

    if (totalEl) totalEl.textContent = String(counts.all || 0);

    if (unreadEl) {
      const unreadCount = counts.unreadMessages || 0;
      unreadEl.textContent = _copy('unreadBadge', { count: unreadCount });
      unreadEl.classList.toggle('hidden', unreadCount <= 0);
    }

    if (resultsEl) {
      resultsEl.textContent = _copy(visibleCount === 1 ? 'resultsOne' : 'resultsMany', { count: visibleCount });
    }

    document.querySelectorAll('.chat-filter-count').forEach((node) => {
      const key = node.dataset.countFor || 'all';
      node.textContent = String(counts[key] || 0);
    });
  }

  function _emptyMessage() {
    if (_searchQuery) return _copy('emptySearch');

    switch (_activeFilter) {
      case 'unread':
        return _copy('emptyUnread');
      case 'favorite':
        return _copy('emptyFavorite');
      case 'clients':
        return _copy('emptyClients');
      case 'recent':
        return _copy('emptyRecent');
      default:
        return _copy('emptyDefault');
    }
  }

  function _skeletonMarkup() {
    return [
      '<div class="chat-thread-skeleton shimmer"></div>',
      '<div class="chat-thread-skeleton shimmer"></div>',
      '<div class="chat-thread-skeleton shimmer"></div>'
    ].join('');
  }

  function _buildThreadCard(thread) {
    const displayName = _peerDisplayName(thread);
    const threadId = _threadId(thread);
    const unreadCount = Math.max(0, Number(thread.unread_count) || 0);
    const lastMessage = _threadPreviewText(thread.last_message_text || thread.last_message || '');
    const kind = _threadKind(thread, displayName);
    const previewTone = _threadPreviewTone(thread, lastMessage, kind);

    const card = UI.el('article', {
      className: 'chat-thread-card'
        + ' kind-' + kind
        + (unreadCount > 0 ? ' unread' : '')
        + (thread.is_favorite ? ' favorite' : ''),
    });
    card.setAttribute('role', 'button');
    card.setAttribute('tabindex', '0');
    card.addEventListener('click', () => _openThread(threadId));
    card.addEventListener('keydown', (event) => {
      if (event.key !== 'Enter' && event.key !== ' ') return;
      event.preventDefault();
      _openThread(threadId);
    });

    const avatarWrap = UI.el('div', { className: 'thread-avatar-wrap' });
    const avatar = UI.el('div', { className: 'thread-avatar kind-' + kind });

    const peerImage = thread.peer_image || thread.peer_profile_image;
    if (peerImage) {
      avatar.appendChild(UI.lazyImg(ApiClient.mediaUrl(peerImage), displayName));
    } else {
      avatar.textContent = (displayName || _copy('unknownUser')).charAt(0);
    }

    const excellenceBadges = UI.normalizeExcellenceBadges(thread.peer_excellence_badges);
    if (excellenceBadges.length) {
      avatarWrap.appendChild(UI.el('span', {
        className: 'thread-avatar-excellence-top',
        textContent: excellenceBadges[0].name || excellenceBadges[0].code || _copy('excellenceFallback'),
      }));
    }

    if (unreadCount > 0) {
      avatarWrap.appendChild(UI.el('span', { className: 'thread-unread-dot', textContent: '' }));
    }
    avatarWrap.appendChild(avatar);

    const content = UI.el('div', { className: 'thread-content' });

    const topRow = UI.el('div', { className: 'thread-top-row' });
    const titleWrap = UI.el('div', { className: 'thread-title-wrap' });
    const nameWrap = UI.el('div', { className: 'thread-name-wrap' });
    const nameEl = UI.el('span', { className: 'thread-name', textContent: displayName || _copy('unknownUser') });
    _setAutoDirection(nameEl, displayName);
    nameWrap.appendChild(nameEl);

    const inlineExcellence = UI.buildExcellenceBadges(excellenceBadges, {
      className: 'excellence-badges compact thread-inline-excellence',
      compact: true,
      iconSize: 10,
    });
    if (inlineExcellence) nameWrap.appendChild(inlineExcellence);
    titleWrap.appendChild(nameWrap);

    const roleLabel = _threadRoleLabel(kind);
    if (roleLabel) {
      titleWrap.appendChild(UI.el('span', {
        className: 'thread-role-chip kind-' + kind,
        textContent: roleLabel,
      }));
    }

    const subtitle = _threadSubtitle(thread, kind);
    if (subtitle) {
      const subtitleEl = UI.el('div', { className: 'thread-subtitle', textContent: subtitle });
      _setAutoDirection(subtitleEl, subtitle);
      content.appendChild(subtitleEl);
    }

    topRow.appendChild(titleWrap);

    const trailing = UI.el('div', { className: 'thread-top-trailing' });
    if (thread.last_message_at) {
      trailing.appendChild(UI.el('span', {
        className: 'thread-time',
        textContent: _relativeTime(thread.last_message_at),
      }));
    }
    trailing.appendChild(_buildThreadActions(thread, displayName));
    topRow.appendChild(trailing);

    content.appendChild(topRow);

    const previewRow = UI.el('div', { className: 'thread-preview-row' });
    const previewLabel = _threadPreviewLabel(previewTone, kind);
    if (previewLabel) {
      previewRow.appendChild(UI.el('span', {
        className: 'thread-preview-pill accent-' + previewLabel.accent,
        textContent: previewLabel.text,
      }));
    }
    const previewTextEl = UI.el('p', { className: 'thread-last-msg', textContent: lastMessage });
    _setAutoDirection(previewTextEl, lastMessage);
    previewRow.appendChild(previewTextEl);
    content.appendChild(previewRow);

    const metaRow = UI.el('div', { className: 'thread-meta-row' });

    if (unreadCount > 0) {
      metaRow.appendChild(UI.el('span', {
        className: 'thread-unread-badge',
        textContent: _copy('unreadNew', { count: unreadCount }),
      }));
    }

    if (thread.is_favorite) {
      metaRow.appendChild(UI.el('span', {
        className: 'thread-favorite-chip',
        textContent: _favoriteLabelDisplay(thread) || _copy('favoriteChip'),
      }));
    }

    if (thread.client_label) {
      const clientLabelEl = UI.el('span', {
        className: 'thread-label-chip',
        textContent: _clientLabelDisplay(thread),
      });
      _setAutoDirection(clientLabelEl, _clientLabelDisplay(thread));
      metaRow.appendChild(clientLabelEl);
    }

    if (_meaningfulValue(thread.peer_city)) {
      const cityLabelEl = UI.el('span', {
        className: 'thread-label-chip city-chip',
        textContent: UI.formatCityDisplay(thread.peer_city),
      });
      _setAutoDirection(cityLabelEl, thread.peer_city);
      metaRow.appendChild(cityLabelEl);
    }

    const openHint = UI.el('span', {
      className: 'thread-open-hint',
      textContent: _copy('openMessages'),
    });
    metaRow.appendChild(openHint);

    content.appendChild(metaRow);

    card.appendChild(avatarWrap);
    card.appendChild(content);

    return card;
  }

  function _buildThreadActions(thread, displayName) {
    const threadId = _threadId(thread);
    const wrap = UI.el('div', { className: 'chats-thread-actions' });
    const menuBtn = UI.el('button', {
      type: 'button',
      className: 'chats-thread-menu-btn',
      title: _copy('messageOptions'),
      ariaLabel: _copy('messageOptions'),
    });
    menuBtn.innerHTML = [
      '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">',
      '<circle cx="12" cy="5" r="1.5"></circle>',
      '<circle cx="12" cy="12" r="1.5"></circle>',
      '<circle cx="12" cy="19" r="1.5"></circle>',
      '</svg>',
    ].join('');

    const menu = UI.el('div', { className: 'chats-thread-menu hidden' });
    menu.addEventListener('click', (event) => event.stopPropagation());

    const canMarkRead = (Number(thread.unread_count) || 0) > 0;
    menu.appendChild(_buildThreadMenuItem(
      canMarkRead ? _copy('markRead') : _copy('markUnread'),
      async () => {
        if (canMarkRead) await _markThreadRead(threadId);
        else await _markThreadUnread(threadId);
      }
    ));
    menu.appendChild(_buildThreadMenuItem(
      thread.is_favorite ? _copy('removeFavorite') : _copy('addFavorite'),
      async () => _toggleFavoriteState(threadId)
    ));
    menu.appendChild(_buildThreadMenuItem(
      thread.is_blocked ? _copy('unblock') : _copy('block'),
      async () => _toggleBlockState(threadId),
      true
    ));
    menu.appendChild(_buildThreadMenuItem(
      _copy('report'),
      async () => _openReportDialog(thread, displayName),
      true
    ));
    menu.appendChild(_buildThreadMenuItem(
      thread.is_archived ? _copy('unarchive') : _copy('archive'),
      async () => _toggleArchiveState(threadId)
    ));

    menuBtn.addEventListener('click', (event) => {
      event.preventDefault();
      event.stopPropagation();
      _toggleActionMenu(threadId, menu);
    });
    menuBtn.addEventListener('keydown', (event) => {
      if (event.key !== 'Enter' && event.key !== ' ') return;
      event.preventDefault();
      event.stopPropagation();
      _toggleActionMenu(threadId, menu);
    });

    wrap.appendChild(menuBtn);
    wrap.appendChild(menu);
    return wrap;
  }

  function _buildThreadMenuItem(label, onClick, danger) {
    const item = UI.el('button', {
      type: 'button',
      className: 'chats-thread-menu-item' + (danger ? ' danger' : ''),
      textContent: label,
    });
    item.addEventListener('click', async (event) => {
      event.preventDefault();
      event.stopPropagation();
      _closeActionMenus();
      await onClick();
    });
    return item;
  }

  function _toggleActionMenu(threadId, menuEl) {
    if (!menuEl) return;
    const currentlyOpen = _activeMenuThreadId === threadId && menuEl.classList.contains('open');
    _closeActionMenus();
    if (currentlyOpen) return;
    _activeMenuThreadId = threadId;
    menuEl.classList.remove('hidden');
    requestAnimationFrame(() => menuEl.classList.add('open'));
  }

  function _closeActionMenus() {
    _activeMenuThreadId = null;
    document.querySelectorAll('.chats-thread-menu').forEach((menu) => {
      menu.classList.remove('open');
      menu.classList.add('hidden');
    });
  }

  function _openThread(threadId) {
    if (!threadId) return;
    window.location.href = _threadUrl(threadId);
  }

  function _findThreadIndex(threadId) {
    const target = Number(threadId);
    return _threads.findIndex((thread) => _threadId(thread) === target);
  }

  async function _markThreadRead(threadId) {
    const index = _findThreadIndex(threadId);
    if (index < 0) return;
    if ((Number(_threads[index].unread_count) || 0) === 0) return;

    const res = await ApiClient.request(
      _withMode('/api/messaging/direct/thread/' + threadId + '/messages/read/'),
      { method: 'POST' }
    );
    if (!res.ok) {
      _showToast(_extractError(res, _copy('markReadFailed')), 'error');
      return;
    }

    _threads[index].unread_count = 0;
    _render();
    window.dispatchEvent(new Event('nw:badge-refresh'));
    _showToast(_copy('markedRead'), 'success');
  }

  async function _markThreadUnread(threadId) {
    const index = _findThreadIndex(threadId);
    if (index < 0) return;
    const res = await ApiClient.request(
      _withMode('/api/messaging/thread/' + threadId + '/unread/'),
      { method: 'POST' }
    );
    if (!res.ok) {
      _showToast(_extractError(res, _copy('markReadFailed')), 'error');
      return;
    }

    _threads[index].unread_count = Math.max(1, Number(_threads[index].unread_count) || 0);
    _render();
    window.dispatchEvent(new Event('nw:badge-refresh'));
    _showToast(_copy('markedUnread'), 'success');
  }

  async function _toggleFavoriteState(threadId) {
    const index = _findThreadIndex(threadId);
    if (index < 0) return;
    const remove = !!_threads[index].is_favorite;
    const res = await ApiClient.request(_withMode('/api/messaging/thread/' + threadId + '/favorite/'), {
      method: 'POST',
      body: remove ? { action: 'remove' } : {},
    });
    if (!res.ok) {
      _showToast(_extractError(res, _copy('favoriteFailed')), 'error');
      return;
    }

    _threads[index].is_favorite = !!res.data?.is_favorite;
    _threads[index].favorite_label = String(res.data?.favorite_label || _threads[index].favorite_label || '').trim();
    _render();
    _showToast(remove ? _copy('favoriteRemoved') : _copy('favoriteAdded'), 'success');
  }

  async function _toggleArchiveState(threadId) {
    const index = _findThreadIndex(threadId);
    if (index < 0) return;
    const remove = !!_threads[index].is_archived;
    if (!remove && !window.confirm(_copy('archiveConfirm'))) return;

    const res = await ApiClient.request(_withMode('/api/messaging/thread/' + threadId + '/archive/'), {
      method: 'POST',
      body: remove ? { action: 'remove' } : {},
    });
    if (!res.ok) {
      _showToast(_extractError(res, _copy('archiveFailed')), 'error');
      return;
    }

    _threads[index].is_archived = !!res.data?.is_archived;
    _render();
    _showToast(remove ? _copy('archiveRemoved') : _copy('archiveAdded'), 'success');
  }

  async function _toggleBlockState(threadId) {
    const index = _findThreadIndex(threadId);
    if (index < 0) return;
    const remove = !!_threads[index].is_blocked;
    const msg = remove
      ? _copy('unblockConfirm')
      : _copy('blockConfirm');
    if (!window.confirm(msg)) return;

    const res = await ApiClient.request(_withMode('/api/messaging/thread/' + threadId + '/block/'), {
      method: 'POST',
      body: remove ? { action: 'remove' } : {},
    });
    if (!res.ok) {
      _showToast(_extractError(res, _copy('blockFailed')), 'error');
      return;
    }

    _threads[index].is_blocked = !!res.data?.is_blocked;
    _render();
    _showToast(_threads[index].is_blocked ? _copy('blocked') : _copy('unblocked'), 'success');
  }

  function _openReportDialog(thread, displayName) {
    _closeReportDialog();
    const threadId = _threadId(thread);
    if (!threadId) return;

    const reasons = [
      { value: 'محتوى غير لائق', label: _copy('reportReasonInappropriate') },
      { value: 'احتيال أو نصب', label: _copy('reportReasonFraud') },
      { value: 'إزعاج أو مضايقة', label: _copy('reportReasonHarassment') },
      { value: 'انتحال شخصية', label: _copy('reportReasonImpersonation') },
      { value: 'محتوى مخالف للشروط', label: _copy('reportReasonTerms') },
      { value: 'أخرى', label: _copy('reportReasonOther') },
    ];

    const backdrop = UI.el('div', { className: 'chats-report-backdrop' });
    const dialog = UI.el('div', { className: 'chats-report-dialog' });
    dialog.setAttribute('role', 'dialog');
    dialog.setAttribute('aria-modal', 'true');
    dialog.setAttribute('aria-label', _copy('reportDialogTitle'));

    dialog.appendChild(UI.el('h3', { textContent: _copy('reportDialogTitle') }));
    const peerInfo = UI.el('div', { className: 'chats-report-peer', textContent: displayName || _copy('unknownUser') });
    _setAutoDirection(peerInfo, displayName);
    dialog.appendChild(peerInfo);

    dialog.appendChild(UI.el('label', { textContent: _copy('reportReasonLabel') }));
    const reasonSelect = UI.el('select', { className: 'chats-report-select' });
    reasons.forEach((reason) => {
      reasonSelect.appendChild(UI.el('option', { value: reason.value, textContent: reason.label }));
    });
    dialog.appendChild(reasonSelect);

    dialog.appendChild(UI.el('label', { textContent: _copy('reportDetailsLabel') }));
    const detailsInput = UI.el('textarea', {
      className: 'chats-report-textarea',
      rows: '4',
      placeholder: _copy('reportDetailsPlaceholder'),
      maxLength: '500',
    });
    dialog.appendChild(detailsInput);

    const actions = UI.el('div', { className: 'chats-report-actions' });
    const cancelBtn = UI.el('button', {
      type: 'button',
      className: 'chats-report-btn ghost',
      textContent: _copy('reportCancel'),
    });
    const sendBtn = UI.el('button', {
      type: 'button',
      className: 'chats-report-btn primary',
      textContent: _copy('reportSend'),
    });
    actions.appendChild(cancelBtn);
    actions.appendChild(sendBtn);
    dialog.appendChild(actions);
    backdrop.appendChild(dialog);

    const close = () => {
      document.removeEventListener('keydown', onKeyDown);
      backdrop.classList.remove('open');
      window.setTimeout(() => {
        if (backdrop.parentNode) backdrop.remove();
      }, 160);
      if (_reportDialogState && _reportDialogState.backdrop === backdrop) {
        _reportDialogState = null;
      }
    };

    const onKeyDown = (event) => {
      if (event.key !== 'Escape') return;
      event.preventDefault();
      close();
    };

    cancelBtn.addEventListener('click', close);
    backdrop.addEventListener('click', (event) => {
      if (event.target === backdrop) close();
    });
    document.addEventListener('keydown', onKeyDown);

    sendBtn.addEventListener('click', async () => {
      const reason = String(reasonSelect.value || '').trim();
      if (!reason) {
        _showToast(_copy('reportChooseReason'), 'error');
        return;
      }
      sendBtn.disabled = true;
      sendBtn.textContent = _copy('reportSending');
      const details = String(detailsInput.value || '').trim();
      const res = await ApiClient.request(_withMode('/api/messaging/thread/' + threadId + '/report/'), {
        method: 'POST',
        body: {
          reason,
          details: details || undefined,
          reported_label: displayName || undefined,
        },
      });
      sendBtn.disabled = false;
      sendBtn.textContent = _copy('reportSend');

      if (!res.ok) {
        _showToast(_extractError(res, _copy('reportFailed')), 'error');
        return;
      }
      close();
      _showToast(_copy('reportSuccess'), 'success');
    });

    document.body.appendChild(backdrop);
    requestAnimationFrame(() => backdrop.classList.add('open'));
    _reportDialogState = { backdrop, close };
  }

  function _closeReportDialog() {
    if (_reportDialogState && typeof _reportDialogState.close === 'function') {
      _reportDialogState.close();
    }
  }

  function _peerDisplayName(thread) {
    const first = (thread.peer_first_name || '').trim();
    const last = (thread.peer_last_name || '').trim();
    const full = (first + ' ' + last).trim();

    if (full) return full;
    if ((thread.peer_name || '').trim()) return thread.peer_name.trim();
    if ((thread.peer_username || '').trim()) return thread.peer_username.trim();

    return (thread.peer_phone || '').trim() || _copy('unknownUser');
  }

  function _threadKind(thread, displayName) {
    if (_isPlatformTeamName(displayName)) return 'team';
    if (Number(thread.peer_provider_id) > 0) return 'provider';
    if (_isProviderMode) return 'client';
    return 'member';
  }

  function _threadRoleLabel(kind) {
    if (kind === 'team') return _copy('teamRole');
    if (kind === 'provider') return _copy('providerRole');
    if (kind === 'client') return _copy('clientRole');
    return '';
  }

  function _threadSubtitle(thread, kind) {
    if (kind === 'team') return _copy('teamSubtitle');
    if (kind === 'provider') return _meaningfulValue(thread.peer_city)
      ? _copy('providerInCity', { city: UI.formatCityDisplay(thread.peer_city) })
      : _copy('providerSubtitle');
    if (kind === 'client') return _meaningfulValue(thread.client_label)
      ? _clientLabelDisplay(thread)
      : _copy('clientSubtitle');
    return _copy('directSubtitle');
  }

  function _favoriteLabelDisplay(thread) {
    const normalized = String(thread?.favorite_label || '').trim().toLowerCase();
    if (normalized === 'potential_client') return '';
    if (normalized === 'important_conversation') return _copy('favoriteChip');
    if (normalized === 'incomplete_contact') return _copy('incompleteContact');
    return String(thread?.favorite_label || '').trim();
  }

  function _clientLabelDisplay(thread) {
    const normalized = String(thread?.client_label || '').trim().toLowerCase();
    if (normalized === 'potential') return '';
    if (normalized === 'current') return _copy('currentClient');
    if (normalized === 'past') return _copy('pastClient');
    return String(thread?.client_label || '').trim();
  }

  function _threadPreviewTone(thread, previewText, kind) {
    if (kind === 'team') return 'team';
    if ((previewText || '').indexOf('🛠️') === 0) return 'service';
    return 'default';
  }

  function _threadPreviewLabel(previewTone, kind) {
    if (previewTone === 'team') return { text: _copy('teamPreview'), accent: 'violet' };
    if (previewTone === 'service') return { text: _copy('serviceRequest'), accent: 'amber' };
    if (kind === 'provider') return { text: _copy('directPreview'), accent: 'blue' };
    return null;
  }

  function _threadPreviewText(rawText) {
    const text = (rawText || '').toString().trim();
    if (!text) return _copy('noMessagesYet');

    if (
      /(https?:\/\/[^\s]+|\/service-request\/[^\s]*)/i.test(text)
      && /service-request/i.test(text)
      && /provider_id=\d+/i.test(text)
    ) {
      return _copy('directServiceRequestPreview');
    }

    return text;
  }

  function _meaningfulValue(value) {
    return String(value || '').trim().length > 0;
  }

  function _isPlatformTeamName(name) {
    const normalized = String(name || '').trim();
    return normalized.startsWith('فريق ') || normalized.toLowerCase().startsWith('team ');
  }

  function _relativeTime(dateStr) {
    const ts = Date.parse(dateStr || '');
    if (!Number.isFinite(ts)) return '';
    const dt = new Date(ts);
    const now = new Date();
    const diffMs = now.getTime() - dt.getTime();
    const diffMinutes = Math.floor(diffMs / 60000);
    if (diffMinutes < 1) return _copy('justNow');
    if (diffMinutes < 60) return _copy('minutesAgo', { count: diffMinutes });

    const diffDays = Math.floor(diffMs / 86400000);
    if (diffDays < 1) {
      return dt.toLocaleTimeString(_locale(), { hour: 'numeric', minute: '2-digit' });
    }
    if (diffDays === 1) return _copy('yesterday');
    if (diffDays < 7) {
      return dt.toLocaleDateString(_locale(), { weekday: 'long' });
    }
    return dt.toLocaleDateString(_locale(), { day: 'numeric', month: 'numeric', year: 'numeric' });
  }

  function _setLoading(value) {
    _isLoading = Boolean(value);
    _render();
  }

  function _setError(message, copyKey) {
    const errorEl = document.getElementById('chats-error');
    const retryBtn = document.getElementById('chats-retry');
    if (!errorEl) return;

    _lastErrorMessage = message || '';
    _lastErrorCopyKey = copyKey || '';

    if (!message) {
      errorEl.classList.add('hidden');
      errorEl.textContent = '';
      if (retryBtn) retryBtn.classList.add('hidden');
      return;
    }

    errorEl.textContent = message;
    errorEl.classList.remove('hidden');
    if (retryBtn) retryBtn.classList.remove('hidden');
  }

  function _showToast(message, type) {
    if (!message) return;
    const existing = document.getElementById('chats-toast');
    if (existing) existing.remove();
    const toast = UI.el('div', {
      id: 'chats-toast',
      className: 'chats-toast' + (type ? (' ' + type) : ''),
      textContent: message,
    });
    document.body.appendChild(toast);
    requestAnimationFrame(() => toast.classList.add('show'));
    window.clearTimeout(_toastTimer);
    _toastTimer = window.setTimeout(() => {
      toast.classList.remove('show');
      window.setTimeout(() => {
        if (toast.parentNode) toast.remove();
      }, 180);
    }, 2400);
  }

  function _extractError(res, fallback) {
    const body = (res && res.data) || {};
    return body.detail || body.message || body.error || fallback;
  }

  function _handleLanguageChange() {
    _applyStaticCopy();
    if (_lastErrorMessage) {
      _setError(_lastErrorCopyKey ? _copy(_lastErrorCopyKey) : _lastErrorMessage, _lastErrorCopyKey);
    }
    _render();
  }

  function _applyStaticCopy() {
    if (window.NawafethI18n && typeof window.NawafethI18n.t === 'function') {
      document.title = window.NawafethI18n.t('siteTitle') + ' — ' + _copy('pageTitle');
    }

    _setText('chats-auth-title', _copy('authTitle'));
    _setText('chats-auth-desc', _copy('authDesc'));
    _setText('chats-auth-cta', _copy('authCta'));
    _setText('chats-page-title', _copy('pageHeading'));
    _setText('chats-page-subtitle', _copy('pageSubtitle'));
    _setText('chats-hero-tag-direct', _copy('heroTagDirect'));
    _setText('chats-hero-tag-team', _copy('heroTagTeam'));
    _setText('chats-hero-tag-safe', _copy('heroTagSafe'));
    _setText('chats-list-title', _copy('listTitle'));
    _setText('chat-filter-all-label', _copy('filterAll'));
    _setText('chat-filter-unread-label', _copy('filterUnread'));
    _setText('chat-filter-favorite-label', _copy('filterFavorite'));
    _setText('chat-filter-clients-label', _copy('filterClients'));
    _setText('chat-filter-recent-label', _copy('filterRecent'));
    _setText('chats-empty-text', _emptyMessage());
    _setText('chats-retry', _copy('retry'));
    _setAttr('chat-search', 'placeholder', _copy('searchPlaceholder'));
    _setAttr('chat-search-clear', 'aria-label', _copy('clearSearch'));
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
    if (!key) return bundle;
    const value = Object.prototype.hasOwnProperty.call(bundle, key) ? bundle[key] : COPY.ar[key];
    return _replaceTokens(value, replacements);
  }

  function _replaceTokens(text, replacements) {
    if (typeof text !== 'string' || !replacements) return text;
    return text.replace(/\{(\w+)\}/g, (_, key) => (
      Object.prototype.hasOwnProperty.call(replacements, key) ? String(replacements[key]) : ''
    ));
  }

  function _setText(id, value) {
    const el = document.getElementById(id);
    if (el) el.textContent = value == null ? '' : String(value);
  }

  function _setAttr(id, name, value) {
    const el = document.getElementById(id);
    if (el) el.setAttribute(name, value == null ? '' : String(value));
  }

  function _setAutoDirection(el, value) {
    if (!el) return;
    if (String(value || '').trim()) el.setAttribute('dir', 'auto');
    else el.removeAttribute('dir');
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
