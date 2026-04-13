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
    extends State<ProviderOrderDetailsScreen> {
  static const Color _mainColor = Colors.deepPurple;

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
    _badgeHandle = UnreadBadgeService.acquire();
    _badgeHandle?.addListener(_handleBadgeChange);
    _handleBadgeChange();
    _ensureProviderAccount();
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: const TextStyle(
              fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14)),
    );
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: color.withAlpha(35),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: Text(text,
          style: TextStyle(
              color: color,
              fontFamily: 'Cairo',
              fontSize: 12,
              fontWeight: FontWeight.bold)),
    );
  }

  Widget _infoLine(
      {required IconData icon, required String label, required String value}) {
    return Row(children: [
      Icon(icon, size: 18, color: _mainColor),
      const SizedBox(width: 8),
      Text(label,
          style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: Colors.black87)),
      const SizedBox(width: 8),
      Expanded(
          child: Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54))),
    ]);
  }

  Widget _readOnlyBox(
      {required String label, required String value, int maxLines = 3}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: const TextStyle(
              fontFamily: 'Cairo', fontWeight: FontWeight.w700, fontSize: 13)),
      const SizedBox(height: 8),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _mainColor.withAlpha(50)),
        ),
        child: Text(value.trim().isEmpty ? '-' : value,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontFamily: 'Cairo', fontSize: 13, height: 1.35)),
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
    return TextField(
      controller: controller,
      enabled: enabled,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _mainColor.withAlpha(70)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _mainColor.withAlpha(170), width: 1.3),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _mainColor.withAlpha(35)),
        ),
      ),
    );
  }

  Widget _dateLine({
    required String label,
    required DateTime? value,
    required VoidCallback onPick,
  }) {
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _mainColor.withAlpha(70)),
          color: Colors.white,
        ),
        child: Row(children: [
          const Icon(Icons.calendar_month, size: 18, color: _mainColor),
          const SizedBox(width: 8),
          Expanded(
              child: Text(
                  value == null ? label : '$label: ${_formatDateOnly(value)}',
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 13))),
          const Icon(Icons.expand_more, color: Colors.black45),
        ]),
      ),
    );
  }

  Widget _moneyField(String label, TextEditingController controller) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontFamily: 'Cairo', fontSize: 12)),
      const SizedBox(height: 6),
      _textField(
        controller: controller,
        enabled: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        hint: '0',
      ),
    ]);
  }

  // ─── Main build ───

  @override
  Widget build(BuildContext context) {
    if (!_accountChecked || _loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_isProviderAccount) return const Scaffold(body: SizedBox.shrink());
    if (_error != null) {
      return Scaffold(
          body: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_error!, style: const TextStyle(fontFamily: 'Cairo')),
        const SizedBox(height: 12),
        ElevatedButton(
            onPressed: _loadDetail,
            child: const Text('إعادة المحاولة',
                style: TextStyle(fontFamily: 'Cairo'))),
      ])));
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
        backgroundColor: Colors.white,
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
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // عنوان
            Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                decoration: BoxDecoration(
                  color: _mainColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: _mainColor.withAlpha(70)),
                ),
                child: const Text('تفاصيل الطلب',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: _mainColor)),
              ),
            ),
            const SizedBox(height: 12),

            // ─── بيانات العميل ───
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _mainColor.withAlpha(8),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _mainColor.withAlpha(50)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.person_outline, color: _mainColor),
                    SizedBox(width: 8),
                    Text('بيانات العميل',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: _mainColor)),
                  ]),
                  const SizedBox(height: 12),
                  _infoLine(
                      icon: Icons.badge_outlined,
                      label: 'الاسم',
                      value: order.clientName ?? 'غير متوفر'),
                  const SizedBox(height: 10),
                  _infoLine(
                      icon: Icons.phone,
                      label: 'الجوال',
                      value: (order.clientPhone ?? '').trim().isEmpty
                          ? 'غير متوفر'
                          : order.clientPhone!),
                  const SizedBox(height: 10),
                  _infoLine(
                      icon: Icons.location_on_outlined,
                      label: 'المدينة',
                      value: (order.city ?? '').trim().isEmpty
                          ? 'غير متوفر'
                          : order.city!),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ─── Header card ───
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black12,
                      blurRadius: 8,
                      offset: Offset(0, 3)),
                ],
              ),
              child: Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text(order.displayId,
                            style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 14,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(width: 6),
                        if (order.requestType != 'normal')
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: order.requestType == 'urgent'
                                  ? Colors.red.withAlpha(25)
                                  : Colors.blue.withAlpha(25),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(order.requestTypeLabel,
                                style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: order.requestType == 'urgent'
                                        ? Colors.red
                                        : Colors.blue)),
                          ),
                      ]),
                      const SizedBox(height: 6),
                      if (order.categoryName != null)
                        Text(
                            '${order.categoryName} / ${order.subcategoryName ?? ''}',
                            style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 12,
                                color: Colors.black54)),
                      Text(_formatDate(order.createdAt),
                          style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              color: Colors.black54)),
                    ],
                  ),
                ),
                _pill(
                    order.statusLabel.isNotEmpty
                        ? order.statusLabel
                        : order.statusGroup,
                    statusColor),
              ]),
            ),
            const SizedBox(height: 14),

            // ─── العنوان + التفاصيل ───
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _readOnlyBox(
                      label: 'عنوان الطلب', value: order.title, maxLines: 2),
                  const SizedBox(height: 12),
                  _readOnlyBox(
                      label: 'تفاصيل الطلب',
                      value: order.description,
                      maxLines: 6),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ─── المرفقات ───
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('مرفقات العميل',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                  if (order.attachments.isEmpty)
                    const Text('لا توجد مرفقات',
                        style: TextStyle(
                            fontFamily: 'Cairo', color: Colors.black54))
                  else ...[
                    if (finalDeliveryAttachments.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      const Text('مرفقات التسليم النهائي',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: _mainColor)),
                      ...finalDeliveryAttachments.map((a) => _attachmentRow(a)),
                      if (regularAttachments.isNotEmpty)
                        const SizedBox(height: 8),
                    ],
                    if (regularAttachments.isNotEmpty) ...[
                      if (finalDeliveryAttachments.isNotEmpty)
                        const Text('مرفقات الطلب',
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold,
                                fontSize: 12)),
                      ...regularAttachments.map((a) => _attachmentRow(a)),
                    ],
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ─── سجل الحالة ───
            if (order.statusLogs.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('سجل تغيير الحالة'),
                    ...order.statusLogs.map((log) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.circle,
                                  size: 8, color: _mainColor),
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
                                            fontWeight: FontWeight.bold)),
                                    if (log.note != null &&
                                        log.note!.isNotEmpty)
                                      Text(log.note!,
                                          style: const TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: 12,
                                              color: Colors.black54)),
                                    if (log.createdAt != null)
                                      Text(_formatDate(log.createdAt!),
                                          style: const TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: 11,
                                              color: Colors.black38)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        )),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            // ─── Actions section ───
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('إجراء على الطلب'),
                  _buildActionsForStatus(order),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // ─── Bottom buttons ───
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: Colors.grey.shade400),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('رجوع',
                      style: TextStyle(
                          fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                ),
              ),
            ]),
          ],
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
              backgroundColor: Colors.green,
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
