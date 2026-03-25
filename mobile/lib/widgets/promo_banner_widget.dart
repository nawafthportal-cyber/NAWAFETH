import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class PromoBannerWidget extends StatefulWidget {
  final String? mediaUrl;
  final bool isVideo;
  final bool isActive;
  final bool autoplay;
  final bool stretchToParent;
  final BoxFit mediaFit;
  final EdgeInsetsGeometry contentPadding;
  final double mediaOverlayOpacity;
  final String? title;
  final String? subtitle;
  final double borderRadius;
  final Widget? fallback;

  const PromoBannerWidget({
    super.key,
    required this.mediaUrl,
    required this.isVideo,
    this.isActive = true,
    this.autoplay = true,
    this.stretchToParent = false,
    this.mediaFit = BoxFit.cover,
    this.contentPadding = EdgeInsets.zero,
    this.mediaOverlayOpacity = 0.4,
    this.title,
    this.subtitle,
    this.borderRadius = 16,
    this.fallback,
  });

  @override
  State<PromoBannerWidget> createState() => _PromoBannerWidgetState();
}

class _PromoBannerWidgetState extends State<PromoBannerWidget> {
  VideoPlayerController? _controller;
  bool _isLoading = false;
  bool _hasVideoError = false;

  @override
  void initState() {
    super.initState();
    _syncVideoController();
  }

  @override
  void didUpdateWidget(covariant PromoBannerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final mediaChanged =
        oldWidget.mediaUrl != widget.mediaUrl || oldWidget.isVideo != widget.isVideo;
    if (mediaChanged) {
      _syncVideoController();
      return;
    }
    _applyPlaybackState();
  }

  Future<void> _syncVideoController() async {
    final url = (widget.mediaUrl ?? '').trim();
    if (!widget.isVideo || url.isEmpty) {
      await _disposeController();
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasVideoError = false;
      });
      return;
    }

    await _disposeController();
    if (!mounted) return;
    setState(() {
      _isLoading = true;
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
      setState(() => _isLoading = false);
      _applyPlaybackState();
    } catch (_) {
      if (_controller == controller) {
        await controller.dispose();
        _controller = null;
      }
      if (!mounted) return;
      setState(() {
        _isLoading = false;
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
    final hasTitle = (widget.title ?? '').trim().isNotEmpty;
    final hasSubtitle = (widget.subtitle ?? '').trim().isNotEmpty;

    final bannerLayers = ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (url.isEmpty)
            _fallback()
          else if (widget.isVideo)
            _buildVideoLayers()
          else
            _buildImage(url),
          if (widget.mediaOverlayOpacity > 0)
            Positioned.fill(
              child: ColoredBox(color: Colors.black.withValues(alpha: widget.mediaOverlayOpacity)),
            ),
          if (hasTitle || hasSubtitle)
            Positioned.fill(
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (hasTitle)
                        Text(
                          widget.title!.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'Cairo',
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      if (hasSubtitle)
                        Text(
                          widget.subtitle!.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    final padded = Padding(
      padding: widget.contentPadding,
      child: bannerLayers,
    );

    if (widget.stretchToParent) {
      return padded;
    }

    return AspectRatio(
      aspectRatio: 16 / 7,
      child: padded,
    );
  }

  Widget _buildImage(String url) {
    return Image.network(
      url,
      fit: widget.mediaFit,
      errorBuilder: (_, __, ___) => _fallback(),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const Center(child: CircularProgressIndicator(color: Colors.white));
      },
    );
  }

  Widget _buildVideoLayers() {
    final controller = _controller;
    if (_hasVideoError) return _fallback();
    if (_isLoading || controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    final size = controller.value.size;
    final mainFit = widget.mediaFit;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: VideoPlayer(controller),
            ),
          ),
        ),
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.3)),
          ),
        ),
        Positioned.fill(
          child: FittedBox(
            fit: mainFit,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: VideoPlayer(controller),
            ),
          ),
        ),
      ],
    );
  }

  Widget _fallback() {
    return widget.fallback ??
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1F2937), Color(0xFF374151)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SizedBox.expand(),
        );
  }
}
