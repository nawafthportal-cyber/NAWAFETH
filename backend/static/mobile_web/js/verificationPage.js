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

  function _extractList(payload) {
    if (Array.isArray(payload)) return payload;
    if (payload && Array.isArray(payload.results)) return payload.results;
    if (payload && Array.isArray(payload.items)) return payload.items;
    return [];
  }

  function _apiErrorMessage(response, fallback) {
    const data = response && response.data ? response.data : null;
    if (data) {
      if (typeof data.detail === 'string' && data.detail.trim()) return data.detail.trim();
      if (Array.isArray(data.non_field_errors) && data.non_field_errors.length) return String(data.non_field_errors[0]);
      const firstKey = Object.keys(data)[0];
      if (firstKey) {
        const value = data[firstKey];
        if (Array.isArray(value) && value.length) return String(value[0]);
        if (typeof value === 'string') return value;
      }
    }
    return fallback;
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
    ]);

    _renderProviderIdentity();
    _renderPricingStrip();
    _renderGreenRequirements();
    _renderGreenFiles();
    _renderBlueFiles();
    _renderBluePreviews();
    _setBadgeType('blue');
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
          window.alert('فعّل خيار المرفقات أولًا.');
          return;
        }
        if (!_blue.files.length) {
          window.alert('أرفق ملفًا رسميًا واحدًا على الأقل.');
          return;
        }
        _blue.filesApplied = true;
        _renderBlueFiles();
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
          window.alert('أرفق ملفًا داعمًا واحدًا على الأقل للشارة الخضراء.');
          return;
        }
        _green.filesApplied = true;
        _renderGreenFiles();
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

  function _showSuccessStep(requestCode) {
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
    if (successNote) successNote.textContent = 'سيتم التواصل معكم بعد عملية التدقيق المعتمدة من منصة المختص.';
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
      return `
        <article class="verify-plan-card ${isCurrent ? 'is-current' : ''}">
          <div class="verify-plan-card-head">
            <strong>${_escapeHtml(offer.plan_name || item.title || item.code || 'باقة')}</strong>
            <span>${_escapeHtml(offer.billing_cycle_label || 'سنوي')}</span>
          </div>
          <div class="verify-plan-price-row">
            <span>التوثيق الأزرق</span>
            <strong>${_escapeHtml(offer.verification_blue_amount || '0.00')} ر.س</strong>
          </div>
          <div class="verify-plan-price-row">
            <span>التوثيق الأخضر</span>
            <strong>${_escapeHtml(offer.verification_green_amount || '0.00')} ر.س</strong>
          </div>
          <div class="verify-plan-foot">${_escapeHtml((offer.cta && offer.cta.label) || 'متاح')}</div>
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
      window.alert(subjectType === 'business' ? 'أدخل رقم السجل التجاري وتاريخه.' : 'أدخل رقم الهوية أو الإقامة وتاريخ الميلاد.');
      return;
    }

    const response = await ApiClient.request('/api/verification/blue-preview/', {
      method: 'POST',
      body: payload,
    });
    if (!response.ok) {
      window.alert(_apiErrorMessage(response, 'تعذر التحقق من البيانات الحالية.'));
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
      window.alert('نفّذ التحقق أولًا ثم اعتمد الاسم المسترجع.');
      return;
    }
    _blue.approvedSubject = subjectType;
    _renderBluePreviews();
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
      window.alert('اعتمد اسم العميل أو اسم المنشأة أولًا.');
      return null;
    }
    if (!_blue.filesApplied || !_blue.files.length) {
      window.alert('أرفق المستندات الرسمية ثم اضغط تقديم داخل قسم المرفقات.');
      return null;
    }

    const preview = _blue.previews[subjectType];
    const fields = _readBlueSubjectFields(subjectType);
    if (!preview || !fields.official_number || !fields.official_date) {
      window.alert('بيانات الشارة الزرقاء غير مكتملة.');
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
      window.alert('اختر بندًا واحدًا على الأقل من بنود الشارة الخضراء.');
      return null;
    }

    if (!_green.filesApplied || !_green.files.length) {
      window.alert('أرفق المستندات الداعمة ثم اضغط تقديم داخل قسم المرفقات.');
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
      window.alert(_apiErrorMessage(createResponse, 'تعذر إنشاء طلب الشارة الزرقاء.'));
      return;
    }

    _requestId = createResponse.data.id;
    _requestCode = String(createResponse.data.code || '').trim();
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
        window.alert(_apiErrorMessage(uploadResponse, 'تم إنشاء الطلب لكن تعذر رفع بعض المرفقات.'));
        return;
      }
    }

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
      window.alert(_apiErrorMessage(createResponse, 'تعذر إنشاء طلب الشارة الخضراء.'));
      return;
    }

    _requestId = createResponse.data.id;
    _requestCode = String(createResponse.data.code || '').trim();

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
        window.alert(_apiErrorMessage(uploadResponse, 'تم إنشاء الطلب لكن تعذر رفع المرفقات الداعمة.'));
        return;
      }
    }

    _showSuccessStep(_requestCode);
  }

  document.addEventListener('DOMContentLoaded', init);
  return { init };
})();
