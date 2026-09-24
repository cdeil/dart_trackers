import 'package:dart_trackers/dart_trackers.dart';
import 'package:test/test.dart';

void main() {
  test('BoT-SORT consumes portable external CMC transforms', () {
    final cmc = _TranslationCmc();
    final tracker = BoTSORTTracker(
      minimumConsecutiveFrames: 1,
      minimumIouThresholdFirstAssoc: 0.1,
      cameraMotionCompensator: cmc,
    );
    expect(
      tracker.update(_detection(0), frame: Object()).trackerIdList(),
      equals([0]),
    );
    expect(
      tracker.update(_detection(5), frame: Object()).trackerIdList(),
      equals([0]),
    );
    tracker.reset();
    expect(cmc.resetCount, equals(1));
  });

  test('CMC adapter receives only high-confidence boxes', () {
    final cmc = _TranslationCmc();
    final tracker = BoTSORTTracker(cameraMotionCompensator: cmc);
    tracker.update(
      Detections.fromRows(
        [
          [0, 0, 10, 10],
          [20, 0, 30, 10],
          [40, 0, 50, 10],
        ],
        confidence: [0.9, 0.3, 0.05],
      ),
      frame: Object(),
    );
    tracker.update(
      Detections.fromRows(
        [
          [1, 0, 11, 10],
        ],
        confidence: [0.3],
      ),
      frame: Object(),
    );
    expect(cmc.maskBoxes, [
      [
        [0.0, 0.0, 10.0, 10.0],
      ],
      null,
    ]);
  });

  test('BoT-SORT accepts a 3x3 transform and rejects non-finite ones', () {
    final track = BoTSORTTracklet([0, 0, 10, 10]);
    track.applyCameraMotion(
      Matrix.fromRows([
        [1, 0, 5],
        [0, 1, 0],
        [0, 0, 1],
      ]),
    );
    expect(track.getStateBbox(), equals([5.0, 0.0, 15.0, 10.0]));
    expect(
      () => track.applyCameraMotion(
        Matrix.fromRows([
          [1, 0, double.nan],
          [0, 1, 0],
        ]),
      ),
      throwsArgumentError,
    );
  });

  test('trackers without CMC warn about unused frames after timing checks', () {
    final warnings = <String>[];
    final tracker = CBIoUTracker(onWarning: warnings.add);
    tracker.update(_detection(0), frame: Object(), timestamp: 1.5);
    tracker.update(_detection(0), frame: Object(), timestamp: 0.5);
    expect(warnings, [
      'CBIoUTracker.update() received a frame argument but does not use it.',
      'Timestamp 0.5 is earlier than 1.5; skipping update.',
    ]);
  });
}

Detections _detection(double x) => Detections.fromRows(
  [
    [x, 0, x + 10, 10],
  ],
  confidence: [0.9],
);

class _TranslationCmc implements CameraMotionCompensator {
  int resetCount = 0;
  final maskBoxes = <List<List<double>>?>[];

  @override
  Matrix estimateAffine2x3(Object frame, {List<List<double>>? maskBoxes}) {
    this.maskBoxes.add(maskBoxes);
    return Matrix.fromRows([
      [1, 0, 5],
      [0, 1, 0],
    ]);
  }

  @override
  void reset() => resetCount++;
}
