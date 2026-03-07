/// نموذج الإشعار — يطابق NotificationSerializer
class NotificationModel {
  final int id;
  final String title;
  final String body;
  final String kind;
  final String? url;
  final String audienceMode; // client, provider, shared
  final bool isRead;
  final bool isPinned;
  final bool isFollowUp;
  final bool isUrgent;
  final DateTime createdAt;

  NotificationModel({
    required this.id,
    required this.title,
    required this.body,
    required this.kind,
    this.url,
    required this.audienceMode,
    required this.isRead,
    required this.isPinned,
    required this.isFollowUp,
    required this.isUrgent,
    required this.createdAt,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      kind: json['kind'] as String? ?? 'info',
      url: json['url'] as String?,
      audienceMode: json['audience_mode'] as String? ?? 'shared',
      isRead: json['is_read'] as bool? ?? false,
      isPinned: json['is_pinned'] as bool? ?? false,
      isFollowUp: json['is_follow_up'] as bool? ?? false,
      isUrgent: json['is_urgent'] as bool? ?? false,
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
    );
  }

  NotificationModel copyWith({
    bool? isRead,
    bool? isPinned,
    bool? isFollowUp,
  }) {
    return NotificationModel(
      id: id,
      title: title,
      body: body,
      kind: kind,
      url: url,
      audienceMode: audienceMode,
      isRead: isRead ?? this.isRead,
      isPinned: isPinned ?? this.isPinned,
      isFollowUp: isFollowUp ?? this.isFollowUp,
      isUrgent: isUrgent,
      createdAt: createdAt,
    );
  }
}

/// نموذج تفضيل الإشعار — يطابق NotificationPreferenceSerializer
String _normalizeNotificationTier(dynamic value) {
  final raw = (value ?? '').toString().trim().toLowerCase();
  switch (raw) {
    case 'leading':
    case 'pioneer':
      return 'pioneer';
    case 'pro':
    case 'professional':
      return 'professional';
    case 'extra':
      return 'extra';
    case 'basic':
      return 'basic';
    default:
      return raw.isEmpty ? 'basic' : raw;
  }
}

class NotificationPreference {
  final String key;
  final String title;
  final bool enabled;
  final String tier; // basic, pioneer, professional, extra
  final bool locked;
  final DateTime? updatedAt;

  NotificationPreference({
    required this.key,
    required this.title,
    required this.enabled,
    required this.tier,
    required this.locked,
    this.updatedAt,
  });

  factory NotificationPreference.fromJson(Map<String, dynamic> json) {
    return NotificationPreference(
      key: json['key'] as String? ?? '',
      title: json['title'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
      tier: _normalizeNotificationTier(json['canonical_tier'] ?? json['tier']),
      locked: json['locked'] as bool? ?? false,
      updatedAt: DateTime.tryParse(json['updated_at'] ?? ''),
    );
  }

  NotificationPreference copyWith({bool? enabled}) {
    return NotificationPreference(
      key: key,
      title: title,
      enabled: enabled ?? this.enabled,
      tier: tier,
      locked: locked,
      updatedAt: updatedAt,
    );
  }
}
