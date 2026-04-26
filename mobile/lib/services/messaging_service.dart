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
import 'local_cache_service.dart';
import 'upload_optimizer.dart';

class MessagingService {
  static const Duration _threadsCacheTtl = Duration(minutes: 8);
  static const int maxMessageLength = 2000;
  static final Map<String, _ThreadsCacheEntry> _threadsCache =
      <String, _ThreadsCacheEntry>{};

  // ──────────────────────────────────────────
  //  قائمة المحادثات  +  الحالات
  // ──────────────────────────────────────────

  /// جلب قائمة المحادثات المباشرة مع دمج الحالات (مفضلة/محظور)
  static Future<List<ChatThread>> fetchThreads({String? mode}) async {
    final result = await fetchThreadsResult(mode: mode);
    return result.data;
  }

  static Future<CachedChatThreadsResult> fetchThreadsResult({
    String? mode,
    bool forceRefresh = false,
  }) async {
    final scope = _cacheScope(mode);
    final cacheKey = 'messaging_threads_cache_$scope';
    final memoryCache = _threadsCache[scope];
    if (!forceRefresh &&
        memoryCache != null &&
        memoryCache.isFresh(_threadsCacheTtl)) {
      return memoryCache.toResult(source: 'memory_cache');
    }

    final diskCache = !forceRefresh ? await _readThreadsDiskCache(cacheKey) : null;
    if (!forceRefresh && diskCache != null && diskCache.isFresh(_threadsCacheTtl)) {
      _threadsCache[scope] = _ThreadsCacheEntry(
        diskCache.data,
        diskCache.cachedAt ?? DateTime.now(),
      );
      return diskCache.copyWith(source: 'disk_cache');
    }

    final threadsRes = await ApiClient.get(_threadsPath(mode));
    if (threadsRes.isSuccess && threadsRes.dataAsList != null) {
      final threads = threadsRes.dataAsList!
          .map((e) => ChatThread.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
      await _mergeThreadStates(threads, mode: mode);
      final result = CachedChatThreadsResult(
        data: threads,
        source: 'network',
      );
      final fetchedAt = DateTime.now();
      _threadsCache[scope] = _ThreadsCacheEntry(threads, fetchedAt);
      await _writeThreadsDiskCache(cacheKey, threads);
      return result.copyWith(cachedAt: fetchedAt);
    }

    final errorMessage = threadsRes.error ?? 'تعذر تحميل المحادثات الآن';
    if (memoryCache != null) {
      return memoryCache.toResult(
        source: 'memory_cache_stale',
        errorMessage: errorMessage,
        statusCode: threadsRes.statusCode,
        dataOverride: _sanitizeCachedThreads(memoryCache.data),
      );
    }
    if (diskCache != null) {
      _threadsCache[scope] = _ThreadsCacheEntry(
        diskCache.data,
        diskCache.cachedAt ?? DateTime.now(),
      );
      return diskCache.copyWith(
        source: 'disk_cache_stale',
        errorMessage: errorMessage,
        statusCode: threadsRes.statusCode,
      );
    }
    return CachedChatThreadsResult(
      data: const <ChatThread>[],
      source: 'empty',
      errorMessage: errorMessage,
      statusCode: threadsRes.statusCode,
    );
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
    final result = await fetchMessagesResult(
      threadId,
      limit: limit,
      offset: offset,
    );
    return result.page;
  }

  static Future<MessagesFetchResult> fetchMessagesResult(
    int threadId, {
    int limit = 30,
    int offset = 0,
  }) async {
    final res = await ApiClient.get(
      '/api/messaging/direct/thread/$threadId/messages/?limit=$limit&offset=$offset',
    );

    if (!res.isSuccess || res.dataAsMap == null) {
      return MessagesFetchResult(
        page: MessagesPage(
          messages: const <ChatMessage>[],
          hasMore: false,
          totalCount: 0,
        ),
        errorMessage: res.error ?? 'تعذر تحميل الرسائل الآن',
        statusCode: res.statusCode,
      );
    }

    final data = res.dataAsMap!;
    final results = (data['results'] as List<dynamic>?)
            ?.map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
            .toList(growable: false) ??
        const <ChatMessage>[];

    return MessagesFetchResult(
      page: MessagesPage(
        messages: results,
        hasMore: data['next'] != null,
        totalCount: data['count'] as int? ?? results.length,
      ),
      statusCode: res.statusCode,
    );
  }

  static Future<ThreadState?> fetchThreadState(int threadId) async {
    final res = await ApiClient.get('/api/messaging/thread/$threadId/state/');
    if (!res.isSuccess || res.dataAsMap == null) {
      return null;
    }
    return ThreadState.fromJson(res.dataAsMap!);
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

  static Future<int?> getOrCreateDirectThreadForRequest(int requestId) async {
    final res = await ApiClient.post(
      '/api/messaging/direct/thread/',
      body: {'request_id': requestId},
    );
    return res.dataAsMap?['id'] as int?;
  }

  static void debugResetCaches() {
    _threadsCache.clear();
  }

  static String _cacheScope(String? mode) {
    final normalized = (mode ?? '').trim().toLowerCase();
    return normalized.isEmpty ? 'shared' : normalized;
  }

  static String _threadsPath(String? mode) {
    final normalized = (mode ?? '').trim();
    return normalized.isNotEmpty
        ? '/api/messaging/direct/threads/?mode=$normalized'
        : '/api/messaging/direct/threads/';
  }

  static String _statesPath(String? mode) {
    final normalized = (mode ?? '').trim();
    return normalized.isNotEmpty
        ? '/api/messaging/threads/states/?mode=$normalized'
        : '/api/messaging/threads/states/';
  }

  static Future<void> _mergeThreadStates(
    List<ChatThread> threads, {
    String? mode,
  }) async {
    final statesRes = await ApiClient.get(_statesPath(mode));
    if (!statesRes.isSuccess || statesRes.dataAsList == null) {
      return;
    }
    final statesMap = <int, ThreadState>{};
    for (final stateJson in statesRes.dataAsList!) {
      final state = ThreadState.fromJson(stateJson as Map<String, dynamic>);
      statesMap[state.threadId] = state;
    }
    for (final thread in threads) {
      final state = statesMap[thread.threadId];
      if (state == null) {
        continue;
      }
      thread.isFavorite = state.isFavorite;
      thread.isArchived = state.isArchived;
      thread.isBlocked = state.isBlocked;
      thread.favoriteLabel = state.favoriteLabel;
      thread.clientLabel = state.clientLabel;
    }
  }

  static Future<void> _writeThreadsDiskCache(
    String cacheKey,
    List<ChatThread> threads,
  ) {
    return LocalCacheService.writeJson(cacheKey, {
      'threads': threads
          .take(40)
          .map(
            (thread) => thread.toJson(
              lastMessageOverride: _safeCachedPreview(thread.lastMessage),
            ),
          )
          .toList(growable: false),
    });
  }

  static Future<CachedChatThreadsResult?> _readThreadsDiskCache(
    String cacheKey,
  ) async {
    final envelope = await LocalCacheService.readJson(cacheKey);
    final payload = envelope?.payload;
    if (payload is! Map) {
      return null;
    }
    final map = Map<String, dynamic>.from(payload);
    final rows = (map['threads'] as List? ?? const <dynamic>[])
        .whereType<Map>()
        .map((row) => ChatThread.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
    return CachedChatThreadsResult(
      data: rows,
      source: 'disk_cache',
      cachedAt: envelope?.cachedAt,
    );
  }

  static String _safeCachedPreview(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    if (trimmed.contains('service-request') || trimmed.contains('/requests/')) {
      return 'طلب خدمة مباشر';
    }
    if (trimmed.contains('http://') || trimmed.contains('https://')) {
      return 'رابط تمت مشاركته';
    }
    return 'رسالة حديثة';
  }

  static List<ChatThread> _sanitizeCachedThreads(List<ChatThread> threads) {
    return threads
        .map(
          (thread) => ChatThread.fromJson(
            thread.toJson(
              lastMessageOverride: _safeCachedPreview(thread.lastMessage),
            ),
          ),
        )
        .toList(growable: false);
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

class MessagesFetchResult {
  final MessagesPage page;
  final String? errorMessage;
  final int statusCode;

  const MessagesFetchResult({
    required this.page,
    this.errorMessage,
    this.statusCode = 200,
  });

  bool get hasError => (errorMessage ?? '').trim().isNotEmpty;
}

class CachedChatThreadsResult {
  final List<ChatThread> data;
  final String source;
  final String? errorMessage;
  final int statusCode;
  final DateTime? cachedAt;

  const CachedChatThreadsResult({
    required this.data,
    required this.source,
    this.errorMessage,
    this.statusCode = 200,
    this.cachedAt,
  });

  bool get fromCache => source.contains('cache');
  bool get isStaleCache => source.endsWith('_stale');
  bool get isOfflineFallback => isStaleCache && statusCode == 0;
  bool get hasError => (errorMessage ?? '').trim().isNotEmpty;

  bool isFresh(Duration ttl) {
    final value = cachedAt;
    if (value == null) {
      return false;
    }
    return DateTime.now().difference(value) <= ttl;
  }

  CachedChatThreadsResult copyWith({
    List<ChatThread>? data,
    String? source,
    String? errorMessage,
    int? statusCode,
    DateTime? cachedAt,
  }) {
    return CachedChatThreadsResult(
      data: data ?? List<ChatThread>.from(this.data),
      source: source ?? this.source,
      errorMessage: errorMessage ?? this.errorMessage,
      statusCode: statusCode ?? this.statusCode,
      cachedAt: cachedAt ?? this.cachedAt,
    );
  }
}

class _ThreadsCacheEntry {
  final List<ChatThread> data;
  final DateTime fetchedAt;

  const _ThreadsCacheEntry(this.data, this.fetchedAt);

  bool isFresh(Duration ttl) {
    return DateTime.now().difference(fetchedAt) <= ttl;
  }

  CachedChatThreadsResult toResult({
    required String source,
    String? errorMessage,
    int statusCode = 200,
    List<ChatThread>? dataOverride,
  }) {
    return CachedChatThreadsResult(
      data: dataOverride ?? List<ChatThread>.from(data),
      source: source,
      errorMessage: errorMessage,
      statusCode: statusCode,
      cachedAt: fetchedAt,
    );
  }
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
