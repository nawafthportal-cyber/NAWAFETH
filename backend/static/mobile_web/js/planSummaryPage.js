'use strict';

const PlanSummaryPage = (() => {
  const EMPTY_PLAN_NOT_SELECTED = 'لم يتم تحديد الباقة المطلوبة.';
  const EMPTY_PLAN_NOT_FOUND = 'تعذر العثور على الباقة المطلوبة';
  const EMPTY_PLAN_LOAD_FAILED = 'تعذر تحميل تفاصيل الباقة.';
  const SUBMIT_FALLBACK_ERROR = 'تعذر إنشاء طلب الاشتراك';

  let _submitting = false;
  let _toastTimer = null;

  function _escapeHtml(value) {
    return String(value || '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/\"/g, '&quot;')
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
      const preferredKeys = [
        'ar',
        'text',
        'label',
        'title',
        'name',
        'value',
        'display_name',
        'display',
        'value_text',
        'display_value',
        'message',
        'en',
      ];

      for (const key of preferredKeys) {
        if (Object.prototype.hasOwnProperty.call(value, key)) {
          const fromKey = _valueToText(value[key]);
          if (fromKey) return fromKey;
        }
      }

      for (const key of Object.keys(value)) {
        const fromAnyKey = _valueToText(value[key]);
        if (fromAnyKey) return fromAnyKey;
      }
    }

    return String(value);
  }

  function _safeText(value, fallback = '') {
    const text = _valueToText(value);
    if (text) return _escapeHtml(text);
    return _escapeHtml(_valueToText(fallback));
  }

  function _asBool(value) {
    if (value === true || value === 1 || value === '1') return true;
    const text = _valueToText(value).toLowerCase();
    return text === 'true' || text === 'yes';
  }

  function _extractList(payload) {
    if (Array.isArray(payload)) return payload;
    if (payload && Array.isArray(payload.results)) return payload.results;
    return [];
  }

  function _planIdFromLocation() {
    const url = new URL(window.location.href);
    const parsed = Number(url.searchParams.get('plan_id') || 0);
    return Number.isFinite(parsed) && parsed > 0 ? parsed : 0;
  }

  function _offer(plan) {
    return plan && typeof plan === 'object' ? (plan.provider_offer || {}) : {};
  }

  function _action(plan) {
    const offer = _offer(plan);
    return offer && typeof offer === 'object' ? (offer.cta || {}) : {};
  }

  function init() {
    if (!Auth.isLoggedIn()) {
      _showAuthGate();
      return;
    }
    _showContent();
    _loadSummary();
  }

  function _showAuthGate() {
    const gate = document.getElementById('auth-gate');
    const content = document.getElementById('summary-content');
    if (gate) gate.classList.remove('hidden');
    if (content) content.classList.add('hidden');
  }

  function _showContent() {
    const gate = document.getElementById('auth-gate');
    const content = document.getElementById('summary-content');
    if (gate) gate.classList.add('hidden');
    if (content) content.classList.remove('hidden');
  }

  function _setLoading(isLoading) {
    const loading = !!isLoading;
    const loader = document.getElementById('summary-loading');
    const empty = document.getElementById('summary-empty');
    const card = document.getElementById('summary-card');
    if (loader) loader.classList.toggle('hidden', !loading);
    if (loading) {
      if (empty) empty.classList.add('hidden');
      if (card) card.classList.add('hidden');
    }
  }

  function _showEmpty(message) {
    const empty = document.getElementById('summary-empty');
    const card = document.getElementById('summary-card');
    const messageEl = document.getElementById('summary-empty-message');
    if (card) card.classList.add('hidden');
    if (empty) empty.classList.remove('hidden');
    if (messageEl) messageEl.textContent = _valueToText(message) || EMPTY_PLAN_NOT_FOUND;
  }

  async function _loadSummary() {
    const planId = _planIdFromLocation();
    if (!planId) {
      _showEmpty(EMPTY_PLAN_NOT_SELECTED);
      return;
    }

    _setLoading(true);

    try {
      const plansRes = await ApiClient.get('/api/subscriptions/plans/');
      if (!plansRes.ok) {
        _showEmpty(EMPTY_PLAN_LOAD_FAILED);
        return;
      }

      const plan = _extractList(plansRes.data).find((item) => Number(item && item.id) === planId);
      if (!plan) {
        _showEmpty(EMPTY_PLAN_NOT_FOUND);
        return;
      }

      _renderSummary(plan);
    } catch (_) {
      _showEmpty(EMPTY_PLAN_LOAD_FAILED);
    } finally {
      _setLoading(false);
    }
  }

  function _detailRow(label, value, emphasize) {
    return `
      <div class="ps-details-row${emphasize ? ' ps-details-row-emphasis' : ''}">
        <span>${_safeText(label)}</span>
        <strong>${_safeText(value)}</strong>
      </div>
    `;
  }

  function _compareRow(row) {
    const item = row && typeof row === 'object' ? row : {};
    const label = item.label ?? item.title ?? item.name;
    const value = item.value ?? item.text ?? item.amount;
    return `
      <div class="ps-compare-row">
        <span class="ps-compare-label">${_safeText(label)}</span>
        <strong class="ps-compare-value">${_safeText(value)}</strong>
      </div>
    `;
  }

  function _renderSummary(plan) {
    const offer = _offer(plan);
    const action = _action(plan);
    const rows = Array.isArray(offer.summary_rows) ? offer.summary_rows : [];
    const features = Array.isArray(offer.feature_bullets)
      ? offer.feature_bullets.map((item) => _valueToText(item)).filter(Boolean)
      : [];

    const planName = _valueToText(offer.plan_name || plan.title || plan.name) || 'الباقة';
    const billingCycle = _valueToText(offer.billing_cycle_label) || 'سنوي';
    const annualPrice = _valueToText(offer.annual_price_label) || 'مجانية';
    const finalAmount = _valueToText(offer.final_payable_label) || annualPrice;
    const verificationEffect = _valueToText(offer.verification_effect_label) || '—';
    const taxNote = _valueToText(offer.tax_note);
    const buttonLabel = _valueToText(action.label) || 'ترقية';
    const canSubmit = _asBool(action.enabled);

    const container = document.getElementById('summary-card');
    if (!container) return;
    container.innerHTML = `
      <section class="plan-summary-layout">
        <article class="ps-hero-card">
          <div class="ps-hero-head">
            <div class="ps-hero-main">
              <h2 class="ps-hero-title">${_safeText(planName)}</h2>
              <p class="ps-hero-description">${_safeText(offer.description)}</p>
            </div>
            <div class="ps-price-chip">
              <div class="ps-price-label">المبلغ النهائي</div>
              <div class="ps-price-value">${_safeText(finalAmount)}</div>
              <div class="ps-price-cycle">${_safeText(billingCycle)}</div>
            </div>
          </div>
        </article>

        <article class="ps-card ps-details-card">
          <h3 class="ps-section-title">تفاصيل الاشتراك</h3>
          <div class="ps-details-grid">
            ${_detailRow('الباقة المختارة', planName)}
            ${_detailRow('دورة الفوترة', billingCycle)}
            ${_detailRow('سعر الباقة', annualPrice)}
            ${_detailRow('أثر التوثيق', verificationEffect)}
            ${_detailRow('المبلغ النهائي المستحق', finalAmount, true)}
          </div>
        </article>

        <article class="ps-card ps-features-card">
          <h3 class="ps-section-title">المزايا الرئيسية</h3>
          <div class="ps-features-list">
            ${features.map((item) => `
              <div class="ps-feature-item">
                <span class="ps-feature-bullet">•</span>
                <span>${_safeText(item)}</span>
              </div>
            `).join('')}
          </div>
        </article>

        <article class="ps-card ps-compare-card">
          <h3 class="ps-section-title">تفاصيل المقارنة</h3>
          <div class="ps-compare-wrap">
            ${rows.map(_compareRow).join('')}
          </div>
        </article>

        <div class="ps-tax-panel">
          <strong class="ps-tax-title">ملاحظة الضريبة</strong>
          <p class="ps-tax-text">${_safeText(taxNote)}</p>
        </div>

        <div class="ps-action-row">
          <button
            id="summary-submit"
            type="button"
            class="btn btn-primary ps-submit-btn"
            data-label="${_safeText(buttonLabel)}"
            ${canSubmit ? '' : 'disabled'}
          >${_safeText(buttonLabel)}</button>
        </div>
      </section>
    `;

    container.classList.remove('hidden');

    if (canSubmit) {
      const submitBtn = document.getElementById('summary-submit');
      if (submitBtn) {
        submitBtn.addEventListener('click', () => _subscribe(plan, finalAmount));
      }
    }
  }

  function _setSubmitting(isSubmitting) {
    _submitting = !!isSubmitting;
    const button = document.getElementById('summary-submit');
    if (!button) return;

    const buttonLabel = button.getAttribute('data-label') || 'ترقية';
    if (_submitting) {
      button.disabled = true;
      button.innerHTML = '<span class="ps-btn-spinner" aria-hidden="true"></span>';
      return;
    }

    button.innerHTML = _escapeHtml(buttonLabel);
    button.disabled = false;
  }

  function _extractError(response, fallback) {
    const data = response && response.data ? response.data : null;
    const errorText = _valueToText(
      (data && (data.detail || data.message || data.error)) ||
      (response && response.error) ||
      ''
    );
    return errorText || fallback;
  }

  async function _subscribe(plan, finalAmount) {
    if (_submitting) return;
    const planId = Number(plan && plan.id);
    if (!Number.isFinite(planId) || planId <= 0) return;

    _setSubmitting(true);
    try {
      const res = await ApiClient.request(`/api/subscriptions/subscribe/${planId}/`, {
        method: 'POST',
      });

      if (!res.ok) {
        _showToast(_extractError(res, SUBMIT_FALLBACK_ERROR), 'error');
        return;
      }

      const amountLabel = _valueToText(finalAmount) || 'مجانية';
      await _showSuccessDialog(amountLabel);
      window.location.href = '/plans/';
    } catch (_) {
      _showToast(SUBMIT_FALLBACK_ERROR, 'error');
    } finally {
      _setSubmitting(false);
    }
  }

  function _showSuccessDialog(amountLabel) {
    const existing = document.getElementById('ps-result-dialog-backdrop');
    if (existing) existing.remove();

    const backdrop = document.createElement('div');
    backdrop.id = 'ps-result-dialog-backdrop';
    backdrop.className = 'ps-result-dialog-backdrop';

    const dialog = document.createElement('div');
    dialog.className = 'ps-result-dialog';
    dialog.setAttribute('role', 'dialog');
    dialog.setAttribute('aria-modal', 'true');
    dialog.setAttribute('aria-label', 'تم إنشاء الطلب');
    dialog.innerHTML = `
      <h3>تم إنشاء الطلب</h3>
      <p>تم إنشاء طلب الاشتراك بنجاح. المبلغ النهائي: ${_safeText(amountLabel)}</p>
      <button type="button" class="btn btn-primary">حسنًا</button>
    `;

    backdrop.appendChild(dialog);
    document.body.appendChild(backdrop);

    return new Promise((resolve) => {
      const close = () => {
        backdrop.remove();
        resolve();
      };

      const okButton = dialog.querySelector('button');
      if (okButton) {
        okButton.addEventListener('click', close);
        okButton.focus();
      }

      backdrop.addEventListener('click', (event) => {
        if (event.target === backdrop) close();
      });
    });
  }

  function _showToast(message, type) {
    if (!message) return;
    const existing = document.getElementById('ps-toast');
    if (existing) existing.remove();

    const toast = document.createElement('div');
    toast.id = 'ps-toast';
    toast.className = 'ps-toast' + (type ? (' ' + type) : '');
    toast.textContent = message;
    document.body.appendChild(toast);

    requestAnimationFrame(() => toast.classList.add('show'));
    window.clearTimeout(_toastTimer);
    _toastTimer = window.setTimeout(() => {
      toast.classList.remove('show');
      window.setTimeout(() => {
        if (toast.parentNode) toast.remove();
      }, 180);
    }, 2400);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  return { init };
})();
