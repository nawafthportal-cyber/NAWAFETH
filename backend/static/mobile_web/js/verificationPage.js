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

  function init() {
    if (!Auth.isLoggedIn()) {
      document.getElementById('auth-gate').style.display = '';
      return;
    }
    document.getElementById('verify-content').style.display = '';
    _bindBadgeOptions();
    _bindNav();
    _bindFiles();
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

  function _renderRequirements() {
    const title = document.getElementById('verify-step2-title');
    const container = document.getElementById('verify-requirements');
    if (_badgeType === 'blue') {
      title.textContent = 'متطلبات الشارة الزرقاء';
      container.innerHTML = `
        <div class="req-item"><span class="req-num">1</span> صورة الهوية الوطنية أو السجل التجاري</div>
        <div class="req-item"><span class="req-num">2</span> صورة شخصية واضحة</div>
      `;
    } else {
      title.textContent = 'متطلبات الشارة الخضراء';
      container.innerHTML = `
        <div class="req-item"><span class="req-num">1</span> الشهادات المهنية أو الأكاديمية</div>
        <div class="req-item"><span class="req-num">2</span> إثبات الخبرة (خطابات، عقود، شهادات خبرة)</div>
        <div class="req-item"><span class="req-num">3</span> صورة شخصية واضحة</div>
      `;
    }
  }

  function _renderSummary() {
    const container = document.getElementById('verify-summary');
    container.innerHTML = `
      <div class="summary-row"><span>نوع الشارة:</span><strong>${_badgeType === 'blue' ? 'الشارة الزرقاء' : 'الشارة الخضراء'}</strong></div>
      <div class="summary-row"><span>المستندات:</span><strong>${_files.length} ملف</strong></div>
      <div class="summary-row"><span>الرسوم:</span><strong>مجاناً</strong></div>
    `;
  }

  async function _submit() {
    // Step 1: Create request
    const req = await ApiClient.request('/api/verification/requests/create/', {
      method: 'POST',
      body: { badge_type: _badgeType, requirements: _badgeType === 'blue' ? ['national_id'] : ['certificates'] }
    });
    if (!req.ok) { alert(req.data?.detail || 'فشل إنشاء الطلب'); return; }
    _requestId = req.data?.id;

    // Step 2: Upload documents
    for (const file of _files) {
      const fd = new FormData();
      fd.append('file', file);
      fd.append('doc_type', _badgeType === 'blue' ? 'id_document' : 'certificate');
      await ApiClient.request(`/api/verification/requests/${_requestId}/documents/`, {
        method: 'POST', body: fd, formData: true
      });
    }

    // Show success
    document.querySelectorAll('.verify-step').forEach(s => s.style.display = 'none');
    document.getElementById('verify-success').style.display = '';
  }

  document.addEventListener('DOMContentLoaded', init);
  return { init };
})();
