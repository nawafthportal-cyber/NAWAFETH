import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class PromoMediaTile extends StatefulWidget {
  final String? mediaUrl;
  final String mediaType;
  final double? height;
  final double borderRadius;
  final bool autoplay;
  final bool isActive;
  final bool showVideoBadge;
  final BoxFit fit;
  final Widget? fallback;

  const PromoMediaTile({
    super.key,
    required this.mediaUrl,
    required this.mediaType,
    this.height,
    this.borderRadius = 16,
    this.autoplay = true,
    this.isActive = true,
    this.showVideoBadge = false,
    this.fit = BoxFit.cover,
    this.fallback,
  });

  @override
  State<PromoMediaTile> createState() => _PromoMediaTileState();
}

class _PromoMediaTileState extends State<PromoMediaTile> {
  VideoPlayerController? _controller;
  bool _isInitializing = false;
  bool _hasVideoError = false;

  @override
  void initState() {
    super.initState();
    _syncVideoController();
  }

  @override
  void didUpdateWidget(covariant PromoMediaTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final mediaChanged =
        oldWidget.mediaUrl != widget.mediaUrl ||
        oldWidget.mediaType != widget.mediaType;
    if (mediaChanged) {
      _syncVideoController();
      return;
    }
    _applyPlaybackState();
  }

  Future<void> _syncVideoController() async {
    final url = (widget.mediaUrl ?? '').trim();
    if (widget.mediaType != 'video' || url.isEmpty) {
      await _disposeController();
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
        _hasVideoError = false;
      });
      return;
    }

    await _disposeController();
    if (!mounted) return;
    setState(() {
      _isInitializing = true;
      _hasVideoError = false;
    });

    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _controller = controller;

    try {
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.initialize();
      if (!mounted || _controller != controller) {
        await controller.dispose();
        return;
      }
      setState(() => _isInitializing = false);
      _applyPlaybackState();
    } catch (_) {
      if (_controller == controller) {
        await controller.dispose();
        _controller = null;
      }
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
        _hasVideoError = true;
      });
    }
  }

  void _applyPlaybackState() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (widget.autoplay && widget.isActive) {
      controller.play();
    } else {
      controller.pause();
    }
  }

  Future<void> _disposeController() async {
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      await controller.pause();
      await controller.dispose();
    }
  }

  @override
  void dispose() {
    unawaited(_disposeController());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final url = (widget.mediaUrl ?? '').trim();
    final child = ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.black.withValues(alpha: 0.78),
                  Colors.blueGrey.shade700,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          if (url.isEmpty)
            widget.fallback ?? const SizedBox.shrink()
          else if (widget.mediaType == 'video')
            _buildVideo()
          else
            _buildImage(url),
          if (widget.showVideoBadge && widget.mediaType == 'video')
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.play_arrow_rounded, color: Colors.white, size: 16),
                    SizedBox(width: 4),
                    Text(
                      'فيديو',
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
        ],
      ),
    );

    if (widget.height != null) {
      return SizedBox(height: widget.height, child: child);
    }
    return child;
  }

  Widget _buildImage(String url) {
    return CachedNetworkImage(
      imageUrl: url,
      fit: widget.fit,
      errorWidget: (_, __, ___) => widget.fallback ?? _fallbackSurface(Icons.broken_image_outlined),
      placeholder: (_, __) => const Center(child: CircularProgressIndicator(color: Colors.white)),
    );
  }

  Widget _buildVideo() {
    final controller = _controller;
    if (_hasVideoError) {
      return widget.fallback ?? _fallbackSurface(Icons.videocam_off_outlined);
    }
    if (_isInitializing || controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    return FittedBox(
      fit: widget.fit,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: controller.value.size.width,
        height: controller.value.size.height,
        child: VideoPlayer(controller),
      ),
    );
  }

  Widget _fallbackSurface(IconData icon) {
    return Center(
      child: Icon(
        icon,
        size: 34,
        color: Colors.white.withValues(alpha: 0.85),
      ),
    );
  }
}
