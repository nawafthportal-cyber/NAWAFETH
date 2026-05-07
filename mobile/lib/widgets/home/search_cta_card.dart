import 'package:flutter/material.dart';

import '../../constants/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Premium Glass / Soft Search CTA card
// ─────────────────────────────────────────────────────────────────────────────

class SearchCtaCard extends StatelessWidget {
  final VoidCallback? onTap;
  final String? greeting;

  const SearchCtaCard({
    super.key,
    this.onTap,
    this.greeting,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: screenWidth,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.cardDark.withAlpha(230)
                : Colors.white.withAlpha(230),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: isDark
                  ? AppColors.borderDark
                  : AppColors.primary.withAlpha(28),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withAlpha(16),
                blurRadius: 16,
                spreadRadius: 0,
                offset: const Offset(0, 4),
              ),
              ...AppShadows.card,
            ],
          ),
          child: Row(
            children: [
              // Search icon in purple bubble
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primaryLight, AppColors.primary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  boxShadow: AppShadows.primaryGlow(AppColors.primary),
                ),
                child: const Icon(
                  Icons.search_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              // Text hint
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      greeting?.isNotEmpty == true ? greeting! : 'ابحث عن خدمة',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: AppTextStyles.bodyLg,
                        fontWeight: AppTextStyles.semiBold,
                        color: isDark
                            ? AppTextStyles.textPrimaryDark
                            : AppTextStyles.textPrimary,
                      ),
                    ),
                    Text(
                      'مختصون موثوقون في خدمتك',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: AppTextStyles.bodySm,
                        fontWeight: AppTextStyles.regular,
                        color: isDark
                            ? AppTextStyles.textTertiaryDark
                            : AppTextStyles.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              // Arrow
              Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 16,
                color: isDark
                    ? AppTextStyles.textTertiaryDark
                    : AppTextStyles.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
