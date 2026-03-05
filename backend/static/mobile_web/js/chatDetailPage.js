/* ===================================================================
   chatDetailPage.js — Modernized direct thread detail
   =================================================================== */
'use strict';

const ChatDetailPage = (() => {
  const state = {
    threadId: null,
    messages: [],
    myUserId: 0,
    isLoading: false,
    isSending: false,
    pollTimer: null,
    ws: null,
    wsConnected: false,
    wsReconnectTimer: null,
    pendingByClientId: new Map(),
    pendingAttachment: null,
    peer: {
      name: 'مستخدم',
      phone: 'غير متوفر',
      city: 'غير متوفر',
      avatar: '',
      id: null,
      providerId: null,
    },
    threadState: {
      is_favorite: false,
      is_archived: false,
      is_blocked: false,
      blocked_by_other: false,
    },
  };

  const dom = {};

  function init() {
    if (!Auth.isLoggedIn()) {
      window.location.href = '/login/?next=' + encodeURIComponent(window.location.pathname);
      return;
    }

    const match = window.location.pathname.match(/\/chat\/(\d+)/);
    if (!match) {
      window.location.href = '/chats/';
      return;
    }
    state.threadId = parseInt(match[1], 10);
    state.myUserId = _toInt(Auth.getUserId()) || 0;

    _cacheDom();
    _bindEvents();
    _setConnectionStatus('offline');
    _renderPeer();
    _updateSendButtonState();
    _boot();
  }

  async function _boot() {
    await Promise.all([
      _loadThreadMeta(),
      _loadThreadState(),
      _loadMessages({ showLoader: true, forceScroll: true }),
    ]);

    _markRead();
    _connectWebSocket();
    _startPollingFallback();
  }

  function _cacheDom() {
    dom.peerAvatar = document.getElementById('peer-avatar');
    dom.peerName = document.getElementById('peer-name');
    dom.peerStatus = document.getElementById('peer-status');
    dom.peerCardName = document.getElementById('peer-card-name');
    dom.peerCardPhone = document.getElementById('peer-card-phone');
    dom.peerCardCity = document.getElementById('peer-card-city');
    dom.favoriteIndicator = document.getElementById('chat-favorite-indicator');
    dom.banner = document.getElementById('chat-thread-banner');

    dom.btnFavorite = document.getElementById('btn-chat-fav');
    dom.btnOptions = document.getElementById('btn-chat-options');
    dom.actionFavorite = document.getElementById('chat-action-favorite');
    dom.actionBlock = document.getElementById('chat-action-block');
    dom.actionArchive = document.getElementById('chat-action-archive');

    dom.sheetBackdrop = document.getElementById('chat-sheet-backdrop');
    dom.optionsSheet = document.getElementById('chat-options-sheet');
    dom.reportBackdrop = document.getElementById('chat-report-backdrop');
    dom.reportDialog = document.getElementById('chat-report-dialog');
    dom.reportReason = document.getElementById('chat-report-reason');
    dom.reportDetails = document.getElementById('chat-report-details');
    dom.btnReportCancel = document.getElementById('btn-report-cancel');
    dom.btnReportSend = document.getElementById('btn-report-send');

    dom.loader = document.getElementById('messages-loader');
    dom.error = document.getElementById('messages-error');
    dom.errorText = document.getElementById('messages-error-text');
    dom.empty = document.getElementById('messages-empty');
    dom.messages = document.getElementById('chat-messages');
    dom.btnRetry = document.getElementById('btn-retry-load');

    dom.inputWrap = document.getElementById('chat-input-wrap');
    dom.attachPreview = document.getElementById('chat-attachment-preview');
    dom.btnAttach = document.getElementById('btn-attach');
    dom.fileInput = document.getElementById('msg-file-input');
    dom.msgInput = document.getElementById('msg-input');
    dom.btnSend = document.getElementById('btn-send');
    dom.toast = document.getElementById('chat-toast');
  }

  function _bindEvents() {
    dom.btnSend?.addEventListener('click', _sendMessage);
    dom.msgInput?.addEventListener('keydown', _onInputKeyDown);
    dom.msgInput?.addEventListener('input', () => {
      _autoGrowInput();
      _updateSendButtonState();
    });

    dom.btnAttach?.addEventListener('click', () => dom.fileInput?.click());
    dom.fileInput?.addEventListener('change', () => {
      const file = dom.fileInput.files && dom.fileInput.files[0];
      if (!file) return;
      state.pendingAttachment = {
        file,
        type: _detectAttachmentType(file),
      };
      _renderAttachmentPreview();
      _updateSendButtonState();
    });

    dom.btnRetry?.addEventListener('click', () => _loadMessages({ showLoader: true, forceScroll: false }));
    dom.btnFavorite?.addEventListener('click', () => _toggleFavorite());
    dom.btnOptions?.addEventListener('click', _openOptionsSheet);

    dom.sheetBackdrop?.addEventListener('click', _closeOptionsSheet);
    dom.optionsSheet?.addEventListener('click', (event) => {
      const actionBtn = event.target.closest('[data-chat-action]');
      if (!actionBtn) return;
      _handleChatAction(actionBtn.getAttribute('data-chat-action'));
    });

    dom.reportBackdrop?.addEventListener('click', _closeReportDialog);
    dom.btnReportCancel?.addEventListener('click', _closeReportDialog);
    dom.btnReportSend?.addEventListener('click', _submitReport);

    document.addEventListener('keydown', (event) => {
      if (event.key !== 'Escape') return;
      _closeOptionsSheet();
      _closeReportDialog();
    });

    window.addEventListener('beforeunload', _cleanup);
  }

  function _cleanup() {
    if (state.pollTimer) clearInterval(state.pollTimer);
    if (state.wsReconnectTimer) clearTimeout(state.wsReconnectTimer);
    if (state.ws) {
      try { state.ws.close(); } catch (_) {}
    }
  }

  async function _loadThreadMeta() {
    const res = await ApiClient.get('/api/messaging/direct/threads/');
    if (!res.ok || !res.data) return;

    const list = Array.isArray(res.data) ? res.data : (res.data.results || []);
    const thread = list.find((t) => String(t.thread_id || t.id) === String(state.threadId));
    if (!thread) return;

    const name = _trim(thread.peer_name) || _joinName(thread.peer_first_name, thread.peer_last_name) || _trim(thread.peer_username) || 'مستخدم';
    state.peer = {
      name,
      phone: _trim(thread.peer_phone) || 'غير متوفر',
      city: _trim(thread.peer_city) || 'غير متوفر',
      avatar: _trim(thread.peer_image || thread.peer_profile_image),
      id: _toInt(thread.peer_id),
      providerId: _toInt(thread.peer_provider_id),
    };

    if (typeof thread.is_favorite === 'boolean') state.threadState.is_favorite = thread.is_favorite;
    if (typeof thread.is_archived === 'boolean') state.threadState.is_archived = thread.is_archived;
    if (typeof thread.is_blocked === 'boolean') state.threadState.is_blocked = thread.is_blocked;

    _renderPeer();
    _renderThreadState();
  }

  async function _loadThreadState() {
    const res = await ApiClient.get('/api/messaging/thread/' + state.threadId + '/state/');
    if (!res.ok || !res.data) return;

    state.threadState = {
      is_favorite: !!res.data.is_favorite,
      is_archived: !!res.data.is_archived,
      is_blocked: !!res.data.is_blocked,
      blocked_by_other: !!res.data.blocked_by_other,
    };

    _renderThreadState();
  }

  async function _loadMessages(opts = {}) {
    if (state.isLoading) return;
    state.isLoading = true;
    if (opts.showLoader) _showViewState('loading');

    const res = await ApiClient.get('/api/messaging/direct/thread/' + state.threadId + '/messages/?limit=80&offset=0');
    state.isLoading = false;

    if (!res.ok || !res.data) {
      _showViewState('error', _extractError(res, 'تعذر تحميل الرسائل حالياً'));
      return;
    }

    const rawList = Array.isArray(res.data) ? res.data : (res.data.results || []);
    const normalized = rawList.map(_normalizeMessage).filter((m) => m && Number.isFinite(m.id));
    normalized.sort((a, b) => _messageSortValue(a) - _messageSortValue(b));
    state.messages = normalized;

    _hydratePeerFromMessages(rawList);
    _renderMessages({ forceScroll: !!opts.forceScroll });
  }

  function _hydratePeerFromMessages(rawList) {
    if (!_isDefaultPeerName(state.peer.name) || !rawList.length) return;

    for (let i = 0; i < rawList.length; i += 1) {
      const raw = rawList[i] || {};
      const senderId = _toInt(raw.sender_id || raw.sender);
      if (senderId && senderId !== state.myUserId && _trim(raw.sender_name)) {
        state.peer.name = _trim(raw.sender_name);
        _renderPeer();
        return;
      }
      if (senderId && senderId === state.myUserId && _trim(raw.receiver_name)) {
        state.peer.name = _trim(raw.receiver_name);
        _renderPeer();
        return;
      }
    }
  }

  function _normalizeMessage(raw) {
    const id = _toInt(raw.id);
    const senderId = _toInt(raw.sender_id || raw.sender);
    const createdAt = raw.created_at || raw.sent_at || raw.timestamp || new Date().toISOString();
    const text = (raw.body || raw.text || raw.content || '').toString();
    const readByIds = Array.isArray(raw.read_by_ids)
      ? raw.read_by_ids.map(_toInt).filter((v) => Number.isFinite(v))
      : [];

    return {
      id,
      senderId,
      text,
      createdAt,
      readByIds,
      attachmentUrl: _trim(raw.attachment_url),
      attachmentType: _trim(raw.attachment_type),
      attachmentName: _trim(raw.attachment_name),
    };
  }

  function _messageSortValue(msg) {
    const dt = new Date(msg.createdAt);
    const t = dt.getTime();
    return Number.isFinite(t) ? t : (msg.id || 0);
  }

  function _showViewState(mode, errText) {
    dom.loader?.classList.add('hidden');
    dom.error?.classList.add('hidden');
    dom.empty?.classList.add('hidden');
    dom.messages?.classList.add('hidden');

    if (mode === 'loading') dom.loader?.classList.remove('hidden');
    if (mode === 'error') {
      if (dom.errorText) dom.errorText.textContent = errText || 'تعذر تحميل الرسائل حالياً';
      dom.error?.classList.remove('hidden');
    }
    if (mode === 'empty') dom.empty?.classList.remove('hidden');
    if (mode === 'messages') dom.messages?.classList.remove('hidden');
  }

  function _renderPeer() {
    if (dom.peerName) dom.peerName.textContent = state.peer.name || 'مستخدم';
    if (dom.peerCardName) dom.peerCardName.textContent = state.peer.name || 'مستخدم';
    if (dom.peerCardPhone) dom.peerCardPhone.textContent = state.peer.phone || 'غير متوفر';
    if (dom.peerCardCity) dom.peerCardCity.textContent = state.peer.city || 'غير متوفر';

    if (!dom.peerAvatar) return;
    dom.peerAvatar.innerHTML = '';
    if (state.peer.avatar) {
      dom.peerAvatar.appendChild(UI.lazyImg(ApiClient.mediaUrl(state.peer.avatar), state.peer.name || ''));
      return;
    }
    dom.peerAvatar.textContent = (state.peer.name || 'م').trim().charAt(0) || 'م';
  }

  function _renderThreadState() {
    const isFavorite = !!state.threadState.is_favorite;
    dom.btnFavorite?.classList.toggle('active', isFavorite);
    dom.favoriteIndicator?.classList.toggle('hidden', !isFavorite);

    if (dom.actionFavorite) {
      const label = dom.actionFavorite.querySelector('span');
      if (label) label.textContent = isFavorite ? 'إزالة من المفضلة' : 'إضافة للمفضلة';
    }
    if (dom.actionArchive) {
      const label = dom.actionArchive.querySelector('span');
      if (label) label.textContent = state.threadState.is_archived ? 'إلغاء الأرشفة' : 'أرشفة المحادثة';
    }
    if (dom.actionBlock) {
      const label = dom.actionBlock.querySelector('span');
      if (label) label.textContent = state.threadState.is_blocked ? 'إلغاء الحظر' : 'حظر العضو';
    }

    if (state.threadState.blocked_by_other) {
      _showBanner('لا يمكنك إرسال رسائل لأن الطرف الآخر قام بحظرك.', 'danger');
      _setComposerDisabled(true);
      return;
    }
    if (state.threadState.is_blocked) {
      _showBanner('قمت بحظر هذا العضو. أزل الحظر من خيارات المحادثة للمتابعة.', 'danger');
      _setComposerDisabled(true);
      return;
    }
    if (state.threadState.is_archived) _showBanner('هذه المحادثة مؤرشفة وستعود تلقائياً عند إرسال رسالة جديدة.', 'info');
    else _hideBanner();

    _setComposerDisabled(false);
  }

  function _showBanner(text, kind) {
    if (!dom.banner) return;
    dom.banner.textContent = text;
    dom.banner.classList.remove('hidden', 'is-danger', 'is-info');
    dom.banner.classList.add(kind === 'danger' ? 'is-danger' : 'is-info');
  }

  function _hideBanner() {
    if (!dom.banner) return;
    dom.banner.classList.add('hidden');
    dom.banner.textContent = '';
  }

  function _setComposerDisabled(disabled) {
    dom.msgInput.disabled = disabled;
    dom.btnAttach.disabled = disabled;
    dom.inputWrap?.classList.toggle('is-disabled', disabled);
    _updateSendButtonState();
  }

  function _renderMessages(opts = {}) {
    if (!dom.messages) return;

    if (!state.messages.length) {
      dom.messages.innerHTML = '';
      _showViewState('empty');
      return;
    }

    const keepBottom = opts.forceScroll || _isNearBottom();
    dom.messages.innerHTML = '';
    _showViewState('messages');

    const frag = document.createDocumentFragment();
    let lastDayKey = '';

    state.messages.forEach((msg, index) => {
      const dayKey = _dayKey(msg.createdAt);
      if (dayKey && dayKey !== lastDayKey) {
        frag.appendChild(_buildDayDivider(msg.createdAt));
        lastDayKey = dayKey;
      }

      const prev = index > 0 ? state.messages[index - 1] : null;
      const next = index < state.messages.length - 1 ? state.messages[index + 1] : null;
      frag.appendChild(_buildMessageNode(msg, prev, next));
    });

    dom.messages.appendChild(frag);
    if (keepBottom) _scrollToBottom();
  }

  function _buildDayDivider(isoDate) {
    const divider = UI.el('div', { className: 'chat-day-divider' });
    divider.appendChild(UI.el('span', { textContent: _formatDayLabel(isoDate) }));
    return divider;
  }

  function _buildMessageNode(msg, prev, next) {
    const mine = msg.senderId === state.myUserId;
    const row = UI.el('div', { className: 'msg-row ' + (mine ? 'mine' : 'theirs') });
    const bubble = UI.el('div', { className: 'msg-bubble ' + (mine ? 'mine' : 'theirs') });

    bubble.classList.toggle('group-prev', _canGroup(prev, msg));
    bubble.classList.toggle('group-next', _canGroup(msg, next));

    const attachmentNode = _buildAttachmentNode(msg);
    if (attachmentNode) bubble.appendChild(attachmentNode);
    if (msg.text) bubble.appendChild(UI.el('div', { className: 'msg-text', textContent: msg.text }));

    const meta = UI.el('div', { className: 'msg-meta' });
    meta.appendChild(UI.el('span', { className: 'msg-time', textContent: _formatTime(msg.createdAt) }));
    if (mine) {
      const read = _isReadByPeer(msg);
      meta.appendChild(UI.el('span', {
        className: 'msg-read-state ' + (read ? 'read' : 'sent'),
        textContent: read ? '✓✓' : '✓',
      }));
    }
    bubble.appendChild(meta);
    row.appendChild(bubble);
    return row;
  }

  function _buildAttachmentNode(msg) {
    if (!msg.attachmentUrl) return null;
    const url = ApiClient.mediaUrl(msg.attachmentUrl);
    if (!url) return null;

    if (msg.attachmentType === 'image') {
      const link = UI.el('a', {
        className: 'msg-attachment msg-attachment-image',
        href: url,
        target: '_blank',
        rel: 'noopener',
      });
      link.appendChild(UI.lazyImg(url, msg.attachmentName || 'صورة مرفقة'));
      return link;
    }

    if (msg.attachmentType === 'audio') {
      const wrap = UI.el('div', { className: 'msg-attachment msg-attachment-audio' });
      wrap.appendChild(UI.el('audio', { controls: 'controls', preload: 'none', src: url }));
      if (msg.attachmentName) wrap.appendChild(UI.el('div', { className: 'msg-attachment-name', textContent: msg.attachmentName }));
      return wrap;
    }

    const fileLink = UI.el('a', {
      className: 'msg-attachment msg-attachment-file',
      href: url,
      target: '_blank',
      rel: 'noopener',
    });
    fileLink.appendChild(UI.el('span', { className: 'msg-attachment-icon', textContent: '📎' }));
    fileLink.appendChild(UI.el('span', { className: 'msg-attachment-name', textContent: msg.attachmentName || 'مرفق' }));
    return fileLink;
  }

  function _isReadByPeer(msg) {
    if (!Array.isArray(msg.readByIds)) return false;
    return msg.readByIds.some((id) => Number.isFinite(id) && id !== state.myUserId);
  }

  function _canGroup(a, b) {
    if (!a || !b) return false;
    if (a.senderId !== b.senderId) return false;
    const aMs = new Date(a.createdAt).getTime();
    const bMs = new Date(b.createdAt).getTime();
    if (!Number.isFinite(aMs) || !Number.isFinite(bMs)) return false;
    if (_dayKey(a.createdAt) !== _dayKey(b.createdAt)) return false;
    return Math.abs(aMs - bMs) <= 4 * 60 * 1000;
  }

  function _isNearBottom() {
    if (!dom.messages) return true;
    return (dom.messages.scrollHeight - dom.messages.scrollTop - dom.messages.clientHeight) < 80;
  }

  function _scrollToBottom() {
    if (!dom.messages) return;
    dom.messages.scrollTop = dom.messages.scrollHeight;
  }

  function _onInputKeyDown(event) {
    if (event.key !== 'Enter' || event.shiftKey) return;
    event.preventDefault();
    _sendMessage();
  }

  function _autoGrowInput() {
    if (!dom.msgInput) return;
    dom.msgInput.style.height = 'auto';
    dom.msgInput.style.height = Math.min(dom.msgInput.scrollHeight, 120) + 'px';
  }

  function _updateSendButtonState() {
    const hasText = !!_trim(dom.msgInput?.value);
    const hasAttachment = !!state.pendingAttachment;
    const blocked = !!state.threadState.is_blocked || !!state.threadState.blocked_by_other;
    const disabled = state.isSending || blocked || (!hasText && !hasAttachment);

    if (dom.btnSend) {
      dom.btnSend.disabled = disabled;
      dom.btnSend.classList.toggle('is-loading', state.isSending);
    }
  }

  async function _sendMessage() {
    if (state.isSending) return;

    const text = _trim(dom.msgInput.value);
    const attachment = state.pendingAttachment;
    if (!text && !attachment) return;

    if (state.threadState.blocked_by_other || state.threadState.is_blocked) {
      _showToast('لا يمكن الإرسال لأن هذه المحادثة محظورة.', 'error');
      return;
    }

    state.isSending = true;
    _updateSendButtonState();

    if (attachment) {
      await _sendAttachmentMessage(text, attachment);
      state.isSending = false;
      _updateSendButtonState();
      return;
    }

    dom.msgInput.value = '';
    _autoGrowInput();
    _updateSendButtonState();

    const clientId = 'web-' + Date.now() + '-' + Math.random().toString(16).slice(2, 8);
    const tempId = -Date.now();
    state.pendingByClientId.set(clientId, tempId);
    state.messages.push({
      id: tempId,
      senderId: state.myUserId,
      text,
      createdAt: new Date().toISOString(),
      readByIds: [],
      attachmentUrl: '',
      attachmentType: '',
      attachmentName: '',
    });
    _renderMessages({ forceScroll: true });

    let sentViaWs = false;
    if (state.wsConnected && state.ws && state.ws.readyState === WebSocket.OPEN) {
      try {
        state.ws.send(JSON.stringify({ type: 'message', text, client_id: clientId }));
        sentViaWs = true;
      } catch (_) {
        sentViaWs = false;
      }
    }

    if (!sentViaWs) {
      const sent = await _sendTextFallback(text, tempId, clientId);
      if (!sent) {
        state.messages = state.messages.filter((m) => m.id !== tempId);
        state.pendingByClientId.delete(clientId);
        _renderMessages({ forceScroll: true });
      }
    }

    state.isSending = false;
    _updateSendButtonState();
  }

  async function _sendAttachmentMessage(text, attachment) {
    const formData = new FormData();
    if (text) formData.append('body', text);
    formData.append('attachment_type', attachment.type || 'file');
    formData.append('attachment', attachment.file);

    const res = await ApiClient.request('/api/messaging/direct/thread/' + state.threadId + '/messages/send/', {
      method: 'POST',
      body: formData,
      formData: true,
    });

    if (!res.ok) {
      _showToast(_extractError(res, 'تعذر إرسال المرفق'), 'error');
      return;
    }

    dom.msgInput.value = '';
    _autoGrowInput();
    _clearPendingAttachment();
    await _loadMessages({ forceScroll: true });
    _showToast('تم إرسال الرسالة', 'success');
    window.dispatchEvent(new Event('nw:badge-refresh'));
  }

  async function _sendTextFallback(text, tempId, clientId) {
    const res = await ApiClient.request('/api/messaging/direct/thread/' + state.threadId + '/messages/send/', {
      method: 'POST',
      body: { body: text },
    });

    state.pendingByClientId.delete(clientId);

    if (!res.ok) {
      _showToast(_extractError(res, 'تعذر إرسال الرسالة'), 'error');
      return false;
    }

    const serverMessageId = _toInt(res.data?.message_id);
    if (Number.isFinite(serverMessageId)) {
      const temp = state.messages.find((m) => m.id === tempId);
      if (temp) temp.id = serverMessageId;
    }

    await _loadMessages({ forceScroll: true });
    window.dispatchEvent(new Event('nw:badge-refresh'));
    return true;
  }

  function _detectAttachmentType(file) {
    const mime = (file?.type || '').toLowerCase();
    if (mime.startsWith('image/')) return 'image';
    if (mime.startsWith('audio/')) return 'audio';
    return 'file';
  }

  function _renderAttachmentPreview() {
    if (!dom.attachPreview) return;
    dom.attachPreview.innerHTML = '';

    if (!state.pendingAttachment || !state.pendingAttachment.file) {
      dom.attachPreview.classList.add('hidden');
      return;
    }

    const file = state.pendingAttachment.file;
    const row = UI.el('div', { className: 'chat-preview-row' });
    row.appendChild(UI.el('span', { className: 'chat-preview-type', textContent: _attachmentLabel(state.pendingAttachment.type) }));
    row.appendChild(UI.el('span', { className: 'chat-preview-name', textContent: file.name || 'مرفق' }));
    row.appendChild(UI.el('button', {
      type: 'button',
      className: 'chat-preview-remove',
      textContent: 'إزالة',
      onclick: () => _clearPendingAttachment(),
    }));

    dom.attachPreview.appendChild(row);
    dom.attachPreview.classList.remove('hidden');
  }

  function _attachmentLabel(type) {
    if (type === 'image') return 'صورة';
    if (type === 'audio') return 'صوت';
    return 'ملف';
  }

  function _clearPendingAttachment() {
    state.pendingAttachment = null;
    if (dom.fileInput) dom.fileInput.value = '';
    _renderAttachmentPreview();
    _updateSendButtonState();
  }

  async function _markRead(withToast) {
    const res = await ApiClient.request('/api/messaging/direct/thread/' + state.threadId + '/messages/read/', { method: 'POST' });
    if (!res.ok) return;
    window.dispatchEvent(new Event('nw:badge-refresh'));
    if (withToast) _showToast('تم تمييز المحادثة كمقروءة', 'success');
  }

  function _startPollingFallback() {
    if (state.pollTimer) clearInterval(state.pollTimer);
    state.pollTimer = setInterval(() => {
      if (!state.wsConnected) _loadMessages();
    }, 5000);
  }

  function _buildWsUrl(token) {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    return protocol + '//' + window.location.host + '/ws/thread/' + state.threadId + '/?token=' + encodeURIComponent(token);
  }

  function _setConnectionStatus(status) {
    if (!dom.peerStatus) return;
    dom.peerStatus.classList.remove('is-online', 'is-offline', 'is-reconnecting');
    if (status === 'online') {
      dom.peerStatus.textContent = 'متصل';
      dom.peerStatus.classList.add('is-online');
      return;
    }
    if (status === 'reconnecting') {
      dom.peerStatus.textContent = 'جاري إعادة الاتصال...';
      dom.peerStatus.classList.add('is-reconnecting');
      return;
    }
    dom.peerStatus.textContent = 'غير متصل';
    dom.peerStatus.classList.add('is-offline');
  }

  function _connectWebSocket() {
    const token = Auth.getAccessToken();
    if (!token || state.wsConnected || state.threadState.blocked_by_other) return;

    try {
      state.ws = new WebSocket(_buildWsUrl(token));
    } catch (_) {
      _setConnectionStatus('reconnecting');
      _scheduleReconnect();
      return;
    }

    state.ws.onopen = () => {
      state.wsConnected = true;
      _setConnectionStatus('online');
      if (state.wsReconnectTimer) {
        clearTimeout(state.wsReconnectTimer);
        state.wsReconnectTimer = null;
      }
      _markRead();
    };

    state.ws.onmessage = (event) => {
      let payload;
      try {
        payload = JSON.parse(event.data);
      } catch (_) {
        return;
      }
      _handleSocketEvent(payload);
    };

    state.ws.onerror = () => {
      state.wsConnected = false;
      _setConnectionStatus('reconnecting');
    };

    state.ws.onclose = () => {
      state.wsConnected = false;
      _setConnectionStatus('offline');
      state.ws = null;
      _scheduleReconnect();
    };
  }

  function _scheduleReconnect() {
    if (state.wsReconnectTimer || state.threadState.blocked_by_other) return;
    state.wsReconnectTimer = setTimeout(() => {
      state.wsReconnectTimer = null;
      _connectWebSocket();
    }, 3000);
  }

  function _handleSocketEvent(payload) {
    if (!payload || !payload.type) return;

    if (payload.type === 'message') {
      _upsertIncomingMessage(payload);
      if (_toInt(payload.sender_id) !== state.myUserId) _markRead();
      window.dispatchEvent(new Event('nw:badge-refresh'));
      return;
    }

    if (payload.type === 'read') {
      _applyReadReceipt(payload);
      window.dispatchEvent(new Event('nw:badge-refresh'));
      return;
    }

    if (payload.type === 'message_deleted') {
      const id = _toInt(payload.message_id);
      if (!Number.isFinite(id)) return;
      state.messages = state.messages.filter((m) => m.id !== id);
      _renderMessages();
      return;
    }

    if (payload.type === 'error' && payload.code === 'blocked') {
      state.threadState.blocked_by_other = true;
      _renderThreadState();
      _showToast('لا يمكنك المراسلة حالياً لأن الطرف الآخر قام بحظرك.', 'error');
      return;
    }

    if (payload.type === 'unblocked') {
      state.threadState.blocked_by_other = false;
      _renderThreadState();
      _showToast('تم رفع الحظر ويمكنك المتابعة.', 'success');
    }
  }

  function _upsertIncomingMessage(payload) {
    const incomingId = _toInt(payload.id);
    if (!Number.isFinite(incomingId)) return;

    const clientId = payload.client_id || null;
    if (clientId && state.pendingByClientId.has(clientId)) {
      const tempId = state.pendingByClientId.get(clientId);
      state.pendingByClientId.delete(clientId);

      const idx = state.messages.findIndex((m) => m.id === tempId);
      const mapped = {
        id: incomingId,
        senderId: _toInt(payload.sender_id),
        text: (payload.text || '').toString(),
        createdAt: payload.sent_at || new Date().toISOString(),
        readByIds: [],
        attachmentUrl: '',
        attachmentType: '',
        attachmentName: '',
      };
      if (idx >= 0) state.messages[idx] = mapped;
      else state.messages.push(mapped);
      state.messages.sort((a, b) => _messageSortValue(a) - _messageSortValue(b));
      _renderMessages({ forceScroll: true });
      return;
    }

    if (state.messages.some((m) => m.id === incomingId)) return;

    state.messages.push({
      id: incomingId,
      senderId: _toInt(payload.sender_id),
      text: (payload.text || '').toString(),
      createdAt: payload.sent_at || new Date().toISOString(),
      readByIds: [],
      attachmentUrl: '',
      attachmentType: '',
      attachmentName: '',
    });
    state.messages.sort((a, b) => _messageSortValue(a) - _messageSortValue(b));
    _renderMessages({ forceScroll: true });
  }

  function _applyReadReceipt(payload) {
    const readerId = _toInt(payload.user_id);
    const ids = Array.isArray(payload.message_ids) ? payload.message_ids.map(_toInt) : [];
    if (!Number.isFinite(readerId) || !ids.length) return;

    const idSet = new Set(ids.filter((v) => Number.isFinite(v)));
    let changed = false;

    state.messages.forEach((msg) => {
      if (!idSet.has(msg.id)) return;
      if (!Array.isArray(msg.readByIds)) msg.readByIds = [];
      if (!msg.readByIds.includes(readerId)) {
        msg.readByIds.push(readerId);
        changed = true;
      }
    });

    if (changed) _renderMessages();
  }

  function _openOptionsSheet() {
    dom.sheetBackdrop?.classList.remove('hidden');
    dom.optionsSheet?.classList.remove('hidden');
    requestAnimationFrame(() => {
      dom.sheetBackdrop?.classList.add('open');
      dom.optionsSheet?.classList.add('open');
    });
  }

  function _closeOptionsSheet() {
    dom.sheetBackdrop?.classList.remove('open');
    dom.optionsSheet?.classList.remove('open');
    setTimeout(() => {
      dom.sheetBackdrop?.classList.add('hidden');
      dom.optionsSheet?.classList.add('hidden');
    }, 180);
  }

  function _openReportDialog() {
    dom.reportBackdrop?.classList.remove('hidden');
    dom.reportDialog?.classList.remove('hidden');
    requestAnimationFrame(() => {
      dom.reportBackdrop?.classList.add('open');
      dom.reportDialog?.classList.add('open');
    });
  }

  function _closeReportDialog() {
    dom.reportBackdrop?.classList.remove('open');
    dom.reportDialog?.classList.remove('open');
    setTimeout(() => {
      dom.reportBackdrop?.classList.add('hidden');
      dom.reportDialog?.classList.add('hidden');
    }, 160);
  }

  function _handleChatAction(action) {
    _closeOptionsSheet();
    if (action === 'read') return _markRead(true);
    if (action === 'favorite') return _toggleFavorite();
    if (action === 'block') return _toggleBlock();
    if (action === 'archive') return _toggleArchive();
    if (action === 'report') _openReportDialog();
  }

  async function _toggleFavorite() {
    const remove = !!state.threadState.is_favorite;
    const res = await ApiClient.request('/api/messaging/thread/' + state.threadId + '/favorite/', {
      method: 'POST',
      body: remove ? { action: 'remove' } : {},
    });
    if (!res.ok) return _showToast(_extractError(res, 'تعذر تحديث المفضلة'), 'error');

    state.threadState.is_favorite = !!res.data?.is_favorite;
    _renderThreadState();
    _showToast(remove ? 'تمت إزالة المحادثة من المفضلة' : 'تمت إضافة المحادثة للمفضلة', 'success');
  }

  async function _toggleArchive() {
    const remove = !!state.threadState.is_archived;
    if (!remove && !window.confirm('أرشفة هذه المحادثة؟ سيتم إخفاؤها من قائمة المحادثات.')) return;

    const res = await ApiClient.request('/api/messaging/thread/' + state.threadId + '/archive/', {
      method: 'POST',
      body: remove ? { action: 'remove' } : {},
    });
    if (!res.ok) return _showToast(_extractError(res, 'تعذر تحديث الأرشفة'), 'error');

    state.threadState.is_archived = !!res.data?.is_archived;
    _renderThreadState();
    _showToast(remove ? 'تم إلغاء أرشفة المحادثة' : 'تمت أرشفة المحادثة', 'success');
  }

  async function _toggleBlock() {
    const remove = !!state.threadState.is_blocked;
    const msg = remove ? 'هل تريد إلغاء الحظر عن هذا العضو؟' : 'هل أنت متأكد من حظر هذا العضو؟ لن يتمكن من مراسلتك.';
    if (!window.confirm(msg)) return;

    const res = await ApiClient.request('/api/messaging/thread/' + state.threadId + '/block/', {
      method: 'POST',
      body: remove ? { action: 'remove' } : {},
    });
    if (!res.ok) return _showToast(_extractError(res, 'تعذر تحديث حالة الحظر'), 'error');

    state.threadState.is_blocked = !!res.data?.is_blocked;
    _renderThreadState();
    _showToast(state.threadState.is_blocked ? 'تم حظر العضو' : 'تم إلغاء الحظر', 'success');
  }

  async function _submitReport() {
    const reason = _trim(dom.reportReason?.value);
    const details = _trim(dom.reportDetails?.value);
    if (!reason) return _showToast('اختر سبب الإبلاغ أولاً', 'error');

    dom.btnReportSend.disabled = true;
    const res = await ApiClient.request('/api/messaging/thread/' + state.threadId + '/report/', {
      method: 'POST',
      body: {
        reason,
        details: details || undefined,
        reported_label: state.peer.name || undefined,
      },
    });
    dom.btnReportSend.disabled = false;

    if (!res.ok) return _showToast(_extractError(res, 'تعذر إرسال البلاغ'), 'error');

    _closeReportDialog();
    if (dom.reportReason) dom.reportReason.value = '';
    if (dom.reportDetails) dom.reportDetails.value = '';
    _showToast('تم إرسال البلاغ بنجاح', 'success');
  }

  function _showToast(message, type) {
    if (!dom.toast) return;
    dom.toast.textContent = message || '';
    dom.toast.classList.remove('show', 'success', 'error');
    if (type) dom.toast.classList.add(type);
    requestAnimationFrame(() => dom.toast.classList.add('show'));
    window.clearTimeout(dom.toast._timer);
    dom.toast._timer = window.setTimeout(() => dom.toast.classList.remove('show'), 2400);
  }

  function _formatTime(value) {
    const dt = new Date(value);
    if (!Number.isFinite(dt.getTime())) return '';
    return dt.toLocaleTimeString('ar-SA', { hour: 'numeric', minute: '2-digit' });
  }

  function _formatDayLabel(value) {
    const dt = new Date(value);
    if (!Number.isFinite(dt.getTime())) return '';

    const now = new Date();
    const startToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
    const startTarget = new Date(dt.getFullYear(), dt.getMonth(), dt.getDate()).getTime();
    const diffDays = Math.round((startToday - startTarget) / 86400000);

    if (diffDays === 0) return 'اليوم';
    if (diffDays === 1) return 'أمس';
    return dt.toLocaleDateString('ar-SA', { day: 'numeric', month: 'long' });
  }

  function _dayKey(value) {
    const dt = new Date(value);
    if (!Number.isFinite(dt.getTime())) return '';
    return dt.getFullYear() + '-' + String(dt.getMonth() + 1).padStart(2, '0') + '-' + String(dt.getDate()).padStart(2, '0');
  }

  function _extractError(res, fallback) {
    if (!res || !res.data) return fallback;
    return res.data.detail || res.data.error || fallback;
  }

  function _isDefaultPeerName(name) {
    const n = _trim(name);
    return !n || n === 'مستخدم' || n === '...';
  }

  function _trim(v) {
    return (v || '').toString().trim();
  }

  function _joinName(first, last) {
    return (_trim(first) + ' ' + _trim(last)).trim();
  }

  function _toInt(v) {
    const n = parseInt(v, 10);
    return Number.isFinite(n) ? n : null;
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();

  return {};
})();
