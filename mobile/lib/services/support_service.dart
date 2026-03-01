/// خدمة الدعم الفني — /api/support/*
library;

import 'dart:io';
import 'package:http/http.dart' as http;
import 'api_client.dart';
import 'upload_optimizer.dart';

class SupportService {
  // ─── فرق الدعم ───

  /// جلب قائمة فرق الدعم المتاحة
  static Future<ApiResponse> fetchTeams() {
    return ApiClient.get('/api/support/teams/');
  }

  // ─── التذاكر ───

  /// إنشاء تذكرة دعم جديدة
  static Future<ApiResponse> createTicket({
    required String ticketType,
    required String description,
    String? reportedKind,
    String? reportedObjectId,
    int? reportedUser,
  }) async {
    final body = <String, dynamic>{
      'ticket_type': ticketType,
      'description': description,
    };
    if (reportedKind != null && reportedKind.isNotEmpty) {
      body['reported_kind'] = reportedKind;
    }
    if (reportedObjectId != null && reportedObjectId.isNotEmpty) {
      body['reported_object_id'] = reportedObjectId;
    }
    if (reportedUser != null) {
      body['reported_user'] = reportedUser;
    }
    return ApiClient.post('/api/support/tickets/create/', body: body);
  }

  /// جلب تذاكري
  static Future<ApiResponse> fetchMyTickets({String? status, String? type}) {
    final params = <String, String>{};
    if (status != null && status.isNotEmpty) params['status'] = status;
    if (type != null && type.isNotEmpty) params['type'] = type;
    final query = params.isNotEmpty
        ? '?${params.entries.map((e) => '${e.key}=${e.value}').join('&')}'
        : '';
    return ApiClient.get('/api/support/tickets/my/$query');
  }

  /// جلب تفاصيل تذكرة
  static Future<ApiResponse> fetchTicketDetail(int ticketId) {
    return ApiClient.get('/api/support/tickets/$ticketId/');
  }

  /// إضافة تعليق على تذكرة
  static Future<ApiResponse> addComment({
    required int ticketId,
    required String text,
  }) async {
    return ApiClient.post(
      '/api/support/tickets/$ticketId/comments/',
      body: {'text': text},
    );
  }

  /// رفع مرفق لتذكرة (multipart)
  static Future<ApiResponse> uploadAttachment({
    required int ticketId,
    required File file,
  }) async {
    final optimized = await UploadOptimizer.optimizeForUpload(file);
    return ApiClient.sendMultipart(
      'POST',
      '/api/support/tickets/$ticketId/attachments/',
      (request) async {
        request.files.add(
          await http.MultipartFile.fromPath('file', optimized.path),
        );
      },
    );
  }
}
