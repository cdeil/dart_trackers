import 'botsort_tracker.dart';
import 'iou.dart';

/// Cascaded Buffered IoU tracker using a small then a larger match buffer.
class CBIoUTracker extends BoTSORTTracker {
  final double bufferRatioFirst;
  final double bufferRatioSecond;

  CBIoUTracker({
    super.lostTrackBuffer,
    super.frameRate,
    super.trackActivationThreshold,
    super.minimumConsecutiveFrames,
    super.minimumIouThresholdFirstAssoc,
    super.minimumIouThresholdSecondAssoc,
    super.minimumIouThresholdUnconfirmedAssoc,
    super.highConfDetThreshold,
    super.instantFirstFrameActivation,
    this.bufferRatioFirst = 0.3,
    this.bufferRatioSecond = 0.5,
    super.onWarning,
  }) : super(
         firstIou: BIoU(bufferRatio: bufferRatioFirst),
         secondIou: BIoU(bufferRatio: bufferRatioSecond),
       );
}
