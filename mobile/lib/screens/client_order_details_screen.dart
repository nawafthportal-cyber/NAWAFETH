import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/service_request_model.dart';
import '../services/account_mode_service.dart';
import '../services/api_client.dart';
import '../services/marketplace_service.dart';
import '../services/reviews_service.dart';
import '../services/unread_badge_service.dart';
import '../widgets/platform_top_bar.dart';
import 'notifications_screen.dart';
import 'provider_profile_screen.dart';

class ClientOrderDetailsScreen extends StatefulWidget {
  final int requestId;

  const ClientOrderDetailsScreen({
    super.key,
    required this.requestId,
  });

  @override
  State<ClientOrderDetailsScreen> createState() =>
      _ClientOrderDetailsScreenState();
}

class _ClientOrderDetailsScreenState extends State<ClientOrderDetailsScreen>
    with SingleTickerProviderStateMixin {
  static const Color _mainColor = Colors.deepPurple;
  static const Color _accentColor = Color(0xFF22577A);

  ServiceRequest? _order;
  bool _loading = true;
  String? _error;
  bool _saving = false;
  bool _accountChecked = false;
  bool _isProviderMode = false;
  int _notificationUnread = 0;
  int _chatUnread = 0;
  ValueListenable<UnreadBadges>? _badgeHandle;

  late final TextEditingController _titleController;
  late final TextEditingController _detailsController;
  final TextEditingController _reminderController = TextEditingController();
  final TextEditingController _rejectInputsReasonController =
      TextEditingController();
  List<Offer> _offers = <Offer>[];
  int? _acceptingOfferId;

  bool _editTitle = false;
  bool _editDetails = false;

  // تقييم (عند الإكمال)
  bool _showRatingForm = false;
  double _ratingResponseSpeed = 0;
  double _ratingCostValue = 0;
  double _ratingQuality = 0;
  double _ratingCredibility = 0;
  double _ratingOnTime = 0;
  final TextEditingController _ratingCommentController =
      TextEditingController();
  late final AnimationController _entranceController;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _titleController = TextEditingController();
    _detailsController = TextEditingController();
    _badgeHandle = UnreadBadgeService.acquire();
    _badgeHandle?.addListener(_handleBadgeChange);
    _handleBadgeChange();
    _ensureClientAccount();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _entranceController.forward();
      }
    });
  }

  Future<void> _ensureClientAccount() async {
    final isProvider = await AccountModeService.isProviderMode();
    if (!mounted) return;
    setState(() {
      _isProviderMode = isProvider;
      _accountChecked = true;
    });

    if (_isProviderMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/orders');
      });
      return;
    }

    _loadDetail();
  }

  @override
  void dispose() {
    _badgeHandle?.removeListener(_handleBadgeChange);
    if (_badgeHandle != null) {
      UnreadBadgeService.release();
      _badgeHandle = null;
    }
    _titleController.dispose();
    _detailsController.dispose();
    _reminderController.dispose();
    _rejectInputsReasonController.dispose();
    _ratingCommentController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  void _handleBadgeChange() {
    final badges = _badgeHandle?.value ?? UnreadBadges.empty;
    if (!mounted) return;
    setState(() {
      _notificationUnread = badges.notifications;
      _chatUnread = badges.chats;
    });
  }

  Future<void> _loadDetail() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final order =
        await MarketplaceService.getClientRequestDetail(widget.requestId);
    if (!mounted) return;

    if (order == null) {
      setState(() {
        _error = 'تعذّر تحميل تفاصيل الطلب';
        _loading = false;
      });
      return;
    }

    List<Offer> offers = <Offer>[];
    if (order.requestType == 'competitive') {
      offers = await MarketplaceService.getRequestOffers(order.id);
      if (!mounted) return;
    }

    setState(() {
      _order = order;
      _titleController.text = order.title;
      _detailsController.text = order.description;
      _offers = offers;
      _acceptingOfferId = null;

      _ratingResponseSpeed = order.reviewResponseSpeed ?? 0;
      _ratingCostValue = order.reviewCostValue ?? 0;
      _ratingQuality = order.reviewQuality ?? 0;
      _ratingCredibility = order.reviewCredibility ?? 0;
      _ratingOnTime = order.reviewOnTime ?? 0;
      _ratingCommentController.text = order.reviewComment ?? '';

      _loading = false;
    });
  }

  Future<void> _acceptOffer(Offer offer) async {
    final order = _order;
    if (order == null) return;

    if (order.requestType != 'competitive' ||
        order.statusGroup != 'new' ||
        order.provider != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يمكن اختيار عرض في الحالة الحالية',
              style: TextStyle(fontFamily: 'Cairo')),
        ),
      );
      return;
    }

    setState(() => _acceptingOfferId = offer.id);
    final res = await MarketplaceService.acceptOffer(offer.id);
    if (!mounted) return;
    setState(() => _acceptingOfferId = null);

    if (res.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم اختيار العرض وإسناد الطلب بنجاح',
              style: TextStyle(fontFamily: 'Cairo')),
        ),
      );
      _loadDetail();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.error ?? 'تعذّر اختيار العرض',
              style: const TextStyle(fontFamily: 'Cairo')),
        ),
      );
    }
  }

  Future<void> _openProviderProfile(Offer offer) async {
    final providerId = offer.provider > 0 ? offer.provider.toString() : null;
    if (providerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر فتح صفحة المزود: معرف غير صالح',
              style: TextStyle(fontFamily: 'Cairo')),
        ),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProviderProfileScreen(
          providerId: providerId,
          providerName:
              offer.providerName.isNotEmpty ? offer.providerName : 'مزود خدمة',
          showBackToMapButton: true,
          backButtonLabel: 'العودة إلى عروض الأسعار',
          backButtonIcon: Icons.local_offer_outlined,
        ),
      ),
    );
  }

  Color _statusColor(String statusGroup) {
    switch (statusGroup) {
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'in_progress':
        return Colors.orange;
      case 'new':
        return Colors.amber.shade800;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime date) =>
      DateFormat('HH:mm  dd/MM/yyyy', 'ar').format(date);

  String _formatDateOnly(DateTime date) =>
      DateFormat('dd/MM/yyyy', 'ar').format(date);

  String _formatMoney(double? value) {
    if (value == null) return '-';
    return '${value.toStringAsFixed(0)} ر.س';
  }

  void _openChat() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('سيتم فتح المحادثة مع مقدم الخدمة قريباً',
            style: TextStyle(fontFamily: 'Cairo')),
      ),
    );
  }

  /// حفظ التعديلات (فقط status=new)
  Future<void> _save() async {
    final order = _order;
    if (order == null) return;

    if (order.status != 'new') {
      Navigator.pop(context, true);
      return;
    }

    final newTitle = _titleController.text.trim();
    final newDesc = _detailsController.text.trim();

    if (newTitle == order.title && newDesc == order.description) {
      Navigator.pop(context, false);
      return;
    }

    setState(() => _saving = true);
    final res = await MarketplaceService.updateClientRequest(
      order.id,
      title: newTitle != order.title ? newTitle : null,
      description: newDesc != order.description ? newDesc : null,
    );
    if (!mounted) return;
    setState(() => _saving = false);

    if (res.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('تم حفظ التعديلات',
                style: TextStyle(fontFamily: 'Cairo'))),
      );
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(res.error ?? 'فشل الحفظ',
                style: const TextStyle(fontFamily: 'Cairo'))),
      );
    }
  }

  Future<void> _decideProviderInputs({required bool approved}) async {
    final order = _order;
    if (order == null) return;

    if (!approved && _rejectInputsReasonController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('سبب الرفض مطلوب', style: TextStyle(fontFamily: 'Cairo')),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    final res = await MarketplaceService.decideProviderInputs(
      order.id,
      approved: approved,
      note: approved ? null : _rejectInputsReasonController.text.trim(),
    );
    if (!mounted) return;
    setState(() => _saving = false);

    if (res.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approved
                ? 'تم اعتماد التفاصيل وبدأ التنفيذ'
                : 'تم رفض التفاصيل وإشعار مقدم الخدمة',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
        ),
      );
      _rejectInputsReasonController.clear();
      _loadDetail();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.error ?? 'فشل تنفيذ العملية',
              style: const TextStyle(fontFamily: 'Cairo')),
        ),
      );
    }
  }

  Future<void> _submitReview() async {
    final order = _order;
    if (order == null) return;

    if (order.reviewId != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم إرسال تقييمك مسبقاً',
              style: TextStyle(fontFamily: 'Cairo')),
        ),
      );
      return;
    }

    final criteria = [
      _ratingResponseSpeed,
      _ratingCostValue,
      _ratingQuality,
      _ratingCredibility,
      _ratingOnTime,
    ];
    if (criteria.any((value) => value <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('الرجاء تعبئة جميع عناصر التقييم',
              style: TextStyle(fontFamily: 'Cairo')),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    final res = await ReviewsService.createReview(
      requestId: order.id,
      responseSpeed: _ratingResponseSpeed.round(),
      costValue: _ratingCostValue.round(),
      quality: _ratingQuality.round(),
      credibility: _ratingCredibility.round(),
      onTime: _ratingOnTime.round(),
      comment: _ratingCommentController.text.trim().isEmpty
          ? null
          : _ratingCommentController.text.trim(),
    );
    if (!mounted) return;
    setState(() => _saving = false);

    if (res.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم إرسال التقييم والمراجعة بنجاح',
              style: TextStyle(fontFamily: 'Cairo')),
        ),
      );
      _loadDetail();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.error ?? 'تعذر إرسال التقييم',
              style: const TextStyle(fontFamily: 'Cairo')),
        ),
      );
    }
  }

  // ─── helper widgets ───

  Widget _infoRow(String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        border: Border.all(color: const Color(0xFFD7E5F2)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        value,
        style: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
          color: Color(0xFF0F172A),
        ),
      ),
    );
  }

  Widget _infoLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 12.5,
          fontWeight: FontWeight.w900,
          color: Color(0xFF0F172A),
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
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
          ),
        ),
        if (canEdit)
          TextButton(
            onPressed: onToggle,
            style: TextButton.styleFrom(
              foregroundColor: _mainColor,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            child: Text(
              isEditing ? 'إيقاف' : 'تعديل',
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
      ],
    );
  }

  Widget _ratingRow({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white70 : const Color(0xFF0F172A),
              ),
            ),
          ),
          RatingBar.builder(
            initialRating: value,
            minRating: 0,
            allowHalfRating: false,
            itemCount: 5,
            itemSize: 20,
            itemPadding: const EdgeInsets.symmetric(horizontal: 1.5),
            itemBuilder: (context, _) =>
                const Icon(Icons.star, color: Colors.amber),
            onRatingUpdate: onChanged,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    if (!_accountChecked) {
      return const Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Center(
            child: CircularProgressIndicator(color: _mainColor),
          ),
        ),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF0E1726) : const Color(0xFFF2F7FB),
        appBar: PlatformTopBar(
          pageLabel: 'تفاصيل الطلب',
          showBackButton: Navigator.of(context).canPop(),
          notificationCount: _notificationUnread,
          chatCount: _chatUnread,
          onNotificationsTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const NotificationsScreen(),
              ),
            );
            await UnreadBadgeService.refresh(force: true);
          },
          onChatsTap: _openChat,
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: isDark
                ? const LinearGradient(
                    colors: [Color(0xFF0E1726), Color(0xFF122235), Color(0xFF17293D)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  )
                : const LinearGradient(
                    colors: [Color(0xFFEEF5FB), Color(0xFFF4F7FB), Color(0xFFF7F8FC)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
          ),
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: _accentColor),
                )
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.error_outline_rounded,
                                size: 48, color: Colors.red.shade400),
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF667085),
                              ),
                            ),
                            const SizedBox(height: 14),
                            ElevatedButton.icon(
                              onPressed: _loadDetail,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _accentColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              icon: const Icon(Icons.refresh_rounded, size: 18),
                              label: const Text(
                                'إعادة المحاولة',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _buildContent(isDark),
        ),
      ),
    );
  }

  Widget _buildContent(bool isDark) {
    final order = _order!;
    final statusColor = _statusColor(order.statusGroup);
    final cardColor = isDark ? const Color(0xFF132637) : Colors.white.withValues(alpha: 0.96);
    final borderColor = isDark ? Colors.white10 : const Color(0xFFE4EBF1);
    final canEdit = order.status == 'new';

    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
              children: [
                _buildEntrance(
                  0,
                  _buildHeroCard(
                    order: order,
                    isDark: isDark,
                    statusColor: statusColor,
                  ),
                ),
                const SizedBox(height: 14),

                if (order.requestType == 'competitive') ...[
                  _buildEntrance(1, _competitiveOffersCard(order, cardColor, borderColor, isDark)),
                  const SizedBox(height: 12),
                ],

                // ─── مكتمل: التسليم + التقييم ───
                if (order.statusGroup == 'completed') ...[
                  _buildEntrance(2, _completedCard(cardColor, borderColor, isDark)),
                  const SizedBox(height: 12),
                ],

                // ─── تحت التنفيذ: المالية ───
                if (order.statusGroup == 'in_progress') ...[
                  _buildEntrance(2, _inProgressCard(order, cardColor, borderColor, isDark)),
                  const SizedBox(height: 12),
                ],

                // ─── جديد: مدخلات مقدم الخدمة + قرار العميل ───
                if (order.statusGroup == 'new' &&
                    (order.expectedDeliveryAt != null ||
                        order.estimatedAmount != null ||
                        order.receivedAmt != null ||
                        order.remainingAmt != null)) ...[
                  _buildEntrance(
                    2,
                    _providerInputsDecisionCard(
                        order, cardColor, borderColor, isDark, canEdit),
                  ),
                  const SizedBox(height: 12),
                ],

                // ─── ملغي ───
                if (order.statusGroup == 'cancelled') ...[
                  _buildEntrance(2, _cancelledCard(order, cardColor, borderColor)),
                  const SizedBox(height: 12),
                ],

                _buildEntrance(
                  3,
                  _surfaceCard(
                    cardColor: cardColor,
                    borderColor: borderColor,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionHeader(
                            title: 'عنوان الطلب',
                            canEdit: canEdit,
                            isEditing: _editTitle,
                            onToggle: () =>
                                setState(() => _editTitle = !_editTitle)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _titleController,
                          enabled: _editTitle && canEdit,
                          decoration: _inputDecoration(),
                          style: const TextStyle(fontFamily: 'Cairo'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                _buildEntrance(
                  4,
                  _surfaceCard(
                    cardColor: cardColor,
                    borderColor: borderColor,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionHeader(
                            title: 'تفاصيل الطلب',
                            canEdit: canEdit,
                            isEditing: _editDetails,
                            onToggle: () =>
                                setState(() => _editDetails = !_editDetails)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _detailsController,
                          enabled: _editDetails && canEdit,
                          minLines: 4,
                          maxLines: 7,
                          decoration: _inputDecoration(),
                          style: const TextStyle(fontFamily: 'Cairo'),
                        ),
                        if (canEdit) ...[
                          const SizedBox(height: 8),
                          Text(
                            'تنبيه: سيتم إشعار مقدم الخدمة بأي تعديل في بيانات الطلب.',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              color: isDark ? Colors.white54 : const Color(0xFF667085),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                _buildEntrance(5, _attachmentsCard(order, cardColor, borderColor, isDark)),
                const SizedBox(height: 12),

                if (order.statusLogs.isNotEmpty) ...[
                  _buildEntrance(6, _statusLogsCard(order, cardColor, borderColor, isDark)),
                  const SizedBox(height: 12),
                ],

                _buildEntrance(
                  7,
                  _surfaceCard(
                    cardColor: cardColor,
                    borderColor: borderColor,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(children: [
                          Icon(Icons.notifications_none_rounded, color: _mainColor),
                          SizedBox(width: 8),
                          Expanded(
                              child: Text('ارسال تنبيه وتذكير للمختص',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF0F172A)))),
                        ]),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _reminderController,
                          minLines: 6,
                          maxLines: 10,
                          decoration: _inputDecoration(hintText: 'اكتب رسالتك هنا...'),
                          style: const TextStyle(fontFamily: 'Cairo'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ─── أزرار الأسفل ───
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: Colors.grey.shade400),
                      backgroundColor: Colors.white.withValues(alpha: 0.9),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: const Text('رجوع',
                        style: TextStyle(
                            fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                  ),
                ),
                if (canEdit) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: _mainColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('حفظ',
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Cards ───

  Widget _buildHeroCard({
    required ServiceRequest order,
    required bool isDark,
    required Color statusColor,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          colors: [Color(0xFF183B64), Color(0xFF22577A), Color(0xFF0F766E)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0C223D).withValues(alpha: 0.16),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -36,
            left: -18,
            child: Container(
              width: 132,
              height: 132,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.10),
              ),
            ),
          ),
          Positioned(
            bottom: -56,
            right: -18,
            child: Container(
              width: 154,
              height: 154,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.inventory_2_outlined,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.displayId,
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          order.title,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11.5,
                            height: 1.8,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withValues(alpha: 0.84),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                    ),
                    child: Text(
                      order.statusLabel.isNotEmpty ? order.statusLabel : order.statusGroup,
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _heroChip(Icons.local_offer_outlined, order.requestTypeLabel),
                  if (order.categoryName != null && order.categoryName!.isNotEmpty)
                    _heroChip(
                      Icons.category_outlined,
                      '${order.categoryName}${order.subcategoryName != null && order.subcategoryName!.isNotEmpty ? ' / ${order.subcategoryName}' : ''}',
                    ),
                  _heroChip(Icons.schedule_outlined, _formatDate(order.createdAt)),
                  if (order.providerName != null && order.providerName!.isNotEmpty)
                    _heroChip(Icons.storefront_outlined, order.providerName!),
                  if (order.providerPhone != null && order.providerPhone!.isNotEmpty)
                    _heroChip(Icons.phone_outlined, order.providerPhone!),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 10.8,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _surfaceCard({
    required Color cardColor,
    required Color borderColor,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0C223D).withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }

  InputDecoration _inputDecoration({String? hintText}) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(
        fontFamily: 'Cairo',
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: Color(0xFF98A2B3),
      ),
      filled: true,
      fillColor: const Color(0xFFF8FBFF),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFFD7E5F2)),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFFD7E5F2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: _mainColor, width: 1.4),
      ),
    );
  }

  Widget _buildEntrance(int index, Widget child) {
    final begin = (0.08 * index).clamp(0.0, 0.8).toDouble();
    final end = (begin + 0.34).clamp(0.0, 1.0).toDouble();
    final animation = CurvedAnimation(
      parent: _entranceController,
      curve: Interval(begin, end, curve: Curves.easeOutCubic),
    );

    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }

  Widget _completedCard(Color cardColor, Color borderColor, bool isDark) {
    final order = _order!;
    final reviewed = order.reviewId != null;
    return Container(
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
          _infoRow(order.deliveredAt == null
              ? '-'
              : _formatDateOnly(order.deliveredAt!)),
          const SizedBox(height: 10),
          _infoLabel('قيمة الخدمة الفعلية'),
          _infoRow(_formatMoney(order.actualAmount)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: reviewed
                  ? null
                  : () => setState(() => _showRatingForm = !_showRatingForm),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: _mainColor),
              ),
              child: Text(reviewed ? 'تم إرسال التقييم' : 'تقييم الخدمة',
                  style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      color: _mainColor)),
            ),
          ),
          if (reviewed) ...[
            const SizedBox(height: 8),
            Text(
              'تم إرسال مراجعتك لهذه الخدمة ويمكنك مشاهدة تفاصيلها في السجل.',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  color: isDark ? Colors.white54 : Colors.black54),
            ),
          ],
          if (_showRatingForm) ...[
            const SizedBox(height: 12),
            _ratingRow(
                label: 'سرعة الاستجابة',
                value: _ratingResponseSpeed,
                onChanged: (v) => setState(() => _ratingResponseSpeed = v)),
            _ratingRow(
                label: 'القيمة مقابل السعر',
                value: _ratingCostValue,
                onChanged: (v) => setState(() => _ratingCostValue = v)),
            _ratingRow(
                label: 'جودة العمل',
                value: _ratingQuality,
                onChanged: (v) => setState(() => _ratingQuality = v)),
            _ratingRow(
                label: 'المصداقية',
                value: _ratingCredibility,
                onChanged: (v) => setState(() => _ratingCredibility = v)),
            _ratingRow(
                label: 'الالتزام بالموعد',
                value: _ratingOnTime,
                onChanged: (v) => setState(() => _ratingOnTime = v)),
            const SizedBox(height: 12),
            const Text('تعليقك',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _ratingCommentController,
              maxLength: 300,
              buildCounter: (context,
                      {required currentLength,
                      required isFocused,
                      maxLength}) =>
                  null,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'اكتب تعليقًا مختصرًا عن التجربة',
                hintStyle: TextStyle(fontFamily: 'Cairo', fontSize: 13),
              ),
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _submitReview,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _mainColor,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('إرسال التقييم',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _inProgressCard(
      ServiceRequest order, Color cardColor, Color borderColor, bool isDark) {
    return Container(
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
          _infoRow(order.expectedDeliveryAt == null
              ? '-'
              : _formatDateOnly(order.expectedDeliveryAt!)),
          const SizedBox(height: 10),
          _infoLabel('قيمة الخدمة المقدرة'),
          _infoRow(_formatMoney(order.estimatedAmount)),
          const SizedBox(height: 10),
          _infoLabel('المبلغ المستلم'),
          _infoRow(_formatMoney(order.receivedAmt)),
          const SizedBox(height: 10),
          _infoLabel('المبلغ المتبقي'),
          _infoRow(_formatMoney(order.remainingAmt)),
          if (order.providerInputsApproved != null) ...[
            const SizedBox(height: 12),
            Text(
              'حالة اعتماد مدخلات مقدم الخدمة: ${order.providerInputsApproved == true ? 'معتمد ✅' : 'مرفوض ❌'}',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  color: isDark ? Colors.white54 : Colors.black54),
            ),
          ],
        ],
      ),
    );
  }

  Widget _providerInputsDecisionCard(ServiceRequest order, Color cardColor,
      Color borderColor, bool isDark, bool canEdit) {
    final waitingDecision = order.providerInputsApproved == null;
    final rejected = order.providerInputsApproved == false;
    final decisionNote = (order.providerInputsDecisionNote ?? '').trim();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('تفاصيل التنفيذ من مقدم الخدمة',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 14,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          _infoLabel('موعد التسليم المتوقع'),
          _infoRow(order.expectedDeliveryAt == null
              ? '-'
              : _formatDateOnly(order.expectedDeliveryAt!)),
          const SizedBox(height: 10),
          _infoLabel('قيمة الخدمة المقدرة'),
          _infoRow(_formatMoney(order.estimatedAmount)),
          const SizedBox(height: 10),
          _infoLabel('المبلغ المستلم'),
          _infoRow(_formatMoney(order.receivedAmt)),
          const SizedBox(height: 10),
          _infoLabel('المبلغ المتبقي'),
          _infoRow(_formatMoney(order.remainingAmt)),
          if (rejected && decisionNote.isNotEmpty) ...[
            const SizedBox(height: 10),
            _infoLabel('سبب الرفض المرسل لمقدم الخدمة'),
            _infoRow(decisionNote),
          ],
          if (canEdit && waitingDecision) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _rejectInputsReasonController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'سبب الرفض عند الحاجة',
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () => _decideProviderInputs(approved: false),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('رفض التفاصيل',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            color: Colors.red)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _saving
                        ? null
                        : () => _decideProviderInputs(approved: true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _mainColor,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('اعتماد وبدء التنفيذ',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                  ),
                ),
              ],
            ),
          ],
          if (!waitingDecision) ...[
            const SizedBox(height: 10),
            Text(
              order.providerInputsApproved == true
                  ? 'تم اعتماد تفاصيل التنفيذ'
                  : 'تم رفض تفاصيل التنفيذ بانتظار إعادة الإرسال',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  color: isDark ? Colors.white54 : Colors.black54),
            ),
          ],
        ],
      ),
    );
  }

  Widget _cancelledCard(
      ServiceRequest order, Color cardColor, Color borderColor) {
    return Container(
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
          _infoRow(order.canceledAt == null
              ? '-'
              : _formatDateOnly(order.canceledAt!)),
          const SizedBox(height: 10),
          _infoLabel('سبب الإلغاء'),
          _infoRow(order.cancelReason ?? '-'),
        ],
      ),
    );
  }

  Color _offerStatusColor(String status) {
    switch (status) {
      case 'selected':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.orange.shade800;
    }
  }

  String _offerStatusLabel(String status) {
    switch (status) {
      case 'selected':
        return 'تم اختياره';
      case 'rejected':
        return 'مرفوض';
      default:
        return 'بانتظار القرار';
    }
  }

  Widget _competitiveOffersCard(
      ServiceRequest order, Color cardColor, Color borderColor, bool isDark) {
    final canSelectOffer = order.statusGroup == 'new' && order.provider == null;

    return Container(
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
                child: Text('عروض الأسعار',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 14,
                        fontWeight: FontWeight.bold)),
              ),
              IconButton(
                onPressed: _loading ? null : _loadDetail,
                tooltip: 'تحديث العروض',
                icon: const Icon(Icons.refresh, color: _mainColor),
              ),
            ],
          ),
          if (_offers.isEmpty)
            Text(
              'لا توجد عروض أسعار حتى الآن.',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  color: isDark ? Colors.white54 : Colors.black54),
            )
          else
            ..._offers.map((offer) {
              final statusColor = _offerStatusColor(offer.status);
              final note = (offer.note ?? '').trim();
              final isSelecting = _acceptingOfferId == offer.id;

              return Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white10 : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: statusColor.withAlpha(70)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => _openProviderProfile(offer),
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  const Icon(Icons.person_outline,
                                      size: 16, color: _mainColor),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      offer.providerName.isNotEmpty
                                          ? offer.providerName
                                          : 'مقدم خدمة #${offer.provider}',
                                      style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.open_in_new_rounded,
                                    size: 15,
                                    color: isDark
                                        ? Colors.white54
                                        : Colors.black45,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withAlpha(20),
                            borderRadius: BorderRadius.circular(14),
                            border:
                                Border.all(color: statusColor.withAlpha(80)),
                          ),
                          child: Text(
                            _offerStatusLabel(offer.status),
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'السعر: ${offer.price} (SR)',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'مدة التنفيذ: ${offer.durationDays} يوم',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    if (note.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'ملاحظة: $note',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                    ],
                    if (canSelectOffer && offer.status == 'pending') ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: isSelecting || _saving
                              ? null
                              : () => _acceptOffer(offer),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _mainColor,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: isSelecting
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Text(
                                  'اختيار هذا العرض',
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
              );
            }),
        ],
      ),
    );
  }

  Widget _attachmentsCard(
      ServiceRequest order, Color cardColor, Color borderColor, bool isDark) {
    final deliveredAt = order.deliveredAt;
    final finalDeliveryAttachments = order.attachments.where((attachment) {
      final createdAt = attachment.createdAt;
      if (deliveredAt == null || createdAt == null) {
        return false;
      }
      return !createdAt.isBefore(deliveredAt);
    }).toList();
    final regularAttachments = order.attachments.where((attachment) {
      return !finalDeliveryAttachments.contains(attachment);
    }).toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('المرفقات',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 14,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (order.attachments.isEmpty)
            Text('لا يوجد مرفقات',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    color: isDark ? Colors.white54 : Colors.black54))
          else ...[
            if (finalDeliveryAttachments.isNotEmpty) ...[
              const Text('مرفقات التسليم النهائي',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: _mainColor)),
              ...finalDeliveryAttachments.map(
                (attachment) => _attachmentRow(attachment, isDark),
              ),
              if (regularAttachments.isNotEmpty) const SizedBox(height: 8),
            ],
            if (regularAttachments.isNotEmpty) ...[
              if (finalDeliveryAttachments.isNotEmpty)
                const Text('مرفقات الطلب',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              ...regularAttachments.map(
                (attachment) => _attachmentRow(attachment, isDark),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _attachmentRow(RequestAttachment attachment, bool isDark) {
    final fileName = _attachmentFileName(attachment);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openAttachment(attachment),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(children: [
              Icon(_attachmentIcon(attachment.fileType),
                  size: 18, color: Colors.grey),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(fileName,
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          color: isDark ? Colors.white70 : Colors.black87))),
              const SizedBox(width: 8),
              Text(attachment.fileType.toUpperCase(),
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      color: isDark ? Colors.white54 : Colors.black54)),
              const SizedBox(width: 6),
              Icon(Icons.open_in_new,
                  size: 16, color: isDark ? Colors.white38 : Colors.black38),
            ]),
          ),
        ),
      ),
    );
  }

  String _attachmentFileName(RequestAttachment attachment) {
    final uri = Uri.tryParse(attachment.fileUrl);
    final segments = (uri?.pathSegments ?? const <String>[])
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments.isNotEmpty) return segments.last;
    final raw = attachment.fileUrl.trim();
    if (raw.isEmpty) return 'ملف';
    return raw.split('/').last;
  }

  String? _normalizedAttachmentUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final parsed = Uri.tryParse(value);
    if (parsed != null && parsed.hasScheme) {
      if ((parsed.scheme == 'http' || parsed.scheme == 'https') &&
          parsed.path.startsWith('/media/')) {
        final base = Uri.parse(ApiClient.baseUrl);
        return base
            .resolve('${parsed.path}${parsed.hasQuery ? '?${parsed.query}' : ''}')
            .toString();
      }
      return parsed.toString();
    }
    return ApiClient.buildMediaUrl(value);
  }

  Future<void> _openAttachment(RequestAttachment attachment) async {
    final url = _normalizedAttachmentUrl(attachment.fileUrl);
    if (url == null || url.isEmpty) {
      _showAttachmentError();
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _showAttachmentError();
      return;
    }
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) _showAttachmentError();
  }

  void _showAttachmentError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'تعذر فتح المرفق',
          style: TextStyle(fontFamily: 'Cairo'),
        ),
      ),
    );
  }

  Widget _statusLogsCard(
      ServiceRequest order, Color cardColor, Color borderColor, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('سجل تغيير الحالة',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 14,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...order.statusLogs.map(
            (log) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.circle, size: 8, color: _mainColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${log.fromStatus.isNotEmpty ? log.fromStatus : '—'} → ${log.toStatus}',
                          style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                              fontWeight: FontWeight.bold),
                        ),
                        if (log.note != null && log.note!.isNotEmpty)
                          Text(log.note!,
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.white54
                                      : Colors.black54)),
                        if (log.createdAt != null)
                          Text(_formatDate(log.createdAt!),
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 11,
                                  color: isDark
                                      ? Colors.white38
                                      : Colors.black38)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _attachmentIcon(String fileType) {
    switch (fileType) {
      case 'image':
        return Icons.image;
      case 'video':
        return Icons.videocam;
      case 'audio':
        return Icons.audiotrack;
      case 'document':
        return Icons.description;
      default:
        return Icons.attach_file;
    }
  }
}
