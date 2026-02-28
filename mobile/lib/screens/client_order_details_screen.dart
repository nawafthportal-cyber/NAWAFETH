import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:flutter_rating_bar/flutter_rating_bar.dart';

import '../models/service_request_model.dart';
import '../services/account_mode_service.dart';
import '../services/marketplace_service.dart';

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

class _ClientOrderDetailsScreenState extends State<ClientOrderDetailsScreen> {
  static const Color _mainColor = Colors.deepPurple;

  ServiceRequest? _order;
  bool _loading = true;
  String? _error;
  bool _saving = false;
  bool _accountChecked = false;
  bool _isProviderMode = false;

  late final TextEditingController _titleController;
  late final TextEditingController _detailsController;
  final TextEditingController _reminderController = TextEditingController();

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

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _detailsController = TextEditingController();
    _ensureClientAccount();
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
    _titleController.dispose();
    _detailsController.dispose();
    _reminderController.dispose();
    _ratingCommentController.dispose();
    super.dispose();
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

    setState(() {
      _order = order;
      _titleController.text = order.title;
      _detailsController.text = order.description;

      _ratingResponseSpeed = order.reviewResponseSpeed ?? 0;
      _ratingCostValue = order.reviewCostValue ?? 0;
      _ratingQuality = order.reviewQuality ?? 0;
      _ratingCredibility = order.reviewCredibility ?? 0;
      _ratingOnTime = order.reviewOnTime ?? 0;
      _ratingCommentController.text = order.reviewComment ?? '';

      _loading = false;
    });
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
    return '${value.toStringAsFixed(0)} (SR)';
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

  // ─── helper widgets ───

  Widget _infoRow(String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(value,
          style: const TextStyle(
              fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold)),
    );
  }

  Widget _infoLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text,
          style: const TextStyle(
              fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold)),
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
            child: Text(title,
                style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 14,
                    fontWeight: FontWeight.bold))),
        if (canEdit)
          TextButton(
            onPressed: onToggle,
            child: Text(isEditing ? 'إيقاف' : 'تعديل',
                style: const TextStyle(
                    fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
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
              child: Text(label,
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 13,
                      color: isDark ? Colors.white70 : Colors.black87))),
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
        backgroundColor: isDark ? const Color(0xFF121212) : Colors.grey[100],
        appBar: AppBar(
          backgroundColor: _mainColor,
          title: const Text('تفاصيل الطلب',
              style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            IconButton(
              onPressed: _openChat,
              tooltip: 'فتح محادثة',
              icon: const Icon(Icons.chat_bubble_outline, color: Colors.white),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!,
                            style: const TextStyle(fontFamily: 'Cairo')),
                        const SizedBox(height: 12),
                        ElevatedButton(
                            onPressed: _loadDetail,
                            child: const Text('إعادة المحاولة',
                                style: TextStyle(fontFamily: 'Cairo'))),
                      ],
                    ),
                  )
                : _buildContent(isDark),
      ),
    );
  }

  Widget _buildContent(bool isDark) {
    final order = _order!;
    final statusColor = _statusColor(order.statusGroup);
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final borderColor = isDark ? Colors.white10 : Colors.grey.shade200;
    final canEdit = order.status == 'new';

    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ─── Header card ───
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
                          Expanded(
                            child: Row(children: [
                              Text(order.displayId,
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black87)),
                              const SizedBox(width: 8),
                              if (order.requestType != 'normal')
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: order.requestType == 'urgent'
                                        ? Colors.red.withAlpha(25)
                                        : Colors.blue.withAlpha(25),
                                    borderRadius: BorderRadius.circular(12),
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
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              color: statusColor.withAlpha(38),
                              borderRadius: BorderRadius.circular(20),
                              border:
                                  Border.all(color: statusColor.withAlpha(90)),
                            ),
                            child: Text(
                              order.statusLabel.isNotEmpty
                                  ? order.statusLabel
                                  : order.statusGroup,
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: statusColor),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(order.title,
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                              color:
                                  isDark ? Colors.white70 : Colors.black54)),
                      if (order.categoryName != null)
                        Text(
                            '${order.categoryName} / ${order.subcategoryName ?? ''}',
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 12,
                                color: isDark
                                    ? Colors.white54
                                    : Colors.black45)),
                      const SizedBox(height: 6),
                      Text(_formatDate(order.createdAt),
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              color:
                                  isDark ? Colors.white54 : Colors.black54)),
                      if (order.providerName != null) ...[
                        const SizedBox(height: 6),
                        Row(children: [
                          const Icon(Icons.person_outline,
                              size: 16, color: _mainColor),
                          const SizedBox(width: 4),
                          Text(order.providerName!,
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.black54)),
                          if (order.providerPhone != null) ...[
                            const SizedBox(width: 12),
                            const Icon(Icons.phone,
                                size: 14, color: _mainColor),
                            const SizedBox(width: 4),
                            Text(order.providerPhone!,
                                style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.white54
                                        : Colors.black45)),
                          ],
                        ]),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // ─── مكتمل: التسليم + التقييم ───
                if (order.statusGroup == 'completed') ...[
                  _completedCard(cardColor, borderColor, isDark),
                  const SizedBox(height: 12),
                ],

                // ─── تحت التنفيذ: المالية ───
                if (order.statusGroup == 'in_progress') ...[
                  _inProgressCard(order, cardColor, borderColor, isDark),
                  const SizedBox(height: 12),
                ],

                // ─── ملغي ───
                if (order.statusGroup == 'cancelled') ...[
                  _cancelledCard(order, cardColor, borderColor),
                  const SizedBox(height: 12),
                ],

                // ─── العنوان ───
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
                          canEdit: canEdit,
                          isEditing: _editTitle,
                          onToggle: () =>
                              setState(() => _editTitle = !_editTitle)),
                      TextField(
                        controller: _titleController,
                        enabled: _editTitle && canEdit,
                        decoration:
                            const InputDecoration(border: OutlineInputBorder()),
                        style: const TextStyle(fontFamily: 'Cairo'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ─── التفاصيل ───
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
                          canEdit: canEdit,
                          isEditing: _editDetails,
                          onToggle: () =>
                              setState(() => _editDetails = !_editDetails)),
                      TextField(
                        controller: _detailsController,
                        enabled: _editDetails && canEdit,
                        minLines: 4,
                        maxLines: 7,
                        decoration:
                            const InputDecoration(border: OutlineInputBorder()),
                        style: const TextStyle(fontFamily: 'Cairo'),
                      ),
                      if (canEdit) ...[
                        const SizedBox(height: 8),
                        Text(
                            'تنبيه: سيتم إشعار مقدم الخدمة بأي تعديل في بيانات الطلب.',
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 12,
                                color: isDark
                                    ? Colors.white54
                                    : Colors.black54)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ─── المرفقات ───
                _attachmentsCard(order, cardColor, borderColor, isDark),
                const SizedBox(height: 12),

                // ─── سجل الحالة ───
                if (order.statusLogs.isNotEmpty) ...[
                  _statusLogsCard(order, cardColor, borderColor, isDark),
                  const SizedBox(height: 12),
                ],

                // ─── تذكير ───
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
                      const Row(children: [
                        Icon(Icons.notifications_none, color: _mainColor),
                        SizedBox(width: 8),
                        Expanded(
                            child: Text('ارسال تنبيه وتذكير للمختص',
                                style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold))),
                      ]),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _reminderController,
                        minLines: 6,
                        maxLines: 10,
                        decoration: InputDecoration(
                          hintText: 'اكتب رسالتك هنا...',
                          hintStyle: const TextStyle(fontFamily: 'Cairo'),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        style: const TextStyle(fontFamily: 'Cairo'),
                      ),
                    ],
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

  Widget _completedCard(Color cardColor, Color borderColor, bool isDark) {
    final order = _order!;
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
          _infoLabel('قيمة الخدمة الفعلية (SR)'),
          _infoRow(_formatMoney(order.actualAmount)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () =>
                  setState(() => _showRatingForm = !_showRatingForm),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: _mainColor),
              ),
              child: const Text('تقييم الخدمة',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      color: _mainColor)),
            ),
          ),
          if (_showRatingForm) ...[
            const SizedBox(height: 12),
            _ratingRow(
                label: 'سرعة الاستجابة',
                value: _ratingResponseSpeed,
                onChanged: (v) => setState(() => _ratingResponseSpeed = v)),
            _ratingRow(
                label: 'التكلفة مقابل الخدمة',
                value: _ratingCostValue,
                onChanged: (v) => setState(() => _ratingCostValue = v)),
            _ratingRow(
                label: 'جودة الخدمة',
                value: _ratingQuality,
                onChanged: (v) => setState(() => _ratingQuality = v)),
            _ratingRow(
                label: 'المصداقية',
                value: _ratingCredibility,
                onChanged: (v) => setState(() => _ratingCredibility = v)),
            _ratingRow(
                label: 'وقت الإنجاز',
                value: _ratingOnTime,
                onChanged: (v) => setState(() => _ratingOnTime = v)),
            const SizedBox(height: 12),
            const Text('تعليق على الخدمة المقدمة (300 حرف)',
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
              decoration: const InputDecoration(border: OutlineInputBorder()),
              style: const TextStyle(fontFamily: 'Cairo'),
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
          _infoLabel('قيمة الخدمة المقدرة (SR)'),
          _infoRow(_formatMoney(order.estimatedAmount)),
          const SizedBox(height: 10),
          _infoLabel('المبلغ المستلم (SR)'),
          _infoRow(_formatMoney(order.receivedAmt)),
          const SizedBox(height: 10),
          _infoLabel('المبلغ المتبقي (SR)'),
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

  Widget _attachmentsCard(
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
          else
            ...order.attachments.map(
              (a) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(children: [
                  Icon(_attachmentIcon(a.fileType),
                      size: 18, color: Colors.grey),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text(a.fileUrl.split('/').last,
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              color: isDark
                                  ? Colors.white70
                                  : Colors.black87))),
                  Text(a.fileType.toUpperCase(),
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          color:
                              isDark ? Colors.white54 : Colors.black54)),
                ]),
              ),
            ),
        ],
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
