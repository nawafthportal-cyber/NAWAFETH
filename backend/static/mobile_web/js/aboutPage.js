/* ===================================================================
   aboutPage.js — About platform page
   GET /api/content/public/
   =================================================================== */
'use strict';

const AboutPage = (() => {
  const SECTION_META = {
    about: { key: 'about_section_about', icon: 'ℹ️', tone: 'primary' },
    vision: { key: 'about_section_vision', icon: '👁️', tone: 'violet' },
    goals: { key: 'about_section_goals', icon: '🎯', tone: 'amber' },
    values: { key: 'about_section_values', icon: '⭐', tone: 'emerald' },
    app: { key: 'about_section_app', icon: '📱', tone: 'slate' },
  };

  function init() {
    _load();
  }

  async function _load() {
    const loading = document.getElementById('about-loading');
    const sections = document.getElementById('about-sections');
    const linksBox = document.getElementById('about-links');
    const story = document.getElementById('about-story');
    const empty = document.getElementById('about-empty');
    const error = document.getElementById('about-error');

    const res = await ApiClient.get('/api/content/public/');
    const ok = !!(res.ok && res.data && typeof res.data === 'object');
    const data = ok ? res.data : {};
    const blocks = data.blocks || {};
    const links = data.links || {};

    _applyHeroContent(blocks);
    const mapped = _mapBlocks(blocks);
    if (sections) {
      sections.innerHTML = '';
      mapped.forEach((item) => {
        sections.appendChild(_buildCard(item));
      });
      sections.classList.toggle('hidden', mapped.length === 0);
    }
    if (story) story.classList.toggle('hidden', !ok);
    if (empty) empty.classList.toggle('hidden', mapped.length !== 0 || !ok);
    if (error) error.classList.toggle('hidden', ok);

    _bindLink('btn-android-store', links.android_store);
    _bindLink('btn-ios-store', links.ios_store);
    _bindLink('btn-website', links.website_url);
    if (linksBox) {
      const visibleCount = linksBox.querySelectorAll('.about-link-tile:not(.hidden)').length;
      linksBox.classList.toggle('hidden', visibleCount === 0);
    }

    // روابط التواصل الاجتماعي
    const socialBox = document.getElementById('about-social');
    _bindLink('btn-x-url', links.x_url);
    _bindLink('btn-instagram-url', links.instagram_url);
    _bindLink('btn-snapchat-url', links.snapchat_url);
    _bindLink('btn-tiktok-url', links.tiktok_url);
    _bindLink('btn-youtube-url', links.youtube_url);
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
    const heroMediaWrap = document.getElementById('about-hero-media-wrap');
    const heroMedia = document.getElementById('about-hero-media');
    const heroVideo = document.getElementById('about-hero-video');
    const mediaBlock = _pickHeroMedia(blocks);

    if (heroTitle) heroTitle.textContent = _resolveTitle(blocks.about_hero_title, 'منصة نوافذ');
    if (heroSubtitle) {
      heroSubtitle.textContent = _resolveTitle(
        blocks.about_hero_subtitle,
        'حلول تقنية مبتكرة تربط مزودي الخدمات بطالبيها',
      );
    }
    if (website) website.textContent = _resolveTitle(blocks.about_website_label, 'الموقع الرسمي');
    if (heroMediaWrap && heroMedia && heroVideo) {
      heroMediaWrap.classList.add('hidden');
      heroMedia.classList.add('hidden');
      heroVideo.classList.add('hidden');
      if (mediaBlock && mediaBlock.media_url) {
        heroMediaWrap.classList.remove('hidden');
        if (mediaBlock.media_type === 'video') {
          heroVideo.src = mediaBlock.media_url;
          heroVideo.classList.remove('hidden');
        } else {
          heroMedia.src = mediaBlock.media_url;
          heroMedia.classList.remove('hidden');
        }
      }
    }
  }

  function _mapBlocks(blocks) {
    return [
      _resolveSection('about', blocks[SECTION_META.about.key], 'من نحن', '', SECTION_META.about),
      _resolveSection('vision', blocks[SECTION_META.vision.key], 'رؤيتنا', '', SECTION_META.vision),
      _resolveSection('goals', blocks[SECTION_META.goals.key], 'أهدافنا', '', SECTION_META.goals),
      _resolveSection('values', blocks[SECTION_META.values.key], 'قيمنا', '', SECTION_META.values),
      _resolveSection('app', blocks[SECTION_META.app.key], 'عن التطبيق', '', SECTION_META.app),
    ].filter((item) => item.body || item.title);
  }

  function _resolveSection(id, apiBlock, fallbackTitle, fallbackBody, meta) {
    return {
      id,
      title: _resolveTitle(apiBlock, fallbackTitle),
      body: _resolveBody(apiBlock, fallbackBody),
      icon: meta.icon,
      tone: meta.tone,
    };
  }

  function _resolveTitle(block, fallback) {
    return String(block && block.title_ar || '').trim() || fallback;
  }

  function _resolveBody(block, fallback) {
    return String(block && block.body_ar || '').trim() || fallback;
  }

  function _buildCard(data) {
    const card = UI.el('article', {
      className: `about-card about-card-${data.tone || 'primary'}`,
      'data-key': data.id || '',
    });
    const badge = UI.el('div', { className: 'about-card-icon', textContent: data.icon || '📄' });
    const title = UI.el('h3', { className: 'about-card-title', textContent: data.title || '' });
    const body = UI.el('p', { className: 'about-card-body', textContent: data.body || '' });

    card.appendChild(badge);
    card.appendChild(title);
    card.appendChild(body);
    return card;
  }

  function _pickHeroMedia(blocks) {
    const candidates = [blocks.about_hero_title, blocks.about_hero_subtitle];
    return candidates.find((item) => item && item.media_url) || null;
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
