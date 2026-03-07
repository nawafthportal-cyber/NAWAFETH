'use strict';

const PlanSummaryPage = (() => {
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

      return '';
    }

    return String(value);
  }

  function _safeText(value, fallback) {
    const text = _valueToText(value);
    if (text) return _escapeHtml(text);
    return _escapeHtml(_valueToText(fallback));
  }

  function _extractList(payload) {
    if (Array.isArray(payload)) return payload;
    if (payload && Array.isArray(payload.results)) return payload.results;
    return [];
  }

  function _planIdFromLocation() {
    const url = new URL(window.location.href);
    return Number(url.searchParams.get('plan_id') || 0);
  }

  function init() {
    if (!Auth.isLoggedIn()) {
      document.getElementById('auth-gate').style.display = '';
      return;
    }
    document.getElementById('summary-content').style.display = '';
    _loadSummary();
  }

  async function _loadSummary() {
    const planId = _planIdFromLocation();
    if (!planId) {
      _showEmpty('لم يتم تحديد الباقة المطلوبة.');
      return;
    }

    document.getElementById('summary-loading').style.display = '';
    const plansRes = await ApiClient.get('/api/subscriptions/plans/');
    document.getElementById('summary-loading').style.display = 'none';
    if (!plansRes.ok) {
      _showEmpty(plansRes.data?.detail || 'تعذر تحميل تفاصيل الباقة.');
      return;
    }

    const plan = _extractList(plansRes.data).find(item => Number(item.id) === planId);
    if (!plan) {
      _showEmpty();
      return;
    }

    _renderSummary(plan);
  }

  function _showEmpty(message) {
    const empty = document.getElementById('summary-empty');
    empty.style.display = '';
    if (message) {
      empty.innerHTML = `<p>${_safeText(message)}</p><a href="/plans/" class="btn btn-secondary">العودة إلى الباقات</a>`;
    }
  }

  function _offer(plan) {
    return plan && typeof plan === 'object' ? (plan.provider_offer || {}) : {};
  }

  function _renderRow(row) {
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
    const cta = offer.cta || {};
    const rows = Array.isArray(offer.summary_rows) ? offer.summary_rows : [];
    const features = Array.isArray(offer.feature_bullets) ? offer.feature_bullets : [];
    const canProceed = cta.enabled === true || cta.enabled === 1 || cta.enabled === '1' || cta.enabled === 'true';
    const buttonLabel = _valueToText(cta.label) || 'ترقية';

    const container = document.getElementById('summary-card');
    container.innerHTML = `
      <section class="plan-summary-layout">
        <article class="ps-hero-card">
          <div class="ps-hero-head">
            <div class="ps-hero-main">
              <div class="ps-title-row">
                <h2 class="ps-hero-title">${_safeText(offer.plan_name || plan.title || plan.name, 'الباقة')}</h2>
                <span class="ps-hero-chip">${_safeText(buttonLabel)}</span>
              </div>
              <p class="ps-hero-description">${_safeText(offer.description)}</p>
            </div>
            <div class="ps-price-chip">
              <div class="ps-price-label">المبلغ النهائي</div>
              <div class="ps-price-value">${_safeText(offer.final_payable_label, 'مجانية')}</div>
              <div class="ps-price-cycle">${_safeText(offer.billing_cycle_label, 'سنوي')}</div>
            </div>
          </div>
        </article>

        <article class="ps-card ps-details-card">
          <h3 class="ps-section-title">تفاصيل الاشتراك</h3>
          <div class="ps-details-grid">
            <div class="ps-details-row"><span>الباقة المختارة</span><strong>${_safeText(offer.plan_name || plan.title || plan.name)}</strong></div>
            <div class="ps-details-row"><span>دورة الفوترة</span><strong>${_safeText(offer.billing_cycle_label, 'سنوي')}</strong></div>
            <div class="ps-details-row"><span>سعر الباقة</span><strong>${_safeText(offer.annual_price_label, 'مجانية')}</strong></div>
            <div class="ps-details-row"><span>أثر التوثيق</span><strong>${_safeText(offer.verification_effect_label)}</strong></div>
            <div class="ps-details-row"><span>المبلغ النهائي المستحق</span><strong>${_safeText(offer.final_payable_label, 'مجانية')}</strong></div>
          </div>
          <div class="ps-tax-note">
            <strong>ملاحظة الضريبة</strong>
            ${_safeText(offer.tax_note)}
          </div>
        </article>

        <article class="ps-card ps-features-card">
          <h3 class="ps-section-title">المزايا الرئيسية</h3>
          <ul class="ps-features-list">
            ${features.map(item => `<li class="ps-feature-item"><span class="ps-feature-bullet">•</span><span>${_safeText(item)}</span></li>`).join('')}
          </ul>
        </article>

        <article class="ps-card ps-compare-card">
          <h3 class="ps-section-title">مقارنة سريعة</h3>
          <div>${rows.map(_renderRow).join('')}</div>
        </article>

        <div class="ps-action-row">
          <button id="summary-submit" class="btn btn-primary ps-submit-btn" ${canProceed ? '' : 'disabled'}>${_safeText(buttonLabel)}</button>
          <a href="/plans/" class="btn btn-secondary ps-back-btn">العودة إلى الباقات</a>
        </div>
      </section>
    `;

    if (canProceed) {
      document.getElementById('summary-submit').addEventListener('click', () => _subscribe(plan, offer));
    }
  }

  async function _subscribe(plan, offer) {
    const button = document.getElementById('summary-submit');
    if (button) button.disabled = true;
    const res = await ApiClient.request(`/api/subscriptions/subscribe/${plan.id}/`, {
      method: 'POST',
    });
    if (button) button.disabled = false;
    if (!res.ok) {
      alert(_valueToText(res.data?.detail) || 'تعذر إنشاء طلب الترقية');
      return;
    }
    const amountLabel = _valueToText(offer.final_payable_label) || _valueToText(offer.annual_price_label) || 'مجانية';
    alert(`تم إنشاء طلب الاشتراك بنجاح. المبلغ النهائي: ${amountLabel}`);
    window.location.href = '/plans/';
  }

  document.addEventListener('DOMContentLoaded', init);
  return { init };
})();
