# Dart trackers implementation record

> The original 2.4 spike described below was completed and superseded by the
> 0.2 parity update. Current design and validation live in `design.md` and
> `validation.md`.

## 0.2 completion

- Upgraded the oracle to `trackers==2.6.0` and `supervision==0.29.0`.
- Added the complete portable IoU family and C-BIoU.
- Added timestamp-aware Kalman prediction and wall-clock lifecycle handling.
- Added `trackedObjects`, strict validation, output-contract fixes, and the
  post-2.6 OC-SORT low-confidence result behavior.
- Implemented affine state application behind the portable CMC seam.
- Retained McByte's Torch/SAM/Cutie mask stack as the documented GPU-runtime
  boundary.

## Goal

Create a self-contained pure Dart spike for the core `trackers` package and use
it to evaluate whether a Dart clone is practical before investing in CMC or
Rust/FFI packaging.

## Recommended approach

Build the package around deterministic, minimal primitives rather than a general
scientific-computing layer.

- Use `Float64List` and a small row-major `Matrix`.
- Avoid a generic `NDArray`.
- Keep the package pure Dart and non-Flutter.
- Use Python-generated fixtures as the conformance oracle.
- Implement each tracker as a complete fixture-backed slice before adding the
    next tracker.
- Keep CMC as an abstract seam only.

## Completed spike deliverables

1. Standalone Dart package in `dart_trackers`.
2. Public barrel export in `lib/dart_trackers.dart`.
3. Core primitives:
    - `Detections`;
    - `Matrix`;
    - `KalmanFilter`;
    - IoU;
    - SciPy-style rectangular assignment.
4. SORT implementation:
    - XYXY Kalman state;
    - IoU assignment;
    - per-instance ID allocation;
    - no input mutation;
    - missing confidence defaults to `1.0`.
5. ByteTrack implementation:
    - two-stage high/low confidence association;
    - installed-Python behavior for absent confidence as zeros;
    - fixture-backed output-order checks.
6. OC-SORT implementation:
    - XCYCSR Kalman state;
    - direction consistency;
    - ORU freeze/unfreeze replay;
    - OCR second-chance matching.
7. BoT-SORT implementation without CMC:
    - XCYCWH Kalman state;
    - scale-aware noise;
    - score-fused first and unconfirmed association;
    - high/low/discard confidence split.
8. Conformance setup:
    - Python generator in `conformance/python/generate_fixtures.py`;
    - fixture environment in `conformance/python/pyproject.toml`;
    - checked-in JSON fixtures under `conformance/fixtures`;
    - Dart tests loading those fixtures.
9. Documentation:
    - v3 design;
    - this plan;
    - spike review.
10. Pub.dev-readiness:
    - package README and metadata;
    - GitHub Actions for Dart CI and publishing;
    - JSONL CLI boundary for Python-driven visual comparisons;
    - browser-safe fixture tests.
11. Separate Flutter example app in `flutter_example/`:
    - Android/iOS/web app shell;
    - demo-video overlay tab using hosted Python-demo clips and deterministic
        sample detections;
    - Android/iOS YOLO camera tab that converts detector boxes to
        `dart_trackers.Detections` and tracks them with `ByteTrackTracker`;
    - explicit AGPL boundary for `ultralytics_yolo`.

## Python/uv conformance environment

Always run Python conformance commands through `uv run` from
`conformance/python`. The environment is pinned to Python 3.14 via
`.python-version`, `requires-python = ">=3.14,<3.15"`, exact package versions in
`pyproject.toml`, and `uv.lock`.

```bash
cd conformance/python
uv run python generate_fixtures.py
```

## Next implementation phases

1. Replace deterministic Flutter demo-video detections with checked-in
    Python-generated per-frame detection JSON assets, then render real visual
    Python-vs-Dart comparison overlays.
2. Add a trace/debug mode to make Python/Dart divergences easy to localize.
3. Expand primitive fixture coverage:
    - rectangular assignment ties;
    - matrix inverse;
    - degenerate boxes;
    - low-FPS lost-buffer behavior.
4. Expand tracker coverage:
    - larger multi-object sequences;
    - assignment tie cases;
    - output-row contract fixtures for duplicate boxes;
    - OC-SORT degenerate XCYCSR boxes and longer ORU gaps.
5. Keep the benchmark harness current:
    - `dart run tool/benchmark.dart`;
    - `uv run python benchmark_reference.py`;
    - compare average update time and RSS deltas on identical synthetic inputs.
6. Add direct XCYCSR primitive fixtures:
    - converters;
    - degenerate-state guards;
    - Kalman state sequences.
7. Add CMC state-warping tests and optional CMC plugin strategy later.

## ByteTrack progress

ByteTrack is now implemented in Dart with fixture coverage for:

- empty updates;
- default single-object confirmation;
- missing confidence as zeros, matching locked installed `trackers==2.4.0`;
- low-confidence second-stage recovery;
- high-confidence-but-below-activation detections being dropped;
- output order where matched high detections precede matched low detections;
- confirmed-track survival across a short gap.

The implementation intentionally snapshots predicted boxes before stage 1 and
uses those same boxes for stage 2, matching Python's current behavior.

## OC-SORT progress

OC-SORT is now implemented in Dart with fixture coverage for:

- empty updates;
- default single-object confirmation;
- absent confidence;
- low-confidence filtering;
- two-object output order;
- OCR recovery across a short gap.

The numerically important parts were still small enough for the existing
`Float64List` + `Matrix` approach. XCYCSR conversion and ORU replay did not
require an NDArray, but they should get direct primitive fixtures before this
graduates from spike to maintained package code.

## BoT-SORT progress

BoT-SORT is now implemented in Dart for the no-CMC path with fixture coverage
for:

- empty updates;
- instant first-frame activation;
- unconfirmed track confirmation on the second frame;
- missing confidence as all-ones confidence;
- low-confidence second-stage recovery;
- very-low-confidence discard;
- two-object output order.

CMC remains intentionally out of scope. Passing `frame` to the Dart BoT-SORT
spike raises `UnsupportedError` so native image processing cannot silently creep
into the portable core.

## Benchmark harness

Preliminary benchmark commands:

```bash
dart run tool/benchmark.dart --frames 500 --objects 20

cd conformance/python
uv run python benchmark_reference.py --frames 500 --objects 20
```

The first run is only a smoke benchmark. Treat numbers as directional until the
sequence sizes, warmup policy, and release/AOT Dart mode are finalized.

## Open design questions

| Question            | Recommendation for now                                                                     |
| ------------------- | ------------------------------------------------------------------------------------------ |
| General NDArray?    | No. Use `Float64List` plus small matrix helpers.                                           |
| Float32 detections? | Not yet. Keep float64 everywhere for Python conformance.                                   |
| Linalg package?     | No. Hand-roll only the operations used by Kalman.                                          |
| Fixture driver?     | Python generates; Dart consumes checked-in JSON.                                           |
| Exact tracker IDs?  | Exact for non-tie synthetic cases; use ID-invariant comparison later for ambiguous scenes. |
| CMC?                | Abstract seam only; no runtime implementation in pure Dart core.                           |
