import 'package:flutter/material.dart';
import 'tube_video_intelligence_screen.dart';
import 'package:provider/provider.dart';
import '../models/tube_models.dart';
import '../providers/tube_player_provider.dart';
import '../services/tube_database_service.dart';
import '../services/tube_download_service.dart';
import '../services/tube_storage_service.dart';
import '../theme/tube_theme.dart';
import '../widgets/tube_image.dart';
import '../widgets/tube_video_card.dart';
import 'tube_channel_screen.dart';
import 'tube_downloads_screen.dart';
import 'tube_privacy_settings_screen.dart';
import 'tube_onboarding_screen.dart';
import '../services/tube_user_profile_service.dart';
import '../services/tube_session_service.dart';
import '../widgets/tube_account_action.dart';

/// Modern YouTube "You" screen replacing the legacy Library tab.
/// Features:
/// - User profile header (Accountless, privacy badge, gear icon)
/// - History horizontal carousel with red progress bar and "View all"
/// - Playlists horizontal carousel (Liked videos, Watch Later, Custom playlists)
/// - Action rows: Downloads (with offline count), Followed channels, Privacy & Data
class TubeYouScreen extends StatefulWidget {
  const TubeYouScreen({super.key});

  @override
  State<TubeYouScreen> createState() => _TubeYouScreenState();
}

class _TubeYouScreenState extends State<TubeYouScreen> {
  final TubeStorageService _storageService = TubeStorageService();
  final TubeDownloadService _downloadService = TubeDownloadService();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: Listenable.merge([TubeSessionService(), _storageService]),
      builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final account = TubeSessionService();
    final handle = account.usesAccountData
        ? account.userHandle
        : (TubeUserProfileService().username.isEmpty
            ? ''
            : '@${TubeUserProfileService().username}');
    final history = _storageService.getWatchHistory();
    final watchLater = _storageService.getWatchLater();
    final localLikes = _storageService.getLocalLikes();
    final playlists = _storageService.getPlaylists();
    final followedChannels = _storageService.getFollowedChannels();
    final downloadedCount = _downloadService.completedCount;
    final provider = context.read<TubePlayerProvider>();

    return Scaffold(
      backgroundColor: TubeTheme.background,
      appBar: AppBar(
        backgroundColor: TubeTheme.background,
        elevation: 0,
        title: const Text('You', style: TubeTheme.appBarTitle),
        actions: [
          const TubeAccountAction(),
          IconButton(
            icon:
                const Icon(Icons.shield_outlined, color: TubeTheme.textPrimary),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const TubePrivacySettingsScreen()),
              ).then((_) {
                if (mounted) setState(() {});
              });
            },
            tooltip: 'Privacy & Security',
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined,
                color: TubeTheme.textPrimary),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const TubePrivacySettingsScreen()),
              ).then((_) {
                if (mounted) setState(() {});
              });
            },
            tooltip: 'Settings',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // 1. Profile / Accountless Header (YouTube style)
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: const BoxDecoration(
                    color: TubeTheme.surfaceVariant,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(Icons.person, size: 32, color: Colors.white70),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        TubeSessionService().isLoggedIn &&
                                !_storageService.isIncognito
                            ? TubeSessionService().userChannelName
                            : TubeUserProfileService().displayName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: TubeTheme.textPrimary,
                        ),
                      ),
                      if (handle.isNotEmpty)
                        Text(handle, style: TubeTheme.bodySmall),
                      TextButton(
                          onPressed: () async {
                            await Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const TubeOnboardingScreen(
                                        editing: true)));
                            if (mounted) setState(() {});
                          },
                          child: const Text('Edit local profile')),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: TubeTheme.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color:
                                      TubeTheme.accent.withValues(alpha: 0.3),
                                  width: 0.8),
                            ),
                            child: Text(
                              TubeSessionService().isLoggedIn &&
                                      !_storageService.isIncognito
                                  ? 'Connected'
                                  : 'Guest',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: TubeTheme.accent,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            '•  Local preferences',
                            style: TextStyle(
                              fontSize: 12,
                              color: TubeTheme.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // 2. History Section (Horizontal Carousel)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('History', style: TubeTheme.sectionTitle),
                TextButton(
                  onPressed: () => _openHistoryList(context),
                  style: TextButton.styleFrom(
                    foregroundColor: TubeTheme.textPrimary,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: const Text('View all',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),

          if (history.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: TubeTheme.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'No watch history yet. Videos you watch will appear here.',
                  style: TextStyle(color: TubeTheme.textTertiary, fontSize: 13),
                ),
              ),
            )
          else
            SizedBox(
              height: 160,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: history.take(12).length,
                itemBuilder: (context, idx) {
                  final h = history[idx];
                  return GestureDetector(
                    onTap: () {
                      provider.playVideo(h.video,
                          startPositionMs: h.positionMs);
                    },
                    child: Container(
                      width: 150,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(
                                TubeTheme.thumbnailRadiusCompact),
                            child: Stack(
                              children: [
                                AspectRatio(
                                  aspectRatio: 16 / 9,
                                  child: TubeNetworkImage(
                                    imageUrl: h.video.thumbnailUrl,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                // Bottom Progress Line (YouTube red progress)
                                Positioned(
                                  bottom: 0,
                                  left: 0,
                                  right: 0,
                                  child: LinearProgressIndicator(
                                    value: h.completionRatio,
                                    backgroundColor: Colors.white24,
                                    valueColor: const AlwaysStoppedAnimation(
                                        TubeTheme.progressRed),
                                    minHeight: 2.5,
                                  ),
                                ),
                                if (h.isResumeAvailable)
                                  Positioned(
                                    top: 4,
                                    left: 4,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 4, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.black87,
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      child: Text(
                                        h.formattedResumePosition,
                                        style: const TextStyle(
                                          fontSize: 9,
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            h.video.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: TubeTheme.textPrimary,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            h.video.channelTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TubeTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

          const Divider(color: TubeTheme.divider, height: 24),

          // 3. Playlists Section (Horizontal Carousel)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Playlists', style: TubeTheme.sectionTitle),
                IconButton(
                  icon: const Icon(Icons.add,
                      color: TubeTheme.textPrimary, size: 22),
                  onPressed: () => _createNewPlaylist(context),
                  tooltip: 'New Playlist',
                ),
              ],
            ),
          ),

          SizedBox(
            height: 140,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                // Liked Videos Playlist Card
                _buildPlaylistCard(
                  title: 'Liked videos',
                  subtitle: '${localLikes.length} videos',
                  icon: Icons.thumb_up,
                  thumbnailUrl: localLikes.isNotEmpty
                      ? localLikes.first.thumbnailUrl
                      : null,
                  onTap: () =>
                      _openVideoList(context, 'Liked videos', localLikes),
                ),

                // Watch Later Playlist Card
                _buildPlaylistCard(
                  title: 'Watch Later',
                  subtitle: '${watchLater.length} videos',
                  icon: Icons.bookmark,
                  thumbnailUrl: watchLater.isNotEmpty
                      ? watchLater.first.thumbnailUrl
                      : null,
                  onTap: () =>
                      _openVideoList(context, 'Watch Later', watchLater),
                ),

                // Custom Playlists
                ...playlists.map((pl) => _buildPlaylistCard(
                      title: pl.title,
                      subtitle: '${pl.count} videos',
                      icon: Icons.queue_music,
                      thumbnailUrl:
                          pl.thumbnailUrl.isNotEmpty ? pl.thumbnailUrl : null,
                      onTap: () => _openVideoList(context, pl.title, pl.videos),
                      onDelete: () async {
                        await _storageService.deletePlaylist(pl.id);
                        await TubeDatabaseService.instance
                            .deletePlaylist(pl.id);
                        setState(() {});
                      },
                    )),
              ],
            ),
          ),

          const Divider(color: TubeTheme.divider, height: 24),

          // 4. Action Rows (Downloads, Subscriptions, History, Settings)
          ListTile(
            leading: const Icon(Icons.auto_awesome_outlined),
            title: const Text('Video intelligence'),
            subtitle: const Text(
                'Transcript summaries, questions, saved notes and a labelled demo'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const TubeVideoIntelligenceScreen())),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: const Icon(Icons.download_done,
                color: TubeTheme.textPrimary, size: 24),
            title: const Text('Downloads',
                style: TextStyle(
                    color: TubeTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w500)),
            subtitle: Text(
              downloadedCount > 0
                  ? '$downloadedCount video${downloadedCount > 1 ? "s" : ""} available offline'
                  : '0 videos offline',
              style: TubeTheme.bodySmall,
            ),
            trailing: const Icon(Icons.chevron_right,
                color: TubeTheme.textTertiary, size: 20),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TubeDownloadsScreen()),
              );
            },
          ),

          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: const Icon(Icons.subscriptions_outlined,
                color: TubeTheme.textPrimary, size: 24),
            title: const Text('Subscriptions',
                style: TextStyle(
                    color: TubeTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w500)),
            subtitle: Text(
              '${followedChannels.length} channel${followedChannels.length != 1 ? "s" : ""} followed locally',
              style: TubeTheme.bodySmall,
            ),
            trailing: const Icon(Icons.chevron_right,
                color: TubeTheme.textTertiary, size: 20),
            onTap: () => _openFollowedChannels(context),
          ),

          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: const Icon(Icons.history,
                color: TubeTheme.textPrimary, size: 24),
            title: const Text('Watch History',
                style: TextStyle(
                    color: TubeTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w500)),
            trailing: Text('${history.length}', style: TubeTheme.bodySmall),
            onTap: () => _openHistoryList(context),
          ),

          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: const Icon(Icons.security,
                color: TubeTheme.textPrimary, size: 24),
            title: const Text('Privacy & Security',
                style: TextStyle(
                    color: TubeTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w500)),
            subtitle: const Text(
                'Incognito mode, history pausing, clear local data',
                style: TubeTheme.bodySmall),
            trailing: const Icon(Icons.chevron_right,
                color: TubeTheme.textTertiary, size: 20),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const TubePrivacySettingsScreen()),
              ).then((_) {
                if (mounted) setState(() {});
              });
            },
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildPlaylistCard({
    required String title,
    required String subtitle,
    required IconData icon,
    String? thumbnailUrl,
    required VoidCallback onTap,
    VoidCallback? onDelete,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius:
                  BorderRadius.circular(TubeTheme.thumbnailRadiusCompact),
              child: Container(
                width: 140,
                height: 78,
                decoration:
                    const BoxDecoration(color: TubeTheme.surfaceVariant),
                child: thumbnailUrl != null
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          TubeNetworkImage(
                              imageUrl: thumbnailUrl, fit: BoxFit.cover),
                          Container(
                            color: Colors.black38,
                            child: Center(
                              child: Icon(icon, color: Colors.white, size: 26),
                            ),
                          ),
                        ],
                      )
                    : Center(
                        child: Icon(icon, color: Colors.white70, size: 28),
                      ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: TubeTheme.textPrimary,
                        ),
                      ),
                      Text(subtitle, style: TubeTheme.bodySmall),
                    ],
                  ),
                ),
                if (onDelete != null)
                  GestureDetector(
                    onTap: onDelete,
                    child: const Icon(Icons.delete_outline,
                        size: 18, color: TubeTheme.textTertiary),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openHistoryList(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (pageCtx) => Scaffold(
          backgroundColor: TubeTheme.background,
          appBar: AppBar(
            backgroundColor: TubeTheme.background,
            title: const Text('History'),
            actions: [
              IconButton(
                icon: const Icon(Icons.delete_sweep),
                onPressed: () async {
                  await _storageService.clearWatchHistory();
                  await TubeDatabaseService.instance.clearWatchHistory();
                  if (pageCtx.mounted) {
                    Navigator.pop(pageCtx);
                  }
                },
                tooltip: 'Clear History',
              ),
            ],
          ),
          body: _storageService.getWatchHistory().isEmpty
              ? const Center(
                  child: Text('Watch history is empty',
                      style: TextStyle(color: TubeTheme.textTertiary)))
              : ListView.separated(
                  itemCount: _storageService.getWatchHistory().length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, idx) {
                    final h = _storageService.getWatchHistory()[idx];
                    return TubeVideoCard(video: h.video);
                  },
                ),
        ),
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  void _openVideoList(
      BuildContext context, String title, List<TubeVideoItem> videos) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: TubeTheme.background,
          appBar: AppBar(
            backgroundColor: TubeTheme.background,
            title: Text(title),
          ),
          body: videos.isEmpty
              ? Center(
                  child: Text('No videos in $title',
                      style: const TextStyle(color: TubeTheme.textTertiary)))
              : ListView.separated(
                  itemCount: videos.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, idx) {
                    return TubeVideoCard(video: videos[idx]);
                  },
                ),
        ),
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  void _openFollowedChannels(BuildContext context) {
    final channels = _storageService.getFollowedChannels();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: TubeTheme.background,
          appBar: AppBar(
            backgroundColor: TubeTheme.background,
            title: const Text('Subscriptions'),
          ),
          body: channels.isEmpty
              ? const Center(
                  child: Text(
                      'No subscriptions yet. Follow channels to see them here.',
                      style: TextStyle(color: TubeTheme.textTertiary)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: channels.length,
                  separatorBuilder: (_, __) =>
                      const Divider(color: TubeTheme.divider, height: 1),
                  itemBuilder: (ctx, idx) {
                    final ch = channels[idx];
                    return ListTile(
                      leading: CircleAvatar(
                        radius: 20,
                        backgroundColor: TubeTheme.surfaceVariant,
                        backgroundImage: ch.avatarUrl.isNotEmpty
                            ? NetworkImage(ch.avatarUrl)
                            : null,
                        child: ch.avatarUrl.isEmpty
                            ? Text(
                                ch.title.isNotEmpty
                                    ? ch.title[0].toUpperCase()
                                    : 'C',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold),
                              )
                            : null,
                      ),
                      title: Text(ch.title, style: TubeTheme.titleMedium),
                      trailing: const Icon(Icons.chevron_right,
                          color: TubeTheme.textTertiary, size: 20),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TubeChannelScreen(
                                channelId: ch.id, channelTitle: ch.title),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  void _createNewPlaylist(BuildContext context) {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TubeTheme.surface,
        title: const Text('New playlist',
            style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
        content: TextField(
          controller: textController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Playlist title',
            hintStyle: TextStyle(color: TubeTheme.textTertiary),
            focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: TubeTheme.accent)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: TubeTheme.textTertiary)),
          ),
          TextButton(
            onPressed: () async {
              final name = textController.text.trim();
              if (name.isNotEmpty) {
                await _storageService.createPlaylist(name);
                final id = 'pl_${DateTime.now().millisecondsSinceEpoch}';
                await TubeDatabaseService.instance.createPlaylist(id, name);
                if (mounted) setState(() {});
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Create',
                style: TextStyle(
                    color: TubeTheme.accent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
