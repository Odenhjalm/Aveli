import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class SmoothVideoSeekBar extends StatefulWidget {
  const SmoothVideoSeekBar({
    required VideoPlayerController controller,
    super.key,
  }) : controller = controller;

  final VideoPlayerController controller;

  @override
  State<SmoothVideoSeekBar> createState() => _SmoothVideoSeekBarState();
}

class _SmoothVideoSeekBarState extends State<SmoothVideoSeekBar> {
  static const Duration _seekDebounce = Duration(milliseconds: 70);
  static const int _minSeekDeltaMillis = 50;

  final ValueNotifier<double> _progress = ValueNotifier<double>(0);
  bool _isDragging = false;
  int _lastSeekMillis = -1;
  DateTime? _lastSeekAt;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerTick);
    _onControllerTick();
  }

  @override
  void didUpdateWidget(covariant SmoothVideoSeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller)) return;
    oldWidget.controller.removeListener(_onControllerTick);
    widget.controller.addListener(_onControllerTick);
    _lastSeekMillis = -1;
    _lastSeekAt = null;
    _onControllerTick();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerTick);
    _progress.dispose();
    super.dispose();
  }

  void _onControllerTick() {
    if (_isDragging) return;
    _setProgress(_fractionFromValue(widget.controller.value));
  }

  double _fractionFromValue(VideoPlayerValue value) {
    if (!value.isInitialized) return 0;
    final durationMs = value.duration.inMilliseconds;
    if (durationMs <= 0) return 0;
    final positionMs = value.position.inMilliseconds.clamp(0, durationMs);
    return positionMs / durationMs;
  }

  void _setProgress(double value) {
    final clamped = value.clamp(0.0, 1.0).toDouble();
    if ((_progress.value - clamped).abs() < 0.0005) return;
    _progress.value = clamped;
  }

  void _onTapDown(Offset localPosition, double width) {
    _applyPointerProgress(localPosition.dx, width, forceSeek: true);
  }

  void _onDragStart(Offset localPosition, double width) {
    _isDragging = true;
    _applyPointerProgress(localPosition.dx, width, forceSeek: true);
  }

  void _onDragUpdate(Offset localPosition, double width) {
    _applyPointerProgress(localPosition.dx, width);
  }

  void _onDragEnd() {
    if (!_isDragging) return;
    _isDragging = false;
    _dispatchSeek(_progress.value, force: true);
  }

  void _applyPointerProgress(
    double dx,
    double width, {
    bool forceSeek = false,
  }) {
    if (width <= 0) return;
    final fraction = (dx / width).clamp(0.0, 1.0).toDouble();
    _setProgress(fraction);
    _dispatchSeek(fraction, force: forceSeek);
  }

  void _dispatchSeek(double fraction, {bool force = false}) {
    final value = widget.controller.value;
    if (!value.isInitialized) return;
    final durationMs = value.duration.inMilliseconds;
    if (durationMs <= 0) return;

    final targetMs = (durationMs * fraction).round().clamp(0, durationMs);
    if (!force) {
      if (_lastSeekMillis >= 0 &&
          (targetMs - _lastSeekMillis).abs() < _minSeekDeltaMillis) {
        return;
      }
      final now = DateTime.now();
      final lastSeekAt = _lastSeekAt;
      if (lastSeekAt != null && now.difference(lastSeekAt) < _seekDebounce) {
        return;
      }
      _lastSeekAt = now;
    } else {
      _lastSeekAt = DateTime.now();
    }

    if (targetMs == _lastSeekMillis && !force) return;
    _lastSeekMillis = targetMs;
    unawaited(widget.controller.seekTo(Duration(milliseconds: targetMs)));
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        height: 22,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) => _onTapDown(details.localPosition, width),
              onHorizontalDragStart: (details) =>
                  _onDragStart(details.localPosition, width),
              onHorizontalDragUpdate: (details) =>
                  _onDragUpdate(details.localPosition, width),
              onHorizontalDragEnd: (_) => _onDragEnd(),
              onHorizontalDragCancel: _onDragEnd,
              child: ValueListenableBuilder<double>(
                valueListenable: _progress,
                builder: (context, progress, child) {
                  return CustomPaint(
                    painter: _SmoothVideoSeekBarPainter(
                      progress: progress,
                      trackColor: Colors.white.withValues(alpha: 0.22),
                      progressColor: Colors.white.withValues(alpha: 0.54),
                      thumbColor: Colors.white.withValues(alpha: 0.90),
                    ),
                    child: child,
                  );
                },
                child: const SizedBox.expand(),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SmoothVideoSeekBarPainter extends CustomPainter {
  const _SmoothVideoSeekBarPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
    required this.thumbColor,
  });

  final double progress;
  final Color trackColor;
  final Color progressColor;
  final Color thumbColor;

  @override
  void paint(Canvas canvas, Size size) {
    final clampedProgress = progress.clamp(0.0, 1.0).toDouble();
    final centerY = size.height / 2;
    final playedX = size.width * clampedProgress;

    final trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset.zero.translate(0, centerY),
      Offset(size.width, centerY),
      trackPaint,
    );

    final playedPaint = Paint()
      ..color = progressColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset.zero.translate(0, centerY),
      Offset(playedX, centerY),
      playedPaint,
    );

    final thumbPaint = Paint()..color = thumbColor;
    canvas.drawCircle(Offset(playedX, centerY), 4, thumbPaint);
  }

  @override
  bool shouldRepaint(covariant _SmoothVideoSeekBarPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.progressColor != progressColor ||
        oldDelegate.thumbColor != thumbColor;
  }
}
