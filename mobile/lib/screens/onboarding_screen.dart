import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:animate_do/animate_do.dart';
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
  final Widget icon;
  final String title;
  final String desc;
  final String? mediaUrl;
  final String mediaType;

  const OnboardItem({
    required this.icon,
    required this.title,
    required this.desc,
    this.mediaUrl,
    this.mediaType = '',
  });

  OnboardItem copyWith({
    Widget? icon,
    String? title,
    String? desc,
    String? mediaUrl,
    String? mediaType,
  }) {
    return OnboardItem(
      icon: icon ?? this.icon,
      title: title ?? this.title,
      desc: desc ?? this.desc,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      mediaType: mediaType ?? this.mediaType,
    );
  }
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // الصفحات الثلاثة (قابلة للتحديث من API)
  late List<OnboardItem> onboardingData = [
    const OnboardItem(
      icon: Icon(Icons.widgets, size: 80, color: AppColors.deepPurple),
      title: "مرحبا بك في نوافذ",
      desc: "منصتك الأولى لربط العملاء بمقدمي الخدمات.",
    ),
    const OnboardItem(
      icon: FaIcon(
        FontAwesomeIcons.users,
        size: 80,
        color: AppColors.deepPurple,
      ),
      title: "لكل عميل ومقدم خدمة",
      desc: "اختر خدماتك أو اعرض خبراتك وابدأ التواصل مباشرة.",
    ),
    const OnboardItem(
      icon: FaIcon(
        FontAwesomeIcons.bolt,
        size: 80,
        color: AppColors.deepPurple,
      ),
      title: "انطلق الآن",
      desc: "جرب تجربة سلسة وسريعة لتصل لما تريد خلال ثوانٍ.",
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadContentFromApi();
  }

  /// تحميل محتوى الأونبوردينغ من API (onboarding_first_time / onboarding_intro)
  Future<void> _loadContentFromApi() async {
    try {
      final result = await ContentService.fetchPublicContent();
      if (!mounted) return;
      if (result.isSuccess && result.dataAsMap != null) {
        final blocks =
            (result.dataAsMap!['blocks'] as Map<String, dynamic>?) ?? {};

        final firstTime = blocks['onboarding_first_time'];
        final intro = blocks['onboarding_intro'];

        setState(() {
          if (firstTime is Map<String, dynamic>) {
            onboardingData[0] = _mergeApiBlock(onboardingData[0], firstTime);
          }

          if (intro is Map<String, dynamic>) {
            onboardingData[1] = _mergeApiBlock(onboardingData[1], intro);
          }
        });
      }
    } catch (_) {
      // fallback إلى النصوص الثابتة
    }
  }

  OnboardItem _mergeApiBlock(OnboardItem fallback, Map<String, dynamic> block) {
    final title = (block['title_ar'] as String?)?.trim() ?? '';
    final body = (block['body_ar'] as String?)?.trim() ?? '';
    final mediaUrl = ApiClient.buildMediaUrl(block['media_url']?.toString());
    final mediaType = (block['media_type'] as String?)?.trim() ?? '';

    return fallback.copyWith(
      title: title.isNotEmpty ? title : fallback.title,
      desc: body.isNotEmpty ? body : fallback.desc,
      mediaUrl: (mediaUrl ?? '').isNotEmpty ? mediaUrl : fallback.mediaUrl,
      mediaType: mediaType.isNotEmpty ? mediaType : fallback.mediaType,
    );
  }

  void _nextPage() {
    if (_currentPage < onboardingData.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
    } else {
      _finishOnboarding();
    }
  }

  void _skip() => _finishOnboarding();

  void _finishOnboarding() {
    Navigator.pushReplacementNamed(context, '/home');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: onboardingData.length,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                itemBuilder: (context, index) {
                  final item = onboardingData[index];
                  return _buildPage(
                    item: item,
                    isActive: index == _currentPage,
                  );
                },
              ),
            ),
            _buildBottomControls(),
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
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          BounceInDown(
            child: ContentBlockMedia(
              mediaUrl: item.mediaUrl,
              mediaType: item.mediaType,
              isActive: isActive,
              borderRadius: 32,
              aspectRatio: 1,
              fallback: Container(
                width: 168,
                height: 168,
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.shade50,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.deepPurple.withValues(alpha: 0.2),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Center(child: item.icon),
              ),
            ),
          ),

          const SizedBox(height: 40),

          FadeInUp(
            delay: const Duration(milliseconds: 300),
            child: Text(
              item.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: "Cairo",
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),

          const SizedBox(height: 18),

          FadeInUp(
            delay: const Duration(milliseconds: 500),
            child: Text(
              item.desc,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: "Cairo",
                fontSize: 16,
                color: Colors.grey.shade600,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              onboardingData.length,
              (index) => AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                margin: const EdgeInsets.symmetric(horizontal: 5),
                width: _currentPage == index ? 26 : 10,
                height: 10,
                decoration: BoxDecoration(
                  color:
                      _currentPage == index
                          ? Colors.deepPurple
                          : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow:
                      _currentPage == index
                          ? [
                            BoxShadow(
                              color: Colors.deepPurple.withOpacity(0.4),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ]
                          : [],
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: _skip,
                child: const Text(
                  "تخطي",
                  style: TextStyle(
                    fontFamily: "Cairo",
                    fontSize: 16,
                    color: Colors.deepOrange,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: _nextPage,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(18),
                  elevation: 5,
                ),
                child: Icon(
                  _currentPage == onboardingData.length - 1
                      ? Icons.check
                      : Icons.arrow_forward_ios,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
