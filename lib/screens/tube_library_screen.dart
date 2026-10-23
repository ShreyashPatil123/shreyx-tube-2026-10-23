// Export TubeYouScreen as TubeLibraryScreen for backwards compatibility
export 'tube_you_screen.dart';

import 'package:flutter/material.dart';
import 'tube_you_screen.dart';

/// Legacy alias for TubeYouScreen
class TubeLibraryScreen extends StatelessWidget {
  const TubeLibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const TubeYouScreen();
  }
}
