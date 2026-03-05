import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nawafeth/services/api_client.dart';
import 'package:nawafeth/widgets/verified_badge_view.dart';

void main() {
  testWidgets('does not render when provider has no badges', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: VerifiedBadgeView(
            isVerifiedBlue: false,
            isVerifiedGreen: false,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.verified), findsNothing);
  });

  testWidgets('opens explanation sheet on tap using backend payload', (
    WidgetTester tester,
  ) async {
    var calls = 0;

    Future<ApiResponse> fakeFetcher(String badgeType) async {
      calls += 1;
      return ApiResponse(
        statusCode: 200,
        data: {
          'badge_type': badgeType,
          'title': 'الشارة الزرقاء',
          'short_description': 'توثيق هوية من مصدر رسمي.',
          'explanation': 'تعني أن مقدم الخدمة مكتمل التحقق الأساسي.',
          'requirements': [
            {
              'code': 'B1',
              'title': 'توثيق الهوية الوطنية أو السجل التجاري',
            },
          ],
        },
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: VerifiedBadgeView(
              isVerifiedBlue: true,
              isVerifiedGreen: false,
              iconSize: 18,
              detailFetcher: fakeFetcher,
            ),
          ),
        ),
      ),
    );

    // No fetch must happen during build/rendering.
    expect(calls, 0);
    await tester.pump();
    expect(calls, 0);

    expect(find.byIcon(Icons.verified), findsOneWidget);

    await tester.tap(find.byType(VerifiedBadgeView));
    await tester.pumpAndSettle();

    // Fetch happens only after explicit tap.
    expect(calls, 1);

    expect(find.text('الشارة الزرقاء'), findsOneWidget);
    expect(find.text('متطلبات الشارة'), findsOneWidget);
    expect(find.textContaining('B1'), findsOneWidget);
  });
}
