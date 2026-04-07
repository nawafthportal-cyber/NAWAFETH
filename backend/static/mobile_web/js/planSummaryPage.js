'use strict';

const PlanSummaryPage = (() => {
  const EMPTY_PLAN_NOT_SELECTED = 'لم يتم تحديد الباقة المطلوبة.';
  const EMPTY_PLAN_NOT_FOUND = 'تعذر العثور على الباقة المطلوبة.';
  const EMPTY_PLAN_LOAD_FAILED = 'تعذر تحميل تفاصيل الباقة.';
  const SUBMIT_FALLBACK_ERROR = 'تعذر إنشاء طلب الاشتراك.';

  const state = {
    plan: null,
    profile: null,
    durationCount: 1,
    submitting: false,
    toastTimer: null,
  };

  function shell() {
    return document.getElementById('summary-content');
  }

  function plansUrl() {
    const node = shell();
    return (node && node.dataset && node.dataset.plansUrl) || '/api/subscriptions/plans/';
  }

  function profileUrl() {
    const node = shell();
    return (node && node.dataset && node.dataset.profileUrl) || '/api/accounts/me/';
  }

  function subscribeUrl(planId) {
    const node = shell();
    const template = (node && node.dataset && node.dataset.subscribeUrlTemplate) || '/api/subscriptions/subscribe/__id__/';
    return template.replace('__id__', String(planId || '0'));
  }

  function paymentUrl(subscriptionId) {
    const node = shell();
    const base = (node && node.dataset && node.dataset.paymentUrl) || '/plans/payment/';
    return `${base}?subscription_id=${encodeURIComponent(String(subscriptionId || '0'))}`;
  }

  function requestCodeFromSubscription(subscription) {
    const requestCode = asText(subscription && subscription.request_code);
    if (requestCode) return requestCode;
    const subscriptionId = Number(subscription && subscription.id);
    if (Number.isFinite(subscriptionId) && subscriptionId > 0) {
      return 'SD' + String(subscriptionId).padStart(6, '0');
    }
    return '—';
  }

  function plansPageUrl() {
    const node = shell();
    return (node && node.dataset && node.dataset.plansPageUrl) || '/plans/';
  }

  function escapeHtml(value) {
    return String(value || '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  function asText(value) {
    if (value == null) return '';
    if (typeof value === 'string') return value.trim();
    if (typeof value === 'number' || typeof value === 'boolean') return String(value);
    if (Array.isArray(value)) return value.map(asText).filter(Boolean).join('، ');
    if (typeof value === 'object') {
      const keys = ['label', 'title', 'name', 'value', 'text', 'message', 'display_name', 'username'];
      for (const key of keys) {
        if (Object.prototype.hasOwnProperty.call(value, key)) {
          const candidate = asText(value[key]);
          if (candidate) return candidate;
        }
      }
    }
    return String(value).trim();
  }

  function safeText(value, fallback = '') {
    return escapeHtml(asText(value) || asText(fallback));
  }

  function asList(payload) {
    if (Array.isArray(payload)) return payload;
    if (payload && Array.isArray(payload.results)) return payload.results;
    if (payload && Array.isArray(payload.items)) return payload.items;
    return [];
  }

  function parseIntParam(name) {
    try {
      const params = new URLSearchParams(window.location.search || '');
      const raw = String(params.get(name) || '').trim();
      if (!raw) return 0;
      const parsed = parseInt(raw, 10);
      return Number.isFinite(parsed) && parsed > 0 ? parsed : 0;
    } catch (_) {
      return 0;
    }
  }

  function roundMoney(value) {
    return Math.round((Number(value) + Number.EPSILON) * 100) / 100;
  }

  function money(value) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed.toFixed(2) : '0.00';
  }

  function moneyNumber(value) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : 0;
  }

  function periodUnit(period) {
    return String(period || '').trim().toLowerCase() === 'month' ? 'شهر' : 'سنة';
  }

  function currentHandle() {
    const profile = state.profile || {};
    const username = asText(profile.username);
    if (username) return `@${username.replace(/^@+/, '')}`;
    const phone = asText(profile.phone);
    if (phone) return phone;
    const fullName = [asText(profile.first_name), asText(profile.last_name)].filter(Boolean).join(' ').trim();
    if (fullName) return fullName;
    return 'الحساب الحالي';
  }

  function offer(plan) {
    return plan && typeof plan === 'object' ? (plan.provider_offer || {}) : {};
  }

  function action(plan) {
    const currentOffer = offer(plan);
    return currentOffer && typeof currentOffer === 'object' ? (currentOffer.cta || {}) : {};
  }

  function canContinue(plan) {
    const currentAction = action(plan);
    const stateCode = String(currentAction.state || '').trim().toLowerCase();
    if (stateCode === 'upgrade') return true;
    if (stateCode !== 'pending') return false;
    return asText(currentAction.label) !== 'بانتظار المراجعة';
  }

  function actionHint(plan) {
    const currentAction = action(plan);
    const stateCode = String(currentAction.state || '').trim().toLowerCase();
    if (stateCode === 'current') return 'هذه هي باقتك الحالية بالفعل.';
    if (stateCode === 'unavailable') return 'لا يمكن تخفيض الباقة من هذا المسار.';
    if (stateCode === 'pending' && asText(currentAction.label) === 'بانتظار المراجعة') {
      return 'هذا الطلب مدفوع بالفعل وينتظر مراجعة فريق الاشتراكات.';
    }
    if (stateCode === 'pending') return 'يوجد طلب سابق غير مكتمل لهذه الباقة، ويمكنك متابعة الدفع منه.';
    return '';
  }

  function submitLabel(plan) {
    const currentAction = action(plan);
    const stateCode = String(currentAction.state || '').trim().toLowerCase();
    if (stateCode === 'pending') return 'استمرار إلى الدفع';
    return 'استمرار';
  }

  function pricingSummary(plan, durationCount) {
    const currentOffer = offer(plan);
    const unitPrice = Number(currentOffer.final_payable_amount != null ? currentOffer.final_payable_amount : plan.price);
    const vatPercent = Number(currentOffer.additional_vat_percent != null ? currentOffer.additional_vat_percent : 0);
    const normalizedDuration = Math.min(10, Math.max(1, parseInt(String(durationCount || '1'), 10) || 1));
    const subtotal = roundMoney((Number.isFinite(unitPrice) ? unitPrice : 0) * normalizedDuration);
    const vat = roundMoney(subtotal * ((Number.isFinite(vatPercent) ? vatPercent : 0) / 100));
    const total = roundMoney(subtotal + vat);
    return {
      durationCount: normalizedDuration,
      subtotal,
      vat,
      total,
    };
  }

  function setLoading(isLoading) {
    const loader = document.getElementById('summary-loading');
    const empty = document.getElementById('summary-empty');
    const card = document.getElementById('summary-card');
    if (loader) loader.classList.toggle('hidden', !isLoading);
    if (isLoading) {
      if (empty) empty.classList.add('hidden');
      if (card) card.classList.add('hidden');
    }
  }

  function showEmpty(message) {
    const empty = document.getElementById('summary-empty');
    const card = document.getElementById('summary-card');
    const messageEl = document.getElementById('summary-empty-message');
    if (card) card.classList.add('hidden');
    if (empty) empty.classList.remove('hidden');
    if (messageEl) messageEl.textContent = asText(message) || EMPTY_PLAN_NOT_FOUND;
  }

  function bindRenderEvents() {
    const durationInput = document.getElementById('summary-duration');
    const submitBtn = document.getElementById('summary-submit');
    const cancelBtn = document.getElementById('summary-cancel');
    const backBtn = document.getElementById('summary-back');

    if (durationInput) {
      const syncDuration = () => {
        const parsed = parseInt(String(durationInput.value || '1'), 10);
        state.durationCount = Math.min(10, Math.max(1, Number.isFinite(parsed) ? parsed : 1));
        durationInput.value = String(state.durationCount);
        renderSummary();
      };
      durationInput.addEventListener('input', syncDuration);
      durationInput.addEventListener('change', syncDuration);
    }

    if (submitBtn) {
      submitBtn.addEventListener('click', submit);
    }

    [cancelBtn, backBtn].forEach((button) => {
      if (!button) return;
      button.addEventListener('click', () => {
        window.location.href = plansPageUrl();
      });
    });
  }

  function renderSummary() {
    const plan = state.plan;
    const container = document.getElementById('summary-card');
    if (!plan || !container) return;

    const summary = pricingSummary(plan, state.durationCount);
    const currentOffer = offer(plan);
    const unitLabel = periodUnit(plan.period);
    const planName = asText(currentOffer.plan_name || plan.title || plan.name) || 'الباقة';
    const canSubmitNow = canContinue(plan) && !state.submitting;
    const hint = actionHint(plan);
    const actionText = submitLabel(plan);

    container.innerHTML = `
      <section class="subsum-shell">
        <header class="subsum-header">
          <button type="button" class="subsum-back" id="summary-back" aria-label="العودة">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <polyline points="15 18 9 12 15 6"></polyline>
            </svg>
          </button>
          <div class="subsum-title-pill">ملخص طلب الترقية والتكلفة</div>
        </header>

        <div class="subsum-user-row">
          <span class="subsum-user-label">اسم المستخدم</span>
          <strong class="subsum-user-handle">${safeText(currentHandle())}</strong>
        </div>

        <div class="subsum-panel">
          <p class="subsum-panel-copy">عرض الباقة التي تم اختيارها من الصفحة السابقة مع إمكانية تعديل ${safeText(unitLabel)} واحتساب التكلفة تلقائياً.</p>
          <div class="subsum-table-wrap">
            <table class="subsum-table" aria-label="ملخص الباقة المختارة">
              <thead>
                <tr>
                  <th>الباقة</th>
                  <th>المدة (${safeText(unitLabel)})</th>
                  <th>التكلفة (ريال سعودي)</th>
                </tr>
              </thead>
              <tbody>
                <tr>
                  <td>${safeText(planName)}</td>
                  <td>
                    <label class="subsum-duration-field" for="summary-duration">
                      <input id="summary-duration" type="number" min="1" max="10" step="1" value="${summary.durationCount}">
                    </label>
                  </td>
                  <td>${safeText(money(summary.subtotal))}</td>
                </tr>
              </tbody>
            </table>
          </div>

          <div class="subsum-total-card">
            <div class="subsum-total-row">
              <span>المجموع</span>
              <strong>${safeText(money(summary.subtotal))}</strong>
            </div>
            <div class="subsum-total-row">
              <span>VAT</span>
              <strong>${safeText(money(summary.vat))}</strong>
            </div>
            <div class="subsum-total-row is-grand">
              <span>التكلفة الكلية</span>
              <strong>${safeText(money(summary.total))}</strong>
            </div>
          </div>

          ${hint ? `<div class="subsum-hint">${safeText(hint)}</div>` : ''}

          <div class="subsum-actions">
            <button type="button" class="subsum-btn subsum-btn-secondary" id="summary-cancel">إلغاء</button>
            <button type="button" class="subsum-btn subsum-btn-primary" id="summary-submit" ${canSubmitNow ? '' : 'disabled'}>${state.submitting ? 'جاري التجهيز...' : safeText(actionText)}</button>
          </div>
        </div>
      </section>
    `;

    container.classList.remove('hidden');
    bindRenderEvents();
  }

  function extractError(response, fallback) {
    const data = response && response.data ? response.data : null;
    const detail = asText((data && (data.detail || data.message || data.error)) || (response && response.error) || '');
    return detail || fallback;
  }

  function showToast(message, type) {
    if (!message) return;
    const existing = document.getElementById('subsum-toast');
    if (existing) existing.remove();

    const toast = document.createElement('div');
    toast.id = 'subsum-toast';
    toast.className = 'subsum-toast' + (type ? (' ' + type) : '');
    toast.textContent = message;
    document.body.appendChild(toast);

    requestAnimationFrame(() => toast.classList.add('show'));
    window.clearTimeout(state.toastTimer);
    state.toastTimer = window.setTimeout(() => {
      toast.classList.remove('show');
      window.setTimeout(() => {
        if (toast.parentNode) toast.remove();
      }, 180);
    }, 2600);
  }

  function requiresPayment(subscription) {
    if (!subscription || typeof subscription !== 'object') return false;
    const invoiceSummary = subscription.invoice_summary || {};
    const invoiceId = Number(subscription.invoice || invoiceSummary.id || 0);
    const requestStatus = asText(subscription.provider_status_code || subscription.status).toLowerCase();
    const invoiceStatus = asText(invoiceSummary.status).toLowerCase();
    const invoicePaid = invoiceStatus === 'paid' || invoiceSummary.payment_effective === true;
    const total = moneyNumber(invoiceSummary.total);

    return invoiceId > 0 && requestStatus === 'pending_payment' && !invoicePaid && total > 0;
  }

  function successDialogCopy(subscription) {
    const statusCode = asText(subscription && (subscription.provider_status_code || subscription.status)).toLowerCase();
    if (statusCode === 'active') {
      return {
        title: 'تم تسجيل الاشتراك بنجاح',
        lines: [
          'تم تفعيل الباقة الأساسية المجانية على حسابكم.',
          'يمكنك الآن العودة إلى صفحة الباقات ومتابعة استخدام المزايا المتاحة.',
        ],
      };
    }

    return {
      title: 'تمت العملية بنجاح',
      lines: [
        'تم تسجيل الطلب بدون الحاجة إلى دفع إضافي.',
        'سيتم إشعاركم بتفعيل الاشتراك بعد مراجعة فريق الاشتراكات.',
      ],
    };
  }

  function showSuccessDialog(subscription) {
    const existing = document.getElementById('subpay-result-backdrop');
    if (existing) existing.remove();

    const copy = successDialogCopy(subscription);
    const backdrop = document.createElement('div');
    backdrop.id = 'subpay-result-backdrop';
    backdrop.className = 'subpay-result-backdrop';
    backdrop.innerHTML = `
      <div class="subpay-result-dialog" role="dialog" aria-modal="true" aria-label="${safeText(copy.title)}">
        <div class="subpay-result-code">رقم الطلب: ${safeText(requestCodeFromSubscription(subscription))}</div>
        <div class="subpay-result-body">
          ${copy.lines.map((line) => `<p>${safeText(line)}</p>`).join('')}
        </div>
        <button type="button" class="subpay-result-close">إغلاق</button>
      </div>
    `;
    document.body.appendChild(backdrop);

    return new Promise((resolve) => {
      const closeButton = backdrop.querySelector('.subpay-result-close');
      const close = () => {
        backdrop.remove();
        resolve();
      };
      if (closeButton) closeButton.addEventListener('click', close);
      backdrop.addEventListener('click', (event) => {
        if (event.target === backdrop) close();
      });
    });
  }

  async function submit() {
    if (!state.plan || state.submitting || !canContinue(state.plan)) return;
    const planId = Number(state.plan.id || 0);
    if (!Number.isFinite(planId) || planId <= 0) return;

    state.submitting = true;
    renderSummary();
    try {
      const response = await ApiClient.request(subscribeUrl(planId), {
        method: 'POST',
        body: {
          duration_count: state.durationCount,
        },
      });

      if (!response.ok || !response.data || !response.data.id) {
        showToast(extractError(response, SUBMIT_FALLBACK_ERROR), 'error');
        return;
      }

      if (!requiresPayment(response.data)) {
        await showSuccessDialog(response.data);
        window.location.href = plansPageUrl();
        return;
      }

      window.location.href = paymentUrl(response.data.id);
    } catch (_) {
      showToast(SUBMIT_FALLBACK_ERROR, 'error');
    } finally {
      state.submitting = false;
      renderSummary();
    }
  }

  async function loadSummary() {
    const planId = parseIntParam('plan_id');
    if (!planId) {
      showEmpty(EMPTY_PLAN_NOT_SELECTED);
      return;
    }

    setLoading(true);
    try {
      const [plansRes, profileRes] = await Promise.allSettled([
        ApiClient.get(plansUrl()),
        ApiClient.get(profileUrl()),
      ]);

      if (plansRes.status !== 'fulfilled' || !plansRes.value.ok) {
        showEmpty(EMPTY_PLAN_LOAD_FAILED);
        return;
      }

      const plan = asList(plansRes.value.data).find((item) => Number(item && item.id) === planId);
      if (!plan) {
        showEmpty(EMPTY_PLAN_NOT_FOUND);
        return;
      }

      state.plan = plan;
      if (profileRes.status === 'fulfilled' && profileRes.value.ok) {
        state.profile = profileRes.value.data;
      }
      renderSummary();
    } catch (_) {
      showEmpty(EMPTY_PLAN_LOAD_FAILED);
    } finally {
      setLoading(false);
    }
  }

  function init() {
    if (!Auth.isLoggedIn()) {
      const gate = document.getElementById('auth-gate');
      if (gate) gate.classList.remove('hidden');
      return;
    }

    const content = document.getElementById('summary-content');
    if (content) content.classList.remove('hidden');
    loadSummary();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  return { init };
})();
