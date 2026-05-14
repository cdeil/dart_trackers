import 'detections.dart';

/// Common interface implemented by all trackers in this package.
///
/// Trackers consume a batch of detections in `xyxy` format and return a new
/// detection batch with `trackerId` populated. Implementations do not mutate
/// the input detections.
abstract interface class Tracker {
  /// Updates tracker state with detections from one frame.
  ///
  /// The optional [frame] argument is reserved for future camera-motion
  /// compensation integrations. Current pure-Dart trackers either ignore it or
  /// reject it when they cannot process image data portably.
  Detections update(Detections detections, {Object? frame});

  /// Clears all live tracks and resets the per-instance track ID counter.
  void reset();
}
