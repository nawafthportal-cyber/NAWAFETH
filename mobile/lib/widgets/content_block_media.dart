import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class ContentBlockMedia extends StatefulWidget {
  final String? mediaUrl;
  final String mediaType;
  final double aspectRatio;
  final double borderRadius;
  final bool autoplay;
  final bool isActive;
  final BoxFit imageFit;
  final BoxFit videoFit;
  final Widget? fallback;

  const ContentBlockMedia({
    super.key,
    required this.mediaUrl,
    required this.mediaType,
    this.aspectRatio = 16 / 9,
    this.borderRadius = 24,
    this.autoplay = true,
    this.isActive = true,
    this.imageFit = BoxFit.cover,
    this.videoFit = BoxFit.cover,
    this.fallback,
  });

  @override
  State<ContentBlockMedia> createState() => _ContentBlockMediaState();
}

class _ContentBlockMediaState extends State<ContentBlockMedia> {
  VideoPlayerController? _controller;
  bool _isInitializing = false;
  bool _hasVideoError = false;

  @override
  void initState() {
    super.initState();
    _syncVideoController();
  }

  @override
  void didUpdateWidget(covariant ContentBlockMedia oldWidget) {
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
      if (mounted) {
        setState(() {
          _hasVideoError = false;
          _isInitializing = false;
        });
      }
      return;
    }

    await _disposeController();
    if (!mounted) return;
    setState(() {
      _hasVideoError = false;
      _isInitializing = true;
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
      if (mounted) {
        setState(() {
          _hasVideoError = true;
          _isInitializing = false;
        });
      }
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
    if (url.isEmpty) {
      return widget.fallback ?? const SizedBox.shrink();
    }

    if (widget.mediaType == 'video') {
      return _buildVideo();
    }
    return _buildImage(url);
  }

  Widget _buildImage(String url) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.deepPurple.shade100,
                    Colors.deepPurple.shade50,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            CachedNetworkImage(
              imageUrl: url,
              fit: widget.imageFit,
              placeholder: (_, __) => const Center(child: CircularProgressIndicator()),
              errorWidget: (_, __, ___) => _buildFallbackSurface(
                icon: Icons.broken_image_outlined,
                label: 'تعذر تحميل الصورة',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideo() {
    final controller = _controller;
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: AspectRatio(
        aspectRatio:
            controller != null && controller.value.isInitialized
                ? controller.value.aspectRatio
                : widget.aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.82),
                    Colors.deepPurple.shade700,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            if (_hasVideoError)
              _buildFallbackSurface(
                icon: Icons.videocam_off_outlined,
                label: 'تعذر تحميل الفيديو',
              )
            else if (_isInitializing || controller == null || !controller.value.isInitialized)
              const Center(child: CircularProgressIndicator(color: Colors.white))
            else
              FittedBox(
                fit: widget.videoFit,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: controller.value.size.width,
                  height: controller.value.size.height,
                  child: VideoPlayer(controller),
                ),
              ),
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
      ),
    );
  }

  Widget _buildFallbackSurface({
    required IconData icon,
    required String label,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 34, color: Colors.white70),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'Cairo',
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
