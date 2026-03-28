/* ===================================================================
   contactPage.js — Support tickets page
   GET  /api/support/teams/
   GET  /api/support/tickets/my/
   GET  /api/support/tickets/<id>/
   POST /api/support/tickets/create/
   POST /api/support/tickets/<id>/comments/
   POST /api/support/tickets/<id>/attachments/ (multipart)
   =================================================================== */
'use strict';

const ContactPage = (() => {
  const TICKET_TYPE_MAP = {
    tech: 'دعم فني',
    subs: 'اشتراكات',
    verify: 'توثيق',
    suggest: 'اقتراحات',
    ads: 'إعلانات',
    complaint: 'شكاوى وبلاغات',
    extras: 'خدمات إضافية',
  };

  const TEAM_CODE_TO_TICKET_TYPE = {
    support: 'tech',
    technical: 'tech',
    tech: 'tech',
    finance: 'subs',
    subs: 'subs',
    verification: 'verify',
    verify: 'verify',
    content: 'suggest',
    suggest: 'suggest',
    complaint: 'complaint',
    promo: 'ads',
    ads: 'ads',
    extras: 'extras',
  };

  const NAME_TO_TYPE = {
    'الدعم الفني': 'tech',
    'الاشتراكات': 'subs',
    'التوثيق': 'verify',
    'الاقتراحات': 'suggest',
    'الإعلانات': 'ads',
    'الشكاوى والبلاغات': 'complaint',
    'الخدمات الإضافية': 'extras',
    'فريق الدعم والمساعدة': 'tech',
    'فريق إدارة الترقية والاشتراكات': 'subs',
    'فريق التوثيق': 'verify',
    'فريق إدارة المحتوى': 'suggest',
    'فريق إدارة الإعلانات والترويج': 'ads',
    'فريق إدارة الخدمات الإضافية': 'extras',
  };

  let _teams = [];
  let _tickets = [];
  let _selectedTicket = null;
  let _content = {};
  let _toastTimer = null;
  let _preferredTicketId = _ticketIdFromUrl();

  async function init() {
    await _loadContent();
    if (!Auth.isLoggedIn()) {
      _showGate();
      return;
    }
    _hideGate();
    _bindActions();
    _loadInitial();
  }

  async function _loadContent() {
    const res = await ApiClient.get('/api/content/public/');
    const data = (res.ok && res.data && typeof res.data === 'object') ? res.data : {};
    const blocks = data.blocks || {};
    _content = {
      gateTitle: _resolve(blocks.contact_gate_title, 'سجّل دخولك'),
      gateDescription: _resolve(blocks.contact_gate_description, 'يجب تسجيل الدخول لعرض تذاكر الدعم'),
      gateLogin: _resolve(blocks.contact_gate_login_label, 'تسجيل الدخول'),
      pageTitle: _resolve(blocks.contact_page_title, 'تواصل مع منصة نوافذ'),
      refreshLabel: _resolve(blocks.contact_refresh_label, 'تحديث'),
      newTicketLabel: _resolve(blocks.contact_new_ticket_label, 'بلاغ جديد'),
      listTitle: _resolve(blocks.contact_list_title, 'قائمة البلاغات'),
      createTitle: _resolve(blocks.contact_create_title, 'إنشاء بلاغ جديد'),
      detailTitle: _resolve(blocks.contact_detail_title, 'تفاصيل البلاغ'),
      emptyLabel: _resolve(blocks.contact_empty_label, 'لا توجد بلاغات حتى الآن'),
      teamLabel: _resolve(blocks.contact_team_label, 'فريق الدعم'),
      teamPlaceholder: _resolve(blocks.contact_team_placeholder, 'اختر فريق الدعم'),
      descriptionLabel: _resolve(blocks.contact_description_label, 'التفاصيل'),
      attachmentsLabel: _resolve(blocks.contact_attachments_label, 'مرفقات (اختياري)'),
      cancelLabel: _resolve(blocks.contact_cancel_label, 'إلغاء'),
      submitLabel: _resolve(blocks.contact_submit_label, 'إرسال البلاغ'),
      replyPlaceholder: _resolve(blocks.contact_reply_placeholder, 'اكتب تعليقك...'),
      replySubmitLabel: _resolve(blocks.contact_reply_submit_label, 'إرسال التعليق'),
    };
    _applyContent();
  }

  function _applyContent() {
    _setText('contact-gate-title', _content.gateTitle);
    _setText('contact-gate-description', _content.gateDescription);
    _setText('contact-gate-login', _content.gateLogin);
    _setText('contact-page-title', _content.pageTitle);
    _setText('contact-refresh-label', _content.refreshLabel);
    _setText('contact-new-ticket-label', _content.newTicketLabel);
    _setText('contact-list-title', _content.listTitle);
    _setText('contact-create-title', _content.createTitle);
    _setText('contact-detail-title', _content.detailTitle);
    _setText('contact-empty-label', _content.emptyLabel);
    _setText('contact-team-label', _content.teamLabel);
    _setText('contact-description-label', _content.descriptionLabel);
    _setText('contact-attachments-label', _content.attachmentsLabel);
    _setText('btn-cancel-ticket', _content.cancelLabel);
    _setText('submit-ticket-text', _content.submitLabel);
  }

  function _showGate() {
    const gate = document.getElementById('auth-gate');
    const content = document.getElementById('support-content');
    if (gate) gate.classList.remove('hidden');
    if (content) content.classList.add('hidden');
  }

  function _hideGate() {
    const gate = document.getElementById('auth-gate');
    const content = document.getElementById('support-content');
    if (gate) gate.classList.add('hidden');
    if (content) content.classList.remove('hidden');
  }

  function _bindActions() {
    const refreshBtn = document.getElementById('btn-support-refresh');
    const newBtn = document.getElementById('btn-new-ticket');
    const cancelBtn = document.getElementById('btn-cancel-ticket');
    const submitBtn = document.getElementById('btn-submit-ticket');

    if (refreshBtn) refreshBtn.addEventListener('click', _loadInitial);
    if (newBtn) newBtn.addEventListener('click', _openNewTicketForm);
    if (cancelBtn) cancelBtn.addEventListener('click', _closeNewTicketForm);
    if (submitBtn) submitBtn.addEventListener('click', _createTicket);
  }

  async function _loadInitial() {
    _setListLoading(true);
    _setListError('');

    await Promise.all([
      _loadTeams(),
      _loadTickets(),
    ]);

    _setListLoading(false);
    _renderSummary();
    _renderTickets();
    if (!_tickets.length) {
      _selectedTicket = null;
      _preferredTicketId = null;
      _syncTicketQueryParam(null);
      _renderTicketDetail();
      return;
    }

    const currentSelectedId = _selectedTicket && _tickets.some((ticket) => ticket && ticket.id === _selectedTicket.id)
      ? _selectedTicket.id
      : null;
    const preferredId = _preferredTicketId || currentSelectedId || _tickets[0].id;
    if (preferredId) {
      const selected = await _selectTicket(preferredId, { silent: true });
      if (selected) return;
    }

    if (_tickets[0] && _tickets[0].id && _tickets[0].id !== preferredId) {
      await _selectTicket(_tickets[0].id, { silent: true });
    }
  }

  async function _loadTeams() {
    const res = await ApiClient.get('/api/support/teams/');
    if (!res.ok || !Array.isArray(res.data)) {
      _teams = [];
      _renderTeams();
      return;
    }
    _teams = res.data;
    _renderTeams();
  }

  function _renderTeams() {
    const select = document.getElementById('support-team');
    if (!select) return;
    select.innerHTML = '';

    const placeholder = UI.el('option', {
      value: '',
      textContent: _content.teamPlaceholder || 'اختر فريق الدعم',
    });
    select.appendChild(placeholder);

    if (_teams.length) {
      _teams.forEach((team) => {
        const label = team.name_ar || team.code || '';
        if (!label) return;
        const option = UI.el('option', {
          value: team.code || label,
          textContent: label,
        });
        select.appendChild(option);
      });
      return;
    }

    Object.entries(TICKET_TYPE_MAP).forEach(([code, label]) => {
      const option = UI.el('option', { value: code, textContent: label });
      select.appendChild(option);
    });
  }

  async function _loadTickets() {
    const res = await ApiClient.get('/api/support/tickets/my/');
    if (!res.ok) {
      _tickets = [];
      _setListError((res.data && res.data.detail) || 'فشل تحميل البلاغات');
      return;
    }

    if (Array.isArray(res.data)) {
      _tickets = res.data;
      return;
    }

    _tickets = Array.isArray(res.data && res.data.results) ? res.data.results : [];
  }

  function _setListLoading(loading) {
    const el = document.getElementById('support-list-loading');
    if (!el) return;
    el.classList.toggle('hidden', !loading);
  }

  function _setListError(message) {
    const el = document.getElementById('support-list-error');
    if (!el) return;
    if (!message) {
      el.textContent = '';
      el.classList.add('hidden');
      return;
    }
    el.textContent = message;
    el.classList.remove('hidden');
  }

  function _renderTickets() {
    const list = document.getElementById('support-ticket-list');
    const empty = document.getElementById('support-list-empty');
    if (!list || !empty) return;
    list.innerHTML = '';

    if (!_tickets.length) {
      empty.classList.remove('hidden');
      list.classList.add('hidden');
      return;
    }

    empty.classList.add('hidden');
    list.classList.remove('hidden');
    const frag = document.createDocumentFragment();
    _tickets.forEach((ticket) => {
      frag.appendChild(_buildTicketItem(ticket));
    });
    list.appendChild(frag);
  }

  function _renderSummary() {
    const totalEl = document.getElementById('support-total-count');
    const openEl = document.getElementById('support-open-count');
    const closedEl = document.getElementById('support-closed-count');
    const total = _tickets.length;
    let closed = 0;

    _tickets.forEach((ticket) => {
      if (String(ticket && ticket.status || '').toLowerCase() === 'closed') {
        closed += 1;
      }
    });

    const open = Math.max(0, total - closed);
    if (totalEl) totalEl.textContent = String(total);
    if (openEl) openEl.textContent = String(open);
    if (closedEl) closedEl.textContent = String(closed);
  }

  function _ticketTypeLabel(value) {
    return TICKET_TYPE_MAP[value] || value || 'بلاغ';
  }

  function _ticketCodeLabel(ticket) {
    return ticket.code || ('HD' + ticket.id);
  }

  function _buildTicketItem(ticket) {
    const button = UI.el('button', {
      className: 'support-ticket-item' + (_selectedTicket && _selectedTicket.id === ticket.id ? ' active' : ''),
      type: 'button',
    });
    button.addEventListener('click', () => _selectTicket(ticket.id));

    const top = UI.el('div', { className: 'support-ticket-top' });
    top.appendChild(UI.el('span', { className: 'support-ticket-code', textContent: _ticketCodeLabel(ticket) }));
    top.appendChild(
      UI.el('span', {
        className: 'support-ticket-status',
        textContent: _statusLabel(ticket.status),
        style: { backgroundColor: _statusColor(ticket.status) + '1A', color: _statusColor(ticket.status) },
      }),
    );

    const typeLabel = _ticketTypeLabel(ticket.ticket_type);
    const desc = String(ticket.description || '').trim();
    const text = desc.length > 80 ? desc.slice(0, 80) + '...' : desc;
    const meta = UI.el('div', { className: 'support-ticket-meta' });
    meta.appendChild(UI.el('span', { className: 'support-ticket-type', textContent: typeLabel }));
    meta.appendChild(UI.el('span', { className: 'support-ticket-time', textContent: _formatDate(ticket.created_at) }));

    const footer = UI.el('div', { className: 'support-ticket-footer' });
    footer.appendChild(UI.el('span', { className: 'support-ticket-footer-label', textContent: 'عرض التفاصيل' }));
    footer.appendChild(UI.el('span', { className: 'support-ticket-footer-arrow', textContent: '‹' }));

    button.appendChild(top);
    button.appendChild(meta);
    button.appendChild(UI.el('div', { className: 'support-ticket-desc', textContent: text || 'بدون وصف' }));
    button.appendChild(footer);
    return button;
  }

  function _statusLabel(status) {
    const map = {
      new: 'جديد',
      in_progress: 'تحت المعالجة',
      returned: 'معاد',
      closed: 'مغلق',
    };
    return map[String(status || '').toLowerCase()] || String(status || '');
  }

  function _statusColor(status) {
    const s = String(status || '').toLowerCase();
    if (s === 'new') return '#2563EB';
    if (s === 'in_progress') return '#7C3AED';
    if (s === 'returned') return '#F59E0B';
    if (s === 'closed') return '#6B7280';
    return '#6B7280';
  }

  function _formatDate(value) {
    if (!value) return '';
    const dt = new Date(value);
    if (Number.isNaN(dt.getTime())) return '';
    return dt.toLocaleString('ar-SA', {
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
    });
  }

  async function _selectTicket(ticketId, options) {
    const opts = options || {};
    const detailRes = await ApiClient.get('/api/support/tickets/' + ticketId + '/');
    if (!detailRes.ok || !detailRes.data) {
      if (!opts.silent) _notify('تعذر تحميل تفاصيل البلاغ', 'error');
      return false;
    }
    _selectedTicket = detailRes.data;
    _preferredTicketId = _selectedTicket && _selectedTicket.id ? _selectedTicket.id : ticketId;
    _syncTicketQueryParam(_preferredTicketId);
    _closeNewTicketForm();
    _renderTickets();
    _renderTicketDetail();
    return true;
  }

  function _renderTicketDetail() {
    const empty = document.getElementById('ticket-detail-empty');
    const body = document.getElementById('ticket-detail-body');
    if (!empty || !body) return;

    if (!_selectedTicket) {
      empty.classList.remove('hidden');
      body.classList.add('hidden');
      body.innerHTML = '';
      return;
    }

    empty.classList.add('hidden');
    body.classList.remove('hidden');
    body.innerHTML = '';

    const ticket = _selectedTicket;
    const attachments = Array.isArray(ticket.attachments) ? ticket.attachments : [];
    const comments = Array.isArray(ticket.comments) ? ticket.comments : [];
    const hero = UI.el('section', { className: 'ticket-detail-hero' });
    const head = UI.el('div', { className: 'ticket-detail-head' });
    const titleWrap = UI.el('div', { className: 'ticket-detail-title-wrap' });
    titleWrap.appendChild(UI.el('span', { className: 'ticket-detail-code', textContent: _ticketCodeLabel(ticket) }));
    titleWrap.appendChild(UI.el('h3', { textContent: _ticketTypeLabel(ticket.ticket_type) }));
    head.appendChild(titleWrap);
    head.appendChild(
      UI.el('span', {
        className: 'support-ticket-status',
        textContent: _statusLabel(ticket.status),
        style: { backgroundColor: _statusColor(ticket.status) + '1A', color: _statusColor(ticket.status) },
      }),
    );
    hero.appendChild(head);

    const metaGrid = UI.el('div', { className: 'ticket-detail-meta-grid' });
    metaGrid.appendChild(_buildDetailMetaCard('تاريخ الإنشاء', _formatDate(ticket.created_at) || '—'));
    metaGrid.appendChild(_buildDetailMetaCard('المرفقات', String(attachments.length)));
    metaGrid.appendChild(_buildDetailMetaCard('التعليقات', String(comments.length)));
    metaGrid.appendChild(_buildDetailMetaCard('الحالة', _statusLabel(ticket.status)));
    hero.appendChild(metaGrid);
    body.appendChild(hero);

    const descriptionSection = UI.el('div', { className: 'ticket-detail-section' });
    descriptionSection.appendChild(_buildSectionHead('وصف البلاغ'));
    descriptionSection.appendChild(
      UI.el('div', {
        className: 'ticket-detail-description',
        textContent: ticket.description || 'لا يوجد وصف مرفق لهذا البلاغ.',
      }),
    );
    body.appendChild(descriptionSection);

    const attachmentsSection = UI.el('div', { className: 'ticket-detail-section' });
    attachmentsSection.appendChild(_buildSectionHead(_content.attachmentsLabel || 'المرفقات', attachments.length));
    if (!attachments.length) {
      attachmentsSection.appendChild(UI.el('p', { className: 'ticket-muted', textContent: 'لا توجد مرفقات مضافة لهذا البلاغ' }));
    } else {
      const attachmentsList = UI.el('div', { className: 'ticket-attachments-list' });
      attachments.forEach((att) => {
        const href = ApiClient.mediaUrl(att.file);
        const link = UI.el('a', {
          className: 'ticket-attachment-link',
          href: href,
          target: '_blank',
          rel: 'noopener',
        });
        link.appendChild(UI.el('span', { className: 'ticket-attachment-icon', textContent: '↗' }));
        link.appendChild(
          UI.el('span', {
            className: 'ticket-attachment-name',
            textContent: String(att.file || '').split('/').pop() || 'مرفق',
          }),
        );
        attachmentsList.appendChild(link);
      });
      attachmentsSection.appendChild(attachmentsList);
    }
    body.appendChild(attachmentsSection);

    const commentsSection = UI.el('div', { className: 'ticket-detail-section' });
    commentsSection.appendChild(_buildSectionHead('التعليقات', comments.length));
    if (!comments.length) {
      commentsSection.appendChild(UI.el('p', { className: 'ticket-muted', textContent: 'لا توجد تعليقات بعد' }));
    } else {
      const commentsList = UI.el('div', { className: 'ticket-comments-list' });
      comments.forEach((comment) => {
        const row = UI.el('div', { className: 'ticket-comment' });
        row.appendChild(
          UI.el('div', {
            className: 'ticket-comment-meta',
            textContent: (comment.created_by_name || 'مستخدم') + ' • ' + _formatDate(comment.created_at),
          }),
        );
        row.appendChild(UI.el('div', { className: 'ticket-comment-text', textContent: comment.text || '' }));
        commentsList.appendChild(row);
      });
      commentsSection.appendChild(commentsList);
    }
    body.appendChild(commentsSection);

    const reply = UI.el('div', { className: 'ticket-reply-box' });
    const replyHead = UI.el('div', { className: 'ticket-reply-head' });
    replyHead.appendChild(UI.el('h4', { textContent: 'أضف تعليقًا جديدًا' }));
    replyHead.appendChild(UI.el('p', { textContent: 'سيظهر تعليقك ضمن سجل البلاغ ليسهل متابعة الحالة.' }));
    reply.appendChild(replyHead);

    const input = UI.el('textarea', {
      id: 'ticket-reply-input',
      className: 'form-textarea ticket-reply-input',
      maxlength: '300',
      placeholder: _content.replyPlaceholder || 'اكتب تعليقك...',
    });
    const sendBtn = UI.el('button', {
      type: 'button',
      className: 'btn-primary',
      textContent: _content.replySubmitLabel || 'إرسال التعليق',
    });
    sendBtn.addEventListener('click', () => _sendComment(ticket.id));
    reply.appendChild(input);
    const replyActions = UI.el('div', { className: 'ticket-reply-actions' });
    replyActions.appendChild(sendBtn);
    reply.appendChild(replyActions);
    body.appendChild(reply);
  }

  function _buildDetailMetaCard(label, value) {
    const card = UI.el('div', { className: 'ticket-detail-meta-card' });
    card.appendChild(UI.el('span', { textContent: label }));
    card.appendChild(UI.el('strong', { textContent: value || '—' }));
    return card;
  }

  function _buildSectionHead(title, count) {
    const head = UI.el('div', { className: 'ticket-section-head' });
    head.appendChild(UI.el('h4', { textContent: title }));
    if (count !== undefined && count !== null) {
      head.appendChild(UI.el('span', { className: 'ticket-section-count', textContent: String(count) }));
    }
    return head;
  }

  function _openNewTicketForm() {
    const form = document.getElementById('new-ticket-form');
    const detail = document.getElementById('ticket-detail-view');
    const newBtn = document.getElementById('btn-new-ticket');
    if (form) form.classList.remove('hidden');
    if (detail) detail.classList.add('hidden');
    if (newBtn) newBtn.classList.add('is-active');
    _syncTicketQueryParam(null);
    _clearCreateError();

    const desc = document.getElementById('support-description');
    if (desc) desc.focus();
  }

  function _closeNewTicketForm() {
    const form = document.getElementById('new-ticket-form');
    const detail = document.getElementById('ticket-detail-view');
    const newBtn = document.getElementById('btn-new-ticket');
    if (form) form.classList.add('hidden');
    if (detail) detail.classList.remove('hidden');
    if (newBtn) newBtn.classList.remove('is-active');
    _syncTicketQueryParam(_selectedTicket && _selectedTicket.id ? _selectedTicket.id : _preferredTicketId);
    _clearCreateError();
  }

  function _teamToTicketType(value) {
    const raw = String(value || '').trim();
    if (!raw) return '';
    const normalized = raw.toLowerCase();
    if (TICKET_TYPE_MAP[normalized]) return normalized;
    if (TEAM_CODE_TO_TICKET_TYPE[normalized]) return TEAM_CODE_TO_TICKET_TYPE[normalized];
    if (/^\d+$/.test(raw)) {
      const team = _teams.find((item) => String(item && item.id) === raw);
      const teamCode = String(team && team.code || '').trim().toLowerCase();
      if (teamCode && TEAM_CODE_TO_TICKET_TYPE[teamCode]) {
        return TEAM_CODE_TO_TICKET_TYPE[teamCode];
      }
    }
    if (NAME_TO_TYPE[raw]) return NAME_TO_TYPE[raw];
    return raw;
  }

  function _extractApiErrorMessage(payload, fallback) {
    if (payload && typeof payload.detail === 'string' && payload.detail.trim()) {
      return payload.detail.trim();
    }
    if (payload && typeof payload === 'object') {
      const values = Object.values(payload);
      for (const value of values) {
        if (typeof value === 'string' && value.trim()) return value.trim();
        if (Array.isArray(value) && value.length && typeof value[0] === 'string' && value[0].trim()) {
          return value[0].trim();
        }
      }
    }
    return fallback;
  }

  async function _createTicket() {
    const teamEl = document.getElementById('support-team');
    const descEl = document.getElementById('support-description');
    const filesEl = document.getElementById('support-files');
    if (!teamEl || !descEl || !filesEl) return;

    const ticketType = _teamToTicketType(teamEl.value);
    const description = String(descEl.value || '').trim();

    if (!ticketType || !description) {
      _setCreateError('الرجاء اختيار فريق الدعم وكتابة التفاصيل');
      return;
    }

    _setCreateLoading(true);
    _clearCreateError();

    const createRes = await ApiClient.request('/api/support/tickets/create/', {
      method: 'POST',
      body: {
        ticket_type: ticketType,
        assigned_team: String(teamEl.value || '').trim(),
        description,
      },
    });

    if (!createRes.ok || !createRes.data) {
      _setCreateLoading(false);
      _setCreateError(_extractApiErrorMessage(createRes.data, 'فشل إنشاء البلاغ'));
      return;
    }

    const ticketId = createRes.data.id;
    const files = Array.from(filesEl.files || []);
    if (ticketId && files.length) {
      for (const file of files) {
        const formData = new FormData();
        formData.append('file', file);
        await ApiClient.request('/api/support/tickets/' + ticketId + '/attachments/', {
          method: 'POST',
          body: formData,
          formData: true,
        });
      }
    }

    descEl.value = '';
    teamEl.value = '';
    filesEl.value = '';
    _setCreateLoading(false);
    _closeNewTicketForm();
    await _loadTickets();
    _renderSummary();
    _renderTickets();
    if (ticketId) {
      await _selectTicket(ticketId);
    }
    _notify('تم إنشاء البلاغ بنجاح', 'success');
  }

  async function _sendComment(ticketId) {
    const input = document.getElementById('ticket-reply-input');
    if (!input) return;
    const text = String(input.value || '').trim();
    if (!text) return;

    const res = await ApiClient.request('/api/support/tickets/' + ticketId + '/comments/', {
      method: 'POST',
      body: { text },
    });
    if (!res.ok) {
      _notify((res.data && res.data.detail) || 'فشل إرسال التعليق', 'error');
      return;
    }

    input.value = '';
    await _selectTicket(ticketId);
    _notify('تمت إضافة التعليق', 'success');
  }

  function _setCreateLoading(loading) {
    const btn = document.getElementById('btn-submit-ticket');
    const txt = document.getElementById('submit-ticket-text');
    const spin = document.getElementById('submit-ticket-spinner');
    if (btn) btn.disabled = loading;
    if (txt) txt.classList.toggle('hidden', loading);
    if (spin) spin.classList.toggle('hidden', !loading);
  }

  function _setCreateError(message) {
    const el = document.getElementById('support-create-error');
    if (!el) return;
    el.textContent = message;
    el.classList.remove('hidden');
  }

  function _clearCreateError() {
    const el = document.getElementById('support-create-error');
    if (!el) return;
    el.textContent = '';
    el.classList.add('hidden');
  }

  function _notify(message, type) {
    const toast = document.getElementById('contact-toast');
    if (!toast) {
      alert(message || '');
      return;
    }

    toast.textContent = message || '';
    toast.classList.remove('show', 'success', 'error');
    if (type) toast.classList.add(type);
    requestAnimationFrame(() => toast.classList.add('show'));
    window.clearTimeout(_toastTimer);
    _toastTimer = window.setTimeout(() => toast.classList.remove('show'), 2400);
  }

  function _ticketIdFromUrl() {
    try {
      const params = new URLSearchParams(window.location.search || '');
      const raw = String(params.get('ticket') || '').trim();
      const parsed = Number(raw);
      if (Number.isFinite(parsed) && parsed > 0) {
        return Math.floor(parsed);
      }
    } catch (_) {}
    return null;
  }

  function _syncTicketQueryParam(ticketId) {
    if (!window.history || typeof window.history.replaceState !== 'function') return;
    try {
      const url = new URL(window.location.href);
      if (ticketId) {
        url.searchParams.set('ticket', String(ticketId));
      } else {
        url.searchParams.delete('ticket');
      }
      const nextUrl = url.pathname + url.search + url.hash;
      window.history.replaceState({}, '', nextUrl);
    } catch (_) {}
  }

  function _resolve(block, fallback) {
    return String(block && block.title_ar || '').trim() || fallback;
  }

  function _setText(id, value) {
    const el = document.getElementById(id);
    if (el && value) el.textContent = value;
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  return {};
})();
