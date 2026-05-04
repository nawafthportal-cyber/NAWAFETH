'use strict';

window.NwProfileQr = (() => {
  function _hasProviderProfile(me) {
    if (!me || typeof me !== 'object') return false;
    return !!(
      me.has_provider_profile
      || me.is_provider
      || me.provider_profile_id
      || String(me.role_state || '').trim().toLowerCase() === 'provider'
    );
  }

  function buildTargetUrl(me, providerProfile) {
    const origin = window.location.origin.replace(/\/$/, '');
    if (providerProfile && providerProfile.id) {
      return `${origin}/provider/${providerProfile.id}/`;
    }
    if (me && me.id) {
      return `${origin}/profile/?user=${me.id}`;
    }
    return `${origin}/profile/`;
  }

  function buildImageUrl(targetUrl, size) {
    const normalizedSize = Number(size) > 0 ? Number(size) : 420;
    return `https://api.qrserver.com/v1/create-qr-code/?size=${normalizedSize}x${normalizedSize}&data=${encodeURIComponent(targetUrl)}`;
  }

  function resolve(me, providerProfile) {
    const targetUrl = buildTargetUrl(me, providerProfile);
    return {
      title: providerProfile && providerProfile.id ? 'QR ملف مقدم الخدمة' : 'رابط نافذتي',
      targetUrl,
      imageUrl: buildImageUrl(targetUrl, 420),
    };
  }

  async function loadCurrent() {
    const meRes = await ApiClient.get('/api/accounts/me/');
    if (!meRes.ok || !meRes.data) {
      throw new Error('تعذر تحميل بيانات الحساب');
    }

    let providerProfile = null;
    if (_hasProviderProfile(meRes.data)) {
      const profileRes = await ApiClient.get('/api/providers/me/profile/');
      providerProfile = profileRes.ok && profileRes.data ? profileRes.data : null;
    }

    return {
      me: meRes.data,
      providerProfile,
      qr: resolve(meRes.data, providerProfile),
    };
  }

  return { buildImageUrl, buildTargetUrl, loadCurrent, resolve };
})();
