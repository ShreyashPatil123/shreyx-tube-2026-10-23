import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/tube_models.dart';
import '../providers/tube_player_provider.dart';
import '../providers/tube_shorts_controller.dart';
import '../services/tube_channel_service.dart';
import '../services/tube_database_service.dart';
import '../services/tube_storage_service.dart';
import '../theme/tube_theme.dart';
import '../widgets/tube_image.dart';
import '../widgets/tube_skeleton.dart';
import '../widgets/tube_video_card.dart';
import 'tube_shorts_screen.dart';
import 'tube_public_playlist_screen.dart';

/// Modern YouTube-style channel screen with 5 sections:
/// Home, Videos (Latest/Popular/Oldest), Shorts (3-col grid), Live, and Playlists.
/// Accountless, privacy-first with local Following storage.
class TubeChannelScreen extends StatefulWidget {
  final String channelId;
  final String channelTitle;

  const TubeChannelScreen({
    super.key,
    required this.channelId,
    required this.channelTitle,
  });

  @override
  State<TubeChannelScreen> createState() => _TubeChannelScreenState();
}

class _TubeChannelScreenState extends State<TubeChannelScreen>
    with TickerProviderStateMixin {
  final TubeChannelService _channelService = TubeChannelService();
  final TubeStorageService _storageService = TubeStorageService();

  late TabController _tabController;
  List<String> _tabs = ['Home', 'Videos'];
  bool _loadingSection = false;
  final Map<String, String> _sectionErrors = {};
  TubeChannelInfo? _channelInfo;

  // Tab Data
  List<TubeChannelVideo> _videos = [];
  List<TubeChannelShort> _shorts = [];
  List<TubeChannelLive> _liveStreams = [];
  List<TubeChannelPlaylist> _playlists = [];

  bool _isLoading = true;
  bool _isFollowed = false;
  TubeChannelSortOrder _currentSort = TubeChannelSortOrder.latest;

  final ScrollController _videosScrollController = ScrollController();
  bool _isLoadingMoreVideos = false;
  bool _hasMoreVideos = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _isFollowed = _storageService.isChannelFollowed(widget.channelId);
    _loadAllChannelData();

    _videosScrollController.addListener(() {
      if (_videosScrollController.hasClients) {
        final maxScroll = _videosScrollController.position.maxScrollExtent;
        final currentScroll = _videosScrollController.position.pixels;
        if (currentScroll >= maxScroll - 400 &&
            !_isLoadingMoreVideos &&
            _hasMoreVideos) {
          _loadMoreVideos();
        }
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _videosScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadAllChannelData() async {
    setState(() => _isLoading = true);

    _sectionErrors.clear();
    Future<T> recover<T>(String section, Future<T> request, T fallback) async {
      try {
        return await request;
      } catch (_) {
        _sectionErrors[section] = 'Could not load this section.';
        return fallback;
      }
    }

    final results = await Future.wait([
      _channelService.getChannel(widget.channelId),
      recover(
          'Videos',
          _channelService.getChannelVideos(widget.channelId,
              sort: _currentSort),
          <TubeChannelVideo>[]),
      recover('Shorts', _channelService.getChannelShorts(widget.channelId),
          <TubeChannelShort>[]),
      recover('Live', _channelService.getChannelLiveStreams(widget.channelId),
          <TubeChannelLive>[]),
      recover(
          'Playlists',
          _channelService.getChannelPlaylists(widget.channelId),
          <TubeChannelPlaylist>[]),
    ]);
    if (!mounted) return;
    setState(() {
      _channelInfo = results[0] as TubeChannelInfo;
      final available = _channelService.availableTabs(widget.channelId);
      final tabs = ['Home', 'Videos', 'Shorts', 'Live', 'Playlists']
          .where(available.contains)
          .toList();
      if (tabs.join() != _tabs.join()) {
        _tabController.dispose();
        _tabs = tabs;
        _tabController = TabController(length: _tabs.length, vsync: this);
      }
      _videos = results[1] as List<TubeChannelVideo>;
      _shorts = results[2] as List<TubeChannelShort>;
      _liveStreams = results[3] as List<TubeChannelLive>;
      _playlists = results[4] as List<TubeChannelPlaylist>;
      _isLoading = false;
      _loadFailed = _sectionErrors.containsKey('Videos');
      _hasMoreVideos = _channelService.hasMoreVideos(widget.channelId);
      _isFollowed = _storageService.isChannelFollowed(widget.channelId);
    });
  }

  Future<void> _changeVideoSort(TubeChannelSortOrder newSort) async {
    if (newSort == _currentSort) return;
    setState(() {
      _currentSort = newSort;
      _isLoading = true;
    });

    try {
      final sorted = await _channelService.getChannelVideos(widget.channelId,
          sort: newSort);
      if (mounted) {
        setState(() {
          _videos = sorted;
          _isLoading = false;
          _hasMoreVideos = _channelService.hasMoreVideos(widget.channelId);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadFailed = true;
        });
      }
    }
  }

  Future<void> _loadMoreVideos() async {
    if (_isLoadingMoreVideos || !_hasMoreVideos) return;
    setState(() {
      _isLoadingMoreVideos = true;
      _loadFailed = false;
    });

    try {
      final more = await _channelService.loadMoreChannelVideos(widget.channelId,
          sort: _currentSort);
      if (mounted) {
        setState(() {
          _videos = more;
          _isLoadingMoreVideos = false;
          _hasMoreVideos = _channelService.hasMoreVideos(widget.channelId);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingMoreVideos = false;
          _loadFailed = true;
        });
      }
    }
  }

  Future<void> _loadMoreSection(String tab) async {
    if (_loadingSection) return;
    setState(() {
      _loadingSection = true;
      _sectionErrors.remove(tab);
    });
    final more = _channelService.hasMoreSection(widget.channelId, tab);
    try {
      if (tab == 'Shorts') {
        _shorts = await _channelService.getChannelShorts(widget.channelId,
            more: more);
      }
      if (tab == 'Live') {
        _liveStreams = await _channelService
            .getChannelLiveStreams(widget.channelId, more: more);
      }
      if (tab == 'Playlists') {
        _playlists = await _channelService.getChannelPlaylists(widget.channelId,
            more: more);
      }
    } catch (_) {
      _sectionErrors[tab] = 'Could not load this section.';
    } finally {
      if (mounted) setState(() => _loadingSection = false);
    }
  }

  Future<void> _toggleFollow() async {
    final info = _channelInfo ??
        TubeChannelInfo(
          id: widget.channelId,
          title: widget.channelTitle,
          avatarUrl: '',
        );
    final nowFollowed = await _storageService.toggleFollowChannel(info);
    await TubeDatabaseService.instance.toggleFollowChannel(
      info.id,
      info.title,
      info.avatarUrl,
    );
    if (mounted) {
      setState(() => _isFollowed = nowFollowed);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: TubeTheme.surfaceVariant,
          content:
              Text(nowFollowed ? 'Channel followed' : 'Channel unfollowed'),
        ),
      );
    }
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TubeTheme.surface,
        title: Text(_channelInfo?.title ?? widget.channelTitle,
            style: const TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_channelInfo?.description.isNotEmpty == true) ...[
                const Text('Description',
                    style: TextStyle(
                        color: TubeTheme.textSecondary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
                const SizedBox(height: 6),
                Text(_channelInfo!.description,
                    style: const TextStyle(
                        color: TubeTheme.textPrimary,
                        fontSize: 13,
                        height: 1.4)),
                const SizedBox(height: 16),
              ],
              Text('Channel ID: ${widget.channelId}',
                  style: const TextStyle(
                      color: TubeTheme.textTertiary, fontSize: 11)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Close', style: TextStyle(color: TubeTheme.accent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playerProvider = context.read<TubePlayerProvider>();
    final shortsController = context.read<TubeShortsController>();

    return Scaffold(
      backgroundColor: TubeTheme.background,
      appBar: AppBar(
        backgroundColor: TubeTheme.background,
        title: Text(widget.channelTitle,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, size: 22),
            onPressed: () => _showAboutDialog(context),
            tooltip: 'About Channel',
          ),
        ],
      ),
      body: _isLoading
          ? const TubeShimmerWrapper(child: TubeChannelHeaderSkeleton())
          : NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Banner
                      if (_channelInfo?.bannerUrl.isNotEmpty == true)
                        AspectRatio(
                          aspectRatio: 16 / 5,
                          child: TubeNetworkImage(
                            imageUrl: _channelInfo!.bannerUrl,
                            fit: BoxFit.cover,
                          ),
                        ),

                      // Header Details (YouTube modern layout)
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 36,
                                  backgroundColor: TubeTheme.surfaceVariant,
                                  backgroundImage: _channelInfo
                                              ?.avatarUrl.isNotEmpty ==
                                          true
                                      ? NetworkImage(_channelInfo!.avatarUrl)
                                      : null,
                                  child:
                                      _channelInfo?.avatarUrl.isEmpty != false
                                          ? Text(
                                              widget.channelTitle.isNotEmpty
                                                  ? widget.channelTitle[0]
                                                      .toUpperCase()
                                                  : 'C',
                                              style: const TextStyle(
                                                  fontSize: 26,
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold),
                                            )
                                          : null,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _channelInfo?.title.isNotEmpty == true
                                            ? _channelInfo!.title
                                            : widget.channelTitle,
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        _channelInfo?.handle.isNotEmpty == true
                                            ? _channelInfo!.handle
                                            : widget.channelId,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: TubeTheme.textTertiary),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        _channelInfo?.subscriberCountText
                                                    .isNotEmpty ==
                                                true
                                            ? _channelInfo!.subscriberCountText
                                            : 'Public channel',
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: TubeTheme.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),

                            // Bio Preview
                            if (_channelInfo?.description.isNotEmpty ==
                                true) ...[
                              const SizedBox(height: 10),
                              GestureDetector(
                                onTap: () => _showAboutDialog(context),
                                child: Text(
                                  _channelInfo!.description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: TubeTheme.textSecondary,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],

                            const SizedBox(height: 14),

                            // Subscribe / Follow Full-Width Pill Button
                            SizedBox(
                              width: double.infinity,
                              height: 38,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _isFollowed
                                      ? TubeTheme.surfaceVariant
                                      : Colors.white,
                                  foregroundColor:
                                      _isFollowed ? Colors.white : Colors.black,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(19)),
                                ),
                                icon: Icon(
                                  _isFollowed ? Icons.check : Icons.add,
                                  size: 18,
                                  color:
                                      _isFollowed ? Colors.white : Colors.black,
                                ),
                                label: Text(
                                  _isFollowed ? 'Following' : 'Follow',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: _isFollowed
                                        ? Colors.white
                                        : Colors.black,
                                  ),
                                ),
                                onPressed: _toggleFollow,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Tab Bar (5 Sections: Home, Videos, Shorts, Live, Playlists)
                      TabBar(
                        controller: _tabController,
                        indicatorColor: TubeTheme.textPrimary,
                        labelColor: TubeTheme.textPrimary,
                        unselectedLabelColor: TubeTheme.textTertiary,
                        labelStyle: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                        unselectedLabelStyle: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.normal),
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        tabs: _tabs.map((tab) => Tab(text: tab)).toList(),
                      ),
                      const Divider(color: TubeTheme.divider, height: 1),
                    ],
                  ),
                ),
              ],
              body: TabBarView(
                controller: _tabController,
                children: _tabs.map((tab) {
                  final content = switch (tab) {
                    'Home' => _buildHomeTab(playerProvider),
                    'Videos' => _buildVideosTab(playerProvider),
                    'Shorts' =>
                      _buildShortsTab(shortsController, playerProvider),
                    'Live' => _buildLiveTab(playerProvider),
                    _ => _buildPlaylistsTab(playerProvider),
                  };
                  if (tab == 'Home' || tab == 'Videos') return content;
                  return Column(children: [
                    Expanded(child: content),
                    if (_sectionErrors.containsKey(tab))
                      Text(_sectionErrors[tab]!),
                    if (_channelService.hasMoreSection(widget.channelId, tab) ||
                        _sectionErrors.containsKey(tab))
                      TextButton(
                          onPressed: _loadingSection
                              ? null
                              : () => _loadMoreSection(tab),
                          child: Text(_loadingSection
                              ? 'Loading…'
                              : !_sectionErrors.containsKey(tab)
                                  ? 'Load more $tab'
                                  : 'Retry $tab')),
                  ]);
                }).toList(),
              ),
            ),
    );
  }

  // =========================================================================
  // TAB BUILDERS
  // =========================================================================

  Widget _buildHomeTab(TubePlayerProvider player) {
    if (_videos.isEmpty) {
      return const Center(
          child: Text('No videos available.',
              style: TextStyle(color: TubeTheme.textTertiary)));
    }

    final featured = _videos.first.item;
    final otherUploads = _videos.skip(1).take(10).toList();

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text('Latest Upload', style: TubeTheme.sectionTitle),
        ),
        TubeVideoCard(video: featured),
        const Divider(color: TubeTheme.divider, height: 16),
        if (otherUploads.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text('Recent Videos', style: TubeTheme.sectionTitle),
          ),
          ...otherUploads
              .map((v) => TubeVideoCard(video: v.item, isCompact: true)),
        ],
      ],
    );
  }

  Widget _buildVideosTab(TubePlayerProvider player) {
    return Column(
      children: [
        if (_loadFailed)
          TextButton(
            onPressed: _videos.isEmpty ? _loadAllChannelData : _loadMoreVideos,
            child: const Text('Could not load uploads. Tap to retry.'),
          ),
        if (_hasMoreVideos && !_isLoadingMoreVideos && !_loadFailed)
          TextButton(
              onPressed: _loadMoreVideos,
              child: const Text('Load more uploads')),
        // Sorting Chip Bar (Latest, Popular, Oldest)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              _buildSortChip('Latest', TubeChannelSortOrder.latest),
              const SizedBox(width: 8),
              _buildSortChip('Popular', TubeChannelSortOrder.popular),
              const SizedBox(width: 8),
              _buildSortChip('Oldest', TubeChannelSortOrder.oldest),
            ],
          ),
        ),
        Expanded(
          child: _videos.isEmpty
              ? const Center(
                  child: Text('No videos uploaded.',
                      style: TextStyle(color: TubeTheme.textTertiary)))
              : ListView.separated(
                  controller: _videosScrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _videos.length + (_isLoadingMoreVideos ? 1 : 0),
                  separatorBuilder: (_, __) =>
                      const Divider(color: TubeTheme.divider, height: 1),
                  itemBuilder: (context, idx) {
                    if (idx >= _videos.length) {
                      return Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        alignment: Alignment.center,
                        child: const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              color: TubeTheme.accent, strokeWidth: 2),
                        ),
                      );
                    }
                    final item = _videos[idx];
                    return TubeVideoCard(video: item.item, isCompact: true);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSortChip(String label, TubeChannelSortOrder sort) {
    final isSelected = _currentSort == sort;
    return GestureDetector(
      onTap: () => _changeVideoSort(sort),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration:
            isSelected ? TubeTheme.chipSelected : TubeTheme.chipUnselected,
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : TubeTheme.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildShortsTab(
      TubeShortsController shortsCtrl, TubePlayerProvider player) {
    if (_shorts.isEmpty) {
      return const Center(
          child: Text('No Shorts uploaded by this channel.',
              style: TextStyle(color: TubeTheme.textTertiary)));
    }

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 9 / 16,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: _shorts.length,
      itemBuilder: (context, idx) {
        final s = _shorts[idx].item;
        return GestureDetector(
          onTap: () {
            // Tapping a Short navigates directly into the dedicated Shorts screen
            player.pause();
            shortsCtrl.selectChannelShorts(
                _shorts.map((s) => s.item).toList(), idx);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const TubeShortsScreen(isActive: true),
              ),
            ).then((_) => shortsCtrl.deactivateScreen());
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              fit: StackFit.expand,
              children: [
                TubeNetworkImage(imageUrl: s.thumbnailUrl, fit: BoxFit.cover),
                if (s.isMembersOnly)
                  const Positioned(
                      top: 6,
                      left: 6,
                      right: 6,
                      child: ColoredBox(
                          color: Colors.black87,
                          child: Padding(
                              padding: EdgeInsets.all(4),
                              child: Text('Members only',
                                  style: TextStyle(
                                      color: Colors.greenAccent,
                                      fontSize: 10))))),
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.transparent, Colors.black87],
                      begin: Alignment.center,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 8,
                  left: 8,
                  right: 8,
                  child: Text(
                    s.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLiveTab(TubePlayerProvider player) {
    if (_liveStreams.isEmpty) {
      return const Center(
          child: Text('No active live streams.',
              style: TextStyle(color: TubeTheme.textTertiary)));
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _liveStreams.length,
      separatorBuilder: (_, __) =>
          const Divider(color: TubeTheme.divider, height: 1),
      itemBuilder: (context, idx) =>
          TubeVideoCard(video: _liveStreams[idx].item, isCompact: true),
    );
  }

  Widget _buildPlaylistsTab(TubePlayerProvider player) {
    if (_playlists.isEmpty) {
      return const Center(
          child: Text('No public playlists found.',
              style: TextStyle(color: TubeTheme.textTertiary)));
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _playlists.length,
      separatorBuilder: (_, __) =>
          const Divider(color: TubeTheme.divider, height: 1),
      itemBuilder: (context, idx) {
        final pl = _playlists[idx];
        return ListTile(
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => TubePublicPlaylistScreen(playlist: pl))),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: ClipRRect(
            borderRadius:
                BorderRadius.circular(TubeTheme.thumbnailRadiusCompact),
            child: Stack(
              children: [
                TubeNetworkImage(
                  imageUrl: pl.thumbnailUrl,
                  width: TubeTheme.compactThumbWidth,
                  height: TubeTheme.compactThumbHeight,
                  fit: BoxFit.cover,
                ),
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${pl.videoCount} videos',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
          title: Text(
            pl.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TubeTheme.titleMedium,
          ),
          subtitle: Text(
            pl.videoCount > 0
                ? '${pl.videoCount} public videos'
                : 'Public playlist',
            style: TubeTheme.bodySmall,
          ),
          trailing:
              const Icon(Icons.playlist_play, color: TubeTheme.textTertiary),
        );
      },
    );
  }
}
