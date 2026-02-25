import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/bottom_nav.dart';
import 'interactive_screen.dart';
import 'registration/register_service_provider.dart';
import 'provider_dashboard/provider_home_screen.dart';
import 'login_settings_screen.dart';
import 'notification_settings_screen.dart';
import 'terms_screen.dart';
import '../widgets/custom_drawer.dart';
import '../services/account_api.dart';
import '../services/providers_api.dart';
import '../services/session_storage.dart';
import '../services/role_controller.dart';
import '../services/account_switcher.dart';
import '../constants/colors.dart';
import '../widgets/profile_account_modes_panel.dart';
import '../widgets/account_switch_sheet.dart';
import '../widgets/profile_action_card.dart';
import '../widgets/profile_quick_links_panel.dart';
import '../utils/auth_guard.dart';

class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key});

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen>
    with SingleTickerProviderStateMixin {
  File? _profileImage;
  File? _coverImage;
  bool isProvider = false;
  bool isProviderRegistered = false;
  bool _isLoading = true;
  String? _fullName;
  String? _username;
  String? _phone;
  int? _followingCount;
  int? _likesCount;
  int? _userId;
  bool _switchingAccount = false;

  @override
  void initState() {
    super.initState();
    _loadIdentityFromStorage();
    _refreshRoleAndUserType();
  }

  String _keepDigits(String input) => input.replaceAll(RegExp(r'[^0-9]'), '');

  /// Display Saudi phone numbers in local format: 05XXXXXXXX (10 digits).
  /// Falls back to the original value if it can't be normalized.
  String _asLocalSaudiPhone(String raw) {
    final digits = _keepDigits(raw.trim());
    if (RegExp(r'^05\d{8}$').hasMatch(digits)) return digits;
    if (RegExp(r'^5\d{8}$').hasMatch(digits)) return '0$digits';
    if (RegExp(r'^9665\d{8}$').hasMatch(digits)) return '0${digits.substring(3)}';
    if (RegExp(r'^009665\d{8}$').hasMatch(digits)) return '0${digits.substring(5)}';
    return raw.trim();
  }

  Future<void> _refreshRoleAndUserType() async {
    await _syncRoleFromBackend();
    await _checkUserType();
  }

  Future<void> _refreshProfile() async {
    await _loadIdentityFromStorage();
    await _refreshRoleAndUserType();
  }

  Future<void> _syncRoleFromBackend() async {
    try {
      final loggedIn = await const SessionStorage().isLoggedIn();
      if (!loggedIn) return;

      final me = await AccountApi().me();
      final hasProviderProfile = me['has_provider_profile'] == true;
      final roleState = (me['role_state'] ?? '').toString().trim().toLowerCase();
      final isProviderByRole = me['is_provider'] == true || roleState == 'provider';
      final providerProfileIdRaw = me['provider_profile_id'];
      final providerProfileId = providerProfileIdRaw is int
          ? providerProfileIdRaw
          : int.tryParse((providerProfileIdRaw ?? '').toString());

      // Trust the /accounts/me/ response instead of making a fallback
      // network call to /providers/me/profile/ which returns 404 for clients.
      const bool hasProviderProfileFallback = false;

      final isProviderRegisteredBackend =
          hasProviderProfile ||
          providerProfileId != null ||
          isProviderByRole ||
          hasProviderProfileFallback;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isProviderRegistered', isProviderRegisteredBackend);

      if (!isProviderRegisteredBackend) {
        await prefs.setBool('isProvider', false);
      }

      await RoleController.instance.refreshFromPrefs();

      String? nonEmpty(dynamic v) {
        final s = (v ?? '').toString().trim();
        return s.isEmpty ? null : s;
      }

      final firstName = nonEmpty(me['first_name']);
      final lastName = nonEmpty(me['last_name']);
      final username = nonEmpty(me['username']);
      final email = nonEmpty(me['email']);
      final phone = nonEmpty(me['phone']);

      final fullNameParts = [
        if (firstName != null) firstName,
        if (lastName != null) lastName,
      ];
      final fullName = fullNameParts.isEmpty ? null : fullNameParts.join(' ');

      await const SessionStorage().saveProfile(
        username: username,
        email: email,
        firstName: firstName,
        lastName: lastName,
        phone: phone,
      );

      int? asInt(dynamic v) {
        if (v is int) return v;
        if (v is num) return v.toInt();
        final s = (v ?? '').toString().trim();
        return int.tryParse(s);
      }

      int? likesCount = asInt(me['favorites_media_count']);
      if (likesCount == null) {
        try {
          likesCount = (await ProvidersApi().getMyFavoriteMedia()).length;
        } catch (_) {
          likesCount = null;
        }
      }

      if (!mounted) return;
      setState(() {
        _userId = asInt(me['id']);
        _fullName = fullName;
        _username = username;
        _phone = phone;
        _followingCount = asInt(me['following_count']);
        _likesCount = likesCount;
      });
    } catch (_) {
      // Best-effort
    }
  }

  Future<void> _loadIdentityFromStorage() async {
    const storage = SessionStorage();
    final fullName = (await storage.readFullName())?.trim();
    final username = (await storage.readUsername())?.trim();
    final phone = (await storage.readPhone())?.trim();
    if (!mounted) return;
    setState(() {
      _fullName = (fullName == null || fullName.isEmpty) ? null : fullName;
      _username = (username == null || username.isEmpty) ? null : username;
      _phone = (phone == null || phone.isEmpty) ? null : phone;
    });
  }

  Future<void> _checkUserType() async {
    final prefs = await SharedPreferences.getInstance();
    final bool isProviderUser = prefs.getBool('isProvider') ?? false;
    final bool isRegistered = prefs.getBool('isProviderRegistered') ?? false;
    
    if (mounted) {
      setState(() {
        isProvider = isProviderUser && isRegistered;
        isProviderRegistered = isRegistered;
        _isLoading = false;
      });
    }
  }

  Future<void> _pickImage({required bool isCover}) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        isCover
            ? _coverImage = File(picked.path)
            : _profileImage = File(picked.path);
      });
    }
  }

  String? _buildClientShareLink() {
    final id = _userId;
    if (id == null) return null;
    return 'nawafeth://user/$id';
  }

  void _showClientQrDialog() {
    final link = _buildClientShareLink();
    showDialog(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'QR نافذتي',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.deepPurple
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    width: 200,
                    height: 200,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                         BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                      border: Border.all(color: Colors.grey.shade100),
                    ),
                    child: link == null
                        ? const Center(child: Text('غير متوفر', style: TextStyle(fontFamily: 'Cairo')))
                        : QrImageView(data: link, padding: EdgeInsets.zero),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: link == null
                              ? null
                              : () async {
                                  final messenger = ScaffoldMessenger.of(context);
                                  await Clipboard.setData(ClipboardData(text: link));
                                  if (!dialogContext.mounted || !context.mounted) return;
                                  Navigator.pop(dialogContext);
                                  messenger.showSnackBar(
                                    const SnackBar(content: Text('تم نسخ الرابط')),
                                  );
                                },
                           style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.deepPurple,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                           ),
                          icon: const Icon(Icons.copy, size: 18),
                          label: const Text('نسخ', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: link == null
                              ? null
                              : () async {
                                  await Share.share(link);
                                },
                          style: OutlinedButton.styleFrom(
                             foregroundColor: AppColors.deepPurple,
                             side: const BorderSide(color: AppColors.deepPurple),
                             padding: const EdgeInsets.symmetric(vertical: 12),
                             shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                          ),
                          icon: const Icon(Icons.share, size: 18),
                          label: const Text('مشاركة', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoading && isProvider) {
      return const ProviderHomeScreen();
    }
    
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.deepPurple),
        ),
        bottomNavigationBar: const CustomBottomNav(currentIndex: 3),
      );
    }
    
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).scaffoldBackgroundColor
            : AppColors.primaryLight,
        drawer: const CustomDrawer(),
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              SliverAppBar(
                expandedHeight: 280.0,
                floating: false,
                pinned: true,
                backgroundColor: AppColors.deepPurple,
                elevation: 0,
                scrolledUnderElevation: 0,
                leading: Builder(
                  builder: (context) => IconButton(
                    icon: const Icon(Icons.menu, color: Colors.white),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  ),
                ),
                actions: [
                   IconButton(
                    icon: const Icon(Icons.qr_code_2_rounded, color: Colors.white),
                    onPressed: _showClientQrDialog,
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                       // Cover Image or Gradient
                       _coverImage != null
                          ? Image.file(_coverImage!, fit: BoxFit.cover)
                          : Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [AppColors.deepPurple, AppColors.primaryDark],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                            ),
                        // Dark Overlay
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.1),
                                Colors.black.withValues(alpha: 0.4),
                              ],
                            ),
                          ),
                        ),
                        
                        // User Info Centered
                        Align(
                          alignment: Alignment.center,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(height: 40),
                              Stack(
                                alignment: Alignment.bottomRight,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white.withValues(alpha: 0.2),
                                      border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 1)
                                    ),
                                    child: CircleAvatar(
                                      radius: 50,
                                      backgroundColor: Colors.white,
                                      backgroundImage: _profileImage != null ? FileImage(_profileImage!) : null,
                                      child: _profileImage == null
                                          ? const Icon(Icons.person, size: 50, color: AppColors.deepPurple)
                                          : null,
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () => _pickImage(isCover: false),
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: const BoxDecoration(
                                        color: AppColors.accentOrange,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _fullName ?? 'مستخدم نافذة',
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              if (_username != null)
                                Text(
                                  '@$_username',
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 14,
                                    color: Colors.white.withValues(alpha: 0.8),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        
                        // Edit Cover Button
                         Positioned(
                          top: 40,
                          left: 16,
                          child: GestureDetector(
                            onTap: () => _pickImage(isCover: true),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.edit, size: 14, color: Colors.white),
                                  SizedBox(width: 4),
                                  Text(
                                    'غطاء',
                                    style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(30),
                  child: Container(
                    height: 30,
                    decoration: const BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                    ),
                  ),
                ),
              ),
            ];
          },
          body: RefreshIndicator(
            color: AppColors.deepPurple,
            onRefresh: _refreshProfile,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  // Quick Stats
                  _buildQuickStats(),
                  const SizedBox(height: 24),
                  
                  // Account Type Badge
                  _buildAccountTypeBadge(),
                  const SizedBox(height: 24),

                  // Main Action Cards
                  _buildActionGrid(),
                  const SizedBox(height: 18),
                  _buildQuickLinks(),
                  
                  const SizedBox(height: 24),

                  ProfileAccountModesPanel(
                    isProviderRegistered: isProviderRegistered,
                    isProviderActive: RoleController.instance.notifier.value.isProvider,
                    isSwitching: _switchingAccount,
                    onSelectMode: _onSelectMode,
                    onRegisterProvider: () async {
                      if (!await checkFullClient(context)) return;
                      if (!context.mounted) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const RegisterServiceProviderPage(),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: const CustomBottomNav(currentIndex: 3),
      ),
    );
  }

  Widget _buildAccountTypeBadge() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(((isDark ? 0.22 : 0.06) * 255).toInt()),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
           Icon(Icons.verified_user_outlined, color: cs.onSurface.withAlpha((0.70 * 255).toInt()), size: 20),
           const SizedBox(width: 8),
           Text(
             'حساب عميل',
             style: TextStyle(
               fontFamily: 'Cairo',
               fontWeight: FontWeight.bold,
               color: cs.onSurface,
               fontSize: 14
             ),
           ),
           if (_phone != null) ...[
             Container(
               margin: const EdgeInsets.symmetric(horizontal: 12),
               height: 16,
               width: 1,
               color: cs.onSurface.withAlpha((0.18 * 255).toInt()),
             ),
             Text(
               _asLocalSaudiPhone(_phone!),
               style: TextStyle(
                 fontFamily: 'Cairo',
                 color: cs.onSurface.withAlpha((0.70 * 255).toInt()),
                 fontSize: 14
               ),
             ),
           ]
        ],
      ),
    );
  }

  Widget _buildQuickStats() {
    final isProviderAccount = RoleController.instance.notifier.value.isProvider;

    final items = <Widget>[
      _statItem(
        value: _followingCount?.toString() ?? '0',
        label: 'أتابع',
        icon: Icons.person_add_alt_1_rounded,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => InteractiveScreen(
                mode: isProviderAccount ? InteractiveMode.provider : InteractiveMode.client,
                initialTabIndex: 0,
              ),
            ),
          );
        },
      ),
      Container(width: 1, height: 40, color: Colors.grey[300]),
      _statItem(
        value: _likesCount?.toString() ?? '0',
        label: 'مفضلتي',
        icon: Icons.thumb_up_alt_rounded,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => InteractiveScreen(
                mode: isProviderAccount ? InteractiveMode.provider : InteractiveMode.client,
                initialTabIndex: 1,
              ),
            ),
          );
        },
      ),
      Container(width: 1, height: 40, color: Colors.grey[300]),
      _statItem(
        value: '0',
        label: 'نقاطي',
        icon: Icons.star_rounded,
        onTap: () {},
      ),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: items,
    );
  }

  Widget _statItem({required String value, required String label, required IconData icon, VoidCallback? onTap}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.deepPurple.withValues(alpha: theme.brightness == Brightness.dark ? 0.14 : 0.07),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.deepPurple, size: 20),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.softBlue,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                color: cs.onSurface.withAlpha((0.60 * 255).toInt()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionGrid() {
    return ProfileActionCard(
      title: 'الملف الشخصي',
      subtitle: 'إدارة بياناتك وإعدادات الدخول',
      icon: Icons.person_outline_rounded,
      accent: AppColors.deepPurple,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const LoginSettingsScreen()),
        );
      },
    );
  }

  Future<void> _onSelectMode(AccountMode mode) async {
    if (_switchingAccount) return;
    setState(() => _switchingAccount = true);
    try {
      await AccountSwitcher.switchTo(context, mode);
    } finally {
      if (mounted) {
        setState(() => _switchingAccount = false);
      }
    }
  }

  Widget _buildQuickLinks() {
    return ProfileQuickLinksPanel(
      title: 'إعدادات سريعة',
      items: [
        ProfileQuickLinkItem(
          title: 'إعدادات التنبيهات',
          icon: Icons.notifications_outlined,
          onTap: () async {
            final navigator = Navigator.of(context);
            if (!await checkFullClient(context)) return;
            if (!mounted) return;
            navigator.push(
              MaterialPageRoute(builder: (_) => const NotificationSettingsScreen()),
            );
          },
        ),
        ProfileQuickLinkItem(
          title: 'الشروط والأحكام',
          icon: Icons.policy_outlined,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TermsScreen()),
            );
          },
        ),
      ],
    );
  }
}
