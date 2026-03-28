/* ===================================================================
   providerDashboardPage.js — Provider Dashboard (لوحة تحكم مقدم الخدمة)
   1:1 parity with Flutter provider_home_screen.dart
   =================================================================== */
'use strict';

const ProviderDashboardPage = (() => {
  let _profile = null;
  let _providerProfile = null;
  let _providerStats = null;
  let _favoritesCount = 0;

  function _extractList(payload) {
    if (Array.isArray(payload)) return payload;
    if (payload && Array.isArray(payload.results)) return payload.results;
    return [];
  }

  function _statusCode(status) {
    return String(status || '').trim().toLowerCase();
  }

  function _subscriptionRank(sub) {
    switch (_statusCode(sub && sub.status)) {
      case 'active':
        return 0;
      case 'grace':
        return 1;
      case 'pending_payment':
        return 2;
      default:
        return 9;
    }
  }

  function _pickPreferredSubscription(subs) {
    if (!Array.isArray(subs) || !subs.length) return null;
    let best = subs[0];
    let bestRank = _subscriptionRank(best);
    for (const sub of subs) {
      const rank = _subscriptionRank(sub);
      if (rank < bestRank) {
        best = sub;
        bestRank = rank;
        if (rank === 0) break;
      }
    }
    return best;
  }

  function _planTitle(sub) {
    return (
      sub?.plan?.title ||
      sub?.plan?.name ||
      sub?.plan_title ||
      sub?.plan_name ||
      'الباقة'
    );
  }

  function _statusLabel(status) {
    switch (_statusCode(status)) {
      case 'active':
        return 'نشط';
      case 'grace':
        return 'فترة سماح';
      case 'pending_payment':
        return 'بانتظار الدفع';
      case 'expired':
        return 'منتهي';
      case 'cancelled':
        return 'ملغي';
      default:
        return 'غير معروف';
    }
  }

  function init() {
    if (!Auth.isLoggedIn()) {
      document.getElementById('auth-gate').style.display = '';
      return;
    }
    document.getElementById('dashboard-content').style.display = '';
    _loadData();
    _bindUploads();
    _bindModeToggle();
    _bindQrAction();
  }

  async function _loadData() {
    // Parallel fetch
    const [profRes, provRes, subRes, urgentRes, competitiveRes, assignedRes, spotsRes] =
      await Promise.allSettled([
        ApiClient.get('/api/accounts/me/'),
        ApiClient.get('/api/providers/me/profile/'),
        ApiClient.get('/api/subscriptions/my/'),
        ApiClient.get('/api/marketplace/provider/urgent/available/'),
        ApiClient.get('/api/marketplace/provider/competitive/available/'),
        ApiClient.get('/api/marketplace/provider/requests/?status_group=new'),
        ApiClient.get('/api/providers/me/spotlights/'),
      ]);

    if (profRes.status === 'fulfilled' && profRes.value.ok) {
      _profile = profRes.value.data;
    }
    if (provRes.status === 'fulfilled' && provRes.value.ok) {
      _providerProfile = provRes.value.data;
    }

    if (!_providerProfile || !_providerProfile.id) {
      sessionStorage.setItem('nw_account_mode', 'client');
      window.location.href = '/profile/';
      return;
    }

    if (_providerProfile && _providerProfile.id) {
      const statsRes = await ApiClient.get('/api/providers/' + _providerProfile.id + '/stats/?mode=provider');
      if (statsRes.ok && statsRes.data) {
        _providerStats = statsRes.data;
      }
    }

    _favoritesCount = _resolveFavoritesCount();

    _renderHeader();
    _renderStats();
    _renderSubscription(subRes);
    _renderCompletion();
    _renderKPIs(urgentRes, competitiveRes, assignedRes);
    _renderSpotlights(spotsRes);
  }

  function _renderHeader() {
    const p = _providerProfile || {};
    const u = _profile || {};
    const isVerifiedBlue = p.is_verified_blue === true;
    const isVerifiedGreen = p.is_verified_green === true;
    const excellenceBadges = _normalizeExcellenceBadges(p.excellence_badges);
    const hasExcellenceBadges = excellenceBadges.length > 0;

    // Cover
    const coverEl = document.getElementById('pd-cover');
    if (p.cover_image) {
      coverEl.style.backgroundImage = `url('${ApiClient.mediaUrl(p.cover_image)}')`;
    } else {
      coverEl.style.backgroundImage = '';
    }

    // Avatar
    const avatarEl = document.getElementById('pd-avatar');
    const img = p.profile_image || u.profile_image;
    avatarEl.textContent = '';
    if (img) {
      avatarEl.style.backgroundImage = `url('${ApiClient.mediaUrl(img)}')`;
    } else {
      avatarEl.style.backgroundImage = '';
      avatarEl.textContent = (p.display_name || u.first_name || '؟')[0];
    }

    // Name
    document.getElementById('pd-name').textContent = p.display_name || `${u.first_name || ''} ${u.last_name || ''}`.trim() || 'مقدم خدمة';
    document.getElementById('pd-handle').textContent = u.username ? `@${u.username}` : '';

    // Avatar badge overlays
    const blueBadge = document.getElementById('pd-avatar-badge-blue');
    const greenBadge = document.getElementById('pd-avatar-badge-green');
    const excellenceBadge = document.getElementById('pd-avatar-badge-excellence');
    if (blueBadge) blueBadge.classList.toggle('hidden', !isVerifiedBlue);
    if (excellenceBadge) excellenceBadge.classList.toggle('hidden', !hasExcellenceBadges);
    if (greenBadge) greenBadge.classList.toggle('hidden', hasExcellenceBadges || !isVerifiedGreen);

    // Text badge under name
    const verifiedRow = document.getElementById('pd-verified');
    const verifiedLabel = verifiedRow ? verifiedRow.querySelector('span') : null;
    const labels = [];
    if (isVerifiedBlue) labels.push('توثيق أزرق');
    if (isVerifiedGreen) labels.push('توثيق أخضر');
    if (hasExcellenceBadges) labels.push('شارة تميز');
    if (verifiedRow) {
      verifiedRow.style.display = labels.length ? '' : 'none';
    }
    if (verifiedLabel) {
      verifiedLabel.textContent = labels.join(' • ');
    }
  }

  function _renderStats() {
    const p = _providerProfile || {};
    const stats = _providerStats || {};
    const followers = stats.followers_count ?? p.followers_count ?? _profile?.provider_followers_count ?? 0;
    const following = stats.following_count ?? p.following_count ?? _profile?.following_count ?? 0;
    const likes = stats.media_likes_count ?? stats.likes_count ?? p.likes_count ?? _profile?.provider_likes_received_count ?? _profile?.likes_count ?? 0;
    const clients = p.total_clients ?? stats.completed_requests ?? p.completed_requests ?? 0;
    const favorites = stats.media_saves_count ?? _favoritesCount;

    _setText('stat-followers', '.pd-stat-val', followers);
    _setText('stat-following', '.pd-stat-val', following);
    _setText('stat-likes', '.pd-stat-val', likes);
    _setText('stat-clients', '.pd-stat-val', clients);
    _setText('stat-favorites', '.pd-stat-val', favorites);
  }

  function _resolveFavoritesCount() {
    const fromStats = _providerStats?.media_saves_count;
    if (Number.isFinite(Number(fromStats))) return Number(fromStats);
    return 0;
  }

  function _normalizeExcellenceBadges(value) {
    if (window.UI && typeof window.UI.normalizeExcellenceBadges === 'function') {
      return window.UI.normalizeExcellenceBadges(value);
    }
    if (!Array.isArray(value)) return [];
    return value.filter((item) => item && typeof item === 'object');
  }

  function _renderSubscription(subRes) {
    const card = document.getElementById('subscription-card');
    if (subRes.status === 'fulfilled' && subRes.value.ok && subRes.value.data) {
      const subs = _extractList(subRes.value.data);
      const selected = _pickPreferredSubscription(subs);
      if (selected) {
        card.style.display = '';
        document.getElementById('plan-name').textContent = _planTitle(selected);
        const metaParts = [`الحالة: ${_statusLabel(selected.status)}`];
        const endRaw = selected.end_at || selected.end_date;
        if (endRaw) {
          const endDate = new Date(endRaw);
          if (!Number.isNaN(endDate.getTime())) {
            metaParts.push(`ينتهي: ${endDate.toLocaleDateString('ar-SA')}`);
          }
        }
        document.getElementById('plan-expiry').textContent = metaParts.join(' • ');
      }
    }
  }

  function _hasText(value) {
    return typeof value === 'string' && value.trim().length > 0;
  }

  function _hasNonEmptyList(value) {
    if (!Array.isArray(value) || !value.length) return false;
    return value.some((item) => {
      if (item == null) return false;
      if (typeof item === 'string') return item.trim().length > 0;
      if (Array.isArray(item)) return item.length > 0;
      if (typeof item === 'object') return Object.keys(item).length > 0;
      return true;
    });
  }

  function _mobileProfileCompletionPercent(profile) {
    const p = profile || {};
    const checks = [
      _hasText(p.display_name) && _hasText(p.bio), // service details
      _hasText(p.about_details) || _hasNonEmptyList(p.qualifications) || _hasNonEmptyList(p.experiences), // additional
      _hasText(p.whatsapp) || _hasText(p.website) || _hasNonEmptyList(p.social_links), // contact
      _hasNonEmptyList(p.languages) && Number(p.coverage_radius_km || 0) > 0, // language/location
      _hasText(p.profile_image) || _hasText(p.cover_image) || _hasNonEmptyList(p.content_sections), // content
      _hasText(p.seo_keywords) || _hasText(p.seo_meta_description) || _hasText(p.seo_slug), // seo
    ];

    const doneOptional = checks.filter(Boolean).length;
    const completion = 0.30 + (doneOptional * (0.70 / 6));
    return Math.max(0, Math.min(100, Math.round(completion * 100)));
  }

  function _renderCompletion() {
    const p = _providerProfile || {};
    const raw = Number(p.profile_completion);
    const pct = Number.isFinite(raw)
      ? (raw <= 1 ? Math.round(raw * 100) : Math.round(raw))
      : _mobileProfileCompletionPercent(p);
    document.getElementById('completion-pct').textContent = `${pct}%`;
    document.getElementById('completion-bar').style.width = `${pct}%`;
    if (pct >= 100) {
      document.getElementById('completion-card').style.display = 'none';
    }
  }

  function _renderKPIs(urgentRes, competitiveRes, assignedRes) {
    const urgent = _countFromSettled(urgentRes);
    const competitive = _countFromSettled(competitiveRes);
    const assigned = _countFromSettled(assignedRes);

    const urgentEl = document.getElementById('kpi-urgent');
    if (urgentEl) urgentEl.textContent = urgent;

    const competitiveEl = document.getElementById('kpi-competitive');
    if (competitiveEl) competitiveEl.textContent = competitive;

    const assignedEl = document.getElementById('kpi-assigned');
    if (assignedEl) assignedEl.textContent = assigned;
  }

  function _countFromSettled(settledResult) {
    if (!settledResult || settledResult.status !== 'fulfilled' || !settledResult.value.ok) return 0;
    const data = settledResult.value.data;
    if (!data) return 0;
    if (Number.isFinite(Number(data.count))) return Number(data.count);
    if (Array.isArray(data)) return data.length;
    if (Array.isArray(data.results)) return data.results.length;
    return 0;
  }

  function _renderSpotlights(spotsRes) {
    const row = document.getElementById('reels-row');
    if (spotsRes.status !== 'fulfilled' || !spotsRes.value.ok) return;
    const spots = spotsRes.value.data?.results || spotsRes.value.data || [];
    spots.forEach(s => {
      const thumb = document.createElement('div');
      thumb.className = 'pd-reel-thumb';
      thumb.title = 'لمحة';
      if (s.thumbnail_url || s.file_url) {
        thumb.style.backgroundImage = `url('${ApiClient.mediaUrl(s.thumbnail_url || s.file_url)}')`;
      }
      const del = document.createElement('button');
      del.className = 'pd-reel-del';
      del.innerHTML = '&times;';
      del.title = 'حذف';
      del.onclick = () => _deleteSpotlight(s.id, thumb);
      thumb.appendChild(del);
      row.appendChild(thumb);
    });
  }

  async function _deleteSpotlight(id, el) {
    if (!confirm('هل تريد حذف هذا الفيديو؟')) return;
    const res = await ApiClient.request(`/api/providers/me/spotlights/${id}/`, { method: 'DELETE' });
    if (res.ok) el.remove();
  }

  function _bindUploads() {
    // Cover upload
    document.getElementById('cover-upload').addEventListener('change', async (e) => {
      const file = e.target.files[0];
      if (!file) return;
      const fd = new FormData();
      fd.append('cover_image', file);
      const res = await ApiClient.request('/api/providers/me/profile/', { method: 'PATCH', body: fd, formData: true });
      if (res.ok) {
        document.getElementById('pd-cover').style.backgroundImage = `url('${URL.createObjectURL(file)}')`;
      }
    });

    // Avatar upload
    document.getElementById('avatar-upload').addEventListener('change', async (e) => {
      const file = e.target.files[0];
      if (!file) return;
      const fd = new FormData();
      fd.append('profile_image', file);
      const res = await ApiClient.request('/api/providers/me/profile/', { method: 'PATCH', body: fd, formData: true });
      if (res.ok) {
        document.getElementById('pd-avatar').style.backgroundImage = `url('${URL.createObjectURL(file)}')`;
      }
    });

    // Spotlight upload
    document.getElementById('spotlight-upload').addEventListener('change', async (e) => {
      const file = e.target.files[0];
      if (!file) return;
      const fd = new FormData();
      fd.append('file', file);
      const res = await ApiClient.request('/api/providers/me/spotlights/', { method: 'POST', body: fd, formData: true });
      if (res.ok) location.reload();
    });
  }

  function _bindModeToggle() {
    const clientBtn = document.getElementById('mode-client-btn');
    const provBtn = document.getElementById('mode-provider-btn');
    clientBtn.addEventListener('click', () => {
      sessionStorage.setItem('nw_account_mode', 'client');
      window.location.href = '/profile/';
    });
    provBtn.addEventListener('click', () => {
      sessionStorage.setItem('nw_account_mode', 'provider');
    });
  }

  function _bindQrAction() {
    const btn = document.getElementById('stat-qr-btn');
    const modal = document.getElementById('pd-qr-modal');
    const closeBtn = document.getElementById('pd-qr-close');
    const copyBtn = document.getElementById('pd-qr-copy');
    const shareBtn = document.getElementById('pd-qr-share');
    const openBtn = document.getElementById('pd-qr-open');
    const qrImage = document.getElementById('pd-qr-image');
    const qrLink = document.getElementById('pd-qr-link');
    if (!btn || !modal) return;

    let qrData = null;

    async function ensureQrData() {
      if (qrData && qrData.targetUrl) return qrData;
      if (!window.NwProfileQr || typeof window.NwProfileQr.resolve !== 'function') {
        throw new Error('تعذر تهيئة QR');
      }
      if (_profile && (_providerProfile || _profile.id)) {
        qrData = window.NwProfileQr.resolve(_profile, _providerProfile);
        return qrData;
      }
      if (typeof window.NwProfileQr.loadCurrent === 'function') {
        const current = await window.NwProfileQr.loadCurrent();
        if (!_profile) _profile = current.me;
        if (!_providerProfile) _providerProfile = current.providerProfile;
        qrData = current.qr;
        return qrData;
      }
      throw new Error('تعذر تحميل بيانات QR');
    }

    function renderQr(data) {
      if (!data) {
        if (qrImage) qrImage.removeAttribute('src');
        if (qrLink) qrLink.textContent = 'جاري تحميل الرابط...';
        if (openBtn) openBtn.href = '#';
        return;
      }
      if (qrImage) qrImage.src = data.imageUrl;
      if (qrLink) qrLink.textContent = data.targetUrl;
      if (openBtn) openBtn.href = data.targetUrl;
    }

    btn.addEventListener('click', async () => {
      modal.classList.remove('hidden');
      modal.setAttribute('aria-hidden', 'false');
      renderQr(null);
      try {
        renderQr(await ensureQrData());
      } catch (error) {
        alert(error && error.message ? error.message : 'تعذر تحميل QR');
        close();
      }
    });

    const close = () => {
      modal.classList.add('hidden');
      modal.setAttribute('aria-hidden', 'true');
    };

    if (closeBtn) closeBtn.addEventListener('click', close);
    modal.addEventListener('click', (e) => {
      if (e.target === modal) close();
    });

    if (copyBtn) {
      copyBtn.addEventListener('click', async () => {
        try {
          const data = await ensureQrData();
          await navigator.clipboard.writeText(data.targetUrl);
          alert('تم نسخ الرابط');
        } catch (error) {
          alert(error && error.message ? error.message : 'تعذر النسخ');
        }
      });
    }

    if (shareBtn) {
      shareBtn.addEventListener('click', async () => {
        try {
          const data = await ensureQrData();
          if (navigator.share) {
            try {
              await navigator.share({ title: data.title, text: data.targetUrl, url: data.targetUrl });
              return;
            } catch {
              // continue to fallback
            }
          }
          window.location.href = '/my-qr/';
        } catch (error) {
          alert(error && error.message ? error.message : 'تعذر مشاركة الرابط');
        }
      });
    }
  }

  function _setText(parentId, selector, val) {
    const parent = document.getElementById(parentId);
    if (!parent) return;
    const el = parent.querySelector(selector);
    if (el) el.textContent = val;
  }

  document.addEventListener('DOMContentLoaded', init);
  return { init };
})();
