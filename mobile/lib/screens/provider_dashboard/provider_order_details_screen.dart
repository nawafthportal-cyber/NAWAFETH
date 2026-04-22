import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:nawafeth/services/account_mode_service.dart';
import 'package:nawafeth/services/unread_badge_service.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/service_request_model.dart';
import '../../services/api_client.dart';
import '../../services/marketplace_service.dart';
import '../../constants/app_theme.dart';
import '../../widgets/platform_top_bar.dart';
import '../notifications_screen.dart';

class ProviderOrderDetailsScreen extends StatefulWidget {
  final int requestId;

  const ProviderOrderDetailsScreen({
    super.key,
    required this.requestId,
  });

  @override
  State<ProviderOrderDetailsScreen> createState() =>
      _ProviderOrderDetailsScreenState();
}

class _ProviderOrderDetailsScreenState
    extends State<ProviderOrderDetailsScreen>
    with SingleTickerProviderStateMixin {
  static const Color _mainColor = AppColors.teal;
  static const Color _accentColor = Color(0xFF115E59);
  static const Color _inkColor = AppTextStyles.textPrimary;
  late final AnimationController _entranceController;

  ServiceRequest? _order;
  bool _loading = true;
  String? _error;
  bool _actionLoading = false;

  // حقول بدء التنفيذ
  final TextEditingController _estimatedAmountController =
      TextEditingController();
  final TextEditingController _receivedAmountController =
      TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  // حقول الإكمال
  final TextEditingController _actualAmountController = TextEditingController();
  final List<File> _completionAttachments = <File>[];

  // حقول الرفض
  final TextEditingController _cancelReasonController = TextEditingController();

  // حقول العرض التنافسي
  final TextEditingController _offerPriceController = TextEditingController();
  final TextEditingController _offerDurationDaysController =
      TextEditingController();
  final TextEditingController _offerNoteController = TextEditingController();
  bool _offerAlreadySent = false;

  DateTime? _expectedDeliveryAt;
  DateTime? _deliveredAt;

  bool _accountChecked = false;
  bool _isProviderAccount = false;
  int _notificationUnread = 0;
  int _chatUnread = 0;
  ValueListenable<UnreadBadges>? _badgeHandle;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _badgeHandle = UnreadBadgeService.acquire();
    _badgeHandle?.addListener(_handleBadgeChange);
    _handleBadgeChange();
    _ensureProviderAccount();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _entranceController.forward();
      }
    });
  }

  Future<void> _ensureProviderAccount() async {
    final isProvider = await AccountModeService.isProviderMode();
    if (!mounted) return;
    setState(() {
      _isProviderAccount = isProvider;
      _accountChecked = true;
    });
    if (!_isProviderAccount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    } else {
      _loadDetail();
    }
  }

  @override
  void dispose() {
    _badgeHandle?.removeListener(_handleBadgeChange);
    if (_badgeHandle != null) {
      UnreadBadgeService.release();
      _badgeHandle = null;
    }
    _estimatedAmountController.dispose();
    _receivedAmountController.dispose();
    _noteController.dispose();
    _actualAmountController.dispose();
    _cancelReasonController.dispose();
    _offerPriceController.dispose();
    _offerDurationDaysController.dispose();
    _offerNoteController.dispose();
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
        await MarketplaceService.getProviderRequestDetail(widget.requestId);
    if (!mounted) return;

    if (order == null) {
      setState(() {
        _error = 'تعذّر تحميل تفاصيل الطلب';
        _loading = false;
      });
      return;
    }

    setState(() {
      _order = order;
      _expectedDeliveryAt = order.expectedDeliveryAt;
      _deliveredAt = order.deliveredAt;
      _estimatedAmountController.text = order.estimatedServiceAmount ?? '';
      _receivedAmountController.text = order.receivedAmount ?? '';
      _actualAmountController.text = order.actualServiceAmount ?? '';
      _cancelReasonController.text = order.cancelReason ?? '';
      _offerAlreadySent = false;
      _loading = false;
    });
  }

  // ─── إجراءات ───

  /// قبول الطلب (المسند أو العاجل المتاح)
  Future<void> _accept() async {
    final order = _order;
    if (order == null) return;

    setState(() => _actionLoading = true);
    final res = (order.requestType == 'urgent' && order.provider == null)
        ? await MarketplaceService.acceptUrgentRequest(widget.requestId)
        : await MarketplaceService.acceptRequest(widget.requestId);
    if (!mounted) return;
    setState(() => _actionLoading = false);

    if (res.isSuccess) {
      if (order.requestType == 'urgent' && order.provider == null) {
        _snack('تم قبول الطلب العاجل بنجاح');
      } else {
        _snack('تم قبول الطلب. أرسل تفاصيل التنفيذ للعميل');
      }
      _loadDetail();
    } else {
      _snack(res.error ?? 'فشلت العملية');
    }
  }

  /// رفض / إلغاء الطلب
  Future<void> _reject() async {
    final reason = _cancelReasonController.text.trim();
    if (reason.isEmpty) {
      _snack('الرجاء كتابة سبب الإلغاء');
      return;
    }
    setState(() => _actionLoading = true);
    final res = await MarketplaceService.rejectRequest(
      widget.requestId,
      cancelReason: reason,
    );
    if (!mounted) return;
    setState(() => _actionLoading = false);

    if (res.isSuccess) {
      _snack('تم إلغاء الطلب');
      _loadDetail();
    } else {
      _snack(res.error ?? 'فشلت العملية');
    }
  }

  /// تحديث التقدم
  Future<void> _updateProgress() async {
    final order = _order;
    if (order == null) return;

    if (order.statusGroup == 'new') {
      if (_expectedDeliveryAt == null) {
        _snack('حدد موعد التسليم المتوقع');
        return;
      }
      final est = _estimatedAmountController.text.trim();
      final rec = _receivedAmountController.text.trim();
      if (est.isEmpty || rec.isEmpty) {
        _snack('أدخل القيمة المقدرة والمبلغ المستلم');
        return;
      }
    }

    setState(() => _actionLoading = true);
    final res = await MarketplaceService.updateProgress(
      widget.requestId,
      expectedDeliveryAt: _expectedDeliveryAt?.toIso8601String(),
      estimatedServiceAmount: _estimatedAmountController.text.trim().isNotEmpty
          ? _estimatedAmountController.text.trim()
          : null,
      receivedAmount: _receivedAmountController.text.trim().isNotEmpty
          ? _receivedAmountController.text.trim()
          : null,
      note: _noteController.text.trim().isNotEmpty
          ? _noteController.text.trim()
          : null,
    );
    if (!mounted) return;
    setState(() => _actionLoading = false);

    if (res.isSuccess) {
      _snack(order.statusGroup == 'new'
          ? 'تم إرسال تحديثك للعميل بانتظار القرار'
          : 'تم تحديث التقدم');
      _loadDetail();
    } else {
      _snack(res.error ?? 'فشلت العملية');
    }
  }

  /// إكمال الطلب
  Future<void> _complete() async {
    if (_deliveredAt == null) {
      _snack('حدد موعد التسليم الفعلي');
      return;
    }
    final actual = _actualAmountController.text.trim();
    if (actual.isEmpty) {
      _snack('أدخل قيمة الخدمة الفعلية');
      return;
    }

    setState(() => _actionLoading = true);
    final res = await MarketplaceService.completeRequest(
      widget.requestId,
      deliveredAt: _deliveredAt!.toIso8601String(),
      actualServiceAmount: actual,
      note: _noteController.text.trim().isNotEmpty
          ? _noteController.text.trim()
          : null,
      attachments: _completionAttachments,
    );
    if (!mounted) return;
    setState(() => _actionLoading = false);

    if (res.isSuccess) {
      _snack('تم إكمال الطلب');
      _completionAttachments.clear();
      _loadDetail();
    } else {
      _snack(res.error ?? 'فشلت العملية');
    }
  }

  Future<void> _sendCompetitiveOffer() async {
    final priceRaw = _offerPriceController.text.trim();
    final durationRaw = _offerDurationDaysController.text.trim();
    final noteRaw = _offerNoteController.text.trim();

    final price = double.tryParse(priceRaw);
    if (priceRaw.isEmpty || price == null || price <= 0) {
      _snack('أدخل سعر عرض صالح');
      return;
    }

    final durationDays = int.tryParse(durationRaw);
    if (durationRaw.isEmpty || durationDays == null || durationDays <= 0) {
      _snack('أدخل مدة تنفيذ بالأيام بشكل صحيح');
      return;
    }

    setState(() => _actionLoading = true);
    final res = await MarketplaceService.createOffer(
      widget.requestId,
      price: priceRaw,
      durationDays: durationDays,
      note: noteRaw.isNotEmpty ? noteRaw : null,
    );
    if (!mounted) return;
    setState(() => _actionLoading = false);

    if (res.isSuccess) {
      setState(() => _offerAlreadySent = true);
      _snack('تم إرسال عرض السعر بنجاح');
      return;
    }

    if (res.statusCode == 409) {
      setState(() => _offerAlreadySent = true);
      _snack('تم إرسال عرض مسبقًا على هذا الطلب');
      return;
    }

    _snack(res.error ?? 'تعذّر إرسال العرض');
  }

  Future<void> _pickCompletionAttachments() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const [
        'jpg',
        'jpeg',
        'png',
        'gif',
        'webp',
        'bmp',
        'pdf',
        'doc',
        'docx',
        'xls',
        'xlsx',
        'ppt',
        'pptx',
        'txt',
        'zip',
        'rar',
      ],
    );

    if (result == null || result.files.isEmpty || !mounted) return;

    setState(() {
      for (final picked in result.files) {
        final path = picked.path;
        if (path == null || path.isEmpty) continue;
        if (_completionAttachments.any((f) => f.path == path)) continue;
        _completionAttachments.add(File(path));
      }
    });
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Cairo'))));
  }

  // ─── Helper widgets ───

  String _formatDate(DateTime date) =>
      DateFormat('HH:mm  dd/MM/yyyy', 'ar').format(date);

  String _formatDateOnly(DateTime date) =>
      DateFormat('dd/MM/yyyy', 'ar').format(date);

  Color _statusColor(String sg) {
    switch (sg) {
      case 'completed':
        return AppColors.success;
      case 'cancelled':
        return AppColors.error;
      case 'in_progress':
        return AppColors.warning;
      case 'new':
        return AppColors.warning;
      default:
        return Colors.grey;
    }
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 5),
      locale: const Locale('ar'),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    final t = time ?? TimeOfDay.fromDateTime(initial);
    return DateTime(date.year, date.month, date.day, t.hour, t.minute);
  }

  void _openChat() {
    _snack('سيتم فتح المحادثة مع العميل قريباً');
  }

  Widget _sectionTitle(String text) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Cairo',
          fontWeight: FontWeight.w900,
          fontSize: 14,
          color: isDark ? Colors.white : _inkColor,
        ),
      ),
    );
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(text,
          style: TextStyle(
              color: color,
              fontFamily: 'Cairo',
              fontSize: 11.5,
              fontWeight: FontWeight.w800)),
    );
  }

  Widget _infoLine(
      {required IconData icon, required String label, required String value}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(children: [
      Icon(icon, size: 18, color: _mainColor),
      const SizedBox(width: 8),
      Text(label,
          style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white70 : _inkColor)),
      const SizedBox(width: 8),
      Expanded(
          child: Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white60 : const Color(0xFF64748B)))),
    ]);
  }

  Widget _readOnlyBox(
      {required String label, required String value, int maxLines = 3}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
              color: isDark ? Colors.white70 : _inkColor)),
      const SizedBox(height: 8),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF6FBFA),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFDCE7E7)),
        ),
        child: Text(value.trim().isEmpty ? '-' : value,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                height: 1.6,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : _inkColor)),
      ),
    ]);
  }

  Widget _textField({
    required TextEditingController controller,
    required bool enabled,
    int maxLines = 1,
    String? hint,
    TextInputType? keyboardType,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextField(
      controller: controller,
      enabled: enabled,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: TextStyle(
        fontFamily: 'Cairo',
        fontSize: 13,
        color: isDark ? Colors.white : _inkColor,
      ),
      decoration: _inputDecoration(
        hint: hint,
        isDark: isDark,
        enabled: enabled,
      ),
    );
  }

  Widget _dateLine({
    required String label,
    required DateTime? value,
    required VoidCallback onPick,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFDCE7E7)),
          color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF6FBFA),
        ),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _mainColor.withAlpha(18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.calendar_month, size: 18, color: _mainColor),
          ),
          const SizedBox(width: 8),
          Expanded(
              child: Text(
                  value == null ? label : '$label: ${_formatDateOnly(value)}',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : _inkColor,
                  ))),
          Icon(Icons.expand_more, color: isDark ? Colors.white38 : Colors.black45),
        ]),
      ),
    );
  }

  Widget _moneyField(String label, TextEditingController controller) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white70 : _inkColor)),
      const SizedBox(height: 6),
      _textField(
        controller: controller,
        enabled: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        hint: '0',
      ),
    ]);
  }

  InputDecoration _inputDecoration({
    required String? hint,
    required bool isDark,
    required bool enabled,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        fontFamily: 'Cairo',
        fontSize: 13,
        color: isDark ? Colors.white30 : Colors.grey.shade500,
      ),
      filled: true,
      fillColor: isDark
          ? Colors.white.withValues(alpha: enabled ? 0.04 : 0.02)
          : enabled
              ? const Color(0xFFF6FBFA)
              : const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: isDark ? Colors.white10 : const Color(0xFFDCE7E7)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: isDark ? Colors.white10 : const Color(0xFFDCE7E7)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
        borderSide: BorderSide(color: _mainColor, width: 1.2),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
      ),
    );
  }

  Widget _surfaceCard({
    required IconData icon,
    required String title,
    String? description,
    required Widget child,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF102928) : Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: _mainColor.withAlpha(12),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _mainColor.withAlpha(18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: _mainColor, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: isDark ? Colors.white : _inkColor,
                      ),
                    ),
                    if (description != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 10.8,
                          height: 1.7,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white60 : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _buildHeroCard(ServiceRequest order, Color statusColor) {
    final categoryLabel = order.categoryName == null
        ? 'بدون تصنيف'
        : '${order.categoryName}${(order.subcategoryName ?? '').trim().isEmpty ? '' : ' / ${order.subcategoryName}'}';
    final locationLabel = order.locationDisplay.trim().isNotEmpty
        ? order.locationDisplay
        : ((order.city ?? '').trim().isNotEmpty ? order.city! : 'غير محدد');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          colors: [Color(0xFF115E59), Color(0xFF0F766E), Color(0xFF14B8A6)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        boxShadow: [
          BoxShadow(
            color: _accentColor.withValues(alpha: 0.20),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -34,
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
            bottom: -58,
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.displayId,
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          order.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            height: 1.6,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _pill(
                    order.statusLabel.isNotEmpty ? order.statusLabel : order.statusGroup,
                    statusColor,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _summaryChip(Icons.category_outlined, categoryLabel),
                  _summaryChip(Icons.place_outlined, locationLabel),
                  _summaryChip(Icons.attach_file_rounded, '${order.attachments.length} مرفقات'),
                  if (order.requestType != 'normal')
                    _summaryChip(Icons.flash_on_rounded, order.requestTypeLabel),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _formatDate(order.createdAt),
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.84),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryChip(IconData icon, String label) {
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
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4FBFA),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              CircularProgressIndicator(color: _mainColor),
              SizedBox(height: 12),
              Text(
                'جار تحميل تفاصيل الطلب...',
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4FBFA),
        body: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: _mainColor.withAlpha(12),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_rounded, size: 34, color: Color(0xFF94A3B8)),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _loadDetail,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text(
                    'إعادة المحاولة',
                    style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _mainColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                ),
              ],
            ),
          ),
        ),
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

  // ─── Main build ───

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!_accountChecked || _loading) {
      return _buildLoadingState();
    }
    if (!_isProviderAccount) return const Scaffold(body: SizedBox.shrink());
    if (_error != null) {
      return _buildErrorState(_error!);
    }

    final order = _order!;
    final statusColor = _statusColor(order.statusGroup);
    final deliveredAt = order.deliveredAt;
    final finalDeliveryAttachments = order.attachments.where((a) {
      final createdAt = a.createdAt;
      if (deliveredAt == null || createdAt == null) {
        return false;
      }
      return !createdAt.isBefore(deliveredAt);
    }).toList();
    final regularAttachments = order.attachments.where((a) {
      return !finalDeliveryAttachments.contains(a);
    }).toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF081B1A) : const Color(0xFFF4FBFA),
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
                    colors: [Color(0xFF081B1A), Color(0xFF0E2524), Color(0xFF14302E)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  )
                : const LinearGradient(
                    colors: [Color(0xFFEFFCFA), Color(0xFFF7FFFD), Color(0xFFFFFFFF)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
          ),
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              _buildEntrance(0, _buildHeroCard(order, statusColor)),
              const SizedBox(height: 12),
              _buildEntrance(
                1,
                _surfaceCard(
                  icon: Icons.person_outline_rounded,
                  title: 'بيانات العميل',
                  description: 'راجع بيانات التواصل والموقع قبل بدء التنفيذ أو إرسال التحديثات.',
                  child: Column(
                    children: [
                      _infoLine(
                        icon: Icons.badge_outlined,
                        label: 'الاسم',
                        value: order.clientName ?? 'غير متوفر',
                      ),
                      const SizedBox(height: 10),
                      _infoLine(
                        icon: Icons.phone_outlined,
                        label: 'الجوال',
                        value: (order.clientPhone ?? '').trim().isEmpty
                            ? 'غير متوفر'
                            : order.clientPhone!,
                      ),
                      const SizedBox(height: 10),
                      _infoLine(
                        icon: Icons.location_on_outlined,
                        label: 'المدينة',
                        value: order.locationDisplay.trim().isEmpty
                            ? 'غير متوفر'
                            : order.locationDisplay,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _buildEntrance(
                2,
                _surfaceCard(
                  icon: Icons.description_outlined,
                  title: 'ملخص الطلب',
                  description: 'العنوان والوصف كما أرسلها العميل مع المحافظة على التفاصيل الأصلية.',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _readOnlyBox(label: 'عنوان الطلب', value: order.title, maxLines: 2),
                      const SizedBox(height: 12),
                      _readOnlyBox(label: 'تفاصيل الطلب', value: order.description, maxLines: 8),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _buildEntrance(
                3,
                _surfaceCard(
                  icon: Icons.attach_file_rounded,
                  title: 'المرفقات',
                  description: 'افصل بين مرفقات الطلب الأصلية ومرفقات التسليم النهائي عند توفرها.',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (order.attachments.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF6FBFA),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFDCE7E7)),
                          ),
                          child: Column(
                            children: [
                              const Icon(Icons.inventory_2_outlined, color: _mainColor, size: 28),
                              const SizedBox(height: 8),
                              Text(
                                'لا توجد مرفقات لهذا الطلب حتى الآن.',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.w800,
                                  color: isDark ? Colors.white : _inkColor,
                                ),
                              ),
                            ],
                          ),
                        )
                      else ...[
                        if (finalDeliveryAttachments.isNotEmpty) ...[
                          const Text(
                            'مرفقات التسليم النهائي',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.w900,
                              fontSize: 12.5,
                              color: _mainColor,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...finalDeliveryAttachments.map((a) => _attachmentRow(a)),
                          if (regularAttachments.isNotEmpty) const SizedBox(height: 12),
                        ],
                        if (regularAttachments.isNotEmpty) ...[
                          Text(
                            finalDeliveryAttachments.isNotEmpty ? 'مرفقات الطلب' : 'مرفقات العميل',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.w900,
                              fontSize: 12.5,
                              color: isDark ? Colors.white : _inkColor,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...regularAttachments.map((a) => _attachmentRow(a)),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              if (order.statusLogs.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildEntrance(
                  4,
                  _surfaceCard(
                    icon: Icons.timeline_rounded,
                    title: 'سجل تغيير الحالة',
                    description: 'تسلسل التحديثات والإجراءات المسجلة على الطلب.',
                    child: Column(
                      children: order.statusLogs.map((log) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: _statusColor(log.toStatus).withAlpha(18),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.circle,
                                  size: 10,
                                  color: _statusColor(log.toStatus),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${log.fromStatus.isNotEmpty ? log.fromStatus : '—'} → ${log.toStatus}',
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w900,
                                        color: isDark ? Colors.white : _inkColor,
                                      ),
                                    ),
                                    if (log.note != null && log.note!.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        log.note!,
                                        style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: isDark ? Colors.white60 : const Color(0xFF64748B),
                                        ),
                                      ),
                                    ],
                                    if (log.createdAt != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        _formatDate(log.createdAt!),
                                        style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          color: isDark ? Colors.white38 : Colors.black38,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _buildEntrance(
                5,
                _surfaceCard(
                  icon: Icons.handyman_outlined,
                  title: 'إجراء على الطلب',
                  description: 'نفّذ الإجراء المناسب حسب حالة الطلب دون تغيير منطق التدفق الحالي.',
                  child: _buildActionsForStatus(order),
                ),
              ),
              const SizedBox(height: 18),
              _buildEntrance(
                6,
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      side: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      backgroundColor: Colors.white.withValues(alpha: 0.9),
                    ),
                    child: Text(
                      'رجوع',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white70 : _inkColor,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionsForStatus(ServiceRequest order) {
    switch (order.statusGroup) {
      case 'new':
        return _newActions();
      case 'in_progress':
        return _inProgressActions();
      case 'completed':
        return _completedInfo(order);
      case 'cancelled':
        return _cancelledInfo(order);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _newActions() {
    final order = _order;
    if (order == null) return const SizedBox.shrink();

    if (order.requestType == 'competitive' && order.provider == null) {
      return _competitiveOfferActions();
    }

    if (order.requestType == 'urgent' && order.provider == null) {
      return _urgentAvailableActions();
    }

    if (order.requestType == 'competitive' && order.provider != null) {
      return _competitiveAssignedNewActions(order);
    }

    return _assignedNewActions(order);
  }

  Widget _assignedNewActions(ServiceRequest order) {
    final rejectedByClient = order.providerInputsApproved == false;
    final rejectionNote = (order.providerInputsDecisionNote ?? '').trim();
    final showAcceptButton = order.requestType != 'urgent';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (showAcceptButton) ...[
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _actionLoading ? null : _accept,
            icon: const Icon(Icons.check_circle_outline, color: Colors.white),
            label: _actionLoading
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('قبول الطلب',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
      if (rejectedByClient) ...[
        _readOnlyBox(
          label: 'سبب رفض العميل للتفاصيل السابقة',
          value: rejectionNote.isEmpty ? '-' : rejectionNote,
          maxLines: 4,
        ),
        const SizedBox(height: 12),
      ],
      _sectionTitle(rejectedByClient
          ? 'إعادة إرسال تفاصيل التنفيذ'
          : 'إرسال تفاصيل التنفيذ'),
      _dateLine(
        label: 'موعد التسليم المتوقع',
        value: _expectedDeliveryAt,
        onPick: () async {
          final picked =
              await _pickDateTime(_expectedDeliveryAt ?? DateTime.now());
          if (picked != null && mounted) {
            setState(() => _expectedDeliveryAt = picked);
          }
        },
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
            child: _moneyField(
                'قيمة الخدمة المقدرة (SR)', _estimatedAmountController)),
        const SizedBox(width: 10),
        Expanded(
            child:
                _moneyField('المبلغ المستلم (SR)', _receivedAmountController)),
      ]),
      const SizedBox(height: 10),
      _textField(
          controller: _noteController, enabled: true, hint: 'ملاحظة (اختياري)'),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _actionLoading ? null : _updateProgress,
          style: ElevatedButton.styleFrom(
            backgroundColor: _mainColor,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: Text(
              rejectedByClient
                  ? 'إعادة إرسال التفاصيل'
                  : 'إرسال التفاصيل للعميل',
              style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
        ),
      ),
      const SizedBox(height: 16),
      _sectionTitle('رفض الطلب'),
      _textField(
          controller: _cancelReasonController,
          enabled: true,
          maxLines: 2,
          hint: 'سبب الإلغاء...'),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: _actionLoading ? null : _reject,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            side: const BorderSide(color: Colors.red),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: const Text('رفض الطلب',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  color: Colors.red)),
        ),
      ),
    ]);
  }

  Widget _urgentAvailableActions() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _readOnlyBox(
        label: 'طلب عاجل متاح',
        value:
            'هذا الطلب العاجل متاح الآن لك. عند القبول سيتم إسناده لك مباشرة.',
        maxLines: 4,
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _actionLoading ? null : _accept,
          icon: const Icon(Icons.flash_on, color: Colors.white),
          label: _actionLoading
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text(
                  'قبول الطلب العاجل',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _competitiveOfferActions() {
    if (_offerAlreadySent) {
      return _readOnlyBox(
        label: 'عرض السعر',
        value: 'تم إرسال عرضك على هذا الطلب. بانتظار قرار العميل.',
        maxLines: 3,
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _readOnlyBox(
        label: 'طلب عروض أسعار متاح',
        value:
            'أدخل السعر ومدة التنفيذ لإرسال عرضك للعميل. يمكنك إرسال عرض واحد لكل طلب.',
        maxLines: 4,
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: _moneyField('سعر العرض (SR)', _offerPriceController),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'مدة التنفيذ (يوم)',
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 12),
                ),
                const SizedBox(height: 6),
                _textField(
                  controller: _offerDurationDaysController,
                  enabled: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: false),
                  hint: 'مثال: 5',
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      _textField(
        controller: _offerNoteController,
        enabled: true,
        maxLines: 3,
        hint: 'ملاحظة للعميل (اختياري)',
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _actionLoading ? null : _sendCompetitiveOffer,
          icon: const Icon(Icons.local_offer_outlined, color: Colors.white),
          label: _actionLoading
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text(
                  'إرسال عرض السعر',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _competitiveAssignedNewActions(ServiceRequest order) {
    final rejectedByClient = order.providerInputsApproved == false;
    final rejectionNote = (order.providerInputsDecisionNote ?? '').trim();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (rejectedByClient) ...[
        _readOnlyBox(
          label: 'سبب رفض العميل للتفاصيل السابقة',
          value: rejectionNote.isEmpty ? '-' : rejectionNote,
          maxLines: 4,
        ),
        const SizedBox(height: 12),
      ],
      _sectionTitle(rejectedByClient
          ? 'إعادة إرسال تفاصيل التنفيذ'
          : 'إرسال تفاصيل التنفيذ'),
      _dateLine(
        label: 'موعد التسليم المتوقع',
        value: _expectedDeliveryAt,
        onPick: () async {
          final picked =
              await _pickDateTime(_expectedDeliveryAt ?? DateTime.now());
          if (picked != null && mounted) {
            setState(() => _expectedDeliveryAt = picked);
          }
        },
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
            child: _moneyField(
                'قيمة الخدمة المقدرة (SR)', _estimatedAmountController)),
        const SizedBox(width: 10),
        Expanded(
            child:
                _moneyField('المبلغ المستلم (SR)', _receivedAmountController)),
      ]),
      const SizedBox(height: 10),
      _textField(
          controller: _noteController, enabled: true, hint: 'ملاحظة (اختياري)'),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _actionLoading ? null : _updateProgress,
          style: ElevatedButton.styleFrom(
            backgroundColor: _mainColor,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: Text(
              rejectedByClient
                  ? 'إعادة إرسال التفاصيل'
                  : 'إرسال التفاصيل للعميل',
              style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
        ),
      ),
    ]);
  }

  Widget _inProgressActions() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('تحديث التقدم'),
      _dateLine(
        label: 'موعد التسليم المتوقع',
        value: _expectedDeliveryAt,
        onPick: () async {
          final picked =
              await _pickDateTime(_expectedDeliveryAt ?? DateTime.now());
          if (picked != null && mounted) {
            setState(() => _expectedDeliveryAt = picked);
          }
        },
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
            child: _moneyField(
                'قيمة الخدمة المقدرة (SR)', _estimatedAmountController)),
        const SizedBox(width: 10),
        Expanded(
            child:
                _moneyField('المبلغ المستلم (SR)', _receivedAmountController)),
      ]),
      const SizedBox(height: 10),
      _textField(
          controller: _noteController, enabled: true, hint: 'ملاحظة (اختياري)'),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _actionLoading ? null : _updateProgress,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: const Text('تحديث التقدم',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
        ),
      ),
      const SizedBox(height: 16),

      // إكمال
      _sectionTitle('إكمال الطلب'),
      _dateLine(
        label: 'موعد التسليم الفعلي',
        value: _deliveredAt,
        onPick: () async {
          final picked = await _pickDateTime(_deliveredAt ?? DateTime.now());
          if (picked != null && mounted) {
            setState(() => _deliveredAt = picked);
          }
        },
      ),
      const SizedBox(height: 12),
      _moneyField('قيمة الخدمة الفعلية (SR)', _actualAmountController),
      const SizedBox(height: 12),
      _sectionTitle('مرفقات الإكمال (فواتير/صور/ملفات)'),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _actionLoading ? null : _pickCompletionAttachments,
          icon: const Icon(Icons.attach_file),
          label: const Text('إضافة مرفقات'),
        ),
      ),
      if (_completionAttachments.isNotEmpty) ...[
        const SizedBox(height: 8),
        ..._completionAttachments.asMap().entries.map(
              (entry) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.insert_drive_file_outlined, size: 18),
                title: Text(
                  entry.value.path.split('\\').last,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 18, color: Colors.red),
                  onPressed: _actionLoading
                      ? null
                      : () {
                          setState(() {
                            _completionAttachments.removeAt(entry.key);
                          });
                        },
                ),
              ),
            ),
      ],
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _actionLoading ? null : _complete,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: const Text('إكمال الطلب',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
        ),
      ),
      const SizedBox(height: 16),

      // رفض
      _sectionTitle('رفض / إلغاء الطلب'),
      _textField(
          controller: _cancelReasonController,
          enabled: true,
          maxLines: 2,
          hint: 'سبب الإلغاء...'),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: _actionLoading ? null : _reject,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            side: const BorderSide(color: Colors.red),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: const Text('إلغاء الطلب',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  color: Colors.red)),
        ),
      ),
    ]);
  }

  Widget _completedInfo(ServiceRequest order) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _readOnlyBox(
          label: 'موعد التسليم الفعلي',
          value: order.deliveredAt != null
              ? _formatDateOnly(order.deliveredAt!)
              : '-'),
      const SizedBox(height: 10),
      _readOnlyBox(
          label: 'قيمة الخدمة الفعلية (SR)',
          value: order.actualServiceAmount ?? '-'),
      if (order.reviewRating != null) ...[
        const SizedBox(height: 10),
        _readOnlyBox(
            label: 'تقييم العميل',
            value: '${order.reviewRating}/5 — ${order.reviewComment ?? ''}'),
      ],
    ]);
  }

  Widget _cancelledInfo(ServiceRequest order) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _readOnlyBox(
          label: 'تاريخ الإلغاء',
          value: order.canceledAt != null
              ? _formatDateOnly(order.canceledAt!)
              : '-'),
      const SizedBox(height: 10),
      _readOnlyBox(label: 'سبب الإلغاء', value: order.cancelReason ?? '-'),
    ]);
  }

  Widget _attachmentRow(RequestAttachment attachment) {
    final fileName = _attachmentFileName(attachment);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openAttachment(attachment),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(children: [
              Icon(_attachIcon(attachment.fileType),
                  size: 18, color: Colors.black45),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(fileName,
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 13))),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _mainColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _mainColor.withAlpha(60)),
                ),
                child: Text(attachment.fileType.toUpperCase(),
                    style: const TextStyle(
                        fontFamily: 'Cairo', fontSize: 11, color: _mainColor)),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.open_in_new, size: 16, color: Colors.black38),
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

  IconData _attachIcon(String type) {
    switch (type) {
      case 'image':
        return Icons.image;
      case 'video':
        return Icons.videocam;
      case 'audio':
        return Icons.audiotrack;
      default:
        return Icons.attach_file;
    }
  }
}
