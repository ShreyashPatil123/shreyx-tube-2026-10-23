import '../services/tube_share_service.dart';
import '../services/tube_session_service.dart';
import 'tube_auth_screen.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/tube_models.dart';
import '../providers/tube_player_provider.dart';
import '../services/tube_download_service.dart';
import '../services/tube_link_service.dart';
import '../theme/tube_theme.dart';
import '../widgets/tube_caption_overlay.dart';
import '../widgets/tube_image.dart';
import '../widgets/tube_player_gestures.dart';
import '../widgets/tube_sheets.dart';
import '../widgets/tube_video_card.dart';
import 'tube_channel_screen.dart';
import 'tube_video_intelligence_screen.dart';

/// Complete modern YouTube-style watch page with embedded native Media3 video surface,
/// gesture HUDs, captions overlay, modern action pills, expandable description box,
/// and Up Next / related recommendations.
class TubeWatchScreen extends StatefulWidget {
  final VoidCallback onCollapse;
  final Widget? videoSurface;

  const TubeWatchScreen(
      {super.key, required this.onCollapse, this.videoSurface});

  @override
  State<TubeWatchScreen> createState() => _TubeWatchScreenState();
}

class _TubeWatchScreenState extends State<TubeWatchScreen> {
  bool _showControls = true;
  Timer? _controlsTimer;
  bool _isDescriptionExpanded = false;
  int _activeTab = 0; // 0 = Up Next / Related, 1 = Queue

  @override
  void initState() {
    super.initState();
    _scheduleControlsHide();
  }

  void _scheduleControlsHide() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      final player = context.read<TubePlayerProvider>();
      if (player.isPlaying) {
        setState(() => _showControls = false);
      } else {
        _scheduleControlsHide();
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleControlsHide();
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final mins = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$mins:$secs';
    }
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TubePlayerProvider>();
    final video = provider.currentVideoItem;
    final resolved = provider.resolvedVideo;

    if (video == null && resolved == null) {
      return const Scaffold(
        backgroundColor: TubeTheme.background,
        body: Center(
          child: Text('No media active',
              style: TextStyle(color: TubeTheme.textTertiary)),
        ),
      );
    }

    final title = resolved?.title ?? video?.title ?? 'YouTube Video';
    final channel = resolved?.uploader ?? video?.channelTitle ?? 'Channel';
    final channelId = video?.channelId ?? '';
    final views =
        video?.formattedViews.isNotEmpty == true ? video!.formattedViews : '';
    final uploaded =
        video?.formattedDate.isNotEmpty == true ? video!.formattedDate : '';

    return Scaffold(
      backgroundColor: TubeTheme.background,
      body: SafeArea(
        top: !provider.isFullscreen,
        bottom: !provider.isFullscreen,
        child: LayoutBuilder(
            builder: (context, bounds) => Column(
                  children: [
                    // 1. VIDEO PLAYER CONTAINER (16:9 or Fullscreen)
                    AspectRatio(
                      aspectRatio: provider.isFullscreen
                          ? bounds.maxWidth / bounds.maxHeight
                          : math.max(
                              (provider.aspectRatio > 0
                                      ? provider.aspectRatio
                                      : 16 / 9)
                                  .clamp(0.3, 3.0),
                              bounds.maxWidth / (bounds.maxHeight * 0.55)),
                      child: Container(
                        color: Colors.black,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // Native Media3 Surface with Gestures
                            TubePlayerGestures(
                              onSingleTap: _toggleControls,
                              onCollapse: provider.isFullscreen
                                  ? provider.exitFullscreen
                                  : widget.onCollapse,
                              onBrightnessChanged: provider.setBrightness,
                              onVolumeChanged: provider.setVolume,
                              onZoomChanged: provider.isFullscreen
                                  ? provider.setVideoZoom
                                  : null,
                              zoom: provider.videoZoom,
                              onDoubleTapLeft: () => provider.seekRelative(-10),
                              onDoubleTapRight: () => provider.seekRelative(10),
                              child: provider.isMembersOnly
                                  ? const SizedBox.shrink()
                                  : widget.videoSurface ??
                                      const SizedBox.shrink(),
                            ),

                            // Captions Overlay
                            TubeCaptionOverlay(
                                cueText: provider.activeCaptionText),

                            // High-Resolution Poster Image & Loading HUD while preparing
                            if (provider.isLoading ||
                                (provider.currentStream == null &&
                                    provider.status == TubePlayerStatus.idle))
                              Stack(
                                fit: StackFit.expand,
                                children: [
                                  TubeNetworkImage(
                                    imageUrl: video?.thumbnailUrl ??
                                        resolved?.thumbnailUrl ??
                                        '',
                                    fit: BoxFit.cover,
                                  ),
                                  if (provider.isLoading)
                                    Container(
                                      color: Colors.black54,
                                      child: Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const CircularProgressIndicator(
                                              color: TubeTheme.progressRed,
                                              strokeWidth: 3,
                                            ),
                                            const SizedBox(height: 14),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 14,
                                                      vertical: 6),
                                              decoration: BoxDecoration(
                                                color: Colors.black87,
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                                border: Border.all(
                                                    color: Colors.white24,
                                                    width: 0.8),
                                              ),
                                              child: Text(
                                                _getLoadingStatusText(
                                                    provider.status),
                                                style: const TextStyle(
                                                  color: TubeTheme.textPrimary,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),

                            // Non-Destructive Buffering HUD
                            if (provider.isBuffering &&
                                !provider.isLoading &&
                                !provider.isMembersOnly)
                              const Center(
                                child: CircularProgressIndicator(
                                  color: TubeTheme.progressRed,
                                  strokeWidth: 3,
                                ),
                              ),

                            // Error HUD with Retry button
                            if (!provider.isMembersOnly &&
                                (provider.status == TubePlayerStatus.error ||
                                    (provider.errorMessage != null &&
                                        !provider.isRetrying)))
                              Container(
                                color: Colors.black87,
                                child: Center(
                                  child: SingleChildScrollView(
                                      child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.error_outline,
                                          color: TubeTheme.error, size: 40),
                                      const SizedBox(height: 10),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 24.0),
                                        child: Text(
                                          provider.errorMessage ??
                                              'Playback error occurred',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                              color: TubeTheme.textSecondary,
                                              fontSize: 13),
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: TubeTheme.accent,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(18)),
                                        ),
                                        icon:
                                            const Icon(Icons.refresh, size: 18),
                                        label: const Text('Retry Video',
                                            style: TextStyle(
                                                fontWeight: FontWeight.w600)),
                                        onPressed: () => provider.retry(),
                                      ),
                                      TextButton(
                                          onPressed: () =>
                                              TubeLinkService.openYouTube(
                                                  TubeLinkService.originalFor(
                                                          video?.id ?? '') ??
                                                      video?.watchUrl ??
                                                      ''),
                                          child: const Text('Open in YouTube')),
                                    ],
                                  )),
                                ),
                              ),

                            // Controls Overlay
                            if (provider.isMembersOnly)
                              Container(
                                color: Colors.black87,
                                padding:
                                    const EdgeInsets.fromLTRB(40, 12, 16, 12),
                                child: SingleChildScrollView(
                                    child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('MEMBERS ONLY',
                                        style: TextStyle(
                                            color: TubeTheme.membersGold,
                                            fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 8),
                                    Text(
                                      provider.errorMessage ??
                                          'Connect an eligible YouTube account to try this members-only video, or open it in YouTube.',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          color: TubeTheme.textPrimary,
                                          fontSize: 13),
                                    ),
                                    TextButton(
                                        onPressed: () async {
                                          final id =
                                              provider.currentVideoItem?.id;
                                          if (!TubeSessionService()
                                              .usesPrivateFeed) {
                                            await Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                    builder: (_) =>
                                                        const TubeAuthScreen()));
                                          }
                                          if (context.mounted &&
                                              provider.currentVideoItem?.id ==
                                                  id &&
                                              TubeSessionService()
                                                  .usesPrivateFeed) {
                                            provider.retry();
                                          }
                                        },
                                        child: Text(
                                            TubeSessionService().usesPrivateFeed
                                                ? 'Retry with connected account'
                                                : 'Connect YouTube account')),
                                    TextButton(
                                        onPressed: () =>
                                            TubeLinkService.openYouTube(
                                                TubeLinkService.originalFor(
                                                        video!.id) ??
                                                    video.watchUrl),
                                        child: const Text('Open in YouTube')),
                                    TextButton.icon(
                                      icon: const Icon(Icons.link),
                                      label: const Text('Copy Link'),
                                      onPressed: () async {
                                        await Clipboard.setData(ClipboardData(
                                            text: video!.watchUrl));
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(const SnackBar(
                                                  content: Text(
                                                      'YouTube link copied')));
                                        }
                                      },
                                    ),
                                  ],
                                )),
                              ),
                            if (provider.isMembersOnly)
                              Positioned(
                                  top: 0,
                                  left: 0,
                                  child: IconButton(
                                    icon: const Icon(Icons.keyboard_arrow_down,
                                        color: Colors.white),
                                    onPressed: widget.onCollapse,
                                  )),
                            if (_showControls &&
                                !provider.isMembersOnly &&
                                provider.status != TubePlayerStatus.error &&
                                provider.errorMessage == null) ...[
                              // Top Bar (Collapse, Title in Fullscreen, Autoplay, CC, Quality, Fullscreen)
                              Positioned(
                                top: 0,
                                left: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.black87,
                                        Colors.transparent
                                      ],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      IconButton(
                                        icon: const Icon(
                                            Icons.keyboard_arrow_down,
                                            color: Colors.white,
                                            size: 28),
                                        onPressed: provider.isFullscreen
                                            ? provider.exitFullscreen
                                            : widget.onCollapse,
                                        tooltip: provider.isFullscreen
                                            ? 'Exit fullscreen'
                                            : 'Minimize to Mini-Player',
                                      ),
                                      if (provider.isFullscreen) ...[
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ] else
                                        const Spacer(),

                                      if (provider.isFullscreen &&
                                          provider.videoZoom > 1)
                                        IconButton(
                                            tooltip: 'Fit video to screen',
                                            onPressed: () =>
                                                provider.setVideoZoom(1),
                                            icon: const Icon(Icons.fit_screen,
                                                color: Colors.white)),
                                      // Autoplay Toggle (YouTube mobile style toggle in top bar)
                                      IconButton(
                                        icon: Icon(
                                          provider.autoPlayNext
                                              ? Icons.play_circle_filled
                                              : Icons.play_circle_outline,
                                          color: provider.autoPlayNext
                                              ? Colors.white
                                              : Colors.white54,
                                          size: 22,
                                        ),
                                        tooltip:
                                            'Autoplay ${provider.autoPlayNext ? "on" : "off"}',
                                        onPressed: () =>
                                            provider.toggleAutoPlayNext(),
                                      ),

                                      // CC Subtitle button
                                      IconButton(
                                        icon: Icon(
                                          provider.currentSubtitle != null
                                              ? Icons.closed_caption
                                              : Icons.closed_caption_outlined,
                                          color:
                                              provider.currentSubtitle != null
                                                  ? const Color(0xFF00E5FF)
                                                  : Colors.white70,
                                          size: 22,
                                        ),
                                        onPressed: () =>
                                            showSubtitlePickerSheet(
                                                context, provider),
                                        tooltip: 'Captions',
                                      ),

                                      // Quality / Settings button
                                      IconButton(
                                        icon: const Icon(
                                            Icons.settings_outlined,
                                            color: Colors.white,
                                            size: 22),
                                        onPressed: () => showQualityPickerSheet(
                                            context, provider),
                                        tooltip:
                                            'Quality (${provider.selectedQuality})',
                                      ),

                                      // Fullscreen Toggle
                                      IconButton(
                                        icon: Icon(
                                          provider.isFullscreen
                                              ? Icons.fullscreen_exit
                                              : Icons.fullscreen,
                                          color: Colors.white,
                                          size: 26,
                                        ),
                                        onPressed: () =>
                                            provider.toggleFullscreen(),
                                        tooltip: provider.isFullscreen
                                            ? 'Exit Fullscreen'
                                            : 'Fullscreen',
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              // Center Play/Pause & Seek Buttons
                              Center(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.replay_10,
                                          color: Colors.white, size: 36),
                                      onPressed: () =>
                                          provider.seekRelative(-10),
                                      tooltip: 'Rewind 10s',
                                    ),
                                    const SizedBox(width: 24),
                                    Container(
                                      width: 60,
                                      height: 60,
                                      decoration: const BoxDecoration(
                                        color: Colors.black54,
                                        shape: BoxShape.circle,
                                      ),
                                      child: IconButton(
                                        iconSize: 40,
                                        icon: Icon(
                                          provider.isPlaying
                                              ? Icons.pause_rounded
                                              : Icons.play_arrow_rounded,
                                          color: Colors.white,
                                        ),
                                        onPressed: () =>
                                            provider.togglePlayPause(),
                                      ),
                                    ),
                                    const SizedBox(width: 24),
                                    IconButton(
                                      icon: const Icon(Icons.forward_10,
                                          color: Colors.white, size: 36),
                                      onPressed: () =>
                                          provider.seekRelative(10),
                                      tooltip: 'Forward 10s',
                                    ),
                                  ],
                                ),
                              ),

                              // Bottom Scrubber Bar & Timestamps
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 4),
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.transparent,
                                        Colors.black87
                                      ],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          trackHeight: 2.5,
                                          thumbShape:
                                              const RoundSliderThumbShape(
                                                  enabledThumbRadius: 6),
                                          overlayShape:
                                              const RoundSliderOverlayShape(
                                                  overlayRadius: 12),
                                          activeTrackColor:
                                              TubeTheme.progressRed,
                                          inactiveTrackColor: Colors.white24,
                                          thumbColor: TubeTheme.progressRed,
                                        ),
                                        child: Slider(
                                          min: 0.0,
                                          max: provider.duration.inMilliseconds
                                                      .toDouble() >
                                                  0
                                              ? provider.duration.inMilliseconds
                                                  .toDouble()
                                              : 1.0,
                                          value: provider
                                              .position.inMilliseconds
                                              .toDouble()
                                              .clamp(
                                                0.0,
                                                provider.duration.inMilliseconds
                                                            .toDouble() >
                                                        0
                                                    ? provider
                                                        .duration.inMilliseconds
                                                        .toDouble()
                                                    : 1.0,
                                              ),
                                          onChanged: provider.isLive
                                              ? null
                                              : (val) {
                                                  provider.seek(Duration(
                                                      milliseconds:
                                                          val.toInt()));
                                                },
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8.0, vertical: 2.0),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            if (provider.isLive)
                                              TextButton.icon(
                                                onPressed: provider.goLive,
                                                icon: const Icon(Icons.circle,
                                                    color: TubeTheme.live,
                                                    size: 9),
                                                label: const Text('LIVE',
                                                    style: TextStyle(
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.bold)),
                                              )
                                            else
                                              Text(
                                                _formatDuration(
                                                    provider.position),
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: TubeTheme.textPrimary,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            if (!provider.isLive)
                                              Text(
                                                _formatDuration(
                                                    provider.duration),
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color:
                                                      TubeTheme.textSecondary,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    // If in fullscreen, only video is visible
                    if (provider.isFullscreen) const Spacer(),

                    // 2. WATCH PAGE DETAILS & RELATED CONTENT (When not fullscreen)
                    if (!provider.isFullscreen)
                      Expanded(
                        child: ListView(
                          padding: EdgeInsets.zero,
                          children: [
                            // Video Title
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                              child: Text(
                                title,
                                style: TubeTheme.titleLarge,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),

                            // Quick Metadata Preview Row (views • upload date • ...more)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16.0, vertical: 2.0),
                              child: GestureDetector(
                                onTap: () => setState(() =>
                                    _isDescriptionExpanded =
                                        !_isDescriptionExpanded),
                                child: Row(
                                  children: [
                                    if (views.isNotEmpty)
                                      Text(
                                        views,
                                        style: TubeTheme.bodySmall.copyWith(
                                            color: TubeTheme.textSecondary),
                                      ),
                                    if (views.isNotEmpty && uploaded.isNotEmpty)
                                      Text(' \u2022 ',
                                          style: TubeTheme.bodySmall.copyWith(
                                              color: TubeTheme.textTertiary)),
                                    if (uploaded.isNotEmpty)
                                      Text(
                                        uploaded,
                                        style: TubeTheme.bodySmall.copyWith(
                                            color: TubeTheme.textSecondary),
                                      ),
                                    if (views.isNotEmpty || uploaded.isNotEmpty)
                                      const SizedBox(width: 6),
                                    Text(
                                      _isDescriptionExpanded
                                          ? 'less'
                                          : '...more',
                                      style: TubeTheme.bodySmall.copyWith(
                                        color: TubeTheme.textPrimary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // Channel & Subscribe/Follow Row (Modern YouTube Pill Layout)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16.0, vertical: 10.0),
                              child: Row(
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      if (channelId.isNotEmpty) {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => TubeChannelScreen(
                                                channelId: channelId,
                                                channelTitle: channel),
                                          ),
                                        );
                                      }
                                    },
                                    child: ClipOval(
                                      child: TubeNetworkImage(
                                        imageUrl: video?.channelAvatarUrl ?? '',
                                        width: 36,
                                        height: 36,
                                        fit: BoxFit.cover,
                                        errorWidget: const CircleAvatar(
                                          radius: 18,
                                          backgroundColor:
                                              TubeTheme.surfaceVariant,
                                          child: Icon(Icons.person,
                                              color: TubeTheme.textSecondary),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () {
                                        if (channelId.isNotEmpty) {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => TubeChannelScreen(
                                                  channelId: channelId,
                                                  channelTitle: channel),
                                            ),
                                          );
                                        }
                                      },
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            channel,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: TubeTheme.textPrimary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  // Follow / Subscribe Pill Button (YouTube style: solid white when un-subscribed, grey when subscribed)
                                  GestureDetector(
                                    onTap: () => provider.toggleFollowChannel(),
                                    child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 200),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: provider.isChannelFollowed
                                            ? TubeTheme.surfaceVariant
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (provider.isChannelFollowed) ...[
                                            const Icon(Icons.check,
                                                size: 14, color: Colors.white),
                                            const SizedBox(width: 4),
                                          ],
                                          Text(
                                            provider.isChannelFollowed
                                                ? 'Following'
                                                : 'Follow',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: provider.isChannelFollowed
                                                  ? Colors.white
                                                  : Colors.black,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Action Buttons Row (Like, Watch Later, Share, Download, Save, PiP)
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              child: Row(
                                children: [
                                  // Like Pill
                                  _ActionPill(
                                    icon: provider.isLikedLocally
                                        ? Icons.thumb_up
                                        : Icons.thumb_up_outlined,
                                    label: provider.isLikedLocally
                                        ? 'Liked'
                                        : 'Like',
                                    isSelected: provider.isLikedLocally,
                                    onTap: () => provider.toggleLocalLike(),
                                  ),
                                  const SizedBox(width: 8),

                                  // Dislike Pill (Standard YouTube action)
                                  _ActionPill(
                                    icon: Icons.thumb_down_outlined,
                                    label: 'Dislike',
                                    isSelected: false,
                                    onTap: () {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content:
                                              Text('Marked as not recommended'),
                                          duration: Duration(seconds: 1),
                                        ),
                                      );
                                    },
                                  ),
                                  const SizedBox(width: 8),

                                  // Share Public URL Pill
                                  _ActionPill(
                                    icon: Icons.auto_awesome_outlined,
                                    label: 'Understand',
                                    isSelected: false,
                                    onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                TubeVideoIntelligenceScreen(
                                                  videoId: video?.id ??
                                                      resolved!.videoId,
                                                  title: title,
                                                  subtitles:
                                                      resolved?.subtitles ?? [],
                                                  onSeek: (id, position) {
                                                    if (provider
                                                            .currentVideoItem
                                                            ?.id !=
                                                        id) {
                                                      return false;
                                                    }
                                                    provider.seek(position);
                                                    return true;
                                                  },
                                                ))),
                                  ),
                                  const SizedBox(width: 8),
                                  _ActionPill(
                                    icon: Icons.share_outlined,
                                    label: 'Share',
                                    isSelected: false,
                                    onTap: () {
                                      if (video != null) {
                                        TubeShareService.share(context, video);
                                      }
                                    },
                                  ),
                                  const SizedBox(width: 8),

                                  // Offline Download Pill
                                  if (video != null &&
                                      !provider.isMembersOnly &&
                                      !provider.isLive)
                                    _ActionPill(
                                      icon: TubeDownloadService()
                                              .isDownloaded(video.id)
                                          ? Icons.download_done
                                          : Icons.download_outlined,
                                      label: TubeDownloadService()
                                              .isDownloaded(video.id)
                                          ? 'Downloaded'
                                          : 'Download',
                                      isSelected: TubeDownloadService()
                                          .isDownloaded(video.id),
                                      onTap: () async {
                                        final currentStream =
                                            provider.currentStream;
                                        if (currentStream != null) {
                                          await TubeDownloadService()
                                              .startDownload(
                                            video: video,
                                            stream: currentStream,
                                          );
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                backgroundColor:
                                                    TubeTheme.surfaceVariant,
                                                content: Text(
                                                    'Downloading "${video.title}" in background...'),
                                              ),
                                            );
                                          }
                                        } else {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                                content: Text(
                                                    'Stream resolving, please wait...')),
                                          );
                                        }
                                      },
                                    ),
                                  const SizedBox(width: 8),

                                  // Watch Later Pill
                                  _ActionPill(
                                    icon: provider.isInWatchLater
                                        ? Icons.bookmark
                                        : Icons.bookmark_border,
                                    label: provider.isInWatchLater
                                        ? 'Saved'
                                        : 'Watch Later',
                                    isSelected: provider.isInWatchLater,
                                    onTap: () => provider.toggleWatchLater(),
                                  ),
                                  const SizedBox(width: 8),

                                  // Add to Playlist Pill
                                  if (video != null)
                                    _ActionPill(
                                      icon: Icons.playlist_add,
                                      label: 'Save',
                                      isSelected: false,
                                      onTap: () => showAddToPlaylistSheet(
                                          context, video),
                                    ),
                                  const SizedBox(width: 8),

                                  // Enter PiP Pill
                                  if (!provider.isMembersOnly)
                                    _ActionPill(
                                      icon: Icons.picture_in_picture_alt,
                                      label: 'PiP',
                                      isSelected: false,
                                      onTap: () => provider.enterPip(),
                                    ),
                                ],
                              ),
                            ),

                            // Expandable YouTube-style Description Container
                            if (video?.description.isNotEmpty == true)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16.0, vertical: 10.0),
                                child: GestureDetector(
                                  onTap: () => setState(() =>
                                      _isDescriptionExpanded =
                                          !_isDescriptionExpanded),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: TubeTheme.surfaceVariant,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              '$views   $uploaded',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: TubeTheme.textPrimary,
                                              ),
                                            ),
                                            const Spacer(),
                                            Icon(
                                              _isDescriptionExpanded
                                                  ? Icons.keyboard_arrow_up
                                                  : Icons.keyboard_arrow_down,
                                              size: 20,
                                              color: TubeTheme.textSecondary,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          video!.description,
                                          maxLines:
                                              _isDescriptionExpanded ? 100 : 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: TubeTheme.textPrimary,
                                            height: 1.4,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          _isDescriptionExpanded
                                              ? 'Show less'
                                              : '...more',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: TubeTheme.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),

                            const Divider(color: TubeTheme.divider, height: 20),

                            // Filter Chips: Up Next / Related & Queue
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16.0),
                              child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      GestureDetector(
                                        onTap: () =>
                                            setState(() => _activeTab = 0),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 14, vertical: 7),
                                          decoration: _activeTab == 0
                                              ? TubeTheme.chipSelected
                                              : TubeTheme.chipUnselected,
                                          child: Text(
                                            'Up Next (${provider.relatedVideos.length})',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: _activeTab == 0
                                                  ? Colors.black
                                                  : TubeTheme.textPrimary,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      GestureDetector(
                                        onTap: () =>
                                            setState(() => _activeTab = 1),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 14, vertical: 7),
                                          decoration: _activeTab == 1
                                              ? TubeTheme.chipSelected
                                              : TubeTheme.chipUnselected,
                                          child: Text(
                                            'Queue (${provider.queue.length})',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: _activeTab == 1
                                                  ? Colors.black
                                                  : TubeTheme.textPrimary,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  )),
                            ),

                            const SizedBox(height: 12),

                            // Content for Up Next vs Queue
                            if (_activeTab == 0) ...[
                              if (provider.isLoadingRelated)
                                const Padding(
                                  padding: EdgeInsets.all(32.0),
                                  child: Center(
                                    child: CircularProgressIndicator(
                                        color: TubeTheme.progressRed,
                                        strokeWidth: 2),
                                  ),
                                )
                              else if (provider.relatedVideos.isEmpty)
                                const Padding(
                                    padding: EdgeInsets.all(24.0),
                                    child: Center(
                                      child: Text('No related videos found.',
                                          style: TextStyle(
                                              color: TubeTheme.textTertiary)),
                                    ))
                              else
                                ...provider.relatedVideos.map((r) =>
                                    TubeVideoCard(video: r, isCompact: true)),
                            ] else ...[
                              if (provider.queue.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.all(32.0),
                                  child: Center(
                                    child: Text(
                                      'Queue is empty. Tap the menu on any video to add.',
                                      style: TextStyle(
                                          color: TubeTheme.textTertiary),
                                    ),
                                  ),
                                )
                              else
                                ReorderableListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: provider.queue.length,
                                  buildDefaultDragHandles: false,
                                  // ignore: deprecated_member_use
                                  onReorder: (oldIndex, newIndex) {
                                    provider.reorderQueue(oldIndex, newIndex);
                                  },
                                  itemBuilder: (context, idx) {
                                    final qItem = provider.queue[idx];
                                    return ListTile(
                                      key: ValueKey('${qItem.id}_$idx'),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 16, vertical: 4),
                                      leading: ClipRRect(
                                        borderRadius: BorderRadius.circular(
                                            TubeTheme.thumbnailRadiusCompact),
                                        child: TubeNetworkImage(
                                          imageUrl: qItem.thumbnailUrl,
                                          width: 100,
                                          height: 56,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                      title: Text(
                                        qItem.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TubeTheme.titleMedium
                                            .copyWith(fontSize: 13),
                                      ),
                                      subtitle: Text(
                                        qItem.channelTitle,
                                        style: TubeTheme.bodySmall,
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.close,
                                                color: TubeTheme.textTertiary,
                                                size: 20),
                                            onPressed: () =>
                                                provider.removeFromQueue(idx),
                                          ),
                                          ReorderableDragStartListener(
                                            index: idx,
                                            child: const Padding(
                                              padding: EdgeInsets.symmetric(
                                                  horizontal: 4.0),
                                              child: Icon(Icons.drag_handle,
                                                  color: TubeTheme.textTertiary,
                                                  size: 20),
                                            ),
                                          ),
                                        ],
                                      ),
                                      onTap: () => provider.playVideo(qItem),
                                    );
                                  },
                                ),
                            ],

                            const SizedBox(height: 32),
                          ],
                        ),
                      ),
                  ],
                )),
      ),
    );
  }

  String _getLoadingStatusText(TubePlayerStatus status) {
    switch (status) {
      case TubePlayerStatus.loadingMetadata:
        return 'Preparing video...';
      case TubePlayerStatus.resolvingStream:
        return 'Resolving optimal stream...';
      case TubePlayerStatus.preparingPlayer:
        return 'Connecting native player...';
      case TubePlayerStatus.retrying:
        return 'Refreshing stream token...';
      default:
        return 'Loading video...';
    }
  }
}

/// YouTube-style action pill button with rounded borders and subtle icon+text
class _ActionPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ActionPill({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? TubeTheme.surfaceContainer : TubeTheme.surfaceVariant,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? TubeTheme.accent : TubeTheme.textPrimary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isSelected ? TubeTheme.accent : TubeTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
