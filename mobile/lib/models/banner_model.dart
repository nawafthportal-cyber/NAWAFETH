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

  static String? _readString(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static int? _readInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse('${value ?? ''}');
  }

  factory BannerModel.fromJson(Map<String, dynamic> json) {
    return BannerModel(
      id: _readInt(json['id']) ?? 0,
      title: _readString(json['title']) ?? _readString(json['caption']),
      mediaType: _readString(json['media_type']) ?? _readString(json['file_type']) ?? 'image',
      mediaUrl: _readString(json['media_url']) ?? _readString(json['file_url']),
      linkUrl: _readString(json['link_url']) ?? _readString(json['redirect_url']),
      providerId: _readInt(json['provider_id']),
      providerDisplayName: _readString(json['provider_display_name']),
      displayOrder: _readInt(json['display_order']) ?? 0,
    );
  }

  bool get isVideo => mediaType == 'video';
}
