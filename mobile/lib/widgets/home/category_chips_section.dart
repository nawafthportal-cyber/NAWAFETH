import 'package:flutter/material.dart';

import '../../constants/app_theme.dart';
import '../../models/category_model.dart';
import 'home_section_header.dart';
import 'loading_skeletons.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Premium Category Chips Section (horizontal scroll)
// ─────────────────────────────────────────────────────────────────────────────

class CategoryChipsSection extends StatelessWidget {
  final List<CategoryModel> categories;
  final bool isLoading;
  final void Function(CategoryModel category)? onCategoryTap;
  final VoidCallback? onSeeAll;

  const CategoryChipsSection({
    super.key,
    required this.categories,
    required this.isLoading,
    this.onCategoryTap,
    this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(
          title: 'التصنيفات',
          leadingIcon: Icons.category_outlined,
          actionLabel: onSeeAll != null ? 'عرض الكل' : null,
          onAction: onSeeAll,
        ),
        if (isLoading && categories.isEmpty)
          const CategoryStripSkeleton()
        else if (categories.isEmpty)
          const HomeEmptyState(
            icon: Icons.category_outlined,
            message: 'لا توجد تصنيفات متاحة حالياً',
          )
        else
          _CategoryChipsList(
            categories: categories,
            onTap: onCategoryTap,
          ),
        const SizedBox(height: 4),
      ],
    );
  }
}

class _CategoryChipsList extends StatelessWidget {
  final List<CategoryModel> categories;
  final void Function(CategoryModel)? onTap;

  const _CategoryChipsList({required this.categories, this.onTap});

  /// Maps well-known category name fragments to icons.
  static const _iconMap = <String, IconData>{
    'تصوير': Icons.camera_alt_outlined,
    'تصميم': Icons.palette_outlined,
    'برمجة': Icons.code_rounded,
    'تقنية': Icons.computer_outlined,
    'استشارة': Icons.support_agent_rounded,
    'محاسبة': Icons.account_balance_outlined,
    'قانوني': Icons.gavel_rounded,
    'ترجمة': Icons.translate_rounded,
    'تعليم': Icons.school_outlined,
    'صحة': Icons.health_and_safety_outlined,
    'جمال': Icons.face_retouching_natural_outlined,
    'سيارة': Icons.directions_car_outlined,
    'منزل': Icons.home_repair_service_outlined,
    'طعام': Icons.restaurant_outlined,
    'سفر': Icons.travel_explore_rounded,
    'رياضة': Icons.fitness_center_rounded,
    'فن': Icons.brush_outlined,
    'موسيقى': Icons.music_note_rounded,
    'تسويق': Icons.campaign_outlined,
    'إعلام': Icons.mic_rounded,
  };

  IconData _iconFor(String name) {
    for (final entry in _iconMap.entries) {
      if (name.contains(entry.key)) return entry.value;
    }
    return Icons.work_outline_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ListView.builder(
        padding: const EdgeInsetsDirectional.only(start: 14, end: 14),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: categories.length,
        itemBuilder: (_, i) {
          final cat = categories[i];
          return _CategoryChip(
            category: cat,
            icon: _iconFor(cat.name),
            onTap: () => onTap?.call(cat),
          );
        },
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final CategoryModel category;
  final IconData icon;
  final VoidCallback? onTap;

  const _CategoryChip({
    required this.category,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? AppColors.cardDark : Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: isDark
                  ? AppColors.borderDark
                  : AppColors.primary.withAlpha(32),
              width: 1,
            ),
            boxShadow: AppShadows.card,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                category.name,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: AppTextStyles.bodySm,
                  fontWeight: AppTextStyles.semiBold,
                  color: isDark
                      ? AppTextStyles.textPrimaryDark
                      : AppTextStyles.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
