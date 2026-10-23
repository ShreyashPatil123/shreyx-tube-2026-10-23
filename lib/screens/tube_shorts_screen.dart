import '../services/tube_share_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/tube_models.dart';
import '../providers/tube_player_provider.dart';
import '../providers/tube_shorts_controller.dart';
import '../services/tube_database_service.dart';
import '../services/tube_storage_service.dart';
import '../theme/tube_theme.dart';
import '../widgets/tube_image.dart';
import '../widgets/tube_shorts_native_player_view.dart';
import 'tube_channel_screen.dart';

/// YouTube Shorts vertical feed matching the observable YouTube mobile Shorts UX.
/// Features:
/// - Fullscreen vertical PageView
/// - Single active short playback with zero background sound
/// - Single tap: play/pause with center HUD
/// - Double tap: like with animated pop-in heart
/// - Right-side action rail: Like, Dislike, Save, Share, Sound
/// - Bottom channel info: 36dp avatar, name, YouTube Subscribe pill, title, sound tag
/// - Bottom continuous red loop progress bar
class TubeShortsScreen extends StatefulWidget {
  final bool isActive;
  const TubeShortsScreen({super.key, this.isActive = false});

  @override
  State<TubeShortsScreen> createState() => _TubeShortsScreenState();
}

class _TubeShortsScreenState extends State<TubeShortsScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final TubeStorageService _storageService = TubeStorageService();
  late final PageController _pageController;

  // Center Play/Pause Ripple HUD
  bool _showRipple = false;
  bool _rippleIsPlaying = false;

  // Double-tap Like Heart Animation
  bool _showHeartAnimation = false;
  Offset _heartPosition = Offset.zero;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
        initialPage: context.read<TubeShortsController>().activeIndex);
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.isActive) {
        context.read<TubeShortsController>().activateScreen(
              mainPlayerProvider: context.read<TubePlayerProvider>(),
            );
      } else {
        context.read<TubeShortsController>().deactivateScreen();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (mounted) {
        context.read<TubeShortsController>().deactivateScreen();
      }
    } else if (state == AppLifecycleState.resumed && widget.isActive) {
      if (mounted) {
        context.read<TubeShortsController>().activateScreen(
              mainPlayerProvider: context.read<TubePlayerProvider>(),
            );
      }
    }
  }

  @override
  void didUpdateWidget(covariant TubeShortsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controller = context.read<TubeShortsController>();
    final mainPlayer = context.read<TubePlayerProvider>();

    if (!widget.isActive && oldWidget.isActive) {
      controller.deactivateScreen();
    } else if (widget.isActive && !oldWidget.isActive) {
      controller.activateScreen(mainPlayerProvider: mainPlayer);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  void _triggerPlayPauseRipple(bool isPlaying) {
    setState(() {
      _showRipple = true;
      _rippleIsPlaying = isPlaying;
    });
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _showRipple = false);
    });
  }

  void _triggerDoubleTapLike(Offset position, TubeVideoItem short) async {
    setState(() {
      _heartPosition = position;
      _showHeartAnimation = true;
    });

    if (!_storageService.isLikedLocally(short.id)) {
      await _storageService.toggleLocalLike(short);
      await TubeDatabaseService.instance.toggleLike(short.id, short.toJson());
      setState(() {});
    }

    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _showHeartAnimation = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<TubeShortsController>();
    final mainPlayer = context.read<TubePlayerProvider>();

    if (controller.isLoadingFeed) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(
              color: TubeTheme.progressRed, strokeWidth: 3),
        ),
      );
    }

    if (controller.shorts.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.video_library_outlined,
                  color: TubeTheme.textTertiary, size: 48),
              const SizedBox(height: 12),
              const Text('No Shorts available right now.',
                  style: TextStyle(color: TubeTheme.textSecondary)),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: TubeTheme.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                ),
                onPressed: () => controller.loadInitialFeed(),
                child: const Text('Refresh Shorts'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. VERTICAL PAGE VIEW
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            physics: const AlwaysScrollableScrollPhysics(
                parent: PageScrollPhysics()),
            itemCount: controller.shorts.length,
            onPageChanged: (idx) {
              controller.onPageChanged(idx, mainPlayerProvider: mainPlayer);
            },
            itemBuilder: (context, idx) {
              final short = controller.shorts[idx];
              final isActive = idx == controller.activeIndex;
              final isLiked = _storageService.isLikedLocally(short.id);
              final isSaved = _storageService.isInWatchLater(short.id);
              final isFollowed =
                  _storageService.isChannelFollowed(short.channelId);

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  controller.togglePlayPause();
                  _triggerPlayPauseRipple(controller.isPlaying);
                },
                onDoubleTapDown: (details) {
                  _triggerDoubleTapLike(details.globalPosition, short);
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Video player surface (rendered ONLY when active)
                    if (isActive)
                      const TubeShortsNativePlayerView()
                    else
                      TubeNetworkImage(
                        imageUrl: short.thumbnailUrl,
                        fit: BoxFit.cover,
                      ),

                    // Poster image while active short is preparing or buffering
                    if (isActive &&
                        (controller.isLoadingActiveShort ||
                            controller.isBuffering))
                      Stack(
                        fit: StackFit.expand,
                        children: [
                          TubeNetworkImage(
                            imageUrl: short.thumbnailUrl,
                            fit: BoxFit.cover,
                          ),
                          Container(
                            color: Colors.black26,
                            child: const Center(
                              child: CircularProgressIndicator(
                                  color: TubeTheme.progressRed, strokeWidth: 3),
                            ),
                          ),
                        ],
                      ),

                    // Top and Bottom gradient overlays for text/icon contrast
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.black45,
                            Colors.transparent,
                            Colors.transparent,
                            Colors.black87,
                          ],
                          stops: [0.0, 0.12, 0.6, 1.0],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),

                    // Error & Retry HUD if active short failed
                    if (isActive && controller.errorMessage != null)
                      Container(
                        color: Colors.black87,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline,
                                  color: TubeTheme.error, size: 42),
                              const SizedBox(height: 12),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 24.0),
                                child: Text(
                                  controller.errorMessage!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: TubeTheme.textSecondary),
                                ),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: TubeTheme.accent,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18)),
                                ),
                                icon: const Icon(Icons.refresh, size: 18),
                                label: const Text('Retry Short',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w600)),
                                onPressed: () => controller.retryActiveShort(),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Top Header Actions (Mute / Sound Toggle)
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 8,
                      right: 16,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.4),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: Icon(
                            controller.isMuted
                                ? Icons.volume_off
                                : Icons.volume_up,
                            color: Colors.white,
                            size: 20,
                          ),
                          onPressed: () => controller.toggleMute(),
                          tooltip: controller.isMuted ? 'Unmute' : 'Mute',
                        ),
                      ),
                    ),

                    // Bottom Channel & Title Info Area (YouTube Shorts style)
                    Positioned(
                      bottom: 24,
                      left: 16,
                      right: 80,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Channel Avatar + Name + Subscribe/Follow Button
                          Row(
                            children: [
                              GestureDetector(
                                onTap: () {
                                  if (short.channelId.isNotEmpty) {
                                    controller.pause();
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => TubeChannelScreen(
                                          channelId: short.channelId,
                                          channelTitle: short.channelTitle,
                                        ),
                                      ),
                                    );
                                  }
                                },
                                child: CircleAvatar(
                                  radius: 17,
                                  backgroundColor: TubeTheme.surfaceVariant,
                                  backgroundImage:
                                      short.channelAvatarUrl.isNotEmpty
                                          ? NetworkImage(short.channelAvatarUrl)
                                          : null,
                                  child: short.channelAvatarUrl.isEmpty
                                      ? Text(
                                          short.channelTitle.isNotEmpty
                                              ? short.channelTitle[0]
                                                  .toUpperCase()
                                              : 'Y',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    if (short.channelId.isNotEmpty) {
                                      controller.pause();
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => TubeChannelScreen(
                                            channelId: short.channelId,
                                            channelTitle: short.channelTitle,
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                  child: Text(
                                    short.channelTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // YouTube Shorts Subscribe/Follow Pill Button
                              GestureDetector(
                                onTap: () async {
                                  final ch = TubeChannelInfo(
                                    id: short.channelId,
                                    title: short.channelTitle,
                                    avatarUrl: short.channelAvatarUrl,
                                  );
                                  await _storageService.toggleFollowChannel(ch);
                                  await TubeDatabaseService.instance
                                      .toggleFollowChannel(
                                    short.channelId,
                                    short.channelTitle,
                                    short.channelAvatarUrl,
                                  );
                                  setState(() {});
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isFollowed
                                        ? Colors.white24
                                        : TubeTheme.accent,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Text(
                                    isFollowed ? 'Following' : 'Follow',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          // Video Title
                          Text(
                            short.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              height: 1.3,
                            ),
                          ),
                          // Audio / Sound Tag
                          if (short.soundTitle != null &&
                              short.soundTitle!.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.music_note,
                                    color: Colors.white, size: 14),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    short.soundTitle!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Right Rail Action Bar (YouTube Shorts style)
                    Positioned(
                      bottom: 24,
                      right: 12,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Like Button
                          _ShortRailButton(
                            icon: isLiked
                                ? Icons.thumb_up
                                : Icons.thumb_up_alt_outlined,
                            iconColor:
                                isLiked ? TubeTheme.progressRed : Colors.white,
                            label: isLiked ? 'Liked' : 'Like',
                            onTap: () async {
                              await _storageService.toggleLocalLike(short);
                              await TubeDatabaseService.instance
                                  .toggleLike(short.id, short.toJson());
                              setState(() {});
                            },
                          ),
                          const SizedBox(height: 18),

                          // Dislike Button
                          _ShortRailButton(
                            icon: Icons.thumb_down_alt_outlined,
                            iconColor: Colors.white,
                            label: 'Dislike',
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Marked as not interested'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 18),

                          // Save / Bookmark Button
                          _ShortRailButton(
                            icon: isSaved
                                ? Icons.bookmark
                                : Icons.bookmark_border,
                            iconColor: isSaved
                                ? const Color(0xFF00E5FF)
                                : Colors.white,
                            label: isSaved ? 'Saved' : 'Save',
                            onTap: () async {
                              await _storageService.toggleWatchLater(short);
                              await TubeDatabaseService.instance
                                  .toggleWatchLater(short.id, short.toJson());
                              setState(() {});
                            },
                          ),
                          const SizedBox(height: 18),

                          // Share Button
                          _ShortRailButton(
                            icon: Icons.share_outlined,
                            iconColor: Colors.white,
                            label: 'Share',
                            onTap: () {
                              TubeShareService.share(context, short);
                            },
                          ),
                          const SizedBox(height: 18),

                          // Sound / Audio Album Art Indicator
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Colors.white12,
                              borderRadius: BorderRadius.circular(6),
                              border:
                                  Border.all(color: Colors.white38, width: 1),
                            ),
                            child: const Icon(Icons.music_note,
                                color: Colors.white, size: 18),
                          ),
                        ],
                      ),
                    ),

                    // Bottom Linear Loop Progress Bar (YouTube red line)
                    if (isActive)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: LinearProgressIndicator(
                          value: controller.progressRatio,
                          minHeight: 2.0,
                          backgroundColor: Colors.white12,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              TubeTheme.progressRed),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),

          // 2. Play/Pause Animated Center Ripple HUD
          if (_showRipple)
            IgnorePointer(
              child: Center(
                child: AnimatedOpacity(
                  opacity: _showRipple ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24, width: 1.5),
                    ),
                    child: Icon(
                      _rippleIsPlaying ? Icons.play_arrow : Icons.pause,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                ),
              ),
            ),

          // 3. Double-Tap Animated Pop-in Heart HUD
          if (_showHeartAnimation)
            IgnorePointer(
              child: Positioned(
                left: _heartPosition.dx - 40,
                top: _heartPosition.dy - 40,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.4, end: 1.2),
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.elasticOut,
                  builder: (context, scale, child) {
                    return Transform.scale(
                      scale: scale,
                      child: child,
                    );
                  },
                  child: const Icon(
                    Icons.favorite,
                    color: TubeTheme.progressRed,
                    size: 80,
                    shadows: [
                      Shadow(color: Colors.black54, blurRadius: 12),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Right-rail button with icon and small text label
class _ShortRailButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;

  const _ShortRailButton({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: iconColor, size: 28),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
