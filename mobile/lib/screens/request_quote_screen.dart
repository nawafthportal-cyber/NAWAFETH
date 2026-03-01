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

class _RequestQuoteScreenState extends State<RequestQuoteScreen> {
  final _titleCtrl = TextEditingController();
  final _detailsCtrl = TextEditingController();

  // ── API data ──
  List<CategoryModel> _categories = [];
  bool _loadingCats = true;
  bool _accountChecked = false;
  bool _isProviderMode = false;

  // ── Form state ──
  CategoryModel? _selectedCat;
  SubCategoryModel? _selectedSub;
  String? _selectedCity;
  DateTime? _deadline;
  bool _submitting = false;
  bool _showSuccess = false;

  // ── Attachments ──
  final List<File> _files = [];

  @override
  void initState() {
    super.initState();
    _ensureClientMode();
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
    if ((_selectedCity ?? '').isEmpty) { _snack('اختر المدينة'); return; }
    if (title.isEmpty) { _snack('أدخل عنوان الطلب'); return; }
    if (details.isEmpty) { _snack('أدخل تفاصيل الطلب'); return; }

    setState(() => _submitting = true);

    final res = await MarketplaceService.createRequest(
      title: title,
      description: details,
      requestType: 'competitive',
      subcategory: _selectedSub!.id,
      city: _selectedCity,
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
    super.dispose();
  }

  // ═══════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const purple = Colors.deepPurple;

    if (!_accountChecked) {
      return const Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Center(
            child: CircularProgressIndicator(color: Colors.deepPurple),
          ),
        ),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF5F5FA),
        bottomNavigationBar: const CustomBottomNav(currentIndex: 2),
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _header(isDark, purple),
                  Expanded(
                    child: AbsorbPointer(
                      absorbing: _showSuccess,
                      child: Opacity(
                        opacity: _showSuccess ? 0.25 : 1,
                        child: _loadingCats
                            ? const Center(child: CircularProgressIndicator(color: Colors.deepPurple, strokeWidth: 2))
                            : SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                                child: _form(isDark, purple),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
              if (_showSuccess) _successOverlay(isDark, purple),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════
  //  HEADER
  // ═══════════════════════════════════════

  Widget _header(bool isDark, Color purple) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.08) : purple.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.arrow_forward_ios_rounded, size: 16, color: isDark ? Colors.white70 : purple),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text('طلب عروض أسعار',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, fontFamily: 'Cairo',
                    color: isDark ? Colors.white : Colors.black87)),
          ),
          Icon(Icons.request_quote_rounded, size: 18, color: purple),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  //  FORM
  // ═══════════════════════════════════════

  Widget _form(bool isDark, Color purple) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Main category ──
        _label('التصنيف الرئيسي', isDark),
        const SizedBox(height: 6),
        _dropdownWidget<CategoryModel>(
          isDark: isDark,
          hint: 'اختر التصنيف',
          value: _selectedCat,
          items: _categories,
          labelFn: (c) => c.name,
          onChanged: (c) => setState(() { _selectedCat = c; _selectedSub = null; }),
        ),

        const SizedBox(height: 14),

        // ── Sub category ──
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

        const SizedBox(height: 14),

        _label('المدينة', isDark),
        const SizedBox(height: 6),
        _dropdownWidget<String>(
          isDark: isDark,
          hint: 'اختر المدينة',
          value: _selectedCity,
          items: SaudiCities.all,
          labelFn: (city) => city,
          onChanged: (city) => setState(() => _selectedCity = city),
        ),

        const SizedBox(height: 14),

        // ── Title ──
        _label('عنوان الطلب', isDark),
        const SizedBox(height: 6),
        _textInput(_titleCtrl, 'أدخل عنوان الطلب', 1, 80, isDark),

        const SizedBox(height: 14),

        // ── Details ──
        _label('تفاصيل الطلب', isDark),
        const SizedBox(height: 6),
        _textInput(_detailsCtrl, 'اشرح ما تحتاجه بالتفصيل...', 4, 500, isDark),

        const SizedBox(height: 14),

        // ── Attachments ──
        _label('المرفقات (اختياري)', isDark),
        const SizedBox(height: 6),
        Row(
          children: [
            _attachBtn(Icons.camera_alt_rounded, 'صورة', _pickImages, isDark, purple),
            const SizedBox(width: 8),
            _attachBtn(Icons.attach_file_rounded, 'ملف', _pickFile, isDark, purple),
          ],
        ),
        if (_files.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 50,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _files.length,
              itemBuilder: (_, i) {
                final isImage = _files[i].path.endsWith('.jpg') ||
                    _files[i].path.endsWith('.jpeg') ||
                    _files[i].path.endsWith('.png');
                return Stack(
                  children: [
                    Container(
                      width: 50, height: 50,
                      margin: const EdgeInsets.only(left: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade100,
                        image: isImage ? DecorationImage(image: FileImage(_files[i]), fit: BoxFit.cover) : null,
                      ),
                      child: isImage ? null : Icon(Icons.insert_drive_file_rounded, size: 20,
                          color: isDark ? Colors.white38 : Colors.grey),
                    ),
                    Positioned(top: 0, left: 6, child: GestureDetector(
                      onTap: () => setState(() => _files.removeAt(i)),
                      child: Container(
                        width: 16, height: 16,
                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                        child: const Icon(Icons.close, size: 10, color: Colors.white),
                      ),
                    )),
                  ],
                );
              },
            ),
          ),
        ],

        const SizedBox(height: 14),

        // ── Deadline ──
        _label('آخر موعد لاستلام العروض', isDark),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: _pickDeadline,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today_rounded, size: 16,
                    color: isDark ? Colors.white38 : purple),
                const SizedBox(width: 8),
                Text(
                  _deadline != null
                      ? DateFormat('yyyy/MM/dd').format(_deadline!)
                      : 'اختر التاريخ',
                  style: TextStyle(fontSize: 11, fontFamily: 'Cairo',
                      color: _deadline != null
                          ? (isDark ? Colors.white : Colors.black87)
                          : (isDark ? Colors.white38 : Colors.grey.shade400)),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),

        // ── Submit ──
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  side: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300),
                ),
                child: Text('إلغاء', style: TextStyle(fontSize: 11, fontFamily: 'Cairo',
                    color: isDark ? Colors.white60 : Colors.black54)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: purple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                child: _submitting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.send_rounded, size: 14),
                          const SizedBox(width: 6),
                          Text('تقديم الطلب', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, fontFamily: 'Cairo')),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ═══════════════════════════════════════
  //  SUCCESS OVERLAY
  // ═══════════════════════════════════════

  Widget _successOverlay(bool isDark, Color purple) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 28),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
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
                backgroundColor: purple, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
    return Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, fontFamily: 'Cairo',
        color: isDark ? Colors.white70 : Colors.black87));
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
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
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
        fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.deepPurple),
        ),
        contentPadding: const EdgeInsets.all(12),
        counterStyle: TextStyle(fontSize: 9, fontFamily: 'Cairo',
            color: isDark ? Colors.white30 : Colors.grey.shade400),
      ),
    );
  }

  Widget _attachBtn(IconData icon, String label, VoidCallback onTap, bool isDark, Color purple) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : purple.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isDark ? Colors.white12 : purple.withValues(alpha: 0.12)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: purple),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, fontFamily: 'Cairo', color: purple)),
          ],
        ),
      ),
    );
  }
}
