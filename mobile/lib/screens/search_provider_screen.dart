import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/analytics_service.dart';
import '../services/api_client.dart';
import '../services/app_logger.dart';
import '../services/home_service.dart';
import '../services/providers_api_service.dart';
import '../models/category_model.dart';
import '../models/provider_public_model.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/custom_drawer.dart';
import '../widgets/excellence_badges_wrap.dart';
import '../widgets/promo_media_tile.dart';
import '../widgets/verified_badge_view.dart';
import 'provider_profile_screen.dart';

class SearchProviderScreen extends StatefulWidget {
  final int? initialCategoryId;
  final String initialQuery;
  final bool showDrawer;
  final bool showBottomNavigation;

  const SearchProviderScreen({
    super.key,
    this.initialCategoryId,
    this.initialQuery = '',
    this.showDrawer = true,
    this.showBottomNavigation = true,
  });

  @override
  State<SearchProviderScreen> createState() => _SearchProviderScreenState();
}

class _SearchProviderScreenState extends State<SearchProviderScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  // ── API data ──
  List<CategoryModel> _categories = [];
  List<ProviderPublicModel> _providers = [];
  bool _loadingCats = true;
  bool _loadingProviders = false;
  bool _initialLoad = true;
  String? _loadError;

  // ── Filters ──
  int? _selectedCatId;
  String _selectedSort = 'default';
  Position? _clientPosition;
  final Map<int, double> _distanceKmByProviderId = {};
  Set<int> _featuredProviderIds = {};
  List<Map<String, dynamic>> _searchPromoPlacements = [];
  String? _searchBannerMediaUrl;
  String _searchBannerMediaType = 'image';
  String? _searchBannerRedirectUrl;
  int? _searchBannerProviderId;
  String? _searchBannerProviderName;
  bool _searchBannerImpressionTracked = false;
  String _lastCategoryPopupKey = '';

  // ── Search results cache (5 min) ──
  static final Map<String, List<ProviderPublicModel>> _searchCache = {};
  static final Map<String, DateTime> _searchCacheTime = {};
  static const _searchCacheTtl = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    _selectedCatId = widget.initialCategoryId;
    _searchCtrl.text = widget.initialQuery.trim();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    await Future.wait([_loadCategories(), _searchProviders()]);
    if (mounted) setState(() => _initialLoad = false);
    _loadSearchPromos();
  }

  Future<void> _loadSearchPromos() async {
    try {
      final selectedCategoryName = _selectedCategoryName();
      final selectedCategoryCity = '';
      final bundle = await ProvidersApiService.fetchSearchPromoBundle(
        selectedCategoryName: selectedCategoryName,
        selectedCategoryCity: selectedCategoryCity,
      );

      final categoryBannerRes = bundle.categoryBanner;
      final searchBannerRes = bundle.searchBanner;
      final categoryPopupRes = bundle.categoryPopup;
      final searchRes = bundle.searchResults;
      final featuredRes = bundle.featuredTop5;

      final categoryBanner = _firstPromoMap(categoryBannerRes);
      final searchBanner = _firstPromoMap(searchBannerRes);
      final chosenBanner = categoryBanner ?? searchBanner;
      _applySearchBanner(chosenBanner);

      final popupPromo = _firstPromoMap(categoryPopupRes);
      final popupKey = selectedCategoryName.trim().toLowerCase();
      if (popupPromo != null && popupKey.isNotEmpty && popupKey != _lastCategoryPopupKey) {
        _lastCategoryPopupKey = popupKey;
        await _showSearchPromoPopup(popupPromo);
      }

      final searchItems = _promoMapsFromResponse(searchRes);
      final featuredItems = _promoMapsFromResponse(
        featuredRes,
        defaultSearchPosition: 'top5',
      );
      final allItems = <Map<String, dynamic>>[
        ...searchItems,
        ...featuredItems,
      ]
          .where(_matchesSearchPromoScope)
          .where((item) => _matchesSearchPromoTargeting(
                item,
                selectedCategoryName: selectedCategoryName,
              ))
          .toList();
      if (mounted) {
        final ids = <int>{};
        for (final item in allItems) {
          final pid = item['target_provider_id'];
          if (pid != null) ids.add(pid is int ? pid : int.tryParse('$pid') ?? 0);
        }
        ids.remove(0);
        setState(() {
          _featuredProviderIds = ids;
          _searchPromoPlacements = allItems;
          _providers = _applySearchPromoOrdering(_providers);
        });
      }
    } catch (error, stackTrace) {
      AppLogger.warn(
        'SearchProviderScreen._loadSearchPromos failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Map<String, dynamic>? _firstPromoMap(dynamic response) {
    final data = response?.data;
    final items = data is List
        ? data
        : (data is Map<String, dynamic> ? (data['results'] as List? ?? const []) : const []);
    if (items.isEmpty) return null;
    final first = items.first;
    if (first is! Map) return null;
    return Map<String, dynamic>.from(first);
  }

  void _applySearchBanner(Map<String, dynamic>? promo) {
    if (!mounted) return;
    if (promo == null) {
      setState(() {
        _searchBannerMediaUrl = null;
        _searchBannerMediaType = 'image';
        _searchBannerRedirectUrl = null;
        _searchBannerProviderId = null;
        _searchBannerProviderName = null;
      });
      return;
    }
    final assets = (promo['assets'] as List?) ?? [];
    if (assets.isEmpty) return;
    final asset = assets.first;
    if (asset is! Map) return;
    final url = ApiClient.buildMediaUrl((asset['file'] ?? asset['file_url']) as String?);
    if (url == null) return;
    final providerIdRaw = promo['target_provider_id'];
    setState(() {
      _searchBannerMediaUrl = url;
      _searchBannerMediaType = ((asset['file_type'] as String?) ?? 'image').trim().toLowerCase();
      _searchBannerRedirectUrl = (promo['redirect_url'] as String?)?.trim();
      _searchBannerProviderId = providerIdRaw is int ? providerIdRaw : int.tryParse('$providerIdRaw');
      _searchBannerProviderName = promo['target_provider_display_name'] as String?;
    });
    if (!_searchBannerImpressionTracked) {
      _searchBannerImpressionTracked = true;
      AnalyticsService.trackFireAndForget(
        eventName: 'promo.banner_impression',
        surface: 'flutter.search.banner',
        sourceApp: 'promo',
        objectType: 'ProviderProfile',
        objectId: (_searchBannerProviderId ?? 0).toString(),
        dedupeKey: 'promo.banner_impression:flutter.search:${_searchBannerProviderId ?? 0}',
        payload: {
          'media_type': _searchBannerMediaType,
          'redirect_url': _searchBannerRedirectUrl ?? '',
        },
      );
    }
  }

  Future<void> _showSearchPromoPopup(Map<String, dynamic> promo) async {
    final assets = (promo['assets'] as List?) ?? [];
    if (assets.isEmpty || !mounted) return;
    final asset = assets.first;
    if (asset is! Map) return;
    final mediaUrl = ApiClient.buildMediaUrl((asset['file'] ?? asset['file_url']) as String?);
    if (mediaUrl == null) return;
    final mediaType = ((asset['file_type'] as String?) ?? 'image').trim().toLowerCase();
    final title = (promo['title'] as String?) ?? '';
    final redirectUrl = (promo['redirect_url'] as String?)?.trim();
    final providerIdRaw = promo['target_provider_id'];
    final providerId = providerIdRaw is int ? providerIdRaw : int.tryParse('$providerIdRaw');
    final providerName = promo['target_provider_display_name'] as String?;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Material(
                  color: Colors.white,
                  child: InkWell(
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      await _openSearchBannerFrom(
                        redirectUrl: redirectUrl,
                        providerId: providerId,
                        providerName: providerName,
                      );
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PromoMediaTile(
                          mediaUrl: mediaUrl,
                          mediaType: mediaType,
                          height: 240,
                          borderRadius: 0,
                          autoplay: true,
                          isActive: true,
                          showVideoBadge: mediaType == 'video',
                          fallback: const SizedBox.shrink(),
                        ),
                        if (title.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              title,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'Cairo',
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: GestureDetector(
                  onTap: () => Navigator.of(ctx).pop(),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 18),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openSearchBannerFrom({
    String? redirectUrl,
    int? providerId,
    String? providerName,
  }) async {
    final redirect = (redirectUrl ?? '').trim();
    if (redirect.isNotEmpty && await _openExternalPromoUrl(redirect)) {
      return;
    }
    if (!mounted || providerId == null || providerId <= 0) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProviderProfileScreen(
          providerId: providerId.toString(),
          providerName: providerName ?? 'مقدم خدمة',
        ),
      ),
    );
  }

  String _selectedCategoryName() {
    if (_selectedCatId == null || _categories.isEmpty) return '';
    for (final category in _categories) {
      if (category.id == _selectedCatId) {
        return category.name.trim();
      }
    }
    return '';
  }

  bool _matchesSearchPromoScope(Map<String, dynamic> item) {
    final scope = (item['search_scope'] as String? ?? '').trim().toLowerCase();
    if (scope.isEmpty || scope == 'default' || scope == 'main_results') {
      return true;
    }
    if (scope == 'category_match') {
      return _selectedCatId != null;
    }
    return true;
  }

  bool _matchesSearchPromoTargeting(
    Map<String, dynamic> item, {
    required String selectedCategoryName,
  }) {
    final targetCategory =
        (item['target_category'] as String? ?? '').trim().toLowerCase();
    final categoryContext = selectedCategoryName.trim().toLowerCase();

    if (targetCategory.isNotEmpty) {
      if (categoryContext.isEmpty) return false;
      if (targetCategory != categoryContext) return false;
    }

    return true;
  }

  Future<void> _loadCategories() async {
    try {
      final cats = await HomeService.fetchCategories();
      if (mounted) {
        setState(() {
          _categories = cats;
          _loadingCats = false;
        });
      }
    } catch (error, stackTrace) {
      AppLogger.warn(
        'SearchProviderScreen._loadCategories failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) setState(() => _loadingCats = false);
    }
  }

  Future<void> _searchProviders(
      {bool requestLocationPermission = false}) async {
    if (mounted) setState(() => _loadingProviders = true);
    try {
      final q = _searchCtrl.text.trim();
      final cacheKey = '${q}_${_selectedCatId ?? ''}';

      // Check cache first
      final cachedAt = _searchCacheTime[cacheKey];
      if (cachedAt != null &&
          DateTime.now().difference(cachedAt) < _searchCacheTtl &&
          _searchCache.containsKey(cacheKey)) {
        final cached = _searchCache[cacheKey]!;
        final distanceMap = await _buildDistanceMap(
          cached,
          requestPermission:
              _selectedSort == 'nearest' ? requestLocationPermission : false,
        );
        _distanceKmByProviderId
          ..clear()
          ..addAll(distanceMap);
        final sorted = List<ProviderPublicModel>.from(cached);
        _sortProviders(sorted);
        if (mounted) {
          setState(() {
            _providers = _applySearchPromoOrdering(sorted);
            _loadError = null;
          });
        }
        if (mounted) setState(() => _loadingProviders = false);
        return;
      }
      final res = await ProvidersApiService.fetchProvidersList(
        pageSize: 30,
        query: q,
        categoryId: _selectedCatId,
      );
      if (res.isSuccess && res.data != null) {
        final list = res.data is List
            ? res.data as List
            : (res.data['results'] as List?) ?? [];
        final providers = list
            .map((e) => ProviderPublicModel.fromJson(e as Map<String, dynamic>))
            .toList();
        // Store in cache
        _searchCache[cacheKey] = List<ProviderPublicModel>.from(providers);
        _searchCacheTime[cacheKey] = DateTime.now();
        final distanceMap = await _buildDistanceMap(
          providers,
          requestPermission:
              _selectedSort == 'nearest' ? requestLocationPermission : false,
        );
        _distanceKmByProviderId
          ..clear()
          ..addAll(distanceMap);
        // Client-side sort
        _sortProviders(providers);
        if (mounted) {
          setState(() {
            _providers = _applySearchPromoOrdering(providers);
            _loadError = null;
          });
        }
      } else {
        if (mounted) {
          setState(() => _loadError = res.error ?? 'فشل تحميل البيانات');
        }
      }
    } catch (e) {
      AppLogger.warn(
        'SearchProviderScreen._searchProviders failed',
        error: e,
      );
      if (mounted) setState(() => _loadError = 'خطأ: $e');
    }
    if (mounted) setState(() => _loadingProviders = false);
  }

  void _sortProviders(List<ProviderPublicModel> list) {
    if (_selectedSort == 'rating') {
      list.sort((a, b) => b.ratingAvg.compareTo(a.ratingAvg));
      return;
    }
    if (_selectedSort == 'completed') {
      list.sort((a, b) => b.completedRequests.compareTo(a.completedRequests));
      return;
    }
    if (_selectedSort == 'followers') {
      list.sort((a, b) => b.followersCount.compareTo(a.followersCount));
      return;
    }
    if (_selectedSort == 'nearest') {
      list.sort((a, b) {
        final da = _distanceKmByProviderId[a.id] ?? double.infinity;
        final db = _distanceKmByProviderId[b.id] ?? double.infinity;
        return da.compareTo(db);
      });
    }
  }

  List<Map<String, dynamic>> _promoMapsFromResponse(
    dynamic response, {
    String defaultSearchPosition = '',
  }) {
    final data = response?.data;
    final rawItems = data is List
        ? data
        : (data is Map<String, dynamic> ? (data['results'] as List? ?? const []) : const []);
    return rawItems.whereType<Map>().map((row) {
      final mapped = Map<String, dynamic>.from(row);
      if ((mapped['search_position'] as String?)?.trim().isEmpty ?? true) {
        if (defaultSearchPosition.isNotEmpty) {
          mapped['search_position'] = defaultSearchPosition;
        }
      }
      return mapped;
    }).toList();
  }

  Future<bool> _openExternalPromoUrl(String rawUrl) async {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return false;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.isAbsolute) return false;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
    return true;
  }

  Future<void> _openSearchBanner() async {
    AnalyticsService.trackFireAndForget(
      eventName: 'promo.banner_click',
      surface: 'flutter.search.banner',
      sourceApp: 'promo',
      objectType: 'ProviderProfile',
      objectId: (_searchBannerProviderId ?? 0).toString(),
      payload: {
        'redirect_url': _searchBannerRedirectUrl ?? '',
        'provider_name': _searchBannerProviderName ?? '',
      },
    );
    final redirect = (_searchBannerRedirectUrl ?? '').trim();
    if (redirect.isNotEmpty && await _openExternalPromoUrl(redirect)) {
      return;
    }
    final providerId = _searchBannerProviderId;
    if (!mounted || providerId == null || providerId <= 0) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProviderProfileScreen(
          providerId: providerId.toString(),
          providerName: _searchBannerProviderName ?? 'مقدم خدمة',
        ),
      ),
    );
  }

  List<ProviderPublicModel> _applySearchPromoOrdering(List<ProviderPublicModel> providers) {
    final ordered = List<ProviderPublicModel>.from(providers);
    if (ordered.isEmpty) return ordered;

    final placements = List<Map<String, dynamic>>.from(_searchPromoPlacements);
    placements.sort((a, b) => _promoPositionRank(a).compareTo(_promoPositionRank(b)));

    var exactSlotsPlaced = 0;
    var top5Offset = 0;
    var top10Offset = 0;
    final handledProviderIds = <int>{};

    for (final placement in placements) {
      final pid = placement['target_provider_id'] is int
          ? placement['target_provider_id'] as int
          : int.tryParse('${placement['target_provider_id'] ?? ''}');
      if (pid == null || pid <= 0 || handledProviderIds.contains(pid)) continue;
      final currentIndex = ordered.indexWhere((provider) => provider.id == pid);
      if (currentIndex < 0) continue;

      final provider = ordered.removeAt(currentIndex);
      final position = (placement['search_position'] as String? ?? '').trim();
      int targetIndex;
      switch (position) {
        case 'first':
          targetIndex = 0;
          exactSlotsPlaced = exactSlotsPlaced < 1 ? 1 : exactSlotsPlaced;
          break;
        case 'second':
          targetIndex = 1;
          exactSlotsPlaced = exactSlotsPlaced < 2 ? 2 : exactSlotsPlaced;
          break;
        case 'top10':
          targetIndex = exactSlotsPlaced + top5Offset + top10Offset;
          top10Offset += 1;
          break;
        case 'top5':
        default:
          targetIndex = exactSlotsPlaced + top5Offset;
          top5Offset += 1;
          break;
      }
      if (targetIndex > ordered.length) targetIndex = ordered.length;
      ordered.insert(targetIndex, provider);
      handledProviderIds.add(pid);
    }

    if (handledProviderIds.isEmpty && _featuredProviderIds.isNotEmpty) {
      final featured = ordered.where((provider) => _featuredProviderIds.contains(provider.id)).toList();
      final rest = ordered.where((provider) => !_featuredProviderIds.contains(provider.id)).toList();
      return [...featured, ...rest];
    }

    return ordered;
  }

  int _promoPositionRank(Map<String, dynamic> placement) {
    final position = (placement['search_position'] as String? ?? '').trim();
    switch (position) {
      case 'first':
        return 0;
      case 'second':
        return 1;
      case 'top5':
        return 2;
      case 'top10':
        return 3;
      default:
        return 9;
    }
  }

  Future<Map<int, double>> _buildDistanceMap(
    List<ProviderPublicModel> providers, {
    required bool requestPermission,
  }) async {
    final result = <int, double>{};

    final pos =
        await _resolveClientPosition(requestPermission: requestPermission);
    if (pos == null) return result;

    for (final provider in providers) {
      final lat = provider.lat;
      final lng = provider.lng;
      if (lat == null || lng == null) continue;
      final km = Geolocator.distanceBetween(
            pos.latitude,
            pos.longitude,
            lat,
            lng,
          ) /
          1000;
      result[provider.id] = km;
    }
    return result;
  }

  Future<Position?> _resolveClientPosition(
      {required bool requestPermission}) async {
    if (_clientPosition != null) return _clientPosition;

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

    try {
      _clientPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
    } catch (error, stackTrace) {
      AppLogger.warn(
        'SearchProviderScreen._ensureClientPosition failed',
        error: error,
        stackTrace: stackTrace,
      );
      _clientPosition = null;
    }

    return _clientPosition;
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _searchProviders);
  }

  void _onCategorySelected(int? catId) {
    setState(() => _selectedCatId = catId);
    _searchProviders();
    _loadSearchPromos();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ═══════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const purple = Colors.deepPurple;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF120F18) : const Color(0xFFF7F4FB),
        drawer: widget.showDrawer ? const CustomDrawer() : null,
        bottomNavigationBar: widget.showBottomNavigation
            ? const CustomBottomNav(currentIndex: 2)
            : null,
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? const [Color(0xFF120F18), Color(0xFF1A1422)]
                  : const [Color(0xFFF8F3FD), Color(0xFFF2EEF9)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                _buildSearchHeader(isDark, purple),
                if (!_loadingCats && _categories.isNotEmpty)
                  _buildCategoryChips(isDark, purple),
                _buildSortBar(isDark, purple),
                Expanded(child: _buildResults(isDark, purple)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════
  //  SEARCH HEADER
  // ═══════════════════════════════════════

  Widget _buildSearchHeader(bool isDark, Color purple) {
    final hasActiveFilter = _selectedCatId != null || _searchCtrl.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1B1623) : Colors.white,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : const Color(0xFFE9DDF7),
          ),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: const Color(0xFF3B155D).withValues(alpha: 0.06),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildIconChrome(
                  icon: Icons.arrow_forward_ios_rounded,
                  isDark: isDark,
                  color: purple,
                  onTap: () => Navigator.pop(context),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'البحث عن مزود خدمة',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Cairo',
                      color: isDark ? Colors.white : const Color(0xFF24182F),
                    ),
                  ),
                ),
                if (widget.showDrawer)
                  Builder(
                    builder: (drawerContext) => _buildIconChrome(
                      icon: Icons.menu_rounded,
                      isDark: isDark,
                      color: purple,
                      onTap: () => Scaffold.of(drawerContext).openDrawer(),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                gradient: isDark
                    ? null
                    : const LinearGradient(
                        colors: [Color(0xFFF9F5FD), Color(0xFFF4EEFC)],
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                      ),
                color: isDark ? Colors.white.withValues(alpha: 0.05) : null,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.07)
                      : const Color(0xFFE7D8F8),
                ),
              ),
              child: TextField(
                controller: _searchCtrl,
                onChanged: _onSearchChanged,
                textAlignVertical: TextAlignVertical.center,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF24182F),
                ),
                decoration: InputDecoration(
                  hintText: 'ابحث بالاسم أو التخصص...',
                  hintStyle: TextStyle(
                    fontSize: 10.5,
                    fontFamily: 'Cairo',
                    color: isDark ? Colors.white38 : const Color(0xFF9B90AA),
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: isDark ? Colors.white38 : const Color(0xFF8B3D8F),
                  ),
                  suffixIcon: _searchCtrl.text.trim().isNotEmpty
                      ? IconButton(
                          onPressed: () {
                            _searchCtrl.clear();
                            _onSearchChanged('');
                            setState(() {});
                          },
                          icon: Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: isDark
                                ? Colors.white38
                                : const Color(0xFF8B3D8F),
                          ),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildSearchStatChip(
                    icon: Icons.manage_search_rounded,
                    label: hasActiveFilter
                        ? _activeSearchSummary()
                        : 'ابدأ بكتابة الخدمة أو اختر تصنيفًا',
                    isDark: isDark,
                  ),
                ),
                if (hasActiveFilter) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _clearSearchFilters,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF8B3D8F),
                      textStyle: const TextStyle(
                        fontSize: 10,
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    child: const Text('إعادة ضبط'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════
  //  CATEGORY CHIPS
  // ═══════════════════════════════════════

  Widget _buildCategoryChips(bool isDark, Color purple) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
      child: Container(
        height: 54,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1B1623) : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : const Color(0xFFE9DDF7),
          ),
        ),
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          itemCount: _categories.length + 1,
          itemBuilder: (_, i) {
            final isAll = i == 0;
            final selected = isAll
                ? _selectedCatId == null
                : _selectedCatId == _categories[i - 1].id;
            final label = isAll ? 'الكل' : _categories[i - 1].name;

            return GestureDetector(
              onTap: () =>
                  _onCategorySelected(isAll ? null : _categories[i - 1].id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsetsDirectional.only(end: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                decoration: BoxDecoration(
                  gradient: selected
                      ? const LinearGradient(
                          colors: [Color(0xFF8A2E8A), Color(0xFFF0823C)],
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                        )
                      : null,
                  color: selected
                      ? null
                      : (isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : const Color(0xFFF8F4FC)),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: selected
                        ? Colors.transparent
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.07)
                            : const Color(0xFFE5D7F6)),
                  ),
                ),
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'Cairo',
                      color: selected
                          ? Colors.white
                          : (isDark ? Colors.white70 : const Color(0xFF5A446F)),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ═══════════════════════════════════════
  //  SORT BAR
  // ═══════════════════════════════════════

  Widget _buildSortBar(bool isDark, Color purple) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1B1623) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : const Color(0xFFE9DDF7),
          ),
        ),
        child: Row(
          children: [
            _buildSearchStatChip(
              icon: Icons.analytics_outlined,
              label: '${_providers.length} نتيجة',
              isDark: isDark,
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => _openSortSheet(isDark, purple),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : const Color(0xFFF8F4FC),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : const Color(0xFFE5D7F6),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.tune_rounded, size: 14, color: purple),
                    const SizedBox(width: 5),
                    Text(
                      _selectedSortLabel(),
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'Cairo',
                        color: purple,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openSortSheet(bool isDark, Color purple) {
    final opts = <Map<String, String>>[
      {'key': 'default', 'label': 'الافتراضي'},
      {'key': 'nearest', 'label': 'الأقرب'},
      {'key': 'rating', 'label': 'أعلى تقييم'},
      {'key': 'completed', 'label': 'الأكثر طلبات مكتملة'},
      {'key': 'followers', 'label': 'الأكثر متابعة'},
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (_) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            top: false,
            child: Container(
              margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1B1623) : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(30)).copyWith(
                  bottomLeft: const Radius.circular(28),
                  bottomRight: const Radius.circular(28),
                ),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : const Color(0xFFE9DDF7),
                ),
                boxShadow: isDark
                    ? null
                    : [
                        BoxShadow(
                          color: const Color(0xFF3B155D).withValues(alpha: 0.09),
                          blurRadius: 30,
                          offset: const Offset(0, -8),
                        ),
                      ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.14)
                            : const Color(0xFFD8C7EE),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF8A2E8A), Color(0xFFF0823C)],
                            begin: Alignment.topRight,
                            end: Alignment.bottomLeft,
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.tune_rounded,
                          color: Colors.white,
                          size: 17,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'ترتيب النتائج',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            fontFamily: 'Cairo',
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF24182F),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ...opts.map((o) {
                    final sel = _selectedSort == o['key'];
                    return _buildSortOptionTile(
                      isDark: isDark,
                      purple: purple,
                      selected: sel,
                      label: o['label']!,
                      onTap: () {
                        setState(() => _selectedSort = o['key']!);
                        _searchProviders(
                          requestLocationPermission: o['key'] == 'nearest',
                        );
                        Navigator.pop(context);
                      },
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _selectedSortLabel() {
    switch (_selectedSort) {
      case 'nearest':
        return 'الأقرب';
      case 'rating':
        return 'أعلى تقييم';
      case 'completed':
        return 'الأكثر تنفيذًا';
      case 'followers':
        return 'الأكثر متابعة';
      default:
        return 'الفرز';
    }
  }

  String _activeSearchSummary() {
    final parts = <String>[];
    final query = _searchCtrl.text.trim();
    final category = _selectedCategoryName();
    if (query.isNotEmpty) {
      parts.add('بحث: $query');
    }
    if (category.isNotEmpty) {
      parts.add('تصنيف: $category');
    }
    return parts.isEmpty ? 'بدون فلاتر نشطة' : parts.join(' • ');
  }

  void _clearSearchFilters() {
    setState(() {
      _selectedCatId = null;
      _selectedSort = 'default';
      _searchCtrl.clear();
    });
    _searchProviders();
    _loadSearchPromos();
  }

  Widget _buildIconChrome({
    required IconData icon,
    required bool isDark,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : const Color(0xFFF7F1FC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : const Color(0xFFE9DDF7),
            ),
          ),
          child: Icon(icon, size: 16, color: isDark ? Colors.white70 : color),
        ),
      ),
    );
  }

  Widget _buildSearchStatChip({
    required IconData icon,
    required String label,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : const Color(0xFFF8F4FC),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: isDark ? Colors.white54 : const Color(0xFF8B3D8F),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                fontFamily: 'Cairo',
                color: isDark ? Colors.white70 : const Color(0xFF6A577B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSortOptionTile({
    required bool isDark,
    required Color purple,
    required bool selected,
    required String label,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              gradient: selected && !isDark
                  ? const LinearGradient(
                      colors: [Color(0xFFF9F3FD), Color(0xFFFFF3EA)],
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                    )
                  : null,
              color: selected
                  ? (isDark
                      ? Colors.white.withValues(alpha: 0.07)
                      : null)
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : const Color(0xFFFAF7FD)),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected
                    ? const Color(0xFFE6B273)
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : const Color(0xFFE9DDF7)),
              ),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: selected
                        ? purple
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.white),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: selected
                          ? Colors.transparent
                          : (isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : const Color(0xFFD9C9EC)),
                    ),
                  ),
                  child: Icon(
                    selected
                        ? Icons.check_rounded
                        : Icons.circle_outlined,
                    size: 12,
                    color: selected
                        ? Colors.white
                        : (isDark ? Colors.white38 : const Color(0xFF9C8BAC)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'Cairo',
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                      color: isDark ? Colors.white70 : const Color(0xFF342344),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════
  //  RESULTS
  // ═══════════════════════════════════════

  Widget _buildResults(bool isDark, Color purple) {
    if (_initialLoad || _loadingProviders) {
      return const Center(
        child: CircularProgressIndicator(
          color: Colors.deepPurple,
          strokeWidth: 2,
        ),
      );
    }
    if (_providers.isEmpty) {
      return Center(
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1B1623) : Colors.white,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : const Color(0xFFE9DDF7),
            ),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: const Color(0xFF3B155D).withValues(alpha: 0.06),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF8E8FF), Color(0xFFFFF1E7)],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  _loadError != null
                      ? Icons.cloud_off_rounded
                      : Icons.search_off_rounded,
                  size: 28,
                  color: purple,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _loadError != null ? 'تعذر تحميل النتائج' : 'لا توجد نتائج حالياً',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'Cairo',
                  color: isDark ? Colors.white : const Color(0xFF24182F),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _loadError ??
                    'جرّب تعديل كلمة البحث أو تغيير التصنيف حتى تظهر لك نتائج أقرب.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.7,
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white54 : const Color(0xFF7A6B8B),
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  if (_loadError != null)
                    ElevatedButton.icon(
                      onPressed: _searchProviders,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: purple,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 10,
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      icon: const Icon(Icons.refresh_rounded, size: 15),
                      label: const Text('إعادة المحاولة'),
                    ),
                  OutlinedButton.icon(
                    onPressed: _clearSearchFilters,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: purple,
                      side: BorderSide(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.09)
                            : const Color(0xFFD9C9EC),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 10,
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    icon: const Icon(Icons.filter_alt_off_rounded, size: 15),
                    label: const Text('تصفير الفلاتر'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 18),
      itemCount: _providers.length + (_searchBannerMediaUrl != null ? 1 : 0),
      itemBuilder: (_, i) {
        if (_searchBannerMediaUrl != null && i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GestureDetector(
              onTap: _openSearchBanner,
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1B1623) : Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : const Color(0xFFE9DDF7),
                  ),
                ),
                padding: const EdgeInsets.all(10),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: PromoMediaTile(
                        mediaUrl: _searchBannerMediaUrl,
                        mediaType:
                            _searchBannerMediaType == 'video' ? 'video' : 'image',
                        height: 130,
                        borderRadius: 18,
                        autoplay: true,
                        isActive: true,
                        showVideoBadge: _searchBannerMediaType == 'video',
                        fallback: const SizedBox.shrink(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _buildPromoTag('إعلان مميز'),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _searchBannerProviderName?.trim().isNotEmpty == true
                                ? _searchBannerProviderName!.trim()
                                : 'مساحة دعائية نشطة',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'Cairo',
                              color:
                                  isDark ? Colors.white : const Color(0xFF24182F),
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
        final idx = _searchBannerMediaUrl != null ? i - 1 : i;
        return _providerCard(_providers[idx], isDark, purple);
      },
    );
  }

  Widget _providerCard(ProviderPublicModel p, bool isDark, Color purple) {
    final profileUrl = ApiClient.buildMediaUrl(p.profileImage);
    final coverUrl = ApiClient.buildMediaUrl(p.coverImage);
    final distanceKm = _distanceKmByProviderId[p.id];

    return GestureDetector(
      onTap: () {
        AnalyticsService.trackFireAndForget(
          eventName: 'search.result_click',
          surface: 'flutter.search.results',
          sourceApp: 'providers',
          objectType: 'ProviderProfile',
          objectId: p.id.toString(),
          payload: {
            'query': _searchCtrl.text.trim(),
            'selected_category_id': _selectedCatId,
            'featured': _featuredProviderIds.contains(p.id),
          },
        );
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProviderProfileScreen(
              providerId: p.id.toString(),
              providerName: p.displayName,
              providerImage: profileUrl,
              providerRating: p.ratingAvg,
              providerVerifiedBlue: p.isVerifiedBlue,
              providerVerifiedGreen: p.isVerifiedGreen,
              providerPhone: p.phone,
              providerLat: p.lat,
              providerLng: p.lng,
              providerOperations: p.completedRequests,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1B1623) : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: _featuredProviderIds.contains(p.id)
                ? const Color(0xFFF1A559)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : const Color(0xFFE9DDF7)),
            width: _featuredProviderIds.contains(p.id) ? 1.5 : 1,
          ),
          boxShadow: _featuredProviderIds.contains(p.id)
              ? [
                  BoxShadow(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.16),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ]
              : [
                  if (!isDark)
                    BoxShadow(
                      color: const Color(0xFF3B155D).withValues(alpha: 0.05),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius:
                  const BorderRadius.horizontal(right: Radius.circular(16)),
              child: SizedBox(
                width: 92,
                height: 118,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    coverUrl != null
                        ? CachedNetworkImage(imageUrl: coverUrl,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => _gradientBox(purple))
                        : _gradientBox(purple),
                    // Gradient overlay
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.black.withValues(alpha: 0.42),
                            Colors.transparent,
                          ],
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                        ),
                      ),
                    ),
                    Center(
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: Colors.white,
                            child: CircleAvatar(
                              radius: 18,
                              backgroundColor: purple.withValues(alpha: 0.1),
                              backgroundImage: profileUrl != null
                                  ? CachedNetworkImageProvider(profileUrl)
                                  : null,
                              child: profileUrl == null
                                  ? Text(
                                      p.displayName.isNotEmpty
                                          ? p.displayName[0]
                                          : '؟',
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: purple))
                                  : null,
                            ),
                          ),
                          if (p.hasExcellenceBadges)
                            Positioned(
                              top: -8,
                              left: -6,
                              child: Container(
                                constraints: const BoxConstraints(maxWidth: 84),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black87,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  p.excellenceBadges.first.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    color: Colors.white,
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w700,
                                    height: 1.1,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (p.isVerified)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: VerifiedBadgeView(
                          isVerifiedBlue: p.isVerifiedBlue,
                          isVerifiedGreen: p.isVerifiedGreen,
                          iconSize: 14,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsetsDirectional.only(start: 12, end: 2, top: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            p.displayName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.45,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'Cairo',
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                        if (_featuredProviderIds.contains(p.id)) ...[
                          const SizedBox(width: 4),
                          _buildPromoTag('مميز'),
                        ],
                        if (p.hasExcellenceBadges) ...[
                          const SizedBox(width: 4),
                          Flexible(
                            child: ExcellenceBadgesWrap(
                              badges: p.excellenceBadges,
                              compact: true,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (p.locationDisplay.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 11,
                            color: isDark
                                ? Colors.white38
                                : Colors.grey.shade500,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            p.locationDisplay,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontFamily: 'Cairo',
                              color: isDark
                                  ? Colors.white38
                                  : Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (distanceKm != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.near_me_outlined,
                            size: 11,
                            color: Colors.blue.shade500,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${distanceKm.toStringAsFixed(1)} كم',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.w700,
                              color: Colors.blue.shade600,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _metricChip(
                          icon: Icons.star_rounded,
                          value: p.ratingAvg > 0
                              ? p.ratingAvg.toStringAsFixed(1)
                              : '-',
                          color: Colors.amber,
                          isDark: isDark,
                        ),
                        _metricChip(
                          icon: Icons.people_outline_rounded,
                          value: '${p.followersCount}',
                          color:
                              isDark ? Colors.white38 : Colors.grey.shade500,
                          isDark: isDark,
                        ),
                        _metricChip(
                          icon: Icons.check_circle_outline_rounded,
                          value: '${p.completedRequests}',
                          color: Colors.green.shade400,
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 8, top: 42),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 12,
                color: isDark ? Colors.white24 : Colors.grey.shade400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricChip({
    required IconData icon,
    required String value,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : const Color(0xFFF8F4FC),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 9.5,
              fontFamily: 'Cairo',
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPromoTag(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w800,
          fontFamily: 'Cairo',
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _gradientBox(Color purple) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFFB39DDB), const Color(0xFFD1C4E9)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
      ),
    );
  }
}
