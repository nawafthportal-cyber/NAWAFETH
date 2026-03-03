/// نموذج بيانات عنصر المعرض أو الأضواء المحفوظ
///
/// يطابق ProviderPortfolioItemSerializer و ProviderSpotlightItemSerializer
/// يُستخدم في تبويب "مفضلتي" في شاشة التفاعلي
class MediaItemModel {
  static final Map<String, _MediaItemInteractionSnapshot>
      _interactionSnapshots = <String, _MediaItemInteractionSnapshot>{};

  final int id;
  final int providerId;
  final String providerDisplayName;
  final String? providerUsername;
  final String? providerProfileImage;
  final String fileType; // image, video
  final String? fileUrl;
  final String? thumbnailUrl;
  final String? caption;
  int likesCount;
  int savesCount;
  bool isLiked;
  bool isSaved;
  final String? createdAt;

  /// نوع المحتوى — portfolio أو spotlight
  final MediaItemSource source;

  MediaItemModel({
    required this.id,
    required this.providerId,
    required this.providerDisplayName,
    this.providerUsername,
    this.providerProfileImage,
    required this.fileType,
    this.fileUrl,
    this.thumbnailUrl,
    this.caption,
    this.likesCount = 0,
    this.savesCount = 0,
    this.isLiked = false,
    this.isSaved = false,
    this.createdAt,
    required this.source,
  });

  static String _interactionKey(MediaItemSource source, int id) {
    return '${source.name}:$id';
  }

  static void rememberInteraction({
    required MediaItemSource source,
    required int id,
    required bool isLiked,
    required bool isSaved,
    required int likesCount,
    required int savesCount,
  }) {
    if (id <= 0) return;
    _interactionSnapshots[_interactionKey(source, id)] =
        _MediaItemInteractionSnapshot(
      isLiked: isLiked,
      isSaved: isSaved,
      likesCount: likesCount < 0 ? 0 : likesCount,
      savesCount: savesCount < 0 ? 0 : savesCount,
    );
  }

  static void applyInteractionOverrides(Iterable<MediaItemModel> items) {
    for (final item in items) {
      item.applyInteractionOverride();
    }
  }

  void rememberInteractionState() {
    rememberInteraction(
      source: source,
      id: id,
      isLiked: isLiked,
      isSaved: isSaved,
      likesCount: likesCount,
      savesCount: savesCount,
    );
  }

  void applyInteractionOverride() {
    if (id <= 0) return;
    final snapshot = _interactionSnapshots[_interactionKey(source, id)];
    if (snapshot == null) return;

    isLiked = snapshot.isLiked;
    isSaved = snapshot.isSaved;
    likesCount = snapshot.likesCount;
    savesCount = snapshot.savesCount;
  }

  factory MediaItemModel.fromJson(
    Map<String, dynamic> json, {
    MediaItemSource source = MediaItemSource.portfolio,
  }) {
    final model = MediaItemModel(
      id: json['id'] as int? ?? 0,
      providerId: json['provider_id'] as int? ?? 0,
      providerDisplayName: json['provider_display_name'] as String? ?? '',
      providerUsername: json['provider_username'] as String?,
      providerProfileImage: json['provider_profile_image'] as String?,
      fileType: json['file_type'] as String? ?? 'image',
      fileUrl: json['file_url'] as String?,
      thumbnailUrl: json['thumbnail_url'] as String?,
      caption: json['caption'] as String?,
      likesCount: json['likes_count'] as int? ?? 0,
      savesCount: json['saves_count'] as int? ?? 0,
      isLiked: json['is_liked'] as bool? ?? false,
      isSaved: json['is_saved'] as bool? ?? false,
      createdAt: json['created_at'] as String?,
      source: source,
    );
    model.applyInteractionOverride();
    model.rememberInteractionState();
    return model;
  }

  /// هل العنصر صورة
  bool get isImage => fileType == 'image';

  /// هل العنصر فيديو
  bool get isVideo => fileType == 'video';
}

/// مصدر المحتوى — معرض الأعمال أو الأضواء
enum MediaItemSource { portfolio, spotlight }

class _MediaItemInteractionSnapshot {
  final bool isLiked;
  final bool isSaved;
  final int likesCount;
  final int savesCount;

  const _MediaItemInteractionSnapshot({
    required this.isLiked,
    required this.isSaved,
    required this.likesCount,
    required this.savesCount,
  });
}
