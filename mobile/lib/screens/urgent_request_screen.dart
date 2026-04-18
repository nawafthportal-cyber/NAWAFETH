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
import 'providers_map_screen.dart';

class UrgentRequestScreen extends StatefulWidget {
  const UrgentRequestScreen({super.key});

  @override
  State<UrgentRequestScreen> createState() => _UrgentRequestScreenState();
}

class _UrgentRequestScreenState extends State<UrgentRequestScreen>
  with SingleTickerProviderStateMixin {
  static const Color _mainColor = Color(0xFFB45309);
  static const Color _accentColor = Color(0xFF7C2D12);
  static const Color _inkColor = Color(0xFF0F172A);
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
  String _dispatchMode = 'all'; // 'all' | 'nearest'
  String _lastNearestToastKey = '';
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
    if (_dispatchMode == 'nearest' && _selectedScopedCity.isEmpty) {
      _snack('اختر المدينة عند البحث عن الأقرب');
      return;
    }

    setState(() => _submitting = true);
    final res = await MarketplaceService.createRequest(
      title: 'طلب عاجل - ${_selectedCat?.name ?? ''}',
      description: desc,
      requestType: 'urgent',
      subcategory: _selectedSub!.id,
      city: _selectedScopedCity.isEmpty ? null : _selectedScopedCity,
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

  void _openMapForCity(String city) {
    final cityValue = city.trim();
    if (cityValue.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProvidersMapScreen(
          category: _selectedCat?.name ?? 'خدمات',
          subCategory: _selectedSub?.name,
          requestDescription: _descCtrl.text.trim(),
          cityFilter: cityValue,
          urgentOnly: true,
        ),
      ),
    );
  }

  void _hintSnack(String msg, {String? city}) {
    final cityValue = (city ?? '').trim();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Cairo', fontSize: 11)),
        backgroundColor: Colors.deepPurple,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        action: cityValue.isEmpty
            ? null
            : SnackBarAction(
                label: 'عرض الخريطة',
                textColor: Colors.white,
                onPressed: () => _openMapForCity(cityValue),
              ),
      ),
    );
  }

  void _maybeShowNearestMapToast() {
    final city = _selectedScopedCity;
    if (_dispatchMode != 'nearest' || city.isEmpty) return;
    final key = '$_dispatchMode::$city';
    if (key == _lastNearestToastKey) return;
    _lastNearestToastKey = key;
    _hintSnack('سيتم عرض المزوّدين الأقرب على الخريطة حسب مدينة $city', city: city);
  }

  @override
  void dispose() {
    _descCtrl.dispose();
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
            child: CircularProgressIndicator(color: Colors.deepPurple),
          ),
        ),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF0E1726) : const Color(0xFFF5F5FA),
        bottomNavigationBar: const CustomBottomNav(currentIndex: 2),
        body: SafeArea(
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  gradient: isDark
                      ? const LinearGradient(
                          colors: [Color(0xFF0E1726), Color(0xFF122235), Color(0xFF17293D)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        )
                      : const LinearGradient(
                          colors: [Color(0xFFFFF7ED), Color(0xFFFFFBF5), Color(0xFFFFFFFF)],
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
            icon: Icons.tune_rounded,
            title: 'إعداد الطلب العاجل',
            description: 'حدد التصنيف وطريقة الإرسال حتى يصل الطلب بسرعة للمزود المناسب.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label('التصنيف الرئيسي', isDark),
                const SizedBox(height: 6),
                _dropdown<CategoryModel>(
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
                _dropdown<SubCategoryModel>(
                  isDark: isDark,
                  hint: 'اختر الفرعي',
                  value: _selectedSub,
                  items: _selectedCat?.subcategories ?? [],
                  labelFn: (s) => s.name,
                  onChanged: (s) => setState(() => _selectedSub = s),
                ),
                const SizedBox(height: 14),
                _label('طريقة الإرسال', isDark),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _radioChip('البحث عن الأقرب', 'nearest', isDark)),
                    const SizedBox(width: 8),
                    Expanded(child: _radioChip('إرسال للجميع', 'all', isDark)),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildEntrance(
          2,
          _sectionCard(
            icon: Icons.place_outlined,
            title: 'المدينة والخريطة',
            description: 'يمكنك تضييق النطاق حسب المدينة أو فتح الخريطة مباشرة عند اختيار الأقرب.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label('المنطقة الإدارية والمدينة', isDark),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: _dropdown<SaudiRegionCatalogEntry>(
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
                      child: _dropdown<String>(
                        isDark: isDark,
                        hint: _dispatchMode == 'nearest'
                            ? 'اختر المدينة (إلزامي)'
                            : 'اختر المدينة (اختياري)',
                        value: _selectedCity,
                        items: _availableCities,
                        labelFn: (city) => city,
                        onChanged: (city) {
                          setState(() => _selectedCity = city);
                          _maybeShowNearestMapToast();
                        },
                      ),
                    ),
                  ],
                ),
                if (_dispatchMode == 'nearest' && _selectedScopedCity.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _openMapForCity(_selectedScopedCity),
                      icon: const Icon(Icons.map_outlined, size: 16),
                      label: const Text(
                        'عرض المزوّدين الأقرب على الخريطة',
                        style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _accentColor,
                        side: BorderSide(color: _accentColor.withValues(alpha: 0.25)),
                        backgroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                ],
                if (_dispatchMode == 'all' && _selectedScopedCity.isNotEmpty) ...[
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
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildEntrance(
          3,
          _sectionCard(
            icon: Icons.notes_rounded,
            title: 'وصف الحالة',
            description: 'اشرح المطلوب بإيجاز ووضوح لرفع سرعة الاستجابة.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label('وصف الخدمة المطلوبة', isDark),
                const SizedBox(height: 6),
                _textField(isDark),
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
            description: 'أضف صورًا أو ملفات أو وسائط توضيحية لدعم الطلب.',
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
        color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFD7E5F2)),
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

  Widget _radioChip(String label, String value, bool isDark) {
    final sel = _dispatchMode == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _dispatchMode = value;
        });
        _maybeShowNearestMapToast();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          gradient: sel
              ? const LinearGradient(
                  colors: [Color(0xFFD97706), Color(0xFFEA580C)],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                )
              : null,
          color: sel ? null : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: sel ? Colors.transparent : (isDark ? Colors.white12 : const Color(0xFFD7E5F2))),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(sel ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                size: 14, color: sel ? Colors.white : (isDark ? Colors.white38 : Colors.grey)),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, fontFamily: 'Cairo',
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
        fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8FBFF),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: isDark ? Colors.white12 : const Color(0xFFD7E5F2)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: isDark ? Colors.white12 : const Color(0xFFD7E5F2)),
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
      leading: Icon(icon, size: 16, color: _mainColor),
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

  Widget _heroCard() {
    final categoryLabel = _selectedCat?.name ?? 'اختر التصنيف المناسب';
    final cityLabel = _selectedScopedCity.isEmpty ? 'بدون مدينة محددة' : _selectedScopedCity;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          colors: [Color(0xFF7C2D12), Color(0xFFB45309), Color(0xFFEA580C)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C2D12).withValues(alpha: 0.22),
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
                          'طلب خدمة عاجلة',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'أرسل الحالة بسرعة وحدد هل تريد الأقرب أو النشر العام للمزوّدين.',
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
                  const Icon(Icons.bolt_rounded, size: 22, color: Colors.white),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _heroChip(Icons.category_outlined, categoryLabel),
                  _heroChip(Icons.route_outlined, _dispatchMode == 'nearest' ? 'الأقرب' : 'للجميع'),
                  _heroChip(Icons.place_outlined, cityLabel),
                  _heroChip(Icons.attach_file_rounded, '${_images.length + _videos.length + _files.length + (_audio == null ? 0 : 1)} مرفقات'),
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
        border: Border.all(color: const Color(0x22B45309)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C2D12).withValues(alpha: 0.06),
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

  Widget _attachmentsPanel(bool isDark) {
    final count = _images.length + _videos.length + _files.length + (_audio == null ? 0 : 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _attachBtn(Icons.camera_alt_rounded, 'صورة', _pickImages, isDark),
            _attachBtn(Icons.attach_file_rounded, 'ملف/وسائط', _pickFile, isDark),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FBFF),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFD7E5F2)),
          ),
          child: count == 0
              ? const Column(
                  children: [
                    Icon(Icons.cloud_upload_outlined, color: _mainColor, size: 26),
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
                      'يمكنك إضافة صور أو فيديوهات أو ملفات أو مقطع صوتي قبل الإرسال.',
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
                    if (_images.isNotEmpty) ...[
                      const Text(
                        'الصور',
                        style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 64,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _images.length,
                          itemBuilder: (_, i) => Stack(
                            children: [
                              Container(
                                width: 64,
                                height: 64,
                                margin: const EdgeInsets.only(left: 8),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  image: DecorationImage(
                                    image: FileImage(_images[i]),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 4,
                                left: 12,
                                child: GestureDetector(
                                  onTap: () => setState(() => _images.removeAt(i)),
                                  child: Container(
                                    width: 20,
                                    height: 20,
                                    decoration: const BoxDecoration(color: Color(0xFFB42318), shape: BoxShape.circle),
                                    child: const Icon(Icons.close, size: 12, color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
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
                      Text('إرسال الطلب', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, fontFamily: 'Cairo')),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

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
