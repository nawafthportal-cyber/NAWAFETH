import 'package:flutter/material.dart';

import 'nawafeth_cached_image.dart';

/// Round provider avatar with an optional online/offline presence dot.
///
/// Use this everywhere a provider's photo is shown so that the green/grey
/// indicator stays consistent across screens.
///
/// ```dart
/// ProviderAvatar(
///   imageUrl: provider.profileImage,
///   displayName: provider.displayName,
///   isOnline: provider.isOnline,
///   radius: 24,
/// );
/// ```
class ProviderAvatar extends StatelessWidget {
  final String? imageUrl;
  final String? displayName;
  final bool isOnline;
  final double radius;

  /// Whether to render the presence dot at all. Defaults to `true`. Set to
  /// `false` for non-provider avatars (clients, system threads).
  final bool showPresence;

  /// Optional override for dot size. If null, scales with [radius].
  final double? dotSize;

  /// Background color for the initials fallback when [imageUrl] is missing.
  final Color? fallbackColor;

  const ProviderAvatar({
    super.key,
    this.imageUrl,
    this.displayName,
    this.isOnline = false,
    this.radius = 22,
    this.showPresence = true,
    this.dotSize,
    this.fallbackColor,
  });

  static const _onlineColor = Color(0xFF22C55E); // green-500
  static const _offlineColor = Color(0xFF9CA3AF); // grey-400

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    final initial = (displayName ?? '').trim().isNotEmpty
        ? (displayName ?? '').trim().characters.first.toUpperCase()
        : '؟';
    final hasImage = (imageUrl ?? '').trim().isNotEmpty;

    final avatar = ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: hasImage
            ? NawafethCachedImage(
                imageUrl: imageUrl!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorWidget: _buildInitialsFallback(initial),
              )
            : _buildInitialsFallback(initial),
      ),
    );

    if (!showPresence) return avatar;

    final ds = dotSize ?? (size * 0.28).clamp(8.0, 16.0);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          bottom: 0,
          right: 0,
          child: Container(
            width: ds,
            height: ds,
            decoration: BoxDecoration(
              color: isOnline ? _onlineColor : _offlineColor,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInitialsFallback(String initial) {
    final size = radius * 2;
    return Container(
      width: size,
      height: size,
      color: fallbackColor ?? const Color(0xFFF1ECF7),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: radius * 0.9,
          fontWeight: FontWeight.bold,
          color: const Color(0xFF6E2EAF),
        ),
      ),
    );
  }
}
