import 'package:flutter/material.dart';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/provider.dart';
import '../models/provider_portfolio_item.dart';
import '../models/user_summary.dart';
import '../services/account_api.dart';
import '../services/chat_nav.dart';
import '../services/providers_api.dart';
import '../services/role_controller.dart';
import '../utils/auth_guard.dart';
import '../constants/colors.dart';
import '../widgets/app_bar.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/custom_drawer.dart';
import 'network_video_player_screen.dart';
import 'service_request_form_screen.dart';

enum InteractiveMode {
  auto,
  client,
  provider,
}

class InteractiveScreen extends StatefulWidget {
  final InteractiveMode mode;
  final int initialTabIndex;

  const InteractiveScreen({
    super.key,
    this.mode = InteractiveMode.auto,
    this.initialTabIndex = 0,
  });

  @override
  State<InteractiveScreen> createState() => _InteractiveScreenState();
}

class _InteractiveScreenState extends State<InteractiveScreen>
  with TickerProviderStateMixin {
  late TabController _tabController;
  late final AnimationController _shimmerController;
  late InteractiveMode _effectiveMode;

  final ProvidersApi _providersApi = ProvidersApi();
  final AccountApi _accountApi = AccountApi();

  bool _capabilitiesLoaded = false;
  String? _followingError;
  String? _followersError;
  String? _favoritesError;

  String? _myDisplayName;
  String? _myHandle;

  // Data Futures
  Future<List<ProviderProfile>>? _followingFuture;
  Future<List<UserSummary>>? _followersFuture;
  Future<List<ProviderPortfolioItem>>? _favoritesFuture;
  final Set<int> _unfollowingProviderIds = <int>{};
  final Set<int> _unfavoritingItemIds = <int>{};
  final Map<int, int> _favoriteMediaRetryNonce = <int, int>{};
  final Set<String> _favoritePreviewsPrefetched = <String>{};

  List<ProviderProfile> _sortFollowing(List<ProviderProfile> items) {
    final out = List<ProviderProfile>.from(items);
    out.sort((a, b) => b.id.compareTo(a.id));
    return out;
  }

  List<UserSummary> _sortFollowers(List<UserSummary> items) {
    final seen = <int>{};
    final out = <UserSummary>[];
    for (final item in items) {
      if (seen.add(item.id)) out.add(item);
    }
    out.sort((a, b) => b.id.compareTo(a.id));
    return out;
  }

  List<ProviderPortfolioItem> _sortFavorites(List<ProviderPortfolioItem> items) {
    final out = List<ProviderPortfolioItem>.from(items);
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  int _favoriteRetryNonceFor(int itemId) => _favoriteMediaRetryNonce[itemId] ?? 0;

  void _retryFavoriteMedia(int itemId) {
    if (!mounted) return;
    setState(() {
      _favoriteMediaRetryNonce[itemId] = _favoriteRetryNonceFor(itemId) + 1;
    });
  }

  String _favoritePreviewUrl(String rawUrl, int itemId) {
    final base = rawUrl.trim();
    if (base.isEmpty) return base;
    final nonce = _favoriteRetryNonceFor(itemId);
    if (nonce <= 0) return base;
    final sep = base.contains('?') ? '&' : '?';
    return '$base${sep}retry=$nonce';
  }

  void _precacheFavoritePreviews(List<ProviderPortfolioItem> items) {
    if (!mounted) return;
    final candidates = items.take(8).map((item) {
      if (item.fileType.toLowerCase() == 'video') {
        return (item.thumbnailUrl ?? '').trim();
      }
      return item.fileUrl.trim();
    }).where((u) => u.isNotEmpty);

    for (final url in candidates) {
      if (_favoritePreviewsPrefetched.contains(url)) continue;
      _favoritePreviewsPrefetched.add(url);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        precacheImage(CachedNetworkImageProvider(url), context).catchError((_) {});
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _effectiveMode =
        widget.mode == InteractiveMode.auto ? InteractiveMode.client : widget.mode;
    
    final initialLength = _effectiveMode == InteractiveMode.provider ? 3 : 2;
    _tabController = TabController(
      length: initialLength, 
      vsync: this, 
      initialIndex: 0 
    );
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _guardAndLoadInitial();
    });
    RoleController.instance.notifier.addListener(_onActiveRoleChanged);
  }

  void _onActiveRoleChanged() {
    _loadCapabilitiesAndReload();
  }

  Future<void> _guardAndLoadInitial() async {
    final canOpen = await checkAuth(context);
    if (!mounted) return;
    if (!canOpen) {
      setState(() {
        _capabilitiesLoaded = true;
        _followingError = 'تسجيل الدخول مطلوب لعرض صفحة تفاعلي';
        _followersError = 'تسجيل الدخول مطلوب لعرض صفحة تفاعلي';
        _favoritesError = 'تسجيل الدخول مطلوب لعرض صفحة تفاعلي';
        _followingFuture = Future<List<ProviderProfile>>.value(const <ProviderProfile>[]);
        _followersFuture = Future<List<UserSummary>>.value(const <UserSummary>[]);
        _favoritesFuture =
            Future<List<ProviderPortfolioItem>>.value(const <ProviderPortfolioItem>[]);
      });
      return;
    }
    await _loadCapabilitiesAndReload();
  }

  String _mapInteractiveLoadError(
    Object error, {
    required String fallback,
    String? forbiddenMessage,
  }) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status == 401) {
        return 'انتهت الجلسة أو يلزم تسجيل الدخول مرة أخرى';
      }
      if (status == 403) {
        return forbiddenMessage ?? 'لا تملك صلاحية الوصول لهذه البيانات';
      }
    }
    return fallback;
  }

  Future<void> _loadCapabilitiesAndReload() async {
    try {
      final me = await _accountApi.me().timeout(const Duration(seconds: 12));
      final hasProviderProfile = me['has_provider_profile'] == true;
      final isProviderActive = RoleController.instance.notifier.value.isProvider;
      final firstName = (me['first_name'] ?? '').toString().trim();
      final lastName = (me['last_name'] ?? '').toString().trim();
      final username = (me['username'] ?? '').toString().trim();
      final providerDisplayName = (me['provider_display_name'] ?? '').toString().trim();
      final fullName = [firstName, lastName].where((e) => e.isNotEmpty).join(' ').trim();
      final displayName = fullName.isNotEmpty
          ? fullName
          : (providerDisplayName.isNotEmpty ? providerDisplayName : (username.isNotEmpty ? username : 'تفاعلي'));
      if (!mounted) return;
      
      final newMode = widget.mode == InteractiveMode.auto
          ? ((hasProviderProfile && isProviderActive)
              ? InteractiveMode.provider
              : InteractiveMode.client)
          : widget.mode;

      final effectiveMode = (newMode == InteractiveMode.provider && !hasProviderProfile)
          ? InteractiveMode.client
          : newMode;

      final newLength = effectiveMode == InteractiveMode.provider ? 3 : 2;
      final newIndex = widget.initialTabIndex.clamp(0, newLength - 1);
      final newController = TabController(length: newLength, vsync: this, initialIndex: newIndex);
      final oldController = _tabController;

      setState(() {
        _effectiveMode = effectiveMode;
        _capabilitiesLoaded = true;
        _myDisplayName = displayName;
        _myHandle = username.isEmpty ? null : '@$username';
        _tabController = newController;
      });
      oldController.dispose();
      
    } catch (_) {
      if (!mounted) return;
      final effectiveMode = widget.mode == InteractiveMode.provider
          ? InteractiveMode.provider
          : InteractiveMode.client;

      final newLength = effectiveMode == InteractiveMode.provider ? 3 : 2;
      final newIndex = widget.initialTabIndex.clamp(0, newLength - 1);
      final newController = TabController(length: newLength, vsync: this, initialIndex: newIndex);
      final oldController = _tabController;

      setState(() {
        _effectiveMode = effectiveMode;
        _capabilitiesLoaded = true;
        _myDisplayName = null;
        _myHandle = null;
        _tabController = newController;
      });
      oldController.dispose();
    }
    _reload();
  }

  void _reload() {
    setState(() {
      _followingError = null;
      _followersError = null;
      _favoritesError = null;
      _followingFuture = _loadFollowingSafe();
      _followersFuture = _effectiveMode == InteractiveMode.provider
          ? _loadFollowersSafe()
          : Future<List<UserSummary>>.value(const <UserSummary>[]);
      _favoritesFuture = _loadFavoritesSafe();
    });
  }

  Future<List<ProviderProfile>> _loadFollowingSafe() async {
    try {
      return await _providersApi.getMyFollowingProviders().timeout(const Duration(seconds: 12));
    } on TimeoutException {
      if (mounted) setState(() => _followingError = 'انتهت مهلة تحميل قائمة المتابعة');
      return const [];
    } catch (e) {
      if (mounted) {
        setState(() {
          _followingError = _mapInteractiveLoadError(
            e,
            fallback: 'تعذر تحميل قائمة المتابعة',
          );
        });
      }
      return const [];
    }
  }

  Future<List<UserSummary>> _loadFollowersSafe() async {
    try {
      return await _providersApi.getMyProviderFollowers().timeout(const Duration(seconds: 12));
    } on TimeoutException {
      if (mounted) setState(() => _followersError = 'انتهت مهلة تحميل قائمة المتابعين');
      return const [];
    } catch (e) {
      if (mounted) {
        setState(() {
          _followersError = _mapInteractiveLoadError(
            e,
            fallback: 'تعذر تحميل قائمة المتابعين',
            forbiddenMessage: 'هذه القائمة متاحة لحسابات مزودي الخدمة فقط',
          );
        });
      }
      return const [];
    }
  }

  Future<List<ProviderPortfolioItem>> _loadFavoritesSafe() async {
    try {
      return await _providersApi.getMyFavoriteMedia().timeout(const Duration(seconds: 12));
    } on TimeoutException {
      if (mounted) setState(() => _favoritesError = 'انتهت مهلة تحميل المفضلة');
      return const [];
    } catch (e) {
      if (mounted) {
        setState(() {
          _favoritesError = _mapInteractiveLoadError(
            e,
            fallback: 'تعذر تحميل المفضلة',
          );
        });
      }
      return const [];
    }
  }

  Future<void> _refreshInteractiveData() async {
    _reload();
    final waiters = <Future<dynamic>>[];
    if (_followingFuture != null) waiters.add(_followingFuture!);
    if (_favoritesFuture != null) waiters.add(_favoritesFuture!);
    if (_effectiveMode == InteractiveMode.provider && _followersFuture != null) {
      waiters.add(_followersFuture!);
    }
    await Future.wait(waiters);
  }

  Future<void> _unfollowProvider(ProviderProfile provider) async {
    if (_unfollowingProviderIds.contains(provider.id)) return;
    setState(() => _unfollowingProviderIds.add(provider.id));
    final ok = await _providersApi.unfollowProvider(provider.id);
    if (!mounted) return;
    setState(() => _unfollowingProviderIds.remove(provider.id));
    if (ok) {
      _reload();
      _showSnack('تم إلغاء المتابعة');
      return;
    }
    _showSnack('تعذر إلغاء المتابعة');
  }

  Future<void> _removeFavoriteMedia(ProviderPortfolioItem item) async {
    if (_unfavoritingItemIds.contains(item.id)) return;
    setState(() => _unfavoritingItemIds.add(item.id));
    final ok = await _providersApi.unlikePortfolioItem(item.id);
    if (!mounted) return;
    setState(() => _unfavoritingItemIds.remove(item.id));
    if (ok) {
      _reload();
      _showSnack('تمت الإزالة من المفضلة');
      return;
    }
    _showSnack('تعذرت إزالة العنصر من المفضلة');
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, style: const TextStyle(fontFamily: 'Cairo'))),
    );
  }

  @override
  void dispose() {
    RoleController.instance.notifier.removeListener(_onActiveRoleChanged);
    _shimmerController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompact = screenWidth < 360;
    final isTablet = screenWidth >= 700;

    // Elegant tab style
    final tabLabelStyle = TextStyle(
      fontFamily: 'Cairo',
      fontSize: isCompact ? 12.5 : 14,
      fontWeight: FontWeight.bold,
    );
    final tabUnselectedLabelStyle = TextStyle(
      fontFamily: 'Cairo',
      fontSize: isCompact ? 12.5 : 14,
      fontWeight: FontWeight.normal,
    );

    final isClient = _effectiveMode == InteractiveMode.client;
    Tab tabItem(IconData icon, String label) {
      return Tab(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: isCompact ? 16 : 18),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: isCompact ? 12 : 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final tabs = isClient
        ? [
            tabItem(Icons.bookmark_border_rounded, 'من أتابع'),
            tabItem(Icons.thumb_up_alt_outlined, 'مفضلتي'),
          ]
        : [
            tabItem(Icons.bookmark_border_rounded, 'من أتابع'),
            tabItem(Icons.person_add_alt_1_rounded, 'متابعيني'),
            tabItem(Icons.thumb_up_alt_outlined, 'مفضلتي'),
          ];

    final views = isClient
      ? [
          _buildGenericTab(_buildFollowingTab()),
          _buildGenericTab(_buildFavoritesTab()),
        ]
      : [
          _buildGenericTab(_buildFollowingTab()),
          _buildGenericTab(_buildFollowersTab()),
          _buildGenericTab(_buildFavoritesTab()),
        ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        drawer: const CustomDrawer(),
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              SliverAppBar(
                expandedHeight: isTablet ? 210 : (isCompact ? 165 : 185),
                floating: false,
                pinned: true,
                elevation: 0,
                scrolledUnderElevation: 0,
                backgroundColor: AppColors.deepPurple,
                leading: Builder(
                  builder: (context) => IconButton(
                    icon: const Icon(Icons.menu, color: Colors.white),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  ),
                ),
                actions: [
                   const NotificationsIconButton(iconColor: Colors.white),
                   IconButton(
                    icon: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white),
                    onPressed: () => ChatNav.openInbox(context),
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  centerTitle: true,
                  background: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppColors.deepPurple,
                          Color(0xFF8E44AD), // A bit lighter purple
                        ],
                      ),
                    ),
                    child: Stack(
                      children: [
                        // Decorative circles
                        Positioned(
                          top: -50,
                          right: -50,
                          child: Container(
                            width: 200,
                            height: 200,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.05),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 20,
                          left: -30,
                          child: Container(
                            width: 150,
                            height: 150,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.05),
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.center,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(height: isTablet ? 48 : 42),
                              Text(
                                _myDisplayName ?? 'تفاعلي',
                                style: TextStyle(
                                  fontSize: isTablet ? 30 : (isCompact ? 22 : 26),
                                  fontWeight: FontWeight.w900,
                                  fontFamily: 'Cairo',
                                  color: Colors.white,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              const SizedBox(height: 2),
                              if (_myHandle != null)
                                Text(
                                  _myHandle!,
                                  style: TextStyle(
                                    fontSize: isCompact ? 12.5 : 14,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'Cairo',
                                    color: Colors.white.withValues(alpha: 0.9),
                                  ),
                                ),
                              Container(
                                margin: const EdgeInsets.only(top: 6),
                                padding: EdgeInsets.symmetric(
                                  horizontal: isCompact ? 10 : 12,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  'متابعة، مفضلة، وتفاعل في مكان واحد',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    fontFamily: 'Cairo',
                                    fontSize: isCompact ? 11 : 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                bottom: PreferredSize(
                  preferredSize: Size.fromHeight(isCompact ? 56 : 60),
                  child: Container(
                    height: isCompact ? 56 : 60,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        isCompact ? 10 : 16,
                        8,
                        isCompact ? 10 : 16,
                        8,
                      ),
                      child: Container(
                         decoration: BoxDecoration(
                          color: AppColors.primaryLight.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(25),
                        ),
                        child: TabBar(
                          controller: _tabController,
                          indicator: BoxDecoration(
                            borderRadius: BorderRadius.circular(25),
                            color: AppColors.deepPurple,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.deepPurple.withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              )
                            ],
                          ),
                          labelColor: Colors.white,
                          unselectedLabelColor: AppColors.deepPurple,
                          labelStyle: tabLabelStyle,
                          unselectedLabelStyle: tabUnselectedLabelStyle,
                          isScrollable: isCompact,
                          indicatorSize: TabBarIndicatorSize.tab,
                          dividerColor: Colors.transparent,
                          splashFactory: NoSplash.splashFactory,
                          tabs: tabs,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ];
          },
          body: TabBarView(
            controller: _tabController,
            children: views,
          ),
        ),
        bottomNavigationBar: const CustomBottomNav(currentIndex: 2),
      ),
    );
  }

  // Wrapper with background
  Widget _buildGenericTab(Widget child) {
    return Container(
      color: Colors.white, // Main body background
      child: child,
    );
  }

  // --- TAB 1: Following (من أتابع) ---
  Widget _buildFollowingTab() {
    return FutureBuilder<List<ProviderProfile>>(
      future: _followingFuture,
      builder: (context, snapshot) {
        if (!_capabilitiesLoaded || snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = _sortFollowing(snapshot.data ?? const []);
        if (list.isEmpty) {
          return _emptyState(
            icon: Icons.bookmark_border,
            title: _followingError == null ? 'لا تتابع أحداً بعد' : 'تعذر تحميل قائمة المتابعة',
            subtitle: _followingError ??
                'تصفح مقدمي الخدمات وابدأ بمتابعتهم لتظهر تحديثاتهم هنا.',
          );
        }

        return RefreshIndicator(
          onRefresh: _refreshInteractiveData,
          child: ListView.separated(
            padding: EdgeInsets.symmetric(
              horizontal: MediaQuery.sizeOf(context).width >= 700 ? 22 : 14,
              vertical: 18,
            ),
            itemCount: list.length,
            separatorBuilder: (context, _) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              final p = list[index];
              return _buildFollowingCard(context, p);
            },
          ),
        );
      },
    );
  }

  Widget _buildFollowingCard(BuildContext context, ProviderProfile p) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isNarrow = screenWidth < 390;
    final name = (p.displayName ?? '').trim();
    final bio = (p.bio ?? '').trim();

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.08),
            spreadRadius: 2,
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ServiceRequestFormScreen(
                  providerId: p.id.toString(),
                  providerName: name.isEmpty ? null : name,
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: AppColors.primaryLight,
                      backgroundImage: (p.imageUrl ?? '').trim().isNotEmpty
                          ? NetworkImage(p.imageUrl!.trim())
                          : null,
                      child: (p.imageUrl ?? '').trim().isNotEmpty
                          ? null
                          : Icon(
                              p.isVerifiedBlue
                                  ? Icons.verified_rounded
                                  : Icons.person,
                              color: p.isVerifiedBlue
                                  ? Colors.blue
                                  : AppColors.deepPurple,
                              size: 24,
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name.isEmpty ? 'مزود خدمة' : name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.softBlue,
                            ),
                          ),
                          Text(
                            (p.username ?? '').trim().isNotEmpty
                                ? '@${p.username}'
                                : '@${p.id}',
                             style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Action Button
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      children: [
                        InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ServiceRequestFormScreen(
                                  providerId: p.id.toString(),
                                  providerName: name.isEmpty ? null : name,
                                ),
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.deepPurple.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.deepPurple.withValues(alpha: 0.3),
                              ),
                            ),
                            child: const Text(
                              'طلب خدمة',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: AppColors.deepPurple,
                              ),
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: _unfollowingProviderIds.contains(p.id)
                              ? null
                              : () => _unfollowProvider(p),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.red.withValues(alpha: 0.25),
                              ),
                            ),
                            child: _unfollowingProviderIds.contains(p.id)
                                ? const Padding(
                                    padding: EdgeInsets.all(8),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.red,
                                    ),
                                  )
                                : const Icon(
                                    Icons.person_remove_outlined,
                                    size: 18,
                                    color: Colors.red,
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (bio.isNotEmpty) ...[
                  SizedBox(height: isNarrow ? 10 : 12),
                  Text(
                    bio,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 13,
                      height: 1.5,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                const Divider(height: 1, color: Color(0xFFEEEEEE)),
                SizedBox(height: isNarrow ? 10 : 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _miniStat(Icons.thumb_up_alt_rounded, '${p.likesCount} إعجاب'),
                    _miniStat(Icons.groups_rounded, '${p.followersCount} متابع'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniStat(IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: Colors.grey[400]),
        const SizedBox(width: 6),
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF757575),
          ),
        ),
      ],
    );
  }

  // --- TAB 2: Followers (متابعيني) ---
  Widget _buildFollowersTab() {
    return FutureBuilder<List<UserSummary>>(
      future: _followersFuture,
      builder: (context, snapshot) {
        if (!_capabilitiesLoaded || snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = _sortFollowers(snapshot.data ?? const []);
        if (list.isEmpty) {
          return _emptyState(
            icon: Icons.groups_rounded,
            title: _followersError == null ? 'لا يوجد متابعون حالياً' : 'تعذر تحميل قائمة المتابعين',
            subtitle: _followersError,
          );
        }

        return RefreshIndicator(
          onRefresh: _refreshInteractiveData,
          child: ListView.separated(
            padding: EdgeInsets.symmetric(
              horizontal: MediaQuery.sizeOf(context).width >= 700 ? 22 : 14,
              vertical: 18,
            ),
            itemCount: list.length,
            separatorBuilder: (context, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final u = list[index];
              return _buildFollowerItem(u);
            },
          ),
        );
      },
    );
  }

  Widget _buildFollowerItem(UserSummary u) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.05),
            offset: const Offset(0, 4),
            blurRadius: 10,
          )
        ],
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: AppColors.deepPurple.withValues(alpha: 0.1),
          child: const Icon(Icons.person, color: AppColors.deepPurple),
        ),
        title: Text(
          u.displayName,
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
           '@${u.username ?? u.id}', 
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              color: Colors.grey[600],
            ),
        ),
        trailing: Container(
           width: 32,
           height: 32,
           decoration: BoxDecoration(
             color: AppColors.primaryLight.withValues(alpha: 0.5),
             shape: BoxShape.circle,
           ),
           child: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.deepPurple),
        ),
      ),
    );
  }

  // --- TAB 3: Favorites (مفضلتي) ---
  Widget _buildFavoritesTab() {
    return FutureBuilder<List<ProviderPortfolioItem>>(
      future: _favoritesFuture,
      builder: (context, snapshot) {
        if (!_capabilitiesLoaded || snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = _sortFavorites(snapshot.data ?? const []);
        if (list.isEmpty) {
          return _emptyState(
            icon: Icons.thumb_up_alt_outlined,
            title: _favoritesError == null ? 'لا توجد عناصر في مفضلتي بعد' : 'تعذر تحميل المفضلة',
            subtitle: _favoritesError ?? 'أي صور أو فيديوهات تعمل لها لايك ستظهر هنا.',
          );
        }
        _precacheFavoritePreviews(list);

        return RefreshIndicator(
          onRefresh: _refreshInteractiveData,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final crossAxisCount = width >= 980 ? 4 : (width >= 700 ? 3 : 2);
              final spacing = width >= 700 ? 14.0 : 12.0;
              // Slightly taller cards on phones to avoid text overflow.
              final ratio = width < 360 ? 0.68 : (width >= 700 ? 0.92 : 0.72);
              return GridView.builder(
                padding: EdgeInsets.fromLTRB(
                  width >= 700 ? 20 : 14,
                  18,
                  width >= 700 ? 20 : 14,
                  20,
                ),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: spacing,
                  mainAxisSpacing: spacing,
                  childAspectRatio: ratio,
                ),
                itemCount: list.length,
                itemBuilder: (context, index) {
                  final item = list[index];
                  return _buildFavoriteMediaCard(context, item);
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildFavoriteMediaCard(BuildContext context, ProviderPortfolioItem item) {
    final isVideo = item.fileType.toLowerCase() == 'video';
    final mediaUrl = item.fileUrl.trim();
    final rawPreviewUrl = isVideo ? ((item.thumbnailUrl ?? '').trim()) : mediaUrl;
    final previewUrl = _favoritePreviewUrl(rawPreviewUrl, item.id);
    final providerDisplayName = item.providerDisplayName.trim();
    final providerTag = ((item.providerUsername ?? '').trim().isNotEmpty)
        ? '@${item.providerUsername!.trim()}'
        : '@${item.providerId}';
    final providerTitle = providerDisplayName.isNotEmpty ? providerDisplayName : providerTag;
    final rawCaption = item.caption.trim();
    final hasCaption = rawCaption.isNotEmpty;
    final caption = hasCaption ? rawCaption : 'بدون وصف';
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          )
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (mediaUrl.isEmpty) return;
          if (isVideo) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => NetworkVideoPlayerScreen(
                  url: mediaUrl,
                  title: item.providerDisplayName,
                ),
              ),
            );
            return;
          }
          showDialog<void>(
            context: context,
            builder: (context) {
              return Dialog(
                insetPadding: const EdgeInsets.all(12),
                backgroundColor: Colors.transparent, // Clean look
                elevation: 0,
                child: InteractiveViewer(
                  child: ClipRRect(
                     borderRadius: BorderRadius.circular(12),
                     child: CachedNetworkImage(
                      imageUrl: mediaUrl,
                      fit: BoxFit.contain,
                      fadeInDuration: const Duration(milliseconds: 220),
                      placeholder: (context, url) => _favoriteMediaPlaceholder(),
                      errorWidget: (context, url, error) => Container(
                        color: AppColors.primaryLight,
                        alignment: Alignment.center,
                        child: const Icon(Icons.broken_image, color: Colors.grey, size: 36),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
        child: LayoutBuilder(
          builder: (context, card) {
            final isNarrowCard = card.maxWidth < 180;
            final captionLines = isNarrowCard ? 2 : 3;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 5,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (!isVideo && mediaUrl.isEmpty)
                        Container(
                          color: AppColors.primaryLight,
                          alignment: Alignment.center,
                          child: const Icon(Icons.image_not_supported, color: Colors.grey),
                        )
                      else if (isVideo && previewUrl.isEmpty)
                        _favoriteVideoPlaceholder()
                      else
                        CachedNetworkImage(
                          imageUrl: previewUrl,
                          cacheKey: 'fav-${item.id}-${_favoriteRetryNonceFor(item.id)}-$previewUrl',
                          fit: BoxFit.cover,
                          fadeInDuration: const Duration(milliseconds: 220),
                          fadeOutDuration: const Duration(milliseconds: 120),
                          placeholder: (context, url) => _favoriteMediaPlaceholder(),
                          errorWidget: (context, url, error) => Container(
                            color: AppColors.primaryLight,
                            child: isVideo
                                ? _favoriteVideoPlaceholder(
                                    onRetry: () => _retryFavoriteMedia(item.id),
                                  )
                                : _favoriteMediaPlaceholder(
                                    isError: true,
                                    onRetry: () => _retryFavoriteMedia(item.id),
                                  ),
                          ),
                        ),
                      if (isVideo)
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
                          ),
                        ),
                      PositionedDirectional(
                        top: 8,
                        start: 8,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: _unfavoritingItemIds.contains(item.id)
                                ? null
                                : () => _removeFavoriteMedia(item),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.45),
                                shape: BoxShape.circle,
                              ),
                              child: _unfavoritingItemIds.contains(item.id)
                                  ? const Padding(
                                      padding: EdgeInsets.all(8),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.favorite,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Text(
                          providerTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: isNarrowCard ? 11 : 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.deepPurple.shade300,
                          ),
                        ),
                        if (providerDisplayName.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            providerTag,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: isNarrowCard ? 10 : 10.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                        const SizedBox(height: 3),
                        Expanded(
                          child: Align(
                            alignment: Alignment.topRight,
                            child: Text(
                              caption,
                              maxLines: captionLines,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: isNarrowCard ? 11 : 11.5,
                                fontWeight: hasCaption ? FontWeight.w700 : FontWeight.w600,
                                height: 1.25,
                                color: hasCaption ? null : Colors.grey.shade500,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _favoriteMediaPlaceholder({bool isError = false, VoidCallback? onRetry}) {
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, _) {
        final t = _shimmerController.value;
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-1.8 + (t * 2.6), -0.2),
              end: Alignment(-0.8 + (t * 2.6), 0.2),
              colors: const [
                Color(0xFFEDEBFA),
                Color(0xFFF8F7FF),
                Color(0xFFE8E5F7),
              ],
              stops: const [0.15, 0.5, 0.85],
            ),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isError ? Icons.broken_image_outlined : Icons.image_outlined,
                  color: Colors.grey.shade500,
                  size: 28,
                ),
                if (isError && onRetry != null) ...[
                  const SizedBox(height: 8),
                  InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: onRetry,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.grey.withValues(alpha: 0.25)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.refresh_rounded, size: 14, color: AppColors.deepPurple),
                          SizedBox(width: 4),
                          Text(
                            'إعادة المحاولة',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.deepPurple,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _favoriteVideoPlaceholder({VoidCallback? onRetry}) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primaryLight.withValues(alpha: 0.9),
            Colors.deepPurple.shade50,
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 30),
            ),
            const SizedBox(height: 8),
            Text(
              'فيديو',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: Colors.grey.shade700,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 8),
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: onRetry,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.25)),
                  ),
                  child: const Text(
                    'إعادة المحاولة',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.deepPurple,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    String? subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.primaryLight.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 48, color: AppColors.deepPurple.withValues(alpha: 0.5)),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.softBlue,
              ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  color: Colors.grey[600],
                  fontSize: 14,
                  height: 1.5
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
             SizedBox(
               width: 150,
               child: ElevatedButton(
                onPressed: _reload,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.deepPurple,
                  elevation: 0,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('تحديث', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
              ),
             ),
          ],
        ),
      ),
    );
  }
}
