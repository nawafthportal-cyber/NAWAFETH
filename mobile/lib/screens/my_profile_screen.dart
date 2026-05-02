import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_theme.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/custom_drawer.dart';
import '../services/auth_service.dart';
import '../services/account_mode_service.dart';
import '../services/profile_service.dart';
import '../services/api_client.dart';
import '../services/unread_badge_service.dart';
import '../widgets/platform_top_bar.dart';
import '../widgets/login_required_prompt.dart';
import '../models/user_profile.dart';
import 'registration/register_service_provider.dart';
import 'provider_dashboard/provider_home_screen.dart';
import 'login_settings_screen.dart';
import 'notifications_screen.dart';
import 'my_chats_screen.dart';
import 'orders_hub_screen.dart';
import 'interactive_screen.dart';
import 'my_qr_screen.dart';

class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key});

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen>
    with SingleTickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final AnimationController _entranceController;
  File? _profileImage;
  File? _coverImage;

  bool _isLoading = true;
  bool _isUploadingImage = false;
  String? _errorMessage;
  UserProfile? _userProfile;
  bool _isProviderMode = false;
  int _notificationUnread = 0;
  int _chatUnread = 0;
  ValueListenable<UnreadBadges>? _badgeListenable;
  bool get isProviderRegistered => _userProfile?.hasProviderProfile ?? false;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _loadProfile();
    _badgeListenable = UnreadBadgeService.acquire();
    _badgeListenable!.addListener(_handleBadgeChange);
    _handleBadgeChange();
    UnreadBadgeService.refresh(force: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _entranceController.forward();
      }
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _badgeListenable?.removeListener(_handleBadgeChange);
    UnreadBadgeService.release();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final isLoggedIn = await AuthService.isLoggedIn();
    if (!isLoggedIn) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'يجب تسجيل الدخول أولاً';
        });
      }
      return;
    }

    final result = await ProfileService.fetchMyProfile();
    if (!mounted) return;

    if (result.isSuccess && result.data != null) {
      final profile = result.data!;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isProviderRegistered', profile.hasProviderProfile);

      final canSwitch = profile.isProvider || profile.hasProviderProfile;
      final saved = await AccountModeService.isProviderMode();
      final effectiveMode = canSwitch ? saved : false;
      await AccountModeService.setProviderMode(effectiveMode);

      setState(() {
        _userProfile = profile;
        _isProviderMode = effectiveMode;
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = result.error;
      });
    }
  }

  Future<void> _pickImage({required bool isCover}) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      final selected = File(picked.path);
      if (!mounted) return;

      setState(() {
        if (isCover) {
          _coverImage = selected;
        } else {
          _profileImage = selected;
        }
      });

      setState(() => _isUploadingImage = true);
      final result = await ProfileService.uploadMyProfileImages(
        profileImagePath: isCover ? null : selected.path,
        coverImagePath: isCover ? selected.path : null,
      );
      if (!mounted) return;
      setState(() => _isUploadingImage = false);

      if (result.isSuccess && result.data != null) {
        setState(() {
          _userProfile = result.data;
          if (isCover) {
            _coverImage = null;
          } else {
            _profileImage = null;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حفظ الصورة بنجاح',
                style: TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ?? 'تعذر حفظ الصورة',
                style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _loadUnreadBadges() async {
    await UnreadBadgeService.refresh(force: true);
  }

  void _handleBadgeChange() {
    final badges = _badgeListenable?.value ?? UnreadBadges.empty;
    if (!mounted) return;
    setState(() {
      _notificationUnread = badges.notifications;
      _chatUnread = badges.chats;
    });
  }

  // =============================================
  //  BUILD
  // =============================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!_isLoading && _errorMessage == null && _isProviderMode) {
      return const ProviderHomeScreen();
    }

    if (_isLoading) {
      return _buildShell(theme,
          child: const Center(
              child: CircularProgressIndicator(color: AppColors.primary)));
    }
    if (_errorMessage != null) return _buildErrorState(theme);

    return _buildClientProfile(theme);
  }

  Widget _buildShell(ThemeData theme, {required Widget child}) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: theme.scaffoldBackgroundColor,
      drawer: const CustomDrawer(),
      bottomNavigationBar: const CustomBottomNav(currentIndex: 3),
      body: child,
    );
  }

  Widget _buildClientProfile(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final profile = _userProfile!;
    const accent = Color(0xFF5E35B1);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor:
          isDark ? const Color(0xFF0F0A1E) : const Color(0xFFF5F0FF),
      drawer: const CustomDrawer(),
      bottomNavigationBar: const CustomBottomNav(currentIndex: 3),
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark
              ? const LinearGradient(
                  colors: [
                    Color(0xFF0D1724),
                    Color(0xFF111D2C),
                    Color(0xFF172331)
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                )
              : const LinearGradient(
                  colors: [
                    Color(0xFFF5F0FF),
                    Color(0xFFF7F4FF),
                    Color(0xFFF9F7FF)
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
        ),
        child: RefreshIndicator(
          onRefresh: _loadProfile,
          color: accent,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                    child: PlatformTopBar(
                      overlay: false,
                      height: 62,
                      showMenuButton: true,
                      notificationCount: _notificationUnread,
                      chatCount: _chatUnread,
                      onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
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
              ),
              SliverToBoxAdapter(
                child: _buildEntrance(1, _buildHeader(profile, isDark, accent)),
              ),
              if (isProviderRegistered)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                  sliver: SliverToBoxAdapter(
                    child: _buildEntrance(2, _buildModeToggle(isDark, accent)),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                sliver: SliverToBoxAdapter(
                  child: _buildEntrance(3, _buildQuickActions(isDark, accent)),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                sliver: SliverToBoxAdapter(
                  child: _buildEntrance(
                      4, _buildMenuSection(isDark, accent, profile)),
                ),
              ),
              if (!isProviderRegistered)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  sliver: SliverToBoxAdapter(
                    child: _buildEntrance(5, _buildProviderCTA(isDark, accent)),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 28)),
            ],
          ),
        ),
      ),
    );
  }

  // -- HEADER --
  Widget _buildHeader(UserProfile profile, bool isDark, Color accent) {
    final screenWidth = MediaQuery.of(context).size.width;
    final coverHeight = screenWidth < 380 ? 178.0 : 198.0;
    final avatarTop = coverHeight - 40;
    final headerHeight = coverHeight + 176;
    final coverImageUrl = ApiClient.buildMediaUrl(profile.coverImage);
    final profileImageUrl = ApiClient.buildMediaUrl(profile.profileImage);

    ImageProvider<Object>? coverImageProvider;
    if (_coverImage != null) {
      coverImageProvider = FileImage(_coverImage!);
    } else if (coverImageUrl != null) {
      coverImageProvider = CachedNetworkImageProvider(coverImageUrl);
    }

    ImageProvider<Object>? profileImageProvider;
    if (_profileImage != null) {
      profileImageProvider = FileImage(_profileImage!);
    } else if (profileImageUrl != null) {
      profileImageProvider = CachedNetworkImageProvider(profileImageUrl);
    }

    return SizedBox(
      height: headerHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: coverHeight,
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: coverImageProvider == null
                  ? LinearGradient(
                      colors: isDark
                          ? [
                              const Color(0xFF5E35B1),
                              const Color(0xFF7E57C2),
                              const Color(0xFF9575CD),
                            ]
                          : [
                              const Color(0xFF5E35B1),
                              const Color(0xFF7E57C2),
                              const Color(0xFF9575CD),
                            ],
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                    )
                  : null,
              image: coverImageProvider != null
                  ? DecorationImage(
                      image: coverImageProvider, fit: BoxFit.cover)
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.08),
                      Colors.black.withValues(alpha: 0.38),
                    ],
                  ),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _miniIconBtn(
                          icon: Icons.camera_alt_outlined,
                          onTap: () => _pickImage(isCover: true),
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: avatarTop,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF0E1726)
                          : const Color(0xFFF2F7FB),
                      width: 4,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.22),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: GestureDetector(
                    onTap: () => _pickImage(isCover: false),
                    child: CircleAvatar(
                      radius: 40,
                      backgroundColor:
                          isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                      backgroundImage: profileImageProvider,
                      child: profileImageProvider == null
                          ? Icon(Icons.person,
                              size: 36,
                              color: isDark ? Colors.white54 : Colors.grey)
                          : null,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  profile.displayName,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'Cairo',
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  profile.usernameDisplay,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Cairo',
                    color: isDark
                        ? const Color(0xFF91A4B9)
                        : const Color(0xFF4F657D),
                  ),
                ),
                const SizedBox(height: 10),
                _buildStatsRow(profile, isDark, accent),
                if (_isUploadingImage) ...[
                  const SizedBox(height: 8),
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniIconBtn({
    required IconData icon,
    required VoidCallback onTap,
    int count = 0,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.26),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.26)),
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

  // -- ACCOUNT MODE TOGGLE --
  Widget _buildModeToggle(bool isDark, Color purple) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1036) : const Color(0xFFF0EAFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0x335E35B1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF5E35B1) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: purple.withValues(alpha: isDark ? 0.22 : 0.10),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.person_rounded,
                      size: 16, color: isDark ? Colors.white : purple),
                  const SizedBox(width: 5),
                  Text(
                    'عميل',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'Cairo',
                      color: isDark ? Colors.white : purple,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: GestureDetector(
              onTap: () async {
                await AccountModeService.setProviderMode(true);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('تم التبديل إلى حساب مقدم الخدمة',
                          style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                      backgroundColor: Colors.green,
                      duration: const Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  );
                  setState(() => _isLoading = true);
                  await _loadProfile();
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.work_outline_rounded,
                        size: 16,
                        color: isDark
                            ? Colors.grey.shade500
                            : Colors.grey.shade500),
                    const SizedBox(width: 5),
                    Text(
                      'مقدم خدمة',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Cairo',
                        color: isDark
                            ? Colors.grey.shade500
                            : Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -- STATS ROW --
  Widget _buildStatsRow(UserProfile profile, bool isDark, Color purple) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1036) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0x225E35B1),
        ),
        boxShadow: [
          BoxShadow(
            color:
                const Color(0xFF5E35B1).withValues(alpha: isDark ? 0.10 : 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _statItem('${profile.followingCount}', 'أتابع', isDark, purple),
          _dividerVertical(isDark),
          _statItem('${profile.likesCount}', 'إعجاب', isDark, purple),
          _dividerVertical(isDark),
          _statItem('${profile.favoritesMediaCount}', 'مفضلتي', isDark, purple),
        ],
      ),
    );
  }

  Widget _statItem(String count, String label, bool isDark, Color purple) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(count,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: purple,
                  fontFamily: 'Cairo')),
          Text(label,
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? const Color(0xFF92A6BA)
                      : const Color(0xFF4F657D),
                  fontFamily: 'Cairo')),
        ],
      ),
    );
  }

  Widget _dividerVertical(bool isDark) {
    return Container(
      width: 1,
      height: 24,
      color:
          isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade200,
    );
  }

  // -- QUICK ACTIONS --
  Widget _buildQuickActions(bool isDark, Color purple) {
    final actions = [
      _QuickAction(Icons.shopping_bag_outlined, 'طلباتي', () {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const OrdersHubScreen()));
      }),
      _QuickAction(Icons.bookmark_border_rounded, 'محفوظاتي', () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const InteractiveScreen(
              initialTab: InteractiveInitialTab.favorites,
            ),
          ),
        );
      }),
      _QuickAction(Icons.chat_bubble_outline_rounded, 'محادثاتي', () {
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => const MyChatsScreen()));
      }),
      _QuickAction(Icons.people_outline_rounded, 'تفاعلي', () {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const InteractiveScreen()));
      }),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1A1036)
            : Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0x225E35B1),
        ),
        boxShadow: [
          BoxShadow(
            color:
                const Color(0xFF5E35B1).withValues(alpha: isDark ? 0.10 : 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'الوصول السريع',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'أوامر يومية سريعة للطلبات والمحادثات والتنبيهات والتفاعل.',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11,
              height: 1.8,
              fontWeight: FontWeight.w700,
              color: isDark ? const Color(0xFF92A6BA) : const Color(0xFF4F657D),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: actions.map((a) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _quickActionCard(a, isDark, purple),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _quickActionCard(_QuickAction action, bool isDark, Color purple) {
    return GestureDetector(
      onTap: action.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1036) : const Color(0xFFF5F1FF),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : const Color(0x225E35B1),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: purple.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(action.icon, size: 20, color: purple),
            ),
            const SizedBox(height: 6),
            Text(
              action.label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                fontFamily: 'Cairo',
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -- MENU SECTION --
  Widget _buildMenuSection(bool isDark, Color purple, UserProfile profile) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1A1036)
            : Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0x225E35B1),
        ),
        boxShadow: [
          BoxShadow(
            color:
                const Color(0xFF5E35B1).withValues(alpha: isDark ? 0.10 : 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'إدارة الحساب',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _menuTile(
            icon: Icons.person_outline_rounded,
            label: 'إعدادات الحساب',
            subtitle: profile.email ?? profile.phone ?? '',
            isDark: isDark,
            purple: purple,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const LoginSettingsScreen())),
          ),
          _menuDivider(isDark),
          _menuTile(
            icon: Icons.qr_code_rounded,
            label: 'QR نافذتي',
            isDark: isDark,
            purple: purple,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MyQrScreen()),
            ),
          ),
          _menuDivider(isDark),
          _menuTile(
            icon: Icons.bookmark_border_rounded,
            label: 'المحفوظات',
            trailing: '${profile.favoritesMediaCount}',
            isDark: isDark,
            purple: purple,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const InteractiveScreen(
                  initialTab: InteractiveInitialTab.favorites,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _menuTile({
    required IconData icon,
    required String label,
    String? subtitle,
    String? trailing,
    required bool isDark,
    required Color purple,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: purple.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 18, color: purple),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Cairo',
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF0F172A))),
                    if (subtitle != null && subtitle.isNotEmpty)
                      Text(subtitle,
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Cairo',
                              color: isDark
                                  ? const Color(0xFF92A6BA)
                                  : const Color(0xFF4F657D))),
                  ],
                ),
              ),
              if (trailing != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: purple.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(trailing,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: purple,
                          fontFamily: 'Cairo')),
                ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_left_rounded,
                  size: 18,
                  color: isDark ? Colors.grey.shade600 : Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuDivider(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Divider(
          height: 1,
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.grey.shade100),
    );
  }

  // -- PROVIDER CTA --
  Widget _buildProviderCTA(bool isDark, Color purple) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [
                  const Color(0xFF5E35B1).withValues(alpha: 0.28),
                  const Color(0xFF7E57C2).withValues(alpha: 0.14)
                ]
              : [const Color(0xFFF0EAFF), Colors.white],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: purple.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: purple.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.rocket_launch_rounded, size: 22, color: purple),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'انضم كمقدم خدمة',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Cairo',
                      color: isDark ? Colors.white : const Color(0xFF0F172A)),
                ),
                const SizedBox(height: 2),
                Text(
                  'شارك مهاراتك وابدأ بتلقي الطلبات',
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Cairo',
                      color: isDark
                          ? const Color(0xFFB2C2D2)
                          : const Color(0xFF4F657D)),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const RegisterServiceProviderPage())),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: purple,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'سجّل الآن',
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    fontFamily: 'Cairo'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -- ERROR STATE --
  Widget _buildErrorState(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final isLoginRequired = _errorMessage == 'يجب تسجيل الدخول أولاً';
    if (isLoginRequired) {
      return _buildShell(
        theme,
        child: LoginRequiredPrompt(
          title: 'الدخول لحسابك مطلوب',
          message: 'سجّل دخولك للوصول إلى صفحة الملف الشخصي وإدارة بياناتك.',
          onLoginTap: () => Navigator.pushNamed(context, '/login'),
        ),
      );
    }
    return _buildShell(
      theme,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded,
                  size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                _errorMessage ?? 'حدث خطأ',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    color: isDark ? Colors.white70 : Colors.black54),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadProfile,
                icon: const Icon(Icons.refresh, color: Colors.white, size: 16),
                label: const Text('إعادة المحاولة',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        color: Colors.white,
                        fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEntrance(int index, Widget child) {
    final begin = (0.08 * index).clamp(0.0, 0.8).toDouble();
    final end = (begin + 0.34).clamp(0.0, 1.0).toDouble();
    final animation = CurvedAnimation(
      parent: _entranceController,
      curve: Interval(begin, end, curve: Curves.easeOutCubic),
    );

    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }
}

class _QuickAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickAction(this.icon, this.label, this.onTap);
}
