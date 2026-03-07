'use strict';

const PlanSummaryPage = (() => {
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
      empty.innerHTML = `<p>${UI.text(message)}</p><a href="/plans/" class="btn btn-secondary">العودة إلى الباقات</a>`;
    }
  }

  function _offer(plan) {
    return plan && typeof plan === 'object' ? (plan.provider_offer || {}) : {};
  }

  function _renderRow(row) {
    return `
      <div class="ps-compare-row">
        <span class="ps-compare-label">${UI.text(row.label || '')}</span>
        <strong class="ps-compare-value">${UI.text(row.value || '')}</strong>
      </div>
    `;
  }

  function _renderSummary(plan) {
    const offer = _offer(plan);
    const cta = offer.cta || {};
    const rows = Array.isArray(offer.summary_rows) ? offer.summary_rows : [];
    const features = Array.isArray(offer.feature_bullets) ? offer.feature_bullets : [];
    const canProceed = Boolean(cta.enabled);
    const buttonLabel = cta.label || 'ترقية';

    const container = document.getElementById('summary-card');
    container.innerHTML = `
      <section class="plan-summary-layout">
        <article class="ps-hero-card">
          <div class="ps-hero-head">
            <div class="ps-hero-main">
              <div class="ps-title-row">
                <h2 class="ps-hero-title">${UI.text(offer.plan_name || plan.title || 'الباقة')}</h2>
                <span class="ps-hero-chip">${UI.text(buttonLabel)}</span>
              </div>
              <p class="ps-hero-description">${UI.text(offer.description || '')}</p>
            </div>
            <div class="ps-price-chip">
              <div class="ps-price-label">المبلغ النهائي</div>
              <div class="ps-price-value">${UI.text(offer.final_payable_label || 'مجانية')}</div>
              <div class="ps-price-cycle">${UI.text(offer.billing_cycle_label || 'سنوي')}</div>
            </div>
          </div>
        </article>

        <article class="ps-card ps-details-card">
          <h3 class="ps-section-title">تفاصيل الاشتراك</h3>
          <div class="ps-details-grid">
            <div class="ps-details-row"><span>الباقة المختارة</span><strong>${UI.text(offer.plan_name || plan.title || '')}</strong></div>
            <div class="ps-details-row"><span>دورة الفوترة</span><strong>${UI.text(offer.billing_cycle_label || 'سنوي')}</strong></div>
            <div class="ps-details-row"><span>سعر الباقة</span><strong>${UI.text(offer.annual_price_label || 'مجانية')}</strong></div>
            <div class="ps-details-row"><span>أثر التوثيق</span><strong>${UI.text(offer.verification_effect_label || '')}</strong></div>
            <div class="ps-details-row"><span>المبلغ النهائي المستحق</span><strong>${UI.text(offer.final_payable_label || 'مجانية')}</strong></div>
          </div>
          <div class="ps-tax-note">
            <strong>ملاحظة الضريبة</strong>
            ${UI.text(offer.tax_note || '')}
          </div>
        </article>

        <article class="ps-card ps-features-card">
          <h3 class="ps-section-title">المزايا الرئيسية</h3>
          <ul class="ps-features-list">
            ${features.map(item => `<li class="ps-feature-item"><span class="ps-feature-bullet">•</span><span>${UI.text(item || '')}</span></li>`).join('')}
          </ul>
        </article>

        <article class="ps-card ps-compare-card">
          <h3 class="ps-section-title">مقارنة سريعة</h3>
          <div>${rows.map(_renderRow).join('')}</div>
        </article>

        <div class="ps-action-row">
          <button id="summary-submit" class="btn btn-primary ps-submit-btn" ${canProceed ? '' : 'disabled'}>${UI.text(buttonLabel)}</button>
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
      alert(res.data?.detail || 'تعذر إنشاء طلب الترقية');
      return;
    }
    const amountLabel = offer.final_payable_label || offer.annual_price_label || 'مجانية';
    alert(`تم إنشاء طلب الاشتراك بنجاح. المبلغ النهائي: ${amountLabel}`);
    window.location.href = '/plans/';
  }

  document.addEventListener('DOMContentLoaded', init);
  return { init };
})();
