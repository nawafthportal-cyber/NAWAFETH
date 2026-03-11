/// خدمة الرسائل — تربط شاشات المحادثة بالـ Backend API
///
/// الـ Endpoints المستخدمة:
/// - GET  /api/messaging/direct/threads/          — قائمة المحادثات
/// - GET  /api/messaging/threads/states/           — حالات المحادثات (مفضلة/محظور/مؤرشف)
/// - POST /api/messaging/direct/thread/            — إنشاء/جلب محادثة مباشرة
/// - GET  /api/messaging/direct/thread/{id}/messages/ — رسائل المحادثة (paginated)
/// - POST /api/messaging/direct/thread/{id}/messages/send/ — إرسال رسالة (نص/مرفق)
/// - POST /api/messaging/direct/thread/{id}/messages/read/ — تمييز كمقروءة
/// - POST /api/messaging/thread/{id}/favorite/     — تبديل المفضلة
/// - POST /api/messaging/thread/{id}/block/        — حظر/إلغاء حظر
/// - POST /api/messaging/thread/{id}/archive/      — أرشفة/إلغاء
/// - POST /api/messaging/thread/{id}/report/       — إبلاغ
/// - POST /api/messaging/thread/{id}/unread/       — تمييز كغير مقروءة
/// - POST /api/messaging/thread/{id}/messages/{mid}/delete/ — حذف رسالة
/// - POST /api/messaging/thread/{id}/favorite-label/ — تصنيف المفضلة
/// - POST /api/messaging/thread/{id}/client-label/   — تصنيف العميل
library;

import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/chat_thread_model.dart';
import '../models/chat_message_model.dart';
import 'api_client.dart';
import 'upload_optimizer.dart';

class MessagingService {
  // ──────────────────────────────────────────
  //  قائمة المحادثات  +  الحالات
  // ──────────────────────────────────────────

  /// جلب قائمة المحادثات المباشرة مع دمج الحالات (مفضلة/محظور)
  static Future<List<ChatThread>> fetchThreads({String? mode}) async {
    // 1) جلب المحادثات
    final threadPath = mode != null
        ? '/api/messaging/direct/threads/?mode=$mode'
        : '/api/messaging/direct/threads/';
    final threadsRes = await ApiClient.get(threadPath);

    if (!threadsRes.isSuccess || threadsRes.dataAsList == null) {
      return [];
    }

    final threads = threadsRes.dataAsList!
        .map((e) => ChatThread.fromJson(e as Map<String, dynamic>))
        .toList();

    // 2) جلب حالات المحادثات ودمجها
    final statesPath = mode != null
        ? '/api/messaging/threads/states/?mode=$mode'
        : '/api/messaging/threads/states/';
    final statesRes = await ApiClient.get(statesPath);

    if (statesRes.isSuccess && statesRes.dataAsList != null) {
      final statesMap = <int, ThreadState>{};
      for (final s in statesRes.dataAsList!) {
        final state = ThreadState.fromJson(s as Map<String, dynamic>);
        statesMap[state.threadId] = state;
      }
      for (final t in threads) {
        final st = statesMap[t.threadId];
        if (st != null) {
          t.isFavorite = st.isFavorite;
          t.isArchived = st.isArchived;
          t.isBlocked = st.isBlocked;
          t.favoriteLabel = st.favoriteLabel;
          t.clientLabel = st.clientLabel;
        }
      }
    }

    return threads;
  }

  /// جلب إجمالي الرسائل غير المقروءة للمحادثات المباشرة
  static Future<int> fetchUnreadCount({String? mode}) async {
    final normalizedMode = (mode ?? '').trim();
    final path = normalizedMode.isNotEmpty
        ? '/api/core/unread-badges/?mode=$normalizedMode'
        : '/api/core/unread-badges/';
    final res = await ApiClient.get(path);
    if (!res.isSuccess) return 0;
    final data = res.dataAsMap ?? {};
    return data['chats'] as int? ?? 0;
  }

  // ──────────────────────────────────────────
  //  رسائل المحادثة
  // ──────────────────────────────────────────

  /// جلب رسائل محادثة مباشرة (paginated — limit/offset)
  static Future<MessagesPage> fetchMessages(
    int threadId, {
    int limit = 30,
    int offset = 0,
  }) async {
    final res = await ApiClient.get(
      '/api/messaging/direct/thread/$threadId/messages/?limit=$limit&offset=$offset',
    );

    if (!res.isSuccess || res.dataAsMap == null) {
      return MessagesPage(messages: [], hasMore: false, totalCount: 0);
    }

    final data = res.dataAsMap!;
    final results = (data['results'] as List<dynamic>?)
            ?.map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    return MessagesPage(
      messages: results,
      hasMore: data['next'] != null,
      totalCount: data['count'] as int? ?? results.length,
    );
  }

  // ──────────────────────────────────────────
  //  إرسال رسالة
  // ──────────────────────────────────────────

  /// إرسال رسالة نصية
  static Future<SendResult> sendTextMessage(int threadId, String body) async {
    final res = await ApiClient.post(
      '/api/messaging/direct/thread/$threadId/messages/send/',
      body: {'body': body},
    );

    return SendResult(
      success: res.isSuccess,
      messageId: res.dataAsMap?['message_id'] as int?,
      error: res.error,
    );
  }

  /// إرسال رسالة مع مرفق (صورة/ملف/صوت)
  static Future<SendResult> sendAttachment(
    int threadId, {
    String? body,
    required File file,
    required String attachmentType, // audio | image | file
  }) async {
    final optimized = await UploadOptimizer.optimizeForUpload(
      file,
      declaredType: attachmentType,
    );

    final res = await ApiClient.sendMultipart(
      'POST',
      '/api/messaging/direct/thread/$threadId/messages/send/',
      (request) async {
        if (body != null && body.trim().isNotEmpty) {
          request.fields['body'] = body.trim();
        }
        request.fields['attachment_type'] = attachmentType;
        request.files.add(
          await http.MultipartFile.fromPath('attachment', optimized.path),
        );
      },
      timeout: const Duration(seconds: 60),
    );

    if (res.isSuccess) {
      return SendResult(
        success: true,
        messageId: res.dataAsMap?['message_id'] as int?,
      );
    }
    return SendResult(success: false, error: res.error ?? 'فشل إرسال المرفق');
  }

  // ──────────────────────────────────────────
  //  تمييز كمقروءة / غير مقروءة
  // ──────────────────────────────────────────

  /// تمييز جميع رسائل المحادثة كمقروءة
  static Future<bool> markRead(int threadId) async {
    final res = await ApiClient.post(
      '/api/messaging/direct/thread/$threadId/messages/read/',
    );
    return res.isSuccess;
  }

  /// تمييز المحادثة كغير مقروءة
  static Future<bool> markUnread(int threadId) async {
    final res = await ApiClient.post(
      '/api/messaging/thread/$threadId/unread/',
    );
    return res.isSuccess;
  }

  // ──────────────────────────────────────────
  //  المفضلة / الحظر / الأرشفة
  // ──────────────────────────────────────────

  /// تبديل حالة المفضلة
  static Future<bool> toggleFavorite(int threadId, {bool remove = false}) async {
    final res = await ApiClient.post(
      '/api/messaging/thread/$threadId/favorite/',
      body: remove ? {'action': 'remove'} : {},
    );
    return res.isSuccess;
  }

  /// حظر / إلغاء حظر
  static Future<bool> toggleBlock(int threadId, {bool remove = false}) async {
    final res = await ApiClient.post(
      '/api/messaging/thread/$threadId/block/',
      body: remove ? {'action': 'remove'} : {},
    );
    return res.isSuccess;
  }

  /// أرشفة / إلغاء أرشفة
  static Future<bool> toggleArchive(int threadId, {bool remove = false}) async {
    final res = await ApiClient.post(
      '/api/messaging/thread/$threadId/archive/',
      body: remove ? {'action': 'remove'} : {},
    );
    return res.isSuccess;
  }

  // ──────────────────────────────────────────
  //  الإبلاغ
  // ──────────────────────────────────────────

  /// إبلاغ عن محادثة — ينشئ تذكرة دعم في الباكند
  static Future<ReportResult> report(
    int threadId, {
    required String reason,
    String? details,
  }) async {
    final res = await ApiClient.post(
      '/api/messaging/thread/$threadId/report/',
      body: {
        'reason': reason,
        if (details != null && details.isNotEmpty) 'details': details,
      },
    );

    if (res.isSuccess) {
      return ReportResult(
        success: true,
        ticketId: res.dataAsMap?['ticket_id'] as int?,
        ticketCode: res.dataAsMap?['ticket_code'] as String?,
      );
    }
    return ReportResult(success: false, error: res.error);
  }

  // ──────────────────────────────────────────
  //  حذف رسالة
  // ──────────────────────────────────────────

  /// حذف رسالة (المرسل فقط)
  static Future<bool> deleteMessage(int threadId, int messageId) async {
    final res = await ApiClient.post(
      '/api/messaging/thread/$threadId/messages/$messageId/delete/',
    );
    return res.isSuccess;
  }

  // ──────────────────────────────────────────
  //  إنشاء/جلب محادثة مباشرة
  // ──────────────────────────────────────────

  /// إنشاء أو جلب محادثة مباشرة مع مقدم خدمة
  static Future<int?> getOrCreateDirectThread(int providerId) async {
    final res = await ApiClient.post(
      '/api/messaging/direct/thread/',
      body: {'provider_id': providerId},
    );
    return res.dataAsMap?['id'] as int?;
  }
}

// ──────────────────────────────────────────
//  نماذج النتائج
// ──────────────────────────────────────────

class MessagesPage {
  final List<ChatMessage> messages;
  final bool hasMore;
  final int totalCount;

  MessagesPage({
    required this.messages,
    required this.hasMore,
    required this.totalCount,
  });
}

class SendResult {
  final bool success;
  final int? messageId;
  final String? error;

  SendResult({required this.success, this.messageId, this.error});
}

class ReportResult {
  final bool success;
  final int? ticketId;
  final String? ticketCode;
  final String? error;

  ReportResult({required this.success, this.ticketId, this.ticketCode, this.error});
}
