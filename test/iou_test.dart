import 'dart:convert';

import 'package:dart_trackers/dart_trackers.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  test('boxIou handles canonical geometry cases', () {
    expect(boxIou([0, 0, 10, 10], [0, 0, 10, 10]), equals(1.0));
    expect(boxIou([0, 0, 10, 10], [10, 10, 20, 20]), equals(0.0));
    expect(
      boxIou([0, 0, 10, 10], [5, 5, 15, 15]),
      closeTo(25.0 / 175.0, 1e-12),
    );
    expect(boxIou([0, 0, 0, 10], [0, 0, 10, 10]), equals(0.0));
  });

  test('boxIouBatch matches fixture', () {
    final fixture =
        jsonDecode(fixtureJson('iou_cases.json')) as Map<String, dynamic>;
    final boxesA = (fixture['boxes_a'] as List<dynamic>)
        .map(
          (row) =>
              (row as List<dynamic>).map((v) => (v as num).toDouble()).toList(),
        )
        .toList();
    final boxesB = (fixture['boxes_b'] as List<dynamic>)
        .map(
          (row) =>
              (row as List<dynamic>).map((v) => (v as num).toDouble()).toList(),
        )
        .toList();
    final expected = (fixture['iou_matrix'] as List<dynamic>)
        .map(
          (row) =>
              (row as List<dynamic>).map((v) => (v as num).toDouble()).toList(),
        )
        .toList();
    final actual = boxIouBatch(boxesA, boxesB);
    for (var i = 0; i < actual.rows; i++) {
      for (var j = 0; j < actual.cols; j++) {
        expect(actual[i][j], closeTo(expected[i][j], 1e-7));
      }
    }
  });

  test('IoU variants match trackers 2.6 fixtures', () {
    final fixture =
        jsonDecode(fixtureJson('iou_cases.json')) as Map<String, dynamic>;
    final boxesA = _boxes(fixture['boxes_a'] as List<dynamic>);
    final boxesB = _boxes(fixture['boxes_b'] as List<dynamic>);
    final expected = fixture['matrices'] as Map<String, dynamic>;
    final metrics = <String, BaseIoU>{
      'iou': const IoU(),
      'biou_0_3': BIoU(bufferRatio: 0.3),
      'giou': const GIoU(),
      'diou': const DIoU(),
      'ciou': const CIoU(),
    };
    for (final entry in metrics.entries) {
      final actual = entry.value.compute(boxesA, boxesB);
      final matrix = _boxes(expected[entry.key] as List<dynamic>);
      for (var i = 0; i < actual.rows; i++) {
        for (var j = 0; j < actual.cols; j++) {
          expect(
            actual[i][j],
            closeTo(matrix[i][j], 1e-7),
            reason: '${entry.key}[$i][$j]',
          );
        }
      }
    }
  });

  test('signed IoU fusion is clamped to the unit interval', () {
    final normalized = const CIoU().normalizeForFusion(
      Matrix.fromRows([
        [-2.0, -1.0, 0.0, 1.0, 2.0],
      ]),
    );
    expect(normalized.toRows().single, equals([0.0, 0.0, 0.5, 1.0, 1.0]));
  });

  test('all IoU variants reject non-finite boxes', () {
    expect(
      () => const IoU().compute(
        [
          [0, 0, double.nan, 1],
        ],
        [
          [0, 0, 1, 1],
        ],
      ),
      throwsArgumentError,
    );
  });
}

List<List<double>> _boxes(List<dynamic> rows) => rows
    .map(
      (row) => (row as List<dynamic>)
          .map((value) => (value as num).toDouble())
          .toList(),
    )
    .toList();
