class ServiceProviderLocation {
  final String id;
  final String name;
  final String category;           // "صيانة المركبات"
  final String subCategory;        // "ميكانيكا"
  final String city;
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
  final bool verified;                // موثق؟

  ServiceProviderLocation({
    required this.id,
    required this.name,
    required this.category,
    required this.subCategory,
    this.city = '',
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
    this.verified = false,
  });

  // ✅ إنشاء من JSON (يدعم استجابة الباكند)
  factory ServiceProviderLocation.fromJson(Map<String, dynamic> json) {
    return ServiceProviderLocation(
      id: (json['id'] ?? json['pk'] ?? '').toString(),
      name: json['display_name'] ?? json['name'] ?? '',
      category: json['category'] ?? '',
      subCategory: json['subCategory'] ?? json['sub_category'] ?? '',
      city: json['city'] ?? '',
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
      verified: json['is_verified_blue'] ??
          json['is_verified_green'] ??
          json['verified'] ??
          false,
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
    bool? verified,
  }) {
    return ServiceProviderLocation(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      subCategory: subCategory ?? this.subCategory,
      city: city ?? this.city,
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
      verified: verified ?? this.verified,
    );
  }
}
