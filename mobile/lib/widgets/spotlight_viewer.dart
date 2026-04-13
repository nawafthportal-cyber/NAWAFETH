import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/media_item_model.dart';
import '../services/api_client.dart';
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
    return Container(
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
        ],
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
