import 'package:flutter/material.dart';

import 'verified_badge_view.dart';

class ProviderNameWithBadges extends StatelessWidget {
  final String name;
  final bool isVerifiedBlue;
  final bool isVerifiedGreen;
  final TextStyle style;
  final TextAlign textAlign;
  final int maxLines;
  final TextOverflow overflow;
  final double badgeIconSize;
  final bool enableBadgeTap;

  const ProviderNameWithBadges({
    super.key,
    required this.name,
    required this.isVerifiedBlue,
    required this.isVerifiedGreen,
    required this.style,
    this.textAlign = TextAlign.start,
    this.maxLines = 2,
    this.overflow = TextOverflow.ellipsis,
    this.badgeIconSize = 14,
    this.enableBadgeTap = false,
  });

  @override
  Widget build(BuildContext context) {
    final trimmedName = name.trim();
    if (!isVerifiedBlue && !isVerifiedGreen) {
      return Text(
        trimmedName,
        maxLines: maxLines,
        overflow: overflow,
        textAlign: textAlign,
        style: style,
      );
    }

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: trimmedName),
          if (isVerifiedBlue)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: 4),
                child: VerifiedBadgeView(
                  isVerifiedBlue: true,
                  isVerifiedGreen: false,
                  iconSize: badgeIconSize,
                  enableTap: enableBadgeTap,
                ),
              ),
            ),
          if (isVerifiedGreen)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: 4),
                child: VerifiedBadgeView(
                  isVerifiedBlue: false,
                  isVerifiedGreen: true,
                  iconSize: badgeIconSize,
                  enableTap: enableBadgeTap,
                ),
              ),
            ),
        ],
      ),
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
      style: style,
    );
  }
}