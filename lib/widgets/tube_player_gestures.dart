import 'dart:async';
import 'package:flutter/material.dart';

/// Interactive gesture detector overlay for the video player:
/// - Left-half vertical drag: Brightness adjustment HUD
/// - Right-half vertical drag: Volume adjustment HUD
/// - Left-half double tap: -10s seek ripple
/// - Right-half double tap: +10s seek ripple
/// - Single tap: Toggle controls visibility
class TubePlayerGestures extends StatefulWidget {
  final Widget child;
  final double zoom;
  final ValueChanged<double>? onZoomChanged;
  final VoidCallback onSingleTap;
  final VoidCallback? onCollapse;
  final VoidCallback onDoubleTapLeft;
  final VoidCallback onDoubleTapRight;
  final ValueChanged<double>? onBrightnessChanged;
  final ValueChanged<double>? onVolumeChanged;

  const TubePlayerGestures({
    super.key,
    required this.child,
    this.zoom = 1,
    this.onZoomChanged,
    required this.onSingleTap,
    this.onCollapse,
    required this.onDoubleTapLeft,
    required this.onDoubleTapRight,
    this.onBrightnessChanged,
    this.onVolumeChanged,
  });

  @override
  State<TubePlayerGestures> createState() => _TubePlayerGesturesState();
}

class _TubePlayerGesturesState extends State<TubePlayerGestures> {
  // HUD states
  bool _showLeftSeekRipple = false;
  bool _showRightSeekRipple = false;
  Timer? _leftRippleTimer;
  Timer? _rightRippleTimer;

  double _dragDistance = 0;
  double _dragHorizontal = 0;
  Offset _lastFocal = Offset.zero;
  double _startZoom = 1;
  double _doubleTapX = 0;
  bool _pinching = false;
  int _dragSide = 0; // centre collapses; edges adjust brightness/volume.
  double _brightness = 0.5;
  double _volume = 0.7;
  bool _showBrightnessHud = false;
  bool _showVolumeHud = false;
  Timer? _hudHideTimer;

  void _triggerLeftRipple() {
    setState(() => _showLeftSeekRipple = true);
    _leftRippleTimer?.cancel();
    _leftRippleTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _showLeftSeekRipple = false);
    });
    widget.onDoubleTapLeft();
  }

  void _triggerRightRipple() {
    setState(() => _showRightSeekRipple = true);
    _rightRippleTimer?.cancel();
    _rightRippleTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _showRightSeekRipple = false);
    });
    widget.onDoubleTapRight();
  }

  void _handleVerticalDragUpdate(
      DragUpdateDetails details, double screenWidth) {
    final isLeft = details.localPosition.dx < (screenWidth / 2);
    final delta = -details.primaryDelta! / 200.0;

    if (isLeft) {
      setState(() {
        _brightness = (_brightness + delta).clamp(0.0, 1.0);
        _showBrightnessHud = true;
        _showVolumeHud = false;
      });
      widget.onBrightnessChanged?.call(_brightness);
    } else {
      setState(() {
        _volume = (_volume + delta).clamp(0.0, 1.0);
        _showVolumeHud = true;
        _showBrightnessHud = false;
      });
      widget.onVolumeChanged?.call(_volume);
    }

    _hudHideTimer?.cancel();
    _hudHideTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) {
        setState(() {
          _showBrightnessHud = false;
          _showVolumeHud = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _leftRippleTimer?.cancel();
    _rightRippleTimer?.cancel();
    _hudHideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;

        return Stack(
          children: [
            ClipRect(
                child:
                    Transform.scale(scale: widget.zoom, child: widget.child)),

            // Gesture capture surface
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: widget.onSingleTap,
                onDoubleTapDown: (details) =>
                    _doubleTapX = details.localPosition.dx,
                onDoubleTap: () {
                  if (_doubleTapX < screenWidth / 2) {
                    _triggerLeftRipple();
                  } else {
                    _triggerRightRipple();
                  }
                },
                onScaleStart: (details) {
                  _dragDistance = _dragHorizontal = 0;
                  _lastFocal = details.localFocalPoint;
                  _startZoom = widget.zoom;
                  _pinching = details.pointerCount > 1;
                  final x = details.localFocalPoint.dx / screenWidth;
                  _dragSide = x < 0.25 && widget.onBrightnessChanged != null
                      ? -1
                      : x > 0.75 && widget.onVolumeChanged != null
                          ? 1
                          : 0;
                },
                onScaleUpdate: (details) {
                  if (details.pointerCount > 1) _pinching = true;
                  final delta = details.localFocalPoint - _lastFocal;
                  _lastFocal = details.localFocalPoint;
                  if (_pinching) {
                    widget.onZoomChanged
                        ?.call((_startZoom * details.scale).clamp(1.0, 3.0));
                    return;
                  }
                  _dragDistance += delta.dy;
                  _dragHorizontal += delta.dx;
                  if (_dragSide != 0) {
                    _handleVerticalDragUpdate(
                        DragUpdateDetails(
                            globalPosition: details.focalPoint,
                            primaryDelta: delta.dy,
                            delta: Offset(0, delta.dy),
                            localPosition:
                                Offset(_dragSide < 0 ? 0 : screenWidth, 0)),
                        screenWidth);
                  }
                },
                onScaleEnd: (details) {
                  if (!_pinching &&
                      _dragSide == 0 &&
                      _dragDistance > _dragHorizontal.abs() &&
                      (_dragDistance > 60 ||
                          details.velocity.pixelsPerSecond.dy > 500)) {
                    widget.onCollapse?.call();
                  }
                },
              ),
            ),

            // Left seek ripple indicator (-10s)
            if (_showLeftSeekRipple)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: screenWidth * 0.45,
                child: IgnorePointer(
                    child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(80)),
                  ),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.fast_rewind_rounded,
                            color: Colors.white, size: 40),
                        SizedBox(height: 4),
                        Text('-10s',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13)),
                      ],
                    ),
                  ),
                )),
              ),

            // Right seek ripple indicator (+10s)
            if (_showRightSeekRipple)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: screenWidth * 0.45,
                child: IgnorePointer(
                    child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(80)),
                  ),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.fast_forward_rounded,
                            color: Colors.white, size: 40),
                        SizedBox(height: 4),
                        Text('+10s',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13)),
                      ],
                    ),
                  ),
                )),
              ),

            // Brightness HUD
            if (_showBrightnessHud)
              Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _brightness > 0.5
                            ? Icons.brightness_high
                            : Icons.brightness_medium,
                        color: Colors.amberAccent,
                        size: 24,
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 100,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _brightness,
                            backgroundColor: Colors.white24,
                            valueColor: const AlwaysStoppedAnimation(
                                Colors.amberAccent),
                            minHeight: 6,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${(_brightness * 100).toInt()}%',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),

            // Volume HUD
            if (_showVolumeHud)
              Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _volume > 0.5
                            ? Icons.volume_up
                            : (_volume > 0
                                ? Icons.volume_down
                                : Icons.volume_mute),
                        color: const Color(0xFF00E5FF),
                        size: 24,
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 100,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _volume,
                            backgroundColor: Colors.white24,
                            valueColor:
                                const AlwaysStoppedAnimation(Color(0xFF00E5FF)),
                            minHeight: 6,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${(_volume * 100).toInt()}%',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
