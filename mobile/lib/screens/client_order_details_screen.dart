import 'dart:async';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:flutter_rating_bar/flutter_rating_bar.dart';

import '../models/client_order.dart';
import '../models/offer.dart';
import '../services/chat_nav.dart';
import '../services/marketplace_api.dart';
import '../services/reviews_api.dart';

class ClientOrderDetailsScreen extends StatefulWidget {
  final ClientOrder order;

  const ClientOrderDetailsScreen({super.key, required this.order});

  @override
  State<ClientOrderDetailsScreen> createState() =>
      _ClientOrderDetailsScreenState();
}

class _ClientOrderDetailsScreenState extends State<ClientOrderDetailsScreen> {
  static const Color _mainColor = Colors.deepPurple;
  late ClientOrder _order;

  late final TextEditingController _titleController;
  late final TextEditingController _detailsController;
  final TextEditingController _reminderController = TextEditingController();

  bool _editTitle = false;
  bool _editDetails = false;

  bool _cancelOrder = false;
  bool _reopenCanceledOrder = false;
  bool _approveProviderInputs = false;
  bool _rejectProviderInputs = false;
  bool _isSaving = false;

  bool _showRatingForm = false;
  late double _ratingResponseSpeed;
  late double _ratingCostValue;
  late double _ratingQuality;
  late double _ratingCredibility;
  late double _ratingOnTime;
  final TextEditingController _ratingCommentController =
      TextEditingController();
  bool _isSubmittingReview = false;
  bool _didSubmitReview = false;

  List<Offer> _offers = [];
  bool _isLoadingOffers = false;
  Timer? _autoRefreshTimer;

  bool _hasReview(ClientOrder order) {
    if (order.reviewId != null && order.reviewId! > 0) return true;
    final criteria = <double?>[
      order.ratingResponseSpeed,
      order.ratingCostValue,
      order.ratingQuality,
      order.ratingCredibility,
      order.ratingOnTime,
    ];
    return criteria.any((v) => v != null && v > 0);
  }

  @override
  void initState() {
    super.initState();
    _order = widget.order;
    _titleController = TextEditingController(text: _order.title);
    _detailsController = TextEditingController(text: _order.details);

    _ratingResponseSpeed = _order.ratingResponseSpeed ?? 0;
    _ratingCostValue = _order.ratingCostValue ?? 0;
    _ratingQuality = _order.ratingQuality ?? 0;
    _ratingCredibility = _order.ratingCredibility ?? 0;
    _ratingOnTime = _order.ratingOnTime ?? 0;
    _ratingCommentController.text = _order.ratingComment ?? '';
    _didSubmitReview = _hasReview(_order);

    _refreshFromBackend();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _refreshFromBackend(silent: true);
    });
  }

  int? _requestIdValue() => int.tryParse(_order.id.replaceAll('#', '').trim());

  Future<void> _refreshFromBackend({bool silent = false}) async {
    await Future.wait([
      _syncOrderFromBackend(silent: silent),
      _fetchOffers(silent: silent),
    ]);
  }

  Future<void> _syncOrderFromBackend({bool silent = false}) async {
    try {
      final requestId = _requestIdValue();
      if (requestId == null) return;

      final data = await MarketplaceApi().getMyRequestDetail(
        requestId: requestId,
      );
      if (data == null) return;

      final fresh = ClientOrder.fromJson(data);
      if (!mounted) return;
      setState(() {
        _order = fresh;
        _didSubmitReview = _hasReview(fresh);
        if (_didSubmitReview) {
          _showRatingForm = false;
        }
        if (!_editTitle) _titleController.text = fresh.title;
        if (!_editDetails) _detailsController.text = fresh.details;
        _approveProviderInputs = fresh.providerInputsApproved == true;
        _rejectProviderInputs = fresh.providerInputsApproved == false;
      });
    } catch (_) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تعذر تحديث بيانات الطلب حالياً',
              style: TextStyle(fontFamily: 'Cairo'),
            ),
          ),
        );
      }
    }
  }

  bool _isValidCriterion(double value) => value >= 1 && value <= 5;

  String? _extractErrorMessage(dynamic data) {
    if (data is Map) {
      for (final entry in data.entries) {
        final v = entry.value;
        if (v is List && v.isNotEmpty) {
          return v.first.toString();
        }
        if (v is String && v.trim().isNotEmpty) {
          return v;
        }
      }
    }
    if (data is String && data.trim().isNotEmpty) return data;
    return null;
  }

  Future<void> _submitReview() async {
    if (_isSubmittingReview) return;

    if (_order.status != 'مكتمل') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'لا يمكن إرسال التقييم إلا بعد اكتمال الطلب',
            style: TextStyle(fontFamily: 'Cairo'),
          ),
        ),
      );
      return;
    }

    final requestId = _requestIdValue();
    if (requestId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'لا يمكن إرسال التقييم: رقم الطلب غير صالح',
            style: TextStyle(fontFamily: 'Cairo'),
          ),
        ),
      );
      return;
    }

    final values = <double>[
      _ratingResponseSpeed,
      _ratingCostValue,
      _ratingQuality,
      _ratingCredibility,
      _ratingOnTime,
    ];
    if (!values.every(_isValidCriterion)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'فضلاً اختر تقييمًا لكل خيار (من 1 إلى 5)',
            style: TextStyle(fontFamily: 'Cairo'),
          ),
        ),
      );
      return;
    }

    setState(() => _isSubmittingReview = true);
    try {
      await ReviewsApi().createReview(
        requestId: requestId,
        responseSpeed: _ratingResponseSpeed.round(),
        costValue: _ratingCostValue.round(),
        quality: _ratingQuality.round(),
        credibility: _ratingCredibility.round(),
        onTime: _ratingOnTime.round(),
        comment: _ratingCommentController.text,
      );

      _didSubmitReview = true;
      _showRatingForm = false;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تم إرسال التقييم بنجاح',
            style: TextStyle(fontFamily: 'Cairo'),
          ),
        ),
      );
      // Do not chain review submission to the generic request save flow.
      // _save() can fail on unrelated request actions (reminders/updates),
      // which makes a successful review look like it failed.
      try {
        await _refreshFromBackend(silent: true);
      } catch (_) {
        // Best effort only; the review has already been created.
      }
    } on DioException catch (e) {
      if (!mounted) return;
      final msg =
          _extractErrorMessage(e.response?.data) ?? 'تعذر إرسال التقييم';
      final lower = msg.toLowerCase();
      if (lower.contains('تم تقييم هذا الطلب') || lower.contains('مسبق')) {
        setState(() {
          _didSubmitReview = true;
          _showRatingForm = false;
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg, style: const TextStyle(fontFamily: 'Cairo')),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تعذر إرسال التقييم',
            style: TextStyle(fontFamily: 'Cairo'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmittingReview = false);
    }
  }

  Future<void> _fetchOffers({bool silent = false}) async {
    // Only fetch offers if order is active/new
    if (_order.status == 'جديد' || _order.status == 'أُرسل') {
      if (!silent) setState(() => _isLoadingOffers = true);
      try {
        final offers = await MarketplaceApi().getRequestOffers(_order.id);
        if (mounted) {
          setState(() {
            _offers = offers;
          });
        }
      } catch (e) {
        debugPrint('Error fetching offers: $e');
      } finally {
        if (mounted && !silent) {
          setState(() => _isLoadingOffers = false);
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _offers = const [];
          _isLoadingOffers = false;
        });
      }
    }
  }

  Future<void> _acceptOffer(Offer offer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('قبول العرض'),
          content: Text('هل أنت متأكد من قبول عرض بقيمة ${offer.price} ريال؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تأكيد القبول'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('جاري قبول العرض...')));

      final success = await MarketplaceApi().acceptOffer(offer.id);
      if (success && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم قبول العرض بنجاح')));
        await _refreshFromBackend();
        if (!mounted) return;
        Navigator.pop(context, _order.copyWith(status: 'جديد'));
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('فشل قبول العرض')));
      }
    }
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _titleController.dispose();
    _detailsController.dispose();
    _reminderController.dispose();
    _ratingCommentController.dispose();
    super.dispose();
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'مكتمل':
        return Colors.green;
      case 'ملغي':
        return Colors.red;
      case 'بانتظار اعتماد العميل':
      case 'تحت التنفيذ':
        return Colors.orange;
      case 'جديد':
      case 'أُرسل':
        return Colors.amber.shade800;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat('HH:mm  dd/MM/yyyy', 'ar').format(date);
  }

  void _openChat() {
    final requestId = _requestIdValue();
    if (requestId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'رقم الطلب غير صالح لفتح المحادثة',
            style: TextStyle(fontFamily: 'Cairo'),
          ),
        ),
      );
      return;
    }

    ChatNav.openThread(
      context,
      requestId: requestId,
      name: (_order.providerName ?? '').trim().isEmpty
          ? 'مقدم الخدمة'
          : _order.providerName!.trim(),
      isOnline: false,
      requestCode: _order.id,
      requestTitle: _order.title,
    );
  }

  Future<void> _save({bool fromReviewFlow = false}) async {
    if (_isSaving) return;
    final requestId = _requestIdValue();
    if (requestId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'رقم الطلب غير صالح',
            style: TextStyle(fontFamily: 'Cairo'),
          ),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final api = MarketplaceApi();
      bool didAnyAction = false;
      String successMessage = 'تم حفظ التغييرات بنجاح';

      if (_reopenCanceledOrder && _order.status == 'ملغي') {
        final ok = await api.reopenMyRequest(
          requestId: requestId,
          note: _reminderController.text.trim(),
        );
        if (!ok) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'تعذر إعادة فتح الطلب حالياً',
                style: TextStyle(fontFamily: 'Cairo'),
              ),
            ),
          );
          return;
        }
        didAnyAction = true;
        successMessage = 'تمت إعادة فتح الطلب كطلب جديد';
      }

      final canCancelOrder =
          _order.status == 'جديد' || _order.status == 'بانتظار اعتماد العميل';
      if (!_reopenCanceledOrder && _cancelOrder && canCancelOrder) {
        final ok = await api.cancelMyRequest(
          requestId: requestId,
          note: _reminderController.text.trim(),
        );
        if (!ok) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'تعذر إلغاء الطلب حالياً',
                style: TextStyle(fontFamily: 'Cairo'),
              ),
            ),
          );
          return;
        }
        didAnyAction = true;
        successMessage = 'تم إلغاء الطلب بنجاح';
      }

      if (!_cancelOrder && !_reopenCanceledOrder) {
        final title = _titleController.text.trim();
        final details = _detailsController.text.trim();
        final titleChanged = title.isNotEmpty && title != _order.title;
        final detailsChanged = details.isNotEmpty && details != _order.details;

        if (titleChanged || detailsChanged) {
          final updated = await api.updateMyRequestDetail(
            requestId: requestId,
            title: titleChanged ? title : null,
            description: detailsChanged ? details : null,
          );
          if (updated == null) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'تعذر تحديث بيانات الطلب حالياً',
                  style: TextStyle(fontFamily: 'Cairo'),
                ),
              ),
            );
            return;
          }
          didAnyAction = true;
          successMessage = 'تم تحديث بيانات الطلب';
        }
      }

      final canDecideProviderInputs =
          _order.status == 'بانتظار اعتماد العميل' &&
          _order.providerInputsApproved == null;
      if (!_cancelOrder &&
          !_reopenCanceledOrder &&
          canDecideProviderInputs &&
          (_approveProviderInputs || _rejectProviderInputs)) {
        final ok = await api.submitProviderInputsDecision(
          requestId: requestId,
          approved: _approveProviderInputs,
          note: _reminderController.text.trim(),
        );
        if (!ok) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'تعذر إرسال قرار الاعتماد/الرفض حالياً',
                style: TextStyle(fontFamily: 'Cairo'),
              ),
            ),
          );
          return;
        }
        didAnyAction = true;
        successMessage = _approveProviderInputs
            ? 'تم اعتماد مدخلات مقدم الخدمة'
            : 'تم رفض مدخلات مقدم الخدمة';
      }

      if (!_cancelOrder &&
          !_reopenCanceledOrder &&
          _reminderController.text.trim().isNotEmpty &&
          !(canDecideProviderInputs &&
              (_approveProviderInputs || _rejectProviderInputs))) {
        if ((_order.providerName ?? '').trim().isEmpty) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'لا يمكن إرسال تذكير قبل تعيين مقدم خدمة للطلب',
                style: TextStyle(fontFamily: 'Cairo'),
              ),
            ),
          );
          return;
        }
        final ok = await api.sendRequestReminder(
          requestId: requestId,
          message: _reminderController.text,
        );
        if (!ok) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'تعذر إرسال التذكير حالياً',
                style: TextStyle(fontFamily: 'Cairo'),
              ),
            ),
          );
          return;
        }
        didAnyAction = true;
        successMessage = 'تم إرسال التذكير للمختص';
      }

      if (!didAnyAction) {
        successMessage = fromReviewFlow
            ? 'تم إرسال التقييم بنجاح'
            : 'لا توجد تغييرات للحفظ';
      }

      await _refreshFromBackend(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            successMessage,
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, _order);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _formatDateOnly(DateTime date) {
    return DateFormat('dd/MM/yyyy', 'ar').format(date);
  }

  String _formatMoney(double? value) {
    if (value == null) return '-';
    final formatted = value.toStringAsFixed(0);
    return '$formatted (SR)';
  }

  Widget _ratingRow({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
    required bool compact,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: compact ? 12 : 13,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          RatingBar.builder(
            initialRating: value,
            minRating: 0,
            allowHalfRating: false,
            itemCount: 5,
            itemSize: compact ? 18 : 20,
            itemPadding: const EdgeInsets.symmetric(horizontal: 1.5),
            itemBuilder: (context, _) =>
                const Icon(Icons.star, color: Colors.amber),
            onRatingUpdate: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _infoRow({required String label, required String value}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
        color: Colors.transparent,
      ),
      child: Text(
        value,
        style: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _infoLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _sectionHeader({
    required String title,
    required bool canEdit,
    required bool isEditing,
    required VoidCallback onToggle,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (canEdit)
          TextButton(
            onPressed: onToggle,
            child: Text(
              isEditing ? 'إيقاف' : 'تعديل',
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < 370;
    final pagePadding = isCompact ? 12.0 : 16.0;
    final cardPadding = isCompact ? 12.0 : 14.0;
    final cardRadius = isCompact ? 12.0 : 14.0;
    final statusColor = _statusColor(_order.status);
    final canEditOrderFields =
        _order.status == 'جديد' || _order.status == 'أُرسل';
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final borderColor = isDark ? Colors.white10 : Colors.grey.shade200;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF121212) : Colors.grey[100],
        appBar: AppBar(
          backgroundColor: _mainColor,
          title: const Text(
            'تفاصيل الطلب',
            style: TextStyle(fontFamily: 'Cairo', color: Colors.white),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            IconButton(
              onPressed: _openChat,
              tooltip: 'فتح محادثة',
              icon: const Icon(Icons.chat_bubble_outline, color: Colors.white),
            ),
            IconButton(
              onPressed: _refreshFromBackend,
              tooltip: 'تحديث',
              icon: const Icon(Icons.refresh, color: Colors.white),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refreshFromBackend,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.all(pagePadding),
                    children: [
                      // Header card
                      Container(
                        padding: EdgeInsets.all(cardPadding),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(cardRadius),
                          border: Border.all(color: borderColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _order.id,
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: statusColor.withValues(
                                        alpha: 0.35,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    _order.status,
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: statusColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${_order.title} ${_order.serviceCode}',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 13,
                                color: isDark ? Colors.white70 : Colors.black54,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _formatDate(_order.createdAt),
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 12,
                                color: isDark ? Colors.white54 : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      if ((_order.latestStatusNote ?? '').trim().isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: borderColor),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.campaign_outlined,
                                    color: _mainColor,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text(
                                      'آخر تحديث من مقدم الخدمة',
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _order.latestStatusNote!.trim(),
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                  color: isDark ? Colors.white70 : Colors.black87,
                                ),
                              ),
                              if (_order.latestStatusAt != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  _formatDate(_order.latestStatusAt!),
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 11,
                                    color: isDark ? Colors.white54 : Colors.black54,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // Offers Section
                      if (_isLoadingOffers)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(8.0),
                            child: CircularProgressIndicator(),
                          ),
                        ),

                      if (!_isLoadingOffers &&
                          (_order.status == 'جديد' ||
                              _order.status == 'أُرسل') &&
                          _offers.isNotEmpty) ...[
                        Text(
                          'العروض المستلمة (${_offers.length})',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ..._offers.map((offer) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: EdgeInsets.all(isCompact ? 10 : 12),
                            decoration: BoxDecoration(
                              color: cardColor,
                              border: Border.all(
                                color: Colors.green.withValues(alpha: 0.5),
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        offer.providerName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'Cairo',
                                          fontSize: isCompact ? 12 : 13,
                                          color: isDark
                                              ? Colors.white
                                              : Colors.black,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${offer.price} ريال',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green,
                                        fontSize: isCompact ? 12 : 13,
                                        fontFamily: 'Cairo',
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'المدة: ${offer.durationDays} يوم',
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: isCompact ? 11 : 12,
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.black87,
                                  ),
                                ),
                                if (offer.note.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'ملاحظات: ${offer.note}',
                                    style: TextStyle(
                                      fontSize: isCompact ? 11 : 12,
                                      color: Colors.grey,
                                      fontFamily: 'Cairo',
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: () => _acceptOffer(offer),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: const Text(
                                      'قبول العرض',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontFamily: 'Cairo',
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 14),
                      ],

                      // Completed order: actual delivery + actual amount + rating entry
                      if (_order.status == 'مكتمل')
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: borderColor),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _infoLabel('موعد التسليم الفعلي'),
                              _infoRow(
                                label: 'موعد التسليم الفعلي',
                                value: _order.deliveredAt == null
                                    ? '-'
                                    : _formatDateOnly(_order.deliveredAt!),
                              ),
                              const SizedBox(height: 10),
                              _infoLabel('قيمة الخدمة الفعلية (SR)'),
                              _infoRow(
                                label: 'قيمة الخدمة الفعلية (SR)',
                                value: _formatMoney(
                                  _order.actualServiceAmountSR,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: _didSubmitReview
                                      ? Colors.green.withValues(alpha: 0.10)
                                      : _mainColor.withValues(alpha: 0.07),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: _didSubmitReview
                                        ? Colors.green.withValues(alpha: 0.35)
                                        : _mainColor.withValues(alpha: 0.25),
                                  ),
                                ),
                                child: Text(
                                  _didSubmitReview
                                      ? 'تم تقييم الطلب مسبقاً.'
                                      : 'تنبيه: يرجى مراجعة الطلب وتقييم الخدمة.',
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: _didSubmitReview
                                        ? Colors.green.shade700
                                        : _mainColor,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: _didSubmitReview
                                      ? null
                                      : () => setState(
                                            () =>
                                                _showRatingForm = !_showRatingForm,
                                          ),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    side: BorderSide(
                                      color: _didSubmitReview
                                          ? Colors.green.shade600
                                          : _mainColor,
                                    ),
                                  ),
                                  icon: Icon(
                                    _didSubmitReview
                                        ? Icons.verified_rounded
                                        : Icons.rate_review_outlined,
                                    color: _didSubmitReview
                                        ? Colors.green.shade700
                                        : _mainColor,
                                  ),
                                  label: Text(
                                    _didSubmitReview
                                        ? 'تم التقييم مسبقاً'
                                        : 'تقييم الخدمة',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.bold,
                                      color: _didSubmitReview
                                          ? Colors.green.shade700
                                          : _mainColor,
                                    ),
                                  ),
                                ),
                              ),
                              if (_showRatingForm && !_didSubmitReview) ...[
                                const SizedBox(height: 12),
                                _ratingRow(
                                  label: 'سرعة الاستجابة',
                                  value: _ratingResponseSpeed,
                                  compact: isCompact,
                                  onChanged: (v) =>
                                      setState(() => _ratingResponseSpeed = v),
                                ),
                                _ratingRow(
                                  label: 'التكلفة مقابل الخدمة',
                                  value: _ratingCostValue,
                                  compact: isCompact,
                                  onChanged: (v) =>
                                      setState(() => _ratingCostValue = v),
                                ),
                                _ratingRow(
                                  label: 'جودة الخدمة',
                                  value: _ratingQuality,
                                  compact: isCompact,
                                  onChanged: (v) =>
                                      setState(() => _ratingQuality = v),
                                ),
                                _ratingRow(
                                  label: 'المصداقية',
                                  value: _ratingCredibility,
                                  compact: isCompact,
                                  onChanged: (v) =>
                                      setState(() => _ratingCredibility = v),
                                ),
                                _ratingRow(
                                  label: 'وقت الإنجاز',
                                  value: _ratingOnTime,
                                  compact: isCompact,
                                  onChanged: (v) =>
                                      setState(() => _ratingOnTime = v),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'تعليق على الخدمة المقدمة (300 حرف)',
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: _ratingCommentController,
                                  maxLength: 300,
                                  buildCounter:
                                      (
                                        context, {
                                        required currentLength,
                                        required isFocused,
                                        maxLength,
                                      }) => null,
                                  minLines: isCompact ? 2 : 3,
                                  maxLines: isCompact ? 4 : 5,
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                  ),
                                  style: const TextStyle(fontFamily: 'Cairo'),
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: _isSubmittingReview
                                        ? null
                                        : _submitReview,
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      backgroundColor: _mainColor,
                                    ),
                                    child: _isSubmittingReview
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Text(
                                            'إرسال التقييم',
                                            style: TextStyle(
                                              fontFamily: 'Cairo',
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),

                      if (_order.status == 'مكتمل') const SizedBox(height: 12),

                      // Under execution / waiting approval extra fields
                      if (_order.status == 'تحت التنفيذ' ||
                          _order.status == 'بانتظار اعتماد العميل')
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: borderColor),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _infoLabel('موعد التسليم المتوقع'),
                              _infoRow(
                                label: 'موعد التسليم المتوقع',
                                value: _order.expectedDeliveryAt == null
                                    ? '-'
                                    : _formatDateOnly(
                                        _order.expectedDeliveryAt!,
                                      ),
                              ),
                              const SizedBox(height: 10),
                              _infoLabel('قيمة الخدمة المقدرة (SR)'),
                              _infoRow(
                                label: 'قيمة الخدمة المقدرة (SR)',
                                value: _formatMoney(_order.serviceAmountSR),
                              ),
                              const SizedBox(height: 10),
                              _infoLabel('المبلغ المستلم (SR)'),
                              _infoRow(
                                label: 'المبلغ المستلم (SR)',
                                value: _formatMoney(_order.receivedAmountSR),
                              ),
                              const SizedBox(height: 10),
                              _infoLabel('المبلغ المتبقي (SR)'),
                              _infoRow(
                                label: 'المبلغ المتبقي (SR)',
                                value: _formatMoney(_order.remainingAmountSR),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'البيانات المدخلة من مقدم الخدمة',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.white54
                                      : Colors.black54,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 12,
                                children: [
                                  Checkbox(
                                    value: _approveProviderInputs,
                                    onChanged: (_order.status !=
                                                'بانتظار اعتماد العميل' ||
                                            _order.providerInputsApproved !=
                                                null)
                                        ? null
                                        : (v) {
                                      setState(() {
                                        _approveProviderInputs = v ?? false;
                                        if (_approveProviderInputs) {
                                          _rejectProviderInputs = false;
                                        }
                                      });
                                    },
                                  ),
                                  const Text(
                                    'اعتماد',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Checkbox(
                                    value: _rejectProviderInputs,
                                    onChanged: (_order.status !=
                                                'بانتظار اعتماد العميل' ||
                                            _order.providerInputsApproved !=
                                                null)
                                        ? null
                                        : (v) {
                                      setState(() {
                                        _rejectProviderInputs = v ?? false;
                                        if (_rejectProviderInputs) {
                                          _approveProviderInputs = false;
                                        }
                                      });
                                    },
                                  ),
                                  const Text(
                                    'رفض',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _order.providerInputsApproved == null
                                    ? 'بانتظار قرار العميل على مدخلات المزود'
                                    : (_order.providerInputsApproved!
                                          ? 'تم اعتماد مدخلات المزود'
                                          : 'تم رفض مدخلات المزود'),
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: _order.providerInputsApproved == null
                                      ? (isDark
                                            ? Colors.white54
                                            : Colors.black54)
                                      : (_order.providerInputsApproved!
                                            ? Colors.green
                                            : Colors.red),
                                ),
                              ),
                            ],
                          ),
                        ),

                      if (_order.status == 'تحت التنفيذ' ||
                          _order.status == 'بانتظار اعتماد العميل')
                        const SizedBox(height: 12),
                      if (_order.status == 'جديد' ||
                          _order.status == 'بانتظار اعتماد العميل')
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: borderColor),
                          ),
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            children: [
                              Checkbox(
                                value: _cancelOrder,
                                onChanged: (v) => setState(
                                  () => _cancelOrder = v ?? false,
                                ),
                              ),
                              const Text(
                                'إلغاء الطلب',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (_order.status == 'جديد' ||
                          _order.status == 'بانتظار اعتماد العميل')
                        const SizedBox(height: 12),

                      // Canceled extra fields
                      if (_order.status == 'ملغي')
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: borderColor),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _infoLabel('تاريخ الإلغاء'),
                              _infoRow(
                                label: 'تاريخ الإلغاء',
                                value: _order.canceledAt == null
                                    ? '-'
                                    : _formatDateOnly(_order.canceledAt!),
                              ),
                              const SizedBox(height: 10),
                              _infoLabel('سبب الإلغاء'),
                              _infoRow(
                                label: 'سبب الإلغاء',
                                value: _order.cancelReason ?? '-',
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                children: [
                                  Checkbox(
                                    value: _reopenCanceledOrder,
                                    onChanged: (v) => setState(
                                      () => _reopenCanceledOrder = v ?? false,
                                    ),
                                  ),
                                  const Text(
                                    'إعادة فتح الطلب (كطلب جديد)',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      if (_order.status == 'ملغي') const SizedBox(height: 12),

                      // Title section
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: borderColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _sectionHeader(
                              title: 'عنوان الطلب',
                              canEdit: canEditOrderFields,
                              isEditing: _editTitle,
                              onToggle: () =>
                                  setState(() => _editTitle = !_editTitle),
                            ),
                            TextField(
                              controller: _titleController,
                              enabled: _editTitle && canEditOrderFields,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                              ),
                              style: const TextStyle(fontFamily: 'Cairo'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Details section
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: borderColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _sectionHeader(
                              title: 'تفاصيل الطلب',
                              canEdit: canEditOrderFields,
                              isEditing: _editDetails,
                              onToggle: () =>
                                  setState(() => _editDetails = !_editDetails),
                            ),
                            TextField(
                              controller: _detailsController,
                              enabled: _editDetails && canEditOrderFields,
                              minLines: isCompact ? 3 : 4,
                              maxLines: isCompact ? 5 : 7,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                              ),
                              style: const TextStyle(fontFamily: 'Cairo'),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              canEditOrderFields
                                  ? 'تنبيه: سيتم إشعار مقدم الخدمة بأي تعديل في بيانات الطلب.'
                                  : 'لا يمكن تعديل بيانات الطلب في هذه المرحلة.',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 12,
                                color: isDark ? Colors.white54 : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Attachments section
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: borderColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'المرفقات',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (_order.attachments.isEmpty)
                              Text(
                                'لا يوجد مرفقات',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  color: isDark
                                      ? Colors.white54
                                      : Colors.black54,
                                ),
                              )
                            else
                              ..._order.attachments.map(
                                (a) => Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.attach_file,
                                        size: 18,
                                        color: Colors.grey,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          a.name,
                                          style: TextStyle(
                                            fontFamily: 'Cairo',
                                            color: isDark
                                                ? Colors.white70
                                                : Colors.black87,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        a.type,
                                        style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 12,
                                          color: isDark
                                              ? Colors.white54
                                              : Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Reminder section (bell + dashed area look-alike)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: borderColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.notifications_none,
                                  color: _mainColor,
                                ),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'ارسال تنبيه وتذكير للمختص',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _reminderController,
                              minLines: isCompact ? 4 : 6,
                              maxLines: isCompact ? 7 : 10,
                              decoration: InputDecoration(
                                hintText: 'اكتب رسالتك هنا...',
                                hintStyle: const TextStyle(fontFamily: 'Cairo'),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              style: const TextStyle(fontFamily: 'Cairo'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Bottom buttons
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(color: Colors.grey.shade400),
                        ),
                        child: const Text(
                          'إلغاء',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: _mainColor,
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'حفظ',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
