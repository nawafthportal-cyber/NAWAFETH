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

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'kind': kind,
      'url': url,
      'audience_mode': audienceMode,
      'is_read': isRead,
      'is_pinned': isPinned,
      'is_follow_up': isFollowUp,
      'is_urgent': isUrgent,
      'created_at': createdAt.toIso8601String(),
    };
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
  final String lockedReason;
  final DateTime? updatedAt;

  NotificationPreference({
    required this.key,
    required this.title,
    required this.enabled,
    required this.tier,
    required this.locked,
    required this.lockedReason,
    this.updatedAt,
  });

  factory NotificationPreference.fromJson(Map<String, dynamic> json) {
    return NotificationPreference(
      key: json['key'] as String? ?? '',
      title: json['title'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
      tier: _normalizeNotificationTier(json['canonical_tier'] ?? json['tier']),
      locked: json['locked'] as bool? ?? false,
      lockedReason: json['locked_reason'] as String? ?? '',
      updatedAt: DateTime.tryParse(json['updated_at'] ?? ''),
    );
  }

  NotificationPreference copyWith({bool? enabled, bool? locked, String? lockedReason}) {
    return NotificationPreference(
      key: key,
      title: title,
      enabled: enabled ?? this.enabled,
      tier: tier,
      locked: locked ?? this.locked,
      lockedReason: lockedReason ?? this.lockedReason,
      updatedAt: updatedAt,
    );
  }
}

class NotificationPreferenceSection {
  final String key;
  final String title;
  final String description;
  final int sortOrder;
  final String noteTitle;
  final String noteBody;

  NotificationPreferenceSection({
    required this.key,
    required this.title,
    required this.description,
    required this.sortOrder,
    required this.noteTitle,
    required this.noteBody,
  });

  factory NotificationPreferenceSection.fromJson(Map<String, dynamic> json) {
    return NotificationPreferenceSection(
      key: json['key'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      sortOrder: json['sort_order'] as int? ?? 999,
      noteTitle: json['note_title'] as String? ?? '',
      noteBody: json['note_body'] as String? ?? '',
    );
  }
}

class NotificationPreferencesPayload {
  final List<NotificationPreference> preferences;
  final List<NotificationPreferenceSection> sections;

  NotificationPreferencesPayload({
    required this.preferences,
    required this.sections,
  });
}
