import '../widgets/tube_shorts_shelf.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/tube_models.dart';
import '../providers/tube_player_provider.dart';
import '../services/tube_home_feed_service.dart';
import '../services/tube_shorts_service.dart';
import '../services/tube_storage_service.dart';
import '../theme/tube_theme.dart';
import '../widgets/tube_image.dart';
import '../widgets/tube_skeleton.dart';
import '../widgets/tube_video_card.dart';
import 'tube_category_feed_screen.dart';
import 'tube_privacy_settings_screen.dart';
import 'tube_search_screen.dart';
import '../services/tube_session_service.dart';
import '../services/tube_innertube_client.dart';
import '../widgets/tube_account_action.dart';

class TubeHomeScreen extends StatefulWidget {
  const TubeHomeScreen({super.key, this.feedService, this.shortsService});
  final TubeHomeFeedService? feedService;
  final TubeShortsService? shortsService;

  @override
  State<TubeHomeScreen> createState() => _TubeHomeScreenState();
}

class _TubeHomeScreenState extends State<TubeHomeScreen>
    with AutomaticKeepAliveClientMixin {
  late final TubeHomeFeedService _feedService =
      widget.feedService ?? TubeHomeFeedService();
  late final TubeShortsService _shortsService =
      widget.shortsService ?? TubeShortsService();
  final TubeStorageService _storageService = TubeStorageService();
  final ScrollController _scrollController = ScrollController();

  static const _categories = [
    'Recommended',
    'Trending',
    'Music',
    'Gaming',
    'Technology',
    'Education',
    'News',
    'Sports',
    'Live',
  ];

  String _selectedCategory = 'Recommended';
  List<TubeVideoItem> _feed = [];
  List<TubeVideoItem> _homeShorts = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isLoadingMore = false;
  String? _errorMessage;
  int _feedGeneration = 0;
  String? _shortsIdentity;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _storageService.addListener(_privacyChanged);
    TubeSessionService().addListener(_accountChanged);
    // Non-negotiable requirement: Always generate fresh feed on cold app launch
    _loadFeed(_selectedCategory, forceRefresh: true);
    _loadShortsShelf();

    _scrollController.addListener(() {
      if (_scrollController.hasClients) {
        final maxScroll = _scrollController.position.maxScrollExtent;
        final currentScroll = _scrollController.position.pixels;
        if (currentScroll >= maxScroll - 800 &&
            !_isLoadingMore &&
            !_isLoading &&
            _feed.isNotEmpty) {
          _loadNextPage();
        }
      }
    });
  }

  void _accountChanged() {
    _privacyChanged();
  }

  void _privacyChanged() {
    if (_shortsIdentity != TubeInnertubeClient().requestIdentity) {
      _homeShorts = [];
      _loadShortsShelf();
    }
    _feed = [];
    _loadFeed(_selectedCategory, forceRefresh: true);
  }

  @override
  void dispose() {
    _storageService.removeListener(_privacyChanged);
    TubeSessionService().removeListener(_accountChanged);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadShortsShelf() async {
    final identity = TubeInnertubeClient().requestIdentity;
    _shortsIdentity = identity;
    try {
      final list = await _shortsService.getShortsFeed(page: 0);
      if (mounted && identity == TubeInnertubeClient().requestIdentity) {
        setState(() {
          _homeShorts = list.take(8).toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _loadFeed(String category, {bool forceRefresh = false}) async {
    final generation = ++_feedGeneration;
    _isLoadingMore = false;
    if (forceRefresh && _feed.isNotEmpty) {
      setState(() {
        _isRefreshing = true;
        _errorMessage = null;
      });
    } else {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final list = await _feedService.getCategoryFeed(
        category,
        forceRefresh: forceRefresh,
      );
      if (mounted && generation == _feedGeneration) {
        setState(() {
          _feed = list;
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    } catch (e) {
      if (mounted && generation == _feedGeneration) {
        setState(() {
          _errorMessage =
              'Could not load $category feed. Check your connection and retry.';
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  Future<void> _loadNextPage() async {
    if (_isLoadingMore ||
        _isLoading ||
        _isRefreshing ||
        _feed.isEmpty ||
        !_feedService.hasMore(_selectedCategory)) {
      return;
    }
    final generation = _feedGeneration;
    setState(() => _isLoadingMore = true);

    try {
      final more = await _feedService.getCategoryFeedNextPage(
        _selectedCategory,
      );
      if (mounted && generation == _feedGeneration) {
        setState(() {
          final existingIds = _feed.map((v) => v.id).toSet();
          final fresh = more.where((v) => !existingIds.contains(v.id)).toList();
          _feed.addAll(fresh);
          _isLoadingMore = false;
        });
      }
    } catch (_) {
      if (mounted && generation == _feedGeneration) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  void scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isIncognito = _storageService.isIncognito;
    final resumeItems = _storageService.getResumeItems().take(10).toList();

    return Scaffold(
      backgroundColor: TubeTheme.background,
      appBar: AppBar(
        titleSpacing: 16,
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: TubeTheme.accent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'SHREYX',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'TUBE',
                style: TextStyle(
                  fontWeight: FontWeight.w300,
                  letterSpacing: 1.5,
                  fontSize: 16,
                ),
              ),
              if (isIncognito) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.amberAccent, width: 0.8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.visibility_off,
                        size: 11,
                        color: Colors.amberAccent,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Incognito',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.amberAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          const TubeAccountAction(),
          IconButton(
            icon: const Icon(Icons.search, color: TubeTheme.textPrimary),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TubeSearchScreen()),
              );
            },
            tooltip: 'Search',
          ),
          IconButton(
            icon: const Icon(
              Icons.shield_outlined,
              color: TubeTheme.textSecondary,
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const TubePrivacySettingsScreen(),
                ),
              ).then((_) {
                if (mounted) setState(() {});
              });
            },
            tooltip: 'Privacy Settings',
          ),
        ],
      ),
      body: Column(
        children: [
          if (TubeSessionService().notice != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(TubeSessionService().notice!),
            ),
          // 1. YouTube-style Category Filter Chips Strip
          Container(
            height: TubeTheme.chipRowHeight,
            color: TubeTheme.background,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: _categories.length + 1,
              itemBuilder: (context, idx) {
                if (idx == _categories.length) {
                  return Padding(
                    padding: const EdgeInsets.only(left: 4.0),
                    child: ActionChip(
                      label: const Text(
                        'Explore',
                        style: TextStyle(
                          fontSize: 12,
                          color: TubeTheme.textPrimary,
                        ),
                      ),
                      backgroundColor: TubeTheme.surfaceVariant,
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TubeCategoryFeedScreen(
                              category: _selectedCategory,
                            ),
                          ),
                        );
                      },
                    ),
                  );
                }

                final cat = _categories[idx];
                final isSelected = cat == _selectedCategory;

                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip(
                    label: Text(cat == 'Recommended' ? 'All' : cat),
                    selected: isSelected,
                    selectedColor: TubeTheme.textPrimary,
                    backgroundColor: TubeTheme.surfaceVariant,
                    labelStyle: TextStyle(
                      color: isSelected
                          ? TubeTheme.background
                          : TubeTheme.textPrimary,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                      fontSize: 13,
                    ),
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    showCheckmark: false,
                    onSelected: (val) {
                      if (val) {
                        setState(() => _selectedCategory = cat);
                        _loadFeed(cat);
                      }
                    },
                  ),
                );
              },
            ),
          ),

          if (_isRefreshing)
            const LinearProgressIndicator(
              minHeight: 2.5,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(TubeTheme.accent),
            ),

          // 2. Feed Body with YouTube Shimmer Loading & Pull-to-Refresh
          Expanded(
            child: RefreshIndicator(
              color: TubeTheme.accent,
              backgroundColor: TubeTheme.surfaceVariant,
              onRefresh: () async {
                await _loadFeed(_selectedCategory, forceRefresh: true);
                _loadShortsShelf();
              },
              child: _isLoading
                  ? const TubeHomeFeedSkeleton()
                  : _errorMessage != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.wifi_off,
                                  size: 48,
                                  color: TubeTheme.textTertiary,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _errorMessage!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: TubeTheme.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: TubeTheme.accent,
                                  ),
                                  onPressed: () => _loadFeed(
                                    _selectedCategory,
                                    forceRefresh: true,
                                  ),
                                  child: const Text(
                                    'Retry',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _feed.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.check_circle_outline,
                                        size: 40),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'No fresh recommendations available.',
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'Recently served and consumed videos are excluded. Try a category, search, or refresh later.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: TubeTheme.textTertiary),
                                    ),
                                    TextButton(
                                      onPressed: () => _loadFeed(
                                        _selectedCategory,
                                        forceRefresh: true,
                                      ),
                                      child: const Text('Try again'),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.builder(
                              controller: _scrollController,
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.only(bottom: 24),
                              itemCount: _feed.length +
                                  (resumeItems.isNotEmpty ? 1 : 0) +
                                  (_homeShorts.isNotEmpty ? 1 : 0) +
                                  1,
                              itemBuilder: (context, idx) {
                                int offset = 0;

                                // Slot 0: Continue Watching Shelf
                                if (resumeItems.isNotEmpty) {
                                  if (idx == 0) {
                                    return _buildContinueWatchingShelf(
                                        resumeItems);
                                  }
                                  offset++;
                                }

                                // Slot 3 or 4: Shorts Shelf
                                final adjustedIdx = idx - offset;
                                if (_homeShorts.isNotEmpty &&
                                    adjustedIdx == 3) {
                                  return _buildShortsShelf();
                                }
                                final videoIdx =
                                    _homeShorts.isNotEmpty && adjustedIdx > 3
                                        ? adjustedIdx - 1
                                        : adjustedIdx;

                                // Bottom pagination spinner
                                if (videoIdx >= _feed.length) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 24),
                                    alignment: Alignment.center,
                                    child: _isLoadingMore
                                        ? const SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CircularProgressIndicator(
                                              color: TubeTheme.accent,
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const SizedBox.shrink(),
                                  );
                                }

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: TubeVideoCard(video: _feed[videoIdx]),
                                );
                              },
                            ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContinueWatchingShelf(List<TubeHistoryItem> resumeItems) {
    return Container(
      color: TubeTheme.surface,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.history, color: TubeTheme.accent, size: 18),
                SizedBox(width: 8),
                Text(
                  'Continue Watching',
                  style: TextStyle(
                    color: TubeTheme.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 168,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: resumeItems.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, idx) {
                final item = resumeItems[idx];
                return GestureDetector(
                  onTap: () {
                    final player = context.read<TubePlayerProvider>();
                    player.playVideo(
                      item.video,
                      startPositionMs: item.positionMs,
                    );
                  },
                  child: SizedBox(
                    width: 170,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: AspectRatio(
                                aspectRatio: 16 / 9,
                                child: TubeNetworkImage(
                                  imageUrl: item.video.thumbnailUrl,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 6,
                              right: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.8),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  item.formattedResumePosition,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: ClipRRect(
                                borderRadius: const BorderRadius.vertical(
                                  bottom: Radius.circular(8),
                                ),
                                child: LinearProgressIndicator(
                                  value: item.progressRatio,
                                  backgroundColor: Colors.white24,
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                    TubeTheme.progressRed,
                                  ),
                                  minHeight: 3,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item.video.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: TubeTheme.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.video.channelTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: TubeTheme.textSecondary,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShortsShelf() => TubeShortsShelf(
      items: _homeShorts,
      onOpen: (short) => context.read<TubePlayerProvider>().playVideo(short));
}
