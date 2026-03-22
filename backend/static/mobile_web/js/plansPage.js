'use strict';

const PlansPage = (() => {
  const EMPTY_MESSAGE = 'لا توجد باقات متاحة حالياً';

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

  function _safeText(value, fallback = '') {
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

  function _asBool(value) {
    if (value === true || value === 1 || value === '1') return true;
    const text = _valueToText(value).toLowerCase();
    return text === 'true' || text === 'yes';
  }

  function _planTheme(tier) {
    switch (_valueToText(tier).toLowerCase()) {
      case 'professional':
        return {
          shell: 'linear-gradient(135deg,#123c32,#0f766e)',
          accent: '#0F766E',
          badge: 'rgba(255,255,255,0.86)',
        };
      case 'pioneer':
        return {
          shell: 'linear-gradient(135deg,#0f4c5c,#2a9d8f)',
          accent: '#2A9D8F',
          badge: 'rgba(255,255,255,0.86)',
        };
      default:
        return {
          shell: 'linear-gradient(135deg,#5f6f52,#a3b18a)',
          accent: '#A3B18A',
          badge: 'rgba(255,255,255,0.86)',
        };
    }
  }

  function _statusBadge(action) {
    const state = _valueToText(action.state).toLowerCase();
    if (state === 'current' || state === 'pending') {
      return `<span class="plan-status">${_safeText(action.label)}</span>`;
    }
    if (state === 'unavailable') {
      return '<span class="plan-status">باقة أقل من الحالية</span>';
    }
    return '';
  }

  function _buildRow(row) {
    const item = row && typeof row === 'object' ? row : {};
    const label = item.label ?? item.title ?? item.name;
    const value = item.value ?? item.text ?? item.amount;
    return `
      <div class="plan-feature">
        <span class="plan-feature-label">${_safeText(label)}</span>
        <strong class="plan-feature-value">${_safeText(value)}</strong>
      </div>
    `;
  }

  function init() {
    const retryButton = document.getElementById('plans-retry');
    if (retryButton) {
      retryButton.addEventListener('click', _loadPlans);
    }

    if (!Auth.isLoggedIn()) {
      _showAuthGate();
      return;
    }
    _showContent();
    _loadPlans();
  }

  async function _loadPlans() {
    _setLoading(true);

    try {
      const plansRes = await ApiClient.get('/api/subscriptions/plans/');
      if (!plansRes.ok) {
        _showState(EMPTY_MESSAGE);
        return;
      }

      const plans = _extractList(plansRes.data);
      if (!plans.length) {
        _showState(EMPTY_MESSAGE);
        return;
      }

      _renderPlans(plans);
    } catch (_) {
      _showState(EMPTY_MESSAGE);
    } finally {
      _setLoading(false);
    }
  }

  function _showAuthGate() {
    const gate = document.getElementById('auth-gate');
    const content = document.getElementById('plans-content');
    if (gate) gate.classList.remove('hidden');
    if (content) content.classList.add('hidden');
  }

  function _showContent() {
    const gate = document.getElementById('auth-gate');
    const content = document.getElementById('plans-content');
    if (gate) gate.classList.add('hidden');
    if (content) content.classList.remove('hidden');
  }

  function _setLoading(isLoading) {
    const loading = !!isLoading;
    const loader = document.getElementById('plans-loading');
    const list = document.getElementById('plans-list');
    const state = document.getElementById('plans-state');
    const retry = document.getElementById('plans-retry');

    if (loader) loader.classList.toggle('hidden', !loading);
    if (retry) retry.disabled = loading;

    if (loading) {
      if (list) list.classList.add('hidden');
      if (state) state.classList.add('hidden');
    }
  }

  function _showState(message) {
    const list = document.getElementById('plans-list');
    const state = document.getElementById('plans-state');
    const messageEl = document.getElementById('plans-state-message');
    if (list) list.classList.add('hidden');
    if (state) state.classList.remove('hidden');
    if (messageEl) messageEl.textContent = _valueToText(message) || EMPTY_MESSAGE;
  }

  function _renderPlans(plans) {
    const container = document.getElementById('plans-list');
    const state = document.getElementById('plans-state');
    if (!container) return;
    container.innerHTML = '';
    const frag = document.createDocumentFragment();
    plans.forEach((plan) => frag.appendChild(_buildPlanCard(plan)));
    container.appendChild(frag);
    container.classList.remove('hidden');
    if (state) state.classList.add('hidden');
  }

  function _buildPlanCard(plan) {
    const offer = _offer(plan);
    const theme = _planTheme(plan.canonical_tier || offer.tier);
    const cta = _cta(plan);
    const rows = Array.isArray(offer.card_rows) ? offer.card_rows : [];
    const buttonLabel = _valueToText(cta.label) || 'ترقية';
    const isEnabled = _asBool(cta.enabled);
    const badge = _statusBadge(cta);

    const card = document.createElement('article');
    card.className = 'plan-card plan-card-rich';
    card.style.setProperty('--plan-shell', theme.shell);
    card.style.setProperty('--plan-badge-bg', theme.badge);
    card.style.setProperty('--plan-badge-text', theme.accent);
    card.style.setProperty('--plan-accent', theme.accent);

    card.innerHTML = `
      <div class="plan-head">
        <div class="plan-head-main">
          <div class="plan-title-row">
            <h2 class="plan-title">${_safeText(offer.plan_name || plan.title || plan.name, 'باقة')}</h2>
            ${badge}
          </div>
          <p class="plan-description">${_safeText(offer.description)}</p>
        </div>
        <div class="plan-price-chip">
          <div class="plan-price-label">السعر السنوي</div>
          <div class="plan-price-value">${_safeText(offer.annual_price_label, 'مجانية')}</div>
        </div>
      </div>
      <div class="plan-details-box">
        <div class="plan-features plan-features-list">${rows.map(_buildRow).join('')}</div>
      </div>
      <div class="plan-footer-row">
        <p class="plan-effect-text">أثر الباقة على التوثيق: ${_safeText(offer.verification_effect_label)}</p>
        <button class="plan-cta-btn" ${isEnabled ? '' : 'disabled'}>${_safeText(buttonLabel)}</button>
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
