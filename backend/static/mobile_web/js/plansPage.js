/* ===================================================================
   plansPage.js — Subscription Plans (الباقات المدفوعة)
   1:1 parity with Flutter plans_screen.dart
   =================================================================== */
'use strict';

const PlansPage = (() => {
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
    const res = await ApiClient.get('/api/subscriptions/plans/');
    document.getElementById('plans-loading').style.display = 'none';
    if (!res.ok) return;
    const plans = res.data?.results || res.data || [];
    if (!plans.length) {
      document.getElementById('plans-empty').style.display = '';
      return;
    }
    const container = document.getElementById('plans-list');
    const frag = document.createDocumentFragment();
    plans.forEach((plan, i) => frag.appendChild(_buildPlanCard(plan, i)));
    container.appendChild(frag);
  }

  function _buildPlanCard(plan, index) {
    const card = document.createElement('div');
    card.className = 'plan-card';
    if (index === 1) card.classList.add('plan-featured'); // 2nd plan highlighted

    const features = (plan.features || plan.feature_list || []);
    const featureHtml = features.map(f =>
      `<li class="plan-feature"><svg width="16" height="16" viewBox="0 0 24 24" fill="#4CAF50"><path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41L9 16.17z"/></svg>${UI.text(typeof f === 'string' ? f : f.name || f.title || '')}</li>`
    ).join('');

    const price = plan.price || plan.monthly_price || 0;
    const name = plan.name || plan.title || 'باقة';

    card.innerHTML = `
      <div class="plan-header" style="background:${_planColor(index)}">
        <h3 class="plan-name">${UI.text(name)}</h3>
        <div class="plan-price">
          <span class="plan-amount">${price}</span>
          <span class="plan-currency">ر.س / شهر</span>
        </div>
      </div>
      <div class="plan-body">
        <p class="plan-desc">${UI.text(plan.description || '')}</p>
        <ul class="plan-features">${featureHtml}</ul>
      </div>
      <div class="plan-footer">
        <button class="btn btn-primary btn-block plan-subscribe-btn" data-id="${plan.id}">اشترك الآن</button>
      </div>
    `;

    card.querySelector('.plan-subscribe-btn').addEventListener('click', () => _subscribe(plan));
    return card;
  }

  async function _subscribe(plan) {
    if (!confirm(`هل تريد الاشتراك في ${plan.name || 'هذه الباقة'}؟`)) return;
    const res = await ApiClient.request('/api/subscriptions/subscribe/', {
      method: 'POST',
      body: { plan_id: plan.id }
    });
    if (res.ok) {
      alert('تم الاشتراك بنجاح!');
      location.reload();
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
