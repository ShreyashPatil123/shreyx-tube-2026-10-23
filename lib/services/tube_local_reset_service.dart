import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import '../providers/tube_player_provider.dart';
import '../providers/tube_shorts_controller.dart';
import 'tube_database_service.dart';
import 'tube_storage_service.dart';
import 'tube_download_service.dart';
import 'tube_user_profile_service.dart';
import 'tube_home_feed_service.dart';
import 'tube_recommendation_engine.dart';
import 'tube_stream_resolver.dart';
import 'tube_shorts_service.dart';
import 'tube_channel_service.dart';
import 'tube_search_service.dart';
import 'tube_playlist_service.dart';
import 'tube_link_service.dart';
import 'tube_session_service.dart';
import 'tube_device_setup_service.dart';
import 'tube_intelligence_store.dart';

const tubeResetMessage =
    'This will permanently delete all data stored locally by ShreyX Tube on this device, including any connected YouTube session, your profile, onboarding preferences, watch and search history, recommendation signals, feed impressions, followed channels, playlists, saved videos, saved AI responses, study notes and settings. Your personalized feed will be reset, and previously consumed videos will no longer be excluded based on the deleted history. This action cannot be undone.';

class TubeLocalResetService {
  static bool _running = false;
  static Future<void> reset(
      TubePlayerProvider player, TubeShortsController shorts) async {
    if (_running) throw StateError('A reset is already in progress');
    _running = true;
    try {
      await player.resetLocalState();
      await shorts.resetLocalState();
      await player.flushSignals();
      TubeHomeFeedService().reset();
      TubeShortsService().reset();
      // Durable marker makes an interrupted multi-store reset retryable on startup.
      await TubeDatabaseService().setSetting('reset_pending', 'true');
      await clearStores();
    } finally {
      _running = false;
    }
  }

  static Future<void> clearStores() async {
    await TubeIntelligenceStore().reset();
    await TubeSessionService().clearSession();
    await TubeDownloadService().clearAllDownloads();
    await DefaultCacheManager().emptyCache();
    await TubeStorageService().clearAllLocalData();
    await TubeDatabaseService().clearAllData();
    TubeHomeFeedService().reset();
    TubeShortsService().reset();
    TubeStreamResolver().clearCache();
    TubeChannelService().clearCache();
    TubeRecommendationEngine().reset();
    TubeSearchService().clearCache();
    TubePlaylistService().clearCache();
    TubeLinkService.clear();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    TubeUserProfileService().reset();
    TubeDeviceSetupService().reset();
  }
}
