import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nawafeth/services/api_client.dart';
import 'package:nawafeth/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const jsonHeaders = <String, String>{'content-type': 'application/json'};

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ApiClient.debugResetHttpClient();
  });

  tearDown(() async {
    ApiClient.debugResetHttpClient();
  });

  test('coalesces concurrent refresh attempts into a single refresh request', () async {
    var protectedCalls = 0;
    var refreshCalls = 0;

    ApiClient.debugSetHttpClient(
      MockClient((request) async {
        if (request.url.path == '/api/accounts/token/refresh/') {
          refreshCalls += 1;
          return http.Response(
            jsonEncode(<String, dynamic>{'access': 'new-access'}),
            200,
            headers: jsonHeaders,
          );
        }

        if (request.url.path == '/api/test/protected/') {
          protectedCalls += 1;
          final auth = request.headers['Authorization'];
          if (auth == 'Bearer expired-access') {
            return http.Response(
              jsonEncode(<String, dynamic>{'detail': 'expired'}),
              401,
              headers: jsonHeaders,
            );
          }
          if (auth == 'Bearer new-access') {
            return http.Response(
              jsonEncode(<String, dynamic>{'ok': true}),
              200,
              headers: jsonHeaders,
            );
          }
          return http.Response(
            jsonEncode(<String, dynamic>{'detail': 'unexpected auth state'}),
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

    final responses = await Future.wait(<Future<ApiResponse>>[
      ApiClient.get('/api/test/protected/'),
      ApiClient.get('/api/test/protected/'),
    ]);

    expect(refreshCalls, 1);
    expect(protectedCalls, 4);
    expect(responses.every((response) => response.isSuccess), isTrue);
    expect(await AuthService.getAccessToken(), 'new-access');
  });

  test('keeps stored tokens when refresh fails transiently', () async {
    var refreshCalls = 0;

    ApiClient.debugSetHttpClient(
      MockClient((request) async {
        if (request.url.path == '/api/accounts/token/refresh/') {
          refreshCalls += 1;
          return http.Response(
            jsonEncode(<String, dynamic>{'detail': 'temporarily unavailable'}),
            503,
            headers: jsonHeaders,
          );
        }

        if (request.url.path == '/api/test/protected/') {
          return http.Response(
            jsonEncode(<String, dynamic>{'detail': 'expired'}),
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

    final response = await ApiClient.get('/api/test/protected/');

    expect(response.statusCode, 401);
    expect(refreshCalls, 1);
    expect(await AuthService.getAccessToken(), 'expired-access');
    expect(await AuthService.getRefreshToken(), 'refresh-token');
  });
}
