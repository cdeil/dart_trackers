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
}

Detections _detection(double x) => Detections.fromRows(
  [
    [x, 0, x + 10, 10],
  ],
  confidence: [0.9],
);

class _TranslationCmc implements CameraMotionCompensator {
  int resetCount = 0;

  @override
  Matrix estimateAffine2x3(Object frame, {List<List<double>>? maskBoxes}) =>
      Matrix.fromRows([
        [1, 0, 5],
        [0, 1, 0],
      ]);

  @override
  void reset() => resetCount++;
}
