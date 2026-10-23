import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../theme/tube_theme.dart';

/// High-performance cached network image widget with YouTube-style shimmer placeholder.
class TubeNetworkImage extends StatelessWidget {
  final String imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? placeholder;
  final Widget? errorWidget;

  const TubeNetworkImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    String cleanUrl = imageUrl.trim();
    if (cleanUrl.startsWith('//')) {
      cleanUrl = 'https:$cleanUrl';
    }

    if (cleanUrl.isEmpty) {
      return errorWidget ?? _defaultPlaceholder();
    }

    final pixels = MediaQuery.devicePixelRatioOf(context);
    final decodeWidth = ((width ?? MediaQuery.sizeOf(context).width) * pixels)
        .round()
        .clamp(1, 1280);
    return CachedNetworkImage(
      imageUrl: cleanUrl,
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: decodeWidth,
      placeholder: (context, url) => placeholder ?? _shimmerPlaceholder(),
      errorWidget: (context, url, error) =>
          errorWidget ?? _defaultPlaceholder(),
    );
  }

  Widget _shimmerPlaceholder() {
    return Shimmer.fromColors(
      baseColor: TubeTheme.shimmerBase,
      highlightColor: TubeTheme.shimmerHighlight,
      child: Container(
        width: width,
        height: height,
        color: TubeTheme.shimmerBase,
      ),
    );
  }

  Widget _defaultPlaceholder() {
    return Container(
      width: width,
      height: height,
      color: TubeTheme.surface,
      child: const Center(
        child: Icon(Icons.play_circle_outline,
            color: TubeTheme.textTertiary, size: 28),
      ),
    );
  }
}
