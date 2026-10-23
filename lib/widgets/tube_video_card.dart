import '../services/tube_share_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/tube_models.dart';
import '../providers/tube_player_provider.dart';
import '../screens/tube_channel_screen.dart';
import '../services/tube_database_service.dart';
import '../services/tube_download_service.dart';
import '../services/tube_storage_service.dart';
import '../services/tube_stream_resolver.dart';
import '../theme/tube_theme.dart';
import 'tube_image.dart';

/// Modern YouTube-styled video card used across Home, Up Next, Search, and Library.
/// Provides both full-width (Home) and compact (Search, Up Next) layouts.
class TubeVideoCard extends StatelessWidget {
  final TubeVideoItem video;
  final VoidCallback? onTap;
  final bool showChannelAvatar;
  final bool isCompact;

  const TubeVideoCard({
    super.key,
    required this.video,
    this.onTap,
    this.showChannelAvatar = true,
    this.isCompact = false,
  });

  void _showActionMenu(BuildContext context) {
    final provider = context.read<TubePlayerProvider>();
    final db = TubeDatabaseService.instance;
    final storage = TubeStorageService();

    showModalBottomSheet(
      context: context,
      backgroundColor: TubeTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.playlist_play,
                    color: TubeTheme.textPrimary),
                title: const Text('Play Next in Queue',
                    style: TextStyle(color: TubeTheme.textPrimary)),
                onTap: () {
                  provider.playNextInQueue(video);
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Added to play next')),
                  );
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.queue_music, color: TubeTheme.textPrimary),
                title: const Text('Add to Queue',
                    style: TextStyle(color: TubeTheme.textPrimary)),
                onTap: () {
                  provider.addToQueue(video);
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Added to queue')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.watch_later_outlined,
                    color: TubeTheme.textPrimary),
                title: const Text('Save to Watch Later',
                    style: TextStyle(color: TubeTheme.textPrimary)),
                onTap: () async {
                  Navigator.pop(ctx);
                  // FIX BUG: Actually persist to database and storage!
                  await db.toggleWatchLater(video.id, video.toJson());
                  await storage.toggleWatchLater(video);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Saved to Watch Later')),
                    );
                  }
                },
              ),
              if (!video.isMembersOnly)
                ListTile(
                  leading: const Icon(Icons.download_outlined,
                      color: TubeTheme.textPrimary),
                  title: const Text('Download Video',
                      style: TextStyle(color: TubeTheme.textPrimary)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    if (TubeDownloadService().isDownloaded(video.id)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Video already downloaded')),
                      );
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(
                              'Starting download for "${video.title}"...')),
                    );
                    try {
                      final resolved =
                          await TubeStreamResolver().resolve(video.id);
                      final stream = resolved.getBestStream('Auto');
                      if (stream != null) {
                        await TubeDownloadService()
                            .startDownload(video: video, stream: stream);
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Download failed: $e')),
                        );
                      }
                    }
                  },
                ),
              ListTile(
                leading: const Icon(Icons.share_outlined,
                    color: TubeTheme.textPrimary),
                title: const Text('Share',
                    style: TextStyle(color: TubeTheme.textPrimary)),
                onTap: () {
                  Navigator.pop(ctx);
                  TubeShareService.share(context, video);
                },
              ),
              ListTile(
                leading: const Icon(Icons.not_interested,
                    color: TubeTheme.textPrimary),
                title: const Text('Not interested',
                    style: TextStyle(color: TubeTheme.textPrimary)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await db.addFeedback(
                      video.id, video.channelId, 'not_interested');
                  await storage.markNotInterested(video.id);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              'Recommendation updated: We will show fewer videos like this')),
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.do_not_disturb_on_outlined,
                    color: TubeTheme.textPrimary),
                title: const Text("Don't recommend channel",
                    style: TextStyle(color: TubeTheme.textPrimary)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await db.addFeedback(
                      video.id, video.channelId, 'dont_recommend_channel');
                  await storage.blockChannel(video.channelTitle);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(
                              'We will not recommend videos from ${video.channelTitle}')),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isCompact) {
      return _buildCompactCard(context);
    }
    return _buildFullCard(context);
  }

  /// YouTube-style full-width card for Home feed
  Widget _buildFullCard(BuildContext context) {
    final timeAgo = video.formattedDate;
    final metadataParts = <String>[];
    if (video.channelTitle.isNotEmpty) {
      metadataParts.add(video.channelTitle);
    }
    if (video.formattedViews.isNotEmpty) {
      metadataParts.add(video.formattedViews);
    }
    if (timeAgo.isNotEmpty) {
      metadataParts.add(timeAgo);
    }
    final metadataText = metadataParts.join(' \u2022 ');

    return InkWell(
      onTap: onTap ??
          () {
            context.read<TubePlayerProvider>().playVideo(video);
          },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 16:9 Edge-to-Edge Thumbnail
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                TubeNetworkImage(
                  imageUrl: video.thumbnailUrl,
                  fit: BoxFit.cover,
                ),
                // Duration Badge
                if (video.durationSeconds > 0 || video.isLive)
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: video.isLive
                            ? TubeTheme.live
                            : Colors.black.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(
                            TubeTheme.durationBadgeRadius),
                      ),
                      child: Text(
                        video.formattedDuration,
                        style: TubeTheme.labelSmall,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Metadata area below thumbnail
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 4, 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Channel Avatar
                if (showChannelAvatar) ...[
                  GestureDetector(
                    onTap: () {
                      if (video.channelId.isNotEmpty) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TubeChannelScreen(
                              channelId: video.channelId,
                              channelTitle: video.channelTitle,
                            ),
                          ),
                        );
                      }
                    },
                    child: CircleAvatar(
                      radius: TubeTheme.avatarSize / 2,
                      backgroundColor: TubeTheme.surfaceVariant,
                      backgroundImage: video.channelAvatarUrl.isNotEmpty
                          ? NetworkImage(video.channelAvatarUrl)
                          : null,
                      child: video.channelAvatarUrl.isEmpty
                          ? const Icon(Icons.person_outline,
                              color: TubeTheme.textSecondary, size: 22)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],

                // Title + Subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        video.title,
                        style: TubeTheme.titleLarge,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (video.isMembersOnly) _membersBadge(),
                      const SizedBox(height: 4),
                      Text(
                        metadataText,
                        style: TubeTheme.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // 3-dots action menu
                IconButton(
                  icon: const Icon(Icons.more_vert,
                      size: 20, color: TubeTheme.textSecondary),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () => _showActionMenu(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// YouTube-style compact card for Search results, Up Next, History
  Widget _buildCompactCard(BuildContext context) {
    final timeAgo = video.formattedDate;
    final detailParts = <String>[
      if (video.formattedViews.isNotEmpty) video.formattedViews,
      if (timeAgo.isNotEmpty) timeAgo,
    ];
    final detailText = detailParts.join(' \u2022 ');

    return InkWell(
      onTap: onTap ??
          () {
            context.read<TubePlayerProvider>().playVideo(video);
          },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail (168x94) with rounded corners
            SizedBox(
              width: TubeTheme.compactThumbWidth,
              height: TubeTheme.compactThumbHeight,
              child: ClipRRect(
                borderRadius:
                    BorderRadius.circular(TubeTheme.thumbnailRadiusCompact),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    TubeNetworkImage(
                      imageUrl: video.thumbnailUrl,
                      fit: BoxFit.cover,
                    ),
                    if (video.durationSeconds > 0 || video.isLive)
                      Positioned(
                        bottom: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: video.isLive
                                ? TubeTheme.live
                                : Colors.black.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(
                                TubeTheme.durationBadgeRadius),
                          ),
                          child: Text(
                            video.formattedDuration,
                            style: TubeTheme.labelSmall,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Video Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    style: TubeTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (video.isMembersOnly) _membersBadge(),
                  const SizedBox(height: 4),
                  Text(
                    video.channelTitle,
                    style: TubeTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detailText,
                    style: TubeTheme.labelSmall
                        .copyWith(color: TubeTheme.textTertiary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // 3-dots action menu
            IconButton(
              icon: const Icon(Icons.more_vert,
                  size: 18, color: TubeTheme.textSecondary),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: () => _showActionMenu(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _membersBadge() => Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
            color: TubeTheme.membersGold,
            borderRadius: BorderRadius.circular(4)),
        child: const Text('MEMBERS ONLY',
            style: TextStyle(
                color: Colors.black,
                fontSize: 10,
                fontWeight: FontWeight.bold)),
      );
}
