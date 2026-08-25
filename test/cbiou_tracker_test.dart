import 'dart:convert';

import 'package:dart_trackers/dart_trackers.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('CBIoUTracker conformance', () {
    final cases = jsonDecode(fixtureJson('cbiou_cases.json')) as List<dynamic>;
    for (final rawCase in cases) {
      final testCase = rawCase as Map<String, dynamic>;
      test(testCase['name'] as String, () {
        final params = testCase['params'] as Map<String, dynamic>;
        final tracker = CBIoUTracker(
          trackActivationThreshold:
              (params['track_activation_threshold'] as num?)?.toDouble() ?? 0.7,
          minimumConsecutiveFrames:
              params['minimum_consecutive_frames'] as int? ?? 2,
          minimumIouThresholdFirstAssoc:
              (params['minimum_iou_threshold_first_assoc'] as num?)
                  ?.toDouble() ??
              0.2,
          highConfDetThreshold:
              (params['high_conf_det_threshold'] as num?)?.toDouble() ?? 0.6,
          bufferRatioFirst:
              (params['buffer_ratio_first'] as num?)?.toDouble() ?? 0.3,
          bufferRatioSecond:
              (params['buffer_ratio_second'] as num?)?.toDouble() ?? 0.5,
        );

        final frames = testCase['frames'] as List<dynamic>;
        final expectedIds = testCase['expected_tracker_id'] as List<dynamic>;
        for (var index = 0; index < frames.length; index++) {
          final frame = frames[index] as Map<String, dynamic>;
          final result = tracker.update(_detections(frame));
          expect(
            result.trackerIdList(),
            equals((expectedIds[index] as List<dynamic>).cast<int>()),
          );
        }
      });
    }
  });
}

Detections _detections(Map<String, dynamic> frame) => Detections.fromRows(
  (frame['xyxy'] as List<dynamic>)
      .map((row) => (row as List<dynamic>).cast<num>())
      .toList(),
  confidence: (frame['confidence'] as List<dynamic>?)?.cast<num>(),
);
