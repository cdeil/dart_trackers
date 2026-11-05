import 'dart:math' as math;
import 'dart:typed_data';

import 'assignment.dart';
import 'cmc.dart';
import 'converters.dart';
import 'detections.dart';
import 'iou.dart';
import 'kalman_filter.dart';
import 'matrix.dart';
import 'motion_model.dart';
import 'timing.dart';
import 'tracker.dart';

/// BoT-SORT tracker with an optional external camera-motion adapter.
///
/// The portable core owns XCYCWH state, scale-aware Kalman noise, score-fused
/// association, and affine state application. Image-based motion estimation is
/// supplied through [cameraMotionCompensator] to avoid an OpenCV dependency.
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
  final double maximumTimeWithoutUpdate;
  final BaseIoU iouFirst;
  final BaseIoU iouSecond;
  final TrackerClock _clock;
  final TrackerWarningHandler? _onWarning;
  final CameraMotionCompensator? cameraMotionCompensator;

  final List<BoTSORTTracklet> tracks = [];
  int _frameId = 0;
  int _nextTrackId = 0;

  /// Creates a BoT-SORT tracker.
  new({
    this.lostTrackBuffer = 30,
    this.frameRate = 30.0,
    this.trackActivationThreshold = 0.7,
    this.minimumConsecutiveFrames = 2,
    this.minimumIouThresholdFirstAssoc = 0.2,
    this.minimumIouThresholdSecondAssoc = 0.5,
    this.minimumIouThresholdUnconfirmedAssoc = 0.3,
    this.highConfDetThreshold = 0.6,
    this.instantFirstFrameActivation = true,
    BaseIoU? firstIou,
    BaseIoU? secondIou,
    this.cameraMotionCompensator,
    TrackerWarningHandler? onWarning,
  }) : maximumFramesWithoutUpdate = computeMaximumFramesWithoutUpdate(
         lostTrackBuffer,
         frameRate,
       ),
       maximumTimeWithoutUpdate = lostTrackBuffer / 30.0,
       iouFirst = firstIou ?? const IoU(),
       iouSecond = secondIou ?? firstIou ?? const IoU(),
       _clock = TrackerClock(frameRate, onWarning: onWarning),
       _onWarning = onWarning {
    if (minimumConsecutiveFrames < 0) {
      throw ArgumentError.value(
        minimumConsecutiveFrames,
        'minimumConsecutiveFrames',
        'Must be non-negative',
      );
    }
  }

  @override
  Detections update(Detections detections, {Object? frame, double? timestamp}) {
    final timing = _clock.timing(timestamp);
    if (timing.skipUpdate) {
      return detections.copyWithTrackerId(
        Int32List.fromList(List.filled(detections.length, -1)),
      );
    }
    if (frame != null && cameraMotionCompensator == null) {
      // Upstream C-BIoU warns here; upstream BoT-SORT with CMC disabled is
      // silent. Dart warns for both because the frame is always unused.
      _onWarning?.call(
        '$runtimeType.update() received a frame argument but does not use it.',
      );
    }
    _frameId++;
    if (tracks.isEmpty && detections.isEmpty) {
      return Detections.empty().copyWithTrackerId(Int32List(0));
    }

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

    // Camera motion is estimated after the confidence split so only
    // high-confidence boxes mask the feature detector, as upstream.
    if (frame != null && cameraMotionCompensator != null) {
      final transform = cameraMotionCompensator!.estimateAffine2x3(
        frame,
        maskBoxes: highBoxes.isEmpty ? null : highBoxes,
      );
      if (transform != null) {
        for (final track in tracks) {
          track.applyCameraMotion(transform);
        }
      }
    }
    // Track state does not change between the association stages, so each
    // predicted box is decoded once.
    final predictedBoxes = <BoTSORTTracklet, List<double>>{
      for (final track in tracks) track: track.getStateBbox(),
    };

    final confirmedTracks = <BoTSORTTracklet>[];
    final unconfirmedTracks = <BoTSORTTracklet>[];
    final lostTracks = <BoTSORTTracklet>[];
    for (final track in tracks) {
      if (track.timeSinceUpdate > 1) {
        lostTracks.add(track);
      } else if (track.trackerId != -1 ||
          track.numberOfSuccessfulUpdates >= minimumConsecutiveFrames) {
        confirmedTracks.add(track);
      } else {
        unconfirmedTracks.add(track);
      }
    }

    final strackPool = [...confirmedTracks, ...lostTracks];
    final stage1 = _getAssociatedIndices(
      _fuseScore(
        _getIouMatrix(strackPool, highBoxes, iouFirst, predictedBoxes),
        highScores,
        iouFirst,
      ),
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
      _getIouMatrix(remainingTracked, lowBoxes, iouSecond, predictedBoxes),
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
          _getIouMatrix(
            unconfirmedTracks,
            unmatchedHighBoxes,
            iouFirst,
            predictedBoxes,
          ),
          unmatchedHighScores,
          iouFirst,
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
      outDetIndices.add(globalIndex);
      outTrackerIds.add(-1);
      if (confidences[globalIndex] >= trackActivationThreshold) {
        final track = BoTSORTTracklet(detectionBoxes[globalIndex]);
        if (_frameId == 1 && instantFirstFrameActivation) {
          track.trackerId = _nextTrackId++;
          outTrackerIds[outTrackerIds.length - 1] = track.trackerId;
        }
        tracks.add(track);
      }
    }

    tracks.removeWhere((track) {
      final isMature =
          track.trackerId != -1 ||
          track.numberOfSuccessfulUpdates >= minimumConsecutiveFrames;
      final isActive = track.timeSinceUpdate == 0;
      final withinBudget = withinLostTrackBudget(
        timeSinceUpdate: track.timeSinceUpdate,
        timeSinceUpdateSeconds: track.timeSinceUpdateSeconds,
        maximumFrames: maximumFramesWithoutUpdate,
        maximumSeconds: timing.usesElapsedTime
            ? maximumTimeWithoutUpdate
            : null,
      );
      return !(withinBudget && (isMature || isActive));
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
    _clock.reset();
    cameraMotionCompensator?.reset();
  }

  @override
  Detections get trackedObjects {
    final confirmed = tracks.where((track) => track.trackerId >= 0).toList();
    return Detections.fromRows(
      [for (final track in confirmed) track.getStateBbox()],
      trackerId: [for (final track in confirmed) track.trackerId],
    );
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
    BaseIoU metric,
    Map<BoTSORTTracklet, List<double>> predictedBoxes,
  ) {
    return metric.compute([
      for (final track in tracklets) predictedBoxes[track]!,
    ], boxes);
  }

  Matrix _fuseScore(Matrix iouSimilarity, List<double> scores, BaseIoU metric) {
    final result = metric.normalizeForFusion(iouSimilarity).copy();
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

/// One BoT-SORT track with XCYCWH Kalman state and scale-aware noise.
class BoTSORTTracklet {
  static const _sigmaP = 0.05;
  static const _sigmaV = 0.00625;
  static const _sigmaM = 0.05;

  final KalmanFilter kf;
  late final KalmanMotionModel motionModel;
  int trackerId = -1;
  int timeSinceUpdate = 0;
  double timeSinceUpdateSeconds = 0.0;
  int age = 0;
  int numberOfSuccessfulUpdates = 1;

  new(List<double> initialBbox) : kf = _createFilter(initialBbox) {
    final measurement = xyxyToXcycwh(initialBbox);
    _setInitialNoise(measurement[2], measurement[3]);
    motionModel = KalmanMotionModel.fromFilter(
      kf,
      positionIndices: const [0, 1, 2, 3],
      velocityIndices: const [4, 5, 6, 7],
    );
  }

  void update(List<double> bbox) {
    // Only update() reads R and only predict() reads Q (upstream #567).
    final (w, h) = _currentWh();
    kf.r = _measurementNoise(w, h);
    kf.update(xyxyToXcycwh(bbox));
    _clampStateBbox();
    timeSinceUpdate = 0;
    timeSinceUpdateSeconds = 0.0;
    numberOfSuccessfulUpdates++;
  }

  List<double> predict([PredictTiming timing = fixedRateTiming]) {
    final (w, h) = _currentWh();
    kf.q = _processNoise(w, h);
    motionModel.calibrate(kf.q);
    motionModel.apply(kf, timing.frameStep, frameRate: timing.frameRate);
    kf.predict();
    _clampStateBbox();
    age++;
    timeSinceUpdate++;
    if (timing.elapsedSeconds != null) {
      timeSinceUpdateSeconds += timing.elapsedSeconds!;
    } else {
      timeSinceUpdateSeconds = 0.0;
    }
    return getStateBbox();
  }

  List<double> getStateBbox() =>
      xcycwhToXyxy([kf.x[0][0], kf.x[1][0], kf.x[2][0], kf.x[3][0]]);

  /// Applies an externally estimated affine transform to the center state,
  /// center velocity, and their covariance.
  ///
  /// [affine] is 2x3, or 3x3 in which case only the top two rows are used, as
  /// upstream does. Non-finite entries throw an [ArgumentError].
  void applyCameraMotion(Matrix affine) {
    if (affine.cols != 3 || (affine.rows != 2 && affine.rows != 3)) {
      throw ArgumentError('Camera motion transform must be 2x3 or 3x3');
    }
    for (var i = 0; i < 6; i++) {
      if (!affine.data[i].isFinite) {
        throw ArgumentError('Camera motion transform must be finite');
      }
    }
    final a00 = affine[0][0];
    final a01 = affine[0][1];
    final a10 = affine[1][0];
    final a11 = affine[1][1];
    final centerX = kf.x[0][0];
    final centerY = kf.x[1][0];
    final velocityX = kf.x[4][0];
    final velocityY = kf.x[5][0];
    kf.x[0][0] = a00 * centerX + a01 * centerY + affine[0][2];
    kf.x[1][0] = a10 * centerX + a11 * centerY + affine[1][2];
    kf.x[4][0] = a00 * velocityX + a01 * velocityY;
    kf.x[5][0] = a10 * velocityX + a11 * velocityY;

    final transform = Matrix.identity(8);
    transform[0][0] = a00;
    transform[0][1] = a01;
    transform[1][0] = a10;
    transform[1][1] = a11;
    transform[4][4] = a00;
    transform[4][5] = a01;
    transform[5][4] = a10;
    transform[5][5] = a11;
    kf.p = transform * kf.p * transform.transpose();
  }

  /// Width and height rebuilt from the decoded corners, so the result keeps
  /// the center-dependent rounding of [getStateBbox] (upstream #572).
  (double, double) _currentWh() {
    final xc = kf.x[0][0];
    final yc = kf.x[1][0];
    final halfW = kf.x[2][0] * 0.5;
    final halfH = kf.x[3][0] * 0.5;
    return (
      math.max((xc + halfW) - (xc - halfW), 1e-3).toDouble(),
      math.max((yc + halfH) - (yc - halfH), 1e-3).toDouble(),
    );
  }

  Matrix _processNoise(double w, double h) => Matrix.diagonal([
    math.pow(_sigmaP * w, 2).toDouble(),
    math.pow(_sigmaP * h, 2).toDouble(),
    math.pow(_sigmaP * w, 2).toDouble(),
    math.pow(_sigmaP * h, 2).toDouble(),
    math.pow(_sigmaV * w, 2).toDouble(),
    math.pow(_sigmaV * h, 2).toDouble(),
    math.pow(_sigmaV * w, 2).toDouble(),
    math.pow(_sigmaV * h, 2).toDouble(),
  ]);

  Matrix _measurementNoise(double w, double h) => Matrix.diagonal([
    math.pow(_sigmaM * w, 2).toDouble(),
    math.pow(_sigmaM * h, 2).toDouble(),
    math.pow(_sigmaM * w, 2).toDouble(),
    math.pow(_sigmaM * h, 2).toDouble(),
  ]);

  void _setInitialNoise(double w, double h) {
    kf.q = _processNoise(w, h);
    kf.r = _measurementNoise(w, h);
    kf.p = Matrix.diagonal([
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
    final measurement = xyxyToXcycwh(bbox);
    for (var i = 0; i < 4; i++) {
      kf.x[i][0] = measurement[i];
    }
    return kf;
  }
}

class _BoTSORTAssociation {
  final List<(int, int)> matched;
  final List<int> unmatchedTracks;
  final List<int> unmatchedDetections;

  const new({
    required this.matched,
    required this.unmatchedTracks,
    required this.unmatchedDetections,
  });
}
