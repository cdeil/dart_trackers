import 'dart:convert';

import 'package:dart_trackers/dart_trackers.dart';
import 'package:test/test.dart';

import 'conformance_harness.dart';
import 'fixtures.dart';

void main() {
  group('linearSumAssignment matches SciPy', () {
    final cases =
        jsonDecode(fixtureJson('assignment_cases.json')) as List<dynamic>;
    for (final rawCase in cases) {
      final testCase = rawCase as Map<String, dynamic>;
      test(testCase['name'] as String, () {
        final matrix = Matrix.fromRows(
          parseRows(testCase['cost_matrix'] as List<dynamic>),
        );
        final maximize = testCase['maximize'] as bool? ?? false;
        if (testCase.containsKey('error')) {
          expect(
            () => linearSumAssignment(matrix, maximize: maximize),
            throwsArgumentError,
          );
          return;
        }
        final result = linearSumAssignment(matrix, maximize: maximize);
        expect(
          result.rowIndices,
          equals((testCase['row_indices'] as List<dynamic>).cast<int>()),
        );
        expect(
          result.colIndices,
          equals((testCase['col_indices'] as List<dynamic>).cast<int>()),
        );
      });
    }
  });
}
