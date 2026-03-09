/// نموذج بانر الإعلان — يطابق HomeBannerSerializer
class BannerModel {
  final int id;
  final String? title;
  final String mediaType; // "image" | "video"
  final String? mediaUrl;
  final String? linkUrl;
  final int? providerId;
  final String? providerDisplayName;
  final int displayOrder;

  BannerModel({
    required this.id,
    this.title,
    this.mediaType = 'image',
    this.mediaUrl,
    this.linkUrl,
    this.providerId,
    this.providerDisplayName,
    this.displayOrder = 0,
  });

  factory BannerModel.fromJson(Map<String, dynamic> json) {
    return BannerModel(
      id: json['id'] as int? ?? 0,
      title: json['title'] as String?,
      mediaType: json['media_type'] as String? ?? 'image',
      mediaUrl: json['media_url'] as String?,
      linkUrl: json['link_url'] as String?,
      providerId: json['provider_id'] as int?,
      providerDisplayName: json['provider_display_name'] as String?,
      displayOrder: json['display_order'] as int? ?? 0,
    );
  }

  bool get isVideo => mediaType == 'video';
}
