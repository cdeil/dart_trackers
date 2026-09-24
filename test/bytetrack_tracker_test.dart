import 'package:dart_trackers/dart_trackers.dart';
import 'package:test/test.dart';

import 'conformance_harness.dart';

void main() {
  group('ByteTrackTracker conformance', () {
    runTrackerConformance('bytetrack_cases.json', byteTrackFromParams);
  });

  test(
    'ByteTrackTracklet consecutive counter resets on second missed predict',
    () {
      final tracklet = ByteTrackTracklet([0, 0, 10, 10]);
      expect(tracklet.numberOfSuccessfulConsecutiveUpdates, equals(1));

      tracklet.predict();
      expect(tracklet.timeSinceUpdate, equals(1));
      expect(tracklet.numberOfSuccessfulConsecutiveUpdates, equals(1));

      tracklet.predict();
      expect(tracklet.timeSinceUpdate, equals(2));
      expect(tracklet.numberOfSuccessfulConsecutiveUpdates, equals(0));
    },
  );
}
