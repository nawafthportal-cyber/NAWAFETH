import 'api_client.dart';
import 'content_service.dart';

class TopBarSponsorData {
  final String name;
  final String? assetUrl;
  final String? redirectUrl;
  final String? providerId;
  final String? messageBody;

  const TopBarSponsorData({
    required this.name,
    this.assetUrl,
    this.redirectUrl,
    this.providerId,
    this.messageBody,
  });

  bool get hasLink =>
      (redirectUrl != null && redirectUrl!.trim().isNotEmpty) ||
      (providerId != null && providerId!.trim().isNotEmpty);
}

class TopBarBrandingService {
  static const Duration _cacheTtl = Duration(minutes: 5);
  static _TopBarSponsorCache? _cache;
  static _TopBarBrandLogoCache? _brandLogoCache;

  static Future<TopBarSponsorData?> fetchActiveSponsor({
    bool forceRefresh = false,
  }) async {
    final cached = _cache;
    if (!forceRefresh && cached != null && cached.isFresh(_cacheTtl)) {
      return cached.data;
    }

    final response = await ApiClient.get(
      '/api/promo/active/?service_type=sponsorship&limit=6',
    );
    if (!response.isSuccess || response.data == null) {
      return cached?.data;
    }

    final sponsor = _pickFirstSponsor(response.data);
    _cache = _TopBarSponsorCache(sponsor, DateTime.now());
    return sponsor;
  }

  static Future<String?> fetchBrandLogo({bool forceRefresh = false}) async {
    final cached = _brandLogoCache;
    if (!forceRefresh && cached != null && cached.isFresh(_cacheTtl)) {
      return cached.data;
    }

    final response = await ContentService.fetchPublicContent(
      forceRefresh: forceRefresh,
    );
    if (!response.isSuccess || response.dataAsMap == null) {
      return cached?.data;
    }

    final logoUrl = _parseBrandLogoUrl(response.dataAsMap!);
    _brandLogoCache = _TopBarBrandLogoCache(logoUrl, DateTime.now());
    return logoUrl;
  }

  static TopBarSponsorData? _pickFirstSponsor(dynamic payload) {
    final rows = _itemsFromPayload(payload);
    for (final row in rows) {
      final sponsor = _parseSponsorRow(row);
      if (sponsor != null) {
        return sponsor;
      }
    }
    return null;
  }

  static List<Map<String, dynamic>> _itemsFromPayload(dynamic payload) {
    if (payload is List) {
      return payload
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }
    if (payload is Map<String, dynamic>) {
      final results = payload['results'];
      if (results is List) {
        return results
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      }
    }
    return const <Map<String, dynamic>>[];
  }

  static TopBarSponsorData? _parseSponsorRow(Map<String, dynamic> row) {
    final sponsorName = _clean(
      row['sponsor_name'] ?? row['target_provider_display_name'],
    );
    final assets = row['assets'];
    String? assetUrl;
    if (assets is List) {
      for (final asset in assets.whereType<Map>()) {
        final normalized = Map<String, dynamic>.from(asset);
        final assetType = _clean(normalized['asset_type']).toLowerCase();
        if (assetType.isNotEmpty && assetType != 'image') {
          continue;
        }
        final rawPath = _clean(normalized['file'] ?? normalized['file_url']);
        if (rawPath.isEmpty) continue;
        assetUrl = ApiClient.buildMediaUrl(rawPath);
        if ((assetUrl ?? '').isNotEmpty) {
          break;
        }
      }
    }

    final redirectUrl = _clean(row['redirect_url'] ?? row['sponsor_url']);
    final providerId = _clean(row['target_provider_id']);
    final messageBody = _clean(row['message_body'] ?? row['message_title']);
    if (sponsorName.isEmpty && (assetUrl ?? '').isEmpty) {
      return null;
    }

    return TopBarSponsorData(
      name: sponsorName.isNotEmpty ? sponsorName : 'راعٍ رسمي',
      assetUrl: assetUrl,
      redirectUrl: redirectUrl.isNotEmpty ? redirectUrl : null,
      providerId: providerId.isNotEmpty ? providerId : null,
      messageBody: messageBody.isNotEmpty ? messageBody : null,
    );
  }

  static String _clean(Object? value) {
    return value == null ? '' : value.toString().trim();
  }

  static String? _parseBrandLogoUrl(Map<String, dynamic> payload) {
    final blocks = payload['blocks'];
    if (blocks is! Map) return null;
    final rawBlock = blocks['topbar_brand_logo'];
    if (rawBlock is! Map) return null;
    final block = Map<String, dynamic>.from(rawBlock);
    final mediaPath = _clean(block['media_url']);
    if (mediaPath.isEmpty) return null;
    final mediaUrl = ApiClient.buildMediaUrl(mediaPath);
    if ((mediaUrl ?? '').trim().isEmpty) return null;
    return mediaUrl;
  }
}

class _TopBarSponsorCache {
  final TopBarSponsorData? data;
  final DateTime fetchedAt;

  const _TopBarSponsorCache(this.data, this.fetchedAt);

  bool isFresh(Duration ttl) {
    return DateTime.now().difference(fetchedAt) <= ttl;
  }
}

class _TopBarBrandLogoCache {
  final String? data;
  final DateTime fetchedAt;

  const _TopBarBrandLogoCache(this.data, this.fetchedAt);

  bool isFresh(Duration ttl) {
    return DateTime.now().difference(fetchedAt) <= ttl;
  }
}
