import 'package:flutter/material.dart';

import '../models/excellence_badge_model.dart';

class ExcellenceBadgesWrap extends StatelessWidget {
  final List<ExcellenceBadgeModel> badges;
  final bool compact;
  final WrapAlignment alignment;
  final EdgeInsetsGeometry padding;

  const ExcellenceBadgesWrap({
    super.key,
    required this.badges,
    this.compact = false,
    this.alignment = WrapAlignment.start,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    if (badges.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: padding,
      child: Wrap(
        alignment: alignment,
        spacing: compact ? 4 : 6,
        runSpacing: compact ? 4 : 6,
        children: badges
            .map((badge) => _BadgeChip(badge: badge, compact: compact))
            .toList(growable: false),
      ),
    );
  }
}

class _BadgeChip extends StatelessWidget {
  final ExcellenceBadgeModel badge;
  final bool compact;

  const _BadgeChip({required this.badge, required this.compact});

  @override
  Widget build(BuildContext context) {
    final color = _badgeColor(badge.color);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: compact ? 0.14 : 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.26)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_badgeIcon(badge), size: compact ? 11 : 13, color: color),
          const SizedBox(width: 4),
          Text(
            badge.name,
            style: TextStyle(
              fontSize: compact ? 9.5 : 11,
              fontWeight: FontWeight.w700,
              fontFamily: 'Cairo',
              color: color,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  IconData _badgeIcon(ExcellenceBadgeModel badge) {
    final normalized = badge.code.trim().toLowerCase();
    if (normalized == 'featured_service' || badge.icon == 'sparkles') {
      return Icons.auto_awesome_rounded;
    }
    if (normalized == 'high_achievement' || badge.icon == 'bolt') {
      return Icons.bolt_rounded;
    }
    if (normalized == 'top_100_club' || badge.icon == 'trophy') {
      return Icons.emoji_events_rounded;
    }
    return Icons.workspace_premium_rounded;
  }

  Color _badgeColor(String rawColor) {
    final cleaned = rawColor.trim().replaceFirst('#', '');
    if (cleaned.isEmpty) return Colors.amber.shade700;
    final value = cleaned.length == 6 ? 'FF$cleaned' : cleaned;
    final parsed = int.tryParse(value, radix: 16);
    if (parsed == null) return Colors.amber.shade700;
    return Color(parsed);
  }
}
