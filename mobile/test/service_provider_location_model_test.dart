import 'package:flutter_test/flutter_test.dart';
import 'package:nawafeth/models/service_provider_location.dart';

void main() {
  test('parses green verification even when blue is explicitly false', () {
    final provider = ServiceProviderLocation.fromJson({
      'id': 12,
      'display_name': 'مزود اختبار',
      'lat': 24.7136,
      'lng': 46.6753,
      'is_verified_blue': false,
      'is_verified_green': true,
    });

    expect(provider.isVerifiedBlue, isFalse);
    expect(provider.isVerifiedGreen, isTrue);
    expect(provider.verified, isTrue);
  });

  test('maps legacy verified=true into green when typed flags are absent', () {
    final provider = ServiceProviderLocation.fromJson({
      'id': 15,
      'display_name': 'مزود قديم',
      'lat': 24.7,
      'lng': 46.6,
      'verified': true,
    });

    expect(provider.isVerifiedBlue, isFalse);
    expect(provider.isVerifiedGreen, isTrue);
    expect(provider.verified, isTrue);
  });
}
