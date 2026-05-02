/* ===================================================================
   orderDetailPage.js — Client order details
   GET/PATCH /api/marketplace/client/requests/<id>/
   =================================================================== */
'use strict';

const OrderDetailPage = (() => {
  const COPY = {
    ar: {
      pageTitle: 'نوافــذ — تفاصيل الطلب',
      invalidRequest: 'تعذر تحديد رقم الطلب',
      gateTitle: 'سجّل دخولك',
      gateDescription: 'يجب تسجيل الدخول لعرض تفاصيل الطلب',
      gateButton: 'تسجيل الدخول',
      kicker: 'متابعة الطلب',
      title: 'تفاصيل الطلب',
      subtitle: 'ملخص الحالة أولًا، ثم التفاصيل والإجراءات.',
      backAria: 'العودة إلى قائمة الطلبات',
      backText: 'رجوع للطلبات',
      orderIdLabel: 'رقم الطلب',
      orderTitleHeading: 'عنوان الطلب',
      orderDescriptionHeading: 'تفاصيل الطلب',
      attachmentsTitle: 'المرفقات',
      clientAttachmentsTitle: 'مرفقات العميل',
      clientAttachmentsDesc: 'الملفات المرفوعة مع الطلب.',
      providerAttachmentsTitle: 'مرفقات مزود الخدمة',
      providerAttachmentsDesc: 'الملفات المرفوعة عند إكمال الخدمة.',
      financeTitle: 'تفاصيل التنفيذ',
      completionTitle: 'بيانات الإكمال',
      providerDecisionTitle: 'قرارك على تفاصيل التنفيذ',
      providerRejectLabel: 'سبب الرفض عند الحاجة',
      providerRejectPlaceholder: 'اكتب سبب رفض التفاصيل ليصل إلى مقدم الخدمة',
      rejectDetails: 'رفض التفاصيل',
      approveAndStart: 'اعتماد وبدء التنفيذ',
      cancelledTitle: 'بيانات الإلغاء',
      reviewTitle: 'تقييم الخدمة',
      reviewResponseSpeed: 'سرعة الاستجابة',
      reviewCostValue: 'القيمة مقابل السعر',
      reviewQuality: 'جودة العمل',
      reviewCredibility: 'المصداقية',
      reviewOnTime: 'الالتزام بالموعد',
      reviewPick: 'اختر',
      reviewCommentLabel: 'تعليقك',
      reviewCommentPlaceholder: 'اكتب تعليقًا مختصرًا عن التجربة',
      reviewSubmit: 'إرسال التقييم',
      reviewSubmitting: 'جاري إرسال التقييم...',
      statusLogsTitle: 'سجل الحالة',
      offersTitle: 'عروض الأسعار',
      refresh: 'تحديث',
      actionsTitle: 'إجراءات الطلب',
      back: 'رجوع',
      save: 'حفظ',
      stopEdit: 'إيقاف',
      edit: 'تعديل',
      loadDetailsFailed: 'تعذر تحميل تفاصيل الطلب',
      loadOffersFailed: 'تعذر تحميل عروض الأسعار',
      providerAccepted: 'تم قبول الطلب',
      awaitingClient: 'بانتظار اعتماد العميل للتفاصيل',
      providerDecisionRejectedPrefix: 'تم رفض التفاصيل سابقًا: ',
      cancelDate: 'تاريخ الإلغاء',
      cancelReason: 'سبب الإلغاء',
      reviewSentPrefix: 'تم إرسال تقييمك',
      overallRatingPrefix: 'التقييم العام',
      cancelReasonLabel: 'سبب الإلغاء',
      cancelReasonPlaceholder: 'اكتب سبب إلغاء الطلب',
      cancelOrder: 'إلغاء الطلب',
      reopenNote: 'يمكنك إعادة فتح الطلب ليعود إلى حالة جديد بدون مقدم خدمة معيّن.',
      reopenOrder: 'إعادة فتح الطلب',
      noAttachments: 'لا يوجد مرفقات',
      attachmentFile: 'ملف',
      openAttachment: 'فتح المرفق',
      attachmentUnavailable: 'رابط المرفق غير متاح',
      noStatusLog: 'لا يوجد سجل حالة',
      statusNew: 'جديد',
      statusSubmitted: 'مرسل',
      statusWaiting: 'بانتظار',
      statusAccepted: 'تم قبول الطلب',
      statusAwaitingClient: 'بانتظار اعتماد العميل للتفاصيل',
      statusInProgress: 'تحت التنفيذ',
      statusCompleted: 'مكتمل',
      statusCancelled: 'ملغي',
      statusRejected: 'مرفوض',
      statusPendingDecision: 'بانتظار القرار',
      statusUnknown: 'غير محدد',
      loadingOffers: 'جاري تحميل عروض الأسعار...',
      noOffers: 'لا توجد عروض أسعار حتى الآن.',
      providerFallback: 'مقدم خدمة',
      providerProfileTitle: 'عرض ملف مقدم الخدمة',
      offerPrice: 'السعر',
      offerDuration: 'مدة التنفيذ',
      days: 'يوم',
      offerNote: 'ملاحظة',
      selectingOffer: 'جاري الاختيار...',
      selectOffer: 'اختيار هذا العرض',
      cannotSelectOffer: 'لا يمكن اختيار عرض في الحالة الحالية',
      invalidOfferId: 'تعذر اختيار العرض: معرف غير صالح',
      acceptOfferFailed: 'تعذّر اختيار العرض',
      acceptOfferSuccess: 'تم اختيار العرض وإسناد الطلب بنجاح',
      returnToOffers: 'العودة إلى عروض الأسعار',
      requestTypeUrgent: 'عاجل',
      requestTypeCompetitive: 'تنافسي',
      requestTypeNormal: 'عادي',
      currency: 'ر.س',
      saveRequired: 'العنوان والتفاصيل مطلوبان',
      saveFailed: 'فشل حفظ التعديلات',
      writeCancelReason: 'يرجى كتابة سبب الإلغاء',
      cancelFailed: 'تعذر إلغاء الطلب',
      cancelSuccess: 'تم إلغاء الطلب بنجاح',
      reopenFailed: 'تعذر إعادة فتح الطلب',
      reopenSuccess: 'تمت إعادة فتح الطلب',
      rejectReasonRequired: 'سبب الرفض مطلوب',
      actionFailed: 'فشل تنفيذ العملية',
      approveSuccess: 'تم اعتماد التفاصيل وبدأ التنفيذ',
      rejectSuccess: 'تم رفض التفاصيل وإشعار مقدم الخدمة',
      reviewFillAll: 'يرجى تعبئة جميع عناصر التقييم',
      reviewTooLong: 'تعليق التقييم يجب ألا يتجاوز 300 حرف',
      reviewSendInProgress: 'جاري إرسال التقييم...',
      reviewSendFailed: 'تعذر إرسال التقييم',
      reviewSendSuccess: 'تم إرسال التقييم بنجاح. تم تحديث حالة الطلب.',
      createdAt: 'تاريخ الإنشاء',
      requestType: 'نوع الطلب',
      category: 'التصنيف',
      provider: 'مقدم الخدمة',
      providerPhone: 'رقم مقدم الخدمة',
      city: 'المدينة',
      expectedDelivery: 'موعد التسليم المتوقع',
      estimatedAmount: 'قيمة الخدمة المقدرة',
      receivedAmount: 'المبلغ المستلم',
      remainingAmount: 'المبلغ المتبقي',
      deliveredAt: 'موعد التسليم الفعلي',
      actualAmount: 'قيمة الخدمة الفعلية',
      attachmentsLabel: 'المرفقات',
      originalLanguageNotice: 'بعض التفاصيل والأسماء والملاحظات تُعرض بلغتها الأصلية.',
    },
    en: {
      pageTitle: 'Nawafeth — Order Details',
      invalidRequest: 'Unable to determine the order number',
      gateTitle: 'Sign in',
      gateDescription: 'You need to sign in to view the order details',
      gateButton: 'Sign in',
      kicker: 'Track order',
      title: 'Order details',
      subtitle: 'Status summary first, then details and actions.',
      backAria: 'Back to orders list',
      backText: 'Back to orders',
      orderIdLabel: 'Order number',
      orderTitleHeading: 'Order title',
      orderDescriptionHeading: 'Order details',
      attachmentsTitle: 'Attachments',
      clientAttachmentsTitle: 'Client attachments',
      clientAttachmentsDesc: 'Files uploaded with the order.',
      providerAttachmentsTitle: 'Provider attachments',
      providerAttachmentsDesc: 'Files uploaded when the service was completed.',
      financeTitle: 'Execution details',
      completionTitle: 'Completion details',
      providerDecisionTitle: 'Your decision on execution details',
      providerRejectLabel: 'Reason for rejection if needed',
      providerRejectPlaceholder: 'Write why you are rejecting the details so the provider receives it',
      rejectDetails: 'Reject details',
      approveAndStart: 'Approve and start execution',
      cancelledTitle: 'Cancellation details',
      reviewTitle: 'Service review',
      reviewResponseSpeed: 'Response speed',
      reviewCostValue: 'Value for price',
      reviewQuality: 'Work quality',
      reviewCredibility: 'Credibility',
      reviewOnTime: 'On-time commitment',
      reviewPick: 'Choose',
      reviewCommentLabel: 'Your comment',
      reviewCommentPlaceholder: 'Write a short comment about the experience',
      reviewSubmit: 'Submit review',
      reviewSubmitting: 'Submitting review...',
      statusLogsTitle: 'Status log',
      offersTitle: 'Price offers',
      refresh: 'Refresh',
      actionsTitle: 'Order actions',
      back: 'Back',
      save: 'Save',
      stopEdit: 'Stop',
      edit: 'Edit',
      loadDetailsFailed: 'Unable to load order details',
      loadOffersFailed: 'Unable to load price offers',
      providerAccepted: 'Accepted by provider',
      awaitingClient: 'Awaiting client approval',
      providerDecisionRejectedPrefix: 'These details were rejected before: ',
      cancelDate: 'Cancellation date',
      cancelReason: 'Cancellation reason',
      reviewSentPrefix: 'Your review was submitted',
      overallRatingPrefix: 'Overall rating',
      cancelReasonLabel: 'Cancellation reason',
      cancelReasonPlaceholder: 'Write why you want to cancel the order',
      cancelOrder: 'Cancel order',
      reopenNote: 'You can reopen the order so it returns to New without an assigned provider.',
      reopenOrder: 'Reopen order',
      noAttachments: 'No attachments',
      attachmentFile: 'File',
      openAttachment: 'Open attachment',
      attachmentUnavailable: 'Attachment link is unavailable',
      noStatusLog: 'No status log available',
      statusNew: 'New',
      statusSubmitted: 'Submitted',
      statusWaiting: 'Waiting',
      statusAccepted: 'Accepted by provider',
      statusAwaitingClient: 'Awaiting client approval',
      statusInProgress: 'In progress',
      statusCompleted: 'Completed',
      statusCancelled: 'Cancelled',
      statusRejected: 'Rejected',
      statusPendingDecision: 'Awaiting decision',
      statusUnknown: 'Unspecified',
      loadingOffers: 'Loading price offers...',
      noOffers: 'No price offers yet.',
      providerFallback: 'Provider',
      providerProfileTitle: 'Open provider profile',
      offerPrice: 'Price',
      offerDuration: 'Execution time',
      days: 'days',
      offerNote: 'Note',
      selectingOffer: 'Selecting...',
      selectOffer: 'Choose this offer',
      cannotSelectOffer: 'You cannot choose an offer in the current state',
      invalidOfferId: 'Unable to choose the offer: invalid identifier',
      acceptOfferFailed: 'Unable to choose the offer',
      acceptOfferSuccess: 'The offer was selected and the order was assigned successfully',
      returnToOffers: 'Back to price offers',
      requestTypeUrgent: 'Urgent',
      requestTypeCompetitive: 'Competitive',
      requestTypeNormal: 'Standard',
      currency: 'SAR',
      saveRequired: 'Title and details are required',
      saveFailed: 'Failed to save changes',
      writeCancelReason: 'Please write the cancellation reason',
      cancelFailed: 'Unable to cancel the order',
      cancelSuccess: 'The order was cancelled successfully',
      reopenFailed: 'Unable to reopen the order',
      reopenSuccess: 'The order was reopened',
      rejectReasonRequired: 'A rejection reason is required',
      actionFailed: 'Failed to complete the action',
      approveSuccess: 'The details were approved and execution started',
      rejectSuccess: 'The details were rejected and the provider was notified',
      reviewFillAll: 'Please complete all review fields',
      reviewTooLong: 'The review comment must not exceed 300 characters',
      reviewSendInProgress: 'Submitting review...',
      reviewSendFailed: 'Unable to submit the review',
      reviewSendSuccess: 'The review was submitted successfully. The order status was updated.',
      createdAt: 'Created at',
      requestType: 'Request type',
      category: 'Category',
      provider: 'Provider',
      providerPhone: 'Provider phone',
      city: 'City',
      expectedDelivery: 'Expected delivery date',
      estimatedAmount: 'Estimated service amount',
      receivedAmount: 'Received amount',
      remainingAmount: 'Remaining amount',
      deliveredAt: 'Actual delivery date',
      actualAmount: 'Actual service amount',
      attachmentsLabel: 'Attachments',
      originalLanguageNotice: 'Some order details, names, and notes are shown in their original language.',
    },
  };

  let _requestId = null;
  let _order = null;
  let _offers = [];
  let _offersLoading = false;
  let _acceptingOfferId = null;
  let _editTitle = false;
  let _editDesc = false;
  let _actionLoading = false;

  function init() {
    _applyStaticCopy();
    _requestId = _parseRequestId();
    if (!_requestId) {
      _setError(_copy('invalidRequest'));
      return;
    }

    if (!Auth.isLoggedIn()) {
      _showGate();
      return;
    }

    _hideGate();
    _bindActions();
    document.addEventListener('nawafeth:languagechange', _handleLanguageChange);
    _loadDetail();
  }

  function _parseRequestId() {
    const m = window.location.pathname.match(/\/orders\/(\d+)\/?$/);
    if (!m) return null;
    return Number(m[1]);
  }

  function _showGate() {
    const gate = document.getElementById('auth-gate');
    const content = document.getElementById('order-content');
    const loginLink = document.getElementById('order-login-link');
    if (gate) gate.classList.remove('hidden');
    if (content) content.classList.add('hidden');
    if (loginLink) loginLink.href = '/login/?next=' + encodeURIComponent(window.location.pathname);
  }

  function _hideGate() {
    const gate = document.getElementById('auth-gate');
    const content = document.getElementById('order-content');
    if (gate) gate.classList.add('hidden');
    if (content) content.classList.remove('hidden');
  }

  function _bindActions() {
    const tBtn = document.getElementById('btn-toggle-title');
    const dBtn = document.getElementById('btn-toggle-desc');
    const sBtn = document.getElementById('btn-save-order');
    const refreshOffersBtn = document.getElementById('btn-refresh-offers');

    if (tBtn) {
      tBtn.addEventListener('click', () => {
        _editTitle = !_editTitle;
        _applyEditableState();
      });
    }

    if (dBtn) {
      dBtn.addEventListener('click', () => {
        _editDesc = !_editDesc;
        _applyEditableState();
      });
    }

    if (sBtn) sBtn.addEventListener('click', _save);

    if (refreshOffersBtn) {
      refreshOffersBtn.addEventListener('click', () => {
        if (!_offersLoading) _loadOffers();
      });
    }

    const approveBtn = document.getElementById('btn-approve-provider-inputs');
    const rejectBtn = document.getElementById('btn-reject-provider-inputs');
    const reviewForm = document.getElementById('order-review-form');

    if (approveBtn) approveBtn.addEventListener('click', () => _decideProviderInputs(true));
    if (rejectBtn) rejectBtn.addEventListener('click', () => _decideProviderInputs(false));
    if (reviewForm) {
      reviewForm.addEventListener('submit', (event) => {
        event.preventDefault();
        _submitReview();
      });
    }
  }

  async function _loadDetail() {
    _setLoading(true);
    _setError('');
    _setPageFeedback('');
    _setOffersFeedback('');
    _setActionFeedback('');
    _setProviderDecisionFeedback('');

    const res = await ApiClient.get('/api/marketplace/client/requests/' + _requestId + '/');
    _setLoading(false);

    if (!res.ok || !res.data) {
      _setError(_extractError(res, _copy('loadDetailsFailed')));
      return;
    }

    _order = res.data;
    _offers = [];
    _acceptingOfferId = null;
    _render();

    if (_isCompetitiveOrder(_order)) {
      await _loadOffers();
      return;
    }

    _renderOffersSection();
  }

  async function _loadOffers() {
    if (!_order || !_isCompetitiveOrder(_order)) {
      _renderOffersSection();
      return;
    }

    _offersLoading = true;
    _setOffersFeedback('');
    _renderOffersSection();

    const res = await ApiClient.get('/api/marketplace/requests/' + _requestId + '/offers/');
    _offersLoading = false;

    if (!res.ok || !res.data) {
      _offers = [];
      _setOffersFeedback(_extractError(res, _copy('loadOffersFailed')), true);
      _renderOffersSection();
      return;
    }

    _offers = _extractList(res.data);
    _renderOffersSection();
  }

  function _setLoading(loading) {
    const loadingEl = document.getElementById('order-loading');
    if (loadingEl) loadingEl.classList.toggle('hidden', !loading);
    if (loading) {
      const detail = document.getElementById('order-detail');
      if (detail) detail.classList.add('hidden');
    }
  }

  function _setError(message) {
    const err = document.getElementById('order-error');
    if (!err) return;
    if (!message) {
      err.textContent = '';
      err.classList.add('hidden');
      return;
    }
    err.textContent = message;
    err.classList.remove('hidden');
  }

  function _setOffersFeedback(message, isError) {
    const el = document.getElementById('order-offers-feedback');
    if (!el) return;
    if (!message) {
      el.textContent = '';
      el.classList.add('hidden');
      el.classList.remove('is-error', 'is-success');
      return;
    }
    el.textContent = message;
    el.classList.remove('hidden');
    el.classList.toggle('is-error', !!isError);
    el.classList.toggle('is-success', !isError);
  }

  function _setReviewFeedback(message, isError) {
    const el = document.getElementById('order-review-feedback');
    if (!el) return;
    if (!message) {
      el.textContent = '';
      el.classList.add('hidden');
      el.classList.remove('is-error', 'is-success');
      return;
    }
    el.textContent = message;
    el.classList.remove('hidden');
    el.classList.toggle('is-error', !!isError);
    el.classList.toggle('is-success', !isError);
  }

  function _setReviewSubmitLoading(loading) {
    const text = document.getElementById('btn-submit-review-text');
    const spinner = document.getElementById('btn-submit-review-spinner');
    if (text) text.textContent = loading ? _copy('reviewSubmitting') : _copy('reviewSubmit');
    if (spinner) spinner.classList.toggle('hidden', !loading);
  }

  function _scrollToReviewSection() {
    const section = document.getElementById('order-review-section');
    if (!section || section.classList.contains('hidden')) return;
    section.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }

  function _statusColor(group) {
    switch (String(group || '').toLowerCase()) {
      case 'new':
        return '#F59E0B';
      case 'in_progress':
        return '#2563EB';
      case 'completed':
        return '#16A34A';
      case 'cancelled':
        return '#DC2626';
      default:
        return '#6B7280';
    }
  }

  function _render() {
    if (!_order) return;

    const detail = document.getElementById('order-detail');
    if (detail) detail.classList.remove('hidden');

    const displayId = document.getElementById('order-display-id');
    if (displayId) {
      const id = _order.id || _requestId;
      displayId.textContent = 'R' + String(id).padStart(6, '0');
    }

    const statusBadge = document.getElementById('order-status-badge');
    if (statusBadge) {
      const color = _statusColor(_statusGroup(_order));
      statusBadge.textContent = _statusLabel(_order);
      statusBadge.style.color = color;
      statusBadge.style.borderColor = color;
      statusBadge.style.backgroundColor = color + '1A';
    }

    const meta = document.getElementById('order-meta');
    if (meta) {
      meta.innerHTML = '';
      const lines = [];
      if (_order.created_at) lines.push({ label: _copy('createdAt'), value: _formatDate(_order.created_at) });
      if (_order.request_type) lines.push({ label: _copy('requestType'), value: _requestTypeLabel(_order.request_type) });
      if (_order.category_name || _order.subcategory_name) {
        lines.push({
          label: _copy('category'),
          value: (_order.category_name || '-') + (_order.subcategory_name ? (' / ' + _order.subcategory_name) : ''),
        });
      }
      if (_order.provider_name) lines.push({ label: _copy('provider'), value: _order.provider_name, autoDirection: true });
      if (_order.provider_phone) lines.push({ label: _copy('providerPhone'), value: _order.provider_phone });
      const cityDisplay = UI.formatCityDisplay(_order.city_display || _order.city, _order.region || _order.region_name);
      if (cityDisplay) lines.push({ label: _copy('city'), value: cityDisplay });

      lines.forEach((line) => {
        const item = UI.el('div', { className: 'order-meta-line' });
        item.appendChild(UI.el('span', { className: 'order-meta-label', textContent: line.label }));
        const valueEl = UI.el('strong', { className: 'order-meta-value', textContent: line.value || '-' });
        if (line.autoDirection) _setAutoDirection(valueEl, line.value);
        item.appendChild(valueEl);
        meta.appendChild(item);
      });
    }

    const titleInput = document.getElementById('order-title');
    const descInput = document.getElementById('order-description');
    if (titleInput) titleInput.value = _order.title || '';
    if (descInput) descInput.value = _order.description || '';
    _setInputAutoDirection(titleInput, _order.title || '');
    _setInputAutoDirection(descInput, _order.description || '');
    _updateOriginalLanguageNotice();

    _renderAttachments(_order);
    _renderStatusLogs(_order.status_logs || []);
    _renderFinanceSection();
    _renderProviderInputsDecisionSection();
    _renderCancelledSection();
    _renderReviewSection();
    _renderActionsSection();

    _editTitle = false;
    _editDesc = false;
    _applyEditableState();
    _renderOffersSection();
  }

  function _renderFinanceSection() {
    const section = document.getElementById('order-finance-section');
    const grid = document.getElementById('order-finance-grid');
    const title = document.getElementById('order-finance-title');
    if (!section || !grid || !_order) return;

    const group = _statusGroup(_order);
    const cards = [];

    if (group === 'new' || group === 'in_progress') {
      if (_order.expected_delivery_at) cards.push(_readonlyInfoCard(_copy('expectedDelivery'), _formatDateOnly(_order.expected_delivery_at)));
      if (_order.estimated_service_amount !== null && _order.estimated_service_amount !== undefined) {
        cards.push(_readonlyInfoCard(_copy('estimatedAmount'), _formatMoney(_order.estimated_service_amount)));
      }
      if (_order.received_amount !== null && _order.received_amount !== undefined) {
        cards.push(_readonlyInfoCard(_copy('receivedAmount'), _formatMoney(_order.received_amount)));
      }
      if (_order.remaining_amount !== null && _order.remaining_amount !== undefined) {
        cards.push(_readonlyInfoCard(_copy('remainingAmount'), _formatMoney(_order.remaining_amount)));
      }
      title.textContent = _copy('financeTitle');
    }

    if (group === 'completed') {
      if (_order.delivered_at) cards.push(_readonlyInfoCard(_copy('deliveredAt'), _formatDateOnly(_order.delivered_at)));
      if (_order.actual_service_amount !== null && _order.actual_service_amount !== undefined) {
        cards.push(_readonlyInfoCard(_copy('actualAmount'), _formatMoney(_order.actual_service_amount)));
      }
      const completionAttachments = _splitAttachments(_order).provider;
      cards.push(_readonlyAttachmentsCard(_copy('attachmentsLabel'), completionAttachments));
      title.textContent = _copy('completionTitle');
    }

    grid.innerHTML = '';
    if (!cards.length) {
      section.classList.add('hidden');
      return;
    }

    cards.forEach((card) => grid.appendChild(card));
    section.classList.remove('hidden');
  }

  function _renderProviderInputsDecisionSection() {
    const section = document.getElementById('order-provider-decision-section');
    const grid = document.getElementById('order-provider-inputs-grid');
    const note = document.getElementById('order-provider-decision-note');
    const feedback = document.getElementById('order-provider-decision-feedback');
    const form = document.getElementById('order-provider-decision-form');
    const rejectReason = document.getElementById('order-provider-reject-note');
    if (!section || !grid || !note || !form || !_order) return;

    const hasInputs = (
      _workflowStage(_order) === 'awaiting_client' &&
      (_order.expected_delivery_at || _order.estimated_service_amount !== null || _order.received_amount !== null || _order.remaining_amount !== null)
    );

    if (!hasInputs) {
      section.classList.add('hidden');
      return;
    }

    grid.innerHTML = '';
    if (feedback) {
      feedback.textContent = '';
      feedback.classList.add('hidden');
      feedback.classList.remove('is-error', 'is-success');
    }
    if (_order.expected_delivery_at) grid.appendChild(_readonlyInfoCard(_copy('expectedDelivery'), _formatDateOnly(_order.expected_delivery_at)));
    if (_order.estimated_service_amount !== null && _order.estimated_service_amount !== undefined) {
      grid.appendChild(_readonlyInfoCard(_copy('estimatedAmount'), _formatMoney(_order.estimated_service_amount)));
    }
    if (_order.received_amount !== null && _order.received_amount !== undefined) {
      grid.appendChild(_readonlyInfoCard(_copy('receivedAmount'), _formatMoney(_order.received_amount)));
    }
    if (_order.remaining_amount !== null && _order.remaining_amount !== undefined) {
      grid.appendChild(_readonlyInfoCard(_copy('remainingAmount'), _formatMoney(_order.remaining_amount)));
    }

    if (_order.provider_inputs_approved === false && _order.provider_inputs_decision_note) {
      note.textContent = _copy('providerDecisionRejectedPrefix') + _order.provider_inputs_decision_note;
      _setAutoDirection(note, _order.provider_inputs_decision_note);
      note.classList.remove('hidden');
    } else {
      note.textContent = '';
      note.removeAttribute('dir');
      note.classList.add('hidden');
    }

    form.classList.toggle('hidden', _actionLoading);
    if (rejectReason && _order.provider_inputs_approved !== false) rejectReason.value = '';
    _setActionButtonsDisabled(_actionLoading);
    section.classList.remove('hidden');
  }

  function _renderCancelledSection() {
    const section = document.getElementById('order-cancelled-section');
    const grid = document.getElementById('order-cancelled-grid');
    if (!section || !grid || !_order) return;

    if (_statusGroup(_order) !== 'cancelled') {
      section.classList.add('hidden');
      return;
    }

    grid.innerHTML = '';
    grid.appendChild(_readonlyInfoCard(_copy('cancelDate'), _order.canceled_at ? _formatDateOnly(_order.canceled_at) : '-'));
    grid.appendChild(_readonlyInfoCard(_copy('cancelReason'), _order.cancel_reason || '-', { autoDirection: true }));
    section.classList.remove('hidden');
  }

  function _renderReviewSection() {
    const section = document.getElementById('order-review-section');
    const summary = document.getElementById('order-review-summary');
    const form = document.getElementById('order-review-form');
    if (!section || !summary || !form || !_order) return;

    if (!_canReview() && !_hasReview()) {
      section.classList.add('hidden');
      return;
    }

    const hasReview = _hasReview();
    summary.classList.toggle('hidden', !hasReview);
    if (hasReview) {
      summary.textContent = _copy('reviewSentPrefix') +
        (_order.review_rating !== null && _order.review_rating !== undefined ? (' - ' + _copy('overallRatingPrefix') + ': ' + _order.review_rating + '/5') : '') +
        (_order.review_comment ? (' - ' + _order.review_comment) : '');
      _setAutoDirection(summary, _order.review_comment || summary.textContent);
    } else {
      summary.textContent = '';
      summary.removeAttribute('dir');
    }

    form.classList.toggle('hidden', hasReview);
    if (hasReview) _fillReviewFieldsFromOrder();
    section.classList.remove('hidden');
  }

  function _renderActionsSection() {
    const section = document.getElementById('order-actions-section');
    const body = document.getElementById('order-actions-body');
    if (!section || !body || !_order) return;

    body.innerHTML = '';
    const group = _statusGroup(_order);
    const actions = _availableActions();

    if (group === 'new' && actions.includes('cancel')) {
      const reasonLabel = UI.el('label', {
        className: 'order-form-label',
        for: 'order-cancel-reason',
        textContent: _copy('cancelReasonLabel'),
      });
      const reasonInput = UI.el('textarea', {
        id: 'order-cancel-reason',
        className: 'form-textarea order-inline-textarea',
        rows: 3,
        placeholder: _copy('cancelReasonPlaceholder'),
      });
      const btn = UI.el('button', {
        type: 'button',
        className: 'btn-secondary',
        textContent: _copy('cancelOrder'),
        onclick: _cancelOrder,
      });
      body.appendChild(reasonLabel);
      body.appendChild(reasonInput);
      body.appendChild(btn);
      section.classList.remove('hidden');
      _setActionButtonsDisabled(_actionLoading);
      return;
    }

    if (group === 'cancelled') {
      const note = UI.el('div', {
        className: 'order-inline-note',
        textContent: _copy('reopenNote'),
      });
      const btn = UI.el('button', {
        type: 'button',
        className: 'btn-primary',
        textContent: _copy('reopenOrder'),
        onclick: _reopenOrder,
      });
      body.appendChild(note);
      body.appendChild(btn);
      section.classList.remove('hidden');
      _setActionButtonsDisabled(_actionLoading);
      return;
    }

    section.classList.add('hidden');
  }

  function _renderAttachments(order) {
    const emptyRoot = document.getElementById('order-attachments-empty');
    const clientGroup = document.getElementById('order-client-attachments-group');
    const clientRoot = document.getElementById('order-client-attachments');
    const providerGroup = document.getElementById('order-provider-attachments-group');
    const providerRoot = document.getElementById('order-provider-attachments');
    if (!emptyRoot || !clientGroup || !clientRoot || !providerGroup || !providerRoot) return;

    emptyRoot.innerHTML = '';
    clientRoot.innerHTML = '';
    providerRoot.innerHTML = '';
    emptyRoot.classList.add('hidden');
    clientGroup.classList.add('hidden');
    providerGroup.classList.add('hidden');

    const groups = _splitAttachments(order);
    if (!groups.client.length && !groups.provider.length) {
      emptyRoot.appendChild(UI.el('p', { className: 'ticket-muted', textContent: _copy('noAttachments') }));
      emptyRoot.classList.remove('hidden');
      return;
    }

    if (groups.client.length) {
      groups.client.forEach((item) => clientRoot.appendChild(_buildAttachmentLine(item)));
      clientGroup.classList.remove('hidden');
    }

    if (groups.provider.length) {
      groups.provider.forEach((item) => providerRoot.appendChild(_buildAttachmentLine(item)));
      providerGroup.classList.remove('hidden');
    }
  }

  function _buildAttachmentLine(item) {
    const href = _resolveAttachmentHref(item);
    const rawPath = String(item?.file_url || item?.file || item?.url || '').trim();
    const pathBits = rawPath.split('?')[0].split('/');
    const name = pathBits[pathBits.length - 1] || _copy('attachmentFile');
    const type = String(item?.file_type || '').toUpperCase() || 'FILE';
    const attrs = {
      className: 'order-line-link',
      title: href ? _copy('openAttachment') : _copy('attachmentUnavailable'),
    };
    if (href) {
      attrs.href = href;
      attrs.rel = 'noopener';
    }
    const line = UI.el(href ? 'a' : 'div', attrs);
    if (href) {
      line.addEventListener('click', (event) => {
        event.preventDefault();
        window.location.href = href;
      });
    }
    const nameWrap = UI.el('span', { className: 'order-file-name' });
    nameWrap.appendChild(UI.el('span', { className: 'order-file-icon', textContent: _attachmentIcon(type) }));
    nameWrap.appendChild(UI.el('span', { textContent: name }));
    line.appendChild(nameWrap);
    line.appendChild(UI.el('span', {
      className: 'order-line-type',
      textContent: type,
    }));
    return line;
  }

  function _attachmentIcon(type) {
    const t = String(type || '').toLowerCase();
    if (t.includes('image') || ['png', 'jpg', 'jpeg', 'webp'].includes(t)) return 'IMG';
    if (t.includes('pdf')) return 'PDF';
    if (t.includes('video') || t.includes('mp4')) return 'VID';
    if (t.includes('audio')) return 'AUD';
    return 'FILE';
  }

  function _splitAttachments(order) {
    const items = Array.isArray(order?.attachments) ? order.attachments : [];
    if (!items.length) return { client: [], provider: [] };

    const deliveredAt = _asDate(order?.delivered_at);
    if (!deliveredAt) {
      return { client: items, provider: [] };
    }

    const client = [];
    const provider = [];
    items.forEach((item) => {
      const createdAt = _asDate(item?.created_at);
      if (createdAt && createdAt.getTime() >= deliveredAt.getTime()) provider.push(item);
      else client.push(item);
    });
    return { client, provider };
  }

  function _resolveAttachmentHref(item) {
    const raw = String(item?.file_url || item?.file || item?.url || '').trim();
    if (!raw) return '';
    if (raw.startsWith('blob:') || raw.startsWith('data:')) return raw;
    if (/^https?:\/\//i.test(raw)) {
      try {
        const url = new URL(raw);
        if (url.pathname.startsWith('/media/')) {
          return window.location.origin + url.pathname + url.search + url.hash;
        }
        return url.toString();
      } catch (_) {
        return raw;
      }
    }
    return ApiClient.mediaUrl(raw) || '';
  }

  function _renderStatusLogs(items) {
    const root = document.getElementById('order-status-logs');
    if (!root) return;
    root.innerHTML = '';

    if (!Array.isArray(items) || !items.length) {
      root.appendChild(UI.el('p', { className: 'ticket-muted', textContent: _copy('noStatusLog') }));
      return;
    }

    items.forEach((log) => {
      const row = UI.el('div', { className: 'order-log-row' });
      const fromLabel = _statusLabelFromCode(log.from_status);
      const toLabel = _statusLabelFromCode(log.to_status);
      row.appendChild(UI.el('div', {
        className: 'order-log-title',
        textContent: fromLabel + ' → ' + toLabel,
      }));
      if (log.note) {
        const noteEl = UI.el('div', { className: 'order-log-note', textContent: log.note });
        _setAutoDirection(noteEl, log.note);
        row.appendChild(noteEl);
      }
      if (log.created_at) row.appendChild(UI.el('div', { className: 'order-log-time', textContent: _formatDate(log.created_at) }));
      root.appendChild(row);
    });
  }

  function _readonlyInfoCard(label, value, options) {
    const item = UI.el('div', { className: 'order-info-item' });
    item.appendChild(UI.el('div', { className: 'order-info-label', textContent: label }));
    const valueEl = UI.el('div', { className: 'order-info-value', textContent: value || '-' });
    if (options && options.autoDirection) _setAutoDirection(valueEl, value);
    item.appendChild(valueEl);
    return item;
  }

  function _readonlyAttachmentsCard(label, attachments) {
    const item = UI.el('div', { className: 'order-info-item order-info-item-attachments' });
    item.appendChild(UI.el('div', { className: 'order-info-label', textContent: label }));

    const body = document.createElement('div');
    body.className = 'order-info-attachments-list';

    if (!Array.isArray(attachments) || !attachments.length) {
      body.appendChild(UI.el('div', { className: 'order-info-value', textContent: _copy('noAttachments') }));
      item.appendChild(body);
      return item;
    }

    attachments.forEach((attachment) => body.appendChild(_buildAttachmentLine(attachment)));
    item.appendChild(body);
    return item;
  }

  function _statusLabelFromCode(raw) {
    const code = String(raw || '').trim().toLowerCase();
    if (code === 'new') return _copy('statusNew');
    if (code === 'submitted') return _copy('statusSubmitted');
    if (code === 'waiting') return _copy('statusWaiting');
    if (code === 'provider_accepted') return _copy('statusAccepted');
    if (code === 'awaiting_client') return _copy('statusAwaitingClient');
    if (code === 'in_progress') return _copy('statusInProgress');
    if (code === 'completed') return _copy('statusCompleted');
    if (code === 'cancelled' || code === 'canceled') return _copy('statusCancelled');
    return String(raw || '—') || '—';
  }

  function _renderOffersSection() {
    const section = document.getElementById('order-offers-section');
    const root = document.getElementById('order-offers');
    const refreshBtn = document.getElementById('btn-refresh-offers');
    if (!section || !root) return;

    if (!_order || !_isCompetitiveOrder(_order)) {
      section.classList.add('hidden');
      root.innerHTML = '';
      if (refreshBtn) refreshBtn.disabled = true;
      return;
    }

    section.classList.remove('hidden');
    if (refreshBtn) refreshBtn.disabled = _offersLoading;
    root.innerHTML = '';

    if (_offersLoading) {
      const loading = UI.el('div', { className: 'order-offers-state' });
      loading.appendChild(UI.el('span', { className: 'spinner-inline' }));
      loading.appendChild(UI.el('span', { textContent: _copy('loadingOffers') }));
      root.appendChild(loading);
      return;
    }

    if (!_offers.length) {
      root.appendChild(UI.el('p', {
        className: 'ticket-muted',
        textContent: _copy('noOffers'),
      }));
      return;
    }

    const canSelectOffer = _canSelectOffers();

    _offers.forEach((offer) => {
      const card = UI.el('article', { className: 'order-offer-card' });
      const head = UI.el('div', { className: 'order-offer-head' });
      const providerName = String(offer.provider_name || '').trim() || (_copy('providerFallback') + ' #' + String(offer.provider || ''));
      const providerHref = _providerProfileHref(offer);

      if (providerHref) {
        const providerLink = UI.el('a', {
          className: 'order-offer-provider',
          href: providerHref,
          title: _copy('providerProfileTitle'),
        });
        providerLink.appendChild(UI.el('span', { className: 'order-offer-provider-name', textContent: providerName }));
        providerLink.appendChild(UI.el('span', { className: 'order-offer-provider-open', textContent: '↗' }));
        head.appendChild(providerLink);
      } else {
        head.appendChild(UI.el('span', { className: 'order-offer-provider-static', textContent: providerName }));
      }

      const statusColor = _offerStatusColor(offer.status);
      head.appendChild(UI.el('span', {
        className: 'order-offer-status',
        textContent: _offerStatusLabel(offer.status),
        style: {
          color: statusColor,
          borderColor: statusColor + '66',
          backgroundColor: statusColor + '14',
        },
      }));
      card.appendChild(head);

      card.appendChild(UI.el('div', {
        className: 'order-offer-line',
        textContent: _copy('offerPrice') + ': ' + String(offer.price || '-') + ' (' + _copy('currency') + ')',
      }));
      card.appendChild(UI.el('div', {
        className: 'order-offer-line',
        textContent: _copy('offerDuration') + ': ' + String(offer.duration_days || '-') + ' ' + _copy('days'),
      }));

      const note = String(offer.note || '').trim();
      if (note) {
        card.appendChild(UI.el('div', {
          className: 'order-offer-note',
          textContent: _copy('offerNote') + ': ' + note,
        }));
      }

      if (canSelectOffer && String(offer.status || '').toLowerCase() === 'pending') {
        const selecting = _acceptingOfferId === Number(offer.id);
        const selectBtn = UI.el('button', {
          type: 'button',
          className: 'btn-primary order-offer-select-btn',
          textContent: selecting ? _copy('selectingOffer') : _copy('selectOffer'),
          onclick: () => _acceptOffer(offer),
        });
        // UI.el sets attributes via setAttribute; passing disabled=false still disables
        // the control because boolean attributes are truthy by presence in HTML.
        // Set the property directly so pending buttons stay clickable.
        selectBtn.disabled = selecting;
        card.appendChild(selectBtn);
      }

      root.appendChild(card);
    });
  }

  async function _acceptOffer(offer) {
    if (!_order || !offer) return;
    if (!_canSelectOffers()) {
      _setOffersFeedback(_copy('cannotSelectOffer'), true);
      return;
    }

    const offerId = Number(offer.id);
    if (!Number.isFinite(offerId) || offerId <= 0) {
      _setOffersFeedback(_copy('invalidOfferId'), true);
      return;
    }

    _acceptingOfferId = offerId;
    _setOffersFeedback('');
    _renderOffersSection();

    const res = await ApiClient.request('/api/marketplace/offers/' + offerId + '/accept/', {
      method: 'POST',
      body: {},
    });

    _acceptingOfferId = null;

    if (!res.ok) {
      _setOffersFeedback(_extractError(res, _copy('acceptOfferFailed')), true);
      _renderOffersSection();
      return;
    }

    _setOffersFeedback(_copy('acceptOfferSuccess'), false);
    _loadDetail();
  }

  function _providerProfileHref(offer) {
    const providerId = Number(offer && offer.provider);
    if (!Number.isFinite(providerId) || providerId <= 0) return '';

    const returnTo = window.location.pathname + window.location.search + '#order-offers-section';
    const params = new URLSearchParams();
    params.set('return_to', returnTo);
    params.set('return_label', _copy('returnToOffers'));

    return '/provider/' + encodeURIComponent(String(providerId)) + '/?' + params.toString();
  }

  function _canSelectOffers() {
    return Boolean(
      _order &&
      _isCompetitiveOrder(_order) &&
      _statusGroup(_order) === 'new' &&
      !_hasAssignedProvider(_order),
    );
  }

  function _canReview() {
    if (!_order || !_hasAssignedProvider(_order) || _hasReview()) return false;
    const group = _statusGroup(_order);
    return group === 'completed';
  }

  function _hasReview() {
    return Boolean(_order && _order.review_id);
  }

  function _offerStatusColor(status) {
    switch (String(status || '').toLowerCase()) {
      case 'selected':
        return '#16A34A';
      case 'rejected':
        return '#DC2626';
      default:
        return '#B45309';
    }
  }

  function _offerStatusLabel(status) {
    switch (String(status || '').toLowerCase()) {
      case 'selected':
        return _copy('statusAccepted');
      case 'rejected':
        return _copy('statusRejected');
      default:
        return _copy('statusPendingDecision');
    }
  }

  function _extractList(payload) {
    if (Array.isArray(payload)) return payload;
    if (payload && Array.isArray(payload.results)) return payload.results;
    return [];
  }

  function _extractError(res, fallback) {
    if (!res || !res.data) return fallback;
    const data = res.data;
    if (typeof data === 'string' && data.trim()) return data.trim();
    if (typeof data.detail === 'string' && data.detail.trim()) return data.detail.trim();
    if (typeof data === 'object') {
      for (const key of Object.keys(data)) {
        const value = data[key];
        if (typeof value === 'string' && value.trim()) return value.trim();
        if (Array.isArray(value) && value.length && typeof value[0] === 'string') return value[0];
      }
    }
    return fallback;
  }

  function _requestTypeLabel(type) {
    const t = String(type || '').toLowerCase();
    if (t === 'urgent') return _copy('requestTypeUrgent');
    if (t === 'competitive') return _copy('requestTypeCompetitive');
    if (t === 'normal') return _copy('requestTypeNormal');
    return type || '';
  }

  function _formatDate(value) {
    const dt = _asDate(value);
    if (!dt) return '';
    return dt.toLocaleString(_locale(), {
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
    });
  }

  function _formatDateOnly(value) {
    const dt = _asDate(value);
    if (!dt) return '';
    return dt.toLocaleDateString(_locale(), {
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    });
  }

  function _formatMoney(value) {
    const num = Number(value);
    if (!Number.isFinite(num)) return String(value || '-');
    return num.toLocaleString(_numberLocale()) + ' ' + _copy('currency');
  }

  function _asDate(value) {
    if (!value) return null;
    const dt = value instanceof Date ? value : new Date(value);
    return Number.isNaN(dt.getTime()) ? null : dt;
  }

  function _statusGroup(order) {
    const explicit = String(order && order.status_group || '').toLowerCase();
    if (['new', 'in_progress', 'completed', 'cancelled'].includes(explicit)) return explicit;
    const status = String(order && order.status || '').toLowerCase();
    if (status === 'in_progress') return 'in_progress';
    if (status === 'completed') return 'completed';
    if (status === 'cancelled' || status === 'canceled') return 'cancelled';
    return 'new';
  }

  function _workflowStage(order) {
    return String(order && order.status || '').toLowerCase();
  }

  function _isCompetitiveOrder(order) {
    return String(order && order.request_type || '').toLowerCase() === 'competitive';
  }

  function _hasAssignedProvider(order) {
    const provider = order && order.provider;
    if (provider === null || provider === undefined || provider === '') return false;
    if (typeof provider === 'object') return provider.id !== null && provider.id !== undefined;
    return true;
  }

  function _canEdit() {
    return _workflowStage(_order) === 'new';
  }

  function _availableActions() {
    return Array.isArray(_order && _order.available_actions) ? _order.available_actions : [];
  }

  function _applyEditableState() {
    const canEdit = _canEdit();
    const titleInput = document.getElementById('order-title');
    const descInput = document.getElementById('order-description');
    const tBtn = document.getElementById('btn-toggle-title');
    const dBtn = document.getElementById('btn-toggle-desc');
    const saveBtn = document.getElementById('btn-save-order');

    if (titleInput) titleInput.disabled = !(canEdit && _editTitle);
    if (descInput) descInput.disabled = !(canEdit && _editDesc);

    if (tBtn) {
      tBtn.classList.toggle('hidden', !canEdit);
      tBtn.textContent = _editTitle ? _copy('stopEdit') : _copy('edit');
    }

    if (dBtn) {
      dBtn.classList.toggle('hidden', !canEdit);
      dBtn.textContent = _editDesc ? _copy('stopEdit') : _copy('edit');
    }

    if (saveBtn) saveBtn.classList.toggle('hidden', !canEdit);
  }

  function _fillReviewFieldsFromOrder() {
    _setSelectValue('review-response-speed', _order.review_response_speed);
    _setSelectValue('review-cost-value', _order.review_cost_value);
    _setSelectValue('review-quality', _order.review_quality);
    _setSelectValue('review-credibility', _order.review_credibility);
    _setSelectValue('review-on-time', _order.review_on_time);
    const comment = document.getElementById('review-comment');
    if (comment) comment.value = _order.review_comment || '';
  }

  function _setSelectValue(id, value) {
    const node = document.getElementById(id);
    if (node) node.value = value !== null && value !== undefined ? String(Math.round(Number(value))) : '';
  }

  async function _save() {
    if (!_order || !_canEdit()) return;

    const titleInput = document.getElementById('order-title');
    const descInput = document.getElementById('order-description');
    if (!titleInput || !descInput) return;

    const newTitle = String(titleInput.value || '').trim();
    const newDesc = String(descInput.value || '').trim();
    if (!newTitle || !newDesc) {
      _setError(_copy('saveRequired'));
      return;
    }

    const patchBody = {};
    if (newTitle !== String(_order.title || '')) patchBody.title = newTitle;
    if (newDesc !== String(_order.description || '')) patchBody.description = newDesc;
    if (!Object.keys(patchBody).length) return;

    _setSaveLoading(true);
    const res = await ApiClient.request('/api/marketplace/client/requests/' + _requestId + '/', {
      method: 'PATCH',
      body: patchBody,
    });
    _setSaveLoading(false);

    if (!res.ok || !res.data) {
      _setError(_extractError(res, _copy('saveFailed')));
      return;
    }

    _setError('');
    _order = res.data;
    _render();
  }

  async function _cancelOrder() {
    if (!_order || _actionLoading || !_availableActions().includes('cancel')) return;
    const reason = String(document.getElementById('order-cancel-reason')?.value || '').trim();
    if (!reason) {
      _setActionFeedback(_copy('writeCancelReason'), true);
      return;
    }

    _setActionLoading(true);
    const res = await ApiClient.request('/api/marketplace/requests/' + _requestId + '/cancel/', {
      method: 'POST',
      body: { reason },
    });
    _setActionLoading(false);

    if (!res.ok) {
      _setActionFeedback(_extractError(res, _copy('cancelFailed')), true);
      return;
    }

    _setActionFeedback(_copy('cancelSuccess'), false);
    _loadDetail();
  }

  async function _reopenOrder() {
    if (!_order || _actionLoading || _statusGroup(_order) !== 'cancelled') return;

    _setActionLoading(true);
    const res = await ApiClient.request('/api/marketplace/requests/' + _requestId + '/reopen/', {
      method: 'POST',
      body: {},
    });
    _setActionLoading(false);

    if (!res.ok) {
      _setActionFeedback(_extractError(res, _copy('reopenFailed')), true);
      return;
    }

    _setActionFeedback(_copy('reopenSuccess'), false);
    _loadDetail();
  }

  async function _decideProviderInputs(approved) {
    if (!_order || _actionLoading) return;
    const note = String(document.getElementById('order-provider-reject-note')?.value || '').trim();
    if (!approved && !note) {
      _setProviderDecisionFeedback(_copy('rejectReasonRequired'), true);
      return;
    }

    _setActionLoading(true);
    const res = await ApiClient.request('/api/marketplace/requests/' + _requestId + '/provider-inputs/decision/', {
      method: 'POST',
      body: approved ? { approved: true } : { approved: false, note },
    });
    _setActionLoading(false);

    if (!res.ok) {
      _setProviderDecisionFeedback(_extractError(res, _copy('actionFailed')), true);
      return;
    }

    await _loadDetail();
    _setPageFeedback(
      String(res.data?.message || '') || (approved ? _copy('approveSuccess') : _copy('rejectSuccess')),
      false,
    );
  }

  async function _submitReview() {
    if (!_order || _actionLoading || !_canReview()) return;

    const fields = {
      response_speed: document.getElementById('review-response-speed')?.value || '',
      cost_value: document.getElementById('review-cost-value')?.value || '',
      quality: document.getElementById('review-quality')?.value || '',
      credibility: document.getElementById('review-credibility')?.value || '',
      on_time: document.getElementById('review-on-time')?.value || '',
    };

    for (const [key, value] of Object.entries(fields)) {
      if (!value) {
        _setReviewFeedback(_copy('reviewFillAll'), true);
        const id = 'review-' + key.replace(/_/g, '-');
        const node = document.getElementById(id);
        if (node) node.focus();
        _scrollToReviewSection();
        return;
      }
    }

    const comment = String(document.getElementById('review-comment')?.value || '').trim();
    if (comment.length > 300) {
      _setReviewFeedback(_copy('reviewTooLong'), true);
      _scrollToReviewSection();
      return;
    }
    const body = {
      response_speed: Number(fields.response_speed),
      cost_value: Number(fields.cost_value),
      quality: Number(fields.quality),
      credibility: Number(fields.credibility),
      on_time: Number(fields.on_time),
    };
    if (comment) body.comment = comment;

    _setReviewFeedback(_copy('reviewSendInProgress'), false);
    _setReviewSubmitLoading(true);
    _scrollToReviewSection();
    _setActionLoading(true);
    const res = await ApiClient.request('/api/reviews/requests/' + _requestId + '/review/', {
      method: 'POST',
      body,
    });
    _setActionLoading(false);
    _setReviewSubmitLoading(false);

    if (!res.ok) {
      _setReviewFeedback(_extractError(res, _copy('reviewSendFailed')), true);
      _scrollToReviewSection();
      return;
    }

    const criteriaValues = Object.values(fields).map((value) => Number(value) || 0);
    const overallRating = criteriaValues.reduce((sum, value) => sum + value, 0) / criteriaValues.length;
    _order.review_id = Number(res.data?.review_id || res.data?.id || Date.now());
    _order.review_response_speed = body.response_speed;
    _order.review_cost_value = body.cost_value;
    _order.review_quality = body.quality;
    _order.review_credibility = body.credibility;
    _order.review_on_time = body.on_time;
    _order.review_comment = comment;
    _order.review_rating = Number.isFinite(overallRating) ? Number(overallRating.toFixed(1)) : null;
    _renderReviewSection();
    _setReviewFeedback(_copy('reviewSendSuccess'), false);
    _scrollToReviewSection();
    _loadDetail();
  }

  function _setActionLoading(loading) {
    _actionLoading = loading;
    _setActionButtonsDisabled(loading);
  }

  function _setActionButtonsDisabled(disabled) {
    document.querySelectorAll('#order-actions-body button, #order-provider-decision-form button, #order-review-form button').forEach((node) => {
      node.disabled = disabled;
    });
  }

  function _setActionFeedback(message, isError) {
    const el = document.getElementById('order-action-feedback');
    if (!el) return;
    if (!message) {
      el.textContent = '';
      el.classList.add('hidden');
      el.classList.remove('is-error', 'is-success');
      return;
    }
    el.textContent = message;
    el.classList.remove('hidden');
    el.classList.toggle('is-error', !!isError);
    el.classList.toggle('is-success', !isError);
  }

  function _setPageFeedback(message, isError) {
    const el = document.getElementById('order-page-feedback');
    if (!el) return;
    if (!message) {
      el.textContent = '';
      el.classList.add('hidden');
      el.classList.remove('is-error', 'is-success');
      return;
    }
    el.textContent = message;
    el.classList.remove('hidden');
    el.classList.toggle('is-error', !!isError);
    el.classList.toggle('is-success', !isError);
  }

  function _setProviderDecisionFeedback(message, isError) {
    const el = document.getElementById('order-provider-decision-feedback');
    if (!el) return;
    if (!message) {
      el.textContent = '';
      el.classList.add('hidden');
      el.classList.remove('is-error', 'is-success');
      return;
    }
    el.textContent = message;
    el.classList.remove('hidden');
    el.classList.toggle('is-error', !!isError);
    el.classList.toggle('is-success', !isError);
  }

  function _setSaveLoading(loading) {
    const btn = document.getElementById('btn-save-order');
    const txt = document.getElementById('save-order-text');
    const spinner = document.getElementById('save-order-spinner');
    if (btn) btn.disabled = loading;
    if (txt) txt.classList.toggle('hidden', loading);
    if (spinner) spinner.classList.toggle('hidden', !loading);
  }

  function _statusLabel(order) {
    const raw = String((order && (order.status_group || order.status || order.status_label)) || '').trim().toLowerCase();
    return _statusLabelFromCode(raw) || _copy('statusUnknown');
  }

  function _currentLang() {
    if (window.NawafethI18n && typeof window.NawafethI18n.getLanguage === 'function') {
      return window.NawafethI18n.getLanguage() === 'en' ? 'en' : 'ar';
    }
    return document.documentElement.lang === 'en' ? 'en' : 'ar';
  }

  function _locale() {
    return _currentLang() === 'en' ? 'en-GB' : 'ar-SA';
  }

  function _numberLocale() {
    return _currentLang() === 'en' ? 'en-US' : 'ar-SA';
  }

  function _copy(key) {
    const lang = _currentLang();
    return (COPY[lang] && COPY[lang][key]) || COPY.ar[key] || '';
  }

  function _applyStaticCopy() {
    document.title = _copy('pageTitle');
    const backLink = document.getElementById('order-back-link');
    const loginLink = document.getElementById('order-login-link');
    const rejectNote = document.getElementById('order-provider-reject-note');
    const reviewComment = document.getElementById('review-comment');
    if (backLink) backLink.setAttribute('aria-label', _copy('backAria'));
    if (loginLink) loginLink.textContent = _copy('gateButton');
    if (rejectNote) rejectNote.placeholder = _copy('providerRejectPlaceholder');
    if (reviewComment) reviewComment.placeholder = _copy('reviewCommentPlaceholder');
    _setText('order-gate-title', _copy('gateTitle'));
    _setText('order-gate-desc', _copy('gateDescription'));
    _setText('order-page-kicker', _copy('kicker'));
    _setText('order-page-title', _copy('title'));
    _setText('order-page-subtitle', _copy('subtitle'));
    _setText('order-back-link-text', _copy('backText'));
    _setText('order-summary-id-label', _copy('orderIdLabel'));
    _setText('order-title-heading', _copy('orderTitleHeading'));
    _setText('order-description-heading', _copy('orderDescriptionHeading'));
    _setText('order-attachments-title', _copy('attachmentsTitle'));
    _setText('order-client-attachments-title', _copy('clientAttachmentsTitle'));
    _setText('order-client-attachments-desc', _copy('clientAttachmentsDesc'));
    _setText('order-provider-attachments-title', _copy('providerAttachmentsTitle'));
    _setText('order-provider-attachments-desc', _copy('providerAttachmentsDesc'));
    _setText('order-provider-decision-title', _copy('providerDecisionTitle'));
    _setText('order-provider-reject-label', _copy('providerRejectLabel'));
    _setText('btn-reject-provider-inputs', _copy('rejectDetails'));
    _setText('btn-approve-provider-inputs', _copy('approveAndStart'));
    _setText('order-cancelled-title', _copy('cancelledTitle'));
    _setText('order-review-title', _copy('reviewTitle'));
    _setText('review-response-speed-label', _copy('reviewResponseSpeed'));
    _setText('review-cost-value-label', _copy('reviewCostValue'));
    _setText('review-quality-label', _copy('reviewQuality'));
    _setText('review-credibility-label', _copy('reviewCredibility'));
    _setText('review-on-time-label', _copy('reviewOnTime'));
    _setText('review-response-speed-placeholder', _copy('reviewPick'));
    _setText('review-cost-value-placeholder', _copy('reviewPick'));
    _setText('review-quality-placeholder', _copy('reviewPick'));
    _setText('review-credibility-placeholder', _copy('reviewPick'));
    _setText('review-on-time-placeholder', _copy('reviewPick'));
    _setText('review-comment-label', _copy('reviewCommentLabel'));
    _setText('btn-submit-review-text', _copy('reviewSubmit'));
    _setText('order-status-logs-title', _copy('statusLogsTitle'));
    _setText('order-offers-title', _copy('offersTitle'));
    _setText('btn-refresh-offers', _copy('refresh'));
    _setText('order-actions-title', _copy('actionsTitle'));
    _setText('order-bottom-back', _copy('back'));
    _setText('save-order-text', _copy('save'));
    _setText('order-original-language-note', _copy('originalLanguageNotice'));
  }

  function _containsArabicScript(value) {
    return /[\u0600-\u06FF]/.test(String(value || '').trim());
  }

  function _hasOriginalLanguageContent() {
    if (!_order || _currentLang() !== 'en') return false;
    const directFields = [
      _order.title,
      _order.description,
      _order.provider_name,
      _order.provider_inputs_decision_note,
      _order.review_comment,
      _order.cancel_reason,
    ];
    if (directFields.some(_containsArabicScript)) return true;
    return Array.isArray(_order.status_logs) && _order.status_logs.some((log) => _containsArabicScript(log && log.note));
  }

  function _updateOriginalLanguageNotice() {
    const notice = document.getElementById('order-original-language-note');
    if (!notice) return;
    notice.textContent = _copy('originalLanguageNotice');
    notice.classList.toggle('hidden', !_hasOriginalLanguageContent());
  }

  function _setText(id, value) {
    const el = document.getElementById(id);
    if (el) el.textContent = value;
  }

  function _setAutoDirection(el, value) {
    if (!el) return;
    if (String(value || '').trim()) el.setAttribute('dir', 'auto');
    else el.removeAttribute('dir');
  }

  function _setInputAutoDirection(el, value) {
    _setAutoDirection(el, value);
  }

  function _handleLanguageChange() {
    _applyStaticCopy();
    if (_order) _render();
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();

  return {};
})();
