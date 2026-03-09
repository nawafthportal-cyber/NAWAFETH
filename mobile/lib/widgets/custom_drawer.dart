// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../constants/colors.dart';
import '../constants/app_texts.dart';
import '../screens/home_screen.dart';
import '../screens/login_settings_screen.dart';
import '../screens/terms_screen.dart';
import '../screens/about_screen.dart';
import '../screens/contact_screen.dart';
import '../screens/login_screen.dart';
import '../screens/my_qr_screen.dart';
import '../main.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
import '../services/api_client.dart';
import '../models/user_profile.dart';

class CustomDrawer extends StatefulWidget {
  const CustomDrawer({super.key});

  @override
  State<CustomDrawer> createState() => _CustomDrawerState();
}

class _CustomDrawerState extends State<CustomDrawer> {
  String selectedLanguage = "ar";

  // ── بيانات المستخدم من API ──
  bool _isLoading = true;
  bool _isLoggedIn = false;
  UserProfile? _userProfile;

  // ── حالة العمليات ──
  bool _isLoggingOut = false;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final loggedIn = await AuthService.isLoggedIn();
    if (!loggedIn) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoggedIn = false;
        });
      }
      return;
    }

    final result = await ProfileService.fetchMyProfile();
    if (!mounted) return;

    if (result.isSuccess && result.data != null) {
      setState(() {
        _isLoggedIn = true;
        _userProfile = result.data!;
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoggedIn = true; // عنده توكن لكن ما جا البروفايل
        _isLoading = false;
      });
    }
  }

  /// تسجيل خروج حقيقي — يحذف التوكنات محلياً + يعطّل الـ refresh بالسيرفر
  Future<void> _performLogout() async {
    if (_isLoggingOut) return;
    setState(() => _isLoggingOut = true);

    try {
      // إرسال refresh token للـ backend لتعطيله
      final refreshToken = await AuthService.getRefreshToken();
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await ApiClient.post('/api/accounts/logout/', body: {
          'refresh': refreshToken,
        });
      }
    } catch (_) {
      // حتى لو فشل — نمسح محلياً
    }

    // مسح التوكنات من الجهاز
    await AuthService.logout();

    if (!mounted) return;

    // الانتقال لشاشة تسجيل الدخول
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  /// حذف الحساب — يعطّل الحساب بالسيرفر ثم يسجل خروج
  Future<void> _performDeleteAccount() async {
    if (_isDeleting) return;
    setState(() => _isDeleting = true);

    try {
      final result = await ApiClient.delete('/api/accounts/delete/');

      if (result.isSuccess) {
        await AuthService.logout();
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حذف الحساب بنجاح',
                style: TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.green,
          ),
        );

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
        );
      } else {
        if (!mounted) return;
        setState(() => _isDeleting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ?? 'حدث خطأ أثناء حذف الحساب',
                style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isDeleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('حدث خطأ في الاتصال', style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final themeController = MyThemeController.of(context);
    final isDarkMode = themeController?.themeMode == ThemeMode.dark;

    return Drawer(
      backgroundColor: theme.scaffoldBackgroundColor,
      child: Column(
        children: [
          // ✅ رأس القائمة — بيانات حقيقية من API
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(
              top: 60,
              right: 20,
              left: 20,
              bottom: 20,
            ),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.deepPurple.withValues(alpha: 0.15)
                  : Colors.deepPurple.withValues(alpha: 0.05),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 👤 معلومات المستخدم
                Expanded(
                  child: _isLoading
                      ? const Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isLoggedIn
                                  ? "أهلاً ${_userProfile?.firstName ?? _userProfile?.username ?? 'مستخدم'}"
                                  : "مرحباً بك",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo',
                                color: isDark
                                    ? Colors.white
                                    : AppColors.primaryDark,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _isLoggedIn
                                  ? (_userProfile?.phone ?? '')
                                  : "سجّل الدخول للمتابعة",
                              style: TextStyle(
                                fontSize: 14,
                                fontFamily: 'Cairo',
                                color:
                                    isDark ? Colors.grey[300] : Colors.black54,
                              ),
                            ),
                            if (_isLoggedIn && _userProfile?.isProvider == true)
                              Container(
                                margin: const EdgeInsets.only(top: 6),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color:
                                      Colors.deepPurple.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  '⭐ مقدّم خدمة',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.w600,
                                    color: Colors.deepPurple,
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
                Column(
                  children: [
                    Switch(
                      value: isDarkMode,
                      activeThumbColor: AppColors.primaryDark,
                      onChanged: (val) {
                        final mode = val ? ThemeMode.dark : ThemeMode.light;
                        themeController?.changeTheme(mode);
                      },
                    ),
                    Text(
                      isDarkMode ? "النمط الليلي" : "النمط النهاري",
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'Cairo',
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          Divider(
            height: 1,
            color: isDark ? Colors.grey[700] : const Color(0xFFE0E0E0),
          ),

          // ✅ عناصر القائمة
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
              children: [
                _buildDrawerItem(
                  icon: Icons.home_outlined,
                  label: AppTexts.getText(context, "home"),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const HomeScreen()),
                    );
                  },
                  isDark: isDark,
                ),
                _buildDrawerItem(
                  icon: Icons.settings_outlined,
                  label: AppTexts.getText(context, "settings"),
                  onTap: () {
                    Navigator.pop(context); // إغلاق الـ Drawer
                    Future.delayed(const Duration(milliseconds: 100), () {
                      if (!mounted) return;
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const LoginSettingsScreen(),
                        ),
                      );
                    });
                  },
                  isDark: isDark,
                ),
                _buildDrawerItem(
                  icon: Icons.language,
                  label: AppTexts.getText(context, "language"),
                  onTap: () => _showLanguageDialog(),
                  isDark: isDark,
                ),
                _buildDrawerItem(
                  icon: FontAwesomeIcons.qrcode,
                  label: AppTexts.getText(context, "qr"),
                  onTap: () {
                    Navigator.pop(context);
                    Future.delayed(const Duration(milliseconds: 100), () {
                      if (!mounted) return;
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const MyQrScreen(),
                        ),
                      );
                    });
                  },
                  isDark: isDark,
                ),
                _buildDrawerItem(
                  icon: Icons.article_outlined,
                  label: AppTexts.getText(context, "terms"),
                  onTap: () {
                    Navigator.pop(context); // إغلاق الـ Drawer
                    Future.delayed(const Duration(milliseconds: 100), () {
                      if (!mounted) return;
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const TermsScreen()),
                      );
                    });
                  },
                  isDark: isDark,
                ),
                _buildDrawerItem(
                  icon: Icons.support_agent,
                  label: AppTexts.getText(context, "support"),
                  onTap: () {
                    Navigator.pop(context); // إغلاق الـ Drawer
                    Future.delayed(const Duration(milliseconds: 100), () {
                      if (!mounted) return;
                      Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const ContactScreen()),
                      );
                    });
                  },
                  isDark: isDark,
                ),
                _buildDrawerItem(
                  icon: Icons.info_outline,
                  label: AppTexts.getText(context, "about"),
                  onTap: () {
                    Navigator.pop(context); // إغلاق الـ Drawer
                    Future.delayed(const Duration(milliseconds: 100), () {
                      if (!mounted) return;
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AboutScreen()),
                      );
                    });
                  },
                  isDark: isDark,
                ),
              ],
            ),
          ),

          Divider(
            height: 1,
            color: isDark ? Colors.grey[700] : const Color(0xFFE0E0E0),
          ),

          // ✅ أزرار أسفل
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: _isLoggedIn
                ? Column(
                    children: [
                      _buildActionBtn(
                        text: _isLoggingOut
                            ? 'جارٍ تسجيل الخروج...'
                            : AppTexts.getText(context, "logout"),
                        color: AppColors.primaryDark,
                        onPressed: _isLoggingOut
                            ? () {}
                            : () {
                                _showLogoutConfirmDialog(context);
                              },
                      ),
                      const SizedBox(height: 10),
                      _buildActionBtn(
                        text: _isDeleting
                            ? 'جارٍ الحذف...'
                            : AppTexts.getText(context, "delete"),
                        color: Colors.red.shade600,
                        onPressed: _isDeleting
                            ? () {}
                            : () => _showDeleteConfirmDialog(context),
                      ),
                    ],
                  )
                : _buildActionBtn(
                    text: 'تسجيل الدخول',
                    color: AppColors.primaryDark,
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// ✅ نافذة اختيار اللغة
  void _showLanguageDialog() {
    showDialog(
      context: context,
      builder: (context) {
        final themeController = MyThemeController.of(context);
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            "🌐 اختر اللغة",
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _languageOption("ar", "🇸🇦", "العربية", themeController),
              const SizedBox(height: 10),
              _languageOption("en", "🇺🇸", "English", themeController),
            ],
          ),
        );
      },
    );
  }

  /// ✅ نافذة تأكيد تسجيل الخروج
  void _showLogoutConfirmDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            "تسجيل الخروج",
            style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
            ),
          ),
          content: const Text(
            "هل تريد تسجيل الخروج من حسابك؟",
            style: TextStyle(fontFamily: 'Cairo', fontSize: 14),
          ),
          actions: [
            TextButton(
              child: const Text("إلغاء", style: TextStyle(fontFamily: 'Cairo')),
              onPressed: () => Navigator.pop(ctx),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryDark),
              child: const Text(
                "تسجيل الخروج",
                style: TextStyle(color: Colors.white, fontFamily: 'Cairo'),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                _performLogout();
              },
            ),
          ],
        );
      },
    );
  }

  /// ✅ نافذة تأكيد الحذف
  void _showDeleteConfirmDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            "⚠️ تأكيد حذف الحساب",
            style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),
          content: const Text(
            "ستقوم بحذف حسابك نهائياً، ولن نتمكن من استعادة بياناتك أو طلباتك السابقة.\n\n"
            "هل أنت متأكد أنك تريد المتابعة؟",
            style: TextStyle(fontFamily: 'Cairo', fontSize: 14),
          ),
          actions: [
            TextButton(
              child: const Text("إلغاء", style: TextStyle(fontFamily: 'Cairo')),
              onPressed: () => Navigator.pop(ctx),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text(
                "تأكيد الحذف",
                style: TextStyle(color: Colors.white, fontFamily: 'Cairo'),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                _performDeleteAccount();
              },
            ),
          ],
        );
      },
    );
  }

  Widget _languageOption(
    String code,
    String flag,
    String title,
    MyThemeController? controller,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Text(flag, style: const TextStyle(fontSize: 24)),
        title: Text(title, style: const TextStyle(fontFamily: 'Cairo')),
        trailing: selectedLanguage == code
            ? const Icon(Icons.check_circle, color: Colors.deepPurple)
            : null,
        onTap: () {
          setState(() => selectedLanguage = code);
          Navigator.pop(context);
          if (code == "ar") {
            controller?.changeLanguage(const Locale('ar', 'SA'));
          } else {
            controller?.changeLanguage(const Locale('en', 'US'));
          }
        },
      ),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Icon(
        icon,
        color: isDark ? Colors.white70 : AppColors.primaryDark,
      ),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 16,
          fontFamily: 'Cairo',
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : Colors.black87,
        ),
      ),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      hoverColor: AppColors.primaryDark.withValues(alpha: 0.08),
    );
  }

  Widget _buildActionBtn({
    required String text,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        onPressed: onPressed,
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 15,
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
