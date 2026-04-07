/* ===================================================================
   verificationPage.js — Provider verification intake
   Blue badge details + green badge requirements + pricing summary
   =================================================================== */
'use strict';

const VerificationPage = (() => {
  let _badgeType = 'blue';
  let _pricing = null;
  let _plans = [];
  let _provider = null;
  let _requestId = null;
  let _requestCode = '';
  let _greenItems = [];
  let _myRequests = [];
  let _blockingRequestsByBadge = { blue: null, green: null };
  let _accessIssue = null;
  let _toastTimer = null;

  const _blue = {
    approvedSubject: '',
    previews: {
      individual: null,
      business: null,
    },
    files: [],
    filesApplied: false,
  };

  const _green = {
    selectedCodes: new Set(),
    files: [],
    filesApplied: false,
  };

  function _escapeHtml(value) {
    return String(value || '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  function _valueToText(value) {
    if (value == null) return '';
    if (typeof value === 'string') return value.trim();
    if (typeof value === 'number' || typeof value === 'boolean') return String(value);
    if (Array.isArray(value)) {
      return value.map(_valueToText).filter(Boolean).join('، ');
    }
    if (typeof value === 'object') {
      const preferredKeys = ['ar', 'text', 'label', 'title', 'name', 'value', 'display_name', 'message', 'en'];
      for (const key of preferredKeys) {
        if (Object.prototype.hasOwnProperty.call(value, key)) {
          const text = _valueToText(value[key]);
          if (text) return text;
        }
      }
      for (const key of Object.keys(value)) {
        const text = _valueToText(value[key]);
        if (text) return text;
      }
    }
    return String(value);
  }

  function _extractList(payload) {
    if (Array.isArray(payload)) return payload;
    if (payload && Array.isArray(payload.results)) return payload.results;
    if (payload && Array.isArray(payload.items)) return payload.items;
    return [];
  }

  function _safeHtml(value, fallback = '') {
    const text = _valueToText(value) || _valueToText(fallback);
    return _escapeHtml(text);
  }

  function _firstText(value) {
    if (typeof value === 'string' && value.trim()) return value.trim();
    if (typeof value === 'number' && Number.isFinite(value)) return String(value);
    if (Array.isArray(value)) {
      for (const item of value) {
        const text = _firstText(item);
        if (text) return text;
      }
      return '';
    }
    if (value && typeof value === 'object') {
      for (const key of Object.keys(value)) {
        const text = _firstText(value[key]);
        if (text) return text;
      }
    }
    return '';
  }

  function _apiErrorMessage(response, fallback) {
    const data = response && response.data ? response.data : null;
    if (data) {
      const detail = _firstText(data.detail);
      if (detail) return detail;
      const nonField = _firstText(data.non_field_errors);
      if (nonField) return nonField;
      const firstKey = Object.keys(data)[0];
      if (firstKey) {
        const value = _firstText(data[firstKey]);
        if (value) return value;
      }
    }
    return fallback;
  }

  function _apiErrorCode(response) {
    const data = response && response.data ? response.data : null;
    return _firstText(data && data.code);
  }

  function _extractExistingRequest(response) {
    const data = response && response.data ? response.data : null;
    const requestItem = data && data.existing_request && typeof data.existing_request === 'object'
      ? data.existing_request
      : null;
    if (!requestItem) return null;
    return {
      id: Number(_firstText(requestItem.id) || 0) || null,
      code: _firstText(requestItem.code),
      status: _firstText(requestItem.status),
      status_label: _firstText(requestItem.status_label),
      badge_type: _firstText(requestItem.badge_type),
    };
  }

  function _statusLabel(status) {
    const map = {
      new: 'جديد',
      in_review: 'تحت المعالجة',
      rejected: 'مرفوض',
      approved: 'معتمد',
      pending_payment: 'بانتظار الدفع',
      active: 'مفعّل',
      expired: 'منتهي',
    };
    const key = String(status || '').trim().toLowerCase();
    return map[key] || 'قائم';
  }

  function _requestStatusLabel(requestItem) {
    const explicitLabel = _valueToText(requestItem && requestItem.status_label);
    if (explicitLabel) return explicitLabel;
    return _statusLabel(requestItem && requestItem.status);
  }

  function _requestStatusTone(status) {
    const key = String(status || '').trim().toLowerCase();
    if (key === 'rejected') return 'error';
    if (key === 'active') return 'success';
    if (key === 'pending_payment' || key === 'approved') return 'warning';
    if (key === 'expired') return 'muted';
    return 'info';
  }

  function _formatDateTime(value) {
    const raw = String(value || '').trim();
    if (!raw) return 'غير متاح';
    const parsed = new Date(raw);
    if (Number.isNaN(parsed.getTime())) return raw;
    return parsed.toLocaleString('ar-SA', {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    });
  }

  function _requirementDecisionLabel(requirement) {
    const fromApi = _valueToText(requirement && requirement.decision_status_label);
    if (fromApi) return fromApi;
    if (requirement && requirement.is_approved === true) return 'معتمد';
    if (requirement && requirement.is_approved === false) return 'مرفوض';
    return 'بانتظار المراجعة';
  }

  function _requirementDecisionTone(requirement) {
    if (requirement && requirement.is_approved === true) return 'success';
    if (requirement && requirement.is_approved === false) return 'error';
    return 'muted';
  }

  function _requestSummaryCounts(requestItem) {
    const requirements = Array.isArray(requestItem && requestItem.requirements) ? requestItem.requirements : [];
    let approved = 0;
    let rejected = 0;
    let pending = 0;
    requirements.forEach((row) => {
      if (row && row.is_approved === true) {
        approved += 1;
      } else if (row && row.is_approved === false) {
        rejected += 1;
      } else {
        pending += 1;
      }
    });
    return { approved, rejected, pending, total: requirements.length };
  }

  function _renderRequestRequirements(requestItem) {
    const requirements = Array.isArray(requestItem && requestItem.requirements) ? requestItem.requirements : [];
    if (!requirements.length) {
      return '<div class="verify-track-empty-inner">لا توجد بنود مرتبطة بهذا الطلب.</div>';
    }

    return `
      <div class="verify-track-req-table-wrap">
        <table class="verify-track-req-table">
          <thead>
            <tr>
              <th>البند</th>
              <th>الحالة</th>
              <th>ملاحظة المراجعة</th>
            </tr>
          </thead>
          <tbody>
            ${requirements.map((row) => {
              const code = _safeHtml(row && row.code);
              const title = _safeHtml(row && row.title);
              const decisionLabel = _safeHtml(_requirementDecisionLabel(row));
              const decisionTone = _requirementDecisionTone(row);
              const note = _safeHtml(row && row.decision_note, row && row.is_approved === false ? 'لم يتم إضافة سبب حتى الآن.' : '—');
              return `
                <tr>
                  <td>
                    <div class="verify-track-req-title">${title}</div>
                    <small>${code}</small>
                  </td>
                  <td><span class="verify-track-pill is-${decisionTone}">${decisionLabel}</span></td>
                  <td>${note}</td>
                </tr>
              `;
            }).join('')}
          </tbody>
        </table>
      </div>
    `;
  }

  function _renderInvoiceSummary(requestItem) {
    const invoice = requestItem && requestItem.invoice_summary ? requestItem.invoice_summary : null;
    if (!invoice) return '';

    const lines = Array.isArray(invoice.lines) ? invoice.lines : [];
    return `
      <section class="verify-track-section">
        <h4>بيانات الفاتورة</h4>
        <div class="verify-track-mini-grid">
          <div><span>رقم الفاتورة</span><strong>${_safeHtml(invoice.code || `IV${invoice.id || ''}`)}</strong></div>
          <div><span>الحالة</span><strong>${_safeHtml(invoice.status)}</strong></div>
          <div><span>الإجمالي</span><strong>${_safeHtml(invoice.total)} ${_safeHtml(invoice.currency || 'SAR')}</strong></div>
        </div>
        ${lines.length ? `
          <ul class="verify-track-lines">
            ${lines.map((line) => `<li><span>${_safeHtml(line && line.item_code)}</span><strong>${_safeHtml(line && line.title)} - ${_safeHtml(line && line.amount)} ${_safeHtml(invoice.currency || 'SAR')}</strong></li>`).join('')}
          </ul>
        ` : ''}
      </section>
    `;
  }

  function _renderLinkedInquiries(requestItem) {
    const inquiries = Array.isArray(requestItem && requestItem.linked_inquiries) ? requestItem.linked_inquiries : [];
    if (!inquiries.length) return '';
    return `
      <section class="verify-track-section">
        <h4>استفسارات مرتبطة</h4>
        <div class="verify-track-inquiries">
          ${inquiries.map((row) => `<span class="verify-track-pill is-info">${_safeHtml(row && row.ticket_code, row && row.ticket_id)}</span>`).join('')}
        </div>
      </section>
    `;
  }

  function _renderRequestsTimeline() {
    const root = document.getElementById('verifyRequestsTimeline');
    if (!root) return;

    const rows = Array.isArray(_myRequests) ? _myRequests.slice() : [];
    if (!rows.length) {
      root.innerHTML = '<div class="verify-track-empty">لا توجد طلبات توثيق سابقة حتى الآن.</div>';
      return;
    }

    root.innerHTML = rows.map((requestItem) => {
      const requestCode = _safeHtml(requestItem && requestItem.code, `AD${requestItem && requestItem.id || ''}`);
      const statusText = _safeHtml(_requestStatusLabel(requestItem));
      const statusTone = _requestStatusTone(requestItem && requestItem.status);
      const counts = _requestSummaryCounts(requestItem);
      const badgeLabels = Array.isArray(requestItem && requestItem.badge_type_labels) ? requestItem.badge_type_labels : [];
      const rejectReason = _valueToText(requestItem && requestItem.reject_reason);
      const hasRejectedItems = counts.rejected > 0 || !!rejectReason;

      return `
        <details class="verify-track-card${hasRejectedItems ? ' has-rejected' : ''}">
          <summary class="verify-track-summary">
            <div class="verify-track-main">
              <strong>رقم الطلب: ${requestCode}</strong>
              <div class="verify-track-meta">تاريخ الإنشاء: ${_safeHtml(_formatDateTime(requestItem && requestItem.requested_at))}</div>
            </div>
            <span class="verify-track-pill is-${statusTone}">${statusText}</span>
          </summary>

          <div class="verify-track-body">
            <div class="verify-track-mini-grid">
              <div><span>نوع الشارة</span><strong>${_safeHtml(badgeLabels.join('، '), _badgeLabel(requestItem && requestItem.badge_type))}</strong></div>
              <div><span>البنود المعتمدة</span><strong>${counts.approved}</strong></div>
              <div><span>البنود المرفوضة</span><strong>${counts.rejected}</strong></div>
              <div><span>بانتظار المراجعة</span><strong>${counts.pending}</strong></div>
            </div>

            ${rejectReason ? `<div class="verify-track-reject-note"><strong>سبب الرفض العام:</strong><p>${_safeHtml(rejectReason)}</p></div>` : ''}

            <section class="verify-track-section">
              <h4>تفاصيل البنود</h4>
              ${_renderRequestRequirements(requestItem)}
            </section>

            ${_renderInvoiceSummary(requestItem)}
            ${_renderLinkedInquiries(requestItem)}

            <section class="verify-track-section">
              <h4>التسلسل الزمني</h4>
              <ul class="verify-track-lines">
                <li><span>استلام الطلب</span><strong>${_safeHtml(_formatDateTime(requestItem && requestItem.requested_at))}</strong></li>
                <li><span>آخر مراجعة</span><strong>${_safeHtml(_formatDateTime(requestItem && requestItem.reviewed_at))}</strong></li>
                <li><span>تاريخ الاعتماد</span><strong>${_safeHtml(_formatDateTime(requestItem && requestItem.approved_at))}</strong></li>
                <li><span>تاريخ التفعيل</span><strong>${_safeHtml(_formatDateTime(requestItem && requestItem.activated_at))}</strong></li>
              </ul>
            </section>
          </div>
        </details>
      `;
    }).join('');
  }

  function _badgeLabel(badgeType) {
    return String(badgeType || '').trim().toLowerCase() === 'green' ? 'الشارة الخضراء' : 'الشارة الزرقاء';
  }

  function _requestBadgeTypes(requestItem) {
    if (!requestItem || typeof requestItem !== 'object') return [];
    if (Array.isArray(requestItem.badge_types) && requestItem.badge_types.length) {
      return requestItem.badge_types
        .map((item) => String(item || '').trim().toLowerCase())
        .filter((item) => item === 'blue' || item === 'green');
    }
    const badgeType = String(requestItem.badge_type || '').trim().toLowerCase();
    return badgeType === 'blue' || badgeType === 'green' ? [badgeType] : [];
  }

  function _buildBlockingRequestsByBadge(requests) {
    const blockingStatuses = new Set(['new', 'in_review', 'approved', 'pending_payment', 'active']);
    const nextMap = { blue: null, green: null };
    (Array.isArray(requests) ? requests : []).forEach((requestItem) => {
      const status = String(requestItem && requestItem.status || '').trim().toLowerCase();
      if (!blockingStatuses.has(status)) return;
      _requestBadgeTypes(requestItem).forEach((badgeType) => {
        if (!nextMap[badgeType]) nextMap[badgeType] = requestItem;
      });
    });
    return nextMap;
  }

  function _currentBlockingRequest() {
    return _blockingRequestsByBadge[_badgeType] || null;
  }

  function _showToast(message, type) {
    const toast = document.getElementById('verifyToast');
    if (!toast) {
      window.alert(message || '');
      return;
    }
    toast.textContent = message || '';
    toast.classList.remove('show', 'success', 'error', 'warning');
    if (type) toast.classList.add(type);
    requestAnimationFrame(() => toast.classList.add('show'));
    window.clearTimeout(_toastTimer);
    _toastTimer = window.setTimeout(() => toast.classList.remove('show'), 3200);
  }

  function _showStatusNotice(title, body, options = {}) {
    const notice = document.getElementById('verifyStatusNotice');
    const titleNode = document.getElementById('verifyStatusNoticeTitle');
    const bodyNode = document.getElementById('verifyStatusNoticeBody');
    const action = document.getElementById('verifyStatusNoticeAction');
    if (!notice || !titleNode || !bodyNode || !action) return;

    titleNode.textContent = title || 'تنبيه';
    bodyNode.textContent = body || '';
    notice.classList.remove('hidden', 'is-error');
    if (options.isError) notice.classList.add('is-error');

    if (options.actionHref && options.actionLabel) {
      action.href = options.actionHref;
      action.textContent = options.actionLabel;
      action.classList.remove('hidden');
    } else {
      action.classList.add('hidden');
      action.removeAttribute('href');
    }
  }

  function _hideStatusNotice() {
    const notice = document.getElementById('verifyStatusNotice');
    if (!notice) return;
    notice.classList.add('hidden');
    notice.classList.remove('is-error');
  }

  function _accessIssueAction(issue) {
    const code = String(issue && issue.code || '').trim();
    const message = String(issue && issue.message || '').trim();
    if (code === 'verification_subscription_required' || code === 'subscription_required') {
      return { href: '/plans/', label: 'تفعيل الاشتراك' };
    }
    if (code === 'provider_profile_required') {
      return { href: '/provider-register/', label: 'استكمال الملف' };
    }
    if (code === 'provider_required') {
      return { href: '/provider-register/', label: 'التسجيل كمزود' };
    }
    if (code === 'authentication_required') {
      return { href: '/login/?next=/verification/', label: 'تسجيل الدخول' };
    }
    if (message.includes('ملف مقدم الخدمة')) {
      return { href: '/provider-register/', label: 'استكمال الملف' };
    }
    if (message.includes('مقدمي الخدمات')) {
      return { href: '/provider-register/', label: 'التسجيل كمزود' };
    }
    if (message.includes('تسجيل الدخول')) {
      return { href: '/login/?next=/verification/', label: 'تسجيل الدخول' };
    }
    return null;
  }

  function _setAccessIssue(message, code) {
    if (!message) return;
    _accessIssue = { message, code: String(code || '').trim() };
  }

  function _setActionButtonsDisabled(disabled) {
    ['verifyToSummaryBtn', 'verifySubmitBtn'].forEach((id) => {
      const button = document.getElementById(id);
      if (!button) return;
      button.disabled = !!disabled;
      button.title = disabled ? 'الإرسال غير متاح حاليًا حتى معالجة التنبيه الظاهر.' : '';
    });
  }

  function _isSuccessStepVisible() {
    const successStep = document.getElementById('verifySuccessStep');
    return !!(successStep && !successStep.classList.contains('hidden'));
  }

  function _refreshStatusState() {
    if (_isSuccessStepVisible()) {
      _hideStatusNotice();
      _setActionButtonsDisabled(false);
      return;
    }

    if (_accessIssue && _accessIssue.message) {
      const action = _accessIssueAction(_accessIssue);
      _showStatusNotice(
        'التوثيق غير متاح حاليًا',
        _accessIssue.message,
        {
          isError: true,
          actionHref: action && action.href,
          actionLabel: action && action.label,
        },
      );
      _setActionButtonsDisabled(true);
      return;
    }

    const existingRequest = _currentBlockingRequest();
    if (existingRequest) {
      const code = String(existingRequest.code || '').trim();
      const statusLabel = String(existingRequest.status_label || _statusLabel(existingRequest.status)).trim();
      _showStatusNotice(
        `يوجد طلب قائم لنفس النوع`,
        `${_badgeLabel(_badgeType)} مرتبطة بطلب قائم${code ? ` برقم ${code}` : ''} وحالته ${statusLabel}. أكمل الطلب الحالي قبل إنشاء طلب جديد.`,
      );
      _setActionButtonsDisabled(true);
      return;
    }

    _hideStatusNotice();
    _setActionButtonsDisabled(false);
  }

  function _rememberBlockingRequest(requestItem, fallbackBadgeType) {
    if (!requestItem || typeof requestItem !== 'object') return;
    const badgeTypes = _requestBadgeTypes(requestItem);
    if (!badgeTypes.length && fallbackBadgeType) {
      const normalized = String(fallbackBadgeType || '').trim().toLowerCase();
      if (normalized === 'blue' || normalized === 'green') badgeTypes.push(normalized);
    }
    badgeTypes.forEach((badgeType) => {
      _blockingRequestsByBadge[badgeType] = Object.assign({ status: 'new' }, requestItem, { badge_type: badgeType });
    });
  }

  function _ensureSubmissionAllowed() {
    if (_accessIssue && _accessIssue.message) {
      _showToast(_accessIssue.message, 'error');
      _refreshStatusState();
      return false;
    }
    const existingRequest = _currentBlockingRequest();
    if (existingRequest) {
      const code = String(existingRequest.code || '').trim();
      const statusLabel = String(existingRequest.status_label || _statusLabel(existingRequest.status)).trim();
      _showToast(
        `${_badgeLabel(_badgeType)} لها طلب قائم${code ? ` برقم ${code}` : ''} وحالته ${statusLabel}. أكمل الطلب الحالي أولًا.`,
        'warning',
      );
      _refreshStatusState();
      return false;
    }
    return true;
  }

  function _createRequestErrorMessage(response, badgeType, fallback) {
    const code = _apiErrorCode(response);
    const existingRequest = _extractExistingRequest(response);
    if (code === 'verification_request_exists' && existingRequest) {
      _rememberBlockingRequest(existingRequest, existingRequest.badge_type || badgeType);
      _refreshStatusState();
      const requestCode = String(existingRequest.code || '').trim();
      const statusLabel = String(existingRequest.status_label || _statusLabel(existingRequest.status)).trim();
      return `${_badgeLabel(existingRequest.badge_type || badgeType)} لها طلب قائم${requestCode ? ` برقم ${requestCode}` : ''} وحالته ${statusLabel}. أكمل الطلب الحالي قبل إنشاء طلب جديد.`;
    }
    if (code === 'verification_blue_profile_required') {
      return 'أكمل بيانات الشارة الزرقاء واعتمد الاسم المسترجع ثم أعد الإرسال.';
    }
    if (code === 'verification_badge_type_required') {
      return 'اختر نوع الشارة وأكمل البنود المطلوبة قبل الإرسال.';
    }
    if (code === 'provider_profile_required') {
      _setAccessIssue('يجب استكمال ملف مقدم الخدمة أولًا قبل طلب التوثيق.', code);
      _refreshStatusState();
      return 'يجب استكمال ملف مقدم الخدمة أولًا قبل طلب التوثيق.';
    }
    if (code === 'provider_required') {
      _setAccessIssue('هذه الخدمة متاحة فقط لمقدمي الخدمات المسجلين.', code);
      _refreshStatusState();
      return 'هذه الخدمة متاحة فقط لمقدمي الخدمات المسجلين.';
    }
    if (code === 'verification_subscription_required') {
      _setAccessIssue('يتطلب طلب التوثيق اشتراكًا فعالًا في الباقة الأساسية أو الريادية أو الاحترافية.', code);
      _refreshStatusState();
      return 'يتطلب طلب التوثيق اشتراكًا فعالًا في الباقة الأساسية أو الريادية أو الاحترافية.';
    }
    if (response && response.status === 0) {
      return 'تعذر الاتصال بالخادم حاليًا. تحقق من الشبكة ثم أعد المحاولة.';
    }
    return _apiErrorMessage(response, fallback);
  }

  async function init() {
    if (!Auth.isLoggedIn()) {
      _showAuthGate();
      return;
    }

    _showPage();
    _bindStaticEvents();

    await Promise.all([
      _loadProviderIdentity(),
      _loadPricing(),
      _loadPlans(),
      _loadGreenRequirements(),
      _loadMyRequests(),
    ]);

    _renderProviderIdentity();
    _renderPricingStrip();
    _renderGreenRequirements();
    _renderGreenFiles();
    _renderBlueFiles();
    _renderBluePreviews();
    _setBadgeType('blue');
    _renderRequestsTimeline();

    if (_accessIssue && _accessIssue.message) {
      _showToast(_accessIssue.message, 'error');
    }
  }

  function _showAuthGate() {
    const gate = document.getElementById('auth-gate');
    if (gate) gate.classList.remove('hidden');
  }

  function _showPage() {
    const content = document.getElementById('verify-content');
    if (content) content.classList.remove('hidden');
  }

  async function _loadProviderIdentity() {
    const [meResponse, providerResponse] = await Promise.all([
      ApiClient.get('/api/accounts/me/?mode=provider'),
      ApiClient.get('/api/providers/me/profile/'),
    ]);

    if (meResponse && !meResponse.ok && (meResponse.status === 401 || meResponse.status === 403)) {
      _setAccessIssue(_apiErrorMessage(meResponse, 'تعذر التحقق من أهلية الحساب للتوثيق.'), _apiErrorCode(meResponse));
    }
    if (providerResponse && !providerResponse.ok && (providerResponse.status === 401 || providerResponse.status === 403)) {
      _setAccessIssue(_apiErrorMessage(providerResponse, 'تعذر تحميل ملف مقدم الخدمة.'), _apiErrorCode(providerResponse));
    }

    const me = meResponse && meResponse.ok ? meResponse.data : null;
    const providerProfile = providerResponse && providerResponse.ok ? providerResponse.data : null;
    const fullName = [me && me.first_name, me && me.last_name].filter(Boolean).join(' ').trim();
    const displayName = String((providerProfile && providerProfile.display_name) || '').trim();
    const username = String((me && me.username) || '').trim();
    const phone = String((me && me.phone) || '').trim();

    _provider = {
      displayName: displayName || fullName || username || phone || 'مزود خدمة',
      username: username || phone || 'provider',
    };
  }

  async function _loadPricing() {
    const response = await ApiClient.get('/api/verification/pricing/my/');
    if (response && response.ok && response.data) {
      _pricing = response.data;
      if (_pricing.has_active_subscription !== true) {
        _setAccessIssue(
          'يتطلب التوثيق اشتراكًا فعالًا في الباقة الأساسية أو الريادية أو الاحترافية. فعّل الاشتراك أولًا ثم أعد المحاولة.',
          'verification_subscription_required',
        );
      }
      return;
    }
    if (response && (response.status === 401 || response.status === 403)) {
      _setAccessIssue(_apiErrorMessage(response, 'التوثيق غير متاح لهذا الحساب حاليًا.'), _apiErrorCode(response));
    }
  }

  async function _loadPlans() {
    const response = await ApiClient.get('/api/subscriptions/plans/');
    if (response && response.ok) {
      _plans = _extractList(response.data);
    }
  }

  async function _loadGreenRequirements() {
    const response = await ApiClient.get('/api/public/badges/green/');
    if (response && response.ok && response.data) {
      _greenItems = Array.isArray(response.data.requirements) ? response.data.requirements : [];
    }
  }

  async function _loadMyRequests() {
    const response = await ApiClient.get('/api/verification/requests/my/');
    if (response && response.ok) {
      _myRequests = _extractList(response.data);
      _blockingRequestsByBadge = _buildBlockingRequestsByBadge(_myRequests);
      _renderRequestsTimeline();
      return;
    }
    if (response && (response.status === 401 || response.status === 403)) {
      _setAccessIssue(_apiErrorMessage(response, 'تعذر التحقق من طلبات التوثيق الحالية.'), _apiErrorCode(response));
    }
    _renderRequestsTimeline();
  }

  function _bindStaticEvents() {
    const backBtn = document.getElementById('verifyBackBtn');
    if (backBtn) backBtn.addEventListener('click', () => { window.history.back(); });

    const cancelBtn = document.getElementById('verifyDetailCancelBtn');
    if (cancelBtn) cancelBtn.addEventListener('click', () => { window.history.back(); });

    const toSummaryBtn = document.getElementById('verifyToSummaryBtn');
    if (toSummaryBtn) toSummaryBtn.addEventListener('click', _goToSummary);

    const summaryCancelBtn = document.getElementById('verifySummaryCancelBtn');
    if (summaryCancelBtn) summaryCancelBtn.addEventListener('click', _showDetailsStep);

    const submitBtn = document.getElementById('verifySubmitBtn');
    if (submitBtn) submitBtn.addEventListener('click', _submit);

    const successCloseBtn = document.getElementById('verifySuccessCloseBtn');
    if (successCloseBtn) {
      successCloseBtn.addEventListener('click', () => {
        window.location.href = '/verification/';
      });
    }

    const trackingRefreshBtn = document.getElementById('verifyTrackingRefreshBtn');
    if (trackingRefreshBtn) {
      trackingRefreshBtn.addEventListener('click', async () => {
        const originalText = trackingRefreshBtn.textContent;
        trackingRefreshBtn.disabled = true;
        trackingRefreshBtn.textContent = 'جاري التحديث...';
        try {
          await _loadMyRequests();
          _showToast('تم تحديث بيانات متابعة الطلبات.', 'success');
        } catch (_err) {
          _showToast('تعذر تحديث بيانات المتابعة حاليًا.', 'error');
        } finally {
          trackingRefreshBtn.disabled = false;
          trackingRefreshBtn.textContent = originalText;
        }
      });
    }

    document.querySelectorAll('.verify-badge-tab').forEach((button) => {
      button.addEventListener('click', () => _setBadgeType(button.dataset.badgeType || 'blue'));
    });

    document.querySelectorAll('input[name="verify-blue-subject"]').forEach((input) => {
      input.addEventListener('change', () => {
        if (input.checked) {
          _highlightBlueSubject(input.value);
        }
      });
    });

    _bindBlueSubjectActions('individual');
    _bindBlueSubjectActions('business');
    _bindBlueFiles();
    _bindGreenFiles();
  }

  function _bindBlueSubjectActions(subjectType) {
    const normalized = subjectType === 'business' ? 'Business' : 'Individual';
    const previewBtn = document.getElementById(`blue${normalized}PreviewBtn`);
    const resetBtn = document.getElementById(`blue${normalized}ResetBtn`);
    const approveBtn = document.getElementById(`blue${normalized}ApproveBtn`);
    const rejectBtn = document.getElementById(`blue${normalized}RejectBtn`);

    if (previewBtn) {
      previewBtn.addEventListener('click', () => _previewBlueSubject(subjectType));
    }
    if (resetBtn) {
      resetBtn.addEventListener('click', () => _resetBlueSubject(subjectType));
    }
    if (approveBtn) {
      approveBtn.addEventListener('click', () => _approveBlueSubject(subjectType));
    }
    if (rejectBtn) {
      rejectBtn.addEventListener('click', () => _rejectBlueSubject(subjectType));
    }
  }

  function _bindBlueFiles() {
    const toggle = document.getElementById('blueExtraDocsToggle');
    const input = document.getElementById('blueAttachmentsInput');
    const applyBtn = document.getElementById('blueFilesApplyBtn');
    const clearBtn = document.getElementById('blueFilesClearBtn');

    if (toggle) {
      toggle.addEventListener('change', () => {
        if (!toggle.checked) {
          _blue.files = [];
          _blue.filesApplied = false;
          if (input) input.value = '';
        }
        _renderBlueFiles();
      });
    }

    if (input) {
      input.addEventListener('change', () => {
        _blue.files = Array.from(input.files || []);
        _blue.filesApplied = false;
        _renderBlueFiles();
      });
    }

    if (applyBtn) {
      applyBtn.addEventListener('click', () => {
        if (!_isBlueAttachmentsEnabled()) {
          _showToast('فعّل خيار المرفقات أولًا ثم اختر الملفات الرسمية المطلوبة.', 'warning');
          return;
        }
        if (!_blue.files.length) {
          _showToast('أرفق ملفًا رسميًا واحدًا على الأقل قبل اعتماد المرفقات.', 'warning');
          return;
        }
        _blue.filesApplied = true;
        _renderBlueFiles();
        _showToast(`تم تجهيز ${_blue.files.length} ملف/ملفات للشارة الزرقاء.`, 'success');
      });
    }

    if (clearBtn) {
      clearBtn.addEventListener('click', () => {
        _blue.files = [];
        _blue.filesApplied = false;
        if (toggle) toggle.checked = false;
        if (input) input.value = '';
        _renderBlueFiles();
      });
    }
  }

  function _bindGreenFiles() {
    const input = document.getElementById('greenAttachmentsInput');
    const applyBtn = document.getElementById('greenFilesApplyBtn');
    const clearBtn = document.getElementById('greenFilesClearBtn');

    if (input) {
      input.addEventListener('change', () => {
        _green.files = Array.from(input.files || []);
        _green.filesApplied = false;
        _renderGreenFiles();
      });
    }

    if (applyBtn) {
      applyBtn.addEventListener('click', () => {
        if (!_green.files.length) {
          _showToast('أرفق ملفًا داعمًا واحدًا على الأقل قبل اعتماد مرفقات الشارة الخضراء.', 'warning');
          return;
        }
        _green.filesApplied = true;
        _renderGreenFiles();
        _showToast(`تم تجهيز ${_green.files.length} ملف/ملفات للشارة الخضراء.`, 'success');
      });
    }

    if (clearBtn) {
      clearBtn.addEventListener('click', () => {
        _green.files = [];
        _green.filesApplied = false;
        if (input) input.value = '';
        _renderGreenFiles();
      });
    }
  }

  function _renderProviderIdentity() {
    const nameNode = document.getElementById('verify-provider-name');
    const handleNode = document.getElementById('verify-provider-handle');
    const summaryHandleNode = document.getElementById('verifySummaryProviderHandle');
    if (nameNode) nameNode.textContent = (_provider && _provider.displayName) || 'مزود خدمة';
    const handle = '@' + (((_provider && _provider.username) || 'provider').replace(/^@+/, ''));
    if (handleNode) handleNode.textContent = handle;
    if (summaryHandleNode) summaryHandleNode.textContent = handle;
  }

  function _setBadgeType(nextType) {
    _badgeType = nextType === 'green' ? 'green' : 'blue';

    document.querySelectorAll('.verify-badge-tab').forEach((button) => {
      button.classList.toggle('is-active', button.dataset.badgeType === _badgeType);
    });

    const bluePanel = document.getElementById('verifyBluePanel');
    const greenPanel = document.getElementById('verifyGreenPanel');
    if (bluePanel) bluePanel.classList.toggle('is-active', _badgeType === 'blue');
    if (greenPanel) greenPanel.classList.toggle('is-active', _badgeType === 'green');

    _showDetailsStep();
    _refreshStatusState();
  }

  function _showDetailsStep() {
    const detailBoard = document.getElementById('verifyDetailBoard');
    const detailActions = document.getElementById('verifyDetailActions');
    const summaryStep = document.getElementById('verifySummaryStep');
    const successStep = document.getElementById('verifySuccessStep');
    const pricingStrip = document.getElementById('verifyPricingStrip');

    if (detailBoard) detailBoard.classList.remove('hidden');
    if (detailActions) detailActions.classList.remove('hidden');
    if (summaryStep) summaryStep.classList.add('hidden');
    if (successStep) successStep.classList.add('hidden');
    if (pricingStrip && _pricing && _pricing.has_active_subscription === true) {
      pricingStrip.classList.remove('hidden');
    }
  }

  function _showSuccessStep(requestCode, note) {
    const detailBoard = document.getElementById('verifyDetailBoard');
    const detailActions = document.getElementById('verifyDetailActions');
    const summaryStep = document.getElementById('verifySummaryStep');
    const successStep = document.getElementById('verifySuccessStep');
    const successNote = document.getElementById('verifySuccessNote');
    const successCode = document.getElementById('verifySuccessRequestCode');
    const pricingStrip = document.getElementById('verifyPricingStrip');

    if (detailBoard) detailBoard.classList.add('hidden');
    if (detailActions) detailActions.classList.add('hidden');
    if (summaryStep) summaryStep.classList.add('hidden');
    if (successStep) successStep.classList.remove('hidden');
    if (pricingStrip) pricingStrip.classList.add('hidden');
    if (successCode) successCode.textContent = requestCode || _requestCode || 'AD0001';
    if (successNote) {
      successNote.textContent = note || 'سيتم التواصل معكم بعد عملية التدقيق المعتمدة من منصة المختص.';
    }
    _hideStatusNotice();
  }

  function _renderPricingStrip() {
    const strip = document.getElementById('verifyPricingStrip');
    const grid = document.getElementById('verifyPlansGrid');
    const note = document.getElementById('verifyCurrentPlanNote');

    if (!strip || !grid) return;

    if (!_pricing || _pricing.has_active_subscription !== true || !_plans.length) {
      strip.classList.add('hidden');
      return;
    }

    const orderMap = { basic: 1, riyadi: 2, pioneer: 2, pro: 3, professional: 3 };
    const plans = _plans
      .filter((item) => item && item.provider_offer)
      .slice()
      .sort((a, b) => {
        const aKey = String(a.tier || a.code || '').toLowerCase();
        const bKey = String(b.tier || b.code || '').toLowerCase();
        return (orderMap[aKey] || 50) - (orderMap[bKey] || 50);
      });

    grid.innerHTML = plans.map((item) => {
      const offer = item.provider_offer || {};
      const isCurrent = offer.cta && offer.cta.state === 'current';
      const description = _valueToText(offer.description);
      const featureBullets = Array.isArray(offer.feature_bullets)
        ? offer.feature_bullets.map((entry) => _valueToText(entry)).filter(Boolean)
        : [];
      const compareRows = Array.isArray(offer.card_rows)
        ? offer.card_rows.filter((row) => {
          const key = String(row && row.key || '').trim();
          return !['annual_price', 'verification_blue', 'verification_green'].includes(key);
        })
        : [];
      return `
        <article class="verify-plan-card ${isCurrent ? 'is-current' : ''}">
          <div class="verify-plan-card-head">
            <div class="verify-plan-card-title-wrap">
              <strong>${_safeHtml(offer.plan_name || item.title || item.code || 'باقة')}</strong>
              <span>${_safeHtml(offer.billing_cycle_label || 'سنوي')}</span>
            </div>
            <span class="verify-plan-chip">${_safeHtml((offer.cta && offer.cta.label) || 'متاح')}</span>
          </div>
          ${description ? `<p class="verify-plan-desc">${_safeHtml(description)}</p>` : ''}
          <div class="verify-plan-price-row verify-plan-price-row-main">
            <span>سعر الباقة</span>
            <strong>${_safeHtml(offer.annual_price_label || offer.annual_price || 'مجانية')}</strong>
          </div>
          <div class="verify-plan-price-row">
            <span>التوثيق الأزرق</span>
            <strong>${_safeHtml(offer.verification_blue_label || `${offer.verification_blue_amount || '0.00'} ر.س`)}</strong>
          </div>
          <div class="verify-plan-price-row">
            <span>التوثيق الأخضر</span>
            <strong>${_safeHtml(offer.verification_green_label || `${offer.verification_green_amount || '0.00'} ر.س`)}</strong>
          </div>
          ${featureBullets.length ? `
            <div class="verify-plan-bullets">
              ${featureBullets.map((entry) => `<span class="verify-plan-bullet">${_safeHtml(entry)}</span>`).join('')}
            </div>
          ` : ''}
          ${compareRows.length ? `
            <div class="verify-plan-meta">
              ${compareRows.map((row) => `
                <div class="verify-plan-meta-row">
                  <span>${_safeHtml(row && row.label)}</span>
                  <strong>${_safeHtml(row && row.value)}</strong>
                </div>
              `).join('')}
            </div>
          ` : ''}
          <div class="verify-plan-foot">${_safeHtml(offer.verification_effect_label || '')}</div>
        </article>
      `;
    }).join('');

    if (note) {
      note.textContent = _pricing.tier_label
        ? `أنت مشترك حاليًا في باقة ${_pricing.tier_label}، والأسعار التالية موضحة بحسب الباقات المتاحة.`
        : 'الأسعار التالية موضحة بحسب الباقات المتاحة لمزودي الخدمة.';
    }
    strip.classList.remove('hidden');
  }

  function _renderBluePreviews() {
    _renderBlueSubjectPreview('individual');
    _renderBlueSubjectPreview('business');
    _highlightBlueSubject(_blue.approvedSubject || _selectedBlueSubject());
  }

  function _renderBlueSubjectPreview(subjectType) {
    const normalized = subjectType === 'business' ? 'Business' : 'Individual';
    const resultCard = document.getElementById(`blue${normalized}Result`);
    const valueNode = document.getElementById(`blue${normalized}ResultValue`);
    const card = document.querySelector(`.verify-lookup-card[data-subject-type="${subjectType}"]`);
    const preview = _blue.previews[subjectType];
    const isApproved = _blue.approvedSubject === subjectType;

    if (resultCard) resultCard.classList.toggle('hidden', !preview);
    if (valueNode) valueNode.textContent = preview && preview.verified_name ? preview.verified_name : '-';
    if (card) card.classList.toggle('is-approved', isApproved);
  }

  function _highlightBlueSubject(subjectType) {
    document.querySelectorAll('.verify-lookup-card[data-subject-type]').forEach((card) => {
      card.classList.toggle('is-current', card.dataset.subjectType === subjectType);
    });
  }

  async function _previewBlueSubject(subjectType) {
    const payload = _readBlueSubjectFields(subjectType);
    if (!payload.official_number || !payload.official_date) {
      _showToast(
        subjectType === 'business'
          ? 'أدخل رقم السجل التجاري وتاريخه قبل التحقق.'
          : 'أدخل رقم الهوية أو الإقامة وتاريخ الميلاد قبل التحقق.',
        'warning',
      );
      return;
    }

    const response = await ApiClient.request('/api/verification/blue-preview/', {
      method: 'POST',
      body: payload,
    });
    if (!response.ok) {
      _showToast(_apiErrorMessage(response, 'تعذر التحقق من البيانات الحالية.'), 'error');
      return;
    }

    _blue.previews[subjectType] = response.data || null;
    if (_blue.approvedSubject === subjectType) {
      _blue.approvedSubject = '';
    }
    _renderBluePreviews();
  }

  function _approveBlueSubject(subjectType) {
    if (!_blue.previews[subjectType]) {
      _showToast('نفّذ التحقق أولًا ثم اعتمد الاسم المسترجع.', 'warning');
      return;
    }
    _blue.approvedSubject = subjectType;
    _renderBluePreviews();
    _showToast('تم اعتماد الاسم المسترجع ويمكنك متابعة الطلب.', 'success');
  }

  function _rejectBlueSubject(subjectType) {
    if (_blue.approvedSubject === subjectType) {
      _blue.approvedSubject = '';
    }
    _blue.previews[subjectType] = null;
    _renderBluePreviews();
  }

  function _resetBlueSubject(subjectType) {
    const normalized = subjectType === 'business' ? 'Business' : 'Individual';
    const numberInput = document.getElementById(`blue${normalized}Number`);
    const dateInput = document.getElementById(`blue${normalized}Date`);
    if (numberInput) numberInput.value = '';
    if (dateInput) dateInput.value = '';
    _rejectBlueSubject(subjectType);
  }

  function _readBlueSubjectFields(subjectType) {
    const normalized = subjectType === 'business' ? 'Business' : 'Individual';
    const numberInput = document.getElementById(`blue${normalized}Number`);
    const dateInput = document.getElementById(`blue${normalized}Date`);
    return {
      subject_type: subjectType,
      official_number: String(numberInput && numberInput.value || '').trim(),
      official_date: String(dateInput && dateInput.value || '').trim(),
    };
  }

  function _selectedBlueSubject() {
    const input = document.querySelector('input[name="verify-blue-subject"]:checked');
    return input ? input.value : 'individual';
  }

  function _isBlueAttachmentsEnabled() {
    const toggle = document.getElementById('blueExtraDocsToggle');
    return !!(toggle && toggle.checked);
  }

  function _renderBlueFiles() {
    const body = document.getElementById('blueAttachmentsBody');
    const list = document.getElementById('blueFileList');
    const feedback = document.getElementById('blueFilesFeedback');
    const enabled = _isBlueAttachmentsEnabled();

    if (body) body.classList.toggle('hidden', !enabled);
    if (list) {
      list.innerHTML = _blue.files.length
        ? _blue.files.map((file) => `<span class="verify-file-chip">${_escapeHtml(file.name)}</span>`).join('')
        : '<span class="verify-file-empty">لا توجد ملفات مضافة.</span>';
    }
    if (feedback) {
      if (!enabled) {
        feedback.textContent = 'فعّل خيار المرفقات إذا رغبت بإرفاق مستندات رسمية.';
        feedback.classList.remove('is-success');
      } else if (_blue.filesApplied && _blue.files.length) {
        feedback.textContent = `تم تجهيز ${_blue.files.length} ملف/ملفات للرفع مع الطلب.`;
        feedback.classList.add('is-success');
      } else if (_blue.files.length) {
        feedback.textContent = 'اضغط تقديم لاعتماد المرفقات ضمن الطلب.';
        feedback.classList.remove('is-success');
      } else {
        feedback.textContent = 'أرفق ملفًا رسميًا واحدًا على الأقل.';
        feedback.classList.remove('is-success');
      }
    }
  }

  function _renderGreenRequirements() {
    const root = document.getElementById('verifyGreenRequirements');
    if (!root) return;

    if (!_greenItems.length) {
      root.innerHTML = '<div class="verify-green-empty">تعذر تحميل بنود الشارة الخضراء حاليًا.</div>';
      return;
    }

    root.innerHTML = _greenItems.map((item) => {
      const code = String(item.code || '').trim().toUpperCase();
      return `
        <label class="verify-green-option" data-code="${_escapeHtml(code)}">
          <span class="verify-green-option-main">
            <input type="checkbox" class="verify-green-toggle" data-code="${_escapeHtml(code)}">
            <span class="verify-green-option-indicator" aria-hidden="true"></span>
            <span class="verify-green-option-text">${_escapeHtml(item.title || code)}</span>
          </span>
        </label>
      `;
    }).join('');

    root.querySelectorAll('.verify-green-toggle').forEach((input) => {
      input.addEventListener('change', () => {
        const code = String(input.dataset.code || '').trim().toUpperCase();
        const row = input.closest('.verify-green-option');
        if (input.checked) {
          _green.selectedCodes.add(code);
          if (row) row.classList.add('is-selected');
        } else {
          _green.selectedCodes.delete(code);
          if (row) row.classList.remove('is-selected');
        }
      });
    });
  }

  function _renderGreenFiles() {
    const list = document.getElementById('greenFileList');
    const feedback = document.getElementById('greenFilesFeedback');

    if (list) {
      list.innerHTML = _green.files.length
        ? _green.files.map((file) => `<span class="verify-file-chip">${_escapeHtml(file.name)}</span>`).join('')
        : '<span class="verify-file-empty">لا توجد ملفات مضافة.</span>';
    }

    if (feedback) {
      if (_green.filesApplied && _green.files.length) {
        feedback.textContent = `تم تجهيز ${_green.files.length} ملف/ملفات داعمة للرفع مع الطلب.`;
        feedback.classList.add('is-success');
      } else if (_green.files.length) {
        feedback.textContent = 'اضغط تقديم لاعتماد المرفقات ضمن طلب الشارة الخضراء.';
        feedback.classList.remove('is-success');
      } else {
        feedback.textContent = 'أرفق ملفًا داعمًا واحدًا على الأقل لطلب الشارة الخضراء.';
        feedback.classList.remove('is-success');
      }
    }
  }

  function _priceEntry(badgeType) {
    return _pricing && _pricing.prices ? (_pricing.prices[badgeType] || null) : null;
  }

  function _priceAmount(badgeType) {
    const entry = _priceEntry(badgeType);
    const raw = entry && (entry.final_amount || entry.amount);
    return String(raw || '0.00');
  }

  function _isFree(badgeType) {
    const entry = _priceEntry(badgeType);
    return !!(entry && entry.is_free);
  }

  function _priceLabel(badgeType) {
    return _isFree(badgeType)
      ? 'مجاني ضمن الباقة'
      : `${_priceAmount(badgeType)} ر.س`;
  }

  function _pricingNote(badgeType) {
    const tierLabel = _pricing && _pricing.tier_label ? _pricing.tier_label : '';
    const note = _pricing && _pricing.price_note ? _pricing.price_note : 'الرسوم النهائية تتحدد حسب باقة المزود عند اعتماد الطلب.';
    if (_isFree(badgeType)) {
      return tierLabel
        ? `هذا الطلب مشمول مجانًا ضمن باقة ${tierLabel}. ${note}`
        : `هذا الطلب مشمول مجانًا. ${note}`;
    }
    return tierLabel
      ? `الرسوم الحالية لهذا الطلب وفق باقة ${tierLabel}: ${_priceAmount(badgeType)} ر.س. ${note}`
      : `الرسوم الحالية لهذا الطلب: ${_priceAmount(badgeType)} ر.س. ${note}`;
  }

  function _validatedBlueSubmission() {
    const subjectType = _blue.approvedSubject;
    if (!subjectType) {
      _showToast('اعتمد اسم العميل أو اسم المنشأة أولًا قبل الانتقال للملخص.', 'warning');
      return null;
    }
    if (!_blue.filesApplied || !_blue.files.length) {
      _showToast('أرفق المستندات الرسمية ثم اضغط "تقديم" داخل قسم المرفقات قبل الإرسال.', 'warning');
      return null;
    }

    const preview = _blue.previews[subjectType];
    const fields = _readBlueSubjectFields(subjectType);
    if (!preview || !fields.official_number || !fields.official_date) {
      _showToast('بيانات الشارة الزرقاء غير مكتملة. راجع حقول التحقق ثم أعد المحاولة.', 'warning');
      return null;
    }

    return {
      subject_type: subjectType,
      official_number: fields.official_number,
      official_date: fields.official_date,
      verified_name: preview.verified_name,
      is_name_approved: true,
      files: _blue.files.slice(),
    };
  }

  function _validatedGreenSubmission() {
    const codes = Array.from(_green.selectedCodes);
    if (!codes.length) {
      _showToast('اختر بندًا واحدًا على الأقل من بنود الشارة الخضراء قبل المتابعة.', 'warning');
      return null;
    }

    if (!_green.filesApplied || !_green.files.length) {
      _showToast('أرفق المستندات الداعمة ثم اضغط "تقديم" داخل قسم المرفقات قبل الإرسال.', 'warning');
      return null;
    }

    const rows = [];
    for (const code of codes) {
      const definition = _greenItems.find((item) => String(item.code || '').trim().toUpperCase() === code);
      rows.push({
        code,
        title: definition && definition.title ? definition.title : code,
      });
    }
    return {
      items: rows,
      files: _green.files.slice(),
    };
  }

  function _goToSummary() {
    const rowsRoot = document.getElementById('verifySummaryRows');
    const detailBoard = document.getElementById('verifyDetailBoard');
    const detailActions = document.getElementById('verifyDetailActions');
    const summaryStep = document.getElementById('verifySummaryStep');
    if (!rowsRoot || !detailBoard || !detailActions || !summaryStep) return;
    if (!_ensureSubmissionAllowed()) return;

    if (_badgeType === 'blue') {
      const payload = _validatedBlueSubmission();
      if (!payload) return;
      const itemLabel = payload.subject_type === 'business'
        ? 'توثيق الشارة الزرقاء للصفة التجارية'
        : 'توثيق الشارة الزرقاء للهوية الشخصية';
      rowsRoot.innerHTML = `
        <tr><td>${_escapeHtml(itemLabel)}</td></tr>
      `;
    } else {
      const payload = _validatedGreenSubmission();
      if (!payload) return;
      rowsRoot.innerHTML = payload.items.map((row) => `
        <tr><td>${_escapeHtml(row.title)}</td></tr>
      `).join('');
    }

    detailBoard.classList.add('hidden');
    detailActions.classList.add('hidden');
    summaryStep.classList.remove('hidden');
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  async function _submit() {
    if (!_ensureSubmissionAllowed()) return;
    const button = document.getElementById('verifySubmitBtn');
    if (button) {
      button.disabled = true;
      button.style.opacity = '0.7';
    }

    try {
      if (_badgeType === 'blue') {
        await _submitBlueRequest();
      } else {
        await _submitGreenRequest();
      }
    } finally {
      if (button) {
        button.disabled = false;
        button.style.opacity = '';
      }
    }
  }

  async function _submitBlueRequest() {
    const payload = _validatedBlueSubmission();
    if (!payload) return;

    const createResponse = await ApiClient.request('/api/verification/requests/create/', {
      method: 'POST',
      body: {
        badge_type: 'blue',
        requirements: [{ badge_type: 'blue', code: 'B1' }],
        blue_profile: {
          subject_type: payload.subject_type,
          official_number: payload.official_number,
          official_date: payload.official_date,
          verified_name: payload.verified_name,
          is_name_approved: true,
        },
      },
    });
    if (!createResponse.ok || !createResponse.data) {
      _showToast(_createRequestErrorMessage(createResponse, 'blue', 'تعذر إنشاء طلب الشارة الزرقاء.'), 'error');
      return;
    }

    _requestId = createResponse.data.id;
    _requestCode = String(createResponse.data.code || '').trim();
    _rememberBlockingRequest(createResponse.data, 'blue');
    _refreshStatusState();
    for (const file of payload.files) {
      const formData = new FormData();
      formData.append('file', file);
      formData.append('doc_type', payload.subject_type === 'business' ? 'cr' : 'id');
      formData.append('title', payload.subject_type === 'business' ? 'إثبات الشارة الزرقاء للمنشأة' : 'إثبات الشارة الزرقاء للفرد');
      const uploadResponse = await ApiClient.request(`/api/verification/requests/${_requestId}/documents/`, {
        method: 'POST',
        body: formData,
        formData: true,
      });
      if (!uploadResponse.ok) {
        _showToast(_apiErrorMessage(uploadResponse, 'تم إنشاء الطلب لكن تعذر رفع بعض المرفقات.'), 'error');
        await _loadMyRequests();
        _showSuccessStep(
          _requestCode,
          'تم إنشاء الطلب، لكن بعض المرفقات لم تُرفع بنجاح. احتفظ برقم الطلب وتواصل مع الدعم أو أعد المحاولة لاحقًا.',
        );
        return;
      }
    }

    await _loadMyRequests();
    _showSuccessStep(_requestCode);
  }

  async function _submitGreenRequest() {
    const payload = _validatedGreenSubmission();
    if (!payload) return;

    const createResponse = await ApiClient.request('/api/verification/requests/create/', {
      method: 'POST',
      body: {
        badge_type: 'green',
        requirements: payload.items.map((row) => ({ badge_type: 'green', code: row.code })),
      },
    });
    if (!createResponse.ok || !createResponse.data) {
      _showToast(_createRequestErrorMessage(createResponse, 'green', 'تعذر إنشاء طلب الشارة الخضراء.'), 'error');
      return;
    }

    _requestId = createResponse.data.id;
    _requestCode = String(createResponse.data.code || '').trim();
    _rememberBlockingRequest(createResponse.data, 'green');
    _refreshStatusState();

    for (const file of payload.files) {
      const formData = new FormData();
      formData.append('file', file);
      formData.append('doc_type', 'other');
      formData.append('title', 'مرفقات داعمة للشارة الخضراء');
      const uploadResponse = await ApiClient.request(`/api/verification/requests/${_requestId}/documents/`, {
        method: 'POST',
        body: formData,
        formData: true,
      });
      if (!uploadResponse.ok) {
        _showToast(_apiErrorMessage(uploadResponse, 'تم إنشاء الطلب لكن تعذر رفع المرفقات الداعمة.'), 'error');
        await _loadMyRequests();
        _showSuccessStep(
          _requestCode,
          'تم إنشاء الطلب، لكن بعض المرفقات الداعمة لم تُرفع بنجاح. احتفظ برقم الطلب وتواصل مع الدعم أو أعد المحاولة لاحقًا.',
        );
        return;
      }
    }

    await _loadMyRequests();
    _showSuccessStep(_requestCode);
  }

  document.addEventListener('DOMContentLoaded', init);
  return { init };
})();
