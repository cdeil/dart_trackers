import 'package:dart_trackers/dart_trackers.dart';

void main() {
  final tracker = SORTTracker(minimumConsecutiveFrames: 1);
  final detections = Detections.fromRows(
    [
      [0, 0, 10, 10],
    ],
    confidence: [0.9],
  );

  final tracked = tracker.update(detections);
  print('tracker ids: ${tracked.trackerIdList()}');
}
