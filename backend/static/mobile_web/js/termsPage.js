/* ===================================================================
   termsPage.js — Terms and legal documents page
   GET /api/content/public/
   =================================================================== */
'use strict';

const TermsPage = (() => {
  const DOC_META = {
    terms: { title: 'اتفاقية الاستخدام', icon: '📘' },
    privacy: { title: 'سياسة الخصوصية', icon: '🛡️' },
    regulations: { title: 'الأنظمة والتشريعات المتبعة', icon: '⚖️' },
    prohibited_services: { title: 'الخدمات الممنوعة', icon: '⛔' },
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

    const res = await ApiClient.get('/api/content/public/');
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

    if (loading) loading.classList.add('hidden');
    if (!cards.length) {
      if (empty) empty.classList.remove('hidden');
      return;
    }

    if (!list) return;
    list.innerHTML = '';
    cards.forEach((item, idx) => {
      list.appendChild(_buildCard(item, idx));
    });
    list.classList.remove('hidden');
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
      const meta = DOC_META[docType] || { title: docType, icon: '📄' };
      const published = doc && doc.published_at ? _formatDate(doc.published_at) : '';
      const version = doc && doc.version ? 'الإصدار ' + doc.version : '';
      const body = doc && doc.body_ar ? String(doc.body_ar).trim() : '';
      const fileUrl = doc && doc.file_url ? ApiClient.mediaUrl(doc.file_url) : '';
      const subtitle = [version, published ? 'آخر تحديث: ' + published : ''].filter(Boolean).join(' • ');
      return {
        title: doc.label_ar || meta.title,
        icon: meta.icon,
        last_update: subtitle,
        content: body || (fileUrl ? _content.fileOnlyHint : _content.missingHint),
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

  function _buildCard(item, idx) {
    const card = UI.el('article', { className: 'expand-card' });
    const head = UI.el('button', { className: 'expand-head', type: 'button' });
    const body = UI.el('div', { className: 'expand-body hidden' });

    head.appendChild(UI.el('span', { className: 'expand-icon', textContent: item.icon || '📄' }));
    const textWrap = UI.el('span', { className: 'expand-head-text' });
    textWrap.appendChild(UI.el('span', { className: 'expand-title', textContent: item.title || 'مستند' }));
    textWrap.appendChild(
      UI.el('span', { className: 'expand-subtitle', textContent: item.last_update || ' ' }),
    );
    head.appendChild(textWrap);
    head.appendChild(UI.el('span', { className: 'expand-arrow', textContent: '⌄' }));

    body.appendChild(UI.el('p', {
      className: 'expand-content',
      textContent: item.content || '',
      style: { whiteSpace: 'pre-line' },
    }));
    if (item.file_url) {
      const openBtn = UI.el('a', {
        className: 'btn-secondary expand-open-btn',
        href: item.file_url,
        target: '_blank',
        rel: 'noopener',
        textContent: _content.openDocumentLabel || 'عرض المستند',
      });
      body.appendChild(openBtn);
    }

    head.addEventListener('click', () => {
      const isOpen = !body.classList.contains('hidden');
      document.querySelectorAll('.expand-card').forEach((node) => node.classList.remove('active'));
      document.querySelectorAll('.expand-card .expand-body').forEach((node) => node.classList.add('hidden'));
      if (!isOpen) {
        card.classList.add('active');
        body.classList.remove('hidden');
      }
    });

    card.dataset.index = String(idx);
    card.appendChild(head);
    card.appendChild(body);
    return card;
  }

  function _resolve(block, fallback) {
    return String(block && block.title_ar || '').trim() || fallback;
  }

  function _setText(id, value) {
    const el = document.getElementById(id);
    if (el && value) el.textContent = value;
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  return {};
})();
