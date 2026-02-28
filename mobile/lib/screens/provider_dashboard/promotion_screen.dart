import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../constants/saudi_cities.dart';
import 'package:nawafeth/services/promo_service.dart';

/// صفحة الترويج / الإعلانات — مربوطة بالـ API
class PromotionScreen extends StatefulWidget {
  const PromotionScreen({super.key});

  @override
  State<PromotionScreen> createState() => _PromotionScreenState();
}

class _PromotionScreenState extends State<PromotionScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // ────── حالة التحميل ──────
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _myRequests = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadMyRequests();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadMyRequests({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    final res = await PromoService.fetchMyRequests();
    if (!mounted) return;

    if (res.isSuccess) {
      final list =
          res.dataAsList ?? (res.dataAsMap?['results'] as List?) ?? [];
      _myRequests = list.cast<Map<String, dynamic>>();
    } else {
      _errorMessage = res.error ?? 'تعذر تحميل طلبات الترويج';
    }

    setState(() => _isLoading = false);
  }

  // ──── خريطة حالات الطلب ────
  static const _statusLabels = {
    'new': 'جديد',
    'in_review': 'قيد المراجعة',
    'quoted': 'تم التسعير',
    'pending_payment': 'بانتظار الدفع',
    'active': 'مفعل',
    'rejected': 'مرفوض',
    'expired': 'منتهي',
    'cancelled': 'ملغي',
  };

  static const _statusColors = {
    'new': Colors.blue,
    'in_review': Colors.orange,
    'quoted': Colors.teal,
    'pending_payment': Colors.amber,
    'active': Colors.green,
    'rejected': Colors.red,
    'expired': Colors.grey,
    'cancelled': Colors.blueGrey,
  };

  static const _adTypeLabels = {
    'banner_home': 'بانر الصفحة الرئيسية',
    'banner_category': 'بانر صفحة القسم',
    'banner_search': 'بانر صفحة البحث',
    'popup_home': 'نافذة منبثقة رئيسية',
    'popup_category': 'نافذة منبثقة داخل قسم',
    'featured_top5': 'تمييز ضمن أول 5',
    'featured_top10': 'تمييز ضمن أول 10',
    'boost_profile': 'تعزيز ملف مقدم الخدمة',
    'push_notification': 'إشعار دفع (Push)',
  };

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F4FC),
        appBar: AppBar(
          backgroundColor: Colors.deepPurple,
          elevation: 0,
          centerTitle: true,
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text(
            'الترويج والإعلانات',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            labelStyle:
                const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
            unselectedLabelStyle: const TextStyle(fontFamily: 'Cairo'),
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            tabs: const [
              Tab(text: 'طلباتي'),
              Tab(text: 'طلب جديد'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildMyRequestsTab(),
            _CreatePromoRequestForm(
              onCreated: () {
                _tabController.animateTo(0);
                _loadMyRequests(silent: true);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ──── تبويب طلباتي ────
  Widget _buildMyRequestsTab() {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.deepPurple));
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 52, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: const TextStyle(fontFamily: 'Cairo', color: Colors.black54),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _loadMyRequests,
              icon: const Icon(Icons.refresh, color: Colors.white),
              label: const Text('إعادة المحاولة',
                  style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      );
    }

    if (_myRequests.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.campaign_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text(
              'لا توجد طلبات ترويج حتى الآن',
              style: TextStyle(fontFamily: 'Cairo', fontSize: 16, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => _tabController.animateTo(1),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('أنشئ طلبك الأول',
                  style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadMyRequests(silent: true),
      color: Colors.deepPurple,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _myRequests.length,
        itemBuilder: (_, i) => _buildRequestCard(_myRequests[i]),
      ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> req) {
    final code = req['code'] as String? ?? '';
    final title = req['title'] as String? ?? 'طلب ترويج';
    final status = req['status'] as String? ?? 'new';
    final adType = req['ad_type'] as String? ?? '';
    final createdAt = req['created_at'] as String? ?? '';

    final statusLabel = _statusLabels[status] ?? status;
    final statusColor = _statusColors[status] ?? Colors.grey;
    final adLabel = _adTypeLabels[adType] ?? adType;

    String dateStr = '';
    if (createdAt.isNotEmpty) {
      try {
        final dt = DateTime.parse(createdAt);
        dateStr =
            '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      } catch (_) {
        dateStr = createdAt;
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 3,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.campaign,
                      color: Colors.deepPurple, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          fontFamily: 'Cairo',
                        ),
                      ),
                      if (code.isNotEmpty)
                        Text(
                          code,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black45,
                            fontFamily: 'Cairo',
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.ad_units, size: 16, color: Colors.black45),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    adLabel,
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        color: Colors.black54),
                  ),
                ),
                const Icon(Icons.calendar_today,
                    size: 14, color: Colors.black45),
                const SizedBox(width: 4),
                Text(
                  dateStr,
                  style: const TextStyle(fontSize: 12, color: Colors.black45),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ──── نموذج إنشاء طلب ترويج جديد ────
class _CreatePromoRequestForm extends StatefulWidget {
  final VoidCallback onCreated;
  const _CreatePromoRequestForm({required this.onCreated});

  @override
  State<_CreatePromoRequestForm> createState() =>
      _CreatePromoRequestFormState();
}

class _CreatePromoRequestFormState extends State<_CreatePromoRequestForm> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _redirectCtrl = TextEditingController();
  final _msgTitleCtrl = TextEditingController();
  final _msgBodyCtrl = TextEditingController();

  String _adType = 'banner_home';
  String _frequency = '60s';
  String _position = 'normal';
  DateTime? _startDate;
  DateTime? _endDate;
  String _targetCity = '';
  String _targetCategory = '';

  bool _isSending = false;

  final List<File> _assetFiles = [];
  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    _titleCtrl.dispose();
    _redirectCtrl.dispose();
    _msgTitleCtrl.dispose();
    _msgBodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? now.add(const Duration(days: 1)) : (now.add(const Duration(days: 2))),
      firstDate: now,
      lastDate: DateTime(now.year + 2),
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.deepPurple,
              onPrimary: Colors.white,
            ),
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: child!,
          ),
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  Future<void> _pickAsset() async {
    final xf = await _picker.pickImage(source: ImageSource.gallery);
    if (xf != null) {
      setState(() => _assetFiles.add(File(xf.path)));
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startDate == null || _endDate == null) {
      _showSnack('يرجى تحديد تاريخ البداية والنهاية', isError: true);
      return;
    }
    if (_endDate!.isBefore(_startDate!) ||
        _endDate!.isAtSameMomentAs(_startDate!)) {
      _showSnack('تاريخ النهاية يجب أن يكون بعد البداية', isError: true);
      return;
    }

    setState(() => _isSending = true);

    final res = await PromoService.createRequest(
      title: _titleCtrl.text.trim(),
      adType: _adType,
      startAt: _startDate!.toUtc().toIso8601String(),
      endAt: _endDate!.toUtc().toIso8601String(),
      frequency: _frequency,
      position: _position,
      targetCategory: _targetCategory.trim().isNotEmpty ? _targetCategory.trim() : null,
      targetCity: _targetCity.trim().isNotEmpty ? _targetCity.trim() : null,
      redirectUrl:
          _redirectCtrl.text.trim().isNotEmpty ? _redirectCtrl.text.trim() : null,
      messageTitle:
          _msgTitleCtrl.text.trim().isNotEmpty ? _msgTitleCtrl.text.trim() : null,
      messageBody:
          _msgBodyCtrl.text.trim().isNotEmpty ? _msgBodyCtrl.text.trim() : null,
    );

    if (!mounted) return;

    if (!res.isSuccess) {
      setState(() => _isSending = false);
      _showSnack(res.error ?? 'فشل في إنشاء الطلب', isError: true);
      return;
    }

    final requestId = res.dataAsMap?['id'] as int?;

    // رفع الملفات
    if (requestId != null && _assetFiles.isNotEmpty) {
      for (final f in _assetFiles) {
        await PromoService.uploadAsset(
          requestId: requestId,
          file: f,
          assetType: 'image',
        );
      }
    }

    if (!mounted) return;
    setState(() => _isSending = false);
    _showSnack('تم إرسال طلب الترويج بنجاح');
    widget.onCreated();
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
      ),
    );
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return 'اختر التاريخ';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'إنشاء طلب ترويج جديد',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'أنشئ طلب إعلان وسيتم مراجعته من فريق نوافذ.',
              style: TextStyle(
                fontFamily: 'Cairo',
                color: Colors.black54,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),

            // عنوان الحملة
            TextFormField(
              controller: _titleCtrl,
              decoration: _inputDecoration('عنوان الحملة', Icons.title),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'العنوان مطلوب' : null,
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            const SizedBox(height: 14),

            // نوع الإعلان
            _labelText('نوع الإعلان'),
            const SizedBox(height: 6),
            _dropdown<String>(
              value: _adType,
              items: const {
                'banner_home': 'بانر الصفحة الرئيسية',
                'banner_category': 'بانر صفحة القسم',
                'banner_search': 'بانر صفحة البحث',
                'popup_home': 'نافذة منبثقة رئيسية',
                'popup_category': 'نافذة منبثقة داخل قسم',
                'featured_top5': 'تمييز ضمن أول 5',
                'featured_top10': 'تمييز ضمن أول 10',
                'boost_profile': 'تعزيز الملف',
                'push_notification': 'إشعار دفع',
              },
              onChanged: (v) => setState(() => _adType = v!),
            ),
            const SizedBox(height: 14),

            // تاريخ البداية والنهاية
            Row(
              children: [
                Expanded(
                  child: _datePickerField(
                    label: 'بداية',
                    value: _fmtDate(_startDate),
                    onTap: () => _pickDate(isStart: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _datePickerField(
                    label: 'نهاية',
                    value: _fmtDate(_endDate),
                    onTap: () => _pickDate(isStart: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // معدل الظهور
            _labelText('معدل الظهور'),
            const SizedBox(height: 6),
            _dropdown<String>(
              value: _frequency,
              items: const {
                '10s': 'كل 10 ثواني',
                '20s': 'كل 20 ثانية',
                '30s': 'كل 30 ثانية',
                '60s': 'كل 60 ثانية',
              },
              onChanged: (v) => setState(() => _frequency = v!),
            ),
            const SizedBox(height: 14),

            // الموقع
            _labelText('موقع الظهور'),
            const SizedBox(height: 6),
            _dropdown<String>(
              value: _position,
              items: const {
                'first': 'الأول',
                'second': 'الثاني',
                'top5': 'ضمن أول 5',
                'top10': 'ضمن أول 10',
                'normal': 'عادي',
              },
              onChanged: (v) => setState(() => _position = v!),
            ),
            const SizedBox(height: 14),

            // المدينة المستهدفة
            _labelText('المدينة المستهدفة (اختياري)'),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _targetCity.isNotEmpty ? _targetCity : null,
              decoration: InputDecoration(
                hintText: 'كل المدن',
                hintStyle: const TextStyle(fontFamily: 'Cairo'),
                prefixIcon: const Icon(Icons.location_city, color: Colors.deepPurple),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Colors.deepPurple, width: 1.4),
                ),
              ),
              isExpanded: true,
              menuMaxHeight: 300,
              items: [
                const DropdownMenuItem<String>(
                  value: '',
                  child: Text('كل المدن', style: TextStyle(fontFamily: 'Cairo')),
                ),
                ...SaudiCities.all.map((city) => DropdownMenuItem(
                      value: city,
                      child: Text(city, style: const TextStyle(fontFamily: 'Cairo')),
                    )),
              ],
              onChanged: (v) => setState(() => _targetCity = v ?? ''),
            ),
            const SizedBox(height: 14),

            // رابط التوجيه
            TextFormField(
              controller: _redirectCtrl,
              decoration:
                  _inputDecoration('رابط التوجيه (اختياري)', Icons.link),
              keyboardType: TextInputType.url,
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            const SizedBox(height: 14),

            // رسالة / عنوان الإشعار
            TextFormField(
              controller: _msgTitleCtrl,
              decoration: _inputDecoration(
                  'عنوان الرسالة (اختياري)', Icons.text_fields),
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _msgBodyCtrl,
              decoration: _inputDecoration(
                  'نص الرسالة (اختياري)', Icons.message_outlined),
              maxLines: 3,
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            const SizedBox(height: 18),

            // ملفات الإعلان
            _labelText('صور / ملفات الإعلان'),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _pickAsset,
              child: Container(
                height: 80,
                width: double.infinity,
                decoration: BoxDecoration(
                  border:
                      Border.all(color: Colors.grey.shade300, width: 1.5),
                  borderRadius: BorderRadius.circular(14),
                  color: Colors.white,
                ),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_upload_outlined,
                          color: Colors.deepPurple, size: 28),
                      SizedBox(height: 4),
                      Text(
                        'اضغط لإضافة صورة أو فيديو',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_assetFiles.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (int i = 0; i < _assetFiles.length; i++)
                    Chip(
                      label: Text('ملف ${i + 1}',
                          style: const TextStyle(fontFamily: 'Cairo')),
                      deleteIcon: const Icon(Icons.close, size: 16),
                      onDeleted: () =>
                          setState(() => _assetFiles.removeAt(i)),
                      backgroundColor: Colors.grey.shade100,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isSending ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  disabledBackgroundColor: Colors.deepPurple.withOpacity(0.4),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _isSending
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text(
                        'إرسال الطلب',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _labelText(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'Cairo',
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontFamily: 'Cairo'),
      prefixIcon: Icon(icon, color: Colors.deepPurple),
      filled: true,
      fillColor: Colors.white,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.deepPurple, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.red),
      ),
    );
  }

  Widget _dropdown<T>({
    required T value,
    required Map<T, String> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          borderRadius: BorderRadius.circular(12),
          items: items.entries
              .map((e) => DropdownMenuItem(
                    value: e.key,
                    child: Text(e.value,
                        style: const TextStyle(fontFamily: 'Cairo')),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _datePickerField({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today,
                size: 18, color: Colors.deepPurple),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        color: Colors.black45),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                        fontFamily: 'Cairo', fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
