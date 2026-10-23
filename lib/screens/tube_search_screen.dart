import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/tube_models.dart';
import '../providers/tube_player_provider.dart';
import '../services/tube_search_service.dart';
import '../services/tube_storage_service.dart';
import '../theme/tube_theme.dart';
import '../widgets/tube_skeleton.dart';
import '../widgets/tube_video_card.dart';
import 'tube_channel_screen.dart';

class TubeSearchScreen extends StatefulWidget {
  final String? initialQuery;
  final TubeSearchService? searchService;

  const TubeSearchScreen({super.key, this.initialQuery, this.searchService});

  @override
  State<TubeSearchScreen> createState() => _TubeSearchScreenState();
}

class _TubeSearchScreenState extends State<TubeSearchScreen> {
  late final TubeSearchService _searchService;
  final TubeStorageService _storageService = TubeStorageService();
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  Timer? _debounceTimer;
  List<String> _suggestions = [];
  List<String> _recentSearches = [];
  TubeSearchResults _results = const TubeSearchResults();
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasSearched = false;
  String _activeFilter = 'All';
  TubeSearchFilters _filters = const TubeSearchFilters();
  int _searchGeneration = 0;
  String _submittedQuery = '';

  @override
  void initState() {
    super.initState();
    _searchService = widget.searchService ?? TubeSearchService();
    _controller = TextEditingController(text: widget.initialQuery ?? '');
    _recentSearches = _storageService.getSearchHistory();
    _focusNode.addListener(_onSearchFocusChanged);

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 350) {
        _loadNextPage();
      }
    });

    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      _executeSearch(widget.initialQuery!);
    } else {
      _focusNode.requestFocus();
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _focusNode.removeListener(_onSearchFocusChanged);
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String text) {
    _debounceTimer?.cancel();
    setState(() {});
    if (text.trim().isEmpty) {
      setState(() {
        _suggestions = [];
        _recentSearches = _storageService.getSearchHistory();
      });
      return;
    }

    // 250ms debounced suggestion fetch
    _debounceTimer = Timer(const Duration(milliseconds: 250), () async {
      final parsed = _searchService.parseInput(text);
      if (parsed.type == TubeInputType.textQuery) {
        final sugs = await _searchService.getSuggestions(text);
        if (mounted && _controller.text == text && _focusNode.hasFocus) {
          setState(() => _suggestions = sugs);
        }
      } else {
        if (mounted) setState(() => _suggestions = []);
      }
    });
  }

  void _onSearchFocusChanged() {
    if (!mounted) return;
    setState(() {});
    if (_focusNode.hasFocus) _onQueryChanged(_controller.text);
  }

  Future<void> _executeSearch(String input) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return;

    _focusNode.unfocus();
    _debounceTimer?.cancel();
    final parsed = _searchService.parseInput(trimmed);

    // 1. Direct Video / Shorts URL Detection
    if (parsed.type == TubeInputType.videoUrl ||
        parsed.type == TubeInputType.shortsUrl) {
      final videoId = parsed.extractedId ?? trimmed;
      final provider = context.read<TubePlayerProvider>();
      provider.resolveAndPlay(videoId);
      Navigator.pop(context);
      return;
    }

    // 2. Channel URL Detection
    if (parsed.type == TubeInputType.channelUrl) {
      final channelId = parsed.extractedId ?? trimmed;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              TubeChannelScreen(channelId: channelId, channelTitle: 'Channel'),
        ),
      );
      return;
    }

    // 3. Normal Text Query Search
    final generation = ++_searchGeneration;
    _submittedQuery = trimmed;
    setState(() {
      _isLoading = true;
      _isLoadingMore = false;
      _hasSearched = true;
      _suggestions = [];
    });

    // Save to local search history
    await _storageService.addSearchQuery(trimmed);
    if (!mounted || generation != _searchGeneration) return;
    _recentSearches = _storageService.getSearchHistory();

    final results = await _searchService.search(
      trimmed,
      filter: _activeFilter,
      filters: _filters,
      forceRefresh: true,
    );

    if (mounted && generation == _searchGeneration) {
      setState(() {
        _results = results;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadNextPage() async {
    final token = _results.continuationToken;
    if (_isLoading || _isLoadingMore || token == null || token.isEmpty) return;
    final generation = _searchGeneration;

    setState(() => _isLoadingMore = true);

    final moreResults =
        await _searchService.searchNextPage(token, filter: _activeFilter);

    if (mounted && generation == _searchGeneration) {
      final existingIds = _results.videos.map((v) => v.id).toSet();
      final newVideos =
          moreResults.videos.where((v) => !existingIds.contains(v.id)).toList();

      setState(() {
        final mergedVideos = [..._results.videos, ...newVideos];
        _results = _results.copyWith(
          videos: _filters.sortBy == 'upload_date'
              ? TubeSearchService.latestFirst(mergedVideos)
              : mergedVideos,
          channels: [..._results.channels, ...moreResults.channels],
          playlists: [..._results.playlists, ...moreResults.playlists],
          continuationToken: moreResults.continuationToken == token
              ? null
              : moreResults.continuationToken,
        );
        _isLoadingMore = false;
      });
    }
  }

  void _showFilterModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: TubeTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        String tempUpload = _filters.uploadDate;
        String tempDuration = _filters.duration;
        String tempSort = _filters.sortBy;

        return StatefulBuilder(
          builder: (context, setModalState) {
            return SingleChildScrollView(
                child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Search Filters',
                        style: TextStyle(
                            color: TubeTheme.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold),
                      ),
                      TextButton(
                        onPressed: () {
                          setModalState(() {
                            tempUpload = 'any';
                            tempDuration = 'any';
                            tempSort = 'relevance';
                          });
                        },
                        child: const Text('Reset',
                            style: TextStyle(
                                color: TubeTheme.accent, fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('Sort by',
                      style: TextStyle(
                          color: TubeTheme.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.bold)),
                  Wrap(
                    spacing: 8,
                    children: {
                      'relevance': 'Relevance',
                      'upload_date': 'Upload Date (Latest)',
                      'view_count': 'Popularity',
                    }
                        .entries
                        .map((entry) => ChoiceChip(
                              label: Text(entry.value),
                              selected: tempSort == entry.key,
                              onSelected: (selected) {
                                if (selected) {
                                  setModalState(() {
                                    tempSort = entry.key;
                                    if (tempSort == 'upload_date' &&
                                        tempUpload == 'any') {
                                      tempUpload = 'today';
                                    }
                                  });
                                }
                              },
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  if (tempSort == 'upload_date')
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                          'Latest orders results within the selected upload period. Any Time uses Today.',
                          style: TextStyle(
                              color: TubeTheme.textSecondary, fontSize: 12)),
                    ),
                  const Text('Upload Date',
                      style: TextStyle(
                          color: TubeTheme.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      {'label': 'Any Time', 'val': 'any'},
                      {'label': 'Last Hour', 'val': 'hour'},
                      {'label': 'Today', 'val': 'today'},
                      {'label': 'This Week', 'val': 'week'},
                      {'label': 'This Month', 'val': 'month'},
                      {'label': 'This Year', 'val': 'year'},
                    ].map((item) {
                      final sel = tempUpload == item['val'];
                      return ChoiceChip(
                        label: Text(item['label']!),
                        selected: sel,
                        selectedColor: TubeTheme.textPrimary,
                        backgroundColor: TubeTheme.surfaceVariant,
                        labelStyle: TextStyle(
                            color: sel
                                ? TubeTheme.background
                                : TubeTheme.textPrimary,
                            fontSize: 11),
                        side: BorderSide.none,
                        showCheckmark: false,
                        onSelected: (val) {
                          if (val) {
                            setModalState(() => tempUpload = item['val']!);
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  const Text('Duration',
                      style: TextStyle(
                          color: TubeTheme.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      {'label': 'Any', 'val': 'any'},
                      {'label': '< 3 mins', 'val': 'short'},
                      {'label': '3 - 20 mins', 'val': 'medium'},
                      {'label': '> 20 mins', 'val': 'long'},
                    ].map((item) {
                      final sel = tempDuration == item['val'];
                      return ChoiceChip(
                        label: Text(item['label']!),
                        selected: sel,
                        selectedColor: TubeTheme.textPrimary,
                        backgroundColor: TubeTheme.surfaceVariant,
                        labelStyle: TextStyle(
                            color: sel
                                ? TubeTheme.background
                                : TubeTheme.textPrimary,
                            fontSize: 11),
                        side: BorderSide.none,
                        showCheckmark: false,
                        onSelected: (val) {
                          if (val) {
                            setModalState(() => tempDuration = item['val']!);
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: TubeTheme.accent,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () {
                        setState(() {
                          _filters = TubeSearchFilters(
                            uploadDate: tempUpload,
                            duration: tempDuration,
                            sortBy: tempSort,
                          );
                        });
                        Navigator.pop(context);
                        _executeSearch(_controller.text);
                      },
                      child: const Text('Apply Filters',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ));
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TubeTheme.background,
      appBar: AppBar(
        backgroundColor: TubeTheme.background,
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: TubeTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: TextField(
          controller: _controller,
          focusNode: _focusNode,
          style: const TextStyle(color: TubeTheme.textPrimary, fontSize: 15),
          textInputAction: TextInputAction.search,
          onChanged: _onQueryChanged,
          onTap: () => _onQueryChanged(_controller.text),
          onSubmitted: _executeSearch,
          decoration: InputDecoration(
            hintText: 'Search or paste YouTube URL...',
            hintStyle:
                const TextStyle(color: TubeTheme.textTertiary, fontSize: 14),
            filled: true,
            fillColor: TubeTheme.surfaceVariant,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide.none,
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10),
            suffixIcon: _controller.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear,
                        color: TubeTheme.textSecondary, size: 20),
                    onPressed: () {
                      _controller.clear();
                      _onQueryChanged('');
                    },
                  )
                : null,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune, color: TubeTheme.textSecondary),
            tooltip: 'Filters',
            onPressed: _showFilterModal,
          ),
          IconButton(
            icon: const Icon(Icons.search, color: TubeTheme.textPrimary),
            onPressed: () => _executeSearch(_controller.text),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Chips (when search results are displayed)
          if (_hasSearched)
            Container(
              height: 44,
              color: TubeTheme.background,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                children: ['All', 'Videos', 'Shorts'].map((f) {
                  final isSelected = f == _activeFilter;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Text(f),
                      selected: isSelected,
                      selectedColor: TubeTheme.textPrimary,
                      backgroundColor: TubeTheme.surfaceVariant,
                      labelStyle: TextStyle(
                        color: isSelected
                            ? TubeTheme.background
                            : TubeTheme.textPrimary,
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w400,
                      ),
                      side: BorderSide.none,
                      showCheckmark: false,
                      onSelected: (val) {
                        if (val) {
                          setState(() => _activeFilter = f);
                          _executeSearch(_controller.text);
                        }
                      },
                    ),
                  );
                }).toList(),
              ),
            ),

          // Main Search Body
          Expanded(
            child: _focusNode.hasFocus
                ? _buildSuggestionsAndRecent()
                : _isLoading
                    ? ListView.builder(
                        itemCount: 6,
                        itemBuilder: (_, __) =>
                            const TubeSearchResultSkeleton(),
                      )
                    : _hasSearched
                        ? RefreshIndicator(
                            onRefresh: () => _executeSearch(_submittedQuery),
                            child: _buildSearchResults(),
                          )
                        : _buildSuggestionsAndRecent(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_results.videos.isEmpty && _results.channels.isEmpty && !_isLoading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          Padding(
            padding: EdgeInsets.all(24),
            child: Text('No results found for this search.',
                style: TextStyle(color: TubeTheme.textTertiary)),
          )
        ],
      );
    }

    final hasChannels = _results.channels.isNotEmpty;
    final totalCount = (hasChannels ? 1 : 0) +
        _results.videos.length +
        (_results.continuationToken != null ? 1 : 0);

    return ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: totalCount,
      itemBuilder: (context, idx) {
        // Channel match card at top if available
        if (hasChannels && idx == 0) {
          final ch = _results.channels.first;
          return _buildChannelResultCard(ch);
        }

        final videoIdx = hasChannels ? idx - 1 : idx;

        // Bottom loading spinner
        if (videoIdx == _results.videos.length) {
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 24),
            alignment: Alignment.center,
            child: _isLoadingMore
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        color: TubeTheme.accent, strokeWidth: 2),
                  )
                : const SizedBox.shrink(),
          );
        }

        // Compact Card matching YouTube Search results
        return TubeVideoCard(
          video: _results.videos[videoIdx],
          isCompact: false,
        );
      },
    );
  }

  Widget _buildChannelResultCard(TubeChannelInfo channel) {
    final isFollowed = _storageService.isChannelFollowed(channel.id);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TubeTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: TubeTheme.surfaceVariant,
            backgroundImage: channel.avatarUrl.isNotEmpty
                ? NetworkImage(channel.avatarUrl)
                : null,
            child: channel.avatarUrl.isEmpty
                ? Text(
                    channel.title.isNotEmpty
                        ? channel.title[0].toUpperCase()
                        : 'C',
                    style: const TextStyle(
                        fontSize: 20, color: TubeTheme.textPrimary))
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(channel.title,
                    style: TubeTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (channel.subscriberCountText.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(channel.subscriberCountText, style: TubeTheme.bodySmall),
                ],
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  isFollowed ? TubeTheme.surfaceVariant : TubeTheme.textPrimary,
              foregroundColor:
                  isFollowed ? TubeTheme.textPrimary : TubeTheme.background,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            onPressed: () async {
              await _storageService.toggleFollowChannel(channel);
              setState(() {});
            },
            child: Text(
              isFollowed ? 'Following' : 'Follow',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionsAndRecent() {
    if (_suggestions.isNotEmpty) {
      return ListView.builder(
        itemCount: _suggestions.length,
        itemBuilder: (context, idx) {
          final sug = _suggestions[idx];
          return ListTile(
            leading: const Icon(Icons.search,
                color: TubeTheme.textTertiary, size: 20),
            title: Text(sug,
                style: const TextStyle(
                    color: TubeTheme.textPrimary, fontSize: 14)),
            trailing: const Icon(Icons.north_west,
                color: TubeTheme.textTertiary, size: 16),
            onTap: () {
              _controller.text = sug;
              _executeSearch(sug);
            },
          );
        },
      );
    }

    if (_recentSearches.isEmpty) {
      return const Center(
        child: Text('Type any search query or paste a YouTube URL',
            style: TextStyle(color: TubeTheme.textTertiary, fontSize: 13)),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Recent Searches',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: TubeTheme.textSecondary)),
              TextButton(
                onPressed: () async {
                  await _storageService.clearSearchHistory();
                  if (mounted) setState(() => _recentSearches = []);
                },
                child: const Text('Clear All',
                    style: TextStyle(color: TubeTheme.accent, fontSize: 12)),
              ),
            ],
          ),
        ),
        // Horizontal scrollable quick-chips
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _recentSearches.take(8).length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, idx) {
              final query = _recentSearches[idx];
              return ActionChip(
                backgroundColor: TubeTheme.surfaceVariant,
                side: BorderSide.none,
                avatar: const Icon(Icons.history,
                    size: 14, color: TubeTheme.textSecondary),
                label: Text(query,
                    style: const TextStyle(
                        color: TubeTheme.textPrimary, fontSize: 12)),
                onPressed: () {
                  _controller.text = query;
                  _executeSearch(query);
                },
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        // Vertical swipe-to-delete list items
        ..._recentSearches.map((query) {
          return Dismissible(
            key: Key('recent_search_$query'),
            direction: DismissDirection.horizontal,
            background: Container(
              color: TubeTheme.accent,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 20),
              child: const Icon(Icons.delete, color: Colors.white, size: 20),
            ),
            secondaryBackground: Container(
              color: TubeTheme.accent,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              child: const Icon(Icons.delete, color: Colors.white, size: 20),
            ),
            onDismissed: (_) async {
              await _storageService.removeSearchQuery(query);
              if (mounted) {
                setState(
                    () => _recentSearches = _storageService.getSearchHistory());
              }
            },
            child: ListTile(
              leading: const Icon(Icons.history,
                  color: TubeTheme.textTertiary, size: 20),
              title: Text(query,
                  style: const TextStyle(
                      color: TubeTheme.textPrimary, fontSize: 14)),
              trailing: IconButton(
                icon: const Icon(Icons.close,
                    color: TubeTheme.textTertiary, size: 18),
                onPressed: () async {
                  await _storageService.removeSearchQuery(query);
                  if (mounted) {
                    setState(() =>
                        _recentSearches = _storageService.getSearchHistory());
                  }
                },
              ),
              onTap: () {
                _controller.text = query;
                _executeSearch(query);
              },
            ),
          );
        }),
      ],
    );
  }
}
