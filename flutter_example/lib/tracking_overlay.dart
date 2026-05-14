import 'dart:math' as math;

import 'package:flutter/material.dart';

class TrackedDetection {
  final Rect box;
  final int trackerId;
  final double confidence;
  final String label;

  const TrackedDetection({
    required this.box,
    required this.trackerId,
    required this.confidence,
    required this.label,
  });
}

class TrackingOverlayPainter extends CustomPainter {
  final List<TrackedDetection> detections;

  const TrackingOverlayPainter(this.detections);

  @override
  void paint(Canvas canvas, Size size) {
    for (final detection in detections) {
      final color = _colorForTrack(detection.trackerId);
      final rect = Rect.fromLTRB(
        detection.box.left * size.width,
        detection.box.top * size.height,
        detection.box.right * size.width,
        detection.box.bottom * size.height,
      );
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = color;
      canvas.drawRect(rect, paint);

      final label = detection.trackerId >= 0
          ? '#${detection.trackerId} ${detection.label} ${(detection.confidence * 100).round()}%'
          : '${detection.label} ${(detection.confidence * 100).round()}%';
      _drawLabel(canvas, rect.topLeft, label, color);
    }
  }

  void _drawLabel(Canvas canvas, Offset origin, String label, Color color) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final background = Rect.fromLTWH(
      origin.dx,
      math.max(0, origin.dy - painter.height - 4),
      painter.width + 8,
      painter.height + 4,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(background, const Radius.circular(4)),
      Paint()..color = color,
    );
    painter.paint(canvas, background.topLeft + const Offset(4, 2));
  }

  @override
  bool shouldRepaint(covariant TrackingOverlayPainter oldDelegate) {
    return oldDelegate.detections != detections;
  }
}

Color _colorForTrack(int id) {
  if (id < 0) return Colors.white;
  final hue = (id * 47) % 360;
  return HSVColor.fromAHSV(1, hue.toDouble(), 0.75, 1).toColor();
}
