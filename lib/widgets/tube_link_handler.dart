import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/tube_models.dart';
import '../providers/tube_player_provider.dart';
import '../providers/tube_shorts_controller.dart';
import '../screens/tube_shorts_screen.dart';
import '../services/tube_link_service.dart';
import '../services/tube_youtube_link.dart';
import '../services/tube_user_profile_service.dart';
import '../services/tube_device_setup_service.dart';

class TubeLinkHandler extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;
  const TubeLinkHandler(
      {super.key, required this.navigatorKey, required this.child});
  @override
  State<TubeLinkHandler> createState() => _TubeLinkHandlerState();
}

class _TubeLinkHandlerState extends State<TubeLinkHandler>
    with WidgetsBindingObserver {
  bool _busy = false, _again = false, _attached = false;
  TubeYoutubeLink? _active;
  String? _lastFailure;
  late TubePlayerProvider _player;
  late TubeShortsController _shorts;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    TubeUserProfileService().addListener(_schedule);
    TubeDeviceSetupService().addListener(_schedule);
    TubeLinkService.channel.setMethodCallHandler((call) async {
      if (call.method == 'incoming') _schedule();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _player = context.read<TubePlayerProvider>();
      _shorts = context.read<TubeShortsController>();
      _player.addListener(_failure);
      _shorts.addListener(_failure);
      _attached = true;
      _schedule();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _schedule();
  }

  void _schedule() {
    if (!mounted) return;
    if (!TubeUserProfileService().onboardingCompleted) {
      _active = null;
      _lastFailure = null;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_drain());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _drain() async {
    if (_busy) {
      _again = true;
      return;
    }
    if (!_attached ||
        TubeDeviceSetupService().pending ||
        !TubeUserProfileService().onboardingCompleted ||
        widget.navigatorKey.currentContext == null) {
      return;
    }
    _busy = true;
    try {
      do {
        _again = false;
        final entries = await TubeLinkService.pending();
        for (final entry in entries) {
          if (!mounted) return;
          final id = entry['id']?.toString() ?? '';
          final link = TubeYoutubeLink.parse(entry['url']?.toString() ?? '');
          if (link == null) {
            _notice('This is not a supported YouTube video link.');
            await TubeLinkService.acknowledge(id);
            continue;
          }
          if (_player.isPlayerVisible) _player.collapsePlayer();
          final navContext = widget.navigatorKey.currentContext!;
          if (!navContext.mounted) return;
          final choice = await showDialog<bool>(
              context: navContext,
              builder: (context) => AlertDialog(
                      title: const Text('Open YouTube video'),
                      content: const Text(
                          'Choose where you would like to watch this video.'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Open in YouTube')),
                        FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Play in ShreyX Tube')),
                      ]));
          if (!mounted) return;
          await TubeLinkService.acknowledge(id);
          if (choice == false) {
            await _open(link.originalUrl);
          }
          if (choice == true) _play(link);
        }
      } while (_again && mounted);
    } on PlatformException {
      _notice('Could not receive the link. Please try opening it again.');
    } finally {
      _busy = false;
    }
  }

  void _play(TubeYoutubeLink link) {
    _active = link;
    TubeLinkService.remember(link.videoId, link.originalUrl);
    _lastFailure = null;
    widget.navigatorKey.currentState!.popUntil((r) => r.isFirst);
    final video = TubeVideoItem(
        id: link.videoId,
        title: 'YouTube video',
        channelTitle: '',
        channelId: '',
        thumbnailUrl: 'https://i.ytimg.com/vi/${link.videoId}/hqdefault.jpg',
        isShort: link.kind == TubeLinkKind.shorts);
    if (link.kind == TubeLinkKind.shorts) {
      _player.pause();
      _player.collapsePlayer();
      _shorts.selectChannelShorts([video], 0,
          startPositionMs: (link.startSeconds ?? 0) * 1000);
      widget.navigatorKey.currentState!
          .push(MaterialPageRoute(
              builder: (_) => const TubeShortsScreen(isActive: true)))
          .then((_) => _shorts.deactivateScreen());
    } else {
      unawaited(_player.playVideo(video,
          startPositionMs:
              link.startSeconds == null ? null : link.startSeconds! * 1000));
    }
  }

  void _failure() {
    final link = _active;
    if (link == null) return;
    final error = link.kind == TubeLinkKind.shorts
        ? (_shorts.activeShort?.id == link.videoId
            ? _shorts.errorMessage
            : null)
        : (_player.currentVideoItem?.id == link.videoId
            ? _player.errorMessage
            : null);
    if (error == null || error == _lastFailure) return;
    _lastFailure = error;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _active != link) return;
      final messenger =
          ScaffoldMessenger.maybeOf(widget.navigatorKey.currentContext!);
      messenger?.showSnackBar(SnackBar(
          content: Text(error),
          duration: const Duration(seconds: 12),
          action: SnackBarAction(
              label: 'Open in YouTube',
              onPressed: () => _open(link.originalUrl))));
    });
  }

  Future<void> _open(String url) async {
    if (!await TubeLinkService.openYouTube(url)) {
      _notice('No YouTube app or browser is available to open this link.');
    }
  }

  void _notice(String text) {
    if (!mounted) return;
    final context = widget.navigatorKey.currentContext;
    if (context != null) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(text)));
    }
  }

  @override
  void dispose() {
    TubeDeviceSetupService().removeListener(_schedule);
    WidgetsBinding.instance.removeObserver(this);
    TubeUserProfileService().removeListener(_schedule);
    TubeLinkService.channel.setMethodCallHandler(null);
    if (_attached) {
      _player.removeListener(_failure);
      _shorts.removeListener(_failure);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
