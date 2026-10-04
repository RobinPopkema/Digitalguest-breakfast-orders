import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/email_service.dart';

class UpdateCountdown extends StatefulWidget {
  const UpdateCountdown(this.service, {super.key});
  final EmailService service;
  @override
  State<UpdateCountdown> createState() => _UpdateCountdownState();
}

class _UpdateCountdownState extends State<UpdateCountdown> {
  Timer? ticker;
  @override
  void initState() {
    super.initState();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.service.nextAutomaticCheck != null) setState(() {});
    });
  }

  @override
  void dispose() {
    ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.service.automaticCheckRemaining;
    final seconds = remaining == null
        ? 0
        : math.max(0, (remaining.inMilliseconds / 1000).ceil());
    final label = remaining == null
        ? 'Automatic updates paused'
        : 'Next automatic update in ${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: SizedBox(
          width: 20,
          height: 20,
          child: remaining == null
              ? Icon(
                  Icons.pause_circle_outline,
                  color: colors.outline,
                  size: 18,
                )
              : CustomPaint(
                  painter: CountdownRing(
                    fraction:
                        (remaining.inMilliseconds /
                                Duration(minutes: widget.service.interval)
                                    .inMilliseconds)
                            .clamp(0.0, 1.0),
                    foreground: colors.onSecondaryContainer.withValues(
                      alpha: .55,
                    ),
                    background: colors.onSecondaryContainer.withValues(
                      alpha: .12,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class CountdownRing extends CustomPainter {
  const CountdownRing({
    required this.fraction,
    required this.foreground,
    required this.background,
  });
  final double fraction;
  final Color foreground, background;
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero), radius = size.shortestSide / 2 - 2;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = background
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 2 * fraction,
      false,
      Paint()
        ..color = foreground
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(CountdownRing oldDelegate) =>
      fraction != oldDelegate.fraction ||
      foreground != oldDelegate.foreground ||
      background != oldDelegate.background;
}
