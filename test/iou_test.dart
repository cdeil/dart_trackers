import 'dart:convert';

import 'package:dart_trackers/dart_trackers.dart';
import 'package:test/test.dart';

import 'conformance_harness.dart';
import 'fixtures.dart';

final _metrics = <String, BaseIoU>{
  'iou': const IoU(),
  'biou_0_3': BIoU(bufferRatio: 0.3),
  'giou': const GIoU(),
  'diou': const DIoU(),
  'ciou': const CIoU(),
};

void main() {
  final fixture =
      jsonDecode(fixtureJson('iou_cases.json')) as Map<String, dynamic>;

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
    final actual = boxIouBatch(
      parseRows(fixture['boxes_a'] as List<dynamic>),
      parseRows(fixture['boxes_b'] as List<dynamic>),
    );
    _expectMatrix(actual, fixture['iou_matrix'] as List<dynamic>, 'iou');
  });

  group('IoU variants match the Python oracle', () {
    for (final rawBatch in fixture['batches'] as List<dynamic>) {
      final batch = rawBatch as Map<String, dynamic>;
      test(batch['name'] as String, () {
        final boxesA = parseRows(batch['boxes_a'] as List<dynamic>);
        final boxesB = parseRows(batch['boxes_b'] as List<dynamic>);
        final matrices = batch['matrices'] as Map<String, dynamic>;
        final fused = batch['fused'] as Map<String, dynamic>;
        for (final entry in _metrics.entries) {
          final actual = entry.value.compute(boxesA, boxesB);
          _expectMatrix(
            actual,
            matrices[entry.key] as List<dynamic>,
            entry.key,
          );
          _expectMatrix(
            entry.value.normalizeForFusion(actual),
            fused[entry.key] as List<dynamic>,
            '${entry.key} fused',
          );
        }
      });
    }
  });

  test('malformed boxes never score above zero', () {
    final malformed = [
      [10.0, 0.0, 0.0, 10.0],
      [0.0, 10.0, 10.0, 0.0],
      [10.0, 10.0, 0.0, 0.0],
    ];
    final wellFormed = [
      [0.0, 0.0, 10.0, 10.0],
    ];
    for (final entry in _metrics.entries) {
      final matrix = entry.value.compute(malformed, wellFormed);
      for (final value in matrix.data) {
        expect(value, lessThanOrEqualTo(0.0), reason: entry.key);
      }
    }
    final giou = const GIoU().compute(malformed, wellFormed);
    expect(giou.data, everyElement(equals(0.0)));
  });

  test('signed metrics are symmetric and bounded by IoU', () {
    final batch = (fixture['batches'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .firstWhere((batch) => batch['name'] == 'random_non_integer');
    final boxesA = parseRows(batch['boxes_a'] as List<dynamic>);
    final boxesB = parseRows(batch['boxes_b'] as List<dynamic>);
    final iou = const IoU().compute(boxesA, boxesB);
    final diou = const DIoU().compute(boxesA, boxesB);
    for (final metric in [const GIoU(), const DIoU(), const CIoU()]) {
      final forward = metric.compute(boxesA, boxesB);
      final backward = metric.compute(boxesB, boxesA).transpose();
      for (var i = 0; i < forward.data.length; i++) {
        expect(forward.data[i], closeTo(backward.data[i], 1e-12));
        expect(forward.data[i], lessThanOrEqualTo(iou.data[i] + 1e-12));
      }
    }
    final ciou = const CIoU().compute(boxesA, boxesB);
    for (var i = 0; i < ciou.data.length; i++) {
      expect(ciou.data[i], lessThanOrEqualTo(diou.data[i] + 1e-12));
    }
  });

  test('empty inputs return correctly shaped matrices', () {
    final boxes = [
      [0.0, 0.0, 1.0, 1.0],
      [1.0, 1.0, 2.0, 2.0],
    ];
    for (final metric in _metrics.values) {
      expect(metric.compute(const [], boxes).rows, 0);
      expect(metric.compute(const [], boxes).cols, 2);
      expect(metric.compute(boxes, const []).rows, 2);
      expect(metric.compute(boxes, const []).cols, 0);
    }
  });

  test('every variant rejects non-finite boxes', () {
    for (final metric in _metrics.values) {
      for (final bad in [double.nan, double.infinity]) {
        expect(
          () => metric.compute(
            [
              [0, 0, bad, 1],
            ],
            [
              [0, 0, 1, 1],
            ],
          ),
          throwsArgumentError,
        );
      }
    }
  });

  test('BIoU validates its ratio and reduces to IoU at zero', () {
    expect(() => BIoU(bufferRatio: -0.01), throwsArgumentError);
    final boxesA = parseRows(fixture['boxes_a'] as List<dynamic>);
    final boxesB = parseRows(fixture['boxes_b'] as List<dynamic>);
    expect(
      BIoU(bufferRatio: 0.0).compute(boxesA, boxesB).data,
      equals(const IoU().compute(boxesA, boxesB).data),
    );
  });

  test('BaseIoU.fromName resolves variants case-insensitively', () {
    expect(BaseIoU.fromName('iou'), isA<IoU>());
    expect(BaseIoU.fromName('GIoU'), isA<GIoU>());
    expect(BaseIoU.fromName('DiOU'), isA<DIoU>());
    expect(BaseIoU.fromName('ciou'), isA<CIoU>());
    expect(BaseIoU.fromName('BIOU'), isA<BIoU>());
    for (final name in ['', 'foo', 'wiou', 'iou2']) {
      expect(() => BaseIoU.fromName(name), throwsArgumentError);
    }
  });
}

void _expectMatrix(Matrix actual, List<dynamic> expectedRows, String label) {
  final expected = parseRows(expectedRows);
  expect(actual.rows, expected.length, reason: label);
  for (var i = 0; i < actual.rows; i++) {
    for (var j = 0; j < actual.cols; j++) {
      expect(
        actual[i][j],
        closeTo(expected[i][j], 1e-7),
        reason: '$label[$i][$j]',
      );
    }
  }
}
