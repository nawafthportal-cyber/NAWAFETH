import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../screens/provider_profile_screen.dart';
import '../services/home_feed_service.dart';
import '../models/provider.dart';

class ProfilesSlider extends StatefulWidget {
  const ProfilesSlider({super.key});

  @override
  State<ProfilesSlider> createState() => _ProfilesSliderState();
}

class _ProfilesSliderState extends State<ProfilesSlider> {
  final ScrollController _scrollController = ScrollController();
  Timer? _timer;
  double _scrollPosition = 0;
  List<ProviderProfile> _providers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchProviders();
  }

  Future<void> _fetchProviders() async {
    final list = await HomeFeedService.instance.getTopProviders(
      limit: 10,
      forceRefresh: false,
    );
    if (mounted) {
      if (list.isEmpty) {
        setState(() => _loading = false);
      } else {
        // Ensure we don't show duplicate providers on the home page.
        final seen = <int>{};
        final unique = <ProviderProfile>[];
        for (final p in list) {
          if (seen.add(p.id)) unique.add(p);
        }
        setState(() {
          _providers = unique;
          _loading = false;
        });
        if (_providers.length > 2) {
          _startAutoScroll();
        }
      }
    }
  }

  void _startAutoScroll() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (_scrollController.hasClients && mounted && _providers.isNotEmpty) {
        _scrollPosition += 116.0; // card width + spacing
        final maxScroll = _scrollController.position.maxScrollExtent;
        if (maxScroll > 0 && _scrollPosition >= maxScroll) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeInOut,
          );
          _scrollPosition = 0;
        } else {
          _scrollController.animateTo(
            _scrollPosition,
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeInOut,
          );
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

  void _openProfileDetail(BuildContext context, ProviderProfile provider) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProviderProfileScreen(
          providerId: provider.id.toString(),
          providerName: provider.displayName,
          providerImage: provider.imageUrl,
          providerVerified: provider.isVerifiedBlue,
          // We can pass more if needed, but Detail screen should fetch full data
        ),
      ),
    );
  }

  ImageProvider? _providerImage(ProviderProfile provider) {
    final raw = (provider.imageUrl ?? '').trim();
    if (raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return CachedNetworkImageProvider(raw);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox(height: 78, child: Center(child: CircularProgressIndicator()));
    if (_providers.isEmpty) return const SizedBox(height: 8);

    return Container(
      color: const Color(0xFFF2F2F2),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SizedBox(
        height: 82,
        child: ListView.builder(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          itemCount: _providers.length,
          itemBuilder: (context, index) {
            final profile = _providers[index];
            final avatar = _providerImage(profile);
            final ratingLabel = profile.ratingAvg > 0 ? profile.ratingAvg.toStringAsFixed(1) : '—';
            final showVerified = profile.isVerifiedBlue || profile.isVerifiedGreen;
            final verifiedColor = profile.isVerifiedGreen ? const Color(0xFF27AE60) : const Color(0xFF2D9CDB);
            return GestureDetector(
              onTap: () => _openProfileDetail(context, profile),
              child: Container(
                width: 84,
                margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFECECEC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white, width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: AppColors.softBlue,
                          child: CircleAvatar(
                            radius: 18,
                            backgroundImage: avatar,
                            child: avatar == null
                                ? const Icon(Icons.person, color: Colors.white, size: 18)
                                : null,
                          ),
                        ),
                        if (showVerified)
                          Positioned(
                            top: -4,
                            left: -4,
                            child: Icon(Icons.verified, size: 14, color: verifiedColor),
                          ),
                        Positioned(
                          left: -2,
                          bottom: -2,
                          child: Container(
                            width: 17,
                            height: 17,
                            decoration: BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1.2),
                            ),
                            alignment: Alignment.center,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                ratingLabel,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (profile.isOnline)
                          Positioned(
                            right: -1,
                            top: -1,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: const Color(0xFF2ECC71),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 1),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
