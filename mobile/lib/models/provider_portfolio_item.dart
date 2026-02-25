import '../services/api_config.dart';

class ProviderPortfolioItem {
  final int id;
  final int providerId;
  final String providerDisplayName;
  final String? providerUsername;
  final String fileType; // image | video
  final String fileUrl;
  final String? thumbnailUrl;
  final String caption;
  final String? redirectUrl;
  final int likeCount;
  final int saveCount;
  final DateTime createdAt;

  const ProviderPortfolioItem({
    required this.id,
    required this.providerId,
    required this.providerDisplayName,
    required this.providerUsername,
    required this.fileType,
    required this.fileUrl,
    required this.thumbnailUrl,
    required this.caption,
    this.redirectUrl,
    required this.likeCount,
    required this.saveCount,
    required this.createdAt,
  });

  factory ProviderPortfolioItem.fromJson(Map<String, dynamic> json) {
    String normalizeMediaUrl(dynamic raw) {
      final s = (raw ?? '').toString().trim();
      if (s.isEmpty) return '';
      if (s.startsWith('http://') || s.startsWith('https://')) return s;
      if (s.startsWith('/')) return '${ApiConfig.baseUrl}$s';
      return s;
    }

    return ProviderPortfolioItem(
      id: json['id'],
      providerId: json['provider_id'],
      providerDisplayName: (json['provider_display_name'] ?? '').toString(),
      providerUsername: (json['provider_username'] ?? '').toString().trim().isEmpty
          ? null
          : (json['provider_username'] ?? '').toString(),
      fileType: (json['file_type'] ?? 'image').toString(),
      fileUrl: normalizeMediaUrl(json['file_url']),
      thumbnailUrl: (() {
        final raw = json['thumbnail_url'] ??
            json['preview_image_url'] ??
            json['poster_url'] ??
            json['video_thumbnail_url'];
        final normalized = normalizeMediaUrl(raw);
        return normalized.isEmpty ? null : normalized;
      })(),
      caption: (json['caption'] ?? '').toString(),
      redirectUrl: (json['redirect_url'] ?? '').toString().trim().isEmpty
          ? null
          : (json['redirect_url'] ?? '').toString().trim(),
      likeCount: json['likes_count'] is num
          ? (json['likes_count'] as num).toInt()
          : int.tryParse('${json['likes_count'] ?? ''}') ?? 0,
        saveCount: json['saves_count'] is num
          ? (json['saves_count'] as num).toInt()
          : int.tryParse('${json['saves_count'] ?? ''}') ?? 0,
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
