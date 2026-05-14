import 'dart:convert';

import 'package:dart_trackers/dart_trackers.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('linearSumAssignment', () {
    final cases = _loadJsonList('assignment_cases.json');
    for (final rawCase in cases) {
      final testCase = rawCase as Map<String, dynamic>;
      test(testCase['name'] as String, () {
        final matrix = Matrix.fromRows(
          (testCase['cost_matrix'] as List<dynamic>)
              .map((row) => (row as List<dynamic>).cast<num>())
              .toList(),
        );
        final result = linearSumAssignment(
          matrix,
          maximize: testCase['maximize'] as bool? ?? false,
        );
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

List<dynamic> _loadJsonList(String path) {
  return jsonDecode(fixtureJson(path)) as List<dynamic>;
}
