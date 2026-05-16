import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../constants/app_theme.dart';
import '../../models/banner_model.dart';
import '../../services/api_client.dart';
import 'loading_skeletons.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Premium Hero Banner Carousel
// ─────────────────────────────────────────────────────────────────────────────

class HeroBannerCarousel extends StatefulWidget {
  final List<BannerModel> banners;
  final bool isLoading;
  final void Function(BannerModel banner)? onBannerTap;

  const HeroBannerCarousel({
    super.key,
    required this.banners,
    required this.isLoading,
    this.onBannerTap,
  });

  @override
  State<HeroBannerCarousel> createState() => _HeroBannerCarouselState();
}

class _HeroBannerCarouselState extends State<HeroBannerCarousel> {
  late PageController _pageCtrl;
  int _currentPage = 0;
  Timer? _autoTimer;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
    _scheduleAutoRotate();
  }

  @override
  void didUpdateWidget(HeroBannerCarousel old) {
    super.didUpdateWidget(old);
    if (old.banners.length != widget.banners.length) {
      _scheduleAutoRotate();
    }
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _pageCtrl.dispose();
    super.dispose();
  }

  void _scheduleAutoRotate() {
    _autoTimer?.cancel();
    if (widget.banners.length <= 1) return;
    _autoTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_pageCtrl.hasClients) return;
      final next = (_currentPage + 1) % widget.banners.length;
      _pageCtrl.animateToPage(
        next,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
  }

  bool _isTappable(BannerModel b) =>
      (b.linkUrl ?? '').trim().isNotEmpty || (b.providerId ?? 0) > 0;

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading && widget.banners.isEmpty) {
      return const HeroBannerSkeleton();
    }

    final width = MediaQuery.sizeOf(context).width;
    final horizontalPadding = width >= 700 ? 24.0 : 12.0;
    final radius = width >= 700 ? AppRadius.xl : AppRadius.lg;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: AspectRatio(
        aspectRatio: 16 / 7,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withAlpha(30),
                blurRadius: 24,
                spreadRadius: 0,
                offset: const Offset(0, 8),
              ),
              ...AppShadows.elevated,
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildBannerContent(),
                if (widget.banners.length > 1)
                  Positioned(
                    bottom: 10,
                    left: 0,
                    right: 0,
                    child: _buildPageDots(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBannerContent() {
    if (widget.banners.isEmpty) {
      return _buildFallbackGradient();
    }
    if (widget.banners.length == 1) {
      return _buildSingleBannerTile(widget.banners.first);
    }
    return PageView.builder(
      controller: _pageCtrl,
      itemCount: widget.banners.length,
      onPageChanged: (idx) {
        if (!mounted) return;
        setState(() => _currentPage = idx);
        _scheduleAutoRotate();
      },
      itemBuilder: (_, i) => _buildSingleBannerTile(widget.banners[i]),
    );
  }

  Widget _buildSingleBannerTile(BannerModel banner) {
    final url = ApiClient.buildMediaUrl(banner.mediaUrl);
    final child = url != null
        ? CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            placeholder: (_, __) => _buildFallbackGradient(),
            errorWidget: (_, __, ___) => _buildFallbackGradient(),
          )
        : _buildFallbackGradient();

    if (!_isTappable(banner)) return child;
    return GestureDetector(
      onTap: () => widget.onBannerTap?.call(banner),
      child: child,
    );
  }

  Widget _buildFallbackGradient() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primaryDark, AppColors.primaryLight],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.image_rounded,
          size: 48,
          color: Colors.white30,
        ),
      ),
    );
  }

  Widget _buildPageDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(widget.banners.length, (i) {
        final isActive = i == _currentPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: isActive ? 18 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.white38,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
        );
      }),
    );
  }
}
