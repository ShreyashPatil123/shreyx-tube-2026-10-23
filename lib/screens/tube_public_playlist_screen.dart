import 'package:flutter/material.dart';
import '../models/tube_models.dart';
import '../services/tube_playlist_service.dart';
import '../widgets/tube_video_card.dart';

class TubePublicPlaylistScreen extends StatefulWidget {
  final TubeChannelPlaylist playlist;
  const TubePublicPlaylistScreen({super.key, required this.playlist});
  @override
  State<TubePublicPlaylistScreen> createState() =>
      _TubePublicPlaylistScreenState();
}

class _TubePublicPlaylistScreenState extends State<TubePublicPlaylistScreen> {
  final List<TubeVideoItem> _items = [];
  bool _loading = false, _more = true;
  int _offset = 0;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await TubePlaylistService()
          .getPlaylistVideos(widget.playlist.id, offset: _offset, limit: 40);
      if (!mounted) return;
      final ids = _items.map((v) => v.id).toSet();
      setState(() {
        _offset += page.length;
        _items.addAll(page.where((v) => ids.add(v.id)));
        _more = page.length == 40;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load playlist.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(widget.playlist.title)),
      body: ListView(children: [
        ..._items.map((v) => TubeVideoCard(video: v)),
        if (_items.isEmpty && !_loading && _error == null)
          const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No publicly available videos.')),
        if (_error != null) Text(_error!),
        if (_more || _error != null)
          TextButton(
              onPressed: _loading ? null : _load,
              child: Text(_loading ? 'Loading…' : 'Load more / retry')),
      ]));
}
