## 0.3.0

Parity with Roboflow `trackers` develop (52610c3, a superset of 2.6.1).

- Moved the Python conformance oracle from `trackers==2.6.0` to trackers
  develop pinned by git revision, with numpy 2.5.3, scipy 1.18.1, and
  supervision 0.30.5. `manifest.json` records the revision and the generator
  refuses to run against another one. The hand-written OC-SORT low-confidence
  fixture rows are gone because the oracle now emits them itself.
- Fixed OC-SORT recovery after two or more missed frames (ORU): the virtual
  trajectory now steps by the current frame step, clamps scale velocity like
  a normal predict, keeps the configured process-noise baseline, and guards a
  zero-width last observation. Previously a shrinking object could decode to
  a negative area, a zero-width box produced NaN state, and a timestamp gap
  could permanently inflate process noise.
- OC-SORT's second-chance association (OCR) always uses plain IoU, and
  detections without confidence bypass `highConfDetThreshold`, as upstream.
- GIoU clamps box extents at zero, so malformed boxes score `0.0` instead of
  `+1.0`/`-1.0` (upstream #589). CIoU squares the angle term before scaling,
  like NumPy.
- `linearSumAssignment` follows SciPy for infinities: `+inf` is a forbidden
  edge when minimizing and `-inf` when maximizing; the opposite sign, NaN, or
  an infeasible matrix throws `ArgumentError` (infeasible used to throw
  `StateError`).
- `minimumConsecutiveFrames` and OC-SORT `deltaT` accept `0`, like upstream.
- BoT-SORT passes only high-confidence boxes (or `null`) to the
  `CameraMotionCompensator`, after the confidence split, and
  `applyCameraMotion` accepts a 3x3 transform.
- `Detections` copies all of its lists, so tracker output no longer shares
  confidence or class-ID storage with the input. All trackers return the same
  empty result.
- Frame-unused warnings use upstream's wording and name the concrete tracker.
- The timestamp bootstrap frame step is computed as `(1 / fps) * fps`, like
  upstream.
- Added `BaseIoU.fromName` (upstream `variant_from_name`) and
  `Matrix.diagonal`, doc comments for the IoU family and converters, and
  ported upstream's #567 Q/R noise split, #572 width/height arithmetic, and
  #580 predicted-box reuse (no output change).
- Fixtures now cover timestamps (bootstrap, gaps, duplicates, backwards,
  seconds-budget pruning, mixed modes), OC-SORT ORU and OCR edge cases,
  malformed and non-integer IoU batches with fusion normalization, SciPy
  assignment ties and forbidden edges, IoU metric selection, and per-frame
  tracked objects and warning counts for every tracker.
- Raised the minimum SDK to Dart 3.13.1 and adopted its concise constructor
  syntax, formatter behavior, and analyzer lints.
- Updated development dependencies and the Flutter example to their latest
  stable releases.

## 0.2.0

- Updated the Python conformance oracle to `trackers==2.6.0` and
  `supervision==0.29.0`.
- Added C-BIoU and the BIoU, GIoU, DIoU, and CIoU metric family.
- Added timestamp-aware prediction, dynamic Kalman process noise, wall-clock
  expiry, duplicate/backwards timestamp handling, and `trackedObjects`.
- Fixed missing-confidence ByteTrack behavior, inclusive lifecycle boundaries,
  low-FPS buffer rounding, sticky instant activation, non-finite box validation,
  XCYCSR zero-scale conversion, and unmatched detection output contracts.
- Included the post-2.6 OC-SORT low-confidence output fix from upstream develop.
- Added a portable BoT-SORT camera-motion adapter and affine state-warp tests.
- Kept the core at zero runtime dependencies and expanded VM, browser,
  conformance, and performance coverage.

## 0.1.0

- Initial pure-Dart package with SORT, ByteTrack, OC-SORT, and no-CMC BoT-SORT.
- Added Python-generated conformance fixtures, Dart tests, benchmark tooling, and
    package documentation.
