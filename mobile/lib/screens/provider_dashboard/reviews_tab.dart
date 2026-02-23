import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/account_api.dart';
import '../../services/reviews_api.dart';
import '../../services/support_api.dart';

class ReviewsTab extends StatefulWidget {
  final int? providerId;
  final bool embedded;
  final Future<void> Function(String customerName)? onOpenChat;

  const ReviewsTab({
    super.key,
    this.providerId,
    this.embedded = false,
    this.onOpenChat,
  });

  @override
  State<ReviewsTab> createState() => _ReviewsTabState();
}

class _ReviewsTabState extends State<ReviewsTab> {
  bool _loading = true;
  String? _error;

  int? _providerId;
  Map<String, dynamic>? _rating;
  List<Map<String, dynamic>> _reviews = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _rating = null;
      _reviews = const [];
    });

    try {
      final providerId = widget.providerId ?? await _resolveProviderId();
      _providerId = providerId;

      final rating = await ReviewsApi().getProviderRatingSummary(providerId);
      final reviews = await ReviewsApi().getProviderReviews(providerId);

      if (!mounted) return;
      setState(() {
        _rating = rating;
        _reviews = reviews;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<int> _resolveProviderId() async {
    final me = await AccountApi().me();
    final providerProfileId = me['provider_profile_id'];
    if (providerProfileId is int && providerProfileId > 0) return providerProfileId;
    if (providerProfileId is String) {
      final parsed = int.tryParse(providerProfileId);
      if (parsed != null && parsed > 0) return parsed;
    }

    throw StateError('Cannot resolve provider_profile_id from /accounts/me/.');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('تعذر تحميل التقييمات', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('إعادة المحاولة')),
            ],
          ),
        ),
      );
    }

    final body = RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _RatingSummaryCard(rating: _rating),
          const SizedBox(height: 12),
          _CriteriaBreakdownSection(rating: _rating),
          const SizedBox(height: 14),
          _SectionHeader(
            title: 'المراجعات',
          ),
          const SizedBox(height: 10),
          if (_reviews.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'لا توجد مراجعات حتى الآن',
                  style: TextStyle(fontFamily: 'Cairo'),
                ),
              ),
            )
          else
            ..._reviews.map(
              (r) => _ReviewCard(
                review: r,
                providerId: _providerId,
                onOpenChat: widget.onOpenChat,
              ),
            ),
        ],
      ),
    );

    if (widget.embedded) {
      return Directionality(textDirection: TextDirection.rtl, child: body);
    }

    // ReviewsTab is used as a tab/content widget; the parent screen should
    // provide the page-level AppBar to avoid duplicated titles.
    return Directionality(textDirection: TextDirection.rtl, child: body);
  }

}

class _ReviewCard extends StatelessWidget {
  final dynamic review;
  final int? providerId;
  final Future<void> Function(String customerName)? onOpenChat;

  const _ReviewCard({
    required this.review,
    required this.providerId,
    required this.onOpenChat,
  });

  @override
  Widget build(BuildContext context) {
    final map = (review is Map<String, dynamic>) ? (review as Map<String, dynamic>) : <String, dynamic>{};

    final reviewIdRaw = map['id'];
    final reviewId = (reviewIdRaw is int)
        ? reviewIdRaw
        : int.tryParse(reviewIdRaw?.toString() ?? '');

    final authorPhone = (map['client_phone'] ?? '').toString().trim();
    final authorName = (map['client_name'] ?? '').toString().trim();
    final authorLabel = authorName.isNotEmpty
        ? authorName
        : (authorPhone.isNotEmpty ? authorPhone : 'عميل');

    final rating = map['rating'] ?? map['stars'];
    final comment = map['comment'] ?? map['text'] ?? map['review'] ?? '';
    final createdAt = map['created_at'] ?? map['createdAt'];

    final ratingValue = _asDouble(rating).clamp(0.0, 5.0).toDouble();

    return Card(
      elevation: 1.2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    authorLabel,
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
                _ReviewOptions(
                  comment: comment.toString(),
                  clientPhone: authorPhone,
                  reviewId: reviewId,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _Stars(value: ratingValue, size: 18),
                const SizedBox(width: 8),
                Text(
                  ratingValue.toStringAsFixed(1),
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (createdAt != null)
                  Text(
                    createdAt.toString(),
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
              ],
            ),
            if (comment.toString().trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                comment.toString(),
                style: const TextStyle(fontFamily: 'Cairo'),
              ),
            ],
            if (onOpenChat != null) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => onOpenChat?.call(authorLabel),
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: const Text('محادثة', style: TextStyle(fontFamily: 'Cairo')),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static double _asDouble(Object? v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }
}

class _Stars extends StatelessWidget {
  final double value;
  final double size;

  const _Stars({required this.value, this.size = 16});

  @override
  Widget build(BuildContext context) {
    final full = value.floor();
    final half = (value - full) >= 0.5 ? 1 : 0;
    final empty = 5 - full - half;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < full; i++) Icon(Icons.star, size: size, color: Colors.amber),
        if (half == 1) Icon(Icons.star_half, size: size, color: Colors.amber),
        for (int i = 0; i < empty; i++) Icon(Icons.star_border, size: size, color: Colors.amber),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
        ),
      ],
    );
  }
}

class _RatingSummaryCard extends StatelessWidget {
  final Map<String, dynamic>? rating;

  const _RatingSummaryCard({required this.rating});

  @override
  Widget build(BuildContext context) {
    final safe = rating ?? const <String, dynamic>{};
    final avg = _asDouble(safe['rating_avg']).clamp(0.0, 5.0).toDouble();
    final count = _asInt(safe['rating_count']);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF5E35B1), Color(0xFF4527A0)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 92,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                const Text(
                  'عدد\nالمقيمين',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$count',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'التقييم',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _Stars(value: avg, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      avg.toStringAsFixed(1),
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static int _asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static double _asDouble(Object? v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

}

class _CriteriaBreakdownSection extends StatelessWidget {
  final Map<String, dynamic>? rating;

  const _CriteriaBreakdownSection({required this.rating});

  @override
  Widget build(BuildContext context) {
    final safe = rating ?? const <String, dynamic>{};
    final count = _asInt(safe['rating_count']);

    final responseSpeedAvg = _asNullableDouble(safe['response_speed_avg']);
    final costValueAvg = _asNullableDouble(safe['cost_value_avg']);
    final qualityAvg = _asNullableDouble(safe['quality_avg']);
    final credibilityAvg = _asNullableDouble(safe['credibility_avg']);
    final onTimeAvg = _asNullableDouble(safe['on_time_avg']);

    // No dummy UI: show this section only when API provides averages.
    final hasAny = [
      responseSpeedAvg,
      costValueAvg,
      qualityAvg,
      credibilityAvg,
      onTimeAvg,
    ].any((v) => v != null);
    if (count <= 0 || !hasAny) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: 'التقييم'),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            children: [
              _CriteriaRow(label: 'سرعة الاستجابة', value: responseSpeedAvg),
              _CriteriaRow(label: 'التكلفة مقابل الخدمة', value: costValueAvg),
              _CriteriaRow(label: 'جودة الخدمة', value: qualityAvg),
              _CriteriaRow(label: 'المصداقية', value: credibilityAvg),
              _CriteriaRow(label: 'وقت الإنجاز', value: onTimeAvg),
            ],
          ),
        ),
      ],
    );
  }

  static int _asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static double? _asNullableDouble(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

class _CriteriaRow extends StatelessWidget {
  final String label;
  final double? value;

  const _CriteriaRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final v = value;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
          ),
          const SizedBox(width: 12),
          if (v == null)
            Text(
              '—',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w700,
              ),
            )
          else
            _Stars(value: v.clamp(0.0, 5.0).toDouble(), size: 18),
        ],
      ),
    );
  }
}

enum _ReviewAction { copyText, copyPhone, report }

class _ReviewOptions extends StatelessWidget {
  final String comment;
  final String clientPhone;
  final int? reviewId;

  const _ReviewOptions({required this.comment, required this.clientPhone, required this.reviewId});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_ReviewAction>(
      tooltip: 'خيارات التقييم',
      position: PopupMenuPosition.under,
      onSelected: (action) async {
        switch (action) {
          case _ReviewAction.copyText:
            if (comment.trim().isEmpty) return;
            await Clipboard.setData(ClipboardData(text: comment));
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('تم نسخ نص المراجعة')),
            );
            return;
          case _ReviewAction.copyPhone:
            if (clientPhone.trim().isEmpty) return;
            await Clipboard.setData(ClipboardData(text: clientPhone));
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('تم نسخ رقم العميل')),
            );
            return;
          case _ReviewAction.report:
            try {
              final res = await SupportApi().createComplaintTicket(
                reason: 'بلاغ مراجعة',
                details: comment.trim().isEmpty
                    ? 'تم الإبلاغ عن مراجعة بدون تعليق نصي.'
                    : 'نص المراجعة: ${comment.trim()}',
                contextLabel: 'رقم العميل',
                contextValue: clientPhone.trim().isEmpty ? 'غير متوفر' : clientPhone.trim(),
                reportedEntityValue: 'مراجعة على ملف المزود',
                reportedKind: (reviewId == null) ? null : 'review',
                reportedObjectId: (reviewId == null) ? null : reviewId.toString(),
              );
              if (!context.mounted) return;
              final code = (res['code'] ?? '').toString().trim();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    code.isEmpty ? 'تم إرسال البلاغ' : 'تم إرسال البلاغ: $code',
                  ),
                ),
              );
            } catch (_) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تعذر إرسال البلاغ حالياً')),
              );
            }
            return;
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: _ReviewAction.copyText,
          enabled: comment.trim().isNotEmpty,
          child: const Text('نسخ نص المراجعة', style: TextStyle(fontFamily: 'Cairo')),
        ),
        PopupMenuItem(
          value: _ReviewAction.copyPhone,
          enabled: clientPhone.trim().isNotEmpty,
          child: const Text('نسخ رقم العميل', style: TextStyle(fontFamily: 'Cairo')),
        ),
        const PopupMenuItem(
          value: _ReviewAction.report,
          child: Text('إبلاغ', style: TextStyle(fontFamily: 'Cairo')),
        ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'خيارات التقييم',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(width: 2),
          Icon(Icons.more_vert, size: 18, color: Colors.grey.shade700),
        ],
      ),
    );
  }
}
