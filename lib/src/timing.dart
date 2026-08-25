/// Timing for one Kalman prediction step.
class PredictTiming {
  final double frameStep;
  final double? elapsedSeconds;
  final bool skipUpdate;
  final double? frameRate;

  const new({
    required this.frameStep,
    required this.elapsedSeconds,
    this.skipUpdate = false,
    this.frameRate,
  });

  bool get skipPredict => frameStep <= 0.0;
  bool get usesElapsedTime => elapsedSeconds != null;
}

const fixedRateTiming = PredictTiming(frameStep: 1.0, elapsedSeconds: null);

typedef TrackerWarningHandler = void Function(String message);

/// Shared timestamp ordering and bootstrap state used by every tracker.
class TrackerClock {
  final double frameRate;
  final TrackerWarningHandler? onWarning;
  double? _lastTimestamp;

  new(this.frameRate, {this.onWarning});

  PredictTiming timing(double? timestamp) {
    if (timestamp == null) {
      _lastTimestamp = null;
      return fixedRateTiming;
    }
    if (!timestamp.isFinite) {
      onWarning?.call('Timestamp $timestamp is not finite; skipping update.');
      return const PredictTiming(
        frameStep: 0.0,
        elapsedSeconds: null,
        skipUpdate: true,
      );
    }
    final last = _lastTimestamp;
    if (last == null) {
      _lastTimestamp = timestamp;
      final elapsed = 1.0 / frameRate;
      return PredictTiming(
        frameStep: 1.0,
        elapsedSeconds: elapsed,
        frameRate: frameRate,
      );
    }
    if (timestamp < last) {
      onWarning?.call(
        'Timestamp $timestamp is earlier than $last; skipping update.',
      );
      return const PredictTiming(
        frameStep: 0.0,
        elapsedSeconds: null,
        skipUpdate: true,
      );
    }
    if (timestamp == last) {
      onWarning?.call(
        'Duplicate timestamp $timestamp; skipping prediction for this step.',
      );
      return const PredictTiming(frameStep: 0.0, elapsedSeconds: 0.0);
    }
    final elapsed = timestamp - last;
    _lastTimestamp = timestamp;
    return PredictTiming(
      frameStep: elapsed * frameRate,
      elapsedSeconds: elapsed,
      frameRate: frameRate,
    );
  }

  void reset() => _lastTimestamp = null;
}

int computeMaximumFramesWithoutUpdate(int lostTrackBuffer, double frameRate) {
  if (lostTrackBuffer < 0) {
    throw ArgumentError.value(
      lostTrackBuffer,
      'lostTrackBuffer',
      'Must be non-negative',
    );
  }
  if (!frameRate.isFinite || frameRate <= 0.0) {
    throw ArgumentError.value(
      frameRate,
      'frameRate',
      'Must be finite and positive',
    );
  }
  if (lostTrackBuffer == 0) return 0;
  final scaled = frameRate / 30.0 * lostTrackBuffer;
  if (!scaled.isFinite) {
    throw ArgumentError.value(
      frameRate,
      'frameRate',
      'Scaled lost-track buffer must be finite',
    );
  }
  return scaled.ceil().clamp(1, 0x7fffffff);
}

bool withinLostTrackBudget({
  required int timeSinceUpdate,
  required double timeSinceUpdateSeconds,
  required int maximumFrames,
  required double? maximumSeconds,
}) => maximumSeconds == null
    ? timeSinceUpdate <= maximumFrames
    : timeSinceUpdateSeconds <= maximumSeconds;
