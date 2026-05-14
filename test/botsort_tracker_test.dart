import 'dart:convert';

import 'package:dart_trackers/dart_trackers.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('BoTSORTTracker conformance without CMC', () {
    final cases =
        jsonDecode(fixtureJson('botsort_cases.json')) as List<dynamic>;
    for (final rawCase in cases) {
      final testCase = rawCase as Map<String, dynamic>;
      test(testCase['name'] as String, () {
        final params = testCase['params'] as Map<String, dynamic>;
        final tracker = BoTSORTTracker(
          lostTrackBuffer: params['lost_track_buffer'] as int? ?? 30,
          frameRate: (params['frame_rate'] as num?)?.toDouble() ?? 30.0,
          trackActivationThreshold:
              (params['track_activation_threshold'] as num?)?.toDouble() ?? 0.7,
          minimumConsecutiveFrames:
              params['minimum_consecutive_frames'] as int? ?? 2,
          minimumIouThresholdFirstAssoc:
              (params['minimum_iou_threshold_first_assoc'] as num?)
                  ?.toDouble() ??
              0.2,
          minimumIouThresholdSecondAssoc:
              (params['minimum_iou_threshold_second_assoc'] as num?)
                  ?.toDouble() ??
              0.5,
          minimumIouThresholdUnconfirmedAssoc:
              (params['minimum_iou_threshold_unconfirmed_assoc'] as num?)
                  ?.toDouble() ??
              0.3,
          highConfDetThreshold:
              (params['high_conf_det_threshold'] as num?)?.toDouble() ?? 0.6,
          instantFirstFrameActivation:
              params['instant_first_frame_activation'] as bool? ?? true,
        );

        final frames = testCase['frames'] as List<dynamic>;
        final expectedIds = testCase['expected_tracker_id'] as List<dynamic>;
        final expectedOutputIndices =
            testCase['expected_output_indices'] as List<dynamic>;
        for (var frameIndex = 0; frameIndex < frames.length; frameIndex++) {
          final frame = frames[frameIndex] as Map<String, dynamic>;
          final detections = _detectionsFromFrame(frame);
          final result = tracker.update(detections);
          expect(
            result.trackerIdList(),
            equals((expectedIds[frameIndex] as List<dynamic>).cast<int>()),
          );
          expect(
            result.xyxyRows(),
            equals(
              _boxesForIndices(
                frame,
                (expectedOutputIndices[frameIndex] as List<dynamic>)
                    .cast<int>(),
              ),
            ),
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

List<List<double>> _boxesForIndices(
  Map<String, dynamic> frame,
  List<int> indices,
) {
  final boxes = (frame['xyxy'] as List<dynamic>)
      .map(
        (row) =>
            (row as List<dynamic>).map((v) => (v as num).toDouble()).toList(),
      )
      .toList();
  return [for (final index in indices) boxes[index]];
}
