import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Embedded AndroidX Media3 PlayerView rendered directly into Flutter via PlatformView.
class TubeNativePlayerView extends StatelessWidget {
  const TubeNativePlayerView({super.key});

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const Center(
        child: Text(
          'Media3 PlayerView is only supported on Android.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return const AndroidView(
      viewType: 'com.shreyx.tube/player_view',
      creationParamsCodec: StandardMessageCodec(),
    );
  }
}
