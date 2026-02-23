import 'package:flutter/material.dart';
import '../widgets/bottom_nav.dart';
import 'provider_profile_screen.dart';
import '../widgets/custom_drawer.dart';
import '../services/providers_api.dart';
import '../services/home_feed_service.dart';
import '../models/category.dart';
import '../models/provider.dart';
import '../widgets/banner_widget.dart';

class SearchProviderScreen extends StatefulWidget {
  final int? initialCategoryId;
  final String? initialQuery;
  final String? initialCity;

  const SearchProviderScreen({super.key})
      : initialCategoryId = null,
        initialQuery = null,
        initialCity = null;
  const SearchProviderScreen.withFilters({
    super.key,
    this.initialCategoryId,
    this.initialQuery,
    this.initialCity,
  });

  @override
  State<SearchProviderScreen> createState() => _SearchProviderScreenState();
}

class _SearchProviderScreenState extends State<SearchProviderScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  int? _selectedCategoryId;
  int? _selectedSubcategoryId;
  String? _selectedCity;

  final ProvidersApi _providersApi = ProvidersApi();
  final HomeFeedService _feed = HomeFeedService.instance;
  List<Category> _categories = [];
  List<ProviderProfile> _providers = [];
  bool _loading = false;
  bool _filtersExpanded = false;

  final List<String> _saudiCities = [
    'الرياض',
    'جدة',
    'مكة المكرمة',
    'المدينة المنورة',
    'الدمام',
    'الخبر',
    'الظهران',
    'الطائف',
    'تبوك',
    'بريدة',
    'خميس مشيط',
    'الهفوف',
    'حفر الباطن',
    'حائل',
    'نجران',
    'جازان',
    'ينبع',
    'القطيف',
    'أبها',
    'عرعر',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery != null && widget.initialQuery!.trim().isNotEmpty) {
      _searchController.text = widget.initialQuery!.trim();
    }
    _selectedCategoryId = widget.initialCategoryId;
    _selectedCity = widget.initialCity;
    if (_selectedCity != null) {
      _cityController.text = _selectedCity!;
    }
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _loadCategories();
    await _loadProviders();
  }

  Future<void> _loadCategories() async {
    final cats = await _providersApi.getCategories();
    if (!mounted) return;
    setState(() {
      _categories = cats;
    });
  }

  Future<void> _loadProviders() async {
    setState(() => _loading = true);
    try {
      // إذا لم يتم إدخال أي فلاتر، نستخدم getProviders() لعرض الجميع
      final hasFilters = _searchController.text.trim().isNotEmpty ||
                        _selectedCity != null ||
                        _selectedCategoryId != null ||
                        _selectedSubcategoryId != null;
      
      final List<ProviderProfile> list;
      if (hasFilters) {
        list = await _providersApi.getProvidersFiltered(
          q: _searchController.text.trim(),
          city: _selectedCity,
          categoryId: _selectedCategoryId,
          subcategoryId: _selectedSubcategoryId,
        );
      } else {
        // تحميل جميع المزودين عند عدم وجود فلاتر
        list = await _providersApi.getProviders();
      }

      // Apply paid promo boosts/featured ordering (admin-managed) using /api/promo/active/.
      String? categoryName;
      if (_selectedCategoryId != null) {
        for (final c in _categories) {
          if (c.id == _selectedCategoryId) {
            categoryName = c.name;
            break;
          }
        }
      }

      final reordered = await _feed.reorderProvidersForPromos(
        providers: list,
        city: _selectedCity,
        categoryName: categoryName,
      );
      
      if (!mounted) return;
      setState(() {
        _providers = reordered;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  void _clearFilters() {
    setState(() {
      _selectedCategoryId = null;
      _selectedSubcategoryId = null;
      _selectedCity = null;
      _cityController.clear();
    });
    _loadProviders();
  }

  int get _activeFiltersCount {
    int count = 0;
    if (_selectedCategoryId != null) count++;
    if (_selectedSubcategoryId != null) count++;
    if (_selectedCity != null) count++;
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    final selectedCategory = _selectedCategoryId == null
        ? null
        : _categories.where((c) => c.id == _selectedCategoryId).cast<Category?>().firstOrNull;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? Colors.grey[900] : const Color(0xFFF8F9FD),
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(70),
          child: AppBar(
            backgroundColor: isDark ? Colors.grey[850] : Colors.white,
            elevation: 0,
            centerTitle: true,
            title: Column(
              children: [
                const Text(
                  "🔍 ابحث عن مزود خدمة",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                  ),
                ),
                Text(
                  _providers.isEmpty && !_loading
                      ? "استخدم الفلاتر للبحث"
                      : "${_providers.length} نتيجة",
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: 'Cairo',
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ],
            ),
            leading: Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.menu_rounded),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
          ),
        ),
        bottomNavigationBar: const CustomBottomNav(currentIndex: 2),
        drawer: const CustomDrawer(),
        body: Column(
          children: [
            // بطاقة الفلاتر العلوية
            Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [
                          const Color(0xFF6366F1),
                          const Color(0xFF8B5CF6),
                        ]
                      : [
                          const Color(0xFF6366F1),
                          const Color(0xFFA855F7),
                        ],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // حقل البحث
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (_) => _loadProviders(),
                        style: const TextStyle(fontFamily: 'Cairo'),
                        decoration: InputDecoration(
                          hintText: 'ابحث بالاسم...',
                          hintStyle: TextStyle(
                            fontFamily: 'Cairo',
                            color: Colors.grey[400],
                          ),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            color: Color(0xFF6366F1),
                            size: 24,
                          ),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: Icon(
                                    Icons.clear_rounded,
                                    color: Colors.grey[600],
                                  ),
                                  onPressed: () {
                                    _searchController.clear();
                                    _loadProviders();
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                  
                  // زر الفلاتر
                  Padding(
                    padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
                    child: InkWell(
                      onTap: () => setState(() => _filtersExpanded = !_filtersExpanded),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.4),
                            width: 2,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _filtersExpanded
                                  ? Icons.filter_alt_rounded
                                  : Icons.filter_alt_outlined,
                              color: Colors.white,
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'خيارات البحث المتقدم',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            if (_activeFiltersCount > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '$_activeFiltersCount',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Cairo',
                                    color: Color(0xFF6366F1),
                                  ),
                                ),
                              ),
                            const SizedBox(width: 8),
                            Icon(
                              _filtersExpanded
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  
                  // قسم الفلاتر المتقدمة
                  if (_filtersExpanded)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(20),
                          bottomRight: Radius.circular(20),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // التصنيف الرئيسي
                          _buildFilterSection(
                            icon: Icons.category_rounded,
                            title: '📂 التصنيف الرئيسي',
                            child: _buildCategoryDropdown(isDark),
                          ),
                          
                          // التصنيف الفرعي
                          if (selectedCategory != null &&
                              selectedCategory.subcategories.isNotEmpty)
                            _buildFilterSection(
                              icon: Icons.layers_rounded,
                              title: '📑 التصنيف الفرعي',
                              child: _buildSubcategoryDropdown(
                                selectedCategory,
                                isDark,
                              ),
                            ),
                          
                          // المدينة
                          _buildFilterSection(
                            icon: Icons.location_city_rounded,
                            title: '🏙️ المدينة',
                            child: _buildCityDropdown(isDark),
                          ),
                          
                          // أزرار التحكم
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _clearFilters,
                                  icon: const Icon(Icons.clear_all_rounded),
                                  label: const Text(
                                    'مسح الكل',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        Colors.white.withValues(alpha: 0.25),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(
                                        color: Colors.white.withValues(alpha: 0.4),
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    setState(() => _filtersExpanded = false);
                                    _loadProviders();
                                  },
                                  icon: const Icon(Icons.search_rounded),
                                  label: const Text(
                                    'بحث',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: const Color(0xFF6366F1),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
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
            
            // النتائج
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF6366F1),
                      ),
                    )
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: SizedBox(
                            height: 180,
                            child: BannerWidget(
                              placement: BannerPlacement.search,
                              city: _selectedCity,
                              categoryName: selectedCategory?.name,
                              limit: 3,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: _providers.isEmpty
                              ? _buildEmptyState()
                              : ListView.builder(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  itemCount: _providers.length,
                                  itemBuilder: (_, index) {
                                    final provider = _providers[index];
                                    return _buildProviderCard(provider, isDark);
                                  },
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

  
  Widget _buildFilterSection({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo',
                color: Colors.white,
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }

  Widget _buildCategoryDropdown(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: DropdownButtonFormField<int>(
        initialValue: _selectedCategoryId,
        decoration: InputDecoration(
          hintText: 'اختر التصنيف الرئيسي',
          hintStyle: TextStyle(
            fontFamily: 'Cairo',
            color: Colors.grey[600],
          ),
          prefixIcon: const Icon(
            Icons.category_rounded,
            color: Color(0xFF6366F1),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
        style: const TextStyle(
          fontFamily: 'Cairo',
          color: Colors.black87,
          fontSize: 14,
        ),
        dropdownColor: Colors.white,
        isExpanded: true,
        items: _categories.map((category) {
          return DropdownMenuItem<int>(
            value: category.id,
            child: Text(category.name),
          );
        }).toList(),
        onChanged: (value) {
          setState(() {
            _selectedCategoryId = value;
            _selectedSubcategoryId = null;
          });
          _loadProviders();
        },
      ),
    );
  }

  Widget _buildSubcategoryDropdown(Category category, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: DropdownButtonFormField<int>(
        initialValue: _selectedSubcategoryId,
        decoration: InputDecoration(
          hintText: 'اختر التصنيف الفرعي',
          hintStyle: TextStyle(
            fontFamily: 'Cairo',
            color: Colors.grey[600],
          ),
          prefixIcon: const Icon(
            Icons.layers_rounded,
            color: Color(0xFF6366F1),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
        style: const TextStyle(
          fontFamily: 'Cairo',
          color: Colors.black87,
          fontSize: 14,
        ),
        dropdownColor: Colors.white,
        isExpanded: true,
        items: category.subcategories.map((subcategory) {
          return DropdownMenuItem<int>(
            value: subcategory.id,
            child: Text(subcategory.name),
          );
        }).toList(),
        onChanged: (value) {
          setState(() => _selectedSubcategoryId = value);
          _loadProviders();
        },
      ),
    );
  }

  Widget _buildCityDropdown(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: DropdownButtonFormField<String>(
        initialValue: _selectedCity,
        decoration: InputDecoration(
          hintText: 'اختر المدينة',
          hintStyle: TextStyle(
            fontFamily: 'Cairo',
            color: Colors.grey[600],
          ),
          prefixIcon: const Icon(
            Icons.location_city_rounded,
            color: Color(0xFF6366F1),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
        style: const TextStyle(
          fontFamily: 'Cairo',
          color: Colors.black87,
          fontSize: 14,
        ),
        dropdownColor: Colors.white,
        isExpanded: true,
        items: _saudiCities.map((city) {
          return DropdownMenuItem<String>(
            value: city,
            child: Text(city),
          );
        }).toList(),
        onChanged: (value) {
          setState(() => _selectedCity = value);
          _loadProviders();
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.search_off_rounded,
              size: 60,
              color: Color(0xFF6366F1),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'لا توجد نتائج',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              fontFamily: 'Cairo',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'جرب تغيير خيارات البحث',
            style: TextStyle(
              fontSize: 15,
              fontFamily: 'Cairo',
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  // 🧾 بطاقة مزود الخدمة
  Widget _buildProviderCard(ProviderProfile provider, bool isDark) {
    final double rating = provider.ratingAvg;
    final int ratingCount = provider.ratingCount;
    final String cityText = provider.city ?? 'غير محدد';
    final String experienceText = provider.yearsExperience > 0
        ? '${provider.yearsExperience} سنوات خبرة'
        : '';

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProviderProfileScreen(
              providerId: provider.id.toString(),
              providerName: provider.displayName,
              providerRating: provider.ratingAvg,
              providerOperations: provider.ratingCount,
              providerVerified:
                  provider.isVerifiedBlue || provider.isVerifiedGreen,
              providerPhone: provider.phone,
              providerLat: provider.lat,
              providerLng: provider.lng,
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [
                    Colors.grey[850]!,
                    Colors.grey[800]!,
                  ]
                : [
                    Colors.white,
                    Colors.grey[50]!,
                  ],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.3)
                  : Colors.grey.withValues(alpha: 0.15),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: isDark
                ? Colors.grey[700]!
                : const Color(0xFF6366F1).withValues(alpha: 0.1),
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // الصورة + التوثيق
              Stack(
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF6366F1).withValues(alpha: 0.2),
                          const Color(0xFFA855F7).withValues(alpha: 0.2),
                        ],
                      ),
                      border: Border.all(
                        color: const Color(0xFF6366F1),
                        width: 3,
                      ),
                    ),
                    child: const Icon(
                      Icons.person_rounded,
                      size: 36,
                      color: Color(0xFF6366F1),
                    ),
                  ),
                  if (provider.isVerifiedBlue || provider.isVerifiedGreen)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.lightBlue,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark ? Colors.grey[850]! : Colors.white,
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.verified_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),
              
              // المعلومات
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      provider.displayName ?? 'غير محدد',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'Cairo',
                        height: 1.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_rounded,
                          size: 16,
                          color: Color(0xFF6366F1),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            [cityText, experienceText]
                                .where((e) => e.isNotEmpty)
                                .join(' • '),
                            style: TextStyle(
                              fontSize: 13,
                              fontFamily: 'Cairo',
                              color: Colors.grey[600],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        // التقييم
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFFFBBF24),
                                Color(0xFFF59E0B),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                size: 16,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                rating.toStringAsFixed(1),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  fontFamily: 'Cairo',
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // عدد التقييمات
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.people_rounded,
                                size: 16,
                                color: Color(0xFF6366F1),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$ratingCount',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  fontFamily: 'Cairo',
                                  color: Color(0xFF6366F1),
                                ),
                              ),
                            ],
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
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

