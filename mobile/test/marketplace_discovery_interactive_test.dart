import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nawafeth/services/account_mode_service.dart';
import 'package:nawafeth/services/api_client.dart';
import 'package:nawafeth/services/auth_service.dart';
import 'package:nawafeth/services/interactive_service.dart';
import 'package:nawafeth/services/local_cache_service.dart';
import 'package:nawafeth/services/marketplace_service.dart';
import 'package:nawafeth/services/messaging_service.dart';
import 'package:nawafeth/services/notification_service.dart';
import 'package:nawafeth/services/providers_api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secureStore = <String, String>{};

  setUp(() async {
    secureStore.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
      final arguments = (call.arguments as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final key = arguments['key']?.toString();
      switch (call.method) {
        case 'read':
          return key == null ? null : secureStore[key];
        case 'write':
          if (key != null) {
            secureStore[key] = arguments['value']?.toString() ?? '';
          }
          return null;
        case 'delete':
          if (key != null) {
            secureStore.remove(key);
          }
          return null;
        case 'deleteAll':
          secureStore.clear();
          return null;
        case 'containsKey':
          return key != null && secureStore.containsKey(key);
        default:
          return null;
      }
    });

    SharedPreferences.setMockInitialValues({});
    LocalCacheService.debugReset();
    await LocalCacheService.init();
    await AccountModeService.setProviderMode(false);
    await AuthService.saveUserBasicInfo(userId: 7, roleState: 'client');
    await InteractiveService.debugResetCaches();
    MessagingService.debugResetCaches();
    NotificationService.debugResetCaches();
    await ProvidersApiService.clearSearchCache();
    ApiClient.debugResetHttpClient();
  });

  tearDown(() {
    ApiClient.debugResetHttpClient();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
  });

  test('service request createRequest sends direct request payload', () async {
    ApiClient.debugSetHttpClient(
      _RecordingClient((request) async {
        expect(request, isA<http.MultipartRequest>());
        final multipart = request as http.MultipartRequest;
        expect(multipart.url.path, '/api/marketplace/requests/create/');
        expect(multipart.fields['mode'], 'client');
        expect(multipart.fields['request_type'], 'normal');
        expect(multipart.fields['subcategory'], '14');
        expect(multipart.fields['provider'], '9');
        expect(multipart.fields['city'], 'الرياض');
        return _jsonStreamedResponse({'id': 101}, 201);
      }),
    );

    final response = await MarketplaceService.createRequest(
      title: 'تركيب مكيف',
      description: 'أحتاج تركيبًا هذا الأسبوع',
      requestType: 'normal',
      subcategory: 14,
      provider: 9,
      city: 'الرياض',
    );

    expect(response.isSuccess, isTrue);
    expect(response.dataAsMap?['id'], 101);
  });

  test('urgent request createRequest returns friendly API error', () async {
    ApiClient.debugSetHttpClient(
      _RecordingClient((request) async {
        final multipart = request as http.MultipartRequest;
        expect(multipart.fields['request_type'], 'urgent');
        expect(multipart.fields['dispatch_mode'], 'nearest');
        return _jsonStreamedResponse({'detail': 'اختر المدينة أولاً'}, 422);
      }),
    );

    final response = await MarketplaceService.createRequest(
      title: 'طلب عاجل',
      description: 'أحتاج الخدمة الآن',
      requestType: 'urgent',
      subcategory: 22,
      dispatchMode: 'nearest',
    );

    expect(response.isSuccess, isFalse);
    expect(response.error, 'اختر المدينة أولاً');
  });

  test('request quote createRequest sends deadline payload', () async {
    ApiClient.debugSetHttpClient(
      _RecordingClient((request) async {
        final multipart = request as http.MultipartRequest;
        expect(multipart.fields['request_type'], 'competitive');
        expect(multipart.fields['quote_deadline'], '2026-04-30');
        return _jsonStreamedResponse({'request_id': 404}, 201);
      }),
    );

    final response = await MarketplaceService.createRequest(
      title: 'طلب عروض أسعار',
      description: 'أريد تسعيرًا مفصلًا',
      requestType: 'competitive',
      subcategory: 33,
      quoteDeadline: '2026-04-30',
    );

    expect(response.isSuccess, isTrue);
    expect(response.dataAsMap?['request_id'], 404);
  });

  test('provider search falls back to cached results when offline', () async {
    ApiClient.debugSetHttpClient(
      _RecordingClient((request) async {
        expect(request.url.path, '/api/providers/list/');
        return _jsonStreamedResponse({
          'count': 1,
          'next': null,
          'results': [_providerJson(id: 18, name: 'نجار الرياض')],
        }, 200);
      }),
    );

    final network = await ProvidersApiService.fetchProvidersPageResult(
      query: 'نجار',
      categoryId: 4,
      forceRefresh: true,
    );

    expect(network.source, 'network');
    expect(network.data, hasLength(1));

    ApiClient.debugSetHttpClient(
      _RecordingClient((request) async {
        throw const SocketException('offline');
      }),
    );

    final cached = await ProvidersApiService.fetchProvidersPageResult(
      query: 'نجار',
      categoryId: 4,
      forceRefresh: true,
    );

    expect(cached.data, hasLength(1));
    expect(cached.isOfflineFallback, isTrue);
    expect(cached.data.first.displayName, 'نجار الرياض');
  });

  test('interactive following falls back to cached data when offline',
      () async {
    ApiClient.debugSetHttpClient(
      _RecordingClient((request) async {
        expect(request.url.path, '/api/providers/me/following/');
        return _jsonStreamedResponse([
          _providerJson(id: 51, name: 'مزود متابع'),
        ], 200);
      }),
    );

    final network = await InteractiveService.fetchFollowingResult(
      forceRefresh: true,
    );

    expect(network.source, 'network');
    expect(network.data, hasLength(1));

    ApiClient.debugSetHttpClient(
      _RecordingClient((request) async {
        throw const SocketException('offline');
      }),
    );

    final cached = await InteractiveService.fetchFollowingResult(
      forceRefresh: true,
    );

    expect(cached.data, hasLength(1));
    expect(cached.isOfflineFallback, isTrue);
    expect(cached.data.first.displayName, 'مزود متابع');
  });

  test('interactive followers use scoped endpoint and preserve role context',
      () async {
    await AccountModeService.setProviderMode(true);
    await AuthService.saveUserBasicInfo(userId: 7, roleState: 'provider');
    ApiClient.debugSetHttpClient(
      _RecordingClient((request) async {
        expect(request.url.path, '/api/providers/me/followers/');
        expect(request.url.queryParameters['mode'], 'provider');
        return _jsonStreamedResponse([
          {
            'id': 88,
            'username': 'client.follower',
            'display_name': 'عميل متابع',
            'provider_id': null,
            'profile_image': '',
            'follow_role_context': 'client',
          },
        ], 200);
      }),
    );

    final result = await InteractiveService.fetchFollowersResult(
      forceRefresh: true,
    );

    expect(result.source, 'network');
    expect(result.data, hasLength(1));
    expect(result.data.first.followRoleContext, 'client');
    expect(result.data.first.followerBadgeLabel, 'عميل');
    expect(result.data.first.providerId, isNull);
  });

  test('notifications fall back to cached data when offline', () async {
    ApiClient.debugSetHttpClient(
      _RecordingClient((request) async {
        expect(request.url.path, '/api/notifications/');
        return _jsonStreamedResponse({
          'count': 1,
          'next': null,
          'results': [
            _notificationJson(
                id: 91, title: 'تنبيه جديد', body: 'تم تحديث الطلب'),
          ],
        }, 200);
      }),
    );

    final network = await NotificationService.fetchNotificationsResult(
      mode: 'client',
      forceRefresh: true,
    );

    expect(network.source, 'network');
    expect(network.page.notifications, hasLength(1));

    ApiClient.debugSetHttpClient(
      _RecordingClient((request) async {
        throw const SocketException('offline');
      }),
    );

    final cached = await NotificationService.fetchNotificationsResult(
      mode: 'client',
      forceRefresh: true,
    );

    expect(cached.page.notifications, hasLength(1));
    expect(cached.isOfflineFallback, isTrue);
    expect(cached.page.notifications.first.title, 'تنبيه جديد');
  });

  test('messaging threads fall back to cached summaries when offline',
      () async {
    ApiClient.debugSetHttpClient(
      _RecordingClient((request) async {
        if (request.url.path == '/api/messaging/direct/threads/') {
          return _jsonStreamedResponse([
            _threadJson(
              id: 15,
              peerName: 'عميل المنصة',
              lastMessage: 'مرحبا بك في المحادثة',
            ),
          ], 200);
        }
        if (request.url.path == '/api/messaging/threads/states/') {
          return _jsonStreamedResponse([
            _threadStateJson(threadId: 15),
          ], 200);
        }
        throw StateError('Unexpected path: ${request.url.path}');
      }),
    );

    final network = await MessagingService.fetchThreadsResult(
      mode: 'client',
      forceRefresh: true,
    );

    expect(network.source, 'network');
    expect(network.data, hasLength(1));
    expect(network.data.first.lastMessage, 'مرحبا بك في المحادثة');

    ApiClient.debugSetHttpClient(
      _RecordingClient((request) async {
        throw const SocketException('offline');
      }),
    );

    final cached = await MessagingService.fetchThreadsResult(
      mode: 'client',
      forceRefresh: true,
    );

    expect(cached.data, hasLength(1));
    expect(cached.isOfflineFallback, isTrue);
    expect(cached.data.first.peerDisplayName, 'عميل المنصة');
    expect(cached.data.first.lastMessage, 'رسالة حديثة');
  });
}

class _RecordingClient extends http.BaseClient {
  _RecordingClient(this._handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
      _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _handler(request);
  }
}

http.StreamedResponse _jsonStreamedResponse(Object body, int statusCode) {
  return http.StreamedResponse(
    Stream<List<int>>.value(utf8.encode(jsonEncode(body))),
    statusCode,
    headers: const {'content-type': 'application/json'},
  );
}

Map<String, dynamic> _providerJson({required int id, required String name}) {
  return <String, dynamic>{
    'id': id,
    'display_name': name,
    'rating_avg': 4.7,
    'rating_count': 12,
    'followers_count': 3,
    'likes_count': 2,
    'following_count': 0,
    'completed_requests': 8,
    'city': 'الرياض',
    'city_display': 'الرياض',
    'is_verified_blue': true,
    'is_verified_green': false,
    'accepts_urgent': true,
    'subcategory_ids': const <int>[4],
  };
}

Map<String, dynamic> _notificationJson({
  required int id,
  required String title,
  required String body,
}) {
  return <String, dynamic>{
    'id': id,
    'title': title,
    'body': body,
    'kind': 'message_new',
    'audience_mode': 'client',
    'is_read': false,
    'is_pinned': false,
    'is_follow_up': false,
    'is_urgent': false,
    'created_at': '2026-04-24T12:00:00Z',
  };
}

Map<String, dynamic> _threadJson({
  required int id,
  required String peerName,
  required String lastMessage,
}) {
  return <String, dynamic>{
    'thread_id': id,
    'peer_id': 44,
    'peer_name': peerName,
    'peer_first_name': peerName,
    'peer_last_name': '',
    'peer_username': '',
    'peer_phone': '0555555555',
    'peer_city': 'riyadh',
    'peer_city_display': 'الرياض',
    'peer_profile_image': '',
    'peer_excellence_badges': const [],
    'last_message': lastMessage,
    'last_message_at': '2026-04-24T12:00:00Z',
    'unread_count': 2,
  };
}

Map<String, dynamic> _threadStateJson({required int threadId}) {
  return <String, dynamic>{
    'thread': threadId,
    'is_favorite': false,
    'favorite_label': '',
    'client_label': '',
    'is_archived': false,
    'is_blocked': false,
    'reply_restricted_to_me': false,
    'reply_restriction_reason': '',
    'system_sender_label': '',
    'is_system_thread': false,
  };
}
