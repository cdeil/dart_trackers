import 'matrix.dart';

/// Estimates camera motion between consecutive frames for BoT-SORT.
///
/// The core package stays free of image-processing dependencies, so motion
/// estimation (for example OpenCV sparse optical flow or ECC, as upstream
/// `trackers.utils.cmc.CMC` does) lives in an app-owned adapter. BoT-SORT
/// applies the returned transform to every track's center, center velocity,
/// and covariance before association.
abstract interface class CameraMotionCompensator {
  /// Returns the 2x3 affine transform mapping the previous frame onto
  /// [frame], or `null` to skip compensation for this frame.
  ///
  /// [maskBoxes] holds the current high-confidence detections (`null` when
  /// there are none) so the estimator can ignore moving foreground objects.
  /// Upstream returns the identity on the first frame and a float32 matrix;
  /// round to float32 when bit-level parity with Python matters.
  Matrix? estimateAffine2x3(Object frame, {List<List<double>>? maskBoxes});

  /// Clears any reference frame; called from `BoTSORTTracker.reset()`.
  void reset();
}
