import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:nawafeth/services/profile_service.dart';
import 'package:nawafeth/utils/debounced_save_runner.dart';

import 'package:latlong2/latlong.dart';

import 'map_radius_picker_screen.dart';

class LanguageLocationStep extends StatefulWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;

  const LanguageLocationStep({
    super.key,
    required this.onNext,
    required this.onBack,
  });

  @override
  State<LanguageLocationStep> createState() => _LanguageLocationStepState();
}

class _LanguageLocationStepState extends State<LanguageLocationStep> {
  final List<String> predefinedLanguages = ['عربي', 'English', 'أخرى'];
  final List<String> selectedLanguages = [];
  final List<String> customLanguages = [];
  final TextEditingController customLanguageController =
      TextEditingController();
  final TextEditingController locationController = TextEditingController();

  int? _selectedDistanceKm;
  LatLng? _selectedCenter;

  final Map<String, bool> serviceRange = {
    'مدينتي 🏙️': false,
    'منطقتي 🗺️': false,
    'دولتي 🌍': false,
    'ضمن نطاق محدد 📍': false,
  };

  static const List<int> _distanceOptionsKm = [2, 5, 10, 20, 50];
  final DebouncedSaveRunner _autoSaveRunner = DebouncedSaveRunner();

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
      final loadedLanguages = profile.languages
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();

      final loadedSelected = <String>[];
      final loadedCustom = <String>[];
      for (final lang in loadedLanguages) {
        if (predefinedLanguages.contains(lang) && lang != 'أخرى') {
          loadedSelected.add(lang);
        } else {
          loadedCustom.add(lang);
        }
      }
      if (loadedCustom.isNotEmpty && !loadedSelected.contains('أخرى')) {
        loadedSelected.add('أخرى');
      }

      final hasLocation = profile.lat != null && profile.lng != null;
      final radiusKm =
          profile.coverageRadiusKm > 0 ? profile.coverageRadiusKm : 10;

      setState(() {
        _isInitialized = false;
        selectedLanguages
          ..clear()
          ..addAll(loadedSelected);
        customLanguages
          ..clear()
          ..addAll(loadedCustom);
        _selectedDistanceKm = radiusKm;
        _selectedCenter =
            hasLocation ? LatLng(profile.lat!, profile.lng!) : null;
        serviceRange['ضمن نطاق محدد 📍'] = hasLocation;
        locationController.text = hasLocation
            ? '(${profile.lat!.toStringAsFixed(5)}, ${profile.lng!.toStringAsFixed(5)}) • $radiusKm كم'
            : '';
        _isLoading = false;
        _saveError = null;
        _isInitialized = true;
      });
      return;
    }

    setState(() {
      _isLoading = false;
      _saveError = result.error ?? 'تعذر تحميل بيانات اللغة والموقع';
      _isInitialized = true;
    });
  }

  void _ensureDefaultDistance() {
    _selectedDistanceKm ??= 10;
  }

  void _selectSingleServiceRange(String selectedKey) {
    final wasSpecificRangeSelected = serviceRange['ضمن نطاق محدد 📍'] == true;

    for (final key in serviceRange.keys.toList()) {
      serviceRange[key] = key == selectedKey;
    }

    final isSpecificRangeSelected = selectedKey == 'ضمن نطاق محدد 📍';
    if (isSpecificRangeSelected) {
      _ensureDefaultDistance();
      return;
    }

    if (wasSpecificRangeSelected) {
      _selectedCenter = null;
      locationController.clear();
    }
  }

  Future<void> _pickMapLocation() async {
    if (_selectedDistanceKm == null) {
      _ensureDefaultDistance();
      if (mounted) setState(() {});
    }

    final picked = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (_) => MapRadiusPickerScreen(
          radiusKm: _selectedDistanceKm!,
          initialCenter: _selectedCenter,
        ),
      ),
    );

    if (picked == null || !mounted) return;
    setState(() {
      _selectedCenter = picked;
      locationController.text =
          '(${picked.latitude.toStringAsFixed(5)}, ${picked.longitude.toStringAsFixed(5)}) • $_selectedDistanceKm كم';
      serviceRange['ضمن نطاق محدد 📍'] = true;
    });
    _queueAutoSave();
  }

  void _queueAutoSave() {
    if (!_isInitialized) return;
    _autoSaveRunner.schedule(_saveToApi);
  }

  Future<void> _saveToApi() async {
    final combinedLanguages = <String>[
      ...selectedLanguages.where((lang) => lang != 'أخرى'),
      ...customLanguages,
    ].map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();

    final payload = <String, dynamic>{
      'languages': combinedLanguages,
      'coverage_radius_km': _selectedDistanceKm ?? 10,
    };

    if (_selectedCenter != null) {
      payload['lat'] = _selectedCenter!.latitude;
      payload['lng'] = _selectedCenter!.longitude;
    }

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

  @override
  void dispose() {
    customLanguageController.dispose();
    locationController.dispose();
    _autoSaveRunner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F4FC),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _buildHeader(),
                const SizedBox(height: 8),
                _buildSaveStatus(),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    child: _isLoading
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 30),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: Colors.deepPurple,
                              ),
                            ),
                          )
                        : _buildForm(),
                  ),
                ),
                const SizedBox(height: 12),
                _buildActionButtons(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------- HEADER ----------------

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "اللغة والموقع الجغرافي",
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.bold,
            color: Colors.deepPurple,
            fontFamily: "Cairo",
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          "حدد اللغات التي يمكنك التعامل بها ونطاق تقديم خدماتك.",
          style: TextStyle(
            fontFamily: "Cairo",
            fontSize: 12,
            color: Colors.black54,
          ),
        ),
        const SizedBox(height: 10),
        _infoTip(
          icon: Icons.info_outline,
          text:
              "اختيار اللغات ونطاق الخدمة يساعد في عرضك للعملاء المناسبين أكثر لاهتماماتك وموقعك.",
        ),
      ],
    );
  }

  Widget _infoTip({required IconData icon, required String text}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F4FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.deepPurple, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontFamily: "Cairo",
                fontSize: 11,
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
                fontFamily: 'Cairo', fontSize: 12, color: Colors.black54),
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

  // ---------------- FORM ----------------

  Widget _buildForm() {
    return Column(
      children: [
        _sectionCard(
          icon: FontAwesomeIcons.language,
          title: 'ما اللغة التي يمكنك تقديم الخدمة من خلالها؟',
          subtitle:
              "اختر اللغات التي يمكنك التحدث والتعامل بها مع العملاء، ويمكنك إضافة لغات أخرى يدويًا.",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: predefinedLanguages.map((lang) {
                  final selected = selectedLanguages.contains(lang);
                  return FilterChip(
                    label: Text(lang),
                    selected: selected,
                    onSelected: (val) {
                      setState(() {
                        val
                            ? selectedLanguages.add(lang)
                            : selectedLanguages.remove(lang);
                      });
                      _queueAutoSave();
                    },
                    selectedColor: Colors.deepPurple,
                    backgroundColor: Colors.grey.shade200,
                    labelStyle: TextStyle(
                      fontFamily: "Cairo",
                      fontSize: 12,
                      color: selected ? Colors.white : Colors.black,
                    ),
                  );
                }).toList(),
              ),
              if (selectedLanguages.contains('أخرى'))
                _buildCustomLanguageInput(),
              if (customLanguages.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Wrap(
                    spacing: 8,
                    children: customLanguages.map((lang) {
                      return Chip(
                        label: Text(
                          lang,
                          style: const TextStyle(fontFamily: "Cairo"),
                        ),
                        onDeleted: () {
                          setState(() => customLanguages.remove(lang));
                          _queueAutoSave();
                        },
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        ),
        _sectionCard(
          icon: FontAwesomeIcons.mapLocationDot,
          title: 'نطاق الخدمة الجغرافي',
          subtitle:
              "حدد النطاق الذي يمكنك تقديم خدماتك فيه. يمكن اختيار خيار واحد فقط.",
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: serviceRange.entries.map((entry) {
              final selected = entry.value;
              return FilterChip(
                label: Text(
                  entry.key,
                  style: const TextStyle(
                    fontFamily: "Cairo",
                    fontSize: 12,
                  ),
                ),
                selected: selected,
                onSelected: (val) {
                  if (!val) return;
                  setState(() {
                    _selectSingleServiceRange(entry.key);
                  });
                  _queueAutoSave();
                },
                selectedColor: Colors.deepPurple,
                backgroundColor: Colors.grey.shade200,
                labelStyle: TextStyle(
                  fontFamily: "Cairo",
                  fontSize: 12,
                  color: selected ? Colors.white : Colors.black,
                ),
              );
            }).toList(),
          ),
        ),
        if (serviceRange['ضمن نطاق محدد 📍'] == true)
          _sectionCard(
            icon: FontAwesomeIcons.locationCrosshairs,
            title: 'المسافة والموقع المحدد',
            subtitle:
                "اختر المسافة التي يمكنك تغطيتها، وحدد موقعك الجغرافي على الخريطة.",
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  children: _distanceOptionsKm.map((km) {
                    final selected = _selectedDistanceKm == km;
                    return FilterChip(
                      label: Text(
                        '$km كم',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                        ),
                      ),
                      selected: selected,
                      onSelected: (_) {
                        setState(() {
                          _selectedDistanceKm = km;
                          if (_selectedCenter != null) {
                            locationController.text =
                                '(${_selectedCenter!.latitude.toStringAsFixed(5)}, ${_selectedCenter!.longitude.toStringAsFixed(5)}) • $_selectedDistanceKm كم';
                          }
                        });
                        _queueAutoSave();
                      },
                      selectedColor: Colors.deepPurple,
                      backgroundColor: Colors.grey.shade200,
                      labelStyle: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        color: selected ? Colors.white : Colors.black87,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _pickMapLocation,
                  icon: const Icon(Icons.my_location),
                  label: const Text(
                    "تحديد موقعي الجغرافي",
                    style: TextStyle(fontFamily: "Cairo", fontSize: 12),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.deepPurple,
                    side: const BorderSide(color: Colors.deepPurple),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: locationController,
                  readOnly: true,
                  style: const TextStyle(fontFamily: "Cairo", fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'موقعي المختار والمسافة',
                    hintStyle: const TextStyle(
                      fontFamily: "Cairo",
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                    prefixIcon: const Icon(Icons.link),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Colors.deepPurple,
                        width: 1.3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ---------------- CUSTOM LANGUAGE INPUT ----------------

  Widget _buildCustomLanguageInput() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: customLanguageController,
              style: const TextStyle(fontFamily: "Cairo", fontSize: 12),
              decoration: InputDecoration(
                hintText: 'أدخل اللغة ثم اضغط "تم"',
                hintStyle: const TextStyle(
                  fontFamily: "Cairo",
                  fontSize: 12,
                  color: Colors.grey,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.deepPurple),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () {
              final lang = customLanguageController.text.trim();
              if (lang.isNotEmpty && !customLanguages.contains(lang)) {
                setState(() {
                  customLanguages.add(lang);
                  customLanguageController.clear();
                });
                _queueAutoSave();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text("تم", style: TextStyle(fontFamily: "Cairo")),
          ),
        ],
      ),
    );
  }

  // ---------------- SECTION CARD ----------------

  Widget _sectionCard({
    required IconData icon,
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: Colors.deepPurple, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.deepPurple,
                    fontFamily: "Cairo",
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(
                fontFamily: "Cairo",
                fontSize: 10.8,
                color: Colors.black54,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  // ---------------- ACTION BUTTONS ----------------

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () async {
              await _autoSaveRunner.flush();
              widget.onBack();
            },
            icon: const Icon(Icons.arrow_back),
            label: const Text("السابق", style: TextStyle(fontFamily: "Cairo")),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: const BorderSide(color: Colors.deepPurple),
              foregroundColor: Colors.deepPurple,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _isLoading
                ? null
                : () async {
                    await _autoSaveRunner.flush();
                    widget.onNext();
                  },
            icon: const Icon(Icons.arrow_forward),
            label: const Text("التالي", style: TextStyle(fontFamily: "Cairo")),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
