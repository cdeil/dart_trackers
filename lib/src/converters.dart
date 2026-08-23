import 'dart:math' as math;

List<double> xyxyToXywh(List<double> box) {
  _validateBox(box);
  return [box[0], box[1], box[2] - box[0], box[3] - box[1]];
}

List<double> xywhToXyxy(List<double> box) {
  _validateBox(box);
  return [box[0], box[1], box[0] + box[2], box[1] + box[3]];
}

List<double> xyxyToXcycwh(List<double> box) {
  _validateBox(box);
  final width = box[2] - box[0];
  final height = box[3] - box[1];
  return [box[0] + width * 0.5, box[1] + height * 0.5, width, height];
}

List<double> xcycwhToXyxy(List<double> box) {
  _validateBox(box);
  return [
    box[0] - box[2] * 0.5,
    box[1] - box[3] * 0.5,
    box[0] + box[2] * 0.5,
    box[1] + box[3] * 0.5,
  ];
}

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
