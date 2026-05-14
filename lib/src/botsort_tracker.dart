import 'dart:math' as math;
import 'dart:typed_data';

import 'assignment.dart';
import 'detections.dart';
import 'iou.dart';
import 'kalman_filter.dart';
import 'matrix.dart';
import 'tracker.dart';

/// BoT-SORT tracker without runtime camera-motion compensation.
///
/// This pure-Dart port implements the no-CMC BoT-SORT path: XCYCWH state,
/// scale-aware Kalman noise, score-fused association, and high/low confidence
/// matching. Passing a video [frame] to [update] is intentionally unsupported.
class BoTSORTTracker implements Tracker {
  final int lostTrackBuffer;
  final double frameRate;
  final double trackActivationThreshold;
  final int minimumConsecutiveFrames;
  final double minimumIouThresholdFirstAssoc;
  final double minimumIouThresholdSecondAssoc;
  final double minimumIouThresholdUnconfirmedAssoc;
  final double highConfDetThreshold;
  final bool instantFirstFrameActivation;
  final int maximumFramesWithoutUpdate;

  final List<BoTSORTTracklet> tracks = [];
  int _frameId = 0;
  int _nextTrackId = 0;

  /// Creates a no-CMC BoT-SORT tracker.
  BoTSORTTracker({
    this.lostTrackBuffer = 30,
    this.frameRate = 30.0,
    this.trackActivationThreshold = 0.7,
    this.minimumConsecutiveFrames = 2,
    this.minimumIouThresholdFirstAssoc = 0.2,
    this.minimumIouThresholdSecondAssoc = 0.5,
    this.minimumIouThresholdUnconfirmedAssoc = 0.3,
    this.highConfDetThreshold = 0.6,
    this.instantFirstFrameActivation = true,
  }) : maximumFramesWithoutUpdate = math
           .max(1, (frameRate / 30.0 * lostTrackBuffer).floor())
           .toInt() {
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
      throw UnsupportedError('BoTSORTTracker pure-Dart spike does not use CMC');
    }
    _frameId++;
    if (tracks.isEmpty && detections.isEmpty) {
      return Detections.empty().copyWithTrackerId(Int32List(0));
    }

    final outDetIndices = <int>[];
    final outTrackerIds = <int>[];

    for (final track in tracks) {
      track.predict();
    }

    final detectionBoxes = detections.xyxyRows();
    final confidences = [
      for (var i = 0; i < detections.length; i++) detections.confidenceAt(i),
    ];
    final highIndices = <int>[];
    final lowIndices = <int>[];
    for (var i = 0; i < detections.length; i++) {
      final confidence = confidences[i];
      if (confidence >= highConfDetThreshold) {
        highIndices.add(i);
      } else if (confidence > 0.1) {
        lowIndices.add(i);
      }
    }

    final highBoxes = [for (final i in highIndices) detectionBoxes[i]];
    final lowBoxes = [for (final i in lowIndices) detectionBoxes[i]];
    final highScores = [for (final i in highIndices) confidences[i]];

    final confirmedTracks = <BoTSORTTracklet>[];
    final unconfirmedTracks = <BoTSORTTracklet>[];
    final lostTracks = <BoTSORTTracklet>[];
    for (final track in tracks) {
      if (track.timeSinceUpdate > 1) {
        lostTracks.add(track);
      } else if (track.numberOfSuccessfulUpdates >= minimumConsecutiveFrames) {
        confirmedTracks.add(track);
      } else {
        unconfirmedTracks.add(track);
      }
    }

    final strackPool = [...confirmedTracks, ...lostTracks];
    final stage1 = _getAssociatedIndices(
      _fuseScore(_getIouMatrix(strackPool, highBoxes), highScores),
      minimumIouThresholdFirstAssoc,
      strackPool.length,
      highBoxes.length,
    );
    for (final (row, col) in stage1.matched) {
      final track = strackPool[row];
      track.update(highBoxes[col]);
      _assignIdIfMature(track);
      outDetIndices.add(highIndices[col]);
      outTrackerIds.add(track.trackerId);
    }

    final remainingTracked = [
      for (final index in stage1.unmatchedTracks)
        if (strackPool[index].timeSinceUpdate == 1) strackPool[index],
    ];
    final stage2 = _getAssociatedIndices(
      _getIouMatrix(remainingTracked, lowBoxes),
      minimumIouThresholdSecondAssoc,
      remainingTracked.length,
      lowBoxes.length,
    );
    for (final (row, col) in stage2.matched) {
      final track = remainingTracked[row];
      track.update(lowBoxes[col]);
      _assignIdIfMature(track);
      outDetIndices.add(lowIndices[col]);
      outTrackerIds.add(track.trackerId);
    }
    for (final detLocalIndex in stage2.unmatchedDetections) {
      outDetIndices.add(lowIndices[detLocalIndex]);
      outTrackerIds.add(-1);
    }

    var unmatchedHigh = stage1.unmatchedDetections;
    final unmatchedHighList = [...unmatchedHigh]..sort();
    var unmatchedUnconfirmedIndices = <int>[
      for (var i = 0; i < unconfirmedTracks.length; i++) i,
    ];
    if (unconfirmedTracks.isNotEmpty && unmatchedHighList.isNotEmpty) {
      final unmatchedHighBoxes = [
        for (final index in unmatchedHighList) highBoxes[index],
      ];
      final unmatchedHighScores = [
        for (final index in unmatchedHighList) highScores[index],
      ];
      final unconfirmed = _getAssociatedIndices(
        _fuseScore(
          _getIouMatrix(unconfirmedTracks, unmatchedHighBoxes),
          unmatchedHighScores,
        ),
        minimumIouThresholdUnconfirmedAssoc,
        unconfirmedTracks.length,
        unmatchedHighBoxes.length,
      );

      for (final (row, col) in unconfirmed.matched) {
        final track = unconfirmedTracks[row];
        final originalHighIndex = unmatchedHighList[col];
        track.update(highBoxes[originalHighIndex]);
        _assignIdIfMature(track);
        outDetIndices.add(highIndices[originalHighIndex]);
        outTrackerIds.add(track.trackerId);
      }
      unmatchedHigh = [
        for (final localIndex in unconfirmed.unmatchedDetections)
          unmatchedHighList[localIndex],
      ];
      unmatchedUnconfirmedIndices = unconfirmed.unmatchedTracks;
    }

    if (unmatchedUnconfirmedIndices.isNotEmpty) {
      final remove = {
        for (final index in unmatchedUnconfirmedIndices)
          unconfirmedTracks[index],
      };
      tracks.removeWhere(remove.contains);
    }

    for (final detLocalIndex in unmatchedHigh) {
      final globalIndex = highIndices[detLocalIndex];
      if (confidences[globalIndex] >= trackActivationThreshold) {
        final track = BoTSORTTracklet(detectionBoxes[globalIndex]);
        if (_frameId == 1 && instantFirstFrameActivation) {
          track.trackerId = _nextTrackId++;
        }
        tracks.add(track);
        outDetIndices.add(globalIndex);
        outTrackerIds.add(track.trackerId);
      }
    }

    tracks.removeWhere((track) {
      final isMature =
          track.numberOfSuccessfulUpdates >= minimumConsecutiveFrames;
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
    _frameId = 0;
    _nextTrackId = 0;
  }

  void _assignIdIfMature(BoTSORTTracklet track) {
    if (track.numberOfSuccessfulUpdates >= minimumConsecutiveFrames &&
        track.trackerId == -1) {
      track.trackerId = _nextTrackId++;
    }
  }

  Matrix _getIouMatrix(
    List<BoTSORTTracklet> tracklets,
    List<List<double>> boxes,
  ) {
    return boxIouBatch([
      for (final track in tracklets) track.getStateBbox(),
    ], boxes);
  }

  Matrix _fuseScore(Matrix iouSimilarity, List<double> scores) {
    final result = iouSimilarity.copy();
    for (var row = 0; row < result.rows; row++) {
      for (var col = 0; col < result.cols; col++) {
        result[row][col] *= scores[col];
      }
    }
    return result;
  }

  _BoTSORTAssociation _getAssociatedIndices(
    Matrix similarityMatrix,
    double minimumSimilarityThreshold,
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
        if (similarityMatrix[row][col] >= minimumSimilarityThreshold) {
          matched.add((row, col));
          unmatchedTracks.remove(row);
          unmatchedDetections.remove(col);
        }
      }
    }

    return _BoTSORTAssociation(
      matched: matched,
      unmatchedTracks: unmatchedTracks.toList()..sort(),
      unmatchedDetections: unmatchedDetections.toList()..sort(),
    );
  }
}

class BoTSORTTracklet {
  static const _sigmaP = 0.05;
  static const _sigmaV = 0.00625;
  static const _sigmaM = 0.05;

  final KalmanFilter kf;
  int trackerId = -1;
  int timeSinceUpdate = 0;
  int age = 0;
  int numberOfSuccessfulUpdates = 1;

  BoTSORTTracklet(List<double> initialBbox) : kf = _createFilter(initialBbox) {
    final measurement = _xyxyToXcycwh(initialBbox);
    _setScaleAwareNoise(measurement[2], measurement[3], initial: true);
  }

  void update(List<double> bbox) {
    _refreshNoiseFromState();
    kf.update(_xyxyToXcycwh(bbox));
    _clampStateBbox();
    timeSinceUpdate = 0;
    numberOfSuccessfulUpdates++;
  }

  List<double> predict() {
    _refreshNoiseFromState();
    kf.predict();
    _clampStateBbox();
    age++;
    timeSinceUpdate++;
    return getStateBbox();
  }

  List<double> getStateBbox() =>
      _xcycwhToXyxy([kf.x[0][0], kf.x[1][0], kf.x[2][0], kf.x[3][0]]);

  void _refreshNoiseFromState() {
    final bbox = getStateBbox();
    final w = math.max(bbox[2] - bbox[0], 1e-3).toDouble();
    final h = math.max(bbox[3] - bbox[1], 1e-3).toDouble();
    _setScaleAwareNoise(w, h);
  }

  void _setScaleAwareNoise(double w, double h, {bool initial = false}) {
    final qDiag = [
      math.pow(_sigmaP * w, 2).toDouble(),
      math.pow(_sigmaP * h, 2).toDouble(),
      math.pow(_sigmaP * w, 2).toDouble(),
      math.pow(_sigmaP * h, 2).toDouble(),
      math.pow(_sigmaV * w, 2).toDouble(),
      math.pow(_sigmaV * h, 2).toDouble(),
      math.pow(_sigmaV * w, 2).toDouble(),
      math.pow(_sigmaV * h, 2).toDouble(),
    ];
    final rDiag = [
      math.pow(_sigmaM * w, 2).toDouble(),
      math.pow(_sigmaM * h, 2).toDouble(),
      math.pow(_sigmaM * w, 2).toDouble(),
      math.pow(_sigmaM * h, 2).toDouble(),
    ];
    kf.q = _diag(qDiag);
    kf.r = _diag(rDiag);
    if (initial) {
      kf.p = _diag([
        math.pow(2 * _sigmaP * w, 2).toDouble(),
        math.pow(2 * _sigmaP * h, 2).toDouble(),
        math.pow(2 * _sigmaP * w, 2).toDouble(),
        math.pow(2 * _sigmaP * h, 2).toDouble(),
        math.pow(10 * _sigmaV * w, 2).toDouble(),
        math.pow(10 * _sigmaV * h, 2).toDouble(),
        math.pow(10 * _sigmaV * w, 2).toDouble(),
        math.pow(10 * _sigmaV * h, 2).toDouble(),
      ]);
    }
  }

  void _clampStateBbox() {
    kf.x[2][0] = math.max(kf.x[2][0], 1e-3).toDouble();
    kf.x[3][0] = math.max(kf.x[3][0], 1e-3).toDouble();
  }

  static KalmanFilter _createFilter(List<double> bbox) {
    final kf = KalmanFilter(dimX: 8, dimZ: 4);
    for (var i = 0; i < 4; i++) {
      kf.f[i][i + 4] = 1.0;
      kf.h[i][i] = 1.0;
    }
    final measurement = _xyxyToXcycwh(bbox);
    for (var i = 0; i < 4; i++) {
      kf.x[i][0] = measurement[i];
    }
    return kf;
  }

  static Matrix _diag(List<double> values) {
    final result = Matrix(values.length, values.length);
    for (var i = 0; i < values.length; i++) {
      result[i][i] = values[i];
    }
    return result;
  }
}

List<double> _xyxyToXcycwh(List<double> xyxy) {
  final w = xyxy[2] - xyxy[0];
  final h = xyxy[3] - xyxy[1];
  return [xyxy[0] + w * 0.5, xyxy[1] + h * 0.5, w, h];
}

List<double> _xcycwhToXyxy(List<double> xcycwh) {
  return [
    xcycwh[0] - xcycwh[2] * 0.5,
    xcycwh[1] - xcycwh[3] * 0.5,
    xcycwh[0] + xcycwh[2] * 0.5,
    xcycwh[1] + xcycwh[3] * 0.5,
  ];
}

class _BoTSORTAssociation {
  final List<(int, int)> matched;
  final List<int> unmatchedTracks;
  final List<int> unmatchedDetections;

  const _BoTSORTAssociation({
    required this.matched,
    required this.unmatchedTracks,
    required this.unmatchedDetections,
  });
}
