import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:nawafeth/services/billing_service.dart';
import 'package:nawafeth/services/promo_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

const _brandColor = Colors.deepPurple;
const _homeBannerRequiredWidth = 1920;
const _homeBannerRequiredHeight = 840;

const _statusLabels = {
  'new': 'جديد',
  'in_review': 'قيد المراجعة',
  'quoted': 'تم التسعير',
  'pending_payment': 'بانتظار الدفع',
  'active': 'مفعل',
  'completed': 'مكتمل',
  'rejected': 'مرفوض',
  'expired': 'منتهي',
  'cancelled': 'ملغي',
};

const _opsLabels = {
  'new': 'جديد',
  'in_progress': 'تحت المعالجة',
  'completed': 'مكتمل',
};

const _invoiceStatusLabels = {
  'draft': 'مسودة',
  'pending': 'بانتظار الدفع',
  'paid': 'مدفوعة',
  'failed': 'فشلت',
  'cancelled': 'ملغاة',
  'refunded': 'مسترجعة',
};

const _frequencyLabels = {
  '10s': 'كل 10 ثواني',
  '20s': 'كل 20 ثانية',
  '30s': 'كل 30 ثانية',
  '60s': 'كل دقيقة',
  '300s': 'كل 5 دقائق',
  '900s': 'كل 15 دقيقة',
  '1800s': 'كل 30 دقيقة',
  '3600s': 'كل ساعة',
};

const _searchScopeLabels = {
  'default': 'قائمة البحث الافتراضية',
  'main_results': 'نتائج البحث الرئيسية',
  'category_match': 'نتائج البحث المطابقة للتصنيف',
};

const _searchScopeOrder = ['default', 'main_results', 'category_match'];

const _searchPositionLabels = {
  'first': 'الأول في القائمة',
  'second': 'الثاني في القائمة',
  'top5': 'من أول خمسة أسماء',
  'top10': 'من أول عشرة أسماء',
};

const _serviceAllowedExtensions = <String, List<String>>{
  'home_banner': ['jpg', 'jpeg', 'png', 'webp', 'mp4'],
  'sponsorship': ['jpg', 'jpeg', 'png', 'webp', 'mp4', 'mov', 'avi', 'mkv', 'webm'],
  'promo_messages': ['jpg', 'jpeg', 'png', 'webp', 'mp4', 'mov', 'avi', 'mkv', 'webm'],
};

const _serviceAttachmentHints = <String, String>{
  'home_banner': 'الأنواع المدعومة: JPG, JPEG, PNG, WEBP, MP4',
  'sponsorship': 'الأنواع المدعومة: صور + فيديو (JPG, PNG, WEBP, MP4, MOV, AVI, MKV, WEBM)',
  'promo_messages': 'الأنواع المدعومة: صور + فيديو (JPG, PNG, WEBP, MP4, MOV, AVI, MKV, WEBM)',
};

String? validatePromoMessageOrAssetRequirement({
  required bool requiresMessage,
  required String messageText,
  required int assetCount,
}) {
  if (!requiresMessage) return null;
  if (messageText.trim().isEmpty && assetCount <= 0) {
    return 'أدخل نص الرسالة أو أضف مرفقًا';
  }
  return null;
}

List<String> orderedSearchScopes(Iterable<String> selectedScopes) {
  final set = selectedScopes.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
  return _searchScopeOrder.where(set.contains).toList(growable: false);
}

String buildHomeBannerVideoAutofitWarning({
  required int requiredWidth,
  required int requiredHeight,
  required int currentWidth,
  required int currentHeight,
}) {
  return 'WARN: سيتم ضبط الفيديو تلقائيًا إلى ${requiredWidth}x$requiredHeight على الخادم '
      '(المقاس الحالي ${currentWidth}x$currentHeight).';
}

const _promoServices = [
  _PromoServiceDef(
    type: 'home_banner',
    label: 'بنر الصفحة الرئيسية',
    icon: Icons.web_asset_rounded,
    needsRange: true,
    needsAssets: true,
    needsRedirect: true,
    needsSpecs: true,
    attachmentsRequired: true,
  ),
  _PromoServiceDef(
    type: 'featured_specialists',
    label: 'شريط أبرز المختصين',
    icon: Icons.star_rounded,
    needsRange: true,
    needsFrequency: true,
  ),
  _PromoServiceDef(
    type: 'portfolio_showcase',
    label: 'شريط البنرات والمشاريع',
    icon: Icons.collections_rounded,
    needsRange: true,
    needsFrequency: true,
  ),
  _PromoServiceDef(
    type: 'snapshots',
    label: 'شريط اللمحات',
    icon: Icons.view_carousel_rounded,
    needsRange: true,
    needsFrequency: true,
  ),
  _PromoServiceDef(
    type: 'search_results',
    label: 'الظهور في قوائم البحث',
    icon: Icons.manage_search_rounded,
    needsRange: true,
    needsSearch: true,
    needsCategory: true,
  ),
  _PromoServiceDef(
    type: 'promo_messages',
    label: 'الرسائل الدعائية',
    icon: Icons.campaign_rounded,
    needsSendAt: true,
    needsChannels: true,
    needsMessage: true,
    needsAssets: true,
    needsSpecs: true,
  ),
  _PromoServiceDef(
    type: 'sponsorship',
    label: 'الرعاية',
    icon: Icons.workspace_premium_rounded,
    needsRange: true,
    needsAssets: true,
    needsRedirect: true,
    needsMessage: true,
    needsSpecs: true,
    needsSponsor: true,
    attachmentsRequired: true,
  ),
];

class PromotionScreen extends StatefulWidget {
  const PromotionScreen({super.key});

  @override
  State<PromotionScreen> createState() => _PromotionScreenState();
}

class _PromotionScreenState extends State<PromotionScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _requests = [];

  bool _canPayRequest(Map<String, dynamic> request) {
    final status = (request['status'] as String? ?? '').trim();
    final invoiceId = int.tryParse('${request['invoice'] ?? ''}');
    final paymentEffective = request['payment_effective'] == true;
    return invoiceId != null &&
        !paymentEffective &&
        (status == 'pending_payment' || status == 'quoted');
  }

  void _snack(String message, bool error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: error ? Colors.red : Colors.green,
        content: Text(message, style: const TextStyle(fontFamily: 'Cairo')),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadRequests();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRequests({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    final res = await PromoService.fetchMyRequests();
    if (!mounted) return;
    if (res.isSuccess) {
      final list =
          res.dataAsList ?? (res.dataAsMap?['results'] as List<dynamic>? ?? []);
      _requests = list
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    } else {
      _error = res.error ?? 'تعذر تحميل طلبات الترويج';
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F4FC),
        appBar: AppBar(
          backgroundColor: _brandColor,
          centerTitle: true,
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text(
            'إدارة الترويج',
            style: TextStyle(
              fontFamily: 'Cairo',
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: const [Tab(text: 'طلباتي'), Tab(text: 'طلب جديد')],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildRequestsTab(),
            _PromoComposer(
              onCreated: () {
                _tabController.animateTo(0);
                _loadRequests(silent: true);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestsTab() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: _brandColor),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: const TextStyle(fontFamily: 'Cairo')),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _loadRequests,
                style: ElevatedButton.styleFrom(backgroundColor: _brandColor),
                child: const Text(
                  'إعادة المحاولة',
                  style: TextStyle(fontFamily: 'Cairo', color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_requests.isEmpty) {
      return const Center(
        child: Text(
          'لا توجد طلبات ترويج حتى الآن',
          style: TextStyle(fontFamily: 'Cairo', color: Colors.black54),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _loadRequests(silent: true),
      color: _brandColor,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'قائمة طلبات الترويج',
                    style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700, fontSize: 16, color: _brandColor),
                  ),
                ),
                Container(
                  width: 10, height: 10,
                  decoration: const BoxDecoration(color: _brandColor, shape: BoxShape.circle),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(const Color(0xFFF3EDFC)),
                border: TableBorder.all(color: const Color(0xFFD6C8EF)),
                headingTextStyle: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700, color: _brandColor, fontSize: 12),
                dataTextStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                columnSpacing: 14,
                columns: const [
                  DataColumn(label: Text('رقم الطلب')),
                  DataColumn(label: Text('اسم العميل')),
                  DataColumn(label: Text('الأولوية')),
                  DataColumn(label: Text('تاريخ ووقت اعتماد الطلب')),
                  DataColumn(label: Text('حالة الطلب')),
                  DataColumn(label: Text('المكلف بالطلب')),
                  DataColumn(label: Text('تاريخ ووقت التكليف')),
                ],
                rows: _requests.map((req) => _buildRequestRow(req)).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  DataRow _buildRequestRow(Map<String, dynamic> request) {
    final status = (request['status'] as String? ?? 'new').trim();
    final code = (request['code'] as String? ?? '').trim();
    final title = (request['title'] as String? ?? '').trim();
    final assignee = (request['assigned_to_name'] as String? ?? request['assigned_to'] as String? ?? '').trim();
    final priority = request['priority'] ?? '';
    final createdAt = (request['created_at'] as String? ?? request['quoted_at'] as String? ?? '').trim();
    final assignedAt = (request['assigned_at'] as String? ?? '').trim();

    String fmtDt(String iso) {
      if (iso.isEmpty) return '—';
      try {
        final dt = DateTime.parse(iso).toLocal();
        return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} – ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (_) {
        return iso;
      }
    }

    return DataRow(
      onSelectChanged: (_) => _showRequestDialog(request),
      cells: [
        DataCell(Text(code, style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w600, color: _brandColor))),
        DataCell(Text(title.isNotEmpty ? title : '—')),
        DataCell(Text('${priority is int ? priority : '—'}')),
        DataCell(Text(fmtDt(createdAt))),
        DataCell(Text(_statusLabels[status] ?? status)),
        DataCell(Text(assignee.isNotEmpty ? assignee : '—')),
        DataCell(Text(fmtDt(assignedAt))),
      ],
    );
  }

  Future<void> _showRequestDialog(Map<String, dynamic> request) async {
    // Fetch fresh detail to get full items + assets
    Map<String, dynamic> detail = request;
    final id = request['id'];
    if (id != null) {
      final res = await PromoService.fetchRequestDetail(id as int);
      if (res.isSuccess && res.dataAsMap != null) detail = res.dataAsMap!;
    }
    if (!mounted) return;

    final items = _asMapList(detail['items']);
    final assets = _asMapList(detail['assets']);
    final canPay = _canPayRequest(detail);
    final status = (detail['status'] as String? ?? '').trim();
    final rejectReason = (detail['reject_reason'] as String? ?? '').trim();
    final action = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          (detail['title'] as String? ?? 'طلب ترويج').trim(),
          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _line('رقم الطلب', (detail['code'] as String? ?? '').trim()),
                _line('الحالة', _statusLabels[detail['status']] ?? '${detail['status']}'),
                _line(
                  'التنفيذ',
                  _opsLabels[detail['ops_status']] ?? '${detail['ops_status'] ?? ''}',
                ),
                if (detail['start_at'] != null)
                  _line('بداية الحملة', _fmtDate(detail['start_at'])),
                if (detail['end_at'] != null)
                  _line('نهاية الحملة', _fmtDate(detail['end_at'])),
                if (status == 'rejected' && rejectReason.isNotEmpty)
                  _line('سبب الرفض', rejectReason),
                if ((detail['invoice_code'] as String? ?? '').trim().isNotEmpty)
                  _line('رقم الفاتورة', (detail['invoice_code'] as String).trim()),
                if ((detail['invoice_status'] as String? ?? '').trim().isNotEmpty)
                  _line(
                    'حالة الفاتورة',
                    (detail['payment_effective'] == true)
                        ? 'مدفوعة'
                        : (_invoiceStatusLabels[detail['invoice_status']] ??
                            '${detail['invoice_status']}'),
                  ),
                if (detail['invoice_total'] != null)
                  _line('الإجمالي', '${_money(detail['invoice_total'])} ريال'),
                if (detail['invoice_vat'] != null)
                  _line('VAT', '${_money(detail['invoice_vat'])} ريال'),
                if ((detail['quote_note'] as String? ?? '').trim().isNotEmpty)
                  _line('ملاحظة الاعتماد', (detail['quote_note'] as String).trim()),
                const SizedBox(height: 12),
                const Text(
                  'تفاصيل الخدمات',
                  style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 8),
                for (final item in items)
                  _buildItemDetail(item, assets),
                if (status == 'rejected') ...[
                  const SizedBox(height: 8),
                  _buildRejectedGuidance(rejectReason),
                ],
              ],
            ),
          ),
        ),
        actions: [
          if (canPay)
            FilledButton(
              onPressed: () => Navigator.pop(context, 'pay'),
              style: FilledButton.styleFrom(
                backgroundColor: _brandColor,
                foregroundColor: Colors.white,
              ),
              child: const Text(
                'الدفع الآن',
                style: TextStyle(fontFamily: 'Cairo'),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق', style: TextStyle(fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
    if (!mounted || action != 'pay') return;
    await _startPayment(detail);
  }

  String _fmtDate(dynamic v) {
    if (v == null) return '';
    final dt = DateTime.tryParse(v.toString());
    if (dt == null) return v.toString();
    final local = dt.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year} - ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildItemDetail(Map<String, dynamic> item, List<Map<String, dynamic>> allAssets) {
    final sType = item['service_type'] as String? ?? '';
    final label = _serviceLabel(sType);
    final itemId = item['id'];
    final itemAssets = allAssets.where((a) => a['item'] == itemId).toList();
    final nestedAssets = _asMapList(item['assets']);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(spacing: 6, runSpacing: 4, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(color: _brandColor, borderRadius: BorderRadius.circular(12)),
              child: Text(label, style: const TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 12)),
            ),
            if (item['subtotal'] != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(12)),
                child: Text('${_money(item['subtotal'])} ريال', style: const TextStyle(fontFamily: 'Cairo', color: Color(0xFF2E7D32), fontSize: 12)),
              ),
            if (item['duration_days'] != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFFE3F2FD), borderRadius: BorderRadius.circular(12)),
                child: Text('${item['duration_days']} يوم', style: const TextStyle(fontFamily: 'Cairo', color: Color(0xFF1565C0), fontSize: 12)),
              ),
          ]),
          const SizedBox(height: 8),
          if ((item['title'] as String? ?? '').isNotEmpty) _line('العنوان', item['title'] as String),
          if (item['start_at'] != null) _line('بداية', _fmtDate(item['start_at'])),
          if (item['end_at'] != null) _line('نهاية', _fmtDate(item['end_at'])),
          if ((item['frequency_label'] as String? ?? '').isNotEmpty) _line('معدل الظهور', item['frequency_label'] as String),
          if ((item['search_scope_label'] as String? ?? '').isNotEmpty) _line('نطاق البحث', item['search_scope_label'] as String),
          if ((item['search_position_label'] as String? ?? '').isNotEmpty) _line('ترتيب الظهور', item['search_position_label'] as String),
          if ((item['target_category'] as String? ?? '').isNotEmpty) _line('التصنيف', item['target_category'] as String),
          if ((item['target_city'] as String? ?? '').isNotEmpty) _line('المدينة', item['target_city'] as String),
          if (item['send_at'] != null) _line('وقت الإرسال', _fmtDate(item['send_at'])),
          if ((item['redirect_url'] as String? ?? '').isNotEmpty) _line('رابط التحويل', item['redirect_url'] as String),
          if ((item['message_title'] as String? ?? '').isNotEmpty) _line('عنوان الرسالة', item['message_title'] as String),
          if ((item['message_body'] as String? ?? '').isNotEmpty) _line('نص الرسالة', item['message_body'] as String),
          if (item['use_notification_channel'] == true)
            const Padding(padding: EdgeInsets.only(top: 2), child: Text('📲 إشعار', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Color(0xFF2E7D32)))),
          if (item['use_chat_channel'] == true)
            const Padding(padding: EdgeInsets.only(top: 2), child: Text('💬 محادثة', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Color(0xFF1565C0)))),
          if ((item['sponsor_name'] as String? ?? '').isNotEmpty) _line('اسم الراعي', item['sponsor_name'] as String),
          if ((item['sponsor_url'] as String? ?? '').isNotEmpty) _line('رابط الراعي', item['sponsor_url'] as String),
          if (item['sponsorship_months'] != null) _line('مدة الرعاية', '${item['sponsorship_months']} شهر'),
          for (final asset in [...nestedAssets, ...itemAssets])
            _buildAssetRow(asset),
        ],
      ),
    );
  }

  Widget _buildAssetRow(Map<String, dynamic> asset) {
    final typeLabels = {'image': 'صورة', 'video': 'فيديو', 'pdf': 'PDF', 'audio': 'صوت'};
    final typeLabel = typeLabels[asset['asset_type']] ?? (asset['asset_type']?.toString() ?? 'ملف');
    final title = (asset['title'] as String? ?? 'ملف مرفق').trim();
    final fileUrl = (asset['file'] as String? ?? '').trim();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$typeLabel - $title',
              style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (fileUrl.isNotEmpty)
            TextButton(
              onPressed: () => _openUrl(fileUrl),
              child: const Text('عرض', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: _brandColor)),
            ),
        ],
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Widget _buildRejectedGuidance(String rejectReason) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF9ED),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF1D39A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ماذا أفعل بعد الرفض؟',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              color: Color(0xFF7A4B00),
            ),
          ),
          const SizedBox(height: 6),
          if (rejectReason.isNotEmpty)
            Text(
              'السبب: $rejectReason',
              style: const TextStyle(
                fontFamily: 'Cairo',
                color: Color(0xFF7A4B00),
                height: 1.5,
              ),
            ),
          const SizedBox(height: 6),
          const Text(
            'قم بتعديل المحتوى أو المرفقات حسب الملاحظة ثم أنشئ طلبًا جديدًا لإعادة المراجعة.',
            style: TextStyle(
              fontFamily: 'Cairo',
              color: Color(0xFF7A4B00),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startPayment(Map<String, dynamic> request) async {
    final invoiceId = int.tryParse('${request['invoice'] ?? ''}');
    if (invoiceId == null) {
      _snack('لا توجد فاتورة مرتبطة بهذا الطلب', true);
      return;
    }

    final idempotencyKey = 'promo-$invoiceId';
    final initRes = await BillingService.initPayment(
      invoiceId: invoiceId,
      idempotencyKey: idempotencyKey,
    );
    if (!mounted) return;
    if (!initRes.isSuccess) {
      _snack(initRes.error ?? 'تعذر فتح صفحة الدفع', true);
      return;
    }

    final attempt = Map<String, dynamic>.from(initRes.dataAsMap ?? const {});
    bool isPaying = false;
    final completed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => StatefulBuilder(
            builder: (dialogContext, setDialogState) => AlertDialog(
              title: const Text(
                'صفحة دفع الترويج',
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _line('رقم الطلب', (request['code'] as String? ?? '').trim()),
                    if ((request['invoice_code'] as String? ?? '').trim().isNotEmpty)
                      _line('رقم الفاتورة', (request['invoice_code'] as String).trim()),
                    _line('الإجمالي', '${_money(request['invoice_total'])} ريال'),
                    if (request['invoice_vat'] != null)
                      _line('VAT', '${_money(request['invoice_vat'])} ريال'),
                    if ((attempt['provider_reference'] as String? ?? '').trim().isNotEmpty)
                      _line('مرجع الدفع', (attempt['provider_reference'] as String).trim()),
                    const SizedBox(height: 10),
                    const Text(
                      'سيتم تنفيذ الدفع التجريبي ثم تفعيل الحملة مباشرة بعد تأكيد السداد.',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        color: Colors.black54,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isPaying ? null : () => Navigator.pop(dialogContext, false),
                  child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
                ),
                FilledButton(
                  onPressed: isPaying
                      ? null
                      : () async {
                          setDialogState(() => isPaying = true);
                          final payRes = await BillingService.completeMockPayment(
                            invoiceId: invoiceId,
                            idempotencyKey: idempotencyKey,
                          );
                          if (!mounted) return;
                          if (!payRes.isSuccess) {
                            if (!dialogContext.mounted) return;
                            setDialogState(() => isPaying = false);
                            _snack(payRes.error ?? 'تعذر إتمام الدفع', true);
                            return;
                          }
                          if (!dialogContext.mounted) return;
                          Navigator.pop(dialogContext, true);
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: _brandColor,
                    foregroundColor: Colors.white,
                  ),
                  child: isPaying
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text(
                          'تأكيد الدفع',
                          style: TextStyle(fontFamily: 'Cairo'),
                        ),
                ),
              ],
            ),
          ),
        ) ??
        false;

    if (!completed) return;
    await _loadRequests(silent: true);
    if (!mounted) return;
    _snack('تم سداد الفاتورة وتفعيل العرض الترويجي', false);
  }
}

class _PromoComposer extends StatefulWidget {
  final VoidCallback onCreated;

  const _PromoComposer({required this.onCreated});

  @override
  State<_PromoComposer> createState() => _PromoComposerState();
}

class _PromoComposerState extends State<_PromoComposer> {
  final _title = TextEditingController();
  bool _showPricing = false;
  late final Map<String, _PromoDraft> _drafts;
  final List<String> _selected = [];
  bool _sending = false;
  Timer? _quoteDebounce;
  bool _quoteLoading = false;
  String _liveSubtotal = '0.00';
  String _liveVat = '0.00';
  String _liveTotal = '0.00';

  _PromoDraft? get _homeBannerDraft {
    if (_selected.contains('home_banner')) {
      return _drafts['home_banner'];
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _drafts = {
      for (final service in _promoServices) service.type: _PromoDraft.withDefaults(service),
    };
  }

  @override
  void dispose() {
    _quoteDebounce?.cancel();
    _title.dispose();
    for (final draft in _drafts.values) {
      draft.dispose();
    }
    super.dispose();
  }

  void _scheduleLiveQuote() {
    _quoteDebounce?.cancel();
    _quoteDebounce = Timer(const Duration(milliseconds: 550), _calculateLiveQuote);
  }

  Future<void> _calculateLiveQuote() async {
    if (!mounted || _showPricing) return;
    if (_title.text.trim().isEmpty || _selected.isEmpty) {
      if (!mounted) return;
      setState(() {
        _quoteLoading = false;
        _liveSubtotal = '0.00';
        _liveVat = '0.00';
        _liveTotal = '0.00';
      });
      return;
    }

    final items = <Map<String, dynamic>>[];
    for (int i = 0; i < _selected.length; i++) {
      final draft = _drafts[_selected[i]]!;
      if (draft.validate() != null) {
        if (!mounted) return;
        setState(() {
          _quoteLoading = false;
          _liveSubtotal = '0.00';
          _liveVat = '0.00';
          _liveTotal = '0.00';
        });
        return;
      }
      items.add(draft.toPayload(i));
    }

    setState(() => _quoteLoading = true);
    final previewRes = await PromoService.previewBundleRequest(
      title: _title.text.trim(),
      items: items,
      mobileScale: _homeBannerDraft?.mobileScale,
      tabletScale: _homeBannerDraft?.tabletScale,
      desktopScale: _homeBannerDraft?.desktopScale,
    );
    if (!mounted) return;
    if (!previewRes.isSuccess) {
      setState(() {
        _quoteLoading = false;
        _liveSubtotal = '0.00';
        _liveVat = '0.00';
        _liveTotal = '0.00';
      });
      return;
    }

    final data = Map<String, dynamic>.from(previewRes.dataAsMap ?? const {});
    setState(() {
      _quoteLoading = false;
      _liveSubtotal = _money(data['subtotal']);
      _liveVat = _money(data['vat_amount']);
      _liveTotal = _money(data['total']);
    });
  }

  Widget _buildLiveTotalCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _brandColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'مجمل التكلفة',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              color: _brandColor,
            ),
          ),
          const SizedBox(height: 6),
          if (_quoteLoading)
            const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: _brandColor),
            )
          else
            Text(
              '$_liveTotal ريال',
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            'قبل الضريبة: $_liveSubtotal ريال • VAT: $_liveVat ريال',
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              color: Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final providerLabel = _title.text.trim().isEmpty ? 'مزود الخدمة' : _title.text.trim();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text(
                    'مزود الخدمة: $providerLabel',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _topNavPill(
                label: 'ترويج',
                active: !_showPricing,
                onTap: () => setState(() => _showPricing = false),
              ),
              const SizedBox(width: 8),
              _topNavPill(
                label: 'الأسعار',
                active: _showPricing,
                onTap: () => setState(() => _showPricing = true),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_showPricing) ...[
            _buildPricingGuide(),
            const SizedBox(height: 24),
          ] else ...[
            const Text(
              'طلب ترويج متعدد الخدمات',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
          TextField(
            controller: _title,
            onChanged: (_) {
              setState(() {});
              _scheduleLiveQuote();
            },
            decoration: _decoration('عنوان الطلب', Icons.title_rounded),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final service in _promoServices)
                FilterChip(
                  selected: _selected.contains(service.type),
                  selectedColor: const Color(0xFFE9E0FA),
                  label: Text(
                    service.label,
                    style: const TextStyle(fontFamily: 'Cairo'),
                  ),
                  onSelected: (_) {
                    setState(() {
                      if (_selected.contains(service.type)) {
                        _selected.remove(service.type);
                      } else {
                        _selected.add(service.type);
                      }
                    });
                    _scheduleLiveQuote();
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          for (int i = 0; i < _selected.length; i++) ...[
            _buildDraftCard(i, _drafts[_selected[i]]!),
            const SizedBox(height: 12),
          ],
          _buildLiveTotalCard(),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _sending ? null : _submit,
              style: ElevatedButton.styleFrom(backgroundColor: _brandColor),
              child: _sending
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text(
                      'معاينة التسعير ثم الإرسال',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }

  Widget _topNavPill({required String label, required bool active, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: active ? _brandColor : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? _brandColor : Colors.grey.shade300),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
            color: active ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _buildPricingGuide() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 920;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _pricingCard(
                  title: 'بنر الصفحة الرئيسية',
                  lines: const [
                    'اقل مدة للحملة 24 ساعة',
                    '1000 ريال سعودي لكل (24) ساعة',
                  ],
                  width: isNarrow ? constraints.maxWidth : constraints.maxWidth * .48,
                ),
                _pricingCard(
                  title: 'شريط أبرز المختصين',
                  lines: const [
                    'اقل مدة للحملة 24 ساعة',
                    'التكلفة لكل (24) ساعة',
                  ],
                  width: isNarrow ? constraints.maxWidth : constraints.maxWidth * .48,
                ),
                _pricingTableCard(
                  title: 'شريط البنرات والمشاريع / شريط اللمحات',
                  headers: const ['معدل الظهور', 'التكلفة (ريال سعودي)'],
                  rows: const [
                    ['مرة كل 10 ثواني', '2000'],
                    ['مرة كل 30 ثانية', '1500'],
                    ['مرة كل دقيقة', '1000'],
                    ['مرة كل خمس دقائق', '500'],
                    ['مرة كل ربع ساعة', '250'],
                    ['مرة كل نصف ساعة', '200'],
                    ['مرة كل ساعة', '100'],
                  ],
                  width: isNarrow ? constraints.maxWidth : constraints.maxWidth * .48,
                ),
                _pricingCard(
                  title: 'الظهور في قوائم البحث',
                  lines: const [
                    'اقل مدة للحملة 24 ساعة',
                    'التكلفة لكل (24) ساعة',
                  ],
                  width: isNarrow ? constraints.maxWidth : constraints.maxWidth * .48,
                  footerTable: const [
                    ['الأول في القائمة', '10,000'],
                    ['الثاني في القائمة', '5,000'],
                    ['من أول خمسة أسماء في القائمة', '2500'],
                    ['من أول عشرة أسماء في القائمة', '1200'],
                  ],
                ),
                _pricingCard(
                  title: 'الرسائل الدعائية',
                  lines: const [
                    'سيتم التواصل معكم من قبلنا للاتفاق على:',
                    'عدد الرسائل',
                    'جدولة الإرسال',
                    'التكلفة',
                    'آلية السداد',
                  ],
                  width: isNarrow ? constraints.maxWidth : constraints.maxWidth * .48,
                ),
                _pricingCard(
                  title: 'الرعاية',
                  lines: const [
                    'سيتم التواصل معكم من قبلنا للاتفاق على:',
                    'مدة الرعاية',
                    'مساحات ظهور الرعاية',
                    'التكلفة',
                    'آلية السداد',
                  ],
                  width: isNarrow ? constraints.maxWidth : constraints.maxWidth * .48,
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _pricingCard({
    required String title,
    required List<String> lines,
    required double width,
    List<List<String>>? footerTable,
  }) {
    return SizedBox(
      width: width,
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  color: _brandColor,
                ),
              ),
              const SizedBox(height: 8),
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    line,
                    style: const TextStyle(fontFamily: 'Cairo', height: 1.5),
                  ),
                ),
              if (footerTable != null) ...[
                const SizedBox(height: 8),
                Table(
                  border: TableBorder.all(color: Colors.grey.shade300),
                  children: [
                    const TableRow(
                      children: [
                        Padding(
                          padding: EdgeInsets.all(8),
                          child: Text('ترتيب الظهور', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                        ),
                        Padding(
                          padding: EdgeInsets.all(8),
                          child: Text('التكلفة (ريال سعودي)', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    for (final row in footerTable)
                      TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(row[0], style: const TextStyle(fontFamily: 'Cairo')),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(row[1], style: const TextStyle(fontFamily: 'Cairo')),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _pricingTableCard({
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
    required double width,
  }) {
    return SizedBox(
      width: width,
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  color: _brandColor,
                ),
              ),
              const SizedBox(height: 8),
              Table(
                border: TableBorder.all(color: Colors.grey.shade300),
                children: [
                  TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(headers[0], style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(headers[1], style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  for (final row in rows)
                    TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(row[0], style: const TextStyle(fontFamily: 'Cairo')),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(row[1], style: const TextStyle(fontFamily: 'Cairo')),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDraftCard(int index, _PromoDraft draft) {
    final service = draft.service;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(service.icon, color: _brandColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${index + 1}. ${service.label}',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _sending ? null : () => _previewServiceQuote(draft, index),
                  icon: const Icon(Icons.visibility_rounded, size: 18),
                  label: const Text(
                    'معاينة',
                    style: TextStyle(fontFamily: 'Cairo'),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  onPressed: () {
                    setState(() => _selected.remove(service.type));
                    _scheduleLiveQuote();
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            if (service.needsRange) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _dateTile(
                      'البداية',
                      _fmtDate(draft.startAt),
                      () => _pickDateTime((value) {
                        setState(() {
                          draft.startAt = value;
                          draft.syncSponsorship();
                        });
                      }, draft.startAt),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _dateTile(
                      'النهاية',
                      _fmtDate(draft.endAt),
                      service.needsSponsor
                          ? null
                          : () => _pickDateTime(
                                (value) => setState(() => draft.endAt = value),
                                draft.endAt,
                              ),
                    ),
                  ),
                ],
              ),
            ],
            if (service.needsFrequency) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: draft.frequency,
                decoration: _decoration('معدل الظهور', Icons.repeat_rounded),
                items: _frequencyLabels.entries
                    .map((e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(
                            e.value,
                            style: const TextStyle(fontFamily: 'Cairo'),
                          ),
                        ))
                    .toList(),
                onChanged: (value) {
                  setState(() => draft.frequency = value ?? '60s');
                  _scheduleLiveQuote();
                },
                onSaved: (_) {},
              ),
            ],
            if (service.needsSearch) ...[
              const SizedBox(height: 8),
              const Text(
                'قوائم الظهور',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final scope in _searchScopeOrder)
                    FilterChip(
                      selected: draft.searchScopes.contains(scope),
                      selectedColor: const Color(0xFFE9E0FA),
                      label: Text(
                        _searchScopeLabels[scope] ?? scope,
                        style: const TextStyle(fontFamily: 'Cairo'),
                      ),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            draft.searchScopes.add(scope);
                          } else {
                            draft.searchScopes.remove(scope);
                          }
                        });
                        _scheduleLiveQuote();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: draft.searchPosition,
                decoration: _decoration(
                  'ترتيب الظهور',
                  Icons.format_list_numbered_rounded,
                ),
                items: _searchPositionLabels.entries
                    .map((e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(
                            e.value,
                            style: const TextStyle(fontFamily: 'Cairo'),
                          ),
                        ))
                    .toList(),
                onChanged: (value) {
                  setState(() => draft.searchPosition = value ?? 'first');
                  _scheduleLiveQuote();
                },
                onSaved: (_) {},
              ),
            ],
            if (service.needsCategory) ...[
              const SizedBox(height: 8),
              TextField(
                controller: draft.category,
                onChanged: (_) => _scheduleLiveQuote(),
                decoration: _decoration(
                  'تصنيف المختص',
                  Icons.category_rounded,
                ),
              ),
            ],
            if (service.needsSendAt) ...[
              const SizedBox(height: 8),
              _dateTile(
                'وقت الإرسال',
                _fmtDate(draft.sendAt),
                () => _pickDateTime(
                  (value) => setState(() => draft.sendAt = value),
                  draft.sendAt,
                ),
              ),
            ],
            if (service.needsChannels) ...[
              CheckboxListTile(
                value: draft.notify,
                title: const Text(
                  'رسائل التنبيه',
                  style: TextStyle(fontFamily: 'Cairo'),
                ),
                onChanged: (value) {
                    setState(() => draft.notify = value ?? false);
                    _scheduleLiveQuote();
                },
              ),
              CheckboxListTile(
                value: draft.chat,
                title: const Text(
                  'رسائل المحادثات',
                  style: TextStyle(fontFamily: 'Cairo'),
                ),
                onChanged: (value) {
                    setState(() => draft.chat = value ?? false);
                    _scheduleLiveQuote();
                },
              ),
            ],
            if (service.needsMessage) ...[
              const SizedBox(height: 8),
              TextField(
                controller: draft.message,
                maxLines: 3,
                onChanged: (_) => _scheduleLiveQuote(),
                decoration: _decoration(
                  service.needsSponsor
                      ? 'نص رسالة الرعاية'
                      : 'نص الرسالة الترويجية',
                  Icons.notes_rounded,
                ),
              ),
            ],
            if (service.needsRedirect) ...[
              const SizedBox(height: 8),
              TextField(
                controller: draft.redirect,
                onChanged: (_) => _scheduleLiveQuote(),
                decoration: _decoration('رابط التوجيه', Icons.link_rounded),
              ),
            ],
            if (service.needsSponsor) ...[
              const SizedBox(height: 8),
              TextField(
                controller: draft.sponsorName,
                onChanged: (_) => _scheduleLiveQuote(),
                decoration: _decoration('اسم الراعي', Icons.badge_rounded),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: draft.months,
                keyboardType: TextInputType.number,
                decoration: _decoration(
                  'مدة الرعاية بالأشهر',
                  Icons.calendar_month_rounded,
                ),
                onChanged: (_) {
                  setState(draft.syncSponsorship);
                  _scheduleLiveQuote();
                },
              ),
            ],
            if (service.needsSpecs) ...[
              const SizedBox(height: 8),
              TextField(
                controller: draft.specs,
                onChanged: (_) => _scheduleLiveQuote(),
                decoration: _decoration(
                  'مواصفات الملف المرفوع',
                  Icons.info_outline_rounded,
                ),
              ),
            ],
            if (service.needsAssets) ...[
              if (service.type == 'home_banner')
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        'المقاس المعتمد: 1920x840 (نسبة 16:7) للصور والفيديو MP4.',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                    _buildScaleSlider(
                      label: 'تحجيم الجوال',
                      value: draft.mobileScale,
                      min: 40,
                      max: 140,
                      onChanged: (value) =>
                          setState(() => draft.mobileScale = value.round()),
                    ),
                    _buildScaleSlider(
                      label: 'تحجيم التابلت',
                      value: draft.tabletScale,
                      min: 40,
                      max: 150,
                      onChanged: (value) =>
                          setState(() => draft.tabletScale = value.round()),
                    ),
                    _buildScaleSlider(
                      label: 'تحجيم الديسكتوب',
                      value: draft.desktopScale,
                      min: 40,
                      max: 160,
                      onChanged: (value) =>
                          setState(() => draft.desktopScale = value.round()),
                    ),
                  ],
                ),
              if ((_serviceAttachmentHints[service.type] ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _serviceAttachmentHints[service.type]!,
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      color: Colors.black54,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _pickAttachment(draft),
                icon: const Icon(Icons.attach_file_rounded),
                label: const Text(
                  'إضافة مرفقات',
                  style: TextStyle(fontFamily: 'Cairo'),
                ),
              ),
              if (draft.files.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (int i = 0; i < draft.files.length; i++)
                      InputChip(
                        label: Text(
                          _name(draft.files[i]),
                          style: const TextStyle(fontFamily: 'Cairo'),
                        ),
                        avatar: Icon(
                          _assetType(draft.files[i]) == 'video'
                              ? Icons.play_circle_fill_rounded
                              : Icons.image_rounded,
                          color: _brandColor,
                        ),
                        onPressed: () => _previewAttachment(draft.files[i]),
                        onDeleted: () {
                          setState(() => draft.files.removeAt(i));
                          _scheduleLiveQuote();
                        },
                      ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }

  InputDecoration _decoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontFamily: 'Cairo'),
      prefixIcon: Icon(icon, color: _brandColor),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    );
  }

  Widget _buildScaleSlider({
    required String label,
    required int value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  color: Colors.black87,
                ),
              ),
            ),
            Text(
              '$value%',
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        Slider(
          value: value.toDouble().clamp(min, max),
          min: min,
          max: max,
          divisions: (max - min).round(),
          label: '$value%',
          activeColor: _brandColor,
          onChanged: (newValue) {
            onChanged(newValue);
            _scheduleLiveQuote();
          },
        ),
      ],
    );
  }

  Widget _dateTile(String label, String value, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: onTap == null ? Colors.grey.shade100 : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontFamily: 'Cairo', fontSize: 12)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontFamily: 'Cairo')),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDateTime(
    ValueChanged<DateTime> onPick,
    DateTime? initial,
  ) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: DateTime(now.year + 2),
      builder: (ctx, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child!,
      ),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial ?? now),
      builder: (ctx, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child!,
      ),
    );
    if (time == null) return;
    onPick(DateTime(date.year, date.month, date.day, time.hour, time.minute));
    _scheduleLiveQuote();
  }

  Future<void> _pickAttachment(_PromoDraft draft) async {
    final allowed = _allowedExtensionsForService(draft.service.type);
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: allowed == null ? FileType.any : FileType.custom,
      allowedExtensions: allowed?.toList(),
    );
    if (result == null) return;
    final selected = result.files
        .where((f) => f.path != null && f.path!.isNotEmpty)
        .map((f) => File(f.path!))
        .toList();

    final supported = <File>[];
    final unsupported = <String>[];
    for (final file in selected) {
      if (_isAllowedForService(file, draft.service.type)) {
        supported.add(file);
      } else {
        unsupported.add(_name(file));
      }
    }

    if (unsupported.isNotEmpty) {
      final allowedText = (allowed ?? <String>{}).map((e) => e.toUpperCase()).join(', ');
      _snack(
        'ملف غير مدعوم: ${unsupported.first}. الأنواع المسموحة: $allowedText',
        true,
      );
    }

    if (supported.isEmpty) return;

    if (draft.service.type == 'home_banner') {
      final validFiles = <File>[];
      final errors = <String>[];
      final warnings = <String>[];

      for (final file in supported) {
        final validationError = await _validateHomeBannerFile(file);
        if (validationError == null) {
          validFiles.add(file);
        } else if (validationError.startsWith('WARN:')) {
          validFiles.add(file);
          warnings.add('${_name(file)}: ${validationError.replaceFirst('WARN:', '').trim()}');
        } else {
          errors.add('${_name(file)}: $validationError');
        }
      }

      if (!mounted) return;
      setState(() {
        draft.files.addAll(validFiles);
      });
      _scheduleLiveQuote();
      if (errors.isNotEmpty) {
        _snack(errors.first, true);
      } else if (warnings.isNotEmpty) {
        _snack(warnings.first, false);
      }
      return;
    }

    setState(() {
      draft.files.addAll(supported);
    });
    _scheduleLiveQuote();
  }

  Future<void> _previewAttachment(File file) async {
    final kind = _assetType(file);
    if (kind != 'image' && kind != 'video') {
      _snack('المعاينة تدعم الصور والفيديو فقط.', true);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => _AttachmentPreviewDialog(file: file, kind: kind),
    );
  }

  Future<void> _previewServiceQuote(_PromoDraft draft, int sortOrder) async {
    final error = draft.validate();
    if (error != null) {
      _snack('${draft.service.label}: $error', true);
      return;
    }

    final title = _title.text.trim().isEmpty ? 'معاينة ${draft.service.label}' : _title.text.trim();
    final previewRes = await PromoService.previewBundleRequest(
      title: title,
      items: [draft.toPayload(sortOrder)],
      mobileScale: draft.service.type == 'home_banner' ? draft.mobileScale : null,
      tabletScale: draft.service.type == 'home_banner' ? draft.tabletScale : null,
      desktopScale: draft.service.type == 'home_banner' ? draft.desktopScale : null,
    );
    if (!mounted) return;
    if (!previewRes.isSuccess) {
      _snack(previewRes.error ?? 'تعذر معاينة تسعير البند', true);
      return;
    }

    final data = Map<String, dynamic>.from(previewRes.dataAsMap ?? const {});
    final items = _asMapList(data['items']);
    final item = items.isNotEmpty ? items.first : const <String, dynamic>{};

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          'معاينة ${draft.service.label}',
          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _line('البند', draft.service.label),
                if (draft.service.needsRange && draft.startAt != null && draft.endAt != null) ...[
                  _line('من', _fmtDate(draft.startAt)),
                  _line('إلى', _fmtDate(draft.endAt)),
                  _line(
                    'مدة الحملة',
                    item['duration_days'] != null ? '${item['duration_days']} يوم' : '-',
                  ),
                ],
                _line('سعر البند', '${_money(item['subtotal'])} ريال'),
                _line('الإجمالي قبل الضريبة', '${_money(data['subtotal'])} ريال'),
                _line('VAT', '${_money(data['vat_amount'])} ريال'),
                _line('الإجمالي النهائي', '${_money(data['total'])} ريال'),
                const SizedBox(height: 8),
                const Text(
                  'تم احتساب السعر حسب قواعد صفحة الأسعار الحالية لكل بند.',
                  style: TextStyle(fontFamily: 'Cairo', color: Colors.black54, height: 1.6),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق', style: TextStyle(fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
  }

  Future<String?> _validateHomeBannerFile(File file) async {
    final type = _assetType(file);
    if (type != 'image' && type != 'video') {
      return 'بنر الصفحة الرئيسية يقبل الصور أو الفيديو فقط.';
    }

    if (type == 'video' && _ext(file) != 'mp4') {
      return 'بنر الصفحة الرئيسية للفيديو يدعم MP4 فقط.';
    }

    if (type == 'image') {
      try {
        final bytes = await file.readAsBytes();
        final image = await _decodeImage(bytes);
        final width = image.width;
        final height = image.height;
        if (width != _homeBannerRequiredWidth || height != _homeBannerRequiredHeight) {
          return 'الأبعاد المطلوبة ${_homeBannerRequiredWidth}x$_homeBannerRequiredHeight. '
              'الأبعاد الحالية ${width}x$height.';
        }
      } catch (_) {
        return 'تعذر قراءة أبعاد الصورة.';
      }
      return null;
    }

    VideoPlayerController? controller;
    try {
      controller = VideoPlayerController.file(file);
      await controller.initialize();
      final size = controller.value.size;
      final width = size.width.round();
      final height = size.height.round();
      if (width != _homeBannerRequiredWidth || height != _homeBannerRequiredHeight) {
        return buildHomeBannerVideoAutofitWarning(
          requiredWidth: _homeBannerRequiredWidth,
          requiredHeight: _homeBannerRequiredHeight,
          currentWidth: width,
          currentHeight: height,
        );
      }
      return null;
    } catch (_) {
      return 'تعذر قراءة أبعاد الفيديو.';
    } finally {
      await controller?.dispose();
    }
  }

  Future<ui.Image> _decodeImage(Uint8List bytes) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, (image) {
      if (!completer.isCompleted) {
        completer.complete(image);
      }
    });
    return completer.future;
  }

  Future<_PaymentSelectionResult?> _openSummaryAndPayment(Map<String, dynamic> preview) async {
    if (!mounted) return null;
    return Navigator.of(context).push<_PaymentSelectionResult>(
      MaterialPageRoute(
        builder: (_) => _PromoSummaryScreen(
          preview: preview,
          providerName: (_title.text.trim().isEmpty ? 'مزود الخدمة' : _title.text.trim()),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty) {
      _snack('أدخل عنوان الطلب', true);
      return;
    }
    if (_selected.isEmpty) {
      _snack('اختر خدمة واحدة على الأقل', true);
      return;
    }

    final items = <Map<String, dynamic>>[];
    for (int i = 0; i < _selected.length; i++) {
      final draft = _drafts[_selected[i]]!;
      final error = draft.validate();
      if (error != null) {
        _snack('${draft.service.label}: $error', true);
        return;
      }
      items.add(draft.toPayload(i));
    }

    setState(() => _sending = true);
    final previewRes = await PromoService.previewBundleRequest(
      title: _title.text.trim(),
      items: items,
      mobileScale: _homeBannerDraft?.mobileScale,
      tabletScale: _homeBannerDraft?.tabletScale,
      desktopScale: _homeBannerDraft?.desktopScale,
    );
    if (!mounted) return;
    if (!previewRes.isSuccess) {
      setState(() => _sending = false);
      _snack(previewRes.error ?? 'تعذر معاينة التسعير', true);
      return;
    }

    final previewPayload = Map<String, dynamic>.from(previewRes.dataAsMap ?? const {});
    final paymentSelection = await _openSummaryAndPayment(previewPayload);
    if (!mounted) return;
    if (paymentSelection == null) {
      setState(() => _sending = false);
      return;
    }

    final createRes = await PromoService.createBundleRequest(
      title: _title.text.trim(),
      items: items,
      mobileScale: _homeBannerDraft?.mobileScale,
      tabletScale: _homeBannerDraft?.tabletScale,
      desktopScale: _homeBannerDraft?.desktopScale,
    );
    if (!mounted) return;
    if (!createRes.isSuccess) {
      setState(() => _sending = false);
      _snack(createRes.error ?? 'فشل إنشاء الطلب', true);
      return;
    }

    final requestId = createRes.dataAsMap?['id'] as int?;
    final detailRes = requestId == null
        ? null
        : await PromoService.fetchRequestDetail(requestId);
    final createdItems =
        _asMapList(detailRes?.dataAsMap?['items'] ?? createRes.dataAsMap?['items']);
    final ids = <String, int>{};
    for (final item in createdItems) {
      final id = item['id'] as int?;
      if (id != null) {
        ids['${item['service_type']}:${item['sort_order'] ?? 0}'] = id;
      }
    }

    final uploadFailures = <String>[];
    if (requestId != null) {
      for (int i = 0; i < _selected.length; i++) {
        final draft = _drafts[_selected[i]]!;
        for (final file in draft.files) {
          final uploadRes = await PromoService.uploadAsset(
            requestId: requestId,
            itemId: ids['${draft.service.type}:$i'],
            file: file,
            assetType: _assetType(file),
            title: draft.service.label,
          );
          if (!mounted) return;
          if (!uploadRes.isSuccess) {
            final reason = uploadRes.error ?? 'تعذر رفع الملف.';
            uploadFailures.add('${_name(file)}: $reason');
          }
        }
      }
    }

    final requestCode = (detailRes?.dataAsMap?['code'] ?? createRes.dataAsMap?['code'] ?? '') as String;

    if (uploadFailures.isNotEmpty) {
      final sample = uploadFailures.first;
      setState(() => _sending = false);
      widget.onCreated();
      _snack(
        'تم إنشاء الطلب ولكن فشل رفع ${uploadFailures.length} ملف. $sample',
        true,
      );
      return;
    }

    final invoiceId = int.tryParse('${detailRes?.dataAsMap?['invoice'] ?? createRes.dataAsMap?['invoice'] ?? ''}');
    if (paymentSelection.confirmed && invoiceId != null) {
      final idempotencyKey = 'promo-$invoiceId-${DateTime.now().millisecondsSinceEpoch}';
      final initRes = await BillingService.initPayment(
        invoiceId: invoiceId,
        provider: 'mock',
        idempotencyKey: idempotencyKey,
      );
      if (initRes.isSuccess) {
        final payRes = await BillingService.completeMockPayment(
          invoiceId: invoiceId,
          idempotencyKey: idempotencyKey,
        );
        if (!payRes.isSuccess) {
          _snack(payRes.error ?? 'تم إنشاء الطلب وتعذر إكمال الدفع الآن.', true);
        }
      } else {
        _snack(initRes.error ?? 'تم إنشاء الطلب وتعذر تهيئة الدفع الآن.', true);
      }
    }

    _title.clear();
    for (final draft in _drafts.values) {
      draft.reset();
    }
    setState(() {
      _selected.clear();
      _sending = false;
    });
    widget.onCreated();

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF2F7D1E)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'رقم الطلب: ${requestCode.isNotEmpty ? requestCode : "—"}',
                  style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700, color: Color(0xFF2F7D1E)),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF2F7D1E)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Column(
                  children: [
                    Text('تمت عملية الدفع بنجاح', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700, fontSize: 16)),
                    SizedBox(height: 4),
                    Text('سيتم التواصل معكم لتنفيذ طلبكم', style: TextStyle(fontFamily: 'Cairo', color: Colors.black54)),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2F7D1E)),
                child: const Text('إغلاق', style: TextStyle(fontFamily: 'Cairo')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _snack(String message, bool error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: error ? Colors.red : Colors.green,
        content: Text(message, style: const TextStyle(fontFamily: 'Cairo')),
      ),
    );
  }
}

class _PromoServiceDef {
  final String type;
  final String label;
  final IconData icon;
  final bool needsRange;
  final bool needsSendAt;
  final bool needsFrequency;
  final bool needsSearch;
  final bool needsCategory;
  final bool needsMessage;
  final bool needsRedirect;
  final bool needsSponsor;
  final bool needsChannels;
  final bool needsAssets;
  final bool needsSpecs;
  final bool attachmentsRequired;

  const _PromoServiceDef({
    required this.type,
    required this.label,
    required this.icon,
    this.needsRange = false,
    this.needsSendAt = false,
    this.needsFrequency = false,
    this.needsSearch = false,
    this.needsCategory = false,
    this.needsMessage = false,
    this.needsRedirect = false,
    this.needsSponsor = false,
    this.needsChannels = false,
    this.needsAssets = false,
    this.needsSpecs = false,
    this.attachmentsRequired = false,
  });
}

class _PromoDraft {
  final _PromoServiceDef service;
  final category = TextEditingController();
  final message = TextEditingController();
  final redirect = TextEditingController();
  final sponsorName = TextEditingController();
  final months = TextEditingController(text: '1');
  final specs = TextEditingController();
  final files = <File>[];
  DateTime? startAt;
  DateTime? endAt;
  DateTime? sendAt;
  String frequency = '60s';
  final Set<String> searchScopes = {'default'};
  String searchPosition = 'first';
  int mobileScale = 100;
  int tabletScale = 100;
  int desktopScale = 100;
  bool notify = true;
  bool chat = false;

  _PromoDraft(this.service);

  _PromoDraft.withDefaults(this.service) {
    if (service.type == 'home_banner') {
      specs.text = 'PNG/MP4 - 1920x840 (16:7)';
    }
  }

  int get monthCount => int.tryParse(months.text.trim()) ?? 0;

  void syncSponsorship() {
    if (!service.needsSponsor || startAt == null || monthCount <= 0) return;
    endAt = DateTime(
      startAt!.year,
      startAt!.month + monthCount,
      startAt!.day,
      startAt!.hour,
      startAt!.minute,
    );
  }

  String? validate() {
    if (service.needsRange) {
      if (startAt == null || endAt == null) return 'حدد تاريخ البداية والنهاية';
      if (!endAt!.isAfter(startAt!)) return 'النهاية يجب أن تكون بعد البداية';
      if (!service.needsSponsor && endAt!.difference(startAt!).inHours < 24) {
        return 'الحد الأدنى لمدة الحملة 24 ساعة';
      }
    }
    if (service.needsSendAt && sendAt == null) return 'حدد وقت الإرسال';
    if (service.needsChannels && !notify && !chat) return 'اختر قناة إرسال';
    final msgValidation = validatePromoMessageOrAssetRequirement(
      requiresMessage: service.needsMessage,
      messageText: message.text,
      assetCount: files.length,
    );
    if (msgValidation != null) return msgValidation;
    if (service.needsSearch && searchScopes.isEmpty) return 'اختر قائمة ظهور واحدة على الأقل';
    if (service.needsSponsor && sponsorName.text.trim().isEmpty) return 'أدخل اسم الراعي';
    if (service.needsSponsor && monthCount <= 0) return 'أدخل مدة الرعاية';
    if (service.attachmentsRequired && files.isEmpty) return 'أضف المرفقات المطلوبة';
    return null;
  }

  Map<String, dynamic> toPayload(int sortOrder) {
    final body = <String, dynamic>{
      'service_type': service.type,
      'title': service.label,
      'sort_order': sortOrder,
      'asset_count': files.length,
    };
    if (service.needsRange) {
      body['start_at'] = startAt!.toUtc().toIso8601String();
      body['end_at'] = endAt!.toUtc().toIso8601String();
    }
    if (service.needsSendAt) body['send_at'] = sendAt!.toUtc().toIso8601String();
    if (service.needsFrequency) body['frequency'] = frequency;
    if (service.needsSearch) {
      final orderedScopes = orderedSearchScopes(searchScopes);
      body['search_scopes'] = orderedScopes;
      body['search_scope'] = orderedScopes.isNotEmpty ? orderedScopes.first : 'default';
      body['search_position'] = searchPosition;
    }
    if (category.text.trim().isNotEmpty) body['target_category'] = category.text.trim();
    if (message.text.trim().isNotEmpty) body['message_body'] = message.text.trim();
    if (redirect.text.trim().isNotEmpty) body['redirect_url'] = redirect.text.trim();
    if (service.needsChannels) {
      body['use_notification_channel'] = notify;
      body['use_chat_channel'] = chat;
    }
    if (service.needsSponsor) {
      body['sponsor_name'] = sponsorName.text.trim();
      body['sponsorship_months'] = monthCount;
    }
    if (service.type == 'home_banner') {
      body['mobile_scale'] = mobileScale;
      body['tablet_scale'] = tabletScale;
      body['desktop_scale'] = desktopScale;
    }
    if (specs.text.trim().isNotEmpty) body['attachment_specs'] = specs.text.trim();
    return body;
  }

  void reset() {
    category.clear();
    message.clear();
    redirect.clear();
    sponsorName.clear();
    months.text = '1';
    specs.clear();
    if (service.type == 'home_banner') {
      specs.text = 'PNG/MP4 - 1920x840 (16:7)';
    }
    files.clear();
    startAt = null;
    endAt = null;
    sendAt = null;
    frequency = '60s';
    searchScopes
      ..clear()
      ..add('default');
    searchPosition = 'first';
    mobileScale = 100;
    tabletScale = 100;
    desktopScale = 100;
    notify = true;
    chat = false;
  }

  void dispose() {
    category.dispose();
    message.dispose();
    redirect.dispose();
    sponsorName.dispose();
    months.dispose();
    specs.dispose();
  }
}

Widget _line(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'Cairo',
                color: Colors.black54,
              ),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontFamily: 'Cairo'))),
        ],
      ),
    );

List<Map<String, dynamic>> _asMapList(dynamic value) {
  if (value is List) {
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }
  return const [];
}

String _serviceLabel(String? type) {
  for (final service in _promoServices) {
    if (service.type == type) return service.label;
  }
  return type ?? '';
}

String _fmtDate(DateTime? value) {
  if (value == null) return 'اختر التاريخ والوقت';
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$day/$month/${value.year} - $hour:$minute';
}

String _money(dynamic value) {
  final parsed = num.tryParse('${value ?? ''}');
  return parsed == null ? '0.00' : parsed.toStringAsFixed(2);
}

String _name(File file) => file.path.split(RegExp(r'[\\/]')).last;

String _ext(File file) {
  final name = _name(file);
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return '';
  return name.substring(dot + 1).toLowerCase();
}

Set<String>? _allowedExtensionsForService(String serviceType) {
  final list = _serviceAllowedExtensions[serviceType];
  if (list == null || list.isEmpty) return null;
  return list.map((e) => e.toLowerCase()).toSet();
}

bool _isAllowedForService(File file, String serviceType) {
  final allowed = _allowedExtensionsForService(serviceType);
  if (allowed == null) return true;
  return allowed.contains(_ext(file));
}

String _assetType(File file) {
  final ext = _ext(file);
  if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) return 'image';
  if (['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(ext)) return 'video';
  return 'other';
}

class _AttachmentPreviewDialog extends StatefulWidget {
  final File file;
  final String kind;

  const _AttachmentPreviewDialog({required this.file, required this.kind});

  @override
  State<_AttachmentPreviewDialog> createState() => _AttachmentPreviewDialogState();
}

class _AttachmentPreviewDialogState extends State<_AttachmentPreviewDialog> {
  VideoPlayerController? _controller;
  Future<void>? _initializeFuture;

  @override
  void initState() {
    super.initState();
    if (widget.kind == 'video') {
      _controller = VideoPlayerController.file(widget.file);
      _initializeFuture = _controller!.initialize();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _name(widget.file),
              style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            if (widget.kind == 'image')
              SizedBox(
                height: 320,
                width: double.maxFinite,
                child: InteractiveViewer(
                  child: Image.file(widget.file, fit: BoxFit.contain),
                ),
              )
            else
              SizedBox(
                height: 320,
                width: double.maxFinite,
                child: FutureBuilder<void>(
                  future: _initializeFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done || _controller == null) {
                      return const Center(child: CircularProgressIndicator(color: _brandColor));
                    }
                    return Column(
                      children: [
                        Expanded(
                          child: AspectRatio(
                            aspectRatio: _controller!.value.aspectRatio,
                            child: VideoPlayer(_controller!),
                          ),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: () {
                            if (_controller!.value.isPlaying) {
                              _controller!.pause();
                            } else {
                              _controller!.play();
                            }
                            setState(() {});
                          },
                          style: FilledButton.styleFrom(backgroundColor: _brandColor),
                          icon: Icon(_controller!.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                          label: Text(
                            _controller!.value.isPlaying ? 'إيقاف' : 'تشغيل',
                            style: const TextStyle(fontFamily: 'Cairo'),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إغلاق', style: TextStyle(fontFamily: 'Cairo')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentSelectionResult {
  final bool confirmed;
  final String method;

  const _PaymentSelectionResult({required this.confirmed, required this.method});
}

class _PromoSummaryScreen extends StatelessWidget {
  final Map<String, dynamic> preview;
  final String providerName;

  const _PromoSummaryScreen({required this.preview, required this.providerName});

  @override
  Widget build(BuildContext context) {
    final items = _asMapList(preview['items']);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F4FC),
        appBar: AppBar(
          backgroundColor: _brandColor,
          title: const Text('ملخص طلب الترويج والتكلفة', style: TextStyle(fontFamily: 'Cairo')),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('اسم المختص: $providerName', style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  const Text(
                    'عرض البنود التي تم اختيارها من الصفحة السابقة وتكلفة كل بند',
                    style: TextStyle(fontFamily: 'Cairo'),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Table(
                        border: TableBorder.all(color: const Color(0xFFB241A1)),
                        children: [
                          const TableRow(
                            decoration: BoxDecoration(color: Color(0xFFA12D9D)),
                            children: [
                              Padding(
                                padding: EdgeInsets.all(10),
                                child: Text('البند', style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontWeight: FontWeight.bold)),
                              ),
                              Padding(
                                padding: EdgeInsets.all(10),
                                child: Text('التكلفة', style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                          for (final item in items)
                            TableRow(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Text(
                                    (item['title'] as String? ?? _serviceLabel(item['service_type'] as String?)).trim(),
                                    style: const TextStyle(fontFamily: 'Cairo'),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Text(
                                    '${_money(item['subtotal'])} ريال${item['duration_days'] != null ? ' • ${item['duration_days']} يوم' : ''}',
                                    style: const TextStyle(fontFamily: 'Cairo'),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Table(
                    border: TableBorder.all(color: const Color(0xFFB241A1)),
                    children: [
                      TableRow(
                        children: [
                          const Padding(padding: EdgeInsets.all(10), child: Text('المجموع', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
                          Padding(padding: const EdgeInsets.all(10), child: Text('${_money(preview['subtotal'])} ريال', style: const TextStyle(fontFamily: 'Cairo'))),
                        ],
                      ),
                      TableRow(
                        children: [
                          const Padding(padding: EdgeInsets.all(10), child: Text('VAT', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
                          Padding(padding: const EdgeInsets.all(10), child: Text('${_money(preview['vat_amount'])} ريال', style: const TextStyle(fontFamily: 'Cairo'))),
                        ],
                      ),
                      TableRow(
                        children: [
                          const Padding(padding: EdgeInsets.all(10), child: Text('التكلفة الكلية', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
                          Padding(padding: const EdgeInsets.all(10), child: Text('${_money(preview['total'])} ريال', style: const TextStyle(fontFamily: 'Cairo'))),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () async {
                            final paymentResult = await Navigator.of(context).push<_PaymentSelectionResult>(
                              MaterialPageRoute(
                                builder: (_) => _PromoPaymentScreen(totalAmount: _money(preview['total'])),
                              ),
                            );
                            if (!context.mounted || paymentResult == null) return;
                            Navigator.pop(context, paymentResult);
                          },
                          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2F7D1E)),
                          child: const Text('استمرار', style: TextStyle(fontFamily: 'Cairo')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PromoPaymentScreen extends StatefulWidget {
  final String totalAmount;

  const _PromoPaymentScreen({required this.totalAmount});

  @override
  State<_PromoPaymentScreen> createState() => _PromoPaymentScreenState();
}

class _PromoPaymentScreenState extends State<_PromoPaymentScreen> {
  String _method = 'apple_pay';
  final _cardNumber = TextEditingController();
  final _expiry = TextEditingController();
  final _cvv = TextEditingController();
  final _name = TextEditingController();

  @override
  void dispose() {
    _cardNumber.dispose();
    _expiry.dispose();
    _cvv.dispose();
    _name.dispose();
    super.dispose();
  }

  void _continuePay() {
    if (_method == 'card') {
      final cardNo = _cardNumber.text.replaceAll(' ', '');
      if (!_isValidCardNumber(cardNo)) {
        _showError('رقم البطاقة غير صالح.');
        return;
      }
      if (!_isValidExpiry(_expiry.text)) {
        _showError('تاريخ الانتهاء غير صالح.');
        return;
      }
      if (!_isValidCvv(_cvv.text)) {
        _showError('CVV غير صالح.');
        return;
      }
      if (_name.text.trim().isEmpty) {
        _showError('أدخل اسم حامل البطاقة.');
        return;
      }
    }
    Navigator.pop(context, _PaymentSelectionResult(confirmed: true, method: _method));
  }

  void _showError(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: Colors.red, content: Text(text, style: const TextStyle(fontFamily: 'Cairo'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F4FC),
        appBar: AppBar(
          backgroundColor: _brandColor,
          title: const Text('شاشة الدفع', style: TextStyle(fontFamily: 'Cairo')),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ListView(
                children: [
                  Text('المبلغ المطلوب: ${widget.totalAmount} ريال', style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'apple_pay', label: Text('Apple Pay', style: TextStyle(fontFamily: 'Cairo')), icon: Icon(Icons.phone_iphone_rounded)),
                      ButtonSegment(value: 'card', label: Text('بطاقة بنكية', style: TextStyle(fontFamily: 'Cairo')), icon: Icon(Icons.credit_card_rounded)),
                    ],
                    selected: {_method},
                    onSelectionChanged: (set) => setState(() => _method = set.first),
                  ),
                  const SizedBox(height: 14),
                  if (_method == 'apple_pay')
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Text('Pay with Apple Pay', style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                      ),
                    )
                  else ...[
                    TextField(
                      controller: _name,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'اسم حامل البطاقة', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _cardNumber,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      maxLength: 19,
                      decoration: const InputDecoration(labelText: 'رقم البطاقة', border: OutlineInputBorder(), counterText: ''),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _expiry,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.next,
                            maxLength: 5,
                            decoration: const InputDecoration(labelText: 'MM/YY', border: OutlineInputBorder(), counterText: ''),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _cvv,
                            keyboardType: TextInputType.number,
                            obscureText: true,
                            maxLength: 4,
                            decoration: const InputDecoration(labelText: 'CVV', border: OutlineInputBorder(), counterText: ''),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Text(
                    'أفضل الممارسات: لا يتم تخزين بيانات البطاقة داخل التطبيق ويتم إرسالها عبر قناة مشفرة فقط.',
                    style: TextStyle(fontFamily: 'Cairo', color: Colors.black54, height: 1.6),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: _continuePay,
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2F7D1E)),
                    child: const Text('دفع', style: TextStyle(fontFamily: 'Cairo')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

bool _isValidCardNumber(String value) {
  if (value.length < 12 || value.length > 19 || int.tryParse(value) == null) return false;
  int sum = 0;
  bool alternate = false;
  for (int i = value.length - 1; i >= 0; i--) {
    int n = int.parse(value[i]);
    if (alternate) {
      n *= 2;
      if (n > 9) n -= 9;
    }
    sum += n;
    alternate = !alternate;
  }
  return sum % 10 == 0;
}

bool _isValidExpiry(String value) {
  final normalized = value.trim();
  if (!RegExp(r'^\d{2}/\d{2}$').hasMatch(normalized)) return false;
  final parts = normalized.split('/');
  final month = int.tryParse(parts[0]);
  final year = int.tryParse(parts[1]);
  if (month == null || year == null || month < 1 || month > 12) return false;
  final now = DateTime.now();
  final fullYear = 2000 + year;
  final expiry = DateTime(fullYear, month + 1, 0, 23, 59, 59);
  return expiry.isAfter(now);
}

bool _isValidCvv(String value) {
  return RegExp(r'^\d{3,4}$').hasMatch(value.trim());
}
