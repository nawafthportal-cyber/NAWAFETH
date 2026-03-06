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

  function init() {
    if (!Auth.isLoggedIn()) {
      _showGate();
      return;
    }
    _hideGate();

    _bindFilters();
    _bindSearch();

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

  function _activeMode() {
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
      window.location.href = '/chat/' + res.data.id + '/';
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
        const preview = (thread.last_message_text || thread.last_message || '').toLowerCase();
        const clientLabel = (thread.client_label || '').toLowerCase();
        const favoriteLabel = (thread.favorite_label || '').toLowerCase();
        return (
          displayName.includes(_searchQuery)
          || phone.includes(_searchQuery)
          || preview.includes(_searchQuery)
          || clientLabel.includes(_searchQuery)
          || favoriteLabel.includes(_searchQuery)
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

    const card = UI.el('a', {
      className: 'chat-thread-card'
        + (unreadCount > 0 ? ' unread' : '')
        + (thread.is_favorite ? ' favorite' : ''),
      href: '/chat/' + threadId + '/',
    });

    const avatarWrap = UI.el('div', { className: 'thread-avatar-wrap' });
    const avatar = UI.el('div', { className: 'thread-avatar' });

    const peerImage = thread.peer_image || thread.peer_profile_image;
    if (peerImage) {
      avatar.appendChild(UI.lazyImg(ApiClient.mediaUrl(peerImage), displayName));
    } else {
      avatar.textContent = (displayName || 'م').charAt(0);
    }

    if (unreadCount > 0) {
      avatarWrap.appendChild(UI.el('span', { className: 'thread-unread-dot', textContent: '' }));
    }
    avatarWrap.appendChild(avatar);

    const content = UI.el('div', { className: 'thread-content' });

    const topRow = UI.el('div', { className: 'thread-top-row' });
    const titleWrap = UI.el('div', { className: 'thread-title-wrap' });
    titleWrap.appendChild(UI.el('span', { className: 'thread-name', textContent: displayName || 'مستخدم' }));

    if (thread.peer_provider_id) {
      titleWrap.appendChild(UI.el('span', { className: 'thread-role-chip', textContent: 'مزود خدمة' }));
    }

    topRow.appendChild(titleWrap);

    if (thread.last_message_at) {
      topRow.appendChild(UI.el('span', {
        className: 'thread-time',
        textContent: _relativeTime(thread.last_message_at),
      }));
    }

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
      return 'طلب خدمة مباشر';
    }

    if (text.length > 110) {
      return text.slice(0, 108) + '...';
    }

    return text;
  }

  function _relativeTime(dateStr) {
    const ts = Date.parse(dateStr || '');
    if (!Number.isFinite(ts)) return '';

    const diff = Math.floor((Date.now() - ts) / 1000);
    if (diff < 60) return 'الآن';
    if (diff < 3600) return Math.floor(diff / 60) + ' د';
    if (diff < 86400) return Math.floor(diff / 3600) + ' س';
    if (diff < 604800) return Math.floor(diff / 86400) + ' ي';

    return new Date(ts).toLocaleDateString('ar-SA', {
      day: 'numeric',
      month: 'short',
    });
  }

  function _setLoading(value) {
    _isLoading = Boolean(value);
    _render();
  }

  function _setError(message) {
    const errorEl = document.getElementById('chats-error');
    if (!errorEl) return;

    if (!message) {
      errorEl.classList.add('hidden');
      errorEl.textContent = '';
      return;
    }

    errorEl.textContent = message;
    errorEl.classList.remove('hidden');
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
