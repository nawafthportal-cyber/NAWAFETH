/* ===================================================================
   utils.js — Render helpers & DOM utilities (XSS-safe)
   =================================================================== */
'use strict';

const UI = (() => {

  /**
   * Safely create a text node (never innerHTML for user data).
   */
  function text(str) {
    return document.createTextNode(str || '');
  }

  /**
   * Create an element with optional attrs and children.
   * @param {string} tag
   * @param {object} attrs — { className, id, style, ... }
   * @param {(Node|string)[]} children
   */
  function el(tag, attrs, children) {
    const e = document.createElement(tag);
    if (attrs) {
      Object.keys(attrs).forEach(k => {
        if (k === 'className') e.className = attrs[k];
        else if (k === 'textContent') e.textContent = attrs[k];
        else if (k === 'innerHTML') { /* BLOCKED — use textContent */ }
        else if (k === 'style' && typeof attrs[k] === 'object') {
          Object.assign(e.style, attrs[k]);
        } else if (k.startsWith('on') && typeof attrs[k] === 'function') {
          e.addEventListener(k.slice(2).toLowerCase(), attrs[k]);
        } else {
          e.setAttribute(k, attrs[k]);
        }
      });
    }
    if (children) {
      children.forEach(c => {
        if (typeof c === 'string') e.appendChild(text(c));
        else if (c instanceof Node) e.appendChild(c);
      });
    }
    return e;
  }

  /**
   * Create an SVG icon (inline, safe).
   * @param {string} name — icon key
   * @param {number} size
   * @param {string} color
   */
  function icon(name, size, color) {
    const icons = {
      star: '<path d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z"/>',
      sparkles: '<path d="M12 2l1.76 4.24L18 8l-4.24 1.76L12 14l-1.76-4.24L6 8l4.24-1.76L12 2zm6 9l.94 2.06L21 14l-2.06.94L18 17l-.94-2.06L15 14l2.06-.94L18 11zM6 15l1.17 2.83L10 19l-2.83 1.17L6 23l-1.17-2.83L2 19l2.83-1.17L6 15z"/>',
      bolt: '<path d="M13 2L4 14h6l-1 8 9-12h-6l1-8z"/>',
      trophy: '<path d="M18 2H6v3H3v3c0 2.97 2.16 5.43 5 5.91V17H6v2h12v-2h-2v-3.09c2.84-.48 5-2.94 5-5.91V5h-3V2zm-9 9c-1.66 0-3-1.34-3-3V7h2v4h1zm9-3c0 1.66-1.34 3-3 3h-1V7h2v1z"/>',
      people: '<path d="M16 11c1.66 0 2.99-1.34 2.99-3S17.66 5 16 5c-1.66 0-3 1.34-3 3s1.34 3 3 3zm-8 0c1.66 0 2.99-1.34 2.99-3S9.66 5 8 5C6.34 5 5 6.34 5 8s1.34 3 3 3zm0 2c-2.33 0-7 1.17-7 3.5V19h14v-2.5c0-2.33-4.67-3.5-7-3.5z"/>',
      heart: '<path d="M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z"/>',
      verified_blue: '<path d="M12 1L3 5v6c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V5l-9-4z"/><path d="M10 15.17l-3.59-3.58L5 13l5 5 9-9-1.41-1.41L10 15.17z" fill="#fff"/>',
      verified_green: '<path d="M12 1L3 5v6c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V5l-9-4z"/><path d="M10 15.17l-3.59-3.58L5 13l5 5 9-9-1.41-1.41L10 15.17z" fill="#fff"/>',
      info: '<path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-6h2v6zm0-8h-2V7h2v2z"/>',
      image: '<path d="M21 19V5c0-1.1-.9-2-2-2H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2zM8.5 13.5l2.5 3.01L14.5 12l4.5 6H5l3.5-4.5z"/>',
      // Category icons
      gavel: '<path d="M1 21h12v2H1v-2zm0-2h12v-2H1v2zm17.7-9.1l-2.1-2.1-1.4 1.4 2.1 2.1-5.2 5.2-2.1-2.1-1.4 1.4 2.1 2.1-1.4 1.4 3.5 3.5 1.4-1.4-2.1-2.1 5.2-5.2 2.1 2.1 1.4-1.4-2.1-2.1 1.4-1.4z"/>',
      engineering: '<path d="M9 15c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4zm13.1-8.16c.01-.11.02-.22.02-.34 0-.12-.01-.23-.03-.34l.74-.58c.07-.05.08-.14.04-.21l-.7-1.21c-.04-.08-.14-.1-.21-.08l-.86.35c-.18-.14-.38-.25-.59-.34l-.13-.93c-.02-.09-.09-.15-.18-.15h-1.4c-.09 0-.16.06-.17.15l-.13.93c-.21.09-.41.21-.59.34l-.87-.35c-.08-.02-.17 0-.21.08l-.7 1.21c-.04.08-.02.16.04.22l.74.58c-.02.11-.03.23-.03.34 0 .11.01.23.03.34l-.74.58c-.07.05-.08.14-.04.22l.7 1.21c.04.08.14.1.21.08l.87-.35c.18.14.38.25.59.34l.13.93c.01.09.08.15.17.15h1.4c.09 0 .16-.06.17-.15l.14-.93c.21-.09.41-.21.59-.34l.87.35c.08.02.17 0 .21-.08l.7-1.21c.04-.08.02-.16-.04-.22l-.74-.58zM14.5 7.5c-.83 0-1.5-.67-1.5-1.5s.67-1.5 1.5-1.5 1.5.67 1.5 1.5-.67 1.5-1.5 1.5z"/>',
      design: '<path d="M20.97 7.27a.996.996 0 000-1.41l-2.83-2.83a.996.996 0 00-1.41 0l-4.49 4.49L8.35 3.63c-.78-.78-2.05-.78-2.83 0l-1.9 1.9c-.78.78-.78 2.05 0 2.83l3.89 3.89L3 16.76V21h4.24l4.52-4.52 3.89 3.89c.39.39.9.58 1.41.58.51 0 1.02-.2 1.41-.58l1.9-1.9c.78-.78.78-2.05 0-2.83l-3.89-3.89 4.49-4.48z"/>',
      delivery: '<path d="M19 7c0-1.1-.9-2-2-2h-3v2h3v2.65L13.52 14H10V9H6c-2.21 0-4 1.79-4 4v3h2c0 1.66 1.34 3 3 3s3-1.34 3-3h4.48L19 10.35V7zM7 17c-.55 0-1-.45-1-1h2c0 .55-.45 1-1 1z"/><path d="M5 6h5v2H5V6zm14 7c-1.66 0-3 1.34-3 3s1.34 3 3 3 3-1.34 3-3-1.34-3-3-3zm0 4c-.55 0-1-.45-1-1s.45-1 1-1 1 .45 1 1-.45 1-1 1z"/>',
      health: '<path d="M10.5 13H8v-3h2.5V7.5h3V10H16v3h-2.5v2.5h-3V13zM12 2L4 5v6.09c0 5.05 3.41 9.76 8 10.91 4.59-1.15 8-5.86 8-10.91V5l-8-3z"/>',
      translate: '<path d="M12.87 15.07l-2.54-2.51.03-.03c1.74-1.94 2.98-4.17 3.71-6.53H17V4h-7V2H8v2H1v1.99h11.17C11.5 7.92 10.44 9.75 9 11.35 8.07 10.32 7.3 9.19 6.69 8h-2c.73 1.63 1.73 3.17 2.98 4.56l-5.09 5.02L4 19l5-5 3.11 3.11.76-2.04zM18.5 10h-2L12 22h2l1.12-3h4.75L21 22h2l-4.5-12zm-2.62 7l1.62-4.33L19.12 17h-3.24z"/>',
      code: '<path d="M9.4 16.6L4.8 12l4.6-4.6L8 6l-6 6 6 6 1.4-1.4zm5.2 0l4.6-4.6-4.6-4.6L16 6l6 6-6 6-1.4-1.4z"/>',
      build: '<path d="M22.7 19l-9.1-9.1c.9-2.3.4-5-1.5-6.9-2-2-5-2.4-7.4-1.3L9 6 6 9 1.6 4.7C.4 7.1.9 10.1 2.9 12.1c1.9 1.9 4.6 2.4 6.9 1.5l9.1 9.1c.4.4 1 .4 1.4 0l2.3-2.3c.5-.4.5-1.1.1-1.4z"/>',
      fitness: '<path d="M20.57 14.86L22 13.43 20.57 12 17 15.57 8.43 7 12 3.43 10.57 2 9.14 3.43 7.71 2 5.57 4.14 4.14 2.71 2.71 4.14l1.43 1.43L2 7.71l1.43 1.43L2 10.57 3.43 12 7 8.43 15.57 17 12 20.57 13.43 22l1.43-1.43L16.29 22l2.14-2.14 1.43 1.43 1.43-1.43-1.43-1.43L22 16.29z"/>',
      home_repair: '<path d="M18 16h-2v-1H8v1H6v-1H2v5h20v-5h-4v1zm2-8h-3V6c0-.55-.45-1-1-1h-4c-.55 0-1 .45-1 1v2H8c-1.1 0-2 .9-2 2v2h4v-1h4v1h4v-2c0-1.1-.9-2-2-2zm-5 0h-2V6h2v2z"/>',
      money: '<path d="M11.8 10.9c-2.27-.59-3-1.2-3-2.15 0-1.09 1.01-1.85 2.7-1.85 1.78 0 2.44.85 2.5 2.1h2.21c-.07-1.72-1.12-3.3-3.21-3.81V3h-3v2.16c-1.94.42-3.5 1.68-3.5 3.61 0 2.31 1.91 3.46 4.7 4.13 2.5.6 3 1.48 3 2.41 0 .69-.49 1.79-2.7 1.79-2.06 0-2.87-.92-2.98-2.1h-2.2c.12 2.19 1.76 3.42 3.68 3.83V21h3v-2.15c1.95-.37 3.5-1.5 3.5-3.55 0-2.84-2.43-3.81-4.7-4.4z"/>',
      campaign: '<path d="M18 11v2h4v-2h-4zm-2 6.61c.96.71 2.21 1.65 3.2 2.39.4-.53.8-1.07 1.2-1.6-.99-.74-2.24-1.68-3.2-2.4-.4.54-.8 1.08-1.2 1.61zM20.4 5.6c-.4-.53-.8-1.07-1.2-1.6-.99.74-2.24 1.68-3.2 2.4.4.53.8 1.07 1.2 1.6.96-.72 2.21-1.65 3.2-2.4zM4 9c-1.1 0-2 .9-2 2v2c0 1.1.9 2 2 2h1l5 3V6L5 9H4zm5.03 1.71L11 9.53v4.94l-1.97-1.18-.48-.29H4v-2h4.55l.48-.29zM14.5 12c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02z"/>',
      school: '<path d="M5 13.18v4L12 21l7-3.82v-4L12 17l-7-3.82zM12 3L1 9l11 6 9-4.91V17h2V9L12 3z"/>',
      car: '<path d="M18.92 6.01C18.72 5.42 18.16 5 17.5 5h-11c-.66 0-1.21.42-1.42 1.01L3 12v8c0 .55.45 1 1 1h1c.55 0 1-.45 1-1v-1h12v1c0 .55.45 1 1 1h1c.55 0 1-.45 1-1v-8l-2.08-5.99zM6.5 16c-.83 0-1.5-.67-1.5-1.5S5.67 13 6.5 13s1.5.67 1.5 1.5S7.33 16 6.5 16zm11 0c-.83 0-1.5-.67-1.5-1.5s.67-1.5 1.5-1.5 1.5.67 1.5 1.5-.67 1.5-1.5 1.5zM5 11l1.5-4.5h11L19 11H5z"/>',
      category: '<path d="M12 2l-5.5 9h11L12 2zm0 3.84L13.93 9h-3.87L12 5.84zM17.5 13c-2.49 0-4.5 2.01-4.5 4.5s2.01 4.5 4.5 4.5 4.5-2.01 4.5-4.5-2.01-4.5-4.5-4.5zm0 7c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5zM3 21.5h8v-8H3v8zm2-6h4v4H5v-4z"/>',
    };
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('width', size || 22);
    svg.setAttribute('height', size || 22);
    svg.setAttribute('viewBox', '0 0 24 24');
    svg.setAttribute('fill', color || 'currentColor');
    svg.innerHTML = icons[name] || icons.category;
    return svg;
  }

  /**
   * Map category name to icon key (mirrors Flutter _categoryIcon).
   */
  function categoryIconKey(name) {
    const n = (name || '').toLowerCase();
    if (n.includes('قانون') || n.includes('محام')) return 'gavel';
    if (n.includes('هندس')) return 'engineering';
    if (n.includes('تصميم')) return 'design';
    if (n.includes('توصيل')) return 'delivery';
    if (n.includes('صح') || n.includes('طب')) return 'health';
    if (n.includes('ترجم')) return 'translate';
    if (n.includes('برمج') || n.includes('تقن')) return 'code';
    if (n.includes('صيان')) return 'build';
    if (n.includes('رياض')) return 'fitness';
    if (n.includes('منزل')) return 'home_repair';
    if (n.includes('مال')) return 'money';
    if (n.includes('تسويق')) return 'campaign';
    if (n.includes('تعليم') || n.includes('تدريب')) return 'school';
    if (n.includes('سيار') || n.includes('نقل')) return 'car';
    return 'category';
  }

  /**
   * Lazy-load image with fade-in.
   */
  function lazyImg(src, alt, className) {
    const img = el('img', {
      loading: 'lazy',
      alt: alt || '',
      className: className || '',
    });
    img.addEventListener('load', () => img.classList.add('loaded'), { once: true });
    img.addEventListener('error', () => {
      img.style.display = 'none'; // hide broken images gracefully
    }, { once: true });
    // Set src after event listeners
    img.src = src;
    return img;
  }

  function _excellenceFallbackColor(code) {
    const normalized = String(code || '').trim().toLowerCase();
    if (normalized === 'high_achievement') return '#0F766E';
    if (normalized === 'top_100_club') return '#7C3AED';
    return '#C0841A';
  }

  function _excellenceIconKey(badge) {
    const code = String(badge && badge.code || '').trim().toLowerCase();
    const iconName = String(badge && badge.icon || '').trim().toLowerCase();
    if (code === 'featured_service' || iconName === 'sparkles') return 'sparkles';
    if (code === 'high_achievement' || iconName === 'bolt') return 'bolt';
    if (code === 'top_100_club' || iconName === 'trophy') return 'trophy';
    return 'sparkles';
  }

  function normalizeExcellenceBadges(value) {
    if (!Array.isArray(value)) return [];
    return value
      .filter(item => item && typeof item === 'object')
      .map(item => ({
        code: String(item.code || '').trim(),
        name: String(item.name || item.title || '').trim(),
        icon: String(item.icon || '').trim(),
        color: String(item.color || '').trim(),
        awarded_at: String(item.awarded_at || '').trim(),
        valid_until: String(item.valid_until || '').trim(),
      }))
      .filter(item => item.code || item.name);
  }

  function buildExcellenceBadges(badges, options) {
    const items = normalizeExcellenceBadges(badges);
    if (!items.length) return null;

    const opts = options || {};
    const className = opts.className || 'excellence-badges';
    const compact = !!opts.compact;
    const wrap = el('div', { className: className + (compact ? ' compact' : '') });
    wrap.style.display = 'flex';
    wrap.style.flexWrap = 'wrap';
    wrap.style.alignItems = 'center';
    wrap.style.gap = compact ? '4px' : '6px';

    items.forEach(item => {
      const color = item.color || _excellenceFallbackColor(item.code);
      const chip = el('span', {
        className: 'excellence-badge-chip',
        title: item.name || item.code,
      });
      chip.style.setProperty('--excellence-badge-color', color);
      chip.style.display = 'inline-flex';
      chip.style.alignItems = 'center';
      chip.style.gap = '4px';
      chip.style.minHeight = compact ? '20px' : '22px';
      chip.style.padding = compact ? '2px 7px' : '3px 8px';
      chip.style.borderRadius = '999px';
      chip.style.border = '1px solid ' + color;
      chip.style.background = 'rgba(255, 255, 255, 0.92)';
      chip.style.color = color;
      chip.style.fontFamily = 'Cairo, sans-serif';
      chip.style.fontSize = compact ? '9.5px' : '10.5px';
      chip.style.fontWeight = '800';
      chip.style.lineHeight = '1';
      chip.style.whiteSpace = 'nowrap';

      const iconWrap = el('span', { className: 'excellence-badge-icon' });
      iconWrap.style.display = 'inline-flex';
      iconWrap.style.alignItems = 'center';
      iconWrap.style.justifyContent = 'center';
      iconWrap.appendChild(icon(_excellenceIconKey(item), opts.iconSize || (compact ? 10 : 12), color));
      chip.appendChild(iconWrap);
      chip.appendChild(el('span', {
        className: 'excellence-badge-label',
        textContent: item.name || item.code,
      }));
      wrap.appendChild(chip);
    });

    return wrap;
  }

  return { el, text, icon, categoryIconKey, lazyImg, normalizeExcellenceBadges, buildExcellenceBadges };
})();
