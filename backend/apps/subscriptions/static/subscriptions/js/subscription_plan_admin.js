(function () {
  'use strict';

  const TIER_FIELD_RULES = {
    promotional_chat_messages_enabled: ['pro'],
    promotional_notification_messages_enabled: ['pro'],
    storage_multiplier: ['riyadi'],
  };

  function normalizedTierValue(value) {
    return String(value || '').trim().toLowerCase();
  }

  function wrappersForField(fieldName) {
    const boxes = Array.from(document.querySelectorAll('.fieldBox.field-' + fieldName));
    if (boxes.length) {
      return boxes;
    }
    return Array.from(document.querySelectorAll('.form-row.field-' + fieldName));
  }

  function setFieldVisibility(fieldName, shouldShow) {
    wrappersForField(fieldName).forEach((node) => {
      node.hidden = !shouldShow;
      node.style.display = shouldShow ? '' : 'none';
    });
  }

  function syncCompositeRows() {
    Array.from(document.querySelectorAll('.form-row')).forEach((row) => {
      const fieldBoxes = Array.from(row.querySelectorAll('.fieldBox'));
      if (!fieldBoxes.length) {
        return;
      }
      const hasVisibleBox = fieldBoxes.some((box) => !box.hidden && box.style.display !== 'none');
      row.hidden = !hasVisibleBox;
      row.style.display = hasVisibleBox ? '' : 'none';
    });
  }

  function syncTierVisibility() {
    const tierField = document.getElementById('id_tier');
    if (!tierField) {
      return;
    }

    const selectedTier = normalizedTierValue(tierField.value || tierField.getAttribute('value'));
    Object.keys(TIER_FIELD_RULES).forEach((fieldName) => {
      const allowedTiers = TIER_FIELD_RULES[fieldName] || [];
      setFieldVisibility(fieldName, allowedTiers.includes(selectedTier));
    });
    syncCompositeRows();
  }

  function slugifySectionLabel(value) {
    return String(value || '')
      .trim()
      .toLowerCase()
      .replace(/[^\u0600-\u06FF\w]+/g, '-')
      .replace(/^-+|-+$/g, '');
  }

  function subscriptionFieldsets() {
    return Array.from(document.querySelectorAll('fieldset.subscription-plan-fieldset'));
  }

  function decorateFieldsets() {
    subscriptionFieldsets().forEach(function (fieldset, index) {
      var heading = fieldset.querySelector('h2');
      var title = heading ? heading.textContent.trim() : 'section-' + String(index + 1);
      if (!fieldset.id) {
        fieldset.id = 'subscription-plan-section-' + (slugifySectionLabel(title) || String(index + 1));
      }
      fieldset.dataset.sectionTitle = title;
    });
  }

  function buildQuickNav() {
    var fieldsets = subscriptionFieldsets();
    if (!fieldsets.length) {
      return;
    }

    var existing = document.querySelector('.subscription-plan-admin-nav');
    if (existing) {
      existing.remove();
    }

    var nav = document.createElement('div');
    nav.className = 'subscription-plan-admin-nav';
    var navTitle = document.createElement('div');
    navTitle.className = 'subscription-plan-admin-nav-title';
    navTitle.textContent = 'التنقل السريع بين أقسام الباقة';
    nav.appendChild(navTitle);

    var chips = document.createElement('div');
    chips.className = 'subscription-plan-admin-nav-chips';
    fieldsets.forEach(function (fieldset) {
      var button = document.createElement('button');
      button.type = 'button';
      button.className = 'subscription-plan-admin-nav-chip';
      button.textContent = fieldset.dataset.sectionTitle || 'قسم';
      button.addEventListener('click', function () {
        fieldset.scrollIntoView({ behavior: 'smooth', block: 'start' });
      });
      chips.appendChild(button);
    });
    nav.appendChild(chips);

    var anchor = fieldsets[0].parentElement;
    if (anchor) {
      anchor.insertBefore(nav, fieldsets[0]);
    }
  }

  document.addEventListener('DOMContentLoaded', function () {
    document.body.classList.add('subscription-plan-admin-page');
    const tierField = document.getElementById('id_tier');
    decorateFieldsets();
    buildQuickNav();
    if (tierField) {
      tierField.addEventListener('change', syncTierVisibility);
      syncTierVisibility();
    }
  });
})();