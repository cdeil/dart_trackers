import 'dart:math' as math;
import 'dart:typed_data';

import 'assignment.dart';
import 'converters.dart';
import 'detections.dart';
import 'iou.dart';
import 'kalman_filter.dart';
import 'matrix.dart';
import 'motion_model.dart';
import 'timing.dart';
import 'tracker.dart';

/// OC-SORT tracker with observation-centric recovery and direction consistency.
///
/// OC-SORT is useful when object motion is less linear. It uses XCYCSR Kalman
/// state, direction consistency during association, OCR, and ORU replay.
class OCSORTTracker implements Tracker {
  final int lostTrackBuffer;
  final double frameRate;
  final int minimumConsecutiveFrames;
  final double minimumIouThreshold;
  final double directionConsistencyWeight;
  final double highConfDetThreshold;
  final int deltaT;
  final int maximumFramesWithoutUpdate;
  final double maximumTimeWithoutUpdate;
  final BaseIoU iou;
  final TrackerClock _clock;
  final TrackerWarningHandler? _onWarning;

  final List<OCSORTTracklet> tracks = [];
  int _frameCount = 0;
  int _nextTrackId = 0;

  /// Creates an OC-SORT tracker.
  new({
    this.lostTrackBuffer = 30,
    this.frameRate = 30.0,
    this.minimumConsecutiveFrames = 3,
    this.minimumIouThreshold = 0.3,
    this.directionConsistencyWeight = 0.2,
    this.highConfDetThreshold = 0.6,
    this.deltaT = 3,
    BaseIoU? iou,
    TrackerWarningHandler? onWarning,
  }) : maximumFramesWithoutUpdate = computeMaximumFramesWithoutUpdate(
         lostTrackBuffer,
         frameRate,
       ),
       maximumTimeWithoutUpdate = lostTrackBuffer / 30.0,
       iou = iou ?? const IoU(),
       _clock = TrackerClock(frameRate, onWarning: onWarning),
       _onWarning = onWarning {
    if (minimumConsecutiveFrames < 1) {
      throw ArgumentError.value(
        minimumConsecutiveFrames,
        'minimumConsecutiveFrames',
      );
    }
    if (deltaT < 1) {
      throw ArgumentError.value(deltaT, 'deltaT');
    }
  }

  @override
  Detections update(Detections detections, {Object? frame, double? timestamp}) {
    if (frame != null) {
      _onWarning?.call('OCSORTTracker ignores frame input.');
    }
    final timing = _clock.timing(timestamp);
    if (timing.skipUpdate) {
      return detections.copyWithTrackerId(
        Int32List.fromList(List.filled(detections.length, -1)),
      );
    }
    if (tracks.isEmpty && detections.isEmpty) {
      return Detections.empty().copyWithTrackerId(Int32List(0));
    }

    final highIndices = <int>[];
    final lowIndices = <int>[];
    for (var i = 0; i < detections.length; i++) {
      if (detections.confidenceAt(i) >= highConfDetThreshold) {
        highIndices.add(i);
      } else {
        lowIndices.add(i);
      }
    }
    final filtered = detections.select(highIndices);

    final detectionBoxes = filtered.xyxyRows();
    final confidences = [
      for (var i = 0; i < filtered.length; i++) filtered.confidenceAt(i),
    ];
    final outDetIndices = <int>[];
    final outTrackerIds = <int>[];

    if (!timing.skipPredict) {
      for (final track in tracks) {
        track.predict(timing);
      }
    }
    if (timing.usesElapsedTime) {
      tracks.removeWhere(
        (track) => !withinLostTrackBudget(
          timeSinceUpdate: track.timeSinceUpdate,
          timeSinceUpdateSeconds: track.timeSinceUpdateSeconds,
          maximumFrames: maximumFramesWithoutUpdate,
          maximumSeconds: maximumTimeWithoutUpdate,
        ),
      );
    }

    final predictedBoxes = [for (final track in tracks) track.getStateBbox()];
    final iouMatrix = iou.compute(predictedBoxes, detectionBoxes);
    final directionMatrix = _computeDirectionConsistencyMatrix(
      detectionBoxes,
      confidences,
    );

    final primary = _getAssociatedIndices(iouMatrix, directionMatrix);
    for (final (row, col) in primary.matched) {
      final track = tracks[row];
      track.update(detectionBoxes[col]);
      outDetIndices.add(highIndices[col]);
      outTrackerIds.add(_resolveTrackerId(track));
    }

    var remainingDetections = primary.unmatchedDetections;
    if (primary.unmatchedDetections.isNotEmpty &&
        primary.unmatchedTracks.isNotEmpty) {
      final lastObservationBoxes = [
        for (final trackIndex in primary.unmatchedTracks)
          tracks[trackIndex].lastObservation,
      ];
      final unmatchedBoxes = [
        for (final detIndex in primary.unmatchedDetections)
          detectionBoxes[detIndex],
      ];
      final ocrIou = iou.compute(lastObservationBoxes, unmatchedBoxes);
      final ocr = _getAssociatedIndices(
        ocrIou,
        Matrix(ocrIou.rows, ocrIou.cols),
      );

      for (final (row, col) in ocr.matched) {
        final trackIndex = primary.unmatchedTracks[row];
        final detIndex = primary.unmatchedDetections[col];
        final track = tracks[trackIndex];
        track.update(detectionBoxes[detIndex]);
        outDetIndices.add(highIndices[detIndex]);
        outTrackerIds.add(_resolveTrackerId(track));
      }
      remainingDetections = [
        for (final localIndex in ocr.unmatchedDetections)
          primary.unmatchedDetections[localIndex],
      ];
    }

    tracks.removeWhere(
      (track) => !withinLostTrackBudget(
        timeSinceUpdate: track.timeSinceUpdate,
        timeSinceUpdateSeconds: track.timeSinceUpdateSeconds,
        maximumFrames: maximumFramesWithoutUpdate,
        maximumSeconds: timing.usesElapsedTime
            ? maximumTimeWithoutUpdate
            : null,
      ),
    );

    for (final detIndex in remainingDetections) {
      tracks.add(OCSORTTracklet(detectionBoxes[detIndex], deltaT: deltaT));
      outDetIndices.add(highIndices[detIndex]);
      outTrackerIds.add(-1);
    }

    for (final detIndex in lowIndices) {
      outDetIndices.add(detIndex);
      outTrackerIds.add(-1);
    }
    final result = outDetIndices.isEmpty
        ? Detections.empty()
        : detections.select(outDetIndices);
    _frameCount++;
    return result.copyWithTrackerId(Int32List.fromList(outTrackerIds));
  }

  @override
  void reset() {
    tracks.clear();
    _frameCount = 0;
    _nextTrackId = 0;
    _clock.reset();
  }

  @override
  Detections get trackedObjects {
    final confirmed = tracks.where((track) => track.trackerId >= 0).toList();
    return Detections.fromRows(
      [for (final track in confirmed) track.getStateBbox()],
      trackerId: [for (final track in confirmed) track.trackerId],
    );
  }

  int _resolveTrackerId(OCSORTTracklet track) {
    final isMature =
        track.numberOfSuccessfulConsecutiveUpdates >= minimumConsecutiveFrames;
    if (_frameCount <= minimumConsecutiveFrames) {
      if (track.timeSinceUpdate == 0) {
        if (track.trackerId == -1) {
          track.trackerId = _nextTrackId++;
        }
        return track.trackerId;
      }
    } else if (isMature) {
      if (track.trackerId == -1) {
        track.trackerId = _nextTrackId++;
      }
      return track.trackerId;
    }
    return -1;
  }

  Matrix _computeDirectionConsistencyMatrix(
    List<List<double>> detectionBoxes,
    List<double> confidences,
  ) {
    final result = Matrix(tracks.length, detectionBoxes.length);
    for (var i = 0; i < tracks.length; i++) {
      final velocity = tracks[i].velocity;
      if (velocity == null) continue;
      final reference =
          tracks[i].getKPreviousObs() ?? tracks[i].lastObservation;
      final refCenterX = (reference[0] + reference[2]) / 2.0;
      final refCenterY = (reference[1] + reference[3]) / 2.0;
      for (var j = 0; j < detectionBoxes.length; j++) {
        final detection = detectionBoxes[j];
        final detCenterX = (detection[0] + detection[2]) / 2.0;
        final detCenterY = (detection[1] + detection[3]) / 2.0;
        var dx = detCenterX - refCenterX;
        var dy = detCenterY - refCenterY;
        final norm = math.sqrt(dx * dx + dy * dy) + 1e-6;
        dx /= norm;
        dy /= norm;
        final dot = (velocity[1] * dx + velocity[0] * dy)
            .clamp(-1.0, 1.0)
            .toDouble();
        final angle = math.acos(dot);
        result[i][j] =
            ((math.pi / 2.0 - angle.abs()) / math.pi) * confidences[j];
      }
    }
    return result;
  }

  _OCSORTAssociation _getAssociatedIndices(
    Matrix iouMatrix,
    Matrix directionMatrix,
  ) {
    final nTracks = iouMatrix.rows;
    final nDetections = iouMatrix.cols;
    final matched = <(int, int)>[];
    final unmatchedTracks = <int>{for (var i = 0; i < nTracks; i++) i};
    final unmatchedDetections = <int>{for (var i = 0; i < nDetections; i++) i};

    if (nTracks > 0 && nDetections > 0) {
      final costMatrix =
          iouMatrix + directionMatrix.scaled(directionConsistencyWeight);
      final assignment = linearSumAssignment(costMatrix, maximize: true);
      for (var i = 0; i < assignment.rowIndices.length; i++) {
        final row = assignment.rowIndices[i];
        final col = assignment.colIndices[i];
        if (iouMatrix[row][col] >= minimumIouThreshold) {
          matched.add((row, col));
          unmatchedTracks.remove(row);
          unmatchedDetections.remove(col);
        }
      }
    }

    return _OCSORTAssociation(
      matched: matched,
      unmatchedTracks: unmatchedTracks.toList()..sort(),
      unmatchedDetections: unmatchedDetections.toList()..sort(),
    );
  }
}

class OCSORTTracklet {
  final KalmanFilter kf;
  late final KalmanMotionModel motionModel;
  final int deltaT;
  int trackerId = -1;
  int timeSinceUpdate = 0;
  double timeSinceUpdateSeconds = 0.0;
  int age = 0;
  int numberOfSuccessfulConsecutiveUpdates = 0;
  late List<double> lastObservation;
  List<double>? previousToLastObservation;
  final Map<int, List<double>> observations = {};
  List<double>? velocity;
  _OCSORTFrozenState? _frozenState;
  bool _observed = true;

  new(List<double> initialBbox, {required this.deltaT})
    : kf = _createFilter(initialBbox) {
    _configureNoise();
    motionModel = KalmanMotionModel.fromFilter(
      kf,
      positionIndices: const [0, 1, 2],
      velocityIndices: const [4, 5, 6],
    );
    lastObservation = List<double>.from(initialBbox);
  }

  void predict([PredictTiming timing = fixedRateTiming]) {
    if (_observed && timeSinceUpdate > 0) {
      _freeze();
      _observed = false;
    }
    _clampVelocity(timing.frameStep);
    motionModel.apply(kf, timing.frameStep, frameRate: timing.frameRate);
    kf.predict();
    age++;
    if (timeSinceUpdate > 0) {
      numberOfSuccessfulConsecutiveUpdates = 0;
    }
    timeSinceUpdate++;
    if (timing.elapsedSeconds != null) {
      timeSinceUpdateSeconds += timing.elapsedSeconds!;
    } else {
      timeSinceUpdateSeconds = 0.0;
    }
  }

  void update(List<double> bbox) {
    final previousBox = getKPreviousObs();
    if (previousBox != null) {
      velocity = _computeVelocity(previousBox, bbox);
    }
    if (!_observed && _frozenState != null) {
      _unfreeze(bbox);
    }
    kf.update(xyxyToXcycsr(bbox));
    _observed = true;
    timeSinceUpdate = 0;
    timeSinceUpdateSeconds = 0.0;
    numberOfSuccessfulConsecutiveUpdates++;
    previousToLastObservation = lastObservation;
    lastObservation = List<double>.from(bbox);
    observations[age] = List<double>.from(bbox);
  }

  List<double> getStateBbox() =>
      xcycsrToXyxy([kf.x[0][0], kf.x[1][0], kf.x[2][0], kf.x[3][0]]);

  List<double>? getKPreviousObs() {
    if (observations.isEmpty) return null;
    for (var i = 0; i < deltaT; i++) {
      final dt = deltaT - i;
      final observation = observations[age - dt];
      if (observation != null) {
        return observation;
      }
    }
    var maxAge = observations.keys.first;
    for (final key in observations.keys.skip(1)) {
      maxAge = math.max(maxAge, key).toInt();
    }
    return observations[maxAge];
  }

  void _freeze() {
    _frozenState = _OCSORTFrozenState(
      x: kf.x.copy(),
      p: kf.p.copy(),
      f: kf.f.copy(),
      h: kf.h.copy(),
      q: kf.q.copy(),
      r: kf.r.copy(),
    );
  }

  void _unfreeze(List<double> newBbox) {
    final frozen = _frozenState;
    if (frozen == null) return;
    kf.x = frozen.x.copy();
    kf.p = frozen.p.copy();
    kf.f = frozen.f.copy();
    kf.h = frozen.h.copy();
    kf.q = frozen.q.copy();
    kf.r = frozen.r.copy();
    motionModel.calibrate(kf.q);
    motionModel.resetCache();

    final timeGap = timeSinceUpdate;
    final last = xyxyToXcycsr(lastObservation);
    final next = xyxyToXcycsr(newBbox);
    final x1 = last[0];
    final y1 = last[1];
    final w1 = math.sqrt(last[2] * last[3]);
    final h1 = math.sqrt(last[2] / last[3]);
    final x2 = next[0];
    final y2 = next[1];
    final w2 = math.sqrt(next[2] * next[3]);
    final h2 = math.sqrt(next[2] / next[3]);
    final dx = (x2 - x1) / timeGap;
    final dy = (y2 - y1) / timeGap;
    final dw = (w2 - w1) / timeGap;
    final dh = (h2 - h1) / timeGap;

    for (var i = 0; i < timeGap; i++) {
      final x = x1 + (i + 1) * dx;
      final y = y1 + (i + 1) * dy;
      final w = w1 + (i + 1) * dw;
      final h = h1 + (i + 1) * dh;
      kf.update([x, y, w * h, w / h]);
      if (i < timeGap - 1) {
        motionModel.apply(kf, 1.0);
        kf.predict();
      }
    }
    _frozenState = null;
  }

  void _configureNoise() {
    kf.r[2][2] *= 10.0;
    kf.r[3][3] *= 10.0;
    for (var i = 4; i < 7; i++) {
      kf.p[i][i] *= 1000.0;
    }
    kf.p = kf.p.scaled(10.0);
    kf.q[6][6] *= 0.01;
    for (var i = 4; i < 7; i++) {
      kf.q[i][i] *= 0.01;
    }
  }

  void _clampVelocity(double frameStep) {
    if (kf.x[2][0] + frameStep * kf.x[6][0] <= 0.0) {
      kf.x[6][0] = 0.0;
    }
  }

  static KalmanFilter _createFilter(List<double> bbox) {
    final kf = KalmanFilter(dimX: 7, dimZ: 4);
    kf.f = Matrix.fromRows([
      [1, 0, 0, 0, 1, 0, 0],
      [0, 1, 0, 0, 0, 1, 0],
      [0, 0, 1, 0, 0, 0, 1],
      [0, 0, 0, 1, 0, 0, 0],
      [0, 0, 0, 0, 1, 0, 0],
      [0, 0, 0, 0, 0, 1, 0],
      [0, 0, 0, 0, 0, 0, 1],
    ]);
    kf.h = Matrix(4, 7);
    for (var i = 0; i < 4; i++) {
      kf.h[i][i] = 1.0;
    }
    final measurement = xyxyToXcycsr(bbox);
    for (var i = 0; i < 4; i++) {
      kf.x[i][0] = measurement[i];
    }
    return kf;
  }

  static List<double> _computeVelocity(List<double> a, List<double> b) {
    final cx1 = (a[0] + a[2]) / 2.0;
    final cy1 = (a[1] + a[3]) / 2.0;
    final cx2 = (b[0] + b[2]) / 2.0;
    final cy2 = (b[1] + b[3]) / 2.0;
    final dy = cy2 - cy1;
    final dx = cx2 - cx1;
    final norm = math.sqrt(dy * dy + dx * dx) + 1e-6;
    return [dy / norm, dx / norm];
  }
}

class _OCSORTAssociation {
  final List<(int, int)> matched;
  final List<int> unmatchedTracks;
  final List<int> unmatchedDetections;

  const new({
    required this.matched,
    required this.unmatchedTracks,
    required this.unmatchedDetections,
  });
}

class _OCSORTFrozenState {
  final Matrix x;
  final Matrix p;
  final Matrix f;
  final Matrix h;
  final Matrix q;
  final Matrix r;

  const new({
    required this.x,
    required this.p,
    required this.f,
    required this.h,
    required this.q,
    required this.r,
  });
}
