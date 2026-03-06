/* ===================================================================
   plansPage.js — Subscription Plans (الباقات المدفوعة)
   1:1 parity with Flutter plans_screen.dart
   =================================================================== */
'use strict';

const PlansPage = (() => {
  let _currentSubscription = null;

  function _extractList(payload) {
    if (Array.isArray(payload)) return payload;
    if (payload && Array.isArray(payload.results)) return payload.results;
    return [];
  }

  function _statusCode(status) {
    return String(status || '').trim().toLowerCase();
  }

  function _subscriptionRank(sub) {
    switch (_statusCode(sub && sub.status)) {
      case 'active':
        return 0;
      case 'grace':
        return 1;
      case 'pending_payment':
        return 2;
      default:
        return 9;
    }
  }

  function _pickPreferredSubscription(subs) {
    if (!Array.isArray(subs) || !subs.length) return null;
    let best = subs[0];
    let bestRank = _subscriptionRank(best);
    for (const sub of subs) {
      const rank = _subscriptionRank(sub);
      if (rank < bestRank) {
        best = sub;
        bestRank = rank;
        if (rank === 0) break;
      }
    }
    return best;
  }

  function _statusLabel(status) {
    switch (_statusCode(status)) {
      case 'active':
        return 'نشط';
      case 'grace':
        return 'فترة سماح';
      case 'pending_payment':
        return 'بانتظار الدفع';
      case 'expired':
        return 'منتهي';
      case 'cancelled':
        return 'ملغي';
      default:
        return 'غير معروف';
    }
  }

  function _featureLabel(feature) {
    switch (String(feature || '').trim().toLowerCase()) {
      case 'verify_blue':
      case 'verify_green':
        return 'رسوم التوثيق تعتمد على فئة الباقة';
      case 'promo_ads':
        return 'إعلانات وترويج';
      case 'priority_support':
        return 'دعم أولوية';
      case 'extra_uploads':
        return 'سعة مرفقات إضافية';
      case 'advanced_analytics':
        return 'تحليلات متقدمة';
      default:
        return String(feature || '').replace(/_/g, ' ').trim();
    }
  }

  function _extractFeatures(plan) {
    const source = (Array.isArray(plan.feature_labels) && plan.feature_labels.length)
      ? plan.feature_labels
      : (plan.features || plan.feature_list || []);
    const out = [];
    source.forEach(item => {
      let label = '';
      if (typeof item === 'string') label = _featureLabel(item);
      else if (item && typeof item === 'object') label = String(item.name || item.title || '').trim();
      else label = String(item || '').trim();
      if (label && !out.includes(label)) out.push(label);
    });
    return out;
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
    const [plansRes, mySubsRes] = await Promise.all([
      ApiClient.get('/api/subscriptions/plans/'),
      ApiClient.get('/api/subscriptions/my/'),
    ]);
    document.getElementById('plans-loading').style.display = 'none';
    if (!plansRes.ok) return;

    const plans = _extractList(plansRes.data);
    _currentSubscription = mySubsRes.ok
      ? _pickPreferredSubscription(_extractList(mySubsRes.data))
      : null;

    if (!plans.length) {
      document.getElementById('plans-empty').style.display = '';
      return;
    }

    const container = document.getElementById('plans-list');
    container.innerHTML = '';
    const frag = document.createDocumentFragment();
    plans.forEach((plan, i) => frag.appendChild(_buildPlanCard(plan, i)));
    container.appendChild(frag);
  }

  function _buildPlanCard(plan, index) {
    const card = document.createElement('div');
    card.className = 'plan-card';
    if (index === 1) card.classList.add('plan-featured'); // 2nd plan highlighted

    const features = _extractFeatures(plan);
    const featureHtml = features.map(f =>
      `<li class="plan-feature"><svg width="16" height="16" viewBox="0 0 24 24" fill="#4CAF50"><path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41L9 16.17z"/></svg>${UI.text(typeof f === 'string' ? f : f.name || f.title || '')}</li>`
    ).join('');

    const price = plan.price || plan.monthly_price || 0;
    const name = plan.name || plan.title || 'باقة';
    const period = String(plan.period || 'month').toLowerCase();
    const periodLabel = String(plan.period_label || '').trim() || (period === 'year' ? 'سنة' : 'شهر');

    const currentPlanId = Number(_currentSubscription?.plan?.id || _currentSubscription?.plan_id || 0);
    const isCurrentPlan = currentPlanId > 0 && currentPlanId === Number(plan.id || 0);
    const currentStatus = _statusCode(_currentSubscription?.status);
    const isCurrentLocked = isCurrentPlan && ['active', 'grace', 'pending_payment'].includes(currentStatus);
    const actionLabel = isCurrentLocked
      ? (currentStatus === 'pending_payment' ? 'قيد التفعيل' : 'الباقة الحالية')
      : 'اشترك الآن';
    const badgeHtml = isCurrentPlan
      ? `<div style="margin-top:8px"><span style="display:inline-flex;padding:4px 10px;border-radius:999px;background:rgba(255,255,255,0.92);color:#4A148C;font-size:12px;font-weight:700">${UI.text(_statusLabel(currentStatus))}</span></div>`
      : '';

    card.innerHTML = `
      <div class="plan-header" style="background:${_planColor(index)}">
        <h3 class="plan-name">${UI.text(name)}</h3>
        <div class="plan-price">
          <span class="plan-amount">${price}</span>
          <span class="plan-currency">ر.س / ${periodLabel}</span>
        </div>
      </div>
      <div class="plan-body">
        <p class="plan-desc">${UI.text(plan.description || '')}</p>
        ${badgeHtml}
        <ul class="plan-features">${featureHtml}</ul>
      </div>
      <div class="plan-footer">
        <button class="btn btn-primary btn-block plan-subscribe-btn" data-id="${plan.id}" ${isCurrentLocked ? 'disabled' : ''}>${actionLabel}</button>
      </div>
    `;

    if (!isCurrentLocked) {
      card.querySelector('.plan-subscribe-btn').addEventListener('click', () => _subscribe(plan));
    }
    return card;
  }

  async function _subscribe(plan) {
    if (!plan?.id) return;
    const planName = plan.name || plan.title || 'هذه الباقة';
    if (!confirm(`هل تريد الاشتراك في ${planName}؟`)) return;
    const res = await ApiClient.request(`/api/subscriptions/subscribe/${plan.id}/`, {
      method: 'POST',
    });
    if (res.ok) {
      alert('تم الاشتراك بنجاح!');
      await _loadPlans();
    } else {
      alert(res.data?.detail || 'فشل الاشتراك');
    }
  }

  function _planColor(i) {
    const colors = ['linear-gradient(135deg,#663D90,#9C27B0)', 'linear-gradient(135deg,#FFD700,#FFA000)', 'linear-gradient(135deg,#4CAF50,#2E7D32)', 'linear-gradient(135deg,#2196F3,#1565C0)'];
    return colors[i % colors.length];
  }

  document.addEventListener('DOMContentLoaded', init);
  return { init };
})();
