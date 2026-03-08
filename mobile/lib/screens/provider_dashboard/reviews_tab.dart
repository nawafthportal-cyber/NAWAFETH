import 'package:flutter/material.dart';

import 'package:nawafeth/services/reviews_service.dart';
import 'package:nawafeth/services/profile_service.dart';

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
        child: CircularProgressIndicator(color: Colors.deepPurple),
      );
    }

    if (_errorMessage != null) {
      return _buildErrorState();
    }

    final content = Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ⭐ التقييم العام
          Center(
            child: Column(
              children: [
                Text(
                  overallRating.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 60,
                    fontWeight: FontWeight.bold,
                    color: Colors.deepPurple,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 6),
                _buildStars(overallRating, size: 34),
                const SizedBox(height: 6),
                Text(
                  "بناءً على $totalReviews مراجعة",
                  style: const TextStyle(color: Colors.black54, fontSize: 14),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),

          if (totalReviews > 0)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'تفصيل البنود',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildCriteriaRow('سرعة الاستجابة', responseSpeedAvg),
                  _buildCriteriaRow('التكلفة مقابل الخدمة', costValueAvg),
                  _buildCriteriaRow('جودة الخدمة', qualityAvg),
                  _buildCriteriaRow('المصداقية', credibilityAvg),
                  _buildCriteriaRow('وقت الإنجاز', onTimeAvg),
                ],
              ),
            ),

          const SizedBox(height: 20),
          const Text(
            'مراجعات العملاء',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              fontFamily: 'Cairo',
            ),
          ),
          const SizedBox(height: 12),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _sortOption,
                isExpanded: true,
                borderRadius: BorderRadius.circular(12),
                items: const [
                  DropdownMenuItem(value: 'الأحدث', child: Text('الأحدث')),
                  DropdownMenuItem(
                    value: 'الأعلى تقييماً',
                    child: Text('الأعلى تقييماً'),
                  ),
                  DropdownMenuItem(
                    value: 'الأقل تقييماً',
                    child: Text('الأقل تقييماً'),
                  ),
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
          const SizedBox(height: 20),
          if (_reviews.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(Icons.reviews_outlined, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text(
                      'لا توجد مراجعات بعد',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 16,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._reviews.map((review) => _buildReviewTile(review)),
        ],
      ),
    );

    if (widget.embedded) {
      return content;
    }

    return RefreshIndicator(
      onRefresh: () => _loadData(silent: true),
      color: Colors.deepPurple,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: content,
      ),
    );
  }

  // 📊 بند تقييم فردي
  Widget _buildCriteriaRow(String title, double rating) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ),
          _buildStars(rating, size: 18),
          const SizedBox(width: 6),
          Text(
            rating.toStringAsFixed(1),
            style: const TextStyle(fontSize: 13, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  // 💬 مراجعة عميل (من API)
  Widget _buildReviewTile(Map<String, dynamic> review) {
    final reviewId = review['id'] as int;
    final reviewKey = reviewId.toString();
    final clientName = review['client_name'] as String? ?? 'عميل';
    final rating = _toDouble(review['rating']);
    final comment = review['comment'] as String? ?? '';
    final providerReply = (review['provider_reply'] as String? ?? '').trim();
    final providerReplyAt = review['provider_reply_at'] as String?;
    final isEdited = review['provider_reply_is_edited'] as bool? ?? false;
    final createdAt = review['created_at'] as String?;

    _replyControllers.putIfAbsent(reviewKey, () => TextEditingController());

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
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.deepPurple.shade100,
                  child: Text(
                    clientName.isNotEmpty ? clientName.characters.first : '?',
                    style: const TextStyle(
                      color: Colors.deepPurple,
                      fontWeight: FontWeight.bold,
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
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          fontFamily: 'Cairo',
                        ),
                      ),
                      Text(
                        dateLabel,
                        style: const TextStyle(
                          color: Colors.black45,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildStars(rating, size: 18),
              ],
            ),
            if (comment.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(comment,
                  style: const TextStyle(fontSize: 14, height: 1.4)),
            ],

            // عرض الرد الحالي (من API)
            if (providerReply.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.deepPurple.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.verified,
                            size: 16, color: Colors.deepPurple),
                        const SizedBox(width: 6),
                        const Text(
                          'رد من مقدم الخدمة',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.deepPurple,
                            fontFamily: 'Cairo',
                          ),
                        ),
                        if (isEdited) ...[
                          const SizedBox(width: 6),
                          const Text(
                            '(معدّل)',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.black45,
                            ),
                          ),
                        ],
                        const Spacer(),
                        if (providerReplyAt != null)
                          Text(
                            _formatDate(providerReplyAt),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.black45,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      providerReply,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (_canReply) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _toggleReply(reviewKey),
                  icon: const Icon(Icons.reply,
                      size: 18, color: Colors.deepPurple),
                  label: Text(
                    providerReply.isEmpty ? "رد" : "تعديل الرد",
                    style: const TextStyle(color: Colors.deepPurple),
                  ),
                ),
              ),
              if (_isReplying[reviewKey] ?? false) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _replyControllers[reviewKey],
                  decoration: InputDecoration(
                    hintText: "اكتب ردك هنا...",
                    hintStyle: const TextStyle(fontFamily: 'Cairo'),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: _isReplySending
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () =>
                              _submitReply(reviewId, reviewKey),
                          child: const Text(
                            "إرسال",
                            style: TextStyle(
                                color: Colors.white, fontFamily: 'Cairo'),
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
        appBar: AppBar(
          backgroundColor: Colors.deepPurple,
          elevation: 0,
          centerTitle: true,
          title: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'المراجعات',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  fontFamily: 'Cairo',
                ),
              ),
              if (totalReviews > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    "$totalReviews",
                    style:
                        const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ],
            ],
          ),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: _buildBody(context),
      ),
    );
  }
}
