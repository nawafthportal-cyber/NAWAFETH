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

    final textController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إبلاغ عن التقييم'),
        content: TextField(
          controller: textController,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'اكتب سبب البلاغ',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, textController.text.trim()),
            child: const Text('إرسال البلاغ'),
          ),
        ],
      ),
    );

    textController.dispose();
    if (reason == null || reason.isEmpty) return;

    final key = 'report_$reviewId';
    setState(() => _isActionLoading[key] = true);
    final res = await SupportService.createTicket(
      ticketType: 'complaint',
      description: reason,
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

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── ملخص التقييم المضغوط ──
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: const Color(0xFF5E35B1).withValues(alpha: 0.07),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
          ),
          child: Row(
            children: [
              // الرقم + نجوم
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    overallRating.toStringAsFixed(1),
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 38,
                      fontWeight: FontWeight.w900,
                      color: isDark
                          ? Colors.white
                          : const Color(0xFF5E35B1),
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 5),
                  _buildStars(overallRating, size: 18),
                  const SizedBox(height: 4),
                  Text(
                    '$totalReviews تقييم',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 10,
                      color: secondaryTextColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              // الفاصل
              Container(
                width: 1,
                height: 72,
                color: borderColor,
              ),
              const SizedBox(width: 16),
              // بنود التقييم
              if (totalReviews > 0)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildCriteriaRow('الاستجابة', responseSpeedAvg,
                          isDark: isDark),
                      _buildCriteriaRow('القيمة', costValueAvg,
                          isDark: isDark),
                      _buildCriteriaRow('الجودة', qualityAvg,
                          isDark: isDark),
                      _buildCriteriaRow('المصداقية', credibilityAvg,
                          isDark: isDark),
                      _buildCriteriaRow('المواعيد', onTimeAvg,
                          isDark: isDark),
                    ],
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // ── شريط الترتيب ──
        Row(
          children: [
            Text(
              'مراجعات العملاء',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: isDark ? Colors.white : const Color(0xFF12082E),
              ),
            ),
            const Spacer(),
            Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: surfaceColor,
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
                    'لا توجد مراجعات بعد',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 13,
                      color: secondaryTextColor,
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.grey[300] : Colors.grey[700],
              ),
            ),
          ),
          _buildStars(rating, size: 12),
          const SizedBox(width: 4),
          Text(
            rating.toStringAsFixed(1),
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
        ],
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
    String dateLabel = '';
    if (createdAt != null) {
      try {
        final dt = DateTime.parse(createdAt);
        final diff = DateTime.now().difference(dt);
        if (diff.inDays == 0) {
          dateLabel = 'اليوم';
        } else if (diff.inDays == 1) {
          dateLabel = 'أمس';
        } else if (diff.inDays < 7) {
          dateLabel = 'قبل ${diff.inDays} أيام';
        } else if (diff.inDays < 30) {
          dateLabel = 'قبل ${(diff.inDays / 7).floor()} أسابيع';
        } else {
          dateLabel = 'قبل ${(diff.inDays / 30).floor()} أشهر';
        }
      } catch (_) {
        dateLabel = createdAt;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: mainColor.withValues(alpha: 0.05),
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
                const SizedBox(width: 9),
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
                _buildStars(rating, size: 13),
              ],
            ),

            // ── نص التعليق ──
            if (comment.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                comment,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11.5,
                  height: 1.55,
                  color: isDark ? Colors.grey[300] : Colors.black87,
                ),
              ),
            ],

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
