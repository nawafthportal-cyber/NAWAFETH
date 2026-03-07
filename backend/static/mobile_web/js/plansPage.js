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
      return `<span class="plan-status plan-status-current">${UI.text(cta.label || '')}</span>`;
    }
    if (cta.state === 'unavailable') {
      return '<span class="plan-status plan-status-unavailable">باقة أقل من الحالية</span>';
    }
    return '';
  }

  function _buildRow(row) {
    return `
      <li class="plan-feature">
        <span class="plan-feature-label">${UI.text(row.label || '')}</span>
        <strong class="plan-feature-value">${UI.text(row.value || '')}</strong>
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
    const cta = _cta(plan);
    const rows = Array.isArray(offer.card_rows) ? offer.card_rows : [];
    const buttonLabel = cta.label || 'ترقية';
    const isEnabled = Boolean(cta.enabled);
    const buttonClass = isEnabled ? 'btn btn-primary' : 'btn btn-secondary';
    const actionHint = cta.current_plan_name
      ? `<p class="plan-current-hint">الباقة الحالية: ${UI.text(cta.current_plan_name)}</p>`
      : '';

    const card = document.createElement('article');
    card.className = 'plan-card plan-card-rich';
    card.style.setProperty('--plan-shell', theme.shell);
    card.style.setProperty('--plan-badge-bg', theme.badge);
    card.style.setProperty('--plan-badge-text', theme.text);

    card.innerHTML = `
      <div class="plan-head">
        <div class="plan-head-main">
          <div class="plan-title-row">
            <h2 class="plan-title">${UI.text(offer.plan_name || plan.title || 'باقة')}</h2>
            ${_statusBadge(offer)}
          </div>
          <p class="plan-description">${UI.text(offer.description || '')}</p>
        </div>
        <div class="plan-price-chip">
          <div class="plan-price-label">السعر السنوي</div>
          <div class="plan-price-value">${UI.text(offer.annual_price_label || 'مجانية')}</div>
        </div>
      </div>
      <div class="plan-details-box">
        <div class="plan-details-title">أهم التفاصيل</div>
        <ul class="plan-features plan-features-list">${rows.map(_buildRow).join('')}</ul>
      </div>
      <div class="plan-footer-row">
        <div class="plan-effect-wrap">
          <div class="plan-effect-label">أثر الباقة على التوثيق</div>
          <div class="plan-effect-value">${UI.text(offer.verification_effect_label || '')}</div>
          ${actionHint}
        </div>
        <button class="${buttonClass} plan-cta-btn" ${isEnabled ? '' : 'disabled'}>${UI.text(buttonLabel)}</button>
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
