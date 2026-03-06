/* ===================================================================
   verificationPage.js — Verification Badge Wizard
   1:1 parity with Flutter verification_screen.dart
   =================================================================== */
'use strict';

const VerificationPage = (() => {
  let _step = 1;
  let _badgeType = '';
  let _requestId = null;
  let _files = [];
  let _pricing = null;
  const _badgeDetailCache = {};

  async function init() {
    if (!Auth.isLoggedIn()) {
      document.getElementById('auth-gate').style.display = '';
      return;
    }
    document.getElementById('verify-content').style.display = '';
    _bindBadgeOptions();
    _bindNav();
    _bindFiles();
    await _loadPricing();
  }

  async function _loadPricing() {
    const res = await ApiClient.get('/api/verification/pricing/my/');
    if (res.ok && res.data) _pricing = res.data;
  }

  async function _loadBadgeDetail(badgeType) {
    if (_badgeDetailCache[badgeType]) return _badgeDetailCache[badgeType];
    const res = await ApiClient.get(`/api/public/badges/${badgeType}/`);
    if (res.ok && res.data) {
      _badgeDetailCache[badgeType] = res.data;
      return res.data;
    }
    return null;
  }

  function _pricingEntry(badgeType) {
    return _pricing?.prices?.[badgeType] || null;
  }

  function _priceAmount(badgeType) {
    const raw = _pricingEntry(badgeType)?.amount;
    const parsed = Number.parseFloat(String(raw ?? '100'));
    return Number.isFinite(parsed) ? parsed : 100;
  }

  function _isFree(badgeType) {
    return _pricingEntry(badgeType)?.is_free === true || _priceAmount(badgeType) <= 0;
  }

  function _formatAmount(amount) {
    return Number.isInteger(amount) ? String(amount) : amount.toFixed(2);
  }

  function _priceLabel(badgeType) {
    return _isFree(badgeType)
      ? 'مجاني عند الاعتماد'
      : `${_formatAmount(_priceAmount(badgeType))} ر.س عند الاعتماد`;
  }

  function _pricingNote(badgeType) {
    const tierLabel = String(_pricing?.tier_label || '').trim();
    if (_isFree(badgeType)) {
      return tierLabel
        ? `هذه الخدمة مجانية ضمن باقة ${tierLabel} بعد اعتماد الطلب.`
        : 'هذه الخدمة مجانية بعد اعتماد الطلب.';
    }
    const amount = _formatAmount(_priceAmount(badgeType));
    return tierLabel
      ? `لن يتم خصم أي مبلغ الآن. بعد مراجعة الطلب واعتماد البنود ستصدر فاتورة بقيمة ${amount} ر.س وفق باقة ${tierLabel}.`
      : `لن يتم خصم أي مبلغ الآن. بعد مراجعة الطلب واعتماد البنود ستصدر فاتورة بقيمة ${amount} ر.س.`;
  }

  function _bindBadgeOptions() {
    document.querySelectorAll('.badge-option').forEach(opt => {
      opt.addEventListener('click', () => {
        document.querySelectorAll('.badge-option').forEach(o => o.classList.remove('selected'));
        opt.classList.add('selected');
        _badgeType = opt.dataset.type;
        _goStep(2);
      });
    });
  }

  function _bindNav() {
    document.getElementById('verify-back1').addEventListener('click', () => _goStep(1));
    document.getElementById('verify-back2').addEventListener('click', () => _goStep(2));
    document.getElementById('verify-next2').addEventListener('click', () => {
      if (!_files.length) { alert('يرجى رفع المستندات المطلوبة'); return; }
      _goStep(3);
    });
    document.getElementById('verify-submit').addEventListener('click', _submit);
  }

  function _bindFiles() {
    const input = document.getElementById('verify-files');
    input.addEventListener('change', () => {
      _files = Array.from(input.files);
      const list = document.getElementById('verify-file-list');
      list.innerHTML = '';
      _files.forEach(f => {
        const chip = document.createElement('span');
        chip.className = 'file-chip';
        chip.textContent = f.name;
        list.appendChild(chip);
      });
    });
  }

  function _goStep(n) {
    _step = n;
    document.querySelectorAll('.verify-step').forEach(s => s.style.display = 'none');
    document.getElementById(`verify-step${n}`).style.display = '';
    document.querySelectorAll('.wizard-step').forEach(s => {
      const si = parseInt(s.dataset.step);
      s.classList.toggle('active', si === n);
      s.classList.toggle('done', si < n);
    });

    if (n === 2) _renderRequirements();
    if (n === 3) _renderSummary();
  }

  async function _renderRequirements() {
    const title = document.getElementById('verify-step2-title');
    const container = document.getElementById('verify-requirements');
    container.innerHTML = '<div class="req-item">جاري تحميل المتطلبات...</div>';
    const detail = await _loadBadgeDetail(_badgeType);
    if (!detail) {
      title.textContent = _badgeType === 'blue' ? 'متطلبات الشارة الزرقاء' : 'متطلبات الشارة الخضراء';
      container.innerHTML = '<div class="req-item">تعذر تحميل المتطلبات حالياً. يمكنك المتابعة ورفع المستندات الداعمة.</div>';
      return;
    }
    title.textContent = `متطلبات ${detail.title || (_badgeType === 'blue' ? 'الشارة الزرقاء' : 'الشارة الخضراء')}`;
    const requirements = Array.isArray(detail.requirements) ? detail.requirements : [];
    container.innerHTML = requirements.length
      ? requirements.map((item, index) => `<div class="req-item"><span class="req-num">${index + 1}</span> ${UI.text(item.title || item.code || '')}</div>`).join('')
      : '<div class="req-item">لا توجد متطلبات إضافية حالياً.</div>';
  }

  function _renderSummary() {
    const container = document.getElementById('verify-summary');
    const pricingNote = document.getElementById('verify-pricing-note');
    const badgeLabel = _badgeType === 'blue' ? 'الشارة الزرقاء' : 'الشارة الخضراء';
    container.innerHTML = `
      <div class="summary-row"><span>نوع الشارة:</span><strong>${badgeLabel}</strong></div>
      <div class="summary-row"><span>المستندات:</span><strong>${_files.length} ملف</strong></div>
      <div class="summary-row"><span>الرسوم المتوقعة:</span><strong>${_priceLabel(_badgeType)}</strong></div>
    `;
    if (pricingNote) pricingNote.textContent = _pricingNote(_badgeType);
  }

  async function _submit() {
    // Step 1: Create request
    const req = await ApiClient.request('/api/verification/requests/create/', {
      method: 'POST',
      body: {
        badge_type: _badgeType,
        requirements: _badgeType === 'blue'
          ? [{ badge_type: 'blue', code: 'B1' }]
          : [{ badge_type: 'green', code: 'G1' }],
      }
    });
    if (!req.ok) { alert(req.data?.detail || 'فشل إنشاء الطلب'); return; }
    _requestId = req.data?.id;

    // Step 2: Upload documents
    for (const file of _files) {
      const fd = new FormData();
      fd.append('file', file);
      fd.append('doc_type', _badgeType === 'blue' ? 'id' : 'license');
      await ApiClient.request(`/api/verification/requests/${_requestId}/documents/`, {
        method: 'POST', body: fd, formData: true
      });
    }

    // Show success
    document.querySelectorAll('.verify-step').forEach(s => s.style.display = 'none');
    const successNote = document.getElementById('verify-success-note');
    if (successNote) successNote.textContent = _pricingNote(_badgeType);
    document.getElementById('verify-success').style.display = '';
  }

  document.addEventListener('DOMContentLoaded', init);
  return { init };
})();
