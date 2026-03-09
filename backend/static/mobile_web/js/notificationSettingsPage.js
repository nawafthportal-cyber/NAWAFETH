/* ===================================================================
   notificationSettingsPage.js — Notification preferences
   GET/PATCH /api/notifications/preferences/
   =================================================================== */
'use strict';

const NotificationSettingsPage = (() => {
  const MODE_KEY = 'nw_account_mode';
  const SECTION_CONFIG = {
    basic: {
      key: 'basic',
      label: 'الباقة الأساسية',
      mountId: 'notif-basic-section',
      className: 'notif-tier-basic',
      items: [
        'new_request',
        'request_status_change',
        'urgent_request',
        'report_status_change',
        'new_chat_message',
        'service_reply',
        'platform_recommendations',
      ],
    },
    pioneer: {
      key: 'pioneer',
      label: 'الباقة الريادية',
      mountId: 'notif-leading-section',
      className: 'notif-tier-pioneer',
      items: [
        'new_follow',
        'new_comment_services',
        'new_like_profile',
        'new_like_services',
        'competitive_offer_request',
      ],
    },
    professional: {
      key: 'professional',
      label: 'الباقة الاحترافية',
      mountId: 'notif-professional-section',
      className: 'notif-tier-professional',
      items: [
        'positive_review',
        'negative_review',
        'new_provider_same_category',
        'highlight_same_category',
        'ads_and_offers',
      ],
    },
    extra: {
      key: 'extra',
      label: 'تنبيهات الخدمات الإضافية',
      mountId: 'notif-extra-section',
      className: 'notif-tier-extra',
      items: [
        'new_payment',
        'new_ad_visit',
        'report_completed',
        'verification_completed',
        'paid_subscription_completed',
        'customer_service_package_completed',
        'finance_package_completed',
        'scheduled_ticket_reminder',
      ],
      noteTitle: 'إدارة العملاء',
      noteBody: 'مخصص للعملاء وخدمتهم المتكررة مثل الصيانة الدورية، ويشمل مواعيد ورسائل تنبيه.',
    },
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

  function _activeMode() {
    try {
      return (sessionStorage.getItem(MODE_KEY) || 'client').trim().toLowerCase() === 'provider'
        ? 'provider'
        : 'client';
    } catch {
      return 'client';
    }
  }

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
    const res = await ApiClient.get('/api/notifications/preferences/?mode=' + encodeURIComponent(_activeMode()));
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

  function _render() {
    _renderStats();
    _renderSections();
    const list = document.getElementById('notif-settings-list');
    if (list) list.classList.remove('hidden');
  }

  function _renderStats() {
    const enabled = _prefs.filter((pref) => pref.enabled && !pref.locked).length;
    const total = _prefs.length;
    const enabledNode = document.getElementById('notif-settings-enabled-count');
    const totalNode = document.getElementById('notif-settings-total-count');
    if (enabledNode) enabledNode.textContent = '(' + String(enabled) + ')';
    if (totalNode) totalNode.textContent = String(total) + ' تنبيه متاح';
  }

  function _renderSections() {
    Object.values(SECTION_CONFIG).forEach((section) => {
      const mount = document.getElementById(section.mountId);
      if (!mount) return;
      mount.innerHTML = '';
      mount.appendChild(_buildSection(section));
    });
  }

  function _buildSection(section) {
    const wrap = UI.el('section', {
      className: 'notif-section-card ' + section.className,
    });

    const header = UI.el('header', { className: 'notif-section-header' });
    header.appendChild(UI.el('h2', { className: 'notif-section-title', textContent: section.label }));
    const prefs = _sectionPrefs(section);
    wrap.appendChild(header);

    const list = UI.el('div', { className: 'notif-toggle-list' });
    if (!prefs.length) {
      list.appendChild(UI.el('div', {
        className: 'notif-empty-state',
        textContent: 'لا توجد إعدادات متاحة في هذا القسم حاليًا',
      }));
    } else {
      prefs.forEach((pref) => list.appendChild(_buildPrefRow(pref, section.key === 'extra')));
    }
    wrap.appendChild(list);

    if (section.noteTitle && section.noteBody) {
      const note = UI.el('div', { className: 'notif-extra-note' });
      note.appendChild(UI.el('div', { className: 'notif-extra-note-arrow', textContent: '↓' }));
      note.appendChild(UI.el('div', { className: 'notif-extra-note-title', textContent: section.noteTitle }));
      note.appendChild(UI.el('p', { className: 'notif-extra-note-body', textContent: section.noteBody }));
      wrap.appendChild(note);
    }

    return wrap;
  }

  function _sectionPrefs(section) {
    const byKey = new Map(_prefs.map((pref) => [pref.key, pref]));
    const ordered = section.items
      .map((key) => byKey.get(key))
      .filter(Boolean);

    const fallback = _prefs.filter((pref) => (
      _normalizeTier(pref) === section.key &&
      !section.items.includes(pref.key)
    ));

    return ordered.concat(fallback);
  }

  function _normalizeTier(pref) {
    const raw = String((pref && (pref.canonical_tier || pref.tier)) || 'basic').trim().toLowerCase();
    return TIER_ALIASES[raw] || raw || 'basic';
  }

  function _buildPrefRow(pref, compact) {
    const row = UI.el('label', {
      className: 'notif-pref-row' + (pref.locked ? ' locked' : '') + (_savingKeys.has(pref.key) ? ' saving' : '') + (compact ? ' compact' : ''),
    });
    if (pref.locked && pref.locked_reason) {
      row.title = pref.locked_reason;
    }

    const title = UI.el('span', { className: 'notif-pref-title', textContent: pref.title || pref.key });
    row.appendChild(title);

    const control = UI.el('span', { className: 'notif-pref-control' });
    if (pref.locked) {
      control.appendChild(UI.el('span', { className: 'notif-pref-lock', textContent: 'مقفل' }));
    } else if (_savingKeys.has(pref.key)) {
      control.appendChild(UI.el('span', { className: 'spinner-inline pref-spinner' }));
    } else {
      const input = UI.el('input', {
        type: 'checkbox',
        className: 'notif-pref-switch',
        'aria-label': pref.title || pref.key,
      });
      input.checked = !!pref.enabled;
      input.addEventListener('change', (event) => {
        event.preventDefault();
        _toggle(pref, input.checked);
      });
      control.appendChild(input);
      control.appendChild(UI.el('span', { className: 'notif-pref-slider' }));
    }

    row.appendChild(control);

    if (pref.locked) {
      row.addEventListener('click', (event) => {
        event.preventDefault();
        _showUpgradeDialog(pref.locked_reason);
      });
    }

    return row;
  }

  async function _toggle(pref, enabled) {
    if (pref.locked || _savingKeys.has(pref.key)) {
      if (pref.locked) _showUpgradeDialog(pref.locked_reason);
      return;
    }

    _savingKeys.add(pref.key);
    _render();

    const res = await ApiClient.request('/api/notifications/preferences/?mode=' + encodeURIComponent(_activeMode()), {
      method: 'PATCH',
      body: { updates: [{ key: pref.key, enabled }] },
    });

    _savingKeys.delete(pref.key);

    if (!res.ok) {
      alert('فشل حفظ الإعداد');
      _render();
      return;
    }

    if (res.data && Array.isArray(res.data.results)) {
      _prefs = res.data.results;
    } else {
      _prefs = _prefs.map((item) => (
        item.key === pref.key
          ? { ...item, enabled }
          : item
      ));
    }
    _render();
  }

  function _showUpgradeDialog(reason) {
    alert(reason || 'هذه الإشعارات غير متاحة في اشتراكك الحالي.');
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  return {};
})();
