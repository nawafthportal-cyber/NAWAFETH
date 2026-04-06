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

  document.addEventListener('DOMContentLoaded', function () {
    const tierField = document.getElementById('id_tier');
    if (!tierField) {
      return;
    }
    tierField.addEventListener('change', syncTierVisibility);
    syncTierVisibility();
  });
})();