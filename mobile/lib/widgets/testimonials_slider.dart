import 'dart:async';
import 'package:flutter/material.dart';
import '../constants/app_theme.dart';

class TestimonialsSlider extends StatefulWidget {
  const TestimonialsSlider({super.key});

  @override
  State<TestimonialsSlider> createState() => _TestimonialsSliderState();
}

class _TestimonialsSliderState extends State<TestimonialsSlider> {
  final PageController _controller = PageController(viewportFraction: 0.85);
  int _currentIndex = 0;

  final List<Map<String, dynamic>> testimonials = [
    {
      'name': 'محمد القحطاني',
      'comment': 'منصة رائعة وسهّلت علي الوصول لمقدم الخدمة.',
      'rating': 5,
    },
    {
      'name': 'سارة العتيبي',
      'comment': 'خدمة سريعة وتعامل راقٍ جدًا، شكرًا نوافذ!',
      'rating': 4,
    },
    {
      'name': 'أحمد الفيفي',
      'comment': 'جربت أكثر من خدمة وكلها ممتازة بكل أمانة.',
      'rating': 5,
    },
  ];

  @override
  void initState() {
    super.initState();
    Timer.periodic(const Duration(seconds: 4), (timer) {
      if (_controller.hasClients) {
        _currentIndex++;
        if (_currentIndex >= testimonials.length) _currentIndex = 0;
        _controller.animateToPage(
          _currentIndex,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl, // ✅ كل المحتوى RTL
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'تقييمات',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.deepPurple,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 140,
            child: PageView.builder(
              controller: _controller,
              itemCount: testimonials.length,
              itemBuilder: (context, index) {
                final t = testimonials[index];
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.primaryDark.withAlpha(38),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const CircleAvatar(
                            backgroundColor: AppColors.primaryDark,
                            radius: 16,
                            child: Icon(
                              Icons.person,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              t['name'],
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        t['comment'],
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13,
                          color: Colors.black87,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: List.generate(
                          5,
                          (i) => Icon(
                            i < t['rating'] ? Icons.star : Icons.star_border,
                            size: 16,
                            color: Colors.amber,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
