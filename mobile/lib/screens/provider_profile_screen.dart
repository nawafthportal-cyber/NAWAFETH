import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../widgets/auto_scrolling_reels_row.dart';
import '../widgets/platform_report_dialog.dart';
import '../widgets/video_reels.dart';
import '../widgets/video_full_screen.dart';
import '../services/auth_service.dart';
import '../services/interactive_service.dart';
import '../services/api_client.dart';
import '../models/media_item_model.dart';
import '../models/provider_public_model.dart';
import '../widgets/spotlight_viewer.dart';
import 'chat_detail_screen.dart';
import 'provider_dashboard/reviews_tab.dart';
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
  bool _isFollowing = false;
  bool _isFollowLoading = false;
  final bool _isOnline = true;
  bool _isLoading = true;

  // ── بيانات من API ──
  ProviderPublicModel? _providerDetail;
  Map<String, dynamic>? _statsData;
  List<Map<String, dynamic>> _apiServices = [];
  List<Map<String, dynamic>> _apiPortfolio = [];
  List<MediaItemModel> _spotlightItems = [];

  // لمحات مقدم الخدمة
  List<MediaItemModel> get _spotlightVideoItems {
    return _spotlightItems
        .where((item) => item.isVideo)
        .where((item) => (item.fileUrl ?? '').trim().isNotEmpty)
        .toList();
  }

  List<String> get _highlightsVideos {
    return _spotlightVideoItems
        .map((item) => _normalizeMediaUrl((item.fileUrl ?? '').trim()))
        .where((path) => path.isNotEmpty)
        .toList();
  }

  List<String> get _highlightsLogos {
    return _spotlightVideoItems
        .map((item) {
          final thumb = (item.thumbnailUrl ?? item.fileUrl ?? '').trim();
          return _normalizeMediaUrl(thumb);
        })
        .where((logo) => logo.isNotEmpty)
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
      _statsData?['likes_count'] as int? ?? _providerDetail?.likesCount ?? 0;

  int get _reviewersCount =>
      _statsData?['rating_count'] as int? ?? _providerDetail?.ratingCount ?? 0;

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
    final grouped = <String, List<Map<String, dynamic>>>{};

    for (final item in _apiPortfolio) {
      final fileType = (item['file_type'] ?? 'image').toString();
      final fileUrl = _normalizeMediaUrl((item['file_url'] ?? '').toString());
      final thumbnailUrl = _normalizeMediaUrl(
        (item['thumbnail_url'] ?? '').toString(),
      );
      final media = fileUrl.isNotEmpty ? fileUrl : thumbnailUrl;
      if (media.isEmpty) continue;

      final rawCaption = (item['caption'] ?? '').toString().trim();
      final sectionTitle = _extractPortfolioSectionTitle(rawCaption);
      final desc = _extractPortfolioItemDescription(
        rawCaption,
        sectionTitle: sectionTitle,
      );
      grouped.putIfAbsent(sectionTitle, () => <Map<String, dynamic>>[]);
      grouped[sectionTitle]!.add({
        'id': _asInt(item['id']),
        'type': fileType == 'video' ? 'video' : 'image',
        'media': media,
        'desc': desc,
        'likes_count': _asInt(item['likes_count']),
        'saves_count': _asInt(item['saves_count']),
        'is_liked': _asBool(item['is_liked']),
        'is_saved': _asBool(item['is_saved']),
      });
    }

    final rawSections = _providerDetail?.contentSections ?? const <dynamic>[];
    final definedSections = rawSections
        .whereType<Map>()
        .map((section) => Map<String, dynamic>.from(section))
        .toList();

    // Prefer explicit sections configured in provider profile content.
    if (definedSections.isNotEmpty) {
      final result = <Map<String, dynamic>>[];
      for (final section in definedSections) {
        final title = (section['title'] ?? '').toString().trim();
        if (title.isEmpty) continue;
        final sectionDesc = (section['description'] ?? '').toString().trim();
        result.add({
          'title': title,
          'section_desc': sectionDesc,
          'items': List<Map<String, dynamic>>.from(grouped[title] ?? const []),
        });
      }
      return result;
    }

    // Fallback for old providers who have portfolio items but no content_sections.
    if (grouped.isEmpty) return [];
    return grouped.entries.map((entry) {
      return <String, dynamic>{
        'title': entry.key,
        'section_desc': '',
        'items': entry.value,
      };
    }).toList();
  }

  String _extractPortfolioSectionTitle(String caption) {
    final text = caption.trim();
    if (text.isEmpty) return 'أعمالي';
    const separators = [' - ', ' — ', ' – ', ' | ', '|'];
    for (final separator in separators) {
      final splitAt = text.indexOf(separator);
      if (splitAt > 0) {
        final section = text.substring(0, splitAt).trim();
        if (section.isNotEmpty) return section;
      }
    }
    return 'أعمالي';
  }

  String _extractPortfolioItemDescription(
    String caption, {
    required String sectionTitle,
  }) {
    final text = caption.trim();
    if (text.isEmpty) return 'بدون وصف';
    if (sectionTitle.isEmpty || sectionTitle == 'أعمالي') return text;
    const separators = [' - ', ' — ', ' – ', ' | ', '|'];
    for (final separator in separators) {
      final prefix = '$sectionTitle$separator';
      if (text.startsWith(prefix)) {
        final description = text.substring(prefix.length).trim();
        if (description.isNotEmpty) return description;
      }
    }
    return text;
  }

  String get providerName =>
      _providerDetail?.displayName ?? widget.providerName ?? 'مزود خدمة';

  String get providerCategory {
    final fromWidget = (widget.providerCategory ?? '').trim();
    if (fromWidget.isNotEmpty) return fromWidget;
    final categories = _uniqueNonEmpty(
      _apiServices.map((service) => _serviceCategoryFromService(service)),
    );
    return _joinForDisplay(categories);
  }

  String get providerSubCategory {
    final fromWidget = (widget.providerSubCategory ?? '').trim();
    if (fromWidget.isNotEmpty) return fromWidget;
    final subcategories = _uniqueNonEmpty(
      _apiServices.map((service) => _serviceSubCategoryFromService(service)),
    );
    return _joinForDisplay(subcategories);
  }

  double get providerRating =>
      _providerDetail?.ratingAvg ?? widget.providerRating ?? 0.0;

  int get providerOperations =>
      _providerDetail?.completedRequests ?? widget.providerOperations ?? 0;

  String get providerImage {
    final raw = _providerDetail?.profileImage ?? widget.providerImage ?? '';
    final normalized = _normalizeMediaUrl(raw);
    if (normalized.isNotEmpty) return normalized;
    return 'assets/images/8410.jpeg';
  }

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

  String get providerQualifications {
    final list = _providerDetail?.qualifications ?? [];
    if (list.isEmpty) return '';
    return list
        .map((e) => e is Map ? (e['title'] ?? e.toString()) : e.toString())
        .where((s) => s.toString().trim().isNotEmpty)
        .join('، ');
  }

  String get providerExperienceYears {
    final years = _providerDetail?.yearsExperience;
    if (years == null || years == 0) return '';
    return '$years سنوات';
  }

  String get providerCommunicationLanguage {
    final list = _providerDetail?.languages ?? [];
    if (list.isEmpty) return '';
    return list
        .map((e) => e is Map ? (e['name'] ?? e.toString()) : e.toString())
        .where((s) => s.toString().trim().isNotEmpty)
        .join('، ');
  }

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

  int get _serviceRangeKm => (_providerDetail?.coverageRadiusKm?.toInt()) ?? 5;

  String _normalizeMediaUrl(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return '';
    if (value.startsWith('assets/')) return value;
    return ApiClient.buildMediaUrl(value) ?? value;
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return null;
  }

  String _serviceCategoryFromService(Map<String, dynamic> service) {
    final subcategory = _asMap(service['subcategory']);
    return (subcategory?['category_name'] ?? '').toString().trim();
  }

  String _serviceSubCategoryFromService(Map<String, dynamic> service) {
    final subcategory = _asMap(service['subcategory']);
    return (subcategory?['name'] ?? '').toString().trim();
  }

  List<String> _uniqueNonEmpty(Iterable<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final clean = value.trim();
      if (clean.isEmpty) continue;
      if (seen.add(clean)) {
        result.add(clean);
      }
    }
    return result;
  }

  String _joinForDisplay(List<String> values, {int maxItems = 3}) {
    if (values.isEmpty) return '';
    if (values.length <= maxItems) return values.join('، ');
    final shown = values.take(maxItems).join('، ');
    return '$shown (+${values.length - maxItems})';
  }

  String _extractSocialHandle(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return '';

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return trimmed;

    final segments =
        uri.pathSegments.where((s) => s.trim().isNotEmpty).toList();
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
            fontSize: 11,
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
                        child:
                            Icon(Icons.location_on, color: mainColor, size: 26),
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

  String get providerWebsite => _providerDetail?.website ?? '';

  /// بحث في قائمة الروابط الاجتماعية عن رابط يحتوي كلمة معينة
  String _findSocialUrl(String keyword) {
    final list = _providerDetail?.socialLinks ?? [];
    for (final item in list) {
      final url =
          (item is Map ? (item['url'] ?? item.toString()) : item.toString())
              .toString()
              .trim();
      if (url.toLowerCase().contains(keyword)) return url;
    }
    return '';
  }

  String get providerInstagramUrl => _findSocialUrl('instagram');

  String get providerXUrl {
    final x = _findSocialUrl('x.com');
    if (x.isNotEmpty) return x;
    return _findSocialUrl('twitter');
  }

  String get providerSnapchatUrl => _findSocialUrl('snapchat');

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
      bool? isFollowingFromPayload;
      if (detailResp.isSuccess && detailResp.dataAsMap != null) {
        parsedDetail = ProviderPublicModel.fromJson(detailResp.dataAsMap!);
        isFollowingFromPayload =
            _readIsFollowingFromPayload(detailResp.dataAsMap);
      }

      if (mounted) {
        setState(() {
          // Provider detail
          if (parsedDetail != null) {
            _providerDetail = parsedDetail;
          }
          if (isFollowingFromPayload != null) {
            _isFollowing = isFollowingFromPayload;
          }

          // Stats
          if (statsResp.isSuccess && statsResp.dataAsMap != null) {
            _statsData = statsResp.dataAsMap;
          }

          // Services
          if (servicesResp.isSuccess) {
            final list = _parseListResponse(servicesResp);
            _apiServices = list.map((e) {
              final dynamic rawImage = e['image'] ?? e['thumbnail_url'];
              final image =
                  _normalizeMediaUrl(rawImage is String ? rawImage : '');
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
                'subcategory': _asMap(e['subcategory']),
                'isLiked': false,
              };
            }).toList();
            _servicesData = List.from(_apiServices);
          }

          // Portfolio
          if (portfolioResp.isSuccess) {
            _apiPortfolio = _parseListResponse(portfolioResp).map((item) {
              final normalized = Map<String, dynamic>.from(item);
              normalized['file_url'] = _normalizeMediaUrl(
                (item['file_url'] ?? '').toString(),
              );
              normalized['thumbnail_url'] = _normalizeMediaUrl(
                (item['thumbnail_url'] ?? '').toString(),
              );
              return normalized;
            }).toList();
          }

          // Spotlights
          if (spotlightsResp.isSuccess) {
            _spotlightItems = _parseListResponse(spotlightsResp)
                .map(_mapSpotlightItem)
                .where((item) => (item.fileUrl ?? '').trim().isNotEmpty)
                .toList();
          } else {
            _spotlightItems = [];
          }

          _isLoading = false;
        });
      }

      final resolvedProviderId = parsedDetail?.id ?? providerId;
      if (resolvedProviderId > 0) {
        _syncFollowState(resolvedProviderId);
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

  double? _asDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    if (value is String) {
      final text = value.trim();
      if (text.isEmpty) return null;
      return double.tryParse(text);
    }
    return null;
  }

  bool _asBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final text = value.trim().toLowerCase();
      if (text == 'true' ||
          text == '1' ||
          text == 'yes' ||
          text == 'y' ||
          text == 'on') {
        return true;
      }
      if (text == 'false' ||
          text == '0' ||
          text == 'no' ||
          text == 'n' ||
          text == 'off' ||
          text.isEmpty) {
        return false;
      }
    }
    return false;
  }

  MediaItemModel _mapSpotlightItem(Map<String, dynamic> item) {
    final id = _asInt(item['id']);
    final providerIdRaw = _asInt(item['provider_id']);
    final providerId = providerIdRaw > 0 ? providerIdRaw : (_resolvedProviderId ?? 0);
    final providerDisplayName = (item['provider_display_name'] ?? providerName)
        .toString()
        .trim();
    final providerUsername = (item['provider_username'] ?? '')
        .toString()
        .trim();
    final fileTypeRaw = (item['file_type'] ?? 'image').toString().toLowerCase();
    final normalizedType = fileTypeRaw.startsWith('video') ? 'video' : 'image';
    final fileUrl = _normalizeMediaUrl((item['file_url'] ?? '').toString());
    final thumbnailUrl = _normalizeMediaUrl(
      (item['thumbnail_url'] ?? item['file_url'] ?? '').toString(),
    );
    final profileImage = _normalizeMediaUrl(
      (item['provider_profile_image'] ?? providerImage).toString(),
    );
    final createdAtRaw = (item['created_at'] ?? '').toString().trim();

    final model = MediaItemModel(
      id: id,
      providerId: providerId,
      providerDisplayName:
          providerDisplayName.isEmpty ? providerName : providerDisplayName,
      providerUsername: providerUsername.isEmpty ? null : providerUsername,
      providerProfileImage: profileImage.isEmpty ? null : profileImage,
      fileType: normalizedType,
      fileUrl: fileUrl.isEmpty ? null : fileUrl,
      thumbnailUrl: thumbnailUrl.isEmpty ? null : thumbnailUrl,
      caption: (item['caption'] ?? '').toString(),
      likesCount: _asInt(item['likes_count']),
      savesCount: _asInt(item['saves_count']),
      isLiked: _asBool(item['is_liked']),
      isSaved: _asBool(item['is_saved']),
      createdAt: createdAtRaw.isEmpty ? null : createdAtRaw,
      source: MediaItemSource.spotlight,
    );
    model.applyInteractionOverride();
    model.rememberInteractionState();
    return model;
  }

  String _formatCompactNumber(num value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    final fixed = value.toStringAsFixed(2);
    return fixed
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  String _servicePriceLabel(Map<String, dynamic> service) {
    final from = _asDouble(service['price_from']);
    final to = _asDouble(service['price_to']);
    final unit = (service['price_unit'] ?? '').toString().trim();
    final unitSuffix = unit.isEmpty ? '' : ' / $unit';

    if (from == null && to == null) {
      return 'السعر: حسب الاتفاق';
    }
    if (from != null && to != null) {
      if ((from - to).abs() < 0.0001) {
        return 'السعر: ${_formatCompactNumber(from)}$unitSuffix';
      }
      return 'السعر: ${_formatCompactNumber(from)} - ${_formatCompactNumber(to)}$unitSuffix';
    }
    final value = from ?? to!;
    return 'السعر: ${_formatCompactNumber(value)}$unitSuffix';
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
        const SnackBar(
            content: Text('تعذر فتح المحادثة: معرف المزود غير صالح')),
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

  bool? _readIsFollowingFromPayload(Map<String, dynamic>? payload) {
    if (payload == null || !payload.containsKey('is_following')) return null;
    final raw = payload['is_following'];
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    if (raw is String) {
      final v = raw.trim().toLowerCase();
      if (v == 'true' || v == '1' || v == 'yes' || v == 'y' || v == 'on') {
        return true;
      }
      if (v == 'false' || v == '0' || v == 'no' || v == 'n' || v == 'off') {
        return false;
      }
    }
    return null;
  }

  Future<void> _syncFollowState(int providerId) async {
    final loggedIn = await AuthService.isLoggedIn();
    if (!loggedIn) return;
    final result = await InteractiveService.fetchFollowing();
    if (!mounted || !result.isSuccess) return;

    final isFollowing =
        result.items.any((provider) => provider.id == providerId);
    if (_isFollowing == isFollowing) return;
    setState(() => _isFollowing = isFollowing);
  }

  Future<void> _toggleFollow() async {
    if (_isFollowLoading) return;

    final providerId = _resolvedProviderId;
    if (providerId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('تعذر تنفيذ المتابعة: معرف المزود غير صالح')),
      );
      return;
    }

    final loggedIn = await AuthService.isLoggedIn();
    if (!loggedIn) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('سجل دخولك أولًا للمتابعة')),
      );
      return;
    }

    setState(() => _isFollowLoading = true);

    final success = _isFollowing
        ? await InteractiveService.unfollowProvider(providerId)
        : await InteractiveService.followProvider(providerId);

    if (!mounted) return;
    if (!success) {
      setState(() => _isFollowLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تحديث حالة المتابعة')),
      );
      return;
    }

    setState(() {
      _isFollowLoading = false;
      _isFollowing = !_isFollowing;

      final currentFollowers = _statsData?['followers_count'] as int? ??
          _providerDetail?.followersCount ??
          0;
      final delta = _isFollowing ? 1 : -1;
      final nextFollowers = currentFollowers + delta;
      _statsData = {
        ...?_statsData,
        'followers_count': nextFollowers < 0 ? 0 : nextFollowers,
      };
    });
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
    final providerLink =
        'https://nawafeth.app/provider/${widget.providerId ?? 'provider'}';

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
                    const Icon(Icons.qr_code_2,
                        size: 22, color: Colors.black87),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'مشاركة نافذة مقدم الخدمة',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
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
                    border:
                        Border.all(color: mainColor.withValues(alpha: 0.25)),
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
                          child: Icon(Icons.qr_code,
                              size: 80, color: Colors.black54),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        e164,
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                await Clipboard.setData(
                                    ClipboardData(text: providerLink));
                                if (sheetContext.mounted) {
                                  Navigator.pop(sheetContext);
                                }
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('تم نسخ الرابط')),
                                );
                              },
                              icon: const Icon(Icons.copy, size: 18),
                              label: const Text('نسخ الرابط',
                                  style: TextStyle(fontFamily: 'Cairo')),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Clipboard.setData(
                                    ClipboardData(text: providerLink));
                                if (sheetContext.mounted) {
                                  Navigator.pop(sheetContext);
                                }
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content:
                                          Text('تم تجهيز الرابط للمشاركة')),
                                );
                              },
                              icon: const Icon(Icons.share, size: 18),
                              label: const Text('مشاركة',
                                  style: TextStyle(fontFamily: 'Cairo')),
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
                  title: const Text('الإبلاغ عن مقدم الخدمة',
                      style: TextStyle(fontFamily: 'Cairo')),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showFollowersList() async {
    final providerId = _resolvedProviderId;
    if (providerId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر جلب قائمة المتابعين')),
      );
      return;
    }
    final result = await InteractiveService.fetchProviderFollowers(providerId);
    if (!mounted) return;
    final followers = result.items;
    final error = result.error;

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
                          fontSize: 12,
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
                  child: error != null && followers.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              error,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                          ),
                        )
                      : followers.isEmpty
                          ? const Center(
                              child: Text(
                                'لا يوجد متابعون بعد',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  color: Colors.black54,
                                ),
                              ),
                            )
                          : ListView.separated(
                              itemCount: followers.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (_, index) {
                                final follower = followers[index];
                                final name =
                                    follower.displayName.trim().isNotEmpty
                                        ? follower.displayName.trim()
                                        : 'مستخدم';
                                final initial = name[0];
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor:
                                        mainColor.withValues(alpha: 0.12),
                                    child: Text(
                                      initial,
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        color: mainColor,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    name,
                                    style: const TextStyle(fontFamily: 'Cairo'),
                                  ),
                                  subtitle: Text(
                                    follower.usernameDisplay,
                                    style: const TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 11,
                                    ),
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

  Future<void> _showFollowingList() async {
    final providerId = _resolvedProviderId;
    if (providerId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر جلب قائمة المتابَعين')),
      );
      return;
    }
    final result = await InteractiveService.fetchProviderFollowing(providerId);
    if (!mounted) return;
    final following = result.items;
    final error = result.error;

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
                          fontSize: 12,
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
                  child: error != null && following.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              error,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                          ),
                        )
                      : following.isEmpty
                          ? const Center(
                              child: Text(
                                'لا يوجد متابَعون بعد',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  color: Colors.black54,
                                ),
                              ),
                            )
                          : ListView.separated(
                              itemCount: following.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (_, index) {
                                final provider = following[index];
                                final name =
                                    provider.displayName.trim().isNotEmpty
                                        ? provider.displayName.trim()
                                        : 'مزود خدمة';
                                final handle =
                                    provider.username?.trim().isNotEmpty == true
                                        ? '@${provider.username!.trim()}'
                                        : '';
                                final initial = name[0];
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor:
                                        mainColor.withValues(alpha: 0.12),
                                    child: Text(
                                      initial,
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        color: mainColor,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    name,
                                    style: const TextStyle(fontFamily: 'Cairo'),
                                  ),
                                  subtitle: handle.isEmpty
                                      ? null
                                      : Text(
                                          handle,
                                          style: const TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: 11,
                                          ),
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
    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF5F5FA);
    final textColor = isDark ? Colors.white : Colors.black;
    final secondaryTextColor = isDark ? Colors.grey[400] : Colors.grey;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: bgColor,
        body: _isLoading
            ? Center(child: CircularProgressIndicator(color: mainColor))
            : CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // ── Header ──
                  SliverToBoxAdapter(
                      child: _buildProviderHeader(
                          isDark, bgColor, textColor, secondaryTextColor)),

                  // ── Highlights ──
                  if (_highlightsVideos.isNotEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                      sliver: SliverToBoxAdapter(
                          child: _highlightsRow(isDark: isDark)),
                    ),

                  // ── Quick Action Buttons ──
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    sliver:
                        SliverToBoxAdapter(child: _buildActionButtons(isDark)),
                  ),

                  // ── Tabs ──
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: SizedBox(
                        height: 68,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: tabs.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 10),
                          itemBuilder: (context, index) {
                            final isSelected = _selectedTabIndex == index;
                            return GestureDetector(
                              onTap: () =>
                                  setState(() => _selectedTabIndex = index),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? mainColor.withValues(alpha: 0.12)
                                      : (isDark
                                          ? Colors.white.withValues(alpha: 0.06)
                                          : Colors.white),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isSelected
                                        ? mainColor.withValues(alpha: 0.35)
                                        : (isDark
                                            ? Colors.white
                                                .withValues(alpha: 0.08)
                                            : Colors.grey.shade200),
                                  ),
                                  boxShadow: isSelected
                                      ? null
                                      : (isDark
                                          ? null
                                          : [
                                              BoxShadow(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.03),
                                                  blurRadius: 6,
                                                  offset: const Offset(0, 2)),
                                            ]),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(tabs[index]['icon'],
                                        size: 18,
                                        color: isSelected
                                            ? mainColor
                                            : (isDark
                                                ? Colors.grey[300]
                                                : Colors.grey.shade600)),
                                    const SizedBox(height: 4),
                                    Text(
                                      tabs[index]['title'],
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 10.5,
                                        height: 1.1,
                                        fontWeight: FontWeight.w700,
                                        color: isSelected
                                            ? mainColor
                                            : (isDark
                                                ? Colors.white70
                                                : Colors.black87),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),

                  // ── Tab Content ──
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
                    sliver: SliverToBoxAdapter(child: _buildTabContent()),
                  ),
                ],
              ),
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  HEADER — matches client profile design
  // ═══════════════════════════════════════════════

  Widget _buildProviderHeader(
      bool isDark, Color bgColor, Color textColor, Color? secondaryTextColor) {
    ImageProvider<Object>? coverProvider;
    final coverImageUrl = _normalizeMediaUrl(_providerDetail?.coverImage);
    if (coverImageUrl.startsWith('http')) {
      coverProvider = NetworkImage(coverImageUrl);
    }

    ImageProvider<Object>? avatarProvider;
    if (providerImage.startsWith('http')) {
      avatarProvider = NetworkImage(providerImage);
    }

    return SizedBox(
      height: 340,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ── Cover ──
          Container(
            height: 150,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: coverProvider == null
                  ? LinearGradient(
                      colors: isDark
                          ? [
                              Colors.deepPurple.shade900,
                              Colors.deepPurple.shade700.withValues(alpha: 0.7)
                            ]
                          : [
                              Colors.deepPurple.shade700,
                              Colors.deepPurple.shade400
                            ],
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                    )
                  : null,
              image: coverProvider != null
                  ? DecorationImage(image: coverProvider, fit: BoxFit.cover)
                  : null,
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _headerIconBtn(
                      _isBookmarked ? Icons.bookmark : Icons.bookmark_outline,
                      () => setState(() => _isBookmarked = !_isBookmarked),
                    ),
                    const SizedBox(width: 8),
                    _headerIconBtn(Icons.ios_share, _showShareAndReportSheet),
                    const Spacer(),
                    _headerIconBtn(Icons.arrow_forward_ios_rounded,
                        () => Navigator.pop(context)),
                  ],
                ),
              ),
            ),
          ),

          // ── Centered Avatar + Info ──
          Positioned(
            top: 110,
            left: 0,
            right: 0,
            child: Column(
              children: [
                // Avatar
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: bgColor, width: 3.5),
                    boxShadow: [
                      BoxShadow(
                          color: mainColor.withValues(alpha: 0.18),
                          blurRadius: 12,
                          offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: isDark
                            ? Colors.grey.shade800
                            : Colors.grey.shade200,
                        backgroundImage: avatarProvider,
                        child: avatarProvider == null
                            ? Icon(Icons.person,
                                size: 36,
                                color: isDark ? Colors.white54 : Colors.grey)
                            : null,
                      ),
                      if (providerVerified)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: mainColor.withValues(alpha: 0.2),
                                  width: 1),
                            ),
                            child: Icon(Icons.check_circle,
                                color: mainColor, size: 16),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Name
                Text(
                  providerName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Cairo',
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                // Handle
                if (providerHandle.isNotEmpty)
                  Text(
                    providerHandle,
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'Cairo',
                      color:
                          isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                    ),
                  ),
                // Category
                if (providerCategory.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '$providerCategory${providerSubCategory.isNotEmpty ? ' • $providerSubCategory' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontFamily: 'Cairo',
                        color: isDark
                            ? Colors.grey.shade500
                            : Colors.grey.shade600,
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                // ── Stats Row ──
                _buildStatsRow(isDark),
                const SizedBox(height: 4),
                _buildConnectionsShortcuts(isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerIconBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }

  // ── Stats Row (matching client design) ──
  Widget _buildStatsRow(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2))
              ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _statItem('$_completedRequests', 'عمليات', isDark),
          _dividerVertical(isDark),
          _statItem(
            '$_followersCount',
            'متابعون',
            isDark,
            onTap: _showFollowersList,
          ),
          _dividerVertical(isDark),
          _statItem(
            '$_likesCount',
            'إعجاب',
            isDark,
          ),
          _dividerVertical(isDark),
          _statItem(
            providerRating.toStringAsFixed(1),
            'التقييم',
            isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionsShortcuts(bool isDark) {
    final textColor = isDark ? Colors.grey.shade400 : Colors.grey.shade700;
    final dividerColor =
        isDark ? Colors.white.withValues(alpha: 0.12) : Colors.grey.shade300;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TextButton(
          onPressed: _showFollowersList,
          style: TextButton.styleFrom(
            foregroundColor: mainColor,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text(
            'عرض المتابعين',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Container(
          width: 1,
          height: 14,
          color: dividerColor,
          margin: const EdgeInsets.symmetric(horizontal: 4),
        ),
        TextButton(
          onPressed: _showFollowingList,
          style: TextButton.styleFrom(
            foregroundColor: textColor,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text(
            'عرض المتابَعين',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _statItem(
    String count,
    String label,
    bool isDark, {
    VoidCallback? onTap,
  }) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(count,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: mainColor,
                fontFamily: 'Cairo')),
        Text(label,
            style: TextStyle(
                fontSize: 9.5,
                color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                fontFamily: 'Cairo')),
      ],
    );

    return Expanded(
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: content,
              ),
            ),
    );
  }

  Widget _dividerVertical(bool isDark) {
    return Container(
      width: 1,
      height: 24,
      color:
          isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade200,
    );
  }

  // ── Action Buttons Row ──
  Widget _buildActionButtons(bool isDark) {
    return Row(
      children: [
        // طلب خدمة
        Expanded(
          flex: 2,
          child: GestureDetector(
            onTap: () {
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
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: mainColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Center(
                child: Text(
                  'طلب خدمة',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _actionIconBtn(
          _isFollowing
              ? Icons.person_remove_alt_1_rounded
              : Icons.person_add_alt_1_rounded,
          _toggleFollow,
          isDark,
          isActive: _isFollowing,
          isLoading: _isFollowLoading,
        ),
        const SizedBox(width: 8),
        _actionIconBtn(
            Icons.chat_bubble_outline_rounded, _openInAppChat, isDark),
        const SizedBox(width: 8),
        _actionIconBtn(Icons.call_outlined, _openPhoneCall, isDark),
        const SizedBox(width: 8),
        _actionIconBtn(FontAwesomeIcons.whatsapp, _openWhatsApp, isDark),
      ],
    );
  }

  Widget _actionIconBtn(
    IconData icon,
    VoidCallback onTap,
    bool isDark, {
    bool isActive = false,
    bool isLoading = false,
  }) {
    final bgColor = isActive
        ? mainColor
        : (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white);
    final iconColor = isActive ? Colors.white : mainColor;

    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: isActive
              ? Border.all(color: mainColor.withValues(alpha: 0.45))
              : null,
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                      color: mainColor.withValues(alpha: isActive ? 0.2 : 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2)),
                ],
        ),
        child: isLoading
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.1,
                  color: iconColor,
                ),
              )
            : Icon(icon, size: 18, color: iconColor),
      ),
    );
  }

  Widget _highlightsRow({required bool isDark}) {
    final textColor = isDark ? Colors.white : Colors.black;
    final sub = isDark ? Colors.grey[400]! : Colors.grey.shade700;
    final spotlightItems = _spotlightVideoItems;
    final shouldAutoScroll = spotlightItems.length >= 9;
    final videoPaths = spotlightItems
        .map((item) => _normalizeMediaUrl((item.fileUrl ?? '').trim()))
        .where((path) => path.isNotEmpty)
        .toList();
    final logos = spotlightItems
        .map((item) {
          final thumb = (item.thumbnailUrl ?? item.fileUrl ?? '').trim();
          return _normalizeMediaUrl(thumb);
        })
        .where((logo) => logo.isNotEmpty)
        .toList();
    final likesCounts = spotlightItems.map((item) => item.likesCount).toList();
    final savesCounts = spotlightItems.map((item) => item.savesCount).toList();
    final likedStates = spotlightItems.map((item) => item.isLiked).toList();
    final savedStates = spotlightItems.map((item) => item.isSaved).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'لمحات مقدم الخدمة',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
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
            videoPaths: videoPaths,
            logos: logos,
            likesCounts: likesCounts,
            savesCounts: savesCounts,
            likedStates: likedStates,
            savedStates: savedStates,
            onTap: _openHighlights,
          )
        else
          SizedBox(
            height: 110,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: spotlightItems.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                if (index >= spotlightItems.length) {
                  return const SizedBox.shrink();
                }
                final item = spotlightItems[index];
                final logo = logos.isNotEmpty ? logos[index % logos.length] : '';
                final path = _normalizeMediaUrl((item.fileUrl ?? '').trim());
                return InkWell(
                  onTap: () => _openHighlights(index),
                  borderRadius: BorderRadius.circular(999),
                  child: VideoThumbnailWidget(
                    path: path,
                    logo: logo,
                    likesCount: item.likesCount,
                    savesCount: item.savesCount,
                    isLiked: item.isLiked,
                    isSaved: item.isSaved,
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
    final spotlightItems = _spotlightVideoItems;
    if (spotlightItems.isEmpty) return;
    final safeIndex = initialIndex.clamp(0, spotlightItems.length - 1);

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SpotlightViewerPage(
          items: spotlightItems,
          initialIndex: safeIndex,
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
        return ReviewsTab(
          embedded: true,
          providerId: _resolvedProviderId,
        );
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
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: text,
                    ),
                  ),
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 10,
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
                  fontSize: 12,
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
                  fontSize: 11,
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
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                providerServicesDetails,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
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
                label: 'المدينة',
                value: providerCityName,
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Icon(Icons.open_in_new, color: mainColor, size: 18),
                  ),
                ),
              ),
              if (_serviceRangeKm > 0 &&
                  providerLat != 0 &&
                  providerLng != 0) ...[
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
                  fontSize: 12,
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
                label: const Text('زر اتصال',
                    style: TextStyle(fontFamily: 'Cairo')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _openWhatsApp,
                icon: const Icon(Icons.chat, size: 18),
                label: const Text('زر واتس اب',
                    style: TextStyle(fontFamily: 'Cairo')),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2))
              ],
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
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: secondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                effective,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
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
    final effectiveValue = display.isNotEmpty
        ? display
        : (url.trim().isEmpty ? 'غير متوفر' : url.trim());

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
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: secondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                effectiveValue,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
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
          fontSize: 11,
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
              fontSize: 13,
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
              fontSize: 11,
              color: secondaryTextColor,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _servicesTab() {
    if (_servicesData.isEmpty) {
      return _emptySectionCard(
        icon: Icons.work_outline,
        title: 'لا توجد خدمات متاحة حالياً',
        subtitle: 'لم يضف مقدم الخدمة خدمات في هذا القسم بعد.',
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _servicesData.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final service = _servicesData[index];
            final title = (service["title"] ?? '').toString().trim();
            final description =
                (service["description"] ?? '').toString().trim();
            final serviceTitle = title.isNotEmpty ? title : 'خدمة بدون اسم';
            final categoryLabel = _serviceCategoryFromService(service);
            final subCategoryLabel = _serviceSubCategoryFromService(service);
            final providerId = _resolvedProviderId?.toString();

            return _serviceCard(
              index: index + 1,
              title: serviceTitle,
              description: description,
              priceLabel: _servicePriceLabel(service),
              categoryLabel: categoryLabel,
              subCategoryLabel: subCategoryLabel,
              onRequest: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ServiceRequestFormScreen(
                      providerName: providerName,
                      providerId: providerId,
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _emptySectionCard({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? Colors.grey.shade700 : Colors.grey.shade300;
    final titleColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.grey.shade400 : Colors.grey.shade700;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade900 : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: mainColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: mainColor, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: titleColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    color: subtitleColor,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _serviceCard({
    required int index,
    required String title,
    required String description,
    required String priceLabel,
    required String categoryLabel,
    required String subCategoryLabel,
    required VoidCallback onRequest,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? Colors.grey[850] : Colors.white;
    final borderColor = isDark ? Colors.grey[700]! : Colors.grey.shade200;
    final titleColor = isDark ? Colors.white : Colors.black87;
    final descColor = isDark ? Colors.grey[350]! : Colors.grey.shade700;
    final hasDescription = description.isNotEmpty;
    final hasCategory = categoryLabel.isNotEmpty;
    final hasSubCategory = subCategoryLabel.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(14),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.035),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: mainColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    '$index',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: mainColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: titleColor,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          if (hasDescription) ...[
            const SizedBox(height: 10),
            Text(
              description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11,
                color: descColor,
                height: 1.55,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _serviceInfoChip(
                icon: Icons.sell_outlined,
                text: priceLabel,
                isPrimary: true,
              ),
              if (hasCategory)
                _serviceInfoChip(
                  icon: Icons.category_outlined,
                  text: categoryLabel,
                ),
              if (hasSubCategory)
                _serviceInfoChip(
                  icon: Icons.tune_rounded,
                  text: subCategoryLabel,
                ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onRequest,
              style: ElevatedButton.styleFrom(
                backgroundColor: mainColor,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.add_circle_outline, size: 18),
              label: const Text(
                'اطلب الخدمة',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _serviceInfoChip({
    required IconData icon,
    required String text,
    bool isPrimary = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isPrimary
        ? mainColor.withValues(alpha: isDark ? 0.26 : 0.12)
        : (isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.grey.shade100);
    final borderColor = isPrimary
        ? mainColor.withValues(alpha: 0.35)
        : (isDark
            ? Colors.white.withValues(alpha: 0.14)
            : Colors.grey.shade300);
    final textColor = isPrimary
        ? (isDark ? Colors.white : mainColor)
        : (isDark ? Colors.grey.shade300 : Colors.grey.shade700);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: textColor,
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
    final sections = serviceGallerySections;

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
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    Text(
                      'المحتوى المرئي الذي أضافه مقدم الخدمة للعملاء',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
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
        if (sections.isEmpty)
          _emptySectionCard(
            icon: Icons.photo_library_outlined,
            title: 'لا توجد عناصر في معرض الأعمال',
            subtitle:
                'المعرض فارغ حالياً. عند إضافة محتوى من حساب مقدم الخدمة سيظهر هنا.',
          ),
        for (final section in sections) ...[
          ...() {
            final sectionItems = (section['items'] as List?) ?? const [];
            final sectionDesc =
                (section['section_desc'] ?? '').toString().trim();
            return [
              Row(
                children: [
                  Text(
                    section['title'] as String,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: textColor,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${sectionItems.length} محتوى',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      color: secondaryTextColor,
                    ),
                  ),
                ],
              ),
              if (sectionDesc.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  sectionDesc,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 10.5,
                    color: secondaryTextColor,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              if (sectionItems.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderColor),
                  ),
                  child: Text(
                    'لا يوجد محتوى مرئي مرفق في هذا القسم حالياً.',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 10.8,
                      color: secondaryTextColor,
                    ),
                  ),
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: sectionItems.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.86,
                  ),
                  itemBuilder: (context, index) {
                    final item = sectionItems[index] as Map<String, dynamic>;
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
            ];
          }(),
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
    final likesCount = _asInt(item['likes_count']);
    final savesCount = _asInt(item['saves_count']);
    final isLiked = _asBool(item['is_liked']);
    final isSaved = _asBool(item['is_saved']);
    final isVideo = type == 'video';
    final normalizedMedia = _normalizeMediaUrl(media);

    return InkWell(
      onTap: () =>
          _openGalleryItem(section: section, indexInSection: indexInSection),
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
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(14)),
                    child: normalizedMedia.startsWith('http')
                        ? Image.network(
                            normalizedMedia,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            errorBuilder: (_, __, ___) => Container(
                              color: Colors.grey.shade200,
                              child: const Center(
                                child: Icon(Icons.image,
                                    size: 34, color: Colors.grey),
                              ),
                            ),
                          )
                        : normalizedMedia.startsWith('assets/')
                            ? Image.asset(
                                normalizedMedia,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                errorBuilder: (_, __, ___) => Container(
                                  color: Colors.grey.shade200,
                                  child: const Center(
                                    child: Icon(Icons.image,
                                        size: 34, color: Colors.grey),
                                  ),
                                ),
                              )
                            : Container(
                                color: Colors.grey.shade200,
                                child: const Center(
                                  child: Icon(
                                      Icons.image_not_supported_outlined,
                                      size: 34,
                                      color: Colors.grey),
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
                          child: Icon(Icons.play_circle_fill,
                              size: 46, color: Colors.white),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(isVideo ? Icons.videocam : Icons.photo,
                              size: 14, color: mainColor),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    desc,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      color: secondaryTextColor,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        isLiked ? Icons.favorite : Icons.favorite_border,
                        size: 15,
                        color: isLiked ? mainColor : secondaryTextColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$likesCount',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: secondaryTextColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        isSaved ? Icons.bookmark : Icons.bookmark_border,
                        size: 15,
                        color: isSaved ? mainColor : secondaryTextColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$savesCount',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: secondaryTextColor,
                        ),
                      ),
                    ],
                  ),
                ],
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
    final media = _normalizeMediaUrl((tapped['media'] ?? '').toString());

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
                          child: Icon(Icons.broken_image,
                              color: Colors.white70, size: 42),
                        ),
                      )
                    : media.startsWith('assets/')
                        ? Image.asset(
                            media,
                            fit: BoxFit.contain,
                            width: double.infinity,
                            height: double.infinity,
                            errorBuilder: (_, __, ___) => const Center(
                              child: Icon(Icons.broken_image,
                                  color: Colors.white70, size: 42),
                            ),
                          )
                        : const Center(
                            child: Icon(Icons.broken_image,
                                color: Colors.white70, size: 42),
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
