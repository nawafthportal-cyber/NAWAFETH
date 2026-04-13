class SaudiRegionCatalogEntry {
  final String nameAr;
  final List<String> cities;

  const SaudiRegionCatalogEntry({
    required this.nameAr,
    required this.cities,
  });

  String get displayName => nameAr.replaceFirst(RegExp(r'^منطقة\s+'), '').trim();
}

/// قائمة المدن السعودية الرسمية — تُستخدم في جميع حقول "المدينة" بالتطبيق
class SaudiCities {
  SaudiCities._();

  static String _cleanText(String? value) {
    return (value ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _stripRegionPrefix(String? value) {
    return _cleanText(value).replaceFirst(RegExp(r'^(?:منطقة|المنطقة)\s+'), '').trim();
  }

  static const List<SaudiRegionCatalogEntry> regionCatalogFallback = [
    SaudiRegionCatalogEntry(
      nameAr: 'منطقة الرياض',
      cities: [
        'الرياض',
        'الخرج',
        'الدلم',
        'الدرعية',
        'الدوادمي',
        'الزلفي',
        'السليل',
        'القويعية',
        'المجمعة',
        'المزاحمية',
        'ثادق',
        'حوطة بني تميم',
        'شقراء',
        'ضرما',
        'عفيف',
        'الأفلاج',
      ],
    ),
    SaudiRegionCatalogEntry(
      nameAr: 'منطقة مكة المكرمة',
      cities: [
        'مكة المكرمة',
        'جدة',
        'الطائف',
        'الجموم',
        'رابغ',
        'القنفذة',
        'الليث',
        'تربة',
        'رنية',
        'ظلم',
      ],
    ),
    SaudiRegionCatalogEntry(
      nameAr: 'منطقة المدينة المنورة',
      cities: ['المدينة المنورة', 'ينبع', 'بدر', 'خيبر', 'العلا'],
    ),
    SaudiRegionCatalogEntry(
      nameAr: 'المنطقة الشرقية',
      cities: [
        'الدمام',
        'الخبر',
        'الظهران',
        'الأحساء',
        'الجبيل',
        'الخفجي',
        'القطيف',
        'حفر الباطن',
      ],
    ),
    SaudiRegionCatalogEntry(
      nameAr: 'منطقة القصيم',
      cities: ['بريدة', 'عنيزة', 'الرس', 'البكيرية', 'البدائع', 'المذنب'],
    ),
    SaudiRegionCatalogEntry(
      nameAr: 'منطقة عسير',
      cities: [
        'أبها',
        'خميس مشيط',
        'بيشة',
        'محايل عسير',
        'النماص',
        'تنومة',
        'سراة عبيدة',
      ],
    ),
    SaudiRegionCatalogEntry(
      nameAr: 'منطقة تبوك',
      cities: ['تبوك', 'ضباء', 'الوجه', 'حقل', 'أملج'],
    ),
    SaudiRegionCatalogEntry(nameAr: 'منطقة حائل', cities: ['حائل']),
    SaudiRegionCatalogEntry(
      nameAr: 'منطقة الجوف',
      cities: ['سكاكا', 'القريات', 'طبرجل'],
    ),
    SaudiRegionCatalogEntry(
      nameAr: 'منطقة الحدود الشمالية',
      cities: ['عرعر', 'رفحاء', 'طريف'],
    ),
    SaudiRegionCatalogEntry(
      nameAr: 'منطقة نجران',
      cities: ['نجران', 'شرورة'],
    ),
    SaudiRegionCatalogEntry(
      nameAr: 'منطقة جازان',
      cities: ['جازان', 'صامطة', 'صبيا'],
    ),
    SaudiRegionCatalogEntry(
      nameAr: 'منطقة الباحة',
      cities: ['الباحة', 'بلجرشي', 'العرضيات'],
    ),
  ];

  /// جميع المدن مرتّبة أبجدياً
  static const List<String> all = [
    'أبها',
    'الأحساء',
    'الأفلاج',
    'الباحة',
    'البكيرية',
    'البدائع',
    'الجبيل',
    'الجموم',
    'الحريق',
    'الحوطة',
    'الخبر',
    'الخرج',
    'الخفجي',
    'الدرعية',
    'الدلم',
    'الدمام',
    'الدوادمي',
    'الرس',
    'الرياض',
    'الزلفي',
    'السليل',
    'الطائف',
    'الظهران',
    'العرضيات',
    'العلا',
    'القريات',
    'القصيم',
    'القطيف',
    'القنفذة',
    'القويعية',
    'الليث',
    'المجمعة',
    'المدينة المنورة',
    'المذنب',
    'المزاحمية',
    'النماص',
    'الوجه',
    'أملج',
    'بدر',
    'بريدة',
    'بلجرشي',
    'بيشة',
    'تبوك',
    'تربة',
    'تنومة',
    'ثادق',
    'جازان',
    'جدة',
    'حائل',
    'حفر الباطن',
    'حقل',
    'حوطة بني تميم',
    'خميس مشيط',
    'خيبر',
    'رابغ',
    'رفحاء',
    'رنية',
    'سراة عبيدة',
    'سكاكا',
    'شرورة',
    'شقراء',
    'صامطة',
    'صبيا',
    'ضباء',
    'ضرما',
    'طبرجل',
    'طريف',
    'ظلم',
    'عرعر',
    'عفيف',
    'عنيزة',
    'محايل عسير',
    'مكة المكرمة',
    'نجران',
    'ينبع',
  ];

  static final Map<String, String> _cityToRegion = {
    for (final entry in regionCatalogFallback)
      for (final city in entry.cities)
        if (city.trim().isNotEmpty) city.trim(): entry.displayName,
  };

  static String lookupRegionByCity(String? city) {
    final cityText = _cleanText(city);
    if (cityText.isEmpty) return '';
    return _cityToRegion[cityText] ?? '';
  }

  static String formatCityDisplay(String? city, {String? region}) {
    final cityText = _cleanText(city);
    final regionText = _stripRegionPrefix(region);

    if (cityText.isEmpty) return '';
    if (cityText.contains(' - ')) return cityText;
    if (regionText.isNotEmpty) {
      if (cityText == regionText || cityText.startsWith('$regionText - ')) {
        return cityText;
      }
      return '$regionText - $cityText';
    }

    final inferredRegion = lookupRegionByCity(cityText);
    if (inferredRegion.isEmpty || inferredRegion == cityText) return cityText;
    return '$inferredRegion - $cityText';
  }
}
