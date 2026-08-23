import 'kalman_filter.dart';
import 'matrix.dart';

/// Scales a tracker's tuned one-frame process noise for variable frame gaps.
class ScalableProcessNoise {
  final int dimension;
  final List<int> positionIndices;
  final List<int> velocityIndices;
  Matrix _baseline;
  List<double>? _accelerationVariance;

  ScalableProcessNoise({
    required this.dimension,
    required this.positionIndices,
    required this.velocityIndices,
    required Matrix baseline,
  }) : _baseline = baseline.copy() {
    if (positionIndices.length != velocityIndices.length) {
      throw ArgumentError('Position and velocity indices must have equal size');
    }
  }

  void calibrate(Matrix processNoise) {
    _baseline = processNoise.copy();
    _accelerationVariance = null;
  }

  Matrix build(double frameStep, {double? frameRate}) {
    final tolerance = frameRate != null && frameRate > 0.0
        ? 0.004 * frameRate
        : 0.1;
    if ((frameStep - 1.0).abs() <= tolerance) return _baseline.copy();

    final acceleration = _accelerationVariance ??= [
      for (final index in velocityIndices) _baseline[index][index],
    ];
    final kinematic = {...positionIndices, ...velocityIndices};
    final result = Matrix(dimension, dimension);
    final dt2 = frameStep * frameStep;
    final dt3 = dt2 * frameStep;
    final dt4 = dt2 * dt2;
    for (var i = 0; i < positionIndices.length; i++) {
      final p = positionIndices[i];
      final v = velocityIndices[i];
      final variance = acceleration[i];
      result[p][p] = variance * dt4 / 4.0;
      result[p][v] = variance * dt3 / 2.0;
      result[v][p] = variance * dt3 / 2.0;
      result[v][v] = variance * dt2;
    }
    for (var i = 0; i < dimension; i++) {
      if (!kinematic.contains(i)) result[i][i] = _baseline[i][i];
    }
    return result;
  }
}

/// Writes the constant-velocity transition and scaled noise onto a filter.
class KalmanMotionModel {
  final int dimension;
  final List<int> positionIndices;
  final List<int> velocityIndices;
  final ScalableProcessNoise processNoise;
  double? _cachedStep;
  Matrix? _cachedTransition;
  Matrix? _cachedNoise;

  KalmanMotionModel.fromFilter(
    KalmanFilter filter, {
    required this.positionIndices,
    required this.velocityIndices,
  }) : dimension = filter.dimX,
       processNoise = ScalableProcessNoise(
         dimension: filter.dimX,
         positionIndices: positionIndices,
         velocityIndices: velocityIndices,
         baseline: filter.q,
       );

  void calibrate(Matrix processNoise) {
    this.processNoise.calibrate(processNoise);
    _cachedNoise = null;
  }

  void apply(KalmanFilter filter, double frameStep, {double? frameRate}) {
    if (_cachedTransition == null || _cachedStep != frameStep) {
      final transition = Matrix.identity(dimension);
      for (var i = 0; i < positionIndices.length; i++) {
        transition[positionIndices[i]][velocityIndices[i]] = frameStep;
      }
      _cachedTransition = transition;
      _cachedStep = frameStep;
      _cachedNoise = null;
    }
    _cachedNoise ??= processNoise.build(frameStep, frameRate: frameRate);
    filter.f = _cachedTransition!.copy();
    filter.q = _cachedNoise!.copy();
  }

  void resetCache() {
    _cachedStep = null;
    _cachedTransition = null;
    _cachedNoise = null;
  }
}
