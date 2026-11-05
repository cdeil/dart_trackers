import 'dart:typed_data';

import 'package:dart_trackers/dart_trackers.dart';
import 'package:test/test.dart';

void main() {
  Detections sample() => Detections.fromRows(
    [
      [0, 0, 10, 10],
      [5, 5, 15, 15],
      [20, 20, 30, 30],
    ],
    confidence: [0.9, 0.5, 0.1],
    classId: [1, 2, 3],
  );

  test('validates shapes', () {
    expect(() => Detections(xyxy: Float64List(3)), throwsArgumentError);
    expect(
      () => Detections(xyxy: Float64List(8), confidence: Float64List(1)),
      throwsArgumentError,
    );
    expect(
      () => Detections.fromRows([
        [0, 0, 1],
      ]),
      throwsArgumentError,
    );
  });

  test('empty has no metadata', () {
    final empty = Detections.empty();
    expect(empty.isEmpty, isTrue);
    expect(empty.confidence, isNull);
    expect(empty.classId, isNull);
    expect(empty.trackerId, isNull);
  });

  test('select reorders, duplicates, and bounds-checks rows', () {
    final selected = sample().select([2, 0, 0]);
    expect(selected.xyxyRows(), [
      [20.0, 20.0, 30.0, 30.0],
      [0.0, 0.0, 10.0, 10.0],
      [0.0, 0.0, 10.0, 10.0],
    ]);
    expect(selected.confidence, [0.1, 0.9, 0.9]);
    expect(selected.classId, [3, 1, 1]);
    expect(() => sample().select([3]), throwsRangeError);
  });

  test('missing confidence reads as 1.0', () {
    final detections = Detections.fromRows([
      [0, 0, 1, 1],
    ]);
    expect(detections.confidenceAt(0), 1.0);
  });

  test('copies never share storage with their source', () {
    final confidence = Float64List.fromList([0.5]);
    final detections = Detections(
      xyxy: Float64List.fromList([0, 0, 1, 1]),
      confidence: confidence,
    );
    confidence[0] = 0.0;
    expect(detections.confidence, [0.5]);

    final ids = Int32List.fromList([7]);
    final withIds = detections.copyWithTrackerId(ids);
    ids[0] = 0;
    withIds.confidence![0] = 0.25;
    expect(withIds.trackerId, [7]);
    expect(detections.confidence, [0.5]);
    expect(
      () => detections.copyWithTrackerId(Int32List(2)),
      throwsArgumentError,
    );
  });

  test('tracker output does not alias input metadata', () {
    final input = sample();
    final output = SORTTracker(minimumConsecutiveFrames: 1).update(input);
    output.confidence![0] = 0.0;
    expect(input.confidence, [0.9, 0.5, 0.1]);
    expect(input.trackerId, isNull);
  });
}
