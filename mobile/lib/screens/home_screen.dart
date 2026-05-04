// ignore_for_file: unused_field, unused_element
import 'dart:async';
import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/app_theme.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/custom_drawer.dart';
import '../services/api_client.dart';
import '../services/analytics_service.dart';
import '../services/app_logger.dart';
import '../services/home_service.dart';
import '../models/category_model.dart';
import '../models/banner_model.dart';
import '../models/featured_specialist_model.dart';
import '../models/provider_public_model.dart';
import '../models/media_item_model.dart';
import '../widgets/promo_banner_widget.dart';
import '../widgets/promo_media_tile.dart';
import '../widgets/platform_top_bar.dart';
import '../widgets/provider_name_with_badges.dart';
import '../widgets/spotlight_viewer.dart';
import '../services/content_service.dart';
import '../services/unread_badge_service.dart';
import '../services/auth_service.dart';

import 'search_provider_screen.dart';
import 'provider_profile_screen.dart';
import 'notifications_screen.dart';
import 'my_chats_screen.dart';
import 'signup_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // -- Data --
  List<CategoryModel> _categories = [];
  List<ProviderPublicModel> _providers = [];
  List<FeaturedSpecialistModel> _featuredSpecialists = [];
  List<BannerModel> _banners = [];
  List<MediaItemModel> _spotlights = [];
  HomeScreenContent _content = HomeScreenContent.empty();
  bool _isCategoriesLoading = true;
  bool _isBannersLoading = true;
  bool _isSpotlightsLoading = true;
  bool _isFeaturedLoading = true;
  bool _isPortfolioShowcaseLoading = true;
  int _notificationUnread = 0;
  int _chatUnread = 0;
  bool _promoPopupShown = false;
  List<MediaItemModel> _portfolioShowcase = [];
  List<Map<String, dynamic>> _portfolioShowcasePlacements = [];
  Map<String, dynamic>? _promoMessagePlacement;
  final Set<int> _seenBannerImpressions = <int>{};
  String? _syncMessage;
  _HomeSyncTone _syncTone = _HomeSyncTone.info;
  int _activeReelIndex = 0;

  // -- Banner carousel --
  final PageController _bannerPageController = PageController();
  Timer? _bannerAutoTimer;
  Timer? _bannersSyncTimer;
  int _bannerCurrentPage = 0;
  static const Duration _imageBannerRotateDelay = Duration(seconds: 5);
  static const Duration _bannerSyncInterval = Duration(minutes: 1);

  // -- Reels auto scroll --
  final ScrollController _categoriesScroll = ScrollController();
  final ScrollController _reelsScroll = ScrollController();
  final ScrollController _featuredSpecialistsScroll = ScrollController();
  final ScrollController _portfolioShowcaseScroll = ScrollController();
  Timer? _categoriesAutoTimer;
  Timer? _categoriesResumeTimer;
  Timer? _reelsTimer;
  Timer? _reelsResumeTimer;
  Timer? _featuredSpecialistsTimer;
  Timer? _featuredSpecialistsResumeTimer;
  Timer? _portfolioShowcaseTimer;
  Timer? _portfolioShowcaseResumeTimer;
  ValueListenable<UnreadBadges>? _badgeListenable;
  double _categoriesPos = 0;
  double _reelsPos = 0;
  double _featuredSpecialistsPos = 0;
  double _portfolioShowcasePos = 0;
  bool _categoriesAutoPaused = false;
  bool _reelsAutoPaused = false;
  bool _featuredSpecialistsAutoPaused = false;
  bool _portfolioShowcaseAutoPaused = false;
  static const Duration _categoriesTickInterval = Duration(milliseconds: 30);
  static const Duration _categoriesResumeDelay = Duration(milliseconds: 2500);
  static const Duration _reelsResumeDelay = Duration(seconds: 3);
  static const Duration _featuredSpecialistsResumeDelay = Duration(seconds: 3);
  static const Duration _featuredSpecialistsRotateDelay = Duration(seconds: 5);
  static const Duration _portfolioShowcaseResumeDelay = Duration(seconds: 3);
  static const Duration _portfolioShowcaseRotateDelay = Duration(seconds: 5);
  static const int _homeBannersLimit = 16;
  static const int _portfolioShowcaseLimit = 16;
  static const int _portfolioShowcaseFetchLimit = 40;
  static const double _reelItemExtent = 76;

  static const _reelFallbackLogos = [
    'assets/images/32.jpeg',
    'assets/images/841015.jpeg',
    'assets/images/879797.jpeg',
  ];

  List<BannerModel> get _heroBanners {
    if (_banners.isNotEmpty) return _banners;
    final fallbackBanner = _content.fallbackBanner;
    if (fallbackBanner == null) return const <BannerModel>[];
    return <BannerModel>[fallbackBanner];
  }

  List<FeaturedSpecialistModel> get _visibleFeaturedSpecialists {
    final seenProviderIds = <int>{};
    final merged = <FeaturedSpecialistModel>[];

    for (final specialist in _featuredSpecialists) {
      if (specialist.providerId <= 0 ||
          !seenProviderIds.add(specialist.providerId)) {
        continue;
      }
      merged.add(specialist);
      if (merged.length >= 10) {
        return merged;
      }
    }

    for (final provider in _topRatedProviders(_providers)) {
      if (provider.id <= 0 || !seenProviderIds.add(provider.id)) {
        continue;
      }
      merged.add(_providerToFeaturedSpecialist(provider));
      if (merged.length >= 10) {
        break;
      }
    }

    return merged;
  }

  @override
  void initState() {
    super.initState();
    _redirectIfCompletionPending();
    final seeded = _seedFromCachedData();
    _loadHomeContent();
    _loadData(showLoader: !seeded);
    _startBannerSync();
    _startCategoriesAutoScroll();
    _startReelsScroll();
    _badgeListenable = UnreadBadgeService.acquire();
    _badgeListenable!.addListener(_handleBadgeChange);
    _handleBadgeChange();
    _reelsScroll.addListener(_handleReelsScroll);
    UnreadBadgeService.refresh(force: true);
  }

  Future<void> _redirectIfCompletionPending() async {
    final loggedIn = await AuthService.isLoggedIn();
    if (!loggedIn) return;
    final needsCompletion = await AuthService.needsCompletion();
    if (!mounted || !needsCompletion) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const SignUpScreen()),
      );
    });
  }

  bool _seedFromCachedData() {
    final cached = HomeService.getCachedHomeData(
      providersLimit: 10,
      bannersLimit: _homeBannersLimit,
      spotlightsLimit: 16,
    );
    if (!cached.hasAnyData) return false;

    _categories = cached.categories;
    _providers = cached.providers;
    _banners = cached.banners;
    _spotlights = cached.spotlights;
    _isCategoriesLoading = cached.categories.isEmpty;
    _isBannersLoading = cached.banners.isEmpty;
    _isSpotlightsLoading = cached.spotlights.isEmpty;
    _isFeaturedLoading = cached.providers.isEmpty;
    return true;
  }

  Future<void> _loadData({
    bool forceRefresh = false,
    bool showLoader = true,
  }) async {
    if (showLoader && mounted) {
      setState(() {
        _isCategoriesLoading = _categories.isEmpty;
        _isBannersLoading = _heroBanners.isEmpty;
        _isSpotlightsLoading = _spotlights.isEmpty;
        _isFeaturedLoading = _visibleFeaturedSpecialists.isEmpty;
      });
    }

    final categoriesFuture =
        HomeService.fetchCategoriesResult(forceRefresh: forceRefresh);
    final providersFuture = HomeService.fetchFeaturedProvidersResult(
      limit: 10,
      forceRefresh: forceRefresh,
    );
    final bannersFuture = HomeService.fetchHomeBannersResult(
      limit: _homeBannersLimit,
      forceRefresh: forceRefresh,
    );
    final spotlightsFuture = HomeService.fetchSpotlightFeedResult(
      limit: 16,
      forceRefresh: forceRefresh,
    );
    final featuredSpecialistsFuture =
        HomeService.fetchFeaturedSpecialistsResult(
      limit: 10,
      forceRefresh: forceRefresh,
    );

    // Fetch promo placements (non-blocking)
    if (!_promoPopupShown) _loadPromoPopup();
    _loadPromoPortfolioShowcase();
    _loadPromoMessages();

    categoriesFuture.then((result) {
      if (!mounted) return;
      setState(() {
        _categories = result.data;
        _isCategoriesLoading = false;
      });
      _startCategoriesAutoScroll();
    }).catchError((_) {
      if (!mounted) return;
      setState(() => _isCategoriesLoading = false);
    });

    bannersFuture.then((result) {
      final banners = result.data;
      if (!mounted) return;
      setState(() {
        _banners = banners;
        _isBannersLoading = false;
      });
      _startBannerAutoRotate();
      if (banners.isNotEmpty) {
        _trackBannerImpression(
          banners.first,
          surface: 'flutter.home.hero_initial',
        );
      }
    }).catchError((_) {
      if (!mounted) return;
      setState(() => _isBannersLoading = false);
    });

    spotlightsFuture.then((result) {
      final spotlights = result.data;
      if (!mounted) return;
      setState(() {
        _spotlights = spotlights;
        _isSpotlightsLoading = false;
      });
    }).catchError((_) {
      if (!mounted) return;
      setState(() => _isSpotlightsLoading = false);
    });

    try {
      final providersResult = await providersFuture;
      final featuredSpecialistsResult = await featuredSpecialistsFuture;
      if (!mounted) return;
      setState(() {
        _providers = providersResult.data;
        _featuredSpecialists = featuredSpecialistsResult.data;
        _isFeaturedLoading = false;
      });
      _startFeaturedSpecialistsAutoRotate();
    } catch (error, stackTrace) {
      AppLogger.warn(
        'HomeScreen failed while loading featured specialists',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() => _isFeaturedLoading = false);
    }

    final categoriesResult = await categoriesFuture.catchError(
      (_) => const CachedFetchResult<List<CategoryModel>>(
        data: <CategoryModel>[],
        source: 'empty',
        errorMessage: 'تعذر تحميل التصنيفات',
        statusCode: 0,
      ),
    );
    final providersResult = await providersFuture.catchError(
      (_) => const CachedFetchResult<List<ProviderPublicModel>>(
        data: <ProviderPublicModel>[],
        source: 'empty',
        errorMessage: 'تعذر تحميل المختصين',
        statusCode: 0,
      ),
    );
    final featuredSpecialistsResult =
        await featuredSpecialistsFuture.catchError(
      (_) => const CachedFetchResult<List<FeaturedSpecialistModel>>(
        data: <FeaturedSpecialistModel>[],
        source: 'empty',
        errorMessage: 'تعذر تحميل المختصين المميزين',
        statusCode: 0,
      ),
    );
    final bannersResult = await bannersFuture.catchError(
      (_) => const CachedFetchResult<List<BannerModel>>(
        data: <BannerModel>[],
        source: 'empty',
        errorMessage: 'تعذر تحميل البانرات',
        statusCode: 0,
      ),
    );
    final spotlightsResult = await spotlightsFuture.catchError(
      (_) => const CachedFetchResult<List<MediaItemModel>>(
        data: <MediaItemModel>[],
        source: 'empty',
        errorMessage: 'تعذر تحميل اللمحات',
        statusCode: 0,
      ),
    );
    if (!mounted) return;
    _updateHomeSyncNotice([
      categoriesResult,
      providersResult,
      featuredSpecialistsResult,
      bannersResult,
      spotlightsResult,
    ]);
  }

  void _startBannerSync() {
    _bannersSyncTimer?.cancel();
    _bannersSyncTimer = Timer.periodic(_bannerSyncInterval, (_) {
      _syncHomeBanners();
    });
  }

  String _bannerSyncSignature(BannerModel banner) {
    return [
      banner.id,
      banner.mediaUrl ?? '',
      banner.mediaType,
      banner.linkUrl ?? '',
      banner.displayOrder,
      banner.durationSeconds ?? 0,
      banner.mobileScale,
      banner.tabletScale,
      banner.desktopScale,
    ].join('|');
  }

  bool _bannerListChanged(List<BannerModel> current, List<BannerModel> next) {
    if (current.length != next.length) return true;
    for (var i = 0; i < current.length; i += 1) {
      if (_bannerSyncSignature(current[i]) != _bannerSyncSignature(next[i])) {
        return true;
      }
    }
    return false;
  }

  Future<void> _syncHomeBanners() async {
    try {
      final latest = await HomeService.fetchHomeBanners(
        limit: _homeBannersLimit,
        forceRefresh: true,
      );
      if (!mounted) return;
      if (!_bannerListChanged(_banners, latest)) {
        return;
      }
      setState(() => _banners = latest);
      _startBannerAutoRotate();
      if (latest.isNotEmpty) {
        _trackBannerImpression(
          latest.first,
          surface: 'flutter.home.hero_auto_sync',
        );
      }
    } catch (error, stackTrace) {
      AppLogger.warn(
        'HomeScreen banner sync failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _loadPromoPopup() async {
    try {
      final promo = await HomeService.fetchPromoByAdType(
        adType: 'popup_home',
        limit: 1,
      );
      if (!mounted || promo == null) return;
      final assets = (promo['assets'] as List?) ?? [];
      final asset =
          assets.isNotEmpty ? assets[0] as Map<String, dynamic> : null;
      final mediaUrl = asset == null
          ? null
          : ApiClient.buildMediaUrl(
              (asset['file'] ?? asset['file_url']) as String?);
      final mediaType =
          ((asset?['file_type'] as String?) ?? 'image').trim().toLowerCase();
      final title = (promo['title'] as String?) ?? '';
      final redirectUrl = (promo['redirect_url'] as String?)?.trim();
      final providerIdRaw = promo['target_provider_id'];
      final providerId =
          providerIdRaw is int ? providerIdRaw : int.tryParse('$providerIdRaw');
      final providerName =
          promo['target_provider_display_name'] as String? ?? 'مقدم خدمة';

      if (mediaUrl == null) return;
      AnalyticsService.trackFireAndForget(
        eventName: 'promo.popup_open',
        surface: 'flutter.home.popup',
        sourceApp: 'promo',
        objectType: 'ProviderProfile',
        objectId: (providerId ?? 0).toString(),
        dedupeKey:
            'promo.popup_open:flutter.home:${providerId ?? 0}:${title.trim()}',
        payload: {
          'redirect_url': redirectUrl ?? '',
          'media_type': mediaType,
          'title': title,
        },
      );
      _promoPopupShown = true;
      await _showPromoPopupDialog(
        mediaUrl: mediaUrl,
        mediaType: mediaType == 'video' ? 'video' : 'image',
        title: title,
        redirectUrl: redirectUrl,
        providerId: providerId,
        providerName: providerName,
      );
    } catch (error, stackTrace) {
      AppLogger.warn(
        'HomeScreen failed to load popup promo',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _loadPromoPortfolioShowcase() async {
    if (mounted && _portfolioShowcase.isEmpty) {
      setState(() => _isPortfolioShowcaseLoading = true);
    }
    try {
      final promoItems = await HomeService.fetchPromoActiveRows(
        serviceType: 'portfolio_showcase',
        limit: _portfolioShowcaseFetchLimit,
      );
      final feedItems = await HomeService.fetchPortfolioFeedRows(
        limit: _portfolioShowcaseFetchLimit,
      );
      if (!mounted) return;

      final promoMedia = <MediaItemModel>[];
      final promoPlacements = <Map<String, dynamic>>[];
      for (final placement in promoItems) {
        final parsed = _portfolioItemFromPromoPlacement(placement);
        if (parsed == null) continue;
        promoMedia.add(parsed);
        promoPlacements.add(placement);
      }

      final organicMedia = <MediaItemModel>[];
      for (final row in feedItems) {
        try {
          organicMedia.add(
            MediaItemModel.fromJson(
              row,
              source: MediaItemSource.portfolio,
            ),
          );
        } catch (error, stackTrace) {
          AppLogger.warn(
            'HomeScreen skipped malformed portfolio feed row',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }

      final merged = _mergePortfolioShowcaseSources(
        promoMedia: promoMedia,
        promoPlacements: promoPlacements,
        organicMedia: organicMedia,
        limit: _portfolioShowcaseLimit,
      );
      if (!mounted) return;
      setState(() {
        _portfolioShowcasePlacements = merged.placements;
        _portfolioShowcase = merged.media;
        _isPortfolioShowcaseLoading = false;
      });
      _startPortfolioShowcaseAutoRotate();
    } catch (error, stackTrace) {
      AppLogger.warn(
        'HomeScreen failed to load portfolio showcase',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() => _isPortfolioShowcaseLoading = false);
    }
  }

  _PortfolioShowcaseMergeResult _mergePortfolioShowcaseSources({
    required List<MediaItemModel> promoMedia,
    required List<Map<String, dynamic>> promoPlacements,
    required List<MediaItemModel> organicMedia,
    int limit = 10,
  }) {
    final random = Random();
    final mergedRows = <Map<String, dynamic>>[];
    final seenKeys = <String>{};
    final normalizedLimit = limit == 0 ? _portfolioShowcaseLimit : limit;
    final maxItems = max(1, normalizedLimit);

    void push({
      required MediaItemModel media,
      required Map<String, dynamic> placement,
      required String source,
    }) {
      final key =
          '${media.providerId}|${media.fileUrl ?? media.thumbnailUrl ?? ''}|${media.id}';
      if (seenKeys.contains(key)) return;
      seenKeys.add(key);
      mergedRows.add({
        'media': media,
        'placement': placement,
        'source': source,
      });
    }

    for (var i = 0; i < promoMedia.length; i += 1) {
      final media = promoMedia[i];
      final placement =
          i < promoPlacements.length ? promoPlacements[i] : <String, dynamic>{};
      push(media: media, placement: placement, source: 'promo');
    }

    for (final media in organicMedia) {
      push(
        media: media,
        placement: <String, dynamic>{
          'target_provider_id': media.providerId,
          'target_provider_display_name': media.providerDisplayName,
          'redirect_url': '',
        },
        source: 'feed',
      );
    }

    final sponsored = mergedRows
        .where((row) => (row['source'] as String? ?? '') == 'promo')
        .toList(growable: false);
    final organic = mergedRows
        .where((row) => (row['source'] as String? ?? '') != 'promo')
        .toList(growable: true)
      ..shuffle(random);

    final resultRows = <Map<String, dynamic>>[];
    resultRows.addAll(sponsored.take(maxItems));
    if (resultRows.length < maxItems) {
      resultRows.addAll(organic.take(maxItems - resultRows.length));
    }

    final selectedRows = resultRows.take(maxItems).toList(growable: false);
    final mergedMedia = selectedRows
        .map((row) => row['media'])
        .whereType<MediaItemModel>()
        .toList(growable: false);
    final mergedPlacements = selectedRows
        .map((row) => row['placement'])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);

    return _PortfolioShowcaseMergeResult(
      media: mergedMedia,
      placements: mergedPlacements,
    );
  }

  Future<void> _loadPromoMessages() async {
    try {
      final items = await HomeService.fetchPromoActiveRows(
        serviceType: 'promo_messages',
        limit: 1,
      );
      if (!mounted) return;
      setState(() {
        _promoMessagePlacement = items.isNotEmpty ? items.first : null;
      });
    } catch (error, stackTrace) {
      AppLogger.warn(
        'HomeScreen failed to load promo messages',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _loadHomeContent({bool forceRefresh = false}) async {
    try {
      final result =
          await ContentService.fetchPublicContent(forceRefresh: forceRefresh);
      if (!mounted || !result.isSuccess || result.dataAsMap == null) return;
      final blocks =
          (result.dataAsMap!['blocks'] as Map<String, dynamic>?) ?? {};
      setState(() {
        _content = HomeScreenContent.fromBlocks(blocks);
      });
    } catch (error, stackTrace) {
      AppLogger.warn(
        'HomeScreen failed to load home content',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _startFeaturedSpecialistsAutoRotate() {
    _featuredSpecialistsTimer?.cancel();
    if (_visibleFeaturedSpecialists.length <= 1) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_featuredSpecialistsScroll.hasClients) return;
      _featuredSpecialistsTimer?.cancel();
      _featuredSpecialistsTimer = Timer.periodic(
        _featuredSpecialistsRotateDelay,
        (_) {
          if (!mounted ||
              !_featuredSpecialistsScroll.hasClients ||
              _featuredSpecialistsAutoPaused) {
            return;
          }
          _syncFeaturedSpecialistsPositionFromController();
          final position = _featuredSpecialistsScroll.position;
          final max = position.maxScrollExtent;
          if (max <= 0) {
            _featuredSpecialistsPos = 0;
            return;
          }
          final viewport = position.viewportDimension;
          final step = viewport > 0
              ? (viewport * 0.42).clamp(96.0, 220.0).toDouble()
              : 110.0;
          final next = _featuredSpecialistsPos + step;
          final target = next >= max - 4 ? 0.0 : next;
          _featuredSpecialistsScroll.animateTo(
            target,
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeInOut,
          );
        },
      );
    });
  }

  void _syncFeaturedSpecialistsPositionFromController() {
    if (!_featuredSpecialistsScroll.hasClients) return;
    final max = _featuredSpecialistsScroll.position.maxScrollExtent;
    final current = _featuredSpecialistsScroll.offset;
    _featuredSpecialistsPos = current.clamp(0.0, max).toDouble();
  }

  void _pauseFeaturedSpecialistsAutoRotate({bool resumeLater = false}) {
    _featuredSpecialistsAutoPaused = true;
    _featuredSpecialistsResumeTimer?.cancel();
    if (!resumeLater) {
      return;
    }
    _featuredSpecialistsResumeTimer =
        Timer(_featuredSpecialistsResumeDelay, () {
      if (!mounted) return;
      _syncFeaturedSpecialistsPositionFromController();
      _featuredSpecialistsAutoPaused = false;
    });
  }

  void _startPortfolioShowcaseAutoRotate() {
    _portfolioShowcaseTimer?.cancel();
    if (_portfolioShowcase.length <= 1) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_portfolioShowcaseScroll.hasClients) return;
      _portfolioShowcaseTimer?.cancel();
      _portfolioShowcaseTimer = Timer.periodic(
        _portfolioShowcaseRotateDelay,
        (_) {
          if (!mounted ||
              !_portfolioShowcaseScroll.hasClients ||
              _portfolioShowcaseAutoPaused) {
            return;
          }
          _syncPortfolioShowcasePositionFromController();
          final position = _portfolioShowcaseScroll.position;
          final max = position.maxScrollExtent;
          if (max <= 0) {
            _portfolioShowcasePos = 0;
            return;
          }
          final viewport = position.viewportDimension;
          final step = viewport > 0
              ? (viewport * 0.48).clamp(148.0, 220.0).toDouble()
              : 168.0;
          final next = _portfolioShowcasePos + step;
          final target = next >= max - 4 ? 0.0 : next;
          _portfolioShowcaseScroll.animateTo(
            target,
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeInOut,
          );
        },
      );
    });
  }

  void _syncPortfolioShowcasePositionFromController() {
    if (!_portfolioShowcaseScroll.hasClients) return;
    final max = _portfolioShowcaseScroll.position.maxScrollExtent;
    final current = _portfolioShowcaseScroll.offset;
    _portfolioShowcasePos = current.clamp(0.0, max).toDouble();
  }

  void _pausePortfolioShowcaseAutoRotate({bool resumeLater = false}) {
    _portfolioShowcaseAutoPaused = true;
    _portfolioShowcaseResumeTimer?.cancel();
    if (!resumeLater) {
      return;
    }
    _portfolioShowcaseResumeTimer = Timer(
      _portfolioShowcaseResumeDelay,
      () {
        if (!mounted) return;
        _syncPortfolioShowcasePositionFromController();
        _portfolioShowcaseAutoPaused = false;
      },
    );
  }

  MediaItemModel? _portfolioItemFromPromoPlacement(
      Map<String, dynamic> placement) {
    final nested = placement['portfolio_item'];
    if (nested is Map) {
      return MediaItemModel.fromJson(
        Map<String, dynamic>.from(nested),
        source: MediaItemSource.portfolio,
      );
    }

    final rawFile =
        (placement['target_portfolio_item_file'] as String?)?.trim() ?? '';
    if (rawFile.isEmpty) return null;
    return MediaItemModel(
      id: placement['target_portfolio_item_id'] as int? ?? 0,
      providerId: placement['target_provider_id'] as int? ?? 0,
      providerDisplayName:
          placement['target_provider_display_name'] as String? ?? 'مقدم خدمة',
      providerProfileImage:
          placement['target_provider_profile_image'] as String?,
      isVerifiedBlue:
        placement['target_provider_is_verified_blue'] as bool? ?? false,
      isVerifiedGreen:
        placement['target_provider_is_verified_green'] as bool? ?? false,
      fileType:
          placement['target_portfolio_item_file_type'] as String? ?? 'image',
      fileUrl: rawFile,
      caption: placement['title'] as String?,
      source: MediaItemSource.portfolio,
    );
  }

  String? _portfolioThumbUrl(MediaItemModel item) {
    return ApiClient.buildMediaUrl(
      item.thumbnailUrl?.trim().isNotEmpty == true
          ? item.thumbnailUrl
          : item.fileUrl,
    );
  }

  Uri? _resolvePromoUri(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return null;

    final parsed = Uri.tryParse(trimmed);
    if (parsed == null) return null;
    if (parsed.isAbsolute) return parsed;

    try {
      return Uri.parse(ApiClient.baseUrl).resolveUri(parsed);
    } catch (error, stackTrace) {
      AppLogger.warn(
        'HomeScreen failed to resolve promo URI',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<bool> _openExternalPromoUrl(String rawUrl) async {
    final uri = _resolvePromoUri(rawUrl);
    if (uri == null) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Uri? _resolveStrictExternalPromoUri(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return null;
    final parsed = Uri.tryParse(trimmed);
    if (parsed == null || !parsed.isAbsolute) return null;
    final scheme = parsed.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    return parsed;
  }

  Future<bool> _openStrictExternalPromoUrl(String rawUrl) async {
    final uri = _resolveStrictExternalPromoUri(rawUrl);
    if (uri == null) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openPromoPlacement({
    String? redirectUrl,
    int? providerId,
    String? providerName,
  }) async {
    final link = (redirectUrl ?? '').trim();
    if (link.isNotEmpty && await _openExternalPromoUrl(link)) {
      return;
    }
    if (!mounted || providerId == null || providerId <= 0) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProviderProfileScreen(
          providerId: providerId.toString(),
          providerName: providerName ?? 'مقدم خدمة',
        ),
      ),
    );
  }

  Future<void> _openBanner(BannerModel banner) async {
    if (!_isBannerActionable(banner)) {
      return;
    }
    AnalyticsService.trackFireAndForget(
      eventName: 'promo.banner_click',
      surface: 'flutter.home.hero',
      sourceApp: 'promo',
      objectType: 'ProviderProfile',
      objectId: (banner.providerId ?? 0).toString(),
      payload: {
        'banner_id': banner.id,
        'redirect_url': banner.linkUrl ?? '',
        'media_type': banner.mediaType,
      },
    );
    await _openPromoPlacement(
      redirectUrl: banner.linkUrl,
      providerId: banner.providerId,
      providerName: banner.providerDisplayName,
    );
  }

  bool _isBannerActionable(BannerModel banner) {
    final redirect = banner.linkUrl?.trim() ?? '';
    if (redirect.isNotEmpty) return true;
    return (banner.providerId ?? 0) > 0;
  }

  void _trackBannerImpression(
    BannerModel banner, {
    required String surface,
  }) {
    if (banner.id <= 0 || !_seenBannerImpressions.add(banner.id)) {
      return;
    }
    AnalyticsService.trackFireAndForget(
      eventName: 'promo.banner_impression',
      surface: surface,
      sourceApp: 'promo',
      objectType: 'ProviderProfile',
      objectId: (banner.providerId ?? 0).toString(),
      dedupeKey: 'promo.banner_impression:flutter:${banner.id}',
      payload: {
        'banner_id': banner.id,
        'redirect_url': banner.linkUrl ?? '',
        'media_type': banner.mediaType,
      },
    );
  }

  Future<void> _showPromoPopupDialog({
    required String mediaUrl,
    required String mediaType,
    required String title,
    String? redirectUrl,
    int? providerId,
    String? providerName,
  }) async {
    final isActionable = (redirectUrl?.trim().isNotEmpty ?? false) ||
        (providerId != null && providerId > 0);
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final content = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PromoMediaTile(
              mediaUrl: mediaUrl,
              mediaType: mediaType,
              height: 240,
              borderRadius: 0,
              autoplay: true,
              isActive: true,
              showVideoBadge: mediaType == 'video',
              fallback: const SizedBox.shrink(),
            ),
            if (title.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
          ],
        );

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Material(
                  color: Colors.white,
                  child: isActionable
                      ? InkWell(
                          onTap: () async {
                            Navigator.of(ctx).pop();
                            AnalyticsService.trackFireAndForget(
                              eventName: 'promo.popup_click',
                              surface: 'flutter.home.popup',
                              sourceApp: 'promo',
                              objectType: 'ProviderProfile',
                              objectId: (providerId ?? 0).toString(),
                              payload: {
                                'redirect_url': redirectUrl ?? '',
                                'title': title,
                              },
                            );
                            await _openPromoPlacement(
                              redirectUrl: redirectUrl,
                              providerId: providerId,
                              providerName: providerName,
                            );
                          },
                          child: content,
                        )
                      : content,
                ),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: GestureDetector(
                  onTap: () => Navigator.of(ctx).pop(),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child:
                        const Icon(Icons.close, color: Colors.white, size: 18),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _startReelsScroll() {
    _reelsTimer?.cancel();
    _reelsTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted || !_reelsScroll.hasClients || _reelsAutoPaused) {
        return;
      }
      _syncReelsPositionFromController();
      _reelsPos += 1.0;
      final max = _reelsScroll.position.maxScrollExtent;
      if (max <= 0) {
        _reelsPos = 0;
        return;
      }
      if (_reelsPos >= max) {
        _reelsScroll.jumpTo(0);
        _reelsPos = 0;
      } else {
        _reelsScroll.jumpTo(_reelsPos);
      }
    });
  }

  void _startCategoriesAutoScroll() {
    _categoriesAutoTimer?.cancel();
    if (_categories.length <= 1) return;
    _categoriesAutoPaused = false;
    _categoriesAutoTimer = Timer.periodic(_categoriesTickInterval, (_) {
      if (!mounted || !_categoriesScroll.hasClients || _categoriesAutoPaused) {
        return;
      }
      _syncCategoriesPositionFromController();
      _categoriesPos += 1.0;
      final max = _categoriesScroll.position.maxScrollExtent;
      if (max <= 0) {
        _categoriesPos = 0;
        return;
      }
      if (_categoriesPos >= max - 1) {
        _categoriesScroll.jumpTo(0);
        _categoriesPos = 0;
      } else {
        _categoriesScroll.jumpTo(_categoriesPos);
      }
    });
  }

  void _syncCategoriesPositionFromController() {
    if (!_categoriesScroll.hasClients) return;
    final max = _categoriesScroll.position.maxScrollExtent;
    final current = _categoriesScroll.offset;
    _categoriesPos = current.clamp(0.0, max).toDouble();
  }

  void _pauseCategoriesAutoScroll({bool resumeLater = false}) {
    _categoriesAutoPaused = true;
    _categoriesResumeTimer?.cancel();
    if (!resumeLater) {
      return;
    }
    _categoriesResumeTimer = Timer(_categoriesResumeDelay, () {
      if (!mounted) return;
      _syncCategoriesPositionFromController();
      _categoriesAutoPaused = false;
    });
  }

  void _scrollCategoriesByStep(bool forward) {
    if (!_categoriesScroll.hasClients) return;
    _pauseCategoriesAutoScroll(resumeLater: true);
    final position = _categoriesScroll.position;
    final step = position.viewportDimension > 0
        ? (position.viewportDimension * 0.72).clamp(140.0, 260.0).toDouble()
        : 180.0;
    final delta = forward ? step : -step;
    final target = (position.pixels + delta).clamp(
      0.0,
      position.maxScrollExtent,
    );
    _categoriesScroll.animateTo(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOut,
    );
  }

  void _syncReelsPositionFromController() {
    if (!_reelsScroll.hasClients) return;
    final max = _reelsScroll.position.maxScrollExtent;
    final current = _reelsScroll.offset;
    _reelsPos = current.clamp(0.0, max).toDouble();
    _syncActiveReelIndex();
  }

  void _handleReelsScroll() {
    if (!_reelsScroll.hasClients) return;
    _syncReelsPositionFromController();
  }

  void _syncActiveReelIndex() {
    if (_spotlights.isEmpty || !_reelsScroll.hasClients) {
      if (_activeReelIndex == 0) return;
      setState(() => _activeReelIndex = 0);
      return;
    }

    final position = _reelsScroll.position;
    final centerOffset = position.pixels + (position.viewportDimension / 2);
    final nextIndex = ((centerOffset - (_reelItemExtent / 2)) / _reelItemExtent)
        .round()
        .clamp(0, _spotlights.length - 1);
    if (nextIndex == _activeReelIndex) return;
    setState(() => _activeReelIndex = nextIndex);
  }

  void _pauseReelsAutoScroll({bool resumeLater = false}) {
    _reelsAutoPaused = true;
    _reelsResumeTimer?.cancel();
    if (!resumeLater) {
      return;
    }
    _reelsResumeTimer = Timer(_reelsResumeDelay, () {
      if (!mounted) return;
      _syncReelsPositionFromController();
      _reelsAutoPaused = false;
    });
  }

  @override
  void dispose() {
    _categoriesAutoTimer?.cancel();
    _categoriesResumeTimer?.cancel();
    _reelsTimer?.cancel();
    _reelsResumeTimer?.cancel();
    _featuredSpecialistsTimer?.cancel();
    _featuredSpecialistsResumeTimer?.cancel();
    _portfolioShowcaseTimer?.cancel();
    _portfolioShowcaseResumeTimer?.cancel();
    _bannersSyncTimer?.cancel();
    _badgeListenable?.removeListener(_handleBadgeChange);
    UnreadBadgeService.release();
    _bannerAutoTimer?.cancel();
    _bannerPageController.dispose();
    _categoriesScroll.dispose();
    _reelsScroll.removeListener(_handleReelsScroll);
    _reelsScroll.dispose();
    _featuredSpecialistsScroll.dispose();
    _portfolioShowcaseScroll.dispose();
    super.dispose();
  }

  void _handleBadgeChange() {
    final badges = _badgeListenable?.value ?? UnreadBadges.empty;
    if (!mounted) return;
    setState(() {
      _notificationUnread = badges.notifications;
      _chatUnread = badges.chats;
    });
  }

  Future<void> _loadUnreadBadges() async {
    await UnreadBadgeService.refresh(force: true);
  }

  // =============================================
  //  BUILD
  // =============================================

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const purple = Colors.deepPurple;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: isDark ? AppColors.bgDark : AppColors.bgLight,
      drawer: const CustomDrawer(),
      bottomNavigationBar: const CustomBottomNav(currentIndex: 0),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            _loadData(forceRefresh: true, showLoader: false),
            _loadHomeContent(forceRefresh: true),
          ]);
        },
        color: purple,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(child: _buildHero()),
            if ((_syncMessage ?? '').trim().isNotEmpty)
              SliverToBoxAdapter(child: _buildSyncNotice(isDark)),
            SliverToBoxAdapter(child: _buildReels(isDark)),
            if (_promoMessagePlacement != null)
              SliverToBoxAdapter(child: _buildPromoMessageCard(isDark, purple)),
            SliverToBoxAdapter(child: _buildCategories(isDark, purple)),
            SliverToBoxAdapter(child: _buildProviders(isDark, purple)),
            if (_portfolioShowcase.isNotEmpty || !_isPortfolioShowcaseLoading)
              SliverToBoxAdapter(
                child: _buildPortfolioShowcase(isDark, purple),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 30)),
          ],
        ),
      ),
    );
  }

  // =============================================
  //  HERO HEADER
  // =============================================

  Widget _buildHero() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bgLight,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: PlatformTopBar(
                overlay: false,
                height: 62,
                showMenuButton: true,
                onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
                notificationCount: _notificationUnread,
                chatCount: _chatUnread,
                onNotificationsTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const NotificationsScreen(),
                    ),
                  );
                  _loadUnreadBadges();
                },
                onChatsTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MyChatsScreen(),
                    ),
                  );
                  _loadUnreadBadges();
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
            child: AspectRatio(
              aspectRatio: 16 / 10.8,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  boxShadow: AppShadows.card,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildHeroBannerBackground(),
                      // Single soft bottom-to-top scrim for text legibility.
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.black.withValues(alpha: 0.55),
                              Colors.transparent,
                            ],
                            begin: Alignment.bottomCenter,
                            end: Alignment.center,
                          ),
                        ),
                      ),
                      _buildHeroContentOverlay(),
                      if (_heroBanners.length > 1) _buildHeroNavigationArrows(),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _buildHeroBannerBackground() {
    final heroBanners = _heroBanners;
    if (_isBannersLoading && heroBanners.isEmpty) {
      return _buildHeroLoadingBackdrop();
    }
    if (heroBanners.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.deepPurple.shade700, Colors.deepPurple.shade400],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
        ),
      );
    }

    if (heroBanners.length == 1) {
      final banner = heroBanners.first;
      final mediaUrl = ApiClient.buildMediaUrl(banner.mediaUrl);
      final content = _buildAdaptiveHeroBanner(
        banner: banner,
        mediaUrl: mediaUrl,
        isActive: true,
      );
      if (!_isBannerActionable(banner)) {
        return content;
      }
      return GestureDetector(
        onTap: () => _openBanner(banner),
        child: content,
      );
    }

    return PageView.builder(
      controller: _bannerPageController,
      itemCount: heroBanners.length,
      onPageChanged: (idx) {
        if (_bannerCurrentPage == idx) return;
        setState(() => _bannerCurrentPage = idx);
        if (idx >= 0 && idx < heroBanners.length) {
          _trackBannerImpression(
            heroBanners[idx],
            surface: 'flutter.home.hero_swipe',
          );
        }
        _scheduleNextBannerAutoRotate();
      },
      itemBuilder: (context, index) {
        final banner = heroBanners[index];
        final mediaUrl = ApiClient.buildMediaUrl(banner.mediaUrl);
        final content = _buildAdaptiveHeroBanner(
          banner: banner,
          mediaUrl: mediaUrl,
          isActive: index == _bannerCurrentPage,
        );
        if (!_isBannerActionable(banner)) {
          return content;
        }
        return GestureDetector(
          onTap: () => _openBanner(banner),
          child: content,
        );
      },
    );
  }

  Widget _buildHeroContentOverlay() {
    final heroBanners = _heroBanners;
    final hasBanners = heroBanners.isNotEmpty;
    final safeIndex = hasBanners
        ? _bannerCurrentPage.clamp(0, heroBanners.length - 1).toInt()
        : 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row — only the lightweight counter when multiple banners exist.
          if (heroBanners.length > 1)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.32),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${safeIndex + 1} / ${heroBanners.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: AppTextStyles.micro,
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          const Spacer(),
          if (heroBanners.length > 1) ...[
            const SizedBox(height: 12),
            Row(
              children: List.generate(_heroBanners.length, (index) {
                final isActive = index == _bannerCurrentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  margin: const EdgeInsetsDirectional.only(end: 5),
                  width: isActive ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: isActive
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(999),
                  ),
                );
              }),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeroNavigationArrows() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          _heroNavButton(
            icon: Icons.chevron_left_rounded,
            onTap: _goToPreviousHeroBanner,
          ),
          const Spacer(),
          _heroNavButton(
            icon: Icons.chevron_right_rounded,
            onTap: _goToNextHeroBanner,
          ),
        ],
      ),
    );
  }

  Widget _heroNavButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    // Lighter, more refined chevron control.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.32),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Icon(icon, size: 20, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildHeroPrimaryAction({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    required bool filled,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: filled
                ? const Color(0xFFF07B32)
                : Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: filled
                  ? Colors.transparent
                  : Colors.white.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroInfoPill({
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9.5,
              fontFamily: 'Cairo',
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroMetricChip({
    required IconData icon,
    required String label,
    required int value,
    required bool isLoading,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 6),
          if (isLoading)
            const _SkeletonBox(
              width: 40,
              height: 12,
              radius: 999,
              baseColor: Color(0x33FFFFFF),
              highlightColor: Color(0x66FFFFFF),
            )
          else
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '$value',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  TextSpan(
                    text: ' $label',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 9.5,
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _openSearchHome() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const SearchProviderScreen(
          showDrawer: false,
          showBottomNavigation: true,
        ),
      ),
    );
  }

  Widget _buildAdaptiveHeroBanner({
    required BannerModel banner,
    required String? mediaUrl,
    required bool isActive,
  }) {
    return Stack(
      fit: StackFit.expand,
      children: [
        PromoBannerWidget(
          mediaUrl: mediaUrl,
          isVideo: banner.isVideo,
          isActive: isActive,
          autoplay: true,
          stretchToParent: true,
          borderRadius: 0,
          contentPadding: EdgeInsets.zero,
          showBackdrop: true,
          backdropBlurSigma: 24,
          backdropOverlayOpacity: 0.18,
          backdropScale: 1.08,
          fallback: _gradientPlaceholder(),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.black.withValues(alpha: 0.18),
                Colors.transparent,
                Colors.black.withValues(alpha: 0.08),
              ],
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeroLoadingBackdrop() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF4F257E), Color(0xFF7B2E87), Color(0xFFF08B46)],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
          ),
        ),
        Positioned(
          top: -28,
          left: -24,
          child: Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
          ),
        ),
        Positioned(
          bottom: -44,
          right: -18,
          child: Container(
            width: 166,
            height: 166,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
          ),
        ),
        const Positioned.fill(
          child: Padding(
            padding: EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkeletonBox(
                  width: 58,
                  height: 22,
                  radius: 999,
                  baseColor: Color(0x33FFFFFF),
                  highlightColor: Color(0x66FFFFFF),
                ),
                Spacer(),
                _SkeletonBox(
                  width: 168,
                  height: 16,
                  radius: 8,
                  baseColor: Color(0x33FFFFFF),
                  highlightColor: Color(0x66FFFFFF),
                ),
                SizedBox(height: 8),
                _SkeletonBox(
                  width: 132,
                  height: 12,
                  radius: 8,
                  baseColor: Color(0x33FFFFFF),
                  highlightColor: Color(0x66FFFFFF),
                ),
                SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _SkeletonBox(
                        height: 42,
                        radius: 16,
                        baseColor: Color(0x33FFFFFF),
                        highlightColor: Color(0x66FFFFFF),
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: _SkeletonBox(
                        height: 42,
                        radius: 16,
                        baseColor: Color(0x33FFFFFF),
                        highlightColor: Color(0x66FFFFFF),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // =============================================
  //  REELS CAROUSEL
  // =============================================

  Widget _buildReels(bool isDark) {
    final hasData = _spotlights.isNotEmpty;

    return _buildSectionShell(
      kicker: 'لمحات حية',
      title: 'أحدث اللمحات',
      isDark: isDark,
      compactHeader: true,
      child: _buildSectionAnimatedContent(
        stateKey: _isSpotlightsLoading && !hasData
            ? 'reels-loading'
            : hasData
                ? 'reels-ready'
                : 'reels-empty',
        child: _isSpotlightsLoading && !hasData
            ? _buildReelsSkeleton(isDark)
            : !hasData
                ? _buildEmptyState(
                    isDark: isDark,
                    icon: Icons.movie_filter_outlined,
                    label: 'لا توجد لمحات حالياً',
                  )
                : SizedBox(
                    height: 102,
                    child: Listener(
                      onPointerDown: (_) => _pauseReelsAutoScroll(),
                      onPointerUp: (_) =>
                          _pauseReelsAutoScroll(resumeLater: true),
                      onPointerCancel: (_) =>
                          _pauseReelsAutoScroll(resumeLater: true),
                      child: ListView.builder(
                        controller: _reelsScroll,
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        itemCount: _spotlights.length,
                        itemBuilder: (context, index) {
                          final item = _spotlights[index];
                          final thumb = _spotlightThumbUrl(item);
                          final mediaUrl = ApiClient.buildMediaUrl(item.fileUrl);
                          final caption = item.sponsoredBadgeOnly
                              ? ((item.sectionTitle ?? '').trim().isNotEmpty
                                  ? (item.sectionTitle ?? '').trim()
                                  : 'ترويج ممول')
                              : (item.caption ?? '').trim();

                          return _PressableScale(
                            onTap: () => _openSpotlightViewer(index),
                            child: SizedBox(
                              width: 76,
                              child: Column(
                                children: [
                                  _reelMediaRing(
                                    imageUrl: thumb,
                                    mediaUrl: mediaUrl,
                                    isVideo: item.isVideo,
                                    isActive: index == _activeReelIndex,
                                    isDark: isDark,
                                    fallbackIcon: item.isVideo
                                        ? Icons.play_arrow_rounded
                                        : Icons.image_rounded,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    caption.isNotEmpty ? caption : 'لمحة',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.w700,
                                      color: isDark
                                          ? Colors.white70
                                          : Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
      ),
    );
  }

  Widget _buildSectionShell({
    required String kicker,
    required String title,
    String? note,
    required Widget child,
    required bool isDark,
    EdgeInsets margin = const EdgeInsets.fromLTRB(14, 8, 14, 4),
    Widget? trailing,
    bool compactHeader = false,
  }) {
    // 2026 minimal-UI section: rely on spacing instead of borders/shadows.
    return Padding(
      padding: margin,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          color: isDark ? AppColors.cardDark : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: isDark ? null : AppShadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(
              kicker: kicker,
              title: title,
              note: note,
              isDark: isDark,
              trailing: trailing,
              compact: compactHeader,
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required String kicker,
    required String title,
    String? note,
    required bool isDark,
    Widget? trailing,
    bool compact = false,
  }) {
    final hasKicker = kicker.trim().isNotEmpty;
    final hasNote = note != null && note.trim().isNotEmpty;
    return Row(
      crossAxisAlignment:
          compact ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        if (!compact)
          Container(
            width: 3,
            height: hasNote ? 32 : 18,
            margin: const EdgeInsetsDirectional.only(end: 10),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasKicker) ...[
                Text(
                  kicker,
                  style: TextStyle(
                    fontSize: AppTextStyles.micro,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Cairo',
                    letterSpacing: 0.1,
                    color: isDark ? const Color(0xFFC7F7EE) : AppColors.primary,
                  ),
                ),
                const SizedBox(height: 3),
              ],
              Text(
                title,
                style: TextStyle(
                  fontSize: compact ? AppTextStyles.h3 : AppTextStyles.h2,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Cairo',
                  height: 1.2,
                  color: isDark ? Colors.white : AppColors.grey900,
                ),
              ),
              if (hasNote) ...[
                const SizedBox(height: 2),
                Text(
                  note,
                  style: TextStyle(
                    fontSize: AppTextStyles.caption,
                    height: 1.4,
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white60 : AppColors.grey500,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 10),
          trailing,
        ],
      ],
    );
  }

  Widget _buildSectionMiniAction({
    required String label,
    required VoidCallback onTap,
  }) {
    // Minimal text-link style action with 44px touch target.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          constraints: const BoxConstraints(minHeight: 32),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: AppTextStyles.bodySm,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Cairo',
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 2),
              const Icon(
                Icons.chevron_left_rounded,
                size: 16,
                color: AppColors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionAnimatedContent({
    required String stateKey,
    required Widget child,
  }) {
    return AnimatedSwitcher(
      duration: AppDurations.normal,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final slide = Tween<Offset>(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: slide, child: child),
        );
      },
      child: KeyedSubtree(
        key: ValueKey(stateKey),
        child: child,
      ),
    );
  }

  void _updateHomeSyncNotice(List<dynamic> results) {
    final typedResults = results.whereType<CachedFetchResult>().toList();
    final hasAnyData = _categories.isNotEmpty ||
        _providers.isNotEmpty ||
        _banners.isNotEmpty ||
        _spotlights.isNotEmpty;
    final offlineFallback =
        typedResults.any((result) => result.isOfflineFallback);
    final staleFallback = typedResults.any((result) => result.isStaleCache);
    final hardFailure = typedResults.any(
      (result) => result.hasError && (result.data as List).isEmpty,
    );

    String? nextMessage;
    var nextTone = _HomeSyncTone.info;

    if (offlineFallback && hasAnyData) {
      nextMessage =
          'أنت غير متصل حالياً. نعرض آخر نسخة محفوظة على الجهاز إلى أن تعود الشبكة.';
      nextTone = _HomeSyncTone.warning;
    } else if (staleFallback && hasAnyData) {
      nextMessage =
          'بعض الأقسام معروضة من الكاش المحلي مؤقتاً حتى يكتمل التحديث من الخادم.';
      nextTone = _HomeSyncTone.info;
    } else if (hardFailure && !hasAnyData) {
      nextMessage =
          'تعذر تحميل بيانات الصفحة الرئيسية حالياً. اسحب لأسفل لإعادة المحاولة.';
      nextTone = _HomeSyncTone.error;
    }

    setState(() {
      _syncMessage = nextMessage;
      _syncTone = nextTone;
    });
  }

  Widget _buildSyncNotice(bool isDark) {
    final config = switch (_syncTone) {
      _HomeSyncTone.warning => (
          icon: Icons.wifi_off_rounded,
          background: AppColors.warningSurface,
          foreground: AppColors.warning,
        ),
      _HomeSyncTone.error => (
          icon: Icons.error_outline_rounded,
          background: AppColors.errorSurface,
          foreground: AppColors.error,
        ),
      _HomeSyncTone.info => (
          icon: Icons.cloud_done_outlined,
          background: AppColors.infoSurface,
          foreground: AppColors.info,
        ),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDark
              ? config.foreground.withValues(alpha: 0.14)
              : config.background,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: config.foreground.withValues(alpha: isDark ? 0.28 : 0.16),
          ),
        ),
        child: Row(
          children: [
            Icon(config.icon, size: 18, color: config.foreground),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _syncMessage ?? '',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: AppTextStyles.bodySm,
                  fontWeight: FontWeight.w700,
                  height: 1.6,
                  color: isDark ? Colors.white : config.foreground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Shared empty-state used across home sections for visual consistency.
  Widget _buildEmptyState({
    required bool isDark,
    required IconData icon,
    required String label,
  }) {
    return SizedBox(
      height: 112,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: AppColors.primarySurface,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 22, color: AppColors.primary),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppTextStyles.bodySm,
                fontFamily: 'Cairo',
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white54 : AppColors.grey500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPromoMessageCard(bool isDark, Color purple) {
    final placement = _promoMessagePlacement;
    if (placement == null) return const SizedBox.shrink();
    final title =
        (placement['message_title'] as String?)?.trim().isNotEmpty == true
            ? (placement['message_title'] as String)
            : ((placement['title'] as String?) ?? 'رسالة دعائية');
    final body = ((placement['message_body'] as String?) ?? '').trim();
    final providerIdRaw = placement['target_provider_id'];
    final providerId =
        providerIdRaw is int ? providerIdRaw : int.tryParse('$providerIdRaw');
    final providerName = placement['target_provider_display_name'] as String?;
    final redirectUrl = placement['redirect_url'] as String?;

    return _buildSectionShell(
      kicker: 'رسالة مميزة',
      title: 'مساحة ترويجية نشطة',
      note: 'إبراز مهني للمحتوى الدعائي داخل الصفحة الرئيسية دون تشويش.',
      isDark: isDark,
      compactHeader: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.primary.withValues(alpha: 0.16)
                  : AppColors.primarySurface,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'رسالة دعائية',
              style: TextStyle(
                color: isDark ? const Color(0xFFE9D9FF) : AppColors.primary,
                fontSize: AppTextStyles.micro,
                fontFamily: 'Cairo',
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              color: isDark ? Colors.white : AppColors.grey900,
              fontSize: AppTextStyles.bodyLg,
              height: 1.35,
              fontFamily: 'Cairo',
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            body.isNotEmpty ? body : 'عرض جديد مخصص لك.',
            style: TextStyle(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.84)
                  : AppColors.grey700,
              fontSize: AppTextStyles.bodyMd,
              height: 1.7,
              fontFamily: 'Cairo',
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              minimumSize: const Size(0, 44),
              side: const BorderSide(color: AppColors.primary, width: 1.1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              textStyle: const TextStyle(
                fontSize: AppTextStyles.bodySm,
                fontFamily: 'Cairo',
                fontWeight: FontWeight.w800,
              ),
            ),
            onPressed: () async {
              await _openPromoPlacement(
                redirectUrl: redirectUrl,
                providerId: providerId,
                providerName: providerName,
              );
            },
            child: const Text('عرض التفاصيل'),
          ),
        ],
      ),
    );
  }

  String? _spotlightThumbUrl(MediaItemModel item) {
    final raw = item.thumbnailUrl?.trim().isNotEmpty == true
        ? item.thumbnailUrl
        : item.fileUrl;
    return ApiClient.buildMediaUrl(raw);
  }

  Widget _reelMediaRing({
    required bool isDark,
    String? imageUrl,
    String? mediaUrl,
    required bool isVideo,
    required bool isActive,
    String? assetPath,
    required IconData fallbackIcon,
  }) {
    return Container(
      width: 70,
      height: 70,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const SweepGradient(
                colors: [
                  Color(0xFF9F57DB),
                  Color(0xFFF1A559),
                  Color(0xFFC8A5FC),
                  Color(0xFF9F57DB)
                ],
              ),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.22),
                        blurRadius: 0,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
          ),
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            ),
            child: ClipOval(
              child: isVideo && mediaUrl != null
                  ? PromoMediaTile(
                      mediaUrl: mediaUrl,
                      mediaType: 'video',
                      borderRadius: 999,
                      autoplay: true,
                      isActive: isActive,
                      fit: BoxFit.cover,
                      fallback: _reelFallback(fallbackIcon),
                    )
                  : imageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) =>
                              _reelFallback(fallbackIcon),
                        )
                      : (assetPath != null
                          ? Image.asset(
                              assetPath,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _reelFallback(fallbackIcon),
                            )
                          : _reelFallback(fallbackIcon)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reelFallback(IconData icon) {
    return Container(
      color: Colors.transparent,
      alignment: Alignment.center,
      child: Icon(icon, color: Colors.deepPurple, size: 22),
    );
  }

  Future<void> _openSpotlightViewer(int index) async {
    if (_spotlights.isEmpty) return;

    _pauseReelsAutoScroll();
    _reelsTimer?.cancel();

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SpotlightViewerPage(
          items: _spotlights,
          initialIndex: index,
        ),
      ),
    );

    if (mounted) {
      _syncSpotlightInteractionState();
      _reelsAutoPaused = false;
      _startReelsScroll();
    }
  }

  void _syncSpotlightInteractionState() {
    if ((!mounted) || (_spotlights.isEmpty && _portfolioShowcase.isEmpty)) {
      return;
    }
    setState(() {
      MediaItemModel.applyInteractionOverrides(_spotlights);
      MediaItemModel.applyInteractionOverrides(_portfolioShowcase);
    });
  }

  void _showNoSpotlights() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('لا توجد لمحات حالياً')),
    );
  }

  // =============================================
  //  CATEGORIES
  // =============================================

  Widget _buildCategories(bool isDark, Color purple) {
    return _buildSectionShell(
      kicker: 'اكتشف الخدمات',
      title: _content.categoriesTitle,
      isDark: isDark,
      trailing: _buildSectionMiniAction(
        label: 'عرض الكل',
        onTap: _openSearchHome,
      ),
      child: _buildSectionAnimatedContent(
        stateKey: _isCategoriesLoading && _categories.isEmpty
            ? 'categories-loading'
            : _categories.isEmpty
                ? 'categories-empty'
                : 'categories-ready',
        child: _isCategoriesLoading && _categories.isEmpty
            ? _buildCategoriesSkeleton(isDark)
            : _categories.isEmpty
                ? _buildEmptyState(
                    isDark: isDark,
                    icon: Icons.category_outlined,
                    label: 'لا توجد تصنيفات متاحة حالياً',
                  )
                : Column(
                    children: [
                      Row(
                        children: [
                          if (_categories.length > 1) ...[
                            _buildSectionScrollButton(
                              isDark: isDark,
                              icon: Icons.chevron_left_rounded,
                              onTap: () => _scrollCategoriesByStep(false),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: SizedBox(
                              height: 96,
                              child: Listener(
                                onPointerDown: (_) => _pauseCategoriesAutoScroll(),
                                onPointerUp: (_) =>
                                    _pauseCategoriesAutoScroll(resumeLater: true),
                                onPointerCancel: (_) =>
                                    _pauseCategoriesAutoScroll(resumeLater: true),
                                child: ListView.builder(
                                  controller: _categoriesScroll,
                                  scrollDirection: Axis.horizontal,
                                  physics: const BouncingScrollPhysics(),
                                  itemCount: _categories.length,
                                  itemBuilder: (context, index) {
                                    final cat = _categories[index];
                                    final icon = _categoryIcon(cat.name);
                                    return Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius:
                                            BorderRadius.circular(AppRadius.md),
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => SearchProviderScreen(
                                                initialCategoryId:
                                                    cat.id > 0 ? cat.id : null,
                                              ),
                                            ),
                                          );
                                        },
                                        child: Container(
                                          width: 78,
                                          margin: const EdgeInsetsDirectional.only(
                                              end: 6),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 6,
                                          ),
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Container(
                                                width: 50,
                                                height: 50,
                                                decoration: BoxDecoration(
                                                  color: isDark
                                                      ? Colors.white
                                                          .withValues(alpha: 0.06)
                                                      : AppColors.primarySurface,
                                                  borderRadius: BorderRadius.circular(
                                                      AppRadius.md),
                                                ),
                                                child: Icon(
                                                  icon,
                                                  size: 22,
                                                  color: AppColors.primary,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Expanded(
                                                child: Text(
                                                  cat.name,
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    fontSize: AppTextStyles.micro,
                                                    fontWeight: FontWeight.w600,
                                                    height: 1.3,
                                                    fontFamily: 'Cairo',
                                                    color: isDark
                                                        ? Colors.white70
                                                        : AppColors.grey700,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                          if (_categories.length > 1) ...[
                            const SizedBox(width: 8),
                            _buildSectionScrollButton(
                              isDark: isDark,
                              icon: Icons.chevron_right_rounded,
                              onTap: () => _scrollCategoriesByStep(true),
                            ),
                          ],
                        ],
                      ),
                      if (_categories.length > 1) ...[
                        const SizedBox(height: 10),
                        _buildCategoriesScrollProgress(isDark: isDark),
                      ],
                    ],
                  ),
      ),
    );
  }

  Widget _buildSectionScrollButton({
    required bool isDark,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
              : AppColors.borderLight,
            ),
            boxShadow: isDark ? null : AppShadows.card,
          ),
          child: Icon(
            icon,
            size: 18,
            color: isDark ? Colors.white70 : AppColors.grey700,
          ),
        ),
      ),
    );
  }

  Widget _buildCategoriesScrollProgress({required bool isDark}) {
    return SizedBox(
      height: 4,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : AppColors.grey200,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return AnimatedBuilder(
                animation: _categoriesScroll,
                builder: (context, _) {
                  final hasClients = _categoriesScroll.hasClients;
                  final max = hasClients
                      ? _categoriesScroll.position.maxScrollExtent
                      : 0.0;
                  final current = hasClients ? _categoriesScroll.offset : 0.0;
                  final progress = max <= 0
                      ? 0.0
                      : (current / max).clamp(0.0, 1.0);
                  final thumbWidth =
                      (constraints.maxWidth * 0.26).clamp(28.0, 88.0);
                  final travel = (constraints.maxWidth - thumbWidth)
                      .clamp(0.0, constraints.maxWidth);
                  return Stack(
                    children: [
                      PositionedDirectional(
                        start: travel * progress,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: thumbWidth,
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFFC7F7EE)
                                : AppColors.primary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  // =============================================
  //  FEATURED PROVIDERS
  // =============================================

  Widget _buildProviders(bool isDark, Color purple) {
    final visibleFeaturedSpecialists = _visibleFeaturedSpecialists;
    final title = (_content.providersTitle.trim().isEmpty ||
            _content.providersTitle == '...' ||
            _content.providersTitle == 'مقدمو الخدمة')
        ? 'أبرز المختصين'
        : _content.providersTitle;
    return _buildSectionShell(
      kicker: 'ترشيحات المنصة',
      title: title,
      isDark: isDark,
      child: _buildSectionAnimatedContent(
        stateKey: _isFeaturedLoading && visibleFeaturedSpecialists.isEmpty
            ? 'providers-loading'
            : visibleFeaturedSpecialists.isEmpty
                ? 'providers-empty'
                : 'providers-ready',
        child: _isFeaturedLoading && visibleFeaturedSpecialists.isEmpty
            ? _buildProvidersSkeleton(isDark)
            : visibleFeaturedSpecialists.isEmpty
                ? _buildEmptyState(
                    isDark: isDark,
                    icon: Icons.workspace_premium_outlined,
                    label: 'لا يوجد مختصون مميزون حالياً',
                  )
                : SizedBox(
                    height: 208,
                    child: Listener(
                      onPointerDown: (_) => _pauseFeaturedSpecialistsAutoRotate(),
                      onPointerUp: (_) => _pauseFeaturedSpecialistsAutoRotate(
                        resumeLater: true,
                      ),
                      onPointerCancel: (_) =>
                          _pauseFeaturedSpecialistsAutoRotate(
                        resumeLater: true,
                      ),
                      child: ListView.builder(
                        controller: _featuredSpecialistsScroll,
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        itemCount: visibleFeaturedSpecialists.length,
                        itemBuilder: (context, index) => _providerCard(
                          visibleFeaturedSpecialists[index],
                          isDark,
                          purple,
                        ),
                      ),
                    ),
                  ),
      ),
    );
  }

  Widget _buildPortfolioShowcase(bool isDark, Color purple) {
    return _buildSectionShell(
      kicker: 'أعمال وبنرات',
      title: 'البنرات والمشاريع',
      isDark: isDark,
      child: _buildSectionAnimatedContent(
        stateKey: _portfolioShowcase.isEmpty
            ? 'portfolio-empty'
            : 'portfolio-ready',
        child: _portfolioShowcase.isEmpty
            ? _buildEmptyState(
                isDark: isDark,
                icon: Icons.photo_library_outlined,
                label: 'لا توجد مشاريع أو بنرات حالياً',
              )
            : SizedBox(
                height: 214,
                child: Listener(
                  onPointerDown: (_) => _pausePortfolioShowcaseAutoRotate(),
                  onPointerUp: (_) =>
                      _pausePortfolioShowcaseAutoRotate(resumeLater: true),
                  onPointerCancel: (_) =>
                      _pausePortfolioShowcaseAutoRotate(resumeLater: true),
                  child: ListView.builder(
                    controller: _portfolioShowcaseScroll,
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: _portfolioShowcase.length,
                    itemBuilder: (context, index) => _portfolioShowcaseCard(
                      _portfolioShowcase[index],
                      index,
                      isDark,
                      purple,
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _portfolioShowcaseCard(
    MediaItemModel item,
    int index,
    bool isDark,
    Color purple,
  ) {
    final thumbUrl = _portfolioThumbUrl(item);

    return _PressableScale(
      onTap: () => _openPortfolioShowcasePlacement(index),
      child: Container(
        width: 188,
        margin: const EdgeInsetsDirectional.only(end: 10),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : AppColors.borderLight,
          ),
          boxShadow: isDark ? null : AppShadows.card,
        ),
        child: AspectRatio(
          aspectRatio: 4 / 5,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: thumbUrl != null
                    ? CachedNetworkImage(
                        imageUrl: thumbUrl,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _gradientPlaceholder(),
                      )
                    : _gradientPlaceholder(),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withValues(alpha: 0.08),
                      Colors.black.withValues(alpha: 0.18),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'مختار',
                    style: TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Cairo',
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              if (item.isVideo)
                Positioned(
                  left: 10,
                  bottom: 10,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openPortfolioShowcasePlacement(int index) async {
    if (index < 0 || index >= _portfolioShowcase.length) return;
    final item = _portfolioShowcase[index];
    final placement =
        (index >= 0 && index < _portfolioShowcasePlacements.length)
            ? _portfolioShowcasePlacements[index]
            : const <String, dynamic>{};

    AnalyticsService.trackFireAndForget(
      eventName: 'promo.portfolio_showcase_click',
      surface: 'flutter.home.portfolio_showcase',
      sourceApp: 'promo',
      objectType: 'ProviderProfile',
      objectId: item.providerId.toString(),
      payload: {
        'media_id': item.id,
        'media_type': item.fileType,
        'redirect_url': (placement['redirect_url'] as String?) ?? '',
      },
    );

    final providerIdRaw = placement['target_provider_id'];
    final providerId =
        providerIdRaw is int ? providerIdRaw : int.tryParse('$providerIdRaw');
    final redirectUrl = (placement['redirect_url'] as String?)?.trim() ?? '';
    if (redirectUrl.isNotEmpty) {
      final opened = await _openStrictExternalPromoUrl(redirectUrl);
      if (opened) return;
    }
    final resolvedProviderId = providerId ?? item.providerId;
    if (resolvedProviderId <= 0) {
      if (!mounted) return;
      _openSearchHome();
      return;
    }
    await _openPromoPlacement(
      redirectUrl: null,
      providerId: resolvedProviderId,
      providerName: (placement['target_provider_display_name'] as String?) ??
          item.providerDisplayName,
    );
  }

  Widget _providerCard(
    FeaturedSpecialistModel specialist,
    bool isDark,
    Color purple,
  ) {
    final profileUrl = ApiClient.buildMediaUrl(specialist.profileImage);
    const cardWidth = 132.0;

    return _PressableScale(
      onTap: () async {
        AnalyticsService.trackFireAndForget(
          eventName: 'promo.featured_specialist_click',
          surface: 'flutter.home.featured_specialists',
          sourceApp: 'promo',
          objectType: 'ProviderProfile',
          objectId: specialist.providerId.toString(),
          payload: {
            'rating_avg': specialist.ratingAvg,
            'rating_count': specialist.ratingCount,
            'redirect_url': specialist.redirectUrl ?? '',
          },
        );

        final externalUrl = specialist.redirectUrl?.trim() ?? '';
        if (externalUrl.isNotEmpty) {
          final opened = await _openStrictExternalPromoUrl(externalUrl);
          if (opened) return;
        }
        if (!mounted) return;
        if (specialist.providerId <= 0) {
          _openSearchHome();
          return;
        }
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProviderProfileScreen(
              providerId: specialist.providerId.toString(),
              providerName: specialist.displayName,
              providerImage: profileUrl,
              providerRating: specialist.ratingAvg,
              providerVerifiedBlue: specialist.isVerifiedBlue,
              providerVerifiedGreen: specialist.isVerifiedGreen,
            ),
          ),
        );
        if (!mounted) return;
        _syncSpotlightInteractionState();
      },
      child: Container(
        width: cardWidth,
        margin: const EdgeInsetsDirectional.only(end: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:
              isDark ? Colors.white.withValues(alpha: 0.04) : AppColors.bgLight,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 6),
            // ── Avatar with subtle tinted ring + overlays (verified + excellence) ──
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : AppColors.primarySurface,
                  ),
                  child: CircleAvatar(
                    radius: 30,
                    backgroundColor:
                        isDark ? AppColors.surfaceDark : Colors.white,
                    backgroundImage: profileUrl != null
                        ? CachedNetworkImageProvider(profileUrl)
                        : null,
                    child: profileUrl == null
                        ? Text(
                            specialist.displayName.isNotEmpty
                                ? specialist.displayName[0]
                                : '؟',
                            style: const TextStyle(
                              fontSize: AppTextStyles.h1,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'Cairo',
                              color: AppColors.primary,
                            ),
                          )
                        : null,
                  ),
                ),
                if (specialist.isVerifiedBlue)
                  Positioned(
                    top: 0,
                    left: -6,
                    child: Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFF5DA9E9),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark
                              ? AppColors.cardDark
                              : Colors.white,
                          width: 2,
                        ),
                        boxShadow: AppShadows.card,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                if (specialist.isVerifiedGreen)
                  Positioned(
                    top: 0,
                    right: -6,
                    child: Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark
                              ? AppColors.cardDark
                              : Colors.white,
                          width: 2,
                        ),
                        boxShadow: AppShadows.card,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                if (specialist.excellenceBadges.isNotEmpty)
                  Positioned(
                    top: specialist.isVerifiedBlue ? 30 : 0,
                    left: -6,
                    child: Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.cardDark.withValues(alpha: 0.96)
                            : AppColors.accentSurface,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : AppColors.accent.withValues(alpha: 0.12),
                        ),
                        boxShadow: AppShadows.card,
                      ),
                      child: const Icon(
                        Icons.auto_awesome_rounded,
                        size: 13,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            // ── Name — centered, up to 2 lines ──
            ProviderNameWithBadges(
              name: specialist.displayName,
              isVerifiedBlue: specialist.isVerifiedBlue,
              isVerifiedGreen: specialist.isVerifiedGreen,
              maxLines: 2,
              textAlign: TextAlign.center,
              badgeIconSize: 13,
              style: TextStyle(
                fontSize: AppTextStyles.bodyMd,
                fontWeight: FontWeight.w700,
                height: 1.25,
                fontFamily: 'Cairo',
                color: isDark ? Colors.white : AppColors.grey900,
              ),
            ),
            const Spacer(),
            // ── Rating — centered minimal pill ──
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (specialist.ratingCount > 0) ...[
                  const Icon(
                    Icons.star_rounded,
                    size: 14,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    specialist.ratingLabel,
                    style: TextStyle(
                      fontSize: AppTextStyles.bodySm,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'Cairo',
                      color: isDark ? Colors.white : AppColors.grey900,
                    ),
                  ),
                ] else
                  Text(
                    '0 تقييم',
                    style: TextStyle(
                      fontSize: AppTextStyles.bodySm,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Cairo',
                      color: isDark ? Colors.white60 : AppColors.grey500,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProviderMetaPill({
    required String label,
    required Color background,
    required Color foreground,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 8.5,
          fontWeight: FontWeight.w800,
          fontFamily: 'Cairo',
          color: foreground,
        ),
      ),
    );
  }

  Widget _buildReelsSkeleton(bool isDark) {
    return SizedBox(
      height: 102,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 5,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          return SizedBox(
            width: 76,
            child: Column(
              children: [
                _SkeletonBox(
                  width: 70,
                  height: 70,
                  radius: 999,
                  baseColor: isDark
                      ? const Color(0x33FFFFFF)
                      : const Color(0xFFEFE8F8),
                  highlightColor: isDark
                      ? const Color(0x66FFFFFF)
                      : const Color(0xFFF8F4FC),
                ),
                const SizedBox(height: 8),
                _SkeletonBox(
                  width: 48,
                  height: 10,
                  radius: 6,
                  baseColor: isDark
                      ? const Color(0x33FFFFFF)
                      : const Color(0xFFEFE8F8),
                  highlightColor: isDark
                      ? const Color(0x66FFFFFF)
                      : const Color(0xFFF8F4FC),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCategoriesSkeleton(bool isDark) {
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 5,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          return SizedBox(
            width: 78,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _SkeletonBox(
                  width: 50,
                  height: 50,
                  radius: AppRadius.md,
                  baseColor: isDark
                      ? const Color(0x33FFFFFF)
                      : AppColors.primarySurface,
                  highlightColor: isDark
                      ? const Color(0x66FFFFFF)
                      : const Color(0xFFF8F4FC),
                ),
                const SizedBox(height: 8),
                const _SkeletonBox(
                  width: 52,
                  height: 9,
                  radius: 5,
                ),
                const SizedBox(height: 4),
                const _SkeletonBox(
                  width: 36,
                  height: 9,
                  radius: 5,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildProvidersSkeleton(bool isDark) {
    return SizedBox(
      height: 208,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 3,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          return Container(
            width: 132,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : AppColors.bgLight,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 6),
                const _SkeletonBox(
                  width: 64,
                  height: 64,
                  radius: 999,
                ),
                const SizedBox(height: 14),
                const _SkeletonBox(width: 92, height: 11, radius: 6),
                const Spacer(),
                const _SkeletonBox(width: 64, height: 12, radius: 6),
              ],
            ),
          );
        },
      ),
    );
  }

  FeaturedSpecialistModel _providerToFeaturedSpecialist(
    ProviderPublicModel provider,
  ) {
    return FeaturedSpecialistModel(
      placementId: provider.id,
      providerId: provider.id,
      displayName: provider.displayName,
      profileImage: provider.profileImage,
      city: provider.city,
      cityDisplay: provider.locationDisplay,
      isVerifiedBlue: provider.isVerifiedBlue,
      isVerifiedGreen: provider.isVerifiedGreen,
      ratingAvg: provider.ratingAvg,
      ratingCount: provider.ratingCount,
      excellenceBadges: provider.excellenceBadges,
    );
  }

  List<ProviderPublicModel> _topRatedProviders(
    List<ProviderPublicModel> providers,
  ) {
    final sorted = providers.where((provider) => provider.id > 0).toList();
    sorted.sort((a, b) {
      final byRating = b.ratingAvg.compareTo(a.ratingAvg);
      if (byRating != 0) return byRating;
      final byCount = b.ratingCount.compareTo(a.ratingCount);
      if (byCount != 0) return byCount;
      return b.id.compareTo(a.id);
    });
    return sorted;
  }

  Widget _gradientPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.deepPurple.shade200, Colors.deepPurple.shade100],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
      ),
      child: const Center(
          child: Icon(Icons.image_outlined, size: 20, color: Colors.white54)),
    );
  }

  // =============================================
  //  PROMO BANNERS — Full-width auto-rotating carousel
  // =============================================

  void _goToPreviousHeroBanner() {
    final heroBanners = _heroBanners;
    if (!mounted ||
        !_bannerPageController.hasClients ||
        heroBanners.length <= 1) {
      return;
    }
    final current = _bannerCurrentPage.clamp(0, heroBanners.length - 1).toInt();
    final prev = (current - 1 + heroBanners.length) % heroBanners.length;
    _bannerPageController.animateToPage(
      prev,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  void _goToNextHeroBanner() {
    final heroBanners = _heroBanners;
    if (!mounted ||
        !_bannerPageController.hasClients ||
        heroBanners.length <= 1) {
      return;
    }
    final current = _bannerCurrentPage.clamp(0, heroBanners.length - 1).toInt();
    final next = (current + 1) % heroBanners.length;
    _bannerPageController.animateToPage(
      next,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  void _handleHeroBannerVideoEnded(int bannerId) {
    final heroBanners = _heroBanners;
    if (!mounted ||
        heroBanners.length <= 1 ||
        !_bannerPageController.hasClients) {
      return;
    }
    final safeIndex =
        _bannerCurrentPage.clamp(0, heroBanners.length - 1).toInt();
    final currentBanner = heroBanners[safeIndex];
    if (currentBanner.id != bannerId || !currentBanner.isVideo) {
      return;
    }
    _bannerAutoTimer?.cancel();
    _goToNextHeroBanner();
  }

  void _scheduleNextBannerAutoRotate() {
    final heroBanners = _heroBanners;
    _bannerAutoTimer?.cancel();
    if (!mounted ||
        heroBanners.length <= 1 ||
        !_bannerPageController.hasClients) {
      return;
    }
    final safeIndex =
        _bannerCurrentPage.clamp(0, heroBanners.length - 1).toInt();
    final currentBanner = heroBanners[safeIndex];
    // الفيديو ينتقل فقط بعد اكتمال التشغيل عبر onVideoEnded.
    if (currentBanner.isVideo) {
      return;
    }
    final expectedBannerId = currentBanner.id;
    final delay = _imageBannerRotateDelay;
    _bannerAutoTimer = Timer(delay, () {
      final liveHeroBanners = _heroBanners;
      if (!mounted ||
          !_bannerPageController.hasClients ||
          liveHeroBanners.length <= 1) {
        return;
      }
      final activeIndex =
          _bannerCurrentPage.clamp(0, liveHeroBanners.length - 1).toInt();
      final activeBanner = liveHeroBanners[activeIndex];
      if (activeBanner.id != expectedBannerId) {
        return;
      }
      _goToNextHeroBanner();
    });
  }

  void _startBannerAutoRotate() {
    final heroBanners = _heroBanners;
    _bannerAutoTimer?.cancel();
    if (heroBanners.length <= 1) return;
    if (_bannerPageController.hasClients) {
      _scheduleNextBannerAutoRotate();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _heroBanners.length <= 1) return;
      _scheduleNextBannerAutoRotate();
    });
  }

  Widget _buildPromoBanners(bool isDark, Color purple) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(_content.bannersTitle, isDark),
          const SizedBox(height: 12),
          SizedBox(
            height: 168,
            child: Stack(
              children: [
                // -- PageView carousel --
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  child: PageView.builder(
                    controller: _bannerPageController,
                    itemCount: _banners.length,
                    onPageChanged: (idx) {
                      setState(() => _bannerCurrentPage = idx);
                      _scheduleNextBannerAutoRotate();
                      if (idx >= 0 && idx < _banners.length) {
                        _trackBannerImpression(
                          _banners[idx],
                          surface: 'flutter.home.hero_swipe',
                        );
                      }
                    },
                    itemBuilder: (context, index) {
                      final b = _banners[index];
                      final url = ApiClient.buildMediaUrl(b.mediaUrl);
                      final hasTitle =
                          b.title != null && b.title!.trim().isNotEmpty;
                      final hasProvider = b.providerDisplayName != null &&
                          b.providerDisplayName!.trim().isNotEmpty;
                      return GestureDetector(
                        onTap: () => _openBanner(b),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            PromoMediaTile(
                              key: ValueKey(
                                  'promo-banner-${b.id}-${b.mediaUrl}'),
                              mediaUrl: url,
                              mediaType: b.isVideo ? 'video' : 'image',
                              borderRadius: 0,
                              height: 168,
                              autoplay: true,
                              isActive: index == _bannerCurrentPage,
                              showVideoBadge: b.isVideo,
                              fallback: _gradientPlaceholder(),
                            ),
                            // Soft bottom scrim only when there's text to show.
                            if (hasTitle || hasProvider)
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: Container(
                                  padding:
                                      const EdgeInsets.fromLTRB(14, 18, 14, 12),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.black.withValues(alpha: 0.55),
                                        Colors.transparent,
                                      ],
                                      begin: Alignment.bottomCenter,
                                      end: Alignment.topCenter,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (hasTitle)
                                        Text(
                                          b.title!.trim(),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: AppTextStyles.h3,
                                            fontWeight: FontWeight.w800,
                                            fontFamily: 'Cairo',
                                            color: Colors.white,
                                            height: 1.2,
                                          ),
                                        ),
                                      if (hasProvider) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          b.providerDisplayName!.trim(),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: AppTextStyles.bodySm,
                                            fontFamily: 'Cairo',
                                            fontWeight: FontWeight.w500,
                                            color: Colors.white
                                                .withValues(alpha: 0.85),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                // -- Dots indicator --
                if (_banners.length > 1)
                  Positioned(
                    bottom: 10,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(_banners.length, (i) {
                        final active = i == _bannerCurrentPage;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: active ? 16 : 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: active
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        );
                      }),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =============================================
  //  HELPERS
  // =============================================

  Widget _sectionTitle(String title, bool isDark) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 18,
          margin: const EdgeInsetsDirectional.only(end: 10),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Flexible(
          child: Text(
            title,
            style: TextStyle(
              fontSize: AppTextStyles.h2,
              fontWeight: FontWeight.w800,
              fontFamily: 'Cairo',
              height: 1.2,
              color: isDark ? Colors.white : AppColors.grey900,
            ),
          ),
        ),
      ],
    );
  }

  IconData _categoryIcon(String name) {
    final n = name.toLowerCase();
    if (n.contains('قانون') || n.contains('محام')) return Icons.gavel_rounded;
    if (n.contains('هندس')) return Icons.engineering_rounded;
    if (n.contains('تصميم')) return Icons.design_services_rounded;
    if (n.contains('توصيل')) return Icons.delivery_dining_rounded;
    if (n.contains('صح') || n.contains('طب')) {
      return Icons.health_and_safety_rounded;
    }
    if (n.contains('ترجم')) return Icons.translate_rounded;
    if (n.contains('برمج') || n.contains('تقن')) return Icons.code_rounded;
    if (n.contains('صيان')) return Icons.build_rounded;
    if (n.contains('رياض')) return Icons.fitness_center_rounded;
    if (n.contains('منزل')) return Icons.home_repair_service_rounded;
    if (n.contains('مال')) return Icons.attach_money_rounded;
    if (n.contains('تسويق')) return Icons.campaign_rounded;
    if (n.contains('تعليم') || n.contains('تدريب')) return Icons.school_rounded;
    if (n.contains('سيار') || n.contains('نقل')) {
      return Icons.directions_car_rounded;
    }
    return Icons.category_rounded;
  }
}

class _SkeletonBox extends StatelessWidget {
  final double? width;
  final double? height;
  final double radius;
  final Color baseColor;
  final Color highlightColor;

  const _SkeletonBox({
    this.width,
    this.height,
    this.radius = 12,
    this.baseColor = const Color(0xFFEFE8F8),
    this.highlightColor = const Color(0xFFF8F4FC),
  });

  @override
  Widget build(BuildContext context) {
    return _ShimmerSkeleton(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: baseColor,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

class _ShimmerSkeleton extends StatefulWidget {
  final Widget child;
  final Color baseColor;
  final Color highlightColor;

  const _ShimmerSkeleton({
    required this.child,
    required this.baseColor,
    required this.highlightColor,
  });

  @override
  State<_ShimmerSkeleton> createState() => _ShimmerSkeletonState();
}

class _ShimmerSkeletonState extends State<_ShimmerSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            final width = bounds.width == 0 ? 1.0 : bounds.width;
            final dx = (width * 2.2 * _controller.value) - width;
            return LinearGradient(
              colors: [
                widget.baseColor,
                widget.highlightColor,
                widget.baseColor,
              ],
              stops: const [0.15, 0.5, 0.85],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              transform: _SlidingGradientTransform(dx),
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcATop,
          child: child,
        );
      },
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  final double slideX;

  const _SlidingGradientTransform(this.slideX);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(slideX, 0, 0);
  }
}

/// Subtle scale-down press feedback for tappable cards.
/// Wraps a child in a [GestureDetector] that animates to ~0.97 on press
/// (150ms easeOut) and back on release. Preserves [onTap] semantics.
class _PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _PressableScale({
    required this.child,
    required this.onTap,
  });

  @override
  State<_PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<_PressableScale> {
  static const double _pressedScale = 0.97;
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? _pressedScale : 1.0,
        duration: AppDurations.fast,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

class _PortfolioShowcaseMergeResult {
  final List<MediaItemModel> media;
  final List<Map<String, dynamic>> placements;

  const _PortfolioShowcaseMergeResult({
    required this.media,
    required this.placements,
  });
}

class HomeScreenContent {
  final String categoriesTitle;
  final String providersTitle;
  final String bannersTitle;
  final BannerModel? fallbackBanner;

  const HomeScreenContent({
    required this.categoriesTitle,
    required this.providersTitle,
    required this.bannersTitle,
    required this.fallbackBanner,
  });

  factory HomeScreenContent.empty() {
    return const HomeScreenContent(
      categoriesTitle: '...',
      providersTitle: 'أبرز المختصين',
      bannersTitle: '...',
      fallbackBanner: null,
    );
  }

  factory HomeScreenContent.fromBlocks(Map<String, dynamic> blocks) {
    String resolve(String key, String fallback) {
      final block = blocks[key];
      if (block is! Map<String, dynamic>) return fallback;
      final title = (block['title_ar'] as String?)?.trim() ?? '';
      return title.isNotEmpty ? title : fallback;
    }

    BannerModel? resolveFallbackBanner(String key) {
      final rawBlock = blocks[key];
      if (rawBlock is! Map) return null;
      final block = Map<String, dynamic>.from(rawBlock);
      final mediaUrl = (block['media_url'] as String?)?.trim() ?? '';
      if (mediaUrl.isEmpty) return null;
      return BannerModel.fromJson({
        'id': 0,
        'title': (block['title_ar'] as String?)?.trim(),
        'media_type': (block['media_type'] as String?)?.trim() ?? 'image',
        'media_url': mediaUrl,
        'display_order': 0,
      });
    }

    return HomeScreenContent(
      categoriesTitle: resolve('home_categories_title', 'التصنيفات'),
      providersTitle: resolve('home_providers_title', 'أبرز المختصين'),
      bannersTitle: resolve('home_banners_title', 'عروض ترويجية'),
      fallbackBanner: resolveFallbackBanner('home_banners_fallback'),
    );
  }
}

enum _HomeSyncTone { info, warning, error }
