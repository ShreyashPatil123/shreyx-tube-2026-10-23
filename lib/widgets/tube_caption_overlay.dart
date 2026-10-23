import 'package:flutter/material.dart';

/// Clean high-contrast subtitle overlay widget for the video player.
class TubeCaptionOverlay extends StatelessWidget {
  final String? cueText;

  const TubeCaptionOverlay({super.key, required this.cueText});

  @override
  Widget build(BuildContext context) {
    if (cueText == null || cueText!.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return Positioned(
      bottom: 24,
      left: 20,
      right: 20,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            cueText!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.3,
              shadows: [
                Shadow(color: Colors.black, blurRadius: 4, offset: Offset(1, 1)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
