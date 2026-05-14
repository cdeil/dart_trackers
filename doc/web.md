# Web support

`dart_trackers` has no runtime dependencies and uses only Dart core libraries in
`lib/`, so the tracking core is suitable for browser compilation.

## What CI validates

```bash
dart test -p chrome
dart compile js example/dart_trackers_example.dart -o build/example.js
```

`dart test -p chrome` compiles and runs the conformance tests in Chrome. The
tests use generated Dart fixture strings instead of `dart:io`, so the same
Python oracle data is exercised on VM and browser JavaScript.

`dart compile js` is a compile smoke test for an example entrypoint.

## Dart web vs Flutter web

Pure Dart web tests currently compile to JavaScript. Flutter web is a larger
stack and may use different compilation modes, including Wasm-related modes as
Flutter evolves. The package should therefore claim core Dart browser
conformance first, then add a separate Flutter example app test before making
stronger Flutter-web statements.

## Numeric caveats

Dart VM and AOT use `double` semantics directly. Browser builds run on JavaScript
numbers, so floating-point operation ordering and integer representation can
vary slightly. Current conformance policy is:

- exact tracker IDs for non-ambiguous fixtures;
- general float comparisons at `atol=1e-7`, `rtol=1e-7`;
- tighter Kalman state checks on VM/AOT where appropriate.
