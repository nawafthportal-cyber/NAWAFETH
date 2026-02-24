import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../constants/colors.dart';
import '../models/provider_portfolio_item.dart';
import '../services/providers_api.dart';
import 'provider_profile_screen.dart';

class HomeMediaViewerScreen extends StatefulWidget {
  final List<ProviderPortfolioItem> items;
  final int initialIndex;

  const HomeMediaViewerScreen({
    super.key,
    required this.items,
    this.initialIndex = 0,
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
  final Set<int> _followingProviderIds = <int>{};
  final Set<int> _favoriteBusy = <int>{};
  final Set<int> _followBusy = <int>{};
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

    // Following providers (backend: /providers/me/following/).
    try {
      final following = await _providersApi.getMyFollowingProviders();
      if (!mounted) return;
      setState(() {
        _followingProviderIds
          ..clear()
          ..addAll(following.map((e) => e.id));
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
  }

  Future<void> _toggleFollowProvider(ProviderPortfolioItem item) async {
    final providerId = item.providerId;
    if (_followBusy.contains(providerId)) return;

    final wasFollowing = _followingProviderIds.contains(providerId);
    setState(() {
      _followBusy.add(providerId);
      if (wasFollowing) {
        _followingProviderIds.remove(providerId);
      } else {
        _followingProviderIds.add(providerId);
      }
    });

    final ok = wasFollowing
        ? await _providersApi.unfollowProvider(providerId)
        : await _providersApi.followProvider(providerId);

    if (!mounted) return;
    setState(() {
      _followBusy.remove(providerId);
      if (!ok) {
        // Revert on failure.
        if (wasFollowing) {
          _followingProviderIds.add(providerId);
        } else {
          _followingProviderIds.remove(providerId);
        }
      }
    });
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
                final liked = _favoritePortfolioIds.contains(current.id);
                final saved = _followingProviderIds.contains(current.providerId);
                return Column(
                  children: [
                    GestureDetector(
                      onTap: () => _openProvider(current),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.deepPurple, width: 2.5),
                        ),
                        child: const CircleAvatar(
                          radius: 25,
                          child: Icon(Icons.person),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _CircleAction(
                      icon: liked ? Icons.thumb_up : Icons.thumb_up_outlined,
                      onTap: () => _toggleFavorite(current),
                    ),
                    const SizedBox(height: 14),
                    _CircleAction(
                      icon: saved ? Icons.bookmark : Icons.bookmark_border,
                      onTap: () => _toggleFollowProvider(current),
                    ),
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
  final VoidCallback onTap;

  const _CircleAction({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.24),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Icon(icon, color: AppColors.deepPurple),
      ),
    );
  }
}
