# Dart trackers design

`dart_trackers` is a pure Dart, zero-runtime-dependency implementation of the
portable tracking core in Roboflow `trackers` 2.6. It targets Dart VM, AOT,
Flutter mobile, and browser builds.

## Public model

- `Detections` stores flat `Float64List` XYXY boxes and optional confidence,
  class, and tracker IDs.
- `Tracker.update()` returns a new batch; it never mutates its input.
- Unmatched or unconfirmed detections use `trackerId == -1`.
- `trackedObjects` exposes confirmed alive Kalman states, including current
  detector misses.
- `timestamp` is an optional absolute capture time. Omitting it preserves the
  one-predict-per-call fixed-rate API.

## Timing and lifecycle

Timestamp bootstrap uses one nominal frame. Duplicate timestamps associate
without predicting. Backwards and non-finite timestamps skip the whole update
and return input rows with `-1`. Gaps scale constant-velocity transition and
DWNA process noise; time-based mode prunes by elapsed seconds before association
to prevent stale ghost IDs.

Positive 30-FPS lost buffers scale with `ceil(frameRate / 30 * buffer)` and an
explicit zero remains zero. Expiry is inclusive. Once a track has a real ID,
maturity is sticky through misses until its budget expires.

## Association

SORT, ByteTrack, OC-SORT, and BoT-SORT accept a `BaseIoU`. BoT-SORT normalizes
signed metrics before confidence fusion. C-BIoU specializes BoT-SORT with a
small first BIoU buffer and a larger second buffer.

The small row-major `Matrix`, Joseph-form Kalman filter, and deterministic
rectangular assignment implementation avoid a scientific-computing dependency.
Float64 is retained for parity and numerical stability.

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
