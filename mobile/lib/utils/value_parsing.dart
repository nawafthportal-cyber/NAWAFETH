library;

const List<String> _defaultPreferredTextKeys = <String>[
  'ar',
  'text',
  'label',
  'title',
  'name',
  'value',
  'display_name',
  'display',
  'value_text',
  'display_value',
  'message',
  'en',
];

String displayText(
  dynamic value, {
  String fallback = '',
  List<String>? preferredTextKeys,
}) {
  if (value == null) return fallback;

  if (value is String) {
    final text = value.trim();
    return text.isEmpty ? fallback : text;
  }

  if (value is bool) {
    return value ? 'نعم' : 'لا';
  }

  if (value is num) {
    return value.toString();
  }

  if (value is List) {
    final parts = value
        .map((item) => displayText(item))
        .where((item) => item.isNotEmpty)
        .toList();
    return parts.isEmpty ? fallback : parts.join('، ');
  }

  if (value is Map) {
    final keys = preferredTextKeys ?? _defaultPreferredTextKeys;
    for (final key in keys) {
      if (value.containsKey(key)) {
        final text = displayText(value[key]);
        if (text.isNotEmpty) return text;
      }
    }

    for (final entry in value.entries) {
      final text = displayText(entry.value);
      if (text.isNotEmpty) return text;
    }

    return fallback;
  }

  final text = value.toString().trim();
  return text.isEmpty ? fallback : text;
}

bool asBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;

  final normalized = displayText(value).toLowerCase();
  return normalized == 'true' ||
      normalized == '1' ||
      normalized == 'yes' ||
      normalized == 'y' ||
      normalized == 'on' ||
      normalized == 'نعم';
}
