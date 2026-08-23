import 'detections.dart';

/// Common interface implemented by all trackers in this package.
abstract interface class Tracker {
  /// Updates tracker state with detections from one frame.
  ///
  /// [timestamp] is the absolute capture time in seconds. Omit it for the
  /// original fixed-rate behaviour. Implementations that do not use [frame]
  /// ignore it so callers can share one pipeline across tracker types.
  Detections update(Detections detections, {Object? frame, double? timestamp});

  /// Confirmed tracks that remain alive, including temporarily missed ones.
  Detections get trackedObjects;

  /// Clears live tracks, timestamp state, and the per-instance ID allocator.
  void reset();
}
