import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../constants/colors.dart';
import '../services/api_client.dart';
import '../services/content_service.dart';
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

  const OnboardItem({
    required this.key,
    required this.icon,
    required this.title,
    required this.desc,
    this.mediaUrl,
    this.mediaType = '',
  });
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const List<String> _orderedKeys = [
    'onboarding_first_time',
    'onboarding_intro',
    'onboarding_get_started',
  ];

  final PageController _pageController = PageController();

  int _currentPage = 0;
  bool _isLoading = true;
  String? _loadError;
  List<OnboardItem> _slides = const [];

  @override
  void initState() {
    super.initState();
    _loadContentFromApi();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadContentFromApi() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final result = await ContentService.fetchPublicContent(forceRefresh: true);
      if (!mounted) return;

      if (!result.isSuccess || result.dataAsMap == null) {
        setState(() {
          _isLoading = false;
          _loadError = result.error ?? 'تعذر تحميل شاشة البداية من الخادم.';
        });
        return;
      }

      final blocks = (result.dataAsMap!['blocks'] as Map<String, dynamic>?) ?? {};
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

      setState(() {
        _slides = slides;
        _currentPage = 0;
        _isLoading = false;
        _loadError = slides.isEmpty
            ? 'محتوى شاشة البداية غير مُعد في لوحة التحكم.'
            : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'تعذر تحميل شاشة البداية من الخادم.';
      });
    }
  }

  OnboardItem? _buildApiItem({
    required String key,
    required Map<String, dynamic> block,
    required int index,
  }) {
    final title = (block['title_ar'] as String?)?.trim() ?? '';
    final body = (block['body_ar'] as String?)?.trim() ?? '';
    if (title.isEmpty && body.isEmpty) {
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

  Widget _iconForIndex(int index) {
    switch (index) {
      case 0:
        return const Icon(
          Icons.widgets_rounded,
          size: 78,
          color: AppColors.deepPurple,
        );
      case 1:
        return const FaIcon(
          FontAwesomeIcons.usersViewfinder,
          size: 72,
          color: AppColors.deepPurple,
        );
      default:
        return const FaIcon(
          FontAwesomeIcons.rocket,
          size: 72,
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
    _finishOnboarding();
  }

  void _finishOnboarding() {
    Navigator.pushReplacementNamed(context, '/home');
  }

  @override
  Widget build(BuildContext context) {
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
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
            _buildGhostButton(label: 'إعادة المحاولة', onPressed: _loadContentFromApi),
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
          child: PageView.builder(
            controller: _pageController,
            itemCount: _slides.length,
            onPageChanged: (index) {
              setState(() => _currentPage = index);
            },
            itemBuilder: (context, index) {
              final item = _slides[index];
              return _buildPage(item: item, isActive: index == _currentPage);
            },
          ),
        ),
        _buildBottomControls(),
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
                fontSize: 24,
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
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
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5EEFF),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '0${_currentPage + 1} / ${_slides.length}',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.deepPurple,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: Column(
                children: [
                  BounceInDown(
                    child: ContentBlockMedia(
                      mediaUrl: item.mediaUrl,
                      mediaType: item.mediaType,
                      isActive: isActive,
                      borderRadius: 28,
                      aspectRatio: 1.02,
                      fallback: Container(
                        width: 188,
                        height: 188,
                        padding: const EdgeInsets.all(28),
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
                              color: AppColors.deepPurple.withValues(alpha: 0.16),
                              blurRadius: 30,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Center(child: item.icon),
                      ),
                    ),
                  ),
                  const Spacer(),
                  FadeInUp(
                    delay: const Duration(milliseconds: 180),
                    child: Text(
                      item.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF24163C),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  FadeInUp(
                    delay: const Duration(milliseconds: 320),
                    child: Text(
                      item.desc,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 16,
                        height: 1.9,
                        color: Color(0xFF6F6482),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
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
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildGhostButton(label: 'تخطي', onPressed: _finishOnboarding),
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
                  onPressed: _nextPage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(158, 56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  icon: Icon(
                    _currentPage == _slides.length - 1
                        ? Icons.check_rounded
                        : Icons.arrow_forward_rounded,
                  ),
                  label: Text(
                    _currentPage == _slides.length - 1 ? 'ابدأ الآن' : 'التالي',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
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
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
