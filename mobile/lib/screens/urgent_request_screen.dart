import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../services/home_service.dart';
import '../services/marketplace_service.dart';
import '../services/account_mode_service.dart';
import '../models/category_model.dart';
import '../constants/saudi_cities.dart';
import '../widgets/bottom_nav.dart';

class UrgentRequestScreen extends StatefulWidget {
  const UrgentRequestScreen({super.key});

  @override
  State<UrgentRequestScreen> createState() => _UrgentRequestScreenState();
}

class _UrgentRequestScreenState extends State<UrgentRequestScreen> {
  static const Set<String> _imageExts = {
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'bmp',
    'heic',
    'heif',
  };
  static const Set<String> _videoExts = {
    'mp4',
    'mov',
    'avi',
    'mkv',
    'webm',
    'm4v',
    '3gp',
    'wmv',
  };
  static const Set<String> _audioExts = {
    'mp3',
    'wav',
    'aac',
    'm4a',
    'ogg',
    'flac',
    'amr',
    'opus',
    'wma',
  };

  final _descCtrl = TextEditingController();

  // ── API data ──
  List<CategoryModel> _categories = [];
  bool _loadingCats = true;
  bool _accountChecked = false;
  bool _isProviderMode = false;

  // ── Form state ──
  CategoryModel? _selectedCat;
  SubCategoryModel? _selectedSub;
  String? _selectedCity;
  String _dispatchMode = 'all'; // 'all' | 'nearest'
  bool _submitting = false;
  bool _showSuccess = false;

  // ── Attachments ──
  final List<File> _images = [];
  final List<File> _videos = [];
  final List<File> _files = [];
  File? _audio;

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
      setState(() => _images.addAll(picks.map((x) => File(x.path))));
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: true,
    );
    if (result == null || !mounted) return;

    var added = 0;
    var replacedAudio = false;

    setState(() {
      for (final picked in result.files) {
        final path = picked.path;
        if (path == null || path.isEmpty) continue;
        if (_isAlreadyAttached(path)) continue;

        final file = File(path);
        final ext = _extractExt(picked.name.isNotEmpty ? picked.name : path);

        if (_imageExts.contains(ext)) {
          _images.add(file);
          added++;
          continue;
        }
        if (_videoExts.contains(ext)) {
          _videos.add(file);
          added++;
          continue;
        }
        if (_audioExts.contains(ext)) {
          _audio = file;
          replacedAudio = true;
          added++;
          continue;
        }
        _files.add(file);
        added++;
      }
    });

    if (added == 0) {
      _snack('لم يتم إضافة مرفقات جديدة');
      return;
    }
    if (replacedAudio) {
      _snack('تم تحديث المرفق الصوتي مع إضافة بقية المرفقات');
    }
  }

  Future<void> _submit() async {
    if (_selectedSub == null) {
      _snack('اختر التصنيف الفرعي');
      return;
    }
    final desc = _descCtrl.text.trim();
    if (desc.isEmpty) {
      _snack('أدخل وصفًا للخدمة');
      return;
    }
    if (_dispatchMode == 'nearest' && (_selectedCity ?? '').isEmpty) {
      _snack('اختر المدينة عند البحث عن الأقرب');
      return;
    }

    setState(() => _submitting = true);
    final res = await MarketplaceService.createRequest(
      title: 'طلب عاجل - ${_selectedCat?.name ?? ''}',
      description: desc,
      requestType: 'urgent',
      subcategory: _selectedSub!.id,
      city: _selectedCity,
      dispatchMode: _dispatchMode,
      images: _images,
      videos: _videos,
      files: _files,
      audio: _audio,
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
    _descCtrl.dispose();
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
            child: Text('طلب خدمة عاجلة',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, fontFamily: 'Cairo',
                    color: isDark ? Colors.white : Colors.black87)),
          ),
          Icon(Icons.bolt_rounded, size: 18, color: Colors.orange.shade700),
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
        _dropdown<CategoryModel>(
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
        _dropdown<SubCategoryModel>(
          isDark: isDark,
          hint: 'اختر الفرعي',
          value: _selectedSub,
          items: _selectedCat?.subcategories ?? [],
          labelFn: (s) => s.name,
          onChanged: (s) => setState(() => _selectedSub = s),
        ),

        const SizedBox(height: 14),

        // ── Dispatch mode ──
        _label('طريقة الإرسال', isDark),
        const SizedBox(height: 6),
        Row(
          children: [
            _radioChip('البحث عن الأقرب', 'nearest', isDark, purple),
            const SizedBox(width: 8),
            _radioChip('إرسال للجميع', 'all', isDark, purple),
          ],
        ),

        const SizedBox(height: 14),

        _label('المدينة', isDark),
        const SizedBox(height: 6),
        _dropdown<String>(
          isDark: isDark,
          hint: _dispatchMode == 'nearest'
              ? 'اختر المدينة (إلزامي)'
              : 'اختر المدينة (اختياري)',
          value: _selectedCity,
          items: SaudiCities.all,
          labelFn: (city) => city,
          onChanged: (city) => setState(() => _selectedCity = city),
        ),
        if (_dispatchMode == 'all' && _selectedCity != null) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _selectedCity = null),
              icon: const Icon(Icons.location_off_outlined, size: 14),
              label: const Text(
                'إلغاء المدينة (إرسال لجميع المدن)',
                style: TextStyle(fontSize: 10, fontFamily: 'Cairo'),
              ),
              style: TextButton.styleFrom(
                foregroundColor: purple,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],

        const SizedBox(height: 14),

        // ── Description ──
        _label('وصف الخدمة المطلوبة', isDark),
        const SizedBox(height: 6),
        _textField(isDark),

        const SizedBox(height: 14),

        // ── Attachments ──
        _label('المرفقات (اختياري)', isDark),
        const SizedBox(height: 6),
        Row(
          children: [
            _attachBtn(Icons.camera_alt_rounded, 'صورة', _pickImages, isDark, purple),
            const SizedBox(width: 8),
            _attachBtn(Icons.attach_file_rounded, 'ملف/وسائط', _pickFile, isDark, purple),
          ],
        ),
        if (_images.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 50,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _images.length,
              itemBuilder: (_, i) => Stack(
                children: [
                  Container(
                    width: 50, height: 50,
                    margin: const EdgeInsets.only(left: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      image: DecorationImage(image: FileImage(_images[i]), fit: BoxFit.cover),
                    ),
                  ),
                  Positioned(top: 0, left: 6, child: GestureDetector(
                    onTap: () => setState(() => _images.removeAt(i)),
                    child: Container(
                      width: 16, height: 16,
                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                      child: const Icon(Icons.close, size: 10, color: Colors.white),
                    ),
                  )),
                ],
              ),
            ),
          ),
        ],
        if (_videos.isNotEmpty || _files.isNotEmpty || _audio != null) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ..._videos.map((v) => _attachmentRow(
                      icon: Icons.video_file_outlined,
                      name: _fileName(v.path),
                      onRemove: () => setState(() => _videos.remove(v)),
                      isDark: isDark,
                    )),
                ..._files.map((f) => _attachmentRow(
                      icon: Icons.insert_drive_file_outlined,
                      name: _fileName(f.path),
                      onRemove: () => setState(() => _files.remove(f)),
                      isDark: isDark,
                    )),
                if (_audio != null)
                  _attachmentRow(
                    icon: Icons.audiotrack_outlined,
                    name: _fileName(_audio!.path),
                    onRemove: () => setState(() => _audio = null),
                    isDark: isDark,
                  ),
              ],
            ),
          ),
        ],

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
                  backgroundColor: Colors.orange.shade700,
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
                          Text('إرسال الطلب', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, fontFamily: 'Cairo')),
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
            Text('تم إرسال الطلب بنجاح', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                fontFamily: 'Cairo', color: isDark ? Colors.white : Colors.black87)),
            const SizedBox(height: 6),
            Text('ستصلك الردود عبر الإشعارات أو قسم طلباتي.',
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

  Widget _dropdown<T>({
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

  Widget _radioChip(String label, String value, bool isDark, Color purple) {
    final sel = _dispatchMode == value;
    return GestureDetector(
      onTap: () => setState(() => _dispatchMode = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: sel ? purple : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: sel ? purple : (isDark ? Colors.white12 : Colors.grey.shade300)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(sel ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                size: 14, color: sel ? Colors.white : (isDark ? Colors.white38 : Colors.grey)),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, fontFamily: 'Cairo',
                color: sel ? Colors.white : (isDark ? Colors.white60 : Colors.black54))),
          ],
        ),
      ),
    );
  }

  Widget _textField(bool isDark) {
    return TextField(
      controller: _descCtrl,
      maxLines: 4,
      maxLength: 500,
      style: TextStyle(fontSize: 11, fontFamily: 'Cairo', color: isDark ? Colors.white : Colors.black87),
      decoration: InputDecoration(
        hintText: 'اشرح ما تحتاجه بإيجاز...',
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

  Widget _attachmentRow({
    required IconData icon,
    required String name,
    required VoidCallback onRemove,
    required bool isDark,
  }) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
      leading: Icon(icon, size: 16, color: Colors.deepPurple),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10.5,
          fontFamily: 'Cairo',
          color: isDark ? Colors.white70 : Colors.black87,
        ),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.close, size: 16, color: Colors.red),
        onPressed: onRemove,
      ),
    );
  }

  bool _isAlreadyAttached(String path) {
    final normalized = path.toLowerCase();
    if (_images.any((f) => f.path.toLowerCase() == normalized)) return true;
    if (_videos.any((f) => f.path.toLowerCase() == normalized)) return true;
    if (_files.any((f) => f.path.toLowerCase() == normalized)) return true;
    if ((_audio?.path.toLowerCase() ?? '') == normalized) return true;
    return false;
  }

  String _extractExt(String input) {
    final name = input.trim().toLowerCase();
    final dot = name.lastIndexOf('.');
    if (dot <= -1 || dot == name.length - 1) return '';
    return name.substring(dot + 1);
  }

  String _fileName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final idx = normalized.lastIndexOf('/');
    if (idx < 0 || idx == normalized.length - 1) return normalized;
    return normalized.substring(idx + 1);
  }
}
