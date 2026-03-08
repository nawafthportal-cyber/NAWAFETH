/* ===================================================================
   aboutPage.js — About platform page
   GET /api/content/public/
   =================================================================== */
'use strict';

const AboutPage = (() => {
  const SECTION_META = {
    about: { key: 'about_section_about', icon: 'ℹ️' },
    vision: { key: 'about_section_vision', icon: '👁️' },
    goals: { key: 'about_section_goals', icon: '🎯' },
    values: { key: 'about_section_values', icon: '⭐' },
    app: { key: 'about_section_app', icon: '📱' },
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

    _applyHeroContent(blocks);
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

    // روابط التواصل الاجتماعي
    const socialBox = document.getElementById('about-social');
    _bindLink('btn-x-url', links.x_url);
    _bindLink('btn-whatsapp', _normalizeWhatsapp(links.whatsapp_url));
    _bindLink('btn-email', _normalizeEmail(links.email));
    const socialTitle = _resolveTitle(blocks.about_social_title, 'تواصل معنا');
    const socialTitleEl = document.getElementById('about-social-title');
    if (socialTitleEl) socialTitleEl.textContent = socialTitle;
    if (socialBox) {
      const visibleSocial = socialBox.querySelectorAll('a:not(.hidden)').length;
      socialBox.classList.toggle('hidden', visibleSocial === 0);
    }

    if (loading) loading.classList.add('hidden');
  }

  function _applyHeroContent(blocks) {
    const heroTitle = document.getElementById('about-hero-title');
    const heroSubtitle = document.getElementById('about-hero-subtitle');
    const website = document.getElementById('btn-website');
    if (heroTitle) heroTitle.textContent = _resolveTitle(blocks.about_hero_title, 'منصة نوافذ');
    if (heroSubtitle) {
      heroSubtitle.textContent = _resolveTitle(
        blocks.about_hero_subtitle,
        'حلول تقنية مبتكرة تربط مزودي الخدمات بطالبيها',
      );
    }
    if (website) website.textContent = _resolveTitle(blocks.about_website_label, 'الموقع الرسمي');
  }

  function _mapBlocks(blocks) {
    return {
      about: _resolveSection(blocks[SECTION_META.about.key], 'من نحن', '', SECTION_META.about.icon),
      vision: _resolveSection(blocks[SECTION_META.vision.key], 'رؤيتنا', '', SECTION_META.vision.icon),
      goals: _resolveSection(blocks[SECTION_META.goals.key], 'أهدافنا', '', SECTION_META.goals.icon),
      values: _resolveSection(blocks[SECTION_META.values.key], 'قيمنا', '', SECTION_META.values.icon),
      app: _resolveSection(blocks[SECTION_META.app.key], 'عن التطبيق', '', SECTION_META.app.icon),
    };
  }

  function _resolveSection(apiBlock, fallbackTitle, fallbackBody, icon) {
    return {
      title: _resolveTitle(apiBlock, fallbackTitle),
      body: _resolveBody(apiBlock, fallbackBody),
      icon,
    };
  }

  function _resolveTitle(block, fallback) {
    return String(block && block.title_ar || '').trim() || fallback;
  }

  function _resolveBody(block, fallback) {
    return String(block && block.body_ar || '').trim() || fallback;
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

  /** تطبيع رابط واتساب — لا يضيف prefix إذا بدأ بـ http */
  function _normalizeWhatsapp(raw) {
    const v = String(raw || '').trim();
    if (!v) return '';
    if (v.startsWith('http://') || v.startsWith('https://')) return v;
    if (v.startsWith('wa.me/')) return 'https://' + v;
    return 'https://wa.me/' + v;
  }

  /** تطبيع بريد إلكتروني — لا يضيف mailto: إذا موجود مسبقاً */
  function _normalizeEmail(raw) {
    const v = String(raw || '').trim();
    if (!v) return '';
    if (v.startsWith('mailto:')) return v;
    return 'mailto:' + v;
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
