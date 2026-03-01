/* ===================================================================
   settingsPage.js — Account settings / profile editing controller
   GET  /api/accounts/me/
   PATCH /api/accounts/me/
   DELETE /api/accounts/delete/
   =================================================================== */
'use strict';

const SettingsPage = (() => {

  function init() {
    const authGate = document.getElementById('auth-gate');
    const content = document.getElementById('settings-content');

    if (!Auth.isLoggedIn()) {
      if (authGate) authGate.classList.remove('hidden');
      if (content) content.classList.add('hidden');
      return;
    }

    if (authGate) authGate.classList.add('hidden');
    if (content) content.classList.remove('hidden');

    _loadProfile();

    const form = document.getElementById('settings-form');
    if (form) form.addEventListener('submit', _onSave);

    const delBtn = document.getElementById('delete-account-btn');
    if (delBtn) delBtn.addEventListener('click', _onDeleteAccount);

    const changePasswordBtn = document.getElementById('btn-change-password');
    if (changePasswordBtn) {
      changePasswordBtn.addEventListener('click', (e) => {
        e.preventDefault();
        alert('ميزة تغيير كلمة المرور ستكون متاحة قريبًا.');
      });
    }

    const avatarInput = document.getElementById('avatar-file-input');
    if (avatarInput) avatarInput.addEventListener('change', _onAvatarSelected);
  }

  /* ---- Load profile data into form ---- */
  async function _loadProfile() {
    const profile = Auth.getProfile ? await Auth.getProfile(true) : null;
    let data = profile;

    if (!data) {
      const res = await ApiClient.get('/api/accounts/me/');
      if (!res.ok) return;
      data = res.data;
    }

    _setVal('set-username', data.username || data.phone || '');
    _setVal('set-first-name', data.first_name || '');
    _setVal('set-last-name', data.last_name || '');
    _setVal('set-phone', data.phone || '');
    _setVal('set-email', data.email || '');

    // Header
    const displayName = [data.first_name || '', data.last_name || '']
      .join(' ')
      .trim() || data.username || data.phone || 'مستخدم';

    const nameEl = document.getElementById('settings-name');
    if (nameEl) nameEl.textContent = displayName;

    const emailEl = document.getElementById('settings-email');
    if (emailEl) emailEl.textContent = data.email || data.phone || '';

    const avatarEl = document.getElementById('settings-avatar');
    if (avatarEl && data.profile_image) {
      avatarEl.src = ApiClient.mediaUrl(data.profile_image);
    }
  }

  function _setVal(id, val) {
    const el = document.getElementById(id);
    if (el) el.value = val;
  }

  /* ---- Save ---- */
  async function _onSave(e) {
    e.preventDefault();
    _setSaving(true);
    _hideSuccess();
    _hideError();

    const body = {};
    const first = document.getElementById('set-first-name')?.value?.trim();
    const last = document.getElementById('set-last-name')?.value?.trim();
    const email = document.getElementById('set-email')?.value?.trim();

    if (first !== undefined) body.first_name = first;
    if (last !== undefined) body.last_name = last;
    if (email !== undefined) body.email = email;

    const res = await ApiClient.request('/api/accounts/me/', { method: 'PATCH', body });
    if (res.ok) {
      _showSuccess('تم حفظ التغييرات بنجاح');
      // Update cached profile
      if (Auth.clearProfileCache) {
        Auth.clearProfileCache();
      }
      await _loadProfile();
    } else {
      const msg = _firstErrorMessage(res.data) || 'حدث خطأ أثناء الحفظ';
      _showError(msg);
    }

    _setSaving(false);
  }

  /* ---- Delete Account ---- */
  async function _onDeleteAccount() {
    const confirmed = confirm('هل أنت متأكد من حذف حسابك؟ هذا الإجراء لا يمكن التراجع عنه.');
    if (!confirmed) return;

    const btn = document.getElementById('delete-account-btn');
    if (btn) { btn.disabled = true; btn.textContent = 'جاري الحذف...'; }

    const res = await ApiClient.request('/api/accounts/delete/', { method: 'DELETE' });
    if (res.ok) {
      Auth.logout();
      window.location.href = '/';
    } else {
      _showError(res.data?.detail || 'حدث خطأ أثناء حذف الحساب');
      if (btn) { btn.disabled = false; btn.textContent = 'حذف الحساب نهائياً'; }
    }
  }

  async function _onAvatarSelected(e) {
    const file = e?.target?.files?.[0];
    if (!file) return;

    if (!file.type.startsWith('image/')) {
      _showError('الملف المختار ليس صورة');
      return;
    }

    const avatarEl = document.getElementById('settings-avatar');
    if (avatarEl) {
      avatarEl.src = URL.createObjectURL(file);
    }

    const formData = new FormData();
    formData.append('profile_image', file);

    _hideSuccess();
    _hideError();
    const res = await ApiClient.request('/api/accounts/me/', {
      method: 'PATCH',
      body: formData,
      formData: true,
    });

    if (res.ok) {
      if (Auth.clearProfileCache) {
        Auth.clearProfileCache();
      }
      _showSuccess('تم تحديث صورة الملف الشخصي');
      await _loadProfile();
      return;
    }

    _showError(_firstErrorMessage(res.data) || 'تعذر رفع الصورة');
  }

  /* ---- Feedback ---- */
  function _showSuccess(msg) {
    const el = document.getElementById('save-success');
    if (!el) return;
    el.textContent = msg;
    el.classList.remove('hidden');
    setTimeout(() => { el.classList.add('hidden'); }, 3000);
  }

  function _showError(msg) {
    const el = document.getElementById('save-error');
    if (!el) return;
    el.textContent = msg;
    el.classList.remove('hidden');
    setTimeout(() => { el.classList.add('hidden'); }, 4000);
  }

  function _hideSuccess() {
    const el = document.getElementById('save-success');
    if (!el) return;
    el.textContent = '';
    el.classList.add('hidden');
  }

  function _hideError() {
    const el = document.getElementById('save-error');
    if (!el) return;
    el.textContent = '';
    el.classList.add('hidden');
  }

  function _setSaving(saving) {
    const btn = document.getElementById('settings-save-btn');
    const txt = document.getElementById('save-text');
    const spin = document.getElementById('save-spinner');
    if (btn) btn.disabled = saving;
    if (txt) txt.classList.toggle('hidden', saving);
    if (spin) spin.classList.toggle('hidden', !saving);
  }

  function _firstErrorMessage(payload) {
    if (!payload || typeof payload !== 'object') return '';
    if (typeof payload.detail === 'string' && payload.detail) return payload.detail;
    if (typeof payload.error === 'string' && payload.error) return payload.error;
    const firstKey = Object.keys(payload)[0];
    if (!firstKey) return '';
    const val = payload[firstKey];
    if (Array.isArray(val) && val.length) return String(val[0] || '');
    if (typeof val === 'string') return val;
    return '';
  }

  // Boot
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
  return {};
})();
