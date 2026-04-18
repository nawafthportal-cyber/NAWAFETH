import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../services/home_service.dart';
import '../services/marketplace_service.dart';
import '../services/account_mode_service.dart';
import '../models/category_model.dart';
import '../constants/saudi_cities.dart';
import '../widgets/bottom_nav.dart';

class RequestQuoteScreen extends StatefulWidget {
  const RequestQuoteScreen({super.key});

  @override
  State<RequestQuoteScreen> createState() => _RequestQuoteScreenState();
}

class _RequestQuoteScreenState extends State<RequestQuoteScreen>
    with SingleTickerProviderStateMixin {
  static const Color _mainColor = Color(0xFF0F766E);
  static const Color _inkColor = Color(0xFF0F172A);
  final _titleCtrl = TextEditingController();
  final _detailsCtrl = TextEditingController();
  late final AnimationController _entranceController;

  // ── API data ──
  List<CategoryModel> _categories = [];
  bool _loadingCats = true;
  bool _accountChecked = false;
  bool _isProviderMode = false;

  // ── Form state ──
  CategoryModel? _selectedCat;
  SubCategoryModel? _selectedSub;
  String? _selectedRegion;
  String? _selectedCity;
  DateTime? _deadline;
  bool _submitting = false;
  bool _showSuccess = false;

  // ── Attachments ──
  final List<File> _files = [];

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _ensureClientMode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _entranceController.forward();
      }
    });
  }

  Future<void> _ensureClientMode() async {
    final isProvider = await AccountModeService.isProviderMode();
    if (!mounted) return;
    setState(() {
      _isProviderMode = isProvider;
      _accountChecked = true;
    });

    if (_isProviderMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/profile');
      });
      return;
    }

    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final cats = await HomeService.fetchCategories();
      if (mounted) setState(() { _categories = cats; _loadingCats = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingCats = false);
    }
  }

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final picks = await picker.pickMultiImage(imageQuality: 80);
    if (picks.isNotEmpty && mounted) {
      setState(() => _files.addAll(picks.map((x) => File(x.path))));
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: true);
    if (result != null && mounted) {
      setState(() => _files.addAll(result.files.where((f) => f.path != null).map((f) => File(f.path!))));
    }
  }

  Future<void> _pickDeadline() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 2)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      locale: const Locale('ar', 'SA'),
    );
    if (picked != null && mounted) setState(() => _deadline = picked);
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    final details = _detailsCtrl.text.trim();

    if (_selectedSub == null) { _snack('اختر التصنيف الفرعي'); return; }
    if (title.isEmpty) { _snack('أدخل عنوان الطلب'); return; }
    if (details.isEmpty) { _snack('أدخل تفاصيل الطلب'); return; }

    setState(() => _submitting = true);

    final res = await MarketplaceService.createRequest(
      title: title,
      description: details,
      requestType: 'competitive',
      subcategory: _selectedSub!.id,
      city: _selectedScopedCity.isEmpty ? null : _selectedScopedCity,
      quoteDeadline: _deadline != null ? DateFormat('yyyy-MM-dd').format(_deadline!) : null,
      files: _files,
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (res.isSuccess) {
      setState(() => _showSuccess = true);
    } else {
      _snack(res.error ?? 'فشل إرسال الطلب');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg, style: const TextStyle(fontFamily: 'Cairo', fontSize: 11)),
          backgroundColor: Colors.red.shade700, behavior: SnackBarBehavior.floating),
    );
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _detailsCtrl.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
        backgroundColor: isDark ? const Color(0xFF0B1A1A) : const Color(0xFFF4FBFA),
        bottomNavigationBar: const CustomBottomNav(currentIndex: 2),
        body: SafeArea(
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  gradient: isDark
                      ? const LinearGradient(
                          colors: [Color(0xFF0B1A1A), Color(0xFF102928), Color(0xFF153331)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        )
                      : const LinearGradient(
                          colors: [Color(0xFFEFFCF8), Color(0xFFF7FFFD), Color(0xFFFFFFFF)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: AbsorbPointer(
                        absorbing: _showSuccess,
                        child: Opacity(
                          opacity: _showSuccess ? 0.25 : 1,
                          child: _loadingCats
                              ? const Center(
                                  child: CircularProgressIndicator(
                                    color: _mainColor,
                                    strokeWidth: 2,
                                  ),
                                )
                              : SingleChildScrollView(
                                  physics: const BouncingScrollPhysics(),
                                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                                  child: _form(isDark),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_showSuccess) _successOverlay(isDark),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════
  //  HEADER
  // ═══════════════════════════════════════

  Widget _form(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildEntrance(0, _heroCard()),
        const SizedBox(height: 12),
        _buildEntrance(
          1,
          _sectionCard(
            icon: Icons.category_outlined,
            title: 'تصنيف الطلب',
            description: 'حدد المجال المناسب حتى تصل عروض الأسعار إلى مزودين مطابقين للخدمة المطلوبة.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label('التصنيف الرئيسي', isDark),
                const SizedBox(height: 6),
                _dropdownWidget<CategoryModel>(
                  isDark: isDark,
                  hint: 'اختر التصنيف',
                  value: _selectedCat,
                  items: _categories,
                  labelFn: (c) => c.name,
                  onChanged: (c) => setState(() {
                    _selectedCat = c;
                    _selectedSub = null;
                  }),
                ),
                const SizedBox(height: 14),
                _label('التصنيف الفرعي', isDark),
                const SizedBox(height: 6),
                _dropdownWidget<SubCategoryModel>(
                  isDark: isDark,
                  hint: 'اختر الفرعي',
                  value: _selectedSub,
                  items: _selectedCat?.subcategories ?? [],
                  labelFn: (s) => s.name,
                  onChanged: (s) => setState(() => _selectedSub = s),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildEntrance(
          2,
          _sectionCard(
            icon: Icons.article_outlined,
            title: 'تفاصيل العرض',
            description: 'أدخل عنوانًا واضحًا ووصفًا دقيقًا لرفع جودة العروض التي ستصلك.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label('عنوان الطلب', isDark),
                const SizedBox(height: 6),
                _textInput(_titleCtrl, 'أدخل عنوان الطلب', 1, 80, isDark),
                const SizedBox(height: 14),
                _label('تفاصيل الطلب', isDark),
                const SizedBox(height: 6),
                _textInput(_detailsCtrl, 'اشرح ما تحتاجه بالتفصيل...', 4, 500, isDark),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildEntrance(
          3,
          _sectionCard(
            icon: Icons.place_outlined,
            title: 'المدينة والموعد النهائي',
            description: 'حدد المدينة إن رغبت، واختر آخر موعد مناسب لاستلام عروض الأسعار.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label('المنطقة الإدارية والمدينة', isDark),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: _dropdownWidget<SaudiRegionCatalogEntry>(
                        isDark: isDark,
                        hint: 'اختر المنطقة الإدارية',
                        value: _activeRegion,
                        items: SaudiCities.regionCatalogFallback,
                        labelFn: (region) => region.displayName,
                        onChanged: (region) {
                          setState(() {
                            _selectedRegion = region?.nameAr;
                            _selectedCity = null;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _dropdownWidget<String>(
                        isDark: isDark,
                        hint: 'اختر المدينة (اختياري)',
                        value: _selectedCity,
                        items: _availableCities,
                        labelFn: (city) => city,
                        onChanged: (city) => setState(() => _selectedCity = city),
                      ),
                    ),
                  ],
                ),
                if (_selectedScopedCity.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() {
                        _selectedRegion = null;
                        _selectedCity = null;
                      }),
                      icon: const Icon(Icons.location_off_outlined, size: 14),
                      label: const Text(
                        'إلغاء المدينة (إرسال لجميع المدن)',
                        style: TextStyle(fontSize: 10.5, fontFamily: 'Cairo'),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: _mainColor,
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                _label('آخر موعد لاستلام العروض', isDark),
                const SizedBox(height: 6),
                _deadlineTile(isDark),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildEntrance(
          4,
          _sectionCard(
            icon: Icons.attach_file_rounded,
            title: 'المرفقات',
            description: 'أرفق صورًا أو ملفات مرجعية لتوضيح النطاق وتسريع وصول عروض أدق.',
            child: _attachmentsPanel(isDark),
          ),
        ),
        const SizedBox(height: 14),
        _buildEntrance(5, _buildActions(isDark)),
      ],
    );
  }

  // ═══════════════════════════════════════
  //  SUCCESS OVERLAY
  // ═══════════════════════════════════════

  Widget _successOverlay(bool isDark) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 28),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 20)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded, size: 48, color: Colors.green),
            const SizedBox(height: 12),
            Text('تم إرسال الطلب بنجاح!', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                fontFamily: 'Cairo', color: isDark ? Colors.white : Colors.black87)),
            const SizedBox(height: 6),
            Text('ستتلقى العروض قريبًا في قسم طلباتي.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, fontFamily: 'Cairo',
                    color: isDark ? Colors.white54 : Colors.black45)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: _mainColor, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                elevation: 0,
              ),
              child: const Text('العودة', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, fontFamily: 'Cairo')),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════
  //  HELPERS
  // ═══════════════════════════════════════

  Widget _label(String text, bool isDark) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w900,
        fontFamily: 'Cairo',
        color: isDark ? Colors.white70 : _inkColor,
      ),
    );
  }

  SaudiRegionCatalogEntry? get _activeRegion {
    return SaudiCities.findRegionEntry(_selectedRegion);
  }

  List<String> get _availableCities => _activeRegion?.cities ?? const [];

  String get _selectedScopedCity {
    return SaudiCities.normalizeScopedCity(_selectedCity, region: _selectedRegion);
  }

  Widget _dropdownWidget<T>({
    required bool isDark,
    required String hint,
    required T? value,
    required List<T> items,
    required String Function(T) labelFn,
    required void Function(T?) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF5FCFB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFD0E7E4)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          hint: Text(hint, style: TextStyle(fontSize: 11, fontFamily: 'Cairo',
              color: isDark ? Colors.white38 : Colors.grey.shade400)),
          icon: Icon(Icons.arrow_drop_down, color: isDark ? Colors.white38 : Colors.grey),
          dropdownColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
          style: TextStyle(fontSize: 11, fontFamily: 'Cairo',
              color: isDark ? Colors.white : Colors.black87),
          items: items.map((e) => DropdownMenuItem<T>(
            value: e,
            child: Text(labelFn(e)),
          )).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _textInput(TextEditingController ctrl, String hint, int lines, int maxLen, bool isDark) {
    return TextField(
      controller: ctrl,
      maxLines: lines,
      maxLength: maxLen,
      style: TextStyle(fontSize: 11, fontFamily: 'Cairo', color: isDark ? Colors.white : Colors.black87),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: 10, fontFamily: 'Cairo',
            color: isDark ? Colors.white30 : Colors.grey.shade400),
        filled: true,
        fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF5FCFB),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: isDark ? Colors.white12 : const Color(0xFFD0E7E4)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: isDark ? Colors.white12 : const Color(0xFFD0E7E4)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: _mainColor),
        ),
        contentPadding: const EdgeInsets.all(12),
        counterStyle: TextStyle(fontSize: 9, fontFamily: 'Cairo',
            color: isDark ? Colors.white30 : Colors.grey.shade400),
      ),
    );
  }

  Widget _attachBtn(IconData icon, String label, VoidCallback onTap, bool isDark) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : _mainColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isDark ? Colors.white12 : _mainColor.withValues(alpha: 0.12)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: _mainColor),
            const SizedBox(width: 5),
            Text(label, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, fontFamily: 'Cairo', color: _mainColor)),
          ],
        ),
      ),
    );
  }

  Widget _heroCard() {
    final categoryLabel = _selectedCat?.name ?? 'اختر التصنيف المناسب';
    final deadlineLabel = _deadline != null ? DateFormat('yyyy/MM/dd').format(_deadline!) : 'بدون موعد نهائي';
    final cityLabel = _selectedScopedCity.isEmpty ? 'جميع المدن' : _selectedScopedCity;

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
            color: const Color(0xFF115E59).withValues(alpha: 0.20),
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
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'طلب عروض أسعار',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'ابنِ طلبًا واضحًا مع موعد نهائي مناسب لتلقي عروض أدق وبشكل منظم.',
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
                  const Icon(Icons.request_quote_rounded, size: 22, color: Colors.white),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _heroChip(Icons.category_outlined, categoryLabel),
                  _heroChip(Icons.place_outlined, cityLabel),
                  _heroChip(Icons.calendar_month_outlined, deadlineLabel),
                  _heroChip(Icons.attach_file_rounded, '${_files.length} مرفقات'),
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

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required String description,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0x2214B8A6)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF115E59).withValues(alpha: 0.06),
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
                  color: _mainColor.withValues(alpha: 0.10),
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
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: _inkColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        height: 1.8,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF667085),
                      ),
                    ),
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

  Widget _deadlineTile(bool isDark) {
    return InkWell(
      onTap: _pickDeadline,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF5FCFB),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFD0E7E4)),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _mainColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.calendar_today_rounded, size: 16, color: _mainColor),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _deadline != null ? DateFormat('yyyy/MM/dd').format(_deadline!) : 'اختر التاريخ',
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w800,
                      color: _deadline != null
                          ? (isDark ? Colors.white : _inkColor)
                          : (isDark ? Colors.white38 : Colors.grey.shade500),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'آخر يوم لاستقبال العروض على هذا الطلب',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white54 : const Color(0xFF667085),
                    ),
                  ),
                ],
              ),
            ),
            if (_deadline != null)
              IconButton(
                onPressed: () => setState(() => _deadline = null),
                icon: const Icon(Icons.close_rounded, size: 18),
                color: const Color(0xFFB42318),
              ),
          ],
        ),
      ),
    );
  }

  Widget _attachmentsPanel(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _attachBtn(Icons.camera_alt_rounded, 'صورة', _pickImages, isDark),
            _attachBtn(Icons.attach_file_rounded, 'ملف', _pickFile, isDark),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF5FCFB),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFD0E7E4)),
          ),
          child: _files.isEmpty
              ? const Column(
                  children: [
                    Icon(Icons.inventory_2_outlined, color: _mainColor, size: 26),
                    SizedBox(height: 8),
                    Text(
                      'لا توجد مرفقات مضافة حتى الآن',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: _inkColor,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'أضف ملفات أو صور مرجعية إذا كانت ستساعد المزودين على تسعير أدق.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF667085),
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'المرفقات المضافة',
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(_files.length, (i) {
                        final file = _files[i];
                        final isImage = _isImageFile(file.path);
                        return Stack(
                          children: [
                            Container(
                              width: 76,
                              height: 76,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                color: Colors.white,
                                image: isImage
                                    ? DecorationImage(
                                        image: FileImage(file),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                              ),
                              child: isImage
                                  ? null
                                  : Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.insert_drive_file_rounded, size: 22, color: _mainColor),
                                        const SizedBox(height: 4),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 6),
                                          child: Text(
                                            _fileName(file.path),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.w700,
                                              color: _inkColor,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                            Positioned(
                              top: 4,
                              left: 4,
                              child: GestureDetector(
                                onTap: () => setState(() => _files.removeAt(i)),
                                child: Container(
                                  width: 20,
                                  height: 20,
                                  decoration: const BoxDecoration(color: Color(0xFFB42318), shape: BoxShape.circle),
                                  child: const Icon(Icons.close, size: 12, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        );
                      }),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildActions(bool isDark) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              side: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300),
              backgroundColor: Colors.white.withValues(alpha: 0.9),
            ),
            child: Text('إلغاء', style: TextStyle(fontSize: 12, fontFamily: 'Cairo', color: isDark ? Colors.white60 : Colors.black54, fontWeight: FontWeight.w800)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: ElevatedButton(
            onPressed: _submitting ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: _mainColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              elevation: 0,
            ),
            child: _submitting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.send_rounded, size: 16),
                      SizedBox(width: 6),
                      Text('تقديم الطلب', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, fontFamily: 'Cairo')),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  bool _isImageFile(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png') || lower.endsWith('.webp');
  }

  String _fileName(String path) => path.split(Platform.pathSeparator).last;

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
}
