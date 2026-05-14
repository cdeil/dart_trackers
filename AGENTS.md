# AGENTS.md

`dart_trackers` is a pure-Dart clone of Roboflow `trackers` for Flutter and Dart
applications. The normal user API is `Detections` plus `SORTTracker`,
`ByteTrackTracker`, `OCSORTTracker`, or no-CMC `BoTSORTTracker`.

## Layout

- `lib/`: package source. Keep runtime dependencies at zero.
- `test/`: Dart tests that consume checked-in conformance fixtures.
- `conformance/python/`: Python 3.14 + uv oracle that regenerates fixtures from
    `trackers==2.4.0`.
- `conformance/fixtures/`: checked-in JSON fixtures.
- `doc/`: package docs, validation notes, benchmark notes, and demo plans.
- `tool/`: benchmark and reporting scripts.

## Commands

Run from the repository root unless noted:

```bash
dart pub get
dart format --output=none --set-exit-if-changed bin example lib test tool
dart analyze --fatal-infos --fatal-warnings
dart test
dart test -p chrome
dart pub publish --dry-run
dart run tool/benchmark.dart --frames 500 --objects 20 --repeats 5
dart compile exe tool/benchmark.dart -o build/benchmark
```

Regenerate fixtures and run Python tooling:

```bash
cd conformance/python
uv run python generate_fixtures.py
uv run ruff format --check .
uv run ruff check .
uv run ty check .
uv run python benchmark_reference.py --frames 500 --objects 20 --repeats 5
```

## Editing notes

- Do not add runtime Dart dependencies unless there is a measured need.
- Preserve Python fixture parity; if tracker semantics change, regenerate
    fixtures and update docs.
- `Matrix`, `KalmanFilter`, and assignment helpers are advanced support APIs; the
    normal public API should remain tracker-centric.
- BoT-SORT intentionally rejects `frame` input until CMC is implemented as a
    portable plugin boundary.
