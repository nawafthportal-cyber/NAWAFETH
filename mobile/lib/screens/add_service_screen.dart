import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_theme.dart';
import '../services/account_mode_service.dart';
import '../services/auth_service.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/custom_drawer.dart';
import 'contact_screen.dart';
import 'orders_hub_screen.dart';
import 'search_provider_screen.dart';
import 'urgent_request_screen.dart';
import 'request_quote_screen.dart';
import 'login_screen.dart';

class AddServiceScreen extends StatefulWidget {
  const AddServiceScreen({super.key});

  @override
  State<AddServiceScreen> createState() => _AddServiceScreenState();
}

class _AddServiceScreenState extends State<AddServiceScreen> {
  bool _accountChecked = false;
  bool _isProviderMode = false;
  bool _switchingToClient = false;

  @override
  void initState() {
    super.initState();
    _loadAccountMode();
  }

  Future<void> _loadAccountMode() async {
    final isProviderMode = await AccountModeService.isProviderMode();
    if (!mounted) return;
    setState(() {
      _isProviderMode = isProviderMode;
      _accountChecked = true;
    });
  }

  Future<void> _switchToClientMode() async {
    if (_switchingToClient) return;
    setState(() => _switchingToClient = true);
    await AccountModeService.setProviderMode(false);
    if (!mounted) return;
    setState(() {
      _isProviderMode = false;
      _switchingToClient = false;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text(
            'تم التبديل إلى حساب العميل، ويمكنك الآن متابعة إنشاء الطلب.',
            style: TextStyle(fontFamily: 'Cairo'),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.green,
        ),
      );
  }

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

    final serviceOptions = <Widget>[
      _buildSectionHead(context),
      const SizedBox(height: 12),
      _ActionCard(
        icon: Icons.search_rounded,
        gradient: const LinearGradient(
          colors: [AppColors.primaryDark, AppColors.primaryLight],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        title: 'البحث عن مزود خدمة',
        subtitle: 'تصفّح المزودين، قارن التقييمات، وابدأ المحادثة بنفسك مباشرة.',
        badge: 'طلب مباشر',
        chips: const [
          _ActionChipSpec(icon: Icons.place_outlined, label: 'فلترة جغرافية'),
          _ActionChipSpec(icon: Icons.star_outline_rounded, label: 'تقييمات حقيقية'),
          _ActionChipSpec(icon: Icons.chat_bubble_outline_rounded, label: 'محادثة فورية'),
        ],
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SearchProviderScreen()),
        ),
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
        subtitle: 'إشعار فوري لأقرب المزودين المؤهلين، مع استجابة سريعة خلال دقائق.',
        badge: 'الأكثر طلبًا',
        isHighlightedBadge: true,
        chips: const [
          _ActionChipSpec(icon: Icons.schedule_rounded, label: 'استجابة فورية'),
          _ActionChipSpec(icon: Icons.call_outlined, label: 'اتصال مباشر'),
          _ActionChipSpec(icon: Icons.near_me_outlined, label: 'أقرب مزود'),
        ],
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
        subtitle: 'استقبل عدة عروض من مزودين موثوقين، قارنها واختر الأنسب لك.',
        badge: 'قارن العروض',
        chips: const [
          _ActionChipSpec(icon: Icons.attach_money_rounded, label: 'أسعار تنافسية'),
          _ActionChipSpec(icon: Icons.monitor_heart_outlined, label: 'مقارنة مرنة'),
          _ActionChipSpec(icon: Icons.verified_outlined, label: 'مزودون موثوقون'),
        ],
        onTap: () => _navigateWithAuth(context, const RequestQuoteScreen()),
      ),
      const SizedBox(height: 20),
      _HelpFooterCard(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ContactScreen()),
        ),
      ),
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? AppColors.bgDark : AppColors.bgLight,
        drawer: const CustomDrawer(),
        bottomNavigationBar: const CustomBottomNav(currentIndex: -1),
        body: SafeArea(
          child: !_accountChecked
              ? const Center(child: CircularProgressIndicator())
              : CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(child: _buildHeader(context)),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate(
                          _isProviderMode
                              ? <Widget>[_buildProviderModeGate(context)]
                              : serviceOptions,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildProviderModeGate(BuildContext context) {
    final switchChild = _switchingToClient
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
        : const Text(
            'التبديل إلى عميل',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.w800,
            ),
          );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          colors: [Color(0xFF0B1320), Color(0xFF0F1D2E), Color(0xFF0C1A2C)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x734A2D8F),
            blurRadius: 36,
            offset: Offset(0, 18),
          ),
        ],
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: Column(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: const Icon(
              Icons.work_rounded,
              color: Color(0xFFC7F7EE),
              size: 30,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'إنشاء الطلبات متاح في وضع العميل',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'أنت تستخدم المنصة الآن بوضع مقدم الخدمة، لذلك تم إيقاف مسارات طلب الخدمات الجديدة حتى لا تختلط أدوات المزود بمسارات العميل.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 14,
              height: 1.8,
              fontWeight: FontWeight.w700,
              color: Color(0xD1F8FAFC),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'بدّل نوع الحساب إلى عميل الآن، ثم ستظهر لك جميع مسارات الطلب مباشرة في نفس الصفحة.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12.5,
              height: 1.8,
              color: Color(0xB8F8FAFC),
            ),
          ),
          const SizedBox(height: 18),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                onPressed: _switchingToClient ? null : _switchToClientMode,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: switchChild,
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () => Navigator.pushNamed(context, '/profile'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.24)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'فتح نافذتي',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ],
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
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0B1320), Color(0xFF0F1D2E), Color(0xFF0C1A2C)],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x734A2D8F),
                      blurRadius: 36,
                      offset: Offset(0, 18),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF4ADE80),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'جاهز لاستقبال طلبك',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () => _navigateWithAuth(context, const OrdersHubScreen()),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.arrow_back_rounded, size: 16),
                          label: const Text(
                            'طلباتي',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'كيف تحب أن نُنجز خدمتك؟',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'اختر المسار الأنسب لك — كل مسار يفتح نموذج طلب مُخصّص بأقل خطوات ممكنة.',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 14,
                        height: 1.75,
                        color: Color(0xD1F8FAFC),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: const [
                        Expanded(
                          child: _HeroStatCard(value: '3', label: 'مسارات للطلب'),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: _HeroStatCard(value: '~2د', label: 'متوسط وقت الإرسال'),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: _HeroStatCard(value: '24/7', label: 'استقبال الطلبات'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
        ],
      ),
    );
  }

      Widget _buildSectionHead(BuildContext context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 18,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      gradient: const LinearGradient(
                        colors: [AppColors.primaryDark, AppColors.primaryLight],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'اختر نوع الطلب',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: isDark ? AppTextStyles.textPrimaryDark : AppTextStyles.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0x0F0F172A),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '3 مسارات',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: isDark ? AppTextStyles.textSecondaryDark : AppTextStyles.textSecondary,
                ),
              ),
            ),
          ],
        );
      }
}

    class _HeroStatCard extends StatelessWidget {
      final String value;
      final String label;

      const _HeroStatCard({required this.value, required this.label});

      @override
      Widget build(BuildContext context) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: Column(
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xC7FFFFFF),
                ),
              ),
            ],
          ),
        );
      }
    }

    class _ActionChipSpec {
      final IconData icon;
      final String label;

      const _ActionChipSpec({required this.icon, required this.label});
    }

// ─── Action Card Widget ──────────────────────────────────────────────────────

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final Gradient gradient;
  final String title;
  final String subtitle;
      final String badge;
      final bool isHighlightedBadge;
      final List<_ActionChipSpec> chips;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.gradient,
    required this.title,
    required this.subtitle,
        required this.badge,
        this.isHighlightedBadge = false,
        this.chips = const [],
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final linearGradient = gradient as LinearGradient;
    final badgeGradient = isHighlightedBadge
        ? const LinearGradient(
            colors: [Color(0xFFF59E0B), Color(0xFFF97316)],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          )
        : linearGradient;

    return Semantics(
      label: '$title. $subtitle',
      button: true,
      child: Material(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        color: Colors.transparent,
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
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        gradient: linearGradient,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: linearGradient.colors.first.withValues(alpha: 0.30),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Icon(icon, size: 26, color: Colors.white),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                title,
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: AppTextStyles.h3,
                                  fontWeight: FontWeight.w900,
                                  color: isDark
                                      ? AppTextStyles.textPrimaryDark
                                      : AppTextStyles.textPrimary,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  gradient: badgeGradient,
                                  borderRadius: BorderRadius.circular(AppRadius.pill),
                                ),
                                child: Text(
                                  badge,
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? AppTextStyles.textSecondaryDark
                                  : AppTextStyles.textSecondary,
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : const Color(0x0F0F172A),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 14,
                        color: AppTextStyles.textSecondary,
                      ),
                    ),
                  ],
                ),
                if (chips.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    height: 1,
                    color: isDark ? Colors.white.withValues(alpha: 0.08) : AppColors.borderLight,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: chips
                        .map(
                          (chip) => _ActionMetaChip(spec: chip, isDark: isDark),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionMetaChip extends StatelessWidget {
  final _ActionChipSpec spec;
  final bool isDark;

  const _ActionMetaChip({required this.spec, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0x0B0F172A),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            spec.icon,
            size: 14,
            color: isDark ? AppTextStyles.textSecondaryDark : AppTextStyles.textSecondary,
          ),
          const SizedBox(width: 5),
          Text(
            spec.label,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: isDark ? AppTextStyles.textSecondaryDark : AppTextStyles.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _HelpFooterCard extends StatelessWidget {
  final VoidCallback onTap;

  const _HelpFooterCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0x14B794F4),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0x59B794F4),
          style: BorderStyle.solid,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0x24B794F4),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.help_outline_rounded, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'غير متأكد من المسار المناسب؟',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: isDark ? AppTextStyles.textPrimaryDark : AppTextStyles.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'تواصل مع فريق الدعم وسنساعدك في اختيار الطريقة الأنسب لاحتياجك.',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    height: 1.6,
                    color: isDark ? AppTextStyles.textSecondaryDark : AppTextStyles.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              foregroundColor: isDark ? Colors.white : AppTextStyles.textPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              side: BorderSide(
                color: isDark ? Colors.white.withValues(alpha: 0.18) : AppColors.borderLight,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'المساعدة',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Action Card Widget ──────────────────────────────────────────────────────
