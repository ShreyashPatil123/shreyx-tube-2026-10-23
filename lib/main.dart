import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'providers/tube_player_provider.dart';
import 'providers/tube_shorts_controller.dart';
import 'screens/tube_main_shell.dart';
import 'screens/tube_watch_screen.dart';
import 'services/tube_database_service.dart';
import 'services/tube_download_service.dart';
import 'services/tube_storage_service.dart';
import 'services/tube_user_profile_service.dart';
import 'theme/tube_theme.dart';
import 'widgets/tube_player_back_observer.dart';
import 'widgets/tube_watch_navigation_boundary.dart';
import 'widgets/tube_mini_player.dart';
import 'widgets/tube_link_handler.dart';
import 'widgets/tube_native_player_view.dart';
import 'screens/tube_onboarding_screen.dart';
import 'services/tube_local_reset_service.dart';
import 'services/tube_session_service.dart';
import 'services/tube_channel_service.dart';
import 'services/tube_playlist_service.dart';
import 'services/tube_search_service.dart';
import 'services/tube_home_feed_service.dart';
import 'services/tube_shorts_service.dart';
import 'services/tube_device_setup_service.dart';
import 'screens/tube_device_setup_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSize = 120;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 96 * 1024 * 1024;

  // Configure edge-to-edge transparent system UI
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.black,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TubeShortsController()),
        ChangeNotifierProvider(
          create: (context) => TubePlayerProvider(
            onNormalPlayback:
                context.read<TubeShortsController>().deactivateScreen,
          ),
        ),
      ],
      child: const TubeStartupGate(),
    ),
  );
}

class TubeStartupGate extends StatefulWidget {
  const TubeStartupGate({super.key});
  @override
  State<TubeStartupGate> createState() => _TubeStartupGateState();
}

class _TubeStartupGateState extends State<TubeStartupGate> {
  late Future<void> _startup = _initialize();
  @override
  void initState() {
    super.initState();
    TubeSessionService().addListener(_accountChanged);
  }

  void _accountChanged() {
    TubeHomeFeedService().reset();
    TubeShortsService().reset();
    TubeChannelService().clearCache();
    TubePlaylistService().clearCache();
    TubeSearchService().clearCache();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }

  @override
  void dispose() {
    TubeSessionService().removeListener(_accountChanged);
    super.dispose();
  }

  Future<void> _initialize() async {
    await TubeDatabaseService().init();
    await TubeStorageService().init();
    await TubeDownloadService().init();
    if (await TubeDatabaseService().getSetting('reset_pending') == 'true') {
      await TubeLocalResetService.clearStores();
    }
    // Optional account restoration must not block Guest startup.
    unawaited(TubeSessionService().init());
    await TubeUserProfileService().init();
    await TubeUserProfileService().loadIdentity();
    await TubeDeviceSetupService().init();
    if (mounted) {
      await context.read<TubePlayerProvider>().restoreNativePlayback();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
        future: _startup,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done &&
              !snapshot.hasError) {
            return const ShreyXTubeApp();
          }
          return MaterialApp(
            theme: TubeTheme.buildThemeData(),
            home: Scaffold(
              body: Center(
                child: snapshot.hasError
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Could not open local storage. Your data has been preserved.',
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () =>
                                setState(() => _startup = _initialize()),
                            child: const Text('Retry'),
                          ),
                        ],
                      )
                    : const CircularProgressIndicator(),
              ),
            ),
          );
        },
      );
}

class ShreyXTubeApp extends StatefulWidget {
  const ShreyXTubeApp({super.key});

  @override
  State<ShreyXTubeApp> createState() => _ShreyXTubeAppState();
}

class _ShreyXTubeAppState extends State<ShreyXTubeApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey<NavigatorState> _watchNavigatorKey =
      GlobalKey<NavigatorState>();
  late final TubePlayerBackObserver _backObserver;
  final GlobalKey _surfaceKey = GlobalKey(debugLabel: 'shared-media3-surface');

  @override
  void initState() {
    super.initState();
    _backObserver = TubePlayerBackObserver(
      onPlayerBack: () {
        if (_watchNavigatorKey.currentState?.canPop() ?? false) {
          _watchNavigatorKey.currentState?.pop();
          return;
        }
        final player = context.read<TubePlayerProvider>();
        if (player.isFullscreen) {
          player.toggleFullscreen();
        } else {
          player.collapsePlayer();
        }
      },
    );
  }

  @override
  void dispose() {
    _backObserver.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(
          [TubeUserProfileService(), TubeDeviceSetupService()]),
      builder: (context, _) => MaterialApp(
        title: 'ShreyX Tube',
        navigatorKey: _navigatorKey,
        debugShowCheckedModeBanner: false,
        navigatorObservers: [_backObserver],
        theme: TubeTheme.buildThemeData(),
        builder: (context, child) {
          return TubeLinkHandler(
            navigatorKey: _navigatorKey,
            child: Selector<TubePlayerProvider, (bool, bool, bool)>(
              selector: (_, p) => (p.isPlayerVisible, p.isExpanded, p.isInPip),
              builder: (context, visibility, _) {
                final shortsActive = context.select<TubeShortsController, bool>(
                  (s) => s.isScreenActive,
                );
                final provider = context.read<TubePlayerProvider>();
                _backObserver.expanded =
                    provider.isExpanded && !provider.isInPip;
                final surface = TubeNativePlayerView(key: _surfaceKey);
                return Overlay.wrap(
                  child: Stack(
                    children: [
                      child ?? const SizedBox(),
                      // Animated Sliding Full Watch Page Overlay
                      if (!TubeDeviceSetupService().pending &&
                          provider.isPlayerVisible &&
                          !provider.isInPip)
                        Positioned.fill(
                          child: AnimatedSlide(
                            offset: provider.isExpanded
                                ? Offset.zero
                                : const Offset(0, 1),
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOutCubic,
                            child: provider.isExpanded
                                ? TubeWatchNavigationBoundary(
                                    child: Navigator(
                                      key: _watchNavigatorKey,
                                      onGenerateRoute: (settings) =>
                                          MaterialPageRoute(
                                        builder: (watchContext) =>
                                            TubeWatchScreen(
                                          onCollapse: () =>
                                              provider.collapsePlayer(),
                                          videoSurface: surface,
                                        ),
                                      ),
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ),
                      if (!TubeDeviceSetupService().pending &&
                          provider.isPlayerVisible &&
                          !provider.isExpanded &&
                          !provider.isInPip &&
                          !shortsActive)
                        Positioned.fill(
                          child: TubeFloatingMiniPlayer(
                            onExpand: provider.expandPlayer,
                            videoSurface: surface,
                          ),
                        ),
                      if (provider.isInPip)
                        Positioned.fill(
                          child: ColoredBox(
                            color: Colors.black,
                            child: surface,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          );
        },
        home: TubeDeviceSetupService().pending
            ? const TubeDeviceSetupScreen(initialSetup: true)
            : TubeUserProfileService().onboardingCompleted
                ? const TubeMainShell()
                : const TubeOnboardingScreen(),
      ),
    );
  }
}
