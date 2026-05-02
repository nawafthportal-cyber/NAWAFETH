/* ===================================================================
   termsPage.js — Terms and legal documents page
   GET /api/content/public/
   =================================================================== */
'use strict';

const TermsPage = (() => {
  const COPY = {
    ar: {
      pageTitle: 'الشروط والأحكام',
      heroKicker: 'المركز القانوني',
      pageSummary: 'اطلع على سياسات نوافذ الرسمية بطريقة واضحة ومنظمة قبل استخدام خدمات المنصة.',
      documentsLabel: 'المستندات',
      latestUpdateLabel: 'آخر تحديث',
      officialFilesLabel: 'مرفقات رسمية',
      railTitle: 'المستندات',
      railAria: 'مستندات الشروط',
      emptyLabel: 'لا توجد مستندات متاحة حالياً',
      openDocumentLabel: 'عرض المستند',
      fileOnlyHint: 'اضغط على زر عرض المستند لفتح النسخة الرسمية.',
      missingHint: 'لا توجد بيانات متاحة لهذا المستند حالياً.',
      versionPrefix: 'الإصدار',
      lastUpdatePrefix: 'آخر تحديث:',
      informationalVersion: 'نسخة معلوماتية',
      documentFallback: 'مستند',
      clauseFallback: 'بند',
      docMeta: {
        terms: 'اتفاقية الاستخدام',
        privacy: 'سياسة الخصوصية',
        regulations: 'الأنظمة والتشريعات المتبعة',
        prohibited_services: 'الخدمات الممنوعة',
      },
    },
    en: {
      pageTitle: 'Terms & Conditions',
      heroKicker: 'Legal center',
      pageSummary: 'Review Nawafeth official policies in a clear and organized way before using platform services.',
      documentsLabel: 'Documents',
      latestUpdateLabel: 'Latest update',
      officialFilesLabel: 'Official files',
      railTitle: 'Documents',
      railAria: 'Legal documents',
      emptyLabel: 'No documents are available right now.',
      openDocumentLabel: 'Open document',
      fileOnlyHint: 'Click open document to view the official version.',
      missingHint: 'No data is currently available for this document.',
      versionPrefix: 'Version',
      lastUpdatePrefix: 'Last update:',
      informationalVersion: 'Informational copy',
      documentFallback: 'Document',
      clauseFallback: 'Clause',
      docMeta: {
        terms: 'Terms of Use',
        privacy: 'Privacy Policy',
        regulations: 'Applicable Regulations',
        prohibited_services: 'Prohibited Services',
      },
    },
  };
  const DOC_META = {
    terms: { titleAr: 'اتفاقية الاستخدام', titleEn: 'Terms of Use', icon: 'document' },
    privacy: { titleAr: 'سياسة الخصوصية', titleEn: 'Privacy Policy', icon: 'shield' },
    regulations: { titleAr: 'الأنظمة والتشريعات المتبعة', titleEn: 'Applicable Regulations', icon: 'scale' },
    prohibited_services: { titleAr: 'الخدمات الممنوعة', titleEn: 'Prohibited Services', icon: 'ban' },
  };
  const DOC_ORDER = ['terms', 'privacy', 'regulations', 'prohibited_services'];
  let _content = {};
  let _payload = null;

  function init() {
    _applyStaticCopy();
    document.addEventListener('nawafeth:languagechange', _handleLanguageChange);
    _load();
  }

  async function _load() {
    const loading = document.getElementById('terms-loading');
    const list = document.getElementById('terms-list');
    const empty = document.getElementById('terms-empty');
    const rail = document.getElementById('terms-rail');
    const nav = document.getElementById('terms-nav');

    const res = await _safeLoadContent();
    _payload = res;
    const data = (res.ok && res.data && typeof res.data === 'object') ? res.data : {};
    const blocks = data.blocks || {};
    _content = {
      pageTitle: _resolve(blocks.terms_page_title, COPY.ar.pageTitle, _copy().pageTitle),
      emptyLabel: _resolve(blocks.terms_empty_label, COPY.ar.emptyLabel, _copy().emptyLabel),
      openDocumentLabel: _resolve(blocks.terms_open_document_label, COPY.ar.openDocumentLabel, _copy().openDocumentLabel),
      fileOnlyHint: _resolve(blocks.terms_file_only_hint, COPY.ar.fileOnlyHint, _copy().fileOnlyHint),
      missingHint: _resolve(blocks.terms_missing_document_hint, COPY.ar.missingHint, _copy().missingHint),
    };
    _applyStaticCopy();
    _setText('terms-page-title', _content.pageTitle);
    _setText('terms-empty-label', _content.emptyLabel);
    const cards = _extractCards(res);
    _renderStats(cards);

    if (loading) loading.classList.add('hidden');
    if (!cards.length) {
      if (empty) empty.classList.remove('hidden');
      if (rail) rail.classList.add('hidden');
      return;
    }

    if (!list) return;
    list.innerHTML = '';
    if (nav) nav.innerHTML = '';
    cards.forEach((item, idx) => {
      list.appendChild(_buildDocument(item, idx));
      if (nav) nav.appendChild(_buildNavLink(item, idx));
    });
    list.classList.remove('hidden');
    if (rail) rail.classList.remove('hidden');
    _bindActiveNav();
  }

  async function _safeLoadContent() {
    try {
      return await ApiClient.get('/api/content/public/');
    } catch (err) {
      return { ok: false, data: null, error: err };
    }
  }

  function _extractCards(res) {
    if (!res.ok || !res.data || typeof res.data !== 'object') {
      return [];
    }
    const documents = res.data.documents || {};
    const orderedTypes = DOC_ORDER.filter((docType) => documents[docType]).concat(
      Object.keys(documents).filter((docType) => !DOC_ORDER.includes(docType)),
    );
    if (!orderedTypes.length) return [];

    return orderedTypes.map((docType) => {
      const doc = documents[docType] || {};
      const meta = DOC_META[docType] || { title: docType, icon: 'document' };
      const published = doc && doc.published_at ? _formatDate(doc.published_at) : '';
      const publishedTime = doc && doc.published_at ? new Date(doc.published_at).getTime() : 0;
      const version = doc && doc.version ? _copy().versionPrefix + ' ' + doc.version : '';
      const body = doc && doc.body_ar ? String(doc.body_ar).trim() : '';
      const fileUrl = doc && doc.file_url ? ApiClient.mediaUrl(doc.file_url) : '';
      const subtitle = [version, published ? _copy().lastUpdatePrefix + ' ' + published : ''].filter(Boolean).join(' | ');
      return {
        key: docType,
        id: 'terms-doc-' + _slug(docType),
        title: _resolveDocTitle(docType, doc, meta),
        icon: meta.icon || 'document',
        version,
        published,
        publishedTime: Number.isNaN(publishedTime) ? 0 : publishedTime,
        last_update: subtitle,
        content: body || (fileUrl ? _content.fileOnlyHint : _content.missingHint),
        clauses: _parseClauses(body || (fileUrl ? _content.fileOnlyHint : _content.missingHint)),
        file_url: fileUrl,
      };
    });
  }

  function _formatDate(iso) {
    const dt = new Date(iso);
    if (Number.isNaN(dt.getTime())) return '';
    return dt.toLocaleDateString(_currentLang() === 'en' ? 'en-US' : 'ar-SA', {
      day: '2-digit',
      month: '2-digit',
      year: 'numeric',
    });
  }

  function _renderStats(cards) {
    _setText('terms-doc-count', String(cards.length));
    _setText('terms-file-count', String(cards.filter((card) => card.file_url).length));
    const latestCard = cards.slice().sort((a, b) => (b.publishedTime || 0) - (a.publishedTime || 0))[0];
    const latest = latestCard && latestCard.published ? latestCard.published : '-';
    _setText('terms-latest-update', latest);
  }

  function _buildDocument(item, idx) {
    const card = UI.el('article', {
      className: 'terms-doc-card',
      id: item.id,
      'data-terms-doc': item.key || String(idx),
    });
    const head = UI.el('header', { className: 'terms-doc-head' });
    const titleWrap = UI.el('div', { className: 'terms-doc-title-wrap' });
    const icon = UI.el('span', { className: 'terms-doc-icon', 'aria-hidden': 'true' });
    icon.appendChild(_icon(item.icon));

    const copy = UI.el('div', { className: 'terms-doc-copy' });
    copy.appendChild(UI.el('h2', { className: 'terms-doc-title', textContent: item.title || _copy().documentFallback }));
    const meta = UI.el('div', { className: 'terms-doc-meta' });
    if (item.version) meta.appendChild(UI.el('span', { textContent: item.version }));
    if (item.published) meta.appendChild(UI.el('span', { textContent: _copy().lastUpdatePrefix + ' ' + item.published }));
    if (!item.version && !item.published) meta.appendChild(UI.el('span', { textContent: _copy().informationalVersion }));
    copy.appendChild(meta);

    titleWrap.appendChild(icon);
    titleWrap.appendChild(copy);
    head.appendChild(titleWrap);

    if (item.file_url) {
      const openBtn = UI.el('a', {
        className: 'terms-open-document',
        href: item.file_url,
        target: '_blank',
        rel: 'noopener',
        textContent: _content.openDocumentLabel || 'عرض المستند',
      });
      openBtn.appendChild(_icon('external'));
      head.appendChild(openBtn);
    }

    const body = UI.el('div', { className: 'terms-doc-body' });
    item.clauses.forEach((clause, clauseIndex) => {
      body.appendChild(_buildClause(clause, clauseIndex));
    });

    card.appendChild(head);
    card.appendChild(body);
    return card;
  }

  function _buildNavLink(item, idx) {
    const link = UI.el('a', {
      className: 'terms-nav-link' + (idx === 0 ? ' is-active' : ''),
      href: '#' + item.id,
      'data-terms-target': item.id,
    });
    const icon = UI.el('span', { className: 'terms-nav-icon', 'aria-hidden': 'true' });
    icon.appendChild(_icon(item.icon));
    link.appendChild(icon);
    link.appendChild(UI.el('span', { textContent: item.title || _copy().documentFallback }));
    return link;
  }

  function _buildClause(clause, idx) {
    const article = UI.el('article', { className: 'terms-clause' });
    article.appendChild(UI.el('span', {
      className: 'terms-clause-number',
      textContent: clause.number || _localizeDigits(String(idx + 1)),
    }));
    const copy = UI.el('div', { className: 'terms-clause-copy' });
    copy.appendChild(UI.el('h3', { textContent: clause.title || _copy().clauseFallback }));
    if (clause.body) {
      copy.appendChild(UI.el('p', { textContent: clause.body }));
    }
    article.appendChild(copy);
    return article;
  }

  function _parseClauses(raw) {
    const lines = String(raw || '')
      .replace(/\r/g, '')
      .split('\n')
      .map((line) => line.trim())
      .filter(Boolean);
    if (!lines.length) return [];

    const clauses = [];
    let current = null;
    const headingPattern = /^([0-9٠-٩]+)[\.\-ـ:)]\s*(.+)$/;

    lines.forEach((line) => {
      const match = line.match(headingPattern);
      if (match) {
        if (current) clauses.push(current);
        current = {
          number: _localizeDigits(match[1]),
          number: _localizeDigits(match[1]),
          title: match[2].trim(),
          lines: [],
        };
        return;
      }
      if (!current) {
        current = {
          number: _localizeDigits(String(clauses.length + 1)),
          title: line,
          lines: [],
        };
        return;
      }
      current.lines.push(line);
    });

    if (current) clauses.push(current);
    return clauses.map((clause) => ({
      number: clause.number,
      title: clause.title,
      body: clause.lines.join('\n'),
    }));
  }

  function _bindActiveNav() {
    const links = Array.from(document.querySelectorAll('.terms-nav-link'));
    const docs = Array.from(document.querySelectorAll('.terms-doc-card'));
    if (!links.length || !docs.length || !('IntersectionObserver' in window)) return;

    const setActive = (id) => {
      links.forEach((link) => {
        link.classList.toggle('is-active', link.getAttribute('data-terms-target') === id);
      });
    };

    const observer = new IntersectionObserver((entries) => {
      const visible = entries
        .filter((entry) => entry.isIntersecting)
        .sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0];
      if (visible && visible.target && visible.target.id) setActive(visible.target.id);
    }, { rootMargin: '-18% 0px -60% 0px', threshold: [0.2, 0.45, 0.7] });

    docs.forEach((doc) => observer.observe(doc));
  }

  function _icon(name) {
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('width', '18');
    svg.setAttribute('height', '18');
    svg.setAttribute('viewBox', '0 0 24 24');
    svg.setAttribute('fill', 'none');
    svg.setAttribute('stroke', 'currentColor');
    svg.setAttribute('stroke-width', '2');
    svg.setAttribute('stroke-linecap', 'round');
    svg.setAttribute('stroke-linejoin', 'round');
    const paths = {
      document: [
        ['path', { d: 'M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z' }],
        ['path', { d: 'M14 2v6h6' }],
        ['path', { d: 'M9 13h6' }],
        ['path', { d: 'M9 17h6' }],
      ],
      shield: [
        ['path', { d: 'M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z' }],
        ['path', { d: 'M9 12l2 2 4-5' }],
      ],
      scale: [
        ['path', { d: 'M12 3v18' }],
        ['path', { d: 'M6 7h12' }],
        ['path', { d: 'M6 7l-3 6h6L6 7z' }],
        ['path', { d: 'M18 7l-3 6h6l-3-6z' }],
        ['path', { d: 'M8 21h8' }],
      ],
      ban: [
        ['circle', { cx: '12', cy: '12', r: '9' }],
        ['path', { d: 'M5.7 5.7l12.6 12.6' }],
      ],
      external: [
        ['path', { d: 'M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6' }],
        ['path', { d: 'M15 3h6v6' }],
        ['path', { d: 'M10 14L21 3' }],
      ],
    };
    (paths[name] || paths.document).forEach(([tag, attrs]) => {
      const node = document.createElementNS('http://www.w3.org/2000/svg', tag);
      Object.keys(attrs).forEach((key) => node.setAttribute(key, attrs[key]));
      svg.appendChild(node);
    });
    return svg;
  }

  function _resolve(block, fallbackAr, fallbackEn) {
    const arValue = String(block && block.title_ar || '').trim();
    const enValue = String(block && block.title_en || '').trim();
    if (_currentLang() === 'en') {
      if (enValue) return enValue;
      if (arValue && arValue !== String(fallbackAr || '').trim()) return arValue;
      return String(fallbackEn || '').trim() || arValue || String(fallbackAr || '').trim();
    }
    return arValue || String(fallbackAr || '').trim();
  }

  function _setText(id, value) {
    const el = document.getElementById(id);
    if (el && value) el.textContent = value;
  }

  function _slug(value) {
    return String(value || '').replace(/[^a-zA-Z0-9_-]+/g, '-').replace(/^-+|-+$/g, '') || 'document';
  }

  function _localizeDigits(value) {
    const raw = String(value || '');
    if (_currentLang() === 'en') return raw;
    return raw.replace(/[0-9]/g, (digit) => '٠١٢٣٤٥٦٧٨٩'[Number(digit)] || digit);
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

  function _resolveDocTitle(docType, doc, meta) {
    const arLabel = String(doc && doc.label_ar || '').trim();
    const enLabel = String(doc && doc.label_en || '').trim();
    const fallbackAr = meta.titleAr || (COPY.ar.docMeta[docType] || COPY.ar.documentFallback);
    const fallbackEn = meta.titleEn || (_copy().docMeta[docType] || COPY.en.documentFallback);
    if (_currentLang() === 'en') {
      if (enLabel) return enLabel;
      return fallbackEn || arLabel || fallbackAr;
    }
    return arLabel || fallbackAr;
  }

  function _applyStaticCopy() {
    const copy = _copy();
    _setText('terms-kicker', copy.heroKicker);
    _setText('terms-page-summary', copy.pageSummary);
    _setText('terms-documents-label', copy.documentsLabel);
    _setText('terms-latest-update-label', copy.latestUpdateLabel);
    _setText('terms-file-count-label', copy.officialFilesLabel);
    _setText('terms-rail-title', copy.railTitle);
    const railMeta = document.getElementById('terms-hero-meta');
    const nav = document.getElementById('terms-nav');
    if (railMeta) railMeta.setAttribute('aria-label', copy.railTitle);
    if (nav) nav.setAttribute('aria-label', copy.railAria);
    if (window.NawafethI18n && typeof window.NawafethI18n.t === 'function') {
      document.title = window.NawafethI18n.t('siteTitle') + ' — ' + copy.pageTitle;
    }
  }

  function _handleLanguageChange() {
    _applyStaticCopy();
    if (_payload) {
      _load();
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  return {};
})();
