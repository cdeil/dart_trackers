import 'matrix.dart';

double boxIou(List<double> a, List<double> b) {
  if (a.length != 4 || b.length != 4) {
    throw ArgumentError('Boxes must have length 4');
  }
  for (final value in [...a, ...b]) {
    if (!value.isFinite) {
      throw ArgumentError('Box contains non-finite value');
    }
  }
  final x1 = a[0] > b[0] ? a[0] : b[0];
  final y1 = a[1] > b[1] ? a[1] : b[1];
  final x2 = a[2] < b[2] ? a[2] : b[2];
  final y2 = a[3] < b[3] ? a[3] : b[3];
  final intersectionWidth = x2 - x1;
  final intersectionHeight = y2 - y1;
  if (intersectionWidth <= 0.0 || intersectionHeight <= 0.0) {
    return 0.0;
  }
  final intersection = intersectionWidth * intersectionHeight;
  final areaA = (a[2] - a[0]) * (a[3] - a[1]);
  final areaB = (b[2] - b[0]) * (b[3] - b[1]);
  final union = areaA + areaB - intersection;
  return union > 0.0 ? intersection / union : 0.0;
}

Matrix boxIouBatch(List<List<double>> boxesA, List<List<double>> boxesB) {
  final result = Matrix(boxesA.length, boxesB.length);
  for (var i = 0; i < boxesA.length; i++) {
    for (var j = 0; j < boxesB.length; j++) {
      result[i][j] = boxIou(boxesA[i], boxesB[j]);
    }
  }
  return result;
}
