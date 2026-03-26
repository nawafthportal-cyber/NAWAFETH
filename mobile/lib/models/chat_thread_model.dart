import 'excellence_badge_model.dart';

/// نموذج محادثة مباشرة من GET /api/messaging/direct/threads/
class ChatThread {
  final int threadId;
  final int peerId;
  final int? peerProviderId;
  final String peerName;
  final String peerFirstName;
  final String peerLastName;
  final String peerUsername;
  final String peerPhone;
  final String peerCity;
  final String peerProfileImage;
  final List<ExcellenceBadgeModel> peerExcellenceBadges;
  final String lastMessage;
  final DateTime lastMessageAt;
  final int unreadCount;

  // حقول حالة محلية (مدمجة من /threads/states/)
  bool isFavorite;
  bool isArchived;
  bool isBlocked;
  String? favoriteLabel;
  String? clientLabel;

  ChatThread({
    required this.threadId,
    required this.peerId,
    this.peerProviderId,
    required this.peerName,
    this.peerFirstName = '',
    this.peerLastName = '',
    this.peerUsername = '',
    required this.peerPhone,
    this.peerCity = '',
    this.peerProfileImage = '',
    this.peerExcellenceBadges = const [],
    required this.lastMessage,
    required this.lastMessageAt,
    required this.unreadCount,
    this.isFavorite = false,
    this.isArchived = false,
    this.isBlocked = false,
    this.favoriteLabel,
    this.clientLabel,
  });

  factory ChatThread.fromJson(Map<String, dynamic> json) {
    return ChatThread(
      threadId: json['thread_id'] as int,
      peerId: json['peer_id'] as int,
      peerProviderId: json['peer_provider_id'] as int?,
      peerName: (json['peer_name'] ?? '') as String,
      peerFirstName: (json['peer_first_name'] ?? '') as String,
      peerLastName: (json['peer_last_name'] ?? '') as String,
      peerUsername: (json['peer_username'] ?? '') as String,
      peerPhone: (json['peer_phone'] ?? '') as String,
      peerCity: (json['peer_city'] ?? json['city'] ?? json['peer_city_name'] ?? '') as String,
      peerProfileImage: (json['peer_profile_image'] ?? '') as String,
      peerExcellenceBadges: _parsePeerExcellence(json['peer_excellence_badges']),
      lastMessage: (json['last_message'] ?? '') as String,
      lastMessageAt: DateTime.tryParse(json['last_message_at'] ?? '') ?? DateTime.now(),
      unreadCount: (json['unread_count'] ?? 0) as int,
    );
  }

  static List<ExcellenceBadgeModel> _parsePeerExcellence(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => ExcellenceBadgeModel.fromJson(Map<String, dynamic>.from(item)))
        .where((item) => item.code.isNotEmpty || item.name.isNotEmpty)
        .toList(growable: false);
  }

  String get peerDisplayName {
    final first = peerFirstName.trim();
    final last = peerLastName.trim();
    final full = ('$first $last').trim();
    if (full.isNotEmpty) return full;
    if (peerName.trim().isNotEmpty) return peerName.trim();
    final username = peerUsername.trim();
    if (username.isNotEmpty) return username;
    return peerPhone.trim();
  }
}

/// نموذج حالة المحادثة من GET /api/messaging/threads/states/
class ThreadState {
  final int threadId;
  final bool isFavorite;
  final String favoriteLabel;
  final String clientLabel;
  final bool isArchived;
  final bool isBlocked;

  ThreadState({
    required this.threadId,
    required this.isFavorite,
    required this.favoriteLabel,
    required this.clientLabel,
    required this.isArchived,
    required this.isBlocked,
  });

  factory ThreadState.fromJson(Map<String, dynamic> json) {
    return ThreadState(
      threadId: json['thread'] as int,
      isFavorite: json['is_favorite'] == true,
      favoriteLabel: (json['favorite_label'] ?? '') as String,
      clientLabel: (json['client_label'] ?? '') as String,
      isArchived: json['is_archived'] == true,
      isBlocked: json['is_blocked'] == true,
    );
  }
}
