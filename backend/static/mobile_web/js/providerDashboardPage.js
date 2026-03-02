/* ===================================================================
   providerDashboardPage.js — Provider Dashboard (لوحة تحكم مقدم الخدمة)
   1:1 parity with Flutter provider_home_screen.dart
   =================================================================== */
'use strict';

const ProviderDashboardPage = (() => {
  let _profile = null;
  let _providerProfile = null;

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
    _setText('stat-followers', '.pd-stat-val', p.followers_count || 0);
    _setText('stat-following', '.pd-stat-val', p.following_count || 0);
    _setText('stat-likes', '.pd-stat-val', p.total_likes || 0);
    _setText('stat-clients', '.pd-stat-val', p.total_clients || 0);
  }

  function _renderSubscription(subRes) {
    const card = document.getElementById('subscription-card');
    if (subRes.status === 'fulfilled' && subRes.value.ok && subRes.value.data) {
      const subs = Array.isArray(subRes.value.data) ? subRes.value.data : (subRes.value.data.results || []);
      const active = subs.find(s => s.status === 'active');
      if (active) {
        card.style.display = '';
        document.getElementById('plan-name').textContent = active.plan_name || active.plan?.name || 'الباقة';
        if (active.end_date) {
          document.getElementById('plan-expiry').textContent = `ينتهي: ${new Date(active.end_date).toLocaleDateString('ar-SA')}`;
        }
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
