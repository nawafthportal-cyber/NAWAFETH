/// نموذج بيانات المستخدم (من /api/accounts/me/)
class UserProfile {
  final int id;
  final String? phone;
  final String? email;
  final String? username;
  final String? firstName;
  final String? lastName;
  final String? profileImage;
  final String? coverImage;
  final String roleState;
  final bool hasProviderProfile;
  final bool isProvider;
  final int followingCount;
  final int likesCount;
  final int favoritesMediaCount;
  final int? providerProfileId;
  final String? providerDisplayName;
  final String? providerCity;
  final int providerFollowersCount;
  final int providerLikesReceivedCount;
  final double? providerRatingAvg;
  final int providerRatingCount;

  UserProfile({
    required this.id,
    this.phone,
    this.email,
    this.username,
    this.firstName,
    this.lastName,
    this.profileImage,
    this.coverImage,
    required this.roleState,
    required this.hasProviderProfile,
    required this.isProvider,
    required this.followingCount,
    required this.likesCount,
    required this.favoritesMediaCount,
    this.providerProfileId,
    this.providerDisplayName,
    this.providerCity,
    required this.providerFollowersCount,
    required this.providerLikesReceivedCount,
    this.providerRatingAvg,
    required this.providerRatingCount,
  });

  /// تحويل من JSON
  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as int,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      username: json['username'] as String?,
      firstName: json['first_name'] as String?,
      lastName: json['last_name'] as String?,
      profileImage: json['profile_image'] as String?,
      coverImage: json['cover_image'] as String?,
      roleState: json['role_state'] as String? ?? 'visitor',
      hasProviderProfile: json['has_provider_profile'] as bool? ?? false,
      isProvider: json['is_provider'] as bool? ?? false,
      followingCount: json['following_count'] as int? ?? 0,
      likesCount: json['likes_count'] as int? ?? 0,
      favoritesMediaCount: json['favorites_media_count'] as int? ?? 0,
      providerProfileId: json['provider_profile_id'] as int?,
      providerDisplayName: json['provider_display_name'] as String?,
      providerCity: json['provider_city'] as String?,
      providerFollowersCount: json['provider_followers_count'] as int? ?? 0,
      providerLikesReceivedCount: json['provider_likes_received_count'] as int? ?? 0,
      providerRatingAvg: _parseDouble(json['provider_rating_avg']),
      providerRatingCount: json['provider_rating_count'] as int? ?? 0,
    );
  }

  /// اسم العرض الكامل
  String get displayName {
    final parts = [firstName, lastName].where((s) => s != null && s.isNotEmpty);
    return parts.isNotEmpty ? parts.join(' ') : (username ?? phone ?? 'مستخدم');
  }

  /// اسم المستخدم مع @
  String get usernameDisplay => username != null && username!.isNotEmpty
      ? (username!.startsWith('@') ? username! : '@$username')
      : '@---';

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
