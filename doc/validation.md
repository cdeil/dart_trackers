# Validation and Python conformance

The Dart package is validated against Roboflow's Python
[`trackers`](https://trackers.roboflow.com/latest/) package using checked-in JSON
fixtures.

The workflow is:

1. Python 3.14 + uv runs the locked Python reference.
2. The reference writes JSON fixtures under `conformance/fixtures`.
3. The generator also writes `test/fixtures.g.dart` so VM and browser tests use
    the same fixture data without `dart:io`.
4. Dart tests consume the fixtures and compare tracker IDs, output row order, IoU,
    assignment, and Kalman state.

## Regenerate fixtures

```bash
cd conformance/python
uv run python generate_fixtures.py
```

The Python environment is pinned in `pyproject.toml`, `.python-version`, and
`uv.lock`. Do not use ambient `python3` for fixture generation.

## Run validation

```bash
dart analyze --fatal-infos --fatal-warnings
dart test
dart test -p chrome

cd conformance/python
uv run ruff format --check .
uv run ruff check .
uv run ty check .
```

`ty` is included because it is the modern Astral type checker, but it is still
young. CI can keep Ruff as the hard Python gate and run `ty` as an advisory check
until it stabilizes.

## Current fixture coverage

- SciPy `linear_sum_assignment` cases.
- `supervision.box_iou_batch` IoU matrix.
- SORT Kalman state sequence.
- SORT end-to-end tracker ID cases.
- ByteTrack tracker IDs and output-row order.
- OC-SORT tracker IDs and output-row order.
- BoT-SORT no-CMC tracker IDs and output-row order.

## Known semantic notes

- ByteTrack in locked `trackers==2.4.0` treats absent confidence as zeros. Dart
    mirrors that oracle even though `Detections.confidenceAt()` defaults to `1.0`.
- BoT-SORT CMC is intentionally not implemented in Dart yet.
- Assignment tie-breaking can produce different but equally valid ID streams in
    ambiguous scenes. Fixtures avoid ambiguous ties until an ID-invariant
    comparison is added.

## Web conformance

The Dart tests avoid `dart:io` by using generated fixture strings. This allows:

```bash
dart test -p chrome
```

This validates browser JavaScript execution. Flutter web builds use a Flutter
toolchain and may use different compilation modes, so a small Flutter integration
example should still be added before claiming full Flutter-web production
coverage.
