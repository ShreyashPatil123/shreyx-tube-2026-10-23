/// Distinguishes sustained/repeated starvation from initial load and seeking.
class TubeBufferRecovery {
  DateTime? _started, _ignoreUntil;
  bool _hasPlayed = false;
  final List<DateTime> _stalls = [];
  void reset() {
    _started = _ignoreUntil = null;
    _hasPlayed = false;
    _stalls.clear();
  }

  void playing() {
    _hasPlayed = true;
    _started = null;
  }

  void seeking(DateTime now) {
    _started = null;
    _stalls.clear();
    final deadline = now.add(const Duration(seconds: 5));
    if (_ignoreUntil == null || deadline.isAfter(_ignoreUntil!)) {
      _ignoreUntil = deadline;
    }
  }

  bool buffering(DateTime now, {required Duration ahead}) {
    if (!_hasPlayed || (_ignoreUntil != null && now.isBefore(_ignoreUntil!))) {
      return false;
    }
    if (_started == null) {
      _started = now;
      _stalls
          .removeWhere((t) => now.difference(t) > const Duration(seconds: 30));
      _stalls.add(now);
    }
    if (ahead <= const Duration(seconds: 1) &&
        (now.difference(_started!) >= const Duration(seconds: 2) ||
            _stalls.length >= 3)) {
      _started = null;
      _stalls.clear();
      _ignoreUntil = now.add(const Duration(seconds: 20));
      return true;
    }
    return false;
  }
}
