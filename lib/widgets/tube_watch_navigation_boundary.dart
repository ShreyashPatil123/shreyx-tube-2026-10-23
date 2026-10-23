import 'package:flutter/material.dart';

/// The overlay navigator has its own lifetime and must not take ownership of
/// the root app's Hero controller or Android back-handling notifications.
class TubeWatchNavigationBoundary extends StatelessWidget {
  const TubeWatchNavigationBoundary({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      NotificationListener<NavigationNotification>(
        onNotification: (_) => true,
        child: HeroControllerScope.none(child: child),
      );
}
