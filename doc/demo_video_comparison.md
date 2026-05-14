# Demo video comparison plan

The release package should include visual demos that compare Python `trackers`
and Dart `dart_trackers` on the same real-world videos.

## Recommended architecture

Keep all video and detection work on the Python side:

1. Python downloads or opens the same demo videos used in the Python trackers
    docs.
2. Python runs the detector and writes per-frame detections to JSONL.
3. Python runs the Python tracker and writes per-frame tracks to JSONL.
4. Dart CLI reads the detection JSONL and writes Dart tracks to JSONL.
5. Python renders comparison videos from both JSONL files.

This keeps Dart focused on the tracking core and avoids adding image/video
dependencies to the package.

## Visual comparison overlay

Render one video with:

- Python tracks as solid boxes;
- Dart tracks as dashed boxes;
- matching track IDs in the same color;
- mismatched boxes or IDs highlighted in red;
- a small per-frame summary: matched IDs, missing IDs, extra IDs, mean IoU.

For side-by-side debugging, also render a two-panel video:

- left: Python tracker output;
- right: Dart tracker output.

## Proposed CLI boundary

The package includes a minimal Dart JSONL tracker command:

```bash
dart run bin/track_json.dart \
    --tracker bytetrack \
    --detections detections.jsonl \
    --output dart_tracks.jsonl
```

After installing the package globally or from pub, the executable name is:

```bash
dart_trackers_track_json \
    --tracker bytetrack \
    --detections detections.jsonl \
    --output dart_tracks.jsonl
```

JSONL keeps the interface language-neutral:

```json
{
  "frame": 0,
  "xyxy": [
    [
      100,
      120,
      180,
      260
    ]
  ],
  "confidence": [
    0.92
  ],
  "class_id": [
    0
  ]
}
```

Output:

```json
{
  "frame": 0,
  "xyxy": [
    [
      100,
      120,
      180,
      260
    ]
  ],
  "tracker_id": [
    -1
  ],
  "class_id": [
    0
  ]
}
```

## Packaging note

Do not include generated `.mp4` files in the pub.dev package tarball. Host them
as GitHub release assets, documentation site assets, or CI artifacts. `.pubignore`
excludes common video formats and `doc/demo/artifacts/`.

## Flutter example

The repository also contains `flutter_example/`, a separate Flutter app that
shows `dart_trackers` inside a mobile/web UI:

- a cross-platform demo-video tab using the Python demo video URLs plus
    deterministic sample detections;
- an Android/iOS camera tab that uses `ultralytics_yolo` for detection and
    `ByteTrackTracker` for tracking.

The Flutter example is intentionally not part of the pub.dev package because the
Ultralytics plugin is AGPL-3.0 unless separately licensed.
