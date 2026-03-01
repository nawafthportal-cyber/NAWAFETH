/* ===================================================================
   homePage.js — Home page controller
   Fetches data from the SAME API endpoints as the Flutter app:
     • GET /api/providers/categories/
     • GET /api/providers/list/?page_size=10
     • GET /api/promo/banners/home/?limit=6
   Implements Stale-While-Revalidate caching strategy.
   =================================================================== */
'use strict';

const HomePage = (() => {
  // Cache keys & TTLs
  const CACHE_CATEGORIES = 'home_categories';
  const CACHE_PROVIDERS  = 'home_providers';
  const CACHE_BANNERS    = 'home_banners';
  const TTL = 90; // seconds

  // DOM refs (resolved once)
  let $categoriesList, $providersList, $bannersList, $bannersSection;
  let $heroSubtitle, $reelsTrack, $offlineBanner;

  // State
  let _isLoading = false;

  /* ----------------------------------------------------------
     INIT
  ---------------------------------------------------------- */
  function init() {
    // Resolve DOM
    $categoriesList = document.getElementById('categories-list');
    $providersList  = document.getElementById('providers-list');
    $bannersList    = document.getElementById('banners-list');
    $bannersSection = document.getElementById('banners');
    $heroSubtitle   = document.getElementById('hero-subtitle');
    $reelsTrack     = document.getElementById('reels-track');
    $offlineBanner  = document.getElementById('offline-banner');

    // Build static reels
    _buildReels();

    // Network listener
    window.addEventListener('online',  () => _setOffline(false));
    window.addEventListener('offline', () => _setOffline(true));

    // Seed from cache first (instant display)
    const seeded = _seedFromCache();

    // Then fetch fresh data
    _loadData(!seeded);

    // Pull-to-refresh via app-shell scroll
    _initPullToRefresh();
  }

  /* ----------------------------------------------------------
     SEED FROM CACHE (instant render)
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

    return any;
  }

  /* ----------------------------------------------------------
     LOAD DATA (parallel API calls)
  ---------------------------------------------------------- */
  async function _loadData(showSkeletons) {
    if (_isLoading) return;
    _isLoading = true;

    // Fire all 3 requests in parallel
    const [catsRes, provsRes, bansRes] = await Promise.allSettled([
      ApiClient.get('/api/providers/categories/'),
      ApiClient.get('/api/providers/list/?page_size=10'),
      ApiClient.get('/api/promo/banners/home/?limit=6'),
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

    // Check if all failed (offline)
    const allFailed = [catsRes, provsRes, bansRes].every(
      r => r.status === 'rejected' || (r.status === 'fulfilled' && !r.value.ok)
    );
    if (allFailed && !navigator.onLine) {
      _setOffline(true);
    }

    _isLoading = false;
  }

  /* ----------------------------------------------------------
     RENDER: CATEGORIES
  ---------------------------------------------------------- */
  function _renderCategories(categories) {
    if (!$categoriesList) return;
    // Use DocumentFragment to minimize reflows
    const frag = document.createDocumentFragment();
    categories.forEach(cat => {
      const iconKey = UI.categoryIconKey(cat.name);
      const item = UI.el('div', { className: 'cat-item' }, [
        UI.el('div', { className: 'cat-icon' }, [UI.icon(iconKey, 22, '#673AB7')]),
        UI.el('div', { className: 'cat-name', textContent: cat.name }),
      ]);
      item.setAttribute('role', 'button');
      item.setAttribute('tabindex', '0');
      frag.appendChild(item);
    });
    $categoriesList.textContent = ''; // clear skeletons
    $categoriesList.appendChild(frag);
  }

  function _renderDefaultCategories() {
    const defaults = [
      { id: 0, name: 'استشارات قانونية' },
      { id: 0, name: 'خدمات هندسية' },
      { id: 0, name: 'تصميم جرافيك' },
      { id: 0, name: 'توصيل سريع' },
      { id: 0, name: 'رعاية صحية' },
      { id: 0, name: 'ترجمة لغات' },
      { id: 0, name: 'برمجة مواقع' },
      { id: 0, name: 'صيانة أجهزة' },
    ];
    _renderCategories(defaults);
  }

  /* ----------------------------------------------------------
     RENDER: PROVIDERS
  ---------------------------------------------------------- */
  function _renderProviders(providers) {
    if (!$providersList) return;
    if (!providers.length) { _renderProvidersEmpty(); return; }

    const frag = document.createDocumentFragment();
    providers.forEach(p => {
      const profileUrl = ApiClient.mediaUrl(p.profile_image);
      const coverUrl = ApiClient.mediaUrl(p.cover_image);
      const displayName = p.display_name || '';
      const initial = displayName.charAt(0) || '؟';

      // Card
      const card = UI.el('div', { className: 'provider-card' });

      // Cover
      const cover = UI.el('div', { className: 'provider-cover' });
      if (coverUrl) {
        cover.appendChild(UI.lazyImg(coverUrl, displayName));
      }
      card.appendChild(cover);

      // Info row
      const info = UI.el('div', { className: 'provider-info' });

      // Avatar
      const avatar = UI.el('div', { className: 'provider-avatar' });
      if (profileUrl) {
        avatar.appendChild(UI.lazyImg(profileUrl, initial));
      } else {
        avatar.appendChild(UI.text(initial));
      }
      info.appendChild(avatar);

      // Meta
      const meta = UI.el('div', { className: 'provider-meta' });

      // Name row
      const nameRow = UI.el('div', { className: 'provider-name-row' });
      nameRow.appendChild(UI.el('span', { className: 'provider-name', textContent: displayName }));
      if (p.is_verified_blue) {
        nameRow.appendChild(UI.icon('verified_blue', 11, '#2196F3'));
      } else if (p.is_verified_green) {
        nameRow.appendChild(UI.icon('verified_green', 11, '#4CAF50'));
      }
      meta.appendChild(nameRow);

      if (p.city) {
        meta.appendChild(UI.el('div', { className: 'provider-city', textContent: p.city }));
      }
      info.appendChild(meta);
      card.appendChild(info);

      // Stats
      const stats = UI.el('div', { className: 'provider-stats' });
      const rating = p.rating_avg > 0 ? parseFloat(p.rating_avg).toFixed(1) : '-';
      stats.appendChild(_statBadge('star', rating, '#FFC107'));
      stats.appendChild(_statBadge('people', String(p.followers_count || 0), '#999'));
      stats.appendChild(_statBadge('heart', String(p.likes_count || 0), '#999'));
      card.appendChild(stats);

      frag.appendChild(card);
    });
    $providersList.textContent = '';
    $providersList.appendChild(frag);
  }

  function _statBadge(iconName, value, color) {
    const cls = iconName === 'star' ? 'provider-stat rating' : 'provider-stat';
    return UI.el('span', { className: cls }, [
      UI.icon(iconName, 11, color),
      UI.text(' ' + value),
    ]);
  }

  function _renderProvidersEmpty() {
    if (!$providersList) return;
    $providersList.textContent = '';
    const empty = UI.el('div', { className: 'providers-empty' }, [
      UI.icon('info', 20, '#ddd'),
      UI.el('span', { textContent: 'لا يوجد مزودو خدمة حالياً' }),
    ]);
    $providersList.appendChild(empty);
  }

  /* ----------------------------------------------------------
     RENDER: BANNERS
  ---------------------------------------------------------- */
  function _renderBanners(banners) {
    if (!$bannersList || !$bannersSection) return;
    if (!banners.length) {
      $bannersSection.style.display = 'none';
      return;
    }
    $bannersSection.style.display = '';

    const frag = document.createDocumentFragment();
    banners.forEach(b => {
      const url = ApiClient.mediaUrl(b.file_url);
      const card = UI.el('div', { className: 'banner-card' });

      if (url) {
        card.appendChild(UI.lazyImg(url, b.caption || ''));
      }

      // Overlay text
      if (b.caption || b.provider_display_name) {
        const overlay = UI.el('div', { className: 'banner-overlay' });
        if (b.caption) {
          overlay.appendChild(UI.el('div', { className: 'banner-caption', textContent: b.caption }));
        }
        if (b.provider_display_name) {
          overlay.appendChild(UI.el('div', { className: 'banner-provider', textContent: b.provider_display_name }));
        }
        card.appendChild(overlay);
      }

      frag.appendChild(card);
    });
    $bannersList.textContent = '';
    $bannersList.appendChild(frag);
  }

  /* ----------------------------------------------------------
     REELS (static — local demo items, matching Flutter)
  ---------------------------------------------------------- */
  function _buildReels() {
    if (!$reelsTrack) return;
    // Since reels use local assets in the mobile app, we render placeholder circles
    // that match the gradient ring aesthetic. Can be replaced with real API data later.
    const colors = ['#9F57DB', '#F1A559', '#7E57C2', '#CE93D8', '#B39DDB'];
    const frag = document.createDocumentFragment();

    // Double items for infinite scroll illusion
    for (let i = 0; i < 16; i++) {
      const c = colors[i % colors.length];
      const item = UI.el('div', { className: 'reel-item' });
      const ring = UI.el('div', { className: 'reel-ring' });
      const inner = UI.el('div', { className: 'reel-inner' });

      // Placeholder with icon
      const ph = UI.el('div', { className: 'reel-placeholder' });
      ph.style.background = `linear-gradient(135deg, ${c}, ${colors[(i + 2) % colors.length]})`;
      const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
      svg.setAttribute('width', '20');
      svg.setAttribute('height', '20');
      svg.setAttribute('viewBox', '0 0 24 24');
      svg.setAttribute('fill', 'rgba(255,255,255,0.6)');
      svg.innerHTML = '<path d="M8 5v14l11-7z"/>';
      ph.appendChild(svg);
      inner.appendChild(ph);

      ring.appendChild(inner);
      item.appendChild(ring);
      frag.appendChild(item);
    }
    $reelsTrack.appendChild(frag);
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
     PULL-TO-REFRESH (simple imperative approach)
  ---------------------------------------------------------- */
  function _initPullToRefresh() {
    const shell = document.getElementById('app-shell');
    if (!shell) return;

    let startY = 0;
    let pulling = false;

    shell.addEventListener('touchstart', e => {
      if (shell.scrollTop <= 0) {
        startY = e.touches[0].clientY;
        pulling = true;
      }
    }, { passive: true });

    shell.addEventListener('touchmove', e => {
      if (!pulling) return;
      const dy = e.touches[0].clientY - startY;
      if (dy > 80 && !_isLoading) {
        pulling = false;
        _loadData(false);
      }
    }, { passive: true });

    shell.addEventListener('touchend', () => { pulling = false; }, { passive: true });
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
