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
      <div style="display:flex;align-items:flex-start;justify-content:space-between;gap:16px;padding:14px 0;border-bottom:1px solid #e5e7eb">
        <span style="color:#475569;font-size:14px">${UI.text(row.label || '')}</span>
        <strong style="color:#0f172a;font-size:14px;text-align:left">${UI.text(row.value || '')}</strong>
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
      <section style="display:grid;gap:18px">
        <article style="background:linear-gradient(135deg,#0f4c5c,#2a9d8f);border-radius:28px;padding:24px;color:#fff;box-shadow:0 18px 40px rgba(15,76,92,.18)">
          <div style="display:flex;align-items:flex-start;justify-content:space-between;gap:16px;flex-wrap:wrap">
            <div>
              <div style="display:flex;align-items:center;gap:10px;flex-wrap:wrap">
                <h2 style="margin:0;font-size:28px;font-weight:900">${UI.text(offer.plan_name || plan.title || 'الباقة')}</h2>
                <span style="display:inline-flex;padding:6px 12px;border-radius:999px;background:rgba(255,255,255,.14);font-size:12px">${UI.text(buttonLabel)}</span>
              </div>
              <p style="margin:10px 0 0;color:rgba(255,255,255,.82);line-height:1.9">${UI.text(offer.description || '')}</p>
            </div>
            <div style="min-width:150px;border-radius:22px;background:rgba(255,255,255,.12);padding:14px 16px;text-align:center">
              <div style="font-size:12px;color:rgba(255,255,255,.74)">المبلغ النهائي</div>
              <div style="margin-top:6px;font-size:24px;font-weight:900">${UI.text(offer.final_payable_label || 'مجانية')}</div>
              <div style="margin-top:4px;font-size:12px;color:rgba(255,255,255,.72)">${UI.text(offer.billing_cycle_label || 'سنوي')}</div>
            </div>
          </div>
        </article>

        <article style="background:#fff;border-radius:24px;padding:22px;box-shadow:0 12px 34px rgba(15,23,42,.08)">
          <h3 style="margin:0 0 14px;font-size:18px;color:#0f172a">تفاصيل الاشتراك</h3>
          <div style="display:grid;gap:12px;margin-bottom:10px">
            <div style="display:flex;justify-content:space-between;gap:16px"><span style="color:#64748b">الباقة المختارة</span><strong>${UI.text(offer.plan_name || plan.title || '')}</strong></div>
            <div style="display:flex;justify-content:space-between;gap:16px"><span style="color:#64748b">دورة الفوترة</span><strong>${UI.text(offer.billing_cycle_label || 'سنوي')}</strong></div>
            <div style="display:flex;justify-content:space-between;gap:16px"><span style="color:#64748b">سعر الباقة</span><strong>${UI.text(offer.annual_price_label || 'مجانية')}</strong></div>
            <div style="display:flex;justify-content:space-between;gap:16px"><span style="color:#64748b">أثر التوثيق</span><strong>${UI.text(offer.verification_effect_label || '')}</strong></div>
            <div style="display:flex;justify-content:space-between;gap:16px"><span style="color:#64748b">المبلغ النهائي المستحق</span><strong>${UI.text(offer.final_payable_label || 'مجانية')}</strong></div>
          </div>
          <div style="margin-top:14px;padding:14px 16px;border-radius:18px;background:#f8fafc;color:#334155;line-height:1.9">
            <strong style="display:block;color:#0f172a;margin-bottom:6px">ملاحظة الضريبة</strong>
            ${UI.text(offer.tax_note || '')}
          </div>
        </article>

        <article style="background:#fff;border-radius:24px;padding:22px;box-shadow:0 12px 34px rgba(15,23,42,.08)">
          <h3 style="margin:0 0 14px;font-size:18px;color:#0f172a">المزايا الرئيسية</h3>
          <ul style="margin:0;padding:0;list-style:none">
            ${features.map(item => `<li style="display:flex;gap:10px;align-items:flex-start;padding:8px 0;color:#1e293b"><span style="color:#0f766e;font-weight:900">•</span><span>${UI.text(item || '')}</span></li>`).join('')}
          </ul>
        </article>

        <article style="background:#fff;border-radius:24px;padding:22px;box-shadow:0 12px 34px rgba(15,23,42,.08)">
          <h3 style="margin:0 0 14px;font-size:18px;color:#0f172a">مقارنة سريعة</h3>
          <div>${rows.map(_renderRow).join('')}</div>
        </article>

        <div style="display:flex;gap:12px;flex-wrap:wrap">
          <button id="summary-submit" class="btn btn-primary" style="min-width:180px" ${canProceed ? '' : 'disabled'}>${UI.text(buttonLabel)}</button>
          <a href="/plans/" class="btn btn-secondary">العودة إلى الباقات</a>
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
