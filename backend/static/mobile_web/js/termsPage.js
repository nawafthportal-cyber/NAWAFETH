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

  const FALLBACK = [
    {
      title: 'اتفاقية الاستخدام',
      icon: '📘',
      last_update: 'آخر تحديث: 10-08-2025',
      content: 'باستخدامك للمنصة، فإنك توافق على الالتزام بالشروط والأحكام.',
      file_url: '',
    },
    {
      title: 'سياسة الخصوصية',
      icon: '🛡️',
      last_update: 'آخر تحديث: 05-08-2025',
      content: 'تحرص المنصة على حماية بيانات المستخدمين وفق الأنظمة المعمول بها.',
      file_url: '',
    },
  ];

  function init() {
    _load();
  }

  async function _load() {
    const loading = document.getElementById('terms-loading');
    const list = document.getElementById('terms-list');
    const empty = document.getElementById('terms-empty');

    const res = await ApiClient.get('/api/content/public/');
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
      return FALLBACK;
    }
    const documents = res.data.documents || {};
    const entries = Object.entries(documents);
    if (!entries.length) return FALLBACK;

    return entries.map(([docType, doc]) => {
      const meta = DOC_META[docType] || { title: docType, icon: '📄' };
      const published = doc && doc.published_at ? _formatDate(doc.published_at) : '';
      return {
        title: meta.title,
        icon: meta.icon,
        last_update: published ? 'آخر تحديث: ' + published : '',
        content: 'اضغط على "عرض المستند" لفتح النسخة الرسمية.',
        file_url: doc && doc.file_url ? ApiClient.mediaUrl(doc.file_url) : '',
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

    body.appendChild(UI.el('p', { className: 'expand-content', textContent: item.content || '' }));
    if (item.file_url) {
      const openBtn = UI.el('a', {
        className: 'btn-secondary expand-open-btn',
        href: item.file_url,
        target: '_blank',
        rel: 'noopener',
        textContent: 'عرض المستند',
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

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  return {};
})();
