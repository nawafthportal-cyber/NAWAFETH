'use strict';

const PlansPage = (() => {
  function _extractList(payload) {
    if (Array.isArray(payload)) return payload;
    if (payload && Array.isArray(payload.results)) return payload.results;
    return [];
  }

  function _offer(plan) {
    return plan && typeof plan === 'object' ? (plan.provider_offer || {}) : {};
  }

  function _cta(plan) {
    const offer = _offer(plan);
    return offer && typeof offer === 'object' ? (offer.cta || {}) : {};
  }

  function _planTheme(tier) {
    switch (String(tier || '').trim().toLowerCase()) {
      case 'professional':
        return {
          shell: 'linear-gradient(135deg,#123c32,#0f766e)',
          accent: '#D1FAE5',
          badge: '#ECFDF5',
          text: '#083344',
        };
      case 'pioneer':
        return {
          shell: 'linear-gradient(135deg,#0f4c5c,#2a9d8f)',
          accent: '#D7F9F1',
          badge: '#F0FDFA',
          text: '#0F3D3E',
        };
      default:
        return {
          shell: 'linear-gradient(135deg,#5f6f52,#a3b18a)',
          accent: '#F1F5E8',
          badge: '#FEFCE8',
          text: '#3F4A31',
        };
    }
  }

  function _statusBadge(offer) {
    const cta = offer.cta || {};
    if (!cta.state) return '';
    if (cta.state === 'current' || cta.state === 'pending') {
      return `<span style="display:inline-flex;padding:5px 10px;border-radius:999px;background:${offer._theme.badge};color:${offer._theme.text};font-size:12px;font-weight:700">${UI.text(cta.label || '')}</span>`;
    }
    if (cta.state === 'unavailable') {
      return `<span style="display:inline-flex;padding:5px 10px;border-radius:999px;background:rgba(255,255,255,.2);color:#fff;font-size:12px;font-weight:700">باقة أقل من الحالية</span>`;
    }
    return '';
  }

  function _buildRow(row) {
    return `
      <li class="plan-feature" style="display:flex;align-items:flex-start;justify-content:space-between;gap:12px;padding:10px 0;border-bottom:1px solid rgba(255,255,255,.14)">
        <span style="font-size:13px;color:rgba(255,255,255,.78)">${UI.text(row.label || '')}</span>
        <strong style="font-size:13px;color:#fff;text-align:left">${UI.text(row.value || '')}</strong>
      </li>
    `;
  }

  function init() {
    if (!Auth.isLoggedIn()) {
      document.getElementById('auth-gate').style.display = '';
      return;
    }
    document.getElementById('plans-content').style.display = '';
    _loadPlans();
  }

  async function _loadPlans() {
    document.getElementById('plans-loading').style.display = '';
    const plansRes = await ApiClient.get('/api/subscriptions/plans/');
    document.getElementById('plans-loading').style.display = 'none';
    if (!plansRes.ok) {
      document.getElementById('plans-empty').style.display = '';
      document.getElementById('plans-empty').innerHTML = `<p>${UI.text(plansRes.data?.detail || 'تعذر تحميل الباقات حالياً')}</p>`;
      return;
    }

    const plans = _extractList(plansRes.data);
    if (!plans.length) {
      document.getElementById('plans-empty').style.display = '';
      return;
    }

    const container = document.getElementById('plans-list');
    container.innerHTML = '';
    const frag = document.createDocumentFragment();
    plans.forEach(plan => frag.appendChild(_buildPlanCard(plan)));
    container.appendChild(frag);
  }

  function _buildPlanCard(plan) {
    const offer = _offer(plan);
    const theme = _planTheme(plan.canonical_tier || offer.tier);
    offer._theme = theme;
    const cta = _cta(plan);
    const rows = Array.isArray(offer.card_rows) ? offer.card_rows : [];
    const buttonLabel = cta.label || 'ترقية';
    const isEnabled = Boolean(cta.enabled);
    const buttonClass = isEnabled ? 'btn btn-primary' : 'btn btn-secondary';
    const actionHint = cta.current_plan_name
      ? `<p style="margin:10px 0 0;color:rgba(255,255,255,.72);font-size:12px">الباقة الحالية: ${UI.text(cta.current_plan_name)}</p>`
      : '';

    const card = document.createElement('article');
    card.className = 'plan-card';
    card.style.background = theme.shell;
    card.style.borderRadius = '26px';
    card.style.padding = '22px';
    card.style.boxShadow = '0 14px 34px rgba(15,23,42,.12)';
    card.style.color = '#fff';

    card.innerHTML = `
      <div style="display:flex;align-items:flex-start;justify-content:space-between;gap:16px">
        <div>
          <div style="display:flex;align-items:center;gap:10px;flex-wrap:wrap">
            <h2 style="margin:0;font-size:24px;font-weight:800">${UI.text(offer.plan_name || plan.title || 'باقة')}</h2>
            ${_statusBadge(offer)}
          </div>
          <p style="margin:10px 0 0;color:rgba(255,255,255,.82);line-height:1.8">${UI.text(offer.description || '')}</p>
        </div>
        <div style="min-width:120px;padding:12px 14px;border-radius:18px;background:rgba(255,255,255,.14);text-align:center">
          <div style="font-size:12px;color:rgba(255,255,255,.72)">السعر السنوي</div>
          <div style="margin-top:6px;font-size:20px;font-weight:800">${UI.text(offer.annual_price_label || 'مجانية')}</div>
        </div>
      </div>
      <div style="margin-top:18px;padding:16px;border-radius:20px;background:rgba(255,255,255,.08)">
        <div style="font-size:13px;color:rgba(255,255,255,.72);margin-bottom:10px">أهم التفاصيل</div>
        <ul class="plan-features" style="margin:0;padding:0;list-style:none">${rows.map(_buildRow).join('')}</ul>
      </div>
      <div style="margin-top:18px;display:flex;align-items:center;justify-content:space-between;gap:16px;flex-wrap:wrap">
        <div>
          <div style="font-size:13px;color:rgba(255,255,255,.72)">أثر الباقة على التوثيق</div>
          <div style="margin-top:6px;font-weight:700">${UI.text(offer.verification_effect_label || '')}</div>
          ${actionHint}
        </div>
        <button class="${buttonClass}" style="min-width:140px" ${isEnabled ? '' : 'disabled'}>${UI.text(buttonLabel)}</button>
      </div>
    `;

    if (isEnabled) {
      card.querySelector('button').addEventListener('click', () => {
        window.location.href = `/plans/summary/?plan_id=${encodeURIComponent(plan.id)}`;
      });
    }
    return card;
  }

  document.addEventListener('DOMContentLoaded', init);
  return { init };
})();
