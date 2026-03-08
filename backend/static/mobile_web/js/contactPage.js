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

  const NAME_TO_TYPE = {
    'الدعم الفني': 'tech',
    'الاشتراكات': 'subs',
    'التوثيق': 'verify',
    'الاقتراحات': 'suggest',
    'الإعلانات': 'ads',
    'الشكاوى والبلاغات': 'complaint',
    'الخدمات الإضافية': 'extras',
  };

  let _teams = [];
  let _tickets = [];
  let _selectedTicket = null;
  let _content = {};

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
    _setText('btn-support-refresh', _content.refreshLabel);
    _setText('btn-new-ticket', _content.newTicketLabel);
    _setText('contact-list-title', _content.listTitle);
    _setText('contact-create-title', _content.createTitle);
    _setText('contact-detail-title', _content.detailTitle);
    _setText('contact-empty-label', _content.emptyLabel);
    _setText('contact-team-label', _content.teamPlaceholder);
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
    _renderTickets();
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

  function _buildTicketItem(ticket) {
    const button = UI.el('button', {
      className: 'support-ticket-item' + (_selectedTicket && _selectedTicket.id === ticket.id ? ' active' : ''),
      type: 'button',
    });
    button.addEventListener('click', () => _selectTicket(ticket.id));

    const top = UI.el('div', { className: 'support-ticket-top' });
    top.appendChild(UI.el('span', { className: 'support-ticket-code', textContent: ticket.code || ('HD' + ticket.id) }));
    top.appendChild(
      UI.el('span', {
        className: 'support-ticket-status',
        textContent: _statusLabel(ticket.status),
        style: { backgroundColor: _statusColor(ticket.status) + '1A', color: _statusColor(ticket.status) },
      }),
    );

    const typeLabel = TICKET_TYPE_MAP[ticket.ticket_type] || ticket.ticket_type || 'بلاغ';
    const desc = String(ticket.description || '').trim();
    const text = desc.length > 80 ? desc.slice(0, 80) + '...' : desc;

    button.appendChild(top);
    button.appendChild(UI.el('div', { className: 'support-ticket-type', textContent: typeLabel }));
    button.appendChild(UI.el('div', { className: 'support-ticket-desc', textContent: text || 'بدون وصف' }));
    button.appendChild(UI.el('div', { className: 'support-ticket-time', textContent: _formatDate(ticket.created_at) }));
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

  async function _selectTicket(ticketId) {
    const detailRes = await ApiClient.get('/api/support/tickets/' + ticketId + '/');
    if (!detailRes.ok || !detailRes.data) {
      alert('تعذر تحميل تفاصيل البلاغ');
      return;
    }
    _selectedTicket = detailRes.data;
    _closeNewTicketForm();
    _renderTickets();
    _renderTicketDetail();
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
    const head = UI.el('div', { className: 'ticket-detail-head' });
    head.appendChild(UI.el('h3', { textContent: ticket.code || ('HD' + ticket.id) }));
    head.appendChild(
      UI.el('span', {
        className: 'support-ticket-status',
        textContent: _statusLabel(ticket.status),
        style: { backgroundColor: _statusColor(ticket.status) + '1A', color: _statusColor(ticket.status) },
      }),
    );
    body.appendChild(head);

    body.appendChild(UI.el('p', { className: 'ticket-detail-description', textContent: ticket.description || '' }));

    if (Array.isArray(ticket.attachments) && ticket.attachments.length) {
      const section = UI.el('div', { className: 'ticket-detail-section' });
      section.appendChild(UI.el('h4', { textContent: _content.attachmentsLabel || 'المرفقات' }));
      ticket.attachments.forEach((att) => {
        const href = ApiClient.mediaUrl(att.file);
        section.appendChild(
          UI.el('a', {
            className: 'ticket-attachment-link',
            href: href,
            target: '_blank',
            rel: 'noopener',
            textContent: String(att.file || '').split('/').pop() || 'مرفق',
          }),
        );
      });
      body.appendChild(section);
    }

    const comments = Array.isArray(ticket.comments) ? ticket.comments : [];
    const commentsSection = UI.el('div', { className: 'ticket-detail-section' });
    commentsSection.appendChild(UI.el('h4', { textContent: 'التعليقات' }));
    if (!comments.length) {
      commentsSection.appendChild(UI.el('p', { className: 'ticket-muted', textContent: 'لا توجد تعليقات بعد' }));
    } else {
      comments.forEach((comment) => {
        const row = UI.el('div', { className: 'ticket-comment' });
        row.appendChild(
          UI.el('div', {
            className: 'ticket-comment-meta',
            textContent: (comment.created_by_name || 'مستخدم') + ' • ' + _formatDate(comment.created_at),
          }),
        );
        row.appendChild(UI.el('div', { className: 'ticket-comment-text', textContent: comment.text || '' }));
        commentsSection.appendChild(row);
      });
    }
    body.appendChild(commentsSection);

    const reply = UI.el('div', { className: 'ticket-reply-box' });
    const input = UI.el('textarea', {
      id: 'ticket-reply-input',
      className: 'form-textarea',
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
    reply.appendChild(sendBtn);
    body.appendChild(reply);
  }

  function _openNewTicketForm() {
    const form = document.getElementById('new-ticket-form');
    const detail = document.getElementById('ticket-detail-view');
    if (form) form.classList.remove('hidden');
    if (detail) detail.classList.add('hidden');
  }

  function _closeNewTicketForm() {
    const form = document.getElementById('new-ticket-form');
    const detail = document.getElementById('ticket-detail-view');
    if (form) form.classList.add('hidden');
    if (detail) detail.classList.remove('hidden');
    _clearCreateError();
  }

  function _teamToTicketType(value) {
    const raw = String(value || '').trim();
    if (!raw) return '';
    if (TICKET_TYPE_MAP[raw]) return raw;
    if (NAME_TO_TYPE[raw]) return NAME_TO_TYPE[raw];
    return raw;
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
      body: { ticket_type: ticketType, description },
    });

    if (!createRes.ok || !createRes.data) {
      _setCreateLoading(false);
      _setCreateError((createRes.data && createRes.data.detail) || 'فشل إنشاء البلاغ');
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
    _renderTickets();
    if (ticketId) {
      await _selectTicket(ticketId);
    }
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
      alert((res.data && res.data.detail) || 'فشل إرسال التعليق');
      return;
    }

    input.value = '';
    await _selectTicket(ticketId);
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
