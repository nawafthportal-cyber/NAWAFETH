import 'package:flutter_test/flutter_test.dart';
import 'package:nawafeth/models/provider_public_model.dart';

void main() {
  test('parses excellence badges from provider public payload', () {
    final provider = ProviderPublicModel.fromJson({
      'id': 7,
      'display_name': 'مزود متميز',
      'is_verified_blue': true,
      'excellence_badges': [
        {
          'code': 'featured_service',
          'name': 'الخدمة المتميزة',
          'icon': 'sparkles',
          'color': '#C0841A',
        },
        {
          'code': 'top_100_club',
          'name': 'نادي المئة الكبار',
          'icon': 'trophy',
          'color': '#7C3AED',
        },
      ],
    });

    expect(provider.hasExcellenceBadges, isTrue);
    expect(provider.excellenceBadges.length, 2);
    expect(provider.excellenceBadges.first.code, 'featured_service');
    expect(provider.excellenceBadges.last.name, 'نادي المئة الكبار');
  });
}
