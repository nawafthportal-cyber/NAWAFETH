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

class _ServiceRequestFormScreenState extends State<ServiceRequestFormScreen> {
  static const Color _mainColor = Colors.deepPurple;

  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _detailsController = TextEditingController();
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
    // إذا جاء من صفحة مزود → نوع عادي تلقائياً
    if (widget.providerId != null) _requestType = 'normal';
    _loadCategories();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _detailsController.dispose();
    // _selectedCity — لا يحتاج dispose
    if (_recorderInitialized) _recorder.closeRecorder();
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
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('إضافة مرفق',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.photo_camera, color: _mainColor),
              title: const Text('تصوير صورة'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: _mainColor),
              title: const Text('اختيار صورة من المعرض'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam, color: _mainColor),
              title: const Text('تصوير فيديو'),
              onTap: () {
                Navigator.pop(context);
                _pickVideo(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.video_library, color: _mainColor),
              title: const Text('اختيار فيديو من المعرض'),
              onTap: () {
                Navigator.pop(context);
                _pickVideo(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.attach_file, color: _mainColor),
              title: const Text('اختيار ملف'),
              onTap: () {
                Navigator.pop(context);
                _pickFile();
              },
            ),
          ]),
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

  // ─── Build ───

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.grey[100],
        appBar: PlatformTopBar(
          pageLabel: widget.providerName != null
              ? 'طلب خدمة من ${widget.providerName}'
              : 'طلب خدمة جديدة',
          showBackButton: true,
          showNotificationAction: false,
          showChatAction: false,
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
            children: [
              // ─── نوع الطلب ───
              _label('نوع الطلب'),
              const SizedBox(height: 6),
              _requestTypePicker(),
              const SizedBox(height: 14),

              // ─── التصنيف ───
              _label('القسم'),
              const SizedBox(height: 6),
              _categoryDropdown(),
              const SizedBox(height: 10),

              _label('التصنيف الفرعي'),
              const SizedBox(height: 6),
              _subcategoryDropdown(),
              const SizedBox(height: 14),

              // ─── المدينة ───
              _label('المدينة'),
              const SizedBox(height: 6),
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
                                fontFamily: 'Cairo', fontSize: 12.5),
                          ),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _selectedCity = v),
              ),
              if (_selectedCity != null) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _selectedCity = null),
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('إلغاء اختيار المدينة'),
                  ),
                ),
              ],
              const SizedBox(height: 14),

              // ─── عنوان الطلب ───
              _label('عنوان الطلب'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _titleController,
                maxLength: 50,
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                decoration: _inputDeco(
                  hint: 'اكتب عنوان الطلب...',
                  counter: '${_titleController.text.length}/50',
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'يرجى إدخال عنوان الطلب'
                    : null,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),

              // ─── تفاصيل الطلب ───
              _label('تفاصيل الطلب'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _detailsController,
                maxLength: 500,
                maxLines: 5,
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                decoration: _inputDeco(
                  hint: 'اكتب تفاصيل الطلب بشكل دقيق...',
                  counter: '${_detailsController.text.length}/500',
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'يرجى إدخال تفاصيل الطلب'
                    : null,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),

              // ─── آخر موعد لاستلام العروض ───
              _label('آخر موعد لاستلام العروض (اختياري)'),
              const SizedBox(height: 6),
              _deadlineTile(),
              const SizedBox(height: 14),

              // ─── المرفقات ───
              _label('المرفقات'),
              const SizedBox(height: 6),
              _attachmentsPreview(),
              const SizedBox(height: 6),
              ElevatedButton.icon(
                onPressed: _showAttachmentOptions,
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text('إضافة مرفق',
                    style: TextStyle(color: Colors.white, fontSize: 12.5)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _mainColor,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 14),

              // ─── رسالة صوتية ───
              _label('رسالة صوتية (اختياري)'),
              const SizedBox(height: 6),
              _audioPart(),
              const SizedBox(height: 20),

              // ─── أزرار ───
              Row(children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _submitRequest,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _mainColor,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('تقديم الطلب',
                            style: TextStyle(
                                fontSize: 13.5,
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: _mainColor, width: 2),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('إلغاء',
                        style: TextStyle(
                            fontSize: 13.5,
                            color: _mainColor,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Sub-widgets ───

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 13.5,
          fontWeight: FontWeight.w800,
          color: _mainColor,
        ),
      );

  InputDecoration _inputDeco({String? hint, String? counter}) =>
      InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 12.5,
          color: Colors.grey.shade600,
        ),
        filled: true,
        fillColor: Colors.white,
        counterText: counter,
        counterStyle: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 11,
          color: Colors.grey.shade600,
        ),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      );

  Widget _requestTypePicker() {
    // إذا جاء من صفحة مزود محدد → نوع عادي فقط.
    if (_isProviderRequest) {
      return Container(
        width: 110,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: _mainColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _mainColor.withValues(alpha: 0.3)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_rounded, color: _mainColor, size: 16),
            SizedBox(width: 6),
            Text(
              'عادي',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: _mainColor,
              ),
            ),
          ],
        ),
      );
    }

    final types = <String, String>{
      'normal': 'عادي',
      'competitive': 'تنافسي',
      'urgent': 'عاجل',
    };
    return Wrap(
      spacing: 8,
      children: types.entries.map((e) {
        final selected = _requestType == e.key;
        return ChoiceChip(
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          label: Text(
            e.value,
            style: const TextStyle(fontFamily: 'Cairo', fontSize: 12.5),
          ),
          selected: selected,
          selectedColor: _mainColor.withAlpha(50),
          onSelected: (val) {
            if (val) setState(() => _requestType = e.key);
          },
        );
      }).toList(),
    );
  }

  Widget _categoryDropdown() {
    if (_categoriesLoading) {
      return const Center(
        child: SizedBox(
          height: 18,
          width: 18,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        ),
      );
    }
    return DropdownButtonFormField<int>(
      initialValue: _selectedCategoryId,
      decoration: _inputDeco(hint: 'اختر القسم'),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          const Icon(Icons.calendar_today, color: _mainColor, size: 18),
          const SizedBox(width: 10),
          Text(
            _quoteDeadline == null
                ? 'اضغط لتحديد التاريخ'
                : DateFormat('dd/MM/yyyy').format(_quoteDeadline!),
            style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12.5,
                color: _quoteDeadline == null ? Colors.grey : Colors.black),
          ),
        ]),
      ),
    );
  }

  Widget _attachmentsPreview() {
    if (_images.isEmpty && _videos.isEmpty && _files.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_images.isNotEmpty) ...[
          const Text(
            'الصور:',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _images
                .map((img) => Stack(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(img,
                            width: 80, height: 80, fit: BoxFit.cover),
                      ),
                      Positioned(
                        top: 0,
                        left: 0,
                        child: GestureDetector(
                          onTap: () => setState(() => _images.remove(img)),
                          child: Container(
                            decoration: const BoxDecoration(
                                color: Colors.red, shape: BoxShape.circle),
                            child: const Icon(Icons.close,
                                color: Colors.white, size: 18),
                          ),
                        ),
                      ),
                    ]))
                .toList(),
          ),
          const SizedBox(height: 12),
        ],
        if (_videos.isNotEmpty) ...[
          const Text(
            'الفيديوهات:',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          ..._videos.map((v) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.video_file, color: _mainColor),
                title: Text(v.path.split('/').last,
                    style:
                        const TextStyle(fontFamily: 'Cairo', fontSize: 11.5)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => setState(() => _videos.remove(v)),
                ),
              )),
          const SizedBox(height: 12),
        ],
        if (_files.isNotEmpty) ...[
          const Text(
            'الملفات:',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          ..._files.map((f) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.attach_file, color: _mainColor),
                title: Text(f.path.split('/').last,
                    style:
                        const TextStyle(fontFamily: 'Cairo', fontSize: 11.5)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => setState(() => _files.remove(f)),
                ),
              )),
        ],
      ]),
    );
  }

  Widget _audioPart() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(
            onPressed: _toggleRecording,
            icon: Icon(_isRecording ? Icons.stop : Icons.mic, size: 34),
            color: _isRecording ? Colors.red : _mainColor,
          ),
          const SizedBox(width: 8),
          Text(
            _isRecording
                ? 'جاري التسجيل... اضغط للإيقاف'
                : _audioPath != null
                    ? 'تم التسجيل ✓'
                    : 'اضغط للبدء بالتسجيل',
            style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                color: _isRecording ? Colors.red : Colors.grey[700]),
          ),
        ]),
        if (_audioPath != null)
          TextButton.icon(
            onPressed: () => setState(() => _audioPath = null),
            icon: const Icon(Icons.delete, size: 18),
            label: const Text('حذف التسجيل'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
      ]),
    );
  }
}
