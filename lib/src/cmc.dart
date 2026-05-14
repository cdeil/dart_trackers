import 'matrix.dart';

/// Placeholder interface for future camera motion compensation support.
///
/// The pure Dart spike deliberately avoids OpenCV or image-processing
/// dependencies. Future BoT-SORT-like trackers can accept an implementation
/// that returns a 2x3 affine transform estimated elsewhere.
abstract interface class CameraMotionCompensator {
  Matrix? estimateAffine2x3(Object frame, {List<List<double>>? maskBoxes});

  void reset();
}
