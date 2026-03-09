import 'package:flutter/material.dart';
import 'package:nawafeth/services/api_client.dart';
import 'package:nawafeth/services/profile_service.dart';
import 'package:nawafeth/services/provider_services_service.dart';
import 'package:nawafeth/utils/debounced_save_runner.dart';

class ServiceDetailsStep extends StatefulWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;

  const ServiceDetailsStep({
    super.key,
    required this.onNext,
    required this.onBack,
  });

  @override
  State<ServiceDetailsStep> createState() => _ServiceDetailsStepState();
}

class _ServiceDetailsStepState extends State<ServiceDetailsStep> {
  final List<_ServiceItem> _services = [];
  final DebouncedSaveRunner _autoSaveRunner = DebouncedSaveRunner();

  int? _fallbackSubcategoryId;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isInitialized = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _services.add(_ServiceItem(isEditing: true));
    _attachItemListeners(_services.first);
    _loadInitialData();
  }

  @override
  void dispose() {
    for (final s in _services) {
      _detachItemListeners(s);
      s.dispose();
    }
    _autoSaveRunner.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    final results = await Future.wait([
      ProfileService.fetchProviderProfile(),
      ProviderServicesService.fetchMyServices(),
      ApiClient.get('/api/providers/me/subcategories/'),
    ]);
    if (!mounted) return;

    final profileResult = results[0] as ProfileResult<dynamic>;
    final servicesResp = results[1] as ApiResponse;
    final subcategoriesResp = results[2] as ApiResponse;

    bool acceptsUrgent = false;
    if (profileResult.isSuccess && profileResult.data != null) {
      final dynamic profile = profileResult.data;
      acceptsUrgent = (profile.acceptsUrgent as bool?) ?? false;
    }

    final subcategoryIds = _parseSubcategoryIds(subcategoriesResp.data);
    _fallbackSubcategoryId = subcategoryIds.isNotEmpty ? subcategoryIds.first : null;

    final serviceList = _parseServices(servicesResp.data);

    setState(() {
      _isInitialized = false;

      for (final s in _services) {
        _detachItemListeners(s);
        s.dispose();
      }
      _services.clear();

      if (serviceList.isNotEmpty) {
        for (final raw in serviceList) {
          final sub = raw['subcategory'];
          final subIdFromMap = sub is Map ? _toInt(sub['id']) : null;
          final item = _ServiceItem(
            id: _toInt(raw['id']),
            subcategoryId: subIdFromMap,
            initialName: (raw['title'] ?? '').toString(),
            initialDescription: (raw['description'] ?? '').toString(),
            isUrgent: acceptsUrgent,
            isEditing: false,
          );
          _services.add(item);
          _attachItemListeners(item);
        }
      } else {
        final first = _ServiceItem(
          isUrgent: acceptsUrgent,
          isEditing: true,
          subcategoryId: _fallbackSubcategoryId,
        );
        _services.add(first);
        _attachItemListeners(first);
      }

      _isLoading = false;
      _saveError = servicesResp.isSuccess
          ? null
          : (servicesResp.error ?? profileResult.error ?? 'تعذر تحميل بيانات الخدمة');
      _isInitialized = true;
    });
  }

  void _attachItemListeners(_ServiceItem item) {
    item.name.addListener(_onItemChanged);
    item.description.addListener(_onItemChanged);
  }

  void _detachItemListeners(_ServiceItem item) {
    item.name.removeListener(_onItemChanged);
    item.description.removeListener(_onItemChanged);
  }

  void _onItemChanged() {
    if (!_isInitialized) return;
    _queueAutoSave();
  }

  void _queueAutoSave() {
    if (!_isInitialized) return;
    _autoSaveRunner.schedule(_saveToApi);
  }

  Future<void> _saveToApi() async {
    final payload = <String, dynamic>{
      'accepts_urgent': _services.any((s) => s.isUrgent),
    };

    if (!mounted) return;
    setState(() {
      _isSaving = true;
    });

    final result = await ProfileService.updateProviderProfile(payload);
    if (!mounted) return;

    setState(() {
      _isSaving = false;
      _saveError = result.isSuccess ? null : (result.error ?? 'فشل الحفظ');
    });
  }

  void _addService() {
    final item = _ServiceItem(
      isUrgent: false,
      isEditing: true, // الخدمة الجديدة تُفتح في وضع تعديل مباشرة
      subcategoryId: _fallbackSubcategoryId,
    );
    _attachItemListeners(item);
    setState(() {
      _services.add(item);
    });
  }

  void _toggleEdit(int index, bool editing) {
    setState(() {
      _services[index].isEditing = editing;
    });
  }

  Future<void> _removeService(int index) async {
    if (_services.length == 1) {
      _showSnack("يجب أن يكون لديك خدمة واحدة على الأقل في ملفك.");
      return;
    }
    final item = _services[index];

    if (item.id != null) {
      final res = await ProviderServicesService.deleteService(item.id!);
      if (!mounted) return;
      if (!res.isSuccess) {
        _showSnack(res.error ?? 'تعذر حذف الخدمة', isError: true);
        return;
      }
    }

    setState(() {
      _detachItemListeners(item);
      item.dispose();
      _services.removeAt(index);
    });
    _queueAutoSave();
    _showSnack("تم حذف الخدمة بنجاح.");
  }

  Future<void> _saveService(int index) async {
    final item = _services[index];
    final name = item.name.text.trim();
    final desc = item.description.text.trim();

    if (name.isEmpty) {
      _showSnack("رجاء أدخل اسمًا واضحًا للخدمة قبل الحفظ.");
      return;
    }

    final subcategoryId = item.subcategoryId ?? _fallbackSubcategoryId;
    if (subcategoryId == null) {
      _showSnack("لا يمكن حفظ الخدمة بدون تصنيف فرعي. حدّد التصنيف أولًا.", isError: true);
      return;
    }

    final payload = <String, dynamic>{
      'title': name,
      'description': desc,
      'subcategory_id': subcategoryId,
      'is_active': true,
    };

    if (!mounted) return;
    setState(() => _isSaving = true);
    final res = item.id != null
        ? await ProviderServicesService.updateService(item.id!, payload)
        : await ProviderServicesService.createService(payload);
    if (!mounted) return;
    setState(() => _isSaving = false);

    if (!res.isSuccess) {
      _showSnack(res.error ?? "تعذر حفظ الخدمة", isError: true);
      return;
    }

    final data = res.dataAsMap;
    if (data != null) {
      item.id = _toInt(data['id']) ?? item.id;
      final sub = data['subcategory'];
      final subId = sub is Map ? _toInt(sub['id']) : null;
      item.subcategoryId = subId ?? subcategoryId;
    } else {
      item.subcategoryId = subcategoryId;
    }

    setState(() {
      item.isEditing = false;
    });
    _queueAutoSave();

    _showSnack("تم حفظ بيانات الخدمة ${index + 1}.");
  }

  Future<void> _handleNext() async {
    final hasValidService = _services.any((s) => s.name.text.trim().isNotEmpty);

    if (!hasValidService) {
      _showSnack("أضف على الأقل خدمة واحدة تحتوي على اسم قبل المتابعة.");
      return;
    }

    // 👇 هنا لاحقًا ممكن تجمع وترسل للباكند
    // final data = _services
    //     .where((s) => s.name.text.trim().isNotEmpty)
    //     .map((s) => {
    //       "name": s.name.text.trim(),
    //       "description": s.description.text.trim(),
    //       "price": s.price.text.trim(),
    //       "is_urgent": s.isUrgent,
    //     })
    //     .toList();

    await _autoSaveRunner.flush();
    widget.onNext();
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 14),
              _buildInfoCard(),
              const SizedBox(height: 10),
              _buildSaveStatus(),
              const SizedBox(height: 18),

              // ✅ قائمة الكروت (ملخّصة أو تحرير حسب الحالة)
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Center(
                    child: CircularProgressIndicator(color: Colors.deepPurple),
                  ),
                ),
              if (!_isLoading)
                ...List.generate(
                  _services.length,
                  (index) => Padding(
                    padding: EdgeInsets.only(
                      bottom: index == _services.length - 1 ? 0 : 16,
                    ),
                    child: _buildServiceCard(index),
                  ),
                ),

              const SizedBox(height: 18),

              // ✅ زر إضافة خدمة
              Center(
                child: OutlinedButton.icon(
                  onPressed: _isLoading ? null : _addService,
                  icon: const Icon(
                    Icons.add_circle_outline,
                    color: Colors.deepPurple,
                    size: 20,
                  ),
                  label: const Text(
                    "إضافة خدمة أخرى",
                    style: TextStyle(
                      fontFamily: "Cairo",
                      color: Colors.deepPurple,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    side: BorderSide(color: Colors.deepPurple.withValues(alpha: 0.7)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 26),

              // ✅ أزرار السابق / التالي
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await _autoSaveRunner.flush();
                        widget.onBack();
                      },
                      icon: const Icon(
                        Icons.arrow_back_ios_new,
                        size: 16,
                        color: Colors.deepPurple,
                      ),
                      label: const Text(
                        "السابق",
                        style: TextStyle(
                          fontFamily: "Cairo",
                          color: Colors.deepPurple,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        side: BorderSide(
                          color: Colors.deepPurple.withValues(alpha: 0.7),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _handleNext,
                      icon: const Icon(
                        Icons.arrow_forward_ios,
                        size: 16,
                        color: Colors.white,
                      ),
                      label: const Text(
                        "التالي",
                        style: TextStyle(
                          fontFamily: "Cairo",
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// عنوان + وصف بسيط للخطوة
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
            style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.black54),
          ),
        ],
      );
    }

    if (_saveError != null) {
      return Text(
        _saveError!,
        style: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 12,
          color: Colors.redAccent,
        ),
      );
    }

    return const SizedBox.shrink();
  }

  /// عنوان + وصف بسيط للخطوة
  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Text(
          "الخدمات التي تقدمها",
          style: TextStyle(
            fontFamily: "Cairo",
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.deepPurple,
          ),
        ),
        SizedBox(height: 6),
        Text(
          "أضف الخدمات الأساسية التي ترغب أن يراها العميل في ملفك.",
          style: TextStyle(
            fontFamily: "Cairo",
            fontSize: 13,
            color: Colors.black54,
          ),
        ),
      ],
    );
  }

  /// كرت إرشادي في الأعلى
  Widget _buildInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F4FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Icon(Icons.info_outline, color: Colors.deepPurple, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              "بعد حفظ الخدمة، ستظهر في كرت ملخّص يحتوي على الاسم، نبذة قصيرة، "
              "وحالة كونها خدمة عاجلة أم لا. يمكنك تعديل أو حذف أي خدمة في أي وقت.",
              style: TextStyle(
                fontFamily: "Cairo",
                fontSize: 12,
                color: Colors.black87,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// كرت خدمة واحدة: إمّا ملخّص أو وضع تحرير
  Widget _buildServiceCard(int index) {
    final item = _services[index];

    if (item.isEditing) {
      // 🔧 وضع التحرير
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black12.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 6),
            ),
          ],
          border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // الهيدر
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.edit_outlined,
                        size: 16,
                        color: Colors.deepPurple,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        "تعديل بيانات الخدمة ${index + 1}",
                        style: const TextStyle(
                          fontFamily: "Cairo",
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.deepPurple,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => _removeService(index),
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.redAccent,
                    size: 20,
                  ),
                  tooltip: "حذف هذه الخدمة",
                ),
              ],
            ),
            const SizedBox(height: 12),

            _buildFieldLabel("اسم الخدمة"),
            const SizedBox(height: 6),
            _buildTextField(
              controller: item.name,
              hint: "مثلاً: تطوير موقع تعريفي لشركة",
              icon: Icons.home_repair_service_outlined,
            ),
            const SizedBox(height: 12),

            _buildFieldLabel("وصف مختصر عن الخدمة"),
            const SizedBox(height: 6),
            _buildTextField(
              controller: item.description,
              hint: "صف بإيجاز ما الذي تقدمه في هذه الخدمة.",
              icon: Icons.description_outlined,
              maxLines: 3,
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Switch(
                  value: item.isUrgent,
                  activeThumbColor: Colors.deepPurple,
                  onChanged: (val) {
                    setState(() {
                      item.isUrgent = val;
                    });
                    _queueAutoSave();
                  },
                ),
                const SizedBox(width: 4),
                const Text(
                  "تُقدَّم كخدمة عاجلة",
                  style: TextStyle(fontFamily: "Cairo", fontSize: 12.5),
                ),
              ],
            ),

            const SizedBox(height: 6),

            Row(
              children: [
                TextButton(
                  onPressed: () => _toggleEdit(index, false),
                  child: const Text(
                    "إلغاء",
                    style: TextStyle(
                      fontFamily: "Cairo",
                      color: Colors.black54,
                    ),
                  ),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () => _saveService(index),
                  icon: const Icon(
                    Icons.check_circle,
                    size: 18,
                    color: Colors.white,
                  ),
                  label: const Text(
                    "حفظ",
                    style: TextStyle(
                      fontFamily: "Cairo",
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // 📦 وضع الملخّص (الكرت المستطيل بعد الحفظ)
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // العنوان + شارة عاجلة
          Row(
            children: [
              Expanded(
                child: Text(
                  item.name.text.isEmpty
                      ? "خدمة بدون اسم"
                      : item.name.text.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: "Cairo",
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
              ),
              if (item.isUrgent) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.bolt, size: 14, color: Colors.redAccent),
                      SizedBox(width: 4),
                      Text(
                        "خدمة عاجلة",
                        style: TextStyle(
                          fontFamily: "Cairo",
                          fontSize: 11.5,
                          color: Colors.redAccent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),

          // وصف مختصر (جزء فقط مع نقاط واختصار)
          Text(
            item.description.text.isEmpty
                ? "لا يوجد وصف بعد — يمكنك إضافة وصف مختصر يوضح تفاصيل هذه الخدمة."
                : item.description.text.trim(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: "Cairo",
              fontSize: 12.5,
              color: Colors.black87,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "… وصف تفصيلي أطول يظهر داخل ملفك عند زيارة العميل لصفحة خدمتك.",
            style: TextStyle(
              fontFamily: "Cairo",
              fontSize: 11,
              color: Colors.black54,
            ),
          ),

          const SizedBox(height: 10),

          Row(
            children: [
              TextButton.icon(
                onPressed: () => _toggleEdit(index, true),
                icon: const Icon(
                  Icons.edit_outlined,
                  size: 18,
                  color: Colors.deepPurple,
                ),
                label: const Text(
                  "تعديل",
                  style: TextStyle(
                    fontFamily: "Cairo",
                    color: Colors.deepPurple,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                  onPressed: () => _removeService(index),
                icon: const Icon(
                  Icons.delete_outline,
                  color: Colors.redAccent,
                  size: 20,
                ),
                tooltip: "حذف هذه الخدمة",
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFieldLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: "Cairo",
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
        color: Colors.deepPurple,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    IconData? icon,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: const TextStyle(fontFamily: "Cairo", fontSize: 13.5),
      decoration: InputDecoration(
        prefixIcon: icon != null ? Icon(icon, color: Colors.deepPurple) : null,
        hintText: hint,
        hintStyle: const TextStyle(
          fontFamily: "Cairo",
          fontSize: 13,
          color: Colors.grey,
        ),
        filled: true,
        fillColor: const Color(0xFFF9F7FF),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.deepPurple.withValues(alpha: 0.35)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.deepPurple.withValues(alpha: 0.25)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide(color: Colors.deepPurple, width: 1.4),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _parseServices(dynamic data) {
    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    if (data is Map && data['results'] is List) {
      final list = data['results'] as List;
      return list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
  }

  List<int> _parseSubcategoryIds(dynamic data) {
    if (data is Map && data['subcategory_ids'] is List) {
      final ids = data['subcategory_ids'] as List;
      return ids.map(_toInt).whereType<int>().toList();
    }
    return [];
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }
}

/// عنصر داخلي لإدارة الكنترولات لكل خدمة
class _ServiceItem {
  int? id;
  int? subcategoryId;
  final TextEditingController name;
  final TextEditingController description;
  bool isUrgent;
  bool isEditing;

  _ServiceItem({
    this.id,
    this.subcategoryId,
    String? initialName,
    String? initialDescription,
    this.isUrgent = false,
    this.isEditing = false,
  }) : name = TextEditingController(text: initialName ?? ''),
       description = TextEditingController(text: initialDescription ?? '');

  void dispose() {
    name.dispose();
    description.dispose();
  }
}
