/* ===================================================================
   orderDetailPage.js — Client order details
   GET/PATCH /api/marketplace/client/requests/<id>/
   =================================================================== */
'use strict';

const OrderDetailPage = (() => {
  let _requestId = null;
  let _order = null;
  let _offers = [];
  let _offersLoading = false;
  let _acceptingOfferId = null;
  let _editTitle = false;
  let _editDesc = false;
  let _actionLoading = false;

  function init() {
    _requestId = _parseRequestId();
    if (!_requestId) {
      _setError('تعذر تحديد رقم الطلب');
      return;
    }

    if (!Auth.isLoggedIn()) {
      _showGate();
      return;
    }

    _hideGate();
    _bindActions();
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
    _setOffersFeedback('');
    _setActionFeedback('');

    const res = await ApiClient.get('/api/marketplace/client/requests/' + _requestId + '/');
    _setLoading(false);

    if (!res.ok || !res.data) {
      _setError(_extractError(res, 'تعذر تحميل تفاصيل الطلب'));
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
      _setOffersFeedback(_extractError(res, 'تعذر تحميل عروض الأسعار'), true);
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
      statusBadge.textContent = _order.status_label || _order.status_group || _order.status || 'غير محدد';
      statusBadge.style.color = color;
      statusBadge.style.borderColor = color;
      statusBadge.style.backgroundColor = color + '1A';
    }

    const meta = document.getElementById('order-meta');
    if (meta) {
      meta.innerHTML = '';
      const lines = [];
      if (_order.created_at) lines.push('تاريخ الإنشاء: ' + _formatDate(_order.created_at));
      if (_order.request_type) lines.push('نوع الطلب: ' + _requestTypeLabel(_order.request_type));
      if (_order.category_name || _order.subcategory_name) {
        lines.push(
          'التصنيف: ' +
          (_order.category_name || '-') +
          (_order.subcategory_name ? (' / ' + _order.subcategory_name) : ''),
        );
      }
      if (_order.provider_name) lines.push('مقدم الخدمة: ' + _order.provider_name);
      if (_order.provider_phone) lines.push('رقم مقدم الخدمة: ' + _order.provider_phone);
      if (_order.city) lines.push('المدينة: ' + _order.city);

      lines.forEach((line) => {
        meta.appendChild(UI.el('div', { className: 'order-meta-line', textContent: line }));
      });
    }

    const titleInput = document.getElementById('order-title');
    const descInput = document.getElementById('order-description');
    if (titleInput) titleInput.value = _order.title || '';
    if (descInput) descInput.value = _order.description || '';

    _renderAttachments(_order.attachments || []);
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
    const rows = [];

    if (group === 'new' || group === 'in_progress') {
      if (_order.expected_delivery_at) rows.push(['موعد التسليم المتوقع', _formatDateOnly(_order.expected_delivery_at)]);
      if (_order.estimated_service_amount !== null && _order.estimated_service_amount !== undefined) {
        rows.push(['قيمة الخدمة المقدرة', _formatMoney(_order.estimated_service_amount)]);
      }
      if (_order.received_amount !== null && _order.received_amount !== undefined) {
        rows.push(['المبلغ المستلم', _formatMoney(_order.received_amount)]);
      }
      if (_order.remaining_amount !== null && _order.remaining_amount !== undefined) {
        rows.push(['المبلغ المتبقي', _formatMoney(_order.remaining_amount)]);
      }
      title.textContent = 'تفاصيل التنفيذ';
    }

    if (group === 'completed') {
      if (_order.delivered_at) rows.push(['موعد التسليم الفعلي', _formatDateOnly(_order.delivered_at)]);
      if (_order.actual_service_amount !== null && _order.actual_service_amount !== undefined) {
        rows.push(['قيمة الخدمة الفعلية', _formatMoney(_order.actual_service_amount)]);
      }
      title.textContent = 'بيانات الإكمال';
    }

    grid.innerHTML = '';
    if (!rows.length) {
      section.classList.add('hidden');
      return;
    }

    rows.forEach(([label, value]) => grid.appendChild(_readonlyInfoCard(label, value)));
    section.classList.remove('hidden');
  }

  function _renderProviderInputsDecisionSection() {
    const section = document.getElementById('order-provider-decision-section');
    const grid = document.getElementById('order-provider-inputs-grid');
    const note = document.getElementById('order-provider-decision-note');
    const form = document.getElementById('order-provider-decision-form');
    const rejectReason = document.getElementById('order-provider-reject-note');
    if (!section || !grid || !note || !form || !_order) return;

    const hasInputs = (
      _statusGroup(_order) === 'new' &&
      (_order.expected_delivery_at || _order.estimated_service_amount !== null || _order.received_amount !== null || _order.remaining_amount !== null)
    );

    if (!hasInputs) {
      section.classList.add('hidden');
      return;
    }

    grid.innerHTML = '';
    if (_order.expected_delivery_at) grid.appendChild(_readonlyInfoCard('موعد التسليم المتوقع', _formatDateOnly(_order.expected_delivery_at)));
    if (_order.estimated_service_amount !== null && _order.estimated_service_amount !== undefined) {
      grid.appendChild(_readonlyInfoCard('قيمة الخدمة المقدرة', _formatMoney(_order.estimated_service_amount)));
    }
    if (_order.received_amount !== null && _order.received_amount !== undefined) {
      grid.appendChild(_readonlyInfoCard('المبلغ المستلم', _formatMoney(_order.received_amount)));
    }
    if (_order.remaining_amount !== null && _order.remaining_amount !== undefined) {
      grid.appendChild(_readonlyInfoCard('المبلغ المتبقي', _formatMoney(_order.remaining_amount)));
    }

    if (_order.provider_inputs_approved === false && _order.provider_inputs_decision_note) {
      note.textContent = 'تم رفض التفاصيل سابقًا: ' + _order.provider_inputs_decision_note;
      note.classList.remove('hidden');
    } else {
      note.textContent = '';
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
    grid.appendChild(_readonlyInfoCard('تاريخ الإلغاء', _order.canceled_at ? _formatDate(_order.canceled_at) : '-'));
    grid.appendChild(_readonlyInfoCard('سبب الإلغاء', _order.cancel_reason || '-'));
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
      summary.textContent = 'تم إرسال تقييمك مسبقًا' +
        (_order.review_rating !== null && _order.review_rating !== undefined ? (' - التقييم العام: ' + _order.review_rating + '/5') : '') +
        (_order.review_comment ? (' - ' + _order.review_comment) : '');
    } else {
      summary.textContent = '';
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

    if (group === 'new') {
      const reasonLabel = UI.el('label', {
        className: 'order-form-label',
        for: 'order-cancel-reason',
        textContent: 'سبب الإلغاء',
      });
      const reasonInput = UI.el('textarea', {
        id: 'order-cancel-reason',
        className: 'form-textarea order-inline-textarea',
        rows: 3,
        placeholder: 'اكتب سبب إلغاء الطلب',
      });
      const btn = UI.el('button', {
        type: 'button',
        className: 'btn-secondary',
        textContent: 'إلغاء الطلب',
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
        textContent: 'يمكنك إعادة فتح الطلب ليعود إلى حالة جديد بدون مقدم خدمة معيّن.',
      });
      const btn = UI.el('button', {
        type: 'button',
        className: 'btn-primary',
        textContent: 'إعادة فتح الطلب',
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

  function _renderAttachments(items) {
    const root = document.getElementById('order-attachments');
    if (!root) return;
    root.innerHTML = '';

    if (!Array.isArray(items) || !items.length) {
      root.appendChild(UI.el('p', { className: 'ticket-muted', textContent: 'لا يوجد مرفقات' }));
      return;
    }

    items.forEach((item) => {
      const href = ApiClient.mediaUrl(item.file_url || item.file || '');
      const name = String(item.file_url || item.file || '').split('/').pop() || 'ملف';
      const line = UI.el('a', {
        className: 'order-line-link',
        href,
        target: '_blank',
        rel: 'noopener',
      });
      line.appendChild(UI.el('span', { textContent: name }));
      line.appendChild(UI.el('span', {
        className: 'order-line-type',
        textContent: String(item.file_type || '').toUpperCase(),
      }));
      root.appendChild(line);
    });
  }

  function _renderStatusLogs(items) {
    const root = document.getElementById('order-status-logs');
    if (!root) return;
    root.innerHTML = '';

    if (!Array.isArray(items) || !items.length) {
      root.appendChild(UI.el('p', { className: 'ticket-muted', textContent: 'لا يوجد سجل حالة' }));
      return;
    }

    items.forEach((log) => {
      const row = UI.el('div', { className: 'order-log-row' });
      row.appendChild(UI.el('div', {
        className: 'order-log-title',
        textContent: (log.from_status || '—') + ' → ' + (log.to_status || '—'),
      }));
      if (log.note) row.appendChild(UI.el('div', { className: 'order-log-note', textContent: log.note }));
      if (log.created_at) row.appendChild(UI.el('div', { className: 'order-log-time', textContent: _formatDate(log.created_at) }));
      root.appendChild(row);
    });
  }

  function _readonlyInfoCard(label, value) {
    const item = UI.el('div', { className: 'order-info-item' });
    item.appendChild(UI.el('div', { className: 'order-info-label', textContent: label }));
    item.appendChild(UI.el('div', { className: 'order-info-value', textContent: value || '-' }));
    return item;
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
      loading.appendChild(UI.el('span', { textContent: 'جاري تحميل عروض الأسعار...' }));
      root.appendChild(loading);
      return;
    }

    if (!_offers.length) {
      root.appendChild(UI.el('p', {
        className: 'ticket-muted',
        textContent: 'لا توجد عروض أسعار حتى الآن.',
      }));
      return;
    }

    const canSelectOffer = _canSelectOffers();

    _offers.forEach((offer) => {
      const card = UI.el('article', { className: 'order-offer-card' });
      const head = UI.el('div', { className: 'order-offer-head' });
      const providerName = String(offer.provider_name || '').trim() || ('مقدم خدمة #' + String(offer.provider || ''));
      const providerHref = _providerProfileHref(offer);

      if (providerHref) {
        const providerLink = UI.el('a', {
          className: 'order-offer-provider',
          href: providerHref,
          title: 'عرض ملف مقدم الخدمة',
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
        textContent: 'السعر: ' + String(offer.price || '-') + ' (SR)',
      }));
      card.appendChild(UI.el('div', {
        className: 'order-offer-line',
        textContent: 'مدة التنفيذ: ' + String(offer.duration_days || '-') + ' يوم',
      }));

      const note = String(offer.note || '').trim();
      if (note) {
        card.appendChild(UI.el('div', {
          className: 'order-offer-note',
          textContent: 'ملاحظة: ' + note,
        }));
      }

      if (canSelectOffer && String(offer.status || '').toLowerCase() === 'pending') {
        const selecting = _acceptingOfferId === Number(offer.id);
        const selectBtn = UI.el('button', {
          type: 'button',
          className: 'btn-primary order-offer-select-btn',
          textContent: selecting ? 'جاري الاختيار...' : 'اختيار هذا العرض',
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
      _setOffersFeedback('لا يمكن اختيار عرض في الحالة الحالية', true);
      return;
    }

    const offerId = Number(offer.id);
    if (!Number.isFinite(offerId) || offerId <= 0) {
      _setOffersFeedback('تعذر اختيار العرض: معرف غير صالح', true);
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
      _setOffersFeedback(_extractError(res, 'تعذّر اختيار العرض'), true);
      _renderOffersSection();
      return;
    }

    _setOffersFeedback('تم اختيار العرض وإسناد الطلب بنجاح', false);
    _loadDetail();
  }

  function _providerProfileHref(offer) {
    const providerId = Number(offer && offer.provider);
    if (!Number.isFinite(providerId) || providerId <= 0) return '';

    const returnTo = window.location.pathname + window.location.search + '#order-offers-section';
    const params = new URLSearchParams();
    params.set('return_to', returnTo);
    params.set('return_label', 'العودة إلى عروض الأسعار');

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
    if (group === 'completed' || group === 'cancelled') return true;
    if (group !== 'in_progress') return false;
    const expected = _asDate(_order.expected_delivery_at);
    if (!expected) return false;
    return Date.now() >= (expected.getTime() + (48 * 60 * 60 * 1000));
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
        return 'تم اختياره';
      case 'rejected':
        return 'مرفوض';
      default:
        return 'بانتظار القرار';
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
    if (t === 'urgent') return 'عاجل';
    if (t === 'competitive') return 'تنافسي';
    if (t === 'normal') return 'عادي';
    return type || '';
  }

  function _formatDate(value) {
    const dt = _asDate(value);
    if (!dt) return '';
    return dt.toLocaleString('ar-SA', {
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
    return dt.toLocaleDateString('ar-SA', {
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    });
  }

  function _formatMoney(value) {
    const num = Number(value);
    if (!Number.isFinite(num)) return String(value || '-');
    return num.toLocaleString('ar-SA') + ' ر.س';
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
    return _statusGroup(_order) === 'new';
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
      tBtn.textContent = _editTitle ? 'إيقاف' : 'تعديل';
    }

    if (dBtn) {
      dBtn.classList.toggle('hidden', !canEdit);
      dBtn.textContent = _editDesc ? 'إيقاف' : 'تعديل';
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
      _setError('العنوان والتفاصيل مطلوبان');
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
      _setError(_extractError(res, 'فشل حفظ التعديلات'));
      return;
    }

    _setError('');
    _order = res.data;
    _render();
  }

  async function _cancelOrder() {
    if (!_order || _actionLoading || _statusGroup(_order) !== 'new') return;
    const reason = String(document.getElementById('order-cancel-reason')?.value || '').trim();
    if (!reason) {
      _setActionFeedback('يرجى كتابة سبب الإلغاء', true);
      return;
    }

    _setActionLoading(true);
    const res = await ApiClient.request('/api/marketplace/requests/' + _requestId + '/cancel/', {
      method: 'POST',
      body: { reason },
    });
    _setActionLoading(false);

    if (!res.ok) {
      _setActionFeedback(_extractError(res, 'تعذر إلغاء الطلب'), true);
      return;
    }

    _setActionFeedback('تم إلغاء الطلب بنجاح', false);
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
      _setActionFeedback(_extractError(res, 'تعذر إعادة فتح الطلب'), true);
      return;
    }

    _setActionFeedback('تمت إعادة فتح الطلب', false);
    _loadDetail();
  }

  async function _decideProviderInputs(approved) {
    if (!_order || _actionLoading) return;
    const note = String(document.getElementById('order-provider-reject-note')?.value || '').trim();
    if (!approved && !note) {
      _setActionFeedback('سبب الرفض مطلوب', true);
      return;
    }

    _setActionLoading(true);
    const res = await ApiClient.request('/api/marketplace/requests/' + _requestId + '/provider-inputs/decision/', {
      method: 'POST',
      body: approved ? { approved: true } : { approved: false, note },
    });
    _setActionLoading(false);

    if (!res.ok) {
      _setActionFeedback(_extractError(res, 'فشل تنفيذ العملية'), true);
      return;
    }

    _setActionFeedback(approved ? 'تم اعتماد التفاصيل وبدأ التنفيذ' : 'تم رفض التفاصيل وإشعار مقدم الخدمة', false);
    _loadDetail();
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
        _setActionFeedback('يرجى تعبئة جميع عناصر التقييم', true);
        const id = 'review-' + key.replace(/_/g, '-');
        const node = document.getElementById(id);
        if (node) node.focus();
        return;
      }
    }

    const comment = String(document.getElementById('review-comment')?.value || '').trim();
    const body = {
      response_speed: Number(fields.response_speed),
      cost_value: Number(fields.cost_value),
      quality: Number(fields.quality),
      credibility: Number(fields.credibility),
      on_time: Number(fields.on_time),
    };
    if (comment) body.comment = comment;

    _setActionLoading(true);
    const res = await ApiClient.request('/api/reviews/requests/' + _requestId + '/review/', {
      method: 'POST',
      body,
    });
    _setActionLoading(false);

    if (!res.ok) {
      _setActionFeedback(_extractError(res, 'تعذر إرسال التقييم'), true);
      return;
    }

    _setActionFeedback('تم إرسال التقييم بنجاح', false);
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

  function _setSaveLoading(loading) {
    const btn = document.getElementById('btn-save-order');
    const txt = document.getElementById('save-order-text');
    const spinner = document.getElementById('save-order-spinner');
    if (btn) btn.disabled = loading;
    if (txt) txt.classList.toggle('hidden', loading);
    if (spinner) spinner.classList.toggle('hidden', !loading);
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();

  return {};
})();
