import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Embedded Android PlatformView for the dedicated Media3 Shorts player.
/// Renders with RESIZE_MODE_ZOOM to seamlessly fill 9:16 vertical viewports.
class TubeShortsNativePlayerView extends StatelessWidget {
  const TubeShortsNativePlayerView({super.key});

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return const IgnorePointer(
        child: AndroidView(
          viewType: 'com.shreyx.tube/shorts_player_view',
          layoutDirection: TextDirection.ltr,
          creationParamsCodec: StandardMessageCodec(),
        ),
      );
    }

    return Container(
      color: Colors.black,
      child: const Center(
        child: Text(
          'Shorts PlatformView is only supported on Android',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ),
    );
  }
}
