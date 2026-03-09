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
  let $heroTitle, $heroSubtitle, $searchPlaceholder, $categoriesTitle, $providersTitle, $bannersTitle, $reelsTrack, $offlineBanner;
  let $carouselTrack, $carouselDots, $carouselPrev, $carouselNext;

  // State
  let _isLoading = false;
  let _reelsData = [];           // keep spotlight items for SpotlightViewer
  let _reelsAutoTimer = null;    // auto-scroll interval
  let _reelsPaused = false;      // pause while user is touching/dragging
  let _reelsBound = false;       // bind track interaction handlers once
  let _carouselItems = [];       // carousel banner data
  let _carouselIdx = 0;          // current slide index
  let _carouselTimer = null;     // auto-rotate timer
  let _carouselPaused = false;   // pause on interaction
  let _featuredProviderIds = new Set(); // IDs of featured (paid) providers
  let _popupShown = false;       // only show popup once per session
  let _homeContent = {
    heroTitle: '',
    heroSubtitle: '',
    searchPlaceholder: '',
    categoriesTitle: '',
    providersTitle: '',
    bannersTitle: '',
  };

  /* ----------------------------------------------------------
     INIT
  ---------------------------------------------------------- */
  function init() {
    $categoriesList = document.getElementById('categories-list');
    $providersList  = document.getElementById('providers-list');
    $bannersList    = document.getElementById('carousel-track');
    $bannersSection = document.getElementById('banners');
    $heroTitle      = document.getElementById('hero-title');
    $heroSubtitle   = document.getElementById('hero-subtitle');
    $searchPlaceholder = document.getElementById('home-search-placeholder');
    $categoriesTitle = document.getElementById('categories-title');
    $providersTitle = document.getElementById('providers-title');
    $bannersTitle = document.getElementById('banners-title');
    $reelsTrack     = document.getElementById('reels-track');
    $offlineBanner  = document.getElementById('offline-banner');
    $carouselTrack  = document.getElementById('carousel-track');
    $carouselDots   = document.getElementById('carousel-dots');
    $carouselPrev   = document.getElementById('carousel-prev');
    $carouselNext   = document.getElementById('carousel-next');
    _bindReelsInteraction();
    _applyHomeContent();

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

    const [contentRes, catsRes, provsRes, bansRes, reelsRes, featuredRes, popupRes] = await Promise.allSettled([
      ApiClient.get('/api/content/public/'),
      ApiClient.get('/api/providers/categories/'),
      ApiClient.get('/api/providers/list/?page_size=10'),
      ApiClient.get('/api/promo/home-carousel/?limit=10'),
      ApiClient.get('/api/providers/spotlights/feed/?limit=16'),
      ApiClient.get('/api/promo/active/?ad_type=featured_top5&limit=10'),
      ApiClient.get('/api/promo/active/?ad_type=popup_home&limit=1'),
    ]);

    if (contentRes.status === 'fulfilled' && contentRes.value.ok && contentRes.value.data) {
      const blocks = contentRes.value.data.blocks || {};
      _homeContent = {
        heroTitle: _resolveBlockTitle(blocks.home_hero_title, 'الرئيسية'),
        heroSubtitle: _resolveBlockTitle(blocks.home_hero_subtitle, 'مزودون موثّقون وخدمات مرتبة لتبدأ بشكل أسرع وأكثر وضوحًا.'),
        searchPlaceholder: _resolveBlockTitle(blocks.home_search_placeholder, 'ابحث'),
        categoriesTitle: _resolveBlockTitle(blocks.home_categories_title, 'التصنيفات'),
        providersTitle: _resolveBlockTitle(blocks.home_providers_title, 'مقدمو الخدمة'),
        bannersTitle: _resolveBlockTitle(blocks.home_banners_title, 'عروض ترويجية'),
      };
      _applyHomeContent();
    }

    // Categories
    if (catsRes.status === 'fulfilled' && catsRes.value.ok && catsRes.value.data) {
      const list = Array.isArray(catsRes.value.data)
        ? catsRes.value.data
        : (catsRes.value.data.results || []);
      NwCache.set(CACHE_CATEGORIES, list, TTL);
      _renderCategories(list);
    } else if (!NwCache.get(CACHE_CATEGORIES)) {
      _renderCategoriesEmpty();
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

    // Featured providers (paid promotion — boost to top)
    if (featuredRes.status === 'fulfilled' && featuredRes.value.ok && featuredRes.value.data) {
      const list = Array.isArray(featuredRes.value.data) ? featuredRes.value.data : [];
      _featuredProviderIds = new Set();
      list.forEach(promo => {
        if (promo.target_provider_id) _featuredProviderIds.add(promo.target_provider_id);
      });
    }

    // Popup promo (home)
    if (!_popupShown && popupRes.status === 'fulfilled' && popupRes.value.ok && popupRes.value.data) {
      const list = Array.isArray(popupRes.value.data) ? popupRes.value.data : [];
      if (list.length > 0) {
        _popupShown = true;
        _showPromoPopup(list[0]);
      }
    }

    // Offline detection
    const allFailed = [contentRes, catsRes, provsRes, bansRes, reelsRes].every(
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

  function _renderCategoriesEmpty() {
    if (!$categoriesList) return;
    $categoriesList.textContent = '';
    $categoriesList.appendChild(
      UI.el('div', { className: 'providers-empty', textContent: 'لا توجد تصنيفات متاحة حالياً' })
    );
  }

  /* ----------------------------------------------------------
     RENDER: PROVIDERS
     Home cards: avatar-first compact layout (no cover background)
   ---------------------------------------------------------- */
  function _renderProviders(providers) {
    if (!$providersList) return;
    if (!providers.length) { _renderProvidersEmpty(); return; }

    // Sort: featured (paid) providers first
    const sorted = [...providers].sort((a, b) => {
      const aFeat = _featuredProviderIds.has(a.id) ? 0 : 1;
      const bFeat = _featuredProviderIds.has(b.id) ? 0 : 1;
      return aFeat - bFeat;
    });

    const frag = document.createDocumentFragment();
    sorted.forEach(p => {
      const profileUrl = ApiClient.mediaUrl(p.profile_image);
      const displayName = (p.display_name || '').trim() || 'مقدم خدمة';
      const initial = displayName.charAt(0) || '؟';
      const providerHref = p.id ? '/provider/' + encodeURIComponent(String(p.id)) + '/' : '/search/';
      const isFeatured = _featuredProviderIds.has(p.id);

      const card = UI.el('a', { className: 'provider-card no-cover' + (isFeatured ? ' promo-featured' : ''), href: providerHref });

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
      if (isFeatured) {
        nameRow.appendChild(UI.el('span', { className: 'promo-featured-badge', textContent: 'مميز' }));
      }
      meta.appendChild(nameRow);

      const excellence = UI.buildExcellenceBadges(p.excellence_badges, {
        className: 'excellence-badges compact provider-card-excellence',
        compact: true,
        iconSize: 10,
      });
      if (excellence) meta.appendChild(excellence);

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
     RENDER: BANNERS CAROUSEL
     Full-width auto-rotating carousel with images & videos.
     Auto-rotates every 2 seconds. Supports swipe on mobile.
  ---------------------------------------------------------- */
  function _renderBanners(banners) {
    if (!$carouselTrack || !$bannersSection) return;
    if (!banners.length) { $bannersSection.style.display = 'none'; return; }
    $bannersSection.style.display = '';

    _carouselItems = banners;
    _carouselIdx = 0;

    // Build slides
    const frag = document.createDocumentFragment();
    banners.forEach((b, i) => {
      const slide = UI.el('div', { className: 'carousel-slide' + (i === 0 ? ' active' : '') });
      slide.setAttribute('data-index', String(i));

      const url = ApiClient.mediaUrl(b.media_url);
      const isVideo = (b.media_type || '').toLowerCase() === 'video';

      if (isVideo && url) {
        const vid = UI.el('video', {
          className: 'carousel-media',
          src: url,
          autoplay: false,
          muted: true,
          loop: true,
          playsInline: true,
          preload: 'metadata',
        });
        vid.setAttribute('playsinline', '');
        slide.appendChild(vid);
      } else if (url) {
        const img = UI.el('img', {
          className: 'carousel-media',
          loading: 'lazy',
          alt: b.title || '',
        });
        img.src = url;
        slide.appendChild(img);
      }

      // Overlay with title & provider
      const overlay = UI.el('div', { className: 'carousel-overlay' });
      if (b.title) overlay.appendChild(UI.el('div', { className: 'carousel-caption', textContent: b.title }));
      if (b.provider_display_name) overlay.appendChild(UI.el('div', { className: 'carousel-provider', textContent: b.provider_display_name }));
      slide.appendChild(overlay);

      // Link wrapper
      if (b.link_url) {
        slide.style.cursor = 'pointer';
        slide.addEventListener('click', () => { window.open(b.link_url, '_blank', 'noopener'); });
      } else if (b.provider_id && b.provider_id > 0) {
        slide.style.cursor = 'pointer';
        slide.addEventListener('click', () => { window.location.href = '/provider/' + b.provider_id + '/'; });
      }

      frag.appendChild(slide);
    });
    $carouselTrack.textContent = '';
    $carouselTrack.appendChild(frag);

    // Build dots
    if ($carouselDots) {
      $carouselDots.textContent = '';
      banners.forEach((_, i) => {
        const dot = UI.el('button', { className: 'carousel-dot' + (i === 0 ? ' active' : '') });
        dot.setAttribute('aria-label', 'شريحة ' + (i + 1));
        dot.addEventListener('click', () => _goToSlide(i));
        $carouselDots.appendChild(dot);
      });
    }

    // Arrow bindings
    if ($carouselPrev) $carouselPrev.onclick = () => _goToSlide((_carouselIdx - 1 + banners.length) % banners.length);
    if ($carouselNext) $carouselNext.onclick = () => _goToSlide((_carouselIdx + 1) % banners.length);

    // Show/hide arrows for single item
    if (banners.length <= 1) {
      if ($carouselPrev) $carouselPrev.style.display = 'none';
      if ($carouselNext) $carouselNext.style.display = 'none';
      if ($carouselDots) $carouselDots.style.display = 'none';
    }

    // Swipe support
    _bindCarouselSwipe();

    // Start auto-rotate
    _startCarouselAutoRotate();
  }

  function _goToSlide(idx) {
    if (!_carouselItems.length) return;
    const slides = $carouselTrack.querySelectorAll('.carousel-slide');
    const dots = $carouselDots ? $carouselDots.querySelectorAll('.carousel-dot') : [];

    // Pause current video
    const currentSlide = slides[_carouselIdx];
    if (currentSlide) {
      const vid = currentSlide.querySelector('video');
      if (vid) vid.pause();
      currentSlide.classList.remove('active');
    }
    if (dots[_carouselIdx]) dots[_carouselIdx].classList.remove('active');

    _carouselIdx = idx;

    // Activate new slide
    const newSlide = slides[_carouselIdx];
    if (newSlide) {
      newSlide.classList.add('active');
      const vid = newSlide.querySelector('video');
      if (vid) { vid.currentTime = 0; vid.play().catch(() => {}); }
    }
    if (dots[_carouselIdx]) dots[_carouselIdx].classList.add('active');
  }

  function _startCarouselAutoRotate() {
    _stopCarouselAutoRotate();
    if (_carouselItems.length <= 1) return;
    _carouselTimer = setInterval(() => {
      if (_carouselPaused) return;
      _goToSlide((_carouselIdx + 1) % _carouselItems.length);
    }, 2000);
  }

  function _stopCarouselAutoRotate() {
    if (_carouselTimer) { clearInterval(_carouselTimer); _carouselTimer = null; }
  }

  function _bindCarouselSwipe() {
    if (!$carouselTrack) return;
    let startX = 0;
    let dragging = false;

    $carouselTrack.addEventListener('pointerdown', e => {
      startX = e.clientX;
      dragging = true;
      _carouselPaused = true;
    }, { passive: true });

    $carouselTrack.addEventListener('pointerup', e => {
      if (!dragging) return;
      dragging = false;
      const dx = e.clientX - startX;
      // RTL: swipe left = prev, swipe right = next
      if (Math.abs(dx) > 40) {
        if (dx > 0) {
          _goToSlide((_carouselIdx + 1) % _carouselItems.length);
        } else {
          _goToSlide((_carouselIdx - 1 + _carouselItems.length) % _carouselItems.length);
        }
      }
      setTimeout(() => { _carouselPaused = false; }, 3000);
    }, { passive: true });

    $carouselTrack.addEventListener('pointercancel', () => {
      dragging = false;
      _carouselPaused = false;
    }, { passive: true });

    // Pause on hover (desktop)
    $carouselTrack.addEventListener('mouseenter', () => { _carouselPaused = true; });
    $carouselTrack.addEventListener('mouseleave', () => { _carouselPaused = false; });
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
    if ($heroTitle) $heroTitle.textContent = _homeContent.heroTitle || 'الرئيسية';
    if (!$heroSubtitle) return;
    const value = String(_homeContent.heroSubtitle || '').trim();
    $heroSubtitle.textContent = (value || 'مزودون موثّقون وخدمات مرتبة لتبدأ بشكل أسرع وأكثر وضوحًا.')
      .replaceAll('{provider_count}', String(count));
  }

  function _applyHomeContent() {
    if ($heroTitle) $heroTitle.textContent = _homeContent.heroTitle || 'الرئيسية';
    if ($heroSubtitle) {
      $heroSubtitle.textContent = (_homeContent.heroSubtitle || 'مزودون موثّقون وخدمات مرتبة لتبدأ بشكل أسرع وأكثر وضوحًا.')
        .replaceAll('{provider_count}', '0');
    }
    if ($searchPlaceholder) {
      $searchPlaceholder.textContent = _homeContent.searchPlaceholder || 'ابحث';
    }
    if ($categoriesTitle) {
      $categoriesTitle.textContent = _homeContent.categoriesTitle || 'التصنيفات';
    }
    if ($providersTitle) {
      $providersTitle.textContent = _homeContent.providersTitle || 'مقدمو الخدمة';
    }
    if ($bannersTitle) {
      $bannersTitle.textContent = _homeContent.bannersTitle || 'عروض ترويجية';
    }
  }

  function _resolveBlockTitle(block, fallback) {
    if (!block || typeof block !== 'object') return fallback;
    const title = String(block.title_ar || '').trim();
    return title || fallback;
  }

  function _setOffline(offline) {
    if (!$offlineBanner) return;
    $offlineBanner.style.display = offline ? 'flex' : 'none';
  }

  /* ----------------------------------------------------------
     PROMO: POPUP HOME
     Shown once per page load when an active popup_home promo exists.
  ---------------------------------------------------------- */
  function _showPromoPopup(promo) {
    const asset = (promo.assets && promo.assets.length) ? promo.assets[0] : null;
    const imageUrl = asset ? ApiClient.mediaUrl(asset.file_url) : null;
    const redirectUrl = promo.redirect_url || '';
    const title = promo.title || '';

    const overlay = UI.el('div', { className: 'promo-popup-overlay' });
    const modal = UI.el('div', { className: 'promo-popup-modal' });

    const closeBtn = UI.el('button', { className: 'promo-popup-close', textContent: '✕', type: 'button' });
    closeBtn.setAttribute('aria-label', 'إغلاق');
    closeBtn.addEventListener('click', () => overlay.remove());
    modal.appendChild(closeBtn);

    if (imageUrl) {
      const img = UI.el('img', { className: 'promo-popup-img' });
      img.src = imageUrl;
      img.alt = title;
      if (redirectUrl) {
        const link = UI.el('a', { href: redirectUrl, target: '_blank', rel: 'noopener' });
        link.appendChild(img);
        modal.appendChild(link);
      } else {
        modal.appendChild(img);
      }
    }

    if (title) {
      modal.appendChild(UI.el('p', { className: 'promo-popup-title', textContent: title }));
    }

    overlay.appendChild(modal);
    overlay.addEventListener('click', e => { if (e.target === overlay) overlay.remove(); });
    document.body.appendChild(overlay);
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
