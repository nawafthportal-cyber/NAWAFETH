// ignore_for_file: unused_element
import 'package:flutter/material.dart';

import 'package:nawafeth/services/reviews_service.dart';
import 'package:nawafeth/services/profile_service.dart';
import 'package:nawafeth/services/support_service.dart';
import 'package:nawafeth/screens/chat_detail_screen.dart';
import 'package:nawafeth/widgets/platform_top_bar.dart';

import 'provider_order_details_screen.dart';

class ReviewsTab extends StatefulWidget {
  const ReviewsTab({
    super.key,
    this.embedded = false,
    this.onOpenChat,
    this.providerId,
  });

  final bool embedded;

  final Future<void> Function(String customerName)? onOpenChat;
  final int? providerId;

  @override
  State<ReviewsTab> createState() => _ReviewsTabState();
}

class _ReviewsTabState extends State<ReviewsTab> {
  static const List<String> _reportReasons = [
    'ألفاظ غير لائقة أو مسيئة',
    'معلومات غير صحيحة أو مضللة',
    'ابتزاز أو تهديد',
    'إفشاء معلومات شخصية',
    'التقييم لا يخص الخدمة المنفذة',
    'أخرى',
  ];

  // ────── حالة التحميل ──────
  bool _isLoading = true;
  bool _isReplySending = false;
  String? _errorMessage;

  // ────── بيانات من API ──────
  int? _providerId;
  double overallRating = 0.0;
  int totalReviews = 0;
  double responseSpeedAvg = 0.0;
  double costValueAvg = 0.0;
  double qualityAvg = 0.0;
  double credibilityAvg = 0.0;
  double onTimeAvg = 0.0;
  Map<String, int> _ratingDistribution = const {
    '1': 0,
    '2': 0,
    '3': 0,
    '4': 0,
    '5': 0,
  };

  List<Map<String, dynamic>> _reviews = [];

  String _sortOption = 'الأحدث';
  final Map<String, bool> _isReplying = {};
  final Map<String, TextEditingController> _replyControllers = {};
  final Map<String, bool> _isActionLoading = {};
  bool get _canReply => widget.providerId == null;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    for (final c in _replyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    // إذا تم تمرير providerId من شاشة عامة نستخدمه مباشرة،
    // وإلا نرجع لسلوك "مزودي أنا".
    _providerId = widget.providerId;
    if (_providerId == null) {
      final meResult = await ProfileService.fetchMyProfile();
      if (!mounted) return;

      if (!meResult.isSuccess || meResult.data == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = meResult.error ?? 'تعذر جلب بيانات المستخدم';
        });
        return;
      }

      _providerId = meResult.data!.providerProfileId;
      if (_providerId == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'لا يوجد ملف مزود مرتبط بحسابك';
        });
        return;
      }
    }

    // جلب التقييمات + ملخص التقييم
    final results = await Future.wait([
      ReviewsService.fetchProviderReviews(_providerId!),
      ReviewsService.fetchProviderRating(_providerId!),
    ]);

    if (!mounted) return;

    // المراجعات
    final reviewsRes = results[0];
    if (reviewsRes.isSuccess) {
      final list = reviewsRes.dataAsList ??
          (reviewsRes.dataAsMap?['results'] as List?) ??
          [];
      _reviews = list.cast<Map<String, dynamic>>();
    }

    // ملخص التقييم
    final ratingRes = results[1];
    if (ratingRes.isSuccess && ratingRes.dataAsMap != null) {
      final d = ratingRes.dataAsMap!;
      overallRating = _toDouble(d['rating_avg']);
      totalReviews = d['rating_count'] as int? ?? 0;
      responseSpeedAvg = _toDouble(d['response_speed_avg']);
      costValueAvg = _toDouble(d['cost_value_avg']);
      qualityAvg = _toDouble(d['quality_avg']);
      credibilityAvg = _toDouble(d['credibility_avg']);
      onTimeAvg = _toDouble(d['on_time_avg']);
      final rawDistribution = d['distribution'] as Map<String, dynamic>?;
      _ratingDistribution = {
        for (var rating = 1; rating <= 5; rating++)
          '$rating': int.tryParse(
                (rawDistribution?['$rating'] ?? 0).toString(),
              ) ??
              0,
      };
    }

    _applySorting();

    setState(() => _isLoading = false);
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  void _applySorting() {
    switch (_sortOption) {
      case 'الأعلى تقييماً':
        _reviews.sort((a, b) =>
            (_toDouble(b['rating'])).compareTo(_toDouble(a['rating'])));
        break;
      case 'الأقل تقييماً':
        _reviews.sort((a, b) =>
            (_toDouble(a['rating'])).compareTo(_toDouble(b['rating'])));
        break;
      default: // الأحدث
        _reviews.sort((a, b) {
          final aId = a['id'] as int? ?? 0;
          final bId = b['id'] as int? ?? 0;
          return bId.compareTo(aId);
        });
    }
  }

  /// إرسال رد على مراجعة عبر API
  Future<void> _submitReply(int reviewId, String reviewKey) async {
    if (!_canReply) return;
    final text = _replyControllers[reviewKey]?.text.trim() ?? '';
    if (text.isEmpty) return;

    setState(() => _isReplySending = true);

    final res = await ReviewsService.replyToReview(reviewId, text);

    if (!mounted) return;
    setState(() => _isReplySending = false);

    if (res.isSuccess) {
      _replyControllers[reviewKey]?.clear();
      setState(() => _isReplying[reviewKey] = false);
      _showSnack('تم إرسال الرد بنجاح');
      // تحديث البيانات
      _loadData(silent: true);
    } else {
      _showSnack(res.error ?? 'فشل في إرسال الرد', isError: true);
    }
  }

  void _toggleReply(String key) {
    setState(() {
      _isReplying[key] = !(_isReplying[key] ?? false);
    });
  }

  Future<void> _openChat(String customerName) async {
    if (widget.onOpenChat != null) {
      await widget.onOpenChat!(customerName);
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ميزة المحادثة غير مفعلة هنا.')),
    );
  }

  Future<void> _toggleLike(Map<String, dynamic> review) async {
    if (!_canReply) return;
    final reviewId = review['id'] as int?;
    if (reviewId == null) return;
    final key = 'like_$reviewId';
    setState(() => _isActionLoading[key] = true);

    final currentLiked = review['provider_liked'] as bool? ?? false;
    final res = await ReviewsService.toggleProviderLike(
      reviewId,
      liked: !currentLiked,
    );

    if (!mounted) return;
    setState(() => _isActionLoading[key] = false);

    if (!res.isSuccess) {
      _showSnack(res.error ?? 'تعذر تحديث الإعجاب', isError: true);
      return;
    }

    final data = res.dataAsMap ?? {};
    review['provider_liked'] = data['provider_liked'] ?? !currentLiked;
    review['provider_liked_at'] = data['provider_liked_at'];
    setState(() {});
  }

  Future<void> _openReviewChat(Map<String, dynamic> review) async {
    if (!_canReply) return;
    final reviewId = review['id'] as int?;
    if (reviewId == null) return;

    final key = 'chat_$reviewId';
    setState(() => _isActionLoading[key] = true);

    final res = await ReviewsService.getOrCreateProviderReviewChatThread(reviewId);
    if (!mounted) return;
    setState(() => _isActionLoading[key] = false);

    if (!res.isSuccess) {
      _showSnack(res.error ?? 'تعذر فتح المحادثة', isError: true);
      return;
    }

    final threadId = res.dataAsMap?['thread_id'] as int?;
    if (threadId == null) {
      _showSnack('تعذر فتح المحادثة', isError: true);
      return;
    }

    final customerName = (review['client_name'] as String?)?.trim();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatDetailScreen(
          threadId: threadId,
          peerName: (customerName != null && customerName.isNotEmpty)
              ? customerName
              : 'العميل',
          peerId: review['client_id'] as int?,
        ),
      ),
    );
  }

  Future<void> _openClientRequest(Map<String, dynamic> review) async {
    final requestId = review['request_id'] as int?;
    if (requestId == null) {
      _showSnack('لا يمكن تحديد الطلب المرتبط بهذا التقييم', isError: true);
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProviderOrderDetailsScreen(requestId: requestId),
      ),
    );
  }

  Future<void> _reportReview(Map<String, dynamic> review) async {
    if (!_canReply) return;
    final reviewId = review['id'] as int?;
    if (reviewId == null) return;

    final reportDescription = await _openReportDialog(review);
    if (reportDescription == null || reportDescription.isEmpty) return;

    final key = 'report_$reviewId';
    setState(() => _isActionLoading[key] = true);
    final res = await SupportService.createTicket(
      ticketType: 'complaint',
      description: reportDescription,
      reportedKind: 'review',
      reportedObjectId: '$reviewId',
      reportedUser: review['client_id'] as int?,
    );

    if (!mounted) return;
    setState(() => _isActionLoading[key] = false);
    if (res.isSuccess) {
      _showSnack('تم إرسال البلاغ بنجاح');
      return;
    }
    _showSnack(res.error ?? 'تعذر إرسال البلاغ', isError: true);
  }

  Future<String?> _openReportDialog(Map<String, dynamic> review) async {
    String selectedReason = '';
    final detailsController = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final reviewText = (review['comment'] as String? ?? '').trim();
            final reviewerName =
                (review['client_name'] as String?)?.trim().isNotEmpty == true
                    ? (review['client_name'] as String).trim()
                    : 'العميل';
            final dateLabel = _reviewRelativeDateLabel(review['created_at'] as String?);
            final detailsLength = detailsController.text.trim().length;
            final canSubmit = selectedReason.trim().isNotEmpty;

            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                insetPadding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
                titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                title: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'إبلاغ عن تقييم',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'سيصل البلاغ إلى إدارة المحتوى لمراجعة هذا التقييم واتخاذ الإجراء المناسب.',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        height: 1.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        reviewerName,
                                        style: const TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      if (dateLabel.isNotEmpty)
                                        Text(
                                          dateLabel,
                                          style: const TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: 10.5,
                                            color: Color(0xFF64748B),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                _buildStars(
                                  _toDouble(review['rating']),
                                  size: 14,
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              reviewText.isNotEmpty
                                  ? reviewText
                                  : 'لا يوجد نص مرفق في هذا التقييم.',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11.5,
                                height: 1.6,
                                color: reviewText.isNotEmpty
                                    ? const Color(0xFF1F2937)
                                    : const Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'سبب البلاغ',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue:
                            selectedReason.isEmpty ? null : selectedReason,
                        decoration: InputDecoration(
                          hintText: 'اختر سبب البلاغ',
                          hintStyle: const TextStyle(fontFamily: 'Cairo'),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide:
                                const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                        ),
                        items: _reportReasons
                            .map(
                              (reason) => DropdownMenuItem<String>(
                                value: reason,
                                child: Text(
                                  reason,
                                  style: const TextStyle(fontFamily: 'Cairo'),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setDialogState(() {
                            selectedReason = value ?? '';
                          });
                        },
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'تفاصيل إضافية',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: detailsController,
                        maxLines: 5,
                        maxLength: 500,
                        onChanged: (_) => setDialogState(() {}),
                        decoration: InputDecoration(
                          hintText: 'اشرح لنا باختصار ما المشكلة في هذا التقييم...',
                          hintStyle: const TextStyle(fontFamily: 'Cairo'),
                          filled: true,
                          fillColor: Colors.white,
                          counterText: '',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide:
                                const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                        ),
                        style: const TextStyle(fontFamily: 'Cairo'),
                      ),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'كلما كان الوصف أوضح، كانت المراجعة أسرع.',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 10.5,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ),
                          Text(
                            '$detailsLength / 500',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: detailsLength >= 450
                                  ? Colors.red.shade400
                                  : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'إلغاء',
                      style: TextStyle(fontFamily: 'Cairo'),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: canSubmit
                        ? () {
                            final details = detailsController.text.trim();
                            final description = details.isEmpty
                                ? 'سبب البلاغ: $selectedReason'
                                : 'سبب البلاغ: $selectedReason\n\nتفاصيل إضافية:\n$details';
                            Navigator.pop(context, description);
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5E35B1),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text(
                      'إرسال البلاغ',
                      style: TextStyle(fontFamily: 'Cairo'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    detailsController.dispose();
    return result;
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(msg, style: const TextStyle(fontFamily: 'Cairo')),
            ),
          ],
        ),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ⭐ بناء النجوم
  Widget _buildStars(double rating, {double size = 22}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        if (index < rating.floor()) {
          return Icon(Icons.star, color: Colors.amber, size: size);
        } else if (index < rating) {
          return Icon(Icons.star_half, color: Colors.amber, size: size);
        } else {
          return Icon(
            Icons.star_border,
            color: Colors.grey.shade400,
            size: size,
          );
        }
      }),
    );
  }

  List<MapEntry<String, double>> _criteriaEntries() {
    return [
      MapEntry('الاستجابة', responseSpeedAvg),
      MapEntry('القيمة', costValueAvg),
      MapEntry('الجودة', qualityAvg),
      MapEntry('المصداقية', credibilityAvg),
      MapEntry('المواعيد', onTimeAvg),
    ];
  }

  String _topCriteriaLabel() {
    if (totalReviews <= 0) return 'بانتظار أول تقييم';
    final sorted = _criteriaEntries().toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.first;
    if (top.value <= 0) return 'بانتظار أول تقييم';
    return '${top.key} ${top.value.toStringAsFixed(1)}';
  }

  int _countReviewsWithReply() {
    return _reviews.where((review) {
      final reply = (review['provider_reply'] ?? review['reply'] ?? '')
          .toString()
          .trim();
      return reply.isNotEmpty;
    }).length;
  }

  int _countLikedReviews() {
    return _reviews.where((review) => review['provider_liked'] == true).length;
  }

  ({String label, String value}) _featuredMetric() {
    final scored = [
      MapEntry('جودة العمل', qualityAvg),
      MapEntry('سرعة الاستجابة', responseSpeedAvg),
      MapEntry('القيمة مقابل السعر', costValueAvg),
      MapEntry('المصداقية', credibilityAvg),
      MapEntry('الالتزام بالمواعيد', onTimeAvg),
    ]..sort((a, b) => b.value.compareTo(a.value));

    if (scored.isNotEmpty && scored.first.value > 0) {
      return (
        label: scored.first.key,
        value: '${scored.first.value.toStringAsFixed(1)} / 5',
      );
    }

    return (label: 'أفضل محور', value: 'بانتظار بيانات');
  }

  String _ratingDescriptor() {
    if (totalReviews <= 0 || overallRating <= 0) {
      return 'لا توجد بيانات كافية بعد، وسيتم تحديث المؤشرات فور وصول تقييمات العملاء.';
    }
    if (overallRating >= 4.8) {
      return 'مستوى استثنائي يعكس رضا عاليًا جدًا وثقة قوية من العملاء.';
    }
    if (overallRating >= 4.4) {
      return 'أداء ممتاز ومتوازن مع انطباع احترافي ثابت عبر التجارب.';
    }
    if (overallRating >= 4.0) {
      return 'تقييم قوي يدل على جودة واضحة وتجربة مرضية في أغلب الطلبات.';
    }
    if (overallRating >= 3.5) {
      return 'النتيجة جيدة، مع مساحة واضحة لتعزيز بعض المحاور للوصول لمستوى أعلى.';
    }
    return 'النتيجة الحالية تحتاج إلى مزيد من التحسين ورفع جودة التجربة في المحاور الأضعف.';
  }

  String _toolbarNoteLabel() {
    if (totalReviews <= 0) {
      return 'لا توجد تقييمات منشورة بعد، وسيظهر السجل هنا فور وصول أول تقييم.';
    }
    return 'إجمالي $totalReviews تقييم، منها ${_countReviewsWithReply()} تقييمات لديها رد من مقدم الخدمة.';
  }

  String _reviewRelativeDateLabel(String? createdAt) {
    if (createdAt == null || createdAt.trim().isEmpty) return '';
    try {
      final dt = DateTime.parse(createdAt);
      final diff = DateTime.now().difference(dt);
      if (diff.inDays == 0) {
        return 'اليوم';
      }
      if (diff.inDays == 1) {
        return 'أمس';
      }
      if (diff.inDays < 7) {
        return 'قبل ${diff.inDays} أيام';
      }
      if (diff.inDays < 30) {
        return 'قبل ${(diff.inDays / 7).floor()} أسابيع';
      }
      return 'قبل ${(diff.inDays / 30).floor()} أشهر';
    } catch (_) {
      return createdAt;
    }
  }

  List<MapEntry<String, double>> _reviewCriteriaEntries(
      Map<String, dynamic> review) {
    final entries = [
      MapEntry('الاستجابة', _toDouble(review['response_speed'])),
      MapEntry('الجودة', _toDouble(review['quality'])),
      MapEntry('السعر', _toDouble(review['cost_value'])),
      MapEntry('المصداقية', _toDouble(review['credibility'])),
      MapEntry('المواعيد', _toDouble(review['on_time'])),
    ];
    return entries.where((entry) => entry.value > 0).toList();
  }

  Widget _buildReviewCriteriaChips(
    Map<String, dynamic> review, {
    required bool isDark,
  }) {
    final criteria = _reviewCriteriaEntries(review);
    if (criteria.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: criteria
          .map(
            (entry) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.10)
                      : const Color(0xFFE2E8F0),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.value.toStringAsFixed(1),
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : const Color(0xFF12082E),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    entry.key,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.grey[300] : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  String _trustScoreLabel() {
    if (totalReviews <= 0) return '0%';
    final percent = ((overallRating.clamp(0, 5) / 5) * 100).round();
    return '$percent%';
  }

  Widget _buildOverviewChip({
    required IconData icon,
    required String label,
    required String value,
    required bool isDark,
    Color accent = const Color(0xFF5E35B1),
  }) {
    final bgColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : accent.withValues(alpha: 0.08);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : accent.withValues(alpha: 0.14);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: accent),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : const Color(0xFF12082E),
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.grey[400] : Colors.grey[700],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricStripCard({
    required String label,
    required String value,
    required bool isDark,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : accent.withValues(alpha: 0.14),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.grey[400] : const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDistributionPanel(bool isDark) {
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : const Color(0xFFE2E8F0);
    final subtitleColor = isDark ? Colors.grey[400] : const Color(0xFF64748B);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'كيف جاءت التقييمات؟',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : const Color(0xFF12082E),
            ),
          ),
          const SizedBox(height: 10),
          ...List.generate(5, (index) {
            final rating = 5 - index;
            final count = _ratingDistribution['$rating'] ?? 0;
            final percent = totalReviews > 0 ? ((count / totalReviews) * 100).round() : 0;

            return Padding(
              padding: EdgeInsets.only(bottom: index == 4 ? 0 : 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 54,
                    child: Text(
                      '$rating نجوم',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: subtitleColor,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: totalReviews > 0 ? count / totalReviews : 0,
                        minHeight: 9,
                        backgroundColor: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : const Color(0xFFE5E7EB),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF14B8A6),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 56,
                    child: Text(
                      '$count • $percent%',
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: subtitleColor,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildPageHeader(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : const Color(0xFFE2E8F0),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFF5E35B1).withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'تجربة العملاء',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF5E35B1),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'التقييمات',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: isDark ? Colors.white : const Color(0xFF12082E),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'لوحة مراجعة موحدة لقراءة الانطباع العام، تحليل المحاور، واستعراض أحدث آراء العملاء بشكل أوضح.',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        height: 1.6,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.grey[400] : Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF5E35B1), Color(0xFF14B8A6)],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: [
                    const Text(
                      'مؤشر الثقة',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _trustScoreLabel(),
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : const Color(0xFFE2E8F0),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.insights_rounded,
                  color: isDark ? Colors.white70 : const Color(0xFF5E35B1),
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'قراءة أسرع: ملخص ثابت بالأعلى مع قائمة تقييمات أوضح للوصول السريع إلى الرد والمحادثة.',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11.5,
                      height: 1.55,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.grey[300] : const Color(0xFF475569),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF5E35B1)),
      );
    }

    if (_errorMessage != null) {
      return _buildErrorState();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.white;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : const Color(0xFFE2E8F0);
    final secondaryTextColor =
        isDark ? Colors.grey[400] : Colors.grey[600];
    final featuredMetric = _featuredMetric();

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.embedded) ...[
          _buildPageHeader(isDark),
          const SizedBox(height: 12),
        ],
        // ── ملخص التقييم الأنيق ──
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: isDark
                ? null
                : const LinearGradient(
                    colors: [Color(0xFFFFFFFF), Color(0xFFF7FBFF)],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
            color: isDark ? surfaceColor : null,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF5E35B1).withValues(
                  alpha: isDark ? 0.08 : 0.10,
                ),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'انطباع العملاء',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color:
                                isDark ? Colors.white : const Color(0xFF12082E),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _ratingDescriptor(),
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 10.5,
                            height: 1.5,
                            color: secondaryTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF5E35B1), Color(0xFF14B8A6)],
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                      ),
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF5E35B1)
                              .withValues(alpha: 0.22),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Text(
                          overallRating.toStringAsFixed(1),
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 6),
                        _buildStars(overallRating, size: 15),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _buildOverviewChip(
                    icon: Icons.reviews_rounded,
                    label: 'إجمالي المراجعات',
                    value: '$totalReviews',
                    isDark: isDark,
                  ),
                  _buildOverviewChip(
                    icon: Icons.auto_awesome_rounded,
                    label: 'أقوى نقطة',
                    value: _topCriteriaLabel(),
                    isDark: isDark,
                    accent: const Color(0xFF14B8A6),
                  ),
                  _buildOverviewChip(
                    icon: Icons.reply_all_rounded,
                    label: 'ردودك المنشورة',
                    value: '${_countReviewsWithReply()}',
                    isDark: isDark,
                    accent: const Color(0xFFF59E0B),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 2.3,
                children: [
                  _buildMetricStripCard(
                    label: 'إجمالي التقييمات',
                    value: '$totalReviews',
                    isDark: isDark,
                    accent: const Color(0xFF5E35B1),
                  ),
                  _buildMetricStripCard(
                    label: 'ردودك المنشورة',
                    value: '${_countReviewsWithReply()}',
                    isDark: isDark,
                    accent: const Color(0xFF14B8A6),
                  ),
                  _buildMetricStripCard(
                    label: 'تقييمات أعجبتك',
                    value: '${_countLikedReviews()}',
                    isDark: isDark,
                    accent: const Color(0xFFF59E0B),
                  ),
                  _buildMetricStripCard(
                    label: featuredMetric.label,
                    value: featuredMetric.value,
                    isDark: isDark,
                    accent: const Color(0xFF0EA5A4),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _buildDistributionPanel(isDark),
              if (totalReviews > 0) ...[
                const SizedBox(height: 16),
                ..._criteriaEntries().map(
                  (entry) => _buildCriteriaRow(
                    entry.key,
                    entry.value,
                    isDark: isDark,
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 12),

        // ── شريط الترتيب ──
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'مراجعات العملاء',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : const Color(0xFF12082E),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_reviews.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : const Color(0xFFF3F7FB),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: borderColor),
                      ),
                      child: Text(
                        '${_reviews.length}',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                          color:
                              isDark ? Colors.white : const Color(0xFF5E35B1),
                        ),
                      ),
                    ),
                  const Spacer(),
                  Container(
                    height: 34,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.03)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: borderColor),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _sortOption,
                        isDense: true,
                        borderRadius: BorderRadius.circular(12),
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        items: const [
                          DropdownMenuItem(
                              value: 'الأحدث', child: Text('الأحدث')),
                          DropdownMenuItem(
                              value: 'الأعلى تقييماً',
                              child: Text('الأعلى تقييماً')),
                          DropdownMenuItem(
                              value: 'الأقل تقييماً',
                              child: Text('الأقل تقييماً')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _sortOption = value;
                              _applySorting();
                            });
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _toolbarNoteLabel(),
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 10.8,
                  height: 1.5,
                  fontWeight: FontWeight.w700,
                  color: secondaryTextColor,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        if (_reviews.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.reviews_outlined,
                      size: 42, color: Colors.grey.shade400),
                  const SizedBox(height: 10),
                  Text(
                    'لا توجد تقييمات حتى الآن',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: secondaryTextColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: 280,
                    child: Text(
                      'عند وصول أول تقييم من العملاء ستظهر هنا البطاقات التفصيلية مع الملخص العام والمحاور.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11.5,
                        height: 1.55,
                        color: secondaryTextColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ..._reviews.map((review) => _buildReviewTile(review)),
      ],
    );

    if (widget.embedded) {
      return content;
    }

    return RefreshIndicator(
      onRefresh: () => _loadData(silent: true),
      color: const Color(0xFF5E35B1),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: content,
      ),
    );
  }

  // 📊 بند تقييم فردي — مضغوط
  Widget _buildCriteriaRow(String title, double rating,
      {bool isDark = false}) {
    final value = rating.clamp(0, 5);
    final progress = value / 5;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : const Color(0xFFE5E7EB),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.grey[200] : const Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 7,
                      backgroundColor: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : const Color(0xFFE5E7EB),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF14B8A6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF5E35B1).withValues(
                  alpha: isDark ? 0.20 : 0.08,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Text(
                value.toStringAsFixed(1),
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : const Color(0xFF5E35B1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 💬 مراجعة عميل (من API) — مضغوطة
  Widget _buildReviewTile(Map<String, dynamic> review) {
    final reviewId = review['id'] as int;
    final reviewKey = reviewId.toString();
    final clientName = review['client_name'] as String? ?? 'عميل';
    final rating = _toDouble(review['rating']);
    final comment = review['comment'] as String? ?? '';
    final providerReply = (review['provider_reply'] as String? ?? '').trim();
    final providerReplyAt = review['provider_reply_at'] as String?;
    final isEdited = review['provider_reply_is_edited'] as bool? ?? false;
    final providerLiked = review['provider_liked'] as bool? ?? false;
    final requestId = review['request_id'] as int?;
    final createdAt = review['created_at'] as String?;

    _replyControllers.putIfAbsent(reviewKey, () => TextEditingController());

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor =
        isDark ? Colors.white.withValues(alpha: 0.07) : Colors.white;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : const Color(0xFFE2E8F0);
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.grey[400] : Colors.grey[600];
    const mainColor = Color(0xFF5E35B1);

    // تنسيق تاريخ
    final dateLabel = _reviewRelativeDateLabel(createdAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        gradient: isDark
            ? null
            : const LinearGradient(
                colors: [Color(0xFFFFFFFF), Color(0xFFFCFDFF)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
        color: isDark ? surfaceColor : null,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: mainColor.withValues(alpha: isDark ? 0.06 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── رأس المراجعة ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: mainColor.withValues(alpha: 0.14),
                  child: Text(
                    clientName.isNotEmpty
                        ? clientName.characters.first
                        : '؟',
                    style: const TextStyle(
                      color: mainColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        clientName,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                          color: textColor,
                        ),
                      ),
                      if (dateLabel.isNotEmpty)
                        Text(
                          dateLabel,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 10,
                            color: subtitleColor,
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: isDark ? 0.18 : 0.14),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.amber.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star_rounded,
                          size: 15, color: Colors.amber),
                      const SizedBox(width: 4),
                      Text(
                        rating.toStringAsFixed(1),
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                          color:
                              isDark ? Colors.white : const Color(0xFF7C5200),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),
            _buildStars(rating, size: 14),

            if (requestId != null || providerLiked) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (requestId != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: borderColor),
                      ),
                      child: Text(
                        'طلب #$requestId',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color:
                              isDark ? Colors.grey[300] : const Color(0xFF475569),
                        ),
                      ),
                    ),
                  if (providerLiked)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: mainColor.withValues(alpha: isDark ? 0.20 : 0.10),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: mainColor.withValues(alpha: 0.18),
                        ),
                      ),
                      child: const Text(
                        'تم تمييزه',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: mainColor,
                        ),
                      ),
                    ),
                ],
              ),
            ],

            if (_reviewCriteriaEntries(review).isNotEmpty) ...[
              const SizedBox(height: 10),
              _buildReviewCriteriaChips(review, isDark: isDark),
            ],

            // ── نص التعليق ──
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.04)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                comment.isNotEmpty
                    ? comment
                    : 'لم يترك العميل تعليقًا نصيًا، وتم تسجيل التقييم الرقمي فقط.',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11.5,
                  height: 1.7,
                  color: comment.isNotEmpty
                      ? (isDark ? Colors.grey[300] : Colors.black87)
                      : (isDark ? Colors.grey[400] : const Color(0xFF94A3B8)),
                ),
              ),
            ),

            // ── أزرار الإجراءات (مضغوطة) ──
            if (_canReply) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  _actionChip(
                    icon: providerLiked
                        ? Icons.thumb_up
                        : Icons.thumb_up_outlined,
                    label: providerLiked ? 'معجب' : 'إعجاب',
                    active: providerLiked,
                    loading:
                        _isActionLoading['like_$reviewId'] ?? false,
                    onTap: () => _toggleLike(review),
                    isDark: isDark,
                  ),
                  const SizedBox(width: 6),
                  _actionChip(
                    icon: Icons.chat_bubble_outline_rounded,
                    label: 'شات',
                    loading:
                        _isActionLoading['chat_$reviewId'] ?? false,
                    onTap: () => _openReviewChat(review),
                    isDark: isDark,
                  ),
                  if (requestId != null) ...[
                    const SizedBox(width: 6),
                    _actionChip(
                      icon: Icons.assignment_outlined,
                      label: 'الطلب',
                      onTap: () => _openClientRequest(review),
                      isDark: isDark,
                    ),
                  ],
                  const Spacer(),
                  _actionChip(
                    icon: Icons.flag_outlined,
                    label: 'إبلاغ',
                    loading:
                        _isActionLoading['report_$reviewId'] ?? false,
                    onTap: () => _reportReview(review),
                    isDark: isDark,
                    isDestructive: true,
                  ),
                ],
              ),
            ],

            // ── الرد الحالي ──
            if (providerReply.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: mainColor.withValues(alpha: isDark ? 0.12 : 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: mainColor.withValues(alpha: 0.18),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.verified,
                            size: 13, color: mainColor),
                        const SizedBox(width: 5),
                        Text(
                          'رد مقدم الخدمة',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                            color: mainColor,
                          ),
                        ),
                        if (isEdited) ...[
                          const SizedBox(width: 5),
                          Text(
                            '(معدّل)',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 9.5,
                              color: subtitleColor,
                            ),
                          ),
                        ],
                        const Spacer(),
                        if (providerReplyAt != null)
                          Text(
                            _formatDate(providerReplyAt),
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 9.5,
                              color: subtitleColor,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      providerReply,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        height: 1.5,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── زر/نموذج الرد ──
            if (_canReply) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: () => _toggleReply(reviewKey),
                  child: Text(
                    providerReply.isEmpty ? '+ رد' : '• تعديل الرد',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: mainColor,
                    ),
                  ),
                ),
              ),
              if (_isReplying[reviewKey] ?? false) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _replyControllers[reviewKey],
                  decoration: InputDecoration(
                    hintText: 'اكتب ردك هنا...',
                    hintStyle: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      color: subtitleColor,
                    ),
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.grey.shade50,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          BorderSide(color: borderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          BorderSide(color: borderColor),
                    ),
                  ),
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: textColor,
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: _isReplySending
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: mainColor),
                        )
                      : GestureDetector(
                          onTap: () => _submitReply(reviewId, reviewKey),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: mainColor,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              'إرسال',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _actionChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool isDark,
    bool active = false,
    bool loading = false,
    bool isDestructive = false,
  }) {
    const mainColor = Color(0xFF5E35B1);
    final fgColor = isDestructive
        ? Colors.red.shade400
        : (active ? mainColor : (isDark ? Colors.grey[300]! : Colors.grey[700]!));
    final bgColor = active
        ? mainColor.withValues(alpha: isDark ? 0.22 : 0.10)
        : (isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.grey.shade100);
    final borderCol = active
        ? mainColor.withValues(alpha: 0.28)
        : (isDark
            ? Colors.white.withValues(alpha: 0.10)
            : Colors.grey.shade300);

    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: borderCol),
        ),
        child: loading
            ? SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                    strokeWidth: 1.5, color: fgColor),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 12, color: fgColor),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: fgColor,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  String _formatDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoDate;
    }
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'حدث خطأ',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 14,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh, color: Colors.white),
              label: const Text(
                'إعادة المحاولة',
                style: TextStyle(fontFamily: 'Cairo', color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: _buildBody(context),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: PlatformTopBar(
          overlay: true,
          pageLabel: 'المراجعات',
          showBackButton: true,
          showNotificationAction: false,
          showChatAction: false,
          trailingActions: [
            if (totalReviews > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$totalReviews',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
          ],
        ),
        body: _buildBody(context),
      ),
    );
  }
}
