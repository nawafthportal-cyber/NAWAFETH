/* ===================================================================
   aboutPage.js — About platform page
   GET /api/content/public/
   =================================================================== */
'use strict';

const AboutPage = (() => {
  const COPY = {
    ar: {
      pageTitle: 'من نحن',
      heroBadge: 'عن المنصة',
      heroTitle: 'منصة نوافذ',
      heroSubtitle: 'حلول رقمية واضحة تربط العملاء بمزودي الخدمات بسرعة وموثوقية.',
      heroPanelKicker: 'الوصول الرسمي',
      heroPanelTitle: 'روابط موثقة وهوية واضحة',
      loadError: 'تعذر تحميل محتوى الصفحة الآن. حاول مرة أخرى بعد قليل.',
      storyKicker: 'نبذة',
      storyTitle: 'تعرف على نوافذ',
      storyEmpty: 'لا توجد أقسام تعريفية منشورة حاليًا.',
      linksKicker: 'روابط',
      linksTitle: 'موقع المنصة',
      androidCaption: 'تطبيق Android',
      iosCaption: 'تطبيق iPhone',
      websiteLabel: 'الموقع الرسمي',
      websiteCaption: 'زيارة موقع نوافذ',
      socialKicker: 'تواصل',
      socialTitle: 'تواصل معنا',
      whatsappLabel: 'واتساب',
      emailLabel: 'البريد',
      heroMediaAlt: 'صورة تعريفية عن المنصة',
      sections: {
        about: { title: 'من نحن', body: 'نوافذ منصة سعودية تساعد الأفراد والمنشآت على الوصول إلى مزودي الخدمات وإدارة التواصل معهم عبر تجربة موحدة وواضحة.' },
        vision: { title: 'رؤيتنا', body: 'أن تكون نوافذ نقطة الوصول الأولى للخدمات في المملكة عبر تجربة عالية الموثوقية وسهلة الاستخدام.' },
        goals: { title: 'أهدافنا', body: 'تقليل وقت الوصول إلى الخدمة، وتحسين جودة التواصل، ورفع شفافية التعامل بين جميع أطراف المنصة.' },
        values: { title: 'قيمنا', body: 'الوضوح، السرعة، الجودة، والالتزام بتجربة استخدام عملية ومفهومة.' },
        app: { title: 'عن التطبيق', body: 'يمكنك عبر تطبيق نوافذ استعراض الخدمات، إدارة الطلبات، والتواصل مع مزودي الخدمة من مكان واحد.' },
      },
    },
    en: {
      pageTitle: 'About Nawafeth',
      heroBadge: 'About the platform',
      heroTitle: 'Nawafeth Platform',
      heroSubtitle: 'Clear digital solutions that connect customers with service providers quickly and reliably.',
      heroPanelKicker: 'Official access',
      heroPanelTitle: 'Verified links and a clear identity',
      loadError: 'Unable to load the page content right now. Please try again shortly.',
      storyKicker: 'Overview',
      storyTitle: 'Get to know Nawafeth',
      storyEmpty: 'No public introduction sections are published right now.',
      linksKicker: 'Links',
      linksTitle: 'Platform website',
      androidCaption: 'Android app',
      iosCaption: 'iPhone app',
      websiteLabel: 'Official website',
      websiteCaption: 'Visit Nawafeth website',
      socialKicker: 'Connect',
      socialTitle: 'Contact us',
      whatsappLabel: 'WhatsApp',
      emailLabel: 'Email',
      heroMediaAlt: 'Platform introduction visual',
      sections: {
        about: { title: 'Who we are', body: 'Nawafeth is a Saudi platform that helps individuals and businesses reach service providers and manage communication through one clear experience.' },
        vision: { title: 'Our vision', body: 'To become the first point of access for services in the Kingdom through a highly reliable and easy-to-use experience.' },
        goals: { title: 'Our goals', body: 'Reduce the time needed to reach services, improve communication quality, and increase transparency between all platform parties.' },
        values: { title: 'Our values', body: 'Clarity, speed, quality, and commitment to a practical and understandable user experience.' },
        app: { title: 'About the app', body: 'Through the Nawafeth app, you can browse services, manage requests, and communicate with providers from one place.' },
      },
    },
  };
  const SECTION_META = {
    about: { key: 'about_section_about', icon: 'ℹ️', tone: 'primary' },
    vision: { key: 'about_section_vision', icon: '👁️', tone: 'violet' },
    goals: { key: 'about_section_goals', icon: '🎯', tone: 'amber' },
    values: { key: 'about_section_values', icon: '⭐', tone: 'emerald' },
    app: { key: 'about_section_app', icon: '📱', tone: 'slate' },
  };
  let _blocks = {};

  function init() {
    _applyStaticCopy();
    document.addEventListener('nawafeth:languagechange', _handleLanguageChange);
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
    _blocks = blocks;
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
    const socialTitle = _resolveTitle(blocks.about_social_title, _copy().socialTitle, _copy().socialTitle);
    const socialTitleEl = document.getElementById('about-social-title');
    if (socialTitleEl) socialTitleEl.textContent = socialTitle;
    if (socialBox) {
      const visibleSocial = socialBox.querySelectorAll('a:not(.hidden)').length;
      socialBox.classList.toggle('hidden', visibleSocial === 0);
    }

    if (loading) loading.classList.add('hidden');
  }

  function _applyHeroContent(blocks) {
    const copy = _copy();
    const heroTitle = document.getElementById('about-hero-title');
    const heroSubtitle = document.getElementById('about-hero-subtitle');
    const websiteLabel = document.querySelector('#btn-website .about-link-label');
    const heroMediaWrap = document.getElementById('about-hero-media-wrap');
    const heroMedia = document.getElementById('about-hero-media');
    const heroVideo = document.getElementById('about-hero-video');
    const mediaBlock = _pickHeroMedia(blocks);

    if (heroTitle) heroTitle.textContent = _resolveTitle(blocks.about_hero_title, COPY.ar.heroTitle, copy.heroTitle);
    if (heroSubtitle) {
      heroSubtitle.textContent = _resolveTitle(
        blocks.about_hero_subtitle,
        COPY.ar.heroSubtitle,
        copy.heroSubtitle,
      );
    }
    if (websiteLabel) websiteLabel.textContent = _resolveTitle(blocks.about_website_label, COPY.ar.websiteLabel, copy.websiteLabel);
    if (heroMediaWrap && heroMedia && heroVideo) {
      heroMediaWrap.classList.add('hidden');
      heroMedia.classList.add('hidden');
      heroVideo.classList.add('hidden');
      heroMedia.alt = copy.heroMediaAlt;
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
      _resolveSection('about', blocks[SECTION_META.about.key], SECTION_META.about),
      _resolveSection('vision', blocks[SECTION_META.vision.key], SECTION_META.vision),
      _resolveSection('goals', blocks[SECTION_META.goals.key], SECTION_META.goals),
      _resolveSection('values', blocks[SECTION_META.values.key], SECTION_META.values),
      _resolveSection('app', blocks[SECTION_META.app.key], SECTION_META.app),
    ].filter((item) => item.body || item.title);
  }

  function _resolveSection(id, apiBlock, meta) {
    const arCopy = COPY.ar.sections[id] || { title: '', body: '' };
    const langCopy = (_copy().sections && _copy().sections[id]) || arCopy;
    return {
      id,
      title: _resolveTitle(apiBlock, arCopy.title, langCopy.title),
      body: _resolveBody(apiBlock, arCopy.body, langCopy.body),
      icon: meta.icon,
      tone: meta.tone,
    };
  }

  function _resolveTitle(block, fallbackAr, fallbackEn) {
    return _resolveLocalized(block, 'title', fallbackAr, fallbackEn);
  }

  function _resolveBody(block, fallbackAr, fallbackEn) {
    return _resolveLocalized(block, 'body', fallbackAr, fallbackEn);
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

  function _resolveLocalized(block, field, fallbackAr, fallbackEn) {
    const lang = _currentLang();
    const arValue = String(block && block[field + '_ar'] || '').trim();
    const enValue = String(block && block[field + '_en'] || '').trim();
    if (lang === 'en') {
      if (enValue) return enValue;
      if (arValue && arValue !== String(fallbackAr || '').trim()) return arValue;
      return String(fallbackEn || '').trim() || arValue || String(fallbackAr || '').trim();
    }
    return arValue || String(fallbackAr || '').trim();
  }

  function _currentLang() {
    try {
      if (window.NawafethI18n && typeof window.NawafethI18n.getLanguage === 'function') {
        return window.NawafethI18n.getLanguage() === 'en' ? 'en' : 'ar';
      }
      return (localStorage.getItem('nw_lang') || 'ar').toLowerCase() === 'en' ? 'en' : 'ar';
    } catch (_) {
      return 'ar';
    }
  }

  function _copy() {
    return COPY[_currentLang()] || COPY.ar;
  }

  function _applyStaticCopy() {
    const copy = _copy();
    _setText('about-hero-badge', copy.heroBadge);
    _setText('about-hero-panel-kicker', copy.heroPanelKicker);
    _setText('about-hero-panel-title', copy.heroPanelTitle);
    _setText('about-error', copy.loadError);
    _setText('about-section-kicker', copy.storyKicker);
    _setText('about-section-title', copy.storyTitle);
    _setText('about-empty', copy.storyEmpty);
    _setText('about-links-kicker', copy.linksKicker);
    _setText('about-links-title', copy.linksTitle);
    _setText('about-android-caption', copy.androidCaption);
    _setText('about-ios-caption', copy.iosCaption);
    _setText('about-website-caption', copy.websiteCaption);
    _setText('about-social-kicker', copy.socialKicker);
    _setText('about-whatsapp-label', copy.whatsappLabel);
    _setText('about-email-label', copy.emailLabel);
    const whatsapp = document.getElementById('btn-whatsapp');
    const email = document.getElementById('btn-email');
    if (whatsapp) whatsapp.setAttribute('title', copy.whatsappLabel);
    if (email) email.setAttribute('title', copy.emailLabel);
    if (window.NawafethI18n && typeof window.NawafethI18n.t === 'function') {
      document.title = window.NawafethI18n.t('siteTitle') + ' — ' + copy.pageTitle;
    }
  }

  function _setText(id, value) {
    const node = document.getElementById(id);
    if (node && value) node.textContent = value;
  }

  function _handleLanguageChange() {
    _applyStaticCopy();
    _applyHeroContent(_blocks || {});
    const sections = document.getElementById('about-sections');
    if (sections) {
      const mapped = _mapBlocks(_blocks || {});
      sections.innerHTML = '';
      mapped.forEach((item) => sections.appendChild(_buildCard(item)));
    }
    const socialTitleEl = document.getElementById('about-social-title');
    if (socialTitleEl) {
      socialTitleEl.textContent = _resolveTitle((_blocks || {}).about_social_title, COPY.ar.socialTitle, _copy().socialTitle);
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  return {};
})();
