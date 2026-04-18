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
      description: 'تنبيهات التشغيل الأساسية المرتبطة بالطلبات والرسائل والتحديثات العامة.',
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
      description: 'تنبيهات التفاعل والنمو المرتبطة بالمتابعات والتعليقات واهتمام العملاء.',
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
      description: 'تنبيهات متقدمة للمراجعات والمنافسة والظهور التجاري.',
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
      description: 'تنبيهات مرتبطة بالخدمات الإضافية والبوابات التشغيلية المتخصصة.',
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
  const SECTION_ORDER = ['basic', 'pioneer', 'professional', 'extra'];
  const TIER_LABELS = {
    basic: 'الباقة الأساسية',
    pioneer: 'الباقة الريادية',
    professional: 'الباقة الاحترافية',
    extra: 'تنبيهات الخدمات الإضافية',
  };

  let _prefs = [];
  const _savingKeys = new Set();
  const _openSections = new Set(['basic']);
  let _toastTimer = null;
  let _activeUpgradeDialog = null;

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
    _bindRetry();
    _load();
  }

  function _bindRetry() {
    const retryBtn = document.getElementById('notif-settings-retry');
    if (!retryBtn) return;
    retryBtn.addEventListener('click', () => {
      _load();
    });
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
    const profileState = await Auth.resolveProfile(false, _activeMode());
    if (!profileState.ok) {
      _setLoading(false);
      if (!Auth.isLoggedIn()) {
        _showGate();
        return;
      }
      _setError('يجري الآن مزامنة نوع الحساب الحالي. حاول مرة أخرى خلال لحظة.');
      return;
    }
    const res = await ApiClient.get('/api/notifications/preferences/?mode=' + encodeURIComponent(_activeMode()));
    _setLoading(false);

    if (res.status === 401) {
      const recovered = await Auth.resolveProfile(true, _activeMode());
      if (!recovered.ok && !Auth.isLoggedIn()) {
        _showGate();
        return;
      }
      _setError('يتم تحديث الجلسة أو نوع الحساب الآن. أعد المحاولة بعد قليل.');
      return;
    }

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
    const empty = document.getElementById('notif-settings-empty');
    const retryBtn = document.getElementById('notif-settings-retry');
    if (loadingEl) loadingEl.classList.toggle('hidden', !loading);
    if (list && loading) list.classList.add('hidden');
    if (empty && loading) empty.classList.add('hidden');
    if (retryBtn && loading) retryBtn.classList.add('hidden');
  }

  function _setError(message) {
    const errorEl = document.getElementById('notif-settings-error');
    const retryBtn = document.getElementById('notif-settings-retry');
    const list = document.getElementById('notif-settings-list');
    const empty = document.getElementById('notif-settings-empty');
    if (!errorEl) return;
    if (!message) {
      errorEl.textContent = '';
      errorEl.classList.add('hidden');
      if (retryBtn) retryBtn.classList.add('hidden');
      return;
    }
    errorEl.textContent = message;
    errorEl.classList.remove('hidden');
    if (retryBtn) retryBtn.classList.remove('hidden');
    if (list) list.classList.add('hidden');
    if (empty) empty.classList.add('hidden');
  }

  function _render() {
    _renderStats();
    const visibleSections = _renderSections();
    const list = document.getElementById('notif-settings-list');
    const empty = document.getElementById('notif-settings-empty');
    const hasSections = visibleSections > 0;
    if (list) list.classList.toggle('hidden', !hasSections);
    if (empty) empty.classList.toggle('hidden', hasSections);
  }

  function _renderStats() {
    const enabled = _prefs.filter((pref) => pref.enabled && !pref.locked).length;
    const total = _prefs.length;
    const enabledNode = document.getElementById('notif-settings-enabled-count');
    const totalNode = document.getElementById('notif-settings-total-count');
    if (enabledNode) enabledNode.textContent = '(' + String(enabled) + ')';
    if (totalNode) totalNode.textContent = String(enabled) + ' مفعّل من أصل ' + String(total);
  }

  function _renderSections() {
    const mountedIds = new Set([
      'notif-basic-section',
      'notif-leading-section',
      'notif-professional-section',
      'notif-extra-section',
      'notif-other-sections',
    ]);
    mountedIds.forEach((id) => {
      const mount = document.getElementById(id);
      if (!mount) return;
      mount.classList.add('hidden');
      mount.innerHTML = '';
    });

    const entries = [];
    SECTION_ORDER.forEach((tierKey) => {
      const section = SECTION_CONFIG[tierKey];
      if (!section) return;
      const prefs = _sectionPrefs(section);
      if (!prefs.length) return;
      entries.push({ section, prefs, mountId: section.mountId });
    });

    _groupUnknownTierPrefs().forEach((prefs, tierKey) => {
      entries.push({
        section: _dynamicSectionConfig(tierKey),
        prefs,
        mountId: 'notif-other-sections',
      });
    });

    _syncOpenSections(entries.map((entry) => entry.section.key));

    entries.forEach((entry) => {
      const mount = document.getElementById(entry.mountId);
      if (!mount) return;
      mount.classList.remove('hidden');
      mount.appendChild(_buildSection(entry.section, entry.prefs));
    });

    return entries.length;
  }

  function _groupUnknownTierPrefs() {
    const grouped = new Map();
    _prefs.forEach((pref) => {
      const tier = _normalizeTier(pref);
      if (SECTION_CONFIG[tier]) return;
      if (!grouped.has(tier)) grouped.set(tier, []);
      grouped.get(tier).push(pref);
    });
    return grouped;
  }

  function _dynamicSectionConfig(tierKey) {
    return {
      key: tierKey,
      label: _formatTierLabel(tierKey),
      description: '',
      className: 'notif-tier-dynamic',
      noteTitle: '',
      noteBody: '',
    };
  }

  function _formatTierLabel(tierKey) {
    const key = String(tierKey || '').trim().toLowerCase();
    if (!key) return 'إعدادات إضافية';
    if (TIER_LABELS[key]) return TIER_LABELS[key];
    return key.replace(/[_-]+/g, ' ');
  }

  function _syncOpenSections(visibleKeys) {
    const visibleSet = new Set(visibleKeys);
    Array.from(_openSections).forEach((key) => {
      if (!visibleSet.has(key)) _openSections.delete(key);
    });
    if (_openSections.size === 0 && visibleKeys.length) {
      if (visibleSet.has('basic')) _openSections.add('basic');
      else _openSections.add(visibleKeys[0]);
    }
  }

  function _buildSection(section, sectionPrefs) {
    const prefs = Array.isArray(sectionPrefs) ? sectionPrefs : _sectionPrefs(section);
    const isOpen = _openSections.has(section.key);
    const wrap = UI.el('section', {
      className:
        'notif-section-card ' +
        section.className +
        (prefs.length ? '' : ' is-empty') +
        (isOpen ? ' expanded' : ' collapsed'),
    });

    const header = UI.el('header', {
      className: 'notif-section-header',
      role: 'button',
      tabindex: '0',
      'aria-expanded': String(isOpen),
    });
    const copy = UI.el('div', { className: 'notif-section-copy' });
    copy.appendChild(UI.el('h2', { className: 'notif-section-title', textContent: section.label }));
    if (section.description) {
      copy.appendChild(UI.el('p', { className: 'notif-section-description', textContent: section.description }));
    }
    header.appendChild(copy);

    const tools = UI.el('div', { className: 'notif-section-header-tools' });
    tools.appendChild(UI.el('span', {
      className: 'notif-section-count',
      textContent: String(prefs.filter((pref) => pref.enabled && !pref.locked).length) + '/' + String(prefs.length || 0),
    }));
    tools.appendChild(UI.el('span', { className: 'notif-section-chevron', textContent: '⌄', 'aria-hidden': 'true' }));
    header.appendChild(tools);

    header.addEventListener('click', () => _toggleSection(section.key));
    header.addEventListener('keydown', (event) => {
      if (event.key !== 'Enter' && event.key !== ' ') return;
      event.preventDefault();
      _toggleSection(section.key);
    });

    wrap.appendChild(header);
    const body = UI.el('div', { className: 'notif-section-body' + (isOpen ? ' open' : '') });

    const sectionNotice = _sectionNotice(section, prefs);
    if (sectionNotice) {
      body.appendChild(UI.el('div', {
        className: 'notif-section-notice',
        textContent: sectionNotice,
      }));
    }

    const list = UI.el('div', { className: 'notif-toggle-list' });
    if (!prefs.length) {
      list.appendChild(UI.el('div', {
        className: 'notif-empty-state',
        textContent: 'لا توجد إعدادات متاحة في هذا القسم حاليًا.',
      }));
    } else {
      prefs.forEach((pref) => list.appendChild(_buildPrefRow(pref, section.key === 'extra')));
    }
    body.appendChild(list);

    if (section.noteTitle && section.noteBody) {
      const note = UI.el('div', { className: 'notif-extra-note' });
      note.appendChild(UI.el('div', { className: 'notif-extra-note-arrow', textContent: '↓' }));
      note.appendChild(UI.el('div', { className: 'notif-extra-note-title', textContent: section.noteTitle }));
      note.appendChild(UI.el('p', { className: 'notif-extra-note-body', textContent: section.noteBody }));
      body.appendChild(note);
    }

    wrap.appendChild(body);
    return wrap;
  }

  function _toggleSection(sectionKey) {
    if (!sectionKey) return;
    if (_openSections.has(sectionKey)) _openSections.delete(sectionKey);
    else _openSections.add(sectionKey);
    _renderSections();
  }

  function _sectionNotice(section, prefs) {
    if (_activeMode() !== 'provider' || section.key === 'basic' || !prefs.length) {
      return '';
    }
    if (!prefs.every((pref) => pref.locked)) {
      return '';
    }
    const tierLocked = prefs.find((pref) => String(pref.locked_reason || '').includes('يلزم الاشتراك في الباقة'));
    if (tierLocked) {
      return tierLocked.locked_reason;
    }
    const genericLocked = prefs.find((pref) => pref.locked_reason);
    return genericLocked ? genericLocked.locked_reason : 'هذه التنبيهات غير متاحة في حسابك الحالي.';
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

    const textWrap = UI.el('span', { className: 'notif-pref-text' });
    textWrap.appendChild(UI.el('span', { className: 'notif-pref-title', textContent: pref.title || pref.key }));
    if (pref.locked && pref.locked_reason) {
      textWrap.appendChild(UI.el('span', { className: 'notif-pref-meta', textContent: pref.locked_reason }));
    }
    row.appendChild(textWrap);

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
      _showToast('فشل حفظ الإعداد', 'error');
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
    _closeUpgradeDialog();
    const message = reason || 'هذه الإشعارات غير متاحة في اشتراكك الحالي.';
    const backdrop = UI.el('div', {
      className: 'notif-settings-dialog-backdrop',
      role: 'presentation',
    });
    const dialog = UI.el('div', {
      className: 'notif-settings-dialog',
      role: 'dialog',
      'aria-modal': 'true',
      'aria-label': 'سبب عدم الإتاحة',
    });

    const iconWrap = UI.el('div', { className: 'notif-settings-dialog-icon', 'aria-hidden': 'true' });
    iconWrap.appendChild(UI.icon('sparkles', 24, '#6f3fa0'));
    dialog.appendChild(iconWrap);
    dialog.appendChild(UI.el('h3', {
      className: 'notif-settings-dialog-title',
      textContent: 'سبب عدم الإتاحة',
    }));
    dialog.appendChild(UI.el('p', {
      className: 'notif-settings-dialog-text',
      textContent: message,
    }));

    const actions = UI.el('div', { className: 'notif-settings-dialog-actions' });
    const okBtn = UI.el('button', {
      type: 'button',
      className: 'btn btn-primary notif-settings-dialog-btn',
      textContent: 'حسنًا',
    });
    const closeBtn = UI.el('button', {
      type: 'button',
      className: 'btn btn-outline notif-settings-dialog-btn notif-settings-dialog-close',
      textContent: 'إغلاق',
    });
    actions.appendChild(okBtn);
    actions.appendChild(closeBtn);
    dialog.appendChild(actions);
    backdrop.appendChild(dialog);

    const close = () => {
      document.removeEventListener('keydown', onKeydown);
      backdrop.classList.remove('show');
      window.setTimeout(() => {
        if (backdrop.parentNode) backdrop.remove();
      }, 150);
      if (_activeUpgradeDialog && _activeUpgradeDialog.backdrop === backdrop) {
        _activeUpgradeDialog = null;
      }
    };

    const onKeydown = (event) => {
      if (event.key === 'Escape') {
        event.preventDefault();
        close();
      }
    };

    okBtn.addEventListener('click', close);
    closeBtn.addEventListener('click', close);
    backdrop.addEventListener('click', (event) => {
      if (event.target === backdrop) close();
    });
    document.addEventListener('keydown', onKeydown);
    document.body.appendChild(backdrop);
    requestAnimationFrame(() => backdrop.classList.add('show'));
    _activeUpgradeDialog = { backdrop, close };
  }

  function _closeUpgradeDialog() {
    if (_activeUpgradeDialog && typeof _activeUpgradeDialog.close === 'function') {
      _activeUpgradeDialog.close();
    }
  }

  function _showToast(message, type) {
    if (!message) return;
    const existing = document.getElementById('notif-settings-toast');
    if (existing) existing.remove();
    const toast = UI.el('div', {
      id: 'notif-settings-toast',
      className: 'notif-settings-toast' + (type ? (' ' + type) : ''),
      textContent: message,
    });
    document.body.appendChild(toast);
    requestAnimationFrame(() => toast.classList.add('show'));
    window.clearTimeout(_toastTimer);
    _toastTimer = window.setTimeout(() => {
      toast.classList.remove('show');
      window.setTimeout(() => {
        if (toast.parentNode) toast.remove();
      }, 180);
    }, 2400);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  return {};
})();
