import 'excellence_badge_model.dart';

/// نموذج بيانات ملف المزود (من /api/providers/me/profile/)
class ProviderProfileModel {
  final int id;
  final String providerType;
  final String displayName;
  final String? profileImage;
  final String? coverImage;
  final String bio;
  final String? aboutDetails;
  final int yearsExperience;
  final String? whatsapp;
  final String? website;
  final List<dynamic> socialLinks;
  final List<dynamic> languages;
  final String city;
  final double? lat;
  final double? lng;
  final int coverageRadiusKm;
  final List<dynamic> qualifications;
  final List<dynamic> experiences;
  final List<dynamic> contentSections;
  final String seoKeywords;
  final String? seoMetaDescription;
  final String? seoSlug;
  final bool acceptsUrgent;
  final bool isVerifiedBlue;
  final bool isVerifiedGreen;
  final List<ExcellenceBadgeModel> excellenceBadges;
  final double ratingAvg;
  final int ratingCount;
  final String? createdAt;

  ProviderProfileModel({
    required this.id,
    required this.providerType,
    required this.displayName,
    this.profileImage,
    this.coverImage,
    required this.bio,
    this.aboutDetails,
    required this.yearsExperience,
    this.whatsapp,
    this.website,
    required this.socialLinks,
    required this.languages,
    required this.city,
    this.lat,
    this.lng,
    required this.coverageRadiusKm,
    required this.qualifications,
    required this.experiences,
    required this.contentSections,
    required this.seoKeywords,
    this.seoMetaDescription,
    this.seoSlug,
    required this.acceptsUrgent,
    required this.isVerifiedBlue,
    required this.isVerifiedGreen,
    this.excellenceBadges = const [],
    required this.ratingAvg,
    required this.ratingCount,
    this.createdAt,
  });

  static const double baseCompletionWeight = 0.30;
  static const double optionalSectionsWeight = 0.70;
  static const int optionalSectionsCount = 6;
  static const double optionalSectionWeight =
      optionalSectionsWeight / optionalSectionsCount;

  /// تحويل من JSON
  factory ProviderProfileModel.fromJson(Map<String, dynamic> json) {
    return ProviderProfileModel(
      id: json['id'] as int,
      providerType: json['provider_type'] as String? ?? 'individual',
      displayName: json['display_name'] as String? ?? '',
      profileImage: json['profile_image'] as String?,
      coverImage: json['cover_image'] as String?,
      bio: json['bio'] as String? ?? '',
      aboutDetails: json['about_details'] as String?,
      yearsExperience: json['years_experience'] as int? ?? 0,
      whatsapp: json['whatsapp'] as String?,
      website: json['website'] as String?,
      socialLinks: json['social_links'] as List<dynamic>? ?? [],
      languages: json['languages'] as List<dynamic>? ?? [],
      city: json['city'] as String? ?? '',
      lat: _parseDouble(json['lat']),
      lng: _parseDouble(json['lng']),
      coverageRadiusKm: json['coverage_radius_km'] as int? ?? 10,
      qualifications: json['qualifications'] as List<dynamic>? ?? [],
      experiences: json['experiences'] as List<dynamic>? ?? [],
      contentSections: json['content_sections'] as List<dynamic>? ?? [],
      seoKeywords: json['seo_keywords'] as String? ?? '',
      seoMetaDescription: json['seo_meta_description'] as String?,
      seoSlug: json['seo_slug'] as String?,
      acceptsUrgent: json['accepts_urgent'] as bool? ?? false,
      isVerifiedBlue: json['is_verified_blue'] as bool? ?? false,
      isVerifiedGreen: json['is_verified_green'] as bool? ?? false,
      excellenceBadges: _parseExcellenceBadges(json['excellence_badges']),
      ratingAvg: _parseDouble(json['rating_avg']) ?? 0.0,
      ratingCount: json['rating_count'] as int? ?? 0,
      createdAt: json['created_at'] as String?,
    );
  }

  bool get hasExcellenceBadges => excellenceBadges.isNotEmpty;

  /// ─── حساب نسبة إكمال الملف التعريفي ───
  ///
  /// 30% من التسجيل الأساسي + 70% موزعة بالتساوي على 6 أقسام.
  double get profileCompletion {
    final completedOptionalSections = [
      isServiceDetailsComplete,
      isAdditionalDetailsComplete,
      isContactInfoComplete,
      isLanguageLocationComplete,
      isContentComplete,
      isSeoComplete,
    ].where((v) => v).length;

    final completion =
        baseCompletionWeight + (completedOptionalSections * optionalSectionWeight);
    return completion.clamp(0.0, 1.0);
  }

  bool get isServiceDetailsComplete =>
      _hasText(displayName) && _hasText(bio);

  bool get isAdditionalDetailsComplete =>
      _hasText(aboutDetails) ||
      _hasNonEmptyList(qualifications) ||
      _hasNonEmptyList(experiences);

  bool get isContactInfoComplete =>
      _hasText(whatsapp) ||
      _hasText(website) ||
      _hasNonEmptyList(socialLinks);

  bool get isLanguageLocationComplete =>
      _hasNonEmptyList(languages) && coverageRadiusKm > 0;

  bool get isContentComplete =>
      _hasText(profileImage) ||
      _hasText(coverImage) ||
      _hasNonEmptyList(contentSections);

  bool get isSeoComplete =>
      _hasText(seoKeywords) ||
      _hasText(seoMetaDescription) ||
      _hasText(seoSlug);

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static bool _hasText(String? value) => value != null && value.trim().isNotEmpty;

  static bool _hasNonEmptyList(List<dynamic>? value) {
    if (value == null || value.isEmpty) return false;
    return value.any((item) {
      if (item == null) return false;
      if (item is String) return item.trim().isNotEmpty;
      if (item is Map) return item.isNotEmpty;
      if (item is Iterable) return item.isNotEmpty;
      return true;
    });
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
