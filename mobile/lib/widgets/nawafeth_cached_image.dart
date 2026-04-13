import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Drop-in replacement for [Image.network] with disk + memory caching.
///
/// Usage:
/// ```dart
/// NawafethCachedImage(imageUrl: url, width: 80, height: 80, fit: BoxFit.cover)
/// ```
class NawafethCachedImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  final BorderRadius? borderRadius;

  const NawafethCachedImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final image = CachedNetworkImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: fit,
      placeholder: (context, url) =>
          placeholder ??
          SizedBox(
            width: width,
            height: height,
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
      errorWidget: (context, url, error) =>
          errorWidget ??
          SizedBox(
            width: width,
            height: height,
            child: const Icon(Icons.broken_image_outlined,
                color: Colors.grey, size: 32),
          ),
    );

    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: image);
    }
    return image;
  }
}

/// Drop-in replacement for [NetworkImage] that uses cached_network_image.
///
/// Usage inside [CircleAvatar] or [DecorationImage]:
/// ```dart
/// CircleAvatar(backgroundImage: cachedNetworkImageProvider(url))
/// ```
CachedNetworkImageProvider cachedNetworkImageProvider(String url) {
  return CachedNetworkImageProvider(url);
}
