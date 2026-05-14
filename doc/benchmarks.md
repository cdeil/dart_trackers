# Benchmarks

Benchmarks are for regression tracking and directional comparison with the
Python reference. They are not the main reason to use this package; the primary
motivation is pure-Dart tracking in Flutter and Dart apps.

## Commands

Dart VM:

```bash
dart run tool/benchmark.dart --frames 500 --objects 10 --repeats 5
dart run tool/benchmark.dart --frames 500 --objects 100 --repeats 5
```

Dart AOT:

```bash
dart compile exe tool/benchmark.dart -o build/benchmark
./build/benchmark --frames 500 --objects 10 --repeats 5
./build/benchmark --frames 500 --objects 100 --repeats 5
```

Python reference:

```bash
cd conformance/python
uv run python benchmark_reference.py --frames 500 --objects 10 --repeats 5
uv run python benchmark_reference.py --frames 500 --objects 100 --repeats 5
```

## Methodology

The benchmark uses deterministic synthetic detections with configurable object
counts. It reports per-tracker timing for repeated runs and should be compared
using medians, not a single best run.

Run both 10-object and 100-object cases:

- 10 objects approximates small mobile scenes.
- 100 objects stresses assignment and matrix allocation behavior.

Dart VM is closest to development/debug workflows. Dart AOT is more relevant to
compiled mobile and desktop applications. Flutter release builds may still differ
because Flutter adds frame scheduling, platform views, detector cost, and UI
rendering.

RSS deltas are reported only as smoke indicators. They can be noisy, especially
on macOS and short runs.

## Current local numbers

Local median update time in microseconds per frame, 500 frames, 5 repeats:

| Runtime     | Objects |   SORT | ByteTrack | OC-SORT | BoT-SORT |
| ----------- | ------: | -----: | --------: | ------: | -------: |
| Dart VM     |      10 |   35.6 |      36.6 |    36.8 |     35.1 |
| Dart VM     |     100 |  881.6 |     890.0 |  1211.4 |    978.0 |
| Dart AOT    |      10 |   38.7 |      41.5 |    45.7 |     45.9 |
| Dart AOT    |     100 | 1041.1 |    1098.7 |  1265.1 |   1160.0 |
| Python 3.14 |      10 |  189.3 |     210.4 |   299.9 |    365.5 |
| Python 3.14 |     100 | 1818.8 |    1762.2 |  2459.3 |   3287.0 |

Treat these as directional. CI should eventually upload benchmark JSON artifacts
so changes can be compared over time on consistent runners.
