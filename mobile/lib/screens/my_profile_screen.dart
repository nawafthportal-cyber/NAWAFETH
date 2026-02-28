import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/custom_drawer.dart';
import '../services/auth_service.dart';
import '../services/account_mode_service.dart';
import '../services/profile_service.dart';
import '../models/user_profile.dart';
import 'registration/register_service_provider.dart';
import 'provider_dashboard/provider_home_screen.dart';
import 'login_settings_screen.dart';
import 'plans_screen.dart';
import 'notifications_screen.dart';
import 'my_chats_screen.dart';
import 'orders_hub_screen.dart';
import 'interactive_screen.dart';

class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key});

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  File? _profileImage;
  File? _coverImage;

  bool _isLoading = true;
  String? _errorMessage;
  UserProfile? _userProfile;
  bool _isProviderMode = false;
  bool get isProviderRegistered => _userProfile?.hasProviderProfile ?? false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    if (!mounted) return;
    setState(() { _isLoading = true; _errorMessage = null; });

    final isLoggedIn = await AuthService.isLoggedIn();
    if (!isLoggedIn) {
      if (mounted) setState(() { _isLoading = false; _errorMessage = 'يجب تسجيل الدخول أولاً'; });
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

      setState(() { _userProfile = profile; _isProviderMode = effectiveMode; _isLoading = false; });
    } else {
      setState(() { _isLoading = false; _errorMessage = result.error; });
    }
  }

  Future<void> _pickImage({required bool isCover}) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() { isCover ? _coverImage = File(picked.path) : _profileImage = File(picked.path); });
    }
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
      return _buildShell(theme, child: const Center(child: CircularProgressIndicator(color: Colors.deepPurple)));
    }
    if (_errorMessage != null) return _buildErrorState(theme);

    return _buildClientProfile(theme);
  }

  Widget _buildShell(ThemeData theme, {required Widget child}) {
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      drawer: const CustomDrawer(),
      bottomNavigationBar: const CustomBottomNav(currentIndex: 3),
      body: child,
    );
  }

  // =============================================
  //  CLIENT PROFILE  -  2026 Design
  // =============================================

  Widget _buildClientProfile(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final profile = _userProfile!;
    const purple = Colors.deepPurple;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF5F5FA),
      drawer: const CustomDrawer(),
      bottomNavigationBar: const CustomBottomNav(currentIndex: 3),
      body: RefreshIndicator(
        onRefresh: _loadProfile,
        color: purple,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // -- Header with Cover + Avatar --
            SliverToBoxAdapter(child: _buildHeader(profile, isDark, purple)),

            // -- Quick Actions Grid --
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              sliver: SliverToBoxAdapter(child: _buildQuickActions(isDark, purple)),
            ),

            // -- Menu Tiles --
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(child: _buildMenuSection(isDark, purple, profile)),
            ),

            // -- Register as Provider CTA --
            if (!isProviderRegistered)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                sliver: SliverToBoxAdapter(child: _buildProviderCTA(isDark, purple)),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  // -- HEADER --
  Widget _buildHeader(UserProfile profile, bool isDark, Color purple) {
    return SizedBox(
      height: 268,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Cover
          Container(
            height: 140,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: _coverImage == null
                  ? LinearGradient(
                      colors: isDark
                          ? [Colors.deepPurple.shade900, Colors.deepPurple.shade800.withValues(alpha: 0.6)]
                          : [Colors.deepPurple.shade600, Colors.deepPurple.shade400],
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                    )
                  : null,
              image: _coverImage != null
                  ? DecorationImage(image: FileImage(_coverImage!), fit: BoxFit.cover)
                  : null,
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _miniIconBtn(Icons.camera_alt_outlined, () => _pickImage(isCover: true)),
                    if (isProviderRegistered) _switchModeChip(purple),
                  ],
                ),
              ),
            ),
          ),

          // Avatar + Info
          Positioned(
            top: 100,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark ? const Color(0xFF121212) : const Color(0xFFF5F5FA),
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: GestureDetector(
                    onTap: () => _pickImage(isCover: false),
                    child: CircleAvatar(
                      radius: 36,
                      backgroundColor: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                      backgroundImage: _profileImage != null ? FileImage(_profileImage!) : null,
                      child: _profileImage == null
                          ? Icon(Icons.person, size: 32, color: isDark ? Colors.white54 : Colors.grey)
                          : null,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  profile.displayName,
                  style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700, fontFamily: 'Cairo',
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                Text(
                  profile.usernameDisplay,
                  style: TextStyle(
                    fontSize: 11.5, fontFamily: 'Cairo',
                    color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 10),
                _buildStatsRow(profile, isDark, purple),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniIconBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Colors.white, size: 16),
      ),
    );
  }

  Widget _switchModeChip(Color purple) {
    return GestureDetector(
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          );
          setState(() => _isLoading = true);
          await _loadProfile();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 6)],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.swap_horiz_rounded, size: 14, color: purple),
            const SizedBox(width: 4),
            Text('مقدم خدمة', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: purple, fontFamily: 'Cairo')),
          ],
        ),
      ),
    );
  }

  // -- STATS ROW --
  Widget _buildStatsRow(UserProfile profile, bool isDark, Color purple) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: isDark
            ? null
            : [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
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
          Text(count, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: purple, fontFamily: 'Cairo')),
          Text(label, style: TextStyle(fontSize: 10, color: isDark ? Colors.grey.shade500 : Colors.grey.shade600, fontFamily: 'Cairo')),
        ],
      ),
    );
  }

  Widget _dividerVertical(bool isDark) {
    return Container(
      width: 1,
      height: 24,
      color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade200,
    );
  }

  // -- QUICK ACTIONS --
  Widget _buildQuickActions(bool isDark, Color purple) {
    final actions = [
      _QuickAction(Icons.shopping_bag_outlined, 'طلباتي', () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const OrdersHubScreen()));
      }),
      _QuickAction(Icons.chat_bubble_outline_rounded, 'محادثاتي', () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const MyChatsScreen()));
      }),
      _QuickAction(Icons.notifications_none_rounded, 'الإشعارات', () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
      }),
      _QuickAction(Icons.people_outline_rounded, 'تفاعلي', () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const InteractiveScreen()));
      }),
    ];

    return Row(
      children: actions.map((a) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: _quickActionCard(a, isDark, purple),
          ),
        );
      }).toList(),
    );
  }

  Widget _quickActionCard(_QuickAction action, bool isDark, Color purple) {
    return GestureDetector(
      onTap: action.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isDark
              ? null
              : [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: purple.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(action.icon, size: 18, color: purple),
            ),
            const SizedBox(height: 4),
            Text(
              action.label,
              style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w600, fontFamily: 'Cairo',
                color: isDark ? Colors.white70 : Colors.black87,
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
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: isDark
            ? null
            : [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          _menuTile(
            icon: Icons.person_outline_rounded,
            label: 'إعدادات الحساب',
            subtitle: profile.email ?? profile.phone ?? '',
            isDark: isDark,
            purple: purple,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginSettingsScreen())),
          ),
          _menuDivider(isDark),
          _menuTile(
            icon: Icons.workspace_premium_outlined,
            label: 'الباقات والاشتراكات',
            isDark: isDark,
            purple: purple,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlansScreen())),
          ),
          _menuDivider(isDark),
          _menuTile(
            icon: Icons.qr_code_rounded,
            label: 'QR نافذتي',
            isDark: isDark,
            purple: purple,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('شاشة QR قريبا', style: TextStyle(fontFamily: 'Cairo', fontSize: 12))),
              );
            },
          ),
          _menuDivider(isDark),
          _menuTile(
            icon: Icons.bookmark_border_rounded,
            label: 'المحفوظات',
            trailing: '${profile.favoritesMediaCount}',
            isDark: isDark,
            purple: purple,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InteractiveScreen())),
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: purple.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: purple),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, fontFamily: 'Cairo', color: isDark ? Colors.white : Colors.black87)),
                    if (subtitle != null && subtitle.isNotEmpty)
                      Text(subtitle, style: TextStyle(fontSize: 10, fontFamily: 'Cairo', color: isDark ? Colors.grey.shade600 : Colors.grey.shade500)),
                  ],
                ),
              ),
              if (trailing != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: purple.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(trailing, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: purple, fontFamily: 'Cairo')),
                ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_left_rounded, size: 18, color: isDark ? Colors.grey.shade600 : Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuDivider(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Divider(height: 1, color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade100),
    );
  }

  // -- PROVIDER CTA --
  Widget _buildProviderCTA(bool isDark, Color purple) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [Colors.deepPurple.shade900.withValues(alpha: 0.4), Colors.deepPurple.shade800.withValues(alpha: 0.2)]
              : [Colors.deepPurple.shade50, Colors.white],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: purple.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: purple.withValues(alpha: 0.1),
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
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, fontFamily: 'Cairo', color: isDark ? Colors.white : Colors.black87),
                ),
                const SizedBox(height: 2),
                Text(
                  'شارك مهاراتك وابدأ بتلقي الطلبات',
                  style: TextStyle(fontSize: 10, fontFamily: 'Cairo', color: isDark ? Colors.grey.shade500 : Colors.grey.shade600),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterServiceProviderPage())),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: purple,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'سجّل الآن',
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white, fontFamily: 'Cairo'),
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
    return _buildShell(
      theme,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                _errorMessage ?? 'حدث خطأ',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Cairo', fontSize: 13, color: isDark ? Colors.white70 : Colors.black54),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadProfile,
                icon: const Icon(Icons.refresh, color: Colors.white, size: 16),
                label: const Text('إعادة المحاولة', style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              if (_errorMessage == 'يجب تسجيل الدخول أولاً') ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pushNamed(context, '/login'),
                  child: const Text('تسجيل الدخول', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.deepPurple, fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          ),
        ),
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
