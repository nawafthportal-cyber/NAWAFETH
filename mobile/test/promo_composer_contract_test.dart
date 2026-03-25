import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nawafeth/screens/provider_dashboard/promotion_screen.dart';
import 'package:nawafeth/services/api_client.dart';
import 'package:nawafeth/services/promo_service.dart';
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

  group('Promo composer helpers', () {
    test('validates promo message with message OR asset rule', () {
      expect(
        validatePromoMessageOrAssetRequirement(
          requiresMessage: true,
          messageText: '   ',
          assetCount: 0,
        ),
        'أدخل نص الرسالة أو أضف مرفقًا',
      );

      expect(
        validatePromoMessageOrAssetRequirement(
          requiresMessage: true,
          messageText: 'نص موجود',
          assetCount: 0,
        ),
        isNull,
      );

      expect(
        validatePromoMessageOrAssetRequirement(
          requiresMessage: true,
          messageText: '   ',
          assetCount: 1,
        ),
        isNull,
      );
    });

    test('orders search scopes by canonical backend order', () {
      final ordered = orderedSearchScopes(<String>[
        'category_match',
        'default',
        'unknown',
        'main_results',
      ]);
      expect(ordered, <String>['default', 'main_results', 'category_match']);
    });

    test('builds home banner video autofit warning message', () {
      final warning = buildHomeBannerVideoAutofitWarning(
        requiredWidth: 1920,
        requiredHeight: 840,
        currentWidth: 1280,
        currentHeight: 720,
      );

      expect(warning.startsWith('WARN:'), isTrue);
      expect(warning, contains('1920x840'));
      expect(warning, contains('1280x720'));
    });
  });

  group('PromoService bundle payload', () {
    test('createBundleRequest sends scales and multi-scope item payload', () async {
      Map<String, dynamic>? capturedBody;

      ApiClient.debugSetHttpClient(
        MockClient((request) async {
          if (request.url.path == '/api/promo/requests/create/') {
            capturedBody = Map<String, dynamic>.from(
              jsonDecode(request.body) as Map<String, dynamic>,
            );
            return http.Response(
              jsonEncode(<String, dynamic>{'id': 101}),
              200,
              headers: jsonHeaders,
            );
          }
          return http.Response('not found', 404);
        }),
      );

      final response = await PromoService.createBundleRequest(
        title: 'طلب ترويج',
        mobileScale: 95,
        tabletScale: 105,
        desktopScale: 110,
        items: <Map<String, dynamic>>[
          <String, dynamic>{
            'service_type': 'search_results',
            'title': 'بحث',
            'search_scopes': <String>['default', 'main_results'],
            'search_scope': 'default',
            'search_position': 'top10',
            'asset_count': 0,
          },
        ],
      );

      expect(response.isSuccess, isTrue);
      expect(capturedBody, isNotNull);
      expect(capturedBody!['mobile_scale'], 95);
      expect(capturedBody!['tablet_scale'], 105);
      expect(capturedBody!['desktop_scale'], 110);
      final items = List<Map<String, dynamic>>.from(capturedBody!['items'] as List);
      expect(items.first['search_scopes'], <String>['default', 'main_results']);
    });

    test('previewBundleRequest sends scales alongside items', () async {
      Map<String, dynamic>? capturedBody;

      ApiClient.debugSetHttpClient(
        MockClient((request) async {
          if (request.url.path == '/api/promo/requests/preview/') {
            capturedBody = Map<String, dynamic>.from(
              jsonDecode(request.body) as Map<String, dynamic>,
            );
            return http.Response(
              jsonEncode(<String, dynamic>{'total': '100.00'}),
              200,
              headers: jsonHeaders,
            );
          }
          return http.Response('not found', 404);
        }),
      );

      final response = await PromoService.previewBundleRequest(
        title: 'معاينة طلب',
        mobileScale: 90,
        tabletScale: 100,
        desktopScale: 120,
        items: <Map<String, dynamic>>[
          <String, dynamic>{
            'service_type': 'home_banner',
            'title': 'بنر',
            'asset_count': 1,
          },
        ],
      );

      expect(response.isSuccess, isTrue);
      expect(capturedBody, isNotNull);
      expect(capturedBody!['mobile_scale'], 90);
      expect(capturedBody!['tablet_scale'], 100);
      expect(capturedBody!['desktop_scale'], 120);
      expect(capturedBody!['items'], isA<List<dynamic>>());
    });
  });
}
