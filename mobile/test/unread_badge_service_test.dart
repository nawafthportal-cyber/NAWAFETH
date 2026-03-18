import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nawafeth/services/account_mode_service.dart';
import 'package:nawafeth/services/api_client.dart';
import 'package:nawafeth/services/auth_service.dart';
import 'package:nawafeth/services/unread_badge_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const jsonHeaders = <String, String>{'content-type': 'application/json'};

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ApiClient.debugResetHttpClient();
    await UnreadBadgeService.debugReset();
  });

  tearDown(() async {
    ApiClient.debugResetHttpClient();
    await UnreadBadgeService.debugReset();
  });

  testWidgets('maintains a single polling timer across multiple subscribers', (
    tester,
  ) async {
    ApiClient.debugSetHttpClient(
      MockClient((request) async {
        if (request.url.path == '/api/core/unread-badges/') {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'notifications': 2,
              'chats': 3,
              'degraded': false,
              'stale': false,
            }),
            200,
            headers: jsonHeaders,
          );
        }
        return http.Response('not found', 404);
      }),
    );

    await AuthService.saveTokens(access: 'token', refresh: 'refresh-token');

    final first = UnreadBadgeService.acquire();
    final second = UnreadBadgeService.acquire();

    await tester.pump();
    await tester.pump();

    expect(UnreadBadgeService.debugSubscriberCount(), 2);
    expect(UnreadBadgeService.debugHasActiveTimer(), isTrue);

    await UnreadBadgeService.refresh(force: true);

    expect(first.value.notifications, 2);
    expect(second.value.chats, 3);

    UnreadBadgeService.release();
    expect(UnreadBadgeService.debugSubscriberCount(), 1);
    expect(UnreadBadgeService.debugHasActiveTimer(), isTrue);

    UnreadBadgeService.release();
    expect(UnreadBadgeService.debugSubscriberCount(), 0);
    expect(UnreadBadgeService.debugHasActiveTimer(), isFalse);
  });

  testWidgets('deduplicates concurrent unread refreshes and reuses one token refresh', (
    tester,
  ) async {
    var badgeCalls = 0;
    var refreshCalls = 0;

    ApiClient.debugSetHttpClient(
      MockClient((request) async {
        if (request.url.path == '/api/accounts/token/refresh/') {
          refreshCalls += 1;
          return http.Response(
            jsonEncode(<String, dynamic>{'access': 'fresh-access'}),
            200,
            headers: jsonHeaders,
          );
        }

        if (request.url.path == '/api/core/unread-badges/') {
          badgeCalls += 1;
          final auth = request.headers['Authorization'];
          if (auth == 'Bearer expired-access') {
            return http.Response(
              jsonEncode(<String, dynamic>{'detail': 'expired'}),
              401,
              headers: jsonHeaders,
            );
          }
          if (auth == 'Bearer fresh-access') {
            return http.Response(
              jsonEncode(<String, dynamic>{
                'notifications': 4,
                'chats': 7,
                'mode': request.url.queryParameters['mode'],
                'degraded': false,
                'stale': false,
              }),
              200,
              headers: jsonHeaders,
            );
          }
          return http.Response(
            jsonEncode(<String, dynamic>{'detail': 'unauthorized'}),
            401,
            headers: jsonHeaders,
          );
        }

        return http.Response('not found', 404);
      }),
    );

    await AuthService.saveTokens(
      access: 'expired-access',
      refresh: 'refresh-token',
    );
    await AccountModeService.setProviderMode(true);

    final results = await Future.wait(<Future<UnreadBadges>>[
      UnreadBadgeService.refresh(force: true),
      UnreadBadgeService.refresh(force: true),
    ]);

    expect(refreshCalls, 1);
    expect(badgeCalls, 2);
    expect(results[0].notifications, 4);
    expect(results[1].chats, 7);
    expect(await AuthService.getAccessToken(), 'fresh-access');
  });

  testWidgets('stops polling and clears badge state on logout', (tester) async {
    ApiClient.debugSetHttpClient(
      MockClient((request) async {
        if (request.url.path == '/api/core/unread-badges/') {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'notifications': 5,
              'chats': 6,
              'degraded': false,
              'stale': false,
            }),
            200,
            headers: jsonHeaders,
          );
        }
        return http.Response('not found', 404);
      }),
    );

    await AuthService.saveTokens(access: 'access-token', refresh: 'refresh-token');

    final listenable = UnreadBadgeService.acquire();
    await tester.pump();
    await UnreadBadgeService.refresh(force: true);

    expect(UnreadBadgeService.debugHasActiveTimer(), isTrue);
    expect(listenable.value.notifications, 5);
    expect(listenable.value.chats, 6);

    await AuthService.logout();
    await tester.pump();

    expect(UnreadBadgeService.debugHasActiveTimer(), isFalse);
    expect(listenable.value.notifications, 0);
    expect(listenable.value.chats, 0);

    UnreadBadgeService.release();
  });

  testWidgets('refreshes unread badges when account mode changes', (tester) async {
    final requestedModes = <String>[];

    ApiClient.debugSetHttpClient(
      MockClient((request) async {
        if (request.url.path == '/api/core/unread-badges/') {
          final mode = request.url.queryParameters['mode'] ?? 'client';
          requestedModes.add(mode);
          final payload = mode == 'provider'
              ? <String, dynamic>{
                  'notifications': 9,
                  'chats': 8,
                  'degraded': false,
                  'stale': false,
                }
              : <String, dynamic>{
                  'notifications': 1,
                  'chats': 2,
                  'degraded': false,
                  'stale': false,
                };
          return http.Response(
            jsonEncode(payload),
            200,
            headers: jsonHeaders,
          );
        }
        return http.Response('not found', 404);
      }),
    );

    await AuthService.saveTokens(access: 'token', refresh: 'refresh-token');

    final listenable = UnreadBadgeService.acquire();
    await UnreadBadgeService.refresh(force: true);
    expect(listenable.value.notifications, 1);
    expect(listenable.value.chats, 2);

    await AccountModeService.setProviderMode(true);
    await tester.pump();
    await tester.pump();

    expect(listenable.value.notifications, 9);
    expect(listenable.value.chats, 8);
    expect(requestedModes, contains('client'));
    expect(requestedModes, contains('provider'));

    UnreadBadgeService.release();
  });
}
