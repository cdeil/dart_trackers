import 'package:dart_trackers/dart_trackers.dart';
import 'package:flutter/material.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import 'tracking_overlay.dart';

Widget buildYoloCameraPage() => const YoloCameraTrackingPage();

class YoloCameraTrackingPage extends StatefulWidget {
  const YoloCameraTrackingPage({super.key});

  @override
  State<YoloCameraTrackingPage> createState() => _YoloCameraTrackingPageState();
}

class _YoloCameraTrackingPageState extends State<YoloCameraTrackingPage> {
  final Tracker _tracker = ByteTrackTracker(minimumConsecutiveFrames: 1);
  final YOLOViewController _yoloController = YOLOViewController();
  List<TrackedDetection> _tracked = const [];

  @override
  void initState() {
    super.initState();
    _yoloController.setShowOverlays(false);
  }

  @override
  void dispose() {
    _yoloController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final modelPath = YOLO.defaultOfficialModel() ?? 'yolo26n';
    return Stack(
      fit: StackFit.expand,
      children: [
        YOLOView(
          modelPath: modelPath,
          task: YOLOTask.detect,
          controller: _yoloController,
          confidenceThreshold: 0.3,
          onResult: _onYoloResults,
        ),
        CustomPaint(painter: TrackingOverlayPainter(_tracked)),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'YOLO model: $modelPath\n'
                'Detections are converted to dart_trackers.Detections and '
                'tracked with ByteTrackTracker.',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _onYoloResults(List<YOLOResult> results) {
    final detections = Detections.fromRows(
      [
        for (final result in results)
          [
            result.normalizedBox.left,
            result.normalizedBox.top,
            result.normalizedBox.right,
            result.normalizedBox.bottom,
          ],
      ],
      confidence: [for (final result in results) result.confidence],
      classId: [for (final result in results) result.classIndex],
    );
    final tracked = _tracker.update(detections);
    setState(() {
      _tracked = [
        for (var i = 0; i < tracked.length; i++)
          TrackedDetection(
            box: Rect.fromLTRB(
              tracked.xyxy[i * 4],
              tracked.xyxy[i * 4 + 1],
              tracked.xyxy[i * 4 + 2],
              tracked.xyxy[i * 4 + 3],
            ),
            trackerId: tracked.trackerId?[i] ?? -1,
            confidence: tracked.confidenceAt(i),
            label: i < results.length ? results[i].className : 'object',
          ),
      ];
    });
  }
}
