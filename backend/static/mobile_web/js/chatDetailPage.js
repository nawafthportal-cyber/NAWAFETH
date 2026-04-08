/* ===================================================================
  chatDetailPage.js — Direct messages detail
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
    wsReconnectAttempts: 0,
    wsDisableUntilTs: 0,
    wsFallbackNotified: false,
    pendingByClientId: new Map(),
    pendingAttachment: null,
    peer: {
      name: 'مستخدم',
      phone: 'غير متوفر',
      city: 'غير متوفر',
      avatar: '',
      id: null,
      providerId: null,
      kind: 'member',
    },
    account: {
      mode: 'client',
      isProviderMode: false,
      providerProfileId: null,
    },
    threadState: {
      is_favorite: false,
      is_archived: false,
      is_blocked: false,
      blocked_by_other: false,
      reply_restricted_to_me: false,
      reply_restriction_reason: '',
      system_sender_label: '',
      is_system_thread: false,
    },
  };

  const WS_MAX_RECONNECT_ATTEMPTS = 6;
  const WS_DISABLE_WINDOW_MS = 60000;

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
    _renderPeer();
    _updateSendButtonState();
    _boot();
  }

  async function _boot() {
    await Promise.all([
      _loadAccountContext(),
      _loadThreadMeta(),
      _loadThreadState(),
      _loadMessages({ showLoader: true, forceScroll: true }),
    ]);

    _markRead();
    _startPollingFallback();
  }

  function _cacheDom() {
    dom.header = document.getElementById('chat-header');
    dom.headerActions = document.getElementById('chat-header-actions');
    dom.memberCard = document.getElementById('chat-member-card');
    dom.peerAvatar = document.getElementById('peer-avatar');
    dom.peerName = document.getElementById('peer-name');
    dom.peerSubtitle = document.getElementById('peer-subtitle');
    dom.peerTags = document.getElementById('peer-tags');
    dom.peerCardNameLabel = document.getElementById('peer-card-name-label');
    dom.peerCardName = document.getElementById('peer-card-name');
    dom.peerCardPhone = document.getElementById('peer-card-phone');
    dom.peerCardCity = document.getElementById('peer-card-city');
    dom.peerCardPhoneRow = document.getElementById('peer-card-phone-row');
    dom.peerCardCityRow = document.getElementById('peer-card-city-row');
    dom.peerCardSystemRow = document.getElementById('peer-card-system-row');
    dom.peerCardSystemValue = document.getElementById('peer-card-system-value');
    dom.favoriteIndicator = document.getElementById('chat-favorite-indicator');
    dom.banner = document.getElementById('chat-thread-banner');
    dom.composerNote = document.getElementById('chat-composer-note');

    dom.btnFavorite = document.getElementById('btn-chat-fav');
    dom.btnOptions = document.getElementById('btn-chat-options');
    dom.btnClientRequests = document.getElementById('btn-client-requests');
    dom.btnSendServiceRequest = document.getElementById('btn-send-service-request');
    dom.btnClientRequestsCard = document.getElementById('btn-client-requests-card');
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
    dom.clientRequestsBackdrop = document.getElementById('chat-client-requests-backdrop');
    dom.clientRequestsSheet = document.getElementById('chat-client-requests-sheet');
    dom.clientRequestsTitle = document.getElementById('chat-client-requests-title');
    dom.clientRequestsBody = document.getElementById('chat-client-requests-body');
    dom.btnClientRequestsClose = document.getElementById('btn-client-requests-close');

    dom.loader = document.getElementById('messages-loader');
    dom.error = document.getElementById('messages-error');
    dom.errorText = document.getElementById('messages-error-text');
    dom.empty = document.getElementById('messages-empty');
    dom.messages = document.getElementById('chat-messages');
    dom.btnRetry = document.getElementById('btn-retry-load');

    dom.inputWrap = document.getElementById('chat-input-wrap');
    dom.inputBar = document.getElementById('chat-input-bar');
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
    dom.btnClientRequests?.addEventListener('click', _openClientRequestsSheet);
    dom.btnClientRequestsCard?.addEventListener('click', _openClientRequestsSheet);
    dom.btnSendServiceRequest?.addEventListener('click', _sendServiceRequestLink);

    dom.sheetBackdrop?.addEventListener('click', _closeOptionsSheet);
    dom.optionsSheet?.addEventListener('click', (event) => {
      const actionBtn = event.target.closest('[data-chat-action]');
      if (!actionBtn) return;
      _handleChatAction(actionBtn.getAttribute('data-chat-action'));
    });

    dom.reportBackdrop?.addEventListener('click', _closeReportDialog);
    dom.btnReportCancel?.addEventListener('click', _closeReportDialog);
    dom.btnReportSend?.addEventListener('click', _submitReport);
    dom.clientRequestsBackdrop?.addEventListener('click', _closeClientRequestsSheet);
    dom.btnClientRequestsClose?.addEventListener('click', _closeClientRequestsSheet);

    document.addEventListener('keydown', (event) => {
      if (event.key !== 'Escape') return;
      _closeOptionsSheet();
      _closeReportDialog();
      _closeClientRequestsSheet();
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
    const res = await ApiClient.get(_withMode('/api/messaging/direct/threads/'));
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
    if (typeof thread.reply_restricted_to_me === 'boolean') state.threadState.reply_restricted_to_me = thread.reply_restricted_to_me;
    if (typeof thread.reply_restriction_reason === 'string') state.threadState.reply_restriction_reason = thread.reply_restriction_reason;
    if (typeof thread.system_sender_label === 'string') state.threadState.system_sender_label = thread.system_sender_label;
    if (typeof thread.is_system_thread === 'boolean') state.threadState.is_system_thread = thread.is_system_thread;

    _renderPeer();
    _renderThreadState();
    _renderProviderClientActions();
  }

  async function _loadAccountContext() {
    state.account.mode = _activeMode();
    state.account.isProviderMode = state.account.mode === 'provider';
    state.account.providerProfileId = null;

    if (!state.account.isProviderMode) {
      _renderProviderClientActions();
      return;
    }

    const res = await ApiClient.get('/api/accounts/me/?mode=provider');
    if (res.ok && res.data) {
      state.account.providerProfileId = _toInt(res.data.provider_profile_id);
    }
    _renderPeer();
    _renderProviderClientActions();
  }

  async function _loadThreadState() {
    const res = await ApiClient.get(_withMode('/api/messaging/thread/' + state.threadId + '/state/'));
    if (!res.ok || !res.data) return;

    state.threadState = {
      is_favorite: !!res.data.is_favorite,
      is_archived: !!res.data.is_archived,
      is_blocked: !!res.data.is_blocked,
      blocked_by_other: !!res.data.blocked_by_other,
      reply_restricted_to_me: !!res.data.reply_restricted_to_me,
      reply_restriction_reason: _trim(res.data.reply_restriction_reason),
      system_sender_label: _trim(res.data.system_sender_label),
      is_system_thread: !!res.data.is_system_thread,
    };

    _renderThreadState();
  }

  async function _loadMessages(opts = {}) {
    if (state.isLoading) return;
    state.isLoading = true;
    if (opts.showLoader) _showViewState('loading');

    const res = await ApiClient.get(
      _withMode('/api/messaging/direct/thread/' + state.threadId + '/messages/?limit=80&offset=0')
    );
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
      const senderTeamName = _trim(raw.sender_team_name);
      if (senderId && senderId !== state.myUserId && (senderTeamName || _trim(raw.sender_name))) {
        state.peer.name = senderTeamName || _trim(raw.sender_name);
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
      senderName: _trim(raw.sender_name),
      senderTeamName: _trim(raw.sender_team_name),
      text,
      createdAt,
      readByIds,
      isSystemGenerated: !!raw.is_system_generated,
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
    const isSystem = _isAutoPlatformThread();
    const displayName = isSystem ? _systemThreadSenderLabel() : (state.peer.name || 'مستخدم');
    if (isSystem && displayName) state.peer.name = displayName;

    if (dom.peerName) dom.peerName.textContent = displayName || 'مستخدم';
    if (dom.peerCardName) dom.peerCardName.textContent = displayName || 'مستخدم';
    if (dom.peerCardPhone) dom.peerCardPhone.textContent = state.peer.phone || 'غير متوفر';
    if (dom.peerCardCity) dom.peerCardCity.textContent = state.peer.city || 'غير متوفر';
    if (dom.peerCardNameLabel) dom.peerCardNameLabel.textContent = isSystem ? 'الفريق المرسل' : 'العضو';
    if (dom.peerCardSystemValue) {
      dom.peerCardSystemValue.textContent = isSystem
        ? 'رسائل آلية مباشرة من ' + _systemThreadSenderLabel()
        : 'رسائل آلية من المنصة';
    }

    state.peer.kind = _derivePeerKind();

    if (dom.peerSubtitle) {
      const subtitle = _peerSubtitle();
      dom.peerSubtitle.textContent = subtitle;
      dom.peerSubtitle.classList.toggle('hidden', !subtitle);
    }

    if (dom.peerTags) {
      const tags = _peerTags();
      dom.peerTags.innerHTML = '';
      dom.peerTags.classList.toggle('hidden', tags.length === 0);
      tags.forEach((tag) => {
        const chip = UI.el('span', {
          className: 'chat-peer-tag' + (tag.accent ? ' accent-' + tag.accent : ''),
          textContent: tag.text,
        });
        dom.peerTags.appendChild(chip);
      });
    }

    if (dom.peerCardPhoneRow) {
      dom.peerCardPhoneRow.classList.toggle('hidden', isSystem || !_hasMeaningfulValue(state.peer.phone));
    }
    if (dom.peerCardCityRow) {
      dom.peerCardCityRow.classList.toggle('hidden', isSystem || !_hasMeaningfulValue(state.peer.city));
    }
    if (dom.peerCardSystemRow) {
      dom.peerCardSystemRow.classList.toggle('hidden', !isSystem);
    }

    if (dom.composerNote) {
      dom.composerNote.textContent = _composerNote();
    }
    dom.header?.classList.toggle('is-system-thread', isSystem);
    dom.memberCard?.classList.toggle('is-system-thread', isSystem);
    _renderHeaderActions();

    if (!dom.peerAvatar) return;
    dom.peerAvatar.innerHTML = '';
    if (state.peer.avatar) {
      dom.peerAvatar.appendChild(UI.lazyImg(ApiClient.mediaUrl(state.peer.avatar), state.peer.name || ''));
      return;
    }
    dom.peerAvatar.textContent = (state.peer.name || 'م').trim().charAt(0) || 'م';
  }

  function _isChatWithClient() {
    if (!Number.isFinite(state.peer.id) || state.peer.id <= 0) return false;
    return !Number.isFinite(state.peer.providerId) || state.peer.providerId <= 0;
  }

  function _canShowProviderClientActions() {
    return !!state.account.isProviderMode && _isChatWithClient();
  }

  function _renderProviderClientActions() {
    const show = _canShowProviderClientActions() && !_isAutoPlatformThread();
    dom.btnClientRequestsCard?.classList.toggle('hidden', !show);
    if (dom.clientRequestsTitle) {
      const peerName = _trim(state.peer.name) || 'العميل';
      dom.clientRequestsTitle.textContent = 'طلبات العميل: ' + peerName;
    }
    _renderHeaderActions();
  }

  function _renderHeaderActions() {
    const isSystem = _isAutoPlatformThread();
    const showProviderTools = _canShowProviderClientActions() && !isSystem;
    dom.btnClientRequests?.classList.toggle('hidden', !showProviderTools);
    dom.btnSendServiceRequest?.classList.toggle('hidden', !showProviderTools);
    dom.btnFavorite?.classList.toggle('hidden', isSystem);
    dom.btnOptions?.classList.toggle('hidden', isSystem);

    const buttons = [
      dom.btnClientRequests,
      dom.btnSendServiceRequest,
      dom.btnFavorite,
      dom.btnOptions,
    ].filter(Boolean);
    const hasVisible = buttons.some((btn) => !btn.classList.contains('hidden'));
    dom.headerActions?.classList.toggle('hidden', !hasVisible);
  }

  function _derivePeerKind() {
    if (_isPlatformTeamName(state.peer.name)) return 'team';
    if (Number.isFinite(state.peer.providerId) && state.peer.providerId > 0) return 'provider';
    if (state.account.isProviderMode) return 'client';
    return 'member';
  }

  function _peerSubtitle() {
    if (_isAutoPlatformThread() || state.threadState.reply_restricted_to_me) {
      const label = _systemThreadSenderLabel() || 'الجهة المرسلة';
      return 'رسائل آلية من ' + label;
    }
    if (state.peer.kind === 'team') return 'رسائل فريق المنصة';
    if (state.peer.kind === 'provider') return 'مقدم خدمة على المنصة';
    if (state.peer.kind === 'client') return 'عميل على المنصة';
    return 'رسائل مباشرة داخل نوافذ';
  }

  function _peerTags() {
    const tags = [];
    const isSystem = _isAutoPlatformThread();

    if (isSystem) {
      tags.push({ text: 'رسائل آلية', accent: 'violet' });
    }

    if (state.peer.kind === 'team') {
      tags.push({ text: 'فريق المنصة', accent: 'violet' });
    } else if (state.peer.kind === 'provider') {
      tags.push({ text: 'مزود خدمة', accent: 'blue' });
    } else if (state.peer.kind === 'client') {
      tags.push({ text: 'عميل', accent: 'amber' });
    }

    if (!isSystem) {
      tags.push({ text: 'رسائل مباشرة' });
    }

    if (!isSystem && _hasMeaningfulValue(state.peer.city)) {
      tags.push({ text: state.peer.city, accent: 'slate' });
    }

    return tags.slice(0, 3);
  }

  function _composerNote() {
    if (state.threadState.blocked_by_other || state.threadState.is_blocked) {
      return 'الإرسال متوقف حتى يتم رفع الحظر.';
    }
    if (_isAutoPlatformThread() || state.threadState.reply_restricted_to_me) {
      return state.threadState.reply_restriction_reason || 'الردود مغلقة على هذه الرسائل الآلية.';
    }
    if (state.peer.kind === 'team') {
      return 'يمكنك متابعة الرسائل مع فريق المنصة وإرسال المرفقات عند الحاجة.';
    }
    if (state.peer.kind === 'provider') {
      return 'أرسل تفاصيلك أو مرفقاتك مباشرة إلى مقدم الخدمة.';
    }
    if (state.peer.kind === 'client') {
      return 'تابع مع العميل وأرسل التفاصيل أو الملفات المطلوبة.';
    }
    return 'يمكنك إرسال نصوص ومرفقات بشكل مباشر.';
  }

  function _hasMeaningfulValue(value) {
    const normalized = _trim(value);
    return !!normalized && normalized !== 'غير متوفر';
  }

  function _isPlatformTeamName(name) {
    const normalized = _trim(name);
    return normalized.startsWith('فريق ');
  }

  function _isAutoPlatformThread() {
    return !!state.threadState.is_system_thread;
  }

  function _systemThreadSenderLabel() {
    return _trim(state.threadState.system_sender_label) || _trim(state.peer.name) || 'فريق المنصة';
  }

  function _renderThreadState() {
    const isSystem = _isAutoPlatformThread();
    const isFavorite = !!state.threadState.is_favorite;
    dom.btnFavorite?.classList.toggle('active', isFavorite);
    dom.favoriteIndicator?.classList.toggle('hidden', isSystem || !isFavorite);
    if (dom.composerNote) dom.composerNote.textContent = _composerNote();

    if (dom.actionFavorite) {
      const label = dom.actionFavorite.querySelector('span');
      if (label) label.textContent = isFavorite ? 'إزالة من المفضلة' : 'إضافة للمفضلة';
    }
    if (dom.actionArchive) {
      const label = dom.actionArchive.querySelector('span');
      if (label) label.textContent = state.threadState.is_archived ? 'إلغاء الأرشفة' : 'أرشفة الرسائل';
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
      _showBanner('قمت بحظر هذا العضو. أزل الحظر من خيارات الرسائل للمتابعة.', 'danger');
      _setComposerDisabled(true);
      return;
    }
    if (isSystem || state.threadState.reply_restricted_to_me) {
      _showBanner(state.threadState.reply_restriction_reason || 'الردود مغلقة لهذه الرسائل الآلية.', 'info');
      _setComposerDisabled(true);
      return;
    }
    if (state.threadState.is_archived) _showBanner('هذه الرسائل مؤرشفة وستعود تلقائياً عند إرسال رسالة جديدة.', 'info');
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
    dom.inputWrap?.classList.toggle('is-readonly', disabled && _isAutoPlatformThread());
    if (dom.inputBar) {
      dom.inputBar.classList.toggle('hidden', disabled && _isAutoPlatformThread());
    }
    if (disabled && _isAutoPlatformThread()) {
      state.pendingAttachment = null;
      if (dom.fileInput) dom.fileInput.value = '';
      _renderAttachmentPreview();
    }
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
    const kind = _messageKind(msg, mine);
    const attachmentTone = _attachmentTone(msg);
    const row = UI.el('div', {
      className: 'msg-row '
        + (mine ? 'mine' : 'theirs')
        + (kind === 'team' ? ' is-team' : '')
        + (attachmentTone ? ' has-attachment' : ''),
    });
    const bubble = UI.el('div', {
      className: 'msg-bubble '
        + (mine ? 'mine' : 'theirs')
        + (kind === 'team' ? ' kind-team' : '')
        + (attachmentTone ? ' has-attachment attachment-' + attachmentTone : ''),
    });

    bubble.classList.toggle('group-prev', _canGroup(prev, msg));
    bubble.classList.toggle('group-next', _canGroup(msg, next));

    const attachmentNode = _buildAttachmentNode(msg);
    const serviceRequestCta = _parseServiceRequestCTA(msg.text);
    const badgeRow = _buildMessageBadgeRow(msg, { mine, kind, attachmentTone, serviceRequestCta });
    if (badgeRow) bubble.appendChild(badgeRow);
    if (attachmentNode) bubble.appendChild(attachmentNode);
    if (serviceRequestCta && serviceRequestCta.helperText) {
      bubble.appendChild(UI.el('div', { className: 'msg-text', textContent: serviceRequestCta.helperText }));
    }
    if (serviceRequestCta) {
      bubble.appendChild(_buildServiceRequestNode(serviceRequestCta, mine));
    } else if (msg.text) {
      bubble.appendChild(_buildRichTextNode(msg.text, mine));
    }

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

  function _buildMessageBadgeRow(msg, options) {
    const items = [];

    if (!options.mine && msg.isSystemGenerated) {
      items.push({
        text: msg.senderTeamName || msg.senderName || state.threadState.system_sender_label || 'رسالة آلية',
        accent: 'violet',
      });
      items.push({ text: 'رسالة آلية', accent: 'soft' });
    } else if (options.kind === 'team' && !options.mine) {
      items.push({
        text: msg.senderName || 'فريق المنصة',
        accent: 'violet',
      });
    }

    if (options.attachmentTone) {
      items.push({
        text: _attachmentLabel(msg.attachmentType || 'file'),
        accent: options.mine ? 'soft' : 'slate',
      });
    }

    if (options.serviceRequestCta) {
      items.push({ text: 'طلب خدمة', accent: 'amber' });
    }

    if (!items.length) return null;

    const row = UI.el('div', { className: 'msg-badge-row' });
    items.forEach((item) => {
      row.appendChild(UI.el('span', {
        className: 'msg-kind-badge accent-' + item.accent,
        textContent: item.text,
      }));
    });
    return row;
  }

  function _buildServiceRequestNode(cta, mine) {
    const node = UI.el('a', {
      className: 'msg-service-cta ' + (mine ? 'mine' : 'theirs'),
      href: cta.href,
    });

    node.appendChild(UI.el('span', { className: 'msg-service-cta-icon', textContent: '🛠️' }));

    const body = UI.el('span', { className: 'msg-service-cta-body' });
    body.appendChild(UI.el('strong', { className: 'msg-service-cta-title', textContent: 'طلب خدمة' }));
    body.appendChild(UI.el('small', { className: 'msg-service-cta-subtitle', textContent: 'اضغط هنا لإرسال طلبك لهذا المزوّد' }));
    node.appendChild(body);

    node.appendChild(UI.el('span', { className: 'msg-service-cta-arrow', textContent: '‹' }));
    return node;
  }

  /* ── Safe URL linkifier (DOM-only, no innerHTML) ── */
  const _URL_RE = /(?:https?:\/\/[^\s<>"""'']+|(?:^|\s)(\/(?:promotion|promo-payment|verification|service-request|provider|provider-orders|subscription|chats|chat)(?:\/[^\s<>"""'']*)?(?:\?[^\s<>"""'']*)?))(?=[.,;:!?)'"»\u200F]*(?:\s|$)|$)/gi;

  function _buildRichTextNode(text, mine) {
    const container = UI.el('div', { className: 'msg-text' });
    _URL_RE.lastIndex = 0;
    let cursor = 0;
    let match;

    while ((match = _URL_RE.exec(text)) !== null) {
      const rawUrl = (match[1] || match[0]).trim();
      const matchStart = match.index + (match[0].length - match[0].trimStart().length);
      const matchEnd = match.index + match[0].trimEnd().length;

      // Text before this URL
      if (matchStart > cursor) {
        container.appendChild(document.createTextNode(text.slice(cursor, matchStart)));
      }

      // Determine href
      let href = rawUrl;
      if (href.startsWith('/')) {
        // Relative path — keep as-is
      } else {
        // Validate full URL
        try { new URL(href); } catch (_) { href = ''; }
      }

      if (href) {
        const isPayment = /\/(promotion|promo-payment|subscription)/.test(href) || /prepare-payment|init-payment|payment/.test(href);
        const linkNode = _buildInlineLink(href, rawUrl, mine, isPayment);
        container.appendChild(linkNode);
      } else {
        container.appendChild(document.createTextNode(rawUrl));
      }
      cursor = matchEnd;
    }

    // Remaining text
    if (cursor < text.length) {
      container.appendChild(document.createTextNode(text.slice(cursor)));
    }

    // If no links were found at all, just use plain textContent (faster)
    if (!container.querySelector('a')) {
      container.textContent = text;
    }
    return container;
  }

  function _buildInlineLink(href, displayText, mine, isPayment) {
    if (isPayment) {
      // Render rich payment CTA card
      const card = UI.el('a', {
        className: 'msg-payment-cta ' + (mine ? 'mine' : 'theirs'),
        href: href,
      });
      card.appendChild(UI.el('span', { className: 'msg-payment-cta-icon', textContent: '💳' }));
      const body = UI.el('span', { className: 'msg-payment-cta-body' });
      body.appendChild(UI.el('strong', { className: 'msg-payment-cta-title', textContent: 'صفحة الدفع' }));
      body.appendChild(UI.el('small', { className: 'msg-payment-cta-sub', textContent: 'اضغط هنا للانتقال إلى صفحة الدفع' }));
      card.appendChild(body);
      card.appendChild(UI.el('span', { className: 'msg-payment-cta-arrow', textContent: '‹' }));
      return card;
    }

    // Plain inline link
    const link = UI.el('a', {
      className: 'msg-inline-link ' + (mine ? 'mine' : 'theirs'),
      href: href,
      target: '_self',
      rel: 'noopener',
    });
    // Try human-friendly display
    let label = displayText;
    try {
      const u = new URL(displayText, window.location.origin);
      const path = u.pathname.replace(/\/+$/, '');
      const LABELS = {
        '/promotion': 'صفحة الترويج',
        '/verification': 'صفحة التوثيق',
        '/service-request': 'طلب خدمة',
        '/provider-orders': 'طلبات المزوّد',
        '/subscription': 'الاشتراك',
        '/chats': 'الرسائل',
      };
      const found = Object.entries(LABELS).find(([k]) => path === k || path.startsWith(k + '/'));
      if (found) label = found[1];
    } catch (_) { /* keep raw */ }
    link.appendChild(UI.el('span', { className: 'msg-inline-link-icon', textContent: '🔗' }));
    link.appendChild(UI.el('span', { className: 'msg-inline-link-text', textContent: label }));
    return link;
  }

  function _parseServiceRequestCTA(text) {
    const value = _trim(text);
    if (!value) return null;

    const urlMatch = value.match(/(https?:\/\/[^\s]+|\/service-request\/[^\s]*)/i);
    if (!urlMatch) return null;

    const rawUrl = _trim(urlMatch[1]);
    if (!rawUrl) return null;

    let parsed = null;
    try {
      parsed = new URL(rawUrl, window.location.origin);
    } catch (_) {
      parsed = null;
    }
    if (!parsed) return null;

    const path = (parsed.pathname || '').replace(/\/+$/, '').toLowerCase();
    if (path !== '/service-request') return null;

    const providerId = _toInt(parsed.searchParams.get('provider_id'));
    if (!providerId || providerId <= 0) return null;

    const helperText = _trim(value.replace(rawUrl, '').replace(/\s+/g, ' '));
    return {
      href: '/service-request/?provider_id=' + encodeURIComponent(String(providerId)),
      helperText,
    };
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

  function _messageKind(msg, mine) {
    if (!mine && (_isPlatformTeamName(msg.senderName) || state.peer.kind === 'team')) return 'team';
    return 'member';
  }

  function _attachmentTone(msg) {
    if (!msg.attachmentUrl) return '';
    if (msg.attachmentType === 'image') return 'image';
    if (msg.attachmentType === 'audio') return 'audio';
    return 'file';
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
    const replyLocked = !!state.threadState.reply_restricted_to_me || _isAutoPlatformThread();
    const disabled = state.isSending || blocked || replyLocked || (!hasText && !hasAttachment);

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
      _showToast('لا يمكن الإرسال لأن هذه الرسائل محظورة.', 'error');
      return;
    }
    if (_isAutoPlatformThread() || state.threadState.reply_restricted_to_me) {
      _showToast(state.threadState.reply_restriction_reason || 'الردود مغلقة لهذه الرسائل الآلية.', 'warning');
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
      senderName: '',
      text,
      createdAt: new Date().toISOString(),
      readByIds: [],
      attachmentUrl: '',
      attachmentType: '',
      attachmentName: '',
    });
    _renderMessages({ forceScroll: true });

    const sent = await _sendTextFallback(text, tempId, clientId);
    if (!sent) {
      state.messages = state.messages.filter((m) => m.id !== tempId);
      state.pendingByClientId.delete(clientId);
      _renderMessages({ forceScroll: true });
    }

    state.isSending = false;
    _updateSendButtonState();
  }

  async function _sendAttachmentMessage(text, attachment) {
    const formData = new FormData();
    if (text) formData.append('body', text);
    formData.append('attachment_type', attachment.type || 'file');
    formData.append('attachment', attachment.file);

    const res = await ApiClient.request(_withMode('/api/messaging/direct/thread/' + state.threadId + '/messages/send/'), {
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
    const res = await ApiClient.request(_withMode('/api/messaging/direct/thread/' + state.threadId + '/messages/send/'), {
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
    const res = await ApiClient.request(
      _withMode('/api/messaging/direct/thread/' + state.threadId + '/messages/read/'),
      { method: 'POST' }
    );
    if (!res.ok) return;
    window.dispatchEvent(new Event('nw:badge-refresh'));
    if (withToast) _showToast('تم تمييز الرسائل كمقروءة', 'success');
  }

  function _startPollingFallback() {
    if (state.pollTimer) clearInterval(state.pollTimer);
    state.pollTimer = setInterval(() => {
      if (!state.isLoading && !document.hidden) {
        _loadMessages();
      }
    }, 15000);
  }

  function _buildWsCandidates(token) {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const mode = encodeURIComponent(_activeMode());
    const path = '/ws/thread/' + state.threadId + '/?token=' + encodeURIComponent(token) + '&mode=' + mode;
    const urls = [];

    const addCandidate = (host) => {
      const safeHost = String(host || '').trim();
      if (!safeHost) return;
      const candidate = protocol + '//' + safeHost + path;
      if (!urls.includes(candidate)) urls.push(candidate);
    };

    // Primary candidate: current host exactly as opened by the user.
    addCandidate(window.location.host);

    // Secondary candidate: switch between www / non-www for production domains.
    const hostname = String(window.location.hostname || '').trim();
    const isLocal = hostname === 'localhost' || hostname === '127.0.0.1';
    if (!isLocal && hostname) {
      const port = window.location.port ? (':' + window.location.port) : '';

      if (hostname.startsWith('www.')) {
        const bareHost = hostname.slice(4);
        if (bareHost) addCandidate(bareHost + port);
      } else if (hostname.includes('.')) {
        addCandidate('www.' + hostname + port);
      }
    }

    return urls;
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
    if (status === 'fallback') {
      dom.peerStatus.textContent = 'اتصال محدود (تحديث تلقائي)';
      dom.peerStatus.classList.add('is-offline');
      return;
    }
    dom.peerStatus.textContent = 'غير متصل';
    dom.peerStatus.classList.add('is-offline');
  }

  function _connectWebSocket() {
    const token = Auth.getAccessToken();
    if (!token || state.wsConnected || state.threadState.blocked_by_other) return;
    if (state.ws && state.ws.readyState === WebSocket.CONNECTING) return;

    const wsCandidates = _buildWsCandidates(token);
    if (!wsCandidates.length) {
      _handleWsFailure();
      return;
    }

    const attemptIndex = state.wsReconnectAttempts % wsCandidates.length;
    const wsUrl = wsCandidates[attemptIndex] || wsCandidates[0];

    const now = Date.now();
    if (state.wsDisableUntilTs && now < state.wsDisableUntilTs) {
      _setConnectionStatus('fallback');
      _scheduleReconnect(state.wsDisableUntilTs - now);
      return;
    }

    try {
      state.ws = new WebSocket(wsUrl);
    } catch (_) {
      _handleWsFailure();
      return;
    }

    state.ws.onopen = () => {
      state.wsConnected = true;
      state.wsReconnectAttempts = 0;
      state.wsDisableUntilTs = 0;
      state.wsFallbackNotified = false;
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
      if (!state.wsDisableUntilTs || Date.now() >= state.wsDisableUntilTs) {
        _setConnectionStatus('reconnecting');
      }
    };

    state.ws.onclose = () => {
      state.wsConnected = false;
      state.ws = null;
      _handleWsFailure();
    };
  }

  function _handleWsFailure() {
    if (state.threadState.blocked_by_other) {
      _setConnectionStatus('offline');
      return;
    }

    state.wsReconnectAttempts += 1;

    if (state.wsReconnectAttempts >= WS_MAX_RECONNECT_ATTEMPTS) {
      state.wsReconnectAttempts = 0;
      state.wsDisableUntilTs = Date.now() + WS_DISABLE_WINDOW_MS;
      _setConnectionStatus('fallback');

      if (!state.wsFallbackNotified) {
        state.wsFallbackNotified = true;
        _showToast('تعذر الاتصال الفوري حالياً، سيتم التحديث تلقائياً.', 'warning');
      }

      _scheduleReconnect(WS_DISABLE_WINDOW_MS);
      return;
    }

    _setConnectionStatus('reconnecting');
    _scheduleReconnect();
  }

  function _scheduleReconnect(delayMs) {
    if (state.wsReconnectTimer || state.threadState.blocked_by_other) return;

    const delay = Number.isFinite(delayMs)
      ? Math.max(1500, delayMs)
      : Math.min(3000 * Math.pow(2, Math.max(0, state.wsReconnectAttempts - 1)), 30000);

    state.wsReconnectTimer = setTimeout(() => {
      state.wsReconnectTimer = null;
      _connectWebSocket();
    }, delay);
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

    if (payload.type === 'error' && payload.code === 'reply_locked') {
      state.threadState.reply_restricted_to_me = true;
      _renderThreadState();
      _showToast(payload.error || 'الردود مغلقة لهذه الرسائل الآلية.', 'warning');
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
        senderName: _trim(payload.sender_name),
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
      senderName: _trim(payload.sender_name),
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
    if (_isAutoPlatformThread()) return;
    dom.sheetBackdrop?.classList.remove('hidden');
    dom.optionsSheet?.classList.remove('hidden');
    requestAnimationFrame(() => {
      dom.sheetBackdrop?.classList.add('open');
      dom.optionsSheet?.classList.add('open');
    });
  }

  function _openClientRequestsSheet() {
    if (!_canShowProviderClientActions()) {
      _showToast('هذا الإجراء متاح فقط في رسائل المزوّد مع العميل', 'error');
      return;
    }
    if (!Number.isFinite(state.peer.id) || state.peer.id <= 0) {
      _showToast('تعذر تحديد العميل لعرض طلباته', 'error');
      return;
    }

    _renderClientRequestsLoading();
    dom.clientRequestsBackdrop?.classList.remove('hidden');
    dom.clientRequestsSheet?.classList.remove('hidden');
    requestAnimationFrame(() => {
      dom.clientRequestsBackdrop?.classList.add('open');
      dom.clientRequestsSheet?.classList.add('open');
    });
    _loadClientRequests();
  }

  function _closeClientRequestsSheet() {
    dom.clientRequestsBackdrop?.classList.remove('open');
    dom.clientRequestsSheet?.classList.remove('open');
    setTimeout(() => {
      dom.clientRequestsBackdrop?.classList.add('hidden');
      dom.clientRequestsSheet?.classList.add('hidden');
    }, 180);
  }

  async function _loadClientRequests() {
    if (!dom.clientRequestsBody) return;
    const peerId = _toInt(state.peer.id);
    if (!peerId || peerId <= 0) {
      _renderClientRequestsError('تعذر تحديد العميل لعرض طلباته');
      return;
    }

    const res = await ApiClient.get('/api/marketplace/provider/requests/?client_user_id=' + peerId);
    if (!res.ok) {
      _renderClientRequestsError(_extractError(res, 'تعذر تحميل طلبات العميل'));
      return;
    }
    const list = _asList(res.data);
    _renderClientRequestsList(list);
  }

  function _renderClientRequestsLoading() {
    if (!dom.clientRequestsBody) return;
    dom.clientRequestsBody.innerHTML = '';
    const stateEl = UI.el('div', { className: 'chat-client-requests-state' });
    stateEl.appendChild(UI.el('div', { className: 'spinner-inline' }));
    stateEl.appendChild(UI.el('p', { textContent: 'جاري تحميل طلبات العميل...' }));
    dom.clientRequestsBody.appendChild(stateEl);
  }

  function _renderClientRequestsError(message) {
    if (!dom.clientRequestsBody) return;
    dom.clientRequestsBody.innerHTML = '';
    const stateEl = UI.el('div', { className: 'chat-client-requests-state error' });
    stateEl.appendChild(UI.el('p', { textContent: message || 'تعذر تحميل طلبات العميل' }));
    dom.clientRequestsBody.appendChild(stateEl);
  }

  function _renderClientRequestsList(items) {
    if (!dom.clientRequestsBody) return;
    dom.clientRequestsBody.innerHTML = '';
    if (!items.length) {
      const empty = UI.el('div', { className: 'chat-client-requests-state' });
      empty.appendChild(UI.el('p', { textContent: 'لا توجد طلبات لهذا العميل' }));
      dom.clientRequestsBody.appendChild(empty);
      return;
    }

    const sorted = [...items].sort((a, b) => {
      const ta = new Date(a.created_at || 0).getTime();
      const tb = new Date(b.created_at || 0).getTime();
      return (Number.isFinite(tb) ? tb : 0) - (Number.isFinite(ta) ? ta : 0);
    });
    const current = sorted.filter((r) => {
      const g = _requestStatusGroup(r);
      return g !== 'completed' && g !== 'cancelled';
    });
    const previous = sorted.filter((r) => {
      const g = _requestStatusGroup(r);
      return g === 'completed' || g === 'cancelled';
    });

    if (current.length) {
      dom.clientRequestsBody.appendChild(UI.el('div', { className: 'chat-client-requests-section-title', textContent: 'الطلبات الحالية' }));
      current.forEach((req) => dom.clientRequestsBody.appendChild(_buildClientRequestCard(req)));
    }
    if (previous.length) {
      dom.clientRequestsBody.appendChild(UI.el('div', { className: 'chat-client-requests-section-title', textContent: 'الطلبات السابقة' }));
      previous.forEach((req) => dom.clientRequestsBody.appendChild(_buildClientRequestCard(req)));
    }
  }

  function _buildClientRequestCard(req) {
    const id = _toInt(req.id);
    const group = _requestStatusGroup(req);
    const statusLabel = _trim(req.status_label) || _requestStatusLabel(group);
    const statusColor = _requestStatusColor(group);
    const createdAtText = _formatRequestDate(req.created_at);
    const providerId = _toInt(req.provider);
    const myProviderId = _toInt(state.account.providerProfileId);
    const assignedToMe = Number.isFinite(providerId) && Number.isFinite(myProviderId) && providerId === myProviderId;

    const card = UI.el('button', { type: 'button', className: 'chat-client-request-card' });
    card.addEventListener('click', () => {
      if (!id || id <= 0) return;
      if (!assignedToMe) {
        _showToast('يمكن فتح تفاصيل الطلبات المسندة لك فقط', 'error');
        return;
      }
      window.location.href = '/provider-orders/' + id + '/';
    });

    const top = UI.el('div', { className: 'chat-client-request-top' });
    const status = UI.el('span', {
      className: 'chat-client-request-status',
      textContent: _requestDisplayId(id) + ' • ' + statusLabel,
    });
    status.style.color = statusColor;
    top.appendChild(status);
    card.appendChild(top);

    card.appendChild(UI.el('div', {
      className: 'chat-client-request-title',
      textContent: _trim(req.title) || 'طلب بدون عنوان',
    }));
    card.appendChild(UI.el('div', {
      className: 'chat-client-request-meta',
      textContent: createdAtText,
    }));

    return card;
  }

  function _requestDisplayId(id) {
    if (!Number.isFinite(id) || id <= 0) return 'R------';
    return 'R' + String(id).padStart(6, '0');
  }

  function _requestStatusGroup(req) {
    const raw = _trim(req?.status_group || req?.status).toLowerCase();
    if (raw === 'completed') return 'completed';
    if (raw === 'cancelled' || raw === 'canceled') return 'cancelled';
    if (raw === 'in_progress') return 'in_progress';
    return 'new';
  }

  function _requestStatusLabel(group) {
    if (group === 'completed') return 'مكتمل';
    if (group === 'cancelled') return 'ملغي';
    if (group === 'in_progress') return 'تحت التنفيذ';
    return 'جديد';
  }

  function _requestStatusColor(group) {
    if (group === 'completed') return '#15803d';
    if (group === 'cancelled') return '#b91c1c';
    if (group === 'in_progress') return '#b45309';
    return '#92400e';
  }

  function _formatRequestDate(value) {
    const dt = new Date(value);
    if (!Number.isFinite(dt.getTime())) return '';
    return dt.toLocaleDateString('ar-SA', {
      day: '2-digit',
      month: '2-digit',
      year: 'numeric',
    });
  }

  async function _sendServiceRequestLink() {
    if (!_canShowProviderClientActions()) {
      _showToast('هذا الإجراء متاح فقط في رسائل المزوّد مع العميل', 'error');
      return;
    }
    const providerId = _toInt(state.account.providerProfileId);
    if (!providerId || providerId <= 0) {
      _showToast('تعذر تحديد معرف المزوّد لإرسال الرابط', 'error');
      return;
    }

    const body = 'طلب خدمة مباشر:\nhttps://www.nawafthportal.com/service-request/?provider_id=' + providerId;
    const res = await ApiClient.request(_withMode('/api/messaging/direct/thread/' + state.threadId + '/messages/send/'), {
      method: 'POST',
      body: { body },
    });
    if (!res.ok) {
      _showToast(_extractError(res, 'فشل إرسال رابط الطلب'), 'error');
      return;
    }
    await _loadMessages({ forceScroll: true });
    _showToast('تم إرسال رابط طلب الخدمة', 'success');
    window.dispatchEvent(new Event('nw:badge-refresh'));
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
    _showToast(remove ? 'تمت إزالة الرسائل من المفضلة' : 'تمت إضافة الرسائل للمفضلة', 'success');
  }

  async function _toggleArchive() {
    const remove = !!state.threadState.is_archived;
    if (!remove && !window.confirm('أرشفة هذه الرسائل؟ سيتم إخفاؤها من قائمة الرسائل.')) return;

    const res = await ApiClient.request('/api/messaging/thread/' + state.threadId + '/archive/', {
      method: 'POST',
      body: remove ? { action: 'remove' } : {},
    });
    if (!res.ok) return _showToast(_extractError(res, 'تعذر تحديث الأرشفة'), 'error');

    state.threadState.is_archived = !!res.data?.is_archived;
    _renderThreadState();
    _showToast(remove ? 'تم إلغاء أرشفة الرسائل' : 'تمت أرشفة الرسائل', 'success');
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

  function _activeMode() {
    try {
      const params = new URLSearchParams(window.location.search || '');
      const modeFromUrl = _trim(params.get('mode')).toLowerCase();
      if (modeFromUrl === 'provider' || modeFromUrl === 'client') {
        sessionStorage.setItem('nw_account_mode', modeFromUrl);
        return modeFromUrl;
      }
    } catch (_) {}

    try {
      const mode = _trim(sessionStorage.getItem('nw_account_mode')).toLowerCase();
      if (mode === 'provider' || mode === 'client') return mode;
    } catch (_) {}
    const role = _trim(Auth.getRoleState()).toLowerCase();
    return role === 'provider' ? 'provider' : 'client';
  }

  function _withMode(path) {
    const mode = _activeMode();
    const sep = path.includes('?') ? '&' : '?';
    return path + sep + 'mode=' + encodeURIComponent(mode);
  }

  function _asList(data) {
    if (Array.isArray(data)) return data;
    if (data && Array.isArray(data.results)) return data.results;
    return [];
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
