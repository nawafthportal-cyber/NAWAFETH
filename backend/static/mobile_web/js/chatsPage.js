/* ===================================================================
   chatsPage.js — Chat threads list controller
   GET /api/messaging/direct/threads/
   =================================================================== */
'use strict';

const ChatsPage = (() => {
  let _threads = [];
  let _activeFilter = 'all';
  let _searchQuery = '';
  let _isLoading = false;
  let _isProviderMode = false;
  let _activeMenuThreadId = null;
  let _toastTimer = null;
  let _reportDialogState = null;
  let _eventsBound = false;

  function init() {
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

    try {
      const [threadsRes, statesRes] = await Promise.all([
        ApiClient.get(_withMode('/api/messaging/direct/threads/')),
        ApiClient.get(_withMode('/api/messaging/threads/states/')),
      ]);

      if (threadsRes.status === 401 || statesRes.status === 401) {
        _showGate();
        return;
      }

      if (!threadsRes.ok || !threadsRes.data) {
        _threads = [];
        _render();
        _setError(_extractError(threadsRes, 'تعذر تحميل المحادثات حالياً.'));
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
      _setError('حدث خطأ غير متوقع أثناء تحميل المحادثات. حاول مرة أخرى.');
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
      clients: visible.filter((thread) => String(thread.client_label || '').trim().length > 0).length,
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
        return (
          displayName.includes(_searchQuery)
          || phone.includes(_searchQuery)
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
          list = list.filter((thread) => String(thread.client_label || '').trim().length > 0);
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
      unreadEl.textContent = unreadCount + ' غير مقروء';
      unreadEl.classList.toggle('hidden', unreadCount <= 0);
    }

    if (resultsEl) {
      resultsEl.textContent = visibleCount + (visibleCount === 1 ? ' نتيجة' : ' نتائج');
    }

    document.querySelectorAll('.chat-filter-count').forEach((node) => {
      const key = node.dataset.countFor || 'all';
      node.textContent = String(counts[key] || 0);
    });
  }

  function _emptyMessage() {
    if (_searchQuery) return 'لا توجد نتائج مطابقة للبحث.';

    switch (_activeFilter) {
      case 'unread':
        return 'لا توجد محادثات غير مقروءة.';
      case 'favorite':
        return 'لا توجد محادثات مفضلة.';
      case 'clients':
        return 'لا توجد محادثات عملاء حالياً.';
      case 'recent':
        return 'لا توجد محادثات حديثة حالياً.';
      default:
        return 'لا توجد محادثات بعد.';
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

    const card = UI.el('article', {
      className: 'chat-thread-card'
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
    const avatar = UI.el('div', { className: 'thread-avatar' });

    const peerImage = thread.peer_image || thread.peer_profile_image;
    if (peerImage) {
      avatar.appendChild(UI.lazyImg(ApiClient.mediaUrl(peerImage), displayName));
    } else {
      avatar.textContent = (displayName || 'م').charAt(0);
    }

    const excellenceBadges = UI.normalizeExcellenceBadges(thread.peer_excellence_badges);
    if (excellenceBadges.length) {
      avatarWrap.appendChild(UI.el('span', {
        className: 'thread-avatar-excellence-top',
        textContent: excellenceBadges[0].name || excellenceBadges[0].code || 'تميز',
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
    nameWrap.appendChild(UI.el('span', { className: 'thread-name', textContent: displayName || 'مستخدم' }));

    const inlineExcellence = UI.buildExcellenceBadges(excellenceBadges, {
      className: 'excellence-badges compact thread-inline-excellence',
      compact: true,
      iconSize: 10,
    });
    if (inlineExcellence) nameWrap.appendChild(inlineExcellence);
    titleWrap.appendChild(nameWrap);

    if (thread.peer_provider_id) {
      titleWrap.appendChild(UI.el('span', { className: 'thread-role-chip', textContent: 'مزود خدمة' }));
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
    content.appendChild(UI.el('p', { className: 'thread-last-msg', textContent: lastMessage }));

    const metaRow = UI.el('div', { className: 'thread-meta-row' });

    if (unreadCount > 0) {
      metaRow.appendChild(UI.el('span', {
        className: 'thread-unread-badge',
        textContent: unreadCount + ' جديد',
      }));
    }

    if (thread.is_favorite) {
      metaRow.appendChild(UI.el('span', {
        className: 'thread-favorite-chip',
        textContent: thread.favorite_label || 'مفضلة',
      }));
    }

    if (thread.client_label) {
      metaRow.appendChild(UI.el('span', {
        className: 'thread-label-chip',
        textContent: thread.client_label,
      }));
    }

    const openHint = UI.el('span', {
      className: 'thread-open-hint',
      textContent: 'فتح المحادثة',
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
      title: 'خيارات المحادثة',
      ariaLabel: 'خيارات المحادثة',
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
      canMarkRead ? 'اجعلها مقروءة' : 'اجعلها غير مقروءة',
      async () => {
        if (canMarkRead) await _markThreadRead(threadId);
        else await _markThreadUnread(threadId);
      }
    ));
    menu.appendChild(_buildThreadMenuItem(
      thread.is_favorite ? 'إزالة من المفضلة' : 'إضافة للمفضلة',
      async () => _toggleFavoriteState(threadId)
    ));
    menu.appendChild(_buildThreadMenuItem(
      thread.is_blocked ? 'إلغاء الحظر' : 'حظر',
      async () => _toggleBlockState(threadId),
      true
    ));
    menu.appendChild(_buildThreadMenuItem(
      'إبلاغ',
      async () => _openReportDialog(thread, displayName),
      true
    ));
    menu.appendChild(_buildThreadMenuItem(
      thread.is_archived ? 'إلغاء الأرشفة' : 'أرشفة',
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
      _showToast(_extractError(res, 'تعذر تحديث حالة القراءة'), 'error');
      return;
    }

    _threads[index].unread_count = 0;
    _render();
    window.dispatchEvent(new Event('nw:badge-refresh'));
    _showToast('تم تحديد المحادثة كمقروءة', 'success');
  }

  async function _markThreadUnread(threadId) {
    const index = _findThreadIndex(threadId);
    if (index < 0) return;
    const res = await ApiClient.request(
      _withMode('/api/messaging/thread/' + threadId + '/unread/'),
      { method: 'POST' }
    );
    if (!res.ok) {
      _showToast(_extractError(res, 'تعذر تحديث حالة القراءة'), 'error');
      return;
    }

    _threads[index].unread_count = Math.max(1, Number(_threads[index].unread_count) || 0);
    _render();
    window.dispatchEvent(new Event('nw:badge-refresh'));
    _showToast('تم تحديد المحادثة كغير مقروءة', 'success');
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
      _showToast(_extractError(res, 'تعذر تحديث المفضلة'), 'error');
      return;
    }

    _threads[index].is_favorite = !!res.data?.is_favorite;
    _threads[index].favorite_label = String(res.data?.favorite_label || _threads[index].favorite_label || '').trim();
    _render();
    _showToast(remove ? 'تمت إزالة المحادثة من المفضلة' : 'تمت إضافة المحادثة للمفضلة', 'success');
  }

  async function _toggleArchiveState(threadId) {
    const index = _findThreadIndex(threadId);
    if (index < 0) return;
    const remove = !!_threads[index].is_archived;
    if (!remove && !window.confirm('أرشفة هذه المحادثة؟ سيتم إخفاؤها من قائمة المحادثات.')) return;

    const res = await ApiClient.request(_withMode('/api/messaging/thread/' + threadId + '/archive/'), {
      method: 'POST',
      body: remove ? { action: 'remove' } : {},
    });
    if (!res.ok) {
      _showToast(_extractError(res, 'تعذر تحديث الأرشفة'), 'error');
      return;
    }

    _threads[index].is_archived = !!res.data?.is_archived;
    _render();
    _showToast(remove ? 'تم إلغاء أرشفة المحادثة' : 'تمت أرشفة المحادثة', 'success');
  }

  async function _toggleBlockState(threadId) {
    const index = _findThreadIndex(threadId);
    if (index < 0) return;
    const remove = !!_threads[index].is_blocked;
    const msg = remove
      ? 'هل تريد إلغاء الحظر عن هذا العضو؟'
      : 'هل أنت متأكد من حظر هذا العضو؟ لن يتمكن من مراسلتك.';
    if (!window.confirm(msg)) return;

    const res = await ApiClient.request(_withMode('/api/messaging/thread/' + threadId + '/block/'), {
      method: 'POST',
      body: remove ? { action: 'remove' } : {},
    });
    if (!res.ok) {
      _showToast(_extractError(res, 'تعذر تحديث حالة الحظر'), 'error');
      return;
    }

    _threads[index].is_blocked = !!res.data?.is_blocked;
    _render();
    _showToast(_threads[index].is_blocked ? 'تم حظر العضو' : 'تم إلغاء الحظر', 'success');
  }

  function _openReportDialog(thread, displayName) {
    _closeReportDialog();
    const threadId = _threadId(thread);
    if (!threadId) return;

    const reasons = [
      'محتوى غير لائق',
      'احتيال أو نصب',
      'إزعاج أو مضايقة',
      'انتحال شخصية',
      'محتوى مخالف للشروط',
      'أخرى',
    ];

    const backdrop = UI.el('div', { className: 'chats-report-backdrop' });
    const dialog = UI.el('div', { className: 'chats-report-dialog' });
    dialog.setAttribute('role', 'dialog');
    dialog.setAttribute('aria-modal', 'true');
    dialog.setAttribute('aria-label', 'إبلاغ عن محادثة');

    dialog.appendChild(UI.el('h3', { textContent: 'إبلاغ عن محادثة' }));
    const peerInfo = UI.el('div', { className: 'chats-report-peer', textContent: displayName || 'مستخدم' });
    dialog.appendChild(peerInfo);

    dialog.appendChild(UI.el('label', { textContent: 'سبب الإبلاغ:' }));
    const reasonSelect = UI.el('select', { className: 'chats-report-select' });
    reasons.forEach((reason) => {
      reasonSelect.appendChild(UI.el('option', { value: reason, textContent: reason }));
    });
    dialog.appendChild(reasonSelect);

    dialog.appendChild(UI.el('label', { textContent: 'تفاصيل إضافية (اختياري):' }));
    const detailsInput = UI.el('textarea', {
      className: 'chats-report-textarea',
      rows: '4',
      placeholder: 'اكتب التفاصيل هنا...',
      maxLength: '500',
    });
    dialog.appendChild(detailsInput);

    const actions = UI.el('div', { className: 'chats-report-actions' });
    const cancelBtn = UI.el('button', {
      type: 'button',
      className: 'chats-report-btn ghost',
      textContent: 'إلغاء',
    });
    const sendBtn = UI.el('button', {
      type: 'button',
      className: 'chats-report-btn primary',
      textContent: 'إرسال البلاغ',
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
        _showToast('اختر سبب الإبلاغ أولاً', 'error');
        return;
      }
      sendBtn.disabled = true;
      sendBtn.textContent = 'جارٍ الإرسال...';
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
      sendBtn.textContent = 'إرسال البلاغ';

      if (!res.ok) {
        _showToast(_extractError(res, 'تعذر إرسال البلاغ'), 'error');
        return;
      }
      close();
      _showToast('تم إرسال البلاغ للإدارة. شكراً لك', 'success');
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

    return (thread.peer_phone || '').trim();
  }

  function _threadPreviewText(rawText) {
    const text = (rawText || '').toString().trim();
    if (!text) return 'لا توجد رسائل بعد';

    if (
      /(https?:\/\/[^\s]+|\/service-request\/[^\s]*)/i.test(text)
      && /service-request/i.test(text)
      && /provider_id=\d+/i.test(text)
    ) {
      return '🛠️ طلب خدمة مباشر';
    }

    return text;
  }

  function _relativeTime(dateStr) {
    const ts = Date.parse(dateStr || '');
    if (!Number.isFinite(ts)) return '';
    const dt = new Date(ts);
    const now = new Date();
    const diffMs = now.getTime() - dt.getTime();
    const diffMinutes = Math.floor(diffMs / 60000);
    if (diffMinutes < 1) return 'الآن';
    if (diffMinutes < 60) return 'منذ ' + diffMinutes + ' د';

    const diffDays = Math.floor(diffMs / 86400000);
    if (diffDays < 1) {
      const h24 = dt.getHours();
      const h = h24 > 12 ? h24 - 12 : h24;
      const amPm = h24 >= 12 ? 'م' : 'ص';
      const m = String(dt.getMinutes()).padStart(2, '0');
      return h + ':' + m + ' ' + amPm;
    }
    if (diffDays === 1) return 'الأمس';
    if (diffDays < 7) {
      const days = ['الأحد', 'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];
      return days[dt.getDay()];
    }
    return dt.getDate() + '/' + (dt.getMonth() + 1) + '/' + dt.getFullYear();
  }

  function _setLoading(value) {
    _isLoading = Boolean(value);
    _render();
  }

  function _setError(message) {
    const errorEl = document.getElementById('chats-error');
    const retryBtn = document.getElementById('chats-retry');
    if (!errorEl) return;

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

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  return {};
})();
