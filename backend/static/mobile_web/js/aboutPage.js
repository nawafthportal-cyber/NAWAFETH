/* ===================================================================
   aboutPage.js — About platform page
   GET /api/content/public/
   =================================================================== */
'use strict';

const AboutPage = (() => {
  const DEFAULTS = {
    about: {
      title: 'من نحن',
      body: 'منصة نوافذ للخدمات لتقنية المعلومات مؤسسة سعودية مقرها الرياض، متخصصة في ربط مزودي الخدمات بطالبيها.',
      icon: 'ℹ️',
    },
    vision: {
      title: 'رؤيتنا',
      body: 'أن نكون المنصة الأولى في المملكة العربية السعودية للوصول للخدمات بسهولة وشفافية.',
      icon: '👁️',
    },
    goals: {
      title: 'هدفنا',
      body: 'تسهيل التواصل بين مزودي الخدمات والعملاء عبر تجربة سريعة ومنظمة.',
      icon: '🎯',
    },
    values: {
      title: 'قيمنا',
      body: 'الشفافية، الموثوقية، الجودة، والابتكار.',
      icon: '⭐',
    },
    app: {
      title: 'عن التطبيق',
      body: 'يمكنك استعراض الخدمات والتواصل مع مزوديها بسهولة عبر تطبيق نوافذ.',
      icon: '📱',
    },
  };

  function init() {
    _load();
  }

  async function _load() {
    const loading = document.getElementById('about-loading');
    const sections = document.getElementById('about-sections');
    const linksBox = document.getElementById('about-links');

    const res = await ApiClient.get('/api/content/public/');
    const data = (res.ok && res.data && typeof res.data === 'object') ? res.data : {};
    const blocks = data.blocks || {};
    const links = data.links || {};

    const mapped = _mapBlocks(blocks);
    if (sections) {
      sections.innerHTML = '';
      Object.keys(mapped).forEach((key) => {
        sections.appendChild(_buildCard(key, mapped[key]));
      });
      sections.classList.remove('hidden');
    }

    _bindLink('btn-android-store', links.android_store);
    _bindLink('btn-ios-store', links.ios_store);
    _bindLink('btn-website', links.website_url);
    if (linksBox) {
      const visibleCount = linksBox.querySelectorAll('a:not(.hidden)').length;
      linksBox.classList.toggle('hidden', visibleCount === 0);
    }

    if (loading) loading.classList.add('hidden');
  }

  function _findBlockByCandidates(blocks, candidates) {
    for (const key of candidates) {
      if (blocks[key] && typeof blocks[key] === 'object') return blocks[key];
    }

    const entries = Object.entries(blocks);
    for (const [key, value] of entries) {
      const normalized = String(key || '').toLowerCase().trim();
      if (!candidates.some((c) => normalized.includes(c))) continue;
      if (value && typeof value === 'object') return value;
    }
    return null;
  }

  function _mapBlocks(blocks) {
    const about = _findBlockByCandidates(blocks, ['about', 'about_us', 'company_about']);
    const vision = _findBlockByCandidates(blocks, ['vision']);
    const goals = _findBlockByCandidates(blocks, ['goals', 'goal', 'objectives']);
    const values = _findBlockByCandidates(blocks, ['values', 'value']);
    const app = _findBlockByCandidates(blocks, ['app', 'application', 'about_app']);

    return {
      about: _mergeBlock(DEFAULTS.about, about),
      vision: _mergeBlock(DEFAULTS.vision, vision),
      goals: _mergeBlock(DEFAULTS.goals, goals),
      values: _mergeBlock(DEFAULTS.values, values),
      app: _mergeBlock(DEFAULTS.app, app),
    };
  }

  function _mergeBlock(defaultData, apiBlock) {
    if (!apiBlock) return defaultData;
    return {
      title: String(apiBlock.title_ar || '').trim() || defaultData.title,
      body: String(apiBlock.body_ar || '').trim() || defaultData.body,
      icon: defaultData.icon,
    };
  }

  function _buildCard(key, data) {
    const card = UI.el('article', { className: 'expand-card', 'data-key': key });
    const head = UI.el('button', { className: 'expand-head', type: 'button' });
    const body = UI.el('div', { className: 'expand-body hidden' });

    head.appendChild(UI.el('span', { className: 'expand-icon', textContent: data.icon || '📄' }));
    const textWrap = UI.el('span', { className: 'expand-head-text' });
    textWrap.appendChild(UI.el('span', { className: 'expand-title', textContent: data.title || '' }));
    head.appendChild(textWrap);
    head.appendChild(UI.el('span', { className: 'expand-arrow', textContent: '⌄' }));

    body.appendChild(UI.el('p', { className: 'expand-content', textContent: data.body || '' }));

    head.addEventListener('click', () => {
      const isOpen = !body.classList.contains('hidden');
      document.querySelectorAll('.expand-card').forEach((node) => node.classList.remove('active'));
      document.querySelectorAll('.expand-card .expand-body').forEach((node) => node.classList.add('hidden'));
      if (!isOpen) {
        card.classList.add('active');
        body.classList.remove('hidden');
      }
    });

    card.appendChild(head);
    card.appendChild(body);
    return card;
  }

  function _bindLink(id, url) {
    const el = document.getElementById(id);
    if (!el) return;
    const clean = String(url || '').trim();
    if (!clean) {
      el.classList.add('hidden');
      return;
    }
    el.href = clean;
    el.classList.remove('hidden');
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  return {};
})();
