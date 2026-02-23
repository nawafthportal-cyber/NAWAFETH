import 'package:flutter/material.dart';

import '../services/providers_api.dart';
import '../services/reviews_api.dart';
import '../services/support_api.dart';
import '../utils/auth_guard.dart';
import '../widgets/platform_report_dialog.dart';
import 'service_request_form_screen.dart';

class ServiceDetailScreen extends StatefulWidget {
  final String title;
  final List<String> images;
  final int? providerId;
  final String providerName;
  final String providerHandle;
  final int likes;
  final int filesCount;
  final int initialCommentsCount;

  const ServiceDetailScreen({
    super.key,
    required this.title,
    required this.images,
    this.providerId,
    this.providerName = 'مزود الخدمة',
    this.providerHandle = '@provider',
    this.likes = 0,
    this.filesCount = 0,
    this.initialCommentsCount = 0,
  });

  @override
  State<ServiceDetailScreen> createState() => _ServiceDetailScreenState();
}

class _ServiceDetailScreenState extends State<ServiceDetailScreen> {
  final ProvidersApi _providersApi = ProvidersApi();
  final ReviewsApi _reviewsApi = ReviewsApi();
  final SupportApi _supportApi = SupportApi();
  final TextEditingController _commentController = TextEditingController();

  int _currentIndex = 0;
  bool _showFullDescription = false;
  bool _showAllComments = false;
  bool _loadingComments = false;
  bool _togglingLike = false;
  bool _isLiked = false;
  late int _likesCount;
  late int _totalCommentsCount;
  final List<Map<String, dynamic>> _comments = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _likesCount = widget.likes;
    _totalCommentsCount = widget.initialCommentsCount;
    _bootstrap();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final providerId = widget.providerId;
    if (providerId == null) return;

    setState(() => _loadingComments = true);
    try {
      final rating = await _reviewsApi.getProviderRatingSummary(providerId);
      final reviews = await _reviewsApi.getProviderReviews(providerId);
      final liked = await _providersApi.getMyLikedProviders();

      if (!mounted) return;
      setState(() {
        _isLiked = liked.any((p) => p.id == providerId);
        _likesCount = _asInt(rating['likes_count']) ?? _likesCount;
        _totalCommentsCount = reviews.length;
        _comments
          ..clear()
          ..addAll(
            reviews.map((r) => {
                  'reviewId': r['id'],
                  'name': (r['client_name'] ?? r['client_phone'] ?? 'مستخدم').toString(),
                  'comment': (r['comment'] ?? '').toString(),
                  'rating': _asDouble(r['rating']),
                  'isLiked': false,
                }),
          );
      });
    } catch (_) {
      // keep defaults
    } finally {
      if (mounted) {
        setState(() => _loadingComments = false);
      }
    }
  }

  Future<void> _toggleProviderLike() async {
    final providerId = widget.providerId;
    if (providerId == null || _togglingLike) return;
    if (!await checkAuth(context)) return;

    setState(() => _togglingLike = true);
    final next = !_isLiked;
    final ok = next
        ? await _providersApi.likeProvider(providerId)
        : await _providersApi.unlikeProvider(providerId);

    if (!mounted) return;
    setState(() {
      _togglingLike = false;
      if (ok) {
        _isLiked = next;
        _likesCount = (_likesCount + (next ? 1 : -1)).clamp(0, 1 << 31);
      }
    });
  }

  void _submitComment() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('إضافة تعليق متاحة بعد إكمال الطلب عبر التقييم.')),
    );
  }

  Future<void> _submitComplaintFromDialog({
    required String reason,
    required String details,
    required String reportedEntity,
    String? contextLabel,
    String? contextValue,
    String? reportedKind,
    String? reportedObjectId,
  }) async {
    if (!await checkAuth(context)) return;
    try {
      final res = await _supportApi.createComplaintTicket(
        reason: reason,
        details: details,
        reportedEntityValue: reportedEntity,
        contextLabel: contextLabel,
        contextValue: contextValue,
        reportedKind: reportedKind,
        reportedObjectId: reportedObjectId,
      );
      if (!mounted) return;
      final code = (res['code'] ?? '').toString().trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            code.isEmpty ? 'تم إرسال البلاغ بنجاح' : 'تم إرسال البلاغ: $code',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر إرسال البلاغ حالياً')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const mainColor = Colors.deepPurple;
    final int videoCount = widget.filesCount > 0 ? 1 : 0;
    final int imageCount = widget.filesCount > 1 ? (widget.filesCount - 1) : widget.filesCount;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.grey[100],
        appBar: AppBar(
          backgroundColor: mainColor,
          title: Text(widget.title, style: const TextStyle(fontFamily: 'Cairo')),
        ),
        body: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _providerHeader(),
              const SizedBox(height: 16),
              _titleLikeCard(mainColor),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _contentTile(icon: Icons.movie_creation_outlined, title: 'فيديو', count: videoCount, mainColor: mainColor)),
                  const SizedBox(width: 12),
                  Expanded(child: _contentTile(icon: Icons.image_outlined, title: 'صور', count: imageCount, mainColor: mainColor)),
                ],
              ),
              const SizedBox(height: 12),
              _gallery(mainColor),
              const SizedBox(height: 16),
              _descriptionCard(),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    if (!await checkFullClient(context)) return;
                    if (!context.mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ServiceRequestFormScreen(
                          providerName: widget.providerName,
                          providerId: widget.providerId?.toString(),
                          initialTitle: widget.title,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.add_circle_outline, color: Colors.white),
                  label: const Text('طلب الخدمة', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: mainColor,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _commentsSection(mainColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _providerHeader() {
    return Row(
      children: [
        const CircleAvatar(
          radius: 26,
          child: Icon(Icons.person),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(widget.providerName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(width: 4),
                const Icon(Icons.verified, color: Colors.green, size: 18),
              ],
            ),
            Text(widget.providerHandle, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ],
        ),
        const Spacer(),
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          onPressed: () {
            showPlatformReportDialog(
              context: context,
              title: 'إبلاغ عن محتوى خدمة',
              reportedEntityLabel: 'الخدمة:',
              reportedEntityValue: widget.title,
              contextLabel: 'مزود الخدمة',
              contextValue: '${widget.providerName} (${widget.providerHandle})',
              onSubmit: ({required reason, required details}) {
                return _submitComplaintFromDialog(
                  reason: reason,
                  details: details,
                  reportedEntity: widget.title,
                  contextLabel: 'مزود الخدمة',
                  contextValue: '${widget.providerName} (${widget.providerHandle})',
                );
              },
            );
          },
          icon: const Icon(Icons.flag_outlined, size: 18),
          label: const Text('إبلاغ'),
        ),
      ],
    );
  }

  Widget _titleLikeCard(Color mainColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.3),
            ),
          ),
          Row(
            children: [
              Text(
                '$_likesCount',
                style: TextStyle(fontSize: 13, color: _isLiked ? mainColor : Colors.grey[700], fontWeight: FontWeight.w600),
              ),
              IconButton(
                onPressed: _togglingLike ? null : _toggleProviderLike,
                icon: Icon(_isLiked ? Icons.thumb_up_alt : Icons.thumb_up_alt_outlined, size: 20, color: _isLiked ? mainColor : Colors.grey.shade700),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _gallery(Color mainColor) {
    if (widget.images.isEmpty) {
      return Container(
        height: 220,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(child: Text('لا توجد صور')),
      );
    }
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                widget.images[_currentIndex],
                fit: BoxFit.cover,
                width: double.infinity,
                height: 220,
              ),
            ),
            Positioned(
              left: 10,
              child: _navArrow(Icons.arrow_back_ios, () {
                setState(() => _currentIndex = (_currentIndex - 1 + widget.images.length) % widget.images.length);
              }),
            ),
            Positioned(
              right: 10,
              child: _navArrow(Icons.arrow_forward_ios, () {
                setState(() => _currentIndex = (_currentIndex + 1) % widget.images.length);
              }),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 60,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: widget.images.length,
            itemBuilder: (context, index) {
              return GestureDetector(
                onTap: () => setState(() => _currentIndex = index),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: _currentIndex == index ? mainColor : Colors.transparent, width: 2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(widget.images[index], width: 70, fit: BoxFit.cover),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _descriptionCard() {
    return GestureDetector(
      onTap: () => setState(() => _showFullDescription = !_showFullDescription),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black12.withValues(alpha: 0.05),
              blurRadius: 5,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.description_outlined, color: Colors.deepPurple),
                SizedBox(width: 8),
                Text('التفاصيل', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _showFullDescription
                  ? 'هذه الخدمة تتضمن شرحًا تفصيليًا لمجال الخدمة، مع تفاصيل أكثر يمكن أن تأتي من الباكند.'
                  : 'اضغط لعرض تفاصيل الخدمة...',
              style: const TextStyle(fontSize: 14, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contentTile({
    required IconData icon,
    required String title,
    required int count,
    required Color mainColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: mainColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: mainColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('$count', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.grey.shade800)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _commentsSection(Color mainColor) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('💬 التعليقات على القسم ($_totalCommentsCount)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 12),
          if (_loadingComments)
            const Center(child: CircularProgressIndicator())
          else if (_comments.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text('لا توجد تعليقات حالياً.', style: TextStyle(color: Colors.grey)),
            )
          else
            Column(
              children: _comments
                  .take(_showAllComments ? _comments.length : 3)
                  .map((c) => _commentTile(c, mainColor))
                  .toList(),
            ),
          if (!_showAllComments && _comments.length > 3)
            TextButton(
              onPressed: () => setState(() => _showAllComments = true),
              child: const Text('عرض المزيد من التعليقات'),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commentController,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _submitComment(),
                  decoration: InputDecoration(
                    hintText: 'أضف تعليقك على القسم...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ),
              IconButton(onPressed: _submitComment, icon: const Icon(Icons.send, color: Colors.deepPurple)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _commentTile(Map<String, dynamic> c, Color mainColor) {
    final isLiked = c['isLiked'] == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: Colors.grey,
            child: const Icon(Icons.person, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text((c['name'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(width: 8),
                    Text(
                      _asDouble(c['rating']).toStringAsFixed(1),
                      style: const TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.star, size: 14, color: Colors.amber),
                  ],
                ),
                Text((c['comment'] ?? '').toString(), style: const TextStyle(fontSize: 13, height: 1.4)),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 18),
            onSelected: (value) {
              if (value == 'like') {
                setState(() => c['isLiked'] = !isLiked);
              } else if (value == 'report') {
                final rawReviewId = c['reviewId'];
                final reviewId = (rawReviewId is int)
                    ? rawReviewId
                    : int.tryParse(rawReviewId?.toString() ?? '');
                showPlatformReportDialog(
                  context: context,
                  title: 'إبلاغ عن تعليق',
                  reportedEntityLabel: 'التعليق:',
                  reportedEntityValue: '${c['name'] ?? ''}: ${c['comment'] ?? ''}',
                  contextLabel: 'الخدمة',
                  contextValue: widget.title,
                  onSubmit: ({required reason, required details}) {
                    return _submitComplaintFromDialog(
                      reason: reason,
                      details: details,
                      reportedEntity: '${c['name'] ?? ''}: ${c['comment'] ?? ''}',
                      contextLabel: 'الخدمة',
                      contextValue: widget.title,
                      reportedKind: reviewId == null ? null : 'review',
                      reportedObjectId: reviewId == null ? null : reviewId.toString(),
                    );
                  },
                );
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'like', child: Text(isLiked ? 'إلغاء الإعجاب' : 'الإعجاب')),
              const PopupMenuItem(value: 'report', child: Text('الإبلاغ عن التعليق')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _navArrow(IconData icon, VoidCallback onTap) {
    return CircleAvatar(
      backgroundColor: Colors.black.withValues(alpha: 0.5),
      child: IconButton(icon: Icon(icon, color: Colors.white, size: 18), onPressed: onTap),
    );
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
