import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no providerId=>verified heuristics remain in modified files', () {
    const files = <String>[
      'lib/widgets/app_bar.dart',
      'lib/widgets/profiles_slider.dart',
      'lib/screens/provider_profile_screen.dart',
      'lib/screens/service_detail_screen.dart',
      'lib/screens/home_screen.dart',
      'lib/screens/search_provider_screen.dart',
      'lib/screens/interactive_screen.dart',
      'lib/screens/providers_map_screen.dart',
    ];

    final bannedPatterns = <RegExp>[
      RegExp("provider\\s*\\[\\s*['\"]verified['\"]\\s*\\]"),
      RegExp(r'providerId\s*!=\s*null[\s\S]{0,220}Icons\.verified'),
      RegExp(r'provider_id\s*!=\s*null[\s\S]{0,220}Icons\.verified'),
      RegExp(r'isVerified\s*=\s*.*providerId'),
      RegExp("['\"]verified['\"]\\s*:\\s*(true|false)"),
    ];

    for (final path in files) {
      final content = File(path).readAsStringSync();
      for (final pattern in bannedPatterns) {
        expect(
          pattern.hasMatch(content),
          isFalse,
          reason: 'Found banned heuristic `${pattern.pattern}` in $path',
        );
      }
    }
  });
}
