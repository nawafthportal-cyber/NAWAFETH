import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/media_item_model.dart';
import '../services/api_client.dart';

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

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.items.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
    _initVideoController();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _initVideoController() async {
    _videoController?.pause();
    await _videoController?.dispose();
    _videoController = null;

    final item = widget.items[_currentIndex];
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
        child: Image.network(
          url,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Icon(
            Icons.broken_image_outlined,
            size: 40,
            color: Colors.white70,
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final paddingTop = MediaQuery.of(context).padding.top;
    return Positioned(
      top: paddingTop + 12,
      left: 12,
      child: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.close, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  Widget _buildCaption(MediaItemModel item) {
    final caption = (item.caption ?? '').trim();
    final provider = (item.providerDisplayName).trim();

    if (caption.isEmpty && provider.isEmpty) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.black.withValues(alpha: 0.75),
              Colors.black.withValues(alpha: 0.05),
            ],
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (caption.isNotEmpty)
              Text(
                caption,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Cairo',
                ),
              ),
            if (provider.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  provider,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 11,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: Text('لا توجد لمحات', style: TextStyle(color: Colors.white))),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.items.length,
            onPageChanged: (index) {
              setState(() => _currentIndex = index);
              _initVideoController();
            },
            itemBuilder: (_, index) => _buildMedia(widget.items[index]),
          ),
          _buildTopBar(),
          _buildCaption(widget.items[_currentIndex]),
        ],
      ),
    );
  }
}
