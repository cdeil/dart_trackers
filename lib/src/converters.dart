import 'dart:math' as math;

/// `[x1, y1, x2, y2]` to top-left `[x, y, w, h]` (supervision's `xywh`).
///
/// Upstream trackers' `xyxy_to_xywh` is center-based; see [xyxyToXcycwh].
List<double> xyxyToXywh(List<double> box) {
  _validateBox(box);
  return [box[0], box[1], box[2] - box[0], box[3] - box[1]];
}

/// Top-left `[x, y, w, h]` to `[x1, y1, x2, y2]`.
List<double> xywhToXyxy(List<double> box) {
  _validateBox(box);
  return [box[0], box[1], box[0] + box[2], box[1] + box[3]];
}

/// `[x1, y1, x2, y2]` to center `[xc, yc, w, h]` (BoT-SORT state layout;
/// upstream trackers' `xyxy_to_xywh`).
List<double> xyxyToXcycwh(List<double> box) {
  _validateBox(box);
  final width = box[2] - box[0];
  final height = box[3] - box[1];
  return [box[0] + width * 0.5, box[1] + height * 0.5, width, height];
}

/// Center `[xc, yc, w, h]` to `[x1, y1, x2, y2]`.
List<double> xcycwhToXyxy(List<double> box) {
  _validateBox(box);
  return [
    box[0] - box[2] * 0.5,
    box[1] - box[3] * 0.5,
    box[0] + box[2] * 0.5,
    box[1] + box[3] * 0.5,
  ];
}

/// `[x1, y1, x2, y2]` to `[xc, yc, s, r]` with area `s = w * h` and aspect
/// ratio `r = w / (h + 1e-6)` (OC-SORT state layout).
List<double> xyxyToXcycsr(List<double> box) {
  _validateBox(box);
  final width = box[2] - box[0];
  final height = box[3] - box[1];
  return [
    box[0] + width * 0.5,
    box[1] + height * 0.5,
    width * height,
    width / (height + 1e-6),
  ];
}

/// `[xc, yc, s, r]` to `[x1, y1, x2, y2]`.
///
/// A negative `s * r` decodes to a zero-size box at the center (upstream
/// returns NaN there); a zero width yields zero height instead of NaN.
List<double> xcycsrToXyxy(List<double> box) {
  _validateBox(box);
  final product = math.max(box[2] * box[3], 0.0);
  final width = math.sqrt(product);
  final height = width > 0.0 ? box[2] / width : 0.0;
  return [
    box[0] - width * 0.5,
    box[1] - height * 0.5,
    box[0] + width * 0.5,
    box[1] + height * 0.5,
  ];
}

void _validateBox(List<double> box) {
  if (box.length != 4) {
    throw ArgumentError.value(box.length, 'box.length', 'Expected 4');
  }
}
