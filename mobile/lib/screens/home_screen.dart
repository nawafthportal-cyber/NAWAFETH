// ignore_for_file: unused_field, unused_element
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/bottom_nav.dart';
import '../widgets/custom_drawer.dart';
import '../services/api_client.dart';
import '../services/analytics_service.dart';
import '../services/home_service.dart';
import '../models/category_model.dart';
import '../models/banner_model.dart';
import '../models/featured_specialist_model.dart';
import '../models/provider_public_model.dart';
import '../models/media_item_model.dart';
import '../widgets/promo_banner_widget.dart';
import '../widgets/promo_media_tile.dart';
import '../widgets/platform_top_bar.dart';
import '../widgets/spotlight_viewer.dart';
import '../widgets/verified_badge_view.dart';
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
  bool _isLoading = true;
  int _notificationUnread = 0;
  int _chatUnread = 0;
  bool _promoPopupShown = false;
  List<MediaItemModel> _portfolioShowcase = [];
  List<Map<String, dynamic>> _portfolioShowcasePlacements = [];
  Map<String, dynamic>? _promoMessagePlacement;
  bool _promoMessageDismissed = false;
  final Set<int> _seenBannerImpressions = <int>{};

  // -- Banner carousel --
  final PageController _bannerPageController = PageController();
  Timer? _bannerAutoTimer;
  Timer? _bannersSyncTimer;
  int _bannerCurrentPage = 0;
  static const Duration _imageBannerRotateDelay = Duration(seconds: 3);
  static const Duration _videoBannerFallbackRotateDelay = Duration(seconds: 30);
  static const Duration _bannerSyncInterval = Duration(minutes: 1);

  // -- Reels auto scroll --
  final ScrollController _reelsScroll = ScrollController();
  final ScrollController _featuredSpecialistsScroll = ScrollController();
  Timer? _reelsTimer;
  Timer? _reelsResumeTimer;
  Timer? _featuredSpecialistsTimer;
  Timer? _featuredSpecialistsResumeTimer;
  ValueListenable<UnreadBadges>? _badgeListenable;
  double _reelsPos = 0;
  double _featuredSpecialistsPos = 0;
  bool _reelsAutoPaused = false;
  bool _featuredSpecialistsAutoPaused = false;
  static const Duration _reelsResumeDelay = Duration(seconds: 3);
  static const Duration _featuredSpecialistsResumeDelay = Duration(seconds: 3);

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

  @override
  void initState() {
    super.initState();
    _redirectIfCompletionPending();
    final seeded = _seedFromCachedData();
    _loadHomeContent();
    _loadData(showLoader: !seeded);
    _startBannerSync();
    _startReelsScroll();
    _badgeListenable = UnreadBadgeService.acquire();
    _badgeListenable!.addListener(_handleBadgeChange);
    _handleBadgeChange();
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
      bannersLimit: 10,
      spotlightsLimit: 16,
    );
    if (!cached.hasAnyData) return false;

    _categories = cached.categories;
    _providers = cached.providers;
    _banners = cached.banners;
    _spotlights = cached.spotlights;
    _isLoading = cached.providers.isEmpty;
    return true;
  }

  Future<void> _loadData({
    bool forceRefresh = false,
    bool showLoader = true,
  }) async {
    if (showLoader && mounted) {
      setState(() => _isLoading = true);
    }

    final categoriesFuture =
        HomeService.fetchCategories(forceRefresh: forceRefresh);
    final providersFuture = HomeService.fetchFeaturedProviders(
      limit: 10,
      forceRefresh: forceRefresh,
    );
    final bannersFuture = HomeService.fetchHomeBanners(
      limit: 10,
      forceRefresh: forceRefresh,
    );
    final spotlightsFuture = HomeService.fetchSpotlightFeed(
      limit: 16,
      forceRefresh: forceRefresh,
    );

    // Fetch promo placements (non-blocking)
    _loadPromoFeatured(forceRefresh: forceRefresh);
    if (!_promoPopupShown) _loadPromoPopup();
    _loadPromoPortfolioShowcase();
    _loadPromoMessages();

    categoriesFuture.then((categories) {
      if (!mounted) return;
      setState(() => _categories = categories);
    });

    bannersFuture.then((banners) {
      if (!mounted) return;
      setState(() => _banners = banners);
      _startBannerAutoRotate();
      if (banners.isNotEmpty) {
        _trackBannerImpression(
          banners.first,
          surface: 'flutter.home.hero_initial',
        );
      }
    });

    spotlightsFuture.then((spotlights) {
      if (!mounted) return;
      setState(() => _spotlights = spotlights);
    });

    providersFuture.then((providers) {
      if (!mounted) return;
      setState(() {
        _providers = providers;
        _isLoading = false;
      });
    });

    try {
      await Future.wait(
          [categoriesFuture, providersFuture, bannersFuture, spotlightsFuture]);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
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
        limit: 10,
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
    } catch (_) {
      // Keep current banners on transient refresh failures.
    }
  }

  Future<void> _loadPromoFeatured({bool forceRefresh = false}) async {
    try {
      final items = await HomeService.fetchFeaturedSpecialists(
        limit: 10,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _featuredSpecialists = items;
      });
      _startFeaturedSpecialistsAutoRotate();
    } catch (_) {}
  }

  Future<void> _loadPromoPopup() async {
    try {
      final res =
          await ApiClient.get('/api/promo/active/?ad_type=popup_home&limit=1');
      if (!mounted || !res.isSuccess || res.data == null) return;
      final items = res.data is List
          ? res.data as List
          : (res.data['results'] as List?) ?? [];
      if (items.isEmpty) return;
      final promo = items[0] as Map<String, dynamic>;
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
    } catch (_) {}
  }

  Future<void> _loadPromoPortfolioShowcase() async {
    try {
      final res = await ApiClient.get(
        '/api/promo/active/?service_type=portfolio_showcase&limit=10',
      );
      if (!mounted || !res.isSuccess) return;
      final items = _promoMapItemsFromResponse(res);
      final media = <MediaItemModel>[];
      final placements = <Map<String, dynamic>>[];
      for (final placement in items) {
        final parsed = _portfolioItemFromPromoPlacement(placement);
        if (parsed == null) continue;
        media.add(parsed);
        placements.add(placement);
      }
      if (!mounted) return;
      setState(() {
        _portfolioShowcasePlacements = placements;
        _portfolioShowcase = media;
      });
    } catch (_) {}
  }

  Future<void> _loadPromoMessages() async {
    try {
      final res = await ApiClient.get(
        '/api/promo/active/?service_type=promo_messages&limit=1',
      );
      if (!mounted || !res.isSuccess) return;
      final items = _promoMapItemsFromResponse(res);
      if (!mounted) return;
      setState(() {
        _promoMessagePlacement = items.isNotEmpty ? items.first : null;
      });
    } catch (_) {}
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
    } catch (_) {
      // Keep current content on transient failures.
    }
  }

  List<dynamic> _promoItemsFromResponse(dynamic response) {
    final data = response?.data;
    if (data is List) return data;
    if (data is Map<String, dynamic>) {
      final results = data['results'];
      if (results is List) return results;
    }
    return const [];
  }

  List<Map<String, dynamic>> _promoMapItemsFromResponse(dynamic response) {
    return _promoItemsFromResponse(response)
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  void _startFeaturedSpecialistsAutoRotate() {
    _featuredSpecialistsTimer?.cancel();
    if (_featuredSpecialists.length <= 1) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_featuredSpecialistsScroll.hasClients) return;
      _featuredSpecialistsTimer?.cancel();
      _featuredSpecialistsTimer = Timer.periodic(
        const Duration(seconds: 3),
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
          const step = 110.0;
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

  Future<bool> _openExternalPromoUrl(String rawUrl) async {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return false;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.isAbsolute) return false;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
    return true;
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

  void _syncReelsPositionFromController() {
    if (!_reelsScroll.hasClients) return;
    final max = _reelsScroll.position.maxScrollExtent;
    final current = _reelsScroll.offset;
    _reelsPos = current.clamp(0.0, max).toDouble();
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
    _reelsTimer?.cancel();
    _reelsResumeTimer?.cancel();
    _featuredSpecialistsTimer?.cancel();
    _featuredSpecialistsResumeTimer?.cancel();
    _bannersSyncTimer?.cancel();
    _badgeListenable?.removeListener(_handleBadgeChange);
    UnreadBadgeService.release();
    _bannerAutoTimer?.cancel();
    _bannerPageController.dispose();
    _reelsScroll.dispose();
    _featuredSpecialistsScroll.dispose();
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
      backgroundColor:
          isDark ? const Color(0xFF120F18) : const Color(0xFFF7F4FB),
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
            SliverToBoxAdapter(child: _buildReels(isDark)),
            if (_promoMessagePlacement != null && !_promoMessageDismissed)
              SliverToBoxAdapter(child: _buildPromoMessageCard(isDark, purple)),
            SliverToBoxAdapter(child: _buildCategories(isDark, purple)),
            SliverToBoxAdapter(child: _buildProviders(isDark, purple)),
            if (_portfolioShowcase.isNotEmpty)
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
        gradient: LinearGradient(
          colors: [Color(0xFFF8F3FD), Color(0xFFF1ECFA)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
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
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: AspectRatio(
              aspectRatio: 16 / 10.8,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF60269E).withValues(alpha: 0.14),
                      blurRadius: 34,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildHeroBannerBackground(),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF160F1F).withValues(alpha: 0.18),
                              const Color(0xFF160F1F).withValues(alpha: 0.04),
                              const Color(0xFF160F1F).withValues(alpha: 0.72),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: const [0.0, 0.4, 1.0],
                          ),
                        ),
                      ),
                      _buildHeroContentOverlay(),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.18),
                ),
              ),
              child: const Text(
                'نوافذ',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const Spacer(),
          const Text(
            'اكتشف المختص المناسب\nبواجهة أسرع للجوال',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              height: 1.35,
              fontFamily: 'Cairo',
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'تصميم أخف، معلومات أوضح، وتنقل سريع بين اللمحات والتصنيفات وأبرز المختصين.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.88),
              fontSize: 10.5,
              height: 1.7,
              fontFamily: 'Cairo',
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildHeroPrimaryAction(
                  label: 'ابدأ البحث',
                  icon: Icons.search_rounded,
                  onTap: _openSearchHome,
                  filled: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildHeroPrimaryAction(
                  label: 'التصنيفات',
                  icon: Icons.widgets_rounded,
                  onTap: _openSearchHome,
                  filled: false,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildHeroInfoPill(
                icon: Icons.auto_awesome_rounded,
                label: 'واجهة مناسبة لكل الجوالات',
              ),
              _buildHeroInfoPill(
                icon: Icons.flash_on_rounded,
                label: 'بحث سريع',
              ),
              _buildHeroInfoPill(
                icon: Icons.verified_rounded,
                label: 'مختصون موثقون',
              ),
            ],
          ),
          if (_heroBanners.length > 1) ...[
            const SizedBox(height: 12),
            Row(
              children: List.generate(_heroBanners.length, (index) {
                final isActive = index == _bannerCurrentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  margin: const EdgeInsetsDirectional.only(end: 6),
                  width: isActive ? 22 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: isActive
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.38),
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
    final shouldLoopSingleVideo = banner.isVideo && _heroBanners.length <= 1;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: PromoBannerWidget(
            key: ValueKey('hero-banner-${banner.id}-${banner.mediaUrl}'),
            mediaUrl: mediaUrl,
            isVideo: banner.isVideo,
            isActive: isActive,
            autoplay: true,
            loopVideo: shouldLoopSingleVideo,
            onVideoEnded: banner.isVideo && isActive && !shouldLoopSingleVideo
                ? () => _handleHeroBannerVideoEnded(banner.id)
                : null,
            borderRadius: 0,
            stretchToParent: true,
            mediaFit: BoxFit.contain,
            mediaOverlayOpacity: 0,
            contentPadding: EdgeInsets.zero,
            showBackdrop: true,
            backdropBlurSigma: 24,
            backdropOverlayOpacity: 0.18,
            backdropScale: 1.08,
            fallback: _gradientPlaceholder(),
          ),
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

  // =============================================
  //  REELS CAROUSEL
  // =============================================

  Widget _buildReels(bool isDark) {
    final hasData = _spotlights.isNotEmpty;

    return _buildSectionShell(
      kicker: 'لمحات حية',
      title: 'أحدث اللمحات',
      note: 'محتوى قصير وسريع الاستكشاف مناسب للجوال.',
      isDark: isDark,
      margin: const EdgeInsets.fromLTRB(14, 2, 14, 4),
      child: !hasData
          ? SizedBox(
              height: 84,
              child: Center(
                child: Text(
                  'لا توجد لمحات حالياً',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
              ),
            )
          : SizedBox(
              height: 102,
              child: Listener(
                onPointerDown: (_) => _pauseReelsAutoScroll(),
                onPointerUp: (_) => _pauseReelsAutoScroll(resumeLater: true),
                onPointerCancel: (_) => _pauseReelsAutoScroll(resumeLater: true),
                child: ListView.builder(
                  controller: _reelsScroll,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: _spotlights.length,
                  itemBuilder: (context, index) {
                    final item = _spotlights[index];
                    final thumb = _spotlightThumbUrl(item);
                    final caption = (item.caption ?? '').trim();

                    return GestureDetector(
                      onTap: () => _openSpotlightViewer(index),
                      child: SizedBox(
                        width: 76,
                        child: Column(
                          children: [
                            _reelMediaRing(
                              imageUrl: thumb,
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
                                color: isDark ? Colors.white70 : Colors.black54,
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
  }) {
    return Padding(
      padding: margin,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1B1623) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : const Color(0xFFE9DDF7),
          ),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: const Color(0xFF3C1B5F).withValues(alpha: 0.06),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
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
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B3D8F).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  kicker,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Cairo',
                    color: Color(0xFF8B3D8F),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'Cairo',
                  color: isDark ? Colors.white : const Color(0xFF24182F),
                ),
              ),
              if (note != null && note.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  note,
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.6,
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white60 : const Color(0xFF796A8A),
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF6EFFC),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFE7D8F8)),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              fontFamily: 'Cairo',
              color: Color(0xFF7B2E87),
            ),
          ),
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
    final body = (placement['message_body'] as String?) ?? '';
    final providerIdRaw = placement['target_provider_id'];
    final providerId =
        providerIdRaw is int ? providerIdRaw : int.tryParse('$providerIdRaw');
    final providerName = placement['target_provider_display_name'] as String?;
    final redirectUrl = placement['redirect_url'] as String?;

    return _buildSectionShell(
      kicker: 'رسالة مميزة',
      title: title,
      note: 'إبراز مهني للمحتوى الدعائي داخل الصفحة الرئيسية دون إزعاج.',
      isDark: isDark,
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 4),
      trailing: IconButton(
        tooltip: 'إخفاء',
        onPressed: () {
          if (!mounted) return;
          setState(() => _promoMessageDismissed = true);
        },
        icon: const Icon(Icons.close_rounded, size: 18),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? const [Color(0xFF271F34), Color(0xFF1B1623)]
                : const [Color(0xFFFFF4EA), Color(0xFFF9EEFF)],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: purple.withValues(alpha: 0.14)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (body.trim().isNotEmpty)
              Text(
                body,
                style: TextStyle(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.84)
                      : const Color(0xFF4E3B59),
                  fontSize: 11,
                  height: 1.8,
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w600,
                ),
              ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                foregroundColor: const Color(0xFF6A246F),
                backgroundColor: Colors.white.withValues(alpha: 0.72),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                textStyle: const TextStyle(
                  fontSize: 10.5,
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
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(
                colors: [
                  Color(0xFF9F57DB),
                  Color(0xFFF1A559),
                  Color(0xFFC8A5FC),
                  Color(0xFF9F57DB)
                ],
              ),
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
              child: imageUrl != null
                  ? Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _reelFallback(fallbackIcon),
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
      note: 'تصنيفات سريعة ومقروءة بحجم مناسب للشاشات الصغيرة.',
      isDark: isDark,
      trailing: _buildSectionMiniAction(
        label: 'عرض الكل',
        onTap: _openSearchHome,
      ),
      child: _categories.isEmpty
          ? SizedBox(
              height: 76,
              child: Center(
                child: Text(
                  'لا توجد تصنيفات متاحة حالياً',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ),
            )
          : SizedBox(
              height: 98,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: _categories.length,
                itemBuilder: (context, index) {
                  final cat = _categories[index];
                  final icon = _categoryIcon(cat.name);
                  return GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SearchProviderScreen(
                            initialCategoryId: cat.id > 0 ? cat.id : null,
                          ),
                        ),
                      );
                    },
                    child: Container(
                      width: 84,
                      margin: const EdgeInsetsDirectional.only(end: 10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.04)
                            : const Color(0xFFF9F5FD),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.06)
                              : const Color(0xFFECDDFA),
                        ),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  const Color(0xFF8E37A3).withValues(alpha: 0.15),
                                  const Color(0xFFF08B46).withValues(alpha: 0.18),
                                ],
                                begin: Alignment.topRight,
                                end: Alignment.bottomLeft,
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(icon, size: 20, color: purple),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: Text(
                              cat.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                height: 1.45,
                                fontFamily: 'Cairo',
                                color:
                                    isDark ? Colors.white70 : Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }

  // =============================================
  //  FEATURED PROVIDERS
  // =============================================

  Widget _buildProviders(bool isDark, Color purple) {
    final title = (_content.providersTitle.trim().isEmpty ||
            _content.providersTitle == '...' ||
            _content.providersTitle == 'مقدمو الخدمة')
        ? 'أبرز المختصين'
        : _content.providersTitle;
    return _buildSectionShell(
      kicker: 'ترشيحات المنصة',
      title: title,
      note: 'بطاقات مختصين مضبوطة بصريًا لتناسب شاشات الجوال الصغيرة.',
      isDark: isDark,
      child: _isLoading
          ? const SizedBox(
              height: 156,
              child: Center(
                child: CircularProgressIndicator(color: Colors.deepPurple),
              ),
            )
          : _featuredSpecialists.isEmpty
              ? SizedBox(
                  height: 92,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 20,
                          color:
                              isDark ? Colors.white24 : Colors.grey.shade300,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'لا يوجد مختصون مميزون حالياً',
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'Cairo',
                            color:
                                isDark ? Colors.white30 : Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : SizedBox(
                  height: 182,
                  child: Listener(
                    onPointerDown: (_) => _pauseFeaturedSpecialistsAutoRotate(),
                    onPointerUp: (_) =>
                        _pauseFeaturedSpecialistsAutoRotate(resumeLater: true),
                    onPointerCancel: (_) =>
                        _pauseFeaturedSpecialistsAutoRotate(resumeLater: true),
                    child: ListView.builder(
                      controller: _featuredSpecialistsScroll,
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      itemCount: _featuredSpecialists.length,
                      itemBuilder: (context, index) => _providerCard(
                        _featuredSpecialists[index],
                        isDark,
                        purple,
                      ),
                    ),
                  ),
                ),
    );
  }

  Widget _buildPortfolioShowcase(bool isDark, Color purple) {
    return _buildSectionShell(
      kicker: 'أعمال وبنرات',
      title: 'شريط البنرات والمشاريع',
      note: 'معرض بصري مضغوط وواضح يبرز الأعمال الترويجية والمشاريع المختارة.',
      isDark: isDark,
      child: SizedBox(
        height: 214,
        child: ListView.builder(
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
    );
  }

  Widget _portfolioShowcaseCard(
    MediaItemModel item,
    int index,
    bool isDark,
    Color purple,
  ) {
    final thumbUrl = _portfolioThumbUrl(item);
    final profileUrl = ApiClient.buildMediaUrl(item.providerProfileImage);

    return GestureDetector(
      onTap: () => _openPortfolioShowcasePlacement(index),
      child: Container(
        width: 188,
        margin: const EdgeInsetsDirectional.only(end: 12),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : const Color(0xFFEBDCF8),
          ),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: const Color(0xFF34104E).withValues(alpha: 0.07),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(22),
                    ),
                    child: thumbUrl != null
                        ? Image.network(
                            thumbUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _gradientPlaceholder(),
                          )
                        : _gradientPlaceholder(),
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
                        padding: const EdgeInsets.all(6),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: purple.withValues(alpha: 0.12),
                    backgroundImage:
                        profileUrl != null ? NetworkImage(profileUrl) : null,
                    child: profileUrl == null
                        ? Text(
                            item.providerDisplayName.isNotEmpty
                                ? item.providerDisplayName[0]
                                : '؟',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: purple,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.caption?.trim().isNotEmpty == true
                              ? item.caption!.trim()
                              : 'مشروع ممول',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Cairo',
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.providerDisplayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 9,
                            fontFamily: 'Cairo',
                            color:
                                isDark ? Colors.white70 : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
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
    await _openPromoPlacement(
      redirectUrl: placement['redirect_url'] as String?,
      providerId: providerId ?? item.providerId,
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
    const cardWidth = 146.0;

    return GestureDetector(
      onTap: () async {
        final externalUrl = specialist.redirectUrl?.trim() ?? '';
        if (externalUrl.isNotEmpty) {
          final opened = await _openExternalPromoUrl(externalUrl);
          if (opened) return;
        }
        if (!mounted) return;
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
        margin: const EdgeInsetsDirectional.only(end: 12),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF221B2E) : const Color(0xFFFCFAFE),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : const Color(0xFFE8DDF5),
          ),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: const Color(0xFF3D195E).withValues(alpha: 0.06),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (specialist.excellenceBadges.isNotEmpty)
                        _buildProviderMetaPill(
                          label: 'متميز',
                          background: const Color(0xFFFFF0D9),
                          foreground: const Color(0xFFB56A00),
                        ),
                      if ((specialist.city ?? '').trim().isNotEmpty)
                        _buildProviderMetaPill(
                          label: specialist.city!.trim(),
                          background: const Color(0xFFF3EEFB),
                          foreground: const Color(0xFF7A2B74),
                        ),
                    ],
                  ),
                ),
                if (specialist.isVerified)
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: VerifiedBadgeView(
                      isVerifiedBlue: specialist.isVerifiedBlue,
                      isVerifiedGreen: specialist.isVerifiedGreen,
                      iconSize: 15,
                      enableTap: false,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Center(
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFFF59E0B), Color(0xFFB13AC7)],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                ),
                child: CircleAvatar(
                  radius: 34,
                  backgroundColor:
                      isDark ? const Color(0xFF221B31) : Colors.white,
                  backgroundImage:
                      profileUrl != null ? NetworkImage(profileUrl) : null,
                  child: profileUrl == null
                      ? Text(
                          specialist.displayName.isNotEmpty
                              ? specialist.displayName[0]
                              : '؟',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Cairo',
                            color: purple,
                          ),
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              specialist.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                fontFamily: 'Cairo',
                color: isDark ? Colors.white : const Color(0xFF24182F),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8D2A7A).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        size: 12,
                        color: Color(0xFFF59E0B),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        specialist.ratingLabel,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Cairo',
                          color: Color(0xFF7A2B74),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  specialist.ratingCount > 0
                      ? '${specialist.ratingCount} تقييم'
                      : 'جديد',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Cairo',
                    color: isDark ? Colors.white54 : const Color(0xFF8B7A9B),
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

  Duration _resolveBannerRotateDelay(BannerModel banner) {
    if (!banner.isVideo) return _imageBannerRotateDelay;
    final seconds = banner.durationSeconds;
    if (seconds == null || seconds <= 0) {
      return _videoBannerFallbackRotateDelay;
    }
    return Duration(seconds: seconds);
  }

  void _goToNextHeroBanner() {
    if (!mounted || !_bannerPageController.hasClients || _banners.length <= 1) {
      return;
    }
    final next = (_bannerCurrentPage + 1) % _banners.length;
    _bannerPageController.animateToPage(
      next,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  void _handleHeroBannerVideoEnded(int bannerId) {
    if (!mounted || _banners.length <= 1 || !_bannerPageController.hasClients) {
      return;
    }
    final safeIndex =
        _bannerCurrentPage >= 0 && _bannerCurrentPage < _banners.length
            ? _bannerCurrentPage
            : 0;
    final currentBanner = _banners[safeIndex];
    if (currentBanner.id != bannerId || !currentBanner.isVideo) {
      return;
    }
    _bannerAutoTimer?.cancel();
    _goToNextHeroBanner();
  }

  void _scheduleNextBannerAutoRotate() {
    _bannerAutoTimer?.cancel();
    if (!mounted || _banners.length <= 1 || !_bannerPageController.hasClients) {
      return;
    }
    final safeIndex =
        _bannerCurrentPage >= 0 && _bannerCurrentPage < _banners.length
            ? _bannerCurrentPage
            : 0;
    final currentBanner = _banners[safeIndex];
    final expectedBannerId = currentBanner.id;
    final delay = currentBanner.isVideo
        ? _resolveBannerRotateDelay(currentBanner)
        : _imageBannerRotateDelay;
    _bannerAutoTimer = Timer(delay, () {
      if (!mounted ||
          !_bannerPageController.hasClients ||
          _banners.length <= 1) {
        return;
      }
      final activeIndex =
          _bannerCurrentPage >= 0 && _bannerCurrentPage < _banners.length
              ? _bannerCurrentPage
              : 0;
      final activeBanner = _banners[activeIndex];
      if (activeBanner.id != expectedBannerId) {
        return;
      }
      _goToNextHeroBanner();
    });
  }

  void _startBannerAutoRotate() {
    _bannerAutoTimer?.cancel();
    if (_banners.length <= 1) return;
    if (_bannerPageController.hasClients) {
      _scheduleNextBannerAutoRotate();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _banners.length <= 1) return;
      _scheduleNextBannerAutoRotate();
    });
  }

  Widget _buildPromoBanners(bool isDark, Color purple) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(_content.bannersTitle, isDark),
          const SizedBox(height: 10),
          SizedBox(
            height: 170,
            child: Stack(
              children: [
                // -- PageView carousel --
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
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
                              height: 170,
                              autoplay: true,
                              isActive: index == _bannerCurrentPage,
                              showVideoBadge: b.isVideo,
                              fallback: _gradientPlaceholder(),
                            ),
                            // Bottom overlay
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.black.withValues(alpha: 0.65),
                                      Colors.transparent
                                    ],
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (b.title != null && b.title!.isNotEmpty)
                                      Text(b.title!,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              fontFamily: 'Cairo',
                                              color: Colors.white)),
                                    if (b.providerDisplayName != null)
                                      Text(b.providerDisplayName!,
                                          maxLines: 1,
                                          style: TextStyle(
                                              fontSize: 10,
                                              fontFamily: 'Cairo',
                                              color: Colors.white
                                                  .withValues(alpha: 0.8))),
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
                    bottom: 8,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(_banners.length, (i) {
                        final active = i == _bannerCurrentPage;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: active ? 18 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: active
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(3),
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
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w800,
        fontFamily: 'Cairo',
        color: isDark ? Colors.white : Colors.black87,
      ),
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
