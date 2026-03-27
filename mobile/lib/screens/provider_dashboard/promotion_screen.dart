import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:nawafeth/models/user_profile.dart';
import 'package:nawafeth/services/billing_service.dart';
import 'package:nawafeth/services/profile_service.dart';
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
  bool _isOpeningNewRequest = false;
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

  Future<void> _openNewRequestPage() async {
    if (_isOpeningNewRequest) return;
    _isOpeningNewRequest = true;
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const PromotionNewRequestScreen()),
    );
    if (!mounted) return;
    _tabController.animateTo(0);
    if (created == true) {
      _loadRequests(silent: true);
    }
    _isOpeningNewRequest = false;
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
            onTap: (index) {
              if (index == 1) {
                Future<void>.microtask(_openNewRequestPage);
              }
            },
            tabs: const [Tab(text: 'طلباتي'), Tab(text: 'طلب جديد')],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _buildRequestsTab(),
            _buildNewRequestTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildNewRequestTab() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.campaign_rounded, size: 34, color: _brandColor),
                const SizedBox(height: 12),
                const Text(
                  'طلب جديد',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    color: _brandColor,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'الانتقال إلى الصفحة التفصيلية لخيارات الترويج',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Cairo', color: Colors.black54),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _openNewRequestPage,
                  style: FilledButton.styleFrom(
                    backgroundColor: _brandColor,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('فتح الطلب الجديد', style: TextStyle(fontFamily: 'Cairo')),
                ),
              ],
            ),
          ),
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
          if (
            (item['service_type'] as String? ?? '') != 'search_results' &&
            (item['target_city'] as String? ?? '').isNotEmpty
          )
            _line('المدينة', item['target_city'] as String),
          if (item['send_at'] != null) _line('وقت الإرسال', _fmtDate(item['send_at'])),
          if ((item['redirect_url'] as String? ?? '').isNotEmpty) _line('رابط التحويل', item['redirect_url'] as String),
          if ((item['message_title'] as String? ?? '').isNotEmpty) _line('عنوان الرسالة', item['message_title'] as String),
          if ((item['message_body'] as String? ?? '').isNotEmpty) _line('نص الرسالة', item['message_body'] as String),
          if ((item['operator_note'] as String? ?? '').isNotEmpty) _line('تعليق المكلف', item['operator_note'] as String),
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

class PromotionNewRequestScreen extends StatelessWidget {
  const PromotionNewRequestScreen({super.key});

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
            'طلب ترويج جديد',
            style: TextStyle(
              fontFamily: 'Cairo',
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        body: _PromoComposer(
          onCreated: () {
            Navigator.of(context).pop(true);
          },
        ),
      ),
    );
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
  String _providerName = 'مزود الخدمة';
  List<Map<String, dynamic>> _liveItems = const [];
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
    _loadProviderIdentity();
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

  Future<void> _loadProviderIdentity() async {
    final res = await ProfileService.fetchMyProfile();
    if (!mounted || !res.isSuccess || res.data == null) return;
    final UserProfile me = res.data!;
    final providerDisplay = (me.providerDisplayName ?? '').trim();
    final displayName = me.displayName.trim();
    final username = me.usernameDisplay.trim();
    final chosen = providerDisplay.isNotEmpty
        ? providerDisplay
        : (displayName.isNotEmpty
            ? displayName
            : (username.isNotEmpty ? username : 'مزود الخدمة'));
    setState(() => _providerName = chosen);
  }

  Future<void> _calculateLiveQuote() async {
    if (!mounted || _showPricing) return;
    if (_title.text.trim().isEmpty || _selected.isEmpty) {
      if (!mounted) return;
      setState(() {
        _quoteLoading = false;
        _liveItems = const [];
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
          _liveItems = const [];
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
        _liveItems = const [];
        _liveSubtotal = '0.00';
        _liveVat = '0.00';
        _liveTotal = '0.00';
      });
      return;
    }

    final data = Map<String, dynamic>.from(previewRes.dataAsMap ?? const {});
    setState(() {
      _quoteLoading = false;
      _liveItems = _asMapList(data['items']);
      _liveSubtotal = _money(data['subtotal']);
      _liveVat = _money(data['vat_amount']);
      _liveTotal = _money(data['total']);
    });
  }

  Widget _buildLiveTotalCard() {
    final hasLiveItems = _liveItems.isNotEmpty;
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
          if (hasLiveItems) ...[
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),
            for (final item in _liveItems)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        (item['title'] as String? ?? _serviceLabel(item['service_type'] as String?)).trim(),
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _brandColor,
                        ),
                      ),
                    ),
                    Text(
                      '${_money(item['subtotal'])} ريال${item['duration_days'] != null ? ' • ${item['duration_days']} يوم' : ''}',
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final providerLabel = _providerName.trim().isEmpty ? 'مزود الخدمة' : _providerName.trim();
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
          _buildServiceSelectionCard(),
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
                      'استمرار',
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

  void _toggleServiceSelection(String serviceType, bool enabled) {
    setState(() {
      if (enabled) {
        if (!_selected.contains(serviceType)) {
          _selected.add(serviceType);
        }
        _selected.sort((a, b) {
          final aIndex = _promoServices.indexWhere((service) => service.type == a);
          final bIndex = _promoServices.indexWhere((service) => service.type == b);
          return aIndex.compareTo(bIndex);
        });
      } else {
        _selected.remove(serviceType);
      }
    });
    _scheduleLiveQuote();
  }

  Widget _buildServiceSelectionCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD7C9EB)),
      ),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Icon(Icons.tune_rounded, color: _brandColor, size: 18),
                SizedBox(width: 8),
                Text(
                  'خيارات الترويج',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w700,
                    color: _brandColor,
                  ),
                ),
              ],
            ),
          ),
          for (int i = 0; i < _promoServices.length; i++)
            Container(
              decoration: BoxDecoration(
                border: i == _promoServices.length - 1
                    ? null
                    : Border(
                        top: BorderSide(color: Colors.grey.shade100),
                      ),
              ),
              child: CheckboxListTile(
                value: _selected.contains(_promoServices[i].type),
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: _brandColor,
                title: Text(
                  _promoServices[i].label,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                subtitle: Text(
                  _selected.contains(_promoServices[i].type)
                      ? 'الخدمة مفعلة ويمكنك إدخال التفاصيل بالأسفل'
                      : 'فعّل الخدمة لإدخال التفاصيل',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    color: Colors.black54,
                  ),
                ),
                onChanged: (value) =>
                    _toggleServiceSelection(_promoServices[i].type, value ?? false),
              ),
            ),
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

  Future<bool> _confirmPreviewSubmission(Map<String, dynamic> preview) async {
    final confirmed = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => _PromoSummaryScreen(
              preview: preview,
              providerName: _providerName,
            ),
          ),
        ) ??
        false;
    return confirmed;
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
    final confirmed = await _confirmPreviewSubmission(previewPayload);
    if (!mounted) return;
    if (!confirmed) {
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
    final detailRes =
        requestId == null ? null : await PromoService.fetchRequestDetail(requestId);
    final createdItems = _asMapList(
      detailRes?.dataAsMap?['items'] ?? createRes.dataAsMap?['items'],
    );
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

    final requestCode = (detailRes?.dataAsMap?['code'] ??
            createRes.dataAsMap?['code'] ??
            '') as String;

    if (requestId == null) {
      setState(() => _sending = false);
      _snack('تم إنشاء الطلب لكن تعذر قراءة رقمه. حاول من تبويب طلباتي.', true);
      widget.onCreated();
      return;
    }

    final prepareRes = await PromoService.preparePayment(requestId: requestId);
    if (!mounted) return;
    if (!prepareRes.isSuccess) {
      final uploadNote = uploadFailures.isNotEmpty
          ? ' (فشل رفع ${uploadFailures.length} ملف).'
          : '';
      setState(() => _sending = false);
      _snack(
        '${prepareRes.error ?? "تعذر تجهيز الدفع لهذا الطلب"}$uploadNote',
        true,
      );
      widget.onCreated();
      return;
    }

    final prepared = Map<String, dynamic>.from(prepareRes.dataAsMap ?? const {});
    final invoiceId = int.tryParse('${prepared['invoice'] ?? ''}');
    if (invoiceId == null) {
      setState(() => _sending = false);
      _snack('تم تجهيز الطلب لكن لم يتم العثور على فاتورة صالحة للدفع.', true);
      widget.onCreated();
      return;
    }

    if (_sending) {
      setState(() => _sending = false);
    }

    final paid = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => _PromoPaymentScreen(
              requestId: requestId,
              requestCode: (prepared['code'] as String? ?? requestCode).trim(),
              invoiceId: invoiceId,
              invoiceCode: (prepared['invoice_code'] as String? ?? '').trim(),
              invoiceTotal: _money(prepared['invoice_total']),
              invoiceVat: _money(prepared['invoice_vat']),
            ),
          ),
        ) ??
        false;
    if (!mounted) return;

    if (!paid) {
      _snack('تم إنشاء الطلب ويمكنك إكمال الدفع لاحقًا من تبويب طلباتي.', false);
      widget.onCreated();
      return;
    }

    final paidRequestCode =
        (prepared['code'] as String? ?? requestCode).trim();
    final warningText = uploadFailures.isNotEmpty
        ? 'تمت عملية الدفع، لكن فشل رفع ${uploadFailures.length} ملف.'
        : 'تمت عملية الدفع بنجاح\nسيتم التواصل معكم لتنفيذ طلبكم';

    _title.clear();
    for (final draft in _drafts.values) {
      draft.reset();
    }
    setState(() {
      _selected.clear();
      _liveItems = const [];
      _liveSubtotal = '0.00';
      _liveVat = '0.00';
      _liveTotal = '0.00';
    });

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
                width: double.infinity,
                alignment: Alignment.center,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF2F7D1E),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'رقم الطلب: ${paidRequestCode.isNotEmpty ? paidRequestCode : "—"}',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    fontSize: 18,
                  ),
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
                child: Text(
                  warningText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    color: Colors.black87,
                    height: 1.6,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2F7D1E),
                ),
                child: const Text(
                  'إغلاق',
                  style: TextStyle(fontFamily: 'Cairo'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    widget.onCreated();
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

class _PromoSummaryScreen extends StatelessWidget {
  final Map<String, dynamic> preview;
  final String providerName;

  const _PromoSummaryScreen({
    required this.preview,
    required this.providerName,
  });

  @override
  Widget build(BuildContext context) {
    final items = _asMapList(preview['items']);
    final normalizedProviderName =
        providerName.trim().isEmpty ? 'مزود الخدمة' : providerName.trim();

    DataRow _itemRow(Map<String, dynamic> item) {
      final title = (item['title'] as String? ??
              _serviceLabel(item['service_type'] as String?))
          .trim();
      return DataRow(
        cells: [
          DataCell(
            Text(
              title.isEmpty ? 'خدمة' : title,
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
          ),
          DataCell(
            Text(
              '${_money(item['subtotal'])} ريال',
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
          ),
        ],
      );
    }

    Widget _totalsRow(String label, String amount) {
      return Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: const Color(0xFFA12D9D).withValues(alpha: 0.45)),
            right: BorderSide(color: const Color(0xFFA12D9D).withValues(alpha: 0.45)),
            bottom: BorderSide(color: const Color(0xFFA12D9D).withValues(alpha: 0.45)),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF6EDF9),
                  border: Border(
                    left: BorderSide(
                      color: const Color(0xFFA12D9D).withValues(alpha: 0.45),
                    ),
                  ),
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                color: Colors.white,
                child: Text(
                  amount,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F4FC),
        appBar: AppBar(
          backgroundColor: _brandColor,
          centerTitle: true,
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text(
            'ملخص طلب الترويج والتكلفة',
            style: TextStyle(
              fontFamily: 'Cairo',
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFFA12D9D)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2F7D1E),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'ملخص طلب الترويج والتكلفة',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'اسم المختص',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFA12D9D),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFA12D9D)),
                        ),
                        child: Text(
                          normalizedProviderName,
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'عرض البنود التي تم اختيارها من الصفحة السابقة وتكلفة كل بند',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFA12D9D)),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowColor:
                            WidgetStateProperty.all(const Color(0xFFA12D9D)),
                        headingTextStyle: const TextStyle(
                          fontFamily: 'Cairo',
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                        dataTextStyle: const TextStyle(
                          fontFamily: 'Cairo',
                          color: Colors.black87,
                        ),
                        border:
                            TableBorder.all(color: const Color(0xFFA12D9D)),
                        columns: const [
                          DataColumn(label: Text('البند')),
                          DataColumn(label: Text('التكلفة')),
                        ],
                        rows: items.isEmpty
                            ? [
                                const DataRow(
                                  cells: [
                                    DataCell(Text('لا توجد بنود')),
                                    DataCell(Text('—')),
                                  ],
                                ),
                              ]
                            : items.map(_itemRow).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _totalsRow('المجموع', '${_money(preview['subtotal'])} ريال'),
                  _totalsRow('VAT', '${_money(preview['vat_amount'])} ريال'),
                  _totalsRow('التكلفة الكلية', '${_money(preview['total'])} ريال'),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, false),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFF2F7D1E)),
                            foregroundColor: const Color(0xFF2F7D1E),
                          ),
                          child: const Text(
                            'إلغاء',
                            style: TextStyle(fontFamily: 'Cairo'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF2F7D1E),
                            foregroundColor: Colors.white,
                          ),
                          child: const Text(
                            'استمرار',
                            style: TextStyle(fontFamily: 'Cairo'),
                          ),
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
  final int requestId;
  final String requestCode;
  final int invoiceId;
  final String invoiceCode;
  final String invoiceTotal;
  final String invoiceVat;

  const _PromoPaymentScreen({
    required this.requestId,
    required this.requestCode,
    required this.invoiceId,
    required this.invoiceCode,
    required this.invoiceTotal,
    required this.invoiceVat,
  });

  @override
  State<_PromoPaymentScreen> createState() => _PromoPaymentScreenState();
}

class _PromoPaymentScreenState extends State<_PromoPaymentScreen> {
  final _cardName = TextEditingController();
  final _cardNumber = TextEditingController();
  final _cardExpiry = TextEditingController();
  final _cardCvv = TextEditingController();

  bool _paying = false;
  String _method = 'mada';

  @override
  void dispose() {
    _cardName.dispose();
    _cardNumber.dispose();
    _cardExpiry.dispose();
    _cardCvv.dispose();
    super.dispose();
  }

  String _digitsOnly(String value) => value.replaceAll(RegExp(r'\D+'), '');

  String _formatCardNumber(String value) {
    final digits = _digitsOnly(value);
    final parts = <String>[];
    for (int i = 0; i < digits.length; i += 4) {
      final end = (i + 4 <= digits.length) ? i + 4 : digits.length;
      parts.add(digits.substring(i, end));
    }
    return parts.join(' ');
  }

  String _formatExpiry(String value) {
    final digits = _digitsOnly(value);
    if (digits.length <= 2) return digits;
    return '${digits.substring(0, 2)}/${digits.substring(2)}';
  }

  bool _isLuhnValid(String digits) {
    int sum = 0;
    bool alternate = false;
    for (int i = digits.length - 1; i >= 0; i--) {
      int n = int.tryParse(digits[i]) ?? -1;
      if (n < 0) return false;
      if (alternate) {
        n *= 2;
        if (n > 9) {
          n -= 9;
        }
      }
      sum += n;
      alternate = !alternate;
    }
    return sum % 10 == 0;
  }

  String? _validateCardForm() {
    if (_cardName.text.trim().length < 3) {
      return 'أدخل اسم حامل البطاقة بشكل صحيح.';
    }

    final cardDigits = _digitsOnly(_cardNumber.text.trim());
    if (cardDigits.length < 12 || cardDigits.length > 19 || !_isLuhnValid(cardDigits)) {
      return 'رقم البطاقة غير صالح.';
    }

    final expiry = _cardExpiry.text.trim();
    final expiryMatch = RegExp(r'^(\d{2})/(\d{2})$').firstMatch(expiry);
    if (expiryMatch == null) {
      return 'أدخل تاريخ الانتهاء بصيغة MM/YY.';
    }
    final month = int.tryParse(expiryMatch.group(1) ?? '') ?? 0;
    final year = 2000 + (int.tryParse(expiryMatch.group(2) ?? '') ?? 0);
    if (month < 1 || month > 12) {
      return 'شهر انتهاء البطاقة غير صحيح.';
    }
    final expiryDate = DateTime(year, month + 1, 0, 23, 59, 59);
    if (expiryDate.isBefore(DateTime.now())) {
      return 'البطاقة منتهية الصلاحية.';
    }

    final cvv = _digitsOnly(_cardCvv.text.trim());
    if (cvv.length < 3 || cvv.length > 4) {
      return 'رمز CVV غير صالح.';
    }
    return null;
  }

  void _snack(String message, bool error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: error ? Colors.red : Colors.green,
        content: Text(message, style: const TextStyle(fontFamily: 'Cairo')),
      ),
    );
  }

  Future<void> _submitPayment() async {
    final validationError = _validateCardForm();
    if (validationError != null) {
      _snack(validationError, true);
      return;
    }

    setState(() => _paying = true);
    final idempotencyKey =
        'promo-checkout-${widget.requestId}-${widget.invoiceId}';

    final initRes = await BillingService.initPayment(
      invoiceId: widget.invoiceId,
      idempotencyKey: idempotencyKey,
    );
    if (!mounted) return;
    if (!initRes.isSuccess) {
      setState(() => _paying = false);
      _snack(initRes.error ?? 'تعذر تهيئة الدفع', true);
      return;
    }

    final payRes = await BillingService.completeMockPayment(
      invoiceId: widget.invoiceId,
      idempotencyKey: idempotencyKey,
    );
    if (!mounted) return;
    if (!payRes.isSuccess) {
      setState(() => _paying = false);
      _snack(payRes.error ?? 'تعذر إتمام عملية الدفع', true);
      return;
    }

    _cardName.clear();
    _cardNumber.clear();
    _cardExpiry.clear();
    _cardCvv.clear();
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    Widget paymentMethodChip({
      required String value,
      required String label,
    }) {
      final selected = _method == value;
      return Expanded(
        child: InkWell(
          onTap: _paying
              ? null
              : () {
                  setState(() => _method = value);
                },
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected ? const Color(0xFF2F7D1E) : const Color(0xFFD9C4EB),
              ),
              color: selected ? const Color(0xFFF3FCEF) : Colors.white,
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Cairo',
                color: selected ? const Color(0xFF2F7D1E) : const Color(0xFF4B2D73),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F4FC),
        appBar: AppBar(
          backgroundColor: const Color(0xFF2F7D1E),
          centerTitle: true,
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text(
            'شاشة الدفع',
            style: TextStyle(
              fontFamily: 'Cairo',
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFFA12D9D)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2F7D1E),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'شاشة الدفع',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (widget.requestCode.trim().isNotEmpty) ...[
                    _line('رقم الطلب', widget.requestCode.trim()),
                  ],
                  if (widget.invoiceCode.trim().isNotEmpty) ...[
                    _line('رقم الفاتورة', widget.invoiceCode.trim()),
                  ],
                  _line('الإجمالي', '${widget.invoiceTotal} ريال'),
                  _line('VAT', '${widget.invoiceVat} ريال'),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFD9C4EB), width: 1.2),
                    ),
                    child: const Text(
                      'Apple Pay',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 42,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      paymentMethodChip(value: 'mada', label: 'مدى'),
                      const SizedBox(width: 8),
                      paymentMethodChip(value: 'visa', label: 'فيزا'),
                      const SizedBox(width: 8),
                      paymentMethodChip(value: 'mastercard', label: 'ماستر كارد'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _cardName,
                    enabled: !_paying,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'اسم حامل البطاقة',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _cardNumber,
                    enabled: !_paying,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'رقم البطاقة',
                      hintText: '0000 0000 0000 0000',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      final formatted = _formatCardNumber(value).trim();
                      if (formatted == _cardNumber.text) return;
                      _cardNumber.value = TextEditingValue(
                        text: formatted,
                        selection:
                            TextSelection.collapsed(offset: formatted.length),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _cardExpiry,
                          enabled: !_paying,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'تاريخ الانتهاء MM/YY',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (value) {
                            final formatted = _formatExpiry(value).trim();
                            if (formatted == _cardExpiry.text) return;
                            _cardExpiry.value = TextEditingValue(
                              text: formatted,
                              selection: TextSelection.collapsed(
                                offset: formatted.length,
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _cardCvv,
                          enabled: !_paying,
                          keyboardType: TextInputType.number,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'CVV',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (value) {
                            final digits = _digitsOnly(value);
                            final clipped =
                                digits.length > 4 ? digits.substring(0, 4) : digits;
                            if (clipped == _cardCvv.text) return;
                            _cardCvv.value = TextEditingValue(
                              text: clipped,
                              selection:
                                  TextSelection.collapsed(offset: clipped.length),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5FFF2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFDCEFD7)),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'حماية الدفع',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF2F7D1E),
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'اتصال مشفر، تحقق idempotency لمنع التكرار، وعدم الاحتفاظ ببيانات البطاقة بعد إتمام العملية.',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            color: Colors.black54,
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: _paying ? null : _submitPayment,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2F7D1E),
                      foregroundColor: Colors.white,
                    ),
                    child: _paying
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'دفع',
                            style: TextStyle(fontFamily: 'Cairo'),
                          ),
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
