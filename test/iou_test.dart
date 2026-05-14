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
}
