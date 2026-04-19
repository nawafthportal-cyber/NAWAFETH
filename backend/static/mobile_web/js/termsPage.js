/* ===================================================================
   termsPage.js — Terms and legal documents page
   GET /api/content/public/
   =================================================================== */
'use strict';

const TermsPage = (() => {
  const DOC_META = {
    terms: { title: 'اتفاقية الاستخدام', icon: 'document' },
    privacy: { title: 'سياسة الخصوصية', icon: 'shield' },
    regulations: { title: 'الأنظمة والتشريعات المتبعة', icon: 'scale' },
    prohibited_services: { title: 'الخدمات الممنوعة', icon: 'ban' },
  };
  const DOC_ORDER = ['terms', 'privacy', 'regulations', 'prohibited_services'];
  let _content = {};

  function init() {
    _load();
  }

  async function _load() {
    const loading = document.getElementById('terms-loading');
    const list = document.getElementById('terms-list');
    const empty = document.getElementById('terms-empty');
    const rail = document.getElementById('terms-rail');
    const nav = document.getElementById('terms-nav');

    const res = await _safeLoadContent();
    const data = (res.ok && res.data && typeof res.data === 'object') ? res.data : {};
    const blocks = data.blocks || {};
    _content = {
      pageTitle: _resolve(blocks.terms_page_title, 'الشروط والأحكام'),
      emptyLabel: _resolve(blocks.terms_empty_label, 'لا توجد مستندات متاحة حالياً'),
      openDocumentLabel: _resolve(blocks.terms_open_document_label, 'عرض المستند'),
      fileOnlyHint: _resolve(blocks.terms_file_only_hint, 'اضغط على "عرض المستند" لفتح النسخة الرسمية.'),
      missingHint: _resolve(blocks.terms_missing_document_hint, 'لا توجد بيانات متاحة لهذا المستند حالياً.'),
    };
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
      const version = doc && doc.version ? 'الإصدار ' + doc.version : '';
      const body = doc && doc.body_ar ? String(doc.body_ar).trim() : '';
      const fileUrl = doc && doc.file_url ? ApiClient.mediaUrl(doc.file_url) : '';
      const subtitle = [version, published ? 'آخر تحديث: ' + published : ''].filter(Boolean).join(' | ');
      return {
        key: docType,
        id: 'terms-doc-' + _slug(docType),
        title: doc.label_ar || meta.title,
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
    return dt.toLocaleDateString('ar-SA', {
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
    copy.appendChild(UI.el('h2', { className: 'terms-doc-title', textContent: item.title || 'مستند' }));
    const meta = UI.el('div', { className: 'terms-doc-meta' });
    if (item.version) meta.appendChild(UI.el('span', { textContent: item.version }));
    if (item.published) meta.appendChild(UI.el('span', { textContent: 'آخر تحديث: ' + item.published }));
    if (!item.version && !item.published) meta.appendChild(UI.el('span', { textContent: 'نسخة معلوماتية' }));
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
    link.appendChild(UI.el('span', { textContent: item.title || 'مستند' }));
    return link;
  }

  function _buildClause(clause, idx) {
    const article = UI.el('article', { className: 'terms-clause' });
    article.appendChild(UI.el('span', {
      className: 'terms-clause-number',
      textContent: clause.number || _toArabicDigits(String(idx + 1)),
    }));
    const copy = UI.el('div', { className: 'terms-clause-copy' });
    copy.appendChild(UI.el('h3', { textContent: clause.title || 'بند' }));
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
          number: _toArabicDigits(match[1]),
          title: match[2].trim(),
          lines: [],
        };
        return;
      }
      if (!current) {
        current = {
          number: _toArabicDigits(String(clauses.length + 1)),
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

  function _resolve(block, fallback) {
    return String(block && block.title_ar || '').trim() || fallback;
  }

  function _setText(id, value) {
    const el = document.getElementById(id);
    if (el && value) el.textContent = value;
  }

  function _slug(value) {
    return String(value || '').replace(/[^a-zA-Z0-9_-]+/g, '-').replace(/^-+|-+$/g, '') || 'document';
  }

  function _toArabicDigits(value) {
    return String(value || '').replace(/[0-9]/g, (digit) => '٠١٢٣٤٥٦٧٨٩'[Number(digit)] || digit);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  return {};
})();
