import 'excellence_badge_model.dart';
import '../constants/saudi_cities.dart';

class FeaturedSpecialistModel {
  final int placementId;
  final int providerId;
  final String displayName;
  final String? profileImage;
  final String? city;
  final String? cityDisplay;
  final String? redirectUrl;
  final bool isVerifiedBlue;
  final bool isVerifiedGreen;
  final double ratingAvg;
  final int ratingCount;
  final bool isOnline;
  final List<ExcellenceBadgeModel> excellenceBadges;

  const FeaturedSpecialistModel({
    required this.placementId,
    required this.providerId,
    required this.displayName,
    this.profileImage,
    this.city,
    this.cityDisplay,
    this.redirectUrl,
    this.isVerifiedBlue = false,
    this.isVerifiedGreen = false,
    this.ratingAvg = 0,
    this.ratingCount = 0,
    this.isOnline = false,
    this.excellenceBadges = const [],
  });

  factory FeaturedSpecialistModel.fromPromoPlacement(
    Map<String, dynamic> json,
  ) {
    return FeaturedSpecialistModel(
      placementId: _parseInt(json['item_id']) ?? _parseInt(json['id']) ?? 0,
      providerId: _parseInt(json['target_provider_id']) ?? 0,
      displayName: _parseString(json['target_provider_display_name']) ?? 'مختص',
      profileImage: _parseString(json['target_provider_profile_image']),
      city: _parseString(json['target_provider_city']),
      cityDisplay: _parseString(json['target_provider_city_display']),
      redirectUrl: _parseString(json['redirect_url']),
      isVerifiedBlue: _parseBool(json['target_provider_is_verified_blue']),
      isVerifiedGreen: _parseBool(json['target_provider_is_verified_green']),
      ratingAvg: _parseDouble(json['target_provider_rating_avg']) ?? 0,
      ratingCount: _parseInt(json['target_provider_rating_count']) ?? 0,
      isOnline: _parseBool(json['target_provider_is_online']),
      excellenceBadges: _parseExcellenceBadges(
        json['target_provider_excellence_badges'],
      ),
    );
  }

  bool get isVerified => isVerifiedBlue || isVerifiedGreen;
  String get locationDisplay => SaudiCities.formatCityDisplay(cityDisplay ?? city);

  String get ratingLabel => ratingAvg > 0 ? ratingAvg.toStringAsFixed(1) : '0.0';

  static String? _parseString(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim());
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().trim());
  }

  static bool _parseBool(dynamic value) {
    if (value is bool) return value;
    final normalized = value?.toString().trim().toLowerCase();
    return normalized == 'true' || normalized == '1';
  }

  static List<ExcellenceBadgeModel> _parseExcellenceBadges(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => ExcellenceBadgeModel.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .toList(growable: false);
  }
}
