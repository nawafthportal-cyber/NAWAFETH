/* ===================================================================
   notificationSettingsPage.js — Notification preferences
   GET/PATCH /api/notifications/preferences/
   =================================================================== */
'use strict';

const NotificationSettingsPage = (() => {
  const TIER_ORDER = ['basic', 'pioneer', 'professional', 'extra'];
  const TIER_LABELS = {
    basic: 'الباقة الأساسية',
    pioneer: 'الباقة الريادية',
    professional: 'الباقة الاحترافية',
    extra: 'الباقة المميزة',
  };
  const TIER_ICONS = {
    basic: '⭐',
    pioneer: '🚀',
    professional: '✨',
    extra: '💎',
  };
  const TIER_ALIASES = {
    basic: 'basic',
    leading: 'pioneer',
    pioneer: 'pioneer',
    professional: 'professional',
    pro: 'professional',
    extra: 'extra',
  };

  let _prefs = [];
  const _savingKeys = new Set();

  function init() {
    if (!Auth.isLoggedIn()) {
      _showGate();
      return;
    }
    _hideGate();
    _load();
  }

  function _showGate() {
    const gate = document.getElementById('auth-gate');
    const content = document.getElementById('notif-settings-content');
    if (gate) gate.classList.remove('hidden');
    if (content) content.classList.add('hidden');
  }

  function _hideGate() {
    const gate = document.getElementById('auth-gate');
    const content = document.getElementById('notif-settings-content');
    if (gate) gate.classList.add('hidden');
    if (content) content.classList.remove('hidden');
  }

  async function _load() {
    _setLoading(true);
    _setError('');
    const res = await ApiClient.get('/api/notifications/preferences/');
    _setLoading(false);

    if (!res.ok || !res.data) {
      _setError((res.data && res.data.detail) || 'فشل تحميل إعدادات الإشعارات');
      return;
    }

    _prefs = Array.isArray(res.data.results) ? res.data.results : [];
    _render();
  }

  function _setLoading(loading) {
    const loadingEl = document.getElementById('notif-settings-loading');
    const list = document.getElementById('notif-settings-list');
    if (loadingEl) loadingEl.classList.toggle('hidden', !loading);
    if (list && loading) list.classList.add('hidden');
  }

  function _setError(message) {
    const errorEl = document.getElementById('notif-settings-error');
    if (!errorEl) return;
    if (!message) {
      errorEl.textContent = '';
      errorEl.classList.add('hidden');
      return;
    }
    errorEl.textContent = message;
    errorEl.classList.remove('hidden');
  }

  function _groupByTier() {
    const grouped = {};
    _prefs.forEach((pref) => {
      const tier = _normalizeTier(pref);
      if (!grouped[tier]) grouped[tier] = [];
      grouped[tier].push(pref);
    });
    return grouped;
  }

  function _normalizeTier(pref) {
    const raw = String((pref && (pref.canonical_tier || pref.tier)) || 'basic').trim().toLowerCase();
    return TIER_ALIASES[raw] || raw || 'basic';
  }

  function _render() {
    const list = document.getElementById('notif-settings-list');
    if (!list) return;
    list.innerHTML = '';

    const grouped = _groupByTier();
    const tiers = [
      ...TIER_ORDER.filter((tier) => grouped[tier]),
      ...Object.keys(grouped).filter((tier) => !TIER_ORDER.includes(tier)),
    ];

    if (!tiers.length) {
      const empty = UI.el('div', { className: 'empty-hint' }, [
        UI.el('p', { textContent: 'لا توجد إعدادات متاحة حالياً' }),
      ]);
      list.appendChild(empty);
      list.classList.remove('hidden');
      return;
    }

    tiers.forEach((tier) => {
      list.appendChild(_buildTierCard(tier, grouped[tier]));
    });

    list.classList.remove('hidden');
  }

  function _buildTierCard(tier, prefs) {
    const card = UI.el('article', { className: 'tier-card' });
    const head = UI.el('header', { className: 'tier-head' });
    const label = TIER_LABELS[tier] || tier;
    const icon = TIER_ICONS[tier] || '🔔';

    head.appendChild(UI.el('span', { className: 'tier-icon', textContent: icon }));
    head.appendChild(UI.el('h2', { className: 'tier-title', textContent: label }));
    head.appendChild(
      UI.el('span', {
        className: 'tier-count',
        textContent: prefs.filter((p) => p.enabled && !p.locked).length + '/' + prefs.length,
      }),
    );
    card.appendChild(head);

    const body = UI.el('div', { className: 'tier-body' });
    prefs.forEach((pref) => {
      body.appendChild(_buildPrefRow(pref));
    });
    card.appendChild(body);

    return card;
  }

  function _buildPrefRow(pref) {
    const row = UI.el('label', {
      className: 'pref-row' + (pref.locked ? ' locked' : ''),
    });

    const info = UI.el('span', { className: 'pref-info' });
    info.appendChild(UI.el('span', { className: 'pref-title', textContent: pref.title || pref.key }));
    if (pref.locked) {
      info.appendChild(UI.el('span', { className: 'pref-subtitle', textContent: 'يتطلب ترقية الباقة' }));
    }
    row.appendChild(info);

    const controlWrap = UI.el('span', { className: 'pref-control' });
    if (pref.locked) {
      controlWrap.appendChild(UI.el('span', { className: 'pref-lock', textContent: '🔒' }));
    } else if (_savingKeys.has(pref.key)) {
      controlWrap.appendChild(UI.el('span', { className: 'spinner-inline pref-spinner' }));
    } else {
      const input = UI.el('input', {
        type: 'checkbox',
        className: 'pref-switch',
      });
      input.checked = !!pref.enabled;
      input.addEventListener('change', (e) => {
        e.preventDefault();
        _toggle(pref, input.checked);
      });
      controlWrap.appendChild(input);
    }
    row.appendChild(controlWrap);

    if (pref.locked) {
      row.addEventListener('click', (e) => {
        e.preventDefault();
        _showUpgradeDialog();
      });
    }

    return row;
  }

  async function _toggle(pref, enabled) {
    if (pref.locked || _savingKeys.has(pref.key)) {
      if (pref.locked) _showUpgradeDialog();
      return;
    }

    _savingKeys.add(pref.key);
    _render();

    const res = await ApiClient.request('/api/notifications/preferences/', {
      method: 'PATCH',
      body: { updates: [{ key: pref.key, enabled }] },
    });

    _savingKeys.delete(pref.key);

    if (!res.ok) {
      alert('فشل حفظ الإعداد');
      _render();
      return;
    }

    _prefs = _prefs.map((p) => (
      p.key === pref.key
        ? { ...p, enabled: enabled }
        : p
    ));
    _render();
  }

  function _showUpgradeDialog() {
    alert('هذه الإشعارات تتطلب ترقية الباقة.');
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  return {};
})();
