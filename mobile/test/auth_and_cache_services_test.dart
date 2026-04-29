import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nawafeth/services/account_mode_service.dart';
import 'package:nawafeth/services/api_client.dart';
import 'package:nawafeth/services/auth_api_service.dart';
import 'package:nawafeth/services/auth_service.dart';
import 'package:nawafeth/services/content_service.dart';
import 'package:nawafeth/services/home_service.dart';
import 'package:nawafeth/services/local_cache_service.dart';
import 'package:nawafeth/services/onboarding_service.dart';
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
    await ContentService.clearCache();
    await HomeService.debugResetCaches();
    ApiClient.debugResetHttpClient();
  });

  tearDown(() {
    ApiClient.debugResetHttpClient();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
  });

  test('login success returns cooldown metadata', () async {
    ApiClient.debugSetHttpClient(
      MockClient((request) async {
        expect(request.url.path, '/api/accounts/otp/send/');
        expect(request.method, 'POST');
        return http.Response(
          jsonEncode({
            'cooldown_seconds': 45,
            'retry_after_seconds': 45,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final result = await AuthApiService.sendOtp('0555555555');

    expect(result.success, isTrue);
    expect(result.cooldownSeconds, 45);
    expect(result.error, isNull);
  });

  test('login error maps validation message', () async {
    ApiClient.debugSetHttpClient(
      MockClient((request) async {
        return http.Response(
          jsonEncode({
            'phone': ['رقم الجوال غير صحيح'],
          }),
          422,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final result = await AuthApiService.sendOtp('0500000000');

    expect(result.success, isFalse);
    expect(result.error, 'رقم الجوال غير صحيح');
  });

  test('otp success saves secure session data', () async {
    ApiClient.debugSetHttpClient(
      MockClient((request) async {
        expect(request.url.path, '/api/accounts/otp/verify/');
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        expect(payload['mobile_any_otp'], isTrue);
        return http.Response(
          jsonEncode({
            'access': 'access-token',
            'refresh': 'refresh-token',
            'user_id': 42,
            'role_state': 'client',
            'needs_completion': false,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final result = await AuthApiService.verifyOtp('0555555555', '1234');

    expect(result.success, isTrue);
    expect(await AuthService.getAccessToken(), 'access-token');
    expect(await AuthService.getRefreshToken(), 'refresh-token');
    expect(await AuthService.getUserId(), 42);
    expect(await AuthService.getRoleState(), 'client');
  });

  test('otp error returns friendly message without saving token', () async {
    ApiClient.debugSetHttpClient(
      MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': 'رمز التحقق غير صالح'}),
          401,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final result = await AuthApiService.verifyOtp('0555555555', '9999');

    expect(result.success, isFalse);
    expect(result.error, 'رمز التحقق غير صالح');
    expect(await AuthService.getAccessToken(), isNull);
  });

  test('onboarding cache flag is stored after markSeen', () async {
    expect(await OnboardingService.shouldShowOnboarding(), isTrue);

    await OnboardingService.markSeen();

    expect(await OnboardingService.shouldShowOnboarding(), isFalse);
  });

  test('home cache fallback returns cached categories when offline', () async {
    ApiClient.debugSetHttpClient(
      MockClient((request) async {
        expect(request.url.path, '/api/providers/categories/');
        return http.Response(
          jsonEncode([
            {
              'id': 1,
              'name': 'قانون',
              'subcategories': [
                {'id': 10, 'name': 'استشارات'}
              ],
            }
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final networkResult = await HomeService.fetchCategoriesResult(
      forceRefresh: true,
    );
    expect(networkResult.source, 'network');
    expect(networkResult.data, hasLength(1));

    ApiClient.debugSetHttpClient(
      MockClient((request) async {
        throw const SocketException('offline');
      }),
    );

    final cachedResult = await HomeService.fetchCategoriesResult(
      forceRefresh: true,
    );

    expect(cachedResult.data, hasLength(1));
    expect(cachedResult.isOfflineFallback, isTrue);
    expect(cachedResult.data.first.name, 'قانون');
  });

  test('api client caches sensitive GET responses per user and mode', () async {
    var requestCount = 0;
    ApiClient.debugSetHttpClient(
      MockClient((request) async {
        requestCount += 1;
        return http.Response(
          jsonEncode({
            'request_count': requestCount,
            'path': request.url.path,
            'query': request.url.query,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await AuthService.saveTokens(access: 'token-a', refresh: 'refresh-a');
    await AuthService.saveUserBasicInfo(userId: 1, roleState: 'client');
    await AccountModeService.setProviderMode(false);

    final firstUserClient =
        await ApiClient.get('/api/accounts/me/?mode=client');
    final firstUserClientCached =
        await ApiClient.get('/api/accounts/me/?mode=client');

    await AuthService.saveUserBasicInfo(userId: 2, roleState: 'client');
    final secondUserClient =
        await ApiClient.get('/api/accounts/me/?mode=client');

    await AuthService.saveUserBasicInfo(userId: 2, roleState: 'provider');
    await AccountModeService.setProviderMode(true);
    final secondUserProvider =
        await ApiClient.get('/api/core/unread-badges/?mode=provider');
    final secondUserProviderCached =
        await ApiClient.get('/api/core/unread-badges/?mode=provider');

    expect(firstUserClient.dataAsMap?['request_count'], 1);
    expect(firstUserClientCached.dataAsMap?['request_count'], 1);
    expect(secondUserClient.dataAsMap?['request_count'], 2);
    expect(secondUserProvider.dataAsMap?['request_count'], 3);
    expect(secondUserProviderCached.dataAsMap?['request_count'], 3);
    expect(requestCount, 3);
  });
}
