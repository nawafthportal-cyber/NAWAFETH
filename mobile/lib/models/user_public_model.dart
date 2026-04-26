/// نموذج بيانات المستخدم العام — يطابق UserPublicSerializer
///
/// يُستخدم في:
/// - قائمة "متابعيني" (التفاعلي - مزود الخدمة)
/// - أي قائمة عامة للمستخدمين
class UserPublicModel {
  final int id;
  final String username;
  final String displayName;
  final int? providerId;
  final String? profileImage;
  final String? followRoleContext;

  UserPublicModel({
    required this.id,
    required this.username,
    required this.displayName,
    this.providerId,
    this.profileImage,
    this.followRoleContext,
  });

  factory UserPublicModel.fromJson(Map<String, dynamic> json) {
    return UserPublicModel(
      id: json['id'] as int? ?? 0,
      username: json['username'] as String? ?? '',
      displayName: json['display_name'] as String? ?? 'مستخدم',
      providerId: json['provider_id'] as int?,
      profileImage:
          (json['profile_image'] as String?) ?? (json['avatar'] as String?),
      followRoleContext: json['follow_role_context'] as String?,
    );
  }

  /// اسم المستخدم بصيغة @username
  String get usernameDisplay => '@$username';

  /// هل المستخدم لديه ملف مزود خدمة
  bool get hasProviderProfile => providerId != null;

  String get followerBadgeLabel {
    switch (followRoleContext) {
      case 'provider':
        return 'مزود خدمة';
      case 'client':
        return 'عميل';
      default:
        return hasProviderProfile ? 'مزود خدمة' : 'مستخدم';
    }
  }
}
