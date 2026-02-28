import 'package:flutter/material.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/custom_drawer.dart';
import 'chat_detail_screen.dart';
import 'provider_profile_screen.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/account_mode_service.dart';
import '../services/interactive_service.dart';
import '../models/provider_public_model.dart';
import '../models/user_public_model.dart';
import '../models/media_item_model.dart';

class InteractiveScreen extends StatefulWidget {
  const InteractiveScreen({super.key});

  @override
  State<InteractiveScreen> createState() => _InteractiveScreenState();
}

class _InteractiveScreenState extends State<InteractiveScreen>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;

  bool _isProviderMode = false;
  bool _isLoggedIn = false;
  bool _authChecked = false;

  List<ProviderPublicModel> _following = [];
  List<UserPublicModel> _followers = [];
  List<MediaItemModel> _favorites = [];

  bool _followingLoading = true;
  bool _followersLoading = true;
  bool _favoritesLoading = true;

  String? _followingError;
  String? _followersError;
  String? _favoritesError;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    final loggedIn = await AuthService.isLoggedIn();
    if (!mounted) return;
    setState(() { _isLoggedIn = loggedIn; _authChecked = true; });
    if (!loggedIn) return;

    final isProviderMode = await AccountModeService.isProviderMode();

    if (mounted) {
      setState(() => _isProviderMode = isProviderMode);
      _initTabController();
    }

    await Future.wait([
      _loadFollowing(),
      if (_isProviderMode) _loadFollowers(),
      _loadFavorites(),
    ]);

    if (!_isProviderMode && mounted) {
      setState(() { _followersLoading = false; _followers = []; });
    }
  }

  void _initTabController() {
    _tabController?.dispose();
    final tabCount = _isProviderMode ? 3 : 2;
    _tabController = TabController(length: tabCount, vsync: this);
  }

  Future<void> _loadFollowing() async {
    if (!mounted) return;
    setState(() { _followingLoading = true; _followingError = null; });
    final result = await InteractiveService.fetchFollowing();
    if (!mounted) return;
    setState(() {
      _followingLoading = false;
      if (result.isSuccess) { _following = result.items; }
      else { _followingError = result.error; }
    });
  }

  Future<void> _loadFollowers() async {
    if (!mounted) return;
    setState(() { _followersLoading = true; _followersError = null; });
    if (!_isProviderMode) {
      if (mounted) setState(() { _followersLoading = false; _followers = []; });
      return;
    }
    final result = await InteractiveService.fetchFollowers();
    if (!mounted) return;
    setState(() {
      _followersLoading = false;
      if (result.isSuccess) { _followers = result.items; }
      else { _followersError = result.error; }
    });
  }

  Future<void> _loadFavorites() async {
    if (!mounted) return;
    setState(() { _favoritesLoading = true; _favoritesError = null; });
    final result = await InteractiveService.fetchFavorites();
    if (!mounted) return;
    setState(() {
      _favoritesLoading = false;
      if (result.isSuccess) { _favorites = result.items; }
      else { _favoritesError = result.error; }
    });
  }

  @override
  void dispose() {
    _tabController?.dispose();
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
      return _shell(isDark, purple, body: const Center(child: CircularProgressIndicator(color: Colors.deepPurple)));
    }

    // Not logged in — show login prompt
    if (!_isLoggedIn) {
      return _shell(isDark, purple, body: _loginRequiredState(isDark, purple));
    }

    if (_tabController == null) {
      return _shell(isDark, purple, body: const Center(child: CircularProgressIndicator(color: Colors.deepPurple)));
    }

    return _shell(
      isDark,
      purple,
      body: Column(
        children: [
          // -- Custom Tab Bar --
          _buildTabBar(isDark, purple),
          // -- Tab Content --
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: _isProviderMode
                  ? [_buildFollowingTab(isDark, purple), _buildFollowersTab(isDark, purple), _buildFavoritesTab(isDark, purple)]
                  : [_buildFollowingTab(isDark, purple), _buildFavoritesTab(isDark, purple)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _shell(bool isDark, Color purple, {required Widget body}) {
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF5F5FA),
      drawer: const CustomDrawer(),
      bottomNavigationBar: const CustomBottomNav(currentIndex: 2),
      body: SafeArea(child: body),
    );
  }

  // -- TAB BAR --
  Widget _buildTabBar(bool isDark, Color purple) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(14),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: isDark ? Colors.deepPurple.shade700 : Colors.white,
          borderRadius: BorderRadius.circular(11),
          boxShadow: isDark
              ? null
              : [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4, offset: const Offset(0, 1))],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: isDark ? Colors.white : purple,
        unselectedLabelColor: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
        labelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 11.5, fontWeight: FontWeight.w500),
        tabs: _isProviderMode
            ? [
                _tabItem(Icons.people_outline_rounded, 'من أتابع'),
                _tabItem(Icons.person_outline_rounded, 'متابعيني'),
                _tabItem(Icons.bookmark_outline_rounded, 'مفضلتي'),
              ]
            : [
                _tabItem(Icons.people_outline_rounded, 'من أتابع'),
                _tabItem(Icons.bookmark_outline_rounded, 'مفضلتي'),
              ],
      ),
    );
  }

  Widget _tabItem(IconData icon, String label) {
    return Tab(
      height: 36,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15),
          const SizedBox(width: 4),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  // =============================================
  //  SHARED WIDGETS
  // =============================================

  Widget _loadingState() {
    return const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: Colors.deepPurple)));
  }

  Widget _errorState(String message, VoidCallback onRetry, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 44, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: isDark ? Colors.white54 : Colors.black45)),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 15, color: Colors.white),
              label: const Text('إعادة المحاولة', style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
            Text(message, textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: isDark ? Colors.white54 : Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }

  Widget _loginRequiredState(bool isDark, Color purple) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: purple.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.lock_outline_rounded, size: 44, color: Colors.grey.shade400),
            ),
            const SizedBox(height: 16),
            Text(
              'يجب تسجيل الدخول لعرض هذه الصفحة',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.black54),
            ),
            const SizedBox(height: 8),
            Text(
              'سجّل دخولك لمتابعة مزودي الخدمة وحفظ المفضلة',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: isDark ? Colors.white38 : Colors.grey.shade500),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/login'),
              icon: const Icon(Icons.login_rounded, size: 16, color: Colors.white),
              label: const Text('تسجيل الدخول', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: purple,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =============================================
  //  TAB: FOLLOWING
  // =============================================

  Widget _buildFollowingTab(bool isDark, Color purple) {
    if (_followingLoading) return _loadingState();
    if (_followingError != null) return _errorState(_followingError!, _loadFollowing, isDark);
    if (_following.isEmpty) return _emptyState(Icons.group_off_rounded, 'لا تتابع أي مزود خدمة حتى الآن', isDark);

    return RefreshIndicator(
      onRefresh: _loadFollowing,
      color: purple,
      child: GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.72,
        ),
        itemCount: _following.length,
        itemBuilder: (context, index) => _followingCard(_following[index], isDark, purple),
      ),
    );
  }

  Widget _followingCard(ProviderPublicModel provider, bool isDark, Color purple) {
    final coverUrl = ApiClient.buildMediaUrl(provider.coverImage);
    final profileUrl = ApiClient.buildMediaUrl(provider.profileImage);

    return GestureDetector(
      onTap: () => _navigateToProvider(provider),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: isDark
              ? null
            : [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          // Provider header
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: purple.withValues(alpha: 0.1),
                  backgroundImage: profileUrl != null ? NetworkImage(profileUrl) : null,
                  child: profileUrl == null
                      ? Text(
                          provider.displayName.isNotEmpty ? provider.displayName[0] : '؟',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: purple),
                        )
                      : null,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              provider.displayName,
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, fontFamily: 'Cairo', color: isDark ? Colors.white : Colors.black87),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (provider.isVerified) ...[
                            const SizedBox(width: 3),
                            Icon(Icons.verified, size: 12, color: provider.isVerifiedBlue ? Colors.blue : Colors.green),
                          ],
                        ],
                      ),
                      if (provider.city != null && provider.city!.isNotEmpty)
                        Text(provider.city!, style: TextStyle(fontSize: 9, fontFamily: 'Cairo', color: isDark ? Colors.grey.shade600 : Colors.grey.shade500)),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => ChatDetailScreen(peerName: provider.displayName, peerProviderId: provider.id),
                  )),
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: purple.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Icon(Icons.chat_bubble_outline_rounded, size: 14, color: purple),
                  ),
                ),
              ],
            ),
          ),

          // Cover image
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: coverUrl != null
                    ? Image.network(coverUrl, fit: BoxFit.cover, width: double.infinity,
                        errorBuilder: (_, __, ___) => _imgPlaceholder(isDark))
                    : _imgPlaceholder(isDark),
              ),
            ),
          ),

          // Stats row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _miniStat(Icons.people_outline, '${provider.followersCount}', isDark),
                _miniStat(Icons.favorite_outline, '${provider.likesCount}', isDark),
                if (provider.ratingAvg > 0)
                  _miniStat(Icons.star_outline_rounded, provider.ratingAvg.toStringAsFixed(1), isDark),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  void _navigateToProvider(ProviderPublicModel p) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => ProviderProfileScreen(
        providerId: p.id.toString(),
        providerName: p.displayName,
        providerRating: p.ratingAvg,
        providerOperations: p.completedRequests,
        providerImage: ApiClient.buildMediaUrl(p.profileImage),
        providerVerified: p.isVerified,
        providerPhone: p.phone,
        providerLat: p.lat,
        providerLng: p.lng,
      ),
    ));
  }

  Widget _imgPlaceholder(bool isDark) {
    return Container(
      color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
      child: Center(child: Icon(Icons.image_outlined, size: 28, color: isDark ? Colors.grey.shade600 : Colors.grey.shade400)),
    );
  }

  Widget _miniStat(IconData icon, String value, bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: isDark ? Colors.grey.shade500 : Colors.grey.shade500),
        const SizedBox(width: 2),
        Text(value, style: TextStyle(fontSize: 10, fontFamily: 'Cairo', color: isDark ? Colors.grey.shade400 : Colors.grey.shade600)),
      ],
    );
  }

  // =============================================
  //  TAB: FOLLOWERS
  // =============================================

  Widget _buildFollowersTab(bool isDark, Color purple) {
    if (_followersLoading) return _loadingState();
    if (_followersError != null) return _errorState(_followersError!, _loadFollowers, isDark);
    if (_followers.isEmpty) return _emptyState(Icons.person_off_rounded, 'لا يوجد متابعون بعد', isDark);

    return RefreshIndicator(
      onRefresh: _loadFollowers,
      color: purple,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        itemCount: _followers.length,
        itemBuilder: (context, index) => _followerTile(_followers[index], isDark, purple),
      ),
    );
  }

  Widget _followerTile(UserPublicModel user, bool isDark, Color purple) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: isDark
            ? null
            : [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 5, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: purple.withValues(alpha: 0.1),
              child: Text(
                user.displayName.isNotEmpty ? user.displayName[0] : '؟',
                style: TextStyle(color: purple, fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.displayName, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, fontFamily: 'Cairo', color: isDark ? Colors.white : Colors.black87)),
                  Text(user.usernameDisplay, style: TextStyle(fontSize: 10, fontFamily: 'Cairo', color: isDark ? Colors.grey.shade500 : Colors.grey.shade500)),
                ],
              ),
            ),
            GestureDetector(
              onTap: () {
                if (user.hasProviderProfile) {
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => ChatDetailScreen(peerName: user.displayName, peerProviderId: user.providerId),
                  ));
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('لا يمكن مراسلة هذا المستخدم — ليس لديه ملف مزود خدمة', style: TextStyle(fontFamily: 'Cairo', fontSize: 11)),
                      backgroundColor: Colors.orange.shade700,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: purple,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.chat_bubble_outline_rounded, size: 12, color: Colors.white),
                    SizedBox(width: 4),
                    Text('مراسلة', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600, fontFamily: 'Cairo')),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =============================================
  //  TAB: FAVORITES
  // =============================================

  Widget _buildFavoritesTab(bool isDark, Color purple) {
    if (_favoritesLoading) return _loadingState();
    if (_favoritesError != null) return _errorState(_favoritesError!, _loadFavorites, isDark);
    if (_favorites.isEmpty) return _emptyState(Icons.bookmark_outline_rounded, 'لا توجد عناصر محفوظة في المفضلة', isDark);

    return RefreshIndicator(
      onRefresh: _loadFavorites,
      color: purple,
      child: GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.85,
        ),
        itemCount: _favorites.length,
        itemBuilder: (context, index) => _favoriteCard(_favorites[index], index, isDark, purple),
      ),
    );
  }

  Widget _favoriteCard(MediaItemModel item, int index, bool isDark, Color purple) {
    final imageUrl = ApiClient.buildMediaUrl(item.thumbnailUrl ?? item.fileUrl);

    return GestureDetector(
      onTap: () => _navigateToProviderById(item.providerId, item.providerDisplayName),
      child: ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Image
          imageUrl != null
              ? Image.network(imageUrl, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _brokenImgPlaceholder(isDark))
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
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 14),
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
                style: const TextStyle(color: Colors.white, fontSize: 9, fontFamily: 'Cairo', fontWeight: FontWeight.w700),
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
                  colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.providerDisplayName,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 10.5, fontFamily: 'Cairo'),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _showRemoveConfirmDialog(index, isDark, purple),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.bookmark_rounded, color: Colors.white, size: 14),
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

  void _navigateToProviderById(int providerId, String providerName) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => ProviderProfileScreen(
        providerId: providerId.toString(),
        providerName: providerName,
      ),
    ));
  }

  Widget _brokenImgPlaceholder(bool isDark) {
    return Container(
      color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
      child: Center(child: Icon(Icons.broken_image_outlined, size: 28, color: isDark ? Colors.grey.shade600 : Colors.grey)),
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
        title: Text('تأكيد الإزالة', style: TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Cairo', fontSize: 14, color: isDark ? Colors.white : Colors.black87)),
        content: Text('هل تريد إزالة المحتوى من المفضلة؟', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: isDark ? Colors.white70 : Colors.black54)),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('إلغاء', style: TextStyle(color: isDark ? Colors.grey.shade500 : Colors.grey, fontFamily: 'Cairo', fontSize: 12)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: purple,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await InteractiveService.unsaveItem(item);
              if (mounted) {
                if (success) {
                  setState(() => _favorites.removeAt(index));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('تم إزالة العنصر من المفضلة', style: TextStyle(fontFamily: 'Cairo', fontSize: 11)),
                      backgroundColor: Colors.green,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('فشل إزالة العنصر — حاول مرة أخرى', style: TextStyle(fontFamily: 'Cairo', fontSize: 11)),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              }
            },
            child: const Text('تأكيد', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 11)),
          ),
        ],
      ),
    );
  }
}
