/* ===================================================================
   providerDetailPage.js — Provider public profile detail
   GET /api/providers/{id}/
   GET /api/providers/{id}/services/
   GET /api/providers/{id}/portfolio/
   GET /api/reviews/providers/{id}/reviews/
   GET /api/reviews/providers/{id}/rating/
   POST /api/providers/{id}/follow/
   POST /api/providers/{id}/unfollow/
   =================================================================== */
'use strict';

const ProviderDetailPage = (() => {
  let _providerId = null;
  let _isFollowing = false;
  let _activeTab = 'profile';

  function init() {
    // Extract provider ID from URL: /provider/123/
    const match = window.location.pathname.match(/\/provider\/(\d+)/);
    if (!match) { document.body.innerHTML = '<p style="text-align:center;padding:60px">مقدم الخدمة غير موجود</p>'; return; }
    _providerId = match[1];

    // Tab clicks
    document.getElementById('prov-tabs').addEventListener('click', e => {
      const btn = e.target.closest('.tab-btn');
      if (!btn) return;
      document.querySelectorAll('#prov-tabs .tab-btn').forEach(t => t.classList.remove('active'));
      btn.classList.add('active');
      _activeTab = btn.dataset.tab;
      _switchTab();
    });

    // Action buttons
    document.getElementById('btn-follow').addEventListener('click', _toggleFollow);
    const msgBtn = document.getElementById('btn-message');
    if (msgBtn) msgBtn.addEventListener('click', () => {
      if (!Auth.isLoggedIn()) { Auth.requireLogin(window.location.pathname); return; }
      window.location.href = '/chats/?start=' + _providerId;
    });
    document.getElementById('btn-request').addEventListener('click', () => {
      window.location.href = '/search/?provider=' + _providerId;
    });

    _loadProvider();
    _loadServices();
    _loadPortfolio();
    _loadReviews();
  }

  function _switchTab() {
    ['profile', 'services', 'portfolio', 'reviews'].forEach(t => {
      const panel = document.getElementById('tab-' + t);
      if (panel) panel.classList.toggle('hidden', t !== _activeTab);
    });
  }

  /* ---------- Provider profile ---------- */
  async function _loadProvider() {
    const res = await ApiClient.get('/api/providers/' + _providerId + '/');
    if (!res.ok || !res.data) return;
    const p = res.data;

    // Cover
    const coverEl = document.getElementById('prov-cover');
    if (p.cover_image) {
      coverEl.innerHTML = '';
      coverEl.appendChild(UI.lazyImg(ApiClient.mediaUrl(p.cover_image), ''));
    }

    // Avatar
    const avatarEl = document.getElementById('prov-avatar');
    if (p.profile_image) {
      avatarEl.innerHTML = '';
      avatarEl.appendChild(UI.lazyImg(ApiClient.mediaUrl(p.profile_image), ''));
    } else {
      avatarEl.textContent = (p.display_name || '').charAt(0) || '؟';
    }

    // Name + badge
    document.getElementById('prov-name').textContent = p.display_name || '';
    const badge = document.getElementById('prov-badge');
    if (p.is_verified_blue) { badge.innerHTML = ''; badge.appendChild(UI.icon('verified_blue', 18, '#2196F3')); }
    else if (p.is_verified_green) { badge.innerHTML = ''; badge.appendChild(UI.icon('verified_green', 18, '#4CAF50')); }
    else badge.classList.add('hidden');

    // @handle
    const handleEl = document.getElementById('prov-handle');
    if (handleEl) handleEl.textContent = p.username ? ('@' + p.username) : '';

    // Category label
    const catEl = document.getElementById('prov-category');
    if (catEl) catEl.textContent = p.category_name || p.main_category || '';

    document.getElementById('prov-city').textContent = p.city || '';

    // Bio
    const bioEl = document.getElementById('prov-bio');
    if (bioEl) bioEl.textContent = p.bio || p.description || 'لا توجد نبذة';

    // Contact info
    const contactList = document.getElementById('prov-contact-list');
    if (contactList) {
      contactList.innerHTML = '';
      if (p.city) _addContactRow(contactList, 'location_on', p.city);
      if (p.phone && p.show_phone) _addContactRow(contactList, 'phone', p.phone);
      if (p.email && p.show_email) _addContactRow(contactList, 'email', p.email);
      if (p.website) _addContactRow(contactList, 'language', p.website);
    }

    // Working hours
    if (p.working_hours && p.working_hours.length) {
      const hoursCard = document.getElementById('prov-hours-card');
      const hoursEl = document.getElementById('prov-hours');
      if (hoursCard && hoursEl) {
        hoursCard.style.display = '';
        hoursEl.innerHTML = '';
        p.working_hours.forEach(h => {
          const row = UI.el('div', { className: 'prov-hours-row' });
          row.appendChild(UI.el('span', { className: 'hours-day', textContent: h.day || '' }));
          row.appendChild(UI.el('span', { className: 'hours-time', textContent: (h.open || '') + ' - ' + (h.close || '') }));
          hoursEl.appendChild(row);
        });
      }
    }

    // Highlights
    if (p.highlights && p.highlights.length) {
      const hlSection = document.getElementById('prov-highlights-section');
      const hlRow = document.getElementById('prov-highlights');
      if (hlSection && hlRow) {
        hlSection.style.display = '';
        p.highlights.forEach(hl => {
          const item = UI.el('div', { className: 'highlight-item' });
          if (hl.image) item.appendChild(UI.lazyImg(ApiClient.mediaUrl(hl.image), ''));
          if (hl.title) item.appendChild(UI.el('span', { textContent: hl.title }));
          hlRow.appendChild(item);
        });
      }
    }

    // Stats
    _setText('stat-rating', p.rating_avg ? parseFloat(p.rating_avg).toFixed(1) : '-');
    _setText('stat-followers', p.followers_count || 0);
    _setText('stat-likes', p.likes_count || 0);
    _setText('stat-completed', p.completed_orders_count || p.orders_count || 0);

    // Following state
    _isFollowing = !!p.is_following;
    _updateFollowBtn();

    // Page title
    document.title = (p.display_name || 'مقدم خدمة') + ' — نوافذ';
  }

  /* ---------- Follow / Unfollow ---------- */
  async function _toggleFollow() {
    if (!Auth.isLoggedIn()) { Auth.requireLogin(window.location.pathname); return; }
    const url = _isFollowing
      ? '/api/providers/' + _providerId + '/unfollow/'
      : '/api/providers/' + _providerId + '/follow/';
    const res = await ApiClient.request(url, { method: 'POST' });
    if (res.ok) {
      _isFollowing = !_isFollowing;
      _updateFollowBtn();
      // Update followers count
      const el = document.getElementById('stat-followers');
      if (el) {
        let c = parseInt(el.textContent) || 0;
        c += _isFollowing ? 1 : -1;
        el.textContent = Math.max(0, c);
      }
    }
  }

  function _updateFollowBtn() {
    const btn = document.getElementById('btn-follow');
    if (_isFollowing) {
      btn.className = 'btn btn-secondary';
      btn.textContent = 'إلغاء المتابعة';
    } else {
      btn.className = 'btn btn-primary';
      btn.textContent = 'متابعة';
    }
  }

  /* ---------- Services ---------- */
  async function _loadServices() {
    const container = document.getElementById('services-list');
    const res = await ApiClient.get('/api/providers/' + _providerId + '/services/');
    if (!res.ok) return;
    const list = Array.isArray(res.data) ? res.data : (res.data.results || []);
    container.innerHTML = '';
    if (!list.length) {
      container.innerHTML = '<div class="empty-hint"><div class="empty-icon">📋</div><p>لا توجد خدمات</p></div>';
      return;
    }
    const frag = document.createDocumentFragment();
    list.forEach(svc => {
      const card = UI.el('div', { className: 'service-card' });
      card.appendChild(UI.el('div', { className: 'service-name', textContent: svc.name || svc.title || '' }));
      if (svc.description) card.appendChild(UI.el('div', { className: 'service-desc', textContent: svc.description }));
      const footer = UI.el('div', { className: 'service-footer' });
      if (svc.price || svc.min_price) {
        const price = svc.price || svc.min_price;
        footer.appendChild(UI.el('span', { className: 'service-price', textContent: parseFloat(price).toLocaleString('ar-SA') + ' ر.س' }));
      }
      if (svc.delivery_days) {
        footer.appendChild(UI.el('span', { className: 'service-duration', textContent: svc.delivery_days + ' يوم' }));
      }
      card.appendChild(footer);
      frag.appendChild(card);
    });
    container.appendChild(frag);
  }

  /* ---------- Portfolio ---------- */
  async function _loadPortfolio() {
    const container = document.getElementById('portfolio-list');
    const res = await ApiClient.get('/api/providers/' + _providerId + '/portfolio/');
    if (!res.ok) return;
    const list = Array.isArray(res.data) ? res.data : (res.data.results || []);
    container.innerHTML = '';
    if (!list.length) {
      container.innerHTML = '<div class="empty-hint"><div class="empty-icon">🖼️</div><p>لا توجد أعمال</p></div>';
      return;
    }
    const grid = UI.el('div', { className: 'media-grid' });
    list.forEach(item => {
      const el = UI.el('div', { className: 'media-item' });
      const imgUrl = item.image || item.media_url || item.file;
      if (imgUrl) el.appendChild(UI.lazyImg(ApiClient.mediaUrl(imgUrl), ''));
      if (item.title || item.caption) {
        el.appendChild(UI.el('div', { className: 'media-caption', textContent: item.title || item.caption }));
      }
      grid.appendChild(el);
    });
    container.appendChild(grid);
  }

  /* ---------- Reviews ---------- */
  async function _loadReviews() {
    const container = document.getElementById('reviews-list');

    // Rating summary + reviews
    const [ratingRes, reviewsRes] = await Promise.all([
      ApiClient.get('/api/reviews/providers/' + _providerId + '/rating/'),
      ApiClient.get('/api/reviews/providers/' + _providerId + '/reviews/')
    ]);

    container.innerHTML = '';

    // Rating summary
    if (ratingRes.ok && ratingRes.data) {
      const r = ratingRes.data;
      const summary = UI.el('div', { className: 'rating-summary' });
      const bigNum = UI.el('div', { className: 'rating-big' });
      bigNum.appendChild(UI.text(r.average ? parseFloat(r.average).toFixed(1) : '-'));
      bigNum.appendChild(UI.icon('star', 20, '#FFC107'));
      summary.appendChild(bigNum);
      summary.appendChild(UI.el('div', { className: 'rating-count', textContent: (r.count || 0) + ' تقييم' }));
      container.appendChild(summary);
    }

    // Individual reviews
    let reviews = [];
    if (reviewsRes.ok && reviewsRes.data) {
      reviews = Array.isArray(reviewsRes.data) ? reviewsRes.data : (reviewsRes.data.results || []);
    }

    if (!reviews.length) {
      container.appendChild(UI.el('div', { className: 'empty-hint', innerHTML: '<div class="empty-icon">⭐</div><p>لا توجد تقييمات بعد</p>' }));
      return;
    }

    reviews.forEach(rev => {
      const card = UI.el('div', { className: 'review-card' });

      const header = UI.el('div', { className: 'review-header' });
      header.appendChild(UI.el('span', { className: 'review-author', textContent: rev.reviewer_name || rev.client_name || 'مستخدم' }));
      // Stars
      const stars = UI.el('span', { className: 'review-stars' });
      const rating = Math.round(rev.rating || 0);
      for (let i = 0; i < 5; i++) {
        stars.appendChild(UI.icon('star', 12, i < rating ? '#FFC107' : '#E0E0E0'));
      }
      header.appendChild(stars);
      card.appendChild(header);

      if (rev.comment || rev.text) {
        card.appendChild(UI.el('div', { className: 'review-text', textContent: rev.comment || rev.text }));
      }

      if (rev.created_at || rev.created) {
        const d = new Date(rev.created_at || rev.created);
        card.appendChild(UI.el('div', { className: 'review-date', textContent: d.toLocaleDateString('ar-SA', { year: 'numeric', month: 'short', day: 'numeric' }) }));
      }

      container.appendChild(card);
    });
  }

  function _addContactRow(container, icon, text) {
    const row = UI.el('div', { className: 'prov-contact-row' });
    row.appendChild(UI.icon(icon, 16, '#888'));
    row.appendChild(UI.el('span', { textContent: text }));
    container.appendChild(row);
  }

  function _setText(id, val) {
    const el = document.getElementById(id);
    if (el) el.textContent = val;
  }

  // Boot
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else { init(); }

  return {};
})();
