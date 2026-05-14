import 'dart:convert';
import 'dart:io';

import 'package:dart_trackers/dart_trackers.dart';

Future<void> main(List<String> args) async {
  final trackerName = _arg(args, '--tracker', 'bytetrack')!;
  final inputPath = _requiredArg(args, '--detections');
  final outputPath = _requiredArg(args, '--output');
  final tracker = _tracker(trackerName);

  final input = File(inputPath);
  final output = File(outputPath).openWrite();
  try {
    for (final line in input.readAsLinesSync()) {
      if (line.trim().isEmpty) continue;
      final frame = jsonDecode(line) as Map<String, dynamic>;
      final detections = _detectionsFromJson(frame);
      final tracked = tracker.update(detections);
      output.writeln(jsonEncode(_trackedFrameToJson(frame, tracked)));
    }
  } finally {
    await output.close();
  }
}

Tracker _tracker(String name) {
  return switch (name) {
    'sort' => SORTTracker(),
    'bytetrack' => ByteTrackTracker(),
    'ocsort' => OCSORTTracker(),
    'botsort' => BoTSORTTracker(),
    _ => throw ArgumentError.value(
      name,
      '--tracker',
      'Expected sort, bytetrack, ocsort, or botsort',
    ),
  };
}

Detections _detectionsFromJson(Map<String, dynamic> frame) {
  final boxes = (frame['xyxy'] as List<dynamic>? ?? const [])
      .map((row) => (row as List<dynamic>).map((v) => v as num).toList())
      .toList();
  final confidence = (frame['confidence'] as List<dynamic>?)
      ?.map((v) => v as num)
      .toList();
  final classId = (frame['class_id'] as List<dynamic>?)?.cast<int>();
  return Detections.fromRows(boxes, confidence: confidence, classId: classId);
}

Map<String, Object?> _trackedFrameToJson(
  Map<String, dynamic> input,
  Detections tracked,
) {
  return {
    'frame': input['frame'],
    'xyxy': tracked.xyxyRows(),
    'confidence': tracked.confidence == null
        ? null
        : [for (var i = 0; i < tracked.length; i++) tracked.confidenceAt(i)],
    'class_id': tracked.classId?.toList(),
    'tracker_id': tracked.trackerIdList() ?? <int>[],
  };
}

String _requiredArg(List<String> args, String name) {
  final value = _arg(args, name, null);
  if (value == null) {
    throw ArgumentError('Missing required argument $name');
  }
  return value;
}

String? _arg(List<String> args, String name, String? defaultValue) {
  final index = args.indexOf(name);
  if (index == -1) return defaultValue;
  if (index + 1 >= args.length) {
    throw ArgumentError('Missing value for $name');
  }
  return args[index + 1];
}
