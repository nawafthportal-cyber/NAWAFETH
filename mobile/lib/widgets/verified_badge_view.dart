import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/verification_service.dart';

typedef BadgeDetailFetcher = Future<ApiResponse> Function(String badgeType);

class VerifiedBadgeView extends StatelessWidget {
  final bool isVerifiedBlue;
  final bool isVerifiedGreen;
  final double iconSize;
  final bool showLabel;
  final bool enableTap;
  final String label;
  final TextStyle? labelStyle;
  final EdgeInsetsGeometry padding;
  final BadgeDetailFetcher? detailFetcher;

  const VerifiedBadgeView({
    super.key,
    required this.isVerifiedBlue,
    required this.isVerifiedGreen,
    this.iconSize = 14,
    this.showLabel = false,
    this.enableTap = true,
    this.label = 'موثّق',
    this.labelStyle,
    this.padding = EdgeInsets.zero,
    this.detailFetcher,
  });

  bool get _isVisible => isVerifiedBlue || isVerifiedGreen;

  String get _badgeType => isVerifiedBlue ? 'blue' : 'green';

  Color get _badgeColor => isVerifiedBlue ? Colors.blue : Colors.green;

  Future<void> _showBadgeExplanation(BuildContext context) async {
    final fetch = detailFetcher ?? VerificationService.fetchPublicBadgeDetail;
    final response = await fetch(_badgeType);
    if (!context.mounted) return;

    final data = response.data;
    if (!response.isSuccess || data is! Map) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر جلب تفاصيل الشارة')),
      );
      return;
    }

    final payload = Map<String, dynamic>.from(data);
    final title = (payload['title'] ?? '').toString().trim();
    final shortDescription =
        (payload['short_description'] ?? '').toString().trim();
    final explanation = (payload['explanation'] ?? '').toString().trim();

    final rawRequirements =
        payload['requirements'] is List ? payload['requirements'] as List : const [];
    final requirements = rawRequirements
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .map((item) {
          final code = (item['code'] ?? '').toString().trim();
          final requirementTitle = (item['title'] ?? '').toString().trim();
          if (code.isEmpty && requirementTitle.isEmpty) return '';
          if (code.isEmpty) return requirementTitle;
          if (requirementTitle.isEmpty) return code;
          return '$code: $requirementTitle';
        })
        .where((line) => line.isNotEmpty)
        .toList(growable: false);

    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.verified, color: _badgeColor, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title.isNotEmpty ? title : 'تفاصيل الشارة',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (shortDescription.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      shortDescription,
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (explanation.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      explanation,
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12.5,
                        height: 1.5,
                      ),
                    ),
                  ],
                  if (requirements.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'متطلبات الشارة',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...requirements.map(
                      (line) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '• ',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                line,
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12.5,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isVisible) return const SizedBox.shrink();

    final icon = Icon(Icons.verified, size: iconSize, color: _badgeColor);

    Widget content;
    if (showLabel) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 4),
          Text(
            label,
            style: labelStyle ??
                const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      );
    } else {
      content = icon;
    }

    if (!enableTap) {
      return Padding(padding: padding, child: content);
    }

    return InkWell(
      onTap: () => _showBadgeExplanation(context),
      borderRadius: BorderRadius.circular(16),
      child: Padding(padding: padding, child: content),
    );
  }
}
