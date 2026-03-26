import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nawafeth/screens/provider_dashboard/promotion_screen.dart';
import 'package:nawafeth/services/api_client.dart';
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

  testWidgets('submits promo_messages request via preview -> create flow', (
    WidgetTester tester,
  ) async {
    Map<String, dynamic>? previewBody;
    Map<String, dynamic>? createBody;

    ApiClient.debugSetHttpClient(
      MockClient((request) async {
        if (request.url.path == '/api/promo/requests/my/') {
          return http.Response('[]', 200, headers: jsonHeaders);
        }

        if (request.url.path == '/api/promo/requests/preview/') {
          previewBody = Map<String, dynamic>.from(
            jsonDecode(request.body) as Map<String, dynamic>,
          );
          return http.Response(
            jsonEncode(<String, dynamic>{
              'subtotal': '100.00',
              'vat_amount': '15.00',
              'total': '115.00',
              'items': <Map<String, dynamic>>[
                <String, dynamic>{
                  'service_type': 'promo_messages',
                  'title': 'الرسائل الدعائية',
                  'subtotal': '100.00',
                  'duration_days': 1,
                },
              ],
            }),
            200,
            headers: jsonHeaders,
          );
        }

        if (request.url.path == '/api/promo/requests/create/') {
          createBody = Map<String, dynamic>.from(
            jsonDecode(request.body) as Map<String, dynamic>,
          );
          return http.Response(
            jsonEncode(<String, dynamic>{
              'id': 9001,
              'code': 'M0001',
              'items': <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 3001,
                  'service_type': 'promo_messages',
                  'sort_order': 0,
                },
              ],
            }),
            200,
            headers: jsonHeaders,
          );
        }

        return http.Response('not found', 404);
      }),
    );

    await tester.pumpWidget(const MaterialApp(home: PromotionScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('طلب جديد'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('الرسائل الدعائية'));
    await tester.pumpAndSettle();

    final titleField = find.byType(TextField).first;
    await tester.enterText(titleField, 'حملة رسائل دعائية');

    final messageField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'نص الرسالة الترويجية',
    );
    expect(messageField, findsOneWidget);
    await tester.enterText(messageField, 'مرحبا، خصومات جديدة');
    tester.testTextInput.hide();
    await tester.pump();

    final sendAtTile = find.ancestor(
      of: find.text('وقت الإرسال'),
      matching: find.byType(InkWell),
    );
    expect(sendAtTile, findsWidgets);
    await tester.ensureVisible(sendAtTile.first);
    await tester.tap(sendAtTile.first);
    await tester.pumpAndSettle();
    await _confirmDialogSelection(tester);
    await _confirmDialogSelection(tester);

    final submitButton = find.widgetWithText(
      ElevatedButton,
      'معاينة التسعير ثم الإرسال',
    );
    expect(submitButton, findsOneWidget);
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('ملخص طلب الترويج والتكلفة'), findsOneWidget);

    await tester.tap(find.text('استمرار'));
    await tester.pumpAndSettle();

    expect(find.text('شاشة الدفع'), findsOneWidget);
    await tester.tap(find.text('دفع'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('تمت عملية الدفع بنجاح'), findsOneWidget);

    expect(previewBody, isNotNull);
    expect(createBody, isNotNull);
    expect(previewBody!['title'], 'حملة رسائل دعائية');
    expect(createBody!['title'], 'حملة رسائل دعائية');

    final previewItems = List<Map<String, dynamic>>.from(
      previewBody!['items'] as List,
    );
    final createItems = List<Map<String, dynamic>>.from(
      createBody!['items'] as List,
    );

    expect(previewItems, hasLength(1));
    expect(createItems, hasLength(1));
    expect(previewItems.first['service_type'], 'promo_messages');
    expect(createItems.first['service_type'], 'promo_messages');
    expect(previewItems.first['message_body'], 'مرحبا، خصومات جديدة');
    expect(createItems.first['message_body'], 'مرحبا، خصومات جديدة');
    expect(previewItems.first['send_at'], isA<String>());
    expect(createItems.first['send_at'], isA<String>());
  });

  testWidgets('opens pricing guide from new promo request composer', (
    WidgetTester tester,
  ) async {
    ApiClient.debugSetHttpClient(
      MockClient((request) async {
        if (request.url.path == '/api/promo/requests/my/') {
          return http.Response('[]', 200, headers: jsonHeaders);
        }
        return http.Response('not found', 404);
      }),
    );

    await tester.pumpWidget(const MaterialApp(home: PromotionScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('طلب جديد'));
    await tester.pumpAndSettle();

    expect(find.textContaining('مزود الخدمة:'), findsOneWidget);

    await tester.tap(find.text('الأسعار'));
    await tester.pumpAndSettle();

    expect(find.text('بنر الصفحة الرئيسية'), findsOneWidget);
    expect(find.text('الظهور في قوائم البحث'), findsOneWidget);
    expect(find.text('مرة كل 10 ثواني'), findsOneWidget);
  });

  testWidgets('shows per-service preview dialog and live total section', (
    WidgetTester tester,
  ) async {
    ApiClient.debugSetHttpClient(
      MockClient((request) async {
        if (request.url.path == '/api/promo/requests/my/') {
          return http.Response('[]', 200, headers: jsonHeaders);
        }
        if (request.url.path == '/api/promo/requests/preview/') {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'subtotal': '120.00',
              'vat_amount': '18.00',
              'total': '138.00',
              'items': <Map<String, dynamic>>[
                <String, dynamic>{
                  'service_type': 'promo_messages',
                  'title': 'الرسائل الدعائية',
                  'subtotal': '120.00',
                  'duration_days': 1,
                },
              ],
            }),
            200,
            headers: jsonHeaders,
          );
        }
        return http.Response('not found', 404);
      }),
    );

    await tester.pumpWidget(const MaterialApp(home: PromotionScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('طلب جديد'));
    await tester.pumpAndSettle();
    expect(find.text('مجمل التكلفة'), findsOneWidget);

    await tester.tap(find.text('الرسائل الدعائية'));
    await tester.pumpAndSettle();

    final titleField = find.byType(TextField).first;
    await tester.enterText(titleField, 'معاينة بند دعائي');

    final messageField = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == 'نص الرسالة الترويجية',
    );
    await tester.enterText(messageField, 'نص اختبار المعاينة');

    final sendAtTile = find.ancestor(of: find.text('وقت الإرسال'), matching: find.byType(InkWell));
    await tester.ensureVisible(sendAtTile.first);
    await tester.tap(sendAtTile.first, warnIfMissed: false);
    await tester.pumpAndSettle();
    await _confirmDialogSelection(tester);
    await _confirmDialogSelection(tester);

    final servicePreviewBtn = find.widgetWithText(OutlinedButton, 'معاينة');
    expect(servicePreviewBtn, findsWidgets);
    await tester.ensureVisible(servicePreviewBtn.first);
    await tester.tap(servicePreviewBtn.first, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.textContaining('معاينة'), findsWidgets);
    expect(find.textContaining('تم احتساب السعر حسب قواعد صفحة الأسعار الحالية لكل بند.'), findsOneWidget);
  });
}

Future<void> _confirmDialogSelection(WidgetTester tester) async {
  final labels = <String>['OK', 'موافق', 'حسنًا', 'حسناً'];
  for (final label in labels) {
    final finder = find.text(label);
    if (finder.evaluate().isNotEmpty) {
      await tester.tap(finder.last);
      await tester.pumpAndSettle();
      return;
    }
  }

  final textButtons = find.byType(TextButton);
  if (textButtons.evaluate().isNotEmpty) {
    await tester.tap(textButtons.last);
    await tester.pumpAndSettle();
  }
}
