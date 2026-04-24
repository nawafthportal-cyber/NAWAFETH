import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_theme.dart';
import '../services/auth_service.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/custom_drawer.dart';
import 'search_provider_screen.dart';
import 'urgent_request_screen.dart';
import 'request_quote_screen.dart';
import 'login_screen.dart';

class AddServiceScreen extends StatelessWidget {
  const AddServiceScreen({super.key});

  Future<void> _navigateWithAuth(BuildContext ctx, Widget screen) async {
    final loggedIn = await AuthService.isLoggedIn();
    if (!ctx.mounted) return;
    if (!loggedIn) {
      Navigator.push(ctx, MaterialPageRoute(builder: (_) => LoginScreen(redirectTo: screen)));
    } else {
      Navigator.push(ctx, MaterialPageRoute(builder: (_) => screen));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? AppColors.bgDark : AppColors.bgLight,
        drawer: const CustomDrawer(),
        bottomNavigationBar: const CustomBottomNav(currentIndex: -1),
        body: SafeArea(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _buildHeader(context)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _ActionCard(
                      icon: Icons.search_rounded,
                      gradient: const LinearGradient(
                        colors: [AppColors.primaryDark, AppColors.primaryLight],
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                      ),
                      title: 'البحث عن مزود خدمة',
                      subtitle: 'استعرض مزودي الخدمات حسب الموقع والتخصص واختر الأنسب لاحتياجك.',
                      tag: 'ابدأ البحث',
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const SearchProviderScreen())),
                    ),
                    const SizedBox(height: 12),
                    _ActionCard(
                      icon: Icons.bolt_rounded,
                      gradient: LinearGradient(
                        colors: [AppColors.warning, AppColors.accent],
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                      ),
                      title: 'طلب خدمة عاجلة',
                      subtitle: 'أرسل طلبًا عاجلًا وسيتم إشعار المزودين المتاحين في منطقتك فورًا.',
                      tag: 'طلب عاجل',
                      onTap: () => _navigateWithAuth(context, const UrgentRequestScreen()),
                    ),
                    const SizedBox(height: 12),
                    _ActionCard(
                      icon: Icons.request_quote_rounded,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0E7490), Color(0xFF0EA5A0)],
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                      ),
                      title: 'طلب عروض أسعار',
                      subtitle: 'صف خدمتك وانتظر عروضًا متعددة من مزودين متنافسين واختر الأفضل.',
                      tag: 'طلب عرض',
                      onTap: () => _navigateWithAuth(context, const RequestQuoteScreen()),
                    ),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [AppColors.cardDark, AppColors.bgDark]
              : [AppColors.primarySurface, AppColors.bgLight],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top bar
          Row(
            children: [
              GestureDetector(
                onTap: () => Scaffold.of(context).openDrawer(),
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: const Icon(Icons.menu_rounded, size: 18, color: AppColors.primary),
                ),
              ),
              const Spacer(),
              Text(
                'إضافة خدمة',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: AppTextStyles.h2,
                  fontWeight: FontWeight.w800,
                  color: isDark ? AppTextStyles.textPrimaryDark : AppTextStyles.textPrimary,
                ),
              ),
              const Spacer(),
              const SizedBox(width: 32),
            ],
          ),
          const SizedBox(height: 22),

          Text(
            'مرحباً بك في نوافذ!',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: AppTextStyles.display2,
              fontWeight: FontWeight.w900,
              color: isDark ? AppTextStyles.textPrimaryDark : AppTextStyles.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'اختر نوع الخدمة التي ترغب بطلبها:',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: AppTextStyles.bodyMd,
              fontWeight: FontWeight.w600,
              color: isDark ? AppTextStyles.textSecondaryDark : AppTextStyles.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ─── Action Card Widget ──────────────────────────────────────────────────────

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final Gradient gradient;
  final String title;
  final String subtitle;
  final String tag;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.gradient,
    required this.title,
    required this.subtitle,
    required this.tag,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      label: '$title. $subtitle',
      button: true,
      child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.xl),
      child: InkWell(
        onTap: () {
          HapticFeedback.mediumImpact();
          onTap();
        },
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: isDark ? AppColors.cardDark : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(color: isDark ? AppColors.borderDark : AppColors.borderLight),
            boxShadow: isDark ? [] : AppShadows.card,
          ),
          child: Row(
            children: [
              // Gradient icon box
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: gradient,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  boxShadow: [
                    BoxShadow(
                      color: (gradient as LinearGradient)
                          .colors
                          .first
                          .withValues(alpha: 0.30),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Icon(icon, size: 24, color: Colors.white),
              ),
              const SizedBox(width: 14),

              // Text block
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: AppTextStyles.h3,
                        fontWeight: FontWeight.w900,
                        color: isDark ? AppTextStyles.textPrimaryDark : AppTextStyles.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: AppTextStyles.caption,
                        fontWeight: FontWeight.w500,
                        color: isDark ? AppTextStyles.textSecondaryDark : AppTextStyles.textSecondary,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // CTA tag
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        gradient: gradient,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            tag,
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: AppTextStyles.caption,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 5),
                          const Icon(Icons.arrow_back_ios_new_rounded,
                              size: 9, color: Colors.white),
                        ],
                      ),
                    ),
                  ],
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

// ─── Action Card Widget ──────────────────────────────────────────────────────
