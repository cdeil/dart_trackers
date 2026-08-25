import 'matrix.dart';

/// Generic linear Kalman filter matching the Python reference math.
class KalmanFilter {
  final int dimX;
  final int dimZ;
  late Matrix x;
  late Matrix p;
  late Matrix f;
  late Matrix h;
  late Matrix q;
  late Matrix r;
  late Matrix k;
  late Matrix y;
  late Matrix s;

  new({required this.dimX, required this.dimZ}) {
    if (dimX < 1 || dimZ < 1) {
      throw ArgumentError('Kalman dimensions must be positive');
    }
    x = Matrix(dimX, 1);
    p = Matrix.identity(dimX);
    f = Matrix.identity(dimX);
    h = Matrix(dimZ, dimX);
    q = Matrix.identity(dimX);
    r = Matrix.identity(dimZ);
    k = Matrix(dimX, dimZ);
    y = Matrix(dimZ, 1);
    s = Matrix(dimZ, dimZ);
  }

  void predict() {
    x = f * x;
    p = f * p * f.transpose() + q;
  }

  void update(List<double>? measurement) {
    if (measurement == null) {
      y = Matrix(dimZ, 1);
      return;
    }
    if (measurement.length != dimZ) {
      throw ArgumentError.value(
        measurement.length,
        'measurement.length',
        'Expected $dimZ',
      );
    }
    final z = Matrix.column(measurement);
    y = z - h * x;
    final pht = p * h.transpose();
    s = h * pht + r;
    k = pht * s.inverse();
    x = x + k * y;

    final iKh = Matrix.identity(dimX) - k * h;
    p = iKh * p * iKh.transpose() + k * r * k.transpose();
  }
}
