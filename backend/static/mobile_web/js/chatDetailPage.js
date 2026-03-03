/* ===================================================================
   chatDetailPage.js — Single chat thread detail
   GET  /api/messaging/direct/thread/<id>/messages/
   POST /api/messaging/direct/thread/<id>/messages/send/
   POST /api/messaging/direct/thread/<id>/messages/read/
   =================================================================== */
'use strict';

const ChatDetailPage = (() => {
  let _threadId = null;
  let _messages = [];
  let _myUserId = null;
  let _pollTimer = null;
  let _ws = null;
  let _wsConnected = false;
  let _wsReconnectTimer = null;
  let _pendingByClientId = new Map();

  function _setConnectionStatus(connected) {
    const statusEl = document.getElementById('peer-status');
    if (!statusEl) return;
    statusEl.textContent = connected ? 'متصل' : 'غير متصل';
    statusEl.classList.toggle('is-online', !!connected);
    statusEl.classList.toggle('is-offline', !connected);
  }

  function init() {
    if (!Auth.isLoggedIn()) { window.location.href = '/login/?next=' + encodeURIComponent(window.location.pathname); return; }

    const match = window.location.pathname.match(/\/chat\/(\d+)/);
    if (!match) { window.location.href = '/chats/'; return; }
    _threadId = match[1];
    _myUserId = parseInt(sessionStorage.getItem('nw_user_id')) || 0;

    // Send message
    document.getElementById('btn-send').addEventListener('click', _sendMessage);
    document.getElementById('msg-input').addEventListener('keydown', e => {
      if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); _sendMessage(); }
    });

    _loadMessages();
    _markRead();
    _setConnectionStatus(false);
    _connectWebSocket();
    _startPollingFallback();
  }

  function _startPollingFallback() {
    if (_pollTimer) clearInterval(_pollTimer);
    _pollTimer = setInterval(() => {
      if (!_wsConnected) _loadMessages();
    }, 5000);
  }

  function _buildWsUrl(token) {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    return protocol + '//' + window.location.host + '/ws/thread/' + _threadId + '/?token=' + encodeURIComponent(token);
  }

  function _connectWebSocket() {
    const token = Auth.getAccessToken();
    if (!token || _wsConnected) return;
    try {
      _ws = new WebSocket(_buildWsUrl(token));
    } catch {
      _scheduleReconnect();
      return;
    }

    _ws.onopen = () => {
      _wsConnected = true;
      _setConnectionStatus(true);
      if (_wsReconnectTimer) {
        clearTimeout(_wsReconnectTimer);
        _wsReconnectTimer = null;
      }
      _markRead();
    };

    _ws.onmessage = (event) => {
      let payload;
      try {
        payload = JSON.parse(event.data);
      } catch {
        return;
      }

      if (payload?.type === 'message') {
        _upsertIncomingMessage(payload);
        if (payload.sender_id !== _myUserId) _markRead();
        window.dispatchEvent(new Event('nw:badge-refresh'));
      }
      if (payload?.type === 'read') {
        window.dispatchEvent(new Event('nw:badge-refresh'));
      }
    };

    _ws.onerror = () => {
      _wsConnected = false;
      _setConnectionStatus(false);
    };

    _ws.onclose = () => {
      _wsConnected = false;
      _setConnectionStatus(false);
      _ws = null;
      _scheduleReconnect();
    };
  }

  function _scheduleReconnect() {
    if (_wsReconnectTimer) return;
    _wsReconnectTimer = setTimeout(() => {
      _wsReconnectTimer = null;
      _connectWebSocket();
    }, 3000);
  }

  function _upsertIncomingMessage(payload) {
    const msgId = parseInt(payload.id, 10);
    const clientId = payload.client_id || null;

    if (clientId && _pendingByClientId.has(clientId)) {
      const tempId = _pendingByClientId.get(clientId);
      _pendingByClientId.delete(clientId);
      const idx = _messages.findIndex(m => m.id === tempId);
      const mapped = {
        id: msgId,
        sender_id: payload.sender_id,
        text: payload.text || '',
        created_at: payload.sent_at || new Date().toISOString(),
      };
      if (idx >= 0) {
        _messages[idx] = mapped;
      } else {
        _messages.push(mapped);
      }
      _renderMessages();
      return;
    }

    if (Number.isFinite(msgId) && _messages.some(m => parseInt(m.id, 10) === msgId)) {
      return;
    }

    _messages.push({
      id: msgId,
      sender_id: payload.sender_id,
      text: payload.text || '',
      created_at: payload.sent_at || new Date().toISOString(),
    });
    _renderMessages();
  }

  async function _loadMessages() {
    const res = await ApiClient.get('/api/messaging/direct/thread/' + _threadId + '/messages/');
    if (!res.ok) return;

    const list = Array.isArray(res.data) ? res.data : (res.data.results || []);

    // Update peer info from first message if available
    if (list.length && !document.getElementById('peer-name').dataset.loaded) {
      const sample = list[0];
      const peerId = sample.sender_id === _myUserId ? sample.receiver_id : sample.sender_id;
      const peerName = sample.sender_id === _myUserId
        ? (sample.receiver_name || 'مستخدم')
        : (sample.sender_name || 'مستخدم');
      document.getElementById('peer-name').textContent = peerName;
      document.getElementById('peer-name').dataset.loaded = '1';
    }

    // Only re-render if count changed
    if (list.length !== _messages.length) {
      _messages = list;
      _renderMessages();
    }
  }

  function _renderMessages() {
    const container = document.getElementById('chat-messages');
    container.innerHTML = '';

    if (!_messages.length) {
      container.innerHTML = '<div class="empty-hint" style="padding:40px"><div class="empty-icon">💬</div><p>ابدأ المحادثة الآن</p></div>';
      return;
    }

    const frag = document.createDocumentFragment();

    // Messages in chronological order
    const sorted = [..._messages].sort((a, b) => new Date(a.created_at || a.timestamp) - new Date(b.created_at || b.timestamp));

    sorted.forEach(msg => {
      const isMine = msg.sender_id === _myUserId || msg.sender === _myUserId;
      const bubble = UI.el('div', { className: 'msg-bubble ' + (isMine ? 'mine' : 'theirs') });

      bubble.appendChild(UI.el('div', { className: 'msg-text', textContent: msg.text || msg.content || msg.body || '' }));

      if (msg.created_at || msg.timestamp) {
        const dt = new Date(msg.created_at || msg.timestamp);
        bubble.appendChild(UI.el('div', {
          className: 'msg-time',
          textContent: dt.toLocaleTimeString('ar-SA', { hour: '2-digit', minute: '2-digit' })
        }));
      }

      frag.appendChild(bubble);
    });

    container.appendChild(frag);

    // Scroll to bottom
    container.scrollTop = container.scrollHeight;
  }

  async function _sendMessage() {
    const input = document.getElementById('msg-input');
    const text = input.value.trim();
    if (!text) return;

    input.value = '';
    input.focus();

    const clientId = 'web-' + Date.now() + '-' + Math.random().toString(16).slice(2, 8);
    const tempId = -Date.now();

    // Optimistic add
    const tempMsg = {
      id: tempId,
      sender_id: _myUserId,
      text: text,
      created_at: new Date().toISOString(),
    };
    _messages.push(tempMsg);
    _pendingByClientId.set(clientId, tempId);
    _renderMessages();

    if (_wsConnected && _ws && _ws.readyState === WebSocket.OPEN) {
      try {
        _ws.send(JSON.stringify({ type: 'message', text, client_id: clientId }));
        return;
      } catch {
        _pendingByClientId.delete(clientId);
      }
    }

    const res = await ApiClient.request('/api/messaging/direct/thread/' + _threadId + '/messages/send/', {
      method: 'POST',
      body: { text },
    });

    if (!res.ok) {
      // Remove temp message on failure
      _messages = _messages.filter(m => m.id !== tempId);
      _pendingByClientId.delete(clientId);
      _renderMessages();
      return;
    }

    // Fallback mode sent successfully via REST; sync latest state
    _pendingByClientId.delete(clientId);
    _loadMessages();

    window.dispatchEvent(new Event('nw:badge-refresh'));
  }

  async function _markRead() {
    await ApiClient.request('/api/messaging/direct/thread/' + _threadId + '/messages/read/', { method: 'POST' });
    window.dispatchEvent(new Event('nw:badge-refresh'));
  }

  // Cleanup on page leave
  window.addEventListener('beforeunload', () => {
    if (_pollTimer) clearInterval(_pollTimer);
    if (_wsReconnectTimer) clearTimeout(_wsReconnectTimer);
    if (_ws) {
      try { _ws.close(); } catch {}
    }
  });

  // Boot
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
  return {};
})();
