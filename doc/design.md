# Dart trackers design v3

This document is the v3 design for a pure Dart clone of Roboflow's `trackers`
package. It supersedes the native-Dart parts of `docs/dart_rewrite_analysis.md`
and adjusts the v2 recommendation in `docs/dart_rewrite_analysis_v2.md`.

## Decision

For this spike, implement a **pure Dart package** instead of a Rust core with a
Dart wrapper.

The Rust design remains strategically attractive for shared Python, Dart,
JS/WASM, and backend use. The work in
`https://github.com/roman-koshchei/trackers-rs` and Roboflow discussion
`https://github.com/roboflow/trackers/issues/393` is useful inspiration:

- keep language-neutral data structures;
- test against the Python reference;
- make assignment and Kalman behavior explicit;
- benchmark after correctness, not before.

However, for a Flutter/Dart package today, Rust creates significant release and
CI complexity: Android/iOS native artifacts, desktop binaries, a separate web
WASM path, and native-toolchain test coverage. A pure Dart spike is the fastest
way to answer whether the tracker core is small and deterministic enough to own
in Dart.

## Upstream context

Roboflow PR `https://github.com/roboflow/trackers/pull/415` discusses and fixes
edge cases around `detections.confidence is None`. This spike deliberately uses
the locked installed `trackers==2.4.0` package as the oracle rather than a local
branch, so Dart follows that package exactly: SORT/OC-SORT treat missing
confidence as passable detections, while ByteTrack treats missing confidence as
zeros and therefore does not spawn new tracks from those detections.

Roboflow PR `https://github.com/roboflow/trackers/pull/414` starts isolating
camera motion compensation (CMC). Dart should follow that direction. CMC should
not force OpenCV, native image processing, or Flutter frame types into the
minimal tracker core.

## Scope

### Current spike scope

The spike implements:

- package scaffolding;
- `Detections` container;
- IoU;
- deterministic rectangular assignment;
- small `Float64List` matrix helper;
- generic Kalman filter;
- SORT tracker with XYXY state;
- ByteTrack tracker with XYXY state;
- OC-SORT tracker with XCYCSR state, ORU, OCR, and direction consistency;
- BoT-SORT tracker without runtime CMC;
- Python-generated JSON conformance fixtures;
- Dart tests that consume those fixtures.

### Out of scope for this spike

- BoT-SORT CMC implementation;
- image/video I/O;
- evaluation metrics;
- OpenCV or CMC estimation;
- Flutter widgets or annotators;
- a general NumPy/NDArray clone.

OC-SORT and no-CMC BoT-SORT have now been added after SORT, ByteTrack, and
primitive fixtures. Partial tracker implementations remain worse than stubs
because they hide semantic divergence; new trackers should continue to land only
as fixture-backed slices.

## Package layout

```text
.
  lib/
    dart_trackers.dart
    src/
      assignment.dart
      cmc.dart
      detections.dart
      iou.dart
      kalman_filter.dart
      matrix.dart
      sort_tracker.dart
      bytetrack_tracker.dart
      botsort_tracker.dart
      ocsort_tracker.dart
  conformance/
    fixtures/
      assignment_cases.json
      iou_cases.json
      kalman_sort_xyxy.json
      manifest.json
       sort_cases.json
       bytetrack_cases.json
       botsort_cases.json
       ocsort_cases.json
    python/
      pyproject.toml
      generate_fixtures.py
  doc/
    design.md
    plan.md
    review.md
    test/
      assignment_test.dart
       bytetrack_tracker_test.dart
       botsort_tracker_test.dart
      iou_test.dart
    kalman_test.dart
     sort_tracker_test.dart
     ocsort_tracker_test.dart
```

## Public API shape

```dart
final tracker = SORTTracker(minimumConsecutiveFrames: 1);
final detections = Detections.fromRows([
  [0, 0, 10, 10],
], confidence: [
  0.9,
]);

final tracked = tracker.update(detections);
print(tracked.trackerIdList());
```

The API intentionally mirrors the Python mental model:

- input is a detection batch with `xyxy`, optional confidence, optional class ID;
- output is a new detection batch with `trackerId`;
- input objects are not mutated;
- unmatched or immature detections receive `trackerId = -1`;
- tracker IDs are allocated by each tracker instance, not globally.

## Data structures

### Detections

Use a flat row-major `Float64List` for bounding boxes with shape `[N, 4]`.

Reasons:

- maps cleanly to NumPy fixture data;
- avoids per-box record/list allocation inside hot loops;
- works on Dart VM, AOT, Flutter mobile, desktop, and web;
- keeps the API small enough to replace or wrap later.

`confidence` uses `Float64List?`; `classId` and `trackerId` use `Int32List?`.
`Detections.confidenceAt()` returns `1.0` when confidence is absent, but trackers
may override that when matching Python semantics require it. ByteTrack currently
treats absent confidence as zeros because that is what locked `trackers==2.4.0`
does.

### Matrix

Use a tiny row-major `Matrix` around `Float64List`.

Do **not** implement a general `NDArray` in this package. The previous
`dart_supervision` experiment showed that a NumPy-shaped abstraction is too much
surface area for this problem. Tracker math needs a small fixed set of
operations:

- identity;
- copy;
- transpose;
- add/subtract;
- scale;
- matrix multiplication;
- Gauss-Jordan inverse with partial pivoting;
- column-vector conversion.

This is enough for SORT, ByteTrack, and OC-SORT. OC-SORT adds XCYCSR conversions
and freeze/unfreeze state snapshots, but still does not require a full
scientific-computing stack. BoT-SORT adds scale-aware diagonal noise and XCYCWH
state, again without requiring a general NDArray.

Avoid `package:ml_linalg`, `scidart`, or a broad numeric dependency until a
measured gap appears. The dependency risk and API mismatch are currently larger
than the benefit.

### Float precision

Use `double` / `Float64List` throughout the spike.

The Python reference uses NumPy float64 for tracker internals in the current
package. The Rust prototype used `f32` successfully for ByteTrack, but Dart
float64 is the safer conformance default. If performance or memory becomes an
issue, a future v4 can evaluate `Float32List` for detections while keeping
Kalman state in float64.

## Assignment strategy

Every tracker relies on `scipy.optimize.linear_sum_assignment`. The Dart spike
ports the rectangular shortest augmenting path structure used by SciPy-style
implementations and exposes:

```dart
linearSumAssignment(matrix, maximize: true)
```

Risks:

- equally optimal assignments can produce different valid ID streams;
- SciPy tie-breaking is deterministic but not a high-level API contract;
- ID exactness in end-to-end tests is fragile when scenes contain ties.

Policy:

- primitive assignment fixtures compare exact row/column results only for
    unique or intentionally stable cases;
- tracker fixtures avoid ambiguous ties;
- future crossing-object tests should either add tiny deterministic score
    perturbations or compare ID partitions rather than raw numeric IDs.

## Kalman and SORT state

The spike implements the Python package's current default SORT state:

- XYXY state vector of length 8:
    `[x1, y1, x2, y2, vx1, vy1, vx2, vy2]`;
- measurement vector of length 4:
    `[x1, y1, x2, y2]`;
- constant-velocity transition with `F[i, i + 4] = 1` for `i = 0..3`;
- measurement matrix `H = eye(4, 8)`;
- SORT noise for XYXY state:
    - `Q = eye(8) * 0.01`;
    - `R = eye(4) * 0.1`;
    - `P = eye(8)`;
- covariance update uses Joseph form, matching the current Python utility.

OC-SORT uses XCYCSR:

- state vector `[xc, yc, scale, ratio, vxc, vyc, vscale]`;
- ratio has no velocity;
- conversion follows the Python reference, including `ratio = width / (height + 1e-6)`;
- the current code still needs more degenerate scale/ratio fixtures before web
    or production claims.

## Lifecycle semantics

SORT spike semantics:

- Every live track predicts once per frame before association.
- Association uses IoU and `linearSumAssignment(maximize: true)`.
- Matches below `minimumIouThreshold` are rejected.
- Unmatched detections with confidence at least `trackActivationThreshold`
    spawn new tracklets.
- Spawned tracklets do not emit a real tracker ID in the same frame.
- Matched tracklets emit a real ID once
    `numberOfSuccessfulUpdates >= minimumConsecutiveFrames`.
- Dead tracklets are removed when:
    `timeSinceUpdate >= maximumFramesWithoutUpdate` or they are immature and not
    active.

The Dart spike uses:

```dart
maximumFramesWithoutUpdate = max(1, floor(frameRate / 30 * lostTrackBuffer))
```

The `max(1, ...)` guard avoids the zero-buffer low-FPS footgun noted in the
Python review while matching current Python behavior for normal 30 FPS cases.

### ByteTrack semantics

The Dart ByteTrack port follows the current Python control flow:

- split detections into high confidence (`confidence >= highConfDetThreshold`)
    and low confidence (everything else);
- associate high detections to all tracks;
- associate low detections to remaining tracks using the predicted boxes
    snapshotted before stage-1 updates;
- spawn only unmatched high detections whose confidence is at least
    `trackActivationThreshold`;
- assign IDs only from matched updates, never on same-frame spawn;
- keep maturity sticky once `trackerId != -1`;
- output rows in Python order, not input order.

ByteTrack-specific confidence note: when `detections.confidence` is absent, the
locked Python oracle uses a zero vector for the high/low split. Dart mirrors that
behavior for ByteTrack even though `Detections.confidenceAt()` defaults to
`1.0`.

### OC-SORT semantics

The Dart OC-SORT port follows the current Python control flow:

- filter detections by `highConfDetThreshold` only when confidence is present;
- predict every tracklet before association;
- associate predicted boxes and detections with IoU plus direction consistency;
- use OCR as a second-chance association against last observations;
- implement ORU by freezing Kalman state on the first missed frame and replaying
    virtual observations when the track is observed again;
- output rows in Python order, not necessarily input order.

### BoT-SORT semantics

The Dart BoT-SORT port intentionally covers the no-CMC path only:

- XCYCWH state vector `[xc, yc, w, h, vxc, vyc, vw, vh]`;
- scale-aware diagonal `P`, `Q`, and `R` from object width/height;
- high/low/discard confidence split with the Python `0.1` low-confidence floor;
- confirmed, unconfirmed, and lost track pools;
- score-fused first and unconfirmed association;
- no score fusion for low-confidence second association;
- optional instant first-frame activation, matching Python's default;
- `frame` input is rejected until CMC is designed as a plugin.

## CMC design

CMC is not implemented in the runtime spike.

The only CMC surface is:

```dart
abstract interface class CameraMotionCompensator {
  Matrix? estimateAffine2x3(Object frame, {List<List<double>>? maskBoxes});
  void reset();
}
```

Rules:

- no OpenCV dependency in `lib/src`;
- no image or Flutter frame type in the core;
- no CMC estimation until BoT-SORT or McByte-like trackers need it;
- if CMC is added, pass an affine 2x3 transform into tracker state warping.

PR 414's direction is good: isolate CMC behind a replaceable module. Dart should
go further and keep the estimation outside the portable core.

## Conformance strategy

The conformance direction is **Python generates, Dart consumes**.

Checked-in JSON fixtures live under `conformance/fixtures`. The generator lives
under `conformance/python`. The current fixture layers are:

1. assignment fixtures from SciPy;
2. IoU fixture from `supervision.box_iou_batch`;
3. SORT XYXY Kalman one-step sequence from Python tracklets;
4. SORT end-to-end synthetic scenes from Python `SORTTracker`;
5. ByteTrack end-to-end synthetic scenes from Python `ByteTrackTracker`;
6. OC-SORT end-to-end synthetic scenes from Python `OCSORTTracker`;
7. BoT-SORT no-CMC end-to-end synthetic scenes from Python `BoTSORTTracker`.

Comparison policy:

- tracker IDs: exact equality for non-ambiguous synthetic fixtures;
- general floats: `atol = 1e-7`, `rtol = 1e-7`;
- Kalman state on Dart VM: `atol = 1e-9`, `rtol = 1e-7`;
- future crossing/tie scenes: prefer ID-partition comparison or deterministic
    epsilon perturbation.

The conformance Python environment is defined in
`conformance/python/pyproject.toml`. It is pinned to Python 3.14 through
`.python-version`, `requires-python = ">=3.14,<3.15"`, exact dependency pins, and
`uv.lock`. Always run fixture generation with:

```bash
cd conformance/python
uv run python generate_fixtures.py
```

The fixture manifest records the actual versions used.

## Lessons from `dart_supervision`

Keep:

- the idea of a Dart-native `Detections` container;
- the SciPy-style assignment algorithm;
- IoU tests and simple geometry helpers.

Do not keep:

- a broad `NDArray` clone;
- unrelated SciPy ports such as interpolation;
- the old `supervision` ByteTracker port;
- structural tests that only check objects exist.

The new package should be tracker-first and fixture-driven.

## Implementation phases

1. **SORT spike**: complete and validated in this folder.
2. **ByteTrack spike**: complete and validated with fixture-backed output order.
3. **OC-SORT spike**: complete and validated with fixture-backed ORU/OCR smoke
    cases.
4. **BoT-SORT no-CMC spike**: complete and validated with fixture-backed
    high/low/unconfirmed association cases.
5. **Trace mode**: add optional per-frame debug output with predicted boxes,
    IoU matrices, assignments, unmatched sets, and lifecycle changes.
6. **Tracker hardening**: add larger multi-object fixtures, output-order edge
    cases, and tie-policy tests.
7. **CMC seam**: only then add affine state-warping tests, still without
    requiring OpenCV in Dart.
8. **Performance pass**: benchmark after semantic conformance is stable.
