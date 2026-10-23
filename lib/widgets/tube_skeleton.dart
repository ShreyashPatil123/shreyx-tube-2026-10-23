import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../theme/tube_theme.dart';

class TubeShimmerWrapper extends StatelessWidget {
  final Widget child;
  const TubeShimmerWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: TubeTheme.shimmerBase,
      highlightColor: TubeTheme.shimmerHighlight,
      child: child,
    );
  }
}

class TubeVideoCardSkeleton extends StatelessWidget {
  const TubeVideoCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(color: Colors.white),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: TubeTheme.cardPaddingH,
            vertical: TubeTheme.cardPaddingV,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: TubeTheme.avatarSize,
                height: TubeTheme.avatarSize,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: TubeTheme.cardMetadataGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      height: 14,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: MediaQuery.of(context).size.width * 0.6,
                      height: 14,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: MediaQuery.of(context).size.width * 0.4,
                      height: 12,
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class TubeVideoCardCompactSkeleton extends StatelessWidget {
  const TubeVideoCardCompactSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: TubeTheme.cardPaddingH,
        vertical: 8.0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: TubeTheme.compactThumbWidth,
            height: TubeTheme.compactThumbHeight,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius:
                  BorderRadius.circular(TubeTheme.thumbnailRadiusCompact),
            ),
          ),
          const SizedBox(width: TubeTheme.cardMetadataGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  height: 14,
                  color: Colors.white,
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  height: 14,
                  color: Colors.white,
                ),
                const SizedBox(height: 6),
                Container(
                  width: 80,
                  height: 12,
                  color: Colors.white,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TubeChipRowSkeleton extends StatelessWidget {
  const TubeChipRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: TubeTheme.chipRowHeight,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: 5,
        padding: const EdgeInsets.symmetric(horizontal: TubeTheme.cardPaddingH),
        itemBuilder: (context, index) {
          final width = 60.0 + (index * 20) % 40;
          return Padding(
            padding: const EdgeInsets.only(right: TubeTheme.chipSpacing),
            child: Center(
              child: Container(
                width: width,
                height: TubeTheme.chipHeight,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(TubeTheme.chipHeight / 2),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class TubeChannelHeaderSkeleton extends StatelessWidget {
  const TubeChannelHeaderSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 3,
          child: Container(color: Colors.white),
        ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(width: 120, height: 20, color: Colors.white),
                    const SizedBox(height: 8),
                    Container(width: 80, height: 14, color: Colors.white),
                  ],
                ),
              ),
              Container(
                width: 80,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class TubeShortsShelfSkeleton extends StatelessWidget {
  const TubeShortsShelfSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 240,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: 3,
        padding: const EdgeInsets.symmetric(horizontal: TubeTheme.cardPaddingH),
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: Container(
              width: 140,
              height: 240,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          );
        },
      ),
    );
  }
}

class TubeSearchResultSkeleton extends StatelessWidget {
  const TubeSearchResultSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    // Similar to compact, but can be reused for search
    return const TubeVideoCardCompactSkeleton();
  }
}

class TubeHomeFeedSkeleton extends StatelessWidget {
  const TubeHomeFeedSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return TubeShimmerWrapper(
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          TubeChipRowSkeleton(),
          TubeVideoCardSkeleton(),
          TubeVideoCardSkeleton(),
          TubeVideoCardSkeleton(),
          TubeVideoCardSkeleton(),
        ],
      ),
    );
  }
}
