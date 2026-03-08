import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nawafeth/models/excellence_badge_model.dart';
import 'package:nawafeth/widgets/excellence_badges_wrap.dart';

void main() {
  testWidgets('renders one chip per excellence badge', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ExcellenceBadgesWrap(
            badges: [
              ExcellenceBadgeModel(
                code: 'featured_service',
                name: 'الخدمة المتميزة',
                icon: 'sparkles',
                color: '#C0841A',
              ),
              ExcellenceBadgeModel(
                code: 'high_achievement',
                name: 'الإنجاز العالي',
                icon: 'bolt',
                color: '#0F766E',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('الخدمة المتميزة'), findsOneWidget);
    expect(find.text('الإنجاز العالي'), findsOneWidget);
    expect(find.byIcon(Icons.auto_awesome_rounded), findsOneWidget);
    expect(find.byIcon(Icons.bolt_rounded), findsOneWidget);
  });
}
