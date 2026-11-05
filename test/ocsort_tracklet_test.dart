import 'package:dart_trackers/dart_trackers.dart';
import 'package:test/test.dart';

void main() {
  test('observations are pruned to the deltaT window', () {
    final tracklet = OCSORTTracklet([0, 0, 10, 10], deltaT: 3);
    for (var i = 0; i < 50; i++) {
      tracklet.predict();
      tracklet.update([i + 1.0, 0, i + 11.0, 10]);
    }
    expect(tracklet.observations.keys.toList()..sort(), [47, 48, 49, 50]);
  });

  test('predict returns the decoded predicted box', () {
    final tracklet = OCSORTTracklet([0, 0, 10, 10], deltaT: 3);
    expect(tracklet.predict(), equals(tracklet.getStateBbox()));
  });

  test('ORU keeps the configured one-frame process noise after a gap', () {
    final tracklet = OCSORTTracklet([0, 0, 10, 10], deltaT: 3);
    final baseline = tracklet.motionModel.processNoise.build(1.0).data;
    const gap = PredictTiming(
      frameStep: 3.0,
      elapsedSeconds: 0.1,
      frameRate: 30.0,
    );
    const nominal = PredictTiming(
      frameStep: 1.0,
      elapsedSeconds: 1 / 30,
      frameRate: 30.0,
    );
    tracklet.predict(nominal);
    tracklet.update([1, 0, 11, 10], nominal);
    tracklet.predict(gap); // unmatched: the frozen Q is gap-scaled
    tracklet.predict(nominal);
    tracklet.update([6, 0, 16, 10], gap);
    expect(tracklet.motionModel.processNoise.build(1.0).data, baseline);
  });
}
