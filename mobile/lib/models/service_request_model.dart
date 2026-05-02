/// نماذج طلبات الخدمة (الطلبات / Orders)
/// تُمثّل بيانات API من /api/marketplace/
library;

import '../constants/saudi_cities.dart';

// ─── مرفق الطلب ───
class RequestAttachment {
  final int id;
  final String fileType; // image, video, audio, document
  final String fileUrl;
  final DateTime? createdAt;

  const RequestAttachment({
    required this.id,
    required this.fileType,
    required this.fileUrl,
    this.createdAt,
  });

  factory RequestAttachment.fromJson(Map<String, dynamic> json) {
    return RequestAttachment(
      id: json['id'] as int,
      fileType: (json['file_type'] ?? '') as String,
      fileUrl: (json['file_url'] ?? '') as String,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
    );
  }
}

// ─── سجل تغيير الحالة ───
class StatusLog {
  final int id;
  final String fromStatus;
  final String toStatus;
  final String? note;
  final DateTime? createdAt;
  final String? actorName;

  const StatusLog({
    required this.id,
    required this.fromStatus,
    required this.toStatus,
    this.note,
    this.createdAt,
    this.actorName,
  });

  factory StatusLog.fromJson(Map<String, dynamic> json) {
    return StatusLog(
      id: json['id'] as int,
      fromStatus: (json['from_status'] ?? '') as String,
      toStatus: (json['to_status'] ?? '') as String,
      note: json['note'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      actorName: json['actor_name'] as String?,
    );
  }
}

// ─── عرض سعر (للطلبات التنافسية) ───
class Offer {
  final int id;
  final int provider;
  final String providerName;
  final String price;
  final int durationDays;
  final String? note;
  final String status; // pending, selected, rejected
  final DateTime? createdAt;

  const Offer({
    required this.id,
    required this.provider,
    required this.providerName,
    required this.price,
    required this.durationDays,
    this.note,
    required this.status,
    this.createdAt,
  });

  factory Offer.fromJson(Map<String, dynamic> json) {
    return Offer(
      id: json['id'] as int,
      provider: json['provider'] as int,
      providerName: (json['provider_name'] ?? '') as String,
      price: (json['price'] ?? '0') as String,
      durationDays: (json['duration_days'] ?? 0) as int,
      note: json['note'] as String?,
      status: (json['status'] ?? 'pending') as String,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
    );
  }
}

// ─── طلب الخدمة (الموديل الموحّد) ───
class ServiceRequest {
  final int id;
  final int? clientId;
  final String title;
  final String description;
  final String requestType; // normal, competitive, urgent
  final String status; // new, in_progress, completed, cancelled
  final String statusGroup;
  final String statusLabel; // Arabic text
  final String? city;
  final String? cityDisplay;
  final DateTime createdAt;

  // مقدم الخدمة
  final int? provider;
  final String? providerName;
  final String? providerPhone;

  // مواعيد
  final String? quoteDeadline;
  final DateTime? expectedDeliveryAt;
  final DateTime? deliveredAt;
  final DateTime? canceledAt;

  // مالية
  final String? estimatedServiceAmount;
  final String? receivedAmount;
  final String? remainingAmount;
  final String? actualServiceAmount;

  // سبب الإلغاء
  final String? cancelReason;

  // مدخلات المزود
  final bool? providerInputsApproved;
  final DateTime? providerInputsDecidedAt;
  final String? providerInputsDecisionNote;

  // التقييم
  final int? reviewId;
  final double? reviewRating;
  final double? reviewResponseSpeed;
  final double? reviewCostValue;
  final double? reviewQuality;
  final double? reviewCredibility;
  final double? reviewOnTime;
  final String? reviewComment;

  // التصنيف
  final int? subcategory;
  final String? subcategoryName;
  final String? categoryName;

  // بيانات العميل
  final String? clientName;
  final String? clientPhone;
  final String? clientCity;
  final String? clientCityDisplay;
  final List<String> availableActions;
  final String? providerInputsStage;

  // بيانات التفاصيل (تأتي فقط في endpoint التفاصيل)
  final List<RequestAttachment> attachments;
  final List<StatusLog> statusLogs;

  const ServiceRequest({
    required this.id,
    this.clientId,
    required this.title,
    required this.description,
    required this.requestType,
    required this.status,
    required this.statusGroup,
    required this.statusLabel,
    this.city,
    this.cityDisplay,
    required this.createdAt,
    this.provider,
    this.providerName,
    this.providerPhone,
    this.quoteDeadline,
    this.expectedDeliveryAt,
    this.deliveredAt,
    this.canceledAt,
    this.estimatedServiceAmount,
    this.receivedAmount,
    this.remainingAmount,
    this.actualServiceAmount,
    this.cancelReason,
    this.providerInputsApproved,
    this.providerInputsDecidedAt,
    this.providerInputsDecisionNote,
    this.reviewId,
    this.reviewRating,
    this.reviewResponseSpeed,
    this.reviewCostValue,
    this.reviewQuality,
    this.reviewCredibility,
    this.reviewOnTime,
    this.reviewComment,
    this.subcategory,
    this.subcategoryName,
    this.categoryName,
    this.clientName,
    this.clientPhone,
    this.clientCity,
    this.clientCityDisplay,
    this.availableActions = const [],
    this.providerInputsStage,
    this.attachments = const [],
    this.statusLogs = const [],
  });

  /// رقم الطلب للعرض: R000001
  String get displayId => 'R${id.toString().padLeft(6, '0')}';

  /// نوع الطلب بالعربي
  String get requestTypeLabel {
    switch (requestType) {
      case 'normal':
        return 'عادي';
      case 'competitive':
        return 'تنافسي';
      case 'urgent':
        return 'عاجل';
      default:
        return requestType;
    }
  }

  /// تحويل المبلغ من نص إلى رقم
  double? get estimatedAmount => _parseAmount(estimatedServiceAmount);
  double? get receivedAmt => _parseAmount(receivedAmount);
  double? get remainingAmt => _parseAmount(remainingAmount);
  double? get actualAmount => _parseAmount(actualServiceAmount);
  String get locationDisplay => SaudiCities.formatCityDisplay(cityDisplay ?? city);
  String get clientLocationDisplay =>
      SaudiCities.formatCityDisplay(clientCityDisplay ?? clientCity);
  bool hasAction(String action) => availableActions.contains(action.trim());

  static double? _parseAmount(String? s) {
    if (s == null || s.isEmpty) return null;
    return double.tryParse(s);
  }

  factory ServiceRequest.fromJson(Map<String, dynamic> json) {
    return ServiceRequest(
      id: json['id'] as int,
      clientId: json['client_id'] as int?,
      title: (json['title'] ?? '') as String,
      description: (json['description'] ?? '') as String,
      requestType: (json['request_type'] ?? 'normal') as String,
      status: (json['status'] ?? 'new') as String,
      statusGroup: (json['status_group'] ?? json['status'] ?? 'new') as String,
      statusLabel: (json['status_label'] ?? '') as String,
      city: json['city'] as String?,
      cityDisplay: json['city_display'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      provider: json['provider'] as int?,
      providerName: json['provider_name'] as String?,
      providerPhone: json['provider_phone'] as String?,
      quoteDeadline: json['quote_deadline'] as String?,
      expectedDeliveryAt: json['expected_delivery_at'] != null
          ? DateTime.tryParse(json['expected_delivery_at'] as String)
          : null,
      deliveredAt: json['delivered_at'] != null
          ? DateTime.tryParse(json['delivered_at'] as String)
          : null,
      canceledAt: json['canceled_at'] != null
          ? DateTime.tryParse(json['canceled_at'] as String)
          : null,
      estimatedServiceAmount: json['estimated_service_amount']?.toString(),
      receivedAmount: json['received_amount']?.toString(),
      remainingAmount: json['remaining_amount']?.toString(),
      actualServiceAmount: json['actual_service_amount']?.toString(),
      cancelReason: json['cancel_reason'] as String?,
      providerInputsApproved: json['provider_inputs_approved'] as bool?,
      providerInputsDecidedAt: json['provider_inputs_decided_at'] != null
          ? DateTime.tryParse(json['provider_inputs_decided_at'] as String)
          : null,
      providerInputsDecisionNote:
          json['provider_inputs_decision_note'] as String?,
      reviewId: json['review_id'] as int?,
      reviewRating: (json['review_rating'] as num?)?.toDouble(),
      reviewResponseSpeed: (json['review_response_speed'] as num?)?.toDouble(),
      reviewCostValue: (json['review_cost_value'] as num?)?.toDouble(),
      reviewQuality: (json['review_quality'] as num?)?.toDouble(),
      reviewCredibility: (json['review_credibility'] as num?)?.toDouble(),
      reviewOnTime: (json['review_on_time'] as num?)?.toDouble(),
      reviewComment: json['review_comment'] as String?,
      subcategory: json['subcategory'] as int?,
      subcategoryName: json['subcategory_name'] as String?,
      categoryName: json['category_name'] as String?,
      clientName: json['client_name'] as String?,
      clientPhone: json['client_phone'] as String?,
        clientCity: json['client_city'] as String?,
        clientCityDisplay: json['client_city_display'] as String?,
      availableActions: json['available_actions'] is List
          ? (json['available_actions'] as List)
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false)
          : const [],
      providerInputsStage: json['provider_inputs_stage'] as String?,
      attachments: json['attachments'] is List
          ? (json['attachments'] as List)
              .map((a) =>
                  RequestAttachment.fromJson(a as Map<String, dynamic>))
              .toList()
          : const [],
      statusLogs: json['status_logs'] is List
          ? (json['status_logs'] as List)
              .map((s) => StatusLog.fromJson(s as Map<String, dynamic>))
              .toList()
          : const [],
    );
  }
}
