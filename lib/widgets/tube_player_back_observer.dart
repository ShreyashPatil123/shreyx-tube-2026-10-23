import 'package:flutter/material.dart';

/// Registers player back handling on the actual routes, including Search.
class TubePlayerBackObserver extends NavigatorObserver {
  TubePlayerBackObserver({required VoidCallback onPlayerBack})
      : _entry = _PlayerPopEntry(onPlayerBack);

  final _PlayerPopEntry _entry;
  final Set<ModalRoute<dynamic>> _routes = {};

  set expanded(bool value) => _entry.canPopNotifier.value = !value;

  void _register(Route<dynamic>? route) {
    if (route is ModalRoute && _routes.add(route)) {
      route.registerPopEntry(_entry);
    }
  }

  void _unregister(Route<dynamic>? route) {
    if (route is ModalRoute && _routes.remove(route)) {
      route.unregisterPopEntry(_entry);
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _register(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _unregister(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _unregister(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _unregister(oldRoute);
    _register(newRoute);
  }

  void dispose() {
    for (final route in _routes.toList()) {
      _unregister(route);
    }
    _entry.canPopNotifier.dispose();
  }
}

class _PlayerPopEntry extends PopEntry<Object?> {
  _PlayerPopEntry(this.onPlayerBack);
  final VoidCallback onPlayerBack;
  @override
  final ValueNotifier<bool> canPopNotifier = ValueNotifier(true);
  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {
    if (!didPop && !canPopNotifier.value) onPlayerBack();
  }
}
