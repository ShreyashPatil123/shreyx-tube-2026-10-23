import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:provider/provider.dart';
import '../providers/tube_player_provider.dart';
import '../theme/tube_theme.dart';

/// Compact native-video controls. Gesture capture is below the interactive buttons.
class TubeMiniPlayer extends StatefulWidget {
  final VoidCallback onExpand;
  final Widget videoSurface;
  final bool compact;
  final double height;
  final VoidCallback? onToggleSize, onHide, onDrop;
  final ValueChanged<Offset>? onMove;
  final ValueChanged<double>? onResize;
  const TubeMiniPlayer(
      {super.key,
      required this.onExpand,
      required this.videoSurface,
      this.compact = true,
      this.height = 84,
      this.onToggleSize,
      this.onHide,
      this.onMove,
      this.onResize,
      this.onDrop});
  @override
  State<TubeMiniPlayer> createState() => _TubeMiniPlayerState();
}

class _TubeMiniPlayerState extends State<TubeMiniPlayer> {
  Offset _last = Offset.zero, _distance = Offset.zero, _longLast = Offset.zero;
  bool _pinching = false;
  @override
  Widget build(BuildContext context) {
    final player = context.watch<TubePlayerProvider>();
    final video = player.currentVideoItem;
    final progress = player.duration.inMilliseconds > 0
        ? (player.position.inMilliseconds / player.duration.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;
    final surface = Stack(fit: StackFit.expand, children: [
      if (!player.isMembersOnly) widget.videoSurface,
      // Native platform views do not receive the Flutter gesture sequence.
      const Positioned.fill(child: ColoredBox(color: Colors.transparent)),
      if (player.isLoading || player.isBuffering)
        const IgnorePointer(
            child: Center(
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)))),
      if (player.isMembersOnly)
        const Center(
            child: Text('Members only', style: TextStyle(fontSize: 10))),
    ]);
    final information = Expanded(
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      player.resolvedVideo?.title ??
                          video?.title ??
                          'Playing video',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                      '${player.isLive ? 'LIVE • ' : ''}${player.resolvedVideo?.uploader ?? video?.channelTitle ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(fontSize: 10, color: Colors.white70)),
                ])));
    final buttons = <Widget>[
      IconButton(
          tooltip: 'Play/Pause',
          iconSize: 22,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: player.togglePlayPause,
          icon: Icon(player.isPlaying ? Icons.pause : Icons.play_arrow)),
      IconButton(
          tooltip: 'Close player',
          iconSize: 20,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: player.dismissPlayer,
          icon: const Icon(Icons.close)),
    ];
    return Semantics(
      label: 'Video mini-player',
      button: true,
      onTap: widget.onExpand,
      customSemanticsActions: {
        if (widget.onToggleSize != null)
          const CustomSemanticsAction(label: 'Resize player'):
              widget.onToggleSize!,
        if (widget.onHide != null)
          const CustomSemanticsAction(label: 'Hide player'): widget.onHide!,
        if (widget.onMove != null) ...{
          const CustomSemanticsAction(label: 'Move player left'): () =>
              widget.onMove!(const Offset(-40, 0)),
          const CustomSemanticsAction(label: 'Move player right'): () =>
              widget.onMove!(const Offset(40, 0)),
          const CustomSemanticsAction(label: 'Move player up'): () =>
              widget.onMove!(const Offset(0, -40)),
          const CustomSemanticsAction(label: 'Move player down'): () =>
              widget.onMove!(const Offset(0, 40)),
        },
      },
      child: Material(
        elevation: 6,
        color: TubeTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: GestureDetector(
          onLongPressStart: (_) => _longLast = Offset.zero,
          onLongPressMoveUpdate: (d) {
            widget.onMove?.call(d.localOffsetFromOrigin - _longLast);
            _longLast = d.localOffsetFromOrigin;
          },
          onLongPressEnd: (_) => widget.onDrop?.call(),
          child: GestureDetector(
            key: const ValueKey('floating-player'),
            behavior: HitTestBehavior.opaque,
            onTap: widget.onExpand,
            onDoubleTap: widget.onToggleSize,
            onScaleStart: (d) {
              _last = d.focalPoint;
              _distance = Offset.zero;
              _pinching = d.pointerCount > 1;
            },
            onScaleUpdate: (d) {
              if (d.pointerCount > 1) _pinching = true;
              if (_pinching) {
                widget.onResize?.call(d.scale);
                return;
              }
              final delta = d.focalPoint - _last;
              _last = d.focalPoint;
              _distance += delta;
              widget.onMove?.call(delta);
            },
            onScaleEnd: (d) {
              if (!_pinching &&
                  _distance.dy < -45 &&
                  _distance.dy.abs() > _distance.dx.abs()) {
                widget.onExpand();
              } else {
                widget.onDrop?.call();
              }
            },
            child: SizedBox(
                height: widget.height,
                child: Column(children: [
                  Expanded(
                      child: widget.compact
                          ? Row(children: [
                              SizedBox(width: 112, child: surface),
                              information,
                              ...buttons
                            ])
                          : Column(children: [
                              Expanded(child: surface),
                              SizedBox(
                                  height: 48,
                                  child:
                                      Row(children: [information, ...buttons]))
                            ])),
                  LinearProgressIndicator(
                      value: player.isLive ? null : progress,
                      minHeight: 2,
                      color: TubeTheme.progressRed,
                      backgroundColor: Colors.white12),
                ])),
          ),
        ),
      ),
    );
  }
}

/// Drag/resize geometry stays inside safe areas and above navigation and keyboard.
class TubeFloatingMiniPlayer extends StatefulWidget {
  final VoidCallback onExpand;
  final Widget videoSurface;
  const TubeFloatingMiniPlayer(
      {super.key, required this.onExpand, required this.videoSurface});
  @override
  State<TubeFloatingMiniPlayer> createState() => _TubeFloatingMiniPlayerState();
}

class _TubeFloatingMiniPlayerState extends State<TubeFloatingMiniPlayer> {
  Offset? _position;
  double _size = 0, _resizeHeight = 84;
  bool _hidden = false, _left = false;
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, bounds) {
        final padding = MediaQuery.paddingOf(context);
        final keyboard = MediaQuery.viewInsetsOf(context).bottom;
        final width = math.min(360.0, math.max(0.0, bounds.maxWidth - 16));
        final top = padding.top + 8;
        final bottom = math.max(padding.bottom + 80, keyboard + 8);
        final maxHeight = math.max(48.0, bounds.maxHeight - top - bottom);
        final compactHeight = 84.0 +
            (MediaQuery.textScalerOf(context).scale(12) / 12 - 1)
                    .clamp(0.0, 1.0) *
                16;
        final height =
            (compactHeight + _size * (width * 9 / 16 + 50 - compactHeight))
                .clamp(48.0, maxHeight);
        final maxX = math.max(8.0, bounds.maxWidth - width - 8);
        final maxY = math.max(top, bounds.maxHeight - bottom - height);
        final position = _position ?? Offset(maxX, maxY);
        final x = position.dx.clamp(8.0, maxX),
            y = position.dy.clamp(top, maxY);
        void move(Offset delta) =>
            setState(() => _position = (_position ?? Offset(x, y)) + delta);
        void hide() => setState(() {
              _hidden = true;
              _left = x < maxX / 2;
              _position = Offset(x, y);
            });
        void drop() {
          if (_position != null &&
              (_position!.dx < -16 || _position!.dx > maxX + 24)) {
            hide();
          } else {
            setState(() => _position = Offset(x, y));
          }
          _resizeHeight = height;
        }

        return Stack(fit: StackFit.expand, children: [
          Offstage(
              offstage: _hidden,
              child: SizedBox.expand(
                  child: Stack(children: [
                Positioned(
                    left: x,
                    top: y,
                    width: width,
                    child: Listener(
                        onPointerDown: (_) => _resizeHeight = height,
                        child: TubeMiniPlayer(
                            onExpand: widget.onExpand,
                            videoSurface: widget.videoSurface,
                            compact: _size < 0.3,
                            height: height,
                            onMove: move,
                            onDrop: drop,
                            onHide: hide,
                            onToggleSize: () =>
                                setState(() => _size = _size < 0.5 ? 1 : 0),
                            onResize: (scale) => setState(() => _size =
                                ((_resizeHeight * scale - compactHeight) /
                                        math.max(
                                            1,
                                            width * 9 / 16 +
                                                50 -
                                                compactHeight))
                                    .clamp(0.0, 1.0)))))
              ]))),
          if (_hidden)
            Positioned(
                left: _left ? 0 : null,
                right: _left ? null : 0,
                top: y,
                child: Material(
                    color: TubeTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                    child: IconButton(
                        tooltip: 'Show mini-player',
                        onPressed: () => setState(() => _hidden = false),
                        icon: Icon(_left
                            ? Icons.chevron_right
                            : Icons.chevron_left)))),
        ]);
      });
}
