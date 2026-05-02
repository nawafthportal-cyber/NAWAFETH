import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../services/marketplace_service.dart';
import '../services/request_draft_service.dart';
import '../services/api_client.dart';
import '../constants/app_theme.dart';
import '../constants/saudi_cities.dart';
import '../models/provider_public_model.dart';
import '../utils/debounced_save_runner.dart';
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
  static const String _draftKey = 'draft_service_request_form_v1';
  static const Color _mainColor = AppColors.primary;
  static const Color _inkColor = AppTextStyles.textPrimary;
  bool _isDark = false;

  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _detailsController = TextEditingController();
  final DebouncedSaveRunner _draftSaveRunner = DebouncedSaveRunner();
  final _titleFocus = FocusNode();
  final _detailsFocus = FocusNode();
  AutovalidateMode _autovalidateMode = AutovalidateMode.disabled;
  late final AnimationController _entranceController;
  String? _selectedRegion;
  String? _selectedCity;
  String _urgentDispatchMode = 'all';
  ProviderPublicModel? _selectedUrgentProvider;
  bool _loadingNearestProviders = false;
  String? _urgentDispatchError;
  double? _requestLat;
  double? _requestLng;

  // ─── نوع الطلب ───
  String _requestType = 'competitive'; // normal | competitive | urgent

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
  bool _draftRestored = false;

  bool get _isProviderRequest => widget.providerId != null;
  String get _effectiveRequestType =>
      _isProviderRequest ? 'normal' : _requestType;

    bool get _showUrgentDispatchControls =>
      !_isProviderRequest && _effectiveRequestType == 'urgent';

  String _sanitizeRequestType(String? requestType) {
    if (_isProviderRequest) return 'normal';
    switch (requestType) {
      case 'competitive':
      case 'urgent':
        return requestType!;
      default:
        return 'competitive';
    }
  }

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _requestType = _sanitizeRequestType(_requestType);
    _titleController.addListener(_scheduleDraftSave);
    _detailsController.addListener(_scheduleDraftSave);
    _restoreDraft();
    _loadCategories();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _entranceController.forward();
      }
    });
  }

  @override
  void dispose() {
    _draftSaveRunner.dispose();
    _titleController.dispose();
    _detailsController.dispose();
    _titleFocus.dispose();
    _detailsFocus.dispose();
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

  SaudiRegionCatalogEntry? get _activeRegion {
    return SaudiCities.findRegionEntry(_selectedRegion);
  }

  List<String> get _availableCities => _activeRegion?.cities ?? const [];

  String get _selectedScopedCity {
    return SaudiCities.normalizeScopedCity(_selectedCity, region: _selectedRegion);
  }

  double? _readDraftDouble(Map<String, dynamic> draft, String key) {
    final value = draft[key];
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  Future<void> _restoreDraft() async {
    final draft = await RequestDraftService.loadDraft(_draftKey);
    if (!mounted || draft == null) {
      return;
    }
    final draftProviderId = RequestDraftService.readString(draft, 'provider_id');
    final currentProviderId = (widget.providerId ?? '').trim();
    if (draftProviderId != currentProviderId) {
      return;
    }

    final requestType = RequestDraftService.readString(draft, 'request_type');
    final quoteDeadlineRaw = RequestDraftService.readString(draft, 'quote_deadline');

    setState(() {
      _requestType = _sanitizeRequestType(
        requestType.isEmpty ? _requestType : requestType,
      );
      _urgentDispatchMode = _isProviderRequest
          ? 'all'
          : (() {
              final savedDispatchMode =
                  RequestDraftService.readString(draft, 'dispatch_mode');
              return savedDispatchMode == 'nearest' ? 'nearest' : 'all';
            })();
      _selectedCategoryId = RequestDraftService.readInt(draft, 'category_id');
      _selectedSubcategoryId = RequestDraftService.readInt(draft, 'subcategory_id');
      _selectedRegion = RequestDraftService.readString(draft, 'region').isEmpty
          ? null
          : RequestDraftService.readString(draft, 'region');
      _selectedCity = RequestDraftService.readString(draft, 'city').isEmpty
          ? null
          : RequestDraftService.readString(draft, 'city');
      _titleController.text = RequestDraftService.readString(draft, 'title');
      _detailsController.text = RequestDraftService.readString(draft, 'details');
      _requestLat = _readDraftDouble(draft, 'request_lat');
      _requestLng = _readDraftDouble(draft, 'request_lng');
      _quoteDeadline = quoteDeadlineRaw.isEmpty
          ? null
          : DateTime.tryParse(quoteDeadlineRaw);
      _draftRestored = true;
    });
  }

  void _scheduleDraftSave() {
    _draftSaveRunner.schedule(_persistDraft);
  }

  Future<void> _persistDraft() async {
    final payload = <String, dynamic>{
      'provider_id': (widget.providerId ?? '').trim(),
      'request_type': _effectiveRequestType,
        'dispatch_mode': _showUrgentDispatchControls ? _urgentDispatchMode : 'all',
      'category_id': _selectedCategoryId,
      'subcategory_id': _selectedSubcategoryId,
      'region': _selectedRegion,
      'city': _selectedCity,
      'title': _titleController.text.trim(),
      'details': _detailsController.text.trim(),
        'request_lat': _showUrgentDispatchControls && _urgentDispatchMode == 'nearest'
          ? _requestLat
          : null,
        'request_lng': _showUrgentDispatchControls && _urgentDispatchMode == 'nearest'
          ? _requestLng
          : null,
      'quote_deadline': _quoteDeadline?.toIso8601String(),
    };

    final hasMeaningfulDraft = [
      payload['category_id'],
      payload['subcategory_id'],
      payload['region'],
      payload['city'],
      payload['title'],
      payload['details'],
      payload['quote_deadline'],
    ].any((value) {
      if (value == null) return false;
      if (value is String) return value.trim().isNotEmpty;
      return true;
    });

    if (!hasMeaningfulDraft) {
      await RequestDraftService.clearDraft(_draftKey);
      return;
    }

    await RequestDraftService.saveDraft(_draftKey, payload);
  }

  // ─── المرفقات ───
  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source);
    if (picked == null || !mounted) return;
    HapticFeedback.selectionClick();
    setState(() => _images.add(File(picked.path)));
  }

  Future<void> _pickVideo(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickVideo(source: source);
    if (picked == null || !mounted) return;
    HapticFeedback.selectionClick();
    setState(() => _videos.add(File(picked.path)));
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'txt', 'xlsx', 'xls'],
    );
    final path = result?.files.single.path;
    if (path == null || !mounted) return;
    HapticFeedback.selectionClick();
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
    HapticFeedback.selectionClick();
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
    HapticFeedback.selectionClick();
    setState(() => _quoteDeadline = picked);
  }

  void _resetUrgentDispatchState({bool clearCoordinates = false}) {
    _urgentDispatchMode = 'all';
    _selectedUrgentProvider = null;
    _urgentDispatchError = null;
    _loadingNearestProviders = false;
    if (clearCoordinates) {
      _requestLat = null;
      _requestLng = null;
    }
  }

  Future<Position?> _resolveUrgentPosition({required bool requestPermission}) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return null;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && requestPermission) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
  }

  Future<List<ProviderPublicModel>> _fetchNearestUrgentProviders({
    required double latitude,
    required double longitude,
  }) async {
    final uri = Uri(
      path: '/api/providers/',
      queryParameters: {
        'has_location': 'true',
        'accepts_urgent': 'true',
        'page_size': '30',
        if (_selectedSubcategoryId != null)
          'subcategory_id': '$_selectedSubcategoryId',
      },
    );
    final response = await ApiClient.get(uri.toString());
    if (!response.isSuccess) {
      throw Exception(response.error ?? 'تعذر تحميل قائمة المزودين');
    }

    final rawList = response.dataAsMap?['results'] is List
        ? List<dynamic>.from(response.dataAsMap!['results'] as List<dynamic>)
        : (response.dataAsList ?? const <dynamic>[]);

    final providers = rawList
        .whereType<Map>()
        .map((item) => ProviderPublicModel.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .where(
          (provider) =>
              provider.lat != null &&
              provider.lng != null &&
              provider.acceptsUrgent,
        )
        .toList(growable: false);

    providers.sort((left, right) {
      final leftDistance = Geolocator.distanceBetween(
        latitude,
        longitude,
        left.lat!,
        left.lng!,
      );
      final rightDistance = Geolocator.distanceBetween(
        latitude,
        longitude,
        right.lat!,
        right.lng!,
      );
      return leftDistance.compareTo(rightDistance);
    });

    return providers;
  }

  Future<void> _selectNearestUrgentProvider() async {
    HapticFeedback.selectionClick();
    setState(() {
      _urgentDispatchMode = 'nearest';
      _loadingNearestProviders = true;
      _urgentDispatchError = null;
    });

    try {
      final position = await _resolveUrgentPosition(requestPermission: true);
      if (position == null) {
        if (!mounted) return;
        setState(() {
          _loadingNearestProviders = false;
          _urgentDispatchError =
              'فعّل الموقع لاستخدام توجيه الطلب العاجل إلى الأقرب.';
        });
        return;
      }

      final providers = await _fetchNearestUrgentProviders(
        latitude: position.latitude,
        longitude: position.longitude,
      );
      if (!mounted) return;

      setState(() {
        _requestLat = position.latitude;
        _requestLng = position.longitude;
        _loadingNearestProviders = false;
        _urgentDispatchError = providers.isEmpty
            ? 'لم نعثر على مزودين قريبين يفعّلون الطلبات العاجلة حالياً.'
            : null;
      });
      _scheduleDraftSave();

      if (providers.isEmpty) {
        return;
      }

      final selectedProvider = await showModalBottomSheet<ProviderPublicModel>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        barrierColor: Colors.black.withValues(alpha: 0.32),
        builder: (sheetContext) {
          final displayProviders = providers.take(12).toList(growable: false);
          return Directionality(
            textDirection: TextDirection.rtl,
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  boxShadow: AppShadows.elevated,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.grey200,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'اختر مزوداً قريباً',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: AppTextStyles.h2,
                        fontWeight: FontWeight.w900,
                        color: _inkColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'سيبقى التوجيه على الأقرب، ويمكنك أيضاً ترشيح مزود قريب لتوجيه الإشعار الأولي مباشرة.',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppTextStyles.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: displayProviders.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final provider = displayProviders[index];
                          final distanceKm = Geolocator.distanceBetween(
                                position.latitude,
                                position.longitude,
                                provider.lat!,
                                provider.lng!,
                              ) /
                              1000;
                          final avatarUrl =
                              ApiClient.buildMediaUrl(provider.profileImage);
                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              onTap: () => Navigator.pop(sheetContext, provider),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.md),
                                  border: Border.all(
                                    color: AppColors.borderLight,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 22,
                                      backgroundColor: AppColors.primarySurface,
                                      backgroundImage: avatarUrl != null
                                          ? NetworkImage(avatarUrl)
                                          : null,
                                      child: avatarUrl == null
                                          ? Text(
                                              provider.displayName.isNotEmpty
                                                  ? provider.displayName[0]
                                                  : '؟',
                                              style: const TextStyle(
                                                fontFamily: 'Cairo',
                                                fontWeight: FontWeight.w900,
                                                color: _mainColor,
                                              ),
                                            )
                                          : null,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            provider.displayName,
                                            style: const TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w800,
                                              color: _inkColor,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${provider.locationDisplay} · ${distanceKm.toStringAsFixed(distanceKm < 10 ? 1 : 0)} كم',
                                            style: const TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.grey500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.primarySurface,
                                        borderRadius: BorderRadius.circular(
                                          AppRadius.pill,
                                        ),
                                      ),
                                      child: Text(
                                        provider.ratingAvg > 0
                                            ? '⭐ ${provider.ratingAvg.toStringAsFixed(1)}'
                                            : '${provider.completedRequests} مكتمل',
                                        style: const TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: _mainColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );

      if (!mounted || selectedProvider == null) return;
      setState(() {
        _selectedUrgentProvider = selectedProvider;
      });
      _scheduleDraftSave();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingNearestProviders = false;
        _urgentDispatchError = 'تعذر تحديد مزود قريب الآن. حاول مرة أخرى.';
      });
    }
  }

  Widget _buildUrgentDispatchControls() {
    final isNearest = _urgentDispatchMode == 'nearest';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        _fieldLabel('توجيه الطلب العاجل'),
        Row(
          children: [
            Expanded(
              child: _dispatchChip(
                icon: Icons.public_rounded,
                label: 'إرسال للجميع',
                hint: 'مطابقة عاجلة حسب التخصص',
                selected: !isNearest,
                onTap: () {
                  if (!isNearest) return;
                  HapticFeedback.selectionClick();
                  setState(() {
                    _resetUrgentDispatchState();
                  });
                  _scheduleDraftSave();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _dispatchChip(
                icon: Icons.near_me_outlined,
                label: 'إرسال للأقرب',
                hint: 'يستخدم موقعك الحالي',
                selected: isNearest,
                onTap: () {
                  if (isNearest && _selectedUrgentProvider != null) {
                    return;
                  }
                  _selectNearestUrgentProvider();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          isNearest
              ? 'سيتم استخدام موقعك الحالي لتضييق الطلب العاجل على الأقرب، ويمكنك ترشيح مزود قريب بشكل اختياري.'
              : 'سيصل الطلب العاجل إلى المزودين المطابقين دون تقييده بموقعك الحالي.',
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: AppColors.grey500,
            height: 1.7,
          ),
        ),
        if (_loadingNearestProviders) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(minHeight: 3),
        ],
        if (_urgentDispatchError != null) ...[
          const SizedBox(height: 8),
          Text(
            _urgentDispatchError!,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: AppColors.error,
            ),
          ),
        ],
        if (isNearest) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed:
                _loadingNearestProviders ? null : _selectNearestUrgentProvider,
            icon: const Icon(Icons.my_location_rounded, size: 18),
            label: Text(
              _selectedUrgentProvider == null
                  ? 'اختيار مزود قريب'
                  : 'تغيير المزود القريب',
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: _mainColor,
              side: BorderSide(color: _mainColor.withValues(alpha: 0.35)),
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
            ),
          ),
        ],
        if (isNearest && _selectedUrgentProvider != null) ...[
          const SizedBox(height: 10),
          _buildSelectedUrgentProviderCard(),
        ],
      ],
    );
  }

  Widget _dispatchChip({
    required IconData icon,
    required String label,
    required String hint,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: AnimatedContainer(
        duration: AppDurations.fast,
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySurface : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected ? _mainColor : AppColors.borderLight,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 19,
              color: selected ? _mainColor : AppColors.grey500,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
                color: selected ? _mainColor : _inkColor,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              hint,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                color: selected
                    ? _mainColor.withValues(alpha: 0.8)
                    : AppColors.grey500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedUrgentProviderCard() {
    final provider = _selectedUrgentProvider!;
    final avatarUrl = ApiClient.buildMediaUrl(provider.profileImage);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.primarySurface,
            backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
            child: avatarUrl == null
                ? Text(
                    provider.displayName.isNotEmpty
                        ? provider.displayName[0]
                        : '؟',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w900,
                      color: _mainColor,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  provider.displayName,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: _inkColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  provider.locationDisplay,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.grey500,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _loadingNearestProviders ? null : _selectNearestUrgentProvider,
            icon: const Icon(Icons.edit_location_alt_outlined, size: 18),
            color: _mainColor,
            tooltip: 'تغيير',
          ),
          IconButton(
            onPressed: () {
              HapticFeedback.selectionClick();
              setState(() {
                _selectedUrgentProvider = null;
              });
              _scheduleDraftSave();
            },
            icon: const Icon(Icons.close_rounded, size: 18),
            color: AppColors.grey500,
            tooltip: 'إزالة',
          ),
        ],
      ),
    );
  }

  void _showAttachmentOptions() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.32),
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(AppRadius.xl),
              boxShadow: AppShadows.elevated,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.grey200,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'إضافة مرفق',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: AppTextStyles.h2,
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
                    fontWeight: FontWeight.w600,
                    color: AppTextStyles.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
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

  void _snack(String msg, {bool isError = true}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isError ? AppColors.grey800 : AppColors.grey700,
      duration: const Duration(seconds: 3),
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      content: Row(
        children: [
          Icon(
            isError
                ? Icons.error_outline_rounded
                : Icons.check_circle_outline_rounded,
            color: isError ? AppColors.errorSurface : AppColors.successSurface,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              msg,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    ));
  }

  // ─── إرسال الطلب ───
  Future<void> _submitRequest() async {
    // بعد أول محاولة إرسال، فعّل التحقق التفاعلي حتى تظهر الأخطاء فورياً عند التصحيح.
    if (_autovalidateMode != AutovalidateMode.onUserInteraction) {
      setState(() {
        _autovalidateMode = AutovalidateMode.onUserInteraction;
      });
    }
    if (!_formKey.currentState!.validate()) {
      HapticFeedback.lightImpact();
      return;
    }

    // التحقق من الحقول المطلوبة
    if (_selectedSubcategoryId == null) {
      HapticFeedback.lightImpact();
      _snack('الرجاء اختيار التصنيف الفرعي');
      return;
    }

    final city = _selectedScopedCity;

    // الطلب العادي يحتاج provider
    int? providerId;
    if (_effectiveRequestType == 'normal') {
      if (widget.providerId == null) {
        HapticFeedback.lightImpact();
        _snack('الطلب العادي يتطلب تحديد مزود خدمة');
        return;
      }
      providerId = int.tryParse(widget.providerId!);
    } else if (_effectiveRequestType == 'urgent' && _urgentDispatchMode == 'nearest') {
      if (_requestLat == null || _requestLng == null) {
        HapticFeedback.lightImpact();
        _snack('حدّد موقعك أولاً لاستخدام توجيه الطلب العاجل إلى الأقرب');
        return;
      }
      providerId = _selectedUrgentProvider?.id;
    }

    final dispatchMode = _effectiveRequestType == 'urgent'
        ? _urgentDispatchMode
        : null;

    // إخفاء لوحة المفاتيح وإعلام خفيف عند بدء الإرسال.
    FocusScope.of(context).unfocus();
    HapticFeedback.selectionClick();
    setState(() => _submitting = true);

    final res = await MarketplaceService.createRequest(
      title: _titleController.text.trim(),
      description: _detailsController.text.trim(),
      requestType: _effectiveRequestType,
      subcategory: _selectedSubcategoryId!,
      city: city.isNotEmpty ? city : null,
      provider: providerId,
        dispatchMode: dispatchMode,
      quoteDeadline: _quoteDeadline != null
          ? DateFormat('yyyy-MM-dd').format(_quoteDeadline!)
          : null,
        requestLat: dispatchMode == 'nearest' ? _requestLat : null,
        requestLng: dispatchMode == 'nearest' ? _requestLng : null,
      images: _images,
      videos: _videos,
      files: _files,
      audio: _audioPath != null ? File(_audioPath!) : null,
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (res.isSuccess) {
      await RequestDraftService.clearDraft(_draftKey);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      showDialog(
        context: context,
        builder: (_) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Row(children: [
              Icon(Icons.check_circle, color: AppColors.success, size: 30),
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
      HapticFeedback.lightImpact();
      _snack(res.error ?? 'فشل إرسال الطلب');
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

  double get _completionProgress {
    int done = 0;
    if (_effectiveRequestType.isNotEmpty) done++;
    if (_selectedCategoryId != null) done++;
    if (_selectedSubcategoryId != null) done++;
    if (_titleController.text.trim().isNotEmpty) done++;
    if (_detailsController.text.trim().isNotEmpty) done++;
    return done / 5;
  }

  // ─── Build ───

  @override
  Widget build(BuildContext context) {
    _isDark = Theme.of(context).brightness == Brightness.dark;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _isDark ? AppColors.bgDark : AppColors.bgLight,
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
          autovalidateMode: _autovalidateMode,
          child: ListView(
            physics: const BouncingScrollPhysics(),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
            children: [
              _buildEntrance(0, _buildFormHeader()),
              if (_draftRestored) ...[
                const SizedBox(height: 10),
                _buildDraftNotice(),
              ],
              const SizedBox(height: 12),
              // ─── الخطوة 1: نوع الطلب ───
              _buildEntrance(
                1,
                _buildSectionCard(
                  title: 'نوع الطلب',
                  icon: Icons.tune_rounded,
                  stepNumber: 1,
                  child: _requestTypePicker(),
                ),
              ),
              const SizedBox(height: 10),
              // ─── الخطوة 2: التصنيف ───
              _buildEntrance(
                2,
                _buildSectionCard(
                  title: 'التصنيف',
                  icon: Icons.category_outlined,
                  stepNumber: 2,
                  child: Column(
                    children: [
                      _fieldLabel('القسم'),
                      _categoryDropdown(),
                      const SizedBox(height: 12),
                      _fieldLabel('التصنيف الفرعي'),
                      _subcategoryDropdown(),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // ─── الخطوة 3: العنوان والتفاصيل ───
              _buildEntrance(
                3,
                _buildSectionCard(
                  title: 'العنوان والتفاصيل',
                  icon: Icons.description_outlined,
                  stepNumber: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _fieldLabel('عنوان الطلب'),
                      TextFormField(
                        controller: _titleController,
                        focusNode: _titleFocus,
                        maxLength: 50,
                        textInputAction: TextInputAction.next,
                        onFieldSubmitted: (_) => _detailsFocus.requestFocus(),
                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                        decoration: _inputDeco(
                          hint: 'مثال: تركيب مكيف سبليت في غرفة النوم',
                          counter: '${_titleController.text.length}/50',
                        ),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                                ? 'يرجى إدخال عنوان الطلب'
                                : null,
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      _fieldLabel('وصف الخدمة المطلوبة'),
                      TextFormField(
                        controller: _detailsController,
                        focusNode: _detailsFocus,
                        maxLength: 500,
                        maxLines: 6,
                        textInputAction: TextInputAction.newline,
                        keyboardType: TextInputType.multiline,
                        style: const TextStyle(
                            fontFamily: 'Cairo', fontSize: 13, height: 1.6),
                        decoration: _inputDeco(
                          hint:
                              'اشرح ما تحتاجه بدقة: الموقع، الوقت المناسب، أي تفاصيل تساعد المزود.',
                          counter: '${_detailsController.text.length}/500',
                        ),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                                ? 'يرجى إدخال تفاصيل الطلب'
                                : null,
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // ─── الخطوة 4: الموقع ───
              _buildEntrance(
                4,
                _buildSectionCard(
                  title: 'الموقع',
                  icon: Icons.location_on_outlined,
                  stepNumber: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _fieldLabel('المنطقة الإدارية'),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedRegion,
                        decoration: _inputDeco(hint: 'اختر المنطقة الإدارية'),
                        isExpanded: true,
                        menuMaxHeight: 300,
                        items: SaudiCities.regionCatalogFallback
                            .map((region) => DropdownMenuItem(
                                  value: region.nameAr,
                                  child: Text(
                                    region.displayName,
                                    style: const TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ))
                            .toList(),
                        onChanged: (value) => setState(() {
                          _selectedRegion = value;
                          _selectedCity = null;
                          _scheduleDraftSave();
                        }),
                      ),
                      const SizedBox(height: 12),
                      _fieldLabel('المدينة', optional: true),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedCity,
                        decoration:
                            _inputDeco(hint: 'اختر المدينة (اختياري)'),
                        isExpanded: true,
                        menuMaxHeight: 300,
                        items: _availableCities
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
                        onChanged: (value) => setState(() {
                          _selectedCity = value;
                          _scheduleDraftSave();
                        }),
                      ),
                      if (_selectedScopedCity.isNotEmpty)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () => setState(() {
                              _selectedRegion = null;
                              _selectedCity = null;
                              _scheduleDraftSave();
                            }),
                            icon: const Icon(Icons.close_rounded, size: 14),
                            label: const Text(
                              'مسح الموقع',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.grey500,
                              minimumSize: const Size(0, 32),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                            ),
                          ),
                        ),
                      if (_showUrgentDispatchControls)
                        _buildUrgentDispatchControls(),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // ─── الخطوة 5: موعد استقبال العروض ───
              _buildEntrance(
                5,
                _buildSectionCard(
                  title: 'موعد استقبال العروض',
                  icon: Icons.calendar_today_outlined,
                  stepNumber: 5,
                  trailingHint: 'اختياري',
                  child: _deadlineTile(),
                ),
              ),
              const SizedBox(height: 10),
              // ─── الخطوة 6: المرفقات والصوت ───
              _buildEntrance(
                6,
                _buildSectionCard(
                  title: 'المرفقات والصوت',
                  icon: Icons.attach_file_rounded,
                  stepNumber: 6,
                  trailingHint: _attachmentsCount == 0
                      ? 'اختياري'
                      : '$_attachmentsCount مرفق',
                  child: Column(
                    children: [
                      _attachmentsPreview(),
                      const SizedBox(height: 14),
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: AppColors.borderLight,
                      ),
                      const SizedBox(height: 14),
                      _audioPart(),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 22),
              _buildEntrance(7, _buildActions()),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Sub-widgets ───

  Widget _fieldLabel(String text, {bool optional = false}) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 6, start: 2),
      child: Row(
        children: [
          Text(
            text,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: AppTextStyles.bodySm,
              fontWeight: FontWeight.w800,
              color: _isDark ? AppTextStyles.textSecondaryDark : AppTextStyles.textSecondary,
            ),
          ),
          if (optional) ...[
            const SizedBox(width: 6),
            const Text(
              '·',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                color: AppColors.grey400,
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              'اختياري',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: AppTextStyles.caption,
                fontWeight: FontWeight.w700,
                color: AppColors.grey400,
              ),
            ),
          ],
        ],
      ),
    );
  }

  InputDecoration _inputDeco({String? hint, String? counter}) =>
      InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: _isDark ? AppColors.grey600 : AppColors.grey400,
        ),
        filled: true,
        fillColor: _isDark ? AppColors.cardDark : AppColors.surfaceLight,
        counterText: counter,
        counterStyle: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 10.5,
          color: _isDark ? AppColors.grey500 : AppColors.grey500,
        ),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: _isDark ? AppColors.borderDark : AppColors.borderLight),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: _isDark ? AppColors.borderDark : AppColors.borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: _mainColor, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.error, width: 1.2),
        ),
        errorStyle: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.error,
        ),
      );

  Widget _requestTypePicker() {
    // إذا جاء من صفحة مزود محدد → نوع عادي فقط.
    if (_isProviderRequest) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.primarySurface,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: const Row(
          children: [
            Icon(Icons.verified_rounded, color: _mainColor, size: 16),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'طلب عادي مباشر إلى مقدم الخدمة المحدد',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: _mainColor,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final types = <Map<String, dynamic>>[
      {
        'key': 'competitive',
        'label': 'تنافسي',
        'hint': 'استقبال عدة عروض',
        'icon': Icons.groups_2_outlined,
      },
      {
        'key': 'urgent',
        'label': 'عاجل',
        'hint': 'تنفيذ مستعجل',
        'icon': Icons.bolt_rounded,
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
              borderRadius: BorderRadius.circular(AppRadius.md),
              onTap: () {
                if (_requestType == entry['key']) return;
                HapticFeedback.selectionClick();
                setState(() {
                  _requestType = entry['key'] as String;
                  if (_requestType != 'urgent') {
                    _resetUrgentDispatchState();
                  }
                  _scheduleDraftSave();
                });
              },
              child: AnimatedContainer(
                duration: AppDurations.fast,
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 12),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primarySurface
                      : AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: selected ? _mainColor : AppColors.borderLight,
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      entry['icon'] as IconData,
                      size: 20,
                      color: selected ? _mainColor : AppColors.grey500,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      entry['label'] as String,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                        color: selected ? _mainColor : _inkColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry['hint'] as String,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? _mainColor.withValues(alpha: 0.78)
                            : AppColors.grey500,
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
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: const Center(
          child: SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: _mainColor),
          ),
        ),
      );
    }
    return DropdownButtonFormField<int>(
      initialValue: _selectedCategoryId,
      decoration: _inputDeco(hint: 'اختر القسم'),
      borderRadius: BorderRadius.circular(AppRadius.md),
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
          _selectedUrgentProvider = null;
          _urgentDispatchError = null;
          _scheduleDraftSave();
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
      borderRadius: BorderRadius.circular(AppRadius.md),
      items: subs
          .map((s) => DropdownMenuItem<int>(
              value: s['id'] as int,
              child: Text(s['name'] as String,
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 12.5))))
          .toList(),
      onChanged: (val) => setState(() {
        _selectedSubcategoryId = val;
        _selectedUrgentProvider = null;
        _urgentDispatchError = null;
        _scheduleDraftSave();
      }),
      validator: (v) => v == null ? 'اختر التصنيف الفرعي' : null,
    );
  }

  Widget _deadlineTile() {
    final hasDate = _quoteDeadline != null;
    return InkWell(
      onTap: () async {
        await _selectDeadline();
        _scheduleDraftSave();
      },
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.primarySurface,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: const Icon(Icons.calendar_today_outlined,
                color: _mainColor, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  hasDate
                      ? DateFormat('dd MMMM yyyy', 'ar').format(_quoteDeadline!)
                      : 'تحديد تاريخ آخر موعد',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: hasDate ? _inkColor : AppColors.grey500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasDate
                      ? 'سيتوقف استقبال العروض بعد هذا التاريخ.'
                      : 'اضغط لاختيار آخر موعد لاستقبال العروض.',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.grey500,
                  ),
                ),
              ],
            ),
          ),
          if (hasDate)
            IconButton(
              onPressed: () => setState(() {
                _quoteDeadline = null;
                _scheduleDraftSave();
              }),
              icon: const Icon(Icons.close_rounded,
                  size: 18, color: AppColors.grey500),
              tooltip: 'مسح',
              splashRadius: 18,
            )
          else
            const Icon(Icons.chevron_left_rounded,
                color: AppColors.grey400, size: 22),
        ]),
      ),
    );
  }

  Widget _attachmentsPreview() {
    final isEmpty = _images.isEmpty &&
        _videos.isEmpty &&
        _files.isEmpty &&
        _audioPath == null;

    return AnimatedSize(
      duration: AppDurations.normal,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: AppDurations.normal,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) =>
            FadeTransition(opacity: animation, child: child),
        child: Column(
          key: ValueKey<bool>(isEmpty),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        if (isEmpty)
          InkWell(
            onTap: _showAttachmentOptions,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 22),
              decoration: BoxDecoration(
                color: AppColors.primarySurface.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: _mainColor.withValues(alpha: 0.18),
                  width: 1.2,
                ),
              ),
              child: const Column(
                children: [
                  Icon(Icons.cloud_upload_outlined,
                      color: _mainColor, size: 28),
                  SizedBox(height: 8),
                  Text(
                    'اضغط لإضافة صورة أو فيديو أو ملف',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: _inkColor,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'المرفقات تساعد مقدم الخدمة على فهم طلبك بشكل أدق.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.grey500,
                    ),
                  ),
                ],
              ),
            ),
          )
        else ...[
          if (_images.isNotEmpty) ...[
            _attachmentGroupLabel('الصور', _images.length),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _images
                  .map((image) => Stack(
                        children: [
                          ClipRRect(
                            borderRadius:
                                BorderRadius.circular(AppRadius.sm),
                            child: Image.file(
                              image,
                              width: 84,
                              height: 84,
                              fit: BoxFit.cover,
                            ),
                          ),
                          PositionedDirectional(
                            top: 4,
                            start: 4,
                            child: InkWell(
                              onTap: () {
                                HapticFeedback.lightImpact();
                                setState(() => _images.remove(image));
                              },
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.62),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close_rounded,
                                  size: 14,
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
            _attachmentGroupLabel('الفيديوهات', _videos.length),
            const SizedBox(height: 8),
            ..._videos.map(
              (video) => _buildAttachmentListItem(
                icon: Icons.videocam_outlined,
                name: video.path.split('/').last,
                onRemove: () {
                  HapticFeedback.lightImpact();
                  setState(() => _videos.remove(video));
                },
              ),
            ),
          ],
          if (_files.isNotEmpty) ...[
            const SizedBox(height: 14),
            _attachmentGroupLabel('الملفات', _files.length),
            const SizedBox(height: 8),
            ..._files.map(
              (file) => _buildAttachmentListItem(
                icon: Icons.insert_drive_file_outlined,
                name: file.path.split('/').last,
                onRemove: () {
                  HapticFeedback.lightImpact();
                  setState(() => _files.remove(file));
                },
              ),
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _showAttachmentOptions,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text(
              'إضافة مرفق آخر',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: _mainColor,
              side: BorderSide(
                color: _mainColor.withValues(alpha: 0.45),
              ),
              minimumSize: const Size(double.infinity, 42),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
            ),
          ),
        ],
          ],
        ),
      ),
    );
  }

  Widget _attachmentGroupLabel(String label, int count) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: AppTextStyles.textSecondary,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.grey100,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: AppColors.grey600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _audioPart() {
    final hasAudio = _audioPath != null;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(children: [
        Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: _isRecording
                  ? AppColors.errorSurface
                  : AppColors.primarySurface,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              onPressed: _toggleRecording,
              icon: Icon(
                _isRecording ? Icons.stop_rounded : Icons.mic_none_rounded,
                size: 22,
              ),
              color: _isRecording ? AppColors.error : _mainColor,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isRecording
                      ? 'جارٍ تسجيل الرسالة…'
                      : hasAudio
                          ? 'تم تجهيز الرسالة الصوتية'
                          : 'أضف ملاحظة صوتية قصيرة',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: _isRecording ? AppColors.error : _inkColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _isRecording
                      ? 'اضغط للإيقاف وحفظ التسجيل.'
                      : hasAudio
                          ? 'يمكنك حذف التسجيل أو إبقاؤه ضمن الطلب.'
                          : 'مفيدة لشرح تفاصيل تحتاج إلى توضيح إضافي.',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.grey500,
                  ),
                ),
              ],
            ),
          ),
        ]),
        if (hasAudio)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => setState(() => _audioPath = null),
              icon: const Icon(Icons.delete_outline_rounded, size: 16),
              label: const Text(
                'حذف التسجيل',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.error,
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _buildFormHeader() {
    final progress = _completionProgress;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF60269E), Color(0xFF8B3FC0)],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.30),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 58,
            height: 58,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 3.5,
                  backgroundColor: Colors.white.withValues(alpha: 0.22),
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
                Text(
                  '${(progress * 100).round()}%',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
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
                    fontSize: AppTextStyles.h2,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _requestTypeDescription,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    height: 1.55,
                    color: Colors.white.withValues(alpha: 0.82),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDraftNotice() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: _mainColor.withValues(alpha: 0.18)),
      ),
      child: const Row(
        children: [
          Icon(Icons.history_rounded, size: 16, color: _mainColor),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'تم استرجاع آخر مسودة محفوظة محليًا. المرفقات لا تُحفظ داخل المسودة.',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 10.8,
                fontWeight: FontWeight.w700,
                color: _inkColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required Widget child,
    String? trailingHint,
    IconData? icon,
    int? stepNumber,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: _isDark ? AppColors.cardDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: _isDark ? [] : AppShadows.card,
        border: _isDark ? Border.all(color: AppColors.borderDark) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _mainColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Icon(icon, size: 18, color: _mainColor),
                    ),
                    if (stepNumber != null)
                      PositionedDirectional(
                        top: -5,
                        end: -5,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: const BoxDecoration(
                            color: _mainColor,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '$stepNumber',
                              style: const TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                fontFamily: 'Cairo',
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ] else
                Container(
                  width: 3,
                  height: 16,
                  decoration: BoxDecoration(
                    color: _mainColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              SizedBox(width: icon != null ? 10 : 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: AppTextStyles.h2,
                    fontWeight: FontWeight.w900,
                    color: _isDark ? AppTextStyles.textPrimaryDark : _inkColor,
                  ),
                ),
              ),
              if (trailingHint != null)
                Text(
                  trailingHint,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: AppTextStyles.caption,
                    fontWeight: FontWeight.w700,
                    color: AppColors.grey400,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          child,
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.grey50,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.primarySurface,
              borderRadius: BorderRadius.circular(AppRadius.xs),
            ),
            child: Icon(icon, color: _mainColor, size: 17),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: _inkColor,
              ),
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded,
                color: AppColors.grey500, size: 18),
            splashRadius: 18,
            tooltip: 'إزالة',
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: Semantics(
            label: 'تقديم الطلب',
            button: true,
            enabled: !_submitting,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submitRequest,
              style: ElevatedButton.styleFrom(
                backgroundColor: _mainColor,
                disabledBackgroundColor: _mainColor.withValues(alpha: 0.55),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
              child: AnimatedSwitcher(
                duration: AppDurations.fast,
                transitionBuilder: (child, anim) =>
                    FadeTransition(opacity: anim, child: child),
                child: _submitting
                    ? const SizedBox(
                        key: ValueKey('submit-loading'),
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'تقديم الطلب',
                        key: ValueKey('submit-label'),
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.grey500,
            minimumSize: const Size(double.infinity, 40),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
          child: const Text(
            'إلغاء',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSheetActionItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minLeadingWidth: 40,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.primarySurface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Icon(icon, color: _mainColor, size: 18),
      ),
      title: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
          color: _inkColor,
        ),
      ),
      trailing: const Icon(Icons.chevron_left_rounded,
          color: AppColors.grey400, size: 20),
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
