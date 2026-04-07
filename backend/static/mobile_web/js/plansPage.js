'use strict';

const PlansPage = (() => {
  const EMPTY_MESSAGE = 'لا توجد باقات متاحة حالياً';
  const PLAN_ORDER = ['basic', 'riyadi', 'pro'];

  const COMPARE_ROWS = [
    {
      key: 'core_services',
      label: 'جميع الخدمات الأساسية للمنصة كعميل وكمختص',
      value: () => 'نعم',
    },
    {
      key: 'notifications_enabled',
      label: 'استلام التنبيهات',
      value: (plan) => _yesNo(_capabilities(plan).notifications_enabled),
    },
    {
      key: 'storage',
      label: 'السعة التخزينية المتاحة',
      value: (plan) => _safeValue(_capabilities(plan).storage && _capabilities(plan).storage.label),
    },
    {
      key: 'competitive_requests',
      label: 'استقبال طلبات الخدمات التنافسية',
      value: (plan) => _safeValue(_capabilities(plan).competitive_requests && _capabilities(plan).competitive_requests.visibility_label),
    },
    {
      key: 'banner_images',
      label: 'صور شعار المنصة (Banner)',
      value: (plan) => _safeValue(_capabilities(plan).banner_images && _capabilities(plan).banner_images.label),
    },
    {
      key: 'promo_chat_messages',
      label: 'التحكم برسائل المحادثات الدعائية',
      value: (plan) => _yesNo(_promotionalControls(plan).chat_messages),
    },
    {
      key: 'promo_notification_messages',
      label: 'التحكم برسائل التنبيه الدعائية',
      value: (plan) => _yesNo(_promotionalControls(plan).notification_messages),
    },
    {
      key: 'reminders',
      label: 'إرسال رسائل تنبيه للعملاء لتقييم الخدمة',
      value: (plan) => _safeValue(_capabilities(plan).reminders && _capabilities(plan).reminders.label),
    },
    {
      key: 'chats_quota',
      label: 'عدد المحادثات المباشرة',
      value: (plan) => _quotaValue(_capabilities(plan).messaging && _capabilities(plan).messaging.direct_chat_quota),
    },
    {
      key: 'verification_blue',
      label: 'التوثيق (شارة زرقاء)',
      value: (plan) => _safeValue(_offer(plan).verification_blue_label),
    },
    {
      key: 'verification_green',
      label: 'التوثيق (شارة خضراء)',
      value: (plan) => _safeValue(_offer(plan).verification_green_label),
    },
    {
      key: 'support_sla',
      label: 'الدعم الفني',
      value: (plan) => _safeValue(_capabilities(plan).support && _capabilities(plan).support.sla_label),
    },
    {
      key: 'annual_price',
      label: 'سعر الاشتراك السنوي',
      value: (plan) => _safeValue(_offer(plan).final_payable_label || _offer(plan).annual_price_label),
    },
  ];

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

  function _capabilities(plan) {
    return plan && typeof plan === 'object' ? (plan.capabilities || {}) : {};
  }

  function _promotionalControls(plan) {
    return _capabilities(plan).promotional_controls || {};
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
      case 'pro':
      case 'professional':
        return {
          shell: 'linear-gradient(180deg,#6d2f9b 0%,#7f45af 100%)',
          accent: '#fdb515',
          badge: 'rgba(255,221,114,0.2)',
        };
      case 'riyadi':
      case 'pioneer':
        return {
          shell: 'linear-gradient(180deg,#8f64be 0%,#a178cb 100%)',
          accent: '#1d2554',
          badge: 'rgba(255,255,255,0.18)',
        };
      default:
        return {
          shell: 'linear-gradient(180deg,#b69bd7 0%,#c8b2e1 100%)',
          accent: '#17366f',
          badge: 'rgba(255,255,255,0.16)',
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

  function _safeValue(value, fallback = '-') {
    const text = _valueToText(value);
    return text || fallback;
  }

  function _yesNo(value) {
    return _asBool(value) ? 'نعم' : '-';
  }

  function _quotaValue(value) {
    const parsed = Number(value || 0);
    if (Number.isFinite(parsed) && parsed > 0) return String(parsed);
    return '-';
  }

  function _canonicalTier(plan) {
    return _valueToText(plan && (plan.canonical_tier || (_offer(plan) && _offer(plan).tier))).toLowerCase();
  }

  function _orderedPlans(plans) {
    return [...plans].sort((left, right) => {
      const leftIndex = PLAN_ORDER.indexOf(_canonicalTier(left));
      const rightIndex = PLAN_ORDER.indexOf(_canonicalTier(right));
      const normalizedLeft = leftIndex === -1 ? 999 : leftIndex;
      const normalizedRight = rightIndex === -1 ? 999 : rightIndex;
      return normalizedLeft - normalizedRight;
    });
  }

  async function _syncAccountBadge() {
    const userPill = document.getElementById('plans-user-pill');
    if (!userPill) return;

    try {
      const profile = await Auth.getProfile();
      const displayName = _valueToText(profile && profile.display_name)
        || _valueToText(profile && profile.provider_display_name)
        || _valueToText(profile && profile.username)
        || 'حساب مقدم الخدمة';
      userPill.textContent = displayName;
    } catch (_) {
      userPill.textContent = 'حساب مقدم الخدمة';
    }
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
    _syncAccountBadge();
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
    const orderedPlans = _orderedPlans(plans);
    container.innerHTML = _buildComparisonLayout(orderedPlans);
    container.classList.remove('hidden');
    if (state) state.classList.add('hidden');

    orderedPlans.forEach((plan) => {
      const cta = _cta(plan);
      if (!_asBool(cta.enabled)) return;
      const button = document.querySelector(`[data-plan-upgrade-id="${String(plan.id)}"]`);
      if (!button) return;
      button.addEventListener('click', () => {
        window.location.href = `/plans/summary/?plan_id=${encodeURIComponent(plan.id)}`;
      });
    });
  }

  function _buildPlanHeader(plan) {
    const offer = _offer(plan);
    const cta = _cta(plan);
    const theme = _planTheme(_canonicalTier(plan));
    const title = _safeText(offer.plan_name || plan.title || plan.name, 'باقة');
    const badge = _statusBadge(cta);
    return `
      <div class="subs-plan-head" style="--subs-plan-shell:${theme.shell};--subs-plan-accent:${theme.accent};--subs-plan-badge:${theme.badge};">
        <div class="subs-plan-head-inner">
          <div class="subs-plan-title-row">
            <strong class="subs-plan-title">${title}</strong>
            ${badge}
          </div>
        </div>
      </div>
    `;
  }

  function _buildCompareCell(plan, row) {
    const value = row.value(plan);
    return `<td class="subs-compare-value">${_safeText(value)}</td>`;
  }

  function _buildActionCell(plan) {
    const cta = _cta(plan);
    const label = _safeText(_valueToText(cta.label) || 'ترقية');
    const enabled = _asBool(cta.enabled);
    const state = _valueToText(cta.state).toLowerCase();
    const extraClass = state === 'current' ? ' is-current' : (state === 'pending' ? ' is-pending' : '');
    return `
      <button
        type="button"
        class="subs-plan-action${extraClass}"
        ${enabled ? '' : 'disabled'}
        data-plan-upgrade-id="${String(plan.id)}"
      >${label}</button>
    `;
  }

  function _buildComparisonLayout(plans) {
    const rowsMarkup = COMPARE_ROWS.map((row) => {
      return `
        <tr>
          <th scope="row" class="subs-compare-feature">${_safeText(row.label)}</th>
          ${plans.map((plan) => _buildCompareCell(plan, row)).join('')}
        </tr>
      `;
    }).join('');

    return `
      <section class="subs-compare-board">
        <div class="subs-compare-table-wrap">
          <table class="subs-compare-table">
            <thead>
              <tr>
                <th class="subs-compare-feature-head">الباقات</th>
                ${plans.map((plan) => `<th class="subs-compare-plan-head-cell">${_buildPlanHeader(plan)}</th>`).join('')}
              </tr>
            </thead>
            <tbody>
              ${rowsMarkup}
            </tbody>
          </table>
        </div>

        <div class="subs-actions-grid subs-actions-grid-${plans.length}">
          <div class="subs-actions-spacer"></div>
          ${plans.map((plan) => `<div class="subs-action-slot">${_buildActionCell(plan)}</div>`).join('')}
        </div>

        <p class="subs-compare-helper">بالضغط على ترقية سيتم الانتقال إلى صفحة ملخص طلب الاشتراك والرسوم.</p>
      </section>
    `;
  }

  document.addEventListener('DOMContentLoaded', init);
  return { init };
})();
