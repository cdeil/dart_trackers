import 'dart:convert';

import 'package:dart_trackers/dart_trackers.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  test('SORT XYXY Kalman state matches Python fixture', () {
    final fixture =
        jsonDecode(fixtureJson('kalman_sort_xyxy.json'))
            as Map<String, dynamic>;
    final initial = (fixture['initial_bbox'] as List<dynamic>)
        .map((v) => (v as num).toDouble())
        .toList();
    final tracklet = SORTTracklet(initial);

    for (final rawStep in fixture['steps'] as List<dynamic>) {
      final step = rawStep as Map<String, dynamic>;
      tracklet.predict();
      final predicted = tracklet.getStateBbox();
      final expectedPredicted = (step['predicted_bbox'] as List<dynamic>)
          .map((v) => (v as num).toDouble())
          .toList();
      for (var i = 0; i < 4; i++) {
        expect(predicted[i], closeTo(expectedPredicted[i], 1e-9));
      }

      final update = (step['update_bbox'] as List<dynamic>)
          .map((v) => (v as num).toDouble())
          .toList();
      tracklet.update(update);
      final expectedState = (step['state'] as List<dynamic>)
          .map((v) => (v as num).toDouble())
          .toList();
      final actualState = tracklet.kf.x.columnToList();
      for (var i = 0; i < actualState.length; i++) {
        expect(actualState[i], closeTo(expectedState[i], 1e-9));
      }
    }
  });
}
