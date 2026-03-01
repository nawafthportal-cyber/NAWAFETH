import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../widgets/app_bar.dart';
import '../widgets/custom_drawer.dart';
import '../widgets/auto_scrolling_reels_row.dart';
import '../widgets/platform_report_dialog.dart';
import '../widgets/video_reels.dart';
import '../widgets/video_full_screen.dart';
import '../services/interactive_service.dart';
import '../services/api_client.dart';
import '../models/provider_public_model.dart';
import 'chat_detail_screen.dart';
import 'provider_dashboard/reviews_tab.dart';
import 'service_detail_screen.dart';
import 'service_request_form_screen.dart';

class ProviderProfileScreen extends StatefulWidget {
  final String? providerId;
  final String? providerName;
  final String? providerCategory;
  final String? providerSubCategory;
  final double? providerRating;
  final int? providerOperations;
  final String? providerImage;
  final bool? providerVerified;
  final String? providerPhone;
  final double? providerLat;
  final double? providerLng;

  const ProviderProfileScreen({
    super.key,
    this.providerId,
    this.providerName,
    this.providerCategory,
    this.providerSubCategory,
    this.providerRating,
    this.providerOperations,
    this.providerImage,
    this.providerVerified,
    this.providerPhone,
    this.providerLat,
    this.providerLng,
  });

  @override
  State<ProviderProfileScreen> createState() => _ProviderProfileScreenState();
}

class _ProviderProfileScreenState extends State<ProviderProfileScreen> {
  final Color mainColor = Colors.deepPurple;

  int _selectedTabIndex = 0;

  bool _isBookmarked = false;
  final bool _isOnline = true;
  bool _isLoading = true;

  // ── بيانات من API ──
  ProviderPublicModel? _providerDetail;
  Map<String, dynamic>? _statsData;
  List<Map<String, dynamic>> _apiServices = [];
  List<Map<String, dynamic>> _apiPortfolio = [];
  List<Map<String, dynamic>> _apiSpotlights = [];

  // لمحات مقدم الخدمة
  List<String> get _highlightsVideos {
    return _apiSpotlights
        .where((s) => (s['file_type'] ?? '') == 'video')
        .map((s) => s['file_url'] as String? ?? '')
        .where((url) => url.isNotEmpty)
        .toList();
  }

  List<String> get _highlightsLogos {
    return _apiSpotlights
        .map((s) => s['thumbnail_url'] as String? ?? s['file_url'] as String? ?? '')
        .where((url) => url.isNotEmpty)
        .toList();
  }

  // عدادات أعلى الصفحة
  int get _completedRequests =>
      _statsData?['completed_requests'] as int? ??
      _providerDetail?.completedRequests ??
      0;
  int get _followersCount =>
      _statsData?['followers_count'] as int? ??
      _providerDetail?.followersCount ??
      0;
  int get _followingCount =>
      _statsData?['following_count'] as int? ??
      _providerDetail?.followingCount ??
      0;
  int get _likesCount =>
      _statsData?['likes_count'] as int? ??
      _providerDetail?.likesCount ??
      0;

  int get _reviewersCount =>
      _statsData?['rating_count'] as int? ??
      _providerDetail?.ratingCount ??
      0;

  final List<Map<String, dynamic>> tabs = const [
    {"title": "الملف الشخصي", "icon": Icons.person_outline},
    {"title": "خدماتي", "icon": Icons.work_outline},
    {"title": "معرض خدماتي", "icon": Icons.photo_library},
    {"title": "المراجعات", "icon": Icons.reviews},
  ];

  // خدمات من API
  List<Map<String, dynamic>> get services => _apiServices;

  late List<Map<String, dynamic>> _servicesData;

  // معرض خدماتي من API — مجموعة حسب subcategory
  List<Map<String, dynamic>> get serviceGallerySections {
    if (_apiPortfolio.isEmpty) return [];
    // Group portfolio items by caption prefix or return as single section
    return [
      {
        'title': 'أعمالي',
        'items': _apiPortfolio.map((item) {
          final fileType = (item['file_type'] ?? 'image') as String;
          final fileUrl = item['file_url'] as String? ?? '';
          final thumbnailUrl = item['thumbnail_url'] as String? ?? '';
          return {
            'type': fileType == 'video' ? 'video' : 'image',
            'media': fileUrl.isNotEmpty ? fileUrl : thumbnailUrl,
            'desc': item['caption'] as String? ?? '',
          };
        }).toList(),
      },
    ];
  }

  String get providerName =>
      _providerDetail?.displayName ?? widget.providerName ?? 'مزود خدمة';

  String get providerCategory =>
      widget.providerCategory ?? '';

  String get providerSubCategory =>
      widget.providerSubCategory ?? '';

  double get providerRating =>
      _providerDetail?.ratingAvg ?? widget.providerRating ?? 0.0;

  int get providerOperations =>
      _providerDetail?.completedRequests ?? widget.providerOperations ?? 0;

  String get providerImage =>
      _providerDetail?.profileImage ?? widget.providerImage ?? 'assets/images/8410.jpeg';

  bool get providerVerified =>
      _providerDetail?.isVerified ?? widget.providerVerified ?? false;

  String get providerPhone =>
      _providerDetail?.phone ?? widget.providerPhone ?? '';

  String get providerHandle =>
      _providerDetail?.username != null ? '@${_providerDetail!.username}' : '';

  String get providerEnglishName => '';

  String get providerAccountType => providerCategory;

  String get providerServicesDetails =>
      _providerDetail?.aboutDetails ?? _providerDetail?.bio ?? '';

  String get providerQualifications =>
      _providerDetail?.qualifications ?? '';

  String get providerExperienceYears {
    final years = _providerDetail?.yearsExperience;
    if (years == null || years == 0) return '';
    return '$years سنوات';
  }

  String get providerCommunicationLanguage =>
      _providerDetail?.languages ?? '';

  String get providerGeoScope {
    final radius = _providerDetail?.coverageRadiusKm;
    final city = _providerDetail?.city ?? '';
    if (radius != null && radius > 0) {
      return '$city (ضمن نطاق ${radius.toStringAsFixed(0)} كم)';
    }
    return city;
  }

  String get providerCityName => _providerDetail?.city ?? '';
  String get providerRegionName => '';
  String get providerCountryName => '';

  double get providerLat => _providerDetail?.lat ?? widget.providerLat ?? 0;
  double get providerLng => _providerDetail?.lng ?? widget.providerLng ?? 0;
  int? get _resolvedProviderId {
    final fromDetail = _providerDetail?.id;
    if (fromDetail != null && fromDetail > 0) return fromDetail;
    final fromWidget = int.tryParse(widget.providerId ?? '');
    if (fromWidget != null && fromWidget > 0) return fromWidget;
    return null;
  }

  int get _serviceRangeKm =>
      (_providerDetail?.coverageRadiusKm?.toInt()) ?? 5;

  String _extractSocialHandle(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return '';

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return trimmed;

    final segments = uri.pathSegments.where((s) => s.trim().isNotEmpty).toList();
    if (segments.isEmpty) return trimmed;
    return '@${segments.last}';
  }

  String _geoScopeDisplayValue() {
    final radius = _serviceRangeKm;
    final city = providerCityName;
    if (radius > 0 && city.isNotEmpty) {
      return 'ضمن نطاق محدد: $radius كم ($city)';
    }
    if (city.isNotEmpty) return 'مدينتي: $city';
    return 'ضمن نطاق محدد: $radius كم';
  }

  Widget _serviceRangeMap({
    required Color borderColor,
    required bool isDark,
  }) {
    final center = LatLng(providerLat, providerLng);
    final radiusMeters = _serviceRangeKm * 1000.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'خريطة نطاق الخدمة (ضمن نطاق محدد)',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.grey[400]! : Colors.grey[700]!,
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 220,
            decoration: BoxDecoration(
              border: Border.all(color: borderColor),
              color: isDark ? Colors.grey[900] : Colors.grey.shade50,
            ),
            child: FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: 12,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.nawafeth.app',
                ),
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: center,
                      radius: radiusMeters,
                      useRadiusInMeter: true,
                      color: mainColor.withAlpha(35),
                      borderColor: mainColor.withAlpha(160),
                      borderStrokeWidth: 2,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: center,
                      width: 44,
                      height: 44,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 10,
                              offset: Offset(0, 4),
                            )
                          ],
                        ),
                        child: Icon(Icons.location_on, color: mainColor, size: 26),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String get providerWebsite =>
      _providerDetail?.website ?? '';

  String get providerInstagramUrl =>
      _providerDetail?.socialLinks?['instagram'] as String? ?? '';

  String get providerXUrl =>
      _providerDetail?.socialLinks?['x'] as String? ??
      _providerDetail?.socialLinks?['twitter'] as String? ?? '';

  String get providerSnapchatUrl =>
      _providerDetail?.socialLinks?['snapchat'] as String? ?? '';

  @override
  void initState() {
    super.initState();
    _servicesData = [];
    _loadProviderData();
  }

  Future<void> _loadProviderData() async {
    final idStr = widget.providerId;
    if (idStr == null || idStr.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }
    final providerId = int.tryParse(idStr);
    if (providerId == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      // Fetch all data in parallel
      final results = await Future.wait([
        InteractiveService.fetchProviderDetail(providerId),
        InteractiveService.fetchProviderStats(providerId),
        InteractiveService.fetchProviderServices(providerId),
        InteractiveService.fetchProviderPortfolio(providerId),
        InteractiveService.fetchProviderSpotlights(providerId),
      ]);

      final detailResp = results[0];
      final statsResp = results[1];
      final servicesResp = results[2];
      final portfolioResp = results[3];
      final spotlightsResp = results[4];
      ProviderPublicModel? parsedDetail;
      if (detailResp.isSuccess && detailResp.dataAsMap != null) {
        parsedDetail = ProviderPublicModel.fromJson(detailResp.dataAsMap!);
      }

      if (mounted) {
        setState(() {
          // Provider detail
          if (parsedDetail != null) {
            _providerDetail = parsedDetail;
          }

          // Stats
          if (statsResp.isSuccess && statsResp.dataAsMap != null) {
            _statsData = statsResp.dataAsMap;
          }

          // Services
          if (servicesResp.isSuccess) {
            final list = _parseListResponse(servicesResp);
            final fallbackImage = parsedDetail?.profileImage ?? widget.providerImage ?? '';
            _apiServices = list.map((e) {
              final dynamic rawImage = e['image'] ?? e['thumbnail_url'] ?? fallbackImage;
              final image = rawImage is String ? rawImage : '';
              return <String, dynamic>{
                'id': e['id'],
                'title': e['title'] ?? '',
                'description': e['description'] ?? '',
                'image': image,
                'likes': _asInt(e['likes_count']),
                'files': _asInt(e['files_count']),
                'comments': _asInt(e['comments_count']),
                'price_from': e['price_from'],
                'price_to': e['price_to'],
                'price_unit': e['price_unit'] ?? '',
                'subcategory': e['subcategory'],
                'isLiked': false,
              };
            }).toList();
            _servicesData = List.from(_apiServices);
          }

          // Portfolio
          if (portfolioResp.isSuccess) {
            _apiPortfolio = _parseListResponse(portfolioResp);
          }

          // Spotlights
          if (spotlightsResp.isSuccess) {
            _apiSpotlights = _parseListResponse(spotlightsResp);
          }

          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<Map<String, dynamic>> _parseListResponse(ApiResponse resp) {
    final data = resp.data;
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    if (data is Map && data.containsKey('results')) {
      return (data['results'] as List).cast<Map<String, dynamic>>();
    }
    return [];
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }

  String _formatPhoneE164(String rawPhone) {
    final phone = rawPhone.replaceAll(RegExp(r'\s+'), '');
    if (phone.startsWith('+')) return phone;

    if (phone.startsWith('05') && phone.length == 10) {
      return '+966${phone.substring(1)}';
    }
    if (phone.startsWith('5') && phone.length == 9) {
      return '+966$phone';
    }
    return phone;
  }

  Future<void> _openPhoneCall() async {
    final e164 = _formatPhoneE164(providerPhone);
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

  String _buildWhatsAppMessage() {
    final buffer = StringBuffer();
    buffer.writeln('@${providerName.replaceAll(' ', '')}');
    buffer.writeln('السلام عليكم');
    buffer.writeln('أتواصل معك بخصوص خدماتك المعروضة في منصة (نوافذ)');
    return buffer.toString().trim();
  }

  Future<void> _openWhatsApp() async {
    final e164 = _formatPhoneE164(providerPhone);
    final waPhone = e164.replaceAll('+', '');
    final encoded = Uri.encodeComponent(_buildWhatsAppMessage());
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

  Future<void> _openInAppChat() async {
    final providerId = _resolvedProviderId;
    if (providerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح المحادثة: معرف المزود غير صالح')),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatDetailScreen(
          peerName: providerName,
          peerProviderId: providerId,
        ),
      ),
    );
  }

  Future<void> _openExternalUrl(String rawUrl) async {
    final url = rawUrl.trim();
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تعذر فتح الرابط')),
    );
  }

  Future<void> _showShareAndReportSheet() async {
    final e164 = _formatPhoneE164(providerPhone);
    final fakeLink = 'https://nawafeth.app/provider/${widget.providerId ?? 'provider_demo'}';

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
                Row(
                  children: [
                    const Icon(Icons.qr_code_2, size: 22, color: Colors.black87),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'مشاركة نافذة مقدم الخدمة',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.grey.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    border: Border.all(color: mainColor.withValues(alpha: 0.25)),
                    borderRadius: BorderRadius.circular(14),
                    color: mainColor.withValues(alpha: 0.04),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.white,
                        ),
                        child: const Center(
                          child: Icon(Icons.qr_code, size: 80, color: Colors.black54),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        e164,
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                await Clipboard.setData(ClipboardData(text: fakeLink));
                                if (sheetContext.mounted) {
                                  Navigator.pop(sheetContext);
                                }
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('تم نسخ الرابط')),
                                );
                              },
                              icon: const Icon(Icons.copy, size: 18),
                              label: const Text('نسخ الرابط', style: TextStyle(fontFamily: 'Cairo')),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: fakeLink));
                                if (sheetContext.mounted) {
                                  Navigator.pop(sheetContext);
                                }
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('تمت مشاركة الرابط (وهمي)')),
                                );
                              },
                              icon: const Icon(Icons.share, size: 18),
                              label: const Text('مشاركة', style: TextStyle(fontFamily: 'Cairo')),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  onTap: () {
                    Navigator.pop(sheetContext);
                    showPlatformReportDialog(
                      context: context,
                      title: 'إبلاغ عن مزود خدمة',
                      reportedEntityLabel: 'بيانات المبلغ عنه:',
                      reportedEntityValue: '$providerName ($providerHandle)',
                      contextLabel: 'نوع البلاغ',
                      contextValue: 'مزود خدمة',
                    );
                  },
                  leading: const Icon(Icons.flag_outlined, color: Colors.red),
                  title: const Text('الإبلاغ عن مقدم الخدمة', style: TextStyle(fontFamily: 'Cairo')),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showFollowersList() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: SizedBox(
            height: 380,
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 48,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Icon(Icons.groups_rounded, color: Colors.black87),
                      const SizedBox(width: 10),
                      Text(
                        'متابعون ($_followersCount)',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    itemCount: 12,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final name = 'متابع ${index + 1}';
                      return ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person)),
                        title: Text(name, style: const TextStyle(fontFamily: 'Cairo')),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showFollowingList() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: SizedBox(
            height: 380,
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 48,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.person_add_alt_1_rounded,
                        color: Colors.black87,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'يتابع ($_followingCount)',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    itemCount: 8,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final name = 'حساب ${index + 1}';
                      return ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person)),
                        title: Text(
                          name,
                          style: const TextStyle(fontFamily: 'Cairo'),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.grey[900] : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;
    final secondaryTextColor = isDark ? Colors.grey[400] : Colors.grey;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: bgColor,
        appBar: const CustomAppBar(title: 'مزود الخدمة'),
        drawer: const CustomDrawer(),
        body: SingleChildScrollView(
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    height: 140,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                        colors: [
                          mainColor.withValues(alpha: 0.85),
                          mainColor.withValues(alpha: 0.55),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 12,
                    left: 12,
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'إضافة لقائمة المتابعة',
                          onPressed: () {
                            setState(() => _isBookmarked = !_isBookmarked);
                          },
                          icon: Icon(
                            _isBookmarked ? Icons.bookmark : Icons.bookmark_outline,
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'مشاركة/إبلاغ',
                          onPressed: _showShareAndReportSheet,
                          icon: const Icon(Icons.ios_share, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    bottom: -48,
                    right: 16,
                    child: CircleAvatar(
                      radius: 48,
                      backgroundColor: bgColor,
                      child: CircleAvatar(
                        radius: 44,
                        backgroundImage: providerImage.startsWith('http')
                            ? NetworkImage(providerImage) as ImageProvider
                            : AssetImage(providerImage),
                      ),
                    ),
                  ),
                  if (providerVerified)
                    Positioned(
                      bottom: -16,
                      right: 22,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: mainColor.withValues(alpha: 0.25), width: 1),
                        ),
                        child: Center(
                          child: Icon(Icons.check_circle, color: mainColor, size: 18),
                        ),
                      ),
                    ),
                  if (_isOnline)
                    Positioned(
                      bottom: -16,
                      right: 86,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          border: Border.all(color: bgColor ?? Colors.white, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 58),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  providerName,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: textColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (providerEnglishName.trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Directionality(
                              textDirection: TextDirection.ltr,
                              child: Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: Text(
                                  providerEnglishName,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: secondaryTextColor,
                                  ),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 2),
                          Text(
                            providerHandle,
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              color: secondaryTextColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (providerAccountType.trim().isNotEmpty) ...[
                            Row(
                              children: [
                                Icon(Icons.work_outline, size: 16, color: secondaryTextColor),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    providerAccountType,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 13,
                                      color: secondaryTextColor,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                          ],
                          Text(
                            '$providerCategory • $providerSubCategory',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                              color: secondaryTextColor,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.qr_code_2, size: 18, color: secondaryTextColor),
                              const SizedBox(width: 8),
                              Icon(
                                Icons.star,
                                size: 18,
                                color: Colors.amber.shade700,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                providerRating.toStringAsFixed(1),
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '($_reviewersCount)',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  color: secondaryTextColor,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '$providerOperations عملية',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                  color: secondaryTextColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _circleStat(
                      icon: Icons.home_repair_service_outlined,
                      value: _completedRequests,
                      onTap: () {},
                      isDark: isDark,
                    ),
                    _circleStat(
                      icon: Icons.groups_rounded,
                      value: _followersCount,
                      onTap: _showFollowersList,
                      isDark: isDark,
                    ),
                    _circleStat(
                      icon: Icons.person_add_alt_1_rounded,
                      value: _followingCount,
                      onTap: _showFollowingList,
                      isDark: isDark,
                    ),
                    _circleStat(
                      icon: Icons.thumb_up_alt_outlined,
                      value: _likesCount,
                      onTap: () {},
                      isDark: isDark,
                    ),
                  ],
                ),
              ),
              if (_highlightsVideos.isNotEmpty) ...[
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _highlightsRow(isDark: isDark),
                ),
              ],
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ServiceRequestFormScreen(
                            providerName: providerName,
                            providerId: _resolvedProviderId?.toString(),
                          ),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: mainColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'طلب خدمة',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 62,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: tabs.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 14),
                  itemBuilder: (context, index) {
                    final isSelected = _selectedTabIndex == index;
                    final bg = isSelected
                        ? mainColor.withValues(alpha: 0.14)
                        : (isDark ? Colors.grey[850]! : Colors.grey.shade100);
                    final border = isSelected
                        ? mainColor.withValues(alpha: 0.35)
                        : (isDark ? Colors.grey[750]! : Colors.grey.shade200);
                    final iconColor = isSelected ? mainColor : (isDark ? Colors.grey[300]! : Colors.grey.shade700);
                    final titleColor = isSelected ? mainColor : textColor;

                    return InkWell(
                      onTap: () => setState(() => _selectedTabIndex = index),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: 92,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: border),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(tabs[index]['icon'], size: 22, color: iconColor),
                            const SizedBox(height: 6),
                            Text(
                              tabs[index]['title'],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: titleColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildTabContent(),
              ),
              const SizedBox(height: 30),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    InkWell(
                      onTap: () => Navigator.of(context).popUntil((route) => route.isFirst),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        child: Row(
                          children: [
                            Icon(Icons.home_outlined, color: mainColor, size: 20),
                            const SizedBox(width: 8),
                            const Text(
                              'الرئيسية',
                              style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _circleActionButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: tooltip,
        child: CircleAvatar(
          radius: 24,
          backgroundColor: color.withValues(alpha: 0.1),
          child: Icon(icon, color: color, size: 22),
        ),
      ),
    );
  }

  Widget _circleStat({
    required IconData icon,
    required int value,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    final ring = isDark ? Colors.grey[750]! : Colors.grey.shade300;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$value',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 44,
            height: 44,
            child: CustomPaint(
              painter: _DashedCirclePainter(
                color: ring,
                strokeWidth: 2,
                dashLength: 5,
                gapLength: 4,
              ),
              child: Center(
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                  child: Icon(icon, color: mainColor, size: 20),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _highlightsRow({required bool isDark}) {
    final textColor = isDark ? Colors.white : Colors.black;
    final sub = isDark ? Colors.grey[400]! : Colors.grey.shade700;
    final shouldAutoScroll = _highlightsVideos.length >= 9;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'لمحات مقدم الخدمة',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: textColor,
              ),
            ),
            const Spacer(),
            Text(
              'اسحب يمين/يسار',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: sub,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (shouldAutoScroll)
          AutoScrollingReelsRow(
            videoPaths: _highlightsVideos,
            logos: _highlightsLogos,
            onTap: _openHighlights,
          )
        else
          SizedBox(
            height: 110,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _highlightsVideos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final logo = _highlightsLogos[index % _highlightsLogos.length];
                return InkWell(
                  onTap: () => _openHighlights(index),
                  borderRadius: BorderRadius.circular(999),
                  child: VideoThumbnailWidget(
                    path: _highlightsVideos[index],
                    logo: logo,
                    onTap: () => _openHighlights(index),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Future<void> _openHighlights(int initialIndex) async {
    if (_highlightsVideos.isEmpty) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoFullScreenPage(
          videoPaths: List<String>.from(_highlightsVideos),
          initialIndex: initialIndex,
          onReportContent: (index) async {
            if (!mounted) return;

            final safeIndex = index.clamp(0, _highlightsVideos.length - 1);
            final videoPath = _highlightsVideos.isEmpty ? '' : _highlightsVideos[safeIndex];

            await showPlatformReportDialog(
              context: context,
              title: 'الإبلاغ عن المحتوى',
              reportedEntityLabel: 'بيانات المبلغ عنه:',
              reportedEntityValue: '$providerName ($providerHandle)',
              contextLabel: 'اللمحة',
              contextValue: '#${safeIndex + 1} • $videoPath',
            );
          },
        ),
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_selectedTabIndex) {
      case 0:
        return _profileTab();
      case 1:
        return _servicesTab();
      case 2:
        return _galleryTab();
      case 3:
        return const ReviewsTab(embedded: true);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _miniStat({
    required IconData icon,
    required int value,
    required String label,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? Colors.grey[850]! : Colors.white;
    final border = isDark ? Colors.grey[700]! : Colors.grey.shade200;
    final text = isDark ? Colors.white : Colors.black;
    final sub = isDark ? Colors.grey[400]! : Colors.grey.shade700;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Icon(icon, color: mainColor, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$value',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: text,
                    ),
                  ),
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      color: sub,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? Colors.grey[850]! : Colors.white;
    final borderColor = isDark ? Colors.grey[700]! : Colors.grey.shade200;
    final textColor = isDark ? Colors.white : Colors.black;
    final secondaryTextColor = isDark ? Colors.grey[400] : Colors.grey[700];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _formCard(
          cardColor: cardColor,
          borderColor: borderColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'نبذة عن مقدم الخدمة',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                providerServicesDetails.isNotEmpty
                    ? providerServicesDetails
                    : 'لا يوجد وصف',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  color: secondaryTextColor,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),
        _formCard(
          cardColor: cardColor,
          borderColor: borderColor,
          child: Column(
            children: [
              _labeledField(
                label: 'التصنيف الرئيسي للخدمات المقدمة',
                value: providerCategory,
                borderColor: borderColor,
                isDark: isDark,
              ),
              const Divider(height: 18),
              _labeledField(
                label: 'التصنيف الفرعي للخدمات المقدمة',
                value: providerSubCategory,
                borderColor: borderColor,
                isDark: isDark,
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),
        _formCard(
          cardColor: cardColor,
          borderColor: borderColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'شرح تفصيلي حول خدمات مقدم الخدمة',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                providerServicesDetails,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  color: secondaryTextColor,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),
        _formCard(
          cardColor: cardColor,
          borderColor: borderColor,
          child: Column(
            children: [
              _labeledField(
                label: 'مؤهلات مقدم الخدمة',
                value: providerQualifications,
                borderColor: borderColor,
                isDark: isDark,
              ),
              const Divider(height: 18),
              _labeledField(
                label: 'سنوات الخبرة',
                value: providerExperienceYears,
                borderColor: borderColor,
                isDark: isDark,
              ),
              const Divider(height: 18),
              _labeledField(
                label: 'لغة التواصل',
                value: providerCommunicationLanguage,
                borderColor: borderColor,
                isDark: isDark,
              ),
              const Divider(height: 18),
              _labeledField(
                label: 'نطاق الخدمة الجغرافي',
                value: _geoScopeDisplayValue(),
                borderColor: borderColor,
                isDark: isDark,
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),
        _formCard(
          cardColor: cardColor,
          borderColor: borderColor,
          child: Column(
            children: [
              _labeledField(
                label: 'الموقع الالكتروني',
                value: providerWebsite,
                borderColor: borderColor,
                isDark: isDark,
                trailing: InkWell(
                  onTap: () => _openExternalUrl(providerWebsite),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Icon(Icons.open_in_new, color: mainColor, size: 18),
                  ),
                ),
              ),

              if (_serviceRangeKm > 0 && providerLat != 0 && providerLng != 0) ...[
                const SizedBox(height: 12),
                _serviceRangeMap(
                  borderColor: borderColor,
                  isDark: isDark,
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 12),
        _formCard(
          cardColor: cardColor,
          borderColor: borderColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'حسابات التواصل الاجتماعي',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 10),
              _socialAccountRow(
                icon: FontAwesomeIcons.instagram,
                label: 'حساب انستقرام',
                url: providerInstagramUrl,
                borderColor: borderColor,
                isDark: isDark,
              ),
              const SizedBox(height: 10),
              _socialAccountRow(
                icon: FontAwesomeIcons.xTwitter,
                label: 'حساب X',
                url: providerXUrl,
                borderColor: borderColor,
                isDark: isDark,
              ),
              const SizedBox(height: 10),
              _socialAccountRow(
                icon: FontAwesomeIcons.snapchat,
                label: 'حساب سناب شات',
                url: providerSnapchatUrl,
                borderColor: borderColor,
                isDark: isDark,
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _openPhoneCall,
                icon: const Icon(Icons.call, size: 18),
                label: const Text('زر اتصال', style: TextStyle(fontFamily: 'Cairo')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _openWhatsApp,
                icon: const Icon(Icons.chat, size: 18),
                label: const Text('زر واتس اب', style: TextStyle(fontFamily: 'Cairo')),
              ),
            ),
          ],
        ),

        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _openInAppChat,
            icon: const Icon(Icons.forum_outlined, size: 18),
            label: const Text(
              'محادثة داخل التطبيق',
              style: TextStyle(fontFamily: 'Cairo'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _formCard({
    required Color cardColor,
    required Color borderColor,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: child,
    );
  }

  Widget _labeledField({
    required String label,
    required String value,
    required Color borderColor,
    required bool isDark,
    Widget? trailing,
  }) {
    final textColor = isDark ? Colors.white : Colors.black;
    final secondary = isDark ? Colors.grey[400]! : Colors.grey[700]!;

    final effective = value.trim().isEmpty ? 'غير متوفر' : value.trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: secondary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                effective,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: textColor,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing,
        ],
      ],
    );
  }

  Widget _socialAccountRow({
    required IconData icon,
    required String label,
    required String url,
    required Color borderColor,
    required bool isDark,
  }) {
    final display = _extractSocialHandle(url);
    final effectiveValue = display.isNotEmpty ? display : (url.trim().isEmpty ? 'غير متوفر' : url.trim());

    final secondary = isDark ? Colors.grey[400]! : Colors.grey[700]!;
    final valueColor = isDark ? Colors.white : Colors.black;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: mainColor, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: secondary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                effectiveValue,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: valueColor,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        InkWell(
          onTap: url.trim().isEmpty ? null : () => _openExternalUrl(url),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Icon(Icons.open_in_new, color: mainColor, size: 18),
          ),
        ),
      ],
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        color: mainColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'Cairo',
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _pill(String title, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? Colors.grey[850]! : Colors.grey.shade100;
    final text = isDark ? Colors.white : Colors.black;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$title: $value',
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: text,
        ),
      ),
    );
  }

  Widget _aboutTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? Colors.grey[850] : Colors.white;
    final borderColor = isDark ? Colors.grey[700]! : Colors.grey.shade200;
    final textColor = isDark ? Colors.white : Colors.black;
    final secondaryTextColor = isDark ? Colors.grey[400] : Colors.grey[700];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'نبذة عن مقدم الخدمة',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            providerServicesDetails.isNotEmpty
                ? providerServicesDetails
                : 'لا يوجد وصف',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              color: secondaryTextColor,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _servicesTab() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _servicesData.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.84,
      ),
      itemBuilder: (context, index) {
        final service = _servicesData[index];
        return InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ServiceDetailScreen(
                  title: service["title"] ?? '',
                  images: [
                    if ((service["image"] as String?)?.isNotEmpty == true)
                      service["image"],
                  ],
                  description: service["description"] ?? '',
                  likes: service["likes"] ?? 0,
                  filesCount: service["files"] ?? 0,
                  initialCommentsCount: service["comments"] ?? 0,
                  providerId: _resolvedProviderId,
                  providerName: providerName,
                  providerHandle: providerHandle,
                  providerImage: providerImage,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: _serviceCard(
            title: service["title"],
            imagePath: service["image"],
            likes: service["likes"],
            files: service["files"],
            comments: service["comments"],
            isLiked: service['isLiked'] == true,
            onToggleLike: () {
              setState(() {
                final liked = service['isLiked'] == true;
                service['isLiked'] = !liked;
                service['likes'] = (service['likes'] as int) + (!liked ? 1 : -1);
                if ((service['likes'] as int) < 0) service['likes'] = 0;
              });
            },
          ),
        );
      },
    );
  }

  Widget _serviceCard({
    required String title,
    required String imagePath,
    required int likes,
    required int files,
    required int comments,
    required bool isLiked,
    required VoidCallback onToggleLike,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? Colors.grey[850] : Colors.white;
    final borderColor = isDark ? Colors.grey[700]! : Colors.grey.shade200;
    final textColor = isDark ? Colors.white : Colors.black;
    final iconColor = isDark ? Colors.grey[400]! : Colors.grey.shade700;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: imagePath.startsWith('http')
                  ? Image.network(
                      imagePath,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.grey.shade200,
                        child: const Center(
                          child: Icon(Icons.work_outline, size: 34, color: Colors.grey),
                        ),
                      ),
                    )
                  : imagePath.isNotEmpty
                      ? Image.asset(
                          imagePath,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          errorBuilder: (_, __, ___) => Container(
                            color: Colors.grey.shade200,
                            child: const Center(
                              child: Icon(Icons.work_outline, size: 34, color: Colors.grey),
                            ),
                          ),
                        )
                      : Container(
                          color: Colors.grey.shade200,
                          child: const Center(
                            child: Icon(Icons.work_outline, size: 34, color: Colors.grey),
                          ),
                        ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    InkWell(
                      onTap: onToggleLike,
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isLiked ? Icons.thumb_up_alt : Icons.thumb_up_alt_outlined,
                              size: 16,
                              color: isLiked ? mainColor : iconColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$likes',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 12,
                                color: isLiked ? mainColor : iconColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(Icons.photo_library_outlined, size: 16, color: iconColor),
                    const SizedBox(width: 4),
                    Text(
                      '$files',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        color: iconColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(Icons.chat_bubble_outline, size: 16, color: iconColor),
                    const SizedBox(width: 4),
                    Text(
                      '$comments',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        color: iconColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _galleryTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? Colors.grey[850]! : Colors.white;
    final borderColor = isDark ? Colors.grey[700]! : Colors.grey.shade200;
    final textColor = isDark ? Colors.white : Colors.black;
    final secondaryTextColor = isDark ? Colors.grey[400] : Colors.grey[600];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: mainColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.photo_library, color: mainColor, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'معرض خدماتي',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    Text(
                      'الأقسام التي أضافها مقدم الخدمة مع المحتوى والوصف',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        color: secondaryTextColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        for (final section in serviceGallerySections) ...[
          Row(
            children: [
              Text(
                section['title'] as String,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: textColor,
                ),
              ),
              const Spacer(),
              Text(
                '${(section['items'] as List).length} محتوى',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  color: secondaryTextColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: (section['items'] as List).length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.86,
            ),
            itemBuilder: (context, index) {
              final item = (section['items'] as List)[index] as Map<String, dynamic>;
              return _galleryMediaTile(
                item: item,
                cardColor: cardColor,
                borderColor: borderColor,
                secondaryTextColor: secondaryTextColor,
                section: section,
                indexInSection: index,
              );
            },
          ),
          const SizedBox(height: 18),
        ],
      ],
    );
  }

  Widget _galleryMediaTile({
    required Map<String, dynamic> item,
    required Color cardColor,
    required Color borderColor,
    required Color? secondaryTextColor,
    required Map<String, dynamic> section,
    required int indexInSection,
  }) {
    final type = (item['type'] ?? 'image').toString();
    final media = (item['media'] ?? '').toString();
    final desc = (item['desc'] ?? '').toString();
    final isVideo = type == 'video';

    return InkWell(
      onTap: () => _openGalleryItem(section: section, indexInSection: indexInSection),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                    child: media.startsWith('http')
                        ? Image.network(
                            media,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            errorBuilder: (_, __, ___) => Container(
                              color: Colors.grey.shade200,
                              child: const Center(
                                child: Icon(Icons.image, size: 34, color: Colors.grey),
                              ),
                            ),
                          )
                        : Image.asset(
                            media.isNotEmpty ? media : 'assets/images/8410.jpeg',
                            fit: BoxFit.cover,
                            width: double.infinity,
                            errorBuilder: (_, __, ___) => Container(
                              color: Colors.grey.shade200,
                              child: const Center(
                                child: Icon(Icons.image, size: 34, color: Colors.grey),
                              ),
                            ),
                          ),
                  ),
                  if (isVideo)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.28),
                            ],
                          ),
                        ),
                        child: const Center(
                          child: Icon(Icons.play_circle_fill, size: 46, color: Colors.white),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(isVideo ? Icons.videocam : Icons.photo, size: 14, color: mainColor),
                          const SizedBox(width: 4),
                          Text(
                            isVideo ? 'فيديو' : 'صورة',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: mainColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                desc,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  color: secondaryTextColor,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openGalleryItem({
    required Map<String, dynamic> section,
    required int indexInSection,
  }) async {
    final items = (section['items'] as List).cast<Map<String, dynamic>>();
    final tapped = items[indexInSection];
    final type = (tapped['type'] ?? 'image').toString();
    final media = (tapped['media'] ?? '').toString();

    if (type == 'video') {
      final videoPaths = items
          .where((e) => (e['type'] ?? '').toString() == 'video')
          .map((e) => (e['media'] ?? '').toString())
          .where((p) => p.isNotEmpty)
          .toList();
      final videoIndex = videoPaths.indexOf(media);

      if (videoPaths.isEmpty) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VideoFullScreenPage(
            videoPaths: videoPaths,
            initialIndex: videoIndex < 0 ? 0 : videoIndex,
          ),
        ),
      );
      return;
    }

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(16),
          child: Stack(
            children: [
              InteractiveViewer(
                child: media.startsWith('http')
                    ? Image.network(
                        media,
                        fit: BoxFit.contain,
                        width: double.infinity,
                        height: double.infinity,
                        errorBuilder: (_, __, ___) => const Center(
                          child: Icon(Icons.broken_image, color: Colors.white70, size: 42),
                        ),
                      )
                    : Image.asset(
                        media,
                        fit: BoxFit.contain,
                        width: double.infinity,
                        height: double.infinity,
                        errorBuilder: (_, __, ___) => const Center(
                          child: Icon(Icons.broken_image, color: Colors.white70, size: 42),
                        ),
                      ),
              ),
              Positioned(
                top: 6,
                left: 6,
                child: IconButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DashedCirclePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double dashLength;
  final double gapLength;

  _DashedCirclePainter({
    required this.color,
    required this.strokeWidth,
    required this.dashLength,
    required this.gapLength,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final radius = (size.shortestSide / 2) - strokeWidth;
    final center = Offset(size.width / 2, size.height / 2);
    final circumference = 2 * 3.141592653589793 * radius;
    final dashCount =
        (circumference / (dashLength + gapLength)).floor().clamp(8, 200);
    final sweep = (2 * 3.141592653589793) / dashCount;
    final dashSweep = sweep * (dashLength / (dashLength + gapLength));

    for (int i = 0; i < dashCount; i++) {
      final start = (sweep * i);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        dashSweep,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DashedCirclePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.dashLength != dashLength ||
        oldDelegate.gapLength != gapLength;
  }
}
