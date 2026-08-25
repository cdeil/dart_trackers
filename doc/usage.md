# Usage guide

`dart_trackers` is a pure-Dart clone of Roboflow's Python
[`trackers`](https://trackers.roboflow.com/latest/) package. It exists so Dart
and Flutter applications can run multi-object tracking locally after a detection
model has produced bounding boxes.

The package does not include video I/O, image decoding, model inference, or UI
widgets. In Flutter, run your detector however you prefer, convert detections to
`Detections`, then call `tracker.update()`.

## Basic API

```dart
import 'package:dart_trackers/dart_trackers.dart';

final tracker = ByteTrackTracker();

final detections = Detections.fromRows(
  [
    [100, 120, 180, 260],
    [260, 110, 330, 250],
  ],
  confidence: [0.92, 0.81],
  classId: [0, 0],
);

final tracked = tracker.update(detections);
final ids = tracked.trackerIdList();
```

The returned `Detections` contains the same detection data plus `trackerId`.
Unconfirmed or unmatched detections are `-1`.

## Tracker interface

All trackers implement `Tracker`:

```dart
Detections updateTracker(Tracker tracker, Detections detections) {
  return tracker.update(detections);
}
```

Available trackers:

- `SORTTracker`
- `ByteTrackTracker`
- `OCSORTTracker`
- `BoTSORTTracker`
- `CBIoUTracker`

Pass absolute capture times when frame delivery is irregular:

```dart
final tracked = tracker.update(detections, timestamp: captureTimeSeconds);
final aliveIncludingMisses = tracker.trackedObjects;
```

For BoT-SORT camera compensation, provide a `CameraMotionCompensator` that
estimates a 2x3 affine transform in your native or Flutter image stack. The
portable package applies the transform but does not ship an image runtime.

The Python tracker comparison is a useful conceptual guide:
https://trackers.roboflow.com/latest/trackers/comparison/

## Choosing parameters

The main parameters intentionally use Dart-style camelCase names but mirror the
Python package:

| Dart parameter             | Python parameter             | Meaning                                           |
| -------------------------- | ---------------------------- | ------------------------------------------------- |
| `lostTrackBuffer`          | `lost_track_buffer`          | Frames to keep a lost track alive.                |
| `trackActivationThreshold` | `track_activation_threshold` | Minimum confidence to spawn a new track.          |
| `minimumConsecutiveFrames` | `minimum_consecutive_frames` | Successful updates before a stable ID is emitted. |
| `minimumIouThreshold`      | `minimum_iou_threshold`      | Minimum IoU for SORT/ByteTrack association.       |
| `highConfDetThreshold`     | `high_conf_det_threshold`    | High/low split for ByteTrack and BoT-SORT.        |

See the Python docs for deeper algorithm explanations:

- SORT: https://trackers.roboflow.com/latest/trackers/sort/
- ByteTrack: https://trackers.roboflow.com/latest/trackers/bytetrack/
- OC-SORT: https://trackers.roboflow.com/latest/trackers/ocsort/
- BoT-SORT: https://trackers.roboflow.com/latest/trackers/botsort/
- C-BIoU: https://trackers.roboflow.com/latest/trackers/cbiou/
- State estimators: https://trackers.roboflow.com/latest/learn/state-estimators/

## Flutter integration pattern

Keep tracker state outside your widget build method:

```dart
class TrackingController {
  final Tracker tracker = ByteTrackTracker();

  Detections processFrame(List<List<num>> boxes, List<num> scores) {
    final detections = Detections.fromRows(boxes, confidence: scores);
    return tracker.update(detections);
  }

  void resetVideo() {
    tracker.reset();
  }
}
```

Call `reset()` when switching videos, camera streams, or scenes.

## Advanced exports

`Matrix`, `KalmanFilter`, `PredictTiming`, converters,
`linearSumAssignment`, and the IoU metric family are exported for tests,
validation tooling, and advanced integrations. They are small tracker support
utilities, not a general numerical-computing API.
