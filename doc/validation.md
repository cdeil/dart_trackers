# Validation and Python conformance

The checked-in fixtures are generated with Python 3.14, `trackers==2.6.0`,
`supervision==0.29.0`, NumPy, and SciPy. `conformance/fixtures/manifest.json`
records the exact environment. Dart consumes embedded copies of the same JSON
so the suite runs on the VM and in Chrome without `dart:io`.

## Commands

```bash
cd conformance/python
uv sync --frozen --group dev
uv run python generate_fixtures.py
uv run ruff format --check .
uv run ruff check .
uv run ty check .

cd ../..
dart format --output=none --set-exit-if-changed bin example lib test tool
dart analyze --fatal-infos --fatal-warnings
dart test
dart test -p chrome
dart pub publish --dry-run
```

Coverage includes SciPy assignment, all five IoU metrics, SORT Kalman state,
end-to-end SORT/ByteTrack/OC-SORT/BoT-SORT/C-BIoU row order and IDs, missing
confidence, unmatched rows, timestamp gaps, backwards/duplicate timestamps,
zero-buffer lifecycle edges, confirmed missed tracks, and external CMC affine
warping.

The OC-SORT fixture generator deliberately augments the stable 2.6 result with
the low-confidence rows described in the next develop changelog entry. Those
rows are returned with `trackerId == -1`; no new track is spawned from them.

Tracker IDs compare exactly only in non-ambiguous scenes. General floats use
`1e-7` tolerance and Kalman state uses `1e-9` absolute / `1e-7` relative
tolerance. Equal-cost assignment scenes can have multiple mathematically valid
ID streams and need partition-based comparison rather than numeric ID equality.

McByte is the one upstream tracker outside Dart scope. Its mask association
requires Torch and SAM/Cutie GPU-capable runtimes. The Dart core remains a
zero-runtime-dependency box tracker; segmentation stays in the app's chosen
on-device inference runtime.
