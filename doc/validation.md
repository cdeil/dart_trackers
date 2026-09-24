# Validation and Python conformance

The checked-in fixtures are generated with Python 3.14 from Roboflow
`trackers` develop, pinned by git revision in `conformance/python/pyproject.toml`
(`[tool.uv.sources]`) and in `ORACLE_REVISION` in `generate_fixtures.py`, with
supervision, NumPy, and SciPy pinned alongside. `conformance/fixtures/manifest.json`
records the exact environment, including the oracle revision; the generator
refuses to run against a different trackers revision. `--check` compares the committed
fixtures with the oracle, allowing a relative float difference of `1e-12`
because libm functions such as `atan` can differ in the last bit between
platforms. To move the oracle, change
both pins, run `uv lock`, regenerate, and update these docs and the CHANGELOG. Dart consumes embedded copies of the same JSON
so the suite runs on the VM and in Chrome without `dart:io`.

## Commands

```bash
cd conformance/python
uv sync --frozen --group dev
uv run python generate_fixtures.py          # regenerate
uv run python generate_fixtures.py --check  # verify, as CI does
uv run ruff format --check .
uv run ruff check .
uv run pyright
uv run pyrefly check --output-format min-text --summarize-errors

cd ../..
dart format --output=none --set-exit-if-changed bin example lib test tool
dart analyze --fatal-infos --fatal-warnings
dart test
dart test -p chrome
dart pub publish --dry-run
```

All tracker fixtures run through one generator (`_run_tracker_cases`) and one
Dart harness (`test/conformance_harness.dart`). For every frame they record the
tracker IDs, the output rows mapped back to input indices, the confirmed tracked
objects with float64 boxes, and the number of warnings. Frames may carry a
`timestamp`, and params may name an IoU metric (`"iou": "giou"`).

Python-generated coverage:

- SciPy assignment, including ties, rectangular shapes in both directions,
  random small-integer matrices, forbidden edges, and invalid inputs.
- All five IoU metrics and their fusion normalization on integer, random
  non-integer, malformed (inverted), and wide-versus-tall boxes.
- SORT XYXY Kalman state.
- End-to-end SORT, ByteTrack, OC-SORT, BoT-SORT (no CMC), and C-BIoU: row order
  and IDs, missing confidence, activation and high/low thresholds, threshold
  equality, zero buffers, immature-track pruning, `minimumConsecutiveFrames: 0`,
  and IoU metric selection.
- Timestamps for every tracker except C-BIoU: bootstrap, gaps, duplicates,
  backwards timestamps, seconds-budget pruning before association, a
  millisecond-rounded clock, and switching back to fixed-rate mode.
- OC-SORT recovery (ORU) after two misses, with a shrinking box, a zero-width
  last observation, and a timestamp gap before the miss; OCR with GIoU;
  `deltaT: 0`; direction weight 0; and low-confidence rows (`trackerId == -1`,
  never associated).

Dart-only tests cover external CMC affine warping and the mask boxes passed to
the adapter, `Detections` value semantics, `Matrix.diagonal`, the process-noise
band and DWNA scaling, and OC-SORT observation pruning.

## Precision differences

Dart computes in float64 throughout. Upstream is mixed precision:

- IoU and BIoU come from `supervision.box_iou_batch` as float32, while GIoU,
  DIoU, and CIoU are float64. BoT-SORT score fusion and the OC-SORT direction
  matrix are float32 as well. Dart values therefore agree to about `3e-8`, and
  a pair whose similarity lies within float32 rounding of a threshold, or two
  nearly tied assignment costs, can resolve differently. Fixtures keep clear of
  those boundaries.
- `tracked_objects` is float32 upstream; the fixtures record float64 boxes from
  each tracklet instead.
- Python compares detector scores in the caller's dtype (usually float32);
  Dart compares float64.
- Kalman algebra uses Gauss-Jordan inversion and plain loops rather than
  LAPACK/BLAS, so state agrees to tolerance, not bit for bit.
- dtype-only upstream fixes (for example the float32 `xcycsr_to_xyxy` paths in
  2.6.1) do not apply to the float64 Dart port.

Tracker IDs compare exactly only in non-ambiguous scenes. General floats use
`1e-7` tolerance and Kalman state uses `1e-9` absolute / `1e-7` relative
tolerance. Equal-cost assignment scenes can have multiple mathematically valid
ID streams and need partition-based comparison rather than numeric ID equality.

McByte is the one upstream tracker outside Dart scope. Its mask association
requires Torch and SAM/Cutie GPU-capable runtimes. The Dart core remains a
zero-runtime-dependency box tracker; segmentation stays in the app's chosen
on-device inference runtime.
