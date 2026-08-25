import 'package:dart_trackers/dart_trackers.dart';
import 'package:test/test.dart';

void main() {
  test('dynamic timing skips backwards updates without mutating tracks', () {
    final warnings = <String>[];
    final tracker = ByteTrackTracker(
      minimumConsecutiveFrames: 1,
      minimumIouThreshold: 0.1,
      onWarning: warnings.add,
    );
    final first = tracker.update(_detection(0), timestamp: 10.0);
    final confirmed = tracker.update(_detection(0), timestamp: 10.0);
    final skipped = tracker.update(_detection(100), timestamp: 9.0);

    expect(first.trackerIdList(), equals([-1]));
    expect(confirmed.trackerIdList(), equals([0]));
    expect(skipped.trackerIdList(), equals([-1]));
    expect(tracker.trackedObjects.trackerIdList(), equals([0]));
    expect(warnings, hasLength(2));
  });

  test('dynamic timing prunes expired tracks before association', () {
    final tracker = ByteTrackTracker(
      lostTrackBuffer: 1,
      minimumConsecutiveFrames: 1,
      minimumIouThreshold: 0.1,
    );
    tracker.update(_detection(0), timestamp: 0.0);
    expect(tracker.update(_detection(0), timestamp: 1 / 30).trackerIdList(), [
      0,
    ]);
    expect(tracker.update(_detection(0), timestamp: 1.0).trackerIdList(), [-1]);
  });

  test('zero lost buffer and non-finite frame rates are validated', () {
    expect(
      SORTTracker(lostTrackBuffer: 0).maximumFramesWithoutUpdate,
      equals(0),
    );
    expect(() => SORTTracker(frameRate: double.nan), throwsArgumentError);
    expect(() => SORTTracker(frameRate: double.infinity), throwsArgumentError);
    expect(() => SORTTracker(lostTrackBuffer: -1), throwsArgumentError);
  });

  test('gap-aware motion scales constant-velocity prediction', () {
    final tracklet = SORTTracklet([0, 0, 10, 10]);
    tracklet.kf.x[4][0] = 2.0;
    tracklet.predict(
      const PredictTiming(
        frameStep: 2.0,
        elapsedSeconds: 2 / 30,
        frameRate: 30,
      ),
    );
    expect(tracklet.getStateBbox()[0], closeTo(4.0, 1e-12));
    expect(tracklet.timeSinceUpdateSeconds, closeTo(2 / 30, 1e-12));
  });

  test('trackedObjects retains confirmed missed tracks through the budget', () {
    final tracker = SORTTracker(
      lostTrackBuffer: 2,
      minimumConsecutiveFrames: 1,
      minimumIouThreshold: 0.1,
    );
    tracker.update(_detection(0));
    tracker.update(_detection(0));
    tracker.update(Detections.empty());
    expect(tracker.trackedObjects.trackerIdList(), equals([0]));
    tracker.update(Detections.empty());
    expect(tracker.trackedObjects.trackerIdList(), equals([0]));
    tracker.update(Detections.empty());
    expect(tracker.trackedObjects, isEmpty);
  });
}

Detections _detection(double x) => Detections.fromRows(
  [
    [x, 0, x + 10, 10],
  ],
  confidence: [0.9],
);
