// ignore_for_file: unused_element
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:nawafeth/services/provider_services_service.dart';
import 'package:nawafeth/widgets/platform_top_bar.dart';

class ServicesTab extends StatefulWidget {
  const ServicesTab({super.key});

  @override
  State<ServicesTab> createState() => _ServicesTabState();
}

class _ServicesTabState extends State<ServicesTab> {
  // ────── حالة التحميل ──────
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  List<Map<String, dynamic>> services = [];
  List<Map<String, dynamic>> _categories = [];

  // ────── تصنيفات: رئيسي → فرعي (من API) ──────
  Map<String, List<Map<String, dynamic>>> categoryMap = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    // جلب التصنيفات + الخدمات بشكل متوازي
    final results = await Future.wait([
      ProviderServicesService.fetchCategories(),
      ProviderServicesService.fetchMyServices(),
    ]);

    if (!mounted) return;

    // التصنيفات
    final catRes = results[0];
    if (catRes.isSuccess && catRes.dataAsList != null) {
      _categories = catRes.dataAsList!.cast<Map<String, dynamic>>();
      categoryMap = {};
      for (final cat in _categories) {
        final name = cat['name'] as String? ?? '';
        final subs = (cat['subcategories'] as List<dynamic>?)
                ?.cast<Map<String, dynamic>>() ??
            [];
        categoryMap[name] = subs;
      }
    }

    // الخدمات
    final svcRes = results[1];
    if (svcRes.isSuccess) {
      final list = svcRes.dataAsList ?? (svcRes.dataAsMap?['results'] as List?) ?? [];
      services = list.cast<Map<String, dynamic>>();
    } else if (!silent) {
      setState(() {
        _isLoading = false;
        _errorMessage = svcRes.error ?? 'تعذر جلب الخدمات';
      });
      return;
    }

    setState(() => _isLoading = false);
  }

  /// حذف خدمة
  Future<void> _deleteService(int index) async {
    final svc = services[index];
    final id = svc['id'] as int?;
    if (id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف الخدمة', style: TextStyle(fontFamily: 'Cairo')),
          content: Text(
            'هل تريد حذف "${svc['title']}"؟',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حذف',
                  style: TextStyle(fontFamily: 'Cairo', color: Colors.red)),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    final res = await ProviderServicesService.deleteService(id);
    if (!mounted) return;

    if (res.isSuccess) {
      setState(() => services.removeAt(index));
      _showSnack('تم حذف الخدمة');
    } else {
      _showSnack(res.error ?? 'فشل الحذف', isError: true);
    }
  }

  void _editService(int index) {
    final item = services[index];
    final svcId = item['id'] as int?;

    // بيانات الخدمة من API
    final subcategory = item['subcategory'] as Map<String, dynamic>?;
    final categoryInSub = subcategory?['category'] as Map<String, dynamic>?;
    String selectedMain = categoryInSub?['name'] as String? ?? '';
    int? selectedSubId = subcategory?['id'] as int?;
    String title = item['title'] as String? ?? '';
    String description = item['description'] as String? ?? '';
    String priceFrom = (item['price_from'] ?? '').toString();
    String priceTo = (item['price_to'] ?? '').toString();
    String priceUnit = item['price_unit'] as String? ?? 'fixed';
    bool isActive = item['is_active'] as bool? ?? true;
    bool acceptsUrgent = item['accepts_urgent'] as bool? ?? false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          left: 20,
          right: 20,
          top: 20,
        ),
        child: StatefulBuilder(
          builder: (context, setModalState) {
            final currentSubList = categoryMap[selectedMain] ?? [];

            return Directionality(
              textDirection: TextDirection.rtl,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Text(
                        svcId != null ? 'تعديل الخدمة' : 'إضافة خدمة جديدة',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Colors.deepPurple,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    _buildLabel("التصنيف الرئيسي"),
                    DropdownButtonFormField<String>(
                      initialValue: categoryMap.containsKey(selectedMain) ? selectedMain : null,
                      decoration: _inputDecoration(),
                      items: categoryMap.keys
                          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                          .toList(),
                      onChanged: (val) {
                        setModalState(() {
                          selectedMain = val!;
                          selectedSubId = null;
                        });
                      },
                    ),
                    const SizedBox(height: 12),

                    _buildLabel("التصنيف الفرعي"),
                    DropdownButtonFormField<int>(
                      initialValue: currentSubList.any((s) => s['id'] == selectedSubId)
                          ? selectedSubId
                          : null,
                      decoration: _inputDecoration(),
                      items: currentSubList
                          .map((s) => DropdownMenuItem<int>(
                                value: s['id'] as int,
                                child: Text(s['name'] as String? ?? ''),
                              ))
                          .toList(),
                      onChanged: (val) {
                        setModalState(() => selectedSubId = val);
                      },
                    ),
                    const SizedBox(height: 12),

                    _buildLabel("اسم الخدمة"),
                    TextFormField(
                      initialValue: title,
                      onChanged: (val) => title = val,
                      decoration: _inputDecoration(hint: "مثال: استشارة قانونية"),
                    ),
                    const SizedBox(height: 12),

                    _buildLabel("وصف الخدمة"),
                    TextFormField(
                      initialValue: description,
                      onChanged: (val) => description = val,
                      maxLines: 3,
                      decoration: _inputDecoration(hint: "وصف مختصر للخدمة"),
                    ),
                    const SizedBox(height: 12),

                    _buildLabel("نوع التسعير"),
                    DropdownButtonFormField<String>(
                      initialValue: priceUnit,
                      decoration: _inputDecoration(),
                      items: const [
                        DropdownMenuItem(value: 'fixed', child: Text('سعر ثابت')),
                        DropdownMenuItem(value: 'starting_from', child: Text('يبدأ من')),
                        DropdownMenuItem(value: 'hour', child: Text('بالساعة')),
                        DropdownMenuItem(value: 'day', child: Text('باليوم')),
                        DropdownMenuItem(value: 'negotiable', child: Text('قابل للتفاوض')),
                      ],
                      onChanged: (val) =>
                          setModalState(() => priceUnit = val ?? 'fixed'),
                    ),

                    if (priceUnit != 'negotiable') ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildLabel("السعر من"),
                                TextFormField(
                                  initialValue: priceFrom,
                                  keyboardType: TextInputType.number,
                                  onChanged: (val) => priceFrom = val,
                                  decoration: _inputDecoration(hint: "0.00"),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildLabel("السعر إلى"),
                                TextFormField(
                                  initialValue: priceTo,
                                  keyboardType: TextInputType.number,
                                  onChanged: (val) => priceTo = val,
                                  decoration: _inputDecoration(hint: "0.00"),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.deepPurple.withValues(alpha: 0.10),
                        ),
                      ),
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'تفعيل استقبال الطلبات العاجلة لهذا التصنيف',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        subtitle: const Text(
                          'يطبّق هذا الإعداد على التصنيف الفرعي المحدد فقط، ويمكنك تغييره لاحقًا من نفس الشاشة.',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            height: 1.45,
                          ),
                        ),
                        value: acceptsUrgent,
                        activeThumbColor: Colors.deepPurple,
                        onChanged: (val) =>
                            setModalState(() => acceptsUrgent = val),
                      ),
                    ),

                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('الخدمة مفعلة',
                          style: TextStyle(fontFamily: 'Cairo')),
                      value: isActive,
                      activeThumbColor: Colors.deepPurple,
                      onChanged: (val) => setModalState(() => isActive = val),
                    ),

                    const SizedBox(height: 20),
                    Center(
                      child: _isSaving
                          ? const CircularProgressIndicator(color: Colors.deepPurple)
                          : ElevatedButton.icon(
                              onPressed: () async {
                                if (selectedSubId == null) {
                                  _showSnack('يرجى اختيار التصنيف الفرعي',
                                      isError: true);
                                  return;
                                }
                                if (title.trim().isEmpty) {
                                  _showSnack('أدخل اسم الخدمة', isError: true);
                                  return;
                                }

                                final payload = <String, dynamic>{
                                  'title': title.trim(),
                                  'description': description.trim(),
                                  'subcategory_id': selectedSubId,
                                  'price_unit': priceUnit,
                                  'is_active': isActive,
                                  'accepts_urgent': acceptsUrgent,
                                };

                                if (priceUnit != 'negotiable') {
                                  final pf = double.tryParse(priceFrom);
                                  final pt = double.tryParse(priceTo);
                                  if (pf != null) payload['price_from'] = pf;
                                  if (pt != null) payload['price_to'] = pt;
                                }

                                setModalState(() {});
                                setState(() => _isSaving = true);

                                final res = svcId != null
                                    ? await ProviderServicesService.updateService(
                                        svcId, payload)
                                    : await ProviderServicesService.createService(
                                        payload);

                                if (!mounted) return;
                                setState(() => _isSaving = false);

                                if (res.isSuccess) {
                                  if (context.mounted) Navigator.pop(context);
                                  _showSnack(svcId != null
                                      ? 'تم تحديث الخدمة بنجاح'
                                      : 'تم إضافة الخدمة بنجاح');
                                  _loadData(silent: true);
                                } else {
                                  _showSnack(
                                      res.error ?? 'فشل في الحفظ',
                                      isError: true);
                                }
                              },
                              icon: const Icon(Icons.save, color: Colors.white),
                              label: Text(
                                svcId != null ? "حفظ التعديلات" : "إضافة الخدمة",
                                style: const TextStyle(color: Colors.white),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.deepPurple,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                  horizontal: 24,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _addNewService() {
    final emptyService = <String, dynamic>{
      'title': '',
      'description': '',
      'price_from': null,
      'price_to': null,
      'price_unit': 'fixed',
      'is_active': true,
      'accepts_urgent': false,
      'subcategory': null,
    };
    services.add(emptyService);
    _editService(services.length - 1);
    services.removeLast();
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(msg, style: const TextStyle(fontFamily: 'Cairo')),
            ),
          ],
        ),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'حدث خطأ',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 14,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh, color: Colors.white),
              label: const Text(
                'إعادة المحاولة',
                style: TextStyle(fontFamily: 'Cairo', color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIntroCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.deepPurple.withValues(alpha: 0.10),
            const Color(0xFF0EA5A4).withValues(alpha: 0.08),
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.12)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'التصنيفات والخدمات',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: Colors.deepPurple,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'أضف تخصصك وفَعِّل الطلبات العاجلة للتصنيفات المناسبة فقط',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
          ),
          SizedBox(height: 6),
          Text(
            'عند إنشاء خدمة جديدة يمكنك تحديد التصنيف الرئيسي والفرعي، ثم تفعيل استقبال الطلبات العاجلة لهذا التصنيف وحده حتى يبقى التوزيع أدق.',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12.5,
              height: 1.6,
              fontWeight: FontWeight.w700,
              color: Color(0xFF475569),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.home_repair_service_outlined,
            size: 56,
            color: Colors.grey,
          ),
          const SizedBox(height: 14),
          const Text(
            'لا توجد خدمات بعد',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'ابدأ الآن بإضافة خدمتك الأولى ليظهر تخصصك للعملاء مع إعدادات التسعير والعاجل.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12.5,
              height: 1.55,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _addNewService,
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text(
              'أضف خدمتك الأولى',
              style: TextStyle(fontFamily: 'Cairo', color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: const PlatformTopBar(
          pageLabel: 'خدماتي',
          showBackButton: true,
        ),
        floatingActionButton: (!_isLoading && _errorMessage == null)
            ? FloatingActionButton(
                backgroundColor: Colors.deepPurple,
                onPressed: _addNewService,
                child: const Icon(Icons.add, color: Colors.white),
              )
            : null,
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.deepPurple),
              )
            : (_errorMessage != null)
                ? _buildErrorState()
                : RefreshIndicator(
                    onRefresh: () => _loadData(silent: true),
                    color: Colors.deepPurple,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _buildIntroCard(),
                        const SizedBox(height: 16),
                        if (services.isEmpty)
                          _buildEmptyState()
                        else
                          ...List.generate(services.length, (index) {
                            final service = services[index];
                            return Padding(
                              padding: EdgeInsets.only(
                                bottom: index == services.length - 1 ? 0 : 16,
                              ),
                              child: Dismissible(
                                key: ValueKey(service['id'] ?? index),
                                direction: DismissDirection.endToStart,
                                background: Container(
                                  alignment: Alignment.centerLeft,
                                  padding: const EdgeInsets.only(left: 20),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: const Icon(Icons.delete,
                                      color: Colors.white),
                                ),
                                confirmDismiss: (_) async {
                                  await _deleteService(index);
                                  return false;
                                },
                                child: InkWell(
                                  onTap: () => _editService(index),
                                  borderRadius: BorderRadius.circular(16),
                                  child: _buildServiceCard(service),
                                ),
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _buildServiceCard(Map<String, dynamic> service) {
    final String priceUnit = service['price_unit'] as String? ?? 'fixed';
    final subcategory = service['subcategory'] as Map<String, dynamic>?;
    final categoryInSub = subcategory?['category'] as Map<String, dynamic>?;
    final mainCatName = categoryInSub?['name'] as String? ?? '';
    final subCatName = subcategory?['name'] as String? ?? '';
    final bool isActive = service['is_active'] as bool? ?? true;
    final bool acceptsUrgent = service['accepts_urgent'] as bool? ?? false;

    // تنسيق السعر
    String priceText;
    final priceFrom = service['price_from'];
    final priceTo = service['price_to'];
    switch (priceUnit) {
      case 'negotiable':
        priceText = 'قابل للتفاوض';
        if (priceFrom != null) priceText += ' (من $priceFrom ر.س)';
        break;
      case 'starting_from':
        priceText = 'يبدأ من ${priceFrom ?? '—'} ر.س';
        break;
      case 'hour':
        priceText = '${priceFrom ?? '—'} ر.س / ساعة';
        break;
      case 'day':
        priceText = '${priceFrom ?? '—'} ر.س / يوم';
        break;
      default:
        if (priceFrom != null && priceTo != null) {
          priceText = '$priceFrom - $priceTo ر.س';
        } else if (priceFrom != null) {
          priceText = '$priceFrom ر.س';
        } else {
          priceText = 'غير محدد';
        }
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? Colors.grey.shade200 : Colors.red.shade100,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                FontAwesomeIcons.briefcase,
                color: Colors.deepPurple,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  service['title'] as String? ?? '',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isActive
                      ? const Color(0xFFECFDF5)
                      : Colors.red.shade50,
                  border: Border.all(
                    color: isActive
                        ? const Color(0xFF10B981).withValues(alpha: 0.35)
                        : Colors.red,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isActive ? 'مفعلة' : 'معطلة',
                  style: TextStyle(
                    color: isActive
                        ? const Color(0xFF047857)
                        : Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
            ],
          ),
          if ((service['description'] as String? ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              service['description'] as String,
              style: const TextStyle(
                  fontSize: 14, color: Colors.black87, fontFamily: 'Cairo'),
            ),
          ],
          const SizedBox(height: 12),
          if (mainCatName.isNotEmpty || subCatName.isNotEmpty)
            Row(
              children: [
                const Icon(Icons.category, size: 16, color: Colors.grey),
                const SizedBox(width: 6),
                Text(
                  [mainCatName, subCatName]
                      .where((s) => s.isNotEmpty)
                      .join(' > '),
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ],
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: acceptsUrgent
                      ? const Color(0xFFECFDF5)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: acceptsUrgent
                        ? const Color(0xFF10B981).withValues(alpha: 0.25)
                        : const Color(0xFFCBD5E1),
                  ),
                ),
                child: Text(
                  acceptsUrgent
                      ? 'يستقبل الطلبات العاجلة'
                      : 'العاجل غير مفعل',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: acceptsUrgent
                        ? const Color(0xFF047857)
                        : const Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.price_check, size: 16, color: Colors.grey),
              const SizedBox(width: 6),
              Text(
                priceText,
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    final idx = services.indexOf(service);
                    if (idx >= 0) _editService(idx);
                  },
                  icon: const Icon(Icons.edit, color: Colors.white, size: 16),
                  label: const Text(
                    'تعديل',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontFamily: 'Cairo',
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    final idx = services.indexOf(service);
                    if (idx >= 0) {
                      _deleteService(idx);
                    }
                  },
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text(
                    'حذف',
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 13),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                ),
              ],
            ),
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
          fontSize: 14,
          color: Colors.deepPurple,
          fontFamily: 'Cairo',
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({String? hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontFamily: 'Cairo'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      isDense: true,
    );
  }
}
