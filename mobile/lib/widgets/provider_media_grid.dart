import 'package:flutter/material.dart';
import '../constants/app_theme.dart';

class ProviderMediaGrid extends StatefulWidget {
  const ProviderMediaGrid({super.key});

  @override
  State<ProviderMediaGrid> createState() => _ProviderMediaGridState();
}

class _ProviderMediaGridState extends State<ProviderMediaGrid> {
  final List<String> mediaFiles = [
    'assets/images/251.jpg',
    'assets/images/gng.png',
    'assets/images/8410.jpeg',
    'assets/images/8410.jpeg',
    'assets/images/251.jpg',
    'assets/images/p.png',
    'assets/images/251.jpg',
    'assets/images/p.png',
  ];

  int visibleCount = 4; // صفين = 4 كروت

  @override
  Widget build(BuildContext context) {
    final visibleMedia = mediaFiles.take(visibleCount).toList();
    final cardWidth = (MediaQuery.of(context).size.width - 48) / 2;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ✅ حذف العنوان
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children:
                visibleMedia.map((file) {
                  return Container(
                    width: cardWidth,
                    height: 120,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.primaryDark.withAlpha(26),
                      ),
                      image: DecorationImage(
                        image: AssetImage(file),
                        fit: BoxFit.cover,
                      ),
                    ),
                  );
                }).toList(),
          ),

          const SizedBox(height: 16),

          Center(
            child: TextButton.icon(
              onPressed: () {
                setState(() {
                  if (visibleCount < mediaFiles.length) {
                    visibleCount = (visibleCount + 4).clamp(
                      0,
                      mediaFiles.length,
                    );
                  } else {
                    visibleCount = 4;
                  }
                });
              },
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryDark,
                backgroundColor: AppColors.primaryLight.withAlpha(26),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: Icon(
                visibleCount < mediaFiles.length
                    ? Icons.expand_more
                    : Icons.expand_less,
                size: 20,
              ),
              label: Text(
                visibleCount < mediaFiles.length ? 'عرض المزيد' : 'عرض أقل',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
