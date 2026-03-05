import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../widgets/bottom_nav.dart';
import '../widgets/custom_drawer.dart';
import '../services/api_client.dart';
import '../services/home_service.dart';
import '../models/category_model.dart';
import '../models/banner_model.dart';
import '../models/provider_public_model.dart';
import '../models/media_item_model.dart';
import '../widgets/spotlight_viewer.dart';
import '../widgets/verified_badge_view.dart';

import 'search_provider_screen.dart';
import 'provider_profile_screen.dart';
import 'notifications_screen.dart';
import 'my_chats_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // -- Data --
  List<CategoryModel> _categories = [];
  List<ProviderPublicModel> _providers = [];
  List<BannerModel> _banners = [];
  List<MediaItemModel> _spotlights = [];
  bool _isLoading = true;

  // -- Banner video --
  VideoPlayerController? _videoController;
  bool _videoReady = false;

  // -- Reels auto scroll --
  final ScrollController _reelsScroll = ScrollController();
  Timer? _reelsTimer;
  double _reelsPos = 0;

  static const _reelFallbackLogos = [
    'assets/images/32.jpeg',
    'assets/images/841015.jpeg',
    'assets/images/879797.jpeg',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initVideo();
    final seeded = _seedFromCachedData();
    _loadData(showLoader: !seeded);
    _startReelsScroll();
  }

  void _initVideo() {
    _videoController = VideoPlayerController.asset('assets/videos/V16.mp4')
      ..setLooping(true)
      ..setVolume(0)
      ..initialize().then((_) {
        if (mounted) { setState(() => _videoReady = true); _videoController!.play(); }
      });
  }

  bool _seedFromCachedData() {
    final cached = HomeService.getCachedHomeData(
      providersLimit: 10,
      bannersLimit: 6,
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

    final categoriesFuture = HomeService.fetchCategories(forceRefresh: forceRefresh);
    final providersFuture = HomeService.fetchFeaturedProviders(
      limit: 10,
      forceRefresh: forceRefresh,
    );
    final bannersFuture = HomeService.fetchHomeBanners(
      limit: 6,
      forceRefresh: forceRefresh,
    );
    final spotlightsFuture = HomeService.fetchSpotlightFeed(
      limit: 16,
      forceRefresh: forceRefresh,
    );

    categoriesFuture.then((categories) {
      if (!mounted) return;
      setState(() => _categories = categories);
    });

    bannersFuture.then((banners) {
      if (!mounted) return;
      setState(() => _banners = banners);
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
      await Future.wait([categoriesFuture, providersFuture, bannersFuture, spotlightsFuture]);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _startReelsScroll() {
    _reelsTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (_reelsScroll.hasClients && mounted) {
        _reelsPos += 1.0;
        final half = _reelsScroll.position.maxScrollExtent / 2;
        if (_reelsPos >= half) { _reelsScroll.jumpTo(0); _reelsPos = 0; }
        else { _reelsScroll.jumpTo(_reelsPos); }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_videoController == null || !_videoReady) return;
    if (state == AppLifecycleState.resumed) { _videoController!.play(); }
    else if (state == AppLifecycleState.paused) { _videoController!.pause(); }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _videoController?.dispose();
    _reelsTimer?.cancel();
    _reelsScroll.dispose();
    super.dispose();
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
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF5F5FA),
      drawer: const CustomDrawer(),
      bottomNavigationBar: const CustomBottomNav(currentIndex: 0),
      body: RefreshIndicator(
        onRefresh: () => _loadData(forceRefresh: true, showLoader: false),
        color: purple,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // -- Hero header with video + search --
            SliverToBoxAdapter(child: _buildHero(isDark, purple)),

            // -- Reels carousel --
            SliverToBoxAdapter(child: _buildReels(isDark)),

            // -- Categories --
            SliverToBoxAdapter(child: _buildCategories(isDark, purple)),

            // -- Featured providers --
            SliverToBoxAdapter(child: _buildProviders(isDark, purple)),

            // -- Promo banners --
            if (_banners.isNotEmpty)
              SliverToBoxAdapter(child: _buildPromoBanners(isDark, purple)),

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

  Widget _buildHero(bool isDark, Color purple) {
    return SizedBox(
      height: 280,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Video background
          if (_videoReady && _videoController != null)
            FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: _videoController!.value.size.width,
                height: _videoController!.value.size.height,
                child: VideoPlayer(_videoController!),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.deepPurple.shade700, Colors.deepPurple.shade400],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
              ),
            ),

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
                          child: const Icon(Icons.menu_rounded, color: Colors.white, size: 20),
                        ),
                      ),
                      const Spacer(),
                      // Logo text
                      const Text(
                        'نوافــذ',
                        style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w900, fontFamily: 'Cairo',
                          color: Colors.white,
                          shadows: [Shadow(color: Colors.black38, blurRadius: 8)],
                        ),
                      ),
                      const Spacer(),
                      // Notifications
                      _heroIconBtn(Icons.notifications_none_rounded, () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
                      }),
                      const SizedBox(width: 8),
                      // Chat
                      _heroIconBtn(Icons.chat_bubble_outline_rounded, () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const MyChatsScreen()));
                      }),
                    ],
                  ),

                  const Spacer(),

                  // Tagline
                  const Text(
                    'اعثر على الخدمة المناسبة',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, fontFamily: 'Cairo', color: Colors.white,
                      shadows: [Shadow(color: Colors.black38, blurRadius: 6)]),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'أكثر من ${_providers.isNotEmpty ? _providers.length : "100"} مقدم خدمة بين يديك',
                    style: TextStyle(fontSize: 11, fontFamily: 'Cairo', color: Colors.white.withValues(alpha: 0.85)),
                  ),
                  const SizedBox(height: 12),

                  // Search bar
                  GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchProviderScreen())),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 3))],
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.search_rounded, size: 18, color: Colors.grey.shade500),
                          const SizedBox(width: 8),
                          Text('ابحث عن خدمة أو مقدم خدمة...', style: TextStyle(fontSize: 12, fontFamily: 'Cairo', color: Colors.grey.shade500)),
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

  Widget _heroIconBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
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
                    fallbackIcon: item.isVideo ? Icons.play_arrow_rounded : Icons.image_rounded,
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
                colors: [Color(0xFF9F57DB), Color(0xFFF1A559), Color(0xFFC8A5FC), Color(0xFF9F57DB)],
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
                          errorBuilder: (_, __, ___) => _reelFallback(fallbackIcon),
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
    if (_spotlights.isEmpty || !mounted) return;
    setState(() {
      MediaItemModel.applyInteractionOverrides(_spotlights);
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
    // Fallback static categories if API returns empty
    final cats = _categories.isNotEmpty
        ? _categories
        : _defaultCategories;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('التصنيفات', isDark),
          const SizedBox(height: 10),
          SizedBox(
            height: 82,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: cats.length,
              itemBuilder: (context, index) {
                final cat = cats[index];
                final icon = _categoryIcon(cat.name);
                return GestureDetector(
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => SearchProviderScreen(initialCategoryId: cat.id > 0 ? cat.id : null),
                    ));
                  },
                  child: Container(
                    width: 76,
                    margin: const EdgeInsets.only(left: 8),
                    child: Column(
                      children: [
                        Container(
                          width: 50, height: 50,
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: isDark ? null : [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
                          ),
                          child: Icon(icon, size: 22, color: purple),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          cat.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, fontFamily: 'Cairo',
                            color: isDark ? Colors.white70 : Colors.black87),
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
              _sectionTitle('مقدمو الخدمة', isDark),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchProviderScreen())),
                child: Text('عرض الكل', style: TextStyle(fontSize: 11, fontFamily: 'Cairo', fontWeight: FontWeight.w600, color: purple)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_isLoading)
            const SizedBox(height: 160, child: Center(child: CircularProgressIndicator(color: Colors.deepPurple)))
          else if (_providers.isEmpty)
            SizedBox(
              height: 80,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline_rounded, size: 20, color: isDark ? Colors.white24 : Colors.grey.shade300),
                    const SizedBox(height: 4),
                    Text('لا يوجد مزودو خدمة حالياً', style: TextStyle(fontSize: 10, fontFamily: 'Cairo',
                        color: isDark ? Colors.white30 : Colors.grey.shade400)),
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
                itemBuilder: (context, index) => _providerCard(_providers[index], isDark, purple),
              ),
            ),
        ],
      ),
    );
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
          boxShadow: isDark ? null : [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              child: SizedBox(
                height: 70,
                width: double.infinity,
                child: coverUrl != null
                    ? Image.network(coverUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _gradientPlaceholder())
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
                    backgroundImage: profileUrl != null ? NetworkImage(profileUrl) : null,
                    child: profileUrl == null
                        ? Text(p.displayName.isNotEmpty ? p.displayName[0] : '؟',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: purple))
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
                              child: Text(p.displayName, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, fontFamily: 'Cairo',
                                  color: isDark ? Colors.white : Colors.black87)),
                            ),
                            if (p.isVerified) ...[
                              const SizedBox(width: 2),
                              VerifiedBadgeView(
                                isVerifiedBlue: p.isVerifiedBlue,
                                isVerifiedGreen: p.isVerifiedGreen,
                                iconSize: 11,
                              ),
                            ],
                          ],
                        ),
                        if (p.city != null)
                          Text(p.city!, style: TextStyle(fontSize: 9, fontFamily: 'Cairo',
                            color: isDark ? Colors.grey.shade600 : Colors.grey.shade500)),
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
                  _miniProviderStat(Icons.star_rounded, p.ratingAvg > 0 ? p.ratingAvg.toStringAsFixed(1) : '-', Colors.amber),
                  _miniProviderStat(Icons.people_outline, '${p.followersCount}', isDark ? Colors.grey.shade500 : Colors.grey.shade500),
                  _miniProviderStat(Icons.favorite_outline, '${p.likesCount}', isDark ? Colors.grey.shade500 : Colors.grey.shade500),
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
        Text(val, style: TextStyle(fontSize: 9.5, fontFamily: 'Cairo', color: color)),
      ],
    );
  }

  Widget _gradientPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.deepPurple.shade200, Colors.deepPurple.shade100],
          begin: Alignment.topRight, end: Alignment.bottomLeft,
        ),
      ),
      child: const Center(child: Icon(Icons.image_outlined, size: 20, color: Colors.white54)),
    );
  }

  // =============================================
  //  PROMO BANNERS
  // =============================================

  Widget _buildPromoBanners(bool isDark, Color purple) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('عروض ترويجية', isDark),
          const SizedBox(height: 10),
          SizedBox(
            height: 130,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _banners.length,
              itemBuilder: (context, index) {
                final b = _banners[index];
                final url = ApiClient.buildMediaUrl(b.fileUrl);
                return GestureDetector(
                  onTap: () {
                    if (b.providerId != null && b.providerId! > 0) {
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => ProviderProfileScreen(
                          providerId: b.providerId.toString(),
                          providerName: b.providerDisplayName,
                        ),
                      ));
                    }
                  },
                  child: Container(
                  width: 220,
                  margin: const EdgeInsets.only(left: 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        url != null
                            ? Image.network(url, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _gradientPlaceholder())
                            : _gradientPlaceholder(),
                        // Bottom info
                        Positioned(
                          bottom: 0, left: 0, right: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Colors.black.withValues(alpha: 0.65), Colors.transparent],
                                begin: Alignment.bottomCenter, end: Alignment.topCenter,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (b.caption != null && b.caption!.isNotEmpty)
                                  Text(b.caption!, maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, fontFamily: 'Cairo', color: Colors.white)),
                                if (b.providerDisplayName != null)
                                  Text(b.providerDisplayName!, maxLines: 1,
                                    style: TextStyle(fontSize: 9, fontFamily: 'Cairo', color: Colors.white.withValues(alpha: 0.8))),
                              ],
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
        fontSize: 14, fontWeight: FontWeight.w800, fontFamily: 'Cairo',
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
    if (n.contains('صح') || n.contains('طب')) return Icons.health_and_safety_rounded;
    if (n.contains('ترجم')) return Icons.translate_rounded;
    if (n.contains('برمج') || n.contains('تقن')) return Icons.code_rounded;
    if (n.contains('صيان')) return Icons.build_rounded;
    if (n.contains('رياض')) return Icons.fitness_center_rounded;
    if (n.contains('منزل')) return Icons.home_repair_service_rounded;
    if (n.contains('مال')) return Icons.attach_money_rounded;
    if (n.contains('تسويق')) return Icons.campaign_rounded;
    if (n.contains('تعليم') || n.contains('تدريب')) return Icons.school_rounded;
    if (n.contains('سيار') || n.contains('نقل')) return Icons.directions_car_rounded;
    return Icons.category_rounded;
  }

  // Fallback categories when API returns empty
  static final _defaultCategories = [
    CategoryModel(id: 0, name: 'استشارات قانونية'),
    CategoryModel(id: 0, name: 'خدمات هندسية'),
    CategoryModel(id: 0, name: 'تصميم جرافيك'),
    CategoryModel(id: 0, name: 'توصيل سريع'),
    CategoryModel(id: 0, name: 'رعاية صحية'),
    CategoryModel(id: 0, name: 'ترجمة لغات'),
    CategoryModel(id: 0, name: 'برمجة مواقع'),
    CategoryModel(id: 0, name: 'صيانة أجهزة'),
  ];
}
