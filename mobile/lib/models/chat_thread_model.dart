/// نموذج محادثة مباشرة من GET /api/messaging/direct/threads/
class ChatThread {
  final int threadId;
  final int peerId;
  final int? peerProviderId;
  final String peerName;
  final String peerPhone;
  final String peerCity;
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
    required this.peerPhone,
    this.peerCity = '',
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
      peerPhone: (json['peer_phone'] ?? '') as String,
      peerCity: (json['peer_city'] ?? json['city'] ?? json['peer_city_name'] ?? '') as String,
      lastMessage: (json['last_message'] ?? '') as String,
      lastMessageAt: DateTime.tryParse(json['last_message_at'] ?? '') ?? DateTime.now(),
      unreadCount: (json['unread_count'] ?? 0) as int,
    );
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
