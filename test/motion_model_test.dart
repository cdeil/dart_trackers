import 'package:dart_trackers/dart_trackers.dart';
import 'package:test/test.dart';

void main() {
  test('Matrix.diagonal places values on the diagonal only', () {
    for (final size in [1, 4, 7, 8]) {
      final values = [for (var i = 0; i < size; i++) i + 1.0];
      final matrix = Matrix.diagonal(values);
      for (var i = 0; i < size; i++) {
        for (var j = 0; j < size; j++) {
          expect(matrix[i][j], i == j ? values[i] : 0.0);
        }
      }
    }
  });

  ScalableProcessNoise noise() => ScalableProcessNoise(
    dimension: 3,
    positionIndices: const [0],
    velocityIndices: const [1],
    baseline: Matrix.diagonal([2.0, 0.5, 7.0]),
  );

  test('near-nominal steps return the one-frame baseline exactly', () {
    // Band is 0.004 * frameRate with a frame rate, 0.1 frame units without.
    expect(noise().build(1.11, frameRate: 30.0).data, [
      2.0,
      0,
      0,
      0,
      0.5,
      0,
      0,
      0,
      7.0,
    ]);
    expect(noise().build(1.09).data[0], 2.0);
    expect(noise().build(1.11).data[0], isNot(2.0));
    expect(noise().build(1.13, frameRate: 30.0).data[0], isNot(2.0));
  });

  test('gap steps use discrete white-noise acceleration scaling', () {
    final q = noise().build(2.0);
    expect(q[0][0], 0.5 * 16 / 4); // sigma^2 * dt^4 / 4
    expect(q[0][1], 0.5 * 8 / 2); // sigma^2 * dt^3 / 2
    expect(q[1][0], 0.5 * 8 / 2);
    expect(q[1][1], 0.5 * 4); // sigma^2 * dt^2
    expect(q[2][2], 7.0); // non-kinematic entries keep the baseline
  });

  test('transition matrix couples position and velocity by the step', () {
    final kf = KalmanFilter(dimX: 2, dimZ: 1);
    final model = KalmanMotionModel.fromFilter(
      kf,
      positionIndices: const [0],
      velocityIndices: const [1],
    );
    model.apply(kf, 2.5);
    expect(kf.f.data, [1.0, 2.5, 0.0, 1.0]);
  });

  test('TrackerClock bootstrap step is computed like upstream', () {
    final timing = TrackerClock(49.0).timing(100.0);
    expect(timing.frameStep, (1.0 / 49.0) * 49.0);
    expect(timing.skipPredict, isFalse);
  });
}
