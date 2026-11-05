import 'dart:convert';

import 'package:dart_trackers/dart_trackers.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

/// Float tolerances from `conformance/fixtures/manifest.json`.
final Map<String, dynamic> _policy =
    (jsonDecode(fixtureJson('manifest.json')) as Map<String, dynamic>)['policy']
        as Map<String, dynamic>;

double _tolerance(String group, String key) =>
    ((_policy[group] as Map<String, dynamic>)[key] as num).toDouble();

/// Builds the IoU metric named by a fixture's `iou` parameter.
BaseIoU? iouFromParams(Map<String, dynamic> params) {
  final name = params['iou'] as String?;
  return name == null ? null : BaseIoU.fromName(name);
}

typedef TrackerFactory = Tracker Function(
  Map<String, dynamic> params,
  TrackerWarningHandler onWarning,
);

int _int(Map<String, dynamic> params, String key, int fallback) =>
    params[key] as int? ?? fallback;

double _double(Map<String, dynamic> params, String key, double fallback) =>
    (params[key] as num?)?.toDouble() ?? fallback;

Tracker sortFromParams(Map<String, dynamic> p, TrackerWarningHandler w) =>
    SORTTracker(
      lostTrackBuffer: _int(p, 'lost_track_buffer', 30),
      frameRate: _double(p, 'frame_rate', 30.0),
      trackActivationThreshold: _double(p, 'track_activation_threshold', 0.25),
      minimumConsecutiveFrames: _int(p, 'minimum_consecutive_frames', 3),
      minimumIouThreshold: _double(p, 'minimum_iou_threshold', 0.3),
      iou: iouFromParams(p),
      onWarning: w,
    );

Tracker byteTrackFromParams(Map<String, dynamic> p, TrackerWarningHandler w) =>
    ByteTrackTracker(
      lostTrackBuffer: _int(p, 'lost_track_buffer', 30),
      frameRate: _double(p, 'frame_rate', 30.0),
      trackActivationThreshold: _double(p, 'track_activation_threshold', 0.7),
      minimumConsecutiveFrames: _int(p, 'minimum_consecutive_frames', 2),
      minimumIouThreshold: _double(p, 'minimum_iou_threshold', 0.1),
      highConfDetThreshold: _double(p, 'high_conf_det_threshold', 0.6),
      iou: iouFromParams(p),
      onWarning: w,
    );

Tracker ocsortFromParams(Map<String, dynamic> p, TrackerWarningHandler w) =>
    OCSORTTracker(
      lostTrackBuffer: _int(p, 'lost_track_buffer', 30),
      frameRate: _double(p, 'frame_rate', 30.0),
      minimumConsecutiveFrames: _int(p, 'minimum_consecutive_frames', 3),
      minimumIouThreshold: _double(p, 'minimum_iou_threshold', 0.3),
      directionConsistencyWeight: _double(
        p,
        'direction_consistency_weight',
        0.2,
      ),
      highConfDetThreshold: _double(p, 'high_conf_det_threshold', 0.6),
      deltaT: _int(p, 'delta_t', 3),
      iou: iouFromParams(p),
      onWarning: w,
    );

Tracker botsortFromParams(Map<String, dynamic> p, TrackerWarningHandler w) =>
    BoTSORTTracker(
      lostTrackBuffer: _int(p, 'lost_track_buffer', 30),
      frameRate: _double(p, 'frame_rate', 30.0),
      trackActivationThreshold: _double(p, 'track_activation_threshold', 0.7),
      minimumConsecutiveFrames: _int(p, 'minimum_consecutive_frames', 2),
      minimumIouThresholdFirstAssoc: _double(
        p,
        'minimum_iou_threshold_first_assoc',
        0.2,
      ),
      minimumIouThresholdSecondAssoc: _double(
        p,
        'minimum_iou_threshold_second_assoc',
        0.5,
      ),
      minimumIouThresholdUnconfirmedAssoc: _double(
        p,
        'minimum_iou_threshold_unconfirmed_assoc',
        0.3,
      ),
      highConfDetThreshold: _double(p, 'high_conf_det_threshold', 0.6),
      instantFirstFrameActivation:
          p['instant_first_frame_activation'] as bool? ?? true,
      firstIou: iouFromParams(p),
      onWarning: w,
    );

Tracker cbiouFromParams(Map<String, dynamic> p, TrackerWarningHandler w) =>
    CBIoUTracker(
      lostTrackBuffer: _int(p, 'lost_track_buffer', 30),
      frameRate: _double(p, 'frame_rate', 30.0),
      trackActivationThreshold: _double(p, 'track_activation_threshold', 0.7),
      minimumConsecutiveFrames: _int(p, 'minimum_consecutive_frames', 2),
      minimumIouThresholdFirstAssoc: _double(
        p,
        'minimum_iou_threshold_first_assoc',
        0.2,
      ),
      minimumIouThresholdSecondAssoc: _double(
        p,
        'minimum_iou_threshold_second_assoc',
        0.5,
      ),
      minimumIouThresholdUnconfirmedAssoc: _double(
        p,
        'minimum_iou_threshold_unconfirmed_assoc',
        0.3,
      ),
      highConfDetThreshold: _double(p, 'high_conf_det_threshold', 0.6),
      instantFirstFrameActivation:
          p['instant_first_frame_activation'] as bool? ?? true,
      bufferRatioFirst: _double(p, 'buffer_ratio_first', 0.3),
      bufferRatioSecond: _double(p, 'buffer_ratio_second', 0.5),
      onWarning: w,
    );

/// Replays every case of a tracker fixture file and checks IDs, output row
/// order, confirmed tracked-object boxes, and warning counts per frame.
void runTrackerConformance(String fixtureName, TrackerFactory factory) {
  final cases = jsonDecode(fixtureJson(fixtureName)) as List<dynamic>;
  final atol = _tolerance('kalman_state', 'atol');
  final rtol = _tolerance('kalman_state', 'rtol');
  for (final rawCase in cases) {
    final testCase = rawCase as Map<String, dynamic>;
    test(testCase['name'] as String, () {
      final warnings = <String>[];
      final tracker = factory(
        testCase['params'] as Map<String, dynamic>,
        warnings.add,
      );
      final frames = testCase['frames'] as List<dynamic>;
      final expectedIds = testCase['expected_tracker_id'] as List<dynamic>;
      final expectedIndices =
          testCase['expected_output_indices'] as List<dynamic>;
      final expectedTracked =
          testCase['expected_tracked_objects'] as List<dynamic>;
      final expectedWarnings =
          testCase['expected_warning_count'] as List<dynamic>;
      for (var f = 0; f < frames.length; f++) {
        final frame = frames[f] as Map<String, dynamic>;
        final detections = detectionsFromFrame(frame);
        final warningsBefore = warnings.length;
        final result = tracker.update(
          detections,
          timestamp: (frame['timestamp'] as num?)?.toDouble(),
        );
        final where = 'frame $f';
        expect(
          result.trackerIdList() ?? const <int>[],
          equals((expectedIds[f] as List<dynamic>).cast<int>()),
          reason: '$where tracker ids',
        );
        expect(
          result.xyxyRows(),
          equals(
            boxesForIndices(
              frame,
              (expectedIndices[f] as List<dynamic>).cast<int>(),
            ),
          ),
          reason: '$where output rows',
        );
        expect(
          warnings.length - warningsBefore,
          equals(expectedWarnings[f] as int),
          reason: '$where warnings: ${warnings.skip(warningsBefore)}',
        );
        expect(
          detections.trackerId,
          isNull,
          reason: 'update() must not mutate input',
        );

        final tracked = expectedTracked[f] as Map<String, dynamic>;
        final actualTracked = tracker.trackedObjects;
        expect(
          actualTracked.trackerIdList() ?? const <int>[],
          equals((tracked['tracker_id'] as List<dynamic>).cast<int>()),
          reason: '$where tracked ids',
        );
        final expectedBoxes = parseRows(tracked['xyxy'] as List<dynamic>);
        final actualBoxes = actualTracked.xyxyRows();
        for (var i = 0; i < expectedBoxes.length; i++) {
          for (var j = 0; j < 4; j++) {
            final expected = expectedBoxes[i][j];
            expect(
              actualBoxes[i][j],
              closeTo(expected, atol + rtol * expected.abs()),
              reason: '$where tracked box $i[$j]',
            );
          }
        }
      }
    });
  }
}

Detections detectionsFromFrame(Map<String, dynamic> frame) {
  final boxes = (frame['xyxy'] as List<dynamic>)
      .map((row) => (row as List<dynamic>).map((v) => v as num).toList())
      .toList();
  final confidence = frame['confidence'] == null
      ? null
      : (frame['confidence'] as List<dynamic>).map((v) => v as num).toList();
  final classId = frame['class_id'] == null
      ? null
      : (frame['class_id'] as List<dynamic>).cast<int>();
  return Detections.fromRows(boxes, confidence: confidence, classId: classId);
}

List<List<double>> boxesForIndices(
  Map<String, dynamic> frame,
  List<int> indices,
) {
  final boxes = parseRows(frame['xyxy'] as List<dynamic>);
  return [for (final index in indices) boxes[index]];
}

/// Parses nested JSON rows, decoding `"inf"`, `"-inf"`, and `"nan"` strings.
List<List<double>> parseRows(List<dynamic> rows) => [
  for (final row in rows)
    [for (final value in row as List<dynamic>) parseDouble(value)],
];

double parseDouble(Object? value) => switch (value) {
  num() => value.toDouble(),
  'inf' => double.infinity,
  '-inf' => double.negativeInfinity,
  'nan' => double.nan,
  _ => throw ArgumentError.value(value, 'value', 'Not a fixture number'),
};
