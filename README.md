# dart_trackers

Pure Dart multi-object tracking for Flutter and Dart applications.

`dart_trackers` is a Dart clone of Roboflow's Python
[`trackers`](https://trackers.roboflow.com/latest/) package. Use it when you
want SORT, ByteTrack, OC-SORT, or BoT-SORT-style object tracking inside a Dart
or Flutter app without shipping Python, Rust, OpenCV, FFI libraries, or platform
plugins.

The goal is portability and API familiarity, not replacing the Python package
for server-side workflows. The Python docs remain the best conceptual reference;
this package mirrors the tracker APIs and notes Dart-specific differences.

## Features

- Zero runtime Dart dependencies.
- Works with Dart VM, Dart AOT, Flutter mobile/desktop, and browser tests.
- `Detections` container with `xyxy`, confidence, class IDs, and tracker IDs.
- `SORTTracker`, `ByteTrackTracker`, `OCSORTTracker`, and no-CMC
    `BoTSORTTracker`.
- Python-generated conformance fixtures against `trackers==2.4.0`.
- Benchmark and validation docs for comparing Dart and Python behavior.

## Install

```yaml
dependencies:
  dart_trackers: ^0.1.0
```

For local development in this repository:

```bash
dart pub get
dart test
```

For a real Flutter integration example, see `flutter_example/`. That app is
kept outside this package because its optional mobile camera demo depends on
`ultralytics_yolo`, which is AGPL-3.0 unless separately licensed.

## Quickstart

```dart
import 'package:dart_trackers/dart_trackers.dart';

void main() {
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
  print(tracked.trackerIdList()); // [-1, -1] until tracks are confirmed.
}
```

Each tracker implements the shared `Tracker` interface:

```dart
Detections trackFrame(Tracker tracker, Detections detections) {
  return tracker.update(detections);
}
```

`update()` returns a new `Detections` object. It does not mutate the input.
Unconfirmed or unmatched detections use `trackerId = -1`.

## Choosing a tracker

| Tracker            | Use when                                                          | Python reference                                                      |
| ------------------ | ----------------------------------------------------------------- | --------------------------------------------------------------------- |
| `SORTTracker`      | You want the simplest, fastest IoU tracker.                       | [SORT](https://trackers.roboflow.com/latest/trackers/sort/)           |
| `ByteTrackTracker` | You have crowded scenes and useful low-confidence detections.     | [ByteTrack](https://trackers.roboflow.com/latest/trackers/bytetrack/) |
| `OCSORTTracker`    | Motion is non-linear or temporarily missing observations matter.  | [OC-SORT](https://trackers.roboflow.com/latest/trackers/ocsort/)      |
| `BoTSORTTracker`   | You want BoT-SORT association without camera-motion compensation. | [BoT-SORT](https://trackers.roboflow.com/latest/trackers/botsort/)    |

## Detection format

Input and output use `Detections`:

- boxes are `xyxy` rows: `[xMin, yMin, xMax, yMax]`;
- `confidence` and `classId` are optional;
- output `trackerId` is populated by the tracker.

This is intentionally similar to Python
[`supervision.Detections`](https://supervision.roboflow.com/latest/detection/core/).
The Dart package does not run detection models or process video frames; pass in
detections from your model or app code.

For video-demo tooling, the package also ships a small JSONL CLI:

```bash
dart run bin/track_json.dart \
    --tracker bytetrack \
    --detections detections.jsonl \
    --output dart_tracks.jsonl
```

## Public API notes

Most users only need:

- `Detections`;
- `Tracker`;
- one of the tracker classes.

`Matrix`, `KalmanFilter`, `linearSumAssignment`, and IoU helpers are exported for
advanced users, tests, and validation tooling. They are small support utilities,
not a general NumPy/SciPy replacement, and their surface may change before 1.0.

`BoTSORTTracker` intentionally does not implement runtime CMC. Passing `frame` to
`update()` raises `UnsupportedError`; future CMC support should be a portable
plugin boundary instead of an OpenCV dependency in the core package.

## Documentation

- [Usage guide](doc/usage.md)
- [Validation and Python conformance](doc/validation.md)
- [Benchmarks](doc/benchmarks.md)
- [Web support](doc/web.md)
- [Demo video comparison plan](doc/demo_video_comparison.md)
- [Design notes](doc/design.md)
- [Spike review](doc/review.md)

## Development

```bash
dart format --output=none --set-exit-if-changed bin example lib test tool
dart analyze --fatal-infos --fatal-warnings
dart test
dart test -p chrome
dart pub publish --dry-run
```

Regenerate Python reference fixtures with uv from the locked Python 3.14
environment:

```bash
cd conformance/python
uv run python generate_fixtures.py
uv run ruff format --check .
uv run ruff check .
uv run ty check .
```
