import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/colors.dart';
import '../models/provider_portfolio_item.dart';
import '../screens/home_media_viewer_screen.dart';
import '../services/home_feed_service.dart';
import 'safe_network_image.dart';

enum BannerPlacement { home, search }

class BannerWidget extends StatefulWidget {
  final BannerPlacement placement;
  final String? city;
  final String? categoryName;
  final int limit;

  const BannerWidget({
    super.key,
    this.placement = BannerPlacement.home,
    this.city,
    this.categoryName,
    this.limit = 6,
  });

  @override
  State<BannerWidget> createState() => _BannerWidgetState();
}

class _BannerWidgetState extends State<BannerWidget> {
  final HomeFeedService _feed = HomeFeedService.instance;
  final PageController _controller = PageController();
  Timer? _timer;

  bool _loading = true;
  bool _loadFailed = false;
  int _index = 0;
  List<ProviderPortfolioItem> _banners = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final List<ProviderPortfolioItem> banners;
      switch (widget.placement) {
        case BannerPlacement.search:
          banners = await _feed.getSearchBannerItems(
            limit: widget.limit,
            city: widget.city,
            categoryName: widget.categoryName,
          );
          break;
        case BannerPlacement.home:
          banners = await _feed.getBannerItems(limit: widget.limit);
          break;
      }

      if (!mounted) return;
      setState(() {
        _banners = banners;
        _loadFailed = _feed.lastBannerItemsLoadFailed;
        _loading = false;
      });
      _startAutoSlide();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _banners = const [];
        _loadFailed = true;
        _loading = false;
      });
    }
  }

  void _startAutoSlide() {
    _timer?.cancel();
    if (_banners.length < 2) return;
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_controller.hasClients || !mounted) return;
      _index = (_index + 1) % _banners.length;
      _controller.animateToPage(
        _index,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeInOut,
      );
    });
  }

  Future<void> _openBanner(BuildContext context, int index) async {
    final item = _banners[index];
    final rawRedirect = (item.redirectUrl ?? '').trim();
    if (rawRedirect.isNotEmpty) {
      final uri = Uri.tryParse(rawRedirect);
      if (uri != null) {
        try {
          final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
          if (launched) return;
        } catch (_) {
          // Fall back to in-app viewer below.
        }
      }
    }

    if (!context.mounted) return;
    await Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (context, animation, secondaryAnimation) => FadeTransition(
          opacity: animation,
          child: HomeMediaViewerScreen(
            items: _banners,
            initialIndex: index,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_banners.isEmpty) {
      if (_loadFailed) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.white,
            border: Border.all(color: Colors.red.shade100),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi_off_rounded, color: Colors.red.shade400, size: 28),
                const SizedBox(height: 8),
                const Text(
                  'تعذر تحميل البنرات الآن',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _loading = true;
                      _loadFailed = false;
                    });
                    _load();
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ),
        );
      }
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            colors: [AppColors.deepPurple, AppColors.primaryDark],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'مساحة إعلانية',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'ستُدار من قبل مدير النظام لاحقاً',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: _banners.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) {
              final item = _banners[i];
              final isVideo = item.fileType.toLowerCase().contains('video');
              return Stack(
                fit: StackFit.expand,
                children: [
                  if (!isVideo)
                    SafeNetworkImage(
                      imageUrl: item.fileUrl,
                      fit: BoxFit.cover,
                      errorWidget: Container(color: Colors.grey.shade300),
                    )
                  else
                    Container(
                      color: Colors.grey.shade300,
                      alignment: Alignment.center,
                      child: const Icon(Icons.videocam_rounded, size: 44, color: Colors.black54),
                    ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          const Color(0xAA7C2A90),
                          const Color(0x557C2A90),
                        ],
                      ),
                    ),
                  ),
                  if (isVideo)
                    Center(
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.40),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 34),
                      ),
                    ),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () async {
                        await _openBanner(context, i);
                      },
                    ),
                  ),
                  // شارة "إعلان" في الزاوية العلوية
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.campaign_rounded, color: Colors.white, size: 12),
                          SizedBox(width: 4),
                          Text(
                            'إعلان',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    right: 14,
                    left: 14,
                    bottom: 16,
                    child: Text(
                      item.caption.trim().isEmpty ? item.providerDisplayName : item.caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          Positioned(
            bottom: 10,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_banners.length, (i) {
                final active = i == _index;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: active ? 16 : 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: active ? Colors.white : Colors.white.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(999),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}
