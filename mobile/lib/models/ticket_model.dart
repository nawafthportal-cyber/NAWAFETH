class Ticket {
  final int? serverId;       // API id (null for local-only tickets)
  final String id;            // code (e.g. HD000001)
  final DateTime createdAt;
  final String status;        // API: new|in_progress|returned|closed → display mapped
  final String supportTeam;
  final String ticketType;    // API ticket_type
  final String title;
  final String description;
  final String priority;
  final List<String> attachments;
  final List<TicketReply> replies;
  final DateTime? lastUpdate;

  Ticket({
    this.serverId,
    required this.id,
    required this.createdAt,
    required this.status,
    required this.supportTeam,
    this.ticketType = '',
    required this.title,
    required this.description,
    this.priority = 'normal',
    this.attachments = const [],
    this.replies = const [],
    this.lastUpdate,
  });

  /// Parse from backend API JSON
  factory Ticket.fromJson(Map<String, dynamic> json) {
    final teamObj = json['assigned_team_obj'] as Map<String, dynamic>?;
    final teamName = teamObj?['name_ar'] ?? '';
    final comments = (json['comments'] as List?)
            ?.map((c) => TicketReply.fromJson(c as Map<String, dynamic>))
            .toList() ??
        [];
    final attachments = (json['attachments'] as List?)
            ?.map((item) {
              if (item is String) return item;
              if (item is Map<String, dynamic>) {
                return item['file'] as String? ?? '';
              }
              return '';
            })
            .where((value) => value.trim().isNotEmpty)
            .toList() ??
        [];

    return Ticket(
      serverId: json['id'] as int?,
      id: json['code'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      status: json['status'] as String? ?? 'new',
      supportTeam: teamName,
      ticketType: json['ticket_type'] as String? ?? '',
      title: json['ticket_type'] as String? ?? '',
      description: json['description'] as String? ?? '',
      priority: json['priority'] as String? ?? 'normal',
      attachments: attachments,
      replies: comments,
      lastUpdate: DateTime.tryParse(json['updated_at'] ?? ''),
    );
  }

  /// Map API status to Arabic display label
  String get displayStatus {
    switch (status) {
      case 'new':
        return 'جديد';
      case 'in_progress':
        return 'تحت المعالجة';
      case 'returned':
        return 'مُعاد';
      case 'closed':
        return 'مغلق';
      default:
        return status;
    }
  }

  Ticket copyWith({
    int? serverId,
    String? id,
    DateTime? createdAt,
    String? status,
    String? supportTeam,
    String? ticketType,
    String? title,
    String? description,
    String? priority,
    List<String>? attachments,
    List<TicketReply>? replies,
    DateTime? lastUpdate,
  }) {
    return Ticket(
      serverId: serverId ?? this.serverId,
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      supportTeam: supportTeam ?? this.supportTeam,
      ticketType: ticketType ?? this.ticketType,
      title: title ?? this.title,
      description: description ?? this.description,
      priority: priority ?? this.priority,
      attachments: attachments ?? this.attachments,
      replies: replies ?? this.replies,
      lastUpdate: lastUpdate ?? this.lastUpdate,
    );
  }
}

class TicketReply {
  final String from; // "user" أو "platform"
  final String message;
  final DateTime timestamp;
  final bool isInternal;

  TicketReply({
    required this.from,
    required this.message,
    required this.timestamp,
    this.isInternal = false,
  });

  /// Parse from backend API JSON (SupportComment)
  factory TicketReply.fromJson(Map<String, dynamic> json) {
    return TicketReply(
      from: json['created_by_name'] as String? ?? 'platform',
      message: json['text'] as String? ?? '',
      timestamp: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      isInternal: json['is_internal'] as bool? ?? false,
    );
  }
}
