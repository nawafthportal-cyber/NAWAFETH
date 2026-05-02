import 'package:flutter/material.dart';
import 'package:nawafeth/services/account_mode_service.dart';
import 'package:nawafeth/services/auth_service.dart';

import '../constants/app_theme.dart';
import 'client_orders_screen.dart';
import 'provider_dashboard/provider_orders_screen.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/platform_top_bar.dart';
import 'login_screen.dart';

class OrdersHubScreen extends StatefulWidget {
  const OrdersHubScreen({super.key});

  @override
  State<OrdersHubScreen> createState() => _OrdersHubScreenState();
}

class _OrdersHubScreenState extends State<OrdersHubScreen> {
  bool _isLoading = true;
  bool _isLoggedIn = false;
  bool _isProviderMode = false;

  @override
  void initState() {
    super.initState();
    _initializeScreen();
  }

  Future<void> _initializeScreen() async {
    final isLoggedIn = await AuthService.isLoggedIn();
    if (!mounted) return;

    if (!isLoggedIn) {
      setState(() {
        _isLoggedIn = false;
        _isProviderMode = false;
        _isLoading = false;
      });
      return;
    }

    final isProvider = await AccountModeService.isProviderMode();
    if (!mounted) return;
    setState(() {
      _isLoggedIn = true;
      _isProviderMode = isProvider;
      _isLoading = false;
    });
  }

  Future<void> _openLogin() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const LoginScreen(redirectTo: OrdersHubScreen()),
      ),
    );
    if (!mounted) return;
    setState(() => _isLoading = true);
    await _initializeScreen();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return const Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Center(
            child: CircularProgressIndicator(color: Colors.deepPurple),
          ),
        ),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? AppColors.bgDark : AppColors.bgLight,
        appBar: PlatformTopBar(
          pageLabel: _isProviderMode ? 'طلبات الخدمة' : 'طلباتي',
          showNotificationAction: false,
          showChatAction: false,
        ),
        bottomNavigationBar: const CustomBottomNav(currentIndex: 1),
        body: !_isLoggedIn
            ? _buildAuthGate(isDark: isDark)
            : _isProviderMode
                ? const ProviderOrdersScreen(embedded: true)
                : const ClientOrdersScreen(embedded: true),
      ),
    );
  }

  Widget _buildAuthGate({required bool isDark}) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            padding: const EdgeInsets.fromLTRB(28, 30, 28, 30),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? const [Color(0xFF1B1730), Color(0xFF231C3D)]
                    : const [Color(0xFFFFFFFF), Color(0xFFF5F0FB)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : const Color(0xFFD9CCF2),
              ),
              boxShadow: isDark
                  ? null
                  : const [
                      BoxShadow(
                        color: Color(0x14673AB7),
                        blurRadius: 28,
                        offset: Offset(0, 14),
                      ),
                    ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : const Color(0x14673AB7),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'طلباتك الشخصية',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: AppTextStyles.micro,
                      fontWeight: FontWeight.w800,
                      color: isDark
                          ? const Color(0xFFE9D9FF)
                          : const Color(0xFF5B21B6),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'سجّل دخولك لعرض طلباتك',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : const Color(0xFF3A1F73),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'يمكنك متابعة حالة الطلبات والتفاصيل بعد تسجيل الدخول.',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.8,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.78)
                        : const Color(0xFF6E5A99),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : const Color(0xFFF8F4FD),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : const Color(0xFFE9DDF8),
                    ),
                  ),
                  child: Text(
                    'حسابك يفتح لك كل تفاصيل الطلب في مكان واحد.',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      height: 1.7,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.82)
                          : AppColors.grey700,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _openLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'تسجيل الدخول',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
