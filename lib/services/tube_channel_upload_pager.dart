import 'dart:async';
import '../models/tube_models.dart';

typedef TubeChannelPage = ({
  List<TubeVideoItem> items,
  String? continuationToken
});

/// An authoritative browse cursor with a lazy uploads-stream fallback. Failed
/// requests never advance the cursor or incorrectly mark the catalog complete.
class TubeChannelUploadPager {
  TubeChannelUploadPager(
      {required this.readPage, required this.fallbackUploads});

  final Future<TubeChannelPage> Function(String? token) readPage;
  final Stream<TubeVideoItem> Function() fallbackUploads;
  final Map<String, TubeVideoItem> _items = {};
  final Set<String> _consumedTokens = {};
  StreamIterator<TubeVideoItem>? _fallback;
  Future<List<TubeVideoItem>>? _pending;
  String? _token;
  bool hasMore = true;

  List<TubeVideoItem> get items => List.unmodifiable(_items.values);

  Future<List<TubeVideoItem>> loadMore() {
    if (!hasMore) return Future.value(items);
    return _pending ??= _load().whenComplete(() => _pending = null);
  }

  Future<List<TubeVideoItem>> _load() async {
    final countBefore = _items.length;
    try {
      do {
        final page = await readPage(_token);
        final next = page.continuationToken;
        if (next != null &&
            (next == _token || _consumedTokens.contains(next))) {
          throw StateError('YouTube repeated a channel continuation token');
        }
        for (final item in page.items) {
          _items[item.id] = item;
        }
        if (_token != null) _consumedTokens.add(_token!);
        _token = next;
        hasMore = next != null;
        // Catch up across duplicate pages if the fallback already loaded them.
      } while (hasMore && _items.length == countBefore);
    } catch (_) {
      _fallback ??= StreamIterator(fallbackUploads());
      try {
        var added = 0;
        while (added < 40 &&
            await _fallback!.moveNext().timeout(const Duration(seconds: 10))) {
          final item = _fallback!.current;
          if (!_items.containsKey(item.id)) {
            _items[item.id] = item;
            added++;
          }
        }
      } catch (_) {
        unawaited(_fallback!.cancel());
        _fallback = null;
      }
      if (_items.length == countBefore) rethrow;
    }
    return items;
  }
}
