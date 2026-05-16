import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';

import '../../constants/app_theme.dart';
import '../../models/featured_specialist_model.dart';
import '../../services/api_client.dart';
import 'home_section_header.dart';
import 'loading_skeletons.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Premium Verified Providers Horizontal Section
// ─────────────────────────────────────────────────────────────────────────────

class VerifiedProvidersSection extends StatelessWidget {
  final List<FeaturedSpecialistModel> specialists;
  final bool isLoading;
  final void Function(FeaturedSpecialistModel specialist)? onProviderTap;
  final VoidCallback? onSeeAll;

  const VerifiedProvidersSection({
    super.key,
    required this.specialists,
    required this.isLoading,
    this.onProviderTap,
    this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(
          title: 'أبرز المختصين',
          leadingIcon: Icons.verified_rounded,
          actionLabel: onSeeAll != null ? 'عرض الكل' : null,
          onAction: onSeeAll,
        ),
        if (isLoading && specialists.isEmpty)
          const VerifiedProvidersSkeleton()
        else if (specialists.isEmpty)
          const HomeEmptyState(
            icon: Icons.group_outlined,
            message: 'لا يوجد مقدمو خدمة متاحون حالياً',
          )
        else
          SizedBox(
            height: 190,
            child: ListView.builder(
              padding: const EdgeInsetsDirectional.only(start: 12, end: 12),
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: specialists.length,
              itemBuilder: (_, i) => _ProviderCard(
                specialist: specialists[i],
                onTap: () => onProviderTap?.call(specialists[i]),
              ),
            ),
          ),
        const SizedBox(height: 4),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Individual provider card
// ─────────────────────────────────────────────────────────────────────────────

class _ProviderCard extends StatelessWidget {
  final FeaturedSpecialistModel specialist;
  final VoidCallback? onTap;

  const _ProviderCard({required this.specialist, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final profileUrl = ApiClient.buildMediaUrl(specialist.profileImage);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 148,
        margin: const EdgeInsetsDirectional.only(end: 10),
        decoration: BoxDecoration(
          color: isDark ? AppColors.cardDark : Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color:
                isDark ? AppColors.borderDark : AppColors.primary.withAlpha(20),
            width: 1,
          ),
          boxShadow: AppShadows.card,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Avatar with badge
              Stack(
                alignment: Alignment.bottomLeft,
                children: [
                  _Avatar(url: profileUrl, size: 62),
                  if (specialist.isVerified)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      child: _VerificationBadge(
                        isBlue: specialist.isVerifiedBlue,
                        isGreen: specialist.isVerifiedGreen,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              // Name
              Text(
                specialist.displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: AppTextStyles.bodySm,
                  fontWeight: AppTextStyles.bold,
                  color: isDark
                      ? AppTextStyles.textPrimaryDark
                      : AppTextStyles.textPrimary,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 4),
              // Rating
              if (specialist.ratingAvg > 0)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    RatingBarIndicator(
                      rating: specialist.ratingAvg.clamp(0, 5),
                      itemBuilder: (_, __) => const Icon(
                        Icons.star_rounded,
                        color: Color(0xFFFFB800),
                      ),
                      itemCount: 5,
                      itemSize: 10,
                      direction: Axis.horizontal,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      specialist.ratingLabel,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: AppTextStyles.caption,
                        fontWeight: AppTextStyles.medium,
                        color: isDark
                            ? AppTextStyles.textSecondaryDark
                            : AppTextStyles.textSecondary,
                      ),
                    ),
                  ],
                ),
              const Spacer(),
              // View button
              _ViewButton(onTap: onTap),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? url;
  final double size;

  const _Avatar({this.url, required this.size});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: AppColors.primary.withAlpha(40),
          width: 1.5,
        ),
        color: isDark ? AppColors.cardDark : AppColors.primarySurface,
      ),
      clipBehavior: Clip.antiAlias,
      child: url != null && url!.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: url!,
              fit: BoxFit.cover,
              width: size,
              height: size,
              placeholder: (_, __) => const Center(
                child: Icon(
                  Icons.person_outline_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              errorWidget: (_, __, ___) => const Center(
                child: Icon(
                  Icons.person_outline_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
            )
          : const Center(
              child: Icon(
                Icons.person_outline_rounded,
                color: AppColors.primary,
                size: 20,
              ),
            ),
    );
  }
}

class _VerificationBadge extends StatelessWidget {
  final bool isBlue;
  final bool isGreen;

  const _VerificationBadge({required this.isBlue, required this.isGreen});

  @override
  Widget build(BuildContext context) {
    final color = isBlue
        ? const Color(0xFF1D9BF0)
        : isGreen
            ? AppColors.success
            : AppColors.primary;
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: const Icon(Icons.check_rounded, size: 11, color: Colors.white),
    );
  }
}

class _ViewButton extends StatelessWidget {
  final VoidCallback? onTap;

  const _ViewButton({this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 26,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.primaryLight, AppColors.primary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        alignment: Alignment.center,
        child: const Text(
          'عرض',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: AppTextStyles.caption,
            fontWeight: AppTextStyles.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
