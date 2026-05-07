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
  bool _isLoggedIn = false;
  bool _authStateResolved = false;
  String? _loadError;
  List<OnboardItem> _slides = const [];
  OnboardItem? _appPreviewItem;

  @override
  void initState() {
    super.initState();
    _resolveAuthState();
    _loadContentFromApi();
    _refreshContentInBackground();
  }

  Future<void> _resolveAuthState() async {
    final loggedIn = await AuthService.isLoggedIn();
    if (!mounted) return;
    setState(() {
      _isLoggedIn = loggedIn;
      _authStateResolved = true;
    });
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
          size: 42,
          color: AppColors.primary,
        );
      case 1:
        return const FaIcon(
          FontAwesomeIcons.usersViewfinder,
          size: 38,
          color: AppColors.primary,
        );
      default:
        return const FaIcon(
          FontAwesomeIcons.rocket,
          size: 38,
          color: AppColors.primary,
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
    final isLoggedIn =
        _authStateResolved ? _isLoggedIn : await AuthService.isLoggedIn();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, isLoggedIn ? '/home' : '/login');
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = _isCompactPhone(size);
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.bgLight,
              Color(0xFFFCFAFF),
              AppColors.surfaceLight,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 12.0 : 16.0,
              vertical: compact ? 6.0 : 12.0,
            ),
            child: _buildBody(),
          ),
        ),
      ),
    );
  }

  bool _isCompactPhone(Size size) => size.width < 380 || size.height < 720;

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
        constraints: const BoxConstraints(maxWidth: 460),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: AppColors.borderLight),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.08),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primarySurface, Color(0xFFEAF6F8)],
                ),
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: AppColors.primary,
                size: 28,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: AppTextStyles.h2,
                fontWeight: FontWeight.w800,
                color: AppColors.grey900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: AppTextStyles.bodyMd,
                height: 1.65,
                color: AppColors.grey600,
              ),
            ),
            const SizedBox(height: 16),
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
    final isSmall = _isCompactPhone(size);
    final double titleSize = isSmall ? 15.0 : AppTextStyles.h1;
    final double bodySize = isSmall ? 11.0 : AppTextStyles.bodyMd;
    final double mediaBox = isSmall ? 92.0 : 118.0;
    final double cardPad = isSmall ? 10.0 : 12.0;
    final double gapMedia = isSmall ? 8.0 : 12.0;
    final double gapTitle = isSmall ? 4.0 : 6.0;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 2, vertical: isSmall ? 2 : 6),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 480),
        padding: EdgeInsets.fromLTRB(cardPad, cardPad, cardPad, cardPad - 4),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: AppColors.borderLight),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.08),
              blurRadius: 18,
              offset: const Offset(0, 10),
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
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.primarySurface,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'الشاشة ${_currentPage + 1}',
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: AppTextStyles.caption,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
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
                              fontSize: AppTextStyles.caption,
                              fontWeight: FontWeight.w700,
                              color: AppColors.grey500,
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
                        aspectRatio: 1.16,
                        fallback: Container(
                          width: mediaBox,
                          height: mediaBox,
                          padding: EdgeInsets.all(isSmall ? 18.0 : 24.0),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                AppColors.primarySurface,
                                AppColors.tealSurface,
                                Color(0xFFFFF8EF),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(999),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    AppColors.primary.withValues(alpha: 0.12),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
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
                          color: AppColors.grey900,
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
                          height: 1.7,
                          color: AppColors.grey600,
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
    final isSmall = _isCompactPhone(size);
    final title =
        item.title.trim().isNotEmpty ? item.title.trim() : 'تعرف على نوافذ';
    final body = item.desc.trim().isNotEmpty
        ? item.desc.trim()
        : 'واجهة سريعة وواضحة تساعدك تبدأ مباشرة من التطبيق.';

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 2, vertical: isSmall ? 2 : 6),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 480),
        padding: EdgeInsets.all(isSmall ? 10.0 : 12.0),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: AppColors.borderLight),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.08),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Column(
              children: [
                Row(
                  children: [
                    Text(
                      _isLoggedIn
                          ? 'آخر خطوة قبل الدخول للرئيسية'
                          : 'آخر خطوة قبل تسجيل الدخول',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: AppTextStyles.caption,
                        fontWeight: FontWeight.w700,
                        color: AppColors.grey500,
                      ),
                    ),
                    Spacer(),
                    const _OnboardMetaChip(label: 'بروفة التطبيق'),
                  ],
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: ContentBlockMedia(
                    mediaUrl: item.mediaUrl,
                    mediaType: item.mediaType,
                    isActive: true,
                    borderRadius: 28,
                    aspectRatio: 0.84,
                    imageFit: BoxFit.contain,
                    videoFit: BoxFit.contain,
                    fallback: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.primarySurface,
                            AppColors.tealSurface,
                            Color(0xFFFFF8EF),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(AppRadius.xl),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.smartphone_rounded,
                          color: AppColors.primary,
                          size: 42,
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
                    color: AppColors.primarySurface.withValues(alpha: 0.62),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: AppTextStyles.h3,
                          fontWeight: FontWeight.w800,
                          color: AppColors.grey900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        body,
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: AppTextStyles.bodySm,
                          height: 1.65,
                          color: AppColors.grey600,
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
    final isSmall = _isCompactPhone(size);

    return Padding(
      padding: EdgeInsets.fromLTRB(2, isSmall ? 8 : 14, 2, isSmall ? 4 : 8),
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
                  color: Color(0x2460269E),
                  blurRadius: 14,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              onPressed: _finishOnboarding,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                foregroundColor: Colors.white,
                minimumSize: Size(134, isSmall ? 44 : 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              icon: const Icon(Icons.arrow_forward_rounded),
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _isLoggedIn ? 'الدخول للرئيسية' : 'تسجيل الدخول',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: AppTextStyles.bodyMd,
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
    final isSmall = _isCompactPhone(size);

    return Padding(
      padding: EdgeInsets.fromLTRB(2, isSmall ? 8 : 14, 2, isSmall ? 4 : 8),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              _slides.length,
              (index) => AnimatedContainer(
                duration: const Duration(milliseconds: 320),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: _currentPage == index ? 22 : 8,
                height: 8,
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
          SizedBox(height: isSmall ? 10 : 16),
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
                        blurRadius: 14,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    onPressed: _nextPage,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      minimumSize: Size(134, isSmall ? 44 : 48),
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
                          fontSize: AppTextStyles.bodyMd,
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
        minimumSize: const Size(84, 42),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: const BorderSide(color: Color(0xFFE3D7F6)),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: AppTextStyles.bodyMd,
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: AppTextStyles.caption,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
    );
  }
}
