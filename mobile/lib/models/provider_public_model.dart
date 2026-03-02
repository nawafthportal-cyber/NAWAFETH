/// نموذج بيانات مزود الخدمة العام — يطابق ProviderPublicSerializer
///
/// يُستخدم في:
/// - قائمة "من أتابع" (التفاعلي)
/// - نتائج البحث عن مزودي الخدمة
/// - أي قائمة عامة لمزودي الخدمة
class ProviderPublicModel {
  final int id;
  final String displayName;
  final String? username;
  final String? profileImage;
  final String? coverImage;
  final String? bio;
  final String? aboutDetails;
  final int? yearsExperience;
  final String? phone;
  final String? whatsapp;
  final String? website;
  final List<dynamic> socialLinks;
  final List<dynamic> languages;
  final String? city;
  final double? lat;
  final double? lng;
  final double? coverageRadiusKm;
  final bool acceptsUrgent;
  final bool isVerifiedBlue;
  final bool isVerifiedGreen;
  final List<dynamic> qualifications;
  final List<dynamic> contentSections;
  final double ratingAvg;
  final int ratingCount;
  final String? createdAt;

  // ── إحصائيات اجتماعية ──
  final int followersCount;
  final int likesCount;
  final int followingCount;
  final int completedRequests;

  ProviderPublicModel({
    required this.id,
    required this.displayName,
    this.username,
    this.profileImage,
    this.coverImage,
    this.bio,
    this.aboutDetails,
    this.yearsExperience,
    this.phone,
    this.whatsapp,
    this.website,
    this.socialLinks = const [],
    this.languages = const [],
    this.city,
    this.lat,
    this.lng,
    this.coverageRadiusKm,
    this.acceptsUrgent = false,
    this.isVerifiedBlue = false,
    this.isVerifiedGreen = false,
    this.qualifications = const [],
    this.contentSections = const [],
    this.ratingAvg = 0.0,
    this.ratingCount = 0,
    this.createdAt,
    this.followersCount = 0,
    this.likesCount = 0,
    this.followingCount = 0,
    this.completedRequests = 0,
  });

  factory ProviderPublicModel.fromJson(Map<String, dynamic> json) {
    return ProviderPublicModel(
      id: _parseInt(json['id']) ?? 0,
      displayName: _parseString(json['display_name']) ?? '',
      username: _parseString(json['username']),
      profileImage: _parseString(json['profile_image']),
      coverImage: _parseString(json['cover_image']),
      bio: _parseString(json['bio']),
      aboutDetails: _parseString(json['about_details']),
      yearsExperience: _parseInt(json['years_experience']),
      phone: _parseString(json['phone']),
      whatsapp: _parseString(json['whatsapp']),
      website: _parseString(json['website']),
      socialLinks: json['social_links'] is List
          ? json['social_links'] as List<dynamic>
          : [],
      languages:
          json['languages'] is List ? json['languages'] as List<dynamic> : [],
      city: _parseString(json['city']),
      lat: _parseDouble(json['lat']),
      lng: _parseDouble(json['lng']),
      coverageRadiusKm: _parseDouble(json['coverage_radius_km']),
      acceptsUrgent: _parseBool(json['accepts_urgent']),
      isVerifiedBlue: _parseBool(json['is_verified_blue']),
      isVerifiedGreen: _parseBool(json['is_verified_green']),
      qualifications: json['qualifications'] is List
          ? json['qualifications'] as List<dynamic>
          : [],
      contentSections: json['content_sections'] is List
          ? json['content_sections'] as List<dynamic>
          : [],
      ratingAvg: _parseDouble(json['rating_avg']) ?? 0.0,
      ratingCount: _parseInt(json['rating_count']) ?? 0,
      createdAt: _parseString(json['created_at']),
      followersCount: _parseInt(json['followers_count']) ?? 0,
      likesCount: _parseInt(json['likes_count']) ?? 0,
      followingCount: _parseInt(json['following_count']) ?? 0,
      completedRequests: _parseInt(json['completed_requests']) ?? 0,
    );
  }

  /// هل المزود مُوثق (أزرق أو أخضر)
  bool get isVerified => isVerifiedBlue || isVerifiedGreen;

  static String? _parseString(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final text = value.trim();
      if (text.isEmpty) return null;
      return int.tryParse(text) ?? double.tryParse(text)?.toInt();
    }
    return null;
  }

  static double? _parseDouble(dynamic value) {
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

  static bool _parseBool(dynamic value) {
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
}
