import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_theme.dart';
import '../services/account_mode_service.dart';
import '../services/auth_service.dart';
import '../utils/responsive.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/custom_drawer.dart';
import 'contact_screen.dart';
import 'login_screen.dart';
import 'orders_hub_screen.dart';
import 'request_quote_screen.dart';
import 'search_provider_screen.dart';
import 'urgent_request_screen.dart';

class AddServiceScreen extends StatefulWidget {
  const AddServiceScreen({super.key});

  @override
  State<AddServiceScreen> createState() => _AddServiceScreenState();
}

class _AddServiceScreenState extends State<AddServiceScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

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
        const SnackBar(
          content: Text(
            'تم التبديل إلى حساب العميل، ويمكنك الآن متابعة إنشاء الطلب.',
            style: TextStyle(fontFamily: 'Cairo'),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.success,
        ),
      );
  }

  Future<void> _navigateWithAuth(BuildContext context, Widget screen) async {
    final loggedIn = await AuthService.isLoggedIn();
    if (!context.mounted) return;
    if (!loggedIn) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => LoginScreen(redirectTo: screen)),
      );
      return;
    }
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final horizontalPadding = ResponsiveLayout.horizontalPadding(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: isDark ? AppColors.bgDark : const Color(0xFFF6F8FB),
        drawer: const CustomDrawer(),
        bottomNavigationBar: const CustomBottomNav(currentIndex: -1),
        body: SafeArea(
          child: !_accountChecked
              ? const Center(child: CircularProgressIndicator())
              : Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: ResponsiveLayout.contentMaxWidth(context),
                    ),
                    child: CustomScrollView(
                      physics: const BouncingScrollPhysics(),
                      slivers: [
                        SliverToBoxAdapter(
                          child: _TopBar(
                            onMenuTap: () =>
                                _scaffoldKey.currentState?.openDrawer(),
                          ),
                        ),
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            horizontalPadding,
                            8,
                            horizontalPadding,
                            28 + bottomPadding,
                          ),
                          sliver: SliverList(
                            delegate: SliverChildListDelegate(
                              _isProviderMode
                                  ? <Widget>[
                                      _ProviderModeGate(
                                        isSwitching: _switchingToClient,
                                        onSwitch: _switchToClientMode,
                                        onProfile: () => Navigator.pushNamed(
                                          context,
                                          '/profile',
                                        ),
                                      ),
                                    ]
                                  : <Widget>[
                                      _HubHero(
                                        onOrdersTap: () => _navigateWithAuth(
                                          context,
                                          const OrdersHubScreen(),
                                        ),
                                      ),
                                      const SizedBox(height: 22),
                                      const _SectionHead(),
                                      const SizedBox(height: 12),
                                      _RequestPathCard(
                                        icon: Icons.search_rounded,
                                        colors: const [
                                          Color(0xFF673AB7),
                                          Color(0xFF9C6BE6),
                                        ],
                                        title: 'البحث عن مزود خدمة',
                                        subtitle:
                                            'تصفّح المزودين، قارن التقييمات، وابدأ المحادثة بنفسك مباشرة.',
                                        badge: 'طلب مباشر',
                                        chips: const [
                                          _ActionChipSpec(
                                            icon: Icons.place_outlined,
                                            label: 'فلترة جغرافية',
                                          ),
                                          _ActionChipSpec(
                                            icon: Icons.star_outline_rounded,
                                            label: 'تقييمات حقيقية',
                                          ),
                                          _ActionChipSpec(
                                            icon: Icons.chat_bubble_outline,
                                            label: 'محادثة فورية',
                                          ),
                                        ],
                                        onTap: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const SearchProviderScreen(),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      _RequestPathCard(
                                        icon: Icons.bolt_rounded,
                                        colors: const [
                                          Color(0xFFE11D48),
                                          Color(0xFFF97316),
                                        ],
                                        title: 'طلب عاجل',
                                        subtitle:
                                            'إشعار فوري لأقرب المزودين المؤهلين، مع استجابة سريعة خلال دقائق.',
                                        badge: 'الأكثر طلبًا',
                                        badgeWarm: true,
                                        chips: const [
                                          _ActionChipSpec(
                                            icon: Icons.schedule_rounded,
                                            label: 'استجابة فورية',
                                          ),
                                          _ActionChipSpec(
                                            icon: Icons.call_outlined,
                                            label: 'اتصال مباشر',
                                          ),
                                          _ActionChipSpec(
                                            icon: Icons.near_me_outlined,
                                            label: 'أقرب مزود',
                                          ),
                                        ],
                                        onTap: () => _navigateWithAuth(
                                          context,
                                          const UrgentRequestScreen(),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      _RequestPathCard(
                                        icon: Icons.request_quote_rounded,
                                        colors: const [
                                          Color(0xFF2563EB),
                                          Color(0xFF7C3AED),
                                        ],
                                        title: 'طلب عروض أسعار',
                                        subtitle:
                                            'استقبل عدة عروض من مزودين موثوقين، قارنها واختر الأنسب لك.',
                                        badge: 'قارن العروض',
                                        chips: const [
                                          _ActionChipSpec(
                                            icon: Icons.attach_money_rounded,
                                            label: 'أسعار تنافسية',
                                          ),
                                          _ActionChipSpec(
                                            icon: Icons.monitor_heart_outlined,
                                            label: 'مقارنة مرنة',
                                          ),
                                          _ActionChipSpec(
                                            icon: Icons.verified_outlined,
                                            label: 'مزودون موثوقون',
                                          ),
                                        ],
                                        onTap: () => _navigateWithAuth(
                                          context,
                                          const RequestQuoteScreen(),
                                        ),
                                      ),
                                      const SizedBox(height: 22),
                                      _HelpFooterCard(
                                        onTap: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const ContactScreen(),
                                          ),
                                        ),
                                      ),
                                    ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final VoidCallback onMenuTap;

  const _TopBar({required this.onMenuTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(
        children: [
          _IconSurfaceButton(
            icon: Icons.menu_rounded,
            onTap: onMenuTap,
          ),
          const Spacer(),
          Text(
            'طلب خدمة',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : AppTextStyles.textPrimary,
            ),
          ),
          const Spacer(),
          const SizedBox(width: 42),
        ],
      ),
    );
  }
}

class _HubHero extends StatelessWidget {
  final VoidCallback onOrdersTap;

  const _HubHero({required this.onOrdersTap});

  @override
  Widget build(BuildContext context) {
    final compact = ResponsiveLayout.isCompactWidth(context);
    return Container(
      width: double.infinity,
      padding:
          EdgeInsets.fromLTRB(compact ? 18 : 22, 24, compact ? 18 : 22, 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF0B1320),
            Color(0xFF0F1D2E),
            Color(0xFF0C1A2C),
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x453F1D84),
            blurRadius: 34,
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
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
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onOrdersTap,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text(
                  'طلباتي',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const Text(
            'كيف تحب أن نُنجز خدمتك؟',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 26,
              height: 1.25,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'اختر المسار الأنسب لك، كل مسار يفتح نموذج طلب مُخصّص بأقل خطوات ممكنة.',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 14,
              height: 1.75,
              fontWeight: FontWeight.w600,
              color: Color(0xD9FFFFFF),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: const [
              Expanded(child: _HeroStat(value: '3', label: 'مسارات للطلب')),
              SizedBox(width: 10),
              Expanded(
                  child: _HeroStat(value: '~2د', label: 'متوسط وقت الإرسال')),
              SizedBox(width: 10),
              Expanded(
                  child: _HeroStat(value: '24/7', label: 'استقبال الطلبات')),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final String value;
  final String label;

  const _HeroStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 76),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
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
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 10.5,
              height: 1.25,
              fontWeight: FontWeight.w700,
              color: Color(0xCCFFFFFF),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHead extends StatelessWidget {
  const _SectionHead();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            gradient: const LinearGradient(
              colors: [Color(0xFF673AB7), Color(0xFF9C6BE6)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'اختر نوع الطلب',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : AppTextStyles.textPrimary,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : const Color(0x0F0F172A),
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: const Text(
            '3 مسارات',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: AppTextStyles.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _RequestPathCard extends StatelessWidget {
  final IconData icon;
  final List<Color> colors;
  final String title;
  final String subtitle;
  final String badge;
  final bool badgeWarm;
  final List<_ActionChipSpec> chips;
  final VoidCallback onTap;

  const _RequestPathCard({
    required this.icon,
    required this.colors,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.chips,
    required this.onTap,
    this.badgeWarm = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = colors.first;
    final badgeColors =
        badgeWarm ? const [Color(0xFFF59E0B), Color(0xFFF97316)] : colors;

    return Semantics(
      label: '$title. $subtitle',
      button: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: () {
            HapticFeedback.mediumImpact();
            onTap();
          },
          borderRadius: BorderRadius.circular(22),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.cardDark : Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: isDark ? AppColors.borderDark : const Color(0x140F172A),
              ),
              boxShadow: isDark ? null : AppShadows.card,
            ),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: colors,
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                        ),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.26),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Icon(icon, size: 27, color: Colors.white),
                    ),
                    const SizedBox(width: 13),
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
                                  fontSize: 16,
                                  height: 1.25,
                                  fontWeight: FontWeight.w900,
                                  color: isDark
                                      ? Colors.white
                                      : AppTextStyles.textPrimary,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: badgeColors,
                                    begin: Alignment.topRight,
                                    end: Alignment.bottomLeft,
                                  ),
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.pill),
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
                          const SizedBox(height: 5),
                          Text(
                            subtitle,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                              height: 1.6,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? AppTextStyles.textSecondaryDark
                                  : AppTextStyles.textSecondary,
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
                const SizedBox(height: 14),
                Divider(
                  height: 1,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : const Color(0x140F172A),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: chips
                        .map((chip) => _ActionMetaChip(spec: chip))
                        .toList(growable: false),
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

class _ActionChipSpec {
  final IconData icon;
  final String label;

  const _ActionChipSpec({required this.icon, required this.label});
}

class _ActionMetaChip extends StatelessWidget {
  final _ActionChipSpec spec;

  const _ActionMetaChip({required this.spec});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : const Color(0x0B0F172A),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            spec.icon,
            size: 14,
            color: isDark
                ? AppTextStyles.textSecondaryDark
                : AppTextStyles.textSecondary,
          ),
          const SizedBox(width: 5),
          Text(
            spec.label,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: isDark
                  ? AppTextStyles.textSecondaryDark
                  : AppTextStyles.textSecondary,
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
        borderRadius: BorderRadius.circular(22),
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : const Color(0x149C6BE6),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : const Color(0x599C6BE6),
          style: BorderStyle.solid,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 360;
          return Flex(
            direction: compact ? Axis.vertical : Axis.horizontal,
            crossAxisAlignment: compact
                ? CrossAxisAlignment.stretch
                : CrossAxisAlignment.center,
            children: [
              if (!compact) ...[
                const _HelpIcon(),
                const SizedBox(width: 12),
              ],
              Expanded(
                flex: compact ? 0 : 1,
                child: Column(
                  crossAxisAlignment: compact
                      ? CrossAxisAlignment.center
                      : CrossAxisAlignment.start,
                  children: [
                    if (compact) ...[
                      const _HelpIcon(),
                      const SizedBox(height: 10),
                    ],
                    Text(
                      'غير متأكد من المسار المناسب؟',
                      textAlign: compact ? TextAlign.center : TextAlign.start,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: isDark
                            ? AppTextStyles.textPrimaryDark
                            : AppTextStyles.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'تواصل مع فريق الدعم وسنساعدك في اختيار الطريقة الأنسب لاحتياجك.',
                      textAlign: compact ? TextAlign.center : TextAlign.start,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        height: 1.6,
                        color: isDark
                            ? AppTextStyles.textSecondaryDark
                            : AppTextStyles.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: compact ? 0 : 10, height: compact ? 12 : 0),
              OutlinedButton(
                onPressed: onTap,
                style: OutlinedButton.styleFrom(
                  foregroundColor:
                      isDark ? Colors.white : AppTextStyles.textPrimary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  side: BorderSide(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.18)
                        : AppColors.borderLight,
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
          );
        },
      ),
    );
  }
}

class _HelpIcon extends StatelessWidget {
  const _HelpIcon();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : const Color(0x249C6BE6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(Icons.help_outline_rounded, color: AppColors.primary),
    );
  }
}

class _ProviderModeGate extends StatelessWidget {
  final bool isSwitching;
  final VoidCallback onSwitch;
  final VoidCallback onProfile;

  const _ProviderModeGate({
    required this.isSwitching,
    required this.onSwitch,
    required this.onProfile,
  });

  @override
  Widget build(BuildContext context) {
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
            color: Color(0x453F1D84),
            blurRadius: 34,
            offset: Offset(0, 18),
          ),
        ],
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
              height: 1.25,
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
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: isSwitching ? null : onSwitch,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: isSwitching
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
                        fontWeight: FontWeight.w900,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onProfile,
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
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconSurfaceButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _IconSurfaceButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: isDark ? AppColors.cardDark : AppColors.primarySurface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, size: 21, color: AppColors.primary),
        ),
      ),
    );
  }
}
