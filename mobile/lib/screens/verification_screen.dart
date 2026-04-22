import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../constants/app_theme.dart';
import '../services/billing_service.dart';
import '../services/verification_service.dart';
import '../widgets/platform_top_bar.dart';

class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;

  // الحالة
  String? selectedType; // "blue" أو "green"
  String? blueOption; // "person" / "company"
  final List<String> greenOptions = [];
  final List<File> uploadedFiles = [];
  Map<String, dynamic>? _pricing;

  // المدخلات
  final _formKeyBlue = GlobalKey<FormState>();
  final _idCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  final _crCtrl = TextEditingController();
  final _crDateCtrl = TextEditingController();

  final ImagePicker _picker = ImagePicker();
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadPricing();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _idCtrl.dispose();
    _dobCtrl.dispose();
    _crCtrl.dispose();
    _crDateCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPricing() async {
    final response = await VerificationService.fetchMyPricing();
    if (!mounted || !response.isSuccess) return;
    setState(() {
      _pricing = response.dataAsMap;
    });
  }

  Map<String, dynamic> _pricingEntryFor(String badgeType) {
    final prices = _pricing?['prices'];
    if (prices is Map) {
      final entry = prices[badgeType];
      if (entry is Map<String, dynamic>) return entry;
      if (entry is Map) return Map<String, dynamic>.from(entry);
    }
    return const <String, dynamic>{};
  }

  double _priceFor(String badgeType) {
    final raw = _pricingEntryFor(badgeType)['amount'];
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw.trim()) ?? 100;
    return 100;
  }

  bool _isFreeBadge(String badgeType) {
    final entry = _pricingEntryFor(badgeType);
    if (entry['is_free'] == true) return true;
    return _priceFor(badgeType) <= 0;
  }

  String _formatAmount(double amount) {
    if (amount == amount.roundToDouble()) {
      return amount.toStringAsFixed(0);
    }
    return amount.toStringAsFixed(2);
  }

  String _priceLabelFor(String badgeType) {
    final amount = _priceFor(badgeType);
    if (_isFreeBadge(badgeType)) return 'مجاني ضمن الباقة';
    return '${_formatAmount(amount)} ر.س سنويًا عند الاعتماد';
  }

  String? _asText(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString().trim() ?? '');
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().trim() ?? '') ?? 0;
  }

  bool _requestNeedsPayment(Map<String, dynamic>? requestItem) {
    if (requestItem == null) return false;
    final invoiceSummaryRaw = requestItem['invoice_summary'];
    final invoiceSummary = invoiceSummaryRaw is Map
        ? Map<String, dynamic>.from(invoiceSummaryRaw)
        : const <String, dynamic>{};

    final invoiceId =
        _toInt(requestItem['invoice'] ?? invoiceSummary['id']) ?? 0;
    final requestStatus = (_asText(requestItem['status']) ?? '').toLowerCase();
    final invoiceStatus =
        (_asText(invoiceSummary['status']) ?? '').toLowerCase();
    final invoicePaid =
        invoiceStatus == 'paid' || invoiceSummary['payment_effective'] == true;
    final total = _toDouble(invoiceSummary['total']);

    return invoiceId > 0 &&
        requestStatus == 'pending_payment' &&
        !invoicePaid &&
        total > 0;
  }

  String _requestCode(Map<String, dynamic> requestItem) {
    final code = _asText(requestItem['code']);
    if (code != null) return code;
    final id = _toInt(requestItem['id']);
    if (id != null && id > 0) {
      return 'AD${id.toString().padLeft(6, '0')}';
    }
    return '';
  }

  Future<bool> _startRequestPayment(Map<String, dynamic> requestItem) async {
    final invoiceSummaryRaw = requestItem['invoice_summary'];
    final invoiceSummary = invoiceSummaryRaw is Map
        ? Map<String, dynamic>.from(invoiceSummaryRaw)
        : const <String, dynamic>{};
    final invoiceId = _toInt(requestItem['invoice'] ?? invoiceSummary['id']);
    if (invoiceId == null || invoiceId <= 0) {
      _showErrorSnackBar('لا توجد فاتورة مرتبطة بهذا الطلب');
      return false;
    }

    final requestId = _toInt(requestItem['id']) ?? 0;
    final initRes = await BillingService.initPayment(
      invoiceId: invoiceId,
      idempotencyKey: 'verify-checkout-$requestId-$invoiceId',
    );
    if (!mounted) return false;

    if (!initRes.isSuccess) {
      _showErrorSnackBar(initRes.error ?? 'تعذر فتح صفحة الدفع');
      return false;
    }

    final payload = Map<String, dynamic>.from(initRes.dataAsMap ?? const {});
    final checkoutUrl = _asText(payload['checkout_url']) ?? '';
    if (checkoutUrl.isEmpty) {
      _showErrorSnackBar('تعذر الحصول على رابط صفحة الدفع');
      return false;
    }

    final opened = await BillingService.openCheckout(
      checkoutUrl: checkoutUrl,
      requestCode: _requestCode(requestItem),
    );
    if (!mounted) return false;

    if (!opened) {
      _showErrorSnackBar('تعذر فتح صفحة الدفع الموحدة');
      return false;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'تم فتح صفحة الدفع الموحدة. بعد نجاح السداد ستعود للتطبيق تلقائيًا.',
        ),
        backgroundColor: AppColors.success,
      ),
    );
    return true;
  }

  String _pricingPolicyNote() {
    final note = (_pricing?['price_note'] ?? '').toString().trim();
    if (note.isNotEmpty) return note;
    return 'المبلغ المعروض هو المبلغ النهائي السنوي، ولا تضاف عليه رسوم إضافية.';
  }

  String _pricingHintFor(String badgeType) {
    final tierLabel = (_pricing?['tier_label'] ?? '').toString().trim();
    final amount = _priceFor(badgeType);
    final policyNote = _pricingPolicyNote();
    if (_isFreeBadge(badgeType)) {
      return tierLabel.isNotEmpty
          ? 'هذه الخدمة مجانية ضمن باقة $tierLabel بعد اعتماد الطلب. $policyNote'
          : 'هذه الخدمة مجانية بعد اعتماد الطلب. $policyNote';
    }
    return tierLabel.isNotEmpty
        ? 'الرسوم السنوية النهائية ${_formatAmount(amount)} ر.س وفق باقة $tierLabel، وتصدر الفاتورة فقط بعد مراجعة الطلب واعتماد الشارة. $policyNote'
        : 'الرسوم السنوية النهائية ${_formatAmount(amount)} ر.س، وتصدر الفاتورة فقط بعد مراجعة الطلب واعتماد الشارة. $policyNote';
  }

  String _selectedPricingHint() {
    return _pricingHintFor(selectedType == 'green' ? 'green' : 'blue');
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  String _digitsOnly(String value) {
    return value.replaceAll(RegExp(r'\D'), '');
  }

  Map<String, String>? _buildBluePreviewPayload() {
    if (selectedType != 'blue') return null;
    if (blueOption == 'person') {
      final officialNumber = _digitsOnly(_idCtrl.text.trim());
      final officialDate = _dobCtrl.text.trim();
      if (officialNumber.isEmpty || officialDate.isEmpty) return null;
      return {
        'subject_type': 'individual',
        'official_number': officialNumber,
        'official_date': officialDate,
      };
    }
    if (blueOption == 'company') {
      final officialNumber = _digitsOnly(_crCtrl.text.trim());
      final officialDate = _crDateCtrl.text.trim();
      if (officialNumber.isEmpty || officialDate.isEmpty) return null;
      return {
        'subject_type': 'business',
        'official_number': officialNumber,
        'official_date': officialDate,
      };
    }
    return null;
  }

  Future<Map<String, dynamic>?> _resolveBlueProfileForSubmission() async {
    final payload = _buildBluePreviewPayload();
    if (payload == null) {
      return null;
    }
    final previewRes = await VerificationService.previewBlue(
      subjectType: payload['subject_type']!,
      officialNumber: payload['official_number']!,
      officialDate: payload['official_date']!,
    );
    if (!previewRes.isSuccess) {
      _showErrorSnackBar(
        (previewRes.error ?? 'تعذر التحقق من بيانات الشارة الزرقاء').trim(),
      );
      return null;
    }
    final preview = previewRes.dataAsMap;
    final verifiedName = (preview?['verified_name'] ?? '').toString().trim();
    if (verifiedName.isEmpty) {
      _showErrorSnackBar('تعذر استرجاع الاسم المعتمد للشارة الزرقاء.');
      return null;
    }
    return {
      'subject_type': payload['subject_type'],
      'official_number': payload['official_number'],
      'official_date': payload['official_date'],
      'verified_name': verifiedName,
      'is_name_approved': true,
    };
  }

  // رفع ملف (صورة مستند)
  Future<void> _pickFile() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    setState(() => uploadedFiles.add(File(picked.path)));
  }

  // اختيار تاريخ من تقويم وحفظه بصيغة YYYY-MM-DD
  Future<void> _pickDateForController(
    TextEditingController controller, {
    DateTime? initialDate,
    DateTime? firstDate,
    DateTime? lastDate,
  }) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate ?? DateTime(now.year - 25),
      firstDate: firstDate ?? DateTime(1950),
      lastDate: lastDate ?? DateTime(now.year + 1),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppColors.deepPurple,
              onPrimary: Colors.white,
              onSurface: Colors.black87,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.deepPurple,
              ),
            ),
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: child!,
          ),
        );
      },
    );

    if (picked == null || !mounted) return;

    final y = picked.year.toString().padLeft(4, '0');
    final m = picked.month.toString().padLeft(2, '0');
    final d = picked.day.toString().padLeft(2, '0');
    setState(() {
      controller.text = "$y-$m-$d";
    });
  }

  // تحقق من صحة المعطيات قبل الانتقال
  bool _canGoNext() {
    if (_currentStep == 0) {
      return selectedType != null;
    }
    if (_currentStep == 1) {
      if (selectedType == "blue") {
        if (blueOption == null) return false;
        if (blueOption == "person" || blueOption == "company") {
          return _formKeyBlue.currentState?.validate() == true &&
              uploadedFiles.isNotEmpty;
        }
        return false;
      } else if (selectedType == "green") {
        return greenOptions.isNotEmpty && uploadedFiles.isNotEmpty;
      }
    }
    return true;
  }

  void _nextStep() {
    // تحقق حقول الشارة الزرقاء قبل الانتقال
    if (_currentStep == 1 && selectedType == "blue") {
      _formKeyBlue.currentState?.save();
      if (!_canGoNext()) return;
    }
    if (_currentStep < 2) {
      setState(() => _currentStep++);
      _pageController.animateToPage(
        _currentStep,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _submitRequest();
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
      _pageController.animateToPage(
        _currentStep,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  /// إرسال طلب التوثيق الفعلي عبر API
  Future<void> _submitRequest() async {
    if (_isSending) return;
    setState(() => _isSending = true);

    // تحديد badge_type و requirements
    String? badgeType = selectedType == 'blue' ? 'blue' : 'green';
    List<Map<String, String>> requirements = [];
    Map<String, dynamic>? blueProfile;

    if (selectedType == 'blue' && blueOption != null) {
      requirements.add({
        'badge_type': 'blue',
        'code': 'B1',
      });
    } else if (selectedType == 'green') {
      final codeMap = {
        'توثيق الاعتماد المهني': 'G1',
        'توثيق الرخص التنظيمية': 'G2',
        'توثيق الخبرات العملية': 'G3',
        'توثيق الدرجة العلمية والأكاديمية': 'G4',
        'توثيق الشهادات الاحترافية': 'G5',
        'توثيق كفو': 'G6',
      };
      for (final opt in greenOptions) {
        requirements.add({
          'badge_type': 'green',
          'code': codeMap[opt] ?? 'G1',
        });
      }
    }

    if (selectedType == 'blue') {
      blueProfile = await _resolveBlueProfileForSubmission();
      if (blueProfile == null) {
        if (mounted) {
          setState(() => _isSending = false);
        }
        return;
      }
    }

    // 1) إنشاء الطلب
    final createRes = await VerificationService.createRequest(
      badgeType: badgeType,
      requirements: requirements,
      blueProfile: blueProfile,
    );

    if (!mounted) return;

    if (!createRes.isSuccess) {
      setState(() => _isSending = false);
      _showErrorSnackBar((createRes.error ?? 'فشل في إنشاء الطلب').trim());
      return;
    }

    final createPayload = Map<String, dynamic>.from(
      createRes.dataAsMap ?? const {},
    );
    final requestId = _toInt(createPayload['id']);
    if (requestId == null) {
      setState(() => _isSending = false);
      _showErrorSnackBar('تم استلام رد غير مكتمل من الخادم أثناء إنشاء الطلب.');
      return;
    }

    // 2) رفع المستندات
    if (uploadedFiles.isNotEmpty) {
      String docType;
      if (selectedType == 'blue') {
        if (blueOption == 'company') {
          docType = 'cr';
        } else {
          docType = 'id';
        }
      } else {
        docType = 'license';
      }

      for (final file in uploadedFiles) {
        final uploadRes = await VerificationService.uploadDocument(
          requestId: requestId,
          file: file,
          docType: docType,
        );
        if (!mounted) return;
        if (!uploadRes.isSuccess) {
          setState(() => _isSending = false);
          _showErrorSnackBar(
            (uploadRes.error ?? 'تم إنشاء الطلب لكن تعذر رفع أحد المرفقات.')
                .trim(),
          );
          return;
        }
      }
    }

    final detailRes = await VerificationService.fetchRequestDetail(requestId);
    if (!mounted) return;
    final requestSnapshot = detailRes.isSuccess && detailRes.dataAsMap != null
        ? Map<String, dynamic>.from(detailRes.dataAsMap!)
        : createPayload;

    if (!mounted) return;
    setState(() => _isSending = false);

    if (_requestNeedsPayment(requestSnapshot)) {
      final opened = await _startRequestPayment(requestSnapshot);
      if (!mounted) return;
      if (opened) return;
    }

    _showSuccess();
  }

  void _showSuccess() {
    final pricingNote = _selectedPricingHint();
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      AppColors.success.withValues(alpha: 0.7),
                      AppColors.success
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Icon(
                  Icons.verified,
                  color: Colors.white,
                  size: 52,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                "تم إرسال طلب التوثيق ✅",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: "Cairo",
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                pricingNote,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: "Cairo",
                  color: Colors.black54,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.deepPurple,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                  ),
                  child: const Text(
                    "حسناً",
                    style: TextStyle(
                      fontFamily: "Cairo",
                      fontSize: 15,
                      color: Colors.white,
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

  String _amountLabel() =>
      _priceLabelFor(selectedType == "green" ? "green" : "blue");
  double _amount() => _priceFor(selectedType == "green" ? "green" : "blue");

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4FC),
      appBar: const PlatformTopBar(
        pageLabel: 'طلب التوثيق',
        showBackButton: true,
        showNotificationAction: false,
        showChatAction: false,
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 4),
            _ProgressSteps(current: _currentStep),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(14, 4, 14, 0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 26,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _step1ChooseBadge(),
                      _step2Details(),
                      _step3Checkout(),
                    ],
                  ),
                ),
              ),
            ),
            _bottomBar(),
          ],
        ),
      ),
    );
  }

  // شريط الأزرار في الأسفل
  Widget _bottomBar() {
    final canNext = _canGoNext();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          if (_currentStep > 0)
            OutlinedButton.icon(
              onPressed: _isSending ? null : _prevStep,
              icon: const Icon(Icons.arrow_back_ios, size: 16),
              label: const Text("السابق"),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.deepPurple,
                side: BorderSide(color: AppColors.deepPurple),
                minimumSize: const Size(120, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          if (_currentStep > 0) const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: (canNext && !_isSending) ? _nextStep : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.deepPurple,
                disabledBackgroundColor:
                    AppColors.deepPurple.withValues(alpha: 0.25),
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isSending && _currentStep == 2)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  else ...[
                    Text(
                      _currentStep == 2 ? "إرسال الطلب" : "التالي",
                      style: const TextStyle(
                        fontFamily: "Cairo",
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      _currentStep == 2
                          ? Icons.check_circle_outline
                          : Icons.arrow_forward_ios_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // الخطوة 1 — اختيار نوع الشارة
  Widget _step1ChooseBadge() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "اختر نوع التوثيق المناسب لك",
            style: TextStyle(
              fontFamily: "Cairo",
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            "يمكنك توثيق هويتك أو اعتمادك المهني للحصول على ثقة أكبر لدى العملاء.",
            style: TextStyle(
              fontFamily: "Cairo",
              color: Colors.black54,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          _badgeCard(
            type: "blue",
            title: "التوثيق بالشارة الزرقاء",
            subtitle: "إثبات الهوية الشخصية أو السجل التجاري كمنشأة.",
            priceLabel: _priceLabelFor("blue"),
            color: Colors.blue,
            highlightLabel: "هوية / سجل تجاري",
            selected: selectedType == "blue",
            onTap: () => setState(() => selectedType = "blue"),
          ),
          const SizedBox(height: 12),
          _badgeCard(
            type: "green",
            title: "التوثيق بالشارة الخضراء",
            subtitle: "توثيق اعتمادك المهني وشهاداتك وخبراتك العملية.",
            priceLabel: _priceLabelFor("green"),
            color: Colors.green,
            highlightLabel: "اعتمادات مهنية",
            selected: selectedType == "green",
            onTap: () => setState(() => selectedType = "green"),
          ),
          const SizedBox(height: 8),
          if (selectedType != null)
            _infoHint(
              text: selectedType == "blue"
                  ? "اختر ما إذا كان التوثيق كفرد أو كيان تجاري، ثم أكمل البيانات المطلوبة."
                  : "اختر نوع الاعتمادات التي ترغب في توثيقها، ثم أرفق المستندات الداعمة.",
            ),
        ],
      ),
    );
  }

  // الخطوة 2 — تفاصيل حسب نوع الشارة
  Widget _step2Details() {
    if (selectedType == null) {
      return const Center(
        child: Text(
          "يرجى اختيار نوع الشارة أولاً من الخطوة السابقة.",
          style: TextStyle(fontFamily: "Cairo", color: Colors.black54),
        ),
      );
    }

    if (selectedType == "blue") return _blueForm();
    return _greenForm();
  }

  // نموذج الشارة الزرقاء — الخيارات تحت بعض (فرد / كيان تجاري / أوراق رسمية)
  Widget _blueForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "اختر نوع التوثيق بالشارة الزرقاء",
            style: TextStyle(
              fontFamily: "Cairo",
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),
          _optionChoiceCard(
            value: "person",
            groupValue: blueOption,
            title: "فرد",
            subtitle: "توثيق هوية شخصية لمستخدم واحد.",
            icon: Icons.person,
            onTap: () => setState(() => blueOption = "person"),
          ),
          const SizedBox(height: 10),
          _optionChoiceCard(
            value: "company",
            groupValue: blueOption,
            title: "كيان تجاري",
            subtitle: "شركة أو مؤسسة بسجل تجاري موثق.",
            icon: Icons.apartment,
            onTap: () => setState(() => blueOption = "company"),
          ),
          const SizedBox(height: 16),
          if (blueOption == "person" || blueOption == "company")
            Form(
              key: _formKeyBlue,
              child: Column(
                children: [
                  if (blueOption == "person") ...[
                    _inputField(
                      controller: _idCtrl,
                      label: "رقم الهوية / الإقامة",
                      icon: Icons.credit_card,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (v) => (v == null || v.trim().length < 8)
                          ? "يرجى إدخال رقم هوية صالح"
                          : null,
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () => _pickDateForController(
                        _dobCtrl,
                        firstDate: DateTime(1950),
                        lastDate: DateTime(DateTime.now().year - 10),
                      ),
                      child: AbsorbPointer(
                        child: _inputField(
                          controller: _dobCtrl,
                          label: "تاريخ الميلاد (YYYY-MM-DD)",
                          icon: Icons.calendar_today_outlined,
                          hint: "اختر من التقويم",
                          keyboardType: TextInputType.datetime,
                          validator: (v) => (v == null ||
                                  !RegExp(
                                    r'^\d{4}-\d{2}-\d{2}$',
                                  ).hasMatch(v))
                              ? "صيغة التاريخ غير صحيحة"
                              : null,
                        ),
                      ),
                    ),
                  ],
                  if (blueOption == "company") ...[
                    _inputField(
                      controller: _crCtrl,
                      label: "رقم السجل التجاري",
                      icon: Icons.business_center_outlined,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (v) => (v == null || v.trim().length < 5)
                          ? "يرجى إدخال رقم سجل صالح"
                          : null,
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () => _pickDateForController(
                        _crDateCtrl,
                        firstDate: DateTime(1970),
                        lastDate: DateTime.now(),
                      ),
                      child: AbsorbPointer(
                        child: _inputField(
                          controller: _crDateCtrl,
                          label: "تاريخ السجل (YYYY-MM-DD)",
                          icon: Icons.date_range_outlined,
                          hint: "اختر من التقويم",
                          keyboardType: TextInputType.datetime,
                          validator: (v) => (v == null ||
                                  !RegExp(
                                    r'^\d{4}-\d{2}-\d{2}$',
                                  ).hasMatch(v))
                              ? "صيغة التاريخ غير صحيحة"
                              : null,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          if (blueOption == "person" || blueOption == "company") ...[
            const SizedBox(height: 16),
            _filesSectionHeader(),
            const SizedBox(height: 6),
            _uploadBox(),
            const SizedBox(height: 6),
            _filesChips(),
          ],
          _infoHint(
            text:
                "للشارة الزرقاء يلزم إدخال بيانات الهوية للفرد أو السجل التجاري للمنشأة، مع إرفاق المستند الرسمي، حتى يتم اعتماد الاسم الرسمي قبل إرسال الطلب.",
          ),
        ],
      ),
    );
  }

  // كرت اختيار نوع التوثيق في الخطوة الثانية (تحت بعض)
  Widget _optionChoiceCard({
    required String value,
    required String? groupValue,
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final bool selected = value == groupValue;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.deepPurple.withValues(alpha: 0.06)
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.deepPurple : Colors.grey.shade300,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected
                    ? AppColors.deepPurple
                    : AppColors.deepPurple.withValues(alpha: 0.08),
              ),
              child: Icon(
                icon,
                color: selected ? Colors.white : AppColors.deepPurple,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: "Cairo",
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: selected ? AppColors.deepPurple : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: "Cairo",
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppColors.deepPurple : Colors.grey.shade400,
                  width: 2,
                ),
                color: selected ? AppColors.deepPurple : Colors.white,
              ),
              child: selected
                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  // نموذج الشارة الخضراء
  Widget _greenForm() {
    final options = [
      "توثيق الاعتماد المهني",
      "توثيق الرخص التنظيمية",
      "توثيق الخبرات العملية",
      "توثيق الدرجة العلمية والأكاديمية",
      "توثيق الشهادات الاحترافية",
      "توثيق كفو",
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "اختر العناصر التي ترغب في توثيقها",
            style: TextStyle(
              fontFamily: "Cairo",
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.map((opt) {
              final selected = greenOptions.contains(opt);
              return FilterChip(
                label: Text(
                  opt,
                  style: const TextStyle(fontFamily: "Cairo"),
                ),
                selected: selected,
                selectedColor: AppColors.deepPurple.withValues(alpha: 0.12),
                checkmarkColor: AppColors.deepPurple,
                side: BorderSide(
                  color: selected ? AppColors.deepPurple : Colors.grey.shade300,
                ),
                onSelected: (val) {
                  setState(() {
                    if (val) {
                      greenOptions.add(opt);
                    } else {
                      greenOptions.remove(opt);
                    }
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          _filesSectionHeader(),
          const SizedBox(height: 6),
          _uploadBox(),
          const SizedBox(height: 6),
          _filesChips(),
          const SizedBox(height: 8),
          _infoHint(
            text:
                "أرفق صور الشهادات أو التراخيص أو المستندات الداعمة لاعتماداتك.",
          ),
        ],
      ),
    );
  }

  // الخطوة 3 — مراجعة الطلب والرسوم
  Widget _step3Checkout() {
    final amount = _amount();
    final isBlue = selectedType == "blue";
    final pricingHint = _selectedPricingHint();
    final amountDisplay = _isFreeBadge(isBlue ? "blue" : "green")
        ? "مجاني ضمن الباقة"
        : "${_formatAmount(amount)} ر.س سنويًا";

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "مراجعة الطلب",
            style: TextStyle(
              fontFamily: "Cairo",
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            "تحقق من تفاصيل طلب التوثيق قبل إرساله للمراجعة.",
            style: TextStyle(fontFamily: "Cairo", color: Colors.black54),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 8,
            shadowColor: Colors.black12,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: isBlue
                                ? [
                                    Colors.blue.shade400,
                                    Colors.blue.shade700,
                                  ]
                                : [
                                    Colors.green.shade400,
                                    Colors.green.shade700,
                                  ],
                          ),
                        ),
                        padding: const EdgeInsets.all(9),
                        child: const Icon(
                          Icons.verified_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          isBlue
                              ? "التوثيق بالشارة الزرقاء"
                              : "التوثيق بالشارة الخضراء",
                          style: const TextStyle(
                            fontFamily: "Cairo",
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      Text(
                        amountDisplay,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepPurple,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Divider(),
                  const SizedBox(height: 8),
                  _kvRow("نوع الشارة", isBlue ? "زرقاء" : "خضراء"),
                  const SizedBox(height: 6),
                  if (isBlue && blueOption != null)
                    _kvRow(
                      "نوع التوثيق",
                      blueOption == "person"
                          ? "فرد"
                          : blueOption == "company"
                              ? "كيان تجاري"
                              : "أوراق رسمية",
                    ),
                  if (!isBlue)
                    _kvRow(
                      "عناصر مختارة",
                      greenOptions.isEmpty
                          ? "-"
                          : greenOptions.length.toString(),
                    ),
                  const SizedBox(height: 6),
                  _kvRow("عدد المرفقات", uploadedFiles.length.toString()),
                  const SizedBox(height: 12),
                  if (!isBlue && greenOptions.isNotEmpty) ...[
                    const Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        "تفاصيل العناصر:",
                        style: TextStyle(
                          fontFamily: "Cairo",
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: greenOptions
                            .map(
                              (e) => Chip(
                                label: Text(
                                  e,
                                  style: const TextStyle(
                                    fontFamily: "Cairo",
                                    fontSize: 11,
                                  ),
                                ),
                                backgroundColor: AppColors.deepPurple
                                    .withValues(alpha: 0.04),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.deepPurple.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      pricingHint,
                      style: const TextStyle(
                        fontFamily: "Cairo",
                        color: Colors.black54,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            "آلية التفعيل",
            style: TextStyle(
              fontFamily: "Cairo",
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 3,
            shadowColor: Colors.black12,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _isFreeBadge(isBlue ? "blue" : "green")
                            ? Icons.verified_outlined
                            : Icons.receipt_long_outlined,
                        color: AppColors.deepPurple,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isFreeBadge(isBlue ? "blue" : "green")
                            ? "لا توجد رسوم عند الاعتماد"
                            : "الفاتورة تصدر بعد الاعتماد",
                        style: const TextStyle(
                          fontFamily: "Cairo",
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    pricingHint,
                    style: const TextStyle(
                      fontFamily: "Cairo",
                      color: Colors.black54,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: Text(
              "الرسوم السنوية النهائية: $amountDisplay",
              style: const TextStyle(
                fontFamily: "Cairo",
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              _amountLabel(),
              style: const TextStyle(
                fontFamily: "Cairo",
                color: Colors.black45,
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  // بطاقة اختيار الشارة (اسم + سعر في سطر، وصف تحت، بدون تداخل)
  Widget _badgeCard({
    required String type,
    required String title,
    required String subtitle,
    required String priceLabel,
    required MaterialColor color,
    required String highlightLabel,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: selected
              ? LinearGradient(
                  colors: [
                    color.withValues(alpha: 0.10),
                    color.withValues(alpha: 0.02)
                  ],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                )
              : null,
          color: selected ? null : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color:
                selected ? color.withValues(alpha: 0.55) : Colors.grey.shade200,
            width: selected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: selected ? 0.08 : 0.03),
              blurRadius: selected ? 18 : 10,
              spreadRadius: 1,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: color.withValues(alpha: 0.12),
              child: Icon(Icons.verified, color: color, size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // سطر العنوان + السعر
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: "Cairo",
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: type == "blue"
                                ? Colors.blue.shade700
                                : Colors.green.shade700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        priceLabel,
                        style: const TextStyle(
                          fontFamily: "Cairo",
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Colors.black54,
                      height: 1.4,
                      fontFamily: "Cairo",
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      highlightLabel,
                      style: TextStyle(
                        fontFamily: "Cairo",
                        fontSize: 10.5,
                        color: color.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // عنصر إدخال موحد
  Widget _inputField({
    required String label,
    required IconData icon,
    TextEditingController? controller,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? hint,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: AppColors.deepPurple),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.deepPurple, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.red),
        ),
      ),
      style: const TextStyle(fontFamily: "Cairo"),
    );
  }

  Widget _filesSectionHeader() {
    return Row(
      children: const [
        Icon(Icons.cloud_upload_outlined, color: Colors.deepPurple),
        SizedBox(width: 8),
        Text(
          "المرفقات",
          style: TextStyle(fontFamily: "Cairo", fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  // صندوق الرفع
  Widget _uploadBox() {
    return GestureDetector(
      onTap: _pickFile,
      child: Container(
        height: 122,
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300, width: 1.6),
          borderRadius: BorderRadius.circular(18),
          color: Colors.white,
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.drive_folder_upload,
                size: 40,
                color: Colors.deepPurple,
              ),
              SizedBox(height: 6),
              Text(
                "اضغط هنا لرفع الملفات",
                style: TextStyle(
                  fontFamily: "Cairo",
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
              SizedBox(height: 2),
              Text(
                "صور الهويات، السجلات، الشهادات...",
                style: TextStyle(
                  fontFamily: "Cairo",
                  fontSize: 11,
                  color: Colors.black45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // عرض المرفقات Chips
  Widget _filesChips() {
    if (uploadedFiles.isEmpty) {
      return Align(
        alignment: Alignment.centerRight,
        child: Text(
          "لم تُرفق ملفات بعد.",
          style: TextStyle(fontFamily: "Cairo", color: Colors.grey.shade600),
        ),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (int i = 0; i < uploadedFiles.length; i++)
          Chip(
            label: Text(
              "ملف ${i + 1}",
              style: const TextStyle(fontFamily: "Cairo"),
            ),
            deleteIcon: const Icon(Icons.close, size: 18),
            onDeleted: () => setState(() => uploadedFiles.removeAt(i)),
            backgroundColor: Colors.grey.shade100,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
      ],
    );
  }

  // صف مفتاح / قيمة
  Widget _kvRow(String k, String v) {
    return Row(
      children: [
        Text(
          k,
          style: const TextStyle(fontFamily: "Cairo", color: Colors.black54),
        ),
        const Spacer(),
        Text(
          v,
          style: const TextStyle(
            fontFamily: "Cairo",
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // تلميح معلوماتي
  Widget _infoHint({required String text}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.deepPurple.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.deepPurple.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: AppColors.deepPurple, size: 19),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontFamily: "Cairo",
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// مؤشّر التقدّم العلوي (3 خطوات) بتصميم حديث
class _ProgressSteps extends StatelessWidget {
  final int current;
  const _ProgressSteps({required this.current});

  @override
  Widget build(BuildContext context) {
    const steps = ["اختيار الشارة", "التفاصيل", "المراجعة"];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      child: Row(
        children: List.generate(3, (index) {
          final isActive = index <= current;
          return Expanded(
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor:
                          isActive ? AppColors.deepPurple : Colors.grey[300],
                      child: Text(
                        "${index + 1}",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontFamily: "Cairo",
                        ),
                      ),
                    ),
                    if (index < 2)
                      Expanded(
                        child: Container(
                          height: 3,
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isActive
                                  ? [
                                      AppColors.deepPurple,
                                      AppColors.deepPurple
                                          .withValues(alpha: 0.4),
                                    ]
                                  : [
                                      Colors.grey.shade300,
                                      Colors.grey.shade300,
                                    ],
                            ),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  steps[index],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: "Cairo",
                    fontSize: 11,
                    color:
                        isActive ? AppColors.deepPurple : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}
