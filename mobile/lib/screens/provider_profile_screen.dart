import 'dart:async';

// ignore_for_file: unused_field, unused_element, unused_local_variable
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:flutter_rating_bar/flutter_rating_bar.dart';

import '../constants/app_theme.dart';
import '../widgets/auto_scrolling_reels_row.dart';
import '../widgets/platform_report_dialog.dart';
import '../widgets/video_reels.dart';
import '../services/auth_service.dart';
import '../services/analytics_service.dart';
import '../services/interactive_service.dart';
import '../services/api_client.dart';
import '../services/provider_share_tracking_service.dart';
import '../utils/value_parsing.dart';
import '../models/media_item_model.dart';
import '../models/provider_public_model.dart';
import '../widgets/excellence_badges_wrap.dart';
import '../widgets/login_required_prompt.dart';
import '../widgets/provider_name_with_badges.dart';
import '../widgets/verified_badge_view.dart';
import '../widgets/spotlight_viewer.dart';
import 'chat_detail_screen.dart';
import 'interactive_screen.dart';
import 'service_request_form_screen.dart';
import 'provider_dashboard/reviews_tab.dart';

class ProviderProfileScreen extends StatefulWidget {
  final String? providerId;
  final String? providerName;
  final String? providerCategory;
  final String? providerSubCategory;
  final double? providerRating;
  final int? providerOperations;
  final String? providerImage;
  final bool? providerVerifiedBlue;
  final bool? providerVerifiedGreen;
  final String? providerPhone;
  final double? providerLat;
  final double? providerLng;
  final bool showBackToMapButton;
  final String backButtonLabel;
  final IconData backButtonIcon;

  /// تحسين: إضافة متغيرات تحكم إضافية مستقبلية (للتوافقية)
  final bool? forceMobileLayout;
  final bool? forceTabletLayout;

  const ProviderProfileScreen({
    super.key,
    this.providerId,
    this.providerName,
    this.providerCategory,
    this.providerSubCategory,
    this.providerRating,
    this.providerOperations,
    this.providerImage,
    this.providerVerifiedBlue,
    this.providerVerifiedGreen,
    this.providerPhone,
    this.providerLat,
    this.providerLng,
    this.showBackToMapButton = false,
    this.backButtonLabel = 'العودة إلى الخريطة',
    this.backButtonIcon = Icons.map_outlined,
    this.forceMobileLayout,
    this.forceTabletLayout,
  });

  @override
  State<ProviderProfileScreen> createState() => _ProviderProfileScreenState();
}

class _ProviderProfileScreenState extends State<ProviderProfileScreen>
    with SingleTickerProviderStateMixin {
  final Color mainColor = const Color(0xFF5E35B1);
  late final AnimationController _entranceController;

  int _selectedTabIndex = 0;

  bool _isBookmarked = false;
  bool _isFollowing = false;
  bool _isFollowLoading = false;
  final bool _isOnline = true;
  bool _isLoading = true;
  bool _profileViewTracked = false;

  // ── بيانات من API ──
  ProviderPublicModel? _providerDetail;
  Map<String, dynamic>? _statsData;
  List<Map<String, dynamic>> _apiServices = [];
  List<Map<String, dynamic>> _apiPortfolio = [];
  List<MediaItemModel> _spotlightItems = [];
  int _portfolioLikes = 0;
  int _spotlightLikes = 0;
  int _portfolioSaves = 0;
  int _spotlightSaves = 0;

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
  int get _profileLikesBase =>
      _statsData?['likes_count'] as int? ?? _providerDetail?.likesCount ?? 0;
  int get _likesCount => _profileLikesBase + _portfolioLikes + _spotlightLikes;

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
        'is_liked': asBool(item['is_liked']),
        'is_saved': asBool(item['is_saved']),
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
      final seenTitles = <String>{};
      for (final section in definedSections) {
        final title = (section['title'] ?? '').toString().trim();
        if (title.isEmpty) continue;
        if (!seenTitles.add(title)) continue;
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
    final detail = _providerDetail;
    if (detail != null) {
      final direct = (detail.primaryCategoryName ?? '').trim();
      if (direct.isNotEmpty) return direct;
      final categories = _uniqueNonEmpty(
        detail.mainCategories.map((item) => item.toString().trim()),
      );
      if (categories.isNotEmpty) return _joinForDisplay(categories);
    }
    final categories = _uniqueNonEmpty(
      _apiServices.map((service) => _serviceCategoryFromService(service)),
    );
    return _joinForDisplay(categories);
  }

  String get providerSubCategory {
    final fromWidget = (widget.providerSubCategory ?? '').trim();
    if (fromWidget.isNotEmpty) return fromWidget;
    final detail = _providerDetail;
    if (detail != null) {
      final direct = (detail.primarySubcategoryName ?? '').trim();
      if (direct.isNotEmpty) {
        final selected = _selectedSubcategoryNames;
        if (selected.length <= 1) return direct;
      }
      final selected = _selectedSubcategoryNames;
      if (selected.isNotEmpty) return _joinForDisplay(selected, maxItems: 20);
    }
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

  bool get providerVerifiedBlue =>
      _providerDetail?.isVerifiedBlue ?? widget.providerVerifiedBlue ?? false;

  bool get providerVerifiedGreen {
    final fromDetail = _providerDetail?.isVerifiedGreen;
    if (fromDetail != null) return fromDetail;
    return widget.providerVerifiedGreen ?? false;
  }

  bool get providerVerified => providerVerifiedBlue || providerVerifiedGreen;

  String get providerPhone =>
      _providerDetail?.phone ?? widget.providerPhone ?? '';

  String get providerHandle =>
      _providerDetail?.username != null ? '@${_providerDetail!.username}' : '';

  String get providerEnglishName => '';

  String get providerAccountType =>
      (_providerDetail?.providerTypeLabel ?? '').trim();

  String get providerServicesDetails => _providerDetail?.bio ?? '';

  String get providerBioSummary {
    final bio = (_providerDetail?.bio ?? '').trim();
    if (bio.isNotEmpty) return bio;
    return (_providerDetail?.aboutDetails ?? '').trim();
  }

  String get providerExperienceYears {
    final years = _providerDetail?.yearsExperience;
    if (years == null || years == 0) return '';
    return '$years سنوات';
  }

  List<String> get _selectedSubcategoryNames {
    final list = _providerDetail?.selectedSubcategories ?? const [];
    return _uniqueNonEmpty(
      list.map((e) {
        if (e is Map) {
          final map = Map<String, dynamic>.from(e);
          return (map['name'] ?? map['subcategory_name'] ?? '')
              .toString()
              .trim();
        }
        return e.toString().trim();
      }),
    );
  }

  String get providerCityName => _providerDetail?.locationDisplay ?? '';
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

  String _normalizeComparableText(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
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
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _servicesData = [];
    _loadProviderData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _entranceController.forward();
      }
    });
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
      int portfolioLikes = 0;
      int portfolioSaves = 0;
      bool portfolioSavedByMe = false;
      int spotlightLikes = 0;
      int spotlightSaves = 0;
      bool spotlightSavedByMe = false;
      if (detailResp.isSuccess && detailResp.dataAsMap != null) {
        parsedDetail = ProviderPublicModel.fromJson(detailResp.dataAsMap!);
        isFollowingFromPayload =
            _readIsFollowingFromPayload(detailResp.dataAsMap);
        if (!_profileViewTracked) {
          _profileViewTracked = true;
          AnalyticsService.trackFireAndForget(
            eventName: 'provider.profile_view',
            surface: 'flutter.provider_profile',
            sourceApp: 'providers',
            objectType: 'ProviderProfile',
            objectId: providerId.toString(),
            dedupeKey: 'provider.profile_view:flutter:$providerId',
            payload: {
              'role_state': await AuthService.getRoleState(),
              'has_detail_payload': true,
            },
          );
        }
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
                'price_unit_label': e['price_unit_label'] ?? '',
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
            for (final item in _apiPortfolio) {
              portfolioLikes += _asInt(item['likes_count']);
              portfolioSaves += _asInt(item['saves_count']);
              if (asBool(item['is_saved'])) {
                portfolioSavedByMe = true;
              }
            }
          }

          // Spotlights
          if (spotlightsResp.isSuccess) {
            _spotlightItems = _parseListResponse(spotlightsResp)
                .map(_mapSpotlightItem)
                .where((item) => (item.fileUrl ?? '').trim().isNotEmpty)
                .toList();
            for (final item in _spotlightItems) {
              spotlightLikes += item.likesCount;
              spotlightSaves += item.savesCount;
              if (item.isSaved) {
                spotlightSavedByMe = true;
              }
            }
          } else {
            _spotlightItems = [];
          }

          _portfolioLikes = portfolioLikes;
          _portfolioSaves = portfolioSaves;
          _spotlightLikes = spotlightLikes;
          _spotlightSaves = spotlightSaves;
          _isBookmarked = portfolioSavedByMe || spotlightSavedByMe;

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

  MediaItemModel _mapSpotlightItem(Map<String, dynamic> item) {
    final id = _asInt(item['id']);
    final providerIdRaw = _asInt(item['provider_id']);
    final providerId =
        providerIdRaw > 0 ? providerIdRaw : (_resolvedProviderId ?? 0);
    final providerDisplayName =
        (item['provider_display_name'] ?? providerName).toString().trim();
    final providerUsername =
        (item['provider_username'] ?? '').toString().trim();
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
      isLiked: asBool(item['is_liked']),
      isSaved: asBool(item['is_saved']),
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
    final unit = _serviceUnitLabel(service);
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

  String _serviceUnitLabel(Map<String, dynamic> service) {
    final explicitLabel = (service['price_unit_label'] ?? '').toString().trim();
    if (explicitLabel.isNotEmpty) return explicitLabel;

    final raw = (service['price_unit'] ?? '').toString().trim();
    const labels = {
      'fixed': 'سعر ثابت',
      'starting_from': 'يبدأ من',
      'hour': 'بالساعة',
      'day': 'باليوم',
      'negotiable': 'قابل للتفاوض',
    };
    return labels[raw] ?? raw;
  }

  String _serviceCountLabel(int count) {
    if (count == 0) return '0 خدمة';
    if (count == 1) return 'خدمة واحدة';
    if (count == 2) return 'خدمتان';
    if (count >= 3 && count <= 10) return '$count خدمات';
    return '$count خدمة';
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
          peerPhone: providerPhone,
          peerCity: providerCityName,
          peerProviderId: providerId,
        ),
      ),
    );
  }

  Future<void> _openServiceRequest() async {
    final loggedIn = await AuthService.isLoggedIn();
    if (!loggedIn) {
      if (!mounted) return;
      await showLoginRequiredPromptDialog(
        context,
        title: 'يلزم تسجيل الدخول لإرسال طلب',
        message: 'لإرسال طلب خدمة لهذا المزود، سجّل دخولك أولاً.',
      );
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ServiceRequestFormScreen(
          providerName: providerName,
          providerId: widget.providerId,
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
      await showLoginRequiredPromptDialog(
        context,
        title: 'يلزم تسجيل الدخول للمتابعة',
        message: 'حتى تتمكن من متابعة مقدم الخدمة، سجّل دخولك أولاً.',
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

  String _buildQrImageUrl(String targetUrl) {
    return 'https://api.qrserver.com/v1/create-qr-code/?size=420x420&data=${Uri.encodeComponent(targetUrl)}';
  }

  Future<void> _showShareAndReportSheet() async {
    final providerId =
        _providerDetail?.id.toString() ?? widget.providerId ?? 'provider';
    final providerLink =
        '${ApiClient.baseUrl.replaceFirst(RegExp(r'/$'), '')}/provider/$providerId/';
    final qrImageUrl = _buildQrImageUrl(providerLink);

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
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: CachedNetworkImage(
                            imageUrl: qrImageUrl,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) {
                              return const Center(
                                child: Icon(
                                  Icons.qr_code,
                                  size: 80,
                                  color: Colors.black54,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        providerLink,
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                await Clipboard.setData(
                                    ClipboardData(text: providerLink));
                                final providerId = _resolvedProviderId;
                                if (providerId != null) {
                                  unawaited(
                                    ProviderShareTrackingService
                                        .recordProfileShare(
                                      providerId: providerId,
                                      channel: 'copy_link',
                                    ),
                                  );
                                }
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
                              onPressed: () async {
                                await SharePlus.instance.share(
                                  ShareParams(
                                    text: providerLink,
                                    subject: 'مشاركة نافذة مقدم الخدمة',
                                  ),
                                );
                                final providerId = _resolvedProviderId;
                                if (providerId != null) {
                                  unawaited(
                                    ProviderShareTrackingService
                                        .recordProfileShare(
                                      providerId: providerId,
                                      channel: 'other',
                                    ),
                                  );
                                }
                                if (sheetContext.mounted) {
                                  Navigator.pop(sheetContext);
                                }
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('تمت مشاركة الرابط'),
                                  ),
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
                      onSubmit: _submitProviderReport,
                    );
                  },
                  leading:
                      const Icon(Icons.flag_outlined, color: AppColors.error),
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
    final result = await InteractiveService.fetchProviderFollowers(
      providerId,
      scopeAll: true,
    );
    if (!mounted) return;
    final followers = result.items;
    final error = result.error;

    final entries = followers
        .map(
          (follower) => {
            'name': follower.displayName.trim().isNotEmpty
                ? follower.displayName.trim()
                : 'مستخدم',
            'username': follower.username.trim().isNotEmpty
                ? '@${follower.username.trim()}'
                : '',
            'image': _normalizeMediaUrl((follower.profileImage ?? '').trim()),
            'badge': follower.followerBadgeLabel,
            'providerId': follower.providerId,
          },
        )
        .toList(growable: false);

    await _showConnectionsSheet(
      title: 'المتابعون',
      subtitle: 'كل من يتابع مقدم الخدمة حالياً',
      count: entries.length,
      icon: Icons.groups_rounded,
      entries: entries,
      error: error,
      emptyMessage: 'لا يوجد متابعون بعد',
    );
  }

  Future<void> _submitProviderReport({
    required String reason,
    required String details,
  }) async {
    final providerId = _resolvedProviderId;
    if (providerId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر إرسال البلاغ: معرف المزود غير صالح')),
      );
      return;
    }

    final loggedIn = await AuthService.isLoggedIn();
    if (!loggedIn) {
      if (!mounted) return;
      await showLoginRequiredPromptDialog(
        context,
        title: 'يلزم تسجيل الدخول للإبلاغ',
        message: 'حتى تتمكن من إرسال بلاغ على مقدم الخدمة، سجّل دخولك أولاً.',
      );
      return;
    }

    final response = await InteractiveService.reportProviderProfile(
      providerId,
      reason: reason,
      details: details,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          response.isSuccess
              ? 'تم إرسال البلاغ إلى فريق الدعم.'
              : (response.error ?? 'تعذر إرسال البلاغ حالياً.'),
        ),
        backgroundColor:
            response.isSuccess ? AppColors.success : AppColors.error,
      ),
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

    final entries = following
        .map(
          (provider) => {
            'name': provider.displayName.trim().isNotEmpty
                ? provider.displayName.trim()
                : 'مزود خدمة',
            'username': provider.username?.trim().isNotEmpty == true
                ? '@${provider.username!.trim()}'
                : '',
            'image': _normalizeMediaUrl((provider.profileImage ?? '').trim()),
            'badge': 'مزود خدمة',
            'providerId': provider.id,
          },
        )
        .toList(growable: false);

    await _showConnectionsSheet(
      title: 'يتابعهم',
      subtitle: 'الحسابات التي يتابعها مقدم الخدمة',
      count: entries.length,
      icon: Icons.person_add_alt_1_rounded,
      entries: entries,
      error: error,
      emptyMessage: 'لا يوجد متابَعون بعد',
    );
  }

  Future<void> _showConnectionsSheet({
    required String title,
    required String subtitle,
    required int count,
    required IconData icon,
    required List<Map<String, dynamic>> entries,
    required String? error,
    required String emptyMessage,
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final resolvedCount = entries.isNotEmpty ? entries.length : count;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.82,
              minHeight: 360,
            ),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF101424) : const Color(0xFFF8FAFF),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(
                color: mainColor.withValues(alpha: isDark ? 0.26 : 0.14),
              ),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 56,
                  height: 5,
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.white : mainColor)
                        .withValues(alpha: 0.24),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              mainColor,
                              mainColor.withValues(alpha: 0.74),
                            ],
                            begin: Alignment.topRight,
                            end: Alignment.bottomLeft,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: mainColor.withValues(alpha: 0.28),
                              blurRadius: 14,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Icon(icon, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? Colors.white70
                                    : Colors.grey.shade700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : mainColor.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: mainColor.withValues(alpha: 0.16),
                                ),
                              ),
                              child: Text(
                                '$resolvedCount حساب',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: mainColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: Icon(
                          Icons.close_rounded,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: error != null && entries.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              error,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? Colors.white70
                                    : Colors.grey.shade700,
                              ),
                            ),
                          ),
                        )
                      : entries.isEmpty
                          ? Center(
                              child: Text(
                                emptyMessage,
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.grey.shade700,
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
                              itemCount: entries.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (_, index) {
                                final entry = entries[index];
                                final name = (entry['name'] ?? '').trim();
                                final username =
                                    (entry['username'] ?? '').trim();
                                final imageUrl = (entry['image'] ?? '').trim();
                                final badge = (entry['badge'] ?? '').trim();
                                final providerId = entry['providerId'] as int?;
                                final initial = name.isNotEmpty ? name[0] : 'م';

                                return Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.07)
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.14)
                                          : mainColor.withValues(alpha: 0.14),
                                    ),
                                    boxShadow: isDark
                                        ? null
                                        : [
                                            BoxShadow(
                                              color: mainColor.withValues(
                                                  alpha: 0.08),
                                              blurRadius: 14,
                                              offset: const Offset(0, 6),
                                            )
                                          ],
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 48,
                                        height: 48,
                                        padding: const EdgeInsets.all(2.5),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              mainColor.withValues(alpha: 0.9),
                                              const Color(0xFF8E66E8),
                                            ],
                                            begin: Alignment.topRight,
                                            end: Alignment.bottomLeft,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(999),
                                          child: imageUrl.isNotEmpty
                                              ? CachedNetworkImage(
                                                  imageUrl: imageUrl,
                                                  fit: BoxFit.cover,
                                                  errorWidget: (_, __, ___) =>
                                                      Container(
                                                    color: isDark
                                                        ? Colors.white
                                                            .withValues(
                                                                alpha: 0.12)
                                                        : Colors.white,
                                                    alignment: Alignment.center,
                                                    child: Text(
                                                      initial,
                                                      style: TextStyle(
                                                        fontFamily: 'Cairo',
                                                        color: mainColor,
                                                        fontWeight:
                                                            FontWeight.w900,
                                                      ),
                                                    ),
                                                  ),
                                                )
                                              : Container(
                                                  color: isDark
                                                      ? Colors.white.withValues(
                                                          alpha: 0.12)
                                                      : Colors.white,
                                                  alignment: Alignment.center,
                                                  child: Text(
                                                    initial,
                                                    style: TextStyle(
                                                      fontFamily: 'Cairo',
                                                      color: mainColor,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                    ),
                                                  ),
                                                ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontFamily: 'Cairo',
                                                fontSize: 12,
                                                fontWeight: FontWeight.w800,
                                                color: isDark
                                                    ? Colors.white
                                                    : Colors.black87,
                                              ),
                                            ),
                                            if (username.isNotEmpty) ...[
                                              const SizedBox(height: 2),
                                              TextButton(
                                                onPressed: () =>
                                                    _handleConnectionUsernameTap(
                                                  sheetContext: sheetContext,
                                                  providerId: providerId,
                                                  displayName: name,
                                                ),
                                                style: TextButton.styleFrom(
                                                  padding: EdgeInsets.zero,
                                                  minimumSize: Size.zero,
                                                  tapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                  alignment:
                                                      Alignment.centerRight,
                                                ),
                                                child: Text(
                                                  username,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontFamily: 'Cairo',
                                                    fontSize: 10.5,
                                                    fontWeight: FontWeight.w800,
                                                    color: isDark
                                                        ? const Color(
                                                            0xFFB39DFF)
                                                        : mainColor,
                                                    decoration: TextDecoration
                                                        .underline,
                                                    decorationColor: isDark
                                                        ? const Color(
                                                            0xFFB39DFF)
                                                        : mainColor,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (badge.isNotEmpty)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 5,
                                              ),
                                              decoration: BoxDecoration(
                                                color: mainColor.withValues(
                                                  alpha: 0.1,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                              ),
                                              child: Text(
                                                badge,
                                                style: TextStyle(
                                                  fontFamily: 'Cairo',
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: mainColor,
                                                ),
                                              ),
                                            ),
                                          const SizedBox(height: 8),
                                          Container(
                                            width: 34,
                                            height: 34,
                                            decoration: BoxDecoration(
                                              color: isDark
                                                  ? Colors.white.withValues(
                                                      alpha: 0.08)
                                                  : mainColor.withValues(
                                                      alpha: 0.08),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Icon(
                                              providerId != null &&
                                                      providerId > 0
                                                  ? Icons
                                                      .arrow_back_ios_new_rounded
                                                  : Icons.info_outline_rounded,
                                              size: 15,
                                              color: mainColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
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

  Future<void> _handleConnectionUsernameTap({
    required BuildContext sheetContext,
    required int? providerId,
    required String displayName,
  }) async {
    if (providerId != null && providerId > 0) {
      Navigator.pop(sheetContext);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProviderProfileScreen(providerId: '$providerId'),
        ),
      );
      return;
    }
    await _showNotProviderDialog(displayName: displayName);
  }

  Future<void> _showNotProviderDialog({required String displayName}) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 28),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF5E35B1), Color(0xFF7C4DFF)],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF5E35B1).withValues(alpha: 0.35),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                    ),
                    child: const Icon(
                      Icons.person_off_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'الحساب ليس مزود خدمة',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$displayName لا يملك ملف مزود خدمة حالياً.',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.95),
                      height: 1.55,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: mainColor,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'تم',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  if (isDark) const SizedBox(height: 2),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final height = media.size.height;
    final isTablet = (widget.forceTabletLayout ?? false) || (width >= 700 && width < 1200);
    final isMobile = (widget.forceMobileLayout ?? false) || width < 700;
    final bgColor = isDark ? const Color(0xFF0F0A1E) : const Color(0xFFF5F0FF);
    final textColor = isDark ? Colors.white : Colors.black;
    final secondaryTextColor = isDark ? Colors.grey[400] : Colors.grey;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: bgColor,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final maxW = constraints.maxWidth;
            final isWide = maxW > 900;
            // تحسين: دعم عرض جانبي على التابلت والشاشات الكبيرة
            return _isLoading
                ? _buildLoadingShell(isDark)
                : Container(
                    decoration: BoxDecoration(
                      gradient: isDark
                          ? const LinearGradient(
                              colors: [
                                Color(0xFF0F0A1E),
                                Color(0xFF120E28),
                                Color(0xFF180E32)
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            )
                          : const LinearGradient(
                              colors: [
                                Color(0xFFF2ECFF),
                                Color(0xFFF7F4FF),
                                Color(0xFFFAF8FF)
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                    ),
                    child: isWide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // قسم البروفايل الجانبي
                              Expanded(
                                flex: 2,
                                child: SingleChildScrollView(
                                  child: Column(
                                    children: [
                                      _buildEntrance(
                                        0,
                                        _buildProviderHeader(
                                          isDark,
                                          bgColor,
                                          textColor,
                                          secondaryTextColor,
                                        ),
                                      ),
                                      if (_highlightsVideos.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                                          child: _buildEntrance(1, _highlightsRow(isDark: isDark)),
                                        ),
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                                        child: _buildEntrance(2, _buildActionButtons(isDark)),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              // قسم التبويبات والمحتوى
                              Expanded(
                                flex: 3,
                                child: Column(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(top: 14),
                                      child: _buildEntrance(3, _buildTabsBar(isDark)),
                                    ),
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
                                        child: _buildEntrance(4, _buildTabContent()),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : CustomScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            slivers: [
                              SliverToBoxAdapter(
                                child: _buildEntrance(
                                  0,
                                  _buildProviderHeader(
                                    isDark,
                                    bgColor,
                                    textColor,
                                    secondaryTextColor,
                                  ),
                                ),
                              ),
                              if (_highlightsVideos.isNotEmpty)
                                SliverPadding(
                                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                                  sliver: SliverToBoxAdapter(
                                    child: _buildEntrance(1, _highlightsRow(isDark: isDark)),
                                  ),
                                ),
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                                sliver: SliverToBoxAdapter(
                                  child: _buildEntrance(2, _buildActionButtons(isDark)),
                                ),
                              ),
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 14),
                                  child: _buildEntrance(3, _buildTabsBar(isDark)),
                                ),
                              ),
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
                                sliver: SliverToBoxAdapter(
                                  child: _buildEntrance(4, _buildTabContent()),
                                ),
                              ),
                            ],
                          ),
                  );
          },
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
      coverProvider = CachedNetworkImageProvider(coverImageUrl);
    }

    ImageProvider<Object>? avatarProvider;
    if (providerImage.startsWith('http')) {
      avatarProvider = CachedNetworkImageProvider(providerImage);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Cover with avatar overlap ──
        Stack(
          clipBehavior: Clip.none,
          children: [
            // Cover
            Container(
              height: 160,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: coverProvider == null
                    ? LinearGradient(
                        colors: isDark
                            ? [
                                const Color(0xFF1A0A3E),
                                const Color(0xFF4527A0),
                              ]
                            : [
                                const Color(0xFF4527A0),
                                const Color(0xFF7E57C2),
                              ],
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                      )
                    : null,
                image: coverProvider != null
                    ? DecorationImage(image: coverProvider, fit: BoxFit.cover)
                    : null,
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: -42,
                    left: -20,
                    child: Container(
                      width: 152,
                      height: 152,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.10),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -54,
                    right: -16,
                    child: Container(
                      width: 170,
                      height: 170,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Buttons overlay
            SafeArea(
              bottom: false,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _headerIconBtn(
                      _isBookmarked ? Icons.bookmark : Icons.bookmark_outline,
                      _openFavorites,
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
            // Avatar centered, overlapping cover bottom
            Positioned(
              bottom: -46,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: bgColor, width: 3.5),
                    boxShadow: [
                      BoxShadow(
                          color: mainColor.withValues(alpha: 0.24),
                          blurRadius: 16,
                          offset: const Offset(0, 6)),
                    ],
                  ),
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 46,
                        backgroundColor: isDark
                            ? Colors.grey.shade800
                            : Colors.grey.shade200,
                        backgroundImage: avatarProvider,
                        child: avatarProvider == null
                            ? Icon(Icons.person,
                                size: 40,
                                color: isDark ? Colors.white54 : Colors.grey)
                            : null,
                      ),
                      if (providerVerified)
                        Positioned(
                          bottom: 2,
                          right: 2,
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: mainColor.withValues(alpha: 0.2),
                                  width: 1),
                            ),
                            child: Center(
                              child: VerifiedBadgeView(
                                isVerifiedBlue: providerVerifiedBlue,
                                isVerifiedGreen: providerVerifiedGreen,
                                iconSize: 18,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 54), // space for avatar overlap (46 + 8)

        // ── Excellence Badges ──
        if (_providerDetail?.hasExcellenceBadges ?? false)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: ExcellenceBadgesWrap(
              badges: _providerDetail?.excellenceBadges ?? const [],
              alignment: WrapAlignment.center,
            ),
          ),

        // ── Name ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: ProviderNameWithBadges(
            name: providerName,
            isVerifiedBlue: providerVerifiedBlue,
            isVerifiedGreen: providerVerifiedGreen,
            maxLines: 2,
            textAlign: TextAlign.center,
            badgeIconSize: 16,
            enableBadgeTap: true,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              fontFamily: 'Cairo',
              color: isDark ? Colors.white : const Color(0xFF12082E),
            ),
          ),
        ),

        // ── Handle ──
        if (providerHandle.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              providerHandle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'Cairo',
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.grey.shade400 : const Color(0xFF7860A0),
              ),
            ),
          ),

        // ── Category ──
        if (providerCategory.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 3, left: 24, right: 24),
            child: Text(
              '$providerCategory${providerSubCategory.isNotEmpty ? ' • $providerSubCategory' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'Cairo',
                color: isDark ? Colors.grey.shade500 : const Color(0xFF625C79),
              ),
            ),
          ),

        if (widget.showBackToMapButton)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: Icon(widget.backButtonIcon, size: 16),
                label: Text(
                  widget.backButtonLabel,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: mainColor,
                  side: BorderSide(color: mainColor.withValues(alpha: 0.35)),
                  backgroundColor: isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ),

        const SizedBox(height: 14),
        _buildOverviewStrip(isDark),
        const SizedBox(height: 10),
        // ── Stats Row ──
        _buildStatsRow(isDark),
        const SizedBox(height: 6),
        _buildConnectionsShortcuts(isDark),
        const SizedBox(height: 4),
      ],
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
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.07)
            : Colors.white.withValues(alpha: 0.98),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: mainColor.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          )
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _statItem('$_completedRequests', 'الطلبات المكتملة', isDark),
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
          // ── Rating with stars ──
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  providerRating.toStringAsFixed(1),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: mainColor,
                    fontFamily: 'Cairo',
                  ),
                ),
                const SizedBox(height: 3),
                RatingBarIndicator(
                  rating: providerRating,
                  itemBuilder: (_, __) =>
                      Icon(Icons.star_rounded, color: mainColor),
                  unratedColor: isDark
                      ? Colors.grey.shade700
                      : Colors.grey.shade300,
                  itemCount: 5,
                  itemSize: 12,
                  direction: Axis.horizontal,
                ),
                const SizedBox(height: 2),
                Text(
                  'التقييم',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                    fontFamily: 'Cairo',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionsShortcuts(bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: _connectionShortcutChip(
            isDark: isDark,
            label: 'المتابعون',
            count: _followersCount,
            icon: Icons.groups_rounded,
            emphasized: true,
            onTap: _showFollowersList,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _connectionShortcutChip(
            isDark: isDark,
            label: 'يتابعهم',
            count: _followingCount,
            icon: Icons.person_add_alt_1_rounded,
            onTap: _showFollowingList,
          ),
        ),
      ],
    );
  }

  Widget _connectionShortcutChip({
    required bool isDark,
    required String label,
    required int count,
    required IconData icon,
    required VoidCallback onTap,
    bool emphasized = false,
  }) {
    final background = emphasized
        ? LinearGradient(
            colors: [
              mainColor.withValues(alpha: isDark ? 0.28 : 0.16),
              mainColor.withValues(alpha: isDark ? 0.14 : 0.08),
            ],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          )
        : LinearGradient(
            colors: [
              isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.white,
              isDark
                  ? Colors.white.withValues(alpha: 0.03)
                  : const Color(0xFFF8FAFF),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          gradient: background,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: emphasized
                ? mainColor.withValues(alpha: 0.28)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : mainColor.withValues(alpha: 0.12)),
          ),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: mainColor.withValues(alpha: emphasized ? 0.12 : 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: mainColor.withValues(alpha: isDark ? 0.18 : 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: mainColor, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: mainColor,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 14,
              color: isDark ? Colors.white54 : Colors.black45,
            ),
          ],
        ),
      ),
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
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: mainColor,
                fontFamily: 'Cairo')),
        Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 10,
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.07)
            : Colors.white.withValues(alpha: 0.98),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: mainColor.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Row 1: Follow + icons ──
          Row(
            children: [
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: !_isFollowing && !_isFollowLoading
                        ? const LinearGradient(
                            colors: [Color(0xFF5E35B1), Color(0xFF7E57C2)],
                            begin: Alignment.centerRight,
                            end: Alignment.centerLeft,
                          )
                        : null,
                    boxShadow: !_isFollowing && !_isFollowLoading
                        ? [
                            BoxShadow(
                              color: const Color(0xFF5E35B1)
                                  .withValues(alpha: 0.28),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ]
                        : null,
                  ),
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: _isFollowing
                          ? mainColor.withValues(alpha: isDark ? 0.18 : 0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _isFollowing
                            ? mainColor.withValues(alpha: 0.28)
                            : (isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : mainColor.withValues(alpha: 0.18)),
                      ),
                    ),
                    child: TextButton.icon(
                      onPressed: _isFollowLoading ? null : _toggleFollow,
                      icon: _isFollowLoading
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(mainColor),
                              ),
                            )
                          : Icon(
                              _isFollowing
                                  ? Icons.person_remove_alt_1_rounded
                                  : Icons.person_add_alt_1_rounded,
                              size: 18,
                              color: _isFollowing ? mainColor : Colors.white,
                            ),
                      label: Text(
                        _isFollowing ? 'متابَع' : 'متابعة',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: _isFollowing ? mainColor : Colors.white,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: _isFollowing ? mainColor : Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _actionIconBtn(
                  Icons.chat_bubble_outline_rounded, _openInAppChat, isDark),
              const SizedBox(width: 8),
              _actionIconBtn(Icons.call_outlined, _openPhoneCall, isDark),
              const SizedBox(width: 8),
              _actionIconBtn(FontAwesomeIcons.whatsapp, _openWhatsApp, isDark),
            ],
          ),
          const SizedBox(height: 10),
          // ── Row 2: Request Service CTA ──
          SizedBox(
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [Color(0xFF60269E), Color(0xFFF1A559)],
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                ),
                boxShadow: [
                  BoxShadow(
                    color: mainColor.withValues(alpha: 0.30),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: TextButton.icon(
                onPressed: _openServiceRequest,
                icon: const Icon(Icons.send_rounded,
                    size: 18, color: Colors.white),
                label: const Text(
                  'إرسال طلب خدمة',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
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
                final logo =
                    logos.isNotEmpty ? logos[index % logos.length] : '';
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

    if (!mounted) return;
    _recomputeEngagementFromLists();
  }

  Future<void> _openFavorites() async {
    final loggedIn = await AuthService.isLoggedIn();
    if (!loggedIn) {
      if (!mounted) return;
      await showLoginRequiredPromptDialog(
        context,
        title: 'يلزم تسجيل الدخول',
        message: 'عرض قائمة المفضلة يحتاج تسجيل الدخول إلى حسابك.',
      );
      return;
    }

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const InteractiveScreen()),
    );

    if (!mounted) return;
    _recomputeEngagementFromLists();
  }

  void _recomputeEngagementFromLists() {
    int portfolioLikes = 0;
    int portfolioSaves = 0;
    bool portfolioSavedByMe = false;
    for (final item in _apiPortfolio) {
      portfolioLikes += _asInt(item['likes_count']);
      portfolioSaves += _asInt(item['saves_count']);
      if (asBool(item['is_saved'])) {
        portfolioSavedByMe = true;
      }
    }

    int spotlightLikes = 0;
    int spotlightSaves = 0;
    bool spotlightSavedByMe = false;
    for (final item in _spotlightItems) {
      spotlightLikes += item.likesCount;
      spotlightSaves += item.savesCount;
      if (item.isSaved) {
        spotlightSavedByMe = true;
      }
    }

    setState(() {
      _portfolioLikes = portfolioLikes;
      _portfolioSaves = portfolioSaves;
      _spotlightLikes = spotlightLikes;
      _spotlightSaves = spotlightSaves;
      _isBookmarked = portfolioSavedByMe || spotlightSavedByMe;
    });
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
    final secondaryTextColor = isDark ? Colors.grey[400] : Colors.grey[700];
    final hasSocialAccounts = providerInstagramUrl.isNotEmpty ||
        providerXUrl.isNotEmpty ||
        providerSnapchatUrl.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _formCard(
          cardColor: cardColor,
          borderColor: borderColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionCardTitle(
                icon: Icons.info_outline_rounded,
                title: 'نبذة عن مقدم الخدمة',
                isDark: isDark,
              ),
              const SizedBox(height: 10),
              Text(
                providerBioSummary.isNotEmpty
                    ? providerBioSummary
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
              _sectionCardTitle(
                icon: Icons.category_outlined,
                title: 'تصنيفات الخدمة',
                isDark: isDark,
              ),
              const Divider(height: 18),
              _labeledField(
                label: 'صفة الحساب',
                value: providerAccountType,
                borderColor: borderColor,
                isDark: isDark,
              ),
              const Divider(height: 18),
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
            children: [
              _sectionCardTitle(
                icon: Icons.contact_page_outlined,
                title: 'بيانات التواصل',
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
                label: 'رقم الواتساب',
                value: (_providerDetail?.whatsapp ?? '').trim(),
                borderColor: borderColor,
                isDark: isDark,
              ),
              const Divider(height: 18),
              _labeledField(
                label: 'الموقع الالكتروني',
                value: providerWebsite,
                borderColor: borderColor,
                isDark: isDark,
                trailing: InkWell(
                  onTap: providerWebsite.isNotEmpty
                      ? () => _openExternalUrl(providerWebsite)
                      : null,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Icon(Icons.open_in_new, color: mainColor, size: 18),
                  ),
                ),
              ),
              const Divider(height: 18),
              _labeledField(
                label: 'المدينة',
                value: providerCityName,
                borderColor: borderColor,
                isDark: isDark,
              ),
            ],
          ),
        ),

        // --- نطاق الخدمة على الخريطة ---
        const SizedBox(height: 12),
        _formCard(
          cardColor: cardColor,
          borderColor: borderColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionCardTitle(
                icon: Icons.map_outlined,
                title: 'نطاق الخدمة على الخريطة',
                isDark: isDark,
              ),
              const SizedBox(height: 10),
              _serviceRangeMap(borderColor: borderColor, isDark: isDark),
            ],
          ),
        ),

        if (hasSocialAccounts) ...[
          const SizedBox(height: 12),
          _formCard(
            cardColor: cardColor,
            borderColor: borderColor,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionCardTitle(
                  icon: Icons.share_outlined,
                  title: 'حسابات التواصل الاجتماعي',
                  isDark: isDark,
                ),
                const SizedBox(height: 10),
                if (providerInstagramUrl.isNotEmpty)
                  _socialAccountRow(
                    icon: FontAwesomeIcons.instagram,
                    label: 'حساب انستقرام',
                    url: providerInstagramUrl,
                    borderColor: borderColor,
                    isDark: isDark,
                  ),
                if (providerInstagramUrl.isNotEmpty &&
                    (providerXUrl.isNotEmpty || providerSnapchatUrl.isNotEmpty))
                  const SizedBox(height: 10),
                if (providerXUrl.isNotEmpty)
                  _socialAccountRow(
                    icon: FontAwesomeIcons.xTwitter,
                    label: 'حساب X',
                    url: providerXUrl,
                    borderColor: borderColor,
                    isDark: isDark,
                  ),
                if (providerXUrl.isNotEmpty && providerSnapchatUrl.isNotEmpty)
                  const SizedBox(height: 10),
                if (providerSnapchatUrl.isNotEmpty)
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
        ],
      ],
    );
  }

  Widget _sectionCardTitle({
    required IconData icon,
    required String title,
    required bool isDark,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: mainColor.withValues(alpha: isDark ? 0.22 : 0.12),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 16, color: mainColor),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : const Color(0xFF12082E),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.07)
            : Colors.white.withValues(alpha: 0.98),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: mainColor.withValues(alpha: 0.07),
            blurRadius: 16,
            offset: const Offset(0, 6),
          )
        ],
      ),
      child: child,
    );
  }

  Widget _buildLoadingShell(bool isDark) {
    final baseColor =
        isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade200;
    final highlightColor =
        isDark ? Colors.white.withValues(alpha: 0.13) : Colors.grey.shade100;

    return Container(
      decoration: BoxDecoration(
        gradient: isDark
            ? const LinearGradient(
                colors: [
                  Color(0xFF0F0A1E),
                  Color(0xFF120E28),
                  Color(0xFF180E32)
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              )
            : const LinearGradient(
                colors: [
                  Color(0xFFF2ECFF),
                  Color(0xFFF7F4FF),
                  Color(0xFFFAF8FF)
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
      ),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Cover skeleton ──
            _SkeletonBox(
              width: double.infinity,
              height: 160,
              radius: 0,
              base: baseColor,
              highlight: highlightColor,
            ),
            const SizedBox(height: 54),
            // ── Name skeleton ──
            Center(
              child: _SkeletonBox(
                width: 160,
                height: 18,
                radius: 12,
                base: baseColor,
                highlight: highlightColor,
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: _SkeletonBox(
                width: 110,
                height: 12,
                radius: 8,
                base: baseColor,
                highlight: highlightColor,
              ),
            ),
            const SizedBox(height: 18),
            // ── Overview strip skeleton ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _SkeletonBox(
                width: double.infinity,
                height: 56,
                radius: 18,
                base: baseColor,
                highlight: highlightColor,
              ),
            ),
            const SizedBox(height: 10),
            // ── Stats row skeleton ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _SkeletonBox(
                width: double.infinity,
                height: 68,
                radius: 18,
                base: baseColor,
                highlight: highlightColor,
              ),
            ),
            const SizedBox(height: 10),
            // ── Connection shortcuts skeleton ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _SkeletonBox(
                      width: double.infinity,
                      height: 60,
                      radius: 18,
                      base: baseColor,
                      highlight: highlightColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SkeletonBox(
                      width: double.infinity,
                      height: 60,
                      radius: 18,
                      base: baseColor,
                      highlight: highlightColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // ── Action buttons skeleton ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _SkeletonBox(
                width: double.infinity,
                height: 120,
                radius: 22,
                base: baseColor,
                highlight: highlightColor,
              ),
            ),
            const SizedBox(height: 14),
            // ── Tabs skeleton ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _SkeletonBox(
                width: double.infinity,
                height: 52,
                radius: 20,
                base: baseColor,
                highlight: highlightColor,
              ),
            ),
            const SizedBox(height: 16),
            // ── Content cards skeleton ──
            for (int i = 0; i < 3; i++) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _SkeletonBox(
                  width: double.infinity,
                  height: 100,
                  radius: 18,
                  base: baseColor,
                  highlight: highlightColor,
                ),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewStrip(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.07)
            : Colors.white.withValues(alpha: 0.98),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: mainColor.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _overviewItem(
              label: 'المدينة',
              value:
                  providerCityName.isNotEmpty ? providerCityName : 'غير محددة',
              isDark: isDark,
            ),
          ),
          _dividerVertical(isDark),
          Expanded(
            child: _overviewItem(
              label: 'الخبرة',
              value: providerExperienceYears.isNotEmpty
                  ? providerExperienceYears
                  : 'غير مذكورة',
              isDark: isDark,
            ),
          ),
          _dividerVertical(isDark),
          Expanded(
            child: _overviewItem(
              label: 'نطاق الخدمة',
              value: _geoScopeDisplayValue(),
              isDark: isDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _overviewItem({
    required String label,
    required String value,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 10.2,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white60 : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11,
              height: 1.4,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabsBar(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.07)
            : Colors.white.withValues(alpha: 0.98),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: mainColor.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: List.generate(tabs.length, (index) {
          final isSelected = _selectedTabIndex == index;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedTabIndex = index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  gradient: isSelected
                      ? const LinearGradient(
                          colors: [Color(0xFF5E35B1), Color(0xFF7E57C2)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color:
                                const Color(0xFF5E35B1).withValues(alpha: 0.32),
                            blurRadius: 12,
                            offset: const Offset(0, 5),
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      tabs[index]['icon'],
                      size: 17,
                      color: isSelected
                          ? Colors.white
                          : (isDark ? Colors.grey[400] : Colors.grey.shade500),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tabs[index]['title'],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 9.5,
                        height: 1.1,
                        fontWeight:
                            isSelected ? FontWeight.w900 : FontWeight.w600,
                        color: isSelected
                            ? Colors.white
                            : (isDark ? Colors.white60 : Colors.grey.shade600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_servicesData.isEmpty) {
      return _emptySectionCard(
        icon: Icons.work_outline,
        title: 'لا توجد خدمات متاحة حالياً',
        subtitle: 'لم يضف مقدم الخدمة خدمات في هذا القسم بعد.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _servicesIntroCard(isDark),
        const SizedBox(height: 12),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _servicesData.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final service = _servicesData[index];
            final title = (service["title"] ?? '').toString().trim();
            final description = (service["description"] ?? '').toString().trim();
            final serviceTitle = title.isNotEmpty ? title : 'خدمة بدون اسم';
            final categoryLabel = _serviceCategoryFromService(service);
            final subCategoryLabel = _serviceSubCategoryFromService(service);

            return _serviceCard(
              index: index + 1,
              title: serviceTitle,
              description: description,
              priceLabel: _servicePriceLabel(service),
              priceUnitLabel: _serviceUnitLabel(service),
              categoryLabel: categoryLabel,
              subCategoryLabel: subCategoryLabel,
            );
          },
        ),
      ],
    );
  }

  Widget _servicesIntroCard(bool isDark) {
    final borderColor = mainColor.withValues(alpha: isDark ? 0.22 : 0.16);
    final subtitleColor = isDark ? Colors.grey.shade400 : Colors.grey.shade700;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: isDark
              ? [
                  Colors.white.withValues(alpha: 0.04),
                  mainColor.withValues(alpha: 0.16),
                ]
              : [
                  Colors.white,
                  mainColor.withValues(alpha: 0.08),
                ],
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: mainColor.withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: mainColor.withValues(alpha: isDark ? 0.22 : 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome_rounded, size: 15, color: mainColor),
                const SizedBox(width: 6),
                Text(
                  'خدمات المزود',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: mainColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'عرض منظم وواضح للخدمات المنشورة',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'يعرض هذا القسم الخدمات مع التسعير وطبيعة التنفيذ والتصنيف بشكل احترافي وسهل القراءة.',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11,
              height: 1.7,
              color: subtitleColor,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color:
                  isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor),
            ),
            child: Text(
              _serviceCountLabel(_servicesData.length),
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
                color: mainColor,
              ),
            ),
          ),
        ],
      ),
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
    required String priceUnitLabel,
    required String categoryLabel,
    required String subCategoryLabel,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? Colors.grey[850] : Colors.white;
    final borderColor = isDark ? Colors.grey[700]! : Colors.grey.shade200;
    final titleColor = isDark ? Colors.white : Colors.black87;
    final descColor = isDark ? Colors.grey[350]! : Colors.grey.shade700;
    final hasDescription = description.isNotEmpty;
    final hasCategory = categoryLabel.isNotEmpty;
    final hasSubCategory = subCategoryLabel.isNotEmpty;
    final footnoteColor = isDark ? Colors.grey.shade500 : Colors.grey.shade600;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(18),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: mainColor.withValues(alpha: 0.05),
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
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            mainColor.withValues(alpha: isDark ? 0.35 : 0.18),
                            mainColor.withValues(alpha: isDark ? 0.20 : 0.08),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          '$index',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            color: mainColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'خدمة منشورة',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: isDark
                                  ? Colors.grey.shade500
                                  : Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
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
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                constraints: const BoxConstraints(minWidth: 106),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                decoration: BoxDecoration(
                  color: mainColor.withValues(alpha: isDark ? 0.22 : 0.10),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: mainColor.withValues(alpha: 0.18)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'التسعير',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      priceLabel,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        color: mainColor,
                        height: 1.45,
                      ),
                    ),
                  ],
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
                text: priceUnitLabel,
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
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 10),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: mainColor.withValues(alpha: isDark ? 0.18 : 0.12),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.chat_bubble_outline_rounded,
                    size: 13, color: mainColor.withValues(alpha: 0.7)),
                const SizedBox(width: 6),
                Text(
                  'للاستفسار استخدم زر المحادثة أو الاتصال أعلى الصفحة',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: footnoteColor,
                    height: 1.5,
                  ),
                ),
              ],
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
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: mainColor.withValues(alpha: isDark ? 0.22 : 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child:
                        Icon(Icons.layers_outlined, size: 15, color: mainColor),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      section['title'] as String,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: textColor,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: mainColor.withValues(alpha: isDark ? 0.18 : 0.09),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${sectionItems.length} محتوى',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: mainColor,
                      ),
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
    final isLiked = asBool(item['is_liked']);
    final isSaved = asBool(item['is_saved']);
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
                        ? CachedNetworkImage(
                            imageUrl: normalizedMedia,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            errorWidget: (_, __, ___) => Container(
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
    if (items.isEmpty) return;

    final pId = int.tryParse(widget.providerId ?? '') ?? 0;
    final pName = providerName;
    final pImage = _providerDetail?.profileImage ?? widget.providerImage;

    final mediaItems = items.map((item) {
      final fileType = (item['type'] ?? 'image').toString();
      final media = (item['media'] ?? '').toString();
      return MediaItemModel(
        id: _asInt(item['id']),
        providerId: pId,
        providerDisplayName: pName,
        providerProfileImage: pImage,
        fileType: fileType,
        fileUrl: media,
        thumbnailUrl: fileType == 'video' ? media : null,
        caption: (item['desc'] ?? '').toString(),
        likesCount: _asInt(item['likes_count']),
        savesCount: _asInt(item['saves_count']),
        isLiked: asBool(item['is_liked']),
        isSaved: asBool(item['is_saved']),
        source: MediaItemSource.portfolio,
      );
    }).toList();

    MediaItemModel.applyInteractionOverrides(mediaItems);

    final safeIndex = indexInSection.clamp(0, mediaItems.length - 1);

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SpotlightViewerPage(
          items: mediaItems,
          initialIndex: safeIndex,
        ),
      ),
    );

    if (!mounted) return;
    // Sync engagement state back to raw maps
    for (int i = 0; i < mediaItems.length && i < items.length; i++) {
      items[i]['likes_count'] = mediaItems[i].likesCount;
      items[i]['saves_count'] = mediaItems[i].savesCount;
      items[i]['is_liked'] = mediaItems[i].isLiked;
      items[i]['is_saved'] = mediaItems[i].isSaved;
    }
    _recomputeEngagementFromLists();
    setState(() {});
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared skeleton box for loading state — animated shimmer sweep
// ─────────────────────────────────────────────────────────────────────────────
class _SkeletonBox extends StatefulWidget {
  final double width;
  final double height;
  final double radius;
  final Color base;
  final Color highlight;

  const _SkeletonBox({
    required this.width,
    required this.height,
    required this.radius,
    required this.base,
    required this.highlight,
  });

  @override
  State<_SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<_SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1.5 + _anim.value * 3, 0),
              end: Alignment(-0.5 + _anim.value * 3, 0),
              colors: [
                widget.base,
                widget.highlight,
                widget.base,
              ],
            ),
          ),
        );
      },
    );
  }
}
