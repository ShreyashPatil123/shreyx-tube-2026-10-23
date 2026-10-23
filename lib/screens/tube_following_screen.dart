import 'package:flutter/material.dart';
import '../models/tube_models.dart';
import '../services/tube_following_service.dart';
import '../services/tube_storage_service.dart';
import '../theme/tube_theme.dart';
import '../widgets/tube_skeleton.dart';
import '../widgets/tube_video_card.dart';
import 'tube_channel_screen.dart';
import '../services/tube_session_service.dart';
import '../services/tube_innertube_client.dart';
import '../widgets/tube_account_action.dart';
import '../services/tube_youtube_account_client.dart';

/// YouTube Subscriptions screen displaying followed channel uploads.
/// Features:
/// - Horizontal avatar strip of all subscribed channels
/// - Infinite chronological feed of videos from followed channels
/// - Shimmer loading skeleton
class TubeFollowingScreen extends StatefulWidget {
  const TubeFollowingScreen({super.key});

  @override
  State<TubeFollowingScreen> createState() => _TubeFollowingScreenState();
}

class _TubeFollowingScreenState extends State<TubeFollowingScreen> {
  final TubeFollowingService _followingService = TubeFollowingService();
  final TubeStorageService _storageService = TubeStorageService();

  List<TubeChannelInfo> _followedChannels = [];
  List<TubeVideoItem> _feed = [];
  bool _isLoading = false;
  String? _error;
  int _generation = 0;
  String? _continuation;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    TubeSessionService().addListener(_reload);
    _storageService.addListener(_reload);
    _loadData();
  }

  void _reload() {
    _loadData();
  }

  @override
  void dispose() {
    TubeSessionService().removeListener(_reload);
    _storageService.removeListener(_reload);
    super.dispose();
  }

  Future<void> _loadData() async {
    final generation = ++_generation;
    final identity = TubeInnertubeClient().requestIdentity;
    setState(() {
      _isLoading = true;
      _error = null;
      _feed = [];
      _followedChannels = [];
      _continuation = null;
      _loadingMore = false;
    });
    try {
      final page = await _followingService.getChannelsPage();
      final channels = page.items;
      if (!mounted ||
          generation != _generation ||
          identity != TubeInnertubeClient().requestIdentity) {
        return;
      }
      setState(() {
        _followedChannels = channels;
        _continuation = page.continuationToken;
      });
      final privatePage = TubeSessionService().usesPrivateFeed
          ? await _followingService.getAccountFeedPage()
          : null;
      final feed = privatePage != null
          ? privatePage.items
          : channels.isEmpty
              ? <TubeVideoItem>[]
              : await _followingService.getFollowingFeed(channels: channels);
      if (!mounted ||
          generation != _generation ||
          identity != TubeInnertubeClient().requestIdentity) {
        return;
      }
      setState(() {
        _followedChannels = channels;
        _feed = feed;
        _continuation =
            privatePage?.continuationToken ?? page.continuationToken;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() {
          _isLoading = false;
          _error = e is TubeAccountApiException
              ? e.message
              : 'Subscriptions could not load. Retry or disconnect to use your local follows.';
        });
      }
    }
  }

  Future<void> _loadMore() async {
    final token = _continuation;
    if (_loadingMore || token == null) return;
    final generation = _generation;
    setState(() => _loadingMore = true);
    try {
      if (TubeSessionService().usesPrivateFeed) {
        final identity = TubeInnertubeClient().requestIdentity;
        final page =
            await _followingService.getAccountFeedPage(continuation: token);
        if (!mounted ||
            generation != _generation ||
            identity != TubeInnertubeClient().requestIdentity) {
          return;
        }
        setState(() {
          final seen = _feed.map((v) => v.id).toSet();
          _feed.addAll(page.items.where((v) => seen.add(v.id)));
          _continuation =
              page.continuationToken == token ? null : page.continuationToken;
        });
        return;
      }
      final page = await _followingService.getChannelsPage(continuation: token);
      final uploads =
          await _followingService.getFollowingFeed(channels: page.items);
      if (!mounted || generation != _generation) return;
      setState(() {
        final seen = _feed.map((v) => v.id).toSet();
        _feed.addAll(uploads.where((v) => seen.add(v.id)));
        final channelIds = _followedChannels.map((c) => c.id).toSet();
        _followedChannels.addAll(page.items.where((c) => channelIds.add(c.id)));
        _continuation =
            page.continuationToken == token ? null : page.continuationToken;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('More subscriptions could not load. Retry.')));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loadingMore = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TubeTheme.background,
      appBar: AppBar(
        backgroundColor: TubeTheme.background,
        elevation: 0,
        title: const Text('Subscriptions', style: TubeTheme.appBarTitle),
        actions: const [TubeAccountAction()],
      ),
      body: _isLoading && _followedChannels.isEmpty && _feed.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Padding(
                      padding: const EdgeInsets.all(24), child: Text(_error!)),
                  TextButton(onPressed: _loadData, child: const Text('Retry')),
                ]))
              : _followedChannels.isEmpty && _feed.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.subscriptions_outlined,
                                size: 64, color: TubeTheme.textTertiary),
                            SizedBox(height: 16),
                            Text(
                              'Don\'t miss new videos',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: TubeTheme.textPrimary),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Follow channels locally in Guest Mode, or connect YouTube using the account button to request your subscriptions.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 13,
                                  color: TubeTheme.textSecondary,
                                  height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      color: TubeTheme.progressRed,
                      backgroundColor: TubeTheme.surfaceVariant,
                      onRefresh: _loadData,
                      child: ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          // 1. Channel Avatars Horizontal Strip
                          SizedBox(
                            height: 98,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              itemCount: _followedChannels.length,
                              itemBuilder: (context, idx) {
                                final ch = _followedChannels[idx];
                                return GestureDetector(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => TubeChannelScreen(
                                            channelId: ch.id,
                                            channelTitle: ch.title),
                                      ),
                                    ).then((_) => _loadData());
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8.0),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        CircleAvatar(
                                          radius: 28,
                                          backgroundColor:
                                              TubeTheme.surfaceVariant,
                                          backgroundImage:
                                              ch.avatarUrl.isNotEmpty
                                                  ? NetworkImage(ch.avatarUrl)
                                                  : null,
                                          child: ch.avatarUrl.isEmpty
                                              ? Text(
                                                  ch.title.isNotEmpty
                                                      ? ch.title[0]
                                                          .toUpperCase()
                                                      : 'C',
                                                  style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.bold),
                                                )
                                              : null,
                                        ),
                                        const SizedBox(height: 4),
                                        SizedBox(
                                          width: 64,
                                          child: Text(
                                            ch.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: TubeTheme.textSecondary),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),

                          const Divider(color: TubeTheme.divider, height: 1),

                          // 2. Feed of Uploads
                          if (_isLoading)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: TubeShimmerWrapper(
                                child: Column(
                                  children: [
                                    TubeVideoCardSkeleton(),
                                    SizedBox(height: 16),
                                    TubeVideoCardSkeleton(),
                                  ],
                                ),
                              ),
                            )
                          else if (_feed.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(32.0),
                              child: Center(
                                child: Text(
                                  'No recent uploads found from your followed channels.',
                                  style:
                                      TextStyle(color: TubeTheme.textTertiary),
                                ),
                              ),
                            )
                          else
                            ..._feed.map((v) => TubeVideoCard(video: v)),
                          if (_continuation != null)
                            TextButton(
                                onPressed: _loadingMore ? null : _loadMore,
                                child: Text(_loadingMore
                                    ? 'Loading…'
                                    : 'Load more channels')),
                        ],
                      ),
                    ),
    );
  }
}
