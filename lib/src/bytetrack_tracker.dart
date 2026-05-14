import 'dart:math' as math;
import 'dart:typed_data';

import 'assignment.dart';
import 'detections.dart';
import 'iou.dart';
import 'kalman_filter.dart';
import 'matrix.dart';
import 'tracker.dart';

/// ByteTrack tracker with high- and low-confidence association stages.
///
/// ByteTrack is a good default for crowded scenes because low-confidence
/// detections can recover already-active tracks without spawning new tracks.
class ByteTrackTracker implements Tracker {
  final int lostTrackBuffer;
  final double frameRate;
  final double trackActivationThreshold;
  final int minimumConsecutiveFrames;
  final double minimumIouThreshold;
  final double highConfDetThreshold;
  final int maximumFramesWithoutUpdate;

  final List<ByteTrackTracklet> tracks = [];
  int _nextTrackId = 0;

  /// Creates a ByteTrack tracker.
  ByteTrackTracker({
    this.lostTrackBuffer = 30,
    this.frameRate = 30.0,
    this.trackActivationThreshold = 0.7,
    this.minimumConsecutiveFrames = 2,
    this.minimumIouThreshold = 0.1,
    this.highConfDetThreshold = 0.6,
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
      throw UnsupportedError('ByteTrackTracker does not use frame input');
    }
    if (tracks.isEmpty && detections.isEmpty) {
      return Detections.empty().copyWithTrackerId(Int32List(0));
    }

    for (final track in tracks) {
      track.predict();
    }

    final detectionBoxes = detections.xyxyRows();
    final highIndices = <int>[];
    final lowIndices = <int>[];
    for (var i = 0; i < detections.length; i++) {
      final confidence = detections.confidence == null
          ? 0.0
          : detections.confidenceAt(i);
      if (confidence >= highConfDetThreshold) {
        highIndices.add(i);
      } else {
        lowIndices.add(i);
      }
    }

    final highBoxes = [for (final i in highIndices) detectionBoxes[i]];
    final lowBoxes = [for (final i in lowIndices) detectionBoxes[i]];
    final outDetIndices = <int>[];
    final outTrackerIds = <int>[];

    final predictedBoxes = [for (final track in tracks) track.getStateBbox()];

    final stage1 = _getAssociatedIndices(
      boxIouBatch(predictedBoxes, highBoxes),
      tracks.length,
      highBoxes.length,
    );

    for (final (row, col) in stage1.matched) {
      final track = tracks[row];
      track.update(highBoxes[col]);
      _assignIdIfMature(track);
      outDetIndices.add(highIndices[col]);
      outTrackerIds.add(track.trackerId);
    }

    final remainingTracks = [for (final i in stage1.unmatchedTracks) tracks[i]];
    final remainingBoxes = [
      for (final i in stage1.unmatchedTracks) predictedBoxes[i],
    ];
    final stage2 = _getAssociatedIndices(
      boxIouBatch(remainingBoxes, lowBoxes),
      remainingTracks.length,
      lowBoxes.length,
    );

    for (final (row, col) in stage2.matched) {
      final track = remainingTracks[row];
      track.update(lowBoxes[col]);
      _assignIdIfMature(track);
      outDetIndices.add(lowIndices[col]);
      outTrackerIds.add(track.trackerId);
    }

    for (final detLocalIndex in stage2.unmatchedDetections) {
      outDetIndices.add(lowIndices[detLocalIndex]);
      outTrackerIds.add(-1);
    }

    for (final detLocalIndex in stage1.unmatchedDetections) {
      final globalIndex = highIndices[detLocalIndex];
      final confidence = detections.confidence == null
          ? 0.0
          : detections.confidenceAt(globalIndex);
      if (confidence >= trackActivationThreshold) {
        tracks.add(ByteTrackTracklet(detectionBoxes[globalIndex]));
        outDetIndices.add(globalIndex);
        outTrackerIds.add(-1);
      }
    }

    tracks.removeWhere((track) {
      final isMature =
          track.trackerId != -1 ||
          track.numberOfSuccessfulConsecutiveUpdates >=
              minimumConsecutiveFrames;
      final isActive = track.timeSinceUpdate == 0;
      return !(track.timeSinceUpdate < maximumFramesWithoutUpdate &&
          (isMature || isActive));
    });

    if (outDetIndices.isEmpty) {
      return Detections.empty().copyWithTrackerId(Int32List(0));
    }
    return detections
        .select(outDetIndices)
        .copyWithTrackerId(Int32List.fromList(outTrackerIds));
  }

  @override
  void reset() {
    tracks.clear();
    _nextTrackId = 0;
  }

  void _assignIdIfMature(ByteTrackTracklet track) {
    if (track.numberOfSuccessfulConsecutiveUpdates >=
            minimumConsecutiveFrames &&
        track.trackerId == -1) {
      track.trackerId = _nextTrackId++;
    }
  }

  _ByteTrackAssociation _getAssociatedIndices(
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

    return _ByteTrackAssociation(
      matched: matched,
      unmatchedTracks: unmatchedTracks.toList()..sort(),
      unmatchedDetections: unmatchedDetections.toList()..sort(),
    );
  }
}

class ByteTrackTracklet {
  final KalmanFilter kf;
  int trackerId = -1;
  int timeSinceUpdate = 0;
  int age = 0;
  int numberOfSuccessfulConsecutiveUpdates = 1;

  ByteTrackTracklet(List<double> initialBbox)
    : kf = _createFilter(initialBbox) {
    _configureNoise();
  }

  void predict() {
    kf.predict();
    if (timeSinceUpdate > 0) {
      numberOfSuccessfulConsecutiveUpdates = 0;
    }
    timeSinceUpdate++;
    age++;
  }

  void update(List<double> bbox) {
    kf.update(bbox);
    timeSinceUpdate = 0;
    numberOfSuccessfulConsecutiveUpdates++;
  }

  List<double> getStateBbox() => [
    kf.x[0][0],
    kf.x[1][0],
    kf.x[2][0],
    kf.x[3][0],
  ];

  void _configureNoise() {
    kf.q = kf.q.scaled(0.01);
    kf.r = kf.r.scaled(0.1);
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

class _ByteTrackAssociation {
  final List<(int, int)> matched;
  final List<int> unmatchedTracks;
  final List<int> unmatchedDetections;

  const _ByteTrackAssociation({
    required this.matched,
    required this.unmatchedTracks,
    required this.unmatchedDetections,
  });
}
