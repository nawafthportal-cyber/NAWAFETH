import 'package:flutter/material.dart';
import '../../../services/home_service.dart';
import '../../../models/category_model.dart';

class ServiceClassificationStep extends StatefulWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;
  final Function(double)? onValidationChanged;
  final Map<String, dynamic>? registrationData;

  const ServiceClassificationStep({
    super.key,
    required this.onNext,
    required this.onBack,
    this.onValidationChanged,
    this.registrationData,
  });

  @override
  State<ServiceClassificationStep> createState() =>
      _ServiceClassificationStepState();
}

class _ServiceClassificationStepState extends State<ServiceClassificationStep> {
  String? selectedMainCategory;
  List<String> selectedSubCategories = [];
  List<String> selectedUrgentServices = [];
  bool urgentRequests = false;
  bool showSuccessMessage = false;

  // API-loaded categories
  List<CategoryModel> _apiCategories = [];
  bool _isCategoriesLoading = true;
  String? _categoriesError;

  List<String> get mainCategories =>
      _apiCategories.map((c) => c.name).toList();

  Map<String, List<String>> get subCategoryMap {
    final map = <String, List<String>>{};
    for (final cat in _apiCategories) {
      map[cat.name] = cat.subcategories.map((s) => s.name).toList();
    }
    return map;
  }

  final TextEditingController mainSuggestionController =
      TextEditingController();
  final TextEditingController subSuggestionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCategories();
    // تأجيل الاستدعاء الأول حتى بعد اكتمال البناء
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _validateForm();
    });
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await HomeService.fetchCategories();
      if (mounted) {
        setState(() {
          _apiCategories = categories;
          _isCategoriesLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCategoriesLoading = false;
          _categoriesError = 'فشل تحميل التصنيفات';
        });
      }
    }
  }

  void _validateForm() {
    // حساب النسبة بناءً على الحقول المملوءة
    double completionPercent = 0.0;
    
    // التصنيف الرئيسي (50% من الصفحة)
    if (selectedMainCategory != null) {
      completionPercent += 0.5;
    }
    
    // التخصصات الفرعية (50% من الصفحة)
    if (selectedSubCategories.isNotEmpty) {
      completionPercent += 0.5;
    }
    
    widget.onValidationChanged?.call(completionPercent);
  }

  @override
  void dispose() {
    mainSuggestionController.dispose();
    subSuggestionController.dispose();
    super.dispose();
  }

  // ==========================
  //   شيت اختيار التصنيف الرئيسي
  // ==========================
  Future<void> _openMainCategorySheet() async {
    final theme = Theme.of(context);
    String? tempSelected = selectedMainCategory;

    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        final height = MediaQuery.of(context).size.height * 0.7;
        return Center(
          child: Container(
            height: height,
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: StatefulBuilder(
              builder: (context, setSheetState) {
                return Column(
                  children: [
                    const SizedBox(height: 12),
                    // مقبض سحب
                    Container(
                      width: 50,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(100),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        "اختر التصنيف الرئيسي",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        "اختر المجال الأنسب لخدماتك ليظهر لعملائك بشكل واضح.",
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.black54,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ),
                    const Divider(height: 24),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        itemCount: mainCategories.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 4),
                        itemBuilder: (context, index) {
                          final item = mainCategories[index];
                          final selected = tempSelected == item;
                          return ListTile(
                            leading: Icon(
                              Icons.circle,
                              size: 10,
                              color:
                                  selected
                                      ? theme.colorScheme.primary
                                      : Colors.grey.shade400,
                            ),
                            title: Text(
                              item,
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight:
                                    selected
                                        ? FontWeight.bold
                                        : FontWeight.w500,
                              ),
                            ),
                            trailing:
                                selected
                                    ? Icon(
                                      Icons.check_circle,
                                      color: theme.colorScheme.primary,
                                    )
                                    : const Icon(
                                      Icons.chevron_left,
                                      color: Colors.grey,
                                    ),
                            onTap: () {
                              setSheetState(() {
                                tempSelected = item;
                              });
                            },
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.grey.shade700,
                                side: BorderSide(color: Colors.grey.shade300),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: const Text("إلغاء"),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.pop(context, tempSelected);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.colorScheme.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: const Text("تأكيد الاختيار"),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );

    if (selected != null && selected.isNotEmpty) {
      setState(() {
        selectedMainCategory = selected;
        selectedSubCategories.clear();
        selectedUrgentServices.clear();
        _validateForm();
      });
    }
  }

  // ==========================
  //   شيت اختيار التخصصات الفرعية
  // ==========================
  Future<void> _openSubCategoryBottomSheet() async {
    if (selectedMainCategory == null) return;

    final theme = Theme.of(context);
    final items = subCategoryMap[selectedMainCategory!] ?? [];
    List<String> tempSelected = List.from(selectedSubCategories);

    final selected = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        final height = MediaQuery.of(context).size.height * 0.7;
        return Center(
          child: Container(
            height: height,
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: StatefulBuilder(
              builder: (context, setSheetState) {
                return Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 50,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(100),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        "اختر التخصصات الفرعية",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        selectedMainCategory ?? "",
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black54,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ),
                    const Divider(height: 24),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 4),
                        itemBuilder: (context, index) {
                          final e = items[index];
                          final selected = tempSelected.contains(e);
                          return CheckboxListTile(
                            value: selected,
                            title: Text(
                              e,
                              style: const TextStyle(fontFamily: 'Cairo'),
                            ),
                            activeColor: theme.colorScheme.primary,
                            onChanged: (val) {
                              setSheetState(() {
                                if (val == true) {
                                  tempSelected.add(e);
                                } else {
                                  tempSelected.remove(e);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.grey.shade700,
                                side: BorderSide(color: Colors.grey.shade300),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: const Text("إلغاء"),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.pop(context, tempSelected);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.colorScheme.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: const Text("تأكيد"),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );

    if (selected != null) {
      setState(() {
        selectedSubCategories = selected;
        _validateForm();
      });
    }
  }

  // ==========================
  //   شيت اختيار الخدمات العاجلة
  // ==========================
  Future<void> _openUrgentServicesBottomSheet() async {
    final theme = Theme.of(context);
    final items = selectedSubCategories;
    List<String> tempSelected = List.from(selectedUrgentServices);

    if (items.isEmpty) return;

    final selected = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        final height = MediaQuery.of(context).size.height * 0.7;
        return Center(
          child: Container(
            height: height,
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: StatefulBuilder(
              builder: (context, setSheetState) {
                return Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 50,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(100),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        "اختر الخدمات العاجلة",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        "هذه الخدمات تظهر في قسم الطلبات العاجلة للعميل.",
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.black54,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ),
                    const Divider(height: 24),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 4),
                        itemBuilder: (context, index) {
                          final e = items[index];
                          final selected = tempSelected.contains(e);
                          return CheckboxListTile(
                            value: selected,
                            title: Text(
                              e,
                              style: const TextStyle(fontFamily: 'Cairo'),
                            ),
                            activeColor: theme.colorScheme.primary,
                            onChanged: (val) {
                              setSheetState(() {
                                if (val == true) {
                                  tempSelected.add(e);
                                } else {
                                  tempSelected.remove(e);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.grey.shade700,
                                side: BorderSide(color: Colors.grey.shade300),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: const Text("إلغاء"),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.pop(context, tempSelected);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.colorScheme.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: const Text("تأكيد"),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );

    if (selected != null) {
      setState(() => selectedUrgentServices = selected);
    }
  }

  // ==========================
  //   Dialog الاقتراح
  // ==========================
  void _openSuggestionDialog() {
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text(
              "اقتراح تصنيف جديد",
              style: TextStyle(fontFamily: 'Cairo'),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: mainSuggestionController,
                  decoration: const InputDecoration(
                    labelText: "اقتراح تصنيف رئيسي",
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: subSuggestionController,
                  decoration: const InputDecoration(
                    labelText: "اقتراح تخصص فرعي",
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("إلغاء"),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  setState(() => showSuccessMessage = true);
                },
                child: const Text("إرسال"),
              ),
            ],
          ),
    );
  }

  // ==========================
  //   الواجهة الرئيسية
  // ==========================
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "تصنيف الاختصاص",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              fontFamily: 'Cairo',
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "ساعد عملاءك على فهم ما تقدمه باختيار التصنيف المناسب والتخصصات الفرعية.",
            style: TextStyle(
              fontSize: 13,
              color: Colors.black54,
              fontFamily: 'Cairo',
            ),
          ),
          const SizedBox(height: 16),
          if (_isCategoriesLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_categoriesError != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Text(
                      _categoriesError!,
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        color: Colors.red,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _isCategoriesLoading = true;
                          _categoriesError = null;
                        });
                        _loadCategories();
                      },
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            )
          else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
              border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // التصنيف الرئيسي
                _buildLabel("التصنيف الرئيسي"),
                GestureDetector(
                  onTap: _openMainCategorySheet,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.category_outlined,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            selectedMainCategory ?? "اختر تصنيفًا رئيسيًا",
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 14,
                              color:
                                  selectedMainCategory == null
                                      ? Colors.grey
                                      : Colors.black87,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(Icons.expand_more, color: Colors.grey),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                if (selectedMainCategory != null) ...[
                  _buildLabel("التخصصات الفرعية"),
                  GestureDetector(
                    onTap: _openSubCategoryBottomSheet,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.list_alt_outlined,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              selectedSubCategories.isEmpty
                                  ? 'اضغط لاختيار التخصصات'
                                  : selectedSubCategories.join("، "),
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 14,
                                color:
                                    selectedSubCategories.isEmpty
                                        ? Colors.grey
                                        : Colors.black87,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Icon(Icons.expand_more, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (selectedSubCategories.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children:
                          selectedSubCategories
                              .map(
                                (e) => Chip(
                                  label: Text(
                                    e,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontFamily: 'Cairo',
                                    ),
                                  ),
                                  deleteIcon: const Icon(Icons.close, size: 16),
                                  onDeleted: () {
                                    setState(() {
                                      selectedSubCategories.remove(e);
                                      _validateForm();
                                    });
                                  },
                                ),
                              )
                              .toList(),
                    ),
                  const SizedBox(height: 16),
                ],

                // الطلبات العاجلة
                SwitchListTile(
                  value: urgentRequests,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    "استقبال الطلبات العاجلة",
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text(
                    "سيتم إبرازك عند اختيار العميل لخدمة عاجلة.",
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      color: Colors.black54,
                    ),
                  ),
                  activeThumbColor: theme.colorScheme.primary,
                  onChanged: (value) {
                    setState(() {
                      urgentRequests = value;
                      selectedUrgentServices.clear();
                    });
                  },
                ),

                if (urgentRequests && selectedSubCategories.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _buildLabel("الخدمات العاجلة"),
                  GestureDetector(
                    onTap: _openUrgentServicesBottomSheet,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.bolt_outlined,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              selectedUrgentServices.isEmpty
                                  ? 'اضغط لاختيار الخدمات العاجلة'
                                  : selectedUrgentServices.join("، "),
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 14,
                                color:
                                    selectedUrgentServices.isEmpty
                                        ? Colors.grey
                                        : Colors.black87,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Icon(Icons.expand_more, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (selectedUrgentServices.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children:
                          selectedUrgentServices
                              .map(
                                (e) => Chip(
                                  label: Text(
                                    e,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontFamily: 'Cairo',
                                    ),
                                  ),
                                  deleteIcon: const Icon(Icons.close, size: 16),
                                  onDeleted:
                                      () => setState(
                                        () => selectedUrgentServices.remove(e),
                                      ),
                                ),
                              )
                              .toList(),
                    ),
                ],

                const SizedBox(height: 20),
                const Text(
                  "إذا لم تجد تصنيف خدماتك، يمكنك اقتراح تصنيف جديد وسيتم مراجعته من قبل الفريق المعني.",
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'Cairo',
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _openSuggestionDialog,
                    icon: const Icon(Icons.add),
                    label: const Text("اقتراح تصنيف جديد"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color.fromARGB(255, 124, 63, 181),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                if (showSuccessMessage) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      "تم إرسال الطلب وسيتم مراجعته من قبل الفريق، وسيتم إبلاغك حال قبوله.",
                      style: TextStyle(fontSize: 13, fontFamily: 'Cairo'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back_ios_new),
                  label: const Text("السابق"),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    // حفظ بيانات التصنيف في خريطة التسجيل
                    final subcategoryIds = <int>[];
                    for (final cat in _apiCategories) {
                      for (final sub in cat.subcategories) {
                        if (selectedSubCategories.contains(sub.name)) {
                          subcategoryIds.add(sub.id);
                        }
                      }
                    }
                    widget.registrationData?['subcategory_ids'] = subcategoryIds;
                    widget.registrationData?['accepts_urgent'] = urgentRequests;
                    widget.onNext();
                  },
                  icon: const Icon(Icons.arrow_forward_ios),
                  label: const Text("التالي"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
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
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 15,
          fontFamily: 'Cairo',
        ),
      ),
    );
  }
}
