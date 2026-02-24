import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../constants/colors.dart';
import '../models/provider_portfolio_item.dart';
import '../services/providers_api.dart';
import '../utils/auth_guard.dart';
import 'provider_profile_screen.dart';

class HomeMediaViewerScreen extends StatefulWidget {
  final List<ProviderPortfolioItem> items;
  final int initialIndex;
  final bool favoritesEnabled;

  const HomeMediaViewerScreen({
    super.key,
    required this.items,
    this.initialIndex = 0,
    this.favoritesEnabled = true,
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
  final Set<int> _favoritePortfolioIds = <int>{};
  final Set<int> _likedProviderIds = <int>{};
  final Set<int> _favoriteBusy = <int>{};
  final Set<int> _providerLikeBusy = <int>{};
  bool _showSwipeHint = true;
  Timer? _hintTimer;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.items.length - 1);
    _pageController = PageController(initialPage: _index);
    _loadCurrentVideo();
    _primeSocialState();
    _hintTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _showSwipeHint = false);
    });
  }

  Future<void> _primeSocialState() async {
    if (widget.items.isEmpty) return;

    // Favorites == liked portfolio items (backend: /providers/me/favorites/).
    try {
      final favorites = await _providersApi.getMyFavoriteMedia();
      if (!mounted) return;
      setState(() {
        _favoritePortfolioIds
          ..clear()
          ..addAll(favorites.map((e) => e.id));
      });
    } catch (_) {
      // Unauthenticated / network failure: ignore.
    }

    // Provider likes (thumb-up on the right menu).
    try {
      final likedProviders = await _providersApi.getMyLikedProviders();
      if (!mounted) return;
      setState(() {
        _likedProviderIds
          ..clear()
          ..addAll(likedProviders.map((e) => e.id));
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

  Future<void> _toggleFavorite(ProviderPortfolioItem item) async {
    final authed = await checkAuth(context);
    if (!authed || !mounted) return;

    if (!widget.favoritesEnabled) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('المفضلة متاحة في معرض الخدمات فقط')),
      );
      return;
    }

    final itemId = item.id;
    if (_favoriteBusy.contains(itemId)) return;

    final wasFav = _favoritePortfolioIds.contains(itemId);
    setState(() {
      _favoriteBusy.add(itemId);
      if (wasFav) {
        _favoritePortfolioIds.remove(itemId);
      } else {
        _favoritePortfolioIds.add(itemId);
      }
    });

    final ok = wasFav
        ? await _providersApi.unlikePortfolioItem(itemId)
        : await _providersApi.likePortfolioItem(itemId);

    if (!mounted) return;
    setState(() {
      _favoriteBusy.remove(itemId);
      if (!ok) {
        // Revert on failure.
        if (wasFav) {
          _favoritePortfolioIds.add(itemId);
        } else {
          _favoritePortfolioIds.remove(itemId);
        }
      }
    });

    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر حفظ العنصر في المفضلة حالياً')),
      );
    }
  }

  Future<void> _toggleProviderLike(ProviderPortfolioItem item) async {
    final authed = await checkAuth(context);
    if (!authed || !mounted) return;

    final providerId = item.providerId;
    if (providerId <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('بيانات المزود غير متاحة حالياً')),
      );
      return;
    }
    if (_providerLikeBusy.contains(providerId)) return;

    final wasLiked = _likedProviderIds.contains(providerId);
    setState(() {
      _providerLikeBusy.add(providerId);
      if (wasLiked) {
        _likedProviderIds.remove(providerId);
      } else {
        _likedProviderIds.add(providerId);
      }
    });

    final ok = wasLiked
        ? await _providersApi.unlikeProvider(providerId)
        : await _providersApi.likeProvider(providerId);

    if (!mounted) return;
    setState(() {
      _providerLikeBusy.remove(providerId);
      if (!ok) {
        // Revert on failure.
        if (wasLiked) {
          _likedProviderIds.add(providerId);
        } else {
          _likedProviderIds.remove(providerId);
        }
      }
    });

    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر حفظ الإعجاب بالمزوّد حالياً')),
      );
    }
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
                final liked = _likedProviderIds.contains(current.providerId);
                final saved = _favoritePortfolioIds.contains(current.id);
                final likeBusy = _providerLikeBusy.contains(current.providerId);
                final saveBusy = _favoriteBusy.contains(current.id);
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
                      onTap: (!hasProviderTarget || likeBusy)
                          ? null
                          : () => _toggleProviderLike(current),
                      loading: likeBusy,
                    ),
                    if (widget.favoritesEnabled) ...[
                      const SizedBox(height: 14),
                      _CircleAction(
                        icon: saved ? Icons.bookmark : Icons.bookmark_border,
                        onTap: saveBusy ? null : () => _toggleFavorite(current),
                        loading: saveBusy,
                      ),
                    ],
                    const SizedBox(height: 14),
                    _CircleAction(
                      icon: Icons.home_rounded,
                      onTap: () => Navigator.pop(context),
                    ),
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
                  title,
                  maxLines: 2,
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

  const _CircleAction({
    required this.icon,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null && !loading;

    return InkWell(
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
    );
  }
}
