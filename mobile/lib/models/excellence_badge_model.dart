class ExcellenceBadgeModel {
  final String code;
  final String name;
  final String icon;
  final String color;
  final String? awardedAt;
  final String? validUntil;

  const ExcellenceBadgeModel({
    required this.code,
    required this.name,
    this.icon = '',
    this.color = '',
    this.awardedAt,
    this.validUntil,
  });

  factory ExcellenceBadgeModel.fromJson(Map<String, dynamic> json) {
    return ExcellenceBadgeModel(
      code: (json['code'] ?? '').toString().trim(),
      name: (json['name'] ?? json['title'] ?? '').toString().trim(),
      icon: (json['icon'] ?? '').toString().trim(),
      color: (json['color'] ?? '').toString().trim(),
      awardedAt: _asNullableString(json['awarded_at']),
      validUntil: _asNullableString(json['valid_until']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'name': name,
      'icon': icon,
      'color': color,
      'awarded_at': awardedAt,
      'valid_until': validUntil,
    };
  }

  static String? _asNullableString(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }
}
