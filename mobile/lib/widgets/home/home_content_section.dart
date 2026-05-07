import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../constants/app_theme.dart';
import '../../models/media_item_model.dart';
import '../../services/api_client.dart';
import 'home_section_header.dart';
import 'loading_skeletons.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Premium Home Content Section (portfolio / spotlights)
// ─────────────────────────────────────────────────────────────────────────────

class HomeContentSection extends StatelessWidget {
  final List<MediaItemModel> items;
  final bool isLoading;
  final String title;
  final String? actionLabel;
  final void Function(MediaItemModel item)? onItemTap;
  final VoidCallback? onSeeAll;

  const HomeContentSection({
    super.key,
    required this.items,
    required this.isLoading,
    this.title = 'المحتوى المميز',
    this.actionLabel,
    this.onItemTap,
    this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(
          title: title,
          leadingIcon: Icons.auto_awesome_rounded,
          actionLabel: actionLabel ?? (onSeeAll != null ? 'عرض الكل' : null),
          onAction: onSeeAll,
        ),
        if (isLoading && items.isEmpty)
          const ContentSectionSkeleton()
        else if (items.isEmpty)
          const HomeEmptyState(
            icon: Icons.photo_library_outlined,
            message: 'لا يوجد محتوى متاح حالياً',
          )
        else
          SizedBox(
            height: 186,
            child: ListView.builder(
              padding: const EdgeInsetsDirectional.only(start: 14, end: 14),
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: items.length,
              itemBuilder: (_, i) => _ContentCard(
                item: items[i],
                onTap: () => onItemTap?.call(items[i]),
              ),
            ),
          ),
        const SizedBox(height: 4),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Single content card
// ─────────────────────────────────────────────────────────────────────────────

class _ContentCard extends StatelessWidget {
  final MediaItemModel item;
  final VoidCallback? onTap;

  const _ContentCard({required this.item, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final thumbUrl = ApiClient.buildMediaUrl(
      item.thumbnailUrl?.isNotEmpty == true ? item.thumbnailUrl : item.fileUrl,
    );
    final isVideo = (item.fileType).toLowerCase() == 'video';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 152,
        margin: const EdgeInsetsDirectional.only(end: 10),
        decoration: BoxDecoration(
          color: isDark ? AppColors.cardDark : Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: AppShadows.card,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Media thumbnail
            Stack(
              children: [
                Container(
                  height: 106,
                  width: double.infinity,
                  color: isDark
                      ? AppColors.cardDark
                      : AppColors.primarySurface,
                  child: thumbUrl != null
                      ? CachedNetworkImage(
                          imageUrl: thumbUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: 106,
                          placeholder: (_, __) => const Center(
                            child: Icon(
                              Icons.image_outlined,
                              color: AppColors.primary,
                              size: 28,
                            ),
                          ),
                          errorWidget: (_, __, ___) => const Center(
                            child: Icon(
                              Icons.broken_image_outlined,
                              color: AppColors.grey300,
                              size: 24,
                            ),
                          ),
                        )
                      : const Center(
                          child: Icon(
                            Icons.image_outlined,
                            color: AppColors.primary,
                            size: 28,
                          ),
                        ),
                ),
                // Video play indicator
                if (isVideo)
                  Positioned.fill(
                    child: Center(
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                // Sponsored badge
                if (item.sponsoredBadgeOnly)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: const Text(
                        'ممول',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            // Text info
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Provider name
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.providerDisplayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: AppTextStyles.caption,
                            fontWeight: AppTextStyles.semiBold,
                            color: isDark
                                ? AppTextStyles.textPrimaryDark
                                : AppTextStyles.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if ((item.caption ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.caption!.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: AppTextStyles.micro,
                        color: isDark
                            ? AppTextStyles.textTertiaryDark
                            : AppTextStyles.textTertiary,
                        height: 1.4,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  // Engagement row
                  Row(
                    children: [
                      const Icon(
                        Icons.favorite_border_rounded,
                        size: 11,
                        color: AppColors.grey400,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${item.likesCount}',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: AppTextStyles.micro,
                          color: AppColors.grey400,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
