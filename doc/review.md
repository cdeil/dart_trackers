# 0.2 parity review

The 0.2 implementation reaches portable parity with Roboflow `trackers` 2.6 for
SORT, ByteTrack, OC-SORT, BoT-SORT without an in-core image estimator, C-BIoU,
the five IoU metrics, timestamp-aware prediction, lifecycle semantics, and
tracked-object access.

The prior 2.4 divergences are removed: missing ByteTrack confidence is one,
unmatched high detections are returned, zero buffers are valid, positive
low-FPS buffers round up, expiry is inclusive, instant IDs remain mature,
non-finite boxes fail early, and XCYCSR zero scale no longer divides by zero.
The post-2.6 OC-SORT low-confidence output change is also covered.

The remaining intentional boundary is McByte mask association. Implementing it
inside this package would add model weights and Torch/SAM/Cutie or platform GPU
runtimes, defeating the portable package boundary. Camera-motion estimation is
similarly delegated to an adapter, but affine state application is implemented
and tested in core.

On the August 2026 Apple 27 beta host, 500-frame AOT medians were 26.5, 22.4,
24.0, 26.5, and 27.0 microseconds/update for SORT, ByteTrack, OC-SORT,
BoT-SORT, and C-BIoU at 10 objects. At 100 objects the same trackers measured
458.9, 460.0, 540.9, 515.3, and 525.8 microseconds/update. The matching Python
2.6 workload measured 139–275 microseconds at 10 objects and 1.26–2.49
milliseconds at 100 objects. These are local regression numbers, not a general
cross-language performance guarantee.
