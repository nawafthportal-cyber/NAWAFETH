import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/account_api.dart';
import '../../services/reviews_api.dart';
import '../../services/support_api.dart';
import '../../services/web_inline_banner.dart';
import '../../services/web_loading_overlay.dart';

class ReviewsTab extends StatefulWidget {
  final int? providerId;
  final bool embedded;
  final bool allowProviderReply;
  final Future<void> Function(String customerName)? onOpenChat;
  final String? initialSearchQuery;
  final String? initialReplyFilter;
  final int? initialMinRating;

  const ReviewsTab({
    super.key,
    this.providerId,
    this.embedded = false,
    this.allowProviderReply = false,
    this.onOpenChat,
    this.initialSearchQuery,
    this.initialReplyFilter,
    this.initialMinRating,
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
  final TextEditingController _searchController = TextEditingController();
  String _replyFilter = 'الكل';
  int _minRating = 0;
  Timer? _searchRouteSyncDebounce;

  @override
  void initState() {
    super.initState();
    _searchController.text = (widget.initialSearchQuery ?? '').trim();
    _replyFilter = _normalizeReplyFilter(widget.initialReplyFilter);
    _minRating = (widget.initialMinRating ?? 0).clamp(0, 5);
    _searchController.addListener(() {
      if (mounted) setState(() {});
      _scheduleWebUrlSync();
    });
    _load();
  }

  @override
  void dispose() {
    _searchRouteSyncDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
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
      final msg = e is StateError ? e.message : e.toString();
      setState(() {
        _error = msg.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadWithOverlay() {
    return WebLoadingOverlayController.instance.run(
      _load,
      message: 'جاري تحديث المراجعات...',
    );
  }

  Future<void> _replyToReview(Map<String, dynamic> review) async {
    final reviewIdRaw = review['id'];
    final reviewId = (reviewIdRaw is int)
        ? reviewIdRaw
        : int.tryParse(reviewIdRaw?.toString() ?? '');
    if (reviewId == null) {
      if (!mounted) return;
      WebInlineBannerController.instance.error('تعذر تحديد رقم المراجعة.');
      return;
    }

    final existingReply = (review['provider_reply'] ?? '').toString().trim();
    final controller = TextEditingController(text: existingReply);
    try {
      final reply = await showDialog<String>(
        context: context,
        builder: (ctx) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: const Text(
                'رد على المراجعة',
                style: TextStyle(fontFamily: 'Cairo'),
              ),
              content: TextField(
                controller: controller,
                maxLength: 500,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  hintText: 'اكتب ردك على مراجعة العميل',
                  border: OutlineInputBorder(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text(
                    'إلغاء',
                    style: TextStyle(fontFamily: 'Cairo'),
                  ),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.of(ctx).pop(controller.text.trim()),
                  child: Text(
                    existingReply.isEmpty ? 'إرسال الرد' : 'تحديث الرد',
                    style: const TextStyle(fontFamily: 'Cairo'),
                  ),
                ),
              ],
            ),
          );
        },
      );
      if (reply == null) return;
      if (reply.trim().isEmpty) {
        if (!mounted) return;
        WebInlineBannerController.instance.info('الرد مطلوب.');
        return;
      }

      await WebLoadingOverlayController.instance.run(
        () => ReviewsApi().replyToReviewAsProvider(
          reviewId: reviewId,
          reply: reply,
        ),
        message: existingReply.isEmpty
            ? 'جاري إرسال الرد...'
            : 'جاري تحديث الرد...',
      );
      if (!mounted) return;
      WebInlineBannerController.instance.success('تم حفظ الرد على المراجعة.');
      await _loadWithOverlay();
    } catch (e) {
      if (!mounted) return;
      WebInlineBannerController.instance.error(_friendlyErrorMessage(e));
    } finally {
      controller.dispose();
    }
  }

  Future<void> _clearReplyForReview(Map<String, dynamic> review) async {
    final reviewIdRaw = review['id'];
    final reviewId = (reviewIdRaw is int)
        ? reviewIdRaw
        : int.tryParse(reviewIdRaw?.toString() ?? '');
    if (reviewId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text(
            'حذف رد المراجعة',
            style: TextStyle(fontFamily: 'Cairo'),
          ),
          content: const Text(
            'هل تريد حذف ردك على هذه المراجعة؟',
            style: TextStyle(fontFamily: 'Cairo'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('حذف', style: TextStyle(fontFamily: 'Cairo')),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    try {
      await WebLoadingOverlayController.instance.run(
        () => ReviewsApi().deleteReviewReplyAsProvider(reviewId: reviewId),
        message: 'جاري حذف رد المراجعة...',
      );
      if (!mounted) return;
      WebInlineBannerController.instance.success('تم حذف رد المراجعة.');
      await _loadWithOverlay();
    } catch (e) {
      if (!mounted) return;
      WebInlineBannerController.instance.error(_friendlyErrorMessage(e));
    }
  }

  String _friendlyErrorMessage(Object e) {
    if (e is StateError && e.message.trim().isNotEmpty) {
      return e.message;
    }
    return 'تعذر حفظ الرد حالياً';
  }

  Future<int> _resolveProviderId() async {
    final me = await AccountApi().me();
    final providerProfileId = me['provider_profile_id'];
    if (providerProfileId is int && providerProfileId > 0)
      return providerProfileId;
    if (providerProfileId is String) {
      final parsed = int.tryParse(providerProfileId);
      if (parsed != null && parsed > 0) return parsed;
    }

    throw StateError('Cannot resolve provider_profile_id from /accounts/me/.');
  }

  int _ratingCountValue() {
    final raw = _rating?['rating_count'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  double _ratingAverageValue() {
    final raw = _rating?['rating_avg'];
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '') ?? 0;
  }

  String _normalizeReplyFilter(String? raw) {
    final v = (raw ?? '').trim().toLowerCase();
    switch (v) {
      case 'replied':
      case 'with_reply':
      case 'مردود':
        return 'مردود';
      case 'unreplied':
      case 'without_reply':
      case 'بدون رد':
        return 'بدون رد';
      case 'all':
      case 'الكل':
      default:
        return 'الكل';
    }
  }

  void _scheduleWebUrlSync() {
    if (!(kIsWeb && widget.embedded)) return;
    _searchRouteSyncDebounce?.cancel();
    _searchRouteSyncDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _syncWebUrl();
    });
  }

  void _syncWebUrl() {
    if (!(kIsWeb && widget.embedded)) return;
    final reply = switch (_replyFilter) {
      'مردود' => 'replied',
      'بدون رد' => 'unreplied',
      _ => 'all',
    };
    final query = <String, String>{
      'reply': reply,
      if (_minRating > 0) 'min_rating': '$_minRating',
      if (_searchController.text.trim().isNotEmpty)
        'q': _searchController.text.trim(),
    };
    SystemNavigator.routeInformationUpdated(
      uri: Uri(path: '/provider_dashboard/reviews', queryParameters: query),
      replace: true,
    );
  }

  Widget _desktopInfoChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              value,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _desktopEmbeddedLayout() {
    final avg = _ratingAverageValue();
    final count = _ratingCountValue();
    final reviews = List<Map<String, dynamic>>.from(_reviews);

    final reviewsList = reviews.isEmpty
        ? const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: Text(
                'لا توجد مراجعات حتى الآن',
                style: TextStyle(fontFamily: 'Cairo'),
              ),
            ),
          )
        : Column(
            children: reviews
                .map(
                  (r) => _ReviewCard(
                    review: r,
                    providerId: _providerId,
                    onOpenChat: widget.onOpenChat,
                    onReply: widget.allowProviderReply
                        ? () => _replyToReview(r)
                        : null,
                    onClearReply: widget.allowProviderReply
                        ? () => _clearReplyForReview(r)
                        : null,
                  ),
                )
                .toList(),
          );

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _desktopInfoChip(
                icon: Icons.star_rounded,
                label: 'متوسط التقييم',
                value: avg.toStringAsFixed(1),
                color: Colors.amber.shade800,
              ),
              _desktopInfoChip(
                icon: Icons.rate_review_rounded,
                label: 'عدد المراجعات',
                value: count.toString(),
                color: Colors.deepPurple,
              ),
              _desktopInfoChip(
                icon: Icons.reply_all_rounded,
                label: 'الردود',
                value: widget.allowProviderReply ? 'مفعّل' : 'غير مفعّل',
                color: widget.allowProviderReply ? Colors.green : Colors.grey,
              ),
              _desktopInfoChip(
                icon: Icons.filter_alt_rounded,
                label: 'المعروضة',
                value: reviews.length.toString(),
                color: Colors.blue,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionHeader(title: 'المراجعات'),
                      const SizedBox(height: 10),
                      reviewsList,
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    _RatingSummaryCard(rating: _rating),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      height: 1,
                      color: Colors.grey.shade200,
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ملخص الجودة',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _CriteriaBreakdownSection(rating: _rating),
                          if ((_ratingCountValue() <= 0))
                            Text(
                              'سيظهر التحليل التفصيلي بعد وصول مراجعات كافية.',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
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
              Text(
                'تعذر تحميل التقييمات',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _loadWithOverlay,
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    final filteredReviews = List<Map<String, dynamic>>.from(_reviews);
    final list = ListView(
      padding: const EdgeInsets.all(16),
      shrinkWrap: widget.embedded,
      physics: widget.embedded
          ? const NeverScrollableScrollPhysics()
          : const AlwaysScrollableScrollPhysics(),
      children: [
        _RatingSummaryCard(rating: _rating),
        const SizedBox(height: 14),
        Container(
          height: 1,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          color: Colors.grey.shade200,
        ),
        const SizedBox(height: 14),
        _CriteriaBreakdownSection(rating: _rating),
        const SizedBox(height: 14),
        _SectionHeader(title: 'المراجعات'),
        const SizedBox(height: 10),
        if (filteredReviews.isEmpty)
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
          ...filteredReviews.map(
            (r) => _ReviewCard(
              review: r,
              providerId: _providerId,
              onOpenChat: widget.onOpenChat,
              onReply: widget.allowProviderReply
                  ? () => _replyToReview(r)
                  : null,
              onClearReply: widget.allowProviderReply
                  ? () => _clearReplyForReview(r)
                  : null,
            ),
          ),
      ],
    );

    final body = widget.embedded
        ? list
        : RefreshIndicator(onRefresh: _load, child: list);

    if (widget.embedded && MediaQuery.of(context).size.width >= 980) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: _desktopEmbeddedLayout(),
      );
    }

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
  final Future<void> Function()? onReply;
  final Future<void> Function()? onClearReply;

  const _ReviewCard({
    required this.review,
    required this.providerId,
    required this.onOpenChat,
    required this.onReply,
    required this.onClearReply,
  });

  @override
  Widget build(BuildContext context) {
    final map = (review is Map<String, dynamic>)
        ? (review as Map<String, dynamic>)
        : <String, dynamic>{};

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
    final providerReply = (map['provider_reply'] ?? '').toString();
    final providerReplyAt = map['provider_reply_at'] ?? map['providerReplyAt'];
    final providerReplyEditedAt =
        map['provider_reply_edited_at'] ?? map['providerReplyEditedAt'];
    final providerReplyIsEdited =
        map['provider_reply_is_edited'] == true ||
        providerReplyEditedAt != null;
    final createdAt = map['created_at'] ?? map['createdAt'];

    final ratingValue = _asDouble(rating).clamp(0.0, 5.0).toDouble();
    final hasProviderReply = providerReply.trim().isNotEmpty;
    final Color reviewBgColor;
    if (ratingValue >= 4.0) {
      reviewBgColor = const Color(0xFFF8FDF8); // high
    } else if (ratingValue >= 2.5) {
      reviewBgColor = const Color(0xFFFFFCF5); // medium
    } else {
      reviewBgColor = const Color(0xFFFFF7F7); // low
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: reviewBgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border(
          top: BorderSide(color: Colors.grey.shade200),
          bottom: BorderSide(color: Colors.grey.shade200),
          left: BorderSide(color: Colors.grey.shade200),
          right: BorderSide(
            color: hasProviderReply
                ? Colors.deepPurple.withValues(alpha: 0.42)
                : Colors.grey.shade200,
            width: hasProviderReply ? 3 : 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.deepPurple.withValues(alpha: 0.12),
                    ),
                  ),
                  child: const Icon(
                    Icons.person_outline_rounded,
                    color: Colors.deepPurple,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        authorLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: Colors.amber.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.star_rounded,
                                  color: Colors.amber,
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  ratingValue.toStringAsFixed(1),
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.w800,
                                    fontSize: 10.8,
                                    color: Color(0xFF9A6700),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          _Stars(value: ratingValue, size: 14),
                        ],
                      ),
                    ],
                  ),
                ),
                _ReviewOptions(
                  comment: comment.toString(),
                  clientPhone: authorPhone,
                  reviewId: reviewId,
                  onReply: onReply,
                  hasProviderReply: providerReply.trim().isNotEmpty,
                  onClearReply: onClearReply,
                ),
              ],
            ),
            if (createdAt != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    size: 14,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _formatDateLabel(createdAt),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 10.5,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ],
            if (comment.toString().trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Text(
                  comment.toString(),
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ),
            ],
            if (hasProviderReply) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.deepPurple.withValues(alpha: 0.06),
                      Colors.deepPurple.withValues(alpha: 0.03),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: Colors.deepPurple.withValues(alpha: 0.15),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.reply,
                          size: 16,
                          color: Colors.deepPurple,
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'رد مقدم الخدمة',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.w800,
                            color: Colors.deepPurple,
                          ),
                        ),
                        const Spacer(),
                        if (providerReplyAt != null)
                          Text(
                            _formatDateLabel(providerReplyAt),
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 10.5,
                              color: Colors.grey.shade700,
                            ),
                          ),
                      ],
                    ),
                    if (providerReplyIsEdited) ...[
                      const SizedBox(height: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'تم تعديل الرد',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            color: Colors.orange.shade900,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 5),
                    Text(
                      providerReply,
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12.5,
                        height: 1.32,
                      ),
                    ),
                  ],
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

  static String _formatDateLabel(dynamic raw) {
    final s = raw?.toString().trim() ?? '';
    if (s.isEmpty) return '';
    final dt = DateTime.tryParse(s);
    if (dt == null) {
      return s.length > 20 ? s.substring(0, 20) : s;
    }
    const months = <int, String>{
      1: 'يناير',
      2: 'فبراير',
      3: 'مارس',
      4: 'أبريل',
      5: 'مايو',
      6: 'يونيو',
      7: 'يوليو',
      8: 'أغسطس',
      9: 'سبتمبر',
      10: 'أكتوبر',
      11: 'نوفمبر',
      12: 'ديسمبر',
    };
    final monthLabel = months[dt.month] ?? dt.month.toString();
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} $monthLabel ${dt.year} • $hh:$mm';
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
        for (int i = 0; i < full; i++)
          Icon(Icons.star, size: size, color: Colors.amber),
        if (half == 1) Icon(Icons.star_half, size: size, color: Colors.amber),
        for (int i = 0; i < empty; i++)
          Icon(Icons.star_border, size: size, color: Colors.amber),
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

enum _ReviewAction { reply, clearReply, copyText, copyPhone, report }

class _ReviewOptions extends StatelessWidget {
  final String comment;
  final String clientPhone;
  final int? reviewId;
  final Future<void> Function()? onReply;
  final bool hasProviderReply;
  final Future<void> Function()? onClearReply;

  const _ReviewOptions({
    required this.comment,
    required this.clientPhone,
    required this.reviewId,
    required this.onReply,
    required this.hasProviderReply,
    required this.onClearReply,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_ReviewAction>(
      tooltip: 'خيارات التقييم',
      position: PopupMenuPosition.under,
      onSelected: (action) async {
        switch (action) {
          case _ReviewAction.reply:
            await onReply?.call();
            return;
          case _ReviewAction.clearReply:
            await onClearReply?.call();
            return;
          case _ReviewAction.copyText:
            if (comment.trim().isEmpty) return;
            await Clipboard.setData(ClipboardData(text: comment));
            if (!context.mounted) return;
            WebInlineBannerController.instance.success('تم نسخ نص المراجعة.');
            return;
          case _ReviewAction.copyPhone:
            if (clientPhone.trim().isEmpty) return;
            await Clipboard.setData(ClipboardData(text: clientPhone));
            if (!context.mounted) return;
            WebInlineBannerController.instance.success('تم نسخ رقم العميل.');
            return;
          case _ReviewAction.report:
            try {
              final res = await SupportApi().createComplaintTicket(
                reason: 'بلاغ مراجعة',
                details: comment.trim().isEmpty
                    ? 'تم الإبلاغ عن مراجعة بدون تعليق نصي.'
                    : 'نص المراجعة: ${comment.trim()}',
                contextLabel: 'رقم العميل',
                contextValue: clientPhone.trim().isEmpty
                    ? 'غير متوفر'
                    : clientPhone.trim(),
                reportedEntityValue: 'مراجعة على ملف المزود',
                reportedKind: (reviewId == null) ? null : 'review',
                reportedObjectId: (reviewId == null)
                    ? null
                    : reviewId.toString(),
              );
              if (!context.mounted) return;
              final code = (res['code'] ?? '').toString().trim();
              WebInlineBannerController.instance.success(
                code.isEmpty ? 'تم إرسال البلاغ.' : 'تم إرسال البلاغ: $code',
              );
            } catch (_) {
              if (!context.mounted) return;
              WebInlineBannerController.instance.error(
                'تعذر إرسال البلاغ حالياً.',
              );
            }
            return;
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: _ReviewAction.reply,
          enabled: reviewId != null && onReply != null,
          child: Text(
            hasProviderReply ? 'تعديل الرد' : 'رد على المراجعة',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
        ),
        PopupMenuItem(
          value: _ReviewAction.clearReply,
          enabled: reviewId != null && onClearReply != null && hasProviderReply,
          child: const Text('حذف الرد', style: TextStyle(fontFamily: 'Cairo')),
        ),
        PopupMenuItem(
          value: _ReviewAction.copyText,
          enabled: comment.trim().isNotEmpty,
          child: const Text(
            'نسخ نص المراجعة',
            style: TextStyle(fontFamily: 'Cairo'),
          ),
        ),
        PopupMenuItem(
          value: _ReviewAction.copyPhone,
          enabled: clientPhone.trim().isNotEmpty,
          child: const Text(
            'نسخ رقم العميل',
            style: TextStyle(fontFamily: 'Cairo'),
          ),
        ),
        const PopupMenuItem(
          value: _ReviewAction.report,
          child: Text('إبلاغ', style: TextStyle(fontFamily: 'Cairo')),
        ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.more_vert, size: 18, color: Colors.grey),
          const SizedBox(width: 2),
          Text(
            'خيارات',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11,
              color: Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }
}
