import 'dart:async';
import 'dart:typed_data';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'video_full_screen.dart';

class VideoReels extends StatefulWidget {
  const VideoReels({super.key});

  @override
  State<VideoReels> createState() => _VideoReelsState();
}

class _VideoReelsState extends State<VideoReels> {
  final ScrollController _scrollController = ScrollController();
  Timer? _timer;
  double _scrollPosition = 0;

  final List<String> _baseVideoPaths = const [
    'assets/videos/1.mp4',
    'assets/videos/2.mp4',
    'assets/videos/3.mp4',
    'assets/videos/4.mp4',
  ];

  // ✅ الشعارات الجديدة
  final List<String> _baseLogos = const [
    'assets/images/32.jpeg',
    'assets/images/841015.jpeg',
    'assets/images/879797.jpeg',
  ];
  
  late final List<String> videoPaths;
  late final List<String> logos;

  @override
  void initState() {
    super.initState();
    // مضاعفة القوائم للتمرير اللانهائي
    videoPaths = List.generate(10, (_) => _baseVideoPaths).expand((x) => x).toList();
    logos = List.generate(10, (_) => _baseLogos).expand((x) => x).toList();
    _startAutoScroll();
  }

  void _startAutoScroll() {
    _timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (_scrollController.hasClients && mounted) {
        _scrollPosition += 1.0;

        final maxScroll = _scrollController.position.maxScrollExtent;
        final halfScroll = maxScroll / 2;
        
        if (_scrollPosition >= halfScroll) {
          _scrollController.jumpTo(0);
          _scrollPosition = 0;
        } else {
          _scrollController.jumpTo(_scrollPosition);
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 110,
      child: Center(
        child: ListView.builder(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(), // ✅ إيقاف التمرير اليدوي
          itemCount: videoPaths.length,
          itemBuilder: (context, index) {
            final logoPath = logos[index % logos.length];
            final actualIndex = index % _baseVideoPaths.length;
            return VideoThumbnailWidget(
              path: videoPaths[index],
              logo: logoPath,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (_) => VideoFullScreenPage(
                          videoPaths: _baseVideoPaths,
                          initialIndex: actualIndex,
                        ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class VideoThumbnailWidget extends StatefulWidget {
  final String path;
  final String logo;
  final int likesCount;
  final int savesCount;
  final bool isLiked;
  final bool isSaved;
  final VoidCallback onTap;
  final EdgeInsetsGeometry margin;

  const VideoThumbnailWidget({
    super.key,
    required this.path,
    required this.logo,
    this.likesCount = 0,
    this.savesCount = 0,
    this.isLiked = false,
    this.isSaved = false,
    required this.onTap,
    this.margin = const EdgeInsets.symmetric(horizontal: 10),
  });

  @override
  State<VideoThumbnailWidget> createState() => _VideoThumbnailWidgetState();
}

class _VideoThumbnailWidgetState extends State<VideoThumbnailWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  Future<Uint8List?>? _generatedThumbnailFuture;

  bool get _isNetworkLogo {
    final logo = widget.logo.trim().toLowerCase();
    return logo.startsWith('http://') || logo.startsWith('https://');
  }

  bool get _hasUsableLogo {
    final logo = widget.logo.trim();
    return logo.isNotEmpty && !_looksLikeVideoAsset(logo);
  }

  bool _looksLikeVideoAsset(String value) {
    final lower = value.trim().toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.m4v') ||
        lower.contains('/video/');
  }

  Future<Uint8List?> _generateThumbnail() async {
    final source = widget.path.trim();
    if (source.isEmpty) return null;
    try {
      return await VideoThumbnail.thumbnailData(
        video: source,
        imageFormat: ImageFormat.JPEG,
        quality: 55,
        maxWidth: 220,
        timeMs: 800,
      );
    } catch (_) {
      return null;
    }
  }

  Widget _buildLogoImage() {
    if (_hasUsableLogo) {
      if (_isNetworkLogo) {
        return CachedNetworkImage(
          imageUrl: widget.logo,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => _buildGeneratedThumbnail(),
        );
      }
      if (widget.logo.startsWith('assets/')) {
        return Image.asset(
          widget.logo,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildGeneratedThumbnail(),
        );
      }
      return _buildGeneratedThumbnail();
    }
    return _buildGeneratedThumbnail();
  }

  Widget _buildGeneratedThumbnail() {
    return FutureBuilder<Uint8List?>(
      future: _generatedThumbnailFuture,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (snapshot.connectionState == ConnectionState.done &&
            bytes != null &&
            bytes.isNotEmpty) {
          return Image.memory(
            bytes,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _logoFallback(),
          );
        }
        return _logoFallback(isLoading: snapshot.connectionState != ConnectionState.done);
      },
    );
  }

  Widget _playBadge() {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.46),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: const Icon(
        Icons.play_arrow_rounded,
        color: Colors.white,
        size: 18,
      ),
    );
  }

  Widget _logoFallback({bool isLoading = false}) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF5E35B1).withValues(alpha: 0.88),
            const Color(0xFF14B8A6).withValues(alpha: 0.78),
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
      ),
      alignment: Alignment.center,
      child: isLoading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(
                  Icons.play_circle_fill_rounded,
                  color: Colors.white,
                  size: 28,
                ),
                SizedBox(height: 4),
                Text(
                  'ريل',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Cairo',
                  ),
                ),
              ],
            ),
    );
  }

  @override
  void initState() {
    super.initState();

    _generatedThumbnailFuture = _generateThumbnail();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant VideoThumbnailWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path || oldWidget.logo != widget.logo) {
      _generatedThumbnailFuture = _generateThumbnail();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        width: 90,
        height: 90,
        child: Container(
          margin: widget.margin,
          child: Stack(
            alignment: Alignment.center,
            children: [
              RotationTransition(
                turns: _animationController,
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(
                      colors: [
                        Color(0xFF9F57DB),
                        Color(0xFFF1A559),
                        Color(0xFFC8A5FC),
                        Color(0xFF9F57DB),
                      ],
                    ),
                  ),
                ),
              ),

              Container(
                width: 80,
                height: 80,
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                child: ClipOval(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildLogoImage(),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.18),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                      Center(child: _playBadge()),
                    ],
                  ),
                ),
              ),

              Positioned(
                top: 2,
                right: 2,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.52),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        widget.isLiked ? Icons.favorite : Icons.favorite_border,
                        size: 10.5,
                        color: widget.isLiked ? Colors.deepPurple : Colors.white,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${widget.likesCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Cairo',
                        ),
                      ),
                      const SizedBox(width: 5),
                      Icon(
                        widget.isSaved ? Icons.bookmark : Icons.bookmark_border,
                        size: 10.5,
                        color: widget.isSaved ? Colors.deepPurple : Colors.white,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${widget.savesCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
