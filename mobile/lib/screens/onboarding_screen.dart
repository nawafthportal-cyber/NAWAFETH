import 'package:flutter/material.dart';

import '../constants/app_theme.dart';
import '../services/auth_service.dart';
import '../services/onboarding_service.dart';
import '../utils/responsive.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();

  int _currentPage = 0;
  bool _isFinishing = false;

  static const List<_OnboardingPageData> _pages = [
    _OnboardingPageData(
      icon: Icons.dashboard_customize_rounded,
      title: 'كل خدماتك في مكان واحد',
      description:
          'تابع طلباتك، تنبيهاتك، وحسابك بسهولة من تطبيق واحد مصمم لتجربة سريعة وواضحة.',
      colors: [Color(0xFFEFE4FF), Color(0xFFF8F4FF)],
      accent: Color(0xFF60269E),
    ),
    _OnboardingPageData(
      icon: Icons.bolt_rounded,
      title: 'تجربة أسرع وأسهل',
      description:
          'واجهة بسيطة تساعدك على الوصول لما تحتاجه بخطوات قليلة ومن أي جهاز.',
      colors: [Color(0xFFE7F4FF), Color(0xFFF3FAFF)],
      accent: Color(0xFF2563EB),
    ),
    _OnboardingPageData(
      icon: Icons.rocket_launch_rounded,
      title: 'ابدأ رحلتك الآن',
      description:
          'سجّل دخولك واستمتع بتجربة منظمة، آمنة، ومناسبة لاستخدامك اليومي.',
      colors: [Color(0xFFFFF0E5), Color(0xFFFFF8F1)],
      accent: Color(0xFFF08A38),
    ),
  ];

  bool get _isLastPage => _currentPage == _pages.length - 1;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _skip() async {
    if (_isFinishing) return;
    await _finishOnboarding();
  }

  Future<void> _next() async {
    if (_isFinishing) return;
    if (_isLastPage) {
      await _finishOnboarding();
      return;
    }
    await _pageController.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finishOnboarding() async {
    setState(() => _isFinishing = true);
    await OnboardingService.markSeen();
    final isLoggedIn = await AuthService.isLoggedIn();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, isLoggedIn ? '/home' : '/login');
  }

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = ResponsiveLayout.horizontalPadding(context);
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF2A104D),
              Color(0xFF4B168A),
              Color(0xFF1C1137),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: ResponsiveLayout.contentMaxWidth(context),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  10,
                  horizontalPadding,
                  12 + bottomPadding,
                ),
                child: Column(
                  children: [
                    _OnboardingTopBar(
                      showSkip: !_isLastPage,
                      onSkip: _skip,
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: _pages.length,
                        onPageChanged: (index) {
                          if (!mounted) return;
                          setState(() => _currentPage = index);
                        },
                        itemBuilder: (context, index) {
                          return _OnboardingPage(
                            data: _pages[index],
                            isCompact:
                                ResponsiveLayout.isCompactWidth(context) ||
                                    ResponsiveLayout.isSmallHeight(context),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    _OnboardingIndicators(
                      count: _pages.length,
                      currentIndex: _currentPage,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton(
                        onPressed: _isFinishing ? null : _next,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accentOrange,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                        ),
                        child: _isFinishing
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(_isLastPage ? 'ابدأ الآن' : 'التالي'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingTopBar extends StatelessWidget {
  final bool showSkip;
  final VoidCallback onSkip;

  const _OnboardingTopBar({
    required this.showSkip,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(
                Icons.window_rounded,
                size: 17,
                color: Colors.white,
              ),
              SizedBox(width: 8),
              Text(
                'نوافذ',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        if (showSkip)
          Semantics(
            button: true,
            label: 'تخطي شاشة البداية',
            child: TextButton(
              onPressed: onSkip,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white.withValues(alpha: 0.9),
              ),
              child: const Text('تخطي'),
            ),
          ),
      ],
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  final _OnboardingPageData data;
  final bool isCompact;

  const _OnboardingPage({
    required this.data,
    required this.isCompact,
  });

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final veryShort = screenHeight < 680;
    final illustrationHeight = veryShort
        ? 132.0
        : isCompact
            ? 150.0
            : 178.0;
    final iconBox = veryShort
        ? 74.0
        : isCompact
            ? 82.0
            : 96.0;
    final titleSize = veryShort
        ? 21.0
        : isCompact
            ? 23.0
            : 27.0;
    final bodySize = veryShort ? 12.5 : 13.5;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(height: veryShort ? 4 : 10),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Container(
                height: illustrationHeight,
                padding: EdgeInsets.all(veryShort ? 12 : 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.28)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: data.colors,
                          ),
                        ),
                      ),
                    ),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: iconBox,
                            height: iconBox,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(26),
                              gradient: LinearGradient(
                                colors: [
                                  data.accent.withValues(alpha: 0.94),
                                  data.accent.withValues(alpha: 0.72),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: Icon(
                              data.icon,
                              size: veryShort ? 36 : 44,
                              color: Colors.white,
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
          SizedBox(height: veryShort ? 18 : 24),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              children: [
                Text(
                  data.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: titleSize,
                    height: 1.22,
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  data.description,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: bodySize,
                    height: 1.55,
                    color: Colors.white.withValues(alpha: 0.78),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingIndicators extends StatelessWidget {
  final int count;
  final int currentIndex;

  const _OnboardingIndicators({
    required this.count,
    required this.currentIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (index) {
        final isActive = index == currentIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 22 : 7,
          height: 7,
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.accentOrange
                : Colors.white.withValues(alpha: 0.34),
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
        );
      }),
    );
  }
}

class _OnboardingPageData {
  final IconData icon;
  final String title;
  final String description;
  final List<Color> colors;
  final Color accent;

  const _OnboardingPageData({
    required this.icon,
    required this.title,
    required this.description,
    required this.colors,
    required this.accent,
  });
}
