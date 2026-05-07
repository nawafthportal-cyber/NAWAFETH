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
  let _subscriptionPlans = [];
  let _activeSubscription = null;
  let _currentSpotlightCount = 0;
  let _coverGalleryIndex = 0;
  let _coverGalleryTimer = 0;
  const PLAN_ORDER = ['basic', 'riyadi', 'pro'];

  function _apiErrorMessage(response, fallback) {
    const data = response && response.data ? response.data : null;
    if (data) {
      if (typeof data.detail === 'string' && data.detail.trim()) return data.detail.trim();
      if (Array.isArray(data.non_field_errors) && data.non_field_errors.length) return String(data.non_field_errors[0]);
      const firstKey = Object.keys(data)[0];
      if (firstKey) {
        const value = data[firstKey];
        if (Array.isArray(value) && value.length) return String(value[0]);
        if (typeof value === 'string' && value.trim()) return value.trim();
      }
    }
    return fallback || 'فشل الطلب';
  }

  function _spotlightFileType(file) {
    const mime = String(file && file.type || '').trim().toLowerCase();
    const name = String(file && file.name || '').trim().toLowerCase();
    if (mime.startsWith('video/') || /\.(mp4|mov|avi|webm|mkv)$/i.test(name)) return 'video';
    if (mime.startsWith('image/') || /\.(jpg|jpeg|png|webp|gif|bmp)$/i.test(name)) return 'image';
    return '';
  }

  function _extractList(payload) {
    if (Array.isArray(payload)) return payload;
    if (payload && Array.isArray(payload.results)) return payload.results;
    return [];
  }

  function _normalizeCoverGallery(profile = _providerProfile) {
    const p = profile || {};
    const gallery = Array.isArray(p.cover_gallery)
      ? p.cover_gallery
      : (Array.isArray(p.coverGallery) ? p.coverGallery : []);
    const normalizedGallery = gallery
      .map((item, index) => {
        const rawUrl = item && (item.image_url || item.imageUrl || item.url || item.image);
        return {
          id: item && item.id != null ? item.id : null,
          imageUrl: rawUrl ? ApiClient.mediaUrl(rawUrl) : '',
          rawUrl: rawUrl || '',
          sortOrder: Number(item && item.sort_order != null ? item.sort_order : index),
          isPrimary: Boolean(item && item.is_primary) || index === 0,
        };
      })
      .filter((item) => item.imageUrl);
    if (normalizedGallery.length) return normalizedGallery;

    const coverImages = Array.isArray(p.cover_images)
      ? p.cover_images
      : (Array.isArray(p.coverImages) ? p.coverImages : []);
    const normalizedList = coverImages
      .map((rawUrl, index) => ({
        id: null,
        imageUrl: rawUrl ? ApiClient.mediaUrl(rawUrl) : '',
        rawUrl: rawUrl || '',
        sortOrder: index,
        isPrimary: index === 0,
      }))
      .filter((item) => item.imageUrl);
    if (normalizedList.length) return normalizedList;

    const coverImage = String(p.cover_image || p.coverImage || '').trim();
    if (!coverImage) return [];
    return [{ id: null, imageUrl: ApiClient.mediaUrl(coverImage), rawUrl: coverImage, sortOrder: 0, isPrimary: true }];
  }

  function _syncProviderCoverGallery(payload) {
    if (!_providerProfile || typeof _providerProfile !== 'object') _providerProfile = {};
    const results = Array.isArray(payload?.results) ? payload.results : [];
    _providerProfile.cover_gallery = results;
    _providerProfile.cover_images = results.map((item) => item?.image_url || item?.imageUrl || '').filter(Boolean);
    _providerProfile.cover_image = _providerProfile.cover_images[0] || '';
  }

  function _statusCode(status) {
    return String(status || '').trim().toLowerCase();
  }

  function _subscriptionRank(sub) {
    switch (_statusCode((sub && (sub.provider_status_code || sub.status)) || '')) {
      case 'active':
        return 0;
      case 'grace':
        return 1;
      case 'awaiting_review':
        return 2;
      case 'pending_payment':
        return 3;
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

  function _planTier(plan) {
    return String(
      (plan && (plan.canonical_tier || plan.tier || plan.code)) || ''
    ).trim().toLowerCase();
  }

  function _basicPlanActionUrl() {
    const basicPlan = _subscriptionPlans.find((plan) => _planTier(plan) === 'basic');
    if (basicPlan && basicPlan.id) {
      return `/plans/summary/?plan_id=${encodeURIComponent(String(basicPlan.id))}`;
    }
    return '/plans/';
  }

  function _subscriptionCapabilities(sub) {
    return sub?.plan?.capabilities || {};
  }

  function _spotlightQuota(sub = _activeSubscription) {
    const quota = _subscriptionCapabilities(sub)?.spotlights?.quota ?? sub?.plan?.provider_offer?.spotlights_quota;
    const parsed = Number(quota);
    return Number.isFinite(parsed) ? parsed : 0;
  }

  function _coverGalleryLimit(sub = _activeSubscription) {
    const limit = _subscriptionCapabilities(sub)?.banner_images?.limit ?? sub?.plan?.provider_offer?.banner_images_limit;
    const parsed = Number(limit);
    return Number.isFinite(parsed) ? parsed : 0;
  }

  function _spotlightPlanName(sub = _activeSubscription) {
    return _planTitle(sub || {});
  }

  function _recommendedUpgradePlan(sub = _activeSubscription) {
    const currentTier = _planTier(sub?.plan || sub);
    const currentIndex = PLAN_ORDER.indexOf(currentTier);
    if (currentIndex === -1) return null;
    for (let index = currentIndex + 1; index < PLAN_ORDER.length; index += 1) {
      const candidate = _subscriptionPlans.find((plan) => _planTier(plan) === PLAN_ORDER[index] && plan?.is_active !== false);
      if (candidate) return candidate;
    }
    return null;
  }

  function _recommendedUpgradeUrl(sub = _activeSubscription) {
    const plan = _recommendedUpgradePlan(sub);
    if (plan?.id) {
      return `/plans/summary/?plan_id=${encodeURIComponent(String(plan.id))}`;
    }
    return '/plans/';
  }

  function _recommendedUpgradeLabel(sub = _activeSubscription) {
    const plan = _recommendedUpgradePlan(sub);
    if (plan?.title) return `الترقية إلى ${plan.title}`;
    return 'استعراض جميع الباقات';
  }

  function _spotlightQuotaReached(sub = _activeSubscription) {
    const quota = _spotlightQuota(sub);
    return quota > 0 && _currentSpotlightCount >= quota;
  }

  function _spotlightQuotaUnavailable(sub = _activeSubscription) {
    return !!sub && _spotlightQuota(sub) <= 0;
  }

  function _renderSpotlightQuotaNote() {
    const note = document.getElementById('spotlight-note');
    const trigger = document.getElementById('spotlight-upload-trigger');
    if (!note || !trigger || !_activeSubscription) return;

    const quota = _spotlightQuota();
    const planName = _spotlightPlanName();
    const reached = _spotlightQuotaReached();
    const remaining = Math.max(quota - _currentSpotlightCount, 0);

    trigger.classList.toggle('is-quota-full', reached);
    trigger.title = reached
      ? `بلغت الحد الأقصى في ${planName}`
      : 'إضافة فيديو';

    note.classList.remove('hidden', 'is-warning');
    if (quota <= 0) {
      trigger.classList.add('is-quota-full');
      note.classList.add('is-warning');
      note.textContent = `رفع اللمحات غير متاح ضمن ${planName}. رقِّ الباقة لتفعيل هذه الميزة.`;
      return;
    }

    if (reached) {
      note.classList.add('is-warning');
      note.textContent = `استخدمت ${_currentSpotlightCount} من ${quota} لمحات ضمن ${planName}. احذف لمحة حالية أو رقِّ الباقة لإضافة المزيد.`;
      return;
    }

    note.textContent = `المتاح ضمن ${planName}: ${remaining} من أصل ${quota} لمحات إضافية. المستخدم حاليًا ${_currentSpotlightCount}/${quota}.`;
  }

  function _closeSpotlightUpgradeDialog() {
    const existing = document.getElementById('pd-spotlight-upgrade-modal');
    if (existing) existing.remove();
    document.body.classList.remove('pd-upgrade-modal-open');
  }

  function _showSpotlightUpgradeDialog(payload = {}) {
    _closeSpotlightUpgradeDialog();

    const title = payload.title || 'وصلت إلى الحد الأقصى لعدد اللمحات';
    const detail = payload.detail || 'احذف لمحة حالية أو رقِّ الباقة لإضافة المزيد من اللمحات.';
    const planName = payload.planName || _spotlightPlanName();
    const quota = Number.isFinite(Number(payload.quota)) ? Number(payload.quota) : _spotlightQuota();
    const currentCount = Number.isFinite(Number(payload.currentCount)) ? Number(payload.currentCount) : _currentSpotlightCount;
    const upgradeUrl = payload.upgradeUrl || _recommendedUpgradeUrl();
    const upgradeLabel = payload.upgradeLabel || _recommendedUpgradeLabel();

    const overlay = document.createElement('div');
    overlay.id = 'pd-spotlight-upgrade-modal';
    overlay.className = 'pd-upgrade-modal';
    overlay.addEventListener('click', (event) => {
      if (event.target === overlay) _closeSpotlightUpgradeDialog();
    });

    const dialog = document.createElement('div');
    dialog.className = 'pd-upgrade-dialog';
    dialog.setAttribute('role', 'dialog');
    dialog.setAttribute('aria-modal', 'true');
    dialog.setAttribute('aria-labelledby', 'pd-upgrade-title');

    const badge = document.createElement('div');
    badge.className = 'pd-upgrade-badge';
    badge.textContent = 'ميزة اللمحات';

    const heading = document.createElement('h3');
    heading.id = 'pd-upgrade-title';
    heading.className = 'pd-upgrade-title';
    heading.textContent = title;

    const copy = document.createElement('p');
    copy.className = 'pd-upgrade-copy';
    copy.textContent = detail;

    const stats = document.createElement('div');
    stats.className = 'pd-upgrade-stats';
    stats.innerHTML = `
      <div class="pd-upgrade-stat">
        <strong>${currentCount}/${quota}</strong>
        <span>اللمحات المستخدمة</span>
      </div>
      <div class="pd-upgrade-stat">
        <strong>${planName}</strong>
        <span>الباقة الحالية</span>
      </div>
    `;

    const actions = document.createElement('div');
    actions.className = 'pd-upgrade-actions';

    const primary = document.createElement('a');
    primary.className = 'pdv4-cta-btn';
    primary.href = upgradeUrl;
    primary.textContent = upgradeLabel;

    const secondary = document.createElement('button');
    secondary.type = 'button';
    secondary.className = 'pd-upgrade-secondary';
    secondary.textContent = 'إدارة اللمحات الحالية';
    secondary.addEventListener('click', _closeSpotlightUpgradeDialog);

    actions.appendChild(primary);
    actions.appendChild(secondary);

    dialog.appendChild(badge);
    dialog.appendChild(heading);
    dialog.appendChild(copy);
    dialog.appendChild(stats);
    dialog.appendChild(actions);
    overlay.appendChild(dialog);
    document.body.appendChild(overlay);
    document.body.classList.add('pd-upgrade-modal-open');
  }

  function _spotlightQuotaPayloadFromResponse(response) {
    const data = response?.data || {};
    return {
      title: data.error_code === 'spotlight_quota_unavailable'
        ? 'رفع اللمحات غير متاح ضمن باقتك الحالية'
        : 'وصلت إلى الحد الأقصى لعدد اللمحات',
      detail: _apiErrorMessage(response, 'احذف لمحة حالية أو رقِّ الباقة لإضافة المزيد من اللمحات.'),
      planName: data.plan_name || _spotlightPlanName(),
      quota: data.spotlight_quota,
      currentCount: data.current_count,
      upgradeUrl: _recommendedUpgradeUrl(),
      upgradeLabel: _recommendedUpgradeLabel(),
    };
  }

  function _setSpotlightSubscriptionLock(isLocked) {
    const input = document.getElementById('spotlight-upload');
    const trigger = document.getElementById('spotlight-upload-trigger');
    const note = document.getElementById('spotlight-note');
    if (input) input.disabled = !!isLocked;
    if (trigger) {
      trigger.classList.toggle('is-disabled', !!isLocked);
      trigger.setAttribute('aria-disabled', isLocked ? 'true' : 'false');
      trigger.title = isLocked ? 'يتطلب رفع الأضواء اشتراكًا فعالًا' : 'إضافة فيديو';
    }
    if (note) {
      note.classList.toggle('hidden', !isLocked);
      note.textContent = isLocked
        ? 'رفع اللمحــات والأضواء متاح بعد تفعيل إحدى الباقات. الباقة الأساسية المجانية كافية لتفعيل هذه الميزة.'
        : '';
    }
  }

  function _setSpotlightUploadState(isUploading, options = {}) {
    const row = document.getElementById('reels-row');
    const trigger = document.getElementById('spotlight-upload-trigger');
    const status = document.getElementById('spotlight-upload-status');
    if (!row || !trigger) return;

    const pendingId = 'spotlight-upload-pending';
    let pending = document.getElementById(pendingId);
    row.classList.toggle('is-uploading', !!isUploading);
    row.setAttribute('aria-busy', isUploading ? 'true' : 'false');
    trigger.classList.toggle('is-uploading', !!isUploading);
    trigger.setAttribute(
      'aria-disabled',
      (isUploading || trigger.classList.contains('is-disabled')) ? 'true' : 'false'
    );

    if (status) {
      status.classList.toggle('hidden', !isUploading);
      status.classList.toggle('is-uploading', !!isUploading);
      status.textContent = isUploading
        ? (options.statusText || 'جاري رفع الريل، انتظر قليلًا حتى يكتمل.')
        : '';
    }

    if (!isUploading) {
      if (pending) {
        if (pending.dataset.previewUrl) {
          try {
            URL.revokeObjectURL(pending.dataset.previewUrl);
          } catch (_) {
            // Ignore revoke failures for stale object URLs.
          }
        }
        pending.remove();
      }
      if (!trigger.classList.contains('is-disabled')) {
        trigger.title = 'إضافة فيديو';
      }
      return;
    }

    if (!pending) {
      pending = document.createElement('div');
      pending.id = pendingId;
      pending.className = 'pd-reel-thumb pd-reel-thumb-uploading';
      pending.setAttribute('role', 'status');
      pending.setAttribute('aria-live', 'polite');
      if (trigger.nextSibling) {
        row.insertBefore(pending, trigger.nextSibling);
      } else {
        row.appendChild(pending);
      }
    }

    pending.dataset.previewUrl = options.previewUrl || '';
    pending.style.backgroundImage = options.previewUrl ? `url('${options.previewUrl}')` : '';
    pending.replaceChildren();

    const overlay = document.createElement('div');
    overlay.className = 'pd-reel-upload-overlay';

    const spinner = document.createElement('span');
    spinner.className = 'spinner-inline pd-reel-upload-spinner';
    spinner.setAttribute('aria-hidden', 'true');

    const label = document.createElement('span');
    label.className = 'pd-reel-upload-label';
    label.textContent = options.label || 'جاري الرفع';

    overlay.appendChild(spinner);
    overlay.appendChild(label);
    pending.appendChild(overlay);
    trigger.title = 'جاري رفع الريل';
  }

  function _setProfileMediaUploadState(kind, isUploading, message) {
    const isCover = kind === 'cover';
    const trigger = document.getElementById(isCover ? 'pd-cover-upload-trigger' : 'pd-avatar-upload-trigger');
    const input = document.getElementById(isCover ? 'cover-upload' : 'avatar-upload');
    const status = document.getElementById(isCover ? 'pd-cover-upload-status' : 'pd-avatar-upload-status');
    const target = document.getElementById(isCover ? 'pd-cover' : 'pd-avatar');

    if (trigger) {
      trigger.classList.toggle('is-uploading', !!isUploading);
      trigger.setAttribute('aria-disabled', isUploading ? 'true' : 'false');
    }
    if (input) input.disabled = !!isUploading;
    if (target) target.setAttribute('aria-busy', isUploading ? 'true' : 'false');
    if (status) {
      status.classList.toggle('hidden', !isUploading);
      status.textContent = isUploading ? (message || 'جاري الرفع...') : '';
    }
  }

  function _stopCoverGalleryRotation() {
    if (_coverGalleryTimer) {
      window.clearInterval(_coverGalleryTimer);
      _coverGalleryTimer = 0;
    }
  }

  function _renderCoverGalleryManager(gallery = _normalizeCoverGallery()) {
    const strip = document.getElementById('pd-cover-gallery-strip');
    const dots = document.getElementById('pd-cover-gallery-dots');
    const note = document.getElementById('pd-cover-gallery-note');
    if (!strip || !dots || !note) return;

    const limit = _coverGalleryLimit();
    const count = gallery.length;
    note.classList.toggle('is-locked', limit <= 0);
    if (limit <= 0) {
      note.textContent = 'فعّل إحدى الباقات لإضافة خلفيات تتبدل خلف صورتك الشخصية بشكل احترافي.';
    } else if (!count) {
      note.textContent = `يمكنك رفع حتى ${limit} خلفية لملفك، وستتبدل تلقائيًا خلف الصورة الشخصية.`;
    } else if (count >= limit) {
      note.textContent = `فعّلت ${count} من ${limit} خلفيات. احذف واحدة لإضافة خلفية جديدة.`;
    } else {
      note.textContent = `فعّلت ${count} من ${limit} خلفيات، وستتبدل تلقائيًا في صفحتك العامة.`;
    }

    dots.innerHTML = '';
    dots.classList.toggle('hidden', gallery.length <= 1);
    gallery.forEach((item, index) => {
      const dot = document.createElement('button');
      dot.type = 'button';
      dot.className = 'pdv4-cover-gallery-dot' + (index === _coverGalleryIndex ? ' is-active' : '');
      dot.setAttribute('aria-label', `الخلفية ${index + 1}`);
      dot.addEventListener('click', () => {
        _coverGalleryIndex = index;
        _renderHeader();
      });
      dots.appendChild(dot);
    });

    strip.innerHTML = '';
    if (!gallery.length) {
      const empty = document.createElement('div');
      empty.className = 'pdv4-cover-gallery-empty';
      empty.textContent = 'لا توجد خلفيات مضافة بعد.';
      strip.appendChild(empty);
      return;
    }

    gallery.forEach((item, index) => {
      const thumb = document.createElement('button');
      thumb.type = 'button';
      thumb.className = 'pdv4-cover-thumb' + (index === _coverGalleryIndex ? ' is-active' : '');
      thumb.style.backgroundImage = `url('${item.imageUrl}')`;
      thumb.setAttribute('aria-label', `عرض الخلفية ${index + 1}`);
      thumb.addEventListener('click', () => {
        _coverGalleryIndex = index;
        _renderHeader();
      });

      const indexBadge = document.createElement('span');
      indexBadge.className = 'pdv4-cover-thumb-index';
      indexBadge.textContent = item.isPrimary ? 'أساسية' : `#${index + 1}`;
      thumb.appendChild(indexBadge);

      if (item.id != null) {
        const remove = document.createElement('button');
        remove.type = 'button';
        remove.className = 'pdv4-cover-thumb-remove';
        remove.setAttribute('aria-label', 'حذف الخلفية');
        remove.innerHTML = '&times;';
        remove.addEventListener('click', (event) => {
          event.stopPropagation();
          _deleteCoverImage(item.id);
        });
        thumb.appendChild(remove);
      }

      strip.appendChild(thumb);
    });
  }

  async function _deleteCoverImage(id) {
    if (!id) return;
    if (!confirm('هل تريد حذف هذه الخلفية؟')) return;
    _setProfileMediaUploadState('cover', true, 'جاري تحديث خلفيات الملف...');
    try {
      const res = await ApiClient.request(`/api/providers/me/cover-gallery/${id}/`, { method: 'DELETE' });
      if (!res.ok) {
        alert(_apiErrorMessage(res, 'تعذر حذف الخلفية'));
        return;
      }
      _syncProviderCoverGallery(res.data);
      _coverGalleryIndex = Math.max(0, Math.min(_coverGalleryIndex, _normalizeCoverGallery().length - 1));
      _renderHeader();
      if (typeof NwToast !== 'undefined') NwToast.success('تم حذف الخلفية');
    } catch (_) {
      alert('تعذر حذف الخلفية، حاول مرة أخرى');
    } finally {
      _setProfileMediaUploadState('cover', false);
    }
  }

  async function _uploadCoverFiles(fileList) {
    const files = Array.from(fileList || []).filter(Boolean);
    if (!files.length) return;

    const limit = _coverGalleryLimit();
    const currentCount = _normalizeCoverGallery().length;
    const availableSlots = limit > 0 ? Math.max(limit - currentCount, 0) : files.length;
    const queue = availableSlots > 0 ? files.slice(0, availableSlots) : [];
    if (!queue.length) {
      alert('بلغت الحد الأقصى لخلفيات الملف في باقتك الحالية.');
      return;
    }
    if (files.length > queue.length) {
      alert(`سيتم رفع ${queue.length} خلفية فقط الآن حسب المتاح في باقتك الحالية. احذف خلفية حالية إذا أردت استبدالها بصورة أخرى.`);
    }

    _setProfileMediaUploadState('cover', true, queue.length > 1 ? `جاري رفع ${queue.length} خلفيات...` : 'جاري رفع خلفية الملف...');
    let uploadedCount = 0;
    try {
      for (const file of queue) {
        if (file.size > 20 * 1024 * 1024) {
          alert('حجم كل خلفية يجب ألا يتجاوز 20 ميغابايت');
          break;
        }
        const fd = new FormData();
        fd.append('image', file);
        const res = await ApiClient.request('/api/providers/me/cover-gallery/', { method: 'POST', body: fd, formData: true });
        if (!res.ok) {
          alert(_apiErrorMessage(res, 'تعذر رفع خلفية الملف'));
          break;
        }
        _syncProviderCoverGallery(res.data);
        uploadedCount += 1;
      }
      if (uploadedCount > 0) {
        _coverGalleryIndex = Math.max(0, Math.min(_coverGalleryIndex, _normalizeCoverGallery().length - 1));
        _renderHeader();
        if (typeof NwToast !== 'undefined') {
          NwToast.success(uploadedCount === 1 ? 'تمت إضافة خلفية الملف' : `تمت إضافة ${uploadedCount} خلفيات`);
        }
      }
    } catch (_) {
      alert('تعذر رفع خلفيات الملف، حاول مرة أخرى');
    } finally {
      _setProfileMediaUploadState('cover', false);
    }
  }

  function _statusLabel(status) {
    switch (_statusCode(status)) {
      case 'active':
        return 'نشط';
      case 'grace':
        return 'فترة سماح';
      case 'awaiting_review':
        return 'بانتظار المراجعة';
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
    const [profRes, provRes, subRes, plansRes, urgentRes, competitiveRes, assignedRes, spotsRes] =
      await Promise.allSettled([
        ApiClient.get('/api/accounts/me/?mode=provider'),
        ApiClient.get('/api/providers/me/profile/'),
        ApiClient.get('/api/subscriptions/my/'),
        ApiClient.get('/api/subscriptions/plans/'),
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
    if (plansRes.status === 'fulfilled' && plansRes.value.ok) {
      _subscriptionPlans = _extractList(plansRes.value.data);
    }
    if (subRes.status === 'fulfilled' && subRes.value.ok) {
      _activeSubscription = _pickPreferredSubscription(_extractList(subRes.value.data));
    } else {
      _activeSubscription = null;
    }

    if (!_providerProfile || !_providerProfile.id) {
      if (window.Auth && typeof window.Auth.setActiveAccountMode === 'function') {
        window.Auth.setActiveAccountMode('client');
      } else {
        sessionStorage.setItem('nw_account_mode', 'client');
      }
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
    _renderCoverGalleryManager();
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
    const coverGallery = _normalizeCoverGallery(p);
    _stopCoverGalleryRotation();
    if (coverGallery.length) {
      _coverGalleryIndex = Math.max(0, Math.min(_coverGalleryIndex, coverGallery.length - 1));
      coverEl.style.backgroundImage = `url('${coverGallery[_coverGalleryIndex].imageUrl}')`;
      coverEl.classList.add('has-gallery');
    } else {
      coverEl.style.backgroundImage = '';
      coverEl.classList.remove('has-gallery');
    }
    _renderCoverGalleryManager(coverGallery);
    if (coverGallery.length > 1) {
      _coverGalleryTimer = window.setInterval(() => {
        _coverGalleryIndex = (_coverGalleryIndex + 1) % coverGallery.length;
        _renderHeader();
      }, 4600);
    }

    function _looksLikePhone(v) {
      var s = String(v || '').replace(/[\s\-\+\(\)@]/g, '');
      return /^0[0-9]{8,12}$/.test(s) || /^9665[0-9]{8}$/.test(s) || /^5[0-9]{8}$/.test(s);
    }
    function _safeName(v) { var s = String(v || '').trim(); return (s && !_looksLikePhone(s)) ? s : ''; }

    // Avatar
    const avatarEl = document.getElementById('pd-avatar');
    const img = p.profile_image || u.profile_image;
    avatarEl.textContent = '';
    if (img) {
      avatarEl.style.backgroundImage = `url('${ApiClient.mediaUrl(img)}')`;
    } else {
      avatarEl.style.backgroundImage = '';
      avatarEl.textContent = (_safeName(p.display_name) || _safeName(u.first_name) || '؟')[0];
    }

    // Name
    document.getElementById('pd-name').textContent = _safeName(p.display_name) || _safeName(`${u.first_name || ''} ${u.last_name || ''}`.trim()) || 'مقدم خدمة';
    document.getElementById('pd-handle').textContent = (u.username && !_looksLikePhone(u.username)) ? `@${u.username}` : '';

    // Avatar badge overlays
    const blueBadge = document.getElementById('pd-avatar-badge-blue');
    const greenBadge = document.getElementById('pd-avatar-badge-green');
    const excellenceBadge = document.getElementById('pd-avatar-badge-excellence');
    if (blueBadge) blueBadge.classList.toggle('hidden', !isVerifiedBlue);
    if (excellenceBadge) excellenceBadge.classList.toggle('hidden', !hasExcellenceBadges);
    if (greenBadge) greenBadge.classList.toggle('hidden', hasExcellenceBadges || !isVerifiedGreen);

    // Text badge under name — hidden by design (badges shown on avatar instead)
    const verifiedRow = document.getElementById('pd-verified');
    const verifiedLabel = verifiedRow ? verifiedRow.querySelector('span') : null;
    const labels = [];
    if (isVerifiedBlue) labels.push('توثيق أزرق');
    if (isVerifiedGreen) labels.push('توثيق أخضر');
    if (hasExcellenceBadges) labels.push('شارة تميز');
    if (verifiedRow) {
      verifiedRow.style.display = 'none';
      verifiedRow.classList.toggle('is-blue', isVerifiedBlue);
      verifiedRow.classList.toggle('is-green', !isVerifiedBlue && isVerifiedGreen);
      verifiedRow.classList.toggle('is-excellence', !isVerifiedBlue && !isVerifiedGreen && hasExcellenceBadges);
    }
    if (verifiedLabel) {
      verifiedLabel.textContent = labels.join(' • ');
    }
  }

  function _renderStats() {
    const p = _providerProfile || {};
    const stats = _providerStats || {};
    const followers = stats.followers_count ?? p.followers_count ?? _profile?.provider_followers_count ?? 0;
    const likes = stats.media_likes_count ?? stats.likes_count ?? p.likes_count ?? _profile?.provider_likes_received_count ?? _profile?.likes_count ?? 0;
    const clients = stats.total_clients ?? p.total_clients ?? 0;
    const favorites = stats.media_saves_count ?? _favoritesCount;

    _setText('stat-followers', '.pd-stat-val', followers);
    _setText('stat-likes', '.pd-stat-val', likes);
    _setText('stat-preference', '.pd-stat-val', favorites);
    _setText('stat-clients', '.pd-stat-val', clients);
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
    const titleNode = document.getElementById('plan-name');
    const metaNode = document.getElementById('plan-expiry');
    const descNode = document.getElementById('plan-description');
    const highlightsNode = document.getElementById('plan-highlights');
    const actionNode = document.getElementById('plan-action-link');
    if (!card || !titleNode || !metaNode || !descNode || !highlightsNode || !actionNode) return;

    if (subRes.status === 'fulfilled' && subRes.value.ok && subRes.value.data) {
      const subs = _extractList(subRes.value.data);
      const selected = _pickPreferredSubscription(subs);
      if (selected) {
        _activeSubscription = selected;
        card.style.display = '';
        card.classList.remove('is-unsubscribed');
        titleNode.textContent = _planTitle(selected);
        const statusCode = selected.provider_status_code || selected.status;
        const statusLabel = selected.provider_status_label || _statusLabel(statusCode);
        const metaParts = [`الحالة: ${statusLabel}`];
        const endRaw = selected.end_at || selected.end_date;
        if (endRaw) {
          const endDate = new Date(endRaw);
          if (!Number.isNaN(endDate.getTime())) {
            metaParts.push(`ينتهي: ${endDate.toLocaleDateString('ar-SA')}`);
          }
        }
        metaNode.textContent = metaParts.join(' • ');
        descNode.classList.add('hidden');
        descNode.textContent = '';
        highlightsNode.classList.add('hidden');
        highlightsNode.innerHTML = '';
        actionNode.href = '/plans/';
        actionNode.textContent = 'إدارة الباقات';
        _setSpotlightSubscriptionLock(false);
        _renderSpotlightQuotaNote();
        _renderCoverGalleryManager();
        return;
      }
    }

    _activeSubscription = null;

    card.style.display = '';
    card.classList.add('is-unsubscribed');
    titleNode.textContent = 'فعّل باقتك الأساسية المجانية';
    metaNode.textContent = 'حسابك حاليًا بدون اشتراك فعال، لذلك تعمل أدوات المزود بصلاحيات محدودة حتى التفعيل.';
    descNode.classList.remove('hidden');
    descNode.textContent = 'فعّل الباقة الأساسية المجانية الآن لتفتح أدوات الظهور والتوثيق والطلبات المخصصة للمزودين بشكل احترافي ومنظم.';
    highlightsNode.classList.remove('hidden');
    highlightsNode.innerHTML = [
      'الطلبات العاجلة والتنافسية متوقفة حتى تفعيل الاشتراك.',
      'رفع اللمحات وخلفيات الملف غير متاح قبل الاشتراك.',
      'رسائل التذكير للعملاء متوقفة حاليًا حتى تفعيل الباقة.',
      'طلب التوثيق يتطلب اشتراكًا فعالًا في الباقة الأساسية أو الأعلى.',
      'ستحتفظ بسعة التخزين المجانية الأساسية، والدعم يتم خلال 5 أيام عمل.',
    ].map((line) => `<li>${line}</li>`).join('');
    actionNode.href = _basicPlanActionUrl();
    actionNode.textContent = 'تفعيل الباقة الأساسية المجانية';
    _setSpotlightSubscriptionLock(true);
    _renderCoverGalleryManager();
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
    const pctEl = document.getElementById('completion-pct');
    const barEl = document.getElementById('completion-bar');
    const actionEl = document.getElementById('completion-action');
    if (pctEl) pctEl.textContent = `${pct}%`;
    if (barEl) barEl.style.width = `${pct}%`;
    if (actionEl) {
      if (pct >= 100) {
        actionEl.textContent = 'تعديل الملف';
        actionEl.setAttribute('href', '/provider-profile-edit/');
      } else {
        actionEl.textContent = 'أكمل ملفك - تعديل الملف';
        actionEl.setAttribute('href', '/provider-profile-edit/?tab=account&focus=fullName&section=basic');
      }
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
    _currentSpotlightCount = spots.length;
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
    _renderSpotlightQuotaNote();
  }

  async function _deleteSpotlight(id, el) {
    if (!confirm('هل تريد حذف هذا الفيديو؟')) return;
    const res = await ApiClient.request(`/api/providers/me/spotlights/${id}/`, { method: 'DELETE' });
    if (res.ok) {
      el.remove();
      _currentSpotlightCount = Math.max(0, _currentSpotlightCount - 1);
      _renderSpotlightQuotaNote();
    }
  }

  function _bindUploads() {
    // Cover upload
    var coverInput = document.getElementById('cover-upload');
    if (coverInput) {
      coverInput.addEventListener('change', async (e) => {
        await _uploadCoverFiles(e.target.files);
        e.target.value = '';
      });
    }

    // Avatar upload
    var avatarInput = document.getElementById('avatar-upload');
    if (avatarInput) {
      avatarInput.addEventListener('change', async (e) => {
        const file = e.target.files[0];
        if (!file) return;
        if (file.size > 20 * 1024 * 1024) {
          alert('حجم الصورة يجب ألا يتجاوز 20 ميغابايت');
          return;
        }
        const fd = new FormData();
        fd.append('profile_image', file);
        _setProfileMediaUploadState('avatar', true, 'جاري رفع الصورة الشخصية...');
        try {
          const res = await ApiClient.request('/api/providers/me/profile/', { method: 'PATCH', body: fd, formData: true });
          if (res.ok) {
            document.getElementById('pd-avatar').style.backgroundImage = `url('${URL.createObjectURL(file)}')`;
            if (typeof NwToast !== 'undefined') NwToast.success('تم تحديث الصورة الشخصية');
          } else {
            alert(_apiErrorMessage(res, 'تعذر رفع الصورة الشخصية'));
          }
        } catch (_) {
          alert('تعذر رفع الصورة الشخصية، حاول مرة أخرى');
        } finally {
          _setProfileMediaUploadState('avatar', false);
          e.target.value = '';
        }
      });
    }

    // Spotlight upload
    var spotlightInput = document.getElementById('spotlight-upload');
    var spotlightTrigger = document.getElementById('spotlight-upload-trigger');
    if (spotlightTrigger) {
      spotlightTrigger.addEventListener('click', (event) => {
        if (_spotlightQuotaUnavailable() || _spotlightQuotaReached()) {
          event.preventDefault();
          _showSpotlightUpgradeDialog({
            detail: _spotlightQuotaUnavailable()
              ? `رفع اللمحات غير متاح ضمن ${_spotlightPlanName()}. رقِّ الباقة لتفعيل هذه الميزة.`
              : `أكملت ${_currentSpotlightCount} من ${_spotlightQuota()} لمحات ضمن ${_spotlightPlanName()}. احذف لمحة حالية أو رقِّ الباقة لإضافة المزيد.`,
          });
        }
      });
    }
    if (spotlightInput) {
      spotlightInput.addEventListener('change', async (e) => {
        const file = e.target.files[0];
        if (!file) return;
        const fileType = _spotlightFileType(file);
        if (fileType !== 'video') {
          alert('يمكن رفع فيديو فقط في قسم الريلز والأضواء.');
          e.target.value = '';
          return;
        }
        if (_spotlightQuotaUnavailable() || _spotlightQuotaReached()) {
          e.target.value = '';
          _showSpotlightUpgradeDialog({
            detail: _spotlightQuotaUnavailable()
              ? `رفع اللمحات غير متاح ضمن ${_spotlightPlanName()}. رقِّ الباقة لتفعيل هذه الميزة.`
              : `أكملت ${_currentSpotlightCount} من ${_spotlightQuota()} لمحات ضمن ${_spotlightPlanName()}. احذف لمحة حالية أو رقِّ الباقة لإضافة المزيد.`,
          });
          return;
        }
        const fd = new FormData();
        fd.append('file', file);
        fd.append('file_type', fileType);
        const input = e.target;
        const previewUrl = URL.createObjectURL(file);
        let shouldResetUploadUi = true;
        let errorMessage = '';
        input.disabled = true;
        _setSpotlightUploadState(true, {
          previewUrl,
          label: 'جاري الرفع',
          statusText: 'جاري رفع الريل، سيظهر هنا تلقائيًا بعد اكتمال التحميل.',
        });
        try {
          const res = await ApiClient.request('/api/providers/me/spotlights/', { method: 'POST', body: fd, formData: true });
          if (res.ok) {
            shouldResetUploadUi = false;
            location.reload();
            return;
          }
          if (res?.data?.error_code === 'spotlight_quota_exceeded' || res?.data?.error_code === 'spotlight_quota_unavailable') {
            _showSpotlightUpgradeDialog(_spotlightQuotaPayloadFromResponse(res));
            errorMessage = '';
          } else {
            errorMessage = _apiErrorMessage(res, 'تعذر رفع الريلز الآن.');
          }
        } catch (_) {
          errorMessage = 'تعذر رفع الريلز الآن، حاول مرة أخرى.';
        } finally {
          input.disabled = false;
          input.value = '';
          if (shouldResetUploadUi) {
            _setSpotlightUploadState(false);
          }
        }
        if (errorMessage) {
          alert(errorMessage);
        }
      });
    }
  }

  function _bindModeToggle() {
    const clientBtn = document.getElementById('mode-client-btn');
    const provBtn = document.getElementById('mode-provider-btn');
    clientBtn.addEventListener('click', () => {
      if (window.Auth && typeof window.Auth.setActiveAccountMode === 'function') {
        window.Auth.setActiveAccountMode('client');
      } else {
        sessionStorage.setItem('nw_account_mode', 'client');
      }
      window.location.href = '/profile/';
    });
    provBtn.addEventListener('click', () => {
      if (window.Auth && typeof window.Auth.setActiveAccountMode === 'function') {
        window.Auth.setActiveAccountMode('provider');
      } else {
        sessionStorage.setItem('nw_account_mode', 'provider');
      }
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
          if (_providerProfile && _providerProfile.id) {
            await ApiClient.request('/api/providers/' + encodeURIComponent(String(_providerProfile.id)) + '/share/', {
              method: 'POST',
              body: { content_type: 'profile', channel: 'copy_link' },
            });
          }
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
              if (_providerProfile && _providerProfile.id) {
                await ApiClient.request('/api/providers/' + encodeURIComponent(String(_providerProfile.id)) + '/share/', {
                  method: 'POST',
                  body: { content_type: 'profile', channel: 'other' },
                });
              }
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
