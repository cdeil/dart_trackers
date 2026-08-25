import 'dart:typed_data';

/// Batch of detections in xyxy format.
///
/// The data model intentionally mirrors the small surface of
/// `supervision.Detections` used by trackers. Bounding boxes are stored as a
/// flat row-major `Float64List` with shape `[length, 4]`.
class Detections {
  final Float64List xyxy;
  final Float64List? confidence;
  final Int32List? classId;
  final Int32List? trackerId;

  new({
    required Float64List xyxy,
    this.confidence,
    this.classId,
    this.trackerId,
  }) : xyxy = Float64List.fromList(xyxy) {
    if (xyxy.length % 4 != 0) {
      throw ArgumentError.value(
        xyxy.length,
        'xyxy.length',
        'Must be a multiple of 4',
      );
    }
    final n = xyxy.length ~/ 4;
    if (confidence != null && confidence!.length != n) {
      throw ArgumentError.value(
        confidence!.length,
        'confidence.length',
        'Expected $n',
      );
    }
    if (classId != null && classId!.length != n) {
      throw ArgumentError.value(
        classId!.length,
        'classId.length',
        'Expected $n',
      );
    }
    if (trackerId != null && trackerId!.length != n) {
      throw ArgumentError.value(
        trackerId!.length,
        'trackerId.length',
        'Expected $n',
      );
    }
  }

  factory empty() => Detections(xyxy: Float64List(0));

  factory fromRows(
    List<List<num>> boxes, {
    List<num>? confidence,
    List<int>? classId,
    List<int>? trackerId,
  }) {
    final flat = Float64List(boxes.length * 4);
    for (var i = 0; i < boxes.length; i++) {
      if (boxes[i].length != 4) {
        throw ArgumentError.value(
          boxes[i].length,
          'boxes[$i].length',
          'Expected 4',
        );
      }
      for (var j = 0; j < 4; j++) {
        flat[i * 4 + j] = boxes[i][j].toDouble();
      }
    }
    return Detections(
      xyxy: flat,
      confidence: confidence == null
          ? null
          : Float64List.fromList(confidence.map((v) => v.toDouble()).toList()),
      classId: classId == null ? null : Int32List.fromList(classId),
      trackerId: trackerId == null ? null : Int32List.fromList(trackerId),
    );
  }

  int get length => xyxy.length ~/ 4;

  bool get isEmpty => length == 0;

  List<double> boxAt(int index) {
    _checkIndex(index);
    final offset = index * 4;
    return [xyxy[offset], xyxy[offset + 1], xyxy[offset + 2], xyxy[offset + 3]];
  }

  double confidenceAt(int index) {
    _checkIndex(index);
    return confidence == null ? 1.0 : confidence![index];
  }

  Detections select(List<int> indices) {
    final selectedXyxy = Float64List(indices.length * 4);
    final selectedConfidence = confidence == null
        ? null
        : Float64List(indices.length);
    final selectedClassId = classId == null ? null : Int32List(indices.length);
    final selectedTrackerId = trackerId == null
        ? null
        : Int32List(indices.length);
    for (var out = 0; out < indices.length; out++) {
      final index = indices[out];
      _checkIndex(index);
      for (var j = 0; j < 4; j++) {
        selectedXyxy[out * 4 + j] = xyxy[index * 4 + j];
      }
      if (selectedConfidence != null) {
        selectedConfidence[out] = confidence![index];
      }
      if (selectedClassId != null) {
        selectedClassId[out] = classId![index];
      }
      if (selectedTrackerId != null) {
        selectedTrackerId[out] = trackerId![index];
      }
    }
    return Detections(
      xyxy: selectedXyxy,
      confidence: selectedConfidence,
      classId: selectedClassId,
      trackerId: selectedTrackerId,
    );
  }

  Detections copyWithTrackerId(Int32List ids) {
    if (ids.length != length) {
      throw ArgumentError.value(ids.length, 'ids.length', 'Expected $length');
    }
    return Detections(
      xyxy: xyxy,
      confidence: confidence,
      classId: classId,
      trackerId: ids,
    );
  }

  List<List<double>> xyxyRows() => List.generate(length, boxAt);

  List<int>? trackerIdList() =>
      trackerId == null ? null : List<int>.from(trackerId!);

  void _checkIndex(int index) {
    if (index < 0 || index >= length) {
      throw RangeError.index(index, this, 'index', null, length);
    }
  }
}
