/* ===================================================================
   providerDashboardPage.js — Provider Dashboard (لوحة تحكم مقدم الخدمة)
   1:1 parity with Flutter provider_home_screen.dart
   =================================================================== */
'use strict';

const ProviderDashboardPage = (() => {
  let _profile = null;
  let _providerProfile = null;
  let _providerStats = null;

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
  }

  async function _loadData() {
    // Parallel fetch
    const [profRes, provRes, subRes, urgentRes, newRes, completedRes, spotsRes] =
      await Promise.allSettled([
        ApiClient.get('/api/accounts/me/'),
        ApiClient.get('/api/providers/me/profile/'),
        ApiClient.get('/api/subscriptions/my/'),
        ApiClient.get('/api/marketplace/provider/urgent/available/'),
        ApiClient.get('/api/marketplace/provider/requests/?status_group=new'),
        ApiClient.get('/api/marketplace/provider/requests/?status_group=completed'),
        ApiClient.get('/api/providers/me/spotlights/'),
      ]);

    if (profRes.status === 'fulfilled' && profRes.value.ok) {
      _profile = profRes.value.data;
    }
    if (provRes.status === 'fulfilled' && provRes.value.ok) {
      _providerProfile = provRes.value.data;
    }

    if (_providerProfile && _providerProfile.id) {
      const statsRes = await ApiClient.get('/api/providers/' + _providerProfile.id + '/stats/?mode=provider');
      if (statsRes.ok && statsRes.data) {
        _providerStats = statsRes.data;
      }
    }

    _renderHeader();
    _renderStats();
    _renderSubscription(subRes);
    _renderCompletion();
    _renderKPIs(urgentRes, newRes, completedRes);
    _renderSpotlights(spotsRes);
  }

  function _renderHeader() {
    const p = _providerProfile || {};
    const u = _profile || {};

    // Cover
    const coverEl = document.getElementById('pd-cover');
    if (p.cover_image) {
      coverEl.style.backgroundImage = `url('${ApiClient.mediaUrl(p.cover_image)}')`;
    }

    // Avatar
    const avatarEl = document.getElementById('pd-avatar');
    const img = p.profile_image || u.profile_image;
    if (img) {
      avatarEl.style.backgroundImage = `url('${ApiClient.mediaUrl(img)}')`;
    } else {
      avatarEl.textContent = (p.display_name || u.first_name || '؟')[0];
    }

    // Name
    document.getElementById('pd-name').textContent = p.display_name || `${u.first_name || ''} ${u.last_name || ''}`.trim() || 'مقدم خدمة';
    document.getElementById('pd-handle').textContent = u.username ? `@${u.username}` : '';

    // Verified
    if (p.is_verified) {
      document.getElementById('pd-verified').style.display = '';
    }
  }

  function _renderStats() {
    const p = _providerProfile || {};
    const stats = _providerStats || {};
    const followers = stats.followers_count ?? p.followers_count ?? _profile?.provider_followers_count ?? 0;
    const following = stats.following_count ?? p.following_count ?? _profile?.following_count ?? 0;
    const likes = stats.likes_count ?? p.likes_count ?? _profile?.provider_likes_received_count ?? _profile?.likes_count ?? 0;
    const clients = p.total_clients ?? stats.completed_requests ?? p.completed_requests ?? 0;

    _setText('stat-followers', '.pd-stat-val', followers);
    _setText('stat-following', '.pd-stat-val', following);
    _setText('stat-likes', '.pd-stat-val', likes);
    _setText('stat-clients', '.pd-stat-val', clients);
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

  function _renderCompletion() {
    const p = _providerProfile || {};
    const pct = p.profile_completion || 0;
    document.getElementById('completion-pct').textContent = `${pct}%`;
    document.getElementById('completion-bar').style.width = `${pct}%`;
    if (pct >= 100) {
      document.getElementById('completion-card').style.display = 'none';
    }
  }

  function _renderKPIs(urgentRes, newRes, completedRes) {
    let urgent = 0, newCount = 0, completed = 0;
    if (urgentRes.status === 'fulfilled' && urgentRes.value.ok) {
      const d = urgentRes.value.data;
      urgent = d.count ?? (Array.isArray(d) ? d.length : (d.results || []).length);
    }
    if (newRes.status === 'fulfilled' && newRes.value.ok) {
      const d = newRes.value.data;
      newCount = d.count ?? (Array.isArray(d) ? d.length : (d.results || []).length);
    }
    if (completedRes.status === 'fulfilled' && completedRes.value.ok) {
      const d = completedRes.value.data;
      completed = d.count ?? (Array.isArray(d) ? d.length : (d.results || []).length);
    }
    document.getElementById('kpi-urgent').textContent = urgent;
    document.getElementById('kpi-new').textContent = newCount;
    document.getElementById('kpi-completed').textContent = completed;
  }

  function _renderSpotlights(spotsRes) {
    const row = document.getElementById('reels-row');
    if (spotsRes.status !== 'fulfilled' || !spotsRes.value.ok) return;
    const spots = spotsRes.value.data?.results || spotsRes.value.data || [];
    spots.forEach(s => {
      const thumb = document.createElement('div');
      thumb.className = 'pd-reel-thumb';
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

  function _setText(parentId, selector, val) {
    const parent = document.getElementById(parentId);
    if (!parent) return;
    const el = parent.querySelector(selector);
    if (el) el.textContent = val;
  }

  document.addEventListener('DOMContentLoaded', init);
  return { init };
})();
