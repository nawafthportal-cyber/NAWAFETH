/* ===================================================================
   providerDetailPage.js — Provider public profile detail (redesigned)
   Mirrors the Flutter ProviderProfileScreen layout.
   =================================================================== */
'use strict';

const ProviderDetailPage = (() => {
  let _providerId = null;
  let _isFollowing = false;
  let _isBookmarked = false;
  let _activeTab = 'profile';
  let _providerData = null;
  let _providerPhone = '';
  let _spotlights = [];
  let _socialUrls = {
    instagram: '',
    x: '',
    snapchat: '',
  };

  function init() {
    const match = window.location.pathname.match(/\/provider\/(\d+)/);
    if (!match) {
      document.querySelector('.pd-page').textContent = '';
      const msg = UI.el('div', { className: 'pd-empty', style: { padding: '80px 20px' } });
      msg.appendChild(UI.el('div', { className: 'pd-empty-icon', textContent: '🔍' }));
      msg.appendChild(UI.el('p', { textContent: 'مقدم الخدمة غير موجود' }));
      document.querySelector('.pd-page').appendChild(msg);
      return;
    }
    _providerId = match[1];

    _bindTabs();
    _bindActions();
    _loadAll();
  }

  /* ── Tabs ── */
  function _bindTabs() {
    document.getElementById('pd-tabs').addEventListener('click', e => {
      const btn = e.target.closest('.pd-tab');
      if (!btn) return;
      document.querySelectorAll('.pd-tab').forEach(t => t.classList.remove('active'));
      btn.classList.add('active');
      _activeTab = btn.dataset.tab;
      document.querySelectorAll('.pd-panel').forEach(p => p.classList.remove('active'));
      const panel = document.getElementById('tab-' + _activeTab);
      if (panel) panel.classList.add('active');
    });
  }

  /* ── Action buttons ── */
  function _bindActions() {
    document.getElementById('btn-follow').addEventListener('click', _toggleFollow);

    const followersBtn = document.getElementById('btn-show-followers');
    if (followersBtn) {
      followersBtn.addEventListener('click', () => _openConnectionsSheet('followers'));
    }

    const followingBtn = document.getElementById('btn-show-following');
    if (followingBtn) {
      followingBtn.addEventListener('click', () => _openConnectionsSheet('following'));
    }

    // Message
    const msgBtn = document.getElementById('btn-message');
    if (msgBtn) msgBtn.addEventListener('click', () => {
      if (!Auth.isLoggedIn()) { window.location.href = '/login/?next=' + encodeURIComponent(window.location.pathname); return; }
      window.location.href = '/chats/?start=' + _providerId;
    });

    // Request service
    document.getElementById('btn-request').addEventListener('click', () => {
      window.location.href = '/service-request/?provider_id=' + encodeURIComponent(String(_providerId));
    });

    // Call
    const callBtn = document.getElementById('btn-call');
    if (callBtn) callBtn.addEventListener('click', () => {
      if (_providerPhone) window.open('tel:' + _formatPhoneE164(_providerPhone));
    });

    // WhatsApp (header + profile tab)
    ['btn-whatsapp', 'pd-btn-whatsapp'].forEach(id => {
      const el = document.getElementById(id);
      if (el) el.addEventListener('click', e => {
        e.preventDefault();
        if (!_providerPhone) return;
        const phone = _formatPhoneE164(_providerPhone).replace('+', '');
        const name = _providerData?.display_name || '';
        const msg = encodeURIComponent('السلام عليكم\nأتواصل معك بخصوص خدماتك في منصة نوافذ @' + name);
        window.open('https://wa.me/' + phone + '?text=' + msg, '_blank');
      });
    });

    // Profile tab quick actions
    const qCall = document.getElementById('pd-btn-call');
    if (qCall) qCall.addEventListener('click', e => {
      e.preventDefault();
      if (_providerPhone) window.open('tel:' + _formatPhoneE164(_providerPhone));
    });
    const qChat = document.getElementById('pd-btn-chat');
    if (qChat) qChat.addEventListener('click', e => {
      e.preventDefault();
      if (!Auth.isLoggedIn()) { window.location.href = '/login/?next=' + encodeURIComponent(window.location.pathname); return; }
      window.location.href = '/chats/?start=' + _providerId;
    });

    // Bookmark
    const bookmarkBtn = document.getElementById('btn-bookmark');
    if (bookmarkBtn) bookmarkBtn.addEventListener('click', () => {
      _isBookmarked = !_isBookmarked;
      bookmarkBtn.classList.toggle('bookmarked', _isBookmarked);
      const svg = bookmarkBtn.querySelector('svg');
      if (svg) svg.setAttribute('fill', _isBookmarked ? '#fff' : 'none');
    });

    // Share
    const shareBtn = document.getElementById('btn-share');
    if (shareBtn) shareBtn.addEventListener('click', async () => {
      const url = window.location.href;
      if (navigator.share) {
        try { await navigator.share({ title: document.title, url }); } catch {}
      } else {
        try { await navigator.clipboard.writeText(url); _showToast('تم نسخ الرابط'); } catch {}
      }
    });
  }

  /* ── Load all data ── */
  async function _loadAll() {
    const [provRes, statsRes] = await Promise.all([
      ApiClient.get('/api/providers/' + _providerId + '/'),
      ApiClient.get('/api/providers/' + _providerId + '/stats/')
    ]);

    if (provRes.ok && provRes.data) {
      _providerData = provRes.data;
      _renderProvider(provRes.data, statsRes.ok ? statsRes.data : null);
    }

    // Parallel: services, portfolio, reviews, spotlights
    _loadServices();
    _loadPortfolio();
    _loadReviews();
    _loadSpotlights();
  }

  /* ═══════════════════════════════════════════════
     RENDER PROVIDER PROFILE
     ═══════════════════════════════════════════════ */
  function _renderProvider(p, stats) {
    _providerPhone = p.phone || p.whatsapp || '';

    // ── Cover ──
    const coverEl = document.getElementById('pd-cover');
    if (p.cover_image) {
      const img = UI.lazyImg(ApiClient.mediaUrl(p.cover_image), 'غلاف');
      img.style.position = 'absolute';
      img.style.inset = '0';
      img.style.width = '100%';
      img.style.height = '100%';
      img.style.objectFit = 'cover';
      coverEl.insertBefore(img, coverEl.firstChild);
    }

    // ── Avatar ──
    const avatarEl = document.getElementById('pd-avatar');
    if (p.profile_image) {
      avatarEl.textContent = '';
      avatarEl.appendChild(UI.lazyImg(ApiClient.mediaUrl(p.profile_image), p.display_name || ''));
    } else {
      avatarEl.textContent = (p.display_name || '').charAt(0) || '؟';
    }

    // ── Badge ──
    const badge = document.getElementById('pd-verified-badge');
    if (p.is_verified_blue || p.is_verified_green) {
      badge.classList.remove('hidden');
      const color = p.is_verified_blue ? '#2196F3' : '#4CAF50';
      badge.querySelector('svg').setAttribute('fill', color);
    }

    // ── Name & handle ──
    _setText('pd-name', p.display_name || '');
    _setText('pd-handle', p.username ? ('@' + p.username) : '');

    // ── Category & city chips ──
    const catEl = document.getElementById('pd-category');
    const catName = p.category_name || p.main_category || '';
    if (catEl) {
      catEl.textContent = catName;
      if (!catName) catEl.style.display = 'none';
    }

    const cityEl = document.getElementById('pd-city');
    if (cityEl) {
      if (p.city) {
        cityEl.textContent = '📍 ' + p.city;
      } else {
        cityEl.style.display = 'none';
      }
    }

    // ── Stats ──
    const completed = stats?.completed_requests ?? p.completed_requests ?? p.completed_orders_count ?? 0;
    const followers = stats?.followers_count ?? p.followers_count ?? 0;
    const following = stats?.following_count ?? p.following_count ?? 0;
    const likes = stats?.likes_count ?? p.likes_count ?? 0;
    const rating = p.rating_avg ? parseFloat(p.rating_avg).toFixed(1) : '-';

    _setText('stat-completed', completed);
    _setText('stat-followers', followers);
    _setText('stat-likes', likes);
    _setText('stat-rating', rating);

    const followingBtn = document.getElementById('btn-show-following');
    if (followingBtn) {
      followingBtn.dataset.count = String(following || 0);
    }

    // ── Follow state ──
    _isFollowing = !!p.is_following;
    _updateFollowBtn();

    // ── Profile tab content ──
    _renderProfileTab(p);

    // ── Page title ──
    document.title = (p.display_name || 'مقدم خدمة') + ' — نوافذ';
  }

  /* ── Render profile tab details ── */
  function _renderProfileTab(p) {
    const unavailable = 'غير متوفر';
    const serviceRangeKm = _resolveServiceRangeKm(p);

    // Bio
    _setText('pd-bio', p.bio || p.description || p.about_details || 'لا يوجد وصف');

    // Categories
    _setText('pd-main-category', _displayOrUnavailable(p.category_name || p.main_category, unavailable));
    _setText('pd-sub-category', _displayOrUnavailable(p.subcategory_name || p.sub_category, unavailable));

    // About details
    _setText('pd-about-details', _displayOrUnavailable(p.about_details || p.bio, unavailable));

    // Qualifications
    const quals = p.qualifications || [];
    const qualsText = quals.map(q => typeof q === 'string' ? q : (q.title || q.name || '')).filter(Boolean).join('، ');
    _setText('pd-qualifications', _displayOrUnavailable(qualsText, unavailable));

    // Experience
    _setText('pd-experience', p.years_experience ? p.years_experience + ' سنوات' : unavailable);

    // Languages
    const langs = p.languages || [];
    const langsText = langs.map(l => typeof l === 'string' ? l : (l.name || '')).filter(Boolean).join('، ');
    _setText('pd-languages', _displayOrUnavailable(langsText, unavailable));

    _setText('pd-city-name', _displayOrUnavailable(p.city, unavailable));

    // Geo scope
    const city = p.city || '';
    if (serviceRangeKm > 0 && city) {
      _setText('pd-geo-scope', 'ضمن نطاق محدد: ' + serviceRangeKm + ' كم (' + city + ')');
    } else if (city) {
      _setText('pd-geo-scope', 'مدينتي: ' + city);
    } else if (serviceRangeKm > 0) {
      _setText('pd-geo-scope', 'ضمن نطاق محدد: ' + serviceRangeKm + ' كم');
    } else {
      _setText('pd-geo-scope', unavailable);
    }

    // ── Website ──
    const websiteRaw = String(p.website || '').trim();
    _setText('pd-website', websiteRaw || unavailable);
    const websiteBtn = document.getElementById('pd-website-open');
    if (websiteBtn) {
      websiteBtn.disabled = !websiteRaw;
      websiteBtn.classList.toggle('disabled', !websiteRaw);
      websiteBtn.onclick = () => {
        if (!websiteRaw) return;
        const url = websiteRaw.startsWith('http') ? websiteRaw : ('https://' + websiteRaw);
        window.open(url, '_blank', 'noopener');
      };
    }

    // ── Social accounts (fixed 3 rows like Flutter) ──
    _socialUrls.instagram = _findSocialUrl(p, 'instagram');
    _socialUrls.x = _findSocialUrl(p, 'x.com') || _findSocialUrl(p, 'twitter');
    _socialUrls.snapchat = _findSocialUrl(p, 'snapchat');

    _setSocialRow('instagram', 'pd-social-instagram', 'pd-social-open-instagram', unavailable);
    _setSocialRow('x', 'pd-social-x', 'pd-social-open-x', unavailable);
    _setSocialRow('snapchat', 'pd-social-snapchat', 'pd-social-open-snapchat', unavailable);

    // ── Map ──
    const lat = parseFloat(p.lat);
    const lng = parseFloat(p.lng);
    if (Number.isFinite(lat) && Number.isFinite(lng) && lat !== 0 && lng !== 0 && typeof L !== 'undefined') {
      const mapCard = document.getElementById('pd-map-wrap');
      const mapEl = document.getElementById('pd-map');
      if (mapCard && mapEl) {
        mapCard.classList.remove('hidden');
        setTimeout(() => {
          const map = L.map(mapEl, { scrollWheelZoom: false }).setView([lat, lng], 12);
          L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
            attribution: '&copy; OpenStreetMap'
          }).addTo(map);
          L.marker([lat, lng]).addTo(map);
          if (serviceRangeKm > 0) {
            L.circle([lat, lng], {
              radius: serviceRangeKm * 1000,
              color: '#673AB7', fillColor: '#673AB7',
              fillOpacity: 0.08, weight: 2
            }).addTo(map);
          }
        }, 300);
      }
    }
  }

  async function _openConnectionsSheet(kind) {
    const isFollowers = kind === 'followers';
    const endpoint = isFollowers
      ? '/api/providers/' + _providerId + '/followers/'
      : '/api/providers/' + _providerId + '/following/';
    const title = isFollowers ? 'متابعون' : 'يتابع';
    const countEl = isFollowers ? document.getElementById('stat-followers') : document.getElementById('btn-show-following');
    const count = countEl ? (parseInt(isFollowers ? countEl.textContent : countEl.dataset.count, 10) || 0) : 0;

    const res = await ApiClient.get(endpoint);
    const items = res.ok
      ? (Array.isArray(res.data) ? res.data : (res.data?.results || []))
      : [];

    const backdrop = UI.el('div', { className: 'pd-sheet-backdrop' });
    const sheet = UI.el('div', { className: 'pd-sheet' });
    const handle = UI.el('div', { className: 'pd-sheet-handle' });
    const header = UI.el('div', { className: 'pd-sheet-header' });
    const heading = UI.el('div', {
      className: 'pd-sheet-title',
      textContent: title + ' (' + count + ')',
    });
    const closeBtn = UI.el('button', {
      className: 'pd-sheet-close',
      type: 'button',
      textContent: '×',
    });
    closeBtn.setAttribute('aria-label', 'إغلاق');
    closeBtn.addEventListener('click', closeSheet);

    header.appendChild(heading);
    header.appendChild(closeBtn);
    sheet.appendChild(handle);
    sheet.appendChild(header);

    const body = UI.el('div', { className: 'pd-sheet-body' });

    if (!res.ok && !items.length) {
      body.appendChild(UI.el('div', {
        className: 'pd-sheet-empty',
        textContent: res.error || 'تعذر تحميل القائمة',
      }));
    } else if (!items.length) {
      body.appendChild(UI.el('div', {
        className: 'pd-sheet-empty',
        textContent: isFollowers ? 'لا يوجد متابعون بعد' : 'لا يوجد متابَعون بعد',
      }));
    } else {
      const list = UI.el('div', { className: 'pd-sheet-list' });
      items.forEach(item => {
        const name = String(item.display_name || item.name || item.username || 'مستخدم').trim() || 'مستخدم';
        const username = String(item.username || item.username_display || '').trim();
        const avatarUrl = ApiClient.mediaUrl(item.profile_image || item.avatar || '');

        const row = UI.el('div', { className: 'pd-sheet-item' });
        const avatar = UI.el('div', { className: 'pd-sheet-avatar' });
        if (avatarUrl) avatar.appendChild(UI.lazyImg(avatarUrl, name));
        else avatar.appendChild(UI.el('span', { textContent: name.charAt(0) }));
        row.appendChild(avatar);

        const meta = UI.el('div', { className: 'pd-sheet-meta' });
        meta.appendChild(UI.el('div', { className: 'pd-sheet-name', textContent: name }));
        if (username) {
          meta.appendChild(UI.el('div', { className: 'pd-sheet-handle-text', textContent: '@' + username }));
        }
        row.appendChild(meta);
        list.appendChild(row);
      });
      body.appendChild(list);
    }

    sheet.appendChild(body);
    backdrop.appendChild(sheet);
    document.body.appendChild(backdrop);
    requestAnimationFrame(() => backdrop.classList.add('open'));

    backdrop.addEventListener('click', e => {
      if (e.target === backdrop) closeSheet();
    });

    function closeSheet() {
      backdrop.classList.remove('open');
      setTimeout(() => backdrop.remove(), 180);
    }
  }

  /* ═══ Follow / Unfollow ═══ */
  async function _toggleFollow() {
    if (!Auth.isLoggedIn()) { window.location.href = '/login/?next=' + encodeURIComponent(window.location.pathname); return; }
    const url = _isFollowing
      ? '/api/providers/' + _providerId + '/unfollow/'
      : '/api/providers/' + _providerId + '/follow/';
    const btn = document.getElementById('btn-follow');
    btn.disabled = true;
    const res = await ApiClient.request(url, { method: 'POST' });
    btn.disabled = false;
    if (res.ok) {
      _isFollowing = !_isFollowing;
      _updateFollowBtn();
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
    if (!btn) return;
    if (_isFollowing) {
      btn.classList.add('following');
      btn.querySelector('span') ? null : null;
      // Replace inner content
      btn.textContent = '';
      const svg = _createSVG('<path d="M16 21v-2a4 4 0 00-4-4H5a4 4 0 00-4 4v2"/><circle cx="8.5" cy="7" r="4"/><line x1="23" y1="11" x2="17" y2="11"/>', 16);
      btn.appendChild(svg);
      btn.appendChild(document.createTextNode(' إلغاء المتابعة'));
    } else {
      btn.classList.remove('following');
      btn.textContent = '';
      const svg = _createSVG('<path d="M16 21v-2a4 4 0 00-4-4H5a4 4 0 00-4 4v2"/><circle cx="8.5" cy="7" r="4"/><line x1="20" y1="8" x2="20" y2="14"/><line x1="23" y1="11" x2="17" y2="11"/>', 16);
      btn.appendChild(svg);
      btn.appendChild(document.createTextNode(' متابعة'));
    }
  }

  /* ═══ Spotlights / Highlights ═══ */
  async function _loadSpotlights() {
    const res = await ApiClient.get('/api/providers/' + _providerId + '/spotlights/');
    if (!res.ok) return;
    const raw = Array.isArray(res.data) ? res.data : (res.data?.results || []);
    if (!raw.length) return;

    _spotlights = raw.map(item => {
      return {
        id: item.id,
        provider_id: item.provider_id || _safeInt(_providerId),
        provider_display_name: item.provider_display_name || _providerData?.display_name || '',
        provider_profile_image: item.provider_profile_image || _providerData?.profile_image || '',
        file_type: item.file_type || 'image',
        file_url: item.file_url || item.media_url || '',
        thumbnail_url: item.thumbnail_url || item.file_url || item.media_url || '',
        caption: item.caption || item.title || '',
        likes_count: _safeInt(item.likes_count),
        saves_count: _safeInt(item.saves_count),
        is_liked: !!item.is_liked,
        is_saved: !!item.is_saved,
      };
    }).filter(item => (item.file_url || item.thumbnail_url));

    if (!_spotlights.length) return;

    const section = document.getElementById('pd-highlights-section');
    const row = document.getElementById('pd-highlights');
    if (!section || !row) return;

    section.classList.remove('hidden');
    row.textContent = '';
    _spotlights.forEach((item, idx) => {
      const el = UI.el('div', { className: 'pd-highlight-item' });
      const thumb = UI.el('div', { className: 'pd-highlight-thumb' });
      const imgUrl = item.thumbnail_url || item.file_url;
      if (imgUrl) thumb.appendChild(UI.lazyImg(ApiClient.mediaUrl(imgUrl), ''));

      const stats = UI.el('div', { className: 'pd-highlight-stats' });
      const likes = UI.el('span', {
        className: 'pd-highlight-stat' + (item.is_liked ? ' active' : ''),
        textContent: '❤ ' + String(_safeInt(item.likes_count)),
      });
      const saves = UI.el('span', {
        className: 'pd-highlight-stat' + (item.is_saved ? ' active' : ''),
        textContent: '🔖 ' + String(_safeInt(item.saves_count)),
      });
      stats.appendChild(likes);
      stats.appendChild(saves);
      thumb.appendChild(stats);

      el.appendChild(thumb);

      const caption = (item.caption || '').toString().trim();
      el.appendChild(UI.el('div', { className: 'pd-highlight-label', textContent: caption || 'لمحة' }));

      el.addEventListener('click', () => {
        if (typeof SpotlightViewer !== 'undefined') {
          SpotlightViewer.open(_spotlights, idx);
        }
      });

      row.appendChild(el);
    });
  }

  /* ═══ Services ═══ */
  async function _loadServices() {
    const container = document.getElementById('pd-services-list');
    const emptyEl = document.getElementById('pd-services-empty');
    const res = await ApiClient.get('/api/providers/' + _providerId + '/services/');
    if (!res.ok) return;
    const list = Array.isArray(res.data) ? res.data : (res.data?.results || []);
    container.textContent = '';
    if (emptyEl) emptyEl.classList.add('hidden');

    if (!list.length) {
      if (emptyEl) emptyEl.classList.remove('hidden');
      return;
    }

    list.forEach((svc, idx) => {
      const title = String(svc.title || svc.name || '').trim() || 'خدمة بدون اسم';
      const description = String(svc.description || '').trim();
      const subcategory = (svc.subcategory && typeof svc.subcategory === 'object') ? svc.subcategory : null;
      const categoryLabel = String(
        (subcategory && subcategory.category_name) ||
        svc.category_name ||
        svc.main_category ||
        ''
      ).trim();
      const subCategoryLabel = String(
        (subcategory && subcategory.name) ||
        svc.subcategory_name ||
        svc.sub_category ||
        ''
      ).trim();

      const card = UI.el('div', { className: 'pd-service-list-card' });

      const head = UI.el('div', { className: 'pd-service-list-head' });
      head.appendChild(UI.el('span', { className: 'pd-service-index', textContent: String(idx + 1) }));
      head.appendChild(UI.el('h4', { className: 'pd-service-list-title', textContent: title }));
      card.appendChild(head);

      if (description) {
        card.appendChild(UI.el('p', { className: 'pd-service-list-desc', textContent: description }));
      }

      const chips = UI.el('div', { className: 'pd-service-list-chips' });
      chips.appendChild(UI.el('span', { className: 'pd-service-chip primary', textContent: _servicePriceLabel(svc) }));
      if (categoryLabel) {
        chips.appendChild(UI.el('span', { className: 'pd-service-chip', textContent: categoryLabel }));
      }
      if (subCategoryLabel) {
        chips.appendChild(UI.el('span', { className: 'pd-service-chip', textContent: subCategoryLabel }));
      }
      card.appendChild(chips);

      const requestBtn = UI.el('button', {
        className: 'pd-service-list-request',
        type: 'button',
        textContent: 'اطلب الخدمة',
      });
      requestBtn.addEventListener('click', () => {
        const params = new URLSearchParams();
        params.set('provider_id', String(_providerId));
        if (svc.id) params.set('service_id', String(svc.id));
        window.location.href = '/service-request/?' + params.toString();
      });
      card.appendChild(requestBtn);

      container.appendChild(card);
    });
  }

  function _servicePriceLabel(service) {
    const from = _asNumber(service.price_from);
    const to = _asNumber(service.price_to);
    const single = _asNumber(service.price || service.min_price);
    const unit = String(service.price_unit || '').trim();
    const suffix = unit ? (' / ' + unit) : '';

    if (Number.isFinite(from) && Number.isFinite(to)) {
      if (Math.abs(from - to) < 0.001) {
        return 'السعر: ' + from.toLocaleString('ar-SA') + suffix;
      }
      return 'السعر: ' + from.toLocaleString('ar-SA') + ' - ' + to.toLocaleString('ar-SA') + suffix;
    }
    if (Number.isFinite(from)) return 'السعر: ' + from.toLocaleString('ar-SA') + suffix;
    if (Number.isFinite(single)) return 'السعر: ' + single.toLocaleString('ar-SA') + suffix;
    return 'السعر: حسب الاتفاق';
  }

  function _asNumber(value) {
    if (value === null || value === undefined || value === '') return NaN;
    const n = Number(value);
    return Number.isFinite(n) ? n : NaN;
  }

  /* ═══ Portfolio ═══ */
  async function _loadPortfolio() {
    const container = document.getElementById('pd-portfolio-sections');
    const emptyEl = document.getElementById('pd-portfolio-empty');
    const res = await ApiClient.get('/api/providers/' + _providerId + '/portfolio/');
    if (!res.ok) return;
    const list = Array.isArray(res.data) ? res.data : (res.data?.results || []);
    container.textContent = '';

    if (!list.length) {
      if (emptyEl) emptyEl.classList.remove('hidden');
      return;
    }
    if (emptyEl) emptyEl.classList.add('hidden');

    const grouped = new Map();
    list.forEach(item => {
      const fileType = String(item.file_type || 'image').toLowerCase();
      const fileUrl = String(item.file_url || item.image || item.media_url || item.file || '').trim();
      const thumbUrl = String(item.thumbnail_url || '').trim();
      const media = fileUrl || thumbUrl;
      if (!media) return;

      const rawCaption = String(item.caption || item.title || '').trim();
      const sectionTitle = _extractPortfolioSectionTitle(rawCaption);
      const description = _extractPortfolioItemDescription(rawCaption, sectionTitle);

      if (!grouped.has(sectionTitle)) grouped.set(sectionTitle, []);
      grouped.get(sectionTitle).push({
        id: _safeInt(item.id),
        type: fileType.startsWith('video') ? 'video' : 'image',
        media: media,
        thumbnail: thumbUrl,
        desc: description,
        likes_count: _safeInt(item.likes_count),
        saves_count: _safeInt(item.saves_count),
        is_liked: !!item.is_liked,
        is_saved: !!item.is_saved,
      });
    });

    const sections = _resolvePortfolioSections(grouped);
    sections.forEach(({ sectionTitle, sectionDesc, items }) => {
      const section = UI.el('section', { className: 'pd-portfolio-section' });
      const header = UI.el('div', { className: 'pd-portfolio-section-head' });
      header.appendChild(UI.el('h4', { className: 'pd-portfolio-section-title', textContent: sectionTitle }));
      header.appendChild(UI.el('span', { className: 'pd-portfolio-section-count', textContent: String(items.length) }));
      section.appendChild(header);

      if (sectionDesc) {
        section.appendChild(UI.el('p', { className: 'pd-portfolio-section-desc', textContent: sectionDesc }));
      }

      if (!items.length) {
        const emptyCard = UI.el('div', { className: 'pd-empty-section-card' });
        emptyCard.appendChild(UI.el('p', { className: 'pd-empty-title', textContent: 'لا توجد عناصر في هذا القسم حالياً' }));
        emptyCard.appendChild(UI.el('p', { className: 'pd-empty-subtitle', textContent: 'سيظهر المحتوى هنا عند إضافته من ملف مقدم الخدمة.' }));
        section.appendChild(emptyCard);
        container.appendChild(section);
        return;
      }

      const grid = UI.el('div', { className: 'pd-portfolio-grid' });
      items.forEach(item => {
        const el = UI.el('div', { className: 'pd-portfolio-item' });
        const displayUrl = (item.type === 'video' && item.thumbnail) ? item.thumbnail : item.media;
        el.appendChild(UI.lazyImg(ApiClient.mediaUrl(displayUrl), item.desc || sectionTitle));

        if (item.type === 'video') {
          const badge = UI.el('div', { className: 'pd-portfolio-video-badge' });
          badge.appendChild(_createSVG('<polygon points="5 3 19 12 5 21 5 3" fill="#fff"/>', 14));
          el.appendChild(badge);
        }

        if (item.desc && item.desc !== 'بدون وصف') {
          el.appendChild(UI.el('div', { className: 'pd-portfolio-overlay', textContent: item.desc }));
        }

        const stats = UI.el('div', { className: 'pd-portfolio-item-stats' });
        const likesStat = UI.el('div', { className: 'pd-portfolio-item-stat' });
        if (item.is_liked) likesStat.classList.add('active');
        likesStat.appendChild(_createSVG('<path d="M20.84 4.61a5.5 5.5 0 00-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 00-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 000-7.78z"/>', 12));
        likesStat.appendChild(UI.el('span', { textContent: String(_safeInt(item.likes_count)) }));
        stats.appendChild(likesStat);

        const savesStat = UI.el('div', { className: 'pd-portfolio-item-stat' });
        if (item.is_saved) savesStat.classList.add('active');
        savesStat.appendChild(_createSVG('<path d="M19 21l-7-5-7 5V5a2 2 0 012-2h10a2 2 0 012 2z"/>', 12));
        savesStat.appendChild(UI.el('span', { textContent: String(_safeInt(item.saves_count)) }));
        stats.appendChild(savesStat);

        el.appendChild(stats);
        grid.appendChild(el);
      });

      section.appendChild(grid);
      container.appendChild(section);
    });

    if (!container.children.length && emptyEl) {
      emptyEl.classList.remove('hidden');
    }
  }

  /* ═══ Reviews ═══ */
  async function _loadReviews() {
    const summaryEl = document.getElementById('pd-rating-summary');
    const listEl = document.getElementById('pd-reviews-list');
    const emptyEl = document.getElementById('pd-reviews-empty');

    const [ratingRes, reviewsRes] = await Promise.all([
      ApiClient.get('/api/reviews/providers/' + _providerId + '/rating/'),
      ApiClient.get('/api/reviews/providers/' + _providerId + '/reviews/')
    ]);

    // Rating summary
    if (ratingRes.ok && ratingRes.data && summaryEl) {
      const r = ratingRes.data;
      summaryEl.textContent = '';
      const bigDiv = UI.el('div', { className: 'pd-rating-big' });
      bigDiv.appendChild(UI.text(r.average ? parseFloat(r.average).toFixed(1) : '-'));
      bigDiv.appendChild(UI.icon('star', 24, '#FFC107'));
      summaryEl.appendChild(bigDiv);
      summaryEl.appendChild(UI.el('div', { className: 'pd-rating-count', textContent: (r.count || 0) + ' تقييم' }));

      // Rating bars
      if (r.distribution) {
        const bars = UI.el('div', { className: 'pd-rating-bars' });
        for (let i = 5; i >= 1; i--) {
          const count = r.distribution[i] || r.distribution[String(i)] || 0;
          const total = r.count || 1;
          const pct = Math.round((count / total) * 100);
          const row = UI.el('div', { className: 'pd-rating-bar-row' });
          row.appendChild(UI.el('span', { className: 'pd-rating-bar-label', textContent: i }));
          row.appendChild(UI.icon('star', 12, '#FFC107'));
          const bar = UI.el('div', { className: 'pd-rating-bar' });
          const fill = UI.el('div', { className: 'pd-rating-bar-fill' });
          fill.style.width = pct + '%';
          bar.appendChild(fill);
          row.appendChild(bar);
          bars.appendChild(row);
        }
        summaryEl.appendChild(bars);
      }
    }

    // Reviews list
    let reviews = [];
    if (reviewsRes.ok && reviewsRes.data) {
      reviews = Array.isArray(reviewsRes.data) ? reviewsRes.data : (reviewsRes.data.results || []);
    }

    if (listEl) listEl.textContent = '';

    if (!reviews.length) {
      if (emptyEl) emptyEl.classList.remove('hidden');
      return;
    }

    reviews.forEach(rev => {
      const card = UI.el('div', { className: 'pd-review-card' });

      const header = UI.el('div', { className: 'pd-review-header' });
      header.appendChild(UI.el('span', { className: 'pd-review-author', textContent: rev.reviewer_name || rev.client_name || 'مستخدم' }));
      const stars = UI.el('span', { className: 'pd-review-stars' });
      const rating = Math.round(rev.rating || 0);
      for (let i = 0; i < 5; i++) {
        stars.appendChild(UI.icon('star', 14, i < rating ? '#FFC107' : '#E0E0E0'));
      }
      header.appendChild(stars);
      card.appendChild(header);

      if (rev.comment || rev.text) {
        card.appendChild(UI.el('div', { className: 'pd-review-text', textContent: rev.comment || rev.text }));
      }
      if (rev.created_at || rev.created) {
        const d = new Date(rev.created_at || rev.created);
        card.appendChild(UI.el('div', { className: 'pd-review-date', textContent: d.toLocaleDateString('ar-SA', { year: 'numeric', month: 'short', day: 'numeric' }) }));
      }
      if (listEl) listEl.appendChild(card);
    });
  }

  /* ═══ Helpers ═══ */

  function _safeInt(value) {
    const n = parseInt(value, 10);
    return Number.isFinite(n) ? n : 0;
  }

  function _setText(id, val) {
    const el = document.getElementById(id);
    if (el) el.textContent = val;
  }

  function _addContactRow(container, iconHtml, text, href) {
    const row = UI.el(href ? 'a' : 'div', { className: 'pd-contact-row' });
    if (href) { row.href = href.startsWith('http') ? href : ('https://' + href); row.target = '_blank'; row.rel = 'noopener'; }
    const iconWrap = UI.el('span', {});
    iconWrap.innerHTML = iconHtml; // safe: from our own _svgIcon
    row.appendChild(iconWrap);
    row.appendChild(UI.el('span', { textContent: text }));
    container.appendChild(row);
  }

  function _addSocialRow(container, iconHtml, label, url) {
    const row = UI.el('div', { className: 'pd-social-row' });
    const iconWrap = UI.el('div', { className: 'pd-social-icon' });
    iconWrap.innerHTML = iconHtml;
    row.appendChild(iconWrap);

    const info = UI.el('div', { className: 'pd-social-info' });
    info.appendChild(UI.el('div', { className: 'pd-social-label', textContent: label }));
    const handle = _extractHandle(url);
    info.appendChild(UI.el('div', { className: 'pd-social-value', textContent: handle || url }));
    row.appendChild(info);

    const link = UI.el('a', { className: 'pd-social-link', href: url.startsWith('http') ? url : ('https://' + url), target: '_blank', rel: 'noopener' });
    link.innerHTML = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 13v6a2 2 0 01-2 2H5a2 2 0 01-2-2V8a2 2 0 012-2h6"/><polyline points="15 3 21 3 21 9"/><line x1="10" y1="14" x2="21" y2="3"/></svg>';
    row.appendChild(link);
    container.appendChild(row);
  }

  function _extractHandle(url) {
    try {
      const uri = new URL(url.startsWith('http') ? url : ('https://' + url));
      const parts = uri.pathname.split('/').filter(Boolean);
      return parts.length ? '@' + parts[parts.length - 1] : '';
    } catch { return ''; }
  }

  function _displayOrUnavailable(value, unavailableText) {
    const text = String(value || '').trim();
    return text || unavailableText;
  }

  function _setSocialRow(kind, valueId, buttonId, unavailableText) {
    const url = String(_socialUrls[kind] || '').trim();
    const valueEl = document.getElementById(valueId);
    if (valueEl) {
      valueEl.textContent = url ? (_extractHandle(url) || url) : unavailableText;
    }
    const button = document.getElementById(buttonId);
    if (!button) return;
    button.disabled = !url;
    button.classList.toggle('disabled', !url);
    button.onclick = () => {
      if (!url) return;
      const href = url.startsWith('http') ? url : ('https://' + url);
      window.open(href, '_blank', 'noopener');
    };
  }

  function _findSocialUrl(provider, keyword) {
    const socialLinks = Array.isArray(provider.social_links) ? provider.social_links : [];
    const needle = String(keyword || '').trim().toLowerCase();
    if (!needle) return '';

    for (const item of socialLinks) {
      const url = (typeof item === 'string' ? item : (item?.url || '')).toString().trim();
      if (!url) continue;
      if (url.toLowerCase().includes(needle)) return url;
    }
    return '';
  }

  function _extractPortfolioSectionTitle(caption) {
    const text = String(caption || '').trim();
    if (!text) return 'أعمالي';
    const separators = [' - ', ' — ', ' – ', ' | ', '|'];
    for (const separator of separators) {
      const idx = text.indexOf(separator);
      if (idx > 0) return text.slice(0, idx).trim() || 'أعمالي';
    }
    return 'أعمالي';
  }

  function _extractPortfolioItemDescription(caption, sectionTitle) {
    const text = String(caption || '').trim();
    if (!text) return 'بدون وصف';
    const section = String(sectionTitle || '').trim();
    if (!section || section === 'أعمالي') return text;

    const separators = [' - ', ' — ', ' – ', ' | ', '|'];
    for (const separator of separators) {
      const prefix = section + separator;
      if (text.startsWith(prefix)) {
        const rest = text.slice(prefix.length).trim();
        return rest || 'بدون وصف';
      }
    }
    return text;
  }

  function _resolveServiceRangeKm(provider) {
    const radiusRaw = Number(provider.coverage_radius_km);
    if (Number.isFinite(radiusRaw) && radiusRaw > 0) {
      return Math.round(radiusRaw);
    }
    return 5;
  }

  function _resolvePortfolioSections(grouped) {
    const rawSections = (_providerData && (_providerData.content_sections || _providerData.contentSections)) || [];
    const definedSections = Array.isArray(rawSections)
      ? rawSections.filter(section => section && typeof section === 'object')
      : [];

    if (definedSections.length) {
      return definedSections.map(section => {
        const title = String(section.section_title || section.title || section.name || 'أعمالي').trim() || 'أعمالي';
        const desc = String(section.section_desc || section.description || '').trim();
        const items = grouped.get(title) || [];
        return { sectionTitle: title, sectionDesc: desc, items };
      });
    }

    const results = [];
    grouped.forEach((items, title) => {
      const firstDesc = items.find(item => item.desc && item.desc !== 'بدون وصف');
      results.push({
        sectionTitle: title,
        sectionDesc: firstDesc ? firstDesc.desc : '',
        items,
      });
    });
    return results;
  }

  function _detectPlatform(url) {
    const u = url.toLowerCase();
    if (u.includes('instagram')) return { label: 'انستقرام', icon: _svgIcon('instagram') };
    if (u.includes('x.com') || u.includes('twitter')) return { label: 'X (تويتر)', icon: _svgIcon('x') };
    if (u.includes('snapchat')) return { label: 'سناب شات', icon: _svgIcon('snapchat') };
    if (u.includes('tiktok')) return { label: 'تيك توك', icon: _svgIcon('web') };
    if (u.includes('facebook')) return { label: 'فيسبوك', icon: _svgIcon('web') };
    if (u.includes('youtube')) return { label: 'يوتيوب', icon: _svgIcon('web') };
    if (u.includes('linkedin')) return { label: 'لينكد إن', icon: _svgIcon('web') };
    return { label: 'رابط', icon: _svgIcon('web') };
  }

  function _svgIcon(name) {
    const icons = {
      location: '<svg width="16" height="16" viewBox="0 0 24 24" fill="#673AB7"><path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5z"/></svg>',
      phone: '<svg width="16" height="16" viewBox="0 0 24 24" fill="#673AB7"><path d="M6.62 10.79c1.44 2.83 3.76 5.14 6.59 6.59l2.2-2.2c.27-.27.67-.36 1.02-.24 1.12.37 2.32.57 3.57.57.55 0 1 .45 1 1V20c0 .55-.45 1-1 1-9.39 0-17-7.61-17-17 0-.55.45-1 1-1h3.5c.55 0 1 .45 1 1 0 1.25.2 2.45.57 3.57.11.35.03.74-.25 1.02l-2.2 2.2z"/></svg>',
      whatsapp: '<svg width="16" height="16" viewBox="0 0 24 24" fill="#25D366"><path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347z"/></svg>',
      web: '<svg width="16" height="16" viewBox="0 0 24 24" fill="#673AB7"><path d="M11.99 2C6.47 2 2 6.48 2 12s4.47 10 9.99 10C17.52 22 22 17.52 22 12S17.52 2 11.99 2zm6.93 6h-2.95a15.65 15.65 0 00-1.38-3.56A8.03 8.03 0 0118.92 8zM12 4.04c.83 1.2 1.48 2.53 1.91 3.96h-3.82c.43-1.43 1.08-2.76 1.91-3.96zM4.26 14C4.1 13.36 4 12.69 4 12s.1-1.36.26-2h3.38c-.08.66-.14 1.32-.14 2 0 .68.06 1.34.14 2H4.26zm.82 2h2.95c.32 1.25.78 2.45 1.38 3.56A7.987 7.987 0 015.08 16zm2.95-8H5.08a7.987 7.987 0 014.33-3.56A15.65 15.65 0 008.03 8zM12 19.96c-.83-1.2-1.48-2.53-1.91-3.96h3.82c-.43 1.43-1.08 2.76-1.91 3.96zM14.34 14H9.66c-.09-.66-.16-1.32-.16-2 0-.68.07-1.35.16-2h4.68c.09.65.16 1.32.16 2 0 .68-.07 1.34-.16 2zm.25 5.56c.6-1.11 1.06-2.31 1.38-3.56h2.95a8.03 8.03 0 01-4.33 3.56zM16.36 14c.08-.66.14-1.32.14-2 0-.68-.06-1.34-.14-2h3.38c.16.64.26 1.31.26 2s-.1 1.36-.26 2h-3.38z"/></svg>',
      instagram: '<svg width="16" height="16" viewBox="0 0 24 24" fill="#E1306C"><rect x="2" y="2" width="20" height="20" rx="5" fill="none" stroke="#E1306C" stroke-width="2"/><circle cx="12" cy="12" r="5" fill="none" stroke="#E1306C" stroke-width="2"/><circle cx="17.5" cy="6.5" r="1.5" fill="#E1306C"/></svg>',
      x: '<svg width="16" height="16" viewBox="0 0 24 24" fill="#000"><path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z"/></svg>',
      snapchat: '<svg width="16" height="16" viewBox="0 0 24 24" fill="#FFFC00"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2z"/></svg>',
    };
    return icons[name] || icons.web;
  }

  function _createSVG(paths, size) {
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('width', size || 16);
    svg.setAttribute('height', size || 16);
    svg.setAttribute('viewBox', '0 0 24 24');
    svg.setAttribute('fill', 'none');
    svg.setAttribute('stroke', 'currentColor');
    svg.setAttribute('stroke-width', '2');
    svg.innerHTML = paths;
    return svg;
  }

  function _formatPhoneE164(phone) {
    const cleaned = phone.replace(/\s+/g, '');
    if (cleaned.startsWith('+')) return cleaned;
    if (cleaned.startsWith('05') && cleaned.length === 10) return '+966' + cleaned.substring(1);
    if (cleaned.startsWith('5') && cleaned.length === 9) return '+966' + cleaned;
    return cleaned;
  }

  function _showToast(msg) {
    const toast = UI.el('div', {
      textContent: msg,
      style: {
        position: 'fixed', bottom: '24px', left: '50%', transform: 'translateX(-50%)',
        background: '#333', color: '#fff', padding: '10px 24px',
        borderRadius: '12px', fontSize: '13px', fontWeight: '600',
        zIndex: '9999', fontFamily: 'Cairo, sans-serif',
        boxShadow: '0 4px 20px rgba(0,0,0,0.2)'
      }
    });
    document.body.appendChild(toast);
    setTimeout(() => toast.remove(), 2500);
  }

  // Boot
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else { init(); }

  return {};
})();
