import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../services/marketplace_service.dart';
import '../constants/saudi_cities.dart';
import '../widgets/platform_top_bar.dart';

/// شاشة إنشاء طلب خدمة جديد — مربوطة بالباكند
class ServiceRequestFormScreen extends StatefulWidget {
  /// اسم مزود الخدمة (فقط للطلب العادي من صفحة المزود)
  final String? providerName;

  /// معرّف ProviderProfile (للطلب العادي فقط)
  final String? providerId;

  const ServiceRequestFormScreen({
    super.key,
    this.providerName,
    this.providerId,
  });

  @override
  State<ServiceRequestFormScreen> createState() =>
      _ServiceRequestFormScreenState();
}

class _ServiceRequestFormScreenState extends State<ServiceRequestFormScreen>
  with SingleTickerProviderStateMixin {
  static const Color _mainColor = Colors.deepPurple;
  static const Color _accentColor = Color(0xFF0F766E);
  static const Color _surfaceColor = Color(0xFFF8FBFF);
  static const Color _inkColor = Color(0xFF0F172A);

  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _detailsController = TextEditingController();
  late final AnimationController _entranceController;
  String? _selectedCity;

  // ─── نوع الطلب ───
  String _requestType = 'normal'; // normal | competitive | urgent

  // ─── الأقسام ───
  List<Map<String, dynamic>> _categories = [];
  bool _categoriesLoading = true;
  int? _selectedCategoryId;
  int? _selectedSubcategoryId;

  // ─── موعد استلام العروض ───
  DateTime? _quoteDeadline;

  // ─── المرفقات ───
  final List<File> _images = [];
  final List<File> _videos = [];
  final List<File> _files = [];
  String? _audioPath;
  bool _isRecording = false;

  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  bool _recorderInitialized = false;

  bool _submitting = false;

  bool get _isProviderRequest => widget.providerId != null;
  String get _effectiveRequestType =>
      _isProviderRequest ? 'normal' : _requestType;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    // إذا جاء من صفحة مزود → نوع عادي تلقائياً
    if (widget.providerId != null) _requestType = 'normal';
    _loadCategories();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _entranceController.forward();
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _detailsController.dispose();
    // _selectedCity — لا يحتاج dispose
    if (_recorderInitialized) _recorder.closeRecorder();
    _entranceController.dispose();
    super.dispose();
  }

  // ─── تحميل الأقسام ───
  Future<void> _loadCategories() async {
    final cats = await MarketplaceService.getCategories();
    if (!mounted) return;
    setState(() {
      _categories = cats;
      _categoriesLoading = false;
    });
  }

  List<Map<String, dynamic>> get _subcategories {
    if (_selectedCategoryId == null) return [];
    final cat = _categories.firstWhere((c) => c['id'] == _selectedCategoryId,
        orElse: () => {});
    final subs = cat['subcategories'];
    if (subs == null) return [];
    return (subs as List).cast<Map<String, dynamic>>();
  }

  // ─── المرفقات ───
  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source);
    if (picked == null || !mounted) return;
    setState(() => _images.add(File(picked.path)));
  }

  Future<void> _pickVideo(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickVideo(source: source);
    if (picked == null || !mounted) return;
    setState(() => _videos.add(File(picked.path)));
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'txt', 'xlsx', 'xls'],
    );
    final path = result?.files.single.path;
    if (path == null || !mounted) return;
    setState(() => _files.add(File(path)));
  }

  Future<void> _initRecorder() async {
    try {
      final status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) {
        if (!mounted) return;
        _snack('يجب السماح بالوصول للميكروفون');
        return;
      }
      await _recorder.openRecorder();
      if (!mounted) return;
      setState(() => _recorderInitialized = true);
    } catch (_) {
      if (mounted) _snack('تعذر تهيئة التسجيل الصوتي');
    }
  }

  Future<void> _toggleRecording() async {
    if (!_recorderInitialized) {
      await _initRecorder();
      if (!_recorderInitialized) return;
    }
    if (_isRecording) {
      final path = await _recorder.stopRecorder();
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _audioPath = path;
      });
    } else {
      final dir = Directory.systemTemp;
      final path =
          '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.aac';
      await _recorder.startRecorder(toFile: path);
      if (!mounted) return;
      setState(() => _isRecording = true);
    }
  }

  Future<void> _selectDeadline() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('ar', 'SA'),
    );
    if (picked == null || !mounted) return;
    setState(() => _quoteDeadline = picked);
  }

  void _showAttachmentOptions() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1F0F172A),
                  blurRadius: 24,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'إضافة مرفق',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: _inkColor,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'أرفق صورًا أو فيديوهات أو ملفات داعمة قبل إرسال الطلب.',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF667085),
                  ),
                ),
                const SizedBox(height: 12),
                _buildSheetActionItem(
                  icon: Icons.photo_camera_outlined,
                  label: 'تصوير صورة',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickImage(ImageSource.camera);
                  },
                ),
                _buildSheetActionItem(
                  icon: Icons.photo_library_outlined,
                  label: 'اختيار صورة من المعرض',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickImage(ImageSource.gallery);
                  },
                ),
                _buildSheetActionItem(
                  icon: Icons.videocam_outlined,
                  label: 'تصوير فيديو',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickVideo(ImageSource.camera);
                  },
                ),
                _buildSheetActionItem(
                  icon: Icons.video_library_outlined,
                  label: 'اختيار فيديو من المعرض',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickVideo(ImageSource.gallery);
                  },
                ),
                _buildSheetActionItem(
                  icon: Icons.attach_file_rounded,
                  label: 'اختيار ملف',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickFile();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Cairo'))));
  }

  // ─── إرسال الطلب ───
  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;

    // التحقق من الحقول المطلوبة
    if (_selectedSubcategoryId == null) {
      _snack('الرجاء اختيار التصنيف الفرعي');
      return;
    }

    final city = _selectedCity ?? '';

    // الطلب العادي يحتاج provider
    int? providerId;
    if (_effectiveRequestType == 'normal') {
      if (widget.providerId == null) {
        _snack('الطلب العادي يتطلب تحديد مزود خدمة');
        return;
      }
      providerId = int.tryParse(widget.providerId!);
    }

    setState(() => _submitting = true);

    final res = await MarketplaceService.createRequest(
      title: _titleController.text.trim(),
      description: _detailsController.text.trim(),
      requestType: _effectiveRequestType,
      subcategory: _selectedSubcategoryId!,
      city: city.isNotEmpty ? city : null,
      provider: providerId,
      quoteDeadline: _quoteDeadline != null
          ? DateFormat('yyyy-MM-dd').format(_quoteDeadline!)
          : null,
      images: _images,
      videos: _videos,
      files: _files,
      audio: _audioPath != null ? File(_audioPath!) : null,
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (res.isSuccess) {
      showDialog(
        context: context,
        builder: (_) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Row(children: [
              Icon(Icons.check_circle, color: Colors.green, size: 30),
              SizedBox(width: 10),
              Text('تم إرسال الطلب'),
            ]),
            content: const Text(
              'تم إرسال طلب الخدمة بنجاح. سيتم إشعارك عند استلام العروض من مقدمي الخدمة.',
              style: TextStyle(height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context); // close dialog
                  Navigator.pop(context, true); // back with refresh signal
                },
                child: const Text('حسناً'),
              ),
            ],
          ),
        ),
      );
    } else {
      _snack(res.error ?? 'فشل إرسال الطلب');
    }
  }

  String get _requestTypeLabel {
    switch (_effectiveRequestType) {
      case 'competitive':
        return 'تنافسي';
      case 'urgent':
        return 'عاجل';
      default:
        return 'عادي';
    }
  }

  String get _requestTypeDescription {
    switch (_effectiveRequestType) {
      case 'competitive':
        return 'يستقبل عروضًا من عدة مقدمي خدمات حتى الموعد الذي تحدده.';
      case 'urgent':
        return 'يُعرض بشكل أسرع للطلبات التي تحتاج تنفيذًا عاجلًا.';
      default:
        return _isProviderRequest
            ? 'الطلب سيُرسل مباشرة إلى مقدم الخدمة المحدد.'
            : 'يوجَّه مباشرة إلى مقدم الخدمة الذي اخترته من داخل المحادثة.';
    }
  }

  int get _attachmentsCount =>
      _images.length + _videos.length + _files.length + (_audioPath == null ? 0 : 1);

  String? get _selectedCategoryName {
    if (_selectedCategoryId == null) return null;
    final category = _categories.cast<Map<String, dynamic>>().where(
          (entry) => entry['id'] == _selectedCategoryId,
        );
    if (category.isEmpty) return null;
    return category.first['name'] as String?;
  }

  String? get _selectedSubcategoryName {
    if (_selectedSubcategoryId == null) return null;
    final sub = _subcategories.where(
      (entry) => entry['id'] == _selectedSubcategoryId,
    );
    if (sub.isEmpty) return null;
    return sub.first['name'] as String?;
  }

  // ─── Build ───

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _surfaceColor,
        appBar: PlatformTopBar(
          pageLabel: widget.providerName != null
              ? 'طلب خدمة من ${widget.providerName}'
              : 'طلب خدمة جديدة',
          showBackButton: true,
          showNotificationAction: false,
          showChatAction: false,
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFF1F7FF), Color(0xFFF8FBFF), Color(0xFFFFFFFF)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Form(
            key: _formKey,
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
              children: [
                _buildEntrance(0, _buildHeroCard()),
                const SizedBox(height: 12),
                _buildEntrance(
                  1,
                  _buildSectionCard(
                    icon: Icons.tune_rounded,
                    title: 'إعداد الطلب',
                    description: 'حدد نوع الطلب والقسم والتصنيف الفرعي بدقة.',
                    child: Column(
                      children: [
                        _requestTypePicker(),
                        const SizedBox(height: 14),
                        _categoryDropdown(),
                        const SizedBox(height: 12),
                        _subcategoryDropdown(),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _buildEntrance(
                  2,
                  _buildSectionCard(
                    icon: Icons.place_outlined,
                    title: 'الموقع والعنوان',
                    description: 'أضف المدينة والعنوان المختصر ليظهر الطلب بشكل أوضح.',
                    child: Column(
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: _selectedCity,
                          decoration: _inputDeco(hint: 'اختر المدينة (اختياري)'),
                          isExpanded: true,
                          menuMaxHeight: 300,
                          items: SaudiCities.all
                              .map((city) => DropdownMenuItem(
                                    value: city,
                                    child: Text(
                                      city,
                                      style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ))
                              .toList(),
                          onChanged: (value) => setState(() => _selectedCity = value),
                        ),
                        if (_selectedCity != null) ...[
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () => setState(() => _selectedCity = null),
                              icon: const Icon(Icons.close_rounded, size: 16),
                              label: const Text(
                                'إلغاء اختيار المدينة',
                                style: TextStyle(fontFamily: 'Cairo'),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _titleController,
                          maxLength: 50,
                          style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                          decoration: _inputDeco(
                            hint: 'اكتب عنوان الطلب...',
                            counter: '${_titleController.text.length}/50',
                          ),
                          validator: (value) => (value == null || value.trim().isEmpty)
                              ? 'يرجى إدخال عنوان الطلب'
                              : null,
                          onChanged: (_) => setState(() {}),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _buildEntrance(
                  3,
                  _buildSectionCard(
                    icon: Icons.notes_rounded,
                    title: 'تفاصيل الطلب',
                    description: 'اشرح المطلوب بدقة حتى تصل عروض مناسبة بشكل أسرع.',
                    child: TextFormField(
                      controller: _detailsController,
                      maxLength: 500,
                      maxLines: 6,
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                      decoration: _inputDeco(
                        hint: 'اكتب تفاصيل الطلب بشكل دقيق...',
                        counter: '${_detailsController.text.length}/500',
                      ),
                      validator: (value) => (value == null || value.trim().isEmpty)
                          ? 'يرجى إدخال تفاصيل الطلب'
                          : null,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _buildEntrance(
                  4,
                  _buildSectionCard(
                    icon: Icons.event_outlined,
                    title: 'موعد استقبال العروض',
                    description: 'يمكنك تركه فارغًا أو تحديد تاريخ مناسب خلال 365 يومًا.',
                    child: _deadlineTile(),
                  ),
                ),
                const SizedBox(height: 12),
                _buildEntrance(
                  5,
                  _buildSectionCard(
                    icon: Icons.attach_file_rounded,
                    title: 'المرفقات',
                    description: 'أضف صورًا أو فيديوهات أو ملفات توضيحية تدعم وصفك.',
                    child: Column(
                      children: [
                        _attachmentsPreview(),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _showAttachmentOptions,
                            icon: const Icon(Icons.add_rounded, color: Colors.white),
                            label: const Text(
                              'إضافة مرفق',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _mainColor,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _buildEntrance(
                  6,
                  _buildSectionCard(
                    icon: Icons.mic_none_rounded,
                    title: 'رسالة صوتية',
                    description: 'أضف توضيحًا صوتيًا مختصرًا إذا كان الشرح الكتابي لا يكفي.',
                    child: _audioPart(),
                  ),
                ),
                const SizedBox(height: 14),
                _buildEntrance(7, _buildActions()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Sub-widgets ───

  InputDecoration _inputDeco({String? hint, String? counter}) =>
      InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: Color(0xFF98A2B3),
        ),
        filled: true,
        fillColor: const Color(0xFFF8FBFF),
        counterText: counter,
        counterStyle: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 11,
          color: Color(0xFF667085),
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFD7E5F2)),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFD7E5F2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: _mainColor, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFDC2626)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.2),
        ),
      );

  Widget _requestTypePicker() {
    // إذا جاء من صفحة مزود محدد → نوع عادي فقط.
    if (_isProviderRequest) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _mainColor.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _mainColor.withValues(alpha: 0.22)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.verified_rounded, color: _mainColor, size: 16),
              SizedBox(width: 8),
              Text(
                'طلب عادي مباشر',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: _mainColor,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final types = <Map<String, String>>[
      {
        'key': 'normal',
        'label': 'عادي',
        'hint': 'موجه لمقدم خدمة محدد',
      },
      {
        'key': 'competitive',
        'label': 'تنافسي',
        'hint': 'استقبال عدة عروض',
      },
      {
        'key': 'urgent',
        'label': 'عاجل',
        'hint': 'عرض سريع للطلبات المستعجلة',
      },
    ];

    return Row(
      children: types.map((entry) {
        final selected = _requestType == entry['key'];
        return Expanded(
          child: Padding(
            padding: EdgeInsetsDirectional.only(
              start: entry == types.first ? 0 : 6,
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => setState(() => _requestType = entry['key']!),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                decoration: BoxDecoration(
                  gradient: selected
                      ? const LinearGradient(
                          colors: [Color(0xFF5B3FD0), Color(0xFF7C4DFF)],
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                        )
                      : null,
                  color: selected ? null : const Color(0xFFF8FBFF),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: selected
                        ? Colors.transparent
                        : const Color(0xFFD7E5F2),
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: _mainColor.withValues(alpha: 0.20),
                            blurRadius: 18,
                            offset: const Offset(0, 10),
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  children: [
                    Text(
                      entry['label']!,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                        color: selected ? Colors.white : _inkColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry['hint']!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? Colors.white.withValues(alpha: 0.84)
                            : const Color(0xFF667085),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _categoryDropdown() {
    if (_categoriesLoading) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FBFF),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFD7E5F2)),
        ),
        child: const Center(
          child: SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
        ),
      );
    }
    return DropdownButtonFormField<int>(
      initialValue: _selectedCategoryId,
      decoration: _inputDeco(hint: 'اختر القسم'),
      borderRadius: BorderRadius.circular(18),
      items: _categories
          .map((c) => DropdownMenuItem<int>(
              value: c['id'] as int,
              child: Text(c['name'] as String,
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 12.5))))
          .toList(),
      onChanged: (val) {
        setState(() {
          _selectedCategoryId = val;
          _selectedSubcategoryId = null; // reset sub
        });
      },
      validator: (v) => v == null ? 'اختر القسم' : null,
    );
  }

  Widget _subcategoryDropdown() {
    final subs = _subcategories;
    return DropdownButtonFormField<int>(
      initialValue: _selectedSubcategoryId,
      decoration: _inputDeco(hint: 'اختر التصنيف'),
      borderRadius: BorderRadius.circular(18),
      items: subs
          .map((s) => DropdownMenuItem<int>(
              value: s['id'] as int,
              child: Text(s['name'] as String,
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 12.5))))
          .toList(),
      onChanged: (val) => setState(() => _selectedSubcategoryId = val),
      validator: (v) => v == null ? 'اختر التصنيف الفرعي' : null,
    );
  }

  Widget _deadlineTile() {
    return InkWell(
      onTap: _selectDeadline,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FBFF),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFD7E5F2)),
        ),
        child: Row(children: [
          const Icon(Icons.calendar_today_outlined, color: _mainColor, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _quoteDeadline == null
                  ? 'اضغط لتحديد التاريخ'
                  : DateFormat('dd/MM/yyyy').format(_quoteDeadline!),
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: _quoteDeadline == null
                    ? const Color(0xFF98A2B3)
                    : _inkColor,
              ),
            ),
          ),
          if (_quoteDeadline != null)
            IconButton(
              onPressed: () => setState(() => _quoteDeadline = null),
              icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFFB42318)),
            ),
        ]),
      ),
    );
  }

  Widget _attachmentsPreview() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD7E5F2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          children: [
            _buildInfoPill(
              icon: Icons.layers_outlined,
              label: _attachmentsCount == 0
                  ? 'لا توجد مرفقات'
                  : 'عدد المرفقات: $_attachmentsCount',
            ),
          ],
        ),
        if (_images.isEmpty && _videos.isEmpty && _files.isEmpty) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE4EBF1)),
            ),
            child: const Column(
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
                  'يمكنك دعم الطلب بصور أو فيديوهات أو ملفات توضّح المطلوب.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF667085),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_images.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text(
            'الصور',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: _inkColor,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _images
                .map((image) => Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.file(
                            image,
                            width: 84,
                            height: 84,
                            fit: BoxFit.cover,
                          ),
                        ),
                        PositionedDirectional(
                          top: 6,
                          start: 6,
                          child: InkWell(
                            onTap: () => setState(() => _images.remove(image)),
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: const BoxDecoration(
                                color: Color(0xFFB42318),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ))
                .toList(),
          ),
        ],
        if (_videos.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text(
            'الفيديوهات',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: _inkColor,
            ),
          ),
          const SizedBox(height: 8),
          ..._videos.map(
            (video) => _buildAttachmentListItem(
              icon: Icons.videocam_outlined,
              name: video.path.split('/').last,
              onRemove: () => setState(() => _videos.remove(video)),
            ),
          ),
        ],
        if (_files.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text(
            'الملفات',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: _inkColor,
            ),
          ),
          const SizedBox(height: 8),
          ..._files.map(
            (file) => _buildAttachmentListItem(
              icon: Icons.insert_drive_file_outlined,
              name: file.path.split('/').last,
              onRemove: () => setState(() => _files.remove(file)),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _audioPart() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD7E5F2)),
      ),
      child: Column(children: [
        Row(children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: _isRecording
                  ? const Color(0xFFFFF1F1)
                  : _mainColor.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              onPressed: _toggleRecording,
              icon: Icon(_isRecording ? Icons.stop_rounded : Icons.mic_none_rounded),
              color: _isRecording ? const Color(0xFFB42318) : _mainColor,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isRecording
                      ? 'جاري تسجيل الرسالة الصوتية'
                      : _audioPath != null
                          ? 'تم تجهيز الرسالة الصوتية'
                          : 'أضف ملاحظة صوتية قصيرة',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: _isRecording ? const Color(0xFFB42318) : _inkColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isRecording
                      ? 'اضغط للإيقاف وحفظ التسجيل الحالي.'
                      : _audioPath != null
                          ? 'يمكنك حذف التسجيل أو إبقاؤه ضمن الطلب.'
                          : 'التسجيل اختياري لكنه مفيد للحالات التي تحتاج شرحًا إضافيًا.',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF667085),
                  ),
                ),
              ],
            ),
          ),
        ]),
        if (_audioPath != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => setState(() => _audioPath = null),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text(
                'حذف التسجيل',
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800),
              ),
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFB42318)),
            ),
          ),
      ]),
    );
  }

  Widget _buildHeroCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          colors: [Color(0xFF183B64), Color(0xFF22577A), Color(0xFF0F766E)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0C223D).withValues(alpha: 0.16),
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
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.assignment_add,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.providerName != null
                              ? 'طلب خدمة من ${widget.providerName}'
                              : 'طلب خدمة جديدة',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _requestTypeDescription,
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
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildHeroChip(icon: Icons.local_offer_outlined, label: _requestTypeLabel),
                  _buildHeroChip(
                    icon: Icons.category_outlined,
                    label: _selectedCategoryName ?? 'القسم غير محدد',
                  ),
                  if (_selectedSubcategoryName != null)
                    _buildHeroChip(
                      icon: Icons.account_tree_outlined,
                      label: _selectedSubcategoryName!,
                    ),
                  if (_selectedCity != null)
                    _buildHeroChip(icon: Icons.location_on_outlined, label: _selectedCity!),
                  if (_attachmentsCount > 0)
                    _buildHeroChip(icon: Icons.attach_file_rounded, label: '$_attachmentsCount مرفقات'),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
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
        border: Border.all(color: const Color(0x220E5E85)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0C223D).withValues(alpha: 0.06),
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

  Widget _buildHeroChip({required IconData icon, required String label}) {
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

  Widget _buildInfoPill({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE4EBF1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: _accentColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 10.8,
              fontWeight: FontWeight.w800,
              color: _inkColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentListItem({
    required IconData icon,
    required String name,
    required VoidCallback onRemove,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4EBF1)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _mainColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: _mainColor, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: _inkColor,
              ),
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFB42318)),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Row(children: [
      Expanded(
        child: ElevatedButton(
          onPressed: _submitting ? null : _submitRequest,
          style: ElevatedButton.styleFrom(
            backgroundColor: _mainColor,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          child: _submitting
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'تقديم الطلب',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: OutlinedButton(
          onPressed: () => Navigator.pop(context),
          style: OutlinedButton.styleFrom(
            foregroundColor: _mainColor,
            padding: const EdgeInsets.symmetric(vertical: 15),
            side: const BorderSide(color: _mainColor, width: 1.5),
            backgroundColor: Colors.white.withValues(alpha: 0.9),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          child: const Text(
            'إلغاء',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _buildSheetActionItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFFF4F8FB),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: _mainColor, size: 20),
      ),
      title: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: _inkColor,
        ),
      ),
      onTap: onTap,
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
}
