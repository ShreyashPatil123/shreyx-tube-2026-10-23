import 'package:flutter/material.dart';
import '../models/tube_models.dart';
import '../theme/tube_theme.dart';
import 'tube_image.dart';

class TubeShortsShelf extends StatelessWidget {
  const TubeShortsShelf({super.key, required this.items, required this.onOpen});
  final List<TubeVideoItem> items;
  final ValueChanged<TubeVideoItem> onOpen;
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    const width = 130.0;
    const titleStyle = TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: TubeTheme.textPrimary,
        height: 1.3);
    var titleHeight = 0.0;
    for (final item in items) {
      final painter = TextPainter(
          text: TextSpan(text: item.title, style: titleStyle),
          maxLines: 2,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context))
        ..layout(maxWidth: width);
      if (painter.height > titleHeight) titleHeight = painter.height;
      painter.dispose();
    }
    final height = (width * 16 / 9 + 6 + titleHeight).ceilToDouble();
    return Container(
      color: TubeTheme.background,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.bolt, color: TubeTheme.accent, size: 20),
                SizedBox(width: 8),
                Text(
                  'Shorts',
                  style: TextStyle(
                    color: TubeTheme.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: height,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, idx) {
                final short = items[idx];
                return GestureDetector(
                  onTap: () => onOpen(short),
                  child: SizedBox(
                    width: width,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: AspectRatio(
                            aspectRatio: 9 / 16,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                TubeNetworkImage(
                                  imageUrl: short.thumbnailUrl,
                                  fit: BoxFit.cover,
                                ),
                                Positioned(
                                  bottom: 6,
                                  right: 6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                        alpha: 0.7,
                                      ),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: const Text(
                                      'Short',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          short.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: titleStyle,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
