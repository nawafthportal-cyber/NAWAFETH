/* ===================================================================
   chatsPage.js — Chat threads list controller
   GET /api/messaging/direct/threads/
   =================================================================== */
'use strict';

const ChatsPage = (() => {
  let _threads = [];
  let _activeFilter = 'all';
  let _searchQuery = '';

  function init() {
    if (!Auth.isLoggedIn()) { _showGate(); return; }
    _hideGate();

    const params = new URLSearchParams(window.location.search);
    const startProviderId = params.get('start') || params.get('provider_id');
    if (startProviderId) {
      _startDirectChat(startProviderId);
      return;
    }

    // Filter chips
    document.getElementById('chat-filters').addEventListener('click', e => {
      const chip = e.target.closest('.filter-chip');
      if (!chip) return;
      document.querySelectorAll('#chat-filters .filter-chip').forEach(c => c.classList.remove('active'));
      chip.classList.add('active');
      _activeFilter = chip.dataset.filter || 'all';
      _render();
    });

    // Search
    document.getElementById('chat-search').addEventListener('input', e => {
      _searchQuery = e.target.value.trim().toLowerCase();
      _render();
    });

    _fetchThreads();
  }

  async function _startDirectChat(providerId) {
    const id = parseInt(providerId, 10);
    if (!id) {
      _fetchThreads();
      return;
    }
    const res = await ApiClient.request('/api/messaging/direct/thread/', {
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
    const g = document.getElementById('auth-gate');
    const c = document.getElementById('chats-content');
    if (g) g.classList.remove('hidden');
    if (c) c.classList.add('hidden');
  }
  function _hideGate() {
    const g = document.getElementById('auth-gate');
    const c = document.getElementById('chats-content');
    if (g) g.classList.add('hidden');
    if (c) c.classList.remove('hidden');
  }

  async function _fetchThreads() {
    const res = await ApiClient.get('/api/messaging/direct/threads/');
    if (res.ok && res.data) {
      _threads = Array.isArray(res.data) ? res.data : (res.data.results || []);
      _render();
    } else if (res.status === 401) {
      _showGate();
    }
  }

  function _getFiltered() {
    let list = [..._threads];

    // Exclude blocked & archived
    list = list.filter(t => !t.is_blocked && !t.is_archived);

    // Search
    if (_searchQuery) {
      list = list.filter(t =>
        _peerDisplayName(t).toLowerCase().includes(_searchQuery) ||
        (t.peer_phone || '').includes(_searchQuery)
      );
    }

    // Filter
    switch (_activeFilter) {
      case 'unread':
        list = list.filter(t => (t.unread_count || 0) > 0);
        break;
      case 'favorite':
        list = list.filter(t => t.is_favorite);
        break;
      case 'recent':
        list.sort((a, b) => new Date(b.last_message_at || 0) - new Date(a.last_message_at || 0));
        return list;
    }

    // Unread first, then by date
    list.sort((a, b) => {
      if ((a.unread_count || 0) > 0 && (b.unread_count || 0) === 0) return -1;
      if ((a.unread_count || 0) === 0 && (b.unread_count || 0) > 0) return 1;
      return new Date(b.last_message_at || 0) - new Date(a.last_message_at || 0);
    });

    return list;
  }

  function _render() {
    const container = document.getElementById('threads-list');
    const emptyEl = document.getElementById('chats-empty');
    const list = _getFiltered();
    container.innerHTML = '';

    if (!list.length) {
      emptyEl.classList.remove('hidden');
      return;
    }
    emptyEl.classList.add('hidden');

    const frag = document.createDocumentFragment();
    list.forEach(t => frag.appendChild(_buildThreadCard(t)));
    container.appendChild(frag);
  }

  function _buildThreadCard(thread) {
    const displayName = _peerDisplayName(thread);
    const threadId = thread.thread_id || thread.id;
    const card = UI.el('a', {
      className: 'thread-card' + ((thread.unread_count || 0) > 0 ? ' unread' : ''),
      href: '/chat/' + threadId + '/',
    });

    // Avatar
    const avatar = UI.el('div', { className: 'thread-avatar' });
    const peerImg = thread.peer_image || thread.peer_profile_image;
    if (peerImg) {
      avatar.appendChild(UI.lazyImg(ApiClient.mediaUrl(peerImg), ''));
    } else {
      avatar.textContent = (displayName || '؟').charAt(0);
    }
    card.appendChild(avatar);

    // Content
    const content = UI.el('div', { className: 'thread-content' });

    const topRow = UI.el('div', { className: 'thread-top-row' });
    topRow.appendChild(UI.el('span', { className: 'thread-name', textContent: displayName || 'مستخدم' }));
    if (thread.last_message_at) {
      topRow.appendChild(UI.el('span', { className: 'thread-time', textContent: _relativeTime(thread.last_message_at) }));
    }
    content.appendChild(topRow);

    const bottomRow = UI.el('div', { className: 'thread-bottom-row' });
    bottomRow.appendChild(UI.el('span', {
      className: 'thread-last-msg',
      textContent: thread.last_message_text || thread.last_message || 'لا توجد رسائل'
    }));
    if ((thread.unread_count || 0) > 0) {
      bottomRow.appendChild(UI.el('span', { className: 'thread-unread-badge', textContent: thread.unread_count }));
    }
    if (thread.is_favorite) {
      bottomRow.appendChild(UI.icon('star', 14, '#FFC107'));
    }
    content.appendChild(bottomRow);

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

  function _relativeTime(dateStr) {
    const now = new Date();
    const dt = new Date(dateStr);
    const diff = Math.floor((now - dt) / 1000);
    if (diff < 60) return 'الآن';
    if (diff < 3600) return Math.floor(diff / 60) + ' د';
    if (diff < 86400) return Math.floor(diff / 3600) + ' س';
    if (diff < 604800) return Math.floor(diff / 86400) + ' ي';
    return dt.toLocaleDateString('ar-SA', { day: 'numeric', month: 'short' });
  }

  // Boot
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
  return {};
})();
