import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:nawafeth/services/billing_service.dart';
import 'package:nawafeth/services/promo_service.dart';

const _brandColor = Colors.deepPurple;

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

const _searchPositionLabels = {
  'first': 'الأول في القائمة',
  'second': 'الثاني في القائمة',
  'top5': 'من أول خمسة أسماء',
  'top10': 'من أول عشرة أسماء',
};

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
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _requests.length,
        itemBuilder: (_, index) => _buildRequestCard(_requests[index]),
      ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> request) {
    final status = (request['status'] as String? ?? 'new').trim();
    final opsStatus = (request['ops_status'] as String? ?? '').trim();
    final items = _asMapList(request['items']);
    final canPay = _canPayRequest(request);
    final labels = items
        .take(3)
        .map((item) => _serviceLabel(item['service_type'] as String?))
        .join('، ');
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _showRequestDialog(request),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.campaign_rounded, color: _brandColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (request['title'] as String? ?? 'طلب ترويج').trim(),
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          (request['code'] as String? ?? '').trim(),
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            color: Colors.black45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _badge(_statusLabels[status] ?? status),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _chip('${items.length} خدمة'),
                  if (opsStatus.isNotEmpty) _chip(_opsLabels[opsStatus] ?? opsStatus),
                  if (request['invoice_total'] != null)
                    _chip('${_money(request['invoice_total'])} ريال'),
                ],
              ),
              if (labels.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  labels,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                ),
              ],
              if (canPay) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: () => _startPayment(request),
                    style: FilledButton.styleFrom(
                      backgroundColor: _brandColor,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.credit_card_rounded),
                    label: const Text(
                      'الدفع الآن',
                      style: TextStyle(fontFamily: 'Cairo'),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showRequestDialog(Map<String, dynamic> request) async {
    final items = _asMapList(request['items']);
    final canPay = _canPayRequest(request);
    final action = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          (request['title'] as String? ?? 'طلب ترويج').trim(),
          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _line('رقم الطلب', (request['code'] as String? ?? '').trim()),
                _line('الحالة', _statusLabels[request['status']] ?? '${request['status']}'),
                _line(
                  'التنفيذ',
                  _opsLabels[request['ops_status']] ?? '${request['ops_status'] ?? ''}',
                ),
                if ((request['invoice_code'] as String? ?? '').trim().isNotEmpty)
                  _line('رقم الفاتورة', (request['invoice_code'] as String).trim()),
                if ((request['invoice_status'] as String? ?? '').trim().isNotEmpty)
                  _line(
                    'حالة الفاتورة',
                    (request['payment_effective'] == true)
                        ? 'مدفوعة'
                        : (_invoiceStatusLabels[request['invoice_status']] ??
                            '${request['invoice_status']}'),
                  ),
                if (request['invoice_total'] != null)
                  _line('الإجمالي', '${_money(request['invoice_total'])} ريال'),
                if (request['invoice_vat'] != null)
                  _line('VAT', '${_money(request['invoice_vat'])} ريال'),
                if ((request['quote_note'] as String? ?? '').trim().isNotEmpty)
                  _line('ملاحظة الاعتماد', (request['quote_note'] as String).trim()),
                const SizedBox(height: 10),
                const Text(
                  'الخدمات',
                  style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '- ${_serviceLabel(item['service_type'] as String?)}',
                      style: const TextStyle(fontFamily: 'Cairo'),
                    ),
                  ),
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
    await _startPayment(request);
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
                            setDialogState(() => isPaying = false);
                            _snack(payRes.error ?? 'تعذر إتمام الدفع', true);
                            return;
                          }
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
  late final Map<String, _PromoDraft> _drafts;
  final List<String> _selected = [];
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _drafts = {
      for (final service in _promoServices) service.type: _PromoDraft(service),
    };
  }

  @override
  void dispose() {
    _title.dispose();
    for (final draft in _drafts.values) {
      draft.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          for (int i = 0; i < _selected.length; i++) ...[
            _buildDraftCard(i, _drafts[_selected[i]]!),
            const SizedBox(height: 12),
          ],
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
                IconButton(
                  onPressed: () => setState(() => _selected.remove(service.type)),
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
                onChanged: (value) => setState(
                  () => draft.frequency = value ?? '60s',
                ),
              ),
            ],
            if (service.needsSearch) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: draft.searchScope,
                decoration: _decoration(
                  'قائمة الظهور',
                  Icons.manage_search_rounded,
                ),
                items: _searchScopeLabels.entries
                    .map((e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(
                            e.value,
                            style: const TextStyle(fontFamily: 'Cairo'),
                          ),
                        ))
                    .toList(),
                onChanged: (value) => setState(
                  () => draft.searchScope = value ?? 'default',
                ),
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
                onChanged: (value) => setState(
                  () => draft.searchPosition = value ?? 'first',
                ),
              ),
            ],
            if (service.needsCategory) ...[
              const SizedBox(height: 8),
              TextField(
                controller: draft.category,
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
                onChanged: (value) =>
                    setState(() => draft.notify = value ?? false),
              ),
              CheckboxListTile(
                value: draft.chat,
                title: const Text(
                  'رسائل المحادثات',
                  style: TextStyle(fontFamily: 'Cairo'),
                ),
                onChanged: (value) =>
                    setState(() => draft.chat = value ?? false),
              ),
            ],
            if (service.needsMessage) ...[
              const SizedBox(height: 8),
              TextField(
                controller: draft.message,
                maxLines: 3,
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
                decoration: _decoration('رابط التوجيه', Icons.link_rounded),
              ),
            ],
            if (service.needsSponsor) ...[
              const SizedBox(height: 8),
              TextField(
                controller: draft.sponsorName,
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
                onChanged: (_) => setState(draft.syncSponsorship),
              ),
            ],
            if (service.needsSpecs) ...[
              const SizedBox(height: 8),
              TextField(
                controller: draft.specs,
                decoration: _decoration(
                  'مواصفات الملف المرفوع',
                  Icons.info_outline_rounded,
                ),
              ),
            ],
            if (service.needsAssets) ...[
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
                      Chip(
                        label: Text(
                          _name(draft.files[i]),
                          style: const TextStyle(fontFamily: 'Cairo'),
                        ),
                        onDeleted: () =>
                            setState(() => draft.files.removeAt(i)),
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
  }

  Future<void> _pickAttachment(_PromoDraft draft) async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null) return;
    setState(() {
      draft.files.addAll(
        result.files
            .where((f) => f.path != null && f.path!.isNotEmpty)
            .map((f) => File(f.path!)),
      );
    });
  }

  Future<bool> _confirmQuotePreview(Map<String, dynamic> preview) async {
    final previewItems = _asMapList(preview['items']);
    return (await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text(
              'مراجعة التسعيرة قبل الإرسال',
              style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (previewItems.isNotEmpty) ...[
                      const Text(
                        'تفاصيل التسعير',
                        style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      for (final item in previewItems)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7F3FF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (item['title'] as String? ?? '').trim().isNotEmpty
                                    ? (item['title'] as String).trim()
                                    : _serviceLabel(item['service_type'] as String?),
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_money(item['subtotal'])} ريال'
                                '${item['duration_days'] != null ? ' • ${item['duration_days']} يوم' : ''}',
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  color: Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                    const SizedBox(height: 4),
                    _line('الإجمالي قبل الضريبة', '${_money(preview['subtotal'])} ريال'),
                    _line('VAT', '${_money(preview['vat_amount'])} ريال'),
                    _line('الإجمالي النهائي', '${_money(preview['total'])} ريال'),
                    const SizedBox(height: 8),
                    const Text(
                      'بمتابعة الإرسال سيتم إنشاء الطلب بهذه التسعيرة الحالية، ثم ينتقل الطلب إلى الاعتماد قبل فتح صفحة الدفع.',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        color: Colors.black54,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: _brandColor,
                  foregroundColor: Colors.white,
                ),
                child: const Text(
                  'إرسال الطلب',
                  style: TextStyle(fontFamily: 'Cairo'),
                ),
              ),
            ],
          ),
        )) ??
        false;
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
    );
    if (!mounted) return;
    if (!previewRes.isSuccess) {
      setState(() => _sending = false);
      _snack(previewRes.error ?? 'تعذر معاينة التسعير', true);
      return;
    }

    final confirmed = await _confirmQuotePreview(
      Map<String, dynamic>.from(previewRes.dataAsMap ?? const {}),
    );
    if (!mounted) return;
    if (!confirmed) {
      setState(() => _sending = false);
      return;
    }

    final createRes = await PromoService.createBundleRequest(
      title: _title.text.trim(),
      items: items,
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

    if (requestId != null) {
      for (int i = 0; i < _selected.length; i++) {
        final draft = _drafts[_selected[i]]!;
        for (final file in draft.files) {
          await PromoService.uploadAsset(
            requestId: requestId,
            itemId: ids['${draft.service.type}:$i'],
            file: file,
            assetType: _assetType(file),
            title: draft.service.label,
          );
        }
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
    _snack('تم إرسال طلب الترويج بنجاح', false);
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
  String searchScope = 'default';
  String searchPosition = 'first';
  bool notify = true;
  bool chat = false;

  _PromoDraft(this.service);

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
    if (service.needsMessage && message.text.trim().isEmpty) return 'اكتب نص الرسالة';
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
      body['search_scope'] = searchScope;
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
    files.clear();
    startAt = null;
    endAt = null;
    sendAt = null;
    frequency = '60s';
    searchScope = 'default';
    searchPosition = 'first';
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

Widget _badge(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _brandColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(fontFamily: 'Cairo', color: _brandColor),
      ),
    );

Widget _chip(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF1ECFA),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 12,
          color: _brandColor,
        ),
      ),
    );

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

String _assetType(File file) {
  final ext = _name(file).split('.').last.toLowerCase();
  if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) return 'image';
  if (['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(ext)) return 'video';
  if (ext == 'pdf') return 'pdf';
  return 'other';
}
