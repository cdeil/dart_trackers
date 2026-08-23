# ------------------------------------------------------------------------
# Trackers
# Copyright (c) 2026 Roboflow. All Rights Reserved.
# Licensed under the Apache License, Version 2.0 [see LICENSE for details]
# ------------------------------------------------------------------------

import argparse
import gc
import json
import time
from collections.abc import Iterable
from typing import Any

import numpy as np
import psutil
import supervision as sv
from trackers import BoTSORTTracker, ByteTrackTracker, CBIoUTracker, OCSORTTracker, SORTTracker


def make_frames(n_frames: int, n_objects: int) -> list[sv.Detections]:
    frames = []
    for frame_index in range(n_frames):
        boxes = []
        confidence = []
        class_id = []
        for object_index in range(n_objects):
            x = 20.0 + object_index * 35.0 + frame_index * 0.7
            y = 30.0 + (object_index % 5) * 45.0 + frame_index * 0.2
            w = 20.0 + (object_index % 3) * 3.0
            h = 30.0 + (object_index % 4) * 2.0
            boxes.append([x, y, x + w, y + h])
            confidence.append(0.3 if frame_index > 3 and frame_index % 7 == 0 else 0.95)
            class_id.append(object_index % 4)
        frames.append(
            sv.Detections(
                xyxy=np.asarray(boxes, dtype=np.float64),
                confidence=np.asarray(confidence, dtype=np.float64),
                class_id=np.asarray(class_id, dtype=int),
            )
        )
    return frames


def run_tracker(tracker: Any, frames: Iterable[sv.Detections]) -> int:
    outputs = 0
    for detections in frames:
        outputs += len(tracker.update(detections))
    return outputs


def run_benchmark(
    name: str,
    tracker_factory: Any,
    frames: list[sv.Detections],
    repeats: int,
) -> dict[str, Any]:
    run_tracker(tracker_factory(), frames[:50])
    gc.collect()
    process = psutil.Process()
    rss_before = process.memory_info().rss
    elapsed_runs_ns = []
    outputs = 0
    for _ in range(repeats):
        start = time.perf_counter_ns()
        outputs = run_tracker(tracker_factory(), frames)
        elapsed_runs_ns.append(time.perf_counter_ns() - start)
    gc.collect()
    rss_after = process.memory_info().rss
    elapsed_runs_ns.sort()
    median_ns = elapsed_runs_ns[len(elapsed_runs_ns) // 2]
    p95_ns = elapsed_runs_ns[round((len(elapsed_runs_ns) - 1) * 0.95)]
    return {
        "tracker": name,
        "median_total_ms": median_ns / 1_000_000.0,
        "median_update_us": median_ns / 1000.0 / len(frames),
        "p95_update_us": p95_ns / 1000.0 / len(frames),
        "run_update_us": [elapsed_ns / 1000.0 / len(frames) for elapsed_ns in elapsed_runs_ns],
        "rss_before_bytes": rss_before,
        "rss_after_bytes": rss_after,
        "rss_delta_bytes": rss_after - rss_before,
        "output_rows": outputs,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--frames", type=int, default=500)
    parser.add_argument("--objects", type=int, default=20)
    parser.add_argument("--repeats", type=int, default=5)
    args = parser.parse_args()

    frames = make_frames(args.frames, args.objects)
    results = [
        run_benchmark("sort", lambda: SORTTracker(minimum_consecutive_frames=1), frames, args.repeats),
        run_benchmark(
            "bytetrack",
            lambda: ByteTrackTracker(
                minimum_consecutive_frames=1,
                track_activation_threshold=0.5,
                high_conf_det_threshold=0.6,
            ),
            frames,
            args.repeats,
        ),
        run_benchmark(
            "ocsort",
            lambda: OCSORTTracker(
                minimum_consecutive_frames=1,
                minimum_iou_threshold=0.1,
            ),
            frames,
            args.repeats,
        ),
        run_benchmark(
            "botsort",
            lambda: BoTSORTTracker(
                minimum_consecutive_frames=1,
                minimum_iou_threshold_first_assoc=0.1,
                minimum_iou_threshold_second_assoc=0.1,
                enable_cmc=False,
            ),
            frames,
            args.repeats,
        ),
        run_benchmark(
            "cbiou",
            lambda: CBIoUTracker(
                minimum_consecutive_frames=1,
                minimum_iou_threshold_first_assoc=0.1,
                minimum_iou_threshold_second_assoc=0.1,
            ),
            frames,
            args.repeats,
        ),
    ]
    print(
        json.dumps(
            {
                "runtime": "python",
                "frames": args.frames,
                "objects": args.objects,
                "repeats": args.repeats,
                "results": results,
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
