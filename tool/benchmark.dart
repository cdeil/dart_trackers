import 'dart:convert';
import 'dart:io';

import 'package:dart_trackers/dart_trackers.dart';

void main(List<String> args) {
  final frames = _intArg(args, '--frames', 500);
  final objects = _intArg(args, '--objects', 20);
  final repeats = _intArg(args, '--repeats', 5);
  final benchmarkFrames = _makeFrames(frames, objects);

  final results = [
    _runBenchmark(
      'sort',
      () => SORTTracker(minimumConsecutiveFrames: 1),
      benchmarkFrames,
      repeats,
    ),
    _runBenchmark(
      'bytetrack',
      () => ByteTrackTracker(
        minimumConsecutiveFrames: 1,
        trackActivationThreshold: 0.5,
        highConfDetThreshold: 0.6,
      ),
      benchmarkFrames,
      repeats,
    ),
    _runBenchmark(
      'ocsort',
      () =>
          OCSORTTracker(minimumConsecutiveFrames: 1, minimumIouThreshold: 0.1),
      benchmarkFrames,
      repeats,
    ),
    _runBenchmark(
      'botsort',
      () => BoTSORTTracker(
        minimumConsecutiveFrames: 1,
        minimumIouThresholdFirstAssoc: 0.1,
        minimumIouThresholdSecondAssoc: 0.1,
      ),
      benchmarkFrames,
      repeats,
    ),
  ];

  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'runtime': 'dart',
      'frames': frames,
      'objects': objects,
      'repeats': repeats,
      'results': results,
    }),
  );
}

Map<String, Object> _runBenchmark(
  String trackerName,
  Tracker Function() trackerFactory,
  List<Detections> frames,
  int repeats,
) {
  // Warm up JIT and caches outside the measured loop.
  _runTracker(trackerFactory(), frames.take(50));

  final totalMicroseconds = <int>[];
  var outputs = 0;
  final rssBefore = ProcessInfo.currentRss;
  for (var i = 0; i < repeats; i++) {
    final stopwatch = Stopwatch()..start();
    outputs = _runTracker(trackerFactory(), frames);
    stopwatch.stop();
    totalMicroseconds.add(stopwatch.elapsedMicroseconds);
  }
  final rssAfter = ProcessInfo.currentRss;
  totalMicroseconds.sort();
  final medianUs = totalMicroseconds[totalMicroseconds.length ~/ 2];
  final p95Us =
      totalMicroseconds[((totalMicroseconds.length - 1) * 0.95).round()];

  return {
    'tracker': trackerName,
    'median_total_ms': medianUs / 1000.0,
    'median_update_us': medianUs / frames.length,
    'p95_update_us': p95Us / frames.length,
    'run_update_us': [
      for (final elapsed in totalMicroseconds) elapsed / frames.length,
    ],
    'rss_before_bytes': rssBefore,
    'rss_after_bytes': rssAfter,
    'rss_delta_bytes': rssAfter - rssBefore,
    'output_rows': outputs,
  };
}

int _runTracker(Tracker tracker, Iterable<Detections> frames) {
  var outputs = 0;
  for (final detections in frames) {
    final result = tracker.update(detections);
    outputs += result.length;
  }
  return outputs;
}

List<Detections> _makeFrames(int frames, int objects) {
  return List.generate(frames, (frameIndex) {
    final boxes = <List<num>>[];
    final confidence = <num>[];
    final classId = <int>[];
    for (var objectIndex = 0; objectIndex < objects; objectIndex++) {
      final x = 20.0 + objectIndex * 35.0 + frameIndex * 0.7;
      final y = 30.0 + (objectIndex % 5) * 45.0 + frameIndex * 0.2;
      final w = 20.0 + (objectIndex % 3) * 3.0;
      final h = 30.0 + (objectIndex % 4) * 2.0;
      boxes.add([x, y, x + w, y + h]);
      confidence.add(frameIndex > 3 && frameIndex % 7 == 0 ? 0.3 : 0.95);
      classId.add(objectIndex % 4);
    }
    return Detections.fromRows(boxes, confidence: confidence, classId: classId);
  });
}

int _intArg(List<String> args, String name, int defaultValue) {
  final index = args.indexOf(name);
  if (index == -1) return defaultValue;
  if (index + 1 >= args.length) {
    throw ArgumentError('Missing value for $name');
  }
  return int.parse(args[index + 1]);
}
