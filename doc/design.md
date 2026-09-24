# Dart trackers design

`dart_trackers` is a pure Dart, zero-runtime-dependency implementation of the
portable tracking core in Roboflow `trackers` (develop after 2.6.0, including
the 2.6.1 fixes). It targets Dart VM, AOT,
Flutter mobile, and browser builds.

## Public model

- `Detections` stores flat `Float64List` XYXY boxes and optional confidence,
  class, and tracker IDs. It copies its inputs, so batches never share storage.
  Empty results carry no confidence or class IDs.
- `Tracker.update()` returns a new batch; it never mutates its input.
- Unmatched or unconfirmed detections use `trackerId == -1`.
- `trackedObjects` exposes confirmed alive Kalman states, including current
  detector misses.
- Warnings go to an optional `onWarning` callback instead of Python's
  `warnings` module; without a callback they are dropped.
- `timestamp` is an optional absolute capture time. Omitting it preserves the
  one-predict-per-call fixed-rate API.

## Timing and lifecycle

Timestamp bootstrap uses one nominal frame, computed as `(1 / fps) * fps` like
upstream. Steps within `0.004 * frameRate` frames of nominal reuse the tuned
one-frame process noise exactly (a fixed `0.1` band when no frame rate is
known, as in OC-SORT's ORU replay), so millisecond-rounded clocks behave like
fixed-rate input. Duplicate timestamps associate
without predicting. Backwards and non-finite timestamps skip the whole update
and return input rows with `-1`. Gaps scale constant-velocity transition and
DWNA process noise; time-based mode prunes by elapsed seconds before association
to prevent stale ghost IDs.

OC-SORT's ORU replays the straight line between the last observation and the
re-detection through the Kalman filter, one update per missed frame, stepping
by the current frame step. Each replay step clamps the scale velocity like a
normal predict, and the replay keeps the configured process-noise baseline.

`minimumConsecutiveFrames` and OC-SORT `deltaT` accept `0` like upstream.
Scaled lost-track buffers saturate at `2^31 - 1` frames for web portability.

Positive 30-FPS lost buffers scale with `ceil(frameRate / 30 * buffer)` and an
explicit zero remains zero. Expiry is inclusive. Once a track has a real ID,
maturity is sticky through misses until its budget expires.

## Association

SORT, ByteTrack, OC-SORT, and BoT-SORT accept a `BaseIoU` (`BaseIoU.fromName`
resolves upstream's metric names). OC-SORT uses it for the primary pass only;
OCR always uses plain IoU. BoT-SORT normalizes signed metrics before confidence
fusion; upstream's single BoT-SORT `iou` parameter maps to `firstIou`. Box
extents are clamped at zero like upstream #589. Dart rejects non-finite BIoU
ratios, which upstream accepts. C-BIoU specializes BoT-SORT with a
small first BIoU buffer and a larger second buffer.

The small row-major `Matrix`, Joseph-form Kalman filter, and deterministic
rectangular assignment implementation avoid a scientific-computing dependency.
Float64 is retained for parity and numerical stability; see
`validation.md` for the resulting precision differences from upstream.

Only one state representation per tracker is ported (XYXY for SORT and
ByteTrack, XCYCSR for OC-SORT, XCYCWH for BoT-SORT and C-BIoU); upstream's
`state_estimator_class` option and CLI/tuning metadata are out of scope.

## Camera motion and GPU boundary

The core does not estimate camera motion. `CameraMotionCompensator` accepts an
opaque frame and returns a 2x3 affine transform from any Flutter/native adapter;
BoT-SORT applies it to XCYCWH center state, center velocity, and covariance.

McByte's Torch/SAM/Cutie mask stack is not portable to this package. Apps can
run segmentation or depth in Core ML/TFLite and feed the resulting boxes into a
portable tracker without coupling tracker math to a model runtime.

## Source of truth

Python-generated fixtures are the behavioral oracle. Changes should update the
locked conformance environment, regenerate JSON, keep the VM and Chrome suites
green, and record a 10-object plus 100-object benchmark before release.
