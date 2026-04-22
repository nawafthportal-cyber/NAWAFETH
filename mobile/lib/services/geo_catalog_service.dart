library;

import '../constants/saudi_cities.dart';
import 'api_client.dart';
import 'app_logger.dart';

class GeoCatalogResult {
  final List<SaudiRegionCatalogEntry> catalog;
  final bool usedFallback;

  const GeoCatalogResult({
    required this.catalog,
    required this.usedFallback,
  });
}

class GeoCatalogService {
  static Future<GeoCatalogResult> fetchRegionCatalogWithFallback() async {
    try {
      final response = await ApiClient.get('/api/providers/geo/regions-cities/');
      final parsed = normalizeRegionCatalog(response.data);
      if (response.isSuccess && parsed.isNotEmpty) {
        return GeoCatalogResult(catalog: parsed, usedFallback: false);
      }
      if (!response.isSuccess) {
        AppLogger.warn(
          'GeoCatalogService.fetchRegionCatalogWithFallback non-success response',
          error: response.error ?? 'status=${response.statusCode}',
        );
      }
    } catch (error, stackTrace) {
      AppLogger.warn(
        'GeoCatalogService.fetchRegionCatalogWithFallback failed',
        error: error,
        stackTrace: stackTrace,
      );
    }

    return GeoCatalogResult(
      catalog: List<SaudiRegionCatalogEntry>.from(
        SaudiCities.regionCatalogFallback,
      ),
      usedFallback: true,
    );
  }

  static List<SaudiRegionCatalogEntry> normalizeRegionCatalog(dynamic data) {
    final rows = data is List
        ? data
        : (data is Map<String, dynamic> && data['results'] is List)
            ? data['results'] as List
            : const [];

    final normalized = <SaudiRegionCatalogEntry>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final item = Map<String, dynamic>.from(row);
      final regionName = _extractDisplayValue(
        item,
        const ['name_ar', 'name', 'region'],
      );
      if (regionName.isEmpty) continue;

      final citiesRaw = item['cities'];
      if (citiesRaw is! List) continue;

      final cities = citiesRaw
          .map((city) {
            if (city is String) return city.trim();
            if (city is Map) {
              return _extractDisplayValue(
                Map<String, dynamic>.from(city),
                const ['name_ar', 'name', 'city'],
              );
            }
            return '';
          })
          .where((city) => city.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

      if (cities.isEmpty) continue;
      normalized.add(SaudiRegionCatalogEntry(nameAr: regionName, cities: cities));
    }

    normalized.sort((left, right) => left.displayName.compareTo(right.displayName));
    return normalized;
  }

  static String _extractDisplayValue(
    Map<String, dynamic> item,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = item[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return '';
  }
}
