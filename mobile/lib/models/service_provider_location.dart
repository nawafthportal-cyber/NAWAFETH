import 'excellence_badge_model.dart';
import '../constants/saudi_cities.dart';

class ServiceProviderLocation {
  final String id;
  final String name;
  final String category;           // "صيانة المركبات"
  final String subCategory;        // "ميكانيكا"
  final String city;
  final String cityDisplay;
  final double latitude;
  final double longitude;
  final double rating;
  final int operationsCount;
  final bool isAvailable;          // متاح الآن؟
  final bool isUrgentEnabled;      // يقبل طلبات عاجلة؟
  final String? profileImage;
  final double? distanceFromUser;  // محسوبة ديناميكياً (بالكيلومتر)
  
  // بيانات إضافية
  final String phoneNumber;
  final List<String> urgentServices;  // الخدمات العاجلة المتاحة
  final int responseTime;             // متوسط وقت الرد (بالدقائق)
  final bool isVerifiedBlue;
  final bool isVerifiedGreen;
  final List<ExcellenceBadgeModel> excellenceBadges;

  bool get verified => isVerifiedBlue || isVerifiedGreen;
  bool get hasExcellenceBadges => excellenceBadges.isNotEmpty;

  ServiceProviderLocation({
    required this.id,
    required this.name,
    required this.category,
    required this.subCategory,
    this.city = '',
    this.cityDisplay = '',
    required this.latitude,
    required this.longitude,
    required this.rating,
    required this.operationsCount,
    this.isAvailable = true,
    this.isUrgentEnabled = true,
    this.profileImage,
    this.distanceFromUser,
    required this.phoneNumber,
    this.urgentServices = const [],
    this.responseTime = 15,
    this.isVerifiedBlue = false,
    this.isVerifiedGreen = false,
    this.excellenceBadges = const [],
  });

  // ✅ إنشاء من JSON (يدعم استجابة الباكند)
  factory ServiceProviderLocation.fromJson(Map<String, dynamic> json) {
    return ServiceProviderLocation(
      id: (json['id'] ?? json['pk'] ?? '').toString(),
      name: json['display_name'] ?? json['name'] ?? '',
      category: json['category'] ?? '',
      subCategory: json['subCategory'] ?? json['sub_category'] ?? '',
      city: json['city'] ?? '',
      cityDisplay: json['city_display'] ?? '',
      latitude: _toDouble(json['lat'] ?? json['latitude']),
      longitude: _toDouble(json['lng'] ?? json['longitude']),
      rating: _toDouble(json['rating_avg'] ?? json['rating']),
      operationsCount:
          _toInt(json['completed_requests'] ?? json['operationsCount']),
      isAvailable: json['isAvailable'] ?? json['is_available'] ?? true,
      isUrgentEnabled:
          json['isUrgentEnabled'] ?? json['accepts_urgent'] ?? true,
      profileImage: json['profile_image'] ?? json['profileImage'],
      distanceFromUser: json['distanceFromUser'] != null
          ? _toDouble(json['distanceFromUser'])
          : null,
      phoneNumber: json['phone'] ?? json['phoneNumber'] ?? '',
      urgentServices: List<String>.from(json['urgentServices'] ?? []),
      responseTime: _toInt(json['responseTime'] ?? json['response_time']),
        isVerifiedBlue: _toBool(json['is_verified_blue']),
        isVerifiedGreen: _toBool(json['is_verified_green']) ||
          (!_toBool(json['is_verified_blue']) && _toBool(json['verified'])),
        excellenceBadges: _parseExcellenceBadges(json['excellence_badges']),
    );
  }

  static double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  static int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static bool _toBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final value = v.trim().toLowerCase();
      return value == 'true' ||
          value == '1' ||
          value == 'yes' ||
          value == 'y' ||
          value == 'on';
    }
    return false;
  }

  String get locationDisplay => SaudiCities.formatCityDisplay(
        cityDisplay.isNotEmpty ? cityDisplay : city,
      );

  // ✅ تحويل إلى JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'subCategory': subCategory,
      'city': city,
      'latitude': latitude,
      'longitude': longitude,
      'rating': rating,
      'operationsCount': operationsCount,
      'isAvailable': isAvailable,
      'isUrgentEnabled': isUrgentEnabled,
      'profileImage': profileImage,
      'distanceFromUser': distanceFromUser,
      'phoneNumber': phoneNumber,
      'urgentServices': urgentServices,
      'responseTime': responseTime,
      'is_verified_blue': isVerifiedBlue,
      'is_verified_green': isVerifiedGreen,
      'excellence_badges': excellenceBadges.map((item) => item.toJson()).toList(growable: false),
      'verified': verified,
    };
  }

  // ✅ نسخ مع تعديلات
  ServiceProviderLocation copyWith({
    String? id,
    String? name,
    String? category,
    String? subCategory,
    String? city,
    String? cityDisplay,
    double? latitude,
    double? longitude,
    double? rating,
    int? operationsCount,
    bool? isAvailable,
    bool? isUrgentEnabled,
    String? profileImage,
    double? distanceFromUser,
    String? phoneNumber,
    List<String>? urgentServices,
    int? responseTime,
    bool? isVerifiedBlue,
    bool? isVerifiedGreen,
    List<ExcellenceBadgeModel>? excellenceBadges,
  }) {
    return ServiceProviderLocation(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      subCategory: subCategory ?? this.subCategory,
      city: city ?? this.city,
      cityDisplay: cityDisplay ?? this.cityDisplay,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      rating: rating ?? this.rating,
      operationsCount: operationsCount ?? this.operationsCount,
      isAvailable: isAvailable ?? this.isAvailable,
      isUrgentEnabled: isUrgentEnabled ?? this.isUrgentEnabled,
      profileImage: profileImage ?? this.profileImage,
      distanceFromUser: distanceFromUser ?? this.distanceFromUser,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      urgentServices: urgentServices ?? this.urgentServices,
      responseTime: responseTime ?? this.responseTime,
      isVerifiedBlue: isVerifiedBlue ?? this.isVerifiedBlue,
      isVerifiedGreen: isVerifiedGreen ?? this.isVerifiedGreen,
      excellenceBadges: excellenceBadges ?? this.excellenceBadges,
    );
  }

  static List<ExcellenceBadgeModel> _parseExcellenceBadges(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => ExcellenceBadgeModel.fromJson(Map<String, dynamic>.from(item)))
        .where((item) => item.code.isNotEmpty || item.name.isNotEmpty)
        .toList(growable: false);
  }
}
