/* ===================================================================
   homePage.js — Home page controller  v3.0
   1:1 mirror of Flutter home_screen.dart layout & behavior.
   Fetches same API endpoints:
     • GET /api/providers/categories/
     • GET /api/providers/list/?page_size=10
     • GET /api/promo/banners/home/?limit=6
     • GET /api/providers/spotlights/feed/?limit=16
   SWR caching, auto-scroll reels, SpotlightViewer on tap.
   =================================================================== */
'use strict';

const HomePage = (() => {
  // Cache keys & TTL
  const CACHE_CATEGORIES = 'home_categories';
  const CACHE_PROVIDERS  = 'home_providers';
  const CACHE_BANNERS    = 'home_banners';
  const CACHE_SPOTLIGHTS = 'home_spotlights';
  const TTL = 90; // seconds

  // DOM refs
  let $categoriesList, $providersList, $bannersList, $bannersSection;
  let $heroSubtitle, $reelsTrack, $offlineBanner;

  // State
  let _isLoading = false;
  let _reelsData = [];           // keep spotlight items for SpotlightViewer
  let _reelsAutoTimer = null;    // auto-scroll interval
  let _reelsPaused = false;      // pause while user is touching/dragging
  let _reelsBound = false;       // bind track interaction handlers once

  /* ----------------------------------------------------------
     INIT
  ---------------------------------------------------------- */
  function init() {
    $categoriesList = document.getElementById('categories-list');
    $providersList  = document.getElementById('providers-list');
    $bannersList    = document.getElementById('banners-list');
    $bannersSection = document.getElementById('banners');
    $heroSubtitle   = document.getElementById('hero-subtitle');
    $reelsTrack     = document.getElementById('reels-track');
    $offlineBanner  = document.getElementById('offline-banner');
    _bindReelsInteraction();

    // Network listener
    window.addEventListener('online',  () => _setOffline(false));
    window.addEventListener('offline', () => _setOffline(true));

    // Seed from cache (instant display)
    const seeded = _seedFromCache();

    // Fetch fresh data
    _loadData(!seeded);

    // Pull-to-refresh
    _initPullToRefresh();
  }

  /* ----------------------------------------------------------
     SEED FROM CACHE
  ---------------------------------------------------------- */
  function _seedFromCache() {
    let any = false;

    const cats = NwCache.get(CACHE_CATEGORIES);
    if (cats && cats.data && cats.data.length) {
      _renderCategories(cats.data);
      any = true;
    }

    const provs = NwCache.get(CACHE_PROVIDERS);
    if (provs && provs.data && provs.data.length) {
      _renderProviders(provs.data);
      any = true;
    }

    const bans = NwCache.get(CACHE_BANNERS);
    if (bans && bans.data && bans.data.length) {
      _renderBanners(bans.data);
      any = true;
    }

    const reels = NwCache.get(CACHE_SPOTLIGHTS);
    if (reels && reels.data && reels.data.length) {
      _reelsData = reels.data;
      _renderReels(reels.data);
      any = true;
    }

    return any;
  }

  /* ----------------------------------------------------------
     LOAD DATA (parallel API calls — same as Flutter)
  ---------------------------------------------------------- */
  async function _loadData(showSkeletons) {
    if (_isLoading) return;
    _isLoading = true;

    const [catsRes, provsRes, bansRes, reelsRes] = await Promise.allSettled([
      ApiClient.get('/api/providers/categories/'),
      ApiClient.get('/api/providers/list/?page_size=10'),
      ApiClient.get('/api/promo/banners/home/?limit=6'),
      ApiClient.get('/api/providers/spotlights/feed/?limit=16'),
    ]);

    // Categories
    if (catsRes.status === 'fulfilled' && catsRes.value.ok && catsRes.value.data) {
      const list = Array.isArray(catsRes.value.data)
        ? catsRes.value.data
        : (catsRes.value.data.results || []);
      NwCache.set(CACHE_CATEGORIES, list, TTL);
      _renderCategories(list);
    } else if (!NwCache.get(CACHE_CATEGORIES)) {
      _renderDefaultCategories();
    }

    // Providers
    if (provsRes.status === 'fulfilled' && provsRes.value.ok && provsRes.value.data) {
      const list = Array.isArray(provsRes.value.data)
        ? provsRes.value.data
        : (provsRes.value.data.results || []);
      NwCache.set(CACHE_PROVIDERS, list, TTL);
      _renderProviders(list);
      _updateSubtitle(list.length);
    } else if (!NwCache.get(CACHE_PROVIDERS)) {
      _renderProvidersEmpty();
    }

    // Banners
    if (bansRes.status === 'fulfilled' && bansRes.value.ok && bansRes.value.data) {
      const list = Array.isArray(bansRes.value.data)
        ? bansRes.value.data
        : [];
      NwCache.set(CACHE_BANNERS, list, TTL);
      _renderBanners(list);
    }

    // Spotlights (reels)
    if (reelsRes.status === 'fulfilled' && reelsRes.value.ok && reelsRes.value.data) {
      const list = Array.isArray(reelsRes.value.data)
        ? reelsRes.value.data
        : (reelsRes.value.data.results || []);
      NwCache.set(CACHE_SPOTLIGHTS, list, TTL);
      if (list.length) {
        _reelsData = list;
        _renderReels(list);
      } else {
        _renderReelsEmpty();
      }
    } else if (!NwCache.get(CACHE_SPOTLIGHTS)) {
      _renderReelsEmpty();
    }

    // Offline detection
    const allFailed = [catsRes, provsRes, bansRes, reelsRes].every(
      r => r.status === 'rejected' || (r.status === 'fulfilled' && !r.value.ok)
    );
    if (allFailed && !navigator.onLine) _setOffline(true);

    _isLoading = false;
  }

  /* ----------------------------------------------------------
     RENDER: CATEGORIES
     Flutter: horizontal ListView, 76px wide, 50×50 icon, name below
  ---------------------------------------------------------- */
  function _renderCategories(categories) {
    if (!$categoriesList) return;
    const frag = document.createDocumentFragment();
    categories.forEach(cat => {
      const iconKey = UI.categoryIconKey(cat.name);
      const categoryUrl = cat.id ? '/search/?category=' + encodeURIComponent(String(cat.id)) : '/search/';
      const item = UI.el('div', { className: 'cat-item' }, [
        UI.el('div', { className: 'cat-icon' }, [UI.icon(iconKey, 22, '#673AB7')]),
        UI.el('div', { className: 'cat-name', textContent: cat.name }),
      ]);
      item.setAttribute('role', 'button');
      item.setAttribute('tabindex', '0');
      item.addEventListener('click', () => { window.location.href = categoryUrl; });
      item.addEventListener('keydown', e => {
        if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); window.location.href = categoryUrl; }
      });
      frag.appendChild(item);
    });
    $categoriesList.textContent = '';
    $categoriesList.appendChild(frag);
  }

  function _renderDefaultCategories() {
    _renderCategories([
      { id: 0, name: 'استشارات قانونية' },
      { id: 0, name: 'خدمات هندسية' },
      { id: 0, name: 'تصميم جرافيك' },
      { id: 0, name: 'توصيل سريع' },
      { id: 0, name: 'رعاية صحية' },
      { id: 0, name: 'ترجمة لغات' },
      { id: 0, name: 'برمجة مواقع' },
      { id: 0, name: 'صيانة أجهزة' },
    ]);
  }

  /* ----------------------------------------------------------
     RENDER: PROVIDERS
     Flutter: horizontal ListView, 150px wide, cover 70px,
     avatar(32px)+name+verified row, city, stats row
  ---------------------------------------------------------- */
  function _renderProviders(providers) {
    if (!$providersList) return;
    if (!providers.length) { _renderProvidersEmpty(); return; }

    const frag = document.createDocumentFragment();
    providers.forEach(p => {
      const profileUrl = ApiClient.mediaUrl(p.profile_image);
      const coverUrl = ApiClient.mediaUrl(p.cover_image);
      const displayName = (p.display_name || '').trim() || 'مقدم خدمة';
      const initial = displayName.charAt(0) || '؟';
      const providerHref = p.id ? '/provider/' + encodeURIComponent(String(p.id)) + '/' : '/search/';

      const card = UI.el('a', { className: 'provider-card', href: providerHref });

      // Cover
      const cover = UI.el('div', { className: 'provider-cover' });
      if (coverUrl) cover.appendChild(UI.lazyImg(coverUrl, displayName));
      card.appendChild(cover);

      // Info section: avatar + name + verification + rating
      const info = UI.el('div', { className: 'provider-info' });
      const head = UI.el('div', { className: 'provider-head' });

      const avatar = UI.el('div', { className: 'provider-avatar' });
      if (profileUrl) {
        avatar.appendChild(UI.lazyImg(profileUrl, initial));
      } else {
        avatar.appendChild(UI.text(initial));
      }
      head.appendChild(avatar);

      const meta = UI.el('div', { className: 'provider-meta' });

      const nameRow = UI.el('div', { className: 'provider-name-row' });
      nameRow.appendChild(UI.el('span', { className: 'provider-name', textContent: displayName }));
      meta.appendChild(nameRow);

      const isVerified = !!(p.is_verified_blue || p.is_verified_green || p.is_verified);
      if (isVerified) {
        const badgeClass = p.is_verified_blue
          ? 'provider-verified-badge is-blue'
          : 'provider-verified-badge is-green';
        const badge = UI.el('span', { className: badgeClass });
        badge.appendChild(
          p.is_verified_blue
            ? UI.icon('verified_blue', 12, '#2196F3')
            : UI.icon('verified_green', 12, '#4CAF50')
        );
        badge.appendChild(UI.text('موثّق'));
        meta.appendChild(badge);
      }

      head.appendChild(meta);
      info.appendChild(head);

      const stats = UI.el('div', { className: 'provider-stats' });
      stats.appendChild(_ratingBadge(_ratingText(p)));
      info.appendChild(stats);

      card.appendChild(info);
      frag.appendChild(card);
    });
    $providersList.textContent = '';
    $providersList.appendChild(frag);
  }

  function _ratingText(provider) {
    const n = Number(provider?.rating_avg ?? provider?.rating ?? provider?.average_rating);
    if (Number.isFinite(n) && n > 0) return n.toFixed(1);
    return '0.0';
  }

  function _ratingBadge(value) {
    return UI.el('span', { className: 'provider-stat rating' }, [
      UI.icon('star', 12, '#FFC107'),
      UI.text(' ' + value),
    ]);
  }

  function _renderProvidersEmpty() {
    if (!$providersList) return;
    $providersList.textContent = '';
    $providersList.appendChild(
      UI.el('div', { className: 'providers-empty' }, [
        UI.icon('info', 20, '#ddd'),
        UI.el('span', { textContent: 'لا يوجد مزودو خدمة حالياً' }),
      ])
    );
  }

  /* ----------------------------------------------------------
     RENDER: BANNERS
     Flutter: horizontal ListView, 220×130, image+gradient+caption
  ---------------------------------------------------------- */
  function _renderBanners(banners) {
    if (!$bannersList || !$bannersSection) return;
    if (!banners.length) { $bannersSection.style.display = 'none'; return; }
    $bannersSection.style.display = '';

    const frag = document.createDocumentFragment();
    banners.forEach(b => {
      const url = ApiClient.mediaUrl(b.file_url);
      const providerId = parseInt(b.provider_id, 10);
      const hasProvider = Number.isFinite(providerId) && providerId > 0;
      const card = hasProvider
        ? UI.el('a', { className: 'banner-card', href: '/provider/' + providerId + '/' })
        : UI.el('div', { className: 'banner-card' });

      if (url) card.appendChild(UI.lazyImg(url, b.caption || ''));

      if (b.caption || b.provider_display_name) {
        const overlay = UI.el('div', { className: 'banner-overlay' });
        if (b.caption) overlay.appendChild(UI.el('div', { className: 'banner-caption', textContent: b.caption }));
        if (b.provider_display_name) overlay.appendChild(UI.el('div', { className: 'banner-provider', textContent: b.provider_display_name }));
        card.appendChild(overlay);
      }
      frag.appendChild(card);
    });
    $bannersList.textContent = '';
    $bannersList.appendChild(frag);
  }

  /* ----------------------------------------------------------
     RENDER: REELS / SPOTLIGHTS
     Flutter: horizontal ListView 108px, auto-scroll timer,
     conic-gradient ring (78px), tap → SpotlightViewerPage
  ---------------------------------------------------------- */
  function _renderReels(items) {
    if (!$reelsTrack) return;
    // Stop existing auto-scroll
    _stopAutoScroll();

    const frag = document.createDocumentFragment();

    items.forEach((item, idx) => {
      const thumb = ApiClient.mediaUrl(item.thumbnail_url || item.file_url || '');
      const caption = (item.caption || '').trim() || 'لمحة';

      // Always a div — click opens SpotlightViewer, NOT provider page
      const reel = UI.el('div', {
        className: 'reel-item',
        role: 'button',
        tabindex: '0',
      });

      const ring = UI.el('div', { className: 'reel-ring' });
      const inner = UI.el('div', { className: 'reel-inner' });

      if (thumb) {
        inner.appendChild(UI.lazyImg(thumb, caption));
      } else {
        inner.appendChild(UI.el('div', { className: 'reel-placeholder' }));
      }

      ring.appendChild(inner);
      reel.appendChild(ring);
      reel.appendChild(UI.el('div', { className: 'reel-caption', textContent: caption }));

      // Click → open SpotlightViewer at this index
      reel.addEventListener('click', () => {
        if (typeof SpotlightViewer !== 'undefined') {
          SpotlightViewer.open(_reelsData, idx);
        }
      });
      reel.addEventListener('keydown', e => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          if (typeof SpotlightViewer !== 'undefined') {
            SpotlightViewer.open(_reelsData, idx);
          }
        }
      });

      frag.appendChild(reel);
    });

    $reelsTrack.textContent = '';
    $reelsTrack.appendChild(frag);

    // Start auto-scroll (mirrors Flutter Timer.periodic)
    _startAutoScroll();
  }

  function _renderReelsEmpty() {
    if (!$reelsTrack) return;
    _stopAutoScroll();
    $reelsTrack.textContent = '';
    $reelsTrack.appendChild(
      UI.el('div', { className: 'reels-empty', textContent: 'لا توجد لمحات حالياً' })
    );
  }

  /* ----------------------------------------------------------
     REELS AUTO-SCROLL (mirrors Flutter Timer.periodic)
     Scrolls continuously with small steps and loops to start.
   ---------------------------------------------------------- */
  function _bindReelsInteraction() {
    if (!$reelsTrack || _reelsBound) return;
    _reelsBound = true;

    const pause = () => { _reelsPaused = true; };
    const resume = () => { _reelsPaused = false; };

    $reelsTrack.addEventListener('pointerdown', pause, { passive: true });
    $reelsTrack.addEventListener('pointerup', resume, { passive: true });
    $reelsTrack.addEventListener('pointercancel', resume, { passive: true });
    $reelsTrack.addEventListener('mouseleave', resume, { passive: true });
  }

  function _startAutoScroll() {
    if (!$reelsTrack) return;
    _reelsPaused = false;

    _reelsAutoTimer = setInterval(() => {
      if (_reelsPaused || !$reelsTrack) return;
      const maxScroll = $reelsTrack.scrollWidth - $reelsTrack.clientWidth;
      if (maxScroll <= 0) return;
      const next = $reelsTrack.scrollLeft + 1;
      $reelsTrack.scrollLeft = next >= maxScroll ? 0 : next;
    }, 50);
  }

  function _stopAutoScroll() {
    if (_reelsAutoTimer) {
      clearInterval(_reelsAutoTimer);
      _reelsAutoTimer = null;
    }
  }

  /* ----------------------------------------------------------
     HELPERS
  ---------------------------------------------------------- */
  function _updateSubtitle(count) {
    if (!$heroSubtitle) return;
    const num = count > 0 ? count : '100';
    $heroSubtitle.textContent = 'أكثر من ' + num + ' مقدم خدمة بين يديك';
  }

  function _setOffline(offline) {
    if (!$offlineBanner) return;
    $offlineBanner.style.display = offline ? 'flex' : 'none';
  }

  /* ----------------------------------------------------------
     PULL-TO-REFRESH
  ---------------------------------------------------------- */
  function _initPullToRefresh() {
    let startY = 0;
    let pulling = false;

    window.addEventListener('touchstart', e => {
      if (window.scrollY <= 0) { startY = e.touches[0].clientY; pulling = true; }
    }, { passive: true });

    window.addEventListener('touchmove', e => {
      if (!pulling) return;
      const dy = e.touches[0].clientY - startY;
      if (dy > 80 && !_isLoading) { pulling = false; _loadData(false); }
    }, { passive: true });

    window.addEventListener('touchend', () => { pulling = false; }, { passive: true });
  }

  /* ----------------------------------------------------------
     BOOT
  ---------------------------------------------------------- */
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  return { refresh: () => _loadData(false) };
})();
