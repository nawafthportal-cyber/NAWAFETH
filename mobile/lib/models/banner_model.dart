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
  final int mobileScale;
  final int tabletScale;
  final int desktopScale;

  BannerModel({
    required this.id,
    this.title,
    this.mediaType = 'image',
    this.mediaUrl,
    this.linkUrl,
    this.providerId,
    this.providerDisplayName,
    this.displayOrder = 0,
    this.mobileScale = 100,
    this.tabletScale = 100,
    this.desktopScale = 100,
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

  static int _readScale(dynamic value, {required int fallback, required int minimum, required int maximum}) {
    final parsed = _readInt(value);
    if (parsed == null) return fallback;
    if (parsed < minimum) return minimum;
    if (parsed > maximum) return maximum;
    return parsed;
  }

  factory BannerModel.fromJson(Map<String, dynamic> json) {
    final mobileScale = _readScale(
      json['mobile_scale'],
      fallback: 100,
      minimum: 40,
      maximum: 140,
    );
    final tabletScale = _readScale(
      json['tablet_scale'],
      fallback: mobileScale,
      minimum: 40,
      maximum: 150,
    );
    return BannerModel(
      id: _readInt(json['id']) ?? 0,
      title: _readString(json['title']) ?? _readString(json['caption']),
      mediaType: _readString(json['media_type']) ?? _readString(json['file_type']) ?? 'image',
      mediaUrl: _readString(json['media_url']) ?? _readString(json['file_url']),
      linkUrl: _readString(json['link_url']) ?? _readString(json['redirect_url']),
      providerId: _readInt(json['provider_id']),
      providerDisplayName: _readString(json['provider_display_name']),
      displayOrder: _readInt(json['display_order']) ?? 0,
      mobileScale: mobileScale,
      tabletScale: tabletScale,
      desktopScale: _readScale(
        json['desktop_scale'],
        fallback: tabletScale,
        minimum: 40,
        maximum: 160,
      ),
    );
  }

  bool get isVideo => mediaType == 'video';

  double scaleForWidth(double width) {
    final safeWidth = width.isFinite && width > 0 ? width : 390;
    final mobile = mobileScale.toDouble();
    final tablet = tabletScale.toDouble();
    final desktop = desktopScale.toDouble();
    if (safeWidth <= 480) return mobile / 100;
    if (safeWidth <= 820) {
      return _interpolate(mobile, tablet, (safeWidth - 480) / 340) / 100;
    }
    if (safeWidth <= 1600) {
      return _interpolate(tablet, desktop, (safeWidth - 820) / 780) / 100;
    }
    return desktop / 100;
  }

  static double _interpolate(double start, double end, double t) {
    final safeT = t < 0 ? 0.0 : (t > 1 ? 1.0 : t);
    return start + ((end - start) * safeT);
  }
}
