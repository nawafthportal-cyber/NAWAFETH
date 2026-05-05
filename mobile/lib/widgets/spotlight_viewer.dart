import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/media_item_model.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/interactive_service.dart';
import '../screens/provider_profile_screen.dart';

/// عارض اللمحات بنمط TikTok — تمرير عمودي + شريط تفاعل جانبي
class SpotlightViewerPage extends StatefulWidget {
  final List<MediaItemModel> items;
  final int initialIndex;

  const SpotlightViewerPage({
    super.key,
    required this.items,
    this.initialIndex = 0,
  });

  @override
  State<SpotlightViewerPage> createState() => _SpotlightViewerPageState();
}

class _SpotlightViewerPageState extends State<SpotlightViewerPage> {
  late final PageController _pageController;
  VideoPlayerController? _videoController;
  int _currentIndex = 0;
  bool _isVideoReady = false;
  bool _hasVideoError = false;

  // حالات التفاعل
  bool _isLikeLoading = false;
  bool _isSaveLoading = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.items.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
    _initVideoController();
  }

  @override
  void dispose() {
    _videoController?.pause();
    _videoController?.dispose();
    _pageController.dispose();
    super.dispose();
  }

  MediaItemModel get _currentItem => widget.items[_currentIndex];

  // ──────────────────────────────────────────
  // 🎥 Video
  // ──────────────────────────────────────────

  Future<void> _initVideoController() async {
    _videoController?.pause();
    await _videoController?.dispose();
    _videoController = null;

    final item = _currentItem;
    if (!item.isVideo) {
      if (mounted) {
        setState(() {
          _isVideoReady = false;
          _hasVideoError = false;
        });
      }
      return;
    }

    final url = _resolveFileUrl(item);
    if (url == null || url.isEmpty) {
      if (mounted) {
        setState(() {
          _isVideoReady = false;
          _hasVideoError = true;
        });
      }
      return;
    }

    setState(() {
      _isVideoReady = false;
      _hasVideoError = false;
    });

    try {
      final controller = url.startsWith('http')
          ? VideoPlayerController.networkUrl(Uri.parse(url))
          : VideoPlayerController.asset(url);
      _videoController = controller;

      await controller.initialize();
      controller
        ..setLooping(true)
        ..setVolume(1.0)
        ..play();

      if (!mounted) return;
      setState(() => _isVideoReady = true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isVideoReady = false;
        _hasVideoError = true;
      });
    }
  }

  String? _resolveFileUrl(MediaItemModel item) {
    final raw = item.fileUrl?.trim();
    if (raw == null || raw.isEmpty) return null;
    return ApiClient.buildMediaUrl(raw) ?? raw;
  }

  // ──────────────────────────────────────────
  // ❤️ إعجاب
  // ──────────────────────────────────────────

  Future<void> _toggleLike() async {
    if (_isLikeLoading) return;
    final item = _currentItem;
    final wasLiked = item.isLiked;

    // Optimistic update
    setState(() {
      _isLikeLoading = true;
      item.isLiked = !wasLiked;
      item.likesCount += wasLiked ? -1 : 1;
      if (item.likesCount < 0) item.likesCount = 0;
    });
    item.rememberInteractionState();

    final success = await _toggleLikeBySource(item, wasLiked);

    if (!mounted) return;
    setState(() {
      _isLikeLoading = false;
      if (!success) {
        // Revert on failure
        item.isLiked = wasLiked;
        item.likesCount += wasLiked ? 1 : -1;
      }
    });
    item.rememberInteractionState();
  }

  // ──────────────────────────────────────────
  // 🔖 حفظ / مفضلة
  // ──────────────────────────────────────────

  Future<void> _toggleSave() async {
    if (_isSaveLoading) return;
    final item = _currentItem;
    final wasSaved = item.isSaved;

    setState(() {
      _isSaveLoading = true;
      item.isSaved = !wasSaved;
      item.savesCount += wasSaved ? -1 : 1;
      if (item.savesCount < 0) item.savesCount = 0;
    });
    item.rememberInteractionState();

    final success = await _toggleSaveBySource(item, wasSaved);

    if (!mounted) return;
    setState(() {
      _isSaveLoading = false;
      if (!success) {
        item.isSaved = wasSaved;
        item.savesCount += wasSaved ? 1 : -1;
      }
    });
    item.rememberInteractionState();
  }

  Future<bool> _toggleLikeBySource(MediaItemModel item, bool wasLiked) {
    if (item.source == MediaItemSource.portfolio) {
      return wasLiked
          ? InteractiveService.unlikePortfolio(item.id)
          : InteractiveService.likePortfolio(item.id);
    }
    return wasLiked
        ? InteractiveService.unlikeSpotlight(item.id)
        : InteractiveService.likeSpotlight(item.id);
  }

  Future<bool> _toggleSaveBySource(MediaItemModel item, bool wasSaved) {
    if (wasSaved) {
      return InteractiveService.unsaveItem(item);
    }
    if (item.source == MediaItemSource.portfolio) {
      return InteractiveService.savePortfolio(item.id);
    }
    return InteractiveService.saveSpotlight(item.id);
  }

  Future<void> _openCommentsSheet() async {
    final item = _currentItem;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _SpotlightCommentsSheet(
          item: item,
          onCountChanged: (count) {
            if (!mounted) return;
            setState(() {
              item.commentsCount = count;
            });
          },
        );
      },
    );
    if (!mounted) return;
    setState(() {});
  }

  // ──────────────────────────────────────────
  // 👤 الانتقال لملف المزود
  // ──────────────────────────────────────────

  void _goToProviderProfile() {
    final item = _currentItem;
    if (item.providerId <= 0) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProviderProfileScreen(
          providerId: item.providerId.toString(),
          providerName: item.providerDisplayName,
          providerImage: item.providerProfileImage,
        ),
      ),
    );
  }

  // ──────────────────────────────────────────
  // 🖼️ بناء واجهة العرض
  // ──────────────────────────────────────────

  Widget _buildMedia(MediaItemModel item) {
    if (item.isVideo) {
      if (_hasVideoError) {
        return const Center(
          child: Icon(Icons.error_outline, size: 40, color: Colors.white70),
        );
      }
      if (!_isVideoReady || _videoController == null) {
        return const Center(
          child: CircularProgressIndicator(color: Colors.white70),
        );
      }
      return Center(
        child: AspectRatio(
          aspectRatio: _videoController!.value.aspectRatio,
          child: VideoPlayer(_videoController!),
        ),
      );
    }

    final url = _resolveFileUrl(item);
    if (url == null || url.isEmpty) {
      return const Center(
        child: Icon(Icons.image_not_supported_outlined, size: 40, color: Colors.white70),
      );
    }
    return InteractiveViewer(
      child: Center(
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.contain,
          progressIndicatorBuilder: (_, __, progress) => Center(
            child: CircularProgressIndicator(
              color: Colors.white70,
              value: progress.progress,
            ),
          ),
          errorWidget: (_, __, ___) => const Icon(
            Icons.broken_image_outlined,
            size: 40,
            color: Colors.white70,
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────
  // ✖️ شريط علوي
  // ──────────────────────────────────────────

  Widget _buildTopBar() {
    final paddingTop = MediaQuery.of(context).padding.top;
    return Positioned(
      top: paddingTop + 8,
      left: 12,
      child: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.close, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────
  // 📝 شريط سفلي — اسم المزود + الوصف
  // ──────────────────────────────────────────

  Widget _buildBottomInfo(MediaItemModel item) {
    final caption = (item.caption ?? '').trim();
    final provider = item.providerDisplayName.trim();

    if (caption.isEmpty && provider.isEmpty) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: 0,
      // نترك مسافة للشريط الجانبي
      right: 72,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 24, 8, 24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.black.withValues(alpha: 0.7),
              Colors.black.withValues(alpha: 0.0),
            ],
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // اسم المزود مع الأيقونة
            if (provider.isNotEmpty)
              GestureDetector(
                onTap: _goToProviderProfile,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildSmallAvatar(item),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        provider,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (caption.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  caption,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 13,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// صورة مصغرة للمزود في أسفل اليسار
  Widget _buildSmallAvatar(MediaItemModel item) {
    final imageUrl = ApiClient.buildMediaUrl(item.providerProfileImage);
    return SizedBox(
      width: 28,
      height: 28,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
            ),
            child: ClipOval(
              child: imageUrl != null && imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _defaultAvatarIcon(14),
                    )
                  : _defaultAvatarIcon(14),
            ),
          ),
          ..._buildVerificationBadgeOverlays(
            item,
            badgeSize: 12,
            iconSize: 7,
            topOffset: -2,
            horizontalOffset: -2,
          ),
        ],
      ),
    );
  }

  Widget _defaultAvatarIcon(double size) {
    return Container(
      color: Colors.deepPurple,
      child: Icon(Icons.person, color: Colors.white, size: size),
    );
  }

  // ──────────────────────────────────────────
  // 📍 الشريط الجانبي — أيقونة مزود + إعجاب + حفظ (نمط TikTok)
  // ──────────────────────────────────────────

  Widget _buildSideActions(MediaItemModel item) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Positioned(
      right: 10,
      bottom: bottomPadding + 24,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 👤 صورة المزود
          _buildProviderAvatar(item),
          const SizedBox(height: 24),

          // ❤️ إعجاب
          _buildActionButton(
            icon: item.isLiked ? Icons.favorite : Icons.favorite_border,
            color: item.isLiked ? Colors.red : Colors.white,
            label: _formatCount(item.likesCount),
            onTap: _toggleLike,
          ),
          const SizedBox(height: 20),

          _buildActionButton(
            icon: Icons.mode_comment_outlined,
            color: Colors.white,
            label: _formatCount(item.commentsCount),
            onTap: _openCommentsSheet,
          ),
          const SizedBox(height: 20),

          // 🔖 حفظ / مفضلة
          _buildActionButton(
            icon: item.isSaved ? Icons.bookmark : Icons.bookmark_border,
            color: item.isSaved ? Colors.amber : Colors.white,
            label: _formatCount(item.savesCount),
            onTap: _toggleSave,
          ),
        ],
      ),
    );
  }

  /// صورة المزود — نقر للذهاب لملفه التعريفي
  Widget _buildProviderAvatar(MediaItemModel item) {
    final imageUrl = ApiClient.buildMediaUrl(item.providerProfileImage);

    return GestureDetector(
      onTap: _goToProviderProfile,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: imageUrl != null && imageUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => _defaultAvatarIcon(24),
                          )
                        : _defaultAvatarIcon(24),
                  ),
                ),
                ..._buildVerificationBadgeOverlays(
                  item,
                  badgeSize: 18,
                  iconSize: 11,
                  topOffset: -3,
                  horizontalOffset: -3,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildVerificationBadgeOverlays(
    MediaItemModel item, {
    required double badgeSize,
    required double iconSize,
    required double topOffset,
    required double horizontalOffset,
  }) {
    final overlays = <Widget>[];
    if (item.isVerifiedBlue) {
      overlays.add(
        Positioned(
          top: topOffset,
          left: horizontalOffset,
          child: _buildVerificationBadgeCircle(
            color: const Color(0xFF5DA9E9),
            badgeSize: badgeSize,
            iconSize: iconSize,
          ),
        ),
      );
    }
    if (item.isVerifiedGreen) {
      overlays.add(
        Positioned(
          top: topOffset,
          right: horizontalOffset,
          child: _buildVerificationBadgeCircle(
            color: const Color(0xFF4CAF50),
            badgeSize: badgeSize,
            iconSize: iconSize,
          ),
        ),
      );
    }
    return overlays;
  }

  Widget _buildVerificationBadgeCircle({
    required Color color,
    required double badgeSize,
    required double iconSize,
  }) {
    return Container(
      width: badgeSize,
      height: badgeSize,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.7),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 6,
          ),
        ],
      ),
      child: Icon(
        Icons.check_rounded,
        size: iconSize,
        color: Colors.white,
      ),
    );
  }

  /// زر تفاعل (إعجاب / حفظ) مع عداد
  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: color,
            size: 32,
            shadows: const [
              Shadow(color: Colors.black54, blurRadius: 6),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontFamily: 'Cairo',
              fontWeight: FontWeight.w600,
              shadows: [
                Shadow(color: Colors.black54, blurRadius: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// تنسيق الأرقام — 1000 → 1K، 1500 → 1.5K
  String _formatCount(int count) {
    if (count < 1000) return count.toString();
    if (count < 10000) {
      final k = count / 1000;
      return k == k.roundToDouble()
          ? '${k.toInt()}K'
          : '${k.toStringAsFixed(1)}K';
    }
    return '${(count / 1000).toInt()}K';
  }

  // ──────────────────────────────────────────
  // 🏗️ Build
  // ──────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text('لا توجد لمحات',
              style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // التمرير العمودي (مثل TikTok)
          PageView.builder(
            scrollDirection: Axis.vertical,
            controller: _pageController,
            itemCount: widget.items.length,
            onPageChanged: (index) {
              setState(() => _currentIndex = index);
              _initVideoController();
            },
            itemBuilder: (_, index) {
              return _buildMedia(widget.items[index]);
            },
          ),

          // شريط علوي — زر إغلاق
          _buildTopBar(),

          // شريط سفلي — معلومات المزود + الوصف
          _buildBottomInfo(_currentItem),

          // شريط جانبي — أيقونات التفاعل (إعجاب + حفظ + ملف المزود)
          _buildSideActions(_currentItem),

          // عنوان "لمحة" أعلى اليمين
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(
                'لمحة',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Cairo',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpotlightCommentsSheet extends StatefulWidget {
  final MediaItemModel item;
  final ValueChanged<int> onCountChanged;

  const _SpotlightCommentsSheet({
    required this.item,
    required this.onCountChanged,
  });

  @override
  State<_SpotlightCommentsSheet> createState() => _SpotlightCommentsSheetState();
}

class _SpotlightCommentsSheetState extends State<_SpotlightCommentsSheet> {
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode();

  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _isLoggedIn = false;
  List<_ViewerComment> _comments = <_ViewerComment>[];
  _ViewerComment? _replyTarget;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    final loggedIn = await AuthService.isLoggedIn();
    final response = await InteractiveService.fetchComments(widget.item);
    if (!mounted) return;
    final parsed = response.isSuccess
        ? _parseComments(response.data)
        : <_ViewerComment>[];
    setState(() {
      _isLoggedIn = loggedIn;
      _isLoading = false;
      _comments = parsed;
    });
    _emitCount();
    if (!response.isSuccess && mounted) {
      _showSnack(response.error ?? 'تعذر تحميل التعليقات حالياً.');
    }
  }

  List<_ViewerComment> _parseComments(dynamic data) {
    final rows = <Map<String, dynamic>>[];
    if (data is List) {
      rows.addAll(data.whereType<Map>().map((row) => Map<String, dynamic>.from(row)));
    } else if (data is Map && data['results'] is List) {
      rows.addAll((data['results'] as List)
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row)));
    }
    return rows.map(_ViewerComment.fromJson).toList(growable: true);
  }

  Future<void> _submitComment() async {
    if (_isSubmitting) return;
    if (!_isLoggedIn) {
      await _openLogin();
      return;
    }
    final body = _commentController.text.trim();
    if (body.isEmpty) return;

    setState(() => _isSubmitting = true);
    final response = await InteractiveService.createComment(
      widget.item,
      body: body,
      parentId: _replyTarget?.id,
    );
    if (!mounted) return;

    if (!response.isSuccess || response.data is! Map) {
      setState(() => _isSubmitting = false);
      _showSnack(response.error ?? 'تعذر نشر التعليق حالياً.');
      return;
    }

    final created = _ViewerComment.fromJson(Map<String, dynamic>.from(response.data as Map));
    setState(() {
      if (_replyTarget == null) {
        _comments.insert(0, created);
      } else {
        final parent = _findCommentById(_replyTarget!.id, _comments);
        if (parent != null) {
          parent.replies.add(created);
          parent.repliesCount = parent.replies.length;
        } else {
          _comments.insert(0, created);
        }
      }
      _commentController.clear();
      _replyTarget = null;
      _isSubmitting = false;
    });
    _emitCount();
    _showSnack(created.parentId == null ? 'تم نشر تعليقك.' : 'تم نشر الرد.');
  }

  Future<void> _toggleLike(_ViewerComment comment) async {
    if (!_isLoggedIn) {
      await _openLogin();
      return;
    }
    if (comment.isLikeBusy) return;
    final wasLiked = comment.isLiked;
    setState(() {
      comment.isLikeBusy = true;
      comment.isLiked = !wasLiked;
      comment.likesCount += wasLiked ? -1 : 1;
      if (comment.likesCount < 0) comment.likesCount = 0;
    });
    final response = wasLiked
        ? await InteractiveService.unlikeComment(widget.item, comment.id)
        : await InteractiveService.likeComment(widget.item, comment.id);
    if (!mounted) return;
    setState(() {
      comment.isLikeBusy = false;
      if (!response.isSuccess) {
        comment.isLiked = wasLiked;
        comment.likesCount += wasLiked ? 1 : -1;
        if (comment.likesCount < 0) comment.likesCount = 0;
        return;
      }
      final data = response.dataAsMap;
      if (data != null && data['likes_count'] != null) {
        comment.likesCount = _ViewerComment.asInt(data['likes_count']);
      }
    });
    if (!response.isSuccess) {
      _showSnack(response.error ?? 'تعذر تحديث الإعجاب بالتعليق حالياً.');
    }
  }

  Future<void> _deleteComment(_ViewerComment comment) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('حذف هذا التعليق؟', style: TextStyle(fontFamily: 'Cairo')),
              content: const Text(
                'سيؤدي ذلك إلى حذف التعليق وردوده نهائيًا.',
                style: TextStyle(fontFamily: 'Cairo'),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                  child: const Text('حذف', style: TextStyle(fontFamily: 'Cairo')),
                ),
              ],
            );
          },
        ) ??
        false;
    if (!confirmed) return;

    final response = await InteractiveService.deleteComment(widget.item, comment.id);
    if (!mounted) return;
    if (!response.isSuccess) {
      _showSnack(response.error ?? 'تعذر حذف التعليق حالياً.');
      return;
    }

    setState(() {
      _removeCommentById(comment.id, _comments);
      if (_replyTarget?.id == comment.id) {
        _replyTarget = null;
      }
    });
    _emitCount();
    _showSnack('تم حذف التعليق.');
  }

  Future<void> _reportComment(_ViewerComment comment) async {
    if (!_isLoggedIn) {
      await _openLogin();
      return;
    }
    final payload = await showModalBottomSheet<_CommentReportPayload>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _CommentReportSheet(comment: comment),
    );
    if (payload == null) return;

    final response = await InteractiveService.reportComment(
      widget.item,
      comment.id,
      reason: payload.reason,
      details: payload.details,
    );
    if (!mounted) return;
    if (!response.isSuccess) {
      _showSnack(response.error ?? 'تعذر إرسال بلاغ التعليق حالياً.');
      return;
    }
    _showSnack('تم إرسال بلاغ التعليق إلى فريق المحتوى.');
  }

  Future<void> _openLogin() async {
    await Navigator.of(context).pushNamed('/login');
    if (!mounted) return;
    final loggedIn = await AuthService.isLoggedIn();
    if (!mounted) return;
    setState(() => _isLoggedIn = loggedIn);
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, style: const TextStyle(fontFamily: 'Cairo'))),
    );
  }

  void _emitCount() {
    final total = _countAllComments(_comments);
    widget.item.commentsCount = total;
    widget.onCountChanged(total);
  }

  int _countAllComments(List<_ViewerComment> comments) {
    var total = 0;
    for (final comment in comments) {
      total += 1 + _countAllComments(comment.replies);
    }
    return total;
  }

  _ViewerComment? _findCommentById(int id, List<_ViewerComment> comments) {
    for (final comment in comments) {
      if (comment.id == id) return comment;
      final nested = _findCommentById(id, comment.replies);
      if (nested != null) return nested;
    }
    return null;
  }

  bool _removeCommentById(int id, List<_ViewerComment> comments) {
    for (var index = 0; index < comments.length; index += 1) {
      final comment = comments[index];
      if (comment.id == id) {
        comments.removeAt(index);
        return true;
      }
      if (_removeCommentById(id, comment.replies)) {
        comment.repliesCount = comment.replies.length;
        return true;
      }
    }
    return false;
  }

  String _relativeTime(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 'الآن';
    final parsed = DateTime.tryParse(raw)?.toLocal();
    if (parsed == null) return 'الآن';
    final diff = DateTime.now().difference(parsed);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inHours < 1) return 'منذ ${diff.inMinutes} د';
    if (diff.inDays < 1) return 'منذ ${diff.inHours} س';
    if (diff.inDays < 7) return 'منذ ${diff.inDays} يوم';
    return '${parsed.day}/${parsed.month}/${parsed.year}';
  }

  Widget _buildReplyBar() {
    if (_replyTarget == null) return const SizedBox.shrink();
    final targetLabel = (_replyTarget!.displayName.isNotEmpty
            ? _replyTarget!.displayName
            : _replyTarget!.username)
        .trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'الرد على ${targetLabel.isEmpty ? 'التعليق' : targetLabel}',
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _replyTarget = null),
            child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          12 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _commentController,
                focusNode: _commentFocusNode,
                minLines: 1,
                maxLines: 4,
                textDirection: TextDirection.rtl,
                decoration: InputDecoration(
                  hintText: _replyTarget == null
                      ? 'اكتب تعليقًا محترمًا...'
                      : 'اكتب ردك...',
                  hintStyle: const TextStyle(fontFamily: 'Cairo'),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: _isSubmitting ? null : _submitComment,
              style: FilledButton.styleFrom(
                minimumSize: const Size(54, 54),
                shape: const CircleBorder(),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommentTile(_ViewerComment comment, {bool isReply = false}) {
    final imageUrl = ApiClient.buildMediaUrl(comment.profileImage);
    final author = comment.displayName.isNotEmpty ? comment.displayName : comment.username;
    return Container(
      margin: EdgeInsetsDirectional.only(start: isReply ? 28 : 0, bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: isReply ? 16 : 18,
                backgroundColor: const Color(0xFFE2E8F0),
                backgroundImage: imageUrl != null && imageUrl.isNotEmpty
                    ? CachedNetworkImageProvider(imageUrl)
                    : null,
                child: imageUrl == null || imageUrl.isEmpty
                    ? Text(
                        author.isEmpty ? 'ن' : author.characters.first,
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            author.isEmpty ? 'مستخدم' : author,
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        if (comment.isVerifiedBlue || comment.isVerifiedGreen) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.verified_rounded,
                            size: 15,
                            color: comment.isVerifiedGreen
                                ? const Color(0xFF16A34A)
                                : const Color(0xFF2563EB),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      _relativeTime(comment.createdAt),
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'delete') {
                    _deleteComment(comment);
                  } else if (value == 'report') {
                    _reportComment(comment);
                  }
                },
                itemBuilder: (menuContext) => [
                  if (comment.isMine)
                    const PopupMenuItem<String>(
                      value: 'delete',
                      child: Text('حذف التعليق', style: TextStyle(fontFamily: 'Cairo')),
                    )
                  else
                    const PopupMenuItem<String>(
                      value: 'report',
                      child: Text('الإبلاغ عن التعليق', style: TextStyle(fontFamily: 'Cairo')),
                    ),
                ],
                icon: const Icon(Icons.more_horiz_rounded, color: Color(0xFF64748B)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            comment.body,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              height: 1.5,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              TextButton.icon(
                onPressed: comment.isLikeBusy ? null : () => _toggleLike(comment),
                icon: Icon(
                  comment.isLiked ? Icons.favorite : Icons.favorite_border,
                  color: comment.isLiked ? Colors.red.shade600 : const Color(0xFF475569),
                  size: 18,
                ),
                label: Text(
                  '${comment.likesCount}',
                  style: const TextStyle(fontFamily: 'Cairo'),
                ),
              ),
              if (!isReply)
                TextButton(
                  onPressed: () {
                    setState(() => _replyTarget = comment);
                    _commentFocusNode.requestFocus();
                  },
                  child: const Text(
                    'رد',
                    style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
          if (comment.replies.isNotEmpty) ...[
            const SizedBox(height: 4),
            ...comment.replies.map((reply) => _buildCommentTile(reply, isReply: true)),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        top: false,
        child: Container(
          height: MediaQuery.of(context).size.height * 0.88,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 48,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'التعليقات',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${widget.item.commentsCount}',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1D4ED8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _buildReplyBar(),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _comments.isEmpty
                        ? const Center(
                            child: Text(
                              'لا توجد تعليقات بعد. كن أول من يعلّق.',
                              style: TextStyle(fontFamily: 'Cairo', color: Color(0xFF64748B)),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            itemCount: _comments.length,
                            itemBuilder: (context, index) => _buildCommentTile(_comments[index]),
                          ),
              ),
              if (!_isLoggedIn)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: OutlinedButton.icon(
                    onPressed: _openLogin,
                    icon: const Icon(Icons.login_rounded),
                    label: const Text('سجّل الدخول لإضافة تعليق', style: TextStyle(fontFamily: 'Cairo')),
                  ),
                ),
              _buildComposer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommentReportSheet extends StatefulWidget {
  final _ViewerComment comment;

  const _CommentReportSheet({required this.comment});

  @override
  State<_CommentReportSheet> createState() => _CommentReportSheetState();
}

class _CommentReportSheetState extends State<_CommentReportSheet> {
  static const List<String> _reasons = <String>[
    'محتوى غير لائق',
    'سبام أو تضليل',
    'عنف أو إساءة',
    'انتهاك حقوق',
    'سبب آخر',
  ];

  late String _reason = _reasons.first;
  final TextEditingController _detailsController = TextEditingController();

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 48,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'الإبلاغ عن التعليق',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                'سيصل هذا البلاغ إلى فريق إدارة المحتوى مع توضيح أنه بلاغ على تعليق.',
                style: TextStyle(fontFamily: 'Cairo', color: Color(0xFF64748B), height: 1.5),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _reason,
                decoration: const InputDecoration(
                  labelText: 'سبب البلاغ',
                  labelStyle: TextStyle(fontFamily: 'Cairo'),
                  border: OutlineInputBorder(),
                ),
                items: _reasons
                    .map((reason) => DropdownMenuItem<String>(
                          value: reason,
                          child: Text(reason, style: const TextStyle(fontFamily: 'Cairo')),
                        ))
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _reason = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _detailsController,
                maxLines: 4,
                textDirection: TextDirection.rtl,
                decoration: const InputDecoration(
                  labelText: 'تفاصيل إضافية',
                  hintText: 'اكتب ملاحظة قصيرة لفريق المراجعة',
                  labelStyle: TextStyle(fontFamily: 'Cairo'),
                  hintStyle: TextStyle(fontFamily: 'Cairo'),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        Navigator.pop(
                          context,
                          _CommentReportPayload(
                            reason: _reason,
                            details: _detailsController.text.trim(),
                          ),
                        );
                      },
                      child: const Text('إرسال البلاغ', style: TextStyle(fontFamily: 'Cairo')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommentReportPayload {
  final String reason;
  final String details;

  const _CommentReportPayload({required this.reason, required this.details});
}

class _ViewerComment {
  final int id;
  final int? parentId;
  final String body;
  final String displayName;
  final String username;
  final String? profileImage;
  final String? createdAt;
  final bool isMine;
  final bool isVerifiedBlue;
  final bool isVerifiedGreen;
  int likesCount;
  bool isLiked;
  bool isLikeBusy = false;
  int repliesCount;
  final List<_ViewerComment> replies;

  _ViewerComment({
    required this.id,
    required this.parentId,
    required this.body,
    required this.displayName,
    required this.username,
    required this.profileImage,
    required this.createdAt,
    required this.isMine,
    required this.isVerifiedBlue,
    required this.isVerifiedGreen,
    required this.likesCount,
    required this.isLiked,
    required this.repliesCount,
    required this.replies,
  });

  factory _ViewerComment.fromJson(Map<String, dynamic> json) {
    final nested = json['replies'];
    final replies = nested is List
        ? nested
            .whereType<Map>()
            .map((row) => _ViewerComment.fromJson(Map<String, dynamic>.from(row)))
            .toList(growable: true)
        : <_ViewerComment>[];
    return _ViewerComment(
      id: asInt(json['id']),
      parentId: json['parent'] == null ? null : asInt(json['parent']),
      body: (json['body'] ?? '').toString(),
      displayName: (json['display_name'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      profileImage: json['profile_image']?.toString(),
      createdAt: json['created_at']?.toString(),
      isMine: json['is_mine'] == true,
      isVerifiedBlue: json['is_verified_blue'] == true,
      isVerifiedGreen: json['is_verified_green'] == true,
      likesCount: asInt(json['likes_count']),
      isLiked: json['is_liked'] == true,
      repliesCount: asInt(json['replies_count']),
      replies: replies,
    );
  }

  static int asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse('${value ?? ''}') ?? 0;
  }
}
