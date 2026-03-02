import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nawafeth/services/interactive_service.dart';
import 'package:nawafeth/services/profile_service.dart';
import 'package:nawafeth/utils/debounced_save_runner.dart';

class ContentStep extends StatefulWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;

  const ContentStep({super.key, required this.onNext, required this.onBack});

  @override
  State<ContentStep> createState() => _ContentStepState();
}

class _ContentStepState extends State<ContentStep> {
  final ScrollController _scrollController = ScrollController();
  final DebouncedSaveRunner _autoSaveRunner = DebouncedSaveRunner();

  final List<SectionContent> sections = [];
  final Set<String> _uploadedMediaPaths = <String>{};

  bool _isAddingNew = false;
  int? _editingIndex;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isInitialized = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    final result = await ProfileService.fetchProviderProfile();
    if (!mounted) return;

    if (result.isSuccess && result.data != null) {
      final profile = result.data!;
      final loadedSections = _deserializeSections(profile.contentSections);
      setState(() {
        sections
          ..clear()
          ..addAll(loadedSections);
        _isLoading = false;
        _saveError = null;
        _isInitialized = true;
      });
      return;
    }

    setState(() {
      _isLoading = false;
      _saveError = result.error ?? 'تعذر تحميل محتوى الأعمال';
      _isInitialized = true;
    });
  }

  void _scrollToEditor() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _startAddSection() {
    setState(() {
      _isAddingNew = true;
      _editingIndex = null;
    });
    _scrollToEditor();
  }

  void _startEditSection(int index) {
    setState(() {
      _isAddingNew = false;
      _editingIndex = index;
    });
    _scrollToEditor();
  }

  void _cancelAddSection() {
    setState(() {
      _isAddingNew = false;
      _editingIndex = null;
    });
  }

  List<SectionContent> _deserializeSections(List<dynamic> raw) {
    final parsed = <SectionContent>[];
    for (final item in raw) {
      if (item is Map) {
        final title = (item['title'] ?? '').toString().trim();
        final description = (item['description'] ?? '').toString().trim();
        if (title.isEmpty && description.isEmpty) continue;
        parsed.add(
          SectionContent(
            title: title,
            description: description,
            contentImages: [],
            contentVideos: [],
          ),
        );
      } else if (item is String && item.trim().isNotEmpty) {
        parsed.add(SectionContent(title: item.trim()));
      }
    }
    return parsed;
  }

  List<Map<String, dynamic>> _serializeSections() {
    return sections
        .where(
          (s) =>
              s.title.trim().isNotEmpty ||
              s.description.trim().isNotEmpty ||
              s.mainImage != null ||
              s.contentVideos.isNotEmpty ||
              s.contentImages.isNotEmpty,
        )
        .map(
          (s) => <String, dynamic>{
            'title': s.title.trim(),
            'description': s.description.trim(),
            'has_main_image': s.mainImage != null,
            'images_count':
                s.contentImages.length + (s.mainImage != null ? 1 : 0),
            'videos_count': s.contentVideos.length,
          },
        )
        .toList();
  }

  void _queueAutoSave() {
    if (!_isInitialized) return;
    _autoSaveRunner.schedule(_saveSectionsToApi);
  }

  String _sectionCaption(SectionContent section) {
    final title = section.title.trim();
    final description = section.description.trim();
    final raw = (title.isNotEmpty && description.isNotEmpty)
        ? '$title - $description'
        : (title.isNotEmpty ? title : description);
    if (raw.isEmpty) return 'معرض أعمال';
    return raw.length > 180 ? raw.substring(0, 180) : raw;
  }

  Future<String?> _uploadPortfolioMediaFile(
    XFile file, {
    required String fileType,
    required String caption,
  }) async {
    final path = file.path.trim();
    if (path.isEmpty || _uploadedMediaPaths.contains(path)) return null;

    final result = await ProfileService.uploadProviderPortfolioItem(
      filePath: path,
      fileType: fileType,
      caption: caption,
    );
    if (result.isSuccess) {
      _uploadedMediaPaths.add(path);
      return null;
    }
    return result.error ?? 'فشل رفع ملف من المعرض';
  }

  Future<String?> _syncSectionMediaToApi(SectionContent section) async {
    final caption = _sectionCaption(section);

    final main = section.mainImage;
    if (main != null) {
      final error = await _uploadPortfolioMediaFile(
        main,
        fileType: 'image',
        caption: caption,
      );
      if (error != null) return error;
    }

    for (final image in section.contentImages) {
      final error = await _uploadPortfolioMediaFile(
        image,
        fileType: 'image',
        caption: caption,
      );
      if (error != null) return error;
    }

    for (final video in section.contentVideos) {
      final error = await _uploadPortfolioMediaFile(
        video,
        fileType: 'video',
        caption: caption,
      );
      if (error != null) return error;
    }

    return null;
  }

  Future<String?> _syncAllSectionsMediaToApi() async {
    for (final section in sections) {
      final error = await _syncSectionMediaToApi(section);
      if (error != null) return error;
    }
    return null;
  }

  List<Map<String, dynamic>> _parseMapList(dynamic data) {
    if (data is List) {
      return data
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }
    if (data is Map && data['results'] is List) {
      final results = data['results'] as List;
      return results
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }
    return const <Map<String, dynamic>>[];
  }

  int? _parseItemId(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  Future<String?> _cleanupPortfolioWhenSectionsEmpty(
    List<Map<String, dynamic>> serializedSections,
  ) async {
    if (serializedSections.isNotEmpty) {
      return null;
    }

    final listResp = await InteractiveService.fetchMyPortfolio();
    if (!listResp.isSuccess) {
      return listResp.error ?? 'تعذر مزامنة معرض الأعمال';
    }

    final items = _parseMapList(listResp.data);
    for (final item in items) {
      final itemId = _parseItemId(item['id']);
      if (itemId == null || itemId <= 0) continue;

      final deleteResp = await InteractiveService.deletePortfolioItem(itemId);
      if (!deleteResp.isSuccess && deleteResp.statusCode != 404) {
        return deleteResp.error ?? 'تعذر حذف عناصر المعرض القديمة';
      }
    }
    return null;
  }

  Future<void> _saveSectionsToApi() async {
    final serializedSections = _serializeSections();
    final payload = <String, dynamic>{
      'content_sections': serializedSections,
    };

    if (!mounted) return;
    setState(() {
      _isSaving = true;
    });

    final cleanupError =
        await _cleanupPortfolioWhenSectionsEmpty(serializedSections);
    if (!mounted) return;
    if (cleanupError != null) {
      setState(() {
        _isSaving = false;
        _saveError = cleanupError;
      });
      return;
    }

    final mediaSyncError = await _syncAllSectionsMediaToApi();
    if (!mounted) return;
    if (mediaSyncError != null) {
      setState(() {
        _isSaving = false;
        _saveError = mediaSyncError;
      });
      return;
    }

    final result = await ProfileService.updateProviderProfile(payload);
    if (!mounted) return;

    setState(() {
      _isSaving = false;
      _saveError = result.isSuccess ? null : (result.error ?? 'فشل الحفظ');
    });
  }

  void _saveNewSection(SectionContent section) {
    setState(() {
      sections.add(section);
      _isAddingNew = false;
    });
    _queueAutoSave();
  }

  void _saveEditedSection(SectionContent section) {
    final index = _editingIndex;
    if (index == null) return;

    setState(() {
      sections[index] = section;
      _editingIndex = null;
    });
    _queueAutoSave();
  }

  Future<void> _confirmDeleteSection(int index) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Text(
            'تأكيد الحذف',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800),
          ),
          content: const Text(
            'هل أنت متأكد من حذف هذا القسم؟',
            style: TextStyle(fontFamily: 'Cairo'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text(
                'إلغاء',
                style: TextStyle(fontFamily: 'Cairo'),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                'حذف',
                style: TextStyle(fontFamily: 'Cairo', color: Colors.redAccent),
              ),
            ),
          ],
        );
      },
    );

    if (shouldDelete == true) {
      if (_editingIndex == index) {
        setState(() => _editingIndex = null);
      }
      _deleteSection(index);
    }
  }

  void _deleteSection(int index) {
    setState(() {
      sections.removeAt(index);
    });
    _queueAutoSave();
  }

  Future<void> _saveAndContinue() async {
    await _autoSaveRunner.flush();
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F4FC),
        bottomNavigationBar: BottomAppBar(
          elevation: 10,
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  if (!_isLoading) {
                    await _autoSaveRunner.flush();
                  }
                  widget.onBack();
                },
                icon: const Icon(Icons.arrow_back, color: Colors.deepPurple),
                label: const Text(
                  "السابق",
                  style: TextStyle(
                    color: Colors.deepPurple,
                    fontFamily: "Cairo",
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.deepPurple),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _saveAndContinue,
                icon: const Icon(Icons.check, color: Colors.white),
                label: const Text(
                  "التالي",
                  style: TextStyle(color: Colors.white, fontFamily: "Cairo"),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 28, 16, 130),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'محتوى خدماتك',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple,
                        fontFamily: "Cairo",
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'اعرض أعمالك السابقة بطريقة منظمة: كل قسم يمثل مشروعًا أو خدمة مع صورة رئيسية وفيديوهات مرتبطة.',
                      style: TextStyle(
                        color: Colors.grey,
                        fontFamily: "Cairo",
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildSaveStatus(),
                    const SizedBox(height: 8),
                    _infoTip(),
                    const SizedBox(height: 18),

                    // الكروت المختصرة للأقسام
                    if (_isLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 30),
                        child: Center(
                          child: CircularProgressIndicator(
                              color: Colors.deepPurple),
                        ),
                      ),
                    if (!_isLoading && sections.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: const Text(
                          'لم تضف أي قسم بعد. أضف قسمًا جديدًا ليظهر هنا.',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            color: Colors.black54,
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                    if (!_isLoading)
                      for (int i = 0; i < sections.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _SectionSummaryCard(
                            index: i,
                            section: sections[i],
                            onTap: () => _startEditSection(i),
                            onDelete: () => _confirmDeleteSection(i),
                          ),
                        ),

                    const SizedBox(height: 12),

                    // زر إضافة قسم جديد
                    Center(
                      child: ElevatedButton.icon(
                        onPressed: _isLoading
                            ? null
                            : (_isAddingNew || _editingIndex != null)
                                ? null
                                : _startAddSection,
                        icon: const Icon(Icons.add),
                        label: const Text(
                          "إضافة قسم جديد",
                          style: TextStyle(fontFamily: "Cairo", fontSize: 12),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // محرر القسم الجديد
                    if (_isAddingNew || _editingIndex != null)
                      NewSectionEditor(
                        initialSection: _editingIndex != null
                            ? sections[_editingIndex!]
                            : null,
                        onCancel: _cancelAddSection,
                        onSave: _editingIndex != null
                            ? _saveEditedSection
                            : _saveNewSection,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoTip() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F4FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Icon(Icons.info_outline, color: Colors.deepPurple, size: 20),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              "مثال: قسم لمحتوى فيديو تعريفي، قسم آخر لشرح لوحة التحكم، قسم ثالث يستعرض نتائج وتجارب عملاء.",
              style: TextStyle(
                fontFamily: "Cairo",
                fontSize: 10.5,
                color: Colors.black87,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveStatus() {
    if (_isSaving) {
      return const Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text(
            'جاري الحفظ التلقائي...',
            style: TextStyle(
                fontFamily: 'Cairo', fontSize: 10.5, color: Colors.black54),
          ),
        ],
      );
    }

    if (_saveError != null) {
      return Text(
        _saveError!,
        style: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 10.5,
          color: Colors.redAccent,
        ),
      );
    }

    return const SizedBox.shrink();
  }

  @override
  void dispose() {
    _autoSaveRunner.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

// نموذج بيانات القسم
class SectionContent {
  String title;
  String description;
  XFile? mainImage; // الصورة الرئيسية للقسم
  List<XFile> contentVideos; // فيديوهات هذا القسم
  List<XFile> contentImages; // صور هذا القسم

  SectionContent({
    this.title = '',
    this.description = '',
    this.mainImage,
    List<XFile>? contentVideos,
    List<XFile>? contentImages,
  })  : contentVideos = contentVideos ?? [],
        contentImages = contentImages ?? [];
}

/// كرت مختصر لعرض القسم (عرض فقط)
class _SectionSummaryCard extends StatelessWidget {
  final int index;
  final SectionContent section;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  const _SectionSummaryCard({
    required this.index,
    required this.section,
    required this.onDelete,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = section.mainImage != null;
    final videosCount = section.contentVideos.length;
    final imagesCount = section.contentImages.length;
    final totalContent = videosCount + imagesCount;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black12.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: Colors.grey.shade200),
        ),
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // صورة مصغرة
            SizedBox(
              width: 64,
              height: 64,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: hasImage
                    ? Image.file(
                        File(section.mainImage!.path),
                        fit: BoxFit.cover,
                      )
                    : Container(
                        color: Colors.deepPurple.shade50,
                        child: const Icon(
                          Icons.image_outlined,
                          color: Colors.deepPurple,
                          size: 28,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 10),

            // نصوص + شارات
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    section.title.isEmpty
                        ? "عنوان قسم غير محدد"
                        : section.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: "Cairo",
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    section.description.isEmpty
                        ? "وصف قصير للقسم يظهر هنا."
                        : section.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: "Cairo",
                      fontSize: 11.5,
                      color: Colors.black54,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      hasImage
                          ? _chip(icon: Icons.image, label: "صورة رئيسية مضافة")
                          : _chip(
                              icon: Icons.image_not_supported_outlined,
                              label: "بدون صورة رئيسية",
                              color: Colors.grey.shade400,
                            ),
                      _chip(
                        icon: Icons.collections,
                        label: totalContent == 0
                            ? "لا يوجد محتوى"
                            : "$totalContent محتوى ($videosCount فيديو، $imagesCount صورة)",
                        color: totalContent == 0
                            ? Colors.grey.shade400
                            : Colors.deepPurple,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // زر الحذف صغير على اليسار
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              tooltip: "حذف هذا القسم",
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip({required IconData icon, required String label, Color? color}) {
    final c = color ?? Colors.deepPurple;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: c),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontFamily: "Cairo", fontSize: 10.5, color: c),
          ),
        ],
      ),
    );
  }
}

/// محرر قسم جديد يُفتح عند الضغط على "إضافة قسم جديد"
class NewSectionEditor extends StatefulWidget {
  final void Function(SectionContent section) onSave;
  final VoidCallback onCancel;
  final SectionContent? initialSection;

  const NewSectionEditor({
    super.key,
    required this.onSave,
    required this.onCancel,
    this.initialSection,
  });

  @override
  State<NewSectionEditor> createState() => _NewSectionEditorState();
}

class _NewSectionEditorState extends State<NewSectionEditor> {
  final picker = ImagePicker();
  late final TextEditingController _titleController;
  late final TextEditingController _descController;
  XFile? _mainImage;
  final List<XFile> _videos = [];
  final List<XFile> _images = [];

  bool get _isEditing => widget.initialSection != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialSection;
    _titleController = TextEditingController(
      text: initial?.title ?? '',
    );
    _descController = TextEditingController(
      text: initial?.description ?? '',
    );
    _mainImage = initial?.mainImage;
    if (initial != null) {
      _videos.addAll(initial.contentVideos);
      _images.addAll(initial.contentImages);
    }
  }

  Future<void> _pickMainImage() async {
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _mainImage = picked);
    }
  }

  void _removeMainImage() {
    if (_mainImage == null) return;
    setState(() => _mainImage = null);
  }

  void _removeVideoAt(int index) {
    if (index < 0 || index >= _videos.length) return;
    setState(() => _videos.removeAt(index));
  }

  void _removeImageAt(int index) {
    if (index < 0 || index >= _images.length) return;
    setState(() => _images.removeAt(index));
  }

  Future<void> _pickVideo({ImageSource source = ImageSource.gallery}) async {
    final picked = await picker.pickVideo(source: source);
    if (picked != null) {
      setState(() => _videos.add(picked));
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await picker.pickImage(source: source);
    if (picked != null) {
      setState(() => _images.add(picked));
    }
  }

  void _showAttachmentsPickerSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'إضافة المرفقات',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13.5,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            ListTile(
              leading:
                  const Icon(Icons.photo_library, color: Colors.deepPurple),
              title: const Text(
                'صورة من الألبوم',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.deepPurple),
              title: const Text(
                'تصوير صورة',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.video_library, color: Colors.deepPurple),
              title: const Text(
                'فيديو من الألبوم',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickVideo(source: ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam, color: Colors.deepPurple),
              title: const Text(
                'تصوير فيديو',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickVideo(source: ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _compactInputDecoration({
    required String hintText,
    required IconData icon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(
        fontFamily: "Cairo",
        fontSize: 11,
        color: Colors.black45,
      ),
      prefixIcon: Icon(icon, size: 18),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }

  void _save() {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("يرجى إدخال عنوان واضح للقسم قبل الحفظ.")),
      );
      return;
    }
    final section = SectionContent(
      title: _titleController.text.trim(),
      description: _descController.text.trim(),
      mainImage: _mainImage,
      contentVideos: List<XFile>.from(_videos),
      contentImages: List<XFile>.from(_images),
    );
    widget.onSave(section);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.deepPurple.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // عنوان للمحرر
          Row(
            children: [
              Icon(
                _isEditing ? Icons.edit_outlined : Icons.add_circle_outline,
                color: Colors.deepPurple,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                _isEditing ? "تعديل القسم" : "إضافة قسم محتوى جديد",
                style: const TextStyle(
                  fontFamily: "Cairo",
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // عنوان القسم
          const Text(
            "عنوان القسم",
            style: TextStyle(
              fontFamily: "Cairo",
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          TextFormField(
            controller: _titleController,
            decoration: _compactInputDecoration(
              hintText: "اكتب عنوان القسم",
              icon: Icons.title,
            ),
            style: const TextStyle(fontSize: 12, fontFamily: "Cairo"),
          ),
          const SizedBox(height: 8),

          // وصف القسم
          const Text(
            "وصف قصير للقسم",
            style: TextStyle(
              fontFamily: "Cairo",
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          TextFormField(
            controller: _descController,
            maxLines: 2,
            decoration: _compactInputDecoration(
              hintText: "اكتب وصفًا قصيرًا للقسم",
              icon: Icons.description,
            ),
            style: const TextStyle(fontSize: 12, fontFamily: "Cairo"),
          ),
          const SizedBox(height: 10),

          // صورة رئيسية
          const Text(
            "الصورة الرئيسية",
            style: TextStyle(
              fontFamily: "Cairo",
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          GestureDetector(
            onTap: _pickMainImage,
            child: Container(
              width: double.infinity,
              height: 130,
              decoration: BoxDecoration(
                color: Colors.deepPurple.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.deepPurple.shade200),
              ),
              child: _mainImage == null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(
                          Icons.image_outlined,
                          size: 30,
                          color: Colors.deepPurple,
                        ),
                        SizedBox(height: 6),
                        Text(
                          "اضغط لاختيار صورة رئيسية لهذا القسم",
                          style: TextStyle(
                            fontFamily: "Cairo",
                            fontSize: 10.5,
                            color: Colors.deepPurple,
                          ),
                        ),
                      ],
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(
                            File(_mainImage!.path),
                            fit: BoxFit.cover,
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: InkWell(
                              onTap: _removeMainImage,
                              borderRadius: BorderRadius.circular(999),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 16),

          // محتوى الفيديو والصور
          const Text(
            "محتوى القسم (فيديوهات وصور)",
            style: TextStyle(
              fontFamily: "Cairo",
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _showAttachmentsPickerSheet,
              icon: const Icon(
                Icons.attachment_rounded,
                color: Colors.white,
                size: 16,
              ),
              label: const Text(
                "إضافة المرفقات",
                style: TextStyle(
                  color: Colors.white,
                  fontFamily: "Cairo",
                  fontSize: 11.5,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
            ),
          ),
          const SizedBox(height: 8),

          if (_videos.isNotEmpty || _images.isNotEmpty) ...[
            const SizedBox(height: 4),
            const Text(
              "المحتوى المضاف:",
              style: TextStyle(
                fontFamily: "Cairo",
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            GridView.builder(
              itemCount: _videos.length + _images.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemBuilder: (_, i) {
                final isVideo = i < _videos.length;
                final file = isVideo ? _videos[i] : _images[i - _videos.length];
                final name = file.name;
                final removeIndex = isVideo ? i : (i - _videos.length);

                return ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    children: [
                      if (isVideo)
                        Container(
                          color: Colors.black87,
                          child: Stack(
                            children: [
                              const Positioned.fill(
                                child: Icon(
                                  Icons.videocam,
                                  color: Colors.white24,
                                  size: 40,
                                ),
                              ),
                              const Center(
                                child: Icon(
                                  Icons.play_circle_fill,
                                  color: Colors.white,
                                  size: 32,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Image.file(
                          File(file.path),
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                        ),
                      Positioned(
                        left: 4,
                        right: 4,
                        bottom: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: "Cairo",
                              fontSize: 9,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      if (isVideo)
                        Positioned(
                          top: 4,
                          left: 4,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.videocam,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        )
                      else
                        Positioned(
                          top: 4,
                          left: 4,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.image,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: InkWell(
                          onTap: () {
                            if (isVideo) {
                              _removeVideoAt(removeIndex);
                            } else {
                              _removeImageAt(removeIndex);
                            }
                          },
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],

          const SizedBox(height: 16),

          Row(
            children: [
              TextButton(
                onPressed: widget.onCancel,
                child: const Text(
                  "إلغاء",
                  style: TextStyle(
                    fontFamily: "Cairo",
                    color: Colors.black54,
                    fontSize: 11.5,
                  ),
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save, color: Colors.white, size: 16),
                label: Text(
                  _isEditing ? "حفظ التعديلات" : "حفظ القسم",
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: "Cairo",
                    fontSize: 11.5,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
