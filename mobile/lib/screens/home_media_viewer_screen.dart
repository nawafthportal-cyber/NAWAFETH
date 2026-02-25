import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../constants/colors.dart';
import '../models/provider_portfolio_item.dart';
import '../services/providers_api.dart';
import '../utils/auth_guard.dart';
import 'provider_profile_screen.dart';

class HomeMediaViewerScreen extends StatefulWidget {
  final List<ProviderPortfolioItem> items;
  final int initialIndex;
  final bool isSpotlightFeed;

  const HomeMediaViewerScreen({
    super.key,
    required this.items,
    this.initialIndex = 0,
    this.isSpotlightFeed = false,
  });

  @override
  State<HomeMediaViewerScreen> createState() => _HomeMediaViewerScreenState();
}

class _HomeMediaViewerScreenState extends State<HomeMediaViewerScreen> {
  late final PageController _pageController;
  late int _index;

  final ProvidersApi _providersApi = ProvidersApi();

  VideoPlayerController? _video;
  bool _videoReady = false;
  final Set<int> _likedMediaIds = <int>{};
  final Set<int> _savedMediaIds = <int>{};
  final Set<int> _likeBusy = <int>{};
  final Set<int> _saveBusy = <int>{};
  final Map<int, int> _likesCountByItem = <int, int>{};
  final Map<int, int> _savesCountByItem = <int, int>{};
  bool _showSwipeHint = true;
  Timer? _hintTimer;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.items.length - 1);
    _pageController = PageController(initialPage: _index);
    for (final item in widget.items) {
      _likesCountByItem[item.id] = item.likeCount;
      _savesCountByItem[item.id] = item.saveCount;
    }
    _loadCurrentVideo();
    _primeSocialState();
    _hintTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _showSwipeHint = false);
    });
  }

  Future<void> _primeSocialState() async {
    if (widget.items.isEmpty) return;

    // Item likes.
    try {
      final likes = widget.isSpotlightFeed
          ? await _providersApi.getMyLikedSpotlights()
          : await _providersApi.getMyLikedMedia();
      if (!mounted) return;
      setState(() {
        _likedMediaIds
          ..clear()
          ..addAll(likes.map((e) => e.id));
        for (final itemId in _likedMediaIds) {
          final current = _likesCountByItem[itemId] ?? 0;
          if (current <= 0) {
            _likesCountByItem[itemId] = 1;
          }
        }
      });
    } catch (_) {
      // Unauthenticated / network failure: ignore.
    }

    // Item saves.
    try {
      final saved = widget.isSpotlightFeed
          ? await _providersApi.getMyFavoriteSpotlights()
          : await _providersApi.getMyFavoriteMedia();
      if (!mounted) return;
      setState(() {
        _savedMediaIds
          ..clear()
          ..addAll(saved.map((e) => e.id));
        for (final itemId in _savedMediaIds) {
          final current = _savesCountByItem[itemId] ?? 0;
          if (current <= 0) {
            _savesCountByItem[itemId] = 1;
          }
        }
      });
    } catch (_) {
      // Unauthenticated / network failure: ignore.
    }
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _video?.dispose();
    _pageController.dispose();
    super.dispose();
  }

  bool _isVideo(ProviderPortfolioItem item) {
    return item.fileType.toLowerCase().contains('video');
  }

  Future<void> _loadCurrentVideo() async {
    if (!mounted) return;
    final item = widget.items[_index];
    final isVideo = _isVideo(item);

    await _video?.dispose();
    _video = null;
    _videoReady = false;
    if (!isVideo) {
      if (mounted) setState(() {});
      return;
    }

    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(item.fileUrl));
      _video = controller;
      await controller.initialize();
      controller
        ..setLooping(true)
        ..play();
      if (!mounted) return;
      setState(() {
        _videoReady = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _videoReady = false;
      });
    }
  }

  Future<void> _openProvider(ProviderPortfolioItem item) async {
    if (item.providerId <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('بيانات المزود غير متاحة حالياً')),
      );
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProviderProfileScreen(
          providerId: item.providerId.toString(),
          providerName: item.providerDisplayName,
        ),
      ),
    );
  }

  int _displayLikeCount(ProviderPortfolioItem item) {
    final current = _likesCountByItem[item.id] ?? item.likeCount;
    return current < 0 ? 0 : current;
  }

  int _displaySaveCount(ProviderPortfolioItem item) {
    final current = _savesCountByItem[item.id] ?? item.saveCount;
    return current < 0 ? 0 : current;
  }

  String _formatCounter(int value) {
    if (value < 1000) return '$value';
    if (value < 1000000) {
      final k = value / 1000;
      return k >= 10 ? '${k.toStringAsFixed(0)}K' : '${k.toStringAsFixed(1)}K';
    }
    final m = value / 1000000;
    return m >= 10 ? '${m.toStringAsFixed(0)}M' : '${m.toStringAsFixed(1)}M';
  }

  Future<void> _toggleLikeMedia(ProviderPortfolioItem item) async {
    final authed = await checkAuth(context);
    if (!authed || !mounted) return;

    final itemId = item.id;
    if (_likeBusy.contains(itemId)) return;

    final wasLiked = _likedMediaIds.contains(itemId);
    setState(() {
      _likeBusy.add(itemId);
      if (wasLiked) {
        _likedMediaIds.remove(itemId);
      } else {
        _likedMediaIds.add(itemId);
      }
    });

    final ok = widget.isSpotlightFeed
      ? (wasLiked
        ? await _providersApi.unlikeSpotlightItem(itemId)
        : await _providersApi.likeSpotlightItem(itemId))
      : (wasLiked
        ? await _providersApi.unlikePortfolioItem(itemId)
        : await _providersApi.likePortfolioItem(itemId));

    if (!mounted) return;
    setState(() {
      _likeBusy.remove(itemId);
      if (!ok) {
        if (wasLiked) {
          _likedMediaIds.add(itemId);
        } else {
          _likedMediaIds.remove(itemId);
        }
      } else {
        final current = _likesCountByItem[itemId] ?? item.likeCount;
        final next = wasLiked ? (current - 1) : (current + 1);
        _likesCountByItem[itemId] = next < 0 ? 0 : next;
      }
    });

    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر حفظ الإعجاب بهذا المحتوى حالياً')),
      );
    }
  }

  Future<void> _toggleSaveMedia(ProviderPortfolioItem item) async {
    final authed = await checkAuth(context);
    if (!authed || !mounted) return;

    final itemId = item.id;
    if (_saveBusy.contains(itemId)) return;

    final wasSaved = _savedMediaIds.contains(itemId);
    setState(() {
      _saveBusy.add(itemId);
      if (wasSaved) {
        _savedMediaIds.remove(itemId);
      } else {
        _savedMediaIds.add(itemId);
      }
    });

    final ok = widget.isSpotlightFeed
        ? (wasSaved
            ? await _providersApi.unsaveSpotlightItem(itemId)
            : await _providersApi.saveSpotlightItem(itemId))
        : (wasSaved
            ? await _providersApi.unsavePortfolioItem(itemId)
            : await _providersApi.savePortfolioItem(itemId));

    if (!mounted) return;
    setState(() {
      _saveBusy.remove(itemId);
      if (!ok) {
        if (wasSaved) {
          _savedMediaIds.add(itemId);
        } else {
          _savedMediaIds.remove(itemId);
        }
      } else {
        final current = _savesCountByItem[itemId] ?? item.saveCount;
        final next = wasSaved ? (current - 1) : (current + 1);
        _savesCountByItem[itemId] = next < 0 ? 0 : next;
      }
    });

    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر حفظ المحتوى في المحفوظات حالياً')),
      );
    }
  }

  Future<void> _openAdLink(ProviderPortfolioItem item) async {
    final raw = (item.redirectUrl ?? '').trim();
    if (raw.isEmpty) return;

    final uri = Uri.tryParse(raw);
    if (uri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('رابط الإعلان غير صالح')),
      );
      return;
    }

    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok || !mounted) return;
    } catch (_) {
      if (!mounted) return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تعذر فتح رابط الإعلان حالياً')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('لا يوجد محتوى')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            itemCount: widget.items.length,
            onPageChanged: (i) async {
              _index = i;
              await _loadCurrentVideo();
            },
            itemBuilder: (context, i) {
              final item = widget.items[i];
              final isVideo = _isVideo(item);
              final isCurrent = i == _index;

              return GestureDetector(
                onTap: () {
                  if (!isVideo) return;
                  final c = _video;
                  if (!isCurrent || c == null || !_videoReady) return;
                  if (c.value.isPlaying) {
                    c.pause();
                  } else {
                    c.play();
                  }
                  setState(() {});
                },
                child: Center(
                  child: isVideo
                      ? (!isCurrent || _video == null || !_videoReady)
                          ? const CircularProgressIndicator(color: Colors.white)
                          : AspectRatio(
                              aspectRatio: _video!.value.aspectRatio,
                              child: VideoPlayer(_video!),
                            )
                      : InteractiveViewer(
                          child: Image.network(
                            item.fileUrl,
                            fit: BoxFit.contain,
                            errorBuilder: (_, error, stackTrace) => const Icon(
                              Icons.broken_image_outlined,
                              color: Colors.white54,
                              size: 64,
                            ),
                          ),
                        ),
                ),
              );
            },
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 6,
            right: 10,
            child: IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          Positioned(
            right: 12,
            bottom: 110,
            child: Builder(
              builder: (context) {
                final current = widget.items[_index];
                final hasProviderTarget = current.providerId > 0;
                final liked = _likedMediaIds.contains(current.id);
                final saved = _savedMediaIds.contains(current.id);
                final likeBusy = _likeBusy.contains(current.id);
                final saveBusy = _saveBusy.contains(current.id);
                final likesCount = _formatCounter(_displayLikeCount(current));
                final savesCount = _formatCounter(_displaySaveCount(current));
                final hasRedirect = (current.redirectUrl ?? '').trim().isNotEmpty;
                return Column(
                  children: [
                    GestureDetector(
                      onTap: hasProviderTarget ? () => _openProvider(current) : null,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: hasProviderTarget
                                ? AppColors.deepPurple
                                : Colors.white54,
                            width: 2.5,
                          ),
                        ),
                        child: CircleAvatar(
                          radius: 25,
                          backgroundColor: hasProviderTarget
                              ? null
                              : Colors.grey.shade300,
                          child: Icon(
                            Icons.person,
                            color: hasProviderTarget
                                ? AppColors.deepPurple
                                : Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _CircleAction(
                      icon: liked ? Icons.thumb_up : Icons.thumb_up_outlined,
                      onTap: likeBusy ? null : () => _toggleLikeMedia(current),
                      loading: likeBusy,
                      label: likesCount,
                    ),
                    const SizedBox(height: 14),
                    _CircleAction(
                      icon: saved ? Icons.bookmark : Icons.bookmark_border,
                      onTap: saveBusy ? null : () => _toggleSaveMedia(current),
                      loading: saveBusy,
                      label: savesCount,
                    ),
                    const SizedBox(height: 14),
                    _CircleAction(
                      icon: Icons.home_rounded,
                      onTap: () => Navigator.pop(context),
                    ),
                    if (hasRedirect) ...[
                      const SizedBox(height: 14),
                      _CircleAction(
                        icon: Icons.open_in_new_rounded,
                        onTap: () => _openAdLink(current),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
          Positioned(
            left: 12,
            right: 64,
            bottom: 26,
            child: Builder(
              builder: (context) {
                final current = widget.items[_index];
                final title = current.caption.trim().isEmpty
                    ? current.providerDisplayName
                    : current.caption;
                return Text(
                  (current.redirectUrl ?? '').trim().isNotEmpty
                      ? '$title  •  إعلان قابل للفتح'
                      : title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                );
              },
            ),
          ),
          if (_showSwipeHint)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.42),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.swipe_up_rounded, color: Colors.white, size: 20),
                        SizedBox(width: 6),
                        Text(
                          'اسحب للأعلى للمحتوى التالي',
                          style: TextStyle(
                            color: Colors.white,
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CircleAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool loading;
  final String? label;

  const _CircleAction({
    required this.icon,
    required this.onTap,
    this.loading = false,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null && !loading;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(99),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: disabled ? Colors.white70 : Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.24),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: AppColors.deepPurple,
                    ),
                  )
                : Icon(
                    icon,
                    color: disabled ? Colors.grey : AppColors.deepPurple,
                  ),
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 4),
          Text(
            label!,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
            ),
          ),
        ],
      ],
    );
  }
}
