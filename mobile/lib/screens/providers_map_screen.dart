// ignore_for_file: unused_element
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/service_provider_location.dart';
import '../services/api_client.dart';
import '../services/app_logger.dart';
import '../services/home_service.dart';
import '../services/providers_api_service.dart';
import '../models/category_model.dart';
import '../constants/saudi_cities.dart';
import '../constants/app_theme.dart';
import '../widgets/excellence_badges_wrap.dart';
import '../widgets/verified_badge_view.dart';
import 'chat_detail_screen.dart';
import 'provider_profile_screen.dart';

class ProvidersMapScreen extends StatefulWidget {
  final String category;
  final String? subCategory;
  final String? requestDescription;
  final List<String>? attachments;
  final String? cityFilter;
  final bool urgentOnly;

  const ProvidersMapScreen({
    super.key,
    required this.category,
    this.subCategory,
    this.requestDescription,
    this.attachments,
    this.cityFilter,
    this.urgentOnly = false,
  });

  @override
  State<ProvidersMapScreen> createState() => _ProvidersMapScreenState();
}

class _ProvidersMapScreenState extends State<ProvidersMapScreen>
  with SingleTickerProviderStateMixin {
  static const Color _mainColor = AppColors.teal;
  static const Color _accentColor = Color(0xFF115E59);
  static const Color _inkColor = AppTextStyles.textPrimary;
  MapController? _mapController;
  bool _isMapReady = false;
  Position? _currentPosition;
  bool _isLoadingLocation = true;
  List<Marker> _markers = [];
  ServiceProviderLocation? _selectedProvider;

  late final TextEditingController _searchController;
  late final AnimationController _entranceController;
  String _selectedSort = 'nearest';
  
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  
  // بيانات تجريبية لمقدمي الخدمات
  List<ServiceProviderLocation> _providers = [];
  List<ServiceProviderLocation> _filteredProviders = [];

  // ألوان حسب التصنيف
  final Map<String, Color> _categoryColors = {
    "صيانة المركبات": Colors.blue,
    "خدمات المنازل": Colors.green,
    "استشارات قانونية": Colors.purple,
  };

  String _formatPhoneE164(String rawPhone) {
    final phone = rawPhone.replaceAll(RegExp(r'\s+'), '');
    if (phone.startsWith('+')) return phone;

    // KSA common formats: 05XXXXXXXX or 5XXXXXXXX
    if (phone.startsWith('05') && phone.length == 10) {
      return '+966${phone.substring(1)}';
    }
    if (phone.startsWith('5') && phone.length == 9) {
      return '+966$phone';
    }

    return phone;
  }

  String _buildWhatsAppMessage(ServiceProviderLocation provider) {
    final serviceLine = widget.subCategory != null && widget.subCategory!.isNotEmpty
        ? '${widget.category} - ${widget.subCategory}'
        : widget.category;

    final buffer = StringBuffer();
    buffer.writeln('@${provider.name}');
    buffer.writeln('السلام عليكم');
    buffer.writeln('أنا عميل في منصة (نوافذ)');
    buffer.writeln('أتواصل معك بخصوص طلب خدمة في $serviceLine');

    final desc = widget.requestDescription?.trim();
    if (desc != null && desc.isNotEmpty) {
      buffer.writeln('الوصف: $desc');
    }

    return buffer.toString().trim();
  }

  Future<void> _openPhoneCall(ServiceProviderLocation provider) async {
    final e164 = _formatPhoneE164(provider.phoneNumber);
    final uri = Uri(scheme: 'tel', path: e164);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تعذر فتح الاتصال')),
    );
  }

  Future<void> _openWhatsApp(ServiceProviderLocation provider) async {
    final e164 = _formatPhoneE164(provider.phoneNumber);
    final waPhone = e164.replaceAll('+', '');
    final message = _buildWhatsAppMessage(provider);
    final encoded = Uri.encodeComponent(message);

    final appUri = Uri.parse('whatsapp://send?phone=$waPhone&text=$encoded');
    final webUri = Uri.parse('https://wa.me/$waPhone?text=$encoded');

    if (await canLaunchUrl(appUri)) {
      await launchUrl(appUri, mode: LaunchMode.externalApplication);
      return;
    }
    if (await canLaunchUrl(webUri)) {
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تعذر فتح واتساب')),
    );
  }

  void _openChat(ServiceProviderLocation provider) {
    final peerProviderId = int.tryParse(provider.id);
    if (peerProviderId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح المحادثة: معرف المزود غير صالح')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatDetailScreen(
          peerName: provider.name,
          peerPhone: provider.phoneNumber,
          peerProviderId: peerProviderId,
        ),
      ),
    );
  }

  Future<void> _showProviderContactActions(ServiceProviderLocation provider) async {
    final e164 = _formatPhoneE164(provider.phoneNumber);
    final completedRequests = provider.operationsCount;
    final ratingText = provider.rating > 0 ? provider.rating.toStringAsFixed(1) : '-';

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openProviderProfile(provider);
                  },
                  child: Column(
                    children: [
                      Container(
                        width: 68,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.deepPurple.withValues(alpha: 0.25),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: _providerImageWidget(
                            provider.profileImage,
                            width: 68,
                            height: 64,
                            fallbackIconSize: 30,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'عرض صفحة المزود',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.deepPurple.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        provider.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.star, size: 16, color: Colors.amber),
                          const SizedBox(width: 4),
                          Text(
                            ratingText,
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Icon(Icons.check_circle_outline,
                              size: 15, color: AppColors.deepPurple),
                          const SizedBox(width: 4),
                          Text(
                            'الطلبات المكتملة: $completedRequests',
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.deepPurple.withValues(alpha: 0.35)),
                    borderRadius: BorderRadius.circular(12),
                    color: AppColors.deepPurple.withValues(alpha: 0.04),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.call, size: 18, color: AppColors.deepPurple),
                      const SizedBox(width: 8),
                      Text(
                        'Call $e164',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.deepPurple,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.deepPurple.withValues(alpha: 0.35)),
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.white,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildContactIcon(
                        icon: FontAwesomeIcons.whatsapp,
                        label: 'واتس',
                        color: const Color(0xFF25D366),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _openWhatsApp(provider);
                        },
                      ),
                      _buildContactIcon(
                        icon: Icons.call,
                        label: 'اتصال',
                        color: AppColors.deepPurple,
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _openPhoneCall(provider);
                        },
                      ),
                      _buildContactIcon(
                        icon: Icons.chat_bubble_outline,
                        label: 'محادثة',
                        color: AppColors.deepPurple,
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _openChat(provider);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildContactIcon({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: color.withValues(alpha: 0.25)),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchController.addListener(_filterProviders);
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _mapController = MapController();
    _initializeMap();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _entranceController.forward();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _entranceController.dispose();
    _mapController?.dispose();
    _sheetController.dispose();
    super.dispose();
  }

  Future<void> _initializeMap() async {
    await _getCurrentLocation();
    await _loadProviders();
    _filterProviders();
  }

  // ✅ الحصول على الموقع الحالي
  Future<void> _getCurrentLocation() async {
    try {
      // التحقق من الصلاحيات
      LocationPermission permission = await Geolocator.checkPermission();
      
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showPermissionDeniedDialog();
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showPermissionDeniedForeverDialog();
        return;
      }

      // الحصول على الموقع
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      setState(() {
        _currentPosition = position;
        _isLoadingLocation = false;
      });

      // تحريك الخريطة للموقع الحالي
      if (_mapController != null && _isMapReady) {
        _mapController!.move(
          LatLng(position.latitude, position.longitude),
          14.0,
        );
      }
    } catch (e) {
      setState(() {
        _isLoadingLocation = false;
      });
      _showErrorDialog('فشل في تحديد الموقع: $e');
    }
  }

  void _moveMapIfReady(LatLng center, double zoom) {
    if (_mapController == null || !_isMapReady) return;
    _mapController!.move(center, zoom);
  }

  String _norm(String value) => value.trim().toLowerCase();

  Future<Map<String, String>> _resolveCategoryFilters() async {
    final category = widget.category.trim();
    final subCategory = (widget.subCategory ?? '').trim();
    if (category.isEmpty && subCategory.isEmpty) return {};

    try {
      final categories = await HomeService.fetchCategories();
      final targetCategory = _norm(category);
      final targetSub = _norm(subCategory);

      CategoryModel? matchedCategory;
      if (targetCategory.isNotEmpty) {
        for (final cat in categories) {
          if (_norm(cat.name) == targetCategory) {
            matchedCategory = cat;
            break;
          }
        }
      }

      if (targetSub.isNotEmpty) {
        for (final cat in categories) {
          for (final sub in cat.subcategories) {
            if (_norm(sub.name) == targetSub) {
              return {
                'subcategory_id': sub.id.toString(),
                'category_id': cat.id.toString(),
              };
            }
          }
        }
      }

      if (matchedCategory != null) {
        return {'category_id': matchedCategory.id.toString()};
      }
    } catch (error, stackTrace) {
      AppLogger.warn(
        'ProvidersMapScreen._resolveCategoryFilters failed',
        error: error,
        stackTrace: stackTrace,
      );
    }

    final q = subCategory.isNotEmpty ? '$category $subCategory'.trim() : category;
    if (q.isNotEmpty) return {'q': q};
    return {};
  }

  // ✅ تحميل المزودين من الـ API
  Future<void> _loadProviders() async {
    final queryParams = <String, String>{
      'has_location': '1',
    };
    final city = (widget.cityFilter ?? '').trim();
    if (city.isNotEmpty) {
      queryParams['city'] = city;
    }
    if (widget.urgentOnly) {
      queryParams['accepts_urgent'] = '1';
    }
    // يمكن إضافة فلتر المدينة إذا كانت متوفرة
    if (_currentPosition != null) {
      queryParams['lat'] = _currentPosition!.latitude.toString();
      queryParams['lng'] = _currentPosition!.longitude.toString();
    }
    queryParams.addAll(await _resolveCategoryFilters());

    final res = await ProvidersApiService.fetchProvidersList(
      extraQueryParameters: queryParams,
    );
    if (!res.isSuccess) return;

    final rawList = (res.data is List)
        ? res.data as List
        : (res.data is Map && (res.data as Map).containsKey('results'))
            ? (res.data as Map)['results'] as List
            : [];

    _providers = rawList
        .map((e) =>
            ServiceProviderLocation.fromJson(e as Map<String, dynamic>))
        .where((p) => p.latitude != 0.0 && p.longitude != 0.0)
        .toList();

    if (city.isNotEmpty) {
      final cityNorm = _norm(SaudiCities.normalizeScopedCity(city));
      _providers = _providers
        .where((p) {
          final providerScoped = SaudiCities.normalizeScopedCity(
            p.city,
            region: SaudiCities.splitCityScope(p.cityDisplay)['region'],
          );
          return _norm(providerScoped) == cityNorm || _norm(p.cityDisplay) == cityNorm;
        })
        .toList();
    }

    if (widget.urgentOnly) {
      _providers = _providers.where((p) => p.isUrgentEnabled).toList();
    }

    // حساب المسافة لكل مزود
    if (_currentPosition != null) {
      for (var i = 0; i < _providers.length; i++) {
        final provider = _providers[i];
        final distance = Geolocator.distanceBetween(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          provider.latitude,
          provider.longitude,
        ) / 1000; // تحويل إلى كيلومتر
        _providers[i] = provider.copyWith(distanceFromUser: distance);
      }
    }
  }

  // ✅ تصفية المزودين حسب التصنيف
  void _filterProviders() {
    final query = _searchController.text.trim().toLowerCase();

    setState(() {
      _filteredProviders = _providers.where((provider) {
        if (query.isEmpty) return true;
        final haystack = [
          provider.name,
          provider.category,
          provider.subCategory,
          provider.city,
          provider.cityDisplay,
        ].join(' ').toLowerCase();
        return haystack.contains(query);
      }).toList();

      _filteredProviders.sort((a, b) {
        switch (_selectedSort) {
          case 'rating':
            return b.rating.compareTo(a.rating);
          case 'completed':
            return b.operationsCount.compareTo(a.operationsCount);
          case 'response':
            return a.responseTime.compareTo(b.responseTime);
          case 'nearest':
          default:
            final distA = a.distanceFromUser ?? double.infinity;
            final distB = b.distanceFromUser ?? double.infinity;
            final byDistance = distA.compareTo(distB);
            if (byDistance != 0) return byDistance;
            return b.rating.compareTo(a.rating);
        }
      });

      _createMarkers();
    });
  }

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 48,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'فرز النتائج',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: _inkColor,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'اختر طريقة العرض الأنسب للمزوّدين على الخريطة والقائمة.',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 14),
                ...[
                  ('nearest', 'الأقرب إليك', Icons.near_me_outlined),
                  ('rating', 'أعلى تقييم', Icons.star_outline_rounded),
                  ('completed', 'الأكثر طلبات مكتملة', Icons.verified_outlined),
                  ('response', 'الأسرع استجابة', Icons.bolt_outlined),
                ].map((item) {
                  final key = item.$1;
                  final selected = _selectedSort == key;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      onTap: () {
                        Navigator.pop(context);
                        setState(() => _selectedSort = key);
                        _filterProviders();
                      },
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                          color: selected ? _mainColor.withValues(alpha: 0.08) : Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: selected ? _mainColor : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(item.$3, color: selected ? _mainColor : const Color(0xFF64748B)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                item.$2,
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: selected ? _mainColor : _inkColor,
                                ),
                              ),
                            ),
                            if (selected)
                              const Icon(Icons.check_circle_rounded, color: _mainColor, size: 20),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  String _sortLabel() {
    switch (_selectedSort) {
      case 'rating':
        return 'أعلى تقييم';
      case 'completed':
        return 'الأكثر طلبات';
      case 'response':
        return 'الأسرع استجابة';
      case 'nearest':
      default:
        return 'الأقرب';
    }
  }

  // ✅ إنشاء الماركرز
  void _createMarkers() {
    final List<Marker> markers = [];

    // موقع المستخدم
    if (_currentPosition != null) {
      markers.add(
        Marker(
          point: LatLng(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
          ),
          width: 80,
          height: 80,
          child: const Icon(
            Icons.my_location,
            color: Colors.blue,
            size: 40,
          ),
        ),
      );
    }

    // مقدمو الخدمات
    for (var provider in _filteredProviders) {
      final color = _categoryColors[provider.category] ?? Colors.red;
      
      markers.add(
        Marker(
          point: LatLng(provider.latitude, provider.longitude),
          width: 80,
          height: 80,
          child: GestureDetector(
            onTap: () {
              setState(() {
                _selectedProvider = provider;
              });
              _animateToProvider(provider);
              _showProviderContactActions(provider);
            },
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.location_on,
                    color: color,
                    size: 32,
                  ),
                ),
                if (_selectedProvider?.id == provider.id)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Text(
                      provider.name,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo',
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    setState(() {
      _markers = markers;
    });
  }

  // ✅ تحريك الخريطة لموقع المزود
  void _animateToProvider(ServiceProviderLocation provider) {
    // Avoid calling move() before FlutterMap is rendered at least once.
    _moveMapIfReady(
      LatLng(provider.latitude, provider.longitude),
      15.0,
    );
  }

  // ✅ فتح بروفايل مقدم الخدمة
  Future<void> _openProviderProfile(ServiceProviderLocation provider) async {
    setState(() {
      _selectedProvider = provider;
    });
    _animateToProvider(provider);
    
    // فتح صفحة البروفايل
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProviderProfileScreen(
          providerId: provider.id,
          providerName: provider.name,
          providerCategory: provider.category,
          providerSubCategory: provider.subCategory,
          providerRating: provider.rating,
          providerOperations: provider.operationsCount,
          providerImage: provider.profileImage,
          providerVerifiedBlue: provider.isVerifiedBlue,
          providerVerifiedGreen: provider.isVerifiedGreen,
          providerPhone: provider.phoneNumber,
          providerLat: provider.latitude,
          providerLng: provider.longitude,
          showBackToMapButton: true,
        ),
      ),
    );
    // عند الرجوع، لا نعيد تحميل البيانات - الخريطة تبقى كما هي
  }

  // ✅ Dialogs
  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('نحتاج للوصول إلى موقعك'),
        content: const Text(
          'لعرض مقدمي الخدمات القريبين، نحتاج للوصول إلى موقعك الحالي.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _getCurrentLocation();
            },
            child: const Text('السماح'),
          ),
        ],
      ),
    );
  }

  void _showPermissionDeniedForeverDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('الصلاحية مرفوضة'),
        content: const Text(
          'تم رفض صلاحية الموقع بشكل دائم. يرجى تفعيلها من إعدادات التطبيق.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('إغلاق'),
          ),
          ElevatedButton(
            onPressed: () async {
              await Geolocator.openAppSettings();
              if (!context.mounted) return;
              Navigator.pop(context);
            },
            child: const Text('فتح الإعدادات'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('خطأ'),
        content: Text(message),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }

  Widget _providerImageWidget(
    String? rawPath, {
    double width = 60,
    double height = 60,
    double fallbackIconSize = 32,
  }) {
    final value = (rawPath ?? '').trim();
    if (value.isEmpty) {
      return Icon(Icons.person, size: fallbackIconSize);
    }

    final mediaUrl = value.startsWith('http') ? value : ApiClient.buildMediaUrl(value);
    if (mediaUrl != null && mediaUrl.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: mediaUrl,
        fit: BoxFit.cover,
        width: width,
        height: height,
        errorWidget: (_, __, ___) {
          if (value.startsWith('assets/')) {
            return Image.asset(
              value,
              fit: BoxFit.cover,
              width: width,
              height: height,
              errorBuilder: (_, __, ___) => Icon(Icons.person, size: fallbackIconSize),
            );
          }
          return Icon(Icons.person, size: fallbackIconSize);
        },
      );
    }

    if (value.startsWith('assets/')) {
      return Image.asset(
        value,
        fit: BoxFit.cover,
        width: width,
        height: height,
        errorBuilder: (_, __, ___) => Icon(Icons.person, size: fallbackIconSize),
      );
    }
    return Icon(Icons.person, size: fallbackIconSize);
  }

  // ✅ عرض dialog تأكيد إرسال الطلب مع التفاصيل
  Future<void> _showSendRequestDialog(ServiceProviderLocation provider) async {
    final navigator = Navigator.of(context);
    await showDialog(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.send, color: AppColors.deepPurple),
              const SizedBox(width: 8),
              const Text(
                'تأكيد إرسال الطلب',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 18),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // معلومات المزود
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          width: 50,
                          height: 50,
                          color: Colors.grey.shade300,
                          child: _providerImageWidget(
                            provider.profileImage,
                            width: 50,
                            height: 50,
                            fallbackIconSize: 24,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    provider.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      fontFamily: 'Cairo',
                                    ),
                                  ),
                                ),
                                if (provider.verified) ...[
                                  const SizedBox(width: 4),
                                  VerifiedBadgeView(
                                    isVerifiedBlue: provider.isVerifiedBlue,
                                    isVerifiedGreen: provider.isVerifiedGreen,
                                    iconSize: 14,
                                  ),
                                ],
                              ],
                            ),
                            Text(
                              provider.subCategory,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                                fontFamily: 'Cairo',
                              ),
                            ),
                            if (provider.hasExcellenceBadges) ...[
                              const SizedBox(height: 4),
                              ExcellenceBadgesWrap(
                                badges: provider.excellenceBadges,
                                compact: true,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // تفاصيل الطلب
                const Text(
                  'تفاصيل الطلب:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    fontFamily: 'Cairo',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'التصنيف: ${widget.category}',
                  style: const TextStyle(fontSize: 13, fontFamily: 'Cairo'),
                ),
                if (widget.subCategory != null)
                  Text(
                    'التصنيف الفرعي: ${widget.subCategory}',
                    style: const TextStyle(fontSize: 13, fontFamily: 'Cairo'),
                  ),
                if (widget.requestDescription != null &&
                    widget.requestDescription!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Divider(),
                  const Text(
                    'الوصف:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      fontFamily: 'Cairo',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Text(
                      widget.requestDescription!,
                      style: const TextStyle(fontSize: 13, fontFamily: 'Cairo'),
                    ),
                  ),
                ],
                if (widget.attachments != null &&
                    widget.attachments!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Divider(),
                  Row(
                    children: [
                      const Icon(Icons.attach_file, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        'المرفقات: ${widget.attachments!.length}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 16, color: Colors.orange.shade700),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'سيتم إرسال هذا الطلب إلى ${provider.name}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange.shade700,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await _showProviderContactActions(provider);
                if (!mounted) return;
                navigator.pop({
                  'provider': provider,
                  'description': widget.requestDescription,
                  'attachments': widget.attachments,
                });
              },
              icon: const Icon(Icons.send, size: 16),
              label: const Text('إرسال', style: TextStyle(fontFamily: 'Cairo')),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.deepPurple,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoadingLocation
          ? _buildLoadingScreen()
          : _filteredProviders.isEmpty
              ? _buildEmptyState()
              : _buildMapWithSheet(),
    );
  }

  // ✅ شاشة التحميل
  Widget _buildLoadingScreen() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFEFFCFA), Color(0xFFF7FFFD), Colors.white],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 28),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: _mainColor.withValues(alpha: 0.10),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(_mainColor),
              ),
              SizedBox(height: 18),
              Text(
                'جارٍ تحديد موقعك وتحميل المزوّدين...',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Cairo',
                  color: _inkColor,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'سنرتب النتائج على الخريطة حسب موقعك الحالي فور اكتمال التحميل.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ✅ حالة فارغة
  Widget _buildEmptyState() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFEFFCFA), Color(0xFFF7FFFD), Colors.white],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: _mainColor.withValues(alpha: 0.10),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: _mainColor.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.search_off_rounded, size: 42, color: _mainColor),
                ),
                const SizedBox(height: 20),
                const Text(
                  'لا يوجد مزودون مطابقون حاليًا',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'Cairo',
                    color: _inkColor,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                const Text(
                  'جرّب توسيع نطاق المدينة، تعديل التخصص، أو العودة لاختيار خدمة مختلفة.',
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF64748B),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 22),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('العودة', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _mainColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ✅ الخريطة مع القائمة السفلية
  Widget _buildMapWithSheet() {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _currentPosition != null
                ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
                : const LatLng(24.7136, 46.6753),
            initialZoom: 14.0,
            minZoom: 5.0,
            maxZoom: 18.0,
            onMapReady: () {
              // Mark as ready; controller is created in initState.
              _isMapReady = true;
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.nawafeth',
            ),
            MarkerLayer(
              markers: _markers,
            ),
          ],
        ),

        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _buildEntrance(
                0,
                Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF115E59), Color(0xFF0F766E), Color(0xFF14B8A6)],
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                    ),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: _accentColor.withValues(alpha: 0.22),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        top: -36,
                        left: -18,
                        child: Container(
                          width: 126,
                          height: 126,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.10),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                InkWell(
                                  onTap: () => Navigator.pop(context),
                                  borderRadius: BorderRadius.circular(16),
                                  child: Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.category,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w900,
                                          fontFamily: 'Cairo',
                                          color: Colors.white,
                                        ),
                                      ),
                                      if ((widget.subCategory ?? '').trim().isNotEmpty)
                                        Text(
                                          widget.subCategory!,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                            fontFamily: 'Cairo',
                                            color: Colors.white.withValues(alpha: 0.84),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    '${_filteredProviders.length} مزود',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      fontFamily: 'Cairo',
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'استعرض المزوّدين على الخريطة، وابحث بينهم بالاسم أو التخصص، ثم اختر الأنسب مباشرة.',
                              style: TextStyle(
                                fontSize: 11.2,
                                height: 1.7,
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.w700,
                                color: Colors.white.withValues(alpha: 0.86),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: TextField(
                                controller: _searchController,
                                style: const TextStyle(fontFamily: 'Cairo', fontSize: 12.5, color: _inkColor),
                                decoration: InputDecoration(
                                  hintText: 'ابحث بالاسم أو التخصص أو المدينة',
                                  hintStyle: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 11.5,
                                    color: Colors.grey.shade500,
                                  ),
                                  prefixIcon: const Icon(Icons.search_rounded, color: _mainColor),
                                  suffixIcon: _searchController.text.trim().isEmpty
                                      ? null
                                      : IconButton(
                                          onPressed: () {
                                            _searchController.clear();
                                            _filterProviders();
                                          },
                                          icon: const Icon(Icons.close_rounded, size: 18),
                                        ),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _headerChip(Icons.sort_rounded, _sortLabel()),
                                if ((widget.cityFilter ?? '').trim().isNotEmpty)
                                  _headerChip(Icons.location_city_outlined, widget.cityFilter!),
                                if (widget.urgentOnly)
                                  _headerChip(Icons.flash_on_rounded, 'عاجل فقط'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        Positioned(
          bottom: 290,
          left: 16,
          child: _buildEntrance(
            1,
            Column(
              children: [
                FloatingActionButton(
                  heroTag: 'providers-map-location',
                  mini: true,
                  backgroundColor: Colors.white,
                  onPressed: () {
                    if (_currentPosition != null && _mapController != null) {
                      _moveMapIfReady(
                        LatLng(
                          _currentPosition!.latitude,
                          _currentPosition!.longitude,
                        ),
                        14.0,
                      );
                    }
                  },
                  child: const Icon(Icons.my_location_rounded, color: _mainColor),
                ),
                const SizedBox(height: 10),
                FloatingActionButton(
                  heroTag: 'providers-map-sort',
                  mini: true,
                  backgroundColor: Colors.white,
                  onPressed: _showSortSheet,
                  child: const Icon(Icons.tune_rounded, color: _mainColor),
                ),
              ],
            ),
          ),
        ),

        DraggableScrollableSheet(
          controller: _sheetController,
          initialChildSize: 0.35,
          minChildSize: 0.15,
          maxChildSize: 0.75,
          builder: (context, scrollController) {
            return _buildEntrance(
              2,
              Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 20,
                      offset: Offset(0, -6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: _mainColor.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.map_outlined, color: _mainColor),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'المزوّدون المطابقون',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                    fontFamily: 'Cairo',
                                    color: _inkColor,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${_filteredProviders.length} نتيجة بعد البحث والفرز الحالي',
                                  style: const TextStyle(
                                    fontSize: 10.8,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'Cairo',
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _showSortSheet,
                            icon: const Icon(Icons.tune_rounded, size: 16),
                            label: Text(
                              _sortLabel(),
                              style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800),
                            ),
                            style: TextButton.styleFrom(foregroundColor: _mainColor),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                        itemCount: _filteredProviders.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final provider = _filteredProviders[index];
                          return _buildProviderCard(provider);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _headerChip(IconData icon, String label) {
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
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              fontFamily: 'Cairo',
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // ✅ بطاقة مقدم الخدمة
  Widget _buildProviderCard(ServiceProviderLocation provider) {
    final isSelected = _selectedProvider?.id == provider.id;
    final distanceText = provider.distanceFromUser != null
        ? '${provider.distanceFromUser!.toStringAsFixed(1)} كم'
        : 'غير محددة';

    return InkWell(
      onTap: () {
        _openProviderProfile(provider);
      },
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? _mainColor.withValues(alpha: 0.06) : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isSelected
                ? _mainColor
                : Colors.grey.shade200,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: _mainColor.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: 68,
                    height: 68,
                    color: Colors.grey.shade200,
                    child: _providerImageWidget(
                      provider.profileImage,
                      width: 68,
                      height: 68,
                      fallbackIconSize: 32,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              provider.name,
                              style: const TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w900,
                                fontFamily: 'Cairo',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (provider.verified) ...[
                            const SizedBox(width: 6),
                            VerifiedBadgeView(
                              isVerifiedBlue: provider.isVerifiedBlue,
                              isVerifiedGreen: provider.isVerifiedGreen,
                              iconSize: 15,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        provider.subCategory.isNotEmpty ? provider.subCategory : provider.category,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          RatingBarIndicator(
                            rating: provider.rating,
                            itemBuilder: (_, __) => const Icon(
                              Icons.star,
                              color: Colors.amber,
                            ),
                            itemCount: 5,
                            itemSize: 14,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${provider.rating}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _metricBadge(Icons.location_on_outlined, distanceText, const Color(0xFF2563EB)),
                          _metricBadge(Icons.verified_outlined, '${provider.operationsCount} طلب مكتمل', _mainColor),
                          if (provider.isUrgentEnabled)
                            _metricBadge(Icons.flash_on_rounded, 'يقبل عاجل', const Color(0xFFDC2626)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (provider.hasExcellenceBadges) ...[
              const SizedBox(height: 10),
              ExcellenceBadgesWrap(
                badges: provider.excellenceBadges,
                compact: true,
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      _buildContactIcon(
                        icon: FontAwesomeIcons.whatsapp,
                        label: 'واتساب',
                        color: const Color(0xFF25D366),
                        onTap: () => _openWhatsApp(provider),
                      ),
                      _buildContactIcon(
                        icon: Icons.call,
                        label: 'اتصال',
                        color: _mainColor,
                        onTap: () => _openPhoneCall(provider),
                      ),
                      _buildContactIcon(
                        icon: Icons.chat_bubble_outline,
                        label: 'محادثة',
                        color: _mainColor,
                        onTap: () => _openChat(provider),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _showProviderContactActions(provider),
                  icon: const Icon(Icons.more_horiz_rounded, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricBadge(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              fontFamily: 'Cairo',
              color: color,
            ),
          ),
        ],
      ),
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
