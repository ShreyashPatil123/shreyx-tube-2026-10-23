import 'package:flutter/material.dart';
import '../models/tube_models.dart';
import '../models/tube_stream.dart';
import '../providers/tube_player_provider.dart';
import '../services/tube_storage_service.dart';

/// Modal bottom sheet for selecting video resolution.
void showQualityPickerSheet(BuildContext context, TubePlayerProvider provider) {
  final resolved = provider.resolvedVideo;
  if (resolved == null) return;

  final qualities = resolved.availableQualities;
  final current = provider.selectedQuality;

  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF141414),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                child: Row(
                  children: [
                    const Icon(Icons.tune, color: Color(0xFFE50914), size: 20),
                    const SizedBox(width: 10),
                    const Text(
                      'Video Quality',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const Spacer(),
                    Text(
                      '${resolved.videoStreams.length} available streams',
                      style: const TextStyle(fontSize: 12, color: Colors.white38),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: qualities.length,
                  itemBuilder: (ctx, idx) {
                    final q = qualities[idx];
                    final isSelected = q.toLowerCase() == current.toLowerCase();

                    // Find stream matching to show extra metadata
                    TubeVideoStream? stream;
                    if (q != 'Auto') {
                      try {
                        stream = resolved.videoStreams.firstWhere(
                          (s) => s.resolution.toLowerCase() == q.toLowerCase(),
                        );
                      } catch (_) {}
                    }

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
                      leading: Icon(
                        isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                        color: isSelected ? const Color(0xFFE50914) : Colors.white38,
                        size: 20,
                      ),
                      title: Text(
                        q,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white70,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: stream != null
                          ? Text(
                              '${stream.container.toUpperCase()} • ${stream.codec} • ${stream.fps}fps • ${stream.isVideoOnly ? "Adaptive Merged" : "Progressive"}',
                              style: const TextStyle(fontSize: 11, color: Colors.white38),
                            )
                          : null,
                      onTap: () {
                        provider.changeQuality(q);
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Modal bottom sheet for selecting Subtitles / Closed Captions.
void showSubtitlePickerSheet(BuildContext context, TubePlayerProvider provider) {
  final resolved = provider.resolvedVideo;
  if (resolved == null) return;

  final subtitles = resolved.subtitles;
  final current = provider.currentSubtitle;

  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF141414),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                child: Row(
                  children: [
                    Icon(Icons.closed_caption, color: Color(0xFF00E5FF), size: 20),
                    SizedBox(width: 10),
                    Text(
                      'Captions & Subtitles',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12),
              // Option: Turn off captions
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
                leading: Icon(
                  current == null ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                  color: current == null ? const Color(0xFF00E5FF) : Colors.white38,
                  size: 20,
                ),
                title: Text(
                  'Off',
                  style: TextStyle(
                    color: current == null ? Colors.white : Colors.white70,
                    fontWeight: current == null ? FontWeight.bold : FontWeight.normal,
                    fontSize: 14,
                  ),
                ),
                onTap: () {
                  provider.setSubtitleTrack(null);
                  Navigator.pop(ctx);
                },
              ),
              if (subtitles.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Center(
                    child: Text('No subtitle tracks available for this video.', style: TextStyle(color: Colors.white38, fontSize: 13)),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: subtitles.length,
                    itemBuilder: (ctx, idx) {
                      final sub = subtitles[idx];
                      final isSelected = current?.languageCode == sub.languageCode;

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
                        leading: Icon(
                          isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                          color: isSelected ? const Color(0xFF00E5FF) : Colors.white38,
                          size: 20,
                        ),
                        title: Text(
                          sub.languageName,
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white70,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          '${sub.languageCode.toUpperCase()} • ${sub.isAutoGenerated ? "Auto-generated" : "Creator provided"}',
                          style: const TextStyle(fontSize: 11, color: Colors.white38),
                        ),
                        onTap: () {
                          provider.setSubtitleTrack(sub);
                          Navigator.pop(ctx);
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// Modal bottom sheet to add video to a local playlist.
void showAddToPlaylistSheet(BuildContext context, TubeVideoItem video) {
  final storage = TubeStorageService();
  final playlists = storage.getPlaylists();

  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF141414),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Save to Local Playlist',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.add, size: 18, color: Color(0xFFE50914)),
                        label: const Text('New Playlist', style: TextStyle(color: Color(0xFFE50914))),
                        onPressed: () {
                          _showCreatePlaylistDialog(context, (name) async {
                            await storage.createPlaylist(name);
                            setState(() {});
                          });
                        },
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white12),
                  if (playlists.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24.0),
                      child: Center(
                        child: Text('No local playlists yet. Tap "New Playlist" to create one.',
                            style: TextStyle(color: Colors.white38, fontSize: 13)),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: playlists.length,
                        itemBuilder: (ctx, idx) {
                          final pl = playlists[idx];
                          final containsVideo = pl.videos.any((v) => v.id == video.id);

                          return CheckboxListTile(
                            value: containsVideo,
                            activeColor: const Color(0xFFE50914),
                            checkColor: Colors.white,
                            title: Text(pl.title, style: const TextStyle(color: Colors.white)),
                            subtitle: Text('${pl.count} videos', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                            onChanged: (val) async {
                              if (val == true) {
                                await storage.addToPlaylist(pl.id, video);
                              } else {
                                await storage.removeFromPlaylist(pl.id, video.id);
                              }
                              setState(() {});
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

void _showCreatePlaylistDialog(BuildContext context, ValueChanged<String> onCreate) {
  final controller = TextEditingController();
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      title: const Text('Create New Playlist', style: TextStyle(color: Colors.white)),
      content: TextField(
        controller: controller,
        autofocus: true,
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(
          hintText: 'Playlist name...',
          hintStyle: TextStyle(color: Colors.white38),
          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFE50914))),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE50914)),
          onPressed: () {
            final text = controller.text.trim();
            if (text.isNotEmpty) {
              onCreate(text);
              Navigator.pop(ctx);
            }
          },
          child: const Text('Create', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
}
