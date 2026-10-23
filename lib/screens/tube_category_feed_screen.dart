import 'package:flutter/material.dart';
import '../models/tube_models.dart';
import '../services/tube_home_feed_service.dart';
import '../widgets/tube_video_card.dart';

/// Dedicated deep-browse screen for a specific category feed with infinite pagination.
class TubeCategoryFeedScreen extends StatefulWidget {
  final String category;

  const TubeCategoryFeedScreen({super.key, required this.category});

  @override
  State<TubeCategoryFeedScreen> createState() => _TubeCategoryFeedScreenState();
}

class _TubeCategoryFeedScreenState extends State<TubeCategoryFeedScreen> {
  final TubeHomeFeedService _feedService = TubeHomeFeedService();
  final ScrollController _scrollController = ScrollController();

  List<TubeVideoItem> _videos = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadInitial();

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 400) {
        _loadNextPage();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final list = await _feedService.getCategoryFeed(widget.category,
          forceRefresh: forceRefresh);
      if (mounted) {
        setState(() {
          _videos = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Could not load ${widget.category} feed. Tap retry.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadNextPage() async {
    if (_isLoadingMore || _isLoading || !_feedService.hasMore(widget.category)) {
      return;
    }
    setState(() => _isLoadingMore = true);

    try {
      final more = await _feedService.getCategoryFeedNextPage(widget.category);
      if (mounted) {
        setState(() {
          final existingIds = _videos.map((v) => v.id).toSet();
          final fresh = more.where((v) => !existingIds.contains(v.id)).toList();
          _videos.addAll(fresh);
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        elevation: 0,
        title: Text(
          widget.category,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      body: RefreshIndicator(
        color: const Color(0xFFE50914),
        backgroundColor: const Color(0xFF1E1E1E),
        onRefresh: () => _loadInitial(forceRefresh: true),
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                    color: Color(0xFFE50914), strokeWidth: 3))
            : _errorMessage != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_errorMessage!,
                            style: const TextStyle(color: Colors.white70)),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFE50914)),
                          onPressed: () => _loadInitial(forceRefresh: true),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : _videos.isEmpty
                    ? const Center(
                        child: Text('No videos found in this feed.',
                            style: TextStyle(color: Colors.white38)))
                    : ListView.separated(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _videos.length + 1,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, idx) {
                          if (idx == _videos.length) {
                            return Container(
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              alignment: Alignment.center,
                              child: _isLoadingMore
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                          color: Color(0xFFE50914),
                                          strokeWidth: 2),
                                    )
                                  : const SizedBox.shrink(),
                            );
                          }
                          return TubeVideoCard(video: _videos[idx]);
                        },
                      ),
      ),
    );
  }
}
