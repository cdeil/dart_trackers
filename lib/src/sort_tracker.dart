import 'dart:math' as math;
import 'dart:typed_data';

import 'assignment.dart';
import 'detections.dart';
import 'iou.dart';
import 'kalman_filter.dart';
import 'matrix.dart';
import 'tracker.dart';

/// SORT tracker using an XYXY constant-velocity Kalman filter.
///
/// SORT is the smallest and fastest tracker in this package. It associates
/// detections to existing tracks by IoU and starts new tracks from unmatched
/// detections above [trackActivationThreshold].
class SORTTracker implements Tracker {
  final int lostTrackBuffer;
  final double frameRate;
  final double trackActivationThreshold;
  final int minimumConsecutiveFrames;
  final double minimumIouThreshold;
  final int maximumFramesWithoutUpdate;

  final List<SORTTracklet> tracks = [];
  int _nextTrackId = 0;

  /// Creates a SORT tracker.
  SORTTracker({
    this.lostTrackBuffer = 30,
    this.frameRate = 30.0,
    this.trackActivationThreshold = 0.25,
    this.minimumConsecutiveFrames = 3,
    this.minimumIouThreshold = 0.3,
  }) : maximumFramesWithoutUpdate = math.max(
         1,
         (frameRate / 30.0 * lostTrackBuffer).floor(),
       ) {
    if (lostTrackBuffer < 1) {
      throw ArgumentError.value(lostTrackBuffer, 'lostTrackBuffer');
    }
    if (frameRate <= 0) {
      throw ArgumentError.value(frameRate, 'frameRate');
    }
    if (minimumConsecutiveFrames < 1) {
      throw ArgumentError.value(
        minimumConsecutiveFrames,
        'minimumConsecutiveFrames',
      );
    }
  }

  @override
  Detections update(Detections detections, {Object? frame}) {
    if (frame != null) {
      throw UnsupportedError('SORTTracker does not use frame input');
    }
    if (tracks.isEmpty && detections.isEmpty) {
      return detections.copyWithTrackerId(Int32List(0));
    }

    for (final track in tracks) {
      track.predict();
    }

    final detectionBoxes = detections.xyxyRows();
    final predictedBoxes = [for (final track in tracks) track.getStateBbox()];
    final iouMatrix = boxIouBatch(predictedBoxes, detectionBoxes);
    final associated = _getAssociatedIndices(
      iouMatrix,
      tracks.length,
      detections.length,
    );

    final matchedTrackletForDetection = <int, SORTTracklet>{};
    for (final (trackIndex, detectionIndex) in associated.matched) {
      final track = tracks[trackIndex];
      track.update(detectionBoxes[detectionIndex]);
      matchedTrackletForDetection[detectionIndex] = track;
    }

    for (final detectionIndex in associated.unmatchedDetections) {
      if (detections.confidenceAt(detectionIndex) >= trackActivationThreshold) {
        tracks.add(SORTTracklet(detectionBoxes[detectionIndex]));
      }
    }

    tracks.removeWhere((track) {
      final isMature =
          track.numberOfSuccessfulUpdates >= minimumConsecutiveFrames;
      final isActive = track.timeSinceUpdate == 0;
      return !(track.timeSinceUpdate < maximumFramesWithoutUpdate &&
          (isMature || isActive));
    });

    final trackerIds = Int32List(detections.length);
    for (var i = 0; i < trackerIds.length; i++) {
      trackerIds[i] = -1;
    }
    for (final entry in matchedTrackletForDetection.entries) {
      final track = entry.value;
      if (track.numberOfSuccessfulUpdates >= minimumConsecutiveFrames) {
        if (track.trackerId == -1) {
          track.trackerId = _nextTrackId++;
        }
        trackerIds[entry.key] = track.trackerId;
      }
    }
    return detections.copyWithTrackerId(trackerIds);
  }

  @override
  void reset() {
    tracks.clear();
    _nextTrackId = 0;
  }

  _Association _getAssociatedIndices(
    Matrix similarityMatrix,
    int nTracks,
    int nDetections,
  ) {
    final matched = <(int, int)>[];
    final unmatchedTracks = <int>{for (var i = 0; i < nTracks; i++) i};
    final unmatchedDetections = <int>{for (var i = 0; i < nDetections; i++) i};

    if (nTracks > 0 && nDetections > 0) {
      final assignment = linearSumAssignment(similarityMatrix, maximize: true);
      for (var i = 0; i < assignment.rowIndices.length; i++) {
        final row = assignment.rowIndices[i];
        final col = assignment.colIndices[i];
        if (similarityMatrix[row][col] >= minimumIouThreshold) {
          matched.add((row, col));
          unmatchedTracks.remove(row);
          unmatchedDetections.remove(col);
        }
      }
    }

    return _Association(
      matched: matched,
      unmatchedTracks: unmatchedTracks.toList()..sort(),
      unmatchedDetections: unmatchedDetections.toList()..sort(),
    );
  }
}

class SORTTracklet {
  final KalmanFilter kf;
  int trackerId = -1;
  int timeSinceUpdate = 0;
  int age = 0;
  int numberOfSuccessfulUpdates = 1;

  SORTTracklet(List<double> initialBbox) : kf = _createFilter(initialBbox) {
    _configureNoise();
  }

  void predict() {
    kf.predict();
    timeSinceUpdate++;
    age++;
  }

  void update(List<double> bbox) {
    kf.update(bbox);
    timeSinceUpdate = 0;
    numberOfSuccessfulUpdates++;
  }

  List<double> getStateBbox() => [
    kf.x[0][0],
    kf.x[1][0],
    kf.x[2][0],
    kf.x[3][0],
  ];

  void _configureNoise() {
    kf.q = Matrix.identity(8).scaled(0.01);
    kf.r = Matrix.identity(4).scaled(0.1);
    kf.p = Matrix.identity(8);
  }

  static KalmanFilter _createFilter(List<double> bbox) {
    if (bbox.length != 4) {
      throw ArgumentError.value(bbox.length, 'bbox.length', 'Expected 4');
    }
    final kf = KalmanFilter(dimX: 8, dimZ: 4);
    for (var i = 0; i < 4; i++) {
      kf.x[i][0] = bbox[i];
      kf.f[i][i + 4] = 1.0;
      kf.h[i][i] = 1.0;
    }
    return kf;
  }
}

class _Association {
  final List<(int, int)> matched;
  final List<int> unmatchedTracks;
  final List<int> unmatchedDetections;

  const _Association({
    required this.matched,
    required this.unmatchedTracks,
    required this.unmatchedDetections,
  });
}
