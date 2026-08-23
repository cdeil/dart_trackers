import 'dart:math' as math;

import 'matrix.dart';

abstract class BaseIoU {
  const BaseIoU();

  Matrix compute(List<List<double>> boxesA, List<List<double>> boxesB) {
    _validateBoxes(boxesA, 'boxesA');
    _validateBoxes(boxesB, 'boxesB');
    if (boxesA.isEmpty || boxesB.isEmpty) {
      return Matrix(boxesA.length, boxesB.length);
    }
    return computeNonEmpty(boxesA, boxesB);
  }

  Matrix computeNonEmpty(List<List<double>> boxesA, List<List<double>> boxesB);

  Matrix normalizeForFusion(Matrix similarity) => similarity;
}

class IoU extends BaseIoU {
  const IoU();

  @override
  Matrix computeNonEmpty(List<List<double>> boxesA, List<List<double>> boxesB) {
    return _pairwiseGeometry(boxesA, boxesB).iou;
  }
}

class BIoU extends BaseIoU {
  final double bufferRatio;

  BIoU({this.bufferRatio = 0.1}) {
    if (bufferRatio < 0.0 || !bufferRatio.isFinite) {
      throw ArgumentError.value(bufferRatio, 'bufferRatio');
    }
  }

  @override
  Matrix computeNonEmpty(List<List<double>> boxesA, List<List<double>> boxesB) {
    if (bufferRatio == 0.0) return const IoU().compute(boxesA, boxesB);
    return const IoU().compute(
      [for (final box in boxesA) _buffer(box)],
      [for (final box in boxesB) _buffer(box)],
    );
  }

  List<double> _buffer(List<double> box) {
    final width = box[2] - box[0];
    final height = box[3] - box[1];
    return [
      box[0] - bufferRatio * width,
      box[1] - bufferRatio * height,
      box[2] + bufferRatio * width,
      box[3] + bufferRatio * height,
    ];
  }
}

abstract class _SignedIoU extends BaseIoU {
  const _SignedIoU();

  @override
  Matrix normalizeForFusion(Matrix similarity) {
    final result = similarity.copy();
    for (var i = 0; i < result.data.length; i++) {
      result.data[i] = ((result.data[i] + 1.0) / 2.0).clamp(0.0, 1.0);
    }
    return result;
  }
}

class GIoU extends _SignedIoU {
  const GIoU();

  @override
  Matrix computeNonEmpty(List<List<double>> boxesA, List<List<double>> boxesB) {
    final geometry = _pairwiseGeometry(boxesA, boxesB);
    final result = Matrix(boxesA.length, boxesB.length);
    for (var i = 0; i < result.data.length; i++) {
      final area = geometry.enclosingArea.data[i];
      final penalty = area > 0.0 ? (area - geometry.union.data[i]) / area : 0.0;
      result.data[i] = geometry.iou.data[i] - penalty;
    }
    return result;
  }
}

class DIoU extends _SignedIoU {
  static const _epsilon = 1e-7;
  const DIoU();

  @override
  Matrix computeNonEmpty(List<List<double>> boxesA, List<List<double>> boxesB) {
    final geometry = _pairwiseGeometry(boxesA, boxesB);
    final result = Matrix(boxesA.length, boxesB.length);
    for (var i = 0; i < boxesA.length; i++) {
      final ax = (boxesA[i][0] + boxesA[i][2]) * 0.5;
      final ay = (boxesA[i][1] + boxesA[i][3]) * 0.5;
      for (var j = 0; j < boxesB.length; j++) {
        final bx = (boxesB[j][0] + boxesB[j][2]) * 0.5;
        final by = (boxesB[j][1] + boxesB[j][3]) * 0.5;
        final dx = ax - bx;
        final dy = ay - by;
        result[i][j] =
            geometry.iou[i][j] -
            (dx * dx + dy * dy) /
                (geometry.enclosingDiagonalSquared[i][j] + _epsilon);
      }
    }
    return result;
  }
}

class CIoU extends _SignedIoU {
  static const _epsilon = 1e-7;
  const CIoU();

  @override
  Matrix computeNonEmpty(List<List<double>> boxesA, List<List<double>> boxesB) {
    final geometry = _pairwiseGeometry(boxesA, boxesB);
    final diou = const DIoU().compute(boxesA, boxesB);
    final result = Matrix(boxesA.length, boxesB.length);
    for (var i = 0; i < boxesA.length; i++) {
      final aw = boxesA[i][2] - boxesA[i][0];
      final ah = math.max(boxesA[i][3] - boxesA[i][1], _epsilon);
      for (var j = 0; j < boxesB.length; j++) {
        final bw = boxesB[j][2] - boxesB[j][0];
        final bh = math.max(boxesB[j][3] - boxesB[j][1], _epsilon);
        final angle = math.atan(aw / ah) - math.atan(bw / bh);
        final v = 4.0 / (math.pi * math.pi) * angle * angle;
        final denominator = 1.0 - geometry.iou[i][j] + v;
        final alpha = denominator > 0.0 ? v / denominator : 0.0;
        result[i][j] = diou[i][j] - alpha * v;
      }
    }
    return result;
  }
}

double boxIou(List<double> a, List<double> b) =>
    const IoU().compute([a], [b])[0][0];

Matrix boxIouBatch(List<List<double>> boxesA, List<List<double>> boxesB) =>
    const IoU().compute(boxesA, boxesB);

_Geometry _pairwiseGeometry(
  List<List<double>> boxesA,
  List<List<double>> boxesB,
) {
  final iou = Matrix(boxesA.length, boxesB.length);
  final union = Matrix(boxesA.length, boxesB.length);
  final enclosingArea = Matrix(boxesA.length, boxesB.length);
  final enclosingDiagonalSquared = Matrix(boxesA.length, boxesB.length);
  for (var i = 0; i < boxesA.length; i++) {
    final a = boxesA[i];
    final areaA = (a[2] - a[0]) * (a[3] - a[1]);
    for (var j = 0; j < boxesB.length; j++) {
      final b = boxesB[j];
      final intersectionWidth = math.max(
        math.min(a[2], b[2]) - math.max(a[0], b[0]),
        0.0,
      );
      final intersectionHeight = math.max(
        math.min(a[3], b[3]) - math.max(a[1], b[1]),
        0.0,
      );
      final intersection = intersectionWidth * intersectionHeight;
      final areaB = (b[2] - b[0]) * (b[3] - b[1]);
      final combined = areaA + areaB - intersection;
      union[i][j] = combined;
      iou[i][j] = combined > 0.0 ? intersection / combined : 0.0;
      final encWidth = math.max(a[2], b[2]) - math.min(a[0], b[0]);
      final encHeight = math.max(a[3], b[3]) - math.min(a[1], b[1]);
      enclosingArea[i][j] = encWidth * encHeight;
      enclosingDiagonalSquared[i][j] =
          encWidth * encWidth + encHeight * encHeight;
    }
  }
  return _Geometry(iou, union, enclosingArea, enclosingDiagonalSquared);
}

void _validateBoxes(List<List<double>> boxes, String name) {
  for (var i = 0; i < boxes.length; i++) {
    if (boxes[i].length != 4) {
      throw ArgumentError.value(
        boxes[i].length,
        '$name[$i].length',
        'Expected 4',
      );
    }
    if (boxes[i].any((value) => !value.isFinite)) {
      throw ArgumentError('$name contains non-finite values');
    }
  }
}

class _Geometry {
  final Matrix iou;
  final Matrix union;
  final Matrix enclosingArea;
  final Matrix enclosingDiagonalSquared;

  const _Geometry(
    this.iou,
    this.union,
    this.enclosingArea,
    this.enclosingDiagonalSquared,
  );
}
