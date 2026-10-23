import 'dart:collection';

class CacheEntry<T> {
  final T data;
  final DateTime expiresAt;

  CacheEntry(this.data, this.expiresAt);

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Lightweight, expiry-aware in-memory cache for API responses.
/// Prevents redundant network requests, limits memory footprint, and ensures fast UI transitions.
class TubeMemoryCache<T> {
  final Duration defaultTtl;
  final int maxCapacity;
  final LinkedHashMap<String, CacheEntry<T>> _store = LinkedHashMap();

  TubeMemoryCache({
    this.defaultTtl = const Duration(minutes: 10),
    this.maxCapacity = 100,
  });

  T? get(String key) {
    final entry = _store[key];
    if (entry == null) return null;

    if (entry.isExpired) {
      _store.remove(key);
      return null;
    }

    // Refresh LRU order
    _store.remove(key);
    _store[key] = entry;
    return entry.data;
  }

  void set(String key, T value, {Duration? ttl}) {
    pruneExpired();

    if (!_store.containsKey(key) && _store.length >= maxCapacity) {
      final oldestKey = _store.keys.first;
      _store.remove(oldestKey);
    }

    final effectiveTtl = ttl ?? defaultTtl;
    _store[key] = CacheEntry(value, DateTime.now().add(effectiveTtl));
  }

  void remove(String key) {
    _store.remove(key);
  }

  void clear() {
    _store.clear();
  }

  void pruneExpired() {
    final now = DateTime.now();
    _store.removeWhere((_, entry) => now.isAfter(entry.expiresAt));
  }

  int get size => _store.length;
}
