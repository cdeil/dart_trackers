## Unreleased

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
