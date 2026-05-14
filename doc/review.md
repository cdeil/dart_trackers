# Dart trackers spike review

## Result

The pure Dart SORT, ByteTrack, OC-SORT, and no-CMC BoT-SORT spike works and
passes the current conformance suite.

Implemented package pieces:

- `Detections` backed by typed lists;
- small `Matrix` helper;
- Joseph-form `KalmanFilter`;
- IoU;
- SciPy-style rectangular assignment;
- `SORTTracker`;
- `ByteTrackTracker`;
- `OCSORTTracker`;
- `BoTSORTTracker` without runtime CMC;
- abstract CMC seam;
- Python fixture generator;
- Dart fixture-consuming tests.

Validated fixture layers:

- SciPy assignment cases;
- `supervision.box_iou_batch` IoU matrix;
- Python SORT XYXY Kalman state sequence;
- Python SORT synthetic end-to-end tracker ID cases.
- Python ByteTrack synthetic end-to-end tracker ID and output-order cases.
- Python OC-SORT synthetic end-to-end tracker ID and output-order cases.
- Python BoT-SORT no-CMC synthetic end-to-end tracker ID and output-order cases.

## What worked well

### The Flutter example can keep the package boundary clean

The real Flutter app lives in `flutter_example/`, outside the pub.dev package.
That lets the core package remain Apache-2.0 and zero-runtime-dependency while
still demonstrating integration with mobile video/camera UI. The app validates on
web with the video tab and uses conditional imports so `ultralytics_yolo` is only
referenced by Android/iOS builds.

The Python trackers docs use RF-DETR through `inference` / `inference-models`
(`rfdetr-nano` by default in the CLI and `rfdetr-medium` on the homepage). For
Flutter, the practical on-device detector path is currently the Ultralytics YOLO
plugin, so the example documents that detector difference and keeps it clearly
separate because of AGPL licensing.

Local validation covered `flutter analyze`, `flutter test`,
`flutter build web --debug`, `flutter build apk --debug`, and
`flutter build ios --debug --simulator --no-codesign`.

### Pure Dart is viable for the small core

SORT, ByteTrack, OC-SORT, and no-CMC BoT-SORT did not require a broad numerical
ecosystem. A small `Float64List` `Matrix` plus explicit loops was enough for
prediction, update, assignment, IoU, XCYCSR conversion, OC-SORT ORU replay,
XCYCWH conversion, and BoT-SORT scale-aware noise. This supports the v3
recommendation to avoid an NDArray clone.

### Python-generated fixtures are the right workflow

The fixture generator made it straightforward to compare Dart behavior against
the current Python reference without running Python from Dart tests. The checked
fixture manifest also records the exact Python, NumPy, SciPy, supervision, and
trackers versions used.

### ByteTrack port exposed output-order semantics

ByteTrack does not currently return detections in input order. It appends output
rows in this order:

1. matched high-confidence detections;
2. matched low-confidence detections;
3. unmatched low-confidence detections with `-1`;
4. spawned unmatched high-confidence detections with `-1`.

The Dart fixture stores `expected_output_indices` as well as `tracker_id` to pin
this behavior explicitly.

### OC-SORT fit the same primitives

OC-SORT was the first real test of the numerically harder parts: XCYCSR state,
direction consistency, OCR, and ORU freeze/unfreeze replay. The implementation is
more verbose than Python because NumPy broadcasting is replaced with explicit
loops, but it still stayed local to `ocsort_tracker.dart` and reused the same
Kalman, matrix, IoU, and assignment primitives.

### BoT-SORT worked once CMC was excluded

BoT-SORT added another state representation (`XCYCWH`) and scale-aware process /
measurement noise, but the core association logic remained a manageable Dart
port. The largest design decision was to reject `frame` input in Dart for now:
no-CMC behavior is fixture-backed, while CMC remains a future plugin boundary
rather than an accidental OpenCV dependency.

### The SORT API stayed clean

The Dart API can match the Python mental model while improving a few semantics:

- `update()` returns a new `Detections`;
- inputs are not mutated;
- missing confidence defaults to `1.0` at the `Detections` API level, with
    ByteTrack overriding this to match locked Python behavior;
- tracker IDs are per-instance rather than class-global.

### CMC can stay isolated

PR 414's CMC-isolation direction maps well to Dart. For this spike, no tracker
needed runtime CMC. Keeping only `CameraMotionCompensator` avoids OpenCV/native
dependencies and preserves web/mobile portability.

## Issues encountered

### Flutter tests need a platform-plugin seam

`video_player` initializes through a platform interface and throws in the plain
Flutter widget-test VM unless a fake implementation is installed. The app now
has a small test-only page injection seam so the smoke test can validate app
navigation without invoking native video or camera plugins.

### The current video tab is not yet a real detector comparison

The Flutter video tab streams the same public Roboflow demo-video URLs used by
the Python demo app, but it overlays deterministic sample detections rather than
running RF-DETR/YOLO over each video frame. This is enough to prove the
`dart_trackers` UI integration and web build, but the next validation step is to
generate per-frame detections on the Python side, bundle JSON assets, and let the
Flutter app run the Dart tracker over those real detections.

### Web support is video/playback only for now

Flutter web builds successfully and Flutter reports the wasm dry run succeeds,
but the YOLO camera tab is intentionally a stub on web because
`ultralytics_yolo` targets Android/iOS. A future web detector would need either a
separate JS/WASM model runtime or precomputed detection assets.

### Conformance uses locked packages, not ambient local imports

The generator no longer prepends the repository `src/` directory to
`sys.path`. It imports the locked `trackers==2.4.0` package from the uv
environment. This removes the need for a direct `pydeprecate` dependency or any
local import shim in the conformance setup.

One behavior difference from the original design assumption is now explicit:
locked `trackers==2.4.0` treats ByteTrack detections with missing confidence as
zero confidence, while SORT/OC-SORT accept them. Dart mirrors the locked oracle
for the spike rather than following unmerged/local fixes.

### Python 3.14 via uv is required

The system `python3` is 3.12.7, but `uv run` provisions Python 3.14.0 and
generates fixtures with the locked dependency set. Conformance commands should
not use ambient `python3`; use:

```bash
cd conformance/python
uv run python generate_fixtures.py
```

`pydeprecate` may still appear transitively because `supervision` depends on it,
but `dart_trackers` no longer depends on it directly.

### Assignment tie-breaking remains risky

The assignment implementation matches the SciPy-style shortest augmenting path
structure and passes unique fixtures. It should not yet be trusted for scenes
with ambiguous equal-cost assignments. Exact tracker IDs can diverge even when
the matching is mathematically valid.

Recommended follow-up:

- add explicit cost-matrix tie fixtures;
- decide whether to perturb costs deterministically;
- compare track partitions instead of raw numeric IDs for crossing scenes.

### Float determinism needs a written policy

Dart VM tests pass with tight tolerances against NumPy float64 fixtures.
Flutter web/dart2js may differ more because JavaScript number semantics and code
generation can change intermediate operation ordering. For now, the spike should
claim Dart VM/AOT conformance only.

Recommended policy:

- tracker IDs exact for unambiguous fixtures;
- general floats `atol=1e-7`, `rtol=1e-7` on VM/AOT;
- Kalman state `atol=1e-9`, `rtol=1e-7` on VM/AOT;
- re-evaluate tolerances on dart2js before promising web equivalence.

### Matrix inverse is intentionally simple

Gauss-Jordan inverse with partial pivoting is enough for the 4x4 Kalman
innovation matrix in the spike. It is not a general linalg library.

Before OC-SORT production work, add fixtures for:

- inverse on well-conditioned and near-singular matrices;
- Kalman covariance symmetry;
- failure behavior for singular matrices.

### SLOC comparison is reproducible

Command:

```bash
python3 tool/sloc_report.py --format markdown
```

Current source-line counts:

| Category                        | Python SLOC | Dart SLOC | Dart / Python |
| ------------------------------- | ----------: | --------: | ------------: |
| NumPy / linalg replacement      |           0 |       210 |           n/a |
| SciPy assignment replacement    |           0 |       176 |           n/a |
| Detection / IoU / state support |         370 |       178 |         0.48x |
| Kalman filter                   |          62 |        53 |         0.85x |
| SORT tracker                    |         172 |       177 |         1.03x |
| ByteTrack tracker               |         206 |       225 |         1.09x |
| OC-SORT tracker                 |         338 |       415 |         1.23x |
| BoT-SORT tracker                |         455 |       366 |         0.80x |
| Dart tests and conformance      |         500 |      1074 |         2.15x |
| Dart JSONL demo CLI             |           0 |        74 |           n/a |

The tracker logic is close to one-to-one for SORT and ByteTrack. OC-SORT is
about 22% larger in Dart because direction-consistency broadcasting and ORU
virtual-observation replay are explicit loops. No-CMC BoT-SORT is smaller than
the Python category because Python's tracker files contain more CMC and
state-estimator generality even after excluding the CMC implementation files.
The real Dart-only overhead is not tracker logic; it is the 386 SLOC replacing
NumPy matrix operations and SciPy assignment. That is still small enough to own
for this package.

The report includes only core tracker sources, primitive numerics, and the
fixture/conformance tests relevant to this spike. It excludes dataset download,
evaluation metrics, scripts, documentation, generated JSON fixtures, package
metadata, and benchmark JSON output. The Python tracker categories include
`src/trackers/core/{sort,bytetrack,ocsort}`, selected utilities under
`src/trackers/utils`, and representative upstream tests under `tests/core`. The
Dart categories include `lib/src`, Dart tests, and the Python fixture/benchmark
scripts because those are maintained inside this new package.

### Preliminary performance benchmark

Command pair:

```bash
dart run tool/benchmark.dart --frames 500 --objects 10 --repeats 5
dart run tool/benchmark.dart --frames 500 --objects 100 --repeats 5
dart compile exe tool/benchmark.dart -o build/benchmark
./build/benchmark --frames 500 --objects 100 --repeats 5

cd conformance/python
uv run python benchmark_reference.py --frames 500 --objects 100 --repeats 5
```

Current local median update time in microseconds per frame, 500 frames, 5
repeats:

| Runtime     | Objects |   SORT | ByteTrack | OC-SORT | BoT-SORT |
| ----------- | ------: | -----: | --------: | ------: | -------: |
| Dart VM     |      10 |   35.6 |      36.6 |    36.8 |     35.1 |
| Dart VM     |     100 |  881.6 |     890.0 |  1211.4 |    978.0 |
| Dart AOT    |      10 |   38.7 |      41.5 |    45.7 |     45.9 |
| Dart AOT    |     100 | 1041.1 |    1098.7 |  1265.1 |   1160.0 |
| Python 3.14 |      10 |  189.3 |     210.4 |   299.9 |    365.5 |
| Python 3.14 |     100 | 1818.8 |    1762.2 |  2459.3 |   3287.0 |

These numbers are directional only. RSS deltas are still noisy and should be
treated as smoke indicators rather than stable memory measurements.

## Design adjustments from Opus 4.7 critique

The Opus critique highlighted three important changes that were applied:

- Pin float tolerance and VM-first conformance policy.
- Treat assignment tie-breaking as the highest ID-divergence risk.
- Specify exact SORT Kalman state, matrices, and noise before coding.

It also recommended not shipping partial trackers, so this spike implements
SORT, ByteTrack, OC-SORT, and no-CMC BoT-SORT as complete fixture-backed slices
and leaves CMC for later phases.

## Pure Dart clone assessment

The spike supports continuing with a pure Dart clone for Flutter/mobile use.

Reasons:

- package setup is simple;
- tests run with ordinary `dart test`;
- no native toolchain is needed;
- the core math is small;
- conformance can be fixture-driven.

The main long-term risks are not raw performance. They are correctness and test
coverage:

- assignment tie semantics;
- longer OC-SORT ORU gaps and degenerate XCYCSR conversions;
- BoT-SORT CMC state warping, if/when a plugin API is added;
- ByteTrack output-row contract on larger/ambiguous scenes;
- CMC isolation for BoT-SORT;
- deterministic fixtures across Python package changes.

## Recommended next step

Add trace-mode debug output before OC-SORT. The trace should dump per frame:

- predicted boxes;
- IoU/similarity matrix;
- assignment rows and columns;
- accepted and rejected matches;
- unmatched tracks/detections;
- spawned/deleted tracks;
- output tracker IDs.

This will make Python/Dart divergence debugging much cheaper than comparing only
final tracker ID streams.
