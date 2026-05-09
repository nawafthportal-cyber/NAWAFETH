/* ===================================================================
  contactPage.js — Support tickets & report tracking page
  GET  /api/support/teams/
  GET  /api/support/tickets/my/
  GET  /api/support/tickets/<id>/
  POST /api/support/tickets/create/
  POST /api/support/tickets/<id>/comments/
  POST /api/support/tickets/<id>/attachments/ (multipart)
  GET  /api/moderation/cases/my/
  GET  /api/moderation/cases/<id>/
  =================================================================== */
'use strict';

const ContactPage = (() => {
  const COPY = {
    ar: {
      pageTitle: 'تواصل معنا',
      gatePoint1: 'عرض سجل البلاغات السابقة',
      gatePoint2: 'متابعة الحالة والتعليقات',
      gatePoint3: 'رفع المرفقات من نفس الواجهة',
      heroEyebrow: 'مركز الدعم والمساعدة',
      heroSubtitle: 'قدّم بلاغًا جديدًا، تابع حالة تذاكرك، وأضف التعليقات والمرفقات من واجهة أوضح وأكثر ترتيبًا.',
      heroTag1: 'متابعة منظمة',
      heroTag2: 'سجل كامل للتعليقات',
      heroTag3: 'رفع مرفقات بسهولة',
      highlightLabel1: 'تجربة واضحة',
      highlightBody1: 'تفاصيل البلاغ، حالته، ومرفقاته معروضة في لوحة واحدة مرتبة وسهلة التتبع.',
      highlightLabel2: 'تواصل أسرع',
      highlightBody2: 'أضف تعليقًا جديدًا أو افتح بلاغًا آخر بدون مغادرة نفس الواجهة.',
      totalTicketsLabel: 'إجمالي البلاغات',
      openTicketsLabel: 'قيد المتابعة',
      closedTicketsLabel: 'مغلقة',
      journeyEyebrow: 'رحلة الدعم باختصار',
      step1Title: 'أنشئ البلاغ',
      step1Body: 'اختر الفريق المناسب ثم اكتب وصفًا واضحًا وأضف ما يلزم من ملفات.',
      step2Title: 'تابع التحديثات',
      step2Body: 'راجع الحالة الحالية وسجل التعليقات بدون التنقل بين أكثر من شاشة.',
      step3Title: 'أكمل الحوار',
      step3Body: 'أضف تعليقًا جديدًا عند الحاجة ليبقى مسار المتابعة واضحًا ومكتملًا.',
      toolbarTitle: 'لوحة دعم أنظف وأوضح',
      toolbarSubtitle: 'بدّل بين تحديث القائمة وفتح بلاغ جديد من شريط أوامر سريع ومباشر.',
      listKicker: 'مركز البلاغات',
      listSubtitle: 'تابع جميع البلاغات التي أرسلتها وحالتها الحالية.',
      listNote: 'تحديث حي للحالة',
      createKicker: 'إنشاء بلاغ',
      createSubtitle: 'اختر الجهة المناسبة ثم اكتب وصفًا واضحًا للمشكلة أو الطلب.',
      createNote: 'نموذج سريع',
      descriptionPlaceholder: 'اشرح المشكلة أو الطلب بشكل واضح ومختصر...',
      attachmentsHint: 'يمكنك إرفاق صور أو ملفات تساعد الفريق على فهم البلاغ بسرعة.',
      detailKicker: 'قراءة ومتابعة',
      detailHelper: 'هنا ستجد الحالة، الوصف، المرفقات، والتعليقات المرتبطة بالبلاغ.',
      detailNote: 'تفاصيل كاملة',
      detailEmptyLabel: 'اختر بلاغًا من القائمة لعرض التفاصيل',
      typeFallback: 'بلاغ',
      viewDetails: 'عرض التفاصيل',
      noDescription: 'بدون وصف',
      statusNew: 'جديد',
      statusInProgress: 'تحت المعالجة',
      statusReturned: 'معاد',
      statusClosed: 'مغلق',
      statusUnderReview: 'قيد المراجعة',
      statusActionTaken: 'تم اتخاذ إجراء',
      statusDismissed: 'مرفوض / بدون إجراء',
      statusEscalated: 'مصعّد',
      createdAtLabel: 'تاريخ الإنشاء',
      attachmentsCountLabel: 'المرفقات',
      commentsCountLabel: 'التعليقات',
      actionsCountLabel: 'سجل المعالجة',
      decisionsCountLabel: 'القرارات',
      statusLabel: 'الحالة',
      descriptionSectionTitle: 'وصف البلاغ',
      noTicketDescription: 'لا يوجد وصف مرفق لهذا البلاغ.',
      noTicketAttachments: 'لا توجد مرفقات مضافة لهذا البلاغ',
      attachmentFallback: 'مرفق',
      commentsSectionTitle: 'التعليقات',
      noComments: 'لا توجد تعليقات بعد',
      activitySectionTitle: 'سجل المعالجة',
      noActivity: 'لا توجد تحديثات تشغيلية بعد',
      sourceLabel: 'المصدر',
      reasonLabel: 'سبب البلاغ',
      linkedTicketLabel: 'التذكرة المرتبطة',
      categoryService: 'بلاغ خدمة',
      categorySpotlight: 'بلاغ لمحة',
      categoryPortfolio: 'بلاغ خدمات ومشاريع',
      categoryComplaint: 'بلاغ محتوى',
      caseFallback: 'بلاغ محتوى',
      userFallback: 'مستخدم',
      originalLanguageNotice: 'بعض تفاصيل البلاغ والأسماء والتعليقات تُعرض بلغتها الأصلية.',
      replyTitle: 'أضف تعليقًا جديدًا',
      replyHint: 'سيظهر تعليقك ضمن سجل البلاغ ليسهل متابعة الحالة.',
      createValidation: 'الرجاء اختيار فريق الدعم وكتابة التفاصيل',
      createFailed: 'فشل إنشاء البلاغ',
      createSuccess: 'تم إنشاء البلاغ بنجاح',
      commentFailed: 'فشل إرسال التعليق',
      commentSuccess: 'تمت إضافة التعليق',
      loadDetailsFailed: 'تعذر تحميل تفاصيل البلاغ',
      listLoadFailed: 'فشل تحميل البلاغات',
      ticketTypes: {
        tech: 'دعم فني',
        subs: 'اشتراكات',
        verify: 'توثيق',
        suggest: 'اقتراحات',
        ads: 'إعلانات',
        complaint: 'شكاوى وبلاغات',
        extras: 'خدمات إضافية',
      },
    },
    en: {
      pageTitle: 'Contact Nawafeth',
      gatePoint1: 'View your previous ticket history',
      gatePoint2: 'Track status updates and comments',
      gatePoint3: 'Upload attachments from the same interface',
      heroEyebrow: 'Support center',
      heroSubtitle: 'Create a new ticket, track your requests, and add comments and attachments from a clearer, better organized interface.',
      heroTag1: 'Organized follow-up',
      heroTag2: 'Complete comment history',
      heroTag3: 'Easy attachments',
      highlightLabel1: 'Clear experience',
      highlightBody1: 'Ticket details, status, and attachments are shown in one organized view that is easy to follow.',
      highlightLabel2: 'Faster communication',
      highlightBody2: 'Add a new comment or open another ticket without leaving the same interface.',
      totalTicketsLabel: 'Total tickets',
      openTicketsLabel: 'In progress',
      closedTicketsLabel: 'Closed',
      journeyEyebrow: 'Support flow at a glance',
      step1Title: 'Create the ticket',
      step1Body: 'Choose the right team, write a clear description, and attach any needed files.',
      step2Title: 'Track updates',
      step2Body: 'Review the current status and comment history without moving across multiple screens.',
      step3Title: 'Continue the thread',
      step3Body: 'Add a new comment when needed so the follow-up path stays clear and complete.',
      toolbarTitle: 'A cleaner support workspace',
      toolbarSubtitle: 'Switch between refreshing the list and opening a new ticket from one fast, direct command bar.',
      listKicker: 'Ticket center',
      listSubtitle: 'Track every ticket you submitted and its current status.',
      listNote: 'Live status updates',
      createKicker: 'Create ticket',
      createSubtitle: 'Choose the right destination and write a clear description of the issue or request.',
      createNote: 'Quick form',
      descriptionPlaceholder: 'Describe the issue or request clearly and briefly...',
      attachmentsHint: 'You can attach images or files that help the team understand the ticket faster.',
      detailKicker: 'Read and follow up',
      detailHelper: 'Here you will find the status, description, attachments, and comments linked to the ticket.',
      detailNote: 'Full details',
      detailEmptyLabel: 'Choose a ticket from the list to view its details',
      typeFallback: 'Ticket',
      viewDetails: 'View details',
      noDescription: 'No description',
      statusNew: 'New',
      statusInProgress: 'In progress',
      statusReturned: 'Returned',
      statusClosed: 'Closed',
      statusUnderReview: 'Under review',
      statusActionTaken: 'Action taken',
      statusDismissed: 'Dismissed',
      statusEscalated: 'Escalated',
      createdAtLabel: 'Created at',
      attachmentsCountLabel: 'Attachments',
      commentsCountLabel: 'Comments',
      actionsCountLabel: 'Activity',
      decisionsCountLabel: 'Decisions',
      statusLabel: 'Status',
      descriptionSectionTitle: 'Ticket description',
      noTicketDescription: 'No description is attached to this ticket.',
      noTicketAttachments: 'No attachments were added to this ticket',
      attachmentFallback: 'Attachment',
      commentsSectionTitle: 'Comments',
      noComments: 'No comments yet',
      activitySectionTitle: 'Activity log',
      noActivity: 'No operational updates yet',
      sourceLabel: 'Source',
      reasonLabel: 'Reason',
      linkedTicketLabel: 'Linked ticket',
      categoryService: 'Service report',
      categorySpotlight: 'Spotlight report',
      categoryPortfolio: 'Portfolio report',
      categoryComplaint: 'Content report',
      caseFallback: 'Content report',
      userFallback: 'User',
      originalLanguageNotice: 'Some ticket details, names, and comments are shown in their original language.',
      replyTitle: 'Add a new comment',
      replyHint: 'Your comment will appear in the ticket timeline to keep follow-up clear.',
      createValidation: 'Please choose a support team and enter the details.',
      createFailed: 'Failed to create the ticket',
      createSuccess: 'Ticket created successfully',
      commentFailed: 'Failed to send the comment',
      commentSuccess: 'Comment added successfully',
      loadDetailsFailed: 'Unable to load ticket details',
      listLoadFailed: 'Failed to load tickets',
      ticketTypes: {
        tech: 'Technical support',
        subs: 'Subscriptions',
        verify: 'Verification',
        suggest: 'Suggestions',
        ads: 'Advertising',
        complaint: 'Complaints & reports',
        extras: 'Additional services',
      },
    },
  };

  const TICKET_TYPE_MAP = COPY.ar.ticketTypes;

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
  let _cases = [];
  let _records = [];
  let _selectedRecord = null;
  let _content = {};
  let _contentBlocks = {};
  let _toastTimer = null;
  let _preferredSelection = _selectionFromUrl();

  async function init() {
    _applyStaticCopy();
    document.addEventListener('nawafeth:languagechange', _handleLanguageChange);
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
    _contentBlocks = data.blocks || {};
    _refreshContent();
  }

  function _refreshContent() {
    const blocks = _contentBlocks || {};
    const copy = _copy();
    _content = {
      gateTitle: _resolve(blocks.contact_gate_title, 'سجّل دخولك', 'Sign in first'),
      gateDescription: _resolve(blocks.contact_gate_description, 'يجب تسجيل الدخول لعرض تذاكر الدعم وفتح بلاغ جديد.', 'Sign in to view support tickets and create a new request.'),
      gateLogin: _resolve(blocks.contact_gate_login_label, 'تسجيل الدخول', 'Sign in'),
      pageTitle: _resolve(blocks.contact_page_title, 'تواصل مع منصة نوافذ', 'Contact Nawafeth platform'),
      refreshLabel: _resolve(blocks.contact_refresh_label, 'تحديث', 'Refresh'),
      newTicketLabel: _resolve(blocks.contact_new_ticket_label, 'بلاغ جديد', 'New ticket'),
      listTitle: _resolve(blocks.contact_list_title, 'قائمة البلاغات', 'Ticket list'),
      createTitle: _resolve(blocks.contact_create_title, 'إنشاء بلاغ جديد', 'Create a new ticket'),
      detailTitle: _resolve(blocks.contact_detail_title, 'تفاصيل البلاغ', 'Ticket details'),
      emptyLabel: _resolve(blocks.contact_empty_label, 'لا توجد بلاغات حتى الآن', 'No tickets yet'),
      teamLabel: _resolve(blocks.contact_team_label, 'فريق الدعم', 'Support team'),
      teamPlaceholder: _resolve(blocks.contact_team_placeholder, 'اختر فريق الدعم', 'Choose a support team'),
      descriptionLabel: _resolve(blocks.contact_description_label, 'التفاصيل', 'Details'),
      attachmentsLabel: _resolve(blocks.contact_attachments_label, 'مرفقات (اختياري)', 'Attachments (optional)'),
      cancelLabel: _resolve(blocks.contact_cancel_label, 'إلغاء', 'Cancel'),
      submitLabel: _resolve(blocks.contact_submit_label, 'إرسال البلاغ', 'Submit ticket'),
      replyPlaceholder: _resolve(blocks.contact_reply_placeholder, 'اكتب تعليقك...', 'Write your comment...'),
      replySubmitLabel: _resolve(blocks.contact_reply_submit_label, 'إرسال التعليق', 'Send comment'),
      gatePoint1: copy.gatePoint1,
      gatePoint2: copy.gatePoint2,
      gatePoint3: copy.gatePoint3,
      heroEyebrow: copy.heroEyebrow,
      heroSubtitle: copy.heroSubtitle,
      heroTag1: copy.heroTag1,
      heroTag2: copy.heroTag2,
      heroTag3: copy.heroTag3,
      highlightLabel1: copy.highlightLabel1,
      highlightBody1: copy.highlightBody1,
      highlightLabel2: copy.highlightLabel2,
      highlightBody2: copy.highlightBody2,
      totalTicketsLabel: copy.totalTicketsLabel,
      openTicketsLabel: copy.openTicketsLabel,
      closedTicketsLabel: copy.closedTicketsLabel,
      journeyEyebrow: copy.journeyEyebrow,
      step1Title: copy.step1Title,
      step1Body: copy.step1Body,
      step2Title: copy.step2Title,
      step2Body: copy.step2Body,
      step3Title: copy.step3Title,
      step3Body: copy.step3Body,
      toolbarTitle: copy.toolbarTitle,
      toolbarSubtitle: copy.toolbarSubtitle,
      listKicker: copy.listKicker,
      listSubtitle: copy.listSubtitle,
      listNote: copy.listNote,
      createKicker: copy.createKicker,
      createSubtitle: copy.createSubtitle,
      createNote: copy.createNote,
      descriptionPlaceholder: copy.descriptionPlaceholder,
      attachmentsHint: copy.attachmentsHint,
      detailKicker: copy.detailKicker,
      detailHelper: copy.detailHelper,
      detailNote: copy.detailNote,
      detailEmptyLabel: copy.detailEmptyLabel,
    };
    _applyContent();
  }

  function _applyContent() {
    _applyStaticCopy();
    _setText('contact-gate-title', _content.gateTitle);
    _setText('contact-gate-description', _content.gateDescription);
    _setText('contact-gate-login', _content.gateLogin);
    _setText('contact-gate-point-1', _content.gatePoint1);
    _setText('contact-gate-point-2', _content.gatePoint2);
    _setText('contact-gate-point-3', _content.gatePoint3);
    _setText('contact-hero-eyebrow', _content.heroEyebrow);
    _setText('contact-page-title', _content.pageTitle);
    _setText('contact-hero-subtitle', _content.heroSubtitle);
    _setText('contact-hero-tag-1', _content.heroTag1);
    _setText('contact-hero-tag-2', _content.heroTag2);
    _setText('contact-hero-tag-3', _content.heroTag3);
    _setText('contact-highlight-label-1', _content.highlightLabel1);
    _setText('contact-highlight-body-1', _content.highlightBody1);
    _setText('contact-highlight-label-2', _content.highlightLabel2);
    _setText('contact-highlight-body-2', _content.highlightBody2);
    _setText('support-total-label', _content.totalTicketsLabel);
    _setText('support-open-label', _content.openTicketsLabel);
    _setText('support-closed-label', _content.closedTicketsLabel);
    _setText('contact-brief-eyebrow', _content.journeyEyebrow);
    _setText('contact-brief-title-1', _content.step1Title);
    _setText('contact-brief-body-1', _content.step1Body);
    _setText('contact-brief-title-2', _content.step2Title);
    _setText('contact-brief-body-2', _content.step2Body);
    _setText('contact-brief-title-3', _content.step3Title);
    _setText('contact-brief-body-3', _content.step3Body);
    _setText('contact-toolbar-title', _content.toolbarTitle);
    _setText('contact-toolbar-subtitle', _content.toolbarSubtitle);
    _setText('contact-refresh-label', _content.refreshLabel);
    _setText('contact-new-ticket-label', _content.newTicketLabel);
    _setText('contact-list-kicker', _content.listKicker);
    _setText('contact-list-title', _content.listTitle);
    _setText('contact-list-subtitle', _content.listSubtitle);
    _setText('contact-list-note', _content.listNote);
    _setText('contact-create-kicker', _content.createKicker);
    _setText('contact-create-title', _content.createTitle);
    _setText('contact-create-subtitle', _content.createSubtitle);
    _setText('contact-create-note', _content.createNote);
    _setText('contact-detail-title', _content.detailTitle);
    _setText('contact-detail-kicker', _content.detailKicker);
    _setText('contact-detail-helper', _content.detailHelper);
    _setText('contact-detail-note', _content.detailNote);
    _setText('contact-detail-empty-label', _content.detailEmptyLabel);
    _setText('contact-empty-label', _content.emptyLabel);
    _setText('contact-team-label', _content.teamLabel);
    _setText('contact-description-label', _content.descriptionLabel);
    _setText('contact-attachments-label', _content.attachmentsLabel);
    _setText('contact-attachments-hint', _content.attachmentsHint);
    _setText('btn-cancel-ticket', _content.cancelLabel);
    _setText('submit-ticket-text', _content.submitLabel);
    _setPlaceholder('support-description', _content.descriptionPlaceholder);
    _setPlaceholder('ticket-reply-input', _content.replyPlaceholder);
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
      _loadCases(),
    ]);

    _records = _mergeRecords();
    _setListLoading(false);
    _renderSummary();
    _renderTickets();
    if (!_records.length) {
      _selectedRecord = null;
      _preferredSelection = null;
      _syncSelectionQueryParam(null);
      _renderTicketDetail();
      return;
    }

    const currentSelected = _currentSelectedSummary();
    const preferredSelection = _preferredSelection || currentSelected || _recordSelection(_records[0]);
    if (preferredSelection) {
      const selected = await _selectRecord(preferredSelection, { silent: true });
      if (selected) return;
    }

    if (_records[0]) {
      await _selectRecord(_recordSelection(_records[0]), { silent: true });
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
        const label = team.name || team.name_en || team.name_ar || team.code || '';
        if (!label) return;
        const option = UI.el('option', {
          value: team.code || label,
          textContent: label,
        });
        select.appendChild(option);
      });
      return;
    }

    Object.entries(_copy().ticketTypes).forEach(([code, label]) => {
      const option = UI.el('option', { value: code, textContent: label });
      select.appendChild(option);
    });
  }

  async function _loadTickets() {
    const res = await ApiClient.get('/api/support/tickets/my/');
    if (!res.ok) {
      _tickets = [];
      _setListError((res.data && res.data.detail) || _copy().listLoadFailed);
      return;
    }

    if (Array.isArray(res.data)) {
      _tickets = res.data;
      return;
    }

    _tickets = Array.isArray(res.data && res.data.results) ? res.data.results : [];
  }

  async function _loadCases() {
    const res = await ApiClient.get('/api/moderation/cases/my/');
    if (!res.ok) {
      _cases = [];
      return;
    }

    if (Array.isArray(res.data)) {
      _cases = res.data;
      return;
    }

    _cases = Array.isArray(res.data && res.data.results) ? res.data.results : [];
  }

  function _mergeRecords() {
    const ticketRows = _tickets.map((ticket) => ({ ...ticket, _recordKind: 'ticket' }));
    const caseRows = _cases.map((item) => ({ ...item, _recordKind: 'case' }));
    return ticketRows.concat(caseRows).sort((left, right) => {
      const leftTime = _timestamp(left && left.created_at);
      const rightTime = _timestamp(right && right.created_at);
      if (rightTime !== leftTime) return rightTime - leftTime;
      return _toPositiveInt(right && right.id) < _toPositiveInt(left && left.id) ? -1 : 1;
    });
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

    if (!_records.length) {
      empty.classList.remove('hidden');
      list.classList.add('hidden');
      return;
    }

    empty.classList.add('hidden');
    list.classList.remove('hidden');
    const frag = document.createDocumentFragment();
    _records.forEach((record) => {
      frag.appendChild(_buildTicketItem(record));
    });
    list.appendChild(frag);
  }

  function _renderSummary() {
    const totalEl = document.getElementById('support-total-count');
    const openEl = document.getElementById('support-open-count');
    const closedEl = document.getElementById('support-closed-count');
    const total = _records.length;
    let closed = 0;

    _records.forEach((record) => {
      if (_isClosedRecord(record)) {
        closed += 1;
      }
    });

    const open = Math.max(0, total - closed);
    if (totalEl) totalEl.textContent = String(total);
    if (openEl) openEl.textContent = String(open);
    if (closedEl) closedEl.textContent = String(closed);
  }

  function _ticketTypeLabel(value) {
    return _copy().ticketTypes[value] || value || _copy().typeFallback;
  }

  function _ticketCodeLabel(ticket) {
    return ticket.code || ('HD' + ticket.id);
  }

  function _buildTicketItem(ticket) {
    const button = UI.el('button', {
      className: 'support-ticket-item' + (_isSelectedRecord(ticket) ? ' active' : ''),
      type: 'button',
    });
    const isSelected = _isSelectedRecord(ticket);
    button.setAttribute('aria-pressed', isSelected ? 'true' : 'false');
    button.setAttribute('aria-label', _recordCodeLabel(ticket) + ' - ' + _recordTitle(ticket));
    button.addEventListener('click', () => _selectRecord(_recordSelection(ticket)));

    const top = UI.el('div', { className: 'support-ticket-top' });
    top.appendChild(UI.el('span', { className: 'support-ticket-code', textContent: _recordCodeLabel(ticket) }));
    const statusBadge = UI.el('span', {
      className: 'support-ticket-status',
      textContent: _statusLabel(ticket.status),
      style: { backgroundColor: _statusColor(ticket.status) + '1A', color: _statusColor(ticket.status) },
    });
    statusBadge.dataset.status = String(ticket.status || '').toLowerCase();
    top.appendChild(statusBadge);

    const typeLabel = _recordMetaLabel(ticket);
    const desc = _recordDescription(ticket);
    const text = desc.length > 80 ? desc.slice(0, 80) + '...' : desc;
    const meta = UI.el('div', { className: 'support-ticket-meta' });
    meta.appendChild(UI.el('span', { className: 'support-ticket-type', textContent: typeLabel }));
    meta.appendChild(UI.el('span', { className: 'support-ticket-time', textContent: _formatDate(ticket.created_at) }));

    const footer = UI.el('div', { className: 'support-ticket-footer' });
    footer.appendChild(UI.el('span', { className: 'support-ticket-footer-label', textContent: _copy().viewDetails }));
    footer.appendChild(UI.el('span', { className: 'support-ticket-footer-arrow', textContent: '‹' }));

    button.appendChild(top);
    button.appendChild(meta);
    button.appendChild(UI.el('div', { className: 'support-ticket-desc', textContent: text || _copy().noDescription }));
    button.appendChild(footer);
    return button;
  }

  function _statusLabel(status) {
    const map = {
      new: _copy().statusNew,
      in_progress: _copy().statusInProgress,
      returned: _copy().statusReturned,
      closed: _copy().statusClosed,
      under_review: _copy().statusUnderReview,
      action_taken: _copy().statusActionTaken,
      dismissed: _copy().statusDismissed,
      escalated: _copy().statusEscalated,
    };
    return map[String(status || '').toLowerCase()] || String(status || '');
  }

  function _statusColor(status) {
    const s = String(status || '').toLowerCase();
    if (s === 'new') return '#2563EB';
    if (s === 'in_progress') return '#7C3AED';
    if (s === 'returned') return '#F59E0B';
    if (s === 'closed') return '#6B7280';
    if (s === 'under_review') return '#7C3AED';
    if (s === 'action_taken') return '#059669';
    if (s === 'dismissed') return '#6B7280';
    if (s === 'escalated') return '#DC2626';
    return '#6B7280';
  }

  function _formatDate(value) {
    if (!value) return '';
    const dt = new Date(value);
    if (Number.isNaN(dt.getTime())) return '';
    return dt.toLocaleString(_currentLang() === 'en' ? 'en-US' : 'ar-SA', {
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
      if (!opts.silent) _notify(_copy().loadDetailsFailed, 'error');
      return false;
    }
    _selectedRecord = { ...detailRes.data, _recordKind: 'ticket' };
    _preferredSelection = _recordSelection(_selectedRecord);
    _syncSelectionQueryParam(_preferredSelection);
    _closeNewTicketForm();
    _renderTickets();
    _renderTicketDetail();
    return true;
  }

  async function _selectCase(caseId, options) {
    const opts = options || {};
    const detailRes = await ApiClient.get('/api/moderation/cases/' + caseId + '/');
    if (!detailRes.ok || !detailRes.data) {
      if (!opts.silent) _notify((detailRes.data && detailRes.data.detail) || _copy().loadDetailsFailed, 'error');
      return false;
    }
    _selectedRecord = { ...detailRes.data, _recordKind: 'case' };
    _preferredSelection = _recordSelection(_selectedRecord);
    _syncSelectionQueryParam(_preferredSelection);
    _closeNewTicketForm();
    _renderTickets();
    _renderTicketDetail();
    return true;
  }

  async function _selectRecord(selection, options) {
    const normalized = _normalizeSelection(selection);
    if (!normalized) return false;
    if (normalized.kind === 'case') {
      return _selectCase(normalized.id, options);
    }
    return _selectTicket(normalized.id, options);
  }

  function _renderTicketDetail() {
    const empty = document.getElementById('ticket-detail-empty');
    const body = document.getElementById('ticket-detail-body');
    if (!empty || !body) return;

    if (!_selectedRecord) {
      empty.classList.remove('hidden');
      body.classList.add('hidden');
      body.innerHTML = '';
      _updateOriginalLanguageNotice();
      return;
    }

    empty.classList.add('hidden');
    body.classList.remove('hidden');
    body.innerHTML = '';

    const ticket = _selectedRecord;
    if (_isCaseRecord(ticket)) {
      _renderCaseDetail(body, ticket);
      _updateOriginalLanguageNotice();
      return;
    }

    const attachments = Array.isArray(ticket.attachments) ? ticket.attachments : [];
    const comments = Array.isArray(ticket.comments) ? ticket.comments : [];
    const hero = UI.el('section', { className: 'ticket-detail-hero' });
    const head = UI.el('div', { className: 'ticket-detail-head' });
    const titleWrap = UI.el('div', { className: 'ticket-detail-title-wrap' });
    titleWrap.appendChild(UI.el('span', { className: 'ticket-detail-code', textContent: _ticketCodeLabel(ticket) }));
    titleWrap.appendChild(UI.el('h3', { textContent: _ticketTypeLabel(ticket.ticket_type) }));
    head.appendChild(titleWrap);
    head.appendChild(
      (() => {
        const statusBadge = UI.el('span', {
        className: 'support-ticket-status',
        textContent: _statusLabel(ticket.status),
        style: { backgroundColor: _statusColor(ticket.status) + '1A', color: _statusColor(ticket.status) },
        });
        statusBadge.dataset.status = String(ticket.status || '').toLowerCase();
        return statusBadge;
      })(),
    );
    hero.appendChild(head);

    const metaGrid = UI.el('div', { className: 'ticket-detail-meta-grid' });
    metaGrid.appendChild(_buildDetailMetaCard(_copy().createdAtLabel, _formatDate(ticket.created_at) || '—'));
    metaGrid.appendChild(_buildDetailMetaCard(_copy().attachmentsCountLabel, String(attachments.length)));
    metaGrid.appendChild(_buildDetailMetaCard(_copy().commentsCountLabel, String(comments.length)));
    metaGrid.appendChild(_buildDetailMetaCard(_copy().statusLabel, _statusLabel(ticket.status)));
    hero.appendChild(metaGrid);
    body.appendChild(hero);

    const descriptionSection = UI.el('div', { className: 'ticket-detail-section' });
    descriptionSection.appendChild(_buildSectionHead(_copy().descriptionSectionTitle));
    const descriptionText = ticket.description || _copy().noTicketDescription;
    const descriptionEl = UI.el('div', {
      className: 'ticket-detail-description',
      textContent: descriptionText,
    });
    _setAutoDirection(descriptionEl, ticket.description);
    descriptionSection.appendChild(descriptionEl);
    body.appendChild(descriptionSection);

    const attachmentsSection = UI.el('div', { className: 'ticket-detail-section' });
    attachmentsSection.appendChild(_buildSectionHead(_content.attachmentsLabel || 'المرفقات', attachments.length));
    if (!attachments.length) {
      attachmentsSection.appendChild(UI.el('p', { className: 'ticket-muted', textContent: _copy().noTicketAttachments }));
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
            textContent: String(att.file || '').split('/').pop() || _copy().attachmentFallback,
          }),
        );
        attachmentsList.appendChild(link);
      });
      attachmentsSection.appendChild(attachmentsList);
    }
    body.appendChild(attachmentsSection);

    const commentsSection = UI.el('div', { className: 'ticket-detail-section' });
    commentsSection.appendChild(_buildSectionHead(_copy().commentsSectionTitle, comments.length));
    if (!comments.length) {
      commentsSection.appendChild(UI.el('p', { className: 'ticket-muted', textContent: _copy().noComments }));
    } else {
      const commentsList = UI.el('div', { className: 'ticket-comments-list' });
      comments.forEach((comment) => {
        const row = UI.el('div', { className: 'ticket-comment' });
        const metaText = (comment.created_by_name || _copy().userFallback) + ' • ' + _formatDate(comment.created_at);
        const metaEl = UI.el('div', {
          className: 'ticket-comment-meta',
          textContent: metaText,
        });
        _setAutoDirection(metaEl, comment.created_by_name);
        row.appendChild(metaEl);
        const commentTextEl = UI.el('div', { className: 'ticket-comment-text', textContent: comment.text || '' });
        _setAutoDirection(commentTextEl, comment.text);
        row.appendChild(commentTextEl);
        commentsList.appendChild(row);
      });
      commentsSection.appendChild(commentsList);
    }
    body.appendChild(commentsSection);

    const reply = UI.el('div', { className: 'ticket-reply-box' });
    const replyHead = UI.el('div', { className: 'ticket-reply-head' });
    replyHead.appendChild(UI.el('h4', { textContent: _copy().replyTitle }));
    replyHead.appendChild(UI.el('p', { textContent: _copy().replyHint }));
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

    _updateOriginalLanguageNotice();
  }

  function _renderCaseDetail(body, item) {
    const actionLogs = Array.isArray(item.action_logs) ? item.action_logs : [];
    const decisions = Array.isArray(item.decisions) ? item.decisions : [];

    const hero = UI.el('section', { className: 'ticket-detail-hero' });
    const head = UI.el('div', { className: 'ticket-detail-head' });
    const titleWrap = UI.el('div', { className: 'ticket-detail-title-wrap' });
    titleWrap.appendChild(UI.el('span', { className: 'ticket-detail-code', textContent: _recordCodeLabel(item) }));
    titleWrap.appendChild(UI.el('h3', { textContent: _recordTitle(item) }));
    head.appendChild(titleWrap);
    head.appendChild(
      (() => {
        const statusBadge = UI.el('span', {
          className: 'support-ticket-status',
          textContent: _statusLabel(item.status),
          style: { backgroundColor: _statusColor(item.status) + '1A', color: _statusColor(item.status) },
        });
        statusBadge.dataset.status = String(item.status || '').toLowerCase();
        return statusBadge;
      })(),
    );
    hero.appendChild(head);

    const metaGrid = UI.el('div', { className: 'ticket-detail-meta-grid' });
    metaGrid.appendChild(_buildDetailMetaCard(_copy().createdAtLabel, _formatDate(item.created_at) || '—'));
    metaGrid.appendChild(_buildDetailMetaCard(_copy().actionsCountLabel, String(actionLogs.length)));
    metaGrid.appendChild(_buildDetailMetaCard(_copy().decisionsCountLabel, String(decisions.length)));
    metaGrid.appendChild(_buildDetailMetaCard(_copy().statusLabel, _statusLabel(item.status)));
    hero.appendChild(metaGrid);
    body.appendChild(hero);

    const descriptionSection = UI.el('div', { className: 'ticket-detail-section' });
    descriptionSection.appendChild(_buildSectionHead(_copy().descriptionSectionTitle));
    const descriptionText = (item.details || item.summary || item.reason || '').trim() || _copy().noTicketDescription;
    const descriptionEl = UI.el('div', {
      className: 'ticket-detail-description',
      textContent: descriptionText,
    });
    _setAutoDirection(descriptionEl, descriptionText);
    descriptionSection.appendChild(descriptionEl);
    body.appendChild(descriptionSection);

    const infoSection = UI.el('div', { className: 'ticket-detail-section' });
    infoSection.appendChild(_buildSectionHead(_copy().reasonLabel));
    const infoList = UI.el('div', { className: 'ticket-comments-list' });
    infoList.appendChild(_buildInfoRow(_copy().reasonLabel, item.reason || '—'));
    infoList.appendChild(_buildInfoRow(_copy().sourceLabel, item.source_label || item.source_model || '—'));
    if (item.linked_support_ticket_code) {
      infoList.appendChild(_buildInfoRow(_copy().linkedTicketLabel, item.linked_support_ticket_code));
    }
    infoSection.appendChild(infoList);
    body.appendChild(infoSection);

    const activitySection = UI.el('div', { className: 'ticket-detail-section' });
    const activities = _buildCaseActivities(item);
    activitySection.appendChild(_buildSectionHead(_copy().activitySectionTitle, activities.length));
    if (!activities.length) {
      activitySection.appendChild(UI.el('p', { className: 'ticket-muted', textContent: _copy().noActivity }));
    } else {
      const activityList = UI.el('div', { className: 'ticket-comments-list' });
      activities.forEach((activity) => {
        const row = UI.el('div', { className: 'ticket-comment' });
        const metaEl = UI.el('div', {
          className: 'ticket-comment-meta',
          textContent: activity.meta,
        });
        _setAutoDirection(metaEl, activity.meta);
        row.appendChild(metaEl);
        const textEl = UI.el('div', { className: 'ticket-comment-text', textContent: activity.text });
        _setAutoDirection(textEl, activity.text);
        row.appendChild(textEl);
        activityList.appendChild(row);
      });
      activitySection.appendChild(activityList);
    }
    body.appendChild(activitySection);
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
    _syncSelectionQueryParam(null);
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
    _syncSelectionQueryParam(_preferredSelection || (_selectedRecord ? _recordSelection(_selectedRecord) : null));
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
        _setCreateError(_copy().createValidation);
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
      _setCreateError(_extractApiErrorMessage(createRes.data, _copy().createFailed));
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
    await _loadInitial();
    _renderSummary();
    _renderTickets();
    if (ticketId) {
      await _selectTicket(ticketId);
    }
    _notify(_copy().createSuccess, 'success');
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
      _notify((res.data && res.data.detail) || _copy().commentFailed, 'error');
      return;
    }

    input.value = '';
    await _selectTicket(ticketId);
    _notify(_copy().commentSuccess, 'success');
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

  function _selectionFromUrl() {
    try {
      const params = new URLSearchParams(window.location.search || '');
      const caseRaw = String(params.get('case') || '').trim();
      const caseId = _toPositiveInt(caseRaw);
      if (caseId) {
        return { kind: 'case', id: caseId };
      }
      const raw = String(params.get('ticket') || '').trim();
      const ticketId = _toPositiveInt(raw);
      if (ticketId) {
        return { kind: 'ticket', id: ticketId };
      }
    } catch (_) {}
    return null;
  }

  function _syncSelectionQueryParam(selection) {
    if (!window.history || typeof window.history.replaceState !== 'function') return;
    try {
      const url = new URL(window.location.href);
      url.searchParams.delete('ticket');
      url.searchParams.delete('case');
      const normalized = _normalizeSelection(selection);
      if (normalized) {
        url.searchParams.set(normalized.kind, String(normalized.id));
      }
      const nextUrl = url.pathname + url.search + url.hash;
      window.history.replaceState({}, '', nextUrl);
    } catch (_) {}
  }

  function _recordSelection(record) {
    if (!record) return null;
    const kind = _isCaseRecord(record) ? 'case' : 'ticket';
    const id = _toPositiveInt(record.id);
    if (!id) return null;
    return { kind, id };
  }

  function _normalizeSelection(selection) {
    if (!selection || typeof selection !== 'object') return null;
    const kind = selection.kind === 'case' ? 'case' : selection.kind === 'ticket' ? 'ticket' : '';
    const id = _toPositiveInt(selection.id);
    if (!kind || !id) return null;
    return { kind, id };
  }

  function _currentSelectedSummary() {
    if (!_selectedRecord) return null;
    const selection = _recordSelection(_selectedRecord);
    if (!selection) return null;
    const found = _records.some((record) => {
      const current = _recordSelection(record);
      return current && current.kind === selection.kind && current.id === selection.id;
    });
    return found ? selection : null;
  }

  function _isTicketRecord(record) {
    return !!record && record._recordKind !== 'case';
  }

  function _isCaseRecord(record) {
    return !!record && record._recordKind === 'case';
  }

  function _isSelectedRecord(record) {
    const recordSelection = _recordSelection(record);
    const selectedSelection = _recordSelection(_selectedRecord);
    return !!recordSelection && !!selectedSelection && recordSelection.kind === selectedSelection.kind && recordSelection.id === selectedSelection.id;
  }

  function _recordCodeLabel(record) {
    return record && record.code ? record.code : (_isCaseRecord(record) ? 'MC' + record.id : _ticketCodeLabel(record));
  }

  function _recordTitle(record) {
    if (_isCaseRecord(record)) {
      return _caseCategoryLabel(record) || record.source_label || _copy().caseFallback;
    }
    return _ticketTypeLabel(record && record.ticket_type);
  }

  function _recordMetaLabel(record) {
    if (_isCaseRecord(record)) {
      return record.source_label || record.source_model || _copy().caseFallback;
    }
    return _ticketTypeLabel(record && record.ticket_type);
  }

  function _recordDescription(record) {
    if (_isCaseRecord(record)) {
      return String(record.summary || record.reason || record.details || '').trim();
    }
    return String(record && record.description || '').trim();
  }

  function _caseCategoryLabel(record) {
    const category = String(record && record.category || '').trim().toLowerCase();
    if (category === 'service') return _copy().categoryService;
    if (category === 'spotlight') return _copy().categorySpotlight;
    if (category === 'portfolio') return _copy().categoryPortfolio;
    if (category === 'complaint') return _copy().categoryComplaint;
    return record && record.source_label ? String(record.source_label).trim() : _copy().caseFallback;
  }

  function _isClosedRecord(record) {
    const status = String(record && record.status || '').toLowerCase();
    if (_isCaseRecord(record)) {
      return status === 'action_taken' || status === 'dismissed' || status === 'escalated';
    }
    return status === 'closed';
  }

  function _buildInfoRow(label, value) {
    const row = UI.el('div', { className: 'ticket-comment' });
    row.appendChild(UI.el('div', { className: 'ticket-comment-meta', textContent: label }));
    const textEl = UI.el('div', { className: 'ticket-comment-text', textContent: value || '—' }));
    _setAutoDirection(textEl, value);
    row.appendChild(textEl);
    return row;
  }

  function _buildCaseActivities(item) {
    const rows = [];
    const actionLogs = Array.isArray(item && item.action_logs) ? item.action_logs : [];
    const decisions = Array.isArray(item && item.decisions) ? item.decisions : [];

    actionLogs.forEach((log) => {
      const actionType = String(log && log.action_type || '').trim();
      const actor = String(log && log.created_by_phone || '').trim() || _copy().userFallback;
      const when = _formatDate(log && log.created_at) || '—';
      const text = String(log && log.note || '').trim() || _statusLabel(log && log.to_status) || actionType || _copy().noActivity;
      rows.push({
        meta: actor + ' • ' + when,
        text,
        timestamp: _timestamp(log && log.created_at),
      });
    });

    decisions.forEach((decision) => {
      const actor = String(decision && decision.applied_by_phone || '').trim() || _copy().userFallback;
      const when = _formatDate(decision && (decision.applied_at || decision.created_at)) || '—';
      const label = _decisionLabel(decision && decision.decision_code);
      const note = String(decision && decision.note || '').trim();
      rows.push({
        meta: actor + ' • ' + when,
        text: note ? label + ' - ' + note : label,
        timestamp: _timestamp(decision && (decision.applied_at || decision.created_at)),
      });
    });

    return rows.sort((left, right) => right.timestamp - left.timestamp);
  }

  function _decisionLabel(value) {
    const normalized = String(value || '').trim().toLowerCase();
    const map = {
      hide: _currentLang() === 'en' ? 'Hide content' : 'إخفاء المحتوى',
      delete: _currentLang() === 'en' ? 'Delete content' : 'حذف المحتوى',
      warn: _currentLang() === 'en' ? 'Warn account' : 'تنبيه الحساب',
      no_action: _currentLang() === 'en' ? 'No action' : 'بدون إجراء',
      escalate: _currentLang() === 'en' ? 'Escalate' : 'تصعيد',
      close: _currentLang() === 'en' ? 'Close' : 'إغلاق',
    };
    return map[normalized] || normalized || _copy().caseFallback;
  }

  function _timestamp(value) {
    const dt = value ? new Date(value) : null;
    if (!dt || Number.isNaN(dt.getTime())) return 0;
    return dt.getTime();
  }

  function _toPositiveInt(value) {
    const parsed = Number(value);
    if (!Number.isFinite(parsed) || parsed <= 0) return 0;
    return Math.floor(parsed);
  }

  function _resolve(block, fallbackAr, fallbackEn) {
    const arValue = String(block && block.title_ar || '').trim();
    const enValue = String(block && block.title_en || '').trim();
    if (_currentLang() === 'en') {
      if (enValue) return enValue;
      if (arValue && arValue !== String(fallbackAr || '').trim()) return arValue;
      return String(fallbackEn || '').trim() || arValue || String(fallbackAr || '').trim();
    }
    return arValue || String(fallbackAr || '').trim();
  }

  function _setText(id, value) {
    const el = document.getElementById(id);
    if (el && value) el.textContent = value;
  }

  function _setAutoDirection(el, value) {
    if (!el) return;
    if (String(value || '').trim()) el.setAttribute('dir', 'auto');
    else el.removeAttribute('dir');
  }

  function _setPlaceholder(id, value) {
    const el = document.getElementById(id);
    if (el && value) el.setAttribute('placeholder', value);
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

  function _copy() {
    return COPY[_currentLang()] || COPY.ar;
  }

  function _applyStaticCopy() {
    const copy = _copy();
    if (window.NawafethI18n && typeof window.NawafethI18n.t === 'function') {
      document.title = window.NawafethI18n.t('siteTitle') + ' — ' + copy.pageTitle;
    }
    _setText('ticket-original-language-note', copy.originalLanguageNotice);
  }

  function _containsArabicScript(value) {
    return /[\u0600-\u06FF]/.test(String(value || '').trim());
  }

  function _hasOriginalLanguageContent() {
    if (!_selectedRecord || _currentLang() !== 'en') return false;
    if (_containsArabicScript(_selectedRecord.description) || _containsArabicScript(_selectedRecord.details) || _containsArabicScript(_selectedRecord.summary) || _containsArabicScript(_selectedRecord.reason)) {
      return true;
    }
    if (Array.isArray(_selectedRecord.comments) && _selectedRecord.comments.some((comment) => {
      return _containsArabicScript(comment && comment.text) || _containsArabicScript(comment && comment.created_by_name);
    })) {
      return true;
    }
    return Array.isArray(_selectedRecord.action_logs) && _selectedRecord.action_logs.some((entry) => {
      return _containsArabicScript(entry && entry.note) || _containsArabicScript(entry && entry.created_by_phone);
    });
  }

  function _updateOriginalLanguageNotice() {
    const note = document.getElementById('ticket-original-language-note');
    if (!note) return;
    note.textContent = _copy().originalLanguageNotice;
    note.classList.toggle('hidden', !_hasOriginalLanguageContent());
  }

  function _handleLanguageChange() {
    _refreshContent();
    _renderSummary();
    _renderTickets();
    _renderTicketDetail();
    _renderTeams();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  return {};
})();
