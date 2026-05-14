import 'dart:convert';

import 'package:dart_trackers/dart_trackers.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('SORTTracker conformance', () {
    final cases = jsonDecode(fixtureJson('sort_cases.json')) as List<dynamic>;
    for (final rawCase in cases) {
      final testCase = rawCase as Map<String, dynamic>;
      test(testCase['name'] as String, () {
        final params = testCase['params'] as Map<String, dynamic>;
        final tracker = SORTTracker(
          lostTrackBuffer: params['lost_track_buffer'] as int? ?? 30,
          frameRate: (params['frame_rate'] as num?)?.toDouble() ?? 30.0,
          trackActivationThreshold:
              (params['track_activation_threshold'] as num?)?.toDouble() ??
              0.25,
          minimumConsecutiveFrames:
              params['minimum_consecutive_frames'] as int? ?? 3,
          minimumIouThreshold:
              (params['minimum_iou_threshold'] as num?)?.toDouble() ?? 0.3,
        );

        final frames = testCase['frames'] as List<dynamic>;
        final expected = testCase['expected_tracker_id'] as List<dynamic>;
        for (var frameIndex = 0; frameIndex < frames.length; frameIndex++) {
          final detections = _detectionsFromFrame(
            frames[frameIndex] as Map<String, dynamic>,
          );
          final result = tracker.update(detections);
          expect(
            result.trackerIdList(),
            equals((expected[frameIndex] as List<dynamic>).cast<int>()),
          );
          expect(
            detections.trackerId,
            isNull,
            reason: 'update() must not mutate input',
          );
        }
      });
    }
  });
}

Detections _detectionsFromFrame(Map<String, dynamic> frame) {
  final boxes = (frame['xyxy'] as List<dynamic>)
      .map((row) => (row as List<dynamic>).map((v) => v as num).toList())
      .toList();
  final confidence =
      frame.containsKey('confidence') && frame['confidence'] != null
      ? (frame['confidence'] as List<dynamic>).map((v) => v as num).toList()
      : null;
  final classId = frame.containsKey('class_id') && frame['class_id'] != null
      ? (frame['class_id'] as List<dynamic>).cast<int>()
      : null;
  return Detections.fromRows(boxes, confidence: confidence, classId: classId);
}
