import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/tube_player_provider.dart';
import '../providers/tube_shorts_controller.dart';
import '../theme/tube_theme.dart';
import 'tube_following_screen.dart';
import 'tube_home_screen.dart';
import 'tube_shorts_screen.dart';
import 'tube_you_screen.dart';

/// Global root application shell hosting the primary navigation tabs and docked persistent mini-player.
/// Persistent playback across all screens:
/// Tab 0: Home
/// Tab 1: Shorts
/// Tab 2: Subscriptions
/// Tab 3: You
class TubeMainShell extends StatefulWidget {
  const TubeMainShell({super.key});

  @override
  State<TubeMainShell> createState() => _TubeMainShellState();
}

class _TubeMainShellState extends State<TubeMainShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    context.select<TubePlayerProvider, (bool, bool)>(
        (p) => (p.isPlayerVisible, p.isExpanded));
    final provider = context.read<TubePlayerProvider>();

    final pages = [
      const TubeHomeScreen(),
      TubeShortsScreen(isActive: _currentIndex == 1),
      const TubeFollowingScreen(),
      const TubeYouScreen(),
    ];

    return Scaffold(
      backgroundColor: TubeTheme.background,
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      // Bottom navigation; the floating player is rendered above all routes by the app.
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          NavigationBarTheme(
            data: NavigationBarThemeData(
              backgroundColor: TubeTheme.background,
              indicatorColor: Colors.transparent,
              height: TubeTheme.bottomNavHeight,
              labelTextStyle: WidgetStateProperty.resolveWith((states) {
                final isSelected = states.contains(WidgetState.selected);
                return TextStyle(
                  color: isSelected
                      ? TubeTheme.textPrimary
                      : TubeTheme.textTertiary,
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                );
              }),
              iconTheme: WidgetStateProperty.resolveWith((states) {
                final isSelected = states.contains(WidgetState.selected);
                return IconThemeData(
                  color: isSelected
                      ? TubeTheme.textPrimary
                      : TubeTheme.textTertiary,
                  size: 24,
                );
              }),
            ),
            child: NavigationBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: (idx) {
                if (_currentIndex == 1 && idx != 1) {
                  // Switching away from Shorts: stop shorts playback immediately
                  context.read<TubeShortsController>().deactivateScreen();
                } else if (idx == 1 && _currentIndex != 1) {
                  // Switching into Shorts: activate shorts, pause normal video playback
                  context
                      .read<TubeShortsController>()
                      .activateScreen(mainPlayerProvider: provider);
                }
                setState(() => _currentIndex = idx);
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.play_circle_outline),
                  selectedIcon: Icon(Icons.play_circle_filled),
                  label: 'Shorts',
                ),
                NavigationDestination(
                  icon: Icon(Icons.subscriptions_outlined),
                  selectedIcon: Icon(Icons.subscriptions),
                  label: 'Subscriptions',
                ),
                NavigationDestination(
                  icon: Icon(Icons.account_circle_outlined),
                  selectedIcon: Icon(Icons.account_circle),
                  label: 'You',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
