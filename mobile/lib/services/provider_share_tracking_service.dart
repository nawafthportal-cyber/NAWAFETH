import 'package:flutter/foundation.dart';

import 'api_client.dart';

class ProviderShareTrackingService {
  static Future<void> recordProfileShare({
    required Object providerId,
    required String channel,
  }) async {
    final providerIdText = providerId.toString().trim();
    if (providerIdText.isEmpty) return;
    try {
      await ApiClient.post(
        '/api/providers/$providerIdText/share/',
        body: {
          'content_type': 'profile',
          'channel': channel,
        },
      );
    } catch (error) {
      debugPrint('Provider share tracking failed: $error');
    }
  }
}