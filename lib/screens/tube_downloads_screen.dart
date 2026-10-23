import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/tube_download_models.dart';
import '../models/tube_models.dart';
import '../providers/tube_player_provider.dart';
import '../services/tube_download_service.dart';
import '../widgets/tube_image.dart';

/// Screen dedicated to offline playback and management of downloaded videos.
class TubeDownloadsScreen extends StatefulWidget {
  const TubeDownloadsScreen({super.key});

  @override
  State<TubeDownloadsScreen> createState() => _TubeDownloadsScreenState();
}

class _TubeDownloadsScreenState extends State<TubeDownloadsScreen> {
  final TubeDownloadService _downloadService = TubeDownloadService();

  @override
  void initState() {
    super.initState();
    _downloadService.init();
  }

  void _playOffline(TubeDownloadItem item) {
    final stream = _downloadService.getOfflineStream(item);
    final video = TubeVideoItem(
      id: item.videoId,
      title: item.title,
      channelTitle: item.channelTitle,
      channelId: item.channelId,
      thumbnailUrl: item.thumbnailUrl,
      durationSeconds: item.durationSeconds,
    );

    final player = context.read<TubePlayerProvider>();
    player.playOfflineVideo(video, stream);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        elevation: 0,
        title: const Text('Offline Downloads', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ),
      body: StreamBuilder<List<TubeDownloadItem>>(
        stream: _downloadService.downloadsStream,
        initialData: _downloadService.downloads,
        builder: (context, snapshot) {
          final items = snapshot.data ?? [];

          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.download_for_offline_outlined, size: 64, color: Colors.white.withValues(alpha: 0.2)),
                  const SizedBox(height: 16),
                  const Text('No downloaded videos', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  const Text('Videos you download will appear here for offline playback.', style: TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, idx) {
              final item = items[idx];
              final isCompleted = item.status == TubeDownloadStatus.completed;

              return InkWell(
                onTap: isCompleted ? () => _playOffline(item) : null,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141414),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Thumbnail with quality badge
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 120,
                              height: 68,
                              child: TubeNetworkImage(
                                imageUrl: item.thumbnailUrl,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 4,
                            right: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE50914),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                item.quality,
                                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      // Details & status
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.channelTitle,
                              style: const TextStyle(color: Colors.white54, fontSize: 11),
                            ),
                            const SizedBox(height: 6),
                            if (!isCompleted) ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: LinearProgressIndicator(
                                      value: item.progress,
                                      backgroundColor: Colors.white12,
                                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFE50914)),
                                      minHeight: 3,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${(item.progress * 100).toInt()}%',
                                    style: const TextStyle(color: Colors.white54, fontSize: 10),
                                  ),
                                ],
                              ),
                            ] else ...[
                              Row(
                                children: [
                                  const Icon(Icons.check_circle, color: Colors.greenAccent, size: 12),
                                  const SizedBox(width: 4),
                                  Text(
                                    item.formattedSize.isNotEmpty ? item.formattedSize : 'Offline Ready',
                                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      // Delete button
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.white38, size: 20),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: const Color(0xFF1E1E1E),
                              title: const Text('Delete Download?', style: TextStyle(color: Colors.white)),
                              content: Text('Remove "${item.title}" from offline storage?', style: const TextStyle(color: Colors.white70)),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                                ),
                                TextButton(
                                  onPressed: () {
                                    _downloadService.deleteDownload(item.videoId);
                                    Navigator.pop(ctx);
                                  },
                                  child: const Text('Delete', style: TextStyle(color: Color(0xFFE50914))),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
