import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../constants/app_theme.dart';
import '../services/api_client.dart';
import '../services/content_service.dart';
import '../services/auth_service.dart';
import '../services/onboarding_service.dart';
import '../widgets/content_block_media.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class OnboardItem {
  final String key;
  final Widget icon;
  final String title;
  final String desc;
  final String? mediaUrl;
  final String mediaType;
  final bool previewOnly;

  const OnboardItem({
    required this.key,
    required this.icon,
    required this.title,
    required this.desc,
    this.mediaUrl,
    this.mediaType = '',
    this.previewOnly = false,
  });
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const List<String> _orderedKeys = [
    'onboarding_first_time',
    'onboarding_intro',
    'onboarding_get_started',
  ];
  static const String _appPreviewKey = 'app_intro_preview';

  final PageController _pageController = PageController();

  int _currentPage = 0;
  bool _showAppPreview = false;
  bool _isLoading = true;
  String? _loadError;
  List<OnboardItem> _slides = const [];
  OnboardItem? _appPreviewItem;

  @override
  void initState() {
    super.initState();
    _loadContentFromApi();
    _refreshContentInBackground();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _refreshContentInBackground() async {
    await _loadContentFromApi(forceRefresh: true, silent: true);
  }

  Future<void> _loadContentFromApi({
    bool forceRefresh = false,
    bool silent = false,
  }) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    try {
      final result =
          await ContentService.fetchPublicContent(forceRefresh: forceRefresh);
      if (!mounted) return;

      if (!result.isSuccess || result.dataAsMap == null) {
        final fallbackSlides = _fallbackSlides();
        setState(() {
          _isLoading = false;
          _slides = fallbackSlides;
          _loadError = fallbackSlides.isEmpty
              ? result.error ?? 'تعذر تحميل شاشة البداية من الخادم.'
              : null;
        });
        return;
      }

      final blocks =
          (result.dataAsMap!['blocks'] as Map<String, dynamic>?) ?? {};
      final slides = <OnboardItem>[];

      for (var index = 0; index < _orderedKeys.length; index++) {
        final key = _orderedKeys[index];
        final block = blocks[key];
        if (block is! Map<String, dynamic>) continue;

        final slide = _buildApiItem(
          key: key,
          block: block,
          index: index,
        );
        if (slide != null) {
          slides.add(slide);
        }
      }

      final previewBlock = blocks[_appPreviewKey];
      OnboardItem? appPreviewItem;
      if (previewBlock is Map<String, dynamic>) {
        appPreviewItem = _buildAppPreviewItem(previewBlock);
      }

      final resolvedSlides = slides.isEmpty ? _fallbackSlides() : slides;
      setState(() {
        _slides = resolvedSlides;
        _appPreviewItem = appPreviewItem;
        _currentPage = 0;
        _showAppPreview = false;
        _isLoading = false;
        _loadError = null;
      });
    } catch (_) {
      if (!mounted) return;
      final fallbackSlides = _fallbackSlides();
      setState(() {
        _isLoading = false;
        _slides = fallbackSlides;
        _loadError = fallbackSlides.isEmpty
            ? 'تعذر تحميل شاشة البداية من الخادم.'
            : null;
      });
    }
  }

  List<OnboardItem> _fallbackSlides() {
    return [
      OnboardItem(
        key: 'fallback_discover',
        icon: _iconForIndex(0),
        title: 'اكتشف الخدمات بسرعة',
        desc:
            'تصفّح التصنيفات والمختصين من شاشة مهيأة للموبايل مع وصول أسرع للمحتوى المهم.',
      ),
      OnboardItem(
        key: 'fallback_secure',
        icon: _iconForIndex(1),
        title: 'دخول آمن وسلس',
        desc:
            'استخدم رقم الجوال ورمز التحقق لإتمام الدخول بسرعة مع الحفاظ على الجلسة بشكل آمن.',
      ),
      OnboardItem(
        key: 'fallback_start',
        icon: _iconForIndex(2),
        title: 'ابدأ من آخر نسخة محفوظة',
        desc:
            'التطبيق يعرض المحتوى المخزن محلياً مباشرة ثم يحدّثه عند توفر الاتصال.',
      ),
    ];
  }

  OnboardItem? _buildApiItem({
    required String key,
    required Map<String, dynamic> block,
    required int index,
  }) {
    final title = (block['title_ar'] as String?)?.trim() ?? '';
    final body = (block['body_ar'] as String?)?.trim() ?? '';
    if (title.isEmpty || body.isEmpty) {
      return null;
    }

    final mediaUrl = ApiClient.buildMediaUrl(block['media_url']?.toString());
    final mediaType = (block['media_type'] as String?)?.trim() ?? '';

    return OnboardItem(
      key: key,
      icon: _iconForIndex(index),
      title: title,
      desc: body,
      mediaUrl: (mediaUrl ?? '').isNotEmpty ? mediaUrl : null,
      mediaType: mediaType,
    );
  }

  OnboardItem? _buildAppPreviewItem(Map<String, dynamic> block) {
    final title = (block['title_ar'] as String?)?.trim() ?? '';
    final body = (block['body_ar'] as String?)?.trim() ?? '';
    final mediaUrl = ApiClient.buildMediaUrl(block['media_url']?.toString());
    final mediaType = (block['media_type'] as String?)?.trim() ?? '';
    if (title.isEmpty && body.isEmpty && (mediaUrl ?? '').isEmpty) {
      return null;
    }

    return OnboardItem(
      key: _appPreviewKey,
      icon: const SizedBox.shrink(),
      title: title,
      desc: body,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      previewOnly: true,
    );
  }

  Widget _iconForIndex(int index) {
    switch (index) {
      case 0:
        return const Icon(
          Icons.widgets_rounded,
          size: 56,
          color: AppColors.deepPurple,
        );
      case 1:
        return const FaIcon(
          FontAwesomeIcons.usersViewfinder,
          size: 52,
          color: AppColors.deepPurple,
        );
      default:
        return const FaIcon(
          FontAwesomeIcons.rocket,
          size: 52,
          color: AppColors.deepPurple,
        );
    }
  }

  void _nextPage() {
    if (_currentPage < _slides.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
      );
      return;
    }
    if (_appPreviewItem != null) {
      setState(() => _showAppPreview = true);
      return;
    }
    _finishOnboarding();
  }

  Future<void> _finishOnboarding() async {
    await OnboardingService.markSeen();
    final isLoggedIn = await AuthService.isLoggedIn();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, isLoggedIn ? '/home' : '/login');
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF8F2FF),
              Color(0xFFFDFBFF),
              Colors.white,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: (size.width * 0.052).clamp(14.0, 24.0),
              vertical: size.height < 700 ? 8.0 : 16.0,
            ),
            child: _buildBody(),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return _buildStatusCard(
        title: 'جاري تحميل شاشة البداية',
        message: 'يتم جلب المحتوى مباشرة من لوحة التحكم.',
        footer: const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      );
    }

    if (_loadError != null) {
      return _buildStatusCard(
        title: 'تعذر عرض شاشة البداية',
        message: _loadError!,
        footer: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildGhostButton(
                label: 'إعادة المحاولة',
                onPressed: () => _loadContentFromApi(forceRefresh: true)),
            const SizedBox(height: 10),
            TextButton(
              onPressed: _finishOnboarding,
              child: const Text(
                'الدخول للرئيسية',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: _showAppPreview
              ? _buildStandaloneAppPreview(_appPreviewItem!)
              : PageView.builder(
                  controller: _pageController,
                  itemCount: _slides.length,
                  onPageChanged: (index) {
                    setState(() => _currentPage = index);
                  },
                  itemBuilder: (context, index) {
                    final item = _slides[index];
                    return _buildPage(
                        item: item, isActive: index == _currentPage);
                  },
                ),
        ),
        _showAppPreview ? _buildAppPreviewControls() : _buildBottomControls(),
      ],
    );
  }

  Widget _buildStatusCard({
    required String title,
    required String message,
    required Widget footer,
  }) {
    return Center(
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: const Color(0xFFE8DBFF)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 34,
              offset: Offset(0, 22),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFF2E9FF), Color(0xFFE7DCFF)],
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: AppColors.deepPurple,
                size: 40,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF24163C),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 15,
                height: 1.8,
                color: Color(0xFF6F6482),
              ),
            ),
            const SizedBox(height: 20),
            footer,
          ],
        ),
      ),
    );
  }

  Widget _buildPage({
    required OnboardItem item,
    required bool isActive,
  }) {
    final size = MediaQuery.sizeOf(context);
    final sw = size.width;
    final sh = size.height;
    final isSmall = sh < 700;
    final double titleSize = (sw * 0.046).clamp(14.0, 18.0);
    final double bodySize = (sw * 0.034).clamp(11.0, 13.0);
    final double mediaBox = (sh * 0.18).clamp(90.0, 140.0);
    final double cardPad = isSmall ? 10.0 : 14.0;
    final double gapMedia = isSmall ? 8.0 : 14.0;
    final double gapTitle = isSmall ? 4.0 : 8.0;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 4, vertical: isSmall ? 4 : 8),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 560),
        padding: EdgeInsets.fromLTRB(cardPad, cardPad, cardPad, cardPad - 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: const Color(0xFFE8DBFF)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F6A3FB1),
              blurRadius: 40,
              offset: Offset(0, 24),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5EEFF),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'الشاشة ${_currentPage + 1}',
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.deepPurple,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _currentPage >= _slides.length - 1
                                ? 'جاهز للانطلاق'
                                : 'جولة تعريفية سريعة',
                            textAlign: TextAlign.end,
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF7B678F),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: isSmall ? 8 : 14),
                    BounceInDown(
                      child: ContentBlockMedia(
                        mediaUrl: item.mediaUrl,
                        mediaType: item.mediaType,
                        isActive: isActive,
                        borderRadius: 28,
                        aspectRatio: 1.04,
                        fallback: Container(
                          width: mediaBox,
                          height: mediaBox,
                          padding: EdgeInsets.all(isSmall ? 18.0 : 26.0),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFFF4EDFF),
                                Color(0xFFECE3FF),
                                Color(0xFFEAF2FF),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(999),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.deepPurple
                                    .withValues(alpha: 0.16),
                                blurRadius: 30,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: Center(child: item.icon),
                        ),
                      ),
                    ),
                    SizedBox(height: gapMedia),
                    FadeInUp(
                      delay: const Duration(milliseconds: 180),
                      child: Text(
                        item.title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: titleSize,
                          fontWeight: FontWeight.w800,
                          height: 1.35,
                          color: const Color(0xFF24163C),
                        ),
                      ),
                    ),
                    SizedBox(height: gapTitle),
                    FadeInUp(
                      delay: const Duration(milliseconds: 320),
                      child: Text(
                        item.desc,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: bodySize,
                          height: 1.85,
                          color: const Color(0xFF6F6482),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildStandaloneAppPreview(OnboardItem item) {
    final size = MediaQuery.sizeOf(context);
    final sh = size.height;
    final isSmall = sh < 700;
    final title =
        item.title.trim().isNotEmpty ? item.title.trim() : 'تعرف على نوافذ';
    final body = item.desc.trim().isNotEmpty
        ? item.desc.trim()
        : 'واجهة سريعة وواضحة تساعدك تبدأ مباشرة من التطبيق.';

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 4, vertical: isSmall ? 4 : 8),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 560),
        padding: EdgeInsets.all(isSmall ? 10.0 : 14.0),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: const Color(0xFFE8DBFF)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F6A3FB1),
              blurRadius: 40,
              offset: Offset(0, 24),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Column(
              children: [
                Row(
                  children: const [
                    Text(
                      'آخر خطوة قبل تسجيل الدخول',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF7B678F),
                      ),
                    ),
                    Spacer(),
                    _OnboardMetaChip(label: 'بروفة التطبيق'),
                  ],
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: ContentBlockMedia(
                    mediaUrl: item.mediaUrl,
                    mediaType: item.mediaType,
                    isActive: true,
                    borderRadius: 28,
                    aspectRatio: 0.78,
                    imageFit: BoxFit.contain,
                    videoFit: BoxFit.contain,
                    fallback: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFFF4EDFF),
                            Color(0xFFECE3FF),
                            Color(0xFFEAF2FF),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.smartphone_rounded,
                          color: AppColors.deepPurple,
                          size: 54,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9F4FF),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE8DBFF)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF24163C),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        body,
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          height: 1.75,
                          color: Color(0xFF6F6482),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildAppPreviewControls() {
    final size = MediaQuery.sizeOf(context);
    final isSmall = size.height < 700;

    return Padding(
      padding: EdgeInsets.fromLTRB(4, isSmall ? 10 : 18, 4, isSmall ? 6 : 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.deepPurple, Color(0xFF7E53C4)],
              ),
              borderRadius: BorderRadius.circular(999),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x336A3FB1),
                  blurRadius: 18,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              onPressed: _finishOnboarding,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                foregroundColor: Colors.white,
                minimumSize: Size(148, isSmall ? 48 : 54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'تسجيل الدخول',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    final size = MediaQuery.sizeOf(context);
    final isSmall = size.height < 700;

    return Padding(
      padding: EdgeInsets.fromLTRB(4, isSmall ? 10 : 18, 4, isSmall ? 6 : 10),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              _slides.length,
              (index) => AnimatedContainer(
                duration: const Duration(milliseconds: 320),
                margin: const EdgeInsets.symmetric(horizontal: 5),
                width: _currentPage == index ? 28 : 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _currentPage == index
                      ? AppColors.deepPurple
                      : const Color(0xFFD9D0E7),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: _currentPage == index
                      ? [
                          BoxShadow(
                            color: AppColors.deepPurple.withValues(alpha: 0.28),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : const [],
                ),
              ),
            ),
          ),
          SizedBox(height: isSmall ? 14 : 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildGhostButton(label: 'تخطي', onPressed: _finishOnboarding),
              Flexible(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.deepPurple, Color(0xFF7E53C4)],
                    ),
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x336A3FB1),
                        blurRadius: 18,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    onPressed: _nextPage,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      minimumSize: Size(148, isSmall ? 48 : 54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    icon: Icon(
                      _currentPage == _slides.length - 1
                          ? Icons.check_rounded
                          : Icons.arrow_forward_rounded,
                    ),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _currentPage == _slides.length - 1
                            ? 'ابدأ الآن'
                            : 'التالي',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGhostButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF7B678F),
        minimumSize: const Size(96, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: const BorderSide(color: Color(0xFFE3D7F6)),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _OnboardMetaChip extends StatelessWidget {
  final String label;

  const _OnboardMetaChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF5EEFF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.deepPurple,
        ),
      ),
    );
  }
}
