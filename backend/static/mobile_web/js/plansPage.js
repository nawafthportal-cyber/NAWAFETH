'use strict';

const PlansPage = (() => {
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

  function _offer(plan) {
    return plan && typeof plan === 'object' ? (plan.provider_offer || {}) : {};
  }

  function _cta(plan) {
    const offer = _offer(plan);
    return offer && typeof offer === 'object' ? (offer.cta || {}) : {};
  }

  function _planTheme(tier) {
    switch (_valueToText(tier).toLowerCase()) {
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
    const state = _valueToText(cta.state).toLowerCase();
    if (!state) return '';
    if (state === 'current' || state === 'pending') {
      return `<span class="plan-status plan-status-current">${_safeText(cta.label)}</span>`;
    }
    if (state === 'unavailable') {
      return '<span class="plan-status plan-status-unavailable">باقة أقل من الحالية</span>';
    }
    return '';
  }

  function _buildRow(row) {
    const item = row && typeof row === 'object' ? row : {};
    const label = item.label ?? item.title ?? item.name;
    const value = item.value ?? item.text ?? item.amount;
    return `
      <li class="plan-feature">
        <span class="plan-feature-label">${_safeText(label)}</span>
        <strong class="plan-feature-value">${_safeText(value)}</strong>
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
      document.getElementById('plans-empty').innerHTML = `<p>${_safeText(plansRes.data?.detail, 'تعذر تحميل الباقات حالياً')}</p>`;
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
    const buttonLabel = _valueToText(cta.label) || 'ترقية';
    const isEnabled = cta.enabled === true || cta.enabled === 1 || cta.enabled === '1' || cta.enabled === 'true';
    const buttonClass = isEnabled ? 'btn btn-primary' : 'btn btn-secondary';
    const actionHint = cta.current_plan_name
      ? `<p class="plan-current-hint">الباقة الحالية: ${_safeText(cta.current_plan_name)}</p>`
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
            <h2 class="plan-title">${_safeText(offer.plan_name || plan.title || plan.name, 'باقة')}</h2>
            ${_statusBadge(offer)}
          </div>
          <p class="plan-description">${_safeText(offer.description)}</p>
        </div>
        <div class="plan-price-chip">
          <div class="plan-price-label">السعر السنوي</div>
          <div class="plan-price-value">${_safeText(offer.annual_price_label, 'مجانية')}</div>
        </div>
      </div>
      <div class="plan-details-box">
        <div class="plan-details-title">أهم التفاصيل</div>
        <ul class="plan-features plan-features-list">${rows.map(_buildRow).join('')}</ul>
      </div>
      <div class="plan-footer-row">
        <div class="plan-effect-wrap">
          <div class="plan-effect-label">أثر الباقة على التوثيق</div>
          <div class="plan-effect-value">${_safeText(offer.verification_effect_label)}</div>
          ${actionHint}
        </div>
        <button class="${buttonClass} plan-cta-btn" ${isEnabled ? '' : 'disabled'}>${_safeText(buttonLabel)}</button>
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
