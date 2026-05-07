import 'package:flutter/material.dart';
import '../../constants/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Shimmer / Skeleton helpers for the premium home screen
// ─────────────────────────────────────────────────────────────────────────────

/// A single animated shimmer block.
class _Shimmer extends StatefulWidget {
  final double width;
  final double height;
  final double radius;

  const _Shimmer({
    required this.width,
    required this.height,
    this.radius = 12,
  });

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat();
    _anim = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor =
        isDark ? const Color(0xFF2A2540) : const Color(0xFFECECF2);
    final highlightColor =
        isDark ? const Color(0xFF3A3558) : const Color(0xFFF8F8FF);

    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          gradient: LinearGradient(
            begin: Alignment(_anim.value - 1, 0),
            end: Alignment(_anim.value + 1, 0),
            colors: [baseColor, highlightColor, baseColor],
          ),
        ),
      ),
    );
  }
}

/// Hero banner skeleton
class HeroBannerSkeleton extends StatelessWidget {
  const HeroBannerSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          child: _Shimmer(
            width: double.infinity,
            height: double.infinity,
            radius: AppRadius.xl,
          ),
        ),
      ),
    );
  }
}

/// Search CTA card skeleton
class SearchCtaCardSkeleton extends StatelessWidget {
  const SearchCtaCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: _Shimmer(width: double.infinity, height: 62, radius: AppRadius.lg),
    );
  }
}

/// Single category chip skeleton
class _CategoryChipSkeleton extends StatelessWidget {
  const _CategoryChipSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 8),
      child: _Shimmer(width: 80, height: 34, radius: AppRadius.pill),
    );
  }
}

/// Category strip skeleton — row of chip skeletons
class CategoryStripSkeleton extends StatelessWidget {
  const CategoryStripSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        padding: const EdgeInsetsDirectional.only(start: 14, end: 14),
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        children: List.generate(
          6,
          (_) => const _CategoryChipSkeleton(),
        ),
      ),
    );
  }
}

/// Single provider card skeleton
class _ProviderCardSkeleton extends StatelessWidget {
  const _ProviderCardSkeleton();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 130,
      margin: const EdgeInsetsDirectional.only(start: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadows.card,
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _Shimmer(width: 52, height: 52, radius: 26),
          const SizedBox(height: 8),
          _Shimmer(width: 80, height: 10, radius: 6),
          const SizedBox(height: 6),
          _Shimmer(width: 50, height: 8, radius: 6),
          const SizedBox(height: 8),
          _Shimmer(width: 72, height: 26, radius: AppRadius.sm),
        ],
      ),
    );
  }
}

/// Verified providers section skeleton
class VerifiedProvidersSkeleton extends StatelessWidget {
  const VerifiedProvidersSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 170,
      child: ListView(
        padding: const EdgeInsetsDirectional.only(start: 14, end: 14),
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        children: List.generate(4, (_) => const _ProviderCardSkeleton()),
      ),
    );
  }
}

/// Single content card skeleton
class _ContentCardSkeleton extends StatelessWidget {
  const _ContentCardSkeleton();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 150,
      margin: const EdgeInsetsDirectional.only(start: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Shimmer(
            width: 150,
            height: 100,
            radius: AppRadius.lg,
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Shimmer(width: 100, height: 9, radius: 5),
                const SizedBox(height: 6),
                _Shimmer(width: 70, height: 8, radius: 5),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Content section skeleton
class ContentSectionSkeleton extends StatelessWidget {
  const ContentSectionSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 170,
      child: ListView(
        padding: const EdgeInsetsDirectional.only(start: 14, end: 14),
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        children: List.generate(4, (_) => const _ContentCardSkeleton()),
      ),
    );
  }
}

/// Section header skeleton
class SectionHeaderSkeleton extends StatelessWidget {
  const SectionHeaderSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
      child: Row(
        children: [
          _Shimmer(width: 130, height: 14, radius: 7),
          const Spacer(),
          _Shimmer(width: 50, height: 12, radius: 6),
        ],
      ),
    );
  }
}
