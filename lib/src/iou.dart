import 'dart:math' as math;

import 'matrix.dart';

/// Pairwise box similarity used for association.
///
/// Boxes are `[x1, y1, x2, y2]` rows and are expected to be well formed
/// (`x1 <= x2`, `y1 <= y2`). Box extents are clamped at zero, as upstream does
/// since trackers #589, so a malformed box contributes no area: IoU and GIoU
/// score it at most `0.0`. DIoU and CIoU still subtract their center-distance
/// and aspect terms and stay unbounded below for malformed input.
///
/// Results are float64. Upstream returns float32 for [IoU] and [BIoU] (from
/// `supervision.box_iou_batch`), so those two agree with Python to about
/// `3e-8` rather than bit for bit.
abstract class BaseIoU {
  const new();

  /// Names accepted by [BaseIoU.fromName].
  static const variantNames = ['biou', 'ciou', 'diou', 'giou', 'iou'];

  /// Resolves a variant name (case-insensitive) to a default-constructed
  /// metric, like upstream `trackers.utils.iou.variant_from_name`.
  factory fromName(String name) => switch (name.toLowerCase()) {
    'iou' => const IoU(),
    'giou' => const GIoU(),
    'diou' => const DIoU(),
    'ciou' => const CIoU(),
    'biou' => BIoU(),
    _ => throw ArgumentError.value(
      name,
      'name',
      'Unknown IoU variant. Valid: $variantNames',
    ),
  };

  /// Returns the `boxesA.length x boxesB.length` similarity matrix.
  ///
  /// Throws an [ArgumentError] for rows that are not length 4 or contain
  /// non-finite values.
  Matrix compute(List<List<double>> boxesA, List<List<double>> boxesB) {
    _validateBoxes(boxesA, 'boxesA');
    _validateBoxes(boxesB, 'boxesB');
    if (boxesA.isEmpty || boxesB.isEmpty) {
      return Matrix(boxesA.length, boxesB.length);
    }
    return computeNonEmpty(boxesA, boxesB);
  }

  /// Computes the similarity for validated, non-empty inputs.
  Matrix computeNonEmpty(List<List<double>> boxesA, List<List<double>> boxesB);

  /// Maps similarities into `[0, 1]` for BoT-SORT score fusion.
  ///
  /// Identity for [IoU] and [BIoU]; signed metrics use `(x + 1) / 2` clamped
  /// to `[0, 1]`, which matters for CIoU (whose infimum is about `-1.5`).
  Matrix normalizeForFusion(Matrix similarity) => similarity;
}

/// Intersection over union.
class IoU extends BaseIoU {
  const new();

  @override
  Matrix computeNonEmpty(List<List<double>> boxesA, List<List<double>> boxesB) {
    return _pairwiseGeometry(boxesA, boxesB).iou;
  }
}

/// Buffered IoU: both boxes are expanded by [bufferRatio] of their width and
/// height on every side before computing IoU (used by C-BIoU).
class BIoU extends BaseIoU {
  final double bufferRatio;

  /// Unlike upstream, non-finite ratios are rejected as well as negative ones.
  new({this.bufferRatio = 0.1}) {
    if (bufferRatio < 0.0 || !bufferRatio.isFinite) {
      throw ArgumentError.value(bufferRatio, 'bufferRatio');
    }
  }

  @override
  Matrix computeNonEmpty(List<List<double>> boxesA, List<List<double>> boxesB) {
    if (bufferRatio == 0.0) return _pairwiseGeometry(boxesA, boxesB).iou;
    return _pairwiseGeometry(
      [for (final box in boxesA) _buffer(box)],
      [for (final box in boxesB) _buffer(box)],
    ).iou;
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
  const new();

  @override
  Matrix normalizeForFusion(Matrix similarity) {
    final result = similarity.copy();
    for (var i = 0; i < result.data.length; i++) {
      result.data[i] = ((result.data[i] + 1.0) / 2.0).clamp(0.0, 1.0);
    }
    return result;
  }
}

/// Generalized IoU (Rezatofighi et al., 2019): IoU minus the fraction of the
/// smallest enclosing box not covered by the union. Range `[-1, 1]`.
class GIoU extends _SignedIoU {
  const new();

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

/// Distance IoU (Zheng et al., 2020): IoU minus the squared center distance
/// over the squared enclosing-box diagonal. Range `[-1, 1]` for well-formed
/// boxes.
class DIoU extends _SignedIoU {
  const new();

  @override
  Matrix computeNonEmpty(List<List<double>> boxesA, List<List<double>> boxesB) {
    return _distanceIou(boxesA, boxesB, _pairwiseGeometry(boxesA, boxesB));
  }
}

/// Complete IoU (Zheng et al., 2020): DIoU minus an aspect-ratio consistency
/// penalty. Can fall below `-1` (about `-1.5` at worst for well-formed boxes).
class CIoU extends _SignedIoU {
  const new();

  @override
  Matrix computeNonEmpty(List<List<double>> boxesA, List<List<double>> boxesB) {
    final geometry = _pairwiseGeometry(boxesA, boxesB);
    final result = _distanceIou(boxesA, boxesB, geometry);
    for (var i = 0; i < boxesA.length; i++) {
      final aw = boxesA[i][2] - boxesA[i][0];
      final ah = math.max(boxesA[i][3] - boxesA[i][1], _epsilon);
      for (var j = 0; j < boxesB.length; j++) {
        final bw = boxesB[j][2] - boxesB[j][0];
        final bh = math.max(boxesB[j][3] - boxesB[j][1], _epsilon);
        final angle = math.atan(aw / ah) - math.atan(bw / bh);
        // Square first, then scale: the NumPy evaluation order upstream.
        final v = 4.0 / (math.pi * math.pi) * (angle * angle);
        final index = i * result.cols + j;
        final denominator = 1.0 - geometry.iou.data[index] + v;
        final alpha = denominator > 0.0 ? v / denominator : 0.0;
        result.data[index] -= alpha * v;
      }
    }
    return result;
  }
}

const _epsilon = 1e-7;

Matrix _distanceIou(
  List<List<double>> boxesA,
  List<List<double>> boxesB,
  _Geometry geometry,
) {
  final result = Matrix(boxesA.length, boxesB.length);
  for (var i = 0; i < boxesA.length; i++) {
    final ax = (boxesA[i][0] + boxesA[i][2]) * 0.5;
    final ay = (boxesA[i][1] + boxesA[i][3]) * 0.5;
    for (var j = 0; j < boxesB.length; j++) {
      final bx = (boxesB[j][0] + boxesB[j][2]) * 0.5;
      final by = (boxesB[j][1] + boxesB[j][3]) * 0.5;
      final dx = ax - bx;
      final dy = ay - by;
      final index = i * result.cols + j;
      result.data[index] =
          geometry.iou.data[index] -
          (dx * dx + dy * dy) /
              (geometry.enclosingDiagonalSquared.data[index] + _epsilon);
    }
  }
  return result;
}

/// IoU of two single boxes.
double boxIou(List<double> a, List<double> b) =>
    const IoU().compute([a], [b])[0][0];

/// Pairwise IoU matrix, the counterpart of `supervision.box_iou_batch`.
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
    // Extents are clamped like the intersection (upstream #589): a box
    // inverted on both axes would otherwise get a positive area and turn the
    // GIoU penalty into a bonus. No-op for well-formed boxes.
    final areaA = math.max(a[2] - a[0], 0.0) * math.max(a[3] - a[1], 0.0);
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
      final areaB = math.max(b[2] - b[0], 0.0) * math.max(b[3] - b[1], 0.0);
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

  const new(
    this.iou,
    this.union,
    this.enclosingArea,
    this.enclosingDiagonalSquared,
  );
}
