import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/api_client.dart';
import '../services/home_service.dart';
import '../models/category_model.dart';
import '../models/provider_public_model.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/custom_drawer.dart';
import '../widgets/excellence_badges_wrap.dart';
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
  String? _searchBannerImageUrl;
  String? _searchBannerRedirectUrl;

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
      final results = await Future.wait([
        ApiClient.get('/api/promo/active/?ad_type=banner_search&limit=1'),
        ApiClient.get('/api/promo/active/?ad_type=featured_top5&limit=10'),
      ]);
      final bannerRes = results[0];
      final featuredRes = results[1];

      if (bannerRes.isSuccess && bannerRes.data != null) {
        final items = bannerRes.data is List
            ? bannerRes.data as List
            : (bannerRes.data['results'] as List?) ?? [];
        if (items.isNotEmpty) {
          final promo = items[0] as Map<String, dynamic>;
          final assets = (promo['assets'] as List?) ?? [];
          if (assets.isNotEmpty) {
            final url = ApiClient.buildMediaUrl(assets[0]['file'] as String?);
            if (url != null && mounted) {
              setState(() {
                _searchBannerImageUrl = url;
                _searchBannerRedirectUrl = promo['redirect_url'] as String?;
              });
            }
          }
        }
      }

      if (featuredRes.isSuccess && featuredRes.data != null) {
        final items = featuredRes.data is List
            ? featuredRes.data as List
            : (featuredRes.data['results'] as List?) ?? [];
        final ids = <int>{};
        for (final item in items) {
          final pid = item['target_provider_id'];
          if (pid != null) ids.add(pid is int ? pid : int.tryParse('$pid') ?? 0);
        }
        ids.remove(0);
        if (ids.isNotEmpty && mounted) {
          setState(() {
            _featuredProviderIds = ids;
            // Re-sort: featured first
            final featured = _providers.where((p) => ids.contains(p.id)).toList();
            final rest = _providers.where((p) => !ids.contains(p.id)).toList();
            _providers = [...featured, ...rest];
          });
        }
      }
    } catch (_) {}
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
    } catch (_) {
      if (mounted) setState(() => _loadingCats = false);
    }
  }

  Future<void> _searchProviders(
      {bool requestLocationPermission = false}) async {
    if (mounted) setState(() => _loadingProviders = true);
    try {
      final q = _searchCtrl.text.trim();
      final queryParameters = <String, String>{'page_size': '30'};
      if (q.isNotEmpty) {
        queryParameters['q'] = q;
      }
      if (_selectedCatId != null) {
        queryParameters['category_id'] = _selectedCatId.toString();
      }

      final uri = Uri(
        path: '/api/providers/list/',
        queryParameters: queryParameters,
      );
      final res = await ApiClient.get(uri.toString());
      if (res.isSuccess && res.data != null) {
        final list = res.data is List
            ? res.data as List
            : (res.data['results'] as List?) ?? [];
        final providers = list
            .map((e) => ProviderPublicModel.fromJson(e as Map<String, dynamic>))
            .toList();
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
            _providers = providers;
            _loadError = null;
          });
        }
      } else {
        if (mounted) {
          setState(() => _loadError = res.error ?? 'فشل تحميل البيانات');
        }
      }
    } catch (e) {
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
    } catch (_) {
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
            isDark ? const Color(0xFF121212) : const Color(0xFFF5F5FA),
        drawer: widget.showDrawer ? const CustomDrawer() : null,
        bottomNavigationBar: widget.showBottomNavigation
            ? const CustomBottomNav(currentIndex: 2)
            : null,
        body: SafeArea(
          child: Column(
            children: [
              // ── Header + Search ──
              _buildSearchHeader(isDark, purple),

              // ── Category chips ──
              if (!_loadingCats && _categories.isNotEmpty)
                _buildCategoryChips(isDark, purple),

              // ── Sort bar ──
              _buildSortBar(isDark, purple),

              // ── Results ──
              Expanded(child: _buildResults(isDark, purple)),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════
  //  SEARCH HEADER
  // ═══════════════════════════════════════

  Widget _buildSearchHeader(bool isDark, Color purple) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          // Top bar
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : purple.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.arrow_forward_ios_rounded,
                      size: 16, color: isDark ? Colors.white70 : purple),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('البحث عن مزود خدمة',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'Cairo',
                        color: isDark ? Colors.white : Colors.black87)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Search field
          Container(
            height: 38,
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : const Color(0xFFF2F2F7),
              borderRadius: BorderRadius.circular(10),
            ),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              textAlignVertical: TextAlignVertical.center,
              style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'Cairo',
                  color: isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                hintText: 'ابحث بالاسم أو التخصص...',
                hintStyle: TextStyle(
                    fontSize: 11,
                    fontFamily: 'Cairo',
                    color: isDark ? Colors.white38 : Colors.grey.shade400),
                prefixIcon: Icon(Icons.search_rounded,
                    size: 18,
                    color: isDark ? Colors.white38 : Colors.grey.shade400),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  //  CATEGORY CHIPS
  // ═══════════════════════════════════════

  Widget _buildCategoryChips(bool isDark, Color purple) {
    return SizedBox(
      height: 38,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: _categories.length + 1, // +1 for "الكل"
        itemBuilder: (_, i) {
          final isAll = i == 0;
          final selected = isAll
              ? _selectedCatId == null
              : _selectedCatId == _categories[i - 1].id;
          final label = isAll ? 'الكل' : _categories[i - 1].name;

          return GestureDetector(
            onTap: () =>
                _onCategorySelected(isAll ? null : _categories[i - 1].id),
            child: Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: selected
                    ? purple
                    : isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected
                      ? purple
                      : (isDark ? Colors.white12 : Colors.grey.shade300),
                ),
              ),
              child: Center(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Cairo',
                        color: selected
                            ? Colors.white
                            : (isDark ? Colors.white60 : Colors.black54))),
              ),
            ),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════
  //  SORT BAR
  // ═══════════════════════════════════════

  Widget _buildSortBar(bool isDark, Color purple) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Text('${_providers.length} نتيجة',
              style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'Cairo',
                  color: isDark ? Colors.white38 : Colors.grey.shade500)),
          const Spacer(),
          GestureDetector(
            onTap: () => _openSortSheet(isDark, purple),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.tune_rounded, size: 14, color: purple),
                const SizedBox(width: 4),
                Text('فرز',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Cairo',
                        color: purple)),
              ],
            ),
          ),
        ],
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
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(99))),
                const SizedBox(height: 12),
                Row(children: [
                  Icon(Icons.tune_rounded, size: 16, color: purple),
                  const SizedBox(width: 6),
                  Text('فرز حسب:',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Cairo',
                          color: isDark ? Colors.white : Colors.black87)),
                ]),
                const SizedBox(height: 8),
                ...opts.map((o) {
                  final sel = _selectedSort == o['key'];
                  return InkWell(
                    onTap: () {
                      setState(() => _selectedSort = o['key']!);
                      _searchProviders(
                        requestLocationPermission: o['key'] == 'nearest',
                      );
                      Navigator.pop(context);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(children: [
                        Icon(
                            sel
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            size: 16,
                            color: sel ? purple : Colors.grey),
                        const SizedBox(width: 8),
                        Text(o['label']!,
                            style: TextStyle(
                                fontSize: 11,
                                fontFamily: 'Cairo',
                                fontWeight:
                                    sel ? FontWeight.w700 : FontWeight.w500,
                                color:
                                    isDark ? Colors.white70 : Colors.black87)),
                      ]),
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

  // ═══════════════════════════════════════
  //  RESULTS
  // ═══════════════════════════════════════

  Widget _buildResults(bool isDark, Color purple) {
    if (_initialLoad || _loadingProviders) {
      return const Center(
          child: CircularProgressIndicator(
              color: Colors.deepPurple, strokeWidth: 2));
    }
    if (_providers.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
                _loadError != null
                    ? Icons.cloud_off_rounded
                    : Icons.search_off_rounded,
                size: 40,
                color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(_loadError ?? 'لا توجد نتائج',
                style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'Cairo',
                    color: isDark ? Colors.white38 : Colors.grey.shade500)),
            if (_loadError != null) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _searchProviders,
                child: Text('إعادة المحاولة',
                    style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.w700,
                        color: purple)),
              ),
            ],
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: _providers.length + (_searchBannerImageUrl != null ? 1 : 0),
      itemBuilder: (_, i) {
        // Promo banner as first item
        if (_searchBannerImageUrl != null && i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(_searchBannerImageUrl!,
                fit: BoxFit.cover,
                height: 120,
                width: double.infinity,
                errorBuilder: (_, __, ___) => const SizedBox.shrink()),
            ),
          );
        }
        final idx = _searchBannerImageUrl != null ? i - 1 : i;
        return _providerCard(_providers[idx], isDark, purple);
      },
    );
  }

  Widget _providerCard(ProviderPublicModel p, bool isDark, Color purple) {
    final profileUrl = ApiClient.buildMediaUrl(p.profileImage);
    final coverUrl = ApiClient.buildMediaUrl(p.coverImage);
    final distanceKm = _distanceKmByProviderId[p.id];

    return GestureDetector(
      onTap: () => Navigator.push(
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
          )),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _featuredProviderIds.contains(p.id)
                ? const Color(0xFFF59E0B)
                : (isDark ? Colors.white10 : Colors.grey.shade200),
            width: _featuredProviderIds.contains(p.id) ? 1.5 : 1,
          ),
          boxShadow: _featuredProviderIds.contains(p.id)
              ? [BoxShadow(color: const Color(0xFFF59E0B).withValues(alpha: 0.15), blurRadius: 6)]
              : null,
        ),
        child: Row(
          children: [
            // ── Cover / Avatar section ──
            ClipRRect(
              borderRadius:
                  const BorderRadius.horizontal(right: Radius.circular(12)),
              child: SizedBox(
                width: 80,
                height: 88,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    coverUrl != null
                        ? Image.network(coverUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _gradientBox(purple))
                        : _gradientBox(purple),
                    // Gradient overlay
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.black.withValues(alpha: 0.3),
                            Colors.transparent
                          ],
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                        ),
                      ),
                    ),
                    // Avatar
                    Center(
                      child: CircleAvatar(
                        radius: 20,
                        backgroundColor: Colors.white,
                        child: CircleAvatar(
                          radius: 18,
                          backgroundColor: purple.withValues(alpha: 0.1),
                          backgroundImage: profileUrl != null
                              ? NetworkImage(profileUrl)
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
                    ),
                    // Verified badge
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

            // ── Info ──
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name
                    Row(
                      children: [
                        Flexible(
                          child: Text(p.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'Cairo',
                                  color: isDark ? Colors.white : Colors.black87)),
                        ),
                        if (_featuredProviderIds.contains(p.id)) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFD97706)]),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('مميز', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: Colors.white)),
                          ),
                        ],
                      ],
                    ),
                    if (p.city != null) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.location_on_outlined,
                              size: 11,
                              color: isDark
                                  ? Colors.white38
                                  : Colors.grey.shade500),
                          const SizedBox(width: 2),
                          Text(p.city!,
                              style: TextStyle(
                                  fontSize: 9.5,
                                  fontFamily: 'Cairo',
                                  color: isDark
                                      ? Colors.white38
                                      : Colors.grey.shade500)),
                        ],
                      ),
                    ],
                    if (p.hasExcellenceBadges) ...[
                      const SizedBox(height: 4),
                      ExcellenceBadgesWrap(
                        badges: p.excellenceBadges,
                        compact: true,
                      ),
                    ],
                    if (distanceKm != null) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.near_me_outlined,
                              size: 11, color: Colors.blue.shade500),
                          const SizedBox(width: 2),
                          Text('${distanceKm.toStringAsFixed(1)} كم',
                              style: TextStyle(
                                  fontSize: 9.5,
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.w700,
                                  color: Colors.blue.shade600)),
                        ],
                      ),
                    ],
                    const SizedBox(height: 6),
                    // Stats
                    Row(
                      children: [
                        _statChip(
                            Icons.star_rounded,
                            p.ratingAvg > 0
                                ? p.ratingAvg.toStringAsFixed(1)
                                : '-',
                            Colors.amber),
                        const SizedBox(width: 8),
                        _statChip(
                            Icons.people_outline_rounded,
                            '${p.followersCount}',
                            isDark ? Colors.white38 : Colors.grey.shade500),
                        const SizedBox(width: 8),
                        _statChip(Icons.check_circle_outline_rounded,
                            '${p.completedRequests}', Colors.green.shade400),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Arrow
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Icon(Icons.arrow_back_ios_new_rounded,
                  size: 12,
                  color: isDark ? Colors.white24 : Colors.grey.shade400),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statChip(IconData icon, String val, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 2),
        Text(val,
            style: TextStyle(
                fontSize: 9.5,
                fontFamily: 'Cairo',
                fontWeight: FontWeight.w600,
                color: color)),
      ],
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
