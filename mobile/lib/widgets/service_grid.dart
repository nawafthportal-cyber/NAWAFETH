import 'package:flutter/material.dart';
import '../constants/app_theme.dart';

class ServiceGrid extends StatefulWidget {
  const ServiceGrid({super.key});

  @override
  State<ServiceGrid> createState() => _ServiceGridState();
}

class _ServiceGridState extends State<ServiceGrid> {
  // قائمة كاملة بالخدمات
  final List<Map<String, dynamic>> allServices = [
    {'title': 'استشارات قانونية', 'icon': Icons.gavel},
    {'title': 'خدمات هندسية', 'icon': Icons.engineering},
    {'title': 'تصميم جرافيك', 'icon': Icons.design_services},
    {'title': 'توصيل سريع', 'icon': Icons.delivery_dining},
    {'title': 'رعاية صحية', 'icon': Icons.health_and_safety},
    {'title': 'ترجمة لغات', 'icon': Icons.translate},
    {'title': 'برمجة مواقع', 'icon': Icons.code},
    {'title': 'صيانة أجهزة', 'icon': Icons.build},
    {'title': 'تدريب رياضي', 'icon': Icons.fitness_center},
    {'title': 'خدمات منزلية', 'icon': Icons.home_repair_service},
    {'title': 'استشارات مالية', 'icon': Icons.attach_money},
    {'title': 'تسويق إلكتروني', 'icon': Icons.campaign},
  ];

  int visibleCount = 6;

  @override
  Widget build(BuildContext context) {
    final visibleServices = allServices.take(visibleCount).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children:
              visibleServices.map((service) {
                return Container(
                  width: (MediaQuery.of(context).size.width - 48) / 2,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
                    border: Border.all(
                      color: AppColors.primaryDark.withAlpha(26),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        service['icon'],
                        size: 36,
                        color: AppColors.primaryDark,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        service['title'],
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.deepPurple,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
        ),

        const SizedBox(height: 16),

        Center(
          child: TextButton.icon(
            onPressed: () {
              setState(() {
                // ✅ تبديل بين "عرض المزيد" و"عرض أقل"
                if (visibleCount < allServices.length) {
                  visibleCount = (visibleCount + 6).clamp(
                    0,
                    allServices.length,
                  );
                } else {
                  visibleCount = 6;
                }
              });
            },
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primaryDark,
              backgroundColor: AppColors.primaryLight.withAlpha(38),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: Icon(
              visibleCount < allServices.length
                  ? Icons.expand_more
                  : Icons.expand_less,
              size: 20,
            ),
            label: Text(
              visibleCount < allServices.length ? 'عرض المزيد' : 'عرض أقل',
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
