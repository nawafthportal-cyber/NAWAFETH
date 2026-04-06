/// خدمة الاشتراكات — /api/subscriptions/*
library;

import 'api_client.dart';

class SubscriptionsService {
  static String? _asString(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static List<Map<String, dynamic>> _extractList(dynamic data) {
    if (data is List) {
      return data
          .whereType<Map>()
          .map(
            (item) =>
                item.map((key, value) => MapEntry(key.toString(), value)),
          )
          .toList();
    }
    if (data is Map && data['results'] is List) {
      final results = data['results'] as List;
      return results
          .whereType<Map>()
          .map(
            (item) =>
                item.map((key, value) => MapEntry(key.toString(), value)),
          )
          .toList();
    }
    return const <Map<String, dynamic>>[];
  }

  static int _subscriptionRank(String? status) {
    switch ((status ?? '').trim().toLowerCase()) {
      case 'active':
        return 0;
      case 'grace':
        return 1;
      case 'awaiting_review':
        return 2;
      case 'pending_payment':
        return 3;
      default:
        return 9;
    }
  }

  static Map<String, dynamic>? selectPreferredSubscription(
    List<Map<String, dynamic>> subscriptions,
  ) {
    if (subscriptions.isEmpty) return null;
    var best = subscriptions.first;
    var bestRank = _subscriptionRank(
      _asString(best['provider_status_code']) ?? _asString(best['status']),
    );
    for (final sub in subscriptions) {
      final rank = _subscriptionRank(
        _asString(sub['provider_status_code']) ?? _asString(sub['status']),
      );
      if (rank < bestRank) {
        best = sub;
        bestRank = rank;
        if (rank == 0) break;
      }
    }
    return best;
  }

  static String planTitleFromSubscription(Map<String, dynamic>? subscription) {
    if (subscription == null) return 'الباقة المجانية';
    final plan = subscription['plan'];
    if (plan is Map) {
      return _asString(plan['title']) ??
          _asString(plan['name']) ??
          _asString(subscription['plan_title']) ??
          _asString(subscription['plan_name']) ??
          'الباقة المجانية';
    }
    return _asString(subscription['plan_title']) ??
        _asString(subscription['plan_name']) ??
        'الباقة المجانية';
  }

  static String subscriptionStatusLabel(String? status) {
    switch ((status ?? '').trim().toLowerCase()) {
      case 'active':
        return 'نشط';
      case 'grace':
        return 'فترة سماح';
      case 'awaiting_review':
        return 'بانتظار المراجعة';
      case 'pending_payment':
        return 'بانتظار الدفع';
      case 'expired':
        return 'منتهي';
      case 'cancelled':
        return 'ملغي';
      default:
        return 'غير معروف';
    }
  }

  static Map<String, dynamic> planOffer(Map<String, dynamic>? plan) {
    final raw = plan?['provider_offer'];
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return const <String, dynamic>{};
  }

  static Map<String, dynamic> planAction(Map<String, dynamic>? plan) {
    final offer = planOffer(plan);
    final raw = offer['cta'];
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return const <String, dynamic>{};
  }

  static String planDisplayTitle(Map<String, dynamic>? plan) {
    final offer = planOffer(plan);
    return _asString(offer['plan_name']) ??
        _asString(plan?['title']) ??
        _asString(plan?['name']) ??
        'الباقة';
  }

  static DateTime? parseSubscriptionEndAt(Map<String, dynamic>? subscription) {
    final raw = _asString(subscription?['end_at'] ?? subscription?['end_date']);
    if (raw == null) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  /// جلب قائمة الباقات المتاحة
  static Future<List<Map<String, dynamic>>> getPlans() async {
    final res = await ApiClient.get('/api/subscriptions/plans/');
    if (!res.isSuccess) return [];
    return _extractList(res.data);
  }

  /// جلب اشتراكاتي
  static Future<List<Map<String, dynamic>>> mySubscriptions() async {
    final res = await ApiClient.get('/api/subscriptions/my/');
    if (!res.isSuccess) return [];
    return _extractList(res.data);
  }

  /// إنشاء اشتراك جديد
  static Future<ApiResponse> subscribe(int planId) async {
    return ApiClient.post('/api/subscriptions/subscribe/$planId/');
  }
}
