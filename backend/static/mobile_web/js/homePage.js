/* ===================================================================
   homePage.js — Home page controller  v3.0
   1:1 mirror of Flutter home_screen.dart layout & behavior.
   Fetches same API endpoints:
     • GET /api/providers/categories/
     • GET /api/providers/list/?page_size=10
     • GET /api/promo/banners/home/
     • GET /api/promo/home-carousel/?limit=16
     • GET /api/providers/spotlights/feed/?limit=16
   SWR caching, auto-scroll reels, SpotlightViewer on tap.
   =================================================================== */
'use strict';

const HomePage = (() => {
  // Cache keys & TTL
  const CACHE_CATEGORIES = 'home_categories';
  const CACHE_PROVIDERS  = 'home_providers';
  const CACHE_FEATURED_SPECIALISTS = 'home_featured_specialists';
  const CACHE_BANNERS    = 'home_banners';
  const CACHE_SPOTLIGHTS = 'home_spotlights';
  const TTL = 90; // seconds
  const CAROUSEL_IMAGE_ROTATE_MS = 3000;
  const CAROUSEL_VIDEO_FALLBACK_ROTATE_MS = 30000;
  const BANNER_SYNC_INTERVAL_MS = 60000;
  const FEATURED_SPECIALISTS_LIMIT = 10;
  const FEATURED_SPECIALISTS_ROTATE_MS = 5000;
  const HOME_BANNERS_LIMIT = 16;
  const PORTFOLIO_SHOWCASE_LIMIT = 16;
  const PORTFOLIO_SHOWCASE_FETCH_LIMIT = 40;
  const PROVIDERS_RESUME_DELAY_MS = 3000;
  const REELS_IMAGE_ROTATE_MS = 3500;
  const REELS_VIDEO_FALLBACK_ROTATE_MS = 30000;

  // DOM refs
  let $categoriesList, $providersList, $bannersList, $bannersSection;
  let $portfolioShowcaseSection, $portfolioShowcaseList;
  let $promoMessageSection, $promoMessageCard;
  let $categoriesTitle, $providersTitle, $bannersTitle, $reelsTrack, $offlineBanner;
  let $carouselTrack, $carouselDots, $carouselPrev, $carouselNext;

  // State
  let _isLoading = false;
  let _reelsData = [];           // keep spotlight items for SpotlightViewer
  let _reelsAutoTimer = null;    // sequential reels timer
  let _reelsPaused = false;      // pause while user is touching/dragging
  let _reelsBound = false;       // bind track interaction handlers once
  let _reelsActiveIdx = 0;       // active reel index for sequential preview
  let _reelsActiveVideoEl = null;
  let _reelsActiveVideoEndedHandler = null;
  let _carouselItems = [];       // carousel banner data
  let _carouselIdx = 0;          // current slide index
  let _carouselTimer = null;     // auto-rotate timer
  let _carouselPaused = false;   // pause on interaction
  let _carouselBound = false;    // bind carousel interaction handlers once
  let _carouselResizeBound = false;
  let _bannerSyncTimer = null;
  let _carouselActiveVideoEl = null;
  let _carouselActiveVideoEndedHandler = null;
  let _providersAutoTimer = null;
  let _providersResumeTimer = null;
  let _providersPaused = false;
  let _providersBound = false;
  let _categoriesWheelSnapTimer = null;
  let _categoriesAutoTimer = null;
  let _categoriesResumeTimer = null;
  let _categoriesPaused = false;
  let _sectionObserver = null;
  let _popupShown = false;       // only show popup once per session
  let _homeContent = {
    categoriesTitle: '',
    providersTitle: '',
    bannersTitle: '',
    fallbackBanner: null,
  };

  /* ----------------------------------------------------------
     INIT
  ---------------------------------------------------------- */
  function init() {
    $categoriesList = document.getElementById('categories-list');
    $providersList  = document.getElementById('providers-list');
    $bannersList    = document.getElementById('carousel-track');
    $bannersSection = document.getElementById('banners');
    $categoriesTitle = document.getElementById('categories-title');
    $providersTitle = document.getElementById('providers-title');
    $bannersTitle = document.getElementById('banners-title');
    $reelsTrack     = document.getElementById('reels-track');
    $offlineBanner  = document.getElementById('offline-banner');
    $carouselTrack  = document.getElementById('carousel-track');
    $carouselDots   = document.getElementById('carousel-dots');
    $carouselPrev   = document.getElementById('carousel-prev');
    $carouselNext   = document.getElementById('carousel-next');
    $portfolioShowcaseSection = document.getElementById('portfolio-showcase');
    $portfolioShowcaseList = document.getElementById('portfolio-showcase-list');
    $promoMessageSection = document.getElementById('home-promo-message');
    $promoMessageCard = document.getElementById('home-promo-message-card');
    _bindReelsInteraction();
    _bindProvidersInteraction();
    _applyHomeContent();
    _initSectionPresentation();
    window.addEventListener('resize', _syncDesktopHomeBehaviors);

    // Network listener
    window.addEventListener('online',  () => _setOffline(false));
    window.addEventListener('offline', () => _setOffline(true));

    // Seed from cache (instant display)
    const seeded = _seedFromCache();

    // Fetch fresh data
    _loadData(!seeded);
    _startBannerSyncTimer();


    // Pull-to-refresh
    _initPullToRefresh();
    window.addEventListener('beforeunload', () => {
      if (_bannerSyncTimer) {
        window.clearInterval(_bannerSyncTimer);
        _bannerSyncTimer = null;
      }
      if (_sectionObserver) {
        _sectionObserver.disconnect();
        _sectionObserver = null;
      }
      window.removeEventListener('resize', _syncDesktopHomeBehaviors);
    }, { once: true });
  }

  function _initSectionPresentation() {
    if (!document.body) return;
    document.body.classList.add('js-enhanced-home');

    const sections = Array.from(document.querySelectorAll('[data-home-section]'));
    const shells = Array.from(document.querySelectorAll('.home-section-shell'));

    shells.forEach((shell) => {
      shell.addEventListener('pointermove', _handleSectionPointerMove, { passive: true });
      shell.addEventListener('pointerleave', _resetSectionPointerGlow, { passive: true });
    });

    if (!sections.length) {
      return;
    }

    if (!('IntersectionObserver' in window)) {
      sections.forEach((section) => section.classList.add('is-visible'));
      return;
    }

    _sectionObserver = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        entry.target.classList.add('is-visible');
        if (_sectionObserver) {
          _sectionObserver.unobserve(entry.target);
        }
      });
    }, {
      threshold: 0.16,
      rootMargin: '0px 0px -12% 0px',
    });

    sections.forEach((section) => _sectionObserver.observe(section));
  }

  function _handleSectionPointerMove(event) {
    if (window.innerWidth < 960) return;
    const shell = event.currentTarget;
    if (!shell) return;
    const rect = shell.getBoundingClientRect();
    if (!rect.width || !rect.height) return;
    const x = ((event.clientX - rect.left) / rect.width) * 100;
    const y = ((event.clientY - rect.top) / rect.height) * 100;
    shell.style.setProperty('--section-pointer-x', `${Math.max(0, Math.min(100, x))}%`);
    shell.style.setProperty('--section-pointer-y', `${Math.max(0, Math.min(100, y))}%`);
  }

  function _resetSectionPointerGlow(event) {
    const shell = event.currentTarget;
    if (!shell) return;
    shell.style.removeProperty('--section-pointer-x');
    shell.style.removeProperty('--section-pointer-y');
  }

  function _notifySectionShown(section) {
    if (!section) return;
    section.classList.add('is-visible');
    if (_sectionObserver) {
      _sectionObserver.unobserve(section);
    }
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
      _updateSubtitle(provs.data.length);
      any = true;
    }

    const featured = NwCache.get(CACHE_FEATURED_SPECIALISTS);
    if (featured && featured.data && featured.data.length) {
      _renderFeaturedSpecialists(featured.data);
      any = true;
    }

    const bans = NwCache.get(CACHE_BANNERS);
    if (bans && !bans.stale && bans.data && bans.data.length) {
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

  function _readBannerString(value) {
    if (value == null) return '';
    return String(value).trim();
  }

  function _readBannerInt(value) {
    const parsed = Number.parseInt(String(value ?? ''), 10);
    return Number.isFinite(parsed) ? parsed : 0;
  }

  function _readPromoFloat(value) {
    const parsed = Number.parseFloat(String(value ?? ''));
    return Number.isFinite(parsed) ? parsed : 0;
  }

  function _readBannerScale(value, fallback, minimum, maximum) {
    const parsed = Number.parseInt(String(value ?? ''), 10);
    if (!Number.isFinite(parsed)) return fallback;
    return Math.max(minimum, Math.min(parsed, maximum));
  }

  function _lerp(start, end, t) {
    return start + ((end - start) * t);
  }

  function _resolveResponsiveBannerScale(banner) {
    const viewportWidth = Math.max(
      window.innerWidth || 0,
      document.documentElement ? document.documentElement.clientWidth : 0,
      390,
    );
    const mobile = _readBannerScale(banner.mobile_scale, 100, 40, 140);
    const tablet = _readBannerScale(banner.tablet_scale, mobile, 40, 150);
    const desktop = _readBannerScale(banner.desktop_scale, tablet, 40, 160);
    if (viewportWidth <= 480) return mobile / 100;
    if (viewportWidth <= 820) {
      return _lerp(mobile, tablet, (viewportWidth - 480) / 340) / 100;
    }
    if (viewportWidth <= 1600) {
      return _lerp(tablet, desktop, (viewportWidth - 820) / 780) / 100;
    }
    return desktop / 100;
  }

  function _applyResponsiveBannerScales() {
    if (!$carouselTrack || !_carouselItems.length) return;
    $carouselTrack.querySelectorAll('.carousel-media-frame').forEach((frame) => {
      const idx = Number.parseInt(frame.getAttribute('data-banner-index') || '', 10);
      const banner = Number.isFinite(idx) ? _carouselItems[idx] : null;
      const scale = banner ? _resolveResponsiveBannerScale(banner) : 1;
      frame.style.setProperty('--banner-effective-scale', String(scale));
    });
  }

  function _bindCarouselResize() {
    if (_carouselResizeBound) return;
    _carouselResizeBound = true;
    let resizeTimer = null;
    window.addEventListener('resize', () => {
      window.clearTimeout(resizeTimer);
      resizeTimer = window.setTimeout(_applyResponsiveBannerScales, 60);
    });
  }

  function _normalizeBanner(raw) {
    if (!raw || typeof raw !== 'object') return null;
    const mediaUrl = _readBannerString(raw.media_url || raw.file_url);
    if (!mediaUrl) return null;
    const mobileScale = _readBannerScale(raw.mobile_scale, 100, 40, 140);
    const tabletScale = _readBannerScale(raw.tablet_scale, mobileScale, 40, 150);
    return {
      id: _readBannerInt(raw.id),
      title: _readBannerString(raw.title || raw.caption),
      media_type: (_readBannerString(raw.media_type || raw.file_type) || 'image').toLowerCase(),
      media_url: mediaUrl,
      link_url: _readBannerString(raw.link_url || raw.redirect_url),
      provider_id: _readBannerInt(raw.provider_id),
      provider_display_name: _readBannerString(raw.provider_display_name),
      display_order: _readBannerInt(raw.display_order),
      mobile_scale: mobileScale,
      tablet_scale: tabletScale,
      desktop_scale: _readBannerScale(raw.desktop_scale, tabletScale, 40, 160),
      duration_seconds: _readBannerInt(
        raw.duration_seconds
        || raw.video_duration_seconds
        || raw.media_duration_seconds
        || raw.display_seconds
      ),
    };
  }

  function _parseBannerList(data) {
    const list = Array.isArray(data)
      ? data
      : (data && Array.isArray(data.results) ? data.results : []);
    return list.map(_normalizeBanner).filter(Boolean);
  }

  function _shuffleList(list) {
    const rows = Array.isArray(list) ? list.slice() : [];
    for (let i = rows.length - 1; i > 0; i -= 1) {
      const j = Math.floor(Math.random() * (i + 1));
      const tmp = rows[i];
      rows[i] = rows[j];
      rows[j] = tmp;
    }
    return rows;
  }

  function _mergeBannerLists(primaryBanners, fallbackBanners, limit = HOME_BANNERS_LIMIT) {
    const safePrimary = Array.isArray(primaryBanners) ? primaryBanners : [];
    const safeFallback = _shuffleList(fallbackBanners);
    const cap = Math.max(1, Number(limit) || HOME_BANNERS_LIMIT);
    if (safePrimary.length >= cap) return safePrimary.slice(0, cap);
    const remaining = Math.max(0, cap - safePrimary.length);
    return safePrimary.concat(safeFallback.slice(0, remaining));
  }

  function _buildFallbackBannerFromBlock(block) {
    if (!block || typeof block !== 'object') return null;
    const mediaUrl = _readBannerString(block.media_url);
    if (!mediaUrl) return null;
    return {
      id: 0,
      title: _readBannerString(block.title_ar),
      media_type: (_readBannerString(block.media_type) || 'image').toLowerCase(),
      media_url: mediaUrl,
      link_url: '',
      provider_id: 0,
      provider_display_name: '',
      display_order: 0,
      mobile_scale: 100,
      tablet_scale: 100,
      desktop_scale: 100,
      duration_seconds: 0,
      is_fallback: true,
    };
  }

  function _resolveRenderedBanners(banners) {
    const safeBanners = Array.isArray(banners) ? banners.filter(Boolean) : [];
    if (safeBanners.length) return safeBanners;
    return _homeContent.fallbackBanner ? [_homeContent.fallbackBanner] : [];
  }

  function _isTrackableBanner(banner) {
    return !!banner && !banner.is_fallback && _readBannerInt(banner.id) > 0;
  }

  function _bannerSignature(list) {
    const rows = Array.isArray(list) ? list : [];
    return rows.map((banner) => [
      String(banner.id || 0),
      String(banner.media_url || ''),
      String(banner.media_type || ''),
      String(banner.link_url || ''),
      String(banner.display_order || 0),
      String(banner.duration_seconds || 0),
      String(!!banner.is_fallback),
    ].join('|')).join('||');
  }

  function _startBannerSyncTimer() {
    if (_bannerSyncTimer) {
      window.clearInterval(_bannerSyncTimer);
      _bannerSyncTimer = null;
    }
    _bannerSyncTimer = window.setInterval(() => {
      if (document.hidden) {
        return;
      }
      _refreshBannersOnly();
    }, BANNER_SYNC_INTERVAL_MS);
  }

  async function _refreshBannersOnly() {
    try {
      const [promoRes, carouselRes] = await Promise.all([
        ApiClient.get('/api/promo/banners/home/'),
        ApiClient.get('/api/promo/home-carousel/?limit=' + HOME_BANNERS_LIMIT),
      ]);

      const promoBanners = (promoRes && promoRes.ok && promoRes.data)
        ? _parseBannerList(promoRes.data)
        : [];
      const carouselBanners = (carouselRes && carouselRes.ok && carouselRes.data)
        ? _parseBannerList(carouselRes.data)
        : [];
      const mergedBanners = _mergeBannerLists(promoBanners, carouselBanners, HOME_BANNERS_LIMIT);
      const renderedBanners = _resolveRenderedBanners(mergedBanners);
      const nextSignature = _bannerSignature(renderedBanners);
      const currentSignature = _bannerSignature(_carouselItems);

      if (!mergedBanners.length) {
        NwCache.set(CACHE_BANNERS, [], TTL);
        if (nextSignature !== currentSignature) {
          _renderBanners(renderedBanners);
        }
        return;
      }

      NwCache.set(CACHE_BANNERS, mergedBanners, TTL);
      if (nextSignature !== currentSignature) {
        _renderBanners(renderedBanners);
      }
    } catch (_) {
      // Keep the current rendered banners on transient sync failures.
    }
  }

  function _classifyCarouselMediaRatio(width, height) {
    const safeWidth = Number(width) || 0;
    const safeHeight = Number(height) || 0;
    if (safeWidth <= 0 || safeHeight <= 0) return 'landscape';
    const ratio = safeWidth / safeHeight;
    if (ratio >= 2.05) return 'ultrawide';
    if (ratio >= 1.05) return 'landscape';
    if (ratio <= 0.8) return 'portrait';
    return 'square';
  }

  function _applyCarouselMediaLayout(frame, width, height) {
    if (!frame) return;
    frame.setAttribute('data-media-ratio', _classifyCarouselMediaRatio(width, height));
  }

  function _bindCarouselMediaLayout(frame, mediaEl, isVideo) {
    if (!frame || !mediaEl) return;
    let resolved = false;
    const apply = (width, height) => {
      if (resolved) return;
      if (!(Number(width) > 0 && Number(height) > 0)) return;
      resolved = true;
      _applyCarouselMediaLayout(frame, width, height);
    };
    const fallback = () => {
      if (resolved) return;
      resolved = true;
      frame.setAttribute('data-media-ratio', 'landscape');
    };

    if (isVideo) {
      const onMetadata = () => apply(mediaEl.videoWidth, mediaEl.videoHeight);
      if (mediaEl.readyState >= 1) onMetadata();
      mediaEl.addEventListener('loadedmetadata', onMetadata, { once: true });
      mediaEl.addEventListener('error', fallback, { once: true });
    } else {
      const onLoad = () => apply(mediaEl.naturalWidth, mediaEl.naturalHeight);
      if (mediaEl.complete) onLoad();
      mediaEl.addEventListener('load', onLoad, { once: true });
      mediaEl.addEventListener('error', fallback, { once: true });
    }

    window.setTimeout(fallback, 1400);
  }

  function _syncCarouselSlideMedia(slide, shouldPlay) {
    if (!slide) return;
    slide.querySelectorAll('video').forEach(video => {
      if (shouldPlay) {
        try { video.currentTime = 0; } catch (_) {}
        const playPromise = video.play();
        if (playPromise && typeof playPromise.catch === 'function') {
          playPromise.catch(() => {});
        }
        return;
      }
      video.pause();
      try { video.currentTime = 0; } catch (_) {}
    });
  }

  function _detachCarouselVideoEndedHook() {
    if (_carouselActiveVideoEl && _carouselActiveVideoEndedHandler) {
      _carouselActiveVideoEl.removeEventListener('ended', _carouselActiveVideoEndedHandler);
    }
    _carouselActiveVideoEl = null;
    _carouselActiveVideoEndedHandler = null;
  }

  function _buildCarouselMedia(banner, url, isVideo, isActive) {
    const frame = UI.el('div', {
      className: 'carousel-media-frame' + (isVideo ? ' is-video' : ' is-image'),
    });
    frame.setAttribute('data-media-ratio', 'landscape');
    frame.style.setProperty('--banner-effective-scale', String(_resolveResponsiveBannerScale(banner)));
    const shouldLoopSingleVideo = isVideo && _carouselItems.length <= 1;

    const backdrop = UI.el('div', {
      className: 'carousel-media-backdrop' + (isVideo ? ' is-video' : ''),
      'aria-hidden': 'true',
    });

    if (isVideo && url) {
      const backdropVid = UI.el('video', {
        className: 'carousel-media-backdrop-video',
        src: url,
        preload: isActive ? 'metadata' : 'none',
        tabindex: '-1',
        'aria-hidden': 'true',
      });
      backdropVid.muted = true;
      backdropVid.loop = shouldLoopSingleVideo;
      backdropVid.playsInline = true;
      backdropVid.setAttribute('playsinline', '');
      backdropVid.setAttribute('disablepictureinpicture', '');
      backdrop.appendChild(backdropVid);
    }

    if (!isVideo && url) {
      const backdropImg = UI.el('img', {
        className: 'carousel-media-backdrop-image',
        alt: '',
        loading: isActive ? 'eager' : 'lazy',
        decoding: 'async',
      });
      backdropImg.src = url;
      frame.appendChild(backdrop);
      backdrop.appendChild(backdropImg);
    } else {
      frame.appendChild(backdrop);
    }

    const stage = UI.el('div', { className: 'carousel-media-stage' });
    frame.appendChild(stage);

    const mediaAlt = banner.title || banner.provider_display_name || 'بنر الصفحة الرئيسية';

    if (isVideo && url) {
      const vid = UI.el('video', {
        className: 'carousel-media carousel-media-video',
        src: url,
        preload: isActive ? 'auto' : 'metadata',
        'aria-label': mediaAlt,
      });
      vid.autoplay = false;
      vid.muted = true;
      vid.loop = shouldLoopSingleVideo;
      vid.playsInline = true;
      vid.setAttribute('playsinline', '');
      vid.setAttribute('disablepictureinpicture', '');
      stage.appendChild(vid);
      _bindCarouselMediaLayout(frame, vid, true);
    } else if (url) {
      const img = UI.el('img', {
        className: 'carousel-media',
        loading: isActive ? 'eager' : 'lazy',
        decoding: 'async',
        fetchpriority: isActive ? 'high' : 'auto',
        alt: mediaAlt,
      });
      img.src = url;
      stage.appendChild(img);
      _bindCarouselMediaLayout(frame, img, false);
    }

    return frame;
  }

  /* ----------------------------------------------------------
     LOAD DATA (parallel API calls — same as Flutter)
  ---------------------------------------------------------- */
  async function _loadData(showSkeletons) {
    if (_isLoading) return;
    _isLoading = true;

    const [contentRes, catsRes, provsRes, promoBansRes, carouselRes, reelsRes, featuredRes, portfolioRes, portfolioFeedRes, snapshotPromoRes, popupRes, promoMessageRes] = await Promise.allSettled([
      ApiClient.get('/api/content/public/'),
      ApiClient.get('/api/providers/categories/'),
      ApiClient.get('/api/providers/list/?page_size=10'),
      ApiClient.get('/api/promo/banners/home/'),
      ApiClient.get('/api/promo/home-carousel/?limit=' + HOME_BANNERS_LIMIT),
      ApiClient.get('/api/providers/spotlights/feed/?limit=16'),
      ApiClient.get('/api/promo/active/?service_type=featured_specialists&limit=' + FEATURED_SPECIALISTS_LIMIT),
      ApiClient.get('/api/promo/active/?service_type=portfolio_showcase&limit=' + PORTFOLIO_SHOWCASE_FETCH_LIMIT),
      ApiClient.get('/api/providers/portfolio/feed/?limit=' + PORTFOLIO_SHOWCASE_FETCH_LIMIT),
      ApiClient.get('/api/promo/active/?service_type=snapshots&limit=16'),
      ApiClient.get('/api/promo/active/?ad_type=popup_home&limit=1'),
      ApiClient.get('/api/promo/active/?service_type=promo_messages&limit=1'),
    ]);

    if (contentRes.status === 'fulfilled' && contentRes.value.ok && contentRes.value.data) {
      const blocks = contentRes.value.data.blocks || {};
      _homeContent = {
        categoriesTitle: _resolveBlockTitle(blocks.home_categories_title, 'التصنيفات'),
        providersTitle: _resolveBlockTitle(blocks.home_providers_title, 'أبرز المختصين'),
        bannersTitle: _resolveBlockTitle(blocks.home_banners_title, 'عروض ترويجية'),
        fallbackBanner: _buildFallbackBannerFromBlock(blocks.home_banners_fallback),
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

    let featuredPlacements = [];
    if (featuredRes.status === 'fulfilled' && featuredRes.value.ok && featuredRes.value.data) {
      featuredPlacements = Array.isArray(featuredRes.value.data)
        ? featuredRes.value.data
        : (featuredRes.value.data.results || []);
    }

    let providerRows = [];
    if (provsRes.status === 'fulfilled' && provsRes.value.ok && provsRes.value.data) {
      providerRows = Array.isArray(provsRes.value.data)
        ? provsRes.value.data
        : (provsRes.value.data.results || []);
      NwCache.set(CACHE_PROVIDERS, providerRows, TTL);
      _updateSubtitle(providerRows.length);
    } else if (!NwCache.get(CACHE_PROVIDERS)) {
      _updateSubtitle(0);
    }

    // Featured providers: sponsored placements + top rated providers.
    const mergedFeaturedSpecialists = _mergeFeaturedSpecialists(
      featuredPlacements,
      providerRows,
      FEATURED_SPECIALISTS_LIMIT
    );
    if (mergedFeaturedSpecialists.length) {
      NwCache.set(CACHE_FEATURED_SPECIALISTS, mergedFeaturedSpecialists, TTL);
      _renderFeaturedSpecialists(mergedFeaturedSpecialists);
    } else if (!NwCache.get(CACHE_FEATURED_SPECIALISTS)) {
      _renderFeaturedSpecialists([]);
    }

    // Portfolio showcase: sponsored placements + latest works from newest providers.
    const portfolioPlacements = (portfolioRes.status === 'fulfilled' && portfolioRes.value.ok && portfolioRes.value.data)
      ? (Array.isArray(portfolioRes.value.data)
        ? portfolioRes.value.data
        : (portfolioRes.value.data.results || []))
      : [];
    const portfolioFeedItems = (portfolioFeedRes.status === 'fulfilled' && portfolioFeedRes.value.ok && portfolioFeedRes.value.data)
      ? (Array.isArray(portfolioFeedRes.value.data)
        ? portfolioFeedRes.value.data
        : (portfolioFeedRes.value.data.results || []))
      : [];
    _renderPortfolioShowcase(
      _mergePortfolioShowcaseLists(portfolioPlacements, portfolioFeedItems, PORTFOLIO_SHOWCASE_LIMIT)
    );

    // Banners
    const promoBanners = (promoBansRes.status === 'fulfilled' && promoBansRes.value.ok && promoBansRes.value.data)
      ? _parseBannerList(promoBansRes.value.data)
      : [];
    const carouselBanners = (carouselRes.status === 'fulfilled' && carouselRes.value.ok && carouselRes.value.data)
      ? _parseBannerList(carouselRes.value.data)
      : [];
    const mergedBanners = _mergeBannerLists(promoBanners, carouselBanners, HOME_BANNERS_LIMIT);
    const bannersFetched =
      promoBansRes.status === 'fulfilled'
      && !!promoBansRes.value
      && promoBansRes.value.ok
      && carouselRes.status === 'fulfilled'
      && !!carouselRes.value
      && carouselRes.value.ok;
    if (mergedBanners.length) {
      NwCache.set(CACHE_BANNERS, mergedBanners, TTL);
      _renderBanners(mergedBanners);
    } else if (bannersFetched) {
      NwCache.set(CACHE_BANNERS, [], TTL);
      _renderBanners(_resolveRenderedBanners([]));
    } else if (!NwCache.get(CACHE_BANNERS)) {
      _renderBanners(_resolveRenderedBanners([]));
    }

    // Spotlights (reels)
    if (reelsRes.status === 'fulfilled' && reelsRes.value.ok && reelsRes.value.data) {
      const feedList = Array.isArray(reelsRes.value.data)
        ? reelsRes.value.data
        : (reelsRes.value.data.results || []);
      const promoSnapshotPlacements = (snapshotPromoRes.status === 'fulfilled' && snapshotPromoRes.value.ok && snapshotPromoRes.value.data)
        ? (Array.isArray(snapshotPromoRes.value.data) ? snapshotPromoRes.value.data : (snapshotPromoRes.value.data.results || []))
        : [];
      const promoSnapshotItems = promoSnapshotPlacements
        .map(_normalizeSnapshotPromoItem)
        .filter(Boolean);
      const list = _mergeReelsLists(promoSnapshotItems, feedList, 16);
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

    // Popup promo (home)
    if (!_popupShown && popupRes.status === 'fulfilled' && popupRes.value.ok && popupRes.value.data) {
      const list = Array.isArray(popupRes.value.data) ? popupRes.value.data : [];
      if (list.length > 0) {
        _popupShown = true;
        _showPromoPopup(list[0]);
      }
    }

    // Promo messages card
    if (promoMessageRes.status === 'fulfilled' && promoMessageRes.value.ok && promoMessageRes.value.data) {
      const rows = Array.isArray(promoMessageRes.value.data)
        ? promoMessageRes.value.data
        : (promoMessageRes.value.data.results || []);
      _renderPromoMessage(rows.length ? rows[0] : null);
    } else {
      _renderPromoMessage(null);
    }

    // Offline detection
    const allFailed = [contentRes, catsRes, provsRes, promoBansRes, carouselRes, reelsRes].every(
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
    _initCategoriesCarousel();
  }

  /* ----------------------------------------------------------
     CAROUSEL: Categories arrow navigation (desktop)
  ---------------------------------------------------------- */
  function _initCategoriesCarousel() {
    if (!$categoriesList) return;
    var carousel = $categoriesList.closest('.categories-carousel');
    if (!carousel) return;
    var prevBtn = carousel.querySelector('.categories-arrow--prev');
    var nextBtn = carousel.querySelector('.categories-arrow--next');
    if (!prevBtn || !nextBtn) return;

    function getCards() {
      return Array.prototype.slice.call($categoriesList.querySelectorAll('.cat-item'));
    }

    function updateArrows() {
      var cards = getCards();
      var listRect = $categoriesList.getBoundingClientRect();
      var tolerance = 6;
      var hasLeftOverflow = false;
      var hasRightOverflow = false;
      var hiddenLeftCount = 0;
      var hiddenRightCount = 0;
      var visibleCount = 0;

      cards.forEach(function(card) {
        var rect = card.getBoundingClientRect();
        if (rect.left < listRect.left - tolerance) {
          hasLeftOverflow = true;
          hiddenLeftCount += 1;
        }
        if (rect.right > listRect.right + tolerance) {
          hasRightOverflow = true;
          hiddenRightCount += 1;
        }
        if (rect.right > listRect.left + tolerance && rect.left < listRect.right - tolerance) {
          visibleCount += 1;
        }
      });

      var isScrollable = ($categoriesList.scrollWidth - $categoriesList.clientWidth) > tolerance;
      carousel.classList.toggle('is-scrollable', isScrollable);
      carousel.classList.toggle('at-start', isScrollable && !hasRightOverflow);
      carousel.classList.toggle('at-end', isScrollable && !hasLeftOverflow);
      prevBtn.disabled = !hasLeftOverflow;
      nextBtn.disabled = !hasRightOverflow;
      _updateCategoriesProgress(carousel, cards.length, visibleCount, hiddenLeftCount, hiddenRightCount, isScrollable);
    }

    function scrollToHiddenCard(edge) {
      var cards = getCards();
      var listRect = $categoriesList.getBoundingClientRect();
      var tolerance = 6;
      var target = null;

      if (edge === 'left') {
        for (var index = cards.length - 1; index >= 0; index -= 1) {
          if (cards[index].getBoundingClientRect().left < listRect.left - tolerance) {
            target = cards[index];
            break;
          }
        }
        if (target) {
          target.scrollIntoView({ behavior: 'smooth', block: 'nearest', inline: 'start' });
        }
        return;
      }

      for (var itemIndex = 0; itemIndex < cards.length; itemIndex += 1) {
        if (cards[itemIndex].getBoundingClientRect().right > listRect.right + tolerance) {
          target = cards[itemIndex];
          break;
        }
      }
      if (target) {
        target.scrollIntoView({ behavior: 'smooth', block: 'nearest', inline: 'end' });
      }
    }

    carousel._updateCategoriesArrows = updateArrows;

    if (!carousel.dataset.bound) {
      prevBtn.addEventListener('click', function() {
        _pauseCategoriesAutoScroll();
        scrollToHiddenCard('left');
        _scheduleCategoriesResume();
      });

      nextBtn.addEventListener('click', function() {
        _pauseCategoriesAutoScroll();
        scrollToHiddenCard('right');
        _scheduleCategoriesResume();
      });

      $categoriesList.addEventListener('wheel', function(event) {
        if (Math.abs(event.deltaY) <= Math.abs(event.deltaX)) return;
        if (($categoriesList.scrollWidth - $categoriesList.clientWidth) <= 4) return;
        event.preventDefault();
        _pauseCategoriesAutoScroll();
        $categoriesList.classList.add('is-wheel-scrolling');
        $categoriesList.scrollBy({ left: event.deltaY, behavior: 'auto' });
        window.clearTimeout(_categoriesWheelSnapTimer);
        _categoriesWheelSnapTimer = window.setTimeout(function() {
          $categoriesList.classList.remove('is-wheel-scrolling');
          if (typeof carousel._updateCategoriesArrows === 'function') {
            carousel._updateCategoriesArrows();
          }
          _scheduleCategoriesResume();
        }, 140);
      }, { passive: false });

      $categoriesList.addEventListener('scroll', function() {
        if (typeof carousel._updateCategoriesArrows === 'function') {
          carousel._updateCategoriesArrows();
        }
      }, { passive: true });

      carousel.dataset.bound = 'true';
    }

    /* — Auto-scroll: slow continuous scroll — */
    _startCategoriesAutoScroll();

    var pauseTarget = carousel || $categoriesList;

    if (!pauseTarget.dataset.autoBound) {
      pauseTarget.addEventListener('pointerdown', function() {
        _pauseCategoriesAutoScroll();
        _scheduleCategoriesResume();
      }, { passive: true });
      pauseTarget.addEventListener('touchstart', function() {
        _pauseCategoriesAutoScroll();
        _scheduleCategoriesResume();
      }, { passive: true });
      pauseTarget.addEventListener('wheel', function() {
        _pauseCategoriesAutoScroll();
        _scheduleCategoriesResume();
      }, { passive: true });
      pauseTarget.dataset.autoBound = 'true';
    }

    window.requestAnimationFrame(function() {
      if (typeof carousel._updateCategoriesArrows === 'function') {
        carousel._updateCategoriesArrows();
      }
    });
    window.setTimeout(function() {
      if (typeof carousel._updateCategoriesArrows === 'function') {
        carousel._updateCategoriesArrows();
      }
    }, 140);
  }

  /* ----------------------------------------------------------
     CATEGORIES: slow auto-scroll with pause on interaction
  ---------------------------------------------------------- */
  var CATEGORIES_AUTO_STEP = 1;
  var CATEGORIES_AUTO_INTERVAL = 30;
  var CATEGORIES_RESUME_DELAY = 2500;

  function _hasHorizontalOverflow(container, tolerance = 2) {
    if (!container) return false;
    return (container.scrollWidth - container.clientWidth) > tolerance;
  }

  function _startCategoriesAutoScroll() {
    _stopCategoriesAutoScroll();
    if (!$categoriesList) return;
    var cards = $categoriesList.querySelectorAll('.cat-item');
    if (cards.length <= 2) return;

    _categoriesPaused = false;
    _categoriesAutoTimer = setInterval(function() {
      if (_categoriesPaused || !$categoriesList) return;
      var maxScroll = $categoriesList.scrollWidth - $categoriesList.clientWidth;
      if (maxScroll <= 0) return;

      if ($categoriesList.scrollLeft >= maxScroll - 1) {
        $categoriesList.scrollTo({ left: 0, behavior: 'smooth' });
      } else {
        $categoriesList.scrollLeft += CATEGORIES_AUTO_STEP;
      }
    }, CATEGORIES_AUTO_INTERVAL);
  }

  function _stopCategoriesAutoScroll() {
    if (_categoriesAutoTimer) {
      clearInterval(_categoriesAutoTimer);
      _categoriesAutoTimer = null;
    }
    if (_categoriesResumeTimer) {
      clearTimeout(_categoriesResumeTimer);
      _categoriesResumeTimer = null;
    }
  }

  function _pauseCategoriesAutoScroll() {
    _categoriesPaused = true;
    if (_categoriesResumeTimer) {
      clearTimeout(_categoriesResumeTimer);
      _categoriesResumeTimer = null;
    }
  }

  function _scheduleCategoriesResume() {
    if (_categoriesResumeTimer) {
      clearTimeout(_categoriesResumeTimer);
    }
    _categoriesResumeTimer = setTimeout(function() {
      _categoriesPaused = false;
      if (!_categoriesAutoTimer) {
        _startCategoriesAutoScroll();
      }
    }, CATEGORIES_RESUME_DELAY);
  }

  function _updateCategoriesProgress(carousel, totalCount, visibleCount, hiddenLeftCount, hiddenRightCount, isScrollable) {
    if (!carousel) return;
    if (!isScrollable || !totalCount) {
      carousel.style.setProperty('--category-thumb-pct', '100%');
      carousel.style.setProperty('--category-progress-offset', '0%');
      return;
    }

    const safeTotal = Math.max(1, Number(totalCount) || 1);
    const safeVisible = Math.max(1, Math.min(safeTotal, Number(visibleCount) || 1));
    const thumbPct = Math.max(18, Math.min(72, (safeVisible / safeTotal) * 100));
    const travelPct = 100 - thumbPct;
    const hiddenSum = Math.max(1, (Number(hiddenLeftCount) || 0) + (Number(hiddenRightCount) || 0));
    const progress = Math.max(0, Math.min(1, (Number(hiddenRightCount) || 0) / hiddenSum));

    carousel.style.setProperty('--category-thumb-pct', thumbPct.toFixed(2) + '%');
    carousel.style.setProperty('--category-progress-offset', (travelPct * progress).toFixed(2) + '%');
  }

  function _renderCategoriesEmpty() {
    if (!$categoriesList) return;
    $categoriesList.textContent = '';
    $categoriesList.appendChild(
      UI.el('div', { className: 'providers-empty', textContent: 'لا توجد تصنيفات متاحة حالياً' })
    );
  }

  /* ----------------------------------------------------------
     RENDER: FEATURED SPECIALISTS
     Compact paid strip: avatar + verification + rating.
   ---------------------------------------------------------- */
  function _normalizeFeaturedSpecialist(raw) {
    if (!raw || typeof raw !== 'object') return null;
    const providerId = _readBannerInt(raw.provider_id || raw.target_provider_id || raw.id);
    if (!providerId) return null;
    const badges = Array.isArray(raw.excellence_badges)
      ? raw.excellence_badges.filter(item => item && typeof item === 'object')
      : (Array.isArray(raw.target_provider_excellence_badges)
        ? raw.target_provider_excellence_badges.filter(item => item && typeof item === 'object')
        : []);
    return {
      id: _readBannerInt(raw.id || raw.item_id || providerId),
      provider_id: providerId,
      display_name: _readBannerString(raw.display_name || raw.target_provider_display_name) || 'مختص',
      profile_image: _readBannerString(raw.profile_image || raw.target_provider_profile_image),
      city: UI.formatCityDisplay(
        _readBannerString(raw.city || raw.target_provider_city_display || raw.target_provider_city),
        _readBannerString(raw.region || raw.target_provider_region)
      ),
      redirect_url: _readBannerString(raw.redirect_url),
      is_verified_blue: !!(raw.is_verified_blue || raw.target_provider_is_verified_blue),
      is_verified_green: !!(raw.is_verified_green || raw.target_provider_is_verified_green),
      rating_avg: _readPromoFloat(raw.rating_avg || raw.target_provider_rating_avg),
      rating_count: _readBannerInt(raw.rating_count || raw.target_provider_rating_count),
      excellence_badges: badges,
    };
  }

  function _sortTopRatedProviders(rows) {
    return (Array.isArray(rows) ? rows : [])
      .slice()
      .sort((a, b) => {
        const ratingDiff = _readPromoFloat(b && b.rating_avg) - _readPromoFloat(a && a.rating_avg);
        if (Math.abs(ratingDiff) > 0.0001) return ratingDiff;
        const countDiff = _readBannerInt(b && b.rating_count) - _readBannerInt(a && a.rating_count);
        if (countDiff) return countDiff;
        return _readBannerInt(b && b.id) - _readBannerInt(a && a.id);
      });
  }

  function _mergeFeaturedSpecialists(placements, providers, limit) {
    const cap = Math.max(1, _readBannerInt(limit) || FEATURED_SPECIALISTS_LIMIT);
    const seenProviderIds = new Set();
    const merged = [];

    (Array.isArray(placements) ? placements : [])
      .map(_normalizeFeaturedSpecialist)
      .forEach((item) => {
        if (!item || !item.provider_id || seenProviderIds.has(item.provider_id) || merged.length >= cap) return;
        seenProviderIds.add(item.provider_id);
        merged.push(item);
      });

    _sortTopRatedProviders(providers)
      .map(_normalizeFeaturedSpecialist)
      .forEach((item) => {
        if (!item || !item.provider_id || seenProviderIds.has(item.provider_id) || merged.length >= cap) return;
        seenProviderIds.add(item.provider_id);
        merged.push(item);
      });

    return merged;
  }

  function _renderFeaturedSpecialists(placements) {
    if (!$providersList) return;
    const seenProviderIds = new Set();
    const specialists = (Array.isArray(placements) ? placements : [])
      .map(_normalizeFeaturedSpecialist)
      .filter(item => item && !seenProviderIds.has(item.provider_id) && seenProviderIds.add(item.provider_id));
    if (!specialists.length) { _renderProvidersEmpty(); return; }

    const frag = document.createDocumentFragment();
    specialists.forEach(item => {
      const profileUrl = ApiClient.mediaUrl(item.profile_image);
      const displayName = item.display_name;
      const initial = displayName.charAt(0) || '؟';
      const providerHref = item.provider_id
        ? '/provider/' + encodeURIComponent(String(item.provider_id)) + '/'
        : '/search/';

      const card = UI.el('div', {
        className: 'featured-specialist-card',
        role: 'button',
        tabindex: '0',
      });
      const openTarget = () => {
        if (typeof NwAnalytics !== 'undefined') {
          NwAnalytics.track('promo.featured_specialist_click', {
            surface: 'mobile_web.home.featured_specialists',
            source_app: 'promo',
            object_type: 'ProviderProfile',
            object_id: String(item.provider_id || ''),
            payload: {
              rating_avg: item.rating_avg,
              rating_count: item.rating_count,
            },
          });
        }
        const external = item.redirect_url && /^https?:\/\//i.test(item.redirect_url);
        if (external) {
          window.open(item.redirect_url, '_blank', 'noopener');
          return;
        }
        window.location.href = providerHref;
      };
      card.addEventListener('click', openTarget);
      card.addEventListener('keydown', e => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          openTarget();
        }
      });

      const avatarShell = UI.el('div', { className: 'featured-specialist-avatar-shell' });
      const avatarRing = UI.el('div', { className: 'featured-specialist-avatar-ring' });
      const avatar = UI.el('div', { className: 'featured-specialist-avatar' });
      if (profileUrl) {
        avatar.appendChild(UI.lazyImg(profileUrl, initial));
      } else {
        avatar.appendChild(UI.text(initial));
      }
      avatarRing.appendChild(avatar);
      avatarShell.appendChild(avatarRing);

      const topExcellenceItems = UI.normalizeExcellenceBadges(item.excellence_badges);
      if (topExcellenceItems.length) {
        avatarShell.appendChild(UI.el('span', {
          className: 'featured-specialist-badge',
          textContent: 'تميز',
        }));
      }

      const isVerified = !!(item.is_verified_blue || item.is_verified_green);
      if (isVerified) {
        const verified = UI.el('span', { className: 'featured-specialist-verified' });
        verified.appendChild(
          item.is_verified_blue
            ? UI.icon('verified_blue', 16, '#2196F3')
            : UI.icon('verified_green', 16, '#4CAF50')
        );
        avatarShell.appendChild(verified);
      }

      card.appendChild(avatarShell);
      card.appendChild(UI.el('div', {
        className: 'featured-specialist-name',
        textContent: displayName,
      }));

      const ratingNumber = Number(item.rating_avg);
      const hasRating = Number.isFinite(ratingNumber) && ratingNumber > 0;
      const meta = UI.el('div', {
        className: 'featured-specialist-meta' + (hasRating ? '' : ' is-empty'),
      });
      if (hasRating) {
        meta.appendChild(UI.icon('star', 12, '#f59e0b'));
        meta.appendChild(UI.text(ratingNumber.toFixed(1)));
      } else {
        meta.appendChild(UI.text('0 تقييم'));
      }
      if (isVerified) {
        meta.appendChild(
          item.is_verified_blue
            ? UI.icon('verified_blue', 12, '#2196F3')
            : UI.icon('verified_green', 12, '#4CAF50')
        );
      }
      card.appendChild(meta);
      frag.appendChild(card);
    });
    $providersList.textContent = '';
    $providersList.appendChild(frag);
    _startProvidersAutoRotate();
  }


  function _renderProvidersEmpty() {
    if (!$providersList) return;
    _stopProvidersAutoRotate();
    $providersList.textContent = '';
    $providersList.appendChild(
      UI.el('div', { className: 'providers-empty' }, [
        UI.icon('info', 20, '#ddd'),
        UI.el('span', { textContent: 'لا يوجد مختصون مميزون حالياً' }),
      ])
    );
  }

  function _bindProvidersInteraction() {
    if (!$providersList || _providersBound) return;
    _providersBound = true;

    const pause = () => _pauseProvidersAutoRotate();
    const resumeLater = () => _pauseProvidersAutoRotate({ resumeLater: true });

    $providersList.addEventListener('pointerdown', function() { pause(); resumeLater(); }, { passive: true });
    $providersList.addEventListener('touchstart', function() { pause(); resumeLater(); }, { passive: true });
    $providersList.addEventListener('wheel', function() { pause(); resumeLater(); }, { passive: true });
  }

  function _isDesktopHomeGrid() {
    return !!(window.matchMedia && window.matchMedia('(min-width: 1024px)').matches);
  }

  function _syncDesktopHomeBehaviors() {
    _initCategoriesCarousel();
    const isFeaturedSpecialists = !!($providersList && $providersList.classList.contains('featured-specialists-scroll'));
    if (_isDesktopHomeGrid() && !isFeaturedSpecialists) {
      _stopProvidersAutoRotate();
      return;
    }
    const hasEnoughCards = !!($providersList && $providersList.querySelectorAll('.featured-specialist-card').length > 1);
    const hasOverflow = _hasHorizontalOverflow($providersList);

    if (hasEnoughCards && hasOverflow) {
      if (!_providersAutoTimer) {
        _startProvidersAutoRotate();
      }
      return;
    }

    if (_providersAutoTimer) {
      _stopProvidersAutoRotate();
    }
  }

  function _pauseProvidersAutoRotate(options = {}) {
    const resumeLater = !!options.resumeLater;
    _providersPaused = true;
    if (_providersResumeTimer) {
      window.clearTimeout(_providersResumeTimer);
      _providersResumeTimer = null;
    }
    if (!resumeLater) return;
    _providersResumeTimer = window.setTimeout(() => {
      _providersPaused = false;
      _providersResumeTimer = null;
    }, PROVIDERS_RESUME_DELAY_MS);
  }

  function _startProvidersAutoRotate() {
    _stopProvidersAutoRotate();
    if (!$providersList) return;
    const isFeaturedSpecialists = $providersList.classList.contains('featured-specialists-scroll');
    if (_isDesktopHomeGrid() && !isFeaturedSpecialists) return;
    const cards = $providersList.querySelectorAll('.featured-specialist-card');
    if (cards.length <= 1) return;
    if (!_hasHorizontalOverflow($providersList)) return;

    _providersPaused = false;
    _providersAutoTimer = setInterval(() => {
      if (_providersPaused || !$providersList) return;
      const maxScroll = $providersList.scrollWidth - $providersList.clientWidth;
      if (maxScroll <= 0) return;

      const firstCard = $providersList.querySelector('.featured-specialist-card');
      const step = firstCard
        ? Math.round(firstCard.getBoundingClientRect().width + 12)
        : Math.max(96, Math.round($providersList.clientWidth * 0.42));

      const next = $providersList.scrollLeft + step;
      const target = next >= maxScroll - 2 ? 0 : next;
      $providersList.scrollTo({ left: target, behavior: 'smooth' });
    }, FEATURED_SPECIALISTS_ROTATE_MS);
  }

  function _stopProvidersAutoRotate() {
    if (_providersAutoTimer) {
      clearInterval(_providersAutoTimer);
      _providersAutoTimer = null;
    }
    if (_providersResumeTimer) {
      window.clearTimeout(_providersResumeTimer);
      _providersResumeTimer = null;
    }
  }

  function _normalizePortfolioShowcaseItem(rawPromo) {
    if (!rawPromo || typeof rawPromo !== 'object') return null;
    const nested = rawPromo.portfolio_item && typeof rawPromo.portfolio_item === 'object'
      ? rawPromo.portfolio_item
      : null;
    const fileUrl = _readBannerString(
      nested ? nested.file_url : (rawPromo.file_url || rawPromo.target_portfolio_item_file)
    );
    if (!fileUrl) return null;
    return {
      id: _readBannerInt(nested ? nested.id : (rawPromo.id || rawPromo.target_portfolio_item_id)),
      provider_id: _readBannerInt(nested ? nested.provider_id : (rawPromo.provider_id || rawPromo.target_provider_id)),
      provider_display_name: _readBannerString(
        nested ? nested.provider_display_name : (rawPromo.provider_display_name || rawPromo.target_provider_display_name)
      ) || 'مقدم خدمة',
      provider_profile_image: _readBannerString(
        nested ? nested.provider_profile_image : (rawPromo.provider_profile_image || rawPromo.target_provider_profile_image)
      ),
      file_type: _readBannerString(
        nested ? nested.file_type : (rawPromo.file_type || rawPromo.target_portfolio_item_file_type)
      ) || 'image',
      file_url: fileUrl,
      thumbnail_url: _readBannerString(nested ? nested.thumbnail_url : rawPromo.thumbnail_url),
      caption: _readBannerString(nested ? nested.caption : (rawPromo.caption || rawPromo.title)) || 'مشروع',
      redirect_url: _readBannerString(rawPromo.redirect_url),
      likes_count: _readBannerInt(nested ? nested.likes_count : 0),
      saves_count: _readBannerInt(nested ? nested.saves_count : 0),
      is_liked: !!(nested && nested.is_liked),
      is_saved: !!(nested && nested.is_saved),
      source: 'portfolio',
    };
  }

  function _mergePortfolioShowcaseLists(promoItems, feedItems, limit) {
    const merged = [];
    const seenKeys = new Set();
    const maxItems = Math.max(1, Number(limit) || PORTFOLIO_SHOWCASE_LIMIT);

    function pushItem(raw, source) {
      const item = _normalizePortfolioShowcaseItem(raw);
      if (!item) return;
      const key = [
        String(item.provider_id || ''),
        String(item.file_url || item.thumbnail_url || ''),
        String(item.id || 0),
      ].join('|');
      if (!key || seenKeys.has(key)) return;
      seenKeys.add(key);
      merged.push({ raw, source });
    }

    (Array.isArray(promoItems) ? promoItems : []).forEach((raw) => pushItem(raw, 'promo'));
    (Array.isArray(feedItems) ? feedItems : []).forEach((raw) => pushItem(raw, 'feed'));

    const sponsored = merged.filter((row) => row.source === 'promo');
    const organic = _shuffleList(merged.filter((row) => row.source !== 'promo'));
    const result = [];

    for (let i = 0; i < sponsored.length && result.length < maxItems; i += 1) {
      result.push(sponsored[i]);
    }
    for (let i = 0; i < organic.length && result.length < maxItems; i += 1) {
      result.push(organic[i]);
    }

    return result.slice(0, maxItems).map((row) => row.raw);
  }

  function _normalizeSnapshotPromoItem(rawPromo) {
    if (!rawPromo || typeof rawPromo !== 'object') return null;
    const nested = rawPromo.spotlight_item && typeof rawPromo.spotlight_item === 'object'
      ? rawPromo.spotlight_item
      : null;
    const fileUrl = _readBannerString(
      nested ? nested.file_url : rawPromo.target_spotlight_item_file
    );
    if (!fileUrl) return null;
    const rawCaption = _readBannerString(nested ? nested.caption : rawPromo.title).trim();
    const caption = (rawCaption === 'لمحة ممولة' || rawCaption === 'ترويج ممول')
      ? ''
      : rawCaption;
    return {
      id: _readBannerInt(nested ? nested.id : rawPromo.target_spotlight_item_id),
      provider_id: _readBannerInt(nested ? nested.provider_id : rawPromo.target_provider_id),
      provider_display_name: _readBannerString(
        nested ? nested.provider_display_name : rawPromo.target_provider_display_name
      ) || 'مقدم خدمة',
      provider_profile_image: _readBannerString(
        nested ? nested.provider_profile_image : rawPromo.target_provider_profile_image
      ),
      file_type: _readBannerString(
        nested ? nested.file_type : rawPromo.target_spotlight_item_file_type
      ) || 'image',
      file_url: fileUrl,
      thumbnail_url: _readBannerString(nested ? nested.thumbnail_url : ''),
      caption,
      likes_count: _readBannerInt(nested ? nested.likes_count : 0),
      saves_count: _readBannerInt(nested ? nested.saves_count : 0),
      is_liked: !!(nested && nested.is_liked),
      is_saved: !!(nested && nested.is_saved),
      section_title: 'ترويج ممول',
      sponsored_badge_only: true,
      source: 'spotlight',
    };
  }

  function _mergeReelsLists(promoItems, feedItems, limit) {
    const merged = [];
    const seenKeys = new Set();
    const maxItems = Math.max(1, Number(limit) || 16);
    const sortedFeed = (Array.isArray(feedItems) ? feedItems : [])
      .slice()
      .sort((a, b) => {
        const aTime = Date.parse(String((a && a.created_at) || '')) || 0;
        const bTime = Date.parse(String((b && b.created_at) || '')) || 0;
        if (bTime !== aTime) return bTime - aTime;
        return Number((b && b.id) || 0) - Number((a && a.id) || 0);
      });

    function pushItem(item) {
      if (!item || typeof item !== 'object') return;
      const key = [
        String(item.provider_id || ''),
        String(item.file_url || item.thumbnail_url || ''),
        String(item.source || 'spotlight'),
      ].join('|');
      if (!key || seenKeys.has(key)) return;
      seenKeys.add(key);
      merged.push(item);
    }

    (Array.isArray(promoItems) ? promoItems : []).forEach(pushItem);
    sortedFeed.forEach(pushItem);
    return merged.slice(0, maxItems);
  }

  function _renderPortfolioShowcase(placements) {
    if (!$portfolioShowcaseSection || !$portfolioShowcaseList) return;
    const items = (Array.isArray(placements) ? placements : [])
      .map(_normalizePortfolioShowcaseItem)
      .filter(Boolean);
    if (!items.length) {
      $portfolioShowcaseSection.style.display = '';
      _notifySectionShown($portfolioShowcaseSection);
      $portfolioShowcaseList.textContent = '';
      $portfolioShowcaseList.appendChild(
        UI.el('div', {
          className: 'providers-empty',
          textContent: 'لا توجد مشاريع أو بنرات حالياً',
        })
      );
      return;
    }
    $portfolioShowcaseSection.style.display = '';
    _notifySectionShown($portfolioShowcaseSection);

    const frag = document.createDocumentFragment();
    items.forEach((item, index) => {
      const card = UI.el('div', { className: 'showcase-card', role: 'button', tabindex: '0' });
      card.setAttribute('aria-label', item.provider_display_name || item.caption || 'فتح صفحة المزود');
      const media = UI.el('div', { className: 'showcase-media' });
      const thumbUrl = ApiClient.mediaUrl(item.thumbnail_url || item.file_url);
      if (thumbUrl) {
        media.style.setProperty('--showcase-bg-image', 'url("' + thumbUrl + '")');
        const img = UI.el('img', { alt: item.caption || 'مشروع ممول', loading: 'lazy' });
        img.src = thumbUrl;
        media.appendChild(img);
      }
      media.appendChild(UI.el('span', { className: 'showcase-chip', textContent: 'مختار' }));
      if ((item.file_type || '').toLowerCase() === 'video') {
        media.appendChild(UI.el('span', { className: 'showcase-video-badge', textContent: '▶' }));
      }
      card.appendChild(media);

      const openProvider = () => {
        if (typeof NwAnalytics !== 'undefined') {
          NwAnalytics.track('promo.portfolio_showcase_click', {
            surface: 'mobile_web.home.portfolio_showcase',
            source_app: 'promo',
            object_type: 'ProviderProfile',
            object_id: String(item.provider_id || ''),
            payload: {
              media_id: item.id || 0,
              media_type: item.file_type || 'image',
              redirect_url: item.redirect_url || '',
            },
          });
        }
        const redirect = _readBannerString(item.redirect_url);
        if (redirect && /^https?:\/\//i.test(redirect)) {
          window.open(redirect, '_blank', 'noopener');
          return;
        }
        if (item.provider_id) {
          window.location.href = '/provider/' + encodeURIComponent(String(item.provider_id)) + '/';
          return;
        }
        window.location.href = '/search/';
      };
      card.addEventListener('click', openProvider);
      card.addEventListener('keydown', e => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          openProvider();
        }
      });
      frag.appendChild(card);
    });

    $portfolioShowcaseList.textContent = '';
    $portfolioShowcaseList.appendChild(frag);
  }

  function _renderPromoMessage(promo) {
    if (!$promoMessageSection || !$promoMessageCard) return;
    if (!promo || typeof promo !== 'object') {
      $promoMessageSection.style.display = 'none';
      $promoMessageCard.textContent = '';
      return;
    }
    const title = _readBannerString(promo.message_title || promo.title) || 'رسالة دعائية';
    const body = _readBannerString(promo.message_body);
    const redirect = _readBannerString(promo.redirect_url);
    const providerId = _readBannerInt(promo.target_provider_id);

    $promoMessageSection.style.display = '';
    _notifySectionShown($promoMessageSection);
    $promoMessageCard.textContent = '';
    const chip = UI.el('span', { className: 'sponsor-chip', textContent: 'رسالة دعائية' });
    const headline = UI.el('div', { className: 'sponsor-title', textContent: title });
    const message = UI.el('div', { className: 'sponsor-body', textContent: body || 'عرض جديد مخصص لك.' });
    const action = UI.el('a', { className: 'ghost-btn', href: '#', textContent: 'عرض التفاصيل' });
    action.addEventListener('click', (event) => {
      event.preventDefault();
      if (redirect) {
        window.open(redirect, '_blank', 'noopener');
        return;
      }
      if (providerId > 0) {
        window.location.href = '/provider/' + encodeURIComponent(String(providerId)) + '/';
      }
    });
    $promoMessageCard.appendChild(chip);
    $promoMessageCard.appendChild(headline);
    $promoMessageCard.appendChild(message);
    $promoMessageCard.appendChild(action);
  }

  function _renderHeroBannerEmptyState() {
    if (!$carouselTrack) return;
    $carouselTrack.textContent = '';
    $carouselTrack.appendChild(
      UI.el('div', {
        className: 'hero-banner-empty',
        textContent: 'لا توجد بنرات نشطة حالياً',
      })
    );
  }

  /* ----------------------------------------------------------
     RENDER: BANNERS CAROUSEL
     Full-width auto-rotating carousel with images & videos.
      Auto-rotates every 3 seconds. Supports swipe on mobile.
  ---------------------------------------------------------- */
  function _renderBanners(banners) {
    if (!$carouselTrack || !$bannersSection) return;
    var heroEl = document.getElementById('hero');
    var heroSkel = document.getElementById('hero-skeleton');
    if (!banners.length) {
      $bannersSection.style.display = '';
      _carouselItems = [];
      _carouselIdx = 0;
      _stopCarouselAutoRotate();
      _renderHeroBannerEmptyState();
      if ($carouselDots) $carouselDots.textContent = '';
      if ($carouselPrev) $carouselPrev.style.display = 'none';
      if ($carouselNext) $carouselNext.style.display = 'none';
      if (heroEl) heroEl.classList.add('hero--no-banners');
      if (heroSkel) heroSkel.style.display = 'none';
      return;
    }
    $bannersSection.style.display = '';
    if (heroEl) heroEl.classList.remove('hero--no-banners');
    if (heroSkel) heroSkel.style.display = 'none';

    _carouselItems = banners;
    _carouselIdx = 0;

    // Build slides
    const frag = document.createDocumentFragment();
    banners.forEach((b, i) => {
      const slide = UI.el('div', { className: 'carousel-slide' + (i === 0 ? ' active' : '') });
      slide.setAttribute('data-index', String(i));

      const url = ApiClient.mediaUrl(b.media_url);
      const isVideo = (b.media_type || '').toLowerCase() === 'video';

      if (url) {
        slide.appendChild(_buildCarouselMedia(b, url, isVideo, i === 0));
      }

      // Gradient overlay (no text — keeps background-readable gradient without captions)
      slide.appendChild(UI.el('div', { className: 'carousel-overlay' }));

      // Link wrapper
      if (b.link_url) {
        slide.style.cursor = 'pointer';
        slide.addEventListener('click', () => {
          if (typeof NwAnalytics !== 'undefined' && _isTrackableBanner(b)) {
            NwAnalytics.track('promo.banner_click', {
              surface: 'mobile_web.home.carousel',
              source_app: 'promo',
              object_type: 'ProviderProfile',
              object_id: String(b.provider_id || ''),
              payload: {
                banner_id: b.id || 0,
                redirect_url: b.link_url,
                media_type: b.media_type || 'image',
              },
            });
          }
          window.open(b.link_url, '_blank', 'noopener');
        });
      } else if (b.provider_id && b.provider_id > 0) {
        slide.style.cursor = 'pointer';
        slide.addEventListener('click', () => {
          if (typeof NwAnalytics !== 'undefined' && _isTrackableBanner(b)) {
            NwAnalytics.track('promo.banner_click', {
              surface: 'mobile_web.home.carousel',
              source_app: 'promo',
              object_type: 'ProviderProfile',
              object_id: String(b.provider_id || ''),
              payload: {
                banner_id: b.id || 0,
                media_type: b.media_type || 'image',
              },
            });
          }
          window.location.href = '/provider/' + b.provider_id + '/';
        });
      }

      frag.appendChild(slide);
    });
    $carouselTrack.textContent = '';
    $carouselTrack.appendChild(frag);
    $carouselTrack.querySelectorAll('.carousel-media-frame').forEach((frame, i) => {
      frame.setAttribute('data-banner-index', String(i));
    });
    _applyResponsiveBannerScales();
    _syncCarouselSlideMedia($carouselTrack.querySelector('.carousel-slide.active'), true);
    if (typeof NwAnalytics !== 'undefined' && _isTrackableBanner(banners[0])) {
      NwAnalytics.trackOnce(
        'promo.banner_impression',
        {
          surface: 'mobile_web.home.carousel',
          source_app: 'promo',
          object_type: 'ProviderProfile',
          object_id: String(banners[0].provider_id || ''),
          payload: {
            banner_id: banners[0].id || 0,
            media_type: banners[0].media_type || 'image',
          },
        },
        'promo.banner_impression:mobile_web.home:' + String(banners[0].id || 0)
      );
    }

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
    } else {
      if ($carouselPrev) $carouselPrev.style.display = '';
      if ($carouselNext) $carouselNext.style.display = '';
      if ($carouselDots) $carouselDots.style.display = '';
    }

    // Swipe support
    _bindCarouselSwipe();
    _bindCarouselResize();

    // Start auto-rotate
    _startCarouselAutoRotate();
  }

  function _goToSlide(idx, opts = {}) {
    if (!_carouselItems.length) return;
    const restartTimer = opts.restartTimer !== false;
    _detachCarouselVideoEndedHook();
    const slides = $carouselTrack.querySelectorAll('.carousel-slide');
    const dots = $carouselDots ? $carouselDots.querySelectorAll('.carousel-dot') : [];

    // Pause current video
    const currentSlide = slides[_carouselIdx];
    if (currentSlide) {
      _syncCarouselSlideMedia(currentSlide, false);
      currentSlide.classList.remove('active');
    }
    if (dots[_carouselIdx]) dots[_carouselIdx].classList.remove('active');

    _carouselIdx = idx;

    // Activate new slide
    const newSlide = slides[_carouselIdx];
    if (newSlide) {
      newSlide.classList.add('active');
      _syncCarouselSlideMedia(newSlide, true);
    }
    if (dots[_carouselIdx]) dots[_carouselIdx].classList.add('active');
    if (restartTimer) _startCarouselAutoRotate();
    if (typeof NwAnalytics !== 'undefined' && _isTrackableBanner(_carouselItems[_carouselIdx])) {
      const banner = _carouselItems[_carouselIdx];
      NwAnalytics.trackOnce(
        'promo.banner_impression',
        {
          surface: 'mobile_web.home.carousel',
          source_app: 'promo',
          object_type: 'ProviderProfile',
          object_id: String(banner.provider_id || ''),
          payload: {
            banner_id: banner.id || 0,
            media_type: banner.media_type || 'image',
          },
        },
        'promo.banner_impression:mobile_web.home:' + String(banner.id || 0)
      );
    }
  }

  function _resolveCarouselSlideDurationMs(banner) {
    if (!banner || (banner.media_type || '').toLowerCase() !== 'video') {
      return CAROUSEL_IMAGE_ROTATE_MS;
    }

    let durationSeconds = Number(banner.duration_seconds);
    if (!(Number.isFinite(durationSeconds) && durationSeconds > 0) && $carouselTrack) {
      const activeSlide = $carouselTrack.querySelector('.carousel-slide.active');
      const videoEl = activeSlide ? activeSlide.querySelector('video.carousel-media-video') : null;
      if (videoEl && Number.isFinite(videoEl.duration) && videoEl.duration > 0) {
        durationSeconds = Number(videoEl.duration);
      }
    }

    if (!(Number.isFinite(durationSeconds) && durationSeconds > 0)) {
      return CAROUSEL_VIDEO_FALLBACK_ROTATE_MS;
    }

    const rawMs = Math.round(durationSeconds * 1000);
    return Math.max(1000, rawMs);
  }

  function _advanceCarouselToNextSlide() {
    if (_carouselItems.length <= 1) return;
    _goToSlide((_carouselIdx + 1) % _carouselItems.length, { restartTimer: false });
    _startCarouselAutoRotate();
  }

  function _startCarouselAutoRotate() {
    _stopCarouselAutoRotate();
    if (_carouselItems.length <= 1 || !$carouselTrack) return;

    const banner = _carouselItems[_carouselIdx];
    const isVideo = String(banner && banner.media_type || '').toLowerCase() === 'video';
    if (!isVideo) {
      _carouselTimer = setTimeout(() => {
        if (_carouselPaused) {
          _startCarouselAutoRotate();
          return;
        }
        _advanceCarouselToNextSlide();
      }, CAROUSEL_IMAGE_ROTATE_MS);
      return;
    }

    const activeSlide = $carouselTrack.querySelector('.carousel-slide.active');
    const videoEl = activeSlide ? activeSlide.querySelector('video.carousel-media-video') : null;
    if (!videoEl) {
      const delayMs = _resolveCarouselSlideDurationMs(banner);
      _carouselTimer = setTimeout(() => {
        if (_carouselPaused) {
          _startCarouselAutoRotate();
          return;
        }
        _advanceCarouselToNextSlide();
      }, delayMs);
      return;
    }

    const handleEnded = () => {
      if (_carouselPaused) {
        _carouselTimer = setTimeout(handleEnded, 350);
        return;
      }
      _advanceCarouselToNextSlide();
    };
    _carouselActiveVideoEl = videoEl;
    _carouselActiveVideoEndedHandler = handleEnded;
    videoEl.addEventListener('ended', handleEnded, { once: true });

    // Safety fallback if a browser never emits "ended" for any transient reason.
    const delayMs = _resolveCarouselSlideDurationMs(banner) + 1000;
    _carouselTimer = setTimeout(handleEnded, delayMs);
  }

  function _stopCarouselAutoRotate() {
    if (_carouselTimer) {
      clearTimeout(_carouselTimer);
      _carouselTimer = null;
    }
    _detachCarouselVideoEndedHook();
  }

  function _bindCarouselSwipe() {
    if (!$carouselTrack || _carouselBound) return;
    _carouselBound = true;
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
    // Stop existing sequential timer
    _stopAutoScroll();
    _reelsActiveIdx = 0;

    const frag = document.createDocumentFragment();

    items.forEach((item, idx) => {
      const thumb = ApiClient.mediaUrl(item.thumbnail_url || item.file_url || '');
      const mediaUrl = ApiClient.mediaUrl(item.file_url || '');
      const isVideo = String(item.file_type || '').toLowerCase() === 'video' && !!mediaUrl;
      const caption = item.sponsored_badge_only
        ? ((item.section_title || '').trim() || 'ترويج ممول')
        : ((item.caption || '').trim() || 'لمحة');

      // Always a div — click opens SpotlightViewer, NOT provider page
      const reel = UI.el('div', {
        className: 'reel-item',
        role: 'button',
        tabindex: '0',
      });

      const ring = UI.el('div', { className: 'reel-ring' });
      const inner = UI.el('div', { className: 'reel-inner' });

      if (isVideo) {
        const preview = UI.el('video', {
          className: 'reel-preview-video',
          preload: 'metadata',
          muted: true,
          playsinline: true,
          tabindex: '-1',
          'aria-hidden': 'true',
        });
        preview.src = mediaUrl;
        preview.muted = true;   // explicit DOM property — required for some browsers
        preview.volume = 0;     // belt-and-suspenders: zero volume before any play()
        preview.loop = false;
        preview.setAttribute('playsinline', '');
        preview.setAttribute('disablepictureinpicture', '');
        if (thumb) preview.poster = thumb;
        inner.appendChild(preview);
      } else if (thumb) {
        inner.appendChild(UI.lazyImg(thumb, caption));
      } else {
        inner.appendChild(UI.el('div', { className: 'reel-placeholder' }));
      }

      ring.appendChild(inner);
      reel.appendChild(ring);
      reel.appendChild(UI.el('div', { className: 'reel-caption', textContent: caption }));
      reel.setAttribute('data-reel-index', String(idx));

      // Click → open SpotlightViewer at this index
      reel.addEventListener('click', () => {
        if (typeof SpotlightViewer !== 'undefined') {
          SpotlightViewer.open(_reelsData, idx, {
            source: 'spotlight',
            label: 'لمحة',
            immersive: true,
            tiktokMode: true,
          });
        }
      });
      reel.addEventListener('keydown', e => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          if (typeof SpotlightViewer !== 'undefined') {
            SpotlightViewer.open(_reelsData, idx, {
              source: 'spotlight',
              label: 'لمحة',
              immersive: true,
              tiktokMode: true,
            });
          }
        }
      });

      frag.appendChild(reel);
    });

    $reelsTrack.textContent = '';
    $reelsTrack.appendChild(frag);
    _setActiveReel(0, { scroll: false });

    // Start sequential previews (active center reel only).
    _startAutoScroll();
  }

  function _renderReelsEmpty() {
    if (!$reelsTrack) return;
    _stopAutoScroll();
    _reelsActiveIdx = 0;
    $reelsTrack.textContent = '';
    $reelsTrack.appendChild(
      UI.el('div', { className: 'reels-empty', textContent: 'لا توجد لمحات حالياً' })
    );
  }

  /* ----------------------------------------------------------
     REELS AUTO-PREVIEW (play active center reel, advance on end)
   ---------------------------------------------------------- */
  function _detachReelVideoEndedHook() {
    if (_reelsActiveVideoEl && _reelsActiveVideoEndedHandler) {
      _reelsActiveVideoEl.removeEventListener('ended', _reelsActiveVideoEndedHandler);
    }
    _reelsActiveVideoEl = null;
    _reelsActiveVideoEndedHandler = null;
  }

  function _setActiveReel(index, options = {}) {
    if (!$reelsTrack) return;
    const reels = Array.from($reelsTrack.querySelectorAll('.reel-item'));
    if (!reels.length) return;

    const normalized = ((index % reels.length) + reels.length) % reels.length;
    _reelsActiveIdx = normalized;

    reels.forEach((reel, idx) => {
      const isActive = idx === normalized;
      reel.classList.toggle('is-active', isActive);

      reel.querySelectorAll('video').forEach(video => {
        video.muted = true; // enforce mute on preview — audio opens only in SpotlightViewer
        if (isActive) {
          const playPromise = video.play();
          if (playPromise && typeof playPromise.catch === 'function') {
            playPromise.catch(() => {});
          }
        } else {
          video.pause();
          try { video.currentTime = 0; } catch (_) {}
        }
      });
    });

    if (options.scroll === false) return;
    const activeReel = reels[normalized];
    _scrollReelInline(activeReel, { behavior: 'smooth' });
  }

  function _scrollReelInline(reelEl, options = {}) {
    if (!$reelsTrack || !reelEl) return;
    const behavior = options.behavior || 'smooth';
    const containerRect = $reelsTrack.getBoundingClientRect();
    const reelRect = reelEl.getBoundingClientRect();
    const deltaX = (reelRect.left - containerRect.left) - ((containerRect.width - reelRect.width) / 2);
    const targetLeft = $reelsTrack.scrollLeft + deltaX;
    $reelsTrack.scrollTo({ left: Math.max(0, targetLeft), behavior });
  }

  function _bindReelsInteraction() {
    if (!$reelsTrack || _reelsBound) return;
    _reelsBound = true;

    const pause = () => { _reelsPaused = true; };
    const resume = () => { window.setTimeout(() => { _reelsPaused = false; }, 500); };

    $reelsTrack.addEventListener('pointerdown', pause, { passive: true });
    $reelsTrack.addEventListener('pointerup', resume, { passive: true });
    $reelsTrack.addEventListener('pointercancel', resume, { passive: true });
    $reelsTrack.addEventListener('mouseenter', pause, { passive: true });
    $reelsTrack.addEventListener('mouseleave', resume, { passive: true });
  }

  function _advanceReelToNext() {
    if (!$reelsTrack) return;
    const count = $reelsTrack.querySelectorAll('.reel-item').length;
    if (count <= 1) return;
    _setActiveReel(_reelsActiveIdx + 1);
    _startAutoScroll();
  }

  function _startAutoScroll() {
    _stopAutoScroll();
    if (!$reelsTrack) return;
    const count = $reelsTrack.querySelectorAll('.reel-item').length;
    if (count <= 1) return;
    _reelsPaused = false;
    _detachReelVideoEndedHook();

    const reels = Array.from($reelsTrack.querySelectorAll('.reel-item'));
    const activeReel = reels[_reelsActiveIdx] || null;
    const activeVideo = activeReel ? activeReel.querySelector('video.reel-preview-video') : null;

    if (!activeVideo) {
      _reelsAutoTimer = setTimeout(() => {
        if (_reelsPaused) {
          _startAutoScroll();
          return;
        }
        _advanceReelToNext();
      }, REELS_IMAGE_ROTATE_MS);
      return;
    }

    const handleEnded = () => {
      if (_reelsPaused) {
        _reelsAutoTimer = setTimeout(handleEnded, 350);
        return;
      }
      _advanceReelToNext();
    };

    _reelsActiveVideoEl = activeVideo;
    _reelsActiveVideoEndedHandler = handleEnded;
    activeVideo.addEventListener('ended', handleEnded, { once: true });

    const durationMs = Number.isFinite(activeVideo.duration) && activeVideo.duration > 0
      ? Math.max(1000, Math.round(activeVideo.duration * 1000))
      : REELS_VIDEO_FALLBACK_ROTATE_MS;

    // Safety fallback in case `ended` does not fire.
    _reelsAutoTimer = setTimeout(handleEnded, durationMs + 1000);
  }

  function _stopAutoScroll() {
    if (_reelsAutoTimer) {
      clearTimeout(_reelsAutoTimer);
      _reelsAutoTimer = null;
    }
    _detachReelVideoEndedHook();
  }

  /* ----------------------------------------------------------
     HELPERS
  ---------------------------------------------------------- */
  function _updateSubtitle(count) {
    // hero text removed — no-op
  }

  function _applyHomeContent() {
    if ($categoriesTitle) {
      $categoriesTitle.textContent = _homeContent.categoriesTitle || 'التصنيفات';
    }
    if ($providersTitle) {
      $providersTitle.textContent = _homeContent.providersTitle || 'أبرز المختصين';
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
    const mediaUrl = asset ? ApiClient.mediaUrl(asset.file || asset.file_url) : null;
    const mediaType = String((asset && asset.file_type) || 'image').toLowerCase();
    const redirectUrl = promo.redirect_url || '';
    const title = promo.title || '';
    const providerId = promo.target_provider_id ? String(promo.target_provider_id) : '';
    const providerHref = providerId ? ('/provider/' + encodeURIComponent(providerId) + '/') : '';
    if (typeof NwAnalytics !== 'undefined') {
      NwAnalytics.trackOnce(
        'promo.popup_open',
        {
          surface: 'mobile_web.home.popup',
          source_app: 'promo',
          object_type: 'ProviderProfile',
          object_id: providerId,
          payload: {
            title: title,
            redirect_url: redirectUrl,
            media_type: mediaType,
          },
        },
        'promo.popup_open:mobile_web.home:' + providerId + ':' + title
      );
    }

    const overlay = UI.el('div', { className: 'promo-popup-overlay' });
    const modal = UI.el('div', { className: 'promo-popup-modal' });

    const closeBtn = UI.el('button', { className: 'promo-popup-close', textContent: '✕', type: 'button' });
    closeBtn.setAttribute('aria-label', 'إغلاق');
    closeBtn.addEventListener('click', () => overlay.remove());
    modal.appendChild(closeBtn);

    if (mediaUrl) {
      const media = mediaType === 'video'
        ? UI.el('video', {
            className: 'promo-popup-media promo-popup-video',
            autoplay: true,
            loop: true,
            muted: true,
            playsinline: true,
          })
        : UI.el('img', { className: 'promo-popup-media promo-popup-img', alt: title });
      media.src = mediaUrl;
      if (mediaType === 'video') {
        media.setAttribute('playsinline', 'playsinline');
        media.setAttribute('aria-label', title || 'فيديو ترويجي');
      }
      const href = redirectUrl || providerHref;
      if (href) {
        const link = UI.el('a', { href, className: 'promo-popup-media-link' });
        if (redirectUrl) {
          link.target = '_blank';
          link.rel = 'noopener';
        }
        link.addEventListener('click', () => {
          if (typeof NwAnalytics === 'undefined') return;
          NwAnalytics.track('promo.popup_click', {
            surface: 'mobile_web.home.popup',
            source_app: 'promo',
            object_type: 'ProviderProfile',
            object_id: providerId,
            payload: {
              title: title,
              redirect_url: redirectUrl,
            },
          });
        });
        link.appendChild(media);
        modal.appendChild(link);
      } else {
        modal.appendChild(media);
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
