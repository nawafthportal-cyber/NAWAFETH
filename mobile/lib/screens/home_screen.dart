// ignore_for_file: unused_field, unused_element
import 'dart:async';
import 'dart:ui' as ui;
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
import '../models/provider_public_model.dart';
import '../models/media_item_model.dart';
import '../widgets/excellence_badges_wrap.dart';
import '../widgets/promo_media_tile.dart';
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
  List<BannerModel> _banners = [];
  List<MediaItemModel> _spotlights = [];
  HomeScreenContent _content = HomeScreenContent.empty();
  bool _isLoading = true;
  int _notificationUnread = 0;
  int _chatUnread = 0;
  Set<int> _featuredProviderIds = {};
  bool _promoPopupShown = false;
  List<MediaItemModel> _portfolioShowcase = [];
  List<Map<String, dynamic>> _sponsorships = [];
  List<Map<String, dynamic>> _snapshotPlacements = [];
  Map<String, dynamic>? _promoMessagePlacement;
  bool _promoMessageDismissed = false;
  final Set<int> _seenBannerImpressions = <int>{};

  // -- Banner carousel --
  final PageController _bannerPageController = PageController();
  Timer? _bannerAutoTimer;
  int _bannerCurrentPage = 0;

  // -- Reels auto scroll --
  final ScrollController _reelsScroll = ScrollController();
  Timer? _reelsTimer;
  ValueListenable<UnreadBadges>? _badgeListenable;
  double _reelsPos = 0;

  static const _reelFallbackLogos = [
    'assets/images/32.jpeg',
    'assets/images/841015.jpeg',
    'assets/images/879797.jpeg',
  ];

  @override
  void initState() {
    super.initState();
    _redirectIfCompletionPending();
    final seeded = _seedFromCachedData();
    _loadHomeContent();
    _loadData(showLoader: !seeded);
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
    _loadPromoFeatured();
    if (!_promoPopupShown) _loadPromoPopup();
    _loadPromoPortfolioShowcase();
    _loadPromoSponsorships();
    _loadPromoSnapshots();
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
        _providers = _sortFeaturedProviders(providers);
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

  Future<void> _loadPromoFeatured() async {
    try {
      final results = await Future.wait([
        ApiClient.get(
            '/api/promo/active/?service_type=featured_specialists&limit=10'),
        ApiClient.get('/api/promo/active/?ad_type=featured_top5&limit=10'),
      ]);
      if (!mounted) return;
      final items = <dynamic>[
        ..._promoItemsFromResponse(results[0]),
        ..._promoItemsFromResponse(results[1]),
      ];
      final ids = <int>{};
      for (final item in items) {
        final pid = item['target_provider_id'];
        if (pid != null) ids.add(pid is int ? pid : int.tryParse('$pid') ?? 0);
      }
      ids.remove(0);
      setState(() {
        _featuredProviderIds = ids;
        _providers = _sortFeaturedProviders(_providers);
      });
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
        dedupeKey: 'promo.popup_open:flutter.home:${providerId ?? 0}:${title.trim()}',
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
      final media = items
          .map(_portfolioItemFromPromoPlacement)
          .whereType<MediaItemModel>()
          .toList();
      if (!mounted) return;
      setState(() => _portfolioShowcase = media);
    } catch (_) {}
  }

  Future<void> _loadPromoSponsorships() async {
    try {
      final res = await ApiClient.get(
        '/api/promo/active/?service_type=sponsorship&limit=10',
      );
      if (!mounted || !res.isSuccess) return;
      final items = _promoMapItemsFromResponse(res);
      if (!mounted) return;
      setState(() => _sponsorships = items);
    } catch (_) {}
  }

  Future<void> _loadPromoSnapshots() async {
    try {
      final res = await ApiClient.get(
        '/api/promo/active/?service_type=snapshots&limit=10',
      );
      if (!mounted || !res.isSuccess) return;
      final items = _promoMapItemsFromResponse(res);
      if (!mounted) return;
      setState(() => _snapshotPlacements = items);
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

  List<ProviderPublicModel> _sortFeaturedProviders(
      List<ProviderPublicModel> providers) {
    if (_featuredProviderIds.isEmpty || providers.isEmpty) {
      return List<ProviderPublicModel>.from(providers);
    }
    final featured =
        providers.where((p) => _featuredProviderIds.contains(p.id)).toList();
    final rest =
        providers.where((p) => !_featuredProviderIds.contains(p.id)).toList();
    return [...featured, ...rest];
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

  String? _promoAssetUrl(Map<String, dynamic> placement) {
    final assets = placement['assets'];
    if (assets is List && assets.isNotEmpty) {
      final first = assets.first;
      if (first is Map) {
        final raw = (first['file'] ?? first['file_url']) as String?;
        return ApiClient.buildMediaUrl(raw);
      }
    }
    return null;
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

  Future<void> _openSponsorPlacement(Map<String, dynamic> placement) async {
    final providerId = placement['target_provider_id'];
    final parsedProviderId =
        providerId is int ? providerId : int.tryParse('$providerId');
    await _openPromoPlacement(
      redirectUrl: placement['redirect_url'] as String?,
      providerId: parsedProviderId,
      providerName:
          placement['target_provider_display_name'] as String? ?? 'مقدم خدمة',
    );
  }

  Future<void> _openBanner(BannerModel banner) async {
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
    final isActionable =
        (redirectUrl?.trim().isNotEmpty ?? false) ||
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
    _reelsTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (_reelsScroll.hasClients && mounted) {
        _reelsPos += 1.0;
        final half = _reelsScroll.position.maxScrollExtent / 2;
        if (_reelsPos >= half) {
          _reelsScroll.jumpTo(0);
          _reelsPos = 0;
        } else {
          _reelsScroll.jumpTo(_reelsPos);
        }
      }
    });
  }

  @override
  void dispose() {
    _reelsTimer?.cancel();
    _badgeListenable?.removeListener(_handleBadgeChange);
    UnreadBadgeService.release();
    _bannerAutoTimer?.cancel();
    _bannerPageController.dispose();
    _reelsScroll.dispose();
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
          isDark ? const Color(0xFF121212) : const Color(0xFFF5F5FA),
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
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // -- Hero header with banner + search --
            SliverToBoxAdapter(child: _buildHero()),

            // -- Reels carousel --
            SliverToBoxAdapter(child: _buildReels(isDark)),

            // -- Promo snapshots strip --
            if (_snapshotPlacements.isNotEmpty)
              SliverToBoxAdapter(child: _buildSnapshotsStrip(isDark, purple)),

            // -- Promo messages callout --
            if (_promoMessagePlacement != null && !_promoMessageDismissed)
              SliverToBoxAdapter(child: _buildPromoMessageCard(isDark, purple)),

            // -- Categories --
            SliverToBoxAdapter(child: _buildCategories(isDark, purple)),

            // -- Featured providers --
            SliverToBoxAdapter(child: _buildProviders(isDark, purple)),

            // -- Sponsored portfolio showcase --
            if (_portfolioShowcase.isNotEmpty)
              SliverToBoxAdapter(
                  child: _buildPortfolioShowcase(isDark, purple)),

            // -- Sponsorships --
            if (_sponsorships.isNotEmpty)
              SliverToBoxAdapter(child: _buildSponsorships(isDark, purple)),

            // -- Bottom safe area --
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  // =============================================
  //  HERO HEADER
  // =============================================

  Widget _buildHero() {
    return SizedBox(
      height: 280,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildHeroBannerBackground(),

          // Gradient overlay
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.black.withValues(alpha: 0.5),
                  Colors.black.withValues(alpha: 0.15),
                  Colors.transparent,
                ],
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
              ),
            ),
          ),

          // Content
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  // Top bar
                  Row(
                    children: [
                      // Menu
                      GestureDetector(
                        onTap: () => _scaffoldKey.currentState?.openDrawer(),
                        child: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.menu_rounded,
                              color: Colors.white, size: 20),
                        ),
                      ),
                      const Spacer(),
                      // Logo text
                      const Text(
                        'نوافــذ',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'Cairo',
                          color: Colors.white,
                          shadows: [
                            Shadow(color: Colors.black38, blurRadius: 8)
                          ],
                        ),
                      ),
                      const Spacer(),
                      // Notifications
                      _heroIconBtn(
                        icon: Icons.notifications_none_rounded,
                        count: _notificationUnread,
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const NotificationsScreen()),
                          );
                          _loadUnreadBadges();
                        },
                      ),
                      const SizedBox(width: 8),
                      // Chat
                      _heroIconBtn(
                        icon: Icons.chat_bubble_outline_rounded,
                        count: _chatUnread,
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const MyChatsScreen()),
                          );
                          _loadUnreadBadges();
                        },
                      ),
                    ],
                  ),

                  const Spacer(),

                  // Tagline
                  Text(
                    _content.heroTitle,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'Cairo',
                        color: Colors.white,
                        shadows: [
                          Shadow(color: Colors.black38, blurRadius: 6)
                        ]),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _content.renderHeroSubtitle(
                        providerCount: _providers.length),
                    style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'Cairo',
                        color: Colors.white.withValues(alpha: 0.85)),
                  ),
                  const SizedBox(height: 12),

                  // Search bar
                  GestureDetector(
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const SearchProviderScreen())),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 3))
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.search_rounded,
                              size: 18, color: Colors.grey.shade500),
                          const SizedBox(width: 8),
                          Text(_content.searchPlaceholder,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'Cairo',
                                  color: Colors.grey.shade500)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroBannerBackground() {
    if (_banners.isEmpty) {
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

    return PageView.builder(
      controller: _bannerPageController,
      itemCount: _banners.length,
      onPageChanged: (idx) {
        if (_bannerCurrentPage == idx) return;
        setState(() => _bannerCurrentPage = idx);
      },
      itemBuilder: (context, index) {
        final banner = _banners[index];
        final mediaUrl = ApiClient.buildMediaUrl(banner.mediaUrl);
        return GestureDetector(
          onTap: () => _openBanner(banner),
          child: _buildAdaptiveHeroBanner(
            banner: banner,
            mediaUrl: mediaUrl,
            isActive: index == _bannerCurrentPage,
          ),
        );
      },
    );
  }

  Widget _buildAdaptiveHeroBanner({
    required BannerModel banner,
    required String? mediaUrl,
    required bool isActive,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width;
        final viewportHeight =
            constraints.maxHeight.isFinite && constraints.maxHeight > 0
                ? constraints.maxHeight
                : 280.0;
        final stagePadding = _heroBannerStagePadding(
          width: viewportWidth,
          height: viewportHeight,
        );
        final borderRadius =
            _clampResponsiveValue(viewportWidth * 0.05, 18, 26);

        return Stack(
          fit: StackFit.expand,
          children: [
            _buildHeroBannerBackdrop(banner, mediaUrl),
            Positioned.fill(
              child: Padding(
                padding: stagePadding,
                child: _buildHeroBannerForeground(
                  banner: banner,
                  mediaUrl: mediaUrl,
                  isActive: isActive,
                  scale: banner.scaleForWidth(viewportWidth),
                  borderRadius: borderRadius,
                ),
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
      },
    );
  }

  double _clampResponsiveValue(double value, double minimum, double maximum) {
    if (value < minimum) return minimum;
    if (value > maximum) return maximum;
    return value;
  }

  EdgeInsets _heroBannerStagePadding({
    required double width,
    required double height,
  }) {
    final horizontal = _clampResponsiveValue(width * 0.045, 12, 36);
    final top = _clampResponsiveValue(height * 0.2, 48, 72);
    final bottom = _clampResponsiveValue(height * 0.34, 84, 118);
    return EdgeInsets.fromLTRB(horizontal, top, horizontal, bottom);
  }

  Widget _buildHeroBannerBackdrop(BannerModel banner, String? mediaUrl) {
    if (mediaUrl == null || banner.isVideo) {
      return _gradientPlaceholder();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Transform.scale(
            scale: 1.08,
            child: Image.network(
              mediaUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _gradientPlaceholder(),
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.black.withValues(alpha: 0.24),
                Colors.blueGrey.shade900.withValues(alpha: 0.18),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeroBannerForeground({
    required BannerModel banner,
    required String? mediaUrl,
    required bool isActive,
    required double scale,
    required double borderRadius,
  }) {
    if (mediaUrl == null) {
      return _gradientPlaceholder();
    }

    final radius = BorderRadius.circular(borderRadius);
    final foreground = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: ColoredBox(
          color: Colors.black.withValues(alpha: banner.isVideo ? 0.32 : 0.18),
          child: banner.isVideo
              ? PromoMediaTile(
                  key: ValueKey('hero-banner-${banner.id}-${banner.mediaUrl}'),
                  mediaUrl: mediaUrl,
                  mediaType: 'video',
                  borderRadius: 0,
                  autoplay: true,
                  isActive: isActive,
                  fit: BoxFit.contain,
                  showVideoBadge: false,
                  fallback: _gradientPlaceholder(),
                )
              : Image.network(
                  mediaUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => _gradientPlaceholder(),
                ),
        ),
      ),
    );
    return Transform.scale(scale: scale, child: foreground);
  }

  Widget _heroIconBtn({
    required IconData icon,
    required VoidCallback onTap,
    required int count,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          if (count > 0)
            Positioned(
              top: -4,
              right: -6,
              child: Container(
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  count > 99 ? '99+' : '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // =============================================
  //  REELS CAROUSEL
  // =============================================

  Widget _buildReels(bool isDark) {
    final hasData = _spotlights.isNotEmpty;

    if (!hasData) {
      return Container(
        height: 96,
        margin: const EdgeInsets.only(top: 12),
        alignment: Alignment.center,
        child: Text(
          'لا توجد لمحات حاليا',
          style: TextStyle(
            fontSize: 11,
            fontFamily: 'Cairo',
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
        ),
      );
    }

    return Container(
      height: 108,
      margin: const EdgeInsets.only(top: 12),
      child: ListView.builder(
        controller: _reelsScroll,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _spotlights.length,
        itemBuilder: (context, index) {
          final item = _spotlights[index];
          final thumb = _spotlightThumbUrl(item);
          final caption = (item.caption ?? '').trim();

          return GestureDetector(
            onTap: () => _openSpotlightViewer(index),
            child: SizedBox(
              width: 78,
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
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSnapshotsStrip(bool isDark, Color purple) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('لمحات ممولة', isDark),
          const SizedBox(height: 10),
          SizedBox(
            height: 124,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _snapshotPlacements.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final placement = _snapshotPlacements[index];
                final mediaUrl = _promoAssetUrl(placement);
                final assets = placement['assets'];
                final first = (assets is List && assets.isNotEmpty)
                    ? assets.first
                    : null;
                final mediaType = (first is Map)
                    ? ((first['file_type'] as String?) ?? 'image')
                    : 'image';
                return SizedBox(
                  width: 180,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () async {
                      await _openSponsorPlacement(placement);
                    },
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: PromoMediaTile(
                              mediaUrl: mediaUrl,
                              mediaType: mediaType,
                              height: 124,
                              borderRadius: 14,
                              autoplay: true,
                              isActive: true,
                              showVideoBadge: mediaType == 'video',
                              fallback: _gradientPlaceholder(),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              (placement['title'] as String?)?.trim().isNotEmpty ==
                                      true
                                  ? (placement['title'] as String)
                                  : 'لمحة ممولة',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'Cairo',
                              ),
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
        ],
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
    final providerId = providerIdRaw is int
        ? providerIdRaw
        : int.tryParse('$providerIdRaw');
    final providerName = placement['target_provider_display_name'] as String?;
    final redirectUrl = placement['redirect_url'] as String?;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1F1A2A) : const Color(0xFFF2ECFF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: purple.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF2A1A4A),
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'إخفاء',
                  onPressed: () {
                    if (!mounted) return;
                    setState(() => _promoMessageDismissed = true);
                  },
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ),
            if (body.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Text(
                  body,
                  style: TextStyle(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.85)
                        : Colors.black87,
                    fontSize: 12,
                    height: 1.5,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonal(
                onPressed: () async {
                  await _openPromoPlacement(
                    redirectUrl: redirectUrl,
                    providerId: providerId,
                    providerName: providerName,
                  );
                },
                child: const Text('عرض التفاصيل'),
              ),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(_content.categoriesTitle, isDark),
          const SizedBox(height: 10),
          if (_categories.isEmpty)
            SizedBox(
              height: 72,
              child: Center(
                child: Text(
                  'لا توجد تصنيفات متاحة حالياً',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ),
            )
          else
            SizedBox(
              height: 82,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
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
                                initialCategoryId: cat.id > 0 ? cat.id : null),
                          ));
                    },
                    child: Container(
                      width: 76,
                      margin: const EdgeInsets.only(left: 8),
                      child: Column(
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.06)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: isDark
                                  ? null
                                  : [
                                      BoxShadow(
                                          color: Colors.black
                                              .withValues(alpha: 0.05),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2))
                                    ],
                            ),
                            child: Icon(icon, size: 22, color: purple),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            cat.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'Cairo',
                                color:
                                    isDark ? Colors.white70 : Colors.black87),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  // =============================================
  //  FEATURED PROVIDERS
  // =============================================

  Widget _buildProviders(bool isDark, Color purple) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _sectionTitle(_content.providersTitle, isDark),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const SearchProviderScreen())),
                child: Text('عرض الكل',
                    style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.w600,
                        color: purple)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_isLoading)
            const SizedBox(
                height: 160,
                child: Center(
                    child: CircularProgressIndicator(color: Colors.deepPurple)))
          else if (_providers.isEmpty)
            SizedBox(
              height: 80,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 20,
                        color: isDark ? Colors.white24 : Colors.grey.shade300),
                    const SizedBox(height: 4),
                    Text('لا يوجد مزودو خدمة حالياً',
                        style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'Cairo',
                            color: isDark
                                ? Colors.white30
                                : Colors.grey.shade400)),
                  ],
                ),
              ),
            )
          else
            SizedBox(
              height: 180,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _providers.length,
                itemBuilder: (context, index) =>
                    _providerCard(_providers[index], isDark, purple),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPortfolioShowcase(bool isDark, Color purple) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('مشاريع ممولة', isDark),
          const SizedBox(height: 10),
          SizedBox(
            height: 206,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _portfolioShowcase.length,
              itemBuilder: (context, index) => _portfolioShowcaseCard(
                _portfolioShowcase[index],
                index,
                isDark,
                purple,
              ),
            ),
          ),
        ],
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
      onTap: () => _openPortfolioShowcaseViewer(index),
      child: Container(
        width: 182,
        margin: const EdgeInsets.only(left: 12),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
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
                      top: Radius.circular(18),
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
                        'ممّول',
                        style: TextStyle(
                          fontSize: 9,
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
                            fontSize: 11.5,
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
                            fontSize: 9.5,
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

  Future<void> _openPortfolioShowcaseViewer(int index) async {
    if (_portfolioShowcase.isEmpty) return;
    _reelsTimer?.cancel();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SpotlightViewerPage(
          items: _portfolioShowcase,
          initialIndex: index,
        ),
      ),
    );
    if (mounted) {
      _syncSpotlightInteractionState();
      _startReelsScroll();
    }
  }

  Widget _providerCard(ProviderPublicModel p, bool isDark, Color purple) {
    final profileUrl = ApiClient.buildMediaUrl(p.profileImage);
    final coverUrl = ApiClient.buildMediaUrl(p.coverImage);

    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProviderProfileScreen(
              providerId: p.id.toString(),
              providerName: p.displayName,
              providerImage: ApiClient.buildMediaUrl(p.profileImage),
              providerRating: p.ratingAvg,
              providerVerifiedBlue: p.isVerifiedBlue,
              providerVerifiedGreen: p.isVerifiedGreen,
              providerPhone: p.phone,
              providerLat: p.lat,
              providerLng: p.lng,
              providerOperations: p.completedRequests,
            ),
          ),
        );
        _syncSpotlightInteractionState();
      },
      child: Container(
        width: 150,
        margin: const EdgeInsets.only(left: 10),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 6,
                      offset: const Offset(0, 2))
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
              child: SizedBox(
                height: 70,
                width: double.infinity,
                child: coverUrl != null
                    ? Image.network(coverUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _gradientPlaceholder())
                    : _gradientPlaceholder(),
              ),
            ),

            // Avatar + Info
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: purple.withValues(alpha: 0.1),
                    backgroundImage:
                        profileUrl != null ? NetworkImage(profileUrl) : null,
                    child: profileUrl == null
                        ? Text(
                            p.displayName.isNotEmpty ? p.displayName[0] : '؟',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: purple))
                        : null,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(p.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      fontFamily: 'Cairo',
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black87)),
                            ),
                            if (p.isVerified) ...[
                              const SizedBox(width: 2),
                              VerifiedBadgeView(
                                isVerifiedBlue: p.isVerifiedBlue,
                                isVerifiedGreen: p.isVerifiedGreen,
                                iconSize: 11,
                              ),
                            ],
                            if (_featuredProviderIds.contains(p.id)) ...[
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(colors: [
                                    Color(0xFFF59E0B),
                                    Color(0xFFD97706)
                                  ]),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text('مميز',
                                    style: TextStyle(
                                        fontSize: 8,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white)),
                              ),
                            ],
                          ],
                        ),
                        if (p.hasExcellenceBadges)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: ExcellenceBadgesWrap(
                              badges: p.excellenceBadges,
                              compact: true,
                            ),
                          ),
                        if (p.city != null)
                          Text(p.city!,
                              style: TextStyle(
                                  fontSize: 9,
                                  fontFamily: 'Cairo',
                                  color: isDark
                                      ? Colors.grey.shade600
                                      : Colors.grey.shade500)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const Spacer(),

            // Stats
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _miniProviderStat(
                      Icons.star_rounded,
                      p.ratingAvg > 0 ? p.ratingAvg.toStringAsFixed(1) : '-',
                      Colors.amber),
                  _miniProviderStat(Icons.people_outline, '${p.followersCount}',
                      isDark ? Colors.grey.shade500 : Colors.grey.shade500),
                  _miniProviderStat(Icons.favorite_outline, '${p.likesCount}',
                      isDark ? Colors.grey.shade500 : Colors.grey.shade500),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniProviderStat(IconData icon, String val, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 2),
        Text(val,
            style: TextStyle(fontSize: 9.5, fontFamily: 'Cairo', color: color)),
      ],
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

  void _startBannerAutoRotate() {
    _bannerAutoTimer?.cancel();
    if (_banners.length <= 1) return;
    _bannerAutoTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted || !_bannerPageController.hasClients) return;
      final next = (_bannerCurrentPage + 1) % _banners.length;
      _bannerPageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
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
                              key: ValueKey('promo-banner-${b.id}-${b.mediaUrl}'),
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

  Widget _buildSponsorships(bool isDark, Color purple) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('الرعاة', isDark),
          const SizedBox(height: 10),
          SizedBox(
            height: 164,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _sponsorships.length,
              itemBuilder: (context, index) => _sponsorshipCard(
                _sponsorships[index],
                isDark,
                purple,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sponsorshipCard(
    Map<String, dynamic> placement,
    bool isDark,
    Color purple,
  ) {
    final imageUrl = _promoAssetUrl(placement);
    final sponsorName =
        (placement['sponsor_name'] as String?)?.trim().isNotEmpty == true
            ? (placement['sponsor_name'] as String).trim()
            : ((placement['target_provider_display_name'] as String?)?.trim() ??
                'راعٍ رسمي');
    final caption = (placement['message_body'] as String?)?.trim() ?? '';
    final duration = placement['sponsorship_months'];
    final months = duration is int ? duration : int.tryParse('$duration') ?? 0;

    return GestureDetector(
      onTap: () => _openSponsorPlacement(placement),
      child: Container(
        width: 232,
        margin: const EdgeInsets.only(left: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            colors: isDark
                ? const [Color(0xFF30284A), Color(0xFF1F1A31)]
                : const [Color(0xFFFFF7E8), Color(0xFFF6F0FF)],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : const Color(0xFFE8DDBA),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: purple.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    months > 0 ? 'رعاية $months' 'ش' : 'رعاية',
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Cairo',
                      color: Colors.deepPurple,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: Colors.white.withValues(alpha: 0.65),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: imageUrl != null
                      ? Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _gradientPlaceholder(),
                        )
                      : _gradientPlaceholder(),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              sponsorName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                fontFamily: 'Cairo',
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            if (caption.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                caption,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5,
                  fontFamily: 'Cairo',
                  color: isDark ? Colors.white70 : Colors.grey.shade700,
                ),
              ),
            ],
          ],
        ),
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
  final String heroTitle;
  final String heroSubtitle;
  final String searchPlaceholder;
  final String categoriesTitle;
  final String providersTitle;
  final String bannersTitle;

  const HomeScreenContent({
    required this.heroTitle,
    required this.heroSubtitle,
    required this.searchPlaceholder,
    required this.categoriesTitle,
    required this.providersTitle,
    required this.bannersTitle,
  });

  factory HomeScreenContent.empty() {
    return const HomeScreenContent(
      heroTitle: '...',
      heroSubtitle: '...',
      searchPlaceholder: '...',
      categoriesTitle: '...',
      providersTitle: '...',
      bannersTitle: '...',
    );
  }

  factory HomeScreenContent.fromBlocks(Map<String, dynamic> blocks) {
    String resolve(String key, String fallback) {
      final block = blocks[key];
      if (block is! Map<String, dynamic>) return fallback;
      final title = (block['title_ar'] as String?)?.trim() ?? '';
      return title.isNotEmpty ? title : fallback;
    }

    return HomeScreenContent(
      heroTitle: resolve('home_hero_title', 'الرئيسية'),
      heroSubtitle: resolve(
        'home_hero_subtitle',
        'مزودون موثّقون وخدمات مرتبة لتبدأ بشكل أسرع وأكثر وضوحًا.',
      ),
      searchPlaceholder: resolve('home_search_placeholder', 'ابحث'),
      categoriesTitle: resolve('home_categories_title', 'التصنيفات'),
      providersTitle: resolve('home_providers_title', 'مقدمو الخدمة'),
      bannersTitle: resolve('home_banners_title', 'عروض ترويجية'),
    );
  }

  String renderHeroSubtitle({required int providerCount}) {
    final value = heroSubtitle.trim();
    if (value.isEmpty) return '';
    return value.replaceAll('{provider_count}', providerCount.toString());
  }
}
