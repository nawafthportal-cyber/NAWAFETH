import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class PromoBannerWidget extends StatefulWidget {
  final String? mediaUrl;
  final bool isVideo;
  final bool isActive;
  final bool autoplay;
  final bool loopVideo;
  final VoidCallback? onVideoEnded;
  final bool stretchToParent;
  final BoxFit mediaFit;
  final EdgeInsetsGeometry contentPadding;
  final double mediaOverlayOpacity;
  final String? title;
  final String? subtitle;
  final double borderRadius;
  final Widget? fallback;
  final bool showBackdrop;
  final double backdropBlurSigma;
  final double backdropOverlayOpacity;
  final double backdropScale;
  final Alignment mediaAlignment;

  const PromoBannerWidget({
    super.key,
    required this.mediaUrl,
    required this.isVideo,
    this.isActive = true,
    this.autoplay = true,
    this.loopVideo = true,
    this.onVideoEnded,
    this.stretchToParent = false,
    this.mediaFit = BoxFit.cover,
    this.contentPadding = EdgeInsets.zero,
    this.mediaOverlayOpacity = 0.4,
    this.title,
    this.subtitle,
    this.borderRadius = 16,
    this.fallback,
    this.showBackdrop = false,
    this.backdropBlurSigma = 12,
    this.backdropOverlayOpacity = 0.3,
    this.backdropScale = 1.08,
    this.mediaAlignment = Alignment.center,
  });

  @override
  State<PromoBannerWidget> createState() => _PromoBannerWidgetState();
}

class _PromoBannerWidgetState extends State<PromoBannerWidget> {
  VideoPlayerController? _controller;
  bool _isLoading = false;
  bool _hasVideoError = false;
  bool _videoEndNotified = false;

  @override
  void initState() {
    super.initState();
    _syncVideoController();
  }

  @override
  void didUpdateWidget(covariant PromoBannerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final mediaChanged = oldWidget.mediaUrl != widget.mediaUrl ||
        oldWidget.isVideo != widget.isVideo;
    if (mediaChanged) {
      _syncVideoController();
      return;
    }
    if (oldWidget.loopVideo != widget.loopVideo) {
      final controller = _controller;
      if (controller != null) {
        unawaited(controller.setLooping(widget.loopVideo));
      }
    }
    if (!oldWidget.isActive && widget.isActive) {
      _videoEndNotified = false;
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
    _videoEndNotified = false;
    controller.addListener(_handleVideoProgress);

    try {
      await controller.setLooping(widget.loopVideo);
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
      if (!widget.loopVideo && !controller.value.isPlaying) {
        _videoEndNotified = false;
        if (controller.value.position > Duration.zero) {
          unawaited(controller.seekTo(Duration.zero));
        }
      }
      controller.play();
    } else {
      controller.pause();
    }
  }

  void _handleVideoProgress() {
    if (widget.loopVideo || !widget.isActive) return;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final duration = controller.value.duration;
    if (duration <= Duration.zero) return;
    final position = controller.value.position;
    final nearEnd = position >= duration - const Duration(milliseconds: 180);
    if (!nearEnd) {
      _videoEndNotified = false;
      return;
    }
    if (_videoEndNotified) return;
    _videoEndNotified = true;
    final callback = widget.onVideoEnded;
    if (callback != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.isActive) {
          callback();
        }
      });
    }
  }

  Future<void> _disposeController() async {
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      controller.removeListener(_handleVideoProgress);
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
            _buildImageLayers(url),
          if (widget.mediaOverlayOpacity > 0)
            Positioned.fill(
              child: ColoredBox(
                  color: Colors.black
                      .withValues(alpha: widget.mediaOverlayOpacity)),
            ),
          if (hasTitle || hasSubtitle)
            Positioned.fill(
              child: SafeArea(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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

  Widget _buildImageLayers(String url) {
    if (!widget.showBackdrop) {
      return _buildImage(url);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: _buildImageBackdrop(url)),
        Positioned.fill(
          child: ColoredBox(
            color:
                Colors.black.withValues(alpha: widget.backdropOverlayOpacity),
          ),
        ),
        Positioned.fill(child: _buildImage(url)),
      ],
    );
  }

  Widget _buildImageBackdrop(String url) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(
        sigmaX: widget.backdropBlurSigma,
        sigmaY: widget.backdropBlurSigma,
      ),
      child: Transform.scale(
        scale: widget.backdropScale,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          alignment: widget.mediaAlignment,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) => _fallback(),
        ),
      ),
    );
  }

  Widget _buildImage(String url) {
    return Image.network(
      url,
      fit: widget.mediaFit,
      alignment: widget.mediaAlignment,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) => _fallback(),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const Center(
            child: CircularProgressIndicator(color: Colors.white));
      },
    );
  }

  Widget _buildVideoLayers() {
    final controller = _controller;
    if (_hasVideoError) return _fallback();
    if (_isLoading || controller == null || !controller.value.isInitialized) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white));
    }

    final size = controller.value.size;
    final mainFit = widget.mediaFit;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: FittedBox(
            fit: BoxFit.cover,
            alignment: widget.mediaAlignment,
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
            alignment: widget.mediaAlignment,
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
