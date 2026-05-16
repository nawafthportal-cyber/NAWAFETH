import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../constants/app_theme.dart';
import '../utils/responsive.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/custom_drawer.dart';
import 'provider_profile_screen.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/account_mode_service.dart';
import '../services/interactive_service.dart';
import '../models/provider_public_model.dart';
import '../models/user_public_model.dart';
import '../models/media_item_model.dart';
import '../widgets/login_required_prompt.dart';
import '../widgets/provider_name_with_badges.dart';
import '../widgets/spotlight_viewer.dart';

enum InteractiveInitialTab {
  following,
  followers,
  favorites,
}

class InteractiveScreen extends StatefulWidget {
  const InteractiveScreen({
    super.key,
    this.initialTab = InteractiveInitialTab.following,
  });

  final InteractiveInitialTab initialTab;

  @override
  State<InteractiveScreen> createState() => _InteractiveScreenState();
}

class _InteractiveScreenState extends State<InteractiveScreen>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;
  int _loadEpoch = 0;
  final TextEditingController _followingSearchController =
      TextEditingController();
  final TextEditingController _followersSearchController =
      TextEditingController();
  final TextEditingController _favoritesSearchController =
      TextEditingController();

  bool _isProviderMode = false;
  bool _isLoggedIn = false;
  bool _authChecked = false;
  bool _followingCompact = false;

  List<ProviderPublicModel> _following = [];
  List<UserPublicModel> _followers = [];
  List<MediaItemModel> _favorites = [];

  bool _followingLoading = true;
  bool _followersLoading = true;
  bool _favoritesLoading = true;

  String? _followingError;
  String? _followersError;
  String? _favoritesError;
  String? _followingStatus;
  String? _followersStatus;
  String? _favoritesStatus;
  bool _followingOfflineFallback = false;
  bool _followersOfflineFallback = false;
  bool _favoritesOfflineFallback = false;

  @override
  void initState() {
    super.initState();
    AccountModeService.addListener(_handleAccountModeChanged);
    _followingSearchController.addListener(_onFilterChanged);
    _followersSearchController.addListener(_onFilterChanged);
    _favoritesSearchController.addListener(_onFilterChanged);
    _loadAllData(forceRefresh: true);
  }

  void _handleAccountModeChanged(bool _) {
    _loadAllData(forceRefresh: true);
  }

  Future<void> _loadAllData({bool forceRefresh = false}) async {
    final requestEpoch = ++_loadEpoch;
    final loggedIn = await AuthService.isLoggedIn();
    if (!mounted || requestEpoch != _loadEpoch) return;
    setState(() {
      _isLoggedIn = loggedIn;
      _authChecked = true;
    });
    if (!loggedIn) return;

    final isProviderMode = await AccountModeService.isProviderMode();
    if (!mounted || requestEpoch != _loadEpoch) return;

    if (mounted) {
      setState(() {
        _isProviderMode = isProviderMode;
        _following = [];
        _followers = [];
        _favorites = [];
        _followingLoading = true;
        _followersLoading = isProviderMode;
        _favoritesLoading = true;
        _followingError = null;
        _followersError = null;
        _favoritesError = null;
        _followingStatus = null;
        _followersStatus = null;
        _favoritesStatus = null;
        _followingOfflineFallback = false;
        _followersOfflineFallback = false;
        _favoritesOfflineFallback = false;
      });
      _initTabController();
    }

    await Future.wait([
      _loadFollowing(forceRefresh: forceRefresh, requestEpoch: requestEpoch),
      if (_isProviderMode)
        _loadFollowers(forceRefresh: forceRefresh, requestEpoch: requestEpoch),
      _loadFavorites(forceRefresh: forceRefresh, requestEpoch: requestEpoch),
    ]);

    if (!_isProviderMode && mounted && requestEpoch == _loadEpoch) {
      setState(() {
        _followersLoading = false;
        _followers = [];
        _followersStatus = null;
        _followersOfflineFallback = false;
      });
    }
  }

  void _initTabController() {
    final previousIndex = _tabController?.index;
    _tabController?.dispose();
    final tabCount = _isProviderMode ? 3 : 2;
    final initialIndex = previousIndex != null && previousIndex < tabCount
        ? previousIndex
        : _initialTabIndex();
    _tabController = TabController(
      length: tabCount,
      vsync: this,
      initialIndex: initialIndex,
    );
  }

  int _initialTabIndex() {
    switch (widget.initialTab) {
      case InteractiveInitialTab.followers:
        return _isProviderMode ? 1 : 0;
      case InteractiveInitialTab.favorites:
        return _isProviderMode ? 2 : 1;
      case InteractiveInitialTab.following:
        return 0;
    }
  }

  Future<void> _loadFollowing({
    bool forceRefresh = false,
    int? requestEpoch,
  }) async {
    if (!mounted) return;
    setState(() {
      _followingLoading = true;
      _followingError = null;
    });
    final result = await InteractiveService.fetchFollowingResult(
      forceRefresh: forceRefresh,
    );
    if (!mounted || (requestEpoch != null && requestEpoch != _loadEpoch)) {
      return;
    }
    setState(() {
      _followingLoading = false;
      _following = result.data;
      _followingStatus = _cacheStatusMessage(result);
      _followingOfflineFallback = result.isOfflineFallback;
      _followingError =
          result.data.isEmpty && result.hasError ? result.errorMessage : null;
    });
  }

  Future<void> _loadFollowers({
    bool forceRefresh = false,
    int? requestEpoch,
  }) async {
    if (!mounted) return;
    setState(() {
      _followersLoading = true;
      _followersError = null;
    });
    if (!_isProviderMode) {
      if (mounted) {
        setState(() {
          _followersLoading = false;
          _followers = [];
        });
      }
      return;
    }
    final result = await InteractiveService.fetchFollowersResult(
      forceRefresh: forceRefresh,
    );
    if (!mounted || (requestEpoch != null && requestEpoch != _loadEpoch)) {
      return;
    }
    setState(() {
      _followersLoading = false;
      _followers = result.data;
      _followersStatus = _cacheStatusMessage(result);
      _followersOfflineFallback = result.isOfflineFallback;
      _followersError =
          result.data.isEmpty && result.hasError ? result.errorMessage : null;
    });
  }

  Future<void> _loadFavorites({
    bool forceRefresh = false,
    int? requestEpoch,
  }) async {
    if (!mounted) return;
    setState(() {
      _favoritesLoading = true;
      _favoritesError = null;
    });
    final result = await InteractiveService.fetchFavoritesResult(
      forceRefresh: forceRefresh,
    );
    if (!mounted || (requestEpoch != null && requestEpoch != _loadEpoch)) {
      return;
    }
    setState(() {
      _favoritesLoading = false;
      _favorites = result.data;
      _favoritesStatus = _cacheStatusMessage(result);
      _favoritesOfflineFallback = result.isOfflineFallback;
      _favoritesError =
          result.data.isEmpty && result.hasError ? result.errorMessage : null;
    });
  }

  String? _cacheStatusMessage(CachedListResult<dynamic> result) {
    if (result.isOfflineFallback) {
      return 'تُعرض بيانات محفوظة مؤقتًا بسبب ضعف الاتصال.';
    }
    if (result.fromCache) {
      return 'تم تحميل البيانات من الكاش المحلي لتسريع التصفح.';
    }
    return null;
  }

  void _onFilterChanged() {
    if (!mounted) return;
    setState(() {});
  }

  String _normalizeSearch(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  bool _matchesQuery(String query, List<String?> values) {
    if (query.isEmpty) return true;
    final haystack = _normalizeSearch(
      values
          .whereType<String>()
          .where((value) => value.trim().isNotEmpty)
          .join(' '),
    );
    return haystack.contains(query);
  }

  List<ProviderPublicModel> get _filteredFollowing {
    final query = _normalizeSearch(_followingSearchController.text);
    return _following.where((provider) {
      return _matchesQuery(query, [
        provider.displayName,
        provider.username,
        provider.locationDisplay,
        provider.primaryCategoryName,
        provider.primarySubcategoryName,
        provider.providerTypeLabel,
      ]);
    }).toList(growable: false);
  }

  List<UserPublicModel> get _filteredFollowers {
    final query = _normalizeSearch(_followersSearchController.text);
    return _followers.where((user) {
      return _matchesQuery(query, [
        user.displayName,
        user.username,
        user.usernameDisplay,
        user.followerBadgeLabel,
      ]);
    }).toList(growable: false);
  }

  List<MediaItemModel> get _filteredFavorites {
    final query = _normalizeSearch(_favoritesSearchController.text);
    return _favorites.where((item) {
      return _matchesQuery(query, [
        item.providerDisplayName,
        item.providerUsername,
        item.caption,
        item.sectionTitle,
        item.source.name,
      ]);
    }).toList(growable: false);
  }

  String _counterLabel(int visible, int total) => '$visible / $total';

  @override
  void dispose() {
    AccountModeService.removeListener(_handleAccountModeChanged);
    _tabController?.dispose();
    _followingSearchController.removeListener(_onFilterChanged);
    _followersSearchController.removeListener(_onFilterChanged);
    _favoritesSearchController.removeListener(_onFilterChanged);
    _followingSearchController.dispose();
    _followersSearchController.dispose();
    _favoritesSearchController.dispose();
    super.dispose();
  }

  // =============================================
  //  BUILD
  // =============================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const purple = Colors.deepPurple;

    // Still checking auth
    if (!_authChecked) {
      return _shell(isDark, purple,
          body: const Center(
              child: CircularProgressIndicator(color: Colors.deepPurple)));
    }

    // Not logged in — show login prompt
    if (!_isLoggedIn) {
      return _shell(isDark, purple, body: _loginRequiredState());
    }

    if (_tabController == null) {
      return _shell(isDark, purple,
          body: const Center(
              child: CircularProgressIndicator(color: Colors.deepPurple)));
    }

    return _shell(
      isDark,
      purple,
      body: Column(
        children: [
          _buildHeaderSummary(isDark, purple),
          _buildTabsOverviewCard(),
          _buildTabBar(isDark, purple),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: _isProviderMode
                  ? [
                      _buildFollowingTab(isDark, purple),
                      _buildFollowersTab(isDark, purple),
                      _buildFavoritesTab(isDark, purple)
                    ]
                  : [
                      _buildFollowingTab(isDark, purple),
                      _buildFavoritesTab(isDark, purple)
                    ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderSummary(bool isDark, Color purple) {
    final hasFollowersTab = _isProviderMode;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            colors: [
              Color(0xFF0E0224),
              Color(0xFF2A1169),
              Color(0xFF0B3331),
            ],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x302A1169),
              blurRadius: 30,
              offset: Offset(0, 18),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF59E0B),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'لوحة تفاعلك',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFFEF3C7),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'شبكتك التفاعلية',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 28,
                height: 1.16,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'تابع من ترتبط بهم، راجع من يتابعك، وارجع إلى العناصر المحفوظة بسرعة.',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                height: 1.7,
                fontWeight: FontWeight.w700,
                color: Color(0xD9FFFFFF),
              ),
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 420;
                final items = <Widget>[
                  Expanded(
                    child: _summaryChip(
                      value: _following.length,
                      label: 'من أتابع',
                      isDark: true,
                      accent: purple,
                    ),
                  ),
                  if (hasFollowersTab)
                    Expanded(
                      child: _summaryChip(
                        value: _followers.length,
                        label: 'متابعيني',
                        isDark: true,
                        accent: const Color(0xFF14958A),
                      ),
                    ),
                  Expanded(
                    child: _summaryChip(
                      value: _favorites.length,
                      label: 'مفضلتي',
                      isDark: true,
                      accent: const Color(0xFFF59E0B),
                      warm: true,
                    ),
                  ),
                ];
                if (narrow && items.length == 3) {
                  return Column(
                    children: [
                      Row(children: [
                        items[0],
                        const SizedBox(width: 8),
                        items[1]
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [items[2]]),
                    ],
                  );
                }
                return Row(
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      items[i],
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryChip({
    required int value,
    required String label,
    required bool isDark,
    required Color accent,
    bool warm = false,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 66),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$value',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: Colors.white.withValues(alpha: 0.72),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabsOverviewCard() {
    return const SizedBox.shrink();
  }

  Widget _shell(bool isDark, Color purple, {required Widget body}) {
    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF121212) : const Color(0xFFEDF0F7),
      drawer: const CustomDrawer(),
      bottomNavigationBar: const CustomBottomNav(currentIndex: -1),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: ResponsiveLayout.contentMaxWidth(context),
            ),
            child: body,
          ),
        ),
      ),
    );
  }

  // -- TAB BAR --
  Widget _buildTabBar(bool isDark, Color purple) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : const Color(0x120F172A),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: TabBar(
        controller: _tabController,
        indicator: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0E0224), Color(0xFF673AB7), Color(0xFF062924)],
            begin: Alignment.centerRight,
            end: Alignment.centerLeft,
          ),
          borderRadius: BorderRadius.all(Radius.circular(16)),
          boxShadow: [
            BoxShadow(
              color: Color(0x4D673AB7),
              blurRadius: 18,
              offset: Offset(0, 6),
            ),
          ],
        ),
        indicatorPadding:
            const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor: isDark ? Colors.white70 : const Color(0xFF475569),
        labelStyle: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 12.5,
          fontWeight: FontWeight.w900,
        ),
        unselectedLabelStyle: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
        tabs: _isProviderMode
            ? [
                _tabItem(
                  Icons.people_outline_rounded,
                  'من أتابع',
                  _following.length,
                ),
                _tabItem(
                  Icons.person_outline_rounded,
                  'متابعيني',
                  _followers.length,
                ),
                _tabItem(
                  Icons.bookmark_outline_rounded,
                  'مفضلتي',
                  _favorites.length,
                ),
              ]
            : [
                _tabItem(
                  Icons.people_outline_rounded,
                  'من أتابع',
                  _following.length,
                ),
                _tabItem(
                  Icons.bookmark_outline_rounded,
                  'مفضلتي',
                  _favorites.length,
                ),
              ],
      ),
    );
  }

  Widget _tabItem(IconData icon, String label, int count) {
    final badgeLabel = count > 999 ? '999+' : '$count';
    return Tab(
      height: 48,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.deepPurple.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 14),
          ),
          const SizedBox(width: 5),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          if (count > 0) ...[
            const SizedBox(width: 5),
            Container(
              constraints: const BoxConstraints(minWidth: 20),
              height: 18,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.deepPurple.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(
                  color: Colors.deepPurple.withValues(alpha: 0.18),
                ),
              ),
              child: Text(
                badgeLabel,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // =============================================
  //  SHARED WIDGETS
  // =============================================

  Widget _loadingState() {
    return const Center(
        child: Padding(
            padding: EdgeInsets.all(40),
            child: CircularProgressIndicator(color: Colors.deepPurple)));
  }

  Widget _errorState(String message, VoidCallback onRetry, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded,
                size: 44, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.black45)),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 15, color: Colors.white),
              label: const Text('إعادة المحاولة',
                  style: TextStyle(
                      fontFamily: 'Cairo', fontSize: 11, color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(IconData icon, String message, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.deepPurple.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: Colors.grey.shade400),
            ),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }

  Widget _emptyFilterState({
    required bool isDark,
    required String message,
  }) {
    return _emptyState(Icons.search_off_rounded, message, isDark);
  }

  Widget _buildFilterToolbar({
    required bool isDark,
    required Color accent,
    required TextEditingController controller,
    required String hintText,
    required int visibleCount,
    required int totalCount,
    required String title,
    required String subtitle,
    bool showDensityToggle = false,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showDensityInline =
              showDensityToggle && constraints.maxWidth > 480;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  height: 1.6,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : accent.withValues(alpha: 0.14),
                        ),
                      ),
                      child: TextField(
                        controller: controller,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        decoration: InputDecoration(
                          hintText: hintText,
                          hintStyle: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color:
                                isDark ? Colors.white38 : Colors.grey.shade500,
                          ),
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            size: 18,
                            color: accent,
                          ),
                          suffixIcon: controller.text.isEmpty
                              ? null
                              : IconButton(
                                  onPressed: controller.clear,
                                  icon: Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                    color: isDark
                                        ? Colors.white54
                                        : Colors.grey.shade500,
                                  ),
                                ),
                          border: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 12),
                        ),
                      ),
                    ),
                  ),
                  if (showDensityInline) ...[
                    const SizedBox(width: 8),
                    _buildDensityToggle(isDark, accent),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : accent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _counterLabel(visibleCount, totalCount),
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        color: isDark ? Colors.white70 : accent,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDensityToggle(bool isDark, Color accent) {
    Widget toggleButton({
      required IconData icon,
      required bool selected,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: selected
                  ? accent
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.transparent),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 18,
              color: selected
                  ? Colors.white
                  : (isDark ? Colors.white70 : Colors.grey.shade700),
            ),
          ),
        ),
      );
    }

    return Container(
      width: 94,
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : accent.withValues(alpha: 0.14),
        ),
      ),
      child: Row(
        children: [
          toggleButton(
            icon: Icons.grid_view_rounded,
            selected: !_followingCompact,
            onTap: () {
              if (!_followingCompact) return;
              setState(() => _followingCompact = false);
            },
          ),
          const SizedBox(width: 4),
          toggleButton(
            icon: Icons.grid_view_outlined,
            selected: _followingCompact,
            onTap: () {
              if (_followingCompact) return;
              setState(() => _followingCompact = true);
            },
          ),
        ],
      ),
    );
  }

  Widget _loginRequiredState() {
    return LoginRequiredPrompt(
      title: 'تسجيل الدخول مطلوب',
      message: 'للوصول إلى المتابعة والمتابعين والمفضلة، سجّل دخولك أولاً.',
      onLoginTap: () => Navigator.pushNamed(context, '/login'),
    );
  }

  // =============================================
  //  TAB: FOLLOWING
  // =============================================

  Widget _buildFollowingTab(bool isDark, Color purple) {
    if (_followingLoading) {
      return _loadingState();
    }
    if (_followingError != null) {
      return _errorState(_followingError!, _loadFollowing, isDark);
    }
    if (_following.isEmpty) {
      return _emptyState(
          Icons.group_off_rounded, 'لا تتابع أي مزود خدمة حتى الآن', isDark);
    }

    final filtered = _filteredFollowing;

    return Column(
      children: [
        if (_followingStatus != null)
          _buildCacheBanner(
            message: _followingStatus!,
            isDark: isDark,
            accent: purple,
            isOffline: _followingOfflineFallback,
            onRefresh: () => _loadFollowing(forceRefresh: true),
          ),
        _buildFilterToolbar(
          isDark: isDark,
          accent: purple,
          controller: _followingSearchController,
          hintText: 'ابحث بالاسم أو المدينة…',
          visibleCount: filtered.length,
          totalCount: _following.length,
          title: 'من أتابع',
          subtitle: 'مزودو الخدمة والأشخاص الذين تتابع نشاطهم.',
          showDensityToggle: true,
        ),
        Expanded(
          child: filtered.isEmpty
              ? _emptyFilterState(
                  isDark: isDark,
                  message: 'لا توجد نتائج تطابق هذا البحث في قائمة من تتابعهم.',
                )
              : RefreshIndicator(
                  onRefresh: () => _loadFollowing(forceRefresh: true),
                  color: purple,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = _followingCompact;
                      final crossAxisCount = compact
                          ? (constraints.maxWidth < 360 ? 2 : 3)
                          : (constraints.maxWidth < 360 ? 1 : 2);
                      final aspectRatio = compact
                          ? (constraints.maxWidth < 360 ? 0.92 : 0.88)
                          : (constraints.maxWidth < 360 ? 1.5 : 0.72);
                      return GridView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(12),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: aspectRatio,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) =>
                            _followingCard(filtered[index], isDark, purple),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _followingCard(
      ProviderPublicModel provider, bool isDark, Color purple) {
    final profileUrl = ApiClient.buildMediaUrl(provider.profileImage);
    final username = provider.username?.trim().isNotEmpty == true
        ? '@${provider.username!.trim()}'
        : '';
    final providerTypeLabel =
        (provider.providerTypeLabel ?? '').trim().isNotEmpty
            ? provider.providerTypeLabel!.trim()
            : 'مزود خدمة';
    final cityText = provider.locationDisplay.trim().isNotEmpty
        ? provider.locationDisplay.trim()
        : 'المدينة غير محددة';
    final categoryText = (provider.primaryCategoryName ?? '').trim();
    final subcategoryText = (provider.primarySubcategoryName ?? '').trim();
    final subtitleParts = <String>[
      if (categoryText.isNotEmpty) categoryText,
      if (subcategoryText.isNotEmpty) subcategoryText else cityText,
    ];
    final subtitleText =
        subtitleParts.isNotEmpty ? subtitleParts.join(' • ') : cityText;
    final ratingText =
        provider.ratingAvg > 0 ? provider.ratingAvg.toStringAsFixed(1) : '0.0';

    return GestureDetector(
      onTap: () => _navigateToProvider(provider),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : purple.withValues(alpha: 0.10),
          ),
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
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: purple,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(18),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: purple.withValues(alpha: 0.1),
                            backgroundImage: profileUrl != null
                                ? CachedNetworkImageProvider(profileUrl)
                                : null,
                            child: profileUrl == null
                                ? Text(
                                    provider.displayName.isNotEmpty
                                        ? provider.displayName[0]
                                        : '؟',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: purple,
                                    ),
                                  )
                                : null,
                          ),
                          if (provider.hasExcellenceBadges)
                            Positioned(
                              top: -8,
                              left: -6,
                              child: Container(
                                constraints: const BoxConstraints(maxWidth: 88),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black87,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  provider.excellenceBadges.first.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    height: 1.1,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: purple.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                providerTypeLabel,
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w900,
                                  color: isDark ? Colors.white : purple,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            ProviderNameWithBadges(
                              name: provider.displayName,
                              isVerifiedBlue: provider.isVerifiedBlue,
                              isVerifiedGreen: provider.isVerifiedGreen,
                              badgeIconSize: 12,
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (username.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                username,
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? Colors.deepPurple.shade100
                                      : Colors.deepPurple.shade500,
                                ),
                              ),
                            ],
                            const SizedBox(height: 4),
                            Text(
                              subtitleText,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                height: 1.5,
                                color: isDark ? Colors.white60 : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _interactiveMetaPill(
                        label: cityText,
                        icon: Icons.location_on_outlined,
                        isDark: isDark,
                        color: purple,
                      ),
                      _interactiveMetaPill(
                        label: ratingText,
                        icon: Icons.star_outline_rounded,
                        isDark: isDark,
                        color: purple,
                      ),
                      _interactiveMetaPill(
                        label: '${provider.followersCount} متابع',
                        icon: Icons.people_outline_rounded,
                        isDark: isDark,
                        color: purple,
                      ),
                      if (provider.completedRequests > 0)
                        _interactiveMetaPill(
                          label: '${provider.completedRequests} مكتمل',
                          isDark: isDark,
                          color: purple,
                          soft: true,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.06),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'عرض الملف',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _interactiveMetaPill({
    required String label,
    required bool isDark,
    required Color color,
    IconData? icon,
    bool soft = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : (soft
                ? color.withValues(alpha: 0.05)
                : color.withValues(alpha: 0.08)),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : color.withValues(alpha: soft ? 0.08 : 0.10),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 12,
              color: isDark ? Colors.white70 : color,
            ),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 9.8,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white70 : (soft ? Colors.black54 : color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _followerFooter({
    required bool isDark,
    required bool isProviderFollower,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              isProviderFollower ? 'فتح الملف' : 'متابع للملف',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
          ),
          Icon(
            Icons.arrow_forward_ios_rounded,
            size: 14,
            color: isDark ? Colors.white54 : Colors.black45,
          ),
        ],
      ),
    );
  }

  void _navigateToFollower(UserPublicModel user) {
    if (!user.hasProviderProfile || user.providerId == null) {
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProviderProfileScreen(
          providerId: user.providerId.toString(),
          providerName: user.displayName,
          providerImage: ApiClient.buildMediaUrl(user.profileImage),
        ),
      ),
    );
  }

  Widget _followerTile(UserPublicModel user, bool isDark, Color purple) {
    final profileUrl = ApiClient.buildMediaUrl(user.profileImage);
    final roleLabel = user.followerBadgeLabel.trim().isNotEmpty
        ? user.followerBadgeLabel.trim()
        : (user.hasProviderProfile ? 'مزود خدمة' : 'مستخدم');
    final canOpenProfile = user.hasProviderProfile && user.providerId != null;
    final accentColor = canOpenProfile ? purple : Colors.grey.shade500;

    return GestureDetector(
      onTap: canOpenProfile ? () => _navigateToFollower(user) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : accentColor.withValues(alpha: canOpenProfile ? 0.10 : 0.08),
          ),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(18),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: accentColor.withValues(alpha: 0.1),
                    backgroundImage: profileUrl != null
                        ? CachedNetworkImageProvider(profileUrl)
                        : null,
                    child: profileUrl == null
                        ? Text(
                            user.displayName.isNotEmpty
                                ? user.displayName[0]
                                : '؟',
                            style: TextStyle(
                              color: accentColor,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            roleLabel,
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 9.5,
                              fontWeight: FontWeight.w900,
                              color: isDark ? Colors.white : accentColor,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          user.displayName,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w900,
                            fontFamily: 'Cairo',
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user.usernameDisplay,
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white70 : accentColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (canOpenProfile)
              _followerFooter(
                isDark: isDark,
                isProviderFollower: true,
              ),
          ],
        ),
      ),
    );
  }

  void _navigateToProvider(ProviderPublicModel p) {
    Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProviderProfileScreen(
            providerId: p.id.toString(),
            providerName: p.displayName,
            providerRating: p.ratingAvg,
            providerOperations: p.completedRequests,
            providerImage: ApiClient.buildMediaUrl(p.profileImage),
            providerVerifiedBlue: p.isVerifiedBlue,
            providerVerifiedGreen: p.isVerifiedGreen,
            providerPhone: p.phone,
            providerLat: p.lat,
            providerLng: p.lng,
          ),
        ));
  }

  // =============================================
  //  TAB: FOLLOWERS
  // =============================================

  Widget _buildFollowersTab(bool isDark, Color purple) {
    if (_followersLoading) {
      return _loadingState();
    }
    if (_followersError != null) {
      return _errorState(_followersError!, _loadFollowers, isDark);
    }
    if (_followers.isEmpty) {
      return _emptyState(
          Icons.person_off_rounded, 'لا يوجد متابعون بعد', isDark);
    }

    final filtered = _filteredFollowers;

    return Column(
      children: [
        if (_followersStatus != null)
          _buildCacheBanner(
            message: _followersStatus!,
            isDark: isDark,
            accent: purple,
            isOffline: _followersOfflineFallback,
            onRefresh: () => _loadFollowers(forceRefresh: true),
          ),
        _buildFilterToolbar(
          isDark: isDark,
          accent: purple,
          controller: _followersSearchController,
          hintText: 'ابحث بالاسم…',
          visibleCount: filtered.length,
          totalCount: _followers.length,
          title: 'متابعيني',
          subtitle: 'العملاء والأشخاص الذين يتابعون ملفك.',
        ),
        Expanded(
          child: filtered.isEmpty
              ? _emptyFilterState(
                  isDark: isDark,
                  message: 'لا توجد نتائج مطابقة داخل قائمة المتابعين.',
                )
              : RefreshIndicator(
                  onRefresh: () => _loadFollowers(forceRefresh: true),
                  color: purple,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(12),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) =>
                        _followerTile(filtered[index], isDark, purple),
                  ),
                ),
        ),
      ],
    );
  }

  // =============================================
  //  TAB: FAVORITES
  // =============================================

  Widget _buildFavoritesTab(bool isDark, Color purple) {
    if (_favoritesLoading) {
      return _loadingState();
    }
    if (_favoritesError != null) {
      return _errorState(_favoritesError!, _loadFavorites, isDark);
    }
    if (_favorites.isEmpty) {
      return _emptyState(Icons.bookmark_outline_rounded,
          'لا توجد عناصر محفوظة في المفضلة', isDark);
    }

    final filtered = _filteredFavorites;
    final spotlightItems = filtered
        .where((item) => item.source == MediaItemSource.spotlight)
        .toList(growable: false);
    final otherItems = filtered
        .where((item) => item.source != MediaItemSource.spotlight)
        .toList(growable: false);

    return Column(
      children: [
        if (_favoritesStatus != null)
          _buildCacheBanner(
            message: _favoritesStatus!,
            isDark: isDark,
            accent: purple,
            isOffline: _favoritesOfflineFallback,
            onRefresh: () => _loadFavorites(forceRefresh: true),
          ),
        _buildFilterToolbar(
          isDark: isDark,
          accent: purple,
          controller: _favoritesSearchController,
          hintText: 'ابحث في المفضلة…',
          visibleCount: filtered.length,
          totalCount: _favorites.length,
          title: 'مفضلتي',
          subtitle: 'الريلز والوسائط التي احتفظت بها للرجوع إليها بسرعة.',
        ),
        Expanded(
          child: filtered.isEmpty
              ? _emptyFilterState(
                  isDark: isDark,
                  message: 'لا توجد عناصر محفوظة تطابق هذا البحث.',
                )
              : RefreshIndicator(
                  onRefresh: () => _loadFavorites(forceRefresh: true),
                  color: purple,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      if (spotlightItems.isNotEmpty) ...[
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                            child: _favoritesSectionHeader(
                              title: 'الريلز المحفوظة',
                              subtitle:
                                  'وصول سريع إلى الأضواء التي احتفظت بها.',
                              isDark: isDark,
                              accent: purple,
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: SizedBox(
                            height: 132,
                            child: ListView.separated(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              itemCount: spotlightItems.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 10),
                              itemBuilder: (context, index) {
                                final item = spotlightItems[index];
                                final originalIndex = _favorites.indexOf(item);
                                return _favoriteReel(
                                  item,
                                  originalIndex >= 0 ? originalIndex : index,
                                  isDark,
                                  purple,
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                      if (otherItems.isNotEmpty) ...[
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              12,
                              spotlightItems.isNotEmpty ? 16 : 12,
                              12,
                              8,
                            ),
                            child: _favoritesSectionHeader(
                              title: spotlightItems.isNotEmpty
                                  ? 'الوسائط المحفوظة'
                                  : 'مفضلتي',
                              subtitle:
                                  'الصور ومقاطع الفيديو المحفوظة للرجوع إليها لاحقًا.',
                              isDark: isDark,
                              accent: purple,
                            ),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          sliver: SliverLayoutBuilder(
                            builder: (context, constraints) {
                              final crossAxisCount =
                                  constraints.crossAxisExtent < 360 ? 1 : 2;
                              return SliverGrid(
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  mainAxisSpacing: 10,
                                  crossAxisSpacing: 10,
                                  childAspectRatio:
                                      constraints.crossAxisExtent < 360
                                          ? 1.25
                                          : 0.85,
                                ),
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) {
                                    final item = otherItems[index];
                                    final originalIndex =
                                        _favorites.indexOf(item);
                                    return _favoriteCard(
                                      item,
                                      originalIndex >= 0
                                          ? originalIndex
                                          : index,
                                      isDark,
                                      purple,
                                    );
                                  },
                                  childCount: otherItems.length,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _favoritesSectionHeader({
    required String title,
    required String subtitle,
    required bool isDark,
    required Color accent,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 10.8,
            fontWeight: FontWeight.w700,
            height: 1.6,
            color: isDark ? Colors.white60 : Colors.black45,
          ),
        ),
      ],
    );
  }

  Widget _favoriteReel(
      MediaItemModel item, int index, bool isDark, Color purple) {
    final imageUrl = ApiClient.buildMediaUrl(item.thumbnailUrl ?? item.fileUrl);
    final caption = (item.caption ?? '').trim().isNotEmpty
        ? item.caption!.trim()
        : item.providerDisplayName;

    return GestureDetector(
      onTap: () => _openFavoriteViewer(index),
      child: SizedBox(
        width: 88,
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(
                      colors: [
                        purple,
                        const Color(0xFFF59E0B),
                        purple.withValues(alpha: 0.85),
                        purple,
                      ],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isDark ? const Color(0xFF1F1F1F) : Colors.white,
                      ),
                      child: ClipOval(
                        child: imageUrl != null
                            ? CachedNetworkImage(
                                imageUrl: imageUrl,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) =>
                                    _brokenImgPlaceholder(isDark),
                              )
                            : _brokenImgPlaceholder(isDark),
                      ),
                    ),
                  ),
                ),
                if (item.isVideo)
                  Positioned(
                    left: 4,
                    bottom: 4,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              caption,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 10.2,
                fontWeight: FontWeight.w800,
                height: 1.4,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCacheBanner({
    required String message,
    required bool isDark,
    required Color accent,
    required bool isOffline,
    required Future<void> Function() onRefresh,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isOffline
              ? const Color(0xFFFFF7ED)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : accent.withValues(alpha: 0.06)),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isOffline
                ? const Color(0xFFF5C28B)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : accent.withValues(alpha: 0.18)),
          ),
        ),
        child: Row(
          children: [
            Icon(
              isOffline ? Icons.cloud_off_rounded : Icons.history_rounded,
              size: 16,
              color: isOffline ? const Color(0xFFB45309) : accent,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: isOffline
                      ? const Color(0xFF92400E)
                      : (isDark ? Colors.white70 : Colors.black54),
                ),
              ),
            ),
            TextButton(
              onPressed: onRefresh,
              style: TextButton.styleFrom(
                foregroundColor: isOffline ? const Color(0xFFB45309) : accent,
                minimumSize: const Size(0, 30),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                textStyle: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: const Text('تحديث'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _favoriteCard(
      MediaItemModel item, int index, bool isDark, Color purple) {
    final imageUrl = ApiClient.buildMediaUrl(item.thumbnailUrl ?? item.fileUrl);

    return GestureDetector(
      onTap: () => _openFavoriteViewer(index),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Image
            imageUrl != null
                ? CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => _brokenImgPlaceholder(isDark))
                : _brokenImgPlaceholder(isDark),

            // Video icon
            if (item.isVideo)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.play_arrow_rounded,
                      color: Colors.white, size: 14),
                ),
              ),

            // Source badge
            Positioned(
              top: 6,
              left: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: item.source == MediaItemSource.spotlight
                      ? Colors.amber.shade700
                      : purple,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  item.source == MediaItemSource.spotlight ? 'أضواء' : 'معرض',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w700),
                ),
              ),
            ),

            Positioned(
              top: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.52),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      item.isLiked ? Icons.favorite : Icons.favorite_border,
                      size: 12,
                      color: item.isLiked ? purple : Colors.white,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${item.likesCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9.5,
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      item.isSaved ? Icons.bookmark : Icons.bookmark_border,
                      size: 12,
                      color: item.isSaved ? purple : Colors.white,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${item.savesCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9.5,
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Bottom bar
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withValues(alpha: 0.7),
                      Colors.transparent
                    ],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.providerDisplayName,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 10.5,
                            fontFamily: 'Cairo'),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    GestureDetector(
                      onTap: () =>
                          _showRemoveConfirmDialog(index, isDark, purple),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(Icons.bookmark_rounded,
                            color: Colors.white, size: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openFavoriteViewer(int initialIndex) async {
    if (_favorites.isEmpty) return;
    final safeIndex = initialIndex.clamp(0, _favorites.length - 1);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SpotlightViewerPage(
          items: _favorites,
          initialIndex: safeIndex,
        ),
      ),
    );
    if (mounted) {
      _loadFavorites();
    }
  }

  Widget _brokenImgPlaceholder(bool isDark) {
    return Container(
      color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
      child: Center(
          child: Icon(Icons.broken_image_outlined,
              size: 28, color: isDark ? Colors.grey.shade600 : Colors.grey)),
    );
  }

  // =============================================
  //  REMOVE DIALOG
  // =============================================

  void _showRemoveConfirmDialog(int index, bool isDark, Color purple) {
    final item = _favorites[index];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('تأكيد الإزالة',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontFamily: 'Cairo',
                fontSize: 14,
                color: isDark ? Colors.white : Colors.black87)),
        content: Text('هل تريد إزالة المحتوى من المفضلة؟',
            style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                color: isDark ? Colors.white70 : Colors.black54)),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('إلغاء',
                style: TextStyle(
                    color: isDark ? Colors.grey.shade500 : Colors.grey,
                    fontFamily: 'Cairo',
                    fontSize: 12)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: purple,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await InteractiveService.unsaveItem(item);
              if (mounted) {
                if (success) {
                  setState(() => _favorites.removeAt(index));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('تم إزالة العنصر من المفضلة',
                          style: TextStyle(fontFamily: 'Cairo', fontSize: 11)),
                      backgroundColor: Colors.green,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('فشل إزالة العنصر — حاول مرة أخرى',
                          style: TextStyle(fontFamily: 'Cairo', fontSize: 11)),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              }
            },
            child: const Text('تأكيد',
                style: TextStyle(
                    color: Colors.white, fontFamily: 'Cairo', fontSize: 11)),
          ),
        ],
      ),
    );
  }
}
